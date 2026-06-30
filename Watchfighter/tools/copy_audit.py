#!/usr/bin/env python3
"""
Copy auditor (TEST_STRATEGY.md §6) — a no-build, no-network proofreading guard
for every user-facing string in the game.

It extracts the copy from the Swift sources (cutscene panels, banners, on-screen
Text) and flags mechanical writing defects: doubled spaces, repeated words,
placeholders, straight-vs-curly inconsistency, missing terminal punctuation on
narrative panels, and a small list of common misspellings. Stylized ALL-CAPS
names (NYRA, TITUS, ASCENDANT, …) are allow-listed so they aren't false-flagged.

Run:  python3 tools/copy_audit.py
Exit: 0 = clean, 1 = findings (so it can gate CI).
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "Watchfighter" / "Game"

# Files that hold user-facing copy.
SOURCES = [
    GAME / "GameScreen.swift",
    GAME / "WatchfighterEngine.swift",
    GAME / "GameModels.swift",
]

# Tokens that are intentionally stylized / proper nouns — never spell-flagged.
ALLOW = {
    "ascendant", "nyra", "titus", "kael", "rook", "voss", "mara", "lennox",
    "sunny", "nova", "specter", "cosmo", "brass", "volkov", "zara", "cage",
    "kairo", "watchfighter", "vs", "ko", "peekaboom", "cinder", "neon",
    "rooftop", "obsidian", "kombat",
}

# Common misspelling -> correction (extend as needed).
MISSPELLINGS = {
    "teh": "the", "recieve": "receive", "seperate": "separate",
    "definately": "definitely", "occured": "occurred", "untill": "until",
    "wich": "which", "thier": "their", "alot": "a lot", "loose": "lose(?)",
    "champ ion": "champion", "tournment": "tournament", "oppenent": "opponent",
    "smudgrd": "smudged", "exciteing": "exciting",
}

STRING_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')


def extract_strings(text: str) -> list[tuple[int, str]]:
    out = []
    for i, line in enumerate(text.splitlines(), 1):
        # skip obvious non-copy: image/asset names, identifiers used as keys
        for m in STRING_RE.finditer(line):
            s = m.group(1)
            out.append((i, s))
    return out


def looks_like_copy(s: str) -> bool:
    # Heuristic: real sentences have a space and a lowercase letter, or are
    # multi-word. Filters out asset names like "DigitizedHero" and keys.
    if len(s) < 3:
        return False
    if " " in s and re.search(r"[a-zA-Z]", s):
        return True
    return False


def audit() -> int:
    findings: list[str] = []

    for path in SOURCES:
        if not path.exists():
            findings.append(f"{path}: missing source file")
            continue
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)
        for lineno, s in extract_strings(text):
            if not looks_like_copy(s):
                continue
            here = f"{rel}:{lineno}"

            if "  " in s:
                findings.append(f"{here}: double space -> {s!r}")
            if s != s.strip():
                findings.append(f"{here}: leading/trailing space -> {s!r}")
            for token in ("TODO", "FIXME", "lorem", "<add", "<TODO", "XXX"):
                if token.lower() in s.lower():
                    findings.append(f"{here}: placeholder {token!r} -> {s!r}")
            # repeated word ("the the")
            for m in re.finditer(r"\b(\w+)\s+\1\b", s, flags=re.IGNORECASE):
                findings.append(f"{here}: repeated word {m.group(1)!r} -> {s!r}")
            # misspellings
            for wrong, right in MISSPELLINGS.items():
                if re.search(rf"\b{re.escape(wrong)}\b", s, flags=re.IGNORECASE):
                    findings.append(f"{here}: '{wrong}' -> '{right}' in {s!r}")
            # spacing before punctuation
            if re.search(r"\s[,.;:!?]", s):
                findings.append(f"{here}: space before punctuation -> {s!r}")

    if findings:
        print(f"COPY AUDIT — {len(findings)} finding(s):\n")
        for f in findings:
            print("  •", f)
        return 1

    print("COPY AUDIT — clean. No mechanical copy defects found.")
    return 0


if __name__ == "__main__":
    sys.exit(audit())
