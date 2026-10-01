# Mesen 2.1.1, script-only build

`mesen-script-only.patch` applies to the official Mesen 2.1.1 source
(github.com/SourMesen/Mesen2, tag `2.1.1`, commit `137ae7ce`). `build.sh`
clones that tag, applies the patch and builds it with the flags of upstream's
own release workflow for the official Linux binary. Mesen's source isn't
vendored here.

## Why

The harness's Lua needs Mesen's debugger: Mesen only runs scripts through it.
In stock Mesen the debugger also does per-access bookkeeping for its own
windows on every CPU and audio-processor (SPC) memory access, whether or not
a window is open:
- access counters
- the code/data log
- call-stack tracking
- the event log
- step and break checks

Our runs use none of it. On px13 it is 28% of an emulator's cycles. Script-only
mode cuts instructions per frame by 20-25% on our legs, with the same results
(`build/attempts/wt/mesen-lean/`).

## What the patch does

**Script-only mode.** It is on when the environment has `MESEN_SCRIPT_ONLY=1`
and no debugger window is open; opening a debugger window turns it off. In
this mode the SNES CPU and SPC debuggers record only the last memory
operation per access, which the Lua callbacks read. They still stop for a
break request between instructions, which is how savestates and other
threads reach the emulator. Any step request, breakpoint or trace logger
drops a CPU back to the full path. Per-PPU-cycle debugger work is skipped
unless a PPU step is pending.

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

## Building (Linux x64)

```
sudo apt install git make clang lld zip libsdl2-dev zlib1g-dev dotnet-sdk-10.0 dotnet-sdk-aot-10.0
tools/mesen/build.sh ~/work/mesen-build            # patched
tools/mesen/build.sh ~/work/mesen-build --stock    # stock, for comparison
```

The output is one self-contained binary,
`<workdir>/Mesen2/bin/linux-x64/Release/linux-x64/publish/Mesen`, shaped
like the official zip's.
- Each build is clean: the makefile tracks no header dependencies.
- On Ubuntu 26.04 the compiler is clang 21; the official build used clang 14
  on Ubuntu 22.04.
- The .NET 10 SDK builds the net8.0 UI with NativeAOT 8.0.31; the official
  build used 8.0.15.
- Built this way, stock 2.1.1 played the same as the official binary: the
  same `[ot6]` lines, RAM hashes and screenshots
  (`build/attempts/wt/mesen-lean/`).

Nothing here installs the binary. To try it with the harness:
- Point a tree's `tools/Mesen-linux` at a directory holding it.
- Use a private `OT6_MESEN_CACHE`, so the shared copy other workers use is
  left alone.
- Export `MESEN_SCRIPT_ONLY=1`; run.sh passes its environment through to Mesen.

## macOS arm64 (untried)

Upstream's workflow builds the Mac app on macos-14 with `USE_AOT=true make`.
The makefile turns LTO and static linking off on Darwin. The steps would be:
- Install SDL2 (already in the Brewfile), Xcode's clang and a .NET 8 SDK.
- Apply the patch and run `USE_AOT=true make`.
- Sign the app ad hoc: `codesign --force --deep -s - Mesen.app`.

The output is `bin/osx-arm64/Release/osx-arm64/publish/Mesen.app`.
`build.sh` is Linux-only as written: it uses the Linux make flags,
`sha256sum` and the Linux output path. The patch is plain C++ and isn't
platform-specific.
