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
        .byte   $f7,$00,$64,$f8,$00,$00,$f2,$32,$dc,$20,$c6,$40,$d4,$f0,$28,$f4
        .byte   $a0,$c4,$3c,$c5,$c0,$46,$b6,$c5,$c0,$50,$b6,$c5,$c0,$5a,$b7,$d6
        .byte   $06,$47,$c4,$64,$c6,$28,$f0,$5a,$d7,$3c,$f0,$32,$2b,$ac,$f0,$82
        .byte   $b6,$f0,$46,$3c,$f0,$1e,$2b,$ac,$eb

AltChannel2:
Channel2:
        .byte   $dc,$20,$c6,$40,$d4,$c4,$3c,$c5,$c0,$46,$b6,$c5,$c0,$50,$b6,$c5
        .byte   $c0,$5a,$d6,$06,$00,$c4,$64,$c6,$32,$d7,$04,$d8,$9b,$ac,$b6,$d7
        .byte   $04,$d8,$9b,$ac,$eb

AltChannel3:
Channel3:
        .byte   $dc,$20,$c6,$40,$d4,$c4,$3c,$c5,$c0,$46,$b6,$c5,$c0,$50,$b7,$d6
        .byte   $05,$63,$c5,$c0,$5a,$a8,$c4,$64,$c6,$3c,$d7,$74,$71,$ac,$b6,$74
        .byte   $71,$ac,$eb

Channel4:
AltChannel4:
        .byte   $dc,$20,$c6,$40,$d4,$c4,$3c,$c5,$c0,$46,$b6,$c5,$c0,$50,$d6,$05
        .byte   $1c,$c5,$c0,$5a,$a8,$c4,$64,$c6,$46,$d7,$4a,$47,$ac,$b6,$4a,$47
        .byte   $ac,$eb

AltChannel5:
Channel5:
        .byte   $dc,$20,$c6,$40,$d4,$c4,$3c,$c5,$c0,$46,$b7,$d6,$04,$7f,$c5,$c0
        .byte   $50,$a8,$c5,$c0,$5a,$a8,$c4,$64,$c6,$50,$4a,$47,$ac,$b6,$4a,$47
        .byte   $ac,$eb

Channel6:
AltChannel6:
        .byte   $dc,$20,$c6,$40,$d4,$c4,$3c,$c5,$c0,$46,$d6,$04,$38,$c5,$c0,$50
        .byte   $a8,$c5,$c0,$5a,$a8,$c4,$64,$c6,$5a,$d8,$4a,$47,$ac,$b6,$4a,$47
        .byte   $ac,$eb

Channel7:
AltChannel7:
        .byte   $c4,$50,$dc,$21,$c6,$28,$d4,$dd,$0a,$b6,$b6,$b6,$d6,$05,$e4,$3c
        .byte   $2b,$ac,$b6,$e4,$3c,$2b,$ac,$eb

AltChannel8:
Channel8:
        .byte   $c4,$5a,$dc,$22,$c6,$50,$d4,$dd,$0a,$b6,$b6,$b6,$d6,$07,$e4,$04
        .byte   $d8,$9b,$ac,$b6,$d7,$e4,$04,$d8,$9b,$ac,$eb

SongEnd:

.endscope

.list on
