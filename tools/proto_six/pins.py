#!/usr/bin/env python3
"""pins.py -- the split's authored data (#566): for a species, the weapon KIND
(classes.py KIND_CLASS) a four-class weakness is keyed by, and where that is
written.  A source starting "wob" is a World of Balance break story
(docs/design/bosses-wob.md by its v0.50 line, or the other WoB design docs)
and binds; one starting "opening" is the hand-authored opening (opening.py)
and binds; one starting "row" is the four-class Ot6ShieldTbl row's own comment
and only prefers.  Kinds, not classes, so a regrouping of the classes moves
the pins with the weapons."""
S, P, B, X = 1, 2, 4, 8

PIN = {
    0x0000: ({P: 'tekmissile'}, "row 'armored infantry, the tekmissile probe'"),
    0x0001: ({S: 'katana', P: 'star'}, "wob L689 'Cyan duel (slash)', '(Shadow pierce)'"),
    0x0002: ({P: 'star'}, "wob L690 'Shadow throw / Bolt Edge'"),
    0x0008: ({S: 'katana'}, "row 'the phantom train: cyan's katana'"),
    0x000b: ({S: 'sword'}, "row 'except edgar's mithril blade'"),
    0x000c: ({X: 'brush'}, "row 'take special too, so Relm's brushes key them'"),
    0x000e: ({S: 'katana'}, "row 'the phantom train: cyan's katana'"),
    0x0011: ({P: 'dagger', S: 'sword'}, "row 'locke's daggers pierce, celes's blade slashes'"),
    0x0015: ({P: 'spear', B: 'fist'}, "row 'the pike goes in, fists stagger it'"),
    0x001a: ({P: 'star'}, "wob L345 party Sabin and Shadow: their pierce is Shadow's Throw"),
    0x001c: ({P: 'dagger'}, "row 'every raider takes the troopers' keys'"),
    0x0021: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x0022: ({S: 'sword', P: 'spear', B: 'rod'}, "row 'terra's blade, edgar's pike, banon's rod'"),
    0x0025: ({X: 'brush'}, "row 'the point or the brush'"),
    0x002b: ({X: 'brush'}, "row 'relm's brush'"),
    0x002c: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x0031: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x0036: ({P: 'dagger'}, "row 'locke's daggers pierce, celes's blade slashes'"),
    0x0038: ({S: 'sword', P: 'spear', B: 'rod'}, "row 'a point in its mouth or a rod on the shell'"),
    0x0039: ({S: 'sword', P: 'spear', B: 'rod'}, "row 'terra's blade, edgar's pike, banon's rod'"),
    0x003a: ({S: 'katana'}, "wob L759 'cut by Cyan's blade'"),
    0x003f: ({P: 'dagger'}, "wob L696 'ditto'"),
    0x0041: ({P: 'crossbow'}, "row 'pierce so Edgar's AutoCrossbow ... answers a five-stack'"),
    0x0044: ({B: 'fist'}, 'wob L345 party Sabin (Shadow drifting): their bludgeon is his fists'),
    0x0045: ({S: 'katana'}, "row block 'his katana (slash) keys every body here' (Cyan's)"),
    0x0046: ({P: 'dagger'}, "row 'terra's knife or her fire'"),
    0x0048: ({P: 'crossbow', B: 'fist'}, "row 'AutoCrossbow sweeps the stack, fists crack the shell'"),
    0x004a: ({X: 'brush'}, "row 'take special too, so Relm's brushes key them'"),
    0x004c: ({P: 'star'}, "row 'shadow's throw (pierce)'"),
    0x0051: ({S: 'katana'}, "row block 'his katana (slash) keys every body here' (Cyan's)"),
    0x0057: ({S: 'katana'}, "row block 'his katana (slash) keys every body here' (Cyan's)"),
    0x0059: ({B: 'fist'}, "wob L761 'crushed by a monk's fists'"),
    0x005e: ({B: 'fist'}, "wob L760 'cracked by Sabin's fists'"),
    0x0060: ({S: 'sword', P: 'spear'}, "row 'the same three; one spirit to each hand'"),
    0x0064: ({P: 'spear'}, "wob L179 'Moogle spears chip him steadily'; row 'mog's fight, mog's class'"),
    0x0065: ({P: 'dagger'}, "wob L695 'pierce for Locke/Gau' (the slash half follows the squad the route fights it with)"),
    0x0069: ({X: 'rod'}, "row block 'every body takes his rod' (Strago's)"),
    0x006b: ({X: 'card'}, "row 'setzer's cards'"),
    0x006c: ({P: 'crossbow'}, "wob L798 'AoE piercing (AutoCrossbow)'"),
    0x006d: ({S: 'katana'}, "row block 'his katana (slash) keys every body here' (Cyan's)"),
    0x0070: ({X: 'rod'}, "row block 'every body takes his rod' (Strago's)"),
    0x0071: ({P: 'dagger', S: 'sword'}, "row 'locke's daggers pierce, celes's blade slashes'"),
    0x0072: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x0073: ({B: 'blitz'}, "row 'carried by the forced party (dagger/autocrossbow and Pummel)'"),
    0x0074: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x0079: ({P: 'dagger'}, "row 'every raider takes the troopers' keys'"),
    0x007e: ({B: 'fang'}, "row block 'The rows key bludgeon, so gau's fists ... break'"),
    0x008a: ({B: 'rod'}, "row 'a shell, strago's rod'"),
    0x008c: ({X: 'card'}, "row 'setzer's cards'"),
    0x008f: ({B: 'fang'}, "row block 'The rows key bludgeon, so gau's fists ... break'"),
    0x0091: ({P: 'crossbow'}, "row 'the autocrossbow sweeps the exoray x3'"),
    0x0094: ({S: 'sword'}, "row 'locke's daggers pierce, celes's blade slashes'"),
    0x0098: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x009a: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x009c: ({P: 'spear'}, "row 'mog's spear unseats it'"),
    0x009d: ({P: 'tekmissile'}, "row 'the missile pierces' (Terra's TekMissile)"),
    0x009f: ({P: 'dagger'}, "wob L697 'Locke SOLO (pierce)'"),
    0x00a4: ({X: 'brush'}, "row 'take special too, so Relm's brushes key them'"),
    0x00a5: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x00a6: ({S: 'katana'}, "row block 'his katana (slash) keys every body here' (Cyan's)"),
    0x00a7: ({P: 'crossbow'}, "row 'the autocrossbow cracks six in two sweeps'"),
    0x00aa: ({P: 'crossbow', B: 'blitz'}, "wob docs: Grenade, 'edgar's tools (pierce) and sabin's blitzes (bludgeon)'"),
    0x00ae: ({S: 'sword'}, "wob docs: Gigantos, 'the landing party's three blades hold the key' (Terra, Locke, Edgar's swords)"),
    0x00b2: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x00b5: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x00b6: ({X: 'rod'}, "row 'banon's rod' "),
    0x00b7: ({X: 'brush'}, "row 'cut it or a brush'"),
    0x00b8: ({X: 'rod'}, "row 'relm's brush the ooze's' "),
    0x00ba: ({S: 'katana'}, "row 'the phantom train: cyan's katana'"),
    0x00bb: ({B: 'fang'}, "row block 'The rows key bludgeon, so gau's fists ... break'"),
    0x00be: ({X: 'brush'}, "row 'steel or a brush'"),
    0x00c0: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x00c2: ({S: 'sword'}, "row 'the banquet's sparring troopers: terra and locke's blades'"),
    0x00c8: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x00ca: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x00cf: ({P: 'spear'}, "row 'edgar's pike'"),
    0x00d0: ({B: 'rod'}, "row 'strago's rod is the key the blades lack (the shell ...)'"),
    0x00d1: ({B: 'blitz'}, "row 'carried by the forced party (dagger/autocrossbow and Pummel)'"),
    0x00d2: ({X: 'brush'}, "row 'relm's brush keys it the day she joins'"),
    0x00d3: ({S: 'sword', X: 'card'}, "row 'the blade for the trio, and setzer's cards'"),
    0x00d5: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x00db: ({S: 'sword', B: 'fist'}, "row 'the blade and the fist' (Celes, Sabin)"),
    0x00df: ({P: 'crossbow'}, "row 'AutoCrossbow sweeps it'"),
    0x00e1: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x00e5: ({X: 'card'}, "row 'special for a Setzer brought along'"),
    0x00e6: ({S: 'sword'}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'"),
    0x00f5: ({S: 'sword'}, "row 'the bear only the blade'"),
    0x00f7: ({P: 'spear'}, "row 'mog's spear for the half with no holy'"),
    0x0102: ({P: 'dagger'}, "wob docs: Mega Armor, 'Locke's daggers keyed pierce'"),
    0x0103: ({B: 'blitz'}, "wob L215 'Pummel ... reveals the bludgeon class'"),
    0x0104: ({P: 'dagger'}, "wob L337 'Mug and daggers chip with piercing'"),
    0x0106: ({B: 'blitz'}, "wob L415 'Pummel x2 chips repeatedly', L408 'Suplexes first'"),
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
    0x012c: ({S: 'sword'}, 'wob L290 party Terra, Locke, Edgar, Sabin, Banon: their slash is a sword'),
    0x0134: ({P: 'tekmissile'}, "wob L151 'Three beams and a TekMissile': the Magitek party's one class key"),
    0x0138: ({S: 'katana'}, "row block 'his katana (slash) keys every body here' (Cyan's)"),
    0x013a: ({P: 'dagger'}, "row 'Locke solo disguise fight'"),
    0x013f: ({S: 'sword'}, "wob docs: Number 128's blades, the facility party's swords"),
    0x0140: ({S: 'sword'}, "wob docs: Number 128's blades, the facility party's swords"),
    0x0144: ({P: 'spear'}, "row 'blades and the spear chip'"),
    0x0145: ({P: 'crossbow'}, "wob docs: Laser Gun, 'Edgar's AutoCrossbow keyed pierce on every part'"),
    0x0147: ({P: 'crossbow'}, "wob docs: MissileBay, 'Edgar's AutoCrossbow keyed pierce on every part'"),
    0x0149: ({P: 'spear'}, "row 'mog's spear is the class key'"),
    0x014b: ({S: 'katana'}, "row 'cyan's quadra slam chips four a turn'"),
    0x014d: ({S: 'sword'}, 'wob L202 party Terra, Locke, Edgar: their slash is a sword'),
    0x014e: ({S: 'katana'}, "wob L691 'Cyan SOLO Doma duel'"),
    0x014f: ({S: 'katana', B: 'fist'}, "wob L692 '(Cyan slash + Sabin bludg)'"),
    0x0152: ({S: 'katana'}, "row block 'his katana (slash) keys every body here' (Cyan's)"),
    0x0153: ({P: 'spear'}, "row 'mog's spear between the scales'"),
    0x0154: ({S: 'katana', B: 'fist'}, "wob L461 party Sabin + Cyan (Rizopas's school)"),
    0x0155: ({S: 'katana', B: 'blitz'}, "wob L497 'CYAN ... Ashura (katana: slash)', L529 'Pummel (2 bludgeoning hits)'"),
    0x0156: ({S: 'katana'}, "row 'cyan's blade cuts it'"),
    0x0160: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x0161: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x0162: ({B: 'rod'}, "row block 'every body takes his rod (bludgeon)' (Strago's)"),
    0x0167: ({X: 'brush'}, "row 'the brush, or celes's ice'"),
    0x016d: ({S: 'sword'}, "row 'terra morphed ... slash is her blade's key'"),
    0x0173: ({S: 'sword'}, "row 'SLASH is Leo's sword'"),
    0x0175: ({P: 'dagger'}, "wob L694 'Locke SOLO ... the thief's dagger finds the seam'"),
    0x0176: ({S: 'katana', B: 'fist'}, "wob L693 'Doma defense (same two)'"),
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
