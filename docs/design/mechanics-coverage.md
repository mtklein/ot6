<!-- Maintained inventory: update when a mechanic moves class or an issue lands. -->
# FF6 mechanics coverage inventory (2026-09-16)

Citations verified against main c066602a on 2026-09-16.

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
| Battle type selection (the roll) | `ff6/src/battle/battle_main.asm:7799-7821` `ChooseBattleType` — masks `$2F48`, rolls `RandBitWithRate`, `stx $201f` (:7820) | HANDLED | `lib/ot6.lua:959-994` `M.battleLayout` reads `$201F` and `$7ACE` (`:961-962`); the driver logs it once the command window is up and every crossing press comes from it. Measured: `[healerdown] [layout] battle type $00 (normal): the monsters stand left of the party; from the party side the cursor crosses with left, and back with right ($201F=00 $7ACE=00)`; `[j39 back attack] [layout] battle type $01 (back attack): the monsters stand RIGHT of the party (back attack); from the party side the cursor crosses with right, and back with left ($201F=01 $7ACE=00)` -> `the cursor is on the MONSTER side at f493: mons=10 chars=00`, `PASS (frame 2616)` (`probe_backattack_j39`, the potion-route snapshot). `battle_healpolicy` asserts all four types' directions | every random encounter on every walked map, world and field | **#185** (the symptom) |
| Normal arrangement (`$201F=0`) | `battle_main.asm:7864` `InitBattleType_00` | HANDLED | read, not assumed: `M.battleLayout` type 0 -> LEFT to the monsters, RIGHT back (btlgfx `_c174bf` / `_c175a3`); the `[layout] battle type $00 (normal)` line above in every suite fight and lab batch (m269 fix4/fix5, Nerapa fix4: unchanged seed for seed) | everywhere | **#185** |
| **Back attack** (`$201F=1`) | `battle_main.asm:7900-7909` `InitBattleType_01`: toggles every `$3AA1.5` row bit, `lda #$20 / tsb $b1` (:7907-7908). Enable bit = `$2F48` bit 5 (`battle-ram.txt:567`) | HANDLED | `M.battleLayout` type 1 -> RIGHT to the monsters, LEFT back (btlgfx `_c17439` / `_c17669`; LEFT from the party side is `_c174e9: rts`). Before: `left pressed twice in target select with no effect (window 01:00:00:01, layout back attack)` x3 then the recovery cap; after: the `[layout] ... back attack` line and the win quoted above | any non-scripted encounter: Narshe mines, Mt Kolts, Lete, both scenario legs, Zozo, Magitek Factory, esper tubes, minecart, Sealed Gate cave, Thamasa/Esper Mtn, FC | **#185** fixed on wt/driver-boost |
| **Pincer** (`$201F=2`) | `battle_main.asm:7889-7896` `InitBattleType_02` — forces every character front row, then `tsb $b1 #$20`. Also sets `$b1` bit 1 via `UpdateMonsterGfxBuf` when monsters live on both sides | HANDLED (cursor, by the jump tables) / PARTIAL (measured) | `M.battleLayout` type 2 -> either LEFT or RIGHT crosses (btlgfx `_c174bf` / `_c17439`, monsters on both sides); a direction that moves nothing twice is skipped. Flee half as before (`ot6_field.lua:148,159`). No pincer fixture in the tree: the arithmetic is asserted (`battle_healpolicy`), the live cross is not yet measured | Thamasa ambush (`gen_thamasa_fire`), `gen_mrf_chute:268`, Zozo clock shaft (`gen_zozo3_clock:41`), any pool `audit_encounters` flags | **#185**; #150 (closed), #82 (closed) |
| **Side attack** (`$201F=3`) | `battle_main.asm:7865` (shares `InitBattleType_00`), enable bit `$2F48` bit 7; disabled when fewer than 3 allies alive (`:7811-7818`). Raises run difficulty per monster (`:15645-15646`) | HANDLED (cursor, by the jump tables) / PARTIAL (measured) | `M.battleLayout` type 3 -> by the group `$7ACE`: 1 (left party group) crosses RIGHT (`_c174ea` returns on LEFT), 3 crosses LEFT (`_c17463` returns on RIGHT), else either; re-read each press since the group moves. Asserted in `battle_healpolicy`; no side-attack fixture measured. `audit_encounters.py` decodes the side bit per formation and lists the maps that can roll one (`--summary`, `--route LOG...`; #186): every rolling WoB route map but 3, 72, 73, 376, 381 | any 3-4 member party in a random; the whole post-reunion route | none |
| **Preemptive strike** (`$b0` bit 6) | `battle_main.asm:7871-7884`: 1/8 base, doubled by Gale Hairpin (`$3A6D` bit 0), `lda #$40 / tsb $b0` (:7883); suppressed by `$2F4B` bit 2. Bit 6 is set nowhere else (`:280` sets `$a0`, `:3124/:10651/:11128` `$10`, `:15520` `$04`) and `stz $b0` (`:6157`) clears it per battle | HANDLED (read, logged, one ledger) | `M.battleLayout` reads `$00B0` bit 6 with the type and the driver's `[layout]` line carries it: `[statuses forest] [layout] battle type $00 (normal): ... ($201F=00 $7ACE=00) preemptive ($b0 bit 6: the party's gauges opened full, the monsters' empty -- a free round)` (probe_statuses forest mode, seed 31: 4 of 12 fights). The one ledger that assumed a normal opening is the first-turn heal check (round cost 0 before an enemy round reads as "top up freely"): under the free round top-ups wait one turn for an attack while raises still go (`[statuses forest] actor=2: the preemptive strike's free round -- no monster has acted yet, so top-ups wait one turn for an attack (raises still go; opts.freeRound="care" keeps the top-ups)`); the ATB and hit ledgers read live gauges and landed hits and needed nothing | every random | #186 (this half) |
| Back Guard relic suppresses back/pincer | `battle_main.asm:7800-7810`; `$3A6D`/`$11D6` bit 1 (`battle-ram.txt:851`, `field-ram.txt:764`) | UNHANDLED | no read | not equipped on the WoB route today — but it is the one-line mitigation for #185 and nothing knows it exists | none |
| Formation arrangement-permission flags `$2F48 spbn----` | `battle_main.asm:8216-8220` `LoadBattleProp`: `BattleProp,x eor #$00f0 -> $2f48`; bits documented `battle-ram.txt:565-567`. Data: `ff6/src/battle/battle_prop.dat` word `[f*4]` | UNHANDLED (live) / HANDLED (static) | 0 live reads of `$2F48`; `tools/audit_encounters.py` decodes all three rolled bits per formation (`Data.arrangements`, bit 5 back / 6 pincer / 7 side per `ChooseBattleType` `:7806,:7809,:7817`) and lists the route's maps per arrangement (`--route`, from the `[tiles]` traces); measured over the regeneration logs: all 43 rolling route maps permit a back attack, 38 a side attack, 35 a pincer | every formation on the route | #186 (static half done) |
| Formation "no L+R run" `$2F4B` bit 0 | `battle-ram.txt:628`; btlgfx `escape_set` never raises `$2F45` | HANDLED | `lib/ot6_field.lua:149` `NO_LR_RUN=0x01`, `:160` | FC escape map 393 (Naughty), event battles | #150 (closed) |
| `$2F4B` bit 2 "disable type message & preemptive" | `battle-ram.txt:625` | UNHANDLED | no read | scripted set-pieces | none |
| Row / back-row damage halving, and battle type overriding it | `battle_main.asm:7838-7850` mirrors `$3AA1.5` into `$2EC5`; `docs/research/row-menu.md:389-398,518` | PARTIAL | field side: `ot6_field.lua:3055 setRows` used by 11 generators; in-battle `$3AA1` and `$201F` never cross-checked, exactly the trap `row-menu.md:399-401` warns about | Narshe defense (`gen_narshe_battle:639`), FC deck (`gen_fc_landing:341`) | none |
| In-battle Row command `$14` / Defend `$15` (menu states `$24`, `$27`) | `battle_main.asm:4133-4140`; `btlgfx_main.asm:19239` (`_24: row`), `:19186` (`_27: def.`) | UNHANDLED | not in `KNOWN_ST` (`lib/ot6.lua:3903-3908`); reached only by accident → the unknown-menu guard backs out after 8 pulses (`:4082-4091`) | any mis-steer on the command list | none |

---

## B. Fleeing and can't-run

| Mechanic | Defining game source | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| L+R run mechanic (`$2F45`) | `battle_main.asm:5721-5731` `Cmd_2a`/`_escape` | HANDLED | `ot6_field.lua:152-199` `newFlee`; `:184` `M.setPad({l=true,r=true})` | every `playBattles="flee"`/`"mustflee"` navigation | #183 (open — walkers hold L+R at 64 sites and flee unintended battles) |
| Can't-run gate `$b1` bit 1 | `battle_main.asm:5729-5731` `lda $b1 / bit #$02 / bne` → message `$09` | HANDLED | `ot6_field.lua:148,159,174-180`; 60-frame refusal debounce at `:150,167` | every pincer roll; FC escape Naughty; Vargas | #150 (closed) |
| Run difficulty `$3A3B` (2/monster, 6 for "harder to run" = `monster_prop+19` bit 0) | `battle_main.asm:15558-15568,15645-15646` | PARTIAL (logged, not planned on) | `ot6_field.lua:167-169` logs `$3a3b`, `$3d70..$3d76`; no decision uses it | every flee | none |
| "A character just ran away" `$3A38` | `battle_main.asm:5733-5735` | UNHANDLED in lib | only `probe_flee_world.lua:41`, `probe_flee_boss.lua:27` | partial-party escapes leave the driver with a shrinking party it never notices | none |
| Monster escape / `Escape` attack `$C2` | `battle-lists.txt:283`; AI `FB 02` end battle (`battle-lists.txt` AI cmd list) | UNHANDLED | no read of the monster-gone edge except `stageSlots` liveness | Ultros at Lete/Opera/Esper Mtn, Chupon on the IAF (`gen_fc_landing:8`) | none |
| Monster entrance/exit (AI `F5`, battle script `$13`, cmd `$24`) | `battle-lists.txt` AI `F5 xx yy zz` (17 entry styles, 6 hide/revive modes); `battle_main.asm` cmd `$24` | HANDLED (by consequence) | `lib/ot6.lua:2678-2691` `stageSlots()` reads live `$3BFC` HP + `$3AA8` presence rather than the formation's opening mask | Ifrit→Shiva (`gen_ifrit_magicite`), Air Force Speck (`floating-continent-route.md:465`), piranha | #172 (closed); **#177 open** — callers still read `$3F45`/`M.formationSpecies` |
| Formation-level "battle change" (AI `F2`, cmd `$20`) and conditional battles `$3EB9` / `cond_battle.dat` | `battle-lists.txt` AI `F2 xx yyyy`; `battle_main.asm:8185-8196` `CondBattle` scan | UNHANDLED (as an event) | no read of `$3EB9` or `$11E0` mid-fight; `stageSlots` absorbs the *slot* consequences only | Ifrit/Shiva, Kefka at Narshe, FC bosses | #177 |

---

## C. Status bits — all four bytes

Defining source for every row: `ff6/include/const.inc:1487-1533` (`STATUS1`/`2`/`3`/`4` bit enums), live cells `$3EE4`/`$3EE5`/`$3EF8`/`$3EF9` +entity*2 (`ff6/notes/battle-ram.txt:1098-1101`), monster slots at +8 (`lib/ot6.lua:2650`).

### Status 1 (persists out of battle)

| Bit | Status | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| 0 | Blind/Dark | PARTIAL — field cure only | `ot6_field.lua:1754` `{bit=0x01, Eyedrop/Remedy}`; nothing in battle | Edgar's Flash, FC descent (the comment at `:1752-1754` records LOCKE arriving blind) | none |
| 1 | Zombie | **UNHANDLED cure** | `ot6_field.lua:1748-1755` `CARE_STATUS_CURES` has **no `0x02` row** (no Revivify); `:2201` `canCast` masks `0xC2` so a zombie is merely excluded from casting | Zombie Dragon/Ghost rows; Overcast (`$3E4D` bit o) | none |
| 2 | Poison | HANDLED both sides | field `ot6_field.lua:1750`; battle `gen_sabin_train.lua:186-190,509-514` (Antidote) — **generator-local, not in the lib** | Phantom Train, Zozo, Sealed Gate | none |
| 3 | Magitek | UNHANDLED | the opening Narshe fights are mashed A only (`gen_battle2.lua:52-61`) | Narshe opening, Magitek escape | #111 (closed) |
| 4 | Invisible/Vanish | PARTIAL | `gen_fc_alcove.lua:81,87` `ST1_INVISIBLE=0x10` → TERRA switches to Fire 2; one generator only | FC alcove Ninjas; Zozo | none |
| 5 | Imp | HANDLED (cured in battle) | `lib/ot6.lua` `M.ST1_IMP`, the driver's cure line (before the heals; the imp itself first, since @1029 zeroes its battle power and an imp keeps its Item row -- BattleCmdProp $01 carries IMP) through `M.statusCure` on the ROM's item records (Green Cherry $F8 STATUS1 $20, Remedy $F5 STATUS1 $65), one confirmed cure per target (`cureQueued`, the raiseQueued shape: measured two Green Cherries spent on one Imp before it). Measured on mrf_263 (probe_statuses mrf mode, Pipsqueak x5): `[status] f+5350 entity 0 char 4 is an IMP (STATUS1/2/3 $20/$00/$00 ...): its Fight lands for 0 ... cure: $F5 x3 (planned next turn)` -> `actor=0 cure entity 0's Imp with $F5 (3 in the bag): its own turn is worth nothing as it stands` -> `[status] f+5808 entity 0's Imp is CLEARED`. Field cure unchanged (`ot6_field.lua:1755`); `gen_sabin_train.lua:993-997` still declares Imp'd Sabin LOST (generator-local) | Pipsqueak ($041, special $45, SPECIAL on its 2nd line): maps 240, 262, 263, 269; Whisper on the train carries the special but its script never says SPECIAL (measured: 22 train fights, no Imp) | #187 |
| 6 | Petrify | PARTIAL — field only | `ot6_field.lua:1749` Soft/Remedy; `:2201` `canCast & 0xC2` | Sealed Gate, FC | none |
| 7 | Dead/Wound | HANDLED | `lib/ot6.lua:795 raiseDecision`, raise/top-up pair `:4457-4473`, `RAISE_WAIT` `:2519`; field revive `ot6_field.lua:2277` | everywhere | #165, #168 (closed) |

### Status 2 (battle-only, harmful)

| Bit | Status | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| 0 | **Condemned / Doom** | PARTIAL (logged only) | `gen_fc_escape.lua:250` prints the bit and the `$3B05` countdown; **no plan reacts**; `lib/ot6.lua:2372` names Condemned in a comment about watch expiry | Nerapa on the FC escape; Doom-casting rows | **#149 (closed) "Nerapa: a seed coin-flip"** — the lab issue, not the mechanic |
| 1 | Near Fatal | UNHANDLED (the bit) | the driver uses its own HP ratios (`healDecision` `lib/ot6.lua:714`) rather than the engine's bit | everywhere | none |
| 2 | Image | PARTIAL | `gen_fc_alcove.lua:88` `ST2_IMAGE=0x04` | FC alcove | none |
| 3 | Silence/Mute | PARTIAL (comment only) | `lib/ot6.lua:4186` notes "Mute greys Magic" and `:2572` records the #153 LOCKE case, but the row-grey read is the only defence: `$202F` bit 7 via `cmdRow` | FC escape Naughtys, Zozo | #153 (closed) |
| 4 | Berserk | HANDLED (planned around; no cure exists) | `M.turnDenied` (`M.ST2_BERSERK`); the driver never plans for or presses at a berserked actor's window, stands its park/idle/target-spin counters down, leaves it out of the raise rule's top-up race and reopens the care budget if it was the carer; `[status]` once per battle per entity with the ROM's cure verdict (Remedy's STATUS2 byte is $48: none). Measured on camp_escaped's world walk (probe_statuses, before the fix): `[landed f610] Berserk on entity 1 INTO ITS OWN OPEN WINDOW: atb=0097 $3AA0=8F menu=01 st=01 actor=1` then the old driver's `actor=1 char=3 plan=fight`, the engine closing the window inside the pulse, and `atb=0097 $3AA0=29` for ~1400 frames while its own Fights went out; the berserked actor's brief window passes through `$7BC2=$10` (an unknown-menu sighting, 1 pulse, 0 drops) | CrassHoppr ($02F) on the world map around the Phantom Forest (SPECIAL on its 1st line); Insecare ($0D0) maps 372-374; Telstar's MEGAZERK on a Blitz (not fought) -- not the Phantom Train or Zozo | #187; **#110 (closed)** |
| 5 | Confuse/Muddle | **HANDLED** | `lib/ot6.lua:655 ST2_MUDDLE=0x20`, `:669 muddleRule`, `:3085-3094`, `:4682-4687` un-muddle confirm | NoiseBlaster self-hits, Zozo, n024 | #170 (closed) |
| 6 | Sap/Seizure | UNHANDLED | no read; `multi-hit.md:199` notes Sap does not chip | Sealed Gate, FC | none |
| 7 | Sleep | HANDLED (planned around) / not measured live | `M.turnDenied` (`M.ST2_SLEEP`), the same gate the engine uses for Berserk (`peaflg STATUS12 {..., SLEEP, CONFUSE, BERSERK}` @0941 cancels the menu) and the same driver handling. No WoB fixture drew it: SlamDancer ($052, map 225) keeps its SPECIAL on its 3rd script line and died first in 20 Zozo clock-room fights under two policies; Suriander ($01E, 1st line) sits on maps 125/126/144 with no fixture on them. Not implemented: the wake-by-hit (a physical hit strips Sleep, @0c45), the Muddle rule's shape | SlamDancer (Zozo 225), Suriander/Rain Man/Pan Dora (125/126/144), Bleary (72/73); not the Phantom Train | #187 |

### Status 3 (battle-only, helpful/timing)

| Bit | Status | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| 0 | Dance | UNHANDLED | no read; Dance command window `$1F`/`$21` not in `KNOWN_ST` | Mog only — **N/A on the WoB route today** (Mog unrecruitable pre-FC, #134 closed); becomes live the moment #143/#146 land | #140, #129 (closed) |
| 1 | Regen | UNHANDLED | no read | esper/relic grants | none |
| 2 | Slow | UNHANDLED | no read; ATB model `lib/ot6.lua:688 atbEta` reads `$3AC8` constant but never the Slow bit | Sealed Gate, FC | none |
| 3 | Haste | UNHANDLED | same | same | none |
| 4 | Stop | HANDLED (planned around) | `M.turnDenied` (`M.ST3_STOP`): the gauge freezes where it was (measured `atb=0AFF -> 445F -> 4B1F` then `4B1F $3AA0=53` for 600 frames, camp_escaped's forest walk, seed 23) and no window opens; the driver's `[status] f+1542 entity 0 char 5 is under STOP (STATUS1/2/3 $00/$00/$10, atb=42F5 ...): the engine holds its gauge (Ot6Gate; $3AF1 counts $12 ticks down) and opens no window for it; planning around it` (seed 31, 2 of 12 forest fights). A list or target screen left open under it is closed with B (Wait mode would hold the clock); a Stop landing at the command window is not a stall (no press, counters stood down) | Ghost ($05A, special $54, SPECIAL on its 2nd line) in the Phantom Forest 130-135 and battle 47's ghosts (train_done.log: SABIN `s00/00/10/00`); Primordite 69/70; Parasite 125/126/144; Phase (FC 315) -- Number 024's script casts none | #187 |
| 5 | Shell | UNHANDLED | no read | boss self-buffs | none |
| 6 | Protect/Safe | UNHANDLED | no read | boss self-buffs | none |
| 7 | **Reflect / Wall** | **HANDLED** | `lib/ot6.lua:2650 MON_ST3=0x3F00`, `:2687` reflect flag per stage slot, `:1015 castVeto`, `:2714` refusal | Nerapa (FC escape), WallChange `$C1` rows | #156 (closed) |

### Status 4

| Bit | Status | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| 0 | Rage | UNHANDLED | Gau's Rage is driven only by `gen_sabin_gau.lua:376-383,431-434` (bespoke, fixture-local) | Veldt fixture only; Gau otherwise benched | #140, #40, #122 (closed) |
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
| `$3E4C` Special Status 1 (piranha, character Runic `c`, enemy Runic, Retort `r`) | `battle-ram.txt:1015-1022` | UNHANDLED | 0 reads of `$3E4C` | Celes's Runic is *pressed* but never *verified*; Cyan's Retort in `gen_sabin_gau:687` | #104 (closed) |
| `$3E4D` phantasm / overcast / control | `battle-ram.txt:1021-1025` | UNHANDLED | 0 reads | Sealed Gate, FC | none |
| `$3C80` can't-control / can't-sketch / can't-scan / can't-run / can't-suplex / **first strike** / harder-to-run | `battle-ram.txt:952-960` | UNHANDLED | 0 reads | every formation | none |

---

## D. Battle menu states — the `$7BC2` space

Defining source: `ff6/src/btlgfx/btlgfx_main.asm:12546-12621` — a 66-entry jump table, `$00`–`$41`. Harness whitelist: `lib/ot6.lua` `KNOWN_ST` = `$01, $05, $0A, $0E, $16, $19, $1B, $24, $27, $2B, $2C, $2D, $2E, $2F, $30, $38` (16 of 66). Guard for the rest: back out with B after 8 pulses. Since #188 the guard is measured: every run prints `[watch] unknown-menu drops by $7BC2 state: ...` (drops and sampled pulses per state) beside its verdict, and each state's first sighting in a battle is an `[unknown-menu]` log line with the actor, the command row and a screenshot.

| Window | State(s) | Defining line | Class | Evidence / note | Route exposure | Issue |
|---|---|---|---|---|---|---|
| Command select | `$05` | `btlgfx_main.asm:18753` | HANDLED | `lib/ot6.lua:2422`, `cmdRow` (`:2580`; e.g. `:3697`) | every turn | — |
| Target select | `$38` | `:16824` | HANDLED (entity and side) | `lib/ot6.lua:4320,4324,4412` `cross()` (`:3989-3999`) takes the side-crossing direction from `M.battleLayout`; the three hard-coded LEFT/RIGHT presses are gone (wt/driver-boost) | every turn | **#185** |
| Item select | `$0A` (+ open `$09`, close `$12`) | `:20764`, `:12992`, `:12880` | HANDLED (`$0A` only; `$09`/`$12` fall to the unknown guard) | `lib/ot6.lua:2422,2446` | every heal | #184 (open) |
| Magic/spell select | `$0E` (+ open `$0D`, close `$14`) | `:19616`, `:13020`, `:12869` | HANDLED (`$0E` only) | `lib/ot6.lua:2422,2441-2444` | Terra/Celes turns | #182 (open) |
| Esper/summon select | `$16` (+ close `$15`) | `:19868`, `:12935` | HANDLED | `lib/ot6.lua:2422` | post-magicite | — |
| Lore | `$19` open, `$1B` select, `$1A` close | `:13219`, `:19909`, `:12891` | HANDLED (open+select; `$1A` not listed) | `lib/ot6.lua:2428,3763-3778` | Strago (Thamasa+) | — |
| Throw | `$2B/$2C/$2D` | `:13145`, `:12858`, `:20469` | HANDLED (all three) | `lib/ot6.lua:2434,3906-3908` | Shadow legs | — |
| Tools | `$30` select, `$2E` open, `$2F` force-close | `:20613`, `:13182`, `:12802` | HANDLED (all three) | `probe_tools.lua` (2026-09-16): A on the Tools row `$05 -> $2E` (~7 frames, wItemList built) `-> $01 -> $30`; B from the list `-> $01 -> $05` directly (`CloseToolsWindow` is a `jsr` there, `$2F` is not written); A on a tool `-> $38`, B `-> $30`. `$2F` is the `$7BCB` force-close after a commit (`$30 -> $2F -> $01 -> $05`). OT6's Blitz, Bushido and Steal ladders reuse this shell (`$6168`), so their open/close pass here too. Under a skill plan the driver waits `$2E`/`$2F` out (`ST_TOOLS_OPEN`/`ST_TOOLS_CLOSE`) | Edgar every fight; Sabin's Blitz, Cyan's Bushido, Locke's Steal through the same shell | #188 |
| **Blitz** | (OT6 retired the `$3D` pad-edge state, `btlgfx_main.asm:12617`; Blitz now routes through the generic list) | ASSUMED | cmd id `CMD_BLITZ=0x0A` at `lib/ot6.lua:2420`, used `:3238-3241, 3870-3872`, but **no Blitz window state is in `KNOWN_ST`** | Sabin, every fight from Figaro on | #115-adjacent, none direct |
| **SwdTech / Bushido** | `$37`, close `$36` | `:19072`, `:12697` | **UNHANDLED in lib** | only `gen_sabin_gau.lua:672-687` (Retort), fixture-local | Cyan from Doma to the FC | **#141 (closed) — committing a MANUAL row past 1× freezes at `st=$01`** |
| **Runic** | command `$0B`, no list window | `battle-lists.txt:41` | ASSUMED (blind key sequence) | `gen_narshe_battle.lua:141` `push("down","a","a")`; `gen_kefka_won.lua:67` identical | Narshe defense, Kefka fight | #104 (closed) |
| **Rage** | `$1C` open, `$1E` select, `$1D` close | `:13248`, `:20235`, `:12902` | PARTIAL, fixture-local | `gen_sabin_gau.lua:431` `ST_RAGE` | Veldt fixture; Gau benched after | #140, #47 (closed) |
| **Dance** | `$1F` open, `$21` select, `$20` close | `:13274`, `:20352`, `:12913` | UNHANDLED | — | **N/A on the current WoB route** — Mog unrecruitable pre-FC (#134) | #140, #129 (closed) |
| **Slot** | `$06` open, `$08` select | `:13322`, `:19324` | UNHANDLED | — | Setzer joins at the Blackjack (`gen_opera7_blackjack`) and rides the whole Vector→FC stretch | none |
| **Sketch / Control** | `$0D`/`$0E` commands; Control uses `$3E4D` bit c | `battle-lists.txt:42-43` | UNHANDLED | — | Relm joins Thamasa; Sketch is a known vanilla-bug area | #28, #123 (closed) |
| **Morph / Revert** | commands `$03`/`$04` | `battle-lists.txt:34-35` | UNHANDLED | `$3EE2`, `$3B04`, `$3F30` all unread | Terra post-esper | none |
| **Leap** | command `$11`, disable bit `$2F49` bit 3 (`battle-ram.txt:616`) | `battle-lists.txt:42` | PARTIAL — avoided, not used | `gen_sabin_gau.lua:369-383` explicitly refuses Leap when it is row 0 | Veldt | #122 (closed) |
| **MagiTek** | `$28` open, `$2A` select, `$29` close | `:13298`, `:20405`, `:12924` | UNHANDLED | Narshe opening is mashed A (`gen_battle2.lua:52-61`) | Narshe opening, Magitek escape | #111 (closed) |
| Equip / weapon-shield (Runic's sword pick) | `$0B`, `$0C`, `$13`, `$10` | `:12728`, `:21421`, `:12755`, `:12743` | UNHANDLED | — | any Runic/Gogo path | none |
| Row `$24` / Def. `$27` | `:19239`, `:19186` | HANDLED (B-out) | `probe_rowdef.lua` (2026-09-16): LEFT at `$05` opens Row (`$05 -> $01 -> $24`), RIGHT opens Def. (`-> $27`); B or the opposite direction closes (`-> $01 -> $05`, cursor kept); the opening direction is not read inside (LEFT held 120 frames in `$24` moved nothing -- the v0.17 train_done attempt-1 no-effect trip, a LEFT held from the field into the battle by `gen_sabin_train.lua:1169-1176`). The driver backs out with B on every path (`[side-window]` log line) and keeps its plan | a direction reaching the command window | #188 |
| Character status window | `$3F`, `$40`, `$41` | `:12627`, `:12637`, `:21846` | UNHANDLED | `$41` is *"status window for character target select"* — reachable from the target screen the driver lives in | any ally-target turn | none |
| Steal/Capture, Jump, Mimic, X-Magic, GP Rain, Health, Shock, Possess | `battle-lists.txt:35-52` | UNHANDLED | Locke's Filch is driven only by `gen_thamasa_fire.lua:663-677` (`ST_THIEF_A`) | Locke throughout; Filch at Thamasa | #55, #68 (closed) |
| **Menu state queue** `$7BF0`, `$7BF1-$7BFF`; cursor queue `$7BC3-$7BC9` | `battle-ram.txt:1826-1827, 1851-1852` | UNHANDLED | the driver reads only `$7BC2` (cursor state) and `$7BCA` (open flag) — `lib/ot6.lua:2417` — so a *queued* transition is invisible and reads as a stall | every transitional frame | none |

---

## E. Target-menu geometry — the #185 root cause, named

| Mechanic | Defining game source | Class | Evidence | Note |
|---|---|---|---|---|
| **Selected target group `$7ACE`** — `0` = monsters-left, `1` = characters-left, `2` = monsters-right, `3` = characters-right | `ff6/notes/battle-ram.txt:1698-1702`; driven by `btlgfx_main.asm:16905-16926` (RIGHT `inc2`, LEFT `dec2`, both gated on `w7e7ace & $02`) | HANDLED | `lib/ot6.lua` `M.battleLayout` reads it with `$201F`; `cross("monsters"/"chars")` in `newFightDriver` replaces the three hard-coded presses, and `steerWatch` checks every press against `$7B7D/$7B7E/$7B7F/$7ACE` (a press that moves nothing twice is not pressed again; `FIGHT DRIVER STUCK` when no derived direction moves it). The evidence lines are in section A | the 9000-frame hang is now a 2500-frame win on the same snapshot (`probe_backattack_j39`: `battle over at f2616 (+2553) ... party 540/481/620/451 (4 alive), monsters up 0`) |
| Side tables `$7B79` monsters-left / `$7B7A` chars-left / `$7B7B` monsters-right / `$7B7C` chars-right | `battle-ram.txt:1773-1776` | UNHANDLED | 0 reads in `lib/` | the layout-independent way to answer "which press reaches the monsters" |
| `$7B7D` chars-lit / `$7B7E` monsters-lit / `$7B7F` all-latch | `battle-ram.txt:1777-1779` | HANDLED | `lib/ot6.lua:2447,2463`, used at `:4318-4432`, in the press signature `tgtSig` (`:3963-3966`) and in the park signature `:4052-4058` | correct, and since wt/driver-boost also the no-effect check: the four cells are the press signature |
| `opts.focus` monster kill order | — (harness construct) | ASSUMED | `lib/ot6.lua:4367-4432`; authored masks at `gen_n128.lua:163`, `gen_terra_returned_checkpoint.lua:115`, `gen_zozo4_dadaluma.lua:133` | the comment at `:4371-4374` says masks "follow the on-screen formation layout" — which is exactly what the battle type changes. Every authored focus mask is a normal-arrangement mask |
| Group-vs-slot targeting (`TARGET::INIT_GROUP`, no `MANUAL`) | `btlgfx_main.asm:16895-16899` | HANDLED | `lib/ot6.lua:4394-4401` (the Bio Blaster `$7B7E=$2C` finding) | — |
| `CheckTargetsBattleType` — pincer/side retarget the *engine* applies | `battle_main.asm:15136,15165,15185` | UNHANDLED | no read | a confirmed target can be silently re-aimed and the driver's damage watch mis-attributes it |

---

## F. Multi-part monsters, transformations, boss stage swaps

| Mechanic | Defining game source | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| Multi-part bodies (one formation, several linked slots) | `ff6/src/battle/battle_monsters.dat` (+1 present mask, +2..+7 indices, +14 high bits — decoded `tools/audit_encounters.py:86-94`) | PARTIAL | `lib/ot6.lua:475 monsterIds`, `:2678 stageSlots` see slots; nothing models "these slots are one creature" | **Number 128 + Left Blade `$140` + RightBlade `$13f`** (`break-coverage-vector.md:205,221`, `gen_n128`); **AirForce `$113` + Laser Gun `$145` + MissileBay `$147` + Speck `$146`** (`floating-continent-route.md:169,465`, `gen_fc_landing`) | #19 (closed), #92 (closed) |
| Script-spawned part (Speck) | AI `F5` (`battle-lists.txt` AI cmd list) | HANDLED | `lib/ot6.lua:2678-2691` presence-filtered | FC approach | #172 (closed) |
| Formation stage swap mid-fight (Ifrit→Shiva) | AI `F2 xx yyyy` "Change Battle"; `battle_main.asm:8185-8196` `CondBattle` | HANDLED for the absorb guard, UNHANDLED as an event | `lib/ot6.lua:2661-2677` (the note explaining why `$3F45` is wrong), `:2678` | battle 70 `gen_ifrit_magicite` | #172 (closed); **#177 open** |
| Metamorph / monster→item transform | `ff6/src/battle/metamorph_prop.dat` | N/A | — | no Ragnarok esper on the WoB route | none |
| Broken-shield / OT6 gate interaction with queued actions | `ff6/src/battle/ot6_break.asm` | HANDLED | `lib/ot6.lua:2736-2756` chip model, `SH_CUR/BRK_TICKS` `:2648` | everywhere | #66, #85 (closed) |

---

## G. Fail and recovery flows

| Mechanic | Defining game source | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| Party wipe in battle | — | HANDLED | `lib/ot6.lua:525 wipeVerdict`, `:502 partyHp`; `ot6_field.lua:63 partyWipedInBattle` | everywhere | #166, #114, #163 (closed) |
| Game Over | event script `GameOver` (`$CC/E568`), plus a battle-module path that bypasses it | HANDLED (as a canary, not a recovery) | `lib/ot6.lua:5804-5895, 6019-6050` (inside `M.run`, `:5762`): read-watch + exec-watch, `M.gameOverFired` `:5856`, pad freeze `:5877`, fail `:6042` | everywhere | #153 (closed); **#178 open** (retry-from-checkpoint is not yet the default) |
| Dead actor → raise → top-up | — | HANDLED | `lib/ot6.lua:795 raiseDecision`, `:2512-2519 raisePending/topUpOwed/RAISE_WAIT`, `:4457-4473` | everywhere | #165, #168 (closed) |
| Healer death lockout | — | HANDLED | any live caster can be the healer (`:2469-2473` comment; `:3155` `cmdRow(actor, CMD_MAGIC)`) | everywhere | #128 (closed) |
| Unknown-menu stall guard | — | HANDLED (as a guard) | `lib/ot6.lua:2481, 4082-4091` — 8 pulses then B + `dropPlan("unknown_menu")` | this is what turns 54 unknown menu states into a *slow* failure rather than a hang; the Phantom Train Throw-list wipe is the recorded case (`:4004-4009`); since wt/driver-boost a third drop in one state fails fast instead (`M.recoveryCount` `:5601`, called at `:4038,4075`) | none |
| Parked-known-window watchdog + pulse budget | — | HANDLED | `lib/ot6.lua:4014-4078` (`parkN > 12`, `budget = min(140, 40+idx)`) | Sealed Gate, IAF, dadaluma | none |

---

## H. Field and world

| Mechanic | Defining game source | Class | Evidence | Route exposure | Issue |
|---|---|---|---|---|---|
| Field passability (both engine branches, incl. diagonals) | `UpdatePlayerMovement`; `field-ram.txt:139-158` | HANDLED | `ot6_field.lua:197-232,263-317` | every walk | — |
| **NPC/object blocking** `$7E2000[dst]` bit 7 | `field-ram.txt:516-530` (object data, 41 B × 50) | HANDLED | `ot6_field.lua:305` "an NPC/object stands there"; blocked-edge learning + re-BFS `:346-390` | every town/dungeon walk | #22 (closed), #134 (closed) |
| Wandering-NPC approach | `field-ram.txt:516` | HANDLED | `ot6_field.lua:1547 chaseTalk` (re-plans each aligned frame), `:3882 talkToObj` | 5 + 11 generators | — |
| Event triggers on tiles | `$078E` "party is on a trigger (disables random battles)" (`field-ram.txt:503`); `$1EB6` bit t tile-event bit (`field-ram.txt:~1075`) | **UNHANDLED (as state)** | 0 reads of `$078E`; triggers are handled *by consequence* — `hasControl()` (`lib/ot6.lua:1885`, movement type `$087c` low nibble 2=user/4=event) and `advanceStory` (`ot6_field.lua:768`, 39 generators) | every scripted step-on | #159 (closed — a wedge with no control and no battle) |
| Doors / map transitions | `$1127` open-door count, `$1129-$1158` door XY (`field-ram.txt:678-679`) | HANDLED (by map-id + settle), UNHANDLED (as door state) | `ot6_field.lua:2816 crossDoor` keys on `mapLow()` + brightness (`:2791 bright`), not on `$1127`; 6 generators | every interior | — |
| Save points | `$01BF` (shared SavePoint script) | HANDLED | `ot6_field.lua:4210 saveGame` `:4200-4226`; 6 generators | Gate Cave, MRF, N024, minecart platform, Thamasa | #125, #10 (closed) |
| Treasure chests | `$1E40-$1E7F` treasure bitfield (`field-ram.txt:1035`) | HANDLED | `ot6_field.lua:1938 chestOpen`, `:1959 openChest` (asserts the bit, not the dialog, `:1988-1995`); 20 generators; audit `tools/audit_chests.py` | route-wide | #84 (closed) |
| **Dialog choices** `$056E` cur / `$056F` max / `$056D` changing | `field-ram.txt:396-401` | PARTIAL — no lib helper | lib only *guards*: `ot6_field.lua:1551,1569` (chaseTalk refuses a blind A), `:4051-4052` ("an A press always takes option 0, so every prompt on a route is answered by a choice-steering rider instead"). Each generator re-rolls its own `choicePick`: `gen_banon.lua:228`, `gen_banquet_done.lua:399-407,701`, `gen_gate_cave_save.lua:392`, `gen_opera5_dance.lua:28-35`, `gen_thamasa_fire.lua:209`, `gen_voyage.lua:153` | Banon (×3 for the Genji Glove), banquet, Gate Cave, aria, Thamasa | #106 (closed) |
| Shops — item/weapon/armor/relic | menu state `$26`: `$25` shop main, `$26` buy list, `$27` quantity | ASSUMED | `ot6_field.lua:2870 shopTalk` (opens on `$25`), `:2048 buyItem` takes a **hard-coded `row`** and steers `$004E` to it (`:2094-2098`) — it never looks the item id up in the shop's list. Shop *type* is never read; all four types are driven identically | South Figaro (`gen_kolts:788,794,843`), Figaro, Narshe, Vector, Jidoor (`probe_jidoor_shop`) | **#176, #179 (open)** |
| Inn | — | ASSUMED (bespoke) | `gen_kolts.lua:726,733-737,879` `innRest` with asserted talk-spot coordinates (81,19) | South Figaro | none |
| **Party swap / split party** | `$0762` enable party change, `$1A6D` current party, `$07FB-$0801` party chars (`field-ram.txt:472,940,510-513`) | PARTIAL | `ot6_field.lua:3766 newPartySelect` — **1 generator uses it**; `$0762` has 0 reads; `$1A6D` 27 reads (mostly contract assertions) | scenario split (3 legs), Narshe defense (3 groups), Blackjack swap room, FC party select (`gen_fc_landing:7`) | #21 (closed) |
| Timed scenes | `$1188-$119F` four 6-byte timer records (`field-ram.txt:684-690`) | HANDLED | `ot6_field.lua:2115 eventTimerLive` — menus stay out while any counter is nonzero | opera rafter chase, banquet, aria | #160, #119 (closed) |
| **Vehicles — chocobo** | `$11FA` vehicle index (`world-ram.txt:205`), chocobo-passable tile bit (`world-ram.txt:110`) | ASSUMED | `worldPassable` (`ot6_field.lua:931`) is **on-foot only**: `(prop & 0x0010) == 0`, with the comment "The engine checks nothing else". `$11FA` is asserted (`gen_edgar.lua:601`, `gen_kolts.lua:908,918-924`) but never fed into the model; the route dismounts rather than navigates mounted | South Figaro chocobo stable | none |
| **Vehicles — airship** | `$11F3` forced-aboard, `$11F4` altitude, `$1F62/63` airship XY, `$1F64` bit 13 aboard (`world-ram.txt:198,205,213`) | PARTIAL — contract assertions only | `ot6_contract.lua:239-246, 291-307, 384-397, 437-456` pin the Blackjack's cells per checkpoint; no navigation reads them | Blackjack from the Opera to the FC; the crash | #131 (closed) |
| Vehicles — raft / Lete / Serpent Trench | `world-ram.txt:121-131` vehicle states; `$1EB6` bit s trench arrow | HANDLED (as scripted rides) | `gen_lete`, `gen_rapids`, `gen_sabin_trench` drive them as timed/choice scenes | Lete River, Serpent Trench | #101 (closed) |
| Ferry (South Figaro ↔ Nikeah) | — | N/A on the current WoB route | the route crosses via the Sabin leg overland | — | — |
| World-map encounters | `world_battle_rate.dat`, `world_battle_group.dat`; tile prop bit `$40` "random battles enabled here" (`ot6_field.lua:929`) | PARTIAL | `worldNavTo` (`:1025`) carries the same `playBattles` contract; the `$40` bit is decoded and **explicitly discarded as "informational"** (`:928-929`), so no route step can predict its own encounter exposure | Narshe→Figaro, Sabin's world leg, Gate Cave approach, WoR landing | #24 (closed) |
| Field random-encounter pool + fleeability | `map_prop.dat +5` bit 7, `sub_battle_group.dat`, `rand_battle_group.dat`, `battle_prop.dat` | HANDLED (static) | `tools/audit_encounters.py` — back, pincer and side bits per formation, and per-map / per-route arrangement lists (#186) | every field map | #82 (closed) |
| Field menu state whitelist | `$26` `zMenuState` | HANDLED | `ot6_field.lua:1765-1771` `CARE_SCREENS` (12 screens named; "every other value … is a fade or a one-frame init"); router presses B off-path | every care visit | **#184 (open)** |
| Field status cures | `field_menu.asm:722-731` `CheckSkillValid`; `item.asm:2282-2286` wound branch | HANDLED for petrify/poison/dark/imp; **zombie missing** | `ot6_field.lua:1748-1755`, `:2201` (`& 0xC2`) | route-wide | none |

---

## I. Ranked gaps — UNHANDLED and ASSUMED, by route exposure

**Tier 1 — fires on ordinary random encounters, i.e. hundreds of times per route:**

1. **Back attack `$201F=1` — HANDLED** on wt/driver-boost (`M.battleLayout`, section A/E evidence). Issue **#185**.
2. **Side attack `$201F=3` — HANDLED by the jump tables, unmeasured live** (no fixture draws one yet). 3× run difficulty still unread.
3. **Pincer target steering — HANDLED by the jump tables, unmeasured live** (the flee half was already handled).
4. **`$2F48` back/side permission bits never audited — UNHANDLED.** `tools/audit_encounters.py:99` reads `$40` only, so the route cannot even *list* which of its 60-odd maps can roll a back attack. No issue. This is the cheapest way to convert #185 from a discovery into an inventory.
5. **`opts.focus` masks are normal-arrangement literals — ASSUMED.** `gen_n128:163`, `gen_zozo4_dadaluma:133`, `gen_terra_returned_checkpoint:115`.
6. **Preemptive strike `$b0` bit 6 — HANDLED** (read with the layout, logged, the first-turn heal check accounts for the free round; #186's driver half).
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
16. **Shop `buyItem` hard-codes the list row — ASSUMED.** `ot6_field.lua:2048`. Interacts with #176/#179.
17. **Party swap has a lib helper used once — PARTIAL.** `newPartySelect`; the scenario split, Narshe defense and FC select each roll their own.
18. **Zombie has no field cure row — UNHANDLED.** `ot6_field.lua:1748-1755`.
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

- **The knowledge exists; the lib does not have it.** `$3EE4` status 1, `$3EE5` Image/Condemned, `$3B05` Condemned counter, Retort, Rage, Filch, and choice-steering are each implemented correctly in *one* generator or probe and never promoted. The back-attack hang was that pattern's cost: `gen_thamasa_fire.lua:653` had known the right answer (`$7ACE`, the target group) since the pincer work; wt/driver-boost promoted it into `M.battleLayout` (`lib/ot6.lua:959-994`).
- **The unknown-menu guard (`lib/ot6.lua:4082-4091`) is load-bearing.** It is the only thing standing between 54 unmodelled menu states and a hard hang, and it converts each of them into ~8 wasted pulses plus a dropped plan. A count of `dropPlan("unknown_menu")` events per run, bucketed by `st`, would turn the remaining half of this table into measurement rather than inference — the unknown states are enumerable from `btlgfx_main.asm:12556-12621` and the driver already logs `st` on every drop.
