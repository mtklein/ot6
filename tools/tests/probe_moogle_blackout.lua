-- probe_moogle_blackout.lua -- checks the field is lit when control
-- returns after losing a wave battle in the Moogle defense.
--
-- Loses wave 1, waits for the loss teleport to land the party at
-- (14,11) on map 51, then asserts ppu.screenBrightness is full at the
-- first frame the loss event goes idle. Zero writes: pad input and
-- reads only.
local H = dofile("tools/tests/lib/ot6.lua")
local DEFENSE = "build/states/moogle_defense.mss.lua"

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

local function snap(tag)
  H.log(string.format(
    "%s f%d map=%d pos=(%d,%d) bright=%d ev=%s dlg=%s batt=%s",
    tag, H.frame, H.mapId(), H.fieldX(), H.fieldY(), bright(),
    tostring(H.eventRunning()), tostring(H.dialogWaiting()),
    tostring(H.battleLoadStarted())))
end

local battN, aPhase = 0, 0
local handoffBright = nil

H.run({ maxFrames = 45000 }, {
  H.loadState(DEFENSE),
  H.waitFrames(30),
  H.call(function()
    snap("boot")
    H.assertEq(bright() >= 15, true, "defense field lit at boot")
  end),
  -- hands off until wave 1 collides with the idle party
  H.driveUntil(function()
    battN = H.battleLoadStarted() and battN + 1 or 0
    return battN >= 3
  end, 8000, { H.call(function() H.setPad({}) end) }, "wave 1 collision"),
  H.call(function() snap("battle up") end),
  -- idle through the battle so the wave wipes the party
  H.driveUntil((function()
    local calm = 0
    return function()
      calm = (not H.battleLoadStarted()) and calm + 1 or 0
      return calm >= 240
    end
  end)(), 30000, { H.call(function() H.setPad({}) end) }, "party wiped, battle gone"),
  H.call(function()
    snap("post-wipe")
    H.screenshot("blackout_postwipe")
  end),
  -- press through the defeat like a human until the loss path has run:
  -- field module back on map 51 with the party on the (14,11) bench
  H.driveUntil(function()
    return (not H.battleLoadStarted()) and H.mapId() == 51
       and H.fieldX() == 14 and H.fieldY() == 11
  end, 6000, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      H.setPad(aPhase < 4 and { "a" } or {})
    end),
  }, "loss path landed (party benched at 14,11)"),
  H.call(function()
    H.setPad({})
    snap("benched")
  end),
  -- the discriminating instant is the first frame the event PC
  -- {$e5,$e6,$e7} sits on its idle parking value $CA/0000, rather than
  -- eventRunning(), which misreads a mid-command WRAM-mirror excursion
  -- as "no event". Soft wait, so an unlit field still reaches the
  -- screenshot below.
  H.waitUntilSoft(function()
    if H.readByte(0x00e7) == 0xCA and H.readByte(0x00e5) == 0
       and H.readByte(0x00e6) == 0 then
      handoffBright = bright()
      return true
    end
    return false
  end, 600, "event handed control back", 1),
  H.call(function()
    snap("after")
    H.screenshot("blackout_field")
    H.assertEq(H.vars["event handed control back"], true,
      "loss event ended within the watch window")
    H.assertEq((handoffBright or 0) >= 15, true,
      "field already lit when the loss event handed control back")
    H.log(string.format(
      "VERDICT: control returned with brightness %d", handoffBright or -1))
  end),
})
