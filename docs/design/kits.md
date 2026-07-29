# Character kits & learn schedules — design dive v2 (2026-07-16)

Scope: World of Balance (kits complete or nearly so by its end; WoR
deepens via magicite, not new lists). Locked items are marked ✦.

## The organizing principles

**Native learning verbs.** FF6 already tells us *how* each character
learns; OT6 keeps each verb and reshapes the lists to exactly 8:

| Verb | Characters | Vanilla precedent |
|---|---|---|
| **By level** | Sabin (Blitz), Cyan (SwdTech), Terra & Celes (natural magic — the vanilla table, largely verbatim) | preserved |
| **By item** | Edgar (Tools are objects you find/buy) | preserved |
| **By deed** | Mog (dance per terrain), Strago (lore by observation), Gau (rage by capture) | preserved |
| **By story** | every signature (free at join ✦) and most divines | — |

**No JP, probably ✦-leaning.** The native verbs may carry the entire
schedule — everything below is scriptable with zero menu-bank work.
Octopath's early-game arc (develop one job, feel it complete, then
branch into subjobs and open up) falls out naturally: kits fill
through the WoB, then magicite arrives late-WoB/WoR as the breadth
layer. JP returns only if playtesting wants a pacing knob.

**Curated kits (the Ochette/Hikari model).** Two characters learn
MORE than 8 and equip a curated subset (~5 slots): Gau and Strago.
> **Row-sharing rule — SETTLED, and reversed the same day it was written
> (owner, 2026-07-29). Leap shares the FIGHT row.**
>
> > *"On the Veldt, you can always just Leap — Fight and Leap are the free
> > options there. Outside the Veldt, you might want to Fight or cast Magic
> > of course."*
>
> On the Veldt: **LEAP / RAGE / MAGIC / ITEM**. Everywhere else:
> **FIGHT / RAGE / MAGIC / ITEM**.
>
> Leap is what Gau is on the Veldt *for*, so Fight and Leap are the
> redundant pair *there* and sharing them costs nothing. Magic is the row
> you might want in **both** places, so Magic is never the row sacrificed
> — it is now never lost anywhere, which is strictly better than the first
> version of this rule.
>
> The first version put Leap on the MAGIC row, on the argument that the
> Veldt is where Gau spends the most turns and so is where losing the free
> action would hurt most: a Veldt Gau out of MP would be left with Rage
> (8 MP), Leap (2 MP) and Item. That argument was wrong twice over —
> Leap fills the free-action role on the Veldt, and **Leap is now free**
> (same ruling; mp-economy.md), so the 0-MP hole it worried about does not
> exist. Recorded rather than deleted because the reversal is the
> interesting part: the dispatch reasoned about the Veldt as a place where
> Gau needs Fight, and the owner reads it as the place where Gau needs
> Leap, which is the correct reading of his own map.
>
> **What it costs, stated plainly.** Leap is not a *contributing* free
> action — it removes Gau from the battle and flags the return-to-Veldt
> event (`TargetEffect_54`, `battle_main.asm:9762-9776`), and vanilla
> refuses it outright with fewer than two party members present. So on
> the Veldt an out-of-MP Gau's free options are *leave* and *Item*; the
> free action that swings a fist is only available off the Veldt. The
> owner's framing accepts this ("you can always just Leap"), and it is the
> right trade given that a Veldt encounter is a hunt rather than a fight —
> but if playtest ever wants a free contributing action on the Veldt, this
> arrangement does not provide one and the row count is still four.
>
> Mechanically this is *simpler*, not merely different: `Ot6VeldtRow`
> (`battle_main.asm`) now runs in `InitCmdList`'s own row loop instead of
> hooking `InitCmd_03/04`, because FIGHT (`$00`) has no init function.
> That means it runs before the relic pass (Dragoon Boots cannot silently
> replace a Veldt Leap with Jump), the `$11` it writes is picked up by
> Leap's own vanilla availability test for free, and `InitCmd_03/04` are
> back to exact vanilla — the has-MP flag `$f8` is no longer involved at
> all.

> **Gau fights ✦ (2026-07-29, #47).** Vanilla's "the feral kid cannot
> fight normally" characterization is overridden for economy coherence:
> once Rage costs 8 MP (#40) a Gau with no Fight has no free action at
> all, and mp-economy.md's target — *Fight must sometimes be the right
> move* — requires that every character be able to decline to spend. His
> four slots become **FIGHT / RAGE / MAGIC / ITEM**; there was never a
> spare one (vanilla's "blank" third row is MAGIC removed at runtime), so
> **Leap shares the FIGHT row** (see the row-sharing rule above) — Leap
> only works on the Veldt, so that row is Leap there and Fight everywhere
> else, and nothing is lost: on the Veldt Leap *is* the free action, and
> it costs no MP. Bare fists are his probe
> (`Ot6WeapClassTbl[$ff]` = bludgeoning), which also makes
> `check_break_reach.py`'s "can field" model true of him for the first
> time.

> **Gau superseded (2026-07-28, owner-settled):** his kit is now
> `kit-gau.md` — the Ochette model, learn many / **equip 8**, possession
> preserved, Dance-model MP, chance-verb boost. This file's Gau lines
> below stand as history; kit-gau.md §11 lists the exact amendments,
> which land with the build.
Everyone else's 8 are fixed. Curating IS their identity — same verb
family, different collection method.

Boost-tier folding means kits list **base spells only** — Fire is a
kit entry; Fire 2/3 are what boosting does to it.

Physical chip classes are **slashing / piercing / bludgeoning /
special ¤** (see weapon-classes.md v2.1); the weapon sets Fight's
class while abilities carry their own, and some attacks are
deliberately **null-break** — big dumb damage that chips nothing,
the physical cousin of non-elemental magic.

---

## The constrained three

### Edgar — Machinist (piercing: spear)

The 8 Tools, verbatim ✦ — learned by acquisition.

| # | Tool | MP | Chip | Source (WoB) |
|---|---|---|---|---|
| 1 | AutoCrossbow ✦ | 4 | piercing ×4 | join (signature) |
| 2 | NoiseBlaster | 6 | — (confuse) | Figaro shop |
| 3 | Bio Blaster | 8 | poison | Figaro shop |
| 4 | Flash | 6 | — (blind) | Figaro shop, restocked South Figaro |
| 5 | Drill | 16 | piercing | Figaro castle, after the sand dive |
| 6 | Chain Saw | 18 | slashing | Zozo chest (vanilla) |
| 7 | Debilitator | 10 | adds + reveals a random weakness ✦ | Vector shop |
| 8 | **Overclock** ✦ (divine) | Σ | — | Magitek factory (story) |

The MP column is mp-economy.md's "scaled by tier 3–20" (AutoCrossbow 3–4,
Drill/Chain Saw 12–20, Debilitator 8–12): gil buys the tool once, MP is the
per-use operating cost. It lives in `Ot6AbilityCostTbl` keyed by **tool item
id** ($a3–$aa, the same keying ot6_class.asm uses for tool classes), charged
under `OT6_MP_COSTS`. The mid-kit gag Air Anchor ($a9, the findable harpoon)
is costed 14 alongside them. **Overclock** fires two tools, so it has no single
price — its cost is the **sum (Σ)** of the two it fires, wired the day Overclock
is built (it is not yet).

- Divine locked ✦: **Overclock** — use two tools in one action. Air
  Anchor stays a findable *item* mid-kit gag, not the capstone.
- AutoCrossbow ×4 piercing = the first shield shredder; Drill the
  armored-boss answer; Chain Saw covers slashing so Edgar alone spans
  two physical classes through tools.
- Passive candidates: *Tinkerer* (tools ignore blind), *Royal
  Discount* (shops half price), *Overcharge* (+1 AutoCrossbow hit
  per 2 BP).

### Sabin — Monk (bludgeoning: fists; claws buy slashing)

The 8 Blitzes, verbatim ✦ — vanilla level table preserved ✦, selected
from a menu (the fighting-game inputs were retired in v0.4). Fists are
the heart of the **bludgeoning** class (fists, staves, rods) —
Pummel-as-blade never sat right. Equipping
claws switches his *Fight* to slashing ✦, but blitz classes are
immutable: Pummel with claws on is still bludgeoning. The weapon
slot is his second class, the ability list is his first.

Levels below are `BlitzLevelTbl` (`field/event.asm:1240`), read out, not
recalled — an earlier draft of this table was wrong in six of eight rows
while still marked "vanilla preserved ✦".

| # | Blitz | MP | Chip | Level |
|---|---|---|---|---|
| 1 | Pummel ✦ | 4 | bludgeoning ×2 | 1 (has it at join) |
| 2 | AuraBolt | 10 | holy | 6 |
| 3 | Suplex | 13 | bludgeoning | 10 |
| 4 | Fire Dance | 17 | fire | 15 |
| 5 | Mantra | 16 | — (heal) | 23 |
| 6 | Air Blade | 22 | wind | 30 |
| 7 | Spiraler | 30 | — | 42 |
| 8 | **Bum Rush** (divine) | 46 | bludgeoning ×8 | 70 / Duncan |

The MP column lives in `Ot6AbilityCostTbl` keyed by attack id $5d–$64,
charged under `OT6_MP_COSTS`. **Rescaled by issue #45 (2026-07-29)** from
2/5/7/9/8/12/18/30: measured against Sabin's real pool at the level each row is
reachable, the old ladder ran 3.6–12.5% where a vanilla spell costs 8–21% of
the pool it is first cast from, so the ladder sat *under* the ruler
mp-economy.md says it shares. The lift is ~2× at the floor tapering to ~1.5× at
the top — compression, not a flat multiply, because pools grow far faster than
a fixed cost. Mantra stays deliberately under Fire Dance: it is a utility
off-ramp, not a damage rung. Full per-row derivation, and the ruler it is
measured against, in mp-economy.md's "The ruler, finally measured".

- Passive candidates: *Iron Fist* (unarmed counts as a bludgeon
  weapon), *Discipline* (+1 BP when striking a Broken enemy),
  *Second Wind* (Mantra also grants 1 BP).

### Cyan — Samurai (slashing: katana)

The 8 SwdTechs priced in BP ✦ (charge gauge deleted ✦). Katana now
lives inside **slashing** with swords — Cyan is a slashing
*specialist* (multi-hit slash chips nobody else matches), not a
mandatory key for katana-only locks. Vanilla level schedule kept.

Names below are the ones the game prints (`BushidoName`, the table the SwdTech
window renders from). The internal disassembly labels — `Bushido*`, `Fang`,
`Oblivion` — stay as they are: renaming code symbols is churn against upstream
that a comment already buys (issue #50).

| # | Tech | BP | MP | Chip | Level |
|---|---|---|---|---|---|
| 1 | Dispatch ✦ | 0 | 4 | slashing | join |
| 2 | Retort | 1 | 10 | — (counter stance) | 6 |
| 3 | Slash | 1 | 13 | slashing | 12 |
| 4 | Quadra Slam | 2 | 16 | slashing ×4 | 15 |
| 5 | Empowerer | 2 | 18 | — (drain) | 24 |
| 6 | Stunner | 3 | 22 | slashing, all enemies | 34 |
| 7 | Quadra Slice | 3 | 30 | wind ×4 | 44 |
| 8 | **Cleave** (divine) | 3, target must be Broken | 46 | — | Phantom Train farewell (story) |

**The MP column, rescaled (issue #45, 2026-07-29; was 1–8, proposed v0.4).**
The old column rode **~⅓ of a comparable Blitz/Tool** — Quadra Slam's slashing
×4 cost 4 MP where Sabin's Air Blade cost 12 — on the ruling that "the banked-BP
requirement is the real price and the MP only prices the cast". That discount
was a claim about the *four-rung* 0×/1×/2×/3× ladder; **#38 rewrote the ladder
to 1×/2×/3× and explicitly deferred the MP column**, and the discount kept
applying to a premise that had been edited out from under it. The v0.7 playtest
found the result: at LV14 Cyan holds 96 MP against techs costing 1/2/3, BP is
not scarce either, so nothing constrains him and Fight is never the right move —
the exact failure mp-economy.md's target box forbids.

So SwdTech now prices at **parity with the Blitz row of the same index**, which
is a level claim rather than an index coincidence: `BlitzLevelTbl` is
1/6/10/15/23/30/42/70 and `BushidoLevelTbl` 1/6/12/15/24/34/44/70
(`ff6/src/field/event.asm:1236-1240`), so row *n* of either kit lands in the
same band against nearly the same pool. **Cyan still pays both currencies** —
the ruling stands, only its magnitude is retired — and if parity plus #38's
1-BP floor leaves him starved, #38's own ruling names the lever: BP seed/regen,
not the floor, and not this column.

One deviation from parity: **Empowerer 18, not Mantra's 16**, because this
column must stay monotonic with the tech index — the boost window offers techs
weakest→strongest and *the cursor row is the boost level* (below), so a 2× row
dearer than the 3× row would read as a bug.

Dispatch is still the cheapest row of any kit (the "free-to-learn is not
free-to-use" floor), now at 4 MP rather than 1 — 6.9% of the pool Cyan actually
joins with, against the 8–21% a vanilla spell costs at the level it is learned.
Cleave tops the ladder at 46 — the window's divine top rung once Cyan has
learned all eight (the moving window, below), and comfortably payable: it is
L70-gated and his L70 pool is 762. Per-row measurement, and the ruler, in
mp-economy.md's "The ruler, finally measured"; gated by
`tools/tests/battle_costtable.lua`.

These numbers live in `Ot6AbilityCostTbl` (ff6/src/battle/ot6_boost.asm),
charged under the `OT6_MP_COSTS` build flag — which **v0.5 flipped ON by
default**, so the shipped ROM charges them (see mp-economy.md).

**Shipped (v0.5, issue #5).** `Ot6BushidoTier` (ff6/src/battle/ot6.asm)
replaces the charge gauge's clock in `UpdateMenuState_37`; the window, its
numerals, the grey-out of unlearned techs, the A-button latch,
`FixPlayerAttack`'s `+$55` and `Cmd_07` are all vanilla and untouched. Boost
0/1/2/3 selects a **moving window of four** — Cyan's top four *learned* techs,
weakest → strongest. With `ceiling` = vanilla's own `$2020` (techs known − 1,
the value that used to cap the bar), `base = max(0, ceiling−3)` and boost picks
`min(base+boost, ceiling)`. Pure arithmetic — no table.

| techs known | window (BP 0 / 1 / 2 / 3) | retired |
|---|---|---|
| ≤ 4 | all of them, in learn order | — (every learned tech reachable) |
| 5 (through Empowerer) | Retort / Slash / Quadra Slam / Empowerer | Dispatch |
| 6 (through Stunner) | Slash / Quadra Slam / Empowerer / Stunner | Dispatch, Retort |
| 8 (full kit) | Empowerer / Stunner / Quadra Slice / **Cleave** | Dispatch…Quadra Slam |

This **fixes #5**. The old design read the BP column as four *bands* and named
each band's top tech, clamped to the ceiling — so a 3-tech Cyan
(Dispatch/Retort/Slash) got Dispatch at 0× and Slash at every higher boost, and
could never cast the Retort he had learned: a *learned* tech made uncastable. The window never skips a middle
tech; only the weakest retire, as Cyan outgrows them.

The three open questions, settled at build time and documented in
`Ot6BushidoTier`'s header:

- **Utility techs retire with the window.** Retort's counter stance and
  Empowerer's
  drain go quiet once Cyan out-levels them — a real cost, not just weak damage.
  Ruling: ship the auto-window as-is, no special-casing of utility. The
  player-chosen **loadout** (the #5 sequel) is where a player pins a utility
  tech in a slot; playtest is the filter.
- **No affordable floor.** The 0× slot is always the cheapest tech *in the
  window*, so it slides up (gets pricier) as Cyan levels — accepted, because his
  MP pool grows on the same schedule.
- **Cleave is the window's conditional top rung**, not a case bolted outside
  it. At full kit the window is Empowerer/Stunner/Quadra Slice/Cleave and BP3
  lands on Cleave (tech 7) by the same `base+boost` sum as any other rung — it falls out
  for free, so it is *cleaner* as the top rung than as a separate invocation. It
  fires exactly as the divine pass built it: selected only when learned and
  unspent, gated at resolution by `Ot6Oblivion` (target must be Broken), and
  dropped back to Quadra Slice (6) here for the rest of any battle whose once-
  per-battle latch is set. `battle_divines` gates that shape (BP3 = Cleave
  clear, Quadra Slice spent).

**BP is read, never written.** `Ot6ActionEnd` consumes the spend and skips that
turn's regen exactly as for any other action, and the ≤3 / never-past-bank caps
stay `Ot6Boost`'s. SwdTech is excluded from `Ot6BoostDmg`'s multiplier for the
same reason folded spells are: the points bought the tech, so they must not also
buy damage. Spend the window cannot use (three points at L1 still buys Dispatch) is
spent, not refunded — the deal a mage already takes on a third point on Fire.

**The SwdTech menu UI is a name + cost submenu** (#8 Layer A). SwdTech no longer
opens the vanilla numeral gauge; `OpenCmdMenuTbl[7]` is repointed to a tools-shell
submenu (the same route Blitz took) that lists the four moving-window techs by
name + MP cost, greyed when the caster can't afford the MP *or* the BP. This
sidestepped the bespoke numeral-gauge redesign once weighed against it: rather
than a new window template + NMI DMA rewrite, it reuses the Tools window shell,
`Ot6CostFor`, and `Ot6AbilityGrey`, with all cost/grey logic gated `.if
OT6_MP_COSTS` so the nomp baseline is undisturbed. The **cursor row is the boost
level** (row 0 = boost 0× … row 3 = boost 3×), so picking a stronger tech spends
more BP — the spend-BP-to-reach-the-stronger-cut tension the numeral gauge had,
now legible. Confirm banks `$3e9d = r` and reuses `Ot6BushidoTier` to latch the
base+r tech; a row the caster lacks the BP for is greyed and refuses on confirm.
`SwdTech`'s names render from `BushidoName` (not `AttackName`, whose $55–$5c slots
are empty pad).

**The loadout is player-configurable** (#8 Layer B). By default the four boost
slots are the auto-window (top-four learned, weakest→strongest — issue #5), but
the player can choose which learned techs occupy 0×/1×/2×/3× and in what order,
from a **field-menu configurator**: X-menu → Skills → SwdTech opens it (bank C3),
showing the four boost slots (name + MP cost) over the learned pool; Up/Down pick
a slot, L/R cycle its tech, Y reverts to auto, B exits. This turns the scheme from
"we chose your four and retired the rest" into "you choose your four" — the same
mechanic, made empowering. The config UI is a **thin C3 shim over bank F0**: every
decision (seed-from-auto, per-slot validated tech, assign, revert, write-back) is a
`jsl` into OT6 F0 procs (`Ot6Loadout*`), so OT6 stays nearly-all-F0 despite its
first menu-bank presence; costs price through `Ot6CostFor` (built for menu-bank
callers), the learned set/ceiling derive from `$1cf7` (not battle-only `$2020`).

Storage is **per-save**: a single 16-bit word at `$1E1D..$1E1E`, inside FF6's
`$1600–$1FFD` save block that round-trips per slot and sits in the save checksum,
so a loadout persists per file and validates automatically. Cyan has exactly 8
SwdTechs (index 0–7 = 3 bits), so the four boost slots pack into 12 bits — slot 0
= bits 0–2, slot 1 = bits 3–5, slot 2 = bits 6–8, slot 3 = bits 9–11 (top 4 bits
unused). **`$0000` = auto**: an all-zero word decodes to "all four slots = tech 0",
a degenerate config no player sets on purpose, and it reads 0 on every existing
save — so the word doubles as the auto sentinel and old saves and new games
default to the auto-window with zero migration (no separate mode flag). Revert-to-auto
writes `$0000`. The battle read is a single branch at the top
of `Ot6BushidoTech` — the shared leaf both the list and the confirm/damage path
call — so manual mode governs display, fire, and damage together; a stored tech
that is no longer learned (`$1cf7` bit clear) falls back to the auto window for
that slot. Because the read is that one leaf, the auto path stays behaviorally
identical to Layer A.

Note the Chip column above is finer-grained than what ships: the class
table (`ot6_class.asm:185-192`) marks all eight slashing, per
weapon-classes.md's "Cyan is a slashing specialist". Retort's and Empowerer's
"—" and Quadra Slice's wind are unbuilt refinements, not a contradiction.

Gate: `tools/tests/battle_bushido.lua`.

- Passive candidates: *Vengeance* (+1 BP whenever any enemy Breaks),
  *Retort* (the vanilla counter as a passive — deliberately the same name as
  SwdTech #2, because it is the same effect), *Zanshin* (Retort chips 1
  when it counters).

---

## The middle three

### Terra — Esper mage (slashing: sword, fire lean)

Vanilla's natural-magic table, trimmed to base tiers with the levels
compressed so the list completes late-WoB. Vanilla makes her the
game's only natural raise-learner (Life at 18) — kept, so revival
lives on Terra, Fenix Downs, and Sraphim, and nowhere else.

| # | Spell | Level |
|---|---|---|
| 1 | Fire ✦ (hides Ultima — see below) | join (vanilla 3) |
| 2 | Cure | join (vanilla 1) |
| 3 | Drain | 12 (vanilla) |
| 4 | Life | 18 (vanilla) |
| 5 | Break | 24 |
| 6 | Pearl | 30 |
| 7 | Merton | 33 |
| 8 | **Trance** (divine) | Zozo awakening (story) |

- **Ultima is the fourth fold, not a slot ✦.** Vanilla's table
  already teaches Terra Ultima at level 99 — a birthright nobody
  ever meets. OT6 makes it real without spending a menu row: after a
  very-late story unlock, Terra casting Fire at 3 BP folds past
  Fire 3 into **Ultima**. It never appears in her list until the
  moment the fold preview renders it. Everyone else gets Ultima the
  expected way — equip Ragnarok.
- **Trance keeps the divine slot**: her esper-state apex — usable
  only while an enemy is Broken, or costing the full 5-BP bank
  (DESIGN.md's two candidates; playtest decides in M6).
- Passive candidates: *Esperkin* (spells chip 2 on weakness),
  *Mag-Armor* (magic taken −25%), *Afterglow* (first cast each
  battle costs 0 MP).

### Locke — Thief (piercing: dagger)

Story-verb learner. More than steal-steal-steal: probe, redistribute,
corrode — and a little merchant blood (he'd say TREASURE HUNTER).

| # | Skill | Effect | Source |
|---|---|---|---|
| 1 | Steal ✦ | vanilla steal | join |
| 2 | Mug | steal + piercing damage | South Figaro escape |
| 3 | Trickshot | piercing chip at range (thrown coin) | Lete River |
| 4 | Filch | steal 1 BP from the target | Opera house |
| 5 | Bestow | give an ally 1 BP | Vector (merchant beat) |
| 6 | Dismantle | armor corrode: −defense, piercing chip | Sealed Gate |
| 7 | Appraise | reveal one enemy's full weakness row | Thamasa |
| 8 | **Master's Mark** (divine) | steal from all enemies + reveal everything | Floating Continent |

- Filch/Bestow make him the economy's hands: take BP from enemies,
  hand it to allies. Tactically he's tempo, not just loot.
- Passive candidates: *Sticky Fingers* (failed steal keeps the
  turn's BP gain), *First Strike* (battle opens +1 BP for Locke),
  *Fence* (steals sell for more).

**Boost-tiered Steal (shipped M3).** Steal is the party's first *chance verb*:
it rolls dice, so BP buys certainty, not potency (DESIGN.md's canon rule — "on
chance verbs boost guarantees"). Each point tilts BOTH axes of the vanilla
gamble — the success chance and the common-vs-rare pick — monotonically, and the
full spend converts it:

| BP | Success | Item pick |
|----|---------|-----------|
| 0 | **vanilla, to the byte** — level+50−targetLevel, Sneak Ring doubles it | vanilla: 1/8 rare, 7/8 common; an empty picked slot still yields nothing |
| 1 | +40 to the effective level (a hard steal → a coin flip; a coin flip → a near-lock) | 3/8 rare when both present; never "nothing" on a hit (takes whichever slot is filled) |
| 2 | +90 (level parity now auto-succeeds) | 3/4 rare when both present; same fallback |
| 3 | **guaranteed** (the level clamps to $ff, so the roll is skipped entirely) | **rare if present, else the common** — taken outright, no roll |

Rulings that fall out of the vanilla math (see `tools/tests/battle_steal.lua`):

- **Sneak Ring** keeps helping the un-boosted and partial tiers — it doubles the
  residual success chance at 0–2 BP exactly as in vanilla. At 3 BP it is moot:
  the level clamp overflows *before* the chance value is ever formed, so the ring
  is never consulted. Nobody stacks a relic onto a certainty.
- **Boost never conjures loot.** An enemy with nothing to steal, or one already
  looted (both slots cleared), yields vanilla's "nothing" at every tier — the
  $ffff top-check drops out before the tier logic runs. 3 BP guarantees a steal
  *if there is something to steal*, and "rare if present" falls back to the
  common when there is no rare (guarantee ≠ conjuring).
- **No damage, no multiplier.** Steal deals none, and the Ot6BoostDmg command
  gate ($05) makes sure boost never sneaks one in: a chance verb answers to
  guarantee, not the ×2/×4/×8 a damage verb takes. This is what keeps the two
  axes legible — and it pre-declares **Mug's** ruling. Mug is *steal + piercing
  damage*: when it ships, boost drives exactly ONE axis (the damage multiply OR
  the steal guarantee, TBD by playtest), never both, or the canon rule stops
  reading cleanly. The steal half rides its unboosted vanilla odds unless boost
  is spent on it.

### Celes — Rune Knight (slashing: sword, ice lean)

Vanilla natural-magic levels nearly verbatim — the table was already
a rune knight's: sensing, warding, hastening. Deliberately mirrors
Terra: both share Cure; fire/life/transcendence against
ice/order/tempo. The duality reads clearer than vanilla ever made it.

| # | Spell/Skill | Level |
|---|---|---|
| 1 | Runic ✦ (absorbs next spell → **+1 BP** ✦) | join |
| 2 | Ice | join (vanilla 1) |
| 3 | Cure | 4 (vanilla) |
| 4 | Imp | 13 (vanilla) |
| 5 | Scan | 18 (vanilla) |
| 6 | Safe | 22 (vanilla) |
| 7 | Haste | 32 (vanilla) |
| 8 | **RunicBlade** (divine, leaning) | Opera / Magitek factory (story) |

- **Row 1 is code now, not only design** (`Ot6RunicBP`, ot6.asm, hooked
  into vanilla's `RunicEffect`): the absorb still becomes MP and now
  also banks 1 BP. Rulings, all covered by `battle_runic.lua` — an
  absorb at a full bank is **capped, never wrapped**; the
  no-regen-after-boost rule does **not** gate it, because that rule
  governs a turn's own end-of-action tick while the absorb is paid
  during the *caster's* action, so boosting the turn she raises Runic
  still gets paid for what she catches; and only the Runic *command*
  pays, not the separate "enemy runic" stance a raging Gau can carry.
  Vanilla's own gate is untouched — what Runic can eat is still the
  spell's `MagicProp` absorb flag, which excludes every esper and every
  MagiTek beam. The Narshe school's $026F now names the BP.
- Divine leaning ✦-ward: **RunicBlade** — a Runic stance that also
  *reflects* what it eats (absorb the MP as BP, bounce the spell).
  Absolute Zero stays the listed alternate until playtest.
- Passive candidates: *Rune Eater* (Runic feeds 2 BP), *Cold Blood*
  (ice chips +1), *Aegis* (magic taken at 0 pending −20%).

---

## Sketches (join order, WoB)

- **Shadow — Assassin (piercing, thrown)**: Throw ✦ signature; smoke
  and exit tricks; divine **Assassinate** — instant kill a Broken
  non-boss. Interceptor is a passive.
- **Setzer — Gambler/Merchant (special ¤: dice, cards; darts =
  piercing)**: Slot ✦ signature; Coin Toss, Hired Help (pay GP for
  effects) carry the merchant house; divine **Jackpot** — a
  Fixed-Dice triple payoff, never Slot itself ✦. Ordinary dice and
  cards chip ¤; the wildest oddballs (Fixed Dice) are null-break —
  huge numbers, no chip, row ignored (vanilla charm, preserved ✦).
- **Mog — Dancer (piercing: spear)**: the 8 Dances verbatim ✦,
  learned by dancing on each terrain ✦; divine **Water Rondo**, kept
  WoB-missable, vanilla-style. Easy and perfect.
  - **Boost-tiered Dance (design canon — awaiting Mog's rung to build).**
    Dance is a *chance verb* like Steal, so boost buys certainty in the dance's
    own vocabulary (DESIGN.md canon rule). **Keep the possession** — Mog still
    dances on his own once it starts; that loss of control IS the dance. Boost
    spent at dance-start buys choreography: **1–2 BP removes the stumble** (the
    ~1/16 wrong-terrain misfire) and shifts the four-move weights toward the
    stronger moves; **3 BP = the dance's best move every turn for the whole
    trance** — fully choreographed, no roll. Same shape as Steal: 0 BP is
    vanilla to the byte, each point narrows the gamble, the full spend converts
    it. This is approved-verbatim design, not yet coded — it lands when Mog's kit
    does (WoB), reusing the same pending-BP read + Ot6ActionEnd charge Steal
    already proves out.

**The chance-verb family.** Steal (shipped) and Dance (above) are the first two;
**Sketch (Relm), Slot (Setzer), and Rage (Gau)** answer to the SAME rule when
their rungs arrive — each rolls dice, so each spends BP on certainty in its own
terms (a chosen sketch, a fixed reel, a picked rage) rather than on a potency it
doesn't have. Held in reserve deliberately: coupling steal odds to a *broken*
enemy (revisit after the v0.3 break-uptime playtest).

## Curated kits (the Ochette/Hikari pair)

Both learn an open-ended collection and **equip ~5** — the player
prunes the kit all game. Same model, different collection verbs:

- **Gau — Beast Tamer (piercing: fangs)**: Leap→**Capture** ✦
  (H'aanit/Ochette). Captured beasts' signature moves fill his
  stable; he equips 5 as controllable skills. The 250-entry berserk
  Rage table retires; the stable is curated in M6. Divine: TBD, a
  capstone beast.
- **Strago — Scholar (bludgeoning: rod)**: Lores by observation ✦
  (Cyrus/Hikari). Aqua Rake free ✦; **Analyze** cheap and early ✦
  (full weakness reveal — the party's scout tool). Learns every lore
  he witnesses, equips 5. Divine: a taught-only capstone lore
  (Grand Train candidate, WoR).

- **Relm — Painter (special ¤: brush)**: Sketch ✦ signature (bug
  preserved ✦ — it eats a save now and then, and that's canon);
  support/trickster kit TBD.

## Open questions for the driver

1. Trance's gate: Broken-enemies-only, the full 5-BP bank, or
   either? (It kept the divine slot now that Ultima rides Fire.)
2. Gau's divine: a specific capstone beast, or the stable's 5th slot
   upgraded to hold anything?
3. Curated-kit slot count: 5 for both Gau and Strago, or asymmetric
   (Gau 5, Strago 6)?
4. Does Bestow (Locke) step on Hired Help (Setzer), or is
   BP-vs-GP economy distinct enough?
