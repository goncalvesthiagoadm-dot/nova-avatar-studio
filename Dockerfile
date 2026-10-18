FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY studio/ ./studio/
RUN useradd --uid 10001 --create-home appuser && mkdir -p /app/storage && chown -R appuser:appuser /app
USER appuser
EXPOSE 10000
CMD ["sh", "-c", "exec uvicorn studio.app:app --host 0.0.0.0 --port ${PORT:-8018} --workers 1"]
