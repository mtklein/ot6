-- whelkbal_tek.lua -- the tutorial's first mechanical win, live: TekMissile
-- (flags3 $20, skill class PIERCE) chips the Whelk head's authored shields
-- 4 -> 3. This is the exact hit the boss measurement caught dealing ~517
-- with ZERO shield movement under the whole-byte $f2 gate.
--
--   tools/tests/run.sh tools/tests/whelkbal_tek.lua build/states/whelkbal_tek.log
--
-- Drive: whelk doorstep -> fight -> dismiss the opening dialog -> burn
-- non-terra menus on their row-1 beam (classless, and the head has no
-- vanilla element weakness, so beams cannot move shields) -> when terra's
-- menu comes up, walk her 2x4 magitek grid to the bottom-right cell
-- (TekMissile) and fire. Laps rotate a target nudge (none/down/up) so the
-- missile finds the HEAD no matter which part the cursor defaults to.

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/whelk_doorstep.mss.lua"
local WHELK = { [0x0134] = true }
local function whelk()
  return H.battleLoadStarted() and H.formationHas(WHELK)
end

local MENU, ACTOR = 0x7bca, 0x62ca
local PHP, MHP = 0x3bf4, 0x3bfc
local SPEC, CHID = 0x57c0, 0x3ed8
local hs, ss, terra
local function headShields() return H.readByte(0x3E40 + hs * 2) end
local function headCRev() return H.readByte(0x3EA5 + hs * 2) end

local function sram(addr) return emu.read(addr, emu.memType.snesMemory) end

local classWrites = {}
local function keepalive()
  for c = 0, 2 do
    if H.readWord(PHP + c * 2) < 200 then H.writeWord(PHP + c * 2, 200) end
  end
  if hs then H.writeWord(MHP + hs * 2, 1600) end
end

-- one cast lap per menu: non-terra menus fire their row-1 beam; terra's
-- menu walks to TekMissile with this lap's target nudge
local lap = 0
local function castStep(donePred, budget, what)
  local streak, idx, stall, mySeq, noMenu = 0, 0, 0, nil, 0
  return H.driveUntil(donePred, budget, {
    H.call(function()
      keepalive()
      if H.readByte(MENU) == 0 then
        streak, idx, stall, mySeq = 0, 0, 0, nil
        noMenu = noMenu + 1
        H.setPad(noMenu % 2 == 0 and { "a" } or {})
        return
      end
      noMenu = 0
      streak = streak + 1
      if streak < 4 then H.setPad({}) return end
      if mySeq == nil then
        if H.readByte(ACTOR) == terra then
          mySeq = { "a", "down", "down", "down", "right", "a" }
          local nudge = lap % 3
          if nudge == 1 then mySeq[#mySeq + 1] = "down" end
          if nudge == 2 then mySeq[#mySeq + 1] = "up" end
          mySeq[#mySeq + 1] = "a"
          lap = lap + 1
        else
          mySeq = { "a", "a", "a" }
        end
        idx = 1
        H.log(string.format("f%d cast[%s] actor=%d seq=%s", H.frame, what,
          H.readByte(ACTOR), table.concat(mySeq, ",")))
      end
      if idx <= #mySeq then
        H.setPad({ mySeq[idx] })
        idx = idx + 1
        return
      end
      stall = stall + 1
      if stall > 2 then mySeq, stall = nil, 0; H.setPad({ "b" }) return end
      H.setPad({ "a" })
    end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(24),
  }, what)
end

local aPhase = 0
H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return whelk() end, 2600, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.battleLoadStarted() then H.setPad({}); return end
      if H.dialogWaiting() then
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
    end),
  }, "whelk event fires"),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 900, "whelk up", 30),
  H.waitFrames(240),

  H.call(function()
    for slot = 0, 5 do
      local sp = H.readWord(SPEC + slot * 2)
      if sp == 0x0134 then hs = slot end
      if sp == 0x0100 then ss = slot end
    end
    for c = 0, 3 do
      if H.readByte(CHID + c * 2) == 0 then terra = c end
    end
    H.assertEq(hs ~= nil and terra ~= nil, true, "head + terra found")
    H.assertEq(headShields(), 4, "head opens with the authored 4 shields")
    H.assertEq(H.readByte(0x3EA4 + hs * 2), 0x02, "head authored pierce-weak")
    emu.addMemoryCallback(function(addr, value)
      classWrites[value] = (classWrites[value] or 0) + 1
    end, emu.callbackType.write, 0x7E57B8, 0x7E57B8)
  end),

  -- dismiss the opening dialog ("VICKS: Hold it!") to the first menu
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 4000, {
    H.pressButtons({ "a" }, 4),
    H.waitFrames(56),
  }, "opening dialog dismissed (first menu up)"),
  H.call(function() H.setPad({}) end),
  H.waitFrames(150),

  -- fire tek missiles until the head's shields move
  castStep(function()
    keepalive()
    return hs ~= nil and headShields() < 4
  end, 25000, "tekmissile chips the whelk head"),
  H.call(function() H.setPad({}) end),
  H.waitFrames(40),

  H.call(function()
    H.assertEq((classWrites[0x02] or 0) >= 1, true,
      "a PIERCING skill load resolved (nobody fights: only TekMissile)")
    H.assertEq(headShields(), 3, "head shields chipped 4 -> 3")
    H.assertEq(headCRev() & 0x02, 0x02, "piercing revealed on the head")
    H.assertEq(sram(0x316190 + 0x134) & 0x02, 0x02,
      "class codex learned piercing for species $134")
    H.log(string.format("head shields=%d crev=%02x", headShields(), headCRev()))
    H.screenshot("whelkbal_tek_chip")
  end),
})
