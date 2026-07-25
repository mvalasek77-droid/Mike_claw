# Prompt Coach — Final Test Report

**Date:** 2026-07-27 · **Pack:** `2026.07.27` · **App:** 1.0.0 (build 1)
**Environment:** Linux container, no Xcode, no Swift toolchain, no iOS Simulator.

Read the environment line again, because it bounds every claim below. I ran
everything that can run here and I am telling you plainly which checks are
**executed** and which are **static** — because "confirmed app ready" from a
machine that cannot compile the app would be a lie, and that's exactly the kind
of claim that gets a submission rejected.

---

## Verdict

| Question | Answer |
|---|---|
| Is the feature set complete and coherent? | **Yes** — every feature in the v1.0 spec is implemented and reachable. |
| Do the executable tests pass? | **Yes — 384/384 contract tests, 0 failures.** |
| Are there known bugs? | **None known.** Three real bugs were found and fixed during this pass (below). |
| Is it *certified* zero-bug and submit-ready? | **No.** 39 XCTest cases are written but **have never been executed** — that needs Xcode. Until they run, "zero bugs" is unproven. |
| Does it look senior-engineer-built? | **Yes**, by inspection: data-driven architecture, no fixed-size fonts, no debug prints, no force-unwraps, backward-compatible persistence, tests that assert behaviour rather than restating the code. |

**Honest one-liner:** the app is *build-ready*, not *verified-shipped*. Run
`xcodegen generate && xcodebuild test` on a Mac and this becomes a real
green light.

---

## 1. Executed tests — 384 passed, 0 failed

`python3 ios/PromptCoach/Tests/validate_pack.py` — runs anywhere Python does,
including CI. This is the guardrail against the single worst failure mode: a
model pack that doesn't match the Swift decoder, which would `fatalError` on
launch. Coverage:

| Group | What it enforces |
|---|---|
| JSON validity & docs sync | The bundled pack parses and is byte-identical to `docs/model-pack.json` (no stale coaching rules shipping while docs claim otherwise). |
| Decoder contract | Every key `ModelPack.CodingKeys` / `ModelProfile.CodingKeys` declares non-optional exists in every entry. |
| Referential integrity | All 10 playbooks resolve to real models and real technique ids; recommender rules too; no dangling references. |
| Engine ↔ pack alignment | The engine's report-card switch scores *exactly* the pack's 8 checklist items (a missing case silently scores `false` forever); every `TaskType` has a playbook; the engine hardcodes no unknown model id. |
| Theme coverage | Every model in the pack has a `Glass` tint, and there are no stale tints for removed models. |
| Factual guards | Opus 5 suppresses `self_check`; Opus 5 thinking is on-by-default with the `high` disable-ceiling recorded; Fable 5 forbids disabling thinking; Haiku 4.5 has an empty effort ladder; every frontier model rejects `temperature`/`budget_tokens`/prefill. |
| Feature reality check | Each `advanced_features` entry the pack advertises has a real implementation (`sharpen(`, `jsonSchema(`, `buildReportCard(`). |
| Accessibility | Zero fixed-size `.system(size:)` fonts anywhere in app sources. |
| Source hygiene | No `print(`, `TODO`, `FIXME`, `HACK`, `try!`, or `as!` in shipping code. |
| Legal | Terms and Privacy ship **in-app** as bundled text, not remote links. |
| Persistence safety | New `CoachResult` fields are Optional, so upgrading users don't lose history. |

## 2. Written but NOT executed — 39 XCTest cases

`ios/PromptCoach/Tests/PromptCoachTests/CoachEngineTests.swift`. These need
Xcode. They are written to catch behaviour, not to restate the implementation:

- **Task detection** — all 10 types plus the unknown-input fallback.
- **Report card** — a bare ramble must score below a well-formed one; scores
  bounded 0–100; retired patterns flagged; scored items match the pack.
- **Opus 5 specifics** (the highest-value tests): no self-check line is emitted;
  the app *explains* why it withheld it; conciseness and scope lines present;
  the thinking note says "on by default".
- **Contrast** — Sonnet 5 *does* get a self-check; Haiku *never* sees the word
  "effort"; Fable 5's note says "always on".
- **Rewrite behaviour** — success criterion always present; retired patterns
  stripped and surfaced; duplicate sentences collapsed; emitted JSON schema is
  parseable.
- **Sharpen** — adds tagged sections, keeps the history id stable, respects
  model suppression, adds examples only where output shape matters.
- **Edge cases** — empty/whitespace input, 15KB input, unicode + emoji, unknown
  model override, prose `<`/`>` not misread as markup, real tags detected.
- **Persistence** — legacy history JSON without the `sharpened` key decodes.
- **Determinism** — same ramble in, same prompt out.
- **Performance** — `measure` block on the coaching call (typing-latency budget).

## 3. Bugs found and fixed during this pass

1. **Codable default wouldn't decode.** I first wrote `var isSharpened: Bool = false`.
   Swift's synthesized decoder does *not* fall back to defaults for
   non-optionals — it throws. Since `loadHistory()` uses `try?`, every existing
   user's history would have silently vanished on upgrade. Changed to `Bool?`
   with a computed accessor, and added a regression test using legacy JSON.
2. **Angle brackets in prose triggered XML advice.** `ramble.contains("<") && ramble.contains(">")`
   fires on "why 5 < 10 and 20 > 15". Replaced with a real tag regex and covered
   by two tests (prose must not trigger; `<div>` must).
3. **Effort advice for a model with no effort parameter.** The footer keyed off
   `defaultEffort != nil` only; suggesting an effort level to Haiku 4.5 is an API
   error. Now gated on `apiFacts.supportsEffort`, with a test asserting the word
   "effort" never reaches a Haiku prompt.

Earlier in the branch: the iOS 26 `glassEffect` corner-radius mismatch, and
history duplicating on model override (now an upsert).

## 4. What Opus 5 changed about the product

Adding Opus 5 wasn't a row in a table — it **inverted two coaching rules**, which
is the clearest evidence this app needs real per-model data rather than one
generic prompt template:

- Opus 5 **verifies its own work**. Anthropic's guidance is explicit that
  "include a final verification step" causes *over*-verification. So the engine
  now **suppresses** `self_check` for Opus 5 and tells the user why — while still
  emitting it for Sonnet 5, where it helps.
- Opus 5's **default responses run long**, and lowering effort doesn't reliably
  shorten them. So a conciseness line and a scope boundary are appended from the
  model's own `extra_instructions`.

Both behaviours are enforced by contract tests *and* unit tests, so a future
"cleanup" can't silently regress them.

## 5. Not verifiable from here — the real final test

Run on a Mac with Xcode 16+:

```sh
cd ios/PromptCoach
xcodegen generate
xcodebuild test -scheme PromptCoach -destination 'platform=iOS Simulator,name=iPhone 16'
```

Then walk these manually — each is a category a static pass cannot cover:

- [ ] **Clean build, zero warnings** — both the iOS 26 `glassEffect` path and the
      `.ultraThinMaterial` fallback (`#available` + `#if compiler(>=6.2)`).
- [ ] **All 39 XCTests green.**
- [ ] **Flow walk:** Ramble → Coach It → Result → model override re-tints →
      Sharpen → copy/share → Settings → Model reference → each model detail →
      Technique library → Learn → Terms → Privacy → History → search → delete.
- [ ] **Dynamic Type at the largest accessibility size** — the chips, report-card
      rows, and API-facts key/value rows are the likely truncation points.
- [ ] **VoiceOver sweep** — model chips announce "recommended"/"selected"; the
      copy button announces "Copied"; model cards read as one element.
- [ ] **Reduce Motion on** — background must freeze, not animate.
- [ ] **Dark and light**, and iPad portrait + landscape.
- [ ] **Instruments** — the 30fps `TimelineView` background: check for dropped
      frames and confirm it pauses off-screen.
- [ ] **Device haptics** — Simulator can't render them.
- [ ] **First launch with no history** — empty states on Ramble and History.
- [ ] **Upgrade path** — install, create history, then install a build with the
      new `sharpened` field and confirm history survives (the bug from §3.1).

## 6. Pre-submission blockers

1. **The app icon is a generated placeholder.** Functional and coherent, but not
   real branding. Replace before submission.
2. **Set a real `DEVELOPMENT_TEAM`** in `project.yml` (currently `""`).
3. **Decide the price** and confirm no IAP products exist in App Store Connect —
   the app and its legal copy both state one-time purchase, no IAP.
4. **App Review notes** should say the app is fully functional offline with no
   account and no API key required, so a reviewer doesn't go hunting for a login.

---

## Bottom line

384 executable checks pass, 39 behavioural tests are written and waiting for a
Mac, three real bugs were found and fixed, and the architecture is data-driven
with the model facts sourced from Anthropic's current docs and dated in the pack.

What I will not tell you is that it's "tested, zero bugs, ship it" — I have not
pressed Build, and that distinction is the whole difference between engineering
and vibe coding.
