# Ifrit & Shiva — magicite sub-job designs

Scope: the two magicite the Magitek Research Facility pays out.

**Canon boundary.** The **while-equipped** spell/stat model is the baseline:
equip grants the spell list live, the stat mod exists only
while the stone is worn, nothing is learned, the summon is the once-per-battle
divine. The proposed *learned-passive* system (magicite.md) is not assumed
anywhere below. Neither esper carries a named passive, because the passive
channel does not exist in the ROM (see §12).

**The three overridden `.dat` bytes are an assembly splice.**
`magic_prop_en.dat` is byte-identical to the FF3us 1.0 base;
`MagicProp` is four `.incbin` runs with three named `.byte` overrides between
them, each carrying the vanilla value it replaces and the argument for
replacing it, and a `.assert` that the pieces still reassemble to 3584 bytes. A
byte changed inside the blob would be invisible in a diff and unattributable in
review. The Osmose reprice is an explicit exception to a house rule (§12),
so it needs to be visible in review.

---

## 1. The constraint budget: what the shipped machinery can express

| Channel | Shipped? | Shape | Evidence |
|---|---|---|---|
| Spell grant | ✅ | **≤ 5 spell ids** per esper, from the vanilla esper record | `ot6_progression.asm:142-181` (`Ot6EsperSpellKnown`, scans `GenjuProp+1,+3,+5,+7,+9`) and `:203-252` (`Ot6UnionEspers`, seeds the union so a spell nobody knows still gets a list slot) |
| Stat mod | ✅ | up to **four** stats, **signed**, −7..+7 each, in vanilla's own equipment layout | `ot6_progression.asm` `Ot6EsperStatMod` + `Ot6EsperStatTbl`: two bytes per esper, `byte0 = [speed:4][vigor:4]`, `byte1 = [magpwr:4][stamina:4]`, each nibble `[sign:1][mag:3]`; `$0000` = no mod. Mirrors `CalcEquipEffect`, `battle_main.asm:2521-2539`. Baseline: `esper-stat-baseline.md` |
| Summon | ✅ (vanilla) | one attack record per esper, `id = esper + $36`; once per battle **per character** | `FixPlayerAttack` sets the character's bit in `$3f2e` (`battle_main.asm:12739-12747`); the Magic menu's esper row is disabled when that bit is set (`battle_main.asm:14436-14439`) |
| Boost-tier folding | ✅ | **8 families only**: fire, ice, bolt, poison→bio, cure, life, slow, haste | `Ot6FoldTbl`, `ot6_boost.asm:340-348`; scanned with a hard `cpx #$0018` bound at `:255`, `:317` |
| Boost on non-folding actions | ✅ | ×2/×4/×8 on base damage; exempted commands are fight `$00`, capture `$06`, bushido `$07`, steal `$05` — **summons (`$19`) are not exempt** | `Ot6BoostDmg`, `ot6_kits.asm:1190-1256` |
| Ability MP cost | ✅ live | Magic prices on the vanilla baseline (`GetMPCost`); `Ot6AbilityCostTbl` only keys blitz/bushido/tool ids | `ot6_boost.asm:352-400` (`Ot6AbilityCost` header); mp-economy.md "Where it lands" |
| **Weapon permit** | ❌ **not built** | no equip-side consumer exists | `ot6_class.asm:17` names equip permits as a *future* consumer; nothing reads a permit anywhere in `ff6/src` |
| **Named passives** | ❌ **not built** | no passive pool, no slots, no learning meter | ROADMAP M4 lists "Passives unlock at 2/4/6/8" as ⬜ |
| **Esper menu copy** | ✅ | the while-equipped stat block is drawn from `Ot6EsperStatTbl`; the detail screen blanks the vanilla learn-% field for a granted spell | `skills.asm:2570-2645`, `:3266-3289` — `GenjuProp` learn-rate bytes are all zeroed |

**Two consequences that shape everything below.**

1. **A magicite's identity has to live in its spell list, its stat package, and
   its summon.** There is no passive channel and no permit channel.
2. **Boost folding + the live MP economy make base-tier elemental grants the
   most efficient actions in the game.** `Ot6QueueFold` runs *after* `GetMPCost`
   has already banked the **base** spell's MP (`ot6_boost.asm:211-215` header;
   mp-economy.md, "BP buys tempo. MP buys power."). So:

   | granted spell | MP charged | at 2 BP casts as | vanilla MP of that tier |
   |---|---|---|---|
   | Fire (`$00`) | **4** | Fire 3 (`$09`, power 121) | 51 |
   | Ice (`$01`) | **5** | Ice 3 (`$0a`, power 122) | 52 |

   (MP and power read from `magic_prop_en.dat`, 14-byte records, +0x05 / +0x06.)
   A base-tier elemental grant is therefore worth roughly ten times its price
   to a boosting caster. That is the intended behaviour, and it is why
   neither esper below carries a tier-2 spell: a pre-folded tier "would
   otherwise sit as an un-foldable dead tier beside the foldable" base spell
   (`genju_prop.asm:130-137`), costing 20/21 MP for what the base spell
   delivers at 4/5 MP under one boost.

---

## 2. Where the player is standing

### 2.1 The party

The Facility party is **Locke, Celes + two** for Ifrit & Shiva and Number 024,
and the same fixed four for Number 128 and the Cranes —
`bosses-wob.md` §13–16. The roster the two new stones compete inside is Locke
(pierce, thief), Celes (slash, ice + Runic), and two of {Edgar, Sabin, Cyan,
Gau, Setzer}. Terra is not in this dungeon.

What that party already brings:

| need | who covers it today |
|---|---|
| ice | **Celes**, innate at join (kits.md, vanilla natural magic) |
| fire | **Sabin**'s Fire Dance (blitz #4, L15, 9 MP — kits.md); **Siren** currently grants base Fire as a leftover vanilla row (`genju_prop.asm:95-96`) |
| bolt | **Ramuh** (Bolt + Rasp, `genju_prop.asm:82-83`) |
| heal | **Kirin** (Cure/Regen/Antdot/Scan, `genju_prop.asm:138`) |
| pierce chip | Locke, Edgar (AutoCrossbow, whole side) |
| slash chip | Celes, Cyan (Quadra Slam ×4), Sabin-with-claws |
| **MP sustain** | **nobody** |
| **magic mitigation** | **nobody** (Celes's Safe is L22 and is physical mitigation) |

Six magicite exist by the end of the Facility (Ramuh, Kirin, Siren, Stray,
Ifrit, Shiva) for four party slots.

### 2.2 The dungeon is hostile to both of their elements

Decoded from `monster_prop.dat` (32-byte records; +0x17 absorb, +0x18 null,
+0x19 weak; element mask $01 fire / $02 ice / $04 bolt / $08 poison / $10 wind /
$20 holy / $40 earth / $80 water):

| body | id | weak | absorb | null |
|---|---|---|---|---|
| Shiva | `$108` | fire | **ice** | $fc (everything but fire/ice) |
| Ifrit | `$109` | ice | **fire** | $fc |
| Number 024 | `$10a` | — | — | — |
| Number 128 | `$10b` | — | **ice** | — |
| Blades | `$13f/$140` | — | **ice** | — |
| Left Crane | `$10d` | water | **bolt** | — |
| Right Crane | `$10e` | water, bolt | **fire** | — |

**After the fight that grants them, neither fire nor ice is the right element
against any remaining Facility boss.** Ice is absorbed by Number 128 and both
blades; fire is absorbed by the Right Crane. Number 024 has no vanilla element
weakness at all and re-hides its row (`bosses-wob.md` §14). Water is the
Cranes' key and nobody in the WoB casts it (DESIGN.md: water has no base
spell; Mog's Water Rondo is missable). Ramuh's bolt is a real key on the
Right Crane only, and the Left Crane absorbs it.

The trash is similar: §2.5 finds exactly one fire-weak species in the whole
Facility and no ice-weak species.

**So neither esper is designed as a fire button or an ice button.** A reward
whose headline effect is useless for the remaining four boss fights of the
dungeon that granted it is a bad reward. Both kits carry
**element-independent value that works inside the Facility**, and their element
is what the player carries out of the dungeon.

### 2.3 Boss shield/class rows (already authored)

`Ot6ShieldTbl`, `ot6_hud.asm:1542-1557`: Ifrit 6·pierce, Shiva 6·slash, Number
024 7·slash|pierce, Number 128 7·pierce, both Cranes 6·pierce. Every Facility
boss is **class-breakable by the party's existing weapons**: Locke pierces and
Celes slashes. The class axis is the reliable axis in this dungeon, so
**anything that makes ordinary weapon swings hit harder is worth
more here than any element.**

### 2.4 Boss MP pools

From `monster_prop.dat` +0x0A/0B: Shiva 500, Ifrit 600, Number 024 777, Number
128 810, each Crane 447. Party pools at this level sit near 40–60 MP
(mp-economy.md, "Early pools"). This matters in §6.

### 2.5 The random-encounter set — and the hole in it

Decoded by walking `sub_battle_group.dat` (`$CF5600`, one byte per
map id) → `rand_battle_group.dat` (`$CF4800`, 8 bytes per group, slot picked
5/16 · 5/16 · 5/16 · 1/16 — the dispatch is at `ff6/notes/ff3u.asm:23211-23233`)
→ the 15-byte formation records in `battle_monsters.dat` (`$CF6200`; layout
corroborated by the worked example at `ot6_hud.asm:1253-1256`) →
`monster_prop.dat`. Map titles from `map_prop.dat` +0 against
`map_title_en.json`; the random-battle enable is `$0525` bit 7
(`field/battle.asm:332`).

**Vector town has no random encounters**: every Vector map (`$0F1`–`$0FD`)
has the enable bit clear and battle group `$00`. The whole stretch's trash is
in the Facility (`$106`–`$113`).

| id | species | lvl | HP | weak | absorb / null |
|---|---|---|---|---|---|
| `$0C7` | Commando | 18 | 580 | bolt \| water | — |
| `$0CB` | Garm | 19 | 615 | bolt \| water | — |
| `$165` | ProtoArmor | 19 | 670 | **bolt** | — |
| `$041` | Pipsqueak | 18 | 250 | bolt \| water | — |
| `$02D` | Trapper | 19 | 555 | bolt \| water | — |
| `$0A0` | Chaser | 19 | 1202 | bolt \| water | — |
| `$047` | Flan | 19 | 255 | **fire** | nulls poison/wind/holy/earth/water |
| `$066` | General | 19 | 650 | **poison** | — |
| `$088` | Gobbler | 19 | 470 | **none** | — |
| `$075` | Rhinox | 19 | 800 | **none** | **absorbs bolt** |

(Three MRF rooms — `$109`, `$10B`, `$10C` — have the enable bit set but battle
group `$00`, which resolves to table entry 0: Leafer `$017` / Dark Wind `$028`,
level-5 Narshe formations. **MARK: whether those rooms are reachable in a state
where the check runs was not verified.** If they are, that is a bug worth a
separate issue rather than a balance input.)

**None of these species appear in `Ot6ElemAddTbl`** (`ot6_break.asm:334-428`;
the table's full id set stops at v0.4's search corridor) **or in
`Ot6ShieldTbl`** (`ot6_hud.asm:1273-1595`). So the element authoring for this
stretch is unwritten, and every trash body here takes formula shields plus
the generated weapon-class break floor.

**The constraint that matters for this design:**

> Across the Facility's ten trash species, exactly one is fire-weak (Flan,
> and only in group `$68`) and none is ice-weak. Six are bolt-weak, and
> Rhinox absorbs bolt.

So for the whole Vector/MRF stretch, Ramuh's bolt is the one element that
covers most of it, and both of the release's headline rewards chip almost
nothing in the dungeon that grants them.

---

## 3. The design

**Ifrit is the body-stat and damage stone. Shiva is the economy and
mitigation stone. Neither is designed around its element.**

- **Ifrit takes HP off the enemy and keeps it.** Drain, plus the largest body
  stat bonus in the game so far. Equip him on a fighter so they hit harder and
  need fewer healing turns from someone else.
- **Shiva takes MP off the enemy and keeps it.** Osmose, plus the mitigation
  that holds up against the dungeon's telegraph contract. Equip her on a caster
  or support character so the party stops running out of MP.

Worn together, Shiva restores the party's MP and Ifrit restores the front
line's HP, so the party can chain Facility encounters without an inn
trip. Worn separately, one is a damage stone and the other a support stone.

They also take **different stats and different carriers**: Ifrit completes
Sabin, Cyan or Edgar, and Shiva completes Celes, Locke or Setzer. There is one
copy of each, so the choice is a party assignment rather than a stat check.

---

## 4. Ifrit — **the Furnace**

> *Menu line:* **IFRIT** — *The forge-beast. Bearer strikes far harder, and
> feeds on what it wounds.*

| channel | value |
|---|---|
| Grants | **Fire**, **Drain** |
| Stat (while equipped) | **+6 vigor / +4 stamina / −3 mag.pwr** |
| Summon (divine) | **Inferno** — fire, all enemies (vanilla record, unchanged) |
| Weapon permit | **none** (§7) |

### 4.1 The two spells

| spell | id | MP | at 1 BP | at 2–3 BP | boost behaviour |
|---|---|---|---|---|---|
| Fire | `$00` | **4** | Fire 2 (pow 60) | Fire 3 (pow 121) | **folds** (`Ot6FoldTbl` row 0); excluded from the ×N multiplier by the tier-family scan at `ot6_kits.asm:1229-1239` |
| Drain | `$04` | **15** | ×2 | ×4 / ×8 | **multiplies** — not in any fold family, deals damage, so it takes `Ot6BoostDmg` in full |

Drain is non-elemental (`magic_prop_en.dat` spell `$04`, +0x01 = `$00`) and
drain-flagged (+0x04 bit `$02`), power 38, hit 120. It works on every machine in
the Facility and chips nothing, which is correct because non-elemental magic
behaves like null-break (DESIGN.md). It turns a fighter's turn into damage and
healing at once.

Ifrit grants only Fire and Drain; his other slots carry his stat package
instead. He does not grant Fire 2 (a dead pre-folded tier), Poison/Bio
(Edgar's authored key), or Cure (Kirin's).

### 4.2 The stat: vigor

Ifrit's `Ot6EsperStatTbl` row is **+6 vigor / +4 stamina / −3 mag.pwr**, the
opposite specialisation to Shiva's (§5.2); see
`docs/design/esper-stat-baseline.md` §4. The four Zozo rows are Ramuh +3
stamina, Siren +2 speed, Stray +3 mag.pwr, Kirin +3 mag.pwr
(`ot6_progression.asm:392-409`). Character base vigor at these levels sits at
31–47 (`char_prop.asm`: Terra 31, Locke 37, Cyan 40, Edgar 39, Sabin 47,
Celes 34); vanilla's per-level esper bonuses are deleted
(`genju_prop.asm:65-71`), and vanilla doubles vigor into the battle stat
`$3b2c` (`ot6_progression.asm:269-271`), so the effective bump is doubled too.

### 4.3 The divine: Inferno

Vanilla record `$37` kept as-is: fire, all enemies, power 51, **26 MP**,
unblockable (+0x04 = `$20`, hit rate 0).

- **Once per battle, per character**, by vanilla's own latch — `tsb $3f2e` in
  `FixPlayerAttack` (`battle_main.asm:12747`), read by the Magic menu's enable
  pass (`battle_main.asm:14436-14439`).
- **Boost multiplies it.** `Ot6BoostDmg` exempts only fight, capture, bushido
  and steal (`ot6_kits.asm:1206-1224`); command `$19` is not exempt, so a 3-BP
  Inferno is ×8 on every enemy for its flat 26 MP.
- The Right Crane absorbs fire; Number 128 and 024 are unaffected by it.

### 4.4 Divine cadence: the summon does **not** replace the character's divine

The summon and a kit divine are separate latches. The summon rides vanilla's
`$3f2e`; kit divines ride OT6's `OT6_DIVINE_USED` at `$3ecb`
(`ot6_memory.inc:42-44`, used by `Ot6Oblivion` / `Ot6Assassinate`,
`ot6_kits.asm:264`, `:346`). They are different resources: the summon lives on
a transferable stone and costs MP; the divine is a permanent property of the
character. Fusing them would mean handing Cyan a magicite disables Cleave.

---

## 5. Shiva — **the Rime**

> *Menu line:* **SHIVA** — *The still cold. Bearer draws the fight's own magic
> out of it, and turns spellfire aside.*

| channel | value |
|---|---|
| Grants | **Ice**, **Osmose**, **Shell** |
| Stat (while equipped) | **+6 mag.pwr / +4 speed / −3 vigor** |
| Summon (divine) | **Diamond Dust** — ice, all enemies, reduced power, **inflicts Slow** |
| Weapon permit | **none** (§7) |

### 5.1 The three spells

| spell | id | MP | boost behaviour | why |
|---|---|---|---|---|
| Ice | `$01` | **5** | **folds** to Ice 2 / Ice 3 | the element she carries out of the dungeon; the chip axis against Ifrit and everything ice-weak after |
| Osmose | `$29` | **8** (see §6) | multiplies (MP damage) | the party's only MP income; the answer to the live MP economy |
| Shell | `$25` | **15** | **inert** — see below | the answer to the Facility's telegraph contract |

Vanilla Shell is single-target (`magic_prop_en.dat` spell `$25`, +0x00 = `$01`;
the multi-target rows in that table carry `$6x`) and costs 15 MP.

**Boosting Shell does nothing.** It is not in `Ot6FoldTbl` and it deals no
damage, so `Ot6BoostDmg` has nothing to multiply. DESIGN.md's BP economy
promises "Buffs/debuffs: duration per BP" but no such mechanism is built
(§12). It is a general gap rather than a Shiva-specific one, and Shiva is the
first kit to meet it.

Shiva grants Ice, Osmose and Shell; she does not grant Ice 2 (a dead
pre-folded tier), Rasp (Ramuh's), or Cure (Kirin's). Slow folds to Slow 2 for
5 MP and suits her, but it goes on the **divine** instead (§5.3), so the list
and the summon do not duplicate each other.

### 5.2 The stat: magic power

Shiva's `Ot6EsperStatTbl` row is **+6 mag.pwr / +4 speed / −3 vigor**, the
two-sided mirror of Ifrit's. See `docs/design/esper-stat-baseline.md`.

Base mag.pwr sits at 25–39 (`char_prop.asm`: Celes 36, Terra 39, Strago 34,
Locke 28, Sabin 28).

### 5.3 The divine: Diamond Dust

Vanilla `$38` mirrors Ifrit's `$37`: same targeting, same flags, power 52 vs
51, 27 MP vs 26. Diamond Dust ships changed: ice, all enemies, **power 34**
(record `$38` +0x06), with **Slow** in the record's status bytes (+0x0C =
`$04`, `STATUS3::SLOW`, `const.inc:1517`). Everything else — targeting `$6e`,
element `$02`, unblockable `$20`, 27 MP — is vanilla.

- Decoded from `monster_prop.dat` +0x16 (STATUS3 immunities): Number
  128 `$10`, both Cranes `$10`, both blades `$00` → **Slow lands**; Number 024
  `$14` → **Slow is blocked**.
- **Boost canon.** Diamond Dust is a **damage verb**, so boost multiplies its
  damage and does not touch the rider. That is the same no-double-dip rule that
  keeps folded spells out of `Ot6BoostDmg`. The record is already
  unblockable (+0x04 = `$20`, hit 0), so there is no chance axis for boost to
  guarantee.
- **The rider lands without a roll, and immunity still applies.** An
  unblockable (+0x04 `$20`, hit 0) damage spell applies its status bytes
  without a roll, because `CheckHit`'s multi-target arm branches on `bit #$20`
  straight to the carry-clear exit. Per-monster immunity is still
  consulted, because `MagicStatusEffect` only stages the rider into `$3de8`
  and `InitStatusVars` ANDs that against `$3330` before anything is set.
  `tools/tests/battle_magicite.lua` fires a menu-driven Diamond Dust at two
  guards, one with the Slow bit set in `$3330` and one with it cleared, and
  gets Slow on the first and not the second from the same cast.

---

## 6. Osmose

**Osmose costs 8 MP** (`magic_prop_en.dat` spell `$29`, +0x05, overridden from
vanilla's `$01` in the `MagicProp` splice), power
26, hit 150, MP-targeting (+0x03 bit `$80`), drain-flagged (+0x04 bit `$02`).
Facility boss MP pools run **447–810** (§2.4). Party max MP at this point is
roughly 40–60 (mp-economy.md).

FF6's magic damage scales on power, level and mag.pwr; at Facility levels a
single unboosted Osmose computes for several hundred, which is many times the
caster's entire pool, so one cast is a full refill against any enemy with MP.
With `OT6_MP_COSTS` live, every verb but Fight costs MP (mp-economy.md), so a
character who never runs out of MP is valuable.

Compounding it: MP damage rides the same `$11b0` value the boost multiplier
edits, so `Ot6BoostDmg` scales it too (`ot6_kits.asm:1240-1252`; MP application
at `ApplyDmgMP`, `battle_main.asm:3021-3050`). *(**UNVERIFIED:** whether the
drain half credits the caster with the **computed** amount or with the amount
actually removed from a smaller pool. Measured at 30 MP against a 500 MP pool
(caster 30 → 22 → 63, target 1000 → 959), the credit equals the amount
removed, but the pool was never the limiting factor there, so the
nearly-empty-enemy case is still open. Read `_c213a7`'s net-damage path before
tuning. The answer changes how large the problem is; the problem exists either
way.)*

**Osmose stays on Shiva, priced at 8 MP**, an explicit exception to
mp-economy.md's "Magic keeps its vanilla MP costs (house rule)". Vanilla
priced Osmose at 1 MP in a game where only some characters spent MP at all;
under OT6 every verb costs MP, and a 1-MP full refill would remove MP as a
constraint altogether. 8 MP keeps the spell net-positive (still a refill),
keeps it castable on a nearly empty pool, and stops it from being free. The
change is one byte and applies globally, so ZoneSeek inherits it.

**A harness note for anyone measuring a spell here.** `LoadMagicProp` fills one
shared property buffer (`$11a0..$11ad`), so on the generated Magitek intro
savestate an ally's beam resolving inside the caster's action window
overwrites the record mid-resolution. Without instrumentation the result looks
like "the summon charged 0 MP, applied no status, and scratched one guard",
which is an artifact of the interleave rather than the spell's behaviour.
Freeze the rest of the party first.

---

## 7. Weapon permits: deliberately none

Neither esper carries a weapon permit. No equip-side code reads a permit; the
only mention in the source is a forward-looking comment (`ot6_class.asm:17`).
Every Facility boss is slash|pierce-breakable (§2.3) and the fixed party
covers both, and Sabin can already switch his Fight to slashing by equipping
claws, so a claw permit on Ifrit would add nothing.

---

## 8. Player-facing copy

Keep `GenjuName` "Ifrit" / "Shiva" and the vanilla summon names (`Inferno`,
`Diamond Dust`, `genju_attack_name_en.json`). The sub-job nicknames used in
this document — *the Furnace*, *the Rime* — are not shipped strings.

The esper detail screen (`skills.asm`) blanks the vanilla learn-rate/percent
field for a granted spell rather than drawing it, since `GenjuProp`'s learn
bytes are zeroed by design (`genju_prop.asm:56-64`); item detail
(`item.asm`) still falls through to the vanilla rate display. The
while-equipped stat block replaces vanilla's "at level up:" line and is drawn
from `Ot6EsperStatTbl`.

---

## 9. Balance

### 9.1 Against the Factory party

Six stones for four slots.

| stone | wants to be worn by | competes with |
|---|---|---|
| Ramuh | any caster | — |
| Kirin | the designated healer | Ifrit (partly) |
| **Ifrit** | Sabin / Cyan / Edgar / Locke | **Siren** |
| **Shiva** | Celes / Locke / Setzer | **Stray** |
| Siren | a caster | Ifrit |
| Stray | a caster | Shiva |

### 9.2 Against the boss keys

| fight | element key | class key | what Ifrit adds | what Shiva adds |
|---|---|---|---|---|
| Ifrit & Shiva `$109`/`$108` | ice → Ifrit, fire → Shiva | pierce / slash | *(not yet owned)* | *(not yet owned)* |
| Number 024 `$10a` | rotating, re-hidden | slash\|pierce | **vigor on the class axis**; Drain (element-independent) | **Shell** vs the wall's tier-2 payoff; Osmose vs a 777 pool. *Slow is immune here* |
| Number 128 `$10b` | authored bolt/water (see below) | pierce | vigor; Drain | **Diamond Dust's Slow**; Shell. *Ice is absorbed — do not cast it* |
| Cranes `$10d`/`$10e` | water (both), bolt (right only) | pierce | vigor; Drain. *Inferno is absorbed by the right Crane* | **Slow on two independent fuses**; Shell vs Fire 3 / Giga Volt |

Both stones contribute to all three post-acquisition fights without their
element. Number 128's body is authored bolt|water
(`ot6_break.asm`: `.word $010b` / `.byte $84, $00`), which is the key Ramuh
pays out just upstream; it absorbs ice.

### 9.3 MP arithmetic, one worked line

A Celes wearing Shiva at ~50 max MP: Shell (15) on the front-liner, Ice at 1 BP
(5) as a probe, Osmose (**8**) to refill: net −12 MP per
three actions against any enemy with a pool, versus −20 without Osmose. That is
the intended result, **sustaining but not free.** At vanilla's 1 MP it is
−19 for three actions plus a full refill, i.e. permanently net-positive, which
is §6's problem stated as a number.

---

## 12. What the shipped machinery cannot express

- **HP% / MP% mods.** Structurally unsupported: the `Ot6EsperStatTbl` selector
  has no encoding for them (`ot6_progression.asm:299-303`).
- **Named passives.** There is no passive pool, no slots and no learning meter
  (ROADMAP M4, ⬜). Neither esper carries one; both are designed around their
  spell lists and stat packages instead.
- **Weapon permits.** No equip-side consumer exists (`ot6_class.asm:17`).
- **Boost on a buff.** `Ot6QueueFold` only folds the 8 tier families and
  `Ot6BoostDmg` only multiplies damage, so **boosting Shiva's Shell has no
  effect**, and the UI still lets a player spend BP on it.
- **A boost/fold family for anything outside the 8 rows.** `Ot6FoldTbl` is
  scanned with a hard `cpx #$0018` bound in three places
  (`ot6_boost.asm:255,:317`, `ot6_kits.asm:1233`).
- **Per-esper summon gating beyond vanilla's.** The once-per-battle latch is
  vanilla's `$3f2e` and is per-character, party-wide-uniform. There is no way
  to say "this summon is twice per battle" or "this summon requires a Broken
  target" the way `Ot6Oblivion` can for a kit divine.
- **Re-pricing magic without breaking a house rule.** Magic prices through
  vanilla `GetMPCost` off the spell record; `Ot6AbilityCostTbl` keys only
  blitz/bushido/tool id ranges (`ot6_boost.asm:352-400`). Repricing a vanilla
  spell (as Osmose was, §6) is a one-byte `.dat` edit, but it is a global
  change, which is why mp-economy.md records it as an explicit exception.
