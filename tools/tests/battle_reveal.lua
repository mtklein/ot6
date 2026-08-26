-- @suite
-- battle_reveal.lua -- the reveal-gate regression test: enemy weakness icons
-- must show '?' until actually revealed, never leak from a dirty seed.
--
-- Ot6SeedShields ORs the persistent codex into the reveal masks $3e89
-- (elements) and $3e9d (classes); it must zero those masks itself before
-- the merge, since a Cmd_20 scene-change reload re-runs the seed without
-- InitBattle's own clear.
--
-- This test arms a one-shot memory callback that stamps every monster's
-- reveal masks to $FF the instant Ot6SeedShields starts, reproducing the
-- state a Cmd_20 reload or uninitialized RAM would hand the seed, then
-- boots the Whelk head fight and asserts every mask reads hidden despite
-- the garbage, and that a real fire chip reveals only the fire axis while
-- the head's class-weak PIERCE axis stays hidden.
--
-- Fixture: whelk_entry. The head ($0134) is authored fire-weak with 4
-- shields and class-weak PIERCE ($02); the shell ($0100) is class-weak
-- $00.  Addresses, all +slot*2 off the monster slot the body lands in:
-- revealed elements $3E91, revealed classes $3EA5, broken timer $3E90,
-- class-weak mask $3EA4, weak elements $3BE8, shields $3E40, HP $3BFC,
-- presence $3AA8, status-1 $3EEC, species $57C0.  HUD shadow line for
-- slot s is H.shadowLine(s); the four weakness cells are the low bytes
-- at +6/+8/+10/+12 ('?' = $BF, fire = $EB).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/whelk_entry.mss.lua"

local REVEAL, RCLASS, TIMER, CWEAK = 0x3E91, 0x3EA5, 0x3E90, 0x3EA4
local WEAK, SHLD = 0x3BE8, 0x3E40
local ALIVE, MSTAT, SPEC = 0x3AA8, 0x3EEC, 0x57C0
local MENU, ACTOR, CHID = 0x7BCA, 0x62CA, 0x3ED8
local HEAD_SP, SHELL_SP = 0x0134, 0x0100
local CHAR_TERRA = 0x00

local hs, ss, terra                  -- head slot, shell slot, Terra's slot

local function present(slot) return (H.readByte(ALIVE + slot * 2) & 1) == 1 end
local function wcell(slot, k) return H.readByte(H.shadowLine(slot) + 6 + k * 2) end
local function headAlive()
  return present(hs) and (H.readByte(MSTAT + hs * 2) & 0xC2) == 0
end

-- One-shot: re-dirty every monster reveal mask the instant the seed begins.
local SEED = H.sym("Ot6SeedShields")
local seedRef
local function armSeedDirtier()
  local fired = false
  seedRef = emu.addMemoryCallback(function()
    if fired then return end
    fired = true
    for slot = 0, 5 do
      emu.write(0x3e91 + slot * 2, 0xFF, emu.memType.snesWorkRam)  -- revealed elems
      emu.write(0x3ea5 + slot * 2, 0xFF, emu.memType.snesWorkRam)  -- revealed classes
      emu.write(0x3e90 + slot * 2, 0xFF, emu.memType.snesWorkRam)  -- broken timer
      emu.write(0x3ea4 + slot * 2, 0xFF, emu.memType.snesWorkRam)  -- class-weak mask
    end
    emu.removeMemoryCallback(seedRef, emu.callbackType.exec, SEED, SEED)
  end, emu.callbackType.exec, SEED, SEED)
end

-- ------------------------------------------------------------- driver --
-- only Terra beams; no beam is ever spent on the shell (MegaVolt counter is lethal)
local BEAM = { "a", "a", "a" }
local HEAL = { "a", "down", "down", "a", "a" }
local mStreak, mSeq, mIdx, mStall, mNoMenu = 0, nil, 1, 0, 0
local beamsOrdered = 0

local function policyPulse()
  if H.readByte(MENU) == 0 then
    mStreak, mSeq, mIdx, mStall = 0, nil, 1, 0
    mNoMenu = mNoMenu + 1
    return mNoMenu % 2 == 0 and { "a" } or {}
  end
  mNoMenu = 0
  mStreak = mStreak + 1
  if mStreak < 4 then return {} end
  if mSeq == nil then
    if H.readByte(ACTOR) == terra and headAlive() then
      beamsOrdered = beamsOrdered + 1
      mSeq = BEAM
    else
      mSeq = HEAL
    end
    mIdx = 1
  end
  if mIdx <= #mSeq then
    local b = mSeq[mIdx]
    mIdx = mIdx + 1
    return { b }
  end
  mStall = mStall + 1
  if mStall > 2 then
    mSeq, mStall = nil, 0
    return { "b" }
  end
  return { "a" }
end

local pulseAge = 29
local function pulseTick()
  pulseAge = (pulseAge + 1) % 30
  if pulseAge == 0 then
    H.setPad(policyPulse())
  elseif pulseAge == 6 then
    H.setPad({})
  end
end

local aPhase = 0

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function()
    armSeedDirtier()
    H.log(string.format("armed seed-entry mask dirtier at $%06X "
      .. "(the quarantined write -- see header)", SEED))
  end),

  -- walk onto the trigger tile
  H.driveUntil(function()
    return H.battleLoadStarted() and H.monstersPresent() > 0
  end, 2600, {
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

  -- the scripted intro re-uploads the small font and veils the hud while it
  -- runs; wait for a font-whole, un-veiled hud (first battle menu open)
  H.driveUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(0x64d5) == 0
       and H.fieldHudPresent()
  end, 6000, {
    H.call(function()
      if H.readByte(MENU) == 0 then H.setPad({ "a" }) else H.setPad({}) end
    end),
    H.waitFrames(10), H.release(), H.waitFrames(10),
  }, "whelk intro dismissed, menu up, hud font whole"),
  H.waitFrames(120),

  H.call(function()
    H.assertEq(H.formationHas({ [HEAD_SP] = true }), true, "whelk head fight")
    for slot = 0, 5 do
      local sp = H.readWord(SPEC + slot * 2)
      if sp == HEAD_SP then hs = slot end
      if sp == SHELL_SP then ss = slot end
    end
    H.assertEq(hs ~= nil, true, "the head has a monster slot")
    H.assertEq(ss ~= nil, true, "the shell has a monster slot")
    for s = 0, 3 do
      if H.readByte(CHID + s * 2) == CHAR_TERRA then terra = s end
    end
    H.assertEq(terra ~= nil, true, "TERRA has a party slot (the only beamer)")
    H.log(string.format("head slot %d, shell slot %d, terra slot %d",
      hs, ss, terra))
  end),

  -- 1. the check: garbage was handed to the seed and the codex is virgin, so
  -- every un-chipped weakness must still read hidden and draw '?'.
  H.call(function()
    local checked, sawAuthored, sawZero = 0, false, false
    for slot = 0, 5 do
      if present(slot) then
        local sp   = H.readWord(SPEC + slot * 2)
        local relm = H.readByte(REVEAL + slot * 2)
        local rcls = H.readByte(RCLASS + slot * 2)
        local brk  = H.readByte(TIMER + slot * 2)
        local clsW = H.readByte(CWEAK + slot * 2)
        H.log(string.format("slot%d sp=%d revE=%02X revC=%02X brk=%02X clsW=%02X cells=%02X,%02X,%02X,%02X",
          slot, sp, relm, rcls, brk, clsW,
          wcell(slot, 0), wcell(slot, 1), wcell(slot, 2), wcell(slot, 3)))
        H.assertEq(relm, 0, "slot "..slot.." revealed-elements hidden despite seed garbage")
        H.assertEq(rcls, 0, "slot "..slot.." revealed-classes hidden despite seed garbage")
        -- broken timer ($3e88): the seed clears it, so a monster handed $FF
        -- at seed must not start broken.
        H.assertEq(brk, 0, "slot "..slot.." broken timer cleared (not broken) despite seed garbage")
        -- class-weak mask ($3e9c): $FF must be replaced, not OR'd, by the
        -- seed's authoritative value.
        H.assertEq(clsW ~= 0xFF, true, "slot "..slot.." class-weak mask replaced, not OR'd (got FF)")
        if sp == HEAD_SP then
          H.assertEq(clsW, 0x02, "head's authored class-weak overwritten to PIERCE $02")
          sawAuthored = true
        end
        if sp == SHELL_SP then
          H.assertEq(clsW, 0x00, "shell's authored gaugeless row overwritten to $00")
          sawZero = true
        end
        for k = 0, 3 do
          local g = wcell(slot, k)
          -- a drawn weakness cell must be '?' ($BF) or blank ($FF/$00); a real
          -- element/class glyph here would be a leaked reveal
          H.assertEq(g == 0xBF or g == 0xFF or g == 0x00, true,
            string.format("slot %d weakness cell %d shows '?'/blank (got %02X)", slot, k, g))
        end
        checked = checked + 1
      end
    end
    H.assertEq(checked > 0, true, "at least one monster on screen to check")
    -- neither half of the overwrite claim may go unexercised
    H.assertEq(sawAuthored, true,
      "the nonzero-over-$FF case really ran (the head was on screen)")
    H.assertEq(sawZero, true,
      "and the zero-over-$FF case really ran (the shell was on screen)")
    H.screenshot("reveal_gate_hidden")
  end),

  -- 2. the reveal still works, on an authored weakness rather than a poked
  -- one: Terra beams the head until its fire weakness turns over.
  H.call(function()
    H.assertEq(H.readByte(WEAK + hs * 2) & 0x01, 0x01,
      "control: the head really is fire-weak (Ot6ElemAddTbl) -- without this "
      .. "the chip below would prove nothing")
    H.assertEq(H.readByte(SHLD + hs * 2), 4, "and carries its authored gauge")
  end),
  H.driveUntil(function()
    return (H.readByte(REVEAL + hs * 2) & 0x01) == 1
  end, 40000, { H.call(pulseTick) }, "a fire chip to reveal fire"),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    local r = H.readByte(REVEAL + hs * 2)
    H.assertEq(beamsOrdered >= 1, true,
      "a beam was really ordered -- a reveal with no beam ordered would mean "
      .. "something other than the chip disclosed it")
    -- exact, not masked: a gate that leaked the whole strip would put $FF
    -- here and still satisfy a bit test
    H.assertEq(r, 0x01, "exactly the fire bit revealed after the chip")
    local drewFire = false
    for k = 0, 3 do if wcell(hs, k) == 0xEB then drewFire = true end end
    H.assertEq(drewFire, true, "chipped head's HUD row shows the fire glyph, not '?'")

    -- And only that axis: the head's second authored axis is its class
    -- weakness, asserted as a pair (there, and still hidden).
    local clsW = H.readByte(CWEAK + hs * 2)
    H.assertEq(clsW, 0x02,
      "control: the head really has a SECOND authored axis to keep hidden -- "
      .. "class-weak PIERCE (without this the next assertion tests nothing)")
    H.assertEq(H.readByte(RCLASS + hs * 2), 0,
      "one fire chip reveals the ELEMENT axis only -- the head's authored "
      .. "PIERCE weakness is still hidden, not disclosed by the same hit")
    -- and the shell, which took no hit at all, disclosed nothing
    H.assertEq(H.readByte(REVEAL + ss * 2), 0,
      "the untouched shell revealed nothing -- the disclosure is per body")
    local stillUnknown = 0
    for k = 0, 3 do if wcell(hs, k) == 0xBF then stillUnknown = stillUnknown + 1 end end
    H.assertEq(stillUnknown > 0, true,
      "and the HUD row still carries a '?' -- the strip was not blanket-revealed")
    H.screenshot("reveal_gate_chipped")
  end),
})
