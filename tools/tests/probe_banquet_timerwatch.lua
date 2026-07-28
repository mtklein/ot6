-- probe_banquet_timerwatch.lua -- measurement instrument behind
-- probe_banquet_timer: phase A found the LIVE timer block ($1188-$119F)
-- reading flags=$07 count=0 after the real Save UI ran.  This variant
-- stages the same live timer, drives the same save, and hangs write
-- callbacks over the timer block (both the $7E bank address and the
-- bank-$00 mirror) logging every writer PC and value.  NOT a suite test.
-- (Caveat per HANDOFF trap 1: block moves/DMA are invisible to Mesen
-- write callbacks -- a silent clobber here means "sample, don't
-- watchpoint" and this probe also samples each menu frame.)
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local STAGE = 5400
local function timerCount() return H.readWord(0x1189) end
local function sram(off) return emu.read(off, emu.memType.snesMemory) end

local writes = 0
local hits = {}   -- ["k/pc addr"] = {count, lastValue}
local function watch(lo, hi, tag)
  emu.addMemoryCallback(function(addr, value)
    local s = emu.getState()
    writes = writes + 1
    local k = string.format("%s pc=%02X/%04X addr=%06X",
      tag, s["cpu.k"] or -1, s["cpu.pc"] or -1, addr)
    local h = hits[k] or { 0, -1 }
    h[1] = h[1] + 1; h[2] = value or -1
    hits[k] = h
  end, emu.callbackType.write, lo, hi, nil, emu.memType.snesMemory)
end
local function dumpHits(label)
  H.log("[hits] " .. label)
  for k, h in pairs(hits) do
    H.log(string.format("  %s n=%d last=%02X", k, h[1], h[2]))
  end
  hits = {}
end

local lastSample = -1

H.run({ maxFrames = 30000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000, "world", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    H.writeByte(0x1188, 0x72)
    H.writeWord(0x1189, STAGE)
    H.writeByte(0x118B, 0x96)
    H.writeByte(0x118C, 0x8A)
    H.writeByte(0x118D, 0x02)
    watch(0x7E1188, 0x7E119F, "hi")
    watch(0x001188, 0x00119F, "lo")
    H.log("[stage] watchers armed, timer=" .. timerCount())
  end),
  -- straight into the menu + save (same drive as phase A)
  H.repeatN(3, { H.pressButtons({ "x" }, 6), H.waitFrames(50) }),
  H.waitUntil(function() return H.readByte(0x59) ~= 0 end, 500, "menu", 5),
  H.call(function()
    dumpHits("boot -> menu open (expect DecTimersMenuBattle ticks only)")
    emu.write(0x307ff0, 0x00, emu.memType.snesMemory)
    H.writeByte(ZMENUSTATE, 0x13)
  end),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x14 end,
    300, "save-slot selection", 5),
  H.call(function()
    H.writeByte(0x4b, 2); H.writeWord(0x95, 0)
    hits = {}
  end),
  H.pressButtons({ "a" }, 4),
  -- per-frame sampler: catch a silent (block-move) clobber between frames
  (function()
    return H.driveUntil(function() return sram(0x307ff0) == 3 end, 1500, {
      H.call(function()
        local c = timerCount()
        if lastSample >= 0 and (c > lastSample or lastSample - c > 4)
           and not (lastSample == 0 and c == 0) then
          H.log(string.format("[sample] counter jumped %d -> %d zstate=%02X",
            lastSample, c, H.readByte(ZMENUSTATE)))
        end
        lastSample = c
        local ph = (H.vars.ph or 0) + 1; H.vars.ph = ph
        H.setPad(ph % 24 < 4 and { a = true } or {})
      end),
    }, "save via watched menu")
  end)(),
  H.release(),
  H.waitFrames(90),
  H.call(function()
    dumpHits("slot select -> save confirmed")
    H.log(string.format("[after] flags=%02X count=%d writes=%d sramCount=%d",
      H.readByte(0x1188), timerCount(), writes,
      sram(0x307400 + 0x9A8 + 1) + 256 * sram(0x307400 + 0x9A8 + 2)))
  end),
})
