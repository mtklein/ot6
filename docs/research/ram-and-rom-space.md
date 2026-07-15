# Research: battle RAM + ROM free space (FF3us 1.0)

Verified 2026-07-14 against ff6hacking.com wiki and the everything8215/ff6
disassembly notes. Kept verbatim-ish from the research pass; distilled
takeaways for OT6 at the bottom.

## Battle RAM map

Primary sources:
- https://www.ff6hacking.com/wiki/doku.php?id=ff3:ff3us:doc:asm:ram:battle_ram
- https://raw.githubusercontent.com/everything8215/ff6/main/notes/battle-ram.txt
  (line-for-line matches the wiki page)
- Battle graphics RAM: https://raw.githubusercontent.com/everything8215/ff6/main/src/btlgfx/btlgfx_ram.inc

Layout: **10 combatant slots** (4 characters + 6 monsters). Per-combatant
variables are parallel tables, 2 bytes per combatant, $14 bytes per table;
entity offset X = $00..$06 (chars), $08..$12 (monsters). Entity masks at
$3018-$302A; character roster slots at $3000-$300D; pointers to character
data (+$1600) at $3010-$3016.

Key per-combatant tables:

| Address | Contents |
|---|---|
| $3BF4 / $3C08 | Current HP / MP |
| $3C1C / $3C30 | Max HP / MP |
| $3EE4/$3EE5, $3EF8/$3EF9 | Status bytes 1-2, 3-4 |
| $3AC8 | ATB gauge constant (see C2/09D2) |
| $3AB4 | Advance wait counter |
| $3ADC/$3ADD | Slow/Normal/Haste counter + constant (32/64/84) |
| $3AF0 / $3AF1 | DoT counter / **Stop counter** |
| $3F0C / $3F0D | Reflect counter / **Freeze counter** |
| $3B18/$3B19 | Level / Speed |
| $3B90 / $3B91 | **Attack elemental / attack properties** (attacker side) |
| $3BCC / $3BCD | Absorbed / immune elements |
| $3BE0 / $3BE1 | **Weak elements / halved elements** |
| $3F20 / $3F22 | Last command / last targets |
| $3254 / $3268 | AI script ptr / counterattack script ptr |
| $3F46+ | Monster 1-6 IDs |

Global: $3A44 battle counter (increments every 16 frames). Display-side ATB:
$3218 (gauge %), $322C advance wait duration.

Region shape: battle logic variables ≈ 7E:2000-3FFF; 7E:4000-F7FF belongs to
the battle **graphics** module (HDMA/sprite/animation buffers).

### Free RAM for new per-combatant state

- `$3ECB-$3ED3` — 9 bytes explicitly marked "unused local battle variables"
  (only range explicitly free inside the battle-variable region).
- 7E:2000-5FFF is **mode-overlaid** with field RAM — anything free-in-battle
  is only free *during battle*. Fine for shields/BP (battle-only by design).
- Persistent state: community practice is SRAM expansion (vanilla: 8 Kb at
  $306000-$307FFF); see https://www.ff6hacking.com/forums/thread-3694-post-37598.html
  — but OT6's JP reuses existing AP storage, so we likely never need this.
- Save-region scraps: $1E1D-$1E3F (~35 bytes), $1E70-$1E7F (madsiur,
  https://www.ff6hacking.com/forums/printthread.php?tid=1408).

## ROM free space + expansion

- Unused-space registry: https://www.ff6hacking.com/wiki/doku.php?id=ff3:ff3us:doc:asm:rom_map:unused_space
  — ~60 fragments, ~29 KB total (<1% of ROM). Largest: $C4A4C0-$C4B9FF
  (5440 B), $C3F091-$C3FFFF (3951 B), $D4F646-$D4FFFF (2496 B),
  $C0D613-$C0DF9F (2445 B), $C47FE8-$C487BF (2008 B).
- **Expansion to 32 Mbit (4 MB) is the standard move**: adds banks $F0-$FF,
  stays plain HiROM; Lunar Expand / SNEStuff / FF3usME all do it
  (https://www.ff6hacking.com/wiki/doku.php?id=hacking_faq).
- Beyond 32 Mbit = ExHiROM; real hacks do it (Return of the Dark Sorcerer is
  8 MB) but long addressing needs bank-byte care
  (https://github.com/Dizzy611/DancingMadFF6/issues/71). Avoid unless forced.
- Collision conventions: the community "patchmap" registry documents which
  ranges existing patches occupy —
  https://www.ff6hacking.com/wiki/doku.php?id=ff3:ff3us:patches:patchmap.
  Expanded-space etiquette from forum practice: editors claim ranges (FF3usME
  AI expansion configurable $F0-$FF); suggestions like "put stuff in $F1-$F2"
  / "$F6-$FB" (https://www.ff6hacking.com/forums/printthread.php?tid=3251).

## OT6 takeaways

1. **Weakness data is already per-combatant in battle RAM** ($3BE0 weak,
   $3BE1 halved, $3BCC absorb, $3BCD immune) and the attack's element is at
   $3B90 during resolution — the break-chip hook reads RAM that already
   exists. This is also how Debilitator must work (it edits $3BE0). Weapon-
   class weakness gets a parallel new table, same $14-stride convention.
2. **Broken-state timer has two vanilla models to copy**: Stop counter
   ($3AF1) and Freeze counter ($3F0D) are existing per-combatant countdowns.
3. **New battle state budget**: shields-current (10 B), shields-max cache
   (10 B), broken timer (10 B), discovered-weakness masks (20 B), BP (4 B for
   characters, or 10 B uniform), boost-pending (4 B) ≈ 60-70 bytes. The
   9 free bytes at $3ECB won't hold it — plan A is claiming a slice of the
   mode-overlaid region verified unused in battle (needs a trace-based
   audit in M0/M1), plan B is bank $7F or the graphics region's slack.
   Battle-only lifetime makes this tractable.
4. **Expand to 32 Mbit immediately in M0** and put all OT6 code/tables in a
   clearly-claimed expanded bank (e.g. $F0-$F1), documented patchmap-style,
   rather than squeezing into vanilla's 29 KB of scraps.
5. All offsets above are for the unheadered 1.0 ROM — matches our base.
