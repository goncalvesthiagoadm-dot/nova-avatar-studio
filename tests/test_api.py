"""Testes de segurança, API e renderização de vídeo real em ambiente local."""
import io
import os
from pathlib import Path
import shutil
import subprocess
import time

from fastapi.testclient import TestClient
import pytest

from studio import app as module


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(module, "DATA", tmp_path)
    monkeypatch.setattr(module, "ASSETS", tmp_path / "assets")
    monkeypatch.setattr(module, "OUTPUTS", tmp_path / "output")
    monkeypatch.setattr(module, "DB", tmp_path / "studio.sqlite")
    monkeypatch.delenv("STUDIO_API_TOKEN", raising=False)
    monkeypatch.delenv("MUSETALK_DIR", raising=False)
    with TestClient(module.app) as c:
        yield c


def make_mp4_and_wav(tmp_path):
    if not shutil.which("ffmpeg"):
        pytest.skip("ffmpeg não encontrado")
    vid = tmp_path / "source.mp4"
    wav = tmp_path / "voice.wav"
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "color=c=navy:s=320x240:r=25:d=1.1", "-c:v", "libx264", "-pix_fmt", "yuv420p", str(vid)], check=True, timeout=25)
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=320:duration=1", str(wav)], check=True, timeout=25)
    return vid, wav


def test_health_no_hermes(client):
    r = client.get("/api/v1/health")
    assert r.status_code == 200
    assert r.json()["product"] == "nova-studio"
    assert r.json()["engines"][0]["id"] == "audio-replace"
    assert client.get("/").status_code == 200
    assert "NOVA" in client.get("/").text
    assert client.get("/static/studio.js").status_code == 200
    assert client.get("/static/../../.env").status_code == 404


def test_api_auth(client, monkeypatch):
    monkeypatch.setenv("STUDIO_API_TOKEN", "long-private-token-test")
    assert client.get("/api/v1/health").status_code == 401
    assert client.get("/api/v1/health", headers={"x-api-key": "no"}).status_code == 401
    assert client.get("/api/v1/health", headers={"x-api-key": "long-private-token-test"}).status_code == 200


def test_projects_and_constraints(client):
    assert client.post("/api/v1/projects", json={"name": ""}).status_code == 422
    r = client.post("/api/v1/projects", json={"name": "Apresentação", "script": "Olá"})
    assert r.status_code == 201
    pid = r.json()["id"]
    assert client.get(f"/api/v1/projects/{pid}").json()["name"] == "Apresentação"
    assert client.patch(f"/api/v1/projects/{pid}", json={"script": "Texto novo"}).json()["script"] == "Texto novo"
    assert client.post(f"/api/v1/projects/{pid}/render", json={"engine": "unknown"}).status_code == 400
    assert client.post(f"/api/v1/projects/{pid}/render", json={"engine": "audio-replace"}).status_code == 422
    assert client.post(f"/api/v1/projects/{pid}/assets/video", files={"file": ("evil.exe", b"script", "application/octet-stream")}).status_code == 415
    assert client.get("/api/v1/projects/none").status_code == 404


def test_real_ffmpeg_end_to_end(client, tmp_path):
    vid, wav = make_mp4_and_wav(tmp_path)
    p = client.post("/api/v1/projects", json={"name": "Teste real", "script": "Teste"}).json()
    for kind, f, mime in [("video", vid, "video/mp4"), ("audio", wav, "audio/wav")]:
        with f.open("rb") as handle:
            r = client.post(f"/api/v1/projects/{p['id']}/assets/{kind}", files={"file": (f.name, handle, mime)})
        assert r.status_code == 200, r.text
    r = client.post(f"/api/v1/projects/{p['id']}/render", json={"engine": "audio-replace"})
    assert r.status_code == 202, r.text
    jid = r.json()["job_id"]
    deadline = time.monotonic() + 28
    while time.monotonic() < deadline:
        status = client.get(f"/api/v1/jobs/{jid}").json()
        if status["status"] not in {"queued", "running"}:
            break
        time.sleep(.25)
    assert status["status"] == "done", status
    data = client.get(f"/api/v1/jobs/{jid}/download")
    assert data.status_code == 200
    assert data.content[:16].find(b"ftyp") != -1
    assert len(data.content) > 1000
    # O segredo interno (path real do disco) nunca sai no JSON de status.
    assert "path" not in status


def test_invalid_media_is_rejected_and_removed(client):
    p = client.post("/api/v1/projects", json={"name": "X"}).json()
    r = client.post(f"/api/v1/projects/{p['id']}/assets/video", files={"file": ("fake.mp4", io.BytesIO(b"not-video"), "video/mp4")})
    assert r.status_code == 415
    assert not list(module.ASSETS.glob("*.mp4"))


def test_public_deployment_refuses_empty_or_weak_auth(tmp_path, monkeypatch):
    monkeypatch.setattr(module, "DATA", tmp_path)
    monkeypatch.setattr(module, "ASSETS", tmp_path / "assets")
    monkeypatch.setattr(module, "OUTPUTS", tmp_path / "output")
    monkeypatch.setattr(module, "DB", tmp_path / "studio.sqlite")
    monkeypatch.setenv("STUDIO_PUBLIC_DEPLOYMENT", "1")
    monkeypatch.delenv("STUDIO_API_TOKEN", raising=False)
    with pytest.raises(RuntimeError, match="STUDIO_API_TOKEN"):
        with TestClient(module.app):
            pass
    monkeypatch.setenv("STUDIO_API_TOKEN", "short")
    with pytest.raises(RuntimeError, match="STUDIO_API_TOKEN"):
        with TestClient(module.app):
            pass
    monkeypatch.setenv("STUDIO_API_TOKEN", "more-than-twenty-four-characters-unique")
    with TestClient(module.app) as c:
        assert c.get("/live").status_code == 200
        assert c.get("/").status_code == 200
        assert c.get("/api/v1/projects").status_code == 401
        assert c.get("/api/v1/projects", headers={"x-api-key": os.environ["STUDIO_API_TOKEN"]}).status_code == 200


def test_never_expose_server_asset_path(client, tmp_path):
    project_response = client.post("/api/v1/projects", json={"name": "Privado"})
    pid = project_response.json()["id"]
    v, a = make_mp4_and_wav(tmp_path)
    for kind, file, mime in (("video", v, "video/mp4"), ("audio", a, "audio/wav")):
        with file.open("rb") as f:
            assert client.post(f"/api/v1/projects/{pid}/assets/{kind}", files={"file": (file.name, f, mime)}).status_code == 200
    detail = client.get(f"/api/v1/projects/{pid}").json()
    assert detail["video"] is True and detail["audio"] is True
    assert str(tmp_path) not in str(detail)
    assert str(tmp_path) not in client.get("/api/v1/projects").text
    assert str(tmp_path) not in str(project_response.json())
    assert client.get("/live").json() == {"ok": True, "service": "nova-studio"}
    assert "default-src 'none'" in client.get("/").headers["content-security-policy"]
