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
6. **The Megalixir and the curers' last point win every draw measured.** The
   tower's Megalixir, saved for Kefka (owner, 2026-11-07) and drunk when
   Fallen One leaves the party at 1 HP, and the curers keeping one point
   through his break, win 48 of 48 runs of both grids (5.3). The grids share
   fights (`d3_k0_s12` and `d3B_k0_s11` are one, opening key be4C): together
   they hold 32 distinct opening keys and 29 distinct Kefka keys
   (`build/attempts/wt/v040-the-end-4/union_keys.txt`). At 16
   shields he still won 4 of 48 then, so his row stayed at 12.
7. **The Megalixir near the top of the bag.** On the entry the Barrier
   Rings' replay made (plates sha256 214d1cc7) the Megalixir sat at bag
   slot 101, the battle's Item list took 1,260 frames to reach it, and
   twice the member reaching for it fell first; moved up before the climb,
   with one Megalixir in flight at a time, the leg wins 48 of 48 again
   (27 distinct opening keys, 30 distinct Kefka keys: 5.4).
8. **Kefka at 16 shields is not yet every draw.** On the line replayed at
   7080ab2b he lost one key at 16 (be20, twice) where 12 lost none, and
   drinking the Megalixir when two members stand under 35% of their HP, not
   three under 30%, won all 48 runs (5.6); on the line rebased onto main
   (9d6b9b0f) the same leg at 16 loses one Kefka key that 12 wins (be30),
   and both counts lose one third tier (5.7).

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
| 514 | Kefka `$12A` | 71 / 62,000 | none; nulls poison | 16 | slash, pierce, bludgeon, special |

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
- **Kefka takes every hand**, sixteen shields, the most of any boss (#514,
  5.5; twelve until v0.43): the last fight is the whole party's.

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
danger cured at a boost: 5.2; the Megalixir when Fallen One leaves the
party at 1 HP and the curers keeping a point through his break: 5.3; the
Megalixir moved to bag slot 5 before the climb: 5.4), the
ending. It asserts the staff roll and then The End by the code
the game runs (exec watches on `EndingAirshipScene2_ext` and `TheEnd_ext`)
and saves its last state, `wor_kefka.mss`, there. No save point follows
Kefka, so the line ends on that savestate rather than a battery: the graph's
last entry, `wor_kefka`, cuts nothing, and `wor-kt-plates-v1` is a plain cut
now that a leg boots it.

What the leg depends on (#480): the entry contract (the statues beaten,
parties 1 and 3 on their plates, party 2 on 412's save point), twelve
members in the three parties, the bag's floor and its Megalixir, Phoenix and Kirin owned and
worn by nobody with STRAGO and LOCKE in party 2, a Cure caster and a Life
caster among the twelve once the stones are on, and the three standing
after the care. The curers who keep their last point through Kefka's
break (5.3) are read from the party there, not listed: each member whose
Magic holds Cure or Life by what it has learned or the stone it wears (on
v0.42's line "[curers] TERRA (Cure, Life), CELES (Cure), STRAGO (Life),
LOCKE (Cure), SHADOW (Cure, Life), SABIN (Cure)": SABIN's Starlet joins the
five the list named).

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
Two more (#515, `build/attempts/wt/polish-kefka/px13/negs.sh`, from the
graph's v0.42 `wor-kt-plates-v1`): with Phoenix's owned bit cleared, "stone
26 for STRAGO: owned, unworn (worn by nil), STRAGO in party 2: got false";
with every actor's learned Cure and Life cleared, every esper taken off and
the stones off, "[curers] none" and "a Cure caster () and a Life caster ()
among the three parties for Kefka's Fallen One ...: got false".

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

**Two driver levers, measured and removed** (on the v0.39 capture, the
Girl first; v040-the-end-4 took them out of the code): the
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
  was cast twice in 24 runs. The ward (`buffVs` taking Life at two points)
  was taken out of the driver after the measurement (v040-the-end-4).
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
  cure. `opts.phaseHold` and the cure's break tail (`lrbt`'s
  `breakTail`) were taken out of the driver (v040-the-end-4).
- **What still loses** (`dflt`, `dfltB`): five of 48, all Kefka's, after the
  first break: Goner and HyperDrive on members at 1 HP (the Wall Ring
  wearers, whom only a Potion reaches, and members whose banks the break
  emptied), or his Ultima answering the last hits below 10,240.

The line's own play under the committed leg: "[end] 24 cinematics, the last
airship scene at f151316, The End at f152030", "PASS (frame 152633)
attempts=1/1" (`end1`).

### 5.3 The Megalixir and the curers' last point (fourth round)

Evidence is under `build/attempts/wt/v040-the-end-3/` (`tally_<arm>.txt`,
`lab/`, `pre/`, `jobs_*.txt`, `chain.log`), px13, the rows' ROM (7f1aba0d),
both grids (A: shifts 0, 1, 4, 5, 8, 9, 12, 13; B: 2, 3, 6, 7, 10, 11, 14,
15; K = 0, 2, 4), 48 runs an arm.

**What the losses were** (5.2's `dflt`, `dfltB`). Fallen One is Kefka's
opener whenever he stands at 32,640 HP or more (`AIScript::_298`), and it
sets HP to 1 (special effect $40, `TargetEffect_40`). After it the members
at 1 HP died to his Battle and Special before any break, or the break's burst
left every bank empty, and HyperDrive (every hit under 30,080), Goner (each
cycle under 32,640) and Ultima (hits under 10,240) took them (`dflt_k0_s8`:
TERRA at 0 BP through the window, then "not curing entity 0 (2944/6309):
$2D restores 965"; `fostB_k0_s6`: Ultima on four members, three at 1 HP,
with Kefka at 10,149).

**The bag.** The tower's Megalixir (chest bit 222) was opened in
gen_wor_kt_guardian and drunk in its battle 13 ("party item $EF: 2 members
inside their round"). The owner's ruling: Megalixirs are saved for Kefka's
fight and used there. The driver spends a Megalixir only in a fight whose
options say `opts.megalixir` (`M.MEGALIXIR`: the care lines and the care
race's bag), and gen_wor_kefka's opens it only while Kefka stands (the first
cut let the care lines drink it in the battle's first formation,
`void/m_k0_s0_megalixir_tier1`) and drinks it when three seated members
stand under 30% of their HP. The tower from gen_wor_kt_guardian on was
replayed in order under the rule (`chain.sh`, from the stocked chain's
wor-kt-atma-v1, sha256 665d7330): "c_guardian ... PASS (frame 243499)
attempts=1/3" through "c_plates ... PASS (frame 2315) attempts=1/3"
(`chain.log`), the plates' capture sha256 1648cc80. gen_wor_kt_guardian
without the Megalixir across shifts 1-15 (`lab/gd_s*`): 15 of 15 PASS, no
Megalixir drunk. The leg asserts the Megalixir at its boot; red on the
capture before the rule (`lab/negmega`): "a Megalixir in the bag for Kefka
(0), saved since gen_wor_kt_guardian's chest: got false, want true".

| arm | the lever (on 5.2's leg) | boot | runs won (A + B) | Kefka lost (keys) | tier 3 lost |
|---|---|---|---|---|---|
| `dflt` (5.2) | the leg before | 44ff430f | 23 + 20 | 5 (4) | 0 |
| `fo` | Fallen One out of the hit ledger (`TO_ONE_OUT`) | 44ff430f | 23 + 21 | 4 (4) | 0 |
| `st` | Starlet on RELM (from SABIN), summoned as care (`careSummon`), Phoenix's Rebirth on two fallen | 44ff430f | 21 + 21 | 6 (6) | 0 |
| `fost` | `fo` + `st` | 44ff430f | 23 + 22 | 3 (3) | 0 |
| `fsrb` | `fost` + the curers' last point (`reserveBank`) | 44ff430f | 24 + 23 | 1 (1) | 0 |
| `fssf` | `fost` + CELES's Safe on the party (`buffVs`) | 44ff430f | 19 + 18 | 11 (11) | 0 |
| `m` | the Megalixir | 1648cc80 | 23 + 24 | 1 (1) | 0 |
| `mf` | `m` + `fsrb`'s levers | 1648cc80 | 22 + 23 | 1 (1) | 2 |
| `mfm` | `mf` + Mute cured on RELM (`muteCure`) | 1648cc80 | 21 + 22 | 2 (2) | 3 |
| `mr` | `m` + `fo` + the curers' last point | 1648cc80 | 24 + 24 | 0 | 0 |
| **`mrb`** | **`m` + the curers' last point** | 1648cc80 | **24 + 24** | 0 | 0 |
| **`d3`** | **the leg as committed (`mrb`'s levers)** | 1648cc80 | **24 + 24** | 0 | 0 |
| `k16` | `d3`, Kefka at 16 shields (ROM ccf835ca) | 1648cc80 | 22 + 22 | 4 (3) | 0 |

Quoted (`tally_<arm>.txt`): "Kefka's battle: 24 runs; won 23, lost 1, other
0; distinct opening keys won 19, lost 1" and "won 21, lost 3 ... won 16,
lost 3" (`fo`, `foB`); "won 21, lost 3 ... won 17, lost 3", "won 21, lost 3
... won 19, lost 3" (`st`, `stB`); "won 23, lost 1 ... won 19, lost 1", "won
22, lost 2 ... won 19, lost 2" (`fost`, `fostB`); "won 24, lost 0 ... won 20,
lost 0", "won 23, lost 1 ... won 20, lost 1" (`fsrb`, `fsrbB`); "won 19, lost
5 ... won 17, lost 5", "won 18, lost 6 ... won 17, lost 6" (`fssf`,
`fssfB`); "won 23, lost 1 ... won 21, lost 1", "won 24, lost 0 ... won 23,
lost 0" (`m`, `mB`); "won 22, lost 2 ... won 18, lost 2", "won 23, lost 1
... won 19, lost 1" (`mf`, `mfB`); "won 21, lost 3 ... won 17, lost 3", "won
22, lost 2 ... won 18, lost 2" (`mfm`, `mfmB`); "won 24, lost 0 ... won 22,
lost 0", "won 24, lost 0 ... won 23, lost 0" (`mr`, `mrB`, and the same for
`mrb`, `mrbB`, `d3`, `d3B`; on this case-insensitive disk `mrb`'s tally
overwrote `tally_mrB.txt`, so the two are retallied from `lab/` as
`v040-the-end-4/tally_mr_gridB.txt` and `tally_mrb_gridA.txt`; `d3`'s and
`d3B`'s tiers read "4 Kefka: won 24, lost 0;
distinct keys won 17, lost 0" and "won 24, lost 0; distinct keys won 20,
lost 0", every tier "lost 0"); "won 22, lost 2 ... won 21, lost 2" twice
(`k16`, `k16B`: "4 Kefka: won 22, lost 2; distinct keys won 16, lost 2",
"... won 19, lost 2").

- **The Megalixir** after Fallen One puts the four back at full HP and MP
  ("actor=0 Megalixir on the party: 4 seated members under 30% of their HP,
  in place of its fight", then "e0:6313/6313 ... e3:4940/4940",
  `m_k2_s0`). Its one loss: the break took him to 6,381, and the Goner and
  Meteor block and Ultima met a party whose banks the burst had emptied.
- **The curers' last point**: while Kefka is Broken, TERRA, CELES, SHADOW,
  LOCKE (Kirin) and STRAGO (Phoenix) attack at a boost that leaves one
  point, so a boosted Cure or Life 2 is there when the window ends
  (`opts.reserveBank`). Alone it took the old boot from 45 to 47 of 48
  (`fost` to `fsrb`); with the Megalixir, 48 of 48.
- **Not kept**: Fallen One out of the hit ledger (it priced every later
  round at full HP and refused Fenix Downs, but fixing it moved nothing
  measurable: `mr` = `mrb`); Starlet on RELM summoned as care (the summon
  reaches the Wall Ring wearers, about 1,800 each from RELM, but RELM
  without Ragnarok loses third tiers, `mf`, and came to Kefka Muted so she
  could not summon, "magic row nil" in `dg_k4_s5`; curing her Mute, `mfm`,
  did no better); CELES's Safe (its turns cost more than it saves).
- **Kefka at 16 shields** (`k16`): the first three tiers play as `d3`; he
  wins 4 of 48 runs on 3 distinct keys (be4C twice, beB8, be0C), so his row
  stays at 12.

### 5.4 The Megalixir within reach (fifth round)

Evidence is under `build/attempts/wt/v040-the-end-6/grid/`
(`tally_<arm>_A.txt`, `tally_<arm>_B.txt`, `lab/`, `pre/`, `jobs_*.txt`,
`megal.txt`), px13, the rows' ROM (7f1aba0d), the plates' capture of
v040-the-end-5's replay (sha256 214d1cc7, which bought the Guardian's two
Barrier Rings at Thamasa), both grids, 48 runs an arm.

**What the losses were** (v040-the-end-5's `d5`, `d5B`: "won 24, lost 0
... won 21, lost 0" and "won 22, lost 2 ... won 19, lost 2"). The bag at
this entry holds two Megalixirs at slot 101. Fallen One left the four at 1
HP, the Megalixir was chosen at once ("actor=2 Megalixir on the party: 4
seated members under 30% of their HP", `d5B_k0_s14`), and the Item list's
walk took the rest of the window ("item steer: row 0 -> 101, walking
fast"; 1,260 frames from plan to confirm in `d5_k0_s0`): Kefka's Battle and
Special killed the member on the way ("went down after its item was
planned"), and the next member to reach for it fell the same way. The same
in `d5B_k4_s6`. In the wins the first cut's 900-frame guard let a second
member drink the second Megalixir before the first had landed, on a party it
had just filled ("hp_net":"0,0,0,0", `d5_k0_s0`).

| arm | the lever (on 5.3's leg) | runs won (A + B) | Kefka lost (keys) | deaths in Kefka's tier (A + B) | runs planning both Megalixirs (`megal.txt`, `megal_d5.txt`) |
|---|---|---|---|---|---|
| `d5` (v040-the-end-5) | the leg before | 24 + 22 | 2 (2) | 38 + 40 | 40 of 48 |
| `r6g` | one Megalixir in flight until it lands or its plan drops | 24 + 22 | 2 (2) | 12 + 23 | 3 of 48 |
| `r6b` | the Megalixir to bag slot 5 before the climb (`H.bagArrange`; `flight` 900, the plan-drop clearing still on) | 24 + 24 | 0 | 5 + 2 | 13 of 48 |
| **`r6`** | **both (the leg as committed)** | **24 + 24** | 0 | 5 + 2 | 0 |

Quoted: "Kefka's battle: 24 runs; won 24, lost 0, other 0; distinct opening
keys won 17, lost 0" and "won 24, lost 0 ... won 20, lost 0" (`r6`,
`tally_r6_A.txt`, `tally_r6_B.txt`; "4 Kefka: won 24, lost 0; distinct keys
won 20, lost 0" and "... won 22, lost 0"; every tier "lost 0"); the same
totals for `r6b`; "won 24, lost 0 ... won 21, lost 0" and "won 22, lost 2
... won 19, lost 2" (`r6g`, the same two losses, `r6gB_k0_s14` and
`r6gB_k4_s6`). Across `r6`'s two grids: 27 distinct opening keys and 30
distinct Kefka keys, every one won.

- **The bag.** gen_wor_kefka's care puts the Megalixir under the heals
  already on top ("slots 0..5 = $E9 $F0 $F5 $EB $EC $EF", one swap, a
  weapon to slot 101), as a player keeps what the last fight needs one
  press away; the walk from plan to confirm is 300 frames (302 to submit) (`r6B_k0_s14`),
  and the Megalixir lands before Kefka's next hits ("hp_net":"5705,4671,
  6357,4669"). `KEFKA_BAG = false` (a lab's) leaves the bag as it came.
- **One in flight.** `opts.megalixir`'s guard holds from the plan until it
  resolves (2,400 frames, `flight`) or its plan drops before the confirm
  (the actor fell). It changes no tally on these grids, but with the bag
  alone 13 of 48 runs drank the second Megalixir on a party the first had
  filled, 1,055 to 1,742 frames after the first was chosen ("hp_net":
  "0,0,0,3128", `r6b_k0_s0`); with it no run of `r6` drinks the second,
  which stays in the bag for a later crisis (in `r6g` a second came only
  after the first's member fell before the confirm, or 3,383 frames later
  on a new crisis, `r6g_k0_s1`). Only gen_wor_kefka sets
  `opts.megalixir`, so no other leg's play moves.

### 5.5 Kefka at 16 shields on v0.42's line (#514)

Evidence is under `build/attempts/wt/polish-kefka/` (`px13/` and `air/`:
`tally_<arm>.txt`, `lab/`, `pre/`, `jobs_*.txt`, `*.head`), the same two
grids (48 runs an arm), from the graph's `wor-kt-plates-v1` capture of
v0.42's line (sha256 addb7578, the tracked save byte for byte: the gear
baseline, leveling move 2, the Evil Oscar fix and the divines all upstream
of it). The order there is "TERRA, CELES, STRAGO, SHADOW, RELM, CYAN, EDGAR,
LOCKE, GOGO, MOG, SETZER, SABIN": RELM, third at v0.40, is fifth now.

| arm | the leg | ROM | runs won | Kefka met / won (keys) | tier 3 lost (keys) | deaths in Kefka's tier |
|---|---|---|---|---|---|---|
| `k12` | main's leg | main's, 12 shields (7a4fd945) | 44 of 48 | 44 / 44 (30) | 4 (3) | 9 |
| **`k16`** | main's leg | **16 shields (ec3a220e)** | 44 of 48 | **44 / 44 (30)** | 4 (3) | 20 |
| `c16` | the curers read from the party (#515) | 16 | 44 of 48 | 44 / 44 (30) | 4 (3) | 20 |
| `m16` | `c16` + the Megalixir open in the third tier too (`vs` the Girl and the Sleep) | 16 | 44 of 48 | 45 / 44 (27 / 1) | 3 (2) | 63 |
| `or16` | `c16` + RELM third (her rod and brush for the Sleep) | 16 | 45 of 48 | 47 / 45 (30 / 1) | 1 (1) | 55 |

Quoted: "4 Kefka: won 44, lost 0; distinct keys won 30, lost 0; deaths in
the tier 9" and "Kefka's battle: 48 runs; won 44, lost 4, other 0; distinct
opening keys won 26, lost 3" (`px13/tally_k12.txt`); "4 Kefka: won 44, lost
0; distinct keys won 30, lost 0; deaths in the tier 20" and the same battle
line (`px13/tally_k16.txt`, `air/tally_c16.txt`); "4 Kefka: won 44, lost 1;
distinct keys won 27, lost 1; deaths in the tier 63" (`air/tally_m16.txt`).
Every arm's "3 lady+sleeper: won 44, lost 4; distinct keys won 26, lost 3"
(`m16`: "won 45, lost 3"). `or16`: "3 lady+sleeper: won 47, lost 1; distinct
keys won 30, lost 1; deaths in the tier 105; ticks 10000-24494", "4 Kefka:
won 45, lost 2; distinct keys won 30, lost 1; deaths in the tier 55",
"Kefka's battle: 48 runs; won 45, lost 3" (`px13/tally_or16.txt`).

- **On this boot Kefka at 16 held wherever he was met.** At 16 he lost none
  of the 44 runs that reached him, on 30 distinct Kefka keys, as at 12; the
  first three tiers play byte for byte as at 12 (the same four runs lost,
  the same keys). He costs more at 16: 20 deaths in his tier across the
  grids against 9. The line replayed since moved the boot (5.6).
- **What loses is the third tier, at 12 and at 16 alike**: four runs on
  three tier-3 keys (be2C twice, beA8, be34), the four members killed by
  the Sleep's Meteo two at a time ("[death] f+14458 entity 1 char 6 from
  667/5539 by slot 3 cmd $0C atk $DF" and entity 2 in the same frame,
  `k16_k2_s4`) and its Special, after Condemned on SHADOW ("entity 3 char 3
  from 3179/4956 by nobody", twice, `k16B_k0_s6`). The tier is twice as long
  as at v0.40 (16,181-38,741 ticks against 7,945-22,065, `tally_r6_*`) with
  188 deaths against 109. That is a regression of the line upstream (the
  front four's levels and HP: CELES L63 5,539 against L68 6,313, RELM 4,942
  against 6,358), not of Kefka's row. On the line replayed for this
  change the order puts RELM third and the tier is no longer lost (5.6).
- **Not kept**: the Megalixir in the third tier (`m16`): the crises there
  come as Meteo's double kills, faster than the 30% trigger; it turned one
  losing key's run into a win (`m16B_k0_s6`, by the care lines' party item:
  "party item $EF: 3 members inside their round"), but drinking it there
  left Kefka without it and he won one run (`m16_k4_s13`, 9 deaths in his
  tier). The curers read from the party (`c16`) add SABIN (Starlet) to the
  five and moved nothing: `c16`'s tallies are `k16`'s.
- **RELM third** (`or16`) puts the third tier back in v0.40's shape (105
  deaths, 10,000-24,494 ticks, one run lost) but meets Kefka on a key he
  wins at 16 only with the stock order: be78, lost twice at 16 ("tier 4
  Kefka LOST after 7166 ticks, 4 deaths", `or16_k0_s8`, `or16B_k0_s7`: Fallen
  One, CELES fell reaching for the Megalixir and his Fire 3 took TERRA and
  STRAGO at 1 HP before the second landed) and won at 12 on the same draws
  ("tier 4 Kefka WON after 21311 ticks, 6 deaths, key be78", `or12_k0_s8`,
  `or12B_k0_s7`; `or12_k2_s9` lost the same third tier as `or16_k2_s9`). So
  16 is thinner than 12 with Kefka, though on the line's own order it
  decides no draw.

### 5.6 The line replayed, and the Megalixir at two under 35% (#514)

The line replayed from power-on at 7080ab2b (`land/land.out`: "gate: GREEN
-- ninja -k 0 -j16 exited 0") moved from `wor-colosseum-v1` on (main's
play, not this change: main's de4ee995 makes the same `wor-colosseum-v1`
capture, sha256 f7e8fbaa, from the same boot, `land/attr.log`), and its
`wor-kt-plates-v1` (sha256 0d979170) puts RELM third: "TERRA, CELES, RELM,
STRAGO, SHADOW, CYAN, EDGAR, LOCKE, GOGO, MOG, SETZER, SABIN". From that
capture, both grids, 48 runs an arm (`px13/tally_f16.txt`,
`air/tally_f12.txt`, `px13/tally_f15.txt`, `mbp/tally_mxn2.txt`):

| arm | ROM | the Megalixir | runs won | Kefka lost (keys) | deaths in Kefka's tier |
|---|---|---|---|---|---|
| `f12` | 12 shields | three under 30% | 48 of 48 | 0 | 23 |
| `f16` | 16 | three under 30% | 46 of 48 | 2 (1: be20) | 60 |
| `f15` | 15 | three under 30% | 47 of 48 | 1 (1: be28) | 43 |
| `mx45` | 16 | three under 45% | 46 of 48 | 2 (1: be20) | 61 |
| **`mxn2`** | **16** | **two under 35%** | **48 of 48** | **0** | 47 |

Quoted: "4 Kefka: won 48, lost 0; distinct keys won 26, lost 0; deaths in
the tier 23", "Kefka's battle: 48 runs; won 48, lost 0" (`f12`); "4 Kefka:
won 46, lost 2; distinct keys won 26, lost 1; deaths in the tier 60",
"Kefka's battle: 48 runs; won 46, lost 2, other 0; distinct opening keys
won 23, lost 1" (`f16`); "4 Kefka: won 47, lost 1; distinct keys won 25, lost
1; deaths in the tier 43" (`f15`, `px13/tally_f15.txt`: be28, a key 16 won,
so 15 is no safer than 16); "4 Kefka: won 48, lost 0; distinct keys won 26,
lost 0; deaths in the tier 47", "Kefka's battle: 48 runs; won 48, lost 0,
other 0; distinct opening keys won 24, lost 0" (`mxn2`). Every arm's third
tier: "3 lady+sleeper: won 48, lost 0; distinct keys won 29, lost 0".

- **What lost at 16** (`f16_k4_s4`, `f16B_k4_s3`, one fight): the first
  Megalixir after Fallen One, then his Special on CELES from full ("ONE
  ACTION from >= 80%"), and below 10,240 his Ultima answered the party's
  hits on three members at about a fifth of their HP ("[death] f+14286
  entity 0 char 0 from 1167/5995 by slot 0 cmd $02 atk $14", and entities 1
  and 3 in the same frame) while the second Megalixir, planned at three
  under 30%, was still on its way. At 12 the same draw was won with no death
  ("tier 4 Kefka WON after 17579 ticks, 0 deaths, key be20", `f12_k4_s4`).
- **Two under 35%** drinks before the third member is in Ultima's reach: 36
  runs drink one Megalixir, 11 both, one a second by the care lines
  (`mbp/megal_mxn2.txt`), and be20 is won with no death ("tier 4 Kefka WON
  after 20116 ticks, 0 deaths, key be20", `mxn2_k4_s4`). The leg's trigger
  is now that; the second Megalixir is still only ever drunk in Kefka's
  tier. Three under 45% (`mx45`, `air/tally_mx45.txt`: "4 Kefka: won 46,
  lost 2; distinct keys won 26, lost 1") loses be20 as before: the third
  member is the one Ultima finds.

### 5.7 On the line rebased onto main (#514)

The branch rebased onto main (e3f989e4: the Death counters, the batched
emulator) and replayed from power-on at 9d6b9b0f (`land2/land2.out`: "gate:
GREEN -- ninja -k 0 -j16 exited 0"); every tracked save "none" against it
(`land2/drift2_before.txt`, 70 keys and the two negatives), so the play to
`wor-kt-plates-v1` (sha256 e59f809b) is main's own, and the order is
"TERRA, CELES, STRAGO, RELM, CYAN, SHADOW, EDGAR, LOCKE, MOG, GOGO, SETZER,
SABIN". Both grids from it, the leg as committed (the Megalixir at two
under 35%):

| arm | ROM | runs won | third tier lost (keys) | Kefka met / won (keys lost) | deaths in Kefka's tier |
|---|---|---|---|---|---|
| `g12` | 12 shields | 47 of 48 | 1 (be50) | 47 / 47 | 16 |
| `g16` | 16 | 46 of 48 | 1 (be50) | 47 / 46 (be30) | 30 |

Quoted: "4 Kefka: won 47, lost 0; distinct keys won 26, lost 0; deaths in
the tier 16", "Kefka's battle: 48 runs; won 47, lost 1, other 0; distinct
opening keys won 27, lost 1" (`air/tally_g12.txt`); "4 Kefka: won 46, lost
1; distinct keys won 25, lost 1; deaths in the tier 30", "Kefka's battle:
48 runs; won 46, lost 2, other 0; distinct opening keys won 26, lost 2"
(`px13/tally_g16.txt`); both "3 lady+sleeper: won 47, lost 1".

- **be30 at 16** (`g16_k0_s13`): the first Megalixir confirmed while STRAGO
  fell from 1 HP, the second planned, and then his Special took CELES from
  5,102 and CYAN from 5,840 of 5,840 ("ONE ACTION from >= 80%"); at 12 the same
  draw "tier 4 Kefka WON after 19175 ticks, 4 deaths, key be30"
  (`g12_k0_s13`). The four more shields keep him in his cycle longer, and
  his Special, not Fallen One or Ultima, decides this one.
- **be50** (`g16B_k0_s2`, `g12B_k0_s2`): the third tier lost at both counts
  ("LOST after 24250 ticks, 8 deaths").

## 6. Not done

- **Kefka at 16 on every draw** (#514): at 16 he loses one key on each of
  the last two lines that 12 wins (be20, closed by the Megalixir at two
  under 35%; be30, open), so 16 does not yet pass every draw; the decision
  between 16 and 12 is the owner's (5.7).
- **The third tier with STRAGO third.** On v0.42's capture the strongest
  first put STRAGO third and RELM fifth, and the lady and the sleeper took
  4 of 48 runs at either shield count (5.5); the replayed line puts RELM
  third and loses none. The order is decided by a level and HP tie-break,
  so a later replay can bring the STRAGO order back; a rule that keeps a
  bludgeon and a special for the Sleep in front was measured only as RELM
  third (`or16`), not made.
- **STRAGO's options** (#512): his nuke lore never reaches his turns
  (`v039-kefka-tower-2/pg0`: "actor=1 char=7 plan=fight" every turn, no lore
  line at all, so a rule ahead of the nuke repertoire decides first); Kefka's
  fight sets no nuke lore, so it does not touch this leg; not investigated.
