# ROBIN HOOD: GRAND THEFT EDITION
### One-page pitch — NES-era Zelda meets GTA6, reskinned as a Robin Hood power fantasy

---

## The Hook
An 8-bit, top-down open world where you don't save the princess — you **destabilize a regime**.
Zelda's body (tile-based overworld, item-gated dungeons, chiptune score) with GTA's brain
(wanted levels, heists, crew management, an economy of crime). Steal from the rich. Give to
the poor. Watch the county turn on its masters.

## Pillars
1. **Crime has a temperature.** Every theft heats up the *Sheriff's Bounty*. Guards hunt you
   across a seamless overworld with directional sightlines — no cover system in this "era,"
   so stealth is positioning, not crouching.
2. **Loot is a moral choice.** Every purse splits between *you* (bow, arrows, armor, tools)
   and *the people* (a visible regional Poverty Meter that unlocks safehouses, informants,
   recruits, and black-market fences).
3. **Two reputations, one outlaw.** *Nobility Heat* brings bounty hunters; *Commoner Fame*
   brings open doors, tips, and — eventually — riots on your behalf.

## The World
Sherwood Forest, the River Trent, Nottingham village, and Nottingham Castle as one seamless
8-bit map — no loading screens between zones. Strict NES constraints: 54-color palette,
chunky 16×16 sprites, 8-directional movement, full-scroll overworld, screen-flip interiors.

## Core Loop
**Scout → Rob → Evade → Redistribute → Upgrade → Escalate.**
Rob a tax caravan on the King's Road. Bounty spikes; the soundtrack's tempo climbs with it.
Lose the guards in the treeline, then walk gold into a starving village. Fame rises, a
safehouse opens, and the next, bigger score becomes possible — until you're ready to storm
the castle.

## Systems
- **Sheriff's Bounty (heat):** 0–5 stars. Crimes witnessed heat faster than crimes unseen.
  Hunters spawn per star and pursue across zones. Heat decays only out of sight — faster
  near friendly villages once Fame is high ("the people hide you").
- **Zelda-style dungeoneering:** the Sheriff's dungeon, St. Mary's Abbey vault, and the
  castle treasury are item-gated: grappling hook for the moat, bombs for false walls, the
  Horn of Sherwood to summon Little John mid-heist.
- **Merry Men as crew:** recruit Little John (breaks gates), Friar Tuck (heals, launders
  tithes), Will Scarlet (disguises), Much (distractions). Call-ins during heists, GTA-crew
  style; each has a loyalty mission.
- **Economy:** fences buy stolen plate; poached venison feeds villages; arrows, quivers,
  and the Longbow of Locksley gate later missions.

## Mission List (vertical slice → Act 3)
**Act 1 — Outlaw** *(tutorial ring around the forest camp)*
1. *Ashes of Locksley* — return from the Crusades; your village burns. Learn movement, bow, theft.
2. *The King's Venison* — poach a royal deer; first heat, first escape into the trees.
3. *Toll Road* — rob your first tax caravan on the King's Road.
4. *Bread Before Gold* — deliver the take to Edwinstowe; meet the Poverty Meter; unlock the camp fence.
5. *A Giant at the Ford* — quarterstaff duel on a log bridge; recruit **Little John**.

**Act 2 — Folk Hero**
6. *The Tithe Barn* — first dungeon (St. Mary's Abbey): item-gated vault, recruit **Friar Tuck**.
7. *The Silver Arrow* — the Sheriff's trap: enter the archery tournament in disguise, win, escape at 5 stars.
8. *Scarlet Letters* — spring **Will Scarlet** from a prison convoy; unlock disguises.
9. *The Great Caravan* — three-crew simultaneous heist on the quarterly tax shipment (call-ins tutorial).
10. *Guy of Gisburne* — a bounty hunter who hunts *you* mission-to-mission until confronted.

**Act 3 — Uprising**
11. *Kindling* — push three regions' Poverty Meters to full; arm the villages you fed.
12. *The Sheriff's Dungeon* — infiltrate to free captured Merry Men; grappling-hook gauntlet.
13. *Storm Nottingham* — the castle as the final dungeon, with everything you built:
    crew call-ins, rioting villagers, and every upgrade you chose to keep instead of give away.

## Audio Direction
Lute-and-recorder chiptune (2A03-style square leads, triangle bass). The score's **tempo is
bound to your bounty level** — a calm pastoral round at 0 stars becomes a galloping tarantella
at 5, then relaxes as you cool off. Diegetic horn blasts when guards spot you.

## The Prototype (this folder)
`index.html` is a zero-dependency playable slice: seamless forest/village/castle overworld,
8-dir movement, robbable tax caravans, poachable royal deer, the castle treasury, guards with
visible sight-cones, star-based bounty with hunters, donation-driven Fame with a Poverty
Meter, and a WebAudio chiptune that speeds up with your heat. Open it in a browser and play.

It also includes a first pass at the three flagship systems:
- **St Mary's Abbey** — a Zelda-style interior dungeon behind the arched door north of the
  village: find the Prior's key in a guarded side room, unlock the vault, and return the
  tithes to the people (+200g, +2 Fame, +2 bounty). Abbey guards attack trespassers on sight.
- **Bow & arrow** — X fires in your facing direction; arrows knock guards out cold (a small
  bounty for assault), down bounty hunters, and take deer at range. Fletch 5 arrows for 10g
  at the camp fire.
- **Little John** — joins the Merry Men at Fame 3. Press C to sound the Horn of Sherwood:
  he charges the nearest guard or hunter, flattens them, and melts back into the trees
  (30s cooldown).

**Controls:** Arrows/WASD move · Space interact (rob / poach / donate / enter) ·
X shoot · C call Little John · M mute.
