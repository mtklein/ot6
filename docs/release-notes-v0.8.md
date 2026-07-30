# OT6 v0.8 — the economy bites

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch containing only the
differences from the original game.

**This release changes numbers in territory you have already played** —
deliberately. Ability costs across every kit were an order of magnitude
too cheap; fixing that touches Sabin from Mt. Kolts onward and Cyan from
the Phantom Train onward.

Promoted from rc2 after the owner's playtest. Two rounds of candidate:
rc1's break effect turned out to fire only rarely, which rc2 fixed.

The playable frontier is unchanged from v0.6 and v0.7.

## How to play

Apply `ot6-v0.8.bps` to a Final Fantasy III (USA) 1.0 ROM with SHA-1
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

**Breaking an enemy is audible even when it dies.** A breaking hit usually
*kills* — it takes vanilla's elemental ×2 and then the broken ×2, so 4×
base, and almost nothing early survives its own break. rc1 refused the
whole effect on that path, which is why it seemed absent. Now:

- **broken and still standing** — white flash *and* sound
- **broken by the killing blow** — sound only, because the death animation
  legitimately owns that palette slot

**Magicite are gear.** Equipping an esper grants a package of stat changes
rather than one small nudge, in the exact two-byte format FF6 uses for
every stat-bearing weapon, helmet and relic in the game. Measured against
that ruler: the best stat armour purchasable in the World of Balance is
+11 across its stats, and a boss stone now sits about there. Three tiers
that differ by *shape*, not just size — found stones +6 across two stats
with no downside, story stones +8 across three with a −2, boss stones +10
across three with a −3. Ifrit is `+6 vigor / +4 stamina / −3 magic` —
body, not book; Shiva is his mirror; Maduin carries `+7 magic`, vanilla's
own per-stat ceiling, and pays −3 vigor for it. Swapping magicite is a
choice now, not a strict upgrade.

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
- **Gau needs a fresh recruitment to gain Fight.** Command slots are
  copied into your save at the moment a character joins, so a Gau
  recruited on v0.7 or earlier keeps the old Rage / Leap / Magic / Item
  menu permanently. Everything else in this build carries into an existing
  save normally. Not supported before 1.0 — start a new game to see it.

## What we'd like to know

- **Did anything get worse than v0.7?** Specifically: Sabin from Mt.
  Kolts, Cyan from the Phantom Train. The rescale makes their abilities
  4× and 2× dearer, and that lands in fights you have already played.
- **Does sound-only read as enough** when a break also kills? That is the
  common case on trash, so it is the one you will hear most.
- Do esper packages feel like finding better gear? Is a −3 an interesting
  cost or an annoyance?
- Does MP now feel like a budget you spend deliberately, or like
  rationing that stops you playing your character?
- Is Fight ever the right move now? That was the whole point — vanilla
  never gave Cyan or Sabin a reason not to use an ability.
- Does the break flash land right? Too subtle, too loud, wrong sound?
- Gau's eight: enough? Interesting to pick, or a chore?
