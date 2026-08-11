# Multi-hit as a first-class dial

Hit count determines break rate: a landed hit that matches a weakness chips a
shield, so the number of times an action strikes is the strongest lever OT6 has
over the break loop, and it multiplies directly against v0.8's MP costs. This
document is a design pass: no data moves and no assembly changes. §10 is the
build list for the pass that does move them.

Owner direction: *"Pummel seems like a good candidate to do 2x
bludgeon, where Suplex is one big hit. Bum Rush could go either way. And not
just Sabin, but also Tools, Quadra Slam should hit 4x, etc."* And the target
shape: *"In Octopath most characters have at least one multi-hit ability they
can lean on for breaking, and a couple have more."*

**Evidence rule (CONTRIBUTING.md).** Every mechanical claim cites the file
and line it was read from, or is labelled **UNVERIFIED**. Numbers taken out
of `.dat` files name the record and byte offset.

Two instruments support this document:
`tools/tests/probe_multihit.lua` (the live rule and the break-window cap) and
`tools/audit_multihit.py` (the shipped table, re-derived from the ROM sources
on every run; it exits nonzero if the enumeration below has gone stale).

---

## Findings

1. **Chip is per hit**, measured rather than inferred: one boosted Fight
   action chipped four shields off one guard (§1).
2. **Cyan is the only character in the game with a multi-hit ability.**
   Pummel is ×1, Bum Rush is ×1, and AutoCrossbow is ×1 per body (§3). Every
   ×2/×4/×8 in `kits.md`'s Chip column is design intent that was never built.
3. **`AutoCrossbow ×4` is a misclassification and should not be carried
   forward.** AutoCrossbow is whole-side rather than multi-hit: four chips
   across four monsters and one against a boss (§2.2). Breadth and rate are
   separate levers and are priced separately.
4. **Excess hits convert to damage rather than being wasted.** A volley that
   breaks its target mid-way stops chipping but keeps hitting, and the
   remaining hits collect the broken ×2 instead (§1.2, measured). Large hit
   counts are therefore self-limiting.
5. **1 BP already buys 1 extra chip**, at no MP cost, for every character
   (`Ot6FightBoost`, measured §1.1). That is the price every
   multi-hit ability competes against, and §7 uses it to answer whether a
   2× Pummel at 4 MP is too strong.

---

## 1. The rule, measured

### 1.1 Per hit, and the mechanism is singular

The engine has exactly one multi-hit mechanism: `$3a70`, *"number of
attacks (0 = 1 attack)"* (`battle_main.asm:6416`), and one loop that consumes
it:

```
@3288:  plx
        dec  $3a70
        bmi  @3291
        pea  ExecAttack-1        ; battle_main.asm:8334-8340
@3291:  rts
```

Every extra count is a whole extra `ExecAttack` → `CalcTargetDmg` pass, and
therefore a whole extra chip opportunity. Quadra Slam reaches that loop by
setting `$3a70 = 3` (`AttackerEffect_32`, `battle_main.asm:10794-10796`); a
boosted Fight reaches the same loop by setting `$3a70 = 1 + 2·BP`
(`Ot6FightBoost`, `ot6_boost.asm:240-248`). A boosted Fight therefore measures
the rule for both, and it can be driven in the opening guard fight, whereas a
Quadra Slam needs Cyan at LV15.

Measured (`probe_multihit.lua` phase 1) against a guard authored with six
shields, class-weak to the party's weapon and weak to no element, so that
neither a beam nor a poison tick could contribute a chip:

| action | `$3a70` set to | chips | shields |
|---|---|---|---|
| unboosted Fight | `1` | 1 | 6 → 5 |
| Fight, 3 BP | `7` | **4** | 5 → 4 → 3 → 2 → 1 |

The chips landed at remaining-counts 7, 5, 3 and 1, the odd ones, which
matches the alternating-hands model: swings alternate hands and an empty
hand lands nothing (`ot6_boost.asm:220-224`), so eight swings are four hits
and four chips. The control guard, authored class-weak to nothing, kept all
six shields.

Two consequences. Per hit is confirmed as the rule for the whole `$3a70`
family, and 1 BP buys 1 extra chip with a single weapon (2 with a Genji
pair), which §7 uses as the price to compare against.

### 1.2 The cap is the break window, and excess hits convert

`probe_multihit.lua` phase 2 ran the identical 8-swing volley into a
two-shield target:

```
$3a70=7   shields 2 -> 1
$3a70=5   shields 1 -> 0    BREAK, timer armed
$3a70=3   chip hook entered, target already 0, no shield write
$3a70=1   chip hook entered, target already 0, no shield write
```

`Ot6Chip` and `Ot6ClassChip` both bail on `lda OT6_BROKEN_TICKS,y / bne done`
(`ot6_break.asm:829-830`, `:927-929`) while the hit itself continues down
`Ot6HitJoin` into `Ot6BrokenDmg`'s ×2. The surplus hits of an over-large
volley are therefore not wasted: they change from break rate into damage at
the point the target breaks. This property matters for the design, because a
hit count larger than a given enemy's gauge still does something useful, and
because hit count and the damage ladder come out of one budget rather than two.

### 1.3 What a hit costs in damage

FF6 subtracts the target's defence per hit (`CalcDmg`,
`battle_main.asm:7404` onward), and OT6 attenuates ×0.5 per hit while shields
hold (`Ot6ShieldedDmg`, called from `Ot6HitJoin`). N hits at power `P/N`
therefore deal strictly less than one hit at power `P` against anything with
defence. Multi-hit is not free: it trades damage for break rate, which is the
shape this dial should have. The exact
compensation curve is a phase-3 measurement (§9) and is not invented here.

---

## 2. Rate, breadth, reach, duration — four levers, priced differently

Rate, breadth, reach and duration are four separate levers with four separate
prices. Breadth is easily mistaken for rate, and the distinction matters
throughout this document.

### 2.1 Rate — hits per action, paid per action
`$3a70`. Chips the same body repeatedly. This is the boss lever.

### 2.2 Breadth — one hit on every body, paid per action
Targeting, not hit count. `ChooseTarget` collapses the target mask to one
random body unless the targeting byte's `INIT` field is non-single
(`battle_main.asm:14951-14961`; `INIT_MASK` values at `const.inc:1298-1302`),
and a multi-target action runs `CalcTargetDmg` once per surviving target
through the loop at `battle_main.asm:8550-8579`, giving one chip per body.

AutoCrossbow is the ability that has been classified wrongly: targeting byte
`$6a` (`INIT` = one-side), `ToolsEffect_07` setting don't-split-damage
(`battle_main.asm:7352-7355`). Against a four-stack it is four chips on four
gauges; against a boss it is one. `kits.md`'s "piercing ×4" reads as rate
but describes breadth. `break-coverage-vector.md` §8.1 and
`break-coverage-sealed-gate.md` §8 already use it correctly as the swarm
answer, so `kits.md` is the document to correct.

Breadth is worth less per chip than rate, because it depends on there
being several bodies, and it does not help against single-target boss fights.
It should therefore be cheaper per chip, and today it is: AutoCrossbow
is 4 MP.

### 2.3 Reach — a second class axis, paid by owning the ability
An ability's break class is independent of the equipped weapon's: Fight swings
whatever is held (`Ot6WeaponClass`), while a Blitz/SwdTech/Tool carries its own
class from `Ot6SkillClassTbl` / `Ot6WeapClassTbl` (`ot6_class.asm:184-197` / `:14-163`).
So a multi-hit can open an axis the weapon cannot.

The static tooling answers a wider question than the design needs.
`check_break_reach.py` models "can field" as game-wide equippability, meaning
every weapon the actor could ever wear. Under that model every walking
character reaches slash, pierce and bludgeoning, and the "ability-only" column
is empty for all fourteen (`audit_multihit.py`'s per-character section prints
that). The design needs the narrower question: can they reach a second axis
without re-equipping, with the weapon they are holding. That is runtime
state, and no static tool answers it. It is recorded as a gap in §9.

One reach fact is solid: Sabin's fists are bludgeoning and so is
Pummel (`ot6_class.asm:163`, `:192`), so a bare-fisted Sabin's Blitz opens no
axis his Fight does not. With claws equipped (slashing,
`ot6_class.asm:139-147`), Pummel becomes his second axis at no extra cost.
That asymmetry is part of his design.

### 2.4 Duration — hits per turn thereafter, paid once
A poison status tick chips, measured. Cmd_22
stores element `$08` itself (`battle_main.asm:13402-13405`) and tail-jumps
`ExecSelfAttack`, so a tick is an ordinary poison hit with no attacker, and it
reaches `Ot6Chip` through the weak branch at `battle_main.asm:1894-1896`.
Measured: two ticks broke a 2-shield poison-weak guard with no action spent
after the application, one chip per tick, ~1048 frames (~17.5 s of battle
time) apart. Sap does not chip, because it has no element. A broken monster receives no
ticks at all (`Ot6Gate`, `ot6_break.asm:1655-1665` → `battle_main.asm:1413-
1417` → Cmd_22's `bit #$10` at `:13368-13371`), so the break window caps
duration the same way it caps rate.

Edgar already owns this curve: Bio Blaster applies a weakness rather than
hitting an existing one. Bio Blaster (item `$a4`) is
rewritten to spell `$7d` Bio Blast by `InitTarget_03`
(`battle_main.asm:6563-6570`), with one-side targeting, POISON element,
power 20, and status1 `$04` = POISON. One cast is one poison chip on every
body plus a further chip per body per ~17 s thereafter. This, rather than any
multi-hit, explains the owner's Zozo sighting.

---

## 3. Phase 1 audit — what the shipped ROM does

`$3a70` is the only mechanism, so grepping every write to it is an
exhaustive enumeration. Ten upward writers exist
(`audit_multihit.py` re-derives them and fails if that changes):

| writer | effect |
|---|---|
| `FightAttack` `battle_main.asm:3505` | `= 1` (two hands), `= 7` with Offering |
| `Ot6FightBoost` `ot6_boost.asm:247-248` | `+= 2` per pending BP |
| Jump + Dragon Horn `battle_main.asm:3953-3959` | `+= 1..3`, random |
| `CheckWeaponMagic` `:8870` | `+= 1` (random weapon spellcast, which is a spell rather than a swing) |
| `AttackerEffect_49` `:10547` | `+= 1` (magicite / random summon) |
| **`AttackerEffect_32`** `:10782-10784` | **`= 3` → four attacks, random target** |
| **`AttackerEffect_36`** `:10987` | **`+= 1`, at quarter power** |

Scanning all 256 `MagicProp` and all 256 `ItemProp` records for those two
effect ids finds three abilities in the whole game:

| id | ability | hits | note |
|---|---|---|---|
| `$58` | Quadra Slam | **×4** | random target per hit |
| `$5b` | Quadra Slice | **×4** | random target per hit |
| `$59` | Empowerer | **×2** | quarter power, and it is a drain |

### 3.1 The three kits, as shipped

`hits` is per target. `tgt` is the targeting byte. `mp/chip` is the MP price
divided by hits, computed single-target, so breadth abilities read at their
boss-fight value, which is the one that matters.

**SwdTech** (magic ids `$55-$5c`, names from `BushidoName`)

| tech | id | hits | tgt | class | pow | MP | mp/chip |
|---|---|---|---|---|---|---|---|
| Dispatch | `$55` | 1 | `$53` single | slash | 120 | 4 | 4.0 |
| Retort | `$56` | 1 | `$53` single | slash | 56 | 10 | — (counter) |
| Slash | `$57` | 1 | `$53` single | slash | 8 | 13 | 13.0 |
| **Quadra Slam** | `$58` | **4** | `$53` single | slash | 72 | 16 | **4.0** |
| Empowerer | `$59` | 2 | `$53` single | slash | 49 | 18 | 9.0 |
| Stunner | `$5a` | 1 | `$7a` one-side | slash | 97 | 28 | 28.0 |
| **Quadra Slice** | `$5b` | **4** | `$53` single | slash | 70 | 50 | **12.5** |
| Cleave | `$5c` | 1 | `$7a` one-side | slash | 0 | 99 | — (execute) |

**Blitz** (magic ids `$5d-$64`)

| blitz | id | hits | tgt | class/elem | pow | MP | mp/chip |
|---|---|---|---|---|---|---|---|
| Pummel | `$5d` | **1** | `$53` single | bludg | 110 | 4 | 4.0 |
| AuraBolt | `$5e` | 1 | `$53` single | holy | 68 | 10 | 10.0 |
| Suplex | `$5f` | 1 | `$7e` one-half | bludg | 180 | 13 | 13.0 |
| Fire Dance | `$60` | 1 | `$7a` one-side | fire | 42 | 17 | 17.0 |
| Mantra | `$61` | 1 | `$3e` allies | — | 1 | 16 | — |
| Air Blade | `$62` | 1 | `$7a` one-side | wind | 78 | 28 | 28.0 |
| Spiraler | `$63` | 1 | `$3e` | — | 200 | 50 | — |
| Bum Rush | `$64` | **1** | `$53` single | bludg | 128 | 99 | 99.0 |

**Tools** (item ids `$a3-$aa`, `ItemProp`)

| tool | id | hits | tgt | class/elem | pow | MP | mp/chip |
|---|---|---|---|---|---|---|---|
| NoiseBlaster | `$a3` | 1 | `$6a` one-side | — | 0 | 6 | — (confuse) |
| Bio Blaster | `$a4` | 1 | `$6a` one-side | **poison + status** | 20 | 8 | 8.0 + duration |
| Flash | `$a5` | 1 | `$6a` one-side | — | 42 | 6 | — (blind) |
| Chain Saw | `$a6` | 1 | `$43` single | slash | 252 | 18 | 18.0 |
| Debilitator | `$a7` | 1 | `$43` single | — | 0 | 10 | — (adds a weakness) |
| Drill | `$a8` | **1** | `$43` single | pierce | 191 | 16 | 16.0 |
| Air Anchor | `$a9` | 1 | `$43` single | pierce | 128 | 14 | 14.0 |
| AutoCrossbow | `$aa` | **1/body** | `$6a` one-side | pierce | 125 | 4 | 4.0 (boss) |

**Targeting-byte caveat.** The `INIT` decode above is read from
`const.inc:1298-1302` plus `ChooseTarget` (`battle_main.asm:14951-14961`), not
observed in play. Suplex's `$7e` decodes as "all monsters", which disagrees
with how Suplex is generally understood to behave. The difference is likely
the menu cursor's default versus what a player confirms, since these commands
all carry `MULTI_TARGET`. Flagged UNVERIFIED; §10 lists a one-run probe to
settle it, and no recommendation below depends on it.

### 3.2 The per-character gap

Read straight off §3.1:

| character | multi-hit today | probe without spending BP |
|---|---|---|
| **Cyan** | Quadra Slam ×4, Quadra Slice ×4, Empowerer ×2 | yes, three of them |
| everyone else | **none** | one chip per action |

Against the owner's Octopath rule (*most characters have at least one, a
couple have more*), the game currently has one character with three and
thirteen with none. That is the gap, and closing it takes more than assigning
counts to the abilities that exist.

---

## 4. The design

Principles, stated so they can be reviewed:

- **P1 — Rate belongs on a signature ability rather than a capstone.** A
  cheap, early, repeatable multi-hit is what gives a character a probing
  identity. Ultimates should be spent into an already-opened gauge rather than
  used to open it. Cleave already follows this rule, since it refuses a target
  that is not Broken, and Bum Rush should not contradict it.
- **P2 — One rate ability per kit, no more** (Cyan excepted; his three are
  vanilla and are the "a couple have more" case the owner asked for).
- **P3 — Breadth, rate and duration should be three different abilities**, so
  a kit presents them to the player as three different answers.
- **P4 — Hit count splits an ability's power; it does not add to it.** §1.3.
- **P5 — Never let a hit count exceed the largest gauge it will meet.** §1.2
  means overshoot is not wasted, but it is not free either: an ability that
  reliably empties any gauge in one action removes the party-composition
  decision from every fight it is used in.

### 4.1 Sabin — the economy prober

| ability | count | reason |
|---|---|---|
| **Pummel** | **×2** bludgeoning | The owner's proposal, and it fits P1: 4 MP at level 1, the earliest multi-hit in the game and his signature. Two chips per action against the 31 authored 2-shield species means Sabin breaks trash without help, which matches the Bio Blaster sighting. Power 110 → ~60 per hit (P4; the exact number comes from §9's measurement). |
| **Suplex** | **×1** | The owner's proposal, and P3: this is the single-hit committer. 180 power is the highest in the Blitz list and it should stay one number. |
| **Bum Rush** | **×4** bludgeoning, not ×8 | ×8 breaks every authored gauge but one in a single action (shield census: 31 species at 2, 10 at 3, 4 at 4, 5 at 5, 8 at 6, 5 at 7, one at 8, one at 11), which fails both P5 and P1, because the ultimate would become the opener. ×4 empties trash and the low bosses outright and is still a capstone moment, while bosses with 5 or more shields need Sabin's own Pummel or a partner to finish. See §8 for the ×8 ledger entry. |
| AuraBolt / Fire Dance / Air Blade | ×1 | Element probes, and Fire Dance/Air Blade are already breadth. Adding rate on top would make Sabin the answer to every fight. |

Identity: the cheapest chips in the game, on one axis (two if he wears claws).

### 4.2 Edgar — the machinist, three curves in one kit

| ability | count | reason |
|---|---|---|
| **AutoCrossbow** | **×1 per body**, unchanged | It is breadth (§2.2) and it is already the designed swarm answer in two of the break-coverage docs. Making it ×4 per body would be 16 chips against a four-stack. `kits.md`'s "×4" is corrected to "whole side, one chip each". |
| **Drill** | **×2** piercing | The owner said "Tools too", and Drill is the tool that should change: it is the armoured-boss answer, since it ignores defence (`ToolsEffect_05`, `battle_main.asm:7330-7333`), so two chips into one gauge complements AutoCrossbow's breadth against swarms. 16 MP → 8.0 MP/chip, which prices rate above breadth, the correct relationship. Power 191 → ~105 per hit (P4). |
| **Bio Blaster** | ×1 per body **+ the DOT** | Duration (§2.4); the tick chip stays as it is. No hit count. |
| **Chain Saw** | ×1 | The slash committer, 252 power. P3. |
| Air Anchor / NoiseBlaster / Flash / Debilitator | ×1 | Gag, and three non-damaging utilities. |

Identity: the only character who fields all three cost curves, breadth
(AutoCrossbow), rate (Drill) and duration (Bio Blaster), and two classes
(pierce + slash) without changing weapons.

### 4.3 Cyan — the burst prober, unchanged

Quadra Slam ×4 and Quadra Slice ×4 already ship and already satisfy the
owner's "×4" instruction. No data moves for Cyan. Two things are worth
recording rather than changing:

- Both are `AttackerEffect_32`, which sets the random target flag
  (`tsb $ba, #$40`, `battle_main.asm:10797-10798`). Against a boss all four hits
  land on the boss; against a four-stack they scatter. Quadra Slam is
  therefore strong against a single boss gauge and unreliable against groups,
  which is the opposite of AutoCrossbow. That behaviour is unintended in
  vanilla but should be kept.
- Empowerer ×2 at quarter power is a drain rather than a probe. Leave it.

Identity: four chips into one gauge, on a slash axis, at burst prices.

### 4.4 Everyone else

Thirteen characters have no multi-hit ability. This pass does not
invent counts for kits that are still being designed (Locke, Gau, Mog dances,
Strago lores, Setzer slots, Shadow throw, Relm). It states the rule for those
passes to apply:

> **Every kit with a damaging physical verb gets exactly one cheap, early,
> repeatable multi-hit** (P1/P2). A kit whose verbs are all magical satisfies
> the Octopath rule differently — through element spread plus boosted Fight —
> and needs no hit count.

Applied to the pending kits, as proposals for their own passes rather than
decisions made here:

| character | candidate | why |
|---|---|---|
| Shadow | **Throw ×2** | He throws a pair. His only damaging verb, and his weapon classes (pierce/bludg) are narrow. |
| Setzer | Slots' physical face ×? | Chance verb; boost already buys certainty (DESIGN.md's canon rule), so hit count may be the wrong lever for him. |
| Locke | — | Filch and Bestow are utility. His probe is his weapon, so no rate. |
| Mog / Strago / Relm / Gau / Terra / Celes | — | Element and breadth kits. Boosted Fight is their rate. |

The owner's rule, *"Even a weak attacker can be useful in a pinch if they can
multihit with a staff or something"*, is already true in OT6 for every
character: `Ot6FightBoost` gives +1 landed hit per BP with any
weapon (§1.1, measured). The question that constrains the design is which
characters are forced to spend BP in order to probe. After
this pass that is everyone except Sabin, Edgar and Cyan, which is the
intended outcome, because those three are the physical-kit characters.

---

## 5. What this costs to build

`$11a9` holds one byte and selects one effect. `LoadMagicProp` copies the
record's `+$09` byte and doubles it into a jump-table index
(`battle_main.asm:6949`), and `DoAttackerEffect` dispatches exactly one
routine (`:10310-10317`). Five of the abilities above already carry a special
effect (Suplex `$30`, Retort `$3c`, Stunner `$3f`, Cleave `$23`, Empowerer
`$36`), so hit counts cannot be data-authored into that slot for any ability
that has one, and reusing `AttackerEffect_32` would force ×4 plus random
targeting on everything.

The answer that fits OT6's existing structure is a small table rather than a
special effect:

> **`Ot6HitCountTbl`** — (ability id, extra attacks) pairs, `$ff`-terminated,
> in the same shape as `Ot6SkillClassTbl` (`ot6_class.asm:184-197`) and placed
> beside it, plus the tool-item-id keying `Ot6WeapClassTbl`
> already uses for Tools. One hook adds its value to `$3a70`.

The hook must fire once per action rather than once per swing, or it re-arms
itself indefinitely. `AttackerEffect_32` is the vanilla precedent for that
problem and its fix: it `stz $11a9`s itself immediately after setting the
count (`battle_main.asm:10799`, inside `:10782-10788`). The build pass must pick the site and
prove the once-per-action property with a probe before relying on it.
`Ot6SkillClass`'s site inside `LoadMagicProp` (`battle_main.asm:6938`) and
`Ot6ItemClass`'s inside `CalcItemEffect` (`battle_main.asm:7181`) are the two candidates,
and neither has been checked for re-entry. Not decided here.

Cost estimate: one table (~24 bytes), one `jsl`, one proc. No `MagicProp`
override, no `ItemProp` override, no new RAM.

---

## 6. Interactions, decided

- **Boost does not add hits to abilities.** `Ot6FightBoost` touches Fight
  only; a boosted Blitz/Tool/SwdTech gets potency (`Ot6BoostDmg`) or a folded
  spell tier. Keep it that way: a 3-BP Quadra Slam that hit ten times would
  end the break loop. (`kits.md` proposes an *Overcharge* passive, "+1
  AutoCrossbow hit per 2 BP", which is a per-character exception a passive
  channel could carry later, and it is out of scope here.)
- **SwdTech is already excluded from `Ot6BoostDmg`** because the BP bought the
  tech. Multi-hit does not change that.
- **Break window caps every curve identically.** Rate (§1.2), duration
  (§2.4) and breadth all stop chipping a broken target and convert to ×2
  damage. That is one rule covering three levers, and it is worth stating in
  the player-facing manual.
- **Reveal is per species.** A chip reveals the weakness on every same-
  species slot (`Ot6RevealCommit`), so a whole-side or multi-hit action is
  also the fastest way to learn a weakness. Measured: a poison tick on one
  guard revealed poison on both.

---

## 7. Cost per chip: whether a 2× Pummel at 4 MP is broken

It is not.  The reason is a measured bound rather than a judgement call.

The cheapest chip is free. `Ot6FightBoost` grants +2 swings per BP, which is
+1 landed chip per BP with one weapon and +2 with a Genji pair (§1.1), and BP
costs no MP. The cheapest chip in OT6 is therefore 0 MP, so a
priced ability cannot be too strong on MP-per-chip alone. What it can do is
make BP-spending pointless, and that is the test.

Measured pools (`mp-economy.md`'s table, re-derived from `CharProp+$01`
plus `LevelUpMP`) at Zozo, the stretch the owner played: Sabin 84 (L13), Edgar 87
(L13), Cyan 76 (L12). Chips per full pool, single target:

| ability | MP | chips/cast | casts | chips per pool |
|---|---|---|---|---|
| Fight | 0 | 1 | ∞ | ∞ (1 per turn) |
| Fight, 3 BP | 0 | 4 | BP-limited | ~4 per bank |
| **Pummel ×2** (proposed) | 4 | 2 | 21 | **42** |
| Pummel ×1 (today) | 4 | 1 | 21 | 21 |
| AutoCrossbow (boss) | 4 | 1 | 21 | 21 |
| AutoCrossbow (4-stack) | 4 | 4 | 21 | 84 across four gauges |
| **Drill ×2** (proposed) | 16 | 2 | 5 | **10** |
| Quadra Slam ×4 | 16 | 4 | 4 | 16 |
| Quadra Slice ×4 | 50 | 4 | 1 | 4 |
| **Bum Rush ×4** (proposed) | 99 | 4 | 0 at L13 | — (L70 ability) |

Read that column against the loop rather than against the other rows. A
42-chip pool is 21 turns, and a battle is about five turns, so at this scale
the constraint is the turn rather than the pool. That is the intended result:
multi-hit should change what one turn accomplishes rather than how
many turns a character can afford, because the number of affordable turns is
what `mp-economy.md` already tunes and it should not be tuned twice.

By the turn, the proposal reads:

- Sabin, one turn, 4 MP: **2 chips** on bludgeoning.
- Sabin, one turn, 0 MP + 1 BP: 2 chips on his weapon's class.
- Cyan, one turn, 16 MP + 2 BP: **4 chips** on slashing.
- Edgar, one turn, 4 MP: 1 chip per body, up to 4 bodies.
- Edgar, one turn, 16 MP: **2 chips** on piercing, through armour.

Those five lines are different jobs at clearly different prices, which is the
outcome the pass wanted. Pummel ×2 costs the same as one BP and buys the same
thing, so it is priced at parity with the free option, which leaves the choice
open rather than automatic.

The case to check in playtest (the Serpent Trench precedent) is a
2-shield poison-weak enemy against Sabin with Pummel ×2 and Edgar with Bio
Blaster's DOT, since both then break it unaided. If the WoB trash pool stops
presenting any resistance at all, the adjustment is shield counts on the trash
pool rather than the hit counts, because shield count only becomes a usable
lever once chip rate is nonzero, which is what this pass provides.

---

## 8. What was rejected, and why

- **Bum Rush ×8** (`kits.md`'s number). Rejected on P5 and the shield census:
  ×8 empties every authored gauge but one in a single action, which turns the
  capstone into the opener and removes the composition decision from every
  fight it appears in. Recorded rather than deleted because it is the owner's
  own figure and he may still want it. If so, the way to have it is
  Cleave's: gate the ability on the target being Broken, so its eight hits are
  damage rather than break rate.
- **AutoCrossbow ×4 per body.** Rejected as a misclassification (§2.2): it is
  already ×4 in the sense that matters, and ×4-per-body would be 16 chips
  against a four-stack.
- **Boost adding hits to abilities.** Rejected (§6): a 3-BP Quadra Slam at ten
  hits ends the loop.
- **Reusing `AttackerEffect_32` to author new hit counts.** Rejected (§5): it
  forces exactly ×4 plus random targeting and consumes the single special-
  effect slot, which five of the candidate abilities already spend.
- **Inventing hit counts for the seven kits still being designed.** Declined
  (§4.4): a partial hit-count table is worse than none, and those kits have
  their own passes. The rule is handed over instead.

---

## 9. What this pass could not establish

- **The exact power split per hit.** P4 says split; FF6's per-hit defence
  subtraction plus OT6's per-hit ×0.5 shielded attenuation means the split is
  not a clean division. Needs a damage measurement against a defended target
  before the build lands. `balance-metrics.md`'s instrumentation is the tool.
- **Suplex's real targeting.** `$7e` decodes as one-half (all monsters) and
  that disagrees with the received account of the ability (§3.1). One probe
  run settles it.
- **Reach, properly measured.** `check_break_reach.py` answers "could this
  actor ever field that class", not "can they field it with what they are
  holding" (§2.3). A held-weapon reach model is a separate, useful tool, and
  it would make the rate-versus-reach comparison quantitative.
- **Where the hit-count hook goes** (§5). Two candidate sites, neither checked
  for once-per-action behaviour.
- **Whether a DOT tick's chip should count against a hit-count budget at all.**
  The tick chip stays; whether Bio Blaster's price should rise now
  that its duration curve is understood is a question for the MP economy, not
  for this table.

---

## 10. The build list

For the pass that moves data. Nothing here is done yet.

1. `Ot6HitCountTbl` in `ot6_class.asm`, beside `Ot6SkillClassTbl`:
   `$5d, 1` (Pummel ×2), `$64, 3` (Bum Rush ×4), `$a8, 1` (Drill ×2),
   `$ff` terminator. Three rows. Tools key on item id, per `Ot6WeapClassTbl`'s
   precedent.
2. One `jsl` at the chosen hook, adding the table value to `$3a70`, with
   `AttackerEffect_32`'s self-disable pattern so it cannot re-arm per swing.
   **Prove once-per-action with a probe first.**
3. `MagicProp` power overrides for `$5d` and `$64`, and an `ItemProp` power
   override for `$a8`, to the numbers §9's damage measurement produces. Use
   `magic_prop_en.dat`'s existing named-override mechanism
   (`battle_main.asm:6960-7022`) so the `.dat` stays byte-identical.
4. A suite test in `probe_multihit.lua`'s shape, driving a real Pummel and a
   real Drill and asserting two chips per action. Promote the probe.
5. Re-run `tools/audit_multihit.py`; it should then report five multi-hit
   abilities, not three.
6. Update `kits.md`'s Chip column to the rates this pass builds: "×2" on
   Pummel and Drill, "×4" on Bum Rush. AutoCrossbow's row already reads
   "piercing, whole side", which is the correct reading.
7. `check_break_reach.py` re-run per stretch: hit counts do not change which
   classes a party can field, but `break-coverage-*.md`'s feel notes will want
   revisiting.
