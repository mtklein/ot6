; ------------------------------------------------------------------------------
; OT6 — weapon/ability class data (M3)
;
; four physical classes, one bit each, sharing a byte with the null-break
; property. together with the 8 elements these are octopath's 12 probe axes.
; the WEAPON sets Fight's class; ABILITIES keep their own class byte
; (sabin with claws equipped slashes on Fight — Pummel stays bludgeoning).
; ------------------------------------------------------------------------------

OT6_SLASH   := $01              ; swords, katanas, claws
OT6_PIERCE  := $02              ; spears, daggers, thrown edges, bolts, darts
OT6_BLUDG   := $04              ; fists, staves, rods, flails, boomerangs
OT6_SPECIAL := $08              ; ¤: dice, cards, brushes — real and breakable
OT6_NULLBRK := $80              ; property, not a class: big dumb damage that
                                ;   chips nothing (the physical mirror of
                                ;   non-elemental magic). class bits stay set
                                ;   for future consumers (equip permits, hud).

.segment "ot6_code"

; ------------------------------------------------------------------------------

; [ weapon item id -> class byte ]

; one byte per item id, directly indexed (no scan: Fight reads this per
; swing). non-weapons are $00. classified per docs/design/weapon-classes.md
; v2.1; WoR-only weapons are classified too — the rules cover them for free.
;
; judgment calls (v2.1 leaves these to taste — driver review welcome):
;   - heal rod $33: NO class. a healing stick teaches nothing; also dodges
;     the undead/heal-reversal ambiguity until someone actually wants it.
;   - the returning-arc family (full moon, boomerang, rising sun, sniper,
;     wing edge) is all bludgeoning per "boomerangs (ranged bludgeon)",
;     even the edgy-looking discs; one-way thrown points (shuriken, stars,
;     darts, hawk eye) are piercing per "thrown edges, darts".
;   - hawk eye $49: piercing (a thrown blade, not a returning arc).
;   - air anchor $a9: piercing (it fires a harpoon).
;   - atma weapon $1c: plain slashing. it's "big dumb damage" in spirit,
;     but v2.1 only names fixed dice for null-break — driver call.
;   - empty hand $ff: bludgeoning. fists are a real class ("claws are how
;     the monk buys into a second class" — bare knuckles stay bludgeon,
;     and umaro punches things correctly for free).
;   - dried meat is $fe and "empty" is $ff in equipment slots; only $ff
;     ever appears in a hand.

Ot6WeapClassTbl:
        ; daggers $00-$09
        .byte   OT6_PIERCE      ; $00 dirk
        .byte   OT6_PIERCE      ; $01 mithrilknife
        .byte   OT6_PIERCE      ; $02 guardian
        .byte   OT6_PIERCE      ; $03 air lancet
        .byte   OT6_PIERCE      ; $04 thiefknife
        .byte   OT6_PIERCE      ; $05 assassin
        .byte   OT6_PIERCE      ; $06 man eater
        .byte   OT6_PIERCE      ; $07 swordbreaker
        .byte   OT6_PIERCE      ; $08 graedus
        .byte   OT6_PIERCE      ; $09 valiantknife
        ; swords $0a-$1c
        .byte   OT6_SLASH       ; $0a mithrilblade
        .byte   OT6_SLASH       ; $0b regalcutlass
        .byte   OT6_SLASH       ; $0c rune edge
        .byte   OT6_SLASH       ; $0d flame sabre
        .byte   OT6_SLASH       ; $0e blizzard
        .byte   OT6_SLASH       ; $0f thunderblade
        .byte   OT6_SLASH       ; $10 epee
        .byte   OT6_SLASH       ; $11 break blade
        .byte   OT6_SLASH       ; $12 drainer
        .byte   OT6_SLASH       ; $13 enhancer
        .byte   OT6_SLASH       ; $14 crystal
        .byte   OT6_SLASH       ; $15 falchion
        .byte   OT6_SLASH       ; $16 soul sabre
        .byte   OT6_SLASH       ; $17 ogre nix
        .byte   OT6_SLASH       ; $18 excalibur
        .byte   OT6_SLASH       ; $19 scimitar
        .byte   OT6_SLASH       ; $1a illumina
        .byte   OT6_SLASH       ; $1b ragnarok
        .byte   OT6_SLASH       ; $1c atma weapon (null-break? driver call)
        ; spears $1d-$24
        .byte   OT6_PIERCE      ; $1d mithril pike
        .byte   OT6_PIERCE      ; $1e trident
        .byte   OT6_PIERCE      ; $1f stout spear
        .byte   OT6_PIERCE      ; $20 partisan
        .byte   OT6_PIERCE      ; $21 pearl lance
        .byte   OT6_PIERCE      ; $22 gold lance
        .byte   OT6_PIERCE      ; $23 aura lance
        .byte   OT6_PIERCE      ; $24 imp halberd
        ; ninja knives $25-$2a
        .byte   OT6_PIERCE      ; $25 imperial
        .byte   OT6_PIERCE      ; $26 kodachi
        .byte   OT6_PIERCE      ; $27 blossom
        .byte   OT6_PIERCE      ; $28 hardened
        .byte   OT6_PIERCE      ; $29 striker
        .byte   OT6_PIERCE      ; $2a stunner
        ; katanas $2b-$32
        .byte   OT6_SLASH       ; $2b ashura
        .byte   OT6_SLASH       ; $2c kotetsu
        .byte   OT6_SLASH       ; $2d forged
        .byte   OT6_SLASH       ; $2e tempest
        .byte   OT6_SLASH       ; $2f murasame
        .byte   OT6_SLASH       ; $30 aura
        .byte   OT6_SLASH       ; $31 strato
        .byte   OT6_SLASH       ; $32 sky render
        ; rods $33-$3c
        .byte   $00             ; $33 heal rod (teaches nothing; see block)
        .byte   OT6_BLUDG       ; $34 mithril rod
        .byte   OT6_BLUDG       ; $35 fire rod
        .byte   OT6_BLUDG       ; $36 ice rod
        .byte   OT6_BLUDG       ; $37 thunder rod
        .byte   OT6_BLUDG       ; $38 poison rod
        .byte   OT6_BLUDG       ; $39 pearl rod
        .byte   OT6_BLUDG       ; $3a gravity rod
        .byte   OT6_BLUDG       ; $3b punisher
        .byte   OT6_BLUDG       ; $3c magus rod
        ; brushes $3d-$40
        .byte   OT6_SPECIAL     ; $3d chocobo brush
        .byte   OT6_SPECIAL     ; $3e davinci brush
        .byte   OT6_SPECIAL     ; $3f magical brush
        .byte   OT6_SPECIAL     ; $40 rainbow brush
        ; thrown stars $41-$43
        .byte   OT6_PIERCE      ; $41 shuriken
        .byte   OT6_PIERCE      ; $42 ninja star
        .byte   OT6_PIERCE      ; $43 tack star
        ; the "special"-icon grab bag $44-$52
        .byte   OT6_BLUDG       ; $44 flail
        .byte   OT6_BLUDG       ; $45 full moon (returning arc)
        .byte   OT6_BLUDG       ; $46 morning star
        .byte   OT6_BLUDG       ; $47 boomerang
        .byte   OT6_BLUDG       ; $48 rising sun (returning arc)
        .byte   OT6_PIERCE      ; $49 hawk eye (thrown blade)
        .byte   OT6_BLUDG       ; $4a bone club
        .byte   OT6_BLUDG       ; $4b sniper (returning arc)
        .byte   OT6_BLUDG       ; $4c wing edge (returning arc)
        .byte   OT6_SPECIAL     ; $4d cards
        .byte   OT6_PIERCE      ; $4e darts
        .byte   OT6_PIERCE      ; $4f doom darts
        .byte   OT6_SPECIAL     ; $50 trump
        .byte   OT6_SPECIAL     ; $51 dice (ordinary ¤: chips)
        .byte   OT6_SPECIAL|OT6_NULLBRK ; $52 fixed dice: rolls huge, teaches nothing
        ; claws $53-$59
        .byte   OT6_SLASH       ; $53 metalknuckle
        .byte   OT6_SLASH       ; $54 mithril claw
        .byte   OT6_SLASH       ; $55 kaiser
        .byte   OT6_SLASH       ; $56 poison claw
        .byte   OT6_SLASH       ; $57 fire knuckle
        .byte   OT6_SLASH       ; $58 dragon claw
        .byte   OT6_SLASH       ; $59 tiger fangs
        ; shields/helms/armor $5a-$a2: no class
        .res    $a3 - $5a, $00
        ; tools $a3-$aa (the Tools command resolves through item data,
        ; so these bytes are the tool skills' classes)
        .byte   $00             ; $a3 noiseblaster
        .byte   $00             ; $a4 bio blaster (resolves as its spell)
        .byte   $00             ; $a5 flash (resolves as its spell)
        .byte   OT6_SLASH       ; $a6 chain saw ("buys edgar slashing")
        .byte   $00             ; $a7 debilitator
        .byte   OT6_PIERCE      ; $a8 drill
        .byte   OT6_PIERCE      ; $a9 air anchor (harpoon; judgment)
        .byte   OT6_PIERCE      ; $aa autocrossbow
        ; skeans/edges $ab-$af resolve as their spells: no class here
        .res    $b0 - $ab, $00
        ; relics $b0-$e6, consumables $e7-$fe: no class
        .res    $ff - $b0, $00
        .byte   OT6_BLUDG       ; $ff empty hand: bare fists bludgeon

; ------------------------------------------------------------------------------

; [ ability id -> class byte ]

; (id, class) pairs, $ff-terminated. abilities carry their own class no
; matter what's equipped ✦ — this table is scanned once per attack load,
; and anything absent is classless: its element byte carries the probe
; (aurabolt is a holy chip, not a punch). WoB physical skills only;
; slots attacks, dances, and rage specials stay unclassified in v1.
;
;   - swdtechs are all slashing: cyan is the slashing specialist, and
;     quadra slam/slice are the best slash chips in the game.
;   - $55 dispatch doubles as slots' "joker doom" (vanilla reuses the
;     record, and renamed its attack-name slot) — so a failed joker doom
;     is a slashing probe. vanilla jank, preserved by inheritance.
;   - pummel/suplex/bum rush bludgeon regardless of claws ✦.
;   - tekmissile is piercing: the whelk tutorial's fourth chip
;     ("three beams and a tekmissile").

Ot6SkillClassTbl:
        .byte   $55, OT6_SLASH  ; dispatch (fang)
        .byte   $56, OT6_SLASH  ; retort (sky)
        .byte   $57, OT6_SLASH  ; slash (tiger)
        .byte   $58, OT6_SLASH  ; quadra slam (flurry — chips per hit)
        .byte   $59, OT6_SLASH  ; empowerer (dragon)
        .byte   $5a, OT6_SLASH  ; stunner (eclipse)
        .byte   $5b, OT6_SLASH  ; quadra slice (tempest)
        .byte   $5c, OT6_SLASH  ; cleave (oblivion)
        .byte   $5d, OT6_BLUDG  ; pummel
        .byte   $5f, OT6_BLUDG  ; suplex (the train is bludgeon-weak. yes.)
        .byte   $64, OT6_BLUDG  ; bum rush
        .byte   $8a, OT6_PIERCE ; tekmissile
        .byte   $ff
