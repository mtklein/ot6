; ------------------------------------------------------------------------------
; Battle command submenus: list builders and per-row draw shims
;
; Everything OT6 adds to the in-battle command windows: Blitz-as-a-menu, the
; priced/greyed row decorators for Blitz, Tools and Dance, and Cyan's SwdTech
; submenu (open, window fill, confirm). All of it is called from btlgfx bank
; $C1/$C3 shims. The Steal submenu is the same shape but lives with its kit,
; in ot6_thief.asm.
; ------------------------------------------------------------------------------

; [ open the Blitz command as a menu ]

; vanilla Blitz had no window: _c1776b armed the 64-frame pad-edge buffer and
; UpdateMenuState_3d matched button codes. This module deletes that path and
; drives Blitz through the Tools window shell instead. _c1776b now jsl's here,
; then jmp's OpenToolsWindow: this proc fills wItemList with the learned
; blitzes, raises the mode flag the two btlgfx shims read (w7e6168, freed when
; UpdateMenuState_3d went), and jumps the tools state machine straight to its
; draw phase (w7e7b9e=4) so it skips the four inventory-scan phases it would
; run for real tools.  The shared cursor is deliberately not reset: the
; Tools shell already honored the Config>Cursor (Memory/Reset) setting for it
; at command-window-open time, and re-zeroing it here would override that; see
; @padded.
;
; the row id stored is the resolved attack id $5d+i (Pummel $5d .. Bum Rush
; $64): ListTextCmd_0f renders ids >=$51 from AttackName with no extra work, and
; the confirm shim subtracts $5d back to the raw index 0-7 that cmd $0a expects,
; the same index UpdateMenuState_3d wrote, so FixPlayerAttack (validates i
; against $1d28, adds +$5d) and the Vargas AI (reads the resolved $5d) are
; untouched. Only learned blitzes appear, so that validation never trips.
;
; entry: jsl from _c1776b (btlgfx C1), db=$7e, a8/i16. clobbers a/x/y (the
; caller's next act is jmp OpenToolsWindow, which reloads what it needs).

.proc Ot6BlitzListOpen
        .a8
        .i16
        ; --- pack the learned blitzes into wItemList ($7e4005, 3 bytes/row) ---
        ldx     #$0000          ; wItemList write offset
        ldy     #$0000          ; blitz index 0-7
        lda     $1d28           ; known-blitz bitmask (the byte FixPlayerAttack
@bit:   lsr                     ;   validates); carry = bit for blitz Y
        bcc     @next
        pha                     ; park the shifted mask on the stack: $36 and
        tya                     ;   OT6_SCR_BIT both have owners here, and the
        clc                     ;   stack has none and survives an nmi
        adc     #$5d            ; attack id $5d + blitz index
        sta     $4005,x         ; wItemList::Index
.if ::OT6_MP_COSTS              ; :: because ca65 resolves .if in the proc's
                                ;   local scope; force the file-scope flag
        jsl     Ot6CostFor      ; A(id) -> A(cost); preserves X and Y
        sta     $4006,x         ; wItemList::Qty = MP cost.  Qty is otherwise
                                ;   unused here, and the row-draw shim reads it
.endif
        inx
        inx
        inx                     ; next row
        pla                     ; unpark the mask
@next:  iny
        cpy     #$0008
        bne     @bit
        ; --- $ff-terminate through the 8-cell (4x2) window ---
        lda     #$ff
@pad:   cpx     #$0018          ; 8 rows * 3 bytes
        bcs     @padded
        sta     $4005,x
.if ::OT6_MP_COSTS              ; :: forces the file-scope flag from in-proc
        stz     $4006,x         ; Qty=0: an empty cell's cost draws as two blanks
.endif
        inx
        inx
        inx
        bra     @pad
@padded:
        ; --- leave the shared cursor triple alone: honor Config>Cursor ---
        ; the Tools shell already applied the Cursor (Memory/Reset) setting to
        ; this character's triple ($895f scroll / $8963 col / $8967 row) when the
        ; command window opened: UpdateMenuState_04 (btlgfx_main.asm:13343)
        ; reads f:$001d4e, and when bit6 is clear (Reset) stz-loops the whole
        ; 92-byte cursor block $890f..$896a to zero; when set (Memory) it skips
        ; that loop, so last turn's positions survive.  Blitz reuses the Tools
        ; triple under the same
        ; per-slot index ($62ca), so doing nothing makes it obey the bit the
        ; same way Tools/Magic/Item do.  A remembered row indexes the packed
        ; $5d+i list directly (in-battle the learned set is fixed), so no
        ; id-to-row mapping is needed.  A fresh window re-init is still forced
        ; below.
        stz     $7ba5           ; force MakeToolsList_04 to re-init the window
        ; --- jump the tools state machine to its draw phase ---
        lda     #$04
        sta     $7b9e           ; w7e7b9e (MakeToolsList phase) -> MakeToolsList_04
        ; --- raise the blitz-mode flag the row-draw / confirm shims read ---
        lda     #$01
        sta     $6168           ; w7e6168
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ draw one Blitz menu row: the names, and (priced build) their MP cost ]
;
; DrawToolsListText (btlgfx, bank C1, the full build) jsl's here for a
; blitz-mode row, in place of the two inline "$0e item-name -> $0f attack-name"
; stores it used to do. Moving that swap into bank F0 gives the priced build
; room to also stamp an MP cost after each name without growing the full C1
; bank: the feature costs C1 a single 4-byte jsl (net -4 bytes there), and the
; logic lives here.
;
; the line buffer w7e5755 already holds the copied Tools template plus the two
; row ids (the caller wrote Index,y -> +5 and Index+3,y -> +11 before the jsl);
; w7e6168 is the blitz flag the caller just tested. entry from a jsl: db=$7e
; (the caller draws through it), a8, Y = drawn-row * 6, so Qty,y is the left
; cell's cost and Qty+3,y the right cell's. clobbers A only (the caller reloads
; it in InitListTextTfr and never re-uses this derived Y).
;
; Always assembled: the stock C1 object jsl's it in both the priced and the
; OT6_MP_COSTS=0 baseline build, so it must resolve in both. Only the cost
; stamping is flag-gated; the nomp row stays the byte-identical two-name
; layout. w7e5755 = $5755 near; the numeric literals below are its +4..+15.
.proc Ot6BlitzRowDecorate
        php
        sep     #$20            ; 8-bit A for the byte stores
        .a8
        .i16
        lda     #$0f            ; left cell: render from AttackName, not ItemName
        sta     $5759           ; w7e5755+4: name command, column 1
.if ::OT6_MP_COSTS              ; :: forces the file-scope flag from in-proc
        ; the name is a fixed 10-wide field; stamp a 2-digit MP cost right after
        ; it, a gap space, then column 2's name and its own cost. ListText cmd
        ; $02 draws two digits with a blank tens-place, so a 0 cost (a padded
        ; empty cell, Qty pre-zeroed) renders as two blanks, leaving a gap.
        ; The $04,$21 font at +2/+3 (carried in from the copied template) colors
        ; the column-1 name and its trailing cost together; grey that byte when
        ; the caster cannot afford the row, the twin of magic greying spell+MP
        ; as one.
        lda     $4006,y         ; wItemList::Qty,y     (column-1 cost)
        jsl     Ot6AbilityGrey  ; -> $04 grey / $00 white; preserves X and Y
        jsl     Ot6BushidoRowGrey ; bushido (w7e6168=2): also grey a row whose boost
                                ;   exceeds current bp; blitz passes A through
        ora     $5758           ; +3   column-1 font palette: $21 -> $21/$25
        sta     $5758
        lda     #$02
        sta     $575b           ; +6   number command      (column-1 cost)
        lda     $4006,y         ; wItemList::Qty,y         (column-1 cost value)
        sta     $575c           ; +7
        lda     #$ff
        sta     $575d           ; +8   space between the columns
        lda     #$04
        sta     $575e           ; +9   set-font command
        lda     $4009,y         ; column-2 cost: grey column 2's font the same
        jsl     Ot6AbilityGrey  ;   way; +9/+10 colors column-2's name AND cost
        ora     #$21            ; +10  font palette: $21 white or $25 grey
        sta     $575f
        lda     #$0f
        sta     $5760           ; +11  name command         (column 2)
        lda     $4008,y         ; wItemList::Index+3,y     (column-2 id, moved)
        sta     $5761           ; +12
        lda     #$02
        sta     $5762           ; +13  number command       (column-2 cost)
        lda     $4009,y         ; wItemList::Qty+3,y       (column-2 cost value)
        sta     $5763           ; +14
        stz     $5764           ; +15  terminator
.else
        lda     #$0f            ; nomp baseline: the old layout, swap column 2's
        sta     $575f           ;   name only (w7e5755+10), no cost, no re-layout
.endif
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ draw one Tools menu row: a leading 2-digit price per name, greyed if
;   the caster cannot afford it ]
;
; DrawToolsListText (btlgfx, bank C1) jsl's here for a real tools row (the
; not-blitz arm), the twin of the Ot6BlitzRowDecorate call one branch over.
; Unlike Blitz, the vanilla tools row already draws correctly, so this shim
; only stamps each tool's MP cost and greys the pair (name + price) the caster
; cannot pay for, through Ot6AbilityGrey, the same $21->$25 magic uses.  In the
; nomp battle object the OT6_MP_COSTS block below is empty and the proc is a
; no-op that leaves the vanilla two-name layout byte for byte.  It is always
; assembled, because the shared C1 object calls it in both builds, so the flag
; gating lives here in the battle object rather than in btlgfx.
;
; Layout and fit finding: the tools window is two columns of 13-wide item
; names (AutoCrossbow, NoiseBlaster, ...), and those already fill the row
; edge to edge, so a Blitz-style cost after each name overflows the 32-tile
; screen.  A true single column would fit a
; trailing cost but needs the tools window to scroll (it is a fixed 4x2 grid
; whose max-scroll is hardwired to zero), which means re-cutting the shared
; item/throw cursor + draw state machine, more work than a cost label warrants.
; So the cost goes in the row's leading pair instead, and each column is laid
; out [font][cost][name] so its one font command colors the price and the name
; as a unit, which is what greying needs.  The template's "$05,$02
; draw-two-spaces" ahead of name 1 (buffer +0/+1) and its "$ff $ff" gap ahead of
; name 2 (+6/+7) become the two font commands; the two costs move to +2/+3 and
; +8/+9 (the old font slots).  A $04 font command draws nothing, so the price
; still lands on the same two tiles immediately left of its name: same 31-tile
; width, all 8 tools, no re-layout.
;
; entry from a jsl: db=$7e, a8 on return, i16 (Ot6CostFor / Ot6AbilityGrey need
; it), Y unused here (the ids sit at fixed buffer offsets).  w7e5755 = $5755;
; the literals below are its +5 (id 1) and +11 (id 2), with font/cost stamped at
; +0..+3 and +6..+9.  cmd $02 renders a 0 as two blanks, so an empty ($ff) cell
; (Ot6CostFor returns 0 for an unpriced id) draws the same gap the
; vanilla spaces did, and Ot6AbilityGrey leaves a 0-cost cell white.
.proc Ot6ToolRowDecorate
        php
        sep     #$20
        .a8
        .i16
.if ::OT6_MP_COSTS              ; :: forces the file-scope flag from in-proc
        ; Reorder each column to [font][cost][name] so one font command colors a
        ; tool's price and its name.  The just-landed price display put the cost
        ; tile before the column's font command, so greying the font (to match
        ; magic) could not reach the number; moving the font ahead of the cost
        ; fixes it at no cost in width, because a $04 font command draws nothing,
        ; so the price still sits on the same two tiles immediately left of its
        ; name.  Column 1: font -> +0/+1 (was the $05,$02 draw-spaces), cost ->
        ; +2/+3 (was the $04,$21 font).  Column 2: font -> +6/+7 (was the $ff,$ff
        ; column gap), cost -> +8/+9 (was the second $04,$21 font).  The name
        ; commands (+4,+10) and their ids (+5,+11, DrawToolsListText's) stay put.
        lda     $575a           ; +5 = column-1 tool id (DrawToolsListText wrote it)
        jsl     Ot6CostFor      ;   id -> MP cost (0 if $ff/unpriced)
        pha                     ; park column-1 cost
        jsl     Ot6AbilityGrey  ;   cost -> $04 grey / $00 white; preserves X,Y
        ora     #$21            ; +1: font palette, $21 white or $25 grey
        sta     $5756
        lda     #$04
        sta     $5755           ; +0: font command (colors column-1 cost + name)
        lda     #$02
        sta     $5757           ; +2: number command (column-1 cost)
        pla
        sta     $5758           ; +3: column-1 cost value
        lda     $5760           ; +11 = column-2 tool id
        jsl     Ot6CostFor
        pha                     ; park column-2 cost
        jsl     Ot6AbilityGrey
        ora     #$21            ; +7: font palette, $21 white or $25 grey
        sta     $575c
        lda     #$04
        sta     $575b           ; +6: font command (colors column-2 cost + name)
        lda     #$02
        sta     $575d           ; +8: number command (column-2 cost)
        pla
        sta     $575e           ; +9: column-2 cost value
.endif
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ draw one Dance menu row: a leading 2-digit price per name, greyed if
;   the caster cannot afford it ]
;
; DrawDanceListText (btlgfx, bank C1) jsl's here after copying the template
; and storing the two row ids, the same shape as Ot6ToolRowDecorate, on the
; dance window.  Dance's price is flat (Ot6DanceCost, the same authority the
; charge reads), so both columns stamp the same number; an empty ($ff) cell
; draws a 0, which cmd $02 renders as two blanks.  Each column re-lays to
; [font][cost][name] so one font command colors price and name as a unit,
; the tools transform verbatim: column 1's "$05,$04 draw-4-spaces" (+0/+1)
; and its "$04,$21 font" (+2/+3) become [font][cost], column 2's "$05,$02
; gap" (+6/+7) and font (+8/+9) likewise; the name commands (+4,+10) and ids
; (+5,+11) stay put.  Row width 2+12+2+12 = 28 tiles, narrower than vanilla's
; 30.  In the nomp build the body is empty and the vanilla layout is
; byte-identical.  Always assembled; the flag gating lives here.
;
; entry from a jsl: db=$7e, a8 on return, i16 (Ot6AbilityGrey needs it).
; w7e5755 = $5755 near; literals below are its offsets.  clobbers A only.
.proc Ot6DanceRowDecorate
        php
        sep     #$20
        .a8
        .i16
.if ::OT6_MP_COSTS              ; :: forces the file-scope flag from in-proc
        lda     $575a           ; +5 = column-1 dance id (caller wrote it)
        jsl     Ot6DanceRowCost ;   id -> cost (0 for an $ff empty cell)
        pha                     ; park column-1 cost
        jsl     Ot6AbilityGrey  ;   cost -> $04 grey / $00 white
        ora     #$21
        sta     $5756           ; +1: font palette (colors cost + name)
        lda     #$04
        sta     $5755           ; +0: font command
        lda     #$02
        sta     $5757           ; +2: number command
        pla
        sta     $5758           ; +3: column-1 cost value
        lda     $5760           ; +11 = column-2 dance id
        jsl     Ot6DanceRowCost
        pha                     ; park column-2 cost
        jsl     Ot6AbilityGrey
        ora     #$21
        sta     $575c           ; +7: font palette
        lda     #$04
        sta     $575b           ; +6: font command
        lda     #$02
        sta     $575d           ; +8: number command
        pla
        sta     $575e           ; +9: column-2 cost value
.endif
        plp
        rtl
.endproc

.if OT6_MP_COSTS
; [ a dance row's price: the flat Ot6DanceCost, 0 for an empty cell ]
; in: A = the row's dance id ($ff = empty).  out: A = cost.  preserves X,Y.
.proc Ot6DanceRowCost
        .a8
        cmp     #$ff
        bne     :+
        lda     #$00            ; empty cell: no price, stays white
        rtl
:       jml     Ot6DanceCost    ; the one authority (its rtl returns for us)
.endproc
.endif  ; OT6_MP_COSTS

; ------------------------------------------------------------------------------

.if OT6_MP_COSTS
; [ add the Bushido "not enough BP" grey reason to a row's font ]
;
; In bushido mode (w7e6168 = 2) the submenu row is the boost level (Y/6 + 1
; with the 1-BP floor, weakest at top). A row whose boost exceeds the
; caster's current bp (OT6_BP_CLASS,entity) is unreachable, because
; Ot6BushidoConfirm refuses to commit it, so grey it like an unaffordable
; spell, a second grey reason on top of Ot6AbilityGrey's MP one.  At 0 bp that
; greys all three rows: the list still shows what the bank would buy (the
; teaching surface) and refuses every row, the same presentation an
; unaffordable spell gets, rather than a list that changes length with the
; wallet.  Blitz mode (w7e6168 = 1) passes the MP grey through untouched.  Only
; reached from Ot6BlitzRowDecorate's OT6_MP_COSTS block, so it lives behind the
; same flag.
;
; Thief mode (w7e6168 = 3) is a second consumer, for the same kind of
; reason: Bestow cannot do anything at 0 BP, because there is no pip to hand
; over, and Ot6Bestow's first refusal is that same test, so the row greys and
; the player learns it before spending the turn rather than after.  This proc
; keeps its Bushido name because the shape is Bushido's ("a second grey reason,
; on top of the MP one, for a row the bank cannot reach"); the two arms share the
; caster-lookup and the stack protocol and nothing else.  Steal and Filch have no
; BP precondition and are never greyed by this arm.
;
; a8/i16.  in: A = the MP grey ($00/$04), Y = drawn-row*6.
; out: A = A | ($04 if the row is out of reach of the caster's bank).
; preserves X and Y.
.proc Ot6BushidoRowGrey
        .a8
        .i16
        pha                     ; [S+1] park the MP grey
        lda     $6168
        cmp     #$03
        beq     @thief          ; the thief submenu's own BP reason
        cmp     #$02
        bne     @pass           ; not bushido: return the MP grey unchanged
        phx                     ; [S+2] save caller X (Ot6BlitzRowDecorate's)
        lda     $62ca           ; entity offset for the bp bank
        and     #$03
        asl
        longa
        and     #$00ff
        tax
        shorta0
        lda     OT6_BP_CLASS,x         ; current bp
        pha                     ; [S+1] park bp ($01,s)
        tya                     ; A = drawn-row*6
        ldx     #$0000          ; row i accumulator
@div:   cmp     #$06            ; i = (row*6) / 6
        bcc     @haver
        sbc     #$06
        inx
        bra     @div
@haver: txa                     ; A = i
        inc     a               ; boost r = i + 1; with the 1-BP floor a
                                ;   0-bp Cyan greys every row (see the header)
        cmp     $01,s           ; r vs bp; C set iff r >= bp
        beq     @afford         ; r == bp: exactly affordable
        bcc     @afford         ; r <  bp: affordable
        pla                     ; r > bp: unreachable, so grey it
        plx                     ; restore caller X
        pla                     ; MP grey
        ora     #$04            ; add magic's disabled bit ($21|$04 = $25)
        rtl
@afford:
        pla                     ; drop bp
        plx                     ; restore caller X
        bra     @pass
; In thief mode only Bestow has a BP precondition, and it is "hold one".
@thief: lda     $4005,y         ; this row's id (column 1; Qty at +1, Flags +2)
        cmp     #OT6_THIEF_BESTOW
        bne     @pass           ; steal / filch / an empty cell: MP grey only
        phx                     ; [S+2] save caller X (Ot6BlitzRowDecorate's)
        lda     $62ca           ; entity offset for the bp bank
        and     #$03
        asl
        longa
        and     #$00ff
        tax
        shorta0
        lda     OT6_BP_CLASS,x  ; current bp
        plx                     ; restore caller X first: plx sets Z/N, so the
        cmp     #$01            ;   affordability test has to come after it
        bcs     @pass           ; holds at least one pip: Bestow is reachable
        pla                     ; 0 bp: nothing to give, so grey it
        ora     #$04            ; magic's disabled bit ($21|$04 = $25)
        rtl
@pass:  pla                     ; MP grey (unchanged)
        rtl
.endproc
.endif  ; OT6_MP_COSTS

; ------------------------------------------------------------------------------

; [ open Cyan's SwdTech as a submenu ]
;
; vanilla SwdTech ran a free numeral gauge (UpdateMenuState_35/37, now dead):
; a bar climbed one unit every 4 frames, the tech was bar>>5, and A latched
; whatever level it happened to show. This module deletes the gauge and drives
; SwdTech through the Tools window shell instead, the twin of Ot6BlitzListOpen.
; OpenCmdMenuTbl[7] now hits a C1 stub that jsl's here then jmp's OpenToolsWindow.
;
; The rows are the boost window: row r (weakest at top) = boost r+1 = the tech
; Ot6BushidoTier returns for that boost (no 0x tier). Ot6BushidoWindow
; enumerates the <=3 techs into wItemList's left column (cells r*2, so row r
; reads at wItemList offset r*6, what _c18470 computes for column 0); the
; right column and any unused rows are $ff (empty), so the window renders a
; single column of 3.
; Confirm (Ot6BushidoConfirm) maps the picked cell back to r, banks OT6_BOOST_REVEALED=r, and
; latches Ot6BushidoTier's tech, so single-select and enumeration share the
; same base+boost math and cannot diverge.
;
; entry: jsl from the C1 stub, db=$7e, a8/i16. clobbers a/x/y (the caller's next
; act is jmp OpenToolsWindow, which reloads what it needs).
.proc Ot6BushidoListOpen
        .a8
        .i16
        jsl     Ot6BushidoWindow    ; pack the <=4 window techs (left col) + $ff pad
.if ::OT6_MP_COSTS                  ; :: forces the file-scope flag from in-proc
        ; stamp each cell's MP cost into wItemList::Qty (a $ff empty cell gets 0,
        ; which cmd $02 renders as two blanks and Ot6AbilityGrey leaves white).
        ldx     #$0000
@cost:  lda     $4005,x             ; wItemList::Index
        cmp     #$ff
        bne     @price
        stz     $4006,x             ; empty cell: cost 0
        bra     @nextc
@price: jsl     Ot6CostFor          ; id -> MP cost (preserves X and Y)
        sta     $4006,x             ; wItemList::Qty
@nextc: inx
        inx
        inx
        cpx     #$0018              ; 8 cells * 3 bytes
        bcc     @cost
.endif
        ; --- honor Config>Cursor the same way Blitz/Tools do: leave the shared
        ; cursor triple alone (the command-window open already applied Memory/
        ; Reset), and force a fresh window re-init. A remembered row indexes the
        ; packed list directly; in-battle the learned set (hence the rows) is
        ; fixed, so no id-to-row remap is needed.
        stz     $7ba5               ; force MakeToolsList_04 to re-init the window
        lda     #$04
        sta     $7b9e               ; jump the tools state machine to its draw phase
        lda     #$02
        sta     $6168               ; w7e6168 = 2 : bushido mode (1 = blitz)
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ enumerate the moving-window techs into wItemList ]
;
; writes attack id ($55 + tech[i]) for row i = 0..min(2,ceiling) into
; wItemList::Index at cell i*2 (the left column of row i), and $ff-fills every
; other cell through the 8-cell (4x2) window. row i is boost i+1, since the
; 0x tier is retired, so the window is three rows deep and row 3 always stays
; $ff (blank, and the C1 confirm refuses it). tech[i] shares Ot6BushidoTech's
; base+boost math and Ot6BushidoOblivion's top-tier swap with single-select, so
; the menu cannot offer a tech the confirm latch would not fire. When Cyan
; knows fewer than three techs (ceiling < 2) only the known rows are emitted; a
; boost past the ceiling would cap to a duplicate tech, so its row is left
; $ff (unselectable) rather than shown.
;
; a8/i16.  out: X = number of rows written (1..3).  clobbers A,X,Y.
.proc Ot6BushidoWindow
        .a8
        .i16
        ; --- $ff-fill all eight window cells first (empty = blank + unselectable) ---
        ldx     #$0000
        lda     #$ff
@pad:   sta     $4005,x             ; wItemList::Index
        inx
        inx
        inx
        cpx     #$0018
        bcc     @pad
        ; --- rowcount-1 = min(2, ceiling): boost past the ceiling duplicates ---
        jsl     Ot6BushidoCeil      ; A = ceiling (0..7)
        cmp     #$03
        bcc     :+
        lda     #$02                ; cap the window at three rows (1x/2x/3x)
:       pha                         ; maxrow -> $02,s (after the offset push)
        lda     #$00
        pha                         ; left-cell write offset -> $01,s
        ldy     #$0000              ; row i
@row:   tya                         ; A = row i
        inc     a                   ; row i -> boost i+1 (no 0x tier)
        jsl     Ot6BushidoTech      ; A = tech (preserves Y; clobbers X)
        jsl     Ot6BushidoOblivion  ; A = tech, top-tier swap (preserves Y)
        clc
        adc     #$55                ; A = attack id $55 + tech
        pha                         ; park id ($01,s; offset now $02,s, max $03,s)
        lda     $02,s               ; A = write offset (r*6)
        longa
        and     #$00ff
        tax                         ; X = write offset
        shorta0
        pla                         ; A = id (offset back at $01,s)
        sta     $4005,x             ; wItemList::Index at row r's left cell
        lda     $01,s               ; advance offset += 6 (one row)
        clc
        adc     #$06
        sta     $01,s
        iny                         ; next row
        tya
        cmp     $02,s               ; i vs maxrow
        bcc     @row                ; i < maxrow: another row
        beq     @row                ; i == maxrow: the last row
        pla                         ; drop the write offset
        pla                         ; A = maxrow
        inc     a                   ; rowcount = maxrow + 1 (1..3)
        longa
        and     #$00ff
        tax                         ; X = rowcount
        shorta0
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ commit a Bushido submenu row: row i = boost i+1, fire that tier's tech ]
;
; jsl from the C1 tools-confirm (@8809, bushido mode w7e6168=2). The C1 side has
; already rejected an $ff (empty) cell, so X points at a real left-column tech
; cell: X = row*6, and row = boost r. Refuse (buzz, stay open) a row the caster
; lacks the BP for, i.e. r > current bp (OT6_BP_CLASS,entity), the confirm twin of the
; menu's bp-grey. Otherwise bank the boost (OT6_BOOST_REVEALED,entity = r; Ot6ActionEnd then
; charges r and skips that turn's regen, as an L/R spend would have),
; latch the tech Ot6BushidoTier returns for boost r into the action queue, and
; close the menu. FixPlayerAttack's +$55 and Cmd_07's dispatch stay untouched.
;
; entry: db=$7e, a8/i16, X = selected cell byte offset (_c18470's). rtl.
.proc Ot6BushidoConfirm
        .a8
        .i16
        ; --- row i = cell offset / 6  (X in {0,6,12} -> i in {0,1,2}) ---
        txa                         ; A = cell offset (low byte, <= 12)
        ldx     #$0000              ; i accumulator
@div:   cmp     #$06
        bcc     @haver
        sbc     #$06                ; C set by the cmp, so sbc is exact
        inx
        bra     @div
@haver: txa                         ; A = i (i <= 2)
        inc     a                   ; boost r = i + 1 (the 1-BP floor)
        pha                         ; park r ($01,s)
        ; --- entity offset for OT6_BP_CLASS/OT6_BOOST_REVEALED ---
        lda     $62ca
        and     #$03
        asl                         ; slot * 2 = entity offset
        longa
        and     #$00ff
        tax
        shorta0
        ; --- refuse a row the caster cannot pay the BP for ---
        lda     OT6_BP_CLASS,x             ; current bp
        cmp     $01,s               ; bp vs r; C set iff bp >= r (affordable)
        bcs     @ok
        pla                         ; drop r
        inc     $95                 ; error buzz; stay in the menu, as magic does
        rtl
@ok:    ; --- bank the boost: OT6_BOOST_REVEALED,entity = r (the spend the row selected) ---
        lda     $01,s
        sta     OT6_BOOST_REVEALED,x             ; pending boost = r (Ot6BushidoTier reads it)
        pla                         ; drop r (already banked); stack balanced
        jsl     Ot6BushidoTier      ; A = base+r tech (reads the OT6_BOOST_REVEALED we just set)
        pha                         ; park tech
        lda     $7b80               ; queue slot y = (w7e7b80 & 3) * 8
        and     #$03
        asl3
        tay
        pla                         ; A = tech
        sta     $2bb0,y             ; attack index (FixPlayerAttack adds +$55)
        lda     $62ca
        sta     $2bae,y             ; character slot
        inc     $7b80               ; commit the queued action
        inc     $7bcb               ; close the menu (state $30 -> $2f)
        rtl
.endproc
