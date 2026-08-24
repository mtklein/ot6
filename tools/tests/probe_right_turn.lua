-- probe_right_turn.lua -- the walkthrough's "take a right": from 21's
-- entrance, the EAST arm (x58-62) and the (37,25)->41(19,51) door are
-- the two never-probed branches (#133).  Try both, goal-checking for
-- the snow-field chain the whole way.
local H = dofile("tools/tests/lib/ot6.lua")
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
local function sw(bit) return (H.readByte(0x1E80 + (bit >> 3)) >> (bit & 7)) & 1 end
local function goals()
  local m = H.mapId() & 0x1ff
  local G = (m == 21) and { {35,2},{34,2},{36,2},{37,2},{36,3} }
    or (m == 41) and { {107,12},{108,12},{117,12},{116,12},{41,5},{42,5},{43,5} }
    or {}
  for _, c in ipairs(G) do
    if H.bfsPath(c[1], c[2]) then return c end
  end
  return nil
end
local function flatten(t)
  local out = {}
  for _, v in ipairs(t) do
    if type(v) == "table" and v.tick == nil and v[1] ~= nil then
      for _, s in ipairs(v) do out[#out + 1] = s end
    else out[#out + 1] = v end
  end
  return out
end
H.run({ maxFrames = 60000 }, flatten({
  H.loadState("build/states/wob_chase23C.mss.lua"),
  H.waitFrames(8),
  -- from the chase spot the only link south is the exit row; ride it to
  -- town (38,2) deliberately, then re-enter 21 at (26,50) and TAKE THE
  -- RIGHT: east along the south strip to the arm at (60,48)
  H.navTo(27, 51, { maxFrames = 9000, playBattles = "flee",
    arrive = function() return mapIs(20) end }),
  H.driveUntil(function() return mapIs(20) end, 900,
    { H.call(function() H.setPad({ down = true }) end) }, "down to town"),
  H.waitFrames(60),
  H.navTo(36, 2, { maxFrames = 9000, playBattles = "flee",
    arrive = function() return mapIs(21) end }),
  H.driveUntil(function() return mapIs(21) end, 900,
    { H.call(function() H.setPad({ up = true }) end) }, "back into 21"),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("re-entered 21 at (%d,%d)", H.fieldX(), H.fieldY()))
  end),
  H.navTo(60, 48, { maxFrames = 15000, playBattles = "flee",
    avoid = { {23,52},{24,52},{25,52},{26,52},{27,52},{28,52} } }),
  H.call(function()
    H.log(string.format("east arm at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("east_arm")
    local g = goals()
    H.log("goal check: " .. (g and ("REACHABLE (%d,%d)"):format(g[1],g[2]) or "no"))
    -- chart the arm neighborhood
    for y = 36, 56, 2 do
      local row = {}
      for x = 50, 63 do row[#row+1] = H.bfsPath(x, y) and "O" or "." end
      H.log("  arm y" .. y .. " " .. table.concat(row))
    end
  end),
  -- push east/north from the arm tip with long holds
  (function()
    local t, phase = 0, 1
    local holds = { {right=true}, {up=true,right=true}, {up=true}, {down=true,right=true} }
    return H.driveUntil(function()
      return not mapIs(21) or goals() ~= nil or t > 5000
    end, 6000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then H.setPad(t % 8 < 4 and { "a" } or {}); return end
        if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
        if t % 350 == 0 then phase = (phase % #holds) + 1 end
        H.setPad(holds[phase])
        if t % 600 == 0 then
          H.log(string.format("  arm-push t=%d map=%d (%d,%d)", t,
            H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
        end
      end),
    }, "east-arm push")
  end)(),
  H.call(function()
    H.log(string.format("after arm: map=%d (%d,%d) goal=%s",
      H.mapId() & 0x1ff, H.fieldX(), H.fieldY(),
      tostring(goals() ~= nil)))
    H.screenshot("after_arm")
  end),
  -- branch B (only if still on 21 with no goal): the (37,25) door -> 41 (19,51)
  H.cond(function() return mapIs(21) and goals() == nil end, flatten({
    H.navTo(37, 26, { maxFrames = 9000, playBattles = "flee",
      arrive = function() return mapIs(41) end }),
    H.driveUntil(function() return mapIs(41) end, 1500,
      { H.call(function() H.setPad({ up = true }) end) }, "into 41 south"),
    H.waitFrames(60),
    H.call(function()
      H.log(string.format("41-south at (%d,%d)", H.fieldX(), H.fieldY()))
      local g = goals()
      H.log("goal check: " .. (g and ("REACHABLE (%d,%d)"):format(g[1],g[2]) or "no"))
      for y = 40, 60, 2 do
        local row = {}
        for x = 4, 40, 2 do row[#row+1] = H.bfsPath(x, y) and "O" or "." end
        H.log("  s41 y" .. y .. " " .. table.concat(row))
      end
      H.screenshot("s41")
    end),
  }), {}),
  H.logStep(function() return "done" end),
}))
