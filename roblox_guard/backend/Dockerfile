FROM python:3.11-slim

WORKDIR /app

# Install system deps for playwright (evidence screenshots)
# Playwright is optional — app degrades gracefully without it
RUN apt-get update && apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Install runtime deps from requirements.txt, then strip test packages
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && pip uninstall -y pytest pytest-asyncio \
    && rm -rf /root/.cache

# Copy the app
COPY . .

# Create volume directories
RUN mkdir -p /data /data/evidence /data/logs

# Persistent volume at /data for SQLite DB + evidence files
ENV RG_DB_PATH=/data/roblox_guard.db
ENV RG_LOG_DIR=/data/logs
ENV RG_EVIDENCE_DIR=/data/evidence

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]