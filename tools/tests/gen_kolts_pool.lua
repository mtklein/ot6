-- gen_kolts_pool.lua -- one crossing past kolts_entry, for a fixture on a map
-- that has a random-encounter pool.

--   kolts_pool.mss   map 100 shelf F, the first walkable stretch of the
--                    mountain, party in control and tile-aligned.

local H = dofile("tools/tests/lib/ot6.lua")

local ENTRY = "build/states/kolts_entry.mss.lua"

-- map compares stay masked: loaders leave flag bits in $1F64's high byte
local function map() return H.mapId() & 0x1ff end

local function where(tag)
  H.log(string.format("[kolts_pool] f%d map=%d field=(%d,%d) ctrl=%s aligned=%s",
    H.frame, map(), H.fieldX(), H.fieldY(),
    tostring(H.hasControl()), tostring(H.tileAligned())))
end

-- Settle: control + alignment + the expected map, held for 30 frames.
-- advanceStory (playBattles="tactical") drives it rather than a passive wait,
-- so an encounter that rolled on the arrival tile is fled instead of
-- stalling the settle to its timeout.
local function settleField(what, dstMap, maxF)
  local held = 0
  return H.advanceStory(function()
    local ok = H.hasControl() and H.tileAligned()
      and not H.battleLoadStarted() and not H.dialogWaiting()
      and (dstMap == nil or map() == dstMap)
    held = ok and held + 1 or 0
    return held >= 30
  end, maxF or 12000, { playBattles = "tactical" })
end

local function mapChanged()
  local m0 = nil
  return function()
    if m0 == nil then m0 = map() end
    return map() ~= m0
  end
end

H.run({ maxFrames = 60000 }, {
  H.loadState(ENTRY),
  H.waitFrames(30),
  settleField("kolts entry point", 95),
  H.call(function()
    H.assertEq(map(), 95, "loaded on map 95, the Mt. Kolts entrance")
    where("entry point")
    -- the roster, so the fixture's party is on the record in the log that
    -- generated it rather than inferred from a later measurement
    for i = 0, 3 do
      local id = H.readByte(0x1a6d + i)          -- party slot -> char index
      if id ~= 0xff then
        local blk = 0x1600 + id * 37
        H.log(string.format(
          "[kolts_pool] slot%d char=%02X level=%d hp=%d/%d mp=%d/%d",
          i, id, H.readByte(blk + 8),
          H.readWord(blk + 9), H.readWord(blk + 11),
          H.readWord(blk + 13), H.readWord(blk + 15)))
      end
    end
  end),

  -- (11,26) is map 95's exit onto shelf F.  The plan is pre-checked
  -- against the map's world-exit row (y=37, two tiles south of the spawn)
  -- because a BFS shortest path that clips that row walks the party off
  -- the mountain.
  H.call(function()
    local p = H.bfsPath(11, 26)
    H.assertEq(p ~= nil, true, "a path to (11,26) exists")
    local x, y = H.fieldX(), H.fieldY()
    local hit = (y == 37)
    for _, d in ipairs(p) do
      local dd = ({ up = { 0, -1 }, down = { 0, 1 },
                    left = { -1, 0 }, right = { 1, 0 },
                    upleft = { -1, -1 }, upright = { 1, -1 },
                    downleft = { -1, 1 }, downright = { 1, 1 } })[d]
      x, y = x + dd[1], y + dd[2]
      if y == 37 then hit = true end
    end
    H.log(string.format("plan to (11,26): %d steps, touches y=37: %s",
      #p, tostring(hit)))
    H.assertEq(hit, false, "plan stays off map 95's world-exit row 37")
  end),
  H.navTo(11, 26, { maxFrames = 20000, arrive = mapChanged(),
           playBattles = "tactical" }),
  H.release(),
  settleField("shelf F", 100),
  H.call(function()
    H.assertEq(map(), 100, "crossed onto map 100, MT. KOLTS shelf F")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.log(string.format("[kolts_pool] danger counter at generation: %04X (unrigged -- "
      .. "whatever the walk accumulated)", H.readWord(0x1f6e)))
    where("shelf F")
    H.screenshot("kolts_pool")
  end),
  H.saveState("kolts_pool.mss"),
  H.logStep(function()
    return string.format("kolts_pool generated at frame %d", H.frame)
  end),

  -- Check the fixture is what it claims: pace the shelf and show an
  -- encounter fires.

  -- The lane is deliberately RIGHT: LEFT from the (8,13) arrival tile
  -- leads to (7,13), shelf F's entrance back to map 95.  H.canStep models
  -- terrain and objects but cannot see entrance records, so the safe
  -- direction is named here and the map is guarded below.
  (function()
    local battN, waited, lane, lastXY, steps = 0, 0, nil, nil, 0
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 3 then H.setPad({}) return true end
      if map() ~= 100 then
        error("pacing left map 100 (now " .. map() .. "): the lane walked "
          .. "onto an entrance tile", 0)
      end
      return waited >= 7000
    end, 7600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          if not H.canStep(x, y, "right") then
            error("shelf F: cannot step right from (" .. x .. "," .. y .. ")", 0)
          end
          lane = { ax = x, ay = y, out = "right", back = BACK.right }
          H.log(string.format("[kolts_pool] lane (%d,%d) %s/%s",
            x, y, lane.out, lane.back))
        end
        local xy = x * 1000 + y
        if lastXY ~= nil and xy ~= lastXY then steps = steps + 1 end
        lastXY = xy
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "an encounter fires on shelf F")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(H.monstersPresent() > 0, true,
      "shelf F drew a live formation -- map 100 carries an encounter group")
    H.log(string.format("[kolts_pool] formation %s",
      string.format("%04X %04X %04X %04X %04X %04X",
        table.unpack(H.formationWords()))))
    for slot = 0, 5 do
      if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
        H.log(string.format("[kolts_pool] mon s%d sp%04X hp%d weak%02X sh%d/%d",
          slot, H.readWord(0x57c0 + slot * 2),
          H.readWord(0x3bfc + slot * 2),
          H.readByte(0x3be8 + slot * 2),
          H.readByte(0x3e40 + slot * 2), H.readByte(0x3e41 + slot * 2)))
      end
    end
  end),
})
