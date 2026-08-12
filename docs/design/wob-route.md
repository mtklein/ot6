# OT6 v0.5–v0.9 — World-of-Balance route plan (Opera → Floating Continent)

## 1. The beat sequence (ordered, zozo_done → WoB finish)

Reconciled against `docs/design/bosses-wob.md` (the master boss doc, which
already specifies every shield count + weakness row) and the FF6 WoB story
order. Boss IDs/shields below are the AUTHORED values from
`ff6/src/battle/ot6.asm` `Ot6ShieldTbl` (all confirmed present).

| release | beat | maps / place | set-piece fights (id · shields · class) | new chars / espers |
|---|---|---|---|---|
| **v0.5** | **A. Opera House** | Jidoor town, Opera House (stage, rafters, catwalks), the Blackjack | **Ultros ②** `$12d` · 6 · slash\|pierce | **Setzer** joins; airship (Blackjack) acquired |
| v0.6 | **B. Vector / Magitek Factory** | Vector town, Magitek Research Facility, minecart rails, Blackjack deck | **Ifrit** `$109`·6·pierce + **Shiva** `$108`·6·slash (tag); **Number 024** `$10a`·7·slash\|pierce; **Number 128** `$10b`·7·pierce + blades `$13f/$140`·3·slash; **L/R Cranes** `$10d/$10e`·6·pierce | **Ifrit + Shiva** magicite; **Terra** returns (available, not active) at the beat's tail |
| v0.7 | **C. Sealed Gate / Banquet** | Cave to the Sealed Gate, rope bridge, Vector (Emperor's banquet Q&A) | *(no conventional boss — the gate/deck battles 121/122/123 are scripted set pieces; Ultros ③ `$12e` belongs to v0.8's Esper Mountain, its battle's only call site being the Relm-joining scene)* | *(no new magicite — the six tube-room stones are owned since v0.6; the "Maduin at the Gate" idea was a `magicite.md` proposal, not shipped state)* |
| v0.8 | **D. Thamasa** | Thamasa town, the burning house | **FlameEater** `$116`·7·pierce + Balloons `$de`·1 | **Strago, Relm** join; no new magicite — the massacre scene's stones are story objects, and the tube-room six are owned since v0.6 |
| v0.9 | **E. FC approach** | Blackjack deck, IAF shmup gauntlet | **Ultros ④** `$168`·7·slash\|pierce + **Chupon** `$12f`·4·bludg (Sneeze); **AirForce** `$113`·8·pierce + LaserGun/MissileBay `$145/$147`·3 + Speck `$146`·1·any | — |
| v0.9 | **F. Floating Continent** | the FC surface, the escape | **AtmaWeapon** `$117`·**11**·slash\|pierce; **Nerapa** `$118`·5·slash\|pierce (blocks the escape) | Shadow forced; WoB ends → WoR (out of scope) |

Set-pieces that draw **no gauge** (scripted scenes, `Ot6ShieldTbl` `0,$00`):
**Guardian** (`$0111/$0112`, invincible in Vector), **Tritoch** (`$0114/$0115/$0144`).
The HUD shows no gauge for these.

v0.7 ends at the stable Thamasa mission handoff; v0.8 ends after the Thamasa
arc; v0.9 finishes when the FC-escape fixture is generated (post-Nerapa,
entering WoR).

Terra becomes selectable at `event_main.asm:25542`, `switch $02F0=1`; `$02F0`
is bit 0 of `$1EDE`, the engine's available-characters word (`EventCmd_e1` =
`set_case AVAIL_CHARS` does `ldx $1ede` / `stx $1eb4`,
`field/event.asm:4443-4448`; cross-checked against `$02F9`=Setzer and
`$02F6`=Celes). The "recovers her will" dialogue (`$05D4`, `:25488`) is 54
lines earlier in the same uninterruptible tail, so it is part of the same beat.

The v0.6 chain's party, read from `$1850` at every set-piece entry point: four
through the Facility, three once Celes is taken by the tube room.

| entry points | measured party |
|---|---|
| `vector_entry` … `magicite_ifrit_shiva` | LOCKE L14, EDGAR L15, SABIN L15, CELES L14 |
| `n024_entry` … `esper_tubes_entry` | LOCKE L15, EDGAR L16, SABIN L15, CELES L15 |
| `esper_tubes`, `minecart_entry` | LOCKE, EDGAR, SABIN — Celes taken by the tube room |
| `n128_won` | LOCKE L15, EDGAR L16, SABIN L16 |

The canonical fixture party is LOCKE, CELES, SABIN, EDGAR, seated at the Zozo
`party_menu`. `gen_vector_entry` asserts the *count* of nonzero `$1850`
entries at the checkpoint is 4, so a chain that loses members fails that
assertion.

At the v0.6 stop line (map 6, `_cacb95` at `:25669`) Terra is **available but not
active**.

---

## 2. The fixture-authoring pattern (what a route agent does per beat)

The pattern used by `gen_zozo2_arrival`→`gen_zozo5_ramuh` and the
`Makefile`'s `SAVESTATES` machinery.

### The route plays casual

Owner, 2026-08-12: "we're trying to test a normal playthrough, not a speed
run. do try to approach things as if a player trying to learn and enjoy the
game." And, naming the audience: "i believe speed runners call these people
*casual*. that's our target audience, the casual."

That word is the standard, and it is a usable one: when a routing choice is
open, the question is what a casual player would do, not what the shortest
correct path is. They are exploring, they do not know what is coming, and
they are playing to enjoy it.

This is the frame for every routing decision, and the route had drifted a
long way from it. Nobody chose that; it came from each segment taking the
locally safe option — flee this encounter, skip that detour, buy the
cheapest thing that works — and the cost only ever showing up somewhere
else. What the route currently does is closer to a speed run by a player
who already knows every answer, and it measures a game nobody is playing.

Concretely, a normal player:

- **Opens the chests — almost all of them.** Owner, 2026-08-12: "human
  players love to open chests to find out what's inside. a typical run will
  open almost every chest you see." So opening is the default and skipping
  one needs a reason, not the other way round. This is not tidiness: a
  Thunder Rod sits in a chest in the South Figaro cave, one room before the
  TunnelArmr fight that blocked the v0.10 release check by losing three
  attempts. A route that skips content reaches a fight the designers
  expected it to reach armed, loses, and reports a balance finding.
  **Measured 2026-08-12: the route opens none of them.** At least 94 chests
  sit on maps the chain reaches and every one of the 512 treasure bits at
  `$1E40` is clear in all 98 savestates and all 12 tracked SRAM
  checkpoints. `tools/audit_chests.py` prints the list, by map, with what
  is in each; `tools/chests_opened.txt` is the grow-only record of the ones
  the route does open, and is empty.
- **Fights things.** Fleeing earns nothing, which is why the Sabin scenario
  reaches the ghost merchant about 9,000 gil poorer than the old lineage.
  Grinding a little for experience or money is expected, not a last resort.
- **Buys what the next stretch needs**, including things that prevent a
  problem rather than curing it: three Star Pendants at South Figaro make
  Mt Kolts' poison a non-issue, where the route instead buys Antidotes and
  then walks a poisoned character down to 1 HP.
- **Arrives with a margin.** A party that clears a fight with nothing to
  spare is a party that a slightly worse roll defeats, and the balance
  reading taken from it is of a fight harder than the one a player meets.

This matters beyond tidiness: **every balance observation this project has
recorded was taken by an under-prepared party.** That does not make them
wrong about what they measured, but it does mean a fight called too hard
should be re-read against what a normal player would bring before it is
called that.

Two limits. This is not licence to make a losing fight pass: a retry ladder
still gets three attempts, and a fight lost three times is a finding, not a
reason to grind until it is not. And everything here is real play through
the drivers, so it costs generation time — say what a step is for and what
it earned.

### The chain shape (entry point → drive → generate)
Each beat is one (or a few) `gen_<beat>.lua` generators. A generator:
1. `H.loadState(".../build/states/<previous>.mss.lua")` — boots the prior link.
2. Asserts the boot invariants (map id, key switches) up front.
3. Drives the segment with the field/nav macros (below).
4. `H.saveState("<name>.mss")` at each reusable checkpoint, with `H.assertEq`
   guards on the switches/coords that define that checkpoint.

Split a long segment into multiple savestates so a failed experiment replays
only a few seconds instead of the whole segment (e.g. `dadaluma_entry` then
`dadaluma_won` on the same tile; `sabin_world`+`sabin_camp` from one script). Convention:
generate a `<boss>_entry` one A-press before the fight, then `<boss>_won`
after.

### The driving toolkit (`tools/tests/lib/ot6.lua` + `ot6_field.lua`)
- **Field nav:** `H.navTo(x,y,{maxFrames})` (BFS+drive to a tile),
  `H.fieldX/Y`, `H.hasControl`, `H.tileAligned`, `H.dialogWaiting`,
  `H.canStep`, `H.movePress`, `H.bfsPath`.
- **World nav:** `H.worldNavTo(x,y)`, `H.worldBfs`, `H.route(steps)` (the
  field↔world handoff driver), `H.worldMode/worldX/Y`.
- **Cutscene riders (the reusable idioms, all in gen_zozo5_ramuh):**
  - `talk(sx,sy,dir,what)` — navTo, face, clean edge-A until a dialog answers.
  - `bumpTake(sx,sy,dir,what)` — walk INTO a collision-activated object.
  - `rideScene(pred,maxFrames,what)` rides a scripted cutscene, edge-tapping A
    through dialog and stall-tapping flag-less
    `TEXT_ONLY` pages. It gates its stall counter on `hasControl()`, not
    `eventRunning()`, because `TEXT_ONLY` pages park the event PC in a
    `$80xxxx` WRAM mirror that `eventRunning()` misreads as "no event." This
    is required for every long cutscene.
  - `killBitAll()` — clears a stray random encounter mid-drive (Zozo's porch
    rolled them; Vector/factory maps will too).
- **Choice-dialog puzzles:** `gen_zozo3_clock.lua` is the template — chained
  choice dialogs each verified by their own `$01F*` latch (the clock's
  6:10:50).
- **Monster-dead-flag boss win:** boss fights whose post-battle event gates on
  battle-switch (`$40`) are won by setting the monster-dead flag (write
  `$3eec+slot*2 |= $80` when `$3aa8+slot*2` is odd) — no real combat needed to
  generate the `_won` state. Verify each post-battle gate.

### The Makefile wiring (per new link)
Add, in order: (1) a `.word`-style dependency+recipe
`build/states/<name>.mss.lua: build/states/<prev>.mss.lua` / `$(call
generate,<name>,gen_<beat>)`; (2) `<name>` onto a `SAVESTATES +=` line. The
dependency-include check auto-derives generator/lib freshness from the `$(call
generate,...)` line, so a new link is checked the moment it is added.
`make savestates` generates the chain; `make -jN savestates` parallelizes independent
branches.

### The test wiring (per beat)
- A `battle_<boss>.lua` with first-line marker `-- @suite savestate=<boss>_entry`
  boots the entry point, drives into the fight, and asserts the gauge is
  **authored** (shield count ≠ formula), the **element add is live**, and the
  intended **chips break it** with a negative control — see `battle_vargas.lua`
  as the canonical example. `suite.sh` auto-discovers it and reports "skipped"
  until the fixture exists.
- Balance measurement: `bal_party.lua` boots a fixture, runs the `boost3`
  policy (bank BP→3, spend, use the weakness once), and sweeps synthetic arms
  via env (`BAL_BUFF_SHIELDS`, `BAL_BUFF_HP`, `BAL_BUFF_CLASS`), reporting
  `won / char_dmg_taken / player_actions_broken / break-lands-at%`. This is the
  Kolts/Zozo **author-then-measure** loop (Measurements #5–#9,
  `docs/design/balance-metrics.md`).

---

## 3. Blockers & hazards (clear/plan before routing)

### Per-beat driving hazards (ranked)
1. **Chupon's Sneeze (Beat E).** Scripted: it ejects a party member mid-fight,
   with no saving throw and no way to prevent it. The `ultros4_chupon` fixture
   driver must keep working after a party member leaves, and the fight cannot be
   won, only survived. Generate the `_won` (survived) state accordingly.
2. **Nav-hard segments (crane-maze class).** The **crane escape** and the **IAF
   shmup** gauntlet are directed, scripted routes rather than free BFS. Follow
   the `gen_zozo4_dadaluma` (directed island graph, follow-the-conveyor) and
   `gen_sabin_train` (reused car interiors, scripted levers) precedents.
3. **Nerapa's timers (Beat F).** Nerapa casts `Condemned` on the whole party
   before the first input, with no telegraph, and the FC escape clock is running
   as well. The driver must win before the countdown ends. The full Nerapa
   script is on the M6 audit list, open question #6 in `bosses-wob.md`; decode it before authoring.

### Scenario / party constraints (issue #6 principle)
Every enemy must be breakable **by the party that can face it**: fixed
parties exactly, free-choice parties by at least one buildable pick. The forced
and constrained parties are:
- Ultros ③: **Terra + 3**.
- FlameEater: **Terra, Locke, Strago** (Shadow outside) — fixed trio.
- Ultros④+Chupon / AirForce: **your chosen three**.
- AtmaWeapon / Nerapa: **your three + Shadow forced**.
Confirm each forced member can hit each boss's authored class row
(slash/pierce dominate; Chupon needs bludg). Cross-check weapon classes in
`ff6/src/battle/ot6_class.asm`.

---

## 4. The fights — break-authoring (#6) & balance status

### Break data status
`Ot6ShieldTbl` is authored end to end through Nerapa. Every remaining boss
and its parts already have a shield+class row (`Ot6ShieldTbl`,
`ff6/src/battle/ot6_hud.asm:1676–2155`). The class rows make every boss
class-breakable now; the data is unused until fixtures exist to measure it.

### Telegraph / vanilla-script work (bosses-wob.md open question #6, M6 data entry)
The "one telegraph per boss, break-cancels-the-fuse" contract needs the vanilla
scripts decoded for several fights. This is work that has to be done:
- The Cranes do not use a contract fuse. Their charge is element-driven
  (`if_element FIRE/LIGHTNING` → Fire 3 / Giga Volt) plus a separate
  `if_battle_timer 60` → Magnitude8. bosses-wob §16 retracts the "OT6
  inherits it verbatim" claim: giving the Cranes a break-cancelable telegraph
  requires new code.
- Still to decode: Number 128's Gale Cut sweep, Crane element sides, Nerapa's full
  script, AirForce's Launcher, Telstar's reinforcement call (audit list).

### Balance (author-then-measure, per beat)
Shield counts in `bosses-wob.md` are a **v1 proposal**; the trash rows were
swept live (Measurements #8–#9). For each boss: after generating its
`_entry`, run `bal_party.lua` (`boost3`, `BAL_BUFF_SHIELDS` sweep) to confirm
the break lands while the enemy is still alive (the recurring finding is that the
formula or first-draft count is often one chip too many). Tune `Ot6ShieldTbl` and
re-measure. AtmaWeapon needs particular attention: 11 shields is 2–3 break
cycles, so measure the pacing.

### Notable fights, one line each
- **AtmaWeapon:** the last major WoB fight: 11 shields, wide added row, forced Shadow.
- **Nerapa:** an intentionally short 5-shield fight under Condemned + escape timer.

---

## Appendix — key files

- Endpoint gen + reusable cutscene idioms: `tools/tests/gen_zozo5_ramuh.lua`
- Directed-maze precedent: `tools/tests/gen_zozo4_dadaluma.lua`
- Choice-dialog puzzle precedent: `tools/tests/gen_zozo3_clock.lua`
- On-rails precedent: `tools/tests/gen_sabin_train.lua`
- Boss-break test template: `tools/tests/battle_vargas.lua`
- Balance harness: `tools/tests/bal_party.lua`; `docs/design/balance-metrics.md`
- Break data (author here): `ff6/src/battle/ot6.asm` — `Ot6ShieldTbl` (4491),
  `Ot6ElemAddTbl` (384)
- Master boss design: `docs/design/bosses-wob.md`
- Esper roster (v0.6: Ifrit/Shiva/Maduin…): `docs/design/magicite.md`
- Savestate machinery: `Makefile` (`SAVESTATES` lists; `generate`/`stackseed` macros)
- Opera event source: `ff6/src/event/event_main.asm` ~22308–28700
- World/vehicle nav: `docs/research/world-map-nav.md`; `tools/tests/lib/ot6_field.lua`
