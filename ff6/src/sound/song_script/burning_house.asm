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

SongStart:
AltChannel1:
Channel1:
        .byte   $f0,$78,$f7,$00,$64,$f8,$00,$00,$f2,$28,$c6,$40,$c4,$14,$cd,$c8
        .byte   $64,$dc,$00,$d0,$dd,$08,$cf,$10,$00

_003f:
        .byte   $a8,$ce,$dd,$0c,$00,$cd,$96,$32,$a8,$f6
        .addr   _003f

AltChannel2:
Channel2:
        .byte   $c6,$40,$c4,$28,$cd,$00,$24,$cb,$00,$ff,$bf,$d2,$dd,$06,$dc,$04
        .byte   $d6,$00,$9a

_005e:
        .byte   $a8,$d4,$ab,$d5,$f6
        .addr   _005e

Channel3:
AltChannel3:
        .byte   $b7,$db,$04

AltChannel4:
Channel4:
        .byte   $c6,$40,$c4,$1e,$dc,$07,$e0,$1f,$d4,$d6,$26,$cd,$00,$98

_0076:
        .byte   $e2,$02,$0d,$b8,$09,$b8,$e2,$01,$0d,$b9,$0d,$c1,$0d,$b8,$0d,$b7
        .byte   $e3,$0d,$bb,$0d,$b8,$e3,$f6
        .addr   _0076

AltChannel7:
SongEnd:
AltChannel6:
AltChannel5:
Channel8:
AltChannel8:
Channel7:
Channel6:
Channel5:

.endscope

.list on
