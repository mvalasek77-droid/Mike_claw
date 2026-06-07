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

### Onyx — "The Ascendant"  *(final boss)*
The one who built the tower and never lost it. Wears every champion's last move
as a trophy. Overtuned health and damage.
**Home stage:** The Summit.

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

The player picks any of the six and climbs the same six-floor ladder. Before each
fight the opponent speaks; after each win the player reflects. Beat the boss to
reach one of two endings (victory = you keep and re-open the gate; defeat = the
tower keeps what it takes, retry).

1. **Volt** — *"You came up the wrong stairwell, slow-hand. I'll show you the express."*
2. **Ember** — *"The flame remembers everyone who climbs. It will remember you burning."*
3. **Frost** — *"...you are warm. That is your only mistake."*
4. **Mirage** — *"Which of us is real? Win and I'll tell you. Lose and it won't matter."*
5. **Bastion** — *"The tower falls one day. I decide who is standing when it does."*
6. **Onyx** — *"You climbed well. Now learn why no one keeps what they win up here."*

(Full pre-fight and post-win lines live in `Engine/StoryMode.swift` as
`StoryScript.ladder`, so writers can edit copy without touching game logic.)

---

## How the story is wired

- `StoryMode` (pure) holds the ladder index and exposes the current opponent +
  dialogue beat. `advance()` walks the ladder and flags completion.
- `GameFlow` (SwiftUI `ObservableObject`) is the screen router: Title →
  Character Select → Story card (pre-fight) → Fight → Story card (post-win) →
  next floor, or → Ending.
- `FightScene` runs one best-of-3 match and reports the winner back to
  `GameFlow`, which advances the story or shows the ending.
