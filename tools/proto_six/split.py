#!/usr/bin/env python3
"""split.py -- the six-class prototype's split of every species' weapon
weaknesses (#566), from v0.50's four classes.

Each v0.50 weakness becomes one of its class's two children, so a species
keeps the NUMBER of weapon weaknesses it had:

    slash    -> Sword  or Katana
    pierce   -> Dagger or Spear
    bludgeon -> Fist   or Arcane
    special  -> Arcane or Dagger

(Special's second child is Dagger: the special holders' own second family --
Setzer's Darts, Relm's and Strago's knives -- so a card, dice or brush
wielder can still put the key in hand where the split took it from Arcane.)

The rule, in order:
  1. PINNED: where docs/design/bosses-wob.md's break story or the v0.50 row's
     own comment names the member whose weapon or skill is the key (or the
     party it lists can hold only one of the two children), the weakness
     becomes that member's new class.  The table below, with its source.
  2. FAMILY: Ultros's four records share one row.
  3. BALANCE: every other weakness, in species-id order (slash, pierce,
     bludgeon, special within a species), goes to whichever of its two
     children fewer of the species the game deals (and gauges) hold so far;
     a tie takes the first-named child; a species never takes one class twice.
     Species no battle deals, and the generated floor's rows, follow the same
     rule after the dealt ones and do not count toward the balance.

Reads v0.50's ot6_hud.asm from git (so it is idempotent), rewrites the class
masks of Ot6ShieldTbl's rows in the working tree's ot6_hud.asm, writes
ff6/tools/six_class_split.json (species -> new mask and how it was chosen;
gen_break_floor.py reads the floor rows from it) and prints the report.

    python3 tools/proto_six/split.py [--report-only]
"""
import collections
import importlib.util
import itertools
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SLASH, PIERCE, BLUDG, SPECIAL = 1, 2, 4, 8
OLD = {"OT6_SLASH": SLASH, "OT6_PIERCE": PIERCE, "OT6_BLUDG": BLUDG, "OT6_SPECIAL": SPECIAL}
OLD_NAME = {SLASH: "slash", PIERCE: "pierce", BLUDG: "bludgeon", SPECIAL: "special"}
SWORD, DAGGER, FIST, ARCANE, KATANA, SPEAR = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20
NEW_NAME = {SWORD: "Sword", DAGGER: "Dagger", FIST: "Fist", ARCANE: "Arcane", KATANA: "Katana", SPEAR: "Spear"}
NEW_CONST = {SWORD: "OT6_SWORD", DAGGER: "OT6_DAGGER", FIST: "OT6_FIST", ARCANE: "OT6_ARCANE",
             KATANA: "OT6_KATANA", SPEAR: "OT6_SPEAR"}
ORDER = (SWORD, DAGGER, SPEAR, KATANA, FIST, ARCANE)       # the order masks are written in
CHILDREN = {SLASH: (SWORD, KATANA), PIERCE: (DAGGER, SPEAR), BLUDG: (FIST, ARCANE), SPECIAL: (ARCANE, DAGGER)}

# ---- 1. pinned ---------------------------------------------------------------
# species -> ({old class: new class}, source).  "wob" = docs/design/bosses-wob.md
# (v0.50 line), "row" = the v0.50 Ot6ShieldTbl row's or block's own comment.
S, P, B, X = SLASH, PIERCE, BLUDG, SPECIAL
PIN = {
    # bosses-wob.md, bosses and their adds
    0x0134: ({P: SPEAR}, "wob L151 'Three beams and a TekMissile': the Magitek party's one class key"),
    0x0000: ({P: SPEAR}, "row 'armored infantry, the tekmissile probe'"),
    0x0064: ({P: SPEAR}, "wob L179 'Moogle spears chip him steadily'; row 'mog's fight, mog's class'"),
    0x0103: ({B: FIST}, "wob L215 'Pummel ... reveals the bludgeon class'"),
    0x014d: ({S: SWORD}, "wob L202 party Terra, Locke, Edgar: their slash is a sword"),
    0x012c: ({S: SWORD}, "wob L290 party Terra, Locke, Edgar, Sabin, Banon: their slash is a sword"),
    0x0104: ({P: DAGGER}, "wob L337 'Mug and daggers chip with piercing'"),
    0x0044: ({B: FIST}, "wob L345 party Sabin (Shadow drifting): their bludgeon is his fists"),
    0x001a: ({P: DAGGER}, "wob L345 party Sabin and Shadow: their pierce is Shadow's Throw"),
    0x0106: ({B: FIST}, "wob L415 'Pummel x2 chips repeatedly', L408 'Suplexes first'"),
    0x0155: ({S: KATANA, B: FIST}, "wob L497 'CYAN ... Ashura (katana: slash)', L529 'Pummel (2 bludgeoning hits)'"),
    0x0154: ({S: KATANA, B: FIST}, "wob L461 party Sabin + Cyan (Rizopas's school)"),
    0x0001: ({S: KATANA, P: DAGGER}, "wob L689 'Cyan duel (slash)', '(Shadow pierce)'"),
    0x0002: ({P: DAGGER}, "wob L690 'Shadow throw / Bolt Edge'"),
    0x014e: ({S: KATANA}, "wob L691 'Cyan SOLO Doma duel'"),
    0x014f: ({S: KATANA, B: FIST}, "wob L692 '(Cyan slash + Sabin bludg)'"),
    0x0176: ({S: KATANA, B: FIST}, "wob L693 'Doma defense (same two)'"),
    0x0175: ({P: DAGGER}, "wob L694 'Locke SOLO ... the thief's dagger finds the seam'"),
    0x0065: ({P: DAGGER}, "wob L695 'pierce for Locke/Gau' (the slash half follows the squad the route fights it with)"),
    0x003f: ({P: DAGGER}, "wob L696 'ditto'"),
    0x009f: ({P: DAGGER}, "wob L697 'Locke SOLO (pierce)'"),
    0x003a: ({S: KATANA}, "wob L759 'cut by Cyan's blade'"),
    0x005e: ({B: FIST}, "wob L760 'cracked by Sabin's fists'"),
    0x0059: ({B: FIST}, "wob L761 'crushed by a monk's fists'"),
    0x006c: ({P: SPEAR}, "wob L798 'AoE piercing (AutoCrossbow)'"),
    0x0108: ({S: SWORD}, "wob L848 'Celes ... her sword into Shiva'"),
    0x0116: ({P: DAGGER}, "wob L958 party Terra, Locke, Strago: their pierce is a dagger"),
    0x0118: ({S: SWORD, P: DAGGER}, "wob L1141 'LOCKE's Genji pair (ThunderBlade, slash + bolt; Assassin, pierce)'"),
    # the v0.50 rows' own comments
    0x000b: ({S: SWORD}, "row 'except edgar's mithril blade'"),
    0x013a: ({P: DAGGER}, "row 'Locke solo disguise fight'"),
    0x0073: ({B: FIST}, "row 'carried by the forced party (dagger/autocrossbow and Pummel)'"),
    0x00d1: ({B: FIST}, "row 'carried by the forced party (dagger/autocrossbow and Pummel)'"),
    0x0041: ({P: SPEAR}, "row 'pierce so Edgar's AutoCrossbow ... answers a five-stack'"),
    0x0173: ({S: SWORD}, "row 'SLASH is Leo's sword'"),
    0x000c: ({X: ARCANE}, "row 'take special too, so Relm's brushes key them'"),
    0x00a4: ({X: ARCANE}, "row 'take special too, so Relm's brushes key them'"),
    0x004a: ({X: ARCANE}, "row 'take special too, so Relm's brushes key them'"),
    0x00df: ({P: SPEAR}, "row 'AutoCrossbow sweeps it'"),
    0x00e5: ({X: ARCANE}, "row 'special for a Setzer brought along'"),
    0x0048: ({P: SPEAR, B: FIST}, "row 'AutoCrossbow sweeps the stack, fists crack the shell'"),
    0x00aa: ({B: FIST}, "row 'sabin's blitzes (bludgeon)'"),
    0x00a3: ({X: ARCANE}, "row 'setzer's special among them'"),
    0x0046: ({P: DAGGER}, "row 'terra's knife or her fire'"),
    0x0015: ({P: SPEAR, B: FIST}, "row 'the pike goes in, fists stagger it'"),
    0x0011: ({P: DAGGER, S: SWORD}, "row 'locke's daggers pierce, celes's blade slashes'"),
    0x0071: ({P: DAGGER, S: SWORD}, "row 'locke's daggers pierce, celes's blade slashes'"),
    0x0094: ({S: SWORD}, "row 'locke's daggers pierce, celes's blade slashes'"),
    0x0036: ({P: DAGGER}, "row 'locke's daggers pierce, celes's blade slashes'"),
    0x00f5: ({S: SWORD}, "row 'the bear only the blade'"),
    0x0008: ({S: KATANA}, "row 'the phantom train: cyan's katana'"),
    0x000e: ({S: KATANA}, "row 'the phantom train: cyan's katana'"),
    0x00ba: ({S: KATANA}, "row 'the phantom train: cyan's katana'"),
    0x008c: ({X: ARCANE}, "row 'setzer's cards'"),
    0x006b: ({X: ARCANE}, "row 'setzer's cards'"),
    0x00d0: ({B: ARCANE}, "row 'strago's rod is the key the blades lack (the shell ...)'"),
    0x00b8: ({X: ARCANE}, "row 'relm's brush the ooze's' (the rod is Arcane too)"),
    0x0156: ({S: KATANA}, "row 'cyan's blade cuts it'"),
    0x00db: ({S: SWORD, B: FIST}, "row 'the blade and the fist' (Celes, Sabin)"),
    0x00a7: ({P: SPEAR}, "row 'the autocrossbow cracks six in two sweeps'"),
    0x00d3: ({S: SWORD, X: ARCANE}, "row 'the blade for the trio, and setzer's cards'"),
    0x0091: ({P: SPEAR}, "row 'the autocrossbow sweeps the exoray x3'"),
    0x016d: ({S: SWORD}, "row 'terra morphed ... slash is her blade's key'"),
    0x00d2: ({X: ARCANE}, "row 'relm's brush keys it the day she joins'"),
    0x014b: ({S: KATANA}, "row 'cyan's quadra slam chips four a turn'"),
    0x009c: ({P: SPEAR}, "row 'mog's spear unseats it'"),
    0x0144: ({P: SPEAR}, "row 'blades and the spear chip'"),
    0x0149: ({P: SPEAR}, "row 'mog's spear is the class key'"),
    0x002b: ({X: ARCANE}, "row 'relm's brush'"),
    0x008a: ({B: ARCANE}, "row 'a shell, strago's rod'"),
    0x00f7: ({P: SPEAR}, "row 'mog's spear for the half with no holy'"),
    0x0153: ({P: SPEAR}, "row 'mog's spear between the scales'"),
    0x009d: ({P: SPEAR}, "row 'the missile pierces' (Terra's TekMissile)"),
    0x004c: ({P: DAGGER}, "row 'shadow's throw (pierce)'"),
    0x0167: ({X: ARCANE}, "row 'the brush, or celes's ice'"),
    0x00be: ({X: ARCANE}, "row 'steel or a brush'"),
    0x0122: ({X: ARCANE}, "row 'steel or a brush'"),
    0x00b7: ({X: ARCANE}, "row 'cut it or a brush'"),
    0x0025: ({X: ARCANE}, "row 'the point or the brush'"),
    0x0022: ({S: SWORD, P: SPEAR, B: ARCANE}, "row 'terra's blade, edgar's pike, banon's rod'"),
    0x0038: ({S: SWORD, P: SPEAR, B: ARCANE}, "row 'a point in its mouth or a rod on the shell'"),
    0x0039: ({S: SWORD, P: SPEAR, B: ARCANE}, "row 'terra's blade, edgar's pike, banon's rod'"),
    0x0060: ({S: SWORD, P: SPEAR}, "row 'the same three; one spirit to each hand'"),
    0x00b6: ({X: ARCANE}, "row 'banon's rod' (Arcane; the bludgeon half goes to Fist)"),
    0x00cf: ({P: SPEAR}, "row 'edgar's pike'"),
    0x0079: ({P: DAGGER}, "row 'every raider takes the troopers' keys'"),
    0x001c: ({P: DAGGER}, "row 'every raider takes the troopers' keys'"),
    0x00c2: ({S: SWORD}, "row 'the banquet's sparring troopers: terra and locke's blades'"),
}
# the blocks whose comment keys every body to one member
for _sp in (0x0072, 0x00b2, 0x00d5, 0x0021, 0x0031, 0x0098, 0x00ca, 0x00e6, 0x00e1, 0x002c, 0x00c0):
    PIN[_sp] = ({S: SWORD}, "row block 'Celes is alone to Tzen and holds slash (every sword ...)'")
for _sp in (0x008f, 0x007e, 0x00bb, 0x0119):
    PIN[_sp] = ({B: FIST}, "row block 'The rows key bludgeon, so gau's fists ... break'")
for _sp in (0x0069, 0x0070):
    PIN[_sp] = ({X: ARCANE}, "row block 'every body takes his rod' (Strago's; the rod is Arcane)")
for _sp in (0x0074, 0x009a, 0x00a5, 0x00b5, 0x00c8, 0x0123, 0x0126, 0x0160, 0x0161, 0x0162):
    PIN[_sp] = ({B: ARCANE}, "row block 'every body takes his rod (bludgeon)' (Strago's)")
for _sp in (0x00a6, 0x006d, 0x0057, 0x0045, 0x0051, 0x0152, 0x0138, 0x0124):
    PIN[_sp] = ({S: KATANA}, "row block 'his katana (slash) keys every body here' (Cyan's)")

# ---- 2. families ---------------------------------------------------------------
FAMILY = {0x012d: 0x012c, 0x012e: 0x012c, 0x0168: 0x012c}      # Ultros 2, 3, 4 take Ultros 1's row


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


BASE = os.environ.get("OT6_SPLIT_BASE", "origin/main")       # the four-class tree
# the route's fights (route_fights.py over the qualification log main's play
# made); absent, the ROUTE step is skipped
FIGHTS = ROOT / "build/attempts/wt/proto-six-classes/route-fights-v050.json"
# a member's signature kit under six classes, by character id: the weapon
# family the member is built around and the class-bearing skills that come
# with them (EDGAR: spear and tools, and a sword, his other family and the
# Chain Saw's class; SHADOW: ninja blade and Throw; 14 BANON, 15 LEO)
ROUTE_KIT = {0: SWORD, 1: DAGGER, 2: KATANA, 3: KATANA | DAGGER, 4: SPEAR | SWORD, 5: FIST, 6: SWORD, 7: ARCANE,
             8: ARCANE, 9: ARCANE, 10: SPEAR, 11: FIST, 12: 0, 13: FIST, 14: ARCANE, 15: SWORD}


def v050(path, text=True):
    return subprocess.run(["git", "show", BASE + ":" + path], cwd=ROOT, check=True, capture_output=True,
                          text=text).stdout


def route_parties():
    """species -> [party kit mask, ...], one per route fight against it."""
    out = collections.defaultdict(list)
    if FIGHTS.exists():
        for f in json.loads(FIGHTS.read_text()):
            kit = 0
            for c in f["chars"]:
                kit |= ROUTE_KIT.get(c, 0)
            for sp in f["species"]:
                out[sp].append(kit)
    return out


def old_rows():
    """v0.50's Ot6ShieldTbl: {species: (shields, old mask)}, both halves."""
    csr = _load(ROOT / "tools/check_shield_rows.py", "csr")
    csr.CLASS_BIT = dict(OLD)
    rows = csr.parse_rows(v050(csr.HUD_ASM), "Ot6ShieldTbl", True)
    return csr, {sp: (sh, m & 15) for sp, sh, m, _ in rows}


def dealt(csr):
    src = csr.read_sources(str(ROOT))
    reach = csr.reachable_formations(src)
    held = set()
    for f in reach:
        held |= set(csr.formation_species(src["bm"], f))
    if 0x23F in reach:
        held |= set(src["colosseum_prop"])
    return held


def assign(masks, order, count, how, parties=None):
    """Split masks[sp] for each sp in order; count is the running tally the
    balance reads (updated only when `count` is not None).  Returns
    ({sp: new mask}, {sp: {old class: new class}})."""
    out, kids_of = {}, {}
    parties = parties or {}
    for sp in order:
        old = masks[sp]
        if sp in FAMILY and FAMILY[sp] in out:
            out[sp], kids_of[sp] = out[FAMILY[sp]], kids_of[FAMILY[sp]]
            how[sp] = "family of $%04x" % FAMILY[sp]
            for b in NEW_NAME:
                if count is not None and out[sp] & b:
                    count[b] += 1
            continue
        pin = {o: k for o, k in PIN.get(sp, ({}, None))[0].items() if old & o}
        olds = [o for o in (S, P, B, X) if old & o]
        tally = count if count is not None else collections.Counter()
        best = None
        for combo in itertools.product(*[(pin[o],) if o in pin else CHILDREN[o] for o in olds]):
            if len(set(combo)) != len(combo):
                continue                                # one class twice
            mask = sum(combo)
            nokey = sum(1 for kit in parties.get(sp, ()) if not kit & mask)
            key = (nokey, sum(tally[k] for k in combo),
                   tuple(CHILDREN[o].index(k) for o, k in zip(olds, combo)))
            if best is None or key < best[0]:
                best = (key, combo)
        assert best is not None, "species $%04x: no split satisfies its pins" % sp
        combo = best[1]
        fights = len(parties.get(sp, ()))
        notes = ["%s->%s%s" % (OLD_NAME[o], NEW_NAME[k], " pinned" if o in pin else "")
                 for o, k in zip(olds, combo)]
        if fights:
            notes.append("route: %d of %d fights keyless" % (best[0][0], fights))
        out[sp], kids_of[sp] = sum(combo), dict(zip(olds, combo))
        how[sp] = ", ".join(notes) or "none"
        if count is not None:
            for k in combo:
                count[k] += 1
    return out, kids_of


def compute():
    csr, rows = old_rows()
    held = dealt(csr)
    gbf = _load(ROOT / "ff6/tools/gen_break_floor.py", "gbf")
    names = gbf.load_names(str(ROOT / "ff6/src/text/monster_name_en.json"))
    gauged = sorted(sp for sp in held if rows.get(sp, (0, 0))[0] > 0)
    how, count = {}, collections.Counter()
    masks = {sp: m for sp, (sh, m) in rows.items()}
    parties = route_parties()
    new, kids = assign(masks, gauged, count, how, parties)
    final_count = collections.Counter(count)
    rest = sorted(sp for sp in rows if sp not in new)
    n2, k2 = assign(masks, rest, collections.Counter(count), how, parties)
    new.update(n2)
    kids.update(k2)
    # the floor: every species id's generated class (reached only by a species
    # with no Ot6ShieldTbl row), split by the same rule after the rows
    floor_old = {sp: gbf.classify(names[sp] if sp < len(names) else "")[0] for sp in range(gbf.CODEX_WIDTH)}
    fhow = {}
    floor, fkids = assign(floor_old, sorted(floor_old), collections.Counter(count), fhow)
    # what a four-class save's revealed bits mean, per species id: bit k set =
    # the weakness of four-class bit k became its SECOND child (Katana, Spear,
    # Arcane, Dagger).  A species with a row reads the row's split, any other
    # the floor's.
    sel = {}
    for sp in range(gbf.CODEX_WIDTH):
        m = kids.get(sp, fkids[sp])
        sel[sp] = sum(o for o, k in m.items() if CHILDREN[o].index(k) == 1)
    return dict(rows=rows, held=held, gauged=gauged, new=new, how=how, count=final_count, floor=floor,
                floor_old=floor_old, names=names, sel=sel, parties=parties)


def write_split_inc(r):
    lines = ["; ----------------------------------------------------------------------------",
             "; what a four-class (v0.50 and older) save's revealed class bits mean, per",
             "; species id (0..383): bit k set = the weakness of four-class bit k (slash $01,",
             "; pierce $02, bludgeon $04, special $08) became its SECOND child (katana,",
             "; spear, arcane, dagger); clear = its first (sword, dagger, fist, arcane).",
             "; Written once, when the six classes replaced the four (#566); it describes",
             "; the saves of the releases before that, so it does not change when a row does.",
             "; ----------------------------------------------------------------------------",
             "", "Ot6ClassSplitTbl:"]
    for sp in range(len(r["sel"])):
        nm = r["names"][sp] if sp < len(r["names"]) else ""
        lines.append("        .byte   $%02x             ; %3d %s" % (r["sel"][sp], sp, nm or "(unused)"))
    (ROOT / "ff6/src/battle/ot6_class_split.inc").write_text("\n".join(lines) + "\n")


def mask_expr(m):
    return "|".join(NEW_CONST[b] for b in ORDER if m & b) or "$00"


def rewrite_hud(new):
    path = ROOT / "ff6/src/battle/ot6_hud.asm"
    lines = path.read_text().split("\n")
    start = next(i for i, l in enumerate(lines) if l.startswith("Ot6ShieldTbl:"))
    sp, done = None, 0
    for i in range(start + 1, len(lines)):
        code = lines[i].split(";", 1)[0]
        w = re.match(r"\s*\.word\s+\$([0-9a-fA-F]{4})\s*$", code)
        if w:
            sp = int(w.group(1), 16)
            if sp == 0xFFFF:
                break
            continue
        b = re.match(r"(\s*\.byte\s+\d+,\s*)(\S+)(\s*)(;.*)?$", lines[i])
        if b and sp is not None:
            expr = mask_expr(new[sp])
            pad = " " if b.group(4) else ""
            lines[i] = b.group(1) + expr + pad + (b.group(4) or "")
            sp, done = None, done + 1
    assert done == len(new), (done, len(new))
    path.write_text("\n".join(lines))


def report(r):
    out = []
    g, new, rows = r["gauged"], r["new"], r["rows"]
    out.append("six-class split of v0.50's weapon weaknesses (tools/proto_six/split.py)")
    out.append("%d Ot6ShieldTbl rows; %d dealt species; %d dealt and gauged" % (len(rows), len(r["held"]), len(g)))
    for label, masks, names in (("v0.50 (four classes)", {sp: rows[sp][1] for sp in g}, OLD_NAME),
                                ("six classes", {sp: new[sp] for sp in g}, NEW_NAME)):
        cnt = collections.Counter(bin(m).count("1") for m in masks.values())
        tot = sum(bin(m).count("1") for m in masks.values())
        out.append("%s: by number of weapon weaknesses: %s; %d weaknesses" % (
            label, ", ".join("%d: %d" % (k, cnt[k]) for k in sorted(cnt)), tot))
        for b, n in names.items():
            k = sum(1 for m in masks.values() if m & b)
            out.append("  %-8s weak species %3d  (%.1f%% of species, %.1f%% of weaknesses)" % (
                n, k, 100.0 * k / len(g), 100.0 * k / tot))
    fought = [sp for sp in g if r["parties"].get(sp)]
    nf = sum(len(r["parties"][sp]) for sp in fought)
    nk = sum(1 for sp in fought for kit in r["parties"][sp] if not kit & new[sp])
    out.append("route fights (species x fight) with a signature-kit key under six: %d of %d (%d keyless, over %d "
               "species the route fought)" % (nf - nk, nf, nk, len(fought)))
    pinned = sum(1 for sp in g if "pinned" in r["how"][sp])
    npin = sum(r["how"][sp].count("pinned") for sp in g)
    nfam = sum(1 for sp in g if r["how"][sp].startswith("family"))
    out.append("dealt gauged species with a pinned weakness: %d (%d weaknesses pinned); family copies: %d; "
               "the other weaknesses by the balance" % (pinned, npin, nfam))
    out.append("")
    out.append("%-6s %-13s %-3s %-28s %-28s %s" % ("id", "name", "sh", "v0.50", "six", "how"))
    for sp in sorted(rows):
        sh, old = rows[sp]
        nm = r["names"][sp] if sp < len(r["names"]) else ""
        out.append("$%04x  %-13s %-3d %-28s %-28s %s%s%s" % (
            sp, nm, sh, "|".join(OLD_NAME[b] for b in OLD_NAME if old & b) or "-",
            "|".join(NEW_NAME[b] for b in ORDER if new[sp] & b) or "-", r["how"][sp],
            "" if sp in r["held"] else "  [not dealt]",
            ("  <- " + PIN[sp][1]) if sp in PIN and "pinned" in r["how"][sp] else ""))
    return "\n".join(out) + "\n"


def main():
    r = compute()
    if "--report-only" not in sys.argv:
        rewrite_hud(r["new"])
        write_split_inc(r)
        (ROOT / "ff6/tools/six_class_split.json").write_text(json.dumps({
            "rows": {"%04x" % sp: r["new"][sp] for sp in sorted(r["new"])},
            "floor": {"%04x" % sp: r["floor"][sp] for sp in sorted(r["floor"])},
        }, indent=1) + "\n")
    sys.stdout.write(report(r))


if __name__ == "__main__":
    main()
