# The six classes, regrouped (owner, 2026-11-23) -- supersedes "Fist" and "Arcane"

The owner mapped the classes to Octopath's six. `tools/six_classes/classes.py` is the grouping as data (run it to
print holders and awkward fits).

| class | bit | const | what carries it | who really holds it (signature weapon or command) |
|---|---|---|---|---|
| Sword | $01 | OT6_SWORD | swords; Chain Saw | Terra, Celes, Leo (Edgar, Locke when they carry one) |
| Dagger | $02 | OT6_DAGGER | daggers; ninja blades $25-$2a; a thief's hit (Mug, Trickshot); Gau's fangs (his empty hand, and either hand while he rages: Ot6WeaponClass, OT6_CLS_FANG) | Locke, Shadow (in hand), Gau |
| Blunt | $04 | OT6_BLUNT | bare fists (not Gau's), knuckles (MetalKnuckle $53, Kaiser $55, Fire Knuckle $57), rods $34-$3c, brushes $3d-$40, Flail, Morning Star, Bone Club; Pummel, Suplex, Bum Rush; Umaro's Charge and Throw | Sabin, Umaro, Strago, Relm, Banon |
| Ranged | $08 | OT6_RANGED | AutoCrossbow, Air Anchor, TekMissile; thrown stars $41-$43 and the three damaging skeans; Darts, Doom Darts; Cards, Trump, Dice (Fixed Dice Ranged, null-break); Coin Toss / GP Rain; Full Moon, Boomerang, Rising Sun, Hawk Eye, Sniper, Wing Edge | Setzer, Shadow (Throw), Edgar (AutoCrossbow) |
| Katana | $10 | OT6_KATANA | katanas; the edged claws (Mithril Claw $54, Poison Claw $56, Dragon Claw $58, Tiger Fangs $59); SwdTech | Cyan, Sabin (with claws) |
| Spear | $20 | OT6_SPEAR | spears; Drill | Edgar, Mog |

Player-facing names: Sword, Dagger, Spear, Katana, Blunt ("yes i like blunt"), Ranged.
There is no Fist and no Arcane any more: OT6_FIST/OT6_ARCANE do not exist; bits $04 and $08 are Blunt and Ranged,
with different members than Fist and Arcane had (rods and brushes moved $08 -> $04; the AutoCrossbow, stars, darts
moved to $08; ninja blades $10 -> $02; edged claws $04 -> $10; Gau's bare hand $04 -> $02).

What a four-class weakness may become (classes.py CHILDREN): slash -> Sword or Katana; pierce -> Dagger, Spear or
Ranged; bludgeon -> Blunt or Ranged; special -> Ranged or Blunt. Intangir $0A3 and Speck $146 take all six.

HUD glyphs (Ot6ClassGlyphTbl, bit order): sword $d9, dagger $d8 (level), blunt $dc (redrawn: a mallet), ranged $de
(the thrown star), katana $db (mirrored), spear $da (upright). build/attempts/wt/v051-six-classes/glyphs-v3.png.
Weapons' names wear {sword} {dagger} {spear} {katana} {staff}=Blunt {star}=Ranged; the type words are DAGGER, SWORD,
SPEAR, KATANA, BLUNT, RANGED. Messages (Ot6ClassMsgTbl): $45 "Weak against swords", $46 daggers, $47 "Weak against
blunt", $48 "Weak against ranged", $4a katanas, $4b spears.

Hired Help: the lowest-bit class the target is weak to; its Fight animation's weapon family: Sword/Katana a blade,
Dagger/Spear/Ranged a point, Blunt a blow.

Save codex: Ot6ClassSplitTbl is now FOUR bytes a species (byte k = the six-class bits the species' weakness of
four-class bit k became; $00 where it had none); Ot6CodexSix ORs the bytes of the revealed four-class bits. The
two-children selector byte and Ot6ClassSecondTbl are gone.

Harness: M.handClass(char, item, raging) (Gau's fangs), M.kitClass("fang"); M.HUD_ICON_NAMES = sword, dagger,
blunt, ranged, katana, spear; ot6_contract.lua's ULTROS2 codex witness reads the ROM's row.

The holder rule (owner: "we don't want just one particular character to be required to get through fights"): at
every story stage, a species' weapon keys must be really held by at least two characters the player can field
there, or by one the story forces into the party (split.py HOLDERS step, stages.py). Dragoon Boots letting their
wearer equip a spear is another branch's (wt/v051-dragoon-spear, #567): do not build on it.

Still to come: the opening (Narshe mines through the Narshe defense, then Kohlingen and Zozo) is being authored by
hand, so those species' rows will move once more. `python3 tools/six_classes/split.py --report-only` prints the
current rows and reasons.
