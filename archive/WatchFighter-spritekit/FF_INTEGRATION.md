# FF × Watchfighter — Integration Package

How to add the **Final-Fantasy-style storytelling layer** (cutscenes between
fights) and the **Hell death→second-chance loop** onto **Codex's Watchfighter**
(the base game: SwiftUI Canvas, `WatchfighterEngine`, 16 fighters with digitized
sprites, Tournament/VS/Learn). This is additive — it does not touch Codex's
combat engine or rendering, so it won't break the working build.

> Target codebase: `AIMarketplace/backend/Watchfighter` on branch
> `claude/ai-marketplace-ios-app-iUYui` (commit 0fab06f). Types referenced below
> are Codex's: `GameScreen`, `GameScreenMode`, `FightMode`, `StoryChapter`,
> `WatchfighterEngine`/`WatchfighterState`.

## 1. Cutscene system (new, ~1 small file + 1 screen mode)

Add a screen mode and a tiny data model. No engine changes.

```swift
// Cutscene.swift  (new file)
struct CutscenePanel: Equatable {
    let speaker: String?   // nil = narrator; else a fighter display name
    let text: String
}

enum FFScript {
    static let intro: [CutscenePanel] = [
        .init(speaker: nil, text: "The hundred-year gate of THE ASCENDANT grinds open. Champions go up. None come down."),
        .init(speaker: nil, text: "The town stopped mourning long ago — now it sells tickets and waits for the next fool to climb."),
        .init(speaker: "Nyra", text: "Another climber? The first floor is mine, and I don't do slow."),
        .init(speaker: nil, text: "Fifteen floors. Fifteen fighters who already gave everything to the tower. You tighten your wraps."),
    ]
    // Act breaks — fire before specific chapters (by index).
    static let beforeBoss: [CutscenePanel] = [
        .init(speaker: nil, text: "The last door is a square of canvas and two gloves."),
        .init(speaker: "Titus", text: "(He says nothing. He raises his fists. No bell has rung for him in a thousand years.)"),
        .init(speaker: nil, text: "Damage alone won't drop him. Land the Million Shot — a SPECIAL on an 8+ combo — or join the wall."),
    ]
    static let hellEntry: [CutscenePanel] = [
        .init(speaker: nil, text: "The floor drops out. You fall past the tower, past the town, into heat."),
        .init(speaker: "Warden", text: "Another the tower couldn't keep. Beat me and crawl back up. Fail, and you stoke the furnace forever."),
    ]
    static let hellEscape: [CutscenePanel] = [
        .init(speaker: "Warden", text: "…tch. Go. The stairs are yours again."),
        .init(speaker: nil, text: "You climb out of the smoke and back onto the floor you fell from. Second chances burn."),
    ]
    // Per-chapter one-liners keyed by StoryChapter index (0...14). Optional flavor.
    static let chapterIntro: [Int: [CutscenePanel]] = [ /* fill per chapter */ ]
}
```

UI (matches Codex's SwiftUI/Canvas style — a text box + speaker + NEXT):

```swift
// In GameScreen, add a case to GameScreenMode: `case cutscene`
// and render this when mode == .cutscene:
private func cutsceneView(_ panels: [CutscenePanel], index: Int, onAdvance: @escaping () -> Void) -> some View {
    let p = panels[min(index, panels.count - 1)]
    return VStack(alignment: .leading, spacing: 6) {
        Text(p.speaker ?? "THE ASCENDANT").font(.system(size: 12, weight: .heavy))
            .foregroundStyle(.pink)
        Text(p.text).font(.system(size: 11)).foregroundStyle(.white)
            .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.55)))
        Button(index + 1 < panels.count ? "NEXT ▶" : "FIGHT!", action: onAdvance)
            .font(.system(size: 12, weight: .bold))
    }.padding(8)
}
```

State to add to `GameScreen` (or a small `CutsceneFlow`): `cutscenePanels`,
`cutsceneIndex`, and a `cutsceneThen` closure/enum (`.toFight` or `.toCard`).
`advance()` increments; at the end it runs `cutsceneThen`.

## 2. Where to hook it into Codex's flow

- **Tournament start:** before chapter 0's fight, set `mode = .cutscene` with
  `FFScript.intro`, then proceed to the existing fighter card / fight.
- **Act breaks:** in the chapter-advance path, if the next chapter is the boss
  (index 14, "Million Room"), play `FFScript.beforeBoss` first.
- **Per-chapter flavor (optional):** play `FFScript.chapterIntro[index]` if present.

## 3. Hell death→second-chance loop (meta-progression)

Codex's tournament currently is **two-loss elimination**. Replace the *first*
loss with a Hell detour:

```
Tournament fight LOSS:
  if !inHell:
      inHell = true
      mode = .cutscene (FFScript.hellEntry, then: fight the WARDEN/demon)
      // reuse Titus's "titan" style or add a `demon` archetype for the Pit boss
  else (lost IN hell):
      run over → gameOver
Hell fight WIN:
  inHell = false
  mode = .cutscene (FFScript.hellEscape, then: refight the SAME chapter)
```

Add `inHell: Bool` to the campaign state. The Pit opponent can be the existing
`titan`/Titus visuals recolored, or a new `demon` archetype (red hide, pitchfork
— Codex's procedural fighter profile supports a weapon limb). Keep the existing
two-loss rule as the *Hell* loss (lose in Hell = over), which preserves stakes.

## 4. Content is original

All cutscene text above is original to this project (no real people, no
copyrighted characters or lines). Codex's roster is already original parody
archetypes — keep it.

## 5. Source of the FF logic (reference implementation)

My SpriteKit version on branch `claude/fighting-game-apple-watch-bk0xF`
implements this exact flow — see `GameFlow.swift` (`playCutscene`,
`advanceCutscene`, `inHell`, `matchEnded`) and `Engine/StoryMode.swift`
(`StoryScript` panels). Port the *structure*, not the SpriteKit code.

## Open decision (for the human)

To actually land this in Codex's game I need either:
- **Permission to commit to `claude/ai-marketplace-ios-app-iUYui`** (I'll add the
  files above directly), or
- a copy of Codex's `Watchfighter` brought into a branch I'm cleared to push to.

Until then this package is the drop-in spec.
