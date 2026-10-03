#!/usr/bin/env python3
"""savestate_ninja_selftest.py -- the savestate graph's build semantics,
end to end, against real ninja on a mock tree, with no emulator.

The mock tree holds the real graph emitter, compose.py, stamps.py,
lua_fingerprint.py and sram_checkpoint.py, mock lib files and generators,
and a stub run.sh that journals each run and "plays" deterministically: an
artifact's bytes are a function of the generator's `local OUT = "..."` line and the
bytes the run booted (its prev's state, or the capture it Continued), and
it publishes an artifact only when its bytes changed, as run.sh does.

The graph: a (power-on) saves k1, which b Continues (a cut); c follows b;
a cutter booted from c saves k2, which d Continues; e follows d and saves k3
(the frontier); a capture-only cutter lifts k4 from c; x is another
power-on root.

Each case moves one input and checks which runs ninja makes, and that the
stamps (stamps.py --check-states) agree with what ninja did.
"""

import base64
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REAL = Path(__file__).resolve().parents[3]
COPIED = ["tools/tests/lib/savestate_ninja.py", "tools/tests/lib/stamps.py",
          "tools/tests/lib/compose.py", "tools/tests/lib/lua_fingerprint.py",
          "tools/tests/lib/sram_checkpoint.py", "tools/build/rom_version.py"]

STUB_RUN = r'''#!/bin/sh
# stub run.sh: journal, injected failure, deterministic "play", publish an
# artifact only when its bytes changed, capture a 32 KiB battery.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SCRIPT="$1"
echo "$OT6_WORKER" >> build/journal
[ -e "build/fail.$OT6_WORKER" ] && { echo "injected failure"; exit 1; }
out=$(sed -n 's/^local OUT = "\(.*\)"$/\1/p' "$SCRIPT")
if [ -n "${OT6_SRAM_CHECKPOINT:-}" ]; then
  boot=$(cat "$OT6_SRAM_CHECKPOINT"/*.sram | shasum -a 256 | cut -c1-16)
else
  prev=$(sed -n 's/.*"build\/states\/\([A-Za-z0-9_]*\)\.mss\.lua".*/\1/p' "$SCRIPT" | head -n 1)
  boot=none
  [ -n "$prev" ] && boot=$(shasum -a 256 < "build/states/$prev.mss" | cut -c1-16)
fi
put() {  # <dest> <content>: write only when it changed
  printf '%s' "$2" > "$1.tmp.$$"
  if cmp -s "$1.tmp.$$" "$1" 2>/dev/null; then rm -f "$1.tmp.$$"
  else mv -f "$1.tmp.$$" "$1"; fi
}
if [ -z "${OT6_NO_PUBLISH:-}" ]; then
  for a in $OT6_EXPECT_ARTIFACT; do
    case "$a" in *.mss.lua) continue ;; esac
    s=${a%.mss}
    c="$s $out boot=$boot"
    put "build/states/$s.mss" "$c"
    put "build/states/$s.mss.lua" "return \"$(printf '%s' "$c" | base64 | tr -d '\n')\"
"
  done
fi
if [ -n "${OT6_CAPTURE_SRM:-}" ]; then
  mkdir -p "$(dirname "$OT6_CAPTURE_SRM")"
  python3 - "$OT6_CAPTURE_SRM" "$OT6_WORKER $out boot=$boot" <<'PY'
import sys, hashlib
seed = hashlib.sha256(sys.argv[2].encode()).digest()
data = (seed * (32768 // len(seed) + 1))[:32768]
try:
    old = open(sys.argv[1], "rb").read()
except OSError:
    old = None
if old != data:
    open(sys.argv[1], "wb").write(data)
PY
fi
exit 0
'''

GEN = '''-- {name}
local OUT = "{out}"
local H = dofile("tools/tests/lib/ot6.lua")
H.run({{}}, {{ {boot} }})
'''


class Tree:
    def __init__(self, root):
        self.root = root

    def p(self, rel):
        return self.root / rel

    def write(self, rel, text):
        path = self.p(rel)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def bump(self, rel):
        """An mtime-only touch, as a checkout makes."""
        os.utime(self.p(rel), None)

    def ninja(self, *args):
        r = subprocess.run(["ninja", "-f", "build/build.ninja", *args],
                           cwd=self.root, capture_output=True, text=True)
        j = self.p("build/journal")
        ran = sorted(j.read_text().split()) if j.exists() else []
        j.write_text("")
        return r.returncode, ran, r.stdout + r.stderr

    def dry(self):
        r = subprocess.run(["ninja", "-f", "build/build.ninja", "-n"],
                           cwd=self.root, capture_output=True, text=True)
        return r.stdout

    def check_states(self):
        r = subprocess.run([sys.executable, "tools/tests/lib/stamps.py",
                            "--check-states"], cwd=self.root,
                           capture_output=True, text=True)
        return r.returncode, r.stdout


def romfill(t, version_byte, code_byte):
    """A 64 KB mock ROM: `version_byte` in each version field
    (rom_version.py masks them), `code_byte` at $1234 (it does not)."""
    b = bytearray(b"\xa5" * 0x10000)
    for off in (0xFFA5, 0xFFC5, 0xFFDC):
        b[off] = version_byte
    b[0x1234] = code_byte
    t.p("build").mkdir(parents=True, exist_ok=True)
    t.p("build/ot6.sfc").write_bytes(bytes(b))


def mock(root):
    t = Tree(root)
    for rel in COPIED:
        t.p(rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(REAL / rel, t.p(rel))
    t.write("tools/tests/lib/ot6.lua", "local M = {}\nM.v = 1\nreturn M\n")
    t.write("tools/tests/lib/ot6_field.lua", "local M = ...\nM.f = 1\n")
    t.write("tools/tests/lib/ot6_contract.lua", "local M = ...\nM.c = 1\n")
    t.write("tools/tests/run.sh", STUB_RUN)
    os.chmod(t.p("tools/tests/run.sh"), 0o755)
    for rel in ("tools/tests/lib/pin_test_saves.py",
                "tools/tests/lib/decode_b64.py"):
        t.write(rel, "# stub\n")
    t.write("tools/state_write_waivers.txt", "")
    t.write("ff6/rom/ff6-en.dbg", "")
    t.write("tools/mesen/EMULATOR", "emulator v1\n")
    t.write("VERSION", "1.0\n")
    romfill(t, 1, 1)
    gens = {"gen_a": ("a1", ""), "gen_b": ("b1", ""),
            "gen_c": ("c1", 'H.loadState("build/states/b.mss.lua")'),
            "gen_cut": ("k2", 'H.loadState("build/states/c.mss.lua")'),
            "gen_d": ("d1", ""),
            "gen_e": ("e1", 'H.loadState("build/states/d.mss.lua")'),
            "gen_seed": ("k4", 'H.loadState("build/states/c.mss.lua")'),
            "gen_x": ("x1", "")}
    for g, (out, boot) in gens.items():
        t.write(f"tools/tests/{g}.lua", GEN.format(name=g, out=out, boot=boot))
    for key in ("k1-v1", "k2-v1", "k3-v1", "k4-v1"):
        d = f"tools/tests/checkpoints/{key}"
        t.write(f"{d}/{key[:2]}.sram", "x" * 32768)
        t.write(f"{d}/manifest.json", json.dumps({
            "schema": "ot6.sram-checkpoint/v1", "payload": f"{key[:2]}.sram",
            "size": 32768,
            "sha256": hashlib.sha256(b"x" * 32768).hexdigest(),
            "persistent_layout": "mock-layout/v1"}))
    t.write("tools/tests/savestate_graph.py", '''
def S(state, **kw):
    return dict({"state": state, "gen": None, "prev": None,
                 "checkpoint": None, "timeout": None,
                 "also": None, "saves": None, "cutter": None}, **kw)
STATES = [
    S("a", gen="gen_a"),
    S("b", gen="gen_b", prev="a", checkpoint="k1-v1"),
    S("c", gen="gen_c", prev="b"),
    S("d", gen="gen_d", prev="c", checkpoint="k2-v1", cutter="gen_cut"),
    S("e", gen="gen_e", prev="d", saves="k3-v1"),
    S("x", gen="gen_x"),
]
CAPTURES = [{"capture": "k4-v1", "cutter": "gen_seed", "prev": "c"}]
''')
    r = subprocess.run([sys.executable, "tools/tests/lib/savestate_ninja.py",
                        "--emit"], cwd=root, capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(f"emit failed: {r.stderr}")
    return t


def main():
    if not shutil.which("ninja"):
        print("savestate_ninja selftest: ninja not installed -- brew bundle")
        return 1
    ok = True

    def check(label, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print(f"  {'pass' if good else 'FAIL'} {label}"
              + ("" if good else f"\n       got  {got!r}\n       want {want!r}"))

    ALL = ["a", "b", "c", "capture_k2_v1", "capture_k4_v1", "d", "e", "x"]
    with tempfile.TemporaryDirectory() as td:
        t = mock(Path(td))
        rc, ran, log = t.ninja()
        check("a fresh tree builds", rc, 0)
        if rc:
            print(log[-3000:])
        check("...running every run once, cutters included", ran, ALL)
        check("the cut Continued the capture its producer made",
              t.p("build/checkpoints/k1-v1/k1.sram").exists()
              and "build/checkpoints/k1-v1" in
              t.p("build/states/b.stamp").read_text(), True)
        m = json.loads(t.p("build/checkpoints/k2-v1/manifest.json").read_text())
        check("each capture is sealed: authored fields, hash, provenance "
              "from its stamp",
              (m["persistent_layout"], m["provenance"]["ancestors"][0]["path"]),
              ("mock-layout/v1", "build/checkpoints/k2-v1.stamp"))
        check("the frontier's and the capture-only cutter's saves are sealed",
              all(t.p(f"build/checkpoints/{k}/manifest.json").exists()
                  for k in ("k3-v1", "k4-v1")), True)
        rc, out = t.check_states()
        check("after a build every stamp is current", rc, 0)

        rc, ran, log = t.ninja()
        check("an untouched tree runs nothing", (ran, "no work to do" in log),
              ([], True))

        for rel in ("build/ot6.sfc", "tools/mesen/EMULATOR",
                    "tools/tests/run.sh", "tools/tests/gen_c.lua",
                    "tools/tests/lib/ot6.lua", "tools/tests/lib/compose.py",
                    "tools/state_write_waivers.txt",
                    "tools/tests/checkpoints/k1-v1/manifest.json"):
            t.bump(rel)
        rc, ran, log = t.ninja()
        check("mtime-only touches (a checkout) replay nothing", ran, [])
        rc, ran, log = t.ninja()
        check("...and leave nothing for the next ninja", "no work to do" in log,
              True)

        # -- the uniform rule: every input of a run, by content -----------
        romfill(t, 1, 2)
        check("dry run after a ROM change lists every run",
              sum(1 for l in t.dry().splitlines()
                  if " generate " in l or " capture " in l), 8)
        rc, out = t.check_states()
        check("...and the stamps call it a different ROM",
              (rc, "a machine snapshot of a different ROM" in out), (1, True))
        rc, ran, _ = t.ninja()
        check("MUTANT a ROM change replays the whole game", ran, ALL)
        romfill(t, 2, 2)
        rc, ran, _ = t.ninja()
        check("a change to the ROM's version fields alone (a VERSION bump) "
              "replays nothing", ran, [])
        rc, out = t.check_states()
        check("...and the stamps, which record the ROM's identity, agree",
              rc, 0)
        check("...while the ROM's copy still takes the new bytes",
              t.p("build/ot6.sfc").read_bytes() ==
              t.p("build/ninja/src/build/ot6.sfc").read_bytes(), True)
        rc, ran, log = t.ninja()
        check("MUTANT ...and the next ninja has no work at all (a stamp "
              "that did not move is not left looking out of date)",
              "no work to do" in log, True)
        t.write("tools/mesen/EMULATOR", "emulator v2\n")
        rc, ran, _ = t.ninja()
        check("an emulator pin change replays the whole game", ran, ALL)
        t.write("tools/tests/run.sh",
                STUB_RUN.replace("set -u\n", "set -u\n# v2\n", 1))
        rc, ran, _ = t.ninja()
        check("a runner change replays the whole game", ran, ALL)

        t.write("tools/tests/lib/ot6.lua", "local M = {}\nM.v = 2\nreturn M\n")
        rc, out = t.check_states()
        check("MUTANT a lib code edit: the stamps call every run stale "
              "(no provenance-drift exemption)",
              (rc, "tools/tests/lib/ot6.lua moved" in out), (1, True))
        rc, ran, _ = t.ninja()
        check("MUTANT a lib code edit replays the whole game", ran, ALL)
        rc, out = t.check_states()
        check("...after which every stamp is current again", rc, 0)

        t.write("tools/tests/lib/ot6.lua",
                "-- why\nlocal M = {}\n\n  M.v = 2  -- note\nreturn M\n")
        rc, ran, log = t.ninja()
        check("a lib comment-only edit replays nothing (its Lua copy keeps "
              "its mtime)", ran, [])
        check("...the copy is the only edge that ran",
              [l.split("] ", 1)[1].split()[0] for l in log.splitlines()
               if l.startswith("[")], ["copy_if_lua_changed"])

        t.write("tools/tests/lib/compose.py",
                t.p("tools/tests/lib/compose.py").read_text() + "\n# note\n")
        rc, ran, log = t.ninja()
        check("compose.py edited without moving any composed program: "
              "every digest re-runs, nothing replays", ran, [])
        t.write("tools/state_write_waivers.txt", "tools/tests/gen_zz.lua\temu.write\n")
        rc, ran, _ = t.ninja()
        check("another script's waiver replays nothing", ran, [])
        t.write("tools/state_write_waivers.txt", "tools/tests/gen_x.lua\temu.write\n")
        rc, ran, _ = t.ninja()
        check("x's own waiver (its write gate off) re-runs x alone", ran, ["x"])

        t.write("tools/tests/lib/stamps.py",
                t.p("tools/tests/lib/stamps.py").read_text() + "\n# note\n")
        rc, ran, log = t.ninja()
        check("a stamp-tool edit rewrites stamps and replays nothing",
              (ran, " stamp " in log or "stamp build" in log), ([], True))
        rc, ran, log = t.ninja()
        check("MUTANT ...and a stamp whose text did not move is not left "
              "looking out of date (the next ninja has no work)",
              "no work to do" in log, True)

        # -- a generator: that run, then what its bytes reach -------------
        t.write("tools/tests/gen_c.lua", t.p("tools/tests/gen_c.lua")
                .read_text().replace('OUT = "c1"', 'OUT = "c2"'))
        dry = t.dry()
        check("a generator change: the dry run lists that run and every "
              "run downstream",
              sorted({l.split("generate ")[1].split()[0] if " generate " in l
                      else "capture_" + l.split("capture ")[1].split()[0]
                      .replace("-", "_")
                      for l in dry.splitlines()
                      if " generate " in l or " capture " in l}),
              ["c", "capture_k2_v1", "capture_k4_v1", "d", "e"])
        rc, ran, _ = t.ninja()
        check("MUTANT a generator change that moves its bytes replays it "
              "and its descendants", ran,
              ["c", "capture_k2_v1", "capture_k4_v1", "d", "e"])
        t.write("tools/tests/gen_c.lua", t.p("tools/tests/gen_c.lua")
                .read_text().replace("H.run({}", "H.run({ x = 1 }"))
        rc, ran, _ = t.ninja()
        check("a generator change that plays to the same bytes stops at "
              "that run (restat)", ran, ["c"])
        rc, out = t.check_states()
        check("...and every stamp is current", rc, 0)

        # -- the capture a cut boots ---------------------------------------
        t.write("tools/tests/gen_a.lua", t.p("tools/tests/gen_a.lua")
                .read_text().replace('OUT = "a1"', 'OUT = "a2"'))
        rc, ran, _ = t.ninja()
        check("a producer whose save moved replays the cut that Continues "
              "it, and on down", ran,
              ["a", "b", "c", "capture_k2_v1", "capture_k4_v1", "d", "e"])
        t.write("tools/tests/checkpoints/k1-v1/k1.sram", "y" * 32768)
        rc, ran, _ = t.ninja()
        check("a tracked checkpoint (a re-cut) replays nothing: the graph "
              "boots its own capture", ran, [])
        man = json.loads(t.p("tools/tests/checkpoints/k1-v1/manifest.json")
                         .read_text())
        t.write("tools/tests/checkpoints/k1-v1/manifest.json",
                json.dumps(dict(man, note="authored")))
        rc, ran, log = t.ninja()
        check("an authored manifest edit re-seals and re-runs the cut that "
              "Continues it, not its producer (and the cut's same bytes "
              "stop there)", (ran, "seal build/checkpoints/k1-v1" in log),
              (["b"], True))

        # -- failure --------------------------------------------------------
        t.write("build/fail.c", "")
        t.write("tools/tests/gen_c.lua", t.p("tools/tests/gen_c.lua")
                .read_text().replace('OUT = "c2"', 'OUT = "c3"'))
        rc, ran, _ = t.ninja()
        check("a failing run fails the build and blocks what boots it",
              (rc != 0, ran), (True, ["c"]))
        t.p("build/fail.c").unlink()
        rc, ran, _ = t.ninja()
        check("the retry runs it and its descendants",
              (rc, ran), (0, ["c", "capture_k2_v1", "capture_k4_v1", "d", "e"]))
        rc, _, log = t.ninja("no-such-target")
        check("an unknown target is a hard error",
              (rc != 0, "unknown target" in log), (True, True))
    print("savestate_ninja selftest:", "ok" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
