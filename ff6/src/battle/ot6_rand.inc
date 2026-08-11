; ------------------------------------------------------------------------------
; OT6 shared leaf: the battle RNG, inlined.
;
; Lived in ot6_kits.asm until the kits split; moved here because it is used
; from two different kits (Ot6StealSlot in ot6_steal.asm, Ot6RageCoin in
; ot6_rage.asm) and a macro definition emits nothing, so the move changes no
; address. ROM CRC32 was unchanged at 0x2E9B5A7F.
; ------------------------------------------------------------------------------

; battle Rand, inlined: this bank ($f0) can't `jsr Rand` (that routine lives in
; $c2 and a near jsr would land in $f0 garbage) and Rand ends `rts`, not `rtl`,
; so it can't be jsl'd either. Its three lines are reproduced here (`inc $be;
; ldx $be; lda f:RNGTbl,x`), the same rolling index into the same table Rand
; walks. a8/i8; A = the draw (0-255); x saved/restored, y untouched.
.macro ot6_rand
        phx
        inc     $be
        ldx     $be
        lda     f:RNGTbl,x
        plx
.endmacro
