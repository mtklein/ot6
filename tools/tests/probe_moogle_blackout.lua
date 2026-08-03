-- probe_moogle_blackout.lua -- what the PLAYER SEES after losing a wave
-- battle in the Moogle defense (issue #74).
--
-- probe_moogle_wipe/_wipe2 established the mechanics of a wave loss: the
-- idle party wipes, the loss path _ccaaba revives all four slots at 1 HP
-- and parks the party at (14,11), and the defense marches on toward the
-- real GameOver.  Neither probe asserted what is on SCREEN.  The collision
-- battle faded the field out; every winning branch fades it back in
-- (fade_in / wait_fade, e.g. _ccaaec) -- and _ccaaba did not, so after the
-- player presses through the Annihilated screen the field stays BLACK
-- while guards march and squads fight invisibly.
--
-- This probe loses wave 1 for real: hands off through the collision and
-- the wipe, then A-mash like a stuck player until the loss teleport lands
-- (field module back, party at the (14,11) bench), then hands off and
-- ASSERTS the loss event lights the field BEFORE handing control back:
-- at the first frame the event engine goes idle after the bench,
-- ppu.screenBrightness must already be full.  Unfixed, the event returns
-- in the dark and the player gets control on a black field (the field
-- engine's own end-of-event fade trickles in ~50 frames later on this
-- route, and nothing guarantees it on the others -- see
-- probe_moogle_fadewatch's transition log).  Green once _ccaaba fades in
-- like its winning siblings.  Zero writes: pad input and reads only.
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
    -- positive control: the brightness read is live (field starts lit)
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
  -- field module back on map 51 with the party on _ccaaba's (14,11) bench
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
  -- hands off: the loss EVENT ITSELF must light the field before it hands
  -- control back.  The discriminating instant is the first frame the event
  -- engine goes idle after the bench: with the fix, fade_in + wait_fade
  -- run inside _ccaaba, so brightness is already full there; unfixed, the
  -- event returns in the dark (measured bright=4, mid-ramp of the field
  -- engine's incidental end-of-event fade -- the player got control on a
  -- black field and the loss pantomime played invisibly).  Soft wait so
  -- the unfixed ROM still reaches the screenshot: the evidence must
  -- survive the failure that reports it.
  H.waitUntilSoft(function()
    if not H.eventRunning() then
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
