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
The Gem Box's wager (owner, 2026-10-26) has its own, under
`build/attempts/wt/v037-economizer/` (`lab/`, with `lab/scripts/`, and
`qual/px13/`), and the line with CELES's Flame Sabres under
`build/attempts/wt/v037-economizer-5/` (`lab/`, `scripts/`, `qual/px13/`).

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
   seated, standing member of the highest level, then the most HP.  From the
   graph's `wor-ancient-v1` (CELES and TERRA L52, CELES with 4 more HP) that
   is CELES; when the battles before the Colosseum raise TERRA a level, it is
   TERRA (sweep `s3`, section 4).
5. **The Colosseum has an inn** (413 NPC_3 (52,16), 400 GP) and no save
   point; its long exit (22,16) lands on the world's (50,18).
5. **The Ragnarok sword is not in this save.**  The route took the Magicite at
   Narshe (v0.32), so vanilla's only Illumina, the sword's wager, is out of
   reach (section 5).

## 1. The leg

| leg | boots | saves | what |
|---|---|---|---|
| `gen_wor_colosseum` | `wor-ancient-v1` | `wor-colosseum-v1` | Kohlingen's counter, the Colosseum: the Striker (SHADOW joins), five wagers (the last, the Gem Box, for TERRA's Economizer); the cabin (SHADOW, CELES, CYAN, TERRA), the gear and relic care, CYAN's Strato pair, Maranda's weapon counter (SHADOW's skeans and edges) and gear stop, three fights on the plain by Maranda, the save on the Falcon's tile (69,183); also `wor_colosseum_in` (inside the Colosseum before the guard: `battle_colosseum`'s fixture) |

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
| Gem Box | SrBehemoth (the Colosseum's: 6, pierce/bludgeon; weak fire, holy) | Economizer | TERRA's relic (section 5) |

Measured with CELES before the leg (labs `sw_stun_celes_s*`,
`sw_crown_celes_s*`: from one capture inside the Colosseum, seed shifts 0-29):
the Test Rider 8 of 8, the Opinicus 8 of 8 over 8 distinct keys.

**The Gem Box's fight** (owner, 2026-10-26: "economizer should make spells
cost 1 MP", so the route takes it).  The SrBehemoth is the one opponent here
the fighter rule's pick does not beat every time, and the player's lever,
who fights and what they wear, is what moves it.  Labs from one capture
inside the Colosseum (`col_in`, made from the tracked `wor-ancient-v1`), one
bet each, field care to full before it, under
build/attempts/wt/v037-economizer/lab/:

| fighter, kit | runs | won (distinct keys) | how the losses went |
|---|---|---|---|
| CELES, her Scimitar and Falchion (`fc_celes_s*`) | 14 | 9 (7 of 9 keys) | worn down, on be18 (shifts 0-2) and be28 (3, 5): "[death] f+6823 entity 0 char 6 from 88/3984 by slot 0 cmd $00 atk $EE" |
| TERRA, her blades (`fc_terra_s*`) | 5 | 1 (1 of 5 keys) | her random Magic turns on her: "by entity 0 char 0 cmd $02 atk $04 (its own action)" (Drain, which the undead body reverses: be84, be94) and "atk $17" (Merton: beA0) |
| CYAN, his Stratos (`fc_cyan_s*`) | 5 | 0 (0 of 5 keys) | worn down, and once his own Bushido |
| CELES, Dragoon Boots for the Wall Ring (`db_celes_s*`; the Relic menu's re-equip also changed her helmet) | 14 | 10 (7 of 9 keys) | worn down (be60, be90) |
| CELES, the bag's two Flame Sabres (`fl_celes_s*`) | 14 | 14 (13 of 13 keys) | none |

(The first pass, `gem_celes_s*` and `gem_terra_s*`, bet without the field
care first and drew the same keys: CELES 5 of 7 runs, TERRA 2 of 7 runs, 2
of 6 keys; superseded by the `fc_` labs.)

So the leg sends CELES for the Gem Box, not the rule's pick (which is TERRA
once the battles before the Colosseum raise her a level), and arms her first
when it can: her Genji Glove's two hands take the bag's Flame Sabres (fire,
the SrBehemoth's weakness; `battle_breakwor_colosseum` checks the weak
byte), and her own blades go back after the fight (`WAGERS`' `fighter` and
`arm`).  The Gem Box is the last wager, so no other fight sees the Sabres.
On the line from power-on the bag holds two (Tzen's weapon counter tops
CELES's Flame Sabres up to a pair, `gen_wor_sabin`), so CELES fights the
Gem Box in both ("[kit] CELES L52 kit 0A 0D 0D 7A 98 D1 BB" in the
qualified play and in every run of section 4's `a5` and `a6`).  For a
while the play from power-on held none (a loss upstream, since fixed), and
the sweep `s4` measured CELES in her own blades on that line (section 4).
The bag holds one Gem Box and a loss takes it, so a lost wager
is a lost attempt (`reload`: the leg raises "LOST: ...", and the runner
retries from the boot, counted, as a person reloads).  TERRA's
self-inflicted losses also end the harness's run, not just the wager: the
battle table read wiped for 369 frames and the wipe canary counted a game
over ("canary: BATTLE WIPE ... Counted as a game over", `fc_terra_s3`),
where CELES's losses to the opponent hand back as lost wagers (section 8).

Left out, each by its own reason:

- **Tortoise Shield for a Titanium helmet** (the bag holds seven; Titanium is
  42/42 and absorbs water, over the party's Circlets): the opponent, the
  Steroidite (25,000 HP, Rush x3), beat CELES 7 times in 7 (lab
  `b_tort_celes`: "[colbet] bet 1 ... LOST" through "bet 7 ... LOST", keys
  be54, be5C, beA8, be38, be44, beDC, beB8), and each loss left her down for
  a Fenix Down.
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
no group deals them; the route's six wagers' `ColosseumProp` records
(opponent and prize) and that each opponent has an authored row; every
formation of world group 49 against the four the cabin seats, and the
Crawler lesson; and #383's skean rows.  Lab `bw1`: "checked 3 designed rows
(the Colosseum's own bodies)", "checked 5 wagers' records", "checked 14
formation-species pairs of world group 49 (4 species)", PASS.  Red on the ROM
without the rows (`mutmain`, origin/main's battle sources: 7 mismatches,
"$037 Siegfried (the Colosseum's) has no Ot6ShieldTbl row") and on two
mutants: Siegfried without pierce (`mutRA`: "class mask $01, want $03"), the
SrBehemoth's row moved off it (`mutRB`: "has no Ot6ShieldTbl row (want 6,
class $06)").  With the Gem Box's record added (it names the SrBehemoth and
the Economizer): lab `bw_gem`, "checked 6 wagers' records", PASS; red with
the prize wanted one off (`mutGB_bw`: "MISMATCH: the Gem Box's prize $CE, the
route plays for $CD"), both under build/attempts/wt/v037-economizer/lab/.

## 4. The fights

No boss on the leg; the Colosseum's fights are the coin flips, if any, and
the measured rates say they are not.  Sweep `s3` played the route that ships:
the qualified commit 1b22315d, from the graph's own `wor-ancient-v1` capture
(`OT6_SRAM_CHECKPOINT=build/checkpoints/wor-ancient-v1`), K 0-5 battles used
up first at seed shifts 0 and 7.  The fighter is the rule's: CELES in the
ten runs with K 0-4, TERRA in the two with K 5 (her K battles took her to
L53):

| fight | sweep `s3`: won (distinct keys); CELES 10 runs, TERRA 2 |
|---|---|
| SHADOW, for the Striker | 12 of 12 (11) |
| the Test Rider, for the SwordBreaker | 12 of 12 (10) |
| the Test Rider, for the Strato | 12 of 12 (11) |
| the Opinicus, for the Genji Helmet | 12 of 12 (9) |
| the Opinicus, for the Falchion | 12 of 12 (12) |

(`tally_s3.txt`: "the Striker against SHADOW won 12 of 12, 11 distinct keys"
and the four lines after it; CELES fought 50 of the 60, TERRA 10, all won.)
The earlier sweeps (`s1`, `s2`, from the tracked `wor-ancient-v1`, where
TERRA and CELES are both L52 and the battles before the Colosseum often take
TERRA to L53) sent TERRA in 8 runs of 12 and CELES in 4 each: 40 fights
TERRA, 20 CELES, all won (`run.out`'s "char 0 WON" and "char 6 WON" lines).
So TERRA has 90 won fights in all (80 from the tracked entry, 10 here) and
CELES 90 (40 there, 50 here).

**With the Gem Box and the Flame Sabres** (the line as it ships), sweeps
`a5` (seed shifts 0 and 7) and `a6` (13 and 22) played the same way at
a0645150 (02409c87's tree), the Economizer's price rule in, from the graph's own
`wor-ancient-v1` capture of that commit's play from power-on
(build/attempts/wt/v037-economizer-5/lab/, px13).  CELES fought every wager
with K 0-1 and TERRA the five before the Gem Box with K 2-5; CELES fought
the Gem Box in all 24, in two Flame Sabres every time
(`fighters_a5.txt`, `fighters_a6.txt`: "a5_k2_s0 0 WON, 0 WON, 0 WON, 0 WON,
0 WON, 6 WON"):

| fight | `a5` and `a6`: won (distinct keys) |
|---|---|
| SHADOW, for the Striker | 24 of 24 (18) |
| the Test Rider, for the SwordBreaker | 24 of 24 (18) |
| the Test Rider, for the Strato | 24 of 24 (17) |
| the Opinicus, for the Genji Helmet | 24 of 24 (21) |
| the Opinicus, for the Falchion | 24 of 24 (19) |
| the SrBehemoth, for the Economizer | 24 of 24 (17) |

(`tally_a56.txt`: "the Gem Box for the Economizer, TERRA's (vs SrBehemoth)
won 24 of 24, 17 distinct keys"; `a5` alone 12 of 12, 10 keys, `a6` 12 of
12, 11.)  Every run passed on its one attempt ("PASS ... attempts=1/1");
the only deaths were SHADOW's own in his fight and CYAN's twice on the
plain by Maranda (`deaths_a56.txt`).

Before the Sabres were back on the line, sweep `s4` played the same
way at 6a7a8130 from the graph's own `wor-ancient-v1` capture on the ROM of
9d654d6f (before the Economizer's price rule; build/attempts/wt/v037-economizer/lab/,
px13), and `t1` (0d2d347a) and `t2` (6888e25e, CELES's blades back after the
fight) from the tracked one:

| fight | `s4`: won (distinct keys) | `t1` | `t2` |
|---|---|---|---|
| SHADOW, for the Striker | 12 of 12 (11) | 12 of 12 (11) | 12 of 12 (11) |
| the Test Rider, for the SwordBreaker | 12 of 12 (10) | 12 of 12 (12) | 12 of 12 (12) |
| the Test Rider, for the Strato | 12 of 12 (11) | 12 of 12 (11) | 12 of 12 (11) |
| the Opinicus, for the Genji Helmet | 12 of 12 (9) | 12 of 12 (10) | 12 of 12 (10) |
| the Opinicus, for the Falchion | 12 of 12 (12) | 12 of 12 (12) | 12 of 12 (12) |
| the SrBehemoth, for the Economizer | 12 of 12 (11) | 12 of 12 (12) | 12 of 12 (12) |

(`tally_s4.txt`: "the Gem Box for the Economizer, TERRA's (vs SrBehemoth)
won 12 of 12, 11 distinct keys".)  In `s4` the rule sent CELES for every
wager with K 0-4 and TERRA for the five before the Gem Box with K 5; CELES
fought the Gem Box in all twelve (`fighters_s4.txt`: "s4_k5_s0 0 WON, 0 WON,
0 WON, 0 WON, 0 WON, 6 WON").  That line held no Flame Sabres, so `s4`'s twelve
are CELES in her own blades ("no $0D in the bag to arm CELES" in every run);
`t1` and `t2`, from the tracked save, armed her.  CELES in her own blades
against the SrBehemoth: 12 of 12 on that line (`s4`, 11 keys), 9 of 14 from
the tracked save's capture (`fc_celes`, 7 of 9 keys).  In two Flame Sabres:
62 of 62 (`a5` and `a6` 24, 17 keys, on the line that ships; `fl_celes` 14,
13 keys; `t1` and `t2` 24, 12 keys each).  A loss of the Gem Box is a lost attempt, retried
from the boot (section 2).  A loss of the Striker would take SHADOW with
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
  Genji Helmet, TERRA's Falchion, LOCKE's SwordBreaker, TERRA's Economizer.
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
- *The Economizer* (the Gem Box's prize, section 2): every spell its
  wearer casts costs 1 MP at any boost (owner, 2026-10-26: "economizer
  should make spells cost 1 MP", taken literally).  Vanilla's relic
  arithmetic already gave a tier its 1 (`Ot6SpellMP`), but a spell outside
  the fold families (Drain, Quake, a summon, a lore) then took
  `Ot6BoostPriceFor`'s x2.5 per point on top, 3, 6 and 16 MP at 1-3 BP; now
  `Ot6MagicPrice` answers 1 for an Economizer wearer before either rule,
  Strago's study included.  `battle_economizer` (Continue wor-colosseum-v1,
  TERRA's Drain at 1 and 3 BP, her Fire folded at 2 BP and her Drain at
  0 BP, each through the real menu, the pool's own movement attributed to
  the cast): PASS on this ROM (lab `econ_economizer`: "cast 2 (f5063):
  spell $04 at 3 BP: MP 637 -> 636"); red on origin/main's
  `ot6_boost.asm` (`main_economizer`: "Drain at 1 BP costs the Economizer's
  1 MP: got 3 ($3), want 1 ($1)") and on the mutant reading the Gold
  Hairpin's bit (`mutHP_economizer`, the same line).  The harness's price
  model (`H.spellPrice`, `H.battleSpellPrice`) answers 1 the same way.
  It goes to TERRA, the party's caster: of the four the cabin seats she has
  learned the most spells ("spells learned: TERRA 7, CELES 6, SHADOW 0,
  CYAN 0", the relic care's own line in the leg's log), her Magic carries
  the party's Cure and Life, and her Fire's boost ladder (Fire 2, Fire 3,
  Ultima at 80 MP once the fold opens, kits.md "Terra") is the most
  expensive casting any of the four does.  CELES's Runic refills her own
  MP.  The leg puts it on TERRA's slot that does not hold her Ribbon (the
  Wall Ring from the tower's MagiMaster kit comes off); the relic rule
  leaves a worn relic it does not rank where it is (`H.relicPlan` step 1),
  so the dressings after it keep it on, and the leg's exit asserts TERRA
  wears it (red with the equip step taken out: lab `mutEQ2`).  The MP
  choice stays with the other three.

## 6. Supplies and kits

**Supplies.**  The graph's `wor-ancient-v1` left 80 Potions and 25 Fenix
Downs (the qualified play's boot line, build/attempts/wt/v037-economizer-5/
qual/px13/wor_colosseum.log: "potion=80 tincture=40 fenix=25 remedy=20
revivify=30 tent=0 gil=654711")
against the band (about level x 1.5 Potions, about the level in Fenix
Downs); Kohlingen's counter (`kohlingenStop`) tops the Potions up first.  The Colosseum's fights
spend nothing from the bag on a win; a loss leaves the fighter down for a
Fenix Down (the Steroidite's seven losses cost seven).  A won fight can
still leave the fighter hurt, and the field care after it pays in Potions:
the bag at the save of the qualified play, "potion=64 tincture=40 fenix=25
remedy=18 revivify=30 tent=0 gil=646143".

**Kits.**  SHADOW joins with nothing worn; the cabin's gear care dresses him
from the bag (the Striker back from his fight, the Genji Shield, the
Colosseum's Genji Helmet, a Power Sash) and Maranda's armor counter sells him
a Dark Gear; the relic care gives him his relics from the bag (below).
Maranda's weapon counter sells his throwing kit: Fire Skeans, Water Edges and
Bolt Edges to nine each, Shadow Edges and Inviz Edges to four (the bag's ten
Shuriken were already there).  CYAN's second Strato goes in his second hand;
TERRA's Falchion replaces the Enhancer (the gear policy).  CELES fights the
Gem Box in the bag's two Flame Sabres (section 2) and takes her Scimitar and
Falchion back after it;
TERRA's Economizer takes her Wall Ring's slot (section 5).  In
the qualified play the relic care gave SHADOW the Memento Ring and a Peace
Ring, CYAN keeping his Genji Glove and Ribbon.  The kit at the save: "SHADOW
L41 kit FF 29 64 81 96 DB B2; CELES L52 kit 0A 19 15 7A 98 D1 BB; CYAN L41
kit 0E 31 31 7A 98 D1 CA; TERRA L53 kit 06 15 5E 7A 94 CA CE".

## 7. Played

Each sweep run is one attempt (retries off) from a committed tree
(`commit.txt`, `diff.sha256`), the leg's variant with K battles used up first
on the plain by Figaro Castle where the boot stands (world group 47:
`mkvar.py`), K 0-5 at seed shifts 0 and 7 (`a6`: 13 and 22): `s3` from the graph's own
`wor-ancient-v1` capture at the qualified commit, `s1` and `s2` (before the
rebase onto the Tritoch leg and the Dance ladder) from the tracked one; with
the Gem Box (build/attempts/wt/v037-economizer/lab/), `s4` from the graph's
own capture on the ROM before the price rule, `t1` and `t2` from the tracked
one; with the Flame Sabres back on the line
(build/attempts/wt/v037-economizer-5/lab/), `a5` and `a6` from the graph's
own capture on this ROM.  `tally_<p>.txt` lists each run and the wagers by key;
`fight_report_<p>.txt` is `tools/fight_report.py` over the runs (its "Pugs"
label on formation `$23F` is the formation's placeholder slot: the opponent
there is the wager's).

| sweep (commit) | runs | fights (fight_report) |
|---|---|---|
| `a5` (a0645150; px13) | 12 of 12 PASS, attempts=1/1 each | every fight won; the Gem Box 12 of 12, 10 keys, CELES in two Flame Sabres |
| `a6` (a0645150, shifts 13 and 22; px13) | 12 of 12 PASS, attempts=1/1 each | every fight won; the Gem Box 12 of 12, 11 keys, CELES in two Flame Sabres |
| `s4` (6a7a8130; px13) | 12 of 12 PASS, attempts=1/1 each | every fight won: SHADOW's `$23E` 11 keys; the wagers' `$23F` 39 keys of 60 fights; the Crawler 28 keys, Mantodea+Spek Tor+Sprinter 6 (one death: CYAN, `s4_k3_s0`, "[death] f+665 entity 2 char 2 ... by slot 0"), Bogy 8, Maliga 2 |
| `t2` (6888e25e; px13) | 12 of 12 PASS, attempts=1/1 each | every fight won: SHADOW's `$23E` 11 keys; the wagers' `$23F` 35 keys of 60 fights; the Crawler 25 keys, Mantodea+Spek Tor+Sprinter 5 (one death), Bogy 7, Maliga 2 |
| `t1` (0d2d347a: CELES kept the Flame Sabres; px13) | 12 of 12 PASS, attempts=1/1 each | every fight won: as `t2` |
| `s3` (1b22315d, qualified; px13) | 12 of 12 PASS, attempts=1/1 each | every fight won: SHADOW's `$23E` 11 keys; the wagers' `$23F` 35 keys of 48 fights; the Crawler 24 keys, Mantodea+Spek Tor+Sprinter 6, Bogy 8, Maliga 2; no deaths but SHADOW's own in his fight |
| `s2` (cb122cdb, the arc's ROM: the rows, the reach, the curse count; CYAN's pair) | 12 of 12 PASS, attempts=1/1 each (the Air) | every fight won: SHADOW's `$23E` 11 keys; the wagers' `$23F` 33 keys of 48 fights (`tally_s2.txt`: the Striker 11 keys, the SwordBreaker 12, the Strato 11, the Genji Helmet 10, the Falchion 12, each 12 of 12); the Crawler 26 keys, Mantodea+Spek Tor+Sprinter 5, Bogy 7, Maliga 2; no deaths but SHADOW's own in his fight |
| `s1` (155c284f) | 12 of 12 PASS, attempts=1/1 each | every fight won: SHADOW's `$23E` 11 keys; the wagers' `$23F` 35 keys of 48 fights; the Crawler 26 keys, Mantodea+Spek Tor+Sprinter 6, the K battles' Bogy 7 and Maliga 2; no deaths but SHADOW's own in his fight |

The tracked checkpoint is re-cut from the qualified play
(build/attempts/wt/v037-economizer-5/qual/px13/): bare `ninja -k 0` at
a0645150 on a clean tree, the line from power-on with the Gem Box's route
and the Flame Sabres (`q1.log`: "sha=a064515036ea... dirty=0"; a0645150 is
02409c87's tree, the branch's commit before its first commit message was
reworded).  It played
every leg and suite green but one selftest, which still priced the
Economizer's boosted spells the old way ("FAIL tools/tests/spell_price_selftest.lua
... relic$40 boost1 price got1 want3"); its expectation was corrected with the
rule, and the branch's own bare `ninja` re-ran it (`q2.log`).  The capture
drifted from the tracked save by the line's own history and the wager
(`drift_wor-colosseum-v1.txt`: "TERRA gear: fresh 15 5E 7A 94 CA CE, tracked
15 5E 7A 94 CA BB", "item $0D: fresh 2, tracked 0", "item $D8: fresh 0,
tracked 1", "gil: fresh 646143, tracked 714410"), and `checkpoint_drift.py
--recut wor-colosseum-v1` made the tracked save the capture ("none -- the
tracked save is the one the graph's play makes today",
`recut_wor-colosseum-v1.txt`).  The leg's log (`wor_colosseum.log`): "PASS
(frame 55093) attempts=1/3", won on its first attempt; "the wagers done: 6
of 6 won", CELES sent every time and armed for the Gem Box ("[kit] CELES L52
kit 0A 0D 0D 7A 98 D1 BB").  The earlier qualification of the wager, before
the Sabres were back, is under build/attempts/wt/v037-economizer/qual/px13/.
The arc's earlier qualification (1b22315d, before the Gem Box) is under
build/attempts/wt/v037-colosseum/qual/px13/ (`q4.log`, `q6.log`).

## 8. Open

1. **The tricks have no driver line.**  A player throws the smoke before a
   physical boss; the arc has no boss after SHADOW joins, so the line waits
   for an arc with one to measure it on.
2. **The Paladin Shield**: the count is halved for random battles; the route
   has not yet chosen who wears the shield, or where.
3. **The Colosseum's late opponents** (section 3) are designed by the arcs
   whose pools deal them.
4. **SHADOW's level**: L41 against CELES and TERRA's L53, as CYAN came back
   from his dream (route-wor-dreams.md section 8).  The plain by Maranda's
   fights lost no one; the arc does not grind him.
5. **A Colosseum fighter who kills herself ends the run.**  When TERRA's own
   Drain or Merton took her last HP, the battle table read wiped for 369
   frames and the harness's wipe canary counted a game over ("canary:
   BATTLE WIPE ... Counted as a game over", lab `fc_terra_s3`) instead of a
   lost wager; a loss to the opponent hands back at once.  The route does not
   meet it (CELES fights the Gem Box), but `H.colosseumBet` should take it as
   a loss.
