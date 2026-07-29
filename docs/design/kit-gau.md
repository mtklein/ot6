# Gau — the hunter's stable: learn many, equip 8 — design dive v1 (2026-07-28)

Scope: issue #40. Gau's kit under the **Ochette model** — Veldt learning stays
unlimited, the battle menu offers an 8-slot loadout — plus the Dance-model MP
rule and the chance-verb boost ladder for Rage. This direction is
**owner-settled, not a proposal**: "ochette for gau is perfect" (#40 comment,
2026-07-28); the learn-many/equip-8 shape proceeds as written there. This is a
**design pass**: no assembly, no data edits. Everything the build pass needs is
listed literally in §8.

**Canon boundary.** Vanilla Rage is the baseline and survives almost whole:
the menu picks a beast, Gau is possessed for the rest of the battle, and every
possessed turn is a 50/50 between Fight and the beast's special
(`Cmd_10`, `ff6/src/battle/battle_main.asm:3351-3371`; the coin at
`:1001-1003`). What changes is exactly three things: the battle list shows a
curated 8 instead of everything he knows; the possession is priced (flat, once,
at Rage-start — #34's Dance model); and boost buys certainty on the coin (the
chance-verb canon, DESIGN.md:131-142). What kits.md wrote for Gau in v2 —
a ~5-slot stable of **controllable** beast skills, "the 250-entry berserk Rage
table retires" (kits.md:26, :417-420) — is **superseded** by the owner ruling;
§11 lists the doc amendments.

**Evidence rule (CONTRIBUTING.md).** Every mechanical claim cites the file and
line it was read from, or is labelled **UNVERIFIED**. Line numbers are from the
`wt/kit-gau` worktree (branched from `main`) on 2026-07-28.

---

## Summary of rulings

| question | ruling |
|---|---|
| Collection | unlimited, untouched — `LearnRage` keeps filling the `$1d2c` bitfield (`battle_main.asm:12334-12348`) |
| Equip | **8 slots**, one byte per slot, configured in the field under Skills → Rage (the Bushido-configurator pattern at 8 rows) |
| SRAM | **8 bytes at `$1e1f-$1e26`** — the same save-block scrap the Bushido word lives in; zero-sentinel = AUTO; **no `persistent_layout` bump, zero anchors regenerated** (§4, the tradeoff table) |
| Battle read | one choke point: `InitSkills`' `$257e` list build (`battle_main.asm:14659-14679`) filters through the loadout; the vanilla Rage window, cursor, scroll and confirm are untouched (§3) |
| MP | **flat 8 MP at Rage-start**, whole-battle possession, mid-trance turns free — one price rule for both possess-verbs (Rage here, Dance in #34) (§5) |
| Boost | 0 BP vanilla coin; 1 BP special ¾; 2 BP special 15/16; 3 BP the special **every turn for the whole trance** — latched at `Cmd_10`, the Slot-latch pattern (§6) |
| Boosted Leap | **not this pass** — Leap's learn step has no roll to convert; rider re-opens if the return-cadence roll is located and playtest wants it (§6.3). Leap prices flat 2 MP |

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
  argument kits.md:25-28 already makes, at the slot count the owner named
  (#40: "choose from 8").
- **The battle game** is vanilla possession: pick one of your eight, pay once,
  and ride the beast until the fight ends. The loss of control is the verb —
  the same ruling Dance made ("that loss of control IS the dance",
  kits.md:396-398).

Eight also matches every other kit's list length ("reshapes the lists to
exactly 8", kits.md:8-9): Gau's battle menu becomes exactly as long as
Sabin's, and the fact that HIS eight are chosen from hundreds is the identity
doing the differentiating, not the menu shape. (kits.md's older "~5 slots" and
its stable-of-controllable-skills model are superseded — §11.)

Gau is already in the supported frontier: the s2 (Sabin scenario) chain
carries him — rung `gau_joined`, minted by `gen_sabin_gau`
(`tools/tests/frontier_graph.py:190-197`), and `gen_sabin_gau` sits in the
smoke set (`Makefile:200`). Natural-boot coverage rides that rung (§9).

---

## 2. The loadout machinery fit — what Bushido built, what 8 slots needs

### 2.1 What the Bushido implementation provides (issue #8 Layer B)

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
  is the single choke point**: when any loadout byte is nonzero, write only
  the stored, still-learned ids (at most 8), set the count `$3a9a`
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
  new screen is `MenuState_7b`'s twin: cursor prop `{1, 8}`, eight
  `cursor_pos` rows (16px pitch: y = 30..142 — fits the frame the Bushido
  screen already proved), one name+cost row per slot. Two deltas from
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
- **Cost display**: every slot row draws the flat trance price through the
  `Ot6LoadoutCost`/`Ot6LoadoutDrawCost` pattern (`field_menu.asm:2772-2774`,
  `:2831-2860`) — uniform by design (§5), so the column doubles as the
  price's teaching surface. The battle window's wallet surface rides #34/#35's
  display-pattern work, which prices Dance's identical shape first.

**AUTO's definition** (needed the moment the sentinel exists): the first eight
known rages in id order — i.e. the head of the vanilla list `InitSkills`
already builds. Not "most recently learned" (needs storage that doesn't
exist), not "strongest" (needs a judgment call the machinery can't make).
A fresh Gau with ≤8 rages is byte-for-byte vanilla under AUTO.

---

## 3. Where the trance itself lives (read, not changed)

For the build pass's orientation — the possession machinery this design
deliberately leaves alone:

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

### 4.1 The precedent, read

The Bushido loadout was added 2026-07-23 (commit `6e2b08a`) as unused bytes
inside the checksummed save block, with an all-zero sentinel meaning AUTO —
"zero migration (every existing save reads `$1e1d..$1e1e` = `$0000` = AUTO)"
(`ot6_kits.asm:7-8`). The `persistent_layout` gate arrived four days *later*
(#25, commit `6488418`, 2026-07-27), and the string it minted —
`ot6-codex-o8-v1`, declared by every real anchor
(`tools/tests/anchors/*/manifest.json`) and by every consuming leg
(`OT6_ANCHOR_LAYOUT:` markers) — was coined for a world that already contained
the loadout word. The precedent is therefore exact: **a zero-sentinel addition
to the save-block scraps is not a layout change**, because no existing byte's
meaning changes and no old anchor can be misread.

### 4.2 The scrap, verified

`$1e1d-$1e3f` (~35 bytes) is documented free save-block space
(`docs/research/ram-and-rom-space.md:56`, the madsiur survey). Bushido holds
`$1e1d-$1e1e`; **`$1e1f-$1e26` is the next eight**. Checks run this pass:

- No code in the tree references `$1e1f-$1e26` (grep over `ff6/src`; the only
  hits are local branch labels named `@1e1f` etc.).
- The checksum window covers them (`$1600-$1ffd`, `save.asm:750-771`), and the
  per-slot round-trip copies them (`save.asm:69/:97`) — persistence and
  validation for free, the same free ride the word gets.
- **Measured, all 11 tracked anchors, all 3 slots each: `$1e1d-$1e28` is
  all-zero** (payload scan of `tools/tests/anchors/*/`, this pass). The
  zero-sentinel migration story is not an argument — it is a property the
  current fleet demonstrably has.

### 4.3 The tradeoff table

| | (a) layout bump + regenerate | (b) codex-page tail | **(c) save-block scrap `$1e1f` (Bushido pattern)** |
|---|---|---|---|
| Bytes | anywhere (schema is being re-cut) | `OT6_CODEX_ROOT+page+$310..$317` (page = `$400`, used = `$310`: `ot6_memory.inc:24-36`) | `$1e1f-$1e26` |
| Anchor cost | **9 real anchors** (11 tracked minus the two negative fixtures) regenerated through real Save UI drives, in dependency order — effectively a frontier re-mint, the multi-hour cost leg-fixtures.md was written to stop paying, plus every leg's `OT6_ANCHOR_LAYOUT` marker and manifest edited | none *claimed* — but see honesty row | **zero** (measured zeros decode as AUTO — the exact semantics those saves had) |
| Checksummed / save-slot semantics | designer's choice | **no**: codex pages sit outside the `$1600-$1ffd` checksum, and codex writes are immediate — a loadout there would survive a reset-without-save, unlike every other menu decision in the game | **yes**, both, for free |
| Init guarantee | designer's choice | **none for the tail**: `Ot6CodexEnsure` wipes only `$300` bytes from `+$10` (`ot6_codex.asm:129-132` and siblings) — the tail is never initialized by any code path. Anchors happen to hold zeros there (measured), but that is the emulator's SRAM fill, not a contract; real-hardware SRAM is undefined, so the tail needs its own sub-signature to be safe | New Game zeroes the save block; sentinel = the uninitialized value (`ot6_kits.asm:18-22`'s argument, and §4.2's measurement) |
| Layout-string honesty | honest by construction (that is its whole cost) | **cannot honestly stay**: `ot6-codex-o8-v1` names the codex page layout *specifically*; claiming tail bytes changes exactly the thing the string versions, so this option quietly converges on option (a) anyway | stays honestly: the string's contract is "refuse an anchor the leg would misread" (`sram_anchor.py:22-33`, leg-fixtures.md:90-91), and no v1 anchor can be misread — zeros are AUTO, the state those saves are genuinely in |
| Precedent | leg-fixtures.md:109-111 names the path but calls it "deliberate", for real schema breaks | none | **the Bushido word itself** |

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
   word's own precedent; the leg-entry invariant contracts (leg-fixtures.md:83-86)
   gain a "rage loadout" row either way.

---

## 5. MP — the Dance model, one price for both possess-verbs

**Ruling: Rage costs a flat 8 MP, charged once at Rage-start; every possessed
turn after is free; death ends the trance and a re-Rage pays again.**

Why flat, in one paragraph: the possession is one decision and vanilla's lock
makes it one *purchase* — "one payment starts a whole-battle state — vanilla's
can't-stop-dancing lock is preserved, so the price is per battle, not per
step" is mp-economy.md:96's rule for Dance, #34 turned it into acceptance
criteria, and issue #40 orders "one pricing rule for both possess-verbs." A
principled per-rage formula (price by the special's spell cost) was considered
and rejected on three counts: it double-charges — the trance's real price is
the surrendered control, already paid, and the special is only *rolled*, not
chosen per turn; it inverts the collection's joy — the rarest hunts would
carry the ugliest prices, taxing exactly the album pages the collection game
exists to celebrate; and it needs a 255-row price surface where the flat rule
needs one number on every row (§2.2's display note). 8 sits in Dance's own
4-10 band at the top half — Rage's stable is broader than Mog's eight dances,
so it prices at the band's ceiling-adjacent rung, not above it — and it is
~20% of Gau's join-era pool (base 10, `mp-economy.md:155-158`, plus the
universal pool of #32/`97f6d6e`): a real commitment, never a lockout, and
cheap next to a 40 MP divine because the payment buys a *gamble*, not an apex.
If #34's dispatcher lands Dance on a different number inside 4-10, **Rage
follows it** — the rule ("possess-verbs share one flat price") outranks this
paragraph's 8.

Mechanics, in the shipped machinery's terms: `Ot6AbilityCost`
(`ot6_boost.asm:403-433`) gains a `$10` arm beside Steal's flat arm — if the
actor's RAGE status bit is already set (`$3ef9` bit 0, the bit `Cmd_10` sets
at `battle_main.asm:3364-3366`), return 0 (mid-trance turn); if clear, return
the flat price (this is the Rage-start action). Charge and refusal are already
universal downstream (the `$3620`→`$3a4c` subtract and its fizzle,
mp-economy.md:270-290), so the refusal surface is the standard one: a Gau
under 8 MP is refused the start, never silently freed, and the mid-trance
zero-charge is measured across a multi-turn trance exactly as #34 specifies
for Dance. `.if OT6_MP_COSTS` gates it all; the nomp baseline is undisturbed.

**Leap prices too** — "only the basic Fight command is free" is the owner
absolute (mp-economy.md:30-34). Leap takes the probe-collect price: **flat
2 MP**, keyed on command `$11` like Steal's `$05` arm (the very price
mp-economy.md:97 already assigned this verb's row). Refused under 2 MP; the
Veldt will still be there next turn.

---

## 6. Boost — the chance-verb canon, Dance-shaped

**Canon** (DESIGN.md:131-142, ROADMAP.md:79-82, kits.md:405-410): on chance
verbs boost buys certainty in the verb's own vocabulary. Rage's vocabulary is
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
converging ladder Steal shipped (+40/+90/clamp, kits.md:311-318). The tilt is
toward entry 1 (the special) because entry 0 is always plain Fight
(`monster_rage.asm:3-5`) — nobody spends BP to punch more predictably.
Exact thresholds are M6's to tune; the mechanism is one threshold compare.

### 6.1 The latch — Slot's pattern, whole-trance duration

BP is spent once, at the Rage-start action, through the normal
`Ot6ActionEnd` consume — but the *tier* must outlive that action by the whole
battle. This is Slot's problem solved again at longer range: Slot latches the
spin's tier at the first A press (`Ot6SlotRig` → `OT6_SLOTTIER` at `$57ba`,
`ot6_kits.asm:1490-1530`, `ot6_memory.inc:59-64`) so the charge and the reels
can never disagree. Rage latches at `Cmd_10` (`battle_main.asm:3351`, before
the `_c21554` tail fires the first possessed action): copy
`OT6_BOOST_REVEALED,x` (capped 3) into **`OT6_RAGETIER`** — the `$57bb` spare
of the same init-exempt strip is the natural cell. Staleness is harmless by
Slot's own argument: the cell is read only while a RAGE status is set, and the
only writer of that status (`Cmd_10`) always rewrites the latch first. One
byte suffices while Gau is the only Rage user; a second user (Gogo, WoR) is
the widen-to-per-character moment (§10.7).

The roll hook replaces `RandRage`'s `jsr RandCarry / rol` pick
(`battle_main.asm:1001-1003`): tier 0 runs vanilla's own coin, byte-identical.

### 6.2 The no-double-dip gates

- **`Ot6BoostDmg` gains a `$10` gate** beside Steal's `$05` and Slot's `$0f`
  (`ot6_kits.asm:1215-1234`): a rage action never takes the ×2/×4/×8
  multiplier. This is load-bearing on the *start* turn — `Cmd_10` executes the
  first possessed action while the pending boost is still live (`:3370`), and
  without the gate a 3-BP Rage-start would buy the guaranteed special AND
  multiply it: exactly the double-dip kits.md:405-410 rules out.
- **Mid-trance turns touch no boost machinery at all**: no fold, no
  multiplier, no `Ot6ActionEnd` consumption beyond vanilla's. A possessed Gau
  has no menu, so no pending boost ever arises on his auto-turns; BP he regens
  during the trance banks, unspendable until the next battle's Rage-start
  (§10.8 — an honest cost, and Cyan-adjacent: banking with a purpose).

Deterministic A/B evidence follows the `battle_slots.lua` discipline
(`tools/tests/battle_slots.lua:28-50`): same drive, one pending byte
different, the pick cells asserted at the tier boundaries with pinned Rand,
write-callbacks attributing every store to bank `$f0` or `$c1/$c2` (§9).

### 6.3 The boosted-Leap rider — evaluated, recommended against (for now)

The proposed rider: boosted Leap = guaranteed capture. Read against the
source, the rider has nothing to buy where it aims:

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
  the gate reads `$11e4` bit 0, whose field-side writer was not read this
  pass. That read is the rider's real prerequisite.

**Recommendation: ship Leap vanilla (plus the 2 MP price) and defer the
rider.** If the return-cadence roll is located and playtest finds the wait
frustrating, the honest rider shape is *boost shortens the absence* (1-3 BP →
sooner/next-battle-guaranteed return) — certainty in Leap's actual vocabulary,
which is absence, not capture. Until then Leap joins Break and Doom in the
boost-inert ledger (§10.5): the UI will accept a spend that buys nothing,
the known canon gap (magicite-tube-six.md §13.4), not a new one. The
alternative reading — reshaping Leap into an in-battle Capture roll
(kits.md:417's `Leap→Capture ✦`) — belongs to the superseded
controllable-stable model and would delete the leap-and-return ritual the
owner's "the collection game IS Gau" framing protects; rejected here, flagged
in §11 for the kits.md amendment.

---

## 7. Balance notes

- **The slot fight is Gau's own menu now**: 8 slots against 200+ candidates is
  the entire tuning surface, and it self-balances the trash/boss split (carry
  a healer beast and you carried one fewer nuke). M6's measurement is
  wear-time per rage across the s2-band fixtures — the magicite-tube-six §10.3
  discipline pointed at loadout slots instead of stones.
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

## 8. Implementation shopping list

No design thought required below; citations are the work order.

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
   - `Ot6RageList` — the battle build: if all 8 bytes zero → return carry
     "use vanilla walk"; else emit ≤8 validated ids + count. Called from the
     `InitSkills` hook.
   - Menu procs: open/input/cycle (next/prev set bit of `$1d2c`, wrapping,
     max 255 hops)/revert (zero all 8)/assign — the `Ot6Loadout*` family
     (`:1024-1157`) with slot count 8 and byte stores.
3. **Battle hook** — `InitSkills`, `battle_main.asm:14659-14679`: branch to
   `Ot6RageList` before the vanilla `$1d2c` walk; on the loadout path write
   the ≤8 ids via the same `hWMDATA` stream, store the count to `$3a9a`, and
   `$ff`-fill through `$267d`. (Verify in the fixture that the vanilla path
   also leaves `$257e+n..$267d` at `$ff` — the confirm and `RandRage` both
   rely on the terminator, `btlgfx_main.asm:20264-20266`,
   `battle_main.asm:992-994`; **UNVERIFIED** this pass who `$ff`-fills it at
   battle init on the vanilla path.)
4. **MP** — `Ot6AbilityCost` (`ot6_boost.asm:403-433`): `@rage` arm for
   command `$10` — RAGE bit of the actor's `$3ef9` set → 0, clear → flat 8;
   `@leap` arm for `$11` → flat 2. Both `.if OT6_MP_COSTS`-gated like Steal's
   arm. Cost display per row in the configurator via the
   `Ot6LoadoutDrawCost` pattern (`field_menu.asm:2831-2860`); battle wallet
   surface rides #34/#35.
5. **Boost** —
   - `Ot6RageTierLatch`, hooked at `Cmd_10` entry (`battle_main.asm:3351`,
     before `:3370`'s `_c21554` tail): `OT6_BOOST_REVEALED,x` capped 3 →
     `OT6_RAGETIER`.
   - `Ot6RageRoll`, replacing `battle_main.asm:1001-1003`'s
     `jsr RandCarry / rol`: tier 0 → vanilla coin; 1/2 → threshold compare
     (`$40`/`$10`); 3 → force entry 1.
   - `Ot6BoostDmg`: `cmp #$10 / beq done` beside the `$0f` gate
     (`ot6_kits.asm:1215-1224`).
6. **Field menu** — repoint `SkillsOption_05` (`field_menu.asm:1323`) under
   `.if LANG_EN` to a new `MENU_STATE` twin of `$7b`
   (`field_menu.asm:2694-2716`): 8-row cursor (`cursor_prop {1, 8}`, eight
   `cursor_pos` at 16px pitch from y=30), per-row monster name
   (`GetMonsterNamePtr`, `skills.asm:1557-1565`) + flat cost, "LEARNED nnn"
   counter, L/R cycle, Y revert, B exit. Vanilla browse code
   (`InitRageList`/`ExpandRageList`, `skills.asm:1477/:1511`) stays assembled
   for the non-EN branch, exactly like the SwdTech browse did.
7. **Tests** — `tools/tests/battle_rage.lua`, the `battle_slots.lua`
   install+attribution discipline:
   - loadout filter A/B: word... bytes zero → `$257e` = vanilla walk (byte
     compare); bytes set → exactly the stored ids then `$ff`, `$3a9a` = count;
   - charge: Rage-start debits 8 (refusal below 8, standard surface);
     mid-trance turns debit 0 across ≥3 possessed turns; death → re-Rage
     debits again; Leap debits 2;
   - tiers: pinned Rand at `$3f`/`$40`/`$0f`/`$10` boundaries per tier;
     0 BP byte-vanilla (fail-before/pass-after recorded both ways);
     3 BP → entry 1 every turn, whole trance;
   - gates: rage damage never multiplied at any tier (`Ot6BoostDmg` `$10`);
     charged tier == latched tier (the Slot delivered-vs-charged theft,
     re-closed);
   - anchor invariance: load one tracked anchor unmodified; assert the rage
     menu behaves AUTO (the §4.2 measurement, pinned as a regression test);
   - natural-boot rows `@suite frontier=gau_joined` (the s2 chain,
     `frontier_graph.py:197`), skipped until the rung mints.
8. **Doc amendments** on land: §11's list.

---

## 9. Tests — the evidence discipline

Fail-before/pass-after per agent-brief: on the pre-change ROM the 0-BP and
zero-loadout arms pass with byte-identical observables (the vanilla-evidence
arm) and every new-behavior arm fails; on the post-change ROM all arms pass;
both runs recorded in the change report. The deterministic method is
`battle_slots.lua`'s (`tools/tests/battle_slots.lua:28-50`): doorstep state,
poked-in Gau (the battle_steal install pattern), monsters stopped and
HP-pinned so every roll is attributable, RNG pinned at tier boundaries, and
write-callbacks recording who wrote `$257e`, `$33a8`, `OT6_RAGETIER`, and the
MP cell — bank `$f0` for the hooks, `$c1/$c2` for vanilla.

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
   not a Rage variant. Superseded by the owner ruling regardless.
4. **Per-rage MP prices, displayed.** Expressible in a 255-row table,
   unexpressible on the menu surface (no per-row cost channel in the battle
   rage window without new draw code for 255 values); rejected with the flat
   rule (§5) before the display question even bites.
5. **Boost on Leap** (this pass). No roll exists in the leap-learn path to
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
   convention every other kit follows has no home here yet, and kits.md's open
   question (a capstone beast vs an upgraded slot, kits.md:436-437) stays
   open. Not this issue's scope; flagged so the omission is visibly a
   decision.

---

## 11. Follow-ups for the dispatcher

1. **Doc amendments this ruling forces** (contradictions found, all
   pre-dating the owner's 2026-07-28 endorsement):
   - kits.md:26 and :412-427 — "~5 slots", the controllable stable, "the
     250-entry berserk Rage table retires", `Leap→Capture ✦`: rewrite the Gau
     entry to the possession/8-slot model (§1-§6). The `✦` on Leap→Capture
     was locked under the superseded model; the owner's newer words govern.
   - mp-economy.md:97-98 — "(Leap and berserk Rage are retired — kits.md)"
     and the "Beast skills (Gau's stable) flat per beast 3-10" row: replace
     with Rage flat-8 (Dance-model) and Leap flat-2 rows.
   - kits.md:438-439 (open question 3, "5 for both Gau and Strago?") —
     Gau is settled at 8 by owner ruling; Strago's count is still open and
     should be re-asked against this precedent.
2. **The Dance number (#34)**: Rage's 8 follows whatever lands there — one
   flat price for possess-verbs is the rule; land them together or reconcile
   after.
3. **The vanilla `$ff`-fill of `$257e-$267d`** (§8.3's UNVERIFIED): one read
   or one probe before the build pass relies on the terminator.
4. **The Leap return-cadence roll**: locate the field-side writer of `$11e4`
   bit 0; if random, the boosted-Leap rider re-opens in the
   absence-shortening shape (§6.3).
5. **Strict-reading layout bump** (§4.4 rider 2): if the dispatcher wants
   `persistent_layout` bumped on principle, budget the 9-anchor regeneration
   and do it deliberately per leg-fixtures.md:109-111 — the byte placement
   does not change either way.
6. **Gau's divine** (§10.9): a design pass of its own, after the loadout
   ships and playtest shows which beast the player misses most.
