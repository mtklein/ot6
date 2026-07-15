# Research: battle code map — where OT6 hooks go (verified 2026-07-14)

The classic commented C2 disassemblies map line-for-line onto the buildable
everything8215/ff6 source (`src/battle/battle_main.asm` keeps `@`-hex labels
matching the classic addresses), so both are cited by C2/xxxx address.

## Documents

- Terii Senshi's original C2 disassembly + Algorithms FAQ v2.3:
  http://www.rpglegion.com/ff6/hack/info.htm (code2.txt),
  https://gamefaqs.gamespot.com/snes/554041-final-fantasy-iii/faqs/13573
- assassin17's expanded "Co-opted Bank C2 Disassembly" (36.5k lines, full
  bank): http://assassin17.brinkster.net/code2i.txt (plain HTTP)
- Leet Sketcher "Bank C2 Disassembly v7" fills the uncommented gaps:
  http://l33t5k37ch3r.altervista.org/bank-c2-disassembly.html
- C3 menu bank: Novalia Spirit's "$C3 Compendium" — fully commented, every
  line (ff6hacking wiki doc:game page, ff6_bank_c3.zip). Menu work in M4
  is well-lit after all.
- C1 (battle gfx): bankC1.txt in slick_banks.zip on the wiki — thin,
  tentative comments; expect real reverse-engineering for the shield-pip UI.
- Mirrors: https://github.com/clementgallet/ff6-tas/tree/master/DisassemblyDocs,
  https://datacrystal.tcrf.net/wiki/Final_Fantasy_VI:ROM_map/Assembly_C22 (etc.)

## Verified hook sites for OT6

| Address | What lives there | OT6 use |
|---|---|---|
| C2/2B69 | magic damage calc (`$11B0 = SpellPower*4 + Level*MagPwr*SpellPower/32`) | boost-tier multipliers |
| C2/2B9D | physical damage calc entry | boost extra hits / multipliers |
| C2/0C9E | post-calc damage modification (random, row, …) | ×2 damage vs Broken |
| C2/0BD3–0C1E | per-target elemental handling — absorb $3BCC (0BE2), null $3BCD (0BF2), half $3BE1 (0C00), **weak $3BE0 (0C0E)**; priority absorb→null→half→weak | **break chip hook** — weakness match already computed here |
| C2/2E27 | monster elemental properties loaded from ROM ($CF0017,X) | seed per-battle weakness/shield state |
| C2/09D2 | ATB gauge-constant calc ("CalcSpeed"): chars `(Speed+20)*C`, C=48/96/126 | BP accrual timing |
| C2/08C6 (gate 08D5–08F2) | per-entity pre-action gate: exits if Death/Petrify, **Stop ($10 @ $3EF8)**, **Freeze ($02 @ $3EF9)** | Broken entities skip turns here |
| C2/22FB | hit determination: `PEA $8040` (Sleep,Petrify) / `PEA $0210` (Freeze,Stop) → always hit | Broken targets always hit — vanilla precedent is exactly Octopath's rule |
| C2/5A83 / 5AA3 | periodic tick: `$3ADC,X += $3ADD,X`; on overflow decrement Stop timer $3AF1,X | Broken-timer countdown lives here |
| C2/5B06 | timed-status wear-off (sets bit in $B8, queues removal via $4E91) | Broken recovery + shield reset |
| C2/4490 / 44BB | attack status set/lift/toggle dispatch; fire-thaws-Freeze check | template for on-Break / on-recover side effects |
| C2/46B0 / 46F0 | per-status-bit set/clear side-effect pointer tables (Stop timer #$12→$3AF1 at C2/467D; Freeze #$22→$3F0D at C2/4691) | Broken as pseudo-status copies this pattern |

## Status bytes: no free bits — Broken is a pseudo-status

All 32 bits across $3EE4/$3EE5/$3EF8/$3EF9 are assigned (full table:
https://www.ff6hacking.com/wiki/doku.php?id=ff3:ff3us:doc:asm:list:condition_effects).
Community practice (madsiur/Synchysi,
https://www.ff6hacking.com/forums/archive/index.php?thread-2153.html): don't
add a 33rd bit; either repurpose one or build a pseudo-status from free RAM.

Precedent: Madsiur's Status Timers Hack used the blank per-entity byte
tables $3E38/$3E39/$3E88/$3E89 + free bits $10–$80 of the expired-status
byte $B8 (https://www.ff6hacking.com/forums/thread-4176.html). We're not
stacking that hack, so those four blank per-entity tables are available —
though since we build from source with ld65, the cleaner move is to
allocate new battle-RAM segments through the linker config instead of
scavenging. (Both options open; decide in M1.)

Broken = per-entity timer + five surgical checks (turn gate, always-hit,
×2 damage, tick, wear-off) — every one at a verified address above, each
copying a vanilla pattern (Stop/Freeze). Spell data byte $07 has six free
bits per *attack* (per Synchysi) if we need to flag attacks specially.

## Spell/attack data (for chip assignment + boost tiers)

14 bytes per spell × 256 at C4/6AC0; byte $01 = elements, bytes $0A–$0D =
status 1–4 to set/lift/toggle (dispatch at C2/4490).
https://www.ff6hacking.com/wiki/doku.php?id=ff3:ff3us:doc:asm:fmt:spell_data
