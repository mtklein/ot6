# World of Ruin: the Colosseum & Shadow

Milestone v0.37, #272 (with #383, Shadow's kit, and #387, the endgame gear
economy): from the save beside the Falcon by Figaro Castle (`wor-ancient-v1`,
where the v0.35 route ends) to Kohlingen's counter, the Dragon's Neck
Colosseum (map 413), the Striker wagered against SHADOW himself, who joins,
the wagers that trade the bag's gear up, the cabin with SHADOW seated,
Maranda's weapon counter for his throwing kit, his first fights on the plain
there, and a save beside the Falcon by Maranda (`wor-colosseum-v1`), the next
arc's boot.

Line numbers are into `ff6/src/event/event_main.asm` unless a file is named.
Evidence is under `build/attempts/wt/v037-colosseum/lab/` (the run logs and
the scripts beside them; the scripts that built them are the lab's own, in
`build/lab/col/` of the worktree, retained under the same evidence path).

---

## 0. Findings

1. **SHADOW waits at the Colosseum.**  Leaving Thamasa after the Veldt cave
   (v0.33) set `$019F` and the Colosseum's `$01EF` (route-wor-gau.md finding
   6); both read 1 in `wor-ancient-v1`.  The guard (413 NPC_10 (23,4),
   `_cb78c3`) asks "Care to fight in the colosseum?"; row 0 opens the wager
   list and then the fighter (`colosseum.asm`, menu states `$72` and `$76`).
2. **The Striker's fight is SHADOW's.**  `ColosseumProp` names Chupon and a
   hidden Striker for the Striker, but while `$01EF` stands
   `CheckColosseumShadow` sets `$0201` and `EventCmd_af` loads formation
   `$23E` instead of `$23F`: SHADOW himself, his own record (L25, 1050 HP in
   `wor-ancient-v1`) on the party's side, fights the fighter.  A win runs
   `_cb78d9`'s scene: `$02F3`, `$01EF` cleared, `norm_lvl SHADOW` (L41 against
   the four's L41-52), Interceptor set; with four seated he waits in the
   Falcon's cabin (party byte `$20`).  The Striker comes back.
3. **A Colosseum fight is the engine's.**  `InitParty` puts the fighter alone
   in seat 0 and sets `$3A97`; `RandCharAction` picks every command; nothing
   the player presses moves it.  A win adds the prize (`WinBattle`'s
   colosseum branch) and pays no experience; a loss takes the wager and
   leaves the fighter down.  The harness's outcome model expected
   experience ("XP MISMATCH" on every win in the first labs); it now pays a
   Colosseum battle nothing (`M.rewardDue`).
4. **The player's lever is the fighter.**  The fight runs itself, so the
   choice is who fights (and what they wear).  `H.colosseumFighter` sends the
   seated member of the highest level, then the most HP: CELES, L52, in this
   arc.
5. **The Colosseum has an inn** (413 NPC_3 (52,16), 400 GP) and no save
   point; its long exit (22,16) lands on the world's (50,18).
6. **The Ragnarok sword is not in this save.**  The route took the Magicite at
   Narshe (v0.32), so vanilla's only Illumina, the sword's wager, is out of
   reach (section 5).

## 1. The leg

| leg | boots | saves | what |
|---|---|---|---|
| `gen_wor_colosseum` | `wor-ancient-v1` | `wor-colosseum-v1` | Kohlingen's counter, the Colosseum: the Striker (SHADOW joins), four wagers; the cabin (SHADOW, CELES, CYAN, TERRA), the gear and relic care, CYAN's Strato pair, Maranda's weapon counter (SHADOW's skeans and edges) and gear stop, three fights on the plain by Maranda, the save on the Falcon's tile (69,183); also `wor_colosseum_in` (inside the Colosseum before the guard: `battle_colosseum`'s fixture) |

## 2. The order, the party and the wagers

The Falcon's tile by Figaro Castle -> Kohlingen (`kohlingenStop`: the bag to
the band) -> the Colosseum (world (50,17)) -> the wagers -> out (50,18) ->
the cabin -> Maranda (down on (69,183), the town's door (69,184)): the weapon
counter (shop 80) and the gear stop -> the plain beside the Falcon: three
fights -> the save.

The Colosseum is entered with the cabin's four from `wor-ancient-v1` (CELES,
RELM, CYAN, TERRA).  After the wagers the cabin seats SHADOW, CELES, CYAN and
TERRA: SHADOW for what only he brings (section 3), CYAN for his new Strato
pair, CELES and TERRA the strongest (L52-53).  RELM, STRAGO and the rest wait
aboard; the next arc's cabin can seat whom it needs.

**The wagers** (`WAGERS` in the generator).  The bag at `wor-ancient-v1`
read against `ColosseumProp` for what each item would fight and win; the
route bets what trades up into gear the party wears, against an opponent the
fighter beats:

| wager | opponent (row) | prize | for |
|---|---|---|---|
| Striker | SHADOW himself (no row: he fights as a character) | SHADOW joins; the Striker back | SHADOW |
| Assassin | Test Rider (3, pierce: the Narshe arc's) | SwordBreaker | LOCKE's blade (pierce, 164) |
| Stunner | Test Rider | Strato | CYAN's second Strato (his pair: 199 and 199 for 199 and 162) |
| Regal Crown | Opinicus (3, slash/bludgeon: Ebot's Rock's) | Genji Helmet | SHADOW's helmet |
| Soul Sabre | Opinicus | Falchion | TERRA's blade (over the Enhancer) |

Measured with CELES before the leg (labs `sw_stun_celes_s*`,
`sw_crown_celes_s*`: from one capture inside the Colosseum, seed shifts 0-29):
the Test Rider 8 of 8, the Opinicus 8 of 8 over 8 distinct keys.  Left out,
each by its own reason:

- **Tortoise Shield for a Titanium helmet** (the bag holds seven; Titanium is
  42/42 and absorbs water, over the party's Circlets): the opponent, the
  Steroidite (25,000 HP, Rush x3), beat CELES 7 times in 7 (lab
  `b_tort_celes`: "[colbet] bet 1 ... LOST" through "bet 7 ... LOST", keys
  be54, be5C, beA8, be38, be44, beDC, beB8), and each loss left her down for
  a Fenix Down.
- **The Gem Box for the Economizer**: every spell at 1 MP for its wearer,
  boosts included (`Ot6SpellMP` takes the Economizer before the boost
  price), so a caster wearing it never chooses between MP for random fights
  and MP for the boss, the tension the economy is built on (guidelines "MP
  tension is the target"; the same reason Osmose costs 8, mp-economy.md).
  The Gem Box stays in the bag.
- **The Cursed Shield** for a Cursed Ring: it is the Paladin Shield to be
  (section 5).
- The rest of the bag's table trades sideways (a Rage Ring for a Blizzard
  Orb and back), down (a Gold Hairpin for a Dragon Horn the bag holds), or
  into relics that cut encounters (the Moogle Charm's Charm Bangle).

## 3. Species and break rows

**Met on the leg.**  The Colosseum's opponents of the route's wagers (Test
Rider, Opinicus) carry the rows of the arcs that meet them at home (the
Narshe arc's and the Gogo arc's), checked there.  SHADOW's own fight has no
gauge: he is a character.  The plain by Maranda's Falcon (world group 49:
the Crawler trio; Mantodea with Sprinter and Spek Tor) carries the Cyan
arc's rows.  The K battles the sweeps used up met the plain by Figaro Castle
(world group 47: Bogy; Deep Eye with Muus; Maliga), the Falcon arc's rows.
No species met lacks an authored row.

**The lesson SHADOW brings.**  The cabin's other three hold blades (slash):
on the plain by Maranda every body takes pierce but the Mantodea, and the
Crawler takes no slash, so SHADOW's Striker keys the Crawler where CELES,
CYAN and TERRA's blades cannot (CELES's ice still finds it, as a spell).

**The Colosseum's own bodies.**  Three of the Colosseum's opponents are dealt
by no random or event group (`where`: every group's formations read from the
ROM), so the Colosseum is where players meet them, and the arc designs them.
The fighter's weapon is the key a player picks by picking who fights.

| species | L / HP | vanilla elements | shields | classes | why |
|---|---|---|---|---|---|
| Siegfried (the impostor) `$037` | 53 / 32,760 | weak to every element | 6 | slash, pierce | a swordsman: steel answers steel |
| Chupon (the Colosseum's) `$040` | 53 / 50,305 | weak ice, water; absorbs fire | 0 (no gauge) | — | the wager the Colosseum will not take; it sneezes the fighter out |
| SrBehemoth (the Colosseum's) `$07F` | 49 / 19,000 | weak fire, holy; absorbs poison | 6 | pierce, bludgeon | the dead beast, as the Veldt cave's: horn and bone |

The Colosseum's other 26 floor opponents (Dueller, Fortis, Innoc, Didalos,
Vectagoyle, Veteran, Steroidite and the rest) are dealt in the World of
Ruin's late pools (random groups 197-227: Kefka's Tower and the dragons'
hunts), whose arcs design them for the parties that meet them there.

`battle_breakwor_colosseum` checks the three rows in the built ROM and that
no group deals them; the route's five wagers' `ColosseumProp` records
(opponent and prize) and that each opponent has an authored row; every
formation of world group 49 against the four the cabin seats, and the
Crawler lesson; and #383's skean rows.  Lab `bw1`: "checked 3 designed rows
(the Colosseum's own bodies)", "checked 5 wagers' records", "checked 14
formation-species pairs of world group 49 (4 species)", PASS.  Red on the ROM
without the rows (`mutmain`, origin/main's battle sources: 7 mismatches,
"$037 Siegfried (the Colosseum's) has no Ot6ShieldTbl row") and on two
mutants: Siegfried without pierce (`mutRA`: "class mask $01, want $03"), the
SrBehemoth's row moved off it (`mutRB`: "has no Ot6ShieldTbl row (want 6,
class $06)").

## 4. The fights

No boss on the leg; the Colosseum's fights are the coin flips, if any, and
the measured rates say they are not:

| fight | fighter | sweep `s1` (K 0-5 at shifts 0 and 7) |
|---|---|---|
| SHADOW, for the Striker | CELES | 12 of 12, 11 distinct keys |
| the Test Rider, for the SwordBreaker | CELES | 12 of 12, 12 keys |
| the Test Rider, for the Strato | CELES | 12 of 12, 12 keys |
| the Opinicus, for the Genji Helmet | CELES | 12 of 12, 11 keys |
| the Opinicus, for the Falchion | CELES | 12 of 12, 11 keys |

(`tally_s1.txt`: "the Striker against SHADOW won 12 of 12, 11 distinct keys"
and the four lines after it.)  A loss of the Striker would take SHADOW with
it, so the leg fails on one (`want = "won"` raises an assertion, which the
runner does not retry; a person reloads); a loss of any other wager is
taken as a loss, logged, and the route goes on.

## 5. SHADOW's kit and the endgame gear economy

**SHADOW's kit (#383)** is in kits.md "Shadow": the eight throwing items
behind Throw, learned by acquisition; the skeans pierce; the smoke (Shadow
Edge, Image) and the exit (Inviz Edge, Vanish) reach one more ally per boost
point.

`battle_shadowkit` (from the leg's end state) plays one battle on the plain
by Maranda through the real menu: a Fire Skean at 0 BP lands a class chip on
a pierce-keyed body (Ot6ClassChip's store under the throw, the attack class
pierce); the smoke at 0 BP returns the mask SHADOW alone, and nobody else
gains Image; the exit at 1 BP SHADOW and the next ally, both vanished; the
smoke at 2 BP SHADOW and the next two it can land on, the vanished ally
passed over, each doubled.  Lab `sk3`: "masks 1, 3 and 13", PASS (frame
6830).  The first build of the reach failed it twice, and both are fixed in
the rule: `ChooseTarget` put the thrower alone back in the mask for
vanilla's targeting `$02` (lab `sk1`: "mask $03" but "entity 2 holds Vanish
after the throw: got false"), and a thrown item is physical, so it missed a
vanished ally (lab `sk2`).  Red on main ("symbol Ot6TrickReach not in
ff6-en.dbg") and on three ROM mutants: no reach (`mutTR`: "mask: got 1, want
3"), no skean rows (`mutSK`: "0 class chip(s) under it"), vanilla targeting
(`mutTB`: "entity 2 holds Vanish after the throw: got false").

The driver kept its lines (SHADOW's Fight, and the elemental skean line).
A sweep line, a skean whenever two or more standing bodies show pierce, was
A/B'd from the leg's end state over four fights a run at seed shifts 0, 3,
7, 11, 13 and 19 (px13): the Crawler trio took a median 3101 ticks over 15
keys with it, 2856 over 14 without (`fight_report_abon.txt`,
`fight_report_aboff.txt`), and Mantodea+Spek Tor+Sprinter 3153 against
2928.5; no deaths either way.  Kept out.

**The endgame gear economy (#387).**

- *The Colosseum's rewards* go into the kits as section 2 lists: CYAN's
  Strato pair (the gear policy leaves a Genji Glove's two hands to the kit,
  so the leg puts the second Strato in his second hand itself), SHADOW's
  Genji Helmet, TERRA's Falchion, LOCKE's SwordBreaker.
- *The Paladin Shield.*  The Cursed Shield lifts its curse after 256 battles
  won with it worn (`LearnItemMagic`: `$3EC0`, kept as `$1DD5`).  OT6 halves
  random encounters a step and doubles their experience and gil
  (`Ot6DangerMulW`, `Ot6RewardMulW`), so the vanilla count cost twice the
  walking.  The count now takes the same pair: a won random battle adds two,
  an event battle one (`Ot6CurseCount`, `ot6_gear.asm`), about 128 random
  battles worn.  `battle_cursecount` (from the leg's end state): the shield
  on SHADOW through the Equip screen, one random battle won, "$1DD5 = 2
  (battle var at the end 2), random true", PASS (lab `cc1`); red on the
  vanilla count and on main ("the count moves by two ...: got 1, want 2").
  Nobody wears it in this arc: the shield sets every stat -7, Condemned,
  Mute, Berserk, Muddle and Sap (route-wor-dreams.md section 9), and the arc
  fights a dozen random battles.  The stretch for it is a long run of random
  battles with no boss on a clock, on a member a Ribbon guards and the party
  can spare: the late World of Ruin's dungeons, or a grind before them.
- *Illumina.*  Vanilla's only Illumina is the Ragnarok sword's wager
  (against Didalos).  OT6 keeps the Narshe choice the route made, the
  Magicite (a magicite is a second job, a pillar), so this route has no
  Illumina, and a player who takes the sword keeps vanilla's way to it.  Left
  as it is.
- *The Economizer* is left in the Colosseum and not taken (section 2): a
  wearer's spells at 1 MP end the MP choice.  Whether it should change
  (a fraction of the cost rather than 1) is open (section 8).

## 6. Supplies and kits

**Supplies.**  `wor-ancient-v1` left 43 Potions and 19 Fenix Downs against
the band (about level x 1.5 Potions, about the level in Fenix Downs);
Kohlingen's counter (`kohlingenStop`) tops them up first ("potion=99 ...
fenix=20 remedy=20" leaving Kohlingen, lab `g3`).  The Colosseum's fights
spend nothing from the bag on a win; a loss leaves the fighter down for a
Fenix Down (the Steroidite's seven losses cost seven).  The bag at the save
(sweep `s1`, `s1_k0_s0`): "potion=76 tincture=40 fenix=20 remedy=20
revivify=30 tent=0 gil=665742".

**Kits.**  SHADOW joins with nothing worn; the cabin's gear care dresses him
from the bag (the Striker back from his fight, the Genji Shield, the
Colosseum's Genji Helmet, a Power Sash) and Maranda's armor counter sells him
a Dark Gear; the relic care gives him the Memento Ring and a Peace Ring.
Maranda's weapon counter sells his throwing kit: Fire Skeans, Water Edges and
Bolt Edges to nine each, Shadow Edges and Inviz Edges to four (the bag's ten
Shuriken were already there).  CYAN's second Strato goes in his second hand;
TERRA's Falchion replaces the Enhancer (the gear policy).  The kit at the
save (`s1_k0_s0`): "SHADOW L41 kit FF 29 64 81 96 DB B2; CELES L53 kit 0A 19
15 7A 98 D1 BB; CYAN L42 kit 0E 31 31 7A 98 D1 CA; TERRA L53 kit 06 15 5E 7A
94 CA BB".

## 7. Played

Each sweep run is one attempt (retries off) from a committed tree
(`commit.txt`, `diff.sha256`), the leg's variant with K battles used up first
on the plain by Figaro Castle where the boot stands (world group 47:
`mkvar.py`), K 0-5 at seed shifts 0 and 7, from the tracked
`wor-ancient-v1`.  `tally_<p>.txt` lists each run and the wagers by key;
`fight_report_<p>.txt` is `tools/fight_report.py` over the runs (its "Pugs"
label on formation `$23F` is the formation's placeholder slot: the opponent
there is the wager's).

| sweep (commit) | runs | fights (fight_report) |
|---|---|---|
| `s2` (cb122cdb, the arc's ROM: the rows, the reach, the curse count; CYAN's pair) | 12 of 12 PASS, attempts=1/1 each (the Air) | every fight won: SHADOW's `$23E` 11 keys; the wagers' `$23F` 33 keys of 48 fights (`tally_s2.txt`: the Striker 11 keys, the SwordBreaker 12, the Strato 11, the Genji Helmet 10, the Falchion 12, each 12 of 12); the Crawler 26 keys, Mantodea+Spek Tor+Sprinter 5, Bogy 7, Maliga 2; no deaths but SHADOW's own in his fight |
| `s1` (155c284f) | 12 of 12 PASS, attempts=1/1 each | every fight won: SHADOW's `$23E` 11 keys; the wagers' `$23F` 35 keys of 48 fights; the Crawler 26 keys, Mantodea+Spek Tor+Sprinter 6, the K battles' Bogy 7 and Maliga 2; no deaths but SHADOW's own in his fight |

The tracked checkpoint was first sealed from a lab capture (`g4`, "PASS
(frame 42059) attempts=1/3") and then re-cut from the graph's own play at
869cf79d (`checkpoint_drift.py --recut`: "none -- the tracked save is the
one the graph's play makes today"; the leg's log in
`build/attempts/wt/v037-colosseum/qual/logs/wor_colosseum.log`: "PASS
(frame 47443) attempts=1/3", won on its first attempt; "the wagers done: 5
of 5 won").

## 8. Open

1. **The tricks have no driver line.**  A player throws the smoke before a
   physical boss; the arc has no boss after SHADOW joins, so the line waits
   for an arc with one to measure it on.
2. **The Economizer** (section 5): kept from the route; a rule that keeps the
   MP choice (a fraction of the cost) would let the Gem Box's wager in.
3. **The Paladin Shield**: the count is halved for random battles; the route
   has not yet chosen who wears the shield, or where.
4. **The Colosseum's late opponents** (section 3) are designed by the arcs
   whose pools deal them.
5. **SHADOW's level**: L41 against CELES and TERRA's L53, as CYAN came back
   from his dream (route-wor-dreams.md section 8).  The plain by Maranda's
   fights lost no one; the arc does not grind him.
