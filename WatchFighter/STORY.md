# WATCHFIGHTER: ASCENDANT — Story & World

All characters, names, places, and dialogue below are **original** to this
project. The game replicates genre *mechanics*, not any existing game's content.

---

## Premise

Every hundred years a tower called **THE ASCENDANT** opens its gate. Six
fighters answer the call and climb it floor by floor, each floor guarded by one
of the others. At the summit waits the **host**, who built the tower and has
never been beaten — and never explained why he keeps it.

You climb anyway.

The hook: the tower doesn't grant a wish or a prize. It grants the *gate* — the
right to decide who climbs next century, and why. Every champion before has shut
it behind them. Your character's arc is deciding what to do with that power.

---

## The cast

### Tetsu — "The Open Palm"  *(all-rounder / default)*
A wandering martial artist chasing the meaning of a master's last lesson. Enters
every tournament to test the answer. Balanced tools, a launching palm strike,
the player's natural on-ramp.
**Home stage:** Dawn Dojo.

### Volt — "The Live Wire"  *(rushdown)*
A street-circuit racer rebuilt with arc-reactor limbs. Fights to outrun the
corporation that wired her. Fast walk speed, a dashing special that closes space.
**Home stage:** Neon Strip.

### Ember — "The Last Cinder"  *(fire zoner)*
A volcano-shrine guardian. Each match feeds the eternal flame she is sworn to
keep alive. Throws cinder projectiles to control the lane.
**Home stage:** Ash Caldera.

### Frost — "The Quiet Winter"  *(ice zoner)*
An exiled cryomancer hunting the rival who shattered her clan. Speaks only in the
cold. A slow, heavy freezing projectile rewards patience.
**Home stage:** Still Glacier.

### Mirage — "The Borrowed Face"  *(teleport rushdown)*
A masked phantom who steps between seconds. No one agrees on what Mirage wants —
least of all Mirage. Longest-reaching special, highest risk.
**Home stage:** Midnight Temple.

### Bastion — "The Standing Wall"  *(armored grappler)*
A demolition golem awakened beneath a fallen city. Believes the tournament
decides who rebuilds the world. Slow, tanky, a launching slam.
**Home stage:** Fallen City.

### Corsair — "The Tipsy Tide"  *(swashbuckler duelist)*
A grinning sea-rogue climbing the tower for the one treasure the ocean never
gave up. Loose footwork, long cutlass reach, lands hard when you least expect.
*(Original pirate archetype — not based on any actor or existing character.)*
**Home stage:** Rogue Tide.

### Nova — "The Last Contract"  *(bounty-hunter zoner)*
A helmeted gun-for-hire tracking a bounty that climbed the tower and never came
back down. Keeps the lane honest with plasma. *(Original sci-fi archetype.)*
**Home stage:** Orbit Nine.

### Onyx — "The Ascendant"  *(penultimate boss / tower host)*
The one who built the tower. He guards the second-to-last floor and steps aside
for whoever can reach the true final door. Overtuned launcher.
**Home stage:** The Summit.

### Titus — "The Undefeated"  *(FINAL BOSS)*
An undefeated heavyweight boxer with bold geometric face markings, silent behind
his fists. The tower's last door is a square of canvas and two gloves. His
**haymaker is armored** — it powers straight through your pokes and launches for
huge damage. The only safe answer is a clean **parry**; mistime it and the round
is gone. Brutally hard, *but beatable* — the wall that finally cracks when you
master it, not a literally impossible fight.
*(Original character — not based on any real boxer's name, face, or likeness.)*
**Home stage:** The Last Bell (a boxing ring).

---

## Stages (parallax backdrops)

Each is rendered procedurally (gradient sky + two parallax silhouette layers +
ground + accent glow) so they cost almost nothing in memory:

| Stage | Motif | Mood |
|-------|-------|------|
| Neon Strip | city skyline | violet night, cyan signage |
| Fallen City | broken skyline | dusty amber dusk |
| Ash Caldera | jagged peaks | red glow, lava glints |
| Still Glacier | ice spires | cold blues, white glints |
| Midnight Temple | pagoda peaks | indigo + violet accent |
| Dawn Dojo | beams & screens | warm sunrise |
| The Summit | obsidian monolith | near-black, magenta accent |

---

## Arcade ladder (Story Mode)

The player picks any selectable fighter and climbs the same ladder. Before each
fight the opponent speaks; after each win the player reflects. Beat the boss to
reach one of two endings (victory = you keep and re-open the gate; defeat = the
tower keeps what it takes, retry).

1. **Volt** — *"You came up the wrong stairwell, slow-hand…"*
2. **Ember** — *"The flame remembers everyone who climbs…"*
3. **Frost** — *"...you are warm. That is your only mistake."*
4. **Corsair** — *"Every tide takes the high ground back. Drink?"*
5. **Mirage** — *"Which of us is real? Win and I'll tell you."*
6. **Nova** — *"Nothing personal. You're just standing in front of a contract."*
7. **Bastion** — *"The tower falls one day. I decide who is standing when it does."*
8. **Onyx** — *"You climbed well. The last door was never mine."*
9. **Titus** *(FINAL BOSS)* — *(silence; he just raises his fists)*

(Full pre/post lines live in `Engine/StoryMode.swift` as `StoryScript.ladder`.)

---

## The final boss is UNBEATABLE — until "the rite"

Titus cannot be hurt by normal means. Every clean hit reads **NO EFFECT** and
deals zero damage; if the timer runs out he wins. He is only made mortal by
performing a secret **process, perfectly**, mid-fight:

> **▽ parry · ▽ parry · • light · ◆ heavy · ★ special**
> (swipe-down, swipe-down, tap-top, tap-bottom, then charge the Crown to ≥50%
> and tap the far right for the special)

The key gestures must land **in order**. Incidental inputs (block, step, Crown
charge) are forgiven, but a wrong *key* gesture resets the chain. Land all five
and **THE BELL RINGS** — Titus becomes mortal for the rest of the match and you
can finally take him down. The on-screen "RING THE BELL ▽ ▽ • ◆ ★" tracker shows
your progress; the pre-fight card spells it out.

Design intent: not a cheap "impossible" wall, but a hidden mastery check — the
champ is untouchable until you prove you know the rite, then it's a real fight.
Implemented as the pure `BossRitual` tracker + `CombatSystem.ritualBroken`.

---

## How the story is wired

- `StoryMode` (pure) holds the ladder index and exposes the current opponent +
  dialogue beat. `advance()` walks the ladder and flags completion.
- `GameFlow` (SwiftUI `ObservableObject`) is the screen router: Title →
  Character Select → Story card (pre-fight) → Fight → Story card (post-win) →
  next floor, or → Ending.
- `FightScene` runs one best-of-3 match and reports the winner back to
  `GameFlow`, which advances the story or shows the ending.
