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
| Do the executable tests pass? | **Yes — 520/520 contract tests, 0 failures.** |
| Are there known bugs? | **None known.** Six real bugs were found and fixed during this pass (below). |
| Is it *certified* zero-bug and submit-ready? | **No.** 58 XCTest cases are written but **have never been executed** — that needs Xcode. Until they run, "zero bugs" is unproven. |
| Does it look senior-engineer-built? | **Yes**, by inspection: data-driven architecture, no fixed-size fonts, no debug prints, no force-unwraps, backward-compatible persistence, tests that assert behaviour rather than restating the code. |

**Honest one-liner:** the app is *build-ready*, not *verified-shipped*. Run
`xcodegen generate && xcodebuild test` on a Mac and this becomes a real
green light.

---

## 1. Executed tests — 520 passed, 0 failed

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
| Persistence safety | New `CoachResult` fields are Optional, so upgrading users don't lose history; `LearningStore.Record` decodes every field with `decodeIfPresent`. |
| **Filler-trim safety** | A Python mirror of the Swift `stripFiller` regex runs the app's real phrase list against must-survive sentences ("what kind of file…", "…at the end of the day…"), must-trim sentences, fenced code, and an idempotence check. This is the one rule that can silently corrupt a user's meaning, so the *rule* is tested, not just its shape. |
| **Token estimation** | Haiku 4.5 is the 1.0 baseline and no frontier multiplier is below it; unknown model ids fall back to 1.0 rather than guessing; the trim loop is bounded (`rounds < 4`) so it always terminates. |
| **Adaptive-control guardrails** | Thresholds are read from the pack, never hardcoded in Swift; a learned preference for a model the pack dropped is discarded; mutes are filtered to techniques the pack still defines; an unknown signal gets an unreachable `Int.max` threshold; re-picking the already-recommended model is not counted as a preference; reset preserves explicit choices. |
| **Learning honesty** | The pack's `self_learning.note` must say "not a trained model" and "local", and must state at least four guardrails including the per-model-suppression one. |
| **Estimate honesty** | The result screen must label token figures as approximate, say "not an exact count", and surface `promptIsLonger`. |
| **XCTest suite keeps up** | Test-method names are unique, and the Swift suite must reference every new surface (filler trim, token report, multipliers, learned preference, auto-sharpen, muting, lenient record decode). |

## 2. Written but NOT executed — 58 XCTest cases

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
- **Filler trim** — meaning-bearing text survives; clause-leading throat-clearing
  goes; fenced code is never edited; the trim is idempotent; an all-filler ramble
  falls back to the original rather than handing an empty ask to the builder.
- **Token report** — attached to every result, internally consistent
  (`cleanedTokens ≤ rambleTokens`), tracks the chosen model's tokenizer, and
  reports `promptIsLonger` honestly for a two-word ramble. Sub-cent formatting
  never renders a real cost as "$0.00".
- **Adaptive controls** — a learned preference shifts the recommendation *and*
  discloses it; an explicit override always wins and suppresses the disclosure;
  a preference for a dropped model falls back to the pack; auto-sharpen applies
  the structure up front; muting every technique still can't reintroduce Opus 5's
  suppressed self-check, and still yields a usable prompt.
- **Persistence** — legacy history JSON without the `sharpened` *or* `tokenReport`
  key decodes; a partial and an empty `LearningStore.Record` both decode with
  learning defaulting to on.
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

4. **Filler phrases that would have mangled real asks.** My first draft of the
   trim list included `kind of`, `sort of`, `i mean`, and `you know`. Even with
   the clause-leading rule, "I mean it when I say only touch the header" becomes
   "it when I say…" and "You know the answer" becomes "the answer" — the trim
   would have quietly changed what the user asked for. All four removed, and the
   contract tests now run the shipped list against a must-survive corpus so a
   future addition can't reintroduce the class.
5. **Smart quotes made two phrases unmatchable.** iOS substitutes `'` for `'` as
   you type, so `if you don't mind` and `for what it's worth` would never have
   matched anything a user actually typed on a phone. Added the curly-apostrophe
   variants.
6. **"Reset learning" copy didn't match what reset did.** The footer said muted
   techniques were untouched while `reset()` cleared them. Fixed the behaviour
   rather than the copy: reset now clears only what the app *inferred* and keeps
   what the user chose outright (the on/off switch and any mutes), with a test
   asserting it.

Earlier in the branch: the iOS 26 `glassEffect` corner-radius mismatch, and
history duplicating on model override (now an upsert). Also fixed while wiring
the adaptive controls: sharpen state was being dropped when the user switched
models after sharpening (`recoach` now re-applies it), and nested
`ObservableObject` mutations weren't propagating to SwiftUI (every learning
write now funnels through `AppState.write(_:)` instead of a Combine bridge).

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
- [ ] **All 58 XCTests green.**
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
- [ ] **Filler trim on a real keyboard** — type (don't paste) a ramble containing
      "if you don't mind" and "for what it's worth" so iOS inserts curly
      apostrophes, and confirm both are matched (the bug from §3.5).
- [ ] **Token card** — numbers read as estimates, and the "made it longer" case
      appears for a very short ramble rather than being hidden.
- [ ] **Adaptive controls** — drive the signals to their thresholds (override the
      same model 3×, sharpen 3×), confirm the adjustment appears in Settings in
      plain language, then Reset and confirm mutes and the on/off switch survive.

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

520 executable checks pass, 58 behavioural tests are written and waiting for a
Mac, six real bugs were found and fixed, and the architecture is data-driven
with the model facts sourced from Anthropic's current docs and dated in the pack.

What I will not tell you is that it's "tested, zero bugs, ship it" — I have not
pressed Build, and that distinction is the whole difference between engineering
and vibe coding.
