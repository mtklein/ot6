-- probe: can any point of gen_sabin_doma's walk reach the map-123 copy of
-- the bit-96 X-Potion at (33,34)? Map 124 (the copy the route sees) never
-- returns control, so the only honest pickup would be the 123 copy. This
-- walks the generator's own entry (121 (28,12) -> 123 (51,30)), dumps a
-- wide canStep grid around (33,34), and asks bfsPath from the arrival room
-- and from the two rooms the crawl visits next.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end

local function dump(CX, CY, tag, r)
  r = r or 4
  for y = CY - r, CY + r do
    local row = {}
    for x = CX - r - 2, CX + r + 2 do
      local w = H.canStep(x, y - 1, "down") or H.canStep(x, y + 1, "up")
        or H.canStep(x - 1, y, "right") or H.canStep(x + 1, y, "left")
      row[#row + 1] = (x == CX and y == CY) and "C" or (w and "." or "#")
    end
    H.log(string.format("[walk %s] y=%2d x=%d.. %s", tag, y, CX - r - 2,
      table.concat(row)))
  end
end

local function paths(tag)
  for _, t in ipairs({ { 32, 34 }, { 34, 34 }, { 33, 33 }, { 33, 35 },
                       { 33, 31 }, { 28, 34 } }) do
    local p = H.bfsPath(t[1], t[2])
    H.log(string.format("[path %s] (%d,%d) = %s", tag, t[1], t[2],
      p and ("FOUND len " .. #p) or "nil"))
  end
end

local function mapChanged()
  local m0
  return function()
    m0 = m0 or map()
    return map() ~= m0
  end
end

H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/kefka_done.mss.lua"),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 1500, "ctl", 5),
  H.call(function()
    H.log(string.format("[probe] boot map=%d (%d,%d)", map(),
      H.fieldX(), H.fieldY()))
  end),
  -- the generator's own entry: 121 (28,12) -> 123 (51,30)
  H.navTo(28, 12, { maxFrames = 15000, playBattles = true,
    arrive = mapChanged() }),
  H.release(), H.waitFrames(45),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end,
    1200, "settled on 123", 5),
  H.call(function()
    H.assertEq(map(), 123, "inside Doma Castle, map 123")
    H.log(string.format("[probe] map 123 at (%d,%d)", H.fieldX(), H.fieldY()))
    dump(33, 34, "123-xpotion", 6)
    paths("from arrival room")
  end),
  -- hop the crawl's first door: (48,28) -> (5,25)
  H.navTo(48, 28, { maxFrames = 15000, playBattles = true,
    arrive = function()
      return H.fieldX() <= 10 and H.fieldY() <= 30
    end }),
  H.release(), H.waitFrames(45),
  H.call(function()
    H.log(string.format("[probe] after (48,28) door at (%d,%d)",
      H.fieldX(), H.fieldY()))
    paths("from west room")
  end),
})
