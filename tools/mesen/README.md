# Mesen 2.1.1, script-only build

Two patches for the official Mesen 2.1.1 source (github.com/SourMesen/Mesen2,
tag `2.1.1`, commit `137ae7ce`), and `build.sh`, which clones that tag,
applies them and builds with the flags of upstream's own release workflow for
the official Linux binary or Mac app, plus `-fno-semantic-interposition` and
frame pointers.
Mesen's source isn't vendored here. Evidence: `build/attempts/wt/mesen-lean/`
(Linux) and `build/attempts/wt/mesen-mac/` (macOS).

## Why

The harness's Lua needs Mesen's debugger: Mesen only runs scripts through it.
In stock Mesen the debugger also does per-access bookkeeping for its own
windows on every CPU and audio-processor (SPC) memory access, whether or not
a window is open: access counters, the code/data log, call-stack tracking,
the event log, and step and break checks. Our runs use none of it; on px13 it
is 28% of an emulator's samples.

With both patches and `build.sh`'s flags, px13 (one fast core, quiet) ran
battle_rage at 407 fps against stock's 290, and the full gen_zozo2_arrival
leg in 475 s against 693 s, with identical results.

## mesen-script-only.patch

**Script-only mode.** It is on when the environment has `MESEN_SCRIPT_ONLY=1`
and no debugger window is open; opening one turns it off.
- For the SNES CPU (and SA-1) and the SPC, while that CPU has no step request,
  pending break, breakpoint or trace log, the Debugger doesn't call into the
  CPU's debugger on a memory access at all. It only records the access and
  runs the Lua callbacks, when that CPU has any.
- Each instruction still goes through the CPU's debugger when a break request
  is pending (how savestates and other threads stop the emulator) or the CPU
  has Lua callbacks; there it records the instruction and nothing else.
- Per-PPU-cycle debugger work is skipped unless a PPU step is pending.

**Two changes that are always on.** Neither changes which callbacks run:
- A per-callback-type bitmap of 256-byte pages lets most accesses skip the
  Lua callback loop, including its address translation. Callbacks on
  absolute memory types bypass the bitmap.
- The "has CPU memory callbacks" flag is per CPU, so SPC accesses skip
  callback dispatch when only SNES callbacks exist.

**What script-only mode gives up.**
- The code/data log and the access counters, so in Lua `emu.getCdlData`
  and `emu.getAccessCounters` return (nearly) empty data. The harness reads
  only the code/data log, for coverage (`coverageFlush`, OT6_COVERAGE):
  run.sh leaves script-only off for a coverage run, and `coverageFlush`
  refuses a log with fewer than 256 marked bytes.
- The `[CPU] Uninitialized memory read` stdout lines; they come from the
  access counters.
- The data behind the debugger's views: call stack, code/data log, access
  counts and the event viewer.
- Mid-frame refresh of the PPU viewers.
- Up-to-date disassembly of code in RAM if a debugger window is opened
  partway through a session.

Without `MESEN_SCRIPT_ONLY=1` the patched binary behaves like stock, apart
from the two always-on changes. run.sh exports `MESEN_SCRIPT_ONLY=1` for
every run but a coverage run; the official binary never reads it (its
MesenCore has no such string).

## mesen-screenshot-sync.patch

The emulation thread hands each finished frame to a decode thread, which
converts it into the buffer `emu.takeScreenshot()` copies. A script's
`startFrame` callback runs right after the hand-off, so a screenshot taken
there sometimes copied the previous frame. The patch makes the screenshot
wait for the pending decode, so it is always the frame the emulation thread
just finished. It applies on its own to a stock build too.

## Building (Linux x64)

```
sudo apt install git make clang lld zip libsdl2-dev zlib1g-dev dotnet-sdk-10.0 dotnet-sdk-aot-10.0
tools/mesen/build.sh ~/work/mesen-build            # both patches, -fno-semantic-interposition, frame pointers
tools/mesen/build.sh ~/work/mesen-build --stock    # stock, as upstream builds it
tools/mesen/build.sh ~/work/x --patches mesen-screenshot-sync.patch --cflags ""   # a subset
```

The output is one self-contained binary,
`<workdir>/Mesen2/bin/linux-x64/Release/linux-x64/publish/Mesen`, shaped
like the official zip's, and `Mesen.buildinfo` beside it: the upstream
commit, each patch's sha256, the flags, the binary's and MesenCore's
sha256 and the toolchain, including the NativeAOT compiler the build
restored. The binary carries the patch record too, as BuildInfo.txt beside
the bare-commit `BuildSha.txt` that Mesen's About box links to. The build
ends with a smoke test: battle_banner through run.sh on a reference binary
and on the new one, failing unless their `[ot6]` lines match. The
reference is the tree's `tools/Mesen-linux/Mesen` while that is the
official 2.1.1 binary (checked by sha256); once a worker has been deployed,
pass `--reference ~/mesen-official/Mesen`. `--no-smoke` skips it.
- Each build is clean: the makefile tracks no header dependencies.
- `-fno-semantic-interposition`: MesenCore.so is built `-fPIC` with default
  visibility, so otherwise every call between its source files goes through
  the PLT and can't be inlined. It changed no results and saved 14-19% of
  cycles per frame. `-fvisibility=hidden` saved less and wasn't kept.
- `-fno-omit-frame-pointer -mno-omit-leaf-frame-pointer` are part of every
  patched build on both platforms (owner, 2026-10-01), so a profile can be
  taken any time; they cost about 1-3%.
- On Ubuntu 26.04 the compiler is clang 21; the official build used clang 14
  on Ubuntu 22.04. The .NET 10 SDK builds the net8.0 UI with NativeAOT
  8.0.31; the official build used 8.0.15. Built this way, stock 2.1.1 played
  the same as the official binary.

To try a build with the harness without installing it:

```
OT6_MESEN_APP=<dir holding Mesen> OT6_MESEN_CACHE=<a cache of its own> tools/tests/run.sh <script>
```

run.sh refuses the machine-wide cache for it and names that app's shared
copy after its sha256.

Every run log ends with `[emulator] <sha256> MESEN_SCRIPT_ONLY
requested=<v> core=<sha256>`: the executable, and the MesenCore that run
loaded (macOS: "Which core a Mac bundle runs", below). run.sh also
publishes that line beside each `.mss` it publishes
(`<state>.mss.emulator`), and `savestate_stamp.sh` copies its first sha
into the stamp's `emulator <sha256>` line, so the two agree. Both are
records of which binary ran, never compatibility bindings, so swapping the
emulator regenerates nothing.

## Deploying on a Linux worker (px13), after this branch is merged

run.sh runs `tools/Mesen-linux/Mesen` of the main tree (`~/ot6`; worktrees
link to it) through one machine-wide shared copy, which it refreshes when
the binary's size or mtime changes. So deploying is replacing that file
while no ninja or run.sh is alive on the machine (other agents' included):

```
cd ~/ot6
tools/mesen/build.sh ~/work/mesen-build        # builds and smoke-tests against the official binary
                                               # (later rebuilds: add --reference ~/mesen-official/Mesen)
mkdir -p ~/mesen-official && cp -p tools/Mesen-linux/Mesen ~/mesen-official/Mesen   # keep the official one
install -m 755 ~/work/mesen-build/Mesen2/bin/linux-x64/Release/linux-x64/publish/Mesen tools/Mesen-linux/Mesen
sha256sum tools/Mesen-linux/Mesen               # = sha256 in Mesen.buildinfo
```

The next run.sh then rebuilds the shared copy and logs the new
`[emulator]` sha. To roll back, install `~/mesen-official/Mesen` the same
way. Nothing regenerates either way.

## Building (macOS arm64)

```
xcode-select --install                      # clang, codesign (the command line tools are enough)
brew bundle                                 # sdl2 and dotnet@8 (keg-only; build.sh finds it)
caffeinate -is tools/mesen/build.sh ~/work/mesen-build
```

`build.sh` follows upstream's macOS job (`USE_AOT=true make`; the makefile
turns LTO and static linking off on Darwin), then signs the bundle ad hoc
(`codesign --force --deep -s -`; upstream signs with its own certificate
and the hardened runtime, which an ad hoc signature doesn't need). The
output is `<workdir>/Mesen2/bin/osx-arm64/Release/osx-arm64/publish/Mesen.app`
with `Mesen.app.buildinfo` beside it, and the smoke test's reference is the
tree's `tools/Mesen.app` while its executable is the official one (sha256
`bddfea2f...1b09`), else `--reference ~/mesen-official/Mesen.app`. On the
Air (M4, 10 cores) a build takes about four minutes.
- `-fno-semantic-interposition` does nothing on Mach-O: clang's driver
  drops it ("argument unused during compilation"), and objects compiled with
  and without it are byte-identical. It stays so both platforms record the
  same flags.
- arm64 macOS keeps frame pointers in non-leaf functions by ABI; the
  frame-pointer flags are accepted without a warning and add the leaf
  functions (clang's `-mframe-pointer=all` in place of `non-leaf`).
- macOS's make is GNU make 3.81, so there's no `-O`, and only the core is
  built in parallel: under `make -j` the C# compiler server that `dotnet
  publish` starts inherits make's jobserver pipe, and make never exits.
  `build.sh` also turns the compiler server and MSBuild node reuse off, so
  the build leaves no process behind.
- The core is built for the host's macOS (`minos` 27.0 on the Macs today);
  the official one targets 14.0. A build runs on a Mac with the same or a
  newer macOS.
- A build is not bit-reproducible: `InteropDLL/EmuApiWrapper.cpp` embeds
  `__DATE__` and `__TIME__`, so two builds of the same source differ in
  MesenCore and so in the executable.

**Which core a Mac bundle runs.** The executable packs MesenCore.dylib
inside it (Dependencies.zip, embedded at build time), and Mesen loads the
copy in its home folder, unpacking it there when that copy is missing or
its size or mtime differs. The patched bundle has no loose core. The
official bundle's loose `Contents/MacOS/MesenCore.dylib` is only what Mesen
unpacked there while the bundle was portable (a settings.json beside the
executable puts the home folder there), the same bytes as its packed one.
run.sh doesn't pre-seed a worker's home with a core, so every run loads the
packed one, which the executable's sha256 covers, and the `[emulator]` line
also carries the core that run loaded (`core=<sha256>`, hashed in the home
afterwards): `bbe30ced...09e3` for the official bundle, and the
`packed_mesencore_sha256` of `Mesen.app.buildinfo` for a build.

## Deploying on a Mac

run.sh runs the main tree's `tools/Mesen.app` (worktrees link to it) through
a machine-wide shared copy, refreshed when the executable's size or mtime
changes; a new bundle path costs a Gatekeeper scan of a few seconds on its
first run. A bundle used by hand in portable mode keeps that profile inside
it (settings.json, Saves, SaveStates, RecentGames ...), so the new bundle
takes those along, but not the dependencies Mesen unpacked there. While no
ninja or run.sh is alive on the machine (other agents' included):

```
cd ~/ot6
B=~/work/mesen-build/Mesen2/bin/osx-arm64/Release/osx-arm64/publish/Mesen.app   # or a copy from another Mac
mkdir -p ~/mesen-official && ditto tools/Mesen.app ~/mesen-official/Mesen.app    # keep the official one, profile and all
mkdir -p ~/mesen-patched && ditto "$B" ~/mesen-patched/Mesen.app && cp -p "$B.buildinfo" ~/mesen-patched/
ditto "$B" tools/Mesen.app.new
for f in tools/Mesen.app/Contents/MacOS/*; do
  n=$(basename "$f")
  [ -e "tools/Mesen.app.new/Contents/MacOS/$n" ] && continue
  case "$n" in MesenCore.dylib|MesenNesDB.txt) continue ;; esac   # unpacked by Mesen, not profile
  ditto "$f" "tools/Mesen.app.new/Contents/MacOS/$n"
done
mv tools/Mesen.app tools/Mesen.app.old && mv tools/Mesen.app.new tools/Mesen.app && rm -rf tools/Mesen.app.old
shasum -a 256 tools/Mesen.app/Contents/MacOS/Mesen   # = sha256 in ~/mesen-patched/Mesen.app.buildinfo
```

The next run.sh rebuilds the shared copy and logs the new `[emulator]` sha.
Later rebuilds smoke-test with `--reference ~/mesen-official/Mesen.app`. To
roll back, put `~/mesen-official/Mesen.app` back the same way (its own
profile is the one from deployment day; carry anything newer across with
the same loop). Nothing regenerates either way.
