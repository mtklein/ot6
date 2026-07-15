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
        .byte   $f0,$78,$f7,$64,$50,$f8,$00,$00,$f2,$46,$c6,$40,$c4,$08,$dc,$07
        .byte   $d6,$0a,$dd,$04,$00

_003b:
        .byte   $a8,$f6
        .addr   _003b

AltChannel2:
Channel2:
        .byte   $c6,$40,$c4,$06,$c3,$d4,$dc,$07,$cb,$00,$b4,$c9,$d6,$12,$cd,$ff
        .byte   $10,$d2,$dd,$04,$00

_0054:
        .byte   $a8,$f6
        .addr   _0054

AltChannel3:
Channel3:
        .byte   $c6,$64,$d4,$d2,$cd,$7f,$46,$dc,$05,$d6,$05,$df,$00,$e0,$1a

_0067:
        .byte   $c4,$12,$e2,$01,$c8,$07,$20,$02,$c8,$06,$1f,$66,$c4,$1c,$c8,$09
        .byte   $22,$2d,$e3,$c8,$08,$1e,$59,$f6
        .addr   _0067

AltChannel4:
Channel4:
        .byte   $c6,$1b,$c4,$0a,$bb,$d4,$d2,$cd,$64,$46,$dc,$05,$d6,$05,$df,$00
        .byte   $e0,$1a

_0093:
        .byte   $e2,$01,$c8,$07,$20,$02,$c8,$06,$1f,$67,$c8,$09,$22,$2d,$e3,$c8
        .byte   $08,$1e,$59,$f6
        .addr   _0093

Channel8:
Channel7:
AltChannel7:
Channel5:
Channel6:
AltChannel6:
AltChannel8:
AltChannel5:
SongEnd:

.endscope

.list on
