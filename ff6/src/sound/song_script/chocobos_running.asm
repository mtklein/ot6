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

AltChannel1:
SongStart:
Channel1:
        .byte   $f0,$78,$f7,$00,$50,$f8,$00,$00,$f2,$23,$c6,$40,$c4,$32,$d0,$dc
        .byte   $00,$cf,$1e,$dd,$0d,$e0,$1e

_003d:
        .byte   $09,$bf,$09,$bf,$f6
        .addr   _003d

AltChannel2:
Channel2:
        .byte   $c6,$40,$c4,$46,$d2,$dc,$02,$d6,$01

_004d:
        .byte   $cb,$00,$01,$bf,$c8,$04,$18,$dd,$0e,$e0,$1a,$09,$bf,$4d,$f6
        .addr   _004d

AltChannel3:
Channel3:
        .byte   $c3,$c6,$40,$c4,$28,$dc,$07,$cb,$00,$02,$af,$d6,$0b,$e0,$1c

_006d:
        .byte   $c8,$02,$14,$09,$bf,$41,$bf,$f6
        .addr   _006d

Channel4:
AltChannel4:
        .byte   $c6,$40,$c4,$46,$be,$d2,$dc,$02,$d6,$01

_0081:
        .byte   $cb,$00,$01,$bf,$c8,$04,$18,$dd,$0e,$e0,$1a,$09,$bf,$4d,$f6
        .addr   _0081

Channel5:
AltChannel5:
        .byte   $be,$c6,$40,$c4,$2d,$dc,$07,$cb,$00,$02,$af,$d6,$0b,$e0,$1c

_00a1:
        .byte   $c8,$02,$14,$09,$bf,$41,$bf,$f6
        .addr   _00a1

Channel7:
AltChannel7:
Channel8:
AltChannel6:
AltChannel8:
Channel6:
SongEnd:

.endscope

.list on
