; ------------------------------------------------------------------------------
; OT6: weapon/ability class data (M3)
;
; six physical classes, one bit each, sharing a byte with the null-break
; property. with the 8 elements these are 14 probe axes (octopath has 12).
; the weapon sets Fight's class; abilities keep their own class byte
; (sabin with a claw equipped is dagger on Fight, and Pummel stays blunt).
; ------------------------------------------------------------------------------

; six weapon classes (#566), after Octopath's six: the four of v0.50 and
; before (slash $01, pierce $02, bludgeon $04, special $08) regrouped by the
; weapon in hand.  tools/six_classes/classes.py is the grouping as data, and
; this file's two tables follow it (the [kind] tags are its kinds).
OT6_SWORD   := $01              ; straight swords; the chain saw
OT6_DAGGER  := $02              ; daggers, ninja blades and claws; a thief's hit
OT6_BLUNT   := $04              ; fists and knuckles, rods and brushes, flails
                                ;   and clubs; the blitzes' blows; umaro's arms
OT6_RANGED  := $08              ; what is thrown or shot: stars, skeans, darts,
                                ;   cards, dice, coins, boomerangs, the
                                ;   autocrossbow, the air anchor, tekmissile
OT6_KATANA  := $10              ; katanas and the curved swords (the sabres,
                                ;   the cutlass, falchion, scimitar); swdtech
OT6_SPEAR   := $20              ; spears; the drill
OT6_CLASSES := $3f              ; every class bit
OT6_NCLASS  = 6
OT6_ANYWEAPON = $df             ; the HUD's mark for a body every class breaks
                                ;   (vanilla's sparkle cell; no class wears it)
OT6_NULLBRK := $80              ; property, not a class: high damage that
                                ;   chips nothing (the physical mirror of
                                ;   non-elemental magic). class bits stay set
                                ;   for future consumers (equip permits, hud).

; the classes the kits load by hand (no weapon, no table row)
OT6_CLS_THIEF = OT6_DAGGER      ; Trickshot and Dismantle (Mug swings the weapon in hand)
OT6_CLS_COIN  = OT6_RANGED      ; Coin Toss and a character's GP Rain
OT6_CLS_CLUB  = OT6_BLUNT      ; Umaro's Charge and Throw
OT6_CLS_FANG  = OT6_DAGGER      ; Gau's own body: his bare hand, and his raging Fight

.segment "ot6_code"

; ------------------------------------------------------------------------------

; [ weapon item id -> class byte ]

; one byte per item id, directly indexed (no scan: Fight reads this per
; swing). non-weapons are $00. WoR-only weapons are classified too.
;
; judgment calls for ambiguous items:
;   - heal rod $33: no class. a healing rod teaches nothing, and leaving it
;     classless avoids the undead/heal-reversal ambiguity until it is needed.
;   - the returning-arc family (full moon, boomerang, rising sun, sniper,
;     wing edge) is all ranged, with what else is thrown (shuriken, stars,
;     darts, cards, dice); v0.50 had the arcs bludgeon ("boomerangs (ranged
;     bludgeon)") and the thrown points pierce ("thrown edges, darts").
;   - hawk eye $49: ranged (a thrown blade; vanilla drew it with the flails).
;   - air anchor $a9: ranged (it fires a harpoon, as the crossbow its bolts).
;   - atma weapon $1c: a plain sword, not null-break.
;   - empty hand $ff: blunt, a fist. the knuckles strike and are blunt too;
;     the claws are dagger (owner, 2026-11-24: "claws just feels like
;     daggers"), so sabin with a claw holds a second class.  the curved,
;     single-edged swords are katana (regalcutlass, flame sabre, falchion,
;     soul sabre, scimitar); every other sword is sword. umaro needs no special case; gau's empty
;     hand is his fangs, dagger, in Ot6WeaponClass (OT6_CLS_FANG).
;   - dried meat is $fe and "empty" is $ff in equipment slots; only $ff
;     ever appears in a hand.

Ot6WeapClassTbl:
        ; daggers $00-$09
        .byte   OT6_DAGGER      ; $00 dirk [dagger]
        .byte   OT6_DAGGER      ; $01 mithrilknife [dagger]
        .byte   OT6_DAGGER      ; $02 guardian [dagger]
        .byte   OT6_DAGGER      ; $03 air lancet [dagger]
        .byte   OT6_DAGGER      ; $04 thiefknife [dagger]
        .byte   OT6_DAGGER      ; $05 assassin [dagger]
        .byte   OT6_DAGGER      ; $06 man eater [dagger]
        .byte   OT6_DAGGER      ; $07 swordbreaker [dagger]
        .byte   OT6_DAGGER      ; $08 graedus [dagger]
        .byte   OT6_DAGGER      ; $09 valiantknife [dagger]
        ; swords $0a-$1c
        .byte   OT6_SWORD       ; $0a mithrilblade [sword]
        .byte   OT6_KATANA      ; $0b regalcutlass [sabre]
        .byte   OT6_SWORD       ; $0c rune edge [sword]
        .byte   OT6_KATANA      ; $0d flame sabre [sabre]
        .byte   OT6_SWORD       ; $0e blizzard [sword]
        .byte   OT6_SWORD       ; $0f thunderblade [sword]
        .byte   OT6_SWORD       ; $10 epee [sword]
        .byte   OT6_SWORD       ; $11 break blade [sword]
        .byte   OT6_SWORD       ; $12 drainer [sword]
        .byte   OT6_SWORD       ; $13 enhancer [sword]
        .byte   OT6_SWORD       ; $14 crystal [sword]
        .byte   OT6_KATANA      ; $15 falchion [sabre]
        .byte   OT6_KATANA      ; $16 soul sabre [sabre]
        .byte   OT6_SWORD       ; $17 ogre nix [sword]
        .byte   OT6_SWORD       ; $18 excalibur [sword]
        .byte   OT6_KATANA      ; $19 scimitar [sabre]
        .byte   OT6_SWORD       ; $1a illumina [sword]
        .byte   OT6_SWORD       ; $1b ragnarok [sword]
        .byte   OT6_SWORD       ; $1c atma weapon [sword]
        ; spears $1d-$24
        .byte   OT6_SPEAR       ; $1d mithril pike [spear]
        .byte   OT6_SPEAR       ; $1e trident [spear]
        .byte   OT6_SPEAR       ; $1f stout spear [spear]
        .byte   OT6_SPEAR       ; $20 partisan [spear]
        .byte   OT6_SPEAR       ; $21 pearl lance [spear]
        .byte   OT6_SPEAR       ; $22 gold lance [spear]
        .byte   OT6_SPEAR       ; $23 aura lance [spear]
        .byte   OT6_SPEAR       ; $24 imp halberd [spear]
        ; ninja knives $25-$2a
        .byte   OT6_DAGGER      ; $25 imperial [ninja blade]
        .byte   OT6_DAGGER      ; $26 kodachi [ninja blade]
        .byte   OT6_DAGGER      ; $27 blossom [ninja blade]
        .byte   OT6_DAGGER      ; $28 hardened [ninja blade]
        .byte   OT6_DAGGER      ; $29 striker [ninja blade]
        .byte   OT6_DAGGER      ; $2a stunner [ninja blade]
        ; katanas $2b-$32
        .byte   OT6_KATANA      ; $2b ashura [katana]
        .byte   OT6_KATANA      ; $2c kotetsu [katana]
        .byte   OT6_KATANA      ; $2d forged [katana]
        .byte   OT6_KATANA      ; $2e tempest [katana]
        .byte   OT6_KATANA      ; $2f murasame [katana]
        .byte   OT6_KATANA      ; $30 aura [katana]
        .byte   OT6_KATANA      ; $31 strato [katana]
        .byte   OT6_KATANA      ; $32 sky render [katana]
        ; rods $33-$3c
        .byte   $00             ; $33 heal rod (teaches nothing; see block)
        .byte   OT6_BLUNT       ; $34 mithril rod [rod]
        .byte   OT6_BLUNT       ; $35 fire rod [rod]
        .byte   OT6_BLUNT       ; $36 ice rod [rod]
        .byte   OT6_BLUNT       ; $37 thunder rod [rod]
        .byte   OT6_BLUNT       ; $38 poison rod [rod]
        .byte   OT6_BLUNT       ; $39 pearl rod [rod]
        .byte   OT6_BLUNT       ; $3a gravity rod [rod]
        .byte   OT6_BLUNT       ; $3b punisher [rod]
        .byte   OT6_BLUNT       ; $3c magus rod [rod]
        ; brushes $3d-$40
        .byte   OT6_BLUNT       ; $3d chocobo brush [brush]
        .byte   OT6_BLUNT       ; $3e davinci brush [brush]
        .byte   OT6_BLUNT       ; $3f magical brush [brush]
        .byte   OT6_BLUNT       ; $40 rainbow brush [brush]
        ; thrown stars $41-$43
        .byte   OT6_RANGED      ; $41 shuriken [star]
        .byte   OT6_RANGED      ; $42 ninja star [star]
        .byte   OT6_RANGED      ; $43 tack star [star]
        ; the "special"-icon grab bag $44-$52
        .byte   OT6_BLUNT       ; $44 flail [flail]
        .byte   OT6_RANGED      ; $45 full moon (returning arc) [boomerang]
        .byte   OT6_BLUNT       ; $46 morning star [flail]
        .byte   OT6_RANGED      ; $47 boomerang [boomerang]
        .byte   OT6_RANGED      ; $48 rising sun (returning arc) [boomerang]
        .byte   OT6_RANGED      ; $49 hawk eye (thrown blade) [boomerang]
        .byte   OT6_BLUNT       ; $4a bone club [club]
        .byte   OT6_RANGED      ; $4b sniper (returning arc) [boomerang]
        .byte   OT6_RANGED      ; $4c wing edge (returning arc) [boomerang]
        .byte   OT6_RANGED      ; $4d cards [card]
        .byte   OT6_RANGED      ; $4e darts [dart]
        .byte   OT6_RANGED      ; $4f doom darts [dart]
        .byte   OT6_RANGED      ; $50 trump [card]
        .byte   OT6_RANGED      ; $51 dice (ordinary: chips) [dice]
        .byte   OT6_RANGED|OT6_NULLBRK; $52 fixed dice: high damage, teaches nothing [dice]
        ; claws $53-$59
        .byte   OT6_BLUNT       ; $53 metalknuckle [knuckle]
        .byte   OT6_DAGGER      ; $54 mithril claw [claw]
        .byte   OT6_BLUNT       ; $55 kaiser [knuckle]
        .byte   OT6_DAGGER      ; $56 poison claw [claw]
        .byte   OT6_BLUNT       ; $57 fire knuckle [knuckle]
        .byte   OT6_DAGGER      ; $58 dragon claw [claw]
        .byte   OT6_DAGGER      ; $59 tiger fangs [claw]
        ; shields/helms/armor $5a-$a2: no class
        .res    $a3 - $5a, $00
        ; tools $a3-$aa (the Tools command resolves through item data,
        ; so these bytes are the tool skills' classes)
        .byte   $00             ; $a3 noiseblaster
        .byte   $00             ; $a4 bio blaster (resolves as its spell)
        .byte   $00             ; $a5 flash (resolves as its spell)
        .byte   OT6_SWORD       ; $a6 chain saw (edgar's sword key) [chainsaw]
        .byte   $00             ; $a7 debilitator
        .byte   OT6_SPEAR       ; $a8 drill [drill]
        .byte   OT6_RANGED      ; $a9 air anchor (harpoon) [air anchor]
        .byte   OT6_RANGED      ; $aa autocrossbow [crossbow]
        ; skeans/edges $ab-$ad resolve as their spells $51-$53, whose class
        ; is Ot6SkillClassTbl's (ranged, #383); the Inviz and Shadow Edges
        ; deal no damage (ot6_shadow.asm): no class here
        .res    $b0 - $ab, $00
        ; relics $b0-$e6, consumables $e7-$fe: no class
        .res    $ff - $b0, $00
        .byte   OT6_BLUNT       ; $ff empty hand: bare fists [fist]

; ------------------------------------------------------------------------------

; [ ability id -> class byte ]

; (id, class) pairs, $ff-terminated. abilities carry their own class no
; matter what is equipped ✦. this table is scanned once per attack load,
; and anything absent is classless: its element byte carries the probe
; (aurabolt is a holy chip, not a punch). WoB physical skills only;
; slots attacks, dances, and rage specials stay unclassified.
;
;   - swdtechs are katana: cyan is its specialist, and quadra slam is
;     the strongest katana chip in the game.  three are not cuts (#379,
;     kits.md's chip column): retort ($56) is a counter stance and
;     empowerer ($59) a drain, so both are classless and chip nothing; quadra
;     slice ($5b) is wind, its element byte (battle_main.asm's MagicProp
;     override), so it is absent here and chips wind shields four times.
;   - $55 dispatch doubles as slots' "joker doom" (vanilla reuses the
;     record, and renamed its attack-name slot), so a failed joker doom
;     is a katana probe. that is vanilla behaviour, kept as it is.
;   - pummel/suplex/bum rush are blunt regardless of claws ✦.
;   - tekmissile is ranged: the whelk tutorial's fourth chip
;     ("three beams and a tekmissile").

Ot6SkillClassTbl:
        .byte   $55, OT6_KATANA ; dispatch [swdtech]
        .byte   $57, OT6_KATANA ; slash [swdtech]
        .byte   $58, OT6_KATANA ; quadra slam (chips per hit) [swdtech]
        .byte   $5a, OT6_KATANA ; stunner [swdtech]
        .byte   $5c, OT6_KATANA ; cleave [swdtech]
        .byte   $5d, OT6_BLUNT  ; pummel [blitz]
        .byte   $5f, OT6_BLUNT  ; suplex (the ghost train takes it) [blitz]
        .byte   $64, OT6_BLUNT  ; bum rush [blitz]
        .byte   $8a, OT6_RANGED ; tekmissile [tekmissile]
        .byte   $51, OT6_RANGED ; fire skean  (thrown, so ranged, #383: [skean]
        .byte   $52, OT6_RANGED ; water edge   each chips ranged and its [skean]
        .byte   $53, OT6_RANGED ; bolt edge    element) [skean]
        .byte   $ff

; ------------------------------------------------------------------------------

; [ the kits' hand-loaded classes, as data ]

; the harness reads these (tools/tests/lib/ot6.lua M.kitClass) so its key
; model follows the ROM: +0 a thief's hit, +1 the coins, +2 Umaro's club,
; +3 the classes a hire may swing (Ot6HireClass: the first the target is
; weak to, in bit order), +4 Gau's fangs
Ot6KitClassTbl:
        .byte   OT6_CLS_THIEF, OT6_CLS_COIN, OT6_CLS_CLUB, OT6_CLASSES, OT6_CLS_FANG

