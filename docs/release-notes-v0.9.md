# OT6 v0.9 — Locke, and the break economy

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch containing only the
differences from the original game.

The playable frontier is unchanged from v0.6, v0.7 and v0.8. Like the
last two, this release is about the game feeling right where you already
are — this time about what things *cost* and what breaking actually buys
you.

## How to play

Apply `ot6-v0.9.bps` to a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7` using a BPS patcher such as
Flips or beat. The patcher will reject any other ROM.

Play from the beginning through the Raid on Vector, the same supported
stop point as v0.8.

## What's changed since v0.8

**Locke has a kit.** Behind the Steal row there's now a thief submenu:
Steal, **Filch** and **Bestow**. Filch takes a shield off — no damage,
no reveal, and it does not care what the monster is weak to, which makes
it the only weakness-independent shield remover in the game. Bestow
hands a Boost Point to an ally. And because the submenu has somewhere to
print a number, **Steal's price is finally visible**; it has been
charged and undisplayed since v0.8.

**Boost-folded spells cost what they are.** Boosting Fire into Fire 3
used to charge you for Fire. The price was being decided before the fold
happened, so the bigger spell rode in behind a bill that had already
been paid. Fire 3 now costs 51 rather than 4, the list shows it, and the
row greys out when you cannot afford it. These tiers run 8–11% of your
pool at the level you would normally *learn* them, and 40–133% at the
level folding reaches them — that gap is what you are buying. *(Thanks
to [@vanorasc](https://github.com/vanorasc) for the idea.)*

**Boosting Runic buys duration, and Celes can act through it.** One,
two or three turns of a standing rune stance at 1, 2 or 3 BP. Two
proposals turned out to be one: vanilla ends the stance *because* she
acted, so the only way she acts without dropping it is for the stance to
outlive her action. The BP it earns is capped at once per round, which
makes a 3-BP Runic come out Boost-neutral against three ordinary turns
while costing a single action. The MP it drinks is still per absorb and
uncapped — that is why a rune knight wants a caster on the other side.

**The broken shield is a shield with a big white X through it.** It was
a shield with a `B` in it, which reads as a 3 at HUD size. That is not a
lettering problem: all six count glyphs share one outline and differ
only across three interior rows, so any symbol-inside-a-shield has to
beat the digits on interior detail alone. The X is drawn over the whole
cell instead, arms leaving the shield at the corners.

**Shields come back after a break now, even if the monster tags out.**
In the Ifrit & Shiva fight, breaking a sibling who then swapped off stage
froze its recovery timer entirely — it would tag back in still broken,
still at zero shields, for well over twice the intended break. Measured
at 4674 frames against an on-stage control's 2159.

**Ability pages show what element they are.** AuraBolt shows pearl, Fire
Dance shows fire, and so on, on the field Blitz page — the same icons
the battle lists use.

**Poison damage over time takes shields off.** This was already true and
is now measured, explained and protected by a test: a poison tick is an
ordinary poison hit with no attacker, so it chips exactly as a poison
spell would. Bio Blaster's plink really was breaking things for you.
Sap does not chip, and a broken monster takes no ticks at all.

## Known gaps, on purpose

- **A broken monster can still act.** Confirmed, measured, and *not*
  fixed in this release: counterattacks and any action already queued
  when the break lands both bypass the gate. In one instrumented fight
  that was 103 actions during break windows, including a broken Ifrit
  casting Fire. The fix is written and measured but cannot land until a
  timing test that currently vetoes a whole bank is made less brittle
  (#66, #67). If a boss hits you during its break, that is this.
- **A break lasts about 36 seconds** on the Ifrit & Shiva fight — many
  boss turns, where the design called for roughly one and a half turn
  cycles. Unchanged this release; it wants a number, not a bug fix.
- **Multi-hit still is not a dial.** The audit landed and the answer was
  worse than expected: across every spell and item record in the game
  there are exactly three multi-hits — Quadra Slam, Quadra Slice and
  Empowerer. **Pummel hits once. Bum Rush hits once.** Cyan is the only
  character in the game with a multi-hit ability. The design for fixing
  that is written; none of it is built (#54).
- **Locke's thief page is battle-only.** The field Skills menu has a
  hard seven-row limit and does not list it yet (#68).
- **The field Magic list still shows no elements**, only the ability
  pages do (#69).
- **Runic's remaining duration is not displayed anywhere.** Three turns
  of shield is legible in principle and invisible in practice.
- **A highlighted spell's MP number does not refresh on a bare L or R.**
  The name and the grey-out do; the number catches up as soon as you
  move the cursor.
- **The Sketch bug is still here**, by explicit decision. It is charm,
  not a defect to fix.
- **Before 1.0, saves are not forward-compatible.** A save from v0.9
  should be fine going forward, but old saves may miss things granted at
  the moment a character joins.

## What we'd like to know

- Does Locke feel like a character now rather than a Steal button? Is
  Filch worth an action, given it does no damage at all?
- Folded spells got dramatically more expensive. Does boosting a spell
  now feel like a real decision, or did it just stop being worth doing?
- Runic: is three turns of a stance you can act through exciting, or
  fiddly? Does it change who you point Celes at?
- Does the X read instantly as "broken" in a busy fight?
- Anything that got *worse* than v0.8 — that remains the one thing a
  release must not do.
