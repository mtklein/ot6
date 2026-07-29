-- probe_sprdata.lua -- who writes w7e80db (monster sprite data / obj palette
-- number) during the doorstep guard fight, and what the formation actually
-- looks like.  #48 scratch probe, not a suite test.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local writes = {}

H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.call(function()
    emu.addMemoryCallback(function(addr, value)
      if #writes >= 200 then return end
      if (addr - 0x7E80DB) % 2 ~= 0 then return end   -- palette bytes only
      local s = emu.getState()
      writes[#writes + 1] = string.format("f%d %02X/%04X [%04X]=%02X",
        H.frame, s["cpu.k"] or 0, s["cpu.pc"] or 0, addr & 0xFFFF, value)
    end, emu.callbackType.write, 0x7E80DB, 0x7E80E6)
  end),
  H.waitFrames(400),
  H.call(function()
    local t = {}
    for s = 0, 5 do
      t[#t + 1] = string.format(
        "s%d present=%02X id=%04X db=%02X db+1=%02X 8117=%04X 810b=%02X",
        s, H.readByte(0x3AA8 + s * 2), H.readWord(0x3F46 + s * 2),
        H.readByte(0x80DB + s * 2), H.readByte(0x80DC + s * 2),
        H.readWord(0x8117 + s * 2), H.readByte(0x810B + s * 2))
    end
    for _, line in ipairs(t) do H.log("formation " .. line) end
    H.log(string.format("8123 palette list: %04X %04X %04X %04X %04X %04X",
      H.readWord(0x8123), H.readWord(0x8125), H.readWord(0x8127),
      H.readWord(0x8129), H.readWord(0x812B), H.readWord(0x812D)))
    H.log("shown $201e = " .. string.format("%02X", H.readByte(0x201E)))
    for _, line in ipairs(writes) do H.log("write " .. line) end
  end),
  H.logStep(function() return "probe_sprdata complete" end),
})
