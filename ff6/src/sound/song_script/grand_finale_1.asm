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
        .byte   $f0,$78,$f7,$00,$64,$f8,$00,$01,$f2,$64,$c6,$40,$c4,$46,$dc,$20
        .byte   $d6,$02,$dd,$00,$e0,$08,$00,$a8,$a8,$a8,$eb

Channel2:
AltChannel2:
        .byte   $c6,$40,$c4,$32,$dc,$20,$d6,$03,$dd,$00,$e0,$08,$00,$a8,$a8,$a8
        .byte   $eb

AltChannel3:
Channel3:
        .byte   $c6,$40,$c4,$28,$d4,$db,$02,$cd,$92,$78,$dc,$20,$d6,$02,$dd,$00
        .byte   $e0,$08,$00,$a8,$a8,$a8,$eb

AltChannel4:
Channel4:
        .byte   $c6,$40,$c4,$28,$d4,$db,$02,$cd,$92,$f0,$dc,$20,$d6,$03,$dd,$00
        .byte   $e0,$08,$00,$a8,$a8,$a8,$eb

AltChannel7:
Channel5:
AltChannel6:
SongEnd:
Channel7:
Channel6:
AltChannel8:
Channel8:
AltChannel5:

.endscope

.list on
