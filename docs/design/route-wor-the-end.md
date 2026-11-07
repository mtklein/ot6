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

`gen_wor_kefka` boots `wor-kt-plates-v1` and plays to "The End": the care,
the plate, the order menu, the battle (the tactical driver, the Girl
killed first in the third tier), the ending. It asserts the staff roll and then The End by the code
the game runs (exec watches on `EndingAirshipScene2_ext` and `TheEnd_ext`)
and saves its last state, `wor_kefka.mss`, there. No save point follows
Kefka, so the line ends on that savestate rather than a battery: the graph's
last entry, `wor_kefka`, cuts nothing, and `wor-kt-plates-v1` is a plain cut
now that a leg boots it.

What the leg depends on (#480): the entry contract (the statues beaten,
parties 1 and 3 on their plates, party 2 on 412's save point), twelve
members in the three parties, and the three standing after the care.

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

## 6. Not done

- **Every draw.** The leg wins 20 of 24 runs of the grid (opening keys: 14
  won, 4 lost); the line retries a loss from its boot (`attempts=1/3`). The losses
  are attrition carried across tiers and Kefka's Fallen One answered one
  care turn a round. Levers not yet tried: a care stop between tiers (heal
  before the last body of a tier dies), the order (who starts and who comes
  in), and the supplies (below).
- **Supplies.** The line reaches Kefka with 6 Fenix Downs, 4 Tonics, 86
  Potions and no Elixir (`wor-kt-plates-v1`): the factory leg's Kohlingen
  stop brings Fenix Downs to 20, and the tower spends 14. The band before a
  boss gauntlet is about the level, capped at 20.
- **STRAGO's options** (#512): his nuke lore never reaches his turns
  (`v039-kefka-tower-2/pg0`: "actor=1 char=7 plan=fight" every turn, no lore
  line at all, so a rule ahead of the nuke repertoire decides first); not
  investigated further here.
