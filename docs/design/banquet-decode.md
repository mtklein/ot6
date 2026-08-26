# The Imperial banquet: decode and measurements

Source decode of the whole banquet block (maps 243/244/250/251/252,
`$007C=1` → `$0238=1`), the scoring circuit and its reward tiers, the timer
save/reset/load behaviour, and battles 26/27/30. Claims cite `file:line`.

Companion to `sealed-gate-route.md`, the v0.7 route survey this block sits in.

---

## 1. State machine: how the block enters and leaves

| step | where | latch | evidence |
|---|---|---|---|
| castle escort | 243 (8,18) trigger | `$013A=1`, `$062F=1`, opens the 243 (15,8) door via `mod_bg_tiles {14,8}` | `event_trigger.asm:1094` → `_cc835c`, `event_main.asm:97039-97078` |
| 250 first entry | map-init | `$013B=1`, `$062D=0`, opens a door at {22,29} | `map_init_event.asm:269` → `_cc839e`, `:97079-97098` |
| banquet start | 250 (54,16), face-UP+A on the dais | `$007C=1`, `set_var 0,0`, `start_timer 0,14400,_cc8a96,{FIELD_VISIBLE,BANQUET,MENU_BATTLE_VISIBLE}`, `$0634=1` (window soldiers appear), `$062E/$0630=0` | `event_trigger.asm:1123` → `_cc8490` `:97242`; gates `:97243-97247` (`$01B4`,`$01B0`,`$007C=0`); tail `:97414-97420` |
| the 4-minute circuit | maps 243/244/250/252 | per-soldier latches `$0217-$022E`, talk counter slots `$014F,$0200-$0216` | §2, §3 |
| dinner | timer-0 expiry, wherever the party stands | `stop_timer 0`, **`$013C=1`** (stops all further soldier scoring), `load_map 5` "That evening…", `$062C=1`, `load_map 251 {80,25}` | `_cc8a96` `:98045-98069` |
| Q&A + challenge | 251 dinner table | `$0230-$0236` question bookkeeping, `$0237` challenge latch, `$01B5` table-trigger re-arm | §4 |
| roster rewrite | Q&A tail | `$02F0-$02F9` forced (`:98934-98943`), `norm_lvl LOCKE/TERRA` (`:98944-98945`), `remove_equip CYAN/EDGAR/SABIN/SETZER` (`:98953-98956`, GAU `:98920`, MOG `:98932`), `char_party` → TERRA+LOCKE only (`:99079-99101`), **`$007D=1`** (`:99133`), control back on 251 (`:99142-99144`) |
| the messenger | 250 (23,12) walk-on | reward ladder (§5.1), `set_var 0,0`, **`$0238=1`** | `event_trigger.asm:1131` → `_cc91c0` `:99146-99264`; gated `$007D=1 && $0238=0` `:99147-99150` |

The block can be left, but not re-entered. The 243 south rows
(11-19,31) are `_cc9359` (`event_trigger.asm:1095-1103`), which with
`$007B=1` is `load_map 253 {29,2}` (`:99389-99395`), with no `$007C` gate.
253's world exit is an ordinary 12-wide long entrance (30,63) → world
(120,188) (`long_entrance.dat` map-253 block), so a player mid-window can
reach the saveable world map. Coming back is not possible: the 243 (15,8)
door into 250 was opened by `_cc835c`'s transient `mod_bg_tiles`, 243's
map-init is `EventReturn` (`map_init_event.asm:262`) and the escort is
`$013A`-latched dead, so a re-entry of 243 shows the closed door and the
map is a dead-end pocket (§5.2). This does not block progress, because the
timer callback collects the party from any field map (§5.3).

There is no early exit. The only writer of `$013C=1` in the game is
`_cc8a96` itself (`:98047`; every other grep hit is an `if_any` condition),
and `_cc8a96` is reached only as the timer-0 callback. The 14400-frame
timer is a hard floor on segment I→J.

## 2. The timer machinery ($1188 family)

Timer 0 block, written by event command `$a0` (`start_timer`,
`field/event.asm:3736-3757`): `$1188` flags = `pfrmxxee` (p=pause in
menu/battle, f=field-visible, r=**banquet**, m=menu/battle-visible, xx=timer
number, ee=event-pointer bits 16-17), `$1189/8A` frame counter,
`$118B/8C/8D` callback as a +$CA0000 event offset. The banquet's call
encodes flags `$72`, ptr `$028A96` (= `_cc8a96`). Timers 1-3 follow at +6
(`$118E`, `$1194`, `$119A`).

Each module's handling of the timer, which accounts for all of the
save/reset/load behaviour:

- **field**: `CheckTimer` + `DecTimers` every frame
  (`field/reset.asm:96-98`; `field/event.asm:5656-5674, 5680-5732`).
  `CheckTimer` fires the callback only when the counter is 0, an event
  pointer is set, no other event is running, and the party is halted.
- **menu**: `DecTimersMenuBattle` (`field/event.asm:5562-5650`, called
  `menu/menu_common.asm:3466`). Bit7 clear means the banquet timer ticks
  through menus, and `CheckEventTimer` (`menu_common.asm:425-444`)
  force-closes the menu when a bit-$20 timer hits 0.
- **battle**: same tick (`btlgfx/btlgfx_main.asm:1628,2231`); expiry raises
  `$1dd1` bit5, and `CheckBattleEnd` force-ends the fight and sets `$3ebc
  |= $20` (`battle/battle_main.asm:12049-12053`). That is b-switch `$45`,
  the path in the field scripts that flashes BLUE and awards no points.
- **world**: no tick at all. No `DecTimers`/`CheckTimer` caller exists in
  `ff6/src/world/`. The countdown freezes on the world map and resumes on
  the next field map.

Save/load: `CopyGameDataToSRAM` runs `PushTimers`, which copies
`$1188-$119F` to `$1FA8-$1FBF`, inside the saved `$1600-$1FFF` block
(`menu/save.asm:42-75, 108-115`); `LoadSavedGame` runs `PopTimers` back
(`:18-34, 121-128`). The score variable (var 0 = `$1FC2`,
`field/event.asm:4453-4523`) and every `$007x/$01xx/$02xx` switch
(`$1E80+`) also live inside that block. Only `InitNewGame` clears timers
(`field/init.asm:184-200`); `InitSavedGame` does not. The banquet timer
survives a battery cycle (§5.3).

## 3. The soldier circuit and its scoring branches

Score = event variable 0 (`$1FC2`). Zeroed at `$007C=1` (`:97419`) and
after the rewards (`:99261`).

The talk counter is one global 24-slot ladder, `_cc88bf`
(`:97835-98002`): each call takes the next unclaimed slot
(`$014F`, then `$0200-$0216`), does `add_var 0,1`, and toasts "N people".
24 callers exist, each latching its own switch first, so ladder
capacity = caller count = 24. Scoring is confined to the window by two
complementary mechanisms: the `$062F`-population scripts (latches
`$0217-$0223`, plus `_cc873b`/`_cc8782`) each gate on
`$007C=1 && $013C=0` because their NPCs exist outside the window too,
while the `$0634`-population scripts (the other nine) gate only on their
own latch, because their NPCs exist only inside the window (`$0634` set
`:97416`, cleared `:99117`).

Census, per map (NPC records in `event/npc_prop.asm`; the two visibility
populations that exist during the window are `$062F`, set at castle entry
`:97077`, and `$0634`, set at banquet start `:97416`; the `$062B`
pre-attack population was cleared by the v0.6 escape, `:96986`):

| map | pos | event | latch | says / does | points |
|---|---|---|---|---|---|
| 243 | (8,18) | `_cc8796` `:97711` | $0224 | "I've slain too many people." | +1 |
| 243 | (12,14) | `_cc873b` `:97670` | $022B | **battle 26** (Mega Armor) | +1, +5 clean |
| 243 | (18,14) | `_cc8782` `:97700` | $022C | "Someone outta thrash ya!" | +1 |
| 244 | (10,17) | `_cc87a6` `:97719` | $0225 | "You're not wanted!" | +1 |
| 244 | (11,23) | `_cc86eb` `:97625` | $0220 | "Kefka's scum…" | +1 |
| 244 | (25,23) | `_cc86ff` `:97637` | $0221 | "My whole family was lost…" | +1 |
| 244 | (16,14) | `_cc8713` `:97648` | $0222 | "…before we could use this machine" | +1 |
| 244 | (20,14) | `_cc8727` `:97659` | $0223 | "Kefka's in jail!" | +1 |
| 250 | (21,24) | `_cc8637` `:97523` | $0217 | "Espers … terrifying the Empire!" | +1 |
| 250 | (25,24) | `_cc864b` `:97534` | $0218 | "We've lost our will to fight." | +1 |
| 250 | (21,18) | `_cc865f` `:97545` | $0219 | "Kefka's been imprisoned…" | +1 |
| 250 | (25,18) | `_cc8673` `:97557` | $021A | "The war's over…" | +1 |
| 250 | (98,51) | `_cc86d7` `:97612` | $021F | "Kefka! Using poison…" | +1 |
| 250 | (51,50) | `_cc87b6` `:97726` | $0226 | **battle 27** (Commando) | +1, +5 clean |
| 250 | (9,49) | `_cc87f9` `:97752` | $0227 | "The Empire'll never die!" | +1 |
| 250 | (110,51) | `_cc8809` `:97759` | $0228 | **battle 27** (Commando) | +1, +5 clean |
| 250 | (120,13) | `_cc884c` `:97786` | $0229 | "Espers… that powerful…" | +1 |
| 250 | (115,16) | `_cc885c` `:97794` | $022A | "We'll never knuckle under…" | +1 |
| 252 | (40,56) | `_cc8687` `:97568` | $021B | "…came to free their friends" | +1 |
| 252 | (42,52) | `_cc869b` `:97579` | $021C | "Facility's been dismantled." | +1 |
| 252 | (42,56) | `_cc86af` `:97590` | $021D | "The Empire's talking peace!" | +1 |
| 252 | (37,57) | `_cc86c3` `:97601` | $021E | "…he imprisoned the fiend!" | +1 |
| 252 | (42,57) | `_cc886c` `:97801` | $022D | **battle 27** (Commando) | +1, +5 clean |
| 252 | (40,54) | `_cc88af` `:97828` | $022E | "…settled after the banquet" | +1 |

24 rows: 20 talks + 4 fights. Window maximum = 24 + 4×5 = 44.
Not scoring: the two dais servants 250 (52,13)/(56,13)
(`_cc83ca/_cc83d4` → "Dinner preparations underway", `:97103-97119`),
the 250 (23,31) / (16,30) / (30,30) "Gestahl waits inside" servants, the
250 (76,56) Kefka-cell scene (`_cc83e8` `:97120-97241`, which is scene
only and scores nothing), and the four (x,49-50) jump-scare floor triggers
(`_cc8342`, `event_trigger.asm:1127-1130`).

The **clean-win idiom** after each fight (`battle 26` at `:97678`;
`battle 27` at `:97730/:97763/:97805`; `battle 30` at `:98022`):
`if_b_switch $NN, next` jumps when the flag is clear
(EventCmd `$b7`, `field/event.asm:4053-4073`; macro
`event_cmd.inc:774-777`). So the +5 is reached only when $40, $45 and
$44 are all clear; any set flag flashes RED/BLUE/GREEN and skips the
points. The `if_switch $022F=0, skip` lines are unconditional in practice,
because `$022F` is never set anywhere in the ROM. The three flags, from the
battle side ($3eb4-block, copied to `$1dc9+` at battle end,
`battle_main.asm:12307-12311`, and seeded from it at init `:6103-6106`):

- `$40` = `$3ebc` bit0, set by `LoseBattle` ("game over after battle
  ends", `:15756-15759`), meaning the party was wiped;
- `$44` = bit4, set by `BattleEnd_01`, which is commented "ran out of
  time before emperor's banquet" (`:12121-12125`);
- `$45` = bit5, set when a BANQUET-flag timer expires mid-battle
  (`:12049-12053`).

Losing costs the +5 but does not end the game. None of the five banquet
battle scripts calls `_ca5ea9`/`GameOver` (contrast `RandBattle`,
`event_main.asm:107-125`, which is where b-switch `$40` normally becomes a
game over); each falls through to `fade_in`, a canned line, and `_cc88bf`,
so the +1 lands even on a loss.

**Castle topology for the circuit** (decoded from
`short/long_entrance.dat`; 251 has no walk-in doors except the dais pair):

```
253 (28,1)+2 ─► 243 (15,29)      243 rows (11-19,31) ─► 253 (29,2)   [exit]
243 (15,8) ─► 250 (23,33)        250 (22,34)+2 ─► 243 (15,10)
250 (9,14) ─► 252 (35,59)        252 (35,60) ─► 250 (9,16)
250 (51,53) ─► 252 (35,50)       252 (35,48) ─► 250 (51,52)
250 (9,52) ─► 244 (13,21)        244 (13,19) ─► 250 (9,51)
250 (65,53) ─► 244 (23,21)       244 (23,19) ─► 250 (65,52)
250 (111,62)+2 ─► 244 (18,13)    244 (18,11) ─► 250 (112,61)
250 (53,9)/(55,9) ─► 251 (79,26)/(81,26)     251 (79,27)+2 ─► 250 (53,11)
250 internal stairs: (15,21)↔(24,52) (31,21)↔(81,59) (23,9)↔(54,34)
  (37,14)↔(101,16) (9,9)↔(14,60) (37,9)↔(60,61) (101,10)↔(120,23)
  (115,22)↔(97,47)
```

## 4. The dinner Q&A tree: every choice and its value

Choice targets are in listed order (`choice` macro,
`event_cmd.inc:746-772`); the highest-scoring option is marked ★.

1. **Toast** (`:98185-98214`): Empire +2 · Returners +1 · **hometowns +5 ★**
2. **Kefka's fate** (`:98250-98272`): **jail +5 ★** · pardon +1 · execute +3
3. **Doma apology** (`:98283-98307`): done-is-done +1 ·
   **"That was inexcusable." +5 ★** · apologize-again +3
4. **Celes** (`:98320-98341`): spy +1 · **"CELES is one of us!" +5 ★** ·
   trust +3
5. **First question** (`:98342-98388`): any of the three = +2, and
   `$0231/$0232/$0233` records which was first (only this first pass sets
   them, `:98361-98363` etc.).
6. **"One more question please!" submenu** (`_cc8d09` `:98399-98452`):
   each new question +2 (`:98418/:98426/:98434`); re-asking an
   already-answered one = −10 (`sub_var 0,10`, `:98443`). Ask all
   three exactly once: +6 total across items 5-6 ★.
7. **Espers spiel** (`:98453-98473`): **"Yes, the Espers have gone too
   far." +5 ★** · "But you unleashed their power!!" +2
8. **Recall** (`:98474-98508`): the question is "which did you ask
   first?"; +5 only if the answer matches the `$0231/2/3` record ★, else 0.
9. **Rest break** (`:98519-98541`): no points either way, but the break is
   the only access to the troopers' challenge ★. Break path `_cc8e1d`
   disperses the party, control on (`:98543-98593`).
   - **Troopers' challenge** `_cc8a47` (`:98011-98044`): four
     EMPEROR_SERVANT NPCs at 251 (76,16)/(78,16)/(82,16)/(84,16)
     (`npc_prop.asm:11510-11540`), `$0237`-latched. "Sure" →
     `start_timer 0,7200,EventReturn` (reuses timer 0, which is free
     because the master timer is already stopped) → **battle 30** → same
     clean-win idiom → **+5 ★** → `stop_timer 0`.
   - Return to the table: walk-on trigger 251 (80,20)
     (`event_trigger.asm:1134` → `_cc8e63` `:98594`), "Shall we begin
     again?" → Yes (`$01B5` is the stand-on-tile re-arm, not a story
     latch).
10. **The favor** (`:98660-98692`): peace +3 ·
    **"That your war's truly over." +5 ★** · sorry +1
11. **Accompany Gestahl** (`:98746-98762`): **Yes on the first ask +3 ★**
    (`_cc8f5e`); "No" loops through `_cc8f53` and a later Yes scores 0.

Q&A maximum = 5+5+5+5+6+5+5+5+3 = **44**. Challenge = **+5**.

## 5. The ≥90 circuit, the rewards, and the probe

### 5.1 Reward ladder (`_cc91c0`, `:99146-99264`)

Always: South Figaro withdrawal `$0276=1` (`:99198`). Then
`cmp_var 0,50/67/77/90` at `:99199/:99211/:99224/:99237`:

- **≥50**: Doma withdrawal, `$0512=0 $0277=1` (`:99206-99210`)
- **≥67**: Imperial-base weapons, via `call _cb2566` (`:99222`), which is
  `switch $045D=0` (`:43943-43945`): `$045D` is the visibility switch of
  the "Locked…" object at 378 (53,40) (`npc_prop.asm:16845-16851`,
  `_cb2562` `:43938`). Clearing it opens the 13-chest annex. `$0278=1`.
- **≥77**: Tintinabar (`give_item`, `:99236`)
- **≥90**: Charm Bangle (`:99249`)

### 5.2 The circuit and the reward tier (what the savestate chain drives)

Absolute maximum = 44 (window) + 5 (challenge) + 44 (Q&A) = 93. The
window half is the scarce half, because the dinner reliably pays its 49 and
the score that reaches the messenger is window + 49. The tier thresholds
therefore translate into window requirements:

| tier | reward | needs window ≥ |
|---|---|---|
| ≥50 | Doma withdrawal | 1 |
| **≥67** | **Imperial-base weapons** | **18** |
| ≥77 | Tintinabar | 28 |
| ≥90 | Charm Bangle | 41 |

Canon is the ≥67 tier, at a driven total of 75 (window 26, 16 of
24 soldiers, in a driver that wastes frames). `$0276`,
`$0277` and `$0278` all pay; Tintinabar and the Charm Bangle do not,
and `banquet-done-v1` asserts their absence rather than their presence.
≥90 needs 41 of the window's 44 points, which is close to a perfect
circuit.

Three route constraints govern the window:

- Control returns inside the throne tower, a 199-tile pocket
  (x48..60, y9..35) whose only exits are the (53,9)/(55,9) doors to 251
  and the (53,35) long entrance back to the corridor at (23,11).
  Leaving it is the first step of the circuit, and it costs 393 frames.
- The castle is cut off until the window opens. Before `_cc8490`,
  map 250's entry is a 131-tile pocket: the west and east columns are
  blocked at (16,30) and (30,30) by the `$0630` "Gestahl waits
  inside" servants. `_cc8490` clears `$0630` at `event_main.asm:97415`,
  one line before `$007C=1`, so the castle opens when the timer
  starts and any route census taken earlier is invalid.
- Map 243 is a one-way pocket. Its (15,8) door into 250 was opened by
  the escort's transient `mod_bg_tiles` (`_cc835c`, `:97070`), and a
  re-entry shows the closed door with no reachable exit. 243 must be
  visited last, and the (22..24,34) door row must be routed around until
  then.

Per-unit costs (timer `$1189`, counting down from 14400):

| item | cost |
|---|---|
| window at first controlled frame | **14302** |
| throne-tower exit | 393 |
| a talk, including its approach | ~210 avg (4 nearest: 836) |
| a talk's dialog alone | ~110-130 |
| field walking | ~16 frames/tile |
| region traversals from the corridor | 38-62 **steps each way** |

1. Enter 250, face UP + A at (54,16). Play through the Gestahl/Cid scene.
   Timer starts on scene end (`:97420`), control returns in the throne
   pocket.
2. Window (≤14400 frames, ticking through dialogs, menus and battles, and
   frozen only on the world map, which the circuit never visits): talk to
   as many of the 24 soldiers of the §3 table as the clock allows, and win
   the fights taken. Suggested order: leave the throne pocket by (53,35)
   → dais room four (21/25,18/24) → stairs (15,21)→(24,52) → west wing →
   (9,14)→252, six there incl. battle 27 → 252 (35,60)→250 (9,16) →
   (9,52)→244, five there → 244 (13,19)→250 → back through 250 east:
   (31,21)→(81,59) region for
   (98,51)/(110,51)/(115,16)/(120,13)/(9,49)/(51,50) → **243 last**,
   three there incl. battle 26.
   Assert after each fight: `$1dd1 & $31 == 0` (b-switches $40/$44/$45
   all clear) and var0 delta == +6 (+1 talk, +5 clean).
   Checkpoint: var0 ≥ 18 before expiry.
3. Let the timer expire anywhere in the castle, party halted (CheckTimer
   requires a halted party and no running event). Play through: map 5
   "That evening…" → map 251 dinner.
4. Q&A, choices by index: toast **2** (hometowns) · Kefka **0** (jail) ·
   Doma **1** (inexcusable) · Celes **1** (one of us) · first question:
   any, say **0**, and remember it · "One more question please!" twice,
   asking the other two questions exactly once each; never repeat one
   (−10) · then "Okay."/"Let's talk about Espers…" · Espers **0** (gone
   too far) · recall: answer with the question asked first (+5) ·
   Cid's break offer: **0** (take the break).
5. Break: walk to any trooper at 251 (76/78/82/84,16), "Sure", win
   battle 30 inside its 2-minute timer (same b-switch assert). Return to
   (80,20), "Yes".
6. Wish: **1** ("That your war's truly over.") · Accompany: **0** (Yes,
   first ask). var0 now 93.
7. Play through the Leo intro (party-conditional lines for SABIN `$01A5`
   and CYAN `$01A2`, `:98820-98835`), the roster rewrite, and the
   TERRA+LOCKE scene. Control returns on 251 as a 2-person party,
   `$007D=1`.
8. Walk out; at 250 (23,12) the messenger fires: assert `$0276/$0277/
   $0278=1`, Tintinabar and Charm Bangle absent from inventory,
   `$0238=1`, var0 back to 0.

Timing constraints, for the gen's asserts: the window
budget is 14400 frames minus the battles taken (timer runs in-battle);
battle 30 has its own 7200; a battle still running when its timer expires
ends with `$45` set, which loses the points but wedges nothing. The fights
are the only variable-cost item, so they are what to accelerate.

### 5.3 The timer across save, reset and load

This behaviour needs no entry in `vanilla-destructive-bugs.md`.

- The world map does not tick a live timer; menus tick it 1:1.
- A completed save carries the live `$1188-$119F` block into SRAM (slot
  bytes `72 xx xx 96 8A 02` with the counter mid-tick, score var intact)
  and the in-session timer keeps running afterwards. Entering the save
  screen and backing out leaves the live timer untouched.
- Cold power-on → Continue restores the block byte-for-byte via
  `PopTimers`, minus the frames the load menu itself ticks.
- Entering an ordinary field map resumes the countdown 1:1, and expiry
  fires the restored callback from wherever the party stands: `$013C=1`,
  map 5 "That evening…", dinner hall 251. `CheckTimer` only compares
  against zero, so the path is value-independent.

A player who walks out mid-window and saves loses nothing: reset plus
Continue resumes the countdown, and the dinner collects the party from
wherever they are. Two behavioral notes belong in the release notes,
neither destructive: the world map pauses the banquet clock indefinitely
(a mild exploit), and a mid-window exit cannot be reversed by walking back
into the castle (§1), so the dinner teleport is what recovers the player.

**Standing harness rule: any save made inside a timer window must drive
the menu with pad input only.** The checkpoint-generating save idiom that
force-writes `ZMENUSTATE=$13` to enter the save selector corrupts the
live `$1188-$119F` block, because leftover menu-state tasks write over it
(bank-C3 writers at C3/E04F+E052 and RAM-stub block moves; exact task
unidentified). The SRAM copy is written first (`PushTimers`
precedes it) and stays correct, which is why checkpoints without a live
timer are unaffected.

No fixture boundary belongs inside the block. Transient switches
(`$013C`, `$0230-$0237`, ladder slots) plus a live timer are not a
suitable place for a checkpoint.

### 5.4 Battles 26/27/30 — contents, loseability, gen asserts

Event battle groups map 1:1, no 3/4-1/4 alternate
(`event_battle_group.dat`): 26→408, 27→418, 30→157. Decode is
`battle_monsters.dat` +1 present-mask, +2..+7 ids, +14 msb;
`battle_prop.dat` aux = `0000` for all three (run allowed, no special
flags). Battles are forceable with the `EventBattle` RAM recipe
`$11e0/$11e2/$078a/$56` (`field/event.asm:1910-1942`):

| battle | formation | live contents | monster row (`monster_prop.dat`) |
|---|---|---|---|
| 26 | 408 | 1× Mega Armor `$102`, HP 1000 | L21, absorb none, weak bolt+water (`$84`) |
| 27 ×3 | 418 | 1× Commando `$0c7`, HP 580 | L18, absorb none, weak bolt+water (`$84`) |
| 30 | 157 | 3× Sp Forces `$0c2`, HP 700 each | L21, absorb none, weak poison (`$08`) |

Clean kills end with `$1dd1 = $00`, meaning b-switches $40/$44/$45 are all
clear. Loseability: a wipe is not a game over
(§3). The script continues, the +5 is skipped, the +1 still lands, and
the party walks away from the fade-in. The gen must assert, per fight, that the formation
words match (species `$102`/`$0c7`/`$0c2` at `$3F46+`), and on the win
that `$1dd1 & $31 == 0` and the var0 delta is +6. A win that arrived by
timer-expiry or wipe must fail the segment rather than pass with a lower
tier.
