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
