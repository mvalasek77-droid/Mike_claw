"""Deterministic release-readiness audit for CodeGenie workspaces."""
from __future__ import annotations

from pathlib import Path
from typing import Any, Literal

from .models import AppSpec, GitHubSyncRequest, ShipRequest

Status = Literal["automated", "assisted", "needs_setup", "user_confirmation", "blocked"]


def run_release_readiness(
    *,
    spec: AppSpec,
    workspace: Path,
    ship: ShipRequest | None = None,
    github: GitHubSyncRequest | None = None,
) -> dict[str, Any]:
    """Return the single source of truth for what can ship now.

    The result is intentionally JSON-shaped so iOS can render it without
    duplicating launch logic. "Ready" here means ready for TestFlight:
    Apple's final legal/privacy review confirmation still stays explicit.
    """
    workspace = Path(workspace)
    items: list[dict[str, Any]] = []

    def add(
        key: str,
        title: str,
        status: Status,
        detail: str,
        action: str,
        *,
        required: bool = True,
    ) -> None:
        items.append({
            "key": key,
            "title": title,
            "status": status,
            "detail": detail,
            "action": action,
            "required": required,
        })

    if not workspace.is_dir():
        add(
            "workspace",
            "Workspace exists",
            "blocked",
            f"No workspace was found for {spec.title}.",
            "Run or restore the build before release automation.",
        )
        return _summarise(items)

    add(
        "workspace",
        "Workspace exists",
        "automated",
        "Generated files are present and auditable.",
        "Continue.",
    )

    project = _first_match(workspace, ("*.xcworkspace", "*.xcodeproj"))
    add(
        "xcode_project",
        "Xcode project",
        "automated" if project else "needs_setup",
        f"Found {project.name}." if project else "No .xcodeproj or .xcworkspace was found.",
        "Generate the Xcode project before archive/export.",
    )

    ipa = _ship_ipa(workspace, ship) or _first_match(workspace, ("*.ipa",))
    archive = _first_match(workspace, ("*.xcarchive",))
    if ipa:
        add(
            "ipa",
            "Distribution IPA",
            "automated",
            f"Found {ipa.name}; TestFlight upload can use this binary.",
            "Validate and upload with altool.",
        )
    elif archive:
        add(
            "ipa",
            "Distribution IPA",
            "assisted",
            f"Found {archive.name}; exportArchive still needs to create an IPA.",
            "Export the archive, then run TestFlight upload.",
        )
    else:
        add(
            "ipa",
            "Distribution IPA",
            "needs_setup",
            "No .ipa or .xcarchive was found.",
            "Archive and export an App Store Connect IPA.",
        )

    asc_api_ready = bool(
        ship
        and ship.asc_api_key_id
        and ship.asc_api_issuer_id
        and ship.asc_api_key_path
    )
    apple_id_ready = bool(ship and ship.apple_id and ship.app_specific_password)
    creds_ready = asc_api_ready or apple_id_ready
    add(
        "apple_credentials",
        "Apple upload credentials",
        "automated" if creds_ready else "needs_setup",
        (
            "ASC API key is configured; upload and processing poll are available."
            if asc_api_ready
            else "Apple ID app-specific password is configured; upload is available."
            if apple_id_ready
            else "No ASC API key or Apple ID app-specific password was provided."
        ),
        "Add Apple Developer credentials in Settings.",
    )

    add(
        "testflight_upload",
        "TestFlight validate/upload",
        "automated" if ipa and creds_ready else "needs_setup",
        (
            "Backend can run validate-app, upload-app, and stream progress."
            if ipa and creds_ready
            else "Needs both a distribution IPA and Apple upload credentials."
        ),
        "Create the IPA and save Apple credentials.",
    )
    add(
        "testflight_polling",
        "TestFlight processing poll",
        "automated" if asc_api_ready else "assisted",
        (
            "ASC API key can poll build processing status."
            if asc_api_ready
            else "Upload can finish, but processing must be checked manually or with ASC API credentials."
        ),
        "Use an ASC API key for automatic processing status.",
        required=False,
    )

    privacy_manifest = _first_named(workspace, {"PrivacyInfo.xcprivacy"})
    privacy_keys = _privacy_keys(privacy_manifest)
    required_privacy_keys = {"NSPrivacyTracking", "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"}
    missing_privacy = sorted(required_privacy_keys - privacy_keys)
    add(
        "privacy_manifest",
        "Privacy manifest",
        "automated" if privacy_manifest and not missing_privacy else "needs_setup",
        (
            f"{privacy_manifest.name} includes the required top-level privacy keys."
            if privacy_manifest and not missing_privacy
            else f"{privacy_manifest.name} is missing {', '.join(missing_privacy)}."
            if privacy_manifest
            else "PrivacyInfo.xcprivacy was not found."
        ),
        "Generate or update PrivacyInfo.xcprivacy before App Store handoff.",
    )

    privacy_policy = _first_release_doc(
        workspace,
        ("privacy", "privacy-policy", "privacy_policy"),
        (".md", ".txt", ".html", ".json"),
    )
    add(
        "privacy_policy",
        "Privacy policy draft",
        "automated" if privacy_policy else "needs_setup",
        (
            f"Found {privacy_policy.relative_to(workspace)}."
            if privacy_policy
            else "No privacy policy or metadata privacy URL was found."
        ),
        "Draft the privacy policy and add its App Store URL.",
    )

    terms = _first_release_doc(
        workspace,
        ("terms", "terms-of-use", "terms_of_use", "eula"),
        (".md", ".txt", ".html", ".json"),
    )
    add(
        "terms_of_use",
        "Terms of use / EULA",
        "automated" if terms else "needs_setup",
        f"Found {terms.relative_to(workspace)}." if terms else "No terms or EULA file was found.",
        "Draft terms of use or adopt Apple's standard EULA.",
        required=False,
    )

    metadata = _first_match(
        workspace,
        ("AppStoreMetadata.json", "app_store_metadata.json", "metadata.json", "fastlane/metadata/**/*"),
    )
    add(
        "app_store_metadata",
        "App Store listing metadata",
        "automated" if metadata else "needs_setup",
        (
            f"Found {metadata.relative_to(workspace)}."
            if metadata
            else "No listing metadata file was found."
        ),
        "Generate name, subtitle, keywords, description, support URL, and category.",
    )

    screenshots = _screenshot_files(workspace)
    add(
        "screenshots",
        "App Store screenshots",
        "automated" if screenshots else "needs_setup",
        (
            f"Found {len(screenshots)} screenshot artifact(s)."
            if screenshots
            else "No App Store screenshot assets were found."
        ),
        "Run the screenshot generator for 6.7-inch, 6.1-inch, and iPad sizes.",
    )

    github_status, github_detail, github_action = _github_status(workspace, github)
    add(
        "github",
        "GitHub workspace sync",
        github_status,
        github_detail,
        github_action,
        required=False,
    )

    add(
        "final_submit",
        "Final App Review submit",
        "user_confirmation",
        "Apple account ownership, privacy truthfulness, export compliance, and final submission require explicit developer confirmation.",
        "Review the generated package, then press Submit in App Store Connect.",
        required=False,
    )

    return _summarise(items)


def _summarise(items: list[dict[str, Any]]) -> dict[str, Any]:
    required = [item for item in items if item["required"]]
    ready_required = [item for item in required if item["status"] in {"automated", "assisted", "user_confirmation"}]
    score = round((len(ready_required) / max(1, len(required))) * 100)
    blockers = [item for item in required if item["status"] == "blocked"]
    missing = [item for item in required if item["status"] == "needs_setup"]
    if blockers:
        gate = "blocked"
    elif missing:
        gate = "needs_setup"
    else:
        gate = "ready_for_testflight"
    next_actions = [item["action"] for item in blockers + missing]
    if not next_actions:
        next_actions = ["Run TestFlight upload, then complete Apple-required final review confirmation."]
    return {
        "release_gate": gate,
        "score": score,
        "items": items,
        "next_actions": next_actions,
        "summary": _summary_text(gate, score, len(missing), len(blockers)),
    }


def _summary_text(gate: str, score: int, missing: int, blockers: int) -> str:
    if gate == "ready_for_testflight":
        return f"Ready for TestFlight automation at {score}/100; final App Review submit remains user-confirmed."
    if gate == "blocked":
        return f"Blocked at {score}/100 with {blockers} critical release blocker(s)."
    return f"Needs setup at {score}/100 with {missing} required automation item(s) missing."


def _first_match(workspace: Path, patterns: tuple[str, ...]) -> Path | None:
    for pattern in patterns:
        matches = sorted(workspace.glob(pattern)) if "/" in pattern else sorted(workspace.rglob(pattern))
        for match in matches:
            if match.exists():
                return match
    return None


def _first_named(workspace: Path, names: set[str]) -> Path | None:
    wanted = {name.lower() for name in names}
    for path in sorted(workspace.rglob("*")):
        if path.is_file() and path.name.lower() in wanted:
            return path
    return None


def _ship_ipa(workspace: Path, ship: ShipRequest | None) -> Path | None:
    if not ship or not ship.ipa_path:
        return None
    raw = Path(ship.ipa_path)
    candidate = raw if raw.is_absolute() else workspace / raw
    try:
        resolved = candidate.resolve()
        resolved.relative_to(workspace.resolve())
    except (OSError, ValueError):
        return None
    return resolved if resolved.is_file() and resolved.suffix == ".ipa" else None


def _privacy_keys(path: Path | None) -> set[str]:
    if not path or not path.is_file():
        return set()
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return set()
    return {key for key in ("NSPrivacyTracking", "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes") if key in text}


def _first_release_doc(workspace: Path, stems: tuple[str, ...], suffixes: tuple[str, ...]) -> Path | None:
    targets = {stem.lower() for stem in stems}
    for path in sorted(workspace.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in suffixes:
            continue
        normalized = path.stem.lower().replace(" ", "-")
        if normalized in targets:
            return path
        if path.suffix.lower() == ".json":
            try:
                body = path.read_text(encoding="utf-8", errors="replace").lower()
            except OSError:
                continue
            if any(f"{stem}_url" in body or f"{stem.replace('-', '_')}_url" in body for stem in targets):
                return path
    return None


def _screenshot_files(workspace: Path) -> list[Path]:
    out: list[Path] = []
    for path in sorted(workspace.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in {".png", ".jpg", ".jpeg"}:
            continue
        parts = {part.lower() for part in path.parts}
        if "screenshot" in path.name.lower() or any("screenshot" in part for part in parts):
            out.append(path)
    return out


def _github_status(
    workspace: Path,
    github: GitHubSyncRequest | None,
) -> tuple[Status, str, str]:
    if github and github.repo_url:
        token_ready = bool(github.token)
        non_https = not github.repo_url.lower().startswith("https://")
        if token_ready or non_https:
            return (
                "automated",
                f"Ready to push branch {github.branch} to {github.repo_url}.",
                "Run GitHub sync after Perfection Mode passes.",
            )
        return (
            "needs_setup",
            "HTTPS GitHub repository was provided without a token.",
            "Add a GitHub token with repo write access.",
        )
    git_config = workspace / ".git" / "config"
    if git_config.is_file():
        return (
            "assisted",
            "Workspace already has a Git remote; push can run if local credentials are configured.",
            "Confirm the target branch and push.",
        )
    return (
        "needs_setup",
        "No GitHub repository target was provided.",
        "Connect GitHub and choose a repository.",
    )
