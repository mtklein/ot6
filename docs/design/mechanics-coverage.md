<!-- Maintained inventory: update when a mechanic moves class or an issue lands. -->
# FF6 mechanics coverage inventory (2026-09-16)

Read-only audit of the harness against the FF6 mechanic space, taken after the
back-attack hang (#185). Classes: HANDLED / ASSUMED / UNHANDLED / PARTIAL / N-A.
Every driver change is planned and gated from this table; a mechanic listed here
is a known gap with an issue, never a surprise.

Issues filed from this audit (2026-09-16): #185 back attack / layout-independent
target steer; #186 side attack, preemptive, arrangement audit; #187 Stop / Sleep /
Berserk / Imp; #188 command windows outside KNOWN_ST and the unknown-menu count;
#189 multi-part monsters; #190 promote generator-local reads into the lib;
#191 shop buyItem by item id.

# OT6 harness coverage inventory — the FF6 mechanic space vs. what the driver reads

Scope: `tools/tests/lib/ot6.lua` (battle/driver), `tools/tests/lib/ot6_field.lua` (field/world), `tools/tests/lib/ot6_contract.lua`, 91 `tools/tests/gen_*.lua`, plus the static audits in `tools/*.py`. Game side cited from `ff6/src`, `ff6/include`, `ff6/notes`.

**Classification key:** HANDLED = code reads the live state and branches on it. ASSUMED = code hard-codes one case. UNHANDLED = nothing reads it. PARTIAL = read in one generator/probe but not in the lib, so it does not generalize.

---

## A. Battle arrangements and initiative

| Mechanic | Defining game source | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| Battle type selection (the roll) | `ff6/src/battle/battle_main.asm:7799-7821` `ChooseBattleType` — masks `$2F48`, rolls `RandBitWithRate`, `stx $201f` (:7820) | HANDLED | `lib/ot6.lua` `M.battleLayout` reads `$201F` and `$7ACE`; the driver logs it once the command window is up and every crossing press comes from it. Measured: `[healerdown] [layout] battle type $00 (normal): the monsters stand left of the party; from the party side the cursor crosses with left, and back with right ($201F=00 $7ACE=00)`; `[j39 back attack] [layout] battle type $01 (back attack): the monsters stand RIGHT of the party (back attack); from the party side the cursor crosses with right, and back with left ($201F=01 $7ACE=00)` -> `the cursor is on the MONSTER side at f493: mons=10 chars=00`, `PASS (frame 2616)` (`probe_backattack_j39`, the potion-route snapshot). `battle_healpolicy` asserts all four types' directions | every random encounter on every walked map, world and field | **#185** (the symptom) |
| Normal arrangement (`$201F=0`) | `battle_main.asm:7864` `InitBattleType_00` | HANDLED | read, not assumed: `M.battleLayout` type 0 -> LEFT to the monsters, RIGHT back (btlgfx `_c174bf` / `_c175a3`); the `[layout] battle type $00 (normal)` line above in every suite fight and lab batch (m269 fix4/fix5, Nerapa fix4: unchanged seed for seed) | everywhere | **#185** |
| **Back attack** (`$201F=1`) | `battle_main.asm:7900-7909` `InitBattleType_01`: toggles every `$3AA1.5` row bit, `lda #$20 / tsb $b1` (:7907-7908). Enable bit = `$2F48` bit 5 (`battle-ram.txt:567`) | HANDLED | `M.battleLayout` type 1 -> RIGHT to the monsters, LEFT back (btlgfx `_c17439` / `_c17669`; LEFT from the party side is `_c174e9: rts`). Before: `left pressed twice in target select with no effect (window 01:00:00:01, layout back attack)` x3 then the recovery cap; after: the `[layout] ... back attack` line and the win quoted above | any non-scripted encounter: Narshe mines, Mt Kolts, Lete, both scenario legs, Zozo, Magitek Factory, esper tubes, minecart, Sealed Gate cave, Thamasa/Esper Mtn, FC | **#185** fixed on wt/driver-boost |
| **Pincer** (`$201F=2`) | `battle_main.asm:7889-7896` `InitBattleType_02` — forces every character front row, then `tsb $b1 #$20`. Also sets `$b1` bit 1 via `UpdateMonsterGfxBuf` when monsters live on both sides | HANDLED (cursor, by the jump tables) / PARTIAL (measured) | `M.battleLayout` type 2 -> either LEFT or RIGHT crosses (btlgfx `_c174bf` / `_c17439`, monsters on both sides); a direction that moves nothing twice is skipped. Flee half as before (`ot6_field.lua:148,159`). No pincer fixture in the tree: the arithmetic is asserted (`battle_healpolicy`), the live cross is not yet measured | Thamasa ambush (`gen_thamasa_fire`), `gen_mrf_chute:269`, Zozo clock shaft (`gen_zozo3_clock:41`), any pool `audit_encounters` flags | **#185**; #150 (closed), #82 (closed) |
| **Side attack** (`$201F=3`) | `battle_main.asm:7865` (shares `InitBattleType_00`), enable bit `$2F48` bit 7; disabled when fewer than 3 allies alive (`:7811-7818`). Raises run difficulty per monster (`:15645-15646`) | HANDLED (cursor, by the jump tables) / PARTIAL (measured) | `M.battleLayout` type 3 -> by the group `$7ACE`: 1 (left party group) crosses RIGHT (`_c174ea` returns on LEFT), 3 crosses LEFT (`_c17463` returns on RIGHT), else either; re-read each press since the group moves. Asserted in `battle_healpolicy`; no side-attack fixture measured. `audit_encounters.py` still decodes only the pincer bit | any 3-4 member party in a random; the whole post-reunion route | none |
| **Preemptive strike** (`$b0` bit 6) | `battle_main.asm:7871-7884`: 1/8 base, doubled by Gale Hairpin (`$3A6D` bit 0), `lda #$40 / tsb $b0` (:7883); suppressed by `$2F4B` bit 2 | **UNHANDLED** | zero reads of `$00b0` in `lib/` or `gen_*` (only `probe_flee_world.lua:50` logs it) | every random; benign today (free turns) but the driver cannot tell a preemptive round from a normal one, so its ATB/press ledgers start mis-seeded | none |
| Back Guard relic suppresses back/pincer | `battle_main.asm:7800-7810`; `$3A6D`/`$11D6` bit 1 (`battle-ram.txt:851`, `field-ram.txt:764`) | UNHANDLED | no read | not equipped on the WoB route today — but it is the one-line mitigation for #185 and nothing knows it exists | none |
| Formation arrangement-permission flags `$2F48 spbn----` | `battle_main.asm:8216-8220` `LoadBattleProp`: `BattleProp,x eor #$00f0 -> $2f48`; bits documented `battle-ram.txt:565-567`. Data: `ff6/src/battle/battle_prop.dat` word `[f*4]` | UNHANDLED (live) / PARTIAL (static, pincer bit only) | 0 live reads of `$2F48`; `tools/audit_encounters.py:96-98` | every formation on the route | none for back/side |
| Formation "no L+R run" `$2F4B` bit 0 | `battle-ram.txt:628`; btlgfx `escape_set` never raises `$2F45` | HANDLED | `lib/ot6_field.lua:149` `NO_LR_RUN=0x01`, `:160` | FC escape map 393 (Naughty), event battles | #150 (closed) |
| `$2F4B` bit 2 "disable type message & preemptive" | `battle-ram.txt:625` | UNHANDLED | no read | scripted set-pieces | none |
| Row / back-row damage halving, and battle type overriding it | `battle_main.asm:7838-7850` mirrors `$3AA1.5` into `$2EC5`; `docs/research/row-menu.md:389-398,518` | PARTIAL | field side: `ot6_field.lua:3023 setRows` used by 11 generators; in-battle `$3AA1` and `$201F` never cross-checked, exactly the trap `row-menu.md:399-401` warns about | Narshe defense (`gen_narshe_battle:637`), FC deck (`gen_fc_landing:334`) | none |
| In-battle Row command `$14` / Defend `$15` (menu states `$24`, `$27`) | `battle_main.asm:4133-4140`; `btlgfx_main.asm:19239` (`_24: row`), `:19186` (`_27: def.`) | UNHANDLED | not in `KNOWN_ST` (`lib/ot6.lua:3331-3336`); reached only by accident → the unknown-menu guard backs out after 8 pulses (`:3416-3425`) | any mis-steer on the command list | none |

---

## B. Fleeing and can't-run

| Mechanic | Defining game source | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| L+R run mechanic (`$2F45`) | `battle_main.asm:5721-5731` `Cmd_2a`/`_escape` | HANDLED | `ot6_field.lua:152-199` `newFlee`; `:184` `M.setPad({l=true,r=true})` | every `playBattles="flee"`/`"mustflee"` navigation | #183 (open — walkers hold L+R at 64 sites and flee unintended battles) |
| Can't-run gate `$b1` bit 1 | `battle_main.asm:5729-5731` `lda $b1 / bit #$02 / bne` → message `$09` | HANDLED | `ot6_field.lua:148,159,174-180`; 60-frame refusal debounce at `:150,167` | every pincer roll; FC escape Naughty; Vargas | #150 (closed) |
| Run difficulty `$3A3B` (2/monster, 6 for "harder to run" = `monster_prop+19` bit 0) | `battle_main.asm:15558-15568,15645-15646` | PARTIAL (logged, not planned on) | `ot6_field.lua:167-169` logs `$3a3b`, `$3d70..$3d76`; no decision uses it | every flee | none |
| "A character just ran away" `$3A38` | `battle_main.asm:5733-5735` | UNHANDLED in lib | only `probe_flee_world.lua:41`, `probe_flee_boss.lua:27` | partial-party escapes leave the driver with a shrinking party it never notices | none |
| Monster escape / `Escape` attack `$C2` | `battle-lists.txt:283`; AI `FB 02` end battle (`battle-lists.txt` AI cmd list) | UNHANDLED | no read of the monster-gone edge except `stageSlots` liveness | Ultros at Lete/Opera/Esper Mtn, Chupon on the IAF (`gen_fc_landing:8`) | none |
| Monster entrance/exit (AI `F5`, battle script `$13`, cmd `$24`) | `battle-lists.txt` AI `F5 xx yy zz` (17 entry styles, 6 hide/revive modes); `battle_main.asm` cmd `$24` | HANDLED (by consequence) | `lib/ot6.lua:2282-2296` `stageSlots()` reads live `$3BFC` HP + `$3AA8` presence rather than the formation's opening mask | Ifrit→Shiva (`gen_ifrit_magicite`), Air Force Speck (`floating-continent-route.md:465`), piranha | #172 (closed); **#177 open** — callers still read `$3F45`/`M.formationSpecies` |
| Formation-level "battle change" (AI `F2`, cmd `$20`) and conditional battles `$3EB9` / `cond_battle.dat` | `battle-lists.txt` AI `F2 xx yyyy`; `battle_main.asm:8185-8196` `CondBattle` scan | UNHANDLED (as an event) | no read of `$3EB9` or `$11E0` mid-fight; `stageSlots` absorbs the *slot* consequences only | Ifrit/Shiva, Kefka at Narshe, FC bosses | #177 |

---

## C. Status bits — all four bytes

Defining source for every row: `ff6/include/const.inc:1487-1533` (`STATUS1`/`2`/`3`/`4` bit enums), live cells `$3EE4`/`$3EE5`/`$3EF8`/`$3EF9` +entity*2 (`ff6/notes/battle-ram.txt:1098-1101`), monster slots at +8 (`lib/ot6.lua:2254`).

### Status 1 (persists out of battle)

| Bit | Status | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| 0 | Blind/Dark | PARTIAL — field cure only | `ot6_field.lua:1722` `{bit=0x01, Eyedrop/Remedy}`; nothing in battle | Edgar's Flash, FC descent (the comment at `:1720-1722` records LOCKE arriving blind) | none |
| 1 | Zombie | **UNHANDLED cure** | `ot6_field.lua:1716-1723` `CARE_STATUS_CURES` has **no `0x02` row** (no Revivify); `:2170` `canCast` masks `0xC2` so a zombie is merely excluded from casting | Zombie Dragon/Ghost rows; Overcast (`$3E4D` bit o) | none |
| 2 | Poison | HANDLED both sides | field `ot6_field.lua:1718`; battle `gen_sabin_train.lua:185-190,512-517` (Antidote) — **generator-local, not in the lib** | Phantom Train, Zozo, Sealed Gate | none |
| 3 | Magitek | UNHANDLED | the opening Narshe fights are mashed A only (`gen_battle2.lua:52-61`) | Narshe opening, Magitek escape | #111 (closed) |
| 4 | Invisible/Vanish | PARTIAL | `gen_fc_alcove.lua:82,87` `ST1_INVISIBLE=0x10` → TERRA switches to Fire 2; one generator only | FC alcove Ninjas; Zozo | none |
| 5 | Imp | PARTIAL (detect only) | field cure `ot6_field.lua:1723` (Remedy); battle `gen_sabin_train.lua:996` detects Imp'd Sabin and declares the attempt **LOST** — no recovery | Phantom Train, Imp Song rows | **#110 (closed) — "Berserk or Imp on Sabin ends the Phantom Train break, with no cure in the scenario"** |
| 6 | Petrify | PARTIAL — field only | `ot6_field.lua:1717` Soft/Remedy; `:2170` `canCast & 0xC2` | Sealed Gate, FC | none |
| 7 | Dead/Wound | HANDLED | `lib/ot6.lua:751 raiseDecision`, raise/top-up pair `:3775-3790`, `RAISE_WAIT` `:2126`; field revive `ot6_field.lua:2245` | everywhere | #165, #168 (closed) |

### Status 2 (battle-only, harmful)

| Bit | Status | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| 0 | **Condemned / Doom** | PARTIAL (logged only) | `gen_fc_escape.lua:250` prints the bit and the `$3B05` countdown; **no plan reacts**; `lib/ot6.lua:2017` names Condemned in a comment about watch expiry | Nerapa on the FC escape; Doom-casting rows | **#149 (closed) "Nerapa: a seed coin-flip"** — the lab issue, not the mechanic |
| 1 | Near Fatal | UNHANDLED (the bit) | the driver uses its own HP ratios (`healDecision` `lib/ot6.lua:670`) rather than the engine's bit | everywhere | none |
| 2 | Image | PARTIAL | `gen_fc_alcove.lua:88` `ST2_IMAGE=0x04` | FC alcove | none |
| 3 | Silence/Mute | PARTIAL (comment only) | `lib/ot6.lua:3520` notes "Mute greys Magic" and `:2176` records the #153 LOCKE case, but the row-grey read is the only defence: `$202F` bit 7 via `cmdRow` | FC escape Naughtys, Zozo | #153 (closed) |
| 4 | Berserk | **UNHANDLED** | no read of `0x10` in `$3EE5` anywhere | Phantom Train, Zozo, Dadaluma | **#110 (closed)** |
| 5 | Confuse/Muddle | **HANDLED** | `lib/ot6.lua:611 ST2_MUDDLE=0x20`, `:625 muddleRule`, `:2651-2660`, `:3989-3994` un-muddle confirm | NoiseBlaster self-hits, Zozo, n024 | #170 (closed) |
| 6 | Sap/Seizure | UNHANDLED | no read; `multi-hit.md:199` notes Sap does not chip | Sealed Gate, FC | none |
| 7 | Sleep | UNHANDLED | no read (`gen_sabin_train.lua:100` names it in a comment as a gap that "cost a diagnosis") | Lullaby rows, Phantom Train | none |

### Status 3 (battle-only, helpful/timing)

| Bit | Status | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| 0 | Dance | UNHANDLED | no read; Dance command window `$1F`/`$21` not in `KNOWN_ST` | Mog only — **N/A on the WoB route today** (Mog unrecruitable pre-FC, #134 closed); becomes live the moment #143/#146 land | #140, #129 (closed) |
| 1 | Regen | UNHANDLED | no read | esper/relic grants | none |
| 2 | Slow | UNHANDLED | no read; ATB model `lib/ot6.lua:644 atbEta` reads `$3AC8` constant but never the Slow bit | Sealed Gate, FC | none |
| 3 | Haste | UNHANDLED | same | same | none |
| 4 | Stop | **UNHANDLED** | no read; a Stopped actor simply never gets a turn and the driver's `menuStreak`/`parkN` watchdogs (`:3396-3412`) cannot tell that from a stall | Sealed Gate, FC, Number 024/128 | none |
| 5 | Shell | UNHANDLED | no read | boss self-buffs | none |
| 6 | Protect/Safe | UNHANDLED | no read | boss self-buffs | none |
| 7 | **Reflect / Wall** | **HANDLED** | `lib/ot6.lua:2254 MON_ST3=0x3F00`, `:2291` reflect flag per stage slot, `:802 castVeto`, `:2318` refusal | Nerapa (FC escape), WallChange `$C1` rows | #156 (closed) |

### Status 4

| Bit | Status | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| 0 | Rage | UNHANDLED | Gau's Rage is driven only by `gen_sabin_gau.lua:378-386,432` (bespoke, fixture-local) | Veldt fixture only; Gau otherwise benched | #140, #40, #122 (closed) |
| 1 | Frozen | UNHANDLED | no read of `$3F0D` Freeze counter either | Ice-3/Absolute 0 rows | none |
| 2 | Reraise | UNHANDLED | no read | esper grants | none |
| 3 | Morph | UNHANDLED | `$3EE2` morphed-character and `$3B04` morph gauge unread; `gen_kefka_won.lua:387` drives the *cutscene* morph, not the command | Terra's Morph post-esper | none |
| 4 | Chant/Casting | UNHANDLED | no read | everywhere | none |
| 5 | Hide | UNHANDLED | no read (AI `FB 0D` sets it) | piranha battle pattern | none |
| 6 | Interceptor | UNHANDLED | no read | Shadow in the party (Sabin leg, Phantom Train, FC) | none |
| 7 | Float | UNHANDLED | no read | Magnitude8 rows | none |

### Special status bytes

| Mechanic | Source | Class | Evidence | Exposure | Issue |
|---|---|---|---|---|---|
| `$3E4C` Special Status 1 (piranha, character Runic `c`, enemy Runic, Retort `r`) | `battle-ram.txt:1015-1022` | UNHANDLED | 0 reads of `$3E4C` | Celes's Runic is *pressed* but never *verified*; Cyan's Retort in `gen_sabin_gau:703` | #104 (closed) |
| `$3E4D` phantasm / overcast / control | `battle-ram.txt:1021-1025` | UNHANDLED | 0 reads | Sealed Gate, FC | none |
| `$3C80` can't-control / can't-sketch / can't-scan / can't-run / can't-suplex / **first strike** / harder-to-run | `battle-ram.txt:952-960` | UNHANDLED | 0 reads | every formation | none |

---

## D. Battle menu states — the `$7BC2` space

Defining source: `ff6/src/btlgfx/btlgfx_main.asm:12546-12621` — a 66-entry jump table, `$00`–`$41`. Harness whitelist: `lib/ot6.lua:3331-3336` `KNOWN_ST` = `$01, $05, $0A, $0E, $16, $19, $1B, $2B, $2C, $2D, $30, $38` (12 of 66). Guard for the rest: `lib/ot6.lua:3416-3425`, back out with B after 8 pulses.

| Window | State(s) | Defining line | Class | Evidence / note | Route exposure | Issue |
|---|---|---|---|---|---|---|
| Command select | `$05` | `btlgfx_main.asm:18753` | HANDLED | `lib/ot6.lua:2059`, `cmdRow` at `:3160` etc. | every turn | — |
| Target select | `$38` | `:16824` | HANDLED for *which entity*, ASSUMED for *which side* | `lib/ot6.lua:3654,3658,3736` | every turn | **#185** |
| Item select | `$0A` (+ open `$09`, close `$12`) | `:20764`, `:12992`, `:12880` | HANDLED (`$0A` only; `$09`/`$12` fall to the unknown guard) | `lib/ot6.lua:2059,2083` | every heal | #184 (open) |
| Magic/spell select | `$0E` (+ open `$0D`, close `$14`) | `:19616`, `:13020`, `:12869` | HANDLED (`$0E` only) | `lib/ot6.lua:2059,2078-2081` | Terra/Celes turns | #182 (open) |
| Esper/summon select | `$16` (+ close `$15`) | `:19868`, `:12935` | HANDLED | `lib/ot6.lua:2059` | post-magicite | — |
| Lore | `$19` open, `$1B` select, `$1A` close | `:13219`, `:19909`, `:12891` | HANDLED (open+select; `$1A` not listed) | `lib/ot6.lua:2065,3226-3241` | Strago (Thamasa+) | — |
| Throw | `$2B/$2C/$2D` | `:13145`, `:12858`, `:20469` | HANDLED (all three) | `lib/ot6.lua:2071,3334-3336` | Shadow legs | — |
| Tools | `$30` select, **`$2E` open**, `$2F` close | `:20613`, `:13182`, `:12802` | ASSUMED — only `$30` is known; `$2E`/`$2F` hit the unknown guard | `lib/ot6.lua:2059`; contrast the Throw family where all three are whitelisted | Edgar, every fight | #115 (closed) |
| **Blitz** | (OT6 retired the `$3D` pad-edge state, `btlgfx_main.asm:12617`; Blitz now routes through the generic list) | ASSUMED | cmd id `CMD_BLITZ=0x0A` at `lib/ot6.lua:2057`, used `:2856-2858, 3298-3300`, but **no Blitz window state is in `KNOWN_ST`** | Sabin, every fight from Figaro on | #115-adjacent, none direct |
| **SwdTech / Bushido** | `$37`, close `$36` | `:19072`, `:12697` | **UNHANDLED in lib** | only `gen_sabin_gau.lua:688-703` (Retort), fixture-local | Cyan from Doma to the FC | **#141 (closed) — committing a MANUAL row past 1× freezes at `st=$01`** |
| **Runic** | command `$0B`, no list window | `battle-lists.txt:41` | ASSUMED (blind key sequence) | `gen_narshe_battle.lua:141` `push("down","a","a")`; `gen_kefka_won.lua:67` identical | Narshe defense, Kefka fight | #104 (closed) |
| **Rage** | `$1C` open, `$1E` select, `$1D` close | `:13248`, `:20235`, `:12902` | PARTIAL, fixture-local | `gen_sabin_gau.lua:432` `ST_RAGE` | Veldt fixture; Gau benched after | #140, #47 (closed) |
| **Dance** | `$1F` open, `$21` select, `$20` close | `:13274`, `:20352`, `:12913` | UNHANDLED | — | **N/A on the current WoB route** — Mog unrecruitable pre-FC (#134) | #140, #129 (closed) |
| **Slot** | `$06` open, `$08` select | `:13322`, `:19324` | UNHANDLED | — | Setzer joins at the Blackjack (`gen_opera7_blackjack`) and rides the whole Vector→FC stretch | none |
| **Sketch / Control** | `$0D`/`$0E` commands; Control uses `$3E4D` bit c | `battle-lists.txt:42-43` | UNHANDLED | — | Relm joins Thamasa; Sketch is a known vanilla-bug area | #28, #123 (closed) |
| **Morph / Revert** | commands `$03`/`$04` | `battle-lists.txt:34-35` | UNHANDLED | `$3EE2`, `$3B04`, `$3F30` all unread | Terra post-esper | none |
| **Leap** | command `$11`, disable bit `$2F49` bit 3 (`battle-ram.txt:616`) | `battle-lists.txt:42` | PARTIAL — avoided, not used | `gen_sabin_gau.lua:370-382` explicitly refuses Leap when it is row 0 | Veldt | #122 (closed) |
| **MagiTek** | `$28` open, `$2A` select, `$29` close | `:13298`, `:20405`, `:12924` | UNHANDLED | Narshe opening is mashed A (`gen_battle2.lua:52-61`) | Narshe opening, Magitek escape | #111 (closed) |
| Equip / weapon-shield (Runic's sword pick) | `$0B`, `$0C`, `$13`, `$10` | `:12728`, `:21421`, `:12755`, `:12743` | UNHANDLED | — | any Runic/Gogo path | none |
| Row `$24` / Defend `$27` | `:19239`, `:19186` | UNHANDLED | — | mis-steer only | none |
| Character status window | `$3F`, `$40`, `$41` | `:12627`, `:12637`, `:21846` | UNHANDLED | `$41` is *"status window for character target select"* — reachable from the target screen the driver lives in | any ally-target turn | none |
| Steal/Capture, Jump, Mimic, X-Magic, GP Rain, Health, Shock, Possess | `battle-lists.txt:35-52` | UNHANDLED | Locke's Filch is driven only by `gen_thamasa_fire.lua:658-670` (`ST_THIEF_A`) | Locke throughout; Filch at Thamasa | #55, #68 (closed) |
| **Menu state queue** `$7BF0`, `$7BF1-$7BFF`; cursor queue `$7BC3-$7BC9` | `battle-ram.txt:1826-1827, 1851-1852` | UNHANDLED | the driver reads only `$7BC2` (cursor state) and `$7BCA` (open flag) — `lib/ot6.lua:2054` — so a *queued* transition is invisible and reads as a stall | every transitional frame | none |

---

## E. Target-menu geometry — the #185 root cause, named

| Mechanic | Defining game source | Class | Evidence | Note |
|---|---|---|---|---|
| **Selected target group `$7ACE`** — `0` = monsters-left, `1` = characters-left, `2` = monsters-right, `3` = characters-right | `ff6/notes/battle-ram.txt:1698-1702`; driven by `btlgfx_main.asm:16905-16926` (RIGHT `inc2`, LEFT `dec2`, both gated on `w7e7ace & $02`) | HANDLED | `lib/ot6.lua` `M.battleLayout` reads it with `$201F`; `cross("monsters"/"chars")` in `newFightDriver` replaces the three hard-coded presses, and `steerWatch` checks every press against `$7B7D/$7B7E/$7B7F/$7ACE` (a press that moves nothing twice is not pressed again; `FIGHT DRIVER STUCK` when no derived direction moves it). The evidence lines are in section A | the 9000-frame hang is now a 2500-frame win on the same snapshot (`probe_backattack_j39`: `battle over at f2616 (+2553) ... party 540/481/620/451 (4 alive), monsters up 0`) |
| Side tables `$7B79` monsters-left / `$7B7A` chars-left / `$7B7B` monsters-right / `$7B7C` chars-right | `battle-ram.txt:1773-1776` | UNHANDLED | 0 reads in `lib/` | the layout-independent way to answer "which press reaches the monsters" |
| `$7B7D` chars-lit / `$7B7E` monsters-lit / `$7B7F` all-latch | `battle-ram.txt:1777-1779` | HANDLED | `lib/ot6.lua:2086-2091`, used at `:3652-3745` and in the park signature `:3400-3404` | correct, and since wt/driver-boost also the no-effect check: the four cells are the press signature |
| `opts.focus` monster kill order | — (harness construct) | ASSUMED | `lib/ot6.lua:3697-3745`; authored masks at `gen_n128.lua:163`, `gen_terra_returned_checkpoint.lua:110`, `gen_zozo4_dadaluma.lua:133` | the comment at `:3699-3702` says masks "follow the on-screen formation layout" — which is exactly what the battle type changes. Every authored focus mask is a normal-arrangement mask |
| Group-vs-slot targeting (`TARGET::INIT_GROUP`, no `MANUAL`) | `btlgfx_main.asm:16895-16899` | HANDLED | `lib/ot6.lua:3728-3736` (the Bio Blaster `$7B7E=$2C` finding) | — |
| `CheckTargetsBattleType` — pincer/side retarget the *engine* applies | `battle_main.asm:15136,15165,15185` | UNHANDLED | no read | a confirmed target can be silently re-aimed and the driver's damage watch mis-attributes it |

---

## F. Multi-part monsters, transformations, boss stage swaps

| Mechanic | Defining game source | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| Multi-part bodies (one formation, several linked slots) | `ff6/src/battle/battle_monsters.dat` (+1 present mask, +2..+7 indices, +14 high bits — decoded `tools/audit_encounters.py:86-94`) | PARTIAL | `lib/ot6.lua:431 monsterIds`, `:2282 stageSlots` see slots; nothing models "these slots are one creature" | **Number 128 + Left Blade `$140` + RightBlade `$13f`** (`break-coverage-vector.md:205,221`, `gen_n128`); **AirForce `$113` + Laser Gun `$145` + MissileBay `$147` + Speck `$146`** (`floating-continent-route.md:169,465`, `gen_fc_landing`) | #19 (closed), #92 (closed) |
| Script-spawned part (Speck) | AI `F5` (`battle-lists.txt` AI cmd list) | HANDLED | `lib/ot6.lua:2282-2296` presence-filtered | FC approach | #172 (closed) |
| Formation stage swap mid-fight (Ifrit→Shiva) | AI `F2 xx yyyy` "Change Battle"; `battle_main.asm:8185-8196` `CondBattle` | HANDLED for the absorb guard, UNHANDLED as an event | `lib/ot6.lua:2265-2280` (the note explaining why `$3F45` is wrong), `:2282` | battle 70 `gen_ifrit_magicite` | #172 (closed); **#177 open** |
| Metamorph / monster→item transform | `ff6/src/battle/metamorph_prop.dat` | N/A | — | no Ragnarok esper on the WoB route | none |
| Broken-shield / OT6 gate interaction with queued actions | `ff6/src/battle/ot6_break.asm` | HANDLED | `lib/ot6.lua:2340-2360` chip model, `SH_CUR/BRK_TICKS` `:2252` | everywhere | #66, #85 (closed) |

---

## G. Fail and recovery flows

| Mechanic | Defining game source | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| Party wipe in battle | — | HANDLED | `lib/ot6.lua:481 wipeVerdict`, `:458 partyHp`; `ot6_field.lua:63 partyWipedInBattle` | everywhere | #166, #114, #163 (closed) |
| Game Over | event script `GameOver` (`$CC/E568`), plus a battle-module path that bypasses it | HANDLED (as a canary, not a recovery) | `lib/ot6.lua:4307-4430`: read-watch + exec-watch, `M.gameOverFired` `:4354`, pad freeze `:4375`, fail `:4420` | everywhere | #153 (closed); **#178 open** (retry-from-checkpoint is not yet the default) |
| Dead actor → raise → top-up | — | HANDLED | `lib/ot6.lua:751 raiseDecision`, `:2122-2126 raisePending/topUpOwed/RAISE_WAIT`, `:3775-3790` | everywhere | #165, #168 (closed) |
| Healer death lockout | — | HANDLED | any live caster can be the healer (`:2094-2098` comment; `:2721` `cmdRow(actor, CMD_MAGIC)`) | everywhere | #128 (closed) |
| Unknown-menu stall guard | — | HANDLED (as a guard) | `lib/ot6.lua:2106, 3416-3425` — 8 pulses then B + `dropPlan("unknown_menu")` | this is what turns 54 unknown menu states into a *slow* failure rather than a hang; the Phantom Train Throw-list wipe is the recorded case (`:3344-3347`) | none |
| Parked-known-window watchdog + pulse budget | — | HANDLED | `lib/ot6.lua:3356-3412` (`parkN > 12`, `budget = min(140, 40+idx)`) | Sealed Gate, IAF, dadaluma | none |

---

## H. Field and world

| Mechanic | Defining game source | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| Field passability (both engine branches, incl. diagonals) | `UpdatePlayerMovement`; `field-ram.txt:139-158` | HANDLED | `ot6_field.lua:196-232,263-317` | every walk | — |
| **NPC/object blocking** `$7E2000[dst]` bit 7 | `field-ram.txt:516-530` (object data, 41 B × 50) | HANDLED | `ot6_field.lua:305` "an NPC/object stands there"; blocked-edge learning + re-BFS `:346-390` | every town/dungeon walk | #22 (closed), #134 (closed) |
| Wandering-NPC approach | `field-ram.txt:516` | HANDLED | `ot6_field.lua:1515 chaseTalk` (re-plans each aligned frame), `:3850 talkToObj` | 5 + 11 generators | — |
| Event triggers on tiles | `$078E` "party is on a trigger (disables random battles)" (`field-ram.txt:503`); `$1EB6` bit t tile-event bit (`field-ram.txt:~1075`) | **UNHANDLED (as state)** | 0 reads of `$078E`; triggers are handled *by consequence* — `hasControl()` (`lib/ot6.lua:1668`, movement type `$087c` low nibble 2=user/4=event) and `advanceStory` (`ot6_field.lua:768`, 39 generators) | every scripted step-on | #159 (closed — a wedge with no control and no battle) |
| Doors / map transitions | `$1127` open-door count, `$1129-$1158` door XY (`field-ram.txt:678-679`) | HANDLED (by map-id + settle), UNHANDLED (as door state) | `ot6_field.lua:2784 crossDoor` keys on `mapLow()` + brightness (`:2759 bright`), not on `$1127`; 6 generators | every interior | — |
| Save points | `$01BF` (shared SavePoint script) | HANDLED | `ot6_field.lua:4085 saveGame` `:4075-4101`; 6 generators | Gate Cave, MRF, N024, minecart platform, Thamasa | #125, #10 (closed) |
| Treasure chests | `$1E40-$1E7F` treasure bitfield (`field-ram.txt:1035`) | HANDLED | `ot6_field.lua:1906 chestOpen`, `:1927 openChest` (asserts the bit, not the dialog, `:1956-1963`); 20 generators; audit `tools/audit_chests.py` | route-wide | #84 (closed) |
| **Dialog choices** `$056E` cur / `$056F` max / `$056D` changing | `field-ram.txt:396-401` | PARTIAL — no lib helper | lib only *guards*: `ot6_field.lua:1519,1537` (chaseTalk refuses a blind A), `:3926-3927` ("an A press always takes option 0, so every prompt on a route is answered by a choice-steering rider instead"). Each generator re-rolls its own `choicePick`: `gen_banon.lua:228`, `gen_banquet_done.lua:402-407,704`, `gen_gate_cave_save.lua:394`, `gen_opera5_dance.lua:28-35`, `gen_thamasa_fire.lua:206`, `gen_voyage.lua:150` | Banon (×3 for the Genji Glove), banquet, Gate Cave, aria, Thamasa | #106 (closed) |
| Shops — item/weapon/armor/relic | menu state `$26`: `$25` shop main, `$26` buy list, `$27` quantity | ASSUMED | `ot6_field.lua:2838 shopTalk` (opens on `$25`), `:2016 buyItem` takes a **hard-coded `row`** and steers `$004E` to it (`:2062-2066`) — it never looks the item id up in the shop's list. Shop *type* is never read; all four types are driven identically | South Figaro (`gen_kolts:787,793,831`), Figaro, Narshe, Vector, Jidoor (`probe_jidoor_shop`) | **#176, #179 (open)** |
| Inn | — | ASSUMED (bespoke) | `gen_kolts.lua:736-749,879` `innRest` with asserted talk-spot coordinates (81,19) | South Figaro | none |
| **Party swap / split party** | `$0762` enable party change, `$1A6D` current party, `$07FB-$0801` party chars (`field-ram.txt:472,940,510-513`) | PARTIAL | `ot6_field.lua:3734 newPartySelect` — **1 generator uses it**; `$0762` has 0 reads; `$1A6D` 27 reads (mostly contract assertions) | scenario split (3 legs), Narshe defense (3 groups), Blackjack swap room, FC party select (`gen_fc_landing:7`) | #21 (closed) |
| Timed scenes | `$1188-$119F` four 6-byte timer records (`field-ram.txt:684-690`) | HANDLED | `ot6_field.lua:2083 eventTimerLive` — menus stay out while any counter is nonzero | opera rafter chase, banquet, aria | #160, #119 (closed) |
| **Vehicles — chocobo** | `$11FA` vehicle index (`world-ram.txt:205`), chocobo-passable tile bit (`world-ram.txt:110`) | ASSUMED | `worldPassable` (`ot6_field.lua:931`) is **on-foot only**: `(prop & 0x0010) == 0`, with the comment "The engine checks nothing else". `$11FA` is asserted (`gen_edgar.lua:601`, `gen_kolts.lua:908,918-924`) but never fed into the model; the route dismounts rather than navigates mounted | South Figaro chocobo stable | none |
| **Vehicles — airship** | `$11F3` forced-aboard, `$11F4` altitude, `$1F62/63` airship XY, `$1F64` bit 13 aboard (`world-ram.txt:198,205,213`) | PARTIAL — contract assertions only | `ot6_contract.lua:239-246, 291-307, 384-397, 437-456` pin the Blackjack's cells per checkpoint; no navigation reads them | Blackjack from the Opera to the FC; the crash | #131 (closed) |
| Vehicles — raft / Lete / Serpent Trench | `world-ram.txt:121-131` vehicle states; `$1EB6` bit s trench arrow | HANDLED (as scripted rides) | `gen_lete`, `gen_rapids`, `gen_sabin_trench` drive them as timed/choice scenes | Lete River, Serpent Trench | #101 (closed) |
| Ferry (South Figaro ↔ Nikeah) | — | N/A on the current WoB route | the route crosses via the Sabin leg overland | — | — |
| World-map encounters | `world_battle_rate.dat`, `world_battle_group.dat`; tile prop bit `$40` "random battles enabled here" (`ot6_field.lua:929`) | PARTIAL | `worldNavTo` (`:1025`) carries the same `playBattles` contract; the `$40` bit is decoded and **explicitly discarded as "informational"** (`:928-929`), so no route step can predict its own encounter exposure | Narshe→Figaro, Sabin's world leg, Gate Cave approach, WoR landing | #24 (closed) |
| Field random-encounter pool + fleeability | `map_prop.dat +5` bit 7, `sub_battle_group.dat`, `rand_battle_group.dat`, `battle_prop.dat` | HANDLED (static) | `tools/audit_encounters.py` — but **pincer bit only** (`:96-98`) | every field map | #82 (closed) |
| Field menu state whitelist | `$26` `zMenuState` | HANDLED | `ot6_field.lua:1733-1740` `CARE_SCREENS` (12 screens named; "every other value … is a fade or a one-frame init"); router presses B off-path | every care visit | **#184 (open)** |
| Field status cures | `field_menu.asm:722-731` `CheckSkillValid`; `item.asm:2282-2286` wound branch | HANDLED for petrify/poison/dark/imp; **zombie missing** | `ot6_field.lua:1716-1723`, `:2170` (`& 0xC2`) | route-wide | none |

---

## I. Ranked gaps — UNHANDLED and ASSUMED, by route exposure

**Tier 1 — fires on ordinary random encounters, i.e. hundreds of times per route:**

1. **Back attack `$201F=1` — HANDLED** on wt/driver-boost (`M.battleLayout`, section A/E evidence). Issue **#185**.
2. **Side attack `$201F=3` — HANDLED by the jump tables, unmeasured live** (no fixture draws one yet). 3× run difficulty still unread.
3. **Pincer target steering — HANDLED by the jump tables, unmeasured live** (the flee half was already handled).
4. **`$2F48` back/side permission bits never audited — UNHANDLED.** `tools/audit_encounters.py:98` reads `$40` only, so the route cannot even *list* which of its 60-odd maps can roll a back attack. No issue. This is the cheapest way to convert #185 from a discovery into an inventory.
5. **`opts.focus` masks are normal-arrangement literals — ASSUMED.** `gen_n128:163`, `gen_zozo4_dadaluma:133`, `gen_terra_returned_checkpoint:110`.
6. **Preemptive strike `$b0` bit 6 — UNHANDLED.** No issue.
7. **Field-menu `$26` unknown screens / care hang — ASSUMED.** Issue **#184**.
8. **Walkers hold L+R — ASSUMED**, 64 sites. Issue **#183**.

**Tier 2 — fires on specific, known route stretches:**

9. **Stop (`$3EF8` bit 4), Sleep, Berserk — UNHANDLED.** Indistinguishable from a driver stall. Berserk/Imp on Sabin is the recorded Phantom Train loss, #110 (closed) — the *mechanic* is still unhandled.
10. **Tools open/close states `$2E`/`$2F` not in `KNOWN_ST` — ASSUMED.** Edgar acts every fight from Figaro on; the Throw family got all three states, Tools got one.
11. **Blitz has a command id but no window state — ASSUMED.** Sabin, every fight.
12. **SwdTech `$37`/`$36` — UNHANDLED in lib**, fixture-local only. Cyan from Doma to the FC. #141 (closed) is the freeze this leaves reachable.
13. **Slot `$06`/`$08` — UNHANDLED.** Setzer rides the entire Vector→FC stretch.
14. **Runic driven by blind `down,a,a` — ASSUMED.** `gen_narshe_battle.lua:141`, `gen_kefka_won.lua:67`.
15. **Multi-part monsters not modelled — PARTIAL.** Number 128's blades, the Air Force's pods and Speck.
16. **Shop `buyItem` hard-codes the list row — ASSUMED.** `ot6_field.lua:2016`. Interacts with #176/#179.
17. **Party swap has a lib helper used once — PARTIAL.** `newPartySelect`; the scenario split, Narshe defense and FC select each roll their own.
18. **Zombie has no field cure row — UNHANDLED.** `ot6_field.lua:1716-1723`.
19. **World passability is on-foot only — ASSUMED.** `ot6_field.lua:931`.
20. **Condemned/Doom logged but never acted on — PARTIAL.** `gen_fc_escape.lua:250`, Nerapa.
21. **Vanish/Image handled in exactly one generator — PARTIAL.** `gen_fc_alcove.lua:87-88`.
22. **Dialog choices have no lib helper — PARTIAL.** Seven independent re-implementations.

**Tier 3 — N/A on the current WoB route, with the reason:**

23. **Dance (`$1F`/`$21`, status3 bit 0)** — Mog is unrecruitable before the FC (#134, closed). Becomes Tier 1 the moment #143 or #146 lands. #140, #129 (closed).
24. **Rage (`$1C`/`$1E`, status4 bit 0)** — Gau is driven only inside `gen_sabin_gau`; benched after. #140, #40.
25. **Sketch / Control (`$0D`/`$0E`)** — Relm joins at Thamasa and is not in a fighting party on the routed legs. #28, #123.
26. **Morph / Revert** — Terra's Morph is a cutscene on this route, not a command. No issue.
27. **Metamorph** — no Ragnarok esper in WoB.
28. **Ferry** — the route crosses overland on the Sabin leg.
29. **Mimic, Jump, X-Magic, GP Rain, Health, Shock, Possess, Umaro's Tackle/Throw** — no route character carries these commands. #146 (Umaro) open but out of WoB scope.

**Tier 4 — status bits with no current route source, listed for completeness (all UNHANDLED):** Near Fatal, Sap, Regen, Slow, Haste, Shell, Protect, Frozen (`$3F0D`), Reraise, Chant, Hide, Interceptor, Float, and the special-status bytes `$3E4C`/`$3E4D`/`$3C80` (which include `can't run`, `can't control`, `can't scan`, and **first strike** — the last of which changes turn-one ordering on formations the route already fights).

---

### Two structural observations

- **The knowledge exists; the lib does not have it.** `$7ACE` (target group), `$3EE4` status 1, `$3EE5` Image/Condemned, `$3B05` Condemned counter, Retort, Rage, Filch, and choice-steering are each implemented correctly in *one* generator or probe and never promoted. The back-attack hang is that pattern's cost: `gen_thamasa_fire.lua:650` has known the right answer since the pincer work.
- **The unknown-menu guard (`lib/ot6.lua:3416-3425`) is load-bearing.** It is the only thing standing between 54 unmodelled menu states and a hard hang, and it converts each of them into ~8 wasted pulses plus a dropped plan. A count of `dropPlan("unknown_menu")` events per run, bucketed by `st`, would turn the remaining half of this table into measurement rather than inference — the unknown states are enumerable from `btlgfx_main.asm:12556-12621` and the driver already logs `st` on every drop.
