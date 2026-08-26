-- probe_srmboot: boot with the player's in-game save injected into SRAM,
-- drive the title into Continue, and screenshot where the save puts us.
local H = dofile("tools/tests/lib/ot6.lua")
local SRM = "build/states/playthrough_srm.mss.lua"

H.run({ maxFrames = 20000 }, {
  -- save slots live at cpu $30:6000-$7fff on hirom
  H.waitFrames(5),
  H.call(function()
    local b64 = H.resolveStateB64(SRM)
    local data = H.b64decode(b64)
    for i = 1, #data do
      emu.write(0x306000 + i - 1, string.byte(data, i), emu.memType.snesMemory)
    end
    H.log("injected " .. #data .. " save bytes into sram")
  end),
  H.waitFrames(350),
  H.call(function() H.screenshot("srmboot_title") end),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.call(function() H.screenshot("srmboot_select") end),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.call(function() H.screenshot("srmboot_loaded_1") end),
  H.waitFrames(600),
  H.call(function()
    H.screenshot("srmboot_loaded_2")
  end),
  -- confirm "This data?" and land on the field
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitFrames(400),
  H.call(function()
    H.screenshot("srmboot_field")
    H.log(string.format("end: battleLoad=%s", tostring(H.battleLoadStarted())))
  end),
})
