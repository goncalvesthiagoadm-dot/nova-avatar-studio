"""Contract tests run without downloading ONNX models or changing production."""
import io
import wave

from fastapi.testclient import TestClient
import pytest

from voice_lite import api as lite


def test_worker_health_and_speech_contract(monkeypatch):
    monkeypatch.setattr(lite, "load_models", lambda: None)
    monkeypatch.setattr(lite, "_ENGINE", object())
    monkeypatch.setattr(lite, "_G2P", object())
    def fake_wav(text, speed):
        assert text == "Olá, sou a apresentadora NOVA."
        assert speed == 1.0
        buf = io.BytesIO()
        with wave.open(buf, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(24000)
            w.writeframes(b"\x00\x00" * 500)
        return buf.getvalue()
    monkeypatch.setattr(lite, "synthesize", fake_wav)
    with TestClient(lite.app) as client:
        assert client.get("/health").status_code == 200
        payload = {"model":"kokoro","input":"Olá, sou a apresentadora NOVA.",
                   "voice":"pf_dora","response_format":"wav","speed":1.0}
        resp = client.post("/v1/audio/speech", json=payload)
        assert resp.status_code == 200
        assert resp.content.startswith(b"RIFF")
        assert resp.headers["content-type"].startswith("audio/wav")
        for changes in ({"voice":"pf_fake"},{"model":"fake"},{"response_format":"mp3"},
                        {"input":"x"*701},{"speed":4.0},{"input":"  "}):
            attempt = client.post("/v1/audio/speech", json={**payload, **changes})
            assert attempt.status_code in (422, 503)
        assert client.get("/docs").status_code == 404


def test_worker_refuses_concurrent_generation(monkeypatch):
    monkeypatch.setattr(lite, "load_models", lambda: None)
    monkeypatch.setattr(lite, "_ENGINE", object())
    monkeypatch.setattr(lite, "_G2P", object())
    payload = {"model":"kokoro","input":"Oi","voice":"pf_dora","response_format":"wav"}
    with TestClient(lite.app) as client:
        acquired = lite._LOCK.acquire(blocking=False)
        assert acquired
        try:
            assert client.post("/v1/audio/speech", json=payload).status_code == 429
        finally:
            lite._LOCK.release()
