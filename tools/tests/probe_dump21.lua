-- probe_dump21.lua -- dumps cliff map 21's tile props (p1/$7E7600,
-- p2/$7E7700) and the NPC-block map ($7E2000, bit7 clear = blocked), for
-- the top pocket ((23,10)-(32,10), the doors into 41's closed east
-- corridor).
local H = dofile("tools/tests/lib/ot6.lua")
H.run({ maxFrames = 3000 }, {
  H.loadState("build/states/wob_chase23C.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
    H.log(string.format("map %d masks xm=%02X ym=%02X party=(%d,%d) z=%02X",
      H.mapId() & 0x1ff, xm, ym, H.fieldX(), H.fieldY(), H.readByte(0xb2)))
    local function tile(x, y)
      return H.readByte(0x7F0000 + (y & ym) * 256 + (x & xm))
    end
    for y = 0, ym do
      local r1, r2, r3 = {}, {}, {}
      for x = 0, xm do
        local t = tile(x, y)
        r1[#r1+1] = string.format("%02x", H.readByte(0x7E7600 + t))
        r2[#r2+1] = string.format("%02x", H.readByte(0x7E7700 + t))
        r3[#r3+1] = (H.readByte(0x7E2000 + (y & 0xFF) * 256 + (x & 0xFF)) & 0x80) == 0
          and "X" or "."
      end
      H.log(string.format("p1 y%02d %s", y, table.concat(r1)))
      H.log(string.format("p2 y%02d %s", y, table.concat(r2)))
      H.log(string.format("nb y%02d %s", y, table.concat(r3)))
    end
  end),
  H.logStep(function() return "done" end),
})
