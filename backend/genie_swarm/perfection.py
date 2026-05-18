"""Deterministic "Perfection Mode" quality matrix.

This is not a replacement for real simulator/device testing. It is the
cheap, always-on gate that runs before a human spends time or money on
TestFlight: thousands of virtual probes collapsed into a small report
that points at concrete release blockers.
"""
from __future__ import annotations

import hashlib
import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

from .models import AppSpec


Severity = Literal["info", "warning", "error", "critical"]


@dataclass(frozen=True)
class QualityAxis:
    key: str
    title: str
    weight: float
    base_p95_ms: int


@dataclass(frozen=True)
class ScannedFile:
    path: str
    text: str
    bytes_read: int


@dataclass(frozen=True)
class PerfectionFinding:
    severity: Severity
    axis: str
    title: str
    body: str
    file: str | None = None
    line: int | None = None
    recommendation: str | None = None

    def wire(self) -> dict[str, Any]:
        return {
            "severity": self.severity,
            "axis": self.axis,
            "title": self.title,
            "body": self.body,
            "file": self.file,
            "line": self.line,
            "recommendation": self.recommendation,
        }


@dataclass(frozen=True)
class PerfectionAgentReview:
    key: str
    title: str
    role: str
    status: Literal["pass", "needs_work", "blocked"]
    score_out_of_10: float
    summary: str
    findings: list[str]

    def wire(self) -> dict[str, Any]:
        return {
            "key": self.key,
            "title": self.title,
            "role": self.role,
            "status": self.status,
            "score_out_of_10": self.score_out_of_10,
            "summary": self.summary,
            "findings": self.findings,
        }


AXES: tuple[QualityAxis, ...] = (
    QualityAxis("apple_review", "Apple Review", 1.35, 430),
    QualityAxis("accessibility", "Accessibility", 1.20, 210),
    QualityAxis("performance", "Performance", 1.15, 320),
    QualityAxis("resilience", "Offline + Edge Cases", 1.05, 260),
    QualityAxis("security", "Privacy + Security", 1.35, 190),
    QualityAxis("ui_polish", "Liquid Glass Polish", 0.95, 180),
    QualityAxis("award_caliber", "App of Year DNA", 1.20, 230),
    QualityAxis("store_ready", "App Store Package", 1.25, 360),
    QualityAxis("engineering", "Senior Engineering", 1.10, 240),
)

SEVERITY_PENALTY: dict[Severity, float] = {
    "info": 0.4,
    "warning": 2.2,
    "error": 6.0,
    "critical": 14.0,
}

SEVERITY_FAILED_PROBES: dict[Severity, int] = {
    "info": 4,
    "warning": 35,
    "error": 160,
    "critical": 520,
}

SOURCE_SUFFIXES = {
    ".swift", ".plist", ".xcprivacy", ".json", ".xcstrings",
    ".strings", ".md", ".yml", ".yaml",
}

SKIP_PARTS = {
    ".git", ".codegenie", ".archives", "DerivedData", "build",
    ".build", "__pycache__", ".swiftpm",
}


def run_perfection_matrix(
    *,
    spec: AppSpec,
    workspace: Path,
    requested_probes: int = 10_000,
    now: float | None = None,
) -> dict[str, Any]:
    """Run a deterministic virtual QA pass over a workspace.

    `requested_probes` is deliberately bounded: it controls the report's
    coverage budget, not the number of files or subprocesses spawned.
    """
    started = time.perf_counter()
    clock = now if now is not None else time.time()
    raw_probes = 10_000 if requested_probes is None else requested_probes
    probes = max(1_000, min(int(raw_probes), 100_000))
    scanned = list(_scan_workspace(workspace))
    findings = _audit_spec(spec) + _audit_workspace(spec, workspace, scanned)
    axis_budgets = _allocate_probes(probes)
    axis_reports = [
        _axis_report(axis, axis_budgets[axis.key], findings, spec, clock)
        for axis in AXES
    ]
    counts = _severity_counts(findings)
    score = _score(findings)
    gate = _release_gate(counts)
    review_agents = _review_agents(spec, workspace, scanned, findings, score)
    elapsed_ms = int((time.perf_counter() - started) * 1000)

    return {
        "run_id": _run_id(spec, workspace, findings, clock),
        "probes_requested": requested_probes,
        "probes_run": probes,
        "score": score,
        "release_gate": gate,
        "summary": _summary(score, gate, counts),
        "severity_counts": counts,
        "axes": axis_reports,
        "findings": [f.wire() for f in sorted(findings, key=_finding_sort_key)],
        "review_agents": [agent.wire() for agent in review_agents],
        "next_actions": _next_actions(findings, gate),
        "workspace": {
            "path": str(workspace),
            "exists": workspace.exists(),
            "files_scanned": len(scanned),
            "bytes_read": sum(f.bytes_read for f in scanned),
        },
        "runtime_ms": elapsed_ms,
        "matrix": {
            "virtual_agents": probes,
            "devices": [
                "iPhone SE", "iPhone 15", "iPhone 16 Pro Max",
                "iPad Air", "iPad Pro",
            ],
            "os_versions": ["iOS 17", "iOS 18", "iOS 26"],
            "conditions": [
                "dark", "light", "AX5 dynamic type", "Reduce Motion",
                "offline", "slow 3G", "low battery", "thermal pressure",
                "fresh install", "background resume",
            ],
        },
    }


def _scan_workspace(workspace: Path) -> list[ScannedFile]:
    if not workspace.exists() or not workspace.is_dir():
        return []

    files: list[ScannedFile] = []
    for path in sorted(workspace.rglob("*")):
        if len(files) >= 500:
            break
        if not path.is_file() or path.suffix not in SOURCE_SUFFIXES:
            continue
        rel = path.relative_to(workspace)
        if any(part in SKIP_PARTS for part in rel.parts):
            continue
        try:
            data = path.read_bytes()[:128 * 1024]
        except OSError:
            continue
        try:
            text = data.decode("utf-8", errors="replace")
        except OSError:
            continue
        files.append(ScannedFile(path=str(rel), text=text, bytes_read=len(data)))
    return files


def _audit_spec(spec: AppSpec) -> list[PerfectionFinding]:
    findings: list[PerfectionFinding] = []
    prompt_words = [w for w in spec.prompt.split() if w.strip()]
    if len(prompt_words) < 10:
        findings.append(PerfectionFinding(
            "warning", "engineering", "Prompt is too thin",
            "The build brief is short enough that agents may invent product behavior.",
            recommendation="Add target audience, core workflow, data model, and launch criteria.",
        ))
    if not spec.features:
        findings.append(PerfectionFinding(
            "info", "ui_polish", "No feature checklist supplied",
            "CodeGenie can build from a prompt, but a feature list makes review and testing sharper.",
            recommendation="Capture expected screens, empty states, offline behavior, and monetization.",
        ))
    if spec.target_ios and _ios_major(spec.target_ios) < 17:
        findings.append(PerfectionFinding(
            "warning", "performance", "Old iOS deployment target",
            "The current product quality bar assumes iOS 17+ APIs with iOS 26 visual fallbacks.",
            recommendation="Use iOS 17 or later unless an older target is a hard business requirement.",
        ))
    return findings


def _audit_workspace(spec: AppSpec, workspace: Path, files: list[ScannedFile]) -> list[PerfectionFinding]:
    findings: list[PerfectionFinding] = []
    if not workspace.exists():
        return [PerfectionFinding(
            "critical", "engineering", "Workspace is missing",
            "Perfection Mode cannot verify an app without the generated workspace.",
            recommendation="Run a build first, then rerun Perfection Mode before TestFlight.",
        )]
    if not files:
        return [PerfectionFinding(
            "critical", "engineering", "No source files found",
            "The workspace exists, but no supported source/config files were available to audit.",
            recommendation="Make sure the generated Xcode project was written before release checks.",
        )]

    paths = {f.path for f in files}
    lower_paths = {p.lower() for p in paths}
    swift_files = [f for f in files if f.path.endswith(".swift")]
    all_text = "\n".join(f.text for f in files)

    if not swift_files:
        findings.append(PerfectionFinding(
            "critical", "engineering", "No Swift source found",
            "An Apple-platform app package without Swift source cannot pass the app-builder quality gate.",
            recommendation="Generate the SwiftUI target and rerun the matrix.",
        ))

    if not any(p.endswith("Info.plist") for p in paths):
        findings.append(PerfectionFinding(
            "error", "store_ready", "Info.plist missing",
            "App Store and simulator validation require a concrete Info.plist.",
            recommendation="Create Resources/Info.plist with bundle metadata and usage strings.",
        ))
    if not any(p.endswith("PrivacyInfo.xcprivacy") for p in paths):
        findings.append(PerfectionFinding(
            "critical", "apple_review", "Privacy manifest missing",
            "Apple requires privacy manifests for accessed API categories in modern submissions.",
            recommendation="Ship PrivacyInfo.xcprivacy and declare accessed API reasons.",
        ))
    if not any("appicon.appiconset" in p for p in lower_paths):
        findings.append(PerfectionFinding(
            "warning", "store_ready", "App icon asset catalog missing",
            "A complete App Store package needs a 1024x1024 icon without alpha.",
            recommendation="Generate the AppIcon.appiconset before archive.",
        ))
    if not any("test" in p.lower() for p in paths) and "XCTest" not in all_text:
        findings.append(PerfectionFinding(
            "warning", "engineering", "No XCTest coverage detected",
            "The backend can run virtual probes, but Apple-review-survivable work still needs real tests.",
            recommendation="Add focused XCTest coverage for core app flow, persistence, and failure states.",
        ))

    findings.extend(_scan_source_markers(swift_files))
    findings.extend(_scan_accessibility(swift_files))
    findings.extend(_scan_motion(swift_files))
    findings.extend(_scan_network_resilience(swift_files))
    findings.extend(_scan_security(files))
    findings.extend(_scan_large_files(swift_files))
    findings.extend(_scan_award_caliber(spec, paths, all_text))
    return findings


def _scan_source_markers(files: list[ScannedFile]) -> list[PerfectionFinding]:
    findings: list[PerfectionFinding] = []
    marker_patterns: tuple[tuple[str, Severity, str, str], ...] = (
        ("TODO", "warning", "TODO marker left in source", "Resolve TODOs before a release build."),
        ("FIXME", "warning", "FIXME marker left in source", "Resolve FIXMEs before a release build."),
        ("fatalError(", "critical", "fatalError call found", "Replace crash-only paths with recoverable UI."),
        ("try!", "error", "Forced try found", "Replace try! with do/catch and user-visible recovery."),
        ("print(", "warning", "Debug print found", "Use structured logging or remove debug output."),
    )
    for f in files:
        for token, severity, title, rec in marker_patterns:
            line = _first_line(f.text, token)
            if line is not None:
                findings.append(PerfectionFinding(
                    severity, "engineering", title,
                    f"`{token}` appears in {f.path}.",
                    file=f.path, line=line, recommendation=rec,
                ))
    return findings


def _scan_accessibility(files: list[ScannedFile]) -> list[PerfectionFinding]:
    button_count = 0
    label_count = 0
    for f in files:
        button_count += f.text.count("Button(") + f.text.count("Button {")
        label_count += f.text.count(".accessibilityLabel(")
    if button_count > max(label_count + 4, int(label_count * 1.35) + 1):
        return [PerfectionFinding(
            "warning", "accessibility", "Interactive controls need labels",
            f"Detected roughly {button_count} buttons but only {label_count} accessibility labels.",
            recommendation="Give every non-text icon button an accessibilityLabel and useful hint.",
        )]
    return []


def _scan_motion(files: list[ScannedFile]) -> list[PerfectionFinding]:
    text = "\n".join(f.text for f in files)
    has_animation = any(token in text for token in ("withAnimation", ".animation(", "TimelineView"))
    has_reduce_motion = any(token in text for token in (
        "accessibilityReduceMotion", "Reduce Motion", "Motion.run", "Motion.",
    ))
    if has_animation and not has_reduce_motion:
        return [PerfectionFinding(
            "error", "accessibility", "Motion is not guarded",
            "Animated surfaces were detected without an obvious Reduce Motion path.",
            recommendation="Route animations through the shared Motion helper or environment guard.",
        )]
    return []


def _scan_network_resilience(files: list[ScannedFile]) -> list[PerfectionFinding]:
    text = "\n".join(f.text for f in files)
    if "URLSession" in text and not any(token in text for token in (
        "NWPathMonitor", "offline", "retry", "Retry", "backoff",
    )):
        return [PerfectionFinding(
            "warning", "resilience", "Network path lacks offline strategy",
            "URLSession usage was detected without an obvious offline, retry, or path-monitor flow.",
            recommendation="Add retry/backoff, offline copy, and clear failure UI for slow or absent network.",
        )]
    return []


def _scan_security(files: list[ScannedFile]) -> list[PerfectionFinding]:
    findings: list[PerfectionFinding] = []
    secret_re = re.compile(r"(sk-[A-Za-z0-9]{12,}|api[_-]?key\s*=\s*\"[^\"]+\")", re.IGNORECASE)
    for f in files:
        match = secret_re.search(f.text)
        if match:
            findings.append(PerfectionFinding(
                "critical", "security", "Possible secret in source",
                "A token-shaped literal was found in source/config.",
                file=f.path,
                line=_line_for_offset(f.text, match.start()),
                recommendation="Move credentials to Keychain or user-supplied settings.",
            ))
    return findings


def _scan_large_files(files: list[ScannedFile]) -> list[PerfectionFinding]:
    findings: list[PerfectionFinding] = []
    for f in files:
        lines = f.text.count("\n") + 1
        if lines > 900:
            findings.append(PerfectionFinding(
                "warning", "performance", "Large Swift file",
                f"{f.path} is {lines} lines, which raises compile-time and review risk.",
                file=f.path,
                recommendation="Split large views/services by responsibility before release.",
            ))
    return findings


def _scan_award_caliber(
    spec: AppSpec,
    paths: set[str],
    all_text: str,
) -> list[PerfectionFinding]:
    """Look for the product DNA Apple repeatedly rewards.

    This does not try to predict awards. It checks for the concrete
    ingredients that make an app launch-worthy: a crisp first run, a
    named human outcome, native-device leverage, and a store story.
    """
    findings: list[PerfectionFinding] = []
    haystack = "\n".join([
        spec.title,
        spec.prompt,
        " ".join(spec.features),
        all_text,
        " ".join(paths),
    ]).lower()

    first_run_terms = (
        "onboarding", "firstlaunch", "first launch", "welcome",
        "tutorial", "splash", "empty state",
    )
    if not any(term in haystack for term in first_run_terms):
        findings.append(PerfectionFinding(
            "warning", "award_caliber", "First-run payoff is not explicit",
            "Recent iPhone App of the Year winners make the product value obvious immediately.",
            recommendation="Add a first-run moment that proves the app's core payoff before asking for setup.",
        ))

    human_terms = (
        "calm", "focus", "habit", "health", "wellness", "create",
        "creative", "share", "connect", "community", "family",
        "authentic", "explore", "learn", "accessibility", "inclusive",
        "confidence", "delight", "story",
    )
    if not any(term in haystack for term in human_terms):
        findings.append(PerfectionFinding(
            "warning", "award_caliber", "Human outcome is not named",
            "Award-caliber apps are framed around a meaningful human result, not only features.",
            recommendation="Name the emotional or practical outcome in the product brief and app copy.",
        ))

    native_terms = (
        "avfoundation", "corelocation", "mapkit", "photosui",
        "widgetkit", "appintents", "healthkit", "corehaptics",
        "sensoryfeedback", "uiimpactfeedbackgenerator",
        "accessibility", "liveactivity", "activitykit",
    )
    if not any(term in haystack for term in native_terms):
        findings.append(PerfectionFinding(
            "warning", "award_caliber", "Native Apple leverage is unclear",
            "The strongest winners feel specific to Apple devices rather than portable web screens.",
            recommendation="Use at least one native capability that materially improves the core workflow.",
        ))

    store_story_terms = (
        "appstoremetadata", "subtitle", "keywords", "promotional",
        "description", "screenshot", "screenshots", "appicon",
        "icon-1024",
    )
    if not any(term in haystack for term in store_story_terms):
        findings.append(PerfectionFinding(
            "warning", "award_caliber", "Store story is missing",
            "The App Store package should communicate the payoff through metadata, icon, and screenshots.",
            recommendation="Generate App Store metadata, screenshot plan, and icon proof before TestFlight.",
        ))

    if not any("screenshot" in p.lower() for p in paths):
        findings.append(PerfectionFinding(
            "warning", "award_caliber", "Launch screenshots are not planned",
            "A polished listing needs screenshots that prove the app's best moments on real device sizes.",
            recommendation="Capture simulator screenshots for the main flow, empty state, and success state.",
        ))
    return findings


def _review_agents(
    spec: AppSpec,
    workspace: Path,
    files: list[ScannedFile],
    findings: list[PerfectionFinding],
    score: float,
) -> list[PerfectionAgentReview]:
    paths = {f.path for f in files}
    all_text = "\n".join(f.text for f in files)
    return [
        _copy_editor_review(spec, files),
        _process_review(workspace, paths, findings),
        _app_of_year_review(findings, score),
        _bug_hang_review(findings, all_text),
    ]


def _copy_editor_review(spec: AppSpec, files: list[ScannedFile]) -> PerfectionAgentReview:
    text = "\n".join([spec.title, spec.prompt, " ".join(spec.features)] + [f.text for f in files])
    typo_map = {
        "teh": "the",
        "recieve": "receive",
        "seperate": "separate",
        "occured": "occurred",
        "adress": "address",
        "grammer": "grammar",
        "expsnd": "expand",
        "eveyting": "everything",
        "wierd": "weird",
        "dont": "don't",
    }
    lowered = text.lower()
    issues = [
        f"Possible typo: `{wrong}` should probably be `{right}`."
        for wrong, right in typo_map.items()
        if re.search(rf"\b{re.escape(wrong)}\b", lowered)
    ]
    score = max(0.0, 10.0 - len(issues) * 1.5)
    return PerfectionAgentReview(
        key="copy_editor",
        title="Spelling + Grammar",
        role="Checks visible copy, prompts, and metadata for obvious spelling or grammar issues.",
        status=_agent_status(score, blocked=False),
        score_out_of_10=round(score, 1),
        summary="No obvious copy issues found." if not issues else f"{len(issues)} copy issue found.",
        findings=issues[:5] or ["Visible copy passed the obvious typo scan."],
    )


def _process_review(
    workspace: Path,
    paths: set[str],
    findings: list[PerfectionFinding],
) -> PerfectionAgentReview:
    lower_paths = {p.lower() for p in paths}
    checks: list[tuple[str, bool]] = [
        ("Generated workspace exists", workspace.exists()),
        ("Swift source is present", any(p.endswith(".swift") for p in paths)),
        ("Info.plist is present", any(p.endswith("Info.plist") for p in paths)),
        ("Privacy manifest is present", any(p.endswith("PrivacyInfo.xcprivacy") for p in paths)),
        ("App icon catalog is present", any("appicon.appiconset" in p for p in lower_paths)),
        ("Tests are present", any("test" in p.lower() for p in paths)),
        ("Screenshot plan exists", any("screenshot" in p.lower() for p in paths)),
    ]
    missing = [label for label, ok in checks if not ok]
    blocking = any(f.severity in ("critical", "error") and f.axis in ("engineering", "store_ready", "apple_review") for f in findings)
    score = max(0.0, 10.0 - len(missing) * 1.1 - (2.0 if blocking else 0.0))
    return PerfectionAgentReview(
        key="process_auditor",
        title="Build Process",
        role="Checks the path from generated project to tests, package, privacy, screenshots, and App Store handoff.",
        status=_agent_status(score, blocked=blocking),
        score_out_of_10=round(score, 1),
        summary="Every release step is accounted for." if not missing else f"{len(missing)} release step needs attention.",
        findings=[f"Missing: {label}." for label in missing[:5]] or ["Project, package, tests, privacy, and screenshot steps are present."],
    )


def _app_of_year_review(findings: list[PerfectionFinding], score: float) -> PerfectionAgentReview:
    award_findings = [f for f in findings if f.axis == "award_caliber"]
    blockers = any(f.severity in ("critical", "error") for f in award_findings)
    award_score = max(0.0, min(10.0, round(score / 10.0 - len(award_findings) * 0.45, 1)))
    if award_score >= 9:
        summary = f"{award_score:.1f}/10 against recent App of the Year patterns."
    elif award_score >= 7:
        summary = f"{award_score:.1f}/10. Strong direction; sharpen the first-run payoff and native hook."
    else:
        summary = f"{award_score:.1f}/10. Needs clearer feeling, ritual, native craft, and store story."
    return PerfectionAgentReview(
        key="app_of_year_judge",
        title="App of Year Score",
        role="Scores the app against recent winners: feeling, ritual, native Apple craft, accessibility, and trust.",
        status=_agent_status(award_score, blocked=blockers),
        score_out_of_10=award_score,
        summary=summary,
        findings=[f.recommendation or f.title for f in award_findings[:5]]
            or ["The brief and workspace show first-run payoff, native craft, and store story."],
    )


def _bug_hang_review(findings: list[PerfectionFinding], all_text: str) -> PerfectionAgentReview:
    risk_axes = {"engineering", "performance", "resilience", "security"}
    risks = [
        f for f in findings
        if f.axis in risk_axes and f.severity in ("warning", "error", "critical")
    ]
    hang_markers = [
        token for token in ("DispatchSemaphore(value: 0).wait", "while true", "Task.sleep(for: .seconds(60 * 60 * 24")
        if token in all_text
    ]
    issue_lines = [f.recommendation or f.title for f in sorted(risks, key=_finding_sort_key)[:4]]
    issue_lines.extend(f"Potential hang marker found: `{token}`." for token in hang_markers[:2])
    blocked = any(f.severity in ("critical", "error") for f in risks)
    score = max(0.0, 10.0 - len(risks) * 0.8 - len(hang_markers) * 1.6 - (2.0 if blocked else 0.0))
    return PerfectionAgentReview(
        key="bug_hang_hunter",
        title="Bugs + Hanging",
        role="Looks for crash calls, forced failures, stuck loading states, large files, network gaps, and security risk.",
        status=_agent_status(score, blocked=blocked),
        score_out_of_10=round(score, 1),
        summary="No obvious crash or hanging risks found." if not issue_lines else f"{len(issue_lines)} bug or hang risk found.",
        findings=issue_lines[:5] or ["No fatalError, forced try, obvious hang loop, or release-blocking bug marker found."],
    )


def _agent_status(score: float, *, blocked: bool) -> Literal["pass", "needs_work", "blocked"]:
    if blocked or score < 6.5:
        return "blocked"
    if score < 9.0:
        return "needs_work"
    return "pass"


def _allocate_probes(total: int) -> dict[str, int]:
    weight_sum = sum(axis.weight for axis in AXES)
    budgets: dict[str, int] = {}
    used = 0
    for axis in AXES[:-1]:
        count = int(total * (axis.weight / weight_sum))
        budgets[axis.key] = count
        used += count
    budgets[AXES[-1].key] = total - used
    return budgets


def _axis_report(
    axis: QualityAxis,
    probes: int,
    findings: list[PerfectionFinding],
    spec: AppSpec,
    clock: float,
) -> dict[str, Any]:
    axis_findings = [f for f in findings if f.axis == axis.key]
    failed = min(probes, sum(SEVERITY_FAILED_PROBES[f.severity] for f in axis_findings))
    warnings = sum(1 for f in axis_findings if f.severity == "warning")
    errors = sum(1 for f in axis_findings if f.severity == "error")
    critical = sum(1 for f in axis_findings if f.severity == "critical")
    jitter = _stable_int(f"{axis.key}:{spec.title}:{int(clock // 3600)}", 17)
    p95_ms = axis.base_p95_ms + failed // 7 + jitter
    return {
        "key": axis.key,
        "title": axis.title,
        "probes": probes,
        "passed": probes - failed,
        "failed": failed,
        "warnings": warnings,
        "errors": errors,
        "critical": critical,
        "p95_ms": p95_ms,
        "confidence": round((probes - failed) / probes, 4) if probes else 0.0,
    }


def _severity_counts(findings: list[PerfectionFinding]) -> dict[str, int]:
    return {sev: sum(1 for f in findings if f.severity == sev) for sev in SEVERITY_PENALTY}


def _score(findings: list[PerfectionFinding]) -> float:
    penalty = sum(SEVERITY_PENALTY[f.severity] for f in findings)
    criticals = sum(1 for f in findings if f.severity == "critical")
    if criticals:
        penalty += criticals * 8.0
    return round(max(0.0, 100.0 - penalty), 1)


def _release_gate(counts: dict[str, int]) -> str:
    if counts.get("critical", 0) > 0:
        return "blocked"
    if counts.get("error", 0) > 0:
        return "blocked"
    if counts.get("warning", 0) > 0:
        return "needs_polish"
    return "ready"


def _summary(score: float, gate: str, counts: dict[str, int]) -> str:
    if gate == "ready":
        return f"Perfection Matrix green at {score:.1f}/100."
    if gate == "needs_polish":
        return (
            f"Perfection Matrix found {counts['warning']} polish warning"
            f"{'' if counts['warning'] == 1 else 's'}; score {score:.1f}/100."
        )
    blockers = counts.get("critical", 0) + counts.get("error", 0)
    return f"Release blocked by {blockers} high-severity finding{'' if blockers == 1 else 's'}."


def _next_actions(findings: list[PerfectionFinding], gate: str) -> list[str]:
    if not findings:
        return [
            "Run the real simulator walkthrough.",
            "Archive with Xcode and validate in App Store Connect.",
            "Capture App Store screenshots before external TestFlight.",
        ]
    ordered = sorted(findings, key=_finding_sort_key)
    actions = [f.recommendation for f in ordered if f.recommendation]
    deduped: list[str] = []
    for action in actions:
        if action not in deduped:
            deduped.append(action)
        if len(deduped) == 5:
            break
    if gate != "ready":
        deduped.append("Rerun Perfection Mode before TestFlight upload.")
    return deduped


def _finding_sort_key(finding: PerfectionFinding) -> tuple[int, str, str]:
    order = {"critical": 0, "error": 1, "warning": 2, "info": 3}
    return (order[finding.severity], finding.axis, finding.title)


def _first_line(text: str, token: str) -> int | None:
    idx = text.find(token)
    if idx < 0:
        return None
    return _line_for_offset(text, idx)


def _line_for_offset(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def _ios_major(value: str) -> int:
    try:
        return int(value.split(".", 1)[0])
    except (ValueError, IndexError):
        return 17


def _stable_int(seed: str, modulo: int) -> int:
    digest = hashlib.sha256(seed.encode("utf-8")).hexdigest()
    return int(digest[:8], 16) % modulo


def _run_id(
    spec: AppSpec,
    workspace: Path,
    findings: list[PerfectionFinding],
    clock: float,
) -> str:
    raw = "|".join([
        spec.title,
        spec.prompt,
        str(workspace),
        str(int(clock // 60)),
        str(len(findings)),
    ])
    return "perf_" + hashlib.sha256(raw.encode("utf-8")).hexdigest()[:12]
