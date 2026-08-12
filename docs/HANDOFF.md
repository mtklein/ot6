# Facts that are expensive to rediscover

These cost real time to work out the first time. Start with
[README.md](../README.md) for what OT6 is, [CONTRIBUTING.md](../CONTRIBUTING.md)
for the house rules, and [ROADMAP.md](ROADMAP.md) for the release plan.

## Measured facts (do not re-derive)

- **fieldCare drives the real menus and prefers casting to drinking.** It
  walks Item→use→target for a consumable and Skills→Magic→spell→target for a
  cure spell, and it reaches for the bag only when nobody can cast, when the
  MP is short, or when the target is KO'd and wants a Fenix Down. The reason
  is OT6's own rule that level up restores HP and MP in full
  (`ot6_progression.asm:3-6`, called from `battle_main.asm:16251`): MP spent
  in a corridor is refunded and a Tonic is not. Measured at
  gen_ifrit_magicite's stop before battle 70: 3 Potions before, 0 items and
  25 MP after, in fewer frames (143 against 229), because a second cast for
  the same caster never leaves `$3B` while each item use pays a full fade
  round trip. `opts.magic=false` restores the item-only drive for a step
  that wants its MP kept. On the field item list, A picks a slot up; only a
  second A on the same slot uses it.
- **The battle fighter prefers casting too, and the grant behind it is
  battle-only.** `newFightDriver`'s heal branch casts a cure where it can
  and reaches for the bag where it cannot; `opts.cure=false` is the old
  item-only drive. It is spelled `cure` rather than `magic` because that
  driver already spends `opts.magic` on its attack line. Both lines find
  the spell in the actor's **live** battle Magic list (`$302C`,entity is
  the engine's own pointer at it; record 0 is the esper row, record n+1 is
  grid cell n, `+3` is the price `GetMPCost` walks) rather than at a row
  the caller names, because OT6 compacts that list to the party's union and
  then prunes it per character (`Ot6UnionEspers` and
  `Ot6EsperSpellKnown`, `ot6_progression.asm:205`, `:144`), so one spell
  sits at different cells under different loadouts. **Those two hooks are
  on the battle spell-list path only** (`battle_main.asm:14455`, `:14628`):
  a Kirin bearer has Cure in battle and no Magic row at all in the field
  menu, so `fieldCare` cannot cast a granted cure and still drinks. There
  is also no revival by magic anywhere in the WoB — no owned esper grants
  Life (`genju_prop.asm`) — so a segment with no Fenix Down in the bag has
  no answer to a death at all.
- **zMosaic (`$B5`) is never cleared, so "was that refused" is an edge, not
  a level.** `MosaicTask` writes `$17 $27 $37 $47 $37 $27 $17 $07` and
  terminates (`field_menu.asm:3820-3844`); nothing re-zeroes it after menu
  init (`menu_init_2.asm:506`). Measured: 40 frames after a real refusal
  `$B5` reads `$07`. Test `$B5 & $F0`, which is nonzero only while the
  animation runs, or every plan after the first refusal reads as refused.
- **fieldCare's world-map exit is debounced, not fixed at the root.**
  `careBackOnMap` on its own still passes at a moment that is not "world
  module running"; `careClose` is what makes the drive safe, by requiring 30
  consecutive satisfying frames plus "not parked on any menu screen" in
  world mode. Field mode takes the raw first true frame, and debouncing it
  there hangs instead. gen_sabin_gau cares on the overworld and passes.
- **`opts.playBattles="flee"` vs `"tactical"` vs `true`**: fleeing means
  standing still while the formation takes free rounds. Blind-A
  `opts.playBattles=true` stalls or wipes the party on any segment that can
  draw an encounter.
  `M.FLEE_CAP` default 1800, per-call `opts.fleeCap` (the South Figaro
  escape route uses 420). Pincer formations cannot be fled at all, which is
  FF6's own rule, and **the flee reads that off `$b1` bit 1 rather than
  waiting out the cap**: `Cmd_2a` checks that bit first and answers "Can't
  run away!!" (`battle_main.asm:5729-5731`), so once it has held for 60
  frames the fight goes to the tactical driver while the party still has its
  HP. Measured on the Phantom Train's front strip, where a pincer of three
  Bombs held the whole 1800 with the run counters at 20/21/12 against a
  difficulty of 6 and a full party came out at 22/0/39. **A nav step's
  `maxFrames` is a walking budget**, so a route whose maps can draw
  encounters needs an allowance on top of it or the fight expires the step
  and reports a navigation timeout for something that is not one.
  **Whether a map can draw one at all is a data question with an answer**:
  `CheckBattleSub` reads map_prop byte `$0525` and returns on bit 7 clear
  (`ff6/src/field/battle.asm:318`, `:332-333`), which is what makes the
  Returner Hideout (108/109/110), the map-112 passage and the Lete River
  arrival map (113) encounter-free. Say that rather than "these maps carry no
  encounter territory"; a segment that cannot roll one still wants a real
  mode, because the mode is what runs if the assumption is ever wrong.
  gen_banon and gen_lete were the last two steps spelling it `true` and are
  now `"tactical"`: fleeing is wrong there because TERRA is a party of one
  for most of the hideout and BANON is aboard for the rest, and BANON dying
  is a Game Over rather than a wipe (`BattleEnd_03` ->`LoseBattle`,
  `battle_main.asm:12305-12307`, `:16039`).
- **A Veldt battle pays gil and no experience, so no stretch of the route
  can be levelled out of from inside it.** `WinBattle` skips the
  experience accumulation monster by monster while `$11E4` bit 1 is set and
  falls straight into the gold sum (`battle_main.asm:15778-15781`); OT6's
  own reward scale runs after and leaves a zero sum zero, which
  `ot6_break.asm:758-760` already records. The Veldt flag does not touch
  running: `$11E4` is read at `:14150`, `:14211` and `:15779` only, none of
  them the run path, so "these packs are unrunnable" is a fact about a
  formation rather than about the Veldt. If a party ever does need levels
  before Mobliz, the Sabin scenario's own encounter-rolling maps are the
  Phantom Forest (132/133/135) and the Phantom Train (141/142/145/149) --
  decoded from `map_prop.dat` byte +5 bit 7 and the
  `sub_battle_group`/`rand_battle_group`/`battle_monsters` chain -- so the
  Lete River loop (#101) is not the only option and is not upstream-cheap.
- **A world walk that fights its random encounters must be segmented with a
  care stop between battles, or it wipes.** In-battle healing is bounded by
  turns: one Tonic turn restores 50 while a Veldt pack deals more than that
  per round to each of two characters, so a deeper bag cannot fix a heal
  RATE deficit and a field menu between battles can, because it costs no
  battle turns. All three of `gen_sabin_gau`'s Veldt walks wiped a party as
  one continuous drive before being converted, the shore-to-Mobliz transit
  last, on 2026-08-12 at f30934 with 30 Tonics and 9 Fenix Downs still in
  the bag. The converted shape is checkpoint, then N segments of "fight one
  battle, `H.fieldCare`, repeat", behind a three-attempt ladder on a
  17-frame stagger. One wrinkle for a transit whose goal is a town
  entrance: the segment exit must not fire on standing at the goal tile,
  because that tile fires on being entered, and a segment that exits while
  parked on it strands the walk.
- **Rows**: `$B3 = $FF` for every command and only the weapon swing
  clears it, so Tools, Magic, Blitz, SwdTech, Throw and Steal are
  row-exempt. Back row wins where damage is break-driven and loses where the
  chipper is a weapon swing (South Figaro vs Phantom Train, both measured).
  Where **nobody's** chipper is a weapon swing the back row is simply free,
  and worth taking: Number 128 is fought with Tools, Magic and Magic, and
  moving all three back turned a fight that lost attempt 1 with the party
  arriving intact into one that wins attempt 1 arriving worse (#92).
  Rows are persistent state, so set them deliberately per segment.
- **FF6 auto-targets nothing. A drive that does not steer a target has not
  chosen one.** Owner, 2026-08-12: later games in the series pick a sensible
  target for you; this one never does. The cursor opens where the engine puts
  it, which for an item is the acting character, and confirming there aims at
  whoever is holding the menu. This has cost real time once: a comment in
  `gen_sabin_train` claimed a Fenix Down's target select "initializes on the
  fallen ally, so the default confirm revives without steering", and the
  revive branch fired eight times, burned all four Fenix Downs into the
  actor, and left CYAN dead at 0/319 through the boss fight. A comment
  fourteen lines below in the same file had the rule right. **"Default
  target" in a drive's prose means "the engine's pick, unread" — treat every
  one of them as unverified until someone has watched where it lands.**
- **The equip audit** (`tools/audit_equipment.py`, a `make test` check with its
  own only-shrinks story-waiver list): check any red segment against it
  before calling the result balance.
- **Absorb fails the run; null does not, and must not.** The absorb guard
  in `M.run`'s frame callback (`lib/ot6.lua`, `battle_absorbguard.lua` is
  the check) reads the formation's species and everyone's equipped weapon
  once per battle and aborts when an element is absorbed, because then
  every swing heals the enemy — the Cranes, where Optimum's ThunderBlades
  healed a bolt-absorbing boss for up to 943 a swing. Do **not** widen it
  to null. On battle 70 both siblings null bolt and the ThunderBlade pick
  is still correct, because that fight is won by chipping shields and a
  chip goes by weapon **class**; the element-aware equip swapped to
  daggers and lost all three attempts. Random encounters log instead of
  failing (`OT6_RANDBTL`, `ot6_boost.asm:14-29`).
- **Do not use Optimum. Decide what equipment the segment needs and equip
  that** (owner, 2026-08-12). It runs per character and picks by attack power
  and nothing else, and it has produced three separate multi-hour
  investigations: the Cranes (ThunderBlades against a bolt-absorbing boss),
  battle 70 (two characters armed into a nulled element, harmless by luck),
  and TunnelArmr (`5, OT6_PIERCE`, `ot6_hud.asm:1943`), where LOCKE took the
  MithrilBlade at 38 and CELES took the Dirk at 26 — CELES spends that fight
  on Runic and never swings, so no shield was ever chipped and all three
  attempts lost over three distinct seeds. Equip by item, with an ordered
  preference list where a slot has more than one acceptable answer.
- **Equipping a Genji Glove, Gauntlet or Merit Award makes the game run
  Optimum by itself, so "we stopped calling it" is not "it never runs."**
  Backing out of the Relic screen after one of those three changes sets the
  reequip flag (`CheckReequipRelics`, `ff6/src/menu/equip.asm:2834`); the
  message routine reads the mode off Config byte `$1D4E` bit `$10`, Optimum
  by default (`:2804`); and menu state `$6d` then calls `EquipOptimum`
  (`ff6/src/menu/field_menu.asm:310-315`). The blast radius is one character
  — both `EquipOptimum` and `EquipRemoveAll` resolve the target through
  `GetSelCharPropPtr` (`equip.asm:1507`, `:1462`) — and it cannot be avoided
  through the real menu, so a call site equips the relic FIRST and overwrites
  the slots it cares about afterwards. Config option 7 does switch the mode
  to Empty (`config.asm:1048-1058`, drawn at `:767-786`) and the setting
  survives a save (`save.asm:239-241` keeps `$1D4E & $70`; new game clears it
  at `field/init.asm:250`), but Empty means `EquipRemoveAll` strips all four
  gear slots, so it trades a wrong pick for a bare character and every call
  site would then owe four deliberate equips instead of two.
- **A second weapon doubles a character's chip rate under boost, and it can
  add a second break class.** This is a fact about boost, weapons and the
  break loop rather than about any one fight. A chip goes by weapon class,
  looked up per hand per swing (`Ot6WeaponClass` reads `$3ca8,x` with the
  hand in x, `ot6_break.asm:1593-1619`), and `Ot6FightBoost` adds two swings
  per point of pending boost while swings alternate hands and an empty hand
  whiffs (`ot6_boost.asm:481-484`). So at pending boost 1 a one-weapon
  character swings three times and lands two, and a Genji Glove pair swings
  four times and lands four: twice the chips per turn, every turn, in a game
  whose whole loop is chipping shields. Put two weapons of the same class in
  the hands and both chip the same axis; put two classes in and the character
  covers both.
  Measured 2026-08-12 on TunnelArmr (`5, OT6_PIERCE`) from `celes_freed`,
  full-HP parties: two pierce hands took the shields 5 → 1 on the first
  boosted Fight and the party came out with LOCKE untouched at 249/249; one
  hand and a shield took them 5 → 3, needed three turns to break, and came
  out LOCKE 20/249 with CELES dead. The route's glove comes from the Returner
  Hideout and costs the Gauntlet — the two answers there are exclusive
  (`event_main.asm:37019`/`:37092` against `:37834`) — and nothing in the
  tree has ever equipped a Gauntlet.
- **The party-hp audit** (`tools/audit_party_hp.py`, same shape, same kind of
  waiver list) is the other half of that: no fixture ships a party member
  dead, petrified, zombie, poisoned, or at or below max HP / 8. Max/8 is the
  game's own near-fatal line (`battle_main.asm:11544-11549`), and the bar is
  there rather than at half HP because the measured distribution has a wide
  gap — 241 party records across 98 fixtures run 0%, 6.5%, then nothing until
  36.6%. Both audits share one savestate reader, `tools/savestate_party.py`.
  `H.assertPartyStanding` is the same four conditions as a generator exit
  contract, and the two must be changed together.
- **Poison is the one status that walking makes worse, and no HP bar can see
  it coming.** `DoPoisonDmg` (`ff6/src/field/player.asm:551`, called per step
  from `:521`) takes max HP/32 off every poisoned character on every step and
  floors the result at 1 (`:593-613`), so a character who leaves a fight
  poisoned reaches the end of any walk of length at exactly 1 HP, whatever
  they had when the fight ended. Measured 2026-08-12 end to end: a map-98
  formation put status `04` on TERRA, gen_kolts's care stop before VARGAS cast
  her back to 136/136 and left the bit standing, gen_returner's two care stops
  each spent Tonics undoing damage the bit immediately redid, gen_returner's
  own exit contract passed her at 136/136 **because a half-HP bar cannot see a
  status**, and five crossings of the Returner Hideout — a place that cannot
  draw an encounter at all — delivered her to `banon_joined` at 1 of 136.
  `M.fieldCare` clears it (`CARE_STATUS_CURES`, one row today), and the
  Antidote comes from South Figaro's shop 8 row 1
  (`ff6/src/menu/shop_prop.dat` record 8), which gen_kolts now buys three of:
  that counter is the last one before Mt. Kolts and the hideout, so a party
  that leaves it without one has nothing that clears the bit. Every other
  curable status-1 bit is a combat handicap that walking does not compound,
  which is why only poison is in the audit and only poison is in `fieldCare`'s
  cure table.
- **It reads the tracked SRAM checkpoints as well as the fixtures, and two
  things in `build/states` are not fixtures at all.** A checkpoint is the
  other boot source (five states cold-Continue out of one), it is a battery
  image rather than a savestate, and it is tracked in git, so no
  regeneration ever refreshes one: a casualty in a checkpoint keeps handing
  the same corpses down until the file is re-captured. All twelve are clean
  today; the four that were not (`terra-returned-v1` → `narshe-mission-v1`,
  `gate-cave-save-v1`, `n024-entry-save-v1`) were re-cut on 2026-08-12. The
  save slot mirrors the `$1600` table record for record, so the same shape
  signature finds it, resolving at `0x1400` in all twelve. Separately, the
  audits skip `build/states` files that `tools/tests/savestate_graph.py` no
  longer declares: 19 of the 98 there are pre-rename leftovers, and one of
  them, `kefka_doorstep`, was reported and worked as a live casualty for a
  session before anyone noticed that no generator writes it.
- **A checkpoint that hands over a corpse costs the segment its revives, and
  the bill lands boundaries later.** Measured end to end on the 2026-08-12
  re-cut. `n024-entry-save-v1` delivered EDGAR and SABIN dead; the segment
  carried two Fenix Downs; the care stop before battle 72 spent both raising
  them; CELES then died in that fight with the bag empty, and no owned esper
  grants Life in the WoB, so `esper_tubes_entry` shipped her at 0/349. The
  part that is expensive to rediscover is what happened **after** that. The
  two spent revives never came back, so `minecart-platform-v1` was cut with
  8 Tonics and no Fenix Downs (against 16 Tonics, 10 Potions and 2 Fenix
  Downs at `mrf-save-room-v1`), `n128_won` inherited that bag, and battle 71
  killed EDGAR at the Cranes with nothing in the game able to raise him.
  Fixing the source fixed all of it without a single balance change: battle
  70 stopped killing anyone once the fight driver cast CELES's Cures instead
  of drinking, and the restored supply then carried through to the Cranes.
  So when a checkpoint ships a casualty, check the **bag** at every
  checkpoint below it before concluding that a fight is too hard. Nothing in
  the tree audits supplies.
- **The route opens no chests at all, and 94 of them are on maps it
  reaches.** Measured 2026-08-12: every one of the 512 treasure bits at
  `$1E40` is clear in all 98 savestates in `build/states` and all 12
  tracked SRAM checkpoints, from power-on to the deepest link.
  `tools/audit_chests.py` is the check and prints the list by map; the
  scope number is a lower bound, because a map the route only crosses,
  with no fixture on it and no map assertion in its generator, is invisible
  to it (map 72 and its two chests are the known case). Nothing here is a
  balance question until the route stops walking past a Thunder Rod one
  room before TunnelArmr, an Atlas Armlet on Mt Kolts, and a Flame Sabre
  and a ThunderBlade in the Magitek Factory. The chest table's format is in
  `research/data-formats.md`; the two things a naive decode gets wrong are
  that the bit index is nine bits, not eight, and that the unit the game
  tracks is the bit rather than the record, since duplicate map copies
  share one bit and can hold different items.
- **Zozo's random encounters have no reachable break class, and the pool
  out-damages the route party.** Measured 2026-08-12 while `dadaluma_entry`
  and `zozo_clock_solved` were blocking the v0.10 check. Declaring maps 221
  and 225 to `tools/check_break_reach.py` and running it against
  LOCKE/CELES/SABIN/EDGAR reports **all eight** formations of groups 77 and
  78 as NO REACHABLE BREAK CLASS: HadesGigas, Gabbldegak, Harvester and
  SlamDancer each carry an `Ot6ShieldTbl` row with no class key at all (rows
  2091/2094/2096/2099), so no party can break them and every hit lands at
  the shielded halving. Zozo is not a declared area in that checker, which
  is why nothing caught it; the two declared areas are the Magitek Facility
  and the Cave to the Sealed Gate. Runtime cost, same day: one street
  encounter took the tactical driver 6352 frames at full HP, and the
  map-225 stair-room formation (three bodies, 350 HP and two shields each,
  round costs 186/99/137/306 against max HPs of 249/245/280/289) killed a
  four-member party at levels 11-12 having taken no damage at all across
  13200 frames. **Declaring the area would turn `make test` red**, so it is
  recorded here rather than landed.
- **A party that enters a fight below `healPercent` may never get a turn
  back.** The other half of the heal policy, and not a bug in it. When the
  item restores at least what a round costs, `M.healDecision` hands the
  decision to the fraction rule and tops up anyone under `opts.healPercent`
  (`lib/ot6.lua:640-646`). On the Zozo street a round took about 45% of each
  character's max HP and a Tonic restored about the same, so a party
  starting at 28%/62% fell below the threshold every single round and every
  actor spent every turn healing: 29 item and 9 heal plans against 18 Fight
  and 20 skill, 35 of them logged "top-up", and two monsters still at
  350/350 when the 30000-frame budget expired. Nobody died, so nothing
  reported a fight; the run reported a navigation timeout. The same
  encounter at full HP was won in 6352 frames. **A care stop before a walk
  that can draw encounters is what prevents this**, and the entry HP is the
  variable to check first when a nav step burns its budget without a
  casualty.
- **A healthier route levels more slowly.** FF6 divides a fight's experience
  among the survivors, so a chain that stops losing members gains levels
  later: the repaired chain reaches `n128_won` at LOCKE 14 / EDGAR 15 /
  SABIN 15 where the old one was 15/16/16. Nothing asserts a level at these
  boundaries and every contract still passes, but a fight that was tuned
  against the old numbers is being fought a level down.
- **A party wipe must be reported as a wipe, and `M.partyWiped()` cannot
  report one.** Four wipes have now been mistaken for stuck navigators. The
  field half misses it because `$1600` keeps pre-battle HP. The battle half,
  `M.partyWipedInBattle` (`lib/ot6_field.lua:90`), was the filed fix for that
  and cannot fire: its first line requires `M.battleLoadStarted()`, which
  returns true only when some slot of `$3BF4` is above 0
  (`lib/ot6.lua:467-475`), while its own verdict requires every slot with a
  sane max HP to be 0. For any real party those two cannot both hold, so it
  returns true only on a garbage table. Confirmed by construction and by
  measurement: a guarded drive calling `H.partyWiped()` every frame stayed
  silent across 22000 frames of an all-zero table (2026-08-12,
  `dadaluma_entry`). **What a wipe does leave** is all four `$3BF4` words at
  0 with the Game Over event running and control never returning; a live
  menu zeroes the same words, so the event and control clauses are load
  bearing. `gen_zozo4_dadaluma`'s `encounters` helper is the worked example,
  on wipeCanary's own 300-frame debounce. Any drive that is not `navTo`,
  `worldNavTo` or `advanceStory` has no wipe check at all unless it brings
  one (`lib/ot6_field.lua:151`).
- **The fight driver's log goes silent on a wipe, and the silence reads as a
  frozen battle.** Same root cause as the bullet above, one layer up.
  `battleLoadStarted()` calls an all-zero `$3BF4` "not a battle" — its
  documented and accepted limit (`lib/ot6.lua:436-440`) — so the frame the
  last character reaches 0, `rideOut` falls to `F.idle()`, `battleTick`
  resets, and no further `battle f+N` line is printed for the rest of the
  run. The last line printed is the last frame somebody was alive, and it is
  followed by nothing. Read backwards from the log that is a battle whose HP,
  monster HP, shields, menu byte and menu state all stopped changing while a
  driver kept sampling. It is a death. Battle 11 (the South Figaro gate
  soldier) was diagnosed three times as a balance wall and once, on this
  signature, as an unknown teardown mechanism, over six RNG seeds, before
  `probe_battle11.lua` hooked `LoseBattle` and found LOCKE at 0 with
  `$3EE4 = $80` and battle message `$29` "annihilated". **A run of identical
  driver lines ending in silence is the shape of a wipe**; before theorising
  about the battle module, hook `LoseBattle` (`battle_main.asm:16039`) or
  read `$3BF4` yourself. That fight's own loss branch is fine: `LoseBattle`
  sets `$3EBC.0`, which is battle switch `$40`, and `if_b_switch $40` jumps
  when the bit is **clear** (`field/event.asm:4053-4060`), so a set bit falls
  through to `_ca85ba`, the scenario reset on map 75 (47,43).
- **Retry ladders are 3 attempts, and go through `H.newSeedLadder`.** A
  battle's whole RNG stream hangs off `$be`, seeded once at battle init from
  the game-time frame counter: `lda $021e / asl2 / sta $be`
  (`battle_main.asm:6174-6176`), so the phase has period 60 and picks one of
  sixty seeds. `L.spread(n)` holds each attempt until `$021e` has *moved* as
  far as its own phase is away (movement, not an equality test — trap 10);
  `L.report()` reads the seed off the store instruction and fails if
  two attempts drew the same one. The old fixed 37-frame stagger did not
  guarantee that: attempt 1 sat at whatever phase the route happened to leave
  it, and one lead value in sixty put it on attempt 2's seed — a ladder
  playing one fight twice, with no symptom (#83; `battle_seedladder.lua` is
  the check, `probe_ladder_seed.lua` the measurement). Do not widen a ladder
  until it succeeds by chance; a ladder that loses all three attempts is
  reporting a finding.
- **Every saved checkpoint is generated through the game's own save routine,
  never synthesised.**

## Traps

**1. A WRAM cell means what its owning module says it means.** `$7E3BF4` is
the party battle-HP table only while the battle module owns that RAM. `$021f`
has exactly four writers, all menu lifecycle, so forcing `ZMENUSTATE` mid-flow
leaves corrupted menu tasks running and the cell reads as overlaid. Ask which
module owns a `$02xx` cell before trusting it, verify by instrumenting (block
moves are invisible to Mesen write callbacks, so sample rather than set a
watchpoint), and confirm persistent facts through SRAM (`$307ff0`, the codex
pages) when a context-free channel exists.

**2. Cycle budgets are per site, and there is no room left on any of them.**
`Ot6BgHud_ext` runs from `WaitFrame` immediately after `WaitVblank` returns,
once per battle frame, and has under 80 cycles of slack, possibly under 20.
Measured with bare-NOP controls carrying no feature at all: 12 NOPs pass, 80
NOPs fail, and the penalty saturates (20 and 110 cycles both cost the
same 163 frames). The symptom is not a crash or a wrong result. Everything
runs about 10% slower, which flips timing-sensitive tests elsewhere and looks
like a bug in those tests. Keep work there inline at the call site; a `jsr`
into a proc that early-outs is already too expensive.

12 NOPs being safe at that site does not make 12 NOPs safe anywhere else: the
same bare-NOP control in bank `$C2`'s **action** path fails at **nine** NOPs,
so that path's margin is under 18 cycles. The canary is
`battle_trueknight` phase 4b, whose covers span reads 1635 intact and 1798
over.

**Twelve cycles per battle frame is over the cliff on the v0.10 branch.**
Measured 2026-08-11 landing issue #87, at the other per-battle-frame site,
`Ot6RestageGate_ext` polled from bank `$C1`'s frame loop
(`btlgfx_main.asm:1749`). Its idle path is 14 cycles. Shortening its
standing-request path build by build gave 1798 at 40 cycles, 1798 at 33,
1798 at 26, and 1635 only once the request was dropped so that the path
became the idle one. Every build was identical apart from that one proc, so
this is 12 cycles per battle frame flipping the canary and nothing else.
Read it as the budget's remaining slack having been spent since v0.9 rather
than as this site being twice as tight as `Ot6BgHud_ext`: the 12-NOP result
was taken with less OT6 code on the per-frame path. Either way, plan a
per-frame change around making the resting path shorter, because there is no
headroom to spend.

**It is cycles on code that runs, not bytes.** Settled 2026-08-11 landing
issue #66, with the control that had been missing: nine *unreachable* bytes
placed just before `ExecAction`'s label give 1635 and pass, while nine bare
NOPs at `ExecAction`'s pre-dispatch check (`battle_main.asm:274`) give 1798
and fail. Both builds grow `battle_code` by the same nine bytes, to `$652c`,
so bank `$C2`'s size and the code motion of everything after the insertion
point are both ruled out. That also disposes of the old hypothesis here that
only per-battle-*frame* code moves this number; per-action code moves it too,
and the four `$C2` call sites that were added for free
(`battle_main.asm:514`, `:3409`, `:4152`, `:14652`, plus `Ot6RecheckMagic` at
`:14715`) were free for some other reason. The practical rule: a change that
lands here needs to spend fewer cycles on the executed path, not to find a
smaller encoding. Issue #66 shipped one gate site instead of two on that
basis, and moved the surviving one below a test that makes it run rarely. The
`Ot6BgHud_ext` record is the block comment over `OT6_BRKLIVE` in
`ff6/src/battle/ot6_memory.inc`. (This is distinct from the vblank-TRANSFER
budget, which is about VRAM words, not cycles.)

**3. A symbol only reaches `H.sym` if the source spells its name out, and a
duplicate name has to be disambiguated by segment.** Two separate hazards
share this one entry because a probe meets both in the same line of code.

`parse_dbg_syms` (`tools/tests/lib/compose.py:473-540`) no longer takes the
first `type=lab` record: a name defined at two distinct addresses goes into
`OT6_SYMS_AMBIG` instead of `OT6_SYMS`, and `H.sym` raises naming both
segments. So the old silent failure — `ExecCmd` resolving to field code
`$C09B1B` instead of the battle dispatcher at `$C213EA`, an instrumentation
window that never closes, every later event misattributed — now reports
itself. Disambiguate with the ca65 segment: `H.sym("ExecCmd@battle_code")`.
3838 of this ROM's 98483 label names are non-unique, so expect it.

What is still silent is the other half: `compose.py` builds `OT6_SYMS` by
scanning the **source text** for literal `sym("Name")` occurrences
(`:439-449`), so `H.sym(name)` with a variable resolves nothing and raises
"symbol not in ff6-en.dbg — rebuild the ROM" at run time, which reads as a
stale build rather than as a spelling problem. Loop over a table of
`{ label, H.sym("Label") }` pairs, never over a table of strings.

**3a. A Lua syntax error in a test produces no output at all — the run just
burns to the wall-clock cap.** Nothing in `run.log` says "syntax error";
the file loads, registers no callbacks, and Mesen's testrunner kills it at
600 s with the same `code=255` signature as core contention (trap 9). Two
600-second kills were spent on one `end()` that should have been `end)()`
before the cause was found (2026-08-12, `probe_battle11.lua`). The tell is
that **no `[ot6]` line appears at all**, not even `loadState`'s: a run that
reached frame 1 always prints one. There is no Lua binary on this machine to
check syntax with, so bisect against a three-line script that boots a fixture
and logs — that costs about 90 s with `OT6_TIMEOUT=90`.

**4. A mismatched ROM/fixture pair presents as "timeout waiting for main
menu".** Savestates are ROM-coupled. When a fixture was generated from a
different ROM than the one under test, the failure you see is a menu that
never opens, and nothing in the output mentions stale state. If a menu drive
times out and you have recently changed ROM-affecting source, regenerate
before you debug the menu. `tools/worktree-setup.sh` prints a matching warning
when it seeds savestates generated on a different branch.

**5. NPC record order determines NPC identity.** Event scripts address NPCs as
{map, index-within-block}, so a record inserted ahead of an existing NPC
renumbers everything after it. **Append records; never insert them.**

**6. `navTo` lands at rest, so a tile that takes the party away must be
entered with a held press rather than made the goal of a `navTo`.** Position
samples are only valid at rest on a tile
(`tools/tests/lib/ot6_field.lua:459`, `:616`).

**7. `event_main.asm` is a dump of separately-addressed scripts.** Adjacency
in it means nothing. Party composition is runtime state: read `$1850` at a
fixture. `bosses-wob.md` is authoritative on party composition.

**8. `LoadMagicProp` fills one shared buffer.** Freeze the rest of the party
when measuring an ability, or an ally's action inside the measurement window
will read as the summon costing nothing. Documented at `freezeOthers`
(`tools/tests/battle_magicite.lua:232`).

**9. The 600-second timeout makes agents starve each other, though not the
owner.** `nice` fixes contention with the owner's game; it does not fix
Mesen's testrunner wall-clock kill. The signature is several savestates
failing to generate with `code=255` at once while the same ones succeed in
isolation. Lower `-j` and retry rather than debugging the generator. Bound a
full `make savestates` with `NINJAFLAGS=-j4` when other agents are live.

**10. A once-per-frame sample cannot see every value of a once-per-frame
counter.** `$021e` is ticked at the very end of the owning module's vblank
handler (`field/reset.asm:286`, after every transfer `FieldNMI` performs), and
that handler is long enough to finish either just inside the emulated frame or
just past it. Measured 2026-08-12 on map 75: the ticks ran at scanlines 247,
257 and then 1 of the following frame, straddling scanline 0 — which is where
`M.run`'s `startFrame` callback samples. Frames therefore held 2, 1, 0, 1 ticks
on a stable four-frame beat, and every phase congruent to 3 mod 4 was written
and overwritten inside one frame. 180 ticks in 180 frames, a quarter of the
values never present when the harness looked. A `read() == wanted` wait on any
counter the game ticks per vblank can hang forever on a value the counter
really does pass through; wait on accumulated movement instead. This cost
sfigaro_town a regeneration, reported as "$021e is not advancing here".

Also measured, and cheaper to read here than to rediscover: capture-calm does
not imply reload-calm, so every generator reloads its own capture and
verifies; a stale seeded fixture looks exactly like a product bug, so run
`--check-states` first; the battle Item cursor is a sum (`$8947` scroll +
`$894F` row); command row zero is not universally Fight; concurrent worktree
suites can SIGTERM each other's Mesen runs, so stagger the heavy runs, `nice`
everything, and keep to one heavy run at a time per machine.

## Canonical facts you should not re-derive

- **The fixture party is LOCKE, CELES, SABIN, EDGAR** (four through the
  Facility, three once the tube room takes Celes), measured at each fight's
  entry point in `design/wob-route.md`; the post-opera checkpoint's entry
  contract counts the `$1850` assignments, so a chain that loses members
  fails with an error rather than continuing.
- **Map 323 is Albrook; Vector is 242 and 253** (`design/vector-route.md`,
  both title index 49).
- **The item equip mask is `item_prop_en.dat` offset `+$01`, 16-bit, bit N =
  actor N** (`research/data-formats.md`). Byte `+$00` also looks like a mask
  and always claims Terra.
- **`monster_prop.dat` `+23` is absorb, `+25` is weak** — `check_boss_rows.py`
  and `check_break_reach.py` enforce doc/data agreement inside `make test`.
- **`OT6_BREAK_TICKS` is `$10`** (`ff6/src/battle/ot6_break.asm:1`) and gives
  a **2159-frame** window, about 36 s, not roughly one turn.
- **There are six multi-hit abilities in the game:** vanilla's Quadra Slam
  ×4, Quadra Slice ×4 and Empowerer ×2, plus v0.10's Pummel ×2, Bum Rush ×4
  and Drill ×2 (`Ot6HitCountTbl`, `ff6/src/battle/ot6_hitcount.asm`).
  `tools/audit_multihit.py` checks this and fails if it changes. **Hit count
  is authored in that table, not in the `.dat` files**, and each ability's
  power is divided by its count through a named splice, so reading a power
  byte out of `magic_prop_en.dat` or `item_prop_en.dat` gives the vanilla
  number rather than the shipped one.
- **SwdTech has a 1-BP floor**; there is no 0-BP tier. `Ot6BushidoTech`
  (`ff6/src/battle/ot6_bushido.asm:92-94`) clamps a stray 0 up, and boost 1/2/3
  selects Cyan's *top three learned* techs, so a given tier's price slides as
  he learns more.
- **A poison DOT tick chips a shield; Sap does not.** A tick is an ordinary
  poison hit with no attacker and chips exactly one axis. A broken monster
  takes no ticks at all.
- **The `event_triggers` fixed block has room for 2 more triggers
  game-wide** — 13 trailing `$FF` bytes in the block at `C40000`+`$1A10`, and
  a trigger is 5 bytes. (`npc_prop` has 76 trailing bytes ≈ 8 more NPC
  records, an upper bound, since an NPC record's last byte could legitimately
  be `$FF`.) Any further save-point work needs segment relocation first
  (`design/save-points-vector.md` §1).
- **The suite is self-registering**, discovered from each test's `-- @suite`
  marker; `tools/tests/suite.sh --list` reports what runs. Tests that load a
  deep story savestate join once `make savestates` has generated it.

## Working agreements

- **Work on `main`.** It carries our best latest work and gets no special
  protection; there is no long-lived integration branch to accumulate on.
  Land agent branches onto it as they are reviewed (owner, 2026-08-12,
  replacing the rule that said otherwise).
- **Cut `release/v0.x` when the release starts, not when it ships.** Do it
  while the release is still being decided, because reconstructing the point
  it should have branched from is guesswork afterwards. The branch is what
  receives a cherry-picked fix; the tag only names a commit and cannot take
  one, so a tag alone is not enough. Nothing is ever held back from `main`
  to feed a release.
- Delegated work gets [agent-brief.md](agent-brief.md) included by reference.
  **Cite the copy in the agent's own worktree**, never the owner's checkout,
  which can be on a release branch and weeks stale.
- Agents commit to their own branches in revertible units, file exclusivity is
  "declare your hunks and expect merges", and regenerating a single savestate
  (`ninja -f build/build.ninja <state>`) is theirs. The full `make savestates`
  chain stays with the dispatcher.
- Agents report follow-ups; the dispatcher files issues.
- Parallel work goes in separate git worktrees; `tools/worktree-setup.sh`
  seeds the ROM, emulator links, states, and the ninja build log. **Worktrees
  live under `.claude/worktrees/<name>` inside the repo**, never as siblings
  of `~/ot6` or anywhere else in the home directory.
- **Close a bug as soon as it is fixed**, not when the fix ships. The
  milestone records which release carries it, so the issue does not have to.
  Close it with the plain explanation of what was wrong and what was
  measured, which is the part that was always worth doing (owner,
  2026-08-12, retracting an earlier rule that said to wait for the release).
- Commit messages here run long and explain why the change was made,
  including what was ruled out. Match that.

## The most common failure mode

Nearly every wrong turn in this project has been the same one: reasoning used
in place of looking, when looking was cheap. The two most expensive cases both
read an absence as information. One was a symbol lookup that returned the
wrong module's address without reporting an error, so an instrumentation
window never closed and every later event was attributed to it (trap 3). The
other was a design table that stated intent as shipped fact for months because
nobody had enumerated the records. One grep or one audit script would have
settled either.

If a conclusion requires believing a documented measurement is wrong, the
instrumentation is more likely to be at fault than the record. Verify with the
cheapest available look: a probe, a byte read, a re-run. Prefer the mechanical
checks to reasoning: the state-write checker and its only-shrinks list, the
equipment audit, `compose.py --check-states` before debugging any red test,
the runtime write guard, and `make savestates NINJAFLAGS="-k 0"` to enumerate
blockers rather than hitting them one per run.

The rules in CONTRIBUTING under "Prove the code is correct" exist because of
specific incidents.
