-- probe_veldt_map.lua -- dump world-0 walkability for the Veldt/Crescent
-- region (x 195..235, y 100..155) so the gau->trench legs can be routed.
-- Boots falls_done, exits the shore (world module loads the map into
-- $7F0000), then renders worldPassable as ascii.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/falls_done.mss.lua"

H.run({ maxFrames = 20000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.navTo(8, 14, { maxFrames = 6000, arrive = function()
    return H.worldMode() end }),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 3000, "world live", 5),
  H.call(function()
    H.log(string.format("party at (%d,%d)", H.worldX(), H.worldY()))
    for y = 100, 155 do
      local row = {}
      for x = 195, 235 do
        if x == H.worldX() and y == H.worldY() then row[#row + 1] = "@"
        elseif x == 220 and y == 115 then row[#row + 1] = "M"  -- Mobliz
        elseif x == 214 and y == 148 then row[#row + 1] = "C"  -- Crescent
        else row[#row + 1] = H.worldPassable(x, y) and "." or "#"
        end
      end
      H.log(string.format("y=%3d %s", y, table.concat(row)))
    end
  end),
})
