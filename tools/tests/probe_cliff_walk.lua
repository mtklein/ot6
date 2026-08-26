-- probe_cliff_walk.lua -- blind-walks NORTH from the $023C chase state
-- toward map 21's crossing row (34..37,1) -> map 22.  The BFS model calls
-- the top pocket unreachable; the engine allows z-level steps the model
-- refuses.  Greedy wiggle: holds up; when y stalls, alternates
-- up-left/up-right sweeps.  Success = the map flips to 22 (the row
-- teleports on step-on).
local H = dofile("tools/tests/lib/ot6.lua")
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
local t, lastY, stall, sweep = 0, nil, 0, 0
H.run({ maxFrames = 30000 }, {
  H.loadState("build/states/wob_chase23C.mss.lua"),
  H.waitFrames(8),
  H.driveUntil(function()
    if mapIs(22) or mapIs(23) then return true end
    if t > 0 and t % 300 == 0 then
      if mapIs(21) then
        for _, c in ipairs({ {35,2},{34,2},{36,2},{37,2},{35,3} }) do
          if H.bfsPath(c[1], c[2]) then
            H.log(string.format("  GOAL: 21 crossing reachable via (%d,%d)", c[1], c[2]))
            return true
          end
        end
      elseif mapIs(41) then
        for _, c in ipairs({ {107,12},{108,12},{117,12},{116,12},{107,13},{117,13} }) do
          if H.bfsPath(c[1], c[2]) then
            H.log(string.format("  GOAL: 41 top door reachable via (%d,%d)", c[1], c[2]))
            return true
          end
        end
      end
    end
    return false
  end, 20000, {
    H.call(function()
      t = t + 1
      local x, y = H.fieldX(), H.fieldY()
      if t % 240 == 0 then
        H.log(string.format("  walk t=%d map=%d at (%d,%d) z=%d", t,
          H.mapId() & 0x1ff, x, y, H.readByte(0xb2) & 3))
      end
      if H.dialogWaiting() then H.setPad(t % 8 < 4 and { "a" } or {}); return end
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      if lastY == nil or y < lastY then lastY = y; stall = 0 end
      if y == lastY then stall = stall + 1 end
      if stall < 90 then
        H.setPad({ up = true })
      else
        sweep = sweep + 1
        local phase = math.floor(sweep / 120) % 4
        if phase == 0 then H.setPad({ up = true, left = true })
        elseif phase == 1 then H.setPad({ left = true })
        elseif phase == 2 then H.setPad({ up = true, right = true })
        else H.setPad({ right = true }) end
        if stall > 1500 then lastY = nil; stall = 0; sweep = 0 end
      end
    end),
  }, "walked onto the 21->22 row"),
  H.call(function()
    H.log(string.format("WANDER END map=%d at (%d,%d)", H.mapId() & 0x1ff,
      H.fieldX(), H.fieldY()))
    H.screenshot("cliff_walk")
  end),
  -- if a goal tile came reachable, take it and push through
  H.cond(function() return mapIs(41) end, {
    (function()
      local tile = nil
      return H.call(function()
        for _, c in ipairs({ {107,12},{108,12},{117,12},{116,12},{107,13},{117,13} }) do
          if H.bfsPath(c[1], c[2]) then tile = c; return end
        end
      end)
    end)(),
  }, {}),
  H.cond(function() return mapIs(41) end, {
    H.navTo(function()
      for _, c in ipairs({ {107,12},{108,12},{117,12},{116,12} }) do
        if H.bfsPath(c[1], c[2]) then return c[1] end
      end
      return H.fieldX()
    end, function()
      for _, c in ipairs({ {107,12},{108,12},{117,12},{116,12} }) do
        if H.bfsPath(c[1], c[2]) then return c[2] end
      end
      return H.fieldY()
    end, { maxFrames = 9000, playBattles = "flee",
      arrive = function() return mapIs(21) end }),
    H.driveUntil(function() return mapIs(21) end, 900,
      { H.call(function() H.setPad({ up = true }) end) }, "into 21 top"),
    H.waitFrames(60),
  }, {}),
  H.cond(function() return mapIs(21) end, {
    H.navTo(function()
      for _, c in ipairs({ {35,2},{34,2},{36,2},{37,2} }) do
        if H.bfsPath(c[1], c[2]) then return c[1] end
      end
      return H.fieldX()
    end, function()
      for _, c in ipairs({ {35,2},{34,2},{36,2},{37,2} }) do
        if H.bfsPath(c[1], c[2]) then return c[2] end
      end
      return H.fieldY()
    end, { maxFrames = 9000, playBattles = "flee",
      arrive = function() return mapIs(22) end }),
    H.driveUntil(function() return mapIs(22) end, 900,
      { H.call(function() H.setPad({ up = true }) end) }, "into 22"),
    H.waitFrames(60),
  }, {}),
  H.call(function()
    H.log(string.format("RESULT map=%d at (%d,%d)", H.mapId() & 0x1ff,
      H.fieldX(), H.fieldY()))
  end),
  H.cond(function() return mapIs(22) or mapIs(23) end,
    { H.saveState("wob_cliffside.mss") }, {}),
  H.logStep(function() return "done" end),
})
