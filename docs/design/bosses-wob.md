# WoB bosses, boss by boss

Scope: every boss and miniboss from Whelk through the Floating
Continent, in story order. Shield counts and weakness rows here are the
hand-authored table. ✦ marks vanilla behavior kept unchanged as a
deliberate jank preservation.

## The boss contract

Stated once, assumed by every block:

- **One telegraph per boss.** The boss announces its big move on its
  turn ("gathering power" register) and fires it on its next turn, so
  the fuse is one full ATB cycle. **Breaking the boss during the fuse
  cancels the move**; the charge does not resume when the boss
  recovers, and has to be started again. Everything else in the fight
  stays vanilla AI.
- **After a cancel the trigger is earned again.** Whatever armed the fuse
  starts over: a hit count from zero, a clock from zero, a rotation from
  its first turn. A boss whose HP alone arms it announces again on its
  first turn back and needs the full fuse again.
- **An announced move always fires** unless a break cancels it or the
  boss dies (owner, 2026-11-23: "don't announce anything that won't
  happen. however, okay to make a roll before that to determine whether
  or not to do the whole sequence"). Nothing rolls between the announce
  and the move. Where a move is not to come every time, the roll is made
  before the announce, on the turn that arms the fuse.
- **A break releases whatever the broken body holds** (owner,
  2026-11-23: "definitely breaking a tentacle should free a party
  member. if possible same for enemies that swallow party members
  temporarily"). Not built yet; the Tentacles' Seize is the first case
  ([bosses-wor.md](bosses-wor.md) block 1).
- **While a fuse is lit the HUD says so**: a yellow **!** before the
  boss's shield emblem, from the announce until the move fires or a
  break cancels it.
- **What is built** (#561, `ot6_fuse.asm`, DESIGN.md "Break system"): the
  cancel, the trigger's reset, the **!**, and the rule that hits on a
  Broken boss wind no fuse, on the one fuse vanilla wrote for a World of
  Balance boss, AtmaWeapon's (block 21, `battle_atmaweapon`), and on
  three in the World of Ruin. The authored telegraphs of blocks 1-5
  (the Whelk to TunnelArmr, wt/v051-tg-wob1), 7-10 (Telstar, the
  GhostTrain, Rizopas, Kefka at Narshe, wt/v051-tg-wob2) and 11-16
  (Dadaluma, the opera Ultros, Ifrit and Shiva, Number 024, Number 128,
  the Cranes, wt/v052-tg-wob2) are built too (each block's **Built**
  line). Every other **Telegraph** line below is
  design text: the scripts do not announce those moves yet. The fuse
  block's idiom for writing them, and its worked example, are in
  `ot6_fuse.asm` and `battle_fuse`.
- **Not every boss races** (owner, 2026-11-24: "not every move needs to
  be announced. not every boss even needs an announced attack, but where
  it fits the feel"). A telegraph is a **race** when the party the story
  brings can break the boss between the announce and the move, and a
  **warning** when it cannot, or when a party that chips from the open
  breaks the boss before it ever announces, so the line mostly says
  "brace" (Defend, heal, Runic). Measured on each block's lab:

  | # | Boss | Fuse | Race or warning |
  |---|---|---|---|
  | 1 | Whelk | 2 turns | Race: unboosted beams from the announce break the head in the fuse, 5 of 5 keys; the prize is the head kept out |
  | 2 | Marshal | 1 turn | Race (while a Lobo stands): broken in the fuse 3 of 3 chipping from the open, 2 of 3 from the announce |
  | 3 | Vargas | 1 turn | Warning: the trio holds no key while an Ipooh stands, and SABIN's Pummel ends the fight |
  | 4 | Ultros ① | 1 turn | Warning: TERRA's sword breaks him before his first announce (the six-class line: 6 party actions, scenario_hub.log; the four-class lab's 3 of 3 agrees); a race only for a party that banks to the announce |
  | 5 | TunnelArmr | 1 turn | Warning: LOCKE's boosted Fight breaks it before it announces (3 of 3); at the announce the answer is CELES's Runic |
  | 6 | Kefka ×2 (camp) | — | None: no big move, no gauge (block 6) |
  | 7 | Telstar | 1 turn | Race at 3 shields: SHADOW's unboosted Fights chip from the announce and SABIN's Pummel breaks, 8 of 10 keys (at 4 it lost 10 of 10; one pip on SHADOW's Fight wins 8 of 10 at 4) |
  | 8 | GhostTrain | 2 turns | Race: won on 3 of 4 keys from the announce |
  | 9 | Rizopas | 1 turn | Race: won on 2 of 3 keys from the announce |
  | 10 | Kefka (Narshe) | 1 turn | Race (four-class lab, when EDGAR's pike keyed him too): won on 3 of 4 keys from the announce; under six classes EDGAR keys him only by Bio Blaster and the line's squad broke him 12 actions in; not re-raced |

  Ultros and TunnelArmr stay at one turn: their warnings fit the feel,
  and a longer fuse would only lengthen fights the party usually ends
  first.
- **Bosses get no exemption from breaks.** Turn loss and ×2 apply to
  AtmaWeapon the same way they apply to a Lobo. Shields are the only
  value tuned per boss.
- **The Vargas triple-tutorial stays verbatim.** Menu-Blitz made the
  in-battle input tutorial mechanically unnecessary, but it stays for
  its charm. No cleanup pass removes it.

- **Scripts run regardless of break state.** Vargas's Pummel finish,
  Chupon's arrival and Sneeze, and the espers interrupting Ultros on the
  bridge all fire whether or not the boss is Broken. The gauge changes
  combat, not scripted story events. (Kefka's camp flees used to head
  this list. They have no state to override, because they have no
  monster and no gauge; see 6.) The ones that ride on a counter do so
  through the exception below.
- **A Broken enemy loses its turns and its counterattacks, but not its
  story.** Whelk's shell does not counter during the window, which
  matches Octopath. `Ot6MayAct` (`ot6_break.asm`) asks the same question
  at turn time that `Ot6Gate` asks at queue time, inside `CheckRetal`,
  and `Ot6BrokenTurn` asks it at `ExecAction` for a turn queued before
  the break (#291).
  The exception is keyed on the counter script's own commands, never on
  the monster (#314, widened by #329). Every AI command is one of:
  *story* (`dlg`, `battle_event`, `change_battle`, `end_battle`,
  `recruit_gau`, `end_veldt`, and the monster entry/exit op:
  `restore_monsters`, `show_monsters`, `hide_monsters`, `kill_monsters`,
  `boss_death`); *attack* (an attack, `set_target`, `cmd`, `use_item`,
  `throw_item`); *scene* (battle and monster variables and switches, the
  monster animations, timers, invincibility, targetability, `fill_atb`,
  `set_status`/`clr_status`); or *control* (conditions, `wait`,
  `end_if`, `end`). A counter block (the span vanilla's conditionmiss
  skips, end_if to end_if) that holds a story command still runs while
  its monster is Broken: its story, scene and control commands in order,
  each attack skipped where it stands. Every other block of that counter
  is skipped whole, the way vanilla skips a Stopped monster's counter
  commands (`Ot6RetalStory`, `Ot6AIBlockStory`, `Ot6AISkip`). Scene
  commands never make a block a story block on their own: a switch a
  story block sets drives the scene; one an attack block sets tracks the
  attacks, and waits for the break to end with them. A dying monster's
  counter (`if_self_dead`, or 0 HP) runs in full, Broken or not, as
  before. So Phunbaba's `if_hit / if_hp<15360` block ends the battle
  without its two BabaBreaths when he is Broken, and the Lete Ultros
  says his fire line without the Special behind it.
  The monster's TURN is not covered: a Broken monster takes no turns,
  so a story beat on a turn script (Whelk's shell dialogue, the Air
  Force's, Tunnel Armor's opening event) plays when the break ends.
  Measured (build/attempts/wt/story-while-broken/): Ultros ④'s Chupon
  entry plays on cue while Ultros is Broken (`battle_ultros4.lua`; on
  main's ROM it came only as his dying counter); the Lete Ultros's fire
  line (`dlg $0b`) plays when Terra's Fire hits him Broken, and the
  Special behind it does not follow (`battle_ultros1.lua`; on main's
  ROM, no line until he died); a Broken Ifrit's or Shiva's story-less
  counter blocks are skipped whole (`battle_brokendeath.lua`); Ultros
  ③'s Relm interrupt runs while Broken on both ROMs, as #314 made it.
  Two of the route's story counters did not come due while their
  monster was Broken: Vargas's (below), and the South Figaro Merchant's,
  whose Steal-for-clothes beat needs him alive and Broken, but LOCKE's
  dagger hit that breaks him takes his last 92-93 HP (the unbroken hit
  before it did 26-27), seven draws of seven
  (fix/merchant-sweep-fix-s*.log, failed/merchant-*).
  Two things shorten or sidestep a break around these beats: Haste on
  the monster (Umaro's Green Cherry block, Doom's phase change) runs its
  break timer about 24% faster (the #329 review's reading, not measured
  here), and a body swap (the opera Ultros's slot
  moves, Chadarnook's) brings in an unbroken body.
- **A nameplate with no shields is itself information.** Scripted
  set-pieces (Tritoch, Guardian, the Imperial Camp Kefka) draw no
  gauge at all, which tells the player the fight is scripted.

Numbers below are shields only; boss HP falls under the global
−25–35% cut. Elemental rows keep vanilla's bits
wherever they exist ✦ (weapon-classes.md); every *added* element or
class is justified by the coverage rule: the party the story gives you
must be able to chip. Before Zozo the proofs rely on kits.md's learn
schedules; from Zozo on, magicite makes fire/ice/bolt roughly
party-independent, and the proofs rely on both.

Recurring bosses rely on the codex. Ultros keeps one weakness row
through all four fights, revealed at the Lete River and revealed from
then on; only his shield count grows.

## The curve at a glance

| # | Boss | Where | Shields |
|---|---|---|---|
| 1 | Whelk (head) | Narshe intro | 4 |
| 2 | Marshal | Narshe escape | 4 (Lobos 3) |
| 3 | Vargas | Mt. Kolts | 5 (Ipoohs 2) |
| 4 | Ultros ① | Lete River | 5 |
| 5 | TunnelArmor | Locke scenario | 5 |
| 6 | Kefka ×2 | Imperial Camp (Sabin) | — (no gauge) |
| 7 | Telstar | Imperial Camp (Sabin) | 3 (Dobermans 2) |
| 8 | GhostTrain | Phantom Train (Sabin) | 4 |
| 9 | Rizopas | Baren Falls (Sabin) | 4 (Piranhas 1) |
| 10 | Kefka | Narshe defense | 6 |
| 11 | Dadaluma | Zozo | 6 (Iron Fists 2) |
| 12 | Ultros ② | Opera house | 6 |
| 13 | Ifrit & Shiva | Magitek factory | 6 + 6 |
| 14 | Number 024 | Magitek factory | 7 |
| 15 | Number 128 | minecart escape | 7 (blades 3 each) |
| 16 | Left & Right Cranes | airship escape | 6 + 6 |
| 17 | Ultros ③ | Esper Mountain (battle 125's only call site is the Relm-joining scene) | 7 |
| 18 | FlameEater | Thamasa | 7 (Balloons 1) |
| 19 | Ultros ④ + Chupon | FC approach | 7 + 4 |
| 20 | AirForce | FC approach | 8 (pods 3/3, Speck 1) |
| 21 | AtmaWeapon | Floating Continent | 11 |
| 22 | Nerapa | FC escape | 5 |

The curve runs 4 shields at the start and 6 at the scenario capstones,
then a 6–7 plateau through act two where difficulty comes from parts
and from fighting several bodies at once (the Cranes are 12 shields of
monster across two gauges) rather than from a larger single count.
After that come one 8, an 11 at the peak, and a deliberate 5 at the
end under a timer. No single WoB gauge exceeds 11; 12 and above is
reserved for the WoR ([bosses-wor.md](bosses-wor.md)).

---

## Narshe intro

### 1. Whelk — the mines

Party: Terra between Vicks and Wedge, all Magitek (fire/bolt/ice
beams; Terra adds TekMissile and Bio Blast).

| part | shields | weak |
|---|---|---|
| Head | 4 | fire + ranged |
| Shell | — (no gauge) | — |

- **Telegraph:** the head announces that it is drawing into its shell
  → two turns later it draws in. Break the head during the fuse to cancel
  the hide: it stays out, Broken, for the whole window. (This block's
  first design had the shell charge a Mega Volt; the lead's ruling below
  replaced it.)
- **Built** (wt/v051-tg-wob1, `battle_whelk`; the lead's ruling,
  2026-11-24: the opening teaches and does not punish, and "not every move
  needs to be announced"). The telegraph is the fight's own rhythm, the
  head drawing into its shell, with no new damage. Where vanilla's shell
  drew the head in on its clock, it now calls the head in (a battle
  switch); the head says **"It draws in!"** and glows, glows again on its
  next turn, and on the turn after that draws in itself, vanilla's "Gruuu"
  and fade. **The rhythm is not vanilla's:** the call comes on vanilla's
  clock (the shell's ten-count), but the hide lands about two of the
  head's turns after it; the shell's clock, restarted at the call, has
  run its count by then, so the shell shows the head again on its next
  turn and the head stays in for less than one shell interval; and it
  hides about half as often as vanilla's head. A break of the head in between cancels the hide, and every
  break of the head sets a hold (`Ot6FuseTbl`'s `OT6_FUSE_HOLD`) that keeps
  the shell from calling it in until the head's first turn back: the
  Broken head stays out for its whole window, which is the reward. The
  shell's Mega Volt counter and its show turns are vanilla's; on its other
  turns the head attacks as vanilla's did (an earlier cut of this branch
  had the head cast an announced Mega Volt, about half each member's HP).
  **A two-turn fuse, 4 shields kept** (the lab, `build/attempts/wt/v051-tg-wob1/lab2/`,
  keys $FD $11 $39 $51 $69): a party that Defends until the line and then
  beams the head unboosted (one Fire Beam a member, one shield each) breaks
  it in the fuse 5 of 5, 4 actions after the line ("BROKEN IN THE FUSE (4
  action(s) from the announce; cancel fired)"); with a one-turn fuse the
  window held 3 actions against 4 shields. A party that dumps a banked
  boost kills the head in the fuse instead (5 of 5), and one that beams
  from the open breaks it in the fuse or before the line, 4 beams in (3
  draws). The line's own fight (`arvis_wake`) takes no new damage.
- **Break story:** the guards warn you away from the shell, and Fire
  Beam is the probe the game points you at. Three beams and a
  TekMissile break the game's first boss within two rounds, which
  teaches the whole sequence: probe, chip, break, dump.
- **Jank ✦:** hitting the shell triggers the MegaVolt counter, exactly
  as in vanilla, and it is still lethal at level 1. Under the proposed
  ruling the counter is disabled only during the head's break window.

### Tritoch — (scene, not a fight)

The frozen esper one-shots the Magitek trio. It is a cutscene that
uses the battle screen. No shields and no gauge are drawn, which is
the first time the game shows that an empty HUD means a scripted
scene.

## Narshe escape

### 2. Marshal — the moogle defense

Party: Locke, Mog, and ten moogles in three squads.

**Shields:** 4 · **Weak:** poison + dagger, spear. Lobos: 3 · fire +
dagger, spear.

- **Telegraph:** the Marshal levels his blade and calls the Lobos in
  → next turn he and both Lobos attack one target. Break him and the
  Lobos attack without coordination.
- **Built** (wt/v051-tg-wob1, `battle_marshal`). His rotation's second
  turn arms it; the next says **"Strike as one!"** and glows; the turn after it fills
  both Lobos' ATB gauges and he strikes twice. Not as written: a monster's
  script cannot aim another monster's attack, so the Lobos act at once on
  their own targets rather than on his. His rotation's last two turns
  (Net/Net/Battle, Battle) no longer come. The line plays only while a
  Lobo stands (the lead, 2026-11-24): alone, his turns are vanilla's alone
  block, `attack BATTLE, SPECIAL, SPECIAL` (it had no Net), which now also
  drops a fuse armed but not yet announced; one already announced fires. Lab (build/attempts/wt/v051-tg-wob1/lab/, LOCKE's squad at full
  HP after gen_moogle's waves, keys $A0/$E0/$30): chipping from the open
  (Fights at the bank) breaks him in the fuse 3 of 3, 7-8 actions from the
  open, 2-3 after the announce (one of those breaks landed after his fire
  turn was read: no cancel, and the Broken turn purged the strike);
  Defending to the announce and then Fighting breaks him in the fuse 2 of
  3 (2 actions) and leaves 1 shield the third time (4 actions), and the
  strike fires. Fuse: one turn; shields kept at 4. **Damage** (`build/attempts/wt/v051-tg-wob1/s6/damage.txt`: the boss suite's unbroken case with the party's HP at each member's own maximum, the line's levels and gear, the party Defending): his
  two Battles and the Lobos' attacks that landed with them took 0 of
  LOCKE's 122, 25 of 146 (17%), 28 of 108 (25%) and 22 of 102 (21%) of
  the moogles'; Defend halves physical damage, so a member who acts
  takes about twice that.
- **Break story:** twelve bodies generate BP quickly and damage
  slowly. Moogle spears chip him steadily, and the break protects
  whichever squad he is attacking. Spear is the featured class,
  matching the pikes Mog, Kupek and Kurin carry (`char_prop.asm`; the
  other moogles swing flails, a claw, blades, a brush and returning arcs).
  LOCKE's dirk is a Dagger, the row's other class, so the thief the
  player controls holds a key on the boss and on the Lobos too.
- **Jank:** the three-squad control scheme stays byte-for-byte,
  including vanilla's unusual moogle gear; losing all squads is still
  a game over.
- **How the line plays it:** the squad that will face the Marshal sits
  out the waves. Four of the six marches pass (15,19) and the other two
  (20,20), so Mog's squad, the strongest and the last to face him, holds
  (15,19) for four waves, Kushu's holds (20,20) for two, and Locke's
  waits beside Terra, meeting only a guard that beat a squad. The waves
  are fought with the fight driver, not blind presses, so Mog's squad
  comes through four of them with Mog standing for his strip (#143).
  With two waves a squad, Locke's squad met the Marshal with 122 to 401
  of its 478 HP, most draws around 26–30%, and an empty bag (it holds a
  couple of heals at most, and nothing in the event restores HP). The
  less HP it brought, the more often it lost: the cause is the squad's
  HP on the whole, not one threshold. At full HP the first squad won on
  every draw the lab dealt (wt/v044-moogle).

## Mt. Kolts

### 3. Vargas (+ two Ipoohs)

Party: Terra, Locke, Edgar. Sabin joins at the midpoint with Pummel
and, at vanilla level 6, AuraBolt, so the fight is planned assuming
holy chip is available.

MEASURED, in `battle_vargas.lua` off the tier-2 fixtures: he seeds
**5/5 with class row $04 (Blunt; bludgeoning through v0.50)**, the Ipoohs 2/2 Sword-weak (slash then),
and his weak byte reads **$28 — poison|holy**, the holy bit being
`Ot6ElemAddTbl`'s add on top of vanilla's poison. Sabin's arrival is
structural rather than descriptive: he gets **no turns at all** until
Vargas's own reaction script fires `battle_event $07/$08`
(hp ≤ 10880, then ≤ 10368, `ai_script.asm:4392-4404`) and knocks the
trio out of the fight. He joins at level 9 on this route, so AuraBolt
is present as planned. AuraBolt takes a shield and reveals holy,
Pummel takes another and reveals the Blunt class, and the same
Pummel kills him.

Edgar's BioBlaster is measured now as well, and the measurement
corrects the break story below. The poison chip works as planned: item
`$a4` resolves to attack `$7d`, element `$08`, and it takes a shield
and reveals poison, while the same party's plain weapon swings hit
Vargas without moving the gauge (`battle_vargas.lua`'s control).
**BioBlaster cannot reach him while an Ipooh is alive.** Its item
targeting byte is `$6a`, which is group-targeting with `$01 MANUAL`
clear, so the cursor cannot be moved off the group, and
`key_target_2`'s INIT_GROUP branch (`btlgfx_main.asm @7875`) aims at
monster group A and falls through to group B only when A is empty.
This formation has the Ipoohs in A and Vargas alone in B. Measured
over one fight: seven consecutive BioBlasters went into the Ipoohs'
group ($06, then $04 once the first died) before the eighth reached
him ($01), about 9500 frames in.

**Shields:** 5 · **Weak:** poison, holy + blunt. Ipoohs: 2 ·
fire + sword.

- **Telegraph:** he drops into his wind stance → **Gale Cut** hits
  the party. This is the same move the script later uses to knock the
  trio out of the fight; it is his only named move, and it is used as
  the fuse.
- **Built** (wt/v051-tg-wob1, `battle_vargas` 9). His rotation is now
  Battle, Battle (arms it), **"Feel the wind!"** with a glow, Gale Cut;
  vanilla's was Battle, Gale Cut, Battle. The fuse block is the script's
  first, so his SABIN lines and his 50-count double Battle wait for the
  move (at most two turns). The Pummel finish and the `battle_event`
  $07/$08 counters are unchanged. Lab (build/attempts/wt/v051-tg-wob1/lab/, the lib's fight driver, keys
  $C0/$D4): the line comes on his 3rd turn, Gale Cut on his 4th, with 3
  party actions between and no break: in phase one the trio holds no key
  while an Ipooh stands (BioBlaster's group targeting, above), so the race
  is not winnable there, by the design's own rule that he cannot be broken
  before SABIN joins. In phase two SABIN alone takes one shield an AuraBolt
  against 5, and his first Pummel ends the fight. The telegraph here warns
  (Defend, heal) rather than races. Fuse: one turn; shields kept at 5.
  **Damage** (`build/attempts/wt/v051-tg-wob1/s6/damage.txt`: the boss suite's unbroken case with the party's HP at each member's own maximum, the line's levels and gear, the party Defending): Gale Cut took 48 of EDGAR's 280 (17%), 49 of LOCKE's
  279 (17%) and 52 of TERRA's 241 (21%).
- **Break story:** phase one gives the trio very little chip.
  BioBlaster's poison is their only key and takes Vargas down 1 while
  the script has the fight going against you. Sabin then arrives with his MetalKnuckle (a knuckle, Blunt on every Fight since v0.51), Pummel ×2 for Blunt and AuraBolt for holy, which supply the chip; Vargas cannot be broken before Sabin joins. **The escorts
  block the key** (measured, above): the spray goes to the Ipoohs'
  target group until both are down, so phase one is clear the adds
  first, then spend the tool. That ordering was not planned, and it
  needs no extra work.
- **Jank ✦: the Blitz requirement stays.** Doom Fist's Condemned
  countdown on Sabin and the Pummel-input finish are unchanged; he
  dies to the script rather than to HP. Breaking him does not end the
  fight. What the ×2 window buys is free turns to enter the Blitz
  input while he is Broken. Killing him by damage instead (11,600 HP
  at level 10) is still possible.
- **Pummel ends it, Broken or not (#314).** MEASURED before the fix
  (seed shifts 0/20/40, on main's ROM and on wt/battle-fixes-023's):
  a Pummel landing on a Broken Vargas, or the Pummel whose second hit
  broke him (from 2 shields), queued no counter (`Ot6MayAct`
  refused it) and the fight went on; only the first Pummel after he
  recovered ended it, 3,079-4,137 frames after the first one. It
  never softlocked while SABIN kept Pummeling, but a SABIN who stopped
  was worn down to a game over. Unbroken, Pummel ends it
  1,084-1,332 frames after it lands, and now Broken does too
  (1,030-1,191). The finish block is exempt from the break (above),
  and `battle_vargas.lua` 7 asserts both Broken cases end to one
  Pummel. The generator's route never reached the Broken case:
  `gen_vargas` plays no weakness hit before SABIN's first Pummel,
  which lands on 5 shields and takes him to 3 (measured, six runs).
- **His other story on the route comes before any break (#329).** The
  counter blocks that bring SABIN in (`battle_event $07`, under 10,880
  HP) and the one after it (`battle_event $08`, under 10,368) would play
  while Vargas is Broken, but the route's play reaches both lines
  unbroken. In phase two, under the four classes (through v0.50), `$08`
  was not reachable Broken: SABIN's MetalKnuckle was a claw (slashing) and
  chipped nothing on Vargas's bludgeoning row. **Under six classes the
  MetalKnuckle is a knuckle, Blunt, and chips his Blunt row**, so SABIN's Fights now take shields
  in phase two, and whether `$08` can play Broken has not been measured
  since. The measurements that follow are v0.50's:
  AuraBolt's one chip cost 393 and 406 HP (10,850 ->
  10,457 and 10,879 -> 10,473) against the ~480 above the line, and
  Pummel ends the fight. MEASURED: SABIN's Fights took him from 10,850
  to 10,230 HP with his shields at 4 throughout, and `$08` ran unbroken
  (build/attempts/wt/story-while-broken/failed/vargas8-*;
  fix/vargas-fix-s0-regress.log). In phase one the only key is
  BioBlaster; `battle_vargas`'s first BioBlaster turn took him from
  11,582 to 11,327 (the party's weapon hits in that stretch included),
  and 720 HP lie above the `$07` line. Whether five BioBlasters with
  the others holding back can break him above it was not measured.

## Lete River

### 4. Ultros ①

Party: Terra, Edgar, Sabin, Banon (Health is a free party heal; his
death is a game over).

**Shields:** 5 · **Weak:** fire, bolt + sword, ranged — the row
he keeps all game. TERRA's sword, TERRA's Fire and EDGAR's AutoCrossbow key him (EDGAR's own Mithril Blade would too; the route's EDGAR carries MOG's Mithril Pike, a Spear, which does not); SABIN's knuckles and BANON's rod are Blunt and key nothing, so they hit and heal (opening.md 9).

- **Telegraph:** two tentacles rise → **Tentacle** hits Banon. Break
  during the fuse to cancel it.
- **Built** (wt/v051-tg-wob1, `battle_ultros1`). His rotation's second
  turn arms it; the next says **"Squirm, BANON!"** and glows; the turn
  after it is vanilla's third turn, "Y…you frighten me!" and Tentacle on
  BANON. The fuse block is the script's first, so his opening line and his
  two one-time lines (Terra's, Sabin's) wait for the move. Lab (build/attempts/wt/v051-tg-wob1/lab/, keys
  $A4/$B8/$D0): chipping from the open (TERRA's Fire, the others' Fights,
  at the bank) breaks him before any announce, 3 of 3, in 8 actions (about
  f2,440); his first announce comes on his 7th turn (the suite, idle party),
  after the three line turns. Defending to the announce without BANON's
  Health wiped the party, 3 of 3, before it came (the lab's policy, not
  play). The suite measures the window: one of his turns, 802 frames
  (f9,052 to f9,854). Fuse: one turn; shields kept at 5. Not measured
  for damage: his move is vanilla's Tentacle on BANON, unchanged.
- **Break story:** Banon's Health makes stalling survivable, so the
  fight teaches banking: probe fire (he has a scripted line about
  seafood), hold at 2–3 BP, break on the fuse, and dump with boosted
  Fight. This is the first fight where failing to cancel the fuse can
  lose the game. AutoCrossbow does heavy damage to him; that is fine,
  because this fight is meant to be easy.
- **Jank ✦:** Ink inflicts Dark, and Dark does nothing because of the
  evade bug. It stays doing nothing. The scripted line on fire fires
  every time, and he flees at the end of the fight.

## The split — three scenarios, three proofs

This is the stress test for the coverage rule (weapon-classes.md).
Terra and Banon's segment through the caves has no boss; that party is
tested at the Narshe defense instead. Per-party notes below.

### 5. TunnelArmor — South Figaro escape (Locke + Celes)

**Shields:** 5 · **Weak:** bolt, water, ice + dagger. (Decoded, not
recalled: `$104` weak = **bolt|water** — `monster_prop.dat` +25 reads
`$84` — and +23/+24 are both `$00`, so it absorbs nothing and nulls
nothing.) Bolt *and* water are
vanilla's machine bits and this party can produce neither — the only
water in the WoB this early is a thrown Water Edge, Throw is Shadow's
✦ and he is two scenarios away, and Locke's list is verbs, not
elements (kits.md) — so both bits are codex trivia today, payoff
later. Ice is the add: Celes's join spell needs a socket, and "frozen
coolant lines" reads fine on a digging machine. **The ice row is
authored** (`Ot6ElemAddTbl` `$0104` + `$02`, weak byte resolves
`$84` → `$86`); the 5 shields and the class (Dagger; piercing through v0.50) were already in
`Ot6ShieldTbl`. Inert to the suite until a Locke+Celes fixture reaches
`battle 67` (event_main.asm:21005).

- **Telegraph:** the drill spools down and the tunnel shakes → its
  quake (Magnitude8 — audit list). **Runic absorbs it.**
- **Built** (wt/v051-tg-wob1, `battle_tunnelarmr`). Not as written:
  Magnitude8 has no Runic flag (`magic_prop_en.dat` $BC byte 3 = $22,
  bit 3 clear) and its power is 100, so the move is TunnelArmr's own
  TekLaser ($B5, Runic-absorbable) on both. Its first turn is the Runic
  tutorial (`battle_event $10`, unchanged); its rotation's second turn
  arms the fuse; the next says **"Laser charges!"** and glows; the turn
  after it is TekLaser on the party. Lab (build/attempts/wt/v051-tg-wob1/lab/, keys $5E/$6E/$8E): chipping
  from the open breaks it before any announce, 3 of 3, in 2 actions
  (LOCKE's boosted Genji Fight takes 4); its announce comes on its 4th
  turn, and the window holds about 2 party actions: Defending to the
  announce and then chipping left 4-5 shields, 3 of 3 (CELES's boosted
  Ice took one and 882 HP; LOCKE's turn did not fall in the window), and
  the move fired. Fuse: one turn; shields kept at 5. **Damage** (`build/attempts/wt/v051-tg-wob1/s6/damage.txt`: the boss suite's unbroken case with the party's HP at each member's own maximum, the line's levels and gear, the party Defending):
  TekLaser took 204 of CELES's 310 (65%) and none of LOCKE's 314 on that
  draw (it was queued on both: a miss or his gear). **Runic, played**
  (`battle_tunnelarmr`'s fifth case): CELES's Runic, confirmed after the
  line, took the cast aimed at both whole ("1 absorb(s) after the move
  (targets $03)"), and neither member lost HP to it. Her stance lasts
  until she queues her next action (vanilla's clear), so an unboosted
  Runic whose next turn comes before the laser lapses: in the first cut
  of the case it did, and the laser took 225 from LOCKE. A boosted Runic
  stands through one more of her turns (`Ot6RunicHold`); the case uses
  boost 1. The fight has
  two valid answers, Runic the quake (vanilla's tutorial) or break the
  machine first (ours), and doing both is best, since Runic converts
  the telegraph into +1 BP ✦ (kits.md), so the boss's biggest move
  pays for the break.
- **Break story:** Mug and daggers chip with Dagger, Ice chips as an
  element, and 5 shields across two bodies puts the break at about the
  first fuse. It is a small fight that uses every part of the system.
  The coverage rule here rests on the added Ice and the Dagger
  class, because both vanilla element bits are unreachable for this
  duo. Narrowing either one leaves the fight with no way to chip at
  all.

### 6–7. Imperial Camp (Sabin, with Shadow drifting in and out)

**Kefka ×2: no gauge, because there is no monster in this fight.**
(Decoded, not recalled.) Both scenes run `battle 56, IMP_CAMP`
(event_main.asm :40683 and :40743). Group 56 in
`event_battle_group.dat` points both its slots at **formation 504**,
and formation 504 in `battle_monsters.dat` (+`$1d88`) is `00 00 ff ff
ff ff ff ff 00 00 00 00 00 00 3f`: the present mask is **`$00`**, and
all six id slots are `$ff` with byte 14 = `$3f` setting every high
bit, which gives six copies of `$1ff`, vanilla's empty-slot sentinel
(battle_main.asm:7720). Nothing is loaded. What `battle_prop.dat`
(+`$7e0`) enables instead is **character AI script `$04`**,
`kefka_imp_camp_1`, whose slot 0 is
`CHAR_PROP::KEFKA_1|CHAR_AI_FLAG_ENEMY_CHAR` (char_ai.asm:163). The
event has already set a party slot to him on the way in:
`char_prop VICKS, KEFKA_1` (event_main.asm:40675; CHAR::VICKS = 15,
CHAR_PROP::KEFKA_1 = `$29`).

The Kefka fought at the camp is therefore a **character entity** using
Kefka's name, sprite and palette, flipped to the enemy side and
running monster AI script `$016f`. He has character HP, which is why
the event can revive and refill him between rounds with `clr_status
VICKS, DEAD` / `max_hp VICKS` (event_main.asm:40739). No `MonsterProp`
record is read for him, so there is no weak byte, no absorb byte and
no shield seed. `Ot6SeedShields` is reached only from the monster/rage
load and returns immediately for character entity offsets in any case
(`ff6/src/battle/ot6_break.asm:6-9`).

A gauge cannot be implemented here: there is no monster entity to
attach a species row to, and gauging a character entity would need a
new per-formation hook rather than a table row.

That matches the intent: both scenes are scripted and should read as
scripted. He takes a few hits and flees, twice, with the waiter line
unchanged, and the empty HUD says so from the start, which is the same
rule as Tritoch one scenario earlier.

**What the contract means here: nothing to build** (wt/v051-tg-wob2). His
script (`AIScript::_367`) is `attack BATTLE` on his turns and, on the
first hit, `battle_event $1d / end_battle`: the fight lasts until the
party lands one blow. There is no big move to announce, no turn on which
a fuse could burn, and no gauge to break it with, so a telegraph would
only delay the scene. The script and both scenes are unchanged.

**Telstar:** 3 shields · bolt, water + dagger, blunt (Dobermans 2 · fire +
dagger, blunt). SABIN's fists and Pummel key both; SHADOW's blade, when
he is in, keys both too, so the pair races the call with two hands, where
SABIN's alone could not break four shields in time (2026-11-24). (Decoded, not recalled: `$044` weak = **bolt|water** —
`monster_prop.dat` +25 reads `$84`, the same byte TunnelArmor and the whole
AirForce assembly carry — and `$01a` Doberman weak = **fire**.)
- **Telegraph:** its antenna sparks and it radios for backup → a
  wave arrives next turn. Break to stop the call. This is the
  first break that prevents a summon; the same use returns at
  FlameEater.
- **Built (wt/v051-tg-wob2, `battle_telstar`).** Each of vanilla's three
  calls (its monster timer at 25, 80 and 200, once each) is announced on
  the turn its clock comes due: "It radios in!" (dialogue `$98`) and a
  glow; the wave comes on Telstar's next turn with vanilla's own "Alarm's
  ringing!" and sound. A break between them cancels the call and
  restarts the clock (`Ot6FuseTbl`, three rows `$0044`), so that wave is
  earned again from zero. The three blocks are vanilla's in reverse
  order, 25 first, so an earlier call is always spent before a later one
  announces (no earlier block can take a lit call's turn); vanilla
  differed only when two calls came due on one turn. The wave is
  formation 61's slots 2-5, species `$001` (Soldier), not Dobermans as
  this block said: read from `battle_monsters.dat` and logged by the suite
  (`[telstar] the slots its calls fill hold $001 $001 $001 $001`).
- **Shields: 3, with SHADOW's blade a key (#566, 2026-11-24).** The
  telegraph branch measured that with bludgeoning alone the pair could
  not win the race at 4: SABIN's Pummel takes two chips and Telstar's
  counter answers every Blitz that lands on it unbroken with Megazerk
  (vanilla's `if_cmd BLITZ`), so after one Pummel nothing the pair held
  chipped (4 of 4 keys lost the race at 4, `build/attempts/wt/v051-tg-wob2/
  lab/`), and it cut the gauge to 2. Under six classes the row is
  Dagger|Blunt: SHADOW's Fight chips one shield a swing and draws no
  Megazerk (the counter answers Blitzes), so the pair races with two
  hands. Measured from the camp (`build/attempts/wt/v051-six-classes/
  labs/telstar/`, 10 distinct keys): the party Defends until "It radios
  in!", then SHADOW Fights unboosted and SABIN Pummels once the gauge
  reads 2. At 4 shields only two party actions fit in the one-turn fuse
  and the race was lost on 10 of 10 keys; at 3 it is won on 8 of 10 (a
  two-turn fuse also won 8 of 10, but its `wait` does not fit beside the
  wave's sound), so the row takes 3. With one pip on SHADOW's Fight the
  pair wins 8 of 10 at 4 too, and with his whole bank he breaks it alone.
  battle_telstar plays the cancel with the gauge and all six keys staged
  (a mechanism test).
- **Break story:** SHADOW's blade chips while SABIN waits, and SABIN's
  Pummel is the breaking blow (it must be: a Pummel on an unbroken
  Telstar draws Megazerk).
- **Jank:** the treasure chest that turns out to be a monster is
  unchanged.

### 8. GhostTrain — the Phantom Train (Sabin, Cyan, Shadow)

**Shields:** 4 (6 until #400) · **HP:** 2600 (vanilla 1900, #400) · **Weak:** fire, bolt, holy + blunt ·
**absorbs poison.** (Decoded, not recalled: `$106` weak =
**fire|bolt|holy** — `monster_prop.dat` +25 reads `$25` — and +23
reads **`$08`, poison absorbed**; +24 is `$00`.)

- **Tuning (#400, 2026-10-06):** four shields over 2600 HP (vanilla 1900,
  six shields), so that once the party spends its pips (#366) the train is
  Broken while alive in about half its fights or more, and Cyan's Cleave
  gets its target.  By
  distinct key, the train is Broken with HP left in 31 and 24 of 45 keys on
  two snapshot sets (2 of 45 at six shields), deaths rise 10 -> 11 and
  23 -> 28, and one key per set turns into an attrition wipe
  (build/attempts/wt/v026-route2/e400/by_key.txt).  Not a hard fight for
  players; no further tuning is planned.  Since #410 the route's fighter
  Suplexes first, so its own fight now ends on that Suplex.
- **Telegraph:** the whistle sounds down the corridor → **Evil
  Toot**, a party-wide random status attack. Break the boiler before
  the move lands; Acid Rain between fuses keeps pressure on your
  healing.
- **Built (wt/v051-tg-wob2, `battle_ghosttrain`).** Vanilla tooted on the
  turn its count of ordinary turns (battle variable 3) reached 2, with two
  of the party standing. Those conditions, the count read one turn
  earlier, now arm the fuse (monster switch 0) on a turn the train spends
  on its ordinary attacks; the next turn announces it, "Whistle blows!"
  (dialogue `$99`) and a glow, in the turn vanilla's toot took; a second
  glowing turn follows; Evil Toot comes on the turn after. The party
  count is tested where the fuse is armed, not on the fuse block, so a
  member felled between the line and the toot cannot drop an announced
  move. A break in the fuse clears switch 0 and the count (`Ot6FuseTbl`
  row `$0106`): an ordinary turn has to come round again. Its opening
  turn (Battle, Special or Evil Toot, once, unannounced: vanilla's), Acid
  Rain's clock and the Suplex are unchanged.
- **Fuse two turns (the lab).** At one turn a party that chipped from the
  announce (SABIN's Pummel, the others Fight) lost 4 of 4 keys, the toot
  coming 2-4 party actions after the line (`lab-b-TRAIN-CHIP-*`). From a
  full gauge that party breaks it in 5-6 party actions, two of the
  train's turns (`lab-c-TRAIN-CHIPFULL-*`, keys `$80 $A0 $E0`/437; on
  `$C0` the train fell first). At two turns the same race was won on 3 of
  4 keys, 5-6 party actions after the line, and lost on `$C0`
  (`lab-c-TRAIN-CHIP-*`). The line's own fighter Suplexes the train dead
  with one shield off before any announce, as before
  (`[b68] WON: 1 of 4 shields off`). **Damage** (`build/attempts/wt/v051-tg-wob1/s6/damage.txt`: the boss suite's unbroken case with the party's HP at each member's own maximum, the line's levels and gear, the party Defending): Evil Toot is a
  status move: 7 of 363, 4 of 282 and 0 of 358 HP.
- **Break story:** the keys are the abilities the scenario gives you.
  AuraBolt is holy chip at range, Pummel ×2 chips repeatedly, and
  Shadow's elemental skeans reach two of the three element bits rather
  than one: Fire Skean is fire (item `$ab` → spell `$51`) and Bolt
  Edge is bolt (`$ad` → `$53`). Cyan cannot chip his own scenario's
  boss, which is deliberate: the Phantom Train farewell is where
  **Cleave** unlocks (kits.md), and Cleave requires a Broken target,
  so the train is the first target it can be used on. Another
  character has to break it for him. The ghost merchant in the
  train's car B (shop record 85) sells **Fire Skean**, giving Shadow
  a chip key in this scenario; fire rather than bolt because fire
  also opens Specter, the monster-in-a-box below.
- **Jank ✦: Suplex kills it outright (#410).** A landed Suplex ($5f) on
  the train deals its whole current HP (Ot6SuplexTrain, ot6_break.asm):
  the classic joke, made true, on this species only (battle_suplextrain,
  with battle_suplex as the control).  The undead
  flag stays as well, so one Fenix Down kills the train instantly
  regardless of break state. Vanilla shortcuts take precedence over
  the break system.
- **Jank ✦: poison heals the Phantom Train.** This is vanilla
  behaviour and it stays. Edgar's Bio Blaster is poison: the
  Throw/Tools table maps item `$a4` to spell `$7d`
  (battle_main.asm:6577) and that spell's element byte is `$08`. If
  Bio Blaster is used on this boss, vanilla's absorb branch flips the
  damage sign and skips past the weakness branch that contains the
  shield chip (battle_main.asm:1850, chip at :1872), so the hit heals
  the train and chips nothing. Edgar is on Terra's segment and this
  party carries no poison, so the problem is latent rather than live.
- **Poison fails on this train twice, on the boss and on the chest.**
  `$0156` Specter, the monster-in-a-box in this same scenario (map
  153, treasure 114 → event battle group 34 → formation 476), also
  absorbs poison (+$2ad7 = `$08`), and is fire|holy weak in vanilla
  (+$2ad9 = `$21`). Specter gets **no authored row**: vanilla's fire
  and holy are both usable keys here (Shadow's Fire Skean and Sabin's
  AuraBolt, the same two the break story above uses).
- **Siegfried is a duel, not a boss (v0.45).** The boastful swordsman
  whose trap waits in the compartment car (`$131`, battle 109, map 153's
  (5,25); the line walks past it) has 100 HP and no vanilla weakness. A
  boss's four shields would mean the break lands on a corpse, and any real
  blow kills him. His row is one shield that any weapon breaks, a
  braggart's gauge. His opening flurry of eight blows is the fight, and
  SHADOW's Interceptor often ends it with a counter that carries no weapon
  class. break-coverage-wob.md section 17 has the row;
  `battle_breakwob_siegfried` plays it from the graph's capture.

### 9. Rizopas, after the Piranha school — Baren Falls (Sabin + Cyan)

Party: SABIN and CYAN, jumping the falls from the top of map 156
(SHADOW has left at the overlook); battle 18 from the jump event
(`event_main.asm:66481`), which calls `_cacfbd` first — `max_hp` and
`max_mp` on every slot — so the party enters at **full HP and MP**
whatever the walk cost it.

**Shields:** 4 (Piranhas 1) · **Weak:** bolt + katana, blunt ·
**Absorbs:** water.

Decoded, not recalled (`monster_prop.dat` row `$155`, 32 bytes at
`+$2AA0`, ROM `$CF2AA0`; `tools/tests/lab_rizopas_template.lua` (deleted in 8d350a73; last version at 182bc361) header):
`28 0e 64 00 00 6e af 03 07 03 27 00 00 00 00 00 0d e0 00 cd e6 09 00 80
00 04 ff 00 00 01 00 20` — speed 40, attack 14, hit 100, evade 0,
m.block 0, defense 110, m.def 175, m.pow 3, **HP 775**, MP 39, level 13;
absorb `$80` water; null `$00`; weak `$04` bolt. Byte 31 `$20` is the
special attack (`LoadRageProp` → `$322d`; `battle_main.asm:8443-8480`):
bits 6 and 7 clear, `$20 − $20 = +0` to the multiplier — a plain
physical hit under its own animation. Bytes 28-31 `00 01 00 20`: the
status 3&4 word `$0001` is the flying flag (Float). `Ot6ShieldTbl`
(`ot6_hud.asm:1601`): 4 shields, class-weak `KATANA|BLUNT` (`SLASH|BLUDG` through v0.50); no
`Ot6ElemAddTbl` row; `Ot6HpMulTbl` ships `$10` (1×), so 775 is the HP the
fight sees. Piranha `$154`: HP 10, level 9, attack 13, weak bolt, 1 shield
`KATANA|BLUNT`.

**AI** (`ai_script.asm:7328-7337`), one entry of each triple at random:
*Battle/Special/Mega Volt · Battle/Ice/Ice · wait · El Nino/Battle/Battle*,
looping; `boss_death` on death. `magic_prop_en.dat`: **Mega Volt** `$B8`
bolt, power 20, hit 150; **Ice** `$01` power 22; **El Nino** `$6F` water,
**power 61**, targeting `$7E` (the whole party), hit byte 0 — unmissable.
The Piranha script (`:7290-7326`) restores two or three of the school on
every death until the battle timer passes 60, then the last death hides
the school and surfaces MONSTER_6 from the water: **the wave is a
fixed-length tax**, ~4,450-5,500 frames in every attempt logged
(`t_surface` in the `[result]` lines), whatever the party does.

**What the party carries** (`lab_rizopas_bake.lua` (deleted in 8d350a73; last version at 182bc361), read at the falls):
CYAN L14, 358 HP, Ashura `$2B` (a katana: Katana), Heavy Shld, Leather Hat,
LeatherArmor, no relics, SwdTech `$07` = Dispatch/Retort/Slash. SABIN
L14, 363 HP, MetalKnuckle `$53` (a knuckle: Blunt on Fight, as Pummel and Suplex
are; every claw slashed through v0.50), Buckler, Leather Hat, Kung Fu Suit, Star Pendant
and Jewel Ring, Blitz `$07` = Pummel/AuraBolt/Suplex. Bag: **Tonic 91,
Potion 2, Fenix Down 15**. Both weapons match the row, so every Fight
hit that lands chips — but each of the two carries one weapon, and half
of a boosted Fight's swings are empty-hand passes that whiff (#235): a
1-BP Fight is 4 swings and **2** landed hits = 2 chips, 2 BP 3, 3 BP 4
(`M.fightHits`; the swing count is `M.fightPasses`). BP caps at 5 and
regenerates one per unboosted turn (`ot6_boost.asm:141`).

**The burst, measured.** Rizopas's spells land on the whole party as
often as on one (`[act] … atk=$B8 tgt=$0003` and `tgt=$0001` both occur),
for 40-90 a head; it acts about twice per party round (its actions in
`care_i0.log` at `t=5062` and `t=5300`, the party's at `5535` and `5691`).
**El Nino is the killer: `[hp] t=5583 entity 0 284 -> 55 (-229)` and
`entity 1 221 -> 0 (-221)` in one action (`control_i55.log`, seed
`$74`); `t=5314 … 326 -> 82 (-244)`, `238 -> 0 (-238)` (`care_i50.log`,
seed `$64`).** Two ordinary hits and then El Nino is ~360 HP to each of
two 358/363-HP members: that is the 650-frame double kill of #162
(the probe's `$EE` reading is store seed `$E4`; `$BE` at battle-up sits
ten draws past InitBattle's store in every run here). Nothing about it
is a telegraph the AI script honours; the doc's earlier "the falls swell
backward" line is not in the script and is removed.

**Built: the nearest telegraph that keeps the contract** (wt/v051-tg-wob2,
`battle_rizopas`). Vanilla's El Nino was a one-in-three pick on turn B,
never announced. The one-in-three is now rolled on turn A (`if_roll 85`,
85 in 256), a turn before anything is announced, and only arms the fuse
(monster switch 0): turn A's own attacks are vanilla's either way. Armed,
the next turn announces it in place of turn B, "Waters swell!" (dialogue
`$9A`) and a glow, and El Nino comes on the turn after. Unarmed, turn B is
its Battle. A break between the line and the wave cancels it
(`Ot6FuseTbl` row `$0155`): the rotation starts again at turn A, roll and
all. Monster switch 1 stands for vanilla's `wait` between the turns, so
the roll can sit on a block's head. El Nino's rate is about the same
(vanilla one a six turns; now one a seven, the announce taking a turn),
and it never comes unannounced. Lab (one-turn fuse, 4 shields, keys `$4E
$72 $82 $9E`/79): with the bank the line carries out of the school, a
full gauge breaks in one Fight (`lab-b-RIZOPAS-CHIPFULL-*`), and the
line's own fighter broke him in 1-2 actions before any announce; a pair
that Defends from the surfacing and Fights from the announce broke him
in the fuse on 2 of the 3 keys that announced (1-2 actions after the
line), and lost the third to El Nino 1 action after it
(`lab-b-RIZOPAS-CHIP-*`). Kept at one turn. **Damage** (`build/attempts/wt/v051-tg-wob1/s6/damage.txt`: the boss suite's unbroken case with the party's HP at each member's own maximum, the line's levels and gear, the party Defending): El Nino
took 232 of SABIN's 363 (63%) and 243 of CYAN's 358 (67%).

**Break story, measured.** The row is honest and the party's Fight is
the key: SABIN's and CYAN's swings both chip. A 1-BP Fight from either is
3 chips; the second member's next swing breaks; the surplus swings of a
2- or 3-BP Fight land broken. `bankboss_i25.log` (seed `$D0`): CYAN
Fight at 5 BP → `[hit] t=5083 rizopas hp=552 (-146) sh=1 (-2)`, `t=5084
hp=0 (-552) sh=0 (-1) brk=16` — **dead in one action, 645 frames after
surfacing**. Pummel (2 Blunt hits) chips less than a boosted Fight
and costs Blitz MP; Dispatch is one Katana hit and is not in the driver.

**Policy × seed** (`tools/tests/rizopaslab_batch.sh` (deleted in 8d350a73; last version at 338328ee), aggregate by
`rizopaslab_aggregate.py` (deleted in 8d350a73; last version at 2e305abc), per-run digests by `rizopaslab_actions.py` (deleted in 8d350a73; last version at 432944a7);
the fixture is `falls_prejump.mss` from `lab_rizopas_bake.lua` (deleted in 8d350a73), the
generator's own walk; seeds are what InitBattle drew, `$be` at the store;
the seed knob is a stand on the jump row plus an exact-frame delay at
"Jump?" — the walk quantizes a plain idle, so twelve idles drew nine
seeds and the tenth, `$E4`, took the prompt knob). Every attempt is
retained under `build/rizopaslab/`. The policies: **control** is
gen_sabin_falls' own fighter, verbatim (boost whatever BP it holds on
every Fight, self-heal under 60% with a Potion when 60+ HP is missing,
else a Tonic, no revive); the rest are the lib fight driver — **care**
(boosted Fight, Potions to whoever is under 40% or inside a round of
death, Fenix Down for the fallen), **bank2** (chip unboosted until 2 BP,
then spend; care as `care`), **allin** (boosted Fight, no items, no
care), **bankboss** (Fight the school unboosted, bank to the cap, unload
when Rizopas surfaces; care as `care`), **pummel** (SABIN's Pummel at
boost, CYAN Fights; care as `care`). None reads hidden HP or future RNG;
`bankboss` reads the same surfacing the screen shows.

| policy | distinct seeds | won | lost | Fenix/win | Potion/win | deaths (all) | mean t (won) | mean boss phase (won) |
|---|---|---|---|---|---|---|---|---|
| control | 10 | 9 | 1 | 0.0 | 1.0 | 1 + the `$E4` wipe | 7460 | 1740 |
| care | 10 | 9 | 1 | 0.0 | 0.0 | 5 | 6814 | 1109 |
| bank2 | 10 | 5 | 5 | 0.0 | 0.0 | 9 | 7184 | 1580 |
| allin | 10 | 10 | 0 | 0.0 | 0.0 | 1 | 6863 | 1185 |
| **bankboss** | 10 | **10** | 0 | 0.0 | 0.1 | **0** | 6897 | **860** |
| pummel | 10 | 10 | 0 | 0.0 | 0.0 | 0 | 7962 | 1414 |

`t` is battle-up to teardown (the ~4,500-frame school included); the boss
phase is surfacing to death. Per seed (boss-phase frames on a win; `L`
lost; Fx/Po/To items spent by the engine's own Item commands; `d`
deaths; the `$E4` column is #162's `$EE`):

| seed | control | care | bank2 | allin | bankboss | pummel |
|---|---|---|---|---|---|---|
| `$14` | 1467 1Po | 1388 | **L** wiped 1Fx 2Po 27To 1d | 1388 | 953 | 1579 |
| `$28` | 1508 1Po | 1233 | 1334 | 1233 | 961 | 1148 |
| `$34` | 1346 1Po | 779 | **L** wiped 2Fx 3d | 779 | 636 | 1107 |
| `$64` | 2351 2Po | **L** wiped 4Fx 2Po 1To 5d | **L** wiped 1Fx 2d | 1877 1d | 649 | 1663 |
| `$74` | 3406 2Po 1d | 1284 | 1512 | 1284 | 648 | 1666 |
| `$80` | 1590 | 1094 | 1834 | 1094 | 940 | 1491 |
| `$B0` | 755 | 803 | **L** wiped 1Fx 1d | 803 | 649 | 1629 |
| `$C4` | 1569 1Po | 1301 | 1988 | 1301 | 1696 1Po | 1151 |
| `$D0` | 1669 1Po | 774 | **L** wiped 1Fx 2d | 774 | 645 | 1110 |
| `$E4` | **L** wiped (both to El Nino at t=5561, 1,096 frames after surfacing) | 1321 | 1231 | 1321 | 824 | 1599 |

Three more seeds the prompt knob drew for the control only, while
hunting `$E4` and the gen path's `$18`: `$C0` won 1539 1Po, `$E0` won
3224 2Po 1d, `$08` won 4768 2Po 5To — the last two are the
qualification's shape (a member down, the other soloing on the bag).
`$18` itself, the seed the generator's own path drew in this tree
(`lab_rizopas_bake.lua` (deleted in 8d350a73): `store seed=$18`), was not landed by any prompt
tried (35, 36 and 37 drew `$14`, 38 and 39 `$28` — the knob steps over
phase 6); the
qualification run's actual seed is unrecorded (the gen never logged
`$be`) and the walk has drifted since (CYAN reached the jump at 338/358
then, 307/358 now), so "the qualification's seed" is not a reproducible
target — the spread above brackets it with `$14` (one phase off) and
the gen-path measurement stands in the bake log.

`allin` and `care` are frame-identical on nine of ten seeds: the care
options never engaged before Rizopas died. Where they did (`$64`), care
lost and no-care won. The old fighter's Potion-a-win is spent on itself
under 60%; its two long wins (`$74`, `$E0`) and its `$08` are a member
dead to El Nino and a 3,000-5,000-frame solo on the bag's two Potions and
then Tonics — the qualification's attempt 1, which ran out of Potions and
wiped.

**Recommendation.** What a person does here: fight the school with
plain, unboosted Fights (a Piranha has 10 HP; a boosted swing on one is
thrown away), arrive at Rizopas with the bank full, and unload — a 3-BP
Fight from either member is seven swings of a class he is weak to (CYAN's Katana, SABIN's Blunt), the break lands in
the first two and the rest land ×4, and Rizopas, broken, loses the turn
that would have been El Nino. Ten seeds, ten wins, no deaths, no Fenix,
one Potion, the boss dead a mean 860 frames after surfacing and 824 on
the seed that wiped the old fighter. That is what `gen_sabin_falls.lua`
now plays (the lib driver with `bank = 99`, flipped to 0 when slot 5
surfaces). Pummel is the second-best verb (two Blunt chips a use,
~100 a hit, ten clean wins) and is what a person who opens the Blitz menu
gets; Dispatch is not in the driver (an unknown-menu TODO). The driver
rules above are for lib/ot6.lua's owner; with them in place `care` is
the same policy as `bankboss` with a safety net, and without them the
safety net is the thing that wipes.

**The driver finding (lib/ot6.lua, not edited here).** `care_i50.log`:
after El Nino left SABIN at 82 and CYAN dead with Rizopas at **553 HP,
1 shield**, the driver spent the next eleven turns on care — `revive
entity 1 with Fenix Down` four times, CYAN standing up at 44 HP and
dying to the next Battle (`[hp] t=6500 entity 1 44 -> 0 (-44)`, again at
`9561`, `10974`), two Potions and a Tonic between — and refused SABIN's
attack every time with `no press: entity 0 (82/363) is inside one round
of death (244) -- caring first`, though the care it then chose was not
for entity 0 and a 1-BP Fight (3 chips on 1 shield, the surplus broken)
was the fight's end. Four Fenix Downs and a wipe against a boss one
action from dead; the control won the same seed by never reviving.
`bank2_i30.log` (seed `$14`) is the same shape with the other veto: El
Nino left the pair at 22/33 with Rizopas at **551 HP, 1 shield**; SABIN,
holding 3 BP, was refused with `no press: Fight at 3 BP would chip 7 of
1 slot 5 but the window's damage 288 (e0:72x4) is short of its 551 HP --
caring` — the window prices one *action's* measured damage ×4, not the
**seven swings** a 3-BP Fight throws, six of them on a broken target
(`bankboss` measured 552-629 from one such Fight) — and the driver then
spent both Potions on the same member (the second `+91` on a 272/363
SABIN while CYAN stood at 33), and, the Potions gone, **27 Tonics** of
+50 against 40-90 hits over 15,000 frames to a wipe. The exact rules:
**(a) the one-round-of-death veto on the press must not fire when the
press's window covers the monster's HP** (the press *is* the care);
**(b) the press window must count the pressing actor's swings, 1 + 2·BP,
with the swings past the break at ×4**, not one prior action ×4; **(c) a
raise is not care when the raised member's HP would be at or under the
monster's smallest measured hit** (44 vs 41-45 here); **(d) a Tonic
whose +50 is under the round's measured cost is not care either** —
attack instead (owner: strong single heals, never a treadmill of weak
ones). With 15 Fenix and 2 Potions in the bag, (c) and (d) are what
stand between this party and the Fenix signal.

## The reunion — Narshe defense

### 10. Kefka and the raiding party

Party: all seven, three squads on the snowfield.

**Shields:** 6 · **Weak:** poison, fire + sword, dagger.

**Authored: the whole row is an add.** `$014a`'s vanilla weak byte
(`monster_prop.dat` +$2959) is `$00`, so the arc's final boss shipped
with no weakness of any kind, and `Ot6ElemAddTbl` carries `$09`
(poison|fire) outright. +$2957/+$2958 are both `$00`, so nothing is
absorbed or nulled. The 6 shields and the two classes were already in
`Ot6ShieldTbl`. Kefka's own row is deliberately broad (poison|fire +
sword, dagger): a squad with a sword (CELES; TERRA and EDGAR while they hold one), a dagger (LOCKE; TERRA's Mithril Knife, which the line's dress puts back in her hand for him) or GAU's fangs in it, or one that brings fire or poison (TERRA's Fire, EDGAR's Bio Blaster), can break him. His waves (Trooper, HeavyArmor, Rider) carry their own rows
(see "The imperial soldier line" below). The katana is not on his row:
a squad of CYAN and SABIN alone keys him with SABIN's claw (a Mithril Claw is a Dagger) or his Fire Dance (level 15), and with GAU it has his fangs (opening.md 10).

- **Telegraph:** he giggles and frost crawls the ground → **Ice**
  across the engaged squad (Ice 2 in this block's first design; the
  lead's ruling, below).
- **Built (wt/v051-tg-wob2, `battle_kefka`).** His clock arms it (the
  monster timer at 40, about 1,300 frames) on one of his turns that is
  vanilla's opening Battle; "Frost creeps!" (dialogue `$9B`) and a glow
  announce it on his next turn; Ice on every member of the squad
  (`set_target ALL_CHARS`) follows on the turn after (Ice 2 until the
  lead's ruling, below). A break between
  cancels it and restarts his clock (`Ot6FuseTbl` row `$014A`). His
  four-turn rotation, its own one-in-three Ice 2 on one member, his
  parting line and his flight are vanilla's; after the cast his rotation
  starts again from its first turn, as after Telstar's calls. CELES's
  Runic takes the cast whole, as TunnelArmor's quake teaches. Lab (one
  turn, 6 shields, TERRA, EDGAR and CELES, keys `$27 $47 $67 $87`/505): a
  squad that Fights with its keys from the open breaks him in 3 party
  actions, one of his turns (`lab-b-KEFKA-CHIPFULL-*`); one that Defends
  until the line (banking the pips) and then Fights broke him in the fuse
  on 3 of 4 keys, 2-3 actions after the line, and on `$87` took the cast
  2 actions after it (`lab-b-KEFKA-CHIP-*`). The line's own fighter
  breaks him in 6-7 actions, about 1,800 frames in, before any announce
  (`lab-a-KEFKA-LINE-*`). **The cast is Ice (tier 1), not Ice 2** (the
  lead, 2026-11-24): Ice on the squad took 79 of TERRA's 306 (25%), 80 of
  CELES's 310 (25%) and none of EDGAR's 315 on that draw
  (`build/attempts/wt/v051-tg-wob1/lab2/dmg_kefka2.log`); his rolled Ice 2 on
  one member stays vanilla's. Before that change, **Damage** (`build/attempts/wt/v051-tg-wob1/s6/damage.txt`: the boss suite's unbroken case with the party's HP at each member's own maximum, the line's levels and gear, the party Defending): Ice 2 on the squad took 221 of
  TERRA's 306 (72%), 225 of CELES's 310 (72%) and none of EDGAR's 315
  on that draw. **Runic, played** (`battle_kefka`'s fifth case): CELES's
  Runic, confirmed after the line and boosted, took the cast aimed at all
  three whole ("1 absorb(s) after the move (targets $07)"); no member
  lost HP to it. Unboosted, it lapses when she queues her next action
  (block 5).
- **Break story:** the waves drain resources before Kefka himself, so
  the fight teaches banking across a sequence of fights: earn BP on
  the waves, arrive holding 4–5 BP, and break him on the first fuse.
  The broad row means most squads you route to him can break him (one
  needs a sword, a dagger, fire or poison), and the squad layer makes the
  routing the player's decision.
- **Jank:** the strategy layer is untouched, and his spell list stays
  low-tier, matching where he is in the story.

## The imperial soldier line — every party gets a key

These are not bosses. They are documented here because this is where
the weakness data lives.

**The fix: a weapon class, chosen per the forced party.** Poison is no
longer special; it is one Edgar-reachable key among several. Each
species gets an `Ot6ShieldTbl` row whose class *every party that fights
it* can reach:

| species | id | shields · class | forced party → its key | thematic |
|---|---|---|---|---|
| Soldier | `$0001` | 2 · blunt\|katana | Cyan duel (katana) · Sabin+Shadow camp `b44` (Sabin's fists: blunt) | cut, or a blow |
| Templar | `$0002` | 3 · dagger\|blunt (+bolt) | Sabin+Shadow camp `b44` (Sabin's fists; Shadow's blade in hand; Bolt Edge) | elite plate; blade in the gap, fists dent it, metal conducts |
| Leader | `$014E` | 3 · katana | Cyan SOLO Doma duel `b46` | the samurai out-cuts the commander |
| Grunt | `$014F` | 2 · blunt\|katana | Doma defense `b13` (Cyan's katana + Sabin's knuckles and Blitz) | two heroes overwhelm a footman |
| Cadet | `$0176` | 3 · blunt\|katana | Doma defense `b14` (same two) | ditto, a bigger body |
| Officer | `$0175` | 2 · dagger | Locke SOLO S.Figaro `b9` | the thief's dagger finds the seam |
| Trooper | `$0065` | 2 · sword\|dagger\|katana | Narshe waves — a squad with a sword, a dagger or a katana | sword for Terra/Celes/Edgar's blade, dagger for Locke and for Gau's fangs, katana for Cyan; Sabin's knuckles hold none, his claw (Dagger since 2026-11-24) does |
| Rider | `$003F` | 3 · dagger\|katana | Narshe waves — a squad with a dagger or a katana | Locke's dagger, Gau's fangs, Sabin's claw, Cyan's katana; Terra's Fire and Edgar's poison (fire still breaks it on the train) |
| HeavyArmor | `$009F` | 3 · dagger | Locke SOLO `b11` (dagger) + Narshe wave (a dagger, or bolt, water or poison) | heavy plate; a blade at the seams |

Shields track the early-war stretch (2 basic infantry, 3 for the elite /
heavier / duel bodies). **Class chips ignore absorb/null**, so
HeavyArmor's vanilla water-absorb and everyone's stray element bits
never interfere with the break; the class is always a legal key.

**The palette.** Armored soldiers take a **dagger** (pierce through
v0.50), on the reading that a blade finds the gaps in armor, with **bolt** where a
party can cast it: the machines (M-TekArmor, HeavyArmor) are natively
bolt-weak in vanilla, and Templar gains bolt (`$04`) here for Shadow's
Bolt Edge at the camp. The Cyan solo duel is **katana**, so it plays as
a swordfight. Sabin's fights add **blunt**. The rows are varied rather
than uniform: the key is whichever character is fighting the enemy.

**Element table.** M-TekArmor and HeavyArmor keep their poison adds, on
top of vanilla bolt, because a party that fights them can cast poison
(Shadow's bolt at the camp; Edgar at the Narshe waves). Leader and
Grunt carry no poison add: poison is unreachable in both of their
forced fights (a solo duel; a Cyan+Sabin defense), and the class row
already answers them. Templar's row is `$00`/`$00` at +$17/+$18 (no
absorb, no null).

**Trooper and Rider.** The Trooper takes sword\|dagger\|katana and the
Rider dagger\|katana: vanilla poison stays the Edgar squad's key, and
the class is the key of any squad with a dagger or a katana in it (or,
on the Trooper, a sword). Formation 88 (Trooper+HeavyArmor, `battle 23`,
event_main.asm:108505) is breakable by those squads, not by Edgar alone;
the HeavyArmor takes only the dagger, so a squad without LOCKE or GAU
breaks it with bolt, water or poison. A squad of SABIN and GAU alone
holds Blunt and a Dagger (GAU's fangs): the fangs key every wave body,
SABIN's knuckles none.

**M-TekArmor.** It is breakable by the party that fights it (Shadow's
Bolt Edge, or the Magitek bolt beam at the camp); it carries the bolt
half of the palette in vanilla.

**The school seed.** The tier-2 dialog ($0276) teaches: armor turns a
careless blow aside, but every plate has a seam, and no two are the
same, so bring the weapon that fits. A precise blade is an answer
(a dagger, a sword, a katana), and there are several tools rather than one. The class
rows are the mechanic; `school.lua` pins the dialog bytes, so text and
data fail separately if either drifts.

**The one place coverage overrode the theme.** The palette's default for
armored soldiers is dagger+bolt, but the Doma courtyard defense party
(Sabin's knuckles + Cyan's katana) can field neither a point nor bolt. Grunt and
Cadet therefore take blunt\|katana rather than the default, using the
rule that Sabin's fights are Blunt.

## The Serpent Trench — three aquatics, three keys

Sabin + Cyan + Gau ride the trench (`battle 19`/`20`/`21`, UNDERWATER,
event_main.asm:21194+; the party is placed together at the ride's entry
`_ca8ae3`). The classes they can field are **blunt** (Sabin's knuckles,
fists and Blitz), **katana** (Cyan's katana and SwdTech) and **dagger**
(Gau's fangs: his bare hand; Sabin's claws once he owns a pair, since
2026-11-24), and nothing else. Every trench
aquatic was a formula species whose vanilla element the party cannot
reach: Anguiform is bolt-only and the party has no bolt, and
Actaneon/Aspik are fire-weak but Sabin's Fire Dance needs level 15. All
three **absorb water**, so an element add would heal them. Class rows
are the answer, and the three keys are split across the three creatures
to match the party, one per member: SABIN's Blunt, CYAN's Katana and
GAU's fangs (a Dagger):

| species | id | shields · class | thematic |
|---|---|---|---|
| Anguiform | `$003A` | 2 · katana | a slippery eel, cut by Cyan's blade |
| Actaneon | `$005E` | 2 · blunt | a shelled crustacean, cracked by Sabin's fists |
| Aspik | `$0059` | 2 · dagger | a constrictor, bitten through by Gau's fangs |

Vanilla bits are kept (dead or level-locked for this party, live for a
later party that carries the element); class chips ignore the
water-absorb.

## Break coverage — the free-roam floor

- **The free-roam tail has a floor.** `Ot6SeedShields`' `@formula`
  fallback seeds a per-species **floor class**: `sta $3e9c,y` reads
  `OT6_FLOOR_CLASS[species]`, a build-time table generated by
  `ff6/tools/gen_break_floor.py` from the monster names, so every
  un-authored body is breakable by some weapon class. The palette
  follows the authored rows: armored/mechanical/dragon/insect →
  **dagger, spear or ranged**, brute/ooze/golem/monk → **blunt or ranged**, and
  beasts/humanoids/casters → **sword or katana** (the remainder); the
  generator deals each family's species to its classes in turn, in
  species-id order. Authored
  `Ot6ShieldTbl` rows still take precedence (the `@hit` path overwrites
  the mask); the floor only fills the gap. `battle_breakfloor` is the
  regression test, and it asserts that all 384 species carry a
  breakable class.
- **Tentacle_2 / Tentacle_3 (`$013D`/`$013E`) are out of WoB scope.**
  They belong to the World-of-Ruin Figaro engine room, which is
  outside this document's World-of-Balance scope. The floor gives them
  a class like any other species, but their fight is in the WoR.

### 11. Dadaluma

Party: any four of the seven.

**Shields:** 6 (Iron Fists 2) · **Weak:** poison + dagger,
blunt. Iron Fists: blunt, ranged. A pick of four holds one of his
classes when LOCKE (dagger), GAU (fangs) or SABIN (knuckles and Blitz)
is in it. The one pick without them, TERRA, CELES, CYAN and EDGAR, keys
him with EDGAR's Bio Blaster (poison) and the Iron Fists with his
AutoCrossbow (opening.md 11).

- **Telegraph:** he crouches to jump → **Jump**, which is
  untargetable and lands on one character. Break him during the
  crouch and he does not leave the ground.
- **Break story:** he calls in Iron Fists at half health and uses his
  own potions. Chip through the adds with AoE Ranged
  (AutoCrossbow), bank BP, and break him during the crouch.
- **Jank:** the mid-fight item use stays, and it suits Zozo. Jump's
  airborne phase stays as vanilla has it.

## Opera → Vector → the factory

### 12. Ultros ② — the opera stage

Party: Locke + three (Celes is mid-aria).

**Shields:** 6 · **Weak:** the row ✦ (fire, bolt, sword,
ranged — revealed at the Lete, still revealed; the codex working
as designed).

- **Telegraph:** the same tentacle wind-up as before. He is a
  recurring boss with a remembered weakness row and a higher shield
  count each time.
- **Break story:** there is no Banon to protect this time, and the
  tentacle targets whoever is most costly to lose. One more shield
  than the Lete River fight, and no free healer.
- **Jank:** the battle takes place on the opera stage and the scene
  continues around it.

### 13. Ifrit & Shiva — Magitek Research Facility

Party: Locke, Celes + two.

| part | shields | weak |
|---|---|---|
| Ifrit | 6 | ice + dagger |
| Shiva | 6 | fire + sword |

- This is vanilla's tag fight: they swap in and out. Each keeps its
  own gauge across swaps, and a swapped-out sibling's break timer
  keeps running; it is not frozen behind the `$3aa0.0` presence gate.
- **A Broken sibling takes no turns.** `Ot6Gate` (`ot6_break.asm`,
  consulted where a full gauge queues a turn) refuses to queue a broken
  monster's turn, and `Ot6BrokenTurn` (`ot6_break.asm`, at the head of
  `ExecAction`) consumes one that was already on its way when the break
  landed, before its AI script runs: no script, no command, the gauge
  reset the way vanilla resets it for a removed action (#291).
  `Ot6MayAct` refuses a Broken sibling's counterattacks. This fight is
  where a queued turn meets a break about once a run, and
  `battle_brokendeath` asserts no script runs on it.

- **Telegraph:** Ifrit inhales and the air shimmers → **Fire 2**;
  Shiva does the same with **Ice 2**. Whichever one is on the field
  runs its own fuse.
- **Break story:** this is the first fight that requires reading
  absorbs, because fire heals Ifrit. Celes can chip both siblings by
  herself, with Ice into Ifrit and her sword into Shiva. The fight
  still ends by script rather than by killing them; the Ramuh script
  stays.

### 14. Number 024 — the specimen guard

Party: Locke, Celes + two.

**Shields:** 7 · **Weak:** *rotating* — WallChange re-rolls the
elemental wall every few turns and re-hides the element row when it
does. Classes fixed: sword + dagger, the handhold while the
wall spins.

- **Telegraph:** the wall changes to a color → the matching tier-2
  spell (Fire 2 / Ice 2 / Bolt 2). The fuse also tells you the current
  wall, and therefore the current absorb, so probe with a different
  element.
- **Break story:** this boss works against the codex. Physical chip is
  steady, magic requires reading the current wall, and a break keeps
  the current wall revealed until the next WallChange re-rolls it. It
  is the only enemy in the WoB whose element row does not stay
  revealed once found.
- **Jank:** WallChange stays random, including back-to-back rolls of
  the same wall.

### 15. Number 128 — the minecart

Party: **three**, on rails. Celes is separated partway through the
Facility, so this fight and the Crane escape run one character short of
the party that walked in.

| part | shields | weak |
|---|---|---|
| body | 7 | bolt, water + dagger |
| Left/Right blades | 3 each | bolt + dagger, katana |

The blades take a dagger or a katana (#566, 2026-11-24: Dagger added so
that a member the minecart forces holds a key; with Katana alone only CYAN
really held one): LOCKE's dagger, SABIN's claw, CYAN's blade, or a curved
sword (LOCKE's or EDGAR's Flame Sabre). The route's three (LOCKE, EDGAR,
SABIN, `level-curve.md`) break them with LOCKE's dagger and SABIN's claw,
and with Bolt, their vanilla weakness (Ramuh is held by then); the body
takes LOCKE's dagger, SABIN's claw and Bolt.

- Blades regenerate a few turns after dying (vanilla ✦), and regrown
  blades return at full shields. Their weakness row stays revealed.
- **Telegraph:** In `AIScript::_267` (`ff6/src/battle/ai_script.asm:4725-4746`;
  the label index is the monster id, 267 = `$010B`), Gale Cut sits behind
  `if_num_monsters 1`: the body Hastes itself and then runs Gale Cut,
  Atomic Ray, Blaster and Shock Wave **once both blades are dead**. While
  a blade is alive it runs `BATTLE, BATTLE, ICE` and `BATTLE, SPECIAL,
  NET`. Killing the blades is what turns the sweep on, so a party that
  leaves them standing keeps the body on its mild script.
- **Break story:** this is the first battle after Zozo gives you four
  espers, and a Ramuh bearer casting Bolt into the body is the first
  use of the sub-job system (magicite.md's storm-lancer).
- **No revival on the ride.** Six fights back to back with no field
  access between them, and nothing that raises the dead in the routed
  bag: no Fenix Down, no shop past the checkpoint, no owned esper
  granting Life in the WoB. A death on the ride is permanent; Fenix
  Down ($F0) is stocked by 25 item shops (`shop_prop.dat`), several of
  them on the road to Vector, so the preparation is the player's.
- **The body regenerates.** Body HP rises mid-fight with no heal cast
  logged; the mechanism and rate are unconfirmed, but it sets a floor
  on how fast a party must chip to make progress.
- **Jank:** regrowth timing stays vanilla; the minecart shooter
  around it stays byte-for-byte.

### 16. Left & Right Cranes — the Blackjack's rigging

Party: the factory four (Setzer is flying the airship).

| part | shields | weak |
|---|---|---|
| Left Crane ($10D) | 6 | water + dagger |
| Right Crane ($10E) | 6 | bolt, water + dagger |

(Decoded from `monster_prop.dat` +25, not recalled: `$10D` weak = water, absorbs bolt.
`$10E` weak = bolt|water, absorbs fire. Vanilla's shared weakness is water.)

- **The Cranes' vanilla charge is element-driven rather than a
  fuse.** Read from `ai_script.asm`: both counters are in the COUNTER
  half of the script, gated on `if_element FIRE` / `if_element
  LIGHTNING`. The level rises only when the player hits a Crane with
  the element it absorbs, and the results are **Fire 3** and **Giga
  Volt**. There is a separate timer move (`if_battle_timer 60` →
  Magnitude8). This is not the one-ATB-cycle fuse the boss contract
  defines above.
- **Break story:** this is the WoB's effective 12-shield fight: two
  live gauges with two fuses on independent clocks. Focus one Crane
  and the other's charge lands. Use the wrong element and you heal its
  sibling, since vanilla's absorbs are unchanged. The elemental key
  here is **water**, the shared vanilla weakness, plus **bolt on the
  Right Crane only**; the espers the factory has just paid out are the
  wrong answer.
- **Jank:** they climb the hull mid-battle, and the wrong-element
  heal stays as the 1994 original shipped it.

## Esper Mountain

### 17. Ultros ③ — the rope bridge

Party: Terra + three.

**Shields:** 7 · **Weak:** the row ✦, third verse.

- **Telegraph:** tentacles again. By this point the player knows the
  pattern and breaks him without probing.
- **Break story:** the espers interrupt and end the fight on the
  script's schedule, regardless of break state. Breaking him before
  they arrive has no mechanical effect.
- **Jank:** the bridge drops him and not the party, as in vanilla.

## Thamasa

### 18. FlameEater — the burning house

Party: Terra, Locke, Strago (Shadow keeps the dog outside).

**Shields:** 7 (Balloons 1 each) · **Weak:** ice, water + dagger.
Balloons: 1 · ice, water.

(Decoded, not recalled: in vanilla `$116` weak = **ice only** —
`monster_prop.dat` +25 reads `$02` — with +24 `$6c` nulling
bolt|poison|holy|earth and +23 `$01` **absorbing fire**. Water above is
an OT6 add, not vanilla. `$0de` Balloon weak = `$82` = ice|water.)

- **Telegraph:** it absorbs the room's fire and turns white →
  **Fireball** across the party. Break during the fuse to cancel it.
- **Break story:** this is Strago's first fight. **Analyze** reads the
  full row on turn one, and Aqua Breath is both the water chip *and*
  the AoE that clears the Balloons before they chain Exploder. The
  adds need AoE and the boss needs focused damage, so the fight
  alternates between the two. Terra's Fire heals the boss; this is the
  first mainline boss where the party's usual attack is the wrong
  one.
- **Jank:** Balloons still Exploder for their full HP, and the house
  burns down on the script's schedule regardless of how the fight
  goes.

## The Floating Continent approach

### 19. Ultros ④ + Chupon — the airship deck

Party: your chosen three (Shadow is waiting on the continent).

| part | shields | weak |
|---|---|---|
| Ultros ④ | 7 | fire, bolt, **poison** + sword, ranged — the row, one bit *added* |
| Chupon | 4 | ice, water + ranged |

(Decoded, not recalled: Ultros ④ is a **different species** from the
first three — `$168`, where the Lete/opera/gate fights are `$12c`/`$12d`/
`$12e` — and vanilla did not give it the same row. `monster_prop.dat` +25
reads `$09` = **fire|poison**, not the `$05` = fire|bolt the other three
carry; +23 still `$80`, water absorbed. So "the row, one last time" was
true of the classes, which `Ot6ShieldTbl` authors identically at
sword|ranged (slash|pierce through v0.50), and false of the elements: the bolt half of the family row
is an `Ot6ElemAddTbl` row, `$0168` `.byte $04`. Water is NOT added and
must not be — `$168` absorbs water, as does every Ultros record
(`+23 = $80`, all four). `$12f` Chupon weak = `$82` = ice|water.)

- **Telegraph:** Ultros's tentacles, for the last time. Chupon has no
  telegraph of his own. When Ultros has taken enough damage, Chupon
  inhales → **Sneeze**, and a character leaves the battle with no
  saving throw and no way to prevent it. The script runs regardless of
  break state, so the fight ends by script rather than by winning.
  Chupon's arrival is Ultros's counter under 12,800 HP, and it comes on
  cue even if Ultros is Broken (#329): `battle_ultros4.lua` breaks him
  with unboosted Fights (one chip a hand) and dumps into the window;
  the hit that crosses the line lands Broken (brk 14-15) and Chupon
  enters 218-442 frames later, Ultros still Broken and alive (shifts
  0/10/20/40). On main's ROM Chupon waited and came only as Ultros's
  dying counter, 1,220 frames after the hit. Played the route's way
  (the IAF driver's boosted Fights), the line falls before the break at
  2 shields in all three draws measured, so the Broken case needs the
  chip-first play.
- **Break story:** this fight teaches not to hold BP. A sneezed
  character leaves with banked BP unspent, so spend it first. Break
  Ultros before the first Sneeze if you can (7 shields across three
  bodies, which is tight) and dump everything. Chupon's 4-shield gauge
  is optional, and not every lineup can break it, because it needs
  Ranged (EDGAR's AutoCrossbow, SETZER's cards and darts, SHADOW's thrown
  stars).
- **Jank:** Sneeze still removes a character with no lasting penalty,
  and Chupon still has no dialogue.

### 20. AirForce — imperial air superiority

Same three, straight from the deck.

| part | shields | weak |
|---|---|---|
| AirForce | 8 | bolt, water + ranged |
| Laser Gun | 3 | bolt, water + ranged |
| MissileBay | 3 | bolt, water + ranged |
| Speck | 1 | bolt, water + any weapon class |

(Decoded, not recalled: all four parts share one vanilla byte —
`monster_prop.dat` +25 = **`$84` = bolt|water** on `$113`, `$145`, `$147`
and `$146` alike, with +23/+24 both `$00`, so the assembly absorbs and
nulls nothing. The Speck's row is the one that differs: it is
bolt|water-weak like the rest, but the authored answer is still one
shield and any weapon class (all six: with Intangir, the one row
whose count of weapon weaknesses the six-class split changed), because
the Speck's purpose is to absorb spells.)

- **Telegraph:** the missile bay racks and locks → **Launcher**
  barrage. Breaking the *bay* cancels it; breaking the body does not.
  This is one step up from Number 128.
- **Break story:** kill both pods and it deploys the Speck, which
  absorbs every spell you cast. That is vanilla behaviour and is
  preserved whole ✦. The answer is the Speck's single shield: any
  weapon in the game breaks it instantly, and the ×2 window then kills
  it. Bolt is the key throughout (Ramuh, or anyone who kept a bolt
  line), with Ranged (EDGAR's AutoCrossbow, SETZER's cards and darts,
  SHADOW's thrown stars) for lineups that did not.
- **Jank:** the IAF shooter sequence before it is unchanged.

## The Floating Continent

### 21. AtmaWeapon

Party: three + Shadow (forced).

**Shields:** 11 · **Weak:** fire, ice, bolt + sword, dagger.
Vanilla has *no* weaknesses here; the whole row is added, and wide on
purpose — the FC party is a free pick plus Shadow, and any lineup must
hold at least two of these five axes. The capstone examines rhythm, not
roster.

- **Telegraph:** it gathers light for a full cycle → **Flare Star**.
  Its opening speech is flavour and has no mechanical effect. Mind
  Blast stays untelegraphed and can arrive mid-rotation, exactly as
  vanilla dealt it.
  **Built** (#561), on vanilla's own script, unchanged: under 12,800 HP
  its turns are a rotation of four (Bio, Quake or Meteo; Battle or its
  Special; Fire 2 on the party; Mind Blast), and the turn after Mind
  Blast it says "Vast energy focused", takes Shell, Safe and Haste and
  glows; it glows again on the next turn and fires Flare Star on the
  one after, so the fuse is two of its turns, not one. The **!** stands
  from the line to Flare Star. A break in between cancels it and the
  rotation starts over: four turns, then the line again
  (`battle_atmaweapon`: "the line returned on its turn 5 back, as many
  turns as the first arming took"). Before, the break only delayed it:
  Flare Star came on its second turn back with no new line
  (build/attempts/wt/v051-fuse/measure/atmaweapon.log). Under 6,144 HP
  the rotation is a different one and no longer reaches Mind Blast, so a
  fuse not yet lit never comes; one already lit still fires.
- **Break story:** 11 shields takes two to three full break cycles,
  with the fuse returning every rotation. Bank BP, break *on* the
  fuse, dump during the ×2 window, survive Mind Blast, and rebuild.
  The fight uses every lesson since Narshe (fuse-cancel, banking,
  absorbs) except part-breaks, since AtmaWeapon has no parts. It is
  the last WoB test of the system.
- **Jank ✦: the MP kill stays.** He has roughly 5,000 MP and dies at
  zero, so Rasp remains a valid but very slow answer. Breaks affect
  turns, not this.

### 22. Nerapa — the escape's doorman

Party: your three plus CELES, who arrives from the statue scene with
every equipment slot empty (route doc §9), during the continent's
collapse, under the 6:00 escape clock.

**Shields:** 5 · **Weak:** ice, bolt, holy + sword, dagger ·
**Absorbs:** fire · **Opens with REFLECT and FLOAT.**

Decoded, not recalled (`monster_prop.dat` row `$118`, 32 bytes at
`+$2300`, ROM `$CF2300`; `tools/tests/lab_nerapa_template.lua` (deleted in 8d350a73; last version at 182bc361) header):
speed 48, attack 11, hit 100, evade 0, m.block 0, defense 105, m.def 150,
m.pow 10, **HP 2800**, MP 280, level 26; absorb `$01` fire; null `$D8`
poison|wind|earth|water; weak `$26` ice|bolt|holy. `Ot6ShieldTbl`
(`ot6_hud.asm:1837`): 5 shields, class-weak `SWORD|DAGGER` (`SLASH|PIERCE` through v0.50). Row bytes
28-31 `00 81 00 20`: the 16-bit "status 3 & 4" word `$0081` that
`LoadRageProp` seeds into `$3de8` (`battle_main.asm:7764-7773`; bit 0 is
the flying flag, folded into Float) sets **status 3 bit 7 = Reflect**.
Measured: every traced fight of the 2026-09-07 lab reads Nerapa's status
bytes as `st=00,00,80,80` from its first action to its last.

**AI** (`ai_script.asm:5237-5266`): on its first turn a dialogue and
**Condemned on all four slots**, once (monster switch 0 — the script
never reapplies it); then the loop *Battle/Battle/Fire 2 · Battle/Fire
Ball/Fire 3 · Battle/Battle/Fire 2*. A **Fight** command against it is
countered with a Battle and counted; the 7th Fight draws **Roulette**
(`if_cmd FIGHT … add_battle_var 0,1`; `if_battle_var_greater 0,6 →
ROULETTE`). Condemned's count (`StartCondemn`, `battle_main.asm:1531`)
is 20 + max(0, 60 − (26 + rand(0..25))) = 29..54, one tick per ATB
overflow of that character; at 1 it casts Doom (`:15296-15303`).
Measured onsets: slot 0 at t≈650-750, then one slot every ~280 frames,
counts 31-55; the first Doom lands at t≈5,400-7,000.

**The fight as measured** (`lab_nerapa_template.lua` (deleted in 8d350a73), doorstep fixture
from `lab_nerapa_bake.lua` (deleted in 8d350a73; last version at 6d5e6307), TERRA L26 / LOCKE L29 / EDGAR L27 / CELES
L23, doorstep at 3:50). Nerapa's opening costs the clock **~1,350
frames** (dialogue 232, four Condemned casts of ~270) before any party
action resolves. The engine writes an action's result one frame after
its own `ExecCmd`; read that way, the ledgers say:

- **Every Bolt and Ice, at every tier, dealt 0 to Nerapa and its full
  damage to a party member** — Reflect. `breakfirst_i37.log`: LOCKE's
  Bolt → `[hp] t=1553 entity 3 888 -> 570 (-318)`; CELES's Ice → `entity
  3 570 -> 295 (-275)`; LOCKE's 2-BP Bolt 3 → `[hp] t=3298 entity 1 1400
  -> 0 (-1400)`; TERRA's 3-BP Ice 3 → `entity 2 1216 -> 0 (-1216)`. The
  driver's `nuke = { Bolt }` line — gen_fc_escape's and the route doc's
  "LOCKE's Bolt nuke" — spent a turn and killed a friend each time it
  fired.
- What lands: **Shiva** (a summon is unreflectable: `magic_prop` `$38`
  byte 2 `$80`, "ignore reflect", vs `$00` on Bolt `$02`) for 534-579 and
  a chip; EDGAR's **AutoCrossbow** 258-272 and a chip, ×4 at 2 BP (1081);
  and **Fight**: CELES's 1-BP Break Blade two swings of ~98, each a chip.
- **Who dies:** CELES (888 HP, no shield/helm/armor) to the first Fire 3
  or a Battle at t≈1,550-2,100 in almost every seed; the driver then
  raises her and she dies again (`control_i7`: 5 raises, 8 deaths, a
  "win" at 0:09). Nobody dies to Doom before t≈5,400.

**Break story, corrected.** Reflect makes this a *physical* break, and
the party has the tool: LOCKE's Genji pair (ThunderBlade, Sword + bolt;
Assassin, Dagger). A base Fight is one swing per hand and each BP adds
two swings, landed alternately (`multi-hit.md` §1), so LOCKE's **1-BP
Fight is four class-weak hits = four chips**; with CELES's two, the gauge
breaks inside the party's first round and the surplus swings land on a
broken, weak target. `physical_i0.log`: `[act] t=1961 start e1 cmd=$00`,
`[hit] t=1962 nerapa (-560) sh=0 (-3)`, `[hit] t=1963 nerapa (-2045)` —
**dead at t≈1,963, before its first Fire**. Fight draws the counter and
counts toward Roulette, but the fight is over by the second Fight. The
telegraph line the earlier draft claimed ("it gathers the curse again")
is not in the script; the Condemned cast is once.

**Policy × seed** (`tools/tests/nerapalab_batch.sh` (deleted in 8d350a73; last version at 338328ee), aggregate by
`nerapalab_aggregate.py` (deleted in 8d350a73; last version at 7ab4eca8); seeds are what InitBattle drew, `$be`; a
repeated seed is a replicate and is not counted twice; `won_late` = Nerapa
fell with under 900 frames of clock, gen_fc_escape's margin — the escape
is still lost). Every attempt is retained under `build/nerapalab/`.

| policy | distinct seeds | won | won_late | lost | Fenix/win | mean t (won) | clock left (won) |
|---|---|---|---|---|---|---|---|
| allin | 8 | 1 | 0 | 7 | 0.0 | 6528 | 7307 |
| breakfirst | 8 | 3 | 0 | 5 | 4.0 | 10587 | 3236 |
| control | 8 | 4 | 1 | 3 | 0.8 | 5763 | 8050 |
| physical | 8 | 8 | 0 | 0 | 0.0 | 2641 | 11176 |
| physical_allin | 8 | 8 | 0 | 0 | 0.0 | 2641 | 11176 |
| physical_bank2 | 8 | 8 | 0 | 0 | 0.0 | 2873 | 10944 |
| physical_raise1 | 8 | 8 | 0 | 0 | 0.0 | 2641 | 11176 |

Per seed (`won` frames / clock left; `L` lost, `late` a win under the
margin; the `$A0` column is issue #149's seed):

| seed | `$C0` | `$20` | `$40` | `$60` | `$80` | `$A0` | `$30` | `$70` |
|---|---|---|---|---|---|---|---|---|
| control | 6221/7574 1Fx | late 13253/582 5Fx | L wiped | L wiped 5Fx | 4477/9334 | L wiped 2Fx | 5121/8710 | 7233/6582 2Fx |
| breakfirst (bank 2) | L wiped 5Fx | L wiped 3Fx | 11037/2790 4Fx | L wiped 2Fx | 12765/1046 6Fx | L wiped | 7958/5873 2Fx | L wiped 2Fx |
| allin (no care) | L wiped | 6528/7307 | L wiped | L wiped | L wiped | L wiped | L wiped | L wiped |
| physical | 2653/11142 | 2405/11430 | 2717/11110 | 2853/10966 | 3261/10550 | 2213/11590 | 2745/11086 | 2281/11534 |
| physical_bank2 | 3005/10790 | 2165/11670 | 3109/10718 | 2782/11037 | 3165/10646 | 3021/10782 | 2833/10998 | 2905/10910 |
| physical_allin | = physical | = physical | = physical | = physical | = physical | = physical | = physical | = physical |
| physical_raise1 | = physical | = physical | = physical | = physical | = physical | = physical | = physical | = physical |

The three physical variants with care options differ from `physical`
only in options that never engage: the fight ends before anyone needs a
heal or a raise, so their traces are frame-identical. Every physical win
had no deaths. Idles 45 and 52 re-drew `$C0` and `$A0` and reproduced
those fights (replicates, not counted).

**Recommendation.** The escape driver must not cast attack magic at a
reflecting target, and against Nerapa the winning verb is the one it
already has for randoms: boosted Fight with LOCKE's pair, the crossbow,
Shiva once. A person does the same after the first bounced Bolt. With
that line the fight is 35-55 s of a 3:50 clock, no Fenix, no deaths, on
every seed tried. Dressing CELES before the continent (she has no armor
at all) is the second lever and is outside this lab.

## Scripted set-pieces (no gauge drawn)

| scene | why it opts out |
|---|---|
| Tritoch (Narshe intro) | one-shots the trio; cutscene in battle clothes |
| Guardian (Vector) | invincible in the WoB — its script says come back later, and the silent HUD says so up front (confirm its WoB palace encounter at data entry) |
| Kefka ×2 (Imperial Camp) | no monster entity at all — formation 504 is empty and the fight runs on character AI `$04`; see 6 above |
| Chupon's Sneeze, Vargas's finish | in their blocks above: scripts beat state |
| TERRA's magitek flashback (battle 115), the esper Kefka fights (battle 97), and the battle-event runner (battles 105, 121-123, 127) | cutscenes played on the battle engine: a 1-HP soldier with no action, a body that casts and ends the battle itself, and an untargetable one that plays the scene. Each has a 0-shield row (v0.45; break-coverage-wob.md section 18) |

## Poison-bit audit

The poison bits on Marshal/Vargas/Kefka/Dadaluma are audited (decoded
from `monster_prop.dat` +25, not recalled — the file is byte-identical
to vanilla `$CF0000`):

   | species | id | weak byte | verdict |
   |---|---|---|---|
   | Marshal | $0064 | $08 poison | vanilla agrees — no add |
   | Vargas | $0103 | $08 poison | poison vanilla; **holy is an add** — authored (`Ot6ElemAddTbl`) |
   | Kefka (Narshe) | $014a | $00 — | **poison is an add** — authored (`Ot6ElemAddTbl`, `$09` with fire) |
   | Dadaluma | $0107 | $08 poison | vanilla agrees — no add |

($14a is the **Narshe defense** Kefka and nothing else. A scan of
all 576 formation records puts him in exactly two, 489 (with the
Ice Dragon) and 505, and 505 is what group 57 / `battle 57` reaches
at event_main.asm:106362, the fight he "won't forget." The camp
scenes share no record with him because they carry no monster at
all. The $11a/$12a Kefka records are the level-83 and level-71
endgame ones, which are out of WoB scope.
From the same pass: Ipooh $014d reads $01 fire, so the fire weak
above is vanilla and not an add, and the chip keys are confirmed in
the data, with AuraBolt ($5e) carrying $20 holy and BioBlaster's
attack ($7d) carrying $08 poison in the vanilla spell records.)
