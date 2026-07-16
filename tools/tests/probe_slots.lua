-- probe_slots: inject the player's srm and screenshot all three save
-- slots on the continue screen, to find the furthest-along save (the
-- one out of the mech suits, for balance measurement).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local SRM = "/Users/mtklein/ot6/build/states/playthrough_srm.mss.lua"

H.run({ maxFrames = 20000 }, {
  H.waitFrames(5),
  H.call(function()
    local data = H.b64decode(H.resolveStateB64(SRM))
    for i = 1, #data do
      emu.write(0x306000 + i - 1, string.byte(data, i), emu.memType.snesMemory)
    end
    H.log("injected " .. #data .. " save bytes")
  end),
  H.waitFrames(350),
  -- Start advances title -> the New Game/Continue menu; pick Continue
  H.repeatN(4, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(60),
  H.pressButtons({ "a" }, 8),   -- Continue -> slot list
  H.waitFrames(90),
  H.call(function() H.screenshot("slot_1") end),
  H.pressButtons({ "down" }, 8), H.waitFrames(40),
  H.call(function() H.screenshot("slot_2") end),
  H.pressButtons({ "down" }, 8), H.waitFrames(40),
  H.call(function() H.screenshot("slot_3") end),
  H.pressButtons({ "up" }, 8), H.waitFrames(40),
  H.call(function() H.screenshot("slot_2b") end),
})
