#!/usr/bin/env python3
"""pins.py -- the split's authored data (#566).

PIN: for a species, the weapon KIND (classes.py KIND_CLASS) a four-class
weakness is keyed by, and where that is written.  A source starting "wob" is
a World of Balance break story (docs/design/bosses-wob.md by its v0.50 line,
or the other WoB design docs) and binds; one starting "row" is the four-class
Ot6ShieldTbl row's own comment and only prefers.

OPENING: for every species of the opening (docs/design/opening.md), the whole
row by weapon kinds, authored by hand; its sources start "opening" and it
binds before everything else, PIN included.

Kinds, not classes, so a regrouping of the classes moves the pins with the
weapons."""
S, P, B, X = 1, 2, 4, 8

PIN = {
    0x000c: ({X: 'brush'}, "row 'take special too, so Relm's brushes key them'"),
    0x0021: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x0025: ({X: 'brush'}, "row 'the point or the brush'"),
    0x002b: ({X: 'brush'}, "row 'relm's brush'"),
    0x002c: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x0031: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x0041: ({P: 'crossbow'}, "row 'pierce so Edgar's AutoCrossbow ... answers a five-stack'"),
    0x0045: ({S: 'katana'}, "row block 'his katana (slash) keys every body here' (Cyan's)"),
    0x0048: ({P: 'crossbow', B: 'fist'}, "row 'AutoCrossbow sweeps the stack, fists crack the shell'"),
    0x004a: ({X: 'brush'}, "row 'take special too, so Relm's brushes key them'"),
    0x004c: ({P: 'star'}, "row 'shadow's throw (pierce)'"),
    0x0051: ({S: 'katana'}, "row block 'his katana (slash) keys every body here' (Cyan's)"),
    0x0057: ({S: 'katana'}, "row block 'his katana (slash) keys every body here' (Cyan's)"),
    0x0069: ({X: 'rod'}, "row block 'every body takes his rod' (Strago's)"),
    0x006b: ({X: 'card'}, "row 'setzer's cards'"),
    0x006d: ({S: 'katana'}, "row block 'his katana (slash) keys every body here' (Cyan's)"),
    0x0070: ({X: 'rod'}, "row block 'every body takes his rod' (Strago's)"),
    0x0072: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x0073: ({B: 'blitz'}, "row 'carried by the forced party (dagger/autocrossbow and Pummel)'"),
    0x0074: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x007e: ({B: 'fang'}, "row block 'The rows key bludgeon, so gau's fists ... break'"),
    0x008a: ({B: 'rod'}, "row 'a shell, strago's rod'"),
    0x008f: ({B: 'fang'}, "row block 'The rows key bludgeon, so gau's fists ... break'"),
    0x0091: ({P: 'crossbow'}, "row 'the autocrossbow sweeps the exoray x3'"),
    0x0098: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x009a: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x009c: ({P: 'spear'}, "row 'mog's spear unseats it'"),
    0x009d: ({P: 'tekmissile'}, "row 'the missile pierces' (Terra's TekMissile)"),
    0x00a4: ({X: 'brush'}, "row 'take special too, so Relm's brushes key them'"),
    0x00a5: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x00a6: ({S: 'katana'}, "row block 'his katana (slash) keys every body here' (Cyan's)"),
    0x00a7: ({P: 'crossbow'}, "row 'the autocrossbow cracks six in two sweeps'"),
    0x00aa: ({P: 'crossbow', B: 'blitz'}, "wob docs: Grenade, 'edgar's tools (pierce) and sabin's blitzes (bludgeon)'"),
    0x00ae: ({S: 'sword'}, "wob docs: Gigantos, 'the landing party's three blades hold the key' (Terra, Locke, Edgar's swords)"),
    0x00b2: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x00b5: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x00b7: ({X: 'brush'}, "row 'cut it or a brush'"),
    0x00b8: ({X: 'rod'}, "row 'relm's brush the ooze's' "),
    0x00bb: ({B: 'fang'}, "row block 'The rows key bludgeon, so gau's fists ... break'"),
    0x00be: ({X: 'brush'}, "row 'steel or a brush'"),
    0x00c0: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x00c2: ({S: 'sword'}, "row 'the banquet's sparring troopers: terra and locke's blades'"),
    0x00c8: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x00ca: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x00d0: ({B: 'rod'}, "row 'strago's rod is the key the blades lack (the shell ...)'"),
    0x00d1: ({B: 'blitz'}, "row 'carried by the forced party (dagger/autocrossbow and Pummel)'"),
    0x00d2: ({X: 'brush'}, "row 'relm's brush keys it the day she joins'"),
    0x00d3: ({S: 'sword', X: 'card'}, "row 'the blade for the trio, and setzer's cards'"),
    0x00d5: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x00db: ({S: 'sword', B: 'fist'}, "row 'the blade and the fist' (Celes, Sabin)"),
    0x00e1: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x00e5: ({X: 'card'}, "row 'special for a Setzer brought along'"),
    0x00e6: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x00f7: ({P: 'spear'}, "row 'mog's spear for the half with no holy'"),
    0x0102: ({P: 'dagger'}, "wob docs: Mega Armor, 'Locke's daggers keyed pierce'"),
    0x0108: ({S: 'sword'}, "wob L848 'Celes ... her sword into Shiva'"),
    0x0109: ({P: 'dagger'}, "wob docs: Ifrit, 'Every Facility boss is class-breakable by Locke and Celes' (Locke's daggers)"),
    0x010a: ({S: 'sword', P: 'dagger'}, "wob docs: Number 024, 'class-breakable by Locke and Celes'"),
    0x010b: ({P: 'dagger'}, "wob docs: Number 128, 'class-breakable by Locke and Celes' (Celes is separated: Locke's daggers)"),
    0x010d: ({P: 'dagger'}, "wob docs: Left Crane, 'class-breakable by Locke and Celes' (Locke's daggers)"),
    0x010e: ({P: 'dagger'}, "wob docs: Right Crane, 'class-breakable by Locke and Celes' (Locke's daggers)"),
    0x0113: ({P: 'crossbow'}, "wob docs: AirForce, 'Edgar's AutoCrossbow keyed pierce on every part'"),
    0x0116: ({P: 'dagger'}, 'wob L958 party Terra, Locke, Strago: their pierce is a dagger'),
    0x0118: ({S: 'sword', P: 'dagger'}, "wob L1141 'LOCKE's Genji pair (ThunderBlade, slash + bolt; Assassin, pierce)'"),
    0x0119: ({B: 'fang'}, "row block 'The rows key bludgeon, so gau's fists ... break'"),
    0x0122: ({X: 'brush'}, "row 'steel or a brush'"),
    0x0123: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x0124: ({S: 'katana'}, "row block 'his katana (slash) keys every body here' (Cyan's)"),
    0x0126: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x0138: ({S: 'katana'}, "row block 'his katana (slash) keys every body here' (Cyan's)"),
    0x0144: ({P: 'spear'}, "row 'blades and the spear chip'"),
    0x0145: ({P: 'crossbow'}, "wob docs: Laser Gun, 'Edgar's AutoCrossbow keyed pierce on every part'"),
    0x0147: ({P: 'crossbow'}, "wob docs: MissileBay, 'Edgar's AutoCrossbow keyed pierce on every part'"),
    0x0149: ({P: 'spear'}, "row 'mog's spear is the class key'"),
    0x014b: ({S: 'katana'}, "row 'cyan's quadra slam chips four a turn'"),
    0x0152: ({S: 'katana'}, "row block 'his katana (slash) keys every body here' (Cyan's)"),
    0x0153: ({P: 'spear'}, "row 'mog's spear between the scales'"),
    0x0160: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x0161: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x0162: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x0167: ({X: 'brush'}, "row 'the brush, or celes's ice'"),
    0x016d: ({S: 'sword'}, "row 'terra morphed ... slash is her blade's key'"),
    0x0173: ({S: 'sword'}, "row 'SLASH is Leo's sword'"),
}

# ---- the opening, authored by hand (#566; docs/design/opening.md) -----------
# Every species the game deals from the Narshe mines through the Narshe
# defense, then Kohlingen and Zozo: the WHOLE row, by the weapon kinds of the
# hands that really meet it (the weapons the characters join with,
# ff6/src/field/char_prop.asm, and the first shops' obvious buys; not the
# automated route's hands, which strip Mog's pike for Edgar).  A row here
# binds and replaces the species' PIN entry; it may change the number of
# weaknesses or name a class that is no child of the old one, and split.py's
# report says where ("OPENING DEPARTS").  The reasons are opening.md's, one
# line each here.  Kinds, not classes, as above.
OPENING = {
    # 1. the mines in Magitek armor: TERRA's TekMissile is the armor's one weapon key
    0x0000: (('tekmissile',), "opening 1: guard, the TekMissile probe (Bio Blast's poison is the element)"),
    0x0134: (('tekmissile',), "opening 1: Whelk's head, 'three beams and a TekMissile' (bosses-wob.md 1)"),
    # the Lobo and the Vomammoth are the armor's (fire beams), then the moogle defense's, and the Lobo is the
    # school's practice chest (TERRA and LOCKE, two daggers)
    0x0019: (('dagger', 'spear'), "opening 1,3,4: lobo; the old pierce was LOCKE's dirk and the moogles' pikes, "
             "two classes now, and the school's practice chest meets it with two daggers"),
    0x001b: (('sword', 'flail'), "opening 3: vomammoth; every moogle squad holds a flail or a brush, two of the "
             "three a sword"),
    # 2. TERRA alone in the mines: a Mithril Knife and Fire
    0x0013: (('dagger', 'sword'), "opening 2: were-rat; TERRA's knife alone, her sword when BANON's party returns"),
    0x004d: (('dagger', 'sword'), "opening 2: repo man; the body her Fire does not key, so the knife must"),
    0x0046: (('dagger', 'rod'), "opening 2: vaporite; her knife or her Fire, BANON's rod later, SABIN's fists on "
             "Mt. Kolts"),
    # 3. the moogle defense: LOCKE's dirk and every weapon class on the field
    0x0064: (('dagger', 'spear'), "opening 3: marshal; 'moogle spears chip him' and LOCKE's dirk did under pierce "
             "(bosses-wob.md 2): both classes, so the thief the player controls holds a key on the boss"),
    # 4. TERRA and LOCKE, two daggers: the plains and the Figaro desert
    0x0017: (('dagger', 'sword'), "opening 4: leafer, the first body on the world map; two daggers meet it, so it "
             "takes one (Dagger is no child of slash|bludgeon)"),
    0x0028: (('dagger', 'crossbow'), "opening 4: dark wind, a flier: the point or the bolt (the fliers' rule)"),
    0x005c: (('dagger',), "opening 4: sand ray; the desert has no fire weakness, so the knives are the key; one "
             "class, since its three elements leave the HUD's four cells one"),
    0x005d: (('dagger',), "opening 4: areneid; on main two daggers had no key at all on the x3 pack "
             "(slash|bludgeon, ice|water); Dagger is no child of those, and its three elements leave one cell"),
    # 5. Figaro: EDGAR joins with a Mithril Blade and the AutoCrossbow
    0x0042: (('dagger', 'crossbow'), "opening 5: m-tekarmor; the knives and the AutoCrossbow's sweep, his first fight"),
    # 6. the cave to South Figaro: the cell splits the hands
    0x002e: (('dagger', 'crossbow'), "opening 6: hornet, a flier and a pest: anyone's point or the sweep"),
    0x0063: (('dagger',), "opening 6: bleary, an eye: the knives (TERRA, LOCKE), not EDGAR's blade"),
    0x0062: (('sword', 'fist'), "opening 6: crawly, a soft worm: EDGAR's blade, not the knives"),
    # 7. the plains round South Figaro (and the Returners' side of Mt. Kolts)
    0x00a8: (('dagger', 'fist'), "opening 7: greasemonk; LOCKE's dagger, then SABIN's fists the day he joins"),
    0x0012: (('sword', 'dagger'), "opening 7: rhodox, everybody's body: the blades and the dagger"),
    0x0015: (('crossbow', 'fist'), "opening 7: rhinotaur, the plains' tank: the bolt goes in (no pike in a new "
             "player's hands), fists stagger it"),
    # 8. Mt. Kolts and Vargas: TERRA has a sword from South Figaro's shop
    0x0086: (('dagger', 'crossbow'), "opening 8: cirpius, the flier that is 94% of the first maps' draws: the old "
             "pierce was LOCKE's dagger and EDGAR's bolts, two classes now"),
    0x007a: ((), "opening 8: tusker: no weapon weakness, as on main; Fire or the Bio Blaster"),
    0x0032: (('sword', 'dagger'), "opening 8: trilium: cut the stalk or stab it"),
    0x000b: (('sword', 'knuckle'), "opening 8: brawler: the blades (it drinks the Bio Blaster's poison), and "
             "SABIN's fists: the first two maps he walks deal it, and his MetalKnuckle, a slash on main, keyed it"),
    0x014d: (('sword',), "opening 8: ipooh: 'fire + slashing' (bosses-wob.md 3), TERRA's and EDGAR's swords"),
    0x0103: (('blitz',), "opening 8: vargas: 'not breakable without the monk'; SABIN's Pummel and now his "
             "MetalKnuckle too"),
    # 9. the Lete River: TERRA, EDGAR, SABIN, BANON
    0x0038: (('crossbow', 'rod'), "opening 9: nautiloid: a bolt in its mouth or a blow on the shell"),
    0x0039: (('sword', 'rod'), "opening 9: exocite: the blades, the fists, BANON's rod"),
    0x0022: (('sword', 'crossbow'), "opening 9: pterodon, a flier: the blades or the bolt"),
    0x012c: (('sword', 'crossbow'), "opening 9: ultros, 'the row he keeps all game': the Lete's party holds two "
             "swords and the AutoCrossbow (no pike, no dagger); fire and bolt take the other two cells"),
    # 10a. TERRA, EDGAR and BANON to Narshe: the raft again, the mines, the back way and its trap
    0x00ef: (('crossbow', 'rod'), "opening 10a: 1st class, a guard in plate: the bolt or BANON's rod"),
    0x00f4: (('sword', 'dagger'), "opening 10a: wild rat: a rat's row (the were-rat's)"),
    0x0060: (('sword', 'crossbow'), "opening 10a: dark side (the checkpoint's trap): the blades or the bolt; not "
             "BANON's rod, which has the other two ('one spirit to each hand')"),
    0x00b6: (('rod', 'crossbow'), "opening 10a: spectre (the trap): BANON's rod, EDGAR's bolts"),
    0x00cf: (('crossbow', 'rod'), "opening 10a: rinn (the trap's x3): the sweep, or the rod"),
    # 10b. LOCKE alone in South Figaro, then with CELES
    0x013a: (('dagger',), "opening 10b: merchant: LOCKE alone"),
    0x0175: (('dagger',), "opening 10b: officer: LOCKE alone"),
    0x009f: (('dagger',), "opening 10b, 11: heavyarmor: LOCKE alone (the seam); one class, since bolt, water "
             "and poison leave the HUD's four cells one"),
    0x0071: (('sword', 'dagger'), "opening 10b: vector pup: LOCKE's dagger, CELES's blade"),
    0x0011: (('sword', 'dagger'), "opening 10b: commander: the same two"),
    0x0036: (('dagger', 'fist'), "opening 10b: trilobiter, a shell: LOCKE's point, or CELES's bare hands (she "
             "joins unarmed)"),
    0x0094: (('sword', 'fist'), "opening 10b: primordite, a soft body: CELES's blade"),
    0x00f5: (('sword', 'fist'), "opening 10b: gold bear, the cave's tank: 'the bear only the blade'"),
    0x0104: (('thief hit',), "opening 10b: tunnelarmor: Trickshot and his dagger; CELES's key is Ice "
             "(bosses-wob.md 5)"),
    # 10c. SABIN's scenario: alone (a hired SHADOW is optional), then CYAN, then GAU
    0x0076: (('katana', 'knuckle'), "opening 10c: rhobite: SABIN's fists alone, CYAN's katana later"),
    0x0029: (('katana', 'star'), "opening 10c: beakor, a flier: the katana or a thrown star; the one body east "
             "of the Lete SABIN alone cannot key"),
    0x002f: (('ninja blade', 'knuckle'), "opening 10c: crasshoppr: fists, or SHADOW's blade"),
    0x0018: (('ninja blade', 'knuckle'), "opening 10c: stray cat: SABIN alone holds only Blunt (his MetalKnuckle "
             "slashed on main), so it takes it; Blunt is no child of slash|pierce"),
    0x0001: (('katana', 'knuckle'), "opening 10c: soldier: CYAN's duel (katana), SABIN at the camp (fists); "
             "Blunt is no child of slash|pierce, and SHADOW's point is optional"),
    0x0002: (('ninja blade', 'knuckle'), "opening 10c: templar: the old pierce was only SHADOW's, an optional "
             "hire; his blade in hand keeps it and SABIN's fists dent the plate"),
    0x001a: (('ninja blade', 'knuckle'), "opening 10c: doberman: as the templar; a x3 pack of 465 HP with no key "
             "for SABIN alone was the camp's slog"),
    0x0044: (('knuckle', 'ninja blade'), "opening 10c: telstar: 'bolt, water + bludgeoning' (bosses-wob.md 6-7), and "
             "SHADOW's blade (2026-11-24, the coordinator: the camp's pair, SABIN and SHADOW, could not break 4 shields "
             "with SABIN's blows alone; a key SHADOW really holds makes the race real; four HUD cells)"),
    0x014e: (('katana',), "opening 10c: leader: CYAN's solo duel"),
    0x014f: (('katana', 'knuckle'), "opening 10c: grunt: CYAN and SABIN at the camp"),
    0x0176: (('katana', 'knuckle'), "opening 10c: cadet: the same two, a bigger body"),
    0x005a: (('katana', 'knuckle'), "opening 10c: ghost (the forest): the katana, the fists, AuraBolt's holy"),
    0x00a2: (('ninja blade', 'katana'), "opening 10c: poplium: the katana, or SHADOW's blade"),
    0x000e: (('katana', 'knuckle'), "opening 10c: whisper (the train): 'holy + slash featured'"),
    0x0008: (('katana', 'knuckle'), "opening 10c: hazer: the same"),
    0x00ba: (('katana', 'knuckle'), "opening 10c: stillgoing: 'the walking body takes SABIN's fists'"),
    0x004f: (('katana', 'star'), "opening 10c: bomb: the katana or a star; not fists, not Fire"),
    0x000f: (('katana', 'star'), "opening 10c: over-mind: the katana or a star"),
    0x0131: (('ninja blade', 'katana', 'knuckle'), "opening 10c: siegfried: one shield any hand of the three breaks"),
    0x0156: (('katana', 'knuckle'), "opening 10c: specter (the train's chest)"),
    0x0106: (('blitz',), "opening 10c: ghosttrain: Pummel and SABIN's knuckle; 'CYAN cannot chip his own "
             "scenario's boss' (bosses-wob.md 8)"),
    0x0154: (('katana', 'knuckle'), "opening 10c: piranha: both hands at the falls"),
    0x0155: (('katana', 'knuckle'), "opening 10c: rizopas: 'both weapons match the row' (bosses-wob.md 9)"),
    0x003a: (('katana',), "opening 10c: anguiform (the trench): cut by CYAN's blade"),
    0x005e: (('blitz',), "opening 10c: actaneon: cracked by SABIN's fists and Blitzes"),
    0x0059: (('fang',), "opening 10c: aspik: GAU's fangs, the trench's third key for its third member (his bare "
             "hand was bludgeon on main; Dagger is no child of bludgeon)"),
    # 11. the Narshe defense: seven in three squads
    0x0065: (('sword', 'dagger', 'katana'), "opening 11: trooper: the player forms the three squads freely, so "
             "a raider takes the hands of all but two of the seven: swords, daggers and fangs, the katana"),
    0x0079: (('sword', 'dagger', 'katana'), "opening 11: bounty man: 'a raider should take the troopers' keys'"),
    0x001c: (('sword', 'dagger', 'katana'), "opening 11: fidor: 'a raider should take the troopers' keys'"),
    0x003f: (('dagger', 'katana'), "opening 11: rider: 'slash for CYAN/SABIN, pierce for LOCKE/GAU' "
             "(bosses-wob.md, the soldier line); TERRA's Fire, EDGAR's poison"),
    0x014a: (('sword', 'dagger'), "opening 11: kefka: 'any squad you route to him can break him' "
             "(bosses-wob.md 10): TERRA's, CELES's and EDGAR's swords, LOCKE's dagger, GAU's fangs; fire and poison "
             "take the other two cells, so the katana has none"),
    # 12. Kohlingen and Zozo: any four of LOCKE, EDGAR, SABIN, CYAN, GAU, CELES
    0x0078: (('katana', 'spear'), "opening 12: red fang, a wolf: CYAN's katana, EDGAR's pike or Drill"),
    0x002a: (('dagger', 'crossbow'), "opening 12: vulture, a flier: the fliers' rule; one class would have one "
             "real holder (the holder rule)"),
    0x0090: (('katana', 'knuckle'), "opening 12: over grunk, the plains' tank: the katana or a blow"),
    0x008c: (('sword', 'crossbow'), "opening 12: mind candy: the blades, and the sweep for the x4 swarm (SETZER's "
             "cards later)"),
    0x006c: (('knuckle', 'crossbow'), "opening 12: iron fist: 'AoE piercing (AutoCrossbow)' on Dadaluma's adds "
             "(bosses-wob.md 11), and SABIN's fists"),
    0x0023: (('drill', 'knuckle'), "opening 12: fossilfang, the rare tank: EDGAR's new Drill (or a pike), or a blow "
             "on the bones"),
    0x00df: (('dagger', 'crossbow'), "opening 12: gabbldegak, the x4 swarm: 'AutoCrossbow sweeps it', and daggers "
             "and fangs; Dagger alone has no real holder in the World of Ruin's Zozo (the holder rule)"),
    0x0052: (('sword', 'katana'), "opening 12: slamdancer, the dangerous one: the blades, CELES's and CYAN's "
             "(and a curved sword's: Katana since 2026-11-24; SABIN's claw is Dagger now); both are slash's"),
    0x004e: (('sword', 'drill'), "opening 12: harvester: a blade or a spear"),
    0x0053: (('knuckle', 'crossbow'), "opening 12: hadesgigas: Blunt alone had one real holder (SABIN: GAU's hand "
             "left bludgeon), so the giant takes the bolt too (the holder rule)"),
    0x0107: (('dagger', 'blitz'), "opening 12: dadaluma: 'every possible pick of four holds at least one of the "
             "two classes' (bosses-wob.md 11): LOCKE, GAU and SABIN are three of the six"),
}

# the two rows whose story is "any weapon breaks it" (bosses-wob.md L1051
# Speck: "any weapon in the game breaks it"; wob-side-trips.md Intangir:
# "every class breaks it"): they took all four classes and take all six, the
# one place a species' number of weapon weaknesses changes (4 -> 6)
EVERY = {0x00a3, 0x0146}

# Ultros 2, 3, 4 take Ultros 1's row ("the row he keeps all game")
FAMILY = {0x012d: 0x012c, 0x012e: 0x012c, 0x0168: 0x012c}

# ---- the break-row suites' proofs (pins_suite.py): each binds, weakness by
# weakness (HARD), over whatever a row comment preferred
import pins_suite as _suite  # noqa: E402

HARD = {}
for _sp, (_kinds, _src) in _suite.SUITE.items():
    _old = PIN.get(_sp, ({}, ""))
    _merged = dict(_old[0])
    _merged.update(_kinds)
    PIN[_sp] = (_merged, _old[1] + (" || " if _old[1] else "") + _src)
    HARD[_sp] = set(_kinds)
EVERY |= set(_suite.EVERY)
# a weakness a row gains beyond its four-class count ({species: [kind, ...]}),
# where a design statement cannot be kept on the old count; each with its reason
ADD = dict(getattr(_suite, "ADD", {}))
