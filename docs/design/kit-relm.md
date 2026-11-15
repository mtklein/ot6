# Relm: the painter as the party's supporter (#538)

Status: **designed, not built** (2026-11-15). The owner's direction: "As an
artist, she should have abilities that buff the team, like a bard or
synergist." The brainstorm in #538 was approved in full; this document turns
it into a kit that can be built, and says where the approved ideas had to
bend and why.

Every buff here works through OT6's own systems: boost points, shields,
Break and the turn gauge. None of them is an FF6 stat status. All of the new
state is battle RAM; nothing is written to the save.

Two changes landing beside this design shape it (owner, 2026-11-15):

- **#542:** the hit that breaks an enemy no longer takes the broken ×2; only
  hits on a body that is already Broken do. The broken window becomes the
  payoff, and each monster effectively gains one shield. This makes Still Life
  (a longer window) and Underpainting (one shield sooner) more valuable, and
  both are priced and capped with that in mind.
- **#543:** broken monsters are no longer drawn grey; the cracked shield
  alone marks a break. Still Life's longer break shows as the cracked shield
  staying up longer, and needs no other display.

The owner also finds the World of Balance too easy on boosted attacks alone.
Nothing below adds damage to a plain boosted Fight. Tint gives a key to a
hit that had none and adds no damage; Portrait and Masterpiece save a boost
point but cost Relm's turn and MP; Gesture gives turns, which do help a
boosted Fighter, so it comes late (L48) and needs timing to pay.

Evidence for the numbers below is in
`build/attempts/wt/v047-relm-design/` (`sources.txt`: the source lines cited;
`relm_mp.py` and `relm_mp.txt`: her MP pool by level from the ROM's own
tables). Nothing here was played.

## 1. The kit

Relm's command rows stay FIGHT, SKETCH, MAGIC, ITEM (`char_prop.asm:239`).
Like Locke behind Steal and Setzer behind Slot, her kit is a list behind
the Sketch row, with Sketch as the first row.

| # | Row (list / banner) | What it does | Target | MP | A boost point buys | Lasts | Ends | Stacking | Learned |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Sketch** ✦ | vanilla Sketch, bug and all (vanilla-destructive-bugs.md) | an enemy | 0 | what the sketched attack's boost buys (boost-rewards.md, unchanged) | the action | -- | -- | join |
| 2 | **Portrait** | the ally's next boosted action counts as boosted one point higher than they paid for: one free point (the gift) | one ally, not Relm | 18 | refuses the boost (its party-wide form is Masterpiece, below) | until that ally's next action that takes a boost | that action, or the battle's end | one gift a body; a second Portrait on a gifted ally is refused at the cursor | her recruitment, Esper Mountain (switch `$02E8`) |
| 3 | **Tint** | for three of the ally's turns, each Fight, Mug/Capture or Jump hit that keys nothing else takes one shield from a body whose element weakness is already revealed; damage is unchanged | an ally (Relm included) | 16 a body | one more ally, in battle order | 3 of that ally's turns | the third turn's end, or the battle's end | a second Tint resets the count to 3; never two shields from one Tint hit | level 18 (she joins at 22, so she has it on joining) |
| 4 | **Varnish** | the next enemy action that would land on the ally misses | an ally (Relm included) | 20 a body | one more ally, in battle order | until used | an enemy hit lands on it, or the battle ends | one coat a body; a varnished ally is passed over | level 25 |
| 5 | **Still Life** (list: StillLife) | the body's break, the current one or its next, lasts half as long again (+8 break ticks) | an enemy | 36 a body | one more enemy, in battle order | one break | that break's end | once a break: a mark laid during a lengthened break waits for the next | Owzer's mansion, after Chadarnook (switch `$0240`) |
| 6 | **Underpainting** (list: Underpnt.) | the next weakness hit on the body takes two shields instead of one | an enemy | 40 a body | one more enemy, in battle order | until a weakness hit lands | that hit, or the battle's end | one mark a body; adds to Ramuh's Conductor | level 42 |
| 7 | **Gesture** | fills the ally's turn gauge: their turn comes up now | an ally, not Relm | 48 a body | one more ally, in battle order | instant | -- | a body whose gauge is already full or whose action is queued is passed over | level 48 |
| 8 | **Masterpiece** (list: Mstrpiece; divine) | every other ally receives Portrait's gift | the party | 99 | the divine itself: greyed and refused under three points | as Portrait | as Portrait | gives nothing to an ally already holding a gift | Strago's return, the Fanatics' Tower (switch `$00BA`) |

The per-body prices follow the reach rule boost-rewards.md built: each point
is its own use, `base × (1 + boost)`, capped at 99 (`Ot6PerPointPrice`). So
Gesture is 48 / 96 / 99 / 99 and Still Life 36 / 72 / 99 / 99. Portrait is
flat (it refuses the boost) and Masterpiece is 99, the divine ceiling.

**The eight slots are full.** Sketch plus the seven approved ideas fill the
eight rows the cast pillar allows, so no row was cut and no alternative was
needed. Two of the approved ideas had to bend: Portrait's boost (below) and
Tint's colour (below).

### Rulings, one per question the brief raised

**Varnish is kept: it is not Image.** Image (Shadow's smoke, the Moon Song,
the Shadow Edge) turns aside physical hits only, on a roll, and can last
several hits. Varnish stops exactly one enemy action of any kind, physical,
magic, a special or a can't-dodge hit, certainly. It is the one guard in
the game against the single big hit a boss telegraphs, spell or not. It is
judged after CheckHit's own verdict (§2), so a hit Image, Vanish or evasion
already turned aside never uses it up, and Runic absorbs a spell before it
reaches the hit test, so a standing Runic keeps the Varnish behind it.

**Portrait refuses the boost.** The approved kit says both "boosting her
abilities buys reach" and "Masterpiece: at 3 BP, every ally's next action
counts as boosted by one". With reach on Portrait, two points would reach
three allies, which is the whole party and exactly Masterpiece, so the
divine would be bought below its gate. The standing rule settles it: an
action whose boost would buy nothing new refuses it. Masterpiece is
Portrait's party-wide form, as Haste2 is Haste's.

**Tint matches each foe's known weakness rather than a chosen colour.** An
element picker would need a second list under the first (the tools shell
has one level). Instead the paint takes, against each body it strikes,
whatever element that body's HUD already shows as a weakness. The player
still has to reveal the weakness first (a chip, Analyze, Appraise), so the
key puzzle stands; Tint shares a key the party knows with a fighter whose
weapon lacks it. It adds a key, never damage: the hit deals what it would
have dealt, and it chips only when nothing else about the hit did, so a
fighter who already keys the body gains nothing. That keeps it from being
a plain boosted-Fight buff (the owner's concern above). And because it
only ever adds a weakness, it cannot heal a body that absorbs the element.
This is a reading of the approved text; §7 asks the owner whether it feels
right.

**Portrait's gift is a point, never a pip.** It raises what an action's
boost buys; it is not banked and cannot be handed on. So:

- **MP follows the effective level.** A gifted Fire paid at one point casts
  Fire 3 and is priced as Fire 3. "MP scales with magnitude" holds: the
  gift replaces a boost point, not MP. The ally's window shows the raised
  price, and a row the ally cannot pay at that level greys and refuses as
  any priced row does, so a gift never makes a cast fizzle.
- **The three-point cap stands.** A gift lets an ally reach three points
  with two banked; it never makes a fourth. An ally who would pay three
  anyway pays two and keeps the third, so a gift is never wasted at the cap.
- **A boosted action earns no pip** (pillar 3), including one boosted only
  by the gift. So the gift is worth exactly one point to the ally.
- **An action that refuses a boost keeps the gift.** Def., Row, Revert,
  Leap, Control, a numberless sketch, a status cure from Item: the boost is
  dropped before it is charged (`Ot6CmdNoBoost`, `Ot6QueueFold`,
  `Ot6KeepBoost`), and the gift with it, so it waits for the next action.
- **Bestow cannot hand it on.** Bestow moves pips, and the gift is not one.
- **Divines.** A divine's one gate is a full three-point boost, and the
  gift counts toward it: two banked plus a gift is a divine. Bestow already
  brings a divine a turn closer, and this is the same support role. The gift
  does not lower a divine's 99 MP. §4 covers Masterpiece making three
  divines in one round.
- **Uncontrolled turns.** The engine spends no boost on a turn it chooses
  (Muddle, Charm, Berserk, the Colosseum, Umaro), so the gift waits. Umaro
  never opens a window, so Portrait and Masterpiece pass over him.
- **Mimic.** A Gogo's copy reads his own pending boost, gift included, as
  every Mimic does.

**How the gift shows.** When a gifted ally's command window opens, their
pending boost already reads one point, and their pip cell is drawn in a
second battle text palette until the gift is used. R raises paid points on
top, up to three in all and never past bank plus gift. L can lower the
pending boost to zero to keep the gift for a later action.

**Gesture cannot loop.** Gesture gives a turn by spending one, so two
characters Gesturing each other gain nothing; but with the reach a boost
buys, a Relm and a Gogo mimicking her could pass turns back and forth while
their banks lasted. One rule closes it: **a turn that Gesture granted
cannot Gesture.** The mark is set when Gesture fills a gauge and cleared at
that character's next action's end; while it is set, Relm's Gesture row
greys and refuses, and a Mimic copy of a Gesture does nothing (it is free,
so it costs nothing). Relm cannot target herself, which also means Gogo's
copy of a Gesture aimed at him finds no body. With this one rule no loop
exists.

**Still Life cannot hold a boss down for good.** A break is lengthened at
most once. The extension is decided at the moment the break would end, so
a mark laid during a lengthened break waits for the next one. The longest
break is half as long again, the same for bosses and trash.

**Underpainting and multi-hit.** The mark is spent on the first chip by a
weakness, element or class, by any source including Tint's. A four-hit
Quadra Slam on a painted body takes five shields: two on the first hit, one
on each of the others. Takes that ignore weaknesses (Filch, Break, Bum
Rush's blows, Cleave's strip) leave it standing: they are not weakness hits.
On the same lightning-weak hit, Ramuh's Conductor and Underpainting each
take their extra shield, three in all; they come from different sources and
each is paid for (a stone worn, a turn and MP spent).

**The Fake Mustache.** The relic turns Sketch into Control
(vanilla's RelicCmdTbl rewrite, which Locke's Thief Glove also uses). For
Locke the gloved Capture has no submenu; Relm would lose her whole kit that
way, so the list opens behind Control as well, with Control as its first
row. Gogo, who can carry Sketch, gets plain Sketch with no list, as he gets
plain Slot (Setzer's precedent).

**The Fanatics' Tower** is magic-only: `InitCmdList` drops every row but
Magic, Item and Mimic (kits.md, "The World of Ruin"), so Relm's kit is off
there, as every kit row is.

## 2. Engine feasibility

Every ability is feasible. None needs new art, a new status or save data.

### The list (menu surface)

- **Open.** `OpenCmdMenuTbl[$0d]` (and `[$0e]` for Control) points at a C1
  stub, `_c1_paint_open`, the twin of `_c1_thief_open` and `_c1_slot_open`
  (`btlgfx_main.asm:18236-18256`): `jsl Ot6PaintListOpen`, then
  `jmp OpenToolsWindow`, or straight to vanilla target select when the
  caster is not Relm (carry clear, as `Ot6SetzerListOpen` does for Gogo).
  `Ot6PaintListOpen` copies `Ot6ThiefListOpen` (`ot6_thief.asm:225`): eight
  cells, two columns of four, each row's id, flat price and its own
  targeting byte, and mode `w7e6168 = 5`.
- **Rows and ids.** Under command `$0d` the queued attack byte is free, as
  it is under Steal: `FixPlayerAttack` has no `$0d` arm and `$0d` is not in
  `CmdWithAttackTbl` (`battle_main.asm:13263`), and `Cmd_0d`
  (`battle_main.asm:3353`) writes `$b7 = $ff` and only later overwrites
  `$b6` with the sketched attack. The rows take ids `$e8`-`$ee`, named from a
  table (`Ot6KitListName`'s painter arm) and bannered through attack name
  type 3 as Locke's later rows are (`Ot6ThiefBannerName`).
- **Targeting.** Each row carries its own byte, as Bestow does: `$43`
  (an enemy) for Sketch, Still Life and Underpainting; `$03` (an ally) for
  Tint and Varnish; `$03` with Relm refused at execution for Portrait and
  Gesture; a whole-party byte for Masterpiece, whose cursor opens on the
  party side and which gifts every ally whatever it names (Master's Mark's
  shape, `ot6_thief.asm:116-127`).
- **Execute.** One hook at `Cmd_0d`'s head (and `Cmd_0e`'s), `jsl
  Ot6PaintExec / bcs`, dispatches the rows, the shape of `Ot6ThiefExec`
  (`ot6_thief.asm:364`). The Sketch row falls through to vanilla.
- **Price.** `Ot6AbilityCost` gains a `$0d`/`$0e` arm keyed on `$3a7b`
  (`ot6_boost.asm:2665`, the `@steal` arm's shape); the reach rows price
  through `Ot6PerPointPrice`. `Ot6KitRowCost` (`ot6_cmdmenu.asm:401`) gains
  mode 5. Drawn, greyed and charged prices come from the one leaf.
- **Greying.** `Ot6BushidoRowGrey` (`ot6_cmdmenu.asm:572`) gains a mode-5
  arm: Masterpiece greys under three points pending (Master's Mark's
  `@mark` test, reused); Gesture greys while Relm carries the Gesture mark.
  `Ot6KitConfirmMP` refuses whatever greys (#232).
- **Boost refusal.** `Ot6RowNoBoost` (`ot6_boost.asm:1518`) gains Portrait,
  so R buzzes on its row; a boost raised on the command window first is
  dropped at the queue (`Ot6QueueFold`), never charged.
- **MP display.** The list draws each row's price as the thief list does
  (two digits after a nine-letter name), live with the pending boost, and the
  wallet line shows Relm's MP while the list is up.
- **Help text.** FF6's battle lists carry no help text; the field Skills
  page lists the eight rows with the locked marker on rows not yet learned,
  as `menu_thiefpage` does for Locke. The Narshe school and PLAYING.md teach
  them.
- **Names.** Rows are nine letters to leave the price a gap, as "Mstr.Mark"
  does: Sketch, Portrait, Tint, Varnish, StillLife, Underpnt., Gesture,
  Mstrpiece. The banner (13 letters) prints the full names; "Underpainting"
  is exactly 13.
- **Cost of a new list.** Measured from the thief list it copies: one C1
  stub (about 8 bytes, two for Control), one table of eight 5-byte records,
  ten-letter names and thirteen-letter banners, and an arm in each of five
  shared leaves. Thief's whole file, eight rows with their effects, is 1,138
  lines; this list's menu half is smaller, since the effects live in their
  own procs.

### Portrait and Masterpiece

- **State.** One byte, `OT6_GIFT`, a character mask in `$3018`'s shape.
- **The window.** On the frame a gifted ally's window opens, pending
  (`OT6_BOOST_REVEALED,x`, `$3e9d`) is raised from 0 to 1. `Ot6Boost`'s R
  cap, "never more than current bp" (`ot6_hud.asm:1399`), becomes bp plus
  the gift. `Ot6BushidoRowGrey`'s SwdTech and Bestow arms read the same
  sum. The pip cell (`Ot6PipGlyph_ext`, `ot6_hud.asm:1930`) ORs a palette
  into its tile word while the gift stands.
- **The charge.** `Ot6ActionEnd`'s spend arm (`ot6_boost.asm:167`, the
  `@spend` label) subtracts pending less one when the gift bit is set and
  pending is at least one, then clears the bit. Every path that drops a
  pending boost before that arm (`Ot6KeepBoost`, the no-action path, the
  queue-side refusals) leaves the bit standing, so a refused action keeps the
  gift without a special case.
- **Price and divines.** Every price authority (`Ot6BoostPriceFor`,
  `ot6_boost.asm:1850`) and every divine gate reads pending, so the effective
  level is priced and gates the divine with no change to them.
- **Bestow.** `Ot6Bestow` charges and hands only paid points: it reads
  pending less the gift.
- **Masterpiece.** Sets the gift bit on every other living ally who takes
  a window (not Umaro). Gated as Master's Mark is: greyed and refused under
  three pending, and a pick taken back to fewer does nothing and costs
  nothing.

### Tint

- **Where Fight's element is set.** `InitPlayerAttack`'s weapon arm loads
  the swinging hand's element, `lda $3b90,x / sta $11a1`
  (`battle_main.asm:7301`), beside `Ot6WeaponClass`. Tint does not touch
  `$11a1`: rewriting the attack's element would also bring vanilla's
  weakness ×2 (`asl $f0`, the `@0c0e` branch, `battle_main.asm:1912-1919`)
  and its absorb test, and both are against the design.
- **Where it chips.** A new leaf in `Ot6HitJoin` (`ot6_break.asm`, which
  runs for every landed hit at `@0c1e`, `battle_main.asm:1920`), after
  `Ot6ClassChip`: if the attacker is a character with Tint turns left, the
  command is Fight, Capture or Jump (`$b5` `$00`/`$06`/`$16`; Mug runs as
  Capture), the target is an unbroken monster, the hit took no chip of its
  own, and `OT6_REVEALED_ELEM,y & $3be0,y` is nonzero, then take
  one shield (`Ot6TakeShields`, `ot6_breakspell.asm:119`). "No chip of its
  own" is read from the hit's own keys, the same tests the two chips make:
  `$3be0,y & $11a1` (the element) and `OT6_ATKCLASS & OT6_BP_CLASS,y` (the
  class) both zero.
- **Which commands.** Only the weapon's own swings: Fight (and its boosted
  swings, `Ot6FightBoost`), Mug and Capture, Jump. Not Throw (the thrown item
  is not the painted weapon) and not skills, which carry their own element
  and class. So every swing of a boosted Fight can key, but only on a body
  the fighter could not key, and the swings deal what they would have.
- **Absorbers.** It adds only weaknesses the body has, so it never touches
  absorb, null or resist.
- **The counter.** `OT6_TINT`, 8 bytes (4 characters, stride 2), turns left.
  `Ot6ActionEnd` decrements it for the actor. A fallen ally takes no turns,
  so the paint waits on them.
- **Display.** A banner at the cast ("Tint") and the shield count dropping
  on each keyed hit. There is no free status icon in FF6's battle HUD, and
  recolouring the swing's weapon sprite would mean a palette swap per swing;
  per the standing rule (accept engine limits) neither is built.

### Gesture

- **How the gauge fills.** `actioncounter` (`battle_main.asm:2806-2829`)
  adds the gauge constant `$3ac8,x` to the word `$3218,x` each tick of
  battle time and treats a carry as full: it zeroes `$3219,x`, sets `$3aa0`
  bits 3 and 7, and the window opens. Gesture writes `$ffff` to `$3218,x`,
  so the next tick carries. It is the same idea as the AI's "fill target's
  gauge" (`MiscAIEffect_08`, `battle_main.asm:5395`, which writes
  `$3ac9`), but writes the gauge, not the constant, so nothing needs
  restoring.
- **Haste and Slow** change `$3ac8` (`CalcSpeed`, `battle_main.asm:1602`),
  which no longer matters once the gauge carries: the granted turn comes
  at once whatever the speed, and the next one refills at the ally's own
  rate.
- **Who is passed over** (a reach walk, `Ot6ReachWalk`'s shape,
  `ot6_reach.asm:184`): Relm herself; a body whose gauge is already full
  (`$3219,x = 0`) or which already has an action queued (`$32cc,x != $ff`,
  Gesture does not reorder the action queue); Stop, Sleep, Petrify, Wound,
  Freeze; a body out of the fight (`$3f2c`, a Jump in the air). A Berserked
  or Muddled ally is not passed over: their turn comes, uncontrolled, as any
  turn of theirs would.
- **"Act next."** A full gauge opens the ally's window behind any window
  already waiting. In Wait mode time stops while they choose; in Active it
  runs. Neither is changed.
- **The mark.** `OT6_GESTURED`, one byte, a character mask: set on each
  body Gesture fills, cleared for the actor at `Ot6ActionEnd`. Relm's row
  greys while hers is set, and `Ot6PaintExec` refuses a Gesture (a Mimic
  copy included) from a marked actor.
- **Mimic.** Sketch is Mimic-able (`battle_cmd_prop.asm:77`), so Gogo can
  copy any painter row; the copy reuses the original targets (`SaveForMimic`
  saves `$3a30` to `$3f22`, `battle_main.asm:400`). Control is not
  (`battle_cmd_prop.asm:80`).

### Still Life

- **The break timer.** `OT6_BROKEN_TICKS` (`$3e88,y`), set to
  `OT6_BREAK_TICKS = $10` (`ot6_break.asm:1`) by every break (`Ot6Chip`,
  `Ot6ClassChip`, `Ot6TakeShields`) and counted down by `Ot6Tick`, which
  `DecCounters` calls each time the body's speed accumulator `$3adc` carries
  (`battle_main.asm:15492-15495`). A break measures 2159 frames, about 36 s,
  on stage (DESIGN.md: "`$10` ... measures **2159 frames**"). Haste or Slow
  on the monster changes the rate, as it does every break.
- **The hook.** One, in `Ot6Tick`'s recovery arm (`ot6_break.asm:1785`):
  when the count reaches zero, a body with its mark set and its held bit
  clear is given 8 more ticks (about 1080 frames, 18 s), the held bit is set
  and the mark cleared; otherwise it recovers as now, and the held bit is
  cleared. Deciding at the recovery moment covers both cases, the current
  break and the next, with one hook and no change to the three break sites.
- **State.** `OT6_STILLMARK` and `OT6_STILLHELD`, one byte each, monster
  masks (the `$3019` half of `$3018`'s word). Cleared per slot by
  `Ot6SeedShields`, the `OT6_BRKTICK` contract, so a `Cmd_20` reload never
  carries a mark onto a new body.
- **Bosses.** The same rule. A boss's break is half as long again at most
  once per break; Still Life cannot chain.

### Underpainting

- **The chip routines.** `Ot6Chip` (`ot6_break.asm:591`) decrements the
  shield count and calls `Ot6Conductor` (`ot6_break.asm:653`;
  `ot6_esper.asm:800`) for Ramuh's extra shield; `Ot6ClassChip`
  (`ot6_break.asm:763`) decrements without one. Underpainting is a leaf of
  `Ot6Conductor`'s shape, `Ot6Underpaint`: A = the shields left after the
  chip; if the body is marked and A is nonzero, take one more and clear the
  mark. It is called beside `Ot6Conductor` in `Ot6Chip`, at the same point
  in `Ot6ClassChip`, and in Tint's leaf.
- **State.** `OT6_UNDERPAINT`, one byte, a monster mask, cleared per slot by
  `Ot6SeedShields`.
- **Consumed by** the first weakness chip on the body, element or class. A
  Broken body takes no chip, so the mark waits through the break.

### Varnish

- **The hook.** `CheckHit` (`battle_main.asm:5952`) returns carry set for a
  miss, and both its hit and miss paths leave through `@22e8`
  (`battle_main.asm:6059`). A jml there, `Ot6VarnishGate`: after the
  `plp`, if carry is clear (the hit lands), the target `y` is a character
  with the varnish bit, and the attacker `x` is a monster, set carry (a
  miss) and clear the bit. FF6 shows it as "Miss".
- **Image and evasion** are judged inside `CheckHit` before its exit, so a
  hit they turned aside reaches the gate as a miss and the Varnish stays.
- **Runic** absorbs in `RunicEffect` (`battle_main.asm:8463`), during
  targeting, before `CheckHit` runs, so the spell never tests the Varnish.
- **What uses it up**: any enemy action that would land, damaging or not
  (a status, a Scan, a fraction). An ally's action never does, so a Cure on
  a varnished ally lands.
- **State.** `OT6_VARNISH`, one byte, a character mask.

### Battle RAM

All of it is battle-only and sits in the measured-free shadow tail, after
`OT6_RAGETIER` (`$ee39`, 8 bytes, `ot6_memory.inc:607`) and under the
range's bound (`<= $ef1f`, the asserts beside it):

| Name | Address | Size | Shape | Cleared by |
|---|---|---|---|---|
| `OT6_TINT` | `$ee41` | 8 | turns left, 4 characters, stride 2 | `Ot6InitBP` |
| `OT6_GIFT` | `$ee49` | 1 | character mask | `Ot6InitBP` |
| `OT6_VARNISH` | `$ee4a` | 1 | character mask | `Ot6InitBP` |
| `OT6_GESTURED` | `$ee4b` | 1 | character mask | `Ot6InitBP`, and per actor at `Ot6ActionEnd` |
| `OT6_STILLMARK` | `$ee4c` | 1 | monster mask | `Ot6InitBP`, per slot in `Ot6SeedShields` |
| `OT6_STILLHELD` | `$ee4d` | 1 | monster mask | as above, and on recovery |
| `OT6_UNDERPAINT` | `$ee4e` | 1 | monster mask | `Ot6InitBP`, per slot in `Ot6SeedShields` |

Fourteen bytes, `$ee41`-`$ee4e`. They lie past `Ot6InitBP`'s shadow clear
(`cpx #$0070`, `ot6_boost.asm:75`), so `Ot6InitBP` zeroes them with
explicit stores, as it does `OT6_RUNICTURNS`, and each gets an assert in
`ot6_memory.inc`.

## 3. Acquisition

**Decided (owner, 2026-11-15): a mix of story beats and level, some in the
World of Balance and some in the World of Ruin, then mostly by level.**

Relm joins at Esper Mountain (`char_party RELM, 1` and `switch $02E8=1`,
`event_main.asm:73701-73703`, just before Ultros's third fight, battle 125)
at L22 on the line (level-curve.md:46). She leaves the party at the
Floating Continent's end and rejoins in the World of Ruin at Owzer's mansion,
raised to the party's average (`norm_lvl RELM`, `event_main.asm:48897`):
"RELM, joining aboard, is seated at L36" (route-wor-thamasa.md:1061), and
L46 after the Fanatics' Tower plain (level-curve.md:561).

| Row | How | Beat or level | Why this beat |
|---|---|---|---|
| Sketch ✦ | at join | -- | her signature |
| Portrait | story, WoB | her recruitment (`$02E8`, Esper Mountain) | her threat to anyone who crosses her is a portrait ("I'm gonna draw your portrait!", `event_main.asm:5068`); it is what she does |
| Tint | level 18 | on joining (she joins at 22) | the plain first lesson: colour a fighter's weapon to key a known weakness |
| Varnish | level 25 | the World of Balance's end if she is seated through the Floating Continent, else on rejoining | a second, simple buff before the break tools |
| Still Life | story, WoR | Owzer's mansion, after Chadarnook (`$0240`, `event_main.asm:48874`, set where Starlet is given) | a painting that holds a demon fast; the painter's beat |
| Underpainting | level 42 | the World of Ruin, on the Fanatics' Tower plain | the break tools arrive together in her World of Ruin arc |
| Gesture | level 48 | the World of Ruin, about the Zone Eater (level-curve.md:562: the belly at 48-50) | the strongest tempo tool comes late, where the World of Balance's ease is not at stake |
| Masterpiece | story, WoR | Strago's return at the tower's foot (`$00BA`, `event_main.asm:89459`) | the grandfather she paints for comes back (her line at the end: "And I have a brave Grandpa who'll stand by me through it all", `event_main.asm:9703`); divines come by story |

Three story beats and four levels. The Thamasa fire and the Floating
Continent are not used: Relm is not in the party during the fire (she is
the one rescued from it), so anything taught there would be the same as
teaching it on joining; and the Floating Continent is where a party of four
must bench one of TERRA, LOCKE, STRAGO and RELM (floating-continent-route.md:52),
so a beat there could be missed by a player who benched her. A switch would
still teach it, but it would arrive without being seen.

**On joining in the World of Balance** she has Sketch, Portrait and Tint,
and Varnish at L25: a kit that makes the party's known weaknesses and its
boosts go further, ready for the Floating Continent. **In the World of
Ruin** she rejoins with Varnish and gains Still Life at once, Masterpiece a
few minutes later at the tower's foot, Underpainting on the plain and
Gesture around the Zone Eater.

**The save.** Nothing new. A row's known-test reads either a vanilla event
switch (`$1E80 + n/8`, bit `n & 7`, as `Ot6ThiefRowKnown` does,
`ot6_thief.asm:157`) or Relm's level in her character record (`$1600`
block). Both are vanilla fields every save already holds. save-layout.md's
policy allows "change what the game does with a field, as long as every
value an older save can hold there still reads sensibly": a save past a
beat or a level has the row, whatever version wrote it. When built,
save-layout.md's event-switch row (`$1E80-$1F5F`, "Read by OT6 code")
adds `$02E8`, `$0240` and `$00BA` to the switches OT6 reads. OT6 sets no
new switch.

## 4. Balance

Numbers: a break lasts 2159 frames (DESIGN.md); damage against an
unbroken, unweak baseline runs 8 (broken and weak) : 4 (broken) : 2
(shielded and weak) : 1 (DESIGN.md "Shielded resistance"). After #542 the
breaking hit takes the shielded rate, so the hits that land inside the
window are the whole ×4. Relm's MP pool, from the ROM's tables before esper
ranks (`relm_mp.txt`): 194 at L22, 230 at L25, 419 at L39, 464 at L42, 561
at L48. Each price sits at 8-9% of the pool on arrival (Tint 16/194 = 8.2%,
Portrait 18/194 = 9.3%, Varnish 20/230 = 8.7%, Still Life 36/419 = 8.6%,
Underpainting 40/464 = 8.6%, Gesture 48/561 = 8.6%), at the bottom of
mp-economy.md's 8-20% band because each is a support turn that buys no
damage of its own.

| Row | Where it shines | Why it is not essential | Limit against trivialising |
|---|---|---|---|
| Tint | a body whose revealed weakness is an element only a caster holds: the Chadarnook demon (weak fire, holy; slash and pierce, six shields, route-wor-thamasa.md:219) when the fire is Terra's Fire and the blades are busy | every key it shares is a key the party already has in a spell | no damage, no second chip, revealed weaknesses only, three turns |
| Portrait | the turn before a divine or a fold: a two-banked ally reaches three | the ally can bank the point themselves a turn later | single target, refuses a boost, one gift a body, a point never a pip |
| Varnish | a boss's telegraphed big hit, on the healer or the member it would kill | Safe, Shell, Image, Runic, healing and levels answer the same hits | one action a coat, one coat a body |
| Still Life | long bosses after #542: half as many hits again land in the window | breaks happen and pay without it | once a break; at most 1.5× a break (3239 frames) |
| Underpainting | bosses with many shields: it gives back the one shield #542 adds | keys and boosts break bodies without it | one mark a body, one extra shield, weakness hits only |
| Gesture | a Broken boss: the heavy hitters who just acted get another turn inside the window | turns come on their own; it only moves them | not on herself; a body already full or queued is passed over; a granted turn cannot Gesture; 48 a body, 99 at two or three points |
| Masterpiece | the burst: three allies boosted at once, into a window | Portrait and the allies' own banks do the same over more turns | full bank, 99 MP, no stacking |

**Flagged.**

- **Masterpiece and divines.** With two banked each and a Masterpiece, three
  allies can each throw a divine in one round. That costs Relm four turns'
  bank, 99 MP, and 99 MP per divine (each ally's divine price; a L48
  Sabin's Bum Rush or Cyan's Cleave is still 99). It is the kit's peak and
  is meant to be. A per-battle limit would break the owner's divine rule
  ("no once-a-battle limit and no other condition", kits.md "Divines"), so
  the bank and the MP are the limits.
- **Gesture and boosted Fights.** Gesture is the one row that helps a plain
  boosted Fighter, by giving them turns. It costs Relm's turn, and an ally
  who has just acted gains a whole turn from it, one halfway through only
  half. At two or three points it covers the party for 99 MP. Learned at
  L48, it does not reach the World of Balance the owner finds too easy.
- **Still Life on bosses.** Kept for bosses, capped at once a break. The
  extra 18 s is about half a break of hits at ×4; after #542 that is the
  largest single payoff in her kit, and the cap keeps it to one window.

## 5. How the test player should use the kit

A policy for the fight driver (`Driver:relmLine`), in priority order, in
event battles (the Locke and Setzer precedent: random battles keep her
Fight, so the legs' frame cost stays put):

1. **Masterpiece** at three banked when the boss is Broken or two allies
   hold two or more.
2. **Still Life** on a Broken boss with more than half its break left, or on
   one at two shields or fewer that the party's next turns can key.
3. **Underpainting** on a boss at four or more shields that the party can
   key, before its keyed hits.
4. **Gesture** while a boss is Broken, on the ally with the most damage
   planned whose gauge is under half full; one point a further such ally,
   bank allowing.
5. **Portrait** on an ally with two banked who plans a divine, else the
   main boost-Fighter while the boss is Broken.
6. **Tint** on a fighter whose weapon keys nothing on the target when the
   target shows a revealed element weakness.
7. **Varnish** at the open, then whenever it is used, on the member with the
   lowest max HP.
8. Otherwise her Fight, as now.

Each line logs what it read (`[relm] Still Life on slot 2: Broken, 11 of 16
ticks left`) so a run shows the kit was exercised. The canon line plays the
policy; a branch leg that feeds nothing can hunt the cases the line rarely
meets (a Gesture loop's refusal, a Masterpiece divine round), per the
canon-playthrough practice.

## 6. Build plan

Each step is its own merge, with a suite that is red on main and on the
named mutant and green on the change. The suites stage the fights from
fixtures already tracked: `ultros-won-v1` and `thamasa-done-v1` (World of
Balance, Relm seated at L22), `wor-owzer-v1` and the `wor_relm` leg's
states (World of Ruin).

| # | Step | Suite | Mutant it must fail | Moves the line | Size |
|---|---|---|---|---|---|
| 1 | The list behind Sketch and Control, names, banners, prices, greys, the field page, the known-test (switch or level), Sketch's row unchanged | `battle_relmkit` (rows at each fixture; Sketch from row 1 still sketches), `menu_relmpage` | `OpenCmdMenuTbl[$0d]` left vanilla; a row keyed on the wrong switch | no (the driver never Sketches) | M, ~250 bytes F0, ~10 C1 |
| 2 | Portrait and Masterpiece: `OT6_GIFT`, the window raise, R cap, charge, Bestow, pip palette | `battle_portrait` (a 0-bank ally casts Fire at one point for nothing and Fire 2's price; two banked plus the gift is Cleave; Def. keeps the gift; Bestow hands only paid pips; Masterpiece gifts three, greyed under three) | the charge ignores the gift (charges full pending) | no | M, ~150 bytes |
| 3 | Tint | `battle_tint` (an unkeyed claw Fight on a revealed fire-weak body chips each swing and lands the control's damage; a keyed swing chips once; Throw does not) | Tint chips on keyed hits too; Tint adds the element to `$11a1` | no | S, ~80 bytes |
| 4 | Varnish | `battle_varnish` (a monster spell misses and clears it; Image takes a physical hit and leaves it; Runic absorbs and leaves it; a Cure lands) | the bit is never cleared | no | S, ~40 bytes |
| 5 | Still Life | `battle_stilllife` (a marked Broken body holds 24 ticks, an unbroken one's next break 24; a mark during the extension waits; a boss the same) | no held bit (the chain) | no | S, ~50 bytes |
| 6 | Underpainting | `battle_underpaint` (two shields on the first keyed hit; Filch and Bum Rush leave it; three with Ramuh's Conductor; a Quadra Slam takes five) | the mark never clears | no | S, ~40 bytes |
| 7 | Gesture | `battle_gesture` (an ally who just acted acts next; sleeping, stopped and queued allies passed over; Relm refused; a Gestured Relm greys; Gogo's copy refused) | no mark (the loop) | no | M, ~90 bytes |
| 8 | The driver policy, then the re-cut of every tracked save Relm is seated in (Esper Mountain to the Floating Continent; Owzer's mansion to the end), with the line's replay | the legs themselves, and a `[relm]` count per arc | `opts.relm = false` as the control arm | **yes** | M, driver ~150 lines; replay is machine time |
| 9 | Docs: kits.md, DESIGN.md, PLAYING.md, the Narshe school's Relm line, the booklet, release notes, save-layout.md's switch row | -- | -- | no | S |

Steps 1-7 change nothing the line plays (the driver never opens her list),
so they land without a re-cut; step 8 is the one that moves play, and it
re-cuts what #542 will already have re-cut if it lands first. Doing step 8
after #542 avoids cutting the same saves twice.

## 7. Questions for the owner

**Does Tint feel right as a key that matches each foe, rather than a colour
you pick?** As designed, the paint takes on whatever element each struck
monster is already known to fear, so a fighter whose weapon has no key can
use the party's. The other reading, Relm choosing fire or ice when she
paints, needs a second menu under her list and lets the paint land on a body
that drinks it. I recommend the matching version: it reads as a synergist
sharing what the party has learned, and it never backfires.

**Is a round where three allies throw their divines the peak you want for
her?** Masterpiece on allies who hold two points each lets them all reach a
divine at once. It costs her whole bank and a lot of MP, and it comes after
Strago's return in the World of Ruin. I recommend keeping it as her
showpiece; if it feels like too much, the gentler version is that a gift
raises an action to two points at most, so Masterpiece speeds divines up
but never completes one.
