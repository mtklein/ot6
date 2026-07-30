# OT6 v0.8-rc2 — the economy bites (release candidate 2)

Everything in [rc1](release-notes-v0.8-rc1.md), plus a fix for the bug the
owner found in it and one new piece of content.

## Fixed since rc1

**Breaking an enemy is audible again.** rc1's break effect fired only
rarely, and the reason was that a breaking hit usually *kills*: it takes
vanilla's elemental ×2 and then the broken ×2, so 4× base — and almost
nothing in the early game survives its own break. The effect was being
refused wholesale on that path. Now a break that kills still lands its
sound; the flash stays suppressed there because the death animation
legitimately owns that palette slot.

So the feedback you get depends on what happened, which is honest:
- **broken and still standing** — white flash *and* sound
- **broken by the killing blow** — sound only

## New since rc1

**Magicite are gear now.** Equipping an esper grants a package of stat
changes rather than a single small nudge, expressed in the exact two-byte
format FF6 uses for every stat-bearing weapon, helmet and relic in the
game. Measured against that: the best stat armour purchasable in the
World of Balance is +11 across its stats, and a boss stone now sits right
about there.

Three tiers, and they differ by *shape*, not just size — which is how
vanilla's own gear ladder works:

- **Found stones** (the Zozo four) — +6 across two stats, no downside.
- **Story stones** (the six from the Magitek tube room) — +8 across three,
  with a −2 somewhere.
- **Boss stones** (Ifrit, Shiva, Maduin) — +10 across three, with a −3.

**Downsides are the point.** Ifrit is `+6 vigor / +4 stamina / −3 magic` —
body, not book. Shiva is his mirror. Maduin carries `+7 magic`, which is
vanilla's own per-stat ceiling, and pays `−3 vigor` for it. Swapping
magicite is now a choice rather than a strict upgrade, and the esper
detail page shows every term.

## Everything else

Unchanged from rc1 — the MP rescale, the 99 ceiling, Gau's Fight and free
Leap, Sabin's Blitz page, the loadout pages, and the two-digit costs. The
known gaps listed there still stand.

## What we'd like to know

Same as rc1, plus:

- **Does sound-only read as enough** when a break also kills? That is the
  common case on trash, so it is the one you will hear most.
- Do esper packages feel like finding better gear? Is a −3 an interesting
  cost or an annoyance?
