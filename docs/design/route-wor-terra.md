# World of Ruin: Terra (Palidor, Mobliz, Phunbaba)

The route from the save beside the Falcon (`wor-falcon-v1`: CELES, SABIN,
EDGAR and SETZER on foot at world (25,160)) to TERRA rejoining in Mobliz,
and the save beside the Falcon there (`wor-terra-v1`). Milestone v0.27,
#264; #365 (the pool round the Falcon's landing) is measured in section 8.
`tools/tests/gen_wor_terra.lua` plays it.

Line numbers are into `ff6/src/event/event_main.asm`. Evidence is under
`build/attempts/wt/v027-terra-route/`; every number below is quoted from a
log there. Nothing was measured by writing game state.

---

## 0. Findings

1. **The arc is one flight and one town.** Palidor waits on the Solitary
   Island's beach (map 398 NPC_6, `_ca55e9`: `give_genju PALIDOR`), shown
   since the Falcon rose (`$039B`); the beach is two maps from a landing on
   the island's grass (75,238). Mobliz is the town at world (237,135); the
   Falcon lands on (238,135), one step east of its gate.
2. **Phunbaba is four monster records in two visits.** The first visit
   (`_cc4990`, trigger 154 (52,58), after TERRA's story `$0290`) is battle
   128, TERRA alone (`char_party TERRA, 2`) against an invincible Phunbaba
   (`AIScript::_362`: `invincible_on SELF`), a loss the event plays on from
   (no `_ca5ea9` after it), then battle 129, the party, which ends when
   Phunbaba is hit under 20480 HP (`_363`: `attack ESCAPE`). The second
   visit (`_cc4c1b`, trigger 150 (40,50), after `_cc4af0` saw the Falcon
   `$00CD` and `_cc4b4b` set `$0292`) is battle 130, which ends when he is
   hit under 15360 HP with two BabaBreaths (`_364`), then battle 131, TERRA
   morphed (`set_b_switch $3A`) with the two the BabaBreaths left, to the
   kill (`_365`).
3. **The BabaBreaths send two of the four to the Falcon.** RemoveChar
   zeroes their `$1850` (`battle_main.asm` `RemoveChar`); they wait in the
   Falcon's cabin (map 12), where "Change party members?" (`_caf59d`) opens
   the party menu. Which two is the battle's draw (CELES and EDGAR in one
   run, CELES and SETZER in another, section 9), so the route regroups
   aboard to a fixed party before it saves.
4. **TERRA rejoins at the party's level, dressed.** Her record at the
   Falcon checkpoint is L27 with nothing equipped (`TERRA's record:
   TERRA(p0) L27 HP 1092/1207 MP 252/252`, `kit TERRA FF FF FF FF FF FF
   FF`); after battle 131 she is L33 with the Break Blade, Gold Shld, Gold
   Helmet and Mithril Vest (`TERRA(p1) L33 HP 1794/1794 MP 331/331`, `kit
   TERRA FF 11 5D 76 89 FF FF`). She fights battle 128 at L27 with nothing
   equipped; it is a loss by design.
5. **Every random species on the route is already authored** (world groups
   29/30 on the island, 37/38 outside Mobliz); the four Phunbaba records
   rode the generated floor (`break floor 5 * slash`) and now have designed
   rows (section 6).
6. **Mobliz has no shop.** Its chests hold an Elixir (163 (51,12)), an
   Ether (150 (34,49)) and a Fenix Down (158 (9,17)); the route opens all
   three. The bag the party brings is inside the band (section 4).
7. **#365: the pool round the Falcon's landing is vanilla's late-game
   pool.** Formation `$143` (Mantodea, Sprinter, Spek Tor x2; L50-54)
   wiped the L33-36 party in 8 of 27 fights; the Crawlers once in 47, a
   pincer the run-first arm met. A slot-0 monster's plain Battle (the
   Mantodea's, vanilla attack 180) made 57 of the 63 kills, 19 of them in
   one action from 80% HP or more.
   The Terra route boards at once and never walks it (section 8).

---

## 1. The start state (`wor-falcon-v1`)

`contract wor-falcon-v1 (entry): all 30 fields hold`; `CELES(p1) L34 HP
1313/1900 ... SABIN(p1) L33 HP 1240/1812 ... EDGAR(p1) L33 HP 1207/1803 ...
SETZER(p1) L33 HP 1402/1800`; `tonic=4 potion=79 xpotion=3 ether=5
elixir=7 fenix=31 remedy=11 soft=19 revivify=32 tent=6 gil=280318`
(`dev/dev17_first_pass.log`).

## 2. The legs

1. **Board** the parked Falcon: A on its tile (`world/move.asm` @204e). The
   lift-off is in place, with no map load, so `$11FA` keeps the on-foot
   load's `$80` for the whole flight; `H.aboardAirship` now reads the
   vehicle engine (`VehicleNMI` installed, `$E0/$E2` at 0) as well
   (`board/board_probe.log`: `$11FA=80 ... E0/E2=0,0 ... nmi=EEA509 (W
   EEA728 V EEA509)`).
2. **Palidor.** Fly to (75,238), walk to the island's tile (76,240) ->
   396, the beach 398, talk to the stone (obj `$15`), back out, board.
3. **Mobliz.** Fly to (238,135), walk in. The child at the gate (158
   (27,15)/(27,16), `_cc43e2`, `$028E`); the Elixir in the house 163; the
   cellar stairs 165 -> the cellar 154; the children and TERRA (154
   (52,57), `_cc4447`, `$028F`); talk to TERRA (154 NPC_2, `_cc4565`,
   `$0290`); the first visit (154 (52,58), section 5); Fenrir from the
   child at (50,53) (`_cc4abd`, `$02D7`).
4. **Katarin.** Out through the house to 158 (27,16): `_cc4af0` sets
   `$00BE` (the Falcon's `$00CD` is its gate). The shelter 165 (11,25),
   its (7,17) loads Katarin's room 150 (`_cc4b29`); the Ether; (40,52)
   `_cc4b4b` (`$0292`: Phunbaba is back); (40,50) the second visit
   (`_cc4c1b`): TERRA joins (`char_party TERRA, 1`, `$00BF`).
5. **Regroup and save.** The Fenix Down chest, out of town, board, X to the
   deck (map 11), the cabin (map 12), a waiting member's "Change party
   members?" -> Yes, the party menu (`H.partySelect`): TERRA, CELES, SABIN,
   EDGAR. Relics (`H.dressRelics`), Fenrir on TERRA, the wheel (11 (15,8),
   facing left, A: `_caf532`) -> Lift-off, land on (238,135), Save: the
   `wor-terra-v1` checkpoint (`H.saveAtCheckpoint`).

### 2.6 The party regrouped aboard

TERRA, who joined, and the three who have walked the World of Ruin since
the island; SETZER stays aboard. The next arcs can regroup the same way
(`CABIN_NPCS` and `REGROUP` in the generator).

## 3. Mechanics the harness learned

- **A trigger that re-fires under the party.** Standing on a trigger whose
  event returns at once (the cellar's (52,58) before TERRA's story, (50,53)
  after Fenrir, Katarin's room's (40,50)), the event runs again every few
  frames, so control reads lost on most frames although the field takes a
  held direction (`cellar/probe3.log`: held Up leaves (52,58) on the second
  frame). `navTo` released its step on every lost frame and blocklisted the
  edge after 30 (`cellar/probe2_navto.log`: `nav: edge (52,58)->up blocked
  in reality`); with `H.NAV_REFIRE_HOLD` it keeps holding a step already
  pressed while only control flickers (`cellar/probe2_navto_fixed.log`:
  `[probe] arrived`, `PASS (frame 24)`). It is opt-in, on in
  `gen_wor_terra` only: on for every walk it moved `gen_whelk_poweron`'s
  play from power-on (`whelk_ab/`: `PASS (frame 36896)` on main's lib and
  on this branch with the switch off, `PASS (frame 36956)` with it always
  on), which reshuffled every later draw.
- **A scripted loss whose wipe reading outlives it.** Battle 128 leaves
  the seat table reading wiped until battle 129's InitBattle, so the wipe
  canary can fire in the scene between them; the generator answers that
  scene's dialog itself and judges the visit by its outcomes: battle 128
  lost with TERRA alone seated, battle 129 won.
- **The wheel** answers A held facing left on its tile; the cabin's
  question is a dialog choice (`H.dialogChoice`).

## 4. The party and its supplies

The supply band (level-curve.md) at L34: Potion 51 (held 76-79), Tincture
9 (held 13), Revivify 3 (held 32), Fenix Down 20 (held 31). Mobliz sells
nothing; the arc spends 3 Potions in the first visit's fight and 2 in the
second's (`potion=79` -> `76` -> `74`, `dev/dev17_first_pass.log`).

TERRA joins with the Break Blade (slash), Gold Shld, Gold Helmet and
Mithril Vest; the relic rule puts the Ribbon and the Earrings on her and
moves CELES to the Genji Glove and Hyper Wrist (`[relics with TERRA] TERRA
wears Ribbon $CA, Earrings $C3`, `CELES wears Genji Glove $D1, Hyper Wrist
$D2`). Fenrir goes on TERRA (magicite.md: "Terra, later in the arc").
Palidor is owned and unworn: each of the four already wears a stone.

## 5. Phunbaba

| battle | record | HP | party | ends |
|---|---|---|---|---|
| 128 | `$16A` | 60000, invincible | TERRA alone (L27, unequipped) | her loss; the event plays on |
| 129 | `$16B` | 28000 | the four | hit under 20480: Escape |
| 130 | `$16C` | 26000 | the four | hit under 15360: BabaBreath x2, end_battle |
| 131 | `$16D` | 26000 | TERRA (morphed) + the two left | his death |

Vanilla: weak poison, absorbs bolt; Bolt 2, Bolt 3, Blow Fish and his
Special. Played results are in section 9.

## 6. Break rows (authored)

| record | shields | classes | why |
|---|---|---|---|
| `$16A` | 0 | -- | TERRA's solo loss: no gauge, as the scripted set-pieces |
| `$16B` | 4 | bludg, special | the hide gives to blows (SABIN) and to ¤ (SETZER: a demon); EDGAR keys him with the Bio Blaster (vanilla poison); the fight lasts 7520 HP, a miniboss's budget |
| `$16C` | 5 | bludg, special | the same body, the longer fight (10640 HP) |
| `$16D` | 12 | slash, bludg, special | TERRA's blade keys him, whoever the BabaBreaths left beside her |

CELES holds no key on `$16B`/`$16C`: her turn is Runic against his Bolt 2
and Bolt 3. `tools/tests/battle_breakwor_terra.lua` (`@suite`) reads the
rows back from the ROM, the vanilla weak and absorb bytes, the formations
of event groups 128-131 and world groups 29/30/37/38, and the keys
(`dev/suite_breakwor_terra_green.log`: `checked 4 designed rows`, `checked
13 formations, 16 formation-species pairs`, `$16D: TERRA's blade (slash)
is a key`, `PASS`).

The first draft gave `$16B` 6 and `$16C` 8. Neither broke in 18 fights each
(`var4/analysis.txt`: `$1A5 (129 first visit): 18 fights, 11 distinct keys,
18 won, 0 lost, 0 party deaths, broken in 0`; `$1A6 ...: 18 fights, 14
distinct keys, 18 won ... broken in 0`): SETZER's Jackpot ends both fights
first (`SETZER Jackpot on slot 0 (28000 HP, 6 shield(s)) at 1 BP: 2 roll(s)
of expected 5280 each`; `actor=3's skill took 10032 off the monsters`). The
rows now carry 4 and 5, the counts of a miniboss with that much HP to
lose (the Mad Oscar's 4 at 2,900, Dullahan's 10 at 23,450).

## 7. The checkpoint

`wor-terra-v1`: world 1 (238,135), slot 3, on foot beside the Falcon;
TERRA, CELES, SABIN, EDGAR; `$0291`, `$02D7`, `$00BE`, `$00BF` set;
Palidor and Fenrir owned, TERRA wearing Fenrir (`ot6_contract.lua`).
`$1F64` bits 12-13 are the facing direction, not an aboard flag
(field-ram.txt `--ddnzpm`); the landing left `$2401`.

## 8. #365: the pool round the Falcon's landing

Measured with `lab_ruinwaste.lua` (`365/`): Continue `wor-falcon-v1`,
care, then walk (25,165) <-> (25,158) (world group 49) fighting every
battle with the route's tactical driver and its field care, up to ten
battles or a wipe, at seed shifts 0-28 (`ruin_s*`; `ruin_k0` is an earlier
copy of shift 0 and repeats its battle keys); `lab_ruinwaste_focus.lua`
(`ruinF_s*`) is the same with the Mantodea first in the kill order; and
`ruin_k3` ran (L+R) from its first three battles before fighting, the
tactical driver taking over at the flee cap.

| formation | arm | fights (distinct battle keys) | lost |
|---|---|---|---|
| `$13F` Crawler x3 | route order | 30 (28) | 0 |
| `$13F` Crawler x3 | Mantodea first | 16 (16) | 0 |
| `$13F` Crawler x3 | run first | 1 (1) | 1 |
| `$143` Mantodea, Sprinter, Spek Tor x2 | route order | 19 (15) | 6 (5 keys) |
| `$143` Mantodea, Sprinter, Spek Tor x2 | Mantodea first | 8 (8) | 2 |

(`365/analysis.txt`, over every `ruin*.log`.) Every `$143` loss had the
Mantodea alive at the end (`battle $143 LOST ...: killed s1:$087 s2:$0B0
s3:$0B0` or `killed s2:$0B0 s3:$0B0`). The one Crawler loss is the
run-first arm's first battle, a pincer (`ruin_k3.log`: `wipe context: the
last battle up (f13650) was formation 5F5E 5D5C 005B 005B 005B 5F5E;
seats ... a6:0/1900 ... a5:0/1812 ... a4:0/1803 ... a9:37/1800`, key
`be1C-g013F`); that walk says no `[outcome]` and no `[death]` lines, so
its course is not in the log. Under the route's own fight order the
Crawlers won 46 of 46 fights (44 distinct keys); the wt/hire-sprite wipes
named in #365's title were a pincer lab whose policy was Defend and Hired
Help (`round2/attempts/pincer_pw5.log`). Of the 63 party deaths logged in
these runs, 57 were `by slot 0 cmd $00 atk $EE`, a slot-0 monster's plain
Battle (the Mantodea in `$143`), 19 of them `ONE ACTION from >= 80%`. Wins
came at L33-38; the losses at L33-36. The Mantodea's attack 180 is
vanilla's (`Mantodea vanilla atk 180 lvl 54 | ot6 atk 180`), and its row is
the floor (`6 * pierce`); the `$143` XP is 9617 (x2 as a random).

What it says: the landing's pool is vanilla's late-game pool meeting a
L33 party; the Mantodea first in the kill order did not change the rate in
these 8 fights. The Terra route does not walk it: the party boards on the
landing tile. The arc that walks the Jidoor continent next would want
designed rows for its six species (Crawler, Mantodea, Sprinter, Spek Tor,
Geckorex, Reach Frog; groups 48-50), and its own measurement of levels or
kit against the Mantodea.

## 9. Played

### 9.1 The run

The chain's own play (`qual/wor_terra.log`, `ninja` on px13 from power-on;
it Continues the chain's capture of `wor-falcon-v1`, `CELES(p1) L33 ...
EDGAR(p1) L32 ... SETZER(p1) L32`): battle 128 `lost after 1867 ticks, 1
seated`, battle 129 `won after 1143 ticks`, `TERRA joined ... TERRA(p1) L32
HP 1692/1692`, one random battle beside the Falcon (formation `$0D6`),
`contract wor-terra-v1 (exit): all 30 fields hold`, `PASS (frame 51224)
attempts=1/3`; its capture is the tracked `wor-terra-v1` (`checkpoint
drift wor-terra-v1: none`, sha256 `dad40a6c...`). Its first try met that
battle on the last step onto the Falcon and `board()` pressed A into it
until it timed out (`qual/wor_terra_chain1_board_battle.log`); boarding
now fights it.

The bootstrap capture (`capture/capture1_bootstrap.log`): `contract
wor-falcon-v1 (entry): all 30 fields hold` ... `[saved] wor-terra-v1: slot
3 holds map 1 ($2401) world tile (238,135)`, `contract wor-terra-v1 (exit):
all 30 fields hold`, `PASS (frame 43814) attempts=1/3`. The variation
set's shift 0 (`var7/var7_s0.log`): `TERRA joined map 158 (11,21):
TERRA(p1) L33 HP 1794/1794 MP 331/331 ... CELES(p1) L34 ... SABIN(p1)
L33`, the cabin `roster ... EDGAR $1850=00 SETZER $1850=00` (the two the
BabaBreaths sent away), `[wor] the stretch: TERRA(p1) L33 ... CELES(p1) L34
... SABIN(p1) L33 ... EDGAR(p1) L33`, `PASS (frame 43870) attempts=1/1`.

### 9.2 Under draw variation, before the kits merge (`var7/`)

Eighteen runs on the final rows: twelve seed shifts (0-44 by 4) and, to
move the encounter draw, K = 2, 5 and 9 random battles used up on the
Solitary Island's grass before the beach (`lab_terra_k*.lua`, the
generator with that one step added; `make_kvariant.py`), each at shifts 0
and 12. All eighteen pass (`PASS (frame 42850)` to `PASS (frame 61178)`,
`attempts=1/1` each). By distinct battle key (`var7/analysis.txt`):

| battle | fights | distinct keys | won | lost | party deaths | broken |
|---|---|---|---|---|---|---|
| 128 TERRA alone | 18 | 16 | 0 | 18 (scripted) | 18 (TERRA) | 0 (no gauge) |
| 129 first visit | 18 | 11 | 18 | 0 | 0 | 0 |
| 130 return | 18 | 14 | 18 | 0 | 0 | 6 |
| 131 TERRA morphed | 18 | 15 | 18 | 0 | 9 | 18 |

- **129 ends on SETZER's first turn** in most draws: his Jackpot is the
  first action and its two rolls take 10032 (`SETZER Jackpot on slot 0
  (28000 HP, 4 shield(s)) at 1 BP`, `took 10032 off the monsters`), past
  the 7520 the fight lasts. A win; the gauge does not come into it.
- **131 is the arc's real fight**, 3736 to 14455 ticks. Its counter is a
  Bolt 2 on every hit taken, and the deaths are the two members beside
  TERRA, from Bolt 2/Bolt 3 or Blow Fish when low (`[death] ... entity 2
  char 4 from 225/1803 by slot 0 cmd $02 atk $07`); TERRA died in none.
  Across the arc the bag spent 0-13 Potions and 0-3 Fenix Downs a run
  (`potions 79 -> 66, fenix 31 -> 28` the most; the Fenix Down chest adds
  one); five of eighteen runs used any Fenix Down. Not a coin flip (18 of
  18 won); the worst draw is attrition, a candidate lab if later levels or
  kits move it.
- **TERRA's blade keys him**: 131 broke in 18 of 18 fights; the 21 breaks
  landed at 3328-22137 of his 26000 HP, the median near 18000, two of
  them on the killing blow (`[brk] ... $16D broken (0 of 12 shields) at HP
  21138`; `at HP 0`).

### 9.3 On the kits ROM (`var9/`, `final/`)

After wt/v027-kits merged (e410e209: Jackpot, Morph and the divines need 3
Boost Points, Break chips shields), the chain was played again from
power-on (`final/qual10.out`, `final/qual11.out`: `ninja` green, `generate
wor_terra` `PASS (frame 46504) attempts=1/3`, `contract wor-terra-v1 (exit):
all 30 fields hold`), and `wor-terra-v1` re-cut from that play
(`final/drift_wor_terra.log`: `checkpoint drift wor-terra-v1: none -- the
tracked save is the one the graph's play makes today`, sha256
`2178ccdc...`).

The variation set was run again at 457304fa, booted from the chain's own
capture of `wor-falcon-v1` (`build/checkpoints/`, not the tracked v0.26
copy): the same twelve seed shifts and K = 2, 5, 9 at shifts 0 and 12. All
eighteen pass (`PASS (frame 45706)` to `PASS (frame 63493)`, `attempts=1/1`
each). By distinct battle key (`var9/analysis.txt`):

| battle | fights | distinct keys | won | lost | party deaths | broken |
|---|---|---|---|---|---|---|
| 128 TERRA alone | 18 | 15 | 0 | 18 (scripted) | 18 (TERRA) | 0 (no gauge) |
| 129 first visit | 18 | 15 | 18 | 0 | 0 | 18 |
| 130 return | 18 | 16 | 18 | 0 | 1 | 18 |
| 131 TERRA morphed | 18 | 17 | 18 | 0 | 0 | 18 |

With Jackpot behind a full boost, SETZER no longer ends battle 129 on his
first turn, and every party fight breaks: the 4 and 5 shields of 129 and
130 now land inside the fights, and 131 breaks at 15271-21265 of 26000 HP.
Battle 131's attrition is gone: no party death in 18 fights (9 before the
merge), and the arc spends 0-7 Potions (`potions 73 -> 66` the most) and
one Fenix Down in one run of eighteen. The rows stay as they are; nothing
here is a lab candidate now.

**A battle on the step onto the Falcon.** None of these draws put one
there, so `lab_board_battle.lua` (`board/`) boards and lands beside Mobliz
until one does, from the chain's `wor-terra-v1`. Before the fix the battle
(formation `$0D6`) was fought and the party, handed back on (238,136) below
the parked Falcon, pressed A there until `timeout after 30000 frames
driving toward board the Falcon` (`board/boardlab_red_before.log`); now
`[board] f4851 on (238,136), the Falcon parked at (238,135): walking back
onto it`, `[boardlab] DONE after 5 round(s): 1 boarding(s) a battle
interrupted`, `PASS (frame 5030)` (`board/boardlab_green_after.log`).

**Battle 128's handling** is asserted in every run: `allowGameOver ON`
only from the first visit's trigger to battle 129's verdict, `[retry]
scripted loss answered (Mobliz battle 128 ...): game over count 1 and the
unanswered record (the party was wiped in battle) cleared`, then
`allowGameOver OFF` (`fix/fix_s0.log`, and each `var9/` log).

### 9.4 What was left

- **Two suites the reshuffled chain exposed.** The Phunbaba rows lengthen
  `Ot6ShieldTbl`, and the chain's play moves from `arvis_wake` on
  (`PASS (frame 18017)` on main, `17983` here); suites whose fixtures come
  from that play meet new draws. `battle_assassinate` was red on the
  pre-kits chain and green on main's (`assassinate/`); the kits rewrite
  passes on both (`assassinate/main_e410e209_pass.log`,
  `branch_92254dd6_pass.log`). `battle_gprain` went red on this chain when
  SETZER and then SABIN were Zombied in a crowd; its exemption now covers an
  ally's lost control (`kits/`).
- **The regroup's party** is fixed (TERRA, CELES, SABIN, EDGAR); SETZER
  waits on the Falcon. A different four is one line (`REGROUP`).
- **Palidor is unworn.** Each of the four wears a stone; the Esper plan
  (magicite.md) gives it to "the Falcon arc's four" to learn from, which a
  later arc's kit pass can decide.
- **The chain's own capture** of `wor-terra-v1` replaces the bootstrap one
  by `checkpoint_drift.py --recut` after a `ninja` that replays the line.
