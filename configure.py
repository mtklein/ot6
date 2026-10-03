#!/usr/bin/env python3
"""configure.py -- emit ./build.ninja, the whole project as one ninja graph.

Bare `ninja` builds and tests everything: the default targets are the
ROM, every generated savestate and checkpoint capture, every suite test's
result, every audit and selftest, and the checkpoint drift gate.  There are
no aliases: anything narrower is a real output path
(`ninja build/states/vargas_entry.mss.lua`,
`ninja build/results/suite/battle_break.ok`, `ninja ff6/rom/ff6-en.sfc`),
and the release is `ninja build/release/ot6-vX.Y.zip
build/release/ot6-vX.Y.apk build/checks/android_apk.ok
build/checks/android_apk_release.ok` (everything in the default, the
release preflights, the patch, the zip and the Android patcher APK with its
checks).
Every edge depends on its true inputs by content, so `ninja` re-runs
exactly what a change invalidates: a ROM, emulator, generator, runner or
test-library change replays the game from the first run it reaches, and a
suite or check edit re-runs that suite or check.
Parallelism is ninja's own, unbounded; emulator-running commands are
prefixed with nice(1).

Structure of the graph (all paths relative to the repo root; run `ninja`
from the root):

  ff6 assets     tracked-source encoders: text json -> .dat/.inc, mml ->
                 song/sfx .asm, monster stencils, lzss compression, the SPC
                 program.  They write tracked paths (committed outputs; a
                 build from a clean git tree reproduces them byte-for-byte).
                 Never `ninja -t clean`: it deletes those tracked outputs,
                 and the encoders update several of them in place
                 (update_array_inc.py asserts the .inc exists), so the tree
                 can no longer build.  A clean build means a clean git tree
                 (`git status` empty), not a cleaned build directory.
  ff6 objects    ca65 with --create-dep; depfiles are rebased to root-relative
                 paths (tools/build/rebase_depfile.py) because ca65 runs with
                 cwd=ff6 and ninja resolves depfile paths against the root.
  ROM            ff6-en.sfc via tools/build/link_rom.sh, which stamps the
                 version fields from VERSION (tools/build/rom_version.py).
  build/ot6.sfc  copy_if_changed of ff6-en.sfc: mtime bumps with unchanged
                 bytes prune everything downstream (restat).  Everything
                 that binds to the ROM (states, suite results, checks)
                 depends on its identity copy instead
                 (copy_if_rom_identity_changed: the version fields masked),
                 so a VERSION bump re-runs only what reads those fields.
  savestates     the one graph of generated states and checkpoint captures,
                 played from power-on, embedded from
                 tools/tests/lib/savestate_ninja.py (the data file is
                 tools/tests/savestate_graph.py).
  suite          one edge per `-- @suite` test, after a digest edge for its
                 composed script (compose.py --digest, restat): the suite
                 re-runs when its composed program, the ROM's identity, the
                 emulator pin, the runner or a checkpoint it boots moved.
                 A test whose fixture is missing builds the fixture, and
                 the release artifact depends on every test's .ok, so
                 "everything ran" is graph structure.
  checks         the selftests and audits, each with its real inputs, so an
                 unchanged tree re-runs none of them; among them the drift
                 gate, every tracked checkpoint against the graph's capture.
  release        preflights (branch, README version, real notes), the BPS
                 patch, the zip (build/release/ot6-vX.Y.zip), and the
                 Android patcher APK with its checks
                 (build/release/ot6-vX.Y.apk, build/checks/android_apk.ok,
                 build/checks/android_apk_release.ok; they need the JDK,
                 the Android SDK and the signing key, which the default
                 does not).

Regeneration: the `configure` edge below re-runs this script when it, the
graph data, VERSION, or any globbed directory changes (the depfile lists
every file AND directory this script read, so adding a test or a source
file re-configures).
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tools" / "tests" / "lib"))
import savestate_ninja as sn  # noqa: E402
sys.path.insert(0, str(ROOT / "tools" / "build"))
import rom_version  # noqa: E402

VERSION = (ROOT / "VERSION").read_text().strip()
# The one VERSION grammar (tools/build/rom_version.py check_version): the APK
# versionCode and the ROM's 15-cell version field both need it, so a VERSION
# outside it fails here, before anything builds.
try:
    rom_version.check_version(VERSION)
except ValueError as e:
    sys.exit(f"configure.py: {e}")
BASE = "Final Fantasy III (USA).sfc"
BASE_SHA1 = "4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7"

read_deps = set()   # every file/dir this script consulted -> configure.d


def glob(pattern, base="."):
    basep = ROOT / base
    hits = sorted(str(p.relative_to(ROOT)) for p in basep.glob(pattern)
                  if p.is_file())
    # record the dirs the glob walked, so an added/removed file (which bumps
    # the dir mtime) re-runs configure
    # (the parent dirs, not `base` itself: ff6/'s own mtime bumps every time
    # a ROM link creates and removes temp_lz, which would re-run configure
    # on every build for nothing)
    for p in hits:
        read_deps.add(str(Path(p).parent))
    return hits


def esc(path):
    """ninja path escaping: spaces only (no $ or : in any path here)."""
    return path.replace("$", "$$").replace(" ", "$ ")


class Writer:
    def __init__(self):
        self.lines = []

    def __call__(self, s=""):
        self.lines.append(s)

    def edge(self, outs, rule, ins=(), implicit=(), order=(), **vars):
        outs = " ".join(esc(o) for o in outs)
        parts = [f"build {outs}: {rule}"]
        if ins:
            parts.append(" " + " ".join(esc(i) for i in ins))
        if implicit:
            parts.append(" | " + " ".join(esc(i) for i in implicit))
        if order:
            parts.append(" || " + " ".join(esc(i) for i in order))
        self("".join(parts))
        for k, v in vars.items():
            if v:
                self(f"  {k} = {v}")


w = Writer()

# ---------------------------------------------------------------- header --
w("# AUTOGENERATED by configure.py -- do not edit.  `ninja` regenerates it.")
w("ninja_required_version = 1.3")
w("builddir = build/ninja")
w()
w("rule sh")
w("  command = $cmd")
w("  description = $desc")
w()
w("# copy_if_changed: re-runs on any mtime bump, rewrites only on a byte")
w("# change; restat = 1 prunes everything downstream when it did not.")
w("rule copy_if_changed")
w("  command = mkdir -p $$(dirname $out) && { cmp -s $in $out || cp $in $out; }")
w("  description = copy_if_changed $in")
w("  restat = 1")
w()
w("# The ROM's copy, the same shape: the new bytes always land, but the")
w("# old mtime is kept when the ROM identity (the ROM with its version")
w("# fields masked, tools/build/rom_version.py) did not move, so a VERSION")
w("# bump alone re-runs nothing that binds to the ROM's identity.")
w("rule copy_if_rom_identity_changed")
w("  command = python3 tools/build/rom_version.py "
  "copy-if-identity-changed $in $out")
w("  description = copy_if_rom_identity_changed $in")
w("  restat = 1")
w()
w("# A Lua source's copy: the new bytes always land, but the old mtime is")
w("# kept when the Lua token stream (comments and whitespace dropped) did")
w("# not move, so restat prunes a comment-only edit (#247).")
w("rule copy_if_lua_changed")
w("  command = python3 tools/tests/lib/lua_fingerprint.py "
  "copy-if-changed $in $out")
w("  description = copy_if_lua_changed $in")
w("  restat = 1")
w()
w("# ca65 runs with cwd=ff6 (sources use ff6-relative include/incbin paths);")
w("# the depfile it writes is therefore ff6-relative and gets rebased to the")
w("# repo root before ninja parses it (deps = gcc).")
w("rule ca65")
w("  command = cd ff6 && ca65 $flags --create-dep $rawdep -l $lst $src -o $obj"
  " && cd .. && python3 tools/build/rebase_depfile.py ff6 $depfile")
w("  depfile = $depfile")
w("  deps = gcc")
w("  description = ca65 $obj")
w()
sn.emit_state_rules(w)
w("# One suite test: compose, boot Mesen headless, publish the log, touch the")
w("# ok.  $env carries the per-test environment (dirty-RAM pins, checkpoint")
w("# batteries, coverage artifact dirs); the separating space lives here.")
w("rule suitetest")
w("  command = $env nice tools/build/run_suite_test.sh $test $out")
w("  description = suite $test")
w()

# -------------------------------------------------------- copy_if_changed --
copy_if_changed_edges = {}
lua_copy_edges = {}


def copy_if_changed_from(src):
    dep = f"build/ninja/src/{src}"
    copy_if_changed_edges[dep] = src
    return dep


def lua_copy_from(src):
    dep = f"build/ninja/src/lua/{src}"
    lua_copy_edges[dep] = src
    return dep


# ------------------------------------------------------------- ff6 assets --
generated = []          # order-only gate for every object: encoders ran first
codec = ["ff6/tools/encode_text.py"] + glob("tools/romtools/*.py", "ff6") \
    + glob("tools/char_table/*.json", "ff6")

text_edges = []
dlg = {"ff6/src/text/dlg1_en.json", "ff6/src/text/dlg2_en.json"}
for j in glob("src/text/*_en.json", "ff6") + ["ff6/src/text/mte_tbl_jp.json"]:
    if j in dlg:
        continue
    import json as _json
    spec = _json.loads((ROOT / j).read_text())
    read_deps.add(j)
    dat = j[:-len(".json")] + ".dat"
    outs = [dat]
    if "inc_path" in spec:
        outs.append("ff6/" + spec["inc_path"])
    w.edge(outs, "sh", [j], implicit=codec,
           cmd=f"cd ff6 && python3 tools/encode_text.py {j[len('ff6/'):]}",
           desc=f"encode_text {j}")
    generated += outs
# the dlg pair: split, encode both, recombine -- one edge, both dats out.
# The json INPUTS arrive through copy_if_changed edges because split/combine
# rewrite them in place (strings migrate across the two-file boundary and
# back, byte-identically): the copy re-runs on the mtime bump, finds the
# bytes unchanged, and restat prunes this edge instead of cycling it.
w.edge(["ff6/src/text/dlg1_en.dat", "ff6/src/text/dlg2_en.dat",
        "ff6/include/text/dlg1_en.inc", "ff6/include/text/dlg2_en.inc"],
       "sh", [copy_if_changed_from(j) for j in sorted(dlg)],
       implicit=codec + ["ff6/tools/fix_dlg.py"],
       cmd="cd ff6 && python3 tools/fix_dlg.py split en"
           " && python3 tools/encode_text.py src/text/dlg1_en.json"
           " && python3 tools/encode_text.py src/text/dlg2_en.json"
           " && python3 tools/fix_dlg.py combine en"
           # split AND combine rewrite the dlg json INPUTS in place (strings
           # migrate across the two-file boundary and back), so without this
           # the inputs are always newer than the outputs and the edge re-runs
           # forever -- the old Makefile rule ended with the same touch.
           " && touch src/text/dlg1_en.dat src/text/dlg2_en.dat"
           " include/text/dlg1_en.inc include/text/dlg2_en.inc",
       desc="encode dlg1/dlg2")
generated += ["ff6/src/text/dlg1_en.dat", "ff6/src/text/dlg2_en.dat",
              "ff6/include/text/dlg1_en.inc", "ff6/include/text/dlg2_en.inc"]

w.edge(["ff6/src/menu/menu_text_en.inc.raw"], "sh",
       ["ff6/src/menu/menu_text_en.inc"],
       implicit=["ff6/tools/encode_menu_text.py"],
       cmd="cd ff6 && python3 tools/encode_menu_text.py"
           " src/menu/menu_text_en.inc",
       desc="encode_menu_text en")
generated += ["ff6/src/menu/menu_text_en.inc.raw"]

for mml in glob("src/sound/song_script/*.mml", "ff6"):
    asm = mml[:-len(".mml")] + ".asm"
    w.edge([asm], "sh", [mml],
           implicit=["ff6/tools/encode_mml.py",
                     "ff6/tools/romtools/bytes_to_asm.py"],
           cmd=f"cd ff6 && python3 tools/encode_mml.py {mml[len('ff6/'):]}",
           desc=f"encode_mml {Path(mml).stem}")
    generated.append(asm)
for mml in glob("src/sound/sfx_script/*.mml", "ff6"):
    asm = mml[:-len(".mml")] + ".asm"
    w.edge([asm], "sh", [mml],
           implicit=["ff6/tools/encode_sfx.py"],
           cmd=f"cd ff6 && python3 tools/encode_sfx.py {mml[len('ff6/'):]}",
           desc=f"encode_sfx {Path(mml).stem}")
    generated.append(asm)

# Monster .trm/.stn pairs are ripped ROM data, tracked and consumed as-is;
# they are NOT regenerated here.  monster_stencil.py's zero-tile trim is not
# display-equivalent to Square's own choices -- regenerating ghosttrain's
# pair dropped a kept-but-empty tile and the Phantom Train fight froze with
# the train's sprite never arriving.  Run the tool by hand only for a
# monster graphic that was actually edited, and verify that fight in-game.

# lzss: the same two source classes the old Makefile derived from tracked
# sources (sprintf-consumed directories and literal incbin paths)
LZ_SPRINTF_DIRS = [
    "src/field/map_tile_prop", "src/field/map_tileset",
    "src/field/overlay_prop", "src/field/sub_tilemap",
    "src/gfx/battle_bg_tiles", "src/gfx/battle_bg_gfx",
    "src/gfx/map_gfx_bg3", "src/gfx/map_anim_gfx_bg3",
]
LZ_LITERAL = [
    "src/gfx/airship1.4bpp", "src/gfx/airship2.4bpp",
    "src/gfx/attack_mode7.4bpp", "src/gfx/attack_mode7.scr",
    "src/gfx/credits.4bpp", "src/gfx/ending_font.2bpp",
    "src/gfx/ending1.4bpp", "src/gfx/ending2.4bpp", "src/gfx/ending3.4bpp",
    "src/gfx/ending4.4bpp", "src/gfx/ending5.4bpp",
    "src/gfx/floating_cont.4bpp", "src/gfx/magitek_train.cgx",
    "src/gfx/minimap_1.4bpp", "src/gfx/minimap_2.4bpp",
    "src/gfx/ruin_cutscene.4bpp",
    "src/gfx/status_en.4bpp", "src/gfx/status_jp.4bpp",
    "src/gfx/title_opening_en.4bpp", "src/gfx/title_opening_jp.4bpp",
    "src/gfx/vector_approach.4bpp", "src/gfx/vector_approach.scr",
    "src/gfx/world_1_bg.4bpp", "src/gfx/world_2_bg.4bpp",
    "src/gfx/world_3_bg.4bpp", "src/gfx/world_3.pal",
    "src/gfx/world_anim_sprite.4bpp", "src/gfx/world_misc_sprite.4bpp",
    "src/gfx/world_backdrop.4bpp", "src/gfx/world_backdrop.scr",
    "src/gfx/world_choco_1.4bpp", "src/gfx/world_choco_2.4bpp",
    "src/world/world_1_tilemap.dat", "src/world/world_2_tilemap.dat",
    "src/world/world_3_tilemap.dat",
]
lz_srcs = []
for d in LZ_SPRINTF_DIRS:
    lz_srcs += [f for f in glob(f"{d}/*", "ff6") if not f.endswith(".lz")]
lz_srcs += [f"ff6/{p}" for p in LZ_LITERAL if (ROOT / "ff6" / p).is_file()]
for src in lz_srcs:
    w.edge([src + ".lz"], "sh", [src],
           implicit=["ff6/tools/ff6_lzss.py"],
           cmd=f"cd ff6 && python3 tools/ff6_lzss.py {src[len('ff6/'):]}"
               f" {src[len('ff6/'):]}.lz",
           desc=f"lzss {Path(src).name}")
    generated.append(src + ".lz")

# the SPC program (assembled + linked separately, then .incbin'd by sound)
w.edge(["ff6/obj/ff6-spc.o"], "ca65", ["ff6/src/sound/ff6-spc.asm"],
       order=generated,
       flags="-g -I include", rawdep="obj/ff6-spc.d",
       depfile="ff6/obj/ff6-spc.d", lst="obj/ff6-spc.lst",
       src="src/sound/ff6-spc.asm", obj="obj/ff6-spc.o")
w.edge(["ff6/src/sound/ff6-spc.dat"], "sh",
       ["ff6/cfg/ff6-spc.cfg", "ff6/obj/ff6-spc.o"],
       cmd="cd ff6 && ld65 -o src/sound/ff6-spc.dat -C cfg/ff6-spc.cfg"
           " obj/ff6-spc.o",
       desc="link ff6-spc.dat")
generated.append("ff6/src/sound/ff6-spc.dat")

# ------------------------------------------------------------ ff6 objects --
MODULES = ["field", "btlgfx", "battle", "menu", "sound", "cutscene",
           "event", "world", "gfx", "text"]
EN_FLAGS = "-g -I include -D LANG_EN=1 -D ROM_VERSION=0"
inc_files = glob("include/*.inc", "ff6") + glob("include/*/*.inc", "ff6")


def module_obj(mod, obj, flags):
    srcs = glob(f"src/{mod}/*", "ff6") + glob(f"src/{mod}/*/*", "ff6")
    srcs = [s for s in srcs if not s.endswith((".lz", ".lst", ".d"))]
    w.edge([f"ff6/obj/{obj}.o"], "ca65", [f"ff6/src/{mod}/{mod}_main.asm"],
           implicit=srcs + inc_files, order=generated,
           flags=flags, rawdep=f"obj/{obj}.d",
           depfile=f"ff6/obj/{obj}.d", lst=f"obj/{obj}.lst",
           src=f"src/{mod}/{mod}_main.asm", obj=f"obj/{obj}.o")
    return f"ff6/obj/{obj}.o"


objs_en = [module_obj(m, f"{m}_en", EN_FLAGS) for m in MODULES]

# ---------------------------------------------------------------- ROMs -----
def rom_edge(out, objs):
    rel = [o[len("ff6/"):] for o in objs]
    w.edge([out, out[:-len(".sfc")] + ".dbg", out[:-len(".sfc")] + ".map"],
           "sh", ["ff6/cfg/ff6-en.cfg"] + objs,
           implicit=["tools/build/link_rom.sh", "ff6/tools/encode_cutscene.py",
                     "ff6/tools/fix_checksum.py", "tools/build/rom_version.py",
                     "VERSION"],
           cmd=f"tools/build/link_rom.sh cfg/ff6-en.cfg {out[len('ff6/'):]} "
               + " ".join(rel),
           desc=f"link {Path(out).name}")


rom_edge("ff6/rom/ff6-en.sfc", objs_en)

# ------------------------------------------------------------- ot6 layer ---
qual = []   # every .ok the release patch depends on

w.edge(["build/checks/base_rom.ok"], "sh", [BASE],
       cmd=f'echo "{BASE_SHA1}  {BASE}" | shasum -a 1 -c - >/dev/null'
           f' && mkdir -p build/checks && touch build/checks/base_rom.ok',
       desc="verify base ROM (FF3us 1.0)")
qual.append("build/checks/base_rom.ok")

# build/ot6.sfc is a copy of the linked ROM rewritten only when its bytes
# change: a relink that produces identical bytes regenerates nothing downstream.
w.edge(["build/ot6.sfc"], "copy_if_changed", ["ff6/rom/ff6-en.sfc"])

# ------------------------------------------------------------ savestates ---
states = sn.load(ROOT)
captures = sn.load_captures(ROOT)
read_deps.add(sn.GRAPH)
# configure-time: a malformed entry, or a tracked checkpoint no run on the
# graph saves (the drift gate would miss it), stops here
errors = sn.validate(states, ROOT, captures)
if errors:
    for e in errors:
        print(f"savestate_graph: {e}", file=sys.stderr)
    sys.exit(1)
state_mss = sn.emit_state_edges(w, states, ROOT, copy_if_changed_from,
                                lua_copy_from, captures)
# Every name a test can reference includes the `also=` siblings: a state
# like figaro_cleared is emitted by gen_edgar's edge as an also-artifact,
# and a filter against primary names only would drop it, leaving an edge
# that races its fixture on a from-scratch build.
state_names = {e["state"] for e in states} \
            | {a for e in states if e["also"] for a in e["also"]}
all_mss = [m for e in states for m in state_mss[e["state"]]]
gate_keys = sorted(sn.producers(states, captures))

# ------------------------------------------------------------------ suite --
LIBS = list(sn.LIB_FILES)
# What a suite's run executes besides its composed script (savestate_ninja's
# RUN_INPUTS, plus the suite wrapper; a suite that Continues a checkpoint
# adds its materialize, below).
SUITE_RUN = [copy_if_changed_from(p) for p in sn.RUN_INPUTS] \
    + [copy_if_changed_from("tools/build/run_suite_test.sh")]
COMPOSE_DEPS = [lua_copy_from(p) for p in LIBS] \
    + [copy_if_changed_from(p) for p in sn.COMPOSE_INPUTS]

# Tests that boot power-on under a dirty deterministic RAM fill and/or
# cold-Continue a tracked checkpoint battery.
TEST_ENV = {
    "battle_reveal_poweron": "OT6_RAM_POWERON=AllOnes "
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/terra-returned-v1",
    "battle_slotsboot":
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/terra-returned-v1",
    "battle_slots":
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/terra-returned-v1",
    # #346: Setzer's party on a natural boot, as battle_slots.  Its runs end
    # between 7,389 and 43,474 frames (14 runs), about 7 minutes at the
    # ~100 frames/s a loaded machine emulates, close to the 600 s default
    "battle_slotcancel": "OT6_TIMEOUT=1800 "
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/terra-returned-v1",
    # Mimic (#260): no fixture has Gogo, so the test Continues fire-out-v1
    # and declares a two-byte command expedient (state_write_waivers.txt)
    "battle_mimic":
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/fire-out-v1",
    # #292: NUMBER 024 (7 shields) is two steps from this save point
    "battle_hudcount":
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/n024-entry-save-v1",
    # Phoenix (#293): no fixture has it, so the test Continues fire-out-v1
    # and declares a one-byte esper expedient (state_write_waivers.txt)
    "battle_phoenixprice":
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/fire-out-v1",
    # #327: TERRA knows Life and pays Life 3 here; no write needed
    "battle_lifefold":
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/fire-out-v1",
    # #319: SETZER's kit, played in Darill's Tomb's east room from the
    # battery cut on its save point (SETZER back in the World of Ruin, so
    # Jackpot is learned).  A run is the Continue, a walk and one to four
    # battles: 6-30k frames (battle_jackpot plays Dullahan from wor_grave)
    # battle_jackpot: three passes and a bounded search (at most 192 throws)
    "battle_jackpot": "OT6_TIMEOUT=3600",
    "battle_cointoss": "OT6_TIMEOUT=3600 "
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-tomb-v1",
    "battle_hiredhelp": "OT6_TIMEOUT=1800 "
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-tomb-v1",
    "battle_setzergrey": "OT6_TIMEOUT=1800 "
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-tomb-v1",
    "battle_gprain": "OT6_TIMEOUT=3600 "
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-tomb-v1",
    "battle_hirerefund": "OT6_TIMEOUT=1800 "
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-tomb-v1",
    # battle_passretarget: 3-21 battles over its entry variations (11k-85k
    # frames, build/attempts/wt/pass-retarget/sweep/), more when the
    # re-split takes its ten crowds
    "battle_passretarget": "OT6_TIMEOUT=3600 "
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-tomb-v1",
    "battle_setzeraim": "OT6_TIMEOUT=1800 "
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-tomb-v1",
    "battle_passside": "OT6_TIMEOUT=1800 "
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-tomb-v1",
    # wt/hire-sprite: the 3 and 2 BP hires' figures (Defends bank the points)
    "battle_hirecrew": "OT6_TIMEOUT=2400 "
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-tomb-v1",
    # the Config screen's version tab, from the Narshe exit spawn
    "menu_configversion":
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/narshe-mission-v1",
    # walks from the Narshe exit spawn into the Beginner's House
    "school":
        "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/narshe-mission-v1",
    # grinds honest world-map fights until the 1/16 Shadow-leave roll passes:
    # an 80-win cap at ~4000 frames a win is ~320k frames, ~1600 s at the
    # ~200 frames/s a loaded machine emulates; the 600 s default cap is far short
    "battle_shadowstays": "OT6_TIMEOUT=3600",
    # each budgets its encounters for EVERY encounter-counter state the
    # game can deal, not the fixture's (lib/ot6_field.lua's
    # worstCaseEncounters), so its worst case is well past the default cap
    # even though a typical run is short: classtarget's 23 lane encounters
    # plus the A/B are ~66k frames; statuses' 36 battles for 16 exposures
    # ~115k; levelup's 40-battle step list ~85k -- at the ~100 frames/s a
    # loaded machine emulates, 11 to 19 minutes
    "battle_classtarget": "OT6_TIMEOUT=3600",
    # at worst four rungs of battle 70 (the ladder's derivation is in the
    # suite): the longest prep measured is 2,663 frames and the longest rung
    # 21,147 (a rung's start to the next rung or the verdict, over 214
    # rungs), so 2,663 + 4 x 21,147 = 87,251 frames.  The slowest rate over
    # the long runs is 80.7 frames/s (the Air, heavily loaded; the Mac at
    # load 12 ran 187.5-236.2): 1,081 s.  1800 is 1.67x that
    # (build/attempts/wt/suite-honesty/brokendeath/round2/)
    "battle_brokendeath": "OT6_TIMEOUT=1800",
    # the bench and its gate lengthen the measured battle: the longest bodies
    # measured are 27,432 frames for the first half (K6) and 9,790 for the
    # Rage half (K4), ~37k frames, 461 s at the 80.7 frames/s above, and a
    # draw that needs more fight retries spends a round (up to 3,345 frames
    # measured) per try; 1800 is 3.9x the measured body
    # (build/attempts/wt/procboost-v024/summary.txt).  The magicite case's
    # worst draw, all eleven tries measuring nothing, played the first half
    # in 88,082 frames (2,907 -> 90,989; with the Rage half's 9,790, ~97.9k
    # frames, 1,213 s at 80.7 frames/s): 1800 is 1.48x it
    # (build/attempts/wt/procboost-magicite/neg/nomeasure_k1.log.gz)
    "battle_procboost": "OT6_TIMEOUT=1800",
    "battle_statuses": "OT6_TIMEOUT=3600",
    "battle_levelup": "OT6_TIMEOUT=3600",
}

# Tests about the version fields themselves (tools/build/rom_version.py):
# everything else binds to the ROM's identity, which leaves those fields
# out, so these also depend on the ROM's bytes (and, through OT6_VERSION in
# their composed program, on VERSION), and the release commit's VERSION bump
# re-runs them on the bytes that ship.
VERSION_TESTS = {"menu_configversion", "title_version"}

# any <name>.mss reference, path-qualified or bare -- compose.py resolves
# both against build/states, so both are fixture dependencies; the filter
# against the graph's state names keeps false positives out
def fixture_deps(lua_path):
    """The sidecars a script's composition embeds (compose.py's own rule,
    savestate_ninja.fixture_refs)."""
    return [f"build/states/{fx}.mss.lua"
            for fx in sn.fixture_refs(ROOT, lua_path, state_names)]


suite_tests = []
for f in glob("tools/tests/*.lua"):
    text = (ROOT / f).read_text(errors="replace")
    m = re.search(r"^-- @suite(.*)$", text, re.M)
    if not m:
        continue
    t = Path(f).stem
    suite_tests.append(t)
    attrs = m.group(1)
    env = TEST_ENV.get(t, "")
    # The suite's composed program: its script, the lib it inlines, the
    # sidecars it embeds, the write gate, its symbols -- compared by token
    # stream, so an edit that leaves the program alone stops at the digest.
    sidecars = fixture_deps(f)
    fm = re.search(r"savestate=([A-Za-z0-9_]+)", attrs)
    if fm and f"build/states/{fm.group(1)}.mss.lua" not in sidecars:
        sidecars.append(f"build/states/{fm.group(1)}.mss.lua")
    digest = f"{sn.DIGEST_DIR}/suite_{t}.digest"
    w.edge([digest], "compose_digest", [f], implicit=COMPOSE_DEPS + sidecars,
           script=f, env=env)
    # The run: the emulator pin too, since a test result is the emulator's
    # as much as the ROM's.
    deps = [digest] + SUITE_RUN
    if t in VERSION_TESTS:
        deps.append("build/ot6.sfc")
    if "OT6_SRAM_CHECKPOINT=" in env:
        key = env.split("OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/")[1].split()[0]
        deps += [copy_if_changed_from(a) for a in sn.checkpoint_inputs(ROOT, key)]
        deps.append(copy_if_changed_from(sn.CHECKPOINT_TOOL))
    w.edge([f"build/results/suite/{t}.ok"], "suitetest", implicit=deps,
           test=t, env=env)
    qual.append(f"build/results/suite/{t}.ok")

# ------------------------------------------------------------------ checks --
def check(name, cmd, deps, desc=None):
    out = f"build/checks/{name}.ok"
    w.edge([out], "sh", implicit=deps,
           cmd=f"{cmd} && mkdir -p build/checks && touch {out}",
           desc=desc or name)
    qual.append(out)


test_luas = glob("tools/tests/*.lua") + glob("tools/tests/lib/*.lua")
check("compose_selftest", "python3 tools/tests/lib/compose.py --selftest",
      ["tools/tests/lib/compose.py", "tools/tests/lib/lua_fingerprint.py"]
      + LIBS)
# a stamp's verdict, every input moved one at a time, with a mutant each
check("stamps_selftest", "python3 tools/tests/lib/stamps.py --selftest",
      ["tools/tests/lib/stamps.py", "tools/tests/lib/compose.py",
       "tools/tests/lib/lua_fingerprint.py", "tools/build/rom_version.py"])
# The version fields and the ROM identity that masks them (one mutant per
# property: a flip outside the fields moves the identity, inside does not).
check("rom_version_selftest", "python3 tools/build/rom_version.py selftest",
      ["tools/build/rom_version.py", "ff6/include/ot6_version.inc",
       "ff6/tools/fix_checksum.py"]
      + glob("tools/char_table/*_en.json", "ff6"))
check("sram_selftest", "python3 tools/tests/lib/sram_checkpoint.py selftest",
      ["tools/tests/lib/sram_checkpoint.py"])
check("verdict_selftest", "sh tools/tests/run.sh --verdict-selftest",
      ["tools/tests/run.sh"])
check("boss_rows", "python3 tools/check_boss_rows.py",
      ["tools/check_boss_rows.py", "docs/design/bosses-wob.md",
       "ff6/src/battle/ot6_hud.asm", "ff6/src/battle/ot6_break.asm"])
# THE RATCHET (owner, 2026-09-01): zero no-key formations anywhere, as a
# hard build gate -- an encounter nobody can chip cannot ship, so a
# claimed-tuned area deterministically cannot hide one.  The audit's
# party-hands model may only tighten.
check("break_coverage_ratchet", "python3 tools/audit_break_coverage.py",
      ["tools/audit_break_coverage.py", "build/ot6.sfc",
       "ff6/src/battle/ot6_hud.asm", "ff6/src/battle/ot6_break_floor.inc",
       "ff6/src/field/sub_battle_group.dat",
       "ff6/src/field/rand_battle_group.dat",
       "ff6/src/field/world_battle_group.dat",
       "ff6/src/battle/battle_monsters.dat",
       "ff6/src/battle/monster_prop.dat"])
# One row per species (#157): Ot6SeedShields takes the FIRST match, so a
# second Ot6ShieldTbl/Ot6ElemAddTbl row for a species is dead code that
# reads as authored.  Source and the shipped ROM table must agree row for
# row.
check("shield_rows",
      "python3 tools/check_shield_rows.py --selftest"
      " && python3 tools/check_shield_rows.py",
      ["tools/check_shield_rows.py", "build/ot6.sfc",
       "ff6/src/battle/ot6_hud.asm", "ff6/src/battle/ot6_break.asm"])
check("break_reach", "python3 tools/check_break_reach.py",
      ["tools/check_break_reach.py"] + glob("src/battle/ot6_*.asm", "ff6"))
# The $1600-$1FFF save block is a compatibility contract
# (docs/design/save-layout.md): every OT6 symbol in it is documented at the
# address and width the build assembled it at, no two fields overlap, and none
# sits outside the free scrap.  Reads the assembled addresses from ff6-en.dbg,
# co-emitted with the ROM, so the copy_if_changed edge re-runs it when the ROM
# changes.
check("save_layout",
      "python3 tools/check_save_layout.py --selftest"
      " && python3 tools/check_save_layout.py",
      ["tools/check_save_layout.py", "docs/design/save-layout.md",
       "ff6/src/battle/ot6_memory.inc",
       copy_if_changed_from("build/ot6.sfc")])
# #305: the natural magic and the Esper spell lists are the planned ones
# (kits.md, magicite.md, magicite-tube-six.md), and none grants a higher
# spell tier (guidelines.md, "Stronger spells come from boosting, never from
# a list").  Reads the grant tables and Ot6FoldTbl out of the built ROM at
# the addresses ff6-en.dbg records; the selftest runs one mutant per rule.
check("spell_grants",
      "python3 tools/check_spell_grants.py --selftest"
      " && python3 tools/check_spell_grants.py",
      ["tools/check_spell_grants.py", "ff6/src/battle/ot6_boost.asm",
       "ff6/include/const.inc", "ff6/src/text/genju_name_en.json",
       "ff6/src/text/magic_name_en.json", "docs/design/kits.md",
       "docs/design/magicite.md", "docs/design/magicite-tube-six.md",
       copy_if_changed_from("build/ot6.sfc")])
# #292: the HUD's shield-count tiles are generated; the checked-in .inc must
# be what the generator writes (counts 1-6 byte-identical to the old art is
# asserted inside the generator).
check("shield_glyphs", "python3 ff6/tools/gen_shield_glyphs.py --check",
      ["ff6/tools/gen_shield_glyphs.py", "ff6/src/battle/ot6_shield_glyphs.inc"])
check("encounters_selftest", "python3 tools/audit_encounters.py --selftest",
      ["tools/audit_encounters.py"])
check("chestvis_selftest", "python3 tools/chest_visibility.py --selftest",
      ["tools/chest_visibility.py"])
check("state_writes",
      "python3 tools/check_state_writes.py --selftest"
      " && python3 tools/check_state_writes.py",
      ["tools/check_state_writes.py", "tools/state_write_waivers.txt"]
      + test_luas)
check("playthrough_honest",
      "python3 tools/check_playthrough_honest.py --selftest"
      " && python3 tools/check_playthrough_honest.py",
      ["tools/check_playthrough_honest.py"] + test_luas)
check("test_registration",
      "python3 tools/check_test_registration.py --selftest"
      " && python3 tools/check_test_registration.py",
      ["tools/check_test_registration.py"] + test_luas)
# the run-log audits' parsers (#154, #175): the report itself is a listing,
# not a gate, but the line shapes it reads are asserted here
check("audit_fenix_selftest",
      "python3 tools/audit_boost.py --selftest"
      " && python3 tools/audit_fenix.py --selftest"
      " && python3 tools/audit_zombie_touches.py --selftest",
      ["tools/audit_boost.py", "tools/audit_fenix.py", "tools/audit_zombie_touches.py",
       "tools/tests/savestate_graph.py"])
# The retention step (#222): evidence a merge message or a design doc
# quotes must outlive the worktree it was produced in, so the copy's
# filter, its idempotence and its refusal to clobber are checked here.
check("retain_evidence_selftest",
      "python3 tools/retain_evidence.py --selftest",
      ["tools/retain_evidence.py"])
check("ninja_py_selftest", "python3 tools/tests/lib/savestate_ninja.py --selftest",
      ["tools/tests/lib/savestate_ninja.py"])
# the graph's build semantics against real ninja on a mock tree: which runs
# each kind of change replays, and that the stamps agree
check("ninja_graph_selftest",
      "python3 tools/tests/lib/savestate_ninja_selftest.py",
      ["tools/tests/lib/savestate_ninja_selftest.py",
       "tools/tests/lib/savestate_ninja.py",
       "tools/tests/lib/stamps.py", "tools/tests/lib/compose.py",
       "tools/tests/lib/sram_checkpoint.py",
       "tools/tests/lib/lua_fingerprint.py", "tools/build/rom_version.py"])
check("runner_isolation", "sh tools/tests/lib/runner_isolation_selftest.sh",
      ["tools/tests/lib/runner_isolation_selftest.sh", "tools/tests/run.sh"])
check("shared_emulator", "sh tools/tests/lib/shared_emulator_selftest.sh",
      ["tools/tests/lib/shared_emulator_selftest.sh", "tools/tests/run.sh"])
checkpoint_files = glob("tools/tests/checkpoints/*/manifest.json") \
    + glob("tools/tests/checkpoints/*/*.sram")
# #218: every checkpoint validates, and every line says which save its
# battery holds.  A manifest that declares `saved` is refused when the
# payload holds a different one -- the check that was missing when two
# checkpoints shipped holding the Kolts summit save.
check("checkpoint_saves", "sh tools/tests/lib/checkpoint_saves.sh",
      ["tools/tests/lib/checkpoint_saves.sh",
       "tools/tests/lib/sram_checkpoint.py"] + checkpoint_files)
check("checkpoint_drift_selftest",
      "python3 tools/tests/lib/checkpoint_drift.py --selftest",
      ["tools/tests/lib/checkpoint_drift.py", "tools/tests/lib/sram_checkpoint.py",
       "tools/tests/lib/stamps.py", "tools/tests/lib/compose.py"])
# THE DRIFT GATE: every tracked checkpoint is the save the graph's run makes
# there today, byte for byte, play time and checksums aside (levels, gear,
# gil, the bag, story switches, the codex).  Every tracked checkpoint is on
# the graph (savestate_ninja.validate refuses one that is not), so this
# compares every one.  The fix for a drifted one is
# `checkpoint_drift.py --recut <key>` and a commit.
check("checkpoint_drift",
      "python3 tools/tests/lib/checkpoint_drift.py --strict "
      + " ".join(gate_keys),
      ["tools/tests/lib/checkpoint_drift.py",
       "tools/tests/lib/sram_checkpoint.py"]
      + [p for k in gate_keys for p in sn.capture_paths(ROOT, k)[:2]]
      + [a for k in gate_keys for a in sn.checkpoint_inputs(ROOT, k)],
      desc="tracked checkpoints are the graph's play")
check("checkpoint_negatives", "nice sh tools/tests/lib/checkpoint_negatives.sh",
      ["tools/tests/lib/checkpoint_negatives.sh"]
      + [copy_if_changed_from(p) for p in sn.RUN_INPUTS + (sn.CHECKPOINT_TOOL,)]
      + [copy_if_changed_from("tools/tests/lib/compose.py")]
      + [lua_copy_from(h) for h in LIBS] + checkpoint_files)
# the segment runner's negative control (#178, #200): a contract failure
# fails on attempt 1 of 3 with no replay -- a red run a suite cannot expect
check("retry_negative", "nice sh tools/tests/lib/retry_negative.sh",
      ["tools/tests/lib/retry_negative.sh",
       copy_if_changed_from("tools/tests/lib/compose.py"),
       copy_if_changed_from("tools/tests/probe_retry_negative.lua")]
      + [copy_if_changed_from(p) for p in sn.RUN_INPUTS]
      + [lua_copy_from(h) for h in LIBS])
# #309: every instrument left in tools/tests (`-- @manual`) composes and
# starts (docs/TESTING.md "Scripts that stay in the tree").
instruments = [f for f in glob("tools/tests/*.lua")
               if re.search(r"^-- @manual", (ROOT / f).read_text(errors="replace"), re.M)]
check("instruments", "nice python3 tools/check_instruments.py",
      ["tools/check_instruments.py", "tools/tests/lib/stamps.py", sn.GRAPH,
       copy_if_changed_from("tools/tests/lib/compose.py")]
      + [copy_if_changed_from(p) for p in sn.RUN_INPUTS]
      + [copy_if_changed_from(f) for f in instruments]
      + [lua_copy_from(h) for h in LIBS]
      + [d for f in instruments for d in fixture_deps(f)])

# the four fixture audits read the generated states and the checkpoints
AUDIT_COMMON = all_mss + checkpoint_files
check("audit_equipment", "python3 tools/audit_equipment.py",
      ["tools/audit_equipment.py"] + AUDIT_COMMON)
check("check_mog_gear", "python3 tools/check_mog_gear.py",
      ["tools/check_mog_gear.py", "build/states/moogle_cleared.mss"])
check("audit_party_hp",
      "python3 tools/audit_party_hp.py --selftest"
      " && python3 tools/audit_party_hp.py",
      ["tools/audit_party_hp.py"] + AUDIT_COMMON)
check("audit_supplies",
      "python3 tools/audit_supplies.py --selftest"
      " && python3 tools/audit_supplies.py",
      ["tools/audit_supplies.py"] + AUDIT_COMMON)
check("audit_chests",
      "python3 tools/audit_chests.py --selftest"
      " && python3 tools/audit_chests.py",
      ["tools/audit_chests.py", "tools/chests_opened.txt",
       "ff6/src/field/trigger/treasure_prop.dat"] + AUDIT_COMMON)

# ---------------------------------------------------------------- release --
rel_dir = f"build/release/ot6-v{VERSION}"
notes = f"docs/release-notes-v{VERSION}.md"

qual_before_release = len(qual)
check("release_branch",
      f"git show-ref --verify --quiet refs/heads/release/v{VERSION}"
      f" || {{ echo 'ERROR: no release/v{VERSION} branch -- cut it first:"
      f" git branch release/v{VERSION}'; exit 1; }}",
      ["VERSION"], desc=f"release/v{VERSION} branch exists")
check("release_readme",
      f"grep -q 'v{VERSION} is the current release' README.md"
      f" || {{ echo 'ERROR: README.md does not say v{VERSION} is the"
      f" current release'; exit 1; }}",
      ["VERSION", "README.md"], desc=f"README names v{VERSION}")

# The two release preflights are not qualification: bare `ninja` runs every
# qualifier on pushed main before the release commit (VERSION, notes,
# README) exists; the zip still requires both.
release_pre = qual[qual_before_release:]
del qual[qual_before_release:]

bps = f"{rel_dir}/{BASE[:-len('.sfc')]}.bps"
w.edge([bps], "sh", [BASE, "build/ot6.sfc"], implicit=qual + release_pre,
       cmd=f'mkdir -p "{rel_dir}" && tools/bin/flips --create --bps'
           f' "{BASE}" build/ot6.sfc "{bps}"',
       desc=f"bps patch v{VERSION}")
w.edge([f"{rel_dir}/RELEASE_NOTES.md"], "sh", [notes, "VERSION"],
       cmd=f'mkdir -p "{rel_dir}" && cp "{notes}" "{rel_dir}/RELEASE_NOTES.md"',
       desc="release notes")
w.edge([f"build/release/ot6-v{VERSION}.zip"], "sh",
       [bps, f"{rel_dir}/RELEASE_NOTES.md"],
       cmd=f'rm -f "build/release/ot6-v{VERSION}.zip" && cd build/release &&'
           f' zip -q -j "ot6-v{VERSION}.zip" "ot6-v{VERSION}/{BASE[:-4]}.bps"'
           f' "ot6-v{VERSION}/RELEASE_NOTES.md"',
       desc=f"release zip v{VERSION}")

# The OT6 Patcher APK (android/, docs/TOOLING.md "Android patcher"): carries
# the patch and writes the patched ROM on the player's device.  Only its own
# paths build it, so bare `ninja` never needs the JDK, the Android SDK or the
# signing key; the scripts say what is missing.
#
# The APK carries build/android/ot6.bps, made by the release patch's own
# flips command from the same inputs, so the APK, the host check and the
# signing checks run without qualification
# (`ninja build/release/ot6-vX.Y.apk build/checks/android_apk.ok`); the
# release itself also requires android_apk_release.ok, which compares that
# patch with the qualified release .bps byte for byte.
android_bps = "build/android/ot6.bps"
w.edge([android_bps], "sh", [BASE, "build/ot6.sfc"],
       cmd=f'mkdir -p build/android && tools/bin/flips --create --bps'
           f' "{BASE}" build/ot6.sfc {android_bps} >/dev/null',
       desc="bps patch for the android apk")
w.edge(["build/checks/android_bps.ok"], "sh", [BASE, android_bps, "build/ot6.sfc"],
       implicit=["tools/android/bps_check.sh", "tools/android/env.sh",
                 "android/src/io/github/mtklein/ot6patcher/Bps.java",
                 "android/src/io/github/mtklein/ot6patcher/RomScan.java",
                 "android/test/BpsTest.java"],
       cmd=f'tools/android/bps_check.sh "{BASE}" {android_bps} build/ot6.sfc'
           f' && mkdir -p build/checks && touch build/checks/android_bps.ok',
       desc="android BPS applier on the JVM")


apk_code = rom_version.apk_version_code(VERSION)
apk = f"build/release/ot6-v{VERSION}.apk"
apk_inputs = ["build/checks/android_bps.ok", "tools/android/build_apk.sh",
              "tools/android/env.sh", "android/AndroidManifest.xml"] \
    + glob("android/src/io/github/mtklein/ot6patcher/*.java") \
    + glob("android/res/*/*.xml")
w.edge([apk], "sh", [android_bps], implicit=apk_inputs,
       cmd=f'tools/android/build_apk.sh {android_bps} {VERSION} {apk_code} {apk}',
       desc=f"android apk v{VERSION}")
w.edge(["build/checks/android_apk.ok"], "sh", [apk, android_bps],
       implicit=["tools/android/verify_apk.sh", "tools/android/env.sh",
                 "android/release-cert.sha256"],
       cmd=f'tools/android/verify_apk.sh {apk} {VERSION} {apk_code} {android_bps}'
           f' && touch build/checks/android_apk.ok',
       desc=f"verify android apk v{VERSION}")
w.edge(["build/checks/android_apk_release.ok"], "sh", [android_bps, bps],
       cmd=f'cmp {android_bps} "{bps}"'
           f' && touch build/checks/android_apk_release.ok',
       desc=f"android apk carries the release patch v{VERSION}")

# ----------------------------------------------- copy_if_changed + regen ---
w()
for dep, src in sorted(copy_if_changed_edges.items()):
    w.edge([dep], "copy_if_rom_identity_changed" if src == sn.ROM
           else "copy_if_changed", [src])
for dep, src in sorted(lua_copy_edges.items()):
    w.edge([dep], "copy_if_lua_changed", [src])
w()
w("rule configure")
w("  command = python3 configure.py")
w("  depfile = build/ninja/configure.d")
w("  deps = gcc")
w("  generator = 1")
w("  restat = 1")
w.edge(["build.ninja"], "configure",
       ["configure.py", sn.GRAPH, "tools/tests/lib/savestate_ninja.py",
        "VERSION", "tools/build/rom_version.py", "ff6/include/ot6_version.inc"])
w()
# The default: every qualifier, and every generated state's and capture's
# record (lib/stamps.py), which nothing else depends on.
qual += [f"build/states/{n}.stamp" for n in sorted(state_names)]
qual += [sn.capture_paths(ROOT, k)[2] for k in gate_keys]
w("default " + " ".join(esc(p) for p in qual))
w()

# ------------------------------------------------------------------ write --
text = "\n".join(w.lines)
out = ROOT / "build.ninja"
(ROOT / "build/ninja").mkdir(parents=True, exist_ok=True)
dep_targets = " ".join(sorted(esc(d) for d in read_deps))
(ROOT / "build/ninja/configure.d").write_text(f"build.ninja: {dep_targets}\n")
if not (out.exists() and out.read_text() == text):
    out.write_text(text)
    n_tests = len(suite_tests)
    print(f"wrote build.ninja ({len(states)} states, {n_tests} suite tests, "
          f"{len(qual)} release qualifiers)")
