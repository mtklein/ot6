-- probe_moogle_wipe.lua -- what happens when a player loses a
-- wave battle in the Moogle defense. Player inputs only: nothing during
-- the battle (the party idles and wipes), A-taps on dialogs after. Zero
-- writes; the GameOver detector is an exec callback on the event
-- routine's own address, read-only.
local H = dofile("tools/tests/lib/ot6.lua")
local DEFENSE = "build/states/moogle_defense.mss.lua"

local gameOverAt = nil
local go = H.sym("GameOver")           -- 0xCCE566: event GameOver routine
emu.addMemoryCallback(function()
  if not gameOverAt then
    gameOverAt = H.frame
    H.log(string.format("GameOver exec at f%d", H.frame))
  end
end, emu.callbackType.exec, go, go)

local function snap(tag)
  local g = {}
  for i = 19, 24 do
    g[#g + 1] = string.format("(%d,%d)",
      H.readWord(0x086a + 0x29 * i) >> 4, H.readWord(0x086d + 0x29 * i) >> 4)
  end
  local hp = {}
  for _, c in ipairs({ 1, 2, 3, 4 }) do
    hp[#hp + 1] = tostring(H.readWord(0x1609 + 37 * c))
  end
  H.log(string.format(
    "%s f%d map=%d pos=(%d,%d) P1hp=%s guards %s $1F41=%02X ev=%s dlg=%s batt=%s",
    tag, H.frame, H.mapId(), H.fieldX(), H.fieldY(), table.concat(hp, "/"),
    table.concat(g, " "), H.readByte(0x1f41), tostring(H.eventRunning()),
    tostring(H.dialogWaiting()), tostring(H.battleLoadStarted())))
end

local battN, dlgN, aPhase = 0, 0, 0

H.run({ maxFrames = 45000 }, {
  H.loadState(DEFENSE),
  H.waitFrames(30),
  H.call(function() snap("boot") end),
  -- hands off until wave 1 collides
  H.driveUntil(function()
    battN = H.battleLoadStarted() and battN + 1 or 0
    return battN >= 3
  end, 8000, { H.call(function() H.setPad({}) end) }, "wave 1 collision"),
  H.call(function() snap("battle up") end),
  -- the player gives no input at all; the wave wipes the idle party.
  -- Terminator: the battle module gone (a total wipe zeroes the HP table,
  -- which battleLoadStarted reads as no-battle) and the field back.
  H.driveUntil((function()
    local calm = 0
    return function()
      calm = (not H.battleLoadStarted()) and calm + 1 or 0
      return calm >= 240
    end
  end)(), 30000, { H.call(function() H.setPad({}) end) }, "party wiped, battle gone"),
  H.call(function() snap("post-wipe") end),
  -- now play the aftermath as a player would: A-tap dialogs, otherwise
  -- hands off, and watch for the GameOver exec.  Snapshot every 300 frames.
  H.driveUntil(function()
    return gameOverAt ~= nil
  end, 25000, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      dlgN = H.dialogWaiting() and dlgN + 1 or 0
      if dlgN >= 3 then H.setPad(aPhase < 4 and { "a" } or {})
      else H.setPad({}) end
      if H.frame % 300 == 0 then snap("watch") end
    end),
  }, "GameOver fires (the march completed)"),
  H.call(function()
    snap("game over")
    H.log(string.format("VERDICT: game over at f%d -- a wipe is a real loss, not a softlock",
      gameOverAt or -1))
  end),
})
