.ifndef OT6_MEMORY_INC
OT6_MEMORY_INC = 1

; OT6 memory ABI.  This file only names owned storage and proves its bounds;
; routine width/clobber contracts remain beside the routines that implement
; them.  Keep this include non-emitting.

; Per-entity battle state. Entity offsets are $00-$06 for characters and
; $08-$12 for monsters.
OT6_SHIELD_CUR       := $3e38
OT6_SHIELD_MAX       := $3e39
OT6_BROKEN_TICKS     := $3e88
OT6_REVEALED_ELEM    := $3e89
OT6_BP_CLASS         := $3e9c
OT6_BOOST_REVEALED   := $3e9d

.assert OT6_SHIELD_CUR + $12 < OT6_BROKEN_TICKS, error, "OT6 entity state overlaps"
.assert OT6_BROKEN_TICKS + $12 < OT6_BP_CLASS, error, "OT6 entity state overlaps"
.assert OT6_BOOST_REVEALED + $12 <= $3eaf, error, "OT6 entity state exceeds owned battle RAM"

; Per-save weakness codex. Each save owns a $400-byte SRAM page; the fourth
; page is transient knowledge for an unsaved New Game.
OT6_CODEX_ROOT       := $316000
OT6_CODEX_STRIDE     := $0400
OT6_CODEX_MAGIC      := OT6_CODEX_ROOT
OT6_CODEX            := OT6_CODEX_ROOT+$0010
OT6_CODEX_CLASS      := OT6_CODEX_ROOT+$0190
OT6_CODEX_TEMP       := $0c00
OT6_CODEX_USED       := $0310

.assert OT6_CODEX_ROOT >= $316000, error, "OT6 codex precedes expanded SRAM"
.assert OT6_CODEX_TEMP = 3 * OT6_CODEX_STRIDE, error, "transient codex is not page four"
.assert OT6_CODEX_CLASS + 384 <= OT6_CODEX_ROOT + OT6_CODEX_USED, error, "class codex exceeds used page"
.assert OT6_CODEX_USED <= OT6_CODEX_STRIDE, error, "OT6 codex page exceeds stride"
.assert OT6_CODEX_ROOT + OT6_CODEX_TEMP + OT6_CODEX_USED <= $317000, error, "OT6 codex exceeds expanded SRAM"

; Per-save working-data word, copied and checksummed by vanilla save code.
OT6_LOADOUT          := $7e1e1d
.assert (OT6_LOADOUT & $ffff) >= $1600, error, "loadout must sit inside the save block"
.assert (OT6_LOADOUT & $ffff) + 1 <= $1ffd, error, "loadout word must sit inside the checksum window"

; Gau's 8-slot rage loadout, one byte per slot, in the next eight bytes of
; the same save-block scrap the Bushido word lives in.  byte = rage id + 1;
; $00 = unset; all eight zero = AUTO (the first eight known rages in id
; order, the head of the vanilla list).  Rage ids run 0..254 (InitSkills
; stops at $fe, LearnRage skips monster index > 255), so +1 fits a byte with
; nothing real outside it.  Remaining scrap after this: $1e27-$1e3f.
OT6_RAGELOAD         := $7e1e1f
OT6_RAGESLOTS        = 8
; The configurator's page geometry, shared by the C3 draw and the F0 cursor
; walk so they cannot disagree about which slot a row is.  Two columns of
; four, because the EN field-menu window fits eight text rows (the
; 12px cadence; see field_menu.asm's Ot6RageDrawSlots header) and a single
; column of eight would leave no row for the title or the LEARNED count.  It
; is also vanilla's own shape for this window: the rage browse is
; `cursor_prop {0,0}, {2,8}` at 12px pitch (skills.asm:281-299).
OT6_RAGECOLS         = 2
OT6_RAGEROWS         = 4
.assert OT6_RAGECOLS * OT6_RAGEROWS = OT6_RAGESLOTS, error, "rage page geometry must cover every slot exactly once"
.assert (OT6_RAGELOAD & $ffff) >= $1600, error, "rage loadout must sit inside the save block"
.assert (OT6_RAGELOAD & $ffff) + OT6_RAGESLOTS - 1 <= $1ffd, error, "rage loadout must sit inside the checksum window"
.assert (OT6_RAGELOAD & $ffff) = (OT6_LOADOUT & $ffff) + 2, error, "rage loadout must follow the bushido word without a gap"

; Strago's 5-slot lore loadout, one byte per slot, in the next five bytes of
; the same scrap.  byte = lore id + 1 (ids 0..23, the $1d29-$1d2b bitfield's
; 24 bits); $00 = unset; all five zero = AUTO (the first five known lores in
; id order).  Five and not eight: Gau's rages are his whole kit, while
; Strago's lores are one verb inside an 8-row kit that also carries Analyze
; and Aqua Rake.  Remaining scrap after this: $1e2c-$1e3f.
OT6_LORELOAD         := $7e1e27
OT6_LORESLOTS        = 5
OT6_LORECOLS         = 1
OT6_LOREROWS         = 5
.assert OT6_LORECOLS * OT6_LOREROWS = OT6_LORESLOTS, error, "lore page geometry must cover every slot exactly once"
.assert (OT6_LORELOAD & $ffff) >= $1600, error, "lore loadout must sit inside the save block"
.assert (OT6_LORELOAD & $ffff) + OT6_LORESLOTS - 1 <= $1ffd, error, "lore loadout must sit inside the checksum window"
.assert (OT6_LORELOAD & $ffff) = (OT6_RAGELOAD & $ffff) + OT6_RAGESLOTS, error, "lore loadout must follow the rage bytes without a gap"

; Battle-only scratch. InitBattle clears through $3ed3. OT6_DIVINE_USED is
; one per-character bitmask; the walkers use the interleaved even words.
; OT6_DIVINE_USED survives a Cmd_20 scene-change reload, so a multi-phase
; boss keeps its "divine already spent" flag across the reload.
OT6_DIVINE_USED      := $3ecb
OT6_SCR_SLOT2        := $3ecc
OT6_SCR_BIT          := $3ece
OT6_SCR_IDX          := $3ed0
OT6_SCR_COLS         := $3ed2

.assert OT6_DIVINE_USED >= $3ecb, error, "OT6 battle scratch precedes owned range"
.assert OT6_SCR_COLS + 1 <= $3ed3, error, "OT6 battle scratch exceeds owned range"

; Battle/HUD global scratch.
OT6_MAPBASE          := $57b6
OT6_ATKCLASS         := $57b8
OT6_FONTDIRTY        := $57b9
OT6_SLOTTIER         := $57ba   ; Slot's stored boost tier:
                                ;   written at the spin's first A press by
                                ;   Ot6SlotRig, re-banked into
                                ;   OT6_BOOST_REVEALED by Ot6SlotCommit so
                                ;   Ot6ActionEnd charges what the reels
                                ;   delivered (ot6_slot.asm, the Slot strip)
OT6_PIPTAIL          := $57bb   ; frames of live pip painting left after
                                ;   an ActionEnd with the battle menu closed.
                                ;   keeps the charge visible on its own
                                ;   frame.  set by Ot6ActionEnd (characters),
                                ;   decremented by Ot6PipStage, cleared by
                                ;   InitBP (init-exempt strip: power-on junk
                                ;   would paint pips over the intro).
OT6_RANDPEND         := $57bc
OT6_RANDBTL          := $57bd
OT6_HUDVEIL          := $57be
OT6_SCRIPTBUSY       := $57bf
OT6_SPECIES          := $57c0
OT6_PIPCUR           := $57cc   ; live pip cell (0 = off); keeps the
OT6_PIPPREV          := $57ce   ;   one-cell footprint and moves only which
OT6_PIPCELL          := $57d0   ;   cell it is (see Ot6PipStage)
OT6_LASTLR           := $57d2
OT6_RESTAGE          := $57d4

.assert OT6_MAPBASE + 1 < OT6_ATKCLASS, error, "OT6 HUD scratch overlaps"
.assert OT6_ATKCLASS < OT6_FONTDIRTY, error, "OT6 HUD scratch overlaps"
.assert OT6_RANDPEND + 3 = OT6_SCRIPTBUSY, error, "OT6 HUD flags are not contiguous"
.assert OT6_SCRIPTBUSY < OT6_SPECIES, error, "OT6 HUD scratch overlaps"
.assert OT6_SPECIES + 11 < OT6_PIPCUR, error, "OT6 species and pip scratch overlap"
.assert OT6_RESTAGE = $57d4, error, "OT6 restage byte moved outside owned range"

; BG HUD line shadow buffer.
OT6_SHADOW           := $ecf1
.assert OT6_SHADOW + (14 * 6) - 1 <= $ed44, error, "OT6 HUD shadow exceeds owned range"

; The shadow tail: the same measured-free $7eecf1-$7ef11f range the shadow
; claims (ot6_hud.asm's four lines of evidence; PushMode7Vars owns $f120+).
;
; pending reveals: a chip banks its newly-revealed weakness bits here at
; damage-calc time; Ot6RevealCommit moves them into OT6_REVEALED_ELEM /
; monster OT6_BOOST_REVEALED (and every same-species slot) on the damage
; frame (the first numeral display, GfxCmd_0b), with Ot6ActionEnd as the
; no-numeral backstop.  One byte per monster slot, stride 2 (indexed by the
; slot offset 0,2..10 like $3e91/$3ea5; odd bytes unused).  Cleared by
; InitBP's shadow clear and per-slot by Ot6SeedShields (Cmd_20 reloads).
OT6_RVPEND_ELEM      := $ed45   ; 12 bytes
OT6_RVPEND_CLS       := $ed51   ; 12 bytes
; wallet pseudo-line: current-MP display painted into the open costed
; list window every nmi.  CUR/PREV are the first cell's vram word address
; (0 = off; prev != cur blanks the old cells one-shot), CELLS the staged
; glyph|attr words.  CUR/PREV cleared by InitBP's extended shadow clear.
OT6_WALLETCUR        := $ed5d
OT6_WALLETPREV       := $ed5f
OT6_WALLET_W         = 5        ; [M][P][hundreds][tens][ones]
OT6_WALLETCELLS      := $ed61   ; OT6_WALLET_W words
OT6_WALLETSIG        := $ed6d   ; staged MP value; the flush repaints only
OT6_WALLETSIGP       := $ed6f   ;   when CUR or SIG moves (see the flush)
OT6_PIPSLOT          := $ed6b   ; the character slot the live pip cell
                                ;   follows while OT6_PIPTAIL runs, the
                                ;   one who just spent BP (Ot6ActionEnd sets
                                ;   both)
; The wallet's five glyph|attr words are written unrolled (OT6_WALLETCELLS+0
; through +9, ot6_hud.asm:1474-1516), so no code mentions the
; width.  That is why OT6_WALLET_W is a comment-only symbol,
; and why a sixth cell could be added there without anyone noticing that the
; run ends flush against OT6_PIPSLOT with no slack.  The assert below catches
; that.  Equality is the current, intended fit ($ed61 + 10 =
; $ed6b), so the bound is <=, not <.
.assert OT6_WALLETCELLS + OT6_WALLET_W * 2 <= OT6_PIPSLOT, error, "OT6 wallet cells run into OT6_PIPSLOT"
OT6_RAGETIER         := $ed73   ; the boost tier stored at Cmd_10 for the
                                ;   whole trance (Slot's OT6_SLOTTIER pattern at
                                ;   longer range: BP is spent once at the
                                ;   Rage-start action but the tier must outlive
                                ;   it).  lives in the measured-free shadow
                                ;   tail, past InitBP's $70-byte clear.
                                ;   Staleness is harmless for the same reason
                                ;   as Slot's: it is read only while a RAGE
                                ;   status is set, and
                                ;   the only writer of that status (Cmd_10)
                                ;   always rewrites the store first.
OT6_NUMCTR           := $ed71   ; last-seen damage-numeral thread counter
                                ;   ($632e).  a change means GfxCmd_0b has
                                ;   allocated a numeral (the damage frame)
                                ;   and Ot6RevealPoll commits pending reveals.
                                ;   past InitBP's clear on purpose: a stale
                                ;   value costs one no-op commit (see the proc)
OT6_COVERPAID        := $ed72   ; per-character bitmask (----1234, the
                                ;   OT6_DIVINE_USED / $3f2f shape).  bit set =
                                ;   that character's True Knight cover has
                                ;   already banked its BP this round.  set by
                                ;   Ot6CoverBP, cleared per character by
                                ;   Ot6ActionEnd (the round boundary) and
                                ;   wholesale by InitBP.  unlike NUMCTR a stale
                                ;   value here would suppress a real earn, so
                                ;   it is init-cleared explicitly.
OT6_PIPPEND          := $ed74   ; a deferred pip paint: character slot
                                ;   + 1 (0 = nothing pending).  Ot6CoverBP
                                ;   banks the blocker here at the cover commit
                                ;   instead of arming OT6_PIPSLOT/OT6_PIPTAIL
                                ;   directly, because that commit precedes the
                                ;   damage numeral by many frames while the
                                ;   tail is short, so the pip would flash and
                                ;   fade before the block visibly landed.
                                ;   Ot6PipPending (ot6_hud.asm) moves
                                ;   it into the live cell on the numeral frame,
                                ;   as Ot6RevealCommit/Ot6RevealPoll do
                                ;   for weakness reveals.  A stale value would
                                ;   paint a spurious pip on the first numeral
                                ;   of the next battle, so InitBP clears it.
; the break flash.  One byte per monster slot, stride 2 and indexed by
; the slot offset 0,2..10 like OT6_RVPEND_* (so a chip holding the
; entity offset in y writes OT6_BRKTICK-8,y and the walkers read
; OT6_BRKTICK,y); odd bytes unused.  The byte is a small state machine:
;   $00        idle
;   $ff        pending: the shields emptied at damage calc and the flash is
;              waiting for the damage frame (Ot6BreakArm, off Ot6RevealPoll's
;              numeral edge / Ot6ActionEnd's backstop, the OT6_PIPPEND shape)
;   1..$18     a live flash, counting down one per main-loop frame
; OT6_BRKPAL banks the monster's own sprite-palette bits (w7e80db & $0e) for
; the frame the flash hands the sprite back.
; Both live past InitBP's shadow clear, so power-on junk is possible; every
; reader is gated on the monster being present ($3aa8) and Ot6SeedShields
; zeroes both per slot at every seed (fresh battle and Cmd_20 reload), which
; is the same clearing contract OT6_RVPEND_* already runs on.
;
; The per-battle-frame path (WaitFrame, after WaitVblank returns,
; btlgfx_main.asm:432-445) has essentially no cycle slack: the battle loop's
; per-iteration budget is close enough to full that a small overrun makes
; WaitVblank miss and the whole iteration costs an extra hardware frame. So
; OT6_BRKLIVE gates the per-frame break-flash painter inline at its call site
; (ot6_hud.asm) rather than through a proc call, since even a `jsr` into a
; proc that early-outs is over budget.  Nonzero = at least one slot has a
; live countdown; the painter recomputes it as it walks, so a stale value
; costs exactly one walk and the byte needs no init clear.
;
; MEASURED SINCE (#236): "essentially no cycle slack" is too strong.  A delay
; loop of known length on that very path, watched through WaitVblank's own
; return interval rather than through a phase length, misses no vblank at
; ~10k cycles per iteration, misses a third of them at ~20k and a third at
; ~41k (build/lab/canary/, and the calibration table in
; battle_trueknight.lua).  So the real headroom is thousands of cycles, not
; tens, and the inline gate above is cheap insurance rather than a
; requirement.  What the old evidence for "no slack" was actually seeing is
; a phase span re-rounding by a whole ATB round on a one-frame shift; that
; is why the canary now counts dropped vblanks instead.
OT6_BRKLIVE          := $ed75
OT6_BRKTICK          := $ed76   ; 12 bytes
OT6_BRKPAL           := $ed82   ; 12 bytes
; boosted Runic.  On reactive verbs, boost buys duration, and
; Runic is the first instance, so the stance needs a lifetime.  Vanilla gives
; it none: its stance is one bit that clears on the first absorb or on
; Celes's next action (battle_main.asm:8671 and :511).
;
; Turns, one byte per character, stride 2 and indexed by the entity offset
; (0/2/4/6) like OT6_BP_CLASS.  Ot6RunicRaise records the pending boost here
; at Cmd_0b, Ot6RunicHold decrements it at each of her QueueActions and puts
; the stance bit back, and 0 means vanilla Runic: one absorb, then it clears.
; The odd bytes are unused.  It is a turn count rather than an absorb count
; for two reasons: a turn count is legible to the player ("three turns of
; shield"), and it bounds the BP earn by construction, since the earn is
; capped at one per round.  Cleared per character by InitBP, because it sits
; past the shadow clear and a stale value would give the next battle a
; standing stance nobody raised, which is a mechanic and not a cosmetic.
OT6_RUNICTURNS       := $ed8e   ; 8 bytes (4 characters, stride 2)
; the once-per-round absorb-earn flag, a per-character bitmask
; (----1234, the OT6_COVERPAID / $3f2f shape).  Bit set = that character's
; Runic has already banked its BP this round.
;
; This is a separate byte from OT6_COVERPAID by design.  The cover flag has
; the same shape and four spare high bits, but they are different verbs with
; different prices: Runic costs a turn, and a
; True Knight cover costs a relic slot and nothing else.  One shared flag
; would make equipping True Knight reduce Celes's Runic earn, an
; interaction nobody asked for and nobody would find.  The rule that a
; reactive earn happens once per round is shared; the storage is not.
OT6_RUNICPAID        := $ed96
; the retaliation pair (#236).  Two per-character bitmasks in the
; ----1234 shape OT6_COVERPAID / OT6_RUNICPAID / $3f2f already use.
;
; OT6_UNCTL  bit set = the ENGINE, not the player, chose this character's
;            action.  Set by Ot6UnctlMark at the two sites vanilla chooses
;            FOR an entity: RandCharAction -- its own "select berserk/
;            zombie/muddled/charmed/colosseum action" (battle_main.asm),
;            which is also the arm Umaro reaches, since CheckPlayerAction
;            refuses him a window by name -- and ExecMonsterAction, where
;            QueueAction sends a character with an AI script (#238).
;            Cleared by Ot6UnctlClear at the one site that means the
;            opposite: the frame CheckPlayerAction opens the battle menu for
;            him.  The hooks are the sides of one vanilla decision, so the
;            bit is the decision, not a re-derivation of it.
;
; It sits past InitBP's $70-byte shadow clear, and a stale bit here is a
; mechanic and not a cosmetic -- it would hand the next battle's first
; uncontrolled swing a free dump -- so InitBP zeroes it explicitly.
OT6_UNCTL            := $ed97

; ...and what "got hit" is measured against: the hp each character stood on
; when its OWN last turn ended, one word per character, stride 2, indexed by
; the entity offset (0/2/4/6) like OT6_BP_CLASS.  0 = no line yet (the
; character has not acted in this battle), which is why InitBP zeroes it.
;
; Ot6ActionEnd draws the line; Ot6Retaliate reads it and, when the actor now
; stands BELOW it, dumps and moves the line to where it stands -- so one
; hurt buys one dump.
;
; Why a line and not a damage hook (#236).  The obvious hook is ApplyDmgHP's
; damage-taken arm, and it was written that way first.  battle_trueknight's
; frame-budget canary refused it: 1635 frames intact, 1798 -- exactly one
; missed vblank per battle-loop iteration -- with a `jsl` there, 1635 again
; with four NOPs in its place (same four bytes, same address), and still
; 1798 with the called proc reduced to a bare `rtl`.  So it is that site's
; cycles, at the jsl/rtl alone, and nothing belongs on it
; (build/attempts/regress/trueknight-{nocalls,clearonly,clear_prov,
; clear_4nop,prov_rtl}.log).  The line costs one 16-bit load and store per
; character action instead, on a path that runs once a turn.
;
; It also reads better in play than a damage flag: a character is provoked
; while it stands worse off than when it last swung, so several small hits
; add up to one retaliation tally, and an ally who heals it back up has genuinely
; un-provoked it.
OT6_HPMARK           := $ed98   ; 8 bytes (4 characters, stride 2)
OT6_BREAK_FLASH      = $18      ; 24 frames: three 4-frame pulses (see
                                ;   Ot6BreakFlash's `and #$04` cadence)
OT6_BREAK_SFX        = $be      ; vanilla's Odin/Raiden cleave sfx
                                ;   (btlgfx_main.asm:26054); see Ot6BreakArm
.assert OT6_RVPEND_ELEM = OT6_SHADOW + (14 * 6), error, "reveal-pending must follow the shadow (InitBP clears both in one loop)"
.assert OT6_WALLETPREV + 1 <= OT6_SHADOW + $70 - 1, error, "wallet cur/prev must sit inside InitBP's $70-byte clear"
.assert OT6_COVERPAID = OT6_NUMCTR + 1, error, "cover-earn flag must follow the numeral counter (both live past InitBP's shadow clear)"
.assert OT6_COVERPAID > OT6_SHADOW + $70 - 1, error, "cover-earn flag must sit PAST InitBP's shadow clear (it is cleared by its own store)"
.assert OT6_COVERPAID + 1 <= $ef1f, error, "OT6 shadow tail exceeds the measured-free range ($f120+ is PushMode7Vars')"
.assert OT6_NUMCTR + 1 < OT6_RAGETIER, error, "OT6 rage tier overlaps the numeral counter"
.assert OT6_RAGETIER >= OT6_SHADOW + $70, error, "OT6 rage tier must sit PAST InitBP's shadow clear (it is stored per trance, not per battle)"
.assert OT6_RAGETIER <= $ef1f, error, "OT6 shadow tail exceeds the measured-free range ($f120+ is PushMode7Vars')"
.assert OT6_COVERPAID <> OT6_RAGETIER, error, "cover-earn flag and rage tier collide"
.assert OT6_PIPPEND > OT6_RAGETIER, error, "deferred-pip cell must not collide with the rage tier"
.assert OT6_PIPPEND > OT6_SHADOW + $70 - 1, error, "deferred-pip cell must sit PAST InitBP's shadow clear (InitBP zeroes it explicitly)"
.assert OT6_PIPPEND <= $ef1f, error, "OT6 shadow tail exceeds the measured-free range ($f120+ is PushMode7Vars')"
.assert OT6_BRKLIVE > OT6_PIPPEND, error, "break-flash live flag must not collide with the deferred-pip cell"
.assert OT6_BRKTICK > OT6_BRKLIVE, error, "break-flash state must not collide with its own live flag"
.assert OT6_BRKPAL = OT6_BRKTICK + 12, error, "break-flash palette bank must follow the tick array without overlap"
.assert OT6_BRKTICK > OT6_SHADOW + $70 - 1, error, "break-flash state sits PAST InitBP's shadow clear (Ot6SeedShields zeroes it per slot)"
.assert OT6_BRKPAL + 12 - 1 <= $ef1f, error, "OT6 shadow tail exceeds the measured-free range ($f120+ is PushMode7Vars')"
.assert OT6_RUNICTURNS >= OT6_BRKPAL + 12, error, "runic duration must not collide with the break-flash palette bank"
.assert OT6_RUNICPAID = OT6_RUNICTURNS + 8, error, "the runic earn flag must follow its duration array without overlap"
.assert OT6_RUNICTURNS > OT6_SHADOW + $70 - 1, error, "runic duration sits PAST InitBP's shadow clear (InitBP zeroes it per character)"
.assert OT6_RUNICPAID <= $ef1f, error, "OT6 shadow tail exceeds the measured-free range ($f120+ is PushMode7Vars')"
.assert OT6_RUNICPAID <> OT6_COVERPAID, error, "the runic and cover earn flags must stay separate ledgers (see OT6_RUNICPAID)"
.assert OT6_UNCTL = OT6_RUNICPAID + 1, error, "the uncontrolled flag must follow the runic earn flag without a gap"
.assert OT6_HPMARK = OT6_UNCTL + 1, error, "the hurt line must follow the uncontrolled flag without a gap"
.assert OT6_UNCTL > OT6_SHADOW + $70 - 1, error, "the retaliation cells sit PAST InitBP's shadow clear (InitBP zeroes them explicitly)"
.assert OT6_HPMARK + 8 - 1 <= $ef1f, error, "OT6 shadow tail exceeds the measured-free range ($f120+ is PushMode7Vars')"


.endif
