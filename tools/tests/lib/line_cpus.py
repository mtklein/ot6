#!/usr/bin/env python3
"""line_cpus.py <worker> -- the CPUs a run of the play from power-on is
confined to on this machine, or nothing.

The line (savestate_ninja.line_runs: the generators on the prev= chain from
power-on, and the cutters booted from them) is one serial chain, and it is
the whole of a qualification's wall time (#390, #396: v0.42's 117 line runs
were 12,787 s of its 13,060).  On a machine whose cores differ in speed,
the line belongs on the fast ones: px13's Ryzen AI 9 HX 370 has four Zen 5
cores (CPUs 0-3 and their SMT siblings 12-15, 5.16 GHz) and eight Zen 5c
cores (4-11, 16-23, 3.29 GHz), and its kernel has amd_pstate's preferred-core
ranking off, so an unconfined run lands on a slow core two times in three
and plays about 1.35x slower there (build/attempts/wt/spike-mesen-profile/).

The machine names its fast CPUs in ~/.config/ot6/line-cpus, as taskset(1)
takes them (px13: `0-3,12-15`); the first word of the file counts.  No file,
no confinement: the Macs, whose schedulers place work by their own rules,
have none.  `<worker>` is the run's OT6_WORKER: a generator's state name, or
a cutter's checkpoint key with "-" as "_" (savestate_ninja.py's naming).
Confinement changes where the emulator runs, never what it computes.
"""
import os
import sys
from pathlib import Path

CONF = os.path.expanduser("~/.config/ot6/line-cpus")
HERE = Path(__file__).resolve().parent


def configured():
    try:
        with open(CONF) as f:
            words = f.read().split()
    except OSError:
        return None
    return words[0] if words else None


def line_workers(states):
    sys.path.insert(0, str(HERE))
    import savestate_ninja as sn
    line = sn.line_runs(states)
    owner = sn._owners(states)
    out = set(line)
    for key, run in sn.producers(states).items():
        if run[0] == "cutter" and owner.get(run[2]) in line:
            out.add(key.replace("-", "_"))
    return out


def main(argv):
    if len(argv) != 2:
        print("usage: line_cpus.py <worker>", file=sys.stderr)
        return 2
    cpus = configured()
    if not cpus:
        return 0
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "savestate_graph", HERE.parent / "savestate_graph.py")
    g = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(g)
    if argv[1] in line_workers(g.STATES):
        print(cpus)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
