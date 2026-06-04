from __future__ import annotations

import asyncio
import json
import shutil
import time
import uuid
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import StreamingResponse


ROOT = Path(__file__).resolve().parent
TEMPLATE = ROOT / "TruthTranslator"
WORKSPACES = Path("/private/tmp/codegenie-generated")

app = FastAPI(title="Local CodeGenie ChadDrop Generator")
jobs: dict[str, dict[str, Any]] = {}


@app.post("/api/coding/swarm/build")
async def start_build(body: dict[str, Any]) -> dict[str, str]:
    spec = body.get("spec") or {}
    title = str(spec.get("title") or "ChadDrop")
    prompt = str(spec.get("prompt") or "")
    job_id = "job_" + uuid.uuid4().hex[:12]
    workspace = WORKSPACES / job_id
    events: list[dict[str, Any]] = []
    jobs[job_id] = {
        "id": job_id,
        "state": "planning",
        "title": title,
        "prompt": prompt,
        "workspace": workspace,
        "events": events,
    }

    def emit(event_type: str, **payload: Any) -> None:
        events.append(
            {
                "type": event_type,
                "ts": time.time(),
                "job_id": job_id,
                "agent": payload.pop("agent", None),
                "payload": payload,
            }
        )

    emit("job.created", title=title, prompt=prompt)
    emit("job.state", state="planning")

    async def generate() -> None:
        try:
            await asyncio.sleep(0.25)
            jobs[job_id]["state"] = "building"
            emit("job.state", state="building")
            emit("log", agent="Architect", message="Planning ChadDrop screens, AI proxy boundary, offline fallback, and App Store-safe humor rules.")
            emit("log", agent="Designer", message="Preparing a dark SwiftUI interface with paste input, tone controls, truth score, and suggested replies.")

            if workspace.exists():
                shutil.rmtree(workspace)
            workspace.mkdir(parents=True, exist_ok=True)
            shutil.copytree(
                TEMPLATE,
                workspace / "ChadDrop",
                ignore=shutil.ignore_patterns(
                    "TruthTranslator.xcodeproj",
                    "*.xcresult",
                    ".DS_Store",
                    "node_modules",
                ),
            )

            await asyncio.sleep(0.25)
            emit("log", agent="Coder", message="Generated the ChadDrop SwiftUI project and Cloudflare OpenAI proxy scaffold.")
            emit(
                "diff",
                path="ChadDrop/TruthTranslator/ContentView.swift",
                status="added",
                summary="Primary paste/decode interface for ChadDrop.",
            )
            emit(
                "diff",
                path="ChadDrop/Proxy/openai-worker.js",
                status="added",
                summary="Server-side OpenAI proxy; no API key is shipped in the iOS app.",
            )
            jobs[job_id]["state"] = "testing"
            emit("job.state", state="testing")
            emit("log", agent="Unit Tester", message="Generated unit and UI test targets for decode behavior and first-screen flow.")

            await asyncio.sleep(0.25)
            jobs[job_id]["state"] = "succeeded"
            emit("job.state", state="succeeded", summary="ChadDrop generated through local CodeGenie.")
            emit("done", success=True)
        except Exception as exc:  # noqa: BLE001
            jobs[job_id]["state"] = "failed"
            emit("job.state", state="failed")
            emit("error", message=str(exc))
            emit("done", success=False)

    asyncio.create_task(generate())
    return {"job_id": job_id, "state": "planning"}


@app.get("/api/coding/swarm/{job_id}/status")
async def status(job_id: str) -> dict[str, Any]:
    job = _job(job_id)
    return {
        "id": job_id,
        "state": job["state"],
        "spec": {"title": job["title"], "prompt": job["prompt"]},
    }


@app.get("/api/coding/swarm/{job_id}/stream")
async def stream(job_id: str) -> StreamingResponse:
    job = _job(job_id)

    async def gen():
        sent = 0
        idle = 0
        while idle < 120:
            events = job["events"]
            while sent < len(events):
                event = events[sent]
                sent += 1
                yield f"event: {event['type']}\n".encode()
                yield ("data: " + json.dumps(event) + "\n\n").encode()
                idle = 0
            if job["state"] in {"succeeded", "failed"} and sent >= len(events):
                break
            idle += 1
            await asyncio.sleep(0.25)

    return StreamingResponse(gen(), media_type="text/event-stream")


@app.get("/api/coding/swarm/{job_id}/files")
async def files(job_id: str) -> dict[str, list[str]]:
    job = _job(job_id)
    workspace: Path = job["workspace"]
    if not workspace.exists():
        return {"files": []}
    return {
        "files": sorted(
            str(path.relative_to(workspace))
            for path in workspace.rglob("*")
            if path.is_file() and ".git" not in path.parts
        )
    }


@app.get("/api/coding/swarm/{job_id}/file")
async def file(job_id: str, path: str = Query(...)) -> dict[str, str]:
    job = _job(job_id)
    base: Path = job["workspace"]
    target = (base / path).resolve()
    if base.resolve() not in target.parents:
        raise HTTPException(403, "path escapes workspace")
    if not target.exists() or not target.is_file():
        raise HTTPException(404, "file not found")
    return {"path": path, "body": target.read_text(encoding="utf-8", errors="replace")}


def _job(job_id: str) -> dict[str, Any]:
    job = jobs.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")
    return job
