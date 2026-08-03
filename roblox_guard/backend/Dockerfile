FROM python:3.11-slim

WORKDIR /app

# Install system deps for playwright (evidence screenshots)
# Keep it minimal — playwright is optional, app degrades gracefully without it
RUN apt-get update && apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Install runtime deps only (strip test packages)
RUN pip install --no-cache-dir fastapi uvicorn httpx[http2] python-multipart pyjwt cryptography

# Copy the app
COPY . .

# Persistent volume at /data for SQLite DB + evidence files
ENV RG_DB_PATH=/data/roblox_guard.db
ENV RG_API_TOKEN=""
ENV RG_ADMIN_TOKEN=""

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]