; ------------------------------------------------------------------------------
; OT6: Umaro's kit (#380)
;
; kits.md "Umaro": he takes no orders.  Every turn the engine picks one of
; his four arms (_163b, battle_main.asm): Charge, Fight, and, with the right
; relic, Throw (Rage Ring) and Storm (Blizzard Orb).  His bank fills a pip a
; turn and, when he is hurt, he dumps it on his next action (#237,
; Ot6UmaroRetaliate), so a full boost for him is a dump of all three points.
; Two things here make that a kit:
;
;   * Charge and Throw are bludgeoning (Ot6UmaroCharge, Ot6UmaroThrow, just
;     before each runs ExecAttack).  Each loads the classless "battle"
;     record and swings no weapon, so neither chipped anything
;     (measured: class $00 at every Charge pass).  A body slammed or an ally
;     hurled is a club's blow.  His Fight takes his weapon's class (a Bone
;     Club, or bare fists: bludgeoning) and Storm its element (ice), as they
;     did.
;   * His divine: a full dump is always Storm.  With three points pending at
;     his chooser the roll is not made: he Storms, ice on every enemy at the
;     boost's x8, with or without the Blizzard Orb.  That is the one gate
;     (kits.md "Divines"): only a dump of all three points spends three, and
;     only being hurt makes him dump, so no Muddle, Charm or Colosseum turn of
;     his reaches it without them.  Under three points the roll is vanilla's.
;     *Reason: a full boost on a character the player cannot aim should buy
;     the arm that needs no aim, and an ice key on a whole formation.*
; ------------------------------------------------------------------------------

.segment "ot6_code"

; [ Umaro's chooser: the arm mask and the divine ]
; jsl from _163b (battle_main.asm) in place of `lda $fe / tax / ora #$30`,
; after the relic tests built $fe ($04 Rage Ring, $08 Blizzard Orb) and
; before RandBitWithRate rolls the arm.  out: X = the rate-table row (vanilla:
; $fe), A = the arms allowed before `asl2` (vanilla: $fe | $30, Charge and
; Fight always).  With three points pending (the dump Ot6UmaroRetaliate made
; at this chooser's head): row 2 and Storm alone ($08 -> $20 after the asl2,
; the bit RandBitWithRate hands to UmaroAttackTbl's slot 1).
; a8, either index width (B is cleared before each tax), y = Umaro's entity
; offset, db=$7e.
.proc Ot6UmaroArm
        .a8
        xba
        lda     #$00
        xba                     ; B = 0, so each tax below is the byte
        phx
        tyx
        lda     OT6_BOOST_REVEALED,x
        plx
        cmp     #$03            ; the divine's one gate: a full boost
        bcc     @roll
        lda     #$08            ; Storm alone, on row 2's rates
        tax
        rtl
@roll:  lda     $fe
        tax
        ora     #$30
        rtl
.endproc

; [ Charge and Throw: the command they draw as, and the club's class ]
; jsl from UmaroAttack_02 / UmaroAttack_00 (battle_main.asm) in place of
; `lda #$23 / sta $b5` and `lda #$24 / sta $b5`, the last writes before each
; jumps to ExecAttack: the "battle" record they loaded on the way here set
; the class to none (Ot6SkillClass), and nothing between here and the chip
; loads another.  a8, db=$7e.  clobbers A; preserves X and Y.
.proc Ot6UmaroCharge
        .a8
        lda     #$23
        bra     Ot6UmaroClub
.endproc

.proc Ot6UmaroThrow
        .a8
        lda     #$24
        ; fall through
.endproc

.proc Ot6UmaroClub
        .a8
        sta     $b5             ; the command it draws as (vanilla's write)
        lda     #OT6_BLUDG
        sta     f:$7e0000+OT6_ATKCLASS
        rtl
.endproc
