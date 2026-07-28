# OT6 v0.6-rc1 — Raid on Vector (release candidate)

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch containing only the
differences from the original game.

This is a **release candidate** for playtesting, not the v0.6 tag. Known
gaps are listed below on purpose — gaps and todos are nothing to be
ashamed of; silent ones are.

## How to play

Apply `ot6-v0.6-rc1.bps` to a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7` using a BPS patcher such as
Flips or beat. The patcher will reject any other ROM.

Play from the beginning through the Raid on Vector: the Magitek Research
Facility, Ifrit and Shiva, Number 024, the minecart and Number 128, the
Cranes, the escape, and Terra's return. The supported stop point is the
first stable world-map moment after Terra rejoins the roster (save there —
it is the v0.7 handoff point).

## What's changed since v0.5

- The playable frontier extends through Vector and the entire Magitek
  Research Facility to Terra's return.
- **Battle MP is now universal.** Characters who know no spells previously
  entered battle with an empty MP pool while every ability carried a
  price — Blitz, Tools, Bushido, and Steal could grey out or silently
  waste the turn. Every character now brings their save's MP into battle,
  and spend is written back exactly. (This bug shipped in v0.5; if your
  early-game Blitzes never worked, this was why.)
- **Ifrit and Shiva join the magicite roster as complete sub-job
  redesigns** — Ifrit "the Furnace" (weight: +5 vigor) and Shiva "the
  Rime" (economy: +4 magic, a re-authored divine). Equip them like any
  stone; their kits come and go with them.
- **The esper detail page tells the truth**: the dead vanilla learn-rate
  columns are gone, and every stone shows its while-worn stat bonus
  ("While worn...Vigor + 5").
- **A new save point** sits in the antechamber before Number 024 — the
  band's one authored addition; the vanilla save rooms and the world map
  cover the rest.
- The Vector/Factory bestiary carries hand-authored break rows tuned to
  the party you actually have — much of the Factory answers to pierce and
  bludgeon rather than slash, and the minecart's Mag Roaders are a
  bludgeon check.
- A save whose checksum happens to be exactly zero is no longer silently
  treated as an empty slot (a vanilla save-loss bug, fixed).

## Known gaps in this RC, on purpose

- **Setzer's Slot is vanilla and free.** Boost currently multiplies its
  damage like an ordinary verb; the designed chance-verb treatment (boost
  buys reel certainty) is not yet built, and Slot carries no MP price yet.
  His divine (Jackpot) and the Gambler/Merchant verbs (Coin Toss, Hired
  Help) are designed but unbuilt — his kit today is honest vanilla.
- **Steal costs 2 MP and no menu surface says so.** The charge is real;
  the number is invisible. Telling you here until it has a home on screen.
- **Setzer's cards and dice wear the ¤ (special) break icon, and nothing
  in this band is ¤-weak.** Deliberate for now (the first ¤ keys are
  planned post-Vector), but the icon teaches a lesson you can't yet use.
- Terra returns *available but not active*; her rejoin is the stop point,
  not a playable stretch.

## What we'd like to know

- Does the Factory band's break authoring land — do pierce and bludgeon
  feel like real answers, or does slash still solve everything?
- Ifrit vs Shiva: does holding one over the other feel like a real
  choice, and is the "While worn" line enough to make that choice
  legible?
- Is the save cadence right — did the pre-024 save point matter, and did
  any stretch feel unfairly far from a save?
- Number 128 and the Cranes: do the multi-part fights read as break
  puzzles or HP walls?
- With MP now real for everyone from the first battle: does the early
  game's ability economy (pre-esper) feel like decisions or like rationing?
