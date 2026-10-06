"""placement.py -- where the next emulators should go: fixed per-machine slots.

Each machine's room is its emulator slots (run.sh's hard ceiling: the first
integer in that machine's ~/.config/ot6/emulator-slots, else its CPU count;
tools/tests/lib/emu_slot.py) less the emulators it runs now and the live
claims on it.  "order" lists machines for the next emulators, each machine's
room in PREFER order.

This replaced a model learned from a log of finished runs (speed against
emulators running, a fitted knee and shift), retired 2026-10-06: an overload
skewed it to advise px13 a peak of 202, and its fit grew to ~40 s a pass
(owner: "the learning mechanism just clearly didn't work.  abandon it").
"""
import contextlib
import fcntl
import json
import os
import time

CLAIM_SEC = 120           # how long a --claim holds its emulators
# Whose machines they are: batches fill px13 (ours alone) first, then the
# Air (the owner's travel laptop, often away), then the Pro (the owner's
# desk machine); a machine not named comes after, in --peer order.
PREFER = ("px13", "air", "mbp")


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


def placement(machines, claims, now):
    """placement.json from the machines' state now and the live claims."""
    out = []
    for m in machines:
        slots = m.get("slots") or m.get("ncpu")
        rec = {"name": m["name"], "up": m["up"], "active": m["active"],
               "load1": (m["load"] or [None])[0], "ncpu": m["ncpu"],
               "fps": m.get("fps"), "slots": slots}
        out.append(rec)
        if not m["up"] or not slots:
            continue
        # A peer that has only just come back (a sleeping laptop's brief
        # network wake) gets no room until it has stayed up a while: work
        # placed there would freeze when it sleeps again.
        if m.get("up_since") and now - m["up_since"] < SETTLE_SEC:
            rec["room"] = 0
            rec["settling"] = int(SETTLE_SEC - (now - m["up_since"]))
            continue
        room = slots - m["active"]
        h = held(claims, m["name"], m["active"], now)
        if h:
            room -= h
            rec["claimed"] = h
        rec.update(peak=slots, room=max(0, room))
    return {"ts": now, "prefer": PREFER, "machines": out, **fill(out)}


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
