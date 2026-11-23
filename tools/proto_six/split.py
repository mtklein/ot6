#!/usr/bin/env python3
"""split.py -- regroup every species' weapon weaknesses from the four classes
into the six (#566).

Each four-class weakness becomes one class its own weapons went to
(classes.py CHILDREN: slash -> Sword or Katana; pierce -> Dagger, Spear or
Ranged; bludgeon -> Blunt or Ranged; special -> Ranged or Blunt), so a
species keeps the NUMBER of weapon weaknesses it had (the two "any weapon
breaks it" rows take all six).  The rule, in order:

  1. OPENING (pins.py OPENING, docs/design/opening.md): the species the game
     deals from the Narshe mines through Zozo are authored by hand, the whole
     row at once, from the hands that really meet them.  Such a row may
     change the number of weaknesses or name a class that is no child of the
     old one; the report lists each that does ("OPENING DEPARTS").
     PINNED (pins.py PIN, sources "wob"): elsewhere, where a World of Balance
     break story names the member whose weapon or skill is the key, the
     weakness becomes the class that weapon carries.
  2. FAMILY: Ultros's four records share one row.
  3. HOLDERS (owner, 2026-11-23: "we don't want just one particular character
     to be required to get through fights"): at each stage the route meets
     the species (stages.py), count the characters the player can field there
     who really hold one of the row's classes (classes.py SIGNATURE: signature
     weapon or command, not "could equip"; through the opening, what a new
     player's hands hold there, stages.py HELD).  A split is refused where
     that is nobody, or one character the story does not force into the
     party; the report lists every row where no split can meet it ("the rule
     binds"), the opening's authored rows included.
  4. ROUTE: of the splits left, keep those under which the fewest of the
     route's own fights against the species leave the party that fought it
     with no key in hand, then with none in its kit (hands, class-bearing
     skills, the bag's tools and throwables), and among those the split that
     puts a key in the most members' hands: a row keyed by the hands of the
     party that met it keeps a key in those hands.  What each party held is
     the baseline play's `[keys]` lines (main's ROM, this branch's harness:
     route_fights.py --keys), re-read under the six-class weapon table.
  5. COMMENT (pins.py, source "row"): then the split the four-class row's own
     comment suggests; a preference, since several describe hands the route
     does not hold.
  6. BALANCE: then, in species-id order, the split whose classes the fewest
     of the species the game deals (and gauges) hold so far; a tie takes the
     first-named children.  Species no battle deals, and the generated
     floor's rows, follow after and do not count toward the balance.

Reads the four-class ot6_hud.asm from git (BASE: origin/main's first parent
before the six, $OT6_SPLIT_BASE; so it is idempotent), rewrites the class
masks of Ot6ShieldTbl's rows in the working tree's ot6_hud.asm, writes
ff6/tools/six_class_split.json (species -> new mask; gen_break_floor.py reads
the floor rows from it) and ff6/src/battle/ot6_class_split.inc
(Ot6ClassSplitTbl: per species, the six-class bits each four-class weakness
became -- what a four-class save's revealed bits mean, for the codex
migration), and prints the report.

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
sys.path.insert(0, str(Path(__file__).resolve().parent))
import classes as C  # noqa: E402
import pins  # noqa: E402
import stages  # noqa: E402

S, P, B, X = C.SLASH, C.PIERCE, C.BLUDG, C.SPECIAL
OLD = {"OT6_SLASH": S, "OT6_PIERCE": P, "OT6_BLUDG": B, "OT6_SPECIAL": X}
BASE = os.environ.get("OT6_SPLIT_BASE", "origin/main")       # the four-class tree
KEYS = ROOT / "build/attempts/wt/v051-six-classes/line/route-keys-base.json"
NEW_NAME, NEW_CONST, ORDER, CHILDREN, OLD_NAME = C.NAME, C.CONST, C.ORDER, C.CHILDREN, C.OLD_NAME


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def base_file(path):
    return subprocess.run(["git", "show", BASE + ":" + path], cwd=ROOT, check=True, capture_output=True,
                          text=True).stdout


def names_mask(names, magitek=False, first=None):
    """the classes the named members really hold at a stage (its first leg)"""
    m = 0
    for n in names:
        if magitek:
            m |= C.KIND_CLASS["tekmissile"] if n == "TERRA" else 0
            continue
        kinds = stages.held_kinds(first, n)
        if kinds is None:
            m |= C.signature_mask(n)
        else:
            for k in kinds:
                m |= C.KIND_CLASS[k]
    return m


def opening_row(old, kinds):
    """An opening row authored whole: (mask, {old class: six-class bits},
    [departures]).  Each new class goes to one old weakness: its parent's
    where it has one in the row (CHILDREN), else an old weakness left with no
    child; a new class with neither is a weakness a four-class save never
    revealed, and stays '?' there."""
    mask = 0
    for k in kinds:
        mask |= C.KIND_CLASS[k]
    olds = [o for o in (S, P, B, X) if old & o]
    kids, taken = {o: 0 for o in olds}, 0
    for o in olds:                                  # each old weakness, its first-named child in the row
        for c in CHILDREN[o]:
            if mask & c and not taken & c:
                kids[o], taken = c, taken | c
                break
    strangers = []
    for c in ORDER:                                 # the row's other classes
        if not mask & c or taken & c:
            continue
        parents = [o for o in olds if c in CHILDREN[o]]
        if parents:
            o = min(parents, key=lambda o: bin(kids[o]).count("1"))
        else:
            strangers.append(c)
            orphans = [o for o in olds if not kids[o]]
            if not orphans:
                taken |= c
                continue
            o = orphans[0]
        kids[o], taken = kids[o] | c, taken | c
    departs = []
    n_old, n_new = len(olds), bin(mask).count("1")
    if n_new != n_old:
        departs.append("%d -> %d weaknesses" % (n_old, n_new))
    if strangers:
        departs.append("%s no child of %s" % ("/".join(NEW_NAME[c] for c in strangers),
                                              "|".join(OLD_NAME[o] for o in olds) or "nothing"))
    lost = [o for o in olds if not any(mask & c for c in CHILDREN[o])]
    if lost:
        departs.append("%s has no child in the row" % "/".join(OLD_NAME[o] for o in lost))
    return mask, kids, departs


def route_evidence():
    """species -> [fight], a fight = dict(leg, kit, hands, each, chars), under
    the six classes; and {leg: names seen fighting in it}."""
    out, seen = collections.defaultdict(list), collections.defaultdict(set)
    if not KEYS.exists():
        return out, seen
    skill = {"B": C.KIND_CLASS["blitz"], "S": C.KIND_CLASS["swdtech"], "M": C.KIND_CLASS["tekmissile"],
             "T": C.KIND_CLASS["thief hit"]}
    for f in json.loads(KEYS.read_text()):
        bag_tools = sum(C.item_class(i) for i in f["bag"] if 0xA3 <= i <= 0xAA)
        bag_throw = sum(C.item_class(i) for i in set(f["bag"]) if 0x41 <= i <= 0x43)
        if any(0xAB <= i <= 0xAD for i in f["bag"]):
            bag_throw |= C.KIND_CLASS["skean"]
        kit = hands = 0
        each, chars = [], set()
        for m in f["members"]:
            h = 0
            for hand in (m.get("r"), m.get("l")):
                if hand is None:
                    continue
                h |= C.KIND_CLASS["fang"] if (m["c"] == 11 and hand == 0xFF) else C.item_class(hand)
            k = h
            for s in m["skills"]:
                k |= skill[s]
            if m["tools"]:
                k |= bag_tools
            if m["throw"]:
                k |= bag_throw
            kit, hands = kit | k, hands | h
            each.append(h)
            if m["c"] < len(C.CHARS):
                chars.add(C.CHARS[m["c"]])
        seen[f["leg"]] |= chars
        for sp in f["species"]:
            out[sp].append(dict(leg=f["leg"], kit=kit, hands=hands, each=tuple(each), chars=chars))
    return out, seen


def old_rows():
    """the four-class Ot6ShieldTbl: {species: (shields, old mask)}, both halves."""
    csr = _load(ROOT / "tools/check_shield_rows.py", "csr")
    csr.CLASS_BIT = dict(OLD)
    rows = csr.parse_rows(base_file(csr.HUD_ASM), "Ot6ShieldTbl", True)
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


def holder_check(mask, fights, stage):
    """The holder rule for one split of one species: [(leg, why)] for each
    stage (by its first leg met) where it is not met."""
    bad, done = [], set()
    for f in fights:
        st = stage.get(f["leg"])
        if st is None or st[0] in done or f["leg"] in stages.VELDT:
            continue
        done.add(st[0])
        first, roster, forced, magitek = st
        real = {n for n in roster if names_mask([n], magitek, first) & mask}
        if magitek and not names_mask(roster, True):
            continue                    # in armor with no TekMissile: no weapon key to hold
        if not real:
            bad.append((f["leg"], "nobody fieldable there (%s) really holds %s" % (
                ", ".join(sorted(roster)), "/".join(NEW_NAME[b] for b in ORDER if mask & b))))
        elif len(real) == 1 and not real <= forced:
            bad.append((f["leg"], "only %s of %s really holds %s, and the story does not force them in" % (
                next(iter(real)), ", ".join(sorted(roster)), "/".join(NEW_NAME[b] for b in ORDER if mask & b))))
    return bad


def assign(masks, order, count, how, ev=None, stage=None, binds=None, departs=None):
    """Split masks[sp] for each sp in order; count is the running tally the
    balance reads (updated only when not None).  Returns ({sp: new mask},
    {sp: {old class: six-class bits}}).  departs: a list to fill with the
    opening's authored rows that change a count or leave the children (None:
    this pass does not read pins.OPENING -- the floor's)."""
    out, kids_of = {}, {}
    ev, stage = ev or {}, stage or {}
    for sp in order:
        old = masks[sp]
        if departs is not None and sp in pins.OPENING:
            kinds, src = pins.OPENING[sp]
            mask, kids, dep = opening_row(old, kinds)
            fights = ev.get(sp, ())
            rule = holder_check(mask, fights, stage) if mask else []
            notes = ["authored: %s" % (", ".join("%s->%s" % (OLD_NAME[o], "|".join(
                NEW_NAME[c] for c in ORDER if k & c) or "none") for o, k in kids.items()) or "no weapon weakness")]
            if dep:
                notes.append("DEPARTS: " + "; ".join(dep))
                departs.append((sp, old, mask, dep))
            if fights:
                notes.append("route: %d fights, %d without a key in hand, %d without one in the kit" % (
                    len(fights), sum(1 for f in fights if not f["hands"] & mask),
                    sum(1 for f in fights if not f["kit"] & mask)))
            if rule and binds is not None:
                binds.append((sp, mask, rule))
            out[sp], kids_of[sp], how[sp] = mask, kids, ", ".join(notes)
            if count is not None:
                for b in NEW_NAME:
                    if mask & b:
                        count[b] += 1
            continue
        if sp in pins.FAMILY and pins.FAMILY[sp] in out:
            out[sp], kids_of[sp] = out[pins.FAMILY[sp]], kids_of[pins.FAMILY[sp]]
            how[sp] = "family of $%04x" % pins.FAMILY[sp]
            for b in NEW_NAME:
                if count is not None and out[sp] & b:
                    count[b] += 1
            continue
        if sp in pins.EVERY and old == 15:
            out[sp] = C.SWORD | C.DAGGER | C.BLUNT | C.RANGED | C.KATANA | C.SPEAR
            kids_of[sp] = {o: sum(CHILDREN[o]) for o in (S, P, B, X)}
            how[sp] = "any weapon breaks it: all four -> all six"
            for b in NEW_NAME:
                if count is not None:
                    count[b] += 1
            continue
        kinds, src = pins.PIN.get(sp, ({}, ""))
        hard = src.startswith("wob")
        pin = {o: C.KIND_CLASS[k] for o, k in kinds.items() if old & o and hard}
        soft = {o: C.KIND_CLASS[k] for o, k in kinds.items() if old & o and not hard}
        olds = [o for o in (S, P, B, X) if old & o]
        tally = count if count is not None else collections.Counter()
        fights = ev.get(sp, ())
        best = None
        for combo in itertools.product(*[(pin[o],) if o in pin else CHILDREN[o] for o in olds]):
            if len(set(combo)) != len(combo):
                continue                                # one class twice
            mask = sum(combo)
            rule = holder_check(mask, fights, stage) if mask else []
            nohand = sum(1 for f in fights if not f["hands"] & mask)
            nokey = sum(1 for f in fights if not f["kit"] & mask)
            holders = sum(1 for f in fights for h in f["each"] if h & mask)
            off = sum(1 for o, k in zip(olds, combo) if o in soft and soft[o] != k)
            key = (len(rule), nohand, nokey, -holders, off, sum(tally[k] for k in combo),
                   tuple(CHILDREN[o].index(k) if k in CHILDREN[o] else 9 for o, k in zip(olds, combo)))
            if best is None or key < best[0]:
                best = (key, combo, rule)
        assert best is not None, "species $%04x: no split satisfies its pins" % sp
        key, combo, rule = best
        notes = ["%s->%s%s" % (OLD_NAME[o], NEW_NAME[k], " pinned" if o in pin else (
            " (comment)" if soft.get(o) == k else (" (not the comment's %s)" % NEW_NAME[soft[o]] if o in soft else "")))
            for o, k in zip(olds, combo)]
        if fights:
            notes.append("route: %d fights, %d without a key in hand, %d without one in the kit, %d member-hands "
                         "holding one" % (len(fights), key[1], key[2], -key[3]))
        if rule and binds is not None:
            binds.append((sp, sum(combo), rule))
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
    how, count, binds, departs = {}, collections.Counter(), [], []
    masks = {sp: m for sp, (sh, m) in rows.items()}
    ev, seen = route_evidence()
    stage = stages.stage_of(stages.line_order(str(ROOT / "build.ninja")), seen)
    new, kids = assign(masks, gauged, count, how, ev, stage, binds, departs)
    final_count = collections.Counter(count)
    rest = sorted(sp for sp in rows if sp not in new)
    n2, k2 = assign(masks, rest, collections.Counter(count), how, ev, stage, binds, departs)
    new.update(n2)
    kids.update(k2)
    # the floor: every species id's generated class (reached only by a species
    # with no Ot6ShieldTbl row), split by the same rule after the rows
    floor_old = {sp: gbf.classify(names[sp] if sp < len(names) else "")[0] for sp in range(gbf.CODEX_WIDTH)}
    floor, fkids = assign(floor_old, sorted(floor_old), collections.Counter(count), {})
    # what a four-class save's revealed bits mean: per species id, for each of
    # the four classes, the six-class bits its weakness became (0: it had none)
    sel = {sp: [kids.get(sp, fkids[sp]).get(o, 0) for o in (S, P, B, X)] for sp in range(gbf.CODEX_WIDTH)}
    return dict(rows=rows, held=held, gauged=gauged, new=new, how=how, count=final_count, floor=floor,
                names=names, sel=sel, ev=ev, binds=binds, stage=stage, departs=departs)


def write_split_inc(r):
    lines = ["; ----------------------------------------------------------------------------",
             "; what a four-class (v0.50 and older) save's revealed class bits mean: four",
             "; bytes a species id (0..383), byte k the six-class bits the species' weakness",
             "; of four-class bit k (slash $01, pierce $02, bludgeon $04, special $08) became;",
             "; $00 where it had none.  Written by tools/proto_six/split.py when the six",
             "; classes replaced the four (#566); it describes the saves of the releases",
             "; before that, so it does not change when a row does.",
             "; ----------------------------------------------------------------------------",
             "", "Ot6ClassSplitTbl:"]
    for sp in range(len(r["sel"])):
        nm = r["names"][sp] if sp < len(r["names"]) else ""
        lines.append("        .byte   %s ; %3d %s" % (", ".join("$%02x" % b for b in r["sel"][sp]), sp,
                                                    nm or "(unused)"))
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
            lines[i] = b.group(1) + mask_expr(new[sp]) + (" " if b.group(4) else "") + (b.group(4) or "")
            sp, done = None, done + 1
    assert done == len(new), (done, len(new))
    path.write_text("\n".join(lines))


def report(r):
    out = []
    g, new, rows = r["gauged"], r["new"], r["rows"]
    out.append("the six-class regrouping of the four-class weapon weaknesses (tools/proto_six/split.py)")
    out.append("%d Ot6ShieldTbl rows; %d dealt species; %d dealt and gauged" % (len(rows), len(r["held"]), len(g)))
    for label, masks, names in (("four classes", {sp: rows[sp][1] for sp in g}, OLD_NAME),
                                ("six classes", {sp: new[sp] for sp in g}, NEW_NAME)):
        cnt = collections.Counter(bin(m).count("1") for m in masks.values())
        tot = sum(bin(m).count("1") for m in masks.values())
        out.append("%s: by number of weapon weaknesses: %s; %d weaknesses" % (
            label, ", ".join("%d: %d" % (k, cnt[k]) for k in sorted(cnt)), tot))
        for b, n in names.items():
            k = sum(1 for m in masks.values() if m & b)
            sole = sum(1 for m in masks.values() if m == b)
            out.append("  %-8s weak species %3d  (%.1f%% of species, %.1f%% of weaknesses; the only weapon key of %d)"
                       % (n, k, 100.0 * k / len(g), 100.0 * k / tot, sole))
    fought = [sp for sp in g if r["ev"].get(sp)]
    nf = sum(len(r["ev"][sp]) for sp in fought)
    nk = sum(1 for sp in fought for f in r["ev"][sp] if not f["kit"] & new[sp])
    nh = sum(1 for sp in fought for f in r["ev"][sp] if not f["hands"] & new[sp])
    out.append("route fights (species x fight, %d over %d species; %s): the party's kit holds one of the species' "
               "six classes in %d (%d without); its weapons in hand in %d (%d without)" % (
                   nf, len(fought), KEYS.relative_to(ROOT) if KEYS.exists() else "no evidence", nf - nk, nk,
                   nf - nh, nh))
    pinned = sum(1 for sp in g if "pinned" in r["how"][sp])
    out.append("dealt gauged species with a pinned weakness: %d" % pinned)
    out.append("the opening's authored rows (pins.OPENING): %d" % sum(1 for sp in rows if sp in pins.OPENING))
    out.append("")
    out.append("OPENING DEPARTS (an authored row that changes the number of weapon weaknesses, or names a class "
               "that is no child of the old ones): %d rows" % len(r["departs"]))
    for sp, old, mask, dep in r["departs"]:
        nm = r["names"][sp] if sp < len(r["names"]) else ""
        out.append("  $%04x %-13s %-22s -> %-24s %s  <- %s" % (
            sp, nm, "|".join(OLD_NAME[b] for b in OLD_NAME if old & b) or "-",
            "|".join(NEW_NAME[b] for b in ORDER if mask & b) or "-", "; ".join(dep), pins.OPENING[sp][1]))
    out.append("")
    out.append("THE HOLDER RULE BINDS (no split of the row met it; the split kept is the least bad): %d rows" % len(
        r["binds"]))
    for sp, mask, rule in r["binds"]:
        nm = r["names"][sp] if sp < len(r["names"]) else ""
        for leg, why in rule:
            out.append("  $%04x %-13s %-22s at %-18s %s" % (
                sp, nm, "|".join(NEW_NAME[b] for b in ORDER if mask & b), leg, why))
    out.append("")
    out.append("%-6s %-13s %-3s %-28s %-28s %s" % ("id", "name", "sh", "four", "six", "how"))
    for sp in sorted(rows):
        sh, old = rows[sp]
        nm = r["names"][sp] if sp < len(r["names"]) else ""
        out.append("$%04x  %-13s %-3d %-28s %-28s %s%s%s" % (
            sp, nm, sh, "|".join(OLD_NAME[b] for b in OLD_NAME if old & b) or "-",
            "|".join(NEW_NAME[b] for b in ORDER if new[sp] & b) or "-", r["how"][sp],
            "" if sp in r["held"] else "  [not dealt]",
            ("  <- " + pins.OPENING[sp][1]) if sp in pins.OPENING else (
                ("  <- " + pins.PIN[sp][1]) if sp in pins.PIN else "")))
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
