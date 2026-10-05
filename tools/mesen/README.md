# OT6's Mesen

OT6's harness runs its own build of Mesen: MesenCE 2.2.1
(github.com/nesdev-org/MesenCE, tag `2.2.1`, commit `20ba206c`) with four
small changes, kept as commits (tag `ot6-2.2.1-4`) on OT6's fork,
github.com/mtklein/mesen (GPL v3, in Mesen's fork network; its
`OT6-CHANGES.md` is the change notice):

- **Script-only debugger mode** (below), for speed.
- **Screenshot sync** (below), for correct screenshots.
- **Render on demand, and a debugger that pays only for the script's
  callbacks** (below), for speed (#394).
- **SDK roll-forward**: `UI/global.json` lets the .NET SDK roll forward to a
  newer major version, so the .NET 10 SDK on px13 builds it as dotnet@8
  does on the Macs. It changes no code.

`EMULATOR` pins the build: one line, `<repository> <tag> <commit>`
(today `https://github.com/mtklein/mesen ot6-2.2.1-4 25f8ce92...`).
`build.sh` builds that commit and nothing else. The same file is an input of
every generate, chain and suite edge (configure.py), like the ROM: a new pin
regenerates every fixture and re-runs every test, and through the chain's
captures `checkpoint_drift.py` then asks for every cut checkpoint to be
re-cut before a release. So moving to a new emulator build is: push the
commit to the fork, tag it `ot6-<base>-<n>`, change `EMULATOR`, build and
deploy it on every machine (Deploying, below: per pin, so trees on the old
pin keep running), then regenerate (`ninja chain`, `ninja`).
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

## Render on demand

Drawing the picture was about 27% of a headless frame, and the harness looks
at few frames (tools/mesen/experiments/render-cost/summary.txt). A script
that calls `emu.setRenderOnDemand(true)` gets only the frames it asks for
with `emu.requestRender()` drawn: the request is read after the StartFrame
event, so a `startFrame` callback can ask for the frame starting then, and
the next callback reads it. It goes through Mesen's own frame-skip path
(`_skipRender`). Drawing leaves one piece of machine state behind: the
palette lookups set the PPU's `InternalCgramAddress`, which savestates
carry and a CGRAM access during rendering uses (review of #394). So a
frame not drawn still evaluates -- tile fetch, layers and backdrop, no
output -- the lines whose lookups can be its last: the last visible line,
every line when HDMA writes INIDISP, the line where forced blank turned on
the frame before, and the current line when forced blank turns on. A flag
tracks when the address may still differ from drawing every frame, and a
savestate or a CGRAM access during rendering while it is set is counted
(`emu.getRenderOnDemandInexact()`; `lib/ot6.lua` fails such a run). On
replays of three harness runs the old build and this one end with the same
WRAM, ARAM, VRAM, OAM, CGRAM, SRAM and `emu.getState()`, and the address
at every frame's start is the same (build/attempts/wt/v026-lib/394/ab/
replay/, replaycg/; the first cut, which didn't evaluate, differed there on
48 forced-blank frames of gen_whelk_poweron). A frame not drawn isn't handed
to the video decoder, so `emu.takeScreenshot()` and `emu.getScreenBuffer()`
keep the last frame drawn, and so does a savestate's picture;
`emu.isFrameRendered()` says whether the frame just finished was drawn.
Unloading the script turns it off.

`lib/ot6.lua` turns it on in `H.run` and asks for a frame ahead of each
read it makes (the watchdog's screen hash every 16 frames, the live shot
every 128); `H.screenshot` of a frame that wasn't drawn is taken on the
next one, and battleActive reads the battle's brightness byte instead of
a screenshot.
A raw pixel read of a frame that wasn't drawn raises; a script reading
pixels itself calls `H.renderAlways()` or `H.requestRender()` a frame
ahead.

## Script callbacks, paid per use

In script-only mode the hot paths (each memory access, instruction, idle
cycle and PPU cycle) test inline, in `Emulator.h` and `Debugger.h`, whether
the CPU is quiet (script-only, no step, break, breakpoint, trace log or
step back) and whether any script has a callback that this access could
run: callbacks are counted per type (read, write, exec) and per CPU, and
the union of every script's 256-byte page filter is kept in the Debugger.
Only then do they call into the debugger. The test is the one the
out-of-line code already made before skipping the per-CPU debugger, so
nothing that runs changes; a run pays for the callbacks it registered and
nothing per cycle otherwise. On gen_whelk_poweron (macOS `sample`, 1 ms)
the debugger and script bookkeeping went from 16.0% of samples to 1.7%
(build/attempts/wt/v026-lib/394/prof/whelk_new1 and whelk_new4).
`RewindManager::IsRewinding` is inline too, and the harness turns rewind
off (`lib/pin_test_saves.py`; `OT6_REWIND=1` keeps it, to measure it).

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

## Deploying

Each machine keeps every pinned build in its own directory,
`~/mesen-pins/<commit>/` (`Mesen.app` and `Mesen.app.buildinfo` on a Mac,
`Mesen` and `Mesen.buildinfo` on Linux), and run.sh runs the one the tree's
`EMULATOR` names, through a machine-wide shared copy of its own
(`Mesen-test-<commit12>` in `~/Library/Caches/ot6` or `~/.cache/ot6`). So
trees on different pins run side by side on one machine, and deploying a
new pin is adding its directory: no tree on another pin notices, and
nothing has to wait for other agents' runs to finish. A machine without the
pin's directory falls back to the main tree's `tools/Mesen.app`
(`tools/Mesen-linux/Mesen`), the way it ran before #394, and run.sh still
refuses any build whose packed record (`python3 tools/mesen/buildinfo.py
<binary>`) is not `EMULATOR`'s line, so a machine missing the pin stops
rather than regenerating under it with the wrong emulator.

On every machine (px13, the Air, this Mac), after building
(`tools/mesen/build.sh`, which ends with the smoke test):

```
P=~/mesen-pins/$(cut -d' ' -f3 tools/mesen/EMULATOR); mkdir -p $P
# macOS
B=~/work/mesen-build/Mesen2/bin/osx-arm64/Release/osx-arm64/publish   # or a copy from another Mac
ditto $B/Mesen.app $P/Mesen.app && cp -p $B/Mesen.app.buildinfo $P/
shasum -a 256 $P/Mesen.app/Contents/MacOS/Mesen    # = sha256 in the buildinfo
# Linux
B=~/work/mesen-build/Mesen2/bin/linux-x64/Release/linux-x64/publish
install -m 755 $B/Mesen $P/Mesen && cp -p $B/Mesen.buildinfo $P/
sha256sum $P/Mesen                                  # = sha256 in the buildinfo
```

The next run.sh in a tree on that pin builds the shared copy (a Gatekeeper
scan of a few seconds on a Mac, once) and logs the new `[emulator]` sha and
`commit=`. Old pins' directories can stay; one no tree uses any more can be
deleted. A deployment whose `EMULATOR` change has landed is followed by
regeneration (`ninja chain`, the checkpoint re-cut, `ninja`); rolling back
is reverting `EMULATOR`, which finds the old pin's directory (or the
fallback) again. `tools/Mesen.app` stays the bundle for playing by hand
(`tools/gui.sh`); the 2.2.1 builds deployed there before per-pin
directories are kept in `~/mesen-patched/` as `2.2.1-<sha8>-Mesen[.app]`.

ot6-2.2.1-4 (25f8ce92) is deployed on all three (2026-10-05), each machine
its own build of it: mbp executable `91fc1bed...f26f` (core `b43f2d35...183d`), the Air `015ead3e...75eb`
(core `825b8c6a...7712`), px13 `ff5f9e06...cf39` (core `b8026921...ee8f`); every build passed the smoke test
("smoke test: OK -- battle_banner's 30 [ot6] lines match the reference
build's", build/attempts/wt/v026-lib/394/builds/*-2.2.1-4*).

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
