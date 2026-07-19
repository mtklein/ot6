-- probe_dismount.lua -- the measurement instrument for getting OFF the
-- chocobo.  figaro_cleared.mss leaves the party riding one (the submerge
-- scene's `vehicle ... CHOCOBO`), and InitChoco (world/init.asm:402) never
-- writes the on-foot tile registers $E0/$E2 -- only InitWorld does, from
-- $1F60 (init.asm:758-762) -- so H.worldX/worldY read 0 and worldNavTo
-- cannot plan a thing until the party is on its feet.  Everything on rung 2
-- past Figaro depends on undoing that, so it gets measured before it gets
-- used.
--
-- THE DISMOUNT, read out of the source and confirmed here frame by frame:
--   * riding, the world module runs MoveVehicle (world/move.asm:361), whose
--     input handler for $20 == 2 is GetChocoInput (world/ctrl.asm:451).  Its
--     last branch, ctrl.asm:562-563, is `lda $05 / bit #$0080 / jsr
--     LandAirship` -- $05 is the held-button low byte (bit7 = B) and the
--     test is on the HELD state, not an edge, so a multi-frame hold is fine.
--   * LandAirship (world/init.asm:1823) forks on $20 at :1827 and takes the
--     chocobo branch @93d4 (:1868): it sets `$19 = 3` (the world's exit
--     trigger), sets $1E bit0 to lock input out, zeroes the rotation and
--     speed vars -- and, the load-bearing part, converts the VEHICLE's
--     mode-7 position into a tile pair and stores it at $1F60/$1F61
--     (:1878-1888: `lda $34 / lsr4 / and #$00ff / sta $1f60` then
--     `lda $38 / asl4 / and #$ff00 / clc / adc $1f60 / sta $1f60`).
--   * $19=3 alone does NOT exit: the world main loop wants bit2
--     (world_start.asm:224-235, `lda $19 / and #$04 / cmp #$04 / bne`).
--     Bit0 instead runs _ee1c56 (move.asm:695), the descent -- it lowers
--     altitude $2D each frame and only when the bird is on the ground does
--     `$19 = ($19 & $FE) | $04` (:672-677) release the exit.
--   * ExitVehicle (init.asm:1596) then plays DismountChocoAnim, and because
--     $19 ~= $FF takes the reload branch: `stz $11fa` (:1616 -- the vehicle
--     byte, cleared) and `jmp ReloadMap` (:1620).  ReloadMap re-dispatches
--     on $11FA & 3 (:118-126), which is now 0, so this time it is InitWorld
--     -- and InitWorld reads $1F60 into $E0/$E2.
-- So: hold B, wait out the descent, and the party is standing on the tile
-- the bird was over with the registers the navigator needs.
--
-- The probe also plans (does not walk) the two rung-2 world legs from the
-- landing tile, so a route bug shows up here rather than 10000 frames into
-- gen_kolts: South Figaro's world entrance (86,111) and Mt. Kolts's
-- (102,100), both read out of the WoB's own short-entrance block (map 0 of
-- trigger/short_entrance.dat: (86,111)/(85,112)/(86,112)/(85,113) -> map 75
-- (1,28); (102,100) -> map 95 (14,35)).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local CLEARED = "/Users/mtklein/ot6/build/states/figaro_cleared.mss.lua"

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

  -- ===================================================================== --
  -- Hold B and watch the state machine: $19 should go 0 -> 3 (LandAirship)
  -- -> 6 (descent done, bit0 cleared / bit2 set) and then $11FA drop to 0
  -- as ExitVehicle reloads the map on foot.
  -- ===================================================================== --
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

  -- ===================================================================== --
  -- Settle exactly the way route()'s world leg does -- control AND full
  -- brightness AND alignment, then the 30-frame margin.  (A world module
  -- can report control on a black screen mid-cutscene; gen_edgar's header
  -- documents the 5700-frame mint that cost.)
  -- ===================================================================== --
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

  -- ===================================================================== --
  -- Plan both rung-2 legs from here.  Planning only: a path that exists is
  -- the claim being checked, and it costs nothing to check it now.
  -- ===================================================================== --
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

  -- ===================================================================== --
  -- Positive control: one real step, so "the registers look sane" is not
  -- the whole story -- the engine has to actually move the party.
  -- ===================================================================== --
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
