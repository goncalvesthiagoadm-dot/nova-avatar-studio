"""Optional self-hosted Brazilian Portuguese narration.

Only connects to a deliberately configured local/Compose service. No paid APIs,
external TTS endpoints, auto-downloads, or access to Hermes services.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class VoiceUnavailable(RuntimeError):
    pass


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise VoiceUnavailable("O servidor de voz redirecionou a conexão; conexão recusada")


def _endpoint() -> str | None:
    """Restrict scripts to a loopback or the dedicated NOVA Compose hostname."""
    raw = os.environ.get("NOVA_KOKORO_URL", "").strip().rstrip("/")
    if not raw:
        return None
    try:
        parts = urlsplit(raw)
        valid_port = parts.port is not None and 1 <= parts.port <= 65535
    except ValueError:
        return None
    if (parts.scheme != "http" or parts.hostname not in
            {"127.0.0.1", "localhost", "kokoro-tts"} or
            parts.path or parts.query or parts.fragment or parts.username or parts.password or
            not valid_port):
        return None
    return raw


def kokoro_status() -> dict:
    status = {
        "id": "kokoro-ptbr", "name": "Kokoro • voz feminina pt-BR",
        "voice": "pf_dora", "available": False, "kind": "neural_tts",
        "requires": "Serviço Kokoro local e isolado configurado",
    }
    endpoint = _endpoint()
    if not endpoint:
        return status
    try:
        with build_opener(_NoRedirect()).open(
            Request(endpoint + "/health", method="GET"), timeout=2,
        ) as response:
            status["available"] = 200 <= response.status < 300
    except (OSError, URLError, HTTPError, VoiceUnavailable):
        pass
    return status


def generate_kokoro_audio(script: str, target: Path) -> None:
    endpoint = _endpoint()
    if not endpoint:
        raise VoiceUnavailable("Kokoro local não configurado")
    if not (1 <= len(script.strip()) <= 700):
        raise ValueError("Roteiro para narração deve ter de 1 a 700 caracteres")
    req = Request(
        endpoint + "/v1/audio/speech",
        data=json.dumps({
            "model": "kokoro", "input": script, "voice": "pf_dora",
            "response_format": "wav", "speed": 1.0,
        }, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json", "Accept": "audio/wav"},
        method="POST",
    )
    token = os.environ.get("NOVA_KOKORO_API_KEY", "").strip()
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with build_opener(_NoRedirect()).open(req, timeout=120) as response:
            if "audio/" not in response.headers.get("Content-Type", "").lower() and (
                "octet-stream" not in response.headers.get("Content-Type", "").lower()
            ):
                raise VoiceUnavailable("Kokoro não devolveu um arquivo de áudio")
            data = response.read(15 * 1024 * 1024 + 1)
    except (URLError, HTTPError, TimeoutError, OSError) as exc:
        raise VoiceUnavailable("Falha na comunicação com Kokoro local") from exc
    if len(data) < 128 or len(data) > 15 * 1024 * 1024:
        raise VoiceUnavailable("Áudio inválido ou maior que 15 MB")
    target.write_bytes(data)
