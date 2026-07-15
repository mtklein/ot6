.list off
.ifndef MTE_TBL_INC
MTE_TBL_INC = 1

.global MTETbl, MTETblPtrs

.scope MTETbl

        Start := bank_start MTETbl

; ##############################################################################
; ###          AUTOMATICALLY GENERATED CODE, DO NOT MODIFY MANUALLY          ###
; ##############################################################################

        ARRAY_LENGTH = 24

        _0 := MTETbl + $0000
        _1 := MTETbl + $0003
        _2 := MTETbl + $0008
        _3 := MTETbl + $000b
        _4 := MTETbl + $000e
        _5 := MTETbl + $0013
        _6 := MTETbl + $0016
        _7 := MTETbl + $0019
        _8 := MTETbl + $001e
        _9 := MTETbl + $0021
        _10 := MTETbl + $002b
        _11 := MTETbl + $0033
        _12 := MTETbl + $0036
        _13 := MTETbl + $0039
        _14 := MTETbl + $003e
        _15 := MTETbl + $0046
        _16 := MTETbl + $0049
        _17 := MTETbl + $004e
        _18 := MTETbl + $0053
        _19 := MTETbl + $0059
        _20 := MTETbl + $005d
        _21 := MTETbl + $0060
        _22 := MTETbl + $0064
        _23 := MTETbl + $0067

; ##############################################################################

.endscope

.endif
.list on
