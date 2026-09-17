-- @manual
-- probe_sabin_merchant.lua -- DIAGNOSTIC probe for #213's Sabin-scenario
-- Tonic stop.  Boots sabin_world.mss (SABIN alone on the world map at
-- (161,36)), walks into map 115 at (165,35), and logs where map 115's
-- objects stand, which tiles the party can reach, and whether the merchant
-- (npc_prop.asm: {16,12}, spawn $0434, `_cb0b7e` -> shop 39) can be talked
-- to.  gen_sabin_world's first stop read "no path (4,12)->(16,13)" on three
-- seeds; this is the look at the screen that follows.
--
-- Found: map 115 is the yard outside the house.  Obj 16 SHADOW (4,12), obj
-- 17 the dog (3,12), obj 18 the merchant at (8,10) beside the chocobo --
-- not {16,12}; (16,y) is outside the reachable set (x 0..13).  The "east"
-- step's "no path" is that measurement, kept.
--
--   tools/tests/run.sh tools/tests/probe_sabin_merchant.lua
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end

local function dump(tag)
  return H.call(function()
    H.log(string.format("[probe] %s: map=%d (%d,%d) $0434=%d $0169=%d f%d", tag,
      map(), H.fieldX(), H.fieldY(), sw(0x0434), sw(0x0169), H.frame))
    for i = 16, 22 do
      H.log(string.format("[probe] obj %d at (%d,%d)", i, objX(i), objY(i)))
    end
    for y = 0, 20 do
      local row = {}
      for x = 0, 31 do
        row[#row + 1] = (x == H.fieldX() and y == H.fieldY()) and "@"
          or (H.bfsPath(x, y) and "#" or ".")
      end
      H.log(string.format("[probe] y=%2d x0..31 %s", y, table.concat(row)))
    end
    H.screenshot("probe_sabin_merchant_" .. tag)
  end)
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/sabin_world.mss.lua"),
  H.waitFrames(30),
  H.worldNavTo(165, 35, { maxFrames = 12000, playBattles = "tactical",
    arrive = function() return not H.worldMode() and map() == 115 end }),
  H.waitUntil(function()
    return map() == 115 and H.hasControl() and H.tileAligned() and bright() >= 15
  end, 6000, "map 115 control", 5),
  H.waitFrames(60),
  dump("entry"),
  H.navTo(16, 14, { maxFrames = 6000, playBattles = true }),
  dump("east"),
})
