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
them on the generated floor in `wor-ragnarok-v1` (World of Balance bodies
whose areas no arc has designed; `veldt_set.py`).  The sweeps met fourteen of
the 44 there (`met.py` over every run's `[key]` lines: `met.txt`), and each
of those has a row now.  The rule is one for all fourteen: the floor's
shields (2 + level / 8) and class kept, so the World of Balance parties
that meet them at home keep their key and their count, and one class from
the body added.  Met at their World of Balance levels (1-11) by the three
who walk the Veldt, they are one-turn fights; the rows are for the areas
they come from as much as for the Veldt.

| species | L | floor | row | body |
|---|---|---|---|---|
| Were-Rat `$013` | 4 | 2 slash | 2 slash, pierce | a rat |
| Leafer `$017` | 5 | 2 slash | 2 slash, bludgeon | a rabbit |
| Vomammoth `$01B` | 1 | 2 slash | 2 slash, bludgeon | a mammoth's hide |
| Dark Wind `$028` | 5 | 2 slash | 2 slash, pierce | a bird |
| M-TekArmor `$042` | 8 | 3 pierce | 3 pierce, bludgeon | armour |
| Repo Man `$04D` | 5 | 2 slash | 2 slash, pierce | a thief |
| Areneid `$05D` | 6 | 2 slash | 2 slash, bludgeon | a shelled crawler |
| Stray Cat `$018` | 10 | 3 slash | 3 slash, pierce | claws and teeth |
| Beakor `$029` | 11 | 3 slash | 3 slash, pierce | a bird |
| CrassHoppr `$02F` | 11 | 3 pierce | 3 pierce, bludgeon | an insect's shell |
| Bomb `$04F` | 8 | 3 slash | 3 slash, bludgeon | burst it |
| Ghost `$05A` | 10 | 3 slash | 3 slash, special | a spirit (guidelines: ¤ on spirits) |
| Rhobite `$076` | 10 | 3 slash | 3 slash, bludgeon | a beetle |
| Poplium `$0A2` | 11 | 3 slash | 3 slash, pierce | a puffball |

The other thirty the Veldt can deal from this save stay on the floor: no
run met them (section 8).  `battle_breakwor_gau` checks the fourteen
(section 4 of the suite): the row, the floor's shields and class kept, the
vanilla and added elements, and a key for TERRA, CELES and RELM.  Red on the
ROM without this arc's rows (`bwbase`: "$07E Rhyos has no Ot6ShieldTbl row
(want 4, class $04)", and the rest) and on two ROM mutants (`rowmuts.sh`):
Toe Cutter without bludgeon (`bwmut1`: "$08F Toe Cutter: GAU alone holds no
key"), Leafer without the floor's slash (`bwmut2`: "$017 Leafer lost the
floor's class $01").

## 4. The bosses

- **The Holy Dragon** (formation 481) is no boss here but the Veldt's first
  battle from this save, fought by three (finding 2).  Measured: section 7.
- **Allo Ver** (the monster chest; Doom, Condemned).  Section 7.
- **The SrBehemoth** (event battle 82; a game over when lost: the runner
  retries from the cave's save point).  Section 7.

## 5. GAU's kit and the Rage line

`Driver:rageLine` (`lib/ot6.lua`) is opt-in (`opts.rage = true`; the
`RAGE_OFF` global turns it off again).  On, at GAU's first window of a
battle, before the keyed and Fight lines, he Rages.  The beast is the one
of the battle list's eight (`$257E`) whose special does the most to the
formation, read with full power: the special is MonsterRage's second
attack, its element, power and targeting MagicProp's; a special something
standing absorbs or nulls is out, a weakness doubles it, a revealed key it
chips counts a thousand (the MagiTek line's rule), and the physical
specials (Battle, Special) are scored as his fists (bludgeon) at a nominal
power.  The boost: an event battle spends up to three pips (the special
every turn), a random battle one (three in four).  The steer reads the rage
window's cursor cells (`$892B`/`$892F`/`$8933`) and the live list, and a
refused confirm takes the verb off for the battle.

Off, which is how this arc plays, GAU Fights: his fists are bludgeon, the
key every body in the Veldt cave carries (section 3).  The line was on for
the first sweeps; the paired A/B in section 7 found the possession slower
on every key, and on the SrBehemoth costlier, than his fists, because the
nine World of Balance rages he returns with are weak (specials of power 8 to
40).  A route that teaches him stronger ones (Leap on the Veldt, kit-gau.md
6.3) is where to turn it on and measure again.

`battle_ragedriver` opts in and checks the line against the engine from
`wor-veldt-cave-v1`: the possessing beast is the planned one (`$33A8`), the
price is 8 once and nothing for a possessed turn, and `OT6_RAGETIER` holds
the planned boost; with the line off GAU never Rages.  Three mutants, one an
assertion (`mkmut.py`): the steer one entry off (`mutA`: "possessed by the
planned beast ($33A8): got 14 ($E), want 11 ($B)"), every possessed turn
charged (`mutB`, the ROM: "got 293 ($125), want 301 ($12D)"), the boost
recorded and not pressed (`mutC`: "OT6_RAGETIER holds the plan's boost: got
0 ($0), want 1 ($1)").  It passes from five draws: `rd3` and, with K cave
battles fought first (the line off for them, `mkrd.py`), `rdv_k0_s3`,
`rdv_k2_s0`, `rdv_k2_s7` and `rdv_k4_s0`, which measured Brawler ($0B) or
Leafer ($17) possessing ("GAU's seat possessed by the planned beast
($33A8) = 23").  The absorb veto is logged, not asserted: no rage GAU
carries is ice, the cave pool's absorb, so no cave draw could fail it.  The
play showed it while the line was on: against the monster chest's Allo
Ver, which drinks poison, Were-Rat's Poison scored -1 ("2:$13 $03 elem $08
pow 25 -> -1", `cv2`).

GAU learns rages as vanilla does, from the formation of the battle he
comes to (BattleEnd_05): the join battles taught Leafer ($17) in some runs,
and the AUTO list then carries it.  The loadout stays AUTO (the first eight
by id); M-TekArmor ($42) is the one it leaves out.

## 6. Supplies

No counter lies between Narshe and Thamasa.  The bag from Kohlingen and
Narshe (93 Potions, 40 Tinctures, 28 Fenix Downs at `wor-ragnarok-v1`) carries
the first leg: the cave's save point held 80-91 Potions, 40 Tinctures and
28-29 Fenix Downs in the final sweep (`sfe_*`: "[wor] ... at the save
point").  Thamasa's item counter (shop 74) brings the Potions back to the
band at the four's level (`careStockPotions`: 99) before the father's house
and Duncan's, which spend almost nothing (96-99 at the save, `sff_*`).  No
Fenix Down was spent in either final sweep.  The audits over the qualified
chain are in section 7.

## 7. Played

Evidence under `build/attempts/wt/v033-wor-gau/lab/`.  Each sweep run is one
attempt from a committed tree (`commit.txt`, `diff.sha256` of the empty
diff), the leg's variant with K battles used up first (`mkvar.py`), K 0-5 at
seed shifts 0 and 7; retries off.  Battles are counted by distinct key (`$be`
at the open with the group word): `tally.py` (`tally_*.txt`) and
`tools/fight_report.py` (`fight_report_*.txt`, per fight `fights_*.tsv`).
`met.py` lists every formation the runs met and each species' row
(`met.txt`).

- **The first plan's sweep** (`swa_*`, at 4d8ec215: SABIN,
  TERRA and CELES on the Veldt, the K battles on the plain outside Narshe):
  9 of 12 passed.  The three lost were one battle (key `be24-g0145`, the
  third K battle at shift 7): a Mantodea pair (formation 325) in a pincer on
  the plain south of Narshe, which killed LOCKE, CELES and RELM from full in
  one action each ("[wipe] ... class=one-shot early"), before the leg's body
  began.  Every run that reached the Veldt met the Holy Dragon there first
  ("$1E1 White Drgn ... 9 keys 9 won ... low_worst 45% ... deaths/fight
  1.78"), and the K battles on the plain had not moved it (finding 2).
- **The Holy Dragon lab** (`hd_*`, `mkhd.py`, `hd.sh`): from that sweep's
  own `wor_veldt_duncan.mss`, ten seed shifts an arm, the Veldt until GAU
  joins.  SABIN, TERRA and CELES: "8 keys 8 won ... low_med 79% low_worst
  45% ... deaths/fight 2.12 ... ticks_med 18741"; TERRA, CELES and RELM: "10
  keys 10 won ... 100% 100% ... 0.00 ... 12327.5".  So the Veldt is the
  three highest's, and SABIN's two stops move after Thamasa (section 2).
- **The Rage A/B** (`boss_*`, `cave_*`; `mkboss.py`, `mkcave.py`;
  `pairs.py`): from the tracked `wor-veldt-cave-v1`, the line on and off,
  ten seed shifts an arm.  The SrBehemoth, over the 4 keys both played:
  "boss_rage ... deaths 2, mean ticks 10363", "boss_norage ... deaths 0, mean
  ticks 6739" (`pairs_boss.txt`; the two deaths are GAU's, possessed, in
  key `be4C`).  The cave's randoms, six battles a run, over the 17 keys both
  played: "cave_rage ... deaths 0, mean ticks 1559", "cave_norage ...
  deaths 0, mean ticks 1363" (`pairs_cave.txt`; Rhyos 3517 against 1750
  ticks median).  The line went opt-in (section 5).
- **The final sweeps**, at 33240ddc (the line off), from the tracked
  checkpoints:
  - `gen_wor_veldt` (`sfe_*`, K Veldt battles with the four seated first,
    which GAU will not join, each moving `$1FA5`): 12 of 12 passed, 36,432 to 58,686 frames; 147 battles, 102
    distinct keys, no member down (`tally_sfe.txt`, `fight_report_sfe.txt`).
    The Veldt's K battles moved the draw: the four met the Holy Dragon first
    in the K >= 1 runs, the three in the K = 0 runs, and the Veldt dealt
    eleven formations there (`tally_sfe.txt`).  GAU joined after the three's
    first to sixth Veldt battle (the budget is twelve; "[veldt] the Veldt
    until GAU joins: 5 battle(s)" the most, `sfe_k5_s7`).
  - `gen_wor_gau` (`sff_*`, K battles below the cave's save point first):
    12 of 12 passed, 32,944 to 54,086 frames; 48 battles, 13 distinct
    keys, no member down (`tally_sff.txt`, `fight_report_sff.txt`).  The
    saves held 96-99 Potions, 40 Tinctures, 28 Fenix Downs and 18-19
    Remedies, GAU at L32-33.
- **The fights.**
  - The Holy Dragon on the Veldt: 4 keys, 4 won, low point 94% median and
    81% worst, no one down, 11,740 ticks median (`fight_report_sfe.txt`).
    No longer attrition; the first plan's 2.12 deaths a fight are above.
  - Allo Ver, the monster chest: 12 keys, 12 won, 97% and 94%, no one down
    (fight_report names formation 515 "$003 Bleary+Crawly": section 8).
  - Rhyos: 7 keys, 7 won, 93% and 89%, 1,726 ticks median (3,546 with the
    Rage line on, `fight_report_sfc.txt`).
  - The SrBehemoth (`fight_report_sff.txt`): 6 keys, 6 won, low point 92%
    median and 82% worst, no one down, 7,177 ticks median.  Neither
    attrition nor a coin flip, and on the easy side of "real but
    surmountable" (fight-quality.md): no lab beyond the Rage A/B above.
  - Who keys: GAU made 58 of the party's 212 keyed plans in `sfe_*` (RELM
    72, TERRA 55, CELES 27; `gau_acts_sfe.txt`) and 27 in `sff_*`, all
    with his fists; with the Rage line on he made none (`gau_acts_sfc.txt`:
    "GAU's plans: rage 85, fight 2").
- **The seed runs** (the captures): `cv3`: gen_wor_veldt from the tracked `wor-ragnarok-v1`
  at 33240ddc, "PASS (frame 40042) attempts=1/3"; `cg4`: gen_wor_gau from
  cv3's capture at 3a0cf4e8, "PASS (frame 33288) attempts=1/3".  Their
  captures seed `wor-veldt-cave-v1` and `wor-gau-v1`
- **Qualification**: QUAL.

## 8. Open

1. **GAU is L32**, his level from the World of Ruin's start, against TERRA
   and CELES's L50: the Veldt's battles pay him nothing he keeps a level on
   here, and he is the member most often down (the one death of the final
   sweeps' cave fights, when there was one, was his).  A grind, or the next
   arc's fights, decide it.
2. **Rage** waits for stronger rages: Leap on the Veldt (each return
   teaches the formation he left from) and a curated loadout (Skills ->
   Rage; AUTO leaves out M-TekArmor) are what a player would do next; the
   line is built and tested for when they come (section 5).
3. **Thirty more floor species** can come on the Veldt from this save
   (`veldt_set.py`: 44 in all, 14 met and authored).  Their areas (World of
   Balance side trips) are where to design them.
4. **The Mantodea pair** on the plain south of Narshe (world group 51,
   formation 325, 80/256) wiped the four the Narshe arc leaves there in one
   of the three keys the first sweep met; the arc's own leg takes no steps
   on that plain.  A lab for the Narshe arc's save, or levels for LOCKE (L41).
5. **SHADOW** waits at the Colosseum ($019F; the milestone that recruits
   him is v0.37's, "The Colosseum & Shadow").
6. **The logs number formations in nine bits**: the driver's `[outcome]` and
   `[board]` lines and `tools/fight_report.py` mask the formation word with
   `$1FF`, so Allo Ver's formation 515 reads as `$003` ("Bleary+Crawly");
   and the SrBehemoth's outcome line reads `$1A8` where its `[key]` line
   reads `g01C4` (formation 452), not explained here.  The counts here use
   the `[key]` lines.
