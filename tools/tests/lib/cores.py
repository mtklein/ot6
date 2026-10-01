#!/usr/bin/env python3
"""cores.py -- put each emulator on a fast core while one is free.

    cores.py exec <slots-dir> -- <command...>   take a free fast core, then
                                                exec the command (pid kept)
    cores.py move <slots-dir> <pid>             Linux: move a running emulator
                                                onto a fast core freed since
                                                it started, or off one that
                                                someone pinned work to by hand
    cores.py show                               what this machine has

Every machine we run on mixes fast and slow cores: px13 has four Zen 5
cores that boost to 5.16 GHz and eight Zen 5c cores at 3.29 GHz; a Mac has
performance and efficiency cores.  Linux's scheduler does not keep a long
emulator on a fast core (px13 runs the same leg at 272 frames/s on a fast
core and 192 on a slow one), and a serial run (`ninja chain`, one leg
after another) is only as fast as the core each leg lands on.

  Linux   On by default.  The fast cores are the physical cores whose
          cpufreq/cpuinfo_max_freq (else acpi_cppc/highest_perf) is within
          FAST_FRAC of the top; with no slower core the machine is not
          hybrid and nothing changes.  Each fast core is a slot for one
          emulator, pinned to its hardware threads (sched_setaffinity before
          the exec); every other emulator is pinned to the slow cores and
          queued, and run.sh's watchdog loop (`move`) hands a slot that
          frees up to the oldest emulator still waiting, the long leg a
          build is most likely waiting on, before anything ninja starts
          next.  A core someone pinned other work to by hand (taskset -c, a
          benchmark) is not taken, and a holder gives its core up when that
          happens after it started.  A caller's own pinning is left alone.
  macOS   Off by default: nothing can be pinned, and the only lever, the QoS
          clamp, costs throughput.  On the Air, ten emulators at the default
          QoS all ran at 130-150 frames/s; with one at default and nine
          clamped to utility, the one ran at 284 (as fast as alone) and the
          nine at 75, because a utility clamp keeps a busy process on the
          efficiency cores.  OT6_FAST_CORES=N opts in: the first N emulators
          keep the default QoS (the performance cores) and the rest run
          under `taskpolicy -c utility`; 0 keeps every emulator off the
          performance cores, e.g. on a machine whose owner is working.

A slot is a file holding its emulator's pid, claimed under an flock on the
slots directory; a slot whose pid is gone is free.  OT6_FAST_CORES=N uses at
most N fast cores; OT6_FAST_CORES=off leaves the command untouched.
"""
import fcntl
import glob
import os
import subprocess
import sys

FAST_FRAC = 0.9   # within 10% of the top clock counts as fast


def _read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


def _cpulist(s):
    out = []
    for part in s.split(","):
        a, _, b = part.partition("-")
        out += range(int(a), int(b or a) + 1)
    return tuple(out)


def detect(root="/sys/devices/system/cpu"):
    """{"kind": "linux"|"darwin", "fast": [slot], "slow": cpus} or None when
    the machine has one kind of core.  A Linux slot is (name, cpus)."""
    if sys.platform == "darwin":
        def sysctl(k):
            r = subprocess.run(["sysctl", "-n", k], capture_output=True,
                               text=True)
            ok = r.returncode == 0 and r.stdout.strip()
            return int(r.stdout) if ok else 0
        if sysctl("hw.nperflevels") < 2:
            return None
        n = sysctl("hw.perflevel0.physicalcpu")
        return {"kind": "darwin", "fast": [(f"p{i}", ()) for i in range(n)],
                "slow": ()} if n else None
    cores = {}
    for d in glob.glob(os.path.join(root, "cpu[0-9]*")):
        if _read(os.path.join(d, "online")) == "0":
            continue
        freq = _read(os.path.join(d, "cpufreq/cpuinfo_max_freq"))
        perf = _read(os.path.join(d, "acpi_cppc/highest_perf"))
        sib = _read(os.path.join(d, "topology/thread_siblings_list"))
        if not (freq or perf) or not sib:
            return None
        key = (int(freq or 0), int(perf or 0))
        sibs = _cpulist(sib)
        cores[sibs] = max(cores.get(sibs, key), key)
    if not cores:
        return None
    use = 0 if all(k[0] for k in cores.values()) else 1
    top = max(k[use] for k in cores.values())
    fast = sorted((s for s, k in cores.items() if k[use] >= FAST_FRAC * top),
                  key=lambda s: (tuple(-x for x in cores[s]), s))
    slow = sorted(c for s, k in cores.items() if k[use] < FAST_FRAC * top
                  for c in s)
    if not slow:
        return None
    return {"kind": "linux",
            "fast": [("cpu" + "-".join(map(str, s)), s) for s in fast],
            "slow": tuple(slow)}


def _limit(info):
    v = os.environ.get("OT6_FAST_CORES", "")
    if v.isdigit():
        info["fast"] = info["fast"][:int(v)]
    return info


def _alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        pass
    return True


def _holder(path):
    held = _read(path)
    return int(held.split()[0]) if held and held.split()[0].isdigit() else None


def hand_pinned(slots, skip=None):
    """Names of the free Linux slots someone pinned other work to by hand
    (taskset -c on a benchmark): a user process whose allowed CPUs all lie
    in the slot's core.  Kernel threads (no cmdline) are pinned per CPU and
    do not count."""
    if sys.platform == "darwin":
        return set()
    busy = set()
    for p in os.listdir("/proc"):
        if not p.isdigit() or int(p) == skip:
            continue
        try:
            with open(f"/proc/{p}/cmdline", "rb") as f:
                if not f.read(1):
                    continue
            with open(f"/proc/{p}/status") as f:
                allowed = next(l.split()[1] for l in f
                               if l.startswith("Cpus_allowed_list:"))
        except (OSError, StopIteration):
            continue
        cpus = set(_cpulist(allowed))
        for name, core in slots:
            if cpus <= set(core):
                busy.add(name)
    return busy


def claim(slots_dir, slots, pid, queued=False, enqueue=True):
    """slots: {name: cpus}, fastest first.  The first free one, now held
    for pid; or None, and (enqueue) pid joins the queue of slow emulators.
    A pid that already holds a slot gets that one back.  The queue goes
    first: a newcomer takes a free slot only when nobody waits, and a queued
    pid only when it is the oldest still waiting.  So a fast core that frees
    up goes to the longest-running slow emulator, most likely a long leg the
    build will wait on, rather than to whatever ninja starts next.  A slot
    someone pinned other work to by hand is not free."""
    queue = os.path.join(slots_dir, "queue")
    os.makedirs(queue, exist_ok=True)
    with open(os.path.join(slots_dir, ".lock"), "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        free = None
        candidates = []
        for name in slots:
            holder = _holder(os.path.join(slots_dir, name))
            if holder == pid:
                return name
            if holder is None or not _alive(holder):
                candidates.append(name)
        if candidates:
            taken = hand_pinned([(n, slots[n]) for n in candidates])
            free = next((n for n in candidates if n not in taken), None)
        waiting = []
        for w in os.listdir(queue):
            path = os.path.join(queue, w)
            if w.isdigit() and _alive(int(w)):
                waiting.append((os.stat(path).st_mtime, int(w)))
            else:
                os.unlink(path)
        if queued and min(waiting, default=(0, pid))[1] != pid:
            return None
        if free is None or (waiting and enqueue and not queued):
            if enqueue and not queued:
                open(os.path.join(queue, str(pid)), "w").close()
            return None
        with open(os.path.join(slots_dir, free), "w") as f:
            f.write(f"{pid}\n")
        if queued:
            os.unlink(os.path.join(queue, str(pid)))
        return free


def _say(msg):
    # Not an [ot6] line: the verdicts and the determinism comparisons read
    # those, and run.sh's load watchdog waits for the first one.
    print(f"[cores] {msg}", file=sys.stderr, flush=True)


def cmd_exec(slots_dir, argv):
    want = os.environ.get("OT6_FAST_CORES", "")
    off = want == "off" or (sys.platform == "darwin" and not want.isdigit())
    info = None if off else detect()
    if not info:
        os.execvp(argv[0], argv)
    if info["kind"] == "linux" and os.sched_getaffinity(0) != set(
            c for _n, cs in info["fast"] for c in cs) | set(info["slow"]):
        # The caller pinned this run itself (taskset -c, a benchmark):
        # leave it where it was put.
        mine = sorted(os.sched_getaffinity(0))
        _say(f"cpus {','.join(map(str, mine))}, as the caller set")
        os.execvp(argv[0], argv)
    info = _limit(info)
    by_name = dict(info["fast"])
    got = claim(slots_dir, by_name, os.getpid(),
                enqueue=info["kind"] == "linux")
    if info["kind"] == "linux":
        cpus = by_name[got] if got else info["slow"]
        os.sched_setaffinity(0, cpus)
        _say(f"{'fast' if got else 'slow'} cpus {','.join(map(str, cpus))}")
    else:
        _say(f"fast slot {got}, default QoS" if got
             else "no fast slot free: utility QoS")
        if not got:
            argv = ["taskpolicy", "-c", "utility"] + argv
    os.execvp(argv[0], argv)


def _pin(pid, cpus):
    for tid in os.listdir(f"/proc/{pid}/task"):
        try:
            os.sched_setaffinity(int(tid), cpus)
        except OSError:
            pass


def cmd_move(slots_dir, pid):
    """Linux only (a QoS clamp cannot be lifted from a running process).
    A queued emulator takes a fast core freed since it started; a holder
    whose core someone has since pinned other work to by hand gives it up
    and rejoins the queue.  Says what it did on stdout."""
    info = None if os.environ.get("OT6_FAST_CORES") == "off" else detect()
    if not info or info["kind"] != "linux" or not _alive(pid):
        return 0
    info = _limit(info)
    by_name = dict(info["fast"])
    queued = os.path.join(slots_dir, "queue", str(pid))
    if os.path.exists(queued):
        got = claim(slots_dir, by_name, pid, queued=True)
        if got:
            _pin(pid, by_name[got])
            print(f"moved to fast cpus {','.join(map(str, by_name[got]))}")
        return 0
    held = next((n for n in by_name
                 if _holder(os.path.join(slots_dir, n)) == pid), None)
    if held and hand_pinned([(held, by_name[held])], skip=pid):
        with open(os.path.join(slots_dir, ".lock"), "w") as lk:
            fcntl.flock(lk, fcntl.LOCK_EX)
            os.unlink(os.path.join(slots_dir, held))
            open(queued, "w").close()
        _pin(pid, info["slow"])
        print(f"fast cpus {','.join(map(str, by_name[held]))} were pinned to "
              "other work by hand: moved to the slow cpus")
    return 0


def main(argv):
    if argv[:1] == ["show"]:
        print(detect())
        return 0
    if len(argv) >= 4 and argv[0] == "exec" and argv[2] == "--":
        cmd_exec(argv[1], argv[3:])
    if len(argv) == 3 and argv[0] == "move":
        return cmd_move(argv[1], int(argv[2]))
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
