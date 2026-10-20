# World of Ruin: Locke (the Phoenix Cave, the Red Dragon)

Milestone v0.32, #268: from the save beside the Falcon at the Fanatics'
Tower (`wor-thamasa-v1`, where v0.31 ends) through the Phoenix Cave, the
Red Dragon and LOCKE's scene, to a save outside Kohlingen with LOCKE seated
(`wor-locke-v1`), the next arc's boot. The cave is split-party:
[split-party.md](split-party.md) has its switches, the order the two parties
take, the library and the first measurements (#275); this doc has the rest
of the arc.

Line numbers are into `ff6/src/event/event_main.asm` unless a file is named.
Evidence is under `build/attempts/wt/v032-locke-arc/` (`data/` read from the
built ROM and the tracked SRAM by `tools/route_data.py` and the scripts
beside them; `rows/` the break-row suite; `lab/` the runs).

## 0. Findings

1. **The scene ends in Kohlingen, not on the Falcon.** `_cc3188` parks the
   Falcon at world (38,48) (`airship_pos`) and loads map 189 (Kohlingen),
   where the leg gets control with CELES and LOCKE alone in party 1 and
   party switching off (`$01CE`); the others wait in the Falcon's cabin. The
   scene gives an X-Potion, a Fenix Down, an X-Ether, an Elixir, a Flame
   Shld and a ValiantKnife, and LOCKE joins with nothing on.
2. **LOCKE joins at L41** (`norm_lvl`: the mean of the available
   characters), six to nine under the four who fly on (TERRA L49, CELES L50,
   RELM L47) and level with the bench (SABIN, CYAN, MOG, UMARO L37-39).
3. **The Wing Edge is past a pit.** Its chest (315 (24,43), bit 172) stands
   beyond a floor that gives way (315 (24,44), `_cc280e`: the party drops to
   313 (25,44)); the step at 315 (23,49) lays a bridge for good (`_cc284b`,
   `$02A5`). It is LOCKE's: blunt (the boomerang class), attack 198, no row
   penalty, the best weapon he can hold on arrival.
4. **Five of the cave's chests are empty in the ROM**: 315 (50,36) and 313
   (18,13), (51,37), (32,42), (34,20) (bits `$0AD`, `$0B0`, `$0AE`, `$0AF`,
   `$0BE`; TreasureProp holds no gil, item or monster flag:
   `data/maps_cave.txt`). The route opens the Warp Stone, the Wing Edge, the
   Dragon Horn and the Ribbon.
5. **The cave's bodies are weak to ice and drink fire**, all but the two
   casters (Necromancr weak to fire and holy, Trixter to holy). Of the two
   parties gen_wor_phoenix makes, party 2 (CELES, RELM, MOG, UMARO) holds
   ice and party 1 (TERRA, STRAGO, SABIN, CYAN) does not (`data/
   wor-phoenix-v1_dump.txt`).
6. **Doom Gaze meets the Falcon on the way** (event group 93, formation
   463) and escapes; its fight is v0.34's (magicite.md). It had no row.

## 1. The legs

| leg | boots | saves | what |
|---|---|---|---|
| `gen_wor_phoenix` | `wor-thamasa-v1` | `wor-phoenix-v1` | Thamasa's inn and counter, the flight (Doom Gaze), the split, the gates, the Warp Stone, the Wing Edge, the rocks, the passage, the lava, the save point |
| `gen_wor_locke` | `wor-phoenix-v1` | `wor-locke-v1` | the bridge, the Red Dragon, the Dragon Horn, the Ribbon, the last bridge, LOCKE; the regroup, Kohlingen, the save |

## 2. The order

The cave as split-party.md section 3 has it, with one addition: party 1,
on 313's west side on its way to (41,27), walks round by 313 (24,50) to 315
(24,54), steps on (23,49) and opens the Wing Edge from (24,44), then goes
back down (`data/paths.txt`: route_data field-path on both maps).

After LOCKE's scene (section 5): out of Kohlingen by its south edge, aboard
the Falcon, the cabin (LOCKE, TERRA, CELES and RELM), a stone for LOCKE,
lift off, land by Kohlingen, the inn, the item counter, the gear counters,
and the save on (40,45), the tile east of the door that `wor-kohlingen-v1`
also uses.

## 3. Species and break rows

Vanilla stats (`data/species.txt`; where else each appears, `data/
sharing.txt`). Before this arc every species here rode the floor (6 shields,
slash or pierce). The rows give each party a key of its own: holy on the
Phase (an element add) and on the casters, a class on the beasts. Vanilla
elements stay.

| species | where | L / HP | vanilla elements; notes | shields | classes | why |
|---|---|---|---|---|---|---|
| Phase `$0BC` | 315 | 47 / 4,550 | weak ice, absorbs fire; Float; Smirk (Stop) | 2 | special, **+holy** | a phantom: holy for the half with no ice |
| Parasoul `$0BF` | 315 | 47 / 2,077 | weak ice, absorbs fire; El Nino, Flash Rain | 2 | slash, pierce | cut or puncture the canopy |
| Necromancr `$0F1` | 315 | 48 / 3,525 | weak fire, holy; absorbs poison; Doom, X-Zone, Flare (Runic) | 2 | slash, special | a robed caster; CELES's Runic eats its list |
| Trixter `$0F7` | 313, 315 | 49 / 3,815 | weak holy; Fire 1-3, Cure 2, Rflect, Haste | 2 | pierce, special | MOG's spear for the half with no holy |
| Aquila `$0EC` | 315 (16/256) | 49 / 6,013 | weak ice, absorbs fire; Flap (x5) | 3 | slash, pierce | a bird, the cave's rare killer |
| Chaos Drgn `$0E2` | 313, 315 | 44 / 9,013 | weak ice, absorbs fire; defence 5; Disaster, Cinderizer | 4 | pierce, blunt | a dragon with no armour |
| Sea Flower `$0E9` | 313 | 47 / 4,200 | weak ice, bolt; absorbs fire, water; Feeler | 2 | slash | a plant, in fives |
| Uroburos `$093` | 313 | 48 / 50 | weak ice, absorbs fire; defence and magic defence 252 | 1 | blunt | 50 HP behind its defence: one crushing blow breaks it |
| Red Dragon `$153` | event 138 | 67 / 30,000 | weak ice, water; absorbs fire | 6 | pierce | MOG's spear between the scales, CELES's ice |
| Doom Gaze `$11D` | event 93 (the sky) | 68 / 55,555 | weak fire, holy; absorbs ice, poison; escapes | 8 | pierce, special | an eye in the sky; v0.34 fights it |

`battle_breakwor_locke` checks the rows in the built ROM, every formation
of the cave's two pools (groups 174 on map 315, 175 on 313) for each party
alone, the Red Dragon for party 2 and Doom Gaze for the four from the tower,
and the lesson (each ice-weak body keyed for party 1 without ice). Red on the
base ROM (44 mismatches); the mutants Phase without holy and Trixter without
pierce each turn it red where they should (`rows/`).

## 4. The bosses

- **The Red Dragon** (event 138, `$153`; party 2). The floor had already
  given it 6 shields and pierce, so the row changes no number of its fight.
  Measured: section 7.
- **Doom Gaze** escapes; nothing on this arc fights it to the end.

## 5. The arc's end

- **The regroup.** LOCKE, TERRA, CELES and RELM: LOCKE with the three
  highest levels, TERRA's Cure and Life and CELES's Cure for medics. SABIN,
  CYAN, STRAGO, MOG and UMARO wait aboard (EDGAR and SETZER already did).
- **LOCKE's kit.** The gear care dresses him from the bag on arrival: the
  Wing Edge, the scene's Flame Shld, a Circlet and a Crystal Mail;
  the relics give him a Ribbon; he takes the first owned stone no one wears
  (Shiva in the seed run). His commands are #382's (Mug, Trickshot,
  Dismantle, Appraise, Master's Mark), built on another branch; this route
  uses no command of his yet.
- **Kohlingen** (shops 65-67, the inn): the bag to the bands at the four's
  level, the gear counters by the plan (`gearStop`).
- **`wor-locke-v1`**: world 1 (40,45), the four seated, `$00D7`, `$02F1`
  set, `$069C` and `$01CE` clear (`M.contracts["wor-locke-v1"]`).

## 6. Supplies and kits

- **The cave** spends from the bag Thamasa stocks (Potions 99, Tinctures
  40, Fenix Downs 20, Remedies 20, Tents 6; gen_wor_phoenix), shared
  between the parties by the split ledger (split-party.md section 4).
- **Kohlingen** brings the bag back to the bands at the four's level: in
  the sweep below the save held 93-95 Potions, 40 Tinctures, 31-36 Fenix
  Downs, 18-20 Remedies and 27-30 Revivifies (`lab/swl_*`: `[wor] ... on
  the save tile`). The gear counters sold nothing the plan wanted in the
  seed run (`lab/cl2`: TERRA and RELM changed helmet and armor from the bag).
- The audits over the qualified chain are in section 7.

## 7. Played

Evidence under `build/attempts/wt/v032-locke-arc/lab/`. Each sweep run is
one attempt from a committed tree (`commit.txt`, `diff.sha256` of the empty
diff), the leg's variant with K random battles used up first
(`mkvar.py`: on the world map beside the tower for gen_wor_phoenix, by
party 1 in the cave's north room for gen_wor_locke), K 0-5 at seed shifts 0
and 7. Battles are counted by distinct key (`$be` at the open with the
group): `tally.py` (`tally_sw.txt`) and `tools/fight_report.py`
(`fight_report_sw.txt`, per fight `fights_sw.tsv`).

- **The seed runs.** `cp1`: gen_wor_phoenix from the tracked
  `wor-thamasa-v1`, "PASS (frame 89187) attempts=1/3", the Wing Edge
  "OPENED". `cl2`: gen_wor_locke from cp1's capture, "PASS (frame 55726)
  attempts=1/3". Their captures seed `wor-phoenix-v1` and `wor-locke-v1`.
- **gen_wor_phoenix**, `swp_*` at cb96cf45: 12 of 12 passed (76,906 to
  92,933 frames).
- **gen_wor_locke**, `swl_*` at cb96cf45 from the new `wor-phoenix-v1`:
  12 of 12 passed (55,866 to 103,178 frames).
- **The Red Dragon**: 12 meetings, 12 keys, 12 won, no member down; the
  party's low point 72% median, 60% worst; 5,392 to 9,629 ticks. It is
  neither attrition nor a coin flip, and no lab was needed. It is on the
  easy side of "real but surmountable" (fight-quality.md): party 2 never
  fell below 60%.
- **Doom Gaze**: met on every phoenix run (12 keys), escaped every time,
  no member down.
- **The rows against the floor.** The same sweep shape before the rows
  (split-party.md's `swp3_*`, `swl5_*`, read by the same tools:
  `fight_report_before_rows.txt`, `tally_before_rows.txt`) against after:

  | formation | keys before / after | deaths a fight before / after | low point median before / after |
  |---|---|---|---|
  | Phase x2 ($150) | 25 / 21 | 0.60 / 0.10 | 54% / 71% |
  | Aquila, Chaos Drgn x2 ($157) | 13 / 12 | 0.23 / 0.08 | 56% / 68% |
  | Necromancr x2, Phase, Parasoul ($152) | 6 / 7 | 1.33 / 2.00 | 68% / 64% |
  | Trixter x3 ($151) | 21 / 28 | 0.00 / 0.04 | 74% / 77% |
  | Doom Gaze ($1CF) | 11 / 12 | 0.27 / 0.00 | 75% / 86% |
  | Red Dragon ($174) | 11 / 12 | 0.00 / 0.00 | 84% / 72% |

  Fenix Downs spent over the 24 runs: 37 before, 18 after.
- **The Necromancers' formation ($152)** still kills: two of its seven
  keys took five deaths each, both party 1's (`swp_k0_s7`, `swp_k4_s7`).
  The cause is Zombie: ZombiStick turns SABIN (L38, the bench), and the
  zombie's own turn comes before the Revivify the driver confirmed lands
  (`swp_k4_s7`: "entity 2 char 5 is under ZOMBIE", "actor=0 cure entity
  2's Zombie with $F1", then "[death] ... entity 3 char 2 ... by entity 2
  char 5 cmd $0A ... (an ally's action)"). A vanilla mechanic on an
  under-levelled bench; a lab candidate (section 8).

## 8. Open

1. **Narshe and Ragnarok.** LOCKE opens Narshe's locks (route-wor-narshe.md
   findings 1-2): the town's only stocked item counter, the weapon shop's
   Ragnarok (stone or sword, a player's choice), the relic shop and the
   elder's treasure room. route-wor-narshe.md planned Ragnarok for v0.32;
   this arc's route does not go there.
2. **The Necromancers' Zombie** (section 7): a Ribbon or another Zombie
   guard on the bench in the cave's first half, or levels for the bench.
   The Ribbon is in this cave (313 (13,20)) and goes on in its second half.
3. **LOCKE's commands** (#382) are another branch's; once they land, the
   next arc's route can measure who lands the breaks (guidelines.md, "every
   recruit should feel amazing"). On arrival he brings blunt (the Wing
   Edge) to a four that held slash, pierce and blunt already, and is six to
   nine levels under them.
4. **Doom Gaze's row** (8, pierce and special) is a first design from the
   meeting on the way; v0.34 fights it.
