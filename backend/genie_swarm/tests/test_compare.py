"""Tests for genie_swarm.compare — the workspace-to-workspace diff."""
from __future__ import annotations

from pathlib import Path

import pytest

from genie_swarm.compare import (
    FileEntry,
    ProjectDiff,
    compare_workspaces,
    read_file_pair,
)


def _seed_workspace(root: Path, files: dict[str, str]) -> Path:
    root.mkdir(parents=True, exist_ok=True)
    for rel, body in files.items():
        target = root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(body)
    return root


# --------------------------------------------------------------------------- #
# Overview comparison
# --------------------------------------------------------------------------- #

def test_compare_reports_added_removed_modified(tmp_path: Path):
    a = _seed_workspace(tmp_path / "a", {
        "App.swift":       "// a v1",
        "removed.swift":   "// only in a",
        "Theme/Glass.swift": "import SwiftUI",
    })
    b = _seed_workspace(tmp_path / "b", {
        "App.swift":       "// a v2 — modified",
        "added.swift":     "// only in b",
        "Theme/Glass.swift": "import SwiftUI",   # unchanged
    })
    diff = compare_workspaces(a, b, job_a="A", job_b="B")
    by_path = {f.path: f for f in diff.files}

    assert by_path["App.swift"].status == "modified"
    assert by_path["removed.swift"].status == "removed"
    assert by_path["added.swift"].status == "added"
    # Unchanged files are omitted by default.
    assert "Theme/Glass.swift" not in by_path

    assert diff.counts == {"same": 0, "added": 1, "removed": 1, "modified": 1}


def test_compare_include_unchanged(tmp_path: Path):
    a = _seed_workspace(tmp_path / "a", {"x.txt": "same bytes"})
    b = _seed_workspace(tmp_path / "b", {"x.txt": "same bytes"})
    diff = compare_workspaces(a, b, job_a="A", job_b="B", include_unchanged=True)
    assert len(diff.files) == 1
    assert diff.files[0].status == "same"


def test_compare_returns_stable_path_order(tmp_path: Path):
    a = _seed_workspace(tmp_path / "a", {
        "zeta.swift": "x", "alpha.swift": "x", "beta/Glass.swift": "x",
    })
    b = _seed_workspace(tmp_path / "b", {
        "zeta.swift": "y", "alpha.swift": "y", "beta/Glass.swift": "y",
    })
    diff = compare_workspaces(a, b, job_a="A", job_b="B")
    paths = [f.path for f in diff.files]
    assert paths == sorted(paths)


def test_compare_skips_codegenie_and_git_dirs(tmp_path: Path):
    a = _seed_workspace(tmp_path / "a", {
        ".codegenie/memory.sqlite3": "binary-ish",
        ".git/HEAD": "ref: x",
        ".archives/zip.zip": "zipdata",
        "App.swift": "import SwiftUI",
    })
    b = _seed_workspace(tmp_path / "b", {
        "App.swift": "import SwiftUI",
    })
    diff = compare_workspaces(a, b, job_a="A", job_b="B")
    paths = {f.path for f in diff.files}
    # Only the differing app file would show up — and it's not differing
    # here, so we expect zero entries. Crucially, no .codegenie/ paths.
    assert all(not p.startswith(".codegenie/") for p in paths)
    assert all(not p.startswith(".git/") for p in paths)
    assert all(not p.startswith(".archives/") for p in paths)


def test_compare_uses_sha_so_same_size_diff_bytes_is_modified(tmp_path: Path):
    """Two files of equal length but different bytes must show as
    modified — a size-only comparator would miss this."""
    a = _seed_workspace(tmp_path / "a", {"foo.swift": "AAAA"})
    b = _seed_workspace(tmp_path / "b", {"foo.swift": "BBBB"})
    diff = compare_workspaces(a, b, job_a="A", job_b="B")
    assert len(diff.files) == 1
    entry = diff.files[0]
    assert entry.status == "modified"
    assert entry.a_size == entry.b_size == 4
    assert entry.a_sha != entry.b_sha


def test_compare_skips_symlinks(tmp_path: Path):
    """A workspace shouldn't be able to escape itself through a
    symlink — the diff walk filters them out."""
    a = _seed_workspace(tmp_path / "a", {"real.swift": "hi"})
    b = _seed_workspace(tmp_path / "b", {"real.swift": "hi"})
    (a / "evil.swift").symlink_to("/etc/passwd")
    diff = compare_workspaces(a, b, job_a="A", job_b="B")
    assert all(f.path != "evil.swift" for f in diff.files)


def test_compare_rejects_identical_paths(tmp_path: Path):
    ws = _seed_workspace(tmp_path / "shared", {"x": "hi"})
    with pytest.raises(ValueError):
        compare_workspaces(ws, ws, job_a="A", job_b="B")


def test_compare_handles_missing_workspace(tmp_path: Path):
    """A non-existent workspace produces empty results, not an
    exception — useful when one side has been archived."""
    a = _seed_workspace(tmp_path / "a", {"x.swift": "hi"})
    b = tmp_path / "ghost"
    diff = compare_workspaces(a, b, job_a="A", job_b="B")
    assert all(f.status == "removed" for f in diff.files)
    assert any(f.path == "x.swift" for f in diff.files)


# --------------------------------------------------------------------------- #
# Per-file deep dive
# --------------------------------------------------------------------------- #

def test_read_file_pair_returns_both_versions(tmp_path: Path):
    a = _seed_workspace(tmp_path / "a", {"App.swift": "v1"})
    b = _seed_workspace(tmp_path / "b", {"App.swift": "v2"})
    body_a, body_b = read_file_pair(a, b, "App.swift")
    assert body_a == "v1"
    assert body_b == "v2"


def test_read_file_pair_handles_missing_sides(tmp_path: Path):
    a = _seed_workspace(tmp_path / "a", {"only_a.swift": "AA"})
    b = _seed_workspace(tmp_path / "b", {})
    body_a, body_b = read_file_pair(a, b, "only_a.swift")
    assert body_a == "AA"
    assert body_b is None


def test_read_file_pair_caps_byte_budget(tmp_path: Path):
    big = "x" * 10_000
    a = _seed_workspace(tmp_path / "a", {"big.txt": big})
    b = _seed_workspace(tmp_path / "b", {"big.txt": big})
    body_a, body_b = read_file_pair(a, b, "big.txt", max_bytes=1024)
    # Both sides truncated identically.
    assert "[truncated at 1024 bytes]" in body_a
    assert "[truncated at 1024 bytes]" in body_b


def test_read_file_pair_rejects_path_escape(tmp_path: Path):
    a = _seed_workspace(tmp_path / "a", {"App.swift": "hi"})
    b = _seed_workspace(tmp_path / "b", {"App.swift": "hi"})
    body_a, body_b = read_file_pair(a, b, "../escape.swift")
    # Both sides should refuse to read the escaped path.
    assert body_a is None
    assert body_b is None


# --------------------------------------------------------------------------- #
# FileEntry helpers
# --------------------------------------------------------------------------- #

def test_file_entry_is_text_like_classifies_correctly():
    swift = FileEntry("App.swift", "modified", 1, 1, "x", "y")
    plist = FileEntry("Info.plist", "modified", 1, 1, "x", "y")
    binary = FileEntry("Icon@2x.png", "added", None, 1, None, "z")
    makefile = FileEntry("Makefile", "added", None, 1, None, "z")
    assert swift.is_text_like
    assert plist.is_text_like
    assert makefile.is_text_like
    assert not binary.is_text_like


def test_project_diff_counts_is_inclusive():
    files = [
        FileEntry("a", "modified", 1, 1, "x", "y"),
        FileEntry("b", "added", None, 2, None, "z"),
        FileEntry("c", "removed", 3, None, "w", None),
    ]
    diff = ProjectDiff(job_a="A", job_b="B", files=files)
    assert diff.counts == {"same": 0, "added": 1, "removed": 1, "modified": 1}
