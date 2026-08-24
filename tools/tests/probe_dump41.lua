-- probe_dump41.lua -- dump mine 41's live tile props (p1 at $7E7600,
-- p2/exit bits at $7E7700, via the BG1 tilemap) so the top-corridor gap
-- (x~66..107 at y~10-14) can be read instead of guessed (#133 Mog).
local H = dofile("tools/tests/lib/ot6.lua")
local function sw(bit) return (H.readByte(0x1E80 + (bit >> 3)) >> (bit & 7)) & 1 end
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
H.run({ maxFrames = 30000 }, {
  H.loadState("build/states/wob_chase23C.mss.lua"),
  H.waitFrames(8),
  H.navTo(27, 51, { maxFrames = 9000, playBattles = "flee",
    arrive = function() return mapIs(20) end }),
  H.driveUntil(function() return mapIs(20) end, 900,
    { H.call(function() H.setPad({ down = true }) end) }, "to town"),
  H.waitFrames(60),
  H.navTo(15, 57, { maxFrames = 12000, playBattles = "flee" }),
  H.driveUntil(function() return sw(0x1F0) == 1 end, 900, {
    H.call(function() H.setPad({ up = true, a = true }) end),
  }, "wall opens"),
  H.release(), H.waitFrames(60),
  H.driveUntil(function() return mapIs(41) end, 1500, {
    H.call(function() H.setPad({ up = true }) end),
  }, "into 41"),
  H.waitFrames(60),
  H.call(function()
    local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
    H.log(string.format("map 41 masks xm=%02X ym=%02X", xm, ym))
    local function p(base, x, y)
      local t = H.readByte(0x7F0000 + (y & ym) * 256 + (x & xm))
      return H.readByte(base + t)
    end
    -- the whole map, full hex, plus the NPC-block map
    for y = 0, ym do
      local r1, r2, r3 = {}, {}, {}
      for x = 0, xm do
        r1[#r1+1] = string.format("%02x", p(0x7E7600, x, y))
        r2[#r2+1] = string.format("%02x", p(0x7E7700, x, y))
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
