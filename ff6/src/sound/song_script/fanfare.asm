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
        .byte   $f7,$00,$46,$f8,$00,$00,$f2,$46,$c4,$3c,$dc,$20,$c6,$32,$d4,$c9
        .byte   $30,$12,$ef,$f0,$6e,$d6,$06,$9e,$a4,$c0,$a4,$c0,$a4,$c0,$d7,$f0
        .byte   $69,$04,$f0,$64,$20,$39,$ac,$ba,$eb

Channel2:
AltChannel2:
        .byte   $c4,$3c,$dc,$20,$c6,$3c,$d4,$c9,$30,$12,$ef,$d6,$06,$3c,$7a,$c0
        .byte   $5e,$c0,$42,$c0,$3c,$58,$71,$ac,$ba,$eb

Channel3:
AltChannel3:
        .byte   $c4,$3c,$dc,$20,$c6,$46,$d4,$c9,$30,$12,$ef,$d6,$05,$74,$a4,$c0
        .byte   $88,$c0,$7a,$c0,$66,$82,$9b,$ac,$ba,$eb

AltChannel4:
Channel4:
        .byte   $c4,$3c,$dc,$21,$c6,$50,$d4,$c9,$30,$12,$ef,$d6,$05,$3c,$42,$c0
        .byte   $42,$c0,$42,$c0,$04,$d8,$82,$71,$ac,$ba,$eb

AltChannel7:
Channel8:
AltChannel5:
SongEnd:
Channel6:
Channel5:
AltChannel6:
AltChannel8:
Channel7:

.endscope

.list on
