#!/usr/bin/env python3
"""leg_species.py [LOGDIR] -- the species each leg of the line deals, for the
route's area dress (#566; tools/tests/lib/ot6_field.lua M.gearDressPlan).

A leg deals what its maps' pools hold and the formations it meets: for every
map the leg's log walks ("[tiles] map=N ... xy=X:Y,...", the run loop's
record), the map's random pool (SubBattleGroup -> RandBattleGroup, every
formation of the group's four words, variants included) when the map has
random battles (MapProp +5 bit 7), and on the world maps the pool of each
sector walked (WorldBattleGroup, sector = map*64 + (y>>5)*8 + (x>>5)); and
every formation the leg's battles opened with ("[keys] form=$NNN": the event
battles and bosses).  The species are BattleMonsters' slots of those
formations.  A leg's dress prepares for the leg and the one after it in the
line's order (a save's dress at a leg's end arms the next), so each leg's
entry is the union of its own species and its successor's.

The table is written into ot6_field.lua between the "-- BEGIN leg_species"
and "-- END leg_species" markers (M.LEG_SPECIES[leg] = { species, ... });
--check only reports whether it would change.  --union keeps every species the
table already lists beside the logs' (a replay's random encounters and walked
sectors vary, so the table gathers them over replays).  --covers checks that the
table holds every species the logs deal for each generator (the gate's check
against the replay's own logs, build/states: an exact match would go red at
every replay that walked one more sector).  LOGDIR defaults to the last full
replay's leg logs.  Run from the repository root.

    python3 tools/six_classes/leg_species.py [LOGDIR] [--check | --union | --covers]
"""
import glob
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import stages  # noqa: E402

LIB = ROOT / "tools/tests/lib/ot6_field.lua"
DEFAULT_LOGS = ROOT / "build/attempts/wt/v051-six-classes/line/six-5304"
TILES = re.compile(r"^\[ot6\] \[tiles\] map=(\d+) n=\d+ xy=(\S*)")
KEYS = re.compile(r"^\[ot6\] .*\[keys\] form=\$([0-9A-F]+) ")


def dat(rel):
    return (ROOT / "ff6/src" / rel).read_bytes()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    logs = Path(args[0]) if args else DEFAULT_LOGS
    props, sbg, rbg, wbg, bm = (dat("field/map_prop.dat"), dat("field/sub_battle_group.dat"),
                                dat("field/rand_battle_group.dat"), dat("field/world_battle_group.dat"),
                                dat("battle/battle_monsters.dat"))

    def expand(w):
        return [(w & 0x1FF) + k for k in range(4)] if w & 0x8000 else [w & 0x1FF]

    def group(g):
        return [f for i in range(0, 8, 2) for f in expand(rbg[g * 8 + i] | (rbg[g * 8 + i + 1] << 8))]

    def species(f):
        rec = bm[f * 15:(f + 1) * 15]
        return {rec[2 + s] | (((rec[14] >> s) & 1) << 8) for s in range(6) if rec[1] & (1 << s)} if len(rec) == 15 else set()

    own = {}
    for p in sorted(glob.glob(str(logs / "*.log"))):
        leg = os.path.basename(p)[:-4]
        forms = set()
        for line in open(p, errors="replace"):
            m = TILES.match(line)
            if m:
                mp = int(m.group(1))
                if mp in (0, 1):
                    for xy in m.group(2).split(","):
                        if ":" not in xy:
                            continue
                        x, y = (int(v) for v in xy.split(":"))
                        sec = mp * 64 + (y >> 5) * 8 + (x >> 5)
                        if sec < len(wbg) and wbg[sec] != 0xFF:
                            forms.update(group(wbg[sec]))
                elif mp * 33 + 5 < len(props) and props[mp * 33 + 5] & 0x80:
                    forms.update(group(sbg[mp]))
                continue
            m = KEYS.match(line)
            if m:
                forms.add(int(m.group(1), 16))
        sp = set()
        for f in forms:
            sp |= species(f)
        own[leg] = sp
    order = [leg for leg in stages.line_order(str(ROOT / "build.ninja")) if leg in own]
    # the generator of each state (the generate edge's `gen`): the lib knows its script (OT6_SCRIPT, the composed
    # preamble's; Mesen's sandbox has no os.getenv), so the table is keyed by generator, each the union of its
    # states' species and their successors'
    gen_of, state = {}, None
    for line in open(ROOT / "build.ninja"):
        m = re.match(r"build build/states/(\w+)\.mss\.lua .*: generate", line)
        if m:
            state = m.group(1)
            continue
        m = re.match(r"\s+gen = (\w+)", line)
        if m and state:
            gen_of[state] = m.group(1)
            state = None
    table = {}
    for i, leg in enumerate(order):
        u = set(own[leg])
        if i + 1 < len(order):
            u |= own[order[i + 1]]
        g = gen_of.get(leg)
        if u and g:
            table[g] = sorted(set(table.get(g, [])) | u)
    text = LIB.read_text()
    old = {}
    for m in re.finditer(r"^  (\w+) = \{ ([^}]*) \},$", text[text.find("-- BEGIN leg_species"):text.find("-- END leg_species")],
                         re.M):
        old[m.group(1)] = {int(v, 16) for v in m.group(2).split(", ") if v}
    if "--covers" in sys.argv:
        miss = [(g, sorted(set(v) - old.get(g, set()))) for g, v in sorted(table.items())
                if set(v) - old.get(g, set())]
        for g, sp in miss:
            print("leg_species: %s deals %s, which M.LEG_SPECIES does not list (rerun with --union)"
                  % (g, " ".join("$%03X" % x for x in sp)))
        print("leg_species: %s" % ("the table covers %s" % os.path.relpath(logs, ROOT) if not miss
                                   else "%d generator(s) not covered" % len(miss)))
        return 1 if miss else 0
    if "--union" in sys.argv:
        for g, v in old.items():
            table[g] = sorted(set(table.get(g, [])) | v)
    order = sorted(table)
    lines = ["-- BEGIN leg_species (tools/six_classes/leg_species.py %s%s; do not edit by hand)" %
             (os.path.relpath(logs, ROOT), " --union" if "--union" in sys.argv else ""),
             "M.LEG_SPECIES = {   -- generator (OT6_SCRIPT) -> the species its legs and the next ones deal"]
    for leg in order:
        if leg in table:
            lines.append("  %s = { %s }," % (leg, ", ".join("0x%03X" % s for s in table[leg])))
    lines += ["}", "-- END leg_species"]
    block = "\n".join(lines) + "\n"
    a = text.find("-- BEGIN leg_species")
    b = text.find("-- END leg_species")
    assert a >= 0 and b > a, "no leg_species markers in " + str(LIB)
    new = text[:a] + block + text[b + len("-- END leg_species\n"):]
    if "--check" in sys.argv:
        print("leg_species: %s" % ("up to date" if new == text else "would change"))
        return 0 if new == text else 1
    LIB.write_text(new)
    print("leg_species: %d generators, %d species-generator pairs, from %s" % (len(table), sum(len(v) for v in table.values()),
                                                                   os.path.relpath(logs, ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
