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

## 9. The south continent round Albrook (world groups 14, 21, 15)

TERRA (Break Blade: slash; Fire, Ice), LOCKE (ThunderBlade: slash, bolt),
from `banquet-done-v1` and `crescent-landing-v1` (SHADOW joins the second:
pierce). EDGAR and SABIN fight the same formation before the banquet.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$07B` Ralph | a beast | 17 | 620 | (+poison) | — | 4 · slash | **2** · slash\|pierce |
| `$081` Wyvern | a dragon | 18 | 892 | ice | — | 4 · pierce | **3** · slash\|pierce |
| `$08D` WeedFeeder | a grazer | 17 | 480 | fire\|wind | — | 4 · slash | **2** · slash\|bludg |
| `$06B` Joker | a conjurer, in threes | 17 | 467 | bolt\|poison | — | 4 · slash | **2** · slash\|special |

Lesson: the blades key every body (the floor's pierce-only Wyvern did not
key the two blades that walk here); the Wyvern is the three-shield dragon,
like the Floating Continent's, and Ice its element. The Joker (world group
15, which the banquet's grind fights: formation 148, three Jokers) takes the
blades and, as a conjurer, special; LOCKE's ThunderBlade reaches its bolt.
Group 15 also deals the ChickenLip, whose row is the side-zones branch's
(wt/v043-wob-zones).

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

TERRA (MithrilBlade: slash; Fire), EDGAR (Mithril Pike: pierce; the Bio
Blaster's poison), BANON (Punisher: bludg), and SABIN (fists: bludg;
AuraBolt: holy) on the upper river. The upper ride's `if_rand` fights are
battles 7 and 8. The lower ride from the hub (`gen_rapids`) forces battle 8:
two Pterodons three times in four, or a Nautiloid, an Exocite and a
Pterodon.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$022` Pterodon | a winged reptile | 12 | 380 | fire | — | 3 · pierce | **2** · slash\|pierce |
| `$038` Nautiloid | a shell | 11 | 236 | fire\|bolt | water | 3 · pierce | **2** · pierce\|bludg |
| `$039` Exocite | a crab | 11 | 196 | fire\|bolt | water | 3 · pierce | **2** · slash\|bludg |

Lesson: each of the three weapon hands keys two of the three bodies, and
TERRA's Fire keys all three. On the floor all three took only EDGAR's
pike.

## 14. The sparkle trap in Narshe's caves (map 49, battle 38)

The same three (TERRA, EDGAR, BANON), in the block maze `gen_terra_clifftop`
solves. Touching one of the eight sparkles (`NPCProp::_49`, `_cce486`)
starts battle 38 and puts the party back at the maze's start. The line
never touches one.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$060` Dark Side | a spirit | 13 | 255 | fire\|holy | poison | 3 · slash | **2** · slash\|special |
| `$0B6` Spectre | a phantom that casts | 13 | 235 | fire\|holy | poison | 3 · slash | **2** · bludg\|special |
| `$0CF` Rinn | a wisp | 11 | 110 | fire\|holy | poison | 3 · slash | **1** · pierce\|special |

Lesson: each spirit takes one of the three weapon hands, TERRA's Fire takes
them all, and the Bio Blaster heals them. Map 48 next door teaches the same
thing with the Wild Rat. All three take special, like the train's spirits.
Rinn is a pest at 110 HP and gets one shield.

## 15. The Battle for Narshe's raiders (battles 22 and 23)

Three squads: TERRA, EDGAR and CELES (blades: slash; pike and AutoCrossbow:
pierce; Fire, Ice), CYAN and SABIN (katana: slash; fists: bludg; AuraBolt),
LOCKE and GAU (knife: pierce; bare hands: bludg). Battle 22 is Trooper ×4,
or one time in four Bounty Man and two Troopers. Battle 23 is Fidor and a
Trooper, or one time in four a HeavyArmor and two Troopers. In every draw of
the v0.45 lab, party 1's descent fought Fidor's formation three times
(`build/attempts/wt/v045-rows/narshe-*.txt`).

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$079` Bounty Man | hired muscle | 13 | 285 | fire | — | 3 · slash | **2** · slash\|pierce |
| `$01C` Fidor | the troopers' war hound | 13 | 355 | fire | — | 3 · slash | **2** · slash\|pierce |

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

## 16. The banquet's sparring troopers (battle 30)

TERRA (Break Blade: slash; Fire) and LOCKE (ThunderBlade: slash, bolt), from
`banquet-done-v1`. During the banquet's free time a trooper offers a
two-minute bout (`_cc8a47`). The canon banquet talks instead.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$0C2` Sp.Forces | the imperial elite | 21 | 700 | poison | — | 4 · pierce | **3** · slash\|pierce |

The trooper line's keys, at a tank's three: three of them against two
blades in a timed bout.

## 17. The Phantom Train: the vestibule car and Siegfried

SABIN, CYAN and SHADOW, as section 6.

| id | body | L | HP | vanilla weak | absorbs | floor | authored |
|---|---|---|---|---|---|---|---|
| `$00F` Over-Mind | a spirit | 13 | 390 | fire\|holy | poison | 3 · slash | **2** · slash\|special |
| `$131` Siegfried | a braggart | 7 | 100 | — | — | 2 · slash | **1** · slash\|pierce\|bludg |

Over-Mind is the vestibule car's own body (map 149, pool 71, with Hazer,
Whisper and StillGoing), and it gets the train's spirit row. Siegfried is
the boastful swordsman whose trap in the compartment car (map 153, (5,25),
battle 109) the line walks past. He has 100 HP and is no boss
(bosses-wob.md section 8). Any real blow kills him, so any weapon breaks him
with its first blow, which fits the world's greatest swordsman. His opening
flurry of eight blows is the whole fight, and it is often ended by SHADOW's
Interceptor: the dog's counter (command $02, attack $FD) has no weapon class
and chips nothing. In `battle_breakwob_siegfried`, played from the graph's
capture, it killed him from 100 HP on the flurry's last blow before any
member's turn (`f4979 slot 0 ($131) hp 100 -> 0, shields 1, cmd $02 atk
$FD`), so on that draw the suite sees his gauge and no break.

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
