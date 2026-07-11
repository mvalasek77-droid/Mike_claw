"""Incident report generator.

Produces a self-contained report a parent can print or hand to Roblox,
police, or NCMEC: situation summary in plain language, the danger patterns
the observations match (with explanation of how those patterns typically
progress), a full alert timeline, behavioral signs to check for at home,
a hash-verified evidence inventory, and the response playbook.

The report is deliberately framed as observations, not accusations — that
framing is what makes it usable by investigators and safe to write.
"""

import html
import os
from datetime import datetime, timezone

from . import education, glossary
from .signals import Severity

# One-paragraph primer so a reader who has never heard of Roblox — a
# grandparent, an officer, a school counselor — can follow the report.
ROBLOX_PRIMER = (
    "For readers new to Roblox: Roblox is an online platform used heavily by "
    "children, where millions of user-made games ('experiences') share one "
    "social layer — any player can meet any other player inside a game, send "
    "them a friend request, and chat with them. Accounts have public profile "
    "pages (visible to anyone) showing a self-description ('bio'), a friend "
    "list, and when the account was created. Roblox has its own virtual "
    "currency (Robux) and filters children's chats, but private messages are "
    "readable only by Roblox's own moderators — no outside tool can see them. "
    "This report is therefore based on the public information above, plus "
    "screenshots supplied by the parent."
)

DISCLAIMER = (
    "This report contains automated observations of publicly visible Roblox "
    "account information, plus evidence supplied by the parent. It states "
    "facts and pattern matches; it does not accuse any person of a crime. "
    "Determinations belong to Roblox Trust & Safety and law enforcement."
)

CSAM_WARNING = (
    "IMPORTANT — evidence handling: never save, upload, or forward sexual "
    "imagery of a minor, even as evidence; possessing or transmitting it is "
    "illegal regardless of intent. If such imagery exists, describe it to "
    "investigators and let them retrieve it through legal process."
)

_SEVERITY_ORDER = {Severity.ELEVATED.value: 0, Severity.WATCH.value: 1, Severity.INFO.value: 2}
_SEVERITY_LABEL = {
    Severity.ELEVATED.value: "Elevated — talk with your child soon",
    Severity.WATCH.value: "Worth a look",
    Severity.INFO.value: "Informational",
}


def _situation_summary(child: dict, alerts: list[dict]) -> str:
    if not alerts:
        return (
            f"No safety alerts are currently recorded for the Roblox account "
            f"@{child['roblox_username']}. This report documents the monitoring "
            f"configuration and available evidence."
        )
    counts = {sev: 0 for sev in _SEVERITY_ORDER}
    for a in alerts:
        counts[a["severity"]] = counts.get(a["severity"], 0) + 1
    top = sorted(alerts, key=lambda a: _SEVERITY_ORDER.get(a["severity"], 9))[0]
    parts = [
        f"Monitoring of the Roblox account @{child['roblox_username']} "
        f"(user id {child['roblox_user_id']}) has recorded "
        f"{counts[Severity.ELEVATED.value]} elevated, {counts[Severity.WATCH.value]} watch-level, "
        f"and {counts[Severity.INFO.value]} informational alert(s).",
        f"The most serious current observation: {top['title']}.",
    ]
    if any(a["type"] == "off_platform_handle" for a in alerts):
        parts.append(
            "At least one contact's profile advertises a way to move "
            "conversations off Roblox. Moving chat to outside apps removes "
            "Roblox's filters and moderation and is the pivot point described "
            "in nearly every documented grooming case on the platform — this "
            "observation deserves attention first."
        )
    return " ".join(parts)


def build_report_markdown(child: dict, alerts: list[dict], evidence: list[dict]) -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    signal_types = {a["type"] for a in alerts}
    dangers = education.dangers_for_signal_types(signal_types)
    alerts_sorted = sorted(
        alerts, key=lambda a: (_SEVERITY_ORDER.get(a["severity"], 9), a["observed_at"]))

    lines: list[str] = []
    add = lines.append

    add("# RobloxGuard incident report")
    add("")
    add(f"- **Generated:** {now}")
    add(f"- **Child's Roblox account:** @{child['roblox_username']} "
        f"(user id {child['roblox_user_id']})")
    add(f"- **Monitoring consented by:** {child['consent_attested_by']} "
        f"on {child['consent_attested_at'][:10]}")
    add("")
    add(f"> {DISCLAIMER}")
    add("")
    add(f"> {ROBLOX_PRIMER}")
    add("")

    add("## 1. Situation summary")
    add("")
    add(_situation_summary(child, alerts))
    add("")

    if dangers:
        add("## 2. What these observations can mean")
        add("")
        add("The observed signals match the following documented risk patterns. "
            "Pattern matches are context, not conclusions.")
        add("")
        for d in dangers:
            add(f"### {d['title']}")
            add("")
            add(d["summary"])
            if d["progression"]:
                add("")
                add("Typical progression:")
                add("")
                for i, step in enumerate(d["progression"], 1):
                    add(f"{i}. {step}")
            add("")

    add("## 3. Alert timeline")
    add("")
    if not alerts_sorted:
        add("_No alerts recorded._")
    for a in alerts_sorted:
        status = " (marked handled)" if a["acknowledged"] else ""
        add(f"### [{_SEVERITY_LABEL.get(a['severity'], a['severity'])}] {a['title']}{status}")
        add("")
        add(f"- Observed: {a['observed_at']}")
        if a.get("subject_username"):
            add(f"- Account involved: @{a['subject_username']} "
                f"(user id {a['subject_user_id']})")
        for fact in a["facts"]:
            add(f"- {fact}")
        add("")
        add(f"**Suggested action:** {a['guidance']}")
        add("")

    add("## 4. Signs to check for at home")
    add("")
    add("The platform can only show part of the picture. Signs only a parent "
        "can observe:")
    add("")
    for sign in education.BEHAVIORAL_SIGNS:
        add(f"- {sign}")
    add("")
    add("**Act the same day if any of these have happened:**")
    add("")
    for flag in education.IMMEDIATE_RED_FLAGS:
        add(f"- {flag}")
    add("")

    add("## 5. Evidence inventory")
    add("")
    add(f"> {CSAM_WARNING}")
    add("")
    if not evidence:
        add("_No evidence captured yet._")
    else:
        add("Each item was fingerprinted (SHA-256) at capture time; "
            "investigators can verify files have not been altered since.")
        add("")
        add("| # | Kind | Captured (UTC) | SHA-256 | Note |")
        add("|---|------|----------------|---------|------|")
        for e in evidence:
            kind = e["kind"].replace("_", " ")
            add(f"| {e['id']} | {kind} | {e['captured_at'][:19]} | "
                f"`{e['sha256'][:16]}…` | {e['note'] or os.path.basename(e['path'])} |")
    add("")

    # Glossary of exactly the terms this report used, so nothing above
    # requires prior Roblox knowledge.
    term_sources = [_situation_summary(child, alerts)]
    for a in alerts_sorted:
        term_sources += [a["title"], a["guidance"], *a["facts"]]
    terms = glossary.explain(*term_sources)
    if terms:
        add("## 6. Terms used in this report")
        add("")
        for entry in terms:
            add(f"- **{entry['term']}** — {entry['definition']}")
        add("")

    add("## 7. Recommended next steps")
    add("")
    for i, step in enumerate(education.RESPONSE_PLAYBOOK, 1):
        add(f"{i}. {step}")
    add("")
    add("### Reporting channels")
    add("")
    add("- **Roblox Report Abuse** (moderators can read the actual chats — no "
        "outside app can): https://en.help.roblox.com/hc/en-us/articles/203312410")
    add("- **NCMEC CyberTipline**: https://report.cybertip.org")
    add("- **Emergency**: 911 or your local emergency number")
    add("")
    return "\n".join(lines)


def build_report_html(child: dict, alerts: list[dict], evidence: list[dict]) -> str:
    """Print-friendly standalone HTML wrapper around the markdown content.

    Kept dependency-free: the markdown is rendered inside <pre-wrap> prose
    styling rather than pulling in a markdown library.
    """
    md = build_report_markdown(child, alerts, evidence)
    body = html.escape(md)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>RobloxGuard report — @{html.escape(child['roblox_username'])}</title>
<style>
  body {{ font: 15px/1.6 -apple-system, system-ui, sans-serif; color: #1a1a1a;
          max-width: 780px; margin: 2rem auto; padding: 0 1rem; }}
  pre {{ white-space: pre-wrap; word-wrap: break-word; font: inherit; }}
  @media print {{ body {{ margin: 0; }} }}
</style>
</head>
<body><pre>{body}</pre></body>
</html>"""
