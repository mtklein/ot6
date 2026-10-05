# OT6's Mesen

OT6's harness runs its own build of Mesen: MesenCE 2.2.1
(github.com/nesdev-org/MesenCE, tag `2.2.1`, commit `20ba206c`) with three
small changes, kept as commits (tag `ot6-2.2.1-1`) on OT6's fork,
github.com/mtklein/mesen (GPL v3, in Mesen's fork network; its
`OT6-CHANGES.md` is the change notice):

- **Script-only debugger mode** (below), for speed.
- **Screenshot sync** (below), for correct screenshots.
- **SDK roll-forward**: `UI/global.json` lets the .NET SDK roll forward to a
  newer major version, so the .NET 10 SDK on px13 builds it as dotnet@8
  does on the Macs. It changes no code.

`EMULATOR` pins the build: one line, `<repository> <tag> <commit>`
(today `https://github.com/mtklein/mesen ot6-2.2.1-1 40586fe8...`).
`build.sh` builds that commit and nothing else. The same file is an input of
every generate, chain and suite edge (configure.py), like the ROM: a new pin
regenerates every fixture and re-runs every test, and through the chain's
captures `checkpoint_drift.py` then asks for every cut checkpoint to be
re-cut before a release. So moving to a new emulator build is: push the
commit to the fork, tag it `ot6-<base>-<n>`, change `EMULATOR`, build and
deploy it on every machine, then regenerate (`ninja chain`, `ninja`).
The file holds no comments, so only a real change regenerates anything.

Until 2026-10-01 the harness ran the same two code changes on SourMesen's
Mesen 2.1.1 (`137ae7ce`), as patch files here; they are tag `ot6-2.1.1-1`
of the fork now, byte-identical to 2.1.1 with those patches
(build/attempts/wt/mesen-fork/treediff-2.1.1.txt).

## Why MesenCE 2.2.1

MesenCE (Mesen Community Edition, in the same fork network) carries
emulation fixes made since 2.1.1. Stock 2.2.1 plays OT6 slightly
differently from 2.1.1 (a few frames earlier or later here and there), and
the difference is one fix: with MesenCE commit 1da6c1ad ("SNES: Fix clock
counting logic for DMAs longer than 255 bytes") reverted, 2.2.1 played six
legs as the official 2.1.1 binary did: battle_rage and wipe_reclass the
same throughout, and the four legs that publish a savestate the same up to
it, the first difference being the emulator version in its header
(build/attempts/mesence-eval/px13/out/fullcmp3_all.txt).
OT6's two changes rebased onto 2.2.1 only by context lines (MesenCE
reformatted its sources); the added code is the same
(build/attempts/wt/mesen-fork/treediff-2.2.1.txt).

## Script-only mode

The harness's Lua needs Mesen's debugger: Mesen only runs scripts through it.
In stock Mesen the debugger also does per-access bookkeeping for its own
windows on every CPU and audio-processor (SPC) memory access, whether or not
a window is open: access counters, the code/data log, call-stack tracking,
the event log, and step and break checks. Our runs use none of it; on px13
it was 28% of an emulator's samples (2.1.1).

Script-only mode is on when the environment has `MESEN_SCRIPT_ONLY=1`
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

Without `MESEN_SCRIPT_ONLY=1` OT6's build behaves like stock, apart from
the two always-on changes. run.sh exports `MESEN_SCRIPT_ONLY=1` for every
run but a coverage run; a stock build never reads it.

## Screenshot sync

The emulation thread hands each finished frame to a decode thread, which
converts it into the buffer `emu.takeScreenshot()` copies. A script's
`startFrame` callback runs right after the hand-off, so a screenshot taken
there sometimes copied the previous frame. The change makes the screenshot
wait for the pending decode, so it is always the frame the emulation thread
just finished.

## Building (Linux x64)

```
sudo apt install git make clang lld zip libsdl2-dev zlib1g-dev dotnet-sdk-10.0 dotnet-sdk-aot-10.0
tools/mesen/build.sh ~/work/mesen-build            # EMULATOR's commit, -fno-semantic-interposition, frame pointers
tools/mesen/build.sh ~/work/mesen-stock --stock    # stock MesenCE 2.2.1, as upstream builds it
```

The output is one self-contained binary,
`<workdir>/Mesen2/bin/linux-x64/Release/linux-x64/publish/Mesen`, shaped
like upstream's release, and `Mesen.buildinfo` beside it: the repository,
tag and commit built (its first line, `mesen <repository> <tag> <commit>`),
the flags, the binary's and MesenCore's sha256 and the toolchain, including
the NativeAOT compiler the build restored. The binary carries the same
record as BuildInfo.txt beside the bare-commit `BuildSha.txt` that Mesen's
About box links to. The build ends with a smoke test: battle_banner through
run.sh on the reference build and on the new one, failing unless their
`[ot6]` lines match. `--no-smoke` skips it.
- Each build is clean: the makefile tracks no header dependencies.
- `-fno-semantic-interposition`: MesenCore.so is built `-fPIC` with default
  visibility, so otherwise every call between its source files goes through
  the PLT and can't be inlined. It changed no results and saved 14-19% of
  cycles per frame (2.1.1). `-fvisibility=hidden` saved less and wasn't kept.
- `-fno-omit-frame-pointer -mno-omit-leaf-frame-pointer` are part of every
  OT6 build on both platforms (owner, 2026-10-01), so a profile can be
  taken any time; they cost about 1-3%.
- On Ubuntu 26.04 the compiler is clang 21 and the .NET 10 SDK builds the
  net8.0 UI with NativeAOT 8.0.x; upstream's release workflow uses Ubuntu
  22.04 and the .NET 8 SDK.

## The reference build

The smoke test compares against a stock MesenCE 2.2.1 build, which plays
like OT6's build does; the official 2.1.1 release plays differently (Why
MesenCE 2.2.1, above). Each machine keeps one in `~/mesen-reference/`,
built by `--stock` with its `.buildinfo` beside it; build.sh accepts it
only when that record names stock 2.2.1 and the executable's sha256. A
`--stock` build skips the smoke test while there is no reference yet.
`--reference <a stock build>` points elsewhere.

```
tools/mesen/build.sh ~/work/mesen-stock --stock
P=~/work/mesen-stock/Mesen2/bin/linux-x64/Release/linux-x64/publish
mkdir -p ~/mesen-reference && install -m 755 $P/Mesen ~/mesen-reference/Mesen && cp -p $P/Mesen.buildinfo ~/mesen-reference/
# macOS: P=~/work/mesen-stock/Mesen2/bin/osx-arm64/Release/osx-arm64/publish
#        ditto $P/Mesen.app ~/mesen-reference/Mesen.app && cp -p $P/Mesen.app.buildinfo ~/mesen-reference/
```

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
records of which binary ran; what makes fixtures regenerate is `EMULATOR`.

## Deploying on a Linux worker (px13)

run.sh runs `tools/Mesen-linux/Mesen` of the main tree (`~/ot6`; worktrees
link to it) through one machine-wide shared copy, which it refreshes when
the binary's size or mtime changes. So deploying is replacing that file
while no ninja or run.sh is alive on the machine (other agents' included).
`~/mesen-patched/` keeps every build deployed, as
`<base>-<sha8>-Mesen` with its `.buildinfo` (`2.1.1-48baed80-Mesen`,
`2.2.1-b5a407c3-Mesen`, ...), so the one replaced is the rollback:

```
cd ~/ot6
tools/mesen/build.sh ~/work/mesen-build        # builds and smoke-tests against ~/mesen-reference
B=~/work/mesen-build/Mesen2/bin/linux-x64/Release/linux-x64/publish/Mesen
n=$(sha256sum $B | cut -c1-8)
mkdir -p ~/mesen-patched && cp -p $B ~/mesen-patched/2.2.1-$n-Mesen && cp -p $B.buildinfo ~/mesen-patched/2.2.1-$n-Mesen.buildinfo
install -m 755 $B tools/Mesen-linux/Mesen
sha256sum tools/Mesen-linux/Mesen               # = sha256 in the buildinfo
```

The next run.sh then rebuilds the shared copy and logs the new
`[emulator]` sha and `commit=`. run.sh refuses to run while the deployed
build's packed record (`python3 tools/mesen/buildinfo.py <binary>`) is not
`EMULATOR`'s line, so a machine left on the old build after a pin change
stops rather than regenerating under the new pin. To roll back, install the kept binary the same way. A
deployment whose `EMULATOR` change has landed is followed by regeneration
(`ninja chain`, the checkpoint re-cut, `ninja`); a rollback that keeps
`EMULATOR` regenerates nothing, so roll back `EMULATOR` with it.

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
with `Mesen.app.buildinfo` beside it, and the smoke test's reference is
`~/mesen-reference/Mesen.app`.
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
- The core is built for the host's macOS (`minos` 27.0 on the Macs today).
  A build runs on a Mac with the same or a newer macOS.
- A build is not bit-reproducible: `InteropDLL/EmuApiWrapper.cpp` embeds
  `__DATE__` and `__TIME__`, so two builds of the same source differ in
  MesenCore and so in the executable.

**Which core a Mac bundle runs.** The executable packs MesenCore.dylib
inside it (Dependencies.zip, embedded at build time), and Mesen loads the
copy in its home folder, unpacking it there when that copy is missing or
its size or mtime differs. A built bundle has no loose core. run.sh doesn't
pre-seed a worker's home with a core, so every run loads the packed one,
which the executable's sha256 covers, and the `[emulator]` line also
carries the core that run loaded (`core=<sha256>`, hashed in the home
afterwards): the `packed_mesencore_sha256` of `Mesen.app.buildinfo`.

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
old=$(shasum -a 256 tools/Mesen.app/Contents/MacOS/Mesen | cut -c1-8)
n=$(shasum -a 256 "$B/Contents/MacOS/Mesen" | cut -c1-8)
mkdir -p ~/mesen-patched && ditto tools/Mesen.app ~/mesen-patched/2.2.1-$old-Mesen.app   # the rollback, profile and all
ditto "$B" ~/mesen-patched/2.2.1-$n-Mesen.app && cp -p "$B.buildinfo" ~/mesen-patched/2.2.1-$n-Mesen.app.buildinfo
ditto "$B" tools/Mesen.app.new
for f in tools/Mesen.app/Contents/MacOS/*; do
  n=$(basename "$f")
  [ -e "tools/Mesen.app.new/Contents/MacOS/$n" ] && continue
  case "$n" in MesenCore.dylib|MesenNesDB.txt) continue ;; esac   # unpacked by Mesen, not profile
  ditto "$f" "tools/Mesen.app.new/Contents/MacOS/$n"
done
mv tools/Mesen.app tools/Mesen.app.old && mv tools/Mesen.app.new tools/Mesen.app && rm -rf tools/Mesen.app.old
shasum -a 256 tools/Mesen.app/Contents/MacOS/Mesen   # = sha256 in the buildinfo
```

(`2.2.1-` names the base of the bundle being kept; the 2.1.1 bundles are
`~/mesen-patched/2.1.1-dbb67f06-Mesen.app`.) The next run.sh rebuilds the
shared copy and logs the new `[emulator]` sha. To roll back, put the kept
bundle back the same way (carry anything newer in its profile across with
the same loop), with `EMULATOR` rolled back too.
