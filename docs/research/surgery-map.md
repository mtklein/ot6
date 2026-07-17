# OT6 Surgery Map — everything8215/ff6 source (verified 2026-07-14, HEAD de6bb61)

Line numbers drift as we insert code; `@xxxx:` labels are the classic
C2/C1 addresses (names, not pins — linking is symbolic).

## 1. Battle-mechanics hook sites — src/battle/battle_main.asm

| Classic | Proc / label | Lines (at map time) | Notes |
|---|---|---|---|
| C2/0B83 | `CalcTargetDmg:` | 1809 | per-target damage calc entry |
| C2/0BD3–0C1E | elemental block in `CalcTargetDmg` | 1844–1876 | gate on `$11a1` (attack element) 1844; forcefield `$3ec8` 1846; absorb `$3bcc,y` 1850–1856; null `$3bcd,y` 1857–1862; half `$3be1,y` 1863–1868; **weak `@0c0e`: `lda $3be0,y / bit $11a1 / beq @0c1e`** 1869–1875 (`asl $f0 / rol $f1` doubles); join `@0c1e` 1876 |
| C2/0C9E | `CalcDmgMod:` | 1961–2039 | variance/def/shell/row/morph; damage in 16-bit `$f0` |
| C2/0C2D | `CalcMaxDmg:` | 1891–1953 | caps 9999, writes `$33d0,y` |
| C2/2B69 / 2B9D | `CalcMagicDmg:` / `CalcDmg:` | 7186 / 7217 | base damage (M2 boost) |
| C2/2C30 | `LoadMonsterProp:` | 7307–7436 | per-monster init, called from `InitMonsters:` 7672@7704 |
| C2/2E27 | inside `LoadRageProp:` | 7504–7550 | **weak elements load: `lda f:MonsterProp+25,x / ora $3be0,y / sta $3be0,y` 7508–7510** — seed shields here (also covers Rage path at 1013) |
| C2/08C6 | `_c208c6:` turn gate | 1383–1420 | Wound/Petrify 1391–93; **Stop `lda $3ef8,x / bit #$10 / bne _08c5` 1394–96**; Freeze 1403–05. Broken-skips-turn goes beside Stop |
| C2/22FB | `@22fb:` in `CheckHit:` (5796) | 5914–5917 | `peaflg STATUS12,{PETRIFY,SLEEP}` / `peaflg STATUS34,{STOP,FROZEN}` / `jsr CheckStatus / bcc @22e8` = always-hit. Macros: include/macros.inc:488; enums const.inc:1540/1582 |
| C2/467D / 4691 | `SetStatus_14:` / `SetStatus_19:` | 11594–11600 / 11618–24 | Stop `#$12→$3af1,y`; Freeze `#$22→$3f0d,y` — timer templates |
| C2/46B0 / 46F0 | `SetStatusTbl:` / `RemoveStatusTbl:` | 11661–11693 / 11696–11728 | 32-entry `.addr` tables; dispatch in `UpdateStatus:` 11032–88 |
| C2/4490 | `ApplyStatusMod:` | 11169–11201 | `@44bb` fire-thaws-Freeze 11191–99 — template for typed lifts |
| C2/5A83 | `DecCounters:` | 14839–14891 | tick `$3adc,x += $3add,x` 14853–57; **Stop dec 14858–63** — Broken timer dec goes beside it |
| C2/5B06 | `_c25b06:` wear-off | 14939–14963 | `$b8` bits 0–3 used, **4–7 free**; → `CreateImmediateAction` cmd `$29` |
| C2/4E91 / 5161 | `CreateImmediateAction:` / `Cmd_29:` | 12881–94 / 13335–67 | queue primitive / wear-off handler |
| C2/09D2 | `CalcSpeed:` | 1539–1571 | ATB constant (M2 BP timing) |
| — | `InitBattle:` | 6053–6067 | zeroes `$3A20–$3ED3`, $FF-fills `$2000–$341F` — auto-inits our RAM |
| — | `ExecAttack:` | 8015; msg pickup 8111–8118 | `$3401` ≠ $ff → battle-script cmd $02 (show message) |

## 2. Free battle RAM — verified unreferenced in all of src/ + include/

- **Three whole unused per-entity tables** (2 B/combatant, $14 stride):
  `$3E38–$3E4B`, `$3E88–$3E9B`, `$3E9C–$3EAF` → 60 bytes. Also `$3ECB–$3ED3`
  (9 global bytes). All zeroed each battle by `InitBattle`.
- Battle logic uses bare hex addresses (no RAM label file); only btlgfx has
  `src/btlgfx/btlgfx_ram.inc` ($7E4000+).

**OT6 allocation:** `$3E38,X` shieldCur · `$3E39,X` shieldMax · `$3E88,X`
brokenTimer · `$3E89,X` flags/revealed · `$3E9C/$3E9D,X` spare (M2 BP) ·
`$3ECB–$3ED2` display buffer (4 rows × 2 B).

## 3. Battle messages

- Text: `src/text/attack_msg_en.json` (256 entries). $09 "Can't run
  away!!"; $15–$1C weak-element msgs; **free slots $45–$93**. Encoded by
  tools/encode_text.py; placed by src/text/text_main.asm:295–318 (bank D1).
- Trigger A (inside attack): store index → `$3401` (see `AttackerEffect_4b`
  10559–67: `lda #$09 / sta $3401`).
- Trigger B (immediate): `Cmd_27` 13274–329 pattern — cmd `$02`→`$2d6e`,
  index→`$2d6f`, `$ff`→`$2d72`, vars `$2f35–$2f3a`, `lda #$04 / jsr
  ExecBtlGfx` (16369). Its weakness loop 13311–28 = copyable feedback code.
- Render: btlgfx `GfxCmd_02:` 22882–96 → `DrawDlgText:` 13905 (large font).
- **Large font already has element icon glyphs**: `{fire}`=$DC `{ice}`=$DB
  `{lightning}`=$D8 `{poison}`=$DE `{wind}`=$D9 `{holy}`=$D6 `{earth}`=$DA
  `{water}`=$DD — usable in messages today.

## 4. Monster-list window + targeting (display hooks)

- C2 feeds: `UpdateMonsterGfxBuf:` battle_main 15169+; `$200D–$2014` = 4
  rows × 2 B name-id (fill 15221–30); `$2015–$201C` alive-counts. Rows
  group identical monsters (aggregation rule needed for shields).
- C1 draws: `BtlGfx_06`/`UpdateMonsterNames:` btlgfx 319–337 (diffs `$200d`
  vs cache `w7eebff`); `DrawMonsterNames:` 10469; template `MenuText::_0:`
  45063–64 (`.byte $0b,slot,$ff,$01` × 4); **`MenuTextCmd_0b:` ~16048–90**
  draws 10 name chars + trailing `$ff` blank via `DrawMenuLetter:` 15494.
  Buffer `w7e5ad5` is 12 wide → 2 spare columns per row.
- **Insertion:** replace the trailing-blank source in `MenuTextCmd_0b` with
  our display buffer (`$3ECB+`) — digit glyphs $B4–$BD. Redraw is automatic
  when `$200d` changes; bump cache to force.
- Targeting: `_c17795:` ~18256 (state $38); `UpdateMenuState_38:` 16767+
  (masks `w7e7b7d/7b7e`); `DrawCursorSprites:` 26828.
- **Bank C1 slack is only $1B bytes** — C1-side shims must be a jsl or a
  few bytes; put logic in F0 or in `btlgfx_code_far` (bank C2, ~$5C9 slack
  after $C2FAA3).

## 5. Fonts / glyphs

- `src/gfx/font_gfx.asm`: `SmallFontGfx` = small_font_en.2bpp — **256 fixed
  8×8 2bpp tiles, glyph code == tile index** (battle menu text incl.
  monster list; DMA'd to VRAM $5800). `LargeFontGfx` = large_font_en.1bpp
  (16×11, 22 B/glyph, code−$80) for message window.
- Item-type icons (small font): $D8 dagger $D9 sword $DA spear $DB katana
  $DC staff $DD brush $DE star $DF special $E0 card $E1 claw $E2 shield
  $E3 helm $E4 armor $E5 tool $E6 scroll $E7 relic. Digits $B4–$BD. ATB
  gauge pieces $F0–$FA.
- **Free small-font cells (blank + unmapped): $D0, $D1, $EB–$EF, $FB–$FD**
  → element icons at $EB–$EF/$FB–$FD in element-bit order (fire→water).

## 6. Linker cfg facts

- `battle_code` floats from $C20000, ends $C26468 → **919 bytes ($397) of
  shim budget** before anything moves; overruns = hard ld65 error (pins at
  $8a70/$fc6d), never silent.
- bank_f0 spans $F0–$FF as one area — keep `ot6_code` under 64 KB (65816
  code can't cross bank boundary); split areas per-bank when needed.
- Header size byte already $0c (=4 MB); fix_checksum degenerates to plain
  sum at 4 MiB; ff6-en1 shares the cfg; ff6-jp.cfg not expanded (fine).

## 7. Gotchas

1. **Stale generated text includes** — CLOSED (re-verified during M3):
   `romtools.encode_text` ends by calling `update_array_inc` itself, so
   plain `make` regenerates `include/text/attack_msg_en.inc` together
   with the `.dat` whenever a message JSON changes. No extra wiring
   needed. Residual trap: calling `rt.encode_text` on a hand-built
   asset_def that still carries an `inc_path` (e.g. a sizing probe)
   rewrites the real include as a side effect — strip `inc_path` first.
2. Only `src/<mod>/<mod>_main.asm` is assembled per module — new files must
   be `.include`d from it (ot6.asm already is).
3. Cross-module entry points go in `include/code_ext.inc` (`.global`
   registry) — declare F0 entry points there for C2 and C1 to `jsl`.
4. C2↔C1 interface = shared `$2000–$2FFF` page + `ExecBtlGfx` cmd queue;
   btlgfx doesn't otherwise read `$3xxx`.
5. Match house style: `peaflg`/`setflg` macros, STATUS12/34 enums.
6. `src/text/*.dat` are build products; edit only `.json`.
