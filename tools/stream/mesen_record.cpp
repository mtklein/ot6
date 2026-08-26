// mesen_record.cpp -- headless Mesen 2 driver that records the run to an AVI.
//
//   mesen_record <MesenCore.dylib> <home_dir> <saves_dir> <rom.sfc> \
//                <script.lua> <out.avi> <timeout_seconds>
//
// Why this program exists.  Mesen 2.1.1's video recorder (ZMBV-in-AVI, with
// the emulated audio interleaved as PCM) lives in the core and works with no
// window: VideoRenderer::UpdateFrame calls ProcessAviRecording BEFORE the
// `if(_renderer)` check (Core/Shared/Video/VideoRenderer.cpp:162-181), and
// SoundMixer::PlayAudioBuffer feeds the recorder before the audio-device
// branch, gated only on `isRecording` (Core/Shared/Audio/SoundMixer.cpp:132-140),
// so neither a rendering device nor an audio device is needed.  What is
// missing is any way to START it headless: recording is reachable only
// through the InteropDLL exports AviRecord/AviStop
// (InteropDLL/RecordApiWrapper.cpp:11-13), which only the C# GUI calls.  The
// Lua surface has no record function (Core/Debugger/LuaApi.cpp:90-160), the
// testrunner has no flag for it (UI/Utilities/TestRunner.cs:16-66,
// UI/Utilities/CommandLineHelper.cs:59-99), and the sandbox's package.loadlib
// is compiled out (no LUA_USE_DLOPEN anywhere in Mesen2's makefile; the
// shipped MesenCore.dylib carries loadlib.c's "dynamic libraries not
// enabled" fallback string).  DYLD injection into the shipped app is blocked
// by its hardened-runtime signature (flags=0x10000(runtime), and no
// com.apple.security.cs.allow-dyld-environment-variables entitlement).
//
// So this program IS the missing caller: it dlopens the same MesenCore.dylib
// the shipped app uses and drives the same exported C API in the same order
// as Mesen's own testrunner (UI/Utilities/TestRunner.cs:16-66 -- InitDll,
// apply config, InitializeEmu with null handles, Pause, ConsoleMode flag,
// LoadRom, LoadScript, MaximumSpeed flag, Resume, poll IsRunning), plus one
// AviRecord call while still paused so frame 0 is on tape.  Passing null
// window handles takes the exact branch the testrunner takes: no renderer,
// no sound device, no key manager (InteropDLL/EmuApiWrapper.cpp:80-127).
//
// Config.  The real testrunner applies the C# ConfigManager's settings.json;
// this host has no C# layer, so it applies the harness pins directly through
// the same SetXxxConfig exports (InteropDLL/ConfigApiWrapper.cpp).  The
// struct definitions below are copied verbatim (methods dropped -- they do
// not affect layout) from Mesen 2.1.1's Core/Shared/SettingTypes.h at the
// cited lines, and a GetMesenVersion() == 0x020101 guard refuses to run
// against any other core, because a struct passed by value into a dylib
// whose layout has drifted is silent corruption.  The pins mirror
// tools/tests/lib/pin_test_saves.py: SnesController on port 0, RamPowerOnState
// (OT6_RAM_POWERON, default AllZeros), DisableFrameSkipping, ScriptTimeout 30,
// and the battery-save folder pinned to <saves_dir> -- run.sh passes its
// invocation-private saves directory, so save isolation holds by construction.
// Settings the play profile might carry beyond these pins (video filters,
// equalizers) are output-side only; EmulationConfig defaults match the pins'
// assumptions (RunAheadFrames = 0, SettingTypes.h:379-386).
//
// Exit code: the emu.stop() code, exactly like the real testrunner
// (0 = steps completed, 1 = Lua error, 2 = frame budget); -1/255 if the ROM
// or script never finished (timeout), mirroring TestRunner.cs:52-65.

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <chrono>
#include <thread>
#include <vector>
#include <dlfcn.h>

// ---- structs copied from Mesen 2.1.1 Core/Shared/SettingTypes.h ----------
// (verbatim fields; member functions omitted -- they carry no storage)

// SettingTypes.h:5-15
enum class EmulationFlags : uint32_t {
  MaximumSpeed = 0x04,
  ConsoleMode = 0x10,
  OutputToStdout = 0x40,
};

// SettingTypes.h:245-287
struct KeyMapping {
  uint16_t A = 0, B = 0, X = 0, Y = 0, L = 0, R = 0;
  uint16_t Up = 0, Down = 0, Left = 0, Right = 0, Start = 0, Select = 0;
  uint16_t U = 0, D = 0;
  uint16_t TurboA = 0, TurboB = 0, TurboX = 0, TurboY = 0, TurboL = 0,
           TurboR = 0, TurboSelect = 0, TurboStart = 0;
  uint16_t GenericKey1 = 0;
  uint16_t CustomKeys[100] = {};
};

// SettingTypes.h:289-296
struct KeyMappingSet {
  KeyMapping Mapping1, Mapping2, Mapping3, Mapping4;
  uint32_t TurboSpeed = 0;
};

// SettingTypes.h:175-181 (SNES members; later consoles' values are unused here)
enum class ControllerType : uint32_t { None = 0, SnesController = 1 };

// SettingTypes.h:316-320
struct ControllerConfig {
  KeyMappingSet Keys;
  ControllerType Type = ControllerType::None;
};

// SettingTypes.h:342-346
enum class RamState : uint32_t { Random = 0, AllZeros = 1, AllOnes = 2 };
// SettingTypes.h:349-355
enum class ConsoleRegion : uint32_t { Auto = 0 };
// SettingTypes.h:534-540
enum class DspInterpolationType : uint32_t { Gauss = 0 };
// SettingTypes.h:388-394
struct OverscanDimensions { uint32_t Left = 0, Right = 0, Top = 0, Bottom = 0; };

// SettingTypes.h:542-577
struct SnesConfig {
  ControllerConfig Port1;
  ControllerConfig Port2;
  ControllerConfig Port1SubPorts[4];
  ControllerConfig Port2SubPorts[4];
  ConsoleRegion Region = ConsoleRegion::Auto;
  bool AllowInvalidInput = false;
  bool BlendHighResolutionModes = false;
  bool HideBgLayer1 = false;
  bool HideBgLayer2 = false;
  bool HideBgLayer3 = false;
  bool HideBgLayer4 = false;
  bool HideSprites = false;
  bool DisableFrameSkipping = false;
  bool ForceFixedResolution = false;
  OverscanDimensions Overscan = {};
  DspInterpolationType InterpolationType = DspInterpolationType::Gauss;
  uint32_t ChannelVolumes[8] = { 100, 100, 100, 100, 100, 100, 100, 100 };
  bool EnableRandomPowerOnState = false;
  bool EnableStrictBoardMappings = false;
  RamState RamPowerOnState = RamState::Random;
  int32_t SpcClockSpeedAdjustment = 0;
  uint32_t PpuExtraScanlinesBeforeNmi = 0;
  uint32_t PpuExtraScanlinesAfterNmi = 0;
  uint32_t GsuClockSpeed = 100;
  int64_t BsxCustomDate = -1;
};

// SettingTypes.h:783-788
enum class GbaDisassemblyMode : uint8_t { Default = 0 };

// SettingTypes.h:790-858
struct DebugConfig {
  bool BreakOnUninitRead = false;
  bool ShowJumpLabels = false;
  bool DrawPartialFrame = false;
  bool ShowVerifiedData = false;
  bool DisassembleVerifiedData = false;
  bool ShowUnidentifiedData = false;
  bool DisassembleUnidentifiedData = false;
  bool UseLowerCaseDisassembly = false;
  bool ShowMemoryValues = false;
  bool AutoResetCdl = false;
  bool UsePredictiveBreakpoints = false;
  bool SingleBreakpointPerInstruction = false;
  bool SnesBreakOnBrk = false;
  bool SnesBreakOnCop = false;
  bool SnesBreakOnWdm = false;
  bool SnesBreakOnStp = false;
  bool SnesBreakOnInvalidPpuAccess = false;
  bool SnesBreakOnReadDuringAutoJoy = false;
  bool SnesUseAltSpcOpNames = false;
  bool SnesIgnoreDspReadWrites = false;
  bool SpcBreakOnBrk = false;
  bool SpcBreakOnStpSleep = false;
  bool GbBreakOnInvalidOamAccess = false;
  bool GbBreakOnInvalidVramAccess = false;
  bool GbBreakOnDisableLcdOutsideVblank = false;
  bool GbBreakOnInvalidOpCode = false;
  bool GbBreakOnNopLoad = false;
  bool GbBreakOnOamCorruption = false;
  bool NesBreakOnBrk = false;
  bool NesBreakOnUnofficialOpCode = false;
  bool NesBreakOnUnstableOpCode = false;
  bool NesBreakOnCpuCrash = false;
  bool NesBreakOnBusConflict = false;
  bool NesBreakOnDecayedOamRead = false;
  bool NesBreakOnPpuScrollGlitch = false;
  bool NesBreakOnExtOutputMode = false;
  bool NesBreakOnInvalidVramAccess = false;
  bool NesBreakOnInvalidOamWrite = false;
  bool NesBreakOnDmaInputRead = false;
  bool PceBreakOnBrk = false;
  bool PceBreakOnUnofficialOpCode = false;
  bool PceBreakOnInvalidVramAddress = false;
  bool SmsBreakOnNopLoad = false;
  bool GbaBreakOnNopLoad = false;
  bool GbaBreakOnInvalidOpCode = false;
  bool GbaBreakOnUnalignedMemAccess = false;
  GbaDisassemblyMode GbaDisMode = GbaDisassemblyMode::Default;
  bool WsBreakOnInvalidOpCode = false;
  bool ScriptAllowIoOsAccess = false;
  bool ScriptAllowNetworkAccess = false;
  uint32_t ScriptTimeout = 1;
};

// SettingTypes.h:860-864
enum class HudDisplaySize : uint32_t { Fixed = 0 };

// SettingTypes.h:866-888
struct PreferencesConfig {
  bool ShowFps = false;
  bool ShowFrameCounter = false;
  bool ShowGameTimer = false;
  bool ShowLagCounter = false;
  bool ShowDebugInfo = false;
  bool DisableOsd = false;
  bool AllowBackgroundInput = false;
  bool PauseOnMovieEnd = false;
  bool ShowMovieIcons = false;
  bool ShowTurboRewindIcons = false;
  bool DisableGameSelectionScreen = false;
  HudDisplaySize HudSize = HudDisplaySize::Fixed;
  uint32_t AutoSaveStateDelay = 5;
  uint32_t RewindBufferSize = 300;
  const char* SaveFolderOverride = nullptr;
  const char* SaveStateFolderOverride = nullptr;
  const char* ScreenshotFolderOverride = nullptr;
};

// Utilities/Video/AviWriter.h:9-15
enum class VideoCodec : uint32_t { None = 0, ZMBV = 1, CSCD = 2, GIF = 3 };

// Core/Shared/Video/VideoRenderer.h:20-26
struct RecordAviOptions {
  VideoCodec Codec;
  uint32_t CompressionLevel;
  bool RecordSystemHud;
  bool RecordInputHud;
};

// ---- the InteropDLL exports we call (InteropDLL/*.cpp) -------------------

template <typename T>
static T sym(void* dl, const char* name) {
  void* p = dlsym(dl, name);
  if (!p) {
    fprintf(stderr, "mesen_record: missing export %s: %s\n", name, dlerror());
    exit(2);
  }
  return reinterpret_cast<T>(p);
}

int main(int argc, char** argv) {
  if (argc != 8) {
    fprintf(stderr, "usage: mesen_record <MesenCore.dylib> <home_dir> "
                    "<saves_dir> <rom.sfc> <script.lua> <out.avi> "
                    "<timeout_seconds>\n");
    return 2;
  }
  const char* corePath = argv[1];
  const char* homeDir = argv[2];
  const char* savesDir = argv[3];
  const char* romPath = argv[4];
  const char* scriptPath = argv[5];
  const char* aviPath = argv[6];
  const int timeoutSec = atoi(argv[7]);

  // Line-buffer stdout: Lua print() inside the core writes to this same
  // stdout, and run.sh reads the log after a kill, so a full buffer must
  // not hold a verdict hostage.
  setvbuf(stdout, nullptr, _IOLBF, 0);

  void* dl = dlopen(corePath, RTLD_NOW | RTLD_LOCAL);
  if (!dl) {
    fprintf(stderr, "mesen_record: dlopen %s: %s\n", corePath, dlerror());
    return 2;
  }

  auto GetMesenVersion = sym<uint32_t (*)()>(dl, "GetMesenVersion");
  auto InitDll = sym<void (*)()>(dl, "InitDll");
  auto InitializeEmu = sym<void (*)(const char*, void*, void*, bool, bool, bool, bool)>(dl, "InitializeEmu");
  auto SetEmulationFlag = sym<void (*)(EmulationFlags, bool)>(dl, "SetEmulationFlag");
  auto SetSnesConfig = sym<void (*)(SnesConfig)>(dl, "SetSnesConfig");
  auto SetDebugConfig = sym<void (*)(DebugConfig)>(dl, "SetDebugConfig");
  auto SetPreferences = sym<void (*)(PreferencesConfig)>(dl, "SetPreferences");
  auto LoadRom = sym<bool (*)(char*, char*)>(dl, "LoadRom");
  auto LoadScript = sym<int32_t (*)(char*, char*, char*, int32_t)>(dl, "LoadScript");
  auto AviRecord = sym<void (*)(char*, RecordAviOptions)>(dl, "AviRecord");
  auto AviIsRecording = sym<bool (*)()>(dl, "AviIsRecording");
  auto AviStop = sym<void (*)()>(dl, "AviStop");
  auto Pause = sym<void (*)()>(dl, "Pause");
  auto Resume = sym<void (*)()>(dl, "Resume");
  auto IsRunning = sym<bool (*)()>(dl, "IsRunning");
  auto GetStopCode = sym<int32_t (*)()>(dl, "GetStopCode");
  auto Stop = sym<void (*)()>(dl, "Stop");
  auto Release = sym<void (*)()>(dl, "Release");

  // The vendored struct layouts above are 2.1.1's.  Refuse any other core.
  uint32_t version = GetMesenVersion();
  if (version != 0x020101) {
    fprintf(stderr, "mesen_record: core reports version %06x, this tool is "
                    "built for 2.1.1 (020101).  Re-verify the SettingTypes.h "
                    "struct layouts against the new source before raising "
                    "this guard.\n", version);
    return 2;
  }

  // Same order as Mesen's own testrunner: UI/Utilities/TestRunner.cs:16-66.
  InitDll();

  // The harness pins, applied through the same interop the C# UI uses.
  SnesConfig snes = {};
  snes.Port1.Type = ControllerType::SnesController;   // pin_test_saves.py #120
  const char* ram = getenv("OT6_RAM_POWERON");
  if (ram && strcmp(ram, "Random") == 0) {
    snes.RamPowerOnState = RamState::Random;
    snes.EnableRandomPowerOnState = true;
  } else if (ram && strcmp(ram, "AllOnes") == 0) {
    snes.RamPowerOnState = RamState::AllOnes;
  } else {
    snes.RamPowerOnState = RamState::AllZeros;        // determinism pin
  }
  snes.DisableFrameSkipping = true;                   // determinism pin
  SetSnesConfig(snes);

  DebugConfig dbg = {};
  dbg.ScriptTimeout = 30;                             // pin_test_saves.py pin
  SetDebugConfig(dbg);

  // Battery saves pinned to the caller's directory (run.sh passes the
  // workspace-private saves dir it wipes and materializes checkpoints into),
  // so a record run cannot touch the play profile's .srm.  Same guarantee
  // pin_test_saves.py gives testrunner runs via SaveDataFolder.
  PreferencesConfig prefs = {};
  prefs.SaveFolderOverride = savesDir;
  SetPreferences(prefs);

  InitializeEmu(homeDir, nullptr, nullptr, true, true, true, true);
  Pause();
  SetEmulationFlag(EmulationFlags::ConsoleMode, true);
  SetEmulationFlag(EmulationFlags::OutputToStdout, true);

  if (!LoadRom(const_cast<char*>(romPath), const_cast<char*>(""))) {
    fprintf(stderr, "mesen_record: LoadRom failed: %s\n", romPath);
    return 2;
  }

  // Start the tape while still paused, so the AVI's first frame is the
  // machine's first frame and the frame counter panel can line up 1:1.
  // An out path of "-" runs everything except the recording itself, which
  // is what isolates the recorder's frame cost in a measurement.
  if (strcmp(aviPath, "-") != 0) {
    RecordAviOptions opts = {};
    opts.Codec = VideoCodec::ZMBV;
    opts.CompressionLevel = 6;    // the GUI's default (VideoRecordConfig.cs:13)
    opts.RecordSystemHud = false; // nothing may draw over the game frame
    opts.RecordInputHud = false;
    AviRecord(const_cast<char*>(aviPath), opts);
    if (!AviIsRecording()) {
      fprintf(stderr, "mesen_record: AviRecord did not start (unwritable %s?)\n",
              aviPath);
      return 2;
    }
  }

  {
    FILE* f = fopen(scriptPath, "rb");
    if (!f) {
      fprintf(stderr, "mesen_record: cannot read %s\n", scriptPath);
      return 2;
    }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    std::vector<char> content(n + 1, 0);
    if (fread(content.data(), 1, n, f) != (size_t)n) {
      fprintf(stderr, "mesen_record: short read on %s\n", scriptPath);
      return 2;
    }
    fclose(f);
    // name/path/content, scriptId -1 = new script (DebugApiWrapper.cpp:186)
    LoadScript(const_cast<char*>(scriptPath), const_cast<char*>(""),
               content.data(), -1);
  }

  SetEmulationFlag(EmulationFlags::MaximumSpeed, true);
  Resume();

  // TestRunner.cs:52-61, with its 100ms poll.
  int result = -1;
  auto start = std::chrono::steady_clock::now();
  while (std::chrono::duration_cast<std::chrono::seconds>(
           std::chrono::steady_clock::now() - start).count() < timeoutSec) {
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    if (!IsRunning()) {
      result = GetStopCode();
      break;
    }
  }

  // Explicit stop first: it joins the writer thread and finalizes the AVI
  // index (AviRecorder.cpp:73-85).  The destructor would too, but only on
  // clean shutdown paths, and we are about to force one.
  AviStop();
  Stop();
  Release();
  return result;
}
