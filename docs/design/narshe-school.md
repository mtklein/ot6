# Narshe school — teaching what OT6 changes

The Narshe Beginner's House rewritten to explain OT6's new rules, in
plain words, instead of vanilla trivia. **Scope:** this change touches
the school's tutorial rooms only, and no story scenes or dialog
elsewhere.

Diff discipline: where an advisor's vanilla lesson is still true in OT6,
the vanilla text is kept byte for byte. Nine dialog ids change (eight
advisors rewritten, and $0274's Esper pages, which were vanilla and are
false in OT6); $026F's first page names the Boost Point; everything
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

## Lesson-to-advisor mapping

The owner's guideline ([guidelines.md](../guidelines.md), "Teach OT6
plainly, out of character"): the school explains what is new relative to
vanilla FF6, in plain words, out of character where that helps ("OT6
..."), with no mystery; each key OT6 mechanic a World of Balance player
meets is explained once and only once. Every advisor says what the rule
is, what the screen shows and which button to press, in the words the
game's own screens use (the shield and '?' cells under each monster, the
dots after each name, the R and L Buttons, the Magic list, "slashing",
"piercing", "bludgeoning" from the battle's own "Weak against ..."
messages). The 2026-09-28 rewrite (#289) replaced the first version's
lore voice ("Strike NOW!", "Greed loses", the deserter's riddle about
the Empire's plates), which players could not follow.

| Key mechanic (WoB) | Advisor | Room |
|---|---|---|
| Orientation; level-ups restore HP/MP; half as many random battles, double Exp./GP | $0257 greeter | outside the door, and the hall |
| Shields, half damage while shielded, breaking (can't act, ×2 damage), recovery | $0267 | middle (106) |
| Weaknesses: '?' cells, elements and weapon types, the Magic list's element icons and the weapon icons, the codex | $0264 | middle (106) |
| Boost Points: 1 at the start, +1 a turn, cap 5; R adds (up to 3), L takes back; no point on a boosted turn | $026D | left (105) |
| What a boost buys: Fight's extra hits (free); ×2/×4/×8 damage on other skills; MP ×2.5 a point, capped at 99 | $0270 | left (105) |
| Stronger spells: Fire → Fire 2 → Fire 3 and the other families, at the cast spell's MP; the Magic list previews | $026E | left (105) |
| Skills that changed: MP on Blitz/Tools/SwdTech/Steal/Dance/Rage; SwdTech rows; Steal/Slot/Rage odds (Steal and Rage certain at 3); Shadow's break kill | $0276 | left (105), far corner |
| Runic earns a Boost Point | $026F page 1 | left (105) |
| Espers: spells only while equipped, stat changes while equipped, no level-up bonuses | $0274 pages 4-5 | hall (the magicite ghost) |
| A practice fight | $025D page 2 | right (107), beside the monster chest |

Not taught here (each is shown where it is used, or is a detail of one
character's menu): Locke's Filch and Bestow (named in his Steal menu),
the boosted Runic stance, the True Knight cover's Boost Point, the Rage,
Lore and SwdTech loadout pages in the field menu, and allies the game
steers spending their points when hurt. Sabin's Blitz list is taught at
the Vargas fight, where the player first uses it (battle dialog $54-$56 and
$D4-$D8: choose Blitz, pick from the list, press A), and only there: $0276
used to repeat it (#301).

The player enters at the bottom-right; the door advisor speaks $0257
and unlocks the door, and the hall greeter repeats it. There is no forced
order (vanilla had none). The replaced advisors carried the most
expendable vanilla lessons: $0267 (numeral colors), $0264 (L/R
multi-target, now misleading, since R/L in battle menus boosts), $026D
(3-way attack trivia), $0270 (Image), $026E (Rflect fade), $0276
(Rflect bounce). $0274's "Learning Magic" pages were vanilla and are
false in OT6 (learn rates are all 0; `ot6_progression.asm`, M5), so they
are replaced; its first three pages (equipping and summoning an Esper)
are still true and kept byte for byte. The $025D advisor stands beside
the live monster chest (event battle group 0: Soldier + Lobo), so his
second page points at a fight the player can take immediately.

## The copy (final)

Conventions are vanilla's: ```` `` '' ```` for quoted terms, `_` = …,
`{n}` hard line break, `{page}` next box (shown below as *(next box)*);
the renderer word-wraps automatically (see constraints below). No page
runs past four lines, measured in game (`tools/tests/school.lua`, below).

**$0257 — greeter (spoken by the door advisor outside in both worlds, and by the hall greeter in the World of Balance):**

> This is a classroom for beginners. Our advisors explain the basics, and what OT6 changes.
>
> *(next box)*
>
> Also new: a level-up fully restores HP and MP. Random battles come half as often, but give double Exp. and GP.

**$0267 — shields and breaking (middle room):**

> Under each monster is a shield icon with a number: its shields. While it has shields, it takes half damage.
>
> *(next box)*
>
> Each hit on a weakness removes one shield. At zero it breaks: it can't act for a while and takes double damage.
>
> *(next box)*
>
> A broken monster's shield icon shows an X. When it recovers, its shields come back.

**$0264 — weaknesses: the ? marks, elements and weapon types, the codex (middle room):**

> The ? marks next to the shield are weaknesses you haven't found yet. A weakness is an element or a weapon type.
>
> *(next box)*
>
> In battle, the Magic list shows a spell's element as an icon. A weapon's icon shows its type.
>
> *(next box)*
>
> Fight uses your weapon's type: swords and claws slash, spears and knives pierce, rods bludgeon.
>
> *(next box)*
>
> Hit a weakness and its ? turns into an icon. The game remembers it for every later battle.

**$026D — Boost Points and the R/L Buttons (left room):**

> The dots after each name in battle are Boost Points.
>
> *(next box)*
>
> Each character starts a battle with 1, and gains 1 after each of their turns, up to 5.
>
> *(next box)*
>
> While choosing a command, press the R Button to add a point: up to 3, if you have them. Arrows show how many.
>
> *(next box)*
>
> Press the L Button to take one back. Boosting uses up those points, and you gain no new point that turn.

**$0270 — what a boost buys: Fight, damage skills, the MP price (left room):**

> A boosted Fight hits once more for each point, and costs no MP.
>
> *(next box)*
>
> Boosting a Blitz, Tool, Lore, Esper or most spells does 2x damage for 1 point, 4x for 2, and 8x for 3.
>
> *(next box)*
>
> Those cost more MP when boosted: 2.5x per point, but never over 99.

**$026E — stronger spells from a boost (left room):**

> Fire, Ice, Bolt, Poison, Cure, Life, Slow and Haste work differently: a boost turns them into stronger spells.
>
> *(next box)*
>
> Boost Fire by 1 point and it casts Fire 2. By 2 points, Fire 3. A 3rd point adds nothing.
>
> *(next box)*
>
> You pay the MP of the spell that is cast. The Magic list shows its name and cost as you press the R Button.

**$0276 — skills that work differently (left room, far corner):**

> In OT6, Blitz, Tools, SwdTech, Steal, Dance and Rage cost MP. If you can't pay, the skill is greyed out.
>
> *(next box)*
>
> Cyan's SwdTech: there is no charge gauge. It lists his three best skills, for 1, 2 and 3 Boost Points.
>
> *(next box)*
>
> Steal, Slot and Rage: each Boost Point improves the odds instead of adding damage.
>
> *(next box)*
>
> With 3 points, Steal always works and gets the rare item, if any, and Rage always uses its special.
>
> *(next box)*
>
> Shadow: once a battle, his hit that breaks a monster, or hits a broken one, kills it. Most bosses just stay broken.

**$025D — the practice fight (right room, beside the monster chest):**

> Ha! / Sometimes monsters lurk inside of treasure chests!
>
> *(next box)*
>
> The chest beside me has monsters in it. Open it to practice what you learned here.

**$0274 — Espers (the magicite ghost in the hall; first three pages vanilla):**

> To use an Esper it must be equipped. Choose ``Skills'' from the menu, then select ``Espers.''
>
> *(next box)*
>
> During battle, select Magic, and press up on the Control Pad. Press the A Button to use the Esper.
>
> *(next box)*
>
> Remember, an Esper can only be used once per battle.
>
> *(next box)*
>
> In OT6, the character who equips an Esper can cast its spells. Unequip it and the spells go too. Nothing is learned.
>
> *(next box)*
>
> Many Espers also change their holder's stats while equipped. There are no stat bonuses at level up.

Every claim was checked against the code (2026-09-28):

- Shields and breaking: the shield cell under each monster draws the
  count (1-6; a count above 6 draws as 6) and a grey shield with an X
  while broken (`ot6_hud.asm`, the BG3 cells under each sprite). Every
  damaging hit on a shielded, unbroken monster is ×0.5, on or off
  weakness (`Ot6ShieldedDmg`, `Ot6ShieldedMulW = $0008`); a hit on a
  weakness chips 1 (`Ot6Chip`, `Ot6ClassChip`; a hit matching both an
  element and a class chips 2); at 0 the broken timer (`OT6_BREAK_TICKS`
  = $10, about 36 s of battle time) stops new actions (`Ot6Gate`) and
  doubles damage (`Ot6BrokenDmg`); recovery refills the shields.
- Weaknesses: '?' until chipped, then the element or class icon; the
  reveal is written to the save's codex at once and pre-revealed in later
  battles (`ot6_codex.asm`, `ot6_break.asm`). Magic-list element icons:
  `Ot6AbilityPad_ext`. Weapon types: `Ot6WeapClassTbl`
  ([weapon-classes.md](weapon-classes.md)).
- Boost Points: open at 1 (`Ot6InitBP`), +1 at the end of an unboosted
  action, cap 5, the pending points subtracted and no +1 on a boosted
  one (`Ot6ActionEnd`); R raises the pending boost to at most 3 and never
  past the bank, L lowers it (`ot6_hud.asm`, the boost input handler).
- What a boost buys: Fight/Capture swings (`Ot6FightBoost`); ×2/×4/×8
  on every other damage verb outside the gate list (`Ot6BoostDmg`); the
  MP price `min(99, round(base × 2.5^boost))` on exactly those
  (`Ot6BoostPriceFor`, [mp-economy.md](mp-economy.md)). Dance is left
  out of $0270's list on purpose: only the dance's first step carries
  the boost (the pending boost clears at that turn's end).
- Stronger spells: `Ot6FoldTbl` (Fire, Ice, Bolt, Poison, Cure, Life,
  Slow, Haste), `Ot6FoldSteps` clamps a boost of 3 to two tiers, the
  cast tier's own MP (`Ot6QueueFold` → `Ot6SpellMP`), and the Magic
  list's live names and prices (`Ot6PreviewList_ext`, `Ot6FoldPrices`).
- Skills: prices and greys ([mp-economy.md](mp-economy.md),
  `Ot6KitConfirmMP`); SwdTech's three
  rows at 1/2/3 BP over Cyan's top three techs (`ot6_bushido.asm`);
  Steal/Slot/Rage odds (`ot6_steal.asm`, `ot6_slot.asm`, `ot6_rage.asm`);
  Shadow's break kill (`ot6_divine.asm`, death-immune targets only
  broken).
- Outside battle: `Ot6LevelUpHeal`; `Ot6DangerMulW = $0008` (half the
  encounter rate) and `Ot6RewardMulW = $0020` (double Exp. and GP, random
  battles only).
- Espers: learn rates 0 and the while-worn spell grant
  (`Ot6EsperSpellKnown`); `Ot6EsperStatTbl` (several Espers carry no
  stat change, hence "Many"); the vanilla level-up bonus bytes are $ff.

## Kept vanilla (lesson still true)

$0258 WoR greeter, $0259 spring, $025A/$06D4 save point, $025B pots,
$025C curatives, $025E/$06D2 relics ($06D2 is shared with a WoR scene,
so it is out of scope anyway), $025F buttons, $0260 equip arrows, $0261 Wait
mode, $0262 run, $0263 ATB/pass, $0265 Row/Defense, $0266 pincer,
$0268 back row, $0269/$026A statuses, $026B undead, $026C Life 3/Regen,
$0271 experience, $0272 near-fatal, $0273 the Esper prompt, $0274's
first three pages, $0275 SwdTech names (the charge gauge is gone, and
this line never mentioned it), $0277–$027D color demo, $03A5/$03A6
chocobo (shared with stables), $025D's first page.

## $026F names the Boost Point

Runic absorbs the next spell for MP **and** +1 BP (Ot6RunicBP,
ff6/src/battle/ot6.asm, hooked into vanilla's RunicEffect), so $026F
(Runic/Morph/Dance/Rage) says so. Only page 1 changes; the Morph and
Dance/Rage pages are untouched:

> ``Runic''
> Turns many magic attacks into MP, and earns a Boost Point! Can be
> used repeatedly.

"Boost Point" is the term $026D teaches, so this line reuses
vocabulary the player has already seen instead of introducing a new one.
Page 1 renders 4 lines, which is the page maximum and the same count the
Morph page already uses, so no 5th-line auto-pause is introduced.

## Text-machine constraints (measured)

- **Source of truth:** `ff6/src/text/dlg1_en.json` (3084 entries,
  entry index = dialog id). `make text_en` runs `fix_dlg.py split` →
  `encode_text.py` (romtools) on both halves → `fix_dlg.py combine`;
  `romtools.encode_text` regenerates `include/text/dlg1_en.inc` /
  `dlg2_en.inc` offset includes itself (the same path already verified
  for `attack_msg`). Identical strings dedup automatically.
- **Encoding:** char tables `dialog_en` + `dialog_escape` + `dte`.
  DTE pairs compress ~1.6:1; the encoder greedy-longest-matches. The
  ROM's DTE table (`dte_tbl_en.dat`) already agrees with the codec's
  `dte.json`. Do **not** run `make dte`: it re-derives the table from
  the corpus and would churn every string.
- **Wrapping:** the field renderer word-wraps automatically. x starts
  at 4, and a word that would reach x=$e0 (224) wraps
  (`src/field/text.asm` InitDlgText `lda #$e0 / sta $c8`,
  UpdateDlgTextOneLine `cmp $c8`). ~220px/line, proportional font
  (FontWidth, `src/gfx/font_gfx.asm`: lowercase mostly 7-8px, space
  5px). A page shows 4 lines; a 5th line auto-pauses for a keypress
  mid-page (vanilla's own long entries do this), but all-new pages
  here are written to wrap ≤4 lines. `{n}` only for structure.
  `tools/tests/school.lua` checks this in game: the number of pages the
  window waits on must equal the text's `{page}` count + 1, so a page
  that ran to a 5th line (one more wait) fails it.
- **Capacity:** dialog block = `fixed_block $01f100` (127,232 B) at
  cd/0000 (`src/text/text_main.asm:96`). The *checked-in* .dat files
  total 126,907 B, but they are ripped Square-original bytes; the
  repo encoder re-encodes the same text to ~118.5 KB, because Square's
  tool was not greedy. The first json edit rebuilds both banks, so ROM
  dialog bytes churn wholesale. That is harmless, since everything
  reaches dialog data through DlgPtrs, cc/e602. Built after the
  plain-words rewrite (#289): 65,540 + 54,043 = 119,583 B, slack 7,649;
  the bank split lands at id 1684 (`Dlg1::ARRAY_LENGTH` → DlgBankInc).
- **Element glyphs in dialog:** the dialog charset maps $76–$7E to
  {fire}-style escapes, but no vanilla string uses them and the M2
  icons live in battle-font cells $eb–$ef/$fb–$fd only. Unverified in
  the field font, so the copy uses words rather than icons.
