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
| Grenade `$0AA` | the bomb isle (27) | 17 / 3,000 | weak ice, water; absorbs fire; answers a Fight with Exploder (its own HP) | 3 | pierce, bludgeon | a broken body does not counter, so the Fight that breaks it draws no Exploder: break it in one swing (LOCKE's boosted knife did it in both of the replay's meetings, "KEYED: Fight at 1 BP lands 4 chip(s)"), or use what it does not answer, EDGAR's tools (pierce) and SABIN's blitzes (bludgeon). The blades stay off it, so a blade's Fight is the one that draws the explosion |
| Intangir `$0A3` | Triangle Island (124, 28) | 26 / 32,000 | absorbs every element; starts Vanished, Hasted, Shelled, Safe, Floating; Meteo on its turn after a hit, Meteo as it dies, escapes under 1,280 HP | 2 | slash, pierce, bludgeon, special | absorbs every element, so every class keys it, SETZER's special among them (the trip his airship opens), but a blade that carries an element heals it (EDGAR's Blizzard, SABIN's Poison Claw): LOCKE's knife, EDGAR's tools, SABIN's blitzes and SETZER's cards break it. Its Meteo and its escape run through its turns, and a broken body has none (`Ot6Gate`; nor counters, the CheckRetal hook): break it to bring it down. Two shields, under the house curve's miniboss count, because its Meteo takes the whole L18-22 four that first meets it; with two, one double strike breaks it again as it recovers (section 3) |

`battle_breakwob_sidetrips` checks the four rows in the built ROM, their
vanilla weak and absorb bytes, that every species of world groups 20, 17,
18, 15, 26 (the other groups that deal the Bug and the ChickenLip), 27, 124
and 28 has a key in the hands of the four that first meets it, and the
lessons (the Grenade takes pierce and bludgeon and not slash; the Intangir
still absorbs every element and takes every hand the islands' four hold).

## 3. The play

Each leg walks a lap of two tiles in one encounter group (`K.worldHunt` on
the world map, `K.hunt` on a field map, `lib/ot6_field.lua`) until every
formation of the pool has been won; the pool is asserted equal to the ROM's,
and the hunt fails at the worst case of the encounter counters' draws
(`M.worstCaseEncounters`). The walker plays every battle with the fight
driver; nothing is fled.

The labs below booted the tracked saves on the branch's ROM, so they are
strategy evidence; the qualified play is section 5's replay.

| leg | lab | battles | formations won | levels after |
|---|---|---|---|---|
| forest | `lab/forest_f1.log` | 6, all won | 65, 66, 68, 69 | SABIN L14, CYAN L14, SHADOW L12 |
| train | `lab/train_t2.log` | 11, all won | 72, 80, 90 | SABIN L14, CYAN L14, SHADOW L13 |
| Esper Mountain | `lab/espermtn_e3.log` | 11 (4 and 7), all won | 164-169 | TERRA L26, LOCKE L27, STRAGO L27, RELM L24 |

What the labs taught:

1. **The Adamanchyt pair sneezes a Fighting party out of the battle.**
   Formations 165 (Adamanchyt x2) and 164 (Adamanchyt beside two Slurms;
   `AIScript::_214`: Sneeze for every Fight) ended 7 battles "PARTY LEFT ...
   4 of 4 seated fled" while the four Fought (`lab/espermtn_e1_fight_sneezed.log`:
   5 in formation 165, 2 in 164). The leg's driver casts instead of Fighting
   where a member can pay (`nuke = { Bolt, Ice, Fire }`, gen_fc_landing's
   shape), and the pair fell with two of four sneezed out
   (`lab/espermtn_e3.log`). The pair's row is #254's; its lesson (magic, not
   steel) is worth keeping there.
2. **The Intangir starts Vanished, and nothing the driver did could touch it.**
   Every Fight, Tool and Blitz missed, and the magic line found no spell
   (`magic-only: no line ... absorb $FF`): 100,000 frames at 32,000 HP
   (`lab/airship_a8.log`). A spell that lands ends Vanish, absorbed or not, so
   the fight driver now casts one when every standing body is Vanished and no
   spell would hurt it (`Driver:revealLine`, `M.REVEAL_SPELLS`: SABIN's Ice
   from SHIVA, EDGAR's Slow from BISMARK). It does not cast while a standing
   body is under Reflect or holds an enemy Runic, and it answers a Tool or a
   Blitz only when it is a classed blow that misses (AutoCrossbow, Pummel),
   not a classless one that lands (Bio Blaster, Flash) (`battle_vanish` part 4).
3. **The party's elemental blades healed the Intangir.** EDGAR's Blizzard (ice)
   and SABIN's Poison Claw (poison) Fought it 137 times for 0 in one meeting
   (`lab/intangir2_s16.log`, key be74). The fight driver now counts a hand
   whose element the target absorbs as no chip, and turns that Fight into the
   member's other verb (EDGAR's tool, SABIN's Pummel), else the magic line,
   else an item (`Driver:absorbWeaponPlan`; `battle_vanish` part 4c, red with
   `M.ABSORB_WEAPON_GUARD = false`). It is inert where no standing body drinks
   a weapon's element, but that is not only off the story's path: in the
   replay at dbc09160 it fired on the main line too, in gate_cave_save (2
   turns), vector_crash (1), wor_tritoch (2), wor_phoenix (2), wor_locke (1)
   and wor_kt_guardian (1) ("no Fight: slot ... absorbs the hand's element"),
   so it moves those legs' play and is part of the checkpoint drift the
   re-cut answers. It changes the verb rather than re-aiming the Fight at a
   body that does not absorb, and it reads the ROM's absorb byte rather than
   the live slot's; both are a follow-up issue.
4. **With that fixed, two shields hold and three and four do not.** The
   Triangle Island hunt from `terra-returned-v1` (LOCKE L21, EDGAR L21, SABIN
   L22, SETZER L18: the levels the island first sees) at seed shifts 0, 4, 8,
   12, 16 and 20 (`lab2/`):

   | shields | Intangir meetings (distinct battle keys) | won | wipes |
   |---|---|---|---|
   | 4 (`intangir4_k*.log`) | 15 (15) | 12 | 3 |
   | 3 (`intangir3_m*.log`) | 16 (15: beEC-g00D2 twice) | 13 | 3 |
   | 2 (`intangir2_n*.log`) | 18 (16) | 18 | 0 |

   Every wipe is the same: the Intangir recovers, the first hits that re-chip
   it arm its Meteo before the break lands, and the Meteo takes all four from
   full (`intangir4_k0.log`: "[death] ... atk $DF (ONE ACTION from >= 80%)",
   four times in one action). With two, one double strike re-breaks it. One
   member falls in most meetings to the Meteo it casts as it dies (the death
   counter is not a turn; 2 to 5 deaths a hunt of three meetings), and the
   field care revives them.

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

- `replay3/`: the play from power-on at 84d9daa2 (rebased on main's e3f989e4,
  emulator pin ot6-2.2.1-7) on px13: "gate: GREEN -- ninja -k 0 -j 4 exited 0"
  (`gate.log`), with each leg's log. Every battle won, none fled by choice; the
  same counts as the dbc09160 replay (`replay2/`):

  | leg | battles (distinct keys) | not clean |
  |---|---|---|
  | `wob_forest_hunt` | 6 (6) | - |
  | `wob_train_hunt` | 11 (11) | - |
  | `wob_south_hunt` | 15 (14) | the Bug's spine petrified a member (cured after the battle) |
  | `wob_airship_hunt` | 23 (22) | - |
  | `wob_esper_mtn_hunt` | 11 (11) | the Adamanchyts sneezed members out of 2 battles; both won |

  Levels after: SABIN L14, CYAN L14, SHADOW L12-13 (forest, train); CELES L20,
  LOCKE L20, EDGAR L21, SABIN L21 (south); LOCKE L23, EDGAR L23, SABIN L23,
  SETZER L19 (airship); TERRA L25, LOCKE L28, STRAGO L26, RELM L24 (Esper
  Mountain). `suite_battle_breakwob_sidetrips.log`, `suite_battle_vanish.log`
  and `suite_battle_ragedriver.log`: PASS. Checkpoint drift before the re-cut:
  43 of 70 tracked keys drifted (`before.txt`); after `--recut`, 70 of 70
  "none" (`after.txt`). `replay2/` is the round before, at dbc09160 on
  de4ee995.
- `rows2/`: the shipped `battle_breakwob_sidetrips` red on main's rows
  (`main.log`: "$0E8 Bug has no Ot6ShieldTbl row (want 2, class $03)" and seven
  more), on the Grenade keyed by slash (`mut_grenade_slash.log`: "$0AA Grenade
  class mask $07, want $06"), on the Intangir without special
  (`mut_intangir_nospecial.log`: "$0A3 Intangir class mask $07, want $0F") and on
  the Grenade's vanilla fire absorb cleared (`mut_grenade_absorb.log`: "$0AA
  Grenade absorb byte $00, want vanilla $01"); PASS on the rows (`rows.log`).
- `lab2/`: the Intangir's shield counts and the battle_vanish and
  battle_ragedriver runs of this round; `lab/`: the first round's strategy runs
  (section 3); `replay/`: the first round's replay at 5c2357b9.
