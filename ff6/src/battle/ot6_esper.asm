; ------------------------------------------------------------------------------
; OT6: the esper rework, plan A (#328, docs/design/esper-rework.md)
;
; A won battle pays its Magic Points (BattleMagicPoints, doubled for a random
; battle as experience and gil are: Ot6RewardMulW) to each living seated
; member, into that member's counter for the stone the member wears.  Every
; esper has the same five rungs (10 / 30 / 75 / 200 / 500 Magic Points); a
; rung once reached is kept for good, whatever is worn later.  The rungs hold
; stat points and relic-style effects, folded into UpdateEquip as one more
; piece of gear (Ot6EsperFold), so the menu's stats and the battle's read the
; same numbers.  This replaces vanilla's learn rates (LearnGenjuMagic), its
; level-up bonus (DoLevelUp's GenjuBonusTbl call) and OT6's while-worn stat
; packages (Ot6EsperStatMod), all retired.
;
; The counters live in expanded SRAM (ot6_memory.inc OT6_ESPER_*): a live
; page that play reads and writes, copied from the slot on a load and into
; the slot on a save.
; ------------------------------------------------------------------------------

.segment "ot6_code"

OT6_ESPER_MAGIC_WORD = $3145    ; 'E1'
OT6_ESPER_MSG        = $49      ; AttackMsg $49: "<char>'s esper reached rank <v0>"

; the rungs' cumulative costs, shared with the menu
OT6_RUNG1 = 10
OT6_RUNG2 = 30
OT6_RUNG3 = 75
OT6_RUNG4 = 200
OT6_RUNG5 = 500
OT6_ESPER_CAP = 9999            ; a counter stops here (the menu shows 4 digits)

; the two signatures labbed before they ship (#328: "lab half-cost spells and
; permanent Haste before shipping them"): Shiva's Gold Hairpin bit (ItemProp
; +11 $20) and Odin's RunningShoes bit (+8 $08).  0 holds one back.
OT6_SIG_HALFMP = $20
OT6_SIG_HASTE  = $08

OT6_REC = 14                    ; bytes per rung record (Ot6LadderTbl)

; esper index (GenjuProp order, 0..26) in A (a8) -> counter slot 0..25 in A:
; Raiden (12) shares Odin's (11) and everything past it moves down one.
.proc Ot6EsperSlot
        .a8
        cmp     #12
        bcc     @done
        beq     @odin
        dec
        rts
@odin:  lda     #11
@done:  rts
.endproc

; A (a16) = Magic Points -> A (a16) = the rungs they reach, 0..5; Z set on 0.
.proc Ot6EsperRankA
        .a16
        cmp     #OT6_RUNG5
        bcs     @r5
        cmp     #OT6_RUNG4
        bcs     @r4
        cmp     #OT6_RUNG3
        bcs     @r3
        cmp     #OT6_RUNG2
        bcs     @r2
        cmp     #OT6_RUNG1
        bcs     @r1
        lda     #$0000
        rts
@r1:    lda     #$0001
        rts
@r2:    lda     #$0002
        rts
@r3:    lda     #$0003
        rts
@r4:    lda     #$0004
        rts
@r5:    lda     #$0005
        rts
.endproc

; A (a16) = actor 0..11 -> A (a16) = actor * 52, that actor's first counter's
; offset past OT6_ESPER_CTR.  Clobbers nothing else.
.proc Ot6EsperRowOff
        .a16
        asl
        asl                     ; x4
        pha
        asl
        asl                     ; x16
        pha
        asl                     ; x32
        clc
        adc     1,s
        adc     3,s             ; x52
        sta     3,s
        pla
        pla
        rts
.endproc

; Clear the live page's counters and sign it.  a/x widths saved.
.proc Ot6EsperClearLive
        php
        longai
        phx
        ldx     #OT6_ESPER_CTR
        lda     #$0000
@clr:   sta     f:OT6_ESPER_LIVE,x
        inx
        inx
        cpx     #OT6_ESPER_SHOWN + 2
        bcc     @clr
        lda     #OT6_ESPER_MAGIC_WORD
        sta     f:OT6_ESPER_LIVE+OT6_ESPER_MAGIC
        plx
        plp
        rts
.endproc

; Make sure the live page is signed (a battery from an earlier build, or a
; savestate that never passed a load or New Game, has none): an unsigned page
; starts from zero.
.proc Ot6EsperEnsureLive
        php
        longa
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_MAGIC
        cmp     #OT6_ESPER_MAGIC_WORD
        beq     @ok
        jsr     Ot6EsperClearLive
@ok:    plp
        rts
.endproc

; [ lifecycle: New Game, load, save ]
; Called from the codex's lifecycle procs (ot6_codex.asm), which vanilla's
; menu already calls at these three moments.

; New Game: no esper progress.
.proc Ot6EsperNewGame
        jsr     Ot6EsperClearLive
        rts
.endproc

; A validated load of slot A (1..3): the slot's page becomes the live page.  A
; slot page with no signature (a save made before this build) reads as no
; progress.  a/x widths saved; A preserved.
.proc Ot6EsperLoaded
        php
        longai
        pha
        phx
        and     #$0003
        dec
        xba
        asl
        asl                     ; (slot - 1) * $400
        tax
        lda     f:OT6_ESPER_ROOT+OT6_ESPER_MAGIC,x
        cmp     #OT6_ESPER_MAGIC_WORD
        beq     @copy
        jsr     Ot6EsperClearLive
        bra     @done
@copy:  lda     3,s             ; the slot (under the phx)
        jsr     Ot6EsperCopySlotToLive
        lda     #OT6_ESPER_MAGIC_WORD
        sta     f:OT6_ESPER_LIVE+OT6_ESPER_MAGIC
@done:  plx
        pla
        plp
        rts
.endproc

; The title screen's Continue (field_menu.asm MenuState_23, on the confirm):
; vanilla loads the slot there and never passes LoadSavedGame, which only the
; reload after a game over calls.  A (a8) = the slot.  rtl.
.proc Ot6EsperContinue
        php
        jsr     Ot6EsperLoaded
        plp
        rtl
.endproc

; A (a16) = slot 1..3.  Copy that slot page's counters into the live page.
; The three slots get their own loops so no scratch cell is needed.
.proc Ot6EsperCopySlotToLive
        .a16
        .i16
        and     #$0003
        cmp     #$0002
        beq     @two
        cmp     #$0003
        beq     @three
        ldx     #OT6_ESPER_CTR
@c1:    lda     f:OT6_ESPER_ROOT,x
        sta     f:OT6_ESPER_LIVE,x
        inx
        inx
        cpx     #OT6_ESPER_COPY
        bcc     @c1
        rts
@two:   ldx     #OT6_ESPER_CTR
@c2:    lda     f:OT6_ESPER_ROOT+OT6_ESPER_STRIDE,x
        sta     f:OT6_ESPER_LIVE,x
        inx
        inx
        cpx     #OT6_ESPER_COPY
        bcc     @c2
        rts
@three: ldx     #OT6_ESPER_CTR
@c3:    lda     f:OT6_ESPER_ROOT+OT6_ESPER_STRIDE*2,x
        sta     f:OT6_ESPER_LIVE,x
        inx
        inx
        cpx     #OT6_ESPER_COPY
        bcc     @c3
        rts
.endproc

; A save into slot A (1..3): the live page's counters become that slot's
; page, signed.  a/x widths saved; A preserved.
.proc Ot6EsperSaveAs
        php
        longai
        pha
        phx
        jsr     Ot6EsperEnsureLive
        lda     1+2,s           ; the slot (under the phx)
        and     #$0003
        cmp     #$0002
        beq     @two
        cmp     #$0003
        beq     @three
        ldx     #OT6_ESPER_CTR
@c1:    lda     f:OT6_ESPER_LIVE,x
        sta     f:OT6_ESPER_ROOT,x
        inx
        inx
        cpx     #OT6_ESPER_COPY
        bcc     @c1
        lda     #OT6_ESPER_MAGIC_WORD
        sta     f:OT6_ESPER_ROOT+OT6_ESPER_MAGIC
        bra     @done
@two:   ldx     #OT6_ESPER_CTR
@c2:    lda     f:OT6_ESPER_LIVE,x
        sta     f:OT6_ESPER_ROOT+OT6_ESPER_STRIDE,x
        inx
        inx
        cpx     #OT6_ESPER_COPY
        bcc     @c2
        lda     #OT6_ESPER_MAGIC_WORD
        sta     f:OT6_ESPER_ROOT+OT6_ESPER_STRIDE+OT6_ESPER_MAGIC
        bra     @done
@three: ldx     #OT6_ESPER_CTR
@c3:    lda     f:OT6_ESPER_LIVE,x
        sta     f:OT6_ESPER_ROOT+OT6_ESPER_STRIDE*2,x
        inx
        inx
        cpx     #OT6_ESPER_COPY
        bcc     @c3
        lda     #OT6_ESPER_MAGIC_WORD
        sta     f:OT6_ESPER_ROOT+OT6_ESPER_STRIDE*2+OT6_ESPER_MAGIC
@done:  plx
        pla
        plp
        rts
.endproc

; ------------------------------------------------------------------------------

; [ earn at victory ]
;
; jsl from WinBattle's per-character loop, in place of vanilla's
; `lda $161e,x / bmi / jsr LearnGenjuMagic`: the loop has already skipped a
; member who is not alive (vanilla pays only the battle's living party; the
; bench earns nothing).  in: X = the character record offset ($3010,y), $fb
; = the formation's Magic Points, and the member's battle slot * 2 on the
; stack under the return address (the loop's `phy`: LearnItemMagic, called
; just before, leaves Y clobbered).  a8, i16, db=$7e.  Preserves x/y.
OT6_EARN_SEAT = 9               ; 1,s.. after php/phx/phy: Y 1-2, X 3-4, P 5,
                                ;   the return address 6-8, the loop's Y 9-10
.proc Ot6EsperEarn
        .a8
        .i16
        php
        phx
        phy
        lda     $161e,x         ; the worn esper
        bmi     @quit           ; none
        pha
        lda     $1600,x         ; actor
        cmp     #OT6_ESPER_CHARS
        pla
        bcs     @quit           ; a guest: no counters
        jsr     Ot6EsperSlot
        sta     OT6_SCR_IDX     ; the counter slot (OT6_SCR_*: victory-time
                                ;   scratch, as Ot6RewardScale_ext uses it)
        lda     $fb
        bne     @pays
@quit:  brl     @out            ; this battle pays nothing
@pays:
        jsr     Ot6EsperEnsureLive
        ; the points: $fb, times Ot6RewardMulW/16 for a random battle
        longa
        lda     $fb
        and     #$00ff
        tax                     ; X = the points
        lda     a:OT6_RANDBTL
        and     #$00ff
        beq     @plain
        lda     f:Ot6RewardMulW
        and     #$00ff
        tay                     ; Y = the multiplier in 16ths
        lda     #$0000
@mul:   cpy     #$0000
        beq     @mdone
        stx     OT6_SCR_SLOT2   ; the points
        clc
        adc     OT6_SCR_SLOT2
        dey
        bra     @mul
@mdone: lsr
        lsr
        lsr
        lsr
        tax
@plain: stx     OT6_SCR_SLOT2   ; the points paid
        txa
        sta     f:OT6_ESPER_LIVE+OT6_ESPER_SHOWN
        ; the counter: (actor * 26 + slot) * 2
        lda     3,s             ; X on entry: the character record
        tax
        lda     $1600,x         ; actor
        and     #$00ff
        jsr     Ot6EsperRowOff
        sta     OT6_SCR_BIT     ; the actor's row offset
        lda     OT6_SCR_IDX
        and     #$00ff
        asl
        clc
        adc     OT6_SCR_BIT
        tax                     ; X = the counter's offset past CTR
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_CTR,x
        pha                     ; the old count
        clc
        adc     OT6_SCR_SLOT2
        bcs     @cap
        cmp     #OT6_ESPER_CAP+1
        bcc     @store
@cap:   lda     #OT6_ESPER_CAP
@store: sta     f:OT6_ESPER_LIVE+OT6_ESPER_CTR,x
        jsr     Ot6EsperRankA
        sta     OT6_SCR_BIT     ; the new rank
        pla
        jsr     Ot6EsperRankA
        cmp     OT6_SCR_BIT
        bcs     @nonew          ; no rung crossed
        lda     OT6_EARN_SEAT,s ; the loop's Y: the battle slot * 2
        and     #$00ff
        lsr                     ; the party slot 0..3
        tax
        shorta
        lda     OT6_SCR_BIT
        sta     f:OT6_ESPER_LIVE+OT6_ESPER_PEND,x
@nonew:
@out:   ply
        plx
        plp
        rtl
.endproc

; [ the victory screen's Magic Points and rank lines ]
;
; jsl from WinBattle after the per-character loop, in place of vanilla's
; "Got <v0> Magic Point(s)" block, which showed only when a spell was being
; learned or Morph was ready.  Shows the points whenever a living member
; wore a stone in a battle that paid some, then one line per member who
; reached a new rank.  a8, i16, db=$7e.  Preserves x/y.
.proc Ot6EsperMsg
        .a8
        .i16
        php
        phx
        phy
        longa
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_MAGIC
        cmp     #OT6_ESPER_MAGIC_WORD
        bne     @out            ; nobody earned (the page was never signed)
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_SHOWN
        beq     @ranks
        sta     $2f35           ; variable 0
        shorta
        stz     $2f37
        lda     #$35            ; "Got <v0> Magic Point(s)"
        jsr     Ot6ShowMsg
@ranks: shorta
        ldx     #$0000
@slot:  lda     f:OT6_ESPER_LIVE+OT6_ESPER_PEND,x
        beq     @next
        sta     $2f35           ; variable 0: the rank
        stz     $2f36
        stz     $2f37
        txa
        sta     $2f38           ; variable 1: the member (by battle slot)
        lda     #OT6_ESPER_MSG
        jsr     Ot6ShowMsg
@next:  inx
        cpx     #$0004
        bcc     @slot
        longa
        lda     #$0000
        sta     f:OT6_ESPER_LIVE+OT6_ESPER_PEND
        sta     f:OT6_ESPER_LIVE+OT6_ESPER_PEND+2
        sta     f:OT6_ESPER_LIVE+OT6_ESPER_SHOWN
@out:   ply
        plx
        plp
        rtl
.endproc

; ShowMsg's body for a caller in this bank: message A (a8) through battle
; graphics command 4.  db=$7e.  Preserves x/y.
.proc Ot6ShowMsg
        .a8
        php
        phx
        phy
        shorta
        longi
        sta     $2d6f
        lda     #$02            ; battle script command $02 (show battle message)
        sta     $2d6e
        lda     #$ff
        sta     $2d72
        lda     #$04            ; battle graphics $04 (execute battle script)
        jsl     ExecBtlGfx_ext
        ply
        plx
        plp
        rts
.endproc

; ------------------------------------------------------------------------------

; [ the kept bonuses, folded into UpdateEquip ]
;
; jsl from UpdateEquip right after its equipment loop, before the HP/MP boost
; flags and the stat clamps are read, so every rung the character has reached
; on every esper adds to the $11xx buffer the way one more relic would: the
; effect bytes OR'd into the same cells CalcEquipEffect fills (ItemProp +5 to
; +13 and +25), the stat points added to the words it adds a relic's boosts
; to.  The HP and MP boosts are bits CheckHPBoost reads largest-first, so the
; largest of several applies.  An earring rung counts as one earring, never a
; second: a character who already wears one gains nothing.  Every caller of
; UpdateEquip (the menus, the field, battle init and re-derivation) sees the
; same result.
;
; in: X = UpdateEquip's record index after the equipment loop (the actor is
; $15dd,x), db=$7e, a8 i16.  Preserves a/x/y and p.
.proc Ot6EsperFold
        php
        longai
        pha
        phx
        phy
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_MAGIC
        cmp     #OT6_ESPER_MAGIC_WORD
        bne     @out            ; no progress page: nothing kept
        lda     $15dd,x         ; the actor
        and     #$00ff
        cmp     #OT6_ESPER_CHARS
        bcs     @out
        jsr     Ot6EsperRowOff
        tax                     ; X = this actor's first counter
        ldy     #$0000          ; Y = this esper's first rung record
@esper: lda     f:OT6_ESPER_LIVE+OT6_ESPER_CTR,x
        jsr     Ot6EsperRankA
        beq     @next
        phx
        pha                     ; rungs left to apply
        tyx
@rung:  jsr     Ot6EsperApply
        txa
        clc
        adc     #OT6_REC
        tax
        lda     1,s
        dec
        sta     1,s
        bne     @rung
        pla
        plx
@next:  inx
        inx
        tya
        clc
        adc     #OT6_REC * 5
        tay
        cpy     #OT6_REC * 5 * OT6_ESPER_SLOTS
        bcc     @esper
@out:   ply
        plx
        pla
        plp
        rtl
.endproc

; One rung record at Ot6LadderTbl+X onto the $11xx buffer.  a16 in and out,
; db=$7e; preserves x/y.
.proc Ot6EsperApply
        .a16
        .i16
        shorta
        lda     f:Ot6LadderTbl+0,x      ; +5 field effects
        tsb     $11df
        lda     f:Ot6LadderTbl+1,x      ; +6 status 1 protection
        tsb     $11d2
        lda     f:Ot6LadderTbl+2,x      ; +7 status 2 protection
        tsb     $11d3
        lda     f:Ot6LadderTbl+3,x      ; +8 status 3 set
        tsb     $11d4
        lda     f:Ot6LadderTbl+4,x      ; +9 relic effects (HP/MP boosts, atlas)
        and     #$fd                    ;   ...but the earring bit, which
        tsb     $11d5                   ;   vanilla moves to $11d7 per piece
        lda     f:Ot6LadderTbl+4,x
        and     #$02
        tsb     $11d7                   ; one earring, never a second
        lda     f:Ot6LadderTbl+5,x      ; +10
        tsb     $11d6
        lda     f:Ot6LadderTbl+6,x      ; +11
        tsb     $11d7
        lda     f:Ot6LadderTbl+7,x      ; +12
        tsb     $11d8
        lda     f:Ot6LadderTbl+8,x      ; +13
        tsb     $11d9
        lda     f:Ot6LadderTbl+9,x      ; +25 status 2 set
        tsb     $11bc
        longa
        lda     f:Ot6LadderTbl+10,x     ; vigor
        and     #$00ff
        clc
        adc     $11a6
        sta     $11a6
        lda     f:Ot6LadderTbl+11,x     ; speed
        and     #$00ff
        clc
        adc     $11a4
        sta     $11a4
        lda     f:Ot6LadderTbl+12,x     ; stamina
        and     #$00ff
        clc
        adc     $11a2
        sta     $11a2
        lda     f:Ot6LadderTbl+13,x     ; mag.pwr
        and     #$00ff
        clc
        adc     $11a0
        sta     $11a0
        rts
.endproc

; ------------------------------------------------------------------------------

; [ the signatures that are new code ]
;
; Four rung-5 effects have no vanilla bit (docs/design/esper-rework.md, the
; table's dagger rows): Conductor (Ramuh), Facet (Carbunkl), Rebirth
; (Phoenix), and Fenrir's Stop and Slow immunity.  (The fifth, Sraphim's
; Grace, has a vanilla stand-in: see Ot6LadderTbl.)  Each asks Ot6EsperSig
; whether the character holds it.

OT6_SLOT_RAMUH    = 0
OT6_SLOT_CARBUNKL = 18
OT6_SLOT_PHOENIX  = 25
OT6_SLOT_FENRIR   = 23

; in: A (16 bits, whatever the m flag) = actor | counter slot << 8.  out: C set
; when that actor's count on that esper has reached the signature (rung 5).
; Preserves a/x/y and every flag but C.  rts.
.proc Ot6EsperSig
        php
        longai
        phx
        pha
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_MAGIC
        cmp     #OT6_ESPER_MAGIC_WORD
        bne     @no
        lda     1,s
        and     #$00ff
        cmp     #OT6_ESPER_CHARS
        bcs     @no
        jsr     Ot6EsperRowOff
        pha                     ; [row] [actor | slot << 8]
        lda     4,s             ; the slot byte
        and     #$00ff
        asl
        clc
        adc     1,s
        tax
        pla
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_CTR,x
        cmp     #OT6_RUNG5      ; C = reached
        bra     @out
@no:    clc
@out:   pla                     ; (pulls leave C alone)
        plx
        bcs     @yes
        plp
        clc
        rts
@yes:   plp
        sec
        rts
.endproc

; jsl from InitChars after LoadCharProp, once per seated character at battle
; start.  x = the battle slot * 2 (either index width), db = $7e.  Facet:
; the boost bank opens at two points (Ot6InitBP opened it at one).  Rebirth:
; the character enters under Life 3 (status 4 bit $04, through the status-to-
; set cell LoadCharProp fills, $3de9).  Preserves everything.
.proc Ot6EsperBattleInit
        php
        longi
        shorta
        pha
        lda     $3ed8,x         ; actor
        xba
        lda     #OT6_SLOT_CARBUNKL
        xba
        jsr     Ot6EsperSig
        bcc     @rebirth
        lda     #$02
        sta     OT6_BP_CLASS,x  ; Facet
@rebirth:
        lda     $3ed8,x
        xba
        lda     #OT6_SLOT_PHOENIX
        xba
        jsr     Ot6EsperSig
        bcc     @out
        lda     $3de9,x         ; status 4 to set at the start
        ora     #$04            ; Life 3
        sta     $3de9,x
@out:   pla
        plp
        rtl
.endproc

; Fenrir's signature: immune to Stop and Slow.  jsl from the end of
; UpdateImmuneStatus in place of its `sta $3330,x` (the status-3/4 mask a
; status must pass to land; a clear bit blocks it), so it runs at battle start
; and whenever the mask is rebuilt, and after vanilla's "block both slow and
; haste if immune to either" rule, which would otherwise block Haste too.
; in: A (a8) = the mask, x = the entity (either index width), db = $7e.
.proc Ot6EsperImmune
        .a8
        php
        pha
        txa
        cmp     #$08
        bcs     @store          ; a monster
        lda     $3ed8,x
        xba
        lda     #OT6_SLOT_FENRIR
        xba
        jsr     Ot6EsperSig
        bcc     @store
        pla
        and     #<~(STATUS3::SLOW | STATUS3::STOP)
        pha
@store: pla
        sta     $3330,x
        plp
        rtl
.endproc

; Conductor: A (a8) = the shields a lightning-weak monster has left after a
; hit's chip; x = the attacker.  One more goes when the attacker holds
; Ramuh's signature and the hit carried lightning ($11a1 bit $04).  rts from
; Ot6Chip (same bank).  Preserves x/y.
.proc Ot6Conductor
        .a8
        beq     @out            ; none left to take
        pha
        lda     $11a1
        and     #$04            ; lightning
        beq     @keep
        txa
        cmp     #$08
        bcs     @keep           ; a monster's attack
        lda     $3ed8,x
        xba
        lda     #OT6_SLOT_RAMUH
        xba
        jsr     Ot6EsperSig
        bcc     @keep
        pla
        dec     a
        rts
@keep:  pla
@out:   rts
.endproc

; ------------------------------------------------------------------------------

; [ a character's progress on one esper, for the menu ]
;
; in: A (a8) = actor, X (i16) = esper index (GenjuProp order).  out: A (a16) =
; Magic Points earned (0 for a guest or with no page).  db unknown; preserves
; x/y; the caller's widths are restored except A, which returns 16-bit wide
; in a register the caller reads as a word (the menu reads it longa).
.proc Ot6EsperProgress
        php
        longai
        phx
        phy
        and     #$00ff
        cmp     #OT6_ESPER_CHARS
        bcs     @none
        pha
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_MAGIC
        cmp     #OT6_ESPER_MAGIC_WORD
        beq     :+
        pla
        bra     @none
:       pla
        jsr     Ot6EsperRowOff
        pha
        txa
        shorta
        jsr     Ot6EsperSlot
        longa
        and     #$00ff
        asl
        clc
        adc     1,s
        tax
        pla
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_CTR,x
        bra     @done
@none:  lda     #$0000
@done:  ply
        plx
        plp
        rtl
.endproc

; the rungs' costs as words, for the menu
Ot6RungCostTbl:
        .word   OT6_RUNG1, OT6_RUNG2, OT6_RUNG3, OT6_RUNG4, OT6_RUNG5

; ------------------------------------------------------------------------------

; [ the ladder ]
;
; Ot6LadderTbl: 26 espers (counter-slot order: GenjuProp order with Odin and
; Raiden as one) x 5 rungs x OT6_REC bytes:
;   +0..+8  ItemProp +5..+13 (field, status 1/2 protection, status 3 set,
;           relic effects)
;   +9      ItemProp +25 (status 2 set)
;   +10..13 vigor, speed, stamina, mag.pwr points
; docs/design/esper-rework.md's table; tools/check_esper_ladder.py holds the
; ROM to it.

; one rung: the effect bytes and the stat points, in the record's order
.mac rung fld, p1, p2, s3, r9, r10, r11, r12, r13, s2, vig, spd, stm, mag
        .byte   fld, p1, p2, s3, r9, r10, r11, r12, r13, s2
        .byte   vig, spd, stm, mag
.endmac
; a stat rung: points only
.mac stat vig, spd, stm, mag
        rung    0,0,0,0,0,0,0,0,0,0, vig, spd, stm, mag
.endmac
; an effect rung: the ten effect bytes only
.mac eff fld, p1, p2, s3, r9, r10, r11, r12, r13, s2
        rung    fld, p1, p2, s3, r9, r10, r11, r12, r13, s2, 0, 0, 0, 0
.endmac
; nothing (a rung whose effect is new code, not a vanilla bit: see the
; signature hooks below)
.mac none
        rung    0,0,0,0,0,0,0,0,0,0, 0, 0, 0, 0
.endmac

; status 1 / 2 bits (const.inc STATUS1 / STATUS2)
S1_DARK   = $01
S1_ZOMBIE = $02
S1_POISON = $04
S1_IMP    = $20
S1_PETRIFY= $40
S1_DEATH  = $80
S2_DOOM   = $01
S2_MUTE   = $08
S2_BSERK  = $10
S2_MUDDLE = $20
S2_SEIZE  = $40
S2_SLEEP  = $80

Ot6LadderTbl:
;                fld  p1  p2  s3  r9  r10 r11 r12 r13 s2
; 0 Ramuh: Stm / Mag; immune to Dark; Conductor (new code)
        stat    0,0,1,0
        stat    0,0,0,1
        eff     0,S1_DARK,0,0,0,0,0,0,0,0
        stat    0,0,2,0
        none
; 1 Ifrit: Vig / Stm; max HP +12.5% (Green Beret); Fight damage up (Atlas)
        stat    1,0,0,0
        stat    0,0,1,0
        eff     0,0,0,0,$10,0,0,0,0,0
        stat    2,0,0,0
        eff     0,0,0,0,$01,0,0,0,0,0
; 2 Shiva: Mag / Spd; immune to Seizure; spells at half MP (Gold Hairpin)
        stat    0,0,0,1
        stat    0,1,0,0
        eff     0,0,S2_SEIZE,0,0,0,0,0,0,0
        stat    0,0,0,2
        eff     0,0,0,0,0,0,OT6_SIG_HALFMP,0,0,0
; 3 Siren: Spd / Mag; immune to Sleep; immune to Berserk and Muddle (Peace Ring)
        stat    0,1,0,0
        stat    0,0,0,1
        eff     0,0,S2_SLEEP,0,0,0,0,0,0,0
        stat    0,2,0,0
        eff     0,0,S2_BSERK|S2_MUDDLE,0,0,0,0,0,0,0
; 4 Terrato: Mag / Stm; counters (Black Belt); max HP +50% (Muscle Belt)
        stat    0,0,0,1
        stat    0,0,1,0
        eff     0,0,0,0,0,0,0,$02,0,0
        stat    0,0,0,2
        eff     0,0,0,0,$08,0,0,0,0,0
; 5 Shoat: Spd / Stm; immune to Petrify; immune to Death and Doom
        stat    0,1,0,0
        stat    0,0,1,0
        eff     0,S1_PETRIFY,0,0,0,0,0,0,0,0
        stat    0,2,0,0
        eff     0,S1_DEATH,S2_DOOM,0,0,0,0,0,0,0
; 6 Maduin: Mag / Stm; max MP +12.5% (Bard's Hat); spell damage up (Earrings)
        stat    0,0,0,1
        stat    0,0,1,0
        eff     0,0,0,0,$80,0,0,0,0,0
        stat    0,0,0,2
        eff     0,0,0,0,$02,0,0,0,0,0
; 7 Bismark: Vig / Stm; Safe at low HP (MithrilGlove); max HP +25% (Red Cap)
        stat    1,0,0,0
        stat    0,0,1,0
        eff     0,0,0,0,0,0,0,0,$02,0
        stat    2,0,0,0
        eff     0,0,0,0,$04,0,0,0,0,0
; 8 Stray: Mag / Spd; immune to Imp; steals more often (Sneak Ring)
        stat    0,0,0,1
        stat    0,1,0,0
        eff     0,S1_IMP,0,0,0,0,0,0,0,0
        stat    0,0,0,2
        eff     0,0,0,0,0,0,$01,0,0,0
; 9 Palidor: Spd / Vig; walks faster (Sprint Shoes); Float (Cherub Down)
        stat    0,1,0,0
        stat    1,0,0,0
        eff     $20,0,0,0,0,0,0,0,0,0
        stat    0,2,0,0
        eff     0,0,0,$01,0,0,0,0,0,0
; 10 Tritoch: Mag / Spd; +1 speed; immune to Dark and Petrify (Jewel Ring)
;    and max MP +50% (Crystal Orb)
        stat    0,0,0,1
        stat    0,1,0,0
        stat    0,1,0,0
        stat    0,0,0,2
        eff     0,S1_DARK|S1_PETRIFY,0,0,$40,0,0,0,0,0
; 11 Odin / Raiden: Vig / Spd; Fight never misses (Sniper Sight); Haste
;    (RunningShoes)
        stat    1,0,0,0
        stat    0,1,0,0
        eff     0,0,0,0,0,0,$10,0,0,0
        stat    2,0,0,0
        eff     0,0,0,OT6_SIG_HASTE,0,0,0,0,0,0
; 12 Bahamut: Mag / Vig; max HP +25% (Red Cap); Fight and spell damage up
;    (Hero Ring)
        stat    0,0,0,1
        stat    1,0,0,0
        eff     0,0,0,0,$04,0,0,0,0,0
        stat    0,0,0,2
        eff     0,0,0,0,$03,0,0,0,0,0
; 13 Alexandr: Stm / Vig; immune to Death; Safe (Guard Ring)
        stat    0,0,1,0
        stat    1,0,0,0
        eff     0,S1_DEATH,0,0,0,0,0,0,0,0
        stat    0,0,2,0
        eff     0,0,0,$40,0,0,0,0,0,0
; 14 Crusader: all four +1 at rungs 1, 2 and 4; max HP +25% (Red Cap);
;    two-handed grip and two weapons (Gauntlet, Genji Glove)
        stat    1,1,1,1
        stat    1,1,1,1
        eff     0,0,0,0,$04,0,0,0,0,0
        stat    1,1,1,1
        eff     0,0,0,0,0,0,0,$18,0,0
; 15 Ragnarok: Vig / Mag; max MP +25% (Minerva); Fight strikes four times
;    (Offering)
        stat    1,0,0,0
        stat    0,0,0,1
        eff     0,0,0,0,$20,0,0,0,0,0
        stat    2,0,0,0
        eff     0,0,0,0,0,0,0,$01,0,0
; 16 Kirin: Mag / Stm; immune to Poison; Regen (Cure Ring)
        stat    0,0,0,1
        stat    0,0,1,0
        eff     0,S1_POISON,0,0,0,0,0,0,0,0
        stat    0,0,0,2
        eff     0,0,0,$02,0,0,0,0,0,0
; 17 ZoneSeek: Mag / Stm; immune to Mute; Shell (Force Shld)
        stat    0,0,0,1
        stat    0,0,1,0
        eff     0,0,S2_MUTE,0,0,0,0,0,0,0
        stat    0,0,0,2
        eff     0,0,0,$20,0,0,0,0,0,0
; 18 Carbunkl: Stm / Mag; Shell at low HP (Barrier Ring); Facet (new code)
        stat    0,0,1,0
        stat    0,0,0,1
        eff     0,0,0,0,0,0,0,0,$01,0
        stat    0,0,2,0
        none
; 19 Phantom: Spd / Mag; no back attacks (Back Guard); Image (Mirage Vest)
        stat    0,1,0,0
        stat    0,0,0,1
        eff     0,0,0,0,0,$02,0,0,0,0
        stat    0,2,0,0
        eff     0,0,0,0,0,0,0,0,0,$04
; 20 Sraphim: Stm / Mag; immune to Doom's countdown; Regen (Cure Ring).  The
;    design's Grace (keep the boost bank through KO and revive) would do
;    nothing: no code clears a fallen character's bank (OT6_BP_CLASS), so the
;    bank already survives a KO.  The healer's Regen stands in, the overlap
;    with Kirin's on purpose (#328).
        stat    0,0,1,0
        stat    0,0,0,1
        eff     0,0,S2_DOOM,0,0,0,0,0,0,0
        stat    0,0,2,0
        eff     0,0,0,$02,0,0,0,0,0,0
; 21 Golem: Stm / Vig; immune to Muddle; covers allies (True Knight)
        stat    0,0,1,0
        stat    1,0,0,0
        eff     0,0,S2_MUDDLE,0,0,0,0,0,0,0
        stat    0,0,2,0
        eff     0,0,0,0,0,0,0,$40,0,0
; 22 Unicorn: Stm / Mag; immune to Zombie; immune to Dark, Zombie and Poison
;    (Amulet)
        stat    0,0,1,0
        stat    0,0,0,1
        eff     0,S1_ZOMBIE,0,0,0,0,0,0,0,0
        stat    0,0,2,0
        eff     0,S1_DARK|S1_ZOMBIE|S1_POISON,0,0,0,0,0,0,0,0
; 23 Fenrir: Spd / Mag; more pre-emptive strikes (Gale Hairpin); immune to
;    Stop and Slow (new code)
        stat    0,1,0,0
        stat    0,0,0,1
        eff     0,0,0,0,0,$01,0,0,0,0
        stat    0,2,0,0
        none
; 24 Starlet: Mag / Spd; immune to Berserk; max MP +25% (Minerva)
        stat    0,0,0,1
        stat    0,1,0,0
        eff     0,0,S2_BSERK,0,0,0,0,0,0,0
        stat    0,0,0,2
        eff     0,0,0,0,$20,0,0,0,0,0
; 25 Phoenix: Stm / Spd; immune to Doom's countdown and Zombie; Rebirth
;    (new code)
        stat    0,0,1,0
        stat    0,1,0,0
        eff     0,S1_ZOMBIE,S2_DOOM,0,0,0,0,0,0,0
        stat    0,0,2,0
        none
        calc_size Ot6LadderTbl
.assert sizeof_Ot6LadderTbl = OT6_REC * 5 * OT6_ESPER_SLOTS, error, "Ot6LadderTbl must be 26 espers x 5 rungs"

; the menu labels for the rungs (tools/esper_ladder.py --labels)
        .include "ot6_esper_labels.inc"
