# World of Ruin: Gau (the Veldt, the Veldt cave, Gau's father, Duncan)

Milestone v0.33, #269: from the save beside the Falcon south of Narshe
(`wor-ragnarok-v1`, where the v0.32 route ends) to GAU joined, the Veldt cave
and its SrBehemoth, SHADOW carried to Thamasa, the father's scene, SABIN's
Bum Rush, and a save beside the Falcon by Duncan's house (`wor-gau-v1`), the
next arc's boot.

Line numbers are into `ff6/src/event/event_main.asm` unless a file is named.
Evidence is under `build/attempts/wt/v033-wor-gau/lab/` (the run logs, and
the scripts beside them: the labs `explore*.lua` and `probe*.lua`, the
variant and mutant builders `mkvar.py`, `mkhd.py` and `mkmut.py`, the
launchers `lab.sh`, `sweep.sh`, `hd.sh` and `mutants.sh`, and the readers
`veldt_set.py`, `kit.py`, `where.py`, `sw.py` and `tally.py`).

---

## 0. Findings

1. **GAU comes only to a party of three or fewer.**  After a Veldt battle
   won with two or more standing, he appears 5/8 of the time
   (`battle_main.asm` @4840: `Rand / cmp #$a0`), and only when the party
   holds fewer than four (@2fbb: `$fc < 4`); the battle's AI then adds him
   (`MiscAIEffect_03`: `$1EDF` bit 3).  He joins at the level he had at the
   World of Ruin's start (`norm_lvl GAU`, :11277): L32, against TERRA and
   CELES's L49-50.
2. **The Veldt deals what the save has fought.**  `$1DDD-$1E1C` holds a bit
   for every formation fought whose monsters are all under 256 and whose
   battle data does not bar it (`battle_main.asm` @49e9); each Veldt battle
   takes the next byte of it that has a bit set (`GetVeldtBattle`,
   `field/battle.asm`: `$1FA5` walks the 64 bytes) and a formation of that
   byte.  In `wor-ragnarok-v1` that is 155 formations, 144 species, 47
   bytes (`veldt_set.py`), the Phoenix Cave's bodies among them, and the
   Holy Dragon (formation 481, alone in its byte).  `$1FA5` moves only
   with Veldt battles and a Continue seeds it from the save, so **the
   Veldt's first battle from this save is the Holy Dragon in every run**;
   battles fought elsewhere first do not move it (section 7).
3. **Duncan fits the arc.**  His house is world (140,20) -> map 127,
   north-east of Narshe's gate; the trigger (7,11) (`_cc0bd8`) asks only for
   SABIN in the party, runs the scene with no battle and teaches Bum Rush
   (`give_blitz`: SABIN's blitz byte `$1D28` reads `$3F` in
   `wor-ragnarok-v1`; `gen_wor_gau` asserts bit 7 after the scene; `$02AF`
   set).  He is visited last, with SABIN seated for the father's house.
4. **The father's house** is world (178,45) -> map 131, its back room map
   116.  The old man (116 NPC_1, `_cb6828` -> `_cb645b`) is talked to facing
   up with SABIN and GAU in the party; the reveal, Jidoor's tailor (map 206)
   and the father's rejection run as one scene that ends on the world map
   beside the Falcon with GAU back in the party (`$0245`, `$0247`, `$0249`).
   It gives no item.
5. **The Veldt cave** (world (207,89) -> map 353) is one map of fourteen
   same-map doors.  Entering at (35,56) shows the dog (`_cb799f`: `$0195`);
   the wall at (43,16) opens to a party facing up with A held
   (`_cb79e6`: `if_any $01B0=0 / $01B4=0` read the facing and the A button
   through `$1EB6`); the save point is (57,44); the door (51,53) lands on
   (59,18), the dog's master (`_cb7a18`).  Chests: the Rage Ring (18,20),
   the Striker (42,26) and a monster chest (6,8): event group 153, word
   `$0203`, formation 515, Allo Ver (`route_data.py` masked the word to nine
   bits and read formation 3; fixed).
6. **SHADOW was saved on the Floating Continent** (`$00A3` = 0 in
   `wor-ragnarok-v1`), so the dog's master is SHADOW: after the SrBehemoth
   (event battle 82, formation 452, one form) the party carries him to
   Thamasa on the Falcon (`airship_pos {250, 231}`), his dream plays, and
   the party stands in Strago's house (map 349; `$0199`, `$0196`, `$019E`).
   Leaving Thamasa by its edge (`_cb7d69`) sends him to the Colosseum
   (`$019F`; the townsman then says "he left for the colosseum").  He is
   recruited there, a later arc's (v0.37's milestone).
7. **Rage had no driver line** (mechanics-coverage.md: UNHANDLED, driven
   only inside `gen_sabin_gau`).  This arc adds one (section 5).
8. **GAU's kit on arrival**: nine rages from the World of Balance (Brawler,
   Whisper, Were-Rat, Rhinotaur, Lobo, Hornet, Trilobiter, Exocite,
   M-TekArmor) and an empty loadout, which AUTO reads as the first eight by
   id (kit-gau.md 8.0): M-TekArmor is left out.  No weapon (his Fight is his
   fists, bludgeon); the gear care dresses him from the bag (Mithril Shld,
   Tiger Mask, Power Sash) and the relic care adds a Star Pendant and a
   Jewel Ring.

## 1. The legs

| leg | boots | saves | what |
|---|---|---|---|
| `gen_wor_veldt` | `wor-ragnarok-v1` | `wor-veldt-cave-v1` | the cabin (TERRA, CELES, RELM), the Veldt until GAU joins, his kit, the cave's dog, chests and wall, its save point |
| `gen_wor_gau` | `wor-veldt-cave-v1` | `wor-gau-v1` | the dog's master and the SrBehemoth, SHADOW to Thamasa, Strago's house (the Memento Ring), Thamasa's item counter, the town's edge, the cabin (SABIN, GAU, TERRA, CELES), the father's house, Duncan's house, the save on the Falcon's tile there |

## 2. The order

Narshe's plain (115,38) -> the Falcon's cabin -> the Veldt (down on
(199,85); Veldt battles paced between the landing and the tile beside it
until GAU joins, at most twelve: twelve without him is (3/8)^12, 8e-6) ->
the Veldt cave (down on (207,90)): (35,56), the Rage Ring, the monster
chest, the Striker, the wall, the save point -> (59,18) -> Thamasa: Strago's
house, the item counter, the south edge -> the cabin -> the father's house
(down on (178,46)) -> Duncan's house (down on (139,21)), and the save there.

Three seated for the Veldt, since GAU will not come to four: the three
highest, TERRA, CELES and RELM.  The first plan seated SABIN, TERRA and
CELES (SABIN for Duncan and the father) and lost 2.12 members a Holy Dragon
fight; the lab that moved it is in section 7.  GAU then walks the cave with
the three who brought him.  After Thamasa the cabin seats SABIN, GAU, TERRA
and CELES for the father's house and Duncan's; RELM, LOCKE and the rest wait
aboard.

## 3. Species and break rows

The cave's bodies (vanilla stats, `route_data.py species`).  Before this arc
all four rode the floor (slash).  The four who walk the cave hold slash
(CELES), pierce (TERRA's dagger), bludgeon (RELM's rod, GAU's fists) and
fire, ice, bolt and poison; the cave drinks CELES's ice (Toe Cutter, the
SrBehemoth) and Allo Ver drinks poison.  The rows key bludgeon on every
body, so GAU's fists and his beasts' physical turns break what CELES's ice
heals.  Vanilla elements stay.

| species | where | L / HP | vanilla elements; notes | shields | classes | why |
|---|---|---|---|---|---|---|
| Toe Cutter `$08F` | 353 (80+80+80/256) | 36 / 2,500 | weak fire, wind; absorbs ice; Doomsickle | 3 | pierce, bludgeon | a scythed shell: crack or puncture it |
| Rhyos `$07E` | 353 (16/256) | 36 / 7,191 | none; Giga Volt, Magnitude8, Rage (x2) | 4 | bludgeon | an armoured horn (defence 150), the rare body |
| Allo Ver `$0BB` | the monster chest (6,8) | 19 / 8,000 | weak fire, holy; absorbs poison; Doom, Condemned | 3 | slash, bludgeon | bones |
| SrBehemoth `$119` | event 82 | 43 / 19,000 | weak fire, poison; absorbs ice; Ice 3, Meteo, Pearl | 6 | pierce, bludgeon | the dead beast: horn and bone; Were-Rat's poison |

`battle_breakwor_gau` checks the rows in the built ROM, every formation of
the cave's pool (group 132), the chest (event group 153) and the
SrBehemoth (event group 82) for the four, and the lesson ("GAU alone keys 4
of the cave's 4 bodies").

The Veldt deals the save's whole fought set (finding 2): 144 species, 44 of
them on the generated floor (World of Balance bodies whose areas no arc has
designed).  This arc gives none of them a row: each is met there at its
World of Balance level by a party of L39-50, and a row for one would change
its home area's fights too.  Section 7 lists the ones the sweep met.

## 4. The bosses

- **The Holy Dragon** (formation 481) is no boss here but the Veldt's first
  battle from this save, fought by three (finding 2).  Measured: section 7.
- **Allo Ver** (the monster chest; Doom, Condemned).  Section 7.
- **The SrBehemoth** (event battle 82; a game over when lost: the runner
  retries from the cave's save point).  Section 7.

## 5. GAU's kit and the Rage line

`Driver:rageLine` (`lib/ot6.lua`): at GAU's first window of a battle, before
the keyed and Fight lines, he Rages.  The beast is the one of the battle
list's eight (`$257E`) whose special does the most to the formation, read
with full power: the special is MonsterRage's second attack, its element,
power and targeting MagicProp's; a special something standing absorbs or
nulls is out, a weakness doubles it, a revealed key it chips counts a
thousand (the MagiTek line's rule), and the physical specials (Battle,
Special) are scored as his fists (bludgeon) at a nominal power.  The boost:
an event battle spends up to three pips (the special every turn), a random
battle one (three in four).  The steer reads the rage window's cursor cells
(`$892B`/`$892F`/`$8933`) and the live list, and a refused confirm takes the
verb off for the battle.  `opts.rage = false` or `RAGE_OFF` is the control.

`battle_ragedriver` checks it against the engine from `wor-veldt-cave-v1`:
the possessing beast is the planned one (`$33A8`), the price is 8 once and
nothing for a possessed turn, and `OT6_RAGETIER` holds the planned boost;
with the line off GAU never Rages.  Three mutants, one an assertion
(`mkmut.py`): the steer one entry off (`mutA`: "possessed by the planned
beast ($33A8): got 14 ($E), want 11 ($B)"), every possessed turn charged
(`mutB`, the ROM: "got 293 ($125), want 301 ($12D)"), the boost recorded and
not pressed (`mutC`: "OT6_RAGETIER holds the plan's boost: got 0 ($0), want
1 ($1)").

## 6. Supplies

No counter lies between Narshe and Thamasa.  The bag from Kohlingen and
Narshe (93 Potions, 40 Tinctures, 28 Fenix Downs at `wor-ragnarok-v1`) carries
the first leg; Thamasa's item counter (shop 74) brings it back to the bands
at the four's level before the save.

## 7. Played
