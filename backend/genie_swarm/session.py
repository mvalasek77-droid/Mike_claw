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

    @property
    def _snapshots_dir(self) -> Path:
        return self.workspace / ".codegenie" / "snapshots"

    def snapshots_size_bytes(self) -> int:
        """Sum of every file under `.codegenie/snapshots/`. Cheap-ish —
        we walk the tree on demand. Cached lookups would help if this
        ever became a hot path; it isn't today."""
        d = self._snapshots_dir
        if not d.is_dir():
            return 0
        total = 0
        for p in d.rglob("*"):
            try:
                if p.is_file():
                    total += p.stat().st_size
            except OSError:
                pass
        return total

    def _safe_label(self, label: str) -> str:
        """Return a filesystem-safe directory name for a checkpoint."""
        keep = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        return "".join(c if c in keep else "_" for c in label) or "snapshot"

    def save(self) -> None:
        # Persist every checkpoint's file contents under
        # `.codegenie/snapshots/<safe-label>/...` so /restore can roll
        # the workspace back to that exact tree. The in-memory
        # `files_snapshot` is the source of truth; we mirror it to disk
        # on each save so a process restart doesn't lose the bytes.
        self._snapshots_dir.mkdir(parents=True, exist_ok=True)
        existing_dirs = {p.name for p in self._snapshots_dir.iterdir() if p.is_dir()}
        kept_dirs: set[str] = set()
        for cp in self.checkpoints:
            slug = self._safe_label(cp.label)
            kept_dirs.add(slug)
            target_dir = self._snapshots_dir / slug
            target_dir.mkdir(parents=True, exist_ok=True)
            for rel, body in cp.files_snapshot.items():
                target = target_dir / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                try:
                    target.write_text(body, encoding="utf-8")
                except OSError:
                    pass
        # Prune snapshot dirs whose label is no longer in memory — e.g.
        # if the orchestrator ever shrinks `checkpoints`. We never
        # auto-shrink today but the hygiene matters for long jobs.
        for stale in existing_dirs - kept_dirs:
            self._rmtree_silent(self._snapshots_dir / stale)

        meta = {
            "job": self.job.model_dump(),
            "transcript": [m.model_dump() for m in self.transcript],
            "checkpoints": [
                {
                    "label": c.label,
                    "at": c.at,
                    "transcript": [m.model_dump() for m in c.transcript],
                    "files": list(c.files_snapshot.keys()),
                    "slug": self._safe_label(c.label),
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
        snapshots_dir = ws / ".codegenie" / "snapshots"

        # Re-hydrate `files_snapshot` from disk if the snapshot dir
        # exists. Falling back to empty (read from workspace next time)
        # keeps older sessions readable.
        def _load_files(slug: str) -> dict[str, str]:
            d = snapshots_dir / slug
            if not d.is_dir():
                return {}
            out: dict[str, str] = {}
            for p in d.rglob("*"):
                if p.is_file():
                    try:
                        out[str(p.relative_to(d))] = p.read_text(encoding="utf-8")
                    except (UnicodeDecodeError, OSError):
                        pass
            return out

        checkpoints = []
        for cp in meta.get("checkpoints", []):
            slug = cp.get("slug")
            files: dict[str, str] = {}
            if slug:
                files = _load_files(slug)
            checkpoints.append(Checkpoint(
                label=cp["label"],
                at=cp["at"],
                transcript=[Message.model_validate(m) for m in cp.get("transcript", [])],
                files_snapshot=files,
            ))
        return cls(
            job=job, workspace=ws, sandbox=sandbox,
            transcript=[Message.model_validate(m) for m in meta["transcript"]],
            checkpoints=checkpoints,
        )

    @staticmethod
    def _rmtree_silent(p: Path) -> None:
        try:
            import shutil
            shutil.rmtree(p, ignore_errors=True)
        except OSError:
            pass

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
        """Rewind the workspace + transcript to a checkpoint.

        Files that existed at the checkpoint get overwritten with their
        snapshot bytes. Files that did NOT exist at the checkpoint —
        i.e. anything an agent created after — are removed so the
        directory matches the snapshot exactly. We never touch
        anything inside `.codegenie/` or `.git/` so memory + VCS
        state survive the rollback.
        """
        wanted_paths = set(cp.files_snapshot.keys())
        # Phase 1: write known files.
        for rel, body in cp.files_snapshot.items():
            target = self.workspace / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            try:
                target.write_text(body, encoding="utf-8")
            except OSError:
                pass
        # Phase 2: remove files added after the checkpoint.
        if wanted_paths:
            for p in self.workspace.rglob("*"):
                if not p.is_file():
                    continue
                parts = p.relative_to(self.workspace).parts
                if not parts:
                    continue
                if parts[0] in {".codegenie", ".git"}:
                    continue
                rel = str(p.relative_to(self.workspace))
                if rel not in wanted_paths:
                    try:
                        p.unlink()
                    except OSError:
                        pass
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
