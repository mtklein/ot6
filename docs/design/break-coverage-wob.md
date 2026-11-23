# Break coverage — the World of Balance species the route met on the floor (#254)

> **Class names.** Written under the four weapon classes (slash, pierce, bludgeon,
> special ¤). Since v0.51 (#566) there are six (Sword, Dagger, Spear, Katana, Blunt,
> Ranged): slash became Sword or Katana, pierce Dagger, Spear or Ranged, bludgeon Blunt
> or Ranged, special Ranged or Blunt, each species keeping its number of weapon
> weaknesses. Each table's row column and the hands named with their weapon below are in the
> six classes' names, as `ot6_hud.asm` ships them; a "floor" column and the dated
> reasoning keep the names of the day.

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

TERRA (MithrilKnife: dagger; Fire).

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$046` Vaporite | a wisp | 5 | 15 | fire\|holy | bolt | 2 · bludg | **1** · dagger\|blunt |

The floor's bludgeon was a key she does not hold. One shield: the hit that
breaks it is the hit that kills it, and both her knife and her Fire key it.

## 2. The Figaro desert and the plains to South Figaro (world groups 1, 12, 3, 5)

TERRA (knife: dagger; Fire), LOCKE (MithrilBlade: sword), EDGAR (Mithril
Pike: spear; AutoCrossbow: ranged; Bio Blaster: poison), from `world-figaro-v1`.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$05C` Sand Ray | a flat fish | 6 | 67 | ice\|water (+poison) | — | 2 · slash | 2 · dagger |
| `$023` FossilFang | bones | 20 | 1399 | fire\|ice\|holy\|water | poison | 4 · pierce | **3** · blunt\|spear |
| `$015` Rhinotaur | a horned hide | 8 | 232 | (+poison) | bolt | 3 · slash | **2** · blunt\|ranged |
| `$012` Rhodox | a small beast | 7 | 119 | (+poison) | — | 2 · slash | 2 · sword\|dagger |
| `$0A8` GreaseMonk | a slick brawler | 8 | 132 | poison | — | 3 · bludg | **2** · dagger\|blunt |

Lesson: TERRA's knife keys the Sand Ray, the Rhodox and the GreaseMonk,
LOCKE's blade the Rhodox, EDGAR's AutoCrossbow the Rhinotaur, and his Bio
Blaster keys the plains (poison, vanilla or added) except the FossilFang,
which drinks it and whose bones turn the blades and the knife: the rare
tank takes EDGAR's pike, and is read, not swung at. The
Rhinotaur and GreaseMonk floor rows (slash, bludgeon) were keys only one
hand or none held; Sabin's party, which meets the Rhinotaur after the Veldt,
keys it with his fists.

## 3. The cave between Figaro Castle and South Figaro (map 72)

The same three.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$063` Bleary | an eye | 7 | 119 | fire | — | 2 · slash | 2 · dagger |
| `$062` Crawly | a soft worm | 7 | 122 | fire | — | 2 · slash | 2 · sword\|blunt |
| `$02E` Hornet | a pest | 6 | 92 | fire | — | 2 · pierce | **1** · dagger\|ranged |

Lesson: every body is fire-weak, so TERRA's Fire is the cave's master key;
the class cell splits the eye (TERRA's knife) from the worm (LOCKE's
blade), the first place the party reads the cell to pick a target; the
Hornet takes the knife and EDGAR's AutoCrossbow.

## 4. Mt. Kolts (map 98; maps 99 and 102 deal the same pool)

TERRA and LOCKE (MithrilBlades: sword; Fire), EDGAR (pike: spear; poison),
from `kolts-summit-v1`.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$032` Trilium | a flower | 9 | 147 | fire | water | 3 · slash | **2** · sword\|dagger |

Cut the stalk or stab it; Fire still burns it, and it still drinks water.
Two shields matches the mountain's other trash (the Kolts block).

## 5. LOCKE and CELES out of South Figaro (map 87; maps 69 and 70)

LOCKE (two daggers: dagger, the leg's own `ok:` line), CELES (a blade:
sword). Map 87 is met again in the World of Ruin by CELES, EDGAR and SABIN
(`wor-figaro-sweep-v1`: two blades, Fire Knuckles).

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$011` Commander | an imperial officer | 10 | 102 | poison | — | 3 · pierce | **2** · sword\|dagger |
| `$071` Vector Pup | a hound | 11 | 166 | fire | — | 3 · slash | **2** · sword\|dagger |
| `$094` Primordite | a soft primitive body | 11 | 145 | bolt | — | 3 · bludg | **2** · sword\|blunt |
| `$036` Trilobiter | a shell | 12 | 150 | — | — | 3 · pierce | **2** · dagger\|blunt |
| `$0F5` Gold Bear | the cave's tank | 13 | 275 | — | — | 3 · slash | 3 · sword\|blunt |

Lesson: the two hands split the cave. The basement's soldiers take both;
the shell takes only LOCKE's point; the soft body and the bear only CELES's
blade. The floor's Primordite row (bludgeon) was a key neither held.

## 6. The Phantom Train (maps 141, 142, 145)

SABIN (MetalKnuckle: blunt; Fire Dance, AuraBolt: fire, holy), CYAN (Ashura:
katana), SHADOW (Imperial: dagger), from `camp-escaped-v1`.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$008` Hazer | a spirit | 12 | 120 | holy | — | 3 · slash | **2** · blunt\|katana |
| `$00E` Whisper | a spirit | 12 | 230 | fire\|holy | poison | 3 · slash | **2** · blunt\|katana |
| `$0BA` StillGoing | a walking body | 12 | 200 | fire\|holy | poison | 3 · slash | **2** · blunt\|katana |

Lesson: holy, CYAN's katana and SABIN's fists key every ghost, the train
weapon-classes.md names ("holy + slash featured", slash through v0.50);
SHADOW's dagger keys none of them. Hazer and Whisper also ride the train's
hallway (map 151) and map 149, which play has not claimed yet (#286).

## 7. Narshe's back way with BANON (map 48)

TERRA (Fire), EDGAR (pike: spear; poison), BANON (a rod: blunt), at
`terra_clifftop`; and LOCKE, EDGAR, SABIN and MOG meet the guards' formation
on the `water_rondo` leg (`water-rondo-v1`: knife, Blizzard, Poison Claw,
pike).

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$0EF` 1st Class | a guard in plate | 11 | 180 | poison | — | 3 · pierce | **2** · blunt\|ranged |
| `$0F4` Wild Rat | a rat | 12 | 160 | fire | poison | 3 · slash | **2** · sword\|dagger |

Lesson: the Bio Blaster keys the guard and heals the rat beside him, which
TERRA's Fire keys; BANON's rod and EDGAR's AutoCrossbow dent the guard's
plate. On the `water_rondo` leg the knife and the Blizzard key the rat and
the AutoCrossbow the guard.

## 8. The plains between Narshe, Kohlingen, Jidoor and Zozo (world groups 9, 10, 11, 13)

Two parties: to Zozo, LOCKE (knives: dagger), EDGAR (pike: spear; poison),
SABIN (Kaiser: blunt; fire, holy), CELES (RegalCutlass: sword), from
`zozo-outside-v1`; to Narshe after the Opera, LOCKE (knife), EDGAR
(Blizzard: sword, ice), SABIN (Poison Claw: katana), SETZER (Cards: ranged),
from `narshe-mission-v1`.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$078` Red Fang | a wolf | 14 | 325 | (+poison) | — | 3 · slash | **2** · katana\|spear |
| `$02A` Vulture | a flier | 15 | 412 | wind | — | 3 · slash | **2** · dagger\|ranged |
| `$090` Over-Grunk | the plains' tank | 15 | 492 | fire | — | 3 · slash | 3 · blunt\|katana |
| `$08C` Mind Candy | a magic moth | 15 | 290 | fire\|wind | — | 3 · slash | **2** · sword\|ranged |

Lesson: the flier falls to LOCKE's knife and the AutoCrossbow, not the
blade (weapon-classes.md's "pierce-weak fliers" for this stretch, pierce
through v0.50); the moth takes SETZER's cards and the blades, the first
trash his hand is made for; the Red Fang takes EDGAR's pike or SABIN's
claw; the Over-Grunk is the tank, for SABIN's fists or claw.

## 9. The south continent round Albrook (world groups 14, 21, 15)

TERRA (Break Blade: sword; Fire, Ice), LOCKE (ThunderBlade: sword, bolt),
from `banquet-done-v1` and `crescent-landing-v1` (SHADOW joins the second:
dagger). EDGAR and SABIN fight the same formation before the banquet.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$07B` Ralph | a beast | 17 | 620 | (+poison) | — | 4 · slash | **2** · sword\|dagger |
| `$081` Wyvern | a dragon | 18 | 892 | ice | — | 4 · pierce | **3** · sword\|dagger |
| `$08D` WeedFeeder | a grazer | 17 | 480 | fire\|wind | — | 4 · slash | **2** · sword\|ranged |
| `$06B` Joker | a conjurer, in threes | 17 | 467 | bolt\|poison | — | 4 · slash | **2** · sword\|blunt |

Lesson: the blades key every body (the floor's pierce-only Wyvern did not
key the two blades that walk here); the Wyvern is the three-shield dragon,
like the Floating Continent's, and Ice its element. The Joker (world group
15, which the banquet's grind fights: formation 148, three Jokers) takes the
blades and Blunt (special through v0.50); LOCKE's ThunderBlade reaches its bolt.
Group 15 also deals the ChickenLip, whose row is the side-zones branch's
(wt/v043-wob-zones).

## 10. The plains and forest round Thamasa (world groups 22, 23, 24)

TERRA (Blizzard: sword, ice), LOCKE (ThunderBlade: sword, bolt), STRAGO
(Fire Rod: blunt, fire), from `esper-mtn-save-v1`.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$096` Cephaler | a winged crawler | 21 | 420 | bolt | — | 4 · slash | **2** · sword\|dagger |
| `$01F` Chimera | a many-headed beast | 22 | 2237 | (+poison) | — | 4 · slash | 4 · sword\|ranged |
| `$01D` Baskervor | a hound | 22 | 750 | (+poison) | — | 4 · slash | **2** · sword\|dagger |

Lesson: LOCKE's ThunderBlade keys the Cephaler twice (its blade and its
bolt); the Chimera keeps the miniboss-grade four; the Baskervor, a hound
like the Vector Pup, is trash at two (the line fights its formation 191 on
the `esper_mtn_save` leg). (#279's side trip reaches
world groups 25 and 22; these rows are this doc's.)

## 11. Esper Mountain (maps 372, 375)

TERRA, LOCKE and STRAGO as above, and RELM (Chocobo Brush: blunt) from
`thamasa-done-v1`.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$0EE` Mandrake | a root | 23 | 1150 | fire | water | 4 · slash | **2** · sword\|blunt |
| `$0D0` Insecare | an insect's shell | 23 | 977 | fire\|wind | — | 4 · pierce | **2** · dagger\|blunt |
| `$0EB` Abolisher | a beast | 24 | 860 | — | — | 5 · slash | **2** · sword\|spear |
| `$0D6` Adamanchyt | the mountain's wall | 24 | 1305 | — | — | 5 · bludg | 5 · dagger\|blunt |
| `$0B8` Slurm | an ooze | 23 | 505 | fire | — | 4 · bludg | **2** · blunt\|ranged |

Lesson: the insect, the shell and the ooze turn the blades the party
carries and take STRAGO's rod and RELM's brush, on the mountain she joins.
The floor's Insecare row (pierce) was a key no hand
here held; its Fire weakness was the only answer. The Adamanchyt keeps the floor's
five, above the house curve, for `battle_breakfour`'s measurement: TERRA's
3-BP Break takes four shields, which is told from three and five only on a
body holding five, and this is the pool the suite plays (TERRA learns Break
here, at level 24). The suite went red when this doc's first draft gave the
shell three:
`build/attempts/wt/v043-wob-rows/gate/suite_battle_breakfour.red.log`, "the
counted cast within 12 tries: got false"). (#283 covers the
mountain's full pool and map 374; these five rows are this doc's.)

## 12. The Floating Continent (map 393)

TERRA (Break Blade), LOCKE (two Blizzards: sword, ice), EDGAR (ThunderBlade,
Epee: sword, bolt), and CELES or SHADOW, from `fc-landing-v1` and
`fc-alcove-v1`.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$169` Naughty | a demon | 24 | 3000 | fire\|bolt\|holy | ice | 5 · slash | **3** · sword\|ranged\|spear |

The pool's elite at the elite's three, like the Behemoth and the Dragon,
and three classes like the pool's other magic bodies (Apokryphos, Misfit,
Brainpan: sword, dagger, blunt); the blades key it.
It still drinks ice, which the party's Blizzards carry: the hit that chips
it heals it.

## The event fights (v0.45, sections 13-18)

Authored 2026-11-14 (wt/v045-rows). The v0.45 design audit
(`build/attempts/wt/design-audit/shield_coverage.txt`) listed 25 species in
formations with no authored row. Fourteen are in formations the game deals:
event battles a script calls, and one pool the route has not claimed. The
other eleven are in none. Sections 13-17 design the fourteen; section 18
classifies the rest. `battle_breakwob_events` checks every row and every
party's key from the built ROM. `battle_breakwob_raft`,
`battle_breakwob_raiders` and `battle_breakwob_siegfried` play the fights
from the graph's captures and check each gauge and a break by the party.
`tools/check_shield_rows.py` now holds the gate: every species in a reachable
formation has a row. On main's table that count was 14
(`build/attempts/wt/v045-rows/coverage-on-main.txt`).

Hands are read from the tracked checkpoints' gear and the generators'
seating: `sabin-done-v1` (TERRA's MithrilBlade, EDGAR's Mithril Pike,
BANON's Punisher), `gen_narshe_battle`'s three squads, `banquet-done-v1` and
`camp-escaped-v1`.

## 13. The Lete River's raft (event battles 7 and 8)

TERRA (MithrilBlade: sword; Fire), EDGAR (Mithril Pike: spear;
AutoCrossbow: ranged; the Bio Blaster's poison), BANON (Punisher: blunt), and SABIN (fists: blunt;
AuraBolt: holy) on the upper river. The upper ride's `if_rand` fights are
battles 7 and 8. The lower ride from the hub (`gen_rapids`) forces battle 8:
two Pterodons three times in four, or a Nautiloid, an Exocite and a
Pterodon.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$022` Pterodon | a winged reptile | 12 | 380 | fire | — | 3 · pierce | **2** · sword\|ranged |
| `$038` Nautiloid | a shell | 11 | 236 | fire\|bolt | water | 3 · pierce | **2** · blunt\|ranged |
| `$039` Exocite | a crab | 11 | 196 | fire\|bolt | water | 3 · pierce | **2** · sword\|blunt |

Lesson: each hand, TERRA's blade, EDGAR's AutoCrossbow and the blunt of
BANON's rod and SABIN's fists, keys two of the three bodies; EDGAR's pike
keys none, and TERRA's Fire keys all three. On the floor all three took
only EDGAR's pike.

## 14. The sparkle trap in Narshe's caves (map 49, battle 38)

The same three (TERRA, EDGAR, BANON), in the block maze `gen_terra_clifftop`
solves. Touching one of the eight sparkles (`NPCProp::_49`, `_cce486`)
starts battle 38 and puts the party back at the maze's start. The line
never touches one.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$060` Dark Side | a spirit | 13 | 255 | fire\|holy | poison | 3 · slash | **2** · sword\|ranged |
| `$0B6` Spectre | a phantom that casts | 13 | 235 | fire\|holy | poison | 3 · slash | **2** · blunt\|ranged |
| `$0CF` Rinn | a wisp | 11 | 110 | fire\|holy | poison | 3 · slash | **1** · blunt\|ranged |

Lesson: EDGAR's AutoCrossbow keys every spirit, TERRA's blade the Dark Side
and BANON's rod the Spectre and Rinn; TERRA's Fire takes them all, and the
Bio Blaster heals them. Map 48 next door teaches the same thing with the
Wild Rat.
Rinn is a pest at 110 HP and gets one shield. The sparkles stay in the maze
after this visit, so any later party that walks it can trip the trap and
meets the same three with its own hands.

## 15. The Battle for Narshe's raiders (battles 22 and 23)

Three squads: TERRA, EDGAR and CELES (blades: sword; pike: spear;
AutoCrossbow: ranged; Fire, Ice), CYAN and SABIN (katana: katana; fists:
blunt; AuraBolt), LOCKE and GAU (knife and fangs: dagger). Battle 22 is Trooper ×4,
or one time in four Bounty Man and two Troopers. Battle 23 is Fidor and a
Trooper, or one time in four a HeavyArmor and two Troopers. In every draw of
the v0.45 lab, party 1's descent fought Fidor's formation three times
(`build/attempts/wt/v045-rows/narshe-*.txt`).

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$079` Bounty Man | hired muscle | 13 | 285 | fire | — | 3 · slash | **2** · sword\|dagger\|katana |
| `$01C` Fidor | the troopers' war hound | 13 | 355 | fire | — | 3 · slash | **2** · sword\|dagger\|katana |

Lesson: every raider takes the troopers' keys, so each squad's hands carry
over from one wave to the next. The lab ran `gen_narshe_battle` unchanged
at seed shifts 0-23 from the graph's `reunion_ready`. Every arm passed all 24
runs, which were 6 distinct plays, each with three Fidor fights. Fidor's
first draft was pierce|bludg, so that the swords would slide off it. On that
ROM the descent broke Fidor with HP left in 2 of the 18 distinct fights,
against 6 on main's floor row (3 · slash). The swords are most of party 1's
blows. With the troopers' keys the descent breaks it in 6 of 18 again, and
its fights are shorter: 1900 frames on average, against 2077 on main and
2292 on the draft (`narshe-base.txt`, `narshe-after-pb.txt`,
`narshe-after-sp.txt`, `summary.txt`).

A squad that marches bare-handed (SABIN and GAU, if the player gives them
no blade or spear) still holds a key against Fidor, Bounty Man and the
Troopers: GAU's fangs are a Dagger. SABIN's fists key none of them. Under
the four classes that squad held no key (fists were bludgeon).

## 16. The banquet's sparring troopers (battle 30)

The banquet runs before the roster is rewritten, so the bout is fought by
`vector-crash-v1`'s party: TERRA (ThunderBlade: sword, bolt; Fire), LOCKE
(MithrilKnife: dagger), EDGAR (Blizzard: sword, ice; AutoCrossbow: ranged;
Bio Blaster: poison) and SABIN (Poison Claw: katana, poison; Fire Dance,
AuraBolt). During the banquet's free time a trooper offers a two-minute bout
(`_cc8a47`). The canon banquet talks instead.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$0C2` Sp.Forces | the imperial elite | 21 | 700 | poison | — | 4 · pierce | **3** · sword\|spear |

A tank's three, in a timed bout: TERRA's and EDGAR's blades and the Bio
Blaster's poison key it; LOCKE's knife, SABIN's claw and the AutoCrossbow do
not.

## 17. The Phantom Train: the vestibule car and Siegfried

SABIN, CYAN and SHADOW, as section 6.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$00F` Over-Mind | a spirit | 13 | 390 | fire\|holy | poison | 3 · slash | **2** · ranged\|katana |
| `$131` Siegfried | a braggart | 7 | 100 | — | — | 2 · slash | **1** · dagger\|blunt\|katana |

Over-Mind is the vestibule car's own body (map 149, pool 71, with Hazer,
Whisper and StillGoing), and it takes CYAN's katana and SHADOW's thrown
stars (ranged). Siegfried is
the boastful swordsman whose trap in the compartment car (map 153, (5,25),
battle 109) the line walks past. He has 100 HP and is no boss
(bosses-wob.md section 8). Any real blow kills him, so any weapon breaks him
with its first blow, which fits the world's greatest swordsman. His opening
flurry of eight blows is the whole fight, and it is often ended by SHADOW's
Interceptor: the dog's counter (command $02, attack $FD) has no weapon class
and chips nothing. In `battle_breakwob_siegfried`, played from the v045-rows
branch's capture, it killed him from 100 HP on the flurry's last blow before
any member's turn (`f4979 slot 0 ($131) hp 100 -> 0, shields 1, cmd $02 atk
$FD`); on the v0.45 landing's capture a member's Fight killed and broke him
(`f5945 slot 0 ($131) hp 100 -> 0, shields 0, cmd $00 atk $80`). So the
suite asserts the break only when a member's weapon-class hit lands, and on a
classless kill it is a gauge check.

## 18. The bodies with no fight to design

Each of these gets a 0-shield row, so the gap is closed on purpose and none
of them draws a gauge. The three cutscene bodies sit in the table's
"scripted set-pieces" block, beside the WoB Guardian and Tritoch. The other
eleven sit under the label `Ot6ShieldTblUnreached`. `check_shield_rows.py`
refuses a marker there whose species any reachable formation holds, so a
later change that makes one reachable fails the build until the body gets a
designed row.

| id | body | formations | how it is reached | class |
|---|---|---|---|---|
| `$179` | flashback soldier | 485 (391, 496 unused) | `battle 115` (event_main.asm:102366): TERRA's magitek flashback; 1 HP, no action, beamed by the ride | cutscene body |
| `$17A` | the esper Kefka fights | 392 (497, 498 unused) | `battle 97` (:76957): casts Fire 1-3 at Kefka, then `battle_event`, `end_battle` | cutscene body |
| `$17B` | the battle-event runner | 384-386, 389, 393 (390, 510 unused) | `battle 121`, `122`, `123`, `105`, `127` (:46108, :46194, :44391, :76604, :33565): untargetable, plays the scene, ends the battle | cutscene body |
| `$10F` | Umaro (a duplicate) | 443 | battle 74: no call site; the cave's Umaro is `$110` | unreachable |
| `$11A` | Kefka (a duplicate) | 453, 562 | battle 83: no call site; 562 in no group; the final battle's Kefka is `$12A` | unreachable |
| `$136` | Colossus | 461, 560 | battle 91: no call site; pool 66 only on maps 157 and 167 (Mobliz, Mt. Crescent), neither battle-enabled | unreachable |
| `$137` | CzarDragon | 561 | in no group | unreachable |
| `$13B` | B.Day Suit | 42 | in no group | unreachable |
| `$16E` | (Terra's flashback AI) | 499 | battle 51: no call site | dummy |
| `$170` | (Cyan at the camp) | 500 | battle 52: no call site | dummy |
| `$172` | (Gau back from the Veldt) | 502 | battle 54: no call site; Gau's return runs on character AI `$0a` (battle_main.asm) | dummy |
| `$177`, `$178` | (unused) | 508, 509 | battles 60, 61: no call site | dummy |
| `$17F` | (unused) | 490-495 | in no group | dummy |

"No call site" means no `battle N` in any event or vehicle script
(event_cmd.inc's one macro emits $4c, $4d and $cf). No engine-coded
battle names the group either (the magitek train's 41, 73 and 144, the
airship's 93). No monster-in-a-box holds it, and no `change_battle` or
CondBattle substitute reaches the formation. The check reads all of these
from the tree.

## Evidence

`build/attempts/wt/v043-wob-rows/rows/` (px13): the twelve suites PASS on
the authored ROM (`green/verdicts.txt`), FAIL on main's ROM (`red-main/`,
every row missing) and on one mutant ROM with a mutation per suite
(`mutate.py`, `mutant/`: each suite red with the line its mutant names);
`audit.before.txt` / `audit.after.txt`: no area claimed by the play
before this landing lists an unauthored species after. The landing's own
replay claims world group 15 (`gate/audit.final.txt`), which added the
Joker (section 9) and the ChickenLip (the side-zones branch's row).

v0.45 (sections 13-18), `build/attempts/wt/v045-rows/` (px13). The graph's
line was replayed on the branch's ROM from power-on to `reunion_ready`, with
`wob_train_specter` beside it. The raft fights of `gen_scenario` and
`gen_rapids` played the new rows, and every leg passed. The three play suites
pass from those captures (`v045-rows-labs.tgz`, `suites/`), and each fails on
main's ROM at its gauge check (`v045-base-labs.tgz`, `neg_*`: "got 3 ($3),
want 2 ($2)" for the raft, "got 2 ($2), want 1 ($1)" for Siegfried).
`battle_breakwob_events` fails on main's ROM with 132 mismatches
(`suite_events_on_main_rom.log`). It also fails on a mutant that gives Fidor
slash|pierce|bludg (`suite_events_mutant_fidor_slash.txt`); that mutant was
made while Fidor's row was pierce|bludg. The `gen_moogle` sweep (shifts
0-23, from `moogle_entry`; TERRA's flashback soldiers now draw no gauge) won
the Marshal with the first squad in every distinct play: 6 of 6 on the
branch, 7 of 7 on main (`moogle-after.txt`, `moogle-base.txt`).
