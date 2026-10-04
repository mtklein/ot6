#!/usr/bin/env python3
"""rewind_search.py -- the rewind-search lab instrument (#375): branch a
character's battle decisions from whole-machine snapshots and score every
option the command window offers, across draws.

    python3 tools/tests/rewind_search.py run --lua tools/tests/gen_sabin_trench.lua \\
        --char 5 --species 0x59 --shifts 0 2 4 --jobs 3 --dir build/lab/rewind/trench
    python3 tools/tests/rewind_search.py report --dir build/lab/rewind/trench

`run` splices tools/tests/rewind_search.lua (the in-emulator half; its
header says what it does at a decision) into the host script right after
its `local H = dofile(...lib/ot6.lua)` line, behind a REWIND table built
from the flags, and runs it once per boot seed shift (OT6_SEED_SHIFT) with
the segment runner's retries off and every artifact kept in the run's own
directory (nothing is published to build/states).  Each shift's log is
<dir>/s<shift>.log.

`report` reads the [rewind] lines of every log in the directory: per
decision the battle key, the driver's own plan, and every branch's score;
then, across decisions, how each kind of option did against the driver's
own choice at the same decision (paired, with a sign test), counting
draws by distinct battle key, and the control line (a restored copy of the
driver's own plan must replay branch "own" exactly).

A lab tool: rewinds never enter the route chain or any balance evidence.
What it finds becomes a driver rule, verified separately by plain play.
"""
import argparse
import concurrent.futures as cf
import math
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PRELUDE = ROOT / "tools" / "tests" / "rewind_search.lua"
sys.path.insert(0, str(ROOT / "tools"))
import check_instruments  # noqa: E402 -- splice(): the one definition qualification checks


def splice(host_text, rewind_lua):
    """The host script with the REWIND table and the instrument inserted
    after its lib line (check_instruments.splice, as qualification does)."""
    return check_instruments.splice(host_text, rewind_lua + "\n" + PRELUDE.read_text())


def rewind_table(a):
    f = [f"char = {a.char}", f"capFrames = {a.cap}"]
    if a.species:
        f.append("species = { " + ", ".join(str(int(s, 0)) for s in a.species) + " }")
    if a.decisions:
        f.append("decisions = { " + ", ".join(str(d) for d in a.decisions) + " }")
    if a.boosts:
        f.append("boosts = { " + ", ".join(str(b) for b in a.boosts) + " }")
    return "REWIND = { " + ", ".join(f) + " }"


def run_one(a, shift, d):
    host = Path(a.lua)
    lua = d / f"{host.stem}_rewind_s{shift}.lua"
    lua.write_text(splice(host.read_text(), rewind_table(a)))
    log = d / f"s{shift}.log"
    env = dict(os.environ, OT6_RETRIES="1", OT6_SEED_SHIFT=str(shift), OT6_TIMEOUT=str(a.timeout),
               OT6_ARTIFACT_DIR=str(d / f"art_s{shift}"), OT6_WORKER=f"rewind_{d.name}_s{shift}")
    subprocess.run(["sh", str(ROOT / "tools" / "tests" / "run.sh"), str(lua), str(log)], cwd=ROOT,
                   env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    lua.unlink()
    text = log.read_text(errors="replace") if log.exists() else ""
    verdict = next((l for l in reversed(text.splitlines())
                    if re.match(r"\[ot6\] (PASS \(frame|FAIL: )", l)), "(no verdict)")
    n = text.count("[ot6] [rewind] D") and len(re.findall(r"^\[ot6\] \[rewind\] D\d+ f\d+ key .* branches$", text, re.M))
    return f"s{shift}: {verdict[6:100]} | {n} decision(s) searched"


# ---- report -------------------------------------------------------------
DEC = re.compile(r"^\[ot6\] \[rewind\] D(\d+) f(\d+) key (\S+) form (.*?) actor (\d) char (\d+) bank (\d+) "
                 r"hp (\S+) mp (\S+): own plan (.*); (\d+) branches$")
BR = re.compile(r"^\[ot6\] \[rewind\] D(\d+) branch (\d+)/(\d+) (own )?(.*?): (\S+(?: \S+)?) deaths=(\d+) down=(\d+) "
                r"actorDied=(\w+) hpLost=(\d+) mpSpent=(\d+) items=(\S+) gil=(\d+) frames=(\d+) monacts=(\S+)(.*)$")
CTL = re.compile(r"^\[ot6\] \[rewind\] D(\d+) control: .* -- (MATCH|MISMATCH)$")


def kind_of(desc):
    """The option's kind, target dropped: 'Fight bp1', 'Blitz $5D bp0', 'Item $E9'."""
    desc = re.sub(r" -> \S+", "", desc).replace(" (driver's aim)", "")
    return desc


def parse(log):
    decs = {}
    for l in log.read_text(errors="replace").splitlines():
        m = DEC.match(l)
        if m:
            decs[int(m.group(1))] = dict(n=int(m.group(1)), frame=int(m.group(2)), key=m.group(3),
                                         form=m.group(4), actor=int(m.group(5)), bank=int(m.group(7)),
                                         hp=m.group(8), own=m.group(10), branches={}, control=None)
            continue
        m = BR.match(l)
        if m and int(m.group(1)) in decs:
            decs[int(m.group(1))]["branches"][int(m.group(2))] = dict(
                own=bool(m.group(4)), desc=m.group(5), how=m.group(6), deaths=int(m.group(7)),
                down=int(m.group(8)), actorDied=m.group(9) == "true", hpLost=int(m.group(10)),
                mp=int(m.group(11)), items=m.group(12), gil=int(m.group(13)), frames=int(m.group(14)),
                acts=m.group(15), dropped="DROPPED" in m.group(16))
            continue
        m = CTL.match(l)
        if m and int(m.group(1)) in decs:
            decs[int(m.group(1))]["control"] = m.group(2)
    return decs


def badness(b):
    """Lower is better: a lost fight, then members down at the end, then
    deaths, then HP lost, then frames."""
    lost = 0 if b["how"] in ("won",) else 1
    return (lost, b["down"], b["deaths"], b["hpLost"], b["frames"])


def signp(a, b):
    n = a + b
    if n == 0:
        return 1.0
    k = min(a, b)
    return min(1.0, 2 * sum(math.comb(n, i) for i in range(k + 1)) / 2 ** n)


def report(d, counter):
    rows = []
    for log in sorted(d.glob("s*.log"), key=lambda p: int(p.stem[1:])):
        for n, dec in sorted(parse(log).items()):
            dec["shift"] = int(log.stem[1:])
            rows.append(dec)
    print(f"{len(rows)} decision(s) searched in {len(list(d.glob('s*.log')))} log(s); "
          f"distinct battle keys {len({r['key'] for r in rows})}")
    ctl = [r["control"] for r in rows]
    print(f"control (restored own plan replays branch own): {ctl.count('MATCH')} MATCH, "
          f"{ctl.count('MISMATCH')} MISMATCH, {ctl.count(None)} unread")
    # per kind of option, against the driver's own choice at the same decision
    kinds = {}
    seen_key = set()
    for r in rows:
        own = r["branches"].get(0)
        if own is None:
            continue
        first_of_key = r["key"] not in seen_key
        seen_key.add(r["key"])
        best = {}
        for k, b in r["branches"].items():
            if k == 0 or b["dropped"]:
                continue
            kd = kind_of(b["desc"])
            if kd not in best or badness(b) < badness(best[kd]):
                best[kd] = b
        for kd, b in best.items():
            K = kinds.setdefault(kd, dict(better=0, worse=0, same=0, n=0, keys=set(), dd=0, dh=0,
                                          counters_b=0, counters_own=0))
            K["n"] += 1
            K["keys"].add(r["key"])
            K["dd"] += b["deaths"] - own["deaths"]
            K["dh"] += b["hpLost"] - own["hpLost"]
            K["counters_b"] += b["acts"].count(counter) if counter else 0
            K["counters_own"] += own["acts"].count(counter) if counter else 0
            if badness(b) < badness(own):
                K["better"] += 1
            elif badness(b) > badness(own):
                K["worse"] += 1
            else:
                K["same"] += 1
    print("\nper kind of option (its best target), against the driver's own choice at the same "
          "decision: better / worse / same (badness: lost, down at end, deaths, HP lost, frames)")
    for kd, K in sorted(kinds.items(), key=lambda kv: -kv[1]["better"] + kv[1]["worse"]):
        print(f"  {kd:24s} n={K['n']:3d} keys={len(K['keys']):3d}  better {K['better']:3d} worse "
              f"{K['worse']:3d} same {K['same']:3d}  sign p={signp(K['better'], K['worse']):.4f}  "
              f"deaths {K['dd']:+d}  HP {K['dh']:+d}"
              + (f"  {counter} drawn {K['counters_b']} vs own {K['counters_own']}" if counter else ""))
    print("\nper decision:")
    for r in rows:
        own = r["branches"].get(0, {})
        print(f"s{r['shift']} D{r['n']} {r['key']} f{r['frame']} bank {r['bank']} hp {r['hp']} "
              f"own {r['own']} -> {own.get('how')} deaths={own.get('deaths')} down={own.get('down')} "
              f"hpLost={own.get('hpLost')} [{r['control']}]  form {r['form']}")
        for k, b in sorted(r["branches"].items()):
            if k == 0:
                continue
            mark = "+" if badness(b) < badness(own) else ("-" if badness(b) > badness(own) else "=")
            print(f"    {mark} {b['desc']:28s} {b['how']:6s} deaths={b['deaths']} down={b['down']} "
                  f"actorDied={b['actorDied']!s:5s} hpLost={b['hpLost']:4d} frames={b['frames']:5d}"
                  f"{' DROPPED' if b['dropped'] else ''}  {b['acts'][:120]}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--lua", required=True, help="the host script (a leg's generator)")
    r.add_argument("--char", type=int, required=True, help="character id whose windows are searched")
    r.add_argument("--species", nargs="*", default=[], help="species words; a decision counts only in "
                   "a formation holding one")
    r.add_argument("--decisions", type=int, nargs="*", default=[], help="decision numbers to search (default all)")
    r.add_argument("--boosts", type=int, nargs="*", default=[], help="boost levels offered (default 0..3)")
    r.add_argument("--cap", type=int, default=12000, help="frames before a branch is scored open")
    r.add_argument("--shifts", type=int, nargs="+", required=True)
    r.add_argument("--jobs", type=int, default=2)
    r.add_argument("--timeout", type=int, default=7200)
    r.add_argument("--dir", required=True)
    s = sub.add_parser("report")
    s.add_argument("--dir", required=True)
    s.add_argument("--counter", default=None, help="a monster action to count, e.g. ':$B9'")
    a = ap.parse_args()
    d = Path(a.dir)
    d.mkdir(parents=True, exist_ok=True)
    if a.cmd == "run":
        (d / "args.txt").write_text(repr(vars(a)) + "\n")
        with cf.ThreadPoolExecutor(max_workers=a.jobs) as ex:
            for out in ex.map(lambda s: run_one(a, s, d), a.shifts):
                print(out, flush=True)
    else:
        report(d, a.counter)
    return 0


if __name__ == "__main__":
    sys.exit(main())
