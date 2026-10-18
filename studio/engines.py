"""Adaptadores explícitos: a primeira opção NÃO gera lip sync; a segunda usa MuseTalk real."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import yaml


class EngineUnavailable(RuntimeError):
    pass


def have_ffmpeg() -> bool:
    return bool(shutil.which("ffmpeg") and shutil.which("ffprobe"))


def musetalk_root() -> Path | None:
    raw = os.environ.get("MUSETALK_DIR", "").strip()
    return Path(raw).resolve() if raw else None


def musetalk_status() -> dict:
    root = musetalk_root()
    has_repo = bool(root and (root / "scripts" / "inference.py").is_file())
    has_weights = bool(root and (root / "models" / "musetalkV15" / "unet.pth").is_file()
                       and (root / "models" / "musetalkV15" / "musetalk.json").is_file())
    gpu = shutil.which("nvidia-smi") is not None
    return {
        "id": "musetalk-1.5", "name": "MuseTalk 1.5 • sincronia real",
        "available": has_repo and has_weights and have_ffmpeg() and gpu,
        "repo_installed": has_repo, "weights_installed": has_weights,
        "gpu_detected": gpu, "ffmpeg": have_ffmpeg(),
        "kind": "ai_lipsync", "requires": "GPU NVIDIA e pesos oficiais instalados",
    }


def engine_catalog() -> list[dict]:
    return [
        {
            "id": "audio-replace", "name": "Teste técnico • trocar áudio",
            "available": have_ffmpeg(), "kind": "video_edit",
            "warning": "NÃO sincroniza os lábios. Mantém movimentos do vídeo-base.",
        },
        musetalk_status(),
    ]


def probe_media(path: Path) -> dict:
    if not have_ffmpeg():
        raise EngineUnavailable("Instale ffmpeg e ffprobe.")
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_format", "-show_streams", "-of", "json", str(path)],
        capture_output=True, text=True, timeout=25, check=False,
    )
    if result.returncode != 0:
        raise ValueError("Arquivo de mídia inválido ou não suportado")
    try:
        payload = json.loads(result.stdout)
        seconds = float(payload["format"].get("duration") or 0)
    except (ValueError, TypeError, KeyError) as exc:
        raise ValueError("Arquivo sem duração detectável") from exc
    if seconds < .15 or seconds > 60:
        raise ValueError("O arquivo deve ter duração entre 0,15 e 60 segundos")
    streams = payload.get("streams", [])
    video = next((s for s in streams if s.get("codec_type") == "video"), None)
    if video:
        if int(video.get("width") or 0) > 3840 or int(video.get("height") or 0) > 2160:
            raise ValueError("Vídeo acima de 3840 × 2160 não é aceito")
    return {"duration": round(seconds, 2), "has_video": bool(video),
            "has_audio": any(s.get("codec_type") == "audio" for s in streams)}


def render_audio_replace(video: Path, audio: Path, target: Path) -> None:
    if not have_ffmpeg():
        raise EngineUnavailable("FFmpeg indisponível")
    cmd = ["ffmpeg", "-y", "-nostdin", "-hide_banner", "-loglevel", "error", "-i", str(video),
           "-i", str(audio), "-map", "0:v:0", "-map", "1:a:0", "-vf",
           "fps=25,scale=w='min(1280,iw)':h=-2", "-c:v", "libx264", "-preset", "veryfast",
           "-crf", "21", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k",
           "-shortest", "-t", "60", "-movflags", "+faststart", str(target)]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=220, check=False)
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("Processamento FFmpeg excedeu o limite") from exc
    if out.returncode or not target.is_file() or target.stat().st_size < 1024:
        raise RuntimeError("Falha ao combinar vídeo e áudio (FFmpeg)")


def render_musetalk(video: Path, audio: Path, target: Path, work_dir: Path) -> None:
    """Executa, sem baixar nada automaticamente, os scripts oficiais MuseTalk v1.5.

    A interface test.yaml oficial mapeia task_0 -> video_path, audio_path.
    Requer ambiente GPU/modelos previamente instalados pelo operador.
    """
    if not musetalk_status()["available"]:
        raise EngineUnavailable("MuseTalk não configurado. Instale o projeto, pesos e CUDA em uma GPU NVIDIA.")
    root = musetalk_root()
    assert root is not None
    config_path = work_dir / "musetalk.yaml"
    config_path.write_text(yaml.safe_dump({"task_0": {
        "video_path": str(video), "audio_path": str(audio), "bbox_shift": 0,
    }}), encoding="utf-8")
    results = work_dir / "results"
    results.mkdir(exist_ok=True)
    cmd = [os.environ.get("MUSETALK_PYTHON", sys.executable), "-m", "scripts.inference",
           "--inference_config", str(config_path), "--result_dir", str(results),
           "--unet_model_path", "models/musetalkV15/unet.pth",
           "--unet_config", "models/musetalkV15/musetalk.json", "--version", "v15"]
    try:
        run = subprocess.run(cmd, cwd=root, capture_output=True, text=True, timeout=1800, check=False)
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("MuseTalk excedeu o limite de 30 minutos") from exc
    if run.returncode:
        raise RuntimeError("MuseTalk não concluiu a inferência; consulte a configuração do motor")
    mp4s = sorted(results.rglob("*.mp4"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not mp4s:
        raise RuntimeError("MuseTalk não gerou arquivo MP4")
    shutil.copyfile(mp4s[0], target)
    if target.stat().st_size < 1024:
        raise RuntimeError("MuseTalk gerou um arquivo inválido")
