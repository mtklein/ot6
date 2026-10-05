"""placement.py -- where the next emulators should go, from the run log.

live.py appends one line per finished run to build/throughput.jsonl
(machine, test, frames, wall, conc = emulators running beside it).  This
module turns that log into, per machine:

  runs      only whole runs count: a pass, or at least WHOLE_FRAC of the
            frames that test's passing runs reach.  A run cut off early
            (killed, or a failure) says little about its level.
  speed     each run's frames/s over the same test's frames/s alone on the
            same machine (the median of its one-emulator runs there, the
            quiet ones if any: load under QUIET_LOAD).  Speed 1.0 is "as
            fast as that test goes alone here", so neither the test mix
            nor a test's solo rate on another machine bends the curve.  A
            test never run alone on the machine is left out of its curve.
            Solo runs of the last HALF_LIFE_H join the baseline only once
            they are older, when the test has older ones (#342): a slow
            spell seen only in solo runs pulled the baseline down with it,
            so its runs read as full speed and the shift never moved.
  shift     d >= 0, the emulators' worth of the machine something else is
            using (other load, heat, the charger): a machine that slows
            down runs like it has d more emulators already.  Each 6-hour
            window gets its own d, and the current d is fitted to the
            recent runs, weights halving every HALF_LIFE_H; it stays 0
            until the last HALF_LIFE_H holds MIN_RECENT runs' worth of
            frames, so one slow run cannot move the knee.
  shape     mean speed per emulator against occupancy: each run counted at
            conc + its window's d, weighted by its frames (capped) and by
            age (SHAPE_HALF_LIFE_D).  Counting a slowed run where it really
            sat keeps a slow spell from bending the shape at the levels it
            happened to run at, so the whole curve moves with the shift.
            Only runs older than HALF_LIFE_H build it, when there are any
            (#342): the last few hours are what the shift is fitted to, and
            a slow spell inside them bent the shape where it ran instead
            (slow solo runs lowered level 1, and the shift read 0); a burst
            of runs at one level waits that long to move the knee.
  knee      the fewest emulators whose total, k * shape(k), is within 5% of
            the best (one more when that is the most ever run, so the curve
            keeps learning), less d: a slowdown moves it down by d, and a
            recovery moves it back.

room = knee - active now - live claims (and, on the owner's machines, those
in RESERVE, the reserve and the owner's load).  "order" lists machines for the next
emulators, each machine's room in PREFER order.
"""
import contextlib
import fcntl
import json
import math
import os
import time

HALF_LIFE_H = 6.0         # the shift follows the last few hours
SHAPE_HALF_LIFE_D = 7.0   # the shape forgets over weeks
FRAME_CAP = 30000         # a run weighs by its frames, up to this many, so
                          # a short run's start-up counts for little and one
                          # long run does not own a level
MIN_RUNS = 3              # a level needs this many runs to count
WHOLE_FRAC = 0.95         # a run without a pass counts once it reaches this
                          # share of its test's passing runs' frames
QUIET_LOAD = 2.0          # a solo run under this 1-min load is a quiet one
MIN_RECENT = 3            # FRAME_CAP-frame runs' worth in the last
                          # HALF_LIFE_H before the shift may move off 0
PRUNE_DAYS = 60           # older records weigh < 0.3% in the shape: dropped
PEAK_FRAC = 0.95          # the knee: fewest emulators within 5% of the best
CLAIM_SEC = 120           # how long a --claim holds its emulators
# Whose machines they are: batches fill px13 (ours alone) first, then the
# Air (the owner's travel laptop, often away), then the Pro (the owner's
# desk machine); a machine not named comes after, in --peer order.
PREFER = ("px13", "air", "mbp")
# The owner's headroom policy, not a measurement: the owner's machines.  On
# each a batch leaves this many emulators' worth of the knee free (0: none,
# owner 2026-10-05: "default to using it more"), and backs off by the load
# our own emulators there do not explain (the owner's own work, or macOS's).
# Every emulator runs niced (run.sh), so the owner's work comes first anyway.
# px13 is ours alone and not listed.
RESERVE = {"mbp": 0, "air": 0}


def _median(xs):
    xs = sorted(xs)
    n = len(xs)
    return (xs[n // 2] + xs[(n - 1) // 2]) / 2 if n else None


def interp(shape, x):
    """Speed per emulator at occupancy x: linear between levels; below the
    lowest, the lowest's; above the highest, the total stays flat (nothing
    measured says it grows)."""
    ks = sorted(shape)
    if x <= ks[0]:
        return shape[ks[0]]
    if x >= ks[-1]:
        return shape[ks[-1]] * ks[-1] / x
    for a, b in zip(ks, ks[1:]):
        if a <= x <= b:
            return shape[a] + (shape[b] - shape[a]) * (x - a) / (b - a)


def _weight(frames, age, half_life):
    return min(frames, FRAME_CAP) * 0.5 ** (max(0.0, age) / half_life)


def _shape(runs, now):
    """{k: speed}, {k: runs} from (occupancy, speed, frames, ts) runs: each
    level's weighted mean speed.  The mean, since a level's total is its
    emulators' speeds summed, fast cores and slow ones alike."""
    acc = {}
    for occ, sp, frames, ts in runs:
        k = max(1, int(round(occ)))
        w = _weight(frames, now - ts, SHAPE_HALF_LIFE_D * 86400)
        a = acc.setdefault(k, [0.0, 0.0, 0])
        a[0] += w * sp
        a[1] += w
        a[2] += 1
    ks = sorted(k for k, a in acc.items() if a[2] >= MIN_RUNS and a[1] > 0)
    # One emulator never runs faster for having more beside it, so the
    # shape is made non-increasing (pooling adjacent levels that break
    # that, weighted).  A batch's runs spread over neighbouring levels by
    # luck of the cores they got; pooling evens that out.
    blocks = []                      # [speed, weight, [levels]]
    for k in ks:
        blocks.append([acc[k][0] / acc[k][1], acc[k][1], [k]])
        while len(blocks) > 1 and blocks[-2][0] < blocks[-1][0]:
            s2, w2, k2 = blocks.pop()
            s1, w1, k1 = blocks.pop()
            blocks.append([(s1 * w1 + s2 * w2) / (w1 + w2), w1 + w2, k1 + k2])
    shape = {k: s for s, _w, lv in blocks for k in lv}
    return shape, {k: acc[k][2] for k in shape}


def _shift(shape, runs, now=None):
    """The d >= 0 that best fits shape(conc + d) to the runs, weighted by
    frames and (with now) by age, HALF_LIFE_H; among equally good d, the
    one nearest 0.  0 when the runs (with now: those of the last
    HALF_LIFE_H) hold fewer than MIN_RECENT runs' worth of frames: too
    little to say the machine has changed."""
    recent = [r for r in runs if now is None or now - r[3] < HALF_LIFE_H * 3600]
    if sum(min(r[2], FRAME_CAP) for r in recent) < MIN_RECENT * FRAME_CAP:
        return 0.0
    top = max(shape)
    ws = [(conc, sp, _weight(frames, 0 if now is None else now - ts,
                             HALF_LIFE_H * 3600))
          for conc, sp, frames, ts in runs]
    best = None
    for i in range(0, 4 * top + 1):
        d = i / 4
        err = sum(w * (sp - interp(shape, max(0.5, conc + d))) ** 2
                  for conc, sp, w in ws)
        key = (round(err, 9), abs(d))
        if best is None or key < best[0]:
            best = (key, d)
    return best[1]


def models(records, now):
    """{machine: {"shape", "counts", "runs", "d", "knee", "total"}}."""
    length = {}
    for r in records:
        if r.get("verdict") == "pass":
            length.setdefault(r["test"], []).append(r["frames"])
    length = {t: _median(v) for t, v in length.items()}
    whole = [r for r in records if r["frames"] > 0 and (
        r.get("verdict") == "pass"
        or r["frames"] >= WHOLE_FRAC * (length.get(r["test"]) or math.inf))]
    solo = {}
    for r in whole:
        if round(r["conc"]) == 1:
            quiet = (r.get("load") or 0.0) < QUIET_LOAD
            old = now - r["ts"] >= HALF_LIFE_H * 3600
            solo.setdefault((r["machine"], r["test"]), []).append(
                (quiet, old, r["fps"]))
    base = {}
    for key, xs in solo.items():
        xs = [x for x in xs if x[1]] or xs      # the older ones, if any
        q = [f for quiet, _o, f in xs if quiet]
        base[key] = _median(q or [f for _q, _o, f in xs])
    out = {}
    win_s = HALF_LIFE_H * 3600
    for m in sorted({r["machine"] for r in whole}):
        runs = [(r["conc"], r["fps"] / base[m, r["test"]], r["frames"], r["ts"])
                for r in whole
                if r["machine"] == m and base.get((m, r["test"]))]
        settled = [r for r in runs if now - r[3] >= win_s]
        first, _ = _shape(settled, now)
        if not first:
            settled = runs
            first, _ = _shape(runs, now)
        if not first:
            continue
        windows = {}
        for run in runs:
            windows.setdefault(int(run[3] // win_s), []).append(run)
        dw = {w: _shift(first, rs) for w, rs in windows.items()}
        shape, counts = _shape([(c + dw[int(ts // win_s)], sp, f, ts)
                                for c, sp, f, ts in settled], now)
        if not shape:
            continue
        d = _shift(shape, runs, now)
        top = max(shape)
        tot = {k: k * interp(shape, k) for k in range(1, top + 1)}
        best = max(tot.values())
        full = min(k for k, t in tot.items() if t >= PEAK_FRAC * best)
        if full == top:
            full += 1
        # the machine's knee with nothing else on it, less what else is on
        # it now
        knee = max(0, int(round(full - d)))
        out[m] = {"shape": shape, "counts": counts, "runs": len(runs),
                  "d": d, "full": full, "knee": knee, "total": tot}
    return out




def held(claims, machine, active, now):
    """Emulators live claims still hold on a machine: what was claimed,
    less what has started there since the oldest live claim."""
    live = [c for c in claims
            if c["machine"] == machine and now - c["ts"] < CLAIM_SEC]
    if not live:
        return 0
    rise = max(0, active - min(c["active0"] for c in live))
    return max(0, sum(c["n"] for c in live) - rise)


SETTLE_SEC = 300      # a returning peer's quiet period before it takes work


def placement(machines, mods, claims, now):
    """placement.json from the machines' state now, the models and claims."""
    out = []
    for m in machines:
        mo = mods.get(m["name"])
        rec = {"name": m["name"], "up": m["up"], "active": m["active"],
               "load1": (m["load"] or [None])[0], "ncpu": m["ncpu"],
               "fps": m.get("fps"), "runs": mo["runs"] if mo else 0}
        out.append(rec)
        if not mo:
            continue
        rec["curve"] = {str(k): [round(v, 2), mo["counts"][k]]
                        for k, v in sorted(mo["shape"].items())}
        rec["shift"] = mo["d"]
        if not m["up"]:
            continue
        # A peer that has only just come back (a sleeping laptop's brief
        # network wake) gets no room until it has stayed up a while: work
        # placed there would freeze when it sleeps again.
        if m.get("up_since") and now - m["up_since"] < SETTLE_SEC:
            rec["room"] = 0
            rec["settling"] = int(SETTLE_SEC - (now - m["up_since"]))
            continue
        room = mo["knee"] - m["active"]
        h = held(claims, m["name"], m["active"], now)
        if h:
            room -= h
            rec["claimed"] = h
        if m["name"] in RESERVE:
            owner = math.ceil(max(0.0, (rec["load1"] or 0.0) - m["active"]))
            room -= RESERVE[m["name"]] + owner
            rec.update(reserve=RESERVE[m["name"]], owner_load=owner)
        rec.update(peak=mo["knee"], room=max(0, room))
    return {"ts": now, "prefer": PREFER, "reserve": RESERVE,
            "machines": out, **fill(out)}


def fill(machines):
    rank = {n: i for i, n in enumerate(PREFER)}
    ranked = sorted((r for r in machines if r.get("room")),
                    key=lambda r: rank.get(r["name"], len(PREFER)))
    order = [r["name"] for r in ranked for _ in range(r["room"])]
    return {"order": order, "room": len(order)}


@contextlib.contextmanager
def locked(path):
    """An exclusive lock on path (a <path>.lock beside it), held by every
    writer: appenders of the run log, its prune, and --claim."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        yield


def append(path, lines):
    """Append whole lines to the run log, under its lock."""
    with locked(path):
        with open(path, "a") as f:
            f.write("".join(lines))


def load_records(path, now):
    """The log's records, newest line per (machine, id); lines older than
    PRUNE_DAYS are dropped, and the file rewritten without them.  Read and
    rewrite happen under the lock appenders take, so no append between
    them is lost."""
    recs, seen, kept, old = [], set(), [], 0
    if not os.path.exists(path):
        return recs, seen
    with locked(path):
        try:
            with open(path) as f:
                lines = f.readlines()
        except OSError:
            return recs, seen
        for line in lines:
            try:
                r = json.loads(line)
                key = (r["machine"], r["id"])
            except (ValueError, KeyError, TypeError):
                kept.append(line)
                continue
            if now - r.get("ts", now) > PRUNE_DAYS * 86400:
                old += 1
                continue
            kept.append(line)
            if key not in seen:
                seen.add(key)
                recs.append(r)
        if old:
            tmp = path + ".tmp"
            with open(tmp, "w") as f:
                f.writelines(kept)
            os.replace(tmp, path)
    return recs, seen


def read_claims(path, now):
    try:
        with open(path) as f:
            cs = [json.loads(l) for l in f if l.strip()]
    except (OSError, ValueError):
        return []
    return [c for c in cs if now - c.get("ts", 0) < CLAIM_SEC]


def claim(path, p, n, who):
    """--place N --claim WHO: under a lock on the claims file, take N from
    placement p less the claims p has not seen yet, record the claim, and
    return the machines taken.  Parallel callers queue on the lock."""
    with locked(path):
        now = time.time()
        live = read_claims(path, now)
        unseen = [c for c in live if c["ts"] > p["ts"]]
        ms = [dict(m) for m in p["machines"]]
        for m in ms:
            if "room" in m:
                m["room"] = max(0, m["room"] - held(
                    unseen, m["name"], m["active"], now))
        take = fill(ms)["order"][:n]
        act = {m["name"]: m["active"] for m in ms}
        new = [{"ts": now, "by": who, "machine": name, "n": take.count(name),
                "active0": act[name]} for name in dict.fromkeys(take)]
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            f.writelines(json.dumps(c) + "\n" for c in live + new)
        os.replace(tmp, path)
    return take
