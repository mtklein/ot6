; ------------------------------------------------------------------------------
; OT6: weapon/ability class data (M3)
;
; four physical classes, one bit each, sharing a byte with the null-break
; property. together with the 8 elements these are octopath's 12 probe axes.
; the weapon sets Fight's class; abilities keep their own class byte
; (sabin with claws equipped slashes on Fight, and Pummel stays bludgeoning).
; ------------------------------------------------------------------------------

; six-class prototype (wt/proto-six-classes, #566): v0.50's four classes each
; split in two.  bits $01..$08 keep their v0.50 parent (slash, pierce,
; bludgeon, special), so a v0.50 save's revealed class bits read as the
; first child of what they were.
OT6_SWORD   := $01              ; swords, the chain saw (was slash)
OT6_DAGGER  := $02              ; daggers, thrown stars and edges, darts,
                                ;   a thief's hit (was pierce)
OT6_FIST    := $04              ; fists, claws, fangs, clubs, flails (was
                                ;   bludgeon; the claws were slash)
OT6_ARCANE  := $08              ; rods, brushes, cards, dice, coins, the
                                ;   returning arcs (was special; the rods
                                ;   and arcs were bludgeon)
OT6_KATANA  := $10              ; katanas, ninja blades, swdtech (was
                                ;   slash; the ninja blades were pierce)
OT6_SPEAR   := $20              ; spears, bolts, the drill, the air anchor,
                                ;   tekmissile (was pierce)
OT6_CLASSES := $3f              ; every class bit
OT6_NCLASS  = 6
OT6_NULLBRK := $80              ; property, not a class: high damage that
                                ;   chips nothing (the physical mirror of
                                ;   non-elemental magic). class bits stay set
                                ;   for future consumers (equip permits, hud).

; the classes the kits load by hand (no weapon, no table row)
OT6_CLS_THIEF = OT6_DAGGER      ; Mug, Trickshot and the rest of Locke's hits
OT6_CLS_COIN  = OT6_ARCANE      ; Coin Toss and a character's GP Rain
OT6_CLS_CLUB  = OT6_FIST        ; Umaro's Charge and Throw

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
;     wing edge) is all bludgeoning per "boomerangs (ranged bludgeon)",
;     even the edgy-looking discs; one-way thrown points (shuriken, stars,
;     darts, hawk eye) are piercing per "thrown edges, darts".
;   - hawk eye $49: piercing (a thrown blade, not a returning arc).
;   - air anchor $a9: piercing (it fires a harpoon).
;   - atma weapon $1c: plain slashing, not null-break.
;   - empty hand $ff: bludgeoning. fists are a real class ("claws are how
;     the monk buys into a second class"), so bare knuckles stay bludgeon
;     and umaro is classified correctly with no special case.
;   - dried meat is $fe and "empty" is $ff in equipment slots; only $ff
;     ever appears in a hand.

Ot6WeapClassTbl:
        ; daggers $00-$09
        .byte   OT6_DAGGER      ; $00 dirk
        .byte   OT6_DAGGER      ; $01 mithrilknife
        .byte   OT6_DAGGER      ; $02 guardian
        .byte   OT6_DAGGER      ; $03 air lancet
        .byte   OT6_DAGGER      ; $04 thiefknife
        .byte   OT6_DAGGER      ; $05 assassin
        .byte   OT6_DAGGER      ; $06 man eater
        .byte   OT6_DAGGER      ; $07 swordbreaker
        .byte   OT6_DAGGER      ; $08 graedus
        .byte   OT6_DAGGER      ; $09 valiantknife
        ; swords $0a-$1c
        .byte   OT6_SWORD       ; $0a mithrilblade
        .byte   OT6_SWORD       ; $0b regalcutlass
        .byte   OT6_SWORD       ; $0c rune edge
        .byte   OT6_SWORD       ; $0d flame sabre
        .byte   OT6_SWORD       ; $0e blizzard
        .byte   OT6_SWORD       ; $0f thunderblade
        .byte   OT6_SWORD       ; $10 epee
        .byte   OT6_SWORD       ; $11 break blade
        .byte   OT6_SWORD       ; $12 drainer
        .byte   OT6_SWORD       ; $13 enhancer
        .byte   OT6_SWORD       ; $14 crystal
        .byte   OT6_SWORD       ; $15 falchion
        .byte   OT6_SWORD       ; $16 soul sabre
        .byte   OT6_SWORD       ; $17 ogre nix
        .byte   OT6_SWORD       ; $18 excalibur
        .byte   OT6_SWORD       ; $19 scimitar
        .byte   OT6_SWORD       ; $1a illumina
        .byte   OT6_SWORD       ; $1b ragnarok
        .byte   OT6_SWORD       ; $1c atma weapon
        ; spears $1d-$24
        .byte   OT6_SPEAR       ; $1d mithril pike
        .byte   OT6_SPEAR       ; $1e trident
        .byte   OT6_SPEAR       ; $1f stout spear
        .byte   OT6_SPEAR       ; $20 partisan
        .byte   OT6_SPEAR       ; $21 pearl lance
        .byte   OT6_SPEAR       ; $22 gold lance
        .byte   OT6_SPEAR       ; $23 aura lance
        .byte   OT6_SPEAR       ; $24 imp halberd
        ; ninja knives $25-$2a
        .byte   OT6_KATANA      ; $25 imperial
        .byte   OT6_KATANA      ; $26 kodachi
        .byte   OT6_KATANA      ; $27 blossom
        .byte   OT6_KATANA      ; $28 hardened
        .byte   OT6_KATANA      ; $29 striker
        .byte   OT6_KATANA      ; $2a stunner
        ; katanas $2b-$32
        .byte   OT6_KATANA      ; $2b ashura
        .byte   OT6_KATANA      ; $2c kotetsu
        .byte   OT6_KATANA      ; $2d forged
        .byte   OT6_KATANA      ; $2e tempest
        .byte   OT6_KATANA      ; $2f murasame
        .byte   OT6_KATANA      ; $30 aura
        .byte   OT6_KATANA      ; $31 strato
        .byte   OT6_KATANA      ; $32 sky render
        ; rods $33-$3c
        .byte   $00             ; $33 heal rod (teaches nothing; see block)
        .byte   OT6_ARCANE      ; $34 mithril rod
        .byte   OT6_ARCANE      ; $35 fire rod
        .byte   OT6_ARCANE      ; $36 ice rod
        .byte   OT6_ARCANE      ; $37 thunder rod
        .byte   OT6_ARCANE      ; $38 poison rod
        .byte   OT6_ARCANE      ; $39 pearl rod
        .byte   OT6_ARCANE      ; $3a gravity rod
        .byte   OT6_ARCANE      ; $3b punisher
        .byte   OT6_ARCANE      ; $3c magus rod
        ; brushes $3d-$40
        .byte   OT6_ARCANE      ; $3d chocobo brush
        .byte   OT6_ARCANE      ; $3e davinci brush
        .byte   OT6_ARCANE      ; $3f magical brush
        .byte   OT6_ARCANE      ; $40 rainbow brush
        ; thrown stars $41-$43
        .byte   OT6_DAGGER      ; $41 shuriken
        .byte   OT6_DAGGER      ; $42 ninja star
        .byte   OT6_DAGGER      ; $43 tack star
        ; the "special"-icon grab bag $44-$52
        .byte   OT6_FIST        ; $44 flail
        .byte   OT6_ARCANE      ; $45 full moon (returning arc)
        .byte   OT6_FIST        ; $46 morning star
        .byte   OT6_ARCANE      ; $47 boomerang
        .byte   OT6_ARCANE      ; $48 rising sun (returning arc)
        .byte   OT6_DAGGER      ; $49 hawk eye (thrown blade)
        .byte   OT6_FIST        ; $4a bone club
        .byte   OT6_ARCANE      ; $4b sniper (returning arc)
        .byte   OT6_ARCANE      ; $4c wing edge (returning arc)
        .byte   OT6_ARCANE      ; $4d cards
        .byte   OT6_DAGGER      ; $4e darts
        .byte   OT6_DAGGER      ; $4f doom darts
        .byte   OT6_ARCANE      ; $50 trump
        .byte   OT6_ARCANE      ; $51 dice (ordinary ¤: chips)
        .byte   OT6_ARCANE|OT6_NULLBRK; $52 fixed dice: high damage, teaches nothing
        ; claws $53-$59
        .byte   OT6_FIST        ; $53 metalknuckle
        .byte   OT6_FIST        ; $54 mithril claw
        .byte   OT6_FIST        ; $55 kaiser
        .byte   OT6_FIST        ; $56 poison claw
        .byte   OT6_FIST        ; $57 fire knuckle
        .byte   OT6_FIST        ; $58 dragon claw
        .byte   OT6_FIST        ; $59 tiger fangs
        ; shields/helms/armor $5a-$a2: no class
        .res    $a3 - $5a, $00
        ; tools $a3-$aa (the Tools command resolves through item data,
        ; so these bytes are the tool skills' classes)
        .byte   $00             ; $a3 noiseblaster
        .byte   $00             ; $a4 bio blaster (resolves as its spell)
        .byte   $00             ; $a5 flash (resolves as its spell)
        .byte   OT6_SWORD       ; $a6 chain saw ("buys edgar slashing")
        .byte   $00             ; $a7 debilitator
        .byte   OT6_SPEAR       ; $a8 drill
        .byte   OT6_SPEAR       ; $a9 air anchor (harpoon)
        .byte   OT6_SPEAR       ; $aa autocrossbow
        ; skeans/edges $ab-$ad resolve as their spells $51-$53, whose class
        ; is Ot6SkillClassTbl's (pierce, #383); the Inviz and Shadow Edges
        ; deal no damage (ot6_shadow.asm): no class here
        .res    $b0 - $ab, $00
        ; relics $b0-$e6, consumables $e7-$fe: no class
        .res    $ff - $b0, $00
        .byte   OT6_FIST        ; $ff empty hand: bare fists bludgeon

; ------------------------------------------------------------------------------

; [ ability id -> class byte ]

; (id, class) pairs, $ff-terminated. abilities carry their own class no
; matter what is equipped ✦. this table is scanned once per attack load,
; and anything absent is classless: its element byte carries the probe
; (aurabolt is a holy chip, not a punch). WoB physical skills only;
; slots attacks, dances, and rage specials stay unclassified.
;
;   - swdtechs slash: cyan is the slashing specialist, and quadra slam is
;     the strongest slash chip in the game.  three are not slashes (#379,
;     kits.md's chip column): retort ($56) is a counter stance and
;     empowerer ($59) a drain, so both are classless and chip nothing; quadra
;     slice ($5b) is wind, its element byte (battle_main.asm's MagicProp
;     override), so it is absent here and chips wind shields four times.
;   - $55 dispatch doubles as slots' "joker doom" (vanilla reuses the
;     record, and renamed its attack-name slot), so a failed joker doom
;     is a slashing probe. that is vanilla behaviour, kept as it is.
;   - pummel/suplex/bum rush bludgeon regardless of claws ✦.
;   - tekmissile is piercing: the whelk tutorial's fourth chip
;     ("three beams and a tekmissile").

Ot6SkillClassTbl:
        .byte   $55, OT6_KATANA ; dispatch
        .byte   $57, OT6_KATANA ; slash
        .byte   $58, OT6_KATANA ; quadra slam (chips per hit)
        .byte   $5a, OT6_KATANA ; stunner
        .byte   $5c, OT6_KATANA ; cleave
        .byte   $5d, OT6_FIST   ; pummel
        .byte   $5f, OT6_FIST   ; suplex (the train is bludgeon-weak)
        .byte   $64, OT6_FIST   ; bum rush
        .byte   $8a, OT6_SPEAR  ; tekmissile
        .byte   $51, OT6_DAGGER ; fire skean  (thrown edges pierce, #383:
        .byte   $52, OT6_DAGGER ; water edge   each chips pierce and its
        .byte   $53, OT6_DAGGER ; bolt edge    element)
        .byte   $ff

; ------------------------------------------------------------------------------

; [ the kits' hand-loaded classes, as data ]

; the harness reads these (tools/tests/lib/ot6.lua M.kitClass) so its key
; model follows the ROM: +0 a thief's hit, +1 the coins, +2 Umaro's club,
; +3 the classes a hire may swing (Ot6HireClass: the first the target is
; weak to, in bit order)
Ot6KitClassTbl:
        .byte   OT6_CLS_THIEF, OT6_CLS_COIN, OT6_CLS_CLUB, OT6_CLASSES

