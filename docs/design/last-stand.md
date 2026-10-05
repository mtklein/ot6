# Last-stand counters: the class, all 17 species (#258)

A last-stand counter is a monster retaliation gated on `if_num_monsters N`
(`FC 13 01 N`): it answers a hit after which N or fewer monsters stand.
The Chitonid's Sneeze was the first member met (route-wor-sabin.md); this
doc enumerates the class from the ROM (docs/guidelines.md, "few
foreseeable surprises") and gives the right play for each body.  Raw
data, the scripts and every byte quoted are under
`build/attempts/wt/v026-route/laststand/` (`ai_bytes.txt` is each
species' AI script as the ROM holds it; it matches
`ff6/src/battle/ai_script.asm` byte for byte).  Read-only analysis of the
v0.25 ROM; the play measurements are listed at the end.

## What the driver's rule should read (the ask of `Driver:readLastStand`)

The driver today (`opts.lastStand`: Sneeze by default, `true` for every
body, `false` off) treats every last-stand body as able to fire on its own
killing blow and every hit as a trigger.  The table below shows three
things the rule should read from the script instead, all decodable the way
`M.partRoles` already walks it:

1. **The `if_self_dead` guard** (`FC 12 00 00 | FE` opening the
   retaliation): seven species carry it and never counter on their own
   killing blow (Apokryphos, Baskervor, TumbleWeed, Ing, GloomShell,
   Crusher, Muus).  For these, "kill it first" is exposure-free whenever
   any other body stands; for the unguarded ones it is exposure-free only
   while more than N others stand at its death.
2. **`if_cmd` / `if_hit`**: Ing and Bug counter only Fight, Mind Candy only
   Steal/Mug, Muus only Magic.  The right play there is the verb, not the
   order: finish a lone Ing or Bug with anything but Fight; do not Steal a
   lone Mind Candy; do not cast at a lone Muus.
3. **Death-only counters** (`if_num_monsters` + `if_self_dead` true:
   Coelecite, Face): only the killing blow fires them, so they go first
   while others stand, or the party floats (earth).

And the effect class decides whether the order is worth turns: removal
(Sneeze) and Petrify/Death always; damage-only counters (Behemoth's Take
Down, Crusher's Lifeshaver, Muus's Battle) only when the party is thin.
The driver is not this branch's file; the rule is filed with the
coordinator.

## Where the census came from

The census is `build/attempts/wt/wor-tzen-door/lab/laststand_census.lua`. It is
standalone Lua (it runs `tools/tests/lib/ot6.lua` with no emulator).  For species
0..$17F it walks the script with `M.partRoles` (`tools/tests/lib/ot6.lua:3716-3760`).
A species counts if its retaliation section holds a block whose conditions
include `FC 13 01 N` (`if_num_monsters N`).  It keeps that block's attack bytes
and leaves out $FE (NOTHING).  It then lists every `battle_monsters.dat`
formation that holds such a species next to one that has no such block.  Added
by 59f7373f and kept in 747fb8ca (`git log --all -S lastStand`).

The driver's handling is `Driver:readLastStand` (`tools/tests/lib/ot6.lua:5502-5574`).
Every counter body is focused first while a plain body stands.  By default it
does this only when the counter throws `M.SNEEZE = 0xCB`;
`opts.lastStand = true` widens it to every body and `false` turns it off.

**What the census and lib model leave out:** they treat every last-stand block
as able to fire on its own killing blow.  That is true only for scripts with no
`if_self_dead` guard (rule 3 below).  Seven of the 17 species carry the guard,
and their counters never fire on the killing blow.  The census also does not
read `if_hit` / `if_cmd`, which narrows the trigger a lot for four species
(Ing, Bug: Fight only; Mind Candy: Steal/Mug only; Muus: Magic only).  It also
misses that Mag Roader $0F3's "counter" is another species' main script (see
its row).

## Engine rules (cited once, used by every row)

All lines are in `ff6/src/battle/battle_main.asm` unless named.

1. **When a counter is queued.** `CheckRetal` (`:12859`) runs after every
   action (`:3188`).  For each present target (`$3aa0.0`) with counters enabled
   (`$341a`, `:12864`), a target whose bit is in `$3a56` ("characters/monsters
   that have died", set by `setnowdead` `:11994-11996`) takes the branch
   `bit $3a56 / bne` (`:12882`).  It goes straight to queueing its counter
   (`@4c9d`, `:12910`).  This **skips** two tests: "can't counter a counter"
   (`$b1` bit 0) and OT6's Broken gate (`jsl Ot6MayAct`, `:12894`, whose
   comment says it sits below this branch on purpose so that `if_self_dead`
   scripts still run).  **So a monster killed by an action always runs its
   retaliation script.**
2. **When it executes.** `BattleLoop` drains the counter queue (`:87-97`,
   `jmp ExecRetal`) *before* `CheckBattleEnd` (`:113`).  So a counter queued by
   the last monster's death still runs.  `ExecAIRetal` (`:12802-12852`) runs
   the script in full.  It runs it restricted (`dec $3a98`, "only execute until
   the first wait / end if / end", `:12827`; in that mode `Ot6AISkip` skips
   every command below $FC, i.e. every attack, `ot6_break.asm:1567-1582`) in
   three cases: the monster has Sleep(psyche) / Muddle / Berserk
   (`$3e60 & $b000`, `:12815-12817`); it has Freeze / Stop (`$3e74 & $0210`,
   `:12818-12820`); or it has a charm target (`$3394`).
3. **`FE` ends the run.** `AICmd_fe`/`AICmd_ff` (`:4417-4421`) set `$f5=$ff`
   and return.  So the first block whose conditions all hold runs, and the
   counter stops at its `end_if`.  A failed condition skips past the next
   FE/FF (`conditionmiss`, `:4449`).  **The vanilla guard
   `if_self_dead / end_if` (`FC 12 00 00 | FE`) at the top of a retaliation
   script makes a dead monster do nothing.**  It is the opening block of
   Apokryphos, Baskervor, TumbleWeed, Ing, GloomShell, Crusher and Muus.
4. **`if_num_monsters N`** = `FC 13 01 N` (`ff6/include/battle/ai_script.inc:544-546`).
   `AICond_13` (`:4980-4990`) is `lda N / cmp $3a77`, true when monsters alive
   <= N.  `$3a77` counts monsters without Wound/Petrify/Zombie (`status1 & $c2`),
   plus characters acting as enemies (`:12649-12692`).  It is read when the
   counter runs, after the action's deaths.
5. **`if_hit`** = `FC 05 00 00`.  `AICond_05` (`:4841-4849`) needs `$327c,x`
   valid.  That byte is written only in `ApplyDmg` (`:3017-3034`, `sta $327c,y`
   "set target that just attacked you").  ApplyDmgHP (`:3047-3060`) returns
   carry set whenever net damage was taken, dead or alive (the `:3015` comment
   "set = target died" is wrong for the alive case).  **Unknown:** I found no
   code that clears `$327c` between actions.  So I could not determine whether
   a 0-damage action (a status spell, Steal) on a monster damaged earlier
   still satisfies `if_hit`.
   **`if_cmd A, B`** = `FC 01 A B` (`AICond_01`, `:4804-4818`) compares the
   last command used on it (`$3d48`, set in `_setblacklist` `:8910-8919`).
   Commands are `BATTLE_CMD` in `ff6/include/const.inc:526`: $00 Fight,
   $02 Magic, $05 Steal, $06 Capture (Mug), $19 Summon.
6. **Odds.** `attack a, b, c` (`F0 a b c`) picks one of three at random
   (`AIRand3`, `:4427`).  A NOTHING ($FE) pick moves on to the next command,
   which here is always the block's FE.  So `F0 X FE FE` fires 1/3 of the
   time, `F0 X X FE` 2/3, `F0 a b c` always, and a bare id (`15` = Quake)
   always.
7. **OT6 Break.** A Broken monster that is alive does not counter
   (`Ot6MayAct`, `ot6_break.asm:1361-1371`, below the died branch).  Its dying
   counter "runs as it always has" (`Ot6AISkip`, `ot6_break.asm:1586-1594`:
   wound/petrify or 0 HP → run).  So Break suppresses the counters to
   non-lethal hits only.

Taken together: for a block gated on `if_num_monsters N` and a hit **without**
the guard, every qualifying hit after which <= N monsters stand fires it, and
so does the monster's own killing blow.  Killing it first is exposure-free only
if more than N others still stand at its death.  **With** the guard, only the
non-lethal hits taken while <= N stand fire it, so killing it first while
others stand avoids it entirely.

## The table

"KB" = fires on its own killing blow.  Odds per rule 6.  Levels/HP from
`tools/route_data.py species` (MonsterProp in the ROM).  Script source lines
are `ff6/src/battle/ai_script.asm`.

| # | species | L / HP | last-stand counter (ROM bytes; source) | effect class | trigger exactly | KB? | formations (others) | where met | right play |
|---|---|---|---|---|---|---|---|---|---|
| 1 | $00C Apokryphos | 26 / 1900 | `FC 12 00 00 \| FE \| FC 13 01 01 \| FC 05 00 00 \| F0 94 95 96` (`:1585-1594`): always one of L.5 Doom / L.4 Flare / L.3 Muddle | status + damage (L.5 Doom = Death to levels divisible by 5; L.4 Flare power 66; L.3 Muddle) | guarded; hit while monsters alive <= 1 | **no** | **$0B2** (Misfit x2), **$0B7** (Brainpan x2, Misfit); also $0B3 solo, $0B6 x3 | Floating Continent, map 394 (WoB), group 112 (+Rand words $80B1/$80B4/$80B7/$80B9) | kill first.  Solo / last one: kill it in one burst (each non-lethal hit while alone draws a guaranteed L.5/L.4/L.3) |
| 2 | $01D Baskervor | 22 / 750 | `FC 12 00 00 \| FE \| FC 13 01 01 \| FC 05 00 00 \| F0 CB FE FE` (`:1340-1351`): 1/3 Sneeze | **removal** (Sneeze: status word $20000000 = Hide; the member leaves the fight and its reward) | guarded; hit while alive <= 1 | **no** | **$0A2** (Cephaler); also $0A0 solo, $0BF x2 | WoB world, group 24, sectors (7,2)-(7,4) terrain t0/t3: Crescent Island (landing (232,150) = sector (7,4)) | kill first (zero exposure).  Solo / last: one-burst kill |
| 3 | $020 Behemoth | 28 / 5800 | `FC 01 19 19 \| F0 DF DF FE \| FE \| FC 13 01 01 \| FC 05 00 00 \| F0 EF EF FE` (`:1570-1580`): 2/3 Special = Take Down | damage (special $23, +4 multiplier steps, x3) | **unguarded**; hit while alive <= 1.  Plus a separate, ungated first block: any Summon on it, 2/3 Meteo (power 60) | **yes** (by rules 1-4; not measured) | **$0BA** (Misfit x2); also $0B1 solo, $0BB x2 | Floating Continent map 394, group 112 | kill first while both Misfits stand (its death leaves 2: no fire).  In $0BB the first Behemoth's death leaves 1 and fires.  Do not Summon on it |
| 4 | $02C HermitCrab | 26 / 305 | `FC 13 01 01 \| FC 05 00 00 \| F0 EF FE FE` (`:1806-1817`): 1/3 Special = Rock | **status: Petrify** (special $46) | **unguarded**; hit while alive <= 1 | **yes** | **$0CF** (HermitCrab x2, Pm Stalker); **$0D0** (Scorpion) | $0CF: Tzen's collapsing house, map 311 (WoR), group 128.  $0D0: no source found | crabs first.  Crab 1's death leaves 2: safe.  Crab 2's killing blow leaves 1: one unavoidable 1/3 Rock.  The other order exposes every hit on a lone crab.  Petrify protection (Ribbon) makes it moot |
| 5 | $034 TumbleWeed | 55 / 6200 | `FC 12 00 00 \| FE \| FC 13 01 01 \| FC 05 00 00 \| F0 EB FE FE` (`:3030-3041`): 1/3 Lifeshaver | damage (earth, power 84) | guarded; hit while alive <= 1 | **no** | only $147 (TumbleWeed x4).  Not in the census list: no plain partner | WoR world, group 52, sectors (5,0),(5,1),(6,1),(5,2) t0/t2 | the last of the four counters non-lethal hits.  Finish the last one in one burst, or bring them down together with multi-target damage |
| 6 | $048 Ing | 21 / 1100 | `FC 12 00 00 \| FE \| FC 01 00 00 \| FC 13 01 01 \| F0 EF FE FE` (`:1476-1487`): 1/3 Special = Glare | **status: Dark** (special $40) | guarded; **Fight** used on it while alive <= 1 (no `if_hit`) | **no** | **$097** (Zombone, Ing x2); also $098 Ing x3 | Cave to the Sealed Gate (WoB): $097 in group 94 (map 384 BASEMENT 3, map 388) and group 95 (map 385 BASEMENT 2); $098 in groups 93/94 (maps 383, 387, 384, 388) | use Magic (not Fight) on a lone Ing, or kill it first |
| 7 | $07C Chitonid | 26 / 1111 | `FC 13 01 01 \| FC 05 00 00 \| F0 CB FE FE` (`:1751-1758`): 1/3 Sneeze | **removal** (Sneeze/Hide) | **unguarded**; hit while alive <= 1 | **yes** (by rules 1-4; reported in the route doc, see "Not determined") | **$0C9** (Gigan Toad x2); **$0CC** (Osprey, Gigan Toad); $082 (Sprinter), $084 (Woolly), $085 (Lunaris x2) | $0C9: WoR group 33, sectors (3,4)-(3,6) t3.  $0CC: WoR group 34, sectors (4,5)-(4,7) t3 (Albrook/Tzen plains).  $082/$084/$085: groups 87/86, which no map, sector or event uses: **unmet** | kill first **while both others stand** (death leaves 2: no fire).  In a 2-body formation one exposure (the killing blow) cannot be avoided by order.  Stop/Sleep on it suppresses its counters while alive (rule 2) |
| 8 | $08A GloomShell | 41 / 2905 | `FC 12 00 00 \| FE \| FC 13 01 01 \| FC 05 00 00 \| F0 EF FE FE` (`:3122-3133`): 1/3 Special = Rock | **status: Petrify** | guarded; hit while alive <= 1 | **no** | **$14D** (Prussian); also $14E x3 | WoR world, group 56, sectors (6,6),(7,6),(6,7),(7,7) t3 | kill first |
| 9 | $08C Mind Candy | 15 / 290 | `FC 13 01 01 \| FC 01 05 06 \| F0 EF FE FE` (`:870-879`): 1/3 Special = SleepSting | **status: Sleep** (special $4F) | **unguarded**; **Steal or Capture(Mug)** on it while alive <= 1 | yes, only if the killing blow is a Mug | **$060** (Iron Fist x2, + Mind Candy x2); **$062** (Over Grunk x2, + Mind Candy x3); also $065 x4 | WoB west (Zozo/Jidoor side): group 10 (sectors (0,2)-(1,4) t0), group 11 (forest t1, (0..1,0..4)), group 13 ($065 only) | **ignore** unless stealing: don't Steal/Mug a Mind Candy once <= 1 stands |
| 10 | $092 Crusher | 36 / 2095 | `FC 12 00 00 \| FE \| FC 13 01 01 \| FC 05 00 00 \| F0 EB FE FE` (`:2556-2567`): 1/3 Lifeshaver | damage (earth, power 84) | guarded; hit while alive <= 1 | **no** | **$11C** (SoulDancer x2, + Crusher x2); **$11D** (Vindr x2, Wild Cat, + Crusher x2) | Owzer's house, map 207 (WoR Jidoor), group 157 (map 208 holds group 158 but does not roll) | kill the Crushers first |
| 11 | $0B3 Coelecite | 20 / 480 | `FC 13 01 01 \| FC 12 00 00 \| F0 BC FE FE` (`:1459-1471`): 1/3 Magnitude8 | damage (earth, power 100; Float avoids earth) | **death only**: self dead AND alive <= 1 | **only on KB** | **$09B** (Lich, Apparite); also $09A x3 | Cave to the Sealed Gate: $09B group 92 (map 382), $09A group 95 (map 385) | kill first while both others stand (no fire).  In $09A the 2nd and 3rd deaths fire.  Or Float the party |
| 12 | $0DB Muus | 28 / 900 | `FC 12 00 00 \| FE \| FC 13 01 01 \| FC 01 02 02 \| F0 EE FE FE \| FE \| FC 01 02 02 \| F0 9D FE FE` (`:2118-2133`): 1/3 Battle; the ungated block is 1/3 Pep Up | damage (a plain Battle hit); the ungated block is Pep Up (heal/cleanse) | guarded; **Magic** on it while alive <= 1 | **no** | **$0F1** (Deep Eye x2, + Muus x2); also $0F2 x3, $0F3 solo | WoR Kohlingen continent: group 47 ($0F1, t3), 46 ($0F2, forest), 45 ($0F3, grass); sectors (0..2, 0..2) | **ignore** (harmless-grade); don't cast at a lone Muus |
| 13 | $0E8 Bug | 16 / 310 | `FC 13 01 01 \| FC 01 00 00 \| F0 EF FE FE` (`:1091-1098`): 1/3 Special = StoneSpine | **status: Petrify** (special $46) | **unguarded**; **Fight** on it while alive <= 1 | yes, if the killing blow is Fight | **$08C** (FossilFang, Bug x3); also $08D x3, $08E x6 | WoB deserts (terrain t2): group 20 (sectors (7,1), (3..4,4), (2..5,5), (1..6,6), (1..5,7)) and group 26 ((2,0),(3,0),(7,2),(4,3),(5,3),(7,3),(7,4)) | kill the last Bug(s) with anything but Fight (magic, Tools...).  Bugs that die while 2+ others stand are safe to Fight |
| 14 | $0F3 Mag Roader | 32 / 1380 | `FC 13 01 01 \| F0 B3 FE FE \| FE \| F0 EE EE FE \| FD \| F0 EE EE EF \| FF` (no `end_retal` after `:2530-2534`; runs on into Wild Cat's main script, `:2536-2551`, marked "*** bug ***") | damage: 1/3 Fire Ball (fire, power 50) when <= 1; otherwise 2/3 Battle | **unguarded, no `if_hit`/`if_cmd`**: *every* counter trigger.  Alive <= 1: Fire Ball block; else falls to `F0 EE EE FE` (2/3 Battle), ended by the FD | **yes**: Fire Ball when <= 1 left after its death, Battle otherwise | **$118** (Mag Roader $0E7 x2); **$119** ($0E7, + $0F3 x2) | map 36, a cave off WoR Narshe (map 32 (15,56)/(22,44) → 36; "WoR map 32" per `docs/design/narshe-school.md:23`), group 190 | not avoidable by order: it counters every hit.  Kill it while >= 2 others stand to get Battle, not Fire Ball |
| 15 | $120 Larry | 47 / 10000 | `FC 13 01 02 \| FC 05 00 00 \| F1 11 \| F0 FE 06 FE \| F8 02 81 \| FE \| FC 05 00 00 \| F1 11 \| F0 FE 06 FE` (`:5641-5650`) | damage (Ice 2, power 62).  The <= 2 gate adds nothing new: it is the same 1/3 Ice 2 plus `add_battle_var 2,1` (F8 02 81), which feeds "Larry ran away" (main `:5618-5628`, hide when var 2 > 4) | unguarded; any damaging hit (1/3 Ice 2 at target byte $11, decoded as `GHOST_2`; meaning **not verified**); at <= 2 alive it also counts toward the flee | yes | **$1CC** (Curley, Moe); $204 (same three) | $1CC: event battle group 90, `event_main.asm:58739` (`_cb8bd1`, trigger map 317 (46,55), "We're the 3 Dream Stooges!": Cyan's dream, WoR).  $204: no source found: **unmet** | not a last-stand problem: a boss mechanic.  Larry absorbs ice, is weak to fire |
| 16 | $158 Long Arm | 73 / 33000 | `FC 13 01 00 \| F1 47 \| F0 FE E3 E3 \| F0 E3 FE E3 \| F0 E3 E3 FE` (`:7389-7394`): up to three Shock Waves (2/3 each) | damage (Shock Wave power 25) | unguarded; **N=0**: only when no monster is left alive at counter time | yes, if it is the last to die (or dies in the action that kills the last) | **$1D7** (Short Arm, Face) | final battle tier 1, event group 101, `event_main.asm:1961` | kill Long Arm and Face before Short Arm |
| 17 | $159 Face | 74 / 30000 | `FC 13 01 00 \| FC 12 00 00 \| F1 47 \| 15` (`:7430-7434`): Quake, always | damage (earth, power 111; Float avoids) | **death only**, N=0: dies last | only on KB, and only as last | **$1D7** | same | kill Face before Short Arm; or Float |

Effect classes in short: **removal** (Sneeze): Baskervor, Chitonid.
**Status**: Petrify (HermitCrab, GloomShell, Bug), Dark (Ing), Sleep
(Mind Candy), Death/Muddle (Apokryphos).  **Damage**: Behemoth, TumbleWeed,
Crusher, Coelecite, Muus, Mag Roader, Larry, Long Arm, Face.  None is harmless
outright; Mind Candy and Muus are nearly so, since their gate is a command a
fighter rarely uses on them.

## Fixtures to play each formation from

From `tools/tests/savestate_graph.py` plus the logs (`met*.txt`).

| formation(s) | fixture before the place | generator that walks it | measured in logs |
|---|---|---|---|
| $060 / $062 Mind Candy | `figaro_submerged` (`:304`); `zozo_done` (`:331`); the `terra-returned-v1` cut before `narshe_mission` (`:468`) | gen_zozo2_arrival, gen_opera1_entry, gen_narshe_mission | $060: zozo_arrival x18, opera_entry x3, narshe_mission x5-7; $062: never |
| $08C Bug | **none known**: WoB desert sectors; no log met $08C/$08D/$08E | (not determined) | never |
| $097 Ing, $09B Coelecite | `narshe_mission` (`:468`, before gen_gate_cave_save); `gate_cave_save` (`:483`, before gen_vector_crash) | gen_gate_cave_save, gen_vector_crash | $097: gate_cave_save x2-3, vector_crash x1; $09B: gate_cave_save x1; $098: gate_cave_save x2, vector_crash x1-3 |
| $0A2 Baskervor | `crescent_landing` (`:540`, before gen_thamasa_arrive); `fire_out` (`:580`, before gen_esper_mtn) | gen_thamasa_arrive, gen_esper_mtn | $0A2: thamasa_night x1, esper_mtn_save x1 (main checkout), suite_field_care_emptybag x5-10 |
| $0B2 / $0B7 Apokryphos, $0BA Behemoth | `fc_landing` (`:657`, before gen_fc_alcove); `fc_alcove` (`:667`, before gen_fc_escape) | gen_fc_alcove, gen_fc_escape | $0B7: fc_alcove x2, wor_landing x1; $0BA: fc_alcove x4; $0B6 and $0BB also met; $0B2: never |
| $0C9 / $0CC Chitonid | `wor_start` (`:708`, before gen_wor_tzen_door); possibly `wor_sabin` (before gen_wor_nikeah: its start (131,179) is sector (4,5), a group-34 sector, but no nikeah log met it) | gen_wor_tzen_door | $0CC: wor_tzen_door x3-4; $0C9: never |
| $0CF HermitCrab | `wor_tzen_door` (`:724`, before gen_wor_sabin) | gen_wor_sabin (the house) | wor_sabin x2 |
| $0F1 Muus | `wor_figaro_sweep` / `wor_kohlingen` / `wor_tomb` (Kohlingen-continent legs, `docs/design/route-wor-falcon.md` §3.2) | gen_wor_kohlingen / gen_wor_tomb / gen_wor_falcon (which crosses group-47 tiles: **not determined**) | never |
| $118 / $119 Mag Roader | **none**: no generator walks map 36 | — | never |
| $11C / $11D Crusher | **none**: no generator enters Owzer's house (map 207) | — | never |
| $14D GloomShell, $147 TumbleWeed | **none**: no generator reaches those WoR sectors | — | never |
| $1CC Larry | **none** (Cyan's dream is not on the route) | — | never |
| $1D7 Long Arm / Face | **none** (final battle) | — | never |
| $082 $084 $085 $0D0 $204 | no draw source found at all | — | never |

## Not determined

- **Killing-blow fire, measured:** I found no log line that isolates a counter
  thrown by a monster on its own killing blow.  The claim rests on engine
  rules 1-4: the `$3a56` branch, the queue drained before CheckBattleEnd, and
  the vanilla death-throe scripts of Coelecite and Face, which only work if a
  dead monster's counter runs.  The project's own reports of it are
  `docs/design/route-wor-sabin.md:91-93` and the issue text.  The lab's
  Chitonid evidence (`tools/tests/lib/ot6.lua:5514-5519`) has a sneeze with the
  Chitonid taken while only one other stood, and it does not show which hit
  fired it.
- Whether `$327c` (if_hit) is cleared between actions, so whether a 0-damage
  action counts as a hit (rule 5).
- Whether Sleep/Stop/Muddle/Berserk still gate the counter of a monster that
  has just died.  `ExecAIRetal` re-reads them on the died path only when
  `$33fe` was clear (`:12824-12826`); whether death clears them first was not
  traced.
- Larry's counter target byte `$11` (disassembly name `GHOST_2`).
- Which terrain tiles the route's WoB legs cross for the Bug's desert groups;
  which Kohlingen-continent leg crosses group 47.
- Formations $082, $084, $085 (Chitonid), $0D0 (HermitCrab + Scorpion) and
  $204 (Larry) have no source in the random groups, field maps, world sectors,
  event battle groups, treasure or `change_battle` tables I searched.  I did
  not check the Veldt (`GetVeldtBattle`, `ff6/src/field/battle.asm:267`).

## Played

**Floating Continent, map 394 (Apokryphos $0B2/$0B3/$0B6/$0B7, Behemoth
$0BA/$0BB).**  `gen_fc_alcove` from `fc-landing-v1`, retries off, seed
shifts 0-55 in steps of 5, played twice: the driver as shipped (only the
Sneeze bodies first) and with `lastStand = true` on every walk fight, which
takes the Apokryphos and the Behemoth first (`[last stand] slot 2 ($00C)
throws $94/$95/$96 (N=1) ... taken first`, 16 fights; `slot 0 ($020)`, 16).
`build/attempts/wt/v026-route/laststand/play_fc/summary.txt`:

| formation | shipped: fights, deaths, mean ticks | every body first: fights, deaths, mean ticks |
|---|---|---|
| $0B7 Apokryphos + Brainpan x2 + Misfit | 25, 0, 4038 | 16, 0, 4151 |
| $0BA Behemoth + Misfit x2 | 16, 1, 3708 | 16, 0, 4127 |
| $0B2 / $0B3 / $0B6 / $0BB | 4/3/-/4, 0 | 2/4/2/4, 0 |

Every fight won in both arms and all 24 runs passed.  At this party's
level the bodies die in a few turns, and the order bought nothing measurable
here (one death in 16 $0BA fights against none) while the Behemoth taken
first cost about 11% more ticks.  The class is not a danger on the FC
route; the rows where it is (the Sneeze on the WoR plains and the WoB's
Crescent island) are already measured in `Driver:readLastStand`'s note.
Not played: the bodies no generator reaches (Bug, Mag Roader, Crusher,
GloomShell, TumbleWeed, Larry, the final battle's arms) and the
route-reachable ones not yet re-measured (HermitCrab in Tzen's house, Ing
and Coelecite in the Sealed Gate cave, Mind Candy on the Jidoor side, Muus
on the Kohlingen continent).
