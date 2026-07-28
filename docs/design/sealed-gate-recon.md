# OT6 v0.7 — Sealed Gate / Banquet route recon

READ-ONLY reverse-engineering pass, 2026-07-28. No source touched, no emulator
run, no make target invoked (the tree was running the serial release gate).
Scope: the `terra-returned-v1` battery anchor (world (24,121), party
LOCKE·EDGAR·SABIN·SETZER, TERRA available — `tools/tests/anchors/terra-returned-v1/manifest.json`)
through the Narshe mission handoff, the Imperial Base, the Cave to the Sealed
Gate, the esper attack, the Imperial banquet, and the Albrook→Crescent Island
voyage, ending at the stable Thamasa mission handoff.

Modeled on `vector-route-recon.md`, and written with its §11 corrections in
mind: offline formation decodes have lied once (Shiva), offline BFS tile counts
lied on `mod_bg_tiles` maps, and stale party tables caused a re-mint. Claims
here cite a file and line, or are labelled **UNVERIFIED**. Line numbers are
from this repo on 2026-07-28.

**ROM-identity caveat, stated honestly:** the v0.6 recon verified
`event_triggers` / `npc_prop` / `map_prop` / entrance tables / `battle_groups`
byte-identical to retail vanilla (2026-07-26). Since then this tree added
exactly one trigger + one NPC record (the 273 save point). I compared
`build/ot6.sfc` against `ff6/rom/ff6-en.sfc` at all seven data segments
(`ff6/rom/ff6-en.map:200,201,226,289,321,323,325`) and they are identical —
but `ff6-en.sfc` in this tree is a **rebuild of the modified source**
(SHA1 `502c544d…` ≠ the Makefile's vanilla pin `4f37e427…`, `Makefile:2`), so
that comparison proves source↔ROM agreement, not vanilla identity. Vanilla
identity for the v0.7 maps is inherited from the v0.6 segment check plus the
known one-trigger delta; **not independently re-proven this pass.** Measured
directly from `build/ot6.sfc`: `event_triggers` has **13 trailing `$FF` bytes =
2 free trigger slots game-wide**, `npc_prop` has **76 = at most 8 records** —
matching HANDOFF's "room for 2 more".

---

## 0. HEADLINES

1. **v0.7 has no conventional boss.** The beat table's boss — "Ultros ③
   `$12e`·7" (`docs/design/wob-route.md:53`, `docs/design/bosses-wob.md:66,748`
   "Sealed Gate — the rope bridge") — is **not in this band**. Species `$12e`
   appears in formations 387/475 only; formation 387 is event battle **125**,
   whose single call site is `event_main.asm:73702`, inside the Esper-Mountain
   sequence: RELM is created and joins two lines earlier (`:73694-73700`), the
   post-fight party is `STRAGO, TERRA, LOCKE, RELM` (`:73708`), and the scene
   loads **map 371** — the Esper Mountain (world entrance `0 (229,130) → 375`,
   short-entrance table), on Crescent Island, i.e. **v0.8**. bosses-wob §17's
   *content* (espers crash the fight, the rope bridge) is the Esper-Mountain
   statue scene; only its location label and beat assignment are wrong. What
   v0.7 actually fights is scripted theater (§3).
2. **"Maduin at/after the Gate" (wob-route.md:53) is also wrong.** All six
   tube-room espers — MADUIN, PHANTOM, UNICORN, BISMARK, CARBUNKL, SHOAT —
   were granted in v0.6 (`event_main.asm:95777-95782`); **no `give_genju`
   exists anywhere in the v0.7 band** (grepped 43000-47600, 67700-69500,
   93700-100450). The band adds zero espers. The v0.7 magicite work is the
   six already-owned, still-unredesigned stones (§4).
3. **Terra is a hard gate on the route.** The Imperial Base entrance event
   refuses passage unless TERRA is in the **active party**
   (`_cb25d6`, `event_main.asm:44004-44016`: `set_case PARTY_CHARS` +
   `if_switch $01A0` → dlg `$065F` "The Espers wouldn't give us the time of
   day without… TERRA…" and a bounce back to the world map). The anchor party
   is LOCKE·EDGAR·SABIN·SETZER with Terra available-not-active, so the chain
   needs a **Blackjack party-swap drive** (the room armed by `$0070=1`,
   `_cb41a5`, `event_main.asm:47154`) before the base — a driving idiom no
   generator has yet.
4. **The band ends by shrinking the party twice.** The banquet tail forces the
   active party to **TERRA + LOCKE** (`event_main.asm:99079-99086,99163`),
   strips Edgar/Sabin/Cyan/Setzer(/Gau/Mog)'s equipment back to inventory
   (`:99042-99057` region, `remove_equip`), and re-normalizes levels
   (`norm_lvl LOCKE/TERRA`, `:99062-99063`). SHADOW joins at the Crescent
   Island landing (`:69154-69160`). The v0.7 stop line is a **three-person
   party: TERRA, LOCKE, SHADOW** on the world map at **(232,150)** — world-
   [Correction 2026-07-28, thamasa-recon.md: the Thamasa town trigger is at
   (250,128), NOT adjacent to this anchor tile — v0.8's first leg starts
   with a real walk; and Crescent Island's trash is terrain-split across
   three encounter groups, not one.]
   saveable, the natural battery anchor (§2).
5. **The band needs NO new event triggers.** Every proposed anchor is either a
   world-map battery save (legal everywhere, dlg `$06D4`) or the vanilla cave
   save point on map 386. The 2-slot ROM budget is untouched and **segment
   relocation is not required for v0.7** (§2.4).
6. **The airship dies mid-band and stays dead.** The esper attack (battle 123)
   forces a scripted crash to world (83,238) (`_cb2948`,
   `event_main.asm:44449-44494`; `airship_pos {83,238}` at `:44494`,
   `switch $007A=1` at `:44451`). Setzer thereafter refuses to fly — "I'll
   have to repair the air ship" / "You'd better take the boat from Albrook"
   (`_cb1ff3`, `:43078-43083`). Everything after the crash is on foot or by
   boat; leg planning must not assume re-flight.

---

## 1. The route, leg by leg

### Leg 1 — anchor F → Narshe mission handoff

Anchor F resumes aboard the grounded Blackjack at world (24,121) (western
continent; offline world BFS from (24,121) reaches nothing on the southern
continent — the airship is mandatory). Fly to Narshe: the WoB entrance is
world `0 (84,33) → map 20 (38,61)` (short-entrance table); tiles
(83-85,34-36) beside it are airship-landable (world tile-prop bit 1 clear,
`LandAirship`, `ff6/src/world/init.asm:1823-1832`; decoded offline from
`world_1_tilemap.dat` + `tile_prop.asm`).

Walking north from (38,61), the trigger row **(37-39,51)** fires the escort
(`event_trigger.asm:114-116`, map-20 block → `_cc7083/_cc70ab/_cc7097`,
`event_main.asm:93804-93826`), gated **`$006B=1 && $0076=0`** ($006B set by the
v0.6 escape, `:96997`). NPC_7: "We've been waiting for you. This way,
please…", then `load_map 30, {110,26}` (`:93864`) — the meeting is on **map
30** (upper Narshe). The scene (`_cc7120/_cc7137`, `:93899-94170`) is pure
`BOTTOM`-dialog choreography: Banon/Arvis/Elder lay out the plan, Terra
attends **as a scene NPC if she is not in the party** (`:93944-93966`
creates/deletes a TERRA object on `$01A0=0`) — **the meeting itself does not
require or change the party**. Tail (`:94125-94181`): dlg `$0656` "TERRA:
I'll do it. I'm the only one who can!", `switch $064E=1`, party repositioned
to (108,19) on map 30, **`switch $0076=1` (`:94170`)** and `$045E-$0467=0`
(`:94171-94180`) — the ten Imperial-Base soldier NPCs' visibility switches
(`npc_prop.asm` map-377 block; matches `_cb2a5b`'s later "That's odd… No
Imperial soldiers…" line, `:44605`). Control returns; walk out of Narshe to
the world map.

**Handoff state:** `$0076=1`, party unchanged. World-saveable anywhere.

### Leg 2 — seat Terra, fly to the base, cross it

Somewhere before the base: the Blackjack party-swap room (`$0070=1` since
v0.6; `_cb41a5`, `:47154`) must put **TERRA into the active four** — meaning
one of LOCKE/EDGAR/SABIN/SETZER sits out (party size is 4). The swap-room
talk/choice flow is **unread** — first new driving idiom of the band.

Fly to the base: land at **(163,194) or (164,194)** — the only landable tiles
in the pass (offline decode; the pocket east of the base, (167,194)-(168,194),
is walkable but **not** landable, so the base cannot be skipped by air).
Stepping east onto **(165,194)** auto-enters **map 377 "IMPERIAL BASE" at
(6,17)**; the trigger row (6,16)/(7,17)/(6,18) (`event_trigger.asm:1806-1809`)
fires `_cb25d6` (`:44004`):

- `$0242=1` → dead (post-band latch);
- `$0079=1` → `_cb280f`, the post-gate scene (leg 4);
- `$0076=0` → `_cb25b9` (`:43990`): guards get collision — pre-meeting the
  base is blocked;
- else: Terra check (headline 3). With Terra: `_cb2a5b` (`:44575`) plays the
  "No Imperial soldiers…" beat once (`$0172` latch) and control stays.

The base is a walkable pass-through: 377 west side ↔ east side, interior door
`377 (13,18) → 378 (33,43)` (the barracks/treasure annex: **13 chests**
including Flame Sabre, Thornlet, RunningShoes, Cherub Down, X-Potion, Ether,
Elixir ×2, Wall Ring, Cure Ring, Back Guard, Pod Bracelet, Trump —
`treasure_prop.dat` map-378 block; **type bits unverified**, contents ids
exact). A lone NPC at 378 (53,40) guards them (`npc_prop.asm` map-378 block,
event `_cb2562`); the banquet's ≥67-point reward "gives you the right to take
any weapons" via `call _cb2566` (`:99218` region) — **the unlock mechanism is
unread**; assume the chests are not lootable on the first pass. Exit east:
long entrance `377 (31,12) → world (167,194)`; walk (168,194) → **(169,194)**
which auto-enters **map 382 "CAVE TO THE SEALED GATE" at (25,37)**.

Note the asymmetry for the return trip: world (166,194) enters the base at
(30,13) (east door) and (165,194) at (6,17) — both single steps on row 194.

### Leg 3 — the cave: 382 → 383 → 385 → 384 → save room → the Gate

Map graph (entrance tables, all cited from the decoded
`short_entrance.dat`/`long_entrance.dat`):

```
world (169,194) ─► 382 (25,37)          cave mouth        [title 69]
382 (31,43) ─► 383 (50,43)              "BASEMENT 1"      encounters grp 93
383 (53,58) ─► 385 (1,2)                "BASEMENT 2"      the timed-floor room
385 (13,13) ─► 384 (26,8)               "BASEMENT 3"      the big bridge map
384 (64,10) ─► 386 (73,58)              "BASEMENT 4"      SAVE POINT (74,53)
384 (4,36) ◄─► (121,22), (94,25) ◄─► (90,58)   internal teleport pairs
384 long (9,27) ─► 391 (8,21)           "SEALED GATE" — lands ON the scene trigger
391 (8,22) ─► 384 (10,27)               the way back out of the gate room
384 (29,48) ─► 383 (118,54)             side loop
384 trigger (5,43) ─► load_map 382 (31,41)   the post-gate shortcut (_cb2a9f, :44618)
```

**Map 385 is a timed alternating-floor puzzle.** Trigger tiles at (3,2)/(10,2)
arm cycle A (`_cb2aca/_cb2ae8`, `:44634/:44646`: `start_timer 0` → `_cb2bb2`,
which flips tile state and re-arms 144-frame timers alternating `$01F5`/`$01F6`
— `:44690-44712,:44738-44745`); (11,3)/(13,11) arm cycle B (`_cb2c6e/_cb2c8c`,
`:44746/:44758`, latch `$01F1`). A carpet of ~40 triggers
(`event_trigger.asm:1844-1885`) covers the floor: `_cb2dbb` tiles hurt during
phase `$01F5`, `_cb2dd2` tiles during `$01F6`, and **(15,10) (`_cb2de9`,
`:44884`) hurts always**. A wrong step costs the whole party HP/8
(`dec_hp … HP_8`, `_cb2dae` `:44858`), teleports SLOT_1 back to **(2,6)** and
clears every `$01F0-$01FF` latch (`_cb2e1b` `:44905`). Map-init `_cb2b0f`
(`map_init_event.asm:404`) restores state on re-entry. **`navTo` cannot drive
this room** — it needs a phase-aware crossing (watch `$1E80+$3E` bits for
`$01F5/$01F6`, step on-phase). This is the v0.6 platform-window problem
(recon §8.4), except this time it is **on the mandatory route**.

**Map 384 is the mod_bg_tiles map.** Its map-init `_cb2e3d`
(`map_init_event.asm:403`, `:44931`) re-applies at least ten tile-patch
blocks from switches, so **the static tilemap does not describe the live map
and offline BFS is unreliable here** — exactly v0.6 recon §8 hazard 3 /
§11's correction class. The machinery, west→east:

| where | event | what |
|---|---|---|
| (46,11) | `_cb2f00` `:44996` | scripted bridge-retract scene, sets `$01F9/$01FB` |
| (40,11) | `_cb2f65` `:45041` | bridge crumbles behind you when `$01F9=1` |
| (58,18) | `_cb2fe7` `:45071` | face-UP+A switch → opens (48,12) span, dlg `$069C` "Heard a distant sound…", `$01F9/$01FA=1` |
| (62,11) | `_cb3062` `:45148` | face-UP+A switch, persistent `$0173` |
| (66,11) | `_cb307e` `:45156` | **trap switch**: spawns a Ninja NPC → **battle 149**, dlg `$069D`, once per tile-latch |
| (71,15) | `_cb3176` `:45276` | face-UP+A switch, persistent `$0174` — extends the x=76 column bridge |
| (89,29) | `_cb31f0` `:45337` | walk-over switch, persistent `$0175` |
| (96,18),(99,18) | `_cc3251/_cb328f` `:45383/:45413` | walk-over switches, session `$01F3/$01F4` |
| (104,17) | `_cb33c9` `:45485` | face-UP+A **toggle** — flips a whole 5×13 bridge region between two states (`$01F5`) |
| (112,16) | `_cb36b5` `:45654` | face-UP+A **toggle** (`$01F6`) — the treasure-alcove bridge |
| (99,13)/(100,12)/(101,13) | `_cb3804/25/46` `:45723-45777` | "There's a switch inside. Flick it?" choice → toggles the (113,10) tile (`$01F7`, `_cb386e`) |
| (75,28)/(79,30)/(75,34)/(71,26) | `_cb30cf…_cb3129` `:45193-45238` | A-press digs: Inviz Edge / Water Skean / Remedy / 2000 GP — each behind **`if_rand`** (nondeterministic; fixtures must not depend on them) |

Chests on 384: Ether ×3, Elixir, Genji Glove (47,11), **Magicite ×3**
((113,6) behind the `$01F7` toggle; (88,53)/(91,49) in the alcove), Atma
Weapon (92,49) (`treasure_prop.dat` map-384 block; type bits unverified).
382: Assassin. 383: Tempest. 385: Coin Toss, X-Potion. 386: Tent.

The `$01B0-$01B4` face+A idiom (v0.6 recon §7) is load-bearing at **seven**
sites on this one map. Every switch needs the bespoke "arrive facing D, hold
A" step.

**Save room:** 384 (64,10) → map 386, `SavePoint` trigger at **(74,53)**
(`event_trigger.asm:1886-1887`), sparkle NPC in the map-386 `npc_prop` block.
The only interior save opportunity in the whole band.

**Route order through 384 is not statically derivable** (mod_bg_tiles +
teleport pairs). What is derivable: entry (26,8) is in the northwest, the
save-room door (64,10) and all switch machinery are center/east, the gate
door (9,27) is far west, and the (4,36)↔(121,22) teleport pair links the two
ends. Expect: east across the bridges → toggles → teleport back west →
(9,27). **Needs a live census at minting** (the `gen_mrf_entry` pattern).

### Leg 3-end — the Sealed Gate scene (map 391)

The long entrance `384 (9,27) → 391 (8,21)` lands **on** the scene trigger
(`event_trigger.asm:1898`: `{8,21} → _cb39ca`), so the whole set piece should
fire on entry (**UNVERIFIED whether frame-0 or first-step**). `_cb39ca`
(`event_main.asm:45953-46321`), gated `$0079=0`:

- long camera choreography, Terra walks to the gate;
- Kefka bursts in **as the VICKS actor** (`char_prop VICKS, KEFKA_2`,
  `:46096-46103`), Terra is **removed from the party** (`char_party TERRA, 0`,
  `:46095`), full heal + status clear (`call _cacfbd`, `:31862-31878`), then
  **`battle 121`** (`:46106`);
- more choreography, second heal, **`battle 122`** (`:46192`);
- the espers burst out (`_cb3c58`, `:46322+`: NPC_11/14/16/17/18 fly past,
  "Hey! The gate!!!"), Terra restored (`char_party TERRA, 1`, `:46202`);
- tail (`:46310-46317`): `$046E-$0470=0, $0471=1, $064D=1, $064C=0`,
  **`$0079=1`**, `load_map 384, {10,28}` — control returns just outside the
  gate door.

**Battles 121/122 decode to formations 384/385 containing only species `$17b`
(blank name, L1 HP1)** — dummy formations whose content must come from the
battle-event script. Same for battle 123 (formation 386). **Treat this decode
as suspect**: v0.6 recon §11 proved the offline `battle_monsters.dat` read
wrong for battle 70 ("Shiva is not in the formation" — she was). Whether
Kefka is a real, loseable combatant here, and whether the kill-bit idiom
applies, **must be probed** (no `if_b_switch` follows either battle — weaker
than a `$40` gate, like Number 024).

### Leg 4 — out of the cave, the esper attack, the crash

After the gate, `$0079=1` makes map-init `_cb2e3d` apply `_cb2aa6`
(`:44662-44673` region — retiles (4,41)-(6,44)), exposing the ungated trigger
at **384 (5,43) → `load_map 382 (31,41)`** (`_cb2a9f`, `:44618`) — the
shortcut out. (**Inference, unverified**: pre-`$0079` those tiles are
unreachable; the trigger itself has no gate.) Exit 382 → world (169,194):
**world-saveable pocket**, (167,194)/(168,194).

Walking west, (166,194) auto-enters the base east side (30,13); crossing to
the west trigger row fires **`_cb280f`** (`:44289`) since `$0079=1`:

- the "What happened? / The Espers flew off… / Toward the capital… /
  Vector…" ensemble (per-available-character lines, `:44117-44287`);
- `switch $0242=1` (`:44351`) — the base entrance goes silent forever;
- **auto-teleport to the Blackjack** (`load_map 6 {15,6}`, `:44352`), Setzer
  (or a crew NPC if Setzer were absent, `$01A9` branch): "We're almost at
  Vector." / "There! What's that?" → **`battle 123, AIRSHIP_CENTER`**
  (`:44389` / `:44442`) — the esper strafing of the ship;
- `$007A=1, $01BA=1, $007B=1, $0246=0` (`:44451-44454`), then a scripted
  VEHICLE flight from (160,188) with explosion/fall choreography
  (`:44455-44491`) ending `load_map 0 {83,239}` + **`airship_pos {83,238}`**
  (`:44493-44494`) — the crash site — and control aboard the grounded wreck
  (`:44520-44531`).

`$007B=1` also disarms Vector's on-contact soldier machinery (map-242 init
`_cc9540` gates `collision_on` on `$007B=0`, v0.6 recon hazard 7), and the
Guardian trap `_cc8321` (`:97000`) requires `$0079=0` so it is **inert** from
here on.

**There is no save between the base west row and the crash** — the whole
stretch is one auto-played sequence. The last save before it is the world
pocket (167-169,194); the first after it is the world map at the crash site.

### Leg 5 — the walk to Vector

On foot from (83,238) to the Vector world trigger (120,187)/(121,187):
**~115-118 steps** (offline world BFS), ~96% of tiles battle-enabled —
`worldGrind` territory, never `worldNavTo` (the gen_opera1 lesson). World
pools on the southern continent: Ralph / Wyvern / WeedFeeder / ChickenLip /
Joker / FossilFang / Bug (`world_battle_group.dat` sectors (2-3,5-7), decoded
via `CheckBattleWorld`'s `(Y&$E0)|((X>>3)&$1C)` indexing,
`field/battle.asm:97-147`). With `$0079=1` the trigger loads **map 253** —
post-attack Vector — at (32,61) (`_ca5ecf`, `:14196-14205`; `$0079` selects
253). Map 253 has **no event triggers at all** (`EventTrigger::_253`, empty)
and a palette-dimming map-init (`_cc92ed`, `:99333`); its exits mirror 242's
(same entrance table shape: five interior doors, the castle door, the world
exit).

### Leg 6 — the Imperial banquet (maps 243 → 250/251/252, the timed block)

Castle door: `253 (28,1) long → 243 (15,29)`. At 243 (8,18) the escort fires
(`_cc835c`, `:97039`: "The Emperor's expecting you. This way…", `$013A=1`,
opens the door tiles). Inside, at **250 (54,16)**, face-UP+A on Gestahl's
dais starts the sequence (`_cc8490`, `:97242`, gated `$007C=0`):

- Gestahl/Cid scene ("I've lost my will to fight…", "talk to as many soldiers
  as you can"), then **`$007C=1`, `set_var 0, 0`,
  `start_timer 0, 14400, _cc8a96, {FIELD_VISIBLE, BANQUET,
  MENU_BATTLE_VISIBLE}`** (`:97418-97420`) — a **4-minute on-screen timer**
  that keeps counting through menus and battles
  (`DecTimersMenuBattle`, `field/event.asm:5592` — "used during emperor's
  banquet"). **Variable 0 is the banquet score.**
- The soldier circuit: ~27 soldier NPCs spread across **five maps** — 243,
  244, 250, 251, 252 (`npc_prop.asm` blocks; events `_cc86xx-_cc88xx`).
  Ordinary talks are +1 each (24 `add_var 0, 1` sites, `:97838-:97999`);
  four soldiers fight: **battle 26** (Mega Armor `$102`, +5 on win,
  `:97678`) and **battle 27 ×3** (Commando `$0c7`, +5 each,
  `:97730/:97763/:97805`).
- Timer expiry → **`_cc8a96`** (`:98045`): wherever the party stands, the
  dinner starts — transition through map 5 ("That evening, the banquet with
  the Emperor took place…"), then **map 251 (80,25)**, the dinner table.
- The dinner is a chained choice-dialog Q&A — the `gen_zozo3_clock` shape,
  exactly as `wob-route.md:151` predicted — with per-answer scores
  (`choice` sites `:98189-:98763`; values +1/+2/+3/+5, one **−10**
  (`sub_var`, `:98443`), a repeatable question submenu (`_cc8d71`,
  `:98446-98451`)). Mid-dinner the player may leave the table
  (251 (80,20) trigger `_cc8e63`, `:98594`) and take the troopers'
  challenge (`_cc8a47`, `:98011`): a **2-minute timed battle 30**
  (Sp Forces `$0c2` ×3; `start_timer 0, 7200` at `:98021`; outcome read via
  battle switches `$40/$45/$44`, +5 clean win, `:98022-98036`).
- Q&A tail (`:98763+`): Gestahl asks Terra to be his envoy, **General Leo**
  introduced ("I'll be waiting for you in Albrook", `:98857`), then the
  roster rewrite (headline 4): availability force-set — TERRA, LOCKE, CYAN,
  EDGAR, SABIN, SETZER available; CELES, SHADOW, STRAGO, RELM unavailable
  (`$02F0-$02F9` writes, `:98934-98943`) — the "wait here and investigate"
  scene, `char_party` → **TERRA + LOCKE only** (`:99079-99086, :99163`),
  `remove_equip` on the four who stay, **`$007D=1`** (`:99133`), control back
  on 251.
- Walking out, at 250 (23,12) the messenger scene scores the banquet
  (`_cc91c0`, `:99146`): always "troops withdrawn from South Figaro"
  (`$0276=1`); **var 0 ≥ 50** → Doma withdrawal (`$0277=1, $0512=0`);
  **≥ 67** → the Imperial-Base weapons unlock (`call _cb2566`, `$0278=1`);
  **≥ 77** → Tintinabar (`:99236`); **≥ 90** → Charm Bangle (`:99249`).
  Then `set_var 0, 0`, `$0238=1` (`:99261-99262`).

**The entire block from `$007C=1` to `$0238=1` is transient event state** —
two live timers, a score variable, castle-wide scripted NPC states — the
paradigm case of the #10 prohibition. No save, anchor, or fixture boundary
may live inside it. It also cannot be shortened: the dinner starts only via
the 14400-frame timer callback (no early-out found; **UNVERIFIED** that none
exists — I did not read all 27 soldier scripts).

### Leg 7 — Vector → Albrook → the voyage → Crescent Island

Exit the castle and Vector; world walk to Albrook, `(138/139,203) → 323
(2,17)` — **33 steps** (offline BFS) from Vector's south exit. The v0.6
"wrong turn" town is v0.7's required destination, so `gen_vector_arrival`'s
Albrook navigation work becomes reusable after all.

With `$007D=1` the port gate at 323 (43,26)/(45,26) stands down
(`_cc62f2/_cc632d`, `:91543/:91585`), Albrook NPCs flip to pre-departure
lines (the `$007D` branch cluster, `:90701-91940`). The port is **map 332**
(via `323 long (43,29) → 332 (22,2)`; Leo NPCs in `NPCProp::_332`,
`npc_prop.asm:14422+`):

- If GAU is available (he is, on this chain — `$1EDF=$88` at the v0.6
  anchor), he tags along and refuses to board at 332 (10,10)/(11,10):
  "He hates ships. We must…leave him behind!" — **`char_party GAU, 0` and
  `switch $02FB=0`** (`_cbcb74/_cbcbde`, `:67905/:67978`).
- The pier scene (`_cbcc84`, `:68091+`): Leo introduces the traveling party —
  **"General CELES…and SHADOW"** (dlg `$0768`, `:68254`) — Celes reappears
  here as an **NPC**, not a party member; Shadow gets his codex intro. "Our
  departure isn't till tomorrow" → a controllable night window in Albrook
  (`$0084/$0085`, `:68308-68310`).
- "Right… let's go" (`$0083=1`, `:68383`) → scripted sail: `load_map 0
  {138,206}` + `ship_gfx` world script (`:68390-68393`), back aboard (the
  ship interior is part of map 332); night watch: **`char_party LOCKE, 0`,
  `party_chars TERRA`** (`:68483-68488`) — Terra alone for the Leo
  conversation (`_cbcefc`, `:68497+`), then the Shadow scene ("In this world
  are many like me who've killed their emotions", `:68854`), Locke's
  seasickness comedy, second sail leg `load_map 0 {193,157}` (`:68963`),
  `$0086=1` (`:69018`), Leo's split briefing — "CELES and I will form one
  group. TERRA, you go with LOCKE and SHADOW" (`_cbd1f3`, `:69024`).
- Landing (`:69154-69190`): `char_party LOCKE, 1`, **`create_obj SHADOW` +
  `char_party SHADOW, 1` + `$02F3=1` + `norm_lvl SHADOW`**, `set_b_switch
  $4B`, and the party is placed on the world map at **(232,150)**, Crescent
  Island, controllable.

**The v0.7 stop line: world (232,150), party TERRA · LOCKE · SHADOW, `$007D=1
$0083=1 $0086=1`, airship still dead (`$007A=1`), Gau unavailable
(`$02FB=0`).** One step north-ish, world (232,150) sits beside the Thamasa
world trigger chain (`_cbd2ee`, `:69190`: → map 343 (23,46)) — v0.8's
doorstep. Crescent Island world trash: Baskervor / Cephaler / Chimera
(sector (7,4) decode).

---

## 2. Save opportunities and anchor candidates

### 2.1 Inventory, route order

| # | where | what | evidence |
|---|---|---|---|
| S0 | world, anywhere | anchor F `terra-returned-v1` (24,121) | tracked; `anchors/terra-returned-v1/manifest.json` |
| S1 | world outside Narshe | world save after `$0076=1` | dlg `$06D4` world-save rule (`save-points-vector.md` §1) |
| S2 | world (163-164,194) | landing tiles beside the base door | offline tile decode |
| S3 | **map 386 (74,53)** | the cave save room, off 384 (64,10) | `event_trigger.asm:1886`; sparkle in `NPCProp::_386` |
| S4 | world (167-169,194) | the pocket between base and cave — usable **both** before the cave and after the gate | entrance table; §1 leg 4 |
| S5 | world (83,238)+ | crash site; the whole walk to Vector | `airship_pos` `:44494` |
| S6 | world outside Vector | last save before the banquet block | map 253 has no save point; castle has none |
| S7 | world between Vector and Albrook | post-banquet, party TERRA+LOCKE | leg 7 |
| S8 | world (232,150) | Crescent Island — the stop line | leg 7 |

No `SavePoint` trigger exists on maps 243-253, 377-385, 391, 323-332, 340-345
except S3 (all their `EventTrigger::_N` blocks read; map 331's save point and
map 375's (Esper Mountain) are outside this band; map 322's is elsewhere).
Unlike v0.6's factory — one long interior one-way — **this band surfaces on
the saveable world map between every major set piece.** Vanilla already
placed the one interior save the band needs (mid-cave, before the Gate).

### 2.2 Proposed anchors (leg-fixtures.md §5-style)

| anchor | battery save at | exists? |
|---|---|---|
| **F** `terra-returned` | world (24,121) | yes — tracked |
| **G** `narshe-mission` | world near (84,35), `$0076=1` | world save, no authoring |
| **H** `gate-cave-save` | map 386 (74,53), Terra in party | vanilla save point |
| **I** `vector-crash` | world (83,238), `$0079=1 $007A=1 $007B=1 $0242=1` | world save, no authoring |
| **J** `banquet-done` | world outside Vector, `$0238=1 $007D=1`, party TERRA+LOCKE | world save, no authoring |
| **K** `thamasa-mission` | world (232,150), party TERRA+LOCKE+SHADOW | world save, no authoring — the v0.7 terminal |

Legs: F→G (fly, meeting), G→H (swap Terra in, base, 382/383/385/384 to the
save room — **the hard leg**: the timed floor + the switch bridges), H→I
(the Gate scene, exit, base re-cross, battle 123, crash — long and almost
entirely scripted; consider a **savestate** split at `gate_won`, not an
anchor), I→J (world grind, the banquet block — **the long atomic leg**:
≥14400 frames of timer alone, plus Q&A; cannot be split legally), J→K
(Albrook, voyage — scripted; the Albrook night window is controllable but
mid-sequence: **UNVERIFIED whether leaving town mid-window is safe**, so
anchor at K, not in Albrook).

An optional S4-pocket anchor (post-gate, pre-crash) is legal and free; take
it only if H→I over-runs the frame budget.

### 2.3 The Terra invariant

Anchors H (and any savestate inside the base/cave) must assert **TERRA in the
`$1850` active set** in their entry contract — the base gate makes her
membership load-bearing, and a stale anchor minted with the wrong four would
pass every ordinary check and then bounce off `_cb25d6`. Anchors J/K must
assert the *shrunk* party (2 and 3 nonzero `$1850` entries respectively) so a
chain that somehow keeps Edgar/Sabin fails loudly (#21's count-assert
pattern, inverted).

### 2.4 ROM budget

**Zero new triggers, zero new NPC records.** All six anchors are world
battery saves or the vanilla 386 save point. The 2-trigger / 8-record budget
(measured, §header) stays intact for the Opera-band backlog (#10), and **v0.7
does not force segment relocation**. If playtesting later wants an authored
save before the banquet (the strongest candidate — Vector 253 has none and
the banquet is long), that is the moment relocation gets designed, not now.

---

## 3. Bosses and set pieces

### 3.1 The fight slate

| fight | where | formation (offline decode — verify at doorstep, §11 precedent) | notes |
|---|---|---|---|
| battle 121, 122 | map 391 gate scene | 384/385 → species `$17b` dummy only | Kefka-at-the-gate theater; Terra out of party; full heal before each (`_cacfbd`); **content lives in the battle-event script, unread**; loseability unknown |
| battle 123 | map 6 deck | 386 → `$17b` dummy | esper strafing; scripted |
| battle 149 | 384 (66,11) trap switch | 524 → **Ninja `$003`** L27 HP1650, absorb poison, weak bolt+pearl (`monster_prop` +23/+25) | the band's one real ambush |
| battle 26 | banquet soldier | 408 → **Mega Armor `$102`** L21 HP1000, weak bolt+water | +5 score |
| battle 27 ×3 | banquet soldiers | 418 → **Commando `$0c7`** L18 HP580, weak bolt+water | +5 each |
| battle 30 | dinner challenge | 157 → **Sp Forces `$0c2` ×3** L21 HP700, weak poison | 2-min timer; outcome via b-switches `$40/$44/$45` |
| battle 75 | Vector gate row | Guardian `$0111` | **inert on-route** (`_cc8321` needs `$0079=0`); already `Ot6ShieldTbl` scripted-theater class (`wob-route.md:58`) |

**No gauge-drawing boss exists in the band** (headline 1). The gate/deck
battles are candidates for the Guardian/Tritoch "draws no gauge, silent HUD"
treatment — a design decision, not authoring work.

### 3.2 Encounter survey shape (the #11-style pass the band needs)

Decoded via the break-band-vector.md §1 chain (`map_prop` byte 5 bit 7 →
`SubBattleGroup` → `RandBattleGroup` → `BattleMonsters` → `MonsterProp`):

| map | title | enable | group | rate | pool (L, HP, absorb/weak from `monster_prop` +23/+25) |
|---|---|---|---|---|---|
| 382 | CAVE TO THE SEALED GATE | Y | 92 | `$0070` | Apparite ×2 · Lich/Apparite/Coelecite · Lich ×3 |
| 383 | BASEMENT 1 | Y | 93 | `$0070` | Apparite ×2 · Apparite×2+Lich×2 · Ing ×3 |
| 384 | BASEMENT 3 | Y | 94 | `$0070` | Zombone ×2 · Zombone+Ing×2 · Ing ×3 |
| 385 | BASEMENT 2 | Y | 95 | `$0070` | Zombone · Zombone+Ing×2 · Coelecite ×3 |
| 386 | BASEMENT 4 | n | 92 | — | save room; carries a group, cannot draw it |
| 377/378 | IMPERIAL BASE | n | 110 | — | no encounters in the base |
| 391/243/250/251/253 | — | n | — | — | no encounters |

Species rows: **Apparite** `$06e` L20 HP781 absorb fire+poison, weak
ice+pearl · **Lich** `$0e5` L20 HP590 absorb fire+poison, weak pearl ·
**Ing** `$048` L21 HP1100 absorb fire+poison, weak pearl+water · **Zombone**
`$082` L21 HP1991 absorb poison, weak fire+pearl · **Coelecite** `$0b3` L20
HP480 absorb fire, weak ice.

**The interesting break-axis shape:** this is an undead cave whose master key
is **pearl/holy — an element no kit in the band can currently produce** —
while **fire, Terra's signature lean (kits.md §Terra), is absorbed by four of
the five species**. The band forces Terra into the party and then punishes
her favorite button, the same inversion Zozo played on poison. The survey
pass has to decide: give the band a reachable pearl key (Kirin/Unicorn
Cure-line as holy chip? a Unicorn redesign hook — see §4), lean on the
secondary axes (ice for Apparite/Coelecite, fire for Zombone only, water for
Ing), or author class rows instead. Plus the banquet's bolt+water armor pair
(Mega Armor/Commando — Ramuh/Bio Blaster keys) and poison Sp Forces, and two
world bands (southern continent, Crescent Island) that have never been
surveyed. That is the #11-shaped deliverable; this table is its inventory,
not its authoring.

---

## 4. Character / kit / magicite obligations

- **Terra** becomes mandatory and active for the first time since v0.3. Her
  kit (kits.md "Esper mage") must be honest at band levels (~L15-16 measured
  at v0.6's tail, `wob-route.md:97-102`; `norm_lvl TERRA` re-normalizes at
  the banquet, `:99063`).
- **Party-swap choice** (dispatcher call): Terra in for one of
  LOCKE/EDGAR/SABIN/SETZER through the cave. The banquet erases the choice
  (forces TERRA+LOCKE) and the scene handles any composition (per-character
  conditionals at `:44117+`, `:98800+`), so the pick is purely a
  balance/coverage question for the cave survey.
- **Post-banquet the band runs two-handed** (TERRA+LOCKE, world trash +
  no fights until the stop line), then **three-handed** (+SHADOW at
  `:69154-69160`, `norm_lvl`). **Shadow's kit is only a sketch**
  (kits.md:380: Throw signature; Assassinate built dormant, ROADMAP v0.4) —
  he joins in v0.7's final frames and v0.8 opens with him active, so his kit
  is this milestone's exit criterion or v0.8's entry debt; decide which.
- **Celes** reappears as an NPC (Albrook/ship) but `$02F6` stays 0; no kit
  work. Equipment stripped from EDGAR/SABIN/CYAN/SETZER/GAU/MOG returns to
  inventory (`remove_equip`, `:99042+`) — fixture inventory assertions should
  expect it.
- **Magicite:** the band grants **no** new esper. The M5 load is the six
  tube-room stones owned since v0.6 with `$00` stat rows —
  `Ot6EsperStatTbl` (`ff6/src/battle/ot6_progression.asm:430-448`): shoat,
  maduin, bismark, carbunkl, phantom, unicorn all `OT6_SM_NONE`, vanilla
  spell lists under the while-equipped engine. Per M5 policy ("each esper
  redesigned in the release where it becomes available") this debt strictly
  belongs to v0.6, which shipped only Ifrit/Shiva; v0.7 is where it lands or
  is explicitly re-scoped. Note `magicite.md`'s roster table *proposes*
  staggered sources ("Maduin — Sealed Gate", "Carbunkl — Sealed Gate",
  "Shoat — Vector aftermath", "Bismark — Thamasa") that contradict the
  shipped all-six-at-the-tube-room event — redistributing acquisition would
  be an event-script change with frontier re-mint cost; a decision is needed
  before the redesigns are written (see Report/decision 3).

---

## 5. Known hazards, ranked

1. **The banquet is one indivisible transient block** (`$007C=1` →
   `$0238=1`): two event timers (14400 + 7200, `FIELD_VISIBLE|BANQUET|
   MENU_BATTLE_VISIBLE` — they tick through menus and battles,
   `field/event.asm:5592`), a score variable, five maps of scripted NPC
   state, and a timer callback that teleports the party. No save/anchor
   inside; whether a *player* save inside it (menu is reachable) survives
   reset/load with timers intact is **unknown and worth a destructive-bug
   probe** — nothing in `vanilla-destructive-bugs.md` covers it (the doc's
   timer entries are FC-countdown only, `:961-963`).
2. **Map 385's alternating floor.** Timer-driven 144-frame phases, party-wide
   HP/8 per mistake, teleport-and-reset. Needs a new phase-aware driving
   idiom; `navTo` will walk into damage tiles. (An HP-attrition loop could
   in principle kill a low-HP party — dec_hp floors at 1 HP or not is
   **unverified**.)
3. **Map 384 is not statically navigable** — `mod_bg_tiles` at ten+ sites,
   two teleport pairs, seven face+A switches, one trap battle, `if_rand`
   digs. Live census required; offline BFS results for this map should not
   be trusted or produced. (v0.6 §8 hazard 3 / §11 correction class.)
4. **Scripted-battle opacity.** Battles 121/122/123 decode to dummy-only
   formations; the battle-event scripts were not read. Loseability, kill-bit
   applicability, and what actually spawns are all probe-first questions.
   Battle 30 *is* battle-switch-gated (`$40/$45/$44` read at `:98023-98035`)
   — the kill-bit idiom needs the right switch set, not just the win bit.
5. **Auto-played stretches with no control:** base west row → battle 123 →
   crash (leg 4), and the timer callback → dinner (leg 6). Fixture asserts
   must ride them (`rideScene`/`hasControl`), never expect control mid-way.
6. **The gate room's entry tile is the scene trigger** (long entrance dest
   (8,21) = trigger (8,21)). There is no in-room doorstep; the `gate_doorstep`
   fixture belongs on map 384 beside (9,27).
7. **The airship is dead from the crash to past the stop line** (`$007A=1`,
   `_cb1ff3` `:43078`). No leg after I may plan a flight; the party-swap
   room is also out of reach after the banquet (not that it matters — the
   party is forced).
8. **Once-latches that die if mis-sequenced:** `$0242` (base scene), `$0172`
   (no-soldiers beat), `$013A` (castle escort), `$0237` (challenge),
   `$0238` (rewards). A leg that reloads an anchor minted *after* a latch
   must not assert the latch's scene.
9. **Gau at the port.** If the chain's roster keeps Gau available, the
   boarding includes his departure scene and `$02FB=0`; a chain minted with
   different availability changes the port choreography (`$01AB` branches).
   Entry contracts for J/K should pin `$1EDE/$1EDF`.
10. **vanilla-destructive-bugs.md has no entries in this band.** The one
    live global item is Sketch (v0.8, ships as-is by owner decision); the
    checksum-`$0000` bug was already fixed (#18, 37a0eb5) — this item
    originally listed it as open, corrected 2026-07-28.
    The Opera comparison (#10's deferred analysis): the banquet is the same
    "long transient choreography" shape but — unlike the Opera — it is
    bounded by the saveable world map on both sides, so it needs no authored
    save and no relocation.

---

## 6. Open questions for the milestone

Only minting or a design decision settles these:

1. **What are battles 121/122/123 really?** Probe `formationWords()` at each
   start and per turn; establish loseability and the win/latch mechanism.
   (The §11 Shiva precedent says the offline decode is not evidence.)
2. **Map 384 live topology**: reachable set at each switch state, whether the
   route order east→toggles→teleport→west is right, where the (5,43)
   shortcut tiles sit pre-`$0079`, and the 385 floor's safe-tile map per
   phase (dump the two `mod_bg_tiles` states and diff).
3. **Does the dinner have an early-out**, or is the 14400-frame timer a hard
   floor on the banquet leg? (Read the remaining soldier scripts or probe.)
4. **Timer state across save/reset/load** inside the banquet window (player-
   facing destructive-bug question, and it decides whether `make test` needs
   a guard).
5. **Score policy**: which reward tier does the frontier chain ship? ≥90
   (Charm Bangle) needs a scripted optimal circuit + Q&A answers; the
   thresholds are at `:99199/:99211/:99224/:99237`. Note ≥50 flips Doma/South
   Figaro world state (`$0276/$0277/$0512`) — whatever tier is chosen becomes
   frontier-wide canon.
6. **The Blackjack party-swap drive** (`_cb41a5` flow unread): the talk/choice
   sequence to seat Terra, and its assert (`$1850` slot 0 nonzero).
7. **The Albrook night window**: is leaving town (to world-save) mid-sequence
   safe, or does `$0084/$0085` state wedge? Decides whether J→K gets a
   mid-leg savestate.
8. **Base treasure unlock mechanism** (`_cb2566`) and whether the ≥67 reward
   plus a return trip is worth routing (13 chests incl. Flame Sabre — a real
   equipment jump for a two-person party).
9. **Magicite scope decision** (§4): redesign all six in place, or
   redistribute acquisitions per magicite.md's proposal (an event change +
   full re-mint).
10. **`dec_hp … HP_8` floor semantics** (can 385's floor kill?), and whether
    the SavePoint at 386 needs the #10 save/reset/load/progress verification
    (it is vanilla, but no OT6 chain has ever exercised it).

---

## Appendix — key addresses

| thing | citation |
|---|---|
| Narshe escort triggers | `event_trigger.asm:114-116` (map 20) → `event_main.asm:93804/93826` |
| meeting scene / map 30 | `load_map 30` `:93864`; scene `:93899-94170`; **`$0076=1` `:94170`** |
| base entry + Terra gate | `event_trigger.asm:1806-1809` → `_cb25d6` `:44004`; refusal dlg `$065F` `:44011+` |
| base soldiers / visibility | `NPCProp::_377` (switches `$045E-$0467`, cleared `:94171-94180`) |
| base→world→cave doors | short entrances: `0 (165,194)→377 (6,17)`, `0 (166,194)→377 (30,13)`, `377 (31,12) long→0 (167,194)`, `0 (169,194)→382 (25,37)` |
| cave graph | §1 leg 3 table (short/long entrance decode) |
| 385 floor machinery | `_cb2aca` `:44634` … `_cb2e1b` `:44905`; map-init `_cb2b0f` (`map_init_event.asm:404`) |
| 384 map-init | `_cb2e3d` `:44931` (`map_init_event.asm:403`) |
| Ninja trap switch | `_cb307e` `:45156` → **battle 149** `:45177` → formation 524 = `$003` |
| Sealed Gate scene | `event_trigger.asm:1898` → `_cb39ca` `:45953`; **battle 121 `:46106`, battle 122 `:46192`**; tail `$0079=1` `:46316`, `load_map 384 {10,28}` `:46317` |
| gate-scene full heal | `_cacfbd` `:31862-31878` |
| post-gate base scene | `_cb280f` `:44289`; `$0242=1` `:44351`; **battle 123** `:44389/:44442` |
| crash flight | `_cb2948` `:44449`; `$007A/$007B=1` `:44451-44453`; `airship_pos {83,238}` `:44494` |
| airship refuses to fly | `_cb1ff3` `:43078-43083`; gate read `:43084` |
| Vector 253 select | `_ca5ecf` `:14196-14205` (`$0079` branch); map-init `_cc92ed` `:99333` |
| castle escort | `_cc835c` `:97039` (243 (8,18)) |
| banquet start / timer / score | `_cc8490` `:97242`; `$007C=1` `:97418`; `set_var 0,0` `:97419`; `start_timer 0,14400,_cc8a96` `:97420` |
| soldier fights | battle 26 `:97678`; battle 27 `:97730/:97763/:97805`; +1 sites `:97838-:97999` |
| dinner start | `_cc8a96` `:98045`; `load_map 251` `:98069` |
| challenge battle | `_cc8a47` `:98011`; `start_timer 0,7200` `:98021`; **battle 30** `:98022`; b-switch reads `:98023-98035` |
| Q&A choice graph | `:98189-98763`; `sub_var 0,10` `:98443` |
| roster rewrite / TERRA+LOCKE | `$02Fx` writes `:98934-98943`; `char_party` block `:99079-99086`; `$007D=1` `:99133` |
| reward ladder | `_cc91c0` `:99146`; thresholds 50/67/77/90 `:99199/:99211/:99224/:99237`; items `:99236/:99249`; `$0238=1` `:99262` |
| Albrook port gate | `_cc62f2/_cc632d` `:91543/:91585` (323 (43,26)/(45,26)) |
| Gau refuses the ship | `_cbcb74/_cbcbde` `:67905/:67978`; `$02FB=0` `:67952` |
| Celes+Shadow intro | dlg `$0768` `:68254` |
| voyage / night deck | sail `:68390`; `party_chars TERRA` `:68488`; Leo talk `_cbcefc` `:68497`; second sail `:68963` |
| landing / SHADOW joins | `:69154-69160`; world **(232,150)** `:69188` |
| Thamasa world trigger | `_cbd2ee` `:69190` → map 343 (23,46) |
| **Ultros ③ is v0.8** | formation 387 = `$12e`; event battle 125; sole call `:73702` with RELM join `:73694-73700`, map 371 load `:73706` |
| tube espers granted v0.6 | `give_genju` block `:95777-95782`; stat rows `ot6_progression.asm:430-448` |
| trigger/NPC free space | measured from `build/ot6.sfc`: 13 / 76 trailing `$FF` bytes |
| world battle indexing | `field/battle.asm:97-147` (`CheckBattleWorld`); sub chain per `break-band-vector.md` §1 |
