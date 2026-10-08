#!/usr/bin/env python3
"""emu_slot.py -- the machine-wide emulator limit run.sh holds (#407).

    emu_slot.py --hold <owner-pid> <ready-file>

Waits for one of this machine's N emulator slots (an exclusive flock on
~/.cache/ot6/emu-slots/<k>), writes "<k> <N> <waited-seconds>" to
<ready-file> once it holds one, then keeps it until <owner-pid> exits (run.sh,
which launches exactly one emulator at a time).  The kernel drops the lock
when this process dies however it dies, so a killed run never leaks a slot.

N is the machine's own setting, not the caller's: the first integer in
~/.config/ot6/emulator-slots, else the CPU count.  Agents launching batches
cannot raise it; a batch larger than N simply queues (2026-10-06: a lab that
claimed 2 emulators from placement launched 64 on px13, load 97 on 24
threads, while the other machines sat idle).

    emu_slot.py --status     prints "<held> <N>" for this machine
    emu_slot.py --selftest   12 holders on a private 3-slot pool: never more
                             than 3 hold at once, all 12 get one, and a
                             killed holder's slot is taken again
"""
import fcntl
import os
import sys
import time
import power_source

SLOT_DIR = os.path.expanduser("~/.cache/ot6/emu-slots")
CONF = os.path.expanduser("~/.config/ot6/emulator-slots")


def slots():
    try:
        with open(CONF) as f:
            for tok in f.read().split():
                if tok.isdigit() and int(tok) > 0:
                    return int(tok)
    except OSError:
        pass
    return os.cpu_count() or 1


def try_take(n):
    os.makedirs(SLOT_DIR, exist_ok=True)
    for k in range(n):
        fd = os.open(os.path.join(SLOT_DIR, str(k)), os.O_RDWR | os.O_CREAT, 0o644)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return k, fd
        except OSError:
            os.close(fd)
    return None, None


def held(n):
    count = 0
    os.makedirs(SLOT_DIR, exist_ok=True)
    for k in range(n):
        fd = os.open(os.path.join(SLOT_DIR, str(k)), os.O_RDWR | os.O_CREAT, 0o644)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(fd, fcntl.LOCK_UN)
        except OSError:
            count += 1
        finally:
            os.close(fd)
    return count


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def selftest():
    import subprocess
    import tempfile
    global SLOT_DIR, CONF
    with tempfile.TemporaryDirectory() as d:
        SLOT_DIR, CONF = os.path.join(d, "slots"), os.path.join(d, "conf")
        with open(CONF, "w") as f:
            f.write("3\n")
        env = dict(os.environ, EMU_SLOT_SELFTEST_DIR=d)
        owners = [subprocess.Popen(["sleep", "60"]) for _ in range(12)]
        holders = [subprocess.Popen([sys.executable, __file__, "--hold",
                                     str(o.pid), os.path.join(d, f"r{i}")], env=env)
                   for i, o in enumerate(owners)]
        # each owner (a run.sh stand-in) ends half a second after its slot
        # arrives, as a short run would
        peak, t0, since = 0, time.time(), {}
        while any(h.poll() is None for h in holders) and time.time() - t0 < 60:
            for i, o in enumerate(owners):
                if i not in since and os.path.exists(os.path.join(d, f"r{i}")):
                    since[i] = time.time()
                if i in since and time.time() - since[i] > 0.5 and o.poll() is None:
                    o.kill()
                o.poll()   # reap: a zombie owner still answers kill(pid, 0)
            peak = max(peak, held(3))
            time.sleep(0.05)
        got = sum(os.path.exists(os.path.join(d, f"r{i}")) for i in range(12))
        # a holder killed mid-hold frees its slot
        o = subprocess.Popen(["sleep", "30"])
        h = subprocess.Popen([sys.executable, __file__, "--hold", str(o.pid),
                              os.path.join(d, "k")], env=env)
        while not os.path.exists(os.path.join(d, "k")):
            time.sleep(0.05)
        before = held(3)
        h.kill(); h.wait(); o.kill(); o.wait()
        after = held(3)
    ok = peak <= 3 and peak >= 2 and got == 12 and before == 1 and after == 0
    print(f"emu_slot selftest: peak {peak} of 3, {got}/12 got a slot, "
          f"killed holder {before}->{after}: {'OK' if ok else 'FAIL'}")
    return 0 if ok else 1


def main():
    if os.environ.get("EMU_SLOT_SELFTEST_DIR"):   # only --selftest's children
        global SLOT_DIR, CONF
        d = os.environ["EMU_SLOT_SELFTEST_DIR"]
        SLOT_DIR, CONF = os.path.join(d, "slots"), os.path.join(d, "conf")
    if sys.argv[1:2] == ["--selftest"]:
        return selftest()
    if sys.argv[1:2] == ["--status"]:
        n = slots()
        print(held(n), n)
        return 0
    if len(sys.argv) != 4 or sys.argv[1] != "--hold":
        print(__doc__, file=sys.stderr)
        return 2
    owner, ready = int(sys.argv[2]), sys.argv[3]
    t0 = time.time()
    previous_reason = None
    while True:
        if not alive(owner):
            return 0
        n = slots()   # re-read: a machine's setting can change while we queue
        # Recheck while queued: a placement claim may precede unplugging.
        # Private slot selftests launch only sleep stand-ins, never emulators.
        reason = None if os.environ.get("EMU_SLOT_SELFTEST_DIR") else power_source.blocked(
            power_source.observe(), time.time())
        if reason != previous_reason:
            print(f"[emu-slot] {('waiting: ' + reason) if reason else 'AC power restored'}", flush=True)
            previous_reason = reason
        if reason:
            time.sleep(1)
            continue
        k, fd = try_take(n)
        if fd is not None:
            # Power could change while acquiring the slot; no running job is stopped.
            if not os.environ.get("EMU_SLOT_SELFTEST_DIR") and power_source.blocked(
                    power_source.observe(), time.time()):
                os.close(fd)
                continue
            break
        time.sleep(1)
    tmp = ready + ".tmp"
    with open(tmp, "w") as f:
        f.write(f"{k} {n} {int(time.time() - t0)}\n")
    os.replace(tmp, ready)
    while alive(owner):
        time.sleep(1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
