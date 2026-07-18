# M3 implementation — weapon classes + reveal (built + gate-green)

**Status (phase 2 complete; body below is phase-1 vintage and NOT swept --
where the header and the body disagree, the header is current):** ROM builds
clean (`make rom`, +12 C2 bytes absorbed, no ld65 overflow); full `make test`
gate green (+ golden);
the story fixture chain re-mints and passes (gen_whelk 2813 · gen_arvis
4842 · gen_narshe_escape 4132 · gen_mines_chase 4047). Live-verified on
the real Whelk boss (probe_whelkclass) and the skill-vs-weapon class path
(probe_tekmissile). Deviations from the phase-1 plan are noted inline
below and in the report; the design is unchanged.

Implements weapon-classes.md v2.1: four physical classes (slashing $01,
piercing $02, bludgeoning $04, special ¤ $08) plus a null-break property
bit ($80). **The weapon sets Fight's class; abilities keep their own.**
Class chip mirrors the elemental chip end to end: same shield counter,
same break, same reveal/message/codex flow. A class-weak hit does *not*
double damage — vanilla's elemental ×2 stays vanilla's alone; the class
payoff is the break window.

## Data

- `ff6/src/battle/ot6_class.asm` (new, bank F0, included from ot6.asm):
  - `Ot6WeapClassTbl` — 256 bytes, item id → class byte, O(1) indexed
    (Fight reads it per swing). $ff "Empty" = bare fist = bludgeon;
    Fixed Dice = ¤|null-break. Judgment calls flagged in the header.
  - `Ot6SkillClassTbl` — (attack id, class) pairs, $ff-terminated:
    8 SwdTechs slashing, Pummel/Suplex/Bum Rush bludgeoning, TekMissile
    piercing. Absent = classless (element carries the probe).
- `Ot6ShieldTbl` records grow 3→4 bytes: word species, byte shields,
  byte class-weak mask. ~45 authored records: Guard, Lobo, Whelk pair,
  every bosses-wob.md boss, and the scripted set-pieces (Tritoch,
  Guardian) pinned to 0 shields so their HUD stays silent. Element ADDS
  from bosses-wob stay M6 data entry — only classes ship here.
- Battle RAM: monster halves of the M2 BP table — `$3e9c,y` class-weak,
  `$3e9d,y` revealed classes (all consumers entity-gated, chars keep BP).
  `$7e57b8` = OT6_ATKCLASS, the executing attack's class byte — retired
  OT6_HUDDIRTY's slot, inside the trace-verified strip and InitBP's
  clear. (Phase 2 finding: the first pick, $57d6, is live vanilla
  battle-gfx scratch — battle_class's write-watcher caught foreign
  bytes there. $57d6+ is off-limits.)
- SRAM codex v2: class table at `$316190` (one byte/species, right after
  the element table — single $0300 wipe). Magic bumped 'O6'→'O7'
  ($364f→$374f) so stale banks re-init once.

## Hooks (ff6/src/battle/battle_main.asm)

| line | site | change |
|---|---|---|
| 6864 | `LoadMagicProp` C2/2966 | +`jsl Ot6SkillClass` — every spell-record attack (magic, skills, enemy attacks, the $ee "battle" record, DoT ticks) |
| 6955 | `_magicpunch` C2/299F, after the weapon-element store | +`jsl Ot6WeaponClass` — x = entity+hand, `$3ca8,x` = the swinging item, per hand per swing (genji/offering honest for free). Monsters store 0 (their $3ca8 is a graphics code) |
| 7002 | `CalcItemEffect` C2/2A37 | +`jsl Ot6ItemClass` — items/Tools/Throw chip their item's class (AutoCrossbow pierces, Chain Saw slashes, thrown Ashura slashes) |
| 1877 | elemental join `@0c1e` C2/0C1E | `jsl Ot6BrokenDmg` → `jsl Ot6HitJoin` (class chip, then broken ×2) — 0 net C2 bytes |

Net C2 growth: +12 bytes (three jsl). All three loaders **store always**
(0 when classless) so a stale class can never leak between attacks —
verified against the Fight path's order (InitTarget loads $ee → 0, then
each swing re-stores the weapon class) and the DoT path (Cmd_22 →
InitTarget_00 → LoadMagicProp($ee) → 0).

Chip rules at the join: runs for every landed hit, including hits whose
element was absorbed/nulled/forcefielded — the blade still lands
(Octopath: chip is independent of damage dealt). Guards: target is a
monster, not broken, not wound/petrified, not a heal ($f2), class bit
present (bmi rejects null-break), mask match. One chip per axis per hit:
a Flame Knife on a fire+pierce-weak monster chips 2.

## Width safety

The action executor runs **i8** (`ExecSelfAttack`/`CalcAttackEffect` are
`.i8`; the annotations are load-bearing — their `ldy #imm` operands
prove the runtime width). Every new proc pins `php/longi` or is
width-agnostic; entity offsets survive the rep because 8-bit index mode
forces high bytes to zero. Found in passing and fixed: `Ot6Chip`'s codex
store ran its 16-bit `ldx OT6_SPECIES-8,y` under caller i8, truncating
species ≥ $100 onto the wrong codex slot (M1 latent bug — battle_codex
only ever exercised Guard, species 0). Now pinned; Ot6ClassChip inherits
the pinned stretch from Ot6HitJoin. **Phase-2 confirmed live**
(probe_whelkclass): the Whelk head ($134) learns its fire weakness at
codex slot $316010+$134, and the truncated neighbor $316010+$34 stays
clean — the exact bug the fix targets.

## Two phase-2 corrections to the data

- **OT6_ATKCLASS moved $57d6 → $57b8.** The first pick, $57d6, is live
  vanilla battle-gfx scratch (battle_class's write-watcher caught
  foreign bytes $84/$85/$ab landing there); $57b8 is retired
  OT6_HUDDIRTY's slot, inside the trace-verified strip and InitBP's
  clear. $57d6+ is off-limits.
- **Whelk-head record fixed $0135 → $0134.** M1 authored $0135, which is
  the *WoR presenter's* head; the Narshe-intro head is species $0134
  (measured live at $57c0). The real first boss had been seeding by
  formula (2 shields) — now the authored 4·piercing seeds correctly.
  Note $0134 carries no vanilla fire bit, so the tutorial's fire probe
  remains an M6 element ADD, not vanilla.

## Messages

`attack_msg_en.json` slots $45–$48 = "Weak against slashing / piercing /
bludgeoning / special"; the chip walks the class bit exactly like the
element walk at base $15. Surgery-map gotcha #1 turned out to be already
closed: `romtools.encode_text` regenerates the offsets include itself,
so the `make text` step rebuilt `.dat` + `.inc` together (verified in the
phase-2 build) — no tooling change shipped (the gotcha note is corrected
in the research doc). When one hit reveals an element *and* a class, the
class message wins ($3401 is a single byte); the element reveal itself
still happens. The class chip's reveal→message→codex path is confirmed
firing live (crev flips, codex learns); a frame with the "Weak against
piercing" banner drawn was not captured (the $3401 index is transient
within one frame and the berserk-fight cadence made it hard to sample),
but the render mechanism is identical to the element messages that
battle_break/battle_codex exercise.

## Out of phase 1 (HUD follow-up)

Class slots in the under-monster strip (element icons then class glyphs:
$d9 sword / $da spear / $dc staff + a new ¤ font cell — free cells $d0,
$d1 remain), class '?' slots pre-reveal, shield glyphs past 6 (Atma is
11 — display saturates at 6 today, count stays true), dual-reveal
message collision, codex-viewer surface.

## Test plan

`tools/tests/battle_class.lua` (this said WRITTEN, NOT RUN — stale: it is in
`suite.sh` and runs every gate; its remaining `GUESS` markers are the thing
to sweep, not whether it runs): doorstep
guards now authored pierce-weak, so the seed itself is under test.
Berserk-forced Fight (battle_hits pattern), element weaknesses zeroed so
only the class path can move shields; phases: authored seed → slash = no
chip → dirk = chip+reveal+codex+glyph → break → recovery with reveal
persisting → Fixed Dice = no chip (null-break) → Dice = ¤ chip. GUESS
markers inline flag the assertions that want a real run (seed-2 stride,
berserk swing cadence, dice phases). battle_codex.lua magic byte updated
for 'O7'.

Phase 2 order: (1) `make` — watch ld65 for battle_code overflow (+12 B)
and confirm `attack_msg_en.inc` regenerates; (2) battle_break + battle_bp
+ battle_hits + battle_codex (regressions — codex now re-inits once);
(3) battle_class; (4) whelk-head codex spot-check (species $135 — the
width fix's first real exercise); (5) manual: Pummel vs a bludgeon-weak
target with claws equipped (ability class beats weapon class), a class
reveal message rendering, Tools chip.

## Open questions for the coordinator

1. Camp/Narshe Kefka share species $14a — one row serves both (Narshe's
   6·slash+pierce shipped; the doc wanted 3 at the camp). Per-formation
   shield overrides are new machinery — M6?
2. Ultros' four fights are four species; the codex forgets him between
   them, against bosses-wob's "revealed at the Lete, remembered forever."
   Wants a species→codex alias table (tiny) — this milestone or M6?
3. Lobo shields: authored 3 (M1 regression anchor) vs bosses-wob's 2.
4. Dual-axis hits chip 2 (element + class). Intended reading of
   "a piercing probe and a fire probe in one swing"?
5. Raged Gau's Fight reads the rage monster's graphics code as an item
   id (SetRage fills $3ca8/9) → junk class until Rage retires. Also
   plain Gau punches bludgeon ($ff fists), not the kit's "fangs =
   piercing" — special-case now or wait for the Capture rework?
6. Heal Rod is classless ("a healing stick teaches nothing") — bludgeon
   instead? Atma Weapon (the sword): null-break candidate?
7. ¤ message wording: "Weak against special" shipped; better voice
   welcome before the font gets a ¤ glyph.
