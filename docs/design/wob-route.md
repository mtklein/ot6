# OT6 v0.5 — World-of-Balance route plan (Opera → Floating Continent)

Scope: continue the fixture route chain from the v0.4 endpoint (`zozo_done`)
to the END of the World of Balance. READ-and-PLAN survey; no source touched.
All line/address references were read from the repo on 2026-07-22.

---

## 0. The current endpoint (where v0.5 picks up)

**Tail state: `build/states/zozo_done.mss`** — minted by `gen_zozo5_ramuh.lua`,
the last link in `Makefile`'s FRONTIER chain (`FRONTIER += ... zozo_done`).

State at that fixture (asserted in the generator's tail):
- **Map 221** (Zozo street), party parked at **(57,45)** facing RIGHT.
- `$0054=1` — v0.4's stop-line switch. `$0053=1` (Ramuh scene ran).
- **Four espers owned**: Ramuh (`$36`), Siren (`$39`), Kirin (`$47`),
  Stray (`$3e`) — bitfield `$1A69`. All four field stones cleared.
- **Terra retrieved but catatonic — she does NOT rejoin the active party.**
- Active roster (from gen comments; the search party was
  `LOCKE+CELES+EDGAR+SABIN`, gather doubles `CYAN/GAU`, forced menu
  `{LOCKE,CELES}`): **Locke, Celes, Edgar, Sabin, Cyan, Gau** active;
  **Terra inactive/catatonic**; **Shadow** is a drift-in/out wanderer.
  *(MARK UNCERTAIN — confirm the exact active/available set with a party
  read off `zozo_done.mss` before authoring Beat A; roster gates every
  "who can break this" call below.)*

The story picks up: leave Zozo → **Jidoor → the Opera House** (the party
needs an airship; the Impresario's Setzer problem is the way to one).

---

## 1. The beat sequence ahead (ordered, zozo_done → WoB finish)

Reconciled against `docs/design/bosses-wob.md` (the master boss doc, which
already specifies every shield count + weakness row) and the FF6 WoB story
order. Boss IDs/shields below are the AUTHORED values from
`ff6/src/battle/ot6.asm` `Ot6ShieldTbl` (all confirmed present).

| beat | maps / place | set-piece fights (id · shields · class) | new chars / espers |
|---|---|---|---|
| **A. Opera House** | Jidoor town, Opera House (stage, rafters, catwalks), the Blackjack | **Ultros ②** `$12d` · 6 · slash\|pierce | **Setzer** joins; airship (Blackjack) acquired |
| **B. Vector / Magitek Factory** | Vector town, Magitek Research Facility, minecart rails, Blackjack deck | **Ifrit** `$109`·6·pierce + **Shiva** `$108`·6·slash (tag); **Number 024** `$10a`·7·slash\|pierce; **Number 128** `$10b`·7·pierce + blades `$13f/$140`·3·slash; **L/R Cranes** `$10d/$10e`·6·pierce | **Ifrit + Shiva** magicite |
| **C. Banquet / Sealed Gate** | Vector (Emperor's banquet Q&A), Cave to the Sealed Gate, rope bridge | **Ultros ③** `$12e`·7·slash\|pierce | Terra recovers her will; (Maduin at/after the Gate — magicite.md) |
| **D. Thamasa** | Thamasa town, the burning house | **FlameEater** `$116`·7·pierce + Balloons `$de`·1 | **Strago, Relm** join; Kefka's massacre scene → magicite |
| **E. FC approach** | Blackjack deck, IAF shmup gauntlet | **Ultros ④** `$168`·7·slash\|pierce + **Chupon** `$12f`·4·bludg (Sneeze); **AirForce** `$113`·8·pierce + LaserGun/MissileBay `$145/$147`·3 + Speck `$146`·1·any | — |
| **F. Floating Continent** | the FC surface, the escape | **AtmaWeapon** `$117`·**11**·slash\|pierce; **Nerapa** `$118`·5·slash\|pierce (escape doorman) | Shadow forced; WoB ends → WoR (out of scope) |

Set-pieces that draw **no gauge** (scripted theater, `Ot6ShieldTbl` `0,$00`):
**Guardian** (`$0111/$0112`, invincible in Vector), **Tritoch** (`$0114/$0115/$0144`).
Their silent HUD is the tell.

v0.5 finishes when the FC-escape fixture mints (post-Nerapa, entering WoR).

---

## 2. The fixture-authoring pattern (what a route agent does per beat)

The house pattern, learned from `gen_zozo2_arrival`→`gen_zozo5_ramuh` and the
`Makefile` frontier machinery.

### The chain shape (doorstep → drive → mint)
Each beat is one (or a few) `gen_<beat>.lua` generators. A generator:
1. `H.loadState(".../build/states/<previous>.mss.lua")` — boots the prior link.
2. Asserts the boot invariants (map id, key switches) up front.
3. Drives the segment with the field/nav macros (below).
4. `H.saveState("<name>.mss")` at each reusable checkpoint, with `H.assertEq`
   guards on the switches/coords that define that checkpoint.

Split a long leg into multiple mints so a failed experiment replays seconds,
not the whole leg (e.g. `dadaluma_doorstep` then `dadaluma_won` on the same
tile; `sabin_world`+`sabin_camp` from one script). Convention: mint a
`<boss>_doorstep` one A-press before the fight, then `<boss>_won` after.

### The driving toolkit (`tools/tests/lib/ot6.lua` + `ot6_field.lua`)
- **Field nav:** `H.navTo(x,y,{maxFrames})` (BFS+drive to a tile),
  `H.fieldX/Y`, `H.hasControl`, `H.tileAligned`, `H.dialogWaiting`,
  `H.canStep`, `H.movePress`, `H.bfsPath`.
- **World nav:** `H.worldNavTo(x,y)`, `H.worldBfs`, `H.route(legs)` (the
  field↔world handoff driver), `H.worldMode/worldX/Y`.
- **Cutscene riders (the reusable idioms, all in gen_zozo5_ramuh):**
  - `talk(sx,sy,dir,what)` — navTo, face, clean edge-A until a dialog answers.
  - `bumpTake(sx,sy,dir,what)` — walk INTO a collision-activated object.
  - `rideScene(pred,maxFrames,what)` — **the key one.** Rides a scripted
    cutscene, edge-tapping A through dialog and stall-tapping flag-less
    `TEXT_ONLY` pages. **Gates its stall counter on `hasControl()`, NOT
    `eventRunning()`** — because `TEXT_ONLY` pages park the event PC in a
    `$80xxxx` WRAM mirror that `eventRunning()` misreads as "no event." This
    is issue #3's fix and is REQUIRED for every v0.5 cutscene.
  - `killBitAll()` — clears a stray random encounter mid-drive (Zozo's porch
    rolled them; Vector/factory maps will too).
- **Choice-dialog puzzles:** `gen_zozo3_clock.lua` is the template — chained
  choice dialogs each verified by their own `$01F*` latch (the clock's
  6:10:50). The **Opera lyric minigame and the banquet Q&A are this shape.**
- **Kill-bit boss win:** boss fights whose post-battle event gates on
  battle-switch (`$40`) are won by the kill-bit idiom (write `$3eec+slot*2 |=
  $80` when `$3aa8+slot*2` is odd) — no real combat needed to mint the `_won`
  state (Vargas/Kefka/Dadaluma all do this; Ultros/factory bosses should too,
  verify each post-battle gate).

### The Makefile wiring (per new link)
Add, in order: (1) a `.word`-style dependency+recipe
`build/states/<name>.mss.lua: build/states/<prev>.mss.lua` / `$(call
mint,<name>,gen_<beat>)`; (2) `<name>` onto a `FRONTIER +=` line. The
`frontier_deps.sh` gate auto-derives generator/lib freshness from the `$(call
mint,...)` line (issue #2 fix), so a new link is gated the moment it is added.
`make frontier` mints the chain; `make -jN frontier` parallelizes independent
branches.

### The test wiring (per beat)
- A `battle_<boss>.lua` with first-line marker `-- @suite frontier=<boss>_doorstep`
  boots the doorstep, drives into the fight, and asserts the gauge is
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

### Cleared / good news
- **Issue #3 (esper-scene walker stall) — CLOSED.** The `rideScene`/
  `hasControl()` fix is live in `gen_zozo5_ramuh.lua`. This is the single most
  important reusable technique for v0.5, which is **cutscene-dense**: the Opera
  performance, the Emperor's banquet, Terra's recovery, the Kefka/Leo massacre,
  the esper-burst at the Sealed Gate, and the AtmaWeapon speech are all long
  `TEXT_ONLY` choreographies. Reuse `rideScene` verbatim; do NOT reintroduce an
  `eventRunning`-gated stall counter.

### Per-beat driving hazards (ranked)
1. **The Opera performance (Beat A) — the headline hazard.** Three custom-drive
   problems stacked (`event_main.asm` ~27380–28700):
   - the **lyric-choice minigame** ("You have 2 more chances / 1 more chance",
     :27701–:27712) — a chained choice dialog under a music-sync timer; drive it
     like the clock puzzle (`gen_zozo3_clock`) but choice-correct, not latch-any.
   - the **timed rafter chase / 4-ton weight** — a step-or-time-limited walk to
     intercept Ultros, with a **stage-master switch** ("press the far right
     switch", :27819). Time pressure + nav; no prior fixture has a *timed* walk.
   - then **Ultros ②**. Build a dedicated `gen_opera_*` driver; budget the most
     time here of any v0.5 beat.
2. **Flying-vehicle world nav (Beats A→F).** From the Opera on, the party has
   the **Blackjack airship**. `world-map-nav.md` documents the vehicle flags
   (`$11FA&3`==0 on foot; airship force-check `$11F3`), but `H.worldNavTo` was
   built and proven for **on-foot BFS only**. Flying nav should be *easier*
   (airship overflies all terrain → near-empty BFS), but mount/takeoff/landing
   are event-driven. **VERIFY/EXTEND `worldNavTo` for the airship before Beat B**
   (Vector is reached by air). MARK: possibly a small lib addition.
3. **Chupon's Sneeze (Beat E).** Scripted: ejects a party member mid-fight, "no
   save, no appeal" — the `ultros4_chupon` fixture driver must **survive a party
   member leaving** and the fight "cannot be won, only survived." Mint the `_won`
   (survived) state accordingly.
4. **Nav-hard segments (crane-maze class).** The **Magitek Research Facility**
   conveyor rooms, the **minecart rails** (on-rails, like the Phantom Train
   `gen_sabin_train`), the **crane escape**, and the **IAF shmup** gauntlet. Each
   is a directed/scripted route, not free BFS — follow the `gen_zozo4_dadaluma`
   (directed island graph, follow-the-conveyor) and `gen_sabin_train` (reused
   car interiors, scripted levers) precedents.
5. **Nerapa's timers (Beat F).** `Condemned` on the whole party before first
   input (untelegraphed ambush) **plus** the FC escape clock. Sprint fight; the
   driver must win before the countdown. (Full Nerapa script is on the M6 audit
   list, open question #7 — decode before authoring.)
6. **Codex/reveal continuity (Ultros recurring).** bosses-wob relies on "Ultros
   keeps one weakness row, revealed at the Lete, remembered forever." On a fresh
   v0.5 chain booted from `zozo_done`, verify the codex carries the reveal; if
   not, first hit shows `?` (still breakable — the row is authored). Minor.

### Scenario / party constraints (issue #6 principle)
Every enemy must be breakable **by the party that can actually face it** — fixed
parties exactly, free-choice parties by *some* buildable pick. v0.5's forced/
constrained parties:
- Opera Ultros ②: **Locke + 3** (Celes mid-aria; Terra catatonic) — *chosen*.
- MRF (Ifrit/Shiva/024): **Locke, Celes + 2** — Locke+Celes effectively fixed.
- Number 128 / Cranes: **the factory four** (fixed set).
- Ultros ③: **Terra + 3**.
- FlameEater: **Terra, Locke, Strago** (Shadow outside) — fixed trio.
- Ultros④+Chupon / AirForce: **your chosen three**.
- AtmaWeapon / Nerapa: **your three + Shadow forced**.
Confirm each forced member holds a key to each boss's authored class row
(slash/pierce dominate; Chupon needs bludg, Shiva needs slash, Ifrit needs
pierce). Cross-check weapon classes in `ff6/src/battle/ot6_class.asm`.

### Open bugs that touch routed parties
- **Issue #5 (OPEN, bug):** Cyan's boost→SwdTech mapping makes learned techs
  unreachable — if Cyan is routed into any v0.5 party, his kit is degraded.
- **Issue #6 (OPEN):** the formula-floor long tail (un-authored trash is
  *unbreakable*, not just un-weak) — bosses are class-breakable already, so this
  gates the *tuning/coverage* pass, not the route itself.

---

## 4. The fights — break-authoring (#6) & balance status

### Break DATA status: shields/classes DONE, one element gap
- **`Ot6ShieldTbl` is authored end-to-end through Nerapa.** Every v0.5 boss AND
  its parts already have a shield+class row (table verified,
  `ot6.asm:4491–4813`). The class rows make every boss **class-breakable today**;
  the data is *inert*, waiting on fixtures to measure.
- **`Ot6ElemAddTbl` stops at v0.4's search corridor (`ot6.asm:384–479`).** The
  v0.5 boss element weaknesses are mostly **vanilla** (Ultros fire/bolt; Ifrit
  fire-absorb / ice-weak, Shiva fire-weak; Cranes water + bolt; Number 128
  bolt/water; FlameEater ice/water; Nerapa ice/bolt/holy, absorbs fire — all
  decoded vanilla per bosses-wob). **The one clear authoring gap:
  AtmaWeapon's `$0117` fire/ice/bolt row is an ADD ("the whole row is added",
  bosses-wob §21 + open question #4) and is NOT in `Ot6ElemAddTbl` yet.** Author
  it during Beat F. (Atma is still slash/pierce-breakable without it; the element
  row is the intended wide capstone.)

### Telegraph / vanilla-script work (open question #7, M6 data entry)
The "one telegraph per boss, break-cancels-the-fuse" contract needs the vanilla
scripts decoded for several v0.5 fights. **Flagged as real work, not free:**
- **The Cranes are NOT a contract-fuse** — their charge is *element-driven*
  (`if_element FIRE/LIGHTNING` → Fire 3 / Giga Volt) plus a separate
  `if_battle_timer 60` → Magnitude8. bosses-wob §16 explicitly retracts the "OT6
  inherits it verbatim" claim: **giving the Cranes a break-cancelable telegraph is
  new machinery to build.**
- Still to decode: Number 128's Gale Cut sweep, Crane element sides, Nerapa's full
  script, AirForce's Launcher, Telstar's reinforcement call (audit list).

### Balance (author-then-measure, per beat)
Shield counts in `bosses-wob.md` are a **v1 proposal**; the trash rows were
swept live (Measurements #8–#9). For each v0.5 boss: after minting its
`_doorstep`, run `bal_party.lua` (`boost3`, `BAL_BUFF_SHIELDS` sweep) to confirm
the break **lands on a live body, not a corpse** (the recurring finding: the
formula/first-draft count is often one chip too many). Tune `Ot6ShieldTbl` and
re-measure. Notable bodies to watch: AtmaWeapon (11 shields = 2–3 break cycles —
measure the rhythm), the Cranes (effective-12 dual gauge), Number 024
(WallChange re-hides the element row — classes stay the handhold).

### Notable fights, one line each
- **Ultros ② (Opera):** codex row, 6 shields, no Banon healer — "same fight,
  honest difficulty." Chosen party; AutoCrossbow (pierce) trivially chips.
- **Ifrit & Shiva (MRF):** tag fight; a **Broken sibling can't tag out** (Stop
  rules — confirm, open question #2). First hard **absorb lesson** (feed Ifrit
  fire, he heals). Celes chips both (Ice→Ifrit, sword→Shiva).
- **Number 024:** the anti-codex boss — WallChange rerolls the element wall and
  **re-hides the row**; classes (slash|pierce) are the fixed handhold.
- **Number 128 / Cranes:** the sub-job debut — **Ramuh's bolt** into the bolt-weak
  bodies (magicite.md's storm-lancer). Part-breaks (blades) as the cancel.
- **AtmaWeapon:** the WoB final exam — 11 shields, wide added row, forced Shadow.
  Author the fire/ice/bolt add here.
- **Nerapa:** deliberate 5-shield coda under Condemned + escape timer.

---

## 5. FIRST beat to author + its doorstep

**FIRST BEAT: Beat A — Jidoor → the Opera House → Ultros ② → the Blackjack.**

**Starting doorstep state: `build/states/zozo_done.mss` (the confirmed v0.4
tail).** No new blocker gates starting — issue #3 (the walker stall) is already
closed, and its `rideScene` fix is the exact tool the Opera cutscene needs.

Suggested sub-fixtures for Beat A (mirroring the zozo_* leg's granularity):
1. `gen_opera1_*` → **`opera_doorstep`** — leave Zozo (map 221 (57,45)) → world
   map → **Jidoor** → the Opera House, parked at the Impresario one A-press from
   the performance trigger. *(Requires flying-vehicle world nav IF the party
   already has no walking route — verify: at `zozo_done` the party is likely
   still on foot, so Jidoor is a walk; the airship comes AFTER the Opera. Confirm
   traversal mode.)*
2. `gen_opera2_*` → **`opera_performance_done`** — ride the lyric minigame +
   timed rafter chase (`rideScene` + clock-style choice driver + timed-walk).
3. `gen_opera3_*` → **`ultros2_doorstep`** / **`ultros2_won`** — the fight
   (kill-bit win if its post-battle event gates on `$40`; verify).
4. `gen_opera4_*` → **`blackjack`** — the Setzer confrontation, **Setzer joins,
   airship acquired** — the Vector leg's boot state.

Before/alongside Beat A:
- Write `battle_ultros2.lua` (`@suite frontier=ultros2_doorstep`) asserting the
  authored 6/slash|pierce gauge and the codex row.
- Confirm the `zozo_done` active roster with a party read (§0 uncertainty).
- Prototype/verify `worldNavTo` for the airship before Beat B (Vector by air).

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
- Esper roster (v0.5: Ifrit/Shiva/Maduin…): `docs/design/magicite.md`
- Frontier/mint machinery: `Makefile` (FRONTIER lists; `mint`/`stackseed` macros)
- Opera event source: `ff6/src/event/event_main.asm` ~22308–28700
- World/vehicle nav: `docs/research/world-map-nav.md`; `tools/tests/lib/ot6_field.lua`

## Beat A — measured corrections (2026-07-22, from authoring)

Corrections to the scoping assumptions, measured while authoring the Opera:

- **Roster at `zozo_done` is LOCKE + CELES only** (measured `$1850`: LOCKE=$C1, CELES=$51, rest $00) — the Zozo leave-cutscene forces `party_menu {LOCKE,CELES}`, not the six the scoping guessed. Gates every "who can break this" call for Beats A–B.
- **The opera OPENS via a Jidoor cutscene, not the opera house.** Talk impresario `_ca9337` on **map 209**, reached from **Jidoor (map 198) north bump-door (16,13→16,12)**: Maria/Celes resemblance → letter (`$0331`) → Setzer intro + `name_menu` → `$0340=1`. The opera-house impresario (map 237, `_caae15`) is hidden behind `$0340` until then.
- **The aria is a choice puzzle (clockPick-class), not a timed walk.** Stage trigger `_cabafd` (map 238, 97,7), three lyric forks; correct sequence **{0,1,0}** → `$0111=1`.
- **Ultros ② = battle 134, `$012d`, 6 shields, slash|pierce** (`Ot6ShieldTbl`, ot6.asm:4757).
- **Geography:** Zozo exit column x=63 → world (23,92); Jidoor = world (27,130)→map 198; opera house = world (45,154)→map 237.

**Fixtures banked (gated):** `opera_doorstep` (map 209 Jidoor impresario), `opera_open` (map 237, `$0340=1`).

**Remaining in Beat A** (boot `opera_open`): the intro drives to **map 234 backstage (16,46), `$0055=1`**; then aria nav (234 → stage door → map 238 trigger, gated `$0056=1`) → {0,1,0} → the **rafter chase** (catwalk maze 233→231→239→232 + `$0355` + likely timer) → **Ultros ②** kill-bit (`ultros2_won`) → Setzer + Blackjack (`setzer_joined`).

## Beat A — second pass: legs 3–4 banked, flower-dance blocker (2026-07-22)

Two more legs banked as gated FRONTIER links, the aria forks solved, and the
aria's post-fork **flower dance** hit as the blocker. Everything below is
measured (probes `probe_opera_aria`/`_route`/`_stage`/`_ariafire`/`_aria3`/
`_dance*`/`_objscan`, all committed).

**Fixtures banked (gated):**
- **`opera_backstage`** (`gen_opera3_backstage`) — `opera_open` → talk the
  IMPRESARIO (`_caae15`) → RIDE the performance intro → controllable on **map
  234 (the THEATER SEATING), {16,46} facing DOWN, `$0055=1`**. The intro is
  *not* ~14,400 frames (survey guess): it settles to control near frame ~6k;
  the ride terminates on 30 straight `settled()` frames on a non-237 map.
- **`opera_stage`** (`gen_opera4_stage`) — backstage → **Route A** onto the
  stage: **map 238 {99,20}, `$0056=1`** (aria ARMED), one `navTo(97,7)` from
  the aria.

**Door topology (decoded from `short_entrance.dat`, maps 234/237/238):**
- 234 stage doors `{4,24}`→238`{117,14}` and `{28,24}`→238`{114,36}` **both
  land in a 238 BACKSTAGE region (x≥109) that is passability-DISCONNECTED from
  the stage.** The stage is reached via the opera-house interior instead:
- **Route A:** 234`{25,49}`→237`{72,32}` (theater floor exit) → walk RIGHT to
  237`{82,32}`→238`{100,22}` (the stage door) → talk CELES `{99,19}`
  (`obj_event _caba44`→`_cabaa8`, sets `$0056=1`, returns control at `{99,20}`)
  → the aria trigger `_cabafd {97,7}` fires (gate `$0056=1 & $0057=0`).
  237's IMPRESARIO is at `{60,48}`, off the `{72,32}`→`{82,32}` walk, so the
  performance trigger is never re-armed in passing.

**The aria forks — SOLVED.** Step onto 238`{97,7}` → `_cabafd` fades and loads
**map 236 (the castle stage)**. Three chained `choice` dialogs, correct
sequence **{0,1,0}** (fork1 `_cabb3d`(0)/`_cabb35`(1); fork2 `_cabc1d`(0)/
`_cabc25`(1); fork3 `_cabc71`(0)/`_cabc69`(1)). Driven clockPick-style off
`$056e`/`$056f` (see `probe_opera_aria3.lua`); the three correct picks ride the
long music-synced choreography cleanly, no fail, ending with control **as CELES
at map 236 {5,21}**.

**THE BLOCKER — the flower dance (map 236 stairs, under a timer).** After the
forks, `start_timer 0, 2336, _cabd21` runs; on expiry `_cabd21`→fail→`load_map
0` (dumped to the world). Measured grace ≈2287 frames from control-return. To
reach `$0111=1` (aria solved) the party must:
1. Complete the **Draco waltz**: NPC `{12,14}`=DRACO (`_cabd35`, gated `$0300`)
   → touch him 3× to set `$01F0`→`$01F1`→`$01F2` (`_cabd5c`/`_cabd6a`/`_cabd7a`),
   he leads/moves each time.
2. Then the **FLOWERS** appear: NPC `{12,19}` (`_cabf27`, gfx FLOWERS) → touch
   → `$0057=1` (it is *not* interactable before the waltz — measured: standing
   on `{12,19}` with A does nothing).
3. Then the **balcony**: step trigger `{8,9}`=`_cabe6d` (gate `if $0057=0
   EventReturn`) → the final verses → **`$0111=1`**, lands 238`{98,7}`.

The obstruction is **map-236 stair navigation**: tiles `03`/`09`/`0B` break the
`canStep`/`bfsPath` model — CELES oscillates in the `(13–14,18–19)` pocket and
cannot climb to Draco `{12,14}`, the flowers `{12,19}`, or the balcony `{8,9}`.
Four driver strategies (manhattan-greedy, adaptive nearest-NPC chase,
flowers-first, x=12 column-climb) all stalled there; `$01F0` set at most once,
never `$01F1`+, and the field-object array (`stride 0x29`, X@`$086a` Y@`$086d`;
CELES=obj#6, play NPCs obj#3`(14,18)`/#7#8#10#12`(13–15,13)`/#9`(8,6)`) shows the
NPCs not visibly moving. **What's needed:** a hand-coded map-236 stair
tile→direction table (the `gen_zozo4_dadaluma` `corridorFollow` precedent),
plus the exact Draco talk-positions/object-id per waltz step, fit inside the
~2336-frame timer. This gates ALL downstream Beat A work (rafters/Ultros②/
Setzer sit past `$0111=1`). `battle_ultros2.lua` stays skipped until
`ultros2_doorstep` exists.

Dev checkpoint (not gated, timer-running): `aria_postfork.mss` — map 236 {5,21}
just after the forks, minted by `probe_opera_postfork.lua` for fast dance
iteration.

## Beat A — third pass: the flower dance is CRACKED ($0111=1, gated)

`gen_opera5_dance.lua` mints **`opera_dance_done`** (FRONTIER-gated, `make test`
green) — map 238 {98,7}, `$0111=1`, the aria SOLVED. Everything below is
measured (probes `probe_opera_geom`/`_occ`/`_dance5`–`_dance8`, all committed).

**The blocker was a Z-SPLIT map, not "stairs break canStep."** Map 236's p1
tile props partition the floor by z-level: **`09` = upper-z only, `02` =
lower-z only, `03`/`0b` = both-z BRIDGE tiles** (stepping OFF a `09` drops the
party to z=1, off a `02` to z=2, off a `03`/`0b` KEEPS z — player.asm `zAfter`).
The lib's `bfsPath` seeds one z and *simulates* `zAfter` along each candidate
path, but the live engine's z diverges across the `09`↔`02`↔`03`↔`0b` joins, so
`bfsPath` returns **no path** from the postfork basin (5,21) to the dance area.
Confirmed by `probe_opera_dance5` (no path to (12,19)/(8,9)/(12,14)). The fix is
`gen_zozo4_dadaluma`'s `corridorFollow` verbatim: **two hand-coded per-tile
direction tables** driven one `canStep`-gated step at a time on the **live z**
(always correct), pulsing the pad so no press outlives its step.

**The record's Draco/flowers coordinates were SWAPPED.** Measured truth:
- **DRACO = obj#19 (=NPC_4=$13) starts AT (12,19)**, OCCUPYING it — that
  occupancy (`$7E2000` bit7 clear, `probe_opera_occ`) is what SEALS the basin
  from the upper region. (12,14) is just open floor above.
- **Stand at (11,19)** (basin edge, reachable) and touch Draco to the RIGHT.
  Each touch runs `_cabd35`/`_cabd5c`/`_cabd6a`: he leads a SLOW step that hops
  him a few tiles around the basin — all uniform `09`, so a **greedy `canStep`
  chase catches him** — and sets `$01F0`→`$01F1`→`$01F2`.
- A **4th touch** runs `_cabd7a`: Draco is hidden, the **FLOWERS (obj#16=NPC_1)
  spawn at (12,19)**. Touch them (`_cabf27`) → `$0057=1`, which moves NPC_1 away
  and **FREES (12,19)** — only now does the climb to the upper region open.
- **Balcony:** climb (12,19)→(12,14) up the x=12 corridor, RIGHT to (14,14), UP
  the `0b` column (14,13/12/11)→(14,10), LEFT along y=10 to (11,10), UP to the
  y=9 strip, LEFT to (8,9). The route **detours right/up AWAY from (8,9)** —
  exactly why the prior manhattan-greedy drivers oscillated. Stepping onto (8,9)
  fires `_cabe6d` (gated `$0057`): it **`stop_timer`s**, then rides the
  wedding-waltz finale (TEXT_ONLY verses → `load_map 233` rafters →
  `load_map 238`) and sets **`$0111=1`** on 238 at (98,7). `rideOpen`
  (gen_opera3's stall-safe A/START rider) carries that untimed tail.

**Timing:** the 2336-frame timer arms as control returns on 236 (~2287 grace);
climb+waltz+flowers+balcony-to-(8,9) measured ~1348 frames — comfortable margin.

**Fixtures banked (gated):** `opera_dance_done` (`gen_opera5_dance`).

**Remaining in Beat A** (boot `opera_dance_done`, map 238 {98,7} `$0111=1`): the
**rafter chase** (Ultros drops in — `_cabf31`/`_cabf3e` dlg $04C8, `$0058=1`;
catwalk maze 233→231→239→232 + `$0355` + a timer → **battle 134 Ultros②**
`$012d`·6·slash|pierce, kill-bit `ultros2_won`) → Setzer + the Blackjack.
`battle_ultros2.lua` stays skipped until `ultros2_doorstep` exists.

## Beat A — fourth pass: rafter chase decoded, sfigaro STEAL fixed (2026-07-23)

The rafter chase is decoded from the vanilla event disassembly
(`ff6/src/event/event_main.asm`, `npc_prop.asm`, `event_trigger.asm`); the
generator + Makefile + probe are wired (`gen_opera6_rafter`, `probe_opera_rafter2`,
`FRONTIER += ultros2_doorstep`). A prerequisite blocker (`sfigaro_town`) was
found and FIXED so the chain to `opera_dance_done` mints again.

### PREREQUISITE FIX — `gen_sfigaro` cider-runner STEAL (`sfigaro_town`)
`make …/opera_dance_done` used to fail at **`sfigaro_town`**: the cafe STEAL never
landed (32 attempts, identical frames, `$3EBD` never moved, timeout), so every
state after it — including all of Beat A — was unreachable. **THREE OT6
corrections fix it** (all measured; `gen_sfigaro`'s `stealDriver`):
1. **STEAL COSTS 2 MP** (`ot6.asm` `Ot6AbilityCost` `@steal`, "flat small"). The
   charge+refusal is universal, so a char below 2 MP has the command REFUSED —
   the menu confirms but no action queues (`TargetEffect_52`'s `$3401`
   `battle_main.asm:9357` never fires). Solo early Locke is under it. **Pin
   battle MP (`$3C08`).** *(This was the decisive missing piece — it looked like
   "the queued action isn't a steal"; it was the MP refusal.)*
2. **STEAL IS A BOOST-TIERED CHANCE VERB** (`ot6.asm` `Ot6StealBoostLevel`, hooked
   `battle_main.asm:9366`): 0 bp = RAW vanilla odds (≈0 for this underleveled
   Locke vs the Merchant), 3 bp = CERTAIN (`@cap`). **Force banked+pending boost
   (`$3e9c`/`$3e9d`, even char offsets 0,2,4,6) to the cap.**
3. **The command cursor does not move on a held d-pad here**, so the old `down`+A
   picked FIGHT. **Poke STEAL (`$05`) into all of the actor's command cells**
   (`CMDTBL $202E`, stride 12/entity, 3/cell — gen_vargas's Blitz-poke idiom).
   Locke's cells measured `00 05 FF 01` = FIGHT / STEAL / — / ITEM; slot 1 of the
   formation is `$13B` b_day_suit (EMPTY steal), so the target must be slot 0
   (the Merchant `$13A`, stealable GUARDIAN/PLUMED_HAT, `monster_items.asm:1900`).

With all three, the steal lands on attempt 1 (`$3401`=1,2,3; `$3EBD` bit4 `$4C`
set; `$0104`=1 clothes, `$01D0`=1 cider); `gen_sfigaro` PASSes and mints
`sfigaro_town` + `sfigaro_passage`. **Anyone else's boost-tiered STEAL driver
needs the same MP-pin + boost + cell-poke trio.**

### THE RAFTER CHASE — decoded from source (verify each leg with a probe)
Boot `opera_dance_done` (238 {98,7} `$0111=1`, `$0345=1`):
1. **Ultros drops in.** ENVELOPE NPC at **238 {99,20}** (`npc_prop.asm:10427`, vis
   gate `$0345`, event `_cabf31`), `set_npc_no_react` → fires on CONTACT. Walk
   into it → `_cabf31` (`:29595`): dlg $04C8/$04C9, `$0345=0`, **`$0058=1`**.
   (`probe_opera_rafter2` drives exactly this; `gen_opera6_rafter` mints the
   `ultros_dropped` checkpoint here.)
2. **Alert the Impresario** (untimed). IMPRESARIO `_cab724` (`:28244`) = NPC
   `$0300` on **MAP 234 {15,46}** (`npc_prop.asm:10077`). Travel 238→237→234
   (reverse of gen_opera4 Route A: 238{100,22}↔237{82,32}, 237{72,32}↔234{25,49}).
   Talk with `$0058=1 & $0110=0` → `_cab744` (`:28266`) → the "5-minutes"
   cutscene → `_cab99b` (`:28677`) loads the rafters and reaches the briefing
   (`:28716`, dlg $04D8 "talk to the man in the room to the far right") which sets
   **`$0110=1`**, `$02BA=1`, `$02BC=1` and **`start_timer 0, 18000, _caba09`**
   (`:28736`). Expiry (`_caba09` `:28738`) = Ultros wins, dump to loss. Party
   lands controllable near **map 231 {15,37}** (`:28688`).
3. **Stage master + framework.** With `$0110=1` the STAGE MASTER (`_cab455`
   `:27803`) opens the way (`_cab45f`) and hints the "far right switch" (`$0355`)
   and "the room to the far left of the stage, then the framework above the
   stage" (`$00A4` gates the hint). Climb into the **catwalk maze 233→231→239→232**
   — Z-SPLIT catwalk maps; expect `bfsPath` to fail across z-joins → hand-coded
   corridor tables (gen_zozo4/gen_opera5 precedent).
4. **The 4-ton weight (map 232).** Four step-triggers at y=27
   (`event_trigger.asm:1033`): **{118,27} `_cab497`** is the WEIGHT DROP
   (`:27840`) — `if ($01B0=1 & $01B4=1)` drop → fall anim → load_map 231 →
   `if_switch $0387=1` → **`_cab6d6` (`:28199`) → `battle 134`** (`:28207`).
   {120,27}`_cab484` = WRONG switch (`$0355=0`), {117,27}`_cab570` = load 239,
   {116,27}`_cab6fb` = BG only. **OPEN: what sets `$01B0`/`$01B4`/`$0387` during
   the chase is not yet decoded** — probe map 232 while walking the switches to
   learn the Ultros-trap mechanic before authoring this leg.
5. **Doorstep.** `battle_ultros2` boots `ultros2_doorstep` and A-mashes into the
   fight, so mint a state whose first uninterrupted advance reaches battle 134 —
   candidate: on 232 about to step {118,27} with `$01B0=$01B4=$0387=1`, or
   mid-`_cab497` (the fall→load→`_cab6d6`→battle tail is dialog-free, auto-plays).
   Post-battle `_cab6d6` tail (`:28208+`): `call _ca5ea9`, `$0332=1`, load 237 →
   Setzer. Verify the post-battle gate before minting `ultros2_won` (kill-bit).

## Beat A — fifth pass: dadaluma crane-maze z-nav (west room CRACKED, bridge-climb blocked) (2026-07-23)

The frontier no longer re-mints cleanly against the current OT6 ROM: a fresh
build of `ff6/rom/ff6-en.sfc` differs from the seeded `build/states` (~4000
bytes), so `sh tools/worktree-setup.sh`'s seed is stale and the whole chain
re-mints. It re-mints correctly THROUGH `zozo_arrival` (sfigaro's steal fix
holds), then **`dadaluma_doorstep` is the first hard blocker** — reproduced,
then partially cracked. Everything below is measured (probes
`probe_westroom.lua`, `probe_bridge.lua`, `probe_climb2.lua`, all committed).

### The pattern: `followPath` HANGS/mis-drives every z-split crane-maze leg
`gen_zozo4_dadaluma`'s `followPath` BFS-seeds ALL FOUR z-levels; on the crane
maze's z-split "beam" tiles the phantom-z first step disagrees with the live
engine, so it oscillates/times out. Three consecutive legs needed hand-coded,
canStep-gated (live-z) per-tile tables (the `corridorFollow`/gen_opera5
precedent). **Two are FIXED; the third is characterised but blocked.**

### FIXED — the WEST ROOM crossing `westRoomCross()` (map 225, (118,26)->(104,27))
The two chambers of the west room connect ONLY through a "\" diagonal beam
(111,15)->(110,14)->(109,13)->(108,12) — a cardinal-only door-walled BFS is
NO-PATH, and (104,27)'s only non-door neighbour (104,26) sits at the beam top.
The discovery: **stepping onto (111,15) fires a one-shot SCENE** (screen fade,
the party's z flips 2->3). It MUST be ridden with A — holding or pulsing a
DIRECTION into it hangs control forever (measured: 6000+ frames frozen, event
stuck true; A completes it in ~900 frames and returns control at z=3). At z=3
the beam is traversable up-left; dropping onto the left chamber's flat `02`
floor restores z=2. Driven as a per-tile table that A-mashes any
scene/dialog/battle and walks the table otherwise. **Verified end-to-end: mints
past this leg to 221(12,37).**

### FIXED — the BRIDGE-ROOM approach `bridgeCross()` (map 221, (28,33)->(31,30))
After the J33 jump the party climbs a "/" z-loop beam ($41/$44/$49) to the
door (31,30)->225. Door-walled single-z BFS is z-consistent at every seed
(`probe_bridge.lua`); a straight per-tile table (no scene) drives it. **Verified:
mints past this leg to 225(30,61).**

### BLOCKED — the BRIDGE-ROOM climb `bridgeClimb()` (map 225, (30,61)->(30,34))
The direct x=30 column is z-split; the model's only route to the (30,34) door
is a 50-step SWITCHBACK LADDER over "/" ($43/$4B) and "\" ($83/$8B) beams
(`probe_westroom.lua` solve, z-consistent). `bridgeClimb` drives it **correctly
from (30,61) all the way up to (29,41)** — then the blocker: the route's next
step lands on **(30,41)**, which is NOT a nav tile at all but a **scripted
event trigger**: it fires a multi-map cutscene that A-mashing carries
225 -> map 5 -> map 18, auto-walking the party under repeated fades
(measured, `probe_climb2.lua`; neutral input instead just hangs control at
(29,41) forever). And **walling (30,41) makes (30,34) NO-PATH** — the
door-walled model has no alternate. So the passability model diverges from the
OT6 engine here (it over-permits the (30,41) event tile as a "/" beam and has
no other route to the door); cracking it needs a live map-of-the-cutscene or a
redesigned door graph, not another per-tile table. **This gates
`dadaluma_doorstep`, hence `zozo_done`, all Beat A opera legs,
`opera_dance_done`, and the rafter chase / `ultros2_doorstep`.**

### Downstream status (all BLOCKED behind dadaluma)
`opera_dance_done` cannot mint, so `gen_opera6_rafter` stays UNVALIDATED and
`ultros2_doorstep` is unminted; `battle_ultros2.lua` stays SKIPPED. The rafter
decode (fourth pass) is unchanged and still awaits a live drive: legs 2-4 and
the `$01B0/$01B4/$0387` weight-trap mechanic remain to be measured once
`opera_dance_done` is reachable. `make test` (frontier-independent base suite)
stays green throughout — the only source change is `gen_zozo4_dadaluma.lua`.
