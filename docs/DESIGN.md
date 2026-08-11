# OT6 Design

FF6 content with Octopath's combat systems. Mechanics come first: vanilla
story, maps, and encounters stay untouched at first; systems land, then
encounters get retuned around them.

## The design goal

> *"We definitely want it to feel like FF6 just always had this improved
> Octopath-style battle system. It's FF6 first, that happens to have
> always had — wink wink — this really modern refined system."*

The goal is FF6 as if it had always been this way, rather than a mod of FF6.
Every decision is checked against that, which is why many of them look
conservative from outside:

- We use the FF3-US translation's names — SwdTech, Dispatch, Cleave —
  because that is what the player remembers (CONTRIBUTING).
- Caps are the series' own: 99, 999, 9999 (`mp-economy.md`).
- Vanilla's quirks stay; only destructive failures are fixed,
  and the Sketch bug ships as-is by owner decision.
- The Vargas triple-tutorial stays verbatim even though menu-Blitz made
  it mechanically unnecessary, because it is charm now (`bosses-wob.md`).
- Scripted set pieces draw no break gauge at all, so an empty HUD still
  marks the scene as scripted the way it did in vanilla.
- New systems reuse the engine's own machinery wherever it exists: the
  break flash uses vanilla's monster-palette slot, the sound uses vanilla's
  own sfx path, and the loadout pages follow vanilla's window geometry down
  to the cursor gutter.

This rules out the thing that makes hacks feel like hacks: a system that is
correct but calls attention to itself with new fonts, new vocabulary, numbers
that do not look like Final Fantasy numbers, or UI that does not sit where the
old UI sat. When a choice is between elegant and familiar, familiar wins
unless elegance buys something a player would notice.

### Why the SNES ROM, and not a GBA port or a Pixel Remaster mod

> *"I want it to feel like this game could have always been this way, and
> one way to do that is to prove it using the exact tools available to
> the original."* — owner

The platform choice is part of the claim, not a nostalgic constraint we
tolerate. Anyone can say FF6 could have shipped with a break-and-boost
system; building it in 65816 on the 1994 hardware, inside the machine's own
budgets, demonstrates it.

The limits are therefore part of the demonstration, and not obstacles to
route around. Each one we have hit is evidence:

- The battle HUD tick has under **80 cycles** of slack per frame; exceeding
  it makes the game run 10% slower (HANDOFF trap 2).
- Extra per-frame VRAM traffic pushes the engine's own transfers past
  vblank and freezes menus; ~13 words a frame was enough.
- Bank C4 has room for **two more event triggers** game-wide, which is
  what makes save-point placement a design problem rather than a
  bookkeeping exercise.
- WRAM is allocated a byte at a time out of a measured-free shadow tail,
  with asserts pinning the property that made each byte free.
- Costs cap at 99 partly because the field renders two digits.

Wanting to bypass one of these is a signal to redesign, not to expand.
ROM *space* is a separate matter: bank `$F0` is expansion, and larger carts
existed, so that is period-legitimate. The SNES's cycles, vblank, WRAM and
PPU are the limits that carry the claim.

For the harness this means everything is proven **in the emulator, on the
real ROM**, with no unit tests against a model of the game. That is why the
fixture chain exists at all, and why "it assembles" has never counted as
evidence here.

Sections marked **TBD** are open design questions, not commitments.

Deep dives (WoB scope): [character kits & learn
schedules](design/kits.md), [weapon classes & the break
spread](design/weapon-classes.md), [magicite sub-jobs](design/magicite.md),
[the MP economy](design/mp-economy.md), [balance
measurement](design/balance-metrics.md).

**House rule: vanilla's bugs stay.** Useless stats, the Sketch bug, and
row jank are part of the original game's charm, and OT6 only touches
vanilla behavior where a pillar requires it.

## Pillars

1. **Distinct characters.** Every character is one job: exactly 8 active
   skills (the 8th is a divine-tier finisher) plus up to 4 passives. There is
   no universal magic pool, and nobody learns everything. Each character's
   vanilla signature (Slots, Steal, Runic, Sketch, Rage, the first
   Tool/Blitz/SwdTech/Dance…) is skill #1, free, from the moment they
   join. The divine slot holds a *new* top-end ability for that character,
   never the signature itself.
2. **Shields and weaknesses.** Every enemy has shields and a hidden weakness
   set (elements + weapon classes). Chip shields by hitting weaknesses; at 0
   the enemy Breaks, loses its turn, and takes double damage.
3. **Boost Points.** +1 per turn, bank up to 5, spend up to 3 to boost an
   action. Boosting costs next turn's BP gain.
4. **Magicite are second jobs.** Equipping a magicite grants its skill list
   and weapon access *while equipped*; nothing is taught permanently. One copy
   of each magicite exists, so kitting the party is a puzzle, the same way
   Octopath allows one shrine license at a time.

## Why FF6 fits this

Vanilla FF6 already ships **four 8-skill jobs**: Edgar has exactly 8 Tools,
Sabin exactly 8 Blitzes, Cyan exactly 8 SwdTech techniques, Mog exactly 8
Dances. Summons are already once-per-battle, which matches Octopath's
divine-skill cadence. Espers already carry small spell lists, so we change
"teaches permanently" to "grants while equipped." And Edgar's Debilitator
already *sets elemental weaknesses on enemies*.

## The cast as jobs

| Character | Job read | Weapon class | Element lean | 8-skill kit |
|---|---|---|---|---|
| Terra | Mage | Sword | Fire | 8 spells; divine: Ultima (see Trance below) |
| Locke | Thief | Dagger | Wind | Steal grows into a full thief kit: Steal, Mug, armor/attack corrode, BP theft **(TBD)** |
| Edgar | Machinist | Spear | Lightning | the 8 Tools, verbatim |
| Sabin | Monk | Claw | Fire/Holy | the 8 Blitzes, selected from a menu |
| Cyan | Samurai | Katana | — | the 8 SwdTech, priced in BP (see below) |
| Celes | Rune Knight | Sword | Ice/Holy | Runic from the start (signature) + spells (see below) |
| Gau | Beast Tamer | Fangs (innate) | Earth | Rage learned without limit on the Veldt, 8 equipped (see below) |
| Setzer | Gambler/Merchant | Cards & dice | — | Slots from the start (signature); Coin Toss, Hired Help (pay GP for effects); divine is a new top-end ability — Fixed Dice jackpot? **(TBD)** — never Slots itself |
| Strago | Scholar | Rod | Fire/Ice/Lightning | 8 Lores, Aqua Breath as the free signature; **Analyze** (reveals shields and weaknesses) cheap at #2 |
| Relm | Painter | Brush | — | Sketch stays as signature; support/trickster kit **(TBD)** |
| Shadow | Assassin | Dagger (thrown) | Dark | Throw + Interceptor passives **(TBD)** |
| Mog | Dancer | Spear | varies by dance | the 8 Dances, verbatim |
| Umaro / Gogo | Berserker / Mime | — | — | bonus characters; Gogo has access to every job and masters none |

**Weapon classes (8):** sword, dagger, spear, katana, claw, rod, ranged
(cards/dice/boomerangs/thrown), brush.
**Elements (8):** FF6's native fire, ice, lightning, wind, earth, water,
holy, poison. That is two more than Octopath's six, which makes the weakness
matrix larger.

## Break system

**Data.** Each enemy gets `shield_max` (1–3 for trash, 4–12 for bosses) and
two weakness bytes — one elemental (enemy records already store elemental
weakness bits in vanilla), one weapon-class (new side table in expanded ROM).

**Chip.** Any damaging hit that matches a weakness removes 1 shield, and a
multi-hit action chips per hit (one boosted Fight chips four shields off one
guard — `multi-hit.md` §1, `probe_multihit.lua`). Multi-hit is rare: an audit
of all 256 `MagicProp` + 256
`ItemProp` records (`tools/audit_multihit.py`, which exits nonzero if it goes
stale) finds **three** multi-hit abilities in the whole game: Quadra
Slam ×4 and Quadra Slice ×4 (`MagicProp $58` effect `$32`,
`AttackerEffect_32` at `battle_main.asm:10794-10796`) and Empowerer ×2.
Edgar's AutoCrossbow hits the *whole enemy side* rather than hitting one
target several times: `ItemProp $aa` sets no extra-attack effect, so it lands
one hit per body and exactly **one** chip against a solo boss. Abilities that
strip several shields at once are the design target; `design/multi-hit.md`
§10 is the build list that would make that true.

**Break.** At 0 shields: the enemy's ATB resets and it is inflicted with a
Broken state for the length of a private broken timer at `$3e88,y` gated by
`Ot6Gate` (`ot6_break.asm:1655` — vanilla Stop is not used); all damage it
takes is ×2; its weakness list is locked revealed for the rest of the
battle. On recovery, shields reset to `shield_max`. `OT6_BREAK_TICKS` is
`$10` (`ot6_break.asm:1`), which measures **2159 frames** — about 36 s of
battle time — for an on-stage monster (`probe_ifritbreak.lua`). That is much
longer than the roughly-one-turn window the design wants; the constant is
deliberately left alone pending a balance call.

**Shielded resistance.** While an enemy still has shields and is not broken it
takes reduced damage (×0.5), so the swing from shielded to broken is ×4, and
×4 on-weakness too rather than ×2: vanilla's weakness ×2 (`asl $f0` at
`battle_main.asm:1899`) lands before `Ot6HitJoin` (`:1901`) applies the
shielded/broken factor, so the two stack. The full range against an
unbroken-unweak baseline is 8 (broken+weak) : 4 (broken) : 2 (shielded+weak)
: 1. The published 4:2:1 damage-per-BP measurement samples the
broken-and-unweak case, so it never measures the strongest state. Either way
the conclusion holds: boosting into an unbroken, non-weak target is the worst
return on BP, which is intended.

**Reveal.** Weaknesses start hidden. Chipping one reveals that entry;
Strago's Analyze reveals everything (the same role Cyrus fills in Octopath).

**Display ships with the break system**, not as later polish: the shield
count and revealed-weakness icons are how an Octopath battle reads to the
player. First pass rides the existing battle text engine: shield count beside
each name in the monster list window and weakness glyphs on target-select.
The battle font already contains weapon icon glyphs (dirk/sword/spear/… from
item names); element glyphs get added to the font. Per-monster OAM overlays
(floating pips above sprites) are the polish pass after that.

**Sources of chip by character.** This is what makes party composition a
puzzle: weapon attacks chip by weapon class; spells chip by element; each
Blitz, Tool, Lore, and Dance carries an assigned class or element (Aura
Cannon is holy, Drill is spear-class, Fire Dance is fire, ...). Full
assignment table **TBD**.

## BP economy

- +1 BP when a character's turn comes up (ATB fills), capped at 5 — unless
  they boosted on their previous action (Octopath's no-regen rule, ported 1:1).
- Spend up to 3 BP when confirming an action. Attack: +1 hit per BP. Skills:
  potency tier per BP. Buffs/debuffs: duration per BP.
- Enemies don't have BP, same asymmetry as Octopath: bosses get shields and
  telegraphs, players get the economy.

**Boost tiers replace spell tiers.** Terra learns *Fire*, once. Boosted once
it casts as Fira; twice, Firaga. This keeps every spell list at 8 without
losing the power curve, and it gives boosting a use on every kit rather than
only on attackers.

**The canon rule: on damage verbs boost multiplies; on chance verbs boost
guarantees.** A verb that rolls dice — Steal, Dance, and their family (Sketch,
Slot, Rage) — has no "potency" to tier, so BP buys *certainty* instead,
expressed in that verb's own vocabulary. Each point narrows the gamble and the
full 3-BP spend removes it. **Steal is the shipped example**
(Locke): 0 BP is vanilla to the byte, with the level roll, the 1/8 rare slot,
and the Sneak Ring doubling all untouched; each BP raises both the success
chance and the rare bias; 3 BP is a guaranteed steal that takes the rare item
*if the enemy has one*, since boost buys certainty rather than creating loot
the enemy never had. It deals no damage and takes no multiplier, because a
chance verb
answers to guarantee rather than potency, and keeping the two axes disjoint is
what keeps the rule easy to follow. Steal's tier table and the full ruling live
in design/kits.md; Dance's approved shape (built when Mog's milestone lands) is
there too.

**The third category: on reactive verbs, boost buys duration.** A verb that
does not act but *waits* — Runic, and every reactive verb after it — has
neither a potency to tier nor a die to load. What it has is a window, so BP
buys window. This follows from a rule already stated above: *buffs/debuffs get
duration per BP*, and a stance is a buff cast on the situation. **Runic is the
shipped example**: 1/2/3 BP buys 1/2/3 of Celes's own turns during which the
stance stands and **she acts normally**.

Those two halves are one lever and not two tiers, which is worth stating
because it is not obvious from outside the code: vanilla ends the stance the
moment she takes a turn, so letting her still act requires making the stance
outlive her action, which is duration. There is no 1-BP option that buys the
free turns without the window.

**Duration is counted in turns, not absorbs.** A turn count is something the
player can read ("three turns of shield"); an absorb count is visible only to
the fight. It also bounds the economy: the BP an absorb pays is capped at
**one per round**, the same cap #37 put on the True Knight cover, which was
itself mirrored from Runic's own machinery. With the cap, a 3-BP Runic is
BP-neutral against three ordinary turns and costs exactly one action. Without
it the earn scales with absorbs, and therefore with how many things are
casting and how long the stance stands, so it grows most in the fights the
stance is bought for. Measured (`battle_runic.lua`): four absorbable casts
into one round of a standing stance bank **+1** with the cap and **+2** on a
control build without it, on a fixture with a single caster.

**Cyan demonstrates the BP system.** The charge gauge, widely disliked in
vanilla, is deleted. The 8 techniques are priced in BP:

| # | Tech | BP |
|---|---|---|
| 1 | Dispatch | 0 |
| 2 | Retort (counter stance) | 1 |
| 3 | Slash | 1 |
| 4 | Quadra Slam (4 hits — strips four shields) | 2 |
| 5 | Empowerer | 2 |
| 6 | Stunner | 3 |
| 7 | Quadra Slice | 3 |
| 8 | Cleave | 3, usable only on a Broken enemy (divine) |

Boost *selects* the tech, the way it folds a mage's spell tier, and
vanilla's own count of techs known clamps the range to the best one Cyan has
learned. Every SwdTech carries a **1-BP floor**: `Ot6BushidoTech`
(`ff6/src/battle/ot6_kits.asm:74-79`) opens with `cmp #$01 / bcs :+ /
lda #$01`, so a stray 0 is clamped *up* to the cheapest tier rather than
allowed to name a tech, and the menu never offers boost 0 at all. The
mapping is `base = max(0, ceiling-2)`, `tech = min(base + boost-1, ceiling)`
(`ot6_kits.asm:65-70`), so boost 1/2/3 selects Cyan's **top three learned**
techs, weakest to strongest. The per-tech BP numbers in the table are
therefore not fixed prices; what a given tier costs slides as he learns
more, so read the column as the *relative* ordering it was drawn for. Pricing
consequences are in `design/kits.md` and `design/mp-economy.md`.

There is also a direct SwdTech submenu — `Ot6BushidoListOpen`
(`ot6_kits.asm:842`), dispatched from `btlgfx_main.asm:18237`, with per-row
greying by `Ot6BushidoRowGrey` and a field-configurable loadout word at
`$1e1d`. Boost selects the tech when the loadout is on AUTO; the submenu is
an additional surface, not a replacement.

Cleave is in the ladder and divine-gated: `Ot6BushidoOblivion`
(`ot6_kits.asm:141`) places tech 7 at boost 3 and drops a *spent* divine
back to Quadra Slice for the rest of the battle; the resolution-time Broken
gate is `Ot6Oblivion` (`ot6_kits.asm:250`), hooked after `ChooseTarget` in
`CalcAttackEffect`, because the target does not exist at command-latch time.
Mapping, consequences, and the reasoning: design/kits.md.

Candidate passive: *Vengeance* — Cyan gains +1 BP whenever any enemy breaks.

**Celes converts defense into economy.** Runic still swallows the next spell;
as well as negating it, it grants her +1 BP. **Boosted**, it stops being a
spent turn and becomes a standing magic shield: 1/2/3 BP holds the stance for
that many of her turns, and she fights through them. Against a caster boss
that is a different fight, and it is the one job nobody else has. The earn
stays capped at one BP per round so the shield cannot pay for itself, and
vanilla's quirk that Runic eats *ally* spells is kept: with the stance
standing for three turns it will eat a lot of Terra's Cures, which is both the
charm and the price.

**Terra's Trance** **(TBD)**: candidates are usable only while an enemy is
Broken, or costing a full 5-BP bank. Either way it is her divine-tier state.

**Gau, controlled.** Gau is the Ochette model — **learn many, equip 8** —
with Rage kept as the verb: Veldt learning stays unlimited and the 8 slots
are the equip layer (`Ot6RageCost` at `ot6_boost.asm:1181`; `Ot6RageLearned`
/ `Slot` / `Nth` / `List` / `Show` from `ot6_kits.asm:1882` onward, with the
model stated at `ot6_kits.asm:1860`). Leap keeps its name, because
CONTRIBUTING's vocabulary rule rules out *Capture*, which FF3-US already
prints as a battle command (`$06`, the Thief Glove). Leap is also free: it
shares the Fight row on the Veldt (`Ot6VeldtRow`, called from
`battle_main.asm:13977`) and costs nothing (`ot6_boost.asm:1186`). There is
no stable. `design/kit-gau.md` is the canonical Gau document.

## Turn structure: ATB stays (for now)

Phase 1 keeps ATB in Wait mode, which already approximates discrete turns:
"a turn" for BP purposes is each time a combatant's gauge fills. This keeps
the hack shippable, because BP math is per-character and does not need global
rounds. A true round-based conversion with a visible turn-order queue (the
full Octopath feel) is a **stretch goal**: it means rewriting the ATB core
in the battle bank, and nothing above depends on it. It is more attainable
than first assumed, since RoSoDude's "Comprehensive ATB Enhancement" ships a
fully turn-based CTB mode with published assembly.

## Magicite as sub-jobs

Equipping a magicite grants, only while equipped:
- its spell/skill list (castable through the same boost-tier rules),
- possibly a weapon-class permit **(TBD)**,
- its passives, one of them a stat bump — a fixed, constant upgrade, never
  a per-level bonus — learned for keeps by carrying the esper long enough
  (the one deliberate exception to while-equipped: design/magicite.md),
- its summon, once per battle, as the sub-job's divine skill.

Vanilla esper records already store a spell list with learn rates; we reuse
the list and ignore the rates. Uniqueness needs no code: there is one of each
magicite.

## Skill learning

Magic AP is rebadged as JP. Skill #1 — the signature — is free and known on
join. The remaining seven are bought in any order at escalating costs
(e.g. 80/200/450/800/1400/2200; divine: 3000 and requires the other seven). Passives unlock at 2/4/6/8 skills learned.
Sequencing note: the purchase menu lives in the menu bank, which is the
hardest code in FF6 to work in, so early milestones use level-based unlocks
and the JP menu lands in M4. Mechanics work does not wait on menu work.

## Balance levers (known problems, planned answers)

- **Shields lengthen fights** → shielded resistance carries the
  lengthening, not an HP dial: `Ot6HpMulTbl` is `$10` — 1× — in every range
  (`ff6/src/battle/ot6_break.asm:636-642`), because resistance is selective
  where a flat HP bump is not. See "Shielded resistance is the difficulty
  lever" below.
- **Boss design** → bosses get telegraphs before big actions (Octopath's
  "gathering power…"), making break-timing the core boss puzzle.
- **Boosted damage vs the 9999 cap** → tune multipliers under the cap first;
  investigate raising the cap later. **(TBD)**
- **Save format** → JP reuses the existing per-character AP storage; BP and
  shields are battle-only state, so saves stay compatible.

## Difficulty transform

Enemy narrative role, visual identity, and recognizable behavior are the
starting point, not immutable constraints. OT6 may author weaknesses,
AI, shields, and other combat properties when that creates a clearer
break puzzle or better pacing; changes should stay legible and preserve
the enemy's broad fantasy unless a deliberate redesign says otherwise.
Enemy **difficulty** numbers are likewise an OT6 tuning surface. The
current broad HP pass is applied as a *runtime transform*: at monster
seed time (the same bank-F0 hook that seeds shields), each
non-authored species' battle HP — current and max copies — is
multiplied by a per-species-range value in 16ths (`Ot6HpMulTbl`),
clamped at 16 bits. Authored `Ot6ShieldTbl` species are exempt (boss
difficulty is bosses-wob.md's job, planned as HP *cuts*), as are
scene-change battles whose monsters carry HP over. Stamina stays
derived from vanilla HP; fraction-of-HP attacks read the transformed
cells and scale with the monster.

**Shielded resistance is the difficulty lever, not the HP dial.**
`Ot6HpMulTbl` ships 1x in every species range; the mechanism is kept present
and neutral for future per-stretch bumps. A flat HP bump lengthens every
fight equally whether or not the player engages the loop. Resistance is
selective: it halves only off-weakness damage, so weakness-exploiters stay
vanilla-fast while players who ignore the loop take longer. Measured
damage-per-BP comes out 4:2:1 (broken : weak+chips : unbroken-unweak), and a
boost-into-sponge policy performs the same as never boosting. See
`design/balance-metrics.md` for the measurements and the resistance
section above for the mechanic.

Vanilla being too easy for the loop to express is still the problem
being solved: mines trash dies in one action, so neither boosting nor
breaking can fire. Resistance is the answer that stuck. Known limit:
no HP dial makes intro trash
expressive, because fire one-shots 15–24 HP mobs at any multiplier.
That is M6 class-weakness authoring, not a difficulty number.

The encounter economy carries its own pair, unrelated to HP:
`Ot6DangerMulW = $0008` (0.5x per-step danger, i.e. fewer fights) and
`Ot6RewardMulW = $0020` (2x xp+gil on random battles), so XP- and
gil-per-step stay ≈ vanilla. XP/gil are *not* vanilla per battle;
they are scaled by the inverse of the rate so the level curve keeps
vanilla's pacing.

## Scaling to endgame

How the balance plan survives late-game numbers:

- **Scale in hits, not multipliers** (soft guideline). FF6's 9999 per-hit
  cap saturates raw damage multipliers as base damage grows; extra hits,
  extra targets, extra effects, and tier-folds (Fire→Fira→Firaga→Ultima)
  scale straight past it. Late-game boost effects default to that shape;
  exceptions for story or flavor are welcome, since it is a default, not a
  law.
- **Do not work against the game's nature.** Vanilla's late-game power
  blowouts (Economizer, Gem Box, Offering…) are handled as they present
  themselves, not preemptively re-priced. Octopath itself is fun and breezy
  when overpowered, and the probe→break→nuke loop stays engaging independent
  of strict difficulty. This sharpens the house rule up top rather than
  contradicting it.
- **No per-level esper bonuses.** Vanilla's +1/+2-per-level esper bonuses
  are out of the sub-job model. Stat growth from magicite comes only as
  learnable-permanent passives — Octopath's Support Skills — each a fixed,
  constant upgrade, large but non-compounding. Octopath's sizing is ~+50 on
  a 999-scale stat; translate to FF6's stat ranges at tuning. Details:
  design/magicite.md.

## Out of scope (for now)

Story/dialog changes, new sprites beyond battle-UI elements, the full Rage
table (curated instead), multiplayer/controller-2 quirks.
