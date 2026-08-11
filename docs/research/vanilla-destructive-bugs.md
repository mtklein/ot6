# Research: vanilla destructive-bug inventory (issue #13)

Issue [#13](https://github.com/mtklein/ot6/issues/13) narrows the "Vanilla's
bugs stay" house rule: harmless quirks are preserved, but before a release
frontier reaches affected content we fix or explicitly accept vanilla defects
that can **crash, lock up, corrupt SRAM/save data, corrupt persistent game
state, cause unavoidable soft locks or progression loss, or produce arbitrary
memory effects with materially destructive outcomes**.

This document is the inventory. It is deliberately short. Per #13, "do not turn
this into a general folklore-driven bug-fix sweep."

## Method, and why the list is short

FF6 bug lore is enormous and much of it describes the **v1.1 (rev 1) US ROM**,
the Japanese ROM, or fan retranslations — not our base. OT6 builds US **1.0**:

- `Makefile:2` pins SHA-1 `4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.
- `ff6/Makefile:285` builds with `-D ROM_VERSION=0`, so
  `ff6/include/const.inc:30-34` sets `LANG_EN_REV1 = 0`.

Two rules were applied:

1. **Confirmed** means the defect is visible in instructions or data under
   `ff6/`, cited by file and line. Everything else is in
   [REPORTED, UNVERIFIED](#reported-unverified) with a note on what would
   settle it.
2. **Destructive** means it clears #13's bar. Being a bug is not enough.
   Cosmetic garbage, wrong tables that only change a shake pattern, dead code,
   and balance oddities stay.

### The single most useful evidence source

The vendored disassembly encodes every US rev-1 change as a
`.if LANG_EN_REV1` block. That is *Square's own list* of what they thought was
worth fixing between 1.0 and 1.1, expressed as code. There are exactly **12**
such sites, and all 12 are in one file:

```
$ grep -rn "LANG_EN_REV1" ff6/src/
ff6/src/btlgfx/btlgfx_main.asm:4229, 4261, 5102, 5125, 5166, 5188,
                               5199, 5255, 5291, 26319, 32872, 47880
```

Of those, **five** (`5188`, `5199`, `5255`, `5291`, `47880`) are the Sketch
guard and its supporting restructure; one (`32872`) is a raster-timing
hardening; the rest are a graphics-routine reorganization. Nothing outside
`btlgfx` was changed for rev 1. That is a strong negative result: the famous
"1.0 is the buggy one" reputation is, in code terms, almost entirely about the
Sketch path.

---

## Summary

Confirmed in source but **below the bar or not player-reachable** — recorded so
they are not rediscovered and re-argued:

| # | Defect | Why it does not qualify |
|---|---|---|
| 3 | `GetVeldtBattle` unbounded search loop (`ff6/src/field/battle.asm:269-283`) | Genuine no-termination loop, but no vanilla path reaches an all-zero Veldt bitmap. **Hazard for OT6 fixtures.** |
| 4 | `SetControlCmd` unguarded attacker index (`ff6/src/battle/battle_main.asm:8901-8908`) | Clean arbitrary-write primitive; vanilla AI data never reaches it. **Hazard for OT6 AI authoring.** |
| 5 | `BattleEnd_02` missing `bmi` guard (`ff6/src/battle/battle_main.asm:12067-12069`) | Would write into the party list / inventory; vanilla data makes Gau's presence certain. **Hazard for OT6 kit authoring.** |
| 6 | `OptimizeCharEquip` hang trap (`ff6/src/menu/equip.asm:1484-1493`) | Hard lockup; every vanilla call site adds the character to the party first. **Hazard for OT6 route authoring.** |
| 7 | `AnimCmd_f7` unsynchronized raster wait (`ff6/src/btlgfx/btlgfx_main.asm:32866-32893`) | Rev-1 code difference confirmed; the failure mode is not. Watch item. |
| 8 | Battle "items obtained" list under-cleared (`ff6/src/btlgfx/btlgfx_main.asm:2488-2492`) | Needs 13 item events in one battle. Not a state a player reaches. |
| 9 | Diagonal step skips the trigger / save-point clears (`ff6/src/field/player.asm:429-453`) | Real engine asymmetry; clears on the first orthogonal step; no destructive outcome shown. |
| 10 | `magic_tmp_buf_clr` wrong data bank (`ff6/src/btlgfx/btlgfx_main.asm:24634-24655`) | Zeroes 40 bytes of a graphics buffer. Cosmetic. |
| 11 | Misaligned NPC `branch` targets (`ff6/src/event/event_main.asm:4678` et al.) | Confirmed in data; scenes demonstrably complete. |
| 12 | `InitTask` / Colosseum self-branch hang traps | Confirmed traps, triggers undemonstrated; the Colosseum one is post-WoB. |
| 13 | `InitSkills` `$2020 = $ff`; `BitToTargetID` `Y = $fe` | One-byte out-of-bounds *reads*. No write, no fault. Cosmetic. |

Everything else that came up is in [REPORTED, UNVERIFIED](#reported-unverified).

---

## 3-13. Confirmed in source, below the bar (or not player-reachable)

Kept here so they are not re-discovered and re-argued later.

### 3. `GetVeldtBattle` is an unbounded search loop

`ff6/src/field/battle.asm:269-283`:

```
.proc GetVeldtBattle
        inc     $1fa5
        lda     $1fa5
        and     #$3f
        tax

; find a nonzero byte in the list of available veldt battles
Loop1:  lda     $1ddd,x
        bne     :+
        txa
        inc
        and     #$3f
        tax
        bra     Loop1
```

X is masked to 0..63 and the loop scans the 64-byte Veldt-availability bitmap
for a nonzero byte. There is no iteration counter and no fallback branch: with
an all-zero bitmap this spins forever. Entered from
`ff6/src/field/battle.asm:179-181` (`lda $24 / cmp #$ff / jeq GetVeldtBattle`).

The bitmap is zeroed on New Game (`ff6/src/field/init.asm:143-148` clears
`$1dc9-$1e1c`, which contains `$1ddd-$1e1c`) and bits are only ever *set*, at
`ff6/src/battle/battle_main.asm:12207-12219`, by essentially every ordinary
random encounter. By the time the Veldt is reachable the bitmap has dozens of
bits.

**Classification: confirmed no-termination loop, no vanilla path to it.** It is
a live hazard for **OT6 fixtures**, though: a savestate or frontier fixture
that warps a party onto a Veldt sector without the encounter history that
populates the bitmap hangs the headless test runner with no error — precisely
the "quiet test" failure mode `CONTRIBUTING.md` warns about.

### 4. `SetControlCmd` builds a WRAM write address from an unguarded index

`ff6/src/battle/battle_main.asm:8901-8908`:

```
SetControlCmd:
@372f:  phx
        phy
        php
        longai_clc
        lda     f:CmdPropPtrs,x
        adc     #$0030
        sta     f:hWMADDL
```

`CmdPropPtrs` is four words (`ff6/src/battle/battle_main.asm:13921-13922`):
`.word $202e,$203a,$2046,$2052`. X is the *attacker* index, taken at
`ff6/src/battle/battle_main.asm:9527-9528`. `TargetEffect_53` guards the
**target** (`cpy #$08 / bcc`, lines 9517-9518) but never the attacker. A
monster attacker (index `$08-$12`) indexes past the 8-byte table into
`RelicCmdTbl1`/`RelicCmdTbl2`/`InitCmdTbl`
(`ff6/src/battle/battle_main.asm:13927-13945`), producing an attacker-chosen
16-bit WRAM destination that then receives 12 bytes through `WMDATA`.

**Classification: confirmed arbitrary-write primitive, unreachable with vanilla
data.** The only way a monster runs a character command is AI command `$f4`
(`ff6/src/battle/battle_main.asm:4431-4434`, which does not validate the
command byte), and every vanilla `cmd` in `ff6/src/battle/ai_script.asm` is
`STEAL`, `CAPTURE`, `JUMP`, or `GP_RAIN`.

**This is the single most important entry for OT6.** OT6 authors enemy AI and
boss contracts through every remaining milestone. `cmd CONTROL` in an authored
script is an arbitrary WRAM write, silently.

### 5. `BattleEnd_02` calls `RemoveChar` without the guard its siblings use

`ff6/src/battle/battle_main.asm:12067-12069` and `11923-11928`:

```
BattleEnd_02:
@48e0:  ldx     $300b       ; gau character slot
        jsr     RemoveChar

RemoveChar:
@47e3:  phx
        lda     $3ed9,x     ; character number
        tax
        stz     $1850,x     ; remove character from party
```

`$300b` is `$ff` when Gau is absent, and the neighbouring end-of-battle handlers
*do* check for it (`ff6/src/battle/battle_main.asm:11972-11973` and
`11986-11987` both `bmi` after the load). With `$300b = $ff` the `stz $1850,x`
index comes from uninitialized battle RAM and can land anywhere in
`$1850-$194f` — through the party list and into the item inventory at `$1869`,
which is save-block data.

**Classification: confirmed missing check, unreachable with vanilla data.**
`$3a6e = $04` is set only by `TargetEffect_54` (Gau's Leap,
`ff6/src/battle/battle_main.asm:9626-9627`), Leap is command `$11` with flags
`NONE` in `ff6/src/battle/battle_cmd_prop.asm:95-96` (not Gogo-assignable, not
Mimic-able), and the confusion table cannot select it. So Gau's presence is
guaranteed — by data, not by code. Another hazard for OT6 kit authoring, though
OT6 has retired Leap outright (`docs/design/kits.md`).

### 6. `OptimizeCharEquip` has a hard hang trap

`ff6/src/menu/equip.asm:1484-1495`:

```
OptimizeCharEquip:
@96d2:  jsr     InitCharProp
        clr_ax
        lda     w0201
@96da:  cmp     zCharID,x
        beq     @96e6
        inx
        cpx     #4
        bne     @96da
@96e4:  bra     @96e4                   ; infinite loop
```

Reached from event command `$9c` (`ff6/src/field/event.asm:3674-3681`). If the
named character is not in one of the four active party slots, the game hangs
hard — reset, and everything since the last save is gone.

Vanilla never triggers it: both real call sites do `char_party X, 1`
immediately before (`ff6/src/event/event_main.asm:15933-15934` at the Figaro
Tentacles scene, `ff6/src/event/event_main.asm:88180-88184` at Terra's
flashback). The only other uses are in the DEBUG new-game block
(`ff6/src/field/init.asm:313-316`, inside the `.if ::DEBUG` branch).

**Classification: not a vanilla defect for #13's purposes. It is an authoring
hazard for OT6.** Any OT6 route change that reorders party composition around
an `opt_equip` is a hard lockup, not a visible glitch. Worth a line in the
route-authoring notes.

### 7. `AnimCmd_f7` raster wait is unsynchronized in 1.0

`ff6/src/btlgfx/btlgfx_main.asm:32866-32893`. Rev 1 added a vblank-clear and
hblank-edge wait before latching the H/V counters; 1.0 latches immediately:

```
@db50:  lda     f:hSTAT78
        lda     f:hSLHV
        lda     f:hOPVCT
        cmp     [$5b]
        bcc     @db50
```

The code difference is certain. The *consequence* is not established from
source — an unstable latch could in principle spin this loop. **Classification:
unverified effect.** To settle: instrument the loop's iteration count in Mesen
across a battery of animations that use command `$f7`. Until then this is not
an inventory item, it is a watch item.

### 8. Battle "items obtained" list is under-cleared

`ff6/src/btlgfx/btlgfx_main.asm:2488-2492`, upstream-annotated:

```
@12d1:  sta     w7e602d,x
        inx
        cpx     #$0040      ; should be #$0050 *** bug ***
        bne     @12d1
```

The obtained-items list is 16 entries × 5 bytes = `$50`; only `$40` is
initialized to `$ff`. The consumer
(`ff6/src/btlgfx/btlgfx_main.asm:9463-9509`) indexes `(counter & $0f) * 5` and
stops at the first `$ff`, so entries 13-15 are only read after 13 real item
events in one battle, and an uninitialized non-`$ff` byte there would be added
to the inventory as a real item with a garbage quantity — persistent, and
saved.

**Classification: confirmed defect, below the bar on reachability.** Thirteen
item events in a single battle is not a state a player reaches. Worth a note
because OT6's steal/drop authoring could in principle raise the event count.

### 9. Diagonal movement skips the trigger and save-point clears

The orthogonal "party moved" path clears both latches and rechecks NPCs —
`ff6/src/field/player.asm:519-540`:

```
@4a03:  jsr     IncSteps
        jsl     DoPoisonDmg
        ...
        lda     $1eb6                   ; clear tile event bit
        and     #$df
        sta     $1eb6
        lda     $1eb7                   ; clear save point event bit
        and     #$7f
        sta     $1eb7
        jsr     UpdateOverlay
        jsr     CheckNPCs
```

The diagonal-movement path (`ff6/src/field/player.asm:429-453`) takes a real
step — `sta $0886,y`, `jsr IncSteps`, `jsr UpdatePartyFlags` — but omits the
`$1eb6` clear, the `$1eb7` clear, `CheckNPCs`, and `DoPoisonDmg`.

`$1eb7` bit 7 is event switch `$01BF`, the sole input to the Save/Tent gate
(`ff6/src/field/menu.asm:229-235`, `ff6/src/menu/field_menu.asm:3642-3643`), so
stepping off a save point diagonally leaves Save enabled off the save point.
`$1eb6` bit 5 is `$01B5`, a single latch shared by every tile trigger on every
map, so a stuck value suppresses the next trigger walked onto.

**Classification: confirmed asymmetry, below the bar.** Both latches clear on
the first orthogonal step, and neither outcome is destructive — FF6 already
permits saving anywhere on the world map. No progression-loss path was found.

### 10. `magic_tmp_buf_clr` writes to the wrong bank

`ff6/src/btlgfx/btlgfx_main.asm:24634-24655`, upstream-annotated (the wrong-bank
`stz` is line 24647). The routine
sets DBR = `$7f`, clears `$7fe400-$7ff7ff`, then does four `stz` sequences
intended for `$7e7b3f/7b49/7b53/7b5d` (damage-numeral thread state,
`ff6/src/btlgfx/btlgfx_ram.inc:553-556`) **without restoring the bank**. Two
effects: the numeral state is not cleared, and 40 bytes of `$7f7b3f-$7f7b66`
are zeroed — which per `ff6/notes/battle-ram.txt:2189` is inside
"$7F6000-$7F7FFF Character 4 Graphics".

**Classification: cosmetic, below the bar.** Recorded because it is a live
trap for OT6's "Claiming RAM" rule: anything OT6 ever parks at
`$7f7b3f-$7f7b66` will be zeroed at unpredictable times by vanilla code.


### 11. Misaligned NPC object-script branch targets

Five upstream-annotated sites where an object script branches to
`label := * - 1`, i.e. one byte before the intended instruction:
`ff6/src/event/event_main.asm:4678` (the Blackjack kidnapping — v0.5 content),
`11318`, `11321`, `35144`, `94287`.

**Classification: confirmed in data, below the bar.** These are async NPC
animation scripts; the scenes demonstrably complete in the retail game. No
evidence of a lock. Recorded so nobody "fixes" them and changes scene timing.

### 12. Two more self-branch hang traps

- `ff6/src/menu/menu_common.asm:3129-3139` — `InitTask` falls into
  `@11ad: bra @11ad` when no free task slot exists at a priority level (64
  slots). Trigger not demonstrated.
- `ff6/src/menu/colosseum.asm:313-326` — the Colosseum "draw Shadow's name"
  routine hangs if Shadow is not found among the 16 character-prop entries.
  Post-WoB, outside the supported route.

Both are confirmed traps with undemonstrated triggers. Not inventory items;
watch items.

### 13. Two one-byte out-of-bounds reads

Both are reads, not writes, and neither faults. Listed so they are on record.

- **`InitSkills` underflows the SwdTech count.**
  `ff6/src/battle/battle_main.asm:14528-14532` does `CountBits` then `dex`, and
  `CountBits` (`ff6/src/battle/battle_main.asm:13506-13512`) returns X = 0 for
  A = 0, so with no SwdTechs known `$2020` becomes `$ff`. The consumer
  (`ff6/src/btlgfx/btlgfx_main.asm:10433-10444`, duplicated at `10208` and
  `19080`) computes `7 - $2020` and walks 8 bytes of the 15-byte `_c2a860`
  palette table (`ff6/src/btlgfx/btlgfx_main.asm:38647-38649`), reaching one
  byte past it. Cosmetic; affects every battle before Cyan learns a tech.
- **`BitToTargetID` returns `Y = $fe` on an empty mask.**
  `ff6/src/battle/battle_main.asm:13486-13496` — the scan falls out with
  X = `$fe`. Every caller pre-checks the mask except `AttackerEffect_2a`
  (Flare Star, `ff6/src/battle/battle_main.asm:10659-10673`), which then does
  `lda $3b18,y` out of range and calls `Div` with a zero divisor. The SNES
  divider returns `$ffff` rather than faulting. Bad damage number at worst.

---

## Explicitly preserved (the other half of the policy)

#13 says the policy must not create an expectation that every harmless vanilla
bug gets modernized. Named examples, so the boundary is on record:

- **Vanish + Doom/X-Zone/Demi on bosses.** A balance exploit. #13 lists "minor
  balance oddities" as preserved.
- **Useless / mis-wired stats.** `CONTRIBUTING.md` already names these.
  Note: the common claim that Evade is *never* read is not what the code shows
  — `ff6/src/battle/battle_main.asm:6016` reads `$3b54` (evade) or
  `$3b55` (mblock) depending on carry. Whatever the truth is, it is benign and
  out of #13's scope; recorded here only so the folklore version doesn't get
  written down as fact.
- **Row jank, animation quirks, the "Ragers" text-erase bug**
  (`ff6/notes/ff3u.asm:98592-98593`), the screen-shake wrong-table bug
  (`ff6/src/field/screen.asm:1134`, upstream-annotated
  `should be ShakeFreqTbl`), the WoR cutscene off-by-one at
  `ff6/src/cutscene/ruin.asm:703`.
- **Dance's can't-stop-dancing lock** — already an explicit OT6 design
  decision, priced into the MP economy (`docs/design/mp-economy.md`, the Dance
  row of "The verb survey" — one payment per battle, not per step). It is
  a within-battle state, not a soft lock.
- **Leap removing Gau.** Not a defect; and vanilla already guards the
  degenerate case — `TargetEffect_54` refuses Leap when fewer than two party
  members remain (`ff6/src/battle/battle_main.asm:9614-9620`).

---

## OT6-side findings (not vanilla, found in passing)

Three things turned up here that are OT6's, not Square's, and belong in
the record.

1. **`OT6_LOADOUT` survives a New Game.** `ff6/src/battle/ot6_memory.inc:38`
   puts Cyan's Bushido loadout word at `$7e1e1d`. It is correctly inside the
   checksum window (asserted at `ot6_memory.inc:39-40`), but it is cleared by
   nothing:
   - `InitNewGame`'s event-flag clear is `ff6/src/field/init.asm:143-148`,
     `stz $1dc9,x` for `$0054` bytes — `$1dc9` through `$1e1c`. `$1e1d` is the
     very next byte.
   - `ClearRAM` at reset only covers `$7e0000-$7e11ff`
     (`ff6/src/field/reset.asm:758-768`, `ldx #$0120` × 16 bytes).
   
   So: load a save with a manual loadout → soft reset → New Game inherits the
   previous game's loadout. Bounded in effect, because the battle-side read
   validates each stored tech and falls back to AUTO
   (`ff6/src/battle/ot6_kits.asm:69-74`). Config hygiene, not a soft lock — but
   it is exactly the class of thing #13's "persistent game-state" clause is
   about, and it is ours.

2. **The codex commits to SRAM outside the save transaction.**
   `ff6/src/battle/ot6_break.asm:876` and `:984` write `f:OT6_CODEX` /
   `f:OT6_CODEX_CLASS` the instant a weakness is learned, mid-battle. Weakness
   knowledge therefore survives a reset-without-saving and survives a party
   wipe, diverging from the checksummed block it nominally belongs to. That may
   well be the intended product behaviour — it is worth being deliberate about
   rather than incidental.

3. **`ClearSRAM` does not reach bank `$31`.** `ff6/src/menu/menu_sram.asm:30-45`
   zeroes `$306000-$307fff` only, so a cartridge-level SRAM wipe leaves the
   codex pages intact. Recovery then rests entirely on the per-page `'O8'`
   magic (`ff6/src/battle/ot6_codex.asm:33 (constant), :62-101 (ensure)`). Not reachable in practice —
   bank `$30` is wiped, so no slot can be loaded — but the two banks have no
   shared validity story, and adding one is cheap while the codex is young.

Also noted: `ff6/src/menu/save.asm:50` adds `sta wSaveSlotToLoad` inside
`CopyGameDataToSRAM`. Vanilla set that variable only on *load*. The effect is
that after a New Game's first save, a party wipe now reloads that slot instead
of resetting to the title. Coherent with the codex lifecycle and arguably
better, but it is a real behaviour change and should be deliberate.

---

## REPORTED, UNVERIFIED

Claims that circulate but that this pass could **not** confirm from `ff6/`.
None of these should be treated as facts, cited, or fixed on this basis.

| Claim | What was read | Why it is unresolved / what would settle it |
|---|---|---|
| The v1.0 raster-wait causes real hangs | `ff6/src/btlgfx/btlgfx_main.asm:32866-32893` | The rev-1 code difference is confirmed; the failure mode is not. Instrument the loop in Mesen across `$f7`-using animations. |
| "Psycho Cyan" / SwdTech charge-gauge lockup | `ff6/src/battle/ot6_boost.asm:583`, `ff6/src/btlgfx/btlgfx_main.asm:19095-19100`, `RandBushido` at `ff6/src/battle/battle_main.asm:881-891` | **Cannot be audited in this tree — OT6 deleted the vanilla charge gauge in v0.3.** What survives is safe: `RandBushido` turns `$2020 = $ff` into `$00` via `inc` and `RandA` returns 0 for A = 0. Settling the vanilla claim needs the pre-OT6 `UpdateMenuState_37` body out of git history. Moot for OT6 either way. |
| Sketch "requires Vanish" / a specific setup | `ff6/src/battle/battle_main.asm:9566-9601` | The code shows *any* non-success exit leaves `$b7 = $ff`. The folklore setups are probably ways to *guarantee* failure, not preconditions. A forced-miss trace settles it. |
| `stx $2020` in `InitSkills` clobbers `$2021` as a 16-bit store | `ff6/src/battle/ot6_kits.asm:28-33` asserts it does; `InitBattle`'s `shortai` at `ff6/src/battle/battle_main.asm:6099` and the `php`/`plp` pairs in `LoadBattleProp`, `InitParty`, `InitInventory` suggest i8 is restored | Unresolved statically. `UpdateEquipBattle` (`ff6/src/battle/battle_main.asm:6807`) has no `php`/`plp` and is the likeliest leak. Needs an emulator watch on `$2020`/`$2021` right after `c2/5828`. |
| "Evade is never used" | `ff6/src/battle/battle_main.asm:6016` | Contradicted at first reading — `$3b54` (evade) *is* loaded, conditionally on carry. Benign either way; recorded so the folklore version does not get written down as fact. |

### Folklore checked and found **absent** (negative results worth keeping)

Each of these was read and the bound verified. None is a defect.

- **Dance "wrong dance" corruption.** `$32e1,y` is bounded to 0..7 on every
  path (`ff6/src/battle/battle_main.asm:941-946`, `14537-14546`, `12780-12781`);
  `DanceBG` has 10 entries, `DanceProp` 32 bytes, `BattleBGDance` 64 entries.
- **Sketch/Control/Rage "random command" wild jump.** All three funnel through
  `_c21554` → `GetCmdForAI` (`ff6/src/battle/battle_main.asm:5079`), which
  can only return a byte from an 11-entry table (max `$1d`) or the default
  `$02`. `CmdTbl` has 51 entries.
- **Rage-list / `MonsterRage` overrun.** `RandRage`'s scan is bounded by 8-bit X
  wrap; `MonsterRage` is exactly 256 × 2 bytes; `LearnRage`
  (`ff6/src/battle/battle_main.asm:12389`) rejects monster IDs ≥ 256, so
  the `$1d2c` bitfield cannot spill into the known-dances field at `$1d4c`.
- **Control / Sketch monster-index overrun.** `MonsterControl` is 384 × 4,
  `MonsterSketch` 384 × 2, `MonsterSpecialAnim` 384 bytes; max monster ID
  `$17f` keeps every `asl2`/`rol` in range.
- **Metamorph.** `TargetEffect_12` masks `and #$1f` then two `rol`s → 0..127
  into a 128-byte table, and `lsr5` → 0..7 into an 8-byte rate table.
- **Slot / Joker Doom.** `_c2b4a3` returns only 0..7; the computed
  `sta $b8,x` is guarded by `cpx #$02`.
- **Mimic on turn one.** `InitRAM` zeroes `$3ee4-$3f43` and seeds
  `$3f28 = $3f24 = $12`, so a first-turn Mimic replays Fight with no targets
  rather than reading stale data.
- **GP Rain divide-by-zero.** Real (`ldx $3ec9 / jsr Div`), but the SNES divider
  returns `$ffff` for a zero divisor rather than faulting.
- **Empty or invalid party from an event script.** A sweep of every labelled
  block in `ff6/src/event/event_main.asm` found no `char_party X, 0` that is not
  bracketed by an add. `party_chars` only rewrites slot aliases — it is not a
  membership command.
- **`EventCmd_99` crashing on zero parties.** Documented at
  `ff6/src/field/event.asm:3622`, but no call site passes 0; the script only
  ever uses 1, 2, or 3.
- **Vehicle/world-state desync.** The airship's world position is copied from
  its sprite on landing (`ff6/src/world/init.asm:1899-1904`); the WoB ground
  entrance is unambiguous because `switch $009D=1` is written exactly once, at
  the WoB→WoR transition.
- **A WoB save point past a point of no return.** All 38 `SavePoint` triggers
  were enumerated. The Floating Continent save point shares its map with an
  unconditional "return to the airship" exit trigger; the Lete River save points
  sit in a loop that re-boards the raft.
- **The Floating Continent countdown surviving Game Over.** `GameOver`'s
  timer-skip guards (`ff6/src/event/event_main.asm:113076-113083`) test event
  bits `$02ab-$02ae` that are never written anywhere, so the timers always stop.
