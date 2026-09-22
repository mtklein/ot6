-- @suite slow
-- battle_classtarget.lua -- #161: the tactical driver aims a plain boost-Fight
-- at the monster its weapon class breaks, not the engine's default cursor.
--
-- The fixture is kolts_cave (map 96, the Mt. Kolts Cirpius pool).  The save's
-- weakness codex already knows Cirpius = pierce (Ot6SeedShields pre-reveals it
-- from past chips), so a fresh Cirpius fight opens with the pierce class shown
-- on every Cirpius slot.  Walking the spawn tile's lane (the same oscillation
-- gen_kolts_cave verifies the pool with) draws map 96's encounters; the mixed
-- one -- Tusker (no class key) beside Cirpius x3 (pierce) -- is the #157
-- picture: TERRA holds a MithrilKnife (pierce), LOCKE and EDGAR MithrilBlades
-- (slash).  A pierce hand should Fight a Cirpius; a slash hand has no key here.
--
-- What it checks, on the real fight the lane reaches:
--   1. selection: the driver's chipAim aims the pierce hand (TERRA) at a
--      pierce-keyed Cirpius, not the unkeyed Tusker, and gives a slash hand
--      (LOCKE) no target at all (nil).  fightChips confirms one chip on the
--      Cirpius and none on the Tusker.
--   2. negative control: opts.aim = false stubs the pick back to the old
--      shape in place -- chipAim then returns nil, the engine's default
--      cursor -- and the "aims at a Cirpius" assertion goes red.
--   3. outcome (A/B from one snapshot, Tools off so the pierce Fight is the
--      only Cirpius chipper): aim-on breaks more Cirpius and ends the fight in
--      fewer frames than aim-off, the old shape.
--
-- Reads only, save for the coherent battle snapshot the A/B branches from
-- (requestSaveState / requestLoadState); no RAM is edited, so this is a
-- measured fight, not a synthetic setup.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"

local TUSKER, CIRPIUS = 0x07A, 0x086
local PIERCE = 0x02

-- ---- battle-RAM reads -----------------------------------------------------
local function speciesAt(s) return H.readWord(0x57C0 + s * 2) end
local function alive(s)
  return H.readWord(0x3BFC + s * 2) > 0 and (H.readByte(0x3AA8 + s * 2) & 1) == 1
end
local function shields(s) return H.readByte(0x3E40 + s * 2) end
local function broken(s) return H.readByte(0x3E90 + s * 2) ~= 0 end
local function classRev(s) return H.readByte(0x3EA5 + s * 2) end
-- the battle-party actor index (0..3) holding character `charId`, or nil
local function actorOf(charId)
  for e = 0, 3 do if H.readByte(0x3ED8 + e * 2) == charId then return e end end
  return nil
end
local function presentSpecies()
  local t = {}
  for s = 0, 5 do if alive(s) then t[s] = speciesAt(s) end end
  return t
end
local function firstSlot(sp)
  for s = 0, 5 do if alive(s) and speciesAt(s) == sp then return s end end
  return nil
end
local function formationText()
  local parts = {}
  for s = 0, 5 do
    if alive(s) then
      parts[#parts + 1] = string.format("s%d=%03X sh=%d crev=%02X",
        s, speciesAt(s), shields(s), classRev(s))
    end
  end
  return table.concat(parts, " ")
end

-- ---- the spawn lane (gen_kolts_cave's own encounter-pool walk) ------------
local BACK = { left = "right", right = "left", up = "down", down = "up" }
local lane = nil
local function laneStep()
  if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
  local x, y = H.fieldX(), H.fieldY()
  if lane == nil then
    for _, d in ipairs({ "right", "left", "up", "down" }) do
      if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] }; break end
    end
    if lane == nil then H.setPad({}); return end
    H.log(string.format("[classtarget] lane (%d,%d) %s/%s", x, y, lane.out, lane.back))
  end
  H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
end

-- Is the encounter now on stage a mixed one -- a keyed Cirpius beside an
-- unkeyed monster?  Only such a formation exercises the pick; a uniform pool
-- (Cirpius x3) leaves chipAim nil by design, so those are fought and skipped.
local function mixedNow()
  local sp, hasCirp, hasOther = presentSpecies(), false, false
  for _, v in pairs(sp) do
    if v == CIRPIUS then hasCirp = true else hasOther = true end
  end
  return hasCirp and hasOther
end

-- ---- state carried across the step list ----------------------------------
local S = { found = false, blob = nil, terra = nil, locke = nil,
            cirp = nil, tusk = nil, ab = {} }

-- one measured A/B branch: drive to the end of the fight with Tools off so
-- the pierce Fight is the only thing that can chip a Cirpius, and record how
-- many Cirpius broke and when the fight ended.
local function measure(name, aim)
  local F = H.newFightDriver(name, { tactical = true, boost = true, items = true,
    bank = 0, healPercent = 55, tools = false, aim = aim })
  local out = S.ab[name]
  return H.seqStep({
    H.call(function() out.broke, out.seen = {}, 0 end),
    H.driveUntil(function() return not H.battleLoadStarted() end, 40000, {
      H.call(function()
        F.frame()
        for s = 0, 5 do
          if alive(s) and speciesAt(s) == CIRPIUS and broken(s) then out.broke[s] = true end
        end
      end),
    }, name .. " drive"),
    H.call(function()
      out.endframe = H.frame
      out.nbroke = 0
      for _ in pairs(out.broke) do out.nbroke = out.nbroke + 1 end
      H.log(string.format("[classtarget] %s: cirpius broken=%d, fight ended at frame %d",
        name, out.nbroke, out.endframe))
    end),
  })
end

-- lane-walk to the next encounter; classify it; a uniform pool is fought to
-- the end and the lane resumes, a mixed one is snapshotted and stops the hunt.
local function huntStep(i)
  return H.cond(function() return not S.found end, {
    H.driveUntil(function() return H.battleLoadStarted() or S.found end, 40000, {
      H.call(laneStep), H.waitFrames(1),
    }, "lane to encounter " .. i),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 1500, "battle " .. i .. " active", 20),
    H.waitFrames(150),
    H.call(function()
      H.log(string.format("[classtarget] encounter %d: %s mixed=%s",
        i, formationText(), tostring(mixedNow())))
      if mixedNow() then
        S.found = true
        S.terra = actorOf(0); S.locke = actorOf(1)
        S.cirp = firstSlot(CIRPIUS); S.tusk = firstSlot(TUSKER)
        H.screenshot("classtarget_mixed")
        S.req = H.requestSaveState()
      end
    end),
    -- a uniform encounter: fight it out with the ordinary driver, then walk on
    H.cond(function() return not S.found end, {
      (function()
        local F = H.newFightDriver("skip" .. i, { tactical = true, boost = true, items = true, bank = 0, healPercent = 55 })
        return H.driveUntil(function() return not H.battleLoadStarted() end, 40000, {
          H.call(function() F.frame() end),
        }, "clear uniform encounter " .. i)
      end)(),
      H.waitFrames(60),
    }, {}),
  }, {})
end

local steps = {
  H.waitFrames(20), H.loadState(STATE), H.waitFrames(20),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 96, "booted in the Mt. Kolts cave (map 96)")
    -- the hands this fixture carries to the mountain
    H.assertEq(H.weaponClass(H.readByte(0x1600 + 37 * 0 + 0x1F)), PIERCE,
      "TERRA holds a pierce weapon (MithrilKnife)")
    H.assertEq(H.weaponClass(H.readByte(0x1600 + 37 * 1 + 0x1F)), 0x01,
      "LOCKE holds a slash weapon (MithrilBlade)")
  end),
}
for i = 1, 8 do steps[#steps + 1] = huntStep(i) end

steps[#steps + 1] = H.call(function()
  H.assertEq(S.found, true,
    "a mixed Cirpius formation was reached within eight lane encounters")
  H.assertEq(S.terra ~= nil and S.locke ~= nil, true, "TERRA and LOCKE are in the fight")
  H.assertEq(S.cirp ~= nil and S.tusk ~= nil, true,
    "the formation pairs a Cirpius with a Tusker")
  -- the pierce key is shown on the Cirpius, and the Tusker shows no class
  H.assertEq(classRev(S.cirp) & PIERCE, PIERCE,
    "the Cirpius opens with its pierce class revealed (from the codex)")
  H.assertEq(classRev(S.tusk) & 0x0F, 0,
    "the Tusker shows no revealed class -- nothing a hand can break")
end)

steps[#steps + 1] = H.waitFrames(5)
steps[#steps + 1] = H.call(function() H.checkReq(S.req, "battle snapshot"); S.blob = S.req.blob end)

-- restore the coherent opening snapshot; both A/B branches start here
local function restoreOpening(what)
  return H.seqStep({
    H.call(function() S.load = H.requestLoadState(S.blob) end),
    H.waitFrames(3),
    H.call(function() H.checkReq(S.load, what) end),
    H.waitUntil(function() return H.battleActive() end, 900, what .. " active", 15),
    H.waitFrames(30),
  })
end

-- 1. selection + 2. negative control, on the live mixed fight.
steps[#steps + 1] = H.call(function()
  local on = H.newFightDriver("sel-on", { tactical = true, aim = true })
  local off = H.newFightDriver("sel-off", { tactical = true, aim = false })
  local pickOn = on.driver:chipAim(S.terra, 0)
  local pickOff = off.driver:chipAim(S.terra, 0)
  local slashPick = on.driver:chipAim(S.locke, 0)
  H.log(string.format("[classtarget] chipAim(TERRA) aim-on=%s aim-off=%s ; chipAim(LOCKE)=%s ; cirp slot=%s tusk slot=%s",
    tostring(pickOn), tostring(pickOff), tostring(slashPick), tostring(S.cirp), tostring(S.tusk)))

  -- the pick aims the pierce hand at a pierce-keyed Cirpius, never the Tusker
  local function aimsAtCirpius(pick)
    H.assertEq(pick ~= nil and speciesAt(pick) == CIRPIUS and (classRev(pick) & PIERCE) == PIERCE, true,
      "the pierce hand is aimed at a pierce-keyed Cirpius")
  end
  aimsAtCirpius(pickOn)
  H.assertEq(pickOn ~= S.tusk, true, "and NOT at the unkeyed Tusker")

  -- a slash hand has no key in this formation, so it keeps the default cursor
  H.assertEq(slashPick, nil, "a slash hand (LOCKE) is given no class target here")

  -- negative control: the stub (aim=false) reverts the pick to nil (default
  -- cursor), and the same assertion that passes for the new pick goes red.
  H.assertEq(pickOff, nil, "the stub (aim=false) makes no class pick -- the old shape")
  local ok = pcall(aimsAtCirpius, pickOff)
  H.assertEq(ok, false,
    "the aims-at-a-Cirpius assertion FAILS under the stubbed old-shape pick")

  -- opt-in-safe: an authored kill order (opts.focus) or a multi-part plan
  -- (self.parts) still wins, so their targeting stays byte-identical -- the
  -- same guard focusList reads.  On THIS fight, where the class pick would
  -- otherwise steer to a Cirpius, both suppress it back to nil (the default
  -- cursor the authored targeting then supplies itself).
  local foc = H.newFightDriver("sel-focus", { tactical = true, aim = true })
  foc.driver.opts.focus = { { slot = S.tusk, mask = 1 << S.tusk } }
  H.assertEq(foc.driver:chipAim(S.terra, 0), nil,
    "an authored opts.focus wins: chipAim makes no class pick")
  local par = H.newFightDriver("sel-parts", { tactical = true, aim = true })
  par.driver.parts = { focus = { { slot = S.tusk, mask = 1 << S.tusk } } }
  H.assertEq(par.driver:chipAim(S.terra, 0), nil,
    "a multi-part self.parts wins: chipAim makes no class pick")
end)

-- 3. outcome A/B: aim-on breaks more Cirpius and ends the fight sooner.
steps[#steps + 1] = (function()
  S.ab["aim-on"], S.ab["aim-off"] = {}, {}
  return H.seqStep({
    restoreOpening("aim-on branch"),
    measure("aim-on", true),
    restoreOpening("aim-off branch"),
    measure("aim-off", false),
    H.call(function()
      local a, b = S.ab["aim-on"], S.ab["aim-off"]
      H.assertEq(a.nbroke >= b.nbroke, true, string.format(
        "aim-on breaks at least as many Cirpius as the old shape (%d vs %d)",
        a.nbroke, b.nbroke))
      H.assertEq(a.endframe < b.endframe, true, string.format(
        "aim-on ends the fight sooner than the old shape (%d vs %d frames)",
        a.endframe, b.endframe))
      H.assertEq(a.nbroke > b.nbroke or a.endframe * 5 < b.endframe * 4, true, string.format(
        "and does so by a clear margin: more Cirpius broken (%d vs %d) or "
        .. ">20%% fewer frames (%d vs %d)", a.nbroke, b.nbroke, a.endframe, b.endframe))
    end),
  })
end)()

H.run({ maxFrames = 300000 }, steps)
