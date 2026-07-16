# OT6 Design — v0.1 (2026-07-14)

FF6 content, Octopath combat grammar. Mechanics-first: vanilla story, maps,
and encounters stay untouched at first; systems land, then encounters get
retuned around them.

Sections marked **TBD** are open design questions, not commitments.

Deep dives (2026-07-16, WoB scope): [character kits & learn
schedules](design/kits.md), [weapon classes & the break
spread](design/weapon-classes.md), [magicite sub-jobs](design/magicite.md).

**House rule: vanilla's bugs stay.** Useless stats, the Sketch bug,
row jank — the original game not being quite right is part of its
charm, and OT6 only touches vanilla behavior where a pillar demands
it.

## Pillars

1. **Sharp silhouettes.** Every character is one job: exactly 8 active skills
   (the 8th is a divine-tier finisher) plus up to 4 passives. No universal
   magic pool — nobody learns everything. **Signatures are birthrights:**
   each character's vanilla icon (Slots, Steal, Runic, Sketch, Capture, the
   first Tool/Blitz/Bushido/Dance…) is skill #1, free, from the moment they
   join. The divine slot holds a *new* apex expression of the character —
   never the identity itself.
2. **Break or be broken.** Every enemy has Shield Points and a hidden weakness
   set (elements + weapon classes). Chip shields by hitting weaknesses; at 0
   the enemy Breaks — loses its turn and takes double damage.
3. **Spend turns like money.** Boost Points: +1 per turn, bank up to 5, spend
   up to 3 to boost an action. Boosting costs next turn's BP gain.
4. **Magicite = second jobs.** Equipping a magicite grants its skill list and
   weapon access *while equipped* — nothing is taught permanently. One copy of
   each magicite exists, so kitting the party is a puzzle, exactly like
   Octopath's one-shrine-license-at-a-time rule.

## Why FF6 wants this

The fit is almost suspicious. Vanilla FF6 already ships **four perfect
8-skill jobs**: Edgar has exactly 8 Tools, Sabin exactly 8 Blitzes, Cyan
exactly 8 Bushido techniques, Mog exactly 8 Dances. Summons are already
once-per-battle (Octopath's divine-skill cadence). Espers already carry small
spell lists — we just change "teaches permanently" to "grants while
equipped." And Edgar's Debilitator already *sets elemental weaknesses on
enemies* — vanilla FF6 was flirting with this system in 1994.

## The cast as jobs

| Character | Job read | Weapon class | Element lean | 8-skill kit |
|---|---|---|---|---|
| Terra | Mage | Sword | Fire | 8 spells; divine: Ultima (see Trance below) |
| Locke | Thief | Dagger | Wind | Steal grows into a full thief kit: Steal, Mug, armor/attack corrode, BP theft **(TBD)** |
| Edgar | Machinist | Spear | Lightning | the 8 Tools, verbatim |
| Sabin | Monk | Claw | Fire/Holy | the 8 Blitzes, verbatim — button inputs stay |
| Cyan | Samurai | Katana | — | the 8 Bushido, priced in BP (see below) |
| Celes | Rune Knight | Sword | Ice/Holy | Runic from the start (signature) + spells (see below) |
| Gau | Beast Tamer | Fangs (innate) | Earth | Leap becomes Capture; controlled beast skills replace berserk Rage (see below) |
| Setzer | Gambler/Merchant | Cards & dice | — | Slots from the start (signature); Coin Toss, Hired Help (pay GP for effects); divine is a new apex — Fixed Dice jackpot? **(TBD)** — never Slots itself |
| Strago | Scholar | Rod | Fire/Ice/Lightning | 8 Lores, Aqua Breath as the free signature; **Analyze** (reveals shields and weaknesses) cheap at #2 |
| Relm | Painter | Brush | — | Sketch stays as signature; support/trickster kit **(TBD)** |
| Shadow | Assassin | Dagger (thrown) | Dark | Throw + Interceptor passives **(TBD)** |
| Mog | Dancer | Spear | varies by dance | the 8 Dances, verbatim |
| Umaro / Gogo | Berserker / Mime | — | — | bonus characters; Gogo = "every job, mastered none" |

**Weapon classes (8):** sword, dagger, spear, katana, claw, rod, ranged
(cards/dice/boomerangs/thrown), brush.
**Elements (8):** FF6's native fire, ice, lightning, wind, earth, water,
holy, poison — two more than Octopath's six, which only makes the weakness
matrix richer.

## Break system

**Data.** Each enemy gets `shield_max` (1–3 for trash, 4–12 for bosses) and
two weakness bytes — one elemental (enemy records already store elemental
weakness bits in vanilla), one weapon-class (new side table in expanded ROM).

**Chip.** Any damaging hit that matches a weakness removes 1 SP. Multi-hit
actions chip per hit — Edgar's AutoCrossbow and Cyan's Flurry become shield
shredders, exactly the role multi-hits play in Octopath.

**Break.** At 0 SP: the enemy's ATB resets and it's inflicted with a Broken
state (Stop-like) for roughly one full turn cycle; all damage it takes is
×2; its weakness list is locked revealed for the rest of the battle. On
recovery, shields reset to `shield_max`.

**Reveal.** Weaknesses start hidden. Chipping one reveals that entry;
Strago's Analyze reveals everything (he is the Cyrus of this party).

**Display is MVP-critical** (priority call 2026-07-14): the shield count and
revealed-weakness icons ARE the feel of an Octopath battle, so they ship
with the break system itself, not as later polish. First pass rides the
existing battle text engine: shield count beside each name in the monster
list window and weakness glyphs on target-select. The battle font already
contains weapon icon glyphs (dirk/sword/spear/… from item names); element
glyphs get added to the font. Per-monster OAM overlays (floating pips above
sprites) are the polish pass after that.

**Sources of chip by character** — this is the party-composition puzzle:
weapon attacks chip by weapon class; spells chip by element; each Blitz,
Tool, Lore, and Dance carries an assigned class or element (Aura Cannon is
holy, Drill is spear-class, Fire Dance is fire, ...). Full assignment table
**TBD** during M3.

## BP economy

- +1 BP when a character's turn comes up (ATB fills), capped at 5 — unless
  they boosted on their previous action (Octopath's no-regen rule, ported 1:1).
- Spend up to 3 BP when confirming an action. Attack: +1 hit per BP. Skills:
  potency tier per BP. Buffs/debuffs: duration per BP.
- Enemies don't have BP, same asymmetry as Octopath: bosses get shields and
  telegraphs, players get the economy.

**Boost tiers replace spell tiers.** Terra learns *Fire*, once. Boosted once
it casts as Fira; twice, Firaga. This is the single best trick in the design:
it keeps every spell list at 8 without losing the power curve, and it makes
boosting mean something on every kit, not just attackers.

**Cyan is the BP showcase.** The charge gauge — the most disliked mechanic in
vanilla — is deleted. Bushido becomes a normal menu of 8 techniques priced in
BP:

| # | Tech | BP |
|---|---|---|
| 1 | Fang | 0 |
| 2 | Sky (counter stance) | 1 |
| 3 | Tiger | 1 |
| 4 | Flurry (4 hits — shield shredder) | 2 |
| 5 | Dragon | 2 |
| 6 | Eclipse | 3 |
| 7 | Tempest | 3 |
| 8 | Oblivion | 3, usable only on a Broken enemy (divine) |

Candidate passive: *Vengeance* — Cyan gains +1 BP whenever any enemy breaks.

**Celes converts defense into economy.** Runic still swallows the next spell;
instead of (just) negating it, it grants her +1 BP. A Rune Knight literally
eats magic and turns it into tempo.

**Terra's Trance** **(TBD)**: candidate — usable only while an enemy is
Broken, or costs a full 5-BP bank. Either way it's her divine-tier state.

**Gau, controlled.** Leap becomes Capture (H'aanit's mechanic, which Rage
always secretly was). Captured beasts go in a stable; Gau equips up to 8 and
uses their signature moves as normal controlled skills. The 250-entry
berserk-roulette Rage table is retired.

## Turn structure: ATB stays (for now)

Phase 1 keeps ATB in Wait mode, which already approximates discrete turns —
"a turn" for BP purposes is each time a combatant's gauge fills. This keeps
the hack shippable: BP math is per-character, so it doesn't need global
rounds. A true round-based conversion with a visible turn-order queue (the
full Octopath feel) is a **stretch goal** — it means rewriting the ATB core
in the battle bank, and nothing above depends on it. (More attainable than
first assumed: RoSoDude's 2025 "Comprehensive ATB Enhancement" ships a
fully turn-based CTB mode *with published assembly* — see
research/prior-art.md.)

## Magicite as sub-jobs

Equipping a magicite grants, only while equipped:
- its spell/skill list (castable through the same boost-tier rules),
- possibly a weapon-class permit **(TBD)**,
- flat stat modifiers — replacing vanilla's permanent level-up bonuses, so
  builds are swappable, not grind-locked,
- its summon, once per battle, as the sub-job's divine skill.

Vanilla esper records already store a spell list with learn rates; we reuse
the list and ignore the rates. Uniqueness needs no code: there's one of each
magicite.

## Skill learning

Magic AP is rebadged as JP. Skill #1 — the signature — is free and known on
join. The remaining seven are bought in any order at escalating costs
(e.g. 80/200/450/800/1400/2200; divine: 3000 and requires the other seven). Passives unlock at 2/4/6/8 skills learned.
Sequencing note: the purchase menu lives in the menu bank — the fiddliest
code in FF6 — so early milestones use level-based unlocks and the JP menu
lands in M4. Fun mechanics don't wait on menu plumbing.

## Balance levers (known problems, planned answers)

- **Shields lengthen fights** → global enemy HP cut ~25–35% so the pace ends
  up "same length, more decisions."
- **Boss design** → bosses get telegraphs before big actions (Octopath's
  "gathering power…"), making break-timing the core boss puzzle.
- **Boosted damage vs the 9999 cap** → tune multipliers under the cap first;
  investigate raising the cap later. **(TBD)**
- **Save format** → JP reuses the existing per-character AP storage; BP and
  shields are battle-only state, so saves stay compatible.

## Out of scope (for now)

Story/dialog changes, new sprites beyond battle-UI elements, the full Rage
table (curated instead), multiplayer/controller-2 quirks.
