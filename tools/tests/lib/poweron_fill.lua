-- poweron_fill.lua -- the power-on fill (OT6_POWERON_FILL), a declared
-- harness mode for finding reads of memory the game never wrote.
--
-- compose.py puts this file at the very top of a composed script, before the
-- preamble and the lib, when (and only when) OT6_POWERON_FILL names a mode
-- and the tree is a fill tree (build/FILL_TREE, made by tools/fill_line.py).
-- A normal run's composed script does not contain it, so a normal run's bytes
-- cannot depend on it.  compose.py defines, ahead of this chunk:
--
--   OT6_FILL_MODE   "ones" | "alt" | "rand"
--   OT6_FILL_SEED   integer (rand only; 0 otherwise)
--   OT6_FILL_REGIONS the RAMs to fill, a set of wram, sram, vram, oam, dsp,
--                   cgram, spc (default wram and sram); a region may
--                   instead map to {ranges = {{lo, hi}...}, except = bool,
--                   text = ...} to fill only those offsets, or all but them
--                   (a lab bisection).  sram is dropped
--                   when a battery was handed to the run
--                   (OT6_SRAM_CHECKPOINT): Mesen loaded it over SRAM, and its
--                   never-written ranges already carry the fill of the run
--                   that saved it.
--
-- Why a Lua write and not Mesen's Snes.RamPowerOnState: that setting offers
-- AllZeros, AllOnes and an unseeded Random only.  The write lands before the
-- first instruction: run under --testrunner, Mesen pauses, loads the ROM
-- (the RAM's power-on state is set there), breaks the CPU before its first
-- instruction because the emulator was paused with a debugger attached
-- (Emulator::InternalLoadRom, `needPause`), then loads the script, whose main
-- chunk this is, and only then resumes (UI/Utilities/TestRunner.cs).  The
-- [fill] line records the CPU's cycle count and PC at the write, and an exec
-- callback on the reset vector's target records that the first instruction
-- ran on filled memory (`[fill] first instruction`), so every fill run's log
-- carries its own proof.
--
-- The pattern is a function of (region, offset), so tools/fill_diff.py
-- recomputes what any byte held at power-on without replaying anything.

do
  local mode, seed = OT6_FILL_MODE, OT6_FILL_SEED or 0
  local M32 = 0xFFFFFFFF
  local function mix(region, off)
    local h = (off * 0x9E3779B1 + seed * 0x85EBCA77 + region * 0xC2B2AE3D) & M32
    h = h ~ (h >> 15); h = (h * 0x2C1B3C6D) & M32
    h = h ~ (h >> 12); h = (h * 0x297A2D39) & M32
    h = h ~ (h >> 15)
    return h & 0xFF
  end
  local function value(region, off)
    if mode == "ones" then return 0xFF end
    if mode == "alt" then return (off & 1) == 0 and 0x55 or 0xAA end
    return mix(region, off)
  end
  -- region ids are part of the rand pattern; fill_diff.py uses the same.
  local mt = emu.memType
  local regions = {
    {1, "wram",  mt.snesWorkRam,   0x20000},
    {2, "sram",  mt.snesSaveRam,   0x8000},
    {3, "vram",  mt.snesVideoRam,  0x10000},
    {4, "oam",   mt.snesSpriteRam, 0x220},
    {5, "cgram", mt.snesCgRam,     0x200},
    {6, "spc",   mt.spcRam,        0x10000},
    {7, "dsp",   mt.spcDspRegisters, 0x80},   -- the S-DSP register file
  }
  local clock = emu.getMasterClock()
  local cycles = emu.getCpuCycleCount(emu.cpuType.snes)
  local st = emu.getState()
  local pc = ((st["cpu.k"] or 0) << 16) | (st["cpu.pc"] or 0)
  local done, readback = {}, {}
  for _, r in ipairs(regions) do
    local id, name, memtype, size = r[1], r[2], r[3], r[4]
    local sel = OT6_FILL_REGIONS[name]
    if sel then
      -- sel is true (the whole RAM), or a lab bisection's {lo, hi} ranges:
      -- only those offsets, or (except) all but them
      local function filled(off)
        if sel == true then return true end
        for _, rr in ipairs(sel.ranges) do
          if off >= rr[1] and off <= rr[2] then return not sel.except end
        end
        return sel.except
      end
      if sel == true and mode == "ones" then
        for off = 0, size - 1 do emu.write(off, 0xFF, memtype) end
      else
        for off = 0, size - 1 do
          if filled(off) then emu.write(off, value(id, off), memtype) end
        end
      end
      -- read it all back: a RAM the debugger cannot write would otherwise
      -- pass for a fill that changed nothing
      local bad = 0
      for off = 0, size - 1 do
        if filled(off) and emu.read(off, memtype) ~= value(id, off) then bad = bad + 1 end
      end
      done[#done + 1] = sel == true and name or (name .. (sel.except and "~" or ":") .. sel.text)
      readback[#readback + 1] = bad == 0 and (name .. " ok") or string.format("%s %d MISMATCHED", name, bad)
    end
  end
  local reset = emu.read(0xFFFC, mt.snesMemory) | (emu.read(0xFFFD, mt.snesMemory) << 8)
  print(string.format("[fill] mode=%s seed=%d regions=%s at masterClock=%d cpuCycles=%d pc=%06X (reset vector $%04X); readback %s",
    mode, seed, table.concat(done, ","), clock, cycles, pc, reset, table.concat(readback, ", ")))
  -- Mesen iterates its callback list while it calls one, so this one is
  -- never removed (removing it from inside itself would mutate that list);
  -- it reports once and then returns at once.
  local seen = false
  emu.addMemoryCallback(function()
    if seen then return end
    seen = true
    local w0 = emu.read(0x0000, mt.snesWorkRam)
    local w1 = emu.read(0x1FFFF, mt.snesWorkRam)
    print(string.format("[fill] first instruction at $%04X: cpuCycles=%d wram[$0000]=%02X (fill %02X) wram[$1FFFF]=%02X (fill %02X)",
      reset, emu.getCpuCycleCount(emu.cpuType.snes), w0, value(1, 0), w1, value(1, 0x1FFFF)))
  end, emu.callbackType.exec, reset, reset)
end
