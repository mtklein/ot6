# World of Ruin: dreams and ruins (Cyan's dream, Wrexsoul, the Ancient Castle)

Milestone v0.35, #271: from the save beside the Falcon by the Opera House
(`wor-opera-v1`, where the v0.34 route ends) to Kohlingen's counter, Doma
Castle and CYAN's dream (the dreamscape and the three Dream Stooges, the
dream's train, the cave below its engine in Magitek armor, the dream's Doma
and Wrexsoul), the wake (every SwdTech, the Magicite Alexandr), and then
Figaro Castle's ride stopped under the stratum, the cave to the Ancient
Castle, Odin and the queen's statue (Raiden), and the Blue Dragon; a save
beside the Falcon by Figaro Castle (`wor-ancient-v1`) is the next arc's
boot.  The Cursed Shield is not uncursed here (section 9).

Line numbers are into `ff6/src/event/event_main.asm` unless a file is named.
Evidence is under `build/attempts/wt/v035-wor-dreams/lab/` (the run logs, and
the scripts beside them: the explore and probe bodies `x1`-`x20` and `y1`-`y4`;
the leg builder `assemble.py` and its parts (`gen_<leg>_head.txt`,
`gen_<leg>_tail.lua`, `gen_<leg>_body.lua`); `fromstate.py` (a leg's tail from
a lab snapshot: the `t1`-`t4` runs); the variant builder `mkvar.py` (the
sweeps); the mutant builder `mkmut.py` and its launcher `mutants.sh`; the
launchers `lab.sh`, `go.sh`, `run.sh`, `multi.sh`, `rawlab.sh`, `genlab.sh`,
`sweep.sh` and `qual.sh`; and the readers `tally.py`, `ev.py`, `where.py`,
`itembytes.py` and `pull.py`).

---

## 0. Findings

1. **The dream starts in Doma Castle's King's room.**  The bed's trigger
   (123 (4,12), entered facing up: `_cb827d`, "Need a rest?") runs the dream
   (`_cb82b1`) when CYAN is in a party of four in the World of Ruin and the
   dream has not been dreamt (`$00DA`).  CYAN is taken; the member at the top
   of the battle order is set down in the dreamscape (317) as an NPC at
   (17,46), the next one at (27,52) (`_cb84ff`/`_cb854f`, `set_case TOP_CHAR`
   each time), and the last walks alone.  The cabin's order CYAN, CELES, RELM,
   TERRA puts TERRA alone: L50, her Ultima at 3 BP and her Morph.
2. **The dreamscape is a warp maze with two guards.**  Its fourteen same-map
   doors are the plan's links.  A stooge stands by each waiting member and
   runs from (15,43)/(19,43) and (25,51)/(28,49) ("I'm not gonna mess with ya
   unless my brothers are here!": `$0189`, `$018B`); a member spoken to
   rejoins.  The three stooges together at (46,55) are event battle 90; a
   second step on that tile after the win loads the dream's train (`_cb8c59`).
3. **The dream's train is three cars and two puzzles.**  The last car (322)
   has a save point; the scene at 143 (88,8) is CYAN with the ghost
   (`$0197`).  The second car (144): the Lump of Metal (3,6) (`$01D6`) set in
   the middle slot (14,8) (`$0187`) clears the blocks before the Flame Shld
   (14,5); its button (27,5) pressed twice, the second press while the first
   one's 240-frame timer runs (`_cb9300`, `$01FB`), opens both doors by the
   Genji Glove (25,5).  The first car (321): three levers (22,5), (17,5),
   (14,5) (`$0184`-`$0186`) move its walls (the route presses them, a
   reachable one at a time, until the panel is reachable: 110), and its check
   (9,5) (`_cb8ec1`: `$017A`) wants the panel's six switches at 0 0 1 1 1 0,
   the pattern the second car's lever shows ("Memorize the positions.").  The
   switches are map switches (`$01F1`-`$01F6`), cleared at every map load, so
   the pattern is carried by the player, not the RAM (lab `x11`: all six read 0
   on entering 321 after the second car's lever had set them).
4. **The cave below the engine is fought in Magitek armor.**  143 (38,8)
   loads the engine (146); (8,13) below the arrival is, in the World of Ruin,
   the cave (`_cba808` -> `_cb93bf`: 320 (6,10), MAGITEK on all three).  In
   the armor the Fight row is MagiTek and Magic stays (InitCmdList); the
   driver's MagiTek line (#373, `Driver:magitekLine`) picks the beam the
   target is weakest to, and every body there is weak to bolt.  320 (6,22) ->
   319; 319 (24,5) -> 320 (22,24); 320 (22,25) -> 319 (24,25), CYAN's scene
   (`$0184`); 319 (14,25), entered from (15,25), drops the party out of the
   armor into the dream's Doma (126 (8,8)), where a save point stands.
5. **Wrexsoul hides in a party member.**  Its first turn is Zinger (AIScript
   `_290`): `TargetEffect_3a` keeps Wrexsoul in `$33F8` and the member in
   `$33F9` and makes Wrexsoul untargetable (`$2F4D`); only that member's fall
   brings it back (`_c207c8`), and its two Soul Savers restore themselves when
   they fall.  The walks' driver fought it as a war of attrition (lab `x16`:
   a wipe at frame 199,253, 25 deaths and 22 raises in); the driver now fells
   the host (section 5).
6. **The wake** (123 (8,8)): `$00DA`, CYAN back in the party with every
   SwdTech (`give_bushido`: `$1CF7` = `$FF`), the katana Aura, and the
   Magicite Alexandr on the dais (123 NPC_9 (25,5), `_cb9a7a`).
7. **Figaro Castle's ride stops under the stratum.**  While `$00CD` (set at
   the Falcon's return, :11258) the engineer's ride stops halfway
   (`_ca694f`: `$02B7`, `$026F`) and asks again (dlg `$01DF`): "(Continue
   journey)" or "(Stop and explore)".  The cave's mouth in basement 1 (35,40)
   is drawn when the map loads with `$02B7` (`_caeaa2`), and the stop loads
   basement 1 before it sets the switch, so the party goes up to the hall and
   down again.  The mouth opens on basement 1's east side, which joins the
   engineer's west room only through the lower hall.
8. **The Ancient Castle.**  The cave (401) -> its save point (402) -> the
   courtyard (407), where (16,33) runs the flashback (`$02DF`: Odin's statue,
   the queen); Odin stands in the castle (406 (33,11), `$0696`); (34,14) faced
   up with A opens the queen's floor's east passage (`$02DE`, drawn at 408's
   load: `_cc19fd`); on the queen's floor (408) the book (TERRA's line), the
   queen (`_cc1f49`: Odin becomes Raiden, `$02DD`) and the Blue Dragon, which
   wanders the east room and fights when touched (event battle 137, `$06A1`).
   A long entrance covers its tile and `len` more, and every one of them lands
   on its one destination (`CheckLongEntrance`): the castle's one-way warps
   are the plan's links.
9. **The way back is two rides.**  There is no walk from the South Figaro
   side to the Kohlingen side (`route_data.py world-path 1 81 86 49 58`: no
   on-foot path).  Under the stratum the engineer asks at once; "(Continue
   journey)" goes to South Figaro (`_ca6969` -> `_ca69ad`), and the next ride,
   to Kohlingen, stops under the stratum again and goes on to the Kohlingen
   side (`_ca6931`), where the Falcon waits.
10. **A Continue at a field save tile** was taken for the save tile while the
    load screen's preview held the slot's map and tile in the cells
    `bootCheckpoint` reads; the A presses stopped on the preview and the
    confirm sat unanswered (`gdo1_s0`, the first boot of `wor-dream-v1`).
    The field test now also wants the menu module not running.

## 1. The legs

| leg | boots | saves | what |
|---|---|---|---|
| `gen_wor_dream` | `wor-opera-v1` | `wor-dream-v1` | the cabin (CYAN, CELES, RELM, TERRA), Kohlingen's counter, Doma Castle's bed, the dreamscape, the stooges, the train, the cave in Magitek armor, the save point in the dream's Doma (126 (8,8)) |
| `gen_wor_doma` | `wor-dream-v1` | `wor-doma-v1` | Wrexsoul (the Zinger line), the wake, Alexandr (on CYAN), the care, out of Doma, the save on the Falcon's tile (170,75); also `wor_doma_throne` (`battle_zinger`'s fixture) |
| `gen_wor_ancient` | `wor-doma-v1` | `wor-ancient-v1` | Kohlingen's counter, Figaro Castle stopped under the stratum, the Ancient Castle (the flashback, Odin, the queen's passage, the book, Raiden, the Blue Dragon), the two rides back, the save on the Falcon's tile (49,58); also `wor_ancient_dragon` |

## 2. The order and the party

The Opera House -> the Falcon's cabin (CYAN, CELES, RELM, TERRA, in that
order) -> Kohlingen's counter -> Doma Castle (world (171,75): the courtyard
285, its west door (28,31) -> 123, 123's doors to the King's room) -> the bed
-> the dreamscape (TERRA alone; the two stooges run; CELES and RELM rejoin;
the three stooges) -> the dream's train (322, the scene at (88,8), 144, 321)
-> the engine (146) -> the cave in Magitek armor (320, 319) -> the dream's
Doma (126), its save point -> Wrexsoul at its throne (25,11) -> the wake
(123): Alexandr -> out of Doma to the Falcon -> Kohlingen's counter again ->
Figaro Castle on the Kohlingen side (53,58): the engineer, the stratum,
"(Stop and explore)" -> basement 1's cave mouth (35,35) -> the cave (401) ->
the save point (402) -> the courtyard (407): the flashback -> the castle
(406): Odin, the Gold Hairpin and the Blizzard Orb, the queen's passage ->
the queen's floor (408): the book, the queen (Raiden), the Blue Dragon, the
X-Ether -> back to basement 1 -> two rides -> the Falcon's tile by Figaro
Castle (49,58).

The party is the dream's: the dream takes CYAN and leaves three, and the four
the cabin seats are the three at the top of the roster (TERRA and CELES L50,
RELM L48 in `wor-opera-v1`; STRAGO L47 and GOGO L42 sit out) with CYAN.  RELM
brings Ultima (Ragnarok), Sketch and the party's only bludgeon; TERRA the
dreamscape's solo walk; CELES the Genji Glove pair and ice for Wrexsoul.
After the dream the same four, CYAN back, walk the Ancient Castle, whose
Reflecting bodies want steel: CYAN's katanas (Strato and Aura, the Genji
Glove from the dream's train), CELES's Falchion pair, TERRA's blade.

## 3. Species and break rows

Vanilla stats from `route_data.py species`; elements stay vanilla.  Rows in
`ff6/src/battle/ot6_hud.asm`.  Every species here was unauthored (the
generated floor: six shields, slash or pierce) and none is dealt anywhere
off this arc's maps (`where.py`: field groups 181-183 and 143-145 are the
dream's and the Ancient Castle's only, event groups 90, 92 and 137 theirs).

**The dream** (field groups 183, the dreamscape; 181, the train and the
dream's Doma; 182, the cave).  TERRA, CELES and RELM hold slash (the two
blades), bludgeon (RELM's rod), fire, ice, bolt and holy (TERRA's and CELES's
spells, the Pearl Rod).  TERRA walks the dreamscape alone until the stooges
run, so every body there takes her blade or her fire.  In the cave the
three ride Magitek armor, whose rows are the beams (fire, bolt, ice), Bio
Blast (poison) and TERRA's Tek Missile (pierce), with no Fight; every body
there is weak to bolt vanilla, so the bolt beam breaks them all.

| species | where | L / HP | vanilla elements | shields | classes | why |
|---|---|---|---|---|---|---|
| Barb-e `$0BE` | 183, 181 | 39 / 3,062 | weak poison | 3 | slash, special | a dream's siren: steel or a brush |
| Critic `$0AB` | 183 | 40 / 1,200 | none | 2 | slash, bludgeon | a shrieking bird |
| Allosaurus `$085` | 183 | 38 / 3,000 | weak fire, holy | 3 | pierce, bludgeon | a dinosaur's hide; TERRA's fire |
| Parasite `$0B1` | 183, 181 | 39 / 1,000 | weak fire | 2 | slash | a soft crawler |
| Pan Dora `$0AC` | 183, 181 | 39 / 1,522 | weak fire, holy; absorbs poison | 3 | bludgeon, special | a jar: break it |
| Rain Man `$00A` | 181 | 39 / 2,722 | weak ice, holy, water | 2 | bludgeon, special | a storm spirit; CELES's ice |
| Samurai `$004` | 181 | 40 / 3,000 | weak poison | 3 | slash, pierce | a swordsman of the dream's war: steel answers steel |
| Suriander `$01E` | 181 | 40 / 2,912 | weak holy | 3 | slash, bludgeon | a ghostly beast |
| PlutoArmor `$09D` | 182 | 39 / 2,850 | weak bolt, water | 3 | pierce | an armored rider: the missile pierces |
| Sky Cap `$095` | 182 | 40 / 3,262 | weak bolt, wind, water | 2 | pierce, special | a flying cap |
| Io `$0FE` | 182 | 39 / 7,862 | weak bolt, holy, water; nulls poison, wind, earth | 4 | pierce, bludgeon | a war machine |
| Curley `$11F` | event 90 | 47 / 15,000 | weak ice, water; absorbs fire | 4 | slash, special | a stooge |
| Larry `$120` | event 90 | 47 / 10,000 | weak fire; absorbs ice, wind | 4 | pierce, bludgeon | a stooge |
| Moe `$121` | event 90 | 47 / 12,500 | absorbs bolt | 4 | slash, bludgeon | a stooge |
| Wrexsoul `$122` | event 92 | 53 / 23,066 | weak ice; absorbs fire, holy | 6 | slash, special | a composite of the war's spirits: steel or a brush |
| SoulSaver `$167` | event 92 | 41 / 3,066 | weak ice; absorbs fire, holy | 2 | special | a soul: the brush, or CELES's ice |

The three stooges take three different class pairs and together hold a key
for every hand; Larry's fire and Curley's ice are the elemental answers.

**The Ancient Castle** (field groups 143, the cave; 144, the castle; 145, the
courtyard; event 137, the Blue Dragon).  Every body wears Reflect and most
have mdef 250: spells bounce and steel decides.  CYAN comes back from his
dream with every SwdTech, and his katana keys every body here.

| species | where | L / HP | vanilla elements | shields | classes | why |
|---|---|---|---|---|---|---|
| Enuo `$0A6` | 143 | 46 / 4,635 | weak holy | 2 | slash, bludgeon | a slime |
| Goblin `$06D` | 143, 145 | 46 / 5,555 | weak holy | 3 | slash, pierce | L.5 Doom, L.4 Flare, L.3 Muddle |
| Figaliz `$057` | 143, 144, 145 | 45 / 4,220 | weak ice | 3 | slash, bludgeon | a lizard |
| Lethal Wpn `$045` | 144 | 47 / 9,200 | weak bolt, water | 4 | slash, bludgeon | a machine: cut its cables or crush it |
| Boxed Set `$051` | 144 | 45 / 4,020 | weak holy | 3 | slash, bludgeon | an empty armor |
| Blue Drgn `$152` | event 137 | 65 / 26,900 | weak bolt; absorbs water | 6 | slash, pierce | a water dragon's scales |

The courtyard's pool (145) also deals the train's Barb-e, Samurai and
Suriander, each of them keyed by slash.

`battle_breakwor_dreams` checks the 22 rows in the built ROM, every
formation of the pools (field groups 183, 181, 182, 143, 144 and 145, events
90, 92 and 137: "checked 22 formations, 48 formation-species-hands
triples") against the hands that meet them, and the lessons: TERRA alone
keys every body of the dreamscape ("TERRA alone (the dreamscape) keys 5 of
5"), the bolt beam every body of the cave ("the bolt beam (the cave) keys 3
of 3"), CYAN alone every body of the Ancient Castle ("CYAN alone (the
Ancient Castle) keys 12 of 12", the species once a pool), the three stooges
three different pairs, the Soul Savers the brush alone among classes, and
the Blue Dragon keeps its bolt weakness and its water absorb (lab
`s_breakwor`: "PASS (frame 31)").  Red on the ROM without this arc's rows and on
two ROM mutants (section 7).

## 4. The bosses

PENDING

## 5. The Zinger line

Wrexsoul's script (AIScript `_290`) opens with Zinger, then casts Bolt 3 on
the party twice and Zingers a random member again whenever it is out; its
two Soul Savers (`_359`) Reflect themselves, drain MP, cast Ice 3, Bolt 3,
Fire 3 and Cure on Wrexsoul, and restore themselves when they fall.  While
Wrexsoul hides only its host's fall brings it back (`_c207c8`), so a party
that fights the Soul Savers fights forever, and the walks' driver did:

| lab | the fight | trials | result |
|---|---|---|---|
| `x16` | the walks' driver (before the line) | 1 | a wipe at frame 199,253 after 25 deaths and 22 raises; Wrexsoul at 15,771 of 23,066 |
| `zoff` | `ZINGER_OFF`, a 60,000-frame cap | 6 runs, 3 keys | be64 won after 53,022 ticks (the host fell 40,505 frames after the hide); be84 and beA4 not won in 60,000 frames (be84's host fell 24,804 frames in) |
| `x17` | the line | 3 | 3 won: 8,102, 27,446 and 17,910 ticks |
| `zon` | the line | 8 runs, 8 keys | 8 won, 8,830-15,086 ticks; the host fell 3,544-10,682 frames after the hide |
| `zon2` | the line spending every pip | 8 runs, 8 keys | 8 won, 9,422-17,078 ticks; the same falls (3,390-10,683): kept out |

(`zon` and `zoff` from `x16`'s snapshot below the throne, seed shifts 0-53;
shifts 0 and 3, 7 and 11, 13 and 19 open the same battle key there.)

`Driver:zingerPlan` (`lib/ot6.lua`, after `buffPlan` in `makePlan`): while
`$33F8` holds a monster and `$33F9` a living member, an actor other than the
host turns an attack plan, or a heal aimed at the host, into a Fight on the
host (the ally-Fight the Muddle rule presses), at the plan's boost when it
was a Fight; care for the other members stands.  `ZINGER_OFF` (a global) is
the control.  A person who saw where the Zinger went does the same: the
host's fall is the only way to the boss, and the party revives the host
once Wrexsoul is out.

`battle_zinger` plays it from the leg's own snapshot below the throne
(`wor_doma_throne`): a Zinger plan once Wrexsoul hides, aimed at the member
`$33F9` names, by another member; the host's fall within 20,000 frames of
the plan; Wrexsoul back within 600 frames of the fall; then the control,
`ZINGER_OFF`, from the same snapshot for as long as the line took and 900
frames more: no Zinger plan, and Wrexsoul still hidden.  Passing (`s_zinger`,
on the lab's throne snapshot: "entity 0 fell 6869 frames after the plan",
"Wrexsoul back 1 frames after the fall", "the control: 0 Zinger plan(s);
Wrexsoul still hidden 8316 frames in: true").  Two mutants (`mkmut.py`,
`mutants.sh`), each red on its assertion: the Fight aimed at another living
member (`mutZA`: "1. the plan's target is the member $33F9 names: got 1, want
3"), the line ignoring `ZINGER_OFF` (`mutZB`: "control: with ZINGER_OFF no
Zinger plan: got 11").

## 6. Supplies and kits

PENDING

## 7. Played

PENDING

## 8. Open

PENDING

## 9. The Cursed Shield

LOCKE took it in Narshe (v0.32, route-wor-narshe.md section 12.2) and it has
stayed in the bag.  The curse lifts by battles worn, and this arc is not
where to wear it:

- **The count.**  At a won battle's experience, `LearnItemMagic`
  (`battle_main.asm` @5fef) adds one to the battle variable `$3EC0` for each
  living member (GOGO and UMARO aside) wearing the Cursed Shld (`$66`); when
  it wraps from 255 to 0 the shield becomes the Paladin Shld (`$67`) on that
  member and the battle says so.  `$3EC0` is `$1DC9 + $0C` kept across
  battles (`$1DD5` in the save block); it reads 0 in `wor-opera-v1` (lab
  `x1`: "[curse] $1DD5 (battle var $3EC0) = 0").  So the shield wants 256
  battles won with its wearer standing.
- **The price.**  ItemProp `$66` (`itembytes.py`): defense and magic
  defense 0, every stat -7 (+16/+17 `$FF`), weak to fire, ice, bolt, poison,
  earth and water (+24 `$CF`), and the statuses at +25 `$79`: Condemned,
  Mute, Berserk, Muddle and Sap.  A Ribbon guards all of them but Condemned,
  so the wearer's Doom counts down every battle.
- **The reward.**  The Paladin Shld: defense and magic defense 59, absorbs
  fire, ice, bolt and holy, nulls poison, wind, earth and water, and teaches
  Ultima (+3/+4: rate 1, spell `$14`).
- **The arc's battles.**  The dream leg fights 9 or 10 (sweep `sd`: 9, 9, 9
  and 10 `[outcome]` lines in `sd_k0_s0`, `sd_k0_s7`, `sd_k1_s0`,
  `sd_k2_s0`, the K battles included), Wrexsoul's leg 1 or 2 (`gdo1_s0`: 2),
  the Ancient Castle about 12 (`t3_s0` and `t4_s0`, 6 each): about 25 of the
  256, and among them the arc's three hardest fights (the stooges, Wrexsoul,
  the Blue Dragon), where a Condemned member with every stat down is a
  liability.

So the uncursing belongs to a stretch of the route with many random
battles and no boss on a clock: a grind on a strong pool, or the long
World of Ruin dungeons ahead, worn by a Ribboned member the party can
spare.  It is left for a later arc; nothing here wears the shield.
