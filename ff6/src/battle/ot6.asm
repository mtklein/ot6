; ------------------------------------------------------------------------------
; OT6 — Octopath Traveler mechanics module
;
; New code and data live in expanded bank $F0 (segment "ot6_code"), reached
; from vanilla banks via jsl; vanilla-bank edits are minimal hook shims so
; bank $C2 stays under its fixed segment offsets.
;
; per-entity state (unused vanilla battle RAM, zeroed by InitBattle):
;   $3e38,X  current shield points (0 = broken or shieldless)
;   $3e39,X  max shield points
;   $3e88,X  broken timer (nonzero = broken; ticks with status counters)
;   $3e89,X  revealed weakness elements (bitmask, same bits as $3be0)
;   $3e9c,X  characters: boost points (0-5) · monsters: class weaknesses
;   $3e9d,X  characters: pending boost (0-3) · monsters: revealed classes
; entity offsets: $00-$06 characters, $08-$12 monsters. the split $3e9c
; table works because every consumer is entity-gated (cmp #$08) — bp code
; never touches monster rows, class code never touches character rows.
; ------------------------------------------------------------------------------

        .include "ot6_memory.inc"
        .include "ot6_rand.inc"     ; macro only -- emits nothing, segment-agnostic

.segment "ot6_code"

; width discipline: callers vary (battle init calls some hooks with 8-bit
; index registers). every entry point either (a) uses only width-agnostic
; instructions — no index immediates, no pushes — or (b) does php + longi
; and restores. entity-offset checks use tya/cmp (width-neutral), never
; cpy #imm. a-width is 8-bit at every hook site.
.a8
.i16

; ------------------------------------------------------------------------------
        .include "ot6_codex.asm"
        .include "ot6_break.asm"
        .include "ot6_icons.asm"
        .include "ot6_boost.asm"
; bank $f0 is laid out by emission order, so this list's order is load-bearing:
; reordering these includes moves every symbol after the swap.
        .include "ot6_bushido.asm"      ; cyan: boost -> tech, battle side
        .include "ot6_divine.asm"       ; oblivion + assassinate, resolution gates
        .include "ot6_cmdmenu.asm"      ; blitz/tools/dance/bushido battle submenus
        .include "ot6_loadout.asm"      ; bushido field configurator + row prices
        .include "ot6_boostdmg.asm"     ; the damage-verb half of the boost canon
        .include "ot6_steal.asm"        ; locke: boost on the steal roll
        .include "ot6_slot.asm"         ; setzer: boost-tiered reels
        .include "ot6_rage.asm"         ; gau: rage loadout, page, and coin
        .include "ot6_lore.asm"         ; strago: lore loadout + mask
        .include "ot6_cover.asm"        ; true knight: a cover pays a boost point
        .include "ot6_thief.asm"        ; locke: steal submenu, filch, bestow
        .include "ot6_hud.asm"
        .include "ot6_progression.asm"

; weapon/ability class data (m3)
        .include "ot6_class.asm"

; multi-hit hit counts, appended after the block above rather than inserted
; into it, so no existing symbol in bank $f0 moves.
        .include "ot6_hitcount.asm"
