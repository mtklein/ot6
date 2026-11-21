; ------------------------------------------------------------------------------
; OT6: Gogo's full kits (#547)
;
; The owner's ruling (2026-11-15): each command Gogo picks opens its owner's
; whole kit, as far as reasonable.  docs/design/kit-gogo.md is the survey:
; what each command gave him before, what it gives him now, and the engine
; limits that keep a piece out.  Most kit machinery is keyed on the command
; and already answers for him (Steal's thief list, the Painter list, Bum
; Rush, Cleave and the SwdTech loadout, Gau's rage loadout, Strago's lore
; loadout, the smoke and the exit, the pin).  The pieces keyed on the owner's
; actor id take Gogo too, in their own leaves:
;   Slot      Setzer's table          Ot6SetzerListOpen (ot6_setzer.asm)
;   Tools     Overclock               Ot6Overclocks (ot6_overclock.asm)
;   Runic     RunicBlade              Ot6BladeRaise (ot6_runicblade.asm)
;   Throw     Assassinate, on a Throw Ot6AssassinateGate (ot6_divine.asm)
;   Magic     Ultima, Fire's 4th fold Ot6FoldSteps (ot6_boost.asm)
;   Lore      Study, Scan and Bserk   Ot6StudyGate below (Ot6StudyOne,
;                                     Ot6MagicPrice), Ot6UnionEspers
;                                     (ot6_progression.asm)
; Gogo stays actor $0C after the Leo reveal (#552), so every test here is on
; the actor id and holds in both states.
; ------------------------------------------------------------------------------

.segment "ot6_code"

OT6_CHAR_GOGO = CHAR::GOGO              ; $0C, revealed or not

; [ does Gogo carry this command? ]
; Gogo (actor $0C, Leo's slot after the reveal too) whose record holds the
; command among its four ($1616-$1619 of the record $3010 points at; Mimic
; is row 0, the three he picked follow).  The record, not the battle's
; command list, so a command the Fanatics' Tower removes still counts:
; what it opens is on another row (Lore's Scan and Bserk ride Magic).
; in: A = command id, X = entity offset (a character), db = $7e, a8, either
; index width.  out: carry set = yes.  preserves A, X and Y.
.proc Ot6GogoCarries
        .a8
        php
        rep     #$10            ; (an 8-bit X or Y comes up with a zero
        .i16                    ;   high byte: the offsets are unchanged)
        phx
        phy
        pha
        txa
        cmp     #$08
        bcs     @no             ; a monster
        lda     $3ed8,x         ; actor
        cmp     #OT6_CHAR_GOGO
        bne     @no
        ldy     $3010,x         ; his record's offset from $1600
        lda     $01,s
        cmp     $1616,y
        beq     @yes
        cmp     $1617,y
        beq     @yes
        cmp     $1618,y
        beq     @yes
        cmp     $1619,y
        beq     @yes
@no:    pla
        ply
        plx
        plp
        clc
        rtl
@yes:   pla
        ply
        plx
        plp
        sec
        rtl
.endproc

; [ whose Scan studies: Strago, or a Gogo who carries Lore ]
; Study is Strago's Scan at the full boost (ot6_analyze.asm); Lore's owner
; is Strago, so a Gogo carrying Lore studies with his Scan too (#547).  The
; boost test is the caller's.  in: X = entity offset, db = $7e, a8, either
; index width.  out: carry set = this caster studies at the full boost.
; preserves A, X and Y.
.proc Ot6StudyCaster
        .a8
        pha
        lda     $3ed8,x
        cmp     #OT6_CHAR_STRAGO
        beq     @yes
        lda     #$0c            ; Lore
        jsl     Ot6GogoCarries
        pla
        rtl                     ; carry: Gogo carries Lore
@yes:   pla
        sec
        rtl
.endproc
