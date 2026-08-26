# Multi-hit as a first-class dial

Hit count determines break rate: a landed hit that matches a weakness chips a
shield, so the number of times an action strikes is the strongest lever OT6 has
over the break loop, and it multiplies directly against MP costs. Pummel
strikes twice, Bum Rush four times and Drill twice, each at power divided by
its hit count (§5, where the hook lives).

Three instruments support the shipped rule:
`tools/tests/probe_multihit.lua` (the live rule and the break-window cap),
`tools/tests/battle_hitcount.lua` (a suite test: a real Pummel, driven by
controller input on the Mt. Kolts fixture, strikes twice), and
`tools/audit_multihit.py` (the shipped table, re-derived from the ROM sources
on every run; it exits nonzero if the enumeration below has gone stale).

---

## Findings

1. **Chip is per hit**, measured rather than inferred: one boosted Fight
   action chipped four shields off one guard (§1). Re-measured on the v0.10
   ROM, same result.
2. **Three characters now have a multi-hit ability; before v0.10 only Cyan
   did.** Sabin has Pummel ×2 and Bum Rush ×4, Edgar has Drill ×2, Cyan keeps
   vanilla's Quadra Slam ×4, Quadra Slice ×4 and Empowerer ×2. AutoCrossbow is
   still ×1 per body, which is breadth rather than rate (§2.2).
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
attacks (0 = 1 attack)"* (`battle_main.asm:6428`), and one loop that consumes
it:

```
@3288:  plx
        dec  $3a70
        bmi  @3291
        pea  ExecAttack-1        ; battle_main.asm:8389-8392
@3291:  rts
```

Every extra count is a whole extra `ExecAttack` → `CalcTargetDmg` pass, and
therefore a whole extra chip opportunity. Quadra Slam reaches that loop by
setting `$3a70 = 3` (`AttackerEffect_32`, `battle_main.asm:10849-10850`); a
boosted Fight reaches the same loop by setting `$3a70 = 1 + 2·BP`
(`Ot6FightBoost`, `ot6_boost.asm:408-428`). A boosted Fight therefore measures
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
hand lands nothing (`ot6_boost.asm:402-403`), so eight swings are four hits
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
(`ot6_break.asm:846-847`, `:964-965`) while the hit itself continues down
`Ot6HitJoin` into `Ot6BrokenDmg`'s ×2. The surplus hits of an over-large
volley are therefore not wasted: they change from break rate into damage at
the point the target breaks. This property matters for the design, because a
hit count larger than a given enemy's gauge still does something useful, and
because hit count and the damage ladder come out of one budget rather than two.

### 1.3 What splitting an ability's power actually costs

This section said, through v0.9, that FF6 *subtracts* the target's defence per
hit, so N hits at power `P/N` deal strictly less than one hit at power `P`.
Both halves of that are wrong, and the build pass found out by reading the
code before dividing anything.

**Defence is a multiplier, applied once per hit, and it is not a subtraction.**
There is exactly one site: `battle_main.asm:2004-2012` loads `$3bb9,y` (or
`$3bb8,y` for the magic side), turns it into `~(def-1)` and runs `MultDmg`
(`:2071-2080`, a 24-bit multiply-and-shift). A multiplier distributes over a
split: two hits each multiplied by `m` total the same as one double-sized hit
multiplied by `m`. Defence therefore costs a multi-hit ability nothing that it
does not cost a single-hit one.

**And the three split abilities skip it anyway.** The same site
opens with `lda $11a2 / bit #$20 / bne`, so the ignore-defence flag branches
past the whole block. Pummel's `MagicProp+$02` is `$21` (physical +
ignore-defence), Bum Rush's is `$20` (ignore-defence, magic damage), and Drill
gets `$20` at runtime from `ToolsEffect_05` (`battle_main.asm:7384-7386`).
All three ignore defence.

OT6's own ×0.5 shielded attenuation (`Ot6ShieldedDmg`, called from
`Ot6HitJoin`) is likewise a per-hit multiplier and likewise distributes.

What the split does cost runs the other way, and is small. FF6's physical
damage is **affine in power rather than linear**: `CalcDmg`
(`battle_main.asm:7458` onward) scales power by 1.75, then adds the hit-rate
term `$11ae` *before* the level multiply, and adds one more raw power term
after it. The hit-rate half is not divided when power is, so N hits at `P/N`
deal somewhat **more** total damage than one hit at `P`, not less. Read off
the formula rather than measured, this is the reason the splits below are
exact division with no compensation — a compensation curve would be
correcting in the wrong direction.

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
(`battle_main.asm:14959-14978`; `INIT_MASK` values at `const.inc:1298-1302`),
and a multi-target action runs `CalcTargetDmg` once per surviving target
through the loop at `battle_main.asm:8613-8621`, giving one chip per body.

AutoCrossbow is the ability that has been classified wrongly: targeting byte
`$6a` (`INIT` = one-side), `ToolsEffect_07` setting don't-split-damage
(`battle_main.asm:7407-7410`). Against a four-stack it is four chips on four
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
state, and no static tool answers it.

One reach fact is solid: Sabin's fists are bludgeoning and so is
Pummel (`ot6_class.asm:163`, `:193`), so a bare-fisted Sabin's Blitz opens no
axis his Fight does not. With claws equipped (slashing,
`ot6_class.asm:139-147`), Pummel becomes his second axis at no extra cost.
That asymmetry is part of his design.

### 2.4 Duration — hits per turn thereafter, paid once
A poison status tick chips, measured. Cmd_22
stores element `$08` itself (`battle_main.asm:13457-13458`) and tail-jumps
`ExecSelfAttack`, so a tick is an ordinary poison hit with no attacker, and it
reaches `Ot6Chip` through the weak branch at `battle_main.asm:1894-1896`.
Measured: two ticks broke a 2-shield poison-weak guard with no action spent
after the application, one chip per tick, ~1048 frames (~17.5 s of battle
time) apart. Sap does not chip, because it has no element. A broken monster receives no
ticks at all (`Ot6Gate`, `ot6_break.asm:1654-1661` → `battle_main.asm:1416-
1419` → Cmd_22's `bit #$10` at `:13434-13435`), so the break window caps
duration the same way it caps rate.

Edgar already owns this curve: Bio Blaster applies a weakness rather than
hitting an existing one. Bio Blaster (item `$a4`) is
rewritten to spell `$7d` Bio Blast by `InitTarget_03`
(`battle_main.asm:6575-6582`), with one-side targeting, POISON element,
power 20, and status1 `$04` = POISON. One cast is one poison chip on every
body plus a further chip per body per ~17 s thereafter.

---

## 3. The audit — what the shipped ROM does

`$3a70` is the only mechanism, so grepping every write to it is an
exhaustive enumeration. Twelve upward writers exist
(`audit_multihit.py` re-derives them and fails if that changes):

| writer | effect |
|---|---|
| `FightAttack` `battle_main.asm:3513` | `= 1` (two hands), `= 7` with Offering |
| `Ot6FightBoost` `ot6_boost.asm:426-427` | `+= 2` per pending BP |
| Jump + Dragon Horn `battle_main.asm:3961-3967` | `+= 1..3`, random |
| `CheckWeaponMagic` `:8936` | `+= 1` (random weapon spellcast, which is a spell rather than a swing) |
| `AttackerEffect_49` `:10613` | `+= 1` (magicite / random summon) |
| **`AttackerEffect_32`** `:10848-10850` | **`= 3` → four attacks, random target** |
| **`AttackerEffect_36`** `:11053` | **`+= 1`, at quarter power** |
| **`Ot6HitCount`** `ot6_hitcount.asm` | **`+= Ot6HitCountTbl`'s value for this ability id** (#54, v0.10) |

Vanilla authors hit counts through special effects, and scanning all 256
`MagicProp` and all 256 `ItemProp` records for those effect ids finds three
abilities in the whole game, all Cyan's:

| id | ability | hits | note |
|---|---|---|---|
| `$58` | Quadra Slam | **×4** | random target per hit |
| `$5b` | Quadra Slice | **×4** | random target per hit |
| `$59` | Empowerer | **×2** | quarter power, and it is a drain |

OT6 authors them through `Ot6HitCountTbl` instead, for the reasons in §5,
and that table has three rows:

| id | ability | extra attacks | hits |
|---|---|---|---|
| `$5d` | Pummel | 1 | **×2** |
| `$64` | Bum Rush | 3 | **×4** |
| `$a8` | Drill (tool item id) | 1 | **×2** |

**Cross-checked against the published accounts of vanilla**, since `kits.md`
once asserted Flurry ×4, Tempest ×4 and Bum Rush ×8 without a source. The
community references agree with this ROM on all three, including the one that
matters: **vanilla Bum Rush is a single hit**, a magic-damage Blitz of power
128 that ignores magic defence, not an eight-hit combo. The ×8 figure belongs
to *Phantom Rush*, the later remakes' replacement for it (seven hits at 9.25×
plus one at 11.75×), which is a different ability in a different game. So the
×8 figure was never a description of anything OT6 shipped or vanilla did;
Bum Rush ships at ×4 (§4.1).

The two Quadras check out too, and the difference between them is one this
ROM's data shows: Flurry (Quadra Slam) makes four randomly-targeted attacks
that do **not** ignore defence — `MagicProp+$02` = `$01`, physical only —
while Tempest (Quadra Slice) makes four that **do**, `+$02` = `$21`. That is
why Quadra Slice is the late-ladder one at 50 MP.

Treat the above as what it is: web accounts used as hypotheses, each
confirmed against the record bytes before it was written down.
`tools/audit_multihit.py` is the check that outlives any of those pages.

### 3.1 The three kits, as shipped

`hits` is per target. `tgt` is the targeting byte. `pow` is the byte the ROM
ships, which for the three abilities OT6 splices is the divided one, not the
`.dat`'s. `mp/chip` is the MP price divided by hits, computed single-target, so
breadth abilities read at their boss-fight value, which is the one that
matters. Every column here is printed by `tools/audit_multihit.py`, which
re-derives it from the sources on every `make test`; the tables below are a
transcription of that output and go stale if nobody re-runs it.

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
| **Pummel** | `$5d` | **2** | `$53` single | bludg | 55 | 4 | **2.0** |
| AuraBolt | `$5e` | 1 | `$53` single | holy | 68 | 10 | 10.0 |
| Suplex | `$5f` | 1 | `$7e` one-half | bludg | 180 | 13 | 13.0 |
| Fire Dance | `$60` | 1 | `$7a` one-side | fire | 42 | 17 | 17.0 |
| Mantra | `$61` | 1 | `$3e` allies | — | 1 | 16 | — |
| Air Blade | `$62` | 1 | `$7a` one-side | wind | 78 | 28 | 28.0 |
| Spiraler | `$63` | 1 | `$3e` | — | 200 | 50 | — |
| **Bum Rush** | `$64` | **4** | `$53` single | bludg | 32 | 99 | **24.8** |

**Tools** (item ids `$a3-$aa`, `ItemProp`)

| tool | id | hits | tgt | class/elem | pow | MP | mp/chip |
|---|---|---|---|---|---|---|---|
| NoiseBlaster | `$a3` | 1 | `$6a` one-side | — | 0 | 6 | — (confuse) |
| Bio Blaster | `$a4` | 1 | `$6a` one-side | **poison + status** | 20 | 8 | 8.0 + duration |
| Flash | `$a5` | 1 | `$6a` one-side | — | 42 | 6 | — (blind) |
| Chain Saw | `$a6` | 1 | `$43` single | slash | 252 | 18 | 18.0 |
| Debilitator | `$a7` | 1 | `$43` single | — | 0 | 10 | — (adds a weakness) |
| **Drill** | `$a8` | **2** | `$43` single | pierce | 96 | 16 | **8.0** |
| Air Anchor | `$a9` | 1 | `$43` single | pierce | 128 | 14 | 14.0 |
| AutoCrossbow | `$aa` | **1/body** | `$6a` one-side | pierce | 125 | 4 | 4.0 (boss) |

**Targeting-byte caveat.** The `INIT` decode above is read from
`const.inc:1298-1302` plus `ChooseTarget` (`battle_main.asm:14959-14978`), not
observed in play. Suplex's `$7e` decodes as "all monsters", which disagrees
with how Suplex is generally understood to behave. The difference is likely
the menu cursor's default versus what a player confirms, since these commands
all carry `MULTI_TARGET`. Flagged UNVERIFIED; no claim below depends on it.

### 3.2 The per-character position

Read straight off §3.1, and printed per character by `audit_multihit.py`:

| character | multi-hit | probe without spending BP |
|---|---|---|
| **Cyan** | Quadra Slam ×4, Quadra Slice ×4, Empowerer ×2 | yes, three of them |
| **Sabin** | Pummel ×2, Bum Rush ×4 | yes, from level 1 at 4 MP |
| **Edgar** | Drill ×2 | yes, once Figaro's sand dive is done |
| everyone else | **none** | one chip per action |

The three physical-kit characters have one or more multi-hit ability; eleven
have none, and rely on boosted Fight instead (§4.4).

---

## 4. The design

Principles, stated so they can be reviewed:

- **P1 — Rate belongs on a signature ability rather than a capstone.** A
  cheap, early, repeatable multi-hit is what gives a character a probing
  identity. Ultimates should be spent into an already-opened gauge rather than
  used to open it. Cleave already follows this rule, since it refuses a target
  that is not Broken, and Bum Rush should not contradict it.
- **P2 — One rate ability per kit, no more** (Cyan excepted; his three are
  vanilla).
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
| **Pummel** | **×2** bludgeoning | Fits P1: 4 MP at level 1, the earliest multi-hit in the game and his signature. Two chips per action against the 31 authored 2-shield species means Sabin breaks trash without help. Power 110 → **55** per hit (P4, straight halving). |
| **Suplex** | **×1** | P3: this is the single-hit committer. 180 power is the highest in the Blitz list and it stays one number. |
| **Bum Rush** | **×4** bludgeoning, not ×8 | ×8 breaks every authored gauge but one in a single action (shield census: 31 species at 2, 10 at 3, 4 at 4, 5 at 5, 8 at 6, 5 at 7, one at 8, one at 11), which fails both P5 and P1, because the ultimate would become the opener. ×4 empties trash and the low bosses outright and is still a capstone moment, while bosses with 5 or more shields need Sabin's own Pummel or a partner to finish. Power 128 → **32** per hit (P4): 99 MP already buys the worst damage-per-MP in the Blitz list, and dividing it makes an expensive capstone weaker still against defended targets, applied anyway because leaving it at 128 across four hits would make the ultimate both the best opener and the best nuke. |
| AuraBolt / Fire Dance / Air Blade | ×1 | Element probes, and Fire Dance/Air Blade are already breadth. Adding rate on top would make Sabin the answer to every fight, and P2 allows him one rate ability, which Pummel is. |
| Mantra / Spiraler | ×1, and the question does not arise | Neither strikes an enemy. Mantra heals the party and Spiraler is a sacrifice; a hit count on either has nothing to chip. |

Identity: the cheapest chips in the game, on one axis (two if he wears claws).
His three bludgeoning Blitzes are one of each shape — Pummel is the rate probe,
Suplex the single-hit committer, Bum Rush the capstone — so the class stays
constant while the job changes, which is P3 applied inside one axis.

### 4.2 Edgar — the machinist, three curves in one kit

| ability | count | reason |
|---|---|---|
| **AutoCrossbow** | **×1 per body**, unchanged | It is breadth (§2.2) and it is already the designed swarm answer in two of the break-coverage docs. Making it ×4 per body would be 16 chips against a four-stack. `kits.md` says "whole side, one hit per body", which is the correct reading. |
| **Drill** | **×2** piercing | The armoured-boss answer, since it ignores defence (`ToolsEffect_05`, `battle_main.asm:7384-7386`), so two chips into one gauge complements AutoCrossbow's breadth against swarms. 16 MP → 8.0 MP/chip, which prices rate above breadth. Power 191 → **96** per hit (P4; 191 halves to 95.5 and the extra point goes to the player). Drill's `$20` ignore-defence flag comes from `ToolsEffect_05` at runtime rather than from its record, which is why the audit's ItemProp columns do not show it. |
| **Bio Blaster** | ×1 per body **+ the DOT** | Duration (§2.4); the tick chip stays as it is. No hit count. |
| **Chain Saw** | ×1 | The slash committer, 252 power. P3. |
| Air Anchor / NoiseBlaster / Flash / Debilitator | ×1 | Gag, and three non-damaging utilities. |

Identity: the only character who fields all three cost curves, breadth
(AutoCrossbow), rate (Drill) and duration (Bio Blaster), and two classes
(pierce + slash) without changing weapons.

### 4.3 Cyan — the burst prober, unchanged

No data moves for Cyan. Vanilla's own counts already fit: two burst
probes at the tiers where a shield is worth opening, and single big numbers
everywhere else. Stated per tech:

| tech | count | reason |
|---|---|---|
| Dispatch `$55` | ×1 | The cheapest row of any kit at 4 MP. Its job is one reliable slash chip a turn, which is what a tier-1 signature should be. Rate here would make the rest of the ladder pointless. |
| Retort `$56` | ×1 | A counter stance rather than an action. Hit count belongs to what it counters with, and multiplying a counter's hits would pay Cyan for being attacked. |
| Slash `$57` | ×1 | Power 8; it is a status verb wearing a damage record. Nothing to divide. |
| **Quadra Slam** `$58` | **×4** | Vanilla's. 16 MP for four slash chips into one body is the best rate-per-MP in the game after Pummel, and it arrives at LV15, which is where a party first meets 4-and-5-shield bosses. |
| Empowerer `$59` | ×2 | Vanilla's, at quarter power, and it is a drain. Left as it is: the two hits are a consequence of the drain effect rather than a probing choice, and repricing a drain belongs to the MP economy. |
| Stunner `$5a` | ×1 | Already breadth: one slash chip on every body. P3 says breadth and rate should be different abilities, and Quadra Slam is the rate one. |
| **Quadra Slice** `$5b` | **×4** | Vanilla's. The late-ladder repeat of Quadra Slam at 50 MP, which prices it as burst rather than as a probe: 12.5 MP per chip against Quadra Slam's 4.0. |
| Cleave `$5c` | ×1 | It refuses a target that is not already Broken, so it never chips at all. It is the rule P1 is named after. |

Two behaviours are worth recording rather than changing:

- Quadra Slam and Quadra Slice are `AttackerEffect_32`, which sets the random
  target flag (`tsb $ba, #$40`, `battle_main.asm:10851-10852`). Against a boss
  all four hits land on the boss; against a four-stack they scatter. Quadra
  Slam is therefore strong against a single boss gauge and unreliable against
  groups, which is the opposite of AutoCrossbow. That behaviour is unintended
  in vanilla but should be kept.
- Neither Quadra gets a power split, because vanilla already priced them as
  four-hit records: 72 and 70 against Dispatch's 120 and Stunner's 97. P4 is
  satisfied without moving a byte.

Identity: four chips into one gauge, on a slash axis, at burst prices.

### 4.4 Everyone else

Thirteen characters have no multi-hit ability of their own. The rule for a
kit with a damaging physical verb is: exactly one cheap, early, repeatable
multi-hit (P1/P2). A kit whose verbs are all magical satisfies the Octopath
rule differently — through element spread plus boosted Fight — and needs no
hit count.

Every character gets +1 landed hit per BP with any weapon regardless
(`Ot6FightBoost`, §1.1, measured), so nobody is without a rate lever; Sabin,
Edgar and Cyan are simply the characters who also have one that costs no BP.

---

## 5. What was built

`$11a9` holds one byte and selects one effect. `LoadMagicProp` copies the
record's `+$09` byte and doubles it into a jump-table index
(`battle_main.asm:6961`), and `DoAttackerEffect` dispatches exactly one
routine (`:10376-10383`). Five of the abilities above already carry a special
effect (Suplex `$30`, Retort `$3c`, Stunner `$3f`, Cleave `$23`, Empowerer
`$36`), so hit counts cannot be data-authored into that slot for any ability
that has one, and reusing `AttackerEffect_32` would force ×4 plus random
targeting on everything.

So the answer is a small table rather than a special effect, and that is what
shipped, in `ff6/src/battle/ot6_hitcount.asm`:

> **`Ot6HitCountTbl`** — (ability id, extra attacks) pairs, `$ff`-terminated,
> in the same shape as `Ot6SkillClassTbl` (`ot6_class.asm:184-197`), keyed by
> attack id for Blitz and by tool item id for Tools, the way
> `Ot6WeapClassTbl` and `Ot6AbilityCostTbl` already key Tools. The two ranges
> are disjoint (`$5d-$64` vs `$a3-$aa`), so one table serves both callers.
> **`Ot6HitCount`** scans it and adds the value to `$3a70`.

### 5.1 Where the hook lives

The hook must fire once per action rather than once per swing, or it re-arms
itself indefinitely and the action never ends. `LoadMagicProp` is not a valid
site: `ExecAttack` calls `InitTarget` itself when `$3400` is `$ff`
(`battle_main.asm:8276-8282`), and `InitTarget_00`/`InitTarget_02` call
`LoadMagicProp` (`:6636`), so `LoadMagicProp` is reachable from inside the
multi-attack loop and a hook there would re-arm.

The hook is in the command handlers instead, `Cmd_0a` for Blitz
(`battle_main.asm:3438`) and `Cmd_09` for Tools (`:4014`). Those cannot be
re-entered by the loop, because the loop's `pea ExecAttack-1` returns to
`ExecAttack` and never to the handler, and `ExecCmd` clears `$3a70` through
`InitGfxScript` (`:6428`) before dispatching, so each handler sees a fresh 0
exactly once per action. That is the same site and the same argument as
`Ot6FightBoost`, which lives in `FightAttack` for the same reason.

The argument is measured rather than trusted: `tools/tests/battle_hitcount.lua`
drives a real Pummel with controller input on the Mt. Kolts fixture and
requires exactly one write of `$3a70 = 1` inside the action, followed by two
`Ot6HitJoin` passes. A re-arming hook would write 1 repeatedly and the test
would fail on the count. AuraBolt, driven through the identical `Cmd_0a` hook
in the same battle, leaves `$3a70` at 0, which is the control that separates
"the table is consulted" from "every Blitz got a hit".

There is no SwdTech hook, because no SwdTech count changes. Adding one later
means one more `jsl` in `Cmd_07` (`battle_main.asm:3977`), where `$b6` is
likewise the ability id before it is rebased.

### 5.2 The power split

P4 needs each ability's power divided by its hit count, or the pass is a
damage buff rather than a break-rate trade. This document's build list proposed
`MagicProp`'s named-override mechanism, and that is what Pummel and Bum Rush
use (`battle_main.asm`, above the `MagicProp` label). `ItemProp` had no such
mechanism, so Drill's needed one built: `ff6/src/menu/item.asm` now carries the
same splice-plus-length-assert shape, with the `.dat` still byte-identical to
the FF3us base. Both splices are pinned by position in
`tools/tests/battle_hitcount.lua`, which reads the records back out of the
built ROM, with Suplex `$5f` and Chain Saw `$a6` as the untouched controls.

The split is exact division, uncompensated, and §1.3 is why: defence is a
multiplier rather than a subtraction, it distributes over a split, and all
three of these abilities ignore it anyway. The only asymmetry runs in the
player's favour, because FF6's physical formula is affine in power, so the
divided ability keeps the undivided hit-rate term on every hit; a
compensation curve would have corrected the wrong way.

Cost: one table (24 bytes), one proc, two `jsl` shims in bank `$C2`, three
spliced data bytes. No new RAM.

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
plus `LevelUpMP`) at Zozo: Sabin 84 (L13), Edgar 87
(L13), Cyan 76 (L12). Chips per full pool, single target:

| ability | MP | chips/cast | MP per chip | casts | chips per pool |
|---|---|---|---|---|---|
| Fight | 0 | 1 | 0 | ∞ | ∞ (1 per turn) |
| Fight, 3 BP | 0 | 4 | 0 | BP-limited | ~4 per bank |
| **Pummel ×2** | 4 | 2 | **2.0** | 21 | **42** |
| Pummel ×1 (before v0.10) | 4 | 1 | 4.0 | 21 | 21 |
| AutoCrossbow (boss) | 4 | 1 | 4.0 | 21 | 21 |
| AutoCrossbow (4-stack) | 4 | 4 | 1.0 | 21 | 84 across four gauges |
| **Drill ×2** | 16 | 2 | **8.0** | 5 | **10** |
| Quadra Slam ×4 | 16 | 4 | 4.0 | 4 | 16 |
| Quadra Slice ×4 | 50 | 4 | 12.5 | 1 | 4 |
| **Bum Rush ×4** | 99 | 4 | **24.8** | 0 at L13 | — (L70 ability) |

The MP-per-chip column is the one `audit_multihit.py` prints, so it is
re-derived from the shipped tables on every `make test` rather than copied
here once. Pummel ×2 at 2.0 is now the cheapest priced chip in the game,
below AutoCrossbow's 4.0 against a boss and level with it against a
four-stack. That is the intended ordering: rate against one body is what a
boss fight needs and breadth is what a swarm needs, and the two should not
be interchangeable.

Read the chips-per-pool column against the loop rather than against the other
rows. A 42-chip pool is 21 turns, and a battle is about five turns, so at this
scale the constraint is the turn rather than the pool. That is the intended
result: multi-hit should change what one turn accomplishes rather than how
many turns a character can afford, because the number of affordable turns is
what `mp-economy.md` already tunes and it should not be tuned twice.

By the turn, the shipped kit reads:

- Sabin, one turn, 4 MP: **2 chips** on bludgeoning.
- Sabin, one turn, 0 MP + 1 BP: 2 chips on his weapon's class.
- Cyan, one turn, 16 MP + 2 BP: **4 chips** on slashing.
- Edgar, one turn, 4 MP: 1 chip per body, up to 4 bodies.
- Edgar, one turn, 16 MP: **2 chips** on piercing, through armour.

Those five lines are different jobs at clearly different prices. Pummel ×2
costs the same as one BP and buys the same thing, so it is priced at parity
with the free option, which leaves the choice open rather than automatic.

