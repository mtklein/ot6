-- shot_mines.lua -- one screenshot of a live mines random-encounter fight at
-- the shipped constants, for eyeball verification (Measurement #5).
--   tools/tests/run.sh tools/tests/shot_mines.lua build/states/shot_mines.log
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/mines_chase.mss.lua"

local function calm(n)
  local cnt = 0
  return function()
    cnt = (H.hasControl() and H.tileAligned()) and cnt + 1 or 0
    return cnt >= n
  end
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(calm(20), 1200, "field control"),
  -- pace the two-tile walk at map entry until a battle starts loading
  H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
    H.call(function()
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
      local x = H.fieldX()
      H.setPad({ [(x >= 78) and "left" or "right"] = true })
    end),
    H.waitFrames(1),
  }, "encounter fires"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 1200, "battle active", 30),
  H.waitFrames(300),                 -- settle past the window-open animation
  H.call(function()
    local sp = {}
    for slot = 0, 5 do
      if (H.readByte(0x3aa8 + slot*2) & 1) == 1 then
        sp[#sp+1] = string.format("s%d:sp%04X:hp%d:sh%d/%d", slot,
          H.readWord(0x57c0 + slot*2), H.readWord(0x3bfc + slot*2),
          H.readByte(0x3e40 + slot*2), H.readByte(0x3e40 + slot*2 + 1))
      end
    end
    H.log("mines fight: knob_hp=" .. string.format("%02x", H.readRomByte(0x300173))
      .. " knob_shield=" .. string.format("%02x", H.readRomByte(0x30033c)))
    H.log("formation: " .. table.concat(sp, "  "))
    H.screenshot("shot_mines")
  end),
})
