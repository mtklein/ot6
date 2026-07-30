; ------------------------------------------------------------------------------
; OT6 shared leaf: the battle RNG, inlined.
;
; Lived in ot6_kits.asm until the kits split; hoisted here because it is used
; from two different kits (Ot6StealSlot in ot6_steal.asm, Ot6RageCoin in
; ot6_rage.asm) and a macro definition emits nothing, so the hoist is
; address-neutral by construction (proven: ROM CRC32 unchanged, 0x2E9B5A7F).
; ------------------------------------------------------------------------------

; battle Rand, inlined: this bank ($f0) can't `jsr Rand` (that routine lives in
; $c2 and a near jsr would land in $f0 garbage) and Rand ends `rts`, not `rtl`,
; so it can't be jsl'd either. Reproduce its three lines here -- `inc $be; ldx
; $be; lda f:RNGTbl,x` -- the same rolling index into the same table Rand walks.
; a8/i8; A = the draw (0-255); x saved/restored, y untouched.
.macro ot6_rand
        phx
        inc     $be
        ldx     $be
        lda     f:RNGTbl,x
        plx
.endmacro
