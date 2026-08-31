# Watch Smash

Compact watchOS arcade brawler built for short Apple Watch sessions. The
fighters use original high-detail bitmap sprites with a 1990s digitized
arcade-fighter feel, not replicas of existing game characters.

The story moves through a 15-fight arcade ladder with original parody
archetypes: a full-height viper assassin, pirate captain, dragon-fist martial
artist, beach-rescue brawler, runway fighter, special-ops soldier, tech baron,
gold-suit blowhard, ice-regent grappler, red-carpet striker, cage fighter, war
king, and a near-impossible heavyweight boss. Wins advance to the next rival,
losses retry the current chapter, and two losses end the run.

The game uses stylized blood sparks, finisher bursts, bitmap and procedural
fighter animation, and bundled retro synthetic voice clips for callouts such as
FIGHT, COMBO, FINISH, and MILLION SHOT. Characters are original and intentionally
avoid exact celebrity, fighter, or classic-game replicas.

## Modes

- Tournament: the full 15-fight ladder with two-loss elimination.
- VS: single-fight challenges against the ladder roster. Nyra starts unlocked,
  and each tournament win opens the next rival.
- Learn: repeatable training rounds with watch-sized prompts for footwork,
  strikes, guard, dash, and meter timing.

## Build

```sh
xcodegen generate
xcodebuild -project Watchsmash.xcodeproj -scheme Watchsmash -sdk watchsimulator -destination 'generic/platform=watchOS Simulator' build
```

## Controls

- Digital Crown or drag: steer
- Center press or drag: strike
- High press or drag: jump kick
- Low press or drag: crouch guard
- Close center press: throw
- Double tap: dash strike, upgraded to a special when the meter is full

The game uses SwiftUI, Canvas, and bundled PNG sprite assets, so it has no
external runtime dependencies.

## Simulator demo

For visual smoke checks without touch input, launch with:

```sh
SIMCTL_CHILD_WATCHSMASH_DEMO=1 xcrun simctl launch --terminate-running-process <watch-udid> com.alphaeliteholdings.watchfighter
```
