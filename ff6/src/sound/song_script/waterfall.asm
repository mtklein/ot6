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
        .byte   $f0,$78,$f7,$00,$64,$f8,$00,$00,$f2,$14,$c6,$40,$c4,$14,$cd,$3c
        .byte   $d7,$d4,$d0,$dc,$00,$cf,$14,$cb,$00,$ff,$ff,$00

_0042:
        .byte   $e2,$01,$a8,$a8,$a8,$cf,$15,$e3,$a8,$cf,$14,$f6
        .addr   _0042

AltChannel2:
Channel2:
        .byte   $c6,$40,$c4,$14,$cd,$f4,$34,$cb,$00,$c8,$ff,$d2,$dc,$04,$d6,$02
        .byte   $3c

_0061:
        .byte   $e2,$02,$c8,$6c,$04,$a8,$c8,$4c,$fb,$a9,$e3,$c8,$30,$0b,$ab,$c8
        .byte   $c0,$f5,$a8,$f6
        .addr   _0061

AltChannel3:
Channel3:
        .byte   $db,$01

Channel4:
AltChannel4:
        .byte   $c6,$40,$c4,$19,$d2,$dc,$04,$d6,$08,$cb,$00,$14,$cb,$00

_0087:
        .byte   $a8,$f6
        .addr   _0087

Channel7:
Channel5:
AltChannel7:
AltChannel8:
Channel8:
AltChannel6:
Channel6:
SongEnd:
AltChannel5:

.endscope

.list on
