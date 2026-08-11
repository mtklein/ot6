-- probe_n20c.lua -- model-vs-engine on post-battle map 20: dump the
-- (49,14) neighborhood's prop bytes, then push raw held directions and see
-- whether the engine moves where the model says wall.
-- Issue #75: playBattles = "tactical" keeps this walk out of the library's
-- monster-dead flag write.  It is intent only -- maps 30 and 20 (Arvis's house, the Narshe streets) draw no random battles (map_prop.dat byte +5
-- bit 7 clear, so the field step handler at ff6/src/field/battle.asm:333-347
-- returns before the roll) -- and "tactical" rather than "flee" because the
-- only battle that could reach the option there is an unscripted surprise.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end

local function dumpat(tag)
  local x, y = H.fieldX(), H.fieldY()
  H.log(string.format("[%s] at (%d,%d) map=%d z=%d masks=%02X/%02X",
    tag, x, y, map(), H.readByte(0x00b2) & 3,
    H.readByte(0x0086), H.readByte(0x0087)))
  for yy = y - 2, y + 2 do
    local row = {}
    for xx = x - 3, x + 3 do
      local t = H.maptile(xx, yy)
      row[#row + 1] = string.format("%02X:%02X/%02X", t,
        H.readByte(0x7E7600 + t), H.readByte(0x7E7700 + t) & 0x0F)
    end
    H.log(string.format("  y=%2d %s", yy, table.concat(row, " ")))
  end
end

local function push(dir, n)
  return H.cond(function() return true end, {
    H.call(function()
      H.log(string.format("push %s from (%d,%d)", dir, H.fieldX(), H.fieldY()))
    end),
    H.hold({ dir }), H.waitFrames(n or 24), H.release(), H.waitFrames(8),
    H.call(function()
      H.log(string.format("  -> now (%d,%d)", H.fieldX(), H.fieldY()))
    end),
  })
end

H.run({ maxFrames = 20000 }, {
  H.loadState("build/states/kefka_won.mss.lua"),
  H.waitFrames(30),
  H.navTo(55, 35, { arrive = function() return map() == 20 end,
                    maxFrames = 6000, playBattles = "tactical" }),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end,
    1200, "streets", 5),
  H.waitFrames(30),
  H.call(function() dumpat("landing") end),
  push("down"), push("down"), push("left"), push("left"),
  push("down"), push("right"),
  H.call(function() dumpat("after-pushes") end),
})
