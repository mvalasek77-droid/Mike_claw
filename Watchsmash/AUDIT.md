# Watch Smash — Audit & Improvements (movement + bugs)

Static audit of the consolidated game (Codex base + FF layer). Engine logic is
verified by reading; needs an Xcode build to confirm runtime.

## Bug found & FIXED
- **Pit cutscene never fired.** My loss→Pit hook compared `opponentWins` frame-
  locally, but a loss increments `opponentWins` on the round-resolve frame while
  the round actually restarts ~2.25s later (after `roundPauseClock`). So the check
  was always false at the restart frame. **Fix:** a persistent `pitPending` flag
  set the instant a loss registers, consumed at the next round start (reset in
  `resetInputTracking`). `GameScreen.swift`.

## Improvements APPLIED (smooth + quick motion)
Applies to **all** fighters, including Codex's digitized sprites.
- **Smooth strike envelope** (`actionStrike`): attacks/hits now thrust out fast
  and ease back (smoothstep, peak ~34% in) instead of snapping to a pose and
  popping back. Drives the body lunge, recoil, jump-kick lift, and the procedural
  punch/kick offsets. Requires the new `DuelFighter.actionDuration` (set in
  `setAction`). `GameModels.swift`, `WatchsmashEngine.swift`, `WatchsmashCanvas.swift`.
- **Quicker player tracking:** Crown/touch follow response `13.5 → 17.5` — snappier
  control, still lerp-smooth. `WatchsmashEngine.swift`.
- **Quicker stride:** procedural walk cadence `sin(t*12)*0.24 → sin(t*15)*0.26`.

## Recommendations (NOT applied — avoid touching Codex's tested balance blind)
- Consider a per-archetype attack-speed multiplier so rushdown fighters feel even
  snappier (data-only; tune after a build).
- The digitized fighters' `stride`/`lean` (canvas ~659/685) are time-based, so they
  animate even when standing still; consider gating to `.walk` for stillness.
- Add Reduce-Motion handling for finisher bursts / screen shake (accessibility).
- The opponent AI re-randomizes pressure every 0.16–0.42s; fine, but logging a
  difficulty curve per chapter would help tuning.

## Verify after build
1. `xcodegen generate` → build to a Watch.
2. Throw a few jabs/kicks/specials — strikes should extend fast and recover
   smoothly (no pop), and walking should feel quick and fluid.
3. Lose floor 1 on purpose — the **Pit** cutscene should now appear before the
   refight (the fixed bug).
