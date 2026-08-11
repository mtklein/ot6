# Research: data-record formats (FF3us 1.0)

Cross-checked across ff6hacking wiki fmt pages, Data Crystal, ff6tools
struct JSON, the disassembly's notes/rom-map.txt, and Beyond Chaos source.
HiROM: file offset = SNES address − 0xC00000.

## Element bit mask (used identically everywhere)

$01 Fire · $02 Ice · $04 Lightning · $08 Poison · $10 Wind · $20 Holy ·
$40 Earth · $80 Water

## Monster stats — $CF0000, 32 B × 384

Key fields: +0x00 speed, +0x01 attack, +0x05/06 def/mdef, +0x08 HP,
+0x10 level, +0x14–16 status immunities, **+0x17 absorb / +0x18 null /
+0x19 WEAK elements**, +0x1B–1D auto-statuses, +0x1F special attack.
Free bits only (+0x12: $02/$08/$20; +0x1E: $08–$40) and no free bytes, so
shield/weapon-weakness data goes in new parallel tables, which is
straightforward when building from source. Monster names $CFC050
(10 B × 384).

## Items — $D85000, 30 B × 256

+0x00 type (0 tool, 1 weapon, 2 armor, 3 shield, 4 helmet, 5 relic,
6 consumable; $80 unused) · +0x01–02 equippable-by bitmask (14 chars) ·
+0x03/+0x04 spell learn rate / spell taught while equipped ·
+0x09–0D relic-effect flag bits (the "commands morph" bits: Fight→Jump,
Slot→GP Rain, Steal→Capture, …) · +0x0F weapon element ·
+0x12 proc-spell ($3F id, $40 random-proc, $80 breaks) ·
+0x13 weapon flags (SwdTech-ok $02, back-row-ok $20, two-hand $40,
runic $80; $01/$04/$08/$10 free) · +0x14 power · +0x1B special-effect
nibble + block/parry anim · +0x1C price.

**No weapon-category (sword/spear/…) field exists.** The only category-ish
datum is the icon glyph prefixed to names at $D2B300. OT6's 8-class table
is a new parallel table keyed by item ID. The glyph is not a category
either: daggers carry `{spear}` in `item_name_en.json`, and `$28` is a
katana.

### The equippable-by mask

**Offset +$01, 16-bit little-endian, i.e. bytes +$01 and +$02.**

The game's own read, `GetValidWeapons` / `GetValidShields`
(`ff6/src/menu/equip.asm:1594-1601`, :1629-1636):

```
        lda     f:ItemProp,x    ; +$00 type
        and     #$07
        cmp     #$01            ; 1 = weapon (3 = shield in the sibling)
        bne     @skip
        longa                   ; <-- 16-bit A
        lda     f:ItemProp+1,x  ; <-- the mask, +$01..+$02
        bit     ze7             ; ze7 = this character's bit
        beq     @skip           ; not equippable
```

Same read at `shop.asm:1415` and `battle_main.asm:14303`. The character
bit comes from `GetCharEquipMask` (`equip.asm:2287`), which indexes
`CharEquipMaskTbl` — a plain identity table, `.word $0001,$0002,$0004,…`
— by actor number. **So bit N = actor N**, per `CHAR_FLAG`
(`ff6/include/const.inc:1416-1430`):

| bit | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| who | Terra | Locke | Cyan | Shadow | Edgar | Sabin | Celes | Strago | Relm | Setzer | Mog | Gau | Gogo | Umaro | Banon | Leo ✱ |

**✱ bit 15 is doubly booked.** It is actor 15 (Leo) *and* the Merit Award
override: `GetCharEquipMask` ends with `lda $11d8 / and #$20 / ora
#$8000` (`equip.asm:2300-2306`), and `$11d8` is the relic-effect byte
fed from item +$0C (`battle_main.asm:2522-2523`), where Merit Award `$da`
carries `$20` (Gauntlet `$d0` = `$08`, Genji Glove `$d1` = `$10`).
Decoding bit 15 as a character therefore reports a spurious Leo on
almost every weapon. Bit 14 (Banon) is real but appears on exactly four
items: the imp gear `$24 / $65 / $83 / $9b`, all mask `$dfff`
(everyone but Umaro).

Pinned against items whose wielders are unambiguous:

| item | id | mask at +$01 | reading at +$01 (correct) | reading at +$00 (wrong) |
|---|---|---|---|---|
| MetalKnuckle…Tiger Fangs (claws) | `$53-$59` | `$8020` | Sabin only — the Blitz signature | `$2001` = Terra + Umaro |
| Ashura…Murasame (katana) | `$2b-$2f` | `$8004` | Cyan only | `$0411` = Terra + Edgar + Mog |
| Imperial…Stunner (ninja) | `$25-$2a` | `$8008` | Shadow only | `$0811` = Terra + Edgar + Gau |
| Mithril Pike…Aura Lance (spear) | `$1d-$23` | `$8410` | Edgar + Mog | `$1011` = Terra + Edgar + Gogo |
| Imp Halberd | `$24` | `$dfff` | everyone but Umaro | `$ff11` = nonsense |
| Heavy Shld | `$5b` | `$8257` | Terra/Locke/Cyan/Edgar/Celes/Setzer | `$5703` = seven wrong names |

The +$00 column is what the byte-0 reading produces: `type | mask<<8`,
with the low byte shifted out and the type byte shifted in. That value
resembles a mask and always includes Terra, because every weapon's type
byte has bit 0 set, and it is always wrong. `$28` Hardened shows the
failure clearly: +$01 says Shadow, correct for a ninja katana, while
+$00 says Terra/Edgar/Gau, which is wrong.

Corollary already used downstream: **Gau's only legal weapon in the
game is the Imp Halberd `$24`**, because no other item with type 1 has
bit 11 set. Any character × weapon-category matrix must be decoded from
the +$01 offset.

## Espers — $D86E00, 11 B × 27

5 × (learn-rate byte, spell-ID byte) pairs + 1 level-up-bonus byte
($FF = none; $00–$10 = HP/MP%/stat bonuses). Empty spell slot = $FF.
Order: Ramuh, Ifrit, Shiva, Siren, Terrato, Shoat, Maduin, Bismark, Stray,
Palidor, Tritoch, Odin, Raiden, Bahamut, Alexandr, Crusader, Ragnarok,
Kirin, ZoneSeek, Carbunkl, Phantom, Sraphim, Golem, Unicorn, Fenrir,
Starlet, Phoenix. ~215 slack bytes follow the table ($D86F29–D86FFF).
Sub-jobs design maps 1:1 onto this record: 5 granted skills + equip bonus.

## Spells/abilities — $C46AC0, 14 B × 256

+0x00 targeting bits · **+0x01 element** · +0x02 flags (physical $01,
ignore-def $20, no-split $40) · +0x03 flags (field-usable $01, ignores
reflect $02, lore-learnable $04, runic-able $08, targets-MP $80) ·
+0x04 flags (heal $01, drain $02, lift-status $04, toggle $08,
unblockable $20, fractional $80) · +0x05 MP cost · +0x06 spell power ·
+0x07 flags ($01 miss-if-immune, $02 show-text; **$04–$80 free — 6 free
bits per attack**) · +0x08 hit rate · +0x09 special-effect index ·
+0x0A–0D status bytes 1–4 to set/lift/toggle.

IDs: 0–53 magic, 54–80 esper summons, 81–255 everything else (Blitzes,
SwdTechs, Lores, Tools, Dances, enemy attacks…). Chip-type assignment for
skills can largely ride the existing element byte; weapon-class chip needs
the new class table (weapons) + per-skill class tags (free bits at +0x07
or a small parallel table).

## Free space near these tables

$D2B224–D2B2FF (220 B, labeled unused), esper-block tail (~215 B), plus
the ~29 KB of scattered fragments in docs/research/ram-and-rom-space.md.
Mostly moot for us: building from source, new tables go in expanded banks
via the linker config.
