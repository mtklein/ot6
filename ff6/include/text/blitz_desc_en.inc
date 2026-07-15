.list off
.ifndef BLITZ_DESC_INC
BLITZ_DESC_INC = 1

.global BlitzDesc, BlitzDescPtrs

.scope BlitzDesc

        Start := BlitzDesc

; ##############################################################################
; ###          AUTOMATICALLY GENERATED CODE, DO NOT MODIFY MANUALLY          ###
; ##############################################################################

        ARRAY_LENGTH = 8

        _0 := BlitzDesc + $0000
        _1 := BlitzDesc + $0021
        _2 := BlitzDesc + $0040
        _3 := BlitzDesc + $005a
        _4 := BlitzDesc + $0074
        _5 := BlitzDesc + $0092
        _6 := BlitzDesc + $00ac
        _7 := BlitzDesc + $00ca

; ##############################################################################

.endscope

.endif
.list on
