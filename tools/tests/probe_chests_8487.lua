-- probe_chests_8487.lua -- walkability around the six chests on maps 84 and 87
--   map 84: 500 gil (7,52) b26, 1500 gil (21,56) b27, 1000 gil (12,55) b28,
--           empty (22,55) b29
--   map 87: RegalCutlass (47,33) b34, Heavy Shld (48,33) b35
-- Boots celes_freed (gen_tunnelarmr's own boot), takes the same two walk-on
-- entrances the generator takes ((57,13) -> 83, (45,12) -> 84 (8,57)),
-- winds the clock so the (15,51) passage to 87 opens, and dumps canStep
-- grids plus bfsPath answers for the candidate stand tiles.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

local function dump(CX, CY, tag)
  for y = CY - 4, CY + 4 do
    local row = {}
    for x = CX - 5, CX + 5 do
      local r = H.canStep(x, y - 1, "down") or H.canStep(x, y + 1, "up")
        or H.canStep(x - 1, y, "right") or H.canStep(x + 1, y, "left")
      row[#row + 1] = (x == CX and y == CY) and "C" or (r and "." or "#")
    end
    H.log(string.format("[walk %s] y=%2d x=%d.. %s", tag, y, CX - 5,
      table.concat(row)))
  end
end

local function paths(list, tag)
  for _, t in ipairs(list) do
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
  H.loadState("build/states/celes_freed.mss.lua"),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 1000, "ctl", 5),
  H.call(function()
    H.log(string.format("[probe] boot map=%d (%d,%d)", map(),
      H.fieldX(), H.fieldY()))
  end),
  -- (57,13) is a same-map warp to the corridor half of map 83; arrival is
  -- the destination tile (35,14), the generator's own rule
  H.navTo(57, 13, { maxFrames = 12000, playBattles = "flee",
    arrive = function() return H.fieldX() == 35 and H.fieldY() == 14 end }),
  H.release(), H.waitFrames(30),
  H.call(function() H.assertEq(map(), 83, "on the corridor, map 83") end),
  H.navTo(45, 12, { maxFrames = 12000, playBattles = "flee",
    arrive = mapChanged() }),
  H.release(), H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 84, "on the clock map, map 84")
    H.log(string.format("[probe] map 84 at (%d,%d)", H.fieldX(), H.fieldY()))
    dump(7, 52, "84-gil500-7,52")
    dump(12, 55, "84-gil1000-12,55")
    dump(21, 56, "84-gil1500-21,56 empty-22,55")
    paths({ { 7, 51 }, { 7, 53 }, { 6, 52 }, { 8, 52 },
            { 12, 54 }, { 11, 55 }, { 13, 55 }, { 12, 56 },
            { 21, 55 }, { 20, 56 }, { 21, 57 }, { 22, 56 }, { 22, 54 },
            { 23, 55 } }, "84")
  end),
  -- wind the clock so the 87 passage opens (the generator's own step)
  H.navTo(18, 49, { maxFrames = 12000, playBattles = "flee" }),
  (function()
    local ph = 0
    return H.driveUntil(function() return sw(0x010D) == 1 end, 1200, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        if H.readByte(0x087f + H.readWord(0x0803)) ~= 0 then
          H.setPad({ up = true }); return
        end
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, "wind the clock ($010D)")
  end)(),
  H.release(), H.waitFrames(30),
  H.navTo(15, 51, { maxFrames = 12000, playBattles = "flee",
    arrive = mapChanged() }),
  H.release(), H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 87, "through the clock passage, map 87")
    H.log(string.format("[probe] map 87 at (%d,%d)", H.fieldX(), H.fieldY()))
    dump(47, 33, "87-cutlass-47,33 shield-48,33")
    paths({ { 47, 34 }, { 48, 34 }, { 46, 33 }, { 49, 33 },
            { 47, 32 }, { 48, 32 } }, "87")
  end),
})
