# ETERNAL COMBAT — Ship-Readiness Checklist

An honest accounting of what's done and what stands between this and the App
Store. I will not mark this "ready to ship" — that's a claim only an actual
build, device test, and App Review can earn. Here's the real path.

## ✅ Done

- Complete original game: 10 fighters + 2 bosses, 12 stages, story (9 floors),
  training, progression/unlocks, settings (music, blood, CPU difficulty).
- Classic-fighter base: jumps/aerials/2D boxes, throws + techs, combo cancels +
  damage scaling, dizzy/stun, parry, armor, projectiles + cooldown, super/EX.
- Game feel: hitstop, camera shake, hit sparks, combo praise, finisher beat,
  optional blood, synthesized SFX + looping music.
- Personality: per-character win quotes + taunts (humor).
- No-soft-lock navigation (in-fight exit button).
- Deterministic, headless-tested engine (7 XCTest suites).

## ⛔ Blocking ship (must do, in order)

1. **Xcode build pass.** Nothing here has been compiled — no Swift toolchain in
   the dev container. `xcodegen generate && open WatchFighter.xcodeproj`, build
   the watch target, fix whatever the compiler surfaces (esp. SpriteKit/SwiftUI/
   AVFoundation specifics). **This is the #1 gate.**
2. **Run the test suites** (`Tests/`) on a watch simulator; fix any red.
3. **Device pass on real hardware** — 60fps check, Crown feel, gesture accuracy,
   haptics, battery/thermals during a full best-of-3, audio behavior.
4. **App icon + assets** — `Assets.xcassets/AppIcon` is a placeholder; needs a
   real 1024px icon set and any launch assets.
5. **Content rating** — with **BLOOD on**, file the correct App Store age rating
   (cartoon/fantasy violence; blood). Default-off keeps the baseline lower.
6. **Online versus** — currently stubbed. Real Watch play needs an iPhone-relay
   transport (WatchConnectivity + the phone's networking). Either build it or
   ship v1 as single-player + local only and label Versus "coming soon".
7. **Privacy / App Store metadata** — privacy nutrition label (no data collected
   if it stays offline), description, screenshots, keywords.

## 🟡 Recommended before 1.0

- Accessibility: VoiceOver labels on all menu controls (exit button done),
  Reduce Motion honoring (skip camera shake), Dynamic Type review of hardcoded
  font sizes.
- Settings persistence audit (music currently in-memory; blood persists).
- Tutorial/first-run flow pointing at How To Play.
- Balance pass #2 (see `BALANCE.md`) once playtested on device.

## 📈 Post-1.0 roadmap

- iPhone-relayed online versus + ranked.
- Per-character aerials/specials depth; a 13th unlockable secret fighter.
- Real recorded SFX/voice + licensed-or-original music.
- iOS companion app (stat tracking, roster gallery) — also where "iPhone flows"
  would live; the game itself is watchOS-only today.
- True iOS/watchOS 26 "Liquid Glass" material adoption once validated in a build.

## Reality check on "PS5 on a watch"

A 1.5" 60fps device with ~1GB RAM and a tiny battery can't be a PS5 — but this
*can* be a genuinely premium, juicy 2D fighter that feels great on the wrist.
That's the bar I'm building to.
