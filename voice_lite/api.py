"""CPU-only Kokoro ONNX lite service. Only reachable within NOVA's Docker network."""
from __future__ import annotations

from contextlib import asynccontextmanager
from io import BytesIO
import os
from pathlib import Path
from threading import Lock

from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, Field

MODEL = Path(os.environ.get("NOVA_VOICE_MODEL", "/models/kokoro-v1.0.int8.onnx"))
VOICES = Path(os.environ.get("NOVA_VOICE_VECTORS", "/models/voices-v1.0.bin"))
VOICE_NAME = "pf_dora"
_ENGINE = None
_G2P = None
_LOCK = Lock()


def load_models() -> None:
    global _ENGINE, _G2P
    if not (MODEL.is_file() and VOICES.is_file()):
        raise RuntimeError("Kokoro model assets missing")
    from kokoro_onnx import Kokoro
    from misaki.espeak import EspeakG2P
    _G2P = EspeakG2P(language="pt-br")
    _ENGINE = Kokoro(str(MODEL), str(VOICES))


@asynccontextmanager
async def lifespan(_: FastAPI):
    load_models()
    yield


app = FastAPI(title="NOVA voice lite internal", docs_url=None, redoc_url=None, lifespan=lifespan)


class SpeechRequest(BaseModel):
    model: str = Field(pattern=r"^kokoro$")
    input: str = Field(min_length=1, max_length=700)
    voice: str = Field(pattern=r"^pf_dora$")
    response_format: str = Field(pattern=r"^wav$")
    speed: float = Field(default=1.0, ge=0.85, le=1.15)


@app.get("/health")
def health():
    if _ENGINE is None or _G2P is None:
        raise HTTPException(503, "Models not ready")
    return {"status": "healthy", "engine": "onnx-cpu", "voice": VOICE_NAME}


def synthesize(script: str, speed: float) -> bytes:
    import soundfile as sf
    if _ENGINE is None or _G2P is None:
        raise RuntimeError("Kokoro not initialized")
    phonemes, _ = _G2P(script)
    if not phonemes:
        raise ValueError("Roteiro não produziu fonemas válidos")
    samples, sample_rate = _ENGINE.create(phonemes, VOICE_NAME, is_phonemes=True, speed=speed)
    with BytesIO() as output:
        sf.write(output, samples, sample_rate, format="WAV", subtype="PCM_16")
        data = output.getvalue()
    if not 128 <= len(data) <= 15 * 1024 * 1024:
        raise ValueError("O arquivo WAV gerado ultrapassa o limite")
    return data


@app.post("/v1/audio/speech")
def audio_speech(body: SpeechRequest):
    if not body.input.strip():
        raise HTTPException(422, "Roteiro vazio")
    if not _LOCK.acquire(blocking=False):
        raise HTTPException(429, "O motor está ocupado; tente novamente")
    try:
        wav = synthesize(body.input, body.speed)
    except (RuntimeError, ValueError):
        raise HTTPException(503, "Motor de voz indisponível ou narração inválida")
    finally:
        _LOCK.release()
    return Response(wav, media_type="audio/wav",
                    headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"})
