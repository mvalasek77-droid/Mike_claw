# Prompt Coach — Feature Roadmap

Where the app is and where it goes. v1.0 is the shippable core: a paid,
on-device, ramble → model-ready-Claude-prompt tool that teaches the technique
behind every edit.

---

## v1.0 — Shipped in this branch

The complete core loop, all on device, no network, no account.

| Feature | State |
|---|---|
| Ramble input (type or dictate via the system keyboard) | ✅ |
| Task detection across 10 task types | ✅ |
| Model recommender (cheapest model that clears the bar) + user override | ✅ |
| Deterministic technique-driven rewrite | ✅ |
| Prompt report card — scores the *original* ramble 0–100 | ✅ |
| "What I changed" naming each technique applied | ✅ |
| Learn explainers for techniques | ✅ |
| Sharpen (meta-prompting) — second pass into tagged sections | ✅ |
| Structured-output mode — emits a JSON schema for machine-readable tasks | ✅ |
| Retired-pattern stripping (prefill / temperature / `budget_tokens` / CRITICAL) | ✅ |
| Per-model overrides (e.g. Opus 5 self-verifies → withhold self-check) | ✅ |
| Model reference library — how to prompt each of the 5 models | ✅ |
| Technique library — 28 techniques, browsable and searchable | ✅ |
| On-device history, searchable, deletable | ✅ |
| Settings + in-app Terms & Privacy | ✅ |
| Liquid Glass theme, per-model tint, Reduce Motion, Dynamic Type, dark mode | ✅ |
| Refreshable model pack (new models without an App Store update) | ✅ (bundled + versioned; remote fetch is v1.1) |

**Not shipped, deliberately:** any jailbreak / guardrail-bypass capability. The
refusal doctor helps *legitimate* requests read as legitimate; it will not help
disguise a disallowed one. See `refusal_handling.out_of_scope`.

---

## v1.1 — Test It (the user's own key)

The one network feature, strictly opt-in.

- Paste an Anthropic API key, stored in the iOS Keychain.
- **Run** the coached prompt against the chosen model and show the reply.
- **Before/after compare** — run the raw ramble and the coached prompt side by
  side so the user *sees* the improvement.
- Model-graded Sharpen: send the prompt for critique instead of the on-device
  deterministic pass.
- Live cost estimate from the pack's per-MTok pricing.
- Honest refusal handling: surface `stop_reason: "refusal"` and offer the
  documented fallback (e.g. Fable 5 → Opus 5).

Everything stays keyless-optional: the app must remain fully useful with no key.

## v1.2 — Remote pack refresh

- Fetch a newer `model-pack.json` from a static URL, signature-checked.
- "New model available" nudge when Anthropic ships one.
- Pack changelog screen so users see what coaching rules changed.

## v1.3 — Prompt library

- Save a coached prompt as a reusable template with `{{placeholders}}`.
- Folders/tags; duplicate-and-tweak.
- Share sheet export as Markdown or JSON.
- Shortcuts / App Intents action: "Coach this prompt" from anywhere.

## v1.4 — Progress & habit

- Score trend over time — the teaching flywheel made visible.
- "Techniques you never use" nudge, with a Learn link.
- Weekly streak-free summary (no dark patterns, no manufactured urgency).

## v2.0 — Platform

- iPad layout with a real two-column split (input | result).
- macOS via Catalyst / native, with a menu-bar quick-coach.
- Widget: last coached prompt, one-tap copy.
- Team/shared packs: an org ships its own house prompting rules as a pack.

---

## Explicitly out of scope

| Not doing | Why |
|---|---|
| Jailbreaks / safety bypass | App Store rejection + Anthropic usage-policy violation. Kills the product. |
| Bundling our own API key | Turns a paid app into an unbounded cost liability, and violates key-handling norms. |
| Subscriptions / IAP | Product decision: one-time price, no upsell surface. |
| Accounts, cloud sync, analytics | The privacy stance is a feature; it's what lets the Privacy Policy be three paragraphs. |
| Supporting non-Claude models | The whole value is per-model Claude accuracy. A generic prompt tool is a worse product. |

---

## Guardrails for future work

1. **The pack stays the source of truth.** New model or changed guidance → edit
   `model-pack.json` and bump `pack_version`. Never hardcode model behaviour in
   Swift.
2. **Contract tests must stay green.** `Tests/validate_pack.py` runs anywhere and
   catches the decode-mismatch class of launch crash; `Tests/PromptCoachTests`
   covers engine behaviour. Both must pass before merge.
3. **Every model claim must be verifiable.** Pricing, context windows, and API
   behaviour come from Anthropic's docs, with the verification date in the pack.
   No guessed facts — a wrong API fact makes the app actively harmful.
4. **On-device first.** Any new feature must degrade gracefully with no network
   and no key.
