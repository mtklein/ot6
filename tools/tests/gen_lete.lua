-- gen_lete.lua -- from banon_joined.mss (map 112, the passage out of the
-- Returner Hideout) onto the Lete River map, one tile from the raft.
-- Generates one state:
--   lete_river.mss  map 113 (30,50), controllable, with the raft's boarding
--                   trigger at (31,51) unfired.  This is the entry point
--                   gen_scenario rides from, and the fixture to start from
--                   when studying the river or the vanilla loop.

-- Map 112 has two entrances: (7,42) -> map 110 and (8,60) -> map 113.
-- BFS knows nothing about entrance triggers, so the plan south is checked
-- against (7,42) before a step is taken.
--
-- playBattles="tactical": BANON is in the party, and his death here goes
-- to LoseBattle (game over), not a retry, so battles are fought rather
-- than fled or blind-cleared.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/banon_joined.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function seq(steps) return H.cond(function() return true end, steps) end

local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end
local function settleField(dstMap, maxF)
  return seq({
    H.waitFrames(90),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), maxF or 12000, { playBattles = "tactical" }),
    H.waitFrames(30),
  })
end

local DD = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 },
             right = { 1, 0 }, upleft = { -1, -1 }, upright = { 1, -1 },
             downleft = { -1, 1 }, downright = { 1, 1 } }
local function planAvoids(tx, ty, bad, what)
  return H.cond(function() return true end, {
    H.waitUntil(function() return H.bfsPath(tx, ty) ~= nil end,
                900, what .. ": a path exists (45f poll)", 45),
    H.call(function()
    local p = H.bfsPath(tx, ty)
    H.assertEq(p ~= nil, true, what .. ": a path exists")
    local x, y, hx, hy = H.fieldX(), H.fieldY(), nil, nil
    for _, d in ipairs(p) do
      x, y = x + DD[d][1], y + DD[d][2]
      for _, b in ipairs(bad) do
        if x == b[1] and y == b[2] then hx, hy = x, y end
      end
    end
    H.log(string.format("%s: %d steps, clean: %s", what, #p, tostring(hx == nil)))
    H.assertEq(hx == nil, true, what .. ": plan avoids the other entrance" ..
      (hx and string.format(" (hits %d,%d)", hx, hy) or ""))
  end),
  })
end

H.run({ maxFrames = 40000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 112, "booted on map 112")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(sw(0x0018), 1, "$0018 set -- the raft will board (_cb059f)")
    H.assertEq(sw(0x001A), 0, "$001A clear -- the river has not been run")
    H.assertEq((H.readByte(0x185e) & 0x07) ~= 0, true, "BANON in the party")
    H.log(string.format("[booted] map=%d (%d,%d)", map(), H.fieldX(), H.fieldY()))
  end),

  planAvoids(8, 60, { { 7, 42 } }, "map 112 -> the river door"),
  H.logStep(function()
    return string.format("cross: (%d,%d) -> (8,60) -> map 113 (30,50)",
      H.fieldX(), H.fieldY())
  end),
  H.navTo(8, 60, { maxFrames = 20000, playBattles = "tactical", arrive = function()
    return map() ~= 112
  end }),
  H.release(),
  settleField(113),
  H.call(function()
    H.assertEq(map(), 113, "on map 113, THE LETE RIVER")
    H.assertEq(H.fieldX(), 30, "at the arrival tile x=30")
    H.assertEq(H.fieldY(), 50, "at the arrival tile y=50")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    -- the boarding trigger is (31,51); it has not fired, which is what
    -- makes this an entry point
    H.assertEq(sw(0x01B5), 0,
      "$01B5 clear -- _cb059f's re-entry guard is unarmed, the raft is unboarded")
    H.assertEq(sw(0x0019), 0, "$0019 clear -- the ride has not started")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d status1=%02X",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11), H.readByte(base + 20)))
      end
    end
    H.log(string.format("[lete_river] f%d map=%d (%d,%d) antidote=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), H.invCountOf(0xF2)))
    H.screenshot("lete_river")
  end),

  -- The last stop before the river, which is long, forced and full of
  -- battles.  Anything not repaired here is carried into it.
  H.fieldCare({ tag = "care before the river", threshold = 0.85 }),
  H.call(function()
    -- The exit contract: nobody dead, petrified, zombie, poisoned, or at
    -- or below max HP / 8.
    H.assertPartyStanding("lete_river exit")
  end),
  H.saveState("lete_river.mss"),
  H.logStep(function()
    return string.format("lete_river generated at frame %d", H.frame)
  end),
})
