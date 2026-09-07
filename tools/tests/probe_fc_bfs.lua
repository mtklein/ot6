-- probe_fc_bfs.lua -- the BFS's view of the FC landing from the cold-Continue
-- state of `fc-landing-v1` (the party at the SavePoint 394 (7,12)): the tile
-- props, exit bits and object map around the landing, and the two path
-- queries the descent makes.  For comparison with gen_fc_alcove's dump of the
-- SAME area after the scripted deck re-entry, where the BFS found no path.
-- A probe: reads only.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function mapIs(m) return (H.mapId() & 0x3ff) == m end
local function dumpArea(tag, x0, y0, x1, y1)
  -- p1 (7E7600+tile: z/bridge/wall bits), p2 (7E7700+tile: exit bits), and
  -- the object map (7E2000+y*256+x: bit 7 clear = an object stands there)
  H.log(string.format("[%s] $b2=%02X at (%d,%d); area (%d..%d, %d..%d) as p1/p2/obj per tile",
    tag, H.readByte(0x00b2), H.fieldX(), H.fieldY(), x0, x1, y0, y1))
  for y = y0, y1 do
    local row = {}
    for x = x0, x1 do
      local t = H.maptile(x, y)
      row[#row + 1] = string.format("%02X/%02X/%02X", H.readByte(0x7E7600 + t), H.readByte(0x7E7700 + t),
        H.readByte(0x7E2000 + (y & 0xFF) * 256 + (x & 0xFF)))
    end
    H.log(string.format("[%s] y=%2d: %s", tag, y, table.concat(row, " ")))
  end
  H.log(string.format("[%s] bfs (10,17): %s  bfs (19,12): %s", tag,
    H.bfsPath(10, 17) and "path" or "NO PATH", H.bfsPath(19, 12) and "path" or "NO PATH"))
end

H.run({ maxFrames = 20000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return mapIs(394) and H.hasControl() end, 3000, "cold Continue to the landing SavePoint", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function() dumpArea("cold-continue", 3, 10, 12, 18) end),
  H.pressButtons({ "right" }, 12), H.waitFrames(30),
  H.call(function() dumpArea("cold-continue after a step", 3, 10, 12, 18) end),
})
