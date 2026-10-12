# Character kits & learn schedules

Scope: World of Balance (kits complete or nearly so by its end; WoR
deepens via magicite, not new lists). Locked items are marked ✦.

## The organizing principles

**Native learning verbs.** FF6 gives each character a way of learning.
OT6 keeps each verb and reshapes the lists to exactly 8:

| Verb | Characters | Vanilla precedent |
|---|---|---|
| **By level** | Sabin (Blitz), Cyan (SwdTech), Terra & Celes (natural magic — the vanilla table, largely verbatim) | preserved |
| **By item** | Edgar (Tools are objects you find/buy) | preserved |
| **By deed** | Mog (dance per terrain), Strago (lore by observation), Gau (rage by hunting) | preserved |
| **By story** | every signature (free at join ✦) and most divines | — |

**No JP, probably ✦-leaning.** The native verbs may carry the entire
schedule, and everything below is scriptable with zero menu-bank work.
That reproduces Octopath's early-game arc (develop one job, feel it
complete, then branch into subjobs and open up): kits fill through the
WoB, then magicite arrives late-WoB/WoR as the breadth layer. JP
returns only if playtesting shows a pacing knob is needed.

**Curated kits (the Ochette/Hikari model).** Two characters learn
more than 8 and equip a curated subset: Strago (~5 slots) and Gau
(8, `kit-gau.md`). Everyone else's 8 are fixed. Curating is part of
their identity: same verb family, different collection method.

**Row-sharing rule: Leap shares the FIGHT row.** On the Veldt Gau's four
rows are **LEAP / RAGE / MAGIC / ITEM**; everywhere else
**FIGHT / RAGE / MAGIC / ITEM**. Leap is the reason to bring Gau to the
Veldt, so Fight and Leap are the redundant pair there and sharing them
costs nothing. Magic is the row a player may want in both places, so
Magic is never the row sacrificed. `Ot6VeldtRow` (`battle_main.asm`) runs
in `InitCmdList`'s own row loop rather than hooking `InitCmd_03/04`,
because FIGHT (`$00`) has no init function. It therefore runs before the
relic pass, so Dragoon Boots cannot replace a Veldt Leap with Jump, and
the `$11` it writes is picked up by Leap's own vanilla availability test
without extra code.

Boost-tier folding means kits list **base spells only**: Fire is a
kit entry, and Fire 2/3 are what boosting does to it. Terra's and
Celes's tables below are the natural magic the ROM ships ("join" is
level 1): `tools/check_spell_grants.py` fails the build when
`NaturalMagic` differs from them (#305).

Physical chip classes are **slashing / piercing / bludgeoning /
special ¤** (see weapon-classes.md). The weapon sets Fight's
class while abilities carry their own. Some attacks are
**null-break**: they deal large damage but chip nothing, which is
the physical equivalent of non-elemental magic.

Chip is per hit, and excess hits after a break convert to the broken ×2
rather than being wasted. `design/multi-hit.md` is the full survey of what
the engine can express. A ×N in the Chip column below means the ability
strikes the same body N times and therefore chips up to N shields per use;
its power is divided by N to pay for that. Six abilities carry one: Pummel
×2, Bum Rush ×4, Drill ×2, Quadra Slam ×4, Quadra Slice ×4, Empowerer ×2.
Breadth is a different thing and is written out in words: AutoCrossbow hits
every body once, which is four chips against a four-stack and one against a
boss.

## Divines

**A divine's one gate is a full 3-BP boost** (owner, 2026-10-11), as in
Octopath Traveler.  Each character's kit slot 8 is what spending all three
points buys, and nothing else gates it: no once-a-battle limit and no other
condition (the Broken-enemy condition Cleave and Trance used to carry is
gone).  *Reason (the owner's): these are things a Final Fantasy player
expects to use freely, and no further complications should be added.*  A
divine can be used again in the same battle whenever the bank holds three.
The bank itself paces it: points come one a turn and none on a boosted
turn, so from an empty bank a divine is every fourth turn at most, and
each divine's MP does the rest.

With fewer than three points pending, a divine is not offered: its row
greys and the A button buzzes (Jackpot, Morph), or the command does what it
does at that boost (Cleave is only ever the SwdTech window's 3-BP row;
Runic and Tools under three points are their plain selves; Shadow's hit
under three points is a hit).  A divine picked at three and then taken
back to fewer (L during target select) falls back at execution and charges
nothing it did not deliver.  Each divine is tuned to be worth a full boost
and to be used more than once a fight; each entry below gives its reason.
Mimic copies a divine's action, not its price, but the gate is the boost:
a Gogo's copy takes the full boost from Gogo's own bank where the copy reads
it (a Jackpot), and is free where it does not (a Cleave).

| Character | Divine | What three points buy | Built |
|---|---|---|---|
| Terra | Trance | her Morph: esper form (magic x2, damage taken halved) for as long as the morph gauge lasts | yes (`ot6_trance.asm`) |
| Celes | RunicBlade | a 3-turn Runic that also sends every spell it absorbs back at its caster | yes (`ot6_runicblade.asm`) |
| Edgar | Overclock | the Tool fires twice, at the boost's x8 each, priced as the two firings | yes (`ot6_overclock.asm`) |
| Cyan | Cleave | the SwdTech window's 3-BP row, from the Phantom Train farewell on: instant death on a killable target, a power-255 cut on a death-immune one | yes (`ot6_divine.asm`, learned by story since #379) |
| Setzer | Jackpot | a throw of two triple rolls, 99 MP | yes (`ot6_setzer.asm`) |
| Shadow | Assassinate | his 3-BP action: a hit of it that breaks a non-boss, or lands on a Broken one, kills it (the effect, not a gate) | yes (`ot6_divine.asm`) |
| Sabin | Bum Rush | (built today as a 99-MP Blitz row at any boost; as a divine it will take the full boost) | no |
| Locke | Master's Mark | steal from all enemies and reveal everything, at 3 BP | no |
| Mog | Water Rondo | the dance at 3 BP: every step x8 for the battle, 99 MP, and it never stumbles, wherever the party fights | yes (`ot6_waterrondo.asm`) |
| Umaro | Storm | a dump of all three points: Storm, ice on every enemy at x8, with or without the Blizzard Orb | yes (`ot6_umaro.asm`) |
| Gau | (open, kit-gau.md) | at 3 BP | no |

Terra's Ultima is a fold, not a divine, but it too is what a full boost buys
(Fire at 3 BP, after her World of Ruin return; see Terra below).  `$3ecb`,
the once-a-battle flag (`OT6_DIVINE_USED`), is retired.
Suites: `battle_divines` and `battle_cleave` (Cleave), `battle_jackpot`,
`battle_assassinate`, `battle_trance`, `battle_runicblade`,
`battle_overclock`, `battle_waterrondo`, `battle_umaro`, each with its gate
(under 3 BP no divine), and an old-ROM red; the menu divines also with a
second use in one battle.

The engine picks a command for a character the player is not driving
(Muddle, Charm, the Colosseum, Berserk) and spends no boost doing it, so
every divine closes that path: a random SwdTech's range stops short of
Cleave (`Ot6RandBushidoTop`), a random Dance draws from the known dances
less Water Rondo and a Water Rondo start under three points stumbles
(`Ot6DanceKnownRand`, `Ot6DanceTerrain`), a Morph the engine chose does not
morph (`Ot6TranceGate`), and Umaro's Storm is his only on a dump of all
three points, which only being hurt makes (`Ot6UmaroArm`).

---

## The constrained three

### Edgar — Machinist (piercing: spear)

The 8 Tools, verbatim ✦, learned by acquisition.

| # | Tool | MP | Chip | Source (WoB) |
|---|---|---|---|---|
| 1 | AutoCrossbow ✦ | 4 | piercing, whole side (one hit per body) | join (signature) |
| 2 | NoiseBlaster | 6 | — (confuse) | Figaro shop |
| 3 | Bio Blaster | 8 | poison | Figaro shop |
| 4 | Flash | 6 | — (blind) | Figaro's tool merchant (shop 82), restocked at South Figaro (shop 5) |
| 5 | Drill | 16 | piercing ×2 | Figaro castle, after the sand dive |
| 6 | Chain Saw | 18 | slashing | Zozo chest (vanilla) |
| 7 | Debilitator | 10 | adds + reveals a random weakness ✦ | Vector's weapon shop (shop 27), open during the banquet |
| 8 | **Overclock** ✦ (divine) | Σ | the Tool's own, twice | Magitek factory (story: switch `$0068`) |

The MP column is mp-economy.md's "scaled by tier 3–20" (AutoCrossbow 3–4,
Drill/Chain Saw 12–20, Debilitator 8–12): gil buys the tool once, and MP is
the per-use operating cost. It lives in `Ot6AbilityCostTbl` keyed by **tool
item id** ($a3–$aa, the same keying ot6_class.asm uses for tool classes).
The mid-kit gag Air Anchor ($a9, the findable
harpoon) is costed 14 alongside them. **Overclock** fires two tools, so it has
no single price; its cost is the **sum (Σ)** of the two it fires.

- Divine ✦: **Overclock**, two tools' worth in one action.  Once EDGAR has
  learned it (event switch `$0068`, set where Cid opens the tube room's way
  out after the espers' scene, and never cleared), a Tool he boosts with all
  three points fires twice: two whole passes, each at the boost's x8, so
  Drill's two strikes become four.  Its price is the two firings, each at
  the 3-BP price (x15.625), capped at 99 as every price is: AutoCrossbow 63
  becomes 99.  The drawn number, the grey, the confirm, the charge and the
  passes all ask `Ot6Overclocks` (`ot6_overclock.asm`).  *Reason: the Tools
  shell picks one row and the engine runs one item record per action, so
  "two tools" is the row the player picked, fired twice: one press, the
  tool's own animation twice, and a price that says what it bought.  Under
  the full-boost rule it is worth the boost by construction (twice a 3-BP
  Tool), and its 99 MP bounds the repeat: two uses empty a L27 Edgar's 201.*
  `battle_overclock` plays it.  Air Anchor stays a findable *item* mid-kit
  gag rather than the capstone.
- **Flash and Debilitator are sold where this table says** (shop
  overrides in `ff6/src/menu/shop.asm`): Flash from Figaro's tool merchant
  in the World of Balance and at South Figaro, Debilitator at Vector's
  weapon shop during the banquet.  **Debilitator reveals the weakness it
  adds**: vanilla's effect adds one element the body is not weak to, and the
  break system reads the weak byte live, so it is a chip trigger at once;
  `Ot6DebilReveal` banks the added bit as a pending reveal, so the HUD draws
  its glyph instead of '?', and keeps it out of the species codex (the
  weakness is this body's, for this battle).  `battle_debilitator`.
- AutoCrossbow's piercing clears waves: one chip per body across a
  whole side, and exactly one chip against a solo boss. Drill answers armored
  bosses. Chain Saw covers slashing, so Edgar alone spans two physical
  classes through tools.

### Sabin — Monk (bludgeoning: fists; claws buy slashing)

The 8 Blitzes, verbatim ✦, with the vanilla level table preserved ✦,
selected from a menu. Fists are
the core of the **bludgeoning** class (fists, staves, rods). Equipping
claws switches his *Fight* to slashing ✦, but blitz classes are
immutable: Pummel with claws on is still bludgeoning. His ability list
sets his first class and his weapon slot sets his second.

Levels below are `BlitzLevelTbl` (`field/event.asm:1240`).

| # | Blitz | MP | Chip | Level |
|---|---|---|---|---|
| 1 | Pummel ✦ | 4 | bludgeoning ×2 | 1 (has it at join) |
| 2 | AuraBolt | 10 | holy | 6 |
| 3 | Suplex | 13 | bludgeoning | 10 |
| 4 | Fire Dance | 17 | fire | 15 |
| 5 | Mantra | 16 | — (heal) | 23 |
| 6 | Air Blade | 28 | wind | 30 |
| 7 | Spiraler | 50 | — | 42 |
| 8 | **Bum Rush** (divine; not built as one: a 99-MP Blitz row at any boost today) | **99** | bludgeoning ×4 | 70 / Duncan |

The MP column lives in `Ot6AbilityCostTbl` keyed by attack id $5d–$64.
Bum Rush is Sabin's ultimate and is
fixed at **99**, which is 13.0% of his L70 pool of 760 and the same fraction
Cleave is of Cyan's pool; both are pinned there so the fractions match. Mantra
is priced under Fire Dance because it is a utility option rather than a damage
tier. The full per-row derivation, and the baseline it is measured against,
are in mp-economy.md's "The baseline".

### Cyan — Samurai (slashing: katana)

The 8 SwdTechs priced in BP ✦ (charge gauge deleted ✦). Katana now
lives inside **slashing** with swords. Cyan is a slashing
*specialist*, with multi-hit slash chips nobody else matches; he is not
a mandatory key for katana-only locks. Vanilla level schedule kept.

Names below are the ones the game prints (`BushidoName`, the table the SwdTech
window renders from). The internal disassembly labels `Bushido*`, `Fang` and
`Oblivion` stay as they are, because renaming code symbols creates churn
against upstream for something a comment already handles.

| # | Tech | BP | MP | Chip | Level |
|---|---|---|---|---|---|
| 1 | Dispatch ✦ | 1 | 4 | slashing | join |
| 2 | Retort | 1 | 10 | — (counter stance) | 6 |
| 3 | Slash | 1 | 13 | slashing | 12 |
| 4 | Quadra Slam | 2 | 16 | slashing ×4 | 15 |
| 5 | Empowerer | 2 | 18 | — (drain; strikes ×2 at quarter power) | 24 |
| 6 | Stunner | 3 | 28 | slashing, all enemies | 34 |
| 7 | Quadra Slice | 3 | 50 | wind ×4 | 44 |
| 8 | **Cleave** (divine) | 3 | **99** | — (instant death; a boss takes a power-255 cut) | Phantom Train farewell (story, #379) |

SwdTech prices at **parity with the Blitz row of the same index**. This is a
level claim rather than an index coincidence: `BlitzLevelTbl` is
1/6/10/15/23/30/42/70 and `BushidoLevelTbl` 1/6/12/15/24/34/44/70
(`ff6/src/field/event.asm:1236-1240`), so row *n* of either kit lands at the
same stage against nearly the same pool. **Cyan pays both currencies.** If
parity plus the 1-BP floor leaves him starved, adjust BP seed and regen rather
than the floor or this column.

One deviation from parity: **Empowerer is 18 rather than Mantra's 16**,
because this column must stay monotonic with the tech index. The boost window
offers techs weakest→strongest and *the cursor row is the boost level*
(below), so a 2× row costing more than the 3× row would read as a bug.

Dispatch is the cheapest row of any kit at 4 MP (the "free-to-learn is not
free-to-use" floor), which is 6.9% of the pool Cyan
joins with, against the 8–21% a vanilla spell costs at the level it is learned.
Cleave is the most expensive at **99, the shared ceiling**: each character with
an ultimate pays 99 for it.  Learned at level 70 it was 13.0% of that pool
(762).  Learned at the Phantom Train farewell (#379), it is just past his
pool when he learns it: the play has him at level 14 with 96 MP there
(falls-done-v1, the save after the train), 148 at level 19 (banquet-done-v1)
and 205 at 24 (fc-alcove-v1), so the price, not the level, decides when he
first swings it, and from the late World of Balance on it is one swing a bar.
*Reason the price stays 99: the shared ceiling, and a guaranteed kill of any
killable body is worth a full bar.*  99 is also the largest number any OT6 price cell can render,
so it is the top of the table's range and not only its current maximum.
Per-row measurement, and the baseline, are in mp-economy.md's "The baseline";
checked by `tools/tests/battle_costtable.lua`.

These numbers live in `Ot6AbilityCostTbl` (ff6/src/battle/ot6_boost.asm)
(see mp-economy.md).

**Every number in these tables is a base price for the rows that
escalate.** Since #219, boosting an ability whose damage the boost
multiplies costs escalating MP: the row's price becomes
`max(base, min(99, floor(base * 2.5^boost + 0.5)))` (`Ot6BoostPriceFor`),
i.e. x1 / x2.5 / x6.25 / x15.625 for pending boost 0/1/2/3, capped at 99 and
never below the base (Phoenix's 110 stays 110).

Who pays it is one test: **a price escalates exactly when `Ot6BoostDmg`
multiplies it.** Blitz, Tools and Dance escalate, because their commands are
outside `Ot6BoostDmg`'s gate and the boost buys them x2/x4/x8. Everything in
that gate is flat, for its own reason: SwdTech, because the boost was already
spent picking the row and the row is charged at its own price; Fight and
Capture, because the boost buys swings; Filch and Bestow, because the boost
buys them nothing at all; and **Steal, Rage and Slot**, the chance verbs,
because the boost on them buys certainty across a spread of outcomes rather
than magnitude, and the BP it costs is what pays for that (owner,
2026-09-17). So Steal is 4 at every level and Rage is 8 at every level, while
Dance — which shares Rage's base price of 8 — pays 8 / 20 / 50 / 99.

The one arithmetic authority is `Ot6BoostPriceFor`
(ff6/src/battle/ot6_boost.asm), which the drawn number, the grey, the confirm
and the charge all reach, so they cannot disagree. The rule, the whole
resulting table and the rulings behind it (the 99 cap flattening dear rows;
an unaffordable boost greyed and refused) are in mp-economy.md's "Boosting
costs MP".

`Ot6BushidoTier` (ff6/src/battle/ot6_bushido.asm)
replaces the charge gauge's clock in `UpdateMenuState_37`; the window, its
numerals, the grey-out of unlearned techs, the A press that stops the gauge,
`FixPlayerAttack`'s `+$55` and `Cmd_07` are all vanilla and untouched. Boost
1/2/3 selects a **moving window**: Cyan's top *learned* techs, weakest →
strongest. There is no 0× tier: `Ot6BushidoTech` clamps a stray 0 up, and the
menu never offers one.  Techs 1-7 come by level, in order, so what he knows of
them is a run 0..`ceiling`; Cleave comes by story at the Phantom Train farewell
(#379), ahead of the run's end, and stands apart from it.  `ceiling` is
vanilla's own `$2020` (techs known − 1, the value that used to cap the bar)
less Cleave, capped at 6 (`Ot6BushidoCeil`; `Ot6LoadoutCeil` is the field's
twin, off `$1cf7`).  One leaf, `Ot6BushidoPick`, makes the pick for the battle
and the configurator: before Cleave, the window is three wide, `base =
max(0, ceiling−2)` and boost picks `min(base+boost−1, ceiling)`; with Cleave,
the 3-BP row is Cleave and the 1- and 2-BP rows are the run's top two, `base =
max(0, ceiling−1)`.  This is arithmetic only, with no table.

| techs known | window (BP 1 / 2 / 3) | retired |
|---|---|---|
| ≤ 3, before the farewell | all of them, in learn order | — (every learned tech reachable) |
| Dispatch + Cleave | Dispatch / — / **Cleave** | — (the 2-BP row would repeat Dispatch, so it is blank) |
| Dispatch, Retort + Cleave | Dispatch / Retort / **Cleave** | — |
| through Quadra Slam + Cleave | Slash / Quadra Slam / **Cleave** | Dispatch, Retort |
| through Empowerer + Cleave | Quadra Slam / Empowerer / **Cleave** | Dispatch…Slash |
| through Stunner + Cleave | Empowerer / Stunner / **Cleave** | Dispatch…Quadra Slam |
| 8 (full kit) | Stunner / Quadra Slice / **Cleave** | Dispatch…Empowerer |

The window never skips a middle
tech of the run; only the weakest retire, as Cyan outgrows them.

Three rulings, documented in `Ot6BushidoTier`'s header:

- **Utility techs retire with the window.** Retort's counter stance and
  Empowerer's
  drain become unavailable once Cyan out-levels them, which costs him utility
  and not only damage.
  Ruling: no special-casing of utility in the auto-window. A player who wants
  a utility tech pins it in a slot with the player-chosen **loadout**.
- **No affordable floor.** The 1× slot is always the cheapest tech *in the
  window*, so it gets pricier as Cyan levels. This is accepted, because his
  MP pool grows on the same schedule.
- **Cleave is the window's 3-BP row** from the Phantom Train farewell on, the
  divine's one gate (see "Divines").  *Reason for the farewell (#379): it is
  the moment his story turns, and a divine comes by story; at level 70 it was
  out of reach of any playthrough that does not grind for it.*  The farewell
  script teaches it with event command `$9e` (`give_bushido_tech`, which
  vanilla left unused), and `BushidoLevelTbl`'s eighth entry is 255, a level
  nobody reaches; Cyan's World of Ruin dream still teaches every tech.  A
  manual loadout may not put it on the 1- or
  2-BP row: `Ot6CleaveSlot` (one leaf for the battle read, the
  configurator's draw and its cycle) refuses it there, and a stored one
  falls back to the auto window for that slot.  A random SwdTech (a
  Muddled or Charmed Cyan, the Colosseum) spends no boost, so its pick
  ranges over the run he knows and never Cleave (`Ot6RandBushidoTop`:
  vanilla's 0..`$2020` would also have reached a tech he does not know,
  since Cleave sits ahead of the run).  At resolution `Ot6Oblivion`
  reads the target: a killable one takes a guaranteed Death (no Broken
  condition any more); a death-immune one (a boss) takes the heaviest
  single cut a record can carry, power 255 with its damage recomputed
  (`Ot6CleaveDmg`; CalcDmg runs before the target is known, so the old
  fallback's power of 70 landed nothing at all).  The record strikes the
  enemy group, and the other bodies take the record as it stands on that
  pass.  *Reason for the cut: a full boost must pay against a boss too, and
  a single 70 was less than the 2-BP Quadra Slice row; 255 is the most one
  hit can carry, about Quadra Slice's four strikes.*  It can be used again
  in the same battle.  `battle_divines` checks the rows, the loadout, a kill
  on an unbroken soldier and two boss cuts in one battle; `battle_cleave`
  the learned Cleave and the window from the play past the farewell;
  `battle_bushidoloadout` the windows beside a short run.

**BP is read, never written.** `Ot6ActionEnd` consumes the spend and skips that
turn's regen exactly as for any other action, and the ≤3 / never-past-bank caps
stay `Ot6Boost`'s. SwdTech is excluded from `Ot6BoostDmg`'s multiplier for the
same reason folded spells are: the points bought the tech, so they must not also
buy damage. Spend the window cannot use (three points at L1 still buys Dispatch)
is spent rather than refunded, the same terms a mage already accepts for a third
point on Fire.

**The SwdTech menu UI is a name + cost submenu.** SwdTech does not
open the vanilla numeral gauge; `OpenCmdMenuTbl[7]` is repointed to a tools-shell
submenu (the same route Blitz takes) that lists the three moving-window techs by
name + MP cost, greyed when the caster can't afford the MP *or* the BP, and
**refused at the confirm** for either reason: `Ot6KitConfirmMP` (the same
gate Blitz, Tools and the thief submenu take, mp-economy.md ruling 2) refuses
the MP reason and, since #232, the BP reason as well, reading the row's grey
from the same `Ot6BushidoRowGrey` that coloured it; `Ot6BushidoConfirm`'s
own bank test is the backstop. Either way it
buzzes and leaves the list open, so a row the window draws as unreachable
costs nothing to
try. It reuses the Tools window shell,
`Ot6CostFor`, and `Ot6AbilityGrey`. SwdTech's rows do **not**
take #219's 2.5x escalation, for the reason the row already exists: the boost
is the row, so the row's own price is the escalation (`Ot6KitRowCost`'s
bushido arm, and `Ot6AbilityCost`'s). The thief window's three rows do not
escalate either, for the chance-verb reason above, so Blitz is the only kit
window `Ot6KitRowCost` prices through `Ot6PendPrice`. The **cursor row is the boost
level** (row 0 = boost 1× … row 2 = boost 3×), so picking a stronger tech spends
more BP. That keeps the numeral gauge's trade of BP for a stronger cut and
makes it readable. Confirm banks `$3e9d = r` and reuses `Ot6BushidoTier` to store the
base+r tech; a row the caster lacks the BP for is greyed and refuses on confirm.
`SwdTech`'s names render from `BushidoName` (not `AttackName`, whose $55–$5c slots
are empty pad).

**The loadout is player-configurable.** By default the three boost
slots are the auto-window (top-three learned, weakest→strongest), but
the player can choose which learned techs occupy 1×/2×/3× and in what order,
from a **field-menu configurator**: X-menu → Skills → SwdTech opens it (bank C3),
showing the three boost slots (name + MP cost) over the learned pool; Up/Down pick
a slot, L/R cycle its tech, Y reverts to auto, B exits. The mechanic is the same
either way, but the player picks the three instead of the scheme picking three
and retiring the rest. The config UI is a **thin C3 shim over bank F0**: every
decision (seed-from-auto, per-slot validated tech, assign, revert, write-back) is a
`jsl` into OT6 F0 procs (`Ot6Loadout*`), so OT6 stays nearly-all-F0 despite its
first menu-bank presence; costs price through `Ot6CostFor` (built for menu-bank
callers), the learned set/ceiling derive from `$1cf7` (not battle-only `$2020`).

Storage is **per-save**: a single 16-bit word at `$1E1D..$1E1E`, inside FF6's
`$1600–$1FFD` save block that round-trips per slot and sits in the save checksum,
so a loadout persists per file and validates automatically. Cyan has exactly 8
SwdTechs (index 0–7 = 3 bits), so the four boost slots pack into 12 bits: slot 0
= bits 0–2, slot 1 = bits 3–5, slot 2 = bits 6–8, slot 3 = bits 9–11 (top 4 bits
unused). **`$0000` = auto**: an all-zero word decodes to "all four slots = tech 0",
a degenerate config no player sets on purpose, and it reads 0 on every existing
save. The word therefore doubles as the auto sentinel, and old saves and new
games default to the auto-window with no migration and no separate mode flag.
Revert-to-auto writes `$0000`. The battle read is a single branch at the top
of `Ot6BushidoTech` — the shared leaf both the list and the confirm/damage path
call — so manual mode governs display, fire, and damage together; a stored tech
that is no longer learned (`$1cf7` bit clear) falls back to the auto window for
that slot.

The Chip column is what ships (#379): `Ot6SkillClassTbl` (`ot6_class.asm`)
marks Dispatch, Slash, Quadra Slam, Stunner and Cleave slashing; Retort (a
counter stance) and Empowerer (a drain) are classless and chip nothing; and
Quadra Slice is wind, its MagicProp element (battle_main.asm's override 7),
which also moves its damage as any wind attack's (double on a wind-weak body,
nothing on an immune one).  No monster casts Quadra Slice, so no monster's
behaviour moves.  `battle_swdtechclass` reads both from the built ROM.

Test: `tools/tests/battle_bushido.lua`.

---

## The middle three

### Terra — Esper mage (slashing: sword, fire lean)

Vanilla's natural-magic table, trimmed to base tiers with the levels
compressed so the list completes late-WoB. Vanilla makes her the
game's only natural raise-learner (Life at 18), which is kept, so in the
World of Balance revival lives on Terra, Fenix Downs, and Sraphim, and
nowhere else. The World of Ruin adds Phoenix's Life (magicite.md, #327).

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

- **Ultima is the fourth fold rather than a slot ✦.** Vanilla's table
  already teaches Terra Ultima at level 99, a level almost no player
  reaches. OT6 makes it reachable without spending a menu row: after a
  very-late story unlock -- her World of Ruin return at Mobliz, event
  switch `$00BF` -- Terra casting Fire at 3 BP folds past Fire 3 into
  **Ultima** (`Ot6FoldSteps` gives her a third step, `Ot6FoldTier` folds
  Fire's row to Ultima on it). It does not appear in her list until the
  fold preview renders it. The fold is the boost's purchase, as every
  fold's is: the cast is priced as Ultima (its own 80 MP) and takes no
  damage multiplier (`Ot6QueueFold` marks it, `OT6_ULTIMAFOLD`). Before the
  unlock, and for everyone else, Fire at 3 BP is Fire 3. Everyone else gets
  Ultima by equipping Ragnarok, and that Ultima is a multiplier spell like
  any other. `battle_ultimafold`.
- **Trance is her divine, and it is her Morph** (vanilla's esper form:
  magic x2, damage taken halved, for as long as the morph gauge lasts,
  learned at the Zozo awakening, battle switch `$42`).  Its one gate is the
  full boost: picked with fewer than three points it buzzes and the command
  window stays up (`Ot6TranceOffer`, OpenCmdMenuTbl[$03]'s stub), and a
  Morph the engine chooses (Muddle, Berserk) or one whose boost was taken
  back does not morph and charges nothing (`Ot6TranceGate`, Cmd_03).  Revert
  stays free, so she can Trance again in the same battle.  *Reason: vanilla
  Morph is already an apex worth three points, and its own gauge bounds it
  across battles.*  `battle_trance`.
- **Break (level 24, and Shoat's) takes shields** (#398): no damage and no
  status; one shield off its one target, ignoring class and element, plus
  one per boost point (four at 3 BP, the ceiling Quadra Slice and Bum Rush
  reach), at its flat 25 MP (the boost buys shields, never a tier or the
  multiplier).  It reveals nothing (Filch's rule).  It is a character's
  own cast: Magic or X-Magic (Terra, Shoat, a Mimic of one) or the Break
  Blade's on-hit spell (one shield: the swing's boost bought swings).  A
  monster's Break, and Control, Sketch and a Rage, which cast as the monster
  does, keep vanilla's petrify -- the Life 3 precedent (magicite.md):
  characters' casts get OT6's behaviour, monsters keep vanilla's.  It works
  on bosses: shields are the boss's own break system.  `Ot6BreakOurs`,
  `Ot6BreakProps` (the vanilla record, edited as it loads for OT6's cast)
  and `Ot6BreakSpell`; `battle_breakspell`, `battle_breakmonster`.

### Locke — Thief (piercing: dagger)

Story-verb learner. His kit covers more than repeated stealing: he
probes, redistributes and corrodes, with some merchant work as well
(he'd say TREASURE HUNTER).

| # | Skill | Effect | Source |
|---|---|---|---|
| 1 | Steal ✦ (4 MP) | vanilla steal | join |
| 2 | Mug | steal + piercing damage | South Figaro escape |
| 3 | Trickshot | piercing chip at range (thrown coin) | Lete River |
| 4 | Filch ✦ (6 MP) | take one shield, class-blind, and bank it as 1 BP | Opera house |
| 5 | Bestow ✦ (5 MP) | give an ally 1 BP | Vector (merchant beat) |
| 6 | Dismantle | armor corrode: −defense, piercing chip | Sealed Gate |
| 7 | Appraise | reveal one enemy's full weakness row | Thamasa |
| 8 | **Master's Mark** (divine, at 3 BP; not built) | steal from all enemies + reveal everything | Floating Continent |

- Filch and Bestow move BP around: take from enemies, give to
  allies. Tactically he supplies tempo as well as loot.

**The thief submenu.** Steal is tier one of this list rather than
a verb of its own, so the list sits behind the Steal row:
`OpenCmdMenuTbl[$05]` opens the Tools-window shell with Steal / Filch / Bestow
in it (`Ot6ThiefListOpen`), priced, with unaffordable rows greyed. This
arrangement is forced, because **Locke has no spare command slot.**
`char_prop.asm:160`
records FIGHT, STEAL, MAGIC, ITEM; the apparently blank third row is MAGIC
removed at runtime by `InitCmd_03` (`battle_main.asm:14112`) for a character who
knows no spell and holds no esper, and the battle
menu is still hard-wired to four rows. When Locke equips an esper the row
comes back as Magic, which this doc's row-sharing rule says is never the row to
sacrifice.

**Filch cannot be a BP steal, because an enemy has no BP.**
`OT6_BP_CLASS` (`$3e9c`) is a *split*
table: character rows hold boost points, **monster rows hold the species'
authored class-weakness mask**, seeded at battle init by `Ot6SeedShields`
(`ot6_break.asm:36` authored, `:51` generated floor). There is no monster BP to
take, and decrementing that byte would corrupt what the break system thinks the
monster is weak to. The alternative reading, where Filch *hands* Locke a
pip, does not work either: `Ot6ActionEnd` already pays +1 BP for any turn a
character did not boost through (`ot6_boost.asm:171-175`), so an ability whose
whole effect is +1 BP is strictly worse than Fight.

Filch instead takes the resource the enemy does have: **one shield, which Locke
keeps as a boost point.** The chip is **class-blind and
element-blind**, whereas `Ot6ClassChip` only fires when the attack's class matches
the target's weakness row, so Locke's piercing dagger does nothing against anything
not weak to piercing. Filch is the party's only weakness-independent shield
remover. It reveals nothing (it takes the shield without teaching the row, so it
complements Debilitator rather than replacing it) and deals no damage. A landed
Filch gives Locke **+2 BP on the turn**, the filched pip plus his own unboosted
regen, which nothing else in the game does. Against an already-Broken or
shieldless target it is a no-op.

Bestow is the sketch verbatim. Its debit rides `OT6_BOOST_REVEALED` so that
`Ot6ActionEnd` does the subtraction, which is the only BP charge path in the game
and is what stops Bestow being free: if it were charged inline, Ot6ActionEnd would
still pay Locke his regen and Bestow would yield a pip a turn for 5 MP. At 0 BP
the row greys and, since #232, the confirm refuses it (`Ot6KitConfirmMP` reads
the same `Ot6BushidoRowGrey` that coloured it), so the turn and the 5 MP stay
with the player; a self-target and an ally already at the 5 cap are still
refused at execution. `battle_bestowrefuse` is the suite.

**Break class: none of the three takes one.** Steal and Bestow deal no damage,
and Filch deals none either. A class glyph on Filch's row would be wrong about
the property that matters: it chips whatever the row says.

**Story gating: grant at join, i.e. no gate.** The rows are Steal's rows and
Steal is granted at join, so they arrive with him. Reasons, in order of weight:
(1) Locke has no learned-set byte, where Blitz has `$1d28` and SwdTech `$1cf7`,
and inventing a per-ability set for him is a change that should ride the change
that needs *eight* tiers rather than the one that ships two; (2) it
is the only option that structurally cannot leave a past-the-beat save without
the skill. When tiers 2/3/6/7 arrive and a learned set becomes
unavoidable, the gate can be added then and grant-at-join becomes its
already-satisfied floor for these two.

**Prices** are on mp-economy.md's baseline (8-20% of the real pool at the
level the ability arrives) against Locke's 31 MP at LV6: Steal 4 (12.9%),
Bestow 5 (16.1%), Filch 6 (19.4%). These are **not** monotonic with the tier
numbering above. Only SwdTech must be monotonic, because there the row *is* the
boost level; this is a free-choice menu like Blitz, which already ships Mantra
under Fire Dance. Filch sits at the top of the baseline range because it is the
strongest thing in the slice and five casts from a full LV6 pool is the scarcity
`mp-economy.md` asks for. `Ot6ThiefCostTbl` is a **second** keyed table, not new
rows in `Ot6AbilityCostTbl`: the row ids are AttackName pad slots `$56-$58`,
which sit inside SwdTech's `$55-$5c` key range, and that shared table's single
scan is built on its three key ranges being disjoint. The command gate is what
keeps the two tables apart. Test: `tools/tests/battle_thief.lua`.

**Boost-tiered Steal.** Steal is the party's first *chance verb*:
it rolls dice, so BP buys certainty rather than potency (DESIGN.md's canon rule,
"on chance verbs boost guarantees"). Each point tilts both axes of the vanilla
gamble, the success chance and the common-vs-rare pick, monotonically, and the
full spend removes the roll:

| BP | Success | Item pick |
|----|---------|-----------|
| 0 | **vanilla, to the byte**: level+50−targetLevel, Sneak Ring doubles it | vanilla: 1/8 rare, 7/8 common; an empty picked slot still yields nothing |
| 1 | +40 to the effective level (a hard steal → a coin flip; a coin flip → a near-lock) | 3/8 rare when both present; never "nothing" on a hit (takes whichever slot is filled) |
| 2 | +90 (level parity now auto-succeeds) | 3/4 rare when both present; same fallback |
| 3 | **guaranteed** (the level clamps to $ff, so the roll is skipped entirely) | **rare if present, else the common**, taken outright with no roll |

Rulings that fall out of the vanilla math (see `tools/tests/battle_steal.lua`):

- **Sneak Ring** keeps helping the un-boosted and partial tiers: it doubles the
  residual success chance at 0–2 BP exactly as in vanilla. At 3 BP it has no
  effect, because the level clamp overflows *before* the chance value is ever
  formed, so the ring is never consulted; it has nothing to add to a steal that
  is already guaranteed.
- **Boost never creates loot.** An enemy with nothing to steal, or one already
  looted (both slots cleared), yields vanilla's "nothing" at every tier, because
  the $ffff top-check drops out before the tier logic runs. 3 BP guarantees a
  steal *if there is something to steal*, and "rare if present" falls back to the
  common when there is no rare.
- **No damage, no multiplier.** Steal deals no damage, and the Ot6BoostDmg command
  gate ($05) keeps boost from adding any: a chance verb takes the
  guarantee, not the ×2/×4/×8 a damage verb takes. That keeps the two
  axes separate.

### Celes — Rune Knight (slashing: sword, ice lean)

Vanilla natural-magic levels nearly verbatim, since the table already
suited a rune knight: sensing, warding, hastening. It mirrors
Terra: both share Cure, and fire/life/transcendence is set against
ice/order/tempo. The pairing is clearer here than in vanilla.

| # | Spell/Skill | Level |
|---|---|---|
| 1 | Runic ✦ (absorbs next spell → **+1 BP** ✦; **boost buys turns** ✦) | join |
| 2 | Ice | join (vanilla 1) |
| 3 | Cure | 4 (vanilla) |
| 4 | Imp | 13 (vanilla) |
| 5 | Scan | 18 (vanilla) |
| 6 | Safe | 22 (vanilla) |
| 7 | Haste | 32 (vanilla) |
| 8 | **RunicBlade** (divine) | Magitek factory (story: switch `$0068`) |

- **Runic's absorb becomes MP and banks 1 BP** (`Ot6RunicBP`, ot6_boost.asm,
  hooked into vanilla's `RunicEffect`). Rulings, all covered by `battle_runic.lua`:
  an absorb at a full bank is **capped, never wrapped**; the
  no-regen-after-boost rule does not gate it, because that rule
  governs a turn's own end-of-action tick while the absorb is paid
  during the *caster's* action, so boosting on the turn she raises Runic
  still pays for what she catches; and only the Runic *command*
  pays, not the separate "enemy runic" stance a raging Gau can carry.
  Vanilla's own gate is untouched: what Runic can absorb is still set by the
  spell's `MagicProp` absorb flag, which excludes every esper and every
  MagiTek beam. The Narshe school's $026F now names the BP.
- **Boosted Runic: on reactive verbs, boost buys duration.**
  This is the third canon category, stated in DESIGN.md because future reactive
  verbs inherit it. 1/2/3 BP = **1/2/3 of Celes's own turns** during which
  the stance stands and **she acts normally**. There is no tier that buys
  the free turns without the duration: vanilla ends the stance in
  `QueueAction` (battle_main.asm:511) *because* she acted, so the only way
  she can act without dropping it is for the stance to outlive her action.
  Rulings:
  - **The duration is counted in turns, not absorbs.** A player can read a
    turn count off the fight ("three turns of shield"), while an absorb
    count depends on the enemy's script. A turn count also bounds the
    economy without extra work.
  - **The BP earn is once per round** (`OT6_RUNICPAID`), the same cap
    True Knight takes. Without the cap, the earn would scale with absorbs and
    with how many things are casting; with it, the earn does not scale.
  - **The MP half stays per absorb and uncapped.** Only the BP earn is
    rationed. Vanilla's restore is the reason a rune knight benefits from a
    caster boss, and rationing it would delete the ability's own reward.
  - **Vanilla's ally-spell quirk is kept.**
    Runic absorbs a *friendly* cast as readily as a hostile one, and a stance
    that stands for three turns will absorb a lot of Terra's Cures. That is
    the constraint that stops a standing shield from being strictly good,
    so it is documented rather than patched.
  - Known edge: a spell that arrives while Celes is stopped/asleep clears
    the stance bit at `RunicEffect`:8671 without absorbing (vanilla's own
    `CheckStatus` gate), and the bit only comes back at her next turn. The
    duration is not shortened, but that spell is not absorbed. Left as vanilla.
- **RunicBlade is what a full boost buys on Runic** once Celes has
  learned it (event switch `$0068`, the Magitek factory, where she turns on
  Kefka).  A 3-BP Runic stands for three of her turns as any 3-BP Runic
  does, absorbs as Runic does (the MP, the once-a-round BP), and sends every
  spell it absorbs back at its caster as her own free cast of it, through
  vanilla's counterattack queue (`Ot6BladeRaise` / `Ot6BladeAbsorb` /
  `Ot6BladeBounce`).  The bounce is the absorbed spell, not a stronger one,
  and no Runic stance absorbs it again (`Ot6BladeNoRunic`: her own stance
  stands while it flies).  An ally's spell she absorbs goes back at the ally
  -- vanilla's ally-spell quirk, kept -- and a spell of her own that her
  stance catches goes nowhere.  Only player magic ($00-$35) bounces;
  a counter is not countered back, and a battle with counters off bounces
  nothing.  *Reason: the old objection to making the divine "Runic at 3
  BP" -- that the canon would have an exception at its top tier and the
  divine would be out of reach without BP -- is the owner's rule now
  (divines take the full boost), and as the 3-BP Runic it costs no menu row
  and keeps duration the reactive verb's purchase.*  `battle_runicblade`.

### Setzer — Gambler/Merchant (special ¤: cards, dice; darts = piercing)

Slot ✦ is the signature; Coin Toss and Hired Help carry the merchant house
(paid in gil, not MP); the divine is **Jackpot**, a Fixed-Dice triple
payoff, never Slot itself ✦. His cards, Trump and Dice chip ¤ on Fight;
the Fixed Dice are null-break (large numbers, no chip, row ignored, vanilla
behaviour preserved ✦). Decisions below were made as the TLM's delegate
for #319 (2026-10-02), each with its reason.

| # | Ability | Price | Chip | Boost buys | Source |
|---|---|---|---|---|---|
| 1 | Slot ✦ | free | the reel's attack | the rig's certainty (see Steal's ladder; `ot6_slot.asm`) | join |
| 2 | Coin Toss | level × 30 gil a toss | ¤, one per body a toss (every enemy) | another toss a point (1 + boost tosses, each its own gil, hit and chip) | join |
| 3 | Hired Help | level × 50 gil a hire | the target's own physical class (slashing, else piercing, else bludgeoning), one a hire | another hire a point (1 + boost hires, each its own fee, hit and chip) | join |
| 4 | **Jackpot** (divine) | 99 MP, at 3 BP | null-break | the divine itself: the full boost buys a throw of two rolls, each its own gamble and its own hit | his World of Ruin return (Kohlingen, switch `$00CA`) |

**The table behind Slot.** Setzer's rows are FIGHT, SLOT, MAGIC, ITEM and
the menu is four rows, so like Locke he has no spare slot, and his third
row is the Magic an Esper gives him. The ladder goes behind the row he has:
`OpenCmdMenuTbl[$0f]` opens a Tools-shell list (mode `$6168 = 4`) whose
first row is Slot itself; Slot's row closes the list and opens the reels
exactly as the command window did, so the reels, their boost ladder and
their charge are unchanged. *Reason: Locke's thief list is the precedent,
and it keeps Magic.* A Coin Toss relic still turns Slot into GP Rain (no
table), as a Thief Glove turns Steal into Capture; a Gogo with Slot gets
the reels straight away (the table is Setzer's job). The row ids are the
last AttackName pad slots: Coin Toss `$59`, Hired Help `$5a`, Jackpot
`$5b`, Slot `$5c` (Slot never queues, and `$5c` is the id Ot6Oblivion keys
Cleave on). `ot6_setzer.asm` has the machinery.

**Coin Toss is GP Rain as a kit row.** It runs vanilla's GP Rain effect:
it takes level × 30 gil and deals twice that, ignoring defense, split over
the targets (the enemy side). *Reason: the relic named Coin Toss already
is this verb in FF6; the kit row makes it Setzer's own without a relic
slot.* Coins are ¤, like his cards and dice, so it chips one shield on each
body whose row holds ¤: the wide ¤ key the guideline asks for ("Special is
a common key"). **Boost buys tosses** (owner, 2026-10-02: boost pays
through more hits, never a bigger one, so no point is lost to the 9,999 cap
on one hit -- at L50 one doubled toss already capped on a lone unshielded
target): 1 + boost tosses, one pass of the action each (`Ot6SetzerEffect`
adds the boost to the attack count), each at level × 30 gil, each its own
hit on every body and its own ¤ chip on every ¤-weak one. Three points are
four tosses and four chips a body. A toss after a body falls splits over
the bodies left (`battle_passretarget`). A toss that finds no body standing (the
tosses before it felled them all) pays nothing, and so does such a hire
(`Ot6CoinPrice`, `battle_hirerefund`). The Coin Toss relic's GP Rain buys
tosses the same way (`Ot6RainPasses` in Cmd_18); before #319 its boost
bought nothing (Ot6BoostDmg's multiplier runs before GP Rain's effect
overwrites the damage). (Earlier the same day the boost doubled the coins,
×2 gil and ×2 damage a point; set aside for the cap.)

**Hired Help is a sellsword whose weapon fits the target.** One enemy; a
hire costs level × 50 gil and lands twice its fee, and its break class is
the first physical class in the target's weakness row (slashing, then
piercing, then bludgeoning); a target with none takes an unkeyed hit.
*Reason: the merchant buys the key the party lacks; it is priced in the
resource a WoR party has a lot of, but a player feels (1,550 gil a hire at
L31), and it is never ¤ (that is Coin Toss's and the cards').* It reveals
the class it chips, as any chip does. **Boost buys hires** (owner,
2026-10-02: boost pays through more hits, so it never runs into the 9,999
cap on one hit): 1 + boost hires, one pass of the action each
(`Ot6SetzerEffect` adds the boost to the attack count Ot6HitCount uses),
each paying its own fee, landing its own hit and chipping its own shield.
Three points are four hires, four chips and 6,200 gil at L31; a hire
lands 3,100 there (1,550 shielded, 6,200 on a Broken body), and its fee
never passes 4,950 (L99), so the damage cannot wrap (the old one-hire x8
fee wrapped from L82) and a hire that meets the cap on a Broken body still
leaves every point its own hit. A hire that outlives its target goes to
another monster, as every pass OT6 adds to an action does
(`Ot6PassRetarget`; [multi-hit.md](multi-hit.md) §6), and one that finds
none standing pays nothing.

**Each hire is somebody new** (owner, 2026-10-02: a growing crew, not the
same guy again). Setzer walks out of sight, and each hire walks in where
he stood, swings the weapon that fits the target and walks off: the 0 BP
hire is a merchant, and each point brings the next, tougher figure, an
Imperial soldier, then General Leo. The fourth hire (3 BP) depends on
Shadow (owner, 2026-10-02):
- **Shadow**, FF6's own mercenary for hire, when he is there to hire:
  recruited and not left on the Floating Continent (event switch
  `$02E3`: his recruitment sets it, and the escape's Jump without him
  clears it), so a Shadow who made the airship is for hire in the World
  of Ruin before he rejoins;
- **Interceptor** while Shadow is in the battle's party, standing or KO'd
  (he can't walk in from outside it, so his dog takes the job and bounds
  in with his counterattack); with no body left to hit, the dog's pass
  draws nothing;
- **a Phantom Train ghost** when Shadow can't be hired (never recruited,
  or left behind on the Floating Continent): the ghosts who joined Sabin's
  party on the train are FF6's other hired hands, and their battle sprite
  set is in the ROM.

Where they walk: in a front, back or side attack, off the screen edge
behind the party (away from the enemies, the way the turn's step back
goes); in a pincer, where the party stands mid-screen between the two
sides, up the party's column and off the top edge, the slot hidden
whenever a tile would be pinned to y = 151 (Float's bob and magitek's
lift counted). Every swap of the slot's graphics happens with the slot
hidden and out of sight, and
Setzer's pose is put back after the last hire as it was before the first.
*Reason: the boost buys hires, and a hire should look hired. The figures
are the ROM's own full battle sprite sets (Locke's disguises, Leo, Shadow,
the train's ghosts), drawn in Setzer's own slot: no VRAM and no new art;
each figure's palette is loaded into Setzer's slot's palette while it
stands in.* The weapon is a fixed one a figure and class (merchant: Dirk,
Regal Cutlass or Mithril Rod; soldier: Mithril Blade, Mithril Pike or
Morning Star; Leo: Crystal, Gold Lance or Morning Star; Shadow: Kodachi,
Ashura or Flail; ghost: Dirk, Mithril Blade, Mithril Pike or Bone Club);
it is a picture only, the class is the hire's. A hire that finds no body
still walks in, and leaves without a swing. The animation draws no Rand
and leaves `$be` as it was; the longer action shifts the frame clock and
ATB timing, so later draws and later battles' keys move (the review
measured the next battle's key: `$be` 60 against E0, build/attempts/wt/
hire-sprite-review/). (`Ot6CoinAnim`, `Ot6HireMark`, `Ot6ShadowHirable`;
`battle_hiredhelp` (1 BP, 0 BP) and `battle_hirecrew` (3 BP, 2 BP) hold
every pass, swap, strike and the restore to the animation's own state,
and count every tile of Setzer's slot the engine pins on any frame of a
hire; the ghost, Interceptor and the pincer (a floating Setzer's too)
are played in labs. Evidence and negative controls: build/attempts/wt/
hire-sprite/round2/, round3_main/ (the v0.24 merge) and round4/.)

**Jackpot (divine): the Fixed Dice come up a triple.** One enemy, by
vanilla's dice arithmetic: face³ × level × 2 for the three dice, times the
face again for the triple (saturating at 65,535 as vanilla's loop does),
then the hit as any hit lands: halved while the target's shields hold,
doubled once it is Broken, capped at 9,999. Null-break: the Fixed Dice
are the outliers, so it chips nothing and ignores the row. **It is a
divine, so its one gate is the full 3-BP boost, and that boost buys a
throw of two rolls** (owner, 2026-10-11; `OT6_JACKPOT_ROLLS`): each roll a
face 1-6 at near-even odds, 42-44 of 256 a face, consistent with the
measurement below (one battle Rand, drawn again past 251, mod 6; the redraw
takes the table's next byte, a fixed successor), each its own triple and
its own hit.  Under three points the row greys and is refused; a throw
whose boost was taken back after the pick rolls nothing and pays nothing.
A roll whose target fell to the roll before goes to another monster; a pass
that finds no body left is skipped: no triple, no dice, no draw. What one
roll lands (the means at even odds; the 42-44 weights move them by under
2%):

| face | L31 shielded | L31 unshielded | L31 Broken | L50 shielded | L50 unshielded |
|---|---|---|---|---|---|
| 1 | 31 | 62 | 124 | 50 | 100 |
| 2 | 496 | 992 | 1,984 | 800 | 1,600 |
| 3 | 2,511 | 5,022 | 9,999 | 4,050 | 8,100 |
| 4 | 7,936 | 9,999 | 9,999 | 9,999 | 9,999 |
| 5 | 9,999 | 9,999 | 9,999 | 9,999 | 9,999 |
| 6 | 9,999 | 9,999 | 9,999 | 9,999 | 9,999 |
| a roll's mean | 5,162 | 6,012 | 7,017 | 5,816 | 6,633 |

so a throw's mean is twice the roll's, about 10,300 shielded at L31.
**Re-justified for repeated use** (the owner removed the once-a-battle
limit): it was priced at 99 MP for up to four 9,999 hits *because* it came
once a battle.  Now a throw can come every fourth turn, so the throw is two
rolls, half the old ceiling, and the price stays 99, the shared ultimate
ceiling: a third of his L31 pool (297), so a full pool buys three throws a
fight, about 31,000 expected shielded at L31 over a dozen turns.  That is
the strongest damage in his kit and worth the full boost (a 3-BP boosted
Fight lands a few thousand), and it is a gamble: a sixth of rolls are a
face 1 (31 damage), so a throw can whiff.  Two rolls rather than one keep a
whole throw from being a single dud.  (The earlier "1 + boost rolls" and
the once-a-battle flag are retired with the rule.)
The labs that measured the faces (`build/attempts/wt/kit-setzer/
jackpot-dist/`, `labs-r3/`): a fight, dice included, is fixed by its
battle key and the inputs, and from the grave the key takes 16 values, so
runs repeat throws and the labs count each distinct throw once. Played
throws at 3 BP, the fight varied by 15 keys and six in-battle stands: 30
distinct throws of 96, 120 rolls, faces 1-6 14 / 24 / 19 / 27 / 19 / 17,
chi2 5.6 (5 df; 11.07 is p = .05). The earlier fault-injected lab's 3-BP
fives (34 of 320, chi2 14.0) were in part repeats: 64 distinct throws of
80, 256 rolls, 43 / 54 / 50 / 36 / 30 / 43, chi2 9.1. Nothing else is
bought: no multiplier (cmd `$0f` is in Ot6BoostDmg's gate) and the MP is
flat.  **Learned on his World of Ruin return** (switch `$00CA`, set when
he rejoins in Kohlingen's inn). *Reason: divines come by story, and his arc
is the tomb and the Falcon; in the WoB his L16-25 Jackpot would land
9,999s against bosses of 5-10k HP, so it waits for the WoR, where it makes
him a recruit that matters at once.*  **Mimic copies the throw**, and the
gate is the copier's own boost (the dice read it at execution): a Gogo with
three points pending throws two rolls free; one without throws nothing.

**Prices.** Slot stays free. Coin Toss and Hired Help cost gil only (the
row draws no MP; it greys and is refused when the purse cannot pay the
price at the pending boost, `Ot6SetzerRowGrey`, the same grey the confirm
reads). Jackpot greys for MP or once spent. One authority each:
`Ot6SetzerCost` (MP, flat, Ot6AbilityCost's `@slot` arm, which charges a Jackpot only at
the full boost) and `Ot6CoinGil`
(gil a throw or a hire; `Ot6CoinTotal` the whole action's, which the grey
reads). Tests: `battle_cointoss`, `battle_hiredhelp`, `battle_jackpot`,
`battle_setzergrey` (the purse's grey and refusal), `battle_gprain` (the
Coin Toss relic's GP Rain), `battle_hirerefund` (a hire past the last
body pays nothing) and `battle_passretarget` (a hire, roll or swing whose
body fell goes to another, and a toss re-splits over the survivors). The
coin suites throw in the battles that deal a
special-weak crowd (the engine's alive mask, so a petrified body is out)
and assert that a toss split and chipped; the other battles are fought out
by the route's fight driver with field care after, within a budget decoded
from the room's pool (the worst encounter-counter state's encounters to
the next crowd, 19 here, per crowd the throws need). `battle_jackpot`
holds every roll to the draw rule, and a bounded search over grave waits,
in-battle stands, Defends and the others' Fight or Defend (128 throws at
most, 99 of them distinct here; a throw redraws with p = 6.1%, so a miss is
0.939^99 = 0.2%) finds a draw whose early kill leaves a pass empty and one
that redraws past 251, or fails by name;
`battle_setzergrey` prices two, three and four throws against the purse,
step 5 from the purse step 4 left. Negative controls: the mutant ROMs
(`mutants5.py`, same-size edits for the savestate suite) and the no-edit
control built by the same pipeline, in
`build/attempts/wt/kit-setzer/m7/` (and `m8/`, battle_jackpot's revised search); the earlier `px13/m2/` set that
c9fccbd6 cites (the floor curve's mutants) was lost with px13's worktree
before it was copied, and the curve it tested is gone.

**The route's driver plays the table** (`Driver:setzerLine`, lib/ot6.lua;
#353), reading what an informed player would: Jackpot, when the bank holds
three, priced as the gamble it is, by a roll's expected landed damage (the
six faces after the shields' halving or the Broken double, capped at 9,999
and the target's HP), when the throw's two rolls are expected to land 4,000
on a target of 4,000 HP or more; Slot
at 3 BP in a random battle against two or more (a chosen triple); Coin
Toss when its revealed ¤ chips two or more bodies, with a toss a point up
to the most shields among them; Hired Help when the
target's revealed row holds a physical class his own Fight does not key,
with a hire a point up to the shields left (bank and purse allowing).
Gil is spent only above a 20,000 reserve, and only in event battles (a
boss, a monster chest): measured, Hired Help in the World of Balance grind
cost some 30,000 gil a run against the control and bought no fewer deaths
(route-wor-falcon.md 13.12), so random battles get his free Fight. `opts.setzer = false` is the
old behaviour (the control arm of the Falcon arc's labs,
route-wor-falcon.md 13.10).

---

## Sketches (join order, WoB)

- **Shadow — Assassin (piercing, thrown)**: Throw ✦ signature; smoke
  and exit tricks; divine **Assassinate** (built).  Its one gate is the
  rule's: an action of his boosted with all three points (no once-a-battle
  limit; a counterattack, Interceptor's, is no action of his and carries no
  divine).  Its effect: a hit of that action that breaks an enemy kills it
  outright on that hit -- break it and it dies -- and so does such a hit on
  an enemy someone else already Broke; a hit that breaks nothing is a hit.
  The break is what the divine does, not a condition on using it.  A boss
  is only Broken (owner ruling, #239).
  *Reason it is worth three points: a kill of any non-boss the party can
  break, every fourth turn.*  `battle_assassinate`.  Interceptor is a
  passive.
- **Setzer — Gambler/Merchant**: built; see "Setzer" above (#319).
- **Mog — Dancer (piercing: spear)**: the 8 Dances verbatim ✦,
  learned by dancing on each terrain ✦; divine **Water Rondo** (built,
  #380, `ot6_waterrondo.asm`), kept WoB-missable, vanilla-style: learned on
  the Lete River.  Its one gate is the full boost: under three points its row
  greys and the confirm buzzes (`Ot6DanceRowColor`, the draw's and the
  confirm's one verdict).  Three points buy what three points buy any dance
  (every step x8 for the battle, the start at 99 MP), and one thing more: it
  never stumbles.  Off its own terrain a dance start stumbles half the time
  (vanilla's roll in Cmd_13), and the party almost never fights on a river
  again; a three-point Water Rondo starts wherever it stands and turns the
  background to the river, so every later step matches (`Ot6DanceTerrain`).
  *Reason it is worth three points: El Nino and Plasma at x8 every turn for
  the rest of the battle, and the only dance a player can count on starting
  anywhere.*  The engine's picks spend no boost: a random Dance (Muddle,
  Charm, the Colosseum) draws from the known dances less Water Rondo
  (`Ot6DanceKnownRand`), and a Water Rondo start that still arrives under
  three points (a dance id left by an earlier start, a Gogo's Mimic he did
  not boost) stumbles, charging nothing, and clears the id.  A Gogo's Mimic
  reads Gogo's own pending boost, the Jackpot precedent.  `battle_waterrondo`.
- **Umaro — Berserker (bludgeoning: club, fists)**: see "Umaro" below
  (#380).

## Umaro — Berserker (bludgeoning: club, fists) (#380)

Umaro takes no orders: the game refuses him a command window by name, and
each turn his chooser (`_163b`) rolls one of four arms.  His kit is those
arms, not a list of eight, and what OT6 adds is what each one breaks and
what a full boost buys.

| Arm | When the roll can pick it | Chip | What the boost buys |
|---|---|---|---|
| Fight | always | his weapon's class: Bone Club or bare fists, bludgeoning | swings (`Ot6FightBoost`) |
| Charge | always | bludgeoning | the damage multiplier |
| Throw | with the Rage Ring | bludgeoning (an ally hurled as a club) | one more throw per point (`Ot6ThrowBoost`) |
| Storm | with the Blizzard Orb | ice, every enemy | the damage multiplier |
| **Storm** (divine) | a dump of all three points, relic or not | ice, every enemy | x8 |

- **Charge and Throw bludgeon** (`Ot6UmaroCharge`, `Ot6UmaroThrow`, the
  last writes before each runs ExecAttack).  Each loads the classless
  "battle" record and swings no weapon, so before #380 neither chipped
  anything (measured: class `$00` at every Charge pass,
  build/attempts/wt/v028-kits/umaro/r1_battle_umaro.out).  A body
  slammed or an ally hurled is a club's blow; Fight and Storm load their own
  class or element over it, as before.
- **The boost** is the retaliation dump (#236/#237, `Ot6UmaroRetaliate`): he
  banks a point a turn, and when he has been hurt since his last turn he
  spends the bank, up to three points, on his next action.
- **His divine: a dump of all three points is Storm.**  With three points
  pending at his chooser the roll is not made; he Storms, ice on every enemy
  at the boost's x8, with or without the Blizzard Orb.  Its one gate is the
  rule's full boost: only a dump spends three, and only being hurt makes him
  dump, so a Muddled, Charmed or Colosseum turn of his never reaches it
  without them.  *Reason: a full boost on a character the player cannot aim
  should buy the arm that needs no aim, and an ice key on a whole
  formation.*  He has no MP (mp-economy.md: Umaro 0), so the price is the
  three points alone.
- **On arrival** (Narshe, World of Ruin, v0.29, with Mog): bludgeoning on
  every arm but Storm, and ice on Storm, which his first full dump brings
  whatever relics he wears.  Where the route picks up the Blizzard Orb and
  the Rage Ring, and whether bludgeoning and ice are keys the party lacks in
  Narshe's mines and his cave, is the v0.29 route's to settle (the break rows
  there are not designed yet).

`battle_umaro` (a synthetic mechanism test: one seat of battle 67 staged as
him, as `battle_retaliate_umaro` does) checks the divine and the class.

## Curated kits (the Ochette/Hikari pair)

Both learn an open-ended collection and equip a curated subset, so the
player prunes the kit all game. Same model, different collection verbs:

- **Gau — Beast Tamer (piercing: fangs)**: `kit-gau.md`.
- **Strago — Scholar (bludgeoning: rod)**: Lores by observation ✦
  (Cyrus/Hikari). Aqua Rake free ✦; **Analyze** cheap and early ✦
  (full weakness reveal, the party's scouting tool). Learns every lore
  he sees cast, **equips 5**: his lores are one verb inside an 8-row
  kit that also carries Analyze and Aqua Rake, so his curation slice is
  smaller than Gau's kit-length list. Machinery: `OT6_LORELOAD`, the
  third loadout configurator (ot6_lore.asm / ot6_lore_page.asm).

- **Relm — Painter (special ¤: brush)**: Sketch ✦ signature (bug
  preserved ✦: it corrupts a save now and then, and that is canon —
  the full owner ruling is in `vanilla-destructive-bugs.md`).

## The World of Ruin: Espers and the magic-only tower (#384)

The World of Ruin adds no new lists to these kits; its twelve Espers are
the breadth layer.  Their spell lists, stat packages and the milestone
that grants each are in [magicite.md](magicite.md) ("World of Ruin
Espers", "When each stone arrives"): Palidor and Fenrir at v0.27, Terrato,
Tritoch and (probably) Ragnarok at v0.29, Starlet with Golem and ZoneSeek
at v0.30, Phoenix at v0.32, Bahamut at v0.34, Odin/Raiden and Alexandr at
v0.35, Crusader at v0.38.

One stop bears on every kit: the Fanatics' Tower (v0.30) is magic-only.
`battle_main.asm` @5354 turns Fight into Magic and removes every command
but Magic, Item and Mimic, so Blitz, SwdTech, Tools, Slot, Lore, Rage,
Sketch, Dance, Steal, Runic and Throw, and any divine that lives on one of
those rows, are off for its randoms, MagiMaster and the Holy Dragon.  A kit verb planned for those fights needs either a
Magic-row form or an explicit exception in that rewrite.
