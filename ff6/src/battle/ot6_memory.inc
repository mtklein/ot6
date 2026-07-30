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

; #40 (kit-gau.md §4): Gau's 8-slot rage loadout, one byte per slot, in the
; NEXT eight bytes of the same save-block scrap the Bushido word lives in.
; byte = rage id + 1; $00 = unset; all eight zero = AUTO (the first eight
; known rages in id order -- the head of the vanilla list).  Rage ids run
; 0..254 (InitSkills stops at $fe, LearnRage skips monster index > 255), so
; +1 fits a byte with nothing real outside it.
;
; NO persistent_layout BUMP, and that is a ruling, not an oversight: the
; string ot6-codex-o8-v1 was coined for a world that already contained the
; Bushido word, whose own precedent is exactly this -- a zero-sentinel
; addition to save-block scraps changes no existing byte's meaning, so no
; tracked anchor can be misread.  All 11 tracked anchors hold zeros here
; (kit-gau.md §4.2, measured), and zeros decode as AUTO, the state those
; saves are genuinely in.  Remaining scrap after this: $1e27-$1e3f.
OT6_RAGELOAD         := $7e1e1f
OT6_RAGESLOTS        = 8
; The configurator's page GEOMETRY, shared by the C3 draw and the F0 cursor
; walk so they can never disagree about which slot a row is.  Two columns of
; four, because the EN field-menu window fits exactly EIGHT text rows (the
; 12px cadence -- see field_menu.asm's Ot6RageDrawSlots header) and a single
; column of eight would leave no row for the title or the LEARNED count.  It
; is also vanilla's own shape for this very window: the rage browse is
; `cursor_prop {0,0}, {2,8}` at 12px pitch (skills.asm:281-299).
OT6_RAGECOLS         = 2
OT6_RAGEROWS         = 4
.assert OT6_RAGECOLS * OT6_RAGEROWS = OT6_RAGESLOTS, error, "rage page geometry must cover every slot exactly once"
.assert (OT6_RAGELOAD & $ffff) >= $1600, error, "rage loadout must sit inside the save block"
.assert (OT6_RAGELOAD & $ffff) + OT6_RAGESLOTS - 1 <= $1ffd, error, "rage loadout must sit inside the checksum window"
.assert (OT6_RAGELOAD & $ffff) = (OT6_LOADOUT & $ffff) + 2, error, "rage loadout must follow the bushido word without a gap"

; Battle-only scratch. InitBattle clears through $3ed3. OT6_DIVINE_USED is
; one per-character bitmask; the walkers use the interleaved even words.
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
OT6_SLOTTIER         := $57ba   ; Slot's latched boost tier (#31 backfill):
                                ;   written at the spin's first A press by
                                ;   Ot6SlotRig, re-banked into
                                ;   OT6_BOOST_REVEALED by Ot6SlotCommit so
                                ;   Ot6ActionEnd charges what the reels
                                ;   delivered (ot6_slot.asm, the Slot strip)
OT6_PIPTAIL          := $57bb   ; #33: frames of live pip painting left after
                                ;   an ActionEnd with the battle menu closed
                                ;   -- keeps the charge visible on its own
                                ;   frame.  set by Ot6ActionEnd (characters),
                                ;   decremented by Ot6PipStage, cleared by
                                ;   InitBP (init-exempt strip: power-on junk
                                ;   would paint pips over the intro).
OT6_RANDPEND         := $57bc
OT6_RANDBTL          := $57bd
OT6_HUDVEIL          := $57be
OT6_SCRIPTBUSY       := $57bf
OT6_SPECIES          := $57c0
OT6_PIPCUR           := $57cc   ; live pip cell (0 = off); #33 keeps the
OT6_PIPPREV          := $57ce   ;   one-cell footprint and moves only WHICH
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
; #33 pending reveals: a chip banks its newly-revealed weakness bits here at
; damage-CALC time; Ot6RevealCommit moves them into OT6_REVEALED_ELEM /
; monster OT6_BOOST_REVEALED (and every same-species slot) on the DAMAGE
; frame (the first numeral display, GfxCmd_0b), with Ot6ActionEnd as the
; no-numeral backstop.  One byte per monster slot, stride 2 (indexed by the
; slot offset 0,2..10 like $3e91/$3ea5; odd bytes unused).  Cleared by
; InitBP's shadow clear and per-slot by Ot6SeedShields (Cmd_20 reloads).
OT6_RVPEND_ELEM      := $ed45   ; 12 bytes
OT6_RVPEND_CLS       := $ed51   ; 12 bytes
; #35 wallet pseudo-line: current-MP display painted into the open costed
; list window every nmi.  CUR/PREV are the first cell's vram word address
; (0 = off; prev != cur blanks the old cells one-shot), CELLS the staged
; glyph|attr words.  CUR/PREV cleared by InitBP's extended shadow clear.
OT6_WALLETCUR        := $ed5d
OT6_WALLETPREV       := $ed5f
OT6_WALLET_W         = 5        ; [M][P][hundreds][tens][ones]
OT6_WALLETCELLS      := $ed61   ; OT6_WALLET_W words
OT6_WALLETSIG        := $ed6d   ; staged MP value; the flush repaints only
OT6_WALLETSIGP       := $ed6f   ;   when CUR or SIG moves (see the flush)
OT6_PIPSLOT          := $ed6b   ; #33: the character slot the live pip cell
                                ;   follows while OT6_PIPTAIL runs -- the one
                                ;   who just spent BP (Ot6ActionEnd sets both)
; The wallet's five glyph|attr words are written UNROLLED (OT6_WALLETCELLS+0
; through +9, ot6_hud.asm:1474-1516), so nothing in the code ever mentions the
; width -- which is exactly how OT6_WALLET_W ended up a comment-only symbol,
; and how a sixth cell could be added there without anyone noticing that the
; run ends flush against OT6_PIPSLOT with zero slack.  This is the check that
; would have said so.  Equality is the current, intended fit ($ed61 + 10 =
; $ed6b), so the bound is <=, not <.
.assert OT6_WALLETCELLS + OT6_WALLET_W * 2 <= OT6_PIPSLOT, error, "OT6 wallet cells run into OT6_PIPSLOT"
OT6_RAGETIER         := $ed73   ; #40: the boost tier latched at Cmd_10 for the
                                ;   whole trance (Slot's OT6_SLOTTIER pattern at
                                ;   longer range -- BP is spent once at the
                                ;   Rage-start action but the tier must outlive
                                ;   it).  kit-gau.md §6.1 proposed $57bb, but
                                ;   #33 took that for OT6_PIPTAIL and $57d5+ is
                                ;   vanilla's own name scratch (btlgfx_ram.inc:
                                ;   ram_res w7e57d5,128), so the strip is full;
                                ;   this lives in the measured-free shadow tail
                                ;   instead, past InitBP's $70-byte clear.
                                ;   Staleness is harmless by Slot's argument:
                                ;   read only while a RAGE status is set, and
                                ;   the only writer of that status (Cmd_10)
                                ;   always rewrites the latch first.
OT6_NUMCTR           := $ed71   ; #33: last-seen damage-numeral thread counter
                                ;   ($632e).  a change means GfxCmd_0b just
                                ;   allocated a numeral -- the damage frame --
                                ;   and Ot6RevealPoll commits pending reveals.
                                ;   past InitBP's clear on purpose: a stale
                                ;   value costs one no-op commit (see the proc)
OT6_COVERPAID        := $ed72   ; #37: per-character bitmask (----1234, the
                                ;   OT6_DIVINE_USED / $3f2f shape) -- bit set =
                                ;   that character's True Knight cover has
                                ;   already banked its BP this ROUND.  set by
                                ;   Ot6CoverBP, cleared per character by
                                ;   Ot6ActionEnd (the round boundary) and
                                ;   wholesale by InitBP.  unlike NUMCTR a stale
                                ;   value here would SUPPRESS a real earn, so
                                ;   it is init-cleared explicitly.
OT6_PIPPEND          := $ed74   ; #42: a DEFERRED pip paint -- character slot
                                ;   + 1 (0 = nothing pending).  Ot6CoverBP
                                ;   banks the blocker here at the cover commit
                                ;   instead of arming OT6_PIPSLOT/OT6_PIPTAIL
                                ;   directly, because that commit precedes the
                                ;   damage numeral by 83-147 frames while the
                                ;   tail is 32 -- the pip flashed and faded
                                ;   two seconds BEFORE the block visibly
                                ;   landed.  Ot6PipPending (ot6_hud.asm) moves
                                ;   it into the live cell on the numeral frame,
                                ;   exactly as Ot6RevealCommit/Ot6RevealPoll do
                                ;   for weakness reveals.  A stale value would
                                ;   paint a spurious pip on the first numeral
                                ;   of the next battle, so InitBP clears it.
; #48: the break flash.  ONE byte per monster slot, stride 2 and indexed by
; the slot offset 0,2..10 exactly like OT6_RVPEND_* (so a chip holding the
; ENTITY offset in y writes OT6_BRKTICK-8,y and the walkers read
; OT6_BRKTICK,y); odd bytes unused.  The byte is a small state machine:
;   $00        idle
;   $ff        PENDING -- the shields emptied at damage CALC and the flash is
;              waiting for the damage frame (Ot6BreakArm, off Ot6RevealPoll's
;              numeral edge / Ot6ActionEnd's backstop, the OT6_PIPPEND shape)
;   1..$18     a live flash, counting down one per main-loop frame
; OT6_BRKPAL banks the monster's own sprite-palette bits (w7e80db & $0e) for
; the frame the flash hands the sprite back.
; Both live PAST InitBP's shadow clear, so power-on junk is possible; every
; reader is gated on the monster being present ($3aa8) and Ot6SeedShields
; zeroes both per slot at every seed (fresh battle AND Cmd_20 reload), which
; is the same clearing contract OT6_RVPEND_* already runs on.
; OT6_BRKLIVE gates the per-frame painter, and it is not an optimisation --
; it is the fix for a measured regression, and the measurement is worth more
; than the feature.  Ot6BreakFlash first walked all six monster slots every
; main-loop frame.  That stretched the True Knight fixture's fight by 10%:
; battle_trueknight's "two more covers in the same round" went 1635 -> 1798
; frames for an IDENTICAL outcome (3 covers, bank 2, one bank write), which
; flipped its 6a assertion from the numeral frame to Ot6ActionEnd's backstop.
;
; Eight builds to pin it, and the first four conclusions were all wrong:
;   painter disabled ................................. 1635  (pass)
;   painter walks, sprite writes suppressed .......... 1798
;   painter walks, EVERY store suppressed ............ 1798   -> not the writes
;   painter early-outs on this flag, `jsr` retained .. 1798   -> not the walk
;   CONTROL: 12 bare NOPs here, no OT6 feature ....... 1635  (pass)
;   CONTROL: 80 bare NOPs here, no OT6 feature ....... 1798   -> not the feature
;   inline gate at the call site, 8 cycles idle ...... 1635  (pass)
; So the cause is neither writes, nor memory, nor this feature: WHAT COSTS IS
; CYCLES SPENT IN Ot6BgHud_ext, AND THE MARGIN IS BETWEEN 12 AND 80 OF THEM.
; That site runs from WaitFrame, after WaitVblank returns, once per battle
; frame (btlgfx_main.asm:432-445), and the battle loop's per-iteration budget
; is close enough to full that a hair over it makes WaitVblank miss and the
; whole iteration costs an extra hardware frame.  The penalty saturates --
; 20 cycles and 110 cycles both cost exactly 163 frames -- which is what a
; near-zero-slack set of frames looks like.  #33's NMI lesson said the same
; thing about vblank TRANSFERS; this says it about plain CPU time.
;
; [ SCOPE, re-measured 2026-07-30 on v0.9 -- issue #67.  Read this before
;   citing the paragraph above as a bank-wide rule. ]
;
; 8d8a570 ran the same bare-NOP control in bank $C2's ACTION path (five NOPs
; before `jsr CheckRetal`, battle_main.asm:3146), saw 1635 -> 1798, and
; concluded that $C2's battle path could not grow at all.  That conclusion is
; RETRACTED.  Re-run on v0.9, the identical control comes back:
;   five NOPs in the $C2 action path ................ 1635  (pass) -- every
;                                                       frame number in the run
;                                                       byte-identical to clean
;   80 NOPs in Ot6BgHud_ext ......................... 1798   -> still over
; The original observation is left on the record because it was honestly
; measured and it did block work for a day; what changed underneath it was
; not investigated.
;
; Independent evidence pointing the same way: the v0.9 merge added ~49 bytes
; of $C2 across four new call sites -- battle_main.asm:514 (Ot6RunicHold, in
; QueueAction), :3409 (Ot6ThiefExec, Cmd_05), :4152 (Ot6RunicRaise, Cmd_0b),
; :14652 (Ot6FoldPrices, UpdateEnabledMagic), plus Ot6RecheckMagic at :14715
; -- with battle_trueknight unmoved at 1635 and no partial degradation.
;
; HYPOTHESIS, UNVERIFIED: what costs is per-battle-FRAME code, not per-ACTION
; or per-menu-redraw code.  Every v0.9 hook above runs once per action or per
; redraw; Ot6BgHud_ext runs from WaitFrame every battle frame.  That is
; consistent with everything measured and with the WaitFrame mechanism above,
; and it is still only consistent-with -- NOBODY has run the NOP control at
; those four v0.9 sites, which is the experiment that would settle it.
;
; So the standing rule is "no growth in the ONCE-PER-BATTLE-FRAME path", not
; "no growth in $C2", and battle_trueknight asserts it in those words now
; (phase 4b) instead of through a pip-delivery assertion that could not tell
; the two apart.  The safe budget is PER SITE, and the only site with a
; measured number is this one.
;
; Hence the gate is INLINE at the call site (ot6_hud.asm): even a `jsr` into
; a proc that early-outs was over the line.  Nonzero = at least one slot has
; a live countdown; the painter recomputes it as it walks, so a stale value
; costs exactly one walk and the byte needs no init clear.
OT6_BRKLIVE          := $ed75
OT6_BRKTICK          := $ed76   ; 12 bytes
OT6_BRKPAL           := $ed82   ; 12 bytes
; #59: boosted Runic.  ON REACTIVE VERBS, BOOST BUYS DURATION (DESIGN.md), and
; Runic is the first instance -- so the stance needs a lifetime, which vanilla
; never gave it (its stance is one bit that dies on the first absorb or on
; Celes's next action, battle_main.asm:8671 and :511).
;
; TURNS, one byte per character, stride 2 and indexed by the ENTITY offset
; (0/2/4/6) like OT6_BP_CLASS -- Ot6RunicRaise latches the pending boost here
; at Cmd_0b, Ot6RunicHold decrements it at each of her QueueActions and puts
; the stance bit back, and 0 means "vanilla Runic": one absorb, then gone.
; The odd bytes are unused.  It is a TURN count and not an absorb count
; deliberately: a turn count is legible to the player ("three turns of
; shield") and it also BOUNDS the BP earn by construction, since the earn is
; capped at one per round.  Cleared per character by InitBP -- it sits past
; the shadow clear, and a stale value would hand the next battle a phantom
; standing stance, which is a mechanic and not a cosmetic.
OT6_RUNICTURNS       := $ed8e   ; 8 bytes (4 characters, stride 2)
; #59: the once-per-round absorb-earn latch -- a per-character bitmask
; (----1234, the OT6_COVERPAID / $3f2f shape).  Bit set = that character's
; Runic has already banked its BP this ROUND.
;
; A SEPARATE BYTE FROM OT6_COVERPAID, deliberately.  #37's cover latch has the
; identical shape and four spare high bits, and sharing them was weighed: the
; two are different verbs with different prices -- Runic costs a turn, a True
; Knight cover costs a relic slot and nothing else -- so one shared latch
; would make equipping True Knight silently tax Celes's Runic earn, an
; interaction nobody asked for and nobody would find.  One rule ("a reactive
; earn is once per round"), two ledgers.
OT6_RUNICPAID        := $ed96
OT6_BREAK_FLASH      = $18      ; 24 frames: three 4-frame pulses (see
                                ;   Ot6BreakFlash's `and #$04` cadence)
OT6_BREAK_SFX        = $be      ; vanilla's Odin/Raiden cleave sfx
                                ;   (btlgfx_main.asm:26054) -- see Ot6BreakArm
.assert OT6_RVPEND_ELEM = OT6_SHADOW + (14 * 6), error, "reveal-pending must follow the shadow (InitBP clears both in one loop)"
.assert OT6_WALLETPREV + 1 <= OT6_SHADOW + $70 - 1, error, "wallet cur/prev must sit inside InitBP's $70-byte clear"
.assert OT6_COVERPAID = OT6_NUMCTR + 1, error, "cover-earn latch must follow the numeral counter (both live past InitBP's shadow clear)"
.assert OT6_COVERPAID > OT6_SHADOW + $70 - 1, error, "cover-earn latch must sit PAST InitBP's shadow clear (it is cleared by its own store)"
.assert OT6_COVERPAID + 1 <= $ef1f, error, "OT6 shadow tail exceeds the measured-free range ($f120+ is PushMode7Vars')"
.assert OT6_NUMCTR + 1 < OT6_RAGETIER, error, "OT6 rage tier overlaps the numeral counter"
.assert OT6_RAGETIER >= OT6_SHADOW + $70, error, "OT6 rage tier must sit PAST InitBP's shadow clear (it is latched per trance, not per battle)"
.assert OT6_RAGETIER <= $ef1f, error, "OT6 shadow tail exceeds the measured-free range ($f120+ is PushMode7Vars')"
; #40 and #37 allocated out of the same measured-free shadow tail in
; parallel worktrees and could not see each other.  They landed adjacent
; and disjoint -- but nothing said so until this assert, which is exactly
; the check a concurrent allocation needs.
.assert OT6_COVERPAID <> OT6_RAGETIER, error, "cover-earn latch and rage tier collide"
.assert OT6_PIPPEND > OT6_RAGETIER, error, "deferred-pip cell must not collide with the rage tier"
.assert OT6_PIPPEND > OT6_SHADOW + $70 - 1, error, "deferred-pip cell must sit PAST InitBP's shadow clear (InitBP zeroes it explicitly)"
.assert OT6_PIPPEND <= $ef1f, error, "OT6 shadow tail exceeds the measured-free range ($f120+ is PushMode7Vars')"
.assert OT6_BRKLIVE > OT6_PIPPEND, error, "break-flash live flag must not collide with the deferred-pip cell"
.assert OT6_BRKTICK > OT6_BRKLIVE, error, "break-flash state must not collide with its own live flag"
.assert OT6_BRKPAL = OT6_BRKTICK + 12, error, "break-flash palette bank must follow the tick array without overlap"
.assert OT6_BRKTICK > OT6_SHADOW + $70 - 1, error, "break-flash state sits PAST InitBP's shadow clear (Ot6SeedShields zeroes it per slot)"
.assert OT6_BRKPAL + 12 - 1 <= $ef1f, error, "OT6 shadow tail exceeds the measured-free range ($f120+ is PushMode7Vars')"
.assert OT6_RUNICTURNS >= OT6_BRKPAL + 12, error, "runic duration must not collide with the break-flash palette bank"
.assert OT6_RUNICPAID = OT6_RUNICTURNS + 8, error, "the runic earn latch must follow its duration array without overlap"
.assert OT6_RUNICTURNS > OT6_SHADOW + $70 - 1, error, "runic duration sits PAST InitBP's shadow clear (InitBP zeroes it per character)"
.assert OT6_RUNICPAID <= $ef1f, error, "OT6 shadow tail exceeds the measured-free range ($f120+ is PushMode7Vars')"
.assert OT6_RUNICPAID <> OT6_COVERPAID, error, "the runic and cover earn latches must stay separate ledgers (see OT6_RUNICPAID)"


.endif
