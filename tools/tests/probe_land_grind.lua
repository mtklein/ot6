-- probe_land_grind.lua -- fly the Blackjack to the Chimera grind pocket and
-- land there, closed-loop (#132).
--
-- probe_grind proved the technique (Y-strafe + B) with a blind snake search
-- that happened to set down on a location entrance (Sabin's house, map 93).
-- This probe replaces the search with a decoded destination: the WoB world
-- encounter data (world_battle_group.dat, sector col X96-127 / row Y0-31,
-- grass slot -> group 22) puts the Chimera+Cephaler pack (formation 190,
-- 1572 XP, ~62.5% of rolls; rest is 3x Cephaler; no pincer-capable
-- formation in the group) on the walkable-and-landable grass pocket at
-- world tiles X 113-119 / Y 25-26 (tile prop $0044: bit1 clear = airship
-- may land, bit4 clear = passable on foot, bit6 set = battles, high byte
-- 0 = grass bg).  Nearest location entrance is (114,17), eight tiles north
-- across mountains ($0053), so a landing here cannot repeat the map-93
-- surprise.
--
-- Flying is closed-loop on the airship position registers (X fine
-- $33-$35, Y fine $37-$39, tile = fine>>12; LandAirship computes the
-- set-down tile with the same shift, init.asm@93f6).  Y-strafe angles are
-- HEADING-RELATIVE (ctrl.asm StrafeAngleTbl: angle = table[dpad] + $73),
-- so the probe first calibrates each dpad direction with one measured
-- burst and then always presses the button whose measured world direction
-- best matches the remaining error vector -- no assumption about what the
-- post-liftoff heading is.
--
-- Phases:
--   A  board the deck, lift off, settle (probe_grind's proven opening);
--   B  calibrate 4 strafe bursts, fly to tile (116,25), land with B
--      (bounce -> sidestep to the next $0044 candidate and retry),
--      save wob_grind.mss;
--   C  verify the encounter zone live: pace the pocket until one random
--      battle fires, log its formation words (want Chimera $01f and/or
--      Cephaler $096), then flee it (L+R, the engine's own mechanic; both
--      formations are runnable -- no pincer bit in battle_prop).
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function fineX() return ((rd(0x35) << 16) | H.readWord(0x33)) end
local function fineY() return ((rd(0x39) << 16) | H.readWord(0x37)) end
local function tileX() return (fineX() >> 12) & 0xFF end
local function tileY() return (fineY() >> 12) & 0xFF end

-- $0044 tiles of the pocket, nearest-first: land target then fallbacks
local CAND = { {116,25},{117,25},{115,25},{114,25},{118,25},{119,25},
               {116,26},{117,26},{115,26},{118,26},{113,25},{114,26} }

-- Execution truth for the dead-B mystery: count how often the input chain
-- actually runs.  Addresses are bank $EE (world program) label offsets:
-- MoveVehicle @1998, GetVehicleInput @6bec, the non-strafe B check @6d22,
-- the common-tail B check @7045, LandAirship @936e.
local hits = { mv = 0, gvi = 0, b1 = 0, b2 = 0, land = 0 }
local lastPad05 = -1
emu.addMemoryCallback(function() hits.mv = hits.mv + 1 end,
  emu.callbackType.exec, 0xEE1998, 0xEE1998)
emu.addMemoryCallback(function() hits.gvi = hits.gvi + 1 end,
  emu.callbackType.exec, 0xEE6BEC, 0xEE6BEC)
emu.addMemoryCallback(function()
  hits.b1 = hits.b1 + 1
  lastPad05 = emu.read(0x05, emu.memType.snesMemory)
end, emu.callbackType.exec, 0xEE6D22, 0xEE6D22)
emu.addMemoryCallback(function() hits.b2 = hits.b2 + 1 end,
  emu.callbackType.exec, 0xEE7045, 0xEE7045)
emu.addMemoryCallback(function() hits.land = hits.land + 1 end,
  emu.callbackType.exec, 0xEE936E, 0xEE936E)
local function hitStr()
  return string.format("mv=%d gvi=%d b1=%d($05=%02X) b2=%d land=%d",
    hits.mv, hits.gvi, hits.b1, lastPad05, hits.b2, hits.land)
end

-- Phase B controller state
local DIRS = { "up", "down", "left", "right" }
local cal = {}            -- button -> {dx,dy} measured fine-units/frame
local mode = "calib"      -- calib -> travel -> rhythm -> done
local calI, calT, calX, calY = 1, 0, 0, 0
local rhyT = 0
local candI = 1
local landed = false

local function target()
  local c = CAND[candI]
  return c[1] * 4096 + 2048, c[2] * 4096 + 2048
end

local function bestDir(ex, ey)
  -- button whose calibrated direction has the largest dot product with
  -- the error vector
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
    if calT <= 45 then H.setPad({}); return end     -- stop dead, then measure
    cal[d] = { x = (fineX() - calX) / 30, y = (fineY() - calY) / 30 }
    H.log(string.format("calib %-5s -> (%.0f,%.0f) fine/frame", d,
      cal[d].x, cal[d].y))
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
  -- probe_grind's proven land cadence, verbatim rhythm: a SHORT strafe burst,
  -- release, then B.  A B pressed after a long continuous strafe hold is
  -- ignored (measured: $19 stays 0, $c2 goes stale for ~200 frames -- the
  -- input path is not polled), so the burst right before the press is part
  -- of the technique, not decoration.
  if mode == "rhythm" then
    rhyT = rhyT + 1
    if rhyT <= 10 then                  -- burst toward the candidate center
      local wx, wy = target()
      local d = bestDir(wx - fineX(), wy - fineY())
      H.setPad(d and { y = true, [d] = true } or {})
      return
    end
    if rhyT <= 22 then H.setPad({}); return end
    if rhyT <= 28 then H.setPad({ b = true }); return end
    H.setPad({})
    -- Landed = the world program is back with the party ON FOOT beside the
    -- parked ship: vehicle type $20 leaves 1 (airship).  NOT $1f64 bit13 --
    -- that bit stays set for a world-map landing ($1f64=2400, measured);
    -- probe_grind's onFoot() only worked because its landing set down on a
    -- location entrance, which loads a FIELD map and rewrites $1f64.
    if rd(0x20) ~= 1 and H.worldHasControl() then landed = true; return end
    local t = rhyT - 28
    if t % 60 == 0 and t <= 120 then
      H.log(string.format(
        "  land try %d f%d: $19=%d veh=%02X tile=(%d,%d) c2=%02X %s",
        candI, t, rd(0x19), rd(0x20), tileX(), tileY(), rd(0xc2), hitStr()))
    end
    if t >= 480 then                    -- bounced; try the next candidate
      H.log(string.format("land at (%d,%d) bounced (c2=%02X); next candidate",
        tileX(), tileY(), rd(0xc2)))
      candI = candI + 1
      if candI > #CAND then error("every landing candidate bounced") end
      mode = "travel"
    end
    return
  end
end

-- Phase C controller: pace the pocket, log + flee the first encounter
local paceDir = "left"
local battN, sawWords, fledOne = 0, false, false
local function paceFrame()
  battN = H.battleLoadStarted() and battN + 1 or 0
  if battN >= 3 then
    if not sawWords then
      sawWords = true
      local w = H.formationWords()
      H.log(string.format(
        "grindzone battle up: species %04X %04X %04X %04X %04X %04X "
        .. "(want Chimera 001F / Cephaler 0096)", w[1], w[2], w[3], w[4], w[5], w[6]))
    end
    H.setPad({ l = true, r = true })     -- runnable pool: no pincer bit set
    return
  end
  if sawWords and battN == 0 and H.worldHasControl() then
    fledOne = true
    H.setPad({})
    return
  end
  if not H.worldHasControl() then H.setPad({}); return end
  local x = H.worldX()
  if x <= 114 then paceDir = "right" elseif x >= 118 then paceDir = "left" end
  H.setPad({ [paceDir] = true })
end

local steps = {
  -- Phase A: probe_grind's proven opening, verbatim
  H.loadState("build/states/iaf_deck.mss.lua"),
  H.waitFrames(4),
  H.navTo(15, 8, { maxFrames = 1500, arrive = function() return H.dialogWaiting() end }),
  H.pressButtons({ "down" }, 3), H.waitFrames(8),
  H.pressButtons({ "a" }, 4), H.waitFrames(150),
  H.call(function()
    H.log(string.format("airborne at tile (%d,%d), heading %d", tileX(), tileY(),
      H.readWord(0x73)))
  end),
  -- Engage A-thrust once before any strafing: probe_grind's proven run always
  -- flew under A power after liftoff and its B presses landed; without this
  -- leg B never triggers LandAirship at all ($19 stays 0 through every try,
  -- measured twice).  Heading is 0 post-liftoff, so a short thrust drifts
  -- north a few tiles; the closed-loop travel corrects afterwards.
  H.hold({ "a" }), H.waitFrames(120), H.release(), H.waitFrames(30),
  H.call(function()
    H.log(string.format("post-thrust at (%d,%d) spd=%04X", tileX(), tileY(),
      H.readWord(0x26)))
  end),
  -- Phase B: calibrate, fly, land, save
  H.driveUntil(function() return landed end, 12000,
    { H.call(flyFrame) }, "airship landed in the grind pocket"),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("LANDED 1f64=%04X veh=%02X world=(%d,%d)",
      H.readWord(0x1f64), rd(0x20), H.worldX(), H.worldY()))
    H.screenshot("grind_landed")
  end),
  H.call(function()
    H.assertEq(rd(0x20) ~= 1, true, "party out of the airship after landing")
    H.assertEq(H.readWord(0x1f64) & 0x1ff, 0, "still on the WoB world map")
    local x, y = H.worldX(), H.worldY()
    H.assertEq(x >= 112 and x <= 121 and y >= 23 and y <= 28, true,
      "landed inside the grind pocket")
  end),
  H.saveState("wob_grind.mss"),
  -- Phase C: one paced encounter, identified and fled
  H.driveUntil(function() return fledOne end, 8000, { H.call(paceFrame) },
    "one grind-pocket encounter identified and fled"),
  H.call(function()
    H.log(string.format("verified: encounter drew and released at (%d,%d)",
      H.worldX(), H.worldY()))
    H.screenshot("grind_verified")
  end),
  H.logStep(function() return "done" end),
}
H.run({ maxFrames = 26000 }, steps)
