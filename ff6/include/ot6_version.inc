; ------------------------------------------------------------------------------
; ot6: the version field's shape, shared by field/header.asm (the field),
; menu/ot6_version.asm (the Config screen) and cutscene/ot6_version.asm (the
; boot splash).  tools/build/rom_version.py reads OT6_VERSION_CELLS from here.
;
; Ot6VersionText (c0/ffa0) is OT6_VERSION_CELLS menu-font cells: "OT6 v" and
; VERSION, centered and padded with spaces ($ff), then a $00.  Both displays
; draw all OT6_VERSION_CELLS cells on every build: the same work, and the
; same cycles, whatever VERSION is.
; ------------------------------------------------------------------------------

.ifndef OT6_VERSION_INC
OT6_VERSION_INC = 1

OT6_VERSION_CELLS = 15

.endif
