-- probe_narshe_town.lua -- bank the in-Narshe fixture + scan door tiles
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function fineX() return ((rd(0x35) << 16) | H.readWord(0x33)) end
local function fineY() return ((rd(0x39) << 16) | H.readWord(0x37)) end
local function sw(bit) return (H.readByte(0x1E80 + (bit >> 3)) >> (bit & 7)) & 1 end
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
local function mogIn()
  -- $1850+char = party-assignment byte; nonzero low bits = in a party.
  -- $02FA is the roster switch set when Mog is taken.
  return (H.readByte(0x1850 + 10) & 0x07) ~= 0 or sw(0x2FA) == 1
end

local CAND = { {84,34},{84,35},{85,35},{84,36},{85,36},{83,35} }
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

-- walk to (x,y) then wait out whatever scene fires, until pred holds
local function stage(x, y, pred, tag, opts)
  opts = opts or {}
  local aPhase, calm = 0, 0
  return {
    H.navTo(x, y, { maxFrames = opts.maxFrames or 9000,
      playBattles = "flee", arrive = pred }),
    H.driveUntil(function()
      if not pred() then calm = 0; return false end
      return calm >= 60
    end, 6000, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if H.dialogWaiting() then
          calm = 0
          H.setPad(aPhase < 4 and { "a" } or {})
        else
          if pred() and H.hasControl() then calm = calm + 1 end
          H.setPad({})
        end
      end),
    }, tag),
  }
end
local function edge(x, y, dir, destMap, tag)
  return {
    H.navTo(x, y, { maxFrames = 9000, playBattles = "flee",
      arrive = function() return mapIs(destMap) end }),
    H.driveUntil(function() return mapIs(destMap) end, 900,
      { H.call(function() H.setPad({ [dir] = true }) end) }, tag),
    H.waitFrames(60),
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

H.run({ maxFrames = 80000 }, flatten({
  H.loadState("build/states/wob_tzen_done.mss.lua"),
  H.waitFrames(8),
  -- board and fly to Narshe
  H.worldNavTo(function() return H.readByte(0x1f62) end,
               function() return H.readByte(0x1f63) end,
    { maxFrames = 8000, playBattles = "tactical",
      arrive = function() return not H.worldMode() end }),
  H.driveUntil(function() return rd(0x20) == 1 end, 1200,
    { H.call(function() H.setPad(H.frame % 16 < 4 and { "a" } or {}) end) },
    "aboard"),
  H.waitFrames(150),
  H.driveUntil(function() return landed end, 16000,
    { H.call(flyFrame) }, "landed at the Narshe doorstep"),
  H.waitFrames(60),
  H.worldNavTo(84, 33, { maxFrames = 6000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  H.driveUntil(function() return not H.worldMode() end, 900,
    { H.call(function() H.setPad(H.frame % 16 < 4 and { "a" } or {}) end) },
    "Narshe loads"),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(mapIs(20), true, "this is Narshe (map 20)")
    H.log(string.format("in Narshe at (%d,%d)", H.fieldX(), H.fieldY()))
  end),
  H.saveState("wob_narshe_town.mss"),
  H.call(function()
    for _, t in ipairs({ {52,37},{52,38},{51,37},{53,37},{52,36},
                         {41,36},{32,30},{29,25},{18,22},{15,56},{22,44},{10,36},{26,8},{33,54} }) do
      local p = H.bfsPath(t[1], t[2])
      H.log(string.format("  bfs (%d,%d): %s", t[1], t[2],
        p and (#p .. " steps") or "NO PATH"))
    end
  end),
  H.logStep(function() return "done" end),
}))
