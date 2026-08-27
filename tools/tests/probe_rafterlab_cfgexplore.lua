-- probe_rafterlab_cfgexplore.lua -- rafter lab: map the Config menu's
-- cursor/state bytes empirically (menu state $26, cursors $4b/$4e, config
-- bytes $1d4d/$1d4e) so a targeted battle-speed/msg-speed driver can be
-- written.  Opens the field menu from rafterlab_dropped (map 238, chase
-- timer NOT armed, so the menu is safe), enters Config, and walks rows
-- pressing left, logging every byte after every press.  Reads + input only.
local H = dofile("tools/tests/lib/ot6.lua")

local function snap(tag)
  H.log(string.format("[cfg] %s f%d $26=%02X $4b=%02X $4e=%02X $1d4d=%02X $1d4e=%02X $1d4f=%02X",
    tag, H.frame, H.readByte(0x26), H.readByte(0x4b), H.readByte(0x4e),
    H.readByte(0x1d4d), H.readByte(0x1d4e), H.readByte(0x1d4f)))
end

local steps = {
  H.loadState("build/states/rafterlab_dropped.mss.lua"),
  H.waitFrames(60),
  H.call(function() snap("boot") end),
  H.driveUntil(function() return H.readByte(0x26) == 0x05 end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "open main menu"),
  H.waitFrames(20),
  H.call(function() snap("main") end),
  H.driveUntil(function()
    return H.readByte(0x26) == 0x05 and H.readByte(0x4b) == 5
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(10) },
    "cursor to Config row"),
  H.call(function() snap("row5") end),
  H.pressButtons({ "a" }, 2),
  H.waitFrames(30),
  H.call(function() snap("entered") end),
}
for row = 1, 9 do
  steps[#steps + 1] = H.call(function() snap("row" .. row .. "-before") end)
  for p = 1, 4 do
    steps[#steps + 1] = H.pressButtons({ "left" }, 2)
    steps[#steps + 1] = H.waitFrames(8)
  end
  steps[#steps + 1] = H.call(function() snap("row" .. row .. "-after-lefts") end)
  steps[#steps + 1] = H.pressButtons({ "down" }, 2)
  steps[#steps + 1] = H.waitFrames(8)
end
steps[#steps + 1] = H.call(function() snap("done") end)
H.run({ maxFrames = 20000 }, steps)
