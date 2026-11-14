-- gen_wob_fc_gigantos.lua -- a branch beside the Floating Continent (#285, docs/design/wob-towns-boxes.md section
-- 4): boot `fc_landing` (TERRA, LOCKE and EDGAR on map 394 at the landing save point (7,12)), take SHADOW in at
-- (10,16) and dress him as gen_fc_alcove does, cross to the floor switch at (44,11) (_cad62f, $01F5: it lays the
-- tiles that reach the box; the route's own crossing never steps on it), and win the monster box at 394 (48,15)
-- (treasure bit 95, event battle group 37: formation 170, Gigantos $0AE alone).  No leg boots what it leaves (the
-- state `wob_fc_gigantos`); gen_fc_alcove goes on from fc_landing.
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, SHADOW, EDGAR = 0x00, 0x01, 0x03, 0x04
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [SHADOW] = "SHADOW", [EDGAR] = "EDGAR" }
local FOUR = { TERRA, LOCKE, SHADOW, EDGAR }
local MAP_FC = 394
-- the route's crossing up to the bridge switch (40,12), then the box's switch (44,11) (lab: from (44,11) the
-- box's south side (48,16) is on foot; before it no side is)
local TRIGS = { { 19, 12 }, { 25, 19 }, { 40, 12 }, { 44, 11 } }
local AVOID = { { 60, 11 }, { 70, 29 } }
local FIGHT = { tactical = true, boost = true, bank = 2, items = true, healPercent = 50 }
H.NAV_REFIRE_HOLD = true
local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, say, kitLine, partyOf, sw = K.map, K.say, K.kitLine, K.partyOf, K.sw

-- gen_fc_alcove's kit for SHADOW (present in the bag -> worn, absent -> kept, logged)
local function kitSteps(char, name, pairs_)
  local steps = {}
  local ip = H.sym("ItemProp") & 0x3FFFFF
  for _, p in ipairs(pairs_) do
    local slot, item = p[1], p[2]
    local tag = string.format("%s FC kit slot %d", name, slot)
    local function secondHand()
      for r = 4, 5 do
        local id = H.readByte(0x1600 + 37 * char + 0x1F + r)
        if id ~= 0xFF and (H.readRomByte(ip + id * 30 + 12) & 0x10) ~= 0 then return true end
      end
      return false
    end
    steps[#steps + 1] = H.cond(function()
      return H.invSlotOf(item) ~= nil and (slot ~= 1 or (H.readRomByte(ip + item * 30) & 7) ~= 1 or secondHand())
    end, { H.equipLoadout(char, { { slot, item } }, { tag = tag, optional = true }) },
      { H.logStep(string.format("%s: $%02X not in the bag; keeping current gear", tag, item)) })
  end
  return H.seqStep(steps)
end

-- SHADOW at (10,16), from (10,15) facing down or (9,16) facing right (gen_fc_alcove's talk)
local function shadowJoins()
  local out = {}
  for _, c in ipairs({ { 10, 15, "down" }, { 9, 16, "right" } }) do
    local t = 0
    out[#out + 1] = H.cond(function() return partyOf(SHADOW) == 0 end, {
      H.navTo(c[1], c[2], { maxFrames = 9000, playBattles = "tactical", fight = FIGHT }),
      H.withReset(H.driveUntil(function() return partyOf(SHADOW) ~= 0 or t > 600 end, 1200, {
        H.call(function()
          t = t + 1
          if H.battleActive() or H.battleLoadStarted() then H.setPad({}); return end
          if H.dialogWaiting() then H.setPad(t % 24 < 3 and { "a" } or {}); return end
          if not H.hasControl() or H.fieldX() ~= c[1] or H.fieldY() ~= c[2] then H.setPad({}); return end
          local ph = t % 40
          if ph < 2 then H.setPad({ [c[3]] = true })
          elseif ph >= 10 and ph < 14 then H.setPad({ "a" })
          else H.setPad({}) end
        end),
      }, string.format("SHADOW joins from (%d,%d)", c[1], c[2])), function() t = 0 end),
      H.release(),
    }, {})
  end
  out[#out + 1] = H.advanceStory(function() return H.hasControl() and H.tileAligned() and not H.dialogWaiting() end,
    6000, { playBattles = "tactical", fight = FIGHT })
  out[#out + 1] = H.call(function()
    H.assertEq(partyOf(SHADOW) ~= 0, true, "SHADOW joined at the (10,16) talk")
    say("fc", "SHADOW in")
  end)
  return H.seqStep(out)
end

local function cross()
  local steps = {}
  for _, t in ipairs(TRIGS) do
    local near = false
    steps[#steps + 1] = H.withReset(H.navTo(t[1], t[2], { maxFrames = 20000, playBattles = "tactical", fight = FIGHT,
      avoid = AVOID, arrive = function()
        if H.fieldX() == t[1] and H.fieldY() == t[2] then near = true end
        return near
      end }), function() near = false end)
    steps[#steps + 1] = H.advanceStory(function()
      return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
    end, 15000, { playBattles = "tactical", fight = FIGHT })
    steps[#steps + 1] = H.waitFrames(60)   -- the tiles land after the trigger's waits (lab: none at once, all by 60)
    steps[#steps + 1] = H.call(function() say("fc", string.format("the switch (%d,%d)", t[1], t[2])) end)
    -- no menu after the bridge switches (40,12) and (44,11): the field reloads the map when a menu closes, and
    -- the tiles _cad550 and _cad62f lay are gone with the reload ($01F2 and $01F5 are the map's scratch switches)
    if t[1] < 40 then
      steps[#steps + 1] = H.fieldCare({ threshold = 0.8, tag = string.format("after (%d,%d)", t[1], t[2]) })
    end
  end
  return H.seqStep(steps)
end

local won = nil
H.run({ maxFrames = 400000 }, {
  H.loadState("build/states/fc_landing.mss.lua"),
  K.watches(),
  H.call(function()
    H.assertEq(map(), MAP_FC, "booted on the Floating Continent (map 394; gen_fc_landing's state)")
    say("fc", "boot")
  end),
  -- @@setup-end

  -- @@stage shadow
  H.setRows({ [TERRA] = true, [EDGAR] = true, [LOCKE] = false }, { tag = "fc rows (gen_fc_alcove's)" }),
  shadowJoins(),
  kitSteps(SHADOW, "SHADOW", { { 4, 0xD1 }, { 0, 0x01 }, { 0, 0x04 }, { 0, 0x05 }, { 1, 0x01 }, { 1, 0x04 },
    { 2, 0x69 }, { 2, 0x6B }, { 3, 0x84 }, { 3, 0x8A }, { 5, 0xB3 } }),
  H.setRows({ [SHADOW] = true }, { tag = "SHADOW to the back row" }),
  H.fieldCare({ threshold = 0.95, tag = "care on landing" }),
  H.call(function() H.log("[kit] " .. kitLine(FOUR)) end),

  -- @@stage cross
  cross(),
  H.call(function()
    H.assertEq(H.bfsPath(48, 16) ~= nil, true, "the box's south side (48,16) on foot once (44,11) is stepped on")
  end),

  -- @@stage box
  -- Against the box, no Steal: LOCKE's treasure-hunt line spends turns that take 0 off a 6000-HP, 5-shield body,
  -- and every action draws its counter (key be90 was lost that way, gigantos/s0 attempt 1).  The blades lead.
  -- Set here, not in FIGHT's table, so the walk to the box plays as before (FIGHT is read live).
  H.call(function() FIGHT.locke = false end),
  K.monsterBox({ x = 48, y = 15, bit = 95, form = 170, species = 0x0AE, what = "the Gigantos box (394 (48,15))",
    avoid = AVOID, done = function(line) won = line end }),
  H.call(function()
    say("fc", "after the box")
    H.log("[kit] " .. kitLine(FOUR))
  end),
  H.saveState("wob_fc_gigantos.mss"),
  H.logStep(function()
    return string.format("wob_fc_gigantos generated: map %d (%d,%d), TERRA L%d LOCKE L%d SHADOW L%d EDGAR L%d, "
      .. "the Gigantos box: %s", map(), H.fieldX(), H.fieldY(), K.lv(TERRA), K.lv(LOCKE), K.lv(SHADOW), K.lv(EDGAR),
      tostring(won))
  end),
})
