-- probe_jidoor.lua -- fly the leveled party to JIDOOR, buy the caster
-- relics, and scout the Auction House (#133 items 2 and 5).
--
-- Jidoor = map 198, world door (27,130) (gen_opera1_entry's measured
-- route; the first version of this probe flew to (120,187), which the
-- SHOW_TITLE banner revealed to be burned VECTOR -- its Gold-tier shops
-- are gone with the story).  The doorstep plain (24,129)-ish is landable
-- ($0044).  Inside: door (5,25) -> room 202, relic shop 23's keeper at
-- (54,16); door (26,27) -> room 200, the Auction House (auctioneer
-- _cb4e47 at (19,24), running when $006B=1 -- set on Setzer's join --
-- and $01F0=0).  Exit doors: 202 (54,23) -> 198 (5,27); 200 (18,26).
--
-- Buys (shop 23 rows): Earrings $c3 row 3 x2 (10000) for the bolt
-- casters, Sniper Sight $e3 row 5 x1 (3000).  Gil at boot 125,737; the
-- auction reserve stays fat because Golem+Zoneseek bidding is next.
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function fineX() return ((rd(0x35) << 16) | H.readWord(0x33)) end
local function fineY() return ((rd(0x39) << 16) | H.readWord(0x37)) end
local function tileX() return (fineX() >> 12) & 0xFF end
local function tileY() return (fineY() >> 12) & 0xFF end
local function gil() return H.readByte(0x1860) | (H.readByte(0x1861) << 8) | (H.readByte(0x1862) << 16) end

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
      H.log(string.format("land at (%d,%d) bounced (c2=%02X); next candidate",
        tileX(), tileY(), rd(0xc2)))
      candI = candI + 1
      if candI > #CAND then error("every landing candidate bounced") end
      mode = "travel"
    end
    return
  end
end

local function talkShop(name)
  local phase = 0
  return H.driveUntil(function() return H.readByte(0x26) == 0x25 end, 3000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      H.setPad(phase < 4 and { "up", "a" } or { "up" })
    end),
  }, name .. ": shop options open")
end
local function closeShop(name)
  local phase = 0
  return H.driveUntil(function() return H.hasControl() end, 3000, {
    H.call(function()
      phase = (phase + 1) % 8
      H.setPad(phase < 4 and { "b" } or {})
    end),
  }, name .. ": shop closed")
end

H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/wob_grind_done.mss.lua"),
  H.waitFrames(8),
  H.call(function() H.log(string.format("boot: gil=%d", gil())) end),
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
  H.call(function() H.log(string.format("landed world=(%d,%d)", H.worldX(), H.worldY())) end),
  H.worldNavTo(27, 130, { maxFrames = 6000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  H.driveUntil(function() return not H.worldMode() end, 900,
    { H.call(function() H.setPad(H.frame % 16 < 4 and { "a" } or {}) end) },
    "town map loads"),
  H.waitFrames(90),
  H.call(function()
    H.log(string.format("in town: map=%d field=(%d,%d)", H.mapId() & 0x3ff,
      H.fieldX(), H.fieldY()))
    H.screenshot("jidoor_arrival")
    H.assertEq(H.mapId() & 0x1ff, 198, "this is Jidoor (map 198)")
  end),
  -- relic shop 23: door (5,25) -> room 202, keeper (54,16)
  H.navTo(5, 25, { maxFrames = 12000, playBattles = "flee",
    arrive = function() return (H.mapId() & 0x1ff) == 202 end }),
  H.waitFrames(60),
  H.navTo(54, 17, { maxFrames = 6000 }),
  talkShop("relics"),
  H.buyItem(0xc3, 3, function() return 2 end, "Earrings x2"),
  H.buyItem(0xe3, 5, function() return 1 end, "Sniper Sight"),
  closeShop("relics"),
  H.call(function()
    H.log(string.format("relics bought: gil=%d earrings=%d sniper=%d",
      gil(), H.invCountOf(0xc3), H.invCountOf(0xe3)))
  end),
  -- back to town, then the Auction House door (26,27) -> room 200
  H.navTo(54, 23, { maxFrames = 6000, playBattles = "flee",
    arrive = function() return (H.mapId() & 0x1ff) == 198 end }),
  H.waitFrames(60),
  H.navTo(26, 27, { maxFrames = 12000, playBattles = "flee",
    arrive = function() return (H.mapId() & 0x1ff) == 200 end }),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("auction house: map=%d field=(%d,%d) gil=%d",
      H.mapId() & 0x3ff, H.fieldX(), H.fieldY(), gil()))
    H.screenshot("auction_house")
  end),
  H.saveState("wob_jidoor.mss"),
  H.logStep(function() return "done" end),
})
