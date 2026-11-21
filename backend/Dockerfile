# CodeGenie Swarm API — the backend that runs the AI build agents.
#
# This is the server the iOS app talks to. It is a plain Python web
# service: it orchestrates the LLM "swarm" that writes an app's source
# code. It does NOT build iOS binaries (that happens later, in Xcode on
# the user's Mac), so it needs no macOS and no Apple toolchain.
#
# No secrets are baked in. Each user brings their own Anthropic/OpenAI
# key, sent with every request over TLS and used only for that build.
# The image is portable: Render, Fly.io, Railway, Google Cloud Run, or
# any host that runs a container.
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Install dependencies first so this layer caches across code changes.
COPY genie_swarm/requirements.txt /app/genie_swarm/requirements.txt
RUN pip install --no-cache-dir -r genie_swarm/requirements.txt "uvicorn[standard]>=0.29"

# Application code.
COPY genie_swarm /app/genie_swarm

# The platform injects $PORT; default to 8000 for local runs.
ENV PORT=8000
EXPOSE 8000

# IMPORTANT: one worker only. The swarm keeps each job's state (progress,
# files, the live event stream) in this process's memory. A second worker
# or a second instance would run jobs the first can't see, so a /stream
# request could land on the wrong process and show nothing. Scale by
# giving this one instance more CPU/RAM, not by adding workers/replicas,
# until job state is moved to a shared store.
CMD ["sh", "-c", "uvicorn genie_swarm.api:app --host 0.0.0.0 --port ${PORT:-8000}"]
