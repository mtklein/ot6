# A boost reward for every action (#469)

Scope: every action a player can take in battle, what a boost buys on it
today, and a proposal for each one that buys nothing. DESIGN.md's rule is the starting point: "Every boost buys
something (owner, 2026-10-22). An action with no reward for boosting
doesn't take a boost ... Each such action is a design opportunity: what
would a boost naturally buy, and which boost family does it join."

## What is built

The first tranche (#469, `wt/boost-rewards`): the four holes are closed and
proposals 1, 3, 4 and 5 are built; proposal 2 is declined.

- **The four holes.** NoiseBlaster refuses the boost (`Ot6ToolNoBoost`: R
  is refused on its Tools row, a boost raised on the command window is
  dropped at the queue, `Ot6QueueFold`, and its price is flat,
  `Ot6ToolPrice`). Certainty, proposal 4's reward for it, would buy nothing:
  a tool's hit rate is ItemProp +21, `$FF`, and CheckHit takes `$FF` as a
  certain hit, so its Confuse already lands wherever an immunity does not
  stop it. Air Anchor was never a hole: its ItemProp +20 power is 128, a
  piercing hit the multiplier doubles (measured, `lab_anchor`, in the
  commit that dropped it from the refusal), so it keeps the multiplier and
  its escalating price. Debilitator has its reward (proposal 4). MagiTek
  Confuser and X-fer refuse it (`Ot6RowNoBoost`'s MagiTek arm, R on the cell;
  `Ot6QueueFold`'s, a boost raised before), and so does the Gravity Rod used
  from Item (`Ot6ItemNoBoost` reads an equipment's cast spell, ItemProp +18
  bit 7, through `Ot6SpellNoBoost`: Quartr is a fraction). A Sketch whose drawn
  attack has no number, or is a reach spell (reach serves Magic and
  X-Magic only, and a sketch keeps command `$0D`), drops its boost once the
  brush has drawn it (`Ot6SketchNoBoost`, in Cmd_0d before `_c21554`); the
  menu cannot refuse R, since the draw is a roll. **This is a deliberate
  exception to #463's rule** that a boost only the resolve shows was useless
  is spent (a Steal on a robbed body): the TLM's call in #469's review, since
  a Sketch cannot know its draw when it is chosen. Suites: `battle_boostreach` (NoiseBlaster, the
  Gravity Rod), `battle_magitekboost`, `battle_sketchboost`.
- **Proposal 1, reach**, as written below, for the fourteen spells
  (`Ot6ReachTbl`, `ot6_reach.asm`). `Ot6SpellReach` runs in CalcAttackEffect
  right after ChooseTarget; it and Shadow's `Ot6TrickReach` share one walk,
  `Ot6ReachWalk`, which passes over a body that is not standing, a vanished
  one for a physical attack, a reflecting one for a reflectable spell, and one
  on which none of the attack's statuses would change (`Ot6ReachLands`: set
  mode, a status it lacks and may take; lift mode, one it holds). Imp and
  Vanish toggle (MagicProp +4 bit 3): their reach follows the body aimed at,
  lifting the status from the others that hold it when that body holds it,
  setting it otherwise. The price is per point, not per body reached: a
  point that finds nobody is still paid for, as a Scan's is. Vanish at a
  monster reaches nobody and its boost is dropped at the queue. The price is
  per body, base x (1 + boost) capped at 99 (`Ot6PerPointPrice`, through
  `Ot6MagicPrice`). Suite: `battle_boostreach` (Safe at 0, 1 and 2 points,
  Imp at a monster).
- **Proposal 2, Def., is declined** (owner, 2026-11-13: leave Defend
  unboostable). Def. keeps refusing the boost as before (`Ot6CmdNoBoost`, a
  boost raised on the command window is dropped); `battle_boostkeep`'s Def.
  cases still hold it.
- **Proposal 3, Bestow**, as written: the pips pending, one at 0 or 1 point,
  as many as the ally can hold, and Locke is charged exactly those
  (`Ot6Bestow`). Suite: `battle_boostkeep`.
- **Proposal 4, Debilitator**: one firing and one more a point, stopping
  when the body has no element left (`Ot6DebilSteps`, a loop in
  TargetEffect_56), priced per firing (`Ot6ToolPrice`: 10 / 20 / 30 / 40,
  80 overclocked). Suite: `battle_boostreach`.
- **Proposal 5, Filch**, as written: `Ot6TakeShields` with one plus the
  points, the first shield banking the pip, priced per shield
  (`Ot6ThiefCharge`, `Ot6ThiefRowCost`: 6 / 12 / 18 / 24). A boost that finds
  no shield (a Broken or shieldless body) is spent: only the resolve can tell.
  Suite: `battle_boostkeep`.

`Ot6PerPointPrice` is mp-economy.md's per-body arm, beside the multiplier's
x2.5 and the chance verbs' flat price.

## What a boost point buys

A point buys more of what the action already does, never a new kind of
effect (guidelines: "Boost pays once"). The shipped examples, which every
proposal below copies:

| family | a point buys | shipped on |
|---|---|---|
| swings | two more swings of the same weapon | Fight, Capture, Mug (`Ot6FightBoost`) |
| passes | one more pass of the same action, each its own hit and chip | Coin Toss, Hired Help, GP Rain, Umaro's Throw, Jackpot's two rolls |
| tier | the next spell of the line, at that spell's own price | Fire/Ice/Bolt, Poison→Bio, Cure, Life, Slow→Slow 2, Haste→Haste2 (`Ot6FoldTbl`); SwdTech's window |
| multiplier | x2/x4/x8 on the number the action produces | everything else with a number: Blitz, Tools, Lore, Dance steps, Throw, Jump, Trickshot, items that heal (`Ot6BoostDmg`) |
| certainty | a narrower gamble; the full boost removes it | Steal, Slot's rig, Rage's coin, Dance's stumble |
| duration | more of the user's own turns the effect stands | Runic (1/2/3 of Celes's turns), Morph (596/800/993 ticks, permanent at 3) |
| reach | one more body, in battle order, wrapping | Shadow's smoke and exit tricks (`Ot6TrickReach`); Scan and Appraise (every enemy at a point) |
| steps or shields | one more application of the same effect | Dismantle (a corrode a point), Break (a shield a point) |

Haste→Haste2 and Slow→Slow 2 are worth reading twice: vanilla's own second
tier of a single-target status is the same status on every body. Reach is
that move for the statuses whose line has no second spell.

## Every player action today

"Refused" means R buzzes on the row or the boost is dropped before it is
charged (#463: `Ot6RowNoBoost`, `Ot6SpellNoBoost`, `Ot6ItemNoBoost`,
`Ot6CmdNoBoost`). "Spent for nothing" means the pips (and an escalated
price, where the row escalates) are taken and nothing is bought: by the
guidelines, a bug.

| action | what a boost buys today |
|---|---|
| Fight, Capture, Mug | swings |
| Jump (Dragoon Boots) | the multiplier (command `$16` is outside `Ot6BoostDmg`'s gate; read, not played) |
| Item: Potion, Tonic, Ether and the rest that heal a number | the multiplier |
| Item: equipment used as a spell (rods, shields) | the multiplier, when the spell has a number; refused when it has none (the Gravity Rod, #469) |
| Item: Antidote, Eyedrop, Soft, Remedy, Green Cherry, Echo Screen | refused |
| Item: Fenix Down, Revivify, X-Potion, X-Ether, Elixir, Megalixir, Tent, Sleeping Bag | refused (fractions) |
| Item: Smoke Bomb, Warp Stone | refused |
| Magic, tier lines | the tier |
| Magic with a number (Drain, Pearl, Flare, Quake, Merton, Osmose, Ultima...) | the multiplier |
| Scan | every enemy at a point; Study at 3 (Strago) |
| Break | a shield a point |
| Magic, single-target statuses: Safe, Shell, Rflect, Vanish, Bserk, Regen, Antdot, Remedy, Mute, Sleep, Muddle, Stop, Imp, Dispel | reach (#469; Vanish on the party only) |
| Magic, death: Doom, X-Zone | refused |
| Magic, fractions: Demi, Quartr, W Wind | refused |
| Magic: Float, Warp, Quick | refused |
| X-Magic | each spell as its own; dropped only when neither buys anything |
| Lore with a number | the multiplier |
| Lore: Condemned, Roulette, Big Guard, L.5 Doom, L.3 Muddle, Reflect???, ForceField, Dischord, Sour Mouth, Pep Up, Rippler | dropped at the turn's end (no R refusal yet: the Lore window is not read) |
| Summon with a number | the multiplier |
| Summon: Hope Song, Demon Eye, Cat Rain, Sonic Dive, Atom Edge, True Edge, Metamorph, Life Guard, Wall, Ruby Power, Fader, Earth Wall, Heal Horn, Moon Song, Rebirth | dropped (`Ot6QueueFold`) |
| Def. | refused (`Ot6CmdNoBoost`) |
| Row | refused (`Ot6CmdNoBoost`) |
| Morph | duration; Trance at 3 (Terra) |
| Revert | refused (`Ot6RevertTake`) |
| Runic | duration; RunicBlade at 3 (Celes) |
| Steal | certainty |
| Filch | a shield a point (#469) |
| Bestow | the pips pending (#469) |
| Trickshot | the multiplier |
| Dismantle | steps |
| Appraise | every enemy at a point |
| Master's Mark | the divine (Locke) |
| SwdTech | the tech (the cursor row is the boost); Cleave at 3 (Cyan) |
| Blitz | the multiplier; Bum Rush at 3 (Sabin) |
| Tools with a number: AutoCrossbow, Bio Blaster, Flash, Drill, Chain Saw | the multiplier; Overclock at 3 (Edgar) |
| Tools without one: NoiseBlaster | refused (#469) |
| Air Anchor (power 128, pierce) | the multiplier |
| Debilitator | a weakness a point (#469) |
| Throw, a damaging item | the multiplier |
| Throw, the smoke and the exit | reach |
| Slot | the rig's certainty |
| Coin Toss, Hired Help | passes |
| Jackpot | the divine (Setzer) |
| Dance | the multiplier on every step, and the stumble's certainty |
| Rage | the coin's certainty |
| Leap | refused (`Ot6CmdNoBoost`) |
| Sketch | the multiplier when the sketched attack has a number; dropped when it has none (#469) |
| Control, and the commanded monster's attacks | refused (`Ot6CmdNoBoost`, at the head of both branches) |
| Mimic | what the copied action's boost buys; kept where that is nothing |
| Umaro's arms | swings, the multiplier, throws; Storm at 3 |
| Assassinate | the divine (Shadow) |
| MagiTek beams with a number, Health, Shock | the multiplier |
| MagiTek: Confuser, X-fer | refused (#469) |
| Possess | refused (`Ot6CmdNoBoost`) |

### Holes to close whatever is decided

Four actions take a boost today and buy nothing. Each should be refused
now, in the same build that closes it, and get its reward later if the
proposal below is taken:

- **Edgar's numberless Tools.** NoiseBlaster (base 6), Debilitator (10)
  and Air Anchor (14) sit in `Ot6AbilityCostTbl` beside the damaging tools
  and escalate with them (mp-economy.md's table: "NoiseBlaster / Flash | 6
  | 15 | 38 | 94", "AuraBolt / Debilitator | 10 | 25 | 63 | 99"), and
  `Ot6RowNoBoost` has no Tools arm (its tools-shell branch tests only the
  thief mode, `cmp #$03 ; thief mode`, `build/attempts/wt/design-boost-every-action/rownoboost.txt`).
  None of the three deals damage, so a boosted one pays up to 94 or 99 MP
  and three pips for the unboosted effect. (Flash, priced beside
  NoiseBlaster, does deal damage: `7E Flash tgt=6a mp=0 pow=42`,
  `spellprops.txt`.) That the three deal no damage is vanilla's
  description, not measured here.
- **A Sketch whose attack has no number.** The sketched attack runs under
  its own command (`_c21554`: `jsr GetCmdForAI ; sta $b5`), so nothing
  queued it as Magic and `Ot6QueueFold`'s no-reward verdict never forms.
  Read, not played.
- **MagiTek Confuser and X-fer**, and **the Gravity Rod used from Item**:
  from #469's opening comment ("Confuser/X-fer and the Gravity Rod from
  Item still spend").

## The proposals

Each names its family, the ladder, the price, the divine it must stay clear
of, how the esper rework's signatures change it ([esper-rework.md](esper-rework.md),
Plan A), and a build estimate. Byte estimates are anchored on shipped procs
measured from the assembled listing (`procsize.py` over
`ff6/obj/battle_en.lst` at de4ee995, `build/attempts/wt/design-boost-every-action/procsizes.txt`).
Size is not the constraint: OT6's whole battle-side `.proc` code is
"297 procs, 18267 bytes" in bank F0's 1 MB (`bank_f0: ... size = $100000`).
The real cost of each is its suite and the regeneration it forces.

### 1. Reach for single-target statuses and cures

**Safe, Shell, Rflect, Vanish, Bserk, Regen, Antdot, Remedy** on the party;
**Mute, Sleep, Muddle, Stop, Imp, Dispel** on the side they are aimed at.

- **Family: reach.** A point covers one more body on the target's side,
  in battle order after the target and wrapping, passing over one the
  status cannot land on; three points cover a party of four. This is
  Haste→Haste2 for the lines vanilla gave no second spell. Each of these
  is single-target only in vanilla: `Safe tgt=01`, `Shell tgt=01`,
  `Rflect tgt=01`, `Vanish tgt=01`, `Bserk tgt=01`, `Regen tgt=03`,
  `Mute tgt=41`, `Stop tgt=41`, `Dispel tgt=41` (targeting byte, no
  multi-target bit `$20`; `spellprops.txt`). Float (`tgt=21`) already
  spreads and stays refused.
- **Price: each body pays its own cast**, base × (1 + boost), capped at 99:
  Safe 12 / 24 / 36 / 48, Rflect 22 / 44 / 66 / 88. Vanilla prices its own
  party tier this way (`Haste tgt=01 mp=10`, `Haste2 tgt=29 mp=38`), and
  Overclock and Coin Toss are OT6's precedent for "priced as the casts it
  replaces". This is a new price arm beside the one test (a point that
  multiplies escalates, a point that buys certainty is flat); see the
  owner questions.
- **Divines.** Doom and X-Zone are left out on purpose: Doom on four
  bodies at 3 BP is most of Cleave ("each killable one dies"). They take
  certainty instead (proposal 8). Vanish reaches allies only: Vanish on
  an enemy makes vanilla's death spells land (a vanilla bug left vanilla),
  and spreading it across a formation would rebuild the same mass kill.
- **Esper rework.** The masteries that put a status on for every battle
  (Kirin's Regen, ZoneSeek's Shell, Alexandr's Safe) take the need for
  reach away from their holders, so this proposal is worth most in the
  World of Balance and on the bench's rotations, less in the late World
  of Ruin. Carbunkl's *Facet* (two points at the start) makes a two-body
  Safe or Shell the natural opening turn. Shiva's half-MP and the
  Economizer cut the per-body price as they cut every price.
- **Build: ~150-200 bytes, M.** Generalize `Ot6TrickReach` ("Ot6TrickReach
  97 bytes"), which already places reach in battle order and passes over a
  body that cannot take it, from the thrower's side to the target's side;
  a 14-byte spell table; the per-body arm in `Ot6MagicPrice`; drop the
  fourteen from `Ot6SpellNoBoost` ("55 bytes"). One suite in the shape of
  `battle_shadowkit`.

### 2. Def.: the guard stands for more of your turns

- **Family: duration**, the reactive verb's canon (DESIGN.md: "on reactive
  verbs, boost buys duration"). A point keeps the guard (physical damage
  halved, `$3aa1.1`) through one more of the defender's own turns, and she
  acts normally in them, exactly as a boosted Runic stands. Vanilla clears
  the guard in `QueueAction` (`@0328: jsr ClearDef`), two instructions
  before the Runic hold already sits (`jsl Ot6RunicHold ; ot6: ...unless
  boost bought this Runic a`; `sites.txt` lines 541 and 545), so the hook
  is the same one.
- **Price:** free (Def. is on the free floor); the points are the price.
- **Divines.** RunicBlade is the 3-BP Runic and bounces spells; a 3-BP
  guard bounces nothing and blocks nothing magical. No overlap.
- **Esper rework.** Golem's signature (cover allies at low HP) makes a
  boosted guard the tank's turn: the cover-er halves what it covers for.
  Alexandr's Safe-every-battle stacks with it (Safe and the guard each
  halve), the same stack vanilla allows a Defending Safe body today.
  *Facet* allows a two-turn guard on turn one.
- **Build: ~50 bytes, S.** A raise at `Cmd_15` in place of
  `Ot6CmdNoBoost` (cf. "Ot6RunicRaise 23 bytes") and a hold after
  `ClearDef` (cf. "Ot6RunicHold 29 bytes"), four bytes of battle RAM for
  the turns left. One suite: the bank, the halved hit on a later turn, the
  guard gone after the last turn.

### 3. Bestow hands as many pips as are pending

- **Family: more of the same** (the issue's "its own pip ladder"). Bestow
  at one point hands one pip, as today; at two, two; at three, three. A
  pip the ally cannot hold (the bank caps at 5) is not handed and not
  charged, as today's refusal at the cap already works. `Ot6Bestow` sets
  the pending to one today ("a pending boost the player raised with L/R is
  set to the one pip, not added to"); it would keep the pending instead.
- **Price:** flat 5 MP; the pips are the price, and they leave Locke.
- **Divines.** It feeds a divine but is not one: a Locke with three banked
  can put an ally at three on the ally's next turn. The arithmetic: the
  ally opens at 1 and banks one a turn, so it reaches 3 at its third turn;
  Bestow 3 moves that to its second. A divine stays one a turn at most
  per character.
- **Esper rework.** *Facet* on Locke opens him at two, so he can hand two
  on his first turn. *Grace* (points kept through KO) protects what was
  handed.
- **Build: ~15 bytes net, S.** Change one store in `Ot6Bestow` ("Ot6Bestow
  63 bytes") and remove its row from `Ot6RowNoBoost`. `battle_bestowrefuse`
  and `battle_boostkeep` move to the new numbers.

### 4. Edgar's numberless Tools

- **Debilitator: one more weakness a point.** Family: more of the same
  (the steps family). Each point runs the add-a-weakness effect again,
  each new bit revealed as today's is (`Ot6DebilReveal`), until the body
  has no element left to take. Price: each weakness its own firing,
  10 / 20 / 30 / 40, replacing an escalation that today buys nothing.
  Overclock (two firings, each at the 3-BP price) becomes 80 MP for up to
  eight weaknesses. No divine overlap: Master's Mark reads weaknesses, it
  does not add them. Ramuh's *Conductor* (one more shield on lightning
  spells) pairs well with a lightning weakness added, and does not overlap.
  Build: ~65 bytes, S (a loop around the effect and a linear price arm).
- **NoiseBlaster and Air Anchor: certainty** on their hit, through the
  shared leaf of proposal 8, flat price (6 and 14 at every boost). Until
  that lands, refuse them (a Tools arm in `Ot6RowNoBoost`, ~25 bytes).

### 5. Filch takes a shield a point

- **Family: shields**, Break's ladder: one shield, plus one a point, four
  at three, class-blind as Filch already is. Only the first shield banks a
  pip; the rest are just shields. Otherwise a 3-BP Filch would pay back
  four pips for three spent.
- **Price: each shield its own Filch**, 6 / 12 / 18 / 24, so that four
  shields cost about what Break's four do (Break is 25 flat).
- **Divines.** Bum Rush and Cleave each strip four shields as part of a
  full-boost action that also does damage; a 3-BP Filch strips four and
  does nothing else. Close enough to name, not close enough to refuse.
  This one also crowds Break, Terra's and Shoat's one shield verb: the
  price parity is the answer.
- **Esper rework.** No signature touches it.
- **Build: ~45 bytes, S.** `Ot6TakeShields` exists ("38 bytes"); Filch
  calls it with the count and its row leaves `Ot6RowNoBoost`.

### 6. Status-cure items reach

- **Antidote, Eyedrop, Soft, Remedy, Green Cherry, Echo Screen: reach.**
  One item, one more ally a point, as the smoke and exit tricks already
  reach with one item. Price: the item; no MP. The full-heal fractions
  (X-Potion, Elixir, Megalixir, Tent, Sleeping Bag, X-Ether) stay refused:
  their party version is a separate item in the shop (Megalixir, Tent),
  and reach would sell it for one Elixir's price.
- **Build: ~25 bytes, S.** Add the six ids to `Ot6TrickReach`'s item test
  (it already runs on the item path) and exempt them in `Ot6ItemNoBoost`.

### 7. Control: certainty on the take, the multiplier on the commands

- **The take: certainty.** Control rolls the level ratio (`CheckSketchHit`:
  caster level × 256 / target level, the Coronet discounting the target's
  level) and hits outright when the caster is at the target's level or
  above. Steal's ladder fits unchanged: +40 effective levels at one point,
  +90 at two, no roll at three (`Ot6StealBoostLevel`'s shape, "49 bytes").
  A body that cannot be controlled still cannot be: boost never overrides
  an immunity, as boost never creates loot. Price flat (Control's planned
  8-12 at every boost).
- **The commands: the multiplier.** Each commanded attack is its own turn
  with its own number, so the default family applies; `Ot6CmdNoBoost`
  moves off that branch.
- **Divines.** None near.
- **Build: ~30 bytes, S.**

### 8. Certainty for status and death that rolls

**Doom, X-Zone, Condemned; NoiseBlaster, Air Anchor; Confuser, X-fer;
Hope Song, Demon Eye, Cat Rain, Metamorph.**

- **Family: certainty.** Each point narrows the status's hit roll against
  magic evasion; three points skip the roll. An immunity is never
  overridden. Flat price: a chance verb's boost is paid in BP.
- **Divines.** This is the line that must stop short of Cleave. Doom is
  single-target, so a certain Doom is one kill a turn, not a formation.
  **Atom Edge and True Edge stay refused**: a certain mass death on every
  enemy is Cleave without its boss cut. L.5 Doom stays refused for the
  same reason.
- **Esper rework.** Shoat's signature (immune to Death and Doom) and
  Fenrir's (Stop and Slow) are defensive and do not touch it.
- **Build: ~90 bytes, M.** One leaf at the status hit check with a
  12-byte id table, and the flat arm in the price authorities. The hit
  path is shared with monsters, so the leaf tests for a character
  attacker as `Ot6BoostDmg` does.

### 9. Demi folds to Quartr

- **Family: tier.** Demi (`frac=1`, power 8, 33 MP) folds at a point to
  Quartr (power 12, 48 MP): vanilla's own better fraction, at its own
  price, as Fire folds to Fire 2. It caps there, as Haste caps at Haste2.
  W Wind is not the third rung, because it hits both sides (its targeting
  is `tgt=04`, the same as Quake's and Merton's).
- **Divines.** None. Fractions do not work on most bosses.
- **Esper rework.** Phantom (Demi) and Terrato (Quartr) are different
  stones; the fold reaches a spell the caster does not hold, as every fold
  does.
- **Build: 3 bytes, S.** One `Ot6FoldTbl` row (`$10,$11,$11`). The price,
  the grey and the preview already follow the fold.

### 10. Fenix Down raises with more HP

- **Family: the multiplier, on the fraction.** A Fenix Down raises at
  power 2 (an eighth of max HP); a point doubles the power: a quarter, a
  half, full at three. Revivify likewise. Price: the item.
- **Divines.** None.
- **Esper rework.** Sraphim's *Grace* (points kept through KO) and
  Phoenix's *Rebirth* (Life 3 at the start) both make dying cheaper; this
  adds a third. The guidelines read heavy Fenix use as a signal of
  under-levelling, so this is low in the ranking.
- **Build: ~35 bytes, S.** Scale the power at `CalcDmgRatio` for a
  character's item, and remove the two from `Ot6ItemNoBoost`.

### 11. Sketch joins the chance verbs

DESIGN.md already names Sketch in the chance-verb family, and today it is
a multiplier verb by accident of the gate (and spends for nothing on a
numberless sketch). Vanilla's Sketch rolls twice: the same level-ratio hit
as Control, then which of the monster's two sketches it draws
(`jsr Rand ; cmp #$40`: one in four the first, three in four the second).
The ladder: the hit as Control's (proposal 7), and the pick as Steal's
rare slot: one in four, three in eight, three in four, then the first
sketch outright. No multiplier (the queued-command test that exempts Rage,
`$3a7c`, exempts Sketch). Flat price. Build ~60 bytes, S-M. This changes
a reward Relm already has; see the owner questions.

### 12. Three lores

- **Dischord halves the target's level once more a point** (a half, a
  quarter, an eighth, a sixteenth; never below 1). Family: steps. It feeds
  every level-ratio roll in the game (Control, Sketch, the L. lores), which
  is what Strago should be for. Price escalates (68 → 99).
- **ForceField nulls one more element a point.** Family: more of the same.
  Price: each element its own cast, 24 / 48 / 72 / 96.
- **L.3 Muddle takes the next smaller divisor too** (3, then 3 or 2).
  Family: reach. L.5 Doom stays refused (proposal 8).
- **Build: ~20-40 bytes each, S.**

### 13. Two clocks

- **Ruby Power's Reflect lasts longer.** Vanilla's Reflect runs out
  (`SetStatus_17: lda #$1a ; set reflect counter to 26`, `sites.txt` line
  12019); a point adds 26 more ticks. Family: duration. Build ~20 bytes.
- **Moon Song's Image wears off more slowly.** Each blocked hit takes the
  image away on a roll; a point narrows it. Family: certainty. Build ~30
  bytes.

### 14. Row moves one more ally a point

Family: reach. Low value: the field menu does the same for free between
battles. Build ~40 bytes.

### Left refused, with the reason

- **Revert** (Morph's boost already bought the form's span), **Leap**
  (kit-gau.md §6.3: no roll to convert), **Possess** (a guest's one-shot).
- **Warp, Warp Stone, Smoke Bomb**: an escape is already certain where it
  is allowed, and the guidelines say fight rather than flee.
- **Float, Big Guard, Wall, Fader, Life Guard, Heal Horn**: they already
  cover everyone and their statuses have no clock.
- **Rippler, Pep Up, Sour Mouth, Reflect???**: no quantity to add to.
- **Scan aimed at the party**: it reads nothing.
- **Atom Edge, True Edge, L.5 Doom**: Cleave (proposal 8).
- **Quick**, unless the owner wants it (questions below).

## Ranking

By how much each adds to play: how often a player meets the choice, and
whether it creates a decision that was not there.

| rank | proposal | who plays it | family | build |
|---|---|---|---|---|
| — | close the four holes | Edgar, Relm, the MagiTek stretch | (refuse) | ~25-40 bytes, S |
| 1 | reach for single-target statuses and cures | every caster, every boss | reach | ~150-200 bytes, M |
| 2 | boosted Def. | everyone | duration | ~50 bytes, S |
| 3 | Bestow ladder | Locke | more of the same | ~15 bytes, S |
| 4 | Debilitator's extra weaknesses (and Edgar's other two) | Edgar | steps / certainty | ~65 bytes, S |
| 5 | Filch's extra shields | Locke | shields | ~45 bytes, S |
| 6 | status-cure items reach | everyone | reach | ~25 bytes, S |
| 7 | Control | Relm | certainty / multiplier | ~30 bytes, S |
| 8 | status and death certainty | casters, Edgar, summoners | certainty | ~90 bytes, M |
| 9 | Demi → Quartr | Phantom's wearer | tier | 3 bytes, S |
| 10 | Fenix Down's fraction | everyone | multiplier | ~35 bytes, S |
| 11 | Sketch's ladder | Relm | certainty | ~60 bytes, S-M |
| 12 | Dischord, ForceField, L.3 Muddle | Strago | steps / reach | ~20-40 bytes each, S |
| 13 | Ruby Power, Moon Song | summoners | duration / certainty | ~20-30 bytes each, S |
| 14 | Row | everyone | reach | ~40 bytes, S |

Reach is first because it changes the most turns: the pre-boss buff round
is where a party spends its points today on nothing, and Haste2 already
teaches the player that a boosted buff covers the party. Def. is second
because every character has it and it turns a rarely-right action into a
tank's turn at almost no build cost. Bestow is third for its size: one
store changed, and Locke becomes the party's battery for divines.

Every proposal ships with a suite (red on main, green after) and a re-cut
of the tracked saves it can reach (the driver would start using it).

## Questions for the owner

**Should a boosted buff pay for every ally it covers?** Charging Safe
12 / 24 / 36 / 48 is what vanilla's Haste and Haste2 already imply and
what Overclock and Coin Toss do. The alternative, a flat price, would make
a 3-BP Safe on the party a 12 MP turn and take MP tension out of the
pre-boss round. I recommend paying per ally.

**Is a guard that holds while you act too much?** A 3-BP Def. halves
physical damage over three of the defender's turns while she keeps
attacking, the way a boosted Runic stands. It is weaker than Safe, which
is permanent for 12 MP, and it costs a whole bank. I recommend shipping it;
it gives frontliners a use for points that is not damage.

**Should Locke be able to hand an ally a whole divine?** With Bestow at
three, a Locke who banked three lets the ally divine a turn earlier. It is
the support role Octopath's boost-sharing classes play. I recommend yes;
the bank still limits Locke to one such hand-off every three turns.

**For enemy debuffs, more targets or more certainty?** Most of Mute,
Sleep, Muddle, Stop and Imp already land on low-evasion bodies, and what
stops them is immunity, which no boost should override; so certainty would
mostly buy nothing and reach would buy a second or third body. I recommend
reach for these, and certainty only for Doom and X-Zone, where reach would
crowd Cleave.

**Should Sketch trade its multiplier for the chance ladder?** DESIGN.md
names Sketch a chance verb, and the ladder gives Relm's points a use on
every sketch, numberless ones included. But a boosted damaging sketch hits
x8 today, and the ladder would take that away. I recommend the ladder,
for consistency with Steal, Rage, Slot and Dance, and because a Sketch is
a draw from two attacks, not a chosen one.

**Should Quick buy extra turns?** One more turn a point is the obvious
"more of the same", but each turn banks a pip, so a 3-BP Quick (already
99 MP) would turn into five turns and a divine at the end of them. I
recommend leaving Quick refused.

**Should a spell do what one of Shadow's tricks does?** Vanish with reach
on the party is what Shadow's Inviz Edge does with a boost. Phantom's
stone pays MP for it and Shadow pays an item, and his covers the party for
one throw. I recommend allowing it; his throw stays cheaper and needs no
stone.

## Evidence

`build/attempts/wt/design-boost-every-action/`: `procsize.py` and
`procsizes.txt` (every OT6 battle proc's size at de4ee995),
`spellprops.txt` (targeting, MP, power and hit of the spells and lores
above, vanilla `magic_prop_en.dat`, OT6's MagicProp overrides not applied),
`sites.txt` (the source lines cited), `rownoboost.txt` (`Ot6RowNoBoost`).
Nothing here was played; every "today" in the inventory is read from the
source and the design docs, and the lines marked "read, not played" are
the ones a suite has not yet measured.
