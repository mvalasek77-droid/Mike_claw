"""Workspace rotation — archive stale job workspaces to a zip and
remove them from the live `workspace_root`, so old builds don't crowd
out new ones on disk.

We never delete a workspace outright. Each archive lives at
`<workspace_root>/.archives/<job_id>-<timestamp>.zip` and Memory is
notified via `note_decision` so the user can find it later (and so
the iOS crash-log + future history views can surface it). Running
jobs are skipped — we never archive workspaces whose `.genie-session
.json` was touched within the cutoff window or whose job_id is
currently in `active_job_ids`.
"""
from __future__ import annotations

import io
import os
import shutil
import time
import zipfile
from dataclasses import dataclass
from pathlib import Path

from .memory import Memory


@dataclass
class ArchiveSummary:
    job_id: str
    archive_path: str
    bytes_written: int
    files_archived: int


def archive_old_workspaces(
    workspace_root: Path,
    *,
    older_than_seconds: float = 30 * 24 * 60 * 60,   # 30 days
    active_job_ids: set[str] | None = None,
    now: float | None = None,
    memory: Memory | None = None,
) -> list[ArchiveSummary]:
    """Walk `workspace_root` and zip every job directory whose
    `.genie-session.json` is older than the cutoff. Returns the list
    of summaries so the caller (and tests) can assert on what moved.

    Skips:
      * `<root>/.archives/` itself
      * job ids in `active_job_ids` (currently running)
      * directories without a `.genie-session.json` (not real sessions)
      * anything modified within the cutoff window
    """
    workspace_root = Path(workspace_root)
    if not workspace_root.is_dir():
        return []

    active = active_job_ids or set()
    clock = now if now is not None else time.time()
    cutoff = clock - older_than_seconds

    archives_dir = workspace_root / ".archives"
    archives_dir.mkdir(parents=True, exist_ok=True)

    results: list[ArchiveSummary] = []
    mem = memory or Memory(workspace_root)

    for entry in workspace_root.iterdir():
        if entry.name.startswith(".") or not entry.is_dir():
            continue
        job_id = entry.name
        if job_id in active:
            continue
        session_json = entry / ".genie-session.json"
        if not session_json.exists():
            continue
        if session_json.stat().st_mtime > cutoff:
            continue

        # Archive the workspace.
        ts = int(session_json.stat().st_mtime)
        archive_path = archives_dir / f"{job_id}-{ts}.zip"
        files_archived = 0
        with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for p in entry.rglob("*"):
                if not p.is_file():
                    continue
                parts = p.relative_to(entry).parts
                # Skip nested archives + git, but DO include .codegenie
                # because the user might want to recover memory data
                # later — they explicitly opted into rotating.
                if not parts:
                    continue
                if parts[0] == ".git":
                    continue
                rel = str(p.relative_to(entry))
                zf.write(p, arcname=rel)
                files_archived += 1

        bytes_written = archive_path.stat().st_size
        try:
            shutil.rmtree(entry, ignore_errors=True)
        except OSError:
            pass

        mem.note_decision(
            job_id, "archive",
            f"workspace zipped to {archive_path.name} "
            f"({files_archived} files, {bytes_written} bytes)",
        )
        results.append(ArchiveSummary(
            job_id=job_id,
            archive_path=str(archive_path),
            bytes_written=bytes_written,
            files_archived=files_archived,
        ))

    return results
