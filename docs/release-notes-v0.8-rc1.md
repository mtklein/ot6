# OT6 v0.8-rc1 — the economy bites (release candidate)

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch containing only the
differences from the original game.

**This is a release candidate, and it changes numbers in territory you
have already played.** That is deliberate: the one thing this build must
not have done is make anything *worse* than v0.7. The place to look is
Sabin from Mt. Kolts onward and Cyan from the Phantom Train onward.

The playable frontier is unchanged from v0.6 and v0.7.

## How to play

Apply `ot6-v0.8-rc1.bps` to a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7` using a BPS patcher such as
Flips or beat. The patcher will reject any other ROM.

Play from the beginning through the Raid on Vector, the same supported
stop point as v0.7.

## What's changed since v0.7

**Breaking an enemy is finally an event.** The broken monster flashes
white and a heavy sound lands with it, on the exact frame the damage
does. Previously the only sign was a digit turning into a 'B'.

**Abilities cost what they're worth.** Every kit price was recalibrated
against what vanilla's own spells cost at the level you learn them — 8 to
20 percent of your pool. The old numbers were an order of magnitude
under: Cyan's techniques ran 1–3 MP against a 96 MP pool, and Cleave, his
capstone, cost *one percent* of the pool it arrives with. MP is now a
budget rather than a rounding error.

**Every kit tops out at 99.** Bum Rush and Cleave are 99 MP — the same
ceiling vanilla's own dearest spell (Quick) sits at, so the top of a kit
now reads the way Final Fantasy numbers are supposed to read. The rungs
beneath were re-derived from that ceiling rather than scaled.

**Steal costs 4**, at parity with Pummel, Dispatch and AutoCrossbow — the
cheapest rung of every kit. (Its price still isn't *displayed* anywhere;
that's an honest gap, noted below.)

**Gau can fight.** His menu is Fight / Rage / Magic / Item, and on the
Veldt that first row becomes Leap — the thing you were going to do there
anyway. **Leap is free now** (it was quietly charging 2 MP with no number
shown anywhere). And his Rage list offers a chosen eight rather than a
wall of two hundred, configured under Skills → Rage.

**Sabin's Blitz page shows abilities instead of button combos.** It had
been teaching the input system OT6 retired in v0.4 — names, MP costs and
break-class icons now.

**Both loadout pages tell you what they're doing** — `L/R SWAPS` where it
was previously undiscoverable, `AUTO` or `MANUAL` with `Y=AUTO` to
revert, and `- EMPTY -` where a Rage slot is genuinely unset.

**Costs render correctly.** The loadout page's cost field could only draw
one digit, so the rescale made six of eight techniques display
punctuation instead of a number. Caught by a test written the same
afternoon.

## Known gaps, on purpose

- **Steal's 4 MP is charged but never displayed.** The battle command
  window has no numeric field at all, so a flat verb has nowhere to show
  a price. Locke's kit gains a submenu in a future release; that's where
  the number will live.
- **Element icons don't appear on ability pages** — only break-class
  ones. The element tiles are only uploaded for battle, so AuraBolt shows
  no pearl cue yet.
- **Multi-hit is not yet a designed dial.** Pummel hitting twice, Quadra
  Slam hitting four times, and what that means for break rate is the next
  big balance pass, not this one.
- **Locke still has only Steal.** Five of his eight designed skills are
  already past in the story and none are built. He's next.

## What we'd like to know

- **Did anything get worse than v0.7?** Specifically: Sabin from Mt.
  Kolts, Cyan from the Phantom Train. The rescale makes their abilities
  4× and 2× dearer, and that lands in fights you have already played.
- Does MP now feel like a budget you spend deliberately, or like
  rationing that stops you playing your character?
- Is Fight ever the right move now? That was the whole point — vanilla
  never gave Cyan or Sabin a reason not to use an ability.
- Does the break flash land right? Too subtle, too loud, wrong sound?
- Gau's eight: enough? Interesting to pick, or a chore?
