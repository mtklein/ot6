-- probe_opera_dance5.lua -- boot aria_postfork (fast), dump ALL 16 field objects
-- unconditionally over time to locate Draco (NPC_4) and the guests, and test
-- whether the lib's own bfsPath/navTo can reach flowers (12,19) and balcony (8,9).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local STRIDE=0x29
local function ovis(i) return H.readByte(0x0867 + i*STRIDE) end
local function ox(i) return H.readWord(0x086a + i*STRIDE) >> 4 end
local function oy(i) return H.readWord(0x086d + i*STRIDE) >> 4 end
local function oface(i) return H.readByte(0x087f + i*STRIDE) end
local function omove(i) return H.readByte(0x087c + i*STRIDE) end
local function dumpAll(tag)
  H.log(string.format("[all %s] f%d map=%d CELES(%d,%d) z=%d | 57=%d 111=%d 1F0=%d 1F1=%d 1F2=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
    sw(0x0057), sw(0x0111), sw(0x01F0), sw(0x01F1), sw(0x01F2)))
  for i=0,15 do
    H.log(string.format("   obj#%2d vis=$%02x (%3d,%3d) face=%d move=$%02x", i, ovis(i), ox(i), oy(i), oface(i), omove(i)))
  end
end
local function pathlog(tx,ty,label)
  local p = H.bfsPath(tx,ty)
  if not p then H.log(string.format("[bfs] %s (%d,%d): NO PATH", label, tx, ty)); return end
  H.log(string.format("[bfs] %s (%d,%d): %d steps: %s", label, tx, ty, #p, table.concat(p," ")))
end

H.run({ maxFrames = 6000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/aria_postfork.mss.lua"),
  H.waitFrames(30),
  H.call(function() H.assertEq(map(),236,"boot 236"); dumpAll("t30") end),
  H.waitFrames(90),
  H.call(function() dumpAll("t120") end),
  H.call(function()
    H.log(string.format("[pos] CELES z=%d at (%d,%d)", H.readByte(0x00b2)&3, H.fieldX(), H.fieldY()))
    pathlog(12,19,"flowers")
    pathlog(8,9,"balcony")
    pathlog(12,14,"draco-tile")
    pathlog(11,20,"basin-mid")
  end),
  H.logStep(function() return "dance5 dump done" end),
})
