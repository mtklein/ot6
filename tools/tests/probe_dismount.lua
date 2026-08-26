-- probe_dismount.lua -- measures getting off the chocobo. figaro_cleared.mss
-- leaves the party riding one, and InitChoco never writes the on-foot tile
-- registers $E0/$E2 (only InitWorld does, from $1F60), so H.worldX/worldY
-- read 0 and worldNavTo cannot plan a route until the party is on foot.
--
-- Holding B triggers LandAirship, which sets $19=3 (the world's exit
-- trigger), locks input via $1E bit0, and converts the vehicle's mode-7
-- position into a tile pair stored at $1F60/$1F61. The descent then lowers
-- altitude each frame and sets $19 bit2 once grounded, at which point
-- ExitVehicle clears $11FA and reloads the map on foot, and InitWorld reads
-- $1F60 into $E0/$E2.
--
-- The probe also plans (does not walk) the two tier-2 world steps from the
-- landing tile: South Figaro's world entrance (86,111) and Mt. Kolts's
-- (102,100).
local H = dofile("tools/tests/lib/ot6.lua")
local CLEARED = "build/states/figaro_cleared.mss.lua"

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

local function snap(tag)
  H.log(string.format(
    "[%s] f%d $1F64=%04X $11FA=%02X $20=%02X $19=%02X $1E=%02X " ..
    "$E0/$E2=(%d,%d) $DF/$E1=(%d,%d) $1F60/61=(%d,%d) " ..
    "veh $34=%04X $38=%04X -> tile (%d,%d) alt $2D=%04X bright=%d",
    tag, H.frame, H.readWord(0x1f64), H.readByte(0x11fa), H.readByte(0x0020),
    H.readByte(0x0019), H.readByte(0x001e),
    H.readByte(0x00e0), H.readByte(0x00e2),
    H.readByte(0x00df), H.readByte(0x00e1),
    H.readByte(0x1f60), H.readByte(0x1f61),
    H.readWord(0x0034), H.readWord(0x0038),
    (H.readWord(0x0034) >> 4) & 0xFF, (H.readWord(0x0038) >> 4) & 0xFF,
    H.readWord(0x002d), bright()))
end

H.run({ maxFrames = 12000 }, {
  H.loadState(CLEARED),
  H.waitFrames(20),
  H.call(function()
    snap("booted")
    H.assertEq(H.worldMode(), true, "booted on the world map")
    H.assertEq(H.readByte(0x11fa) & 3, 2, "riding the chocobo ($11FA&3=2)")
    H.assertEq(H.readByte(0x0020), 2, "vehicle type $20=2 (chocobo)")
    H.assertEq(H.worldX(), 0, "$E0 really is 0 while riding (InitChoco)")
    H.assertEq(H.worldY(), 0, "$E2 really is 0 while riding (InitChoco)")
    H.screenshot("dismount_riding")
  end),

  -- Hold B and watch the state machine: $19 goes 0 -> 3 -> 6, and then
  -- $11FA drops to 0 as ExitVehicle reloads the map on foot.
  H.hold({ "b" }),
  H.driveUntil(function() return H.readByte(0x0019) ~= 0 end, 120, {
    H.waitFrames(1),
  }, "B sets the exit trigger $19"),
  H.call(function() snap("B seen") end),
  H.driveUntil(function() return H.readByte(0x11fa) & 3 == 0 end, 600, {
    H.call(function()
      if H.frame % 8 == 0 then snap("descending") end
    end),
    H.waitFrames(1),
  }, "$11FA cleared (ExitVehicle ran)"),
  H.release(),
  H.call(function() snap("vehicle byte cleared") end),

  -- Waits for control, full brightness, and alignment, then a margin: a
  -- world module can report control on a black screen mid-cutscene.
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
  end, 900, "on foot, controllable, lit", 5),
  H.waitFrames(30),
  H.call(function()
    snap("on foot")
    H.assertEq(H.worldMode(), true, "still on the world map")
    H.assertEq(H.readByte(0x11fa) & 3, 0, "off the bird ($11FA&3=0)")
    H.assertEq(H.worldX() ~= 0 or H.worldY() ~= 0, true,
      string.format("$E0/$E2 initialised by InitWorld (got %d,%d)",
        H.worldX(), H.worldY()))
    H.assertEq(H.worldX(), H.readByte(0x1f60), "$E0 came from $1F60")
    H.assertEq(H.worldY(), H.readByte(0x1f61), "$E2 came from $1F61")
    H.log(string.format("landing tile passable on foot: %s (prop=%04X)",
      tostring(H.worldPassable(H.worldX(), H.worldY())),
      H.worldTileProp(H.worldX(), H.worldY())))
    H.screenshot("dismount_onfoot")
  end),

  -- Plans (does not walk) both tier-2 steps: the claim checked is that a
  -- path exists.
  H.call(function()
    for _, t in ipairs({ { 86, 111, "South Figaro (map 75)" },
                         { 102, 100, "Mt. Kolts (map 95)" } }) do
      local p = H.worldBfs(t[1], t[2])
      H.log(string.format("plan (%d,%d)->(%d,%d) %s: %s",
        H.worldX(), H.worldY(), t[1], t[2], t[3],
        p and (#p .. " steps") or "NO PATH"))
      H.assertEq(p ~= nil, true, "a world path exists to " .. t[3])
    end
  end),

  -- Positive control: one step, so the check covers the engine moving the
  -- party and not only the register values.
  H.call(function()
    local p = H.worldBfs(86, 111)
    H.log("first planned step is " .. tostring(p and p[1]))
  end),
  H.driveUntil((function()
    local sx, sy
    return function()
      if sx == nil then sx, sy = H.worldX(), H.worldY() end
      return H.worldX() ~= sx or H.worldY() ~= sy
    end
  end)(), 400, {
    H.hold({ "down" }), H.waitFrames(24), H.release(), H.waitFrames(4),
    H.hold({ "right" }), H.waitFrames(24), H.release(), H.waitFrames(4),
    H.hold({ "up" }), H.waitFrames(24), H.release(), H.waitFrames(4),
    H.hold({ "left" }), H.waitFrames(24), H.release(), H.waitFrames(4),
  }, "a real on-foot world step lands"),
  H.release(),
  H.call(function()
    snap("stepped")
    H.log("DISMOUNT PROVEN: hold B, wait for $11FA&3==0, then navigate")
  end),
})
