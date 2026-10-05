#!/usr/bin/env python3
"""rc_categorize.py <sample.txt>... -- bucket macOS `sample`'s "Sort by top of
stack" (self time) by what the work is for.  Derived from
build/attempts/wt/emu-profile/scripts/categorize_sample.py, with the PPU split
into the pixel pipeline _skipRender gates (and SendFrame's work) versus the
PPU timing/sprite-evaluation/register work that runs on every frame anyway,
and the DSP split from the SPC700.  Idle waits of sleeping threads are left out.
"""
import re, sys

RULES = [
    ("debugger + script-only bookkeeping", r"(^|[ :<])(Debugger|SnesDebugger|SpcDebugger|BreakpointManager|Profiler|SnesEventManager|BaseEventManager|CodeDataLogger|CdlManager|CallstackManager|MemoryAccessCounter|TraceLogger|DisassemblyInfo|Disassembler|ExpressionEvaluator|FrozenAddressManager|MemoryDumper|StepRequest|DebugUtilities)::"),
    ("lua dispatch + VM + emu.* API (harness Lua)", r"(ScriptingContext|ScriptManager|LuaApi|LuaCallHelper|^lua|^l_|^str_|^tconcat|^math_|^tinsert|^auxsort|^propagatemark|^singlestep|^reallymarkobject|^sweep|^atomic|^traverse|^freeobj|^precall|^luaE_|^luaH|^luaS|^luaO|^luaV|^luaD|^luaC|^luaF|^luaG|^luaM|^luaT|^luaK|^luaY|^luaX|^llex|^index2value|^auxgetstr|^getgeneric|^mainpositionTV|^insert_newkey|^rehash|^internshrstr|^createstrobj|^tostringbuff|^str_format|^gmatch|^match|^do_match|^max_expand|^singlematch|^classend|^add_value|^add_s|^moveresults|^retstat|^funcargs|^GCTM|^callclosemethod)"),
    ("png/deflate (screenshots, savestates)", r"(tdefl|tinfl|mz_|miniz|PNGHelper|spng|crc32|adler)"),
    ("rewind/savestate", r"(RewindManager|RewindData|SaveStateManager|Serializer)"),
    ("PPU pixel pipeline (what _skipRender skips)", r"SnesPpu::(FetchTileData|GetHorizontalOffsetByte|GetVerticalOffsetByte|GetTilemapData|GetChrData|Render(Mode|Tilemap|Sprites|BgColor)|ApplyColorMath|ApplyBrightness|ApplyHiResMode|ProcessMaskWindow|DrawMainPixel|DrawSubPixel|GetRgbColor|IsRenderRequired|ConvertToHiRes|SendFrame|FillInterlacedFrame|ApplyColorMathToPixel)"),
    ("PPU other (scanline timing, sprite eval/fetch, registers)", r"SnesPpu::"),
    ("video output (decode thread: filter/convert)", r"(VideoDecoder|SnesDefaultVideoFilter|BaseVideoFilter|VideoRenderer|ScaleFilter|RotateFilter|SoftwareRenderer|RenderedFrame|ScanlineFilter|DebugHud|SystemHud)"),
    ("DSP (sample synthesis, envelopes, echo)", r"(^|[ :])(Dsp|DspVoice)(::|<)"),
    ("SPC700 (+timers)", r"(^|[ :])(Spc|SpcTimer)(::|<)"),
    ("audio output (resample/mix)", r"(SoundMixer|HermiteResampler|SoundResampler|blip_|Equalizer|ReverbFilter|CrossFeedFilter|WaveRecorder)"),
    ("CPU + bus + DMA + clocks", r"(SnesCpu|DummySnesCpu|SnesMemoryManager|RamHandler|RomHandler|RegisterHandler|SnesDmaController|InternalRegisters|BaseCartridge|SnesConsole|SnesControlManager|SnesController|IMemoryHandler|MemoryMappings|AluMulDiv|CpuBwRamHandler|BaseControlManager|ControlManager|Emulator::|NotificationManager)"),
    ("libc/kernel/other", r"."),
]
IDLE = ("__psynch_cvwait", "__workq_kernreturn", "__semwait_signal", "mach_msg2_trap", "__select",
        "kevent", "__gettimeofday", "cerror_nocancel", "_pthread_cond_wait", "_pthread_mutex_droplock",
        "_pthread_exit_if_canceled", "_pthread_cond_updateval", "Rh", "SystemNative_", "AutoResetEvent",
        "clock_gettime", "mach_absolute_time", "clock_get_time", "__commpage_gettimeofday", "nanosleep",
        "__ulock_wait", "swtch_pri", "thread_switch")

for path in sys.argv[1:]:
    text = open(path, errors="replace").read()
    sec = text.split("Sort by top of stack, same collapsed (when >= 5):", 1)[1]
    tot, allc, other, top = {}, 0, {}, []
    for line in sec.splitlines():
        m = re.match(r"\s+(.*?)\s+\(in (\S+)\)\s+(\d+)\s*$", line)
        if not m:
            continue
        sym, n = m.group(1), int(m.group(3))
        if sym.startswith(IDLE):
            continue
        allc += n
        top.append((n, sym))
        for name, rx in RULES:
            if re.search(rx, sym):
                tot[name] = tot.get(name, 0) + n
                if name.startswith("libc"):
                    other[sym] = other.get(sym, 0) + n
                break
    print(f"== {path}  ({allc} busy samples at 1 ms, idle waits excluded)")
    for name, _ in RULES:
        print(f"  {tot.get(name, 0) / allc * 100:5.1f}%  {name}")
    print("    other, top: " + "; ".join(f"{s[:40]} {n/allc*100:.1f}%" for s, n in sorted(other.items(), key=lambda kv: -kv[1])[:5]))
    print("    top 25 self:")
    for n, s in sorted(top, reverse=True)[:25]:
        print(f"      {n/allc*100:5.1f}%  {s[:110]}")
