# World of Balance: the side trips off the story's path

Issues #279 (the Chimera/Cephaler zones), #280 (Triangle Island and the
Intangir), #282 (the southern forests and the bomb isle), #283 (Esper
Mountain's whole pool and its side cave, map 374) and #286 (the Phantom
Train's hallway and the Phantom Forest's pools), from the World of Balance
coverage audit (`build/attempts/wob-coverage/`: `wob_gap.txt`,
`world0_summary.txt`, `gap_species.txt`). Each is a branch leg off the
World of Balance line at the first point a player can reach the place, and
each walks its zone until every formation of its pool has been won. No leg
boots what they leave: the main line, the middle-path playthrough, does not
move for them (docs/TESTING.md, "the canon playthrough").

Evidence is under `build/attempts/wt/v043-wob-zones/` (section 5 quotes the
lines behind each number).

---

## 1. The legs and where they branch

| leg | boots | party | zones (world group or map) | issue |
|---|---|---|---|---|
| `gen_wob_forest_hunt` | `camp-escaped-v1` (beside forest_done) | SABIN, CYAN, SHADOW | the Phantom Forest's clearing (132, group 68: the springs' pool too) and fork (134, group 69) | #286 |
| `gen_wob_train_hunt` | `train_b68_entry` (gen_sabin_train's capture) | SABIN, CYAN, SHADOW | the passenger car's hallway (151, group 72), through 141's door (59,8) | #286 |
| `gen_wob_south_hunt` | `post-opera-v1` (beside vector_entry) | CELES, LOCKE, EDGAR, SABIN | the forest east of Albrook (group 20), the forest north-west of it (group 17; group 18 by Maranda deals the same pool) | #282 |
| `gen_wob_airship_hunt` | `terra-returned-v1` (beside narshe_mission) | LOCKE, EDGAR, SABIN, SETZER | by the Blackjack: the bomb isle (27), the north isles (22), the plain north of Thamasa (25), Triangle Island (124) | #279 #280 #282 |
| `gen_wob_esper_mtn_hunt` | `ultros-won-v1` (beside thamasa_done) | TERRA, LOCKE, STRAGO, RELM | Esper Mountain's slopes (375, group 90) and the side cave (374, group 89) with its Chocobo Suit | #283 |

Where each branches, and why there:

- **The airship's islands open at `terra-returned-v1`, not after the opera.**
  After the opera the Blackjack sets the party down by Albrook, and its wheel
  does nothing until Setzer's lesson on the deck after the Vector escape
  (`_caf532`: `if_switch $016F=0, EventReturn`; `$016F` is set by
  `_caa6c0`'s "Take a turn at the wheel!"). A lab that boarded the parked
  ship at `post-opera-v1` stood at the wheel for 1,200 frames with no
  lift-off. The first save with the wheel in the party's hands is
  `terra-returned-v1`, the grounded Blackjack at (24,121).
- **The plain north of Thamasa (group 25) is on the same continent as the
  Thamasa arc,** and the line fights one of its formations on the way to
  Esper Mountain (formation 161 in `esper_mtn_save.log`); the airship reaches
  it first, so the leg lands there from the Blackjack.
- **The southern forests are on foot from the opera's landing** (137,203),
  the same continent as Vector and Albrook.
- **Esper Mountain's side cave** opens from the save compartment's middle
  shortcut (`_cbeebe`: 375 (12,46), live once `$0097` is set in the statue
  room) to (39,46), whose compartment holds 374's door (36,41). The line
  takes the shortcut beside it, (11,51), towards 372.
- **The hallway** is the passenger car the line walks past on the train's
  roof (141): its doors (59,8), (66,8), (75,8) and (82,8) load map 151.

None of this is play the canon player needs, and none of it rejoins the
line. The trips are worth making (the islands' XP, the Chocobo Suit), but a
player who skips them loses nothing the story asks for.

## 2. Species and break rows

The split with #254 (the World of Balance species on the generated floor in
areas the line already claims): a species the coverage audit
(`tools/audit_break_coverage.py`) lists in a claimed area is #254's.
That leaves four species first met in these zones and on the generated
floor; every other body here is #254's or already authored (section 4).

The party that first meets the forests is the post-opera four: CELES (the
RegalCutlass: slash), LOCKE (the MithrilKnife: pierce), EDGAR (the Mithril
Pike and AutoCrossbow: pierce) and SABIN (the Kaiser and Pummel: bludgeon).
The islands' party is the four the wheel is handed to: LOCKE, EDGAR (the
Blizzard, a blade: slash; his tools: pierce), SABIN (the Poison Claw: slash;
Pummel: bludgeon) and SETZER (cards and dice: special). Vanilla elements
stay.

| species | where | L / HP | vanilla | shields | classes | why |
|---|---|---|---|---|---|---|
| Bug `$0E8` | forest east of Albrook (20) | 16 / 310 | weak ice, water; alone, it answers a Fight with a petrifying spine | 2 | slash, pierce | a shell on wings: cut or spear it; trash in packs of three to six |
| ChickenLip `$03D` | forests north-west of Albrook and by Maranda (17, 18) | 18 / 545 | weak ice; Quake when alone | 2 | slash, bludgeon | a heavy bird in packs of five: the blade or the fist |
| Grenade `$0AA` | the bomb isle (27) | 17 / 3,000 | weak ice, water; absorbs fire; a Fight makes it explode (Exploder: its own HP) | 3 | pierce, bludgeon | its keys are the hands that are not Fight: EDGAR's tools (pierce) and SABIN's blitzes (bludgeon). A blade's Fight (slash) is the lesson's wrong answer, so slash stays off |
| Intangir `$0A3` | Triangle Island (124, 28) | 26 / 32,000 | absorbs every element; starts Vanished, Hasted, Shelled, Safe, Floating; Meteo on its turn after a hit, Meteo as it dies, escapes under 1,280 HP | 2 | slash, pierce, bludgeon, special | absorbs every element, so every hand but magic breaks it, SETZER's among them (the trip his airship opens). Its Meteo and its escape run through its turns, and a broken body has none (`Ot6Gate`; nor counters, the CheckRetal hook): break it to kill it. Two shields, so one double strike (LOCKE's Genji pair) breaks it again as it recovers, before the turn that would answer the hit (section 3) |

`battle_breakwob_sidetrips` checks the four rows in the built ROM, their
vanilla weak and absorb bytes, that every species of world groups 20, 17,
18, 27, 124 and 28 has a key in the hands of the four that first meets it,
and the lessons (the Grenade takes pierce and bludgeon and not slash; the
Intangir still absorbs every element and takes every hand the islands' four
hold).

## 3. The play

Each leg walks a lap of two tiles in one encounter group (`K.worldHunt` on
the world map, `K.hunt` on a field map, `lib/ot6_field.lua`) until every
formation of the pool has been won; the pool is asserted equal to the ROM's,
and the hunt fails at the worst case of the encounter counters' draws
(`M.worstCaseEncounters`). The walker plays every battle with the fight
driver; nothing is fled.

Every battle every leg met was won, none fled, in the labs below (booted from
the tracked saves on the branch's ROM, so they are strategy evidence; the
qualified play is section 5's replay):

| leg | battles | formations won | levels after |
|---|---|---|---|
| forest | 6, all won | 65, 66, 68, 69 | SABIN L14, CYAN L14, SHADOW L12 |
| train | 11, all won | 72, 80, 90 | SABIN L14, CYAN L14, SHADOW L13 |
| south | 15 (11 and 4), all won | 139-142 (group 20), 145, 149 (group 17) | CELES L21, LOCKE L20, EDGAR L21, SABIN L21 |
| Esper Mountain | 11 (4 and 7), all won | 164-169 | TERRA L26, LOCKE L27, STRAGO L27, RELM L24 |
| airship, Triangle Island only (the lowest levels, straight from the save) | 30 over three seed shifts, all won | 6, 7, 210 | LOCKE L21, EDGAR L21, SABIN L22, SETZER L18, unchanged (the Intangir pays no XP); Fenix Downs 20 to 17 or 18 |

What the labs taught:

1. **The Adamanchyt pair sneezes a Fighting party out of the battle.**
   Formation 165 (Adamanchyt x2, `AIScript::_214`: Sneeze for every Fight)
   ended "PARTY LEFT ... 4 of 4 seated fled" in each of its meetings while
   the four Fought (`lab/espermtn_e1_fight_sneezed.log`, 14 battles left that
   way). The leg's driver casts instead of Fighting where a member can pay
   (`nuke = { Bolt, Ice, Fire }`, gen_fc_landing's shape), and the pair fell
   with two of four sneezed out (`lab/espermtn_e3.log`). The pair's row is
   #254's; its lesson (magic, not steel) is worth keeping there.
2. **The Intangir starts Vanished, and nothing the driver did could touch it.**
   Every Fight, Tool and Blitz missed, and the magic line found no spell
   (`magic-only: no line ... absorb $FF`): 100,000 frames at 32,000 HP
   (`lab/airship_a8.log`). A spell that lands ends Vanish, absorbed or not, so
   the fight driver now casts one when every standing body is Vanished and no
   spell would hurt it (`Driver:dodgePlan`, `M.REVEAL_SPELLS`: SABIN's Ice
   from SHIVA, EDGAR's Slow from BISMARK). Then the four broke it and killed
   it twice.
3. **On four shields the Intangir is a coin flip; on two, a sure thing.**
   With four, the third meeting wiped the four: it recovered, the first hits
   armed its Meteo before the second break, and the Meteo took all four from
   80% (`lab/intangir_i2.log`: `[death] ... atk $DF (ONE ACTION from >= 80%)`).
   With two, nine meetings over seed shifts 0, 8 and 16 (eight distinct battle
   keys) were all won (`lab/intangir2_s0.log`, `_s8`, `_s16`). One member
   falls in most of them, to the Meteo it casts as it dies (the death counter
   is not a turn); the field care revives them.

## 4. What the other bodies here are

The coverage audit's claimed areas hold these zones' other floor bodies, and
#254 authors them (its branch `wt/v043-wob-rows`, `break-coverage-wob.md`):
FossilFang, Ralph and Wyvern (the southern forests), Chimera and Cephaler (the
north isles, the plain north of Thamasa), Mandrake, Insecare, Abolisher,
Adamanchyt and Slurm (Esper Mountain), Hazer, Whisper and StillGoing (the
train). The Phantom Forest's Ghost and Poplium and the bomb isle's Bomb were
authored before.

Not covered by either: the Baskervor (`$01D`, formations 160, 162, 191 on the
Thamasa continent) is still on the generated floor. The line meets it
(formation 191 in `esper_mtn_save.log`), so it was not first met in these
zones, and the audit lists its group as unclaimed, so it is not in #254's
list.

Map 130 (a spring of the Phantom Forest's, the coverage audit's "unvisited")
has no entrance in the forest's maps (route_data: no short or long entrance
leads to it); its pool is group 68, the clearing's, won on 132.

## 5. Evidence

Under `build/attempts/wt/v043-wob-zones/`:

- `replay/`: the play from power-on on the branch's ROM (`gate1.log`, `ninja -k
  0` at 5c2357b9; its one red edge, audit_chests, wanted the Chocobo Suit in
  `tools/chests_opened.txt`), with each leg's log. Every battle won, none
  fled, no member down:

  | leg | battles (distinct keys) | the hunts |
  |---|---|---|
  | `wob_forest_hunt` | 6 (6) | 132: 2 battles; 134: 2 |
  | `wob_train_hunt` | 11 (11) | 151: 11 |
  | `wob_south_hunt` | 15 (14) | group 20: 10; group 17: 2 |
  | `wob_airship_hunt` | 23 (22) | group 27: 10; group 22: 2; group 25: 7; group 124: 4 |
  | `wob_esper_mtn_hunt` | 11 (11) | 375: 4; 374: 7 |

  Levels after: SABIN L14, CYAN L14, SHADOW L12-13 (forest, train); CELES L20,
  LOCKE L20, EDGAR L21, SABIN L21 (south); LOCKE L23, EDGAR L23, SABIN L23,
  SETZER L19 (airship); TERRA L25, LOCKE L27, STRAGO L27, RELM L23 (Esper
  Mountain). `suite_battle_breakwob_sidetrips.log`: PASS.
- `rows/`: `battle_breakwob_sidetrips` red on main's rows (`main.log`: "$0E8 Bug
  has no Ot6ShieldTbl row (want 2, class $03)" and five more), red on the
  Grenade keyed by slash (`mut_grenade_slash.log`: "$0AA Grenade class mask $07,
  want $06") and on the Intangir without special (`mut_intangir_nospecial.log`:
  "$0A3 Intangir class mask $07, want $0F"), PASS on the rows (`rows.log`).
  These ran with the Intangir on four shields; the suite's expectation moved to
  two with the row.
- `lab/`: the strategy runs of section 3.
