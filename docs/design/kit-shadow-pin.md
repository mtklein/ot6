# Shadow: throws that hobble and pin (#546)

Status: **designed, not built** (2026-11-16). The owner's direction:
"let's reimagine leghold trap into slow/stop style effects on abilities of
shadow." Octopath's Hunter has Leghold Trap, which pushes an enemy's turn
back. FF6 shows no turn order, so the trap becomes FF6's own Slow and Stop.
The picture is Vamp in MGS2, who throws a knife into your shadow and pins you
to the ground: **Shadow pins your shadow.**

The rule is keyed on the Throw command, not on any item, so it works in the
World of Balance with whatever is in the bag. His stars and skeans only
arrive in the World of Ruin (kits.md "Shadow"), and his early kit is thin.
The owner's ruling for Relm, "overshoot rather than undershoot", applies
here too; vanilla's Slow and Stop immunities stand, so most bosses keep
their protection.

Evidence for the numbers below is in `build/attempts/wt/v048-shadow-design/`:
`sources.txt` holds every source line cited (`cite.py` prints it),
`slowstop_immune.txt` decodes every monster's Slow and Stop immunity from
the ROM (`slowstop_immune.py`), and `turn_ticks.txt` gives a monster's turn
in status ticks from the ROM's own arithmetic (`turn_ticks.py`). Nothing
here was played.

**A correction to the brief.** Shadow's boosted Throw does not add passes.
`Ot6ThrowBoost` (`ot6_boost.asm:988`), the "dumped Throw" in multi-hit.md,
is Umaro's arm: it is called only from `UmaroAttack_00`
(`battle_main.asm:3643`), where Umaro throws an ally. Shadow's Throw is
command `$08`, and a boost on it buys `Ot6BoostDmg`'s x2/x4/x8
(`ot6_boostdmg.asm:56`; boost-rewards.md: "Throw, a damaging item | the
multiplier"). It is one hit. §3 decides the boost with that in mind.

## 1. The rule

> **A throw hobbles a free enemy and pins a hobbled one.** Every hit of
> Shadow's Throw that lands on a monster Slows it. A hit on a monster that
> is already Slowed pins it instead: Stop, for eight status ticks, about two
> of its own turns. The pin uses up the hobble, so a pinned enemy is free
> when the pin ends and needs two more throws to pin again. A throw at a
> pinned enemy deals its damage and changes nothing else. A Broken enemy is
> already down: a throw hobbles it if it is free, and never pins it.
> Vanilla's immunities stand: a monster that cannot be Slowed is never
> hobbled or pinned, and one that cannot be Stopped is hobbled and stays
> hobbled.

The rule in full, one ruling for each question:

| Question | Ruling | Why |
|---|---|---|
| Which throws | every Throw (command `$08`) by a character whose hit lands on a monster: any weapon from the bag, the stars, the skeans | keyed on the verb, so it works from Shadow's first World of Balance fight with what the bag holds |
| The smoke and the exit | not affected: they land on allies, and the rule is for monsters | the Shadow Edge and Inviz Edge put Image and Vanish on the party (`CalcItemEffect`, `battle_main.asm:7417-7426`); hobbling a friend is no part of the picture |
| A throw at an ally | nothing (a muddled or deliberate throw at the party) | the trap is for enemies |
| Does the hobble need a hit | yes: it lands with the hit, on the bodies the hit landed on | a throw cannot be dodged (`$11a4 = $20`, `CalcItemEffect`), so in practice only a vanished body, or one whose Image turns the knife aside, escapes it |
| A hit that kills | the death is all that shows | nothing to hobble |
| Slow's length | until something lifts it: vanilla Slow has no timer | accept the engine |
| The pin's length | 8 status ticks (`OT6_PIN_TICKS = 8`), half a break (`OT6_BREAK_TICKS = $10`) and under half of vanilla Stop's 18 (`SetStatus_14`, `battle_main.asm:12039-12045`) | §1.1 |
| Re-pinning | a pinned enemy cannot be pinned again until the pin ends, and the pin used up the hobble, so it takes a hobble and then a pin | stops a lock without weakening the pin; §1.2 |
| Multi-target throws | the skeans strike every enemy, and each body they land on is hobbled or pinned by its own state | the rule is per hit; §5 weighs it |
| A Broken enemy | hobbled if free; never pinned; its hobble waits for it to rise | §2 |
| A pinned enemy that breaks | both run; whichever ends last gives back its turns | neither timer touches the other (§4) |
| Haste | a hobble takes a Hasted enemy's Haste (vanilla `SetStatus_12` clears Haste when it sets Slow, `battle_main.asm:12004-12010`); Haste cast on a hobbled enemy frees it (`SetStatus_13` clears Slow) | accept the engine |
| Other sources of Slow | a monster Slowed by Bismark's Slow, Slow 2 or Diamond Dust is hobbled: Shadow's next throw pins it | the rule reads the status, not who set it, and the mark shows the status (§4.5) |
| Gogo | Gogo's Throw and a Mimic of a throw hobble and pin by the same rule | the owner's rule for Gogo (#547) gives him each command's full kit; keyed on the command, the copy gets it for free |
| Umaro's Throw | unchanged: he throws an ally (`$b5 = $24`), not command `$08` | it is his arm, not Shadow's verb |
| Interceptor | unchanged: the dog's counter is not a throw | |
| Assassinate | unchanged: its kill reads the break, and a throw it kills with needs no hobble | |
| Monsters' throws | never hobble the party | the rule is Shadow's |

### 1.1 How long is a short while

FF6's Stop is a counter. `SetStatus_14` (`battle_main.asm:12039-12045`)
writes `$12` (18) to `$3af1,y`, and `DecCounters` decrements it each time
the body's speed accumulator carries (`battle_main.asm:15494-15511`): `lda
$3adc,x / adc $3add,x / sta $3adc,x / bcc` returns, a carry runs `Ot6Tick`
(the break timer) and then `dec $3af1,x`. The accumulator adds `$3add`, the
body's speed class: `$20` Slowed, `$40` normal, `$54` Hasted (`CalcSpeed`,
`battle_main.asm:1604-1616`). So Stop and the break count the same ticks,
and both run half as fast on a Slowed body.

DESIGN.md measured a tick: "`OT6_BREAK_TICKS` is `$10` ... which measures
**2159 frames** — about 36 s of battle time — for an on-stage monster",
134.9 frames a tick at normal speed. Vanilla Stop's 18 ticks are about 2429
frames, 40 s.

A monster's turn, from the same arithmetic (`turn_ticks.txt`; `CalcSpeed`
for the gauge, `UpdateBattleTime` adding it once per two frames,
`battle_main.asm:2715-2760`, and a new game's battle speed field of 2,
`menu_sram.asm:102`):

```
median monster speed 33.5 quartiles [30.0, 33.5, 39.75]
speed 30 battle-speed-field 2: a turn = 4.27 ticks =   546 frames at normal speed
speed 40 battle-speed-field 2: a turn = 3.56 ticks =   455 frames at normal speed
```

Both the gauge and the tick scale with `$3add`, so **a turn's length in
ticks does not depend on Slow or Haste**: a pin of N ticks costs an enemy
the same share of its own turns whatever its speed class. At the default
battle speed a median enemy takes a turn every 4 ticks; a break (16 ticks)
is about four of its turns, vanilla Stop about four and a half.

The pin is **8 ticks: about two of a median enemy's turns, about 1080
frames (18 s) at normal speed.** That is the same eight Relm's Still Life
adds to a break (kit-relm.md). Because the pin uses up the hobble, the pinned
enemy ticks at its normal rate, so 8 ticks is 18 s in wall time and not 36.
Six would be closer to "a short while"; eight follows the owner's lean to
overshoot (§8 asks).

While Stopped, a monster's gauge does not fill: `_c208c6` sets `$3aa0`
bits 4 and 6 and clears bit 4 only past `Ot6Gate`'s stop-or-broken test
(`battle_main.asm:1446-1457`), and `UpdateBattleTime` skips the gauge of a
body with any of `$3aa0`'s `$3a` bits (`battle_main.asm:2754-2760`). So a pin
delays the enemy's next turn by exactly its length. That is Leghold Trap.

### 1.2 Why the pin uses up the hobble

If the hobble outlived the pin, the pin would tick at the Slowed rate
(twice as long in wall time, about 2158 frames) and every throw after the
first would pin the moment the last one ended: Shadow alone could hold an
enemy down for good with about one turn in six. Using it up makes each pin cost two throws (two of
Shadow's turns and two items), leaves a gap after each pin in which the enemy
moves at full speed, and gives the shield line one state at a time: a dagger
while hobbled, a knife in its shadow while pinned, nothing when free (§4.5).
Picture: the knife comes out of its leg and goes into its shadow.

Measured as arithmetic, with Shadow throwing at one enemy on every turn of
his (his turn is about 377 frames at his speed of 38, `char_prop.asm:185`,
by the gauge arithmetic above for a character), the cycle is pin, two idle throws' worth of time, hobble,
pin: about 1508 frames, of which the enemy is pinned 1079 and Slowed 377.
It gets about 0.44 of a turn a cycle against 2.76 untouched, so it loses
about 84% of its turns for half of Shadow's. That is strong, and it is only
reachable on a body that takes both Slow and Stop (§5).

### 1.3 Which enemies take it

From the ROM (`slowstop_immune.txt`: MonsterProp +22, "blocked status 3",
read by `LoadRageProp` at `battle_main.asm:7881`; `FixImmuneStatus` blocks
Slow with Haste, `battle_main.asm:6583-6592`), of 384 records, tallied in
`slowstop_tally.txt`:

```
  69 slow=IMMUNE stop=IMMUNE
   4 slow=IMMUNE stop=takes
  42 slow=takes stop=IMMUNE
 269 slow=takes stop=takes
```

Nearly all trash takes both. Among the bosses Shadow is seated for:

- **World of Balance.** The Phantom Train (`$106`) is immune to both;
  AtmaWeapon (`$117`) takes Slow and not Stop; Nerapa (`$118`) takes Stop
  but not Slow, so it is never hobbled and never pinned. No boss of his
  World of Balance stretch can be pinned. The Kefkas at the Imperial Camp
  are character entities with no monster record (bosses-wob.md §6-7).
- **World of Ruin.** Inferno (`$10c`) takes Slow, not Stop, and its arms,
  Rough (`$141`) and Striker (`$142`), take both (Kefka's tower, battle 114,
  party 3 with SHADOW, route-wor-kefka-tower.md). Doom, Chadarnook, Dullahan,
  Hidon, Atma, the second Guardian and the Ice, Blue, Red and Dirt dragons
  take Slow and not Stop. White Drgn (`$024`), Poltrgeist (`$129`),
  SrBehemoth (`$119`), Hidon's Hidonites and one Tentacle take both.
  Wrexsoul, Goddess, Doom Gaze, the Gold, Skull and Storm dragons and the
  final Kefka (`$12a`) take neither.

## 2. Against the shields

**A pin is FF6's Stop, nothing more.** It does not chip, does not reveal,
and does not change damage. It takes turns, and Break takes turns, so the
two must read cleanly side by side.

**A Broken enemy is never pinned.** It already loses its turns
(`Ot6Gate`, `Ot6BrokenTurn`); a pin running under a break would mostly
run out before the break did, and, using up the hobble, would end the Slow
that is stretching the break (below). So a throw at a Broken enemy deals its
broken ×2 and hobbles it if it is free; a hobble already on it is kept for
when it rises, and the next throw after the break ends pins it. What the
player reads: break it, hit it while it is down, pin it as it gets up.

**A pinned enemy that breaks** keeps both: the break timer (`$3e88`,
`Ot6Tick`) and the stop counter (`$3af1`) tick on the same carry and never
touch each other (§4.4). It gets its turns back when the later one ends.

**The hobble lengthens breaks.** OT6's break timer rides the monster's speed
accumulator (`Ot6Tick`, called from `DecCounters` on the carry,
`battle_main.asm:15501`), so a Slowed body's break ticks at `$20` against
`$40`: twice as long in wall time. This is not new: every Slow in the game
already does it (kit-relm.md: "Haste or Slow on the monster changes the
rate, as it does every break"; Bismark's Slow and Diamond Dust apply it in
the World of Balance). What is new is that every throw now carries it. On a
boss that takes Slow and not Stop, most of them, the hobble is the payoff:
half its turns and a break window twice as long, for one throw. With Relm's
Still Life on top a window is three times the plain one. §8 asks whether
that should stay.

**What the player should understand.** The shield gauge is the break; the
mark before it is the trap. A dagger means the next throw pins; a knife in
the shadow means it is pinned; a Broken enemy's dagger waits for it to rise.

## 3. Boost

**A boost on a throw keeps buying the multiplier, and nothing else.** The
hobble and the pin are what every throw does, at 0 BP.

- Every throwable deals damage (Throw takes weapons and the throwing items;
  the smoke and exit are the exceptions and already buy reach), so the
  multiplier always buys something and the boost is never empty.
- **Boost pays once** (guidelines): a point that both multiplied the throw
  and lengthened the pin would be two payoffs.
- At 0 BP the trap costs nothing but the turn and the item. That is what
  makes it Shadow's World of Balance tool: he earns his pip while he throws,
  and the boost stays for the damage the rest of the party is building to.

**Considered and not chosen.**

- *Duration* (each point lengthens the pin): the closest fit, as Runic and
  Morph buy duration. It would take the multiplier from every damaging
  throw, including the skeans that are his World of Ruin damage, to buy
  something that matters only on a hobbled, stoppable target.
- *Passes* (a boosted throw throws again per point, as Umaro's dump does,
  so the second throw pins): one boosted turn would hobble and pin, which
  folds the two-step picture into one action. It would also make Throw a
  multi-hit pierce chipper, a seventh entry in a list kept to six on purpose
  (`tools/audit_multihit.py`), each pass spending an item, and it would
  replace his damage multiplier with Fight's ladder.
- *Certainty*: a throw cannot be dodged, so there is no roll to load.
- *Reach* (a point hobbles one more enemy): the skeans already reach every
  enemy.

## 4. Engine feasibility

**Feasible, with two small hooks for the rule and a seventh cell on the
shield line for the mark.** No new status, no save data.

### 4.1 Where a throw resolves

`Cmd_08` (`battle_main.asm:4077-4082`) sets the damage multiplier `$bd` and
joins the item path at `_189e`. A thrown weapon or star takes
`CalcItemEffect` with carry set (`battle_main.asm:4110`), which clears
`$11a0-$11af`, sets "can't dodge", and branches past every status load for a
throw (`bcs @2adc ; branch if tools/throw`, `battle_main.asm:7377`), so a
thrown weapon carries no status of its own; only the Inviz and Shadow Edges
set one (`battle_main.asm:7417-7426`). A skean takes the spell path
(`@18e3`) with `$b5` still `$08`. Both reach `ExecAttack`.

`ExecAttack` runs `CalcAttackEffect` and then `UpdateStatus` once per pass
(`battle_main.asm:8470-8480`). `CalcAttackEffect`'s per-target loop (`@3440`)
visits only the bodies the hit landed on (`$a4`) and calls
`MagicStatusEffect` for each (`battle_main.asm:8738-8752`), which ORs the
attack's statuses into `$3de8,y`, "status 3/4 to set", and `$3e10,y`, "to
clear". `InitStatusVars` then masks the set against `$3330,y`, the body's
blocked-status-3 mask (`battle_main.asm:11705-11716`), and `UpdateStatus`
runs each status's set and clear routine (`battle_main.asm:11477-11483`).

### 4.2 The hook: `Ot6Pin`

A `jsl Ot6Pin` right after `jsr MagicStatusEffect` in the per-target loop
(`battle_main.asm:8749`; beside `Ot6Life3Revive`, `Ot6BreakSpell` and
`Ot6Analyze`, which already hook that loop). With x = the attacker and y =
the target:

1. Return unless `$b5 = $08` (Throw), x < `$08` (a character), y ≥ `$08` (a
   monster), and `$b1` bit 0 is clear (not a counter).
2. A Stopped target (`$3ef8,y & STATUS3::STOP`): return.
3. A Broken target (`OT6_BROKEN_TICKS,y`), or one not Slowed: OR
   `STATUS3::SLOW` into `$3de8,y`. A Slow-immune body loses it to
   `InitStatusVars`'s mask; a Slowed one already holds it.
4. A Slowed, unbroken target whose `$3330,y` allows Stop: OR
   `STATUS3::STOP` into `$3de8,y`, OR `STATUS3::SLOW` into `$3e10,y` (the
   pin uses up the hobble), and set its bit in `OT6_PINNING`. A
   Stop-immune one: nothing (it stays hobbled).

Because the writes go through vanilla's own status-to-set and to-clear
cells, immunity, the Haste/Slow pair and the gauge-constant refresh
(`RemoveStatus_12` sets `$3204`'s CalcSpeed flag,
`battle_main.asm:12021`) all come from vanilla with no extra code. Smoke and
exit throws target allies, so step 1 ends them.

### 4.3 The pin's length: `Ot6StopTicks`

`SetStatus_14` is `php / shorta / lda #$12 / sta $3af1,y / plp / rts`
(`battle_main.asm:12039-12045`). The `lda #$12 / sta $3af1,y` (5 bytes)
becomes `jsl Ot6StopTicks / nop`: if y's bit is in `OT6_PINNING`, clear it
and store `OT6_PIN_TICKS`; else store `$12`. Every other Stop (Fenrir's
spell, the monsters' own) keeps vanilla's 18. `OT6_PINNING` is cleared by
`Ot6InitBP` and per slot by `Ot6SeedShields`; a pin blocked at
`UpdateStatus` (never, given step 4's test, but cheap to guard) is cleared
at the action's end with the hold flush.

**A turn already queued.** Vanilla removes no queued action when Stop lands:
`Ot6Gate` refuses to *queue* a Stopped body's turn (`ot6_break.asm:1834`),
and `Ot6BrokenTurn` empties a Broken body's queued turn at `ExecAction`
(`ot6_break.asm:2191`), but nothing empties a Stopped one's. A monster whose
gauge filled just before the pin may still act once. Build step 1 measures
it; if it acts, `Ot6BrokenTurn`'s test widens to "Broken, or Stopped" (one
`ora`), so the pin takes the turn it lands on, as the break does. That also
changes Fenrir's Stop to match, which is the same consistency #291 gave the
break.

### 4.4 Break and Stop timers

No conflict. `Ot6Tick` (`ot6_break.asm:2240`) decrements `$3e88,x`
(`OT6_BROKEN_TICKS`); `DecCounters` then decrements `$3af1,x` on the same
carry (`battle_main.asm:15501-15507`). They share the tick and nothing else.
`Ot6Gate` already answers "stop or broken" with one test
(`ot6_break.asm:1834-1842`). The only ordering detail: `Ot6Tick` runs before
the presence gate and the stop counter after it, so an off-stage monster's
break runs and its pin waits; no fight Shadow is in moves a monster off
stage while pinned, and vanilla Stop has the same order.

**Story counters.** A Stopped monster's counter script does not run
(vanilla; the comment above `Ot6AIOpSize`, `ot6_break.asm`, "as vanilla
skips a Stopped monster's counter commands"). The Broken exception (#314,
#329) lets a Broken monster's story blocks play; a pin has none. Step 1
checks the bodies that take both Slow and Stop against
`build/attempts/wt/story-while-broken/enum_story.py`'s list of story
blocks; Vargas, the airship Ultros and Phunbaba are the known ones, and
Shadow meets none of them while seated (and the airship Ultros, `$168`, is
Stop-immune).

### 4.5 The mark on the shield line

**How Relm's marks were done** (origin/wt/v047-relm). Relm's paint recolours
cells the line already has: `Ot6BgHudLine` (`ot6_hud.asm`) asks
`Ot6UnderAttr`, `Ot6StillAttr` and `Ot6StillBrokenAttr` (`ot6_paint.asm:1232-
1265`) for the attribute of the count, the emblem and the broken shield, and
they answer `OT6_PAINT_ATTR = $21 | (6 << 2)`, text palette 6, green, when
the slot's bit is in a mask (`Ot6SlotHas`). No new cell, no new tile; the
cost is a test per line and three small procs.

**Why the trap needs its own cell.** Recolouring would collide with Relm's
green on the same cells, and colour alone cannot say "hobbled" and "pinned"
apart from "painted". A shape can. The line today is six cells: the lead
cell (the emblem, or the broken shield) at the anchor less one, the count,
and four weakness cells (`ot6_hud.asm:288-353`; the flush,
`ot6_hud.asm:863-880`).

**The mark: one cell before the lead cell, at the monster's feet.**

- **Hobbled:** the battle font's own dagger, glyph `$D8`
  (`small_symbols_en.json`: `"0xD8": "{dagger}"`), the same font page the
  class icons use (`Ot6ClassGlyphTbl`, `ot6_icons.asm:661`). No new art.
- **Pinned:** a knife standing point-down, one new 8×8 2bpp tile (16 bytes)
  in a free cell of the field font page beside `Ot6BgGlyphCellTbl`'s, drawn
  by `gen_shield_glyphs.py` beside the emblem. Fallback with no new art: the
  dagger in palette 7, the broken shield's red.
- **Free:** the cell is blank.

The mark shows the status, from any source: a body Slowed by Bismark's Slow
shows the dagger, since the next throw will pin it; one Stopped by Fenrir
shows the knife. That is the true state, and it teaches the rule.

**It lands with the hit** (#539). A throw's status is computed in
`CalcAttackEffect` and applied by `UpdateStatus`, both before the battle
script plays the throw, so a mark read from the live status would appear
before the knife flies. The mark rides the gauge's hold instead:

- `Ot6Hold` (`ot6_break.asm:941`) also snapshots the slot's mark (live
  Slow/Stop) into `OT6_SHOWN`'s odd byte. `OT6_SHOWN` is 12 bytes, stride
  2 by slot (`ot6_memory.inc:641`), and every store to it is 8-bit at an
  even offset, so the odd bytes are free.
- `Ot6Pin` calls `Ot6Hold` on the target, so a throw's target is held from
  the moment its hit is computed.
- `Ot6EvPush` (`ot6_break.asm:1086`) packs the mark after this hit into the
  event's class byte, bits 4 and 5 (the four classes use bits 0-3): the live
  Slow/Stop, plus `$3de8,y`'s pending set, less `$3e10,y`'s pending clear,
  masked by `$3330,y`, since the numeral is queued before `UpdateStatus`
  runs (`Ot6EvPush`'s own note: "its death not yet marked (UpdateStatus)").
  `Ot6EvApply` copies the bits to the odd byte and masks them off before
  `Ot6RevealSibs`.
- `Ot6BgHudLine` draws the held mark while the slot is held, the live
  status otherwise. Timer changes (a pin wearing off, a Haste) show live,
  at once, which is when they happen.

**Cost.** The flush writes one more word a line (it starts one column
earlier, two before the anchor), plus one for the vacated cell when a line
moves; the worst burst grows from about 82 words to about 94, 11.8 scanlines
at the measured ~8 words a scanline, ending near scanline 260 of 262
(`ot6_hud.asm`'s own budget note above the flush). That fits, but the margin
is thin and step 2 measures it with the existing `@late` gate. A line
anchored in column 0 or 1 puts the mark in the row above, so it takes the
lead cell's edge rule (`ot6_hud.asm:863-867`). Fallback if the margin
fails: the cell after the fourth weakness cell, appended to the same burst
with no address change.

### 4.6 Battle RAM

| Name | Size | Shape | Cleared by |
|---|---|---|---|
| `OT6_PINNING` | 1 | monster mask, slot s = bit s: a Stop this action queued as a pin | `Ot6InitBP`, per slot in `Ot6SeedShields`, consumed by `Ot6StopTicks` |
| `OT6_MARKCELL` | 6 | per slot: 0 free, 1 hobbled, 2 pinned, as the line shows it | `Ot6InitBP` |
| held mark | 0 | `OT6_SHOWN`'s odd bytes | with the hold |

Seven bytes. After Relm's build the measured-free tail holds 11
(`OT6_UNDERPAINT` at `$ef14`, the bound `<= $ef1f`, origin/wt/v047-relm
`ot6_memory.inc:690-702`), so they fit there, with asserts in
`ot6_memory.inc`. `OT6_MARKCELL` holds a state, not a tile word, because
twelve bytes of words would not fit; the flush looks the word up in a
three-entry table, a few cycles a line.

### 4.7 Gogo, Mimic, Umaro, Assassinate

- **Gogo's Throw** is command `$08` by a character: the hook covers it with
  nothing added.
- **Mimic** re-runs the copied command's handler (multi-hit.md), so a copy
  of a throw reaches `Ot6Pin` as command `$08` from Gogo. It reads the
  target's state at the copy: Shadow's throw hobbles, Gogo's copy pins.
- **Umaro's Throw** runs `$b5 = $24` (`Ot6UmaroThrow`): outside the hook.
- **Assassinate** is untouched. Its kill is decided at the break
  (`ot6_divine.asm`); a throw that kills shows only the death.

## 5. Balance

Numbers: a pin is 8 ticks, about 1079 frames (8 × 134.9) at normal speed,
about two of a median enemy's turns; a break is 16 ticks; vanilla Stop 18.

| Where | What it does | Why it is not essential | The limit |
|---|---|---|---|
| World of Balance trash (the Imperial Camp's Templars and M-TekArmor, the Phantom Forest's ghosts, the Floating Continent's Apokryphos, Brainpan, Misfit, Wirey Drgn) | two throws take the dangerous one out for two of its turns; one throw halves its pace | Fight kills most trash in the same two turns | two throws and two items a pin; the pin frees it, and it has to be hobbled again |
| AtmaWeapon, the Floating Continent (Shadow is seated, forced) | a hobble halves its turns and doubles its break window | Bismark's Slow does the same, and the fight is won without either | Stop-immune: never pinned |
| Inferno's arms, Rough and Striker (Kefka's tower, party 3) | the arms can be pinned in turn while the party works on Inferno | the fight is won on breaks and levels today (route-wor-kefka-tower.md) | two throws a pin, one arm at a time |
| White Drgn, Poltrgeist | pinnable bosses: Shadow can take most of their turns with half of his | Fenrir's Stop does more for MP (18 ticks, and its boost reaches more bodies) | Shadow's turns and the bag |
| Stop-immune bosses (Doom, Chadarnook, Dullahan, Atma, four dragons) | the hobble: half their turns, breaks twice as long | Slow spells do the same | never pinned |
| The skeans on a crowd | the first hobbles every enemy, the second pins them all for two turns each | the skeans already end most crowds; each costs gil | World of Ruin only, two skeans for one round of pins |

**Does it trivialise trash?** Not by itself. A pin needs two throws, which
kill most World of Balance trash anyway, and each throw spends an item from
a thin bag. Two skeans pinning a whole crowd is the strongest case; it is
two turns and two skeans to win a round, in the World of Ruin, against
crowds the skeans already beat.

**Does it trivialise a boss?** Only the few that take both, and those were
already open to Fenrir's Stop, which lasts more than twice as long and costs
no item. The new thing is reach in time: the pin exists in the World of
Balance, where no Stop does. No World of Balance boss Shadow meets can be
pinned (§1.3).

**The real new power is the hobble on bosses.** Most bosses that block Stop
take Slow, so every throw now halves a boss's turns and stretches its
breaks. Slow already did this; Shadow makes it free and early. Leaning
strong, it stays; §8 asks.

**His World of Balance stretch.** Shadow is a hired sword who comes and
goes: the Imperial Camp, the Phantom Forest and Train, and the Floating
Continent. His Fight is a pierce key; until now Throw was a skean on a
revealed weakness and little else. With the trap his turn always does
something Fight cannot: the camp's Templars and M-TekArmor, the train's
ghosts and the continent's crowds can be held, and AtmaWeapon hobbled. It
makes him the party's tempo piece while he is there, which is what a hired
assassin should be, and the bag's spare Dirks and Shuriken become
ammunition worth carrying.

## 6. How the test player should use it

A driver policy (`Driver:shadowLine`), in event battles first (the Locke,
Setzer and Relm precedent), random battles keeping today's Fight and skean
lines so the legs' frame cost stays put. In priority order:

1. **The skean line stands** (a skean whose element a revealed weakness
   takes): it now also hobbles or pins every body it lands on.
2. **Pin**: a standing, unbroken, Slowed enemy that the ROM's
   `MonsterProp +22` lets be Stopped, not already pinned, with the most HP
   left among such; throw the cheapest throwable (§ below).
3. **Hobble a boss**: a boss that takes Slow and is not Slowed, at the open
   and after each pin ends. On a boss that blocks Stop, once is enough.
4. **Hold the throw at a Broken boss** that is hobbled already: Fight for
   the ×2, and throw as the break ends.
5. Otherwise Fight, as now.

**What it throws.** The cheapest item in the bag that is not worn by a
seated member and not reserved: a spare weapon by its shop price, then a
star, never a skean outside rule 1. Supply: about level ÷ 4 cheap
throwables bought at weapon shops on the route where Shadow is seated
(Dirks in the World of Balance, Shuriken at Thamasa in the World of Ruin),
priced in gil as the guidelines ask.

Each line logs what it read (`[shadow] pin slot 1 Rough: Slowed, stop ok,
Dirk`; `[shadow] hobble slot 0 AtmaWeapon: stop-immune`) so a run shows the
trap was exercised. The canon line plays the policy; a branch leg can hunt
the rare cases (a Gogo copy that pins, a pinned enemy that breaks).

## 7. Build plan

Each step is its own merge, with a suite red on main and on its mutant and
green on the change.

| # | Step | Suite | Mutant it must fail | Moves the line | Size |
|---|---|---|---|---|---|
| 0 | Measure: a Stopped monster's already-queued turn (does it act?); the tick against DESIGN.md's 134.9 frames; the flush's margin with a seventh cell | `lab_pinturn` (a lab, kept under build/attempts) | -- | no | S, machine time |
| 1 | The rule: `Ot6Pin` in the per-target loop, `Ot6StopTicks` in `SetStatus_14`, `OT6_PINNING`; `Ot6BrokenTurn`'s Stop arm if step 0 says a queued turn runs | `battle_shadowpin`: a throw hobbles (Slow set, `$3add = $20`); the next pins (`$3af1 = 8`, Slow cleared); a throw at the pinned one changes only HP; a Broken hobbled body stays hobbled and unpinned; a Stop-immune body stays hobbled; a Slow-immune body is untouched; the smoke and exit touch no monster; a Fenrir-style Stop keeps 18; Gogo's Mimic pins after Shadow's hobble; a skean hobbles every body it lands on | `OT6_PIN_TICKS` ignored (vanilla 18); the pin keeps the Slow; no character test (a monster's throw slows the party) | no (the driver never throws for it yet) | S, ~70 bytes F0, two hooks |
| 2 | The mark: the seventh cell, the knife tile, `OT6_MARKCELL`, the held mark in `OT6_SHOWN`'s odd bytes and the event's class bits | `battle_shadowmark`: the mark cell's VRAM word before the throw's numeral, after it, while pinned, at wear-off; a Slow spell's mark appears at its script's end; Relm's green cells unchanged beside it; the #539 display suites (`battle_break`, `battle_breakflash`) stay green | the mark read live (it appears before the numeral) | no | M, ~150 bytes, one 16-byte tile, the flush |
| 3 | The driver policy and the bag's throwables, then the re-cut of every tracked save Shadow is seated in (the Imperial Camp to the Phantom Train; the Floating Continent; the Colosseum on), with the line's replay | the legs, a `[shadow]` count per arc | `opts.shadowpin = false` as the control arm | **yes** | M, driver ~120 lines; the replay is machine time |
| 4 | Docs: kits.md, DESIGN.md's cast row, PLAYING.md's Shadow section, the Narshe school if it teaches Throw, the booklet, release notes | -- | -- | no | S |

Steps 1 and 2 change nothing the line plays (no driver throws for the trap,
and the skean line's throws only gain a status the line's fights are won
without; `battle_shadowkit` and the Colosseum leg's skean fights must stay
green, and if a skean fight's outcome moves, that leg re-cuts in step 1).
Step 3 is the one that moves play. Building after #545 and Relm (#538) avoids
cutting the same saves twice, and puts the RAM after Relm's.

## 8. Questions for the owner

**Is two of the enemy's turns the right length for a pin?** As designed a
pin lasts eight ticks, half a break, which is about two turns of a typical
enemy and about eighteen seconds. Vanilla's Stop spell lasts eighteen
ticks. Six ticks would read more like a quick pin and less like a hold. I
recommend eight: it is the overshoot side, the pin costs two throws, and
only a handful of bosses can be pinned at all.

**Should the pin use up the hobble?** As designed the knife moves from the
enemy's leg to its shadow, so a pinned enemy is free when the pin ends and
needs a hobble before it can be pinned again. The other way, the enemy stays
slowed after the pin, the pin lasts twice as long, and every throw after
that pins it, which lets Shadow keep one enemy down for good with about one
turn in six. I recommend using it
up: it keeps the two-step picture, gives the enemy a gap after each pin, and
the marks show one state at a time.

**Should a boost still buy damage on a throw?** As designed the trap comes
with every throw at no cost and the boost multiplies the damage, as now.
The alternative is a boosted throw that throws once per point, as Umaro's
dumped Throw does, so one boosted turn hobbles and pins at once; it would
also turn Throw into a multi-hit shield chipper and spend an item per throw.
I recommend keeping the multiplier: the trap is the everyday tool and the
boost is still Shadow's damage.

**Should slowing an enemy keep stretching its break?** OT6's break timer
runs on the enemy's own clock, so a Slowed enemy stays Broken twice as long.
That was already true of the Slow spell, but every throw now carries it, and
most bosses that shrug off Stop take Slow. A hobbled boss loses half its
turns and stays down twice as long, and with Relm's Still Life three times
as long. I recommend keeping it: it is what makes Shadow worth bringing to
the bosses he cannot pin, and the break window is where #542 put the
payoff. The alternative, a break that always runs at the same pace, would
be a change to every Slow in the game.

**Do the marks read right?** As designed a hobbled enemy shows a small
dagger just before its shield, and a pinned one a knife standing in its
shadow; the mark shows any Slow or Stop, whoever cast it. I recommend this
pair: the dagger is the font's own and the knife is one new tile.
