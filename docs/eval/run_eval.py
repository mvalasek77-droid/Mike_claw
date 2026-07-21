#!/usr/bin/env python3
"""
Claude Prompt Coach — eval harness.

Validates the model-pack rewrite rules with real numbers instead of trusting
the docs. For each test ramble, for each target model, it:

  1. Runs the RAW ramble against the model.
  2. Builds a COACHED prompt by applying that model's rules from
     docs/model-pack.json, and runs it against the same model.
  3. Uses an LLM judge (Opus 4.8) to score both outputs against the ramble's
     acceptance criteria and pick a winner.

It then prints a per-model win-rate so you can see whether coaching actually
helps, and where.

Usage:
    export ANTHROPIC_API_KEY=sk-ant-...        # or `ant auth login`
    python docs/eval/run_eval.py                       # all models, all rambles
    python docs/eval/run_eval.py --models claude-sonnet-5
    python docs/eval/run_eval.py --rambles email-refund,sql-report
    python docs/eval/run_eval.py --out results.json

Notes:
  - Uses adaptive thinking + streaming, per current Claude API guidance.
  - Never emits temperature/top_p/top_k or prefills (rejected by these models).
  - The coach here is a lightweight prompt-builder from the pack rules; the real
    app does the rewrite on device. This harness measures whether the *rules*
    move the needle, which is the point.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

try:
    import anthropic
except ImportError:
    sys.exit("Install the SDK first:  pip install anthropic")

HERE = Path(__file__).resolve().parent
PACK_PATH = HERE.parent / "model-pack.json"
RAMBLES_PATH = HERE / "rambles.jsonl"
JUDGE_MODEL = "claude-opus-4-8"


def load_pack() -> dict:
    return json.loads(PACK_PATH.read_text())


def load_rambles() -> list[dict]:
    return [json.loads(line) for line in RAMBLES_PATH.read_text().splitlines() if line.strip()]


def build_coached_prompt(ramble: dict, model_entry: dict, cross_rules: list[str]) -> str:
    """Apply this model's rewrite rules to produce a coached prompt.

    The app does this on device; here we hand the rules to a model-agnostic
    template so the eval measures the rules, not a hand-written prompt.
    """
    rules = "\n".join(f"- {r}" for r in model_entry["rewrite_rules"])
    cross = "\n".join(f"- {r}" for r in cross_rules)
    acceptance = "\n".join(f"- {a}" for a in ramble["acceptance"])
    return (
        f"{ramble['intent']}\n\n"
        f"Original request (verbatim): {ramble['ramble']}\n\n"
        f"Success criteria — done means:\n{acceptance}\n\n"
        f"Style/approach guidance for this task:\n{rules}\n{cross}"
    )


def run_model(client: anthropic.Anthropic, model: str, prompt: str) -> str:
    """Run a prompt against a model with adaptive thinking + streaming."""
    with client.messages.stream(
        model=model,
        max_tokens=4096,
        thinking={"type": "adaptive"},
        output_config={"effort": "high"},
        messages=[{"role": "user", "content": prompt}],
    ) as stream:
        msg = stream.get_final_message()
    return "".join(b.text for b in msg.content if b.type == "text").strip()


JUDGE_SCHEMA = {
    "type": "object",
    "properties": {
        "raw_score": {"type": "integer", "description": "0-10, how well output A meets the criteria"},
        "coached_score": {"type": "integer", "description": "0-10, how well output B meets the criteria"},
        "winner": {"type": "string", "enum": ["raw", "coached", "tie"]},
        "reason": {"type": "string"},
    },
    "required": ["raw_score", "coached_score", "winner", "reason"],
    "additionalProperties": False,
}


def judge(client: anthropic.Anthropic, ramble: dict, raw_out: str, coached_out: str) -> dict:
    criteria = "\n".join(f"- {a}" for a in ramble["acceptance"])
    prompt = (
        "You are grading two responses to the same underlying request against fixed "
        "acceptance criteria. Score each 0-10 and pick a winner. Judge only how well "
        "each meets the criteria and intent — not length or style for its own sake.\n\n"
        f"Intent: {ramble['intent']}\n\n"
        f"Acceptance criteria:\n{criteria}\n\n"
        f"--- OUTPUT A (raw) ---\n{raw_out}\n\n"
        f"--- OUTPUT B (coached) ---\n{coached_out}\n"
    )
    resp = client.messages.create(
        model=JUDGE_MODEL,
        max_tokens=1024,
        output_config={"format": {"type": "json_schema", "schema": JUDGE_SCHEMA}},
        messages=[{"role": "user", "content": prompt}],
    )
    text = next(b.text for b in resp.content if b.type == "text")
    return json.loads(text)


def main() -> None:
    pack = load_pack()
    rambles = load_rambles()
    all_ids = [m["id"] for m in pack["models"]]

    ap = argparse.ArgumentParser()
    ap.add_argument("--models", help="comma-separated model IDs (default: all in pack)")
    ap.add_argument("--rambles", help="comma-separated ramble IDs (default: all)")
    ap.add_argument("--out", help="write full results JSON to this path")
    args = ap.parse_args()

    models = args.models.split(",") if args.models else all_ids
    if args.rambles:
        wanted = set(args.rambles.split(","))
        rambles = [r for r in rambles if r["id"] in wanted]

    client = anthropic.Anthropic()  # picks up ANTHROPIC_API_KEY or an ant profile
    cross_rules = pack["cross_model_rules"]
    by_id = {m["id"]: m for m in pack["models"]}

    results = []
    tally: dict[str, dict[str, int]] = {}

    for model in models:
        entry = by_id.get(model)
        if entry is None:
            print(f"! {model} not in model-pack.json — skipping", file=sys.stderr)
            continue
        tally[model] = {"coached": 0, "raw": 0, "tie": 0}
        print(f"\n=== {entry['name']} ({model}) ===")

        for r in rambles:
            print(f"  · {r['id']} … ", end="", flush=True)
            raw_out = run_model(client, model, r["ramble"])
            coached_prompt = build_coached_prompt(r, entry, cross_rules)
            coached_out = run_model(client, model, coached_prompt)
            verdict = judge(client, r, raw_out, coached_out)
            tally[model][verdict["winner"]] += 1
            print(f"raw {verdict['raw_score']} vs coached {verdict['coached_score']} "
                  f"→ {verdict['winner']}")
            results.append({
                "model": model, "ramble": r["id"],
                "raw_output": raw_out, "coached_output": coached_out,
                "coached_prompt": coached_prompt, "verdict": verdict,
            })

    print("\n=== win rates (coached vs raw) ===")
    for model, t in tally.items():
        n = sum(t.values()) or 1
        print(f"  {model}: coached {t['coached']}/{n}, "
              f"raw {t['raw']}/{n}, tie {t['tie']}/{n}  "
              f"→ coach win rate {t['coached'] / n:.0%}")

    if args.out:
        Path(args.out).write_text(json.dumps({"tally": tally, "results": results}, indent=2))
        print(f"\nWrote full results to {args.out}")


if __name__ == "__main__":
    main()
