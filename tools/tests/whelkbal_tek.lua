-- @manual Whelk TekMissile chip measurement instrument, run by hand
-- whelkbal_tek.lua -- the tutorial's first mechanical win, driven live:
-- TekMissile (flags3 $20, skill class PIERCE) chips the Whelk head's
-- authored shields 4 -> 3.
--
-- Drive: whelk entry point -> fight -> dismiss the opening dialog -> spend
-- non-terra menus on Heal Force (self-target) -> when terra's menu comes up,
-- walk her 2x4 magitek grid to the bottom-right cell (TekMissile) and fire.
-- Laps rotate a target nudge (none/down/up) so the missile finds the head
-- whichever part the cursor defaults to.
--
-- The head has a fire weakness (Ot6ElemAddTbl), so a beam also chips it.
-- Heal Force is self-target and moves no gauge, so the missile is the only
-- thing in the fight that can chip, which keeps the attribution to
-- TekMissile.  The head's alive/element-reveal state is asserted at the
-- end as the proof that no beam ever landed on it.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/whelk_entry.mss.lua"
local WHELK = { [0x0134] = true }
local function whelk()
  return H.battleLoadStarted() and H.formationHas(WHELK)
end

local MENU, ACTOR = 0x7bca, 0x62ca
local MHP = 0x3bfc
local SPEC, CHID = 0x57c0, 0x3ed8
local hs, ss, terra
local function headShields() return H.readByte(0x3E40 + hs * 2) end
local function headCRev() return H.readByte(0x3EA5 + hs * 2) end

local function sram(addr) return emu.read(addr, emu.memType.snesMemory) end

-- The codex is per save slot: the active page follows wSaveSlotToLoad
-- ($7e021f) -- 1/2/3 map to $000/$400/$800 and anything else, which
-- includes a New Game, uses the transient page OT6_CODEX_TEMP = $0c00.
local CODEX_ROOT, CODEX_CLASS, CODEX_TEMP = 0x316000, 0x0190, 0x0c00
local function codexPage()
  local slot = H.readByte(0x021f)
  if slot == 1 then return 0x0000 end
  if slot == 2 then return 0x0400 end
  if slot == 3 then return 0x0800 end
  return CODEX_TEMP
end
local function codexClass(sp)
  return sram(CODEX_ROOT + codexPage() + CODEX_CLASS + sp)
end

local classWrites = {}
local function headElemRev() return H.readByte(0x3E91 + hs * 2) end
local function headHp() return H.readWord(MHP + hs * 2) end

-- one cast lap per menu: non-terra menus spend their turn on Heal Force,
-- which is self-target and moves no gauge, so nothing but the missile can
-- chip; terra's menu walks to TekMissile with this lap's target nudge
local lap = 0
local function castStep(donePred, budget, what)
  local streak, idx, stall, mySeq, noMenu = 0, 0, 0, nil, 0
  return H.driveUntil(donePred, budget, {
    H.call(function()
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
          -- Heal Force is (2,0) in both magitek lists and self-targets by
          -- default; (1,1) is a blank cell the cursor can wedge on.
          mySeq = { "a", "down", "down", "a", "a" }
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
    return hs ~= nil and headShields() < 4
  end, 25000, "tekmissile chips the whelk head"),
  H.call(function() H.setPad({}) end),
  -- The shield write lands at damage-calc time; the reveal is committed
  -- later, on the damage frame's first numeral, with Ot6ActionEnd as the
  -- no-numeral backstop.  Fixed settle, not a wait-until: a waitUntil on
  -- the bit would make the assertion agree with itself.
  H.waitFrames(300),

  H.call(function()
    H.assertEq((classWrites[0x02] or 0) >= 1, true,
      "a PIERCING skill load resolved (nobody fights: only TekMissile)")
    H.assertEq(headShields(), 3, "head shields chipped 4 -> 3")
    H.assertEq(headCRev() & 0x02, 0x02, "piercing revealed on the head")
    -- the attribution, asserted rather than assumed: nothing but the missile
    -- touched the head, so its element axis is still undisclosed.  A beam
    -- landing on the fire-weak head would have turned this over, and the
    -- 4 -> 3 above would not have been the missile's.
    H.assertEq(headElemRev(), 0,
      "no beam ever landed on the head -- its element axis is still hidden, "
      .. "so the chip above is the TekMissile's")
    -- and it lived through the fight on its own 1600, with no HP written
    H.assertEq(headHp() > 0, true,
      "the head survived on its authored HP -- no pin, no re-heal")
    H.log(string.format("save slot $021f=%d -> codex page $%04x",
      H.readByte(0x021f), codexPage()))
    H.assertEq(codexClass(0x134) & 0x02, 0x02,
      "class codex learned piercing for species $134 on the active page")
    H.log(string.format("head shields=%d crev=%02x", headShields(), headCRev()))
    H.screenshot("whelkbal_tek_chip")
  end),
})
