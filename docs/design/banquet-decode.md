# The Imperial banquet, decoded and probed

Issue #31 probe-first item, 2026-07-28. Source decode of the whole banquet
block (maps 243/244/250/251/252, `$007C=1` → `$0238=1`), the derived ≥90
scoring circuit, the timer save/reset/load probe (run, with verdict), and
live verification of battles 26/27/30. Written from this worktree
(`wt/v07-banquet`, main @ 97f6d6e); line numbers are from that tree. Claims
cite `file:line` or sit in the unverified ledger (§8). Probes live at
`tools/tests/probe_banquet_*.lua` (§7) and their logs are quoted inline.

Companion to `sealed-gate-recon.md` §1 leg 6; corrections to it in §6.

---

## 1. State machine: how the block enters and leaves

| step | where | latch | evidence |
|---|---|---|---|
| castle escort | 243 (8,18) trigger | `$013A=1`, `$062F=1`, opens the 243 (15,8) door via `mod_bg_tiles {14,8}` | `event_trigger.asm:1094` → `_cc835c`, `event_main.asm:97039-97078` |
| 250 first entry | map-init | `$013B=1`, `$062D=0`, opens a door at {22,29} | `map_init_event.asm:269` → `_cc839e`, `:97079-97098` |
| banquet start | 250 (54,16), face-UP+A on the dais | `$007C=1`, `set_var 0,0`, `start_timer 0,14400,_cc8a96,{FIELD_VISIBLE,BANQUET,MENU_BATTLE_VISIBLE}`, `$0634=1` (window soldiers appear), `$062E/$0630=0` | `event_trigger.asm:1123` → `_cc8490` `:97242`; gates `:97243-97247` (`$01B4`,`$01B0`,`$007C=0`); tail `:97414-97420` |
| the 4-minute circuit | maps 243/244/250/252 | per-soldier latches `$0217-$022E`, talk counter rungs `$014F,$0200-$0216` | §2, §3 |
| dinner | timer-0 expiry, wherever the party stands | `stop_timer 0`, **`$013C=1`** (kills all further soldier scoring), `load_map 5` "That evening…", `$062C=1`, `load_map 251 {80,25}` | `_cc8a96` `:98045-98069` |
| Q&A + challenge | 251 dinner table | `$0230-$0236` question bookkeeping, `$0237` challenge latch, `$01B5` table-trigger re-arm | §4 |
| roster rewrite | Q&A tail | `$02F0-$02F9` forced (`:98934-98943`), `norm_lvl LOCKE/TERRA` (`:98944-98945`), `remove_equip CYAN/EDGAR/SABIN/SETZER` (`:98953-98956`, GAU `:98920`, MOG `:98932`), `char_party` → TERRA+LOCKE only (`:99079-99101`), **`$007D=1`** (`:99133`), control back on 251 (`:99142-99144`) |
| the messenger | 250 (23,12) walk-on | reward ladder (§5.1), `set_var 0,0`, **`$0238=1`** | `event_trigger.asm:1131` → `_cc91c0` `:99146-99264`; gated `$007D=1 && $0238=0` `:99147-99150` |

**The block is exit-able but one-way.** The 243 south rows
(11-19,31) are `_cc9359` (`event_trigger.asm:1095-1103`), which with
`$007B=1` is just `load_map 253 {29,2}` (`:99389-99395`) — no `$007C` gate.
253's world exit is an ordinary 12-wide long entrance (30,63) → world
(120,188) (`long_entrance.dat` map-253 block). So a player mid-window can
reach the saveable world map. Coming *back* is doubtful: the 243 (15,8)
door into 250 was opened by `_cc835c`'s transient `mod_bg_tiles`, 243's
map-init is `EventReturn` (`map_init_event.asm:262`) and the escort is
`$013A`-latched dead, so a reload of 243 shows the static (closed) door
(passability of the closed tiles: unverified, §8). It does not matter for
progress: the timer callback collects the party from **any field map** —
measured, §5.3 B4.

**No early-out exists.** The only writer of `$013C=1` in the game is
`_cc8a96` itself (`:98047`; every other grep hit is an `if_any` condition),
and `_cc8a96` is reached only as the timer-0 callback. The recon's
UNVERIFIED "no early-out found" is now verified: the 14400-frame timer is a
hard floor on leg I→J. All 24 soldier scripts and every castle trigger were
read.

## 2. The timer machinery ($1188 family)

Timer 0 block, written by event command `$a0` (`start_timer`,
`field/event.asm:3736-3757`): `$1188` flags = `pfrmxxee` (p=pause in
menu/battle, f=field-visible, r=**banquet**, m=menu/battle-visible, xx=timer
number, ee=event-pointer bits 16-17), `$1189/8A` frame counter,
`$118B/8C/8D` callback as a +$CA0000 event offset. The banquet's call
encodes flags `$72`, ptr `$028A96` (= `_cc8a96`). Timers 1-3 follow at +6
(`$118E`, `$1194`, `$119A`).

Who ticks and fires it, per module — this is the whole
save/reset/load story:

- **field**: `CheckTimer` + `DecTimers` every frame
  (`field/reset.asm:96-98`; `field/event.asm:5656-5674, 5680-5732`).
  `CheckTimer` fires the callback only when the counter is 0, an event
  pointer is set, no other event is running, and the party is halted.
- **menu**: `DecTimersMenuBattle` (`field/event.asm:5562-5650`, called
  `menu/menu_common.asm:3466`) — bit7 clear means the banquet timer ticks
  through menus; `CheckEventTimer` (`menu_common.asm:425-444`) force-closes
  the menu when a bit-$20 timer hits 0.
- **battle**: same tick (`btlgfx/btlgfx_main.asm:1628,2231`); expiry raises
  `$1dd1` bit5, and `CheckBattleEnd` force-ends the fight and sets `$3ebc
  |= $20` (`battle/battle_main.asm:12049-12053`) — that is b-switch `$45`,
  the "flash BLUE, no points" path in the field scripts.
- **world**: **nothing**. No `DecTimers`/`CheckTimer` caller exists in
  `ff6/src/world/`, and it is measured: 150 idle world frames leave the
  counter untouched (§5.3 A1, B2). The countdown freezes on the world map
  and resumes on the next field map.

Save/load: `CopyGameDataToSRAM` runs `PushTimers` — `$1188-$119F` →
`$1FA8-$1FBF`, inside the saved `$1600-$1FFF` block
(`menu/save.asm:42-75, 108-115`); `LoadSavedGame` runs `PopTimers` back
(`:18-34, 121-128`). The score variable (var 0 = `$1FC2`,
`field/event.asm:4453-4523`) and every `$007x/$01xx/$02xx` switch
(`$1E80+`) also live inside that block. Only `InitNewGame` clears timers
(`field/init.asm:184-200`); `InitSavedGame` does not. Vanilla built the
banquet timer to survive a battery cycle — and it does (§5.3).

## 3. The soldier circuit — every scoring branch

Score = event variable 0 (`$1FC2`). Zeroed at `$007C=1` (`:97419`) and
after the rewards (`:99261`).

**The talk counter is one global 24-rung ladder**, `_cc88bf`
(`:97835-98002`): each call takes the next unclaimed rung
(`$014F`, then `$0200-$0216`), `add_var 0,1`, and toasts "N people".
Exactly 24 callers exist, each latching its own switch first, so ladder
capacity = caller count = 24. Scoring is confined to the window by two
complementary mechanisms: the `$062F`-population scripts (latches
`$0217-$0223`, plus `_cc873b`/`_cc8782`) each gate on
`$007C=1 && $013C=0` because their NPCs exist outside the window too,
while the `$0634`-population scripts (the other nine) gate only on their
own latch — their NPCs exist *only* inside the window (`$0634` set
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

24 rows: 20 talks + 4 fights. Window maximum = 24 + 4×5 = **44**.
Not scoring: the two dais servants 250 (52,13)/(56,13)
(`_cc83ca/_cc83d4` → "Dinner preparations underway", `:97103-97119`),
the 250 (23,31) / (16,30) / (30,30) "Gestahl waits inside" servants, the
250 (76,56) Kefka-cell scene (`_cc83e8` `:97120-97241`, pure theater), and
the four (x,49-50) jump-scare floor triggers (`_cc8342`,
`event_trigger.asm:1127-1130`).

**The clean-win idiom** after each fight (`battle 26` at `:97678`;
`battle 27` at `:97730/:97763/:97805`; `battle 30` at `:98022`):
`if_b_switch $NN, next` **jumps when the flag is CLEAR**
(EventCmd `$b7`, `field/event.asm:4053-4073`; macro
`event_cmd.inc:774-777`). So the +5 is reached only when **$40, $45 and
$44 are all clear**; any set flag flashes RED/BLUE/GREEN and skips the
points (the `if_switch $022F=0, skip` lines are unconditional in practice —
`$022F` is never set anywhere in the ROM). The three flags, from the
battle side ($3eb4-block, copied to `$1dc9+` at battle end,
`battle_main.asm:12307-12311`, and seeded from it at init `:6103-6106`):

- `$40` = `$3ebc` bit0, set by `LoseBattle` ("game over after battle
  ends", `:15756-15759`) — the party was wiped;
- `$44` = bit4, set by `BattleEnd_01` — literally commented "ran out of
  time before emperor's banquet" (`:12121-12125`);
- `$45` = bit5, set when a BANQUET-flag timer expires mid-battle
  (`:12049-12053`).

Losing costs the +5 but **not the game**: none of the five banquet battle
scripts calls `_ca5ea9`/`GameOver` (contrast `RandBattle`,
`event_main.asm:107-125`, which is where b-switch `$40` normally becomes a
game over); each falls through to `fade_in` + a canned line + `_cc88bf`
(the +1 lands even on a loss).

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

## 4. The dinner Q&A tree — every choice, every value

Choice targets are in listed order (`choice` macro,
`event_cmd.inc:746-772`); "best" marked ★.

1. **Toast** (`:98185-98214`): Empire +2 · Returners +1 · **hometowns +5 ★**
2. **Kefka's fate** (`:98250-98272`): **jail +5 ★** · pardon +1 · execute +3
3. **Doma apology** (`:98283-98307`): done-is-done +1 ·
   **"That was inexcusable." +5 ★** · apologize-again +3
4. **Celes** (`:98320-98341`): spy +1 · **"CELES is one of us!" +5 ★** ·
   trust +3
5. **First question** (`:98342-98388`): any of the three = +2, and
   `$0231/$0232/$0233` records WHICH was first (only this first pass sets
   them, `:98361-98363` etc.).
6. **"One more question please!" submenu** (`_cc8d09` `:98399-98452`):
   each *new* question +2 (`:98418/:98426/:98434`); re-asking an
   already-answered one = **−10** (`sub_var 0,10`, `:98443`). Ask all
   three exactly once: +6 total across items 5-6 ★.
7. **Espers spiel** (`:98453-98473`): **"Yes, the Espers have gone too
   far." +5 ★** · "But you unleashed their power!!" +2
8. **Recall** (`:98474-98508`): "which did you ask first?" — +5 only if
   the answer matches the `$0231/2/3` record ★, else 0.
9. **Rest break** (`:98519-98541`): no points either way, but the break is
   the ONLY access to the troopers' challenge ★. Break path `_cc8e1d`
   disperses the party, control on (`:98543-98593`).
   - **Troopers' challenge** `_cc8a47` (`:98011-98044`): four
     EMPEROR_SERVANT NPCs at 251 (76,16)/(78,16)/(82,16)/(84,16)
     (`npc_prop.asm:11510-11540`), `$0237`-latched. "Sure" →
     `start_timer 0,7200,EventReturn` (reuses timer 0 — the master is
     already stopped) → **battle 30** → same clean-win idiom → **+5 ★**
     → `stop_timer 0`.
   - Return to the table: walk-on trigger 251 (80,20)
     (`event_trigger.asm:1134` → `_cc8e63` `:98594`), "Shall we begin
     again?" → Yes (`$01B5` is the stand-on-tile re-arm, not a story
     latch).
10. **The favor** (`:98660-98692`): peace +3 ·
    **"That your war's truly over." +5 ★** · sorry +1
11. **Accompany Gestahl** (`:98746-98762`): **Yes on the FIRST ask +3 ★**
    (`_cc8f5e`); "No" loops through `_cc8f53` and a later Yes scores 0.

Q&A maximum = 5+5+5+5+6+5+5+5+3 = **44**. Challenge = **+5**.

## 5. The ≥90 circuit, the rewards, and the probe

### 5.1 Reward ladder (`_cc91c0`, `:99146-99264`)

Always: South Figaro withdrawal `$0276=1` (`:99198`). Then
`cmp_var 0,50/67/77/90` at `:99199/:99211/:99224/:99237`:

- **≥50**: Doma withdrawal, `$0512=0 $0277=1` (`:99206-99210`)
- **≥67**: Imperial-base weapons — `call _cb2566` (`:99222`), which is just
  `switch $045D=0` (`:43943-43945`): `$045D` is the visibility switch of
  the "Locked…" object at 378 (53,40) (`npc_prop.asm:16845-16851`,
  `_cb2562` `:43938`). Clearing it opens the 13-chest annex. `$0278=1`.
- **≥77**: Tintinabar (`give_item`, `:99236`)
- **≥90**: **Charm Bangle** (`:99249`)

### 5.2 The ≥90 walkthrough (frontier canon)

Absolute maximum = 44 (window) + 5 (challenge) + 44 (Q&A) = **93**.
≥90 leaves **3 points of slack**, so: all four window battles clean, the
challenge clean, and a perfect Q&A are all mandatory (each is worth ≥5);
the slack allows at most 3 dropped talk-points (or the +3 accompany).
Simplest robust policy for the gen: **take all 93 and assert ≥90.**

1. Enter 250, face UP + A at (54,16). Ride the Gestahl/Cid scene. Timer
   starts on scene end (`:97420`), control returns at the dais.
2. Window (≤14400 frames, ticking through dialogs, menus, battles —
   frozen only on the world map, which the circuit never visits): talk to
   all 24 soldiers of the §3 table and WIN the four fights. Suggested
   order (passability inside 250 is mod-free but live-unverified — census
   at mint): dais room four (21/25,18/24) → stairs (15,21)→(24,52) →
   west wing → (9,14)→252, six there incl. battle 27 → 252 (35,60)→250
   (9,16) → (9,52)→244, five there → 244 (13,19)→250 → (22,34)→243,
   three there incl. battle 26 → back through 250 east: (31,21)→(81,59)
   region for (98,51)/(110,51)/(115,16)/(120,13)/(9,49)/(51,50).
   Assert after each fight: `$1dd1 & $31 == 0` (b-switches $40/$44/$45
   all clear) AND var0 delta == +6 (+1 talk, +5 clean).
   Checkpoint: var0 == 44 before expiry, with all 24 latches set.
3. Let the timer expire anywhere in the castle, party halted (CheckTimer
   requires a halted party and no running event). Ride: map 5 "That
   evening…" → map 251 dinner.
4. Q&A, choices by index: toast **2** (hometowns) · Kefka **0** (jail) ·
   Doma **1** (inexcusable) · Celes **1** (one of us) · first question:
   any, say **0** — remember it · "One more question please!" twice,
   asking the OTHER two questions exactly once each; never repeat one
   (−10) · then "Okay."/"Let's talk about Espers…" · Espers **0** (gone
   too far) · recall: answer with the question asked first (+5) ·
   Cid's break offer: **0** (take the break).
5. Break: walk to any trooper at 251 (76/78/82/84,16), "Sure", win
   battle 30 inside its 2-minute timer (same b-switch assert). Return to
   (80,20), "Yes".
6. Wish: **1** ("That your war's truly over.") · Accompany: **0** (Yes,
   first ask). var0 now 93.
7. Ride the Leo intro (party-conditional lines for SABIN `$01A5` and CYAN
   `$01A2`, `:98820-98835`), the roster rewrite, the TERRA+LOCKE scene.
   Control returns on 251 as a 2-person party, `$007D=1`.
8. Walk out; at 250 (23,12) the messenger fires: assert `$0276/$0277/
   $0278=1`, Tintinabar and Charm Bangle in inventory, `$0238=1`,
   var0 back to 0.

Timing constraints, for the gen's asserts rather than hopes: the window
budget is 14400 frames minus four battles (timer runs in-battle); battle
30 has its own 7200; a battle still running when its timer dies ends with
`$45` set — points lost but nothing wedges. Whether 24 talks + 4 real
(non-kill-bit) wins fit in 4 minutes for the real leg party is a
mint-time measurement (§8); if it proves tight, the fights are the thing
to accelerate — they are the only variable-cost item.

### 5.3 The timer save/reset/load probe — verdict: **benign, by design**

`vanilla-destructive-bugs.md` gets **no new entry**. The full result set:

**Staging (stated honestly).** The banquet is five unminted legs
downstream of `terra-returned-v1`, so no probe reached it naturally.
Staging: cold-Continue the terra-returned battery (world (24,121), on
foot), hand-write timer 0 exactly as `start_timer 0,N,_cc8a96,{…}` would
(flags `$72`, ptr `$028A96`), plus score var 0 = 17. This proves the
**save/load mechanism for a live banquet timer**; it does NOT prove
banquet reachability, the castle-exit walk, or dinner-scene coherence for
a mid-window party — the exit rows are source-cited (§1) and the dinner
ride was only taken to its first latch. The staged save was written by the
real Save UI via **pure pad input** (see the harness hazard below).

Measured, all logs in the probe headers' run lines:

- **A1/B2** — the world map does not tick a live timer (150 idle frames,
  counter byte-identical; twice, either side of a battery cycle).
- **A2** — menus tick it 1:1 (120 frames in the world menu = 120 counts).
- **A3** — a natural completed save carries the live block into SRAM:
  slot-3 bytes `72 xx xx 96 8A 02` with the counter mid-tick, score var
  intact; the in-session timer keeps running afterwards
  (`probe_banquet_timer_save.lua`: WRAM `72 … count=4955` after menu
  close, SRAM `72 count=5089`).
- **Cancel-only visit** — entering the save screen and backing out leaves
  the live timer untouched (`probe_banquet_timer_cancel.lua`).
- **B1** — cold power-on → Continue restores the block byte-for-byte via
  `PopTimers` minus the 76 frames the load menu itself ticked
  (battery 5089 → WRAM 5013 at first world frame).
- **B3** — entering an ordinary field map (198, a town the banquet never
  visits) resumes the countdown 1:1.
- **B4** — expiry fires the restored callback from that town: `$013C=1`,
  map 5 "That evening…", dinner hall 251 loaded. The counter was forced
  to 240 to bound the wait — `CheckTimer` only compares against zero, so
  the path is value-independent.

So: a player who walks out mid-window and saves loses nothing — reset +
Continue resumes the countdown and the dinner collects the party from
wherever they are. Two behavioral notes worth the release notes, neither
destructive: the world map **pauses** the banquet clock indefinitely
(mild exploit), and a mid-window exit is one-way back into the castle
(§1) — the dinner teleport is what un-strands the player.

**Harness hazard found on the way** (this, not vanilla, was the scary
reading): the anchor-gen save idiom that force-writes `ZMENUSTATE=$13`
to enter the save selector **corrupts the live `$1188-$119F` block** —
leftover menu-state tasks scribble on it (write-watch caught bank-C3
writers at C3/E04F+E052 and RAM-stub block moves; exact task
unidentified, ledger §8). The SRAM copy is written first (`PushTimers`
precedes) and stays correct, which is why every existing anchor is
unaffected — no anchor has a live timer. Rule for future gens: **any
save made inside a timer window must drive the menu with pad input
only** (`probe_banquet_timer_save.lua` is the template; the poke variant
`probe_banquet_timer.lua` is kept as the failing counter-example, and
`probe_banquet_timerwatch.lua` is the instrument).

### 5.4 Battles 26/27/30 — contents, loseability, gen asserts

Event battle groups map 1:1, no 3/4-1/4 alternate
(`event_battle_group.dat`): 26→408, 27→418, 30→157. Offline decode
(`battle_monsters.dat` +1 present-mask, +2..+7 ids, +14 msb;
`battle_prop.dat` aux = `0000` for all three: run allowed, no special
flags) **confirmed live** (`probe_banquet_battles.lua`, forced via the
`EventBattle` RAM recipe `$11e0/$11e2/$078a/$56`, `field/event.asm:
1910-1942`):

| battle | formation | live contents | monster row (`monster_prop.dat`) |
|---|---|---|---|
| 26 | 408 | 1× Mega Armor `$102`, HP 1000 | L21, absorb none, weak bolt+water (`$84`) |
| 27 ×3 | 418 | 1× Commando `$0c7`, HP 580 | L18, absorb none, weak bolt+water (`$84`) |
| 30 | 157 | 3× Sp Forces `$0c2`, HP 700 each | L21, absorb none, weak poison (`$08`) |

Clean kill-bit wins end with `$1dd1 = $00` — b-switches $40/$44/$45 all
clear (measured, all three). Loseability: a wipe is NOT a game over
(§3) — the script continues, the +5 is skipped, the +1 still lands, and
the party walks away from the fade-in (post-loss party HP state:
unverified, ledger). **The gen must assert, per fight:** formation words
match (species `$102`/`$0c7`/`$0c2` at `$3F46+`), and on the win
`$1dd1 & $31 == 0` plus the var0 +6 delta — a "win" that arrived by
timer-expiry or wipe must fail the leg, not pass quietly with a lower
tier.

## 6. Corrections to sealed-gate-recon.md

1. **"+5 on win" is really "+5 on clean win, flags inverted":**
   `if_b_switch` branches when the flag is CLEAR, so the recon's "outcome
   read via `$40/$45/$44`, +5 clean win" had the right conclusion but the
   bits are *failure* flags (wipe / banquet-time-up / timer-ended), all
   required clear. Practical consequence for the gen is the §5.4 assert.
2. **"~27 soldier NPCs spread across five maps 243,244,250,251,252"** →
   exactly **24 scoring soldiers on four maps** (243/244/250/252). 251 is
   the dinner hall; its only scoring content is the troopers' challenge.
3. **"24 `add_var 0,1` sites"** → one 24-rung global ladder (`_cc88bf`);
   the distinction matters because the +1 is capped by rung exhaustion,
   not by NPC count.
4. **"two live timers"** → the challenge reuses timer 0 after the master
   is stopped; at most one timer is ever live, which is why the
   save-probe only had to stage one block.
5. **Base treasure unlock mechanism (recon §1 leg 2 "unread")**: answered —
   `_cb2566` clears `$045D`, the "Locked…" object at 378 (53,40).
6. **Hazard 1's open question** (save/reset/load inside the window) is
   settled benign (§5.3); the hazard's "two event timers … callback
   teleports the party" stands otherwise as written, and the #10
   no-anchor-inside-the-block prohibition is unchanged — transient
   switches (`$013C`, `$0230-$0237`, ladder rungs) plus a live timer are
   still no place for a fixture boundary.
7. Recon line refs `:97678/:97730/:97763/:97805` (fight sites) and
   `:99199/:99211/:99224/:99237` (thresholds) re-verified exact.

## 7. Probe inventory (this worktree)

| file | role | result |
|---|---|---|
| `tools/tests/probe_banquet_timer.lua` | phase A: stage live timer, world/menu tick, poked save drive | PASS; also the counter-example — poked drive corrupts live WRAM timer |
| `tools/tests/probe_banquet_timerwatch.lua` | write-watcher + per-frame sampler over `$1188-$119F` through the save | writer census (C0/BB57 ticks; C3/E04F+E052 + MVN stub on the poked path) |
| `tools/tests/probe_banquet_timer_cancel.lua` | natural navigation, save screen visit, cancel | timer survives |
| `tools/tests/probe_banquet_timer_save.lua` | natural pad-input completed save; captured the phase-B battery | timer survives in-session AND in SRAM |
| `tools/tests/probe_banquet_timer2.lua` | phase B: cold boot the captured battery; B1-B4 | PASS end-to-end (restore, freeze, resume, fire) |
| `tools/tests/probe_banquet_battles.lua` | force battles 26/27/30, live formation + clean-win flags | PASS, table §5.4 |

Run lines are in each header. Phase A→B chaining:
`probe_banquet_timer_save` with `OT6_CAPTURE_SRM=build/states/
banquet_timer_live.srm`, then wrap the capture as an anchor dir
(manifest schema `ot6.sram-anchor/v1`, layout `ot6-codex-o8-v1`) for
`OT6_SRAM_ANCHOR` — the phase-B manifest self-describes as staged, not a
route state. None is a suite test; none is frontier input.

## 8. Unverified-claims ledger

- **Window feasibility**: 24 talks + 4 real wins inside 14400 frames for
  the real leg party (TERRA/LOCKE/EDGAR/SABIN at band levels) is
  UNMEASURED. The only full-circuit timing evidence will be the mint
  itself. If ≥90 proves undrivable in-window, the score policy decision
  (recon open question 5) reopens.
- **250's interior passability / route order** between the coordinate
  clusters in §5.2 is derived from entrances + NPC coordinates only; no
  live census. 250 is not a `mod_bg_tiles` map (its init is `_cc839e`,
  one door, latched), so offline reading should hold — but the v0.6
  precedent says census at mint anyway.
- **The closed 243 (15,8) door after a mid-window re-entry**: presumed
  impassable (static tilemap, no re-opening init). Untested; only
  matters for a player who exits and tries to return before expiry.
- **Post-loss party state** after a lost banquet fight (HP floor,
  status) — unread and unmeasured; the gen never loses, players can.
- **`$44`'s full trigger set**: `BattleEnd_01` is also reachable via the
  battle-end special-event table (`$3a6e`) and a sneeze path
  (`battle_main.asm:12065-12066`); which in-battle mechanism (if any)
  sets `$3a6e=1` for these formations was not traced. All observed clean
  wins leave it clear.
- **The C3/E04F writer's identity** in the poked-menu corruption (§5.3):
  caught by PC, not attributed to a named routine; the dbg-symbol
  neighborhood suggests a redraw task running with a stale index. The
  behavioral rule (pad-input saves inside timer windows) does not depend
  on the attribution.
- **Dinner-scene coherence when fired from an arbitrary map** was ridden
  only to the 251 load with a non-banquet party (staged). The real leg
  fires it inside the castle with the real party; nothing suggests
  map-of-origin sensitivity beyond what B4 exercised, but the full scene
  was not ridden in staging.
- **Menu tick during the save-slot screens** was measured only for the
  top menu (A2); the selector screens also call `DecTimersMenuBattle`
  (same loop) and the observed SRAM-vs-stage deltas are consistent with
  continuous ticking, but no per-screen breakdown was taken.
