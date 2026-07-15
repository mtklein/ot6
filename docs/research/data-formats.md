# Research: data-record formats (FF3us 1.0, verified 2026-07-14)

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
Free bits only (+0x12: $02/$08/$20; +0x1E: $08–$40), no free bytes —
shield/weapon-weakness data goes in new parallel tables (trivial from
source). Monster names $CFC050 (10 B × 384).

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
is a new parallel table keyed by item ID.

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
