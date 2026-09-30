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
; correctly never folds).  Every World of Balance stone grants its planned
; list: docs/design/magicite.md's roster table, with magicite-ifrit-shiva.md
; for Ifrit and Shiva and magicite-tube-six.md for the tube room's six.  The
; twelve World of Ruin stones grant the lists in magicite.md's "World of Ruin
; Espers" table, in the order written there (#327).  No row grants a higher
; tier (#305); tools/check_spell_grants.py checks both.  An esper's summon
; (Cmd_19, battle_main.asm:3703) is not in this table, and is untouched.
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

; 3: siren.  Mute, Sleep: the planned list (docs/design/magicite.md's WoB roster table, "the
;   controller job").  Vanilla's Slow and the leftover Fire are not in it.
make_genju_prop {MUTE, 0}, {SLEEP, 0}, {}, {}, {}

; 4: terrato, "the Landslide" (magicite.md's World of Ruin table).  Quake hits
;   every body on the field that does not float; Quartr is the enemy-only
;   fraction.  Vanilla's W Wind moves to Bahamut.
make_genju_prop {QUAKE, 0}, {QUARTR, 0}, {}, {}, {}

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

; 8: stray.  Muddle, Imp: the planned list (docs/design/magicite.md's WoB roster table, "the
;   trickster job").  Vanilla's Float is not in it.
make_genju_prop {MUDDLE, 0}, {IMP, 0}, {}, {}, {}

; 9: palidor, "the Tailwind".  Float (its own verb) and Slow (folds to Slow 2).
;   Vanilla's Haste is on three other sources, and Haste2/Slow 2 are tiers.
make_genju_prop {FLOAT, 0}, {SLOW, 0}, {}, {}, {}

; 10: tritoch, "the second caster".  Ice and Bolt (a second copy of the caster
;   job for a split party) and Poison in place of Fire; all three fold.
make_genju_prop {ICE, 0}, {BOLT, 0}, {POISON, 0}, {}, {}

; 11: odin, "the Warlord".  Meteor, and Bserk: Odin's berserkers, a fighter's
;   stone that turns an enemy caster into a brawler.
make_genju_prop {METEOR, 0}, {BSERK, 0}, {}, {}, {}

; 12: raiden, "the Warlord, ascended".  Raiden replaces Odin (take_genju ODIN,
;   give_genju RAIDEN), so it keeps Odin's list and adds Quick.
make_genju_prop {METEOR, 0}, {BSERK, 0}, {QUICK, 0}, {}, {}

; 13: bahamut, "the Dragon King".  Flare, and W Wind (the wingbeat).
make_genju_prop {FLARE, 0}, {W_WIND, 0}, {}, {}, {}

; 14: alexandr, "the Bastion".  Dispel, Safe, Shell.  Vanilla's Pearl and Remedy
;   are Unicorn's job.
make_genju_prop {DISPEL, 0}, {SAFE, 0}, {SHELL, 0}, {}, {}

; 15: crusader, "the Capstone".  Merton, Meteor.
make_genju_prop {MERTON, 0}, {METEOR, 0}, {}, {}, {}

; 16: ragnarok, "the Last Word".  Ultima to end a fight, or Warp to leave it.
make_genju_prop {ULTIMA, 0}, {WARP, 0}, {}, {}, {}

; 17: kirin.  Cure, Regen: the planned list (docs/design/magicite.md's WoB roster table, "the
;   medic job").  Cure folds to Cure 2/Cure 3 under boost (Ot6FoldTbl).
;   Vanilla's Antdot and Scan are not in it.
make_genju_prop {CURE, 0}, {REGEN, 0}, {}, {}, {}

; 18: zoneseek (optional, Jidoor Auction House).  Shell, Haste: the planned
;   list (docs/design/magicite.md's WoB roster table, "the abjurer").
make_genju_prop {SHELL, 0}, {HASTE, 0}, {}, {}, {}

; 19: carbunkl.  Rflect (nobody else grants it) + Safe.  WARP is field
;   furniture, so it is not granted here.
make_genju_prop {RFLECT, 0}, {SAFE, 0}, {}, {}, {}

; 20: phantom.  Vanish + Demi (halves current HP).  BSERK dropped: it removes
;   player control.
make_genju_prop {VANISH, 0}, {DEMI, 0}, {}, {}, {}

; 21: sraphim (optional, the man in the woods near Tzen).  Cure, Life: the
;   planned list (docs/design/magicite.md's WoB roster table, "the white-mage job").  Both fold
;   under boost (Cure 2/Cure 3, Life 2/Life 3).
make_genju_prop {CURE, 0}, {LIFE, 0}, {}, {}, {}

; 22: golem (optional, Jidoor Auction House).  The planned list is "Safe,
;   Protect-alike" (docs/design/magicite.md's WoB roster table, "the wall job").  FF6 has
;   no Protect spell beyond Safe itself, so only Safe is granted; the summon
;   still raises the Earth Wall that soaks physical hits for the party
;   (battle_main $3a81, preserved).
make_genju_prop {SAFE, 0}, {}, {}, {}, {}

; 23: unicorn.  Pearl (its vanilla 40 MP keeps it a decision rather than the
;   default swing) + Remedy.  CURE_2 dropped (dead pre-folded tier).
make_genju_prop {PEARL, 0}, {REMEDY, 0}, {}, {}, {}

; 24: fenrir, "the Banisher".  Stop and X-Zone.  Vanilla's Warp moves to
;   Ragnarok.
make_genju_prop {STOP, 0}, {X_ZONE, 0}, {}, {}, {}

; 25: starlet, "the second medic".  Cure (folds to Cure 2/Cure 3), Regen,
;   Remedy: a medic for the second party of a split.
make_genju_prop {CURE, 0}, {REGEN, 0}, {REMEDY, 0}, {}, {}

; 26: phoenix, "the Rebirth".  Life, which boosts to Life 2 and Life 3
;   (Ot6FoldTbl, #327), so Life 2 and Life 3 are tiers and not granted; and
;   Antdot.
make_genju_prop {LIFE, 0}, {ANTDOT, 0}, {}, {}, {}

; ------------------------------------------------------------------------------
