-- probe_tzen.lua -- fly Jidoor -> Tzen: buy SRAPHIM (3000 GP) and what
-- relics the purse allows.
--
-- Boots from wob_golem_done.mss (in Jidoor town, Golem+Zoneseek won).
-- Tzen = map 306, world door (119,149); the doorstep row below is
-- landable.  Inside: the Sraphim seller stands at (29,3) (_cc5ddd, WoB
-- arm: "For 3000 GP this glowing stone's yours", choice row 0 = Yes);
-- the relic room 312 is the bump door (25,7), keeper shop 32 at (80,16)
-- (Earrings/RunningShoes/Black Belt/Amulet).  RunningShoes x1 is bought
-- only if the purse still covers it after Golem+Sraphim; the gil top-up
-- for the rest is another grind chunk, not this probe's business.
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function fineX() return ((rd(0x35) << 16) | H.readWord(0x33)) end
local function fineY() return ((rd(0x39) << 16) | H.readWord(0x37)) end
local function gil() return H.readByte(0x1860) | (H.readByte(0x1861) << 8) | (H.readByte(0x1862) << 16) end
local function espers()
  local n = 0
  for i = 0, 3 do
    local b = H.readByte(0x1a69 + i)
    while b > 0 do n = n + (b & 1); b = b >> 1 end
  end
  return n
end
local function mapIs(m) return (H.mapId() & 0x1ff) == m end

local CAND = { {117,150},{116,150},{118,150},{117,151},{116,151},{115,150},{119,151} }
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

local function approachTalk(nx, ny, name, doneFn)
  local tile, dir = nil, "up"
  local phase = 0
  return {
    H.call(function()
      -- adjacency first (all four sides -- the Tzen seller's south tile
      -- is blocked), then the across-the-counter tiles shops use
      local cands = {
        {nx,ny+1,"up"},{nx-1,ny,"right"},{nx+1,ny,"left"},{nx,ny-1,"down"},
        {nx,ny+2,"up"},{nx-1,ny+1,"up"},{nx+1,ny+1,"up"},
        {nx-2,ny,"right"},{nx+2,ny,"left"},{nx,ny-2,"down"},
      }
      for _, c in ipairs(cands) do
        if H.bfsPath(c[1], c[2]) or
           (H.fieldX() == c[1] and H.fieldY() == c[2]) then
          tile, dir = { c[1], c[2] }, c[3]
          H.log(string.format("[%s] talk tile (%d,%d) facing %s", name, c[1], c[2], dir))
          return
        end
      end
      error(name .. ": no reachable talk tile near (" .. nx .. "," .. ny .. ")")
    end),
    H.navTo(function() return tile[1] end, function() return tile[2] end,
      { maxFrames = 8000, playBattles = "flee" }),
    H.driveUntil(doneFn, 3000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
        H.setPad(phase < 4 and { [dir] = true, a = true } or { [dir] = true })
      end),
    }, name .. ": done"),
  }
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
local espersAtBoot = nil

H.run({ maxFrames = 50000 }, flatten({
  H.loadState("build/states/wob_golem_done.mss.lua"),
  H.waitFrames(8),
  H.call(function()
    espersAtBoot = espers()
    H.log(string.format("boot: gil=%d espers=%d map=%d (%d,%d)",
      gil(), espersAtBoot, H.mapId() & 0x3ff, H.fieldX(), H.fieldY()))
  end),
  -- leave Jidoor: the town's world exit is the bottom edge at the arrival
  -- tile (15,61)
  H.navTo(15, 61, { maxFrames = 12000, playBattles = "flee",
    arrive = function() return H.worldMode() end }),
  H.driveUntil(function() return H.worldMode() end, 900,
    { H.call(function() H.setPad({ down = true }) end) }, "out to the world"),
  H.waitFrames(60),
  -- board the ship parked at the Jidoor doorstep
  H.worldNavTo(function() return H.readByte(0x1f62) end,
               function() return H.readByte(0x1f63) end,
    { maxFrames = 8000, playBattles = "tactical",
      arrive = function() return not H.worldMode() end }),
  H.driveUntil(function() return rd(0x20) == 1 end, 1200,
    { H.call(function() H.setPad(H.frame % 16 < 4 and { "a" } or {}) end) },
    "aboard"),
  H.waitFrames(150),
  H.driveUntil(function() return landed end, 16000,
    { H.call(flyFrame) }, "landed at the Tzen doorstep"),
  H.waitFrames(60),
  H.worldNavTo(119, 149, { maxFrames = 6000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  H.driveUntil(function() return not H.worldMode() end, 900,
    { H.call(function() H.setPad(H.frame % 16 < 4 and { "a" } or {}) end) },
    "Tzen loads"),
  H.waitFrames(90),
  H.call(function()
    H.log(string.format("in Tzen: map=%d field=(%d,%d)", H.mapId() & 0x3ff,
      H.fieldX(), H.fieldY()))
    H.assertEq(mapIs(306), true, "this is WoB Tzen (map 306)")
    H.screenshot("tzen_arrival")
  end),
  -- Sraphim: seller at (29,3), ride his choice at row 0 (Yes) until owned
  approachTalk(29, 3, "sraphim",
    function() return espers() > espersAtBoot end),
  H.call(function()
    H.log(string.format("SRAPHIM bought: gil=%d espers=%d", gil(), espers()))
  end),
  -- relic room 312 via bump door (25,7); keeper shop 32 at (80,16)
  H.navTo(25, 8, { maxFrames = 9000, playBattles = "flee" }),
  H.driveUntil(function() return mapIs(312) end, 600,
    { H.call(function() H.setPad({ up = true }) end) }, "into the relic room"),
  H.waitFrames(50),
  approachTalk(80, 16, "relics",
    function() return H.readByte(0x26) == 0x25 end),
  H.cond(function() return gil() >= 7000 end, {
    H.buyItem(0xba, 1, function() return 1 end, "RunningShoes"),
  }, {}),
  (function()
    local phase = 0
    return H.driveUntil(function() return H.hasControl() end, 3000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(phase < 4 and { "b" } or {})
      end),
    }, "shop closed")
  end)(),
  H.call(function()
    H.log(string.format("TZEN RESULT: gil=%d espers=%d shoes=%d",
      gil(), espers(), H.invCountOf(0xba)))
    H.screenshot("tzen_done")
  end),
  -- out of the relic room (no return door record: rooms exit by walking
  -- off the south edge back to the parent map), then out of town via the
  -- exit row y=31, and save ON THE WORLD beside the ship so the next leg
  -- boots ready to board
  H.navTo(81, 22, { maxFrames = 6000, playBattles = "flee",
    arrive = function() return mapIs(306) end }),
  H.driveUntil(function() return mapIs(306) end, 900,
    { H.call(function() H.setPad({ down = true }) end) }, "back in Tzen"),
  H.waitFrames(50),
  H.navTo(23, 30, { maxFrames = 9000, playBattles = "flee",
    arrive = function() return H.worldMode() end }),
  H.driveUntil(function() return H.worldMode() end, 900,
    { H.call(function() H.setPad({ down = true }) end) }, "out to the world"),
  H.waitFrames(60),
  H.saveState("wob_tzen_done.mss"),
  H.logStep(function() return "done" end),
}))
