# OT6 v0.8 — Thamasa route survey

Scope per ROADMAP v0.8: the v0.7 stop line — checkpoint K, world (232,150),
party TERRA·LOCKE·SHADOW (`sealed-gate-recon.md` §1 segment 7) — through
Thamasa town, Strago joining, the burning house and FlameEater, Relm joining,
the Esper Mountain and Ultros ③, Kefka's massacre, and the post-massacre mission
transition, ending where control returns on the world map beside the repaired
Blackjack.

Claims cite a file and line or are labelled **UNVERIFIED**. Every formation
table below is an offline read of `battle_monsters.dat` /
`event_battle_group.dat` and is marked verify-on-arrival. Distances are
Manhattan lower bounds or unmeasured — no offline BFS has been run for this
area, and two of its maps are retiled by events partway through (§7 hazard
4), so a step model needs the right tile state.

---

## 0. HEADLINES

1. **The stop line is established precisely.** The area ends at
   `event_main.asm:78007-78009`: `load_map 0, {249,128}` + `airship_pos
   {249,127}` — control on the WoB world map at **(249,128)**, one tile from
   the repaired, re-flying(?) Blackjack, party **TERRA·LOCKE·STRAGO·RELM**,
   with the full roster re-normalized and re-available *except Shadow*
   (`$02F3` set 0 at `:77970` and never restored; `norm_lvl` sweep
   `:77976-77982`; availability restore `:77983-77988`; `$009D=1` `:77992`).
   Whether the party stands beside or aboard the ship, and whether liftoff
   works immediately (`$007A` is never cleared in the area — the fly-refusal
   script branches on `$007D=1` to `_cb1fef`, unread), is **UNVERIFIED** —
   v0.9's first probe.
2. **Two joins, one guest, and Shadow leaves twice.** Strago joins mid-fire
   (`char_party STRAGO,1` `:71794`, `$02E7/$02F7=1` `:71796-71797` — no
   `norm_lvl`); Relm joins **two lines before battle 125 begins**
   (`:73694-73701`); Shadow exits the party at the inn night (`char_party
   SHADOW,0` `:70456`, `$02F3=0` `:70653`) and exits the story two scenes
   later with `remove_equip SHADOW` (`:73018`) returning his gear to
   inventory. General **Leo is player-controlled, solo**, for the massacre —
   he rides the WEDGE actor slot (`char_prop WEDGE, LEO` `:76352`,
   `char_party WEDGE,1` `:76354`).
3. **Sketch goes live inside battle 125, and the fight's scripted finish IS a
   successful Sketch.** Relm is an active party member when the Ultros ③
   battle command runs (`:73698` vs `:73702`). Ultros's `MonsterSketch` row
   is **TENTACLE, TENTACLE** (`monster_sketch.asm:313`), and his AI reaction
   block ends the battle when he is hit by TENTACLE (`ai_script.asm:6315-6321`:
   dlg "I'm nothing more than a stupid octopus!" → `kill_monsters ALL`).
   Sketch is the only player source of Tentacle. The charm moment and the
   shipped bug share a die roll — a *missed* Sketch is exactly the bug's
   entry condition (§5).
4. **The area grants zero magicite.** No `give_genju` exists anywhere in
   `:69190-78110` (grepped). Kefka *takes* the drained espers; the player
   gets none. `magicite.md`'s "Bismark — Thamasa" acquisition proposal is
   contradicted by shipped state.
5. **The massacre is this area's banquet — one indivisible auto-chain.**
   From the mountain-top trigger 375 (15,17) (`_cbf2b5` `:74063`) the script
   runs the esper reveal, Yura, the return to town (`$0099=1` `:75156`), the
   Leo/Yura scene, and Kefka's arrival without returning control until the
   player holds a **solo Leo** in a locked town (`:76367`; map 341 has **no
   long entrances** — its own block is empty, the town cannot be exited).
   Inside it: loseable **battle 124** (Leo vs Kefka, real HP 5001), theater
   battles 105/97, and optional repeatable Guardian fights at the town-edge
   triggers (`_cc0960` `:78041`, `battle 75` `:78048` — no once-latch). No
   save is legal anywhere inside. The nearest prior save is the Esper
   Mountain save point.
6. **Vanilla already covers Ultros ③** — the mountain save point at 375
   (8,44) (`event_trigger.asm:1795`, sparkle in `NPCProp::_375` on the
   standing `$0632` switch) sits seven tiles from the statue-room door
   (375 (2,45) → 371 (9,9), short-entrance table). The area's two real holes
   are the **burning house** and the **massacre approach**. Plugging both
   costs 2 triggers + 2 NPC records — **the entire remaining game-wide
   budget** (13 trailing `$FF` bytes = 2 trigger slots, 76 = 8 NPC records,
   measured from `build/ot6.sfc`). §6 carries the relocation design.
7. **The relocation is two constants and one Lua pin.** Bank C4's segments
   flow *sequentially* from `C40000` by linker config (`ff6/cfg/ff6-en.cfg:61-70`;
   only `ending_gfx_1` is pinned, at offset `$ba00`), and the chain ends at
   `C4A4BF` — leaving a measured **$1540 (5,440) bytes of `$FF`** before the
   pin (verified byte-for-byte in the shipped ROM). Growing the two
   `fixed_block` sizes (`event_trigger.asm:19-22`, `npc_prop.asm:183-189`)
   shifts every downstream segment automatically; all readers are
   symbol-addressed far reads (`event.asm:5770-5804`, `player.asm:761-781`).
   The one hardcoded consumer in the repo is
   `tools/tests/battle_runic.lua:68` (`MAGIC_PROP = 0x046AC0`). Plus the
   standing cost: every savestate regenerates; batch checkpoints survive (#9).
8. **The encounter shape is the Zozo inversion, authored by vanilla itself.**
   Fire is the Esper Mountain's master key — Mandrake, Insecare, and Slurm
   are all weak to fire (§3.2) — and then FlameEater *absorbs* fire and
   punishes the button the mountain just taught (bosses-wob §18 already
   frames this; the trash data agrees with the frame). Ice/water is the
   counter-suite: Balloons, FlameEater, and (via the authored add) Aqua
   Breath's debut all line up.

---

## 1. The route, segment by segment

Switch chronology (all sets read from source):
`$008B/$008C` (magic vignettes, optional) → `$008D` (Strago talked,
`:69854`) → `$0190+$008E` (fire, `:70634-70635`) → `$02E7/$02F7` (Strago
joins) → `$0090` (FlameEater down, `:72129`) → `$0091+$0098` (morning after,
`:73000-73001`) → `$0092` (Shadow departs, `:73302`) → `$0096/$0097`
(statues, `:74018-74019`) → `$02E8/$02F8` (Relm joins) → `$0095` (Ultros
beaten, `:73801`) → `$0099` (back in town, `:75156`) → `$018A` (Kefka,
`:76337`) → `$009B` (Leo fallen, `:76598`) → `$009C` (burial, `:77313`) →
`$009D` (area tail, `:77992`).

Town map variants: map **343** until `$0099`, **341** while `$0099 && !$009C`
(the massacre state), **340** after `$009C`, **344** after `$00A4` (v0.9;
`_cbd2ee` `:69190-69205` and the interior exit routers `:69206-69290`).
Map 342 is a third variant that nothing loads (`load_map 342` appears
nowhere; empty trigger block) — the map-275 pattern, excluded.

### Segment 1 — checkpoint K → Thamasa town

From world (232,150), walk to the Thamasa world trigger at **(250,128)**
(`event_trigger.asm:35` → `_cbd2ee` `:69190`) → map 343 (23,46). Manhattan
lower bound 40 steps; **unmeasured** — no BFS run. Crescent Island world
trash is terrain-split (decoded via `CheckBattleWorld`'s
`(Y&$E0)|((X>>3)&$1C)` index OR'd with the terrain-group offset through
`BattleBGGroupTbl`, `field/battle.asm:97-147`):

| terrain group | pool (`monster_prop` +16/+8/+23/+25) |
|---|---|
| 24 (grass) | Baskervor `$01d` L22 HP750, no weakness · Cephaler `$096` L21 HP420 weak bolt |
| 25 (forest) | Chimera `$01f` L22 HP2237, no weakness · Cephaler ×3 |
| 26 (desert) | FossilFang `$023` L20 HP1399 abs poison, weak fire/ice/holy/water · Bug `$0e8` L16 HP310 weak ice/water (packs up to ×6) |

The Veldt is the neighboring sector west (`world_battle_group` `$FF`
sentinel at sector 152 — the veldt flag branch, `field/battle.asm:137-140`);
straying across the strait is not possible on foot but the adjacency is
worth knowing when the WoR comes.

Town on first entry (`$007D=1` branches): shops open — the weapon shop is
**the rod suite** (Mithril/Fire/Ice/Thunder Rod, Morning Star + Hawk Eye,
Stout Spear, Darts — `shop_prop.dat` row 33, menu at `:69475`), armor row 34,
items row 35 (Revivify, Remedy, Warp Stone), relics row 45 (Earrings, Wall
Ring, RunningShoes…). An NPC teaches the rod-as-item mechanic (dlg `$078D`).
Five minor chests on 343 only (Echo Screen, Green Cherry, Soft, Eyedrop,
Fenix Down — `treasure_prop.dat` map-343 block; **the later town variants
340/341/344 have no chest records**, so town chests are only openable
pre-`$0099`). The inn demands 1500 GP until Strago is talked to
(`_cbd769` `:69509`), 1 GP after (`$079D`, `:69483+`). Two optional
magic-in-secret vignettes on 343 arm at (35,15) and (25,12)
(`event_trigger.asm:1670-1672`; `$008B` `:69719`, `$008C` `:69802`).

### Segment 2 — Strago's house, the inn night, the fire

Strago's house is map **349** (town door 343 (29,13) → 349 (37,24); interior
stair pair (39,10)↔(61,20); Memento Ring chest at (56,16) upstairs). Talking
to Strago (`_cbd982` `:69814`) plays the Strago-then-Relm introduction and
**opens two naming screens back to back** (`name_menu STRAGO` `:69871`
region, `name_menu RELM` `:70067`) — a driving idiom no generator has
needed since the hello-world rename: the fixture must accept/confirm two
default names mid-scene. Sets `$008D=1` (`:69854`).

Sleeping at the inn (1 GP, `_cbd7ac` `:69540`, `$008D` branch `:69555` →
`_cbdcc7` `:70419`): the night scene — **Shadow leaves the party**
(`char_party SHADOW, 0` `:70456`), fire breaks out, `$0190=1 $008E=1`
(`:70634-70635`), Shadow runs off after Interceptor and goes *unavailable*
(`$02F3=0` `:70653`). Control returns on map 343 at (12,21), retiled: map
343's init `_cbd41a` (`map_init_event.asm:362` → `:69289`) applies the
burning-house `mod_bg_tiles` blocks whenever `$008E && !$0090` — **town 343
is a mod_bg_tiles map during the fire window** (§7 hazard 4). Town exits
(long entrances 343 (24,1)/(0,0)×31/(19,48) → parent world) are structurally
ungated, so a world save mid-fire looks legal — **UNVERIFIED live**. The inn
refuses service during the fire ("FIRE!!", `:69493` → `:69566`).

### Segment 3 — the burning house and FlameEater (map 351)

Talk to Strago at the house door — an NPC event, not a tile trigger
(`NPCProp::_343` record at (39,24) on switch `$0508`,
`npc_prop.asm:15217-15222` → `_cbde30` `:70668`). The scene ends with
**Strago joining** (`char_prop STRAGO` + `char_party STRAGO,1` + `$02E7=1
$02F7=1` + `max_hp/max_mp`, `:71790-71801` — **no `norm_lvl`**; join level
presumably comes from `char_prop`'s init-time averaging, **UNVERIFIED**) and
`load_map 351, {4,11}` (`:71852`).

Map 351 is event-only: no encounter enable, no exits except scripted ones,
entry party forced **TERRA·LOCKE·STRAGO** (`:71874`). Its content is all
NPC-triggered:

- **Twelve wandering flame NPCs**, each `set_npc_movement RANDOM` with
  collision on (map init `_cbe5cb`, `map_init_event.asm:370`; NPC block
  `npc_prop.asm:15714-15861`), each firing **battle 31** on contact-talk
  (`_cbe6cb…_cbe75a`, `:72012-72089`) — formations 158/159 = **Balloon ×3
  (75%) or ×6 (25%)** (the `EventBattle` two-word draw,
  `field/event.asm:1911-1922`). Balloon `$0de`: L22 HP555, absorbs fire,
  weak ice|water, sketch row SPECIAL/**EXPLODER** — they self-destruct for
  full HP. A fought flame is hidden+deleted for the rest of the visit.
- One scripted four-flame ambush at (21,22) (`_cbe622` `:71906`, **battle
  45** = Balloon ×4, `:71993`).
- **FlameEater** at (46,53) (`_cbe767` `:72095`): party order re-forced
  STRAGO·TERRA·LOCKE (`:72101`), **battle 79** (`:72124`) — formation 449,
  FlameEater `$116` L26 HP8400, absorbs fire, nulls bolt|poison|holy|earth,
  weak ice (+ the authored OT6 **water** add, `ot6_break.asm:472-479`;
  shields 7 · pierce, `ot6_hud.asm:1718-1719`; break story bosses-wob §18).
  `$0090=1` at `:72129`.

Two chests: Fire Rod (4,52) and **Ice Rod (45,7)** — vanilla's own hint
(rods break for a spell cast; the Ice Rod is a FlameEater key in hand on the
way in). After the fight: the Relm/Interceptor rescue, Shadow's smoke-bomb
exit, and the night talk at Strago's house (`load_map 349 {64,16}`
`:72613`), ending `$0091=1 $0098=1` (`:73000-73001`) with control in the
house, party TERRA·LOCKE·STRAGO.

### Segment 4 — Shadow's departure

Leaving Strago's house (349 (37,25), `event_trigger.asm:1708` → `_cbec92`
`:73010`, gated `$0091 && !$0092`) plays Shadow's goodbye on 343 (29,15):
`remove_equip SHADOW` (`:73018` — his gear returns to inventory; fixture
inventory assertions should expect it), Interceptor stays behind with Relm,
`$0092=1` (`:73302`). Town and world are then free; last chance to shop and
world-save before the mountain.

### Segment 5 — Esper Mountain: 375 ⇄ 372/373/374 → 371

World entrance **0 (229,130) → 375 (55,31)** (short-entrance table; return
375 (55,32) → world). Whether the entrance is *reachable* before `$0098` —
i.e. whether a party can sequence-break onto the mountain before the fire —
is **UNVERIFIED** (`$0098` is set with `$0091` but nothing in
`event_main.asm`/`world` reads it as a gate; the statue scene scripts a
STRAGO object it never checks for — a probe-first wedge risk, §7 hazard 8).

The map graph (short-entrance decode):

```
375 exterior hub: (48,9)/(16,8)/(45,41)/(52,46)/(42,26) ⇄ 372 (caves, grp 89)
                  (60,16)/(32,50)/(42,63) ⇄ 373 (caves, grp 89)
                  (36,41) ⇄ 374 (one-room cave, grp 89)
                  (2,45) → 371 (9,9)  and  (53,62) → 371 (19,15)   [statue room]
371 (10,9) → 375 (3,45);  371 (19,14) → 375 (53,61)
```

Slide triggers on 375 ((47,53)/(39,54)/(36,53), `:73340-73357` region) are
one-way descents; three more at (11,51)/(12,46)/(17,49) are
**`$0097`-gated `mod_bg_tiles` shortcuts** (`_cbee8f/_cbeebe/_cbeeec`
`:73358-73416`) — map 375's static tilemap stops describing the live map
once the statues are seen (§7 hazard 4). Three one-shot esper-glimpse
vignettes at 375 (53,17)/(47,57) and 373 (20,17) (`$017B/$017D/$017C`,
`:73417-73494`).

**Save point: 375 (8,44)** (`event_trigger.asm:1795`; sparkle on `$0632` in
`NPCProp::_375`) — seven tiles from the 371 west door. Encounters:

| map | group | pool |
|---|---|---|
| 372/373/374 | 89 | Mandrake `$0ee` L23 HP1150 abs water **weak fire** · Insecare `$0d0` L23 HP977 **weak fire|wind** · Abolisher `$0eb` L24 HP860 no weakness |
| 375 | 90 | Slurm `$0b8` L23 HP505 **weak fire** (packs to ×5) · Adamanchyt `$0d6` L24 HP1305 no weakness |
| 371 | — | no encounters (statue room) |

Chests: X-Potion (372 (41,34)), Tabby Suit (373 (14,9)), Chocobo Suit
(374 (18,9)), Heal Rod (375 (46,27)).

In the statue room, walking (15,20) fires the statue-lore scene (`_cbf168`
`:73807`, sets `$0096/$0097` `:74018-74019`); the very next tile (15,22)
fires **Ultros ③** (`_cbefa5` `:73495`, gated `$0097 && !$0095`):

- Ultros choreography, then **Relm is created and joins the active party**
  (`char_prop RELM` + `max_hp/max_mp` + `char_party RELM,1` + `$02E8=1
  $02F8=1`, `:73694-73701` — again **no `norm_lvl`**);
- **battle 125** (`:73702`) — formation 387, Ultros `$12e` L25 **HP22000**,
  absorbs water, weak fire|bolt; OT6 row 7 shields · slash|pierce
  (`ot6_hud.asm:1716-1717`). AI (`ai_script.asm:6267-6355`): opening dialog,
  self Haste+Safe under 15360 HP, Lode Stone on a 60-tick timer, a
  turn-count dive (Magnitude8/Aqua Rake, vanish-and-return), an
  elemental-counter form after 5 party Magic casts, `battle_event $16` under
  10240 HP (`:6310`), and two exits: HP zero, or **hit by TENTACLE →
  surrender dialog → `kill_monsters ALL`** (`:6315-6321`) — §5.
- post-fight: party **STRAGO·TERRA·LOCKE·RELM** (`:73709`), `$0095=1`
  (`:73801`), control in 371.

The player can walk back out to the 375 save point (and the world) here —
the last save before the massacre.

### Segment 6 — the massacre (one atomic chain)

Stepping on 375 **(15,17)** (`_cbf2b5` `:74063`, gated `!$0099`; resets the
vignette latches) starts the chain: espers reveal themselves, Yura's "Halt!"
(dlg `$07FF`), the Terra-power beat, agreement to meet Leo — **`$0099=1`
(`:75156`)** — auto-load town 341 (24,27) (`:75187`), the Leo/Yura peace
scene, Kefka's Magitek entrance ("How 'bout a little Magitek mayhem!"), and
the roster rewrite: everyone out, **LEO in as a solo party on the WEDGE
actor** (`:76346-76361`), `$018A=1` (`:76337`), control at 341 (22,22)
(`:76367`).

The Leo window: town 341 is **locked** (no long entrances; the three
exit-tile trigger rows `:78020-78040` instead fire `_cc0960` `:78041` —
"M.TEK TROOPER: General Leo, prepare yourself!" → **battle 75**, offline
decode formation 445 = **Guardian `$111` L71 HP50000** (the vanilla
Leo-vs-Guardian curiosity; no once-latch, so it repeats every approach —
and it is XP on a character who leaves forever, worth a fixture rule).
Formation decode suspect per the §11 precedent; the Guardian carries the
0-gauge scripted-theater OT6 row (`ot6_hud.asm:1742-1743`). Approaching
Kefka (`_cbfff4` `:76452`, an NPC event) → **battle 124**
(`:76470`, `char_prop VICKS, KEFKA_4` `:76461`): formation 388 =
KEFKA_VS_LEO `$173`, L1 **HP5001**. Its AI (`ai_script.asm:7952-7965`) is a
real fight — Battle/Poison, Fire 3/Bolt, Bio/Drain — that ends only
`if_self_dead` (→ `battle_event $17`, `end_battle`). **Leo must win it, solo,
and losing is presumed a game over — UNVERIFIED.** Leo's Shock is a free
guest verb by standing ruling (`mp-economy.md`, the guest-verb row of
"The verb survey").

Then without a further save opportunity: `$009B=1` (`:76598`), theater
**battle 105** (formation 389, dummy `$17b`) and the scripted esper flyover
(`load_map 0 {181,197} AIRSHIP` + vehicle choreography, `:76602-76627`),
reload 341 (24,19) (`:76628`), Kefka's drain scenes, **battle 97**
(`:76954`, VICKS=KEFKA_3 `:76945`): formation 392 = KEFKA_VS_ESPER `$17a`
HP50001, whose AI is pure theater — espers cast Fire/Fire 2/Fire 3 at him,
`battle_event $1a`, `end_battle` (`ai_script.asm:8047-8056`). Leo dies in
the scene, the party is restored (`:77242-77253`, WEDGE out), and the grave
scene on map 340 (54,19) (`:77259`) sets **`$009C=1` (`:77313`)**.

### Segment 7 — burial, the Blackjack returns, the handoff

Auto-chained scenes: Terra at Leo's grave, wounded Interceptor, the airship
flying in (`load_map 0 {211,170} AIRSHIP` `:77500`), Setzer/Cyan/Edgar/Sabin
at 340 (22,28) ("We've been had!! The Emperor is a liar!"), Strago and Relm
talking themselves aboard, then the area tail (`:77962-78009`):
availability zeroed and rebuilt with `norm_lvl` for
CYAN/SHADOW/EDGAR/SABIN/SETZER/GAU/CELES (+MOG if available, `_cc0935`
`:78014`), everyone restored **except `$02F3` (Shadow)**, `and_status
SHADOW, NONE` (`:77990`), `$009D=1 $01BA=1` (`:77992-77993`), and control at
**world (249,128)**, airship parked at (249,127).

**The v0.8 stop line: world (249,128), party TERRA·LOCKE·STRAGO·RELM,
`$0099=$009B=$009C=$009D=1`, `$02E7/$02E8/$02F7/$02F8=1`, `$02F3=0`,
world-saveable.** The natural batch checkpoint (§2).

---

## 2. Save opportunities and checkpoint candidates

### 2.1 Inventory, route order

| # | where | what | evidence |
|---|---|---|---|
| S0 | world (232,150) | checkpoint K, the v0.7 terminal | `sealed-gate-recon.md` §1 segment 7 |
| S1 | world, Crescent Island | save anywhere on the walk to (250,128) and on every town↔mountain crossing until `$0099` | dlg `$06D4` world-save rule (`save-points-vector.md` §1) |
| S2 | world outside town, mid-fire | structurally open (343's exits are ungated during `$008E`) | **UNVERIFIED live** |
| S3 | **map 375 (8,44)** | the Esper Mountain save point — before the statues, and reachable again between Ultros ③ and the massacre trigger | `event_trigger.asm:1795`; `NPCProp::_375` sparkle |
| S4 | world (249,128) | the stop line | segment 7 |

No `SavePoint` trigger exists on any other map in this area — the blocks for
340-351 and 371-375 were read in full (`event_trigger.asm:1647-1803`; the
nearby SavePoints on maps 353/354/355/358 belong to other areas' maps —
Veldt Cave, Floating-Continent-era maps, and an event-only interior — none
is reachable from this area). The town has **no save point in any variant**,
and map 341 additionally cannot be exited.

The two holes, measured against #10's principles:

- **The burning house.** Retry boundary for FlameEater is S2 (if the fire
  window really allows leaving town) or the pre-inn world save — either way
  a retry replays the fire-night scene and/or the flame gauntlet. Not
  catastrophic (the gauntlet is short) but it is the area's only boss whose
  entry point has no save inside ~40 steps.
- **The massacre approach.** Battle 124 is a loseable solo fight buried
  ~three scenes deep in an unskippable chain; a loss replays from S3 plus
  the entire mountain-top → Yura → town → Kefka choreography. This is the
  single worst retry cost in the area and it lands on the area's least
  conventional fight.

### 2.2 Proposed checkpoints (leg-fixtures.md letters continue from K)

| checkpoint | batch save at | exists? |
|---|---|---|
| **K** `thamasa-mission` | world (232,150) — the input | v0.7 deliverable |
| **L** `thamasa-night` | world outside town, `$008D=1`, party TERRA·LOCKE·SHADOW, pre-inn | world save, no authoring |
| **M** `fire-out` | world outside town, `$0090=$0091=$0092=1`, party TERRA·LOCKE·STRAGO | world save, no authoring |
| **N** `esper-mtn-save` | map 375 (8,44), pre-statues (`$0097=0`) | vanilla save point |
| **O** `ultros-won` | map 375 (8,44) again, `$0095=1`, party +RELM | same save point, second visit |
| **P** `thamasa-done` | world (249,128), `$009C=$009D=1` — the v0.8 terminal | world save, no authoring |

Segments: K→L (world walk, town, two name menus — short), L→M (**the fire
block**: inn scene, house gauntlet, FlameEater, rescue night, Shadow's
goodbye — one long interior stretch with no legal checkpoint inside; splittable
only by savestates at `house_entry` / `flameeater_won`), M→N (world walk +
mountain approach), N→O (statues + Ultros ③ — short, the vanilla save point
serves both ends), O→P (**the massacre block**: the atomic chain of segment 6 —
battle 124 is the risk point; savestate splits at `massacre_start` /
`kefka_duel_won`, never checkpoints). K→L, M→N are trivial; L→M and O→P are
the work.

### 2.3 Entry contracts worth pinning

- L/M/N/O/P must assert the **availability vector** (`$02F3=0` from M
  onward; `$02E7/$02F7` from M; `$02E8/$02F8` from O) — the area is
  join-heavy and a stale checkpoint with the wrong roster passes size checks
  while breaking every scene's `party_chars`.
- M must assert Shadow's equipment is back in inventory (`remove_equip`,
  `:73018`) — the #21 count-assert pattern applied to gear.
- O must assert `$0095=1 && $0099=0` — the window between Ultros and the
  massacre trigger is the only place O can legally exist; a save generated
  after stepping on (15,17) is unreachable-in-principle.
- P asserts the segment-7 tail: `$009D=1`, four-person party, Shadow
  unavailable, `norm_lvl`'d bench (spot-check one benched level against the
  party average).

### 2.4 ROM budget — the verdict

Measured from the shipped `build/ot6.sfc`:
`event_triggers` has **13 trailing `$FF` = 2 free trigger slots**;
`npc_prop` has **76 = at most 8 records**.

v0.8's wants, priced per `save-points-vector.md` §1 (5 bytes trigger +
9 bytes NPC each):

1. **A save point in Thamasa town on map 343** (e.g. the square near
   (33,25)) — covers the fire window (FlameEater retry) and the general
   Octopath town cadence. 1 trigger + 1 NPC. Reuses standing switch `$0632`;
   simplest and highest player value.
2. **A save point at the mountain top near 375 (15,17)** — the last
   controllable ground before the massacre chain; cuts the battle-124 retry
   from "whole chain" to "the chain from Yura on" (the chain itself cannot
   be shortened; the save just eliminates the mountain re-climb).
   1 trigger + 1 NPC.

Both together = **2 triggers + 2 NPCs: exactly the whole remaining budget,
leaving zero for the deferred v0.5/Opera backfill (~5 wanted per #10's
deferred list).** The combined need (≈7) exceeds the budget (2) — the
dispatch's expectation holds. §6 is the relocation design that resolves it.

The bare minimum is also on the table: **zero mandatory spends.** Vanilla
covers Ultros ③; the fire window arguably has S2; the massacre hole is
mostly a *fixture* problem (savestates) and vanilla shipped it this way.
But both placements score well against #10's published principles, and the
budget is the only reason to hesitate — which is an argument for fixing the
budget, not for skipping the saves.

---

## 3. Bosses and set pieces

### 3.1 The fight slate

| fight | where | formation (offline decode — verify on arrival, §11 precedent) | notes |
|---|---|---|---|
| battle 31 ×12 | map 351 flames | 158/159 → Balloon `$0de` ×3 (75%) / ×6 (25%) | contact battles; Exploder = full-HP self-destruct; flames wander randomly |
| battle 45 | 351 (21,22) | 411 → Balloon ×4 | scripted ambush |
| **battle 79** | 351 (46,53) | 449 → **FlameEater** `$116` L26 HP8400, abs fire, null bolt/poison/holy/earth, weak ice (+OT6 water) | shields 7 · pierce; party STRAGO·TERRA·LOCKE; bosses-wob §18 is current |
| **battle 125** | 371 (15,22) | 387 → **Ultros ③** `$12e` L25 HP22000, abs water, weak fire/bolt | shields 7 · slash\|pierce; Relm active; two exits: HP zero or Sketch→Tentacle (§5); `battle_event $16` under 10240 HP — content unread, probe |
| battle 75 (repeatable) | 341 exit rows, Leo window | 445 → **Guardian** `$111` L71 HP50000 | 0-gauge theater row exists; XP-on-Leo hazard; decode suspect |
| **battle 124** | Kefka approach, Leo solo | 388 → KEFKA_VS_LEO `$173` HP5001 | **real, loseable**; ends only on Kefka's death (`ai_script.asm:7959-7964`); no OT6 row — falls to the generated break floor and *will draw a gauge* (decision 4) |
| battle 105 | esper flyover | 389 → dummy `$17b` | theater |
| battle 97 | drain scene | 392 → KEFKA_VS_ESPER `$17a` HP50001 | pure script: espers cast, `battle_event $1a`, end (`ai_script.asm:8047-8056`) |

Boss break data is **already authored** for the area's two conventional
bosses and the Balloons (`ot6_hud.asm:1716-1721`), and FlameEater's water
add shipped with #23 (`ot6_break.asm:472-479`). What is *not* authored:
`$173`/`$17a` (massacre Kefkas) have no rows — the break floor will give
them a weapon-class weakness and the HUD will draw a formula gauge
(2+level/8; L1 → gauge 2) on what are script-shaped fights. Report/Report/decision 4.

### 3.2 Encounter survey shape (the #11-style pass)

The area's random-encounter surface is small: three mountain cave maps
(group 89), the mountain exterior (group 90), and three world terrain
groups (24/25/26) — §1 segments 1 and 5 carry the full pools. The shape:

- **Fire is the mountain's master key** (Mandrake, Insecare, Slurm), teaching
  exactly the button FlameEater then absorbs — vanilla authored the OT6
  house lesson unprompted. Terra's lean works on trash; the boss forces the
  pivot to ice/water (Ice Rod chest, Aqua Breath, the shipped water add).
- **No-weakness bodies** carry the other axis: Abolisher, Adamanchyt,
  Baskervor, Chimera have empty weak rows and ride the generated break
  floor (weapon classes only). The survey pass should decide whether any
  gets an authored element row or whether class-only is the intended
  texture for an area whose kit additions (rods = bludgeon, brush = special)
  want weapon-class relevance anyway.
- Levels: island L20-22, mountain L23-24, bosses L25-26 vs a party arriving
  from v0.7 at roughly L16-19 (**unestablished** — v0.7 has not been generated;
  wob-route measured L15-16 at the v0.6 tail). The gap is the area's
  balance question: vanilla tuned Thamasa for ~L22+ parties. The XP texture
  on the way (two scripted Balloon gauntlets, a repeatable Guardian that
  only Leo can farm) does not close it. Measure at authoring, per the M6
  discipline.

---

## 4. Character / kit / magicite obligations

- **Strago (Blue Mage/Scholar, `kits.md`'s "Curated kits").** Joins in segment 3
  with no norm_lvl and fights FlameEater within minutes — his debut showcase
  is already designed (Analyze scout + Aqua Breath water chip, bosses-wob §18)
  but **the machinery is not built**: the curated-kit model (learn many,
  equip ~5 — M4 ⬜, `ROADMAP.md` M4's curated-kit machinery),
  Lore-by-observation, and Analyze itself (it rides that same M4 kit work) are
  all open. Aqua Breath free at join, Lores MP-priced (`mp-economy.md`, "The
  verb survey"). Base MP 13 (`mp-economy.md`, "Early pools") under the
  now-universal pool (#32). This is the area's largest kit build.
- **Relm (Pictomancer, `kits.md`'s "Curated kits").** Joins in segment 5 *inside*
  the Ultros scene. Kit is "Sketch ✦ signature (bug preserved ✦), support/trickster kit
  TBD" — v0.8 must at minimum decide the 8-slot sketch (sic) of her kit even
  if only Sketch + basics ship. Sketch's MP price is proposed flat 2-4,
  no refund on the bug (`mp-economy.md`, "The verb survey"). Control is
  explicitly deferred there too ("priced when her kit lands"). Base MP 18.
  Boost canon: §5.5.
- **Shadow — the #31 entry debt.** He is party-active only from checkpoint K to
  the inn night (segments 1-2: one town, no mandatory fights, then gone until the
  Floating Continent). The v0.7 issue moved his kit here; the real scope
  question is whether a kit that is *reachable* for ~20 controllable minutes
  with zero required battles justifies the build now, or whether the debt
  moves once more to v0.9 (where he is forced party on the FC approach and
  the kit is load-bearing). Throw is free by ruling (item is the price,
  `mp-economy.md`, "The verb survey"); Assassinate is built dormant since v0.4.
  Report/decision 3.
- **General Leo.** A real, loseable solo fight on a guest. Shock free
  (`mp-economy.md`'s standing guest-verb ruling covers him; no kit
  table needed). What is unsettled is presentation: battle 124's Kefka has
  no authored OT6 row, and Leo has no BP/boost tutorialization — does the
  gauge/boost HUD even behave with a WEDGE-actor solo party? Probe;
  Report/decision 4.
- **Magicite: zero new stones** (headline 4). The area's M5 obligation is
  whatever v0.7 left: if the six tube-room redesigns shipped in v0.7 (per
  #31's commitment), v0.8 has **no esper work at all** — the first such area.
  If v0.7 re-scoped, the debt compounds here. Either way v0.8 adds none.
- **Equipment flow to assert in fixtures:** Shadow's gear returns at segment 4
  (`:73018`); the area tail norm-levels the entire bench (`:77976-77982`)
  — any fixture asserting exact bench levels across the area boundary will
  see them move.

---

## 5. Sketch, operationally

The owner's decision is final and shipped: **the Sketch bug ships unfixed,
documented** (CONTRIBUTING.md "House rules"; `vanilla-destructive-bugs.md`).
This section is the operational plan that decision requires.

### 5.1 Where Sketch becomes player-usable

**Battle 125 is the first live Sketch**, and it is not incidental: Relm
joins the active party two script lines before the battle command
(`:73698` → `:73702`), her command set is FIGHT/SKETCH/MAGIC/ITEM
(`char_prop.asm:236-244` per the research doc), and the fight's scripted
finish rewards Sketch specifically — `MonsterSketch[302]` = TENTACLE,
TENTACLE (`monster_sketch.asm:313`), and Ultros's reaction block converts an
incoming TENTACLE into surrender + `kill_monsters ALL`
(`ai_script.asm:6315-6321`). After `$0095`, every random battle with Relm
deployed carries Sketch: the rest of the area has *no mandatory battles
with Relm* (she is benched for the massacre), so within v0.8 the exposure
surface is battle 125 plus optional mountain/world trash on the walk out.
From the stop line onward she is a free-pick party member and the surface
is everything.

### 5.2 The mechanics, read (what "miss" means here)

`TargetEffect_55` (`battle_main.asm:9673-9700`) exits without fixing `$b7`
(the poisoned byte) in three cases: target is a character (`cpy #$08`),
target flagged unsketchable (`$3c80,y` bit `$20`), or the
`CheckSketchHit` roll fails. `CheckSketchHit` (`battle_main.asm:9065-9083`)
is a level ratio — attacker level vs target level (Coronet scales it);
when the attacker's level is not clearly above the target's, a random roll
decides. Direction of the division **read but not traced** — the operational
consequence is the same either way: **at the levels here (Relm ~L17-24 vs
Ultros L25) a Sketch miss is a live outcome, plausibly ~20-30% per cast,
and every miss walks the `$b7=$ff` path into `AnimType_2f`'s unguarded
index** (`vanilla-destructive-bugs.md`: severity is
data-dependent — corrupt sprite, spawned inventory, or a bank-`$7e` sweep
that reaches the save block and battle inventory). Ultros ③ is sketchable
(flag bit clear — his sketch row is load-bearing for the scripted finish).

### 5.3 What the release notes must say, concretely

The policy branch being exercised is "explicitly accepted in the release
notes — never shipped silently" (CONTRIBUTING). The notes need four
concrete sentences, not a link:

1. **What:** Relm's Sketch carries FF6 1.0's most famous bug, on purpose.
   When a Sketch *misses*, the game can — rarely — corrupt the item
   inventory, crash, or damage the save in ways that surface later. When a
   Sketch *hits*, the bug cannot fire.
2. **When:** misses happen against enemies of higher level than Relm and
   against vanished/invisible targets. Her debut fight (the octopus on the
   Esper Mountain) is above her level — the joke fight is also the riskiest
   Sketch you will ever cast, and yes, sketching him is still the intended
   finish.
3. **Defense:** save before experimenting — the world map saves anywhere,
   and the mountain save point is right outside the arena. [If Report/decision 1
   ships the town save point, name it here too.]
4. **Why:** vanilla's destructive bugs normally get fixed (the save-slot
   checksum bug was, v0.6/#18); this one is the deliberate exception —
   it is the canonical piece of 1994 jank the project keeps as charm, by
   owner decision. Not a known-issue-we-ran-out-of-time; a house rule.

### 5.4 The FIXTURE hazard — real, and it needs a rule

The dispatch asked whether a gen or playtest drive can trip the bug
accidentally. **Yes, with meaningful probability, at the worst possible
moment:**

- The natural way to script battle 125 is the way the game teaches — drive
  Sketch. Every driven Sketch at the levels here risks the ~1-in-4 miss, and a
  miss during a savestate-generation run can sweep bank `$7e` — the save block
  and battle inventory — right before the harness writes the batch checkpoint
  (O `ultros-won`) that every downstream segment will trust. A corrupted-but-
  checksum-valid tracked checkpoint is the nastiest failure the leg-fixtures
  design can produce (the invariant contract is the only net under it).
- The same applies to any gen past this area that deploys Relm and sweeps
  commands.

Proposed harness rules (for the dispatcher to adopt into the agent brief /
gen conventions):

1. **Savestate-generating scripts never issue Sketch.** Battle 125's generator ends
   the fight on HP (22000 HP is long but deterministic) or — if the Sketch
   finish is wanted for route fidelity — only after a probe confirms the
   attacker-level ≥ target-level auto-hit condition holds for the generated
   party (it will not, at the levels expected here; so: HP finish).
2. **The Sketch charm moment gets one dedicated, isolated probe fixture** —
   savestate-in, savestate-out, feeding **no** checkpoint — that drives Sketch,
   observes both outcomes (Tentacle finish on hit; on a forced miss,
   watches `($76),3` / `$b7` per the research doc's settle-list) and
   documents the shipped behavior. That probe doubles as the release-notes
   evidence and settles the Sketch row of
   `vanilla-destructive-bugs.md`'s "REPORTED, UNVERIFIED" table — worth doing
   even though no fix will follow.
3. **Checkpoint O's entry contract** (and P's) should include an inventory
   checksum/spot-assert so a silent `$7e` sweep in any earlier drive fails
   loudly instead of laundering into the baseline.

### 5.5 Reconciling the boost canon with ships-unfixed

The chance-verb canon (`kits.md`'s "chance-verb family", ROADMAP design
canon) slates
Sketch for boost-certainty: BP buys sketch **selection** — the hit roll and
the 75/25 move pick (`battle_main.asm:9694-9700`: `Rand cmp #$40` selects
between the two `MonsterSketch` entries). The bug is a **graphics-index
escape on the failure path**. Do they intersect? **Yes — at exactly one
branch, and in the safe direction.** Boost-certainty forces
`CheckSketchHit` to succeed, and the success path is what writes a valid
`$b7` (`:9691`); a boosted Sketch therefore *cannot* reach the bug through
the miss exit. At 0 BP the verb is vanilla to the byte — canon requires
this (Steal's shipped precedent) — so **the bug remains reachable exactly
where the owner ruled it ships: in unboosted play.** Two implementation
constraints follow for whoever builds Relm's boost tier:

- Force success **through** the vanilla success path (let `TargetEffect_55`
  run and write `$b7`), never by skipping the target effect — a shim that
  bypasses it would *create* new `$ff` escapes.
- Leave the invalid-target exits alone: a character-targeted or
  unsketchable-target Sketch is not a "chance" and boost must not validate
  it; those exits stay vanilla (and stay bug-reachable — that is the
  shipped rule, and the release notes' "misses" language covers it).

No conflict exists between the canon and the ruling; `kits.md`'s Relm sketch
("bug preserved ✦") is already the synthesis.

---

## 6. The bank-C4 budget, and the segment-relocation design (proposal)

### 6.1 The measured facts

- `event_triggers` is a `fixed_block $1a10` at the head of bank C4
  (`event_trigger.asm:19-22`); `npc_prop` a `fixed_block $50b0` abutting it
  (`npc_prop.asm:183-189`). `fixed_block` pads to the declared size and
  errors on overrun (`macros.inc:408-431`).
- The bank's segments are laid **sequentially by the linker** — none of the
  chain has a fixed offset; only `ending_gfx_1` is pinned, at `$ba00`
  (`ff6/cfg/ff6-en.cfg:61-70`). The chain (`ff6/rom/ff6-en.map:200-208`):
  `event_triggers → npc_prop → magic_prop → char_name → blitz_code →
  init_rage → shop_prop → metamorph_prop → font_gfx`, ending at `C4A4BF`.
- **Free space: `C4A4C0-C4B9FF` = `$1540` (5,440) bytes**, measured as
  all-`$FF` in the shipped `build/ot6.sfc`.
- Remaining slack inside the blocks: 13 bytes (2 trigger slots) / 76 bytes
  (8 NPC records).

### 6.2 The design: grow in place, don't relocate anything

Because the chain is sequential and symbol-addressed, "relocation" is not a
move at all — it is **two constants**:

```
event_trigger.asm:  fixed_block $1a10  →  fixed_block $1a60   (+$50 = +16 trigger slots)
npc_prop.asm:       fixed_block $50b0  →  fixed_block $5140   (+$90 = +16 NPC records)
```

Everything downstream shifts by `$E0` and the assembler recomputes every
reference for free: the trigger/NPC pointer tables are `ptr_tbl` label
arithmetic, and every runtime reader is a far symbol read
(`event.asm:5770-5804` triggers, `field/event.asm:1921` event battles,
`player.asm:761-781` treasure, the `MagicProp`/`ShopProp`/`MetamorphProp`
splices in `battle_main.asm`/`shop.asm`). Sixteen-and-sixteen covers v0.8
(≤2), the Opera backfill (~5), and the rest of the WoB with margin, and
spends only `$E0` of the `$1540` headroom.

### 6.3 What breaks — the full list

1. **`tools/tests/battle_runic.lua:68`** pins `MAGIC_PROP = 0x046AC0` (with
   the comment at `:39` acknowledging the pin). One-line fix; better, make
   it read the address from the map file the build already produces, so the
   next growth is free.
2. **Every savestate dies** — this is a ROM change like any other
   (`leg-fixtures.md`, "The problem"); the full savestate chain regenerates
   once. **Batch checkpoints survive** (#9's proven property) — which is
   precisely why the checkpoint conversion should be ahead of this change,
   and why the change should land **in v0.8's already-inevitable ROM
   window** (kit tables, encounter rows, and any new save points are ROM
   changes too; one window, one regeneration).
3. **The BPS patch grows**: every byte from `C41A10` to `C4A4BF` shifts, so
   the patch carries a ~35 KB shifted region it didn't before. Cosmetic,
   but worth expecting in the release diff.
4. **Docs that quote absolute C4 addresses** (`data-formats.md`'s
   "$C46AC0", the `; c4/xxxx` comments in the disassembly) go stale by
   `$E0`. The comments are vendor cosmetics; the research doc should gain
   one line noting the OT6 offset.
5. Not broken, worth stating: the sparkle-append rule
   (`save-points-vector.md` §1 — append records at the end of a map's NPC
   block, never insert) is unaffected; per-map NPC indices don't move.

### 6.4 Recommendation

Land the growth **with v0.8's first ROM change**, before the area's save
points and kit tables, so the budget stops constraining design during the
milestone rather than after it. The v0.8 spends (decision 1) then come out
of a 16-slot pool instead of a 2-slot one, and the Opera backfill stops
being blocked on segment surgery. If the dispatcher prefers deferring, the
fallback is reasonable too: v0.8 fits in the existing 2 slots (§2.4), and the
growth waits for the backfill — but it regenerates the whole savestate chain a
second time for no saved work.

---

## 7. Known hazards, ranked

1. **The massacre chain is atomic and loseable in the middle.** From 375
   (15,17) to the 340 grave there is no save, no exit (341 has none), and
   battle 124 is a real solo fight (§1 segment 6). Fixtures: savestate splits
   only; assert `rideScene`/`hasControl` around the two Leo control
   windows. Players: the retry is S3 + the whole chain — the §2.4
   mountain-top save point is the mitigation.
2. **Sketch in harness drives** (§5.4). One rule — savestate-generating scripts
   never issue Sketch — removes the whole class; adopt it before the first Relm
   fixture exists, not after a corrupted checkpoint.
3. **Nondeterministic actors on the critical path.** The 12 burning-house
   flames wander `RANDOM` with collision on; the Balloon draw is 75/25
   (3 vs 6); world/mountain trash is standard RNG. The house drive needs
   either a flame-tolerant `navTo` (fight-through: every contact is a
   battle 31) or per-step re-planning; do not script fixed paths.
4. **Three mod_bg_tiles contexts**: town 343 during the fire (init
   `_cbd41a`), the fire's mid-scene retiles (`_cbde30`), and mountain 375
   after `$0097` (the three shortcut retiles). Offline BFS on those maps in
   the wrong state will lie — the v0.6 §11 correction class. Live census at
   authoring.
5. **Two naming screens mid-scene** (`name_menu STRAGO/RELM`, segment 2). A new
   driving idiom; a gen that only knows dialog-advance will hang on the
   first one.
6. **The `$0099→$009C` town lockdown**: any fixture assuming "towns can be
   exited" breaks on 341. Conversely the segment-6 exit-row triggers fight a
   repeatable Guardian — a drive that wanders into an exit row mid-window
   eats a 50000-HP theater fight (and Leo banks the XP; he leaves forever,
   so it is pure waste plus RNG).
7. **Join levels are un-normalized at join** (Strago `:71790-71801`, Relm
   `:73694-73701` — no `norm_lvl`; the area tail normalizes the *bench*,
   not them). If `char_prop` init-averaging is weaker than assumed
   (**UNVERIFIED**), Strago could reach FlameEater at a floor level.
   One probe: read Strago's level at M.
8. **Sequence-break wedge risk at the mountain**: the statue scene scripts a
   STRAGO object with no presence check (`_cbf168`), and nothing readable
   gates the world entrance (229,130) before the fire (`$0098` is written,
   never read as a gate — grepped). If a pre-Strago party can walk in, the
   scene is a probable hang. Vanilla may prevent it by geometry
   (**UNVERIFIED**). Worth one probe at the entry point; not a route risk for the
   canonical chain.
9. **Offline decode trust boundaries**: formation 445 ("Guardian" for the
   Leo exit fights) and every dummy-species formation (105/97) carry the
   §11 Shiva caveat; `battle_event $16/$17/$1a` contents are unread. Probe
   before asserting anything about their contents.
---

## 9. Open questions for the milestone

1. **Battle 125's `battle_event $16`** — what actually happens under 10240
   HP (Relm dialog? the sketch tutorial beat?). Probe `formationWords()` +
   ride the event.
2. **Can battle 124 be lost, and what does losing look like** (game over vs
   scripted continue)? Decides how paranoid the O→P fixture must be and
   what the release notes say about the Leo fight.
3. **Leo's level and kit surface** in battle 124 under OT6 (BP pips? boost
   input live? gauge drawn on an unauthored `$173`?). One savestate probe.
4. **Does the fire window really allow leaving town** (S2)? One drive:
   fire on, walk out (19,48), world-save, re-enter, assert `$008E` state
   reconstruction.
5. **Join-level mechanics** for Strago/Relm (no `norm_lvl` at join): read
   `char_prop` init or measure at M and O.
6. **Mountain sequence-break** (hazard 8): walk a pre-`$008D` party to
   (229,130); if entry succeeds, walk to 371 and observe.
7. **Stop-line posture**: on-foot beside the ship vs aboard; is liftoff
   live (`$007A` uncleared, `_cb1fef` unread)? v0.9's entry contract
   depends on it.
8. **The v0.8 offline BFS set**: 343 (both tile states), 351, 375 (both
   states), 372/373/374 — run the ported step model with per-state
   tilemaps; live-census 375's shortcut retiles.
9. **XP/gil conservation across the area's scripted battles** (12× battle
   31 at player option, repeatable battle 75 on a departing guest): does
   this area's balance need a rule for Leo-banked XP?
10. **Where does `battle_event $17` (Leo's fall) leave battle state** — the
    monster-dead-flag idiom question for the one real fight in the massacre.

---

## Appendix — key addresses

| thing | citation |
|---|---|
| Thamasa world trigger | `event_trigger.asm:35` {250,128} → `_cbd2ee` `event_main.asm:69190` |
| town variant routing | `:69190-69290`; map 342 unused (no loads, empty trigger block) |
| map inits (fire retile, corpses, grave) | `map_init_event.asm:359-370` → `_cbd41a :69289`, `_cbffa6 :76404`, `_cbff70 :76381` |
| magic vignettes | `_cbd89f :69671` (`$008B :69719`), `_cbd8f9 :69722` (`$008C :69802`) |
| Strago house scene + name menus | `_cbd982 :69814`; `$008D=1 :69854` |
| inn flow | `_cbd73f :69483`; 1500 GP `:69509`; sleep→fire `:69555` → `_cbdcc7 :70419` |
| fire night / Shadow out | `char_party SHADOW,0 :70456`; `$0190/$008E :70634-70635`; `$02F3=0 :70653` |
| burning-house door NPC | `npc_prop.asm:15217-15222` (343 (39,24), `$0508`) → `_cbde30 :70668` |
| Strago joins | `:71790-71801` (`char_party :71794`, `$02E7/$02F7 :71796-71797`) |
| burning house | entry `load_map 351 :71852`; ambush `battle 45 :71993`; flames `battle 31 :72012-72089`; NPC block `npc_prop.asm:15714-15861` |
| FlameEater | `_cbe767 :72095`; party `:72101`; **battle 79 `:72124`**; `$0090 :72129`; shield row `ot6_hud.asm:1718-1719`; water add `ot6_break.asm:472-479` |
| post-fire night / morning | `load_map 349 :72613`; `$0091/$0098 :73000-73001` |
| Shadow departs | `_cbec92 :73010`; `remove_equip SHADOW :73018`; `$0092 :73302` |
| Esper Mtn entrances | world `0 (229,130)→375 (55,31)`; graph §1 segment 5 (short-entrance decode) |
| Mtn save point | `event_trigger.asm:1795` (375 (8,44)); sparkle `NPCProp::_375` (`$0632`) |
| statue scene | `_cbf168 :73807`; `$0096/$0097 :74018-74019` |
| Ultros ③ scene | `_cbefa5 :73495`; **RELM join `:73694-73701`**; **battle 125 `:73702`**; post-party `:73709`; `$0095 :73801`; shield row `ot6_hud.asm:1716-1717` |
| Ultros ③ AI | `ai_script.asm:6267-6355`; `battle_event $16 :6310`; **Tentacle surrender `:6315-6321`** |
| Sketch machinery | `MonsterSketch` row `monster_sketch.asm:313`; `TargetEffect_55` `battle_main.asm:9673-9700`; `CheckSketchHit :9065-9083` |
| massacre chain start | `_cbf2b5 :74063`; `$0099 :75156`; town reload `:75187` |
| Leo swap | `$018A :76337`; `char_prop WEDGE, LEO :76352-76354`; control `:76367` |
| Leo exit fights | `_cc0960 :78041`; **battle 75 `:78048`** (form 445 decode: Guardian — suspect) |
| Kefka duel | Kefka NPC talk `npc_prop.asm:15056` → `_cbfff4 :76452`; VICKS=KEFKA_4 `:76461`; **battle 124 `:76470`**; AI `ai_script.asm:7952-7965` |
| theater battles | `$009B :76598`; battle 105 `:76601` + flyover `:76602-76627`; battle 97 `:76954` (AI `ai_script.asm:8047-8056`) |
| party restore / grave | `:77242-77253`; `load_map 340 {54,19} :77259`; `$009C :77313` |
| area tail / stop line | avail+`norm_lvl` `:77964-77989`; `and_status SHADOW :77990`; `$009D :77992`; **`load_map 0 {249,128} :78007`; `airship_pos {249,127} :78009`** |
| shops | `shop_prop.dat` rows 33/34/35/45; menus `:69475/:69480/:69485/:69540` |
| treasure | `treasure_prop.dat` blocks 343/349/351/372/373/374/375 |
| encounter decode chain | `break-band-vector.md` §1 method; world terrain OR `field/battle.asm:97-147` |
| bank-C4 budget | `fixed_block`s `event_trigger.asm:19-22` / `npc_prop.asm:183-189`; cfg `ff6/cfg/ff6-en.cfg:61-70`; chain `ff6/rom/ff6-en.map:200-208`; free gap + trailing pads measured in `build/ot6.sfc` (SHA1 `49754546…`) |
| the one hardcoded C4 consumer | `tools/tests/battle_runic.lua:39,68` |
