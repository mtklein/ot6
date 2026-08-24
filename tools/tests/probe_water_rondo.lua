-- probe_water_rondo.lua -- take MOG down the Serpent Trench and learn
-- Water Rondo (#133 item 4).
--
-- Boots from wob_mog_done.mss (Mog just recruited on the Narshe cliff).
-- Route: walk the cliff chain back down (23 -> 22 -> 21 -> town), out to
-- the world, board the ship at the Narshe doorstep, fly to Crescent
-- Mountain (world door (214,148), approach column (214,149..152), land
-- on the west plain), enter 167 -> door (25,26) -> cave 168, step the
-- dive trigger (8,11) ("Jump? (Why not?)" -- the post-scenario $0041 arm,
-- A-only ride per the choice-menu lesson), then ride the trench: battles
-- fought tactically; Mog aboard learns the water-terrain dance when he
-- wins there.  Ends at Nikeah; saves wob_rondo_done.mss.
--
-- If the join left Mog OUT of the active party, the deck party-change
-- would be needed first; the probe asserts his party byte early so that
-- shows up as a loud clear failure rather than a silent no-learn.
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function fineX() return ((rd(0x35) << 16) | H.readWord(0x33)) end
local function fineY() return ((rd(0x39) << 16) | H.readWord(0x37)) end
local function sw(bit) return (H.readByte(0x1E80 + (bit >> 3)) >> (bit & 7)) & 1 end
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
local function dances() return H.readByte(0x1D4C) end

local CAND = { {210,148},{209,148},{210,147},{211,148},{208,149},{209,150},{207,148} }
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
    if not d then error("no usable strafe direction") end
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
local function edgeRow(x, y, dir, destMap, tag)
  return {
    H.navTo(x, y, { maxFrames = 9000, playBattles = "flee",
      arrive = function() return mapIs(destMap) end }),
    H.driveUntil(function() return mapIs(destMap) end, 1200,
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
local d0 = nil
local tactical = H.newFightDriver("rondo", { tactical = true, boost = true,
  items = true, healPercent = 55 })

H.run({ maxFrames = 120000 }, flatten({
  H.loadState("build/states/wob_mog_done.mss.lua"),
  H.waitFrames(8),
  H.call(function()
    d0 = dances()
    local mogParty = H.readByte(0x1850 + 10) & 0x07
    H.log(string.format("boot: dances=%02X mog-party=%d map=%d (%d,%d)",
      d0, mogParty, H.mapId() & 0x3ff, H.fieldX(), H.fieldY()))
    H.assertEq(mogParty ~= 0, true,
      "MOG is in the active party after the cliff join")
  end),
  -- down the cliffs: 23 -> 22 -> 21 -> town -> world
  edgeRow(23, 31, "down", 22, "23 -> 22"),
  edgeRow(16, 40, "down", 21, "22 -> 21"),
  edgeRow(24, 52, "down", 20, "21 -> town"),
  H.navTo(38, 61, { maxFrames = 12000, playBattles = "flee",
    arrive = function() return H.worldMode() end }),
  H.driveUntil(function() return H.worldMode() end, 900,
    { H.call(function() H.setPad({ down = true }) end) }, "out to the world"),
  H.waitFrames(60),
  -- board and fly to Crescent Mountain
  H.worldNavTo(function() return H.readByte(0x1f62) end,
               function() return H.readByte(0x1f63) end,
    { maxFrames = 8000, playBattles = "tactical",
      arrive = function() return not H.worldMode() end }),
  H.driveUntil(function() return rd(0x20) == 1 end, 1200,
    { H.call(function() H.setPad(H.frame % 16 < 4 and { "a" } or {}) end) },
    "aboard"),
  H.waitFrames(150),
  H.driveUntil(function() return landed end, 20000,
    { H.call(flyFrame) }, "landed at Crescent Mountain"),
  H.waitFrames(60),
  H.worldNavTo(214, 149, { maxFrames = 8000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  H.driveUntil(function() return not H.worldMode() end, 900,
    { H.call(function() H.setPad(H.frame % 16 < 4 and { up = true, a = true } or { up = true }) end) },
    "Crescent Mountain loads"),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(mapIs(167), true, "inside Crescent Mountain (map 167)")
  end),
  -- into the cave and off the ledge
  H.navTo(25, 25, { maxFrames = 9000, playBattles = "flee",
    arrive = function() return mapIs(168) end }),
  H.driveUntil(function() return mapIs(168) end, 900,
    { H.call(function() H.setPad({ down = true }) end) }, "into the dive cave"),
  H.waitFrames(60),
  -- the dive: step (8,11), ride the "Jump?" choice A-only
  (function()
    local t, talked = 0, false
    return {
      H.navTo(8, 11, { maxFrames = 6000, playBattles = "flee",
        arrive = function() return H.dialogWaiting() end }),
      H.driveUntil(function() return H.worldMode() end, 4000, {
        H.call(function()
          t = t + 1
          if H.dialogWaiting() then talked = true end
          if talked then
            H.setPad(t % 24 < 3 and { "a" } or {})
          else
            H.setPad({})
          end
        end),
      }, "dove into the Serpent Trench"),
    }
  end)(),
  H.waitFrames(90),
  H.call(function()
    H.log(string.format("riding the trench: worldId=%d", H.readWord(0x1f64) & 0xFF))
    H.screenshot("trench_ride")
  end),
  -- ride it out: battles fought tactically, forks left alone, until the
  -- ride ends (back on a field map = Nikeah, or the WoB world)
  (function()
    local battN, hb = 0, -600
    return H.driveUntil(function()
      local w = H.readWord(0x1f64)
      return (w & 0x1ff) >= 3 and not H.battleActive()
    end, 40000, {
      H.call(function()
        battN = H.battleLoadStarted() and battN + 1 or 0
        if battN == 0 then tactical.idle() end
        if H.frame - hb >= 900 then
          hb = H.frame
          H.log(string.format("  trench f%d w=%04X dances=%02X",
            H.frame, H.readWord(0x1f64), dances()))
        end
        if battN >= 3 then tactical.frame(); return end
        if H.dialogWaiting() then H.setPad(H.frame % 16 < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, "the trench ride ends")
  end)(),
  H.waitFrames(120),
  H.call(function()
    H.log(string.format("RONDO RESULT: dances %02X -> %02X map=%d (%d,%d)",
      d0, dances(), H.mapId() & 0x3ff, H.fieldX(), H.fieldY()))
    H.screenshot("rondo_done")
    H.assertEq(dances() ~= d0, true,
      "Mog learned a dance on the water (Water Rondo)")
  end),
  H.saveState("wob_rondo_done.mss"),
  H.logStep(function() return "done" end),
}))
