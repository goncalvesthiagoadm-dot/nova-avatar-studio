# Optional ONNX CPU voice worker, separate from the NOVA main app.
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl espeak-ng libsndfile1 && rm -rf /var/lib/apt/lists/*
COPY voice_lite/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt
RUN mkdir -p /models && \
    curl --retry 3 -fL --silent --show-error \
       'https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/kokoro-v1.0.int8.onnx' \
       -o /models/kokoro-v1.0.int8.onnx && \
    echo 'ae315a79b623f244700e4afb9246c46a26066782e049ba174bf3ba433970ee9c  /models/kokoro-v1.0.int8.onnx' | sha256sum -c - && \
    curl --retry 3 -fL --silent --show-error \
       'https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/voices-v1.0.bin' \
       -o /models/voices-v1.0.bin && \
    echo 'bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d  /models/voices-v1.0.bin' | sha256sum -c -
COPY voice_lite/__init__.py voice_lite/api.py /app/voice_lite/
RUN useradd --uid 10002 --create-home voiceuser && chown -R voiceuser:voiceuser /app /models
USER voiceuser
EXPOSE 8880
CMD ["uvicorn", "voice_lite.api:app", "--host", "0.0.0.0", "--port", "8880", "--workers", "1"]
