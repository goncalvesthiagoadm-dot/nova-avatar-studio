"""NOVA Studio: API standalone e estúdio web. Sem integração com Hermes."""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from datetime import datetime, timezone
import os
from pathlib import Path
import secrets
import sqlite3
import uuid

from fastapi import FastAPI, File, Header, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
from pydantic import BaseModel, Field

from .engines import engine_catalog, probe_media, render_audio_replace, render_musetalk
from .voices import VoiceUnavailable, generate_kokoro_audio, kokoro_status

BASE = Path(__file__).resolve().parent
DATA = Path(os.environ.get("STUDIO_DATA_DIR", str(BASE.parent / "storage"))).resolve()
ASSETS = DATA / "assets"
OUTPUTS = DATA / "output"
DB = DATA / "studio.sqlite"
POOL = ThreadPoolExecutor(max_workers=1, thread_name_prefix="nova-render")


def now():
    return datetime.now(timezone.utc).isoformat()


def conn():
    cx = sqlite3.connect(str(DB), timeout=15)
    cx.row_factory = sqlite3.Row
    return cx


def init_db():
    ASSETS.mkdir(parents=True, exist_ok=True)
    OUTPUTS.mkdir(parents=True, exist_ok=True)
    with conn() as cx:
        cx.executescript("""
          CREATE TABLE IF NOT EXISTS projects (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, script TEXT NOT NULL,
            video TEXT, audio TEXT, created_at TEXT NOT NULL
          );
          CREATE TABLE IF NOT EXISTS jobs (
            id TEXT PRIMARY KEY, project_id TEXT NOT NULL, engine TEXT NOT NULL,
            status TEXT NOT NULL, error TEXT, path TEXT, created_at TEXT NOT NULL,
            finished_at TEXT, FOREIGN KEY(project_id) REFERENCES projects(id)
          );
        """)
        cx.execute("UPDATE jobs SET status='interrupted', error='Serviço reiniciado durante processamento' WHERE status IN ('running','queued')")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # Fail closed when running on a publicly accessible host.
    if os.environ.get("STUDIO_PUBLIC_DEPLOYMENT") == "1" and len(os.environ.get("STUDIO_API_TOKEN", "").strip()) < 24:
        raise RuntimeError("A publicação requer STUDIO_API_TOKEN forte (24+ caracteres)")
    init_db()
    yield


app = FastAPI(title="NOVA Avatar Studio", version="0.2.0", lifespan=lifespan,
              docs_url="/api/docs", redoc_url=None)


@app.middleware("http")
async def auth_and_security(req: Request, call_next):
    token = os.environ.get("STUDIO_API_TOKEN", "").strip()
    if token and (req.url.path.startswith("/api/v1/") or req.url.path.startswith("/api/docs")):
        provided = req.headers.get("x-api-key", "")
        if not secrets.compare_digest(provided, token):
            return JSONResponse({"detail": "Chave de API inválida"}, status_code=401)
    response = await call_next(req)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Cache-Control"] = "no-store"
    response.headers["Content-Security-Policy"] = (
        "default-src 'none'; script-src 'self'; style-src 'self'; "
        "img-src 'self' data: blob:; media-src 'self' blob:; "
        "connect-src 'self'; font-src 'self'; form-action 'self'; "
        "base-uri 'self'; frame-ancestors 'none'"
    )
    return response


class NewProject(BaseModel):
    name: str = Field(min_length=1, max_length=70)
    script: str = Field(default="", max_length=4000)


class UpdateScript(BaseModel):
    script: str = Field(max_length=4000)


class RenderRequest(BaseModel):
    engine: str = Field(default="audio-replace")


def project(pid: str) -> dict:
    with conn() as cx:
        row = cx.execute("SELECT * FROM projects WHERE id=?", (pid,)).fetchone()
    if row is None:
        raise HTTPException(404, "Projeto não encontrado")
    return dict(row)


def public_project(row: dict) -> dict:
    # The browser only needs asset presence, never server file paths.
    return {"id": row["id"], "name": row["name"], "script": row["script"],
            "video": bool(row["video"]), "audio": bool(row["audio"]),
            "created_at": row["created_at"]}


def job(jid: str) -> dict:
    with conn() as cx:
        row = cx.execute("SELECT * FROM jobs WHERE id=?", (jid,)).fetchone()
    if row is None:
        raise HTTPException(404, "Renderização não encontrada")
    return dict(row)


@app.get("/", response_class=HTMLResponse, include_in_schema=False)
def homepage():
    return (BASE / "static" / "index.html").read_text(encoding="utf-8")


@app.get("/static/{file_name}", include_in_schema=False)
def static_file(file_name: str):
    if file_name not in {"studio.css", "studio.js"}:
        raise HTTPException(404)
    return FileResponse(BASE / "static" / file_name)


@app.get("/live", include_in_schema=False)
def live():
    """No private content: used by hosting HTTP health check."""
    return {"ok": True, "service": "nova-studio"}


@app.get("/api/v1/health")
def health():
    return {"ok": True, "product": "nova-studio", "version": "0.3.0",
            "engines": engine_catalog(), "voices": [kokoro_status()]}


@app.get("/api/v1/projects")
def list_projects():
    with conn() as cx:
        return [public_project(dict(r)) for r in cx.execute("SELECT * FROM projects ORDER BY created_at DESC LIMIT 100")]


@app.post("/api/v1/projects", status_code=201)
def create_project(body: NewProject):
    pid = uuid.uuid4().hex
    with conn() as cx:
        cx.execute("INSERT INTO projects (id,name,script,created_at) VALUES(?,?,?,?)",
                   (pid, body.name.strip(), body.script, now()))
    return public_project(project(pid))


@app.patch("/api/v1/projects/{pid}")
def update_project(pid: str, body: UpdateScript):
    project(pid)
    with conn() as cx:
        cx.execute("UPDATE projects SET script=? WHERE id=?", (body.script, pid))
    return public_project(project(pid))


@app.get("/api/v1/projects/{pid}")
def get_project(pid: str):
    return public_project(project(pid))


@app.post("/api/v1/projects/{pid}/assets/{kind}")
async def upload_asset(pid: str, kind: str, file: UploadFile = File(...)):
    if kind not in {"video", "audio"}:
        raise HTTPException(400, "Tipo permitido: video ou audio")
    project(pid)
    ext = Path(file.filename or "").suffix.lower()
    allowed = {"video": {".mp4", ".mov", ".webm"},
               "audio": {".wav", ".mp3", ".m4a", ".aac"}}[kind]
    if ext not in allowed:
        raise HTTPException(415, "Formato de arquivo não aceito")
    limit = 60 * 1024 * 1024 if kind == "video" else 15 * 1024 * 1024
    location = ASSETS / f"{pid}-{kind}-{uuid.uuid4().hex[:8]}{ext}"
    written = 0
    try:
        with location.open("wb") as out:
            while chunk := await file.read(1024 * 1024):
                written += len(chunk)
                if written > limit:
                    raise HTTPException(413, "Arquivo acima do limite")
                out.write(chunk)
        info = probe_media(location)
        if not info["has_video" if kind == "video" else "has_audio"]:
            raise HTTPException(415, "Arquivo não contém faixa compatível")
    except (ValueError, RuntimeError) as exc:
        location.unlink(missing_ok=True)
        raise HTTPException(415, str(exc)) from exc
    except Exception:
        location.unlink(missing_ok=True)
        raise
    await file.close()
    with conn() as cx:
        old_row = cx.execute(f"SELECT {kind} FROM projects WHERE id=?", (pid,)).fetchone()
        old = old_row[0] if old_row else None
        cx.execute(f"UPDATE projects SET {kind}=? WHERE id=?", (str(location), pid))
    if old:
        candidate = Path(old)
        if candidate.parent == ASSETS:
            candidate.unlink(missing_ok=True)
    return {"ok": True, "kind": kind, "name": file.filename, "size": written, **info}


@app.post("/api/v1/projects/{pid}/narration")
def create_narration(pid: str):
    """Generate an actual WAV from the saved script using local, optional Kokoro."""
    p = project(pid)
    script = p["script"].strip()
    if not script or len(script) > 700:
        raise HTTPException(422, "Salve um roteiro de 1 a 700 caracteres antes de gerar a voz")
    if not kokoro_status()["available"]:
        raise HTTPException(409, "Kokoro indisponível: configure e inicie o serviço local de voz")
    target = ASSETS / f"{pid}-audio-kokoro-{uuid.uuid4().hex[:8]}.wav"
    try:
        generate_kokoro_audio(script, target)
        media = probe_media(target)
        if not media["has_audio"]:
            raise ValueError("Kokoro não gerou uma faixa de áudio")
    except (ValueError, RuntimeError, VoiceUnavailable) as exc:
        target.unlink(missing_ok=True)
        raise HTTPException(502, str(exc)) from exc
    with conn() as cx:
        cx.execute("UPDATE projects SET audio=? WHERE id=?", (str(target), pid))
    old = p["audio"]
    if old:
        old_path = Path(old)
        if old_path.parent == ASSETS and old_path != target:
            old_path.unlink(missing_ok=True)
    return {"ok": True, "voice": "pf_dora", "duration": media["duration"], "kind": "neural_tts"}


@app.get("/api/v1/projects/{pid}/audio")
def preview_project_audio(pid: str):
    p = project(pid)
    if not p["audio"]:
        raise HTTPException(404, "Projeto sem áudio")
    f = Path(p["audio"])
    if f.resolve().parent != ASSETS.resolve() or not f.is_file():
        raise HTTPException(404, "Áudio do projeto não encontrado")
    media_type = {
        ".wav": "audio/wav", ".mp3": "audio/mpeg",
        ".aac": "audio/aac", ".m4a": "audio/mp4",
    }.get(f.suffix.lower(), "application/octet-stream")
    return FileResponse(f, media_type=media_type, filename="nova-voz" + f.suffix)


def process(jid: str, pid: str, engine: str, video: str, audio: str):
    target = OUTPUTS / f"{jid}.mp4"
    work = OUTPUTS / jid
    work.mkdir(parents=True, exist_ok=True)
    try:
        with conn() as cx:
            cx.execute("UPDATE jobs SET status='running' WHERE id=?", (jid,))
        if engine == "audio-replace":
            render_audio_replace(Path(video), Path(audio), target)
        elif engine == "musetalk-1.5":
            render_musetalk(Path(video), Path(audio), target, work)
        else:
            raise ValueError("Motor inexistente")
        with conn() as cx:
            cx.execute("UPDATE jobs SET status='done', path=?, finished_at=? WHERE id=?",
                       (str(target), now(), jid))
    except Exception as exc:
        target.unlink(missing_ok=True)
        with conn() as cx:
            cx.execute("UPDATE jobs SET status='error', error=?, finished_at=? WHERE id=?",
                       (str(exc)[:260], now(), jid))


@app.post("/api/v1/projects/{pid}/render", status_code=202)
def render(pid: str, body: RenderRequest):
    p = project(pid)
    engines = {e["id"]: e for e in engine_catalog()}
    if body.engine not in engines:
        raise HTTPException(400, "Motor desconhecido")
    if not engines[body.engine]["available"]:
        raise HTTPException(409, "Motor indisponível; verifique /api/v1/health")
    if not p["video"] or not p["audio"]:
        raise HTTPException(422, "Envie um vídeo-base e um áudio")
    # Uma renderização por vez para não sobrecarregar máquinas de uso pessoal.
    with conn() as cx:
        busy = cx.execute("SELECT COUNT(*) FROM jobs WHERE status IN ('queued','running')").fetchone()[0]
        if busy >= 2:
            raise HTTPException(429, "Fila cheia; tente novamente após concluir uma renderização")
        jid = uuid.uuid4().hex
        cx.execute("INSERT INTO jobs (id,project_id,engine,status,created_at) VALUES(?,?,?,?,?)",
                   (jid, pid, body.engine, "queued", now()))
    POOL.submit(process, jid, pid, body.engine, p["video"], p["audio"])
    return {"job_id": jid, "status": "queued", "status_url": f"/api/v1/jobs/{jid}"}


@app.get("/api/v1/jobs/{jid}")
def get_job(jid: str):
    j = job(jid)
    j.pop("path", None)
    if j["status"] == "done":
        j["download_url"] = f"/api/v1/jobs/{jid}/download"
    return j


@app.get("/api/v1/jobs/{jid}/download")
def download(jid: str):
    j = job(jid)
    if j["status"] != "done" or not j["path"]:
        raise HTTPException(409, "Vídeo ainda não disponível")
    f = Path(j["path"])
    if f.parent != OUTPUTS or not f.is_file():
        raise HTTPException(404, "Arquivo de saída não encontrado")
    return FileResponse(f, media_type="video/mp4", filename=f"nova-studio-{jid[:8]}.mp4")
