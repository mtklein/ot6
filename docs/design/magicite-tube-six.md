# The tube-room six — magicite sub-job designs

The six espers the tube room grants at once — MADUIN, SHOAT, PHANTOM,
CARBUNKL, BISMARK and UNICORN (`give_genju` block,
`ff6/src/field/event_main.asm:95777-95782`) — are designed in place. The
all-six-at-once acquisition stays, because redistributing it would mean an
event edit plus regenerating every savestate and would gain no player-visible
pacing. §11 lists the exact data changes.

These six stones are this stretch's player-facing content, sharing one
acquisition moment with six distinct reasons to swap mid-dungeon; the goal
is differentiation between them rather than a power ranking.

**Canon boundary.** The shipped **while-equipped** model is the baseline:
equip grants the spell list live, the stat mod exists only while worn, nothing
is learned, the summon is the once-per-battle divine
(magicite-ifrit-shiva.md, "Canon boundary"). magicite.md's roster row for each
stone is treated as an identity seed. Its PASSIVE column (*Trinity*,
*Gorgon Eye*, *Ghostwalk*, *Facet*, *Tidal*, *Purity*) is unbuildable, because
no passive channel exists in the ROM, so each entry is re-expressed here
through what is buildable or recorded in §12's ledger. The seed names are kept
as each stone's documentation nickname.

---

## Summary table

A stone's stat package is two bytes in vanilla's own equipment layout: four
signed nibbles, −7..+7 each, over vigor/speed/stamina/mag.pwr. Each stone below moves two or three stats
and five of the six carry a downside; `ot6_progression.asm`'s table carries
the per-esper reasoning.

| esper (idx) | nickname | grants | stat vig/spd/stm/mag | divine (vanilla record, all kept) | the swap reason |
|---|---|---|---|---|---|
| Maduin (6) | **the Trinity** | Fire, Ice, Bolt | **−3 / 0 / +3 / +7** | **Chaos Wing** `$3c`: non-elem 55, all enemies, 44 MP | one caster, three fold families; the right element on demand |
| Shoat (5) | **the Gorgon Eye** | Break, Doom | **−2 / +6 / +2 / 0** | **Demon Eye** `$3b`: petrify all, hit 96, 45 MP | delete one body per turn, where deletion is legal |
| Phantom (20) | **the Ghostwalk** | Vanish, Demi | **0 / +6 / −2 / +2** | **Fader** `$4a`: Clear on the party, 38 MP | the party stops being hit by physicals |
| Carbunkl (19) | **the Facet** | Rflect, Safe | **0 / −2 / +6 / +2** | **Ruby Power** `$49`: Rflect on the party, 36 MP | the enemy's magic is turned back on it |
| Bismark (7) | **the Tide** | Haste, Slow | **+5 / −2 / +3 / 0** | **Sea Song** `$3d`: WATER 58, all enemies, 50 MP | tempo both ways, plus the game's only water verb |
| Unicorn (23) | **the Purity** | **Pearl** (§9), Remedy | **0 / 0 / +5 / +2** | **Heal Horn** `$4d`: Remedy on the party, 30 MP | the undead stretch's key element, and the cleanse |

The six stat packages are six different shapes: Maduin is a caster with reduced
vigor, Shoat is fast with reduced vigor, Phantom is fast with reduced stamina,
Carbunkl is durable and slow, and Bismark is strong and slow. Unicorn's package
is the smallest and the only one with no downside, because his power is in the
Pearl grant (§9).

**No summon re-author is needed.** Inferno and Diamond
Dust were a mirrored pair that had to be split apart; vanilla already authored
these six divines as six different verbs: a petrify wipe, a non-elemental
nuke, a water nuke, party-reflect, party-vanish, party-cleanse (records
`$3b/$3c/$3d/$49/$4a/$4d`, decoded §4-§9; names Demon Eye / Chaos Wing / Sea
Song / Ruby Power / Fader / Heal Horn, `genju_attack_name_en.json`). The
MagicProp splice gains no new overrides.

---

## 1. The constraint budget

magicite-ifrit-shiva.md §1 is the authority on what the machinery can express:
≤5 spell ids per stone (`ot6_progression.asm:142-181` `Ot6EsperSpellKnown`,
`:203-252` `Ot6UnionEspers`), a while-worn stat package of four *signed*
nibbles, −7..+7 each, over Vigor/Speed/Stamina/Mag.Pwr in vanilla's own
`ItemProp+16/+17` layout (`ot6_progression.asm`, `Ot6EsperStatMod`), the
once-per-battle summon on vanilla's `$3f2e` latch (`battle_main.asm:12852` sets
it, `:14550` greys the menu row), boost folding for 8 families only
(`Ot6FoldTbl`, `ot6_boost.asm:340-348`), and the ×2/×4/×8 multiplier on
non-folding damage (`Ot6BoostDmg`, `ot6_kits.asm:1190-1256`; summons are not
exempt, `:1206-1224`). No passives, no permits, no learn rates.

Two things the design depends on:

1. **The esper detail page renders the kit accurately.** There is no learn-%
   column (blanked caption `skills.asm:2528-2544`, forced blank per-row
   `:2606-2608`), and the bonus line is a **"While worn...&lt;Stat&gt;+N"**
   block drawn straight from `Ot6EsperStatTbl` (`skills.asm:2624-2673`). So an
   authored stat row is automatically player-visible, and a `$0000` row draws a
   blank line.
2. **MP is universal**: every character brings their save's pool into battle.
   A stone on Locke or Sabin has a real pool behind it; granted-spell MP prices
   below are judged against this stretch's pools of roughly 40-60.

The vanilla rows these replace are placeholders, and three of them are broken
the same way Ifrit's and Shiva's were:

- **Vanilla Maduin grants three dead pre-folded tiers**: `FIRE_2, ICE_2,
  BOLT_2`, 20-22 MP each for what the base spells deliver at 4-6 MP under one
  boost. All three go (the Kirin reason).
- **Vanilla Bismark grants Life**, which puts revival on a stone anyone can
  wear and so violates kits.md's written rule that revival "lives on Terra,
  Fenix Downs, and Sraphim, and nowhere else" (kits.md, Terra section). Dropped.
- **Vanilla Shoat grants Bio**, the pre-folded cap of the poison family
  (`Ot6FoldTbl` row 3, `ot6_boost.asm:344`): 26 MP for what a 3-MP Poison folds
  into at 1 BP. It is also poison into a stretch where four of five cave
  species **absorb** poison (§2.2), so casting it heals the enemy for 26 MP.
  Dropped.

---

## 2. Where the player is standing

### 2.1 The stretch's three parties

The stretch's route puts three different parties in front of these stones:

- **The cave: TERRA / LOCKE / EDGAR / SABIN** (owner ruling; Terra is a hard
  requirement at the base). Terra is the stretch's only innate
  mage: at these levels, around 15-16, she knows Fire, Cure, Drain (kits.md,
  Terra's table; Life is L18). Locke, Edgar and Sabin cast only through their
  stones.
- **The banquet: TERRA + LOCKE** (`event_main.asm:99079-99086`).
- **The stop line: TERRA / LOCKE / SHADOW** at world (232,150). Shadow joins
  in the stretch's final frames. His kit is a sketch (kits.md, Sketches), so a
  stone is most of what he can be given.

**Twelve stones, four slots.** By the cave the player owns Ramuh, Kirin,
Siren, Stray, Ifrit, Shiva plus these six. Every design below has to say how it
competes with the incumbents' jobs: bolt+Rasp, heal, sleep-mute control,
trickster, vigor+Drain, and economy+Shell.

### 2.2 The cave is an undead stretch where the obvious elements do not work

The cave species, with status-immunity bytes added
(`monster_prop.dat` +0x14/+0x15/+0x16 = blocked
STATUS1/2/3; element masks +0x17 absorb / +0x19 weak; STATUS1 `DEAD=$80`,
`PETRIFY=$40`, `INVISIBLE=$10`, STATUS3 `SLOW=$04`, `STOP=$10` —
`ff6/include/const.inc:1488-1525`):

| species | id | HP | MP | weak | absorb | death | petrify | slow | stop |
|---|---|---|---|---|---|---|---|---|---|
| Apparite | `$06e` | 781 | 60 | ice, **pearl** | fire, poison | **open** | blocked | blocked | blocked |
| Lich | `$0e5` | 590 | 90 | **pearl** | fire, poison | **open** | blocked | blocked | blocked |
| Ing | `$048` | 1100 | 50 | **pearl**, water | fire, poison | **open** | blocked | **lands** | **lands** |
| Zombone | `$082` | 1991 | 160 | fire, **pearl** | poison | **open** | blocked | **lands** | **lands** |
| Coelecite | `$0b3` | 480 | 15 | ice | fire | **open** | **open** | **lands** | **lands** |

Plus the stretch's one real ambush, the trap-switch **Ninja** `$003` (HP 1650,
weak bolt+pearl, absorbs poison; death open, petrify/slow/stop blocked), and
the banquet slate: **Mega Armor** `$102` / **Commando** `$0c7` (both weak
bolt+water, death open, slow/stop land) and the elite **Sp Forces** `$0c2`
(weak poison; death, petrify, slow and stop all blocked, so it is the one body
in the stretch that answers only to damage).

Four findings that shape the designs:

1. **Pearl/holy is the key element here**: 4 of 5 cave species are pearl-weak,
   and the party has almost no access to it. The one current source is Sabin's
   AuraBolt (record `$5e` element `$20`; classless by design, "aurabolt is a
   holy chip, not a punch", `ot6_class.asm:172`), a 5-MP blitz on one character.
   §9 makes Unicorn the second source; that is the cross-doc
   coupling with the parallel cave-survey pass.
2. **Fire is absorbed by 4 of 5 species** and Terra is forced into the party,
   so the stretch inverts her signature element the way Zozo inverted poison.
   Ice is the natural secondary (Apparite, Coelecite); water reaches Ing.
3. **Death is open on every cave species** by the immunity byte, so the cave is
   open to Doom on that reading. Whether the undead special-property flag
   (+0x12 bit `$80`, set on Apparite/Lich/Ing/Zombone) alters death-type
   resolution in C2 before the immunity byte is consulted is what Shoat's
   design (§5) depends on.
4. **Enemy MP pools are small** (15-160), so Osmose income in this stretch is
   low and Shiva does not automatically hold a slot the way she did in the
   Facility. That leaves room for the new six.

### 2.3 The rest of the stretch's fights

The gate battles 121/122 and the deck battle 123 decode to dummy formations
and are scripted set pieces rather than real fights, so no stone is
designed against them.
The banquet's optional fights and the 2-minute challenge are real: bolt+water
keys (Ramuh, Maduin, Sea Song) and a poison key nobody fields with Edgar
absent (Sp Forces resist all six stones' control, so they are a damage check,
which Maduin or a boosted divine answers).

---

## 3. The design call

> **Each of the six stones does one job: casting, execution, concealment,
> reflection, tempo, and status cleansing.**

The tube room hands over six stones in one scene, so the differences must
be visible on the equip screen and testable in the next corridor. Each stone
gets exactly one battlefield job, no stone's job overlaps an incumbent's, and
each is built from its magicite.md identity seed with the unbuildable passive
re-expressed through the three real channels (list, stat, divine):

| seed (unbuildable passive) | re-expression |
|---|---|
| Maduin *Trinity* — "first spell each battle +1 tier" | the only stone granting **all three** foldable attack elements; the biggest mag.pwr in the game |
| Shoat *Gorgon Eye* — "Break may chip 2" | the two deletion verbs (Break/Doom) plus the petrify-all divine |
| Phantom *Ghostwalk* — "first hit taken each battle misses" | **Fader is the same effect applied to the whole party**, so the divine covers the passive |
| Carbunkl *Facet* — "Runic feeds +1 more BP" | undeliverable (Celes is absent for the whole stretch, §12); the stone keeps the gem's real verb: reflection, single and party-wide |
| Bismark *Tidal* — "water chip +1" | no water spell exists to grant (§12); **Sea Song is the game's only water verb**, and the kit becomes tempo: Haste/Slow |
| Unicorn *Purity* — "status durations halved" | cure-after-the-fact instead of shortening: Remedy in the kit, party-Remedy as the divine, plus Pearl (§9) |

Stat tiers: FIELD (upside +6 across 2 stats, no downside), STORY
(+8 across 3, downside −2) and BOSS (+10 across 3, downside −3), measured
against the bonuses vanilla's own equipment gives. The tube six are
story-granted rather than fought for, so they sit on **STORY**, with one
deliberate exception: **Maduin on BOSS**. This stretch has no boss, Maduin
is Terra's inheritance, and his stone carrying the strongest stat package
in the game so far is the reward the stretch pays.

---

## 4. Maduin — **the Trinity**

> *Menu line:* **MADUIN** — *Terra's father. The whole storm in one stone.*

| channel | value |
|---|---|
| Grants | **Fire**, **Ice**, **Bolt** |
| Stat (while worn) | **vig −3 / stm +3 / mag +7** |
| Divine | **Chaos Wing** `$3c` — non-elemental, all enemies, power 55, 44 MP, unblockable (+0x04 `$20`, hit 0). Vanilla, unchanged. |

**The kit is three fold families on one stone.** Fire `$00` (4 MP), Ice `$01`
(5 MP), Bolt `$02` (6 MP), and every one folds to its tier-3 at 2 BP for base
price (`Ot6FoldTbl` rows 0-2, `ot6_boost.asm:341-343`). The Ifrit/Shiva pass
established that one base-tier elemental grant is worth ~10× its price to a
boosting caster; Maduin carries three of them. He grants no utility, no economy
and no defense; he is the pure caster job, and
his empty fourth and fifth slots serve the same purpose as Ifrit's.

**Against the incumbents.** Ifrit, Shiva and Ramuh each carry one of these
elements plus a job (Drain / Osmose+Shell / Rasp). Maduin offers
breadth: the wearer is never on the wrong element for more than one turn. In the
cave that means casting ice at Apparite and Coelecite and holding fire back,
which restates the stretch's absorb lesson on the stone that grants fire.
At the banquet fights it means bolt into Mega Armor and
Commando without carrying Ramuh out of the cave.

**Stat.** +7 mag.pwr, one step over Shiva's +6. It is the strongest stat stone
in the game (§3), and +7 is both the encoding's maximum and
vanilla's own per-stat maximum. Base mag.pwr 25-39 (`char_prop.asm`). All three
of his grants scale off it, and the −3 vigor marks him as a caster rather than
a fighter.

**Divine.** Chaos Wing is kept unchanged: non-elemental, so it is never
absorbed. It is the apex action that works in the fire-hostile cave and against
Sp Forces, and the damage-check answer the stretch otherwise lacks.
`Ot6BoostDmg` multiplies it (summons are not exempt, `ot6_kits.asm:1206-1224`),
so a 3-BP Chaos Wing is the stretch's biggest number. Its 44 MP is most of a
pool at these levels, so it is one cast per battle by design.

**Trinity, the passive, is dropped** (§12.1) because there is no passive
channel. The first-cast-free-tier idea was flagged "too strong a folding
interaction?" in magicite.md's own open questions; the fold engine already gives
the tiering, so what is lost is flavour rather than function.

---

## 5. Shoat — **the Gorgon Eye**

> *Menu line:* **SHOAT** — *The stone that stares back. One look, one corpse.*

| channel | value |
|---|---|
| Grants | **Break**, **Doom** |
| Stat (while worn) | **vig −2 / spd +6 / stm +2** |
| Divine | **Demon Eye** `$3b` — petrify, all enemies, hit 96, blockable death-class (+0x04 `$10`), 45 MP. Vanilla, unchanged. |

**The executioner's two verbs.** Break `$0c` (25 MP, hit 120, sets PETRIFY)
and Doom `$0d` (35 MP, hit 95, sets DEAD): both power 0, both hit-rolled,
both death-class (+0x04 `$10`). This is the stone for deleting one dangerous
body instead of wearing it down, which bypasses the shield math. The break
loop is chip, break, nuke; Shoat skips all three when the hit roll and
the immunity byte allow it. The immunity byte is what makes him a
swap choice rather than a general answer, and §2.2's table says where he works.
Bio is dropped (§1); two spells is the Ramuh/Ifrit precedent, and the third
slot is deliberately the divine.

**In this stretch.** Petrify is blocked by 4 of 5 cave species, the Ninja, Mega
Armor and Commando, but **death is open on every one of them except Sp
Forces**. If the undead-flag question (§2.2 finding 3) resolves that death-type
lands, Shoat is strong in the cave: 35 MP deletes a 1991-HP Zombone
that would otherwise be the longest trash fight in the stretch. If it resolves
that undead resist death, his cave value drops to Coelecite (petrifiable)
and the Ninja. **The design accepts either outcome**, since being
situational is his identity.

**Boost does nothing for Break or Doom.** This is a canon gap rather than a
Shoat-specific problem (§12.4). They deal no damage (`Ot6BoostDmg` multiplies
`$11b0`, which stays 0) and fold nowhere. DESIGN.md's canon says chance verbs
answer to BP-buys-certainty, which is Steal's shipped shape, but no such
mechanism exists for hit-rolled magic. Shoat is the first stone whose whole kit
sits outside both boost axes, and the UI will let a player spend 3 BP on Doom
for no effect.

**Stat.** +6 speed, −2 vigor, +2 stamina. His spells scale off nothing (fixed
hit rates vs target m.block), so the natural bonus is speed, letting him act
before the telegraph lands. The vigor downside matches the fiction: the Gorgon
Eye is a stare rather than a strike.

**Divine.** Demon Eye is kept: petrify on all enemies at hit 96. It wipes trash
where petrify is legal and misses everywhere §2.2 marks petrify blocked. 45 MP
prices it as a fight-ender. The kit and the divine overlap as single-target to
all-target scaling (Break → Demon Eye), the same shape as Phantom's
Vanish → Fader, and that is accepted in both places because the all-target
version is the once-per-battle apex of the same effect rather than a second
copy of it.

---

## 6. Phantom — **the Ghostwalk**

> *Menu line:* **PHANTOM** — *What the tubes could not hold. Be nowhere.*

| channel | value |
|---|---|
| Grants | **Vanish**, **Demi** |
| Stat (while worn) | **spd +6 / stm −2 / mag +2** |
| Divine | **Fader** `$4a` — Clear (INVISIBLE) on the whole party, 38 MP. Vanilla, unchanged. |

**The divine covers the unbuildable passive.** magicite.md's *Ghostwalk*
("first hit taken each battle misses") has no passive channel, but Fader
applies the same effect to the whole party once per battle: everyone is
untargetable by physical attacks until magic hits them. No re-author is needed;
the vanilla record already does it.

**The kit.** Vanish `$26` (18 MP, sets INVISIBLE, single target) works in both
directions: on an ally it guarantees one physical dodge, and on an enemy
(targeting `$01` retargets in vanilla) it sets up the Vanish+Doom combination
described below. Demi `$10` (33 MP, gravity: fraction flag +0x04
`$80`) halves a large HP pool the party cannot kill yet.
Against Zombone's 1991 HP it is the stretch's best single action if the
death-class miss check (+0x04 `$10` rides Demi too) passes the same
undead-flag question as Doom. Bserk is dropped from the vanilla row for the
recorded Ifrit reason: it removes player control (`genju_prop.asm:97-98`).

**The Vanish+Doom interaction.** Phantom grants Vanish and Shoat grants
Doom. Vanilla's Clear status forces magic to bypass its hit roll, which in
vanilla lets death-class spells ignore protection. DESIGN.md's house rule is
"vanilla's bugs stay", which is why the Sketch bug is kept; this combination
costs two esper slots, two characters' turns and 53 MP, which is a real
price, and it is preserved under the same house rule.

**Stat.** +6 speed, −2 stamina, +2 mag.pwr: the roster seed's selector at the
STORY tier, with lower stamina as the cost of the speed.
The wearer acts early; on Locke that fits the thief kit, and the stone is the
hand-off to Shadow at the stop line. **Phantom is Shadow's stone**
(kits.md sketches him as the assassin, and this stone makes him playable the
frame he joins).

**Swap reason.** Wear Phantom when the enemy's threat is physical (Fader
blanks it) or when one body has too much HP to race (Demi). In the cave the
undead have MP and presumably spells, and magic ignores Clear, so Fader is not
a general answer there. That keeps Carbunkl's job separate from Phantom's.

---

## 7. Carbunkl — **the Facet**

> *Menu line:* **CARBUNKL** — *The little gem. What is cast at you is yours.*

| channel | value |
|---|---|
| Grants | **Rflect**, **Safe** |
| Stat (while worn) | **spd −2 / stm +6 / mag +2** |
| Divine | **Ruby Power** `$49` — Reflect on the whole party, 36 MP. Vanilla, unchanged. |

**The mirror stone.** Rflect `$24` (22 MP, single) and Safe `$1c` (12 MP,
single) are the two mitigation spells nobody else grants. Shiva grants Shell,
which reduces magic damage that still lands; Carbunkl grants Reflect, which
turns magic around, and Safe, the physical mitigation, unclaimed because Celes
and Golem are both absent from the
stretch. The vanilla row's extra spells (Haste/Shell/Warp beside them,
`genju_prop.asm:172`) are trimmed to the two that are the job: Haste
moves to Bismark, where it is part of that stone's identity; Shell
stays Shiva's; Warp is a field spell.

**Facet, the seed passive, cannot be delivered this stretch and is dropped**
(§12.3): "Runic feeds +1 more BP" needs Celes, who is an NPC from
the banquet to past the stop line. When she returns, the pairing is
something a player can find on their own, since Carbunkl plus Runic is already
good without a passive.

**Swap reason.** The cave undead carry real MP (Lich 90, Zombone 160) and the
stretch's set pieces telegraph magic; Ruby Power cast before a telegraph
reflects the enemy's largest attack back at them. The cost is vanilla's own
behaviour: a reflected party also bounces friendly magic, so Kirin's Cure aimed
at a Ruby-Powered ally lands on the enemy. That interaction (the Carbunkl
wearer and the Kirin wearer having to coordinate turns) is the party puzzle
working as designed. Whether the cave species cast reflectable spells decides
how much of Carbunkl's cave value comes from Ruby Power specifically; his
Safe grant and the divine keep him useful either way.

**Stat.** +6 stamina, −2 speed, +2 mag.pwr: the roster seed's selector at the
STORY tier, raising endurance and reducing speed.

---

## 8. Bismark — **the Tide**

> *Menu line:* **BISMARK** — *The sea remembers its own pace. So will you.*

| channel | value |
|---|---|
| Grants | **Haste**, **Slow** |
| Stat (while worn) | **vig +5 / spd −2 / stm +3** |
| Divine | **Sea Song** `$3d` — WATER (element `$80`), all enemies, power 58, 50 MP, unblockable. Vanilla, unchanged. |

**The kit is tempo in both directions, and both spells fold.** Haste `$1f`
(10 MP) folds to Haste2, which is party-wide, at 1 BP (`Ot6FoldTbl` row 7,
`ot6_boost.asm:348`); Slow `$19` (5 MP) folds to Slow 2, which is all enemies,
at 1 BP (row 6, `:347`). One wearer spending 15 MP and 2 BP changes the action
economy on both sides. Party-wide haste for 10 MP (vanilla
Haste2 costs 38) is this stone's version of the 10×-value fold engine.

**Water is only expressible on the divine.** magicite.md's open question 2 asks
whether Bismark grants the game's only Water spell. The machinery answers it:
there is **no water-element record in the player-magic range** to
grant (scanned `magic_prop_en.dat` records `$00-$35`, +0x01 bit `$80`: none),
and the grant channel cannot create new spells (§12.5). Sea Song is the
only water verb the party can field in this era, which makes Bismark's
divine unique in kind as well as in size: Ing in the cave, and Mega Armor and
Commando at the banquet, are all water-weak, and boost multiplies it. Tidal,
the chip passive, goes into the ledger; the water identity stays on the divine.

**Life is removed** from the vanilla row, restoring kits.md's revival rule
(§1). Fire/Ice/Bolt are removed as Maduin's job.

**The Slow collision.** Siren also grants Slow
(`genju_prop.asm:119`), and Shiva's Diamond Dust carries a Slow rider. The
differentiation is real, since Bismark folds Slow to all-enemies at 1 BP and
pairs it with Haste while Siren's is one of three single-target control
spells.

**Stat.** +5 vigor, +3 stamina, −2 speed: high mass and low speed.
On the cave party it gives Edgar, Sabin or Locke a second body stone, so Ifrit
is not the only vigor answer. In the cave, where slow is blocked by Apparite
and Lich and the undead absorb the obvious elements, vigor on the class axis is
his minimum value, the same argument that applied to Ifrit in the Facility.

**Swap reason.** Wear Bismark when the fight is about turns: haste the party
into a telegraph window, slow what survives, and hold Sea Song for
water-weak bodies. No other stone in the roster does tempo.

---

## 9. Unicorn — **the Purity** — and the holy coupling

> *Menu line:* **UNICORN** — *The horn answers what should not be walking.*

| channel | value |
|---|---|
| Grants | **Pearl**, **Remedy** |
| Stat (while worn) | **stm +5 / mag +2** |
| Divine | **Heal Horn** `$4d` — Remedy's full status-clear set on the whole party (status bytes `45/e8/14`, identical to record `$33`; cleanse flag +0x04 `$04`), 30 MP. Vanilla, unchanged. |

**The kit is damage plus cleanse.** Remedy `$33` (15 MP, single-target full
cleanse) re-expresses *Purity* as cure-after-the-fact instead of
duration-halving, and Heal Horn scales it party-wide as the divine. Pearl
`$0e` (40 MP, holy, power 108) is the stretch's key element
(§2.2: pearl-weak on 4 of 5 cave species and the Ninja) on the stone whose
fiction is that the undead do not get to keep walking. Cure 2 (dead
pre-folded tier, the Kirin reason), Dispel, Safe (→ Carbunkl) and Shell
(Shiva's) all drop from the vanilla five-row.

**Pearl is on Unicorn for identity; the cave's pearl reachability does not
depend on it.** The stretch's pearl
key is Sabin's AuraBolt, a 5 MP holy chip the party has had since Vargas
(`ot6_class.asm:172`, record `$5e` elem `$20`), plus the authored
`Ot6ShieldTbl` class rows for the cave species; pearl keys 90.6 % of cave
draws with zero absorbers, and none of that runs through this stone. What
Unicorn adds is the
holy damage and the big-hit option: power 108 one-shots this stretch's trash
on-weakness, it takes `Ot6BoostDmg`'s ×2/×4/×8 as a non-folding damage
spell, and it gives a
while-worn copy of Pearl fifteen levels before Terra learns it at L30 (kits.md).
The vanilla 40 MP, a whole pool at these levels, limits it to roughly one
cast a fight, and it is not repriced because the vanilla price already does the
work needed here. A second source of a key that one party member already
carries in a five-slot Blitz list adds depth.

**Why Unicorn and not Carbunkl carries holy.** The horn fits the
holy image, and Carbunkl's identity as reflection is complete without it.
Putting Pearl on Carbunkl would make one stone both the mitigation and the
damage while Unicorn was left with two utility spells, which works against
having six distinct reasons to swap.

**Stat.** +5 stamina, +2 mag.pwr: the protector's selector, and the only
package of the six with no downside. His power is in his kit, so his stat
package is not also the largest.

**Swap reason.** The cave: Pearl into anything, Remedy/Heal Horn
against the zombie/poison riders undead stretches carry.
The banquet and voyage: the two- and three-person parties have no Kirin slot
to spare, and Unicorn is the healer-adjacent stone that also swings.

---

## 10. Balance

### 10.1 The slot fight, segment by segment

Six stones granted together, each with a reason to be worn at some point in
the stretch.

| segment | party | the four slots' strongest claims | the six's entry points |
|---|---|---|---|
| cave (382-386) | Terra, Locke, Edgar, Sabin | Kirin (undead chip damage is constant), Maduin (ice + the crown stat), Unicorn (the key), one of Bismark/Carbunkl/Shoat by threat | Maduin and Unicorn near-locks; Bismark for tempo+Sea Song (Ing), Shoat if Doom lands, Carbunkl if the undead cast, Phantom vs the Ninja ambush and Zombone (Demi) |
| banquet fights | Terra + Locke | two slots only: Maduin (bolt into Mega Armor/Commando; Chaos Wing for Sp Forces) + Bismark (Sea Song covers both water-weak bodies; Haste inside the 2-minute timer) | Shoat: death is open on Mega Armor/Commando — one-cast solutions to the +5 score fights |
| voyage / stop line | Terra, Locke, Shadow | free choice, no fights in this segment; the segment is where **Phantom goes to Shadow** | the loadout at this segment's end is the player's first three-stone build choice |

The failure mode to watch is **Maduin + Unicorn becoming the only answer** in
the cave, since between them they carry the largest stat package and the key
element. If that happens, adjust Maduin's stat magnitude rather than his list,
and Pearl's presence rather than its price.

### 10.2 What each incumbent keeps

Ramuh keeps bolt+Rasp (and is skippable within the stretch, since Maduin covers
bolt; Ramuh's era was Zozo/Vector). Kirin keeps the only
sustained heal. Shiva keeps Shell and the only MP income, which is low in this
stretch (§2.2.4). Ifrit keeps Drain and shares vigor with Bismark. Siren and
Stray keep their control kits, with the Slow collision noted above (§8). No
new stone strictly contains an old one.

---

## 11. The data

There is no new battle code and no MagicProp overrides. Two files change.

**`ff6/src/menu/genju_prop.asm`** — rows 5, 6, 7, 19, 20, 23:

```
; 5: shoat -- "the Gorgon Eye".  The executioner: Break + Doom, the two
;   deletion verbs.  BIO is DROPPED: it is the pre-folded CAP of the poison
;   family (Ot6FoldTbl row 3 -- a 26 MP dead tier beside a 3 MP fold) and
;   poison is Edgar's authored key.  Both spells are power-0 hit-rolled
;   death-class: outside BOTH boost axes (no damage to multiply, no fold
;   row, and no chance-verb certainty mechanism exists for magic).
make_genju_prop {BREAK, 0}, {DOOM, 0}, {}, {}, {}

; 6: maduin -- "the Trinity".  Terra's inheritance: the pure mage job.  ALL
;   THREE grants are base tiers of fold families (Ot6FoldTbl rows 0-2); the
;   vanilla FIRE_2/ICE_2/BOLT_2 row was three dead pre-folded tiers at once.
make_genju_prop {FIRE, 0}, {ICE, 0}, {BOLT, 0}, {}, {}

; 7: bismark -- "the Tide".  The tempo mage: Haste and Slow BOTH fold
;   party-/field-wide at 1 BP (Ot6FoldTbl rows 6-7).  Water lives in his
;   summon (Sea Song, the game's only water verb) because no water-element
;   player spell exists to grant.  LIFE is DROPPED: revival lives on Terra,
;   Fenix Downs and Sraphim only (kits.md).  FIRE/ICE/BOLT dropped:
;   Maduin's job.
make_genju_prop {HASTE, 0}, {SLOW, 0}, {}, {}, {}

; 19: carbunkl -- "the Facet".  The mirror: Rflect (nobody else grants it)
;   + Safe (the physical wall -- Celes and Golem are both absent).  HASTE
;   moved to Bismark (identity, not fifth wheel); SHELL stays Shiva's;
;   WARP is field furniture, dropped.
make_genju_prop {RFLECT, 0}, {SAFE, 0}, {}, {}, {}

; 20: phantom -- "the Ghostwalk".  The assassin's second: Vanish (both
;   directions -- the dodge, and the old trick) + Demi (halve what you
;   cannot yet kill).  BSERK dropped: removes player control.  The divine,
;   Fader, IS the unbuildable Ghostwalk passive made party-wide.
make_genju_prop {VANISH, 0}, {DEMI, 0}, {}, {}, {}

; 23: unicorn -- "the Purity".  The paladin: smite + cleanse.  PEARL is
;   the paladin identity and the big-hit option; the cave's pearl
;   reachability stands on Sabin's AuraBolt plus the authored
;   Ot6ShieldTbl class rows, never on this stone.  CURE_2 dropped
;   (dead pre-folded tier); SAFE -> Carbunkl; SHELL stays Shiva's.
make_genju_prop {PEARL, 0}, {REMEDY, 0}, {}, {}, {}
```

**`ff6/src/battle/ot6_progression.asm`**, `Ot6EsperStatTbl` — six rows in
vanilla's four-signed-nibble equipment layout, vigor/speed/stamina/mag.pwr:

```
        esper_stat   -2,  +6,  +2,   0   ;  5 shoat
        esper_stat   -3,   0,  +3,  +7   ;  6 maduin
        esper_stat   +5,  -2,  +3,   0   ;  7 bismark
        esper_stat    0,  -2,  +6,  +2   ; 19 carbunkl
        esper_stat    0,  +6,  -2,  +2   ; 20 phantom
        esper_stat    0,   0,  +5,  +2   ; 23 unicorn
```

Bismark is the second vigor stone, so Ifrit no longer owns that stat alone.

**Unchanged, explicitly:** all six summon records `$3b/$3c/$3d/$49/$4a/$4d`
(the MagicProp splice gains nothing); every learn-rate byte (stays 0); every
`GENJU_BONUS` byte (stays `$ff`); `Ot6FoldTbl`; the `$3f2e` summon latch and
the `$3ecb` kit-divine latch stay separate (the Ifrit §4.4 ruling applies:
fusing them would penalise wearing a stone).

**Menu copy: no work required.** The detail page renders granted spell
names and the while-worn stat mod directly from these two tables
(`skills.asm`); authoring the bytes above is the whole player-facing job.

---

## 12. What the shipped machinery cannot express

This is the full ledger. Of the Ifrit/Shiva §12 list, HP/MP-percentage mods
still cannot be expressed; two-sided and multi-stat mods now can (§1). New or
newly-instantiated items:

1. **Maduin's *Trinity*** ("first spell each battle +1 tier") — no passive
   channel, and no per-battle-first-cast hook exists anywhere. Dropped;
   the fold engine carries the tiering fantasy.
2. **Shoat's *Gorgon Eye*** ("Break may chip 2") — no passive channel, and
   Break could not chip regardless: chip requires a damaging hit (DESIGN.md,
   Break system) and Break deals none. Dropped.
3. **Carbunkl's *Facet*** ("Runic feeds +1 more BP") — no passive channel,
   and its beneficiary is absent for the whole stretch. Dropped.
4. **BP-buys-certainty for hit-rolled magic.** DESIGN.md's chance-verb canon
   is implemented only for Steal (command-specific). Break, Doom and Vanish,
   which are Shoat's and Phantom's whole lists, sit outside both boost axes,
   and the UI accepts a 3-BP spend that does nothing.
5. **A water spell in a kit** (Bismark's *Tidal*). Structural: no
   water-element record exists in the player-magic range (`magic_prop_en.dat`
   `$00-$35` scanned, +0x01 bit `$80`: none), and the grant channel cannot
   create records. Water is expressible only at divine cadence (Sea Song),
   unless a vanilla record is deliberately re-authored to water, which
   would be a global spell change of the Osmose-exception class.
6. **Unicorn's *Purity*** ("status durations halved") — no passive channel,
   no duration model to halve. Re-expressed as cure-after-the-fact.
7. **Per-battle-count or condition-gated summons** — Demon Eye at "twice per
   battle" cannot be expressed.
