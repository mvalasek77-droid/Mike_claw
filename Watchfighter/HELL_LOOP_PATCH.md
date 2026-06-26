# Hell Demon-Fight — Ready-to-Apply Engine Patch

The literal "die → fight a demon in the Pit → win to resume, lose to start over"
loop. It touches Codex's tested engine, so it's written here as an exact patch to
apply and verify during the build pass (don't ship it unbuilt).

**No new `FighterArchetype` case** (that would break the many exhaustive switches).
We reuse an existing tough archetype as the Pit Warden — recommend `kairo`
(War King). Recolor later if desired.

## 1. `WatchfighterState` — add one flag (GameModels.swift)
```swift
var pitActive: Bool = false   // currently fighting the Pit warden (second-chance)
```
Default value = safe; no switch/initializer breakage.

## 2. `resolveRoundIfNeeded()` — branch the win/loss (WatchfighterEngine.swift)
Replace the **`else { state.opponentWins += 1 … }`** loss block and the final
end-check with pit-aware logic:

```swift
if playerWon {
    if state.pitActive {
        // Clawed out of the Pit — resume the ladder, no win credited.
        state.pitActive = false
        state.player.action = .victory
        state.opponent.action = .defeated
        showBanner("BACK FROM THE PIT", "the climb continues", duration: 2.0)
        // (skip playerWins++ / score for the pit fight)
    } else {
        state.playerWins += 1
        state.score += 500 + Int(state.roundTimer.rounded()) * 4
        state.player.action = .victory
        state.opponent.action = .defeated
        if state.opponent.archetype.isMillionBoss {
            showBanner("MILLION SHOT", "the impossible counter ends Titus", duration: 2.0)
        } else {
            showBanner(winner.finisherTitle, "\(winner.displayName) ends round \(state.round)", duration: 2.0)
        }
    }
} else {
    if state.pitActive {
        // Lost in the Pit — the run is over.
        state.opponent.action = .victory
        state.player.action = .defeated
        state.phase = .gameOver
        state.winnerText = ruleSet.defeatText
    } else {
        // First fall — dragged to the Pit instead of taking an elimination strike.
        state.pitActive = true
        state.player.action = .defeated
        state.opponent.action = .victory
        showBanner("INTO THE PIT", "win to climb back", duration: 2.0)
    }
}

// finisher FX (unchanged) …

// End check: pit fights never end the run via the win/loss thresholds.
if !state.pitActive,
   state.playerWins >= ruleSet.playerWinsToEnd || state.opponentWins >= ruleSet.opponentWinsToEnd {
    state.phase = .gameOver
    state.winnerText = state.playerWins >= ruleSet.playerWinsToEnd ? ruleSet.victoryText : ruleSet.defeatText
    state.bannerTimer = 0
}
```
> Note: this replaces the two-loss elimination with a one-fall→Pit→one-life model
> (matches the requested "lose → hell; lose in hell → start over"). If you want to
> KEEP two-loss elimination as well, gate the Pit on the *first* fall only and let
> the second fall use the old path.

## 3. `startNextRound()` — spawn the warden for a pit fight
In the opponent line, pick the warden when `pitActive`:
```swift
let nextOpponent: FighterArchetype = state.pitActive
    ? .kairo                                   // Pit Warden (reused archetype)
    : (ruleSet.advancesLadder ? opponent(for: state.chapter) : previousOpponent)
state.opponent = DuelFighter(archetype: nextOpponent, x: 0.75, facing: -1)
```
Keep `state.chapter` unchanged during a pit fight (it already is, since playerWins
doesn't change). When the pit is cleared, the next `startNextRound` spawns the real
chapter opponent again (refight the floor you fell on).

## 4. GameScreen.swift — cutscene hooks (flow side)
The Pit cutscene already fires on a fall (see `FFScript.pit` + the `opponentWins`
check). With this engine patch, also key the **escape** cutscene off `pitActive`
clearing:
- On entering the pit (loss, `pitActive` just became true): play `FFScript.pit`
  with `toFight: false` (already wired via the loss branch — re-point it to detect
  `engine.state.pitActive`).
- On clearing the pit (win while `pitActive` was true): play a short
  `FFScript.pitEscape` then continue.

Add to `FFScript`:
```swift
static let pitEscape: [CutscenePanel] = [
    CutscenePanel(speaker: "THE PIT", text: "…tch. The stairs are yours again. But the tower never forgets a face it dropped."),
    CutscenePanel(speaker: nil,    text: "You climb out of the smoke and back onto the floor you lost. One life left — make it count."),
]
```

## Verify after applying
1. `xcodegen generate` → build.
2. Lose floor 1 on purpose → expect INTO THE PIT → fight the Warden (kairo).
3. Win the Pit → BACK FROM THE PIT → refight floor 1's real opponent.
4. Lose the Pit → game over.
5. Confirm the boss floor (Million Room / Titus) and the Million-Shot rule still
   work unchanged.
