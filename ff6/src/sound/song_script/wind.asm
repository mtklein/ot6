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
Channel1:
AltChannel1:
        .byte   $f0,$78,$f2,$3c,$f7,$00,$3c,$f8,$00,$00,$c4,$40,$c6,$40,$d6,$03
        .byte   $dc,$04,$dd,$08,$cd,$28,$eb,$cb,$00,$ff,$bf,$c8,$28,$02,$22

_0045:
        .byte   $e2,$01,$a8,$c8,$28,$05,$ab,$c8,$18,$fb,$e3,$b0,$c8,$30,$15,$ab
        .byte   $c8,$30,$eb,$af,$f6
        .addr   _0045

Channel2:
AltChannel2:
        .byte   $c4,$40,$c6,$40,$d2,$d6,$06,$dc,$03,$cd,$44,$38,$cb,$00,$a0,$bf
        .byte   $dd,$04,$8b

_006f:
        .byte   $a9,$e2,$01,$c8,$2c,$07,$ae,$c8,$84,$f8,$a8,$c8,$2c,$08,$ae,$c8
        .byte   $2c,$f6,$ae,$e3,$c8,$18,$06,$f6
        .addr   _006f

AltChannel3:
Channel3:
        .byte   $c4,$28,$c6,$40,$d4,$db,$01,$bb,$d6,$03,$dc,$04,$dd,$08,$cd,$28
        .byte   $eb,$cb,$00,$ff,$bf,$c8,$28,$02,$22

_00a2:
        .byte   $e2,$01,$a8,$c8,$28,$05,$ab,$c8,$18,$fb,$e3,$b0,$c8,$30,$15,$ab
        .byte   $c8,$30,$eb,$af,$f6
        .addr   _00a2

Channel4:
AltChannel4:
        .byte   $c4,$28,$c6,$40,$d4,$db,$02,$bb,$d2,$d6,$06,$dc,$03,$cd,$44,$38
        .byte   $cb,$00,$a0,$bf,$dd,$04,$8b

_00d0:
        .byte   $a9,$e2,$01,$c8,$2c,$07,$ae,$c8,$84,$f8,$a8,$c8,$2c,$08,$ae,$c8
        .byte   $2c,$f6,$ae,$e3,$c8,$18,$06,$f6
        .addr   _00d0

AltChannel6:
AltChannel8:
Channel7:
Channel6:
SongEnd:
Channel5:
Channel8:
AltChannel5:
AltChannel7:

.endscope

.list on
