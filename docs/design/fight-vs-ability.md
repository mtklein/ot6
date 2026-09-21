# Fight and the ability at #219's prices — what the MP still buys

Authored 2026-09-18 from `tools/tests/fightvsabilitylab.py` (the lab; its
docstring carries the policies and the observers), a static cross-reference
of the route's own gear against the World of Balance's own bodies, and a
four-shape, seven-policy, four-seed spread of the shipped party balance
instrument. Every number below is quoted from a retained log under
`build/lab/fight-vs-ability/` — the lab keeps every attempt, failures and
superseded spreads included.
`python3 tools/tests/fightvsabilitylab.py aggregate` prints the
head-to-head, `... mechanic` the swing ladder and `... reach` the static
arm; `build/lab/fight-vs-ability/aggregate.txt`,
`build/lab/fight-vs-ability/mechanic.txt` and
`build/lab/fight-vs-ability/reach.txt` are those three outputs.

**Nothing here changes the ROM.** The 2.5x rate, the 99 cap and the Fight
exemption are the owner's design, and he has settled them for this
release: "we'll stick with this 2.5x cost scaling for abilities for this
release, and we'll check through human playtesting how the balance feels."
So this document carries no proposal. It carries the measurements, and one
page of what to expect at the controls.

**Boosted Fight is supposed to be good at breaking and at clearing random
fights quickly** (owner, 2026-09-18: "the intention is that it's useful for
breaking and for wiping out random fights quickly"). Everywhere below that
it wins on shields or on turns, that is the feature working, and it is
reported as confirmation. The question this lab was built to answer is the
narrow one that remains: **where does a boosted ability still earn its MP?**

## The short answer

Five places, all measured, and one that is honestly nowhere:

| the ability's job | does it still earn the MP | where |
|---|---|---|
| a shield class no weapon in the party reaches | **yes, and it is the only key** | 7 of 32 WoB bodies; Flan and Rhinox measured |
| a status a weapon cannot answer | **yes, and it is the only answer** | Vanish, Zozo's Gabbldegak |
| an element the weapon delivers backwards | **yes** | Rhinox absorbs bolt; LOCKE's blade heals it |
| whole-group damage | **yes** | Bio Blaster, 2.53 chips and 296 damage in one 8-MP turn |
| magnitude on a body with real HP | **yes, and by a factor of sixty** | Pummel 800 for 4 MP against a Fight's 13 |
| healing | not measured here | Mantra is L23; no routed party carries it in the stretches covered |
| breaking a class the weapon already reaches | **no** | boosted Fight does it free and faster — intended |
| clearing a random the party can already chip | **no** | boosted Fight does it free and faster — intended |

And one thing the prices did not do, which is the load-bearing finding:
**#219 priced the boost, not the ability.** Every number in the left column
above is bought at boost 0, at 4 to 8 MP, unchanged from before #219. In
this whole corpus — 212 costed turns under the unboosted ability policy —
the ability's price never moved, and it still out-damaged a Fight by up to
sixty to one.

## The ROM these numbers were taken on

`build/ot6.sfc` built from this branch's base, `a1007a97` ("Merge #228: the
Narshe descent's own fighter prices and rations its boost"). Two things
landed on `main` while the spread ran, and neither would have changed one
action of it:

- **an unaffordable kit row is refused at the confirm** (`236532d2`) rather
  than committed and fizzled at execution. Nothing in this corpus was ever
  unaffordable: across all 97 head-to-head logs, **824 costed turns and not
  one of them failed to spend MP**
  (`grep 'fva-act' build/lab/fight-vs-ability/*/*.log | grep -E 'Blitz|Tools|Magic|Steal' | grep -c 'spent=0$'` → 0
  in each of the four fixture directories). The pools here are WoB pools of
  77 to 243 MP against 4-to-21-MP rows; the refusal has nothing to refuse.
- **every fighter prices a boost before planning one**, through
  `H.boostPlan` (`cc25e69b`). The lab's fighter is `bal_party.lua`'s, which
  does not call it; with no unaffordable plan anywhere in the corpus there
  is nothing for it to step down. The prices actually charged are
  `mp-economy.md`'s table read back off the runs, exactly:

```
== zozo_arrival, every costed turn, (pending boost, MP charged) ==
 102 rev=0 spent=4        Pummel / AutoCrossbow, base
  48 rev=0 spent=5        Ice, base
  36 rev=0 spent=8        Bio Blaster, base
  20 rev=1 spent=10       Pummel / AutoCrossbow at boost 1 (4 x 2.5)
  24 rev=1 spent=21       Ice at boost 1 -- the FOLD to Ice 2, at Ice 2's
                          own vanilla 21, not 2.5x
   4 rev=3 spent=63       Pummel at boost 3 (4 x 15.625)
```

A re-run on today's `main` would move frame counts (the library's observers
moved and the fighters changed), not these prices and not the mechanic.

## 1. The mechanic, confirmed in play rather than read off the comment

`Ot6FightBoost` (`ff6/src/battle/ot6_boost.asm:402`) adds **+2 swings per
pending BP**, and its header reads:

> swings alternate hands and empty-hand swings whiff, so +2 swings per bp =
> +1 real hit for a one-weapon character, and a genji-glove pair swings
> both hands again, doubling the bonus as it doubles everything else.

The ROM path underneath it: `FightAttack` (`battle_main.asm:3519-3527`)
writes `$3a70` = **1** (7 with an Offering) and calls the boost; the
multi-attack loop runs **`$3a70` + 1 passes** (`dec $3a70 / bmi`,
`battle_main.asm:8392`); and each pass hands `_magicpunch` the carry out of
`lda $3a70 / inc / lsr` (`:8285`), which `ror $b6 / bpl / inx` (`:7156`)
turns into the hand. So the passes alternate hands whether or not the off
hand holds anything, and an empty hand's battle power is 0, which takes the
"jump if no damage" exit at `:8290`.

Measured, not argued. The observers count one exec of `Ot6WeaponClass` per
hand per swing and one exec of `Ot6HitJoin` per landed hit on a monster, per
action, over 24 runs of `fight0`..`fight3` on three fixtures
(`build/lab/fight-vs-ability/mechanic.txt`; the per-run logs are under
`build/lab/fight-vs-ability/*-mech/`):

| who | hands | BP | n | `$3a70` | passes | swings | landed hits | histogram |
|---|---|---|---|---|---|---|---|---|
| CELES | 1 | 0 | 432 | 1.00 | 2.00 | 2.00 | 0 or **1** | `0:62,1:370` |
| CELES | 1 | 1 | 86 | 1.00 | 4.00 | 4.00 | 0 or **2** | `0:21,2:65` |
| CELES | 1 | 2 | 41 | 1.00 | 6.00 | 6.00 | 0 or **3** | `0:2,3:39` |
| CELES | 1 | 3 | 30 | 1.00 | 8.00 | 8.00 | 0 or **4** | `0:3,4:27` |
| EDGAR | 1 | 0..3 | 497 | 1.00 | 2/4/6/8 | 2/4/6/8 | 0 or **1/2/3/4** | `0:62,1:309` … `0:4,4:21` |
| SABIN | 1 | 0..3 | 561 | 1.00 | 2/4/6/8 | 2/4/6/8 | 0 or **1/2/3/4** | `0:64,1:348` … `0:3,4:26` |
| LOCKE (Genji pair) | 2 | 0 | 456 | 1.00 | 2.00 | 2.00 | **2** | `0:63,2:341,3:52` |
| LOCKE (Genji pair) | 2 | 1 | 88 | 1.00 | 4.00 | 4.00 | **4** | `0:19,4:44,5:23,6:2` |
| LOCKE (Genji pair) | 2 | 2 | 43 | 1.00 | 6.00 | 6.00 | **6** | `0:2,6:21,7:17,8:3` |
| LOCKE (Genji pair) | 2 | 3 | 24 | 1.00 | 8.00 | 8.00 | **8** | `0:3,8:6,9:13,10:2` |

The header is right and the histogram is the proof: a one-weapon character
lands **1 + BP** real hits and never a value between, because the whiffing
half is the empty hand, not a die roll. Two quoted actions, one of each
shape:

```
[fva-act] n=9 f2515 slot=1 char=06 Fight($00) atk=$FF bp=3 rev=3 hands=1
  live=1 aim=1 pre=1 frev=3 fb1=0 cnt=7 passes=8 swings=8 hits=4 dmg=134
   -- build/lab/fight-vs-ability/zozo_arrival-mech/fight3_j00.log

[fva-act] n=6 f10815 slot=2 char=01 Fight($00) atk=$FF bp=2 rev=2 hands=2
  live=3 aim=1 pre=1 frev=2 fb1=0 cnt=5 passes=6 swings=6 hits=6 dmg=142
   -- build/lab/fight-vs-ability/ifrit_entry-mech/fight2_j00.log
```

Eight swings, four hits, one weapon. Six swings, six hits, a pair.

### The one thing the library disagreed with the ROM about — fixed in #235

`M.fightSwings` returned `1 + 2*boost` for a one-weapon character where
the ROM lands `1 + boost`. It has been replaced by two functions that say
which number they are — `M.fightPasses(boost)` for the swings the loop
runs and `M.fightHits(hands, boost)` for the hits that land — and both
callers (`fightChips`, and the `hits` the press rule prices a turn with)
now take the landed count. The ladder is no longer a constant anybody can
write down: `battle_healpolicy.lua` derives it from this ROM's own
`FightAttack` and `Ot6FightBoost`, and `battle_hits.lua` counts the swings
and the landed hits of a real 2-BP Fight and checks the model against
them.

The same measurement turned up a second doubling on the same road.
`M.isWeapon($FF)` answered **true**: `$FF` is the empty-slot sentinel and
not an item id, but `ItemProp` has thirty bytes at that index and the type
byte there reads `$01`, "weapon, record in use". This lab's own
`fvaArmed` had to guard it locally; the driver's `handsOf` did not, so
every character with a bare off hand was counted as a Genji pair. It is
guarded in `M.isWeapon` now, with both halves pinned.

**What the error actually cost, measured** (`tools/tests/fightswingslab.py`,
logs under `build/lab/fight-swings/`). The arithmetic first: running both
models through the shipped `keyBoost` over every (shields, bank, hands)
a WoB gauge presents, the chosen boost depth moves in **four** cells, all
one-weapon — need 3 at bank 2 or 3 (1 → 2 pips), need 4 at bank 3 (2 → 3),
need 5 at bank 3 (2 → 3) — and the old model claimed a break the ROM
cannot land in six more. The pair branch never moves; it was right.

So the earlier draft of this section overstated one thing and understated
another. At **six** shields with a full bank the two models pick the same
depth (3): what was wrong there was the *claim*, not the pip count. The
depth moves at three, four and five shields — including as a six-shield
gauge is chipped down past them, which is how it reaches Ifrit and Shiva
after all.

In play, on battle 70 over a twelve-seed spread, eleven of twelve fights
are frame-for-frame identical and one is not. At seed `$84` the driver
planned `Fight at 2 BP lands 5 chips on 4 shields: the smallest boost that
breaks this turn`, landed **three** hits, and the gauge went 4 → 1: the
break did not land, and the fight ran 43 turns and 13,871 frames. With the
model corrected the same turn planned `Fight at 3 BP lands 4 chips on 4
shields`, landed four, the gauge went 4 → 0, and the fight ended in 31
turns and 10,114 frames. Across the corpus, keyed claims judged against
the gauge they named: 8 kept and 1 broken before, 8 kept and 0 broken
after. Every seed won in both arms.

### What a landed hit is worth

Three multipliers decide whether the extra hits matter
(`ff6/src/battle/ot6_break.asm`):

- **shielded, off-weakness: x0.5.** `Ot6ShieldedMulW` is `$0008`, 8/16ths,
  applied per hit while the gauge stands.
- **element-weak: x2 then x0.5, so about x1** — "the chip is the real
  payoff", as the source says.
- **broken: x2**, and the broken timer denies the body its turns.
- **chips are per landed hit**, once for the weapon's class and once for
  its element, and the class chip collects no damage bonus of its own.

So the boosted Fight's extra swings buy chips first and damage second, and
against a body whose class and element the weapon does not carry they buy
**neither**. That is the whole of section 2.

## 2. Where the ability still earns its MP

### 2.1 A shield class no weapon in the party can reach

This is the sharpest one and it is structural, not situational. In all four
stretch fixtures the static arm reads, **the routed party wields no
bludgeoning weapon at all**: SABIN's MetalKnuckle is a *slashing* weapon
(`weapon-classes.md`: "claws are how the monk buys into a second class"),
and LOCKE, EDGAR, CELES and TERRA carry swords, spears and daggers.
`Ot6SkillClassTbl` gives Pummel, Suplex and Bum Rush the bludgeoning class
whatever is equipped, so for that whole span the class exists in the party
only as an ability.

(The first bludgeoning weapon the route actually carries is STRAGO's Ice
Rod, at `esper_mtn_save` — a stretch `check_break_reach.py`'s areas do not
cover, so it is outside this arm. Whoever extends the areas to Esper
Mountain should expect section 2.1 to get smaller there: map 375's Slurm
and Adamanchyt are both bludgeon-keyed, and his rod is the key.)

Cross-referencing each stretch's own fixture gear and bag against the
formations its maps and event battles actually roll — the areas and the
table parsers are `tools/check_break_reach.py`'s, so this arm and the
shipped linter cannot read the tables differently
(`build/lab/fight-vs-ability/reach.txt`):

```
  bodies examined                      32
  a routed Fight chips it              25
  ONLY a costed ability chips it        7
  nothing in the party chips it         0
  no gauge to chip                      0
```

The seven, with the key that opens them:

| body | shields | class key | element key | the only key the party holds |
|---|---|---|---|---|
| ProtoArmor `$165` | 2 | bludg | bolt | SABIN Pummel 4 MP / Suplex 13 MP |
| Flan `$047` | 2 | bludg | fire | Pummel; Suplex; Fire Dance 17 MP; AutoCrossbow 4 MP (fire) |
| Trapper `$02D` | 2 | bludg | bolt\|water | Pummel; Suplex |
| Rhinox `$075` | 2 | bludg | — | Pummel; Suplex |
| Mag Roader `$006` | 2 | bludg | fire | Pummel; Suplex; Fire Dance; AutoCrossbow |
| Mag Roader `$0AF` | 2 | bludg | ice | Pummel; Suplex |
| HadesGigas `$053` | 2 | bludg | poison | EDGAR Bio Blaster 8 MP; Pummel; Suplex |

Every one is bludgeon-keyed, and **SABIN's Pummel at 4 MP is on every
row**. Measured against Flan, on the whole `ifrit_entry` spread
(`build/lab/fight-vs-ability/ifrit_entry/`, 28 logs, tabulated in
`build/lab/fight-vs-ability/mechanic-ifrit_entry.txt`):

| action | n | landed hits | shields chipped | MP |
|---|---|---|---|---|
| CELES Fight, 0 BP | 68 | 1.00 | **0.00** | 0 |
| CELES Fight, 1 BP | 12 | 2.00 | **0.00** | 0 |
| CELES Fight, 2 BP | 7 | 3.00 | **0.00** | 0 |
| CELES Fight, 3 BP | 2 | 4.00 | **0.00** | 0 |
| LOCKE Genji Fight, 0/1/2 BP | 130 | 2.00 / 4.00 / 6.00 | **0.00** | 0 |
| SABIN Fight, 0 BP | 156 | 1.00 | **0.00** | 0 |
| **SABIN Pummel, 0 BP** | **32** | **2.00** | **2.00** | **4** |

A boosted Fight against a Flan is eight swings and nothing on the gauge, at
any boost, with or without the Genji pair. An unboosted Pummel takes two
shields for four MP. That is the role, and it costs base price.

The same thing measured on a body with real HP — Rhinox, 800 HP, bludgeon
key, **absorbs bolt** (`n024_won`, party LOCKE / EDGAR / SABIN / CELES):

```
[fva-act] n=1 f8080 slot=1 char=05 Blitz($0A) atk=$5D bp=1 rev=0 hands=1
  live=2 aim=1 monhp=1600 tgt=$0200 sh=4 hits=2 dmg=800 chips=2
  mp 116->112 spent=4
[fva-act] n=5 f12361 slot=3 char=06 Fight($00) atk=$FF bp=2 rev=0 hands=1
  live=1 aim=1 monhp=568 tgt=$0200 sh=2 pre=1 cnt=1 passes=2 swings=2
  hits=1 dmg=13 chips=0 mp 175->175 spent=0
   -- build/lab/fight-vs-ability/n024_won/ability0_j00.log
```

**One unboosted Pummel kills a Rhinox outright — 800 damage and two
shields, for 4 MP. A Fight on the same body does 13.** Sixty-one to one,
and the Fight is the boosted one. Over the whole `n024_won` spread that is
not a lucky roll: 40 Pummels averaged 725 damage and 1.60 chips, against
SABIN's 670 Fights at 22.0 damage and 0.03 chips
(`build/lab/fight-vs-ability/mechanic-n024_won.txt`). Rhinox's
defence is the likely reason the sword reads so low — it is the kind of
body the class table calls armoured — but this lab measured the outcome,
not the formula, and does not claim the mechanism.

### 2.2 A status a weapon cannot answer

Zozo's Gabbldegak casts **Vanish on itself** on its second beat
(`ai_script.asm:955`: `attack BATTLE, BATTLE, VANISH`). Against a Vanished
body every physical misses, at every boost, with any number of hands:

```
[fva-act] n=19 f14816 slot=0 char=01 Fight($00) atk=$FF bp=2 rev=2 hands=2
  live=2 aim=1 monhp=656 tgt=$0800 sh=8 rh=$02 lh=$01 pre=1 cnt=5 passes=6
  swings=6 hits=0 dmg=0 chips=0 mp 139->139 spent=0
   -- build/lab/fight-vs-ability/zozo_arrival/fight2_j13.log
```

Six swings from LOCKE's Genji pair at two pips, aimed at a body that was
standing when the action resolved (`aim=1`), for nothing at all.

**That it is the status and not a run of bad luck is what the histogram
says.** A per-swing miss would put mass on 1, 2 and 3 hits; the measured
distribution is bimodal and has none:

```
cmd     who    hands bp     n  $3a70 passes swings max  hits    dmg chips  hist
Fight   CELES      1  2    41   1.00   6.00   6.00   3  2.85   52.3  0.00  0:2,3:39
Fight   CELES      1  3    30   1.00   8.00   8.00   4  3.60   61.7  0.00  0:3,4:27
Fight   SABIN      1  2    39   1.00   6.00   6.00   3  2.85   81.4  0.00  0:2,3:37
Fight   SABIN      1  3    29   1.00   8.00   8.00   4  3.59  100.6  0.00  0:3,4:26
   -- build/lab/fight-vs-ability/mechanic.txt
```

Either every swing lands or the whole action does nothing, which is what a
status gate looks like and not what a hit roll looks like. Over the whole
`zozo_arrival` head-to-head spread
(`build/lab/fight-vs-ability/mechanic-zozo_arrival.txt`), Fights that
landed no hit at all while a live body stood and was aimed at:

| actor | Fights | landed nothing |
|---|---|---|
| CELES | 227 | 90 |
| EDGAR | 209 | 84 |
| SABIN | 206 | 86 |
| LOCKE (pair) | 273 | 95 |

and, in the same spread, the costed verbs against the same pool:

| verb | n | landed a hit |
|---|---|---|
| CELES Ice `$01` / Ice 2 `$06` | 44 / 21 | **44 / 21 — every one** |
| SABIN Pummel `$5D` | 98 | **98 — every one** |
| EDGAR Bio Blaster `$A4` | 36 | **36 — every one** |

Pummel, Bio Blaster and AutoCrossbow each carry `$20` at `magic_prop_en.dat`
`+$04`, the can't-dodge bit, so `CheckHit` takes its carry-clear exit with
no roll (`battle_hitcount.lua` pins the same bit on the blitzes); magic
lands on a Vanished body by vanilla's own rule, and here it did, 65 times
out of 65. **This is the clearest case in the whole lab where the ability
is not merely better but is the only thing that works at all**, and the
price of working is 4, 5 or 8 MP — boost 0.

It shows up in the verdicts, not just the ladder. On `zozo_arrival` the
Fight-only policies could not finish: `fight0` won 18 of 24 battles and
`fight1` 9 of 13, and **six of those twelve runs were still swinging when
the forty-minute wall clock killed them** — every `fight0` and `fight1` run
but one (`rc=143` in
`build/lab/fight-vs-ability/run-zozo_arrival.txt`). Their logs are retained
and the four or five battles each had already reported are counted; a
seventh, `fight1_j47`, exceeded the frame budget and reported nothing,
which is why `fight1`'s n is 13 rather than 24. No ability run was killed,
and every ability arm won 24 of 24.

### 2.3 An element the weapon delivers backwards

LOCKE carries ThunderBlade from the Magitek factory on (`$0F`, a bolt
weapon). Rhinox **absorbs bolt** (`monster_prop.dat`, read back by
`check_boss_rows`' own parser). His Fight therefore heals it, and the two
consecutive turns show it in the stage's HP, which *rises* across his
action:

```
[fva-act] n=13 f4818 slot=2 char=01 Fight($00) atk=$FF bp=0 rev=0 hands=2
  live=2 aim=1 monhp=887 tgt=$0200 rh=$0F lh=$02 cnt=1 passes=2 swings=2
  hits=2 dmg=0 chips=0
[fva-act] n=14 f4910 slot=0 char=04 Fight($00) atk=$FF bp=0 rev=0 hands=1
  live=2 aim=1 monhp=940 tgt=$0200 rh=$0B lh=$5A cnt=1 passes=2 swings=2
  hits=1 dmg=15 chips=0
   -- build/lab/fight-vs-ability/n024_won-mech/fight3_j00.log
```

887 HP before LOCKE swings, **940 after** — his two hits gave it 53 back.
At three pips it is eight hits of the same. The party's best physical turn
in the game, spent feeding the thing. (The fight driver's absorb guard
reads the species' absorb byte before it casts; nothing guards the weapon
already on the hand, which is the shipped behaviour and not this lab's to
change.) The answer here is the ability, and again it is Pummel at 4 MP.

### 2.4 Whole-group damage

`multi-hit.md` calls this breadth rather than rate, and prices it
separately. Measured on the Zozo pool, where the whole street is
poison-weak and EDGAR's Bio Blaster carries poison across the whole enemy
side (`magic_prop_en.dat` `$7d`, target byte `$6a`):

| EDGAR's turn | n | landed hits | shields chipped | damage | MP |
|---|---|---|---|---|---|
| Fight, 0 BP | 209 | 0.60 | 0.03 | 32.7 | 0 |
| Fight, 3 BP | 11 | 0.73 | 0.00 | 36.0 | 0 |
| **Bio Blaster `$A4`, 0 BP** | **36** | **2.53** | **2.53** | **295.9** | **8** |

`hits` and `chips` are the same number because every body it reached was
weak to what it carried. One 8-MP turn takes two and a half shields off two
and a half bodies; his boosted Fight takes 0.03 shields off one. Breadth is
a thing a swing cannot do however many times it swings, and it is bought at
base price.

One caveat on the other tool, for whoever reads this next: AutoCrossbow
`$AA` measured **1.00 landed hits per cast** at `n024_won`, on formations
of two and three bodies, against `kits.md`'s "one hit per body across a
whole side" — 50 casts, `Tools $AA EDGAR 1 0 50 ... 1.00 ... 291.1` in
`build/lab/fight-vs-ability/mechanic-n024_won.txt`, and its rows
do carry a two-body target mask (`tgt=$0300`). Those formations are Rhinox
and Gobbler, neither of which is weak to what the crossbow carries, so a
hit that rounds to nothing is the likelier explanation than a targeting
one. Not chased here; named so it is not mistaken for a measurement of
breadth.

### 2.5 Magnitude, on a body with enough HP to show it

On trash the extra hits saturate: a 397-damage Pummel against a 350-HP
Gabbldegak wastes the difference, which is why `Blitz $5D` at boost 1 in
the Zozo ladder reads 422 damage against boost 0's 397 rather than double
it. Dadaluma, at 3270 HP and six shields, is where magnitude is legible
(`build/lab/fight-vs-ability/dadaluma_entry/ability0_j00.log`, one whole
fight, unboosted throughout):

```
n=2 Blitz($0A) atk=$5D  hits=2 dmg=365 chips=2  mp 153->149 spent=4
n=3 Magic($02) atk=$01  hits=1 dmg=118 chips=0  mp 158->153 spent=5
n=4 Fight($00) atk=$FF  hits=1 dmg=55  chips=0  (EDGAR, one weapon)
n=5 Fight($00) atk=$FF  hits=2 dmg=214 chips=2  (LOCKE, Genji pair)
n=6 Blitz($0A) atk=$5D  hits=2 dmg=944 chips=2  mp 149->145 spent=4
n=7 Fight($00) atk=$FF  hits=1 dmg=194 chips=0  (CELES)
n=8 Tools($09) atk=$AA  hits=1 dmg=734 chips=0  mp 77->73  spent=4
```

That is eight of the nine turns; the ninth is the killing one, which the
instrument's stop rule cuts off before it reaches `SaveForMimic`. Nine
turns, 21 MP for the whole party, Dadaluma dead, and **54 damage taken**.
The three four-MP turns in that list did 365, 944 and 734 damage and took
four of the six shields; the free ones did 55, 194 and 214. Boost nothing,
pay base price, win.

### 2.6 Healing — not measured

Mantra is Blitz #5 at level 23 and no party in the stretches this lab
covers is there yet (SABIN is L19-L22 at the four fixtures). Cure is a
tier-family head and folds rather than taking the 2.5x ladder, so #219 does
not touch its price at all. **This lab says nothing about healing**, and a
claim either way would be invented.

## 3. Where the ability does not earn its MP, and that is the design

### 3.1 Breaking a class the weapon already reaches

Dadaluma is six shields, class `pierce|bludg`, and LOCKE arrives at Zozo
with a Genji pair of Guardian and MithrilKnife — **two piercing weapons**.
His Fight at one pip is four hits and four chips. Over eight Dadaluma
fights (`build/lab/fight-vs-ability/dadaluma_entry/`, two seeds x four
battles):

| policy | won | turns to kill | shields chipped | party MP |
|---|---|---|---|---|
| `ability0` (kit, never boosted) | 8/8 | 9.0 | 6.00 | 21 |
| `abilitygreedy` (kit, boost as it comes) | 8/8 | 8.5 | 6.00 | 43 |
| **`fight1` (Fight only, one pip as it comes)** | **8/8** | **9.0** | **6.00** | **0** |
| `fight0` (Fight only, never boost) | 0/8 | — | 2.00 | 0 |
| `fight2` (Fight only, wait for two pips) | 0/8 | — | 2.00 | 0 |
| `fight3` (Fight only, wait for three pips) | 0/8 | — | 2.00 | 0 |

**A boost-1 Genji Fight matches the ability turn for turn on this boss and
pays nothing** — same nine turns, same six chips, same 3270 damage. That is
the feature working exactly as intended: a pierce gauge in front of a
piercing pair is the boosted Fight's fight.

It costs something the table does show: `fight1` took **1166** damage
getting there against the unboosted kit arm's **54**, because the kit arm
broke the gauge sooner and the break window denied Dadaluma his turns. The
free answer is slower to arrive and the party wears the difference.

(Read `fight0`/`fight2`/`fight3` as what they are: a `fightN` arm waits
until the bank holds N before it spends, so a deeper arm also acts less
often early. Their 0-of-8 is the cost of banking against a boss that puts
out 2400 damage, not a fact about depth alone. Section 5 takes that up.)

### 3.2 Clearing a random the party can already chip

The same shape, on the Zozo street pool, over 24 battles a policy
(`aggregate.txt`):

| policy | won | turns to kill | damage/turn | shields | MP |
|---|---|---|---|---|---|
| `ability0` | 24/24 | 8.2 | 167.8 | 4.29 | 23.2 |
| `ability3` | 24/24 | 8.2 | 167.0 | 4.17 | 40.4 |
| `abilitygreedy` | 24/24 | **5.6** | **233.8** | 2.62 | 38.0 |
| `fight0` | 18/24 | 15.8 | 63.0 | 4.19 | 0 |
| `fight1` | 9/13 | 12.6 | 57.8 | 3.00 | 0 |
| `fight2` | 21/24 | 10.5 | 94.3 | 4.17 | 0 |
| `fight3` | 19/24 | 11.2 | 77.1 | 3.96 | 0 |

Zozo is a bad advertisement for the free option because of the Vanish
above, so read the chips column rather than the turns: **boosted Fight
matches the kit on shields for nothing** — `fight2` chips 4.17 a battle,
exactly `ability3`'s 4.17 and within a tenth of `ability0`'s 4.29, for 0 MP
against 23 to 40. Where the weapon carries the key, the pips do the job and
the MP is spare.

`ifrit_entry`, whose bodies no weapon can chip, is where that stops being
true — every Fight arm chips **0.00** there and wins only on brute damage,
taking 7 to 10 turns against the ability's 3.6 to 4.2.

## 4. The head-to-head, all four shapes

Four fixtures, seven policies, four in-battle RNG phases each (two for the
boss), 24 battles a policy (8 for the boss) — 97 retained runs.
`build/lab/fight-vs-ability/aggregate.txt` is the whole table with every
battle listed; this is its summary block.

```
fixture        policy           n  won kild  kacts    kfr   acts     dmg dmg/act  taken  chips     mp
dadaluma_entry ability0         8    8    8    9.0   2787    9.0    3270   363.3     54   6.00   21.0
dadaluma_entry ability3         8    8    8    9.0   2788    9.0    3270   363.3     54   6.00   21.0
dadaluma_entry abilitygreedy    8    8    8    8.5   2959    9.4    3270   348.8    185   6.00   43.0
dadaluma_entry fight0           8    0    0    0.0      0   16.8     706    42.2   2400   2.00    0.0
dadaluma_entry fight1           8    8    8    9.0   2234    9.0    3270   363.3   1166   6.00    0.0
dadaluma_entry fight2           8    0    0    0.0      0   15.5    1133    73.1   2400   2.00    0.0
dadaluma_entry fight3           8    0    0    0.0      0   22.4     863    38.6   2400   2.00    0.0
ifrit_entry    ability0        24   24   24    4.2   1605    5.9     892   151.9    128   1.67   13.3
ifrit_entry    ability3        24   24   24    4.2   1605    5.9     892   151.9    128   1.67   13.3
ifrit_entry    abilitygreedy   24   24   24    3.6   1510    4.8     892   187.9    129   0.83   34.0
ifrit_entry    fight0          24   24   24    9.8   2471   11.4     892    78.5    372   0.00    0.0
ifrit_entry    fight1          24   24   24    7.0   2493    9.5     892    93.9    263   0.00    0.0
ifrit_entry    fight2          24   24   24    8.0   2444   10.0     892    89.2    404   0.00    0.0
ifrit_entry    fight3          24   24   24    9.0   2341   10.4     892    85.7    370   0.00    0.0
n024_won       ability0        24   24   24    5.8   1675    5.7    1435   253.2    216   3.50   19.0
n024_won       ability3        24   24   24    5.8   1675    5.7    1435   253.2    216   3.50   19.0
n024_won       abilitygreedy   24   24   24    5.9   1724    5.8    1435   249.6    174   2.83   45.0
n024_won       fight0          24    4    4    2.0    188   38.3     951    24.8    635   1.17    0.0
n024_won       fight1          24    4    4    2.0    290   30.6     982    32.1    549   1.21    0.0
n024_won       fight2          24    4    4    2.0    188   29.0    1017    35.1    512   1.17    0.0
n024_won       fight3          24    4    4    2.0    188   28.8     989    34.3    455   1.12    0.0
zozo_arrival   ability0        24   24   24    8.2   3034    8.4    1412   167.8    210   4.29   23.2
zozo_arrival   ability3        24   24   24    8.2   3068    8.5    1412   167.0    217   4.17   40.4
zozo_arrival   abilitygreedy   24   24   24    5.6   2007    5.7    1335   233.8    186   2.62   38.0
zozo_arrival   fight0          21   18   18   15.8   2959   20.0    1257    63.0    280   4.19    0.0
zozo_arrival   fight1          13    9    9   12.6   2832   20.0    1157    57.8    443   3.00    0.0
zozo_arrival   fight2          24   21   21   10.5   2678   13.5    1276    94.3    301   4.17    0.0
zozo_arrival   fight3          24   19   19   11.2   2594   16.0    1231    77.1    326   3.96    0.0
```

`kacts` is turns-to-kill (the turn after which no body still held HP);
`acts` is the instrument's own count, which runs past that because its stop
rule reads a monster's presence bit rather than its HP.

The shape worth calling out is `n024_won`: **Rhinox x2, 1600 HP, bludgeon
key, bolt absorbed.** Every Fight arm ran the 9000-frame budget out at
about 45 turns and under 1000 of the 1600 HP, with **zero chips and zero
breaks**; every ability arm killed it in five to six turns for 21 MP:

```
n024_won  fight0    0075,0075  3 budget   9000  44  -1   9000  887  801  0  0  0
n024_won  ability0  0075,0075  3 won      1637   5   5   1637 1600  406  4  2 21
```

That is not the boosted Fight being weak. That is the boosted Fight being
the wrong tool, and the ability being the only one in the bag.

### What "the boosted ability" actually means in play

One honest limit on all of the above. Across the whole corpus the ability
policies took **600 costed turns**, and the boost they reached was:

| policy | costed turns | at boost 0 | at boost 1 | at boost 3 |
|---|---|---|---|---|
| `ability0` | 212 | 212 | — | — |
| `ability3` | 212 | 208 | — | **4** |
| `abilitygreedy` | 176 | 24 | **152** | — |

`ability3` waits for three pips and almost never gets them: a character
takes about two turns in a five-to-nine-turn fight, the bank opens at one
and earns one per unboosted action. **A three-pip bank is a boss resource,
not a random-encounter one**, and that is why `ability0` and `ability3` are
the same run at `ifrit_entry` and `n024_won` — the deep boost never fired.
So "the boosted ability" in these tables means **boost 1, at 2.5x**, four
times in the whole corpus at 15.625x. Where the deep boost is affordable
and worth it is a boss question this lab does not answer; it answers that
the base-price ability is where the value is.

## 5. What a player should expect to feel

This is the part to read before playtesting.

**Boost is a tempo resource, MP is a magnitude resource, and the two are
not interchangeable any more.** Pips arrive by not spending them; MP does
not come back until a level or an inn. After #219 they buy the same thing
on an ability — more damage — at wildly different prices, so the ability's
boost is the first thing to stop paying for.

**Reach for a boosted ability when the ability is doing something the
swing cannot do at all.** In practice that is four screens:

1. **The gauge will not move.** You have swung twice and the pip row under
   the enemy has not changed. Your weapon is the wrong class. Stop swinging
   and open the kit — Pummel, Bio Blaster, the tool with the right icon.
   Four to eight MP and the gauge starts falling. Do not boost it; the chip
   count does not move with the boost, only the damage does.
2. **It vanished, or your blade is feeding it.** Numbers stop appearing, or
   the enemy's HP goes the wrong way. Blitzes and tools cannot be dodged
   and magic ignores Vanish. Again: base price.
3. **There are four of them and they share a weakness.** Bio Blaster at
   eight MP took two and a half shields off two and a half bodies a turn
   on the Zozo street; a swing takes one off one. Breadth is the thing a
   boost cannot buy you — and, again, it is bought at base price.
4. **It is a real boss and it is going to be a long fight.** This is the
   only place the *boost* on an ability is worth considering, because the
   fight is long enough for the bank to reach two or three and the body has
   enough HP that x4 or x8 is not thrown away. Expect to pay 25 MP for x4
   and 63 for x8 on a four-MP row, and expect that to be one or two turns
   out of your whole pool.

**Do not reach for a boosted ability to break something your weapon already
breaks.** Against Dadaluma the free one-pip Genji Fight matched the kit turn
for turn — nine turns, six chips, the same kill — and paid nothing. Against
the Zozo street the boosted Fight chips as well as the boosted kit does.
When the icons match your weapon, the pips are the answer and the MP is
spare.

**What a wasted boost feels like:** you spend three pips on a Blitz, watch
63 MP go, and the number that comes back is bigger than it needed to be
because the body died on the first hit. The cap on how much a boosted
ability can be worth is the target's remaining HP, and on trash that cap
binds almost immediately — boost 1 on Pummel measured 422 damage against
boost 0's 397 in Zozo, for two and a half times the MP, because a
397-damage Pummel already kills a 350-HP Gabbldegak.

**What a wasted bank feels like:** you hold three pips for two rounds
waiting for the big turn, and the boss kills someone in the meantime. Every
Fight-only arm that waited for two or three pips lost all eight Dadaluma
fights; the one that spent a single pip as it arrived won all eight.

## 6. Randoms: boost, or bank?

The standing guideline is "boost-Fight through randoms". **The numbers keep
it, with one correction: spend shallow and often, do not bank for three.**

Turns to kill, Fight-only arms, over 24 battles each:

| | never boost | 1 pip | 2 pips | 3 pips |
|---|---|---|---|---|
| zozo_arrival, turns to kill | 15.8 | 12.6 | **10.5** | 11.2 |
| ifrit_entry, turns to kill | 9.8 | **7.0** | 8.0 | 9.0 |
| n024_won, battles killed of 24 | 4 | 4 | 4 | 4 |
| dadaluma_entry, won of 8 | 0 | **8** | 0 | 0 |

Unboosted Fight is the worst row everywhere it can be compared. So the
answer to "is the right default in randoms now to bank instead" is **no** —
boosting Fight still beats holding the pips, which is the guideline
working. But three pips is never the best row and is sometimes the worst,
because a policy that waits for three spends its early turns not acting,
and a random encounter is over in five to nine turns. **One or two pips,
spent the turn they arrive, is the whole of it**; the third pip is a
boss's, and even there it went further as two ones than held for one
three.

`n024_won` is the row that says what the pips cannot fix: 4 of 24 at every
depth, because Rhinox's gauge has no key any weapon in that party carries.
No amount of boosting buys a chip axis (section 2.1).

### The one player who never had that choice — #236

Everything above assumes a player deciding when to spend. A character the
player is **not** driving never had the choice: every writer of the pending
boost was a player-driven path (the boost press, the SwdTech confirm, the
thief submenu, the Slot reels), so `Ot6ActionEnd` took its regen arm on
every one of that character's turns. Measured in battle 66 before the
change: a berserked EDGAR banked 1-2-3-4-5 over four engine-chosen Fights
while being hit the whole way, and the charge arm ran zero times
(`build/attempts/<branch>/lab/uncontrolled/probe_bank.log`). The boost
economy was inert for Umaro, a Berserked ally, a Muddled ally and a
Colosseum fighter alike — one cause, one class.

The rule now is the owner's: **bank normally; when you are hurt, dump the
whole bank on your next swing.** It lands on the same ladder this document
measures — the spend caps at 3 while the bank caps at 5, so a dump is at
most three pips, which is `1 + 2*3 = 7` in `$3a70`, eight passes, and **four
landed hits with one weapon, eight with a Genji pair**. It costs BP and no
MP: Fight is free, and `Ot6BoostDmg` exempts command `$00`/`$06` from the
damage multiplier, so the pips buy swings and nothing else.

Measured on this ROM, eight seeds, `tools/tests/battle_retaliate.lua` and
`build/attempts/<branch>/sweeps/retaliate/`: bank 5 → 2, pending 3, `$3a70`
7, 8 passes (4 main, 4 off), 4 landed of a possible 4, every seed. The
Muddle case is the same numbers with the volley aimed at the party
(`build/attempts/<branch>/lab/uncontrolled/lab_retaliate_muddle.log`), which
is the intent and not an oversight. Umaro and the Colosseum are World of
Ruin content and are reasoned from the ROM rather than played: Umaro is
refused a command window by name, so he reaches the same engine arm, but
only one of his four attack slots is `FightAttack`, so the dump is armed at
his chooser, ahead of the roll (#237, `Ot6UmaroRetaliate`): his plain swing
takes it as swings, Charge and Storm as the damage multiplier, and Throw as
one extra throw per pip (`Ot6ThrowBoost`). That is a staged mechanism test
(`tools/tests/battle_retaliate_umaro.lua`, a party member of the TunnelArmr
fight renamed to him), never route play.

A character an AI script drives — CYAN in the Doma courtyard defence — is
also one the player is not driving, and reaches `ExecMonsterAction` without
ever passing `RandCharAction`; the latch is set there too (#238), and
`tools/tests/battle_retaliate_script.lua` plays that defence and measures
his provoked scripted Fight dumping.

## 7. The lab

`tools/tests/fightvsabilitylab.py`. Three arms.

**`reach`** is static and needs no emulator: for every formation the
route's own areas roll (`tools/check_break_reach.py`'s `AREAS`, whose
parsers it imports so the two cannot read `Ot6ShieldTbl`, the break floor
or `Ot6ElemAddTbl` differently), it asks whether each party member's
*actual* weapons — read out of that stretch's tracked savestate with
`tools/savestate_party.py`, not assumed — chip that body, and which of that
member's kit verbs would. A verb counts only at the level that learns it
(`BlitzLevelTbl` / `BushidoLevelTbl`) and a tool only when the bag really
holds it.

**`write` / `run` / `aggregate` / `mechanic`** derive `tools/tests/bal_party.lua`
— the shipped, owner-sanctioned party balance instrument, whose protocol is
already seeded `$1FA1`/`$1FA2` draws so battle *k* is the same battle in
every arm, paired samples, per-character attribution — into
`build/lab/fight-vs-ability/lab.lua`. The derivation adds seven policies,
four fixtures beside `bal_party`'s own, an `FVA_JITTER` knob that shifts
the in-battle RNG phase so a policy is run over a spread, one aiming rule,
and five read-only CPU exec observers. Every substitution asserts it
matched exactly once, so an edit to the instrument fails the derivation
instead of silently measuring something else. `bal_party`'s own `envcfg`
reads are dead — Mesen's Lua sandbox blocks `os.getenv`
(`lib/compose.py:2016`) — so the policy, the fixture and the jitter are
substituted into a per-run copy as literals, and an unsubstituted token
fails the run rather than quietly measuring the default fixture.

The observers read and never write:

```
ExecCmd@battle_code   parks the acting character's command, attack, target
                      mask, pending boost, MP, both hands' item ids, the
                      shield total, the monster HP total and how many
                      bodies still hold HP
Ot6FightBoost         the VANILLA swing count in $3a70, before the boost's
                      own add -- plus the two cells the proc's own
                      early-outs read there: the pending boost it is about
                      to deliver, and $B1 bit 0
Ot6WeaponClass        one exec per hand per swing, gated on the acting
                      entity, so it counts SWINGS ATTEMPTED
Ot6HitJoin            one exec per LANDED hit, gated on Y >= $08 so a
                      counterattack landing on a character inside the
                      action is not counted as one of its hits
SaveForMimic          the action resolved: emit the row
```

The one thing the derivation changes about how the instrument *plays*:
`bal_party` presses A on whatever the target cursor happens to be lighting,
which on a formation that has lost a body is often a corpse. The derived
copy taps the d-pad until the lit mask covers a body still standing and
only then confirms — d-pad and A, nothing else, with a twelve-tap budget
after which it confirms anyway so a cursor it cannot reach is measured
rather than hidden.

The head-to-head spread ran before the last two observer refinements (the
`Y >= $08` gate on `Ot6HitJoin` and the `$B1` read at `Ot6FightBoost`), so
the swing ladder in section 1 is a **separate, later spread** —
`--tag mech`, `fight0`..`fight3` on three fixtures at two jitters, 24 runs
under `build/lab/fight-vs-ability/*-mech/` and tabulated in `mechanic.txt`.
Adding a read-only observer cannot change an emulated run, so the two
spreads are the same game; they are kept apart only so that every retained
log carries the same fields as the table drawn from it. The head-to-head
tables in sections 3 and 4 are the earlier spread's and are unaffected by
either refinement, which touch only how hits are attributed within an
action.

### What is retained, including what is superseded

`build/lab/fight-vs-ability/` keeps everything, and
`build/lab/fight-vs-ability/pre-live/README.txt` says why each superseded
spread is still there:

- `pre-live/zozo_arrival/` — the first cut of the observers, with no
  live-body count. `bal_party`'s stop rule reads a monster's presence bit
  and status byte, never its HP, so a formation whose last body is at 0 HP
  keeps the fight "live" for a few hundred frames while the queued actions
  swing at nothing; those turns entered the ladder as 8-swing, 0-hit
  Fights.
- `pre-live/zozo_arrival-blindaim/` — the live count, but the blind A at
  the target cursor. 124 of 396 Fights under `fight0` and 167 of 362 under
  `fight3` landed nothing while a live body stood, against 8 of 56 in each
  ability arm, whose AutoCrossbow and Pummel need no cursor. A head-to-head
  on those numbers would have measured the instrument's aim and would have
  been biased the whole way towards the ability.
- `esper_mtn_save/` — 28 runs of a fixture that stands on the save point
  and never hands the pacer field control ("timeout after 1800 frames
  waiting for field control (b=1)"). It was meant to be the caster's
  stretch; `ultros_won`, the same map one step later, fails the same way.
  The caster arm in this document is therefore CELES's Ice and Ice 2 inside
  the other three fixtures, and TERRA is not measured at all.
- Six `zozo_arrival` runs killed by the forty-minute wall clock (`rc=143`
  in `run-zozo_arrival.txt`) kept four or five of their six battles; those
  battles count and the missing ones do not. A seventh (`fight1_j47`,
  `rc=2`) exceeded the frame budget and reported nothing, which is why
  `fight1`'s n is 13 rather than 24. All seven are `fight0` or `fight1`
  runs on the pool that Vanishes; no ability run was killed anywhere.

Nothing in this document is quoted from `pre-live/`.

The tree is 638 text files and 60 MiB and it lives in the agent worktree
this work was done in, so it has to be carried across before that worktree
goes (`docs/TESTING.md`, #222):

```sh
python3 tools/retain_evidence.py <worktree> worktree-agent-aa580481caaf13688
```

which puts every path cited above under
`build/attempts/worktree-agent-aa580481caaf13688/lab/fight-vs-ability/…`
in the main tree, relative paths preserved. `--dry-run` from this branch
plans 638 files with no conflicts. If that step is missed, the citations
here resolve nowhere, the way `zozo-grind.md`'s do.

### The blind spots

- **Per-turn damage saturates on trash**, because a hit past the kill is
  wasted; `kacts` (turns-to-kill) is the column to read there, and `dmg/act`
  only on Dadaluma.
- **`dmg` for a group ability is the sum over every body it reached**, so
  Bio Blaster's 296 is two and a half bodies' worth and Pummel's 800 is
  one.
- **A counterattack is excluded from the ladder** by `$B1` bit 0, the same
  flag `Ot6FightBoost` refuses on; those rows are in the logs with `fb1=1`
  and carry the unboosted swing count whatever the actor's pending boost
  reads.
- **LOCKE's pair occasionally logs one or two hits above `2(1+BP)`.** Every
  such row reads `dmg=0` against a Rhinox, which absorbs his blade's bolt:
  the absorb path runs the same join. It is the finding in section 2.3
  showing up in the arithmetic, not an extra swing.
- **TERRA, CYAN, MOG, STRAGO, RELM, SETZER and GAU are not measured.** The
  static arm covers every routed body in three areas; the in-play arm
  covers LOCKE, EDGAR, SABIN and CELES.
