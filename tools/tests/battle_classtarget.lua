-- @suite slow
-- battle_classtarget.lua -- #161: the tactical driver aims a plain boost-Fight
-- at the monster its weapon class breaks, not the engine's default cursor.
--
-- The fixture is kolts_cave (map 96, the Mt. Kolts Cirpius pool).  Its
-- weakness codex does NOT know Cirpius yet: a first Cirpius fight opens
-- with no class shown (`encounter 1: s2=086 sh=2 crev=00 ...` on main,
-- build/attempts/wt/draw-budgets/lab/draw-budgets/baseline_classtarget.log).
-- A pierce hit on a Cirpius teaches the codex (Ot6ClassChip stores the
-- class to OT6_CODEX_CLASS), and every later Cirpius fight opens with
-- pierce shown on every Cirpius slot (Ot6SeedShields pre-reveals it).  Walking the spawn tile's lane (the same
-- oscillation gen_kolts_cave verifies the pool with) draws map 96's
-- encounters; the mixed one -- Tusker (no class key) beside Cirpius x3
-- (pierce) -- is the #157 picture: TERRA holds a MithrilKnife (pierce),
-- LOCKE and EDGAR MithrilBlades (slash).  A pierce hand should Fight a
-- Cirpius; a slash hand has no key here.
--
-- Which encounter deals the mixed formation is not the fixture's to
-- choose: map 96's group deals it at 80/256 (the pool is read from the ROM
-- below, H.encounterPool), and the save's encounter counter decides when.
-- Every regeneration of the chain moves that counter, so the hunt takes
-- the mixed formation only ONCE PIERCE IS KNOWN (a mixed fight that opens
-- before then is fought -- which teaches -- and the lane walks on), and its
-- encounter budget is the most any counter state needs to deal an
-- all-Cirpius formation (which teaches) and after it the mixed one
-- (H.worstCaseEncounters), not the handful this fixture happens to need.
-- Every lane encounter that is not the one is fought out and followed by
-- a field-care stop (H.careStop), as after any battle on the route: the
-- hunt can fight a couple of dozen battles, and nothing it checks needs
-- the party worn down.
--
-- What it checks, on the real fight the lane reaches:
--   1. selection: the driver's chipAim aims the pierce hand (TERRA) at a
--      pierce-keyed Cirpius, not the unkeyed Tusker, and gives a slash hand
--      (LOCKE) no target at all (nil).
--   2. negative control: opts.aim = false stubs the pick back to the old
--      shape in place -- chipAim then returns nil, the engine's default
--      cursor -- and the "aims at a Cirpius" assertion goes red.
--   3. the aim's effect (A/B from one snapshot, Tools off so the pierce
--      Fight is the only Cirpius chipper): through the whole fight, aim-on
--      never aims TERRA's Fight at the unkeyed Tusker while a pierce-keyed
--      Cirpius stands, and aim-off, the old shape, does -- each Fight's
--      target read at the engine's hand-off of the confirmed input
--      (GetPlayerTargets).  The pierce chips landed on a Cirpius (counted
--      at Ot6ClassChip's store), the Cirpius broken and the frames each
--      branch's fight took from its own restore are logged beside it, not
--      asserted; why is at the A/B below.
--
-- Reads only, save for the coherent battle snapshot the A/B branches from
-- (requestSaveState / requestLoadState); no RAM is edited, so this is a
-- measured fight, not a synthetic setup.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"
local MAP = 96

local TUSKER, CIRPIUS = 0x07A, 0x086
local PIERCE = 0x02

-- ---- the lane's pool, and the encounter budget it implies ------------------
-- A slot is MIXED when every formation it can deal holds a Tusker and a
-- Cirpius, and TEACHES when every one is Cirpius alone (every target a
-- Cirpius, so the party's first pierce hit lands on one).
local POOL = H.encounterPool(H.fieldEncounterGroup(MAP))
local MIXED, TEACHES = {}, {}
for slot = 1, 4 do
  local mixed, teaches = true, true
  for _, f in ipairs(POOL[slot].formations) do
    local c, t, other = false, false, false
    for _, sp in ipairs(f.species) do
      if sp == CIRPIUS then c = true elseif sp == TUSKER then t = true else other = true end
    end
    mixed = mixed and c and t
    teaches = teaches and c and not t and not other
  end
  MIXED[slot], TEACHES[slot] = mixed, teaches
end
local BUDGET, HIST = H.worstCaseEncounters(function()
  local taught = false
  return function(slot)
    if taught and MIXED[slot] then return true end
    if TEACHES[slot] then taught = true end
    return false
  end
end)

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

-- ---- pierce chips on a Cirpius, at the ROM's own store --------------------
-- Ot6ClassChip (ot6_break.asm) is where a landed hit's class chip happens:
-- `dec a / sta OT6_SHIELD_CUR,y` is its one store to a shield cell, so a
-- write to a monster's cell ($3E40 + 2*slot, OT6_SHIELD_CUR + 8) made from
-- inside that routine is exactly one chip.  It is a PIERCE chip when the
-- attack's class (OT6_ATKCLASS, $57B8) and the target's class weaknesses
-- (OT6_BP_CLASS + 8, $3EA4 + 2*slot) share the pierce bit -- the match the
-- routine itself made.  The routine's end is the next proc in the file,
-- Ot6RevealCommit.  Reads only; `branchRecord` is the record of the branch
-- being measured, nil outside one.
local SH_CUR, BP_CLASS, ATKCLASS = 0x3E40, 0x3EA4, 0x57B8
local CLASSCHIP, CLASSCHIP_END = H.sym("Ot6ClassChip"), H.sym("Ot6RevealCommit")
assert(CLASSCHIP < CLASSCHIP_END and CLASSCHIP_END - CLASSCHIP < 0x100,
  "Ot6RevealCommit follows Ot6ClassChip in the ROM (the chip store's pc range)")
local branchRecord = nil
emu.addMemoryCallback(function(addr)
  if branchRecord == nil then return end
  local off = addr - (0x7E0000 + SH_CUR)
  if off % 2 ~= 0 then return end
  local st = emu.getState()
  local pc = (st["cpu.k"] << 16) | st["cpu.pc"]
  if pc < CLASSCHIP or pc >= CLASSCHIP_END then return end
  local slot = off // 2
  if speciesAt(slot) ~= CIRPIUS then return end
  if (H.readByte(ATKCLASS) & H.readByte(BP_CLASS + slot * 2) & PIERCE) == 0 then return end
  branchRecord.chips = branchRecord.chips + 1
  branchRecord.on[slot] = (branchRecord.on[slot] or 0) + 1
end, emu.callbackType.write, 0x7E0000 + SH_CUR, 0x7E0000 + SH_CUR + 11)

-- ---- where the pierce hand's Fights were aimed ----------------------------
-- GetPlayerTargets (battle_main.asm) turns a confirmed menu input into an
-- action: X = the actor's entity offset, Y = its input-queue offset, and
-- the queue holds the command ($2BAF), attack ($2BB0) and the target word
-- the cursor confirmed ($2BB1: characters low, monsters high).  Each Fight
-- TERRA confirms is recorded with the monster it was aimed at and whether
-- a pierce-keyed Cirpius stood at that moment -- the input the aim
-- changes, read at the engine's own hand-off.
local TERRA_ENT = nil       -- TERRA's entity offset, set when the fight is found
do
  local gpt = H.sym("GetPlayerTargets")
  emu.addMemoryCallback(function()
    if branchRecord == nil or TERRA_ENT == nil then return end
    local st = emu.getState()
    local x, y = st["cpu.x"] & 0xFFFF, st["cpu.y"] & 0xFFFF
    if x ~= TERRA_ENT or H.readByte(0x2BAF + y) ~= 0x00 then return end
    local mons = (H.readWord(0x2BB1 + y) >> 8) & 0x3F
    local slot = nil
    for s = 0, 5 do if mons == (1 << s) then slot = s end end
    local keyed = false
    for s = 0, 5 do
      if alive(s) and speciesAt(s) == CIRPIUS and (classRev(s) & PIERCE) ~= 0 then keyed = true end
    end
    local at = slot and speciesAt(slot) or nil
    branchRecord.fights[#branchRecord.fights + 1] = string.format("%s%s",
      slot and string.format("s%d=%03X", slot, at) or string.format("mask%02X", mons),
      keyed and "" or "(no keyed Cirpius)")
    if keyed and at ~= CIRPIUS then branchRecord.offKey = branchRecord.offKey + 1 end
  end, emu.callbackType.exec, gpt, gpt)
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

-- Is the encounter now the mixed formation -- a Cirpius beside a Tusker?
-- Only that one exercises the pick; a uniform pool (Cirpius x3) leaves
-- chipAim nil by design.
local function mixedNow()
  return firstSlot(CIRPIUS) ~= nil and firstSlot(TUSKER) ~= nil
end
-- Does this fight open with the Cirpius' pierce class already shown (the
-- codex pre-reveal, taught by an earlier fight on this lane)?
local function pierceKnown()
  local c = firstSlot(CIRPIUS)
  return c ~= nil and (classRev(c) & PIERCE) == PIERCE
end

-- ---- state carried across the step list ----------------------------------
local S = { found = false, blob = nil, terra = nil, locke = nil,
            cirp = nil, tusk = nil, ab = {}, seen = {} }

-- one measured A/B branch, from the restore that starts it: drive to the
-- end of the fight with Tools off so the pierce Fight is the only thing
-- that can chip a Cirpius, and record the pierce chips that landed on a
-- Cirpius (branchRecord), how many Cirpius broke, and how many frames the
-- fight took from the restored snapshot.
local function measure(name, aim)
  local F = H.newFightDriver(name, { tactical = true, boost = true, items = true,
    bank = 0, healPercent = 55, tools = false, aim = aim })
  local out = S.ab[name]
  return H.seqStep({
    H.call(function()
      out.broke, out.chips, out.on, out.fights, out.offKey = {}, 0, {}, {}, 0
      TERRA_ENT = S.terra * 2
      branchRecord = out
    end),
    H.driveUntil(function() return not H.battleLoadStarted() end, 40000, {
      H.call(function()
        F.frame()
        for s = 0, 5 do
          if alive(s) and speciesAt(s) == CIRPIUS and broken(s) then out.broke[s] = true end
        end
      end),
    }, name .. " drive"),
    H.call(function()
      branchRecord = nil
      out.frames = H.frame - out.restored
      out.nbroke = 0
      for _ in pairs(out.broke) do out.nbroke = out.nbroke + 1 end
      local per = {}
      for s = 0, 5 do
        if out.on[s] then per[#per + 1] = string.format("s%d:%d", s, out.on[s]) end
      end
      H.log(string.format("[classtarget] %s: pierce chips on a Cirpius=%d (%s), cirpius "
        .. "broken=%d, fight took %d frames from the restored snapshot (f%d..f%d); TERRA's "
        .. "Fights aimed at: %s -- %d off the key while a keyed Cirpius stood", name,
        out.chips, #per > 0 and table.concat(per, " ") or "none", out.nbroke, out.frames,
        out.restored, H.frame, #out.fights > 0 and table.concat(out.fights, " ") or "none",
        out.offKey))
    end),
  })
end

-- lane-walk to the next encounter; classify it.  The mixed formation with
-- pierce already shown is snapshotted and stops the hunt; anything else --
-- a uniform pool, or the mixed one before pierce is known -- is fought out
-- with the ordinary driver (which is what teaches) and the lane resumes.
local function huntStep(i)
  return H.cond(function() return not S.found end, {
    H.driveUntil(function() return H.battleLoadStarted() or S.found end, 40000, {
      H.call(laneStep), H.waitFrames(1),
    }, "lane to encounter " .. i),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 1500, "battle " .. i .. " active", 20),
    H.waitFrames(150),
    H.call(function()
      local mixed, known = mixedNow(), pierceKnown()
      S.seen[#S.seen + 1] = string.format("%d:%s%s", i, mixed and "mixed" or "uniform",
        known and "+pierce" or "")
      H.log(string.format("[classtarget] encounter %d: %s mixed=%s pierce-known=%s%s",
        i, formationText(), tostring(mixed), tostring(known),
        (mixed and not known) and " -- fought to teach, not taken" or ""))
      if mixed and known then
        S.found = true
        S.at = i
        S.terra = actorOf(0); S.locke = actorOf(1)
        S.cirp = firstSlot(CIRPIUS); S.tusk = firstSlot(TUSKER)
        H.screenshot("classtarget_mixed")
        S.req = H.requestSaveState()
      end
    end),
    -- not the one: fight it out with the ordinary driver, care for the
    -- party on the field, then walk on
    H.cond(function() return not S.found end, {
      (function()
        local F = H.newFightDriver("skip" .. i, { tactical = true, boost = true, items = true, bank = 0, healPercent = 55 })
        return H.driveUntil(function() return not H.battleLoadStarted() end, 40000, {
          H.call(function() F.frame() end),
        }, "clear encounter " .. i)
      end)(),
      H.waitFrames(60),
      H.careStop("care after lane encounter " .. i),
    }, {}),
  }, {})
end

local steps = {
  H.waitFrames(20), H.loadState(STATE), H.waitFrames(20),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, MAP, "booted in the Mt. Kolts cave (map 96)")
    -- the hands this fixture carries to the mountain
    H.assertEq(H.weaponClass(H.readByte(0x1600 + 37 * 0 + 0x1F)), PIERCE,
      "TERRA holds a pierce weapon (MithrilKnife)")
    H.assertEq(H.weaponClass(H.readByte(0x1600 + 37 * 1 + 0x1F)), 0x01,
      "LOCKE holds a slash weapon (MithrilBlade)")
    -- the pool, as the ROM deals it, and the budget it implies
    local anyMixed, anyTeach = false, false
    for slot = 1, 4 do
      local e, parts = POOL[slot], {}
      for _, f in ipairs(e.formations) do
        local names = {}
        for _, sp in ipairs(f.species) do names[#names + 1] = string.format("%03X", sp) end
        parts[#parts + 1] = string.format("%d [%s]", f.id, table.concat(names, " "))
      end
      H.log(string.format("[classtarget] map %d group %d slot %d (%d/256): %s%s", MAP,
        POOL.group, slot, e.odds, table.concat(parts, ", "),
        MIXED[slot] and " MIXED" or (TEACHES[slot] and " teaches" or "")))
      anyMixed = anyMixed or MIXED[slot]
      anyTeach = anyTeach or TEACHES[slot]
    end
    H.assertEq(anyMixed and anyTeach, true,
      "map 96's pool deals both an all-Cirpius formation and the Tusker+Cirpius one")
    H.log(string.format("[classtarget] budget: %d encounters -- the most any encounter-counter "
      .. "state needs to deal an all-Cirpius formation and then the mixed one "
      .. "(%.1f%% of states need 8 or fewer, %.1f%% 16 or fewer)", BUDGET,
      100 * H.encounterShare(HIST, 8), 100 * H.encounterShare(HIST, 16)))
  end),
}
for i = 1, BUDGET do steps[#steps + 1] = huntStep(i) end

steps[#steps + 1] = H.call(function()
  H.assertEq(S.found, true, string.format(
    "the mixed Cirpius formation, with pierce already known, was reached within %d lane "
    .. "encounters, the most any encounter-counter state needs (encounters: %s) -- "
    .. "an all-Cirpius fight that did not teach pierce shows here as a uniform with no "
    .. "+pierce after it", BUDGET, table.concat(S.seen, " ")))
  H.assertEq(S.terra ~= nil and S.locke ~= nil, true, "TERRA and LOCKE are in the fight")
  H.assertEq(S.cirp ~= nil and S.tusk ~= nil, true,
    "the formation pairs a Cirpius with a Tusker")
  -- the pierce key is shown on the Cirpius, and the Tusker shows no class
  H.assertEq(classRev(S.cirp) & PIERCE, PIERCE,
    "the Cirpius opens with its pierce class revealed (the codex, taught on this lane)")
  H.assertEq(classRev(S.tusk) & 0x0F, 0,
    "the Tusker shows no revealed class -- nothing a hand can break")
end)

steps[#steps + 1] = H.waitFrames(5)
steps[#steps + 1] = H.call(function() H.checkReq(S.req, "battle snapshot"); S.blob = S.req.blob end)

-- restore the coherent opening snapshot; both A/B branches start here, and
-- each branch's clock starts at its own restore
local function restoreOpening(name)
  local what = name .. " branch"
  return H.seqStep({
    H.call(function() S.load = H.requestLoadState(S.blob) end),
    H.waitFrames(3),
    H.call(function() H.checkReq(S.load, what); S.ab[name].restored = H.frame end),
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

-- 3. the aim's effect, A/B from the one snapshot.  What the aim changes is
-- where the pierce hand's Fight is aimed: counted at the engine's own
-- hand-off of each confirmed input (GetPlayerTargets, above), aim-on
-- never aims TERRA's Fight at the unkeyed Tusker while a pierce-keyed
-- Cirpius stands, and aim-off -- the engine's default cursor -- does, on
-- this fight.  Across twelve different mixed fights (lab copies that flee
-- 0, 1, 2, 3, 4, 5, 6, 8, 10, 13, 16 and 21 lane encounters before the
-- body, so the hunt starts that far along the encounter counter:
-- build/attempts/wt/draw-budgets-fix/lab/classtarget/final/ct_pre*.log,
-- `[classtarget] A/B`), aim-on aimed 0 of its 3 to 5 Fights off the key
-- and aim-off 1 to 3 of its 4 or 5, every time: once the Cirpius the
-- default cursor starts on falls, the cursor sits on the Tusker.
-- What is not asserted, and why.  The pierce chips landed on a Cirpius
-- came out aim-on 4 against aim-off 4 in six of those fights, 5 in four
-- and 3 in two -- a Cirpius takes two chips and then breaks, and the
-- default cursor's first target is a Cirpius as well -- so "aim-on lands
-- more chips" held in two of twelve (and failed seven of eight as an
-- assertion: build/attempts/wt/draw-budgets-fix/lab/classtarget/r1/
-- summary.tsv).  The frames each fight took, from its own restore, ran
-- 0.70 to 1.07 of aim-off's, above 1 twice.  (An older form compared
-- H.frame at each branch's end; H.frame runs on across a restore and
-- aim-off ran second, so "sooner" held by construction.)
steps[#steps + 1] = (function()
  S.ab["aim-on"], S.ab["aim-off"] = {}, {}
  return H.seqStep({
    restoreOpening("aim-on"),
    measure("aim-on", true),
    restoreOpening("aim-off"),
    measure("aim-off", false),
    H.call(function()
      local a, b = S.ab["aim-on"], S.ab["aim-off"]
      H.log(string.format("[classtarget] A/B: TERRA Fights aimed off the key while a keyed "
        .. "Cirpius stood %d of %d vs %d of %d; pierce chips on a Cirpius %d vs %d; cirpius "
        .. "broken %d vs %d; frames from the restore %d vs %d (on/off %.3f)", a.offKey,
        #a.fights, b.offKey, #b.fights, a.chips, b.chips, a.nbroke, b.nbroke, a.frames,
        b.frames, a.frames / b.frames))
      H.assertEq(#a.fights > 0, true, "TERRA Fought in the aim-on branch (the count below is "
        .. "not vacuous)")
      H.assertEq(a.offKey, 0, string.format("aim-on never aims TERRA's Fight at the unkeyed "
        .. "Tusker while a pierce-keyed Cirpius stands (%d Fights)", #a.fights))
      H.assertEq(b.offKey > a.offKey, true, string.format("and the old shape does, on this "
        .. "fight: the A/B separates (%d of %d vs %d of %d)", b.offKey, #b.fights, a.offKey,
        #a.fights))
    end),
  })
end)()

H.run({ maxFrames = 300000 }, steps)
