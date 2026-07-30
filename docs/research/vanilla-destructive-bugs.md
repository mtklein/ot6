# Research: vanilla destructive-bug inventory (issue #13)

Status: research only. Nothing here changes behavior. Started 2026-07-26.

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

## Frontier map (summary)

**Two** defects clear #13's bar:

| # | Defect | Class | Reachable via | Frontier | Verdict |
|---|---|---|---|---|---|
| **1** | **Sketch graphics-index escape** | arbitrary WRAM write → save corruption / crash | Relm, `Sketch`, any battle | **v0.8 (Thamasa)** | **Meets the bar analytically; ships as-is by owner decision (§1)** |
| **2** | **Save-slot checksum `$0000` reads as "empty slot"** | save loss: slot unloadable, then silently overwritten | any save, ~1 in 65 536 | **v0.1 (already shipped)** | **Meets the bar. Needs a decision now, not at v0.8.** |

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

## 1. The Sketch bug — stays vanilla, by owner decision

> **Owner decision (2026-07-28): Sketch ships unfixed.** #13/#28 briefly
> made a fix a v0.8 release gate; that reversed the owner's standing
> "vanilla's bugs stay" call without sign-off and was itself reversed.
> v0.8 documents the bug in its release notes instead. The analysis below
> stands as analysis — severity, reachability, and fix options — so the
> decision stays an informed one, and so nothing here needs re-deriving if
> playtesting ever reopens it.

This is the one #13 names, and it is real, it is severe, and the whole chain is
readable in the vendored source. It is also *not* what most write-ups say it
is: it is not a battle-logic bug at all. It is a **battle-graphics** bug, and
Square fixed it in rev 1 with a two-instruction guard.

### The chain, instruction by instruction

**(a) `$b7` is seeded with `$ff` and only corrected on success.**

`ff6/src/battle/battle_main.asm:3327-3333`:

```
Cmd_0d:                          ; command $0d: sketch
@151f:  tyx
        jsr     _c2298a
        lda     #$ff
        sta     $b7              ; <-- line 3320
        lda     #$aa             ; special effect $55 (sketch)
        sta     $11a9
        jsr     ExecAttack
```

`$b4`-`$b7` are the four bytes of a battle-script command. `$b7` is overwritten
with a real value **only** on the success path of the sketch target effect —
`ff6/src/battle/battle_main.asm:9579-9586`:

```
        jsr     CheckSketchHit
        bcs     _c23b1b          ; miss -> bail, $b7 stays $ff
        sty     $3417
        tya
        sbc     #$07
        lsr
        sta     $b7              ; <-- line 9585: monster slot 0..5
        jsr     _c235bb          ; rewrite the queued script command in place
```

Every other exit from `TargetEffect_55` leaves `$b7 = $ff`: a failed
`CheckSketchHit` roll (line 9580), a target flagged unsketchable
(`ff6/src/battle/battle_main.asm:9572-9574`), and a target that is a *character*
rather than a monster (`cpy #$08 / bcc`, lines 9570-9571).

**(b) The command is queued with whatever `$b7` holds.**

`_c235d4` copies `$b4`/`$b6` as two 16-bit words into `$3a28`/`$3a2a`
(`ff6/src/battle/battle_main.asm:8608-8617`), and `_c2629e` writes those into
the battle script queue at `$2d6e`
(`ff6/src/battle/battle_main.asm:16189-16204`). `ExecAttack` queues the attack
message at `ff6/src/battle/battle_main.asm:8217` *before* target effects run,
which is why the success path at 9586 rewrites it in place.

**(c) The graphics engine walks that queue and reads byte 3 as an entity index.**

`ff6/src/btlgfx/btlgfx_main.asm:22392-22414` sets `$76 = $2d6e` and steps it by
4 per command, so `($76),3` **is** `$b7`.

`ff6/src/btlgfx/btlgfx_main.asm:47870-47895` — battle animation init `$2f`, the
sketch animation. The rev-1 fix is the middle block:

```
AnimType_2f:
@f5d2:  ldy     #$2800
        jsl     ClearBG1TargetTiles_far
        lda     w7e898d
        and     #$fe
        sta     w7e898d
        ldy     #3
        lda     ($76),y          ; <-- $b7

.if LANG_EN_REV1                 ; ***** NOT BUILT IN US 1.0 *****
        bpl     @f5e6
        ldx     #$ffff
        bra     @f5f1
.endif

@f5e6:  asl                      ; US 1.0 falls straight through
        tax
        longa
        lda     $2001,x          ; monster index array is $2001..$200c
        tax
        shorta0
@f5f1:  jsl     LoadSketchMonsterGfx
```

The rev-1 guard is `bpl` — it rejects exactly the case where byte 3 has bit 7
set, which is exactly `$ff`. That is conclusive: the value Square guarded
against is the `lda #$ff / sta $b7` at `battle_main.asm:3330-3331`.

In US 1.0, `$ff` is doubled to `$fe` and used as an index into a **six-entry**
array. `tax` here runs with 8-bit A and 16-bit X, so `X = (B << 8) | $fe`
where `B` is the accumulator's hidden high byte. For any small `B` the read
lands in the **character battle spell lists** at `$208e-$257d`
(`ff6/notes/battle-ram.txt:444-452`; built at
`ff6/src/battle/battle_main.asm:14228-14285`). With `B = 0` it is `$7e20ff`,
which is *byte 1 of spell-list entry 28* — the "disabled because MP is too low"
flag — with the entry's targeting byte above it. The resulting 16-bit garbage
becomes the monster graphics index.

`B` is not pinned from source alone; `ClearBG1TargetTiles` (line 26260) leaves
a 16-bit value in A. See [what would settle it](#what-would-settle-the-remaining-sketch-questions).

**(d) The garbage index reads a garbage 5-byte graphics record.**

`LoadEsperGfxProp`, `ff6/src/btlgfx/btlgfx_main.asm:5287-5300` — the second
rev-1 guard:

```
@24f5:  longa
        lda     $10
.if LANG_EN_REV1                 ; ***** NOT BUILT IN US 1.0 *****
        cmp     #$ffff
        bne     @24f9
        clr_a
.endif
@24f9:  asl2
        clc
        adc     $10              ; index * 5
        tax
        lda     f:MonsterGfxProp+2,x
        ...
        lda     f:MonsterGfxProp+4,x
        sta     w7e81aa          ; graphics map ("stencil") number
```

A third rev-1 guard sits in `LoadSketchMonsterGfx` itself
(`ff6/src/btlgfx/btlgfx_main.asm:5252-5266`), and a fourth restructures
`LoadSummonGfx` to preserve X across the call
(`ff6/src/btlgfx/btlgfx_main.asm:5186-5210`).

**(e) A degenerate stencil sets a loop counter to zero, and the loop runs 256
times.**

`InitStencil`, `ff6/src/btlgfx/btlgfx_main.asm:4735-4764`:

```
@21b8:  ldx     $00
        longa
        stz     $10
@21be:  lda     w7e822d,x        ; one row of stencil bits
        beq     @21ce            ; first row empty -> leave with X = 0
        ...
@21ce:  ...
        shorta0
        txa
        lsr
        cmp     w7e8257
        bcc     @21ee
        lda     w7e8257
@21ee:  sta     w7e8253          ; row count -- can be 0
        lda     $12
        inc
        cmp     w7e8256
        bcc     @21fc
        lda     w7e8256
@21fc:  sta     w7e8251          ; column count -- can be 0
        sta     w7e8252
```

If the garbage stencil's first row word is zero, `X` is still 0 when the loop
exits, `0 < w7e8257` so the clamp is skipped, and the **row counter is 0**.

`LoadMonsterGfx`, `ff6/src/btlgfx/btlgfx_main.asm:4854-4879`:

```
@22a5:  ldy     $00
@22a7:  jsr     CheckMonsterStencilBit
        ...
@22bc:  dec     w7e8252
        bne     @22a7            ; 0 -> $ff -> 256 columns
        ...
        lda     $61
        clc
        adc     #$0200           ; advance the destination 512 bytes per row
        sta     $61
        shorta0
        dec     w7e8253
        bne     @22a5            ; 0 -> $ff -> 256 rows
```

Both counters are 8-bit `dec`/`bne`. Zero means 256 iterations. The destination
`$61` starts inside the monster graphics buffer, which
`ClearMonsterGfxBuf` (`ff6/src/btlgfx/btlgfx_main.asm:4513-4520`) establishes as
`$7eae3f`, `$2000` bytes. 256 rows × `$0200` = `$20000` — **the destination
sweeps the whole of bank `$7e`, twice.** `LoadMonsterGfxTile`
(`ff6/src/btlgfx/btlgfx_main.asm:4792-4852`) does the writing via `sta ($10)`
with DBR = `$7e`.

**(f) That bank is the save block and the battle inventory, and both get
written out.**

Bank `$7e` holds:

- `$1600-$1fff` — the save block (`ff6/notes/battle-ram.txt:406`), which
  includes OT6's Bushido loadout word at `$7e1e1d`
  (`ff6/src/battle/ot6_memory.inc:38-40`).
- `$2686-$2b85` — the battle inventory, 256+8 items × 5 bytes
  (`ff6/notes/battle-ram.txt:455-457`).
- `$1508-$15ff` — the CPU stack (`ff6/notes/battle-ram.txt:404`).

At end of battle, `ff6/src/battle/battle_main.asm:12157-12193` copies character
HP/MP/status into `$1609/$160d/$1614` and the whole battle inventory into
`$1869`/`$1969`:

```
@4987:  lda     $2686,y          ; copy item number      <- line 12170
        sta     $1869,x
        inc
        beq     @4993
        lda     $2689,y          ; copy item quantity
@4993:  sta     $1969,x
```

So graphics bytes written over `$2686` become the party's actual inventory, and
the next save writes them to SRAM. That is the mechanical explanation for the
glitch's folklore reputation for spawning items — and for eating saves. Writes
landing on the stack at `$1508-$15ff` are the crash case.

### Reachability

Command `$0d` (Sketch) is granted to exactly one character — Relm, character
prop 8, `ff6/src/field/char_prop.asm:236-244`:

```
; 8: relm
        make_char_prop
        set_char_prop_hp_mp 37, 18
        set_char_prop_cmds FIGHT, SKETCH, MAGIC, ITEM
```

No monster AI path can produce command `$0d` — `GetCmdForAI`
(`ff6/src/battle/battle_main.asm:5079`) can only return the eleven values
in `CmdForAITbl`, and `$0d` is not among them. `AnimType_2f` is reached only
from `CmdAnim_0d`, which is reached only from the Sketch command. So the
frontier is precisely **Relm joining at Thamasa — v0.8**
(`docs/design/wob-route.md:54`), which is exactly the milestone on #13.

Sketch also becomes equippable in the World of Ruin (Gogo). That is past
v0.9 and outside the supported route, but it means the fix cannot be scoped as
"Relm-only" if the WoR is ever supported.

For completeness, this is the *only* unvalidated entity-index-to-graphics path
in the battle graphics module. Its nearest sibling, `LoadTrainGfx`
(`ff6/src/btlgfx/btlgfx_main.asm:40134-40141`), does the same `lda $2001,x /
tax` and then range-checks with `cpx #$0106` before using the result.

### Severity is data-dependent, and that matters

Only step (e) escalates. If the garbage record happens to yield a stencil whose
first row is non-empty, both counters are clamped to at most 16 and the writes
stay inside the `$2000`-byte buffer — the player sees a corrupt sprite and
nothing else. This is why the same input produces "nothing happened", "I got
99 Ribbons", and "it froze" in different reports. It is one bug with a payload
selected by whatever record the index lands on.

### What OT6 changes about it

- **The index payload moves.** The garbage index is read out of character
  spell-list RAM (`$208e`+). OT6's live per-ability MP costs (v0.5) drive the
  "disabled" flag byte at exactly that offset
  (`ff6/src/battle/battle_main.asm:14228-14285` writes spell index / disabled
  flag / targeting / MP cost per entry), and OT6's kit rework changes which
  spell sits in each slot. OT6 therefore does not inherit vanilla's *specific*
  garbage — it inherits the mechanism with a different payload. Nothing about
  OT6 makes the bug safer; it makes vanilla-derived reports about *what it
  does* inapplicable.
- **The blast radius now includes OT6 state.** `OT6_LOADOUT` at `$7e1e1d` sits
  inside the save block and inside the checksum window
  (`ff6/src/battle/ot6_memory.inc:38-40`). The weakness codex lives in expanded
  SRAM bank `$31` (`ff6/src/battle/ot6_memory.inc:23-35`), which a bank-`$7e`
  sweep does not reach directly.
- **Two design docs currently say the opposite of #13** and must be reconciled
  before v0.8:
  - `docs/design/kits.md:708` — "Sketch ✦ signature (bug preserved ✦ — it
    eats a save now and then, and that's canon)".
  - `docs/design/mp-economy.md:315` — "the Sketch bug stays (house rule) and
    does not refund".
  - `CONTRIBUTING.md` "House rules" names the Sketch bug as charm.

### Fix and mitigation options

Ordered by how narrow they are.

**Option A — make `$b7` always valid (narrowest, battle-side, no graphics
work).** The graphics engine is only unsafe because it is handed `$ff`. Set
`$b7` to the target's monster slot on *every* exit from the sketch path, not
just success, so `AnimType_2f` always loads a real on-screen monster. This is
a hook OT6 already knows how to place (bank `$f0` shim off `Cmd_0d` /
`TargetEffect_55`), touches no `btlgfx` code, and costs no bank `$c1` space.
Caveat to verify first: `$b7` is also the second message parameter in the
queued script command, so a changed value must be checked against the
"couldn't be sketched" / miss message rendering
(`ff6/src/battle/battle_main.asm:9757-9758` sets `$3401 = $1f`).

**Option B — backport Square's rev-1 guard.** Semantically the safest, because
it is the vendor's own fix and rev 1 shipped with it. The obstacle is space:
`AnimType_2f` is in bank `$c1`, which `CONTRIBUTING.md` records as 100% full.
It does not need new space, though — the six instructions at
`btlgfx_main.asm:47888-47893` (`asl / tax / rep #$20 / lda $2001,x / tax /
shorta0`) occupy 11 bytes, enough for a `jsl` into bank `$f0` plus padding. The
bank-`$f0` routine does the validated version of those six instructions and
returns `$ffff` for a bad index; `LoadEsperGfxProp` then needs its own
`cmp #$ffff` guard, which is a second small shim.

**Option C — redesign Sketch as an OT6 ability.** Relm's kit is explicitly TBD
(`docs/design/kits.md:708`), and OT6 has already retired far more
entrenched vanilla verbs — Cyan's charge gauge, Sabin's fighting-game Blitz
input, Gau's Leap and berserk Rage
(`docs/ROADMAP.md` M4, `docs/design/kits.md`). If Relm's Sketch is going to be
rebuilt in bank `$f0` for the chance-verb boost canon anyway
(`docs/design/kits.md:686`: "Sketch (Relm), Slot (Setzer), and Rage (Gau)
answer to the SAME rule"), then the vanilla path stops being reachable and the
bug is fixed as a side effect of work already planned.

**Recommendation.** Sketch is fixable narrowly — the defect is one unvalidated
byte, and Square's own fix is two instructions. It does **not** need a
redesign to be made safe. But because Relm's kit is unwritten and Sketch is
already slated for the chance-verb treatment, Option C likely gets the fix for
free; Option A is the cheap insurance to land first, so the frontier is safe
even if Relm's kit slips. Either way the positive-control regression is the
same and should be built before the fix: a test that drives a *failing* Sketch
and asserts the queued script command's byte 3 is never negative when
`AnimType_2f` runs.

### What would settle the remaining Sketch questions

Three things are inferred rather than read, and all three are cheap to pin with
a Mesen watch on a forced-miss Sketch:

1. **The value of `B` at `btlgfx_main.asm:47889`**, which fixes exactly which
   address the `lda $2001,x` reads. Watch `X` at that instruction.
2. **How often step (e) escalates** — i.e. the distribution of stencil first-row
   words across the records the index can select. Watch `w7e8253`/`w7e8251`
   after `InitStencil` and flag zero.
3. **Whether the sketch animation is queued on every miss.** `CmdAnim_0d`
   (`ff6/src/btlgfx/btlgfx_main.asm:27528-27534`) has no targets-hit check,
   unlike its neighbours (compare `CmdAnim_16` at
   `ff6/src/btlgfx/btlgfx_main.asm:27540-27560`, which does test targets),
   which is good evidence it always runs — but "good evidence" is not a trace.

---

## 2. Save-slot checksum `$0000` reads as an empty slot — already shipped

The second defect that clears the bar, and unlike Sketch it is live in every
release we have tagged. It is a save-loss bug, not a corruption bug: the data
is intact on the cartridge and the game refuses to see it.

### The mechanism

A save slot is a verbatim `$0a00`-byte image of the live block `$7e1600-$7e1fff`
(`ff6/src/menu/save.asm:42-79`). Its integrity check is a plain 16-bit sum of
the bytes `$1600-$1ffd`, stored at `$1ffe`:

`ff6/src/menu/save.asm:745-759`:

```
CalcSaveSlotChecksum:
@19d1:  stz     $e7
        stz     $e8
        ldx     z0
        clc
@19d8:  lda     $1600,x
        adc     $e7
        sta     $e7
        clr_a
        adc     $e8
        sta     $e8
        inx
        cpx     #$09fe
        bne     @19d8
```

The problem is the *verifier*, `ff6/src/menu/save.asm:767-776`:

```
CheckSaveSlotChecksum:
@19eb:  longa
        lda     $e7
        cmp     $1ffe
        bne     @19f6                   ; return 0 if invalid
        bra     @19f7                   ; return checksum value if valid
@19f6:  clr_a
@19f7:  tay
        shorta
        rts
```

It returns the **checksum itself** as the validity token, and zero for invalid.
There is no separate flag. Every consumer then tests that token with
`beq`/`bne`:

- `ff6/src/menu/save.asm:280-281`, `301-302`, `322-323` cache it in `$91`/`$93`/`$95`
  and draw the slot as `SaveSlot<n>EmptyText` when it is zero.
- `ff6/src/menu/field_menu.asm:2902-2903` — the **load** path:
  `ldy $91,x / beq @2a00`, i.e. refuse.
- `ff6/src/menu/field_menu.asm:1981-1988` — the **save** path:

```
        ldy     $91,x                   ; sram checksum
        bne     @2580                   ; branch if sram is valid

; slot is empty, save instantly
        jsr     PlaySuccessSfx
        jsr     SaveGame
```

So a perfectly intact save whose 2558-byte sum happens to be exactly `$0000` is
displayed as empty, cannot be loaded, and is **overwritten with no
are-you-sure prompt** the next time the player picks that slot. The save is
gone.

### Why it clears the bar and Sketch's neighbours do not

- It is **save loss**, named explicitly in #13.
- It is **already in every shipped frontier**, from v0.1. Under #13's own
  acceptance criterion — "no release advertises a frontier containing a known
  crash/corruption/save-loss bug without a fix, mitigation, or explicit
  release-blocking decision" — it needs a decision *now*, not at v0.8.
- It is **not** rare enough to dismiss. The rate is roughly 1 in 65 536 per
  save. A long playthrough saves hundreds of times; across a playtest cohort
  somebody will hit it. And v0.6's roadmap item is literally
  "player-facing save cadence" (`docs/ROADMAP.md`, v0.6 bullet) — i.e. more
  saves, more exposure.

The reason the bug is invisible in vanilla folklore is that it is
indistinguishable from an ordinary empty slot: a wiped cartridge reads as all
zeroes, whose checksum is also `$0000`, so "checksum 0 means empty" is *also*
doing real work. That is exactly why the fix has to be careful.

### Fix options

**Option A — bias the stored checksum away from zero (3 instructions).** The
stored word at `$1ffe` is *outside* the summed range (`cpx #$09fe` stops at
`$1ffd`), so mapping `$0000 → $ffff` at the end of `CalcSaveSlotChecksum`
applies identically on write and on verify, and no other code reads `$1ffe`.
A genuinely empty (zero-filled) slot still sums to `$0000` on the *stored* side
and so still compares unequal to `$ffff`, i.e. still reads as empty — the
existing behaviour that matters is preserved. This is the narrowest fix and it
is where I would start.

**Option B — return a real boolean.** Change `CheckSaveSlotChecksum` to return
`$0001`/`$0000` instead of the checksum value. Same three-instruction cost, but
it needs a check that no caller uses the *value* rather than its truthiness.
A grep of `$91`/`$93`/`$95` is the whole verification.

Either way the positive-control regression is the same and is cheap to build
headless: construct a save block whose sum is `$0000`, save it, and assert the
slot loads. That test must fail against the current ROM before the fix lands.

### Related, but **not** a defect: no journaling

`CopyGameDataToSRAM` (`ff6/src/menu/save.asm:42-75`) writes the 2560-byte slot
in one un-shadowed byte loop, with no commit flag beyond the checksum. Power
loss mid-write destroys the previous contents of that slot. That is how every
SNES battery save works and is not something #13 asks us to fix. Recorded
because OT6 *widened* the window: `jsl Ot6CodexSaveAs` at
`ff6/src/menu/save.asm:47` now replaces the destination's codex page in SRAM
bank `$31` **before** the vanilla block copy starts, and the codex page has no
checksum of its own. An interrupted save now leaves an invalid slot *and* a
replaced codex page.

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
  decision, priced into the MP economy (`docs/design/mp-economy.md:315`). It is
  a within-battle state, not a soft lock.
- **Leap removing Gau.** Not a defect; and vanilla already guards the
  degenerate case — `TargetEffect_54` refuses Leap when fewer than two party
  members remain (`ff6/src/battle/battle_main.asm:9614-9620`).

---

## OT6-side findings (not vanilla, found in passing)

The brief asked how OT6's own work interacts with vanilla's defects. Three
things turned up that are OT6's, not Square's, and belong in the record.

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

---

## Bottom line for #13's acceptance criteria

- **Two** vanilla defects in this base clear #13's destructive bar with
  code-level evidence, out of thirteen confirmed defects and a much larger pile
  of folklore that did not survive contact with the source.
  1. The **Sketch graphics-index escape** — frontier **v0.8 (Thamasa)**,
     matching the milestone already on the issue.
  2. The **save-slot checksum `$0000`** case — frontier **v0.1**, i.e. it is in
     every release already tagged.
- **The earliest genuine release-gate risk was the checksum bug, not Sketch —
  and it is FIXED** (2026-07-27, issue #18, commit 37a0eb5, with its
  positive-control regression save_checksum in the suite; this paragraph
  kept for the reasoning record). It was live in every tagged release, it
  was a save-loss bug, v0.6 explicitly increases save frequency, and the
  fix was three instructions. Under #13's own acceptance
  criteria it needs a fix, a mitigation, or a written release-blocking decision
  before the next tag — it cannot wait for v0.8.
- No confirmed destructive defect is *specific* to **v0.6** or **v0.7**.
- The riskiest items that are not vanilla defects are the three unguarded
  primitives — `SetControlCmd` (#4), `BattleEnd_02` (#5), `OptimizeCharEquip`
  (#6) — plus the `GetVeldtBattle` loop (#3). All four are harmless because of
  what vanilla *data* happens to contain, and OT6 is in the business of
  changing that data. `SetControlCmd` is the worst: `cmd CONTROL` in an
  authored AI script is a silent arbitrary WRAM write.
- One OT6-side persistent-state bug found in passing: `OT6_LOADOUT` at
  `$7e1e1d` is cleared by neither `InitNewGame` nor `ClearRAM`, so a New Game
  inherits the previous game's Bushido loadout.
- Three project documents currently assert the opposite of #13 about Sketch and
  need reconciling as part of closing it: `CONTRIBUTING.md` (House rules),
  `docs/design/kits.md:708`, `docs/design/mp-economy.md:315`.

### Suggested acceptance-criteria mapping

| #13 criterion | What this document supplies |
|---|---|
| `CONTRIBUTING.md` distinguishes quirks from destructive failures | The bar as applied here, plus the [Explicitly preserved](#explicitly-preserved-the-other-half-of-the-policy) list as the worked boundary. |
| Destructive bugs tracked with a reproduction/source basis and frontier owner | The two [Frontier map](#frontier-map-summary) rows, each with an instruction-level chain. |
| No release ships a known crash/corruption/save-loss bug undecided | The checksum bug forced this decision and was fixed (#18) ahead of the v0.6 tag; Sketch ships as-is by owner decision (CONTRIBUTING). |
| Sketch fixed or mitigated before Relm ships | Three costed options, narrowest first. |
| Narrowly scoped, covered by positive-control regressions | Both fixes name their positive control, and both controls must fail against the current ROM first. |
| The policy does not demand modernizing every quirk | Eleven confirmed defects are argued *down*, with citations, in this same document. |
