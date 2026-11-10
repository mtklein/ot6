; ------------------------------------------------------------------------------
; OT6: a reflected spell with nowhere to land shows no bounce (#520)
;
; CalcReflectDmg (battle_main.asm) queues the bounce's animation first --
; battle script command $09, or $15 when $3405 is counting -- with its target
; record $a0..$a9 all $ff, then fills that record with each body the bounce
; finds.  When the bounce finds none (ChooseTarget hands back an empty mask
; for every reflector), the command still runs with an all-$ff record, and
; GfxCmd_09 (btlgfx_main.asm; $15 jumps into its tail) never returns: the
; battle-script interpreter sits in ExecBtlGfx command 4 and the battle never
; reaches BattleLoop again.  That is vanilla's: the retail ROM hangs the same
; way (build/attempts/wt/v041-battle-hang/vanilla/vr_rd: a monster's Imp at a
; reflecting member with every monster down; with a monster standing, or
; without the Reflect, the script returns).
;
; The bounce is aimed at the reflector's other side, so it finds nothing
; only when every body there is down -- in practice the last monster's
; counter cast after a poison tick killed it (#519: L.30 Magic's Imp at Celes
; in a Wall Ring, Fanatics' Tower), since counters run ahead of
; CheckBattleEnd.  The spell is reflected and lands nowhere, so the bounce is
; not shown: the queued command becomes $07 (step the script data pointer),
; which consumes the same data block, so every command behind it reads the
; block it was written for.
; ------------------------------------------------------------------------------

.segment "ot6_code"

; jsl from CalcReflectDmg's tail (battle_main.asm), replacing `lda #$0010 /
; bit $ba`, which it repeats last, so A = $0010 and Z are as they were.
; a16/i8, db = $7e.  x and y are preserved.
.proc Ot6ReflectNowhere
        .a16
        .i8
        php
        sep     #$20
        .a8
        phx
        ldx     #$09
@scan:  lda     $a0,x           ; the bounce's target record
        cmp     #$ff
        bne     @out            ; it landed somewhere: as it was
        dex
        bpl     @scan
        lda     $3a72           ; the queue's end: the bounce is the last
        sec                     ;   command queued (a bounce that lands on
        sbc     #$04            ;   nothing queues nothing after it)
        tax
        lda     $2d6e,x
        cmp     #$09
        beq     @drop
        cmp     #$15
        bne     @out
@drop:  lda     #$07            ; step the data pointer, show nothing
        sta     $2d6e,x
@out:   plx
        plp
        .a16
        lda     #$0010
        bit     $ba
        rtl
.endproc
