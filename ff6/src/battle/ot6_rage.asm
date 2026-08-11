; ------------------------------------------------------------------------------
; GAU -- THE HUNTER'S STABLE: the rage loadout, its page, and Rage's coin
;
; The eight-slot loadout (battle list build + field configurator state, the
; same split shape ot6_loadout.asm has for Cyan) and Ot6RageCoin, boost's tilt
; on the possession roll.
; ------------------------------------------------------------------------------
; Carved out of ot6_kits.asm (v0.9, 3037 lines) with the emission order of
; every instruction preserved: ot6.asm includes these files in exactly the
; order their text sat in the old one, so the assembler sees the identical
; token stream and the linker the identical segment. Proven, not argued --
; ROM CRC32 0x2E9B5A7F and ff6-en.map are byte-identical across the split.
; ------------------------------------------------------------------------------

; ==============================================================================
; GAU -- THE HUNTER'S STABLE (issue #40, docs/design/kit-gau.md)
;
; The Ochette model: Veldt learning stays unlimited (LearnRage and the $1d2c
; bitfield are UNTOUCHED -- the collection game IS Gau), and the battle Rage
; window is filtered to an 8-slot loadout configured in the field.
;
; Storage: OT6_RAGELOAD, eight bytes at $7e1e1f, in the same save-block scrap
; the Bushido word lives in.  byte = rage id + 1; $00 = unset; all eight zero
; = AUTO.  No persistent_layout bump -- see ot6_memory.inc for the ruling.
;
; The battle read is ONE choke point: the flat list InitSkills builds at $257e.
; Everything downstream -- the window draw (btlgfx DrawRageListText), the
; confirm (btlgfx @852a, which refuses an $ff cell), the scroll cap, even
; RandRage's confused-rager fallback -- reads that list and narrows itself for
; free.  No cursor table, window template or btlgfx edit at all.
; ------------------------------------------------------------------------------

; [ is a rage learned?  test bit (id & 7) of $1d2c + (id >> 3) ]
;
; The field/battle-shared twin of the bit walk InitSkills does over the 32-byte
; $1d2c-$1d4b bitfield (battle_main.asm:14684-14691): one bit per species,
; LSB-first inside each byte, id order.
; a8/i16.  in: A = rage id (0..254).  out: carry = learned, A preserved.
;   clobbers X.  preserves Y.
.proc Ot6RageLearned
        .a8
        .i16
        phy                     ; [$01,s..$02,s] caller Y
        pha                     ; [$01,s] the id
        lsr
        lsr
        lsr                     ; A = id >> 3 = byte index
        longa
        and     #$001f          ; 32 bytes -- ids 0..254 cannot overrun it
        tax
        shorta0
        lda     $01,s           ; the id again
        and     #$07
        longa
        and     #$00ff
        tay                     ; Y = bit index (clean shift count)
        shorta0
        lda     f:$7e1d2c,x     ; the learned-rage bitfield
        iny                     ; shift bit+1 times -> carry = bit
:       lsr
        dey
        bne     :-
        pla                     ; A = the id (PLA preserves carry)
        ply                     ; caller Y  (PLY preserves carry)
        rtl
.endproc

; [ a loadout slot's rage, validated -- the single source of truth ]
;
; Mirrors the Bushido loadout's Ot6LoadoutSlotTech: the stored byte only counts
; if the species is still in the bitfield.  It cannot normally go stale
; (learning is monotonic and nothing ever clears $1d2c), but a corrupt or
; hand-edited save must not put an id in the list that SetRage would resolve
; into monster properties the player never hunted.
; a8/i16.  in: A = slot (0..7).  out: carry set + A = rage id, or carry clear
;   (unset / no longer learned).  clobbers X.  preserves Y.
.proc Ot6RageSlot
        .a8
        .i16
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:OT6_RAGELOAD,x
        beq     @none           ; $00 = unset
        dec     a               ; stored byte - 1 = rage id
        jsl     Ot6RageLearned  ; carry = learned (A preserved)
        bcc     @none
        rtl                     ; carry set, A = the id
@none:  clc
        rtl
.endproc

; [ the n-th learned rage in id order (AUTO's definition) ]
;
; AUTO is "the first eight known rages in id order" -- the head of the very
; list InitSkills builds.  Not "most recently learned" (no storage exists) and
; not "strongest" (no judgment the machinery can make).  BOTH readers call this
; (the field page through Ot6RageShow, the battle build through Ot6RageList's
; AUTO arm), which is what makes the untouched page and the untouched battle
; menu show the same eight beasts by construction rather than by agreement.
; a8/i16.  in: A = n (0-based).  out: carry set + A = the id, or carry clear
;   (fewer than n+1 learned).  clobbers X.  preserves Y.
.proc Ot6RageNth
        .a8
        .i16
        pha                     ; [$01,s] n (counted down)
        phy                     ; [$01,s..$02,s] caller Y (n now $03,s)
        ldy     #$0000          ; candidate id
@try:   tya
        jsl     Ot6RageLearned  ; carry = learned; preserves Y, clobbers X
        bcc     @next
        lda     $03,s
        beq     @hit
        dec     a
        sta     $03,s
@next:  iny
        cpy     #$00ff          ; ids 0..254 (InitSkills' own ceiling)
        bcc     @try
        ply
        pla
        clc                     ; fewer than n+1 learned
        rtl
@hit:   tya                     ; A = the id (a8 reads Y's low byte)
        sta     $03,s           ; overwrite the parked n with it
        ply                     ; caller Y
        pla                     ; A = the id
        sec
        rtl
.endproc

; [ THE CHOKE POINT: build the battle rage list from the loadout ]
;
; Called from InitSkills (battle_main.asm) in place of -- not beside -- the
; vanilla $1d2c walk.  EITHER arm builds the list and returns carry SET; the
; vanilla walk below the call site is now unreachable from here and stays only
; as the reference the AUTO arm is measured against (battle_rage.lua's
; explicitly-labelled equivalence arm).
;
;   MANUAL (any loadout byte nonzero): the stored, still-learned ids in SLOT
;     order -- the player's own arrangement, at most eight.
;   AUTO (all eight bytes zero, the state every pre-existing save and every
;     tracked checkpoint is in): the FIRST EIGHT known rages in id order, via the
;     same Ot6RageNth window the field page draws.
;
; THE AUTO RULING, 2026-07-28 (dispatcher; kit-gau.md §2.2 vs the original
; §8.2).  §2.2 always defined AUTO as "the first eight known rages"; the first
; build pass shipped §8.2's "all-zero hands back to the vanilla walk" instead,
; which meant a player who never opened the configurator still met the vanilla
; 200-entry wall -- the exact thing the owner asked to be rid of ("keep the
; number of his rages within reasonable limits").  The wall must not be
; reachable through inaction, so AUTO truncates.  The collection is untouched:
; $1d2c still holds every species hunted, and the field page still cycles the
; whole bitfield.  Only the BATTLE menu is eight long, always.
;
; Terminator: InitBattle $ff-fills $2000-$341f (battle_main.asm:6096-6102, a
; 16-bit double-store loop) BEFORE it calls InitSkills, so every cell past the
; ones we write is already $ff -- which is what both readers stop on (the
; btlgfx confirm at :20264-20266, RandRage's scan at :992-994).  We write the
; terminator anyway rather than depend on a fill three hundred lines away.
;
; entry: jsl from InitSkills, db=$7e (InitBattle's MVN left it there).  Sets its
; own widths and restores the caller's.  clobbers A,X,Y.  out: carry ALWAYS set
; (the list is built here); the carry-clear "run the vanilla walk" contract is
; kept in the call site for shape, not because this can still return it.
.proc Ot6RageList
        php
        shorta0
        longi
        stz     $3a9a           ; number of known rages, rebuilt below
        ; --- THE WRAM DATA PORT, set exactly the way the vanilla walk sets it.
        ; Vanilla streams the ids through $2180 and, on the way in, writes
        ; hWMADDH = 0 -- and the rest of the game leans on that bank byte being
        ; 0, because dozens of later writers set only the low word
        ; (`ldx #$9e8b / stx hWMADDL` in LoadArrayItem, item.asm:1256;
        ; Ot6LoadoutDrawCost; Ot6DrawRageName's blank arm; ...).  This proc
        ; first used plain `sta $257e,y` stores and so never touched it.  That
        ; was NOT the bug that took battle_dlgmenu/battle_magicite/visual_f2
        ; red (see the AUTO arm below for the one that was, and note it did not
        ; go green until that was fixed) -- the port is kept because a hook
        ; that replaces vanilla code should inherit vanilla's side effects,
        ; not just its output.
        longa
        lda     #$257e          ; pointer to known rages
        sta     f:hWMADDL
        shorta0
        lda     #$00
        sta     f:hWMADDH       ; ... bank 0 -- the load-bearing half
        ; --- AUTO?  all eight bytes zero -> the auto WINDOW, not the wall ---
        ldx     #$0000
@zero:  lda     f:OT6_RAGELOAD,x
        bne     @manual
        inx
        cpx     #OT6_RAGESLOTS
        bcc     @zero
        ; AUTO -- the first eight known rages, in ONE pass over the 32-byte
        ; bitfield, skipping empty bytes whole.
        ;
        ; NOT eight calls to Ot6RageNth.  Ot6RageNth walks ids 0..254 from
        ; scratch every time, so the obvious loop costs ~255 jsl'd bit tests
        ; PER SLOT -- and for the overwhelmingly common party, the one with no
        ; rages at all, it still walks the full 255 before returning "nothing".
        ; That is on the order of twenty thousand cycles added to EVERY
        ; battle's InitSkills, for every party in the game -- and battle init
        ; is frame-coupled: the OT6 font re-lay is staged one slice per nmi and
        ; admission-gated on the live v counter (ot6_hud.asm:644-673).  It took
        ; battle_dlgmenu ("font region corrupt: 1836 bytes differ at vram
        ; $B000+001"), battle_magicite and visual_f2 red -- three tests with
        ; nothing to do with Gau, all green on the pre-change ROM, all green
        ; again with the single pass below.  The field page can afford
        ; Ot6RageNth (one call per drawn row, once per keypress); this cannot.
        ; A = scratch, B = the byte being shifted, X = byte index, Y = ids
        ; emitted, $01,s = bit position.
        ldx     #$0000          ; bitfield byte index
        ldy     #$0000          ; ids emitted so far
@abyte: lda     f:$7e1d2c,x
        beq     @anext          ; empty byte: skip its eight ids outright
        xba                     ; park it in B
        lda     #$00
        pha                     ; [$01,s] bit position 0..7
@abit:  xba                     ; A = the remaining bits
        lsr                     ; carry = this id's bit
        xba                     ; park the rest back (xba does not touch carry)
        bcc     @abitn
        txa                     ; id = byte index * 8 + bit
        asl
        asl
        asl
        clc
        adc     $01,s
        cmp     #$ff            ; id 255 is unlearnable; vanilla's walk stops
        beq     @abitn          ;   at $fe, so neither may emit it
        sta     f:hWMDATA
        inc     $3a9a
        iny
        cpy     #OT6_RAGESLOTS
        bcs     @adone          ; eight carried: the rest of the album stays
@abitn: lda     $01,s
        inc     a
        sta     $01,s
        cmp     #$08
        bcc     @abit
        pla                     ; drop the bit position
@anext: inx
        cpx     #$0020          ; 32 bytes
        bcc     @abyte
        bra     @endauto
@adone: pla                     ; drop the bit position
@endauto:
        lda     #$ff
        sta     f:hWMDATA       ; terminate (belt-and-braces; see the header)
        plp
        sec                     ; handled
        rtl
@manual:
        lda     #$00
        pha                     ; [$01,s] slot -- NOT X: Ot6RageSlot clobbers it
@slot:  lda     $01,s
        jsl     Ot6RageSlot     ; carry set + A = id; kills X
        bcc     @next
        sta     f:hWMDATA
        inc     $3a9a
@next:  lda     $01,s
        inc     a
        sta     $01,s
        cmp     #OT6_RAGESLOTS
        bcc     @slot
@term:  pla                     ; drop the slot / window counter
        lda     #$ff
        sta     f:hWMDATA       ; terminate (belt-and-braces; see the header)
        plp
        sec                     ; handled
        rtl
.endproc

; ------------------------------------------------------------------------------
; GAU'S FIELD CONFIGURATOR -- bank-F0 state logic (the Ot6Loadout* twin)
;
; Same division of labour the Bushido configurator proved: everything that
; DECIDES lives here in F0 and the C3 handler is a thin tilemap/cursor/DMA
; shim, so the field page and the battle list can never disagree about what
; the loadout says.  All entries a8/i16, D = 0 (so the $08/$09 new-press
; joypad and the $4d/$4e cursor position are reachable), rtl.  The learned set
; is read from $1d2c through the SAME Ot6RageLearned leaf the battle build
; uses -- the invariant that kept Bushido's two readers in agreement.
;
; The one shape difference from Bushido: Cyan's "pool" is eight techs and can
; be drawn as a grid, Gau's is up to 255 species and cannot.  So the L/R cycle
; IS the browse -- it walks the $1d2c bitfield -- and a LEARNED count stands in
; for the grid (the collection score, which is the number the hunter cares
; about anyway).
; ------------------------------------------------------------------------------

; [ is the loadout AUTO?  all eight bytes zero ]
; out: carry set = AUTO.  clobbers A,X.  preserves Y.
.proc Ot6RageIsAuto
        .a8
        .i16
        ldx     #$0000
@lp:    lda     f:OT6_RAGELOAD,x
        bne     @manual
        inx
        cpx     #OT6_RAGESLOTS
        bcc     @lp
        sec
        rtl
@manual:
        clc
        rtl
.endproc

; [ the rage a slot SHOWS, validated -- the page's single source of truth ]
; MANUAL returns the stored, still-learned id; AUTO computes the slot's window
; entry on the fly, so merely opening the page writes nothing (the Bushido
; configurator's implicit-seed property, kept).
; in: A = slot (0..7).  out: carry set + A = rage id, carry clear = blank row.
;   clobbers X.  preserves Y.
.proc Ot6RageShow
        .a8
        .i16
        pha
        jsl     Ot6RageIsAuto       ; carry set = AUTO (clobbers A and X)
        pla                         ; A = slot (PLA preserves carry)
        bcs     @auto
        jmp     Ot6RageSlot         ; tail-call: the stored, validated id
@auto:  jmp     Ot6RageNth          ; tail-call: the auto window's slot-th id
.endproc

; [ freeze the AUTO window into the eight bytes (the first edit out of AUTO) ]
; So the un-touched slots keep the beasts they were displaying rather than
; emptying.  A slot the auto window cannot fill (fewer than eight learned)
; stays $00 = unset, which the battle build simply skips.
; clobbers A,X,Y.
.proc Ot6RageSeed
        .a8
        .i16
        ldy     #$0000
@lp:    tya
        jsl     Ot6RageNth          ; carry set + A = id; preserves Y, kills X
        bcc     @done               ; fewer than Y+1 learned: the rest stay unset
        inc     a                   ; stored byte = id + 1
        phy
        plx                         ; X = slot (the i16 transfer idiom; Y intact)
        sta     f:OT6_RAGELOAD,x
        iny
        cpy     #OT6_RAGESLOTS
        bcc     @lp
@done:  rtl
.endproc

; [ open the configurator: cursor to the top slot ]
; Leaves the eight bytes as they are -- AUTO stays AUTO until the first edit,
; because Ot6RageShow computes the window per slot on the fly.
; clobbers A.
.proc Ot6RageOpen
        .a8
        .i16
        stz     $4d                 ; cursor: single column
        stz     $4e                 ; ... top slot
        stz     $4f
        stz     $50
        stz     $51
        stz     $52
        rtl
.endproc

; [ which slot is the cursor on?  the page is two columns of four ]
;
; The menu framework's own index for a {cols, rows} cursor is
; `$4b = $53 * $4e + $4d` (CalcShortListIndex, menu_common.asm:1205-1224) --
; row-major, so reading order left-to-right, top-to-bottom.  We recompute it
; here rather than read $4b because $4b is only refreshed by C3's
; UpdateCursorPos at the TOP of the frame: a cycle in the same frame as a move
; would otherwise edit the slot the cursor just left.
; a8/i16.  out: A = slot (0..7).  clobbers nothing else.
.proc Ot6RageCurSlot
        .a8
        .i16
        lda     $4e                 ; cursor row (0..OT6_RAGEROWS-1)
        asl                         ; * OT6_RAGECOLS (2)
        clc
        adc     $4d                 ; + cursor column (0..1)
        rtl
.endproc

; [ cycle the cursored slot to the prev/next LEARNED rage; go MANUAL ]
; The first edit out of AUTO freezes the window first (Ot6RageSeed), then walks
; the $1d2c bitfield from the slot's current id to the next/previous set bit,
; wrapping over 0..254 -- vanilla's own id range (InitSkills stops at $fe).
; A slot showing nothing starts its walk at id 0.  Uses menu scratch $e0 (D=0),
; free during input, exactly as Ot6LoadoutAssign uses $e0..$e4.
; in: A = step delta ($01 = next, $ff = previous).  clobbers A,X,Y.
.proc Ot6RageCycleCore
        .a8
        .i16
        pha                         ; [$01,s] delta
        jsl     Ot6RageIsAuto
        bcc     :+
        jsl     Ot6RageSeed         ; first edit: freeze the window into bytes
:       jsl     Ot6RageCurSlot      ; cursored slot (0..7), from column+row
        jsl     Ot6RageShow         ; carry set + A = the id it is showing
        bcs     :+
        lda     #$00                ; blank row: start the walk at id 0
:       sta     $e0
        ldy     #$00ff              ; try every id once (0..254)
@hop:   lda     $e0
        clc
        adc     $01,s               ; += delta
        cmp     #$ff                ; $ff is off both ends of 0..$fe
        bcc     @have
        lda     $01,s
        bmi     @low                ; delta $ff (down): 0 - 1 wraps to $fe
        lda     #$00                ; delta $01 (up):  $fe + 1 wraps to 0
        bra     @have
@low:   lda     #$fe
@have:  sta     $e0
        jsl     Ot6RageLearned      ; carry = learned (A preserved)
        bcs     @found
        dey
        bne     @hop
        pla                         ; nothing learned at all: leave it alone
        rtl
@found: jsl     Ot6RageCurSlot      ; A = the cursored slot
        longa
        and     #$00ff
        tax                         ; X = slot
        shorta0
        lda     $e0
        inc     a                   ; stored byte = id + 1
        sta     f:OT6_RAGELOAD,x
        pla                         ; drop delta
        rtl
.endproc

Ot6RageNext:                        ; R shoulder -> next learned rage
        lda     #$01
        jmp     Ot6RageCycleCore
Ot6RagePrev:                        ; L shoulder -> previous learned rage
        lda     #$ff
        jmp     Ot6RageCycleCore

; [ per-frame input: mutate loadout state; tell C3 what to do next ]
; The Ot6LoadoutInput contract, over the two-column, four-row page:
;   B      -> exit               (return A = 2)
;   Up/Dn  -> move the row       (return A = 1: redraw)
;   Lt/Rt  -> the other column   (return A = 1)   (dpad; only two columns, so
;             either direction is the same toggle)
;   L/R    -> cycle the slot     (return A = 1)   (shoulders)
;   Y      -> revert to AUTO     (return A = 1)   (NOT Select -- FF6's default
;             config aliases physical Select onto the R bit, so it cannot be
;             told apart from the R-shoulder cycle)
;   else                          (return A = 0: idle)
.proc Ot6RageInput
        .a8
        .i16
        lda     $09                 ; dpad / B / Y / Select / Start
        bit     #$80                ; B -> exit
        beq     :+
        lda     #$02
        rtl
:       bit     #$08                ; Up
        beq     @dn
        lda     $4e
        bne     :+
        lda     #OT6_RAGEROWS       ; wrap 0 -> last row (pre-decrement)
:       dec     a
        sta     $4e
        lda     #$01
        rtl
@dn:    lda     $09
        bit     #$04                ; Down
        beq     @side
        lda     $4e
        inc     a
        cmp     #OT6_RAGEROWS
        bcc     :+
        lda     #$00                ; wrap last -> 0
:       sta     $4e
        lda     #$01
        rtl
@side:  lda     $09
        bit     #$03                ; dpad Left/Right -> the other column
        beq     @sel
        lda     $4d
        eor     #$01                ; exactly two columns: either way toggles
        sta     $4d
        lda     #$01
        rtl
@sel:   lda     $09
        bit     #$40                ; Y -> revert to AUTO (all eight bytes 0)
        beq     @lr
        ldx     #$0000
        lda     #$00
:       sta     f:OT6_RAGELOAD,x
        inx
        cpx     #OT6_RAGESLOTS
        bcc     :-
        lda     #$01
        rtl
@lr:    lda     $08                 ; A / X / L / R shoulders
        bit     #$20                ; L shoulder -> previous learned rage
        beq     @rsh
        jsl     Ot6RagePrev
        lda     #$01
        rtl
@rsh:   lda     $08
        bit     #$10                ; R shoulder -> next learned rage
        beq     @idle
        jsl     Ot6RageNext
        lda     #$01
        rtl
@idle:  lda     #$00
        rtl
.endproc

; [ how many rages are known?  the collection score ]
; Popcount of the whole $1d2c-$1d4b bitfield.  Stands in for the pool grid
; Cyan's page draws: with up to 255 candidates the grid is not expressible,
; and the count is the number the collection game is actually about.
; out: A = count (0..255).  clobbers A,X,Y and menu scratch $e0/$e1.
.proc Ot6RageCount
        .a8
        .i16
        ldx     #$0000
        ldy     #$0000              ; running count
@byte:  lda     f:$7e1d2c,x
        beq     @next
        sta     $e0
        lda     #$08
        sta     $e1
@bit:   lsr     $e0
        bcc     :+
        iny
:       dec     $e1
        bne     @bit
@next:  inx
        cpx     #$0020              ; 32 bytes
        bcc     @byte
        tya                         ; a8: the count's low byte (max 255)
        rtl
.endproc

; [ price a rage row -- ALWAYS defined, flag-gated body ]
; The Ot6LoadoutCost shim, for the shared (flag-agnostic) menu object: ON
; tail-calls the one price authority, nomp returns 0 and the row draws no
; number.  Every row shows the SAME number by design -- the price is flat, so
; the column doubles as the rule's teaching surface.
; out: A = MP cost (0 under nomp).  rtl.
.proc Ot6RageRowCost
        .a8
        .i16
.if ::OT6_MP_COSTS
        jmp     Ot6RageCost         ; tail-call: its rtl returns for us
.else
        lda     #$00
        rtl
.endif
.endproc

; ------------------------------------------------------------------------------

; [ latch the trance's boost tier (Cmd_10's entry) ]
;
; BP is spent once, at the Rage-START action, through the normal Ot6ActionEnd
; consume -- but the TIER must outlive that action by the whole battle, because
; every possessed turn after it rolls the same tilted coin.  That is Slot's
; problem at longer range: Ot6SlotRig latches the spin's tier so the charge and
; the reels can never disagree; this latches the trance's tier so the charge and
; the whole possession can never disagree.
;
; It fires ONLY on the start turn -- the turn whose RAGE status bit is still
; clear.  A mid-trance Cmd_10 (every possessed turn re-enters here) finds the
; bit set and leaves the latch alone; latching there would read the already-
; consumed pending byte and silently drop the trance to tier 0.
;
; TWO CALL SITES, and the second one is why the ladder works on the start turn:
;   * FixPlayerAttack's cmd-$10 arm (battle_main.asm @4dec) -- where vanilla
;     rolls the START turn's attack, at action LOAD, before Cmd_10 exists.
;     Measured: without this site, roll 1 of a 1-BP trance saw tier 0 and rolls
;     2..5 saw tier 1 -- the turn the BP was spent on was the one turn it did
;     not buy (battle_rage.lua's tier arms assert the fix).
;   * Cmd_10 itself -- for the auto-queued possessed turns, and as the
;     belt-and-braces latch if the load path is ever reached differently.
; Both are idempotent on the start turn: the pending byte is not consumed until
; Ot6ActionEnd, so the second latch stores the same value the first did.
;
; entry: jsl from either site, a8, Y = attacker entity, db=$7e.  Index width is
; not assumed -- Y only ever indexes two absolute tables with an entity index.
; clobbers A's low half only (a8), preserving B for FixPlayerAttack's xba.
.proc Ot6RageTierLatch
        .a8
        lda     $3ef9,y         ; status 4
        lsr                     ; bit 0 = RAGE: already possessed?
        bcs     @done           ; mid-trance turn: the latched tier stands
        lda     OT6_BOOST_REVEALED,y     ; pending boost 0-3
        cmp     #$04
        bcc     :+
        lda     #$03            ; (defensive: Ot6Boost already caps at 3)
:       sta     f:$7e0000+OT6_RAGETIER
@done:  rtl
.endproc

; [ boost tilts Rage's coin -- the chance verb's certainty, Dance-shaped ]
;
; DESIGN.md's canon: on damage verbs boost multiplies, on chance verbs boost
; GUARANTEES, in the verb's own vocabulary.  Rage's vocabulary is one coin per
; possessed turn -- RandCarry + rol picks entry 0 (always plain Fight) or entry
; 1 (the beast's special; monster_rage.asm:3-5).  The beast was already chosen
; from the menu, so the gamble BP buys off is which half of it shows up, and it
; buys it for the whole trance:
;
;   tier 0   the caller's own carry, untouched                       1/2
;   tier 1   the special unless a fresh draw < $40                    3/4
;   tier 2   the special unless a fresh draw < $10                  15/16
;   tier 3   no roll at all -- the special, every turn, all trance    1/1
;
; Each point roughly quarters the miss odds (1/2 -> 1/4 -> 1/16 -> 0), the same
; converging ladder Steal shipped.  The tilt is toward entry 1 because entry 0
; is always plain Fight -- nobody spends BP to punch more predictably.
;
; RNG DISCIPLINE: tier 0 draws NOTHING extra, so a 0-BP trance walks exactly
; the RNGTbl indices vanilla walks -- that is the byte-identical arm the
; fixture asserts, and it is why the tier test can be a same-drive A/B.
;
; entry: jsl from RandRage (bank C2) immediately after its `jsr RandCarry`,
; a8, INDEX WIDTH UNKNOWN (the site precedes RandRage's `longai`).  So the
; caller's P is parked and the index-width bit restored by hand at the end --
; `plp` would also restore the stale carry this proc exists to replace.
; in: carry = vanilla's coin, A = the value RandRage is about to `rol`.
; out: carry = the tier's coin.  A and Y preserved; X clobbered.
.proc Ot6RageCoin
        .a8
        pha                     ; [$01,s] the caller's A (the rol operand)
        lda     #$00
        rol                     ; A = vanilla's coin (0/1); carry consumed
        pha                     ; [$01,s] coin
        php
        pla                     ; A = caller P ...
        pha                     ; [$01,s] ... parked for the width restore
        rep     #$10            ; i16, so phy has a known width.  an 8-bit Y
        .i16                    ;   widens to $00yy and sep #$10 truncates it
        phy                     ;   back -- correct from either caller width
        ;   stack from here: $01,s Ylo  $02,s Yhi  $03,s P  $04,s coin  $05,s A
        lda     f:$7e0000+OT6_RAGETIER
        beq     @done           ; tier 0: vanilla's coin stands, no extra draw
        cmp     #$03
        bcc     @tilt
        lda     #$01            ; tier 3+: the special, unconditionally
        sta     $04,s           ; overwrite the parked coin
        bra     @done
@tilt:  cmp     #$02
        beq     @t2
        lda     #$40            ; tier 1: the special unless draw < $40
        bra     @roll
@t2:    lda     #$10            ; tier 2: the special unless draw < $10
@roll:  pha                     ; [$01,s] threshold -- everything else +1
        sep     #$10            ; ot6_rand indexes $be as a BYTE
        .i8
        ot6_rand                ; A = draw 0-255 (the macro saves/restores X)
        cmp     $01,s           ; carry set iff draw >= threshold
        lda     #$00
        rol                     ; A = 1 when the special wins
        sta     $05,s           ; overwrite the parked coin
        pla                     ; drop the threshold
        rep     #$10
        .i16
@done:  ply                     ; caller Y
        pla                     ; A = caller P
        and     #$10            ; restore the index width by hand: sep/rep
        beq     @i16            ;   leave C alone, plp would not
        sep     #$10
        bra     @coin
@i16:   rep     #$10
@coin:  pla                     ; A = the coin (0/1)
        lsr                     ; -> carry
        pla                     ; A = the caller's original A (PLA keeps C)
        rtl
.endproc
