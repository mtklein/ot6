# Break coverage — the World of Balance species the route met on the floor (#254)

Authored 2026-11-12. `python3 tools/audit_break_coverage.py` listed 35
species (and the Baskervor below, which the line meets in world group 24
while the audit still counts that group unclaimed), inside the World of Balance areas the route has fought (the tuning
claim), that still rode the generated floor (`ot6_break_floor.inc` classes
and `2 + level/8` shields): the issue's 67 less those authored since by the
Veldt (#269) and other arcs. This doc designs them area by area in the shape
of [break-coverage-gate.md](break-coverage-gate.md). One `@suite` per area,
`tools/tests/battle_breakwob_<area>.lua`, re-verifies the rows from the built
ROM; section numbers here are the suites' `section N`.

## Rules for every area

- **Vanilla element bits stay untouched ✦**, and so do the poison adds
  `Ot6ElemAddTbl` already gives seven of these bodies (Sand Ray, Rhodox,
  Rhinotaur, Chimera, Baskervor, Red Fang, Ralph). Each suite asserts the weak and
  absorb bytes and the add.
- **House curve**: 1 pests, 2 trash, 3 tanks, 4 miniboss-grade. The floor
  gave these bodies 2-5 shields by level; at 3 and up the break lands on a
  corpse (the Mt. Kolts block's finding in `ot6_hud.asm`), so trash is 2.
- **The party holds a key**: each row keys at least one hand of every party
  the route seats there. The hands are read from the tracked checkpoints'
  gear (`build/attempts/wt/v043-wob-rows/rows/`, `gear.py`) and from the
  battle logs' `[board]` lines (who fought which formation). Each area
  teaches something (its lesson), and the suite checks the lesson.
- The rows are one block in `Ot6ShieldTbl` (`ff6/src/battle/ot6_hud.asm`,
  "the world of balance: the species the route met on the floor").

Hands below: weapon class first, then the elements the party's spells,
tools and weapons reach.

## 1. The Narshe mines, TERRA alone (map 50; map 42 deals the same pool)

TERRA (MithrilKnife: pierce; Fire).

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$046` Vaporite | a wisp | 5 | 15 | fire\|holy | bolt | 2 · bludg | **1** · pierce\|bludg |

The floor's bludgeon was a key she does not hold. One shield: the hit that
breaks it is the hit that kills it, and both her knife and her Fire key it.

## 2. The Figaro desert and the plains to South Figaro (world groups 1, 12, 3, 5)

TERRA (knife: pierce; Fire), LOCKE (MithrilBlade: slash), EDGAR (Mithril
Pike: pierce; Bio Blaster: poison), from `world-figaro-v1`.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$05C` Sand Ray | a flat fish | 6 | 67 | ice\|water (+poison) | — | 2 · slash | 2 · slash\|pierce |
| `$023` FossilFang | bones | 20 | 1399 | fire\|ice\|holy\|water | poison | 4 · pierce | **3** · pierce\|bludg |
| `$015` Rhinotaur | a horned hide | 8 | 232 | (+poison) | bolt | 3 · slash | **2** · pierce\|bludg |
| `$012` Rhodox | a small beast | 7 | 119 | (+poison) | — | 2 · slash | 2 · slash\|pierce |
| `$0A8` GreaseMonk | a slick brawler | 8 | 132 | poison | — | 3 · bludg | **2** · pierce\|bludg |

Lesson: EDGAR's pike keys every body here, and his Bio Blaster keys the
plains (poison, vanilla or added) except the FossilFang, which drinks it and
whose bones turn the blade: the rare tank is read, not swung at. The
Rhinotaur and GreaseMonk floor rows (slash, bludgeon) were keys only one
hand or none held; Sabin's party, which meets the Rhinotaur after the Veldt,
keys it with his fists.

## 3. The cave between Figaro Castle and South Figaro (map 72)

The same three.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$063` Bleary | an eye | 7 | 119 | fire | — | 2 · slash | 2 · pierce |
| `$062` Crawly | a soft worm | 7 | 122 | fire | — | 2 · slash | 2 · slash\|bludg |
| `$02E` Hornet | a pest | 6 | 92 | fire | — | 2 · pierce | **1** · slash\|pierce |

Lesson: every body is fire-weak, so TERRA's Fire is the cave's master key;
the class cell splits the eye (the point: TERRA, EDGAR) from the worm (the
edge: LOCKE), the first place the party reads the cell to pick a target.

## 4. Mt. Kolts (map 98; maps 99 and 102 deal the same pool)

TERRA and LOCKE (MithrilBlades: slash; Fire), EDGAR (pike: pierce; poison),
from `kolts-summit-v1`.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$032` Trilium | a flower | 9 | 147 | fire | water | 3 · slash | **2** · slash\|pierce |

Cut the stalk or stab it; Fire still burns it, and it still drinks water.
Two shields matches the mountain's other trash (the Kolts block).

## 5. LOCKE and CELES out of South Figaro (map 87; maps 69 and 70)

LOCKE (two daggers: pierce, the leg's own `ok:` line), CELES (a blade:
slash). Map 87 is met again in the World of Ruin by CELES, EDGAR and SABIN
(`wor-figaro-sweep-v1`: two blades, Fire Knuckles).

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$011` Commander | an imperial officer | 10 | 102 | poison | — | 3 · pierce | **2** · pierce\|slash |
| `$071` Vector Pup | a hound | 11 | 166 | fire | — | 3 · slash | **2** · slash\|pierce |
| `$094` Primordite | a soft primitive body | 11 | 145 | bolt | — | 3 · bludg | **2** · slash\|bludg |
| `$036` Trilobiter | a shell | 12 | 150 | — | — | 3 · pierce | **2** · pierce\|bludg |
| `$0F5` Gold Bear | the cave's tank | 13 | 275 | — | — | 3 · slash | 3 · slash\|bludg |

Lesson: the two hands split the cave. The basement's soldiers take both;
the shell takes only LOCKE's point; the soft body and the bear only CELES's
blade. The floor's Primordite row (bludgeon) was a key neither held.

## 6. The Phantom Train (maps 141, 142, 145)

SABIN (MetalKnuckle: bludg; Fire Dance, AuraBolt: fire, holy), CYAN (Ashura:
slash), SHADOW (Imperial: pierce), from `camp-escaped-v1`.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$008` Hazer | a spirit | 12 | 120 | holy | — | 3 · slash | **2** · slash\|special |
| `$00E` Whisper | a spirit | 12 | 230 | fire\|holy | poison | 3 · slash | **2** · slash\|special |
| `$0BA` StillGoing | a walking body | 12 | 200 | fire\|holy | poison | 3 · slash | **2** · slash\|bludg |

Lesson: holy and CYAN's katana key every ghost, the train weapon-classes.md
names ("holy + slash featured"). The two spirits take special (#347, "Special
(¤) is a common key"; a WoB Setzer or Relm who comes back here keys them);
the walking body takes SABIN's fists. Hazer and Whisper also ride the train's
hallway (map 151) and map 149, which play has not claimed yet (#286).

## 7. Narshe's back way with BANON (map 48)

TERRA (Fire), EDGAR (pike: pierce; poison), BANON (a rod: bludg), at
`terra_clifftop`; and LOCKE, EDGAR, SABIN and MOG meet the guards' formation
on the `water_rondo` leg (`water-rondo-v1`: knife, Blizzard, Poison Claw,
pike).

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$0EF` 1st Class | a guard in plate | 11 | 180 | poison | — | 3 · pierce | **2** · pierce\|bludg |
| `$0F4` Wild Rat | a rat | 12 | 160 | fire | poison | 3 · slash | **2** · slash\|pierce |

Lesson: the Bio Blaster keys the guard and heals the rat beside him, which
TERRA's Fire keys; BANON's rod dents the guard's plate.

## 8. The plains between Narshe, Kohlingen, Jidoor and Zozo (world groups 9, 10, 11, 13)

Two parties: to Zozo, LOCKE (knives: pierce), EDGAR (pike: pierce; poison),
SABIN (Kaiser: bludg; fire, holy), CELES (RegalCutlass: slash), from
`zozo-outside-v1`; to Narshe after the Opera, LOCKE (knife), EDGAR
(Blizzard: slash, ice), SABIN (Poison Claw: slash), SETZER (Cards: special),
from `narshe-mission-v1`.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$078` Red Fang | a wolf | 14 | 325 | (+poison) | — | 3 · slash | **2** · slash\|pierce |
| `$02A` Vulture | a flier | 15 | 412 | wind | — | 3 · slash | **2** · pierce |
| `$090` Over-Grunk | the plains' tank | 15 | 492 | fire | — | 3 · slash | 3 · slash\|bludg |
| `$08C` Mind Candy | a magic moth | 15 | 290 | fire\|wind | — | 3 · slash | **2** · slash\|special |

Lesson: the flier falls to the point and not the edge (weapon-classes.md's
"pierce-weak fliers" for this stretch); the moth takes SETZER's cards, the
first trash his hand is made for; the Over-Grunk is the tank.

## 9. The south continent round Albrook (world groups 14, 21)

TERRA (Break Blade: slash; Fire, Ice), LOCKE (ThunderBlade: slash, bolt),
from `banquet-done-v1` and `crescent-landing-v1` (SHADOW joins the second:
pierce). EDGAR and SABIN fight the same formation before the banquet.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$07B` Ralph | a beast | 17 | 620 | (+poison) | — | 4 · slash | **2** · slash\|pierce |
| `$081` Wyvern | a dragon | 18 | 892 | ice | — | 4 · pierce | **3** · slash\|pierce |
| `$08D` WeedFeeder | a grazer | 17 | 480 | fire\|wind | — | 4 · slash | **2** · slash\|bludg |

Lesson: the blades key every body (the floor's pierce-only Wyvern did not
key the two blades that walk here); the Wyvern is the three-shield dragon,
like the Floating Continent's, and Ice its element.

## 10. The plains and forest round Thamasa (world groups 22, 23, 24)

TERRA (Blizzard: slash, ice), LOCKE (ThunderBlade: slash, bolt), STRAGO
(Fire Rod: bludg, fire), from `esper-mtn-save-v1`.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$096` Cephaler | a winged crawler | 21 | 420 | bolt | — | 4 · slash | **2** · slash\|pierce |
| `$01F` Chimera | a many-headed beast | 22 | 2237 | (+poison) | — | 4 · slash | 4 · slash\|pierce |
| `$01D` Baskervor | a hound | 22 | 750 | (+poison) | — | 4 · slash | **2** · slash\|pierce |

Lesson: LOCKE's ThunderBlade keys the Cephaler twice (its blade and its
bolt); the Chimera keeps the miniboss-grade four; the Baskervor, a hound
like the Vector Pup, is trash at two (the line fights its formation 191 on
the `esper_mtn_save` leg). (#279's side trip reaches
world groups 25 and 22; these rows are this doc's.)

## 11. Esper Mountain (maps 372, 375)

TERRA, LOCKE and STRAGO as above, and RELM (Chocobo Brush: special) from
`thamasa-done-v1`.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$0EE` Mandrake | a root | 23 | 1150 | fire | water | 4 · slash | **2** · slash\|bludg |
| `$0D0` Insecare | an insect's shell | 23 | 977 | fire\|wind | — | 4 · pierce | **2** · pierce\|bludg |
| `$0EB` Abolisher | a beast | 24 | 860 | — | — | 5 · slash | **2** · slash\|pierce |
| `$0D6` Adamanchyt | the mountain's wall | 24 | 1305 | — | — | 5 · bludg | 5 · pierce\|bludg |
| `$0B8` Slurm | an ooze | 23 | 505 | fire | — | 4 · bludg | **2** · bludg\|special |

Lesson: the insect, the shell and the ooze turn the blades the party
carries and take STRAGO's rod; the ooze takes RELM's brush too, the
mountain she joins on. The floor's Insecare row (pierce) was a key no hand
here held; its Fire weakness was the only answer. The Adamanchyt stays at five,
above the house curve: TERRA learns Break on this mountain (level 24), and
the shell is the body her boosted Break is read on (a 3-BP Break takes four
of its five; `battle_breakfour` measures it here, and went red when this
doc's first draft gave the shell three:
`build/attempts/wt/v043-wob-rows/gate/suite_battle_breakfour.red.log`, "the
counted cast within 12 tries: got false"). (#283 covers the
mountain's full pool and map 374; these five rows are this doc's.)

## 12. The Floating Continent (map 393)

TERRA (Break Blade), LOCKE (two Blizzards: slash, ice), EDGAR (ThunderBlade,
Epee: slash, bolt), and CELES or SHADOW, from `fc-landing-v1` and
`fc-alcove-v1`.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$169` Naughty | a demon | 24 | 3000 | fire\|bolt\|holy | ice | 5 · slash | **3** · slash\|pierce\|special |

The pool's elite at the elite's three, like the Behemoth and the Dragon;
special like the pool's other magic bodies (Apokryphos, Misfit, Brainpan).
It still drinks ice, which the party's Blizzards carry: the hit that chips
it heals it.

## Evidence

`build/attempts/wt/v043-wob-rows/rows/` (px13): the twelve suites PASS on
the authored ROM (`green/verdicts.txt`), FAIL on main's ROM (`red-main/`,
every row missing) and on one mutant ROM with a mutation per suite
(`mutate.py`, `mutant/`: each suite red with the line its mutant names);
`audit.before.txt` / `audit.after.txt`: no claimed area lists an
unauthored species after.
