# Mesen 2.1.1, script-only build

Two patches for the official Mesen 2.1.1 source (github.com/SourMesen/Mesen2,
tag `2.1.1`, commit `137ae7ce`), and `build.sh`, which clones that tag,
applies them and builds with the flags of upstream's own release workflow for
the official Linux binary, plus `-fno-semantic-interposition`. Mesen's source
isn't vendored here. Evidence: `build/attempts/wt/mesen-lean/`.

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
- The `[CPU] Uninitialized memory read` stdout lines; they come from the
  access counters.
- The data behind the debugger's views: call stack, code/data log, access
  counts and the event viewer.
- Mid-frame refresh of the PPU viewers.
- Up-to-date disassembly of code in RAM if a debugger window is opened
  partway through a session.

Without `MESEN_SCRIPT_ONLY` the patched binary behaves like stock, apart from
the two always-on changes.

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
tools/mesen/build.sh ~/work/mesen-build            # both patches, -fno-semantic-interposition
tools/mesen/build.sh ~/work/mesen-build --stock    # stock, as upstream builds it
PATCHES=mesen-screenshot-sync.patch EXTRA_CFLAGS= tools/mesen/build.sh ~/work/x   # a subset
```

The output is one self-contained binary,
`<workdir>/Mesen2/bin/linux-x64/Release/linux-x64/publish/Mesen`, shaped
like the official zip's.
- Each build is clean: the makefile tracks no header dependencies.
- `-fno-semantic-interposition`: MesenCore.so is built `-fPIC` with default
  visibility, so otherwise every call between its source files goes through
  the PLT and can't be inlined. It changed no results and saved 14-19% of
  cycles per frame. `-fvisibility=hidden` saved less and wasn't kept.
- On Ubuntu 26.04 the compiler is clang 21; the official build used clang 14
  on Ubuntu 22.04. The .NET 10 SDK builds the net8.0 UI with NativeAOT
  8.0.31; the official build used 8.0.15. Built this way, stock 2.1.1 played
  the same as the official binary.

Nothing here installs the binary. To try it with the harness:
- Point a tree's `tools/Mesen-linux` at a directory holding it.
- Use a private `OT6_MESEN_CACHE`, so the shared copy other workers use is
  left alone.
- Export `MESEN_SCRIPT_ONLY=1`; run.sh passes its environment through to Mesen.

## macOS arm64 (untried)

Upstream's workflow builds the Mac app on macos-14 with `USE_AOT=true make`.
The makefile turns LTO and static linking off on Darwin. The steps would be:
- Install SDL2 (already in the Brewfile), Xcode's clang and a .NET 8 SDK.
- Apply the patches and run `USE_AOT=true make CXX="clang++ -fno-semantic-interposition"`.
- Sign the app ad hoc: `codesign --force --deep -s - Mesen.app`.

The output is `bin/osx-arm64/Release/osx-arm64/publish/Mesen.app`.
`build.sh` is Linux-only as written: it uses the Linux make flags,
`sha256sum` and the Linux output path. The patches are plain C++ and aren't
platform-specific.
