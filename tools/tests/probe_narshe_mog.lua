-- probe_narshe_mog.lua -- fly to NARSHE and recruit MOG via the Lone
-- Wolf chase (#133 item 3).
--
-- Decoded route (event_trigger/npc_prop/entrance data, all step-on):
--   world (84,33) -> town 20 (38,61)
--   door (52,37) -> treasure room 30 arriving ON the intro trigger
--     (79,17): Lone Wolf appears [$0239]
--   back out (79,18) -> 20 (52,39); trigger (49,37) [$023A]
--   trigger row (37..39,20) [$023B]; top edge (34..39,1) -> 21 (26,50)
--   trigger row (30..32,22) [$023C]; 21 top edge (34..37,1) -> 22 (19,39)
--   22 top edge (18..21,1) -> 23 (25,31)
--   trigger (22,20) [$023D]; triggers (8..10,18) resolve the cliff
--     standoff [$023F: Lone Wolf and MOG hang from the ledge]
--   MOG's npc at (9,16) (_ccd5df, needs $023F=1): talking to him takes
--     Mog over the Gold Hairpin -- the routed choice -- and he JOINS.
-- Gates verified in the fixture: $0070=1 (chase open), $0239..$023F=0,
-- WoB.  Boots from wob_tzen_done.mss (on the world beside the ship at
-- Tzen); saves wob_mog_done.mss on the world outside Narshe.
local H = dofile("tools/tests/lib/ot6.lua")
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function fineX() return ((rd(0x35) << 16) | H.readWord(0x33)) end
local function fineY() return ((rd(0x39) << 16) | H.readWord(0x37)) end
local function sw(bit) return (H.readByte(0x1E80 + (bit >> 3)) >> (bit & 7)) & 1 end
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
local function mogIn()
  -- $1850+char = party-assignment byte; nonzero low bits = in a party.
  -- $02FA/$02EA are the roster switches _ccd5df sets when Mog is taken.
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
  -- the chase
  edge(52, 37, "up", 30, "into the treasure room"),
  stage(79, 17, function() return sw(0x239) == 1 end, "Lone Wolf intro [$0239]",
    { maxFrames = 4000 }),
  edge(79, 18, "down", 20, "back to town"),
  stage(49, 37, function() return sw(0x23A) == 1 end, "chase [$023A]"),
  stage(38, 20, function() return sw(0x23B) == 1 end, "chase [$023B]"),
  edge(36, 2, "up", 21, "north to map 21"),
  stage(31, 22, function() return sw(0x23C) == 1 end, "chase [$023C]"),
  edge(35, 2, "up", 22, "north to map 22"),
  edge(19, 2, "up", 23, "north to the cliff (map 23)"),
  stage(22, 20, function() return sw(0x23D) == 1 end, "the standoff [$023D]"),
  stage(8, 18, function() return sw(0x23F) == 1 end, "the ledge [$023F]"),
  -- take MOG (over the Gold Hairpin: the routed choice).  Stand EXACTLY
  -- at (9,17) facing up: MOG hangs at (9,16), Lone Wolf at (9,15) -- and
  -- talking to Lone Wolf instead takes the Hairpin and DROPS Mog.
  H.navTo(9, 17, { maxFrames = 6000, playBattles = "flee" }),
  (function()
    local phase = 0
    return H.driveUntil(function() return mogIn() end, 9000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
        H.setPad(phase < 4 and { up = true, a = true } or { up = true })
      end),
    }, "MOG joins")
  end)(),
  H.call(function()
    H.log("MOG RECRUITED")
    H.screenshot("mog_joined")
  end),
  -- out of Narshe: cliff -> back down is a long walk; save right here on
  -- the cliff instead -- the next leg can walk out itself
  H.saveState("wob_mog_done.mss"),
  H.logStep(function() return "done" end),
}))
