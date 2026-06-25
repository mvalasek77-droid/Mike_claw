# ETERNAL COMBAT — Rendering (all-procedural, no art assets)

You don't need an artist. Every visual in this game is **generated in code at
runtime** — there are zero sprite/model files. Two interchangeable paths exist
behind one `FighterRenderer` protocol:

## 1. `SkeletonRenderer` — the procedural fighter (default, no assets)

A fighter is drawn as an **outlined, shaded figure with body mass** (not stick
lines), driven by the pure `Animator` poses, plus three generative techniques:

- **Code-generated rim/impact light.** A soft radial-gradient sprite is rendered
  once with Core Graphics (`SkeletonRenderer.softGlow`) and tinted per character.
  It *flares* during attack startup/active frames and blinds white on impact —
  fake dynamic lighting, distilled from the "PS2/N64 lit-character" mood without
  any 3D or textures.
- **Verlet "spirit ribbon".** Each fighter trails a ribbon simulated with real
  cloth physics (verlet integration: inertia + gravity + rigid segment
  constraints). It reacts to movement, jumps, and hits — life and motion with no
  animation frames. (`SkeletonRenderer.updateRibbon`)
- **Two-tone outline shading** for readable silhouettes at 1.5".

Everything is deterministic (same combat state → same look), so it's netplay-safe.

## 2. `SpriteFighter` — real sprite art (automatic drop-in, if it ever exists)

The instant a **Sprite Atlas** named `<id>_atlas` ships in `Assets.xcassets`,
`FightScene.makeRenderer` switches that character to textured sprites — no engine
changes. Frame naming convention:

```
<id>_<anim>_<n>      e.g.  volt_idle_0, volt_idle_1, volt_attack_0, volt_hurt_0
```

Animations consumed: `idle`, `attack`, `hurt`, `block`, `jump`, `down`
(missing sets fall back to `idle`). Suggested frame size ≈ **120×120 px** (≈60pt
tall on watch @2x), feet centered horizontally, ~12 fps.

## Why this approach

- **No asset pipeline, no artist, no licensing** — the whole game is math.
- **Tiny footprint** — ideal for the watch's memory/battery limits.
- **Distill, don't copy** — the *mood* of classic fighters (lighting, motion,
  pace, music) is recreated from scratch in original code; nothing is lifted.

## Performance budget

- Procedural fighter ≈ 14 shape nodes + 1 glow sprite + 1 ribbon (10 pts) each.
- Particle bursts are short-lived and capped; camera shake/zoom honor Reduce
  Motion. Target 60fps; degrade gracefully on smaller/older watches.
