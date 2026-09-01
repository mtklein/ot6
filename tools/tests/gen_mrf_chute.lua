-- gen_mrf_chute.lua -- mrf_entry (MAGITEK FACTORY map 262, {28,8}) -> the
-- conveyor chute at {19,25} -> the factory's lower half, control back at
-- {10,45}.  Generates mrf_chute.mss.
--
-- The upper floor is one connected region on foot, but everything below
-- y~27 is unreachable except through the chute.  The {19,25} trigger is
-- ungated and walks the party over non-walkable tiles to {10,45}, one
-- tile west of the {11,45} trigger the upper floor could not reach.
-- Stepping onto {19,23}/{19,24} on the way in is harmless: they are
-- door-frame animations guarded by the once-per-tile latch $01B5.

local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

local MAP_TITLE_PTRS, MAP_TITLE = 0x268400, 0x0EF100
local function mapTitleHere()
  local p = H.readRomWord(MAP_TITLE_PTRS + H.readByte(0x0520) * 2)
  local a, s = MAP_TITLE + p, ""
  for _ = 1, 24 do
    local c = H.readRomByte(a)
    if c == 0 then break end
    if     c >= 0x20 and c <= 0x39 then s = s .. string.char(65 + c - 0x20)
    elseif c >= 0x3A and c <= 0x53 then s = s .. string.char(97 + c - 0x3A)
    elseif c >= 0x54 and c <= 0x5D then s = s .. string.char(48 + c - 0x54)
    elseif c == 0x65 then s = s .. "."
    elseif c == 0x7F then s = s .. " "
    else s = s .. string.format("<%02X>", c) end
    a = a + 1
  end
  return s
end

local CHARS = { "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN",
                "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU",
                "GOGO", "UMARO" }
local function partyReport(tag)
  local party, raw = {}, {}
  local cur = H.readByte(0x1A6D)
  for c = 0, 13 do
    local b = H.readByte(0x1850 + c)
    raw[#raw + 1] = string.format("%s=%02X", CHARS[c + 1], b)
    if (b & 0x07) == cur and b ~= 0 then
      local base = 0x1600 + 37 * c
      party[#party + 1] = string.format("%s(order %d, L%d, weapon %02X)",
        CHARS[c + 1], (b >> 3) & 3, H.readByte(base + 0x08),
        H.readByte(base + 0x1F))
    end
  end
  return string.format("[party @ %s] party#%d = %s   | $1850: %s | $1EDE=%02X $1EDF=%02X",
    tag, cur, table.concat(party, ", "), table.concat(raw, " "),
    H.readByte(0x1EDE), H.readByte(0x1EDF))
end

local DELTA = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }

-- Tap `dir` whenever the party has control, hold off while a scene controls
-- it, edge-A through dialogs.  Used to walk into a trigger whose scene then
-- takes over; the tap keeps the party from sliding past the tile.
local function tapInto(dir, pred, maxFrames, what)
  local phase, n, ph, calm, hb = 0, 0, 0, 0, 0
  return H.driveUntil(function()
    calm = (pred() and settled()) and calm + 1 or 0
    return calm >= 16
  end, maxFrames or 12000, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if hb % 120 == 0 then
        H.log(string.format("tapInto f%d (%d,%d) phase=%d ctl=%s algn=%s "
          .. "dlg=%s ev=%s $01B5=%d face=%d",
          H.frame, H.fieldX(), H.fieldY(), phase, tostring(H.hasControl()),
          tostring(H.tileAligned()), tostring(H.dialogWaiting()),
          tostring(H.eventRunning()), sw(0x01B5),
          H.readByte(0x087f + H.readWord(0x0803))))
      end
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true }); phase = 0; return
      end
      if H.dialogWaiting() then
        H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
      end
      if phase == 0 then
        H.setPad({})
        -- Stop tapping once the party is on the target tile: the
        -- terminator needs 16 consecutive calm frames there, and a
        -- further tap would walk off it before the count completes.
        if pred() then return end
        if settled() then phase, n = 1, 0 end
        return
      end
      if phase == 1 then
        n = n + 1
        H.setPad({ [dir] = true })
        if n >= 8 then phase, n = 2, 0 end
        return
      end
      H.setPad({})
      n = n + 1
      if n >= 24 then phase = 0 end
    end),
  }, what)
end

local function census(tag, targets)
  local sx, sy = H.fieldX(), H.fieldY()
  local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
  local seen, q, qi = { [(sy & ym) * 256 + (sx & xm)] = true }, { { sx, sy } }, 1
  while qi <= #q and qi <= 3000 do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    for d, v in pairs(DELTA) do
      if H.canStep(x, y, d) then
        local nx, ny = (x + v[1]) & xm, (y + v[2]) & ym
        local k = ny * 256 + nx
        if not seen[k] then seen[k] = true; q[#q + 1] = { nx, ny } end
      end
    end
  end
  H.log(string.format("[census %s] from (%d,%d) on map %d: %d tiles reachable",
    tag, sx, sy, map(), #q))
  for _, t in ipairs(targets or {}) do
    local p = H.bfsPath(t[1], t[2])
    H.log(string.format("[census %s] -> (%d,%d) %-34s : %s", tag, t[1], t[2],
      t[3] or "", p and (#p .. " steps: " .. table.concat(p, " ")) or "NO PATH"))
  end
end

local CROSS_ATTEMPTS = 6
local L = H.newSeedLadder("mrf crossing", { attempts = CROSS_ATTEMPTS })
local crossed, crossLost, crossBlob = false, nil, nil

local function crossBody()
  return H.cond(function() return crossLost == nil end, {
    -- 1. across the upper floor to {19,22}, one tile above the door frames.
    H.navTo(19, 22, { maxFrames = 50000, playBattles = "tactical",
      wipeEndsRide = true,
      arrive = function() return H.fieldY() >= 40 end }),
    H.call(function()
      if H.partyWiped() then
        crossLost = string.format("wiped crossing the upper floor near (%d,%d)",
          H.fieldX(), H.fieldY())
        H.log("[mrf crossing] LOST -- " .. crossLost)
      end
    end),
    H.cond(function() return crossLost == nil end, {
      H.navTo(19, 22, { maxFrames = 18000, playBattles = "tactical",
        wipeEndsRide = true }),                       -- doors
      H.call(function()
        if H.partyWiped() then
          crossLost = "wiped at the door frames"
          H.log("[mrf crossing] LOST -- " .. crossLost)
        end
      end),
    }, {}),
    H.cond(function() return crossLost == nil end, {
      H.call(function()
        H.assertEq(H.fieldX(), 19, "above the chute x")
        H.assertEq(H.fieldY(), 22, "above the chute y")
        H.log(string.format("[chute] poised at (%d,%d)", H.fieldX(), H.fieldY()))
        H.screenshot("mrf_chute_entry")
      end),
      -- 2. three tapped DOWN steps: {19,23} and {19,24} animate the door open,
      --    {19,25} is the chute and takes the party over.
      tapInto("down", function() return H.fieldX() == 10 and H.fieldY() == 45 end,
        16000, "DOWN through the door frames onto the chute -> (10,45)"),
      H.call(function()
        if H.fieldX() == 10 and H.fieldY() == 45 and not H.partyWiped() then
          crossed = true
          H.log(string.format("[mrf crossing] rode the chute to (10,45)"))
        else
          crossLost = string.format("chute ride ended at (%d,%d)%s",
            H.fieldX(), H.fieldY(), H.partyWiped() and " (wiped)" or "")
          H.log("[mrf crossing] LOST -- " .. crossLost)
        end
      end),
    }, {}),
  }, {})
end

local function crossAttempt(n)
  local ldReq
  return H.cond(function() return not crossed end, {
    H.logStep(function()
      return string.format("[mrf crossing] ATTEMPT %d of %d begins at f%d%s",
        n, CROSS_ATTEMPTS, H.frame,
        n > 1 and (" (prior loss: " .. tostring(crossLost) .. ")") or "")
    end),
    -- attempts past the first rewind to the full-healed pre-crossing
    -- checkpoint; the spread below then takes a different battle-RNG phase.
    H.cond(function() return n > 1 end, {
      H.call(function() ldReq = H.requestLoadState(crossBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(ldReq, "mrf crossing attempt " .. n) end),
      H.waitFrames(60),
    }, {}),
    H.call(function() crossLost = nil end),
    L.spread(n),                          -- spread the battle RNG phase (#83)
    crossBody(),
  }, {})
end

-- allowGameOver: the crossing ladder deliberately loses attempts and
-- reloads the full-healed crossBlob before taking the next battle-RNG
-- phase, so a wipe's Game Over is expected.  Correctness is ground-truth
-- guarded: every attempt rewinds to a known-good party, `crossed` only
-- flips on the real (10,45) landing, and assertPartyStanding is the exit
-- contract.
H.run({ maxFrames = 400000, allowGameOver = true }, {
  H.loadState("build/states/mrf_entry.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(mapTitleHere(), "MAGITEK FACTORY", "booted in the MAGITEK FACTORY")
    H.assertEq(map(), 262, "booted on map 262")
    H.assertEq(H.fieldX(), 28, "boot x")
    H.assertEq(H.fieldY(), 8, "boot y")
    -- Positive control for the step itself: the chute's landing zone must be
    -- unreachable on foot at this point.  If it becomes reachable, this
    -- generator is walking a route it treats as a ride, and the assertion
    -- below that the party ended at (10,45) would no longer mean anything.
    H.assertEq(H.bfsPath(10, 45), nil,
      "CONTROL: (10,45) is NO-PATH on foot from the landing -- the chute "
      .. "is the only way down")
    H.log(partyReport("mrf_entry"))
  end),

  -- 0. Care, before the crossing.

  -- Threshold 0.85 rather than a boss step's 0.95: what follows is trash
  -- encounters and a scripted ride.
  H.fieldCare({ tag = "care before the upper-floor crossing",
                threshold = 0.85 }),

  -- Capture the pre-crossing checkpoint: the full-healed party at the
  -- landing, the retry ladder's rewind point.  Nothing is written to the
  -- game; this is just this boot's own state.
  (function()
    local req
    return H.cond(function() return true end, {
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "pre-crossing checkpoint capture")
        crossBlob = req.blob
        H.log(string.format("pre-crossing checkpoint captured (%d bytes) at "
          .. "(%d,%d) f%d", #crossBlob, H.fieldX(), H.fieldY(), H.frame))
      end),
    }, {})
  end)(),

  L.watch(),
  crossAttempt(1),
  crossAttempt(2),
  crossAttempt(3),
  crossAttempt(4),
  crossAttempt(5),
  crossAttempt(6),
  L.report(),
  H.call(function()
    if not crossed then
      error(string.format("the Magitek Factory upper-floor crossing was not "
        .. "survived in %d seed-ladder attempts (last loss: %s).  If every "
        .. "phase loses even from a full-healed party, that is a balance "
        .. "finding about this pincer, not a route bug -- capture the numbers.",
        CROSS_ATTEMPTS, tostring(crossLost)), 0)
    end
  end),

  H.waitFrames(60),
  H.call(function()
    H.assertEq(mapTitleHere(), "MAGITEK FACTORY", "still in the MAGITEK FACTORY")
    H.assertEq(map(), 262, "still on map 262 -- the chute is intra-map")
    H.assertEq(H.fieldX(), 10, "chute exit x (obj_script move list)")
    H.assertEq(H.fieldY(), 45, "chute exit y")
    H.assertEq(sw(0x0069), 0, "$0069 still CLEAR")
    H.log(string.format("[mrf_chute] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.log(partyReport("mrf_chute"))
  end),

  -- The repair half of the care stop: whatever the winning crossing cost
  -- is fixed here rather than shipped downstream.
  H.fieldCare({ tag = "care after the crossing", threshold = 0.85 }),
  H.call(function()
    -- The exit contract: a failure here means the crossing cost more
    -- than the bag could answer.
    H.assertPartyStanding("mrf_chute exit")
    H.screenshot("mrf_chute")
  end),
  H.saveState("mrf_chute.mss"),

  -- 3. census of the lower half, so the next step is planned from measurement.
  H.call(function()
    census("mrf_chute", {
      { 11, 45, "_cc78d0" },
      { 22, 53, "the scripted 263 transition _cc7651" },
      { 22, 54, "its twin _cc765f" },
      { 10, 54, "_cc7682 lift down" },
      { 6, 31, "_cc76a7 lift up" },
      { 12, 60, "short entrance -> 263 (12,7)" },
      { 15, 60, "long entrance -> 263 (15,9)" },
      { 21, 27, "_cc781b" },
      { 4, 22, "platform hop west _cc76cc" },
      { 9, 22, "platform hop east _cc76f1" },
    })
  end),
  H.logStep(function()
    return string.format("mrf_chute generated at frame %d -- map 262 (10,45), "
      .. "below the one-way chute", H.frame)
  end),
})
