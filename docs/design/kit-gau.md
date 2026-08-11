# Gau — the hunter's stable: learn many, equip 8

Gau's kit under the **Ochette model** — Veldt learning stays unlimited, the
battle menu offers an 8-slot loadout — plus the Dance-model MP rule and the
chance-verb boost ladder for Rage. The learn-many/equip-8 shape is
**owner-settled, not a proposal**.

**Canon boundary.** Vanilla Rage is the baseline and survives almost whole:
the menu picks a beast, Gau is possessed for the rest of the battle, and every
possessed turn is a 50/50 between Fight and the beast's special
(`Cmd_10`, `ff6/src/battle/battle_main.asm:3351-3371`; the coin at
`:1001-1003`). What changes is exactly three things: the battle list shows a
curated 8 instead of everything he knows; the possession is priced (flat, once,
at Rage-start — the Dance model); and boost buys certainty on the coin (the
chance-verb canon, `DESIGN.md`'s "BP economy").

**Evidence rule (CONTRIBUTING.md).** Every mechanical claim cites the file and
line it was read from, or is labelled **UNVERIFIED**.

---

## Summary of rulings

| question | ruling |
|---|---|
| Collection | unlimited, untouched — `LearnRage` keeps filling the `$1d2c` bitfield (`battle_main.asm:12334-12348`) |
| Equip | **8 slots**, one byte per slot, configured in the field under Skills → Rage (the Bushido-configurator pattern at 8 rows) |
| SRAM | **8 bytes at `$1e1f-$1e26`** — the same save-block scrap the Bushido word lives in; zero-sentinel = AUTO; **no `persistent_layout` bump, zero anchors regenerated** (§4, the tradeoff table) |
| Battle read | one choke point: `InitSkills`' `$257e` list build (`battle_main.asm:14659-14679`) filters through the loadout; the vanilla Rage window, cursor, scroll and confirm are untouched (§3). **AUTO truncates to eight too — the wall is not reachable by inaction (§8.0)** |
| MP | **flat 8 MP at Rage-start**, whole-battle possession, mid-trance turns free — one price rule for both possess-verbs (Rage and Dance) (§5) |
| Boost | 0 BP vanilla coin; 1 BP special ¾; 2 BP special 15/16; 3 BP the special **every turn for the whole trance** — latched at `Cmd_10`, the Slot-latch pattern (§6) |
| Boosted Leap | **no rider** — Leap's learn step has no roll to convert; it re-opens if the return-cadence roll is located and playtest wants it (§6.3). **Leap is free** (§5) |

---

## 1. Identity — the hunter

Gau is the game's collection character, and vanilla already built the whole
loop: he learns nothing from levels, items or story — only from hunting.
`LearnRage` (`battle_main.asm:12334-12348`) sets one bit per species in the
`$1d2c-$1d4b` bitfield at the end of a Veldt return, and the Veldt formation
pool makes nearly everything in the game huntable eventually. That loop — see
a beast, want it, go get it — **is** Gau, and this design does not touch it:
no cap on learning, no curation of what the Veldt teaches, no change to Leap's
ritual (§6.3).

What vanilla got wrong is the payoff surface: 200+ learned rages arrive in the
battle menu as an unsorted, unsearchable wall (two columns, scroll position
capped at `$7c` — `btlgfx_main.asm:20238-20240` — i.e. built for a list of
hundreds), and the one that matters is 40 button-presses away while the ATB
runs. The Ochette model splits the two games apart:

- **The collection game** stays unlimited and happens on the Veldt — the
  hunter's album, a completionist's pleasure.
- **The preparation game** is new and happens in the field menu: *which eight
  do you carry tonight?* Eight is enough to cover roles (a healer beast, an
  element per pocket, a status special, a big dumb special) and few enough
  that each slot is a real decision — the same "curating IS the identity"
  argument `kits.md`'s organizing principles already make, at the slot count
  the owner named.
- **The battle game** is vanilla possession: pick one of your eight, pay once,
  and ride the beast until the fight ends. The loss of control is the verb —
  the same ruling Dance made ("that loss of control IS the dance",
  `kits.md`'s Mog sketch).

Eight also matches every other kit's list length ("reshapes the lists to
exactly 8", `kits.md`'s organizing principles): Gau's battle menu becomes
exactly as long as Sabin's, and the fact that HIS eight are chosen from
hundreds is the identity doing the differentiating, not the menu shape.

Gau is already in the supported frontier: the s2 (Sabin scenario) chain
carries him — rung `gau_joined`, minted by `gen_sabin_gau`
(`tools/tests/frontier_graph.py:190-197`), and `gen_sabin_gau` sits in the
smoke set (`Makefile:200`). Natural-boot coverage rides that rung (§9).

---

## 2. The loadout machinery fit — what Bushido built, what 8 slots needs

### 2.1 What the Bushido implementation provides

The Bushido loadout is a complete, shipped instance of exactly this feature at
4 slots, in three layers:

1. **Storage**: one packed word at `$7e1e1d` (`OT6_LOADOUT`,
   `ot6_memory.inc:38-40`), inside the working-save block `$1600-$1fff` that
   `save.asm` round-trips per slot (`save.asm:69`, `:97`) and
   `CalcSaveSlotChecksum` covers (`$1600-$1ffd`, `save.asm:750-771`). Word 0 =
   AUTO — the sentinel doubles as the zero-migration path, because every
   pre-existing save already reads 0 there (`ot6_kits.asm:4-26`).
2. **Bank-F0 logic, shared by menu and battle**: unpack
   (`Ot6LoadoutUnpack`, `ot6_kits.asm:932`), learned-validation
   (`Ot6TechLearned`, `:906`), per-slot resolution with auto fallback
   (`Ot6LoadoutSlotTech`, `:960`), assign/cycle/seed/revert
   (`:985/:1064/:1024`, input walker `:1103`), and pricing
   (`Ot6LoadoutCost`, `:1167`). The battle read is a single branch at the top
   of the shared leaf (`Ot6BushidoTech`, `ot6_kits.asm:57-77`), so menu and
   battle can never decode the word differently.
3. **A thin C3 shim**: `SkillsOption_02` repointed from the vanilla browse
   list to the configurator (`field_menu.asm:1164-1186`), menu state `$7b`
   (`MenuState_7b`, `field_menu.asm:2696-2716`) doing only tilemap/cursor/DMA
   framework — cursor prop `{1, 4}` over four rows, four `cursor_pos` entries,
   name+cost draw per row (`field_menu.asm:2865-2879`, `:2754-2780`).

### 2.2 What widening to 8 slots (and 255 candidates) changes

Gau's numbers break the *packing*, not the pattern. Cyan has 8 techs → 3 bits
a slot → one word. Gau has rage ids 0-254 (the `InitSkills` list walk writes
ids 0..254 and stops at `$ff`, `battle_main.asm:14676-14678`; `LearnRage`
skips monster index > 255, `:12336-12337`) → **one byte per slot, 8 bytes**.
Encoding: **stored byte = rage id + 1; `$00` = unset**. An unset slot resolves
by the same per-slot fallback Bushido uses for an unlearned stored tech
(`ot6_kits.asm:73-74`); all-eight-zero = AUTO, which every existing save and
anchor already reads (§4, measured). Ids 0-254 map to $01-$ff with no loss —
id 255 is unlearnable in vanilla, so nothing real is outside the byte (§10.6).

Per machinery layer:

- **Battle list — the one read that changes.** The battle Rage window never
  reads the learned bitfield itself; it renders and confirms out of the flat
  list at `$257e` that `InitSkills` builds once per battle from `$1d2c`
  (`battle_main.asm:14659-14679`; draw `btlgfx_main.asm:11084-11102`; confirm
  `:20261-20272`, which takes `$257e,x` and refuses `$ff`). **That build loop
  is the single choke point**: write only the eight the hunter carries — the
  stored, still-learned ids when any loadout byte is nonzero, otherwise AUTO's
  first-eight window (§8.0) — set the count `$3a9a`
  (`:14674`), and `$ff`-fill the rest of the `$257e-$267d` region (256 cells;
  the dance list starts at `$267e`, `:14656`). Everything downstream is
  untouched and self-consistently narrowed: the window draws ≤8 names and
  blanks (`$ff` rows already draw blank — the confirm refuses them,
  `btlgfx_main.asm:20264-20266`), the scroll cap `$7c` never engages, and
  even the *random*-rage fallback (a muddled/unset rager: `RandRage`'s pick
  over `$3a9a`/`$257e`, `battle_main.asm:987-999`) now rolls over the eight
  the player prepared — the confusion gamble respects the loadout for free.
  No cursor table, window template, or btlgfx edit is needed **at all** on
  the battle side.
- **Field configurator**: `SkillsOption_05` (the vanilla Skills → Rage browse,
  `field_menu.asm:1323-1359`, menu state `$1d` over `InitRageList`,
  `skills.asm:1477`) is repointed exactly the way `SkillsOption_02` was. The
  new screen is `MenuState_7b`'s twin, with cursor prop `{2, 4}`: two columns
  of four on odd rows at vanilla's 12px pitch (§8.0b), one name row per slot.
  Two deltas from
  Bushido: names come from `MonsterName` via the rage browse's own plumbing
  (`GetMonsterNamePtr`, `skills.asm:1557-1565`) instead of `BushidoName`;
  and the "pool" cannot be a drawn grid (255 candidates vs Cyan's 8), so
  the L/R cycle-through-learned IS the browse — the Bushido cycle walks 8
  residues (`Ot6LoadoutCycleCore`, `ot6_kits.asm:1064-1087`), Gau's walks
  the `$1d2c` bitfield for the next/previous set bit. A "LEARNED nnn"
  counter replaces the pool grid (the collection score, drawn where
  Bushido draws "LEARNED").
- **F0 logic**: same proc family, byte array instead of packed word —
  `Ot6RageSlot` (read+validate, auto fallback), `Ot6RageLearned` (bit test
  against `$1d2c` — the field-side twin of the battle build's own test),
  assign/cycle/revert. Menu and battle share the same F0 leaves, the
  invariant that kept Bushido's two readers honest.
- **Cost display**: the flat trance price is drawn once, on the page's title
  row, through the `Ot6LoadoutCost`/`Ot6LoadoutDrawCost` pattern
  (`field_menu.asm:2772-2774`, `:2831-2860`). The price is uniform by design
  (§5), so one copy teaches the whole rule — and two columns of names leave no
  room for a per-row price field (§8.0b).

**AUTO's definition** (needed the moment the sentinel exists): the first eight
known rages in id order — i.e. the head of the vanilla list `InitSkills`
already builds. Not "most recently learned" (needs storage that doesn't
exist), not "strongest" (needs a judgment call the machinery can't make).
A fresh Gau with ≤8 rages is byte-for-byte vanilla under AUTO; past eight AUTO
truncates, deliberately (§8.0).

---

## 3. Where the trance itself lives (read, not changed)

The possession machinery this design deliberately leaves alone:

- `Cmd_10` (`battle_main.asm:3351-3371`): latches the chosen beast into
  `$33a8,y`, sets the RAGE status (`$3ef9,y |= $01`, `:3364-3366`), loads the
  beast's properties (`SetRage`, `:1015-1031`), and **immediately executes the
  first possessed action this same turn** (the `_c21554` tail, `:3370`).
- Every later turn routes command $10 through the action-setup path at
  `battle_main.asm:12890-12897` into `RandRage` (`:977-1009`), whose
  `RandCarry`+`rol` (`:1001-1003`) is the 50/50 between the beast's two
  authored attacks — entry 0 always Fight, entry 1 the special
  (`make_monster_rage`, `ff6/src/battle/monster_rage.asm:3-5`; table at
  cf/4600).
- The trance ends only with the battle or the body: rage is stripped on
  death/battle-end (`RemoveStatus_18`, `battle_main.asm:11572`; the `$eefe`
  battle-end mask, `:12371`).

---

## 4. THE SRAM RULING — 8 bytes at `$1e1f`, no layout bump

The 8 loadout bytes must persist per save. Three candidate homes were weighed;
the decisive evidence is **how the Bushido word itself got in** and **what the
tracked anchor fleet actually holds**.

### 4.1 The precedent

The Bushido loadout sits in unused bytes inside the checksummed save block,
with an all-zero sentinel meaning AUTO — "zero migration (every existing save
reads `$1e1d..$1e1e` = `$0000` = AUTO)" (`ot6_kits.asm:7-8`). The
`persistent_layout` string `ot6-codex-o8-v1`, declared by every real anchor
(`tools/tests/anchors/*/manifest.json`) and by every consuming leg
(`OT6_ANCHOR_LAYOUT:` markers), was coined for a world that already contained
the loadout word. The precedent is therefore exact: **a zero-sentinel addition
to the save-block scraps is not a layout change**, because no existing byte's
meaning changes and no old anchor can be misread.

### 4.2 The scrap, verified

`$1e1d-$1e3f` (~35 bytes) is documented free save-block space
(`docs/research/ram-and-rom-space.md`, the madsiur survey). Bushido holds
`$1e1d-$1e1e`; **`$1e1f-$1e26` is the next eight**.

- No code in the tree references `$1e1f-$1e26` (grep over `ff6/src`; the only
  hits are local branch labels named `@1e1f` etc.).
- The checksum window covers them (`$1600-$1ffd`, `save.asm:750-771`), and the
  per-slot round-trip copies them (`save.asm:69/:97`) — persistence and
  validation for free, the same free ride the word gets.
- **All 11 tracked anchors, all 3 slots each, read `$1e1d-$1e28` all-zero**
  (payload scan of `tools/tests/anchors/*/`). The zero-sentinel migration
  story is not an argument — it is a property the fleet demonstrably has.

### 4.3 The tradeoff table

| | (a) layout bump + regenerate | (b) codex-page tail | **(c) save-block scrap `$1e1f` (Bushido pattern)** |
|---|---|---|---|
| Bytes | anywhere (schema is being re-cut) | `OT6_CODEX_ROOT+page+$310..$317` (page = `$400`, used = `$310`: `ot6_memory.inc:24-36`) | `$1e1f-$1e26` |
| Anchor cost | **9 real anchors** (11 tracked minus the two negative fixtures) regenerated through real Save UI drives, in dependency order — effectively a frontier re-mint, the multi-hour cost leg-fixtures.md was written to stop paying, plus every leg's `OT6_ANCHOR_LAYOUT` marker and manifest edited | none *claimed* — but see honesty row | **zero** (measured zeros decode as AUTO — the exact semantics those saves had) |
| Checksummed / save-slot semantics | designer's choice | **no**: codex pages sit outside the `$1600-$1ffd` checksum, and codex writes are immediate — a loadout there would survive a reset-without-save, unlike every other menu decision in the game | **yes**, both, for free |
| Init guarantee | designer's choice | **none for the tail**: `Ot6CodexEnsure` wipes only `$300` bytes from `+$10` (`ot6_codex.asm:129-132` and siblings) — the tail is never initialized by any code path. Anchors happen to hold zeros there (measured), but that is the emulator's SRAM fill, not a contract; real-hardware SRAM is undefined, so the tail needs its own sub-signature to be safe | New Game zeroes the save block; sentinel = the uninitialized value (`ot6_kits.asm:18-22`'s argument, and §4.2's measurement) |
| Layout-string honesty | honest by construction (that is its whole cost) | **cannot honestly stay**: `ot6-codex-o8-v1` names the codex page layout *specifically*; claiming tail bytes changes exactly the thing the string versions, so this option quietly converges on option (a) anyway | stays honestly: the string's contract is "refuse an anchor the leg would misread" (`sram_anchor.py:22-33`, `leg-fixtures.md`'s "Costs, named"), and no v1 anchor can be misread — zeros are AUTO, the state those saves are genuinely in |
| Precedent | `leg-fixtures.md` names the path but calls it "deliberate", for real schema breaks | none | **the Bushido word itself** |

### 4.4 The ruling

**Option (c): `OT6_RAGELOAD := $7e1e1f`, 8 bytes, byte = rage id + 1, `$00` =
unset, all-zero = AUTO. `persistent_layout` stays `ot6-codex-o8-v1`. Zero
anchors regenerated.** With `ot6_memory.inc` asserts pinning the range inside
`$1600..$1ffd`, exactly as the word's asserts do (`ot6_memory.inc:39-40`).

Two honesty riders:

1. The scrap budget is now `$1e27-$1e3f` (25 bytes) plus `$1e70-$1e7f` —
   finite. When it runs out, option (a) is the honest path; leg-fixtures.md's
   regenerate-and-migrate discipline exists for that day, and spending 8 of 35
   bytes on a headline kit is what the scrap is *for*.
2. `persistent_layout` versions the *schema*, and this ruling extends the
   schema compatibly rather than changing it. If the dispatcher prefers the
   strict reading ("any new persistent byte bumps the string"), the bump can
   ride option (c)'s bytes unchanged — the cost is only the 9-anchor
   regeneration, not a different design. Recommended: no bump, matching the
   word's own precedent; the leg-entry invariant contracts (`leg-fixtures.md`,
   "The invariant contract") gain a "rage loadout" row either way.

---

## 5. MP — the Dance model, one price for both possess-verbs

**Ruling: Rage costs a flat 8 MP, charged once at Rage-start; every possessed
turn after is free; death ends the trance and a re-Rage pays again.**

Why flat, in one paragraph: the possession is one decision and vanilla's lock
makes it one *purchase* — "one payment starts a whole-battle state — vanilla's
can't-stop-dancing lock is preserved, so the price is per battle, not per
step" is `mp-economy.md`'s Dance row in "The verb survey", and one pricing
rule governs both possess-verbs. A principled per-rage formula (price by the special's spell cost) was considered
and rejected on three counts: it double-charges — the trance's real price is
the surrendered control, already paid, and the special is only *rolled*, not
chosen per turn; it inverts the collection's joy — the rarest hunts would
carry the ugliest prices, taxing exactly the album pages the collection game
exists to celebrate; and it needs a 255-row price surface where the flat rule
needs one number on every row (§2.2's display note). 8 sits in Dance's own
4-10 band at the top half — Rage's stable is broader than Mog's eight dances,
so it prices at the band's ceiling-adjacent rung, not above it — and it is
~20% of Gau's join-era pool (base 10, `mp-economy.md`'s "Early pools", plus the
universal pool): a real commitment, never a lockout, and cheap next to a 40 MP
divine because the payment buys a *gamble*, not an apex. If Dance ever lands
on a different number inside 4-10, **Rage follows it** — the rule
("possess-verbs share one flat price") outranks this paragraph's 8.

Mechanics, in the shipped machinery's terms: `Ot6AbilityCost`
(`ot6_boost.asm:403-433`) gains a `$10` arm beside Steal's flat arm — if the
actor's RAGE status bit is already set (`$3ef9` bit 0, the bit `Cmd_10` sets
at `battle_main.asm:3364-3366`), return 0 (mid-trance turn); if clear, return
the flat price (this is the Rage-start action). Charge and refusal are already
universal downstream (the `$3620`→`$3a4c` subtract and its fizzle,
`mp-economy.md`'s "Where it lands"), so the refusal surface is the standard
one: a Gau under 8 MP is refused the start, never silently freed, and the mid-trance
zero-charge holds across a multi-turn trance exactly as Dance specifies.
`.if OT6_MP_COSTS` gates it all; the nomp baseline is undisturbed.

**Leap is free**, by owner ruling, and it is the exception to "only the basic
Fight command is free" (`mp-economy.md`'s "Principles"). Two reasons, both about
surfaces: a price on Leap **cannot be displayed** anywhere (Leap is a
top-level command row, and that window draws a name and a disabled-flag colour
and nothing else — `command_window_data_set`, `btlgfx_main.asm:10099-10125`;
the only way to meet a number would be a refusal after the turn was spent, and
that path composes no number either), and Leap **shares the FIGHT row** on the
Veldt (kits.md's row-sharing rule), so pricing it would reopen the
free-action hole in Gau's own territory. `Ot6AbilityCost` has no `cmd $11`
arm; the verb falls out of the chain with vanilla's own 0. Steal's flat 2
stands.

---

## 6. Boost — the chance-verb canon, Dance-shaped

**Canon** (`DESIGN.md`'s "BP economy", `ROADMAP.md`'s design canon,
`kits.md`'s "chance-verb family"): on chance verbs boost buys certainty in
the verb's own vocabulary. Rage's vocabulary is
one coin — `RandCarry` + `rol`, "1/2 chance first or second attack will be
chosen" (`battle_main.asm:1001-1003`) — rolled fresh every possessed turn.
The beast is *chosen* (the menu did that); the gamble is which half of the
beast shows up. So BP tilts the coin, for the whole trance:

| BP | the coin | odds of the special |
|---|---|---|
| 0 | vanilla to the byte — `RandCarry`, untouched | 1/2 |
| 1 | special unless `Rand < $40` | 3/4 |
| 2 | special unless `Rand < $10` | 15/16 |
| 3 | **no roll — the special, every turn, all trance** | 1/1 |

Each point roughly quarters the miss odds (1/2 → 1/4 → 1/16 → 0), the same
converging ladder Steal shipped (+40/+90/clamp, `kits.md`'s "Boost-tiered
Steal"). The tilt is toward entry 1 (the special) because entry 0 is always plain Fight
(`monster_rage.asm:3-5`) — nobody spends BP to punch more predictably.
Exact thresholds are M6's to tune; the mechanism is one threshold compare.

### 6.1 The latch — Slot's pattern, whole-trance duration

BP is spent once, at the Rage-start action, through the normal
`Ot6ActionEnd` consume — but the *tier* must outlive that action by the whole
battle. This is Slot's problem solved again at longer range: Slot latches the
spin's tier at the first A press (`Ot6SlotRig` → `OT6_SLOTTIER` at `$57ba`,
`ot6_kits.asm:1490-1530`, `ot6_memory.inc:59-64`) so the charge and the reels
can never disagree. Rage copies `OT6_BOOST_REVEALED,x` (capped 3) into
**`OT6_RAGETIER`** — the `$57bb` spare of the same init-exempt strip.
Staleness is harmless by Slot's own argument: the cell is read only while a
RAGE status is set, and the only writer of that status (`Cmd_10`) always
rewrites the latch first. One byte suffices while Gau is the only Rage user; a
second user (Gogo, WoR) is the widen-to-per-character moment (§10.7).

**The latch lives at TWO sites, and both are load-bearing.** `RandRage` has
two callers: `Cmd_10` (`battle_main.asm:3351`, before the `_c21554` tail fires
the first possessed action) covers every later turn, but the *start* turn's
attack is rolled by `FixPlayerAttack`'s cmd-`$10` arm (`battle_main.asm`
@4dec) at action LOAD, before `Cmd_10` exists. Latch at `Cmd_10` alone and the
very turn the BP was spent on is the one turn it does not buy — a 3-BP Rage
would be a coin flip on its headline turn. Both sites are idempotent on the
start turn because the pending byte is not consumed until `Ot6ActionEnd`.

The roll hook replaces `RandRage`'s `jsr RandCarry / rol` pick
(`battle_main.asm:1001-1003`): tier 0 runs vanilla's own coin, byte-identical.

### 6.2 The no-double-dip gates

- **`Ot6BoostDmg` gains a `$10` gate** beside Steal's `$05` and Slot's `$0f`
  (`ot6_kits.asm:1215-1234`): a rage action never takes the ×2/×4/×8
  multiplier. This is load-bearing on the *start* turn — `Cmd_10` executes the
  first possessed action while the pending boost is still live (`:3370`), and
  without the gate a 3-BP Rage-start would buy the guaranteed special AND
  multiply it: exactly the double-dip `kits.md`'s "Boost-tiered Steal"
  rules out.
- **Mid-trance turns touch no boost machinery at all**: no fold, no
  multiplier, no `Ot6ActionEnd` consumption beyond vanilla's. A possessed Gau
  has no menu, so no pending boost ever arises on his auto-turns; BP he regens
  during the trance banks, unspendable until the next battle's Rage-start
  (§10.8 — an honest cost, and Cyan-adjacent: banking with a purpose).

Deterministic A/B evidence follows the `battle_slots.lua` discipline
(`tools/tests/battle_slots.lua:28-50`): same drive, one pending byte
different, the pick cells asserted at the tier boundaries with pinned Rand,
write-callbacks attributing every store to bank `$f0` or `$c1/$c2` (§9).

### 6.3 The boosted-Leap rider — recommended against, for now

The rider would be: boosted Leap = guaranteed capture. Read against the
source, it has nothing to buy where it aims:

- **Leap's learn step is already certain.** The leap needs ≥2 present
  characters and the Veldt (`TargetEffect_54`, `battle_main.asm:9719-9735`;
  Veldt flag `$11e4`, `:14016-14020`), and the end-of-battle event learns
  **every** species present, no roll (`BattleEnd_02`→`BattleEnd_05`→
  `LearnRage`, `:12172-12186`, `:12334-12348`). "Guaranteed capture" would
  guarantee what already happens.
- **The only gamble is the return cadence** — when Gau reappears
  (`GauAppears`, `:12159-12166`; the appear gate `:12081-12090` and
  `:7928-7936`, char AI `$0a`). Whether that cadence is random per Veldt
  battle or deterministic once the party has a slot free is **UNVERIFIED** —
  the gate reads `$11e4` bit 0, whose field-side writer is unread. That read
  is the rider's real prerequisite.

**Leap ships vanilla and the rider is deferred.** If the return-cadence roll
is located and playtest finds the wait frustrating, the honest rider shape is
*boost shortens the absence* (1-3 BP → sooner/next-battle-guaranteed return) —
certainty in Leap's actual vocabulary, which is absence, not capture. Until
then Leap joins Break and Doom in the boost-inert ledger (§10.5): the UI
accepts a spend that buys nothing, the known canon gap
(magicite-tube-six.md §13.4), not a new one. Reshaping Leap into an in-battle
Capture roll (the superseded `Leap→Capture ✦` sketch) is rejected: it would delete the
leap-and-return ritual the owner's "the collection game IS Gau" framing
protects.

---

## 7. Balance notes

- **The slot fight is Gau's own menu now**: 8 slots against 200+ candidates is
  the entire tuning surface, and it self-balances the trash/boss split (carry
  a healer beast and you carried one fewer nuke). M6's measurement is
  wear-time per rage across the s2-band fixtures — the magicite-tube-six §10.3
  discipline pointed at loadout slots instead of stones. Unmeasured.
- **3 BP + the right special is the headline buy** and it is priced twice:
  3 BP (a full bank, Octopath's no-regen rule biting the next turn) AND the
  8 MP trance price AND the control loss. A guaranteed Aqua Rake every turn at
  Baren Falls-era power is strong; the levers, in order, are the tier
  thresholds (§6's table), never the loadout width and never the flat price
  diverging from Dance's.
- **The confusion interaction is free depth**: a muddled unset-rager rolls a
  random rage *from the loadout* (§2.2), so preparation even disciplines
  Gau's failure modes.

---

## 8. Where the machinery lives

### 8.0 AUTO truncates to eight

**AUTO = the first eight known rages in id order, in battle as well as in the
field menu.** `Ot6RageList` builds the list on both arms and always returns
carry set; the vanilla `$1d2c` walk below the `InitSkills` call site is
unreachable from that site and stays only as the reference
`battle_rage.lua`'s explicitly-labelled equivalence arm measures against. A
default that handed back to the vanilla walk would put the 200-entry wall in
front of anybody who never opened the configurator — the precise thing the
feature exists to remove — so **the wall must not be reachable through
inaction.**

What this does **not** change:

- **The collection is untouched.** `LearnRage` and the `$1d2c-$1d4b` bitfield
  are exactly as vanilla left them; the field page still cycles every species
  hunted, and the LEARNED counter still shows the whole album. Only the eight
  the hunter *carries* are capped.
- **Migration.** All-zero means AUTO, so no save, anchor, or
  `persistent_layout` string moves (§4 stands whole).
- **Equivalence, stated precisely.** §2.2's "a fresh Gau with ≤8 rages is
  byte-for-byte vanilla under AUTO" holds *within the window* and is measured
  as its own arm; past eight, AUTO deliberately diverges from vanilla, which
  is the point.

One knock-on flagged rather than fixed: the `InitSkills` hook is not
`LANG_EN`-gated, so a `ff6-jp` build (not produced by `make rom` or `make
test`) would also truncate to eight with no configurator to widen it. §11
carries it as a follow-up.

**This hook runs in EVERY battle, so its COST is part of its contract.** The
AUTO arm must be ONE pass over the 32-byte bitfield that skips empty bytes
whole (~32 loads for a rage-less party, less than vanilla's own 255-iteration
walk) — **not** eight calls to `Ot6RageNth`, which walks ids 0..254 from
scratch every call and so charges the commonest party, the one with no rages
at all, ~255 jsl'd bit tests before the first call returns "nothing". That is
on the order of twenty thousand cycles added to `InitSkills`, and battle init
is coupled to the frame: the OT6 font re-lay is staged one slice per NMI and
admission-gated on the live V counter (`ot6_hud.asm:644-673`), so the cost
lands on `battle_dlgmenu`, `battle_magicite` and `visual_f2` — three tests
with nothing to do with Gau.

The arm also re-establishes `hWMADDH = 0` by writing the list through the WRAM
data port the way the vanilla walk does (`battle_main.asm` @5840); that bank
byte being 0 is a global invariant every `ldx #$9e8b / stx hWMADDL` writer
depends on (`LoadArrayItem`, `item.asm:1256`; `Ot6LoadoutDrawCost`;
`Ot6DrawRageName`'s blank arm). A hook that replaces vanilla code inherits
vanilla's side effects.

The general rule: **a hook that stops handing back to vanilla is a new hot
path.** Cost it, and re-run the whole suite, not just the feature's own test.

### 8.0b The configurator page's geometry

**The EN field-menu window does not show BG1 ScreenA at one tile row per eight
scanlines.** A tilemap row *pair* is displayed in twelve scanlines — the ODD
row gets eight of them, the even row four — and nothing past row 15 is inside
the window at all. Odd rows 1,3,…,15 render whole at screen
`y = 116 + 6*(row-1)`; even rows show only their bottom three scanlines.
Vanilla says the same thing from the other side: every EN cursor table for
this window is `cursor_pos {x, 116 + n*12}` (`skills.asm:125-126`, `:249-250`,
`:292-293`), and `DrawRageName` biases its row by one under `.if LANG_EN`
(`skills.asm:1571-1574`) for exactly this reason. A single column of eight on
rows 4-18 draws eight three-scanline slivers and a caption below the window's
bottom edge. `tools/tests/probe_ragegeom.lua` is the per-row glyph ruler that
measures it, poked straight into the BG1A shadow.

**So the page is two columns of four on odd rows, vanilla's own shape for this
window** (the rage browse is `cursor_prop {0,0}, {2,8}`, `skills.asm:281-299`):

| tilemap row | content |
|---|---|
| 1 | `RAGE LOADOUT` + the flat price, stated once (`8 MP EACH`) |
| 3 | `L/R SWAPS` — the control hint |
| 5 / 7 / 9 / 11 | slots 0-1 / 2-3 / 4-5 / 6-7 — name at col 3 (left) or col 16 (right) |
| 15 | `LEARNED nnn` |

**The control hint and the empty marker.** L/R swapping a slot's beast is not
discoverable on its own, so row 3 carries the hint; the Bushido page carries
the same string (`OT6_LOADOUT_HINT`, which is why its title shortens to
`SWDTECH` to find room).

An unset slot draws `- EMPTY -`, in
the page's BLUE chrome colour so it cannot be read as a beast. It is **not**
`-default-`: nothing defaults into an unset slot. A blank row has exactly two
causes and both mean the slot contributes nothing to the battle list — an AUTO
window shorter than eight (`Ot6RageNth` runs out; §2.2's truncation), and a
MANUAL slot whose byte is `$00` (`Ot6RageList`'s `@manual` arm skips it).
`Ot6RageSeed` stops at the end of the window, so a player who edits while
fewer than eight are hunted keeps genuinely empty tail slots — reachable, and
fillable again with L/R, which starts an empty row's walk at id 0.

Slot order is the menu framework's own index, `$4b = cols*row + col`
(`CalcShortListIndex`, `menu_common.asm:1205-1224`), so slot even = left,
slot odd = right, and `row = 5 + (slot & ~1)`. `Ot6RageCurSlot`
(`ot6_kits.asm`) computes the same number on the F0 side. The dpad's Left and
Right move between the columns; the L/R shoulders cycle. `OT6_RAGECOLS`/`OT6_RAGEROWS` (`ot6_memory.inc`) carry the geometry with
an assert that they cover every slot exactly once. There is no room for a
per-row price column — two 10-cell names plus two cursor gutters plus two
4-cell `n MP` fields is 30 columns and the window's right border is column 30 —
so the price is one copy on the title row. It is flat by design (§5), so one
copy teaches the same rule.

### 8.0c The cursor gutter

The menu cursor is a **16×16 sprite** and `cursor_pos {x, y}` is its **top-left
corner**, so an entry at `x` covers tilemap columns `x/8` and `x/8+1` and the
row it points at must begin at `x/8 + 2`:

> **`cursor_x = 8 × text_col − 16`**

Vanilla obeys it without exception in this window: magic draws at cols 3/16
under cursors 8/112 (`skills.asm:831`, `:836` vs `:125-126`), espers at 3/17
under 8/120 (`:1733`, `:1737` vs `:249-250`), rage at 5/19 under 24/136
(`:1544`, `:1548` vs `:292-293`), and the Config menu's value column 14 under
96 (`config.asm:50`). It holds on the shipped ROM too — the untouched
magic list's `cursor_pos {8, 116}` lights screen `x 8..23, y 116..131`.
`tools/tests/probe_menucols.lua` and `tools/tests/probe_cursorgutter.lua` are
the isolated instruments, and both page tests carry the rule as a canary that
reads the cursor table out of the ROM rather than restating it. A left column
drawn at col 2 under a cursor at `x = 8` puts the sprite on the leading glyph.

1. **`ot6_memory.inc`**: `OT6_RAGELOAD := $7e1e1f` (8 bytes) + asserts
   `>= $1600` and `+7 <= $1ffd` (the `OT6_LOADOUT` assert pair,
   `ot6_memory.inc:38-40`, widened). `OT6_RAGETIER := $57bb` beside
   `OT6_SLOTTIER` with the same strip comment discipline.
2. **F0, `ot6_kits.asm` (new strip beside the Bushido loadout)**:
   - `Ot6RageLearned` — bit test of rage id A against `$1d2c` (the
     `Ot6TechLearned` shape, `:906-923`, 32-byte field).
   - `Ot6RageSlot` — slot → stored byte; `$00`/unlearned → `$ff` (empty);
     else id (byte−1). The `Ot6LoadoutSlotTech` shape (`:960-978`) minus the
     auto-window math (AUTO is resolved at the list build, not per slot).
   - `Ot6RageList` — the battle build: **all 8 bytes zero (AUTO) → emit the
     first eight known rages in id order** (the same window the field page
     draws, §8.0); else emit ≤8 validated ids + count. Either arm returns
     carry set. Called from the `InitSkills` hook.
   - Menu procs: open/input/cycle (next/prev set bit of `$1d2c`, wrapping,
     max 255 hops)/revert (zero all 8)/assign — the `Ot6Loadout*` family
     (`:1024-1157`) with slot count 8 and byte stores.
3. **Battle hook** — `InitSkills`, `battle_main.asm:14659-14679`: branch to
   `Ot6RageList` before the vanilla `$1d2c` walk; on the loadout path write
   the ≤8 ids via the same `hWMDATA` stream and store the count to `$3a9a`.
   The `$ff` terminator the confirm and `RandRage` rely on
   (`btlgfx_main.asm:20264-20266`, `battle_main.asm:992-994`) does not come
   from `InitSkills` on either path: `InitBattle`'s 16-bit double-store loop
   fills `$2000-$341f` with `$ff` (`battle_main.asm:6096-6102`) before its one
   call to `InitSkills` (`:6162`).
4. **MP** — `Ot6AbilityCost` (`ot6_boost.asm:403-433`): `@rage` arm for
   command `$10` — RAGE bit of the actor's `$3ef9` set → 0, clear → flat 8.
   `.if OT6_MP_COSTS`-gated like Steal's arm. No `cmd $11` arm: Leap is free
   (§5). The flat price is drawn once on the configurator's title row via the
   `Ot6LoadoutDrawCost` pattern (`field_menu.asm:2831-2860`).
5. **Boost** —
   - `Ot6RageTierLatch`, hooked at **both** `RandRage` callers — `Cmd_10`
     entry (`battle_main.asm:3351`, before `:3370`'s `_c21554` tail) and
     `FixPlayerAttack`'s cmd-`$10` arm at action LOAD (§6.1):
     `OT6_BOOST_REVEALED,x` capped 3 → `OT6_RAGETIER`.
   - `Ot6RageRoll`, replacing `battle_main.asm:1001-1003`'s
     `jsr RandCarry / rol`: tier 0 → vanilla coin; 1/2 → threshold compare
     (`$40`/`$10`); 3 → force entry 1.
   - `Ot6BoostDmg`: `cmp #$10 / beq done` beside the `$0f` gate
     (`ot6_kits.asm:1215-1224`).
6. **Field menu** — `SkillsOption_05` (`field_menu.asm:1323`) is repointed
   under `.if LANG_EN` to a `MENU_STATE` twin of `$7b`
   (`field_menu.asm:2694-2716`): `cursor_prop {2, 4}` over the odd-row
   geometry of §8.0b, per-row monster name (`GetMonsterNamePtr`,
   `skills.asm:1557-1565`), "LEARNED nnn" counter, L/R cycle, Y revert, B
   exit. Vanilla browse code (`InitRageList`/`ExpandRageList`,
   `skills.asm:1477/:1511`) stays assembled for the non-EN branch, exactly
   like the SwdTech browse.

---

## 9. Tests — the evidence discipline

The deterministic method is `battle_slots.lua`'s
(`tools/tests/battle_slots.lua:28-50`): doorstep state, poked-in Gau (the
battle_steal install pattern), monsters HP-pinned so every roll is
attributable, RNG pinned at tier boundaries, and write-callbacks recording who
wrote `$257e`, `$33a8`, `OT6_RAGETIER`, and the MP cell — bank `$f0` for the
hooks, `$c1/$c2` for vanilla. Every behavioural arm is recorded
fail-before/pass-after, with the 0-BP and zero-loadout arms holding
byte-identical observables against vanilla.

**The bench must be WOUNDED, not stopped.** Parking the non-actor party slots
with the stop status costs exactly what `battle_slots.lua:114-118` says it
does: "a stopped character's pending menu stays open forever and starves the
actor's next turn" — the battle parks on an open list at `cmd10 = 1` and every
multi-turn claim ("mid-trance turns are free", "the latch survives several
possessed turns") is **vacuously true against a battle that took one turn**. A
dead row raises no menu, and the same drive then takes five possessed turns.
**Any arm that asserts something about "several turns" must also assert the
turn COUNT, or it is asserting nothing.**

---

## 10. What the machinery cannot express — the honest ledger

1. **Per-rage or per-slot boost tiers.** One pending-BP cell per character
   (`OT6_BOOST_REVEALED`), one latch per trance; "slot 3 always boosted" has
   no storage and no UI channel. The tier is a start-of-trance decision, ever.
2. **Mid-trance rage switching.** The possession runs to battle end or death
   (`battle_main.asm:11572`, `:12371`); switching needs status surgery plus a
   re-pick UI that doesn't exist. Deliberately not wanted — the lock is the
   verb — but it is also not *available*, which is the honest half.
3. **Controllable beast skills** (kits.md's stable model). The machinery
   expresses possession, not command: the rage attacks live in a monster-
   indexed pair table (`monster_rage.asm`) resolved inside `RandRage`, not in
   player ability records. A menu of castable beast moves is a new command,
   not a Rage variant. Ruled out by the owner regardless.
4. **Per-rage MP prices, displayed.** Expressible in a 255-row table,
   unexpressible on the menu surface (no per-row cost channel in the battle
   rage window without new draw code for 255 values); rejected with the flat
   rule (§5) before the display question even bites.
5. **Boost on Leap.** No roll exists in the leap-learn path to
   convert (§6.3) — a 3-BP Leap spends for nothing, joining Break/Doom in the
   known chance-verb gap (magicite-tube-six.md §13.4) until the return-cadence
   roll is located.
6. **Rage id 255.** The +1 byte encoding tops out at id 254 — exactly
   vanilla's own ceiling (`InitSkills` stops at `$fe`,
   `battle_main.asm:14676-14678`; `LearnRage` skips index > 255,
   `:12336-12337`). Nothing real is lost; noted so nobody "fixes" the
   encoding into a 2-byte slot.
7. **A second simultaneous Rage user.** One `OT6_RAGETIER` byte; Gogo (WoR)
   raging beside Gau would share it. The widen is mechanical (per-character
   strip) and deferred to the band that fields Gogo.
8. **Spending BP mid-trance.** A possessed Gau banks regen he cannot spend —
   no menu, no confirm moment. Honest cost of the possession, priced into §6's
   "3 BP is a full-bank decision".
9. **Gau's divine.** The 8 slots are all rages; the kit-slot-8-divine
   convention every other kit follows has no home here yet, and `kits.md`'s
   open question (a capstone beast vs an upgraded slot) stays open. Flagged so the omission is visibly a decision.

---

## 11. Open follow-ups

1. **Strago's curated slot count.** Gau is settled at 8 by owner ruling;
   `kits.md`'s open question on Strago is still open and should be re-asked
   against this precedent.
2. **The Dance number**: Rage's 8 follows whatever lands there — one flat
   price for possess-verbs is the rule.
3. **The Leap return-cadence roll**: locate the field-side writer of `$11e4`
   bit 0; if random, the boosted-Leap rider re-opens in the
   absence-shortening shape (§6.3).
4. **Strict-reading layout bump** (§4.4 rider 2): if `persistent_layout` is to
   be bumped on principle, budget the 9-anchor regeneration and do it
   deliberately per `leg-fixtures.md`'s "Costs, named" — the byte placement
   does not change either way.
5. **Gau's divine** (§10.9): a design pass of its own, after playtest shows
   which beast the player misses most.
6. **The Bushido configurator's geometry** (§8.0b): Skills → SwdTech draws its
   slot rows on even tilemap rows and two of its four pool rows outside the
   window — visible in `menu_swdtechpage.lua`'s own screenshot, invisible to
   every assertion in the suite. Needs a layout pass of its own plus a
   screen-geometry canary in `menu_swdtechpage.lua` (the even-row/row>15 rule
   `menu_ragepage.lua` carries). Three slots fit the odd rows; the four-row
   pool does not.
7. **The `LANG_EN` gate on the `InitSkills` hook** (§8.0's knock-on): the
   choke point is unconditional, so a `ff6-jp` link would truncate to eight
   with no configurator to widen it. `make rom` and `make test` build only
   `ff6-en`/`ff6-en-nomp`, so nothing shipped is affected; gate it (or decide
   jp is out of scope in writing) before anyone links jp again.
