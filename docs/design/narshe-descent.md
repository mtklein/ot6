# The Narshe descent — EDGAR's 57 MP, and the turns it threw away (#219)

Authored 2026-09-17 from `tools/tests/narshedescentlab.py` (the lab; its
docstring carries the policies), the v0.18 tree's failing
`build/states/narshe_battle.log`, and a 12-seed spread of
`gen_narshe_battle` over four policies — three cuts of the generator's own
fighter on the shipped ROM, and one on a pre-#219 control ROM assembled
from the same sources. Every number below is quoted from a retained log
under `build/lab/narshe-descent/` — the lab keeps every attempt, failures
included. `python3 tools/tests/narshedescentlab.py aggregate control priced
ration preprice --seeds 0,5,10,15,20,25,30,35,40,45,50,55` prints them all;
`build/lab/narshe-descent/aggregate.txt` is that output,
`build/lab/narshe-descent/sweep.txt` the run's own,
and `build/lab/narshe-descent/tables-seed00.txt` the four per-battle tables
seed 0 produced.

## What happened in the build

`narshe_battle` (gen_narshe_battle) stopped generating after #219 landed:

```
[descent] PARTY WIPED in battle #14 at f63718 (started f60291, tier 3) -- party [0/306 0/315 0/310 0/0]
[descent] no attempt survived of 3 tries
```

The generator has not changed since (`git log -- tools/tests/gen_narshe_battle.lua`),
and it regenerated in the build before. The lab's `control` policy — the
generator verbatim with two read-only CPU exec observers added — reproduces
that verdict frame for frame on seed 0, which is what says the observers
change nothing (`build/lab/narshe-descent/control/seed00.log`):

```
[ndlab] [act] f10213 b3 slot1 char4 Tools($09) atk=$AA bp=2 rev=2 plan=2 mp 7->7 spent=0 dmg=0 took=0 fizzle=1
```

That one line is the whole failure. EDGAR is at **7 MP**, he spends **2
banked BP** on a boost, the command reaches `ExecCmd` — and it takes no MP
and does no damage. The turn and the pips are gone.

## Where the resources actually go

`gen_narshe_battle` does not use the lib's fight driver. It has its own
fighter (`mkFighter` / `seqFor`), a dozen lines long, which builds a button
sequence from the acting character and the banked BP. As it stood when #219
landed, in full:

    boost prefix        bank to 2, dump up to 3
    EDGAR (4), tier 2+  down A A A   Tools -> AutoCrossbow
    CELES (6), tier 3+  down A A     Runic
    SABIN (5), tier 3+  down A A A   Blitz -> Pummel
    everyone else       A A          Fight

So **#219's driver-side fix never reached this segment.** The commit that
taught the driver to price a boost (`6e097729`) touched `lib/ot6.lua`,
`battle_boostprice.lua` and `gen_sfigaro.lua`. This generator reads none of
them. There are no `stepped down` lines in its log because `M.affordBoost`
was never called.

### The party going in

`[ndlab] [party descent start]`, at the defense-live checkpoint, identical
on every seed (`control/seed00.log`):

```
c0=L12 271/271 hp 87/87 mp back | c1=L13 314/314 hp 88/88 mp front | c2=L14 358/358 hp 56/96 mp front
c4=L13 315/315 hp 57/87 mp back | c5=L14 363/363 hp 27/94 mp front | c6=L13 310/310 hp 96/96 mp back
c11=L15 394/394 hp 95/111 mp front
```

Party 1 walks the descent: TERRA (c0), EDGAR (c4), CELES (c6). **Only one
of the three has a costed verb**, and he carries **57 of 87 MP** into it.
TERRA and CELES Fight (and CELES Runics, for nothing measurable — 20 turns,
0 damage, 0 MP, on `control/seed00.log`), so their pools sit untouched:
`97/97` and `96/96` at the corridor care stop, on every seed of every
policy.

### AutoCrossbow's ladder

Base 4 MP (`Ot6AbilityCostTbl`, `ot6_boost.asm:1544`), and
`min(99, floor(base * 2.5^boost + 0.5))` on top:

| boost | price | damage |
|---|---|---|
| 0 | 4 | x1 |
| 1 | 10 | x2 |
| 2 | **25** | x4 |
| 3 | 63 | x8 |

The fighter asks for boost 2 the moment the bank reaches 2 pips, which is
every third turn. **57 MP is two of those.**

### Per battle, control seed 0

`python3 tools/tests/narshedescentlab.py table build/lab/narshe-descent/control/seed00.log`
(`mp_sp` = MP the party spent in the fight, `fizz` = turns under a costed
verb that neither spent MP nor moved a monster, `mp_end` = TERRA, EDGAR,
CELES at the last live frame):

| at | # | formation | frames | mp_sp | hp_lost | turns | fizz | mp_end |
|---|---|---|---|---|---|---|---|---|
| 1 | 1 | Bounty Man + Trooper x2 | 1961 | **25** | 101 | 4 | 0 | 97,**32**,96 |
| 1 | 2 | Trooper x4 | 2058 | **25** | 99 | 4 | 0 | 97,**7**,96 |
| 1 | 3 | HeavyArmor + Trooper x2 | **7985** | 0 | **391** | **21** | 3 | 97,7,96 |
| 1 | 4 | Fidor + Trooper | **4837** | 0 | **351** | 11 | 1 | 97,7,96 |
| 2 | 5 | Bounty Man + Trooper x2 | 2266 | 29 | 251 | 5 | 0 | 97,28,96 |
| 2 | 6 | Trooper x4 | 2082 | 25 | 162 | 5 | 0 | 97,3,96 |
| 2 | 7 | HeavyArmor + Trooper x2 | 7513 | 0 | 318 | 27 | 3 | 97,3,96 |
| 2 | 8 | Fidor + Trooper | 3626 | 0 | 163 | 11 | 2 | 97,3,96 |
| 2 | 9 | HeavyArmor + Trooper x2 | 3320 | 0 | 256 | 7 | 1 | 97,3,96 |
| 3 | 10-14 | (the same five again) | | | | | | |

Read the first two rows and the third. Battle 1 and battle 2 each cost 25
MP and each ended in **one** EDGAR turn:

```
[ndlab] [act] f5153 b1 slot1 char4 Tools($09) atk=$AA bp=2 rev=2 plan=2 mp 57->32 spent=25 dmg=711
[ndlab] [act] f7897 b2 slot1 char4 Tools($09) atk=$AA bp=2 rev=2 plan=2 mp 32->7  spent=25 dmg=815
```

711 and 815 damage, whole formations at once. The feature works, and the
qualification's own log says the same about its battle 1.

Battle 3 is the same three bodies as battle 1 plus a HeavyArmor, and it
takes **21 turns and 7,985 frames**, because from here EDGAR is at 7 MP and
every boosted crossbow he orders does this:

```
[ndlab] [act] f10213 b3 ... Tools($09) atk=$AA bp=2 rev=2 mp 7->7  spent=0 dmg=0   fizzle=1
[ndlab] [act] f11484 b3 ... Fight($00) atk=$FF bp=0 rev=0 mp 7->7  spent=0 dmg=28
[ndlab] [act] f13198 b3 ... Tools($09) atk=$AA bp=2 rev=2 mp 7->7  spent=0 dmg=0   fizzle=1
[ndlab] [act] f15366 b3 ... Tools($09) atk=$AA bp=2 rev=2 mp 7->7  spent=0 dmg=0   fizzle=1
```

**The unboosted crossbow costs 4 and he has 7.** It was affordable on every
one of those turns. Over the whole run:

| char | verb | turns | mp | damage | fizzles | dmg/turn |
|---|---|---|---|---|---|---|
| TERRA | Fight | 46 | 0 | 2600 | 0 | 56.5 |
| EDGAR | Fight | 35 | 0 | 2298 | 0 | 65.7 |
| CELES | Fight | 25 | 0 | 1402 | 0 | 56.1 |
| **EDGAR** | **Tools** | **24** | **158** | **4448** | **16** | **185.3** |
| CELES | Runic | 20 | 0 | 0 | 0 | 0.0 |

**16 of EDGAR's 24 tool turns did nothing at all.** He is the party's only
source of more than ~60 damage a turn, and two thirds of the turns he spent
being that were thrown away.

### Why the ROM let that happen

**Fixed in v0.19; this section records the measurement that led to the
fix.** An unaffordable kit row is now refused at the confirm
(`Ot6KitConfirmMP`, `mp-economy.md` ruling 2), so the sixteen dead turns
below are no longer reachable: the window buzzes and stays open and the
turn is still the player's. What follows is what the ROM did when this lab
ran.

It was not an oversight — a documented scope decision in #219 itself
(`ff6/src/battle/ot6_boost.asm`, `Ot6AbilityGrey`'s header, since
rewritten):

> Scope: this ports the visual half of magic's affordance (grey the row).
> The other half, magic's `lda $2093,x / bmi` at the A-button that no-ops
> the confirm on a disabled spell ... would live in the tools/blitz confirm
> (UpdateMenuState_30 @8809, btlgfx_main.asm:20668). That is btlgfx (bank
> C1), a stock object linked into both the shipped and the nomp ROM ... So
> the block stays where it is and costs no bytes: CalcAttackEffect's
> universal insufficient-MP fizzle refuses the cast at execution, and the
> grey tells the player before they get there.

So for Tools and Blitz, an unaffordable row is **greyed but still
selectable**, and the refusal happens at `battle_main.asm:8409` — after the
turn and the pips are spent. That is fine for a person, who reads the grey.
It is fatal to a fighter that does not.

(`mp-economy.md` ruling 2 says "greyed **and refused**". For the kit
windows only the grey shipped; the refusal was the execution-time fizzle.
The doc and the ROM disagreed about *where*. The owner's call was to make
the ROM match the doc, and v0.19 does: see ruling 2 and
`tools/tests/battle_kitrefuse.lua`.)

### The one refill point

There is no shop, no inn and no save point between the staging tile and
KEFKA, and nothing in the bag the harness will spend on MP (below). The
descent's only MP refill is a **level-up**: `DoLevelUp` ends with
`jsl Ot6LevelUpHeal  ; ot6: refill current HP/MP to the new maxima`
(`battle_main.asm:16258`), which puts current HP and MP back to the new
maxima. It is visible once in `ration/seed00.log` — EDGAR crosses the last
collision's victory screen at `mp 9` and enters KEFKA at `mp 97` — and it
is not something a route can plan around: it lands when the XP lands.

## The spread

Twelve `OT6_SEED_SHIFT` values, 0 through 55 in steps of 5 — idle frames the
segment runner inserts at the boot point, the beat a player pauses before
walking on — with the lib's retries **off** (`OT6_RETRIES=1`), so every seed
reports its first try. Nothing is published to `build/states`.

Two pairs of seeds draw the same first battle (20/30 share RNG key `be40`,
40/50 share `be90`; the `first battle` column of `aggregate.txt`), so the
twelve runs are **ten distinct samples** per policy.

The four policies, all on the same fixture and the same 12 shifts:

- **control** — the fighter as it stood when #219 landed: the bank's whole
  boost, planned without asking what it costs.
- **priced** — the fighter asks `H.affordBoost` (the lib's copy of
  `Ot6BoostPriceFor`) and steps the boost down to what the pool covers,
  dropping to Fight when it cannot pay even the base.
- **ration** — priced, and one turn may spend at most a quarter of the
  caster's **maximum** MP. This is what the tree now ships.
- **preprice** — `control`'s fighter on a control ROM assembled from the
  same sources with `-D OT6_BOOST_PRICE=0`, which makes `Ot6BoostPriceFor`
  return the base at every level: every base price still charged, a boost
  free again. **The pre-#219 economy**, and the "before".

### Results

```
policy      n  pass  wipes  fights  turns  fizzles fizz/run    frames
control    12     5     22     144   1491      130     10.8     38129
priced     12     8     15     139   1411        0      0.0     37787
ration     12    11      3      88    835        0      0.0     30806
preprice   12    12      1      89    713        0      0.0     28605
```

(`wipes` counts `PARTY WIPED` — a lost descent reloaded from the
defense-live checkpoint, the ladder the generator already carries. `frames`
is the mean over passing runs. A run FAILs when all three attempts wipe.)

Per seed, pass/fail and wipes (`aggregate.txt` has frames and RNG keys):

| seed | key | control | priced | ration | preprice |
|---|---|---|---|---|---|
| 0 | beC0 | **FAIL** (3) | PASS | PASS | PASS |
| 5 | beD0 | PASS | PASS (1 wipe) | PASS | PASS |
| 10 | beE0 | PASS | PASS | PASS | PASS |
| 15 | beF0 | **FAIL** (3) | PASS | PASS | PASS |
| 20 | be40 | PASS | **FAIL** (3) | PASS | PASS |
| 25 | be30 | **FAIL** (3) | PASS | **FAIL** (3) | PASS |
| 30 | be40 | PASS | **FAIL** (3) | PASS | PASS |
| 35 | be50 | **FAIL** (3) | PASS (1 wipe) | PASS | PASS (1 wipe) |
| 40 | be90 | **FAIL** (3) | **FAIL** (3) | PASS | PASS |
| 45 | be80 | **FAIL** (3) | PASS (1 wipe) | PASS | PASS |
| 50 | be90 | **FAIL** (3) | **FAIL** (3) | PASS | PASS |
| 55 | beAC | PASS | PASS | PASS | PASS |

By distinct sample: control **4 of 10**, priced **8 of 10**, ration **9 of
10**, preprice **10 of 10**.

## Was it attrition?

**Half.** The hypothesis was cumulative resource attrition across a
14-battle descent. The numbers refute the "cumulative" and confirm the
"resource".

- It is **not** gradual. EDGAR's pool is gone after **two battles of
  seven**, both in the first 8,000 frames, and it never moves again. The 14
  battles in the failing log are the same five formations replayed by the
  three-attempt ladder, not fourteen encounters draining a pool.
- It is **not** general. Two of the three walkers spend no MP at all in
  `control` — TERRA and CELES are at `97/97` and `96/96` the whole way, and
  CELES's twenty Runic turns cost nothing and do nothing.
- The decisive part is **not the economy at all but the fighter**. `priced`
  runs on the identical ROM with the identical prices and takes fizzles
  from 130 to 0 and passes from 4/10 to 8/10 — the same 57 MP, spent on
  turns that land.
- What **is** attrition is the residue: even priced, 57 MP buys two boost-2
  crossbows and one unboosted, and from battle 3 EDGAR is a plain fighter
  at **55 dmg/turn** against Tools' **457** (`priced/seed20.log`). That is
  what the last two failures are, and what `ration` answers by buying five
  x2 turns instead of two x4 ones.

The size of the economy change, measured on the same fixture and the same
twelve shifts: **pre-#219 the same 57 MP bought fourteen boosted crossbows
at 4 MP each — more than the descent has EDGAR turns for. Today it buys
two.** `preprice/seed00.log` spends 4 MP a fight — `57, 53, 49, 45, 41, 33,
25` across the seven, eight boosted crossbows at **448 damage a turn** and
not one fizzle; `control/seed00.log` spends 25 a fight and is at 7/87 after
two.

## Two things this lab found on the way

**1. The class is generator-local fighters.** Fifteen generators press R
with a fighter of their own and never mention `affordBoost`; eight of those
also name a costed ability by name:

```sh
for f in $(grep -ln '"r"' tools/tests/gen_*.lua); do
  grep -q affordBoost "$f" && continue
  grep -qiE "AutoCrossbow|Pummel|AuraBolt|Bio Blaster|NoiseBlaster|Dispatch" "$f" || continue
  basename "$f"
done
```

```
gen_kefka_won.lua  gen_opera7_blackjack.lua  gen_rapids.lua  gen_sabin_train.lua
gen_scenario.lua   gen_sabin_gau.lua         gen_vargas.lua  gen_zozo4_dadaluma.lua
```

They pass today because their pools last the fights they play. Narshe is
simply the longest stretch with no refill point and the smallest pool. That
is its own issue, not this one.

**2. The bag has MP in it and nothing in the harness knows.**
`H.fieldCare`'s vocabulary is Tonic, Potion, Fenix Down, Antidote, Soft,
Remedy — six items, and its roster line prints exactly those six
(`ot6_field.lua:3083`). At the descent's one care stop it sees
`c4 292/315 hp 32/87 mp` and does nothing about the MP, because it has no
MP restorative at all. The bag at that moment (decoded from
`build/states/narshe_battle.mss`) holds **2 Elixirs** — "Recovers HP/MP to
100%", an ordinary usable item — plus 3 Sleeping Bags and 2 Tents, which
are **save-point only** (`item.asm:@84e2/@84f8` branch on `w0201` bit 7 and
grey otherwise) and so genuinely unusable mid-descent. There is no Tincture
in the bag, and the two item shops whose ids the route asserts do not stock
one (shop 8, South Figaro, `gen_sfigaro.lua:657`; shop 15, Narshe,
`gen_narshe_mission.lua:470`). **The Figaro Castle item shop does.** Its
counter (`event_main.asm:_ca67a2`) opens shop 4, 47 or 64 on the `$00A4` /
`$0048` switches, and all three stock **Tincture** — shop 4 is Tonic,
Tincture, Antidote, Soft, Echo Screen, Fenix Down, Sleeping Bag, Tent
(`ff6/src/menu/shop_prop.dat`). `gen_edgar.lua:366` stops at that counter
and buys 30 Tonics.

## Recommendation

**Price the boost in `gen_narshe_battle`'s own fighter, and ration it.**
That is the change this branch lands — sixteen lines inside `seqFor`, no
new machinery, using `M.affordBoost` and `M.abilityCost` (the latter
promoted from a private local in the fight driver to the module, so a
generator with its own fighter reaches the same numbers the ROM does).
Measured over the same twelve shifts:

| | passes | distinct samples | wipes | fizzled turns | fights | party turns | mean frames |
|---|---|---|---|---|---|---|---|
| before (`control`) | 5 / 12 | 4 / 10 | 22 | 130 | 144 | 1491 | 38,129 |
| after (`ration`) | **11 / 12** | **9 / 10** | **3** | **0** | **88** | **835** | **30,806** |
| for reference, pre-#219 (`preprice`) | 12 / 12 | 10 / 10 | 1 | 0 | 89 | 713 | 28,605 |

The shipped fighter now measures within one sample, one fight and 2,200
frames of the economy it had before #219 — on the #219 ROM, at the #219
prices.

The generate edge itself, run unmodified from the same tracked
`reunion_ready` fixture with the graph's own retry ladder and nothing
published (`build/lab/narshe-descent/shipped/narshe_battle.log`):

```
[ot6] PASS (frame 33361) attempts=1/3
```

First try, and the same frame as the lab's `ration` seed 0 — which is what
says the observers do not change the run in either direction. `build/lab/narshe-descent/ration.lua` is the shipped generator
verbatim plus the observers, and the lab's `derive()` locates the body it
measures by its two ends, so an edit to either end fails the derivation
rather than silently measuring something else.

The one remaining failure is **seed 25**, and it is not an MP failure:
EDGAR still holds 27/87 and the ration is working (10 MP a turn, tools into
battle 4), and attempt 2's battle 7 — four Troopers — takes **766 HP** off
the party in nine turns (`ration/seed25.log`). That is an ordinary bad
draw of the kind "lost battles are normal" covers, and the segment's own
three-attempt ladder is what it is for.

### Options not taken, and what they would cost

- **Carry MP.** Teach `H.fieldCare` an MP arm and the descent's care stop
  would drink the two Elixirs already in the bag: +174 MP for EDGAR, six
  more boost-2 crossbows, at the cost of two Elixirs the route has no other
  claim on. Buying Tinctures at Figaro is the durable version and is dear:
  **1500 gil for 50 MP** (`item_prop_en.dat` +$1C), two of them against the
  ~5,338 gil that stop has, and `gen_edgar.lua` already records that
  overspending there starves South Figaro's own targets. Not measured here;
  it is a lib change plus a route change and belongs to whoever owns the
  supply curve.
- **Levels or gear.** Not measured. The party walks in at L12-L13 with the
  rows already set back for all three, which is the preparation this
  segment already makes.
- **The escalation rate.** Not changed, and not proposed: 2.5x and the 99
  cap are the owner's locked design. The measurement to hand him is only
  this — **at boost 2 a Tool costs 6.25x its base, and a WoB L13 EDGAR's 87
  MP buys two of them for a seven-battle segment with no refill point.** If
  two is the intent, the fighter change above is the whole answer and the
  numbers say it is sufficient. If it is not, the levers this lab can see
  are the pool, the supply, and the number of refill points on the route —
  not the rate.
- **Refuse an unaffordable kit row at the confirm.** ~~Owner's call~~ —
  **taken, and landed in v0.19.** The gate went exactly where
  `Ot6AbilityGrey`'s header said it would (`UpdateMenuState_30 @8809`,
  plus the dance confirm at @85f0), and the objection died with the build
  graph rather than with the rule: btlgfx is now assembled once per flag,
  the gates sit inside `.if OT6_MP_COSTS`, and the nomp ROM is still the
  same bytes. The grey now means what `mp-economy.md` ruling 2 says it
  means, and this segment's failure is impossible for a blind fighter as
  well as for a person. `tools/tests/battle_kitrefuse.lua`.

## The lab

`tools/tests/narshedescentlab.py`. Each policy is a derived copy of
`gen_narshe_battle.lua` — the generator verbatim, plus two read-only CPU
exec observers and one settled per-battle line, plus the policy's own
`seqFor` body — run once per seed under `run.sh` with retries off and
`OT6_SEED_SHIFT` idle frames at the boot point. Every substitution asserts
it matched exactly once.

The observers are `fcalcovelab`'s in shape: `ExecCmd@battle_code` runs with
X = the acting entity's offset and `$b5`/`$b6` the command and attack after
queue-time folding, and parks the actor's MP (`$3c08+x`), banked BP
(`$3e9c+x`), revealed boost (`$3e9d+x`) and every monster's HP;
`SaveForMimic` runs once the command has resolved. The fizzle is visible
because the insufficient-MP path aborts *inside* `ExecCmd` and returns to
`ExecAction`'s own `jsr SaveForMimic` (`battle_main.asm:277-278`), so the
observer still fires and reports the same MP and no damage. They read, they
never write.

`narshedescentlab.py rom` builds the pre-#219 control: the battle module
reassembled with `-D OT6_BOOST_PRICE=0` and linked through the graph's own
`link_rom.sh` recipe against the graph's own objects, checked byte-distinct
from `build/ot6.sfc`. The run arm points **both** `OT6_ROM` and the new
`OT6_DBG` at it — the flag adds a byte inside `Ot6BoostPriceFor` and so
moves every label after it, and an observer hooked at the shipped ROM's
`SaveForMimic` would be hooked at nothing. `OT6_BOOST_PRICE` is a
measurement control, like `OT6_MP_COSTS` beside it; nothing in the ninja
graph ships it.

Per-battle attribution is action-granular with one frame of slack at each
boundary, the blind spot `balance-metrics.md` already documents: MP and
monster HP are read at `ExecCmd` and again at `SaveForMimic`, so damage
belongs to the turn, while HP *lost* is billed to the fight (every drop
between consecutive samples, seeded from the settled fight-start line),
because the monsters' rounds land between party turns.
