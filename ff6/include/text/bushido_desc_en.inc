.list off
.ifndef BUSHIDO_DESC_INC
BUSHIDO_DESC_INC = 1

.global BushidoDesc, BushidoDescPtrs

.scope BushidoDesc

        Start := BushidoDesc

; ##############################################################################
; ###          AUTOMATICALLY GENERATED CODE, DO NOT MODIFY MANUALLY          ###
; ##############################################################################

        ARRAY_LENGTH = 8

        _0 := BushidoDesc + $0000
        _1 := BushidoDesc + $000e
        _2 := BushidoDesc + $0024
        _3 := BushidoDesc + $0039
        _4 := BushidoDesc + $0049
        _5 := BushidoDesc + $0062
        _6 := BushidoDesc + $007f
        _7 := BushidoDesc + $008f

; ##############################################################################

.endscope

.endif
.list on