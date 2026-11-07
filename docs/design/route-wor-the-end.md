# World of Ruin: Kefka and the ending

Issue #274. The last leg of the line: from `wor-kt-plates-v1` (party 2 on
412's save point, parties 1 and 3 on 411's plates; route-wor-kefka-tower.md)
up to Kefka, his battle, the ending and the staff roll. This doc decodes the
climb and the battle from the ROM, designs the battle's break rows, and
measures the fight.

Evidence is under `build/attempts/wt/v040-the-end/`. Line numbers are into
`ff6/src/event/event_main.asm` unless a file is named.

---

## 0. Findings

1. **One battle, four formations.** Event battle 101 opens on formation 471
   (Short Arm, Long Arm, Face); when every body of a formation is dead,
   `CheckFinalBattle` (battle_main.asm) loads the next from
   `FinalBattleIDTbl` (471, 512, 513, 514) inside the same battle. Between
   two formations the end-of-battle special event $06 clears the fallen
   members (Wound, Zombie, Poison) and the next members of the order menu's
   list take their seats. A party that falls whole inside a formation is a
   game over (`_ca5ea9` after `battle 101`).
2. **The order menu chooses who fights.** `order_menu` (event command $9D,
   menu type $08, `final_order.asm`) lists the members of the three parties
   (twelve on the line); the player picks an order, START fills the rest in
   list order. The first four start the fight; the rest come in, in order,
   for the fallen.
3. **The third tier kills on its way out.** The Sleep's death answer is two
   Calmness (Death) (`AIScript::_351`, `if_self_dead`), so the third tier
   usually ends with two or three members down, and Kefka is met by the
   bench the order put next.
4. **The Girl first.** Killing the lady before the sleeper (her Pearl Wind
   heals it to full) takes the leg from 17 to 20 of 24 runs across the grid
   (section 5); the rest are attrition carried from tier to tier and
   Kefka's Fallen One, not yet every draw.
5. **Life 2, boosted cures and two stones answer Fallen One.** Reviving the
   fallen with Life at one point (full HP), curing the member in danger with
   Cure at one or two points, and Phoenix and Kirin on STRAGO and LOCKE take
   the stocked chain's grid from 18 to 23 of 24 runs (20 of 24 on a second
   grid); the third tier is never lost again, and what loses is Kefka after
   his first break (5.2).

## 1. The climb

Party 2 steps from 412 (82,45) down to 411 (109,42) and onto the middle
plate (109,40). 411's three plates run `_cc193f`: the walking party's bit
($02C6, $02CA, $02CE) set, all three set starts `FinalBattle` (:926). The
scene loads map 336, the three parties climb, Kefka speaks; then the order
menu, `battle 101` (:1961) and, won, the escape and `GameEnding` (:2528):
each character's scene, `cutscene FALCON` (event command $BF,
`EndingAirshipScene2_ext`: the staff roll over the Falcon), `ending 32` and
`cutscene THE_END` (event command $BB, `TheEnd_ext`), which never returns.
No input is asked after the battle but the dialogs' A.

Nothing on the way deals a random battle: 412 and 411 have random battles
off (`route_data.py map 411 412`).

**The order menu** (`final_order.asm`): `$4B` is the cursor (0 "reset",
1-12 the list, 13 "end"), `$4A` how many are picked, `$7E9D8A+i` the
list's characters (those in a party, `MakeFinalOrderCharList`), `$0205+k`
the k-th pick. A on a white name picks it; B takes the last pick back;
START (or A on "end") closes the menu after `FillFinalOrder` adds the
unpicked in list order.

## 2. The battle and its rows

| formation | species | L / HP | vanilla | shields | classes |
|---|---|---|---|---|---|
| 471 | Short Arm `$157` | 73 / 27,000 | weak water | 6 | pierce, bludgeon |
| 471 | Long Arm `$158` | 73 / 33,000 | weak wind | 6 | slash, pierce |
| 471 | Face `$159` | 74 / 30,000 | weak fire; nulls earth | 8 | bludgeon, special |
| 512 | Hit `$15D` | 73 / 28,000 | weak poison | 6 | slash, bludgeon |
| 512 | Tiger `$15A` | 70 / 30,000 | weak ice; absorbs earth | 6 | slash, pierce |
| 512 | Tools `$15B` | 73 / 24,000 | weak bolt | 6 | pierce, bludgeon |
| 512 | Magic `$15C` | 72 / 41,000 | weak earth | 8 | slash, special |
| 513 | Girl `$15E` | 58 / 9,999 | absorbs every element | 3 | slash, pierce |
| 513 | Sleep `$15F` | 71 / 40,000 | none | 8 | bludgeon, special |
| 514 | Kefka `$12A` | 71 / 62,000 | none; nulls poison | 12 | slash, pierce, bludgeon, special |

The generated floor stood for each before (six shields, slash only). The
lessons:

- **Every hand in every tier.** Whoever the order puts in front meets the
  tier, so each formation between its bodies takes slash, pierce, bludgeon
  and special: any four hold a key somewhere, and the order decides who
  breaks what. The bodies keep the tower's grammar: the Short Arm and the
  Tools are machines (the point and the blow, as the factory's), the Face
  and the Sleep are magic made stone (the blow and the brush, as the
  statues), the Magic a sorceress (the Madam's pair), the Hit a warrior in
  plate (the Retainer's), the Tiger and the Long Arm hide and sinew.
- **Steel for the lady.** The Girl absorbs every element, so a spell heals
  her and only a weapon breaks her. When she stands alone she casts Life 2
  on the dead (`AIScript::_350`); a break holds that turn.
- **Kefka takes every hand**, twelve shields: the last fight is the whole
  party's.

`battle_breakwor_end` checks the rows in the built ROM, their vanilla weak
and absorb bytes, that event battle 101 opens on 471 and the tier table
chains the four, and the lessons. Red on main's rows (`rows/main.log`, 25
mismatches: "$12A Kefka has no Ot6ShieldTbl row (want 12, class $0F)") and
on a mutant with the Girl keyed by slash and special (`rows/mut_girl.log`:
"formation 513 (tier 3): its bodies together key class mask $0D, want every
hand ($0F)"); PASS on the rows (`rows/rows.log`).

What the bodies do (ai_script.asm `_343`-`_351`, `_298`):

- the arms and the face: the Short Arm's VacuumWave, the Long Arm's Shock
  Wave (three when it is the last standing), the Face's Dread (Petrify),
  Magnitude 8, R.Polarity and Safe and Haste on the others; Quake when it
  dies;
- the four figures: the Tiger's S. Cross, N. Cross, Flare Star and Doom
  Tusk (Zombie); the Tools' Diffuser, Tek Laser, Absolute 0, Delta Hit
  (Petrify), Atomic Ray; the Magic's whole spell book (Stop, Muddle, Imp,
  Reflect on itself, Life 3), Quartr when hit below a quarter; the Hit's
  ten hits when it dies;
- the lady and the sleeper: the Girl's Pearl Wind and Calmness (Sleep), and
  Life 2 alone; the Sleep's Meteo, W Wind, Merton, Condemned, and its two
  Calmness (Death) when it dies;
- Kefka: Goner, Havoc Wing, Fallen One (HP to 1), Revenger, Meteor, the
  third-tier spells; Ultima and HyperDrive in answer.

## 3. The order

The line picks the twelve by level, the most HP first among equals (a
player puts the strongest in front): at `wor-kt-plates-v1`, "TERRA, CELES,
RELM, STRAGO, CYAN, SHADOW, LOCKE, MOG, GOGO, SABIN, EDGAR, SETZER" (the
leg's `[order] committed` line). The first four hold slash (TERRA's and
CELES's blades) and bludgeon (RELM's and STRAGO's rods); the bench behind
them brings the pierce and the cards.

Before the plate each party is cared for in turn (`H.splitCare`), and the
leg asserts all twelve stand (`T.standing`).

## 4. The leg and the line's end

`gen_wor_kefka` boots `wor-kt-plates-v1` and plays to "The End": Phoenix on
STRAGO and Kirin on LOCKE (party 2's, walking at the boot), the care, the
plate, the order menu, the battle (the tactical driver, the Girl killed
first in the third tier, the fallen revived with Life 2 and the member in
danger cured at a boost: 5.2), the ending. It asserts the staff roll and then The End by the code
the game runs (exec watches on `EndingAirshipScene2_ext` and `TheEnd_ext`)
and saves its last state, `wor_kefka.mss`, there. No save point follows
Kefka, so the line ends on that savestate rather than a battery: the graph's
last entry, `wor_kefka`, cuts nothing, and `wor-kt-plates-v1` is a plain cut
now that a leg boots it.

What the leg depends on (#480): the entry contract (the statues beaten,
parties 1 and 3 on their plates, party 2 on 412's save point), twelve
members in the three parties, the bag's floor, Phoenix and Kirin owned and
worn by nobody with STRAGO and LOCKE in party 2, and the three standing
after the care.

## 5. Measured

From the graph's `wor-kt-plates-v1` capture (sha256 1d4e7643, the tracked
save byte for byte; the v0.39 release's play) on the rows' ROM (7f1aba0d),
px13, each run the leg itself with a prelude of lab globals (`lab.sh`):
K = 0, 2, 4 battles fought by party 2 on 334's north before the climb
(`KEFKA_BURN`; 412 and 411 deal none) by seed shifts 0, 1, 4, 5, 8, 9, 12,
13, each run stopped at Kefka's outcome (`KEFKA_UNTIL`). Tallied by
`kefkatally.py` (`tally_*.txt`): each formation of the battle by its own
battle key (`$be` at its load with the formation), and the battle by its
opening key. The driver names a tier's outcome by the formation the battle
has already moved on to, which the tally undoes.

| arm | the lever | runs won | opening keys won / lost | third tier lost | Kefka lost |
|---|---|---|---|---|---|
| `g` (+ `p3`) | the stock driver | 17 of 24 | 15 / 5 | 5 (4 keys) | 2 (2 keys) |
| **`f`** | **the Girl first** | **20 of 24** | 14 / 4 | 2 (2 keys) | 2 (2 keys) |
| `wg` | the Girl first, the Wall Rings off | 15 of 24 | 15 / 7 | 2 | 7 (6 keys) |
| `wgr` | `wg` + a party cure reopens the round's care in ruin (`ruinCure`) | 19 of 24 | 17 / 5 | 2 | 3 |
| `gh`, `wgh` (K = 0) | the Girl first, heal at 80% (and the Wall Rings off) | 6 of 8, 6 of 8 | | 0, 2 | 2, 0 |

Quoted: "Kefka's battle: 24 runs; won 17, lost 7, other 0; distinct opening
keys won 15, lost 5" (`tally_g.txt`); "Kefka's battle: 24 runs; won 20, lost
4, other 0; distinct opening keys won 14, lost 4", "3 lady+sleeper: won 22,
lost 2; distinct keys won 18, lost 2", "4 Kefka: won 20, lost 2; distinct
keys won 18, lost 2" (`tally_f.txt`); "Kefka's battle: 24 runs; won 15, lost
9" (`tally_wg.txt`); "Kefka's battle: 24 runs; won 19, lost 5"
(`tally_wgr.txt`). The first two tiers were never lost (`f`: "1 arms+face:
won 24, lost 0; distinct keys won 17", "2 figures: won 24, lost 0; distinct
keys won 20").

- **The Girl first** (the leg's policy): her Pearl Wind heals the Sleep back
  to full while the party hits it ("s3:40000/40000" over and over in
  `g_k0_s8`, the third tier lost after 32,796 ticks with eight deaths); with
  her dead first the same key won ("tier 3 lady+sleeper WON after 22410
  ticks, 6 deaths, key beB4", `f_k0_s8`).
- **The Wall Rings stay on.** With RELM's and STRAGO's on, TERRA casts no
  party cure ("no party cure: entity 2 wears Reflect"), but Kefka's Fire 3,
  Ice 3 and Bolt 3 bounce back onto him; with them off, Kefka won 15 of 22
  where he was met against 20 of 22.
- **Kefka's Fallen One** opens his tier: every member at 1 HP. The driver
  gives the round one care turn and the others attack inside a round of
  death ("SPEND (attack): 1/6542 is inside one round of death ... the round's
  care turn went to actor 3", `wg_k0_s0`), and the race is won or lost on
  whether his Goner (below 32,640 HP) or Ultima (answered below 10,240) comes
  first. `ruinCure` (a party heal reopening the round's care) helped only
  with the Wall Rings off and is not kept (`ruincure.diff`).
- **What still loses** (`f`): two third tiers to the Sleep's Merton and Meteo
  on a party that came out of the second tier battered (`f_k4_s13`,
  `f_k4_s8`), and two Kefkas to Goner on a party Fallen One left at 1 HP
  (`f_k2_s12`, `f_k4_s0`). HP carries from tier to tier, and the second
  tier is long (14,281-41,909 ticks).

The line's own play (K = 0, shift 0) won in every arm, and the leg as the
graph plays it: `p4` "PASS (frame 149361) attempts=1/1", "[end] 24
cinematics, the last airship scene at f148043, The End at f148758" (the
stock policy); `p5` with the Girl first, "PASS (frame 144993) attempts=1/1",
"[end] 24 cinematics, the last airship scene at f143675, The End at f144390".

**Negatives** (#480, #513; `neg/`, `negs.sh`, lab batteries edited by
`make_negative.py` from the graph's captures), each red at its assert:
gen_wor_kt_poltergeist with the four bludgeons emptied, "a bludgeon for
STRAGO in the bag or his hands ... got false"; with one Wall Ring left, "a
Wall Ring for each of the 2 members who wear one for the Poltergeist, in the
bag or worn (1): got false"; gen_wor_kefka with LOCKE fallen and no Fenix
Down, "the three parties before Kefka: who stands: got LOCKE 0/3857 status
$80, want every member"; with party 2's plate bit set, "contract
wor-kt-plates-v1 (entry) VIOLATED ... switch $02CA (party 2 not yet on a
plate of 411 ...): expected 0, read 1". The positive is the leg's play: "ok:
the three parties before Kefka: who stands = every member" (`p3`).
`T.standing` is the one helper the three statue legs call too.

### 5.1 The bag, the order and Kefka's shields (second round)

**The bag.** gen_wor_kt_factory's Kohlingen stop now stocks the tower and
Kefka: Fenix Downs to 40, Potions to 99 (the first play stocked 20 and
reached Kefka with 6). The tower's legs were replayed in order on this tree
from the graph's `wor-desert-v1` (sha256 3876df9e), each from the leg before
(`chain.sh`, `seal.py`, `chain.log`): every leg "PASS ... attempts=1/3", the
factory "bought 15 x $F0", and Kefka's boot reached with "potion=85
tincture=40 fenix=15". gen_wor_kefka asserts the floor at its boot (10 Fenix
Downs, 40 Potions); the graph's v0.39 capture is its negative: "the bag for
Kefka: 6 Fenix Downs (floor 10) and 86 Potions (floor 40), stocked at
Kohlingen by gen_wor_kt_factory: got false" (`neg/neg_kefka_bag`).

**Two driver levers, off** (on the v0.39 capture, the Girl first): the
ruin rule (`opts.ruin`: three or more members inside their round reopen the
round's care for every actor, a party cure ahead of a raise), "Kefka's
battle: 24 runs; won 16, lost 8, other 0; distinct opening keys won 11, lost
8" (`tally_r.txt`); with a care stop at each tier's end as well
(`KEFKA_TIER_CARE`: the last body under a quarter of its HP, heal at 90%, no
press), "won 17, lost 7 ... won 12, lost 7" (`tally_rt.txt`). The Girl first
alone was 20 of 24.

**The order** (the owner's six arms; from the stocked chain's
`wor-kt-plates-v1`, the Girl first, the same K x shift grid):

| arm | order | runs won | opening keys won / lost | tier 1 lost | tier 2 lost | tier 3 lost | Kefka lost (keys) |
|---|---|---|---|---|---|---|---|
| `os` | strongest first (the leg's) | **18 of 24** | 16 / 5 | 0 | 0 | 2 | 4 (4) |
| `ob` | as recruited in the World of Balance | 14 of 24 | 14 / 8 | 0 | 0 | 6 | 4 (4) |
| `ow` | weakest first | 5 of 24 | 4 / 17 | 3 | 7 | 7 | 2 (2) |
| `orr` | as recruited in the World of Ruin | 7 of 24 | 7 / 15 | 3 | 0 | 13 | 1 (1) |
| `om` | strong and carried alternating | 6 of 24 | 5 / 16 | 3 | 0 | 7 | 8 (6) |
| `ox` | a seeded shuffle (Python `random.Random(274)`: SETZER, SHADOW, EDGAR, GOGO, MOG, LOCKE, RELM, TERRA, CELES, SABIN, STRAGO, CYAN) | 3 of 24 | 3 / 18 | 0 | 13 | 6 | 2 (2) |

Quoted (`tally_<arm>.txt`): "Kefka's battle: 24 runs; won 18, lost 6, other
0; distinct opening keys won 16, lost 5" (`os`); "won 14, lost 10 ... won
14, lost 8" (`ob`); "won 5, lost 19 ... won 4, lost 17" (`ow`); "won 7, lost
17 ... won 7, lost 15" (`orr`); "won 6, lost 18 ... won 5, lost 16" (`om`);
"won 3, lost 21 ... won 3, lost 18" (`ox`). None passes every draw; the
strongest first is the best by far and stays.

**Kefka at 16 shields** (`k16`, a ROM arm, ccf835ca, the strongest first):
the first three tiers play exactly as `os` (their rows did not change), and
Kefka loses more: "4 Kefka: won 15, lost 7; distinct keys won 15, lost 7"
against `os`'s "4 Kefka: won 18, lost 4; distinct keys won 18, lost 4";
"Kefka's battle: 24 runs; won 15, lost 9" (`tally_k16.txt`). The row stays
at 12 until the fight passes every draw at 12.

### 5.2 The heals that answer Fallen One (third round)

Evidence is under `build/attempts/wt/v040-the-end-2/` (`tally_<arm>.txt`,
`lab/`, `pre/`, `jobs_<arm>.txt`), every arm on the stocked chain's
`wor-kt-plates-v1` (sha256 44ff430f) and the rows' ROM (7f1aba0d), px13,
the same K x shift grid as 5.1 (grid A: shifts 0, 1, 4, 5, 8, 9, 12, 13);
some arms also on grid B (shifts 2, 3, 6, 7, 10, 11, 14, 15), the same K.

**What the losses were.** Every Kefka loss in `os` has the same shape:
Fallen One opens his tier and leaves the four at 1 HP; the first break takes
him from about 52,000 to between 4,000 and 26,000 while he loses his turns;
the break ends with the four still at 1 HP (a Potion puts back 250, a Fenix
Down raises at an eighth, and a cure on a Wall Ring wearer bounces); then
below 32,640 his cycle opens with Goner, and his counters, HyperDrive below
30,080 and Ultima below 10,240, take whoever is left (`os_k4_s0`: Goner at
4,468 HP, "from 834/4672 ... atk $DE"). His HP when the party fell:
4,311 to 26,310 across the later arms' losses.

**What the party had.** No Elixir or Megalixir (the bag at the boot: 85
Potions, 15 Fenix Downs, 40 Tinctures, no X-Potion); Life known to TERRA and
to SHADOW through Sraphim, Cure to TERRA, CELES and SHADOW; Phoenix (Life)
and Kirin (Cure, Regen) owned and worn by nobody. Life at one point is Life
2 (full HP on the fallen) and at two Life 3 (status 4's reraise, not
reflected); Cure at one point is Cure 2 and at two Cure 3, several times the
plain cast's 965 the care lines price.

| arm | the lever | runs won | opening keys won / lost | tier 3 lost | Kefka lost (keys) |
|---|---|---|---|---|---|
| `os` | the leg before (5.1) | 18 of 24 | 16 / 5 | 2 | 4 (4) |
| `l3` | Life 3 on each member through Kefka's tier and below half the Sleep's HP (the bank unchecked: cast at one point) | 11 of 24 | 11 / 10 | 2 | 11 (10) |
| `l3b` | `l3`, the bank holding two points | 16 of 24 | 15 / 7 | 2 | 6 (6) |
| `l3c` | Life 3 only with Kefka under 60% | 18 of 24 | 16 / 5 | 2 | 4 (4) |
| `lr` | Life 2 on the fallen (`lifeRaise`) | 18 of 24 | 15 / 5 | 0 | 6 (5) |
| `lrbc` | `lr` + Cure at one or two points on the member under 40%, not in a break (`boostCure`) | 21 of 24 | 20 / 3 | 0 | 3 (2) |
| `lrbt` | `lrbc`, the break's last quarter open to the cure | 21 of 24 | 20 / 3 | 0 | 3 (2) |
| `lrbn` | `lrbc`, the cure in breaks too | 21 of 24 | 18 / 3 | 0 | 3 (3) |
| **`lrbs`** | **`lrbc` + Phoenix on STRAGO, Kirin on LOCKE** | **23 of 24** | 18 / 1 | 0 | 1 (1) |
| `lrbsB` | `lrbs` on grid B | 20 of 24 | 15 / 4 | 0 | 4 (4) |
| `lrbw` | `lrbs` with RELM's and STRAGO's Wall Rings off | 17 of 24 | 16 / 7 | 0 | 7 (7) |
| `lrb6`, `lrb6B` | `lrbs`, the cure under 60% | 22, 21 of 24 | 17 / 2, 16 / 3 | 0, 0 | 2, 3 |
| `ph`, `phB` | `lrbs` + the break's hold (`phaseHold`: a first break stops at 42,000 and its turns go to heals) | 22, 20 of 24 | 17 / 2, 15 / 4 | 0, 0 | 2, 4 |
| `dflt`, `dfltB` | the leg as committed (`lrbs`'s levers) | 23, 20 of 24 | 18 / 1, 15 / 4 | 0, 0 | 1, 4 |

Quoted: "Kefka's battle: 24 runs; won 11, lost 13, other 0; distinct opening
keys won 11, lost 10" (`l3`); "won 16, lost 8 ... won 15, lost 7" (`l3b`);
"won 18, lost 6 ... won 16, lost 5" (`l3c`); "won 18, lost 6 ... won 15,
lost 5" and "3 lady+sleeper: won 24, lost 0" (`lr`); "won 21, lost 3 ... won
20, lost 3" (`lrbc`, `lrbt`); "won 21, lost 3 ... won 18, lost 3" (`lrbn`);
"won 23, lost 1, other 0; distinct opening keys won 18, lost 1" and "4 Kefka:
won 23, lost 1; distinct keys won 18, lost 1" (`lrbs`, `dflt`); "won 20, lost
4 ... won 15, lost 4" (`lrbsB`, `dfltB`); "won 17, lost 7 ... won 16, lost 7"
(`lrbw`); "won 22, lost 2 ... won 17, lost 2", "won 21, lost 3 ... won 16,
lost 3" (`lrb6`, `lrb6B`); "won 22, lost 2 ... won 17, lost 2", "won 20, lost
4 ... won 15, lost 4" (`ph`, `phB`). The first two tiers were never lost.

- **Life 3 costs the race.** Two points a cast, from TERRA's or SHADOW's
  bank, is two points not spent breaking Kefka; the first cut went at one
  point when the bank held one (Life 2, which does nothing to the living:
  "wanted 2, the bank holds 1: going at 1", `l3_k4_s13`). Gated under 60% it
  was cast twice in 24 runs. The ward stays in the driver (`buffVs` takes
  Life at two points), off.
- **Life 2 ends the third tier's losses**: a fallen member back at full HP
  for one point ("CELES 6155/6155" after "Life at 1 BP (Life 2) on fallen
  entity 1", `lr_k0_s5`), and the Sleep's attrition never took a tier again
  in any arm after it.
- **Boosted cures and two more casters** carry Kefka's tier: 42 members fell
  in it across `lrbc`'s grid, 21 in `lrbs`'s. The leg keeps both, and the
  stones (`gen_wor_kefka`: `STONES`; the boot asserts them owned and unworn).
- **The Wall Rings stay** (`lrbw`): with them off the cures reach RELM and
  STRAGO, and Kefka's Fire 3, Ice 3 and Bolt 3 reach the party.
- **The break's hold** does not help: the hits already queued when the hold
  begins take him past it (the break opened at 48,408 and the hold met him at
  29,518, `ph_k4_s12`), and a window's heals are a Potion or two and one
  cure.
- **What still loses** (`dflt`, `dfltB`): five of 48, all Kefka's, after the
  first break: Goner and HyperDrive on members at 1 HP (the Wall Ring
  wearers, whom only a Potion reaches, and members whose banks the break
  emptied), or his Ultima answering the last hits below 10,240.

The line's own play under the committed leg: "[end] 24 cinematics, the last
airship scene at f151316, The End at f152030", "PASS (frame 152633)
attempts=1/1" (`end1`).

## 6. Not done

- **Every draw.** The leg wins 23 of 24 runs on grid A and 20 of 24 on grid
  B (5.2; the leg before: 18 of 24); every loss is Kefka's, after his first
  break, on members at 1 HP (Goner, HyperDrive) or to his Ultima below 10,240.
  The line retries a loss from its boot (`attempts=1/3`). Tried and not
  enough besides 5.1's: Life 3 (`l3`, `l3b`, `l3c`), the Wall Rings off
  (`lrbw`), a higher cure line (`lrb6`), the break's hold (`ph`).
- **Kefka at 16 shields**, the owner's want, once the fight passes every draw at
  12 (5.1).
- **What a player does next**: heal the Wall Ring wearers, whom no cure
  reaches (a Potion's 250 is all they get), and keep a point in the curers'
  banks through a break; or more damage in the first break. Neither is built.
- **STRAGO's options** (#512): his nuke lore never reaches his turns
  (`v039-kefka-tower-2/pg0`: "actor=1 char=7 plan=fight" every turn, no lore
  line at all, so a rule ahead of the nuke repertoire decides first); Kefka's
  fight sets no nuke lore, so it does not touch this leg; not investigated.
