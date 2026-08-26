-- probe_return_pocket.lua -- flies from Tzen to the Chimera pocket, lands,
-- and saves the fixture.  Boots from wob_golem_done.mss.
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

local CAND = { {116,25},{117,25},{115,25},{114,25},{118,25},{116,26},{117,26} }
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
      -- try adjacency on all four sides first, then the across-the-counter
      -- tiles shops use
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


H.run({ maxFrames = 30000 }, flatten({
  H.loadState("build/states/wob_tzen_done.mss.lua"),
  H.waitFrames(8),
  H.worldNavTo(function() return H.readByte(0x1f62) end,
               function() return H.readByte(0x1f63) end,
    { maxFrames = 8000, playBattles = "tactical",
      arrive = function() return not H.worldMode() end }),
  H.driveUntil(function() return rd(0x20) == 1 end, 1200,
    { H.call(function() H.setPad(H.frame % 16 < 4 and { "a" } or {}) end) },
    "aboard"),
  H.waitFrames(150),
  H.driveUntil(function() return landed end, 16000,
    { H.call(flyFrame) }, "landed back at the Chimera pocket"),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("back at the pocket: world=(%d,%d) gil=%d",
      H.worldX(), H.worldY(), gil()))
  end),
  H.saveState("wob_grind_run.mss"),
  H.logStep(function() return "done" end),
}))
