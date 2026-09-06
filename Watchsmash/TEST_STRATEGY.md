# Watch Smash — AI Test Strategy

A complete plan for an AI agent (or a human + AI pair) to test **every process,
function, and feature** of the game for flow and bugs. It defines *what* to test,
*how* the AI drives each test, and the *pass criteria* that decide ship / no-ship.

> **Build reality:** this repo holds Apple-only Swift (SwiftUI / SwiftUI Canvas /
> WatchKit). It cannot compile in the Linux container — the toolchain isn't here.
> So the strategy is split into three layers by *where* each layer runs. Layers 1
> and 3 are automatable today; Layer 2 needs a Mac/Xcode runner (local or CI).

---

## 0. Test layers (where the AI runs each check)

| Layer | Runs on | What it covers | Cost |
|------|---------|----------------|------|
| **L1 — Headless engine** | `xcodebuild test` on macOS / CI (`WatchsmashTests`) | All deterministic combat logic: damage, combos, AI, ladder flow, boss rule, difficulty, mode rules. **The bulk of bug-finding.** | Cheap, fast, repeatable |
| **L2 — UI / device walkthrough** | watchOS Simulator or a real Watch | Rendering, flips, cutscenes, blur, Crown input, scene transitions, the *feel* of flow | Slower, needs a runner |
| **L3 — Static analysis** | Anywhere (this container too) | Grammar/spelling of all on-screen copy, dead code, switch-exhaustiveness, balance-constant audit | Cheap, immediate |

The engine is intentionally a pure value type driven by `tick(delta:input:)` with a
**seeded RNG** (`WatchsmashEngine(seed:)`) and debug hooks (`debugSetPlayer`,
`debugSetOpponent`, `debugChargeSpecial`). That makes the AI able to script *any*
game state deterministically — this is the backbone of the whole strategy.

---

## 1. The AI test loop (how the agent works)

For each feature below the AI follows the same loop:

1. **Locate** the function/feature in source (grep the symbol).
2. **Specify** the expected behavior in one sentence (the oracle).
3. **Drive** it:
   - L1: write/extend an XCTest using seeded engine + debug hooks.
   - L2: script a Simulator walkthrough (or a built-in autoplay bot, §8) and
     capture a screenshot at each milestone.
   - L3: scan the string literals / switch statements directly.
4. **Assert** against the oracle; on failure, capture state (seed, tick count,
   `state` dump) so the bug is reproducible from a single seed.
5. **Record** PASS/FAIL in the coverage matrix (§9) with the repro seed.

Golden rule: **every reported bug must come with a seed + tick count that
reproduces it deterministically.** No "sometimes it glitches."

---

## 2. Feature coverage matrix (every process & function)

Each row is a test target. ✅ = existing test, ➕ = test to add.

### 2.1 Core combat (`WatchsmashEngine.performAttack`, `applyHit`)
- ✅ Player attack damages opponent and scores (`testPlayerAttackDamagesOpponentAndScores`)
- ✅ Combo chains before timer expires (`testComboChainsBeforeTimerExpires`)
- ✅ Special consumes meter + longer-range projectile (`testSpecialConsumes…`)
- ✅ Dash strike closes gap without full meter (`testDashStrikeClosesGap…`)
- ✅ Jump-kick hits over longer arc (`testJumpKickHitsOverLongerArc`)
- ✅ Throw damages + repositions at point blank (`testThrowDamages…`)
- ✅ Crouch sets low-guard stance (`testCrouchSetsLowGuardStance`)
- ➕ **Every** `FighterAction` (jab/kick/jumpKick/throwAttack/projectile/special)
  produces damage > 0 in range and **0 out of range** (range table at
  `performAttack`, lines ~333–360). Loop all 6 actions × in/out distance.
- ➕ Cooldown gating: a second attack inside `playerAttackClock` is ignored.
- ➕ Guard meter depletion → chip damage → guard break behaves per the model.
- ➕ Health never goes < 0 and never > `maxHealth` after any sequence.
- ➕ `actionDuration > 0` after every attack and `actionTimer ≤ actionDuration`
  (the smooth-motion envelope invariant — already covered for one case in
  `FFLayerTests`; extend to all actions).

### 2.2 Character uniqueness — **all fighters have unique styles** (§3)
- ✅ Fighters expose distinct technique profiles (`testFightersExposeDistinct…`)
- ✅ Zoner projectile out-reaches grappler projectile
- ✅ Grappler throw > acrobat throw (damage + pushback)
- ➕ Full uniqueness sweep (see §3).

### 2.3 The boxer / final boss (§4)
- ✅ Titan needs combo-special for Million-Shot damage (`testTitanRequires…`)
- ✅ Million-shot rule (`millionCounter` at engine line 387–390)
- ➕ Brute-force invincibility proof (see §4).

### 2.4 Mode rules (`FightRuleSet`)
- ✅ Chapter progression uses each rival (`testChapterProgressionUsesEachRival`)
- ✅ Full ladder ends after final boss (`testFullLadderEndsAfterFinalBoss`)
- ✅ Versus ends after one round win (`testVersusModeEndsAfter…`)
- ✅ Learn repeats same opponent (`testLearnModeRepeats…`)
- ✅ Loss retries chapter; second loss ends run (`testLossRetriesCurrentChapter…`)
- ➕ Tournament best-of: `opponentWinsToEnd == 2`, `playerWinsToEnd ==
  StoryChapter.allCases.count`; round timer per mode (60/75/90).

### 2.5 Story / cutscene flow (`FFScript`, `CutsceneOverlay`, `GameScreen`)
- ✅ Core cutscenes present & non-empty (`FFLayerTests`)
- ✅ Per-floor beats cover mid-floors, not intro/boss
- ✅ First loss continues run + refights same floor (the Pit/Hell hook)
- ✅ Boss beat hides secret behind blur (`testBossBeatHidesTheSecret…`)
- ➕ Each floor beat fires **once** (seenChapters), not on refights.
- ➕ Pit beat fires on a loss and only when `pitPending` is set.
- ➕ `playCutscene → advanceCutscene → fight` routing reaches `.fighting` for
  every script (intro, midpoint, pit, beforeBoss, all 13 chapter beats).

### 2.6 AI difficulty (§7)
- ✅ Opponent pressure can damage player (`testOpponentPressureCanDamagePlayer`)
- ➕ Toughness floor + per-fighter difficulty ordering (see §7).

### 2.7 Input / movement (`updatePlayer`, Crown)
- ✅ Player stays on left side of duel space (`testPlayerMovementStays…`)
- ➕ Crown target tracking response lerps toward `targetX` (response constant
  `17.5 * quickness`) and clamps to the player's half.

### 2.8 Resources / packaging
- ✅ Voice resources bundled (`testVoiceResourcesAreBundled…`)
- ➕ Every `archetype.imageName` resolves to a bundled asset.
- ➕ `PrivacyInfo.xcprivacy` present; Info.plist sane (L3).

---

## 3. Strategy: prove **all characters are unique**

Goal: no two fighters play the same. The AI builds a **fingerprint** per
`FighterArchetype` and asserts they're all distinct.

For each archetype, sample from `GameModels` + engine:
- `combatStyle` (balanced/rushdown/grappler/zoner/acrobat/bruiser/titan)
- per-action `damageMultiplier`, `rangeMultiplier`, `cooldownMultiplier`
- `quickness`, `meterBuildRate`, `desiredSpacing` (from `updateOpponent`)
- `preferredAttack(distance:pressure:meter:)` sampled on a grid of
  distances × meter × pressure → the AI's "move table"
- visual: `combatStyle` flip-turn (canvas §FLIP) and `kickReach` (canvas)
- `signatureMove` string

Assertions:
1. **No duplicate fingerprints** — hash the tuple above; the set size == roster size.
2. **Style coverage** — every `CombatStyle` case is used by ≥1 fighter (catches a
   dead style).
3. **Behavioral divergence** — run the *same* scripted player gauntlet (same seed)
   against every fighter; the resulting (damage-taken, distance-kept, move-mix)
   vectors must differ pairwise beyond a threshold. Two fighters that produce
   near-identical traces fail even if their constants differ on paper.
4. **Personality reads visually (L2)** — screenshot each fighter mid-jab,
   mid-kick, mid-jumpKick; confirm distinct silhouette, palette, flip arc, and
   kick height. (Acrobat = full flip + highest kick; titan = short arc + planted
   kick.)

➕ Test stub: `testEveryFighterHasAUniqueBehavioralFingerprint`.

---

## 4. Strategy: prove the **boxer can't be defeated** (and the path is hidden)

Two separate claims, tested separately.

**(a) Invincible to damage.** In `applyHit`, `millionCounter` requires
`defender.archetype.isMillionBoss && action == .special && state.combo >= 8`;
otherwise boss damage is floored to `max(1, round(raw * 0.04))`.

AI brute-force proof (`testBossSurvivesEveryNonMillionAssault`):
- Set opponent = `.titan`, `debugChargeSpecial`, full health.
- For a large scripted gauntlet — every action, every combo length **1…7**,
  with and without meter, from every range — confirm boss health stays > 0.
- Confirm a `combo == 8 + special` is the **only** thing that drops it
  (already partly in `testTitanRequiresComboSpecialForMillionShotDamage`;
  widen to assert *exhaustive* failure of all other paths).
- Edge: combo exactly 7 + special → survives; combo 8 + non-special → survives;
  combo 8 + special but `isMillionBoss == false` → normal damage (guards the flag).

**(b) The path is smudged out.** `CutscenePanel.blurredHint` carries the secret
sequence; `CutsceneOverlay` renders it under `.blur(radius: 5.5)` inside the
"THE SECRET — REDACTED" box.
- ✅ L1: exactly one boss panel has a non-empty `blurredHint`; a "CANNOT BE
  BEATEN" line exists (`testBossBeatHidesTheSecret…`).
- ➕ L2: screenshot the boss cutscene; OCR the blurred region — the secret text
  must be **illegible** (OCR confidence low / wrong), while the surrounding
  un-blurred copy is legible. That's the visual proof the smudge works.

---

## 5. Strategy: full tournament run incl. **Hell/Pit mode** and scenes

The marquee end-to-end test. Two forms:

**(a) L1 deterministic ladder walk (`testTournamentFullRunReachesAndClearsBoss`).**
Drive a *scripted winning player* (or force wins via `debugSet…` health) from
floor 1 to `millionRoom`:
- Assert `state.chapter` advances through **all 15** `StoryChapter` cases in order.
- Assert the correct rival per floor (`opponent(for:)`, engine ~743).
- At the boss, execute the Million-Shot and assert the run ends in victory.
- Inject a **loss** on an arbitrary mid-floor → assert `pitPending` set →
  refight **same** floor → run continues (the Hell/second-chance loop). Confirm
  a *second* loss on that floor ends the run.

**(b) L2 scripted playthrough with scene capture.** Using the autoplay bot (§8)
or manual play, walk the whole tournament and screenshot **every transition**:
- intro cutscene → floor 1 fight → win banner → floor 2 beat → … → midpoint
  act-break → … → Pit/Hell cutscene on a forced loss → refight → … →
  `beforeBoss` (with blurred secret) → boss fight → ending.
- Each cutscene must route into `.fighting` (no soft-lock), portraits/nameplates
  render, text fits the watch frame (no clipping), and the "exciting scenes"
  actually appear at the right beats.

**Soft-lock sweep:** from every `GameScreenMode` (`menu`, `versusSelect`,
`learnSelect`, `cutscene`, `fighting`, `tournament/versus/learn`,
`gameOver/victory`) confirm there's always a forward path and a back-to-menu
path. No dead-end screens.

---

## 6. Strategy: grammar & spelling (L3, runnable now)

Every player-facing string is a literal in source — the AI extracts and checks
them without a build.

Sources to scan:
- `FFScript` (intro, midpoint, pit, beforeBoss, all `chapter(_:)` beats) —
  `GameScreen.swift`
- Banners/callouts in `WatchsmashEngine` (`showBanner`, signature moves,
  "MILLION SHOT", "TITUS SHRUGS", victory/defeat text)
- `FightRuleSet.victoryText/defeatText`, button labels ("NEXT ▶", "FIGHT!"),
  nameplates, `STORE_LISTING.md` copy
- `CombatStyle.label`, fighter names/titles in `GameModels`

Process:
1. Extract all string literals shown to the user (grep `Text(` , `CutscenePanel(`,
   `showBanner(`, `"…"` in copy files).
2. Run a spell/grammar pass (dictionary + LLM proofread), **allow-listing**
   intentional stylized tokens (NYRA, TITUS, ASCENDANT, MILLION SHOT, fighter
   names) so they aren't flagged.
3. Check consistency: tense, voice (second-person "you"), ALL-CAPS usage,
   ellipsis/em-dash style, no double spaces, terminal punctuation.
4. Confirm no placeholder text ("TODO", "lorem", "<add …>") ships — note
   `STORE_LISTING.md` currently has intentional `<add …>` placeholders that must
   be filled before submission (flag, don't ship).

➕ Optional L1 guard: `testNoUserFacingCopyHasPlaceholders` — assert none of the
shipping `FFScript`/banner strings contain "TODO"/"<".

---

## 7. Strategy: make the **AI tough**, hits back hard, per-fighter difficulty

Two parts: **verify** current behavior, and **flag the gap** the request implies.

**Current state (verified by reading):** opponent difficulty comes *only* from the
archetype — `quickness`, `combatStyle` spacing, and `meterBuildRate`. In
`updateOpponent` the move/approach response is
`min(1, delta * (8.4 + opponentPressure*5.6) * quickness)` and pressure is random
`0.48…1.0`. **There is no per-chapter difficulty ramp** — floor 1 and floor 14
share the same aggression model. So "each fighter more/less difficulty" is only
true to the extent archetypes differ; it does **not** escalate up the tower.

**Implemented — the difficulty ramp (`opponentDifficulty`, `WatchsmashEngine`).**
A per-floor multiplier rising 1.0 (floor 1 / Learn mode) → ~1.6 (top floors),
keyed off `state.chapter.rawValue`. It feeds: the opponent's aggression
(pressure floor), reaction speed (`opponentDecisionClock`), closing speed
(movement `response`), attack frequency (`opponentAttackClock`), and outgoing
damage (`rawDamage` on the opponent side). Floor 1 is mathematically neutral, so
all pre-existing balance tests and the seeded RNG sequence are unchanged.

**Tests added (`BalanceAndCoverageTests`):**
- ✅ `testDifficultyRampIsNeutralOnFloorOneAndRisesToTheTop` — ramp is 1.0 at
  floor 1, > 1.4 at the boss.
- ✅ `testHigherFloorsHitAPassivePlayerHarder` — same fighter deals more to a
  passive player higher up the tower.
- ✅ `testTheAIPunishesAPassivePlayerHardUpTheTower` — the *toughness floor*: a
  do-nothing player loses real health ("attacks back hard").
- ✅ `testEachFighterCarriesItsOwnDifficulty` — per-fighter damage output spans a
  range and isn't flat across the roster ("more or less difficulty").

Damage output is measured with a self-healing dummy so it captures the AI's
*output rate*, not a capped kill. Balance constants (the 0.60 spread, pressure
floor slope) are tunable after a device pass.

---

## 8. Tooling: the autoplay bot (how the AI "plays" for L2/flow)

To exercise flow without a human, add a headless **autoplay driver** behind the
existing `WATCHSMASH_DEMO=1` flag:
- A scripted `GameInput` generator that can (a) play to win, (b) play passively
  (toughness test), (c) force a loss, (d) execute the Million-Shot combo.
- A "scene recorder" that snapshots `GameScreenMode` + a screenshot on every
  state change, producing the tournament storyboard for review.
- Deterministic: seed the engine, fix the input script → identical run every time.

This bot is what walks §5's full tournament and feeds §3/§7's behavioral traces.

---

## 9. Coverage matrix & exit criteria

The AI maintains a living table: `feature | layer | test name | seed | status`.

**Ship gate (all must hold):**
1. L1: `xcodebuild test` green — 100% of §2 rows have a passing test (existing +
   added). Every combat action, mode, and the ladder/Pit loop covered.
2. Character uniqueness (§3): no duplicate fingerprints, all styles used,
   behavioral traces pairwise-distinct.
3. Boss (§4): brute-force proof passes — invincible to all non-Million paths;
   secret renders blurred/illegible (L2 OCR).
4. Tournament (§5): full 15-floor deterministic walk + Pit loop pass; L2
   storyboard shows every scene with no soft-lock.
5. Difficulty (§7): toughness floor passes; difficulty ordering + per-fighter
   spread pass (after the ramp is implemented).
6. Copy (§6): grammar/spelling clean, no placeholders in shipping strings.
7. L2 device pass: flips, big kicks, cutscenes, blur, Crown control all render
   and feel right on a real Watch (screenshots attached).

**Bug bar:** any crash, soft-lock, health/combo out-of-range, a defeatable boss, a
duplicate-feeling fighter, a legible "secret," or shippable typo = blocker.
Balance/feel issues = tune-before-ship, not blockers.

---

## 10. CI wiring (so this runs every push)

Add a macOS CI job: `xcodegen generate` → `xcodebuild test -scheme Watchsmash
-destination 'platform=watchOS Simulator,name=Apple Watch …'`. L1 + the bot-driven
L2 smoke (boot to menu, run one scripted fight, capture screenshots) run on every
push to `claude/fighting-game-apple-watch-bk0xF`. L3 grammar scan runs anywhere
(no Apple toolchain needed) and can run in this Linux container today.

See `AUDIT.md` for the static-audit findings this strategy operationalizes, and
`SELL_READY.md` / `STORE_LISTING.md` for the ship checklist this gate feeds.
