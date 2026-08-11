# The esper stat baseline: what a gear upgrade is worth

The owner's direction is *"rebalance esper passives by making equipping an
esper feel like equipping a next-level-up piece of equipment, so something
like maybe +10 stats across relevant stats."* The `+10` in that direction is a
hypothesis. This document measures the comparison the direction names before
pricing anything.

**Evidence rule (CONTRIBUTING.md).** Every number below names the file and the
byte offset it was read from. The two measurement scripts are transcribed in
§6 so the table can be re-derived.

---

## 0. Findings

1. **Vanilla FF6 already encodes the object wanted here.** `ItemProp+16/+17`
   is two bytes holding four signed 4-bit stat deltas, for vigor, speed,
   stamina and mag.pwr, decoded by `CalcEquipEffect`
   (`ff6/src/battle/battle_main.asm:2521-2539`). Range −7..+7 per stat. It is
   not a selector plus a magnitude. Every stat-bearing weapon, helmet, armour
   and relic in the game uses this encoding, so the encoding question has a
   measured answer rather than a designed one: adopt the game's own.
2. **A level-up grants zero base stats.** `DoLevelUp`
   (`battle_main.asm:16053-16111`) writes max HP and max MP only. The only
   per-level base-stat channel vanilla ever had was the esper bonus byte,
   which grants +1 or +2 in exactly one stat (`GenjuBonusTbl` handlers,
   `battle_main.asm:16198-16209`), and M5 deleted it by setting every
   `GenjuProp` bonus byte to `$ff`. So "next-level-up" cannot mean character
   level, because a character level-up is worth no base stats at all.
3. **Vanilla's gear tiers do not grow stat packages.** Within a slot,
   consecutive tiers raise defense power by +1..+7 and change the shape of the
   stat package rather than growing its sum (§2). The next tier up is a
   sidegrade in stats and an upgrade in defense.
4. **+10 across several stats is about three tiers rather than one.** Measured
   against WoB shop stock, whose stat-bearing pieces run median net +3, q3 +6,
   ceiling +11. It is close to the best stat package purchasable in the World
   of Balance (Power Sash, +11, 5000 gil).
5. **Downsides have vanilla precedent, and it is rare.** In all 256 item
   records only two carry a negative: Cursed Shld (−7 on all four) and Iron
   Armor (−2 speed, for heavy armour slowing the wearer). Those two are the
   licence for a downside stat and the model for how sparing to be.

---

## 1. Baseline A: the size of an equipment stat package

### 1.1 The encoding, read from the decoder

`CalcEquipEffect` (`battle_main.asm:2521-2539`):

```
        lda     f:ItemProp+16,x         ; a16 -> reads BOTH bytes +16 and +17
        ldy     #$0006
@0fcf:  pha
        and     #$000f
        bit     #$0008
        beq     @0fdc                   ; branch if positive boost
        eor     #$fff7
        inc
@0fdc:  clc
        adc     $11a0,y                 ; add to stat
        sta     $11a0,y
        pla
        lsr4
        dey2
        bpl     @0fcf
```

Four iterations, `Y` = 6, 4, 2, 0, against the property buffer
`$11a6` vigor / `$11a4` speed / `$11a2` stamina / `$11a0` mag.pwr
(`battle_main.asm:6786-6800` reads them back in that order). So:

| nibble | stat | buffer |
|---|---|---|
| `+16` low | vigor | `$11a6` (vanilla later doubles it into `$3b2c`) |
| `+16` high | speed | `$11a4` (`$3b19`) |
| `+17` low | stamina | `$11a2` (`$3b40`) |
| `+17` high | mag.pwr | `$11a0` (`$3b41`) |

Sign decode: for a nibble `v` with bit 3 set, `(v ^ $fff7) + 1` = `−(v & 7)`.
So a nibble is **bit 3 = sign flag, bits 0-2 = magnitude**, giving `0`..`+7`
and `$9`..`$f` = `−1`..`−7`. `$8` is a dead code that decodes to zero.

These nibbles are the unit the rest of this document uses. Every number in
§1.2 and §2 is in these units, so a design number transcribes into a table
byte without conversion.

### 1.2 The distribution over all 256 records

`ff6/src/menu/item_prop_en.dat`, 30 bytes per record, 256 records, bytes
+16/+17. The file is byte-identical to the FF3us 1.0 base, so this is
vanilla's own distribution rather than OT6's.

| population | items | net-total min | q1 | **median** | q3 | max | stats touched (median) |
|---|---|---|---|---|---|---|---|
| all stat-bearing items | 55 | −28 | +3 | **+5** | +8 | +28 | 2 |
| WoB shop-purchasable | 12 | −2 | +2 | **+3** | +6 | +11 | 1 |
| relics | 4 | +2 | +5 | **+5** | +5 | +5 | 1 |
| helmets | 11 | +2 | +4 | **+6** | +6 | +10 | 2 |
| body armour | 18 | −2 | +5 | **+7** | +11 | +24 | 1.5 |
| weapons | 21 | +1 | +2 | **+4** | +7 | +28 | 2 |

Per-magnitude counts across all 55 stat-bearing records (each nonzero nibble
counted once): `+1`×27, `+2`×34, `+3`×19, `+4`×7, `+5`×11, `+6`×7, `+7`×12,
`−2`×1, `−7`×4. +1 and +2 together are more than half of all stat deltas in
the game. +7 is the ceiling, which is the encoding's own limit, and only these
items reach it: Enhancer, Magus Rod, Illumina, Ragnarok, Nutkin Suit, Wing
Edge.

Stats-touched counts: 26 items touch one stat, 7 touch two, 6 touch three, and
16 touch all four. Multi-stat packages are common, and they are the form the
late-game high-end gear takes.

### 1.3 The two negatives in the whole game

| item | record | package | reading |
|---|---|---|---|
| Cursed Shld | `$66` (+16/+17 = `ff ff`) | −7 / −7 / −7 / −7 | a curse, which is the item's purpose |
| Iron Armor | `$87` (+16 = `a0`) | speed −2 | heavy plate slows the wearer |

Nothing else in 256 records carries a downside. A downside is legal, is
authored sparingly, and reads as flavour rather than as a tax. Iron Armor is
the precedent worth copying: −2 on one stat, on an item whose identity already
implied it.

---

## 2. Baseline B: what the next tier up grants

WoB shop stock, decoded from `ff6/src/menu/shop_prop.dat` (9 bytes per shop:
+0 type/price-adjust, +1..+8 item ids, `$ff` empty; `shop.asm:1802` for the
type mask, `:819` for the item slots). WoB = shops 0-45; the Diamond/Crystal
tiers first appear at shop 57 and Thamasa (the v0.8 stretch) is shops 33/34/35.

Ordered by defense/battle power (`ItemProp+20`), which is how the game tiers
a slot:

### Helmets

| tier | Dpow | Δ Dpow | package | net | gil |
|---|---|---|---|---|---|
| Hair Band | 12 | — | — | 0 | 150 |
| Plumed Hat | 14 | +2 | — | 0 | 250 |
| Magus Hat | 15 | +1 | mag +5 | **+5** | 600 |
| Bandana | 16 | +1 | — | 0 | 800 |
| Head Band | 16 | +0 | vig +3, spd +1, stm +2 | **+6** | 1600 |
| Iron Helmet | 18 | +2 | — | 0 | 1000 |
| Bard's Hat | 19 | +1 | — | 0 | 3000 |
| Green Beret | 19 | +0 | — | 0 | 3000 |
| Mithril Helm | 20 | +1 | — | 0 | 2000 |
| Tiger Mask | 21 | +1 | vig +3, spd +2, stm +1 | **+6** | 2500 |
| Tiara | 22 | +1 | mag +2 | **+2** | 3000 |
| Gold Helmet | 22 | +0 | — | 0 | 4000 |
| Mystery Veil | 24 | +2 | spd +1, mag +3 | **+4** | 5500 |

### Body armour

| tier | Dpow | Δ Dpow | package | net | gil |
|---|---|---|---|---|---|
| Cotton Robe | 32 | — | — | 0 | 200 |
| Kung Fu Suit | 34 | +2 | — | 0 | 250 |
| Silk Robe | 39 | +5 | mag +1 | +1 | 600 |
| **Iron Armor** | 40 | +1 | **spd −2** | −2 | 700 |
| Mithril Vest | 45 | +5 | — | 0 | 1200 |
| Ninja Gear | 47 | +2 | spd +2 | +2 | 1100 |
| White Dress | 47 | +0 | mag +5 | +5 | 2200 |
| Mithril Mail | 51 | +4 | — | 0 | 3500 |
| **Power Sash** | 52 | +1 | vig +5, spd +1, stm +5 | **+11** | 5000 |
| Gaia Gear | 53 | +1 | — | 0 | 6000 |
| Gold Armor | 55 | +2 | — | 0 | 10000 |

Shields in the WoB (Buckler 16 → Heavy 22 → Mithril 27 → Gold 34) carry no
stat package. The shield tiers raise defense only, by Δ +5..+7 a tier.
Relics: of the 17 WoB-purchasable relics, only Barrier Ring carries a package
(mag +2); the other three stat relics in the game (Blizzard Orb mag +5, Rage
Ring vig +5, Sneak Ring spd +5) are WoR/found.

Measured, one tier is worth +1 to +7 defense power plus a stat package that
changes shape rather than growing. Nine of the thirteen WoB helmet tiers carry
no stat package; the four that do run +2 to +6 and are role sidegrades of each
other (Magus Hat and Head Band are the same tier by defense and serve opposite
roles).

---

## 3. Baseline C: the level-up readings

The owner's phrase is "next-**level-up** piece of equipment", which supports
two readings. Both were measured.

| reading | what it grants, measured | evidence |
|---|---|---|
| **character level-up** | **max HP and max MP only.** Vigor / speed / stamina / mag.pwr do not grow with level in FF6 at all. | `DoLevelUp`, `battle_main.asm:16053-16111`: reads `LevelUpHP-2,x` / `LevelUpMP-2,x` and writes `$160b` max HP / `$160f` max MP. No `$161a-$161d` write on any path. |
| **vanilla esper per-level bonus** | **+1 or +2 in exactly one stat, per level**, capped at 128 | `GenjuBonus_09..GenjuBonus_10`, `battle_main.asm:16198-16209`. The enum names it: `STRENGTH_1/2`, `SPEED_1/2`, `STAMINA_1/2`, `MAGPWR_1/2` (`ff6/include/const.inc:858-876`). |
| **the OT6 model** | the §4 tiers: +6..+10 gross across 2-3 stats, with a downside on the upper tiers, applied while worn | `Ot6EsperStatTbl`, `ot6_progression.asm` |

Two consequences.

1. The character-level reading is unusable, because a level-up is worth zero
   base stats and so cannot be the comparison. Only the equipment reading
   remains, which is what §1 and §2 measure.
2. The vanilla esper bonus reading is smaller than it looks. An OT6 WoB
   stretch is 1-3 levels (`wob-route.md`'s table of fight entry points: LOCKE
   L14 → L15, EDGAR L15 → L16 across the whole v0.6 beat). Under vanilla,
   wearing Ramuh for that stretch would have granted +1..+3 stamina,
   permanently. One stretch of vanilla esper growth is therefore worth about a
   flat while-worn +3, delivered up front and taken back on unequip. That is
   the correct like-for-like comparison, and it is why a gear tier's worth is
   a much larger ask than one stretch's.

---

## 4. Whether +10 across several stats is one tier or three

Three tiers measured against the median, about 1.7 tiers measured against the
third quartile, and close to the WoB ceiling.

| the number | measured comparator |
|---|---|
| net **+3** | the **median** stat-bearing piece of WoB shop gear |
| net **+6** | q3 of WoB shop gear: Head Band, Tiger Mask (mid-range helmets, 1600-2500 gil) |
| net **+10** | ~3× the median; between Tiger Mask (+6) and the ceiling |
| net **+11** | Power Sash, the best stat package purchasable in the World of Balance, 5000 gil, Thamasa |
| net **+24..+28** | BehemothSuit, Illumina, Ragnarok: WoR top-end gear, out of range |

The owner's `+10` is about three tiers rather than a one-tier step. It amounts
to *"the best stat armour in the World of Balance, worn in addition to your
armour."* That is a defensible target for a magicite, since magicite is
scarce, is fought for, occupies a one-per-character slot, and twelve of them
compete for four slots. It should be authored knowingly, and it should not be
the whole number.

The design call this baseline supports (the values are in
`ot6_progression.asm`):

> Spend the owner's ~+10 as the upside column, and pay for the top of that
> range with a downside of −2 or −3, so the net lands at +6..+7. That is one
> tier above the mid-range helmet the player is wearing, with a large, legible
> number on the stat that matters. The tiers are then expressed in the gross
> reward and in the sharpness of the trade rather than in the net, which is
> how §2 measured vanilla's own tiers behaving.

Tiers, with their measured comparator:

| tier | who | upside column | downside | net | comparator |
|---|---|---|---|---|---|
| **FIELD** | the Zozo four (found on a floor) | **+6** across 2 | — | +6 | Head Band / Tiger Mask, q3 of WoB gear |
| **STORY** | the tube six (handed over in a scene) | **+8** across 3 | −2 | +6 | above q3, below the ceiling |
| **BOSS** | Ifrit, Shiva, Maduin (fought for, top tier) | **+10** across 3 | −3 | +7 | Power Sash (+11), the WoB ceiling |

Per-stat magnitudes stay inside vanilla's own +7 cap (§1.2), following
`mp-economy.md`'s standing rule to prefer the series' own numbers where a cap
is needed. Only Maduin reaches 7, and the encoding cannot express more.

**Unresolved, and shipping anyway** (per the owner's ruling that an
unresolved value is not a blocker): whether the tiers should separate on net
as well as on gross, i.e. FIELD +6 / STORY +7 / BOSS +9 net. This version
keeps the net flat at +6..+7, because §2 measured vanilla's tiers as shape
changes rather than sum changes, and because a stone found on a Zozo floor is
worn for twenty hours while a boss stone competes with eleven others. Only a
playthrough settles it. The alternative is noted in the table comment beside
the roster.

---

## 5. The encoding

`Ot6EsperStatTbl` uses vanilla's own equipment layout (§1.1): two bytes per
esper, four signed nibbles, −7..+7 each, `$0000` = no mod. It was chosen for
four reasons rather than for packing efficiency:

- the baseline measured above is already in these units, so a design number is
  transcribed rather than converted;
- an esper then carries the same kind of object a piece of equipment carries,
  which is what the issue's title asks for;
- the sign bit, and therefore the downside, is included at no extra cost;
- the decode has a proven reference implementation in the ROM to mirror
  (`CalcEquipEffect`), including its `$8`-is-zero quirk.

The cost is a per-stat ceiling of 7. Per §1.2, nothing in vanilla exceeds +7
either, so the ceiling does not bind anything shipped or planned.

Bank `$f0` is 1 MB of `$ff` fill (`ff6/cfg/ff6-en.cfg:23`), so the second byte
per esper costs no scarce space.

---

## 6. Reproducing the tables

Both scripts read only tracked source and need no ROM.

**Baseline A** — every record's package, plus the distribution: decode
`ff6/src/menu/item_prop_en.dat` at stride 30, bytes +16/+17, four nibbles per
record, `bit3` = sign / `bits0-2` = magnitude; type from `+0 & 7`
(1 weapon, 2 body, 3 shield, 4 helmet, 5 relic); defense/battle power `+20`;
price `+28/+29` little-endian (price 2 = not sold). Names from
`ff6/src/text/item_name_en.json` `text[]`, stripping the leading `{glyph}`.

**Baseline B** — WoB stock: `ff6/src/menu/shop_prop.dat` at stride 9, items in
+1..+8, `$ff` empty; take shops 0-45.

**Baseline C** — `battle_main.asm:16053` (`DoLevelUp`) and `:16198`
(`GenjuBonus_09`) read directly; no script.
