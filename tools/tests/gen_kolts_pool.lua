-- gen_kolts_pool.lua -- one crossing past kolts_doorstep, for a fixture that
-- actually HAS a random-encounter pool.
--
--   kolts_pool.mss   map 100 shelf F, the first walkable stretch of the
--                    mountain, party in control and tile-aligned.
--
-- WHY THIS EXISTS.  kolts_doorstep.mss (map 95) is the mountain's ENTRANCE
-- map, and it is transit only: a balance run paced 437 tiles on it across
-- six samples and drew zero encounters, voiding every one as a timeout.
-- That is not a pacing bug and not a rate to tune -- map 95 simply carries
-- no encounter group, so no amount of walking on it can measure the Kolts
-- trash pool.  gen_kolts' own map-100 flood (its THE MOUNTAIN header) names
-- shelf F as the first partition past the entrance; K1 is the single
-- crossing that reaches it, and this script is exactly gen_kolts' K1 with a
-- save on the far side.
--
-- The party is whatever kolts_doorstep carries -- the Figaro->Kolts three,
-- TERRA + LOCKE + EDGAR -- which is the point: every party number in
-- balance-metrics.md before this fixture was solo Terra or the two-thirds
-- Locke+Terra of worldmap_narshe, so Edgar's Tools rungs (the pierce and
-- poison CLASS chips, the only class-chip carrier the stretch has) had
-- never been driven against a live pool.
--
-- ENCOUNTER SUPPRESSION during the crossing, not battle-clearing.  An
-- encounter fired on the way would leave the fixture with spent MP, spent
-- HP and banked XP -- a party that is no longer the stretch's party, which
-- is the one thing this fixture is for.  $1F6E (the per-step danger
-- accumulator both trigger paths compare against) is held at zero across
-- the walk and the settle, so no step can reach the threshold; it is left
-- at zero in the saved state, which is also what bal_party.lua writes
-- before every sample anyway (mines_pace.lua, Measurement #4: a cold
-- counter is the honest steady-state interval).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local DOORSTEP = "/Users/mtklein/ot6/build/states/kolts_doorstep.mss.lua"
local DANGER = 0x1f6e

-- map compares stay MASKED: loaders ride flag bits in $1F64's high byte
local function map() return H.mapId() & 0x1ff end

local function where(tag)
  H.log(string.format("[kolts_pool] f%d map=%d field=(%d,%d) ctrl=%s aligned=%s",
    H.frame, map(), H.fieldX(), H.fieldY(),
    tostring(H.hasControl()), tostring(H.tileAligned())))
end

-- gen_kolts' settleField, minus the story-chain scaffolding it does not
-- need here: control + alignment + the expected map, held for 30 frames.
local function settleField(what, dstMap, maxF)
  local held = 0
  return H.driveUntil(function()
    H.writeWord(DANGER, 0)              -- see header: no encounter mid-settle
    local ok = H.hasControl() and H.tileAligned()
      and (dstMap == nil or map() == dstMap)
    held = ok and held + 1 or 0
    return held >= 30
  end, maxF or 12000, { H.call(function() H.setPad({}) end), H.waitFrames(1) },
  "settle " .. what)
end

local function mapChanged()
  local m0 = nil
  return function()
    if m0 == nil then m0 = map() end
    return map() ~= m0
  end
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOORSTEP),
  H.waitFrames(30),
  settleField("kolts doorstep", 95),
  H.call(function()
    H.assertEq(map(), 95, "loaded on map 95, the Mt. Kolts entrance")
    where("doorstep")
    -- the roster, so the fixture's party is on the record in the log that
    -- minted it rather than inferred from a later measurement
    for i = 0, 3 do
      local id = H.readByte(0x1a6d + i)          -- party slot -> char index
      if id ~= 0xff then
        local blk = 0x1600 + id * 37
        H.log(string.format("[kolts_pool] slot%d char=%02X level=%d hp=%d/%d",
          i, id, H.readByte(blk + 8),
          H.readWord(blk + 9), H.readWord(blk + 11)))
      end
    end
  end),

  -- K1, gen_kolts' first mountain crossing: (11,26) is map 95's exit onto
  -- shelf F.  gen_kolts pre-checks this plan against the map's world-exit
  -- row (y=37, two tiles south of the spawn) before walking it; the same
  -- check runs here, because a BFS shortest path that clips that row walks
  -- the party off the mountain and the mint would save the WORLD map.
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
  H.navTo(11, 26, { maxFrames = 20000, arrive = mapChanged() }),
  H.release(),
  settleField("shelf F", 100),
  H.call(function()
    H.assertEq(map(), 100, "crossed onto map 100, MT. KOLTS shelf F")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.writeWord(DANGER, 0)
    where("shelf F")
    H.screenshot("kolts_pool")
  end),
  H.saveState("kolts_pool.mss"),
  H.logStep(function()
    return string.format("kolts_pool minted at frame %d", H.frame)
  end),

  -- PROOF THE FIXTURE IS WHAT IT CLAIMS: pace the shelf and show an
  -- encounter actually fires.  Map 95 looked fine by every other check and
  -- was still unmeasurable, so "this map has a pool" is asserted here, once,
  -- at mint time -- not discovered as six voided samples in a balance run.
  --
  -- The lane is RIGHT, and that is not a coin flip.  The passability model
  -- allows LEFT from the (8,13) arrival tile, and (7,13) is shelf F's
  -- entrance back to map 95 (gen_kolts' mountain flood: "F ... exits
  -- (7,13)->95").  A first cut scanned left-first, walked straight off the
  -- mountain on step one, and then paced 7000 encounterless frames on map
  -- 95 -- which reads exactly like "shelf F has no pool" and is not.
  -- H.canStep models terrain and objects; it cannot see entrance records,
  -- so the safe direction is named here and the map is guarded below.
  H.call(function() H.writeWord(DANGER, 0) end),
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
