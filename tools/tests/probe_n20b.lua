-- probe_n20b.lua -- why is the (53,8) perch isolated?  Dump the movement
-- model's view: prop bytes, exit bits, object-map occupancy around it.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end

H.run({ maxFrames = 30000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/kefka_won.mss.lua"),
  H.waitFrames(30),
  H.navTo(67, 26, { arrive = function() return map() == 20 end,
                    maxFrames = 12000 }),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end,
    1200, "landed", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("at (%d,%d) map %d z=%d", H.fieldX(), H.fieldY(),
      map(), H.readByte(0x00b2) & 3))
    for y = 6, 12 do
      local row = {}
      for x = 48, 58 do
        local t = H.maptile(x, y)
        local p1 = H.readByte(0x7E7600 + t)
        local p2 = H.readByte(0x7E7700 + t)
        local ob = H.readByte(0x7E2000 + (y & 0xFF) * 256 + (x & 0xFF))
        row[#row + 1] = string.format("%02X/%02X/%02X%s", p1, p2 & 0x0F,
          ob & 0x80, (ob & 0x80) == 0 and "*" or " ")
      end
      H.log(string.format("y=%2d  %s", y, table.concat(row, " ")))
    end
    for _, mv in ipairs({ "up", "down", "left", "right" }) do
      H.log(string.format("canStep(53,8,%s)=%s", mv,
        tostring(H.canStep(53, 8, mv))))
    end
  end),
})
