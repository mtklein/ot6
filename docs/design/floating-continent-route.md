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
Who to keep is a kit question for the FC break fights (AtmaWeapon wants two of
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
- 394 (70,29) → `_ca5a6c` (`event_trigger.asm:1961`) "The airship's below! Do you wish to return?" → `load_map 6,{16,6}` (`:13612`); the "Yes" branch `_ca5a8a` (`:13627`) sets **`$035E=1`** (`:13633`) *while AtmaWeapon is alive* (`if $035F=0`, `:13632`) — this is what poses Shadow's NPC.

**Encounters.** Only 394 rolls (`map_prop +5 = $80`; `SubBattleGroup[394]=112`;
`field/battle.asm:332-333`,`:394-411`). Group 112's four words are `$80B1/$80B4/
$80B7/$80B9` = base forms 177/180/183/185 **each +Rand(0..3)** (the `$8000`
flag, `battle_main.asm:8215-8224`) → effective pool **177–188**. Contents:
Behemoth `$020`, Apokryphos `$00c`, Misfit `$0a4`, Ninja `$003`, Wirey Drgn
`$0d8`, Brainpan `$04a`, Dragon `$083` — the vanilla FC pool. Map 358 is
encounter-free (`+5 = $00`). (Confirmed with `tools/audit_encounters.py 394`,
which the FC's `+Rand` flag first exercised — the fix is `e855c36`.) **Several of
these formations permit a pincer** (e.g. the Apokryphos/Misfit, Ninja, and
Brainpan groups), so a walk across 394 wants a fight budget or a `"tactical"`
playBattles mode, not a blind `"flee"` (HANDOFF, the flee bullet).

**Shadow rejoin.** Talk to the Shadow NPC at 394 (10,16), visibility switch
`$035E`, event `_cad9a7` (`npc_prop.asm:17437-17443`; script `:32586`):
`norm_lvl SHADOW` `:32616`, `char_party SHADOW,1` `:32625`, `$02F3=1` `:32627`,
clears the NPC `$035E=0` `:32633`, met-latch `$002A=1` `:32634`. `$035E` is set
only at `:13633` (above), so Shadow appears after the party reaches the return
point (70,29), elects to return, and has **not** yet beaten AtmaWeapon.
**verify-on-arrival** that nothing upstream pre-sets `$035E`.

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

**The crossing (map 394 to the save alcove 358).** The stair-reveal
triggers chain and the scripted chutes ride two-way: (40,6)↔(32,16) and
the (67,39)-walk pair are twins, so riding one down already visits its
return twin. A validated crossing: (4,8) → (19,12) (25,19) (40,12)
(40,6)-chute (36,28) (67,39)-walk (40,24) (63,33) (59,39) (52,24)
(82,30) (90,43) → 358.

Shadow's rejoin sits ahead of the (70,29) "return?" choice: choosing to
return with Shadow already talked in at (10,16) but not yet rejoined
triggers the scripted Shadow **removal** (`_cad9fc`), and the (89,25)
chute reaches that removal branch — so a route that wants Shadow at the
save alcove must avoid (70,29) after the talk-in. Shadow's 1/16
post-battle leave-roll is gated OFF while the live map is 394
(`Ot6ShadowLeaves`), since a mid-FC leave would clear `$02F3` and
forfeit the humane escape.

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
  (11 shields, five-axis weakness) wants a lineup holding ≥2 of fire/ice/bolt/
  slash/pierce; Nerapa absorbs fire (don't bring a fire-only chipper).
- **A lost fight is a real Game Over** everywhere on this stretch (the IAF
  `_ca5ea9` handler, the escape-clock `GameOver`), unlike the massacre's
  savestate-split theater. The route needs a save before the FC (the 394 (7,12)
  point) and honest loss handling.
