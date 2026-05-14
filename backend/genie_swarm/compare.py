"""Pure-function diff between two job workspaces.

The build-comparison surface in the iOS app needs two answers:

1. **Overview**: which files differ between job A and job B, and how
   big is each change? This is the file-list view.
2. **Per-file**: full text of both versions so the iOS hunk renderer
   can show inline.

This module exposes both as plain dataclasses. The API layer wraps
them in JSON; the orchestrator never calls them directly. We keep
the comparison strictly on-disk — no Memory lookups, no SSE events —
so a comparison can run against archived workspaces too.

Files inside `.codegenie/`, `.git/`, and any path that ``Sandbox``
would already reject are excluded. We do not follow symlinks.
"""
from __future__ import annotations

import hashlib
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, Literal


FileStatus = Literal["same", "added", "removed", "modified"]


# Files we never surface in a diff. Memory state and VCS metadata
# aren't useful as workspace deltas — and `.codegenie/` may contain
# secret-adjacent material we deliberately keep off-export.
_EXCLUDED_TOP_LEVEL = {".codegenie", ".git", ".archives"}


@dataclass(frozen=True)
class FileEntry:
    """One row in the comparison overview."""
    path: str
    status: FileStatus
    a_size: int | None
    b_size: int | None
    a_sha: str | None
    b_sha: str | None

    @property
    def is_text_like(self) -> bool:
        """Heuristic: treat files with a recognisable code/markup
        suffix as text. Binary files still appear in the overview but
        the per-file endpoint refuses to load their bytes."""
        suffixes = {
            ".swift", ".py", ".js", ".ts", ".tsx", ".jsx", ".html",
            ".css", ".scss", ".json", ".yaml", ".yml", ".md", ".txt",
            ".plist", ".xcconfig", ".xcprivacy", ".xcstrings", ".strings",
            ".sh", ".bash", ".rb", ".m", ".mm", ".h", ".c", ".cpp",
            ".gitignore", ".env",
        }
        p = Path(self.path)
        return p.suffix.lower() in suffixes or p.name in {"Makefile", "Dockerfile"}


@dataclass(frozen=True)
class ProjectDiff:
    """Result of a workspace-to-workspace comparison."""
    job_a: str
    job_b: str
    files: list[FileEntry]

    @property
    def counts(self) -> dict[str, int]:
        out = {"same": 0, "added": 0, "removed": 0, "modified": 0}
        for f in self.files:
            out[f.status] += 1
        return out


# --------------------------------------------------------------------------- #
# Public API
# --------------------------------------------------------------------------- #

def compare_workspaces(
    workspace_a: Path,
    workspace_b: Path,
    *,
    job_a: str,
    job_b: str,
    include_unchanged: bool = False,
) -> ProjectDiff:
    """Compare two workspace directories file-by-file.

    Returns a `ProjectDiff` with one `FileEntry` per path that exists
    in either side (or both, when `include_unchanged=True`). Order is
    stable and sorted by path so the iOS list view is deterministic.
    """
    if workspace_a == workspace_b:
        raise ValueError("workspace_a and workspace_b are the same path")
    a_files = dict(_walk_files(workspace_a))
    b_files = dict(_walk_files(workspace_b))

    all_paths = sorted(set(a_files) | set(b_files))
    entries: list[FileEntry] = []
    for rel in all_paths:
        a = a_files.get(rel)
        b = b_files.get(rel)
        if a is not None and b is not None:
            if a.sha == b.sha:
                if include_unchanged:
                    entries.append(FileEntry(rel, "same", a.size, b.size, a.sha, b.sha))
                continue
            entries.append(FileEntry(rel, "modified", a.size, b.size, a.sha, b.sha))
        elif a is None and b is not None:
            entries.append(FileEntry(rel, "added", None, b.size, None, b.sha))
        elif a is not None and b is None:
            entries.append(FileEntry(rel, "removed", a.size, None, a.sha, None))

    return ProjectDiff(job_a=job_a, job_b=job_b, files=entries)


def read_file_pair(
    workspace_a: Path, workspace_b: Path, rel_path: str, *,
    max_bytes: int = 200_000,
) -> tuple[str | None, str | None]:
    """Read both versions of a file as UTF-8 text. Returns `(None, body)`
    when the file is new, `(body, None)` when removed. Caps each side
    at `max_bytes`; oversized files are reported as truncated."""
    a_text = _read_text_if_present(workspace_a, rel_path, max_bytes)
    b_text = _read_text_if_present(workspace_b, rel_path, max_bytes)
    return a_text, b_text


# --------------------------------------------------------------------------- #
# Internals
# --------------------------------------------------------------------------- #

@dataclass(frozen=True)
class _FileFingerprint:
    size: int
    sha: str


def _walk_files(workspace: Path) -> Iterator[tuple[str, _FileFingerprint]]:
    """Yield `(relative_path, fingerprint)` for every file under
    `workspace` that isn't in the excluded set. We skip symlinks
    explicitly so a malicious workspace can't make us follow off the
    disk."""
    if not workspace.is_dir():
        return
    base = workspace.resolve()
    for path in base.rglob("*"):
        if path.is_symlink() or not path.is_file():
            continue
        try:
            rel = path.relative_to(base)
        except ValueError:
            continue
        parts = rel.parts
        if not parts or parts[0] in _EXCLUDED_TOP_LEVEL:
            continue
        try:
            data = path.read_bytes()
        except OSError:
            continue
        yield (
            str(rel),
            _FileFingerprint(
                size=len(data),
                sha=hashlib.sha256(data).hexdigest()[:16],
            ),
        )


def _read_text_if_present(workspace: Path, rel: str, cap: int) -> str | None:
    target = (workspace / rel).resolve()
    try:
        target.relative_to(workspace.resolve())
    except ValueError:
        return None
    if not target.is_file():
        return None
    try:
        data = target.read_bytes()
    except OSError:
        return None
    truncated = len(data) > cap
    body = data[:cap].decode("utf-8", errors="replace")
    if truncated:
        body += f"\n... [truncated at {cap} bytes]"
    return body
