; ------------------------------------------------------------------------------
; Strago: the lore loadout and its page (the Ot6Rage* family at 5 slots)
;
; The Ochette model, third instance: observation learning stays unlimited
; (LearnLore and the $1d29-$1d2b bitfield are untouched) and the battle Lore
; menu is filtered to a 5-slot loadout configured in the field.  Everything
; that decides lives here in F0; the C3 page (ot6_lore_page.asm) is tilemap,
; cursor and DMA only, the same split both earlier configurators use.
;
; Storage: OT6_LORELOAD, five bytes at $7e1e27, next in the save-block scrap.
; byte = lore id + 1 (ids 0..23); $00 = unset; all five zero = AUTO.
;
; The battle read is one choke point, and it is smaller than Gau's: vanilla's
; lore-list walk in InitSpellList (battle_main.asm @556a) tests one bit per
; lore against $1d29,x and everything downstream (count $3a87, the $310f/$306a
; list tables, the menu draw and confirm) narrows from which bits pass.  So
; the hook is not a list builder: Ot6LoreMask writes an EFFECTIVE 3-byte mask
; to $ee/$ef/$f0 and the vanilla walk reads that instead of $1d29 directly.
; The walk itself, its rotating-bit idiom, and everything downstream stay
; vanilla.  ($f0 doubles as InitSpellList's own pointer scratch a few lines
; later; the walk is finished with the mask before that write happens.)
; ------------------------------------------------------------------------------

; [ is a lore learned?  test bit (id & 7) of $1d29 + (id >> 3) ]
; The Ot6RageLearned shape over the 3-byte lore bitfield: LSB-first inside
; each byte, in id order, matching both vanilla walkers (InitSpellList @556a
; counts down from bit 23; the menu browse _c3520f counts up from bit 0).
; a8/i16.  in: A = lore id (0..23).  out: carry = learned, A preserved.
;   clobbers X.  preserves Y.  An id past 23 reads as unlearned.
.proc Ot6LoreLearned
        .a8
        .i16
        cmp     #$18
        bcs     @no             ; ids 24+ do not exist
        phy                     ; [$01,s..$02,s] caller Y
        pha                     ; [$01,s] the id
        lsr
        lsr
        lsr                     ; A = id >> 3 = byte index (0..2)
        longa
        and     #$0003
        tax
        shorta0
        lda     $01,s           ; the id again
        and     #$07
        longa
        and     #$00ff
        tay                     ; Y = bit index (clean shift count)
        shorta0
        lda     f:$7e1d29,x     ; the learned-lore bitfield
        iny                     ; shift bit+1 times -> carry = bit
:       lsr
        dey
        bne     :-
        pla                     ; A = the id (PLA preserves carry)
        ply                     ; caller Y  (PLY preserves carry)
        rtl
@no:    clc
        rtl
.endproc

; [ a loadout slot's lore, validated: the single source of truth ]
; The stored byte only counts if the bit is still set.  Learning is monotonic
; and nothing clears $1d29, so staleness needs a corrupt or hand-edited save;
; the validation is against feeding the battle menu a lore never observed.
; a8/i16.  in: A = slot (0..4).  out: carry set + A = lore id, or carry clear
;   (unset / not learned).  clobbers X.  preserves Y.
.proc Ot6LoreSlot
        .a8
        .i16
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:OT6_LORELOAD,x
        beq     @none           ; $00 = unset
        dec     a               ; stored byte - 1 = lore id
        jsl     Ot6LoreLearned  ; carry = learned (A preserved)
        bcc     @none
        rtl                     ; carry set, A = the id
@none:  clc
        rtl
.endproc

; [ the n-th learned lore in id order (AUTO's definition) ]
; AUTO is "the first five known lores in id order".  Both readers resolve
; through this (the page via Ot6LoreShow, the battle mask via Ot6LoreMask's
; AUTO arm walking the same bits in the same order), so the page and the
; battle menu show the same five by construction.  24 candidates, so the
; walk-from-scratch cost Gau's page had to avoid is 24 bit tests here and
; needs no separate fast path.
; a8/i16.  in: A = n (0-based).  out: carry set + A = the id, or carry clear
;   (fewer than n+1 learned).  clobbers X.  preserves Y.
.proc Ot6LoreNth
        .a8
        .i16
        pha                     ; [$01,s] n (counted down)
        phy                     ; [$01,s..$02,s] caller Y (n now $03,s)
        ldy     #$0000          ; candidate id
@try:   tya
        jsl     Ot6LoreLearned  ; carry = learned; preserves Y, clobbers X
        bcc     @next
        lda     $03,s
        beq     @hit
        dec     a
        sta     $03,s
@next:  iny
        cpy     #$0018          ; ids 0..23
        bcc     @try
        ply
        pla
        clc                     ; fewer than n+1 learned
        rtl
@hit:   tya                     ; A = the id (a8 reads Y's low byte)
        sta     $03,s           ; overwrite the parked n with it
        ply                     ; caller Y
        pla                     ; A = the id
        sec
        rtl
.endproc

; [ set bit `A = lore id` in the effective mask at $ee/$ef/$f0 ]
; a8/i16, D = 0 (battle's own; InitSpellList reads the same dp bytes).
; clobbers A,X,Y.
.proc Ot6LoreMaskSet
        .a8
        .i16
        pha                     ; [$01,s] the id
        lsr
        lsr
        lsr
        longa
        and     #$0003
        tax                     ; X = byte index (0..2)
        shorta0
        lda     $01,s
        and     #$07
        longa
        and     #$00ff
        tay                     ; Y = bit index
        shorta0
        lda     #$01
        cpy     #$0000
        beq     @or
:       asl
        dey
        bne     :-
@or:    ora     $ee,x
        sta     $ee,x
        pla
        rtl
.endproc

; [ the choke point: the effective lore mask InitSpellList reads ]
;
; Called from InitSpellList (battle_main.asm) immediately before the lore
; walk, whose `bit $1d29,x` becomes `bit $ee,x`.  Writes 3 bytes:
;
;   MANUAL (any loadout byte nonzero): the bits of the stored, still-learned
;     ids, the player's own five.
;   AUTO (all five bytes zero, the state every pre-existing save is in): the
;     first five known lores in id order.  AUTO truncates past five so the
;     full list is not reachable through inaction, though at 24 candidates
;     the stakes are comfort, not usability.
;
; This runs in every battle's init.  The AUTO arm is one pass over 24 bits
; through Ot6LoreLearned and the MANUAL arm five Ot6LoreSlot resolutions;
; both are O(dozens) of bit tests.  No WRAM data port is involved: the mask
; is three direct-page bytes, and vanilla's walk still performs all its own
; downstream writes.
;
; entry: jsl from InitSpellList, D = 0, db = $7e.  Sets its own widths and
; restores the caller's (Ot6RageList's own discipline; InitSpellList's widths
; at the call site are the caller's business, not an assumption to bake in).
; clobbers A,X,Y.
.proc Ot6LoreMask
        php
        shorta0
        longi
        stz     $ee
        stz     $ef
        stz     $f0
        ldx     #$0000
@zero:  lda     f:OT6_LORELOAD,x
        bne     @manual
        inx
        cpx     #OT6_LORESLOTS
        bcc     @zero
        ; AUTO: the first five known, in id order
        ldy     #$0000          ; ids emitted
        ldx     #$0000          ; candidate id (X here; the helpers clobber it,
                                ;   so it is re-derived from the stack instead)
        lda     #$00
        pha                     ; [$01,s] candidate id
@atry:  lda     $01,s
        jsl     Ot6LoreLearned  ; carry = learned (A preserved, Y preserved)
        bcc     @anext
        phy                     ; Ot6LoreMaskSet clobbers Y
        jsl     Ot6LoreMaskSet
        ply
        iny
        cpy     #OT6_LORESLOTS
        bcs     @adone
@anext: lda     $01,s
        inc     a
        sta     $01,s
        cmp     #$18
        bcc     @atry
@adone: pla                     ; drop the candidate id
        plp
        rtl
@manual:
        lda     #$00
        pha                     ; [$01,s] slot
@slot:  lda     $01,s
        jsl     Ot6LoreSlot     ; carry set + A = id; kills X
        bcc     @next
        jsl     Ot6LoreMaskSet
@next:  lda     $01,s
        inc     a
        sta     $01,s
        cmp     #OT6_LORESLOTS
        bcc     @slot
        pla                     ; drop the slot
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------
; Strago's field configurator: bank-F0 state logic
; Single column of five (the Bushido shape, not Gau's two-column), because
; five rows fit the window's odd-row cadence with the title, hint and LEARNED
; rows intact.  All entries a8/i16, D = 0, rtl.
; ------------------------------------------------------------------------------

; [ is the loadout AUTO?  all five bytes zero ]
; out: carry set = AUTO.  clobbers A,X.  preserves Y.
.proc Ot6LoreIsAuto
        .a8
        .i16
        ldx     #$0000
@lp:    lda     f:OT6_LORELOAD,x
        bne     @manual
        inx
        cpx     #OT6_LORESLOTS
        bcc     @lp
        sec
        rtl
@manual:
        clc
        rtl
.endproc

; [ the lore a slot shows, validated: the page's single source of truth ]
; MANUAL returns the stored, still-learned id; AUTO computes the slot's
; window entry on the fly, so opening the page writes nothing.
; in: A = slot (0..4).  out: carry set + A = lore id, carry clear = blank row.
;   clobbers X.  preserves Y.
.proc Ot6LoreShow
        .a8
        .i16
        pha
        jsl     Ot6LoreIsAuto       ; carry set = AUTO (clobbers A and X)
        pla                         ; A = slot (PLA preserves carry)
        bcs     @auto
        jmp     Ot6LoreSlot         ; tail-call: the stored, validated id
@auto:  jmp     Ot6LoreNth          ; tail-call: the auto window's slot-th id
.endproc

; [ store the AUTO window into the five bytes (the first edit out of AUTO) ]
; clobbers A,X,Y.
.proc Ot6LoreSeed
        .a8
        .i16
        ldy     #$0000
@lp:    tya
        jsl     Ot6LoreNth          ; carry set + A = id; preserves Y, kills X
        bcc     @done               ; fewer than Y+1 learned: the rest stay unset
        inc     a                   ; stored byte = id + 1
        phy
        plx                         ; X = slot (the i16 transfer idiom; Y intact)
        sta     f:OT6_LORELOAD,x
        iny
        cpy     #OT6_LORESLOTS
        bcc     @lp
@done:  rtl
.endproc

; [ open the configurator: cursor to the top slot ]
; clobbers A.
.proc Ot6LoreOpen
        .a8
        .i16
        stz     $4d                 ; cursor: single column
        stz     $4e                 ; ... top slot
        stz     $4f
        stz     $50
        stz     $51
        stz     $52
        rtl
.endproc

; [ which slot is the cursor on?  single column: the row is the slot ]
; a8/i16.  out: A = slot (0..4).  clobbers nothing else.
.proc Ot6LoreCurSlot
        .a8
        .i16
        lda     $4e
        rtl
.endproc

; [ cycle the cursored slot to the prev/next learned lore; go MANUAL ]
; The Ot6RageCycleCore shape over 24 ids, wrapping 0..23.  A slot showing
; nothing starts its walk at id 0.  Uses menu scratch $e0 (D=0).
; in: A = step delta ($01 = next, $ff = previous).  clobbers A,X,Y.
.proc Ot6LoreCycleCore
        .a8
        .i16
        pha                         ; [$01,s] delta
        jsl     Ot6LoreIsAuto
        bcc     :+
        jsl     Ot6LoreSeed         ; first edit: store the window into bytes
:       jsl     Ot6LoreCurSlot      ; cursored slot (0..4)
        jsl     Ot6LoreShow         ; carry set + A = the id it is showing
        bcs     :+
        lda     #$00                ; blank row: start the walk at id 0
:       sta     $e0
        ldy     #$0018              ; try every id once (0..23)
@hop:   lda     $e0
        clc
        adc     $01,s               ; += delta
        cmp     #$18                ; off either end of 0..$17?
        bcc     @have
        lda     $01,s
        bmi     @low                ; delta $ff (down): 0 - 1 wraps to $17
        lda     #$00                ; delta $01 (up):  $17 + 1 wraps to 0
        bra     @have
@low:   lda     #$17
@have:  sta     $e0
        jsl     Ot6LoreLearned      ; carry = learned (A preserved)
        bcs     @found
        dey
        bne     @hop
        pla                         ; nothing learned at all: leave it alone
        rtl
@found: jsl     Ot6LoreCurSlot      ; A = the cursored slot
        longa
        and     #$00ff
        tax                         ; X = slot
        shorta0
        lda     $e0
        inc     a                   ; stored byte = id + 1
        sta     f:OT6_LORELOAD,x
        pla                         ; drop delta
        rtl
.endproc

Ot6LoreNext:                        ; R shoulder -> next learned lore
        lda     #$01
        jmp     Ot6LoreCycleCore
Ot6LorePrev:                        ; L shoulder -> previous learned lore
        lda     #$ff
        jmp     Ot6LoreCycleCore

; [ per-frame input: mutate loadout state; tell C3 what to do next ]
; The shared contract: 0 = idle, 1 = redraw, 2 = exit.  Single column, so the
; dpad's Left/Right have nothing to toggle and stay idle; the shoulders cycle
; (the Bushido page's own scheme, which this page's shape matches).
;   B      -> exit               (return A = 2)
;   Up/Dn  -> move the row       (return A = 1)
;   Y      -> revert to AUTO     (return A = 1)
;   L/R    -> cycle the slot     (return A = 1)
.proc Ot6LoreInput
        .a8
        .i16
        lda     $09                 ; dpad / B / Y / Select / Start
        bit     #$80                ; B -> exit
        beq     :+
        lda     #$02
        rtl
:       bit     #$08                ; Up
        beq     @dn
        lda     $4e
        bne     :+
        lda     #OT6_LOREROWS       ; wrap 0 -> last row (pre-decrement)
:       dec     a
        sta     $4e
        lda     #$01
        rtl
@dn:    lda     $09
        bit     #$04                ; Down
        beq     @sel
        lda     $4e
        inc     a
        cmp     #OT6_LOREROWS
        bcc     :+
        lda     #$00                ; wrap last -> 0
:       sta     $4e
        lda     #$01
        rtl
@sel:   lda     $09
        bit     #$40                ; Y -> revert to AUTO (all five bytes 0)
        beq     @lr
        ldx     #$0000
        lda     #$00
:       sta     f:OT6_LORELOAD,x
        inx
        cpx     #OT6_LORESLOTS
        bcc     :-
        lda     #$01
        rtl
@lr:    lda     $08                 ; A / X / L / R shoulders
        bit     #$20                ; L shoulder -> previous learned lore
        beq     @rsh
        jsl     Ot6LorePrev
        lda     #$01
        rtl
@rsh:   lda     $08
        bit     #$10                ; R shoulder -> next learned lore
        beq     @idle
        jsl     Ot6LoreNext
        lda     #$01
        rtl
@idle:  lda     #$00
        rtl
.endproc

; [ how many lores are known?  the collection score ]
; Popcount of $1d29-$1d2b.  Max 24, so two digits.
; out: A = count (0..24).  clobbers A,X,Y and menu scratch $e0/$e1.
.proc Ot6LoreCount
        .a8
        .i16
        ldx     #$0000
        ldy     #$0000              ; running count
@byte:  lda     f:$7e1d29,x
        beq     @next
        sta     $e0
        lda     #$08
        sta     $e1
@bit:   lsr     $e0
        bcc     :+
        iny
:       dec     $e1
        bne     @bit
@next:  inx
        cpx     #$0003              ; 3 bytes
        bcc     @byte
        tya                         ; a8: the count's low byte
        rtl
.endproc

; [ price a lore row: the vanilla spell price, read from the shipped table ]
; Lores are spell-shaped (spell id = lore id + $8b) and their MP costs are
; vanilla MagicProp data, charged by vanilla's own battle path -- these are
; not OT6-added prices, so there is no OT6_MP_COSTS gate and the page draws
; them under nomp too.  Per-row rather than flat because the prices differ
; per lore, which is the one display difference from the possess-verb pages.
; menu-caller only: uses menu scratch $e0 (D = 0).
; in: A = lore id (0..23).  out: A = MP cost.  clobbers A,X and $e0/$e1.
.proc Ot6LoreRowCost
        .a8
        .i16
        clc
        adc     #$8b                ; spell id ($8b..$a2)
        longa
        and     #$00ff
        asl                         ; n*2
        sta     $e0
        asl
        asl
        asl                         ; n*16
        sec
        sbc     $e0                 ; n*14 = MagicProp record offset
        tax
        shorta0
        lda     f:MagicProp+5,x     ; the spell's mp cost
        rtl
.endproc
