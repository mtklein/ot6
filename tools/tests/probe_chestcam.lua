-- probe_chestcam.lua -- measures the camera formula: BG1 scroll = partyPx
-- - (112,112), clamped at 0, view 256x224.  The $5B/$5F triplets decode
-- little-endian with the low byte as subpixel (value >> 8 = pixels); the
-- scroll shadows are $5B (H) and $5F (V).
local H = dofile("tools/tests/lib/ot6.lua")

local function camLog(tag, cx, cy)
  local px = H.readWord(0x086a + H.readWord(0x0803))
  local py = H.readWord(0x086d + H.readWord(0x0803))
  local h = { H.readByte(0x5B), H.readByte(0x5C), H.readByte(0x5D) }
  local v = { H.readByte(0x5F), H.readByte(0x60), H.readByte(0x61) }
  H.log(string.format(
    "[chestcam] %s map=%d tile=(%d,%d) partypx=(%d,%d) chest=(%d,%d) "
    .. "rawH=%02x %02x %02x rawV=%02x %02x %02x",
    tag, H.mapId() & 0x1ff, H.fieldX(), H.fieldY(), px, py, cx, cy,
    h[1], h[2], h[3], v[1], v[2], v[3]))
  H.screenshot("chestcam_" .. tag)
end

local function camReport(tag, cx, cy)
  return H.call(function() camLog(tag, cx, cy) end)
end

H.run({ maxFrames = 120000 }, {
  -- A. Flame Sabre.  The route's near tiles ((10,33) and its band) are
  -- CONVEYOR-transit tiles, not walkable ground, so navTo has no path to
  -- them; the chute ride (x[10..28] y[3..45]) covers them instead.  Rides
  -- the chute (mrf_entry -> the (19,25) chute) and reads the camera
  -- mid-slide over two row bands: y 22..28 (the chest's own rows) and
  -- y 31..35 (the (10,33) claim).
  H.loadState("build/states/mrf_entry.mss.lua"),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 1000, "control A", 5),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 262, "mrf_entry sits on map 262")
  end),
  H.navTo(19, 22, { maxFrames = 30000, playBattles = "tactical" }),
  (function()
    local shot1, shot2 = false, false
    return H.driveUntil(function()
      return H.fieldY() >= 44 and H.tileAligned()
    end, 6000, {
      H.call(function()
        local y = H.fieldY()
        if not shot1 and y >= 22 and y <= 28 and H.fieldX() <= 13 then
          shot1 = true
          camLog("flamesabre_y" .. y, 3, 25)
        elseif not shot2 and y >= 31 and y <= 35 then
          shot2 = true
          camLog("flamesabre_lo_y" .. y, 3, 25)
        end
        -- pulse DOWN while still on walkable ground above the chute; go
        -- neutral once the slide has the party (y past 25 or control lost).
        if y <= 25 and H.hasControl() then
          H.setPad((H.frame % 8 < 4) and { down = true } or {})
        else
          H.setPad({})
        end
      end),
    }, "the chute ride reaches the lower landing")
  end)(),

})
