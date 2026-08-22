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
; M5 (espers-as-sub-jobs): fork-independent data
;
; Learn rates are all zero.  Under M5 an equipped esper grants its spells for
; the duration it is worn instead of teaching them permanently: Ot6EsperSpellKnown
; (ot6.asm) resolves an equipped esper's GenjuProp spell-ids as $ff-known while
; ValidateSpellList builds the in-battle Magic list.  IncLearnMagic returns
; immediately on a 0% rate (battle_main.asm:15726), so a zeroed rate is exactly
; "granted while worn, never written into the $1a6e learned table."  The grant
; reads the spell IDs (the odd bytes), which are kept; zeroing the rate does
; not touch them.  This is correct under both the augment and replace readings
; of the fork: both keep the additive grant, and replace only adds innate
; suppression later.
;
; Level-up bonuses are all GENJU_BONUS::NONE ($ff).  DoLevelUp bmi-skips a
; negative bonus (battle_main.asm:15821), so vanilla per-level esper stat growth
; is deleted.  Correct under every pending stat-layer option -- v0.4's decision
; is "not the vanilla level-up mechanism."  The replacement stat/passive layer is
; a separate, still-pending fork.
;
; Ramuh (esper 0) is re-authored to its M5 test shape: base-tier Bolt (folds to
; Bolt2/Bolt3 under boost via Ot6FoldTbl, ot6.asm) plus Rasp (an MP attack, in no
; fold family so it correctly never folds).  Ramuh is the Zozo reward the subjob
; test drives.  The other espers keep their vanilla spell-ids for now (rates
; zeroed, bonuses stripped); re-authoring their grant lists to base-tier shapes
; is a data-append for when the augment/replace and stat-layer forks land.  An
; esper's summon (Cmd_19, battle_main.asm:3703) is not in this table, and is
; untouched.
; ------------------------------------------------------------------------------

; 0: ramuh: M5 test esper, base-tier Bolt (folds) + Rasp (MP attack)
make_genju_prop {BOLT, 0}, {RASP, 0}, {}, {}, {}

; 1: ifrit, "the Furnace" (v0.6, magicite-ifrit-shiva.md §4).  The fighter's
;   stone: weight rather than an element button.  Base-tier Fire (folds to
;   Fire2/Fire3
;   under boost via Ot6FoldTbl) plus Drain, which is in no fold family and
;   therefore correctly takes Ot6BoostDmg's x2/x4/x8 multiplier instead.  Drain
;   is non-elemental (magic_prop_en.dat $04, +$01 = $00) and drain-flagged
;   (+$04 bit $02), so it is the half of this kit that works on every machine in
;   the Magitek Research Facility, where fire is absorbed by the Right Crane
;   and is correct against one trash species (§2.2, §2.5).
;   The vanilla FIRE_2 grant is dropped for the Kirin reason: a pre-folded tier
;   is a dead, un-foldable row beside the base spell, and it costs 20 MP for
;   what the 4 MP base spell delivers under one boost.
;   Two spells is deliberate (the Ramuh precedent); Ifrit's third "slot" is
;   the +5 vigor in Ot6EsperStatTbl (ot6_progression.asm).  Bserk is the
;   reserved third candidate, held back because it removes player control.
;   Poison/Bio stays Edgar's authored key; Cure stays Kirin's.
make_genju_prop {FIRE, 0}, {DRAIN, 0}, {}, {}, {}

; 2: shiva, "the Rime" (v0.6, magicite-ifrit-shiva.md §5).  The caster's
;   stone: economy.  Base-tier Ice (folds) + Osmose (the party's only MP income,
;   repriced to 8 MP; see the MagicProp override in battle_main.asm) + Shell
;   (three of the Facility's four remaining boss fights answer to magic
;   mitigation and nobody in the party has any; Celes's Safe is L22 and is
;   physical).  ICE_2 dropped for the same dead-pre-folded-tier reason as
;   Ifrit's FIRE_2.  RASP left to Ramuh so the two MP stones stay distinct
;   (Ramuh destroys MP, Shiva steals it); CURE left to Kirin, because Shiva
;   prevents damage and Kirin repairs it.  SLOW is deliberately not here: it
;   rides her
;   re-authored Diamond Dust divine instead (battle_main.asm MagicProp $38), so
;   the list and the summon do not duplicate each other and Siren keeps a job.
;   Known gap (§12.6): boosting Shell does nothing, because it is in no fold
;   family and deals no damage, so Ot6BoostDmg has nothing to multiply.  That
;   is a
;   general gap in the BP economy, not a Shiva bug.
make_genju_prop {ICE, 0}, {OSMOSE, 0}, {SHELL, 0}, {}, {}

; 3: siren
make_genju_prop {SLEEP, 0}, {MUTE, 0}, {SLOW, 0}, {FIRE, 0}, {}

; 4: terrato
make_genju_prop {QUAKE, 0}, {QUARTR, 0}, {W_WIND, 0}, {}, {}

; 5: shoat, "the Gorgon Eye" (v0.7, magicite-tube-six.md §5).  The
;   executioner: Break + Doom, the two deletion verbs.  BIO is dropped for two
;   reasons: it is the pre-folded cap of the poison family (Ot6FoldTbl row 3,
;   ot6_boost.asm:344, a 26 MP dead tier beside a 3 MP fold) and poison is
;   Edgar's authored key (Bio Blaster, kits.md's Edgar tool table).  It is
;   also poison into a cave section where four of five species absorb poison
;   (magicite-tube-six.md §2.2), i.e. a 26 MP self-heal
;   button for the enemy.  Both spells are power-0 hit-rolled death-class,
;   outside both boost axes (no damage to multiply, no fold row, and no
;   chance-verb certainty mechanism exists for magic); ledger item (§13.4),
;   not a bug here.
make_genju_prop {BREAK, 0}, {DOOM, 0}, {}, {}, {}

; 6: maduin, "the Trinity" (v0.7, magicite-tube-six.md §4).  Terra's
;   inheritance: the pure mage job.  All three grants are base tiers of fold
;   families (Ot6FoldTbl rows 0-2, ot6_boost.asm:341-343); the vanilla
;   FIRE_2/ICE_2/BOLT_2 row was three dead pre-folded tiers at once, the
;   Kirin reason (row 17 below), three times over.
make_genju_prop {FIRE, 0}, {ICE, 0}, {BOLT, 0}, {}, {}

; 7: bismark, "the Tide" (v0.7, magicite-tube-six.md §8).  The tempo mage:
;   Haste and Slow both fold party-/field-wide at 1 BP (Ot6FoldTbl rows 6-7,
;   ot6_boost.asm:347-348).  Water lives in his summon (Sea Song $3d, the
;   game's only water verb) because no water-element player spell exists to
;   grant (§13.5).  LIFE is dropped: revival lives on Terra, Fenix Downs and
;   Sraphim only (docs/design/kits.md, Terra's revival rule), and the vanilla
;   row put revival on a stone anyone can wear, breaking that rule.
;   FIRE/ICE/BOLT dropped: Maduin's job.
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

; 17: kirin, healer kit.  CURE is base-tier: it folds to Cure2/Cure3 under boost
;   via Ot6FoldTbl (ot6.asm), so the vanilla pre-folded CURE_2 grant is dropped;
;   the Ramuh precedent is "grant the base tier, let boost do the tiering."  A
;   granted Cure2 would otherwise sit as an un-foldable dead tier beside the
;   foldable Cure (kits.md: kits list base spells only).  Regen/Antdot/Scan are in
;   no fold family, so they are already correct as-is.
make_genju_prop {CURE, 0}, {REGEN, 0}, {ANTDOT, 0}, {SCAN, 0}, {}

; 18: zoneseek, "the Sap" (optional, Jidoor Auction House).  The MP-warfare
;   stone: Rasp and Osmose are the game's MP attrition (drain to kill a caster,
;   steal to fuel your own), Shell the magic wall behind them.  No fold family
;   touches these three, so all three stand as-is.  An optional stone, tuned to
;   the story tier it is bought alongside (the tube six).
make_genju_prop {RASP, 0}, {OSMOSE, 0}, {SHELL, 0}, {}, {}

; 19: carbunkl, "the Facet" (v0.7, magicite-tube-six.md §7).  The mirror:
;   Rflect (nobody else grants it) + Safe (the physical wall; Celes and
;   Golem are both absent all section).  HASTE moved to Bismark for identity;
;   SHELL stays Shiva's; WARP is field furniture, dropped.
make_genju_prop {RFLECT, 0}, {SAFE, 0}, {}, {}, {}

; 20: phantom, "the Ghostwalk" (v0.7, magicite-tube-six.md §6).  The
;   assassin's second: Vanish (both directions, the dodge and the old
;   trick) + Demi (halve what you cannot yet kill).  BSERK dropped: it removes
;   player control (the recorded Ifrit reason).  The divine, Fader $4a, is the
;   unbuildable Ghostwalk passive made party-wide.
make_genju_prop {VANISH, 0}, {DEMI, 0}, {}, {}, {}

; 21: sraphim, "the Seraph" (optional, the man in the woods near Tzen).  The
;   revival stone -- one of the only three sources of Life in the game (Bismark
;   row: "revival lives on Terra, Fenix Downs and Sraphim only").  LIFE folds to
;   Life 2 under boost (Ot6FoldTbl), and CURE folds to Cure 2/Cure 3, so the
;   vanilla pre-folded CURE_2 grant is dropped as a dead un-foldable tier (the
;   Kirin/Unicorn reason); the foldable CURE covers every tier.  Regen/Remedy
;   round out the durable-healer identity.
make_genju_prop {LIFE, 0}, {CURE, 0}, {REGEN, 0}, {REMEDY, 0}, {}

; 22: golem, "the Bulwark" (optional, Jidoor Auction House).  The defensive wall
;   -- its summon still raises the Earth Wall that soaks physical hits for the
;   party (battle_main $3a81, preserved).  The granted kit is that identity:
;   Safe (the physical-defense buff) plus Stop (lock a threat down).  The
;   pre-folded CURE_2 is dropped -- a dead un-foldable tier, and healing is
;   Kirin/Sraphim's job, not the wall's.
make_genju_prop {SAFE, 0}, {STOP, 0}, {}, {}, {}

; 23: unicorn -- "the Purity" (v0.7, magicite-tube-six.md §9).  The paladin:
;   smite + cleanse.  PEARL is BRANCH A of the cross-doc holy decision, DECIDED
;   by the dispatcher 2026-07-28 (§9 decision box): the section's pearl
;   REACHABILITY stands on Sabin's AuraBolt plus the survey's authored class
;   rows (break-coverage-sealed-gate.md), never on this stone -- Unicorn grants
;   Pearl as the paladin identity and the big-hit option, its vanilla 40 MP
;   keeping it a decision rather than the default swing.  CURE_2 dropped (dead
;   pre-folded tier, the Kirin reason); SAFE -> Carbunkl; SHELL stays Shiva's;
;   DISPEL dropped (branch B's second row).
make_genju_prop {PEARL, 0}, {REMEDY, 0}, {}, {}, {}

; 24: fenrir
make_genju_prop {WARP, 0}, {X_ZONE, 0}, {STOP, 0}, {}, {}

; 25: starlet
make_genju_prop {CURE, 0}, {CURE_2, 0}, {CURE_3, 0}, {REGEN, 0}, {REMEDY, 0}

; 26: phoenix
make_genju_prop {LIFE, 0}, {LIFE_2, 0}, {LIFE_3, 0}, {CURE_3, 0}, {FIRE_3, 0}

; ------------------------------------------------------------------------------
