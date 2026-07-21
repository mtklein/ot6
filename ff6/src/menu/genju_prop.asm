; ------------------------------------------------------------------------------

.export GenjuProp

; ------------------------------------------------------------------------------

.mac make_genju_spell spell_id, spell_rate
        .byte spell_rate, ATTACK::spell_id
.endmac

.mac make_genju_prop spell1, spell2, spell3, spell4, spell5, bonus
        .ifnblank spell1
                make_genju_spell spell1
        .else
                make_genju_spell NONE, 0
        .endif
        .ifnblank spell2
                make_genju_spell spell2
        .else
                make_genju_spell NONE, 0
        .endif
        .ifnblank spell3
                make_genju_spell spell3
        .else
                make_genju_spell NONE, 0
        .endif
        .ifnblank spell4
                make_genju_spell spell4
        .else
                make_genju_spell NONE, 0
        .endif
        .ifnblank spell5
                make_genju_spell spell5
        .else
                make_genju_spell NONE, 0
        .endif
        .ifnblank bonus
                .byte GENJU_BONUS::bonus
        .else
                .byte GENJU_BONUS::NONE
        .endif
.endmac

; ------------------------------------------------------------------------------

.segment "genju_prop"

; d8/6e00
GenjuProp:

; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------
; M5 (espers-as-sub-jobs) -- FORK-INDEPENDENT DATA
;
; LEARN RATES ARE ALL ZERO.  Under M5 an equipped esper GRANTS its spells for
; the duration it is worn instead of teaching them permanently: Ot6EsperSpellKnown
; (ot6.asm) resolves an equipped esper's GenjuProp spell-ids as $ff-known while
; ValidateSpellList builds the in-battle Magic list.  IncLearnMagic returns
; immediately on a 0% rate (battle_main.asm:15726), so a zeroed rate is exactly
; "granted while worn, never written into the $1a6e learned table."  The grant
; reads the spell IDs (the odd bytes), which are kept -- zeroing the rate does
; not touch them.  This is correct under both the augment and replace readings
; of the fork: both keep the additive grant; replace only ADDS innate suppression
; later.
;
; LEVEL-UP BONUSES ARE ALL GENJU_BONUS::NONE ($ff).  DoLevelUp bmi-skips a
; negative bonus (battle_main.asm:15821), so vanilla per-level esper stat growth
; is deleted.  Correct under every pending stat-layer option -- v0.4's decision
; is "not the vanilla level-up mechanism."  The replacement stat/passive layer is
; a separate, still-pending fork.
;
; Ramuh (esper 0) is re-authored to its M5 proof shape: BASE-TIER Bolt (folds to
; Bolt2/Bolt3 under boost via Ot6FoldTbl, ot6.asm) plus Rasp (an MP attack, in no
; fold family so it correctly never folds).  Ramuh is the Zozo reward the subjob
; test drives.  The other espers keep their vanilla spell-ids for now (rates
; zeroed, bonuses stripped); re-authoring their grant lists to base-tier shapes
; is a data-append for when the augment/replace and stat-layer forks land.  An
; esper's SUMMON (Cmd_19, battle_main.asm:3703) is not in this table -- untouched.
; ------------------------------------------------------------------------------

; 0: ramuh -- M5 proof esper: base-tier Bolt (folds) + Rasp (MP attack)
make_genju_prop {BOLT, 0}, {RASP, 0}, {}, {}, {}

; 1: ifrit
make_genju_prop {FIRE, 0}, {FIRE_2, 0}, {DRAIN, 0}, {}, {}

; 2: shiva
make_genju_prop {ICE, 0}, {ICE_2, 0}, {RASP, 0}, {OSMOSE, 0}, {CURE, 0}

; 3: siren
make_genju_prop {SLEEP, 0}, {MUTE, 0}, {SLOW, 0}, {FIRE, 0}, {}

; 4: terrato
make_genju_prop {QUAKE, 0}, {QUARTR, 0}, {W_WIND, 0}, {}, {}

; 5: shoat
make_genju_prop {BIO, 0}, {BREAK, 0}, {DOOM, 0}, {}, {}

; 6: maduin
make_genju_prop {FIRE_2, 0}, {ICE_2, 0}, {BOLT_2, 0}, {}, {}

; 7: bismark
make_genju_prop {FIRE, 0}, {ICE, 0}, {BOLT, 0}, {LIFE, 0}, {}

; 8: stray
make_genju_prop {MUDDLE, 0}, {IMP, 0}, {FLOAT, 0}, {}, {}

; 9: palidor
make_genju_prop {HASTE, 0}, {SLOW, 0}, {HASTE2, 0}, {SLOW_2, 0}, {FLOAT, 0}

; 10: tritoch
make_genju_prop {FIRE_3, 0}, {ICE_3, 0}, {BOLT_3, 0}, {}, {}

; 11: odin
make_genju_prop {METEOR, 0}, {}, {}, {}, {}

; 12: raiden
make_genju_prop {QUICK, 0}, {}, {}, {}, {}

; 13: bahamut
make_genju_prop {FLARE, 0}, {}, {}, {}, {}

; 14: alexandr
make_genju_prop {PEARL, 0}, {SHELL, 0}, {SAFE, 0}, {DISPEL, 0}, {REMEDY, 0}

; 15: crusader
make_genju_prop {MERTON, 0}, {METEOR, 0}, {}, {}, {}

; 16: ragnarok
make_genju_prop {ULTIMA, 0}, {}, {}, {}, {}

; 17: kirin
make_genju_prop {CURE, 0}, {CURE_2, 0}, {REGEN, 0}, {ANTDOT, 0}, {SCAN, 0}

; 18: zoneseek
make_genju_prop {RASP, 0}, {OSMOSE, 0}, {SHELL, 0}, {}, {}

; 19: carbunkl
make_genju_prop {RFLECT, 0}, {HASTE, 0}, {SHELL, 0}, {SAFE, 0}, {WARP, 0}

; 20: phantom
make_genju_prop {BSERK, 0}, {VANISH, 0}, {DEMI, 0}, {}, {}

; 21: sraphim
make_genju_prop {LIFE, 0}, {CURE_2, 0}, {CURE, 0}, {REGEN, 0}, {REMEDY, 0}

; 22: golem
make_genju_prop {SAFE, 0}, {STOP, 0}, {CURE_2, 0}, {}, {}

; 23: unicorn
make_genju_prop {CURE_2, 0}, {REMEDY, 0}, {DISPEL, 0}, {SAFE, 0}, {SHELL, 0}

; 24: fenrir
make_genju_prop {WARP, 0}, {X_ZONE, 0}, {STOP, 0}, {}, {}

; 25: starlet
make_genju_prop {CURE, 0}, {CURE_2, 0}, {CURE_3, 0}, {REGEN, 0}, {REMEDY, 0}

; 26: phoenix
make_genju_prop {LIFE, 0}, {LIFE_2, 0}, {LIFE_3, 0}, {CURE_3, 0}, {FIRE_3, 0}

; ------------------------------------------------------------------------------
