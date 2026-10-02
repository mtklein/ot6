
; +----------------------------------------------------------------------------+
; |                                                                            |
; |                              FINAL FANTASY VI                              |
; |                                                                            |
; +----------------------------------------------------------------------------+
; | file: header.asm                                                           |
; |                                                                            |
; | description: snes cartridge header                                         |
; |                                                                            |
; | created: 8/2/2022                                                          |
; +----------------------------------------------------------------------------+

.segment "interrupt"

JmpReset:
@ff00:  fixed_block $10
        sei
        clc
        xce
        jml     Reset
        end_fixed_block

; ------------------------------------------------------------------------------

; [ nmi ]

JmpNMI:
@ff10:  jml     $001500

; ------------------------------------------------------------------------------

; [ irq ]

JmpIRQ:
@ff14:  jml     $001504

; ------------------------------------------------------------------------------

; [ ot6: the build's version, shown on the Config screen and the boot splash ]

; A fixed-size field at a fixed address (c0/ffa0, the ot6_version segment in
; cfg/ff6-en.cfg), filled after the link by tools/build/rom_version.py from
; the repo's VERSION file: "OT6 v<VERSION>" in the menu font's encoding,
; $00-terminated and $00-padded.  The SNES header title below is the same
; kind of field (ASCII "OT6 V<VERSION>", space-padded).  The ROM identity
; that fixtures and test results bind to (rom_version.py identity) is the
; ROM with these two fields and the header checksum zeroed, so a VERSION
; bump changes the shipped bytes and nothing a fixture depends on.  The
; assembled bytes here are only placeholders: the stamp checks this
; address in ff6-en.dbg before it writes.

.export Ot6VersionText

.segment "ot6_version"

Ot6VersionText:
@ffa0:  fixed_block $10
        .byte   0                       ; placeholder (rom_version.py stamps it)
        end_fixed_block 0

; ------------------------------------------------------------------------------

.segment "snes_header_ext"

.if LANG_EN

SnesHeaderExt:
@ffb0:  fixed_block $10
        .byte   "C3"                    ; publisher: squaresoft
        .byte   "F6  "                  ; game code
        end_fixed_block 0
.endif

; ------------------------------------------------------------------------------

.segment "snes_header"

SnesHeader:
@ffc0:
.if LANG_EN
        .byte   "OT6                  " ; rom title (U): rom_version.py stamps
                                        ; "OT6 V<VERSION>" (see Ot6VersionText)
.else
        .byte   "FINAL FANTASY 6      " ; rom title (J)
.endif
        .byte   $31                     ; HiROM, FastROM
        .byte   $02                     ; rom + ram + sram
        .byte   $0c                     ; rom size: 48 Mbit
        .byte   $05                     ; sram size: 256 kbit (ot6: weakness codex in the second 8k bank)
.if LANG_EN
        .byte   $01                     ; destination: north america
        .byte   $33                     ; use extended header
.else
        .byte   $00                     ; destination: japan
        .byte   $c3                     ; publisher: squaresoft
.endif
        .byte   ROM_VERSION             ; revision number (0 or 1)
        .word   0                       ; checksum (calculate later)
HeaderChecksum:
        .word   $ffff                   ; inverse checksum

; ------------------------------------------------------------------------------

.segment "vectors"

@ffe0:  .res    10
@ffea:  .addr   JmpNMI
        .res    2
@ffee:  .addr   JmpIRQ
        .res    12
@fffc:  .addr   JmpReset
        .res    2

; ------------------------------------------------------------------------------
