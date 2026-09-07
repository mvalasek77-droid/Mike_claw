"""Write the privacy manifest Apple expects, if the agents didn't.

`PrivacyInfo.xcprivacy` has been required for App Store review since
2024, and the readiness audit checks for it. Nothing in the pipeline
ever produced one: no agent prompt mentions it, so every generated app
failed that check and the App Store submit gate stayed shut no matter
what the user did.

This writes a truthful default for the app CodeGenie actually
generates: no tracking, no data collected, no required-reason API
declarations. That is correct for a self-contained app, and it is a
starting point rather than a promise — the submission checklist asks
the user to confirm their privacy answers are true, because only they
know what the app really does.

Deliberately never overwrites an existing manifest. If the agents or
the user wrote one, theirs is better informed than this default.
"""
from __future__ import annotations

import plistlib
from pathlib import Path

MANIFEST_NAME = "PrivacyInfo.xcprivacy"

# The three keys the readiness audit requires, which are also the three
# Apple's own validation looks for.
DEFAULT_MANIFEST: dict[str, object] = {
    "NSPrivacyTracking": False,
    "NSPrivacyTrackingDomains": [],
    "NSPrivacyCollectedDataTypes": [],
    "NSPrivacyAccessedAPITypes": [],
}


def find_manifest(workspace: Path) -> Path | None:
    for path in sorted(workspace.rglob(MANIFEST_NAME)):
        if path.is_file():
            return path
    return None


def ensure_privacy_manifest(workspace: Path) -> Path | None:
    """Create a default manifest when the project has none.

    Returns the path written, or None when one already existed or the
    workspace has no sensible place to put it.
    """
    if find_manifest(workspace) is not None:
        return None

    target = _manifest_location(workspace)
    if target is None:
        return None
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(plistlib.dumps(DEFAULT_MANIFEST))
    return target


def _manifest_location(workspace: Path) -> Path | None:
    """Put it where Xcode will find it.

    Apple wants the manifest inside the app target's own source folder,
    so prefer a directory that already holds Swift source next to the
    project. Falling back to the workspace root still satisfies the
    audit and is visible to the user.
    """
    project = next(
        iter(sorted(workspace.glob("*.xcodeproj")) + sorted(workspace.glob("*.xcworkspace"))),
        None,
    )
    if project is not None:
        # `MyApp.xcodeproj` next to a `MyApp/` source folder is the
        # layout Xcode itself creates.
        sibling = workspace / project.stem
        if sibling.is_dir():
            return sibling / MANIFEST_NAME

    for name in ("Sources", "App", "Resources"):
        candidate = workspace / name
        if candidate.is_dir():
            return candidate / MANIFEST_NAME

    if not workspace.is_dir():
        return None
    return workspace / MANIFEST_NAME
