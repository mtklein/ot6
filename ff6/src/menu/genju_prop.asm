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
; M5 (espers-as-sub-jobs)
;
; Learn rates are all zero.  An equipped esper grants its spells for the
; duration it is worn instead of teaching them permanently: Ot6EsperSpellKnown
; (ot6.asm) resolves an equipped esper's GenjuProp spell-ids as $ff-known while
; ValidateSpellList builds the in-battle Magic list.  IncLearnMagic returns
; immediately on a 0% rate (battle_main.asm:15726), so a zeroed rate is exactly
; "granted while worn, never written into the $1a6e learned table."  The grant
; reads the spell IDs (the odd bytes), which are kept; zeroing the rate does
; not touch them.
;
; Level-up bonuses are all GENJU_BONUS::NONE ($ff).  DoLevelUp bmi-skips a
; negative bonus (battle_main.asm:15821), so vanilla per-level esper stat
; growth is deleted.
;
; Ramuh (esper 0) carries base-tier Bolt (folds to Bolt2/Bolt3 under boost via
; Ot6FoldTbl, ot6.asm) plus Rasp (an MP attack, in no fold family so it
; correctly never folds).  The other espers keep their vanilla spell-ids
; (rates zeroed, bonuses stripped).  An esper's summon (Cmd_19,
; battle_main.asm:3703) is not in this table, and is untouched.
; ------------------------------------------------------------------------------

; 0: ramuh: base-tier Bolt (folds) + Rasp (MP attack)
make_genju_prop {BOLT, 0}, {RASP, 0}, {}, {}, {}

; 1: ifrit.  Base-tier Fire (folds to Fire2/Fire3 under boost via Ot6FoldTbl)
;   plus Drain, which is in no fold family and therefore correctly takes
;   Ot6BoostDmg's x2/x4/x8 multiplier instead.  Drain is non-elemental
;   (magic_prop_en.dat $04, +$01 = $00) and drain-flagged (+$04 bit $02).
;   The vanilla FIRE_2 grant is dropped: a pre-folded tier is a dead,
;   un-foldable row beside the base spell, and it costs 20 MP for what the
;   4 MP base spell delivers under one boost.  Ifrit's third "slot" is the
;   +5 vigor in Ot6EsperStatTbl (ot6_progression.asm).
make_genju_prop {FIRE, 0}, {DRAIN, 0}, {}, {}, {}

; 2: shiva.  Base-tier Ice (folds) + Osmose (the party's only MP income,
;   repriced to 8 MP; see the MagicProp override in battle_main.asm) + Shell.
;   ICE_2 dropped for the same dead-pre-folded-tier reason as Ifrit's FIRE_2.
;   SLOW is not granted here: it rides her re-authored Diamond Dust divine
;   instead (battle_main.asm MagicProp $38).  Boosting Shell does nothing,
;   because it is in no fold family and deals no damage, so Ot6BoostDmg has
;   nothing to multiply.
make_genju_prop {ICE, 0}, {OSMOSE, 0}, {SHELL, 0}, {}, {}

; 3: siren
make_genju_prop {SLEEP, 0}, {MUTE, 0}, {SLOW, 0}, {FIRE, 0}, {}

; 4: terrato
make_genju_prop {QUAKE, 0}, {QUARTR, 0}, {W_WIND, 0}, {}, {}

; 5: shoat.  Break + Doom.  BIO is dropped: it is the pre-folded cap of the
;   poison family (Ot6FoldTbl row 3, ot6_boost.asm:344, a 26 MP dead tier
;   beside a 3 MP fold).  Both spells are power-0 hit-rolled death-class,
;   outside both boost axes: no damage to multiply, no fold row, and no
;   chance-verb certainty mechanism exists for magic.
make_genju_prop {BREAK, 0}, {DOOM, 0}, {}, {}, {}

; 6: maduin.  All three grants are base tiers of fold families (Ot6FoldTbl
;   rows 0-2, ot6_boost.asm:341-343); the vanilla FIRE_2/ICE_2/BOLT_2 row was
;   three dead pre-folded tiers at once.
make_genju_prop {FIRE, 0}, {ICE, 0}, {BOLT, 0}, {}, {}

; 7: bismark.  Haste and Slow both fold party-/field-wide at 1 BP (Ot6FoldTbl
;   rows 6-7, ot6_boost.asm:347-348).  Water lives in his summon (Sea Song
;   $3d, the game's only water verb) because no water-element player spell
;   exists to grant.  LIFE is dropped: the vanilla row put revival on a stone
;   anyone can wear.
make_genju_prop {HASTE, 0}, {SLOW, 0}, {}, {}, {}

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

; 17: kirin, healer kit.  CURE is base-tier: it folds to Cure2/Cure3 under
;   boost via Ot6FoldTbl (ot6.asm), so the vanilla pre-folded CURE_2 grant is
;   dropped -- it would otherwise sit as an un-foldable dead tier beside the
;   foldable Cure.  Regen/Antdot/Scan are in no fold family, so they are
;   already correct as-is.
make_genju_prop {CURE, 0}, {REGEN, 0}, {ANTDOT, 0}, {SCAN, 0}, {}

; 18: zoneseek (optional, Jidoor Auction House).  Rasp, Osmose, and Shell: no
;   fold family touches these three, so all three stand as-is.
make_genju_prop {RASP, 0}, {OSMOSE, 0}, {SHELL, 0}, {}, {}

; 19: carbunkl.  Rflect (nobody else grants it) + Safe.  WARP is field
;   furniture, so it is not granted here.
make_genju_prop {RFLECT, 0}, {SAFE, 0}, {}, {}, {}

; 20: phantom.  Vanish + Demi (halves current HP).  BSERK dropped: it removes
;   player control.
make_genju_prop {VANISH, 0}, {DEMI, 0}, {}, {}, {}

; 21: sraphim (optional, the man in the woods near Tzen).  LIFE folds to
;   Life 2 under boost (Ot6FoldTbl), and CURE folds to Cure 2/Cure 3, so the
;   vanilla pre-folded CURE_2 grant is dropped as a dead un-foldable tier; the
;   foldable CURE covers every tier.
make_genju_prop {LIFE, 0}, {CURE, 0}, {REGEN, 0}, {REMEDY, 0}, {}

; 22: golem (optional, Jidoor Auction House).  Its summon still raises the
;   Earth Wall that soaks physical hits for the party (battle_main $3a81,
;   preserved).  Safe + Stop.  The pre-folded CURE_2 is dropped -- a dead
;   un-foldable tier.
make_genju_prop {SAFE, 0}, {STOP, 0}, {}, {}, {}

; 23: unicorn.  Pearl (its vanilla 40 MP keeps it a decision rather than the
;   default swing) + Remedy.  CURE_2 dropped (dead pre-folded tier).
make_genju_prop {PEARL, 0}, {REMEDY, 0}, {}, {}, {}

; 24: fenrir
make_genju_prop {WARP, 0}, {X_ZONE, 0}, {STOP, 0}, {}, {}

; 25: starlet
make_genju_prop {CURE, 0}, {CURE_2, 0}, {CURE_3, 0}, {REGEN, 0}, {REMEDY, 0}

; 26: phoenix
make_genju_prop {LIFE, 0}, {LIFE_2, 0}, {LIFE_3, 0}, {CURE_3, 0}, {FIRE_3, 0}

; ------------------------------------------------------------------------------
