# OT6 Design

FF6 content with Octopath's combat systems.

Vanilla's bugs — useless stats, the Sketch bug, row jank — stay; OT6 only
touches vanilla behavior where a pillar requires it.

## Pillars

1. **Distinct characters.** Every character is one job: up to 8 active
   skills, the 8th a divine-tier finisher where the job has a natural one
   (a character whose kit is one verb, or a varied set with no best member
   such as Mog's Dances or Gau's Rages, needs none; owner, 2026-11-15). There is
   no universal magic pool, and nobody learns everything. Each character's
   vanilla signature (Slots, Steal, Runic, Sketch, Rage, the first
   Tool/Blitz/SwdTech/Dance…) is skill #1, free, from the moment they
   join. The divine slot holds a *new* top-end ability for that character,
   never the signature itself.
2. **Shields and weaknesses.** Nearly every enemy has shields and a hidden
   weakness set (elements + weapon classes); eleven authored rows have none
   and draw no gauge, where the fight is not a break fight (the Whelk's and
   Presenter's shells, Chadarnook, the Magic Urn, the Zone Eater, Tritoch). Chip shields by hitting weaknesses; at 0
   the enemy Breaks, loses its turn, and takes double damage.
3. **Boost Points.** Start each battle with 1, +1 at the end of each
   action, bank up to 5, spend up to 3 to boost an action. A boosted action
   earns no BP.
4. **Magicite are second jobs.** Equipping a magicite grants its spells and
   its summon *while equipped*; no spell is taught permanently. What a
   character keeps is the esper's ladder: Magic Points from battles won
   wearing it buy five ranks of stat points and relic-style effects, kept for
   good ([esper-rework.md](design/esper-rework.md), built in v0.44). One copy
   of each magicite exists, so kitting the party is a puzzle, the same way
   Octopath allows one shrine license at a time. Gau can wear espers; Umaro
   and Gogo cannot.

## The cast as jobs

| Character | Job read | Weapon class | Element lean | 8-skill kit |
|---|---|---|---|---|
| Terra | Mage | Sword | Fire | 8 spells; divine: Trance (Morph at a full boost); Ultima is Fire's fourth fold |
| Locke | Thief | Dagger | — | Steal, Filch, Bestow, Mug, Trickshot, Dismantle, Appraise; divine: Master's Mark |
| Edgar | Machinist | Spear (and Sword: swords, the Chain Saw) | — | seven Tools, learned by acquisition; divine: Overclock. Air Anchor is a findable extra |
| Sabin | Monk | Fist (bare hands, claws) | Fire/Holy/Wind | the 8 Blitzes, selected from a menu |
| Cyan | Samurai | Katana | Wind | the 8 SwdTech, priced in BP (see below) |
| Celes | Rune Knight | Sword | Ice | Runic from the start (signature) + spells (see below) |
| Gau | Beast Tamer | Fist (bare hands) | varies by rage | Rage learned without limit on the Veldt, 8 equipped (see below); no divine (a varied set needs none; owner, 2026-11-15) |
| Setzer | Gambler/Merchant | Arcane (cards, dice) | — | Slot from the start (signature), with Coin Toss and Hired Help (paid in gil) behind it; divine: Jackpot, a Fixed-Dice triple, never Slot itself (kits.md) |
| Strago | Scholar | Arcane (rod) | varies by lore | Lores (five equipped), Aqua Rake as the free row; **Analyze** (Scan: reveals every weakness of a species), always his, 3 MP; divine: Study, his Scan at a full boost, which learns every lore the monsters present could cast; Bserk, learned by watching a monster inflict Berserk (kits.md) |
| Relm | Painter | Arcane (brush) | — | Sketch (signature) with the party's buffs behind it, a list like Locke's: Portrait (a free boost point), Tint (an ally's weapon carries the colour she picks), Varnish (the next enemy hit misses), Still Life (a break lasts twice as long), Underpainting (the next weakness hit takes two shields), Gesture (an ally's turn now); divine: Masterpiece (every other ally's free point). Built ([kit-relm.md](design/kit-relm.md), #538) |
| Shadow | Assassin | Dagger (thrown), Katana (ninja blade) | Fire/Water/Lightning (the skeans) | Throw (signature) over the eight throwing items, learned by acquisition as Edgar's Tools are: three stars, three skeans (Dagger and an element), the smoke (Image) and the exit (Vanish), whose boost buys reach (kits.md "Shadow"); divine: Assassinate, at a full 3-BP boost (kits.md "Divines"): the hit of his that breaks an enemy kills it outright, as does a hit on one already Broken; a boss is only Broken. Every throw hobbles (Slows) an enemy and pins (Stops, 8 ticks) a Slowed one ([kit-shadow-pin.md](design/kit-shadow-pin.md), #546) |
| Mog | Dancer | Spear | varies by dance | the 8 Dances, verbatim; no divine for now (kits.md "Divines") |
| Umaro | Berserker | Fist (club, bare hands) | Ice | takes no orders; four arms (Fight, Charge, Throw, Storm); divine: Storm, ice on every enemy, on a dump of all three points (kits.md "Umaro") |
| Gogo | Mime | Arcane (rod) | — | bonus character; has access to every job and masters none |

**Break classes (6):** Sword (swords), Dagger (daggers, thrown stars and
edges, darts), Spear (spears and lances), Katana (katanas, ninja blades),
Fist (bare hands, claws, flails, clubs) and Arcane (rods, brushes, cards,
dice, boomerangs), `OT6_SWORD` .. `OT6_SPEAR` in `ot6_class.asm`;
`Ot6WeapClassTbl` gives every weapon one. The column above is each
character's own class; [weapon-classes.md](design/weapon-classes.md) has
every class each can equip into. Through v0.50 there were four (slash,
pierce, bludgeon, special).
**Elements (8):** FF6's native fire, ice, lightning, wind, earth, water,
holy, poison. That is two more than Octopath's six, which makes the weakness
matrix larger.

## Break system

**Data.** Each enemy gets `shield_max`, one `Ot6ShieldTbl` row per species
the game deals: 1–3 for trash (2 for most), 4–6 for the strongest commons
and the monster-box guards, 4–12 for bosses, the Storm Drgn's 14 and Kefka's
16 at the top of his tower above that, and 0 for a body that draws no gauge
(a scripted set-piece, or a marker for a body no battle deals). It also gets
two weakness bytes — one elemental (enemy records already store elemental
weakness bits in vanilla), one weapon-class (new side table in expanded ROM).

**Chip.** Any damaging hit that matches a weakness removes 1 shield, and a
multi-hit action chips per hit (one boosted Fight chips four shields off one
guard; `multi-hit.md` §1). A few takes ignore weakness: the Break spell,
Filch, each of Bum Rush's four blows, Cleave's four on a death-immune body.
Ramuh's Conductor adds a second shield to a lightning hit that already
matched. Multi-hit is deliberately
scarce: `tools/audit_multihit.py` (which exits nonzero if it goes stale)
enumerates **six** multi-hit abilities in the whole game, spread over the
three physical kits. Cyan's are vanilla's — Quadra Slam ×4 and Quadra Slice ×4
(`MagicProp $58`/`$5b` effect `$32`, `AttackerEffect_32`) and Empowerer ×2. Sabin's Pummel ×2 and Bum
Rush ×4 and Edgar's Drill ×2 come from `Ot6HitCountTbl`
(`ff6/src/battle/ot6_hitcount.asm`), which adds to the same `$3a70` counter;
each of those three has its power divided by its hit count, so the extra hits
buy break rate rather than damage.
Edgar's AutoCrossbow hits the *whole enemy side* rather than hitting one
target several times: `ItemProp $aa` sets no extra-attack effect and has no
table row, so it lands one hit per body and exactly **one** chip against a
solo boss. Breadth and rate are separate levers and are priced separately;
`design/multi-hit.md` is the survey.

**Break.** At 0 shields (`Ot6Chip` / `Ot6ClassChip`) the enemy is Broken
for the length of a private timer at `$3e88,y`; no ATB cell is written.
While the timer runs `Ot6Gate` refuses to queue its turns (vanilla Stop is
not used) and `Ot6BrokenTurn` empties a turn it had already queued, so its
gauge refills and waits; every hit that lands on it while Broken is ×2. A
break reveals no
weaknesses. On recovery (`Ot6Tick`), shields reset to `shield_max`. `OT6_BREAK_TICKS` is
`$10` (`ot6_break.asm:1`), which measures **2159 frames** — about 36 s of
battle time — for an on-stage monster (`probe_ifritbreak.lua`, deleted).
A body that returns from death is fresh: a monster the AI restores
(`Ot6Arrive`, Cmd_24) or Life or Reraise raises (`Ot6Revive`) comes back
with full shields, not Broken and with no marks, keeping only its revealed
weaknesses (#557).

**Shielded resistance.** Every hit is judged on the enemy's state before it
lands. While an enemy still has shields it takes reduced damage (×0.5), and
the hit that takes its last shield is one of those hits: it lands on a
shielded enemy, so it is halved and not doubled. Only a hit on an enemy that
is already Broken takes ×2; in a multi-hit action, the hits after the one
that breaks (owner, 2026-11-15, #542: "the hit that breaks should not
benefit from dropped shields", which gives each monster about one more
shield's worth of hits; through v0.45 the breaking hit skipped the ×0.5 and
took the ×2, measured at 784 against the 190 of the chips before it on the
Whelk's head, `battle_break`). `Ot6HitBroke` marks the slot whose last
shield a take removes (`OT6_HITBRK`), `Ot6ShieldedDmg` halves a marked hit
and `Ot6BrokenDmg` withholds its ×2 and clears the mark. Shadow's
Assassinate still kills on the breaking hit: its gate reads the break, not
the damage. The swing from shielded to broken is ×4, and ×4 on-weakness too
rather than ×2: vanilla's weakness ×2 (`asl $f0` in `CalcTargetDmg`) lands
before `Ot6HitJoin` applies the shielded/broken factor, so the two stack.
The full range against an unbroken-unweak baseline is 8 (broken+weak) : 4
(broken) : 2 (shielded+weak) : 1. The published 4:2:1 damage-per-BP
measurement samples the broken-and-unweak case, so it never measures the
strongest state. Either way the conclusion holds: boosting into an
unbroken, non-weak target is the worst return on BP, which is intended.

**Reveal.** Weaknesses start hidden. Chipping one reveals that entry
(`Ot6RevealCommit`, for every monster of the species) and it stays revealed,
across battles too: the per-save codex seeds it at the next battle's start
(`Ot6SeedShields`). A character's Scan reveals every weakness of its
target's species at once (Strago's Analyze, the role Cyrus fills in
Octopath; kits.md "Strago").

**Display ships with the break system**, not as later polish: the shield
count and revealed-weakness icons are how an Octopath battle reads to the
player. Under each monster, one line on the battlefield's text layer: the
shield gauge, a shield emblem and the count in the battle font's own
numerals, both plain white, and then the weaknesses, a grey '?' for each
unrevealed one and its element or weapon-class icon once revealed (the
battle font already holds the weapon glyphs, from item names). The gauge
takes no element's hue, so a count does not read as one of the keys: #397
drew it gold on navy, the lightning and holy icons' yellow, and a revealed
bolt beside the count read as a smear of it (owner, 2026-11-14). White is
also the wind and weapon-class icons' colour, and the '?' grey earth's: the
battle text palettes hold no other white or mid grey. A broken monster shows a broken
shield where the gauge was; its sprite keeps its colours (#543 removed
v0.45's grey sprite, which a formation with three monster palettes could not
show). The gauge, a revealed weakness, the break's white flash and its
cleave change when the hit that caused them visibly lands, one hit at a time
(#539): an action's hits are all computed before its battle script plays
them, so the HUD draws a held copy of each monster's gauge (`OT6_HOLD`,
`OT6_SHOWN`) that each damage numeral advances to the state its hit left
(`Ot6NumQueued` notes it as the numeral is queued, `Ot6RevealPoll` shows it
when the script reaches that numeral), and the script's end shows the rest.
Display only: every rule reads the live state.

**Sources of chip by character.** This is what makes party composition a
puzzle: weapon attacks chip by weapon class; spells chip by element; each
Blitz, Tool, Lore, and Dance carries an assigned class or element (Aura
Cannon is holy, Drill is spear-class, Fire Dance is fire, ...).

## BP economy

- +1 BP at the end of each of a character's actions (`Ot6ActionEnd`),
  capped at 5, unless that action was boosted (Octopath's no-regen rule).
  Every character opens a battle with 1 BP (`Ot6InitBP`).
- Spend up to 3 BP when confirming an action. Attack: +1 hit per BP. Skills:
  potency tier per BP. Single-target statuses and cures: one more body per BP.
  Def., Row, Leap and Possess take no boost.
- The cell beside each name shows the bank as the player has seen it
  happen (owner, #540: "visible until the ability that uses them begins,
  and should not visibly regenerate until that player becomes active").
  A pending boost shows as arrows from the press until its action begins,
  confirmed and queued included; from then the pips show the bank less the
  pending points, which `Ot6ActionEnd` charges when the action ends. The
  regen point shows when its character is next active (its window opens or
  its next action begins), a cover's or an absorb's point when the blow or
  spell lands. Display only (`Ot6PipFace`, `OT6_BPMARK`): every rule reads
  the bank and the pending byte, which move when they always did; the
  owner's wording is about what is visible, and moving the bank would move
  every BP decision in the game.
- Enemies don't have BP, same asymmetry as Octopath: bosses get shields and
  telegraphs, players get the economy.
- Boosting also costs MP, when the boost is buying damage. A boosted
  ability pays `max(base, min(99, floor(base × 2.5^boost + 0.5)))`
  (`Ot6BoostPriceFor`) — x1 / x2.5 / x6.25 / x15.625, capped at 99 and never
  below the base. Where the boost buys more of the same (the reach spells,
  Debilitator's weaknesses, Filch's shields) each point is its own use and
  the price is `base × (1 + boost)`, capped the same (`Ot6PerPointPrice`).
  So a boost is a trade of two currencies rather than a free
  multiplier. The multiplier's rule is one test: **a price escalates by
  x2.5 exactly when the boost multiplies the action.** So Fight and Capture stay free (the boost
  buys swings), tier-family magic and SwdTech are unchanged (the boost
  already buys a dearer tier), and the chance verbs — **Steal, Rage and
  Slot** — stay flat at every level, because their boost buys certainty
  across a spread of outcomes rather than magnitude, and the BP it costs is
  what pays for that. MP scales with magnitude; BP alone pays for certainty.
  mp-economy.md's "Boosting costs MP" has the rule, the table and the
  rulings.
- Never a refund (owner, 2026-10-22): a boosted action either charges
  nothing, isn't allowed a boost, or keeps what was spent.
- Every boost buys something (owner, 2026-10-22). An action with no reward
  for boosting doesn't take a boost: R can't raise one on it, and its price
  doesn't escalate. Where the reward is only known when the action runs (a
  Steal on a body with nothing left, Scan with one body standing), the boost
  is spent, fruitlessly: the player chose it. (An action refused for lack
  of MP never happened and keeps its boost; a Mimic copy is free in every
  case.) Each such action is a design
  opportunity: what would a boost naturally buy, and which boost family
  does it join (#469; the survey and proposals are
  [design/boost-rewards.md](design/boost-rewards.md)).

**Boost tiers replace spell tiers.** Terra learns *Fire*, once. Boosted once
it casts as Fira; twice, Firaga. This keeps every spell list at 8 without
losing the power curve, and it gives boosting a use on every kit rather than
only on attackers.

**The canon rule: on damage verbs boost multiplies; on chance verbs boost
guarantees.** A verb that rolls dice — Steal, Dance, and their family (Slot,
Rage) — has no "potency" to tier, so BP buys *certainty* instead,
expressed in that verb's own vocabulary. Each point narrows the gamble and the
full 3-BP spend removes it. **Steal is the shipped example**
(Locke): 0 BP is vanilla to the byte, with the level roll, the 1/8 rare slot,
and the Sneak Ring doubling all untouched; each BP raises both the success
chance and the rare bias; 3 BP is a guaranteed steal that takes the rare item
*if the enemy has one*, since boost buys certainty rather than creating loot
the enemy never had. It deals no damage and takes no multiplier, because a
chance verb
answers to guarantee rather than potency, and keeping the two axes disjoint is
what keeps the rule easy to follow. Steal's tier table and the full ruling
live in design/kits.md.

**Dance carries both halves (#473).** A Dance's boost multiplies every step
of the dance it starts, and since #473 it also loads the one die a Dance
rolls: off its own terrain, vanilla's start stumbles on a coin (an even
draw from the battle RNG table, exactly 1/2). That coin is the same one
Rage's special rides, so Dance takes Rage's ladder unchanged: a stumble
1/2 at 0 BP (vanilla's roll, untouched), 1/4 at 1, 1/16 at 2, never at 3.
It is still one payoff: the boost buys the dance at that tier, and starting
is part of the dance. A stumble spends the boost, because the odds were
bought and the roll was taken, and charges no MP, because the MP pays for
the dance's magnitude, which never began. MP scales with magnitude; BP
pays for certainty. The ladder and its derivation are in design/kits.md
(Mog).

Sketch is neither: it takes the boost of whatever it drew. A sketched attack
with a number multiplies; one with none drops the boost once the brush has
drawn it (boost-rewards.md).

**The third category: on reactive verbs, boost buys duration.** The three
families are potency (the multiplier or the tier), certainty (the chance
verbs) and reach or duration. Fourteen single-target status spells and cures
buy reach: a point covers one more body (`ot6_reach.asm`; boost-rewards.md),
and Shadow's smoke and exit do the same. A verb that does not act but *waits*
— Runic, and every reactive verb after it — has neither a potency to tier nor
a die to load. What it has is a window, so BP buys window; Morph's boost buys
a longer span in the same way. A stance is a buff cast on the situation.
**Runic is the shipped example**: 1/2/3 BP buys 1/2/3 of Celes's own turns during which the
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
| 1 | Dispatch | 1 |
| 2 | Retort (counter stance) | 1 |
| 3 | Slash | 1 |
| 4 | Quadra Slam (4 hits — strips four shields) | 2 |
| 5 | Empowerer | 2 |
| 6 | Stunner | 3 |
| 7 | Quadra Slice | 3 |
| 8 | Cleave | 3 (divine: a full boost is its one gate) |

Boost *selects* the tech, the way it folds a mage's spell tier, and
vanilla's own count of techs known clamps the range to the best one Cyan has
learned. Every SwdTech carries a **1-BP floor**: `Ot6BushidoTech`
(`ff6/src/battle/ot6_bushido.asm`) opens with `cmp #$01 / bcs :+ /
lda #$01`, so a stray 0 is clamped *up* to the cheapest tier rather than
allowed to name a tech, and the menu never offers boost 0 at all. The
mapping is `base = max(0, ceiling-2)`, `tech = min(base + boost-1, ceiling)`
(its `@auto` block, with `Ot6BushidoCeil`), so boost 1/2/3 selects Cyan's **top three learned**
techs, weakest to strongest. The per-tech BP numbers in the table are
therefore not fixed prices; what a given tier costs slides as he learns
more, so read the column as the *relative* ordering it was drawn for. Pricing
consequences are in `design/kits.md` and `design/mp-economy.md`.

There is also a direct SwdTech submenu — `Ot6BushidoListOpen`
(`ot6_cmdmenu.asm`), dispatched from `btlgfx_main.asm`, with per-row
greying by `Ot6BushidoRowGrey` (`ot6_cmdmenu.asm`) and a field-configurable loadout word at
`$1e1d`. Boost selects the tech when the loadout is on AUTO; the submenu is
an additional surface, not a replacement.

Cleave is in the ladder as the divine: tech 7 is only ever the window's
3-BP row (`Ot6CleaveSlot` keeps it out of the 1- and 2-BP loadout slots),
a random SwdTech (Muddle, Charm, the Colosseum) stops short of it
(`Ot6RandBushidoTop`), and its effect is decided in `Ot6Oblivion`
(`ot6_divine.asm`), hooked after `ChooseTarget` in `CalcAttackEffect`,
because the target does not exist when the command is entered: it
strikes every enemy: Death on each killable body, and on a death-immune one
four shields lost and a power-255 cut.
Mapping, consequences, and the reasoning: design/kits.md.

**Celes converts defense into economy.** Runic still swallows the next spell;
as well as negating it, it grants her +1 BP. **Boosted**, it stops being a
spent turn and becomes a standing magic shield: 1/2/3 BP holds the stance for
that many of her turns, and she fights through them. Against a caster boss
that is a different fight, and it is the one job nobody else has. The earn
stays capped at one BP per round so the shield cannot pay for itself, and
vanilla's quirk that Runic eats *ally* spells is kept: with the stance
standing for three turns it will eat a lot of Terra's Cures, which is both the
charm and the price.

**Gau, controlled.** Gau is the Ochette model — **learn many, equip 8** —
with Rage kept as the verb: Veldt learning stays unlimited and the 8 slots
are the equip layer (`Ot6RageCost` in `ot6_boost.asm`; `Ot6RageLearned`
/ `Slot` / `Nth` / `List` / `Show` in `ot6_rage.asm`, with the model stated
in that file's header). Leap keeps its name, because
CONTRIBUTING's vocabulary rule rules out *Capture*, which FF3-US already
prints as a battle command (`$06`, the Thief Glove). Leap is also free: it
shares the Fight row on the Veldt (`Ot6VeldtRow`, called from
`battle_main.asm`) and costs nothing (`Ot6RageCost`). There is
no stable. `design/kit-gau.md` is the canonical Gau document.

## Turn structure

ATB is vanilla's: Wait or Active as the player sets it in Config (a new
game starts on Wait, `menu_sram.asm`); OT6 does not force either. "A turn"
for BP purposes is each action a character finishes. BP math is
per-character and does not need global rounds.

## Magicite as sub-jobs

While worn, a magicite grants its spells (castable through the same
boost-tier rules) and its summon, vanilla's once-per-battle summon (not a kit
divine: the kit divines' one gate is a full 3-BP boost, design/kits.md).
Nothing else is rented: the old while-worn stat package is gone.

What stays is the ladder (v0.44, esper-rework.md). Each won battle that pays
Magic Points gives them to every living seated member for the esper that
member wears; random battles pay double, the bench earns none. Five ranks, at
10, 30, 75, 200 and 500: two stat points, a small effect such as an
immunity, two more points, and a relic-tier signature. A rank once reached
stays with that character whatever they wear later. Odin and Raiden share
one count. Vanilla's learn rates are all zero and are ignored. Uniqueness
needs no code: there is one of each magicite. Gau can wear espers and earns
ranks; Umaro and Gogo cannot.

## Skill learning

Set aside (owner, 2026-11-15): the game keeps the mix it grew into --
some abilities learned naturally, some found, some unlocked by wearing
espers -- and no JP purchase is planned. A battle's Magic Points buy esper
ranks (esper-rework.md). The old plan, kept for the record: magic AP
is rebadged as JP. Skill #1 — the signature — is free and known on
join. The remaining seven are bought in any order at escalating costs
(e.g. 80/200/450/800/1400/2200; divine: 3000 and requires the other seven).
Passives unlock at 2/4/6/8 skills learned.

## Difficulty transform

Enemy difficulty numbers are an OT6 tuning surface. The current broad HP
pass is applied as a *runtime transform*: at monster seed time (the same
bank-F0 hook that seeds shields), each non-authored species' battle HP —
current and max copies — is multiplied by a per-species-range value in
16ths (`Ot6HpMulTbl`), clamped at 16 bits. Authored `Ot6ShieldTbl` species
are exempt (boss difficulty is bosses-wob.md's job), as are scene-change
battles whose monsters carry HP over. Stamina stays derived from vanilla HP;
fraction-of-HP attacks read the transformed cells and scale with the
monster.

**Shielded resistance is the difficulty lever, not the HP dial.**
`Ot6HpMulTbl` ships 1x in every species range. A flat HP bump lengthens
every fight equally whether or not the player engages the loop. Resistance
is selective: it halves only off-weakness damage, so weakness-exploiters
stay vanilla-fast while players who ignore the loop take longer. Measured
damage-per-BP comes out 4:2:1 (broken : weak+chips : unbroken-unweak), and a
boost-into-sponge policy performs the same as never boosting. See
`design/balance-metrics.md` for the measurements.

The encounter economy carries its own pair, unrelated to HP:
`Ot6DangerMulW = $0008` (0.5x per-step danger, i.e. fewer fights) and
`Ot6RewardMulW = $0020` (2x xp+gil on random battles), so XP- and
gil-per-step stay ≈ vanilla. XP/gil are *not* vanilla per battle;
they are scaled by the inverse of the rate so the level curve keeps
vanilla's pacing.
