-- gen_kolts_cave.lua -- one crossing past kolts_pool, for the second Mt.
-- Kolts encounter pool, the one most of the mountain uses.

--   kolts_cave.mss   map 96 region P, party in control and tile-aligned.

--   maps 95/96/97   group 61   Cirpius x3 (93.75%), +Tusker in slot 1
--   maps 98/99/102  group 62   Trilium-pair 62.5%, Trilium+Tusker+Cirpius x2
--   map  100        group 63   Brawler-pair / Tusker-pair   <- kolts_pool
--   map  101        group 64   Brawler+Trilium+Vaporite x2 / Tusker-pair

local H = dofile("tools/tests/lib/ot6.lua")

local POOL = "build/states/kolts_pool.mss.lua"

local function map() return H.mapId() & 0x1ff end

local function where(tag)
  H.log(string.format("[kolts_cave] f%d map=%d field=(%d,%d) ctrl=%s aligned=%s",
    H.frame, map(), H.fieldX(), H.fieldY(),
    tostring(H.hasControl()), tostring(H.tileAligned())))
end

-- settle: advanceStory (playBattles="flee") so an arrival-tile encounter
-- is fled instead of stalling a passive wait to timeout.
local function settleField(what, dstMap, maxF)
  local held = 0
  return H.advanceStory(function()
    local ok = H.hasControl() and H.tileAligned()
      and not H.battleLoadStarted() and not H.dialogWaiting()
      and (dstMap == nil or map() == dstMap)
    held = ok and held + 1 or 0
    return held >= 30
  end, maxF or 12000, { playBattles = "flee" })
end

local function mapChanged()
  local m0 = nil
  return function()
    if m0 == nil then m0 = map() end
    return map() ~= m0
  end
end

local A100 = { { 7, 13 }, { 19, 17 }, { 43, 24 }, { 50, 33 }, { 34, 7 },
               { 7, 29 }, { 9, 37 }, { 30, 52 }, { 58, 45 }, { 7, 48 },
               { 17, 59 }, { 56, 7 }, { 31, 36 } }
local A96  = { { 15, 21 }, { 16, 21 }, { 22, 21 }, { 16, 22 }, { 14, 12 },
               { 15, 12 }, { 12, 8 }, { 12, 9 }, { 29, 25 }, { 25, 15 } }
local A102 = { { 42, 50 }, { 43, 50 }, { 35, 50 }, { 50, 46 } }

-- one arrival check per circuit leg: right map, and (when the arrival tile
-- is fixed) the exact tile, so a mis-warp fails here with the tile in the
-- message instead of five legs later
local function at(tag, m, x, y)
  return H.call(function()
    H.assertEq(map(), m, tag .. ": on map " .. m)
    where(tag)
    if x then
      H.assertEq(H.fieldX(), x, tag .. ": at x=" .. x)
      H.assertEq(H.fieldY(), y, tag .. ": at y=" .. y)
    end
  end)
end

H.run({ maxFrames = 120000 }, {
  H.loadState(POOL),
  H.waitFrames(30),
  settleField("shelf F", 100),
  H.call(function()
    H.assertEq(map(), 100, "loaded on map 100, Mt. Kolts shelf F")
    where("shelf F")
  end),

  H.navTo(19, 17, { maxFrames = 20000, arrive = mapChanged(),
           playBattles = "flee" }),
  H.release(),
  settleField("cave 96 P", 96),
  H.call(function()
    H.assertEq(map(), 96, "crossed onto map 96, the Mt. Kolts cave")
    where("cave arrival")
  end),

  -- P -> shelf D
  H.navTo(22, 21, { maxFrames = 20000, playBattles = "flee", avoid = A96,
           arrive = mapChanged() }),
  H.release(), settleField("shelf D", 100), at("shelf D", 100, 44, 24),

  -- D -> ledge E, a same-map warp ((56,7) -> (30,36)), so the arrive
  -- predicate keys on the x jump rather than a map change
  H.navTo(56, 7, { maxFrames = 25000, playBattles = "flee", avoid = A100,
           arrive = function() return H.fieldX() <= 32 end }),
  H.release(), settleField("ledge E", 100), at("ledge E", 100, 30, 36),
  H.openChest{ stand = { 30, 34 }, face = "up", bit = 39,
               what = "Atlas Armlet",
               nav = { playBattles = "flee", avoid = A100 } },

  -- E -> D (the same warp pair, back: (31,36) -> (57,7))
  H.navTo(31, 36, { maxFrames = 15000, playBattles = "flee", avoid = A100,
           arrive = function() return H.fieldX() >= 50 end }),
  H.release(), settleField("D again", 100), at("D again", 100, 57, 7),

  -- D -> cave pocket S
  H.navTo(50, 33, { maxFrames = 25000, playBattles = "flee", avoid = A100,
           arrive = mapChanged() }),
  H.release(), settleField("cave S", 96), at("cave S", 96, 28, 25),
  H.openChest{ stand = { 28, 26 }, face = "down", bit = 38, what = "Guardian",
               nav = { playBattles = "flee", avoid = A96 } },

  -- S -> D
  H.navTo(29, 25, { maxFrames = 15000, playBattles = "flee", avoid = A96,
           arrive = mapChanged() }),
  H.release(), settleField("D third", 100), at("D third", 100, 51, 33),

  -- D -> cave R.  R's arrival tile (14,12) is the second glimpse trigger,
  -- so the settle plays that scene out; no exact-tile assert because the
  -- scene can nudge the party.
  H.navTo(34, 7, { maxFrames = 25000, playBattles = "flee", avoid = A100,
           arrive = mapChanged() }),
  H.release(), settleField("cave R", 96, 24000), at("cave R", 96),

  -- R -> the bridge (the long entrance at (12,8))
  H.navTo(12, 8, { maxFrames = 20000, playBattles = "flee", avoid = A96,
           arrive = mapChanged() }),
  H.release(), settleField("bridge", 102), at("bridge", 102, 51, 46),

  -- bridge -> shelf C
  H.navTo(43, 50, { maxFrames = 20000, playBattles = "flee", avoid = A102,
           arrive = mapChanged() }),
  H.release(), settleField("shelf C", 100), at("shelf C", 100, 6, 29),

  -- C -> cave pocket Q
  H.navTo(9, 37, { maxFrames = 20000, playBattles = "flee", avoid = A100,
           arrive = mapChanged() }),
  H.release(), settleField("cave Q", 96), at("cave Q", 96, 25, 16),
  H.openChest{ stand = { 27, 15 }, face = "up", bit = 37, what = "Tent",
               nav = { playBattles = "flee", avoid = A96 } },

  -- Q -> C
  H.navTo(25, 15, { maxFrames = 15000, playBattles = "flee", avoid = A96,
           arrive = mapChanged() }),
  H.release(), settleField("C second", 100), at("C second", 100, 9, 36),

  -- C -> the bridge
  H.navTo(7, 29, { maxFrames = 20000, playBattles = "flee", avoid = A100,
           arrive = mapChanged() }),
  H.release(), settleField("bridge second", 102),
  at("bridge second", 102, 43, 51),

  -- bridge -> R, up the (50,46) stair
  H.navTo(50, 46, { maxFrames = 20000, playBattles = "flee", avoid = A102,
           arrive = mapChanged() }),
  H.release(), settleField("R second", 96), at("R second", 96, 11, 8),

  -- R -> D
  H.navTo(15, 12, { maxFrames = 20000, playBattles = "flee", avoid = A96,
           arrive = mapChanged() }),
  H.release(), settleField("D fourth", 100), at("D fourth", 100, 35, 7),

  -- D -> P.  The return lands on (21,21), P's other arrival tile, and the
  -- existing off-trigger step below walks the last stretch to (18,22).
  H.navTo(43, 24, { maxFrames = 25000, playBattles = "flee", avoid = A100,
           arrive = mapChanged() }),
  H.release(), settleField("P return", 96), at("P return", 96, 21, 21),
  -- ===================================================================== --

  H.navTo(18, 22, { maxFrames = 8000, playBattles = "flee" }),
  H.release(),
  settleField("cave 96 P, off-trigger", 96),
  H.call(function()
    H.assertEq(map(), 96, "still on map 96 after stepping clear")
    H.assertEq(H.fieldX(), 18, "spawn tile is (18,22), not the trigger")
    H.assertEq(H.fieldY(), 22, "spawn tile is (18,22), not the trigger")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.chestOpen(37), true, "Tent bit 37 open (cave Q)")
    H.assertEq(H.chestOpen(38), true, "Guardian bit 38 open (cave S)")
    H.assertEq(H.chestOpen(39), true, "Atlas Armlet bit 39 open (ledge E)")
    H.log(string.format("[kolts_cave] danger counter at generation: %04X (unrigged -- "
      .. "whatever the walk accumulated)", H.readWord(0x1f6e)))
    where("cave spawn")
    H.screenshot("kolts_cave")
  end),
  H.saveState("kolts_cave.mss"),
  H.logStep(function()
    return string.format("kolts_cave generated at frame %d", H.frame)
  end),

  -- Check the fixture is what it claims.  The lane is not named here: map
  -- 96 P's arrival tile is not one any earlier script stops on, so the
  -- first walkable direction is taken and the map is guarded, raising
  -- with the tile in the message if the pacing walks onto an exit.
  (function()
    local battN, waited, lane, lastXY, steps = 0, 0, nil, nil, 0
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 3 then H.setPad({}) return true end
      if map() ~= 96 then
        error("pacing left map 96 (now " .. map() .. ") after " .. steps
          .. " steps: the lane walked onto an entrance tile", 0)
      end
      return waited >= 7000
    end, 7600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then
              lane = { ax = x, ay = y, out = d, back = BACK[d] }
              break
            end
          end
          if lane == nil then
            error("cave P: no walkable direction from (" .. x .. "," .. y .. ")", 0)
          end
          H.log(string.format("[kolts_cave] lane (%d,%d) %s/%s",
            x, y, lane.out, lane.back))
        end
        local xy = x * 1000 + y
        if lastXY ~= nil and xy ~= lastXY then steps = steps + 1 end
        lastXY = xy
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "an encounter fires in cave 96 P")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(H.monstersPresent() > 0, true,
      "cave 96 drew a live formation -- map 96 carries an encounter group")
    H.log(string.format("[kolts_cave] formation %s",
      string.format("%04X %04X %04X %04X %04X %04X",
        table.unpack(H.formationWords()))))
    for slot = 0, 5 do
      if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
        H.log(string.format("[kolts_cave] mon s%d sp%04X hp%d weak%02X sh%d/%d",
          slot, H.readWord(0x57c0 + slot * 2),
          H.readWord(0x3bfc + slot * 2),
          H.readByte(0x3be8 + slot * 2),
          H.readByte(0x3e40 + slot * 2), H.readByte(0x3e41 + slot * 2)))
      end
    end
  end),
})
