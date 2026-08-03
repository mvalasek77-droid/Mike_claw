FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && pip uninstall -y pytest pytest-asyncio \
    && rm -rf /root/.cache

COPY . .

RUN mkdir -p /data /data/evidence /data/logs

ENV RG_DB_PATH=/data/roblox_guard.db \
    RG_LOG_DIR=/data/logs \
    RG_EVIDENCE_DIR=/data/evidence

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
