-- read_before_write.lua -- report every read of WRAM or battery SRAM the
-- game makes before anything wrote that byte (OT6_RBW=1).
--
-- compose.py puts this file right after the power-on fill (or first, with
-- no fill) when OT6_RBW is set, in a fill tree only, like the fill.  It
-- changes no emulated state: its callbacks return nothing, so every read
-- and write goes through unchanged.
--
-- Written-since-power-on is a byte per address.  At power-on every WRAM
-- byte is unwritten; battery SRAM is unwritten only when no battery was
-- handed to the run (OT6_RBW_SRAM), since a loaded battery is the game's
-- own earlier writes.  A run that loads a savestate rebuilds nothing: the
-- bitmap describes this run from power-on, so read it on a power-on or
-- Continue leg.
--
-- Cost: callbacks cover only the 64-byte blocks that still hold an
-- unwritten byte, merged into at most RBW_MAX_RANGES ranges and re-cut
-- every RBW_RECUT frames, so the cleared and much-used RAM drops out within
-- the first frames and the run pays only for touching what was never
-- written.  The WRAM port ($2180-$2183, CPU or DMA) writes WRAM without a
-- WRAM address on the bus, so it is followed by hand.
--
-- Each new (instruction, address) is printed once:
--   [rbw] f<frame> <ram> $<addr> read by $<pc> (value $<v>)
-- and a summary per 256-byte page at the end of each recut window that saw
-- a hit.  `pc` is the CPU's program counter during the access (the
-- instruction's own address or a few bytes past it), or the instruction
-- that started a DMA.

do
  local mt, cb = emu.memType, emu.callbackType
  local BLOCK = 64
  local RBW_MAX_RANGES = 24
  local RBW_RECUT = 30
  local written = { wram = {}, sram = {} }
  local sizes = { wram = 0x20000, sram = 0x8000 }
  local types = { wram = mt.snesWorkRam, sram = mt.snesSaveRam }
  local live = { wram = true, sram = OT6_RBW_SRAM and true or false }
  if not live.sram then
    for a = 0, sizes.sram - 1 do written.sram[a] = true end
  end
  local seen, hits, lines = {}, 0, 0
  local MAX_LINES = 4000
  local frame = 0

  local function pcNow()
    local st = emu.getState()
    frame = st["ppu.frameCount"] or frame
    return ((st["cpu.k"] or 0) << 16) | (st["cpu.pc"] or 0)
  end

  local function onRead(ram)
    local w = written[ram]
    return function(addr, value)
      if w[addr] then return end
      local pc = pcNow()
      local key = ram .. addr .. ":" .. pc
      hits = hits + 1
      local n = (seen[key] or 0) + 1
      seen[key] = n
      if n == 1 and lines < MAX_LINES then
        lines = lines + 1
        print(string.format("[rbw] f%d %s $%05X read by $%06X (value $%02X)",
          frame, ram, addr, pc, value or 0))
      end
    end
  end
  local function onWrite(ram)
    local w = written[ram]
    return function(addr) w[addr] = true end
  end

  -- the WRAM port: WMADD ($2181-$2183) and WMDATA ($2180)
  local wmadd = 0
  emu.addMemoryCallback(function(addr, value)
    if addr == 0x2181 then wmadd = (wmadd & 0x1FF00) | value
    elseif addr == 0x2182 then wmadd = (wmadd & 0x100FF) | (value << 8)
    elseif addr == 0x2183 then wmadd = (wmadd & 0x0FFFF) | ((value & 1) << 16)
    else
      written.wram[wmadd] = true
      wmadd = (wmadd + 1) & 0x1FFFF
    end
  end, cb.write, 0x2180, 0x2183)
  emu.addMemoryCallback(function(addr, value)
    if not written.wram[wmadd] then
      local pc = pcNow()
      local key = "wram" .. wmadd .. ":" .. pc
      local n = (seen[key] or 0) + 1
      seen[key] = n
      hits = hits + 1
      if n == 1 and lines < MAX_LINES then
        lines = lines + 1
        print(string.format("[rbw] f%d wram $%05X read by $%06X (value $%02X) via WMDATA",
          frame, wmadd, pc, value or 0))
      end
    end
    wmadd = (wmadd + 1) & 0x1FFFF
  end, cb.read, 0x2180, 0x2180)

  local regs = {}      -- {ram, type, start, end, kind}
  local readers = { wram = onRead("wram"), sram = onRead("sram") }
  local writers = { wram = onWrite("wram"), sram = onWrite("sram") }

  local function ranges(ram)
    local w, size = written[ram], sizes[ram]
    local out = {}
    for b = 0, size - 1, BLOCK do
      local open = false
      for a = b, b + BLOCK - 1 do
        if not w[a] then open = true; break end
      end
      if open then
        local last = out[#out]
        if last and last[2] == b - 1 then last[2] = b + BLOCK - 1
        else out[#out + 1] = { b, b + BLOCK - 1 } end
      end
    end
    -- merge the closest neighbours until the list fits
    while #out > RBW_MAX_RANGES do
      local best, gap = 1, math.huge
      for i = 1, #out - 1 do
        local g = out[i + 1][1] - out[i][2]
        if g < gap then best, gap = i, g end
      end
      out[best][2] = out[best + 1][2]
      table.remove(out, best + 1)
    end
    return out
  end

  local function recut()
    for _, r in ipairs(regs) do
      emu.removeMemoryCallback(r.ref, r.kind, r.s, r.e, emu.cpuType.snes, r.t)
    end
    regs = {}
    for _, ram in ipairs({ "wram", "sram" }) do
      if live[ram] then
        local t = types[ram]
        local rs = ranges(ram)
        if #rs == 0 then live[ram] = false end
        for _, r in ipairs(rs) do
          regs[#regs + 1] = { kind = cb.read, s = r[1], e = r[2], t = t,
            ref = emu.addMemoryCallback(readers[ram], cb.read, r[1], r[2], emu.cpuType.snes, t) }
          regs[#regs + 1] = { kind = cb.write, s = r[1], e = r[2], t = t,
            ref = emu.addMemoryCallback(writers[ram], cb.write, r[1], r[2], emu.cpuType.snes, t) }
        end
      end
    end
  end
  recut()

  local lastHits = 0
  local ticks = 0
  emu.addEventCallback(function()
    ticks = ticks + 1
    if ticks % RBW_RECUT == 0 then
      frame = emu.getState()["ppu.frameCount"] or frame
      recut()
      if ticks % (RBW_RECUT * 32) == 0 or hits ~= lastHits then
        local open = { wram = 0, sram = 0 }
        for _, ram in ipairs({ "wram", "sram" }) do
          local w = written[ram]
          for a = 0, sizes[ram] - 1 do if not w[a] then open[ram] = open[ram] + 1 end end
        end
        print(string.format("[rbw] f%d unwritten wram=%d sram=%d, reads of unwritten bytes so far %d (%d callbacks)",
          frame, open.wram, open.sram, hits, #regs))
        lastHits = hits
      end
    end
  end, emu.eventType.endFrame)
  print(string.format("[rbw] watching wram%s from power-on", live.sram and " and sram" or ""))
end
