"""Head-to-head model ranking — Cursor's "let two models compete and pick
the winner" mechanic, ported into the Genie Swarm.

Use case: the Coder agent runs twice in parallel against the same task,
once on Claude and once on GPT-5. A third model (the **judge**) reads
both candidate diffs and decides which to apply. The losing diff is
discarded. We get the marginal quality of an ensemble at the cost of
two parallel runs.

This file is the rank engine. The orchestrator opts into it by setting
`SwarmConfig.parallel_models = True` and providing more than one client
in the `model_overrides` map.
"""
from __future__ import annotations

import asyncio
import json
import re
from dataclasses import dataclass

from .llm import LLMClient
from .models import Message


@dataclass
class Candidate:
    label: str           # human label, e.g. "claude" or "gpt"
    model: str           # canonical model id
    output: str          # the agent's final assistant text or rendered diff
    usage: dict[str, int]


@dataclass
class Verdict:
    winner_label: str
    score: float            # 0..1 — judge's confidence
    rationale: str
    losers: list[str]


_JUDGE_SYSTEM_PROMPT = """\
You are a senior iOS engineer judging two candidate code diffs that
attempt to solve the same task.

Score each candidate on:
  - correctness (1-5)
  - SwiftUI / Apple HIG idiomaticity (1-5)
  - readability + maintainability (1-5)
  - safety (force-unwraps, retain cycles, threading) (1-5)

Pick the winner. If they're effectively tied, pick the one with fewer
risk markers. Be terse — your output is parsed.

Return EXACTLY this JSON shape and nothing else:
{
  "winner": "<label>",
  "confidence": <0..1 float>,
  "rationale": "<one sentence>"
}
"""


async def rank(
    candidates: list[Candidate],
    *,
    judge: LLMClient,
    judge_model: str = "claude-opus-4-7",
) -> Verdict:
    """Ask `judge` to choose between candidates. Returns a `Verdict`.

    Defensively parses the judge's reply: if the JSON is malformed or
    the named winner doesn't exist, we fall back to the candidate with
    the most output tokens (proxy for engagement). The orchestrator
    can always override.
    """
    if len(candidates) < 2:
        # Nothing to rank — return a degenerate verdict that picks the
        # one we have so callers don't need to special-case.
        only = candidates[0]
        return Verdict(
            winner_label=only.label,
            score=1.0,
            rationale="single candidate; no contest",
            losers=[],
        )

    user_prompt_parts: list[str] = ["# Task: pick a winner.", ""]
    for c in candidates:
        user_prompt_parts.append(f"## Candidate {c.label} ({c.model})")
        user_prompt_parts.append("```")
        user_prompt_parts.append(c.output[:8_000])  # bound prompt size
        user_prompt_parts.append("```")
        user_prompt_parts.append("")
    user_prompt = "\n".join(user_prompt_parts)

    response = await judge.complete(
        model=judge_model,
        system=_JUDGE_SYSTEM_PROMPT,
        messages=[Message(role="user", content=user_prompt)],
        tools=[],
        max_tokens=400,
        temperature=0.0,
    )

    parsed = _parse_verdict(response.text)
    valid_labels = {c.label for c in candidates}
    winner = parsed.get("winner") if parsed else None
    if winner not in valid_labels:
        # Fallback: pick by output volume.
        winner = max(candidates, key=lambda c: len(c.output)).label
        confidence = 0.4
        rationale = "judge reply unparseable; fell back to longest output"
    else:
        confidence = float(parsed.get("confidence", 0.6)) if parsed else 0.6
        rationale = (parsed or {}).get("rationale", "")[:240]

    return Verdict(
        winner_label=winner,
        score=max(0.0, min(1.0, confidence)),
        rationale=rationale,
        losers=[c.label for c in candidates if c.label != winner],
    )


def _parse_verdict(text: str) -> dict | None:
    """Extract the JSON blob from the judge's reply."""
    text = text.strip()
    # Most replies are pure JSON, but we tolerate code-fence wrappers.
    fence = re.search(r"\{.*\}", text, flags=re.DOTALL)
    if not fence:
        return None
    try:
        return json.loads(fence.group(0))
    except json.JSONDecodeError:
        return None


# --------------------------------------------------------------------------- #
# High-level helper for the orchestrator
# --------------------------------------------------------------------------- #

async def race(
    runners: list[tuple[str, str, "asyncio.Future[str]"]],
    *,
    judge: LLMClient,
    judge_model: str = "claude-opus-4-7",
) -> Verdict:
    """Wait for every runner to finish, then rank them. Each tuple is
    `(label, model_id, future_yielding_assistant_text)`."""
    results = await asyncio.gather(*[fut for _, _, fut in runners], return_exceptions=True)
    candidates: list[Candidate] = []
    for (label, model_id, _), output in zip(runners, results):
        if isinstance(output, Exception):
            continue
        candidates.append(Candidate(
            label=label, model=model_id,
            output=output if isinstance(output, str) else str(output),
            usage={},
        ))
    if not candidates:
        return Verdict(
            winner_label="(none)", score=0,
            rationale="every candidate failed", losers=[],
        )
    return await rank(candidates, judge=judge, judge_model=judge_model)
