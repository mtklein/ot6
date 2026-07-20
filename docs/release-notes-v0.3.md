# OT6 v0.3

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch, a file that
records the differences between the original ROM and the modified ROM.

## How to play

Apply ot6-v0.3.bps to a Final Fantasy III (USA) 1.0 ROM (sha1
4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7) using any BPS patcher (Flips,
beat). The patcher will reject any other ROM.

Play from a new game through the Battle for Narshe — beat Kefka on the
cliffs, then stop. That is the full opening act: the mines, Figaro,
Mt. Kolts, the Returners, the Lete River, all three scenarios of the
split, the reunion, and the battle.

Past that stop point the new systems run but are not balanced yet.

## What's changed since v0.2

- **The playable stretch triples.** v0.2 ended at Vargas; v0.3 plays
  the Returner hideout, the Lete River, Locke's South Figaro, Sabin's
  long road (the Imperial Camp, Doma, the Phantom Train, Baren Falls,
  the Serpent Trench), the Terra/Banon rapids, and the Battle for
  Narshe against Kefka himself.
- **Breaks land now.** On Mt. Kolts and beyond, enemy shields empty a
  round before the kill, so the Broken window — lose their turns, take
  double damage — is a real part of ordinary fights instead of a
  technicality on the killing blow. Boss fights are built around it:
  break Vargas at the right moment and finish him properly.
- **Cyan joins with Bushido rebuilt on Boost Points.** No charge gauge:
  your banked BP picks the technique. The bar in his menu is a
  selector now, not a timer.
- **Celes joins with Runic that pays.** Absorbing a spell banks a
  Boost Point on top of the MP — and the Narshe school's advisor
  finally says so.
- **The Empire's armor fears one right tool.** The school's hint pays
  off: Magitek and heavy armor, and Doma's soldiers, all answer to
  Edgar's Bio Blaster — most visibly in the Battle for Narshe. (Kefka
  has his own weaknesses. Probe him.)
- **Fixed:** Boost pips no longer render as stray numbers (they were
  being overwritten by damage-numeral graphics); boosting after an
  action is confirmed no longer silently wastes points; counterattacks
  no longer deliver boosted damage for free; Cyan's techniques can no
  longer be charged the wrong price by late input.

## Known issues

- In battles with many enemies on screen, stray white text characters
  can be overdrawn on the battlefield. Cosmetic; under investigation.
- The moment a weakness is revealed can read slightly early against
  the damage numbers. Measured as honest, but tell us if it bothers
  you.

## What we'd like to know

- Does the difficulty curve land? Early fights are meant to be a
  gentle on-ramp; by Mt. Kolts you should need to Boost to survive,
  and it should feel great when you do. If you hit a wall and had to
  stop and grind, tell us where.
- Do Breaks feel like the payoff of a plan, or an accident?
- Which of the three scenarios played best, and did anything in
  Sabin's long road drag?
