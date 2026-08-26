-- probe_jidoor_town.lua -- bank an in-Jidoor fixture and scout door
-- reachability.  The flight leg is slow (~1800 frames); everything inside
-- the town iterates from wob_jidoor_town.mss instead.  Also reports, via
-- H.bfsPath from the arrival tile, which tiles around the relic-shop door
-- (5,25) and the Auction House door (26,27) are pathable -- shop doors
-- here are bump/step-through entrances, so the walk targets a pathable
-- neighbor and pushes through.
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function fineX() return ((rd(0x35) << 16) | H.readWord(0x33)) end
local function fineY() return ((rd(0x39) << 16) | H.readWord(0x37)) end
local function tileX() return (fineX() >> 12) & 0xFF end
local function tileY() return (fineY() >> 12) & 0xFF end

local CAND = { {24,129},{23,129},{25,128},{24,128},{22,130},{30,129},{31,129} }
local DIRS = { "up", "down", "left", "right" }
local cal = {}
local mode = "calib"
local calI, calT, calX, calY = 1, 0, 0, 0
local rhyT, candI, landed = 0, 1, false
local function target()
  local c = CAND[candI]
  return c[1] * 4096 + 2048, c[2] * 4096 + 2048
end
local function bestDir(ex, ey)
  local best, bestDot = nil, 0
  for _, d in ipairs(DIRS) do
    local v = cal[d]
    if v then
      local dot = v.x * ex + v.y * ey
      if dot > bestDot then best, bestDot = d, dot end
    end
  end
  return best
end
local function flyFrame()
  if mode == "calib" then
    local d = DIRS[calI]
    if calT == 0 then calX, calY = fineX(), fineY() end
    calT = calT + 1
    if calT <= 30 then H.setPad({ y = true, [d] = true }); return end
    if calT <= 45 then H.setPad({}); return end
    cal[d] = { x = (fineX() - calX) / 30, y = (fineY() - calY) / 30 }
    calI, calT = calI + 1, 0
    if calI > #DIRS then mode = "travel" end
    return
  end
  if mode == "travel" then
    local wx, wy = target()
    local ex, ey = wx - fineX(), wy - fineY()
    if math.abs(ex) < 4096 and math.abs(ey) < 4096 then
      mode, rhyT = "rhythm", 0
      H.setPad({})
      return
    end
    local d = bestDir(ex, ey)
    if not d then error("strafe calibration produced no usable direction") end
    H.setPad({ y = true, [d] = true })
    return
  end
  if mode == "rhythm" then
    rhyT = rhyT + 1
    if rhyT <= 10 then
      local wx, wy = target()
      local d = bestDir(wx - fineX(), wy - fineY())
      H.setPad(d and { y = true, [d] = true } or {})
      return
    end
    if rhyT <= 22 then H.setPad({}); return end
    if rhyT <= 28 then H.setPad({ b = true }); return end
    H.setPad({})
    if rd(0x20) ~= 1 and H.worldHasControl() then landed = true; return end
    if rhyT - 28 >= 480 then
      candI = candI + 1
      if candI > #CAND then error("every landing candidate bounced") end
      mode = "travel"
    end
    return
  end
end

H.run({ maxFrames = 30000 }, {
  H.loadState("build/states/wob_grind_done.mss.lua"),
  H.waitFrames(8),
  H.worldNavTo(function() return H.readByte(0x1f62) end,
               function() return H.readByte(0x1f63) end,
    { maxFrames = 8000, playBattles = "tactical",
      arrive = function() return not H.worldMode() end }),
  H.driveUntil(function() return rd(0x20) == 1 end, 1200,
    { H.call(function() H.setPad(H.frame % 16 < 4 and { "a" } or {}) end) },
    "aboard (vehicle mode)"),
  H.waitFrames(150),
  H.driveUntil(function() return landed end, 16000,
    { H.call(flyFrame) }, "landed at the Jidoor doorstep"),
  H.waitFrames(60),
  H.worldNavTo(27, 130, { maxFrames = 6000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  H.driveUntil(function() return not H.worldMode() end, 900,
    { H.call(function() H.setPad(H.frame % 16 < 4 and { "a" } or {}) end) },
    "town map loads"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 198, "this is Jidoor (map 198)")
  end),
  H.saveState("wob_jidoor_town.mss"),
  H.call(function()
    for _, t in ipairs({ {5,25},{5,26},{6,25},{4,25},{5,24},
                         {26,27},{26,28},{25,27},{27,27},{26,26},
                         {16,12},{16,13} }) do
      local p = H.bfsPath(t[1], t[2])
      H.log(string.format("  bfs (%d,%d): %s", t[1], t[2],
        p and ("reachable, " .. #p .. " steps") or "NO PATH"))
    end
  end),
  H.logStep(function() return "done" end),
})
