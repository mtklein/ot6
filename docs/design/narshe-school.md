# Narshe school — teaching the OT6 loop (2026-07-18)

The Narshe Beginner's House rewritten to teach break/boost instead of
vanilla trivia. **The fence:** this change touches the school's tutorial
rooms only — no story scenes, no other dialog anywhere. DESIGN.md's
"story/dialog changes out of scope" clause (DESIGN.md:269-271) is
amended by this sanction exactly that far and no farther.

Diff discipline: an advisor whose vanilla lesson is still true in OT6
keeps vanilla text, byte for byte. Eight dialog ids change; everything
else in the school is untouched.

## The vanilla school (inventory, from source)

Four maps. Doors and NPCs from `ff6/src/field/trigger/short_entrance.dat`
(map offsets in `include/field/short_entrance.inc`),
`ff6/src/event/npc_prop.asm` (`NPCProp::_104` … `_107`), scripts in
`ff6/src/event/event_main.asm` (`_cc339c` … `_cc36b9`), chests in
`ff6/src/field/trigger/treasure_prop.dat`.

- **Map 104 — front hall.** Entered from Narshe town at {33,54} (WoB
  map 20; WoR map 32 via the `_cc3940` trigger — same doorway). Three
  doors on the north wall: x=93 → map 105, x=99 → map 106, x=108 →
  map 107. NPCs: greeter (`_cc339c`, dlg $0257 WoB / $0258 WoR),
  recovery-spring lecturer ($0259) + the spring itself (`_cc33ae`),
  "go get experience" ($0271), Wait-mode advisor ($0261), and the
  magicite ghost ($0273/$0274, appears once you carry magicite). The
  WoR door-opener outside (`_cc33b8`, NPCProp::_20) reuses dlg $0257.
- **Map 105 — left room** (vanilla: statuses & esoterica). Ten
  advisors: $0269/$026A statuses, $026B undead-vs-cure, $026C Life 3 /
  Regen, $026D 3-way attack, $026E Rflect fades, $026F
  Runic/Morph/Dance/Rage, $0270 Image, $0272 near-fatal skills, $0275
  SwdTech names, $0276 Rflect bounce trick. Chest: Tonic.
- **Map 106 — middle room** (vanilla: battle basics). Eight advisors:
  $0262 run (hold L+R), $0263 ATB meter / pass turn, $0264 L/R
  multi-target, $0265 Row/Defense, $0266 pincer, $0267 damage
  numerals, $0268 back row, $0277–$027D status-color demo. Chest:
  Sleeping Bag.
- **Map 107 — right room** (vanilla: items & the world). Save point
  (+$025A/$06D4), $025B pots, $025C curative items, $025D
  monsters-in-chests, $025E/$06D2 relics, $025F buttons, $0260
  equip-shop arrows, chocobo advisor (`_ccd2ee`, shared $03A5/$03A6).
  Chests: a **monster-in-a-box** at {54,28} (event battle group 0 =
  formation 0, Soldier + Lobo) and a Tincture.

Dialog id = index into `ff6/src/text/dlg1_en.json` ($0257 = entry 599).

## Room-to-lesson mapping

The player enters at the bottom-right; the greeter stands beside the
entrance and names the course. No forced order (vanilla had none), but
the natural nearest-door-first walk is 107 → 106 → 105, which lands:
supplies and a practice fight on the doorstep, the core loop in the
middle, the economy and the rung-2 seed in the deepest room.

| Room | Teaches | Changed ids |
|---|---|---|
| Hall (104) | orientation: the war has new rules | $0257 |
| Middle (106) | **the core loop**: shields, chip-on-weakness, Break; hidden '?', reveal, the forever-codex, ability element marks | $0267, $0264 |
| Left (105) | **the economy**: BP gain/bank/spend, R/L; the no-regen rule, why greed loses (shielded resistance); spell folding; the rung-2 seed | $026D, $0270, $026E, $0276 |
| Right (107) | vanilla supplies/save, plus the practice dare at the live monster chest | $025D |

Slot choice inside each room: the replaced advisors carried the most
expendable vanilla lessons — $0267 (numeral colors), $0264 (L/R
multi-target: now actively *misleading*, since R/L during a spell list
fold tiers and R/L during the command menu boost), $026D (3-way attack
trivia), $0270 (Image), $026E (Rflect fade corner case), $0276 (Rflect
bounce corner case). The seed sits on $0276 deliberately: the deepest
corner of the deepest room holds the forward-looking secret. The $025D
advisor stands directly beside the live monster chest — his dare is the
school's graduation exercise and the echo the mines' chest ambush
(Repo Man) pays back later.

## The copy (final)

Conventions are vanilla's: ```` `` '' ```` for quoted terms, `_` = …,
`{n}` hard line break, `{page}` next box; the renderer word-wraps
automatically (see constraints below). Breaks/Boost/Broken are
capitalized as proper mechanics; shields stay common.

**$0257 — greeter (also spoken by the WoR door-opener):**

> This is a classroom for the beginner. The war has new rules: shields,
> Breaks, Boosts.{n}Think of us as your advisors_

**$0267 — the loop (middle room):**

> The number under a monster is its shields. Hit a weakness, the right
> element or weapon, and one falls.{page}At zero it Breaks: it loses
> its turns and takes double damage until it recovers. Strike NOW!

**$0264 — probing, reveals, the codex, ability marks (middle room):**

> The ``?'' by a monster's shields are weaknesses it hasn't shown you.
> Probe with everything!{page}A true hit turns ``?'' into the weakness
> itself. What you learn, you know forever.{page}Each ability bears the
> mark of its element. Match the mark to the weakness.

**$026D — Boost Points (left room):**

> The dots by each name are Boost Points. You gain 1 a turn, and can
> bank 5.{page}The R Button spends up to 3 on the command you're
> choosing. The L Button takes them back.

**$0270 — the no-regen rule and greed (left room):**

> Boosting has a price: a turn you boost earns no Boost Point.{page}And
> shields blunt wrong hits to half strength. Greed loses. Spend into
> weakness, or into the Broken.

**$026E — spell folding (left room):**

> Boost folds magic: Fire becomes Fire 2, then Fire 3, for the base
> spell's MP.{page}Watch the spell list as you tap the R Button. What
> you see is what will cast.

**$0276 — the rung-2 seed (left room, deepest corner):**

> A deserter from the Empire swears their armored machines shrug off
> blade and fire alike.{page}``Every armor fears one right tool,'' he
> said.{n}Find it, and even the Empire Breaks.

**$025D — the practice dare (right room, beside the monster chest):**

> Ha!{n}Sometimes monsters lurk inside of treasure chests!{page}The one
> beside me bites. Open it and practice your Breaks!

Every claim is implemented behavior: chip on element (ot6.asm chip
path) or weapon class (M3, ot6_class.asm), break = lost turns + ×2
until recovery with shields restored (Ot6Gate/Ot6BrokenDmg), reveals
replace '?' cells and persist in the SRAM codex, shielded resistance
×0.5 off-weakness (Ot6ShieldedDmg, finalized 0.5x), BP open 1 / +1 per
turn / cap 5 / spend ≤3 (Ot6InitBP, Ot6ActionEnd, Ot6Boost), no regen
on a boosted turn (Ot6ActionEnd), folds per Ot6FoldTbl with base-tier
MP (Ot6QueueFold), live list re-fold (Ot6PreviewList_ext). The seed pays off with
Edgar's Bio Blaster ("tool" is the wink) without naming it.

## Kept vanilla (lesson still true)

$0258 WoR greeter, $0259 spring, $025A/$06D4 save point, $025B pots,
$025C curatives, $025E/$06D2 relics ($06D2 is shared with a WoR scene —
out of fence anyway), $025F buttons, $0260 equip arrows, $0261 Wait
mode, $0262 run, $0263 ATB/pass, $0265 Row/Defense, $0266 pincer,
$0268 back row, $0269/$026A statuses, $026B undead, $026C Life 3/Regen,
$026F Runic/Morph/Dance/Rage (Runic is vanilla in the ROM today; the
+1-BP Runic is design, not code), $0271 experience, $0272 near-fatal,
$0273/$0274 espers (vanilla esper mechanics are what's live today),
$0275 SwdTech (charge gauge still live today), $0277–$027D color demo,
$03A5/$03A6 chocobo (shared with stables).

When Runic-as-BP, the Bushido menu, or magicite sub-jobs ship, $026F /
$0275 / $0274 become false and rejoin this exercise.

## Text-machine constraints (measured)

- **Source of truth:** `ff6/src/text/dlg1_en.json` (3084 entries,
  entry index = dialog id). `make text_en` runs `fix_dlg.py split` →
  `encode_text.py` (romtools) on both halves → `fix_dlg.py combine`;
  `romtools.encode_text` regenerates `include/text/dlg1_en.inc` /
  `dlg2_en.inc` offset includes itself (same path m3-impl.md:103-104
  verified for attack_msg). Identical strings dedup automatically.
- **Encoding:** char tables `dialog_en` + `dialog_escape` + `dte`.
  DTE pairs compress ~1.6:1; the encoder greedy-longest-matches. The
  ROM's DTE table (`dte_tbl_en.dat`) already agrees with the codec's
  `dte.json` — do **not** run `make dte` (it re-derives the table from
  the corpus and would churn every string).
- **Wrapping:** the field renderer word-wraps automatically — x starts
  at 4, a word that would reach x=$e0 (224) wraps
  (`src/field/text.asm` InitDlgText `lda #$e0 / sta $c8`,
  UpdateDlgTextOneLine `cmp $c8`). ~220px/line, proportional font
  (FontWidth, `src/gfx/font_gfx.asm`: lowercase mostly 7-8px, space
  5px). A page shows 4 lines; a 5th line auto-pauses for a keypress
  mid-page (vanilla's own long entries do this), but all-new pages
  here are written to wrap ≤4 lines. `{n}` only for structure.
- **Capacity:** dialog block = `fixed_block $01f100` (127,232 B) at
  cd/0000 (`src/text/text_main.asm:96`). The *checked-in* .dat files
  total 126,907 B — but they are ripped Square-original bytes; the
  repo encoder re-encodes the same text to ~118.5 KB (Square's tool
  wasn't greedy). First json edit rebuilds both banks: ROM dialog
  bytes churn wholesale (harmless — everything reaches dialog data
  through DlgPtrs, cc/e602), and real slack is ~8.4 KB. Built
  post-change total: 65,554 + 53,302 = 118,856 B (slack 8,376); the
  bank split lands at id 1715 (`Dlg1::ARRAY_LENGTH` → DlgBankInc).
- **Element glyphs in dialog:** the dialog charset maps $76–$7E to
  {fire}-style escapes, but no vanilla string uses them and the M2
  icons live in battle-font cells $eb–$ef/$fb–$fd only. Unverified in
  the field font — the copy uses words, not icons.

## Implementation

1. Replace the eight entries in `ff6/src/text/dlg1_en.json` (indexes
   599, 605, 612, 615, 621, 622, 624, 630).
2. Update the stale transcription comments at the `dlg` sites in
   `ff6/src/event/event_main.asm` (`_cc339c`, `_cc33b8`, `_cc33f0`,
   `_cc340f`, `_cc341b`, `_cc368e`, `_cc3692`, `_cc369a`, `_cc36b9`).
   Comments only; no script or NPC changes.
3. `make rom` — the .dat/.inc regenerate from the json edit.
4. Test: `tools/tests/school.lua` (smoke.lua pattern) — follows
   DlgPtrs (PRG 0x0CE602 + 2·id) into the dialog block (PRG 0x0D0000
   + ptr) and asserts the encoded bytes of two distinctive new
   strings ($0257 and $0276), so it self-locates across future text
   shifts. Added to `suite.sh` TESTS.

## Open items

- **L/R during targeting:** vanilla multi-target (the old $0264) may
  now collide with Ot6Boost, which watches L/R whenever `$7bca` says a
  battle menu is open. Needs a live check; if multi-target still
  works, it's undocumented in the school now (acceptable — vanilla
  discovery); if it half-works, that's an input-priority bug to file,
  not a text problem.
- **The magicite ghost ($0274)** teaches vanilla espers, which is what
  the ROM does today but contradicts the magicite-as-sub-jobs design.
  Rewrite belongs to the milestone that implements sub-jobs.
- **WoR door-opener shares $0257**: he now announces the new rules at
  the door in the World of Ruin — read and accepted (he is the
  school's own doorman; the line is world-state-neutral).
- **Element icons in school text** once the field font question above
  is settled — icons teaching icons would beat words.
