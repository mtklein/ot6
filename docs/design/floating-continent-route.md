# IAF / Floating Continent route

This is the route from the World of Balance stop line — WoB world (249,128),
party TERRA·LOCKE·STRAGO·RELM, `$009D=1`, beside the repaired Blackjack —
through the Imperial Air Force gauntlet and the Floating Continent assault,
to where control returns in the World of Ruin.

Claims cite a `file:line` or are labelled **UNVERIFIED** (needs a live
read) or **verify-on-arrival** (an offline data decode, true unless the
data moved). Line numbers are into `ff6/src/event/event_main.asm` unless a
path is given. Formation contents are decoded offline from
`event_battle_group.dat` (4 bytes/group = two formation words) →
`battle_monsters.dat` (15-byte records: `+1` present mask, `+2..+7` low id,
`+14` per-slot bit-8); the decode is validated against known event battles
(`battle 124`→form 388 `$173` KEFKA_VS_LEO per `gen_massacre`). Boss
shield/weakness data is not re-derived here — it lives in `bosses-wob.md`
§19–22 and is cross-referenced in §7.

---

## 0. Findings

1. **Liftoff is immediate; the fly-refusal ladder is off-path.** At the stop
   line the Blackjack is a free WoB world vehicle: `load_map 0, {249,128}` for
   the party on foot + `airship_pos {249,127}` for the vehicle, under
   `set_script_mode WORLD` (`:78007-78009`); `$009D=1` was set at `:77992`.
   Boarding is the ordinary "walk onto the airship tile" world action and runs
   no event script. The Setzer talk-to-refuse ladder `_cb2007` (`:43089-43092`)
   is a **map-7 Blackjack-interior NPC** (`event/npc_prop.asm:294-300`), and it
   short-circuits at `$005D=1` (set once at `:43448`, never cleared) into the
   pre-repair "go scout around" leaves (dlg $051E/$051F/$0520). It never gates
   stop-line liftoff: **liftoff works immediately.**

2. **The IAF is armed by *landing* the airship, not by flying to a spot.**
   There is no world-coordinate trigger. `AirshipGround` (`:172-181`, dispatched
   as `VehicleEvent_02` from `ff6/src/world/move.asm:1201` when the land button
   `$08` bit 7 is pressed over a landable tile) has **no coordinate gate**: with
   `$009D=1 && $009E=0` the *first landing anywhere* diverts to `_ca5ad4`
   (`:13653`) → `load_map 3,{8,9}` → the map-3 arrival trigger `_ca5ade`
   (`event/event_trigger.asm:52-53`, `:13659`), the FC-discovery cutscene. That
   ends (`:14041-14062`) by dropping the party onto the Blackjack **deck**
   (map 6, world (249,126)), setting `$009E=1` (`:14057`) and running the FC-var
   init `_cce4c2` (`:112972`).

3. **"Find the Floating Continent" forces a party of three.** The deck menu
   `_caf579` (reached once the discovery sets `$009E=1`, via `_caf548` `:36130`;
   `_caf579` itself is `:36152-36158`) offers dlg $0527
   "Find the Floating Continent / Lift-off / Not just yet". Option 0 → `_ca5817`
   (`:13209`), which requires `$01A2=1` = **exactly three** party members
   (`_cac5c1` recomputes it, `:30515`/`:30667`); a four-party hits dlg $084E
   "Only 3 allowed…" and returns. The routed party is four
   (TERRA·LOCKE·STRAGO·RELM), so the route **must bench one at the deck** before
   the IAF. With three aboard, `_ca583a` (`:13227`) plays the ambush → dlg $084F
   "The Imperial Airforce (IAF)!" → the first `battle 126` (`:13406`).

4. **The IAF gauntlet is a scripted auto-chain** (§3): six waves of
   `battle 126` (formations **175/176**, Sky Armor + Spit Fire) on field timers,
   then `battle 107` (Ultros④, form 477) once `$01F0` is set by the "something
   curious approaches" teaser, then `battle 89` (AirForce, form 459), then
   `load_map 394` — no free airship nav inside it.

5. **The Floating Continent is one map, not a chain.** Map **394**
   "THE FLOATING LAND" is the whole assault; the descent is `mod_bg_tiles`
   staircase reveals *within* 394, not map transitions (394 has zero
   short/long entrances). The only sub-map is the encounter-free save alcove
   **358**. AtmaWeapon is fought in place at 394 (60,15) (`battle 80`, form 450);
   Shadow rejoins by talking to an NPC at 394 (10,16). Two **vanilla** save
   points already exist (394 (7,12), 358 (8,10)) — see §4.

6. **The escape waits for Shadow with a five-second margin.**
   After the statues rise, a 6:00 master clock (`start_timer 0, 21600`,
   `:34144`) runs to a GameOver on expiry (`:34155`/`:34174`). Shadow arrives at
   **0:05 remaining** (`start_timer 2, 21300`, `:34145`; handler `_ca57b3`
   `:13137`) *only if the party is standing at the jump ledge*
   (`$01FD && $01FE`), setting the saved-flag `$037D=1` (`:13172`). The humane
   line — "Wait!!" at the ledge (dlg $0872/$0873) — spends ~355 s of the clock
   for a 5-second safety window; "Jump!!" early runs `_ca48c1` (`:11325`),
   clears `$02F3` (`:11333`) and forfeits `$037D`, losing Shadow for the whole
   WoR (checked at `:12033`/`:12172`). See §5.

7. **The arc ends as solo Celes on the Solitary Island.** The exit chain
   `_ca48d6` (`:11337`, maps 10 → 376 → 390) carries the airship off the
   collapsing continent into `cutscene RUIN` (`$ad`, `:12210`) — the WoB→WoR
   cut. `cutscene FLOATING_CONT` (`:13964`) is the *approach/statue* cutscene,
   not the collapse. The WoR opening lands on the Solitary Island (map 397),
   Celes solo (`char_party CELES,1`, others removed, `:12224-12227`), WoR flag
   `$00A4=1` (`:12423`); control returns after Cid's fish request at the
   `pass_off`/`return` (`:12397`/`:12449`). Shadow's FC fate is already fixed by
   then. This is the arc's stop line and the end of the World of Balance. See §6.

8. **Engineering headroom** (§8): ~16 free trigger slots exist, and the FC's
   two save points are **vanilla**, costing zero slots. The telegraph pass
   still must be data-authored (no per-frame cycle headroom).

---

## 1. The stop line and liftoff

Entry state: control on the WoB world map at **(249,128)**, party
**TERRA·LOCKE·STRAGO·RELM**, roster re-normalized and available except Shadow
(`$02F3=0`), `$009D=1`. The Blackjack is parked at (249,127) as a free vehicle
(`airship_pos {249,127}`, `:78009`).

Liftoff is the ordinary world board action (walk onto the airship tile). No
event runs; the `_cb2007` refusal ladder (`:43089`) belongs to the map-7
interior Setzer NPC and is dead post-repair (`$005D=1` since `:43448`). Switch
state at the line: `$009D=1`, `$009E=0` (set only later at `:14057`), `$005D=1`,
`$007D=1` (inferred — the Thamasa shops/inn gate on it at `:69474`+/`:69493`, so
it holds on arrival; exact byte **UNVERIFIED**, and moot for liftoff).

---

## 1a. Prep at Thamasa before boarding (measured, probe_fc_prep.lua)

The gauntlet is a heal race (round costs of 300–600 per character against
~900–1100 HP at L23–26), so the combat heal must be a Potion and it must be
one press away.  From the stop line, RIGHT enters post-massacre Thamasa —
**map 340**, not the pre-massacre 343: the same tiles under another map
index — at (23,46).  The item shop door is still (26,37) → 347 (36,44), the
keeper at (36,39) (stage (36,41), face up); rows: Tonic 0, Potion 1, Fenix
Down 6.  The prep buys POTION to 65 (the L29 band plus the FC's measured
spend, docs/design/level-curve.md's shop table, #176; it was 40 until the
segment runner made the RNG shift survivable, #179), FENIX DOWN to 25 (a row
already at or over its target is skipped -- the seed carries 28), TONIC to
99 (9,050 gil of a 203k purse: `gil=203205` at the counter, `gil=194155`
after), then `H.bagArrange` puts Potion, Fenix Down,
Tonic, Antidote, Remedy at bag slots 0–4 through the field Item menu's real
pick-up-and-swap (the seed shipped the Potion at row 43: a 43-row list walk
per battle heal, and two of three died while it walked — attempts 10–11).
Return door 347 (36,45) → 340 (26,39); DOWN off (23,46) lands on the world
at exactly (249,128) with the Blackjack on (249,127), so the boarding walk
below starts unchanged.  Whole prep ≈ 4,100 frames.

## 2. Boarding, landing, and the deck menu — the real entry

The IAF is not reached by flying to a location. The sequence is:

| step | action | mechanism |
|---|---|---|
| 1 | Board at (249,127) | world vehicle board; free flight, no refusal (§1) |
| 2 | **Land on any landable tile** | `AirshipGround` `:172-181` (`VehicleEvent_02`, `world/move.asm:1201`); `$009D=1 && $009E=0` → `_ca5ad4` `:13653`, no coordinate gate |
| 3 | Ride the FC-discovery cutscene | `load_map 3,{8,9}` → trigger `_ca5ade` `:13659` (`event_trigger.asm:52-53`); statue exposition; `cutscene FLOATING_CONT` `:13964`; ends dropping party on the deck (map 6, (249,126)), **`$009E=1`** `:14057`, FC-var init `_cce4c2` `:112972` |
| 4 | Deck menu → **trim to 3** → "Find the Floating Continent" | `_caf579` `:36130-36158` dlg $0527; option 0 → `_ca5817` `:13209` needs `$01A2=1` (exactly 3, `_cac5c1` `:30515`/`:30667`); else dlg $084E |
| 5 | IAF ambush | `_ca583a` `:13227` → dlg $084F → `battle 126` `:13406` |

The two gating switches to watch live: **`$009E`** (0→1 = discovery ran) and
**`$01A2`** (must be 1 = three aboard). The forced three-party is a **route
decision**: one of TERRA/LOCKE/STRAGO/RELM is benched for the entire IAF+FC.
Who to keep is a kit question for the FC break fights (AtmaWeapon needs two of
fire/ice/bolt/slash/pierce; §7).

---

## 3. The IAF gauntlet

A scripted auto-chain on field timers (`:13399-13557`); the airship-fly plane
NPCs (`_ca5892`..`_ca596a`) are set dressing. Every battle routes through
`call _ca5ea9`, the GameOver read-canary handler (a loss is a real Game Over —
see `gen_massacre.lua` on the same handler).

| # | line | event | formation(s) | contents (verify-on-arrival) |
|---|---|---|---|---|
| 1 | `:13406` | `battle 126, AIRSHIP_CENTER` | 175 / 176 | Sky Armor `$043` ×2 + Spit Fire `$0e3` (175); Sky Armor + Spit Fire (176) |
| — | `:13446` | `switch $00A0=1`; `start_timer 0,256,_ca598f` | | |
| 2 | `:13460` | `battle 126` | 175/176 | " |
| 3 | `:13467` | `battle 126` (gap 384) | 175/176 | " |
| 4 | `:13474` | `battle 126` (gap 320) | 175/176 | " |
| — | `:13478` | dlg $0850 "Something…curious…approaches!!"; NPC_9 descent sets **`$01F0=1`** `:13520`; `start_timer 0,416` | | the Ultros teaser |
| 5 | `:13526` | `battle 126` | 175/176 | " |
| 6 | `:13533` | `battle 126` (gap 512) | 175/176 | " |
| 7 | `:13540` | `battle 107, AIRSHIP_WOB` (gated `if $01F0=0 EventReturn`, `:13538`) | 477 | **Ultros④** `$168` (Chupon `$12f` script-added; §7) |
| 8 | `:13557` | `battle 89, CLOUDS` (after `switch $01CC=0`, `call _cacfbd`) | 459 | **AirForce** `$113` + Laser Gun `$145` + MissileBay `$147` (Speck `$146` script-spawned; §7) |
| → | `:13560` | `load_map 394,{4,8},DOWN` — **FC entry**; dlg $0851 "…the Statues are just ahead" `:13585` | | |

**Break data (decoded from `Ot6ShieldTbl` / `monster_prop` / `Ot6ElemAddTbl`):**

| enemy | L | shields | weak | class |
|---|---|---|---|---|
| Sky Armor `$043` | 24 | 5 | **bolt**\|wind | $02 |
| Spit Fire `$0e3` | 25 | 5 | **bolt**\|wind | $01 |
| Ultros④ `$168` | 26 | 7 | fire\|**bolt**\|poison (absorbs water) | $03 |
| Chupon `$12f` | 26 | 4 | ice\|water (absorbs fire) | $04 |
| AirForce `$113` | 25 | 8 | **bolt**\|water | $02 |

**Bolt is the IAF key.** Sky Armor, Spit Fire, Ultros④, and AirForce are *all*
bolt-weak — and so is AtmaWeapon (§7). A bolt-leaning party breaks every wave
fast, which matters because the waves auto-chain with no field care-stop
between most waves.

**Tuning.** Sky Armor `$043` and Spit Fire `$0e3` carry authored
`Ot6ShieldTbl` rows of **2 pips each** (the formula fallback would give the
repeating wave trash boss-scale 5-gauges; the real gauges stay on Ultros 7 /
Chupon 4 / AirForce 8). Two care stops — `call _cacfbd` (the tent heal:
revive + full HP/MP, the same sub the chain already ran before AirForce) —
run after waves 3 and 6, so each three-wave stretch is tight-but-winnable
(~300 HP bleed/wave against a ~1000 pool) rather than an eight-fight
attrition ramp. The field menu also opens between waves (the wave timers are
FIELD_ONLY and pause in menus), so ordinary menu healing works too. Ultros④
is armed by *walking* to the deck's right edge (map 10 triggers (22,5-7) →
`_ca5a16`, gated on the teaser's `$01F0`); after Ultros the script
auto-chains into AirForce with its own tent call — no field window there.

A measured run at L24/24/25 with a bolt-leaning kit clears all six
`battle 126` waves at/near full HP each time, wins Ultros④+Chupon in ~12k
frames and AirForce in two rounds, landing on map 394 with the party at
739/787/544 HP going in.

`tools/tests/probe_iaf.lua` drives the whole entry headless (board →
discovery → deck → "Find the FC" → the party-formation menu → the ambush)
and reads `battle 126` in the emulator as **Sky Armor `$043` + Spit Fire
`$0e3`**, matching formation 175's offline decode.

The `AIRSHIP_CENTER`/`AIRSHIP_WOB`/`CLOUDS` arguments are battle **backgrounds**
(`event_cmd.inc:234`, `battle_bg.inc`), not part of the formation id.

---

### 3a. Dressing the bench pick (measured, gen_fc_landing.lua)

The deck party select can pull a benched character (EDGAR) into the three,
and he arrives with every slot empty — the field Equip screen never showed
him while benched, so the Thamasa prep cannot dress him.  On the story deck
right after the select the main menu is **disabled** (X did nothing for
1200 frames with no dialog up; the party stands on the helm tile), so the
first place he can be dressed is the field gap after wave 1, where the menu
opens (the wave timers are FIELD_ONLY: they run while the menu is closed and
pause while it is open).  `H.equipKit` does one Equip session and one Relic
session per character there — round trips are what the gap cannot afford —
and the wearable rungs are read from his own list ($25 is Shadow-only, mask
$8008, and never appears).  A Relic-screen back-out with the Genji Glove
involved runs the game's own Optimum on exit (element-blind best-attack
gear).  The first cut of the seed fought all 13 battles with EDGAR naked and
still won; the re-cut dresses him after wave 1.

## 4. The Floating Continent (map 394 + save alcove 358)

**One map.** 394 "THE FLOATING LAND" (`map_prop.dat` rec 394 title index 59) is
the whole assault. It has no short/long entrances
(`include/field/short_entrance.inc`, `long_entrance.inc`); the descent is
`mod_bg_tiles` staircase-reveal triggers within 394 (e.g. `_cadac0` (70,23),
`_cada55` (89,25), `_cad916` (90,43); `:32739`/`:32699`/`:32512`).

**Edges** (event-driven):
- Entry: IAF → `load_map 394,{4,8},DOWN` (`:13560`).
- 394 (90,43) → `load_map 358,{8,7}`, `$01B5=1` (`event_trigger.asm:1962`, `:32517`).
- 358 (8,8) → `load_map 394,{90,42}` (`event_trigger.asm:1755`, `:32546`).
- 394 (70,29) → `_ca5a6c` (`event_trigger.asm:1961`) "The airship's below! Do you wish to return?" — **dlg $0857 rows: 0 = (No), 1 = (Yes)**, and the event gates itself on `$01B5` (`if_switch $01B5=1, EventReturn` then `switch $01B5=1`), so the prompt fires ONCE ever; a gen must answer Yes the first time (the first descent cut answered row 0 and stayed on 394) → `load_map 6,{16,6}` (`:13612`); the "Yes" branch `_ca5a8a` (`:13627`) sets **`$035E=1`** (`:13633`) *while AtmaWeapon is alive* (`if $035F=0`, `:13632`) — this is what poses Shadow's NPC.

**Encounters.** Only 394 rolls (`map_prop +5 = $80`; `SubBattleGroup[394]=112`;
`field/battle.asm:332-333`,`:394-411`). Group 112's four words are `$80B1/$80B4/
$80B7/$80B9` = base forms 177/180/183/185 **each +Rand(0..3)** (the `$8000`
flag, `battle_main.asm:8215-8224`) → effective pool **177–188**. Contents:
Behemoth `$020`, Apokryphos `$00c`, Misfit `$0a4`, Ninja `$003`, Wirey Drgn
`$0d8`, Brainpan `$04a`, Dragon `$083` — the vanilla FC pool. Map 358 is
encounter-free (`+5 = $00`). (Confirmed with `tools/audit_encounters.py 394`,
which the FC's `+Rand` flag first exercised — the fix is `e855c36`.) **Several of
these formations permit a pincer** (e.g. the Apokryphos/Misfit, Ninja, and
Brainpan groups), so a walk across 394 needs a fight budget or a `"tactical"`
playBattles mode, not a blind `"flee"` (HANDOFF, the flee bullet).

**Rows.** The (67,39) walk's Behemoth one-shot a front-row TERRA at 792 HP
(two Fenix Downs in one random, run.0FsoIlAX r6). TERRA (Magic) and EDGAR
(Tools) never swing, so the back row costs them nothing and halves the
physical damage they take; the deck kit sets TERRA/EDGAR back, LOCKE front.
**SHADOW is not in that set** — he joins at the landing, after
`gen_fc_alcove`'s `setRows` has already run, with every equipment slot
empty and in the front row, and the shipped run dresses him only at the
save alcove once the crossing is over. Measured over 12 seeds that costs
the segment 24 deaths and 20 Fenix Downs against 7 and 7 for a dressed,
back-row SHADOW: [fc-alcove.md](fc-alcove.md) (#221).

**Shadow rejoin — MEASURED (probe_fc_shadow.lua on the fc-landing-v1 seed).**
At the landing, before any return trip, `$035E=1`, `$035F=1`, the object map
marks (10,16) occupied, and a talk from (10,15) facing DOWN makes Shadow join
(`$02F3=1`, party of four). The earlier reading — that `$035E` is set only by
the (70,29) return's Yes branch (`:13635`, gated on `$035F=1`) so Shadow
appears only after returning — was wrong in effect: the switch is already on
when the party lands (its origin is not an explicit `switch $035E=1` in
`event_main.asm`, which has only the `:13635` site; a default-on NPC switch
fits). The talk: NPC at 394 (10,16), event `_cad9a7` (`npc_prop.asm:17437-
17443`; script `:32586`): `norm_lvl SHADOW` `:32616`, `char_party SHADOW,1`
`:32625`, `$02F3=1` `:32627`, clears the NPC `$035E=0` `:32633`, met flag
`$002A=1` `:32634`. Its walkable neighbours are (10,15) and (9,16) only —
(10,17) and (11,16) are F7 walls (probe_fc_bfs.lua's map dump). So the
descent is: talk at the landing, then the crossing; (70,29) is avoided
outright, because with Shadow in, its Yes branch is his scripted removal.

**AtmaWeapon.** NPC at 394 (60,15), switch `$035F`, event `_cada30` →
`battle 80` (`:32681`) = **formation 450**, monster 279 `$0117` "AtmaWeapon".
Shadow is forced (rejoined just before); no pre-battle dialog (AtmaWeapon's
speech is battle-side, `ai_script.asm:5169`). Post-win: `$035F=0` `:32686`,
Shadow leaves in `_cad9fc` (`:32642`, dlg $0855, `char_party SHADOW,0` `:32649`,
`$02F3=0` `:32677`). The AtmaWeapon NPC is at map 394 **(60,15)**
(`ff6/src/event/npc_prop.asm:17346-17347`); the (60,11) pre-fight trigger
`_cadd1e` (`event_trigger.asm:1959`) plays CATASTROPHE and arranges the party.

**Save points — both vanilla, zero budget cost.**
- 394 (7,12): `make_event_trigger {7,12}, SavePoint` (`event_trigger.asm:1960`)
  + sparkle NPC (`npc_prop.asm:17491-17496`, switch `$0632`). Beside the (4,8)
  landing.
- 358 (8,10): `make_event_trigger {8,10}, SavePoint` (`event_trigger.asm:1753`)
  + sparkle NPC (`npc_prop.asm:16188-16196`, `$0632`). The encounter-free alcove.

No new save-point authoring is needed here; see §8.

---

**The crossing (map 394 to the save alcove 358).** The reveals do NOT
persist across a map load (measured, probe_fc_exit.lua on the fc-alcove-v1
seed: (89,25) reads F7 after the alcove exit until (82,30) is stepped again,
whose event takes control for a moment and changes the tiles) — every leg
re-steps its reveals hop by hop. The stair-reveal
triggers chain and the scripted chutes ride two-way: (40,6)↔(32,16) and
the (67,39)-walk pair are twins, so riding one down already visits its
return twin. A validated crossing: (4,8) → (19,12) (25,19) (40,12)
(40,6)-chute (36,28) (67,39)-walk (40,24) (63,33) (59,39) (52,24)
(82,30) (90,43) → 358.

Shadow's rejoin sits ahead of the (70,29) "return?" choice: choosing to
return with Shadow already talked in at (10,16) but not yet rejoined
triggers the scripted Shadow **removal** (`_cad9fc`), and the (89,25)
chute reaches that removal branch — so a route that needs Shadow at the
save alcove must avoid (70,29) after the talk-in. Shadow's vanilla 1/16
post-battle leave roll is a NO-OP in OT6 everywhere (`Ot6ShadowLeaves`;
owner's call 2026-09-01: Shadow stays for the whole game, only scripted
departures remain), so no won battle here or on the escape map can clear
`$02F3` and forfeit the humane escape. (Until 2026-09-01 that handler was
mis-banked and every passing roll halted the CPU -- see battle_main.asm's
Ot6ShadowLeaves comment.)

**Pool elements (decoded at the correct offsets — monster_prop +25 weak,
+23 absorb, per `tools/check_boss_rows.py`; a first pass read the status
bytes at +20/+22 and is retracted).** Dragon ($083, 7000 HP): weak **bolt**.
Behemoth ($020, 5800 HP): weak ice. Ninja ($003): weak bolt+holy.
Apokryphos weak bolt/holy/water, Brainpan weak fire/bolt/holy, Misfit weak
fire/holy, WireyDrgn none. **Nothing in the pool absorbs bolt**, and bolt is a
weakness for four of the seven species — Bolt is a good nuke here, and TERRA
carries Ramuh (bolt). The descent's difficulty is the Dragon's 7000 HP and
850 MP at the party's level, not element hostility; see the descent lab note.

The FC randoms carry authored `Ot6ShieldTbl` rows: Behemoth/Dragon 3
pips, Apokryphos/Misfit/Ninja/WireyDrgn/Brainpan 2 pips. Four of the
seven species are vanilla no-run (`monster_prop` +19 bit 2: Apokryphos,
Misfit, WireyDrgn, Brainpan), so 7 of the 12 formations cannot be fled.
Ninja pairs throw ~300/char AoE per round and can nuke a full-HP party
by round 3; Behemoth (6051 HP) wins by attrition if entered wounded. No
WoB shop sells Diamond-tier gear (the Diamond shops are `$00A4=1` WoR
variants); vanilla survives this pool around L26-30.

**AtmaWeapon's approach.** The plateau (x56-64, y3-25) is tile-hermetic
— zero walkable neighbors, no chute lands inside it. The only entry is
the reveal at **(63,28)** (`_cad907`, `$01FB`): a 3-tile ladder at
(63,25-27) into the plateau's south-east tip. The chute graph:
(40,24)↔(63,31), (42,17)↔(67,39), (48,22)↔(77,31), (70,23)↔(89,25) are
two-way tunnels; (36,28)/(52,24)/(59,39)/(63,28)/(82,30) are pure
reveals. The route: descent prefix → the (40,24) tunnel (lands (63,31))
→ step (63,28) → climb → (60,12) → (60,11) CATASTROPHE → battle 80.

AtmaWeapon (form 450) has 23349 HP and an 11-pip slash|pierce shield
that re-shields mid-fight. Post-win, `_cada30` runs
`if_case CHAR::SHADOW → _cad9fc`, dropping the party to 3; the escape
sequence re-handles Shadow from there.

## 5. The escape

**Trigger.** After Kefka moves the statues (cutscene `:33900-34126`), the party
lands via `load_map 393,{67,16}` (`:34127`); Shadow's dlg $0870
"Get outta here on the double!" (`:34138`); `remove_equip SHADOW` `:34141`;
`play_song METAMORPHOSIS` `:34142`; **`switch $02BC=1`** (escape active) `:34143`;
then two timers.

**Nerapa — the escape's doorman.** The Nerapa NPC is on the escape-landing map
393 at **(108,15)**, switch `$0361`, event `_cada48`
(`ff6/src/event/npc_prop.asm:17324-17327`) → `battle 81` (`:32693`) =
**formation 451**, monster 280 `$0118` "Nerapa"; opens with Condemned on the
whole party, run under the escape clock (§7, `bosses-wob.md` §22).

**The clocks.**

| stage | value / cite |
|---|---|
| Escape active | `switch $02BC=1` `:34143` |
| Master clock | `start_timer 0, 21600, _cae414` `:34144` = **6:00** (21600 f ÷ 60) |
| Expiry | `_cae414` `:34155` → `stop_timer`, shake, fade, `call GameOver` `:34174` |
| Shadow arrival | `start_timer 2, 21300, _ca57b3` `:34145` = **5:55 = 0:05 remaining** |
| Arrival handler | `_ca57b3` `:13137`, gated `if_any $01FE=0 / $01FD=0 → EventReturn` (must be at the ledge); `stop_timer 0/2` `:13142`; dlg $0874 "SHADOW!!" `:13169`; **`switch $037D=1`** `:13172` |
| Wait-or-jump fork | ledge NPC `_ca577e` `:13108` dlg $0872 "Jump!! / Wait!!"; later `_ca57a8` `:13131` dlg $0873 |
| Jump early = lose Shadow | "Jump" → `_ca48c1` `:11325`, `$02F3=0` `:11333`, skips the `$037D` path |
| Saved flag | `$037D` (read in WoR at `:12033`/`:12172` to spawn Shadow's actor) |
| Exit | both paths → `_ca48d6` `:11337`: `$02BC=0`, `load_map 10` → **376** `:11374` → **390** `:11432` (airship flees) |

**Measured (gen_fc_escape.lua, 2026-09-01).** At the party's first control on
393 the master clock reads 21,569 frames (5:59) with flags $70 — it RUNS in
menus and battles (the `p` bit is clear) — and Shadow's timer 21,269; so the
whole walk, every encounter, Nerapa and the walk to the ledge must fit inside
~5:50 for the party to be waiting there when Shadow's timer fires. Walking to
Nerapa at the default fighting policy met four random encounters at ~3,000
frames each and the clock expired before Nerapa was engaged; the game over is
`_cae414`'s expiry. (An earlier reading of "16,752 left" was the timer's flags
byte, not its count: the record is flags at +0, the frame count at +1.) The
393 walks are **fought** (`playBattles="tactical"`, physical damage only,
no BP bank): the map's one formation sets the can't-run bit, and the
earlier "mustflee" walk never released anything — see §9 for the
measurement and for why a Bolt nuke on the walk stalls the driver. Nerapa
is fought with LOCKE's Bolt nuke and TERRA's Shiva. (A 12-frame decision
cadence was tried and rejected: it makes the magic-list steer oscillate,
and Bolt plans were dropped 32 times in one unrunnable fight — that, not
the walking, burned the clock on that attempt. The 30-frame cadence
steers Bolt cleanly in the Nerapa driver.) Terra swaps Blizzard (ice) for the spare
MithrilBlade before 393: species $0169 in the pool absorbs ice, and the lib's
absorbed-weapon guard fails the run at that encounter otherwise.

Per-screen collapse segments during the run use `start_timer 1, 180/480,
_cae4d4` (`:34268`+), distinct from the master clock.

**The humane line.** Hold at the ledge and choose
"Wait!!" until Shadow arrives at 0:05. The wait costs ~355 s of the 6:00 clock
and is safe by exactly one **300-frame (5-second)** window; leaving early
permanently forfeits Shadow. The route's canon is the wait.

---

## 6. The World of Ruin landing (arc stop line)

The exit chain `_ca48d6` (`:11337`) runs maps 10 → 376 (`load_pal
STATUE_SMOKE`) → 390 (`:11432`), then `cutscene RUIN` (`$ad`, `:12210`) — the
WoB→WoR cut (title card dlg $0877). (`cutscene FLOATING_CONT` `:13964` is the
earlier approach cutscene, not this.)

WoR opening: `load_map 1,{74,22},AIRSHIP` (`:12228`) → Solitary Island interior
398 → 396 → **397 {100,38}** (`:12237-12247`), the Cid/Celes bedside. Party is
**Celes solo** (`create_obj CELES`/`char_party CELES,1`, `char_party TERRA,0`,
`delete_obj TERRA`, `:12224-12227`); roster reset `$02F0..$02FD=0` (`:12431`),
only Celes normalized (`:12427-12430`). WoR flag **`$00A4=1`** (`:12423`).

**Stop line.** After Cid's fish request (dlg $087F, `:12388`) the startup event
hands control (`pass_off SLOT_1`/`NPC_1`, `:12397-12398`) and `return`s
(`:12449`): the player holds **solo Celes on the Solitary Island (map 397)**.
Shadow's FC fate is already decided (`$037D`, §5). This is the end of the World
of Balance and the arc's finish.

**Measured (gen_fc_escape.lua, 2026-09-01).** The opening's dialogs page for
roughly 5,000 frames after the party reaches (100,38) (`$ba=01` with `$d3=00`
between pages, event pc at the WaitDlg script), then control returns with solo
Celes at (99,38), 964 HP, `$00A4=1`, `$037D=1`; the gen emits `wor_landing.mss`
there. (A first attempt was failed by the harness's game-over canary: its
one-byte READ watch on the GameOver script fired three times on a neighbouring
fetch with the title screen never entered; the watch is now gated on the event
interpreter's pc.)

**The clock that starts at the stop line (read from `:12390-12449`).** Right
before the `return` that hands control back, the opening sets `var 7 = 120`
(Cid's health) and starts `timer 0, 64, _ca533f, FIELD_ONLY`, which decrements
var 7 every 64 field frames — about 2:08 of field time until Cid dies unfed,
which is the fork to the cliff scene. The escape gen's terminal (control at the
bedside) therefore leaves a live clock in the seed it cuts; the first WoR gen
must feed him (or accept the fork) before anything else. `gen_wor_start`
feeds him (`docs/design/wor-start.md`: the measured clock, the fish and the
odds).

**Equipment note — Nerapa.** Elsewhere on this route Celes's Fire Rod is
fine (the enemies there absorb ice, not fire), but Nerapa is the
exception: it absorbs fire and is ice-weak, so an Ice Rod belongs on
Celes for this fight only.

---

## 7. Bosses (cross-ref `bosses-wob.md` §19–22)

Shield/weakness/telegraph data is authored and recorded in `bosses-wob.md`; this
survey only pins the formations that reach them.

| fight | event | form | monsters | bosses-wob |
|---|---|---|---|---|
| Ultros④ + Chupon | `battle 107` `:13540` | 477 | Ultros `$168` (Chupon `$12f` script-added) | §19: shields 7/4; Chupon's Sneeze ends by script — don't hold BP |
| AirForce | `battle 89` `:13557` | 459 | AirForce `$113`, Laser Gun `$145`, MissileBay `$147` (Speck `$146` script-spawned) | §20: shields 8/3/3/1; break the bay to cancel Launcher; Speck absorbs spells |
| AtmaWeapon | `battle 80` `:32681` | 450 | AtmaWeapon `$0117` | §21: shields 11, weak fire/ice/bolt+slash/pierce (whole row added); Shadow forced; Flare-Star fuse each rotation; MP-kill preserved |
| Nerapa | `battle 81` `:32693` | 451 | Nerapa `$0118` | §22: shields 5, weak ice/bolt/holy+slash/pierce, **absorbs fire**; Condemned ambush under the escape clock |

The IAF trash (Sky Armor / Spit Fire, forms 175/176) carries no drawn gauge in
`bosses-wob.md`; it is ordinary break material and is not a set piece.

---

## 8. Engineering constraints and route notes

- **Trigger budget: ~16 free, and the FC needs none.** Measured in the
  shipped ROM: 83 trailing `$FF` = **16 free trigger slots**, 202 trailing in
  npc_prop (`event_trigger.asm:22`, `npc_prop.asm:188`). The FC's two save
  points are **vanilla** (§4), so the stretch adds no triggers at all. If
  future work does need one, the mechanism is unchanged: enlarge the
  `fixed_block` constant, let the bank-C4 chain shift (`save-points-vector.md`
  §1).
- **Telegraph must be data-authored.** The per-battle-frame HUD hook
  `Ot6BgHud_ext` has essentially no cycle headroom (under ~80, possibly <20).
  The FC bosses' telegraphs (Flare Star, Launcher, Sneeze, Condemned) must
  ride the existing break/shield tables, not new per-frame code.
- **The forced three-party (§2/§3) is the stretch's one roster decision.** The
  fourth of TERRA·LOCKE·STRAGO·RELM is benched for the whole IAF+FC. AtmaWeapon
  (11 shields, five-axis weakness) needs a lineup holding ≥2 of fire/ice/bolt/
  slash/pierce; Nerapa absorbs fire (don't bring a fire-only chipper).
- **A lost fight is a real Game Over** everywhere on this stretch (the IAF
  `_ca5ea9` handler, the escape-clock `GameOver`), unlike the massacre's
  savestate-split theater. The route needs a save before the FC (the 394 (7,12)
  point) and honest loss handling.

---

## 9. Measured on the current ROM (2026-09-07)

The three segments were re-cut in one sitting on ROM `build/ot6.sfc`
sha256 `783ac067…` (byte-identical to the main tree's 2026-09-01 19:01
content-stable ROM copy), with `main` merged into the parked branch (the post-v0.17 fight
driver: the cure-MP reserve, brokendeath chips before the kill; Shadow's
leave roll a no-op). Every run is `tools/tests/run.sh` with
`OT6_SRAM_CHECKPOINT` on the tracked battery, pad presses and reads only
(`check_playthrough_honest.py` passes); logs are under
`build/states/cuts/`.

| segment | run | verdict | battles | Fenix | levels going out |
|---|---|---|---|---|---|
| P → Q `gen_fc_landing` | `fc-landing-v1_20260907-072734.log` | `PASS (frame 65085)` | 14 IAF battle-actives (6 waves, Ultros④+Chupon, AirForce; the counter double-counts a wave whose load blinks) | 2, both in one wave (`[IAF] actor=1/2 revive entity 0`) | TERRA L23 · LOCKE L27 · EDGAR L25 |
| Q → R `gen_fc_alcove` | `fc-alcove-v1_20260907-073713.log` | `PASS (frame 38559)` | 7 randoms on 394 (two Dragons at 7000 HP, a Behemoth pack, two Ninja trios, two Apokryphos/Misfit fours) | 0 | TERRA L25 · LOCKE L28 · SHADOW L25 · EDGAR L27 |
| R → WoR `gen_fc_escape`, attempt 1 (mustflee walk) | `wor_landing_20260907-074008.log` | **FAIL** at Nerapa: `assertEq failed: Nerapa defeated: got true, want false` | AtmaWeapon won (24000 HP, 11 pips, re-shield at 4130 with 10; ~10,000 frames, 0 Fenix); 4 Naughty on 393; Nerapa LOST | 2, both on Nerapa | TERRA L26 · LOCKE L29 · SHADOW L25 · EDGAR L27 at `escape_start` |
| R → WoR `gen_fc_escape`, attempt 2 (fight walk) | `wor_landing_20260907-075542.log` | **FAIL**, the same line | frame-identical to attempt 1 through the doorstep (3:51 at f49317): the 63-frame L+R hold fell inside battle load | 2, Nerapa | — |
| lab V4 (from `escape_start`: dress CELES, then the escape) | `lab_escape_v4_20260907-081006.log` | `PASS (frame 22250)` | kit 1,349 clock frames; doorstep 3:40; Nerapa won, 2:05 left; Shadow saved at f22250 | 1, Nerapa | — |
| R → WoR `gen_fc_escape`, attempt 4 (ninja; CELES kit + ladder, no loss rules yet) | `wor_landing_ninja1_20260907-0820_FAIL.log` | **FAIL** — rung 1 "won" Nerapa at `master clock 0`, the Game Over followed and the harness Continued the alcove save: `navTo: no path (8,10)->(112,15)` | kit 621 clock frames (21567→20946); doorstep 3:43; rung 1 `seeded $be=$A0`, Nerapa fell at f63522 with 0:00 | **15, all on Nerapa** (27 → 12; `fenix=14` in the WON line was read before the last raises landed) — the driver raised the same member over and over under Condemned | — |
| R → WoR `gen_fc_escape`, attempt 5 (ninja; CELES kit + ladder with the loss rules) | `wor_landing_ninja2_20260907-0836_PASS.log` | `PASS (frame 91828)` | rung 1 `$A0` **abandoned** — `attempt 1 LOST at f63462: 13 Fenix Downs spent (budget 3)` (the field-bag read only registered at the fight's end; fixed after this run); reload; rung 2 `seeded $be=$D0 from $021e=52`, `WON on attempt 2 at f70176, master clock 6790` (1:53 left); Shadow saved; `landing: map=397 (99,38) party=1 hp=964 $00A4=1 $037D=1` | 2 on the accepted rung (27 → 25; the abandoned rung's 15 were reloaded away) | CELES L24 solo |
| R → WoR `gen_fc_escape`, attempt 6 (ninja; in-fight Fenix count, first cut) | `wor_landing_ninja3_20260907-0844_FAIL.log` | **FAIL** — harness, not play: the count scanned the battle inventory two frames after seeding, during battle load, found no record and read it as 27 spent; all five rungs (`$A0 $D0 $10 $40 $70`, 5 distinct seeds) were reloaded unfought | 0 battles fought | 0 | — |
| R → WoR `gen_fc_escape`, **attempt 7 (ninja; the committed gen)** | `wor_landing_ninja4_20260907-0857_PASS.log` (the agent worktree's run; not the qualified fixture, see the two rows below) | `PASS (frame 84582)` | rung 1 `$A0` abandoned in-fight — `attempt 1 LOST at f56216: 4 Fenix Downs spent (budget 3)` with 1:59 left; reload to the doorstep (27 Fenix, 13288 on the clock); rung 2 `$D0` `WON on attempt 2 at f62930, master clock 6790, fenix=25 (2 spent)`; Shadow saved; `landing: map=397 (99,38) party=1 hp=964 $00A4=1 $037D=1` | 2 on the accepted rung; `audit_fenix build/states/wor_landing.log` still counts the abandoned rung's 4 and flags `wor_landing 8 BOSS` — the lab candidate stands | CELES L24 solo, 964 HP |
| R → WoR, **the v0.16 qualification's fixture** (pass 3, 2026-09-07 10:48, pre-Reflect driver) | `build/states/wor_landing.log` in the qualification tree | `PASS (frame 78396)` | a different doorstep seed on the same policy: `[Nerapa] attempt 1 at f49661, master clock 13742, fenix=27` → `WON on attempt 1 at f54200, master clock 9327, fenix=27 (0 spent)`; `landing: map=397 (99,38) party=1 hp=964` | 0; `audit_fenix`: no threshold violations | CELES L24 solo |
| R → WoR, **regenerated on main under the Reflect-aware driver** (#156, 2026-09-07 ~11:40) | `build/states/wor_landing.log` on main | `PASS (frame 75594)` | `actor=0's summon took 515`, `actor=1's fight took 2285`, `[Nerapa] WON on attempt 1 at f53368, master clock 7340, fenix=27 (0 spent)`; party 819/1071/919/888 untouched; the lab (bosses-wob.md s22) shows this line 12/12 across seeds | 0 | CELES L24 solo |
| R → WoR `gen_fc_escape`, attempt 3 (fight walk + Nerapa seed sweep) | `wor_landing_20260907-080405.log` | `PASS (frame 78180)` | ladder rung 1 (`seeded $be=$10 from $021e=4`) won at t≈12,500 — `WON on attempt 1 at f61888, master clock 1419` (0:23 left); Shadow saved (`$037D`); `landing: map=397 (99,38) party=1 hp=964 $00A4=1 $037D=1` | **7, all on Nerapa** (Condemned killed slots 0–1 at t≈9,000 and they were raised) — a lab candidate | CELES L24 solo at the bedside |

Both battery payloads came out **byte-identical** to the 2026-09-01 cuts
(`fc-landing.sram` e7c0ea7b…, `fc-alcove.sram` 985d5a55…): the merged
driver changed no decision on those two segments. Their manifests now
carry the generator signature of the committed sources.

**The escape, measured from `escape_start`** (gen_fc_escape's second
artifact: first control on 393, master clock 21,567 frames = 5:59, Shadow's
clock 21,267). Four experiments from that one snapshot, all retained
(`lab_escape_v0..v3_*.log`):

- The 393 pool is one formation, **Naughty `$169` ×1, 3000 HP, 5 pips**
  (`audit_encounters.py 393`: group 123, no pincer). In battle `$b1` reads
  `$06` from frame 3: Naughty's `monster_prop` +19 is `$8D`, whose bit 3
  is the no-run flag (`UpdateMonsterGfxBuf` sets `$06` for it) and whose
  bit 0 is harder-to-run (+6 difficulty) — so nothing on this map is run
  from in this ROM. The flee helper's refusal there was the engine's own
  answer: `$b1` bit 1 (`CANT_RUN = 0x02`) is the gate the escape command
  itself tests (`Cmd_2a`: "can't run away!!"); bit 2 is only the smoke
  bomb's, and "harder to run" is not a `$b1` bit at all (#150, measured
  on camp_escaped: with `$b1=00` the helper's L+R released the party from
  two randoms). The walks declare the fight they were doing
  (`playBattles="tactical"`).
- Each Naughty falls to the physical line (Fight / AutoCrossbow, no BP
  bank) in ~1,200–1,900 frames; four of them cost the clock 7,700–8,300
  frames and the party reached Nerapa's doorstep at **3:41** (13,262; fight
  walk) / **3:51** (13,866; attempt 1's walk).
- A Bolt nuke on the walk was fatal to the *driver*, not the party: with
  `nuke={2}` the navTo driver's magic plan parked in menu state `$05`
  ("consumed 41 pulses in state $05 without landing", ten drops) on the
  second Naughty and the party bled out over 12,000 frames without a hit
  landing (V0 and V1, both wiped at (86,10)). Cause (#153, reproduced
  from fc_alcove with `probe_nuke_park.lua`): Naughty Mutes LOCKE
  (status 2 `$08`), the engine marks his Magic row disabled (`$202F`
  bit 7) and the command cursor skips it, so the steer's down/up hopped
  1 ↔ 3 around row 2 forever. `cmdRow` now reports a disabled row as
  absent and a plan whose row greys mid-menu is dropped; the same walk
  re-run plans Fight for the muted turn and wins the fight.
- **Nerapa is a coin flip on its seed at these levels.** Condemned is on
  all four by t=3000 (`$3EE5` bit 0 set, counts 32/31/29/25) and reaches
  zero around t≈7,000. The gen's attempt 1 (doorstep 3:51) lost: Nerapa at
  1263 HP / 2 pips by t=5100, then every actor healing or reviving
  (Potion 276 against round costs of 668–998) until the count ran out —
  wipe at t≈7,800, two Fenix Downs. From the same snapshot with the fight
  walk (doorstep 3:41, a different seed) the identical driver won at
  t≈6,000 with **1:48** left and no Fenix (V2); V3 (heal threshold 20 and a
  TERRA Bolt line) produced a frame-identical trace, so neither lever
  changed a decision — the driver's lethal-next-round heal rule and the
  once-per-fight summon dominate. One win and one loss on the current ROM
  is what is known; the passing gen run is a search-selected win, not a
  rate.
- The ledge wait from 1:45 works: Shadow's `$037D` set at f22154 in both
  passing labs, with `t0=1557 t2=1257` on the last logged wait tick.
- **CELES is the escape's fourth, and she arrives bare.** The statue scene
  puts her in party 1 (`$1850+6` = `$79` at `escape_start`; SHADOW's byte
  is `$00` — he has left) with every equipment slot `$FF` — she has been
  benched bare since the Vector crash — and the 888-HP fourth slot in
  every 393 battle log is her, swinging nothing. The field menu opens on
  393 with the clock running through it. Lab V4 (from the same
  `escape_start`): `H.equipKit` for CELES cost **1,349 frames of clock**
  (21,537 → 20,188) for one Equip and one Relic session; the Break Blade
  `$11` and relics `$B1`/`$B5` landed, her own list refused the bag's
  shield/helm/armor (`$84`, `$5B`/`$5A`, `$6B`/`$69`, ~120–150 frames each
  to find out), the walk still reached Nerapa at 3:40 (a different seed
  ran shorter fights), and Nerapa fell with **one** Fenix Down and 2:05
  left; Shadow saved at f22250. The gen now dresses her right after the
  `escape_start` save, so the lab fixture stays "first control, bare".
- Espers as worn (record byte +$1E in every fixture): TERRA `$02` SHIVA,
  LOCKE `$06`, SHADOW and EDGAR none. The deck's `SHIVA -> EDGAR` esper
  session logged "equipped, back on the list" and the byte never moved —
  `H.equipEsper` does not verify the stone landed (the summon it was meant
  to enable is refused every fight: `summon refused for char 4 … stone=$FF`).

**Nerapa, measured properly (lab, 2026-09-07; `bosses-wob.md` §22).**
The "coin flip" above was the driver, not the seed. Nerapa opens with
**Reflect** (`monster_prop` `$118` +29 bit 7; every traced fight reads its
status bytes `st=00,00,80,80`), so "LOCKE's Bolt nuke" and every Ice the
driver cast bounced onto the party for 275-1400 a cast and dealt Nerapa
nothing — the only damage the control policy ever landed was Shiva once,
the crossbow, and blade swings, and the turns after that went to raising
the bare CELES. From one doorstep snapshot (`lab_nerapa_bake.lua`:
`escape_start` → CELES's kit → the fought walk, doorstep at 3:50) over
the same 8-seed spread, the current driver won 4 of 8 distinct seeds
cleanly (1 more at 0:09 on 5 Fenix, 3 wipes); a no-magic policy (boosted Fight with
LOCKE's Genji pair, the crossbow, Shiva) won **every** seed in
2,200-3,300 frames with no deaths and no Fenix Downs, Nerapa dead before
its first Fire. The per-attempt lines and the table are in §22 of the
bosses doc; the driver requirement is a Reflect check before any attack
cast (a read of status 3 bit 7 at `$3EF8 + 2·slot`).

**Supplies.** Q leaves the alcove with `tonic=21 potion=33 fenix=27` after
the descent's care stops (99 Tonics bought at Thamasa; the IAF waves' care
spent 70 of them). There is no shop between Thamasa and the World of Ruin,
and the first WoR gen inherits the 2:08 Cid clock (§6) before any town.
