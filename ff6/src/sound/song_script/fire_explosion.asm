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
        .byte   $f0,$78,$f2,$3c,$f8,$00,$00,$f7,$3c,$c4,$32,$c6,$40,$cf,$12,$d0
        .byte   $cd,$00,$78,$dd,$05,$00

_003c:
        .byte   $a8,$f6
        .addr   _003c

AltChannel2:
Channel2:
        .byte   $c4,$7f,$c6,$40,$d6,$01,$dc,$07,$dd,$07,$38

_004b:
        .byte   $a8,$f6
        .addr   _004b

AltChannel3:
AltChannel4:
AltChannel5:
AltChannel6:
AltChannel7:
AltChannel8:
Channel3:
Channel4:
Channel5:
Channel6:
Channel7:
Channel8:
SongEnd:

.endscope

.list on
