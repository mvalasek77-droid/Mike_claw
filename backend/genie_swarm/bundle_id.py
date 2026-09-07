"""Make the generated project use the bundle ID everything else expects.

The Xcode project is written by the agents, so its bundle identifier is
whatever the model happened to choose — typically something off the
example in the architect prompt. Meanwhile the phone creates the App
Store Connect record, signs, uploads, and polls TestFlight against a
bundle ID of its own. Those two were never connected, so the archive
was signed as one app and uploaded against another, and Apple rejected
it every time.

Nothing here talks to Xcode. It rewrites the identifier in the project
files on disk, deterministically, after the integrator has assembled
the project and before anything builds it. Test targets keep their
`.Tests` / `.UITests` suffix, because Apple requires a test bundle to
differ from the app it tests.
"""
from __future__ import annotations

import re
from pathlib import Path

# `PRODUCT_BUNDLE_IDENTIFIER = com.example.app;` in a pbxproj, with or
# without quotes around the value.
_PBX = re.compile(
    r'(PRODUCT_BUNDLE_IDENTIFIER\s*=\s*)"?([A-Za-z0-9._\-$()]+)"?(\s*;)'
)
# `PRODUCT_BUNDLE_IDENTIFIER: com.example.app` in an XcodeGen project.yml.
_YAML = re.compile(
    r'(PRODUCT_BUNDLE_IDENTIFIER\s*:\s*)"?([A-Za-z0-9._\-$()]+)"?'
)
# `"bundle_id": "com.example.app"` in the architect's plan.
_PLAN = re.compile(r'("bundle_id"\s*:\s*")([^"]*)(")')

_TEST_SUFFIXES = ("tests", "uitests", "uitest", "test")


def is_valid_bundle_id(value: str) -> bool:
    """Apple allows letters, digits, hyphens and dots, and wants at
    least one dot. Anything else is rejected at upload, long after the
    point where saying so is useful."""
    if not value or len(value) > 155 or "." not in value:
        return False
    if value.startswith(".") or value.endswith(".") or ".." in value:
        return False
    return all(
        part and re.fullmatch(r"[A-Za-z0-9\-]+", part)
        for part in value.split(".")
    )


def _suffix_for(existing: str) -> str:
    """Preserve a test target's suffix so it stays distinct from the app.

    Apple refuses a test bundle that shares the app's identifier, so
    rewriting every target to one value would break the build in a way
    that looks nothing like a bundle ID problem.
    """
    tail = existing.rsplit(".", 1)[-1].lower() if "." in existing else ""
    if tail in _TEST_SUFFIXES:
        return "." + existing.rsplit(".", 1)[-1]
    return ""


def enforce_bundle_id(workspace: Path, bundle_id: str) -> list[str]:
    """Rewrite the bundle identifier across the generated project.

    Returns the workspace-relative paths that changed, so the caller can
    say what it did. A blank or malformed `bundle_id` is a no-op: the
    generated project's own value is a better outcome than a broken one
    written over it.
    """
    if not is_valid_bundle_id(bundle_id):
        return []

    changed: list[str] = []
    for path in _project_files(workspace):
        try:
            original = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        if path.name == "plan.json":
            updated = _PLAN.sub(lambda m: m.group(1) + bundle_id + m.group(3), original)
        else:
            pattern = _YAML if path.suffix in {".yml", ".yaml"} else _PBX
            updated = pattern.sub(
                lambda m: m.group(1) + bundle_id + _suffix_for(m.group(2))
                + (m.group(3) if pattern is _PBX else ""),
                original,
            )

        if updated != original:
            path.write_text(updated, encoding="utf-8")
            changed.append(str(path.relative_to(workspace)))
    return changed


def _project_files(workspace: Path) -> list[Path]:
    """Every file that can carry a bundle identifier. Deliberately
    narrow — a blanket search would rewrite the identifier inside
    generated Swift source and docs, where it is prose rather than
    configuration."""
    found: list[Path] = []
    found.extend(sorted(workspace.glob("*.xcodeproj/project.pbxproj")))
    found.extend(sorted(workspace.glob("*/*.xcodeproj/project.pbxproj")))
    for name in ("project.yml", "project.yaml"):
        found.extend(sorted(workspace.glob(name)))
        found.extend(sorted(workspace.glob(f"*/{name}")))
    plan = workspace / "docs" / "plan.json"
    if plan.exists():
        found.append(plan)
    return found
