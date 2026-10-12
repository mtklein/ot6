; ------------------------------------------------------------------------------
; OT6: Edgar's Overclock, the divine of his Tools (#378)
;
; kits.md: Overclock uses two tools in one action, and its price is the sum
; of the two it fires.  The divine's one gate is a full 3-BP boost (kits.md
; "Divines", owner 2026-10-11): once EDGAR has learned it, a Tool he boosts
; with all three points is overclocked -- it fires twice in the action,
; each firing a whole pass at the boost's x8 (Ot6BoostDmg's multiplier, which
; Tools take), so two tools' worth of hits, chips and damage land for one
; turn.  There is no once-a-battle limit: three points buy it every time.
;
; Why the chosen tool twice rather than two different tools: the Tools shell
; picks one row, and the engine runs one item's record per action (Cmd_09's
; ItemProp load).  Two firings of the row the player picked keep the menu
; one press and the effect legible (the tool's own animation, twice), and
; the price says it: the sum of the two firings, each at the 3-BP price
; (x15.625, capped at 99), capped at 99 as every price is.
;
; Learned at the Magitek factory: event switch $0068, set where Cid opens
; the way out of the tube room after the espers' scene (event_main.asm, "CID:
; Quick! Over here!") and never cleared.  Celes's RunicBlade is learned on the
; same switch (ot6_runicblade.asm).
;
; Every surface asks Ot6Overclocks, so the drawn price, the grey, the confirm,
; the charge and the passes cannot disagree:
;   the draw     Ot6ToolRowDecorate   -> Ot6PendToolPrice
;   the confirm  Ot6KitRowCost (mode 0) -> Ot6PendToolPrice
;   the charge   Ot6AbilityCost (cmd $09) -> Ot6ToolPrice
;   the passes   Ot6HitCount (a tool id) -> Ot6OverclockPasses
; ------------------------------------------------------------------------------

.segment "ot6_code"

OT6_CHAR_EDGAR   = $04
OT6_FACTORY_SW   = $1e80 + ($68 >> 3)   ; switch $0068: the tube room's exit
OT6_FACTORY_BIT  = 1 << ($68 & 7)

; [ does this character's Tool overclock? ]
; EDGAR, Overclock learned, and a full 3-BP boost pending.
; in: x = entity offset (either width), db = $7e, a8.  out: carry set = yes.
; clobbers A; preserves X and Y.
.proc Ot6Overclocks
        .a8
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     @no
        lda     $3ed8,x         ; character id
        cmp     #OT6_CHAR_EDGAR
        bne     @no
        lda     OT6_BOOST_REVEALED,x
        cmp     #$03            ; the divine's one gate: a full boost
        bcc     @no
        lda     f:$7e0000+OT6_FACTORY_SW
        and     #OT6_FACTORY_BIT
        beq     @no             ; not learned yet
        sec
        rtl
@no:    clc
        rtl
.endproc

; [ a Tool's price for this caster: the escalated row, twice when overclocked ]
; in: A = tool item id, X = caster entity offset.  out: A = price.
; a8/i16, db = $7e; preserves X and Y.
.proc Ot6ToolPrice
        .a8
        .i16
        jsl     Ot6CostFor      ; the row's base
        jsl     Ot6BoostPriceFor        ; x2.5 per pending boost, capped at 99
        pha
        jsl     Ot6Overclocks
        pla                     ; (pla leaves the carry alone)
        bcc     @out
        cmp     #$00
        beq     @out            ; an unpriced cell stays 0
        asl                     ; two firings, each at that price
        bcs     @cap
        cmp     #100
        bcc     @out
@cap:   lda     #99             ; the two-digit ceiling every price takes
@out:   rtl
.endproc

; [ the same, for the caster whose menu is open ($62ca), Ot6PendPrice's twin ]
; in: A = tool item id.  out: A = price.  a8/i16, db = $7e; preserves X, Y.
.proc Ot6PendToolPrice
        .a8
        .i16
        phx
        phy
        pha
        lda     $62ca           ; active caster slot
        longa
        and     #$0003
        asl                     ; slot -> entity offset
        tax
        shorta0
        pla
        jsl     Ot6ToolPrice
        ply
        plx
        rtl
.endproc

; [ an overclocked Tool fires twice: double the action's passes ]
; From Ot6HitCount, after the tool's own extra hits (Drill's x2) are added:
; passes = $3a70 + 1, so twice the passes is 2 * $3a70 + 1.  Drill's two
; strikes become four.
; in: A = tool item id, Y = the attacker (Cmd_09's own), db = $7e, a8, i16.
; preserves A, X, Y.
.proc Ot6OverclockPasses
        .a8
        .i16
        pha
        phx
        tyx
        jsl     Ot6Overclocks
        bcc     @out
        lda     f:$7e0000+$3a70
        asl
        inc     a
        sta     f:$7e0000+$3a70
        jsl     Ot6PassesAdded  ; a firing whose body fell retargets
@out:   plx
        pla
        rtl
.endproc
