# ETERNAL COMBAT — Balance Notes

First-pass tuning. All values live in `Engine/Roster.swift` (per character) and
`Engine/Move.swift` / `Engine/CombatSystem.swift` (shared systems), so they're
trivial to retune. Numbers are in engine ticks (60/s) and lane points.

## Roster snapshot

| Fighter | HP | Walk | Archetype | Special (dmg / reach) | Notes |
|---------|----|------|-----------|-----------------------|-------|
| Tetsu   | 108 | 2.2 | all-rounder | 17 / 46 (launch) | the baseline |
| Volt    | 100 | 2.6 | rushdown | 16 / 58 | fast, dash special |
| Ember   | 96  | 2.1 | zoner | 14 / projectile | fireball control |
| Frost   | 100 | 1.9 | zoner | 12 / slow projectile | patient |
| Mirage  | 92  | 2.8 | teleport rush | 15 / 70 | glassy, longest non-blade special |
| Bastion | 124 | 1.6 | grappler | 20 / 40 (launch) | crushing heavy (19 dmg) |
| Corsair | 100 | 2.3 | duelist | 16 / 78 | long cutlass |
| Nova    | 98  | 2.2 | zoner | 15 / fast projectile | strong neutral |
| Vesper  | 94  | 2.4 | swordmaster | 18 / 84 (launch) | longest normals, low HP |
| Marina  | 100 | 2.8 | athlete | 15 / 50 | fastest light, best aerials |
| Onyx*   | 150 | 2.4 | boss | 24 / 64 (launch) | unlock by clearing story |
| Titus*  | 180 | 2.5 | FINAL BOSS | 30 / 52 (armor+launch) | **invincible until the rite** |

\* bosses — Onyx is unlockable; Titus is boss-only.

## Design rules of thumb

- **HP band:** selectable cast sits in 92–124. Glass cannons (Vesper, Mirage)
  trade HP for reach/speed; Bastion trades speed for HP + damage.
- **Reach vs HP:** the longer the poke (Vesper 84, Corsair 78), the lower the HP.
- **Bosses break the band on purpose** — Onyx/Titus are meant to feel unfair;
  Titus additionally can't be damaged until the secret rite (`BossRitual`).

## Shared systems (the "feel" knobs)

| System | Value | Where |
|--------|-------|-------|
| Light frame data | 3 / 2 / 6 (s/a/r) | `Move.light` |
| Heavy frame data | 9 / 3 / 16 | `Move.heavy` |
| Combo scaling | 1, 1, .8, .65, .5, .4, .3 (min .25) | `CombatSystem.scaling` |
| Jump velocity / gravity | 11 / 0.85 | `CombatSystem` |
| Parry window | 6 ticks | `CombatSystem.parryWindow` |
| Stun → dizzy | 100 threshold, 0.5 decay | `CombatSystem` |
| Throw tech window | 4 ticks | `CombatSystem.throwTechWindow` |
| Special meter cost | 50 (EX at 100) | `CombatSystem.chargeToFire` |

## Known tuning TODOs

- Air normals are shared across the cast; per-character aerials would deepen the
  jump game (Marina especially).
- Projectile characters (Ember/Frost/Nova) want a recovery/cooldown pass so
  fireball spam is punishable on whiff.
- Boss AI (`.boss`) reaction (4 ticks) may be too strict for casual players — a
  difficulty selector is a candidate for the next pass.
