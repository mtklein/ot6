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
Channel1:
SongStart:
        .byte   $f0,$78,$f7,$00,$64,$f8,$00,$00,$f2,$14,$c4,$0f,$c6,$40,$d4,$d0
        .byte   $dc,$00,$dd,$04,$e0,$10

_003c:
        .byte   $b9,$e2,$01,$cf,$1a,$63,$a8,$cf,$18,$00,$e3,$b8,$f6
        .addr   _003c

Channel2:
AltChannel2:
_004b:
        .byte   $b7,$c6,$40,$c4,$08,$dc,$04,$d6,$04,$dd,$00,$e0,$0d,$c8,$14,$08
        .byte   $00,$c4,$0f,$dd,$0b,$e0,$0f,$08,$01,$c8,$14,$08,$c4,$06,$dd,$03
        .byte   $e0,$13,$00,$b8,$f6
        .addr   _004b

_0072:
Channel3:
AltChannel3:
        .byte   $b7,$c6,$40,$c4,$00,$c5,$72,$18,$d2,$cb,$00,$d0,$bf,$dc,$07,$d6
        .byte   $07,$dd,$02,$cd,$4c,$20,$2a,$e0,$0c,$b0,$a9,$a8,$aa,$f6
        .addr   _0072

SongEnd:
Channel4:
AltChannel4:
Channel6:
AltChannel7:
Channel8:
Channel7:
AltChannel5:
Channel5:
AltChannel8:
AltChannel6:

.endscope

.list on
