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
        .byte   $f4,$a0,$f7,$00,$32,$f8,$00,$00,$f2,$32,$c4,$3c,$dc,$20,$c6,$40
        .byte   $d4,$f0,$4b,$e8,$06,$b6,$d6,$07,$23,$d8,$93,$f1,$90,$28,$85,$69
        .byte   $55,$eb

AltChannel2:
Channel2:
        .byte   $c4,$3c,$dc,$20,$c6,$40,$d4,$e8,$06,$b6,$d6,$06,$5b,$69,$15,$3f
        .byte   $1d,$eb

Channel3:
AltChannel3:
        .byte   $c4,$3c,$dc,$20,$c6,$40,$d4,$e8,$06,$b6,$b7,$ba,$d6,$07,$20,$eb

AltChannel4:
Channel4:
        .byte   $e8,$06,$b6,$c4,$3c,$dc,$20,$c6,$40,$d4,$b7,$ba,$d6,$05,$20,$eb

AltChannel5:
Channel5:
        .byte   $e8,$06,$b6,$c4,$3c,$dc,$03,$e0,$0d,$c6,$40,$d4,$d6,$07,$23,$d8
        .byte   $93,$85,$69,$55,$eb

Channel6:
AltChannel6:
        .byte   $e8,$04,$b6,$c4,$3c,$dc,$03,$e0,$0d,$c6,$40,$d4,$d6,$06,$85,$bd
        .byte   $3c,$1d,$eb

AltChannel7:
Channel7:
        .byte   $e8,$02,$b6,$c4,$3c,$dc,$03,$e0,$0d,$c6,$40,$d4,$d6,$06,$58,$12
        .byte   $d8,$7f,$eb

AltChannel8:
Channel8:
        .byte   $c4,$3c,$dc,$03,$e0,$0d,$c6,$40,$d4,$d6,$06,$20,$d8,$82,$55,$eb

SongEnd:

.endscope

.list on
