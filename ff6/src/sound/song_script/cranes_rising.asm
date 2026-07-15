.list off

; this file is generated automatically, do not modify manually

.scope
        .word   SongEnd - Header

Header:
        .addr   SongStart
        .addr   SongEnd
        .addr   Channel1
        .addr   Channel2
        .addr   Channel3
        .addr   Channel4
        .addr   Channel5
        .addr   Channel6
        .addr   Channel7
        .addr   Channel8
        .addr   AltChannel1
        .addr   AltChannel2
        .addr   AltChannel3
        .addr   AltChannel4
        .addr   AltChannel5
        .addr   AltChannel6
        .addr   AltChannel7
        .addr   AltChannel8

Channel1:
AltChannel1:
SongStart:
        .byte   $f0,$78,$f7,$00,$64,$f8,$00,$00,$f2,$32,$c4,$08,$c6,$40,$d0,$dc
        .byte   $00,$cf,$10

_0039:
        .byte   $0c,$f6
        .addr   _0039

AltChannel2:
Channel2:
        .byte   $c6,$40,$c4,$0f,$d4,$dc,$04,$d6,$08,$cd,$00,$78,$cb,$00,$01,$bf
        .byte   $e4

_004e:
        .byte   $c8,$c0,$01,$00,$c5,$ff,$28,$da,$01,$f6
        .addr   _004e

AltChannel3:
Channel3:
        .byte   $c6,$40,$d6,$03,$c8,$01,$f1,$dc,$04,$df,$02

_0065:
        .byte   $c4,$7f,$0b,$c5,$5c,$00,$aa,$f6
        .addr   _0065

AltChannel4:
Channel4:
        .byte   $c6,$40,$c4,$32,$d2,$d4,$d6,$07,$cd,$ff,$8c,$dc,$07

_007c:
        .byte   $5e,$c8,$24,$06,$e0,$10,$0e,$e2,$3c,$0d,$e3,$f6
        .addr   _007c

Channel5:
AltChannel5:
        .byte   $c6,$14,$db,$02,$f6
        .addr   _0093

Channel6:
AltChannel6:
        .byte   $c6,$6b

_0093:
        .byte   $dc,$20,$d6,$04,$c4,$46

_0099:
        .byte   $01,$f6
        .addr   _0099

Channel7:
SongEnd:
Channel8:
AltChannel7:
AltChannel8:

.endscope

.list on
