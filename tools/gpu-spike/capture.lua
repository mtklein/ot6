-- @manual gpu-spike oracle capture (#392): records a battle segment for the
-- GPU 65816 replay.  Boots first_battle, lets it settle, then from the first
-- interrupt taken after SETTLE frames records, for SEG_FRAMES NMIs:
--   * the starting machine at that interrupt boundary (WRAM, SRAM, CPU regs,
--     every getState key as text),
--   * every CPU-bus read and write of the I/O pages ($2100-$21FF,
--     $4000-$43FF in banks $00-$3F/$80-$BF) with the instruction count it
--     happened in and its value,
--   * every interrupt taken (NMI/IRQ) with the instruction count it followed,
--     the CPU cycle count, the CPU registers, and 128 per-1KB WRAM hashes,
--   * the PC of every instruction for the first PC_FRAMES frames.
-- Inputs: press A for 4 frames every 16 (picks Fight and a target for each
-- ready member), the pad the game saw is in the $4218/$4219 reads.
-- Output: [b64:gpu_init.bin], [b64:gpu_trace.bin] blobs; formats in replay.h.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/first_battle.mss.lua"
local SETTLE = 60
local SEG_FRAMES = 600 -- GPU_SEG_FRAMES
local PC_FRAMES = 30 -- GPU_PC_FRAMES

local armed, started, done = false, false, false
local icount, nmis = 0, 0
local ev = {}          -- packed records, in time order
local pcs = {}         -- packed u32 PCs
local init = nil
local WR = emu.memType.snesWorkRam

local function wramHashes()
  -- 128 blocks of 1KB; per block FNV-1a over little-endian u32 words.
  local out = {}
  for b = 0, 127 do
    local h = 2166136261
    local base = b * 1024
    for o = 0, 1020, 4 do
      h = ((h ~ emu.read32(base + o, WR, false)) * 16777619) & 0xffffffff
    end
    out[#out + 1] = string.pack("<I4", h)
  end
  return table.concat(out)
end

local function cpuRegs()
  local s = emu.getState()
  return string.pack("<I2I2I2I2I2I1I1I2I1I1I8",
    s["cpu.a"] or 0, s["cpu.x"] or 0, s["cpu.y"] or 0, s["cpu.sp"] or 0, s["cpu.d"] or 0,
    s["cpu.dbr"] or 0, s["cpu.k"] or 0, s["cpu.pc"] or 0, s["cpu.ps"] or 0,
    s["cpu.emulationMode"] and 1 or 0, s["cpu.cycleCount"] or 0)
end

local function snapshot()
  local w = {}
  for o = 0, 0x1FFFC, 4 do w[#w + 1] = string.pack("<I4", emu.read32(o, WR, false)) end
  local sramSize = emu.getMemorySize(emu.memType.snesSaveRam)
  local sr = {}
  for o = 0, sramSize - 1 do sr[#sr + 1] = string.char(emu.read(o, emu.memType.snesSaveRam)) end
  local s = emu.getState()
  local keys = {}
  for k, v in pairs(s) do keys[#keys + 1] = k .. "=" .. tostring(v) end
  table.sort(keys)
  local text = table.concat(keys, "\n")
  local regs = cpuRegs()
  return "GPUI" .. string.pack("<I4I4I4", #regs, sramSize, #text) .. regs ..
         table.concat(w) .. table.concat(sr) .. text
end

local function finish()
  done = true
  H.emitBlob("gpu_init.bin", init)
  local hdr = string.pack("<I4I4I4", #ev, #pcs, PC_FRAMES)
  H.emitBlob("gpu_trace.bin", "GPUT" .. hdr .. table.concat(pcs) .. table.concat(ev))
  H.log(string.format("capture done: %d interrupts-frames, %d instructions, %d records",
    nmis, icount, #ev))
end

local function onInterrupt(kind)
  return function()
    if done then return end
    if armed and not started and kind == 1 then
      started = true
      icount = 0
      init = snapshot()
      H.log("capture started at frame " .. emu.getState()["ppu.frameCount"])
      return
    end
    if not started then return end
    if kind == 1 then nmis = nmis + 1 end
    ev[#ev + 1] = string.pack("<BI4", kind == 1 and 0x4E or 0x49, icount) .. cpuRegs() .. wramHashes()
    if nmis >= SEG_FRAMES then finish() end
  end
end

emu.addEventCallback(onInterrupt(1), emu.eventType.nmi)
emu.addEventCallback(onInterrupt(2), emu.eventType.irq)

emu.addMemoryCallback(function(addr)
  if started and not done then
    icount = icount + 1
    if nmis < PC_FRAMES then pcs[#pcs + 1] = string.pack("<I4", addr) end
  end
end, emu.callbackType.exec, 0x000000, 0xFFFFFF)

local function ioRead(addr, value)
  if started and not done then ev[#ev + 1] = string.pack("<BI4I4B", 0x52, icount, addr, value) end
end
local function ioWrite(addr, value)
  if started and not done then ev[#ev + 1] = string.pack("<BI4I4B", 0x57, icount, addr, value) end
end
for _, bank in ipairs((function()
  local t = {}
  for b = 0x00, 0x3F do t[#t + 1] = b end
  for b = 0x80, 0xBF do t[#t + 1] = b end
  return t end)()) do
  local base = bank << 16
  emu.addMemoryCallback(ioRead, emu.callbackType.read, base | 0x2100, base | 0x21FF)
  emu.addMemoryCallback(ioRead, emu.callbackType.read, base | 0x4000, base | 0x43FF)
  emu.addMemoryCallback(ioWrite, emu.callbackType.write, base | 0x2100, base | 0x21FF)
  emu.addMemoryCallback(ioWrite, emu.callbackType.write, base | 0x4000, base | 0x43FF)
end

H.run({ maxFrames = SEG_FRAMES * 2 + 2000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(SETTLE),
  H.call(function() armed = true end),
  H.repeatN(math.ceil((SEG_FRAMES + 40) / 16), {
    H.pressButtons({ "a" }, 4),
    H.waitFrames(12),
  }),
  H.call(function()
    if not done then error("capture did not finish: " .. nmis .. " frames", 0) end
    H.screenshot("gpu_capture_end")
  end),
})
