# Prompt Coach eval harness

Validates the model-pack rewrite rules with real numbers instead of trusting the
docs. Answers one question per model: **does coaching a ramble actually produce a
better result than sending the ramble raw?**

## How it works

For each test ramble in `rambles.jsonl`, for each target model:

1. Run the **raw** ramble against the model.
2. Build a **coached** prompt by applying that model's rules from
   `../model-pack.json`, and run it against the same model.
3. An **LLM judge** (Opus 4.8) scores both outputs 0–10 against the ramble's
   acceptance criteria and picks a winner.

The output is a per-model coach win-rate. If coaching helps, coached wins most
rambles; if a rule is wrong or neutral, you'll see it in the losses and can
tune `model-pack.json`.

## Run it

```sh
pip install anthropic
export ANTHROPIC_API_KEY=sk-ant-...     # or: ant auth login

python run_eval.py                      # all models, all rambles
python run_eval.py --models claude-sonnet-5
python run_eval.py --rambles email-refund,sql-report
python run_eval.py --out results.json   # dump every output + verdict
```

Uses **your own** Anthropic key and bills to your account — same key the app's
optional Test It feature uses. A full run is 3 models × 5 rambles × 2 outputs +
15 judge calls ≈ 45 calls; expect a few dollars at these models' prices.

## Files

- `rambles.jsonl` — test cases. Each has an `id`, the raw `ramble`, the `intent`,
  and a list of `acceptance` criteria the judge grades against. Add your own —
  the harness is only as good as the rambles.
- `run_eval.py` — the runner (adaptive thinking, streaming, no sampling params).
- `../model-pack.json` — the rules under test.

## Reading the results

- **Coach win-rate ≥ ~70%** on a model → its rules are pulling their weight.
- **A specific ramble where raw wins** → the coached prompt over-engineered or
  the rule misfired for that task shape; read `coached_prompt` in the `--out`
  dump and adjust that model's `rewrite_rules`.
- **Lots of ties** → the rambles may be too easy to distinguish; add harder,
  more under-specified cases where coaching has room to matter.

## Honest caveats

- The judge is a model, so scores are directional, not ground truth. Spot-check
  a few outputs yourself, especially close calls.
- The coach here is a lightweight prompt-builder from the pack rules, not the
  on-device app. It measures whether the **rules** move the needle — which is
  the thing you actually want to know before shipping them.
- Five rambles is a smoke test. For a real signal, grow `rambles.jsonl` to
  15–25 cases spanning the task types your users bring.
