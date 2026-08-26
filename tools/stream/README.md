# tools/stream -- watchable recordings of headless playthroughs

Turn any harness run into a video you can watch: the game (with its audio)
plus, **below** the game -- never over it -- a controller readout that lights
up per frame from the harness's own input log, a frame counter, and the
run's `H.log` notes as a soft subtitle track.

## Usage

```sh
OT6_RECORD=1 tools/tests/run.sh tools/tests/battle_boost.lua
open build/stream/battle_boost.mp4
```

That is the whole interface.  The run behaves exactly as it does unrecorded
(same verdict, same frame counts -- see Determinism below); at run end
`build/stream/<script>.mp4` appears, alongside two sidecars:

- `<script>.inputs.tsv` -- frame-stamped pad-change log (`3023<TAB>a+down`)
- `<script>.notes.srt`  -- every `H.log` line, frame-stamped, as subtitles
  (also muxed into the MP4 as a soft track; enable it in the player)

A FAILed run is composed too -- watching what a run did is most of the point
when it did the wrong thing.  With `OT6_RECORD` unset, nothing in this
directory runs and `run.sh` is byte-for-byte on its old path.

Requires `ffmpeg` (in the Brewfile).  The panel itself is drawn pixel-by-
pixel by `compose.py` and piped in as raw video, so only core ffmpeg filters
are needed -- the Homebrew ffmpeg bottle ships without libass/freetype, so
`subtitles`/`drawtext` filters do not exist in it (checked 9.0.1_1).

## How the capture works (and why there is a custom host)

Mesen 2.1.1's own video recorder does the capture: ZMBV video plus the
emulated audio as interleaved PCM, one pass, one AVI.  It works with no
window and no audio device -- both claims verified in Mesen's source at the
tag the shipped binary reports (2.1.1 = commit 137ae7ce), then by running:

- `VideoRenderer::UpdateFrame` calls `ProcessAviRecording(frame)` *before*
  its `if(_renderer)` check, so frames reach the recorder with no rendering
  device attached (Core/Shared/Video/VideoRenderer.cpp:162-181).
- `SoundMixer::PlayAudioBuffer` feeds the recorder gated only on "is a
  recorder attached", before and independent of the audio-device branch and
  of `EnableAudio` (Core/Shared/Audio/SoundMixer.cpp:132-160) -- so the test
  profile's audio-off pin needs no change, and the tape still has sound.
- Recording forces every frame to render: `_skipRender` requires
  `!IsRecording()` (Core/SNES/SnesPpu.cpp:491-499); the harness already pins
  `DisableFrameSkipping` anyway.

What Mesen does **not** provide is any way to *start* that recorder
headless.  Ruled out, in order:

- **Lua**: the API has no record call (the full function table is
  Core/Debugger/LuaApi.cpp:90-160).
- **Command line**: `--testrunner` accepts no recording flag
  (UI/Utilities/CommandLineHelper.cs:59-99; `recordMovie` there is a `.mmo`
  input-movie, not video, and is only wired on the GUI path,
  CommandLineHelper.cs:150-156).
- **`package.loadlib`** (load a shim into Mesen's Lua): compiled out --
  no `LUA_USE_DLOPEN`/`LUA_USE_MACOSX` anywhere in Mesen2's makefile, and
  the shipped MesenCore.dylib carries loadlib.c's "dynamic libraries not
  enabled" fallback string.
- **DYLD injection**: the shipped app is hardened-runtime signed
  (`flags=0x10000(runtime)`) without
  `com.apple.security.cs.allow-dyld-environment-variables`, so dyld strips
  `DYLD_INSERT_LIBRARIES`.
- **.NET startup hooks**: the host binary carries no `DOTNET_STARTUP_HOOKS`
  support string, and there is no C# toolchain on this machine anyway.

The recorder *is* reachable through the C exports the shipped GUI calls:
`AviRecord`/`AviStop` (InteropDLL/RecordApiWrapper.cpp:11-13), which are
plain exported symbols in MesenCore.dylib (`nm -gU` shows `_AviRecord`).
So `mesen_record.cpp` is a ~150-line host that dlopens the same
MesenCore.dylib the app uses and drives the same exported API in the same
order as Mesen's own testrunner (UI/Utilities/TestRunner.cs:16-66), plus one
`AviRecord` call while the emulator is still paused so the tape starts at
frame 0.  It applies the pin_test_saves.py pins (controller, RAM power-on
state, frame skipping, script timeout, private save folder) through the same
`SetXxxConfig` exports the C# UI uses, with struct layouts copied verbatim
from 2.1.1's Core/Shared/SettingTypes.h and a `GetMesenVersion() == 0x020101`
guard that refuses any other core, since a by-value struct against a drifted
layout is silent corruption.

## The pipeline

1. `run.sh` (record mode) compiles `mesen_record`, prepends `OT6_RECORD =
   true` to a copy of the composed script, and runs the host instead of the
   testrunner.  Same workspace isolation, same saves wipe, same checkpoint
   materialization, same verdict parsing, same timeout retry.
2. `lib/ot6.lua`'s recording taps ("recording sidecars" section) emit
   `[ot6pad] <frame> <buttons>` on every pad change from `M.setPad`, and
   `[ot6note] <frame> <text>` from every `M.log`, over stdout into the run
   log like everything else.
3. `compose.py` reads the tape + log and renders the MP4: the 256x224 tape
   scaled 2x nearest to 512x448, panel drawn underneath at 512x112, notes
   muxed as soft mov_text subtitles.

### The recorded run must be the testrunner's run

The C# layer's SNES defaults differ from the core's own struct defaults in
two places, and the testrunner applies the C# ones, so the host must too:

- **Overscan 7 top / 8 bottom** (UI/Config/SnesConfig.cs:45 vs
  SettingTypes.h:562).  Behavioral, not just cosmetic: the decoded frame
  size feeds `emu.takeScreenshot()`, whose PNG byte count
  `M.screenLooksAlive()` thresholds.  Also puts the tape at the 256x224
  the repo's screenshots document.
- **SpcClockSpeedAdjustment 40** (UI/Config/SnesConfig.cs:62 vs
  SettingTypes.h:570).  The SPC clock derives from it (32000 + adjustment,
  Core/SNES/Spc.cpp:54,126; the 40 maps to real hardware's 32040Hz).  At
  32000Hz the CPU/SPC interleaving shifts within the frame and long runs
  diverge (the game's H/V-counter load at $0630-$0632 samples one scanline
  apart, then encounter resolution drifts).

With both matched, recorded and unrecorded runs pass at identical frames
with byte-identical WRAM.  If a Mesen upgrade shifts these defaults again,
this is the first place to look when a recorded run stops matching its
unrecorded twin.

### Frame alignment

Tape frame `n` (0-based) holds the frame during which `M.frame` read `n+1`:
recording starts while the emulator is still paused, and `M.frame`
increments at `startFrame` before the frame is decoded.  The panel's counter
therefore prints `n+1`, and a pad event stamped frame `F` lights its buttons
from tape frame `F-1`.  Cross-check on the demo: the run's `PASS (frame
3023)` and a 3024-frame tape agree exactly (frames 1..3024; `emu.stop`
lands one frame after the verdict).  The pad set at frame `F` is latched by
the ROM at that frame's input poll, so the game's reaction can trail the
panel by a frame -- watchable in the demo where each A-press's dialog
advance lands right at the lit frame.

The two vstack branches are pinned to the same timebase with pts = frame
index (`settb`/`setpts=N` in compose.py); without that, framesync pads
duplicate frames and the panel walks out of step.  `verify_panel.py` exists
so that failure mode cannot come back silently.

## Verifying a render

```sh
python3 tools/stream/verify_panel.py build/stream/battle_boost.mp4 \
        build/stream/battle_boost.inputs.tsv             # must PASS
python3 tools/stream/verify_panel.py build/stream/battle_boost.mp4 \
        build/stream/battle_boost.inputs.tsv --shift 30  # must FAIL
```

It samples pad intervals from the input log, extracts the video frame in the
middle of each, and checks all 12 button cells (held must be lit, idle must
be dark) plus the frame-counter digits (rendered with compose.py's own font;
at least 90% of expected pixels lit and at most 10% stray).  `--shift`
deliberately reads the wrong frame and must fail; run it once after touching
compose.py, because a checker that cannot fail is not a check.

## Measurements (battle_boost, 3023 frames, M4-class machine)

- Recording overhead on the emulator: **none measurable**.  Same host, same
  script, tape vs no tape (`mesen_record ... -` skips the recorder):
  11.28s/11.29s without, 11.20s/10.89s with.  The ZMBV encoder runs on its
  own thread (AviRecorder.cpp:56-67) and the machine has idle cores.
- Determinism: recorded and unrecorded runs both end `PASS (frame 3023)`;
  the taps and the recorder touch no emulated state
  (`tools/check_state_writes.py` stays green).
- Compose: ~1.4s for 3024 frames (panel drawing + x264 veryfast).
- Sizes: 20MB tape -> 3.1MB MP4 for 50s of gameplay.
- End-to-end wall cost of `OT6_RECORD=1`: 10.5s -> 12.2s on this run
  (host compile ~1s + compose ~1.4s; capture itself free, above).

## Verified vs deferred

Verified this pass:

- Headless one-pass video+audio capture through the real testrunner code
  path, from power-on, frame-exact against the input log (see above).
- Audio present with the audio pin untouched (RMS -24dB on the title theme;
  silence over the first boot seconds is the game's own).
- run.sh record mode end to end on a suite test (`battle_boost`), the
  FAIL path (a deliberately failing script still composed its 122-frame
  video), and zero-diff behavior with `OT6_RECORD` unset (no
  `[ot6pad]`/`[ot6note]` lines, verdict selftest green, smoke green).
- `OT6_SRAM_CHECKPOINT` under record mode: `gen_vector_entry` from the
  post-opera-v1 checkpoint passes recorded at the same frame (6029) as the
  stock testrunner run, and `verify_panel.py` is green on the result.  This
  run is also what caught the two config divergences above.

Deferred / known limits:

- **Watch-while-running.**  The AVI index is finalized at emulator exit, so
  the MP4 exists only after the run.  ffmpeg can read a growing index-less
  AVI, so a live "follow" compose is plausible; not built this pass.
- **Resolution switches.**  `AviRecorder::AddFrame` stops the recording if
  the frame size ever changes (AviRecorder.cpp:88-106).  FF6 stayed 256x239
  for everything recorded so far; a hi-res switch mid-run would truncate the
  tape rather than corrupt it, and compose.py warns on unexpected geometry.
  `Snes.ForceFixedResolution` exists but was deliberately not pinned: it
  changes screenshot sizes, and `M.screenLooksAlive()`'s thresholds read
  those, so pinning it could make a recorded run *behave* differently.
- **Suite-wide recording** (`suite.sh` fan-out with OT6_RECORD): untested;
  record one test at a time for now.
- **The soft-subtitle track needs the player's cooperation** (QuickTime:
  View > Subtitles; VLC/mpv pick it up as track "eng").  Burning notes into
  the panel would need a text renderer for arbitrary strings; the bitmap
  font in compose.py covers only what the panel draws.
- The host applies the harness's determinism pins but not the play
  profile's cosmetic settings (video filters, equalizer); those are
  output-side only.  `OT6_RAM_POWERON` is honored.

## Watching live (tools/stream/live.py)

The tape is a sequential ZMBV stream, so it decodes while it is still being
written: `live.py` follows the newest recording workspace (`tail -f` piped
through ffmpeg), serves one page showing the newest frame, the live frame
counter and held pad from the `[ot6pad]` taps, and the driver's `[ot6note]`
lines.

    OT6_RECORD=1 tools/tests/run.sh tools/tests/<x>.lua &
    python3 tools/stream/live.py        # http://127.0.0.1:8611/

The image feed samples at 4 fps and tracks the emulator with negligible lag;
the pad/frame readout lags by Mesen's stdout block buffering.  Known limit,
inherited from the recorder: if the tape stops (frame-geometry change), the
image freezes while the pad/note telemetry keeps flowing.
