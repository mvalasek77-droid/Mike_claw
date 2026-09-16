# ETERNAL COMBAT — The FF × Fighting-Game Bridge

The goal: a **Mortal-Kombat/Street-Fighter fighting engine** wrapped in
**original-PlayStation-Final-Fantasy-style storytelling** — narrative cutscenes
that *bridge* into each fight. This doc is the map of how the two halves connect
and where to extend them.

## The core loop (Tournament mode)

```
Title → Menu → Choose Fighter
      → CUTSCENE (FF text-box narrative)        ← story
      → VS CARD (anime splash + trash talk)     ← bridge
      → FIGHT (MK/SF combat, best-of-3)         ← action
      → win:  POST-WIN card → next floor
              (act-break CUTSCENE before Onyx & Titus)
      → lose: HELL — fall to the Pit, fight the demon
              win:  escape CUTSCENE → resume the same floor
              lose: GAME OVER → start the run over
      → clear floor 9 (Titus) → EPILOGUE → Victory
```

The **bridge** is the cutscene → VS-card → fight chain. Story sets stakes, the VS
card hands off to combat, the result feeds the next story beat. That hand-off is
the whole "FF between MK fights" feel.

## Where it lives in code (so it's extendable)

| Piece | File | Notes |
|-------|------|-------|
| Narrative panels | `Engine/StoryMode.swift` → `StoryScript` | `intro`, `beforeOnyx`, `beforeTitus`, `hellEntry`, `hellEscape`. Pure data — add panels freely. |
| Cutscene player | `Views.swift` → `CutsceneView` | Speaker portrait (`FaceView`) + text box + NEXT. |
| Flow / routing | `GameFlow.swift` | `playCutscene(_:then:)`, `advanceCutscene()`, `CutsceneThen` decides cutscene→card or cutscene→fight. |
| Ladder | `Engine/StoryMode.swift` → `ladder` | 9 floors of opponent + pre/post dialogue. |
| The Pit (Hell) | `GameFlow.matchEnded` + `CharacterSpec.demon` + `hell` stage | `inHell` reroutes the next fight to the demon; win resumes, loss restarts. |
| Combat | `Engine/CombatSystem.swift` | The MK/SF half: combos, specials, throws, juggles, parry, armor, dizzy. |
| Resume | `ResumeStore` | A lock-out mid-run resumes at the saved floor. |

## How to add a story beat (the bridge in practice)

1. Add panels to a `StoryScript` array (narrator = `speakerID: nil`, or a
   character id for a portrait).
2. Call `playCutscene(StoryScript.yourBeat, then: .storyCard)` at the right
   moment in `GameFlow` (e.g. inside `continueStory()` for a floor).
3. The fight that follows is whatever `opponentSpec` resolves to — so the same
   bridge works for any opponent, the Pit demon included.

## Final-boss rule (unchanged, by design)

The last opponent, **Titus**, is the **undefeatable boxer**: he takes **zero
damage** until you perform the secret rite mid-fight (`BossRitual`). Story and
combat reinforce each other here — the cutscene tells you he can't be beaten by
damage, and the engine enforces it.

## Roadmap to deepen the FF side (next steps)

- **Per-character story routes**: give each fighter their own `ladder`/cutscenes
  and a unique ending (FF-style character arcs). The flow already keys off
  `playerSpec`, so this is mostly content + a route table.
- **Branching**: `CutsceneThen` can grow more cases (e.g. a midpoint choice).
- **Map/overworld screen** between floors for a stronger RPG feel.
- **Voiced text crawl / typewriter** effect in `CutsceneView` for PS1-era flavor.

## Honest status

All of the above is wired and compiles by inspection, but this environment has no
Swift toolchain — it needs an Xcode build + device run to confirm. The FF/MK
*structure* is in place; tuning the pacing and the look is the on-device work.
