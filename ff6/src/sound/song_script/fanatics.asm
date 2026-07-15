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
SongStart:
AltChannel1:
        .byte   $f0,$4b,$f4,$cc,$f7,$00,$64,$f8,$00,$00,$f2,$64,$dc,$20,$c6,$5a
        .byte   $d4,$dd,$08

_0039:
        .byte   $d6,$06,$c4,$3c,$e2,$0f,$ba,$e3,$c4,$6e,$e2,$01,$70,$54,$70,$7e
        .byte   $e3,$f6
        .addr   _0039

Channel2:
AltChannel2:
        .byte   $c4,$50,$dc,$21,$c6,$23,$d4,$dd,$08

_0056:
        .byte   $d6,$05,$b6,$b6,$b6,$b6,$e2,$01,$2a,$0e,$2a,$0e,$e3,$f6
        .addr   _0056

AltChannel3:
Channel3:
        .byte   $c4,$32,$dc,$26,$c6,$40,$d4,$e8,$02,$b6

_0070:
        .byte   $d6,$04,$b6,$b6,$c4,$28,$c5,$c0,$2d,$85,$93,$85,$93,$85,$93,$85
        .byte   $93,$c5,$c0,$32,$85,$93,$85,$93,$85,$93,$85,$93,$c4,$37,$e2,$01
        .byte   $70,$54,$70,$7e,$e3,$f6
        .addr   _0070

AltChannel4:
Channel4:
        .byte   $c4,$32,$dc,$26,$c6,$40,$d4,$e8,$02,$b6

_00a2:
        .byte   $d6,$04,$b6,$c4,$23,$c5,$c0,$28,$5b,$69,$5b,$69,$5b,$69,$5b,$69
        .byte   $c5,$c0,$2d,$5b,$69,$5b,$69,$5b,$69,$5b,$69,$d7,$c5,$c0,$32,$07
        .byte   $15,$07,$15,$07,$15,$07,$15,$c4,$37,$d8,$e2,$01,$2a,$0e,$2a,$0e
        .byte   $e3,$f6
        .addr   _00a2

AltChannel5:
Channel5:
        .byte   $dc,$26,$c6,$40,$d4,$e8,$02,$b6

_00de:
        .byte   $d6,$03,$c4,$1e,$c5,$c0,$23,$31,$3f,$31,$3f,$31,$3f,$31,$3f,$c5
        .byte   $c0,$28,$31,$3f,$31,$3f,$31,$3f,$31,$3f,$c5,$c0,$2d,$31,$3f,$31
        .byte   $3f,$31,$3f,$31,$3f,$c5,$c0,$32,$31,$3f,$31,$3f,$31,$3f,$31,$3f
        .byte   $c4,$37,$e2,$01,$70,$54,$70,$54,$e3,$f6
        .addr   _00de

Channel6:
        .byte   $c4,$7d,$dc,$25,$d4,$e8,$02,$b6

_0122:
        .byte   $d6,$03,$a8,$b6,$b6,$b6,$e2,$01,$a9,$c6,$14,$46,$c6,$6e,$46,$c6
        .byte   $14,$46,$c6,$6e,$47,$e3,$f6
        .addr   _0122

Channel7:
        .byte   $dc,$23,$c6,$32,$d4

_0140:
        .byte   $e2,$0f,$d6,$05,$c4,$32,$3f,$c4,$19,$3f,$e3,$e2,$1f,$c4,$50,$41
        .byte   $c4,$28,$41,$41,$41,$e3,$f6
        .addr   _0140

AltChannel6:
Channel8:
        .byte   $dc,$24,$c6,$40,$e8,$02,$b6

_0160:
        .byte   $c4,$5a,$d6,$03,$e2,$03,$90,$90,$8d,$e3,$e2,$01,$e2,$01,$e2,$01
        .byte   $c4,$7d,$77,$c4,$5a,$77,$77,$77,$e3,$e2,$01,$c4,$7d,$5b,$c4,$5a
        .byte   $5b,$5b,$5b,$e3,$e3,$e3,$f6
        .addr   _0160

AltChannel8:
AltChannel7:
SongEnd:

.endscope

.list on
