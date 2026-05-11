"""Session — owns the workspace, transcript, and checkpoints for a job.

Each `BuildJob` gets one `Session`. Sessions are persisted as JSON
(transcript) plus the on-disk workspace, so a run can be resumed.
"""
from __future__ import annotations

import json
import time
from dataclasses import dataclass, field
from pathlib import Path

from .models import BuildJob, JobState, Message
from .sandbox import Sandbox, SandboxPolicy


@dataclass
class Checkpoint:
    """A snapshot we can restore to. We keep one per agent invocation, so
    the orchestrator can roll back if a downstream agent finds the build
    is unrecoverable."""
    label: str
    at: float
    transcript: list[Message]
    files_snapshot: dict[str, str]


@dataclass
class Session:
    job: BuildJob
    workspace: Path
    sandbox: Sandbox
    transcript: list[Message] = field(default_factory=list)
    checkpoints: list[Checkpoint] = field(default_factory=list)

    @classmethod
    def open(cls, job: BuildJob, root: Path) -> "Session":
        ws = root / job.id
        ws.mkdir(parents=True, exist_ok=True)
        sandbox = Sandbox(SandboxPolicy(workspace=ws))
        return cls(job=job, workspace=ws, sandbox=sandbox)

    # ------------------------------------------------------------------
    # Persistence
    # ------------------------------------------------------------------

    def save(self) -> None:
        meta = {
            "job": self.job.model_dump(),
            "transcript": [m.model_dump() for m in self.transcript],
            "checkpoints": [
                {
                    "label": c.label,
                    "at": c.at,
                    "transcript": [m.model_dump() for m in c.transcript],
                    "files": list(c.files_snapshot.keys()),
                }
                for c in self.checkpoints
            ],
        }
        (self.workspace / ".genie-session.json").write_text(json.dumps(meta, indent=2))

    @classmethod
    def load(cls, root: Path, job_id: str) -> "Session":
        ws = root / job_id
        meta = json.loads((ws / ".genie-session.json").read_text())
        job = BuildJob.model_validate(meta["job"])
        sandbox = Sandbox(SandboxPolicy(workspace=ws))
        # Restore checkpoint metadata so resume() can tell which stages
        # already ran. We deliberately don't reload `files_snapshot`
        # contents — the workspace on disk is the source of truth for
        # files, and the snapshot dict is only used for in-memory
        # rollback during a single run.
        checkpoints = [
            Checkpoint(
                label=cp["label"],
                at=cp["at"],
                transcript=[Message.model_validate(m) for m in cp.get("transcript", [])],
                files_snapshot={},
            )
            for cp in meta.get("checkpoints", [])
        ]
        return cls(
            job=job, workspace=ws, sandbox=sandbox,
            transcript=[Message.model_validate(m) for m in meta["transcript"]],
            checkpoints=checkpoints,
        )

    # ------------------------------------------------------------------
    # Checkpoints — light, in-memory + best-effort file snapshot
    # ------------------------------------------------------------------

    def checkpoint(self, label: str) -> Checkpoint:
        snapshot: dict[str, str] = {}
        for p in self.workspace.rglob("*"):
            if p.is_file() and p.stat().st_size < 256_000 and ".git" not in p.parts:
                try:
                    snapshot[str(p.relative_to(self.workspace))] = p.read_text(
                        encoding="utf-8", errors="replace"
                    )
                except (UnicodeDecodeError, OSError):
                    pass
        cp = Checkpoint(
            label=label,
            at=time.time(),
            transcript=list(self.transcript),
            files_snapshot=snapshot,
        )
        self.checkpoints.append(cp)
        # Persist so resume() can find this checkpoint after a crash
        # or process restart. Cheap — the session JSON is < 100KB
        # even with a long transcript.
        try:
            self.save()
        except OSError:
            # Best-effort: a workspace write failure shouldn't kill
            # the in-memory build. The next save() attempt will retry.
            pass
        return cp

    def restore(self, cp: Checkpoint) -> None:
        for rel, body in cp.files_snapshot.items():
            target = self.workspace / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(body, encoding="utf-8")
        self.transcript = list(cp.transcript)

    # ------------------------------------------------------------------
    # Convenience
    # ------------------------------------------------------------------

    def update_state(self, new: JobState, *, error: str | None = None) -> None:
        self.job.state = new
        if new == JobState.failed and error:
            self.job.error = error
        if new in {JobState.succeeded, JobState.failed, JobState.cancelled}:
            self.job.finished_at = time.time()
        if new == JobState.planning and self.job.started_at is None:
            self.job.started_at = time.time()
