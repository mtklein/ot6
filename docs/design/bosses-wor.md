# WoR bosses, boss by boss

Scope: every boss and event fight of the World of Ruin, from the Figaro
Tentacles to Kefka, in the order the automated line meets them. It is the
World of Ruin counterpart of [bosses-wob.md](bosses-wob.md) and assumes
that document's boss contract. Issue #561. It began as a survey that
changed no ROM byte; **unit A of its build order is now built** (section
1.3: the cancel, the lit-fuse mark, and the fuses of Atma, the Gold Dragon
and Kefka, with the World of Balance's AtmaWeapon). Every other telegraph
here is design text. Each block says what is built, what the vanilla script
offers as a wind-up, and what is proposed.

The owner's rulings on the contract (2026-11-23), written into
bosses-wob.md's contract and assumed below: after a cancel the trigger is
earned again; an announced move always fires unless a break cancels it,
and any roll is made before the announce ("don't announce anything that
won't happen. however, okay to make a roll before that to determine
whether or not to do the whole sequence"); Kefka's telegraph is Goner
("sounds well integrated with the game"); and a break releases whatever
the broken body holds ("definitely breaking a tentacle should free a party
member. if possible same for enemies that swallow party members
temporarily").

Owner's direction for the survey (2026-11-23): "carefully designed boss
fights sounds like the right place to focus. every boss should be
interesting and ideally distinct. telegraphed big moves that a break
cancels sounds right out of octopath." So each boss also gets a **hook**:
one line saying what makes its fight different from every other boss in
the game. Hooks come from the vanilla script first, and from Octopath's
vocabulary only where vanilla offers nothing.

Source lines are cited as `file:line` at f3f644c7 (`ai_script.asm` is
`ff6/src/battle/ai_script.asm`, `ot6_hud.asm` and `ot6_break.asm` are in
`ff6/src/battle/`, `battle_main.asm` likewise). Play is cited as
`build/states/<leg>.log:line`: the main tree's logs of the line played on
2026-11-22 (ROM identity `bb39e5e3d1e2`, `build/states/wor_falcon.stamp`).
One fight a boss is one draw, not a rate; where a route document measured
a rate, its section is cited. The raw lines behind every play number here
are collected in `build/attempts/wt/v051-bosses-wor/raw_lines.md`
(made by `rawlines.py` beside it; `evidence.sh` regenerates the ROM-side
files). "Not measured" means no log shows it.

## 1. The contract in the World of Ruin: what is built

Read from the source before anything was proposed.

- **Every WoR boss has an authored shield row.** `Ot6ShieldTbl`
  (`ot6_hud.asm:2001`) holds a row for each body in section 6 of
  wor-coverage.md and for the final battle (`ot6_hud.asm:2700-3510`). No
  WoR boss has an `Ot6ElemAddTbl` row: that table's three WoR entries are
  the L.20 Magic, the L.70 Magic and the Phase (`ot6_break.asm:297-306`),
  so every boss's elements are vanilla's.
- **No AI script is changed, for any boss in either world.**
  `ai_script.asm` has one commit, the flatten that brought the disassembly
  in (`git log -- ff6/src/battle/ai_script.asm`: `fba50e7f`), and no line
  of it mentions OT6.
- **No telegraph was built, in either world, when this was surveyed**
  (section 1.3 says what is built since). The word appeared in the ROM
  source once, in a comment about Diamond Dust (`battle_main.asm:7084`),
  and in no test or tool.
  bosses-wob.md's telegraph lines ("he giggles and frost crawls the
  ground") are design text; two of its blocks already say so (Rizopas:
  "Nothing about it is a telegraph the AI script honours",
  bosses-wob.md:519-521; Nerapa: "is not in the script", :1150-1151). The
  one WoB fuse a player sees is vanilla's own: AtmaWeapon's "Vast energy
  focused", two glowing turns, then Flare Star (`ai_script.asm:5179-5196`).
- **What is built is the other half of the contract**: a Broken monster
  takes no turn (`Ot6Gate`, `ot6_break.asm:1945`; `Ot6BrokenTurn`, :2302),
  makes no counterattack (`Ot6MayAct`, :1994), and still plays the story
  blocks of its counter with their attacks taken out (`Ot6RetalStory`
  :2111, `Ot6AIBlockStory` :2153, `Ot6AISkip` :2208). The suites are
  `battle_brokendeath`, `battle_vargas`, `battle_ultros1`,
  `battle_ultros4`, `battle_stophead` and `battle_kefka`.

### 1.1 What a break did to a vanilla fuse (before unit A)

Measured since, on the ROM the survey read (f3f644c7), by the fuse suites
run as labs with the cancel's asserts off
(`build/attempts/wt/v051-fuse/measure/`): in all four fights the break
delayed the move and no more. AtmaWeapon's Flare Star and Atma's Ultima
came on the boss's second turn back, the Gold Dragon's Bolt 3 and Kefka's
Goner on the first, none with a new line ("the break DELAYED the fuse",
one line a log). Three Fights on a Broken Gold Dragon took its count from
2 to 5 and lit the charge inside the break (golddrgn.log: "the cells at
recovery: 07 313B 05 01 0 (at the break: 07 313B 02 00 0)"). The reading
below stands, with the one correction marked.

A monster's turn runs its script from the top (`ExecMonsterAction`,
`battle_main.asm:489-509`). `wait` ends the turn and saves where the next
one resumes: the resume address in `$3d0c,x` and the index of the block it
stopped in, in `$3240,x` (`AICmd_fd`, :4417; the reload at
`NextAICmd`, :4487-4503). `end_if` and `end` store `$ff` there, so the next
turn starts its block from the top (`AICmd_fe`, :4428-4432).

A Broken monster's turn is emptied before its script runs
(`Ot6BrokenTurn`), so neither cell moves. Three consequences, read from
the source and **not measured live**:

1. **A break delays a script fuse; it does not cancel it.** AtmaWeapon
   Broken between its two glowing turns resumes at the second glow when it
   recovers. The contract says the opposite ("the charge does not resume
   when the boss recovers, and has to be started again",
   bosses-wob.md:14-17).
2. **Timers run through a break.** The battle and monster timers count
   every 16 frames for every body present (`GlobalCounter_01`,
   `battle_main.asm:15792-15806`), Broken or not; a timer condition reads
   half the count (`AICond_0b`, :4871-4876), so `if_monster_timer 40` is
   about 1,280 frames, less than a break's 2,159 (DESIGN.md "Break"). A
   timed move is due on the boss's first turn back.
3. **A hit counter stops or runs by what else its block holds.** A counter
   block with a story command (a `dlg`, a monster entering or leaving)
   runs while its monster is Broken, attacks removed; any other counter
   block is skipped whole (`Ot6AISkip`). So hits landed in a break window
   do not count toward Dullahan's, Atma's, the Goddess's or the
   Poltrgeist's counters, and do count toward the Gold Dragon's (its
   block holds `dlg $73`), Doom's (`dlg $88`) and the demon Chadarnook's
   (`show_monsters`).

One reading correction that moves several counts by one:
`if_battle_var_greater v, n` is true at **n or more**, not above n
(`AICond_0d`, `battle_main.asm:4884-4889`: `lda $ee / cmp $3a2f`, carry set
at or above). **Measured since, and the count is one more than that
reading gave**: a script's variable commands are queued like its attacks
and run after the script has been read, so a condition in the same block
reads the variable before that run's own `add`. A tally that says "n or
more" after an add is met by the run after the nth: Atma charges on the
**thirteenth** counted hit (`battle_atma`: "the tally climbed from 0 to
13"), the Gold Dragon on the **fifth** Fight (`battle_golddrgn`: "the
count climbed from 0 to 5"). By the same reading Dullahan's combo is armed
by the ninth counter and the demon Chadarnook leaves on the fifth, as the
route documents said; those two are not measured.

### 1.2 How a telegraph is built

Four pieces, all built by unit A (section 1.3); this is the survey's plan
for them, kept for the reasons.

1. **The fuse block, in the boss's own script, in vanilla's idiom.**
   AtmaWeapon's block is the pattern: a condition, a `dlg`, a glow,
   `wait`, the move, the trigger cleared, `end_if`. Six WoR scripts already
   hold one (section 2's "vanilla" telegraphs). The announce rides on a
   turn the boss already takes, so its number of attacks does not change
   (open question 3).
2. **Room for the scripts.** The script block is a fixed `$3950` bytes
   (`ai_script.asm:22`, closed at :8176) and the built ROM leaves fewer
   than ten free (`build/attempts/wt/v051-bosses-wor/ai_block_free.txt`:
   "trailing $ff run: 9 bytes", "highest script pointer $3946 of $3950").
   A `dlg` is 3 bytes, a glow 4, a `wait` 1 (`AICmdSizeTbl`,
   `battle_main.asm:5147`). The block has to move: every read of it is
   long-addressed (`lda f:AIScript,x`: `battle_main.asm:4381, 4405, 4407,
   7805`; `ot6_break.asm:2063, 2084, 2095, 2124, 2166, 2180`) and the
   pointer table holds offsets from the label (`ptr_tbl AIScript`,
   `ai_script.asm:14`), so the `ai_script` segment can load in bank F0
   (`ff6/cfg/ff6-en.cfg:105`, :23) with a larger block.
3. **The lines.** Battle dialogue has 256 slots and 115 of them,
   `$8D`-`$FF`, read "Wait a minute!" (`ff6/src/text/monster_dlg_en.json`;
   `ai_block_free.txt`). A line of fourteen characters or fewer costs no
   text space.
4. **The cancel.** Where a break starts (`Ot6Chip`, `ot6_break.asm:749`;
   `Ot6ClassChip`, :916; the Break spell, `ot6_breakspell.asm:132`), store
   `$ff` in `$3240,y`: the boss's next turn starts its block from the top,
   as after any `end_if`. That restarts a script fuse at its announce.
   For a fuse whose trigger lives in a variable or a timer, a small table
   by species names what the break also clears (a monster switch mask, a
   battle variable, the monster timer). Whether the trigger is cleared is
   open question 1.

The survey expected the HUD to take no part ("Telegraph must be
data-authored", floating-continent-route.md:499-502: the per-frame hook
had no cycles to spare). The lead asked for a sign on the shield line, and
it costs one byte test a frame in a battle with no fuse boss (section 1.3).

### 1.3 What unit A built

`ff6/src/battle/ot6_fuse.asm` (#561); DESIGN.md "Break system" has the
rule in one paragraph.

- **The cancel.** `Ot6FuseTbl` holds one row a fuse: the species, where
  its script resumes while the fuse is lit (or, for a fuse a counter arms,
  the battle switch that is set), and what a break clears. Every take that
  empties a last shield ends in `Ot6HitBroke` (the element and class
  chips, OT6's Break, Filch, Bum Rush, Cleave's strip), and that calls
  `Ot6FuseCancel`: for a lit fuse, `$ff` into `$3240,y` and the row's
  clears. A break while no fuse is lit changes nothing.
- **Earned again.** Each row leaves the script where its own move's last
  commands would: Atma's switch and tally cleared (thirteen hits again),
  the Gold Dragon's switch, turn count and Fight count (five Fights
  again), AtmaWeapon's two switches (its rotation's four turns again),
  Kefka's two battle switches (his HP arms him, so he says the line again
  on his first turn back and Goner needs the turn after it).
- **Hits on a Broken boss wind no fuse.** A counter that only counts was
  already skipped while its monster is Broken; the Gold Dragon's was not,
  because its block speaks a line and a `dlg` made it a story block. A
  fuse's announce is no story now (`Ot6FuseLineTbl`).
- **An announced move always fires.** None of the four vanilla fuses rolls
  between its announce and its move (each move is one attack); `battle_fuse`
  checks every row for it. For telegraphs still to be written there is a
  roll condition, `if_roll <chance in 256>` (AI conditional `$0a`,
  vanilla's unused second "never"). It belongs on the block that arms a
  fuse, a turn before the announce, never on the fuse block: a block's
  conditions are tested again on the turn it resumes.
- **The sign.** While a fuse is lit a yellow **!** stands in the cell
  before the boss's shield emblem, the cell Shadow's dagger and knife use
  (by turns with them, about half a second each, when the boss is also
  Slowed or Stopped). It appears with the announce and goes when the move
  is queued or with the hit that breaks the boss. Screenshots:
  `build/attempts/wt/v051-fuse/shots/`.
- **Room.** The AI script block and its pointer table load in bank `$F1`,
  the block `$6000` bytes (vanilla's `$3950` had under ten free); about
  9,900 are free. `build/attempts/wt/v051-fuse/move/what_moved.txt` shows
  the move byte for byte.
- **The idiom and its worked example.** The fuse block in vanilla's idiom
  is written out at the top of `ot6_fuse.asm`. The CzarDragon's script,
  which no battle deals, carries the example: a clock and a roll arm it on
  an ordinary turn, "CzarDragon draws breath!" (battle dialogue `$8D`, the
  first free slot) announces it on the next, Flare Star follows, and a
  break in between clears the switch and restarts the clock. A new
  telegraph is that block in the boss's script, a label after its `wait`,
  a line in a free slot, and a row in `Ot6FuseTbl`.
- **A release fits the table.** The row's flags have room for "a break
  frees what this body holds", applied at every break, lit or not. The
  release itself is what Discard does (`TargetEffect_44`,
  `battle_main.asm`): four stores on the holder and the member its `$3358`
  names. Not built; block 1.
- **The suites.** `battle_fuse` (the table against the built scripts, the
  block's home, no roll after an announce, the worked example on a staged
  formation), `battle_atmaweapon`, `battle_atma`, `battle_golddrgn`,
  `battle_goner`. Each boss suite plays its battle three times from one
  snapshot: unbroken (the line, the **!**, the move on vanilla's turn),
  broken in the fuse (the cancel, the **!** gone with the hit, no move on
  the turns back, the trigger earned again in full, then the move after
  the second announce), and broken outside it (nothing cancelled, the
  trigger's cells untouched, Fights in the window counting for nothing).
  They are mechanism tests: the gauge is staged for the breaking Fight
  and HP is held.
- **The driver.** The fight driver reads the same lit bit the **!** is
  drawn from and, when the member whose turn it is can take the boss's
  last shields with a Fight, makes its planned attack that Fight
  (`Driver:fusePlan`). It does not yet hold a last shield for an
  announce, or work a full gauge down inside a fuse. On the line played
  on unit A's ROM (the gate at c44f23b2, `build/attempts/wt/v051-fuse/gate-c44f/`)
  no fuse lit in any of the four fights: the legs' logs hold no `[fuse]`
  line, and the party won each before its boss announced (AtmaWeapon 7,610
  ticks, Atma 7,087, the Gold Dragon 3,727, Kefka 14,506; 6,907, 6,611,
  4,019 and 17,138 on the survey's line, whose play upstream differed). So
  the line does not exercise the cancel; the suites do. Whether a party
  that meets the announce breaks the boss in time is each unit's lab
  (turns to break against the fuse's length).

## 2. Hooks at a glance

"Vanilla" in the telegraph column means the announce is already in the
script. Shields are today's; an arrow is a proposal (section 3).

| # | Boss | Hook | Telegraph | Shields |
|---|---|---|---|---|
| 1 | Tentacles x4 | Hostages: a Slowed member is Seized and is out of the fight until its holder is Broken or dead; each body drinks a different element | Entwine (Slow) -> Seize on that body's next turn (vanilla) | 5 each |
| 2 | Dullahan | The hit counter: every blow that lands outside a break winds the frost; eight wind it | "Dullahan's blade rimes over" -> the ice combo, Absolute 0 at its end | 10 |
| 3 | Presenter and its head (the tomb's chest) | The Narshe Whelk grown: the shell is the wrong answer. The same hook on purpose, a callback | a hit on the shell -> Giga Volt (vanilla counter) | 0 / 6 |
| 4 | Phunbaba, the two visits | He ends the fight himself at an HP line. Crossed while Broken, the second visit ends without BabaBreath and nobody is blown out | "Phunbaba fills his lungs" just above the line -> BabaBreath x2 | 4 / 5 |
| 5 | Phunbaba, TERRA's fight | The roster is whoever BabaBreath left, and her Trance is the key | none proposed | 12 |
| 6 | Storm Drgn | Proposed (Octopath): the gauge grows after each break, 10, 12, 14 | "The Storm Dragon swallows the wind" -> Cyclonic | 14 -> 10 growing to 14 |
| 7 | Ice Dragon | Freeze and thaw: N. Cross freezes members, and fire, its weakness, is also the thaw | "The air goes still" -> Absolute 0 | 6 |
| 8 | Tritoch | It answers the command, not the hit: any skill command draws Cold Dust on its user, fire draws Rasp, plain Fight draws nothing, and defence 254 makes Fight a chip and nothing more | "Frost creeps up the cliff" -> Ice 3 | 10 |
| 9 | Umaro | The recruit's audition: he Jumps at the third spell, Tackles at fire, and under 10,240 HP eats a Green Cherry | "Umaro digs out a Green Cherry" -> the cherry | 6 |
| 10 | Pugs x3 (Umaro's cave's chest) | A tug of war: each Pug steps forward every turn and stabs when it arrives; three Fights knock it back; a spell draws Pearl | the steps forward (vanilla) -> Knife | 4 each |
| 11 | Chadarnook | Two bodies in one frame: the demon stands for four of the party's actions or 40 counts; bank on the goddess, spend on him | "The paint runs" -> the swap | 0 / 6 |
| 12 | White Drgn | No weapons and no weakness: in the tower only the Break spell opens it, and every spell cast draws Dispel on the party | none natural | 6 |
| 13 | MagiMaster | Every hit re-rolls his wall and a break freezes it; his death is Ultima | "MagiMaster gathers the last of his magic" -> Ultima (a dying move: open question 4) | 8 |
| 14 | Red Dragon | A clock, not a counter: every 40 counts a fire burst on the party, whatever the party does | "The Red Dragon's scales turn white" -> Flare Star | 6 -> 8 |
| 15 | Doom Gaze | The hunt: he flees on his third turn and keeps his wounds; Broken, he cannot flee | "Doom Gaze turns to flee" -> Escape | 8 |
| 16 | SrBehemoth, twice | The fight turns round: the first beast's death brings its corpse in from behind, undead, with its elements inverted | Hypno Gas (Sleep) -> "4 attacks!!" (vanilla) | 6 + 6 |
| 17 | Hidon | The fuse the party wants: GrandTrain comes only when he stands alone, and STRAGO has to see it | a glow (vanilla) -> GrandTrain | 6 (Hidonites 2) |
| 18 | Dirt Drgn | Fight from the air: Float dodges everything it casts, and it spends turns pulling Float down | 50 Gs (vanilla) -> Quake | 6 -> 8 |
| 19 | Dream Stooges | A trio with jobs: Curley raises the fallen, Larry runs and comes back, and Delta Hit comes only while all three stand | "The three line up" -> Delta Hit | 4 each |
| 20 | Wrexsoul | He hides inside a party member; only felling the host brings him out | "Wrexsoul's shape wavers" -> Zinger | 6 (SoulSavers 2) |
| 21 | Blue Drgn | The thief of buffs: it Slows itself, then Ripplers its statuses for a Hasted member's | its own Slow (vanilla) -> Rippler | 6 -> 8 |
| 22 | KatanaSoul (the castle's chest) | The mirror duelist: steel is answered with steel, magic with thrown blades and coin | "KatanaSoul's power up!" (vanilla) | 6 |
| 23 | Master Pug (the cave's chest) | The spell is the tell: its wall turns every 15 counts and the spell it casts names the weakness it wears | WallChange (vanilla) -> the matching tier-3 spell | 6 |
| 24 | Inferno, Striker, Rough | Proposed (Octopath): the arms guard the engine, whose gauge is shut while an arm stands; the arms regrow on a clock | "Inferno's coils whine" -> Giga Volt | 6 (arms 3) |
| 25 | Atma | The charge the party arms: thirteen blows and he stops to gather light for two turns, then Ultima | "Unknown light surrounded Atma!" (vanilla) -> Ultima. **Built** | 10 -> 12 |
| 26 | Gold Drgn | Fights wind it, spells do not: five Fights and it stores energy for two turns | "Gold Dragon begins to store energy!" (vanilla) -> Bolt 3 on all. **Built** | 6 -> 8 |
| 27 | Skull Drgn | A four-beat bar: three beats of Condemned and fire, then Disaster on the fourth, every time | "The Skull Dragon's jaw unhinges" -> Disaster | 6 -> 8 |
| 28 | Guardian | A boss rush in one body: it runs Ultros's, Dadaluma's, the Air Force's and Atma's programs in turn, each ending in that boss's finisher | "Ran ...'s battle program!" (vanilla) -> Wave Cannon, Flare Star | 10 |
| 29 | Doom | The field closes: each Force Field nulls one more element for both sides, and only the classes stay open | Targetting (vanilla) -> Demon Rage on the marked member | 10 |
| 30 | Goddess | She borrows the party: Love Token makes a member take her hits, Charm turns one | "The sky splits" -> Quasar | 8 -> 10 |
| 31 | Poltrgeist | The executioner: Stop, then Blaster on whoever is Stopped; every hit is answered with Fire 3 | Stop (vanilla) -> Blaster | 8 -> 10 |
| 32 | The final battle, tiers 1-3 | Kill order: each body's death or last stand is an attack (the Face's Quake, the Hit's ten blows, the Sleep's two deaths), and the Girl raises the Sleep | none; open question 4 | 6-8, the Girl 3 |
| 33 | Kefka | The whole roster's fight: the fallen are replaced in the order the player set | "The end comes...beyond chaos." (vanilla) -> Goner. **Built** | 16 |

Not fights: Phunbaba's first record (TERRA's scripted loss) and the Zone
Eater draw no gauge and get no contract (section 5).

### 2.1 Hooks that read the same

Vanilla reuses a few shapes. Each pair below is flagged with what keeps
the two apart, or with a proposal where nothing does.

| shape | who | kept apart by |
|---|---|---|
| a hit counter arms the big move | Dullahan (8), Atma (12), Doom (8, R.Polarity), Goddess (8, Overcast), Poltrgeist (8, Wave Cannon), Hidon (10), KatanaSoul (6 Fights), Gold Drgn (4 Fights), the demon Chadarnook (4); in the WoB Nerapa and Dadaluma | The counter is the hook for three only: Dullahan teaches it, Atma pays two idle turns for it, the Gold Dragon counts Fights alone. The statues keep their counters as vanilla detail and take other hooks (rows 29-31). **Flag: before this table, six bosses read "hit it N times and something lands".** |
| a status marks the victim, the payoff comes next turn | Tentacles (Slow -> Seize), Poltrgeist (Stop -> Blaster), Doom (Targetting -> Demon Rage), the second SrBehemoth (Sleep -> four attacks) | What the payoff is: a hostage, an execution, a single heavy blow, a flurry. **Flag: the Tentacles and the Poltrgeist are the closest pair in the game** (a status, then a move that removes the member). The Tentacles' answer is to break the holder; the Poltrgeist's is to cure Stop or break him. If that is too close, the Poltrgeist's hook becomes its Fire 3 answer to every hit (few, large actions). |
| a body the party must not hit beside one it must | Whelk (WoB), Presenter (the tomb's chest), Chadarnook's goddess | The Presenter is the Whelk on purpose. Chadarnook's hook is the window (four actions), not the mistake. |
| WallChange | Number 024 (WoB), MagiMaster, Master Pug | What turns the wall: 024 its own turns, MagiMaster the party's hits, the Master Pug a clock, with its spell as the tell. |
| parts that return | Number 128's blades (WoB), Inferno's arms, the Hidonites, the SoulSavers | **Flag: Inferno reads as Number 128** (regrowing arms that change the body's script) with the Cranes' absorb triangle on top. The proposal gives it Octopath's guarding adds instead. The Hidonites are the fuse's switch; the SoulSavers are a trap (fighting them never ends). |
| a self-buff phase | Umaro (Green Cherry), KatanaSoul (power up), Doom (aura): the last two set the same three statuses, Image, Reflect, Haste (`ai_script.asm:5801-5803`, :5908-5910) | Umaro's is the telegraph and can be denied; KatanaSoul's is a clock to beat; Doom's is the door to his real hook. |
| Delta Hit while all three stand | the Stooges and Inferno run the same block (`ai_script.asm:5544-5549`, :4754-4758) | **Flag.** It is the Stooges' telegraph; Inferno's is Giga Volt. |
| a reviver | Curley (Life 2), the Girl (Life 2 when alone), the Magic (Life 3) | The Stooges' is a kill order among three equals; the Girl's is one small body beside one large. Close in shape, and far apart in the game. |
| a member leaves the battle | Chupon's Sneeze (WoB), Phunbaba's BabaBreath | Sneeze cannot be stopped; BabaBreath can, by the break (block 4). |
| Condemned | Nerapa (WoB, once, under a clock), Skull Drgn, the Sleep | The Skull Dragon's hook is the bar's fourth beat, not the count. |
| a timed burst | Red Dragon (40), Blue Drgn (40, CleanSweep), Dirt Drgn (20, 50 Gs), Master Pug (15), KatanaSoul (40) | The clock is the Red Dragon's hook alone. **Flag: the Red and Blue Dragons both fire a party-wide element every 40 counts**; the Blue Dragon's hook is Rippler. |
| a low-HP second rotation | Storm, Red and Blue Drgn, SrBehemoth, the demon, Atma, Goddess, Poltrgeist, Kefka | Every boss has one; it is no one's hook. The Storm Dragon is the dragon vanilla gave nothing else, hence the proposal. |

**The eight dragons**, side by side: a gauge that grows (Storm), freeze and
thaw (Ice), Break-only under Dispel (White), a clock (Red), Float (Dirt),
stolen buffs (Blue), a charge wound by Fights (Gold), a four-beat bar
(Skull). Seven come from the vanilla scripts; the Storm Dragon's is the one
borrowed from Octopath.

## 3. The curve

bosses-wob.md: "No single WoB gauge exceeds 11; 12 and above is reserved
for the WoR" (:130-131). Today's WoR rows, in the line's order. "First
break" is the tick at which the line's one fight first showed 0 shields on
a living body, with its HP then; "never" means the body died or fled
unbroken.

| Boss | L / HP | Shields today | On the line: fight length, first break | Proposed |
|---|---|---|---|---|
| Tentacles x4 | 31-34 / 4,000-7,000 | 5 each | 7,060 ticks; never (lowest 3, 3, 1, 1) | 5 each |
| Whelk head (chest) | 31 / 9,845 | 6 (shell 0) | 6,773; never (lowest 1) | 6 |
| Dullahan | 37 / 23,450 | 10 | 6,622; 4,386 at 12,563 HP | 10 |
| Phunbaba, first visit | 31 / 28,000 | 4 | 4,399; 1,460 | 4 |
| Phunbaba, second visit | 31 / 26,000 | 5 | 2,922; 2,439 | 5 |
| Phunbaba, TERRA's | 31 / 26,000 | **12** | 6,779; 2,858 | 12 |
| Storm Drgn | 74 / 42,000 | **14** | 14,383; 8,027 at 36,202 HP | 10, 12, 14 |
| Ice Dragon | 74 / 24,400 | 6 | 8,216; 4,577 | 6 |
| Tritoch | 62 / 30,000 | 10 | 7,804; 4,905 | 10 |
| Umaro | 33 / 17,200 | 6 | 6,151; 3,533 | 6 |
| Pugs x3 (chest) | 99 / 14,001 | 4 each | 8,065; 1,713 | 4 each |
| Chadarnook (the demon) | 41 / 30,000 | 6 (goddess 0) | 12,576; 10,618 at 4,606 HP | 6 |
| White Drgn | 71 / 18,500 | 6 | 21,014; never (lowest 3) | 6 |
| MagiMaster | 68 / 50,000 | 8 | 31,262; never (lowest 1) | 8 |
| Red Dragon | 67 / 30,000 | 6 | 4,836; never (lowest 1) | 8 |
| Doom Gaze | 68 / 55,555 | 8 | three meetings; 3,162 in the first | 8 |
| SrBehemoth, then its corpse | 43, 49 / 19,000 each | 6, 6 | 6,737; 1,720 and 5,008 | 6, 6 |
| Hidon | 43 / 25,000 | 6 (Hidonites 2) | 14,937; 5,560 | 6 |
| Dirt Drgn | 53 / 28,500 | 6 | 8,339; never (lowest 2) | 8 |
| Curley, Larry, Moe | 47 / 15,000, 10,000, 12,500 | 4 each | 11,616; 534 | 4 each |
| Wrexsoul | 53 / 23,066 | 6 (SoulSavers 2) | 11,162; 9,302 at 3,535 HP | 6 |
| Blue Drgn | 65 / 26,900 | 6 | 3,429; 1,760 | 8 |
| KatanaSoul (chest) | 61 / 37,620 | 6 | 4,037; 2,009 | 6 |
| Master Pug (chest) | 73 / 22,000 | 6 | 3,159; 1,285 | 6 |
| Inferno (Striker, Rough) | 67 / 30,800 | 6 (3, 3) | 8,579; 6,145 | 6 (3, 3) |
| Atma | 67 / 55,000 | 10 | 6,611; 3,183 | 12 |
| Gold Drgn | 62 / 32,400 | 6 | 4,019; 1,934 | 8 |
| Skull Drgn | 62 / 32,800 | 6 | 5,420; 3,847 | 8 |
| Guardian | 67 / 60,000 | 10 | 7,496; 4,252 | 10 |
| Doom | 73 / 63,000 | 10 | 10,754; 5,452 | 10 |
| Goddess | 68 / 44,000 | 8 | 6,242; 4,635 | 10 |
| Poltrgeist | 67 / 58,000 | 8 | 18,367; 6,922 | 10 |
| Short Arm, Long Arm, Face | 73-74 / 27,000-33,000 | 6, 6, 8 | 11,466; the Long Arm at 9,930; the Face never chipped | as today |
| Hit, Tiger, Tools, Magic | 70-73 / 24,000-41,000 | 6, 6, 6, 8 | 32,045; six breaks | as today |
| Girl, Sleep | 58, 71 / 9,999, 40,000 | 3, 8 | 22,948; 3,386 and 10,900 | as today |
| Kefka | 71 / 62,000 | **16** | 17,138; 9,237 at 37,134 HP | 16 |

(Rows: `build/attempts/wt/v051-bosses-wor/rows.txt`, read from
`ot6_hud.asm` and `monster_prop.dat` by `rows.py`. Play: `raw_lines.md`.)

### 3.1 The proposed bands

By the body's role in its fight, not its level:

| band | shields | who |
|---|---|---|
| a part that returns, or a small body beside the boss | 2-3 | Hidonites, SoulSavers, Striker, Rough, the Girl |
| one of several equal bodies | 4-5 | Tentacles, Stooges, Pugs |
| a miniboss, a chest's guard, a fight a script clock ends | 4-6 | Phunbaba's two visits, the Whelk head, Umaro, the demon, both SrBehemoths, Hidon, Wrexsoul, KatanaSoul, Master Pug, Inferno |
| a boss | 8 | Doom Gaze, MagiMaster, the dragons, the final battle's large bodies |
| an arc's capstone, a tower guard, a statue | 10 | Dullahan, Tritoch, Guardian, Doom, Goddess, Poltrgeist |
| the reserved tier | 12 and up | Phunbaba 4 (12), Atma (12), the Storm Drgn (to 14), Kefka (16) |

### 3.2 Rows off the curve

1. **The dragons are 14, 6, 6, 6, 6, 6, 6, 6.** Six is the number the
   generated fallback gives any body of level 32 or more
   (`ot6_break.asm:103-111`: "shields = 2 + level / 8 ... capped at 6").
   The Red Dragon's row kept it ("the floor had already given it 6
   shields", route-wor-locke.md section 4), as did the tower's two ("the
   generated floor stood for each: six shields",
   route-wor-kefka-tower.md section 3). Only the Ice Dragon's 6 was
   chosen by measurement (ten held the break off until Absolute 0 wore
   the party down: route-wor-narshe.md 11.4). On the line the late
   dragons are the shortest boss fights there are (Blue 3,429 ticks,
   Gold 4,019, Red 4,836); route-wor-kefka-tower.md section 6 already
   notes the Gold Dragon "may be too easy for an eighth dragon".
   Proposed: 8 for Red,
   Dirt, Blue, Gold and Skull; the Ice Dragon stays at its measured 6; the
   White Dragon stays at 6 because one spell is its only key. Each change
   is a lab, not an edit.
2. **Atma has fewer shields (10) than the AtmaWeapon it rematches (11).**
   Its row comment calls it "the atmaweapon's row, the rematch"
   (`ot6_hud.asm:3455-3458`). Proposed 12.
3. **The statues are 10, 8, 8**, and the two at 8 equal MagiMaster and
   Doom Gaze, bosses a party meets twenty levels earlier. Proposed 10 each.
   Twelve would put the Warring Triad in the reserved tier; the Poltrgeist
   is already the tower's longest fight (18,367 ticks on the line; a coin
   flip before the bench was levelled, route-wor-kefka-tower.md section 6),
   and one member of its party holds its class key (block 31), so it is
   the row least able to take more.
4. **Phunbaba's last record (12) outranks every Kefka's Tower boss** at
   level 31. It is TERRA's return and she breaks it fast (2,858 ticks, six
   shields in one board step, `wor_terra.log:5415`), so it sits in the
   reserved tier as a set-piece; flagged, no change proposed.
5. **The Storm Dragon's 14** is the game's second gauge, on a dragon the
   line meets at level 35-37. As a flat count it is off any dragon
   ladder; as the growing gauge of row 6 it is that dragon's hook.
6. **The Face's 8 was never chipped on the line** (8 at the open, 8 at
   its death, `raw_lines.md` "final tier 1"): the front four at the plate
   are two blades and two rods, and the rods' hits went elsewhere. Its
   keys are bludgeon, special and fire (`ot6_hud.asm:3480-3482`).
7. **The White Dragon's row is one key** (special; `ot6_hud.asm:3006-3009`)
   with no vanilla weakness. In its own fight weapons are off and only the
   Break spell chips it: 21,014 ticks, never broken, lowest 3
   (`wor_tower.log:29339-34519`). The Veldt deals the same formation to a
   party of three whose sixteen Fights never moved the gauge
   (`wor_veldt.log:1125-3469`, shields 6 throughout).

---

## 4. Boss by boss

Each block: what is **built**, the vanilla **script**'s wind-up, the
**hook**, the proposed **telegraph**, the **shields** against the curve,
the **break story** for the party the line brings, and how the fight plays
**on the line**. Parties and levels are read from each fight's outcome line
(`build/attempts/wt/v051-bosses-wor/party.txt`). No block's AI is changed
today; that is said once, in section 1.

## The Solitary Island to the Falcon

### 1. Tentacles — Figaro Castle's engine room

Party: CELES, SABIN, EDGAR (who joins on the spot), level 31
(`wor_edgar.log:24322`, :24451). Formation 454, event group 84.

**Built.** Four rows, 5 shields each, a different class pair on each
(`ot6_hud.asm:2700-2714`). Vanilla elements: `$11B` weak ice and water,
absorbs fire; `$13C` weak fire, absorbs ice and water; `$13D` and `$13E`
no weakness, absorbing bolt and earth with water. route-wor-edgar.md 8.5
(:666-692) wrote the block "in bosses-wob's style" and named Entwine as
the wind-up; nothing was built for it.

**Script** (`ai_script.asm:5384-5426`; the other three bodies are the same
shape). Seize comes before the rotation, on any Slowed member, and Entwine
is one pick in the rotation:

```
5389:         if_monster_switch_clr 7
5390:         if_status_set CHAR_SLOT_1, SLOW
5391:                 attack SEIZE
5392:                 end_if
...
5409:                 reset_monster_timer
5410:                 attack ENTWINE, ENTWINE, SPECIAL
```

A held member is released by Discard after 30 counts of the holder's
timer (:5385-5388) or by its death (:5419-5422).

**Hook.** Hostages. A Slowed member is Seized, cannot act or be healed,
and feeds its holder until the holder is Broken or dead. No other boss
takes a member out of the party's hands and gives them back.

**Telegraph.** Vanilla's, unchanged: Entwine Slows, and that body Seizes
on its next turn. The Slow is the announce; no line is needed. Under the
contract a break costs the body the turn it would Seize on, and the ×2
window is long enough to kill a 4,000-7,000 HP body. **A break on a
holder releases its captive** (the owner, 2026-11-23: "definitely breaking
a tentacle should free a party member"; a contract rule now, to be built
with this block, unit B), the release Discard performs
(`TargetEffect_44`: the holder's switch 7 and `$3358`, the member's
`$3359` and its bit in `$3403`). Without it a Broken holder cannot Discard
either, so the member stays held for the whole break (read from the turn
rule; not measured). Unit A's table has room for the row (section 1.3). Stays verbatim: Seize, the drain, Discard's 30 counts, the
counters, the absorbs, 0 XP.

**Shields.** 5 each, 20 across four gauges: the WoR's opening multi-body
fight, on the band.

**Break story.** SABIN (claws, fists) and EDGAR (the Break Blade, the
AutoCrossbow's pierce on all four) hold a class key on every body; CELES
(slash) on three; `$13D` answers only fists and the crossbow
(route-wor-edgar.md 8.5). Elements are a trap: each body drinks one of the
party's three.

**On the line.** Won in 7,060 ticks with no death, and **no body was
Broken**: the gauges' lowest readings were 3, 3, 1, 1
(`wor_edgar.log:22535-24322`; `fights_edgar.txt`). The line banks three
points and spends them on area attacks (the crossbow and Air Blade at ×8),
which chip each body once an action and kill before five. Over draws:
0 of 90 distinct fights lost, "the Seize lottery still decides the losses"
(route-wor-edgar.md 12.7). The break is not part of the winning line
today; the hostage rule would make it one.

### 2. Dullahan — Darill's Tomb

Party: CELES 33, SABIN, EDGAR, SETZER 32 (`wor_falcon.log:5098`, :5171).
Formation 455, event group 85. A loss is a game over.

**Built.** 10 shields; pierce, bludgeon, special (`ot6_hud.asm:2775-2780`);
weak fire, absorbs ice (vanilla). The count is owner-approved
(route-wor-falcon.md section 14, :2472-2475). The telegraph is "proposed"
and open: Absolute 0 (:786-788, :2483-2488).

**Script** (`ai_script.asm:5431-5475`). The wind-up is a counter. Each
action that hits him adds one (:5472-5475) and at eight the next four
turns are the ice combo:

```
5442:         if_battle_var_greater 1, 8
5443:                 attack N_CROSS, SPECIAL, NOTHING
5444:                 wait
5445:                 attack ICE_2, SPECIAL, NOTHING
5446:                 wait
5447:                 attack PEARL_LORE, NOTHING, ABSOLUTE0
5448:                 wait
5449:                 attack ICE_2, ABSOLUTE0, NOTHING
5450:                 set_battle_var 1, 0
```

Absolute 0 is one pick in three on the third turn and on the fourth.
Around it: L? Pearl once at the open (:5432-5435), Cure 2 on himself under
10,240 HP once a rotation (:5436-5441), and a rotation of Ice 3, Ice 2
and Pearl.

**Hook.** The hit counter. The party's own blows wind his big move, and
blows that land while he is Broken do not count: his counter block holds
no story command, so it is skipped whole (section 1.1). Hit him freely in
the window, carefully outside it. He is the first boss the WoR player
meets after the Falcon's party forms, and the place to teach it.

**Telegraph.** "Dullahan's blade rimes over" at the head of the combo
block, on the turn the counter trips; the combo then runs as vanilla
wrote it, Absolute 0 at its end. That is a fuse of two turns, one more
than the contract's, because the move sits two turns into vanilla's own
block. Build: one `dlg` and a `short_glow` before :5443; the cancel store
restarts the block, and the species table zeroes battle variable 1 on a
break so the eight must be earned again (open question 1). To announce a
move that then comes one time in three would teach nothing, so the
proposal makes Absolute 0 certain on the third turn (open question 2).
Stays verbatim: L? Pearl and its gil digit, Cure 2, the answer to Reflect,
the rotation, the counter's Battle.

The alternative, if the owner prefers a one-turn fuse: his Cure 2. "Light
gathers in the wound", a `wait`, then the cure; a break denies the heal.

**Shields.** 10, the capstone band.

**Break story.** EDGAR pierces and SETZER holds pierce (Darts) or special
(Cards, Dice); SABIN's Blitz is the blow and his claws carry fire; CELES
holds fire by Maduin and stands on Runic, which five of his spells feed
(route-wor-falcon.md section 5). Every member has a key.

**On the line.** Won in 6,622 ticks, no death; broken once, at tick 4,386
with 12,563 of 23,450 HP left (`wor_falcon.log:4534`, :5098). Over draws:
80 of 80 with the route's policy, and "the hit-counter combo barely fires
(Absolute 0: 0 in `dull/`, 2 in `dullctl/`): the break and the kill come
first" (route-wor-falcon.md 13.6). A telegraph on a move that arrives
twice in 144 fights is the open point; the counter at eight, not nine,
and a party that plays to the hook rather than racing, would see it more.

### 3. The Presenter — the chest beside the tomb's save point

Party: the same four (`wor_falcon.log:2095`). Formation 433, event group
116.

**Built.** The shell `$101` has no gauge; the head `$135` has 6, pierce,
with vanilla fire (`ot6_hud.asm:2781-2788`): "the narshe whelk's rows
grown for the WoR".

**Script** (`ai_script.asm:4329-4345`, :6419-6444). The shell answers
every hit with Giga Volt (:4343-4345). The head hides for 20 counts after
two hits (:6425-6430) and the shell casts Magnitude 8 while it is hidden
(:4330-4332).

**Hook.** The Narshe Whelk, grown: the same lesson on purpose, for a
player who remembers the first boss. Flagged as a deliberate repeat.

**Telegraph.** None proposed; the counter is the lesson.

**On the line.** Won in 6,773 ticks by **killing the shell**
(`wor_falcon.log:2095`: "killed s0:$101"); the head's gauge fell to 1 and
never broke. The wrong answer wins at these levels, three Giga Volts
taken on the way (`fights_states.txt`: "101 cmd0C atkB9: 3"). A tuning
note, not a defect (guidelines: a win is a win).

### 4. Phunbaba, the two visits — Mobliz

Party: CELES 33, SABIN, EDGAR, SETZER 32 (`wor_terra.log:2869`, :4703).
Battles 129 and 130, records `$16B` and `$16C`.

**Built.** 4 and 5 shields, bludgeon and special
(`ot6_hud.asm:2800-2810`); weak poison, absorbs bolt. Six and eight "never
broke in 18 fights" each (route-wor-terra.md section 6). The first record
`$16A`, TERRA alone against an invincible body, has no gauge (:2796-2799).

**Script.** Both fights end at an HP line in the counter
(`ai_script.asm:7819-7823`, :7842-7849):

```
7842:         if_hit
7843:         if_hp SELF, 15360
7844:                 set_target RAND_CHAR
7845:                 attack BABABREATH
7846:                 set_target RAND_CHAR
7847:                 attack BABABREATH
7848:                 end_battle
```

**Hook.** He ends the fight himself, and the break decides how.
`end_battle` is a story command, so the block runs while he is Broken
with its attacks removed: "Phunbaba's `if_hit / if_hp<15360` block ends
the battle without its two BabaBreaths when he is Broken"
(bosses-wob.md:57-59). **This is the one move in the World of Ruin that a
break cancels today.**

**Telegraph.** "Phunbaba fills his lungs", once, on his turn when his HP
is within about 2,500 of the line; the fuse is that band of HP, not a
turn. Build: a block at the head of the turn script (`if_hp` and a
monster switch), nothing else. Stays verbatim: the rotation, the line at
15,360, BabaBreath, the first visit's Escape under 20,480.

**Shields.** 4 and 5, set by measurement.

**Break story.** SABIN's Blitz and SETZER's cards are the class keys,
EDGAR's Bio Blaster the vanilla poison; CELES holds none and stands on
Runic against Bolt 2 and Bolt 3 (route-wor-terra.md section 6).

**On the line.** The second visit crossed the line Broken: at f+2700 he
stood at 14,196 HP with 0 shields (`wor_terra.log:4639`), his next action
was the battle's end with no BabaBreath before it (`:4683`: "cmd $30 atk
$02"), and the last fight opened with four seated (`:4751`: "e0 748/1798,
e1 1394/1923, e2 1692/1692, e3 1185/1698") where vanilla leaves TERRA two
companions. First visit: 4,399 ticks, broken at 1,460; second: 2,922
ticks, broken at 2,439; no deaths.

### 5. Phunbaba, TERRA's fight

Party: CELES, SABIN, TERRA 32 (morphed), SETZER (`wor_terra.log:6422`,
:6537). Battle 131, record `$16D`.

**Built.** 12 shields; slash, bludgeon, special
(`ot6_hud.asm:2811-2814`).

**Script** (`ai_script.asm:7855-7868`): the same rotation; a Bolt 2 in
answer to every hit; no line, no counter, no clock.

**Hook.** The roster is whoever BabaBreath left, and TERRA arrives in
Trance. The fight before decides this one's party.

**Telegraph.** None proposed. Vanilla offers no wind-up here, and the
fight's meaning is the one before it.

**Shields.** 12: in the reserved tier at level 31 (section 3.2, 4).

**On the line.** Won in 6,779 ticks, no death; six shields fell in one
board step and he broke at tick 2,858 with 19,492 of 26,000 HP
(`wor_terra.log:5415`).

## The open world

### 6. Storm Drgn — Mt. Zozo

Party: CYAN 35, TERRA 37, SABIN, CELES 36 (`wor_storm.log:5153`, :5185).
Event group 133.

**Built.** 14 shields; slash, pierce (`ot6_hud.asm:2860-2864`); weak
bolt, absorbs wind. "Cyan's quadra slam chips four a turn".

**Script** (`ai_script.asm:6966-6984`). No counter, no timer, no line.
Its one change is a second rotation under 15,360 HP:

```
6967:         if_hp SELF, 15360
6968:                 set_target NOTHING
6969:                 attack BATTLE, BATTLE, AERO
6970:                 wait
6971:                 set_target NOTHING
6972:                 attack BATTLE, SPECIAL, CYCLONIC
```

**Hook.** Vanilla gives this dragon nothing of its own, so the proposal
borrows from Octopath: **the gauge grows.** It opens at 10 and returns
from each break with two more, to 14, today's number. The first break is
the cheap one. Build: where `Ot6Tick` refills the gauge
(`ot6_break.asm:2379-2380`), a species entry adds to `OT6_SHIELD_MAX` up
to a cap.

**Telegraph.** "The Storm Dragon swallows the wind" on the first turn
under 15,360, riding on that turn's attack; Cyclonic on the next, certain
(vanilla: one pick in three). Cyclonic cuts every member to a fraction of
their HP (`attacks.txt`: "CYCLONIC ... st=-/nearfatal"). Stays verbatim:
Wind Slash, Rage, the counter's Battle.

**Shields.** 14 today (section 3.2, 5).

**Break story.** Four blades: every member holds slash; bolt is the
ThunderBlade's; CYAN's Tempest heals it (route-wor-cyan.md section 6).

**On the line.** Won in 14,383 ticks, no death; broken once, at tick
8,027 with 36,202 of 42,000 HP (`wor_storm.log:3570`, :5153): more than
half the fight passed before the first break. Over draws at level 38-40:
30 of 30, party deaths in 13; at the arrival level 3 of 14 lost
(route-wor-cyan.md 5.1-5.4).

### 7. Ice Dragon — the Narshe cliffs

Party: CYAN, TERRA, CELES, MOG (`wor_narshe.log:22250`). Event group 132;
it walks the cliff and fights on touch.

**Built.** 6 shields; pierce, bludgeon (`ot6_hud.asm:2926-2933`); weak
fire, absorbs ice. Six "not the plan's ten".

**Script** (`ai_script.asm:6922-6940`): a three-turn rotation with no
condition, a Battle in answer to every hit, and Surge at its death.

```
6923:         attack BATTLE, N_CROSS, N_CROSS
6924:         wait
6925:         attack BATTLE, ABSOLUTE0, ABSOLUTE0
6926:         wait
6927:         attack BATTLE, SURGE, ABSOLUTE0
```

**Hook.** Freeze and thaw. N. Cross freezes members (`attacks.txt`:
"N_CROSS ... st=-/-/-/frozen"), a fire hit thaws a frozen member
(vanilla's rule; not measured here), and fire is the dragon's weakness:
the element that breaks it is the one the party has to spend on itself.

**Telegraph.** "The air goes still" on the first beat, riding on that
turn's N. Cross or Battle; Absolute 0 on the second, certain (vanilla:
two picks in three). The rotation is three beats, so the fuse returns
every rotation, as AtmaWeapon's does. Build: one `dlg` at :6923; the
cancel store restarts the bar at its first beat.

**Shields.** 6 by measurement (route-wor-narshe.md 11.4).

**Break story.** MOG's spear is the only class key; fire is everyone's,
and since v0.37 CELES swings two Flame Sabres at it (13.2).

**On the line.** Won in 8,216 ticks; broken at 4,577 with 18,589 of
24,400 HP; one death, CYAN to Surge from 605 HP
(`wor_narshe.log:21060`, :21349, :22250). Over draws: a member died in 6
of 112 fights with the blades (13.4).

### 8. Tritoch — the cliff's top

Party: CYAN 38, TERRA 39, CELES 38, MOG 36 (`wor_tritoch.log:3808`,
:3852). Battle 119, record `$144`; the two WoB records keep no gauge.

**Built.** 10 shields; slash, pierce (`ot6_hud.asm:2919-2925`); weak
fire, absorbs ice, nulls six elements; defence 254.

**Script** (`ai_script.asm:6794-6819`): a rotation of Rasp, Ice 3 and Cold
Dust, and counters keyed on the command used:

```
6805:         if_element FIRE
6806:                 attack NOTHING, NOTHING, RASP
6807:                 end_if
6808:         if_cmd BUSHIDO, TOOLS
6809:                 set_target PREV_ATTACKER
6810:                 attack NOTHING, NOTHING, COLD_DUST
```

and the same for Blitz, Lore, Sketch and Rage.

**Hook.** It answers the command, not the hit. A skill command draws Cold
Dust (Frozen) on its user, fire draws Rasp, plain Fight draws nothing,
and defence 254 makes Fight worth nothing but its chip. Fight is for the
gauge, fire is for the damage: the break system's two halves, split
across two verbs.

**Telegraph.** "Frost creeps up the cliff" on the first beat; Ice 3 on
the second, certain (vanilla: two in three). CELES's Runic eats it, so
the fight has two answers, as TunnelArmor's has. Stays verbatim: the
counters, Rasp.

**Shields.** 10, the capstone band.

**Break story.** All four hold a class key; MOG "lands half of Tritoch's
breaks in the arc he joins for" (route-wor-narshe.md 11.4).

**On the line.** Won in 7,804 ticks, no death; broken at 4,905 with
13,714 of 30,000 HP (`wor_tritoch.log:3177`). "Tritoch and Umaro never
threatened the party in 23 fights" (11.4): a fight that needs its hook.

### 9. Umaro — his cave

Party: the same four, 39/39/39/37 (`wor_tritoch.log:9382`). Battle 117,
record `$110` (`$10F` is a duplicate no battle deals,
`ot6_hud.asm:3602-3603`).

**Built.** 6 shields; slash, pierce (`ot6_hud.asm:2915-2918`); weak fire
and poison, absorbs ice. "break him before his green cherry".

**Script** (`ai_script.asm:4914-4976`). The wind-up is an HP line with
vanilla's own line on it:

```
4917:         if_hp SELF, 10240
4918:                 set_target SELF
4919:                 use_item GREEN_CHERRY
4920:                 flash_red MONSTER_1
4921:                 dlg $49
4927:                 set_status PROTECT
4928:                 set_status SHELL
4929:                 set_status HASTE
4930:                 set_status REGEN
```

Each Magic command counts (:4968-4970) and at three he Jumps
(:4933-4936); fire draws Tackle or Blizzard (:4971-4973).

**Hook.** The recruit's audition. He reads the party's verbs (a Jump for
spells, a Tackle for fire), and at 10,240 HP he doubles down. Beating him
is how he joins.

**Telegraph.** "Umaro digs out a Green Cherry" with the red flash, a
`wait`, then the cherry and vanilla's "Power 100 times up!". A break in
the fuse and he drops it: the species table sets battle switch 0, the
block's own once-flag, so it is gone for the fight (open question 1).
Eaten, its Haste shortens his later breaks (bosses-wob.md:77-80). Stays
verbatim: the Jump, the counters, the cherry's four statuses.

**Shields.** 6, a guard's count for the fight that ends in a recruit.

**Break story.** Every member holds slash or pierce, and three cast fire.

**On the line.** Won in 6,151 ticks, no death; broken at 3,533 with
12,002 of 17,200 HP, above the cherry's line
(`wor_tritoch.log:8798`, :9382).

### 10. Pugs — the chest in Umaro's cave

Party: CYAN, TERRA, CELES, MOG (`wor_umaro_box.log:2510`), on a branch leg
nothing boots (wor-coverage.md section 12). Formation 235, three Pugs,
level 99.

**Built.** 4 shields each; slash, special (`ot6_hud.asm:2912-2914`).

**Script** (`ai_script.asm:4217-4292`). Each Pug steps forward on its
turn and strikes with Knife when it has stepped eight times; three Fights
on a Pug knock it back a step; any Magic draws Pearl on the caster
(:4289-4291).

```
4226:         if_self_in_slot MONSTER_3
4227:                 move_forward_fast MONSTER_3
4228:                 attack BATTLE
4229:                 add_monster_var 1
```

**Hook.** A tug of war over ground: the Pugs' position on the screen is
the fuse, and Fights push it back.

**Telegraph.** Vanilla's, unchanged: the walk forward is the announce.

**On the line.** Won in 8,065 ticks, no death, four breaks, the first at
1,713 (`wor_umaro_box.log:830`, :2510).

### 11. Chadarnook — Owzer's house

Party: CYAN 40, TERRA 40, CELES 39, SABIN 37 (`wor_relm.log:3982`,
:4105). Formation 456: the goddess `$11E` and, hidden behind her, the
demon `$148`.

**Built.** The goddess has no gauge, the demon 6 with slash and pierce
(`ot6_hud.asm:2963-2969`); the demon is weak to fire and holy and absorbs
bolt. So this is not a no-gauge fight: only its wrong body is. Why the
goddess has none: hitting her draws Phantasm and she returns from her own
death (`ai_script.asm:5531-5538`); "hitting her is the fight's mistake".
That ruling is kept.

**Script.** The demon leaves on a clock or on the party's hits, and how
he left sets how long she stays (`ai_script.asm:6874-6879`, :6909-6917,
:5513-5528):

```
6874:         if_monster_timer 40
6875:                 reset_monster_timer
6876:                 set_battle_var 3, 1
6877:                 show_monsters MONSTER_1, CHADARNOOK
6878:                 kill_monsters MONSTER_2, CHADARNOOK
...
6909:         if_hit
6910:                 attack NOTHING, NOTHING, BOLT_2
6911:                 add_battle_var 0, 1
6912:                 if_battle_var_greater 0, 4
```

Gone on his clock (variable 3 at 1) she takes three turns before he
returns; driven off by four hits (variable 3 at 0) she takes one.

**Hook.** Two bodies in one frame, and a window the party sets. The demon
stands for four of the party's actions or 40 counts. Four small hits
waste the window; four boosted ones are the fight. It is the banking
exam: earn on the goddess's turns without touching her, spend on his.

**Telegraph.** "The paint runs" on the turn before he leaves by the
clock; the swap is the move. A break in the fuse holds him on the canvas
for the window, where every hit doubles. His hit counter still counts
while he is Broken, because its block holds `show_monsters`, a story
command (section 1.1), so the fourth hit still sends him off;
route-wor-thamasa.md 5.2 left that as a lab question. Proposed: the
species table zeroes variable 0 at the break, so a break buys four more
actions. Stays verbatim: Phantasm, Doom Kiss, Charm, the demon's Bolt 2
counter, Flash Rain under 15,360.

**Shields.** 6 on the demon.

**Break story.** Four blades; fire from TERRA and the Ifrit wearer, Pearl
from TERRA; CELES on Runic for Bolt 2 and 3. The demon absorbs bolt.

**On the line.** Won in 12,576 ticks, no death, and broken once, late: at
tick 10,618 with 4,606 of 30,000 HP (`wor_relm.log:3478`). Over draws it
is "attrition ... Doom Kiss, Charm and the demon's Bolt 3 over 8,000 to
67,000 ticks, about two deaths a fight", 89 of 91 won
(route-wor-thamasa.md 12.5). The longest spread of any WoR boss, and the
fight with the most to gain from a designed window.

### 12. White Drgn — the Fanatics' Tower

Party: TERRA 49, CELES 48, RELM, STRAGO 46 (`wor_tower.log:34519`,
:34766). Formation 481, event group 139; magic only (battle switch `$38`).

**Built.** 6 shields; special (`ot6_hud.asm:3006-3009`); no weakness,
absorbs holy. "no weakness and no reflect: ot6's break is its key".

**Script** (`ai_script.asm:3253-3266`): Pearl twice a turn, and any Magic
draws Dispel on the whole party.

```
3263:         if_cmd MAGIC
3264:                 set_target ALL_CHARS
3265:                 attack DISPEL, DISPEL, NOTHING
```

**Hook.** No weapons and no weakness. In a tower where only spells work,
every spell is answered with Dispel, and the one thing that opens the
gauge is the Break spell. It is the dragon that asks for one spell by
name.

**Telegraph.** None is natural: its turn is the same every turn. Leave it
without one; its fight is its counter.

**Shields.** 6 (section 3.2, 7).

**Break story.** TERRA knows Break and the Shoat wearer has a second; a
boosted Break takes four shields (route-wor-thamasa.md 5.3, 5.4). No other key
exists inside the tower.

**On the line.** Won in 21,014 ticks, no death, **never broken**: the
gauge's lowest reading was 3 (`wor_tower.log:29339-34519`; 24 Magic
actions). It is the longest dragon fight on the line by a factor of two.
An earlier lab broke it "twice a fight by TERRA's Break"
(route-wor-thamasa.md 11.4); the line as played does not.

### 13. MagiMaster — the tower's top

Party: the same four (`wor_tower.log:57199`, :57455). Formation 354,
event group 145; magic only.

**Built.** 8 shields; special (`ot6_hud.asm:3010-3012`); no weakness of
his own: "his wall's one weakness (wallchange), or ot6's break".

**Script** (`ai_script.asm:3551-3578`). Two things, both in the counter:

```
3571:         if_self_dead
3572:                 set_target NOTHING
3573:                 attack ULTIMA
3574:                 end_if
3575:         if_hit
3576:                 set_target SELF
3577:                 attack WALLCHANGE
```

**Hook.** Every hit re-rolls his wall and a break freezes it: "Broken he
takes no turns and draws no counters, so his wall stands still for the
window" (route-wor-thamasa.md 12.3). One hit a wall outside the window,
every hit on a known wall inside it. And his death is Ultima.

**Telegraph.** His big move is the dying one, and a dying counter runs in
full whatever his state (bosses-wob.md:55-57), so a break cannot cancel
it today. Two proposals, the second the owner's to choose (open question
4): the announce, "MagiMaster gathers the last of his magic", once, on
his turn under 6,400 HP, so the party has a turn to raise Shell and Life
3; and the rule that **a boss killed while Broken loses its dying
attack**, which would make "kill him inside the window" the answer.
Stays verbatim: WallChange on every hit, the spell loop, Ultima's power.

**Shields.** 8, the boss band.

**Break story.** Inside the tower no class applies. The keys are the
element his wall shows (Maduin's fire, ice and bolt answer three walls in
eight) and the Break spell, TERRA's and Shoat's (12.3).

**On the line.** Won in 31,262 ticks, the longest single-body fight of
the line, and **never broken** (lowest 1). 201 of its 225 decisions were
a wait for the wall (`fights_states.txt`: "did={'defer': 201, 'magic':
18, 'item': 6}"). His dying Ultima took all four from full HP at once,
and three of them wore Life 3: the "shell=0 life3=0" this survey first
quoted (`wor_tower.log:56900`) was read after the Ultima had spent it; the
reading before it has `life3=1` on e0-e2 and 0 on STRAGO (e3)
(`[end] f250800`, the 2026-11-22 log kept as
`build/attempts/wt/v051-wipe-win/wor_tower.2026-11-22.log.gz`, line
56756). The engine raised the three at an eighth of their HP
("partyhp=448,433,452,0") and the battle was won: no wipe, no retry, and
the driver's `[wipe]` line was wrong, not the verdict (#564; the driver now
says `[allfell]` and `[raised]` there). The labs' median was 60,251 ticks
with the break line and a second Break (12.3).

### 14. Red Dragon — the Phoenix Cave

Party: CELES, RELM, MOG, UMARO, the cave's second party
(`wor_locke.log:2666`). Event group 138.

**Built.** 6 shields; pierce (`ot6_hud.asm:3049-3052`); weak ice and
water, absorbs fire. "The floor had already given it 6 shields and
pierce, so the row changes no number of its fight"
(route-wor-locke.md section 4).

**Script** (`ai_script.asm:7223-7280`). A clock, ahead of everything else
in the script:

```
7224:         if_monster_timer 40
7225:                 reset_monster_timer
7226:                 attack S_CROSS, L4_FLARE, FLARE_STAR
7227:                 end_if
```

It strips Reflect with Eraser and says so (:7228-7259, "Remove Rflect"),
and under 10,240 HP it turns to Flare (:7260-7267).

**Hook.** A clock, not a counter. Every 40 counts, about 21 seconds, a
fire burst lands on the party whatever the party has done. The fight is
measured in bursts taken.

**Telegraph.** "The Red Dragon's scales turn white" on its turn when the
clock passes 30; the burst at 40, as now. Flare Star for the line's sake;
the pick stays vanilla's one in three unless question 2 says otherwise.
A break does not stop a clock (section 1.1), so the species table resets
the monster timer at the break: the break buys a whole fresh clock.
Build: one block ahead of :7224 with its own switch. Stays verbatim:
Eraser, the Flare phase, the counter.

**Shields.** 6, the floor's number; proposed 8.

**Break story.** MOG's spear is the only class key in this party; ice is
CELES's. UMARO and RELM hold none unless RELM casts. A party of four with
one class key and one caster's element: thin, and it shows.

**On the line.** Won in 4,836 ticks, no death, **never broken** (lowest
1): eight actions, six Fights and two skills, and it was dead
(`wor_locke.log:1436-2666`).

### 15. Doom Gaze — the sky

Party: CELES, RELM, GOGO, STRAGO (`wor_opera.log:7469`). Formation 463;
met from the Falcon's deck, and its HP carries between meetings.

**Built.** 8 shields; pierce, special (`ot6_hud.asm:3053-3057`); weak
fire and holy, absorbs ice and poison.

**Script** (`ai_script.asm:5480-5500`). It opens with L5 Doom, and its
third turn is to leave:

```
5486:         attack BATTLE, DOOM, ICE_3
5487:         wait
5488:         attack DOOM, AERO, AERO
5489:         wait
5490:         set_target SELF
5491:         attack NOTHING, ESCAPE, ESCAPE
```

**Hook.** The hunt. He flees on his third turn, two picks in three, and
keeps his wounds for the next meeting. A Broken monster takes no turn, so
**a Broken Doom Gaze cannot flee**: that is true today, by the turn rule
alone. The break is the net.

**Telegraph.** "Doom Gaze turns to flee" on his second turn, riding on
its attack; Escape on the third, certain. A break in the fuse holds him
for the window, and with the cancel store he starts his three turns
again when he recovers. Stays verbatim: L5 Doom, Doom, the HP carried
between meetings.

**Shields.** 8, the boss band.

**Break story.** RELM's brush is the class key; fire and holy from the
casters. Two members of four hold no key.

**On the line.** Three meetings: 7,919 ticks and he escaped (broken once,
at 3,162), 5,214 ticks and he escaped (never broken), 6,141 ticks and he
died (broken at 4,447 with 8,960 HP left)
(`wor_opera.log:7469`, :9251, :11145). GOGO fell to the opening L5 Doom
in all three, 247-257 frames in (`:5528`, `:7996`, `:9605`: "by slot 0
cmd $0C atk $94 (ONE ACTION from >= 80%)"): he is level 45 on this line
(`wor_ebot.log:13088`).
Vanilla's level trick, and it stays. With CELES seated the hunt takes
three to five meetings (route-wor-gogo.md section 4).

### 16. SrBehemoth, twice — the Veldt cave

Party: TERRA 51, CELES 50, RELM 47, GAU 33 (`wor_gau.log:1817`, :2003).
Event battle 82: formation 452, then formation 424.

**Built.** Two rows, 6 shields each, pierce and bludgeon:
`ot6_hud.asm:3076-3081` for the first (`$119`, weak fire and poison,
absorbs ice) and :3314-3317 for the second (`$07F`, weak fire and holy,
absorbs poison). The second row sits under the Colosseum's heading, which
says its bodies "are met nowhere else" (:3301-3305); it is also this
cave's second body (below).

**Script.** The first beast's death is the event
(`ai_script.asm:5338-5348`):

```
5338:         if_monsters_dead MONSTER_1
5340:                 hide_monsters SELF, FADE_HORIZONTAL
5341:                 dlg $7c
5343:                 chars_right_to_left
5344:                 dlg $7d
5346:                 change_battle 424, INSTANT, RESTORE_MONSTERS
```

"Enemy's coming from behind!", the party turns round, and formation 424
is the undead SrBehemoth (`formations.txt`: "424
['SRBEHEMOTH_UNDEAD$07f']"). The second opens on any sleeper with
vanilla's "4 attacks!!" (:4160-4169) and its Special is Hypno Gas
(`specials.txt`).

**Hook.** The fight turns round. The first beast's death brings its
corpse in from behind with its elements inverted: poison hurt the first
and heals the second, and holy now hurts.

**Telegraph.** Vanilla's, on the second body: Hypno Gas puts a member to
sleep, and the next turn that member takes four blows with the line "4
attacks!!". Proposed: a `wait` between the line and the blows, so the
line is a fuse and not a caption. The first body gets none.

**Shields.** 6 and 6, guards' counts for a two-stage fight.

**Break story.** TERRA's dagger pierces, RELM's rod and GAU's fists are
blows; fire is TERRA's. GAU's Were-Rat poison, the first body's vanilla
key (:3079), heals the second.

**On the line.** Won in 6,737 ticks, no death; the first broken at 1,720
and the second at 5,008 (`wor_gau.log:602`, :1394, :1817). The outcome
line names formation `$1A8` where the key line names `g01C4`:
route-wor-gau.md finding 6 left that "not explained here"; it is the
`change_battle` above.

### 17. Hidon — Ebot's Rock

Party: STRAGO 53, RELM 53, GOGO 45, TERRA 54 (`wor_ebot.log:12774`,
:13088). Formation 464: Hidon and four Hidonites.

**Built.** Hidon 6, pierce and bludgeon; the Hidonites 2 each, a
different pair on each (`ot6_hud.asm:3183-3197`). Hidon is weak to fire,
holy and earth and absorbs poison.

**Script** (`ai_script.asm:5731-5789`). Vanilla's own fuse, and its
switch is the adds:

```
5744:         if_monster_switch_clr 0
5745:         if_num_monsters 1
5746:                 short_glow MONSTER_1
5747:                 set_target NOTHING
5748:                 attack GRANDTRAIN
5749:                 clr_battle_switch 0, 0
5750:                 set_monster_switch 0
```

GrandTrain comes only when he stands alone, once, until the Hidonites
return (all four, 80 counts after the last fell, :5732-5739).

**Hook.** The fuse the party wants. GrandTrain is STRAGO's lore and no
other species casts it, so this is the one fight where the right play is
to arm the big move, let it land, and survive it. Killing the four
Hidonites is the arming.

**Telegraph.** Vanilla's glow, with a line, "Hidon swells", and a `wait`
before GrandTrain. A break in the fuse cancels it, which here is the
mistake: the lesson is that a break is a choice. Stays verbatim: the
Hidonites' return, ChokeSmoke on the fallen, the counter.

**Shields.** 6; Hidonites 2.

**Break story.** It is STRAGO's quest and every body takes his rod
(:3159-3162); TERRA's dagger, fire and holy besides.

**On the line.** Won in 14,937 ticks, no death; Hidon broken twice, at
5,560 and 11,335 (`wor_ebot.log:10552`, :11927). STRAGO studies him:
"the party beat it before it cast it, so he keeps his points while it
stands" (route-wor-gogo.md section 4). The line already plays to the
hook.

### 18. Dirt Drgn — the Opera House

Party: CELES, RELM, GOGO, STRAGO (`wor_opera.log:4671`). Event group 134.

**Built.** 6 shields; pierce, bludgeon (`ot6_hud.asm:3200-3203`); weak
wind and water.

**Script** (`ai_script.asm:6989-7011`). Every turn is earth, and a clock
watches for Float:

```
6990:         if_monster_timer 20
6991:                 reset_monster_timer
6992:                 if_status_set RAND_CHAR, FLOAT
6993:                         set_target ALL_CHARS
6994:                         attack FIFTY_GS
```

**Hook.** Fight from the air. Float dodges everything it casts, and it
spends its turns pulling Float down. Measured: with a Cherub Down on each
member, "the dragon spent 136 actions on 50 Gs ... and its 37 Quakes took
nothing" (route-wor-gogo.md section 4).

**Telegraph.** Vanilla's, with a beat added: 50 Gs is the announce, and
the earth spell that follows is the move. Proposed: after a 50 Gs that
grounds someone, the next turn's pick is Quake, certain, with the line
"The stage cracks". Break between the two and the grounded member is
safe. Stays verbatim: 50 Gs, Honed Tusk, the rotation.

**Shields.** 6; proposed 8.

**Break story.** STRAGO's rod is the blow and his Aqua Rake the wind and
water; the other three hold no class key.

**On the line.** Won in 8,339 ticks, no death, **never broken** (lowest
2): thirteen actions, seven spells, five lores and an item, no Fight
(`wor_opera.log:2791-4671`). Over draws: 60 of 60 with the Cherub Downs,
0.05 deaths a fight.

### 19. The Dream Stooges — Cyan's dream

Party: CELES 53, RELM 53, TERRA 54; three, since CYAN is the dream's
(`wor_dream.log:9145`, :9233). Formation 460, event battle 90.

**Built.** 4 shields each, three class pairs that between them take every
hand (`ot6_hud.asm:3252-3261`). Curley weak to ice and water, Larry to
fire, Moe to nothing; each absorbs another's element.

**Script** (`ai_script.asm:5543-5692`). Three scripts with one shared
block and a job apiece:

```
5544:         if_monsters_alive {MONSTER_1, MONSTER_2, MONSTER_3}
5545:         if_battle_timer 30
5546:                 reset_battle_timer
5547:                 set_target RAND_CHAR
5548:                 attack DELTA_HIT
```

Curley raises the fallen with Life 2 (:5560-5567). Larry runs after four
hits and comes back 30 counts later, each with a line (:5608-5628). Four
Magic commands and each wraps itself in Reflect and bounces its own
tier-3 spell at the party (:5550-5559).

**Hook.** A trio with jobs. Delta Hit (Petrify) is theirs only while all
three stand, Curley undoes any kill, and Larry leaves the field. The
fight is a kill order among three bodies of equal weight.

**Telegraph.** "The three line up" on a stooge's turn when the battle
clock passes 20; Delta Hit at 30, as now. Breaking any one of the three
in the fuse cancels it: the species table resets the battle timer at the
break. Stays verbatim: Life 2, Larry's exit and return, the Reflect
answer to Magic.

**Shields.** 4 each, 12 across three gauges.

**Break story.** Two blades and a rod or brush: between the three bodies
every member holds a key somewhere (:3252-3253).

**On the line.** Won in 11,616 ticks, no death, three breaks, the first
at 534 (`wor_dream.log:6493`, :9145). Over draws: 10 of 10, low point 97%
(route-wor-dreams.md section 4).

### 20. Wrexsoul — Doma's throne, in the dream

Party: CELES 54, RELM 54, TERRA 55 (`wor_doma.log:6114`, :6398).
Formation 462: Wrexsoul and two SoulSavers. Event battle 92.

**Built.** Wrexsoul 6, slash and special; the SoulSavers 2, special
(`ot6_hud.asm:3262-3268`). All three weak to ice, absorbing fire and
holy.

**Script** (`ai_script.asm:5697-5726`, :7657-7693). He opens by hiding in
a member (Zinger), comes out when the host falls, and goes back in:

```
5703:         if_battle_switch_set 0, 0
5704:                 set_target ALL_REFLECT_MONSTERS
5705:                 attack NOTHING, BOLT_3, BOLT_3
5706:                 wait
5707:                 set_target ALL_REFLECT_MONSTERS
5708:                 attack NOTHING, BOLT_3, BOLT_3
5709:                 wait
5710:                 set_target RAND_CHAR
5711:                 attack NOTHING, ZINGER, ZINGER
```

The SoulSavers restore themselves when they fall (:7681-7690).

**Hook.** He hides inside a party member, and only felling the host
brings him out. Nothing else in the game asks the party to turn on its
own.

**Telegraph.** "Wrexsoul's shape wavers" on his second turn out; Zinger
on the third, certain (vanilla: two in three). A break in the fuse keeps
him out for the window, and the cancel store gives him three turns to
count again. Stays verbatim: the opening Zinger, the host rule, the
SoulSavers.

**Shields.** 6; SoulSavers 2.

**Break story.** Two blades for Wrexsoul and RELM's brush for all three;
ice from CELES.

**On the line.** Won in 11,162 ticks. One death, the host's, by the
party's own hand (`wor_doma.log:4925`: "entity 3 char 0 from 41/4383 by
entity 0 char 6 cmd $00 atk $FF (an ally's action)"). Broken once, late:
tick 9,302 with 3,535 of 23,066 HP (`:5686`). Over draws: 11 of 11
(route-wor-dreams.md section 4).

### 21. Blue Drgn — the Ancient Castle

Party: CELES 55, RELM 55, CYAN 44, TERRA 56 (`wor_ancient.log:11511`,
:11552). Event group 137; it walks the queen's east room.

**Built.** 6 shields; slash, pierce (`ot6_hud.asm:3286-3288`); weak bolt,
absorbs water.

**Script** (`ai_script.asm:7147-7218`). CleanSweep at the open and every
40 counts of the battle clock (:7148-7155), and this, once a rotation,
for each seat:

```
7157:         if_status_set CHAR_SLOT_1, HASTE
7158:         if_status_clr SELF, HASTE
7159:         if_status_clr SELF, PROTECT
7160:                 set_target SELF
7161:                 attack SLOW
7162:                 set_target CHAR_SLOT_1
7163:                 attack RIPPLER
```

Rippler exchanges the caster's statuses with the target's.

**Hook.** The thief of buffs. It Slows itself on purpose and then trades:
the member's Haste for its Slow, and whatever else that member wears. The
party's own preparation is what it takes.

**Telegraph.** Vanilla's, with a beat between: its Slow on itself is the
announce, and Rippler follows the same turn today. Proposed: a `wait`
between them. Break it in the fuse and it stays Slowed with nothing
traded. Stays verbatim: CleanSweep's clock, the Aqua Rake phase under
16,384.

**Shields.** 6; proposed 8.

**Break story.** Three blades key it; bolt from the Maduin or Tritoch
wearer. CYAN returns from his dream with every SwdTech.

**On the line.** Won in 3,429 ticks, no death; broken at 1,760 with
18,953 of 26,900 HP (`wor_ancient.log:11047`, :11511). The shortest boss
fight of the line: six actions. "Not a coin flip; no lab"
(route-wor-dreams.md section 4).

### 22. KatanaSoul — the Ancient Castle's chest

Party: the same four (`wor_ancient_boxes.log:1379`), on a branch leg.
Formation 465, event group 95.

**Built.** 6 shields; slash, pierce (`ot6_hud.asm:3296-3300`); weak
poison.

**Script** (`ai_script.asm:5794-5838`). A clock with vanilla's own line,
and two counters:

```
5795:         if_monster_switch_clr 0
5796:         if_battle_timer 40
5797:                 short_glow MONSTER_1
5798:                 dlg $63
5800:                 set_target SELF
5801:                 set_status IMAGE
5802:                 set_status REFLECT
5803:                 set_status HASTE
```

Six Fights draw SlayerEdge (:5813-5817); three Magic or Lore commands
draw a thrown blade and GP Rain (:5806-5812).

**Hook.** The mirror duelist: he answers steel with steel and magic with
blades and coin, and after 40 counts he is Hasted, Imaged and Reflecting.
A duel against a clock.

**Telegraph.** Vanilla's line, "KatanaSoul's power up!", with a `wait`
before the statuses land.

**On the line.** Won in 4,037 ticks, no death; broken at 2,009
(`wor_ancient_boxes.log:877`, :1379).

### 23. Master Pug — the chest in the castle's cave

Party: the same four (`wor_ancient_boxes.log:4751`). Formation 483, event
group 113.

**Built.** 6 shields; slash, special (`ot6_hud.asm:3291-3295`); no
weakness of its own, absorbs water.

**Script** (`ai_script.asm:6488-6542`). WallChange on a clock, and then
the spell opposite the weakness it now wears:

```
6489:         if_monster_timer 15
6490:                 reset_monster_timer
6491:                 attack WALLCHANGE
...
6502:         if_weak_element SELF, ICE
6503:                 set_target NOTHING
6504:                 attack NOTHING, FIRE_3, FIRE_3
```

and so for each of the eight (:6502-6533). Every hit draws Step Mine.

**Hook.** The spell is the tell. Its weakness turns every 15 counts, and
the spell it casts names the element that will break it: Fire 3 means
ice. A weakness that rotates, as Octopath has them, read from vanilla's
own script.

**Telegraph.** Vanilla's, unchanged: WallChange is the announce and the
spell the move.

**On the line.** Won in 3,159 ticks, no death; broken at 1,285
(`wor_ancient_boxes.log:4243`, :4751).

## Kefka's Tower

Three parties, each two carriers and two of the bench
(route-wor-kefka-tower.md section 4). Party 1: TERRA, RELM, EDGAR, SETZER.
Party 2: CELES, STRAGO, LOCKE, MOG. Party 3: CYAN, SHADOW, SABIN, GOGO.
Levels at Guardian's save: TERRA 63, CELES 58, CYAN 55, SHADOW 56, RELM
55, STRAGO 54, EDGAR 52, GOGO 46, LOCKE 43, SABIN 41, MOG 40, SETZER 32
(`wor_kt_guardian.log:10615`).

### 24. Inferno, Striker and Rough — the factory

Party 3 (`wor_kt_inferno.log:2607`). Formation 484, event battle 114.

**Built.** Inferno 6, pierce and bludgeon; Striker 3, slash and pierce;
Rough 3, slash and bludgeon (`ot6_hud.asm:3429-3438`). A triangle of
elements: Inferno weak to bolt and drinking fire, Striker weak to fire
and drinking ice, Rough weak to ice and drinking bolt.

**Script** (`ai_script.asm:4753-4783`, :6756-6789). Delta Hit on a
30-count clock while all three stand, the Stooges' block
(:4754-4758). One arm down, Bolt 3 or Meteor every turn (:4766-4768);
both down, TekBarrier on itself (:4759-4765). Each arm returns on its own
clock, Rough after 20 counts and Striker after 40:

```
6757:         if_monsters_dead MONSTER_4
6758:         if_monster_timer 20
6759:                 restore_monsters MONSTER_4, FADE_DOWN
```

**Hook.** As vanilla wrote it, this is Number 128 again (arms that regrow
and change the body's script) with the Cranes' wrong-element heal on top:
flagged in 2.1. Proposed, from Octopath: **the arms guard the engine.**
While an arm stands, Inferno's gauge is shut and its count is drawn
locked; an arm's death opens it until that arm's clock brings it back, 20
or 40 counts. The longer window is Striker's, so which arm to kill is a
choice. Build: a species flag read in `Ot6Chip` and `Ot6ClassChip`,
refusing the chip while another body of the formation is present, and one
HUD state. A returning arm is fresh already (#557, `ot6_break.asm:203`).

**Telegraph.** "Inferno's coils whine" on the first beat of its rotation;
Giga Volt on the second, certain (vanilla: two in three, :4771). Stays
verbatim: the arms' clocks, Delta Hit, Meteor, TekBarrier.

**Shields.** 6 and 3, 3: a guard and its parts.

**Break story.** SHADOW's point and SABIN's Blitz key Inferno; CYAN's
katana keys both arms; bolt is SHADOW's Bolt Edge. "SABIN's Fire Knuckle
healed Inferno"
(route-wor-kefka-tower.md section 6): the absorb triangle bites.

**On the line.** Won in 8,579 ticks, no death; Inferno broken at 6,145
with 11,113 of 30,800 HP; the arms' gauges never reached 0
(`wor_kt_inferno.log:1985`, :2607). Over draws: 11 or 12 of 12 (section
6).

### 25. Atma — the tower's north

Party 2 (`wor_kt_atma.log:5252`). Formation 482, event battle 112;
optional, with a save point behind him.

**Built.** 10 shields; slash, pierce (`ot6_hud.asm:3455-3458`); no
weakness, absorbs five elements. "the atmaweapon's row, the rematch".

**Script** (`ai_script.asm:8103-8154`). Vanilla's longest fuse, armed by
the party's hits:

```
8104:         if_monster_switch_set 0
8105:                 dlg $83
8106:                 short_glow MONSTER_1
8107:                 attack NOTHING
8108:                 wait
8109:                 short_glow MONSTER_1
8110:                 attack NOTHING
8111:                 wait
8112:                 long_glow MONSTER_1
8113:                 set_target NOTHING
8114:                 attack ULTIMA
8115:                 clr_monster_switch 0
```

`dlg $83` is "Unknown light surrounded Atma!". The switch is set by the
thirteenth counter (:8147-8154; measured, section 1.1), and while it is
set he does not counter.

**Hook.** The charge the party arms. Thirteen blows and he stops attacking
for two whole turns to gather light, then Ultima. The AtmaWeapon's fuse
came on his schedule; this one comes on the party's, and it pays two free
turns to whoever is ready for it. Hits in a break window do not count
(section 1.1).

**Telegraph.** Vanilla's, unchanged, and **built** (#561, section 1.3;
`battle_atma`). The **!** stands from the line to Ultima, which comes on
his second turn after it. A break in between cancels it: the script waits
nowhere, monster switch 0 and battle variable 3 read clear, his first
turns back hold no Ultima, and the line returns only after thirteen more
counted hits ("the tally climbed from 0 to 13 before the second line, as
before the first"). Hits on him while he is Broken count for nothing.
Before, a break delayed Ultima to his second turn back
(build/attempts/wt/v051-fuse/measure/atma.log). Nothing in the script
changed.

**Shields.** 10, one under the AtmaWeapon's 11; proposed 12.

**Break story.** CELES's blade, LOCKE's knife and MOG's spear: three of
four hold a key. No element helps.

**On the line.** Won in 6,611 ticks, no death; broken at 3,183 with
44,055 of 55,000 HP (`wor_kt_atma.log:4415`, :5252). Fifteen party
actions in all. Whether the light came is not measured: the log names no
monster action. Over draws: 12 of 12, 0 deaths (section 6).

### 26. Gold Drgn — the tower's west

Party 2 (`wor_kt_guardian.log:10446`). Event battle 135.

**Built.** 6 shields; slash, pierce (`ot6_hud.asm:3459-3462`); weak
water, absorbs bolt.

**Script** (`ai_script.asm:7047-7118`). **The telegraph already exists in
vanilla, line and all.** Five Fights arm it (measured, section 1.1), in
the counter:

```
7105:         if_cmd FIGHT
7106:         if_battle_switch_clr 0, 0
7107:                 add_monster_var 1
7108:                 if_battle_var_greater 36, 4
7109:                 if_battle_switch_clr 0, 0
7110:                         set_battle_switch 0, 0
7111:                         dlg $73
```

"Gold Dragon begins to store energy!" It then counts two of its own
turns and fires Bolt 3 on the whole party on the third (:7048-7058).
Magic is answered with Bolt instead (:7115-7117), and it wraps itself in
Reflect when a member wears it (:7059-7078).

**Hook.** Fights wind it, spells do not. The player chooses how to hit:
steel is safe four times and the fifth starts the clock, magic is answered
at once and never starts it.

**Telegraph.** Vanilla's, unchanged, and **built** (#561, section 1.3;
`battle_golddrgn`). At three turns it is longer than the contract's one.
The **!** stands from the line (its counter's, on the fifth Fight) to
Bolt 3. A break in between cancels the charge: battle switch 0, the turn
count and the Fight count read clear, its first turns back hold no Bolt 3,
and the line returns only after five more Fights. Its arming block holds a
`dlg`, so before this it ran while the dragon was Broken and Fights in the
window could light the charge on a Broken dragon (section 1.1); a fuse's
announce is no story now, so Fights on a Broken dragon count for nothing,
as hits on a Broken Atma never did.

**Shields.** 6, the floor's number; proposed 8. "It may be too easy for an
eighth dragon" (route-wor-kefka-tower.md section 6).

**Break story.** CELES's blade and the bench's knife and spear; STRAGO's
Aqua Rake is its water.

**On the line.** Won in 4,019 ticks, no death; broken at 1,934 with
22,733 of 32,400 HP; nine of the ten actions were Fights
(`wor_kt_guardian.log:9891`, :10446), enough to arm the charge. Whether
Bolt 3 fired is not measured: the log names no monster action.

### 27. Skull Drgn — the tower's east

Party 3 (`wor_kt_guardian.log:3979`). Event battle 136.

**Built.** 6 shields; bludgeon, special (`ot6_hud.asm:3463-3466`); weak
fire and holy, absorbs poison.

**Script** (`ai_script.asm:7123-7142`). A fixed bar of four beats, no
conditions:

```
7125:         attack BATTLE, CONDEMNED, ELF_FIRE
7126:         wait
7128:         attack BATTLE, CONDEMNED, SPECTER
7129:         wait
7131:         attack BATTLE, CONDEMNED, ELF_FIRE
7132:         wait
7133:         set_target RAND_CHAR
7134:         attack DISASTER
```

Disaster is Dark, Imp, Condemned, Mute, Muddle and Float on one member
(`attacks.txt`).

**Hook.** A four-beat bar. The fourth beat is always Disaster, the only
turn in the game's dragons with no dice in it. A player can count it.

**Telegraph.** "The Skull Dragon's jaw unhinges" on the third beat, riding
on its attack; Disaster on the fourth, as now. The cancel store restarts
the bar at its first beat, so a break in the fuse buys three safe beats.
The script's odds do not change at all: this is the cleanest fit in the
World of Ruin.

**Shields.** 6, the floor's number; proposed 8.

**Break story.** Thin on class: "Party 3's keys are slash and pierce
only" (route-wor-kefka-tower.md section 4), so SABIN's Blitz is the only
blow and nobody holds special. Fire is SHADOW's skean and SABIN's; holy
is Aura Bolt.

**On the line.** Won in 5,420 ticks, no death; broken at 3,847 with
15,162 of 32,800 HP (`wor_kt_guardian.log:3529`, :3979).

### 28. Guardian — the chamber's middle

Party 2 (`wor_kt_guardian.log:61064`). Battle 140, record `$112`; the
WoB's `$111` keeps no gauge.

**Built.** 10 shields; pierce, bludgeon (`ot6_hud.asm:3439-3443`); weak
bolt and water.

**Script** (`ai_script.asm:3674-3788`). Four programs, each announced and
each ending in another boss's finisher. The third and fourth:

```
3711:                 dlg $80
3713:                 attack TEK_LASER, DIFFUSER, DIFFUSER
3714:                 wait
...
3719:                 dlg $67
3722:                 dlg $3c
3724:                 dlg $45
3726:                 attack WAVECANNON
...
3741:                 dlg $65
3743:                 short_glow MONSTER_1
3746:                 set_target NOTHING
3747:                 attack FLARE_STAR
```

"Ran Air Force's battle program!", three turns, then "Wave Cannon! Count
down!! Count 3! Count 2! Count 1!" and the shot in one turn; "Ran Atma's
battle program!", three turns, "Vast energy focused" and Flare Star in
one turn. Between programs it runs its basic one (:3775-3780).

**Hook.** A boss rush in one body. It plays Ultros, Dadaluma, the Air
Force and Atma in turn, and each program's name tells the player which
finisher is three turns away. A memory test of the World of Balance.

**Telegraph.** Vanilla's lines, with one beat moved: a `wait` between each
countdown and its shot, so "Count 1!" and "Vast energy focused" are
fuses. The contract allows one telegraph a boss and this body has four
programs; proposed as one telegraph, "the program", whose announce is its
name (open question 5). A break aborts the program: the species table
clears monster switches 1-4 and he falls back to the basic program.

**Shields.** 10, the capstone band.

**Break story.** LOCKE's knife, MOG's spear and STRAGO's rod; CELES wants
Bolt. STRAGO's Aqua Rake is its water.

**On the line.** Won in 7,496 ticks; broken at 4,252 with 46,711 of
60,000 HP; one death, MOG from full HP in one action
(`wor_kt_guardian.log:59863`, :60228, :61064). Over draws: 11 of 11
(section 6).

### 29. Doom — the west column

Party 3 (`wor_kt_doom.log:23003`). Formation 468, event battle 98.

**Built.** 10 shields; slash, special (`ot6_hud.asm:3444-3447`); weak
holy, absorbs ice and poison.

**Script** (`ai_script.asm:5861-5913`). At half his HP, in the counter,
with vanilla's line:

```
5901:                 if_hp SELF, 32640
5902:                 if_monster_switch_clr 1
5903:                         short_glow MONSTER_1
5904:                         short_glow MONSTER_1
5905:                         dlg $88
5907:                         set_target SELF
5908:                         set_status IMAGE
5909:                         set_status REFLECT
5910:                         set_status HASTE
```

"Doom's aura is shaking!" From then on he casts ForceField every 20
counts, up to eight times (:5865-5871), marks a member with Targetting,
and opens his next turn with Demon Rage on the mark (:5862-5864,
:5877-5885).

**Hook.** The field closes. Each Force Field nulls one more element,
chosen at random, for everyone on the field (vanilla's spell, special
effect `$31` in `attacks.txt`; its reach is not measured here); eight
casts and no element lands. His one vanilla weakness, holy, can be shut
by the first cast or the eighth.
The classes stay open: this is the fight where the weapon is the key that
cannot be taken. Octopath's locked weaknesses, from vanilla's own spell.

**Telegraph.** Vanilla's, unchanged: Targetting marks a member, and his
next turn begins with Demon Rage on the mark. The crosshair is the
announce. A break between the two holds the blow for the window; whether
the mark is cleared is open question 1. Stays verbatim: the aura and its
statuses, ForceField, R.Polarity at eight hits, the ice rotation.

**Shields.** 10.

**Break story.** CYAN's katana and SABIN's claws are slash; nobody in
party 3 holds special; holy is SABIN's Aura Bolt. His phase change runs
even while he is Broken (its block holds a `dlg`), and its Haste shortens
his breaks (bosses-wob.md:77-80).

**On the line.** Won in 10,754 ticks; broken at 5,452 with 25,589 of
63,000 HP; one death, SABIN to Ice 3 holding three points
(`wor_kt_doom.log:21332`, :21618, :23003). Over draws from Guardian's
save: 9 of 9 once the bench is levelled and dressed against ice
(route-wor-kefka-tower.md finding 6).

### 30. Goddess — the east column

Party 1 (`wor_kt_goddess.log:2124`). Formation 469, event battle 99.

**Built.** 8 shields; pierce, special (`ot6_hud.asm:3448-3450`); no
weakness, absorbs bolt and holy.

**Script** (`ai_script.asm:5918-5956`). Every Fight is answered with Love
Token (:5949-5952), which makes its target take her hits; Charm and
Lullaby sit in her rotation; after eight hits, once, Overcast
(:5919-5925), which turns whoever falls into a Zombie. Under 32,640 HP
the rotation changes, and its third turn is:

```
5933:                 set_target NOTHING
5934:                 attack BOLT_3, QUASAR, QUASAR
```

**Hook.** She borrows the party. Love Token makes the member who struck
her into her shield, Charm turns one against the rest, and Overcast keeps
the fallen. Other bosses have adds; hers are the player's own.

**Telegraph.** "The sky splits" on the second turn of the low rotation;
Quasar on the third, certain (vanilla: two in three). Stays verbatim:
Love Token, Charm, Lullaby, Overcast.

**Shields.** 8; proposed 10.

**Break story.** EDGAR's spear, SETZER's cards or darts, RELM's brush:
three of four hold a key. No element helps.

**On the line.** Won in 6,242 ticks, no death; broken once, at tick
4,635 with 19,159 of 44,000 HP (`wor_kt_goddess.log:1686`, :2124). Over
draws: about 7 or 8 of 9 (route-wor-kefka-tower.md finding 6).

### 31. Poltrgeist — the middle column

Party 2 (`wor_kt_poltergeist.log:61829`). Formation 470, event battle
100.

**Built.** 8 shields; bludgeon, special (`ot6_hud.asm:3451-3454`); weak
poison, absorbs fire and wind.

**Script** (`ai_script.asm:5961-6000`). A two-step kill ahead of the
rotation, and a counter on every hit:

```
5966:         if_status_set CHAR_SLOT_1, STOP
5967:                 attack BLASTER
5968:                 end_if
...
5988:         attack BATTLE, SHRAPNEL, STOP
...
5996:         if_hit
5997:                 add_battle_var 3, 1
5998:                 attack NOTHING, FIRE_3, NOTHING
```

Blaster is Death (`attacks.txt`). Eight hits draw Wave Cannon
(:5962-5965).

**Hook.** The executioner: he Stops a member, and his next turn kills
whoever is Stopped. And every hit is answered, one time in three, with
Fire 3. Few large actions, and a Stop to answer inside one turn. Flagged
in 2.1 as the Tentacles' shape; if that is too close, the Fire 3 answer
is the hook.

**Telegraph.** Vanilla's, unchanged: Stop is the announce and Blaster the
move, one turn apart. A break, or a cure for Stop, cancels it.

**Shields.** 8; proposed 10 with care (section 3.2, 3).

**Break story.** The thinnest in the tower. STRAGO's rod is the party's
only class key (the leg hands him the Pearl Rod for it,
route-wor-kefka-tower.md section 5); CELES, LOCKE and MOG hold none.
Poison is its vanilla weakness, the Tritoch wearer's spell. One
key-holder in four is a flag: a party 2 without STRAGO could chip it
only by poison.

**On the line.** Won in 18,367 ticks, no death; broken twice, at 6,922
and 16,611 (`wor_kt_poltergeist.log:58951`, :61313, :61829). It is the
longest tower fight by a factor of two. Over draws it was the tower's
coin flip before the bench was levelled: 6 of 11, three or four deaths in
every win (section 6).

## The final battle

One battle, four formations (`FinalBattleIDTbl`,
`battle_main.asm:12759-12760`: 471, 512, 513, 514); the fallen are
replaced between tiers in the order the player set
(route-wor-the-end.md findings 1-2). On the line the front four are
TERRA, CELES, STRAGO, RELM, and Kefka is finished by CYAN, SHADOW, STRAGO
and RELM (`wor_kefka.log:3839`, :21328).

### 32. The three tiers

**Built.** Short Arm 6, Long Arm 6, Face 8; Hit 6, Tiger 6, Tools 6,
Magic 8; Girl 3, Sleep 8 (`ot6_hud.asm:3473-3504`). Each tier's bodies
between them take every hand.

**Script** (`ai_script.asm:7360-7592`). The moves that decide these tiers
are on deaths and last stands, not on turns:

```
7430:         if_num_monsters 0
7431:         if_self_dead
7432:                 set_target NOTHING
7433:                 attack QUAKE               ; the Face
...
7535:         if_self_dead
7537:                 attack SPECIAL             ; the Hit, then nine Battles
...
7553:         if_num_monsters 1
7554:                 set_target ALL_DEAD_MONSTERS
7555:                 attack LIFE_2              ; the Girl, alone
...
7583:         if_self_dead
7585:                 attack SPECIAL             ; the Sleep: Calmness, twice
```

**Hook.** Kill order as the puzzle, three times over, with a roster
behind it. The Face's death is a Quake; the Long Arm alone answers every
action with three Shock Waves (:7389-7394); the Hit dies swinging ten
times; the Girl raises the Sleep; the Sleep's death kills two.

**Telegraph.** None proposed: these are bodies of one battle, and the
battle's telegraph is Kefka's. Their dying attacks are what open question
4 would touch: "The third tier kills on its way out"
(route-wor-the-end.md finding 3).

**Shields.** On the band; the Face's 8 unchipped on the line (section
3.2, 6).

**On the line.** Tier 1: 11,466 ticks, no death, one break (the Long
Arm). Tier 2: 32,045 ticks, six breaks, no death. Tier 3: 22,948 ticks,
two breaks and five deaths, three of them to the Sleep's Meteo
(`wor_kefka.log:14715`, :15347, :15992: "by slot 3 cmd $0C atk $DF").

### 33. Kefka

**Built.** 16 shields, every hand (`ot6_hud.asm:3505-3510`); no weakness,
nulls poison. Decided (#514): "Kefka holds the most shields of any boss"
(route-wor-the-end.md section 6).

**Script** (`ai_script.asm:6005-6076`). Vanilla gives the last boss a
one-turn fuse with a line:

```
6024:         if_hp SELF, 32640
6025:                 dlg $8c
6027:                 set_battle_switch 0, 0
6028:                 set_battle_switch 0, 1
6029:                 kefka_head MONSTER_1
6030:                 wait
6031:                 set_target NOTHING
6032:                 attack GONER
```

"The end comes...beyond chaos.", his head, and Goner on the next turn;
two turns of attacks follow and the block starts again, so under 32,640
HP the line returns every fourth turn. Above it his first turn is Fallen
One on the whole party with no warning (:6044-6046). Low, a hit draws
HyperDrive or Ultima (:6065-6076), but not while the fuse's switch is
set.

**Hook.** The whole roster's fight: who stands in front is the order the
player chose, and the fallen are replaced from it. And the last boss is
the one vanilla already wrote to the contract.

**Telegraph.** Goner, vanilla's, unchanged (the owner, 2026-11-23: it
"sounds well integrated with the game"), and **built** (#561, section 1.3;
`battle_goner`). The **!** stands from the line to Goner, his next turn.
A break in between cancels it: battle switches 0 and 1 read clear, so his
counters stand again, and since his HP is what arms him he says the line
again on his first turn back; Goner needs the full turn after that. Before,
a break delayed Goner to his first turn back with no new line
(build/attempts/wt/v051-fuse/measure/goner.log). Fallen One, the move that
costs the line its fights (route-wor-the-end.md 5.2-5.4), has no announce
and is not his telegraph.

**Shields.** 16, decided.

**Break story.** Every hand keys him; no element does.

**On the line.** Won in 17,138 ticks; broken once, at tick 9,237 with
37,134 of 62,000 HP, above Goner's line; one death, CYAN from full HP in
one action (`wor_kefka.log:19014`, :19353, :21328). Over draws at 16: 44
of 44 where met, one known open key (route-wor-the-end.md 5.5, section
6).

## 5. Set-pieces and event fights with no contract

| fight | row | why no contract |
|---|---|---|
| Phunbaba, TERRA alone (battle 128, `$16A`) | 0 (`ot6_hud.asm:2796-2799`) | invincible (`ai_script.asm:7789-7792`); her loss is the story (`wor_terra.log:1762`: "LOST after 1729 ticks") |
| Zone Eater (`$171`) | 0 (:3152-3156) | the fight is to be Engulfed |
| the goddess Chadarnook (`$11E`) | 0 (:2963-2965) | the wrong body of block 11 |
| the Presenter's shell (`$101`) | 0 (:2783-2785) | the wrong body of block 3 |
| Owzer's paintings and the house's event fights (formations 287-290) | the species' own rows; Still Life 4 (:2960-2962) | ordinary species met by event |
| the Tzen house's two chests (Pm Stalker x4) and the Veldt cave's chest (Allo Ver) | the species' own rows | ordinary species in a chest (wor-coverage.md section 12) |
| the Colosseum's Siegfried, Chupon and SrBehemoth | :3306-3317 | one fighter, auto-battled |

## 6. The CzarDragon: a ninth dragon

The idea: the unused CzarDragon as an optional superboss once the eight
dragons fall, in the role Octopath's hidden final boss plays. Feasibility,
from the ROM.

**What exists.**

- A monster record, `$137`: level 83, 60,001 HP, 60,000 MP, speed 30,
  attack 13, defence 102, magic defence 153, no weakness, absorb or null,
  0 XP and 0 GP (`monster_prop.dat` row `$137`; `rows.txt`).
- A name, "CzarDragon" (`ff6/src/text/monster_name_en.json:321`).
- A graphic and palette of its own name, `czardragon.4bpp`
  (`ff6/src/gfx/monster_gfx.asm:91`, :535, :746). The Doom Drgn and the
  Blue Drgn wear the same graphic (:833, :1134); the CzarDragon's own
  entry is :1107.
- An entrance line nothing plays, battle dialogue `$4C`: "Mwa, ha ha...
  Humans and their desires! I'm free at last! I bring you destruction...
  I bring you terror... I am Czar... Prepare yourselves!"
  (`monster_dlg_en.json:87`; no `dlg $4c` in `ai_script.asm`).
- A formation, 561, the CzarDragon alone (`formations.txt`).
- Steal and drop slots, empty (`monster_items.asm:1882-1884`); Sketch and
  Control entries (`monster_sketch.asm:322`, `monster_control.asm:337`).
- The count it would hang on: event variable 6, counted down by the
  routine every dragon's death calls (`_cc1f9f`, `event_main.asm:81380`,
  called at :28216, :80362, :80390, :81461, :81471, :84738, :86881,
  :89695), which at the last gives Crusader ("Defeated all 8 dragons...
  Dragon Seal broken!!", :81430-81453).

**What does not.**

- A script: `attack BATTLE / end` (`ai_script.asm:6479-6483`).
- A way in: formation 561 is "in no group" (break-coverage-wob.md:389)
  and no event calls it. Seven event battle groups have no call site and
  could be pointed at it (74, 83, 91, 51, 52, 60, 61:
  `ot6_hud.asm:3602-3623`).
- A gauge: its row is 0, in the table of bodies no battle deals
  (`ot6_hud.asm:3610-3611`); `tools/check_shield_rows.py` holds it there
  until a formation deals it.
- A place, a reward, a reason to come. Crusader is already paid by the
  eighth dragon.

**What it would take.** An event (a hook after `give_genju CRUSADER`, or
a place that opens then), a repointed battle group, a script, a row, a
reward, a leg and a suite. The script needs unit A's room (section 1.2)
and nothing else new. The vanilla tools fit the role: Guardian already
shows how one body runs other bosses' programs by name, so the natural
design is **the eight dragons in one body**, each phase wearing one
dragon's key and ending in its signature (Cyclonic, Absolute 0, Pearl,
Flare Star, Quake, Rippler, the stored Bolt 3, Disaster), with the hooks
this document gives them. That makes it the exam for the eight dragons'
blocks, as Octopath's hidden boss is the exam for its eight. Size: one unit of
the build order, after the dragons are built, plus the owner's answers to
question 12.

## 7. Build order

Units of two to four bosses. Each boss gets a suite named as the WoB's
are (`battle_vargas`, `battle_ultros4`): `battle_<boss>`, booting the
graph's capture before the fight, asserting the announce, the move
landing on its turn unbroken, the move absent after a break in the fuse,
and a negative for each. The row suites (`battle_breakwor_<arc>`) keep
checking rows. Each unit ends with its leg's sweep by distinct battle
key, before and after.

| unit | bosses | what it builds | suites |
|---|---|---|---|
| A (**built**, section 1.3) | Atma, Gold Drgn, Kefka (and the WoB's AtmaWeapon) | the machinery of 1.2 on fuses vanilla already wrote: the script block moved, the cancel store, the species table, the lit-fuse mark, the roll condition. No change to those scripts | `battle_fuse` (the table, the block, the worked example), `battle_atma`, `battle_golddrgn`, `battle_goner`, `battle_atmaweapon` |
| B | Tentacles, Dullahan, Phunbaba | the first authored lines; the hostage release; the hit counter cleared by a break | `battle_tentacles`, `battle_dullahan`, `battle_phunbaba` |
| C | Chadarnook, Umaro, Tritoch | a window fight, a buff denied, a command-keyed boss | `battle_chadarnook`, `battle_umaro`, `battle_tritoch` |
| D | Storm, Ice and Red Dragons | the growing gauge; a rotation fuse; a clock reset by the break | `battle_stormdrgn`, `battle_icedragon`, `battle_reddragon` |
| E | MagiMaster, White Drgn, Doom Gaze | the dying move (after question 4); the flight held | `battle_magimaster`, `battle_whitedrgn`, `battle_doomgaze` |
| F | SrBehemoth, Hidon, Dirt Drgn | vanilla lines given a beat; the fuse to leave alone | `battle_srbehemoth`, `battle_hidon`, `battle_dirtdrgn` |
| G | Stooges, Wrexsoul, Blue Drgn | a shared clock; Zinger; Rippler | `battle_stooges`, `battle_wrexsoul` (beside `battle_zinger`), `battle_bluedrgn` |
| H | Inferno, Skull Drgn, Guardian | the guarding arms; the four-beat bar; the programs | `battle_inferno`, `battle_skulldrgn`, `battle_guardian` |
| I | Doom, Goddess, Poltrgeist | the statues as one tier; counts settled by lab | `battle_doom`, `battle_goddess`, `battle_poltrgeist` |
| J | the chests: KatanaSoul, Master Pug, Pugs, the Presenter | a beat on vanilla's lines; no new hooks | `battle_katanasoul`, `battle_masterpug` |
| K | the CzarDragon, if wanted | section 6 | `battle_czardragon` |

A comes first because everything else stands on it and it changes no
script. B is next because it is where a new player meets the contract. I
is late because the statues are the fights closest to a coin flip today.
The dragons' shield changes (section 3.2, 1) ride with D, G and H as
labs.

## 8. Open questions for the owner

Each can be answered in a sentence.

1. **After a break cancels a fuse, must the trigger be earned again?**
   Either the boss announces again on its first turn back (one store, no
   table), or the break also clears what armed it: eight more hits on
   Dullahan, a fresh clock for the Red Dragon, Umaro's cherry gone.
   **Answered: earned again** (built, section 1.3). A clock a break
   restarts keeps running through the break, so a clock shorter than a
   break (2,159 frames) is due again on the boss's first turn back; if a
   fresh clock after recovery is wanted for the Red Dragon, unit D resets
   it at the break's end instead.
2. **May a telegraphed move become certain on its turn** where vanilla
   rolled it one time in three or two in three (Absolute 0, Cyclonic,
   Quasar, Doom Gaze's Escape)? **Answered: it must be.** An announced
   move always fires; the roll, if kept, is made before the announce and
   decides whether the sequence starts (`if_roll`, section 1.3).
3. **Does the boss still attack on the turn it announces?** Proposed yes:
   the line rides on a turn it already takes, so vanilla's count of
   attacks is unchanged. Octopath's bosses spend the turn.
4. **Should a boss killed while Broken lose its dying attack?**
   MagiMaster's Ultima, the Sleep's two Calmness, the Hit's ten blows,
   the Face's Quake, the Ice Dragon's Surge. Today a dying counter runs
   in full (bosses-wob.md:55-57). Story on a death (the death animation,
   a scene) would still play.
5. **One telegraph a boss, or one a phase** where vanilla wrote several
   (Guardian's four programs)?
6. **Kefka's telegraph: Goner, which vanilla announces, or Fallen One,**
   which is what the line loses to? **Answered: Goner** (built).
7. **The eight dragons: one shield count or a ladder?** And is the Storm
   Dragon's 14 the dragons' number, or its own hook (the gauge that
   grows)?
8. **Atma under the AtmaWeapon's 11:** raise the rematch to 12?
9. **The three statues: one count for the Triad (10, or 12), or 10, 8, 8
   as the lanes have them?**
10. **Hooks that need new code, borrowed from Octopath:** the growing
    gauge (Storm Drgn) and the guarding arms (Inferno). Welcome, or
    should every hook be vanilla's?
11. **Hidon: is GrandTrain a fuse the player is meant to leave alone,**
    so STRAGO learns it?
12. **The CzarDragon:** wanted? If so, where does it wait, and what does
    it pay, now that Crusader is the eighth dragon's prize?
13. **Should a break free a member a Tentacle holds?** **Answered: yes,**
    and the same for any body that holds or swallows a member for a
    while; a contract rule, built with unit B.

## 9. Surprises

1. **No telegraph is built anywhere, WoB included.** bosses-wob.md's
   telegraph lines are prose; `ai_script.asm` is untouched since the
   disassembly was absorbed. The contract's built half is the break's
   effect on turns and counters (section 1).
2. **A break delayed a vanilla fuse and did not cancel it** (section
   1.1): the script resumed where its `wait` left it. Measured since on
   all four fuses, and fixed by unit A (section 1.3).
3. **Vanilla already wrote fuses for six WoR bosses, five with a line:**
   the Gold Dragon's "begins to store energy!", Atma's "Unknown light",
   Kefka's "The end comes...beyond chaos.", Guardian's countdown, the
   second SrBehemoth's "4 attacks!!", and Hidon's glow. Three more
   announce a self-buff (Umaro, KatanaSoul, Doom), and three are a status
   that marks the victim a turn ahead (Entwine, Stop, Targetting).
4. **One WoR big move is already cancelled by a break, and the line does
   it:** Phunbaba's two BabaBreaths, by the story-while-broken rule. The
   line's fourth fight opens with four seated (block 4).
5. **Bosses the line never breaks:** all four Tentacles, the Red Dragon,
   the Dirt Drgn, the White Drgn, MagiMaster, the Whelk head, and the
   Face, whose gauge never moved. None is unbreakable by its party; each
   is killed first, or waited out.
6. **Thin break stories:** the Poltrgeist (one class key-holder in its
   party), the Red Dragon (one), the Skull Drgn (one blow, no special in
   party 3), Doom (no special in party 3), and the White Drgn (one
   spell). None is unbreakable.
7. **The second SrBehemoth is a different species under a heading that
   says otherwise.** `$07F` (formation 424) arrives by `change_battle`
   from the first one's death; its row sits with the Colosseum's bodies
   "met nowhere else" (`ot6_hud.asm:3301-3317`). The row's values are
   right for it. The comment is wrong, and it explains the formation
   mismatch route-wor-gau.md finding 6 left open.
8. **`if_battle_var_greater` is "at least", and a tally still needs one
   more hit than its number**, because the block's own add runs after its
   conditions are read: measured on Atma (13) and the Gold Dragon (5).
   The two route documents' counts were right (section 1.1).
9. **The script block was full:** under ten free bytes. Unit A moved it
   to bank `$F1` with about 9,900 free (section 1.3).
10. **Seven dragons carry 6, the fallback's number**, one of them by
    measurement, and three of the late ones are the line's shortest boss
    fights (section 3.2, 1).
11. **Atma (10) has fewer shields than the AtmaWeapon (11).**
12. **The Presenter was won by killing its shell**, the body with no
    gauge that the fight calls the wrong answer (block 3).
13. **MagiMaster's Ultima took all four from full HP**, and Life 3 raised
    the three who wore it; STRAGO, without it, stayed down. The driver
    logged it as a `[wipe]` before a won outcome (block 13; #564).
14. **GOGO dies to Doom Gaze's opening L5 Doom in every meeting**: level
    45 (block 15).
15. **Doom Gaze cannot flee while Broken**, today, with nothing built for
    it (block 15).
16. **The demon Chadarnook's hit counter runs while he is Broken**, and
    the goddess stays one turn or three by how he left (block 11).

## 10. Evidence

Under `build/attempts/wt/v051-bosses-wor/` in the main tree:

| file | what |
|---|---|
| `raw_lines.md` | for each boss fight on the line: the open, each break's board line, each death, the outcome, with log line numbers (`rawlines.py`) |
| `fights_states.txt`, `fights_edgar.txt` | the same fights summarised: decisions, lowest shield readings, monster actions (`fights.py`) |
| `party.txt` | who fought each boss and at what level (`party.py`) |
| `rows.txt` | each body's shield row with its `ot6_hud.asm` line, and its level, HP and elements from `monster_prop.dat` (`rows.py`) |
| `formations.txt` | the boss formations decoded from `battle_monsters.dat` (`form.py`) |
| `ai_ranges.txt` | each body's script lines in `ai_script.asm` (`ai.py`) |
| `attacks.txt`, `specials.txt` | the signature attacks' records and each body's Special (`atk.py`, `special.py`) |
| `ai_block_free.txt` | the script block's free bytes in the built ROM and the free dialogue slots (`aiblock.py`) |

No emulator was run for this survey. Every play number is one fight of
the line as it stood on 2026-11-22, except where a route document's sweep
is cited by section.
