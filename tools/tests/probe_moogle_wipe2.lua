-- probe_moogle_wipe2.lua -- the wave-loss aftermath, played the way a
-- player who lost would: mash A at whatever is on screen. Mashes A
-- unconditionally from the moment the wipe lands and screenshots every
-- 3000 frames. Zero writes.
local H = dofile("tools/tests/lib/ot6.lua")
local DEFENSE = "build/states/moogle_defense.mss.lua"

local gameOverAt = nil
local go = H.sym("GameOver")
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
  H.log(string.format(
    "%s f%d map=%d pos=(%d,%d) guards %s $1F41=%02X ev=%s dlg=%s batt=%s mon=%d",
    tag, H.frame, H.mapId(), H.fieldX(), H.fieldY(), table.concat(g, " "),
    H.readByte(0x1f41), tostring(H.eventRunning()),
    tostring(H.dialogWaiting()), tostring(H.battleLoadStarted()),
    H.monstersPresent()))
end

local battN, aPhase, shotN = 0, 0, 0

H.run({ maxFrames = 50000 }, {
  H.loadState(DEFENSE),
  H.waitFrames(30),
  H.driveUntil(function()
    battN = H.battleLoadStarted() and battN + 1 or 0
    return battN >= 3
  end, 8000, { H.call(function() H.setPad({}) end) }, "wave 1 collision"),
  H.call(function() snap("battle up") end),
  -- idle through the battle so the party wipes
  H.driveUntil((function()
    local calm = 0
    return function()
      calm = (not H.battleLoadStarted()) and calm + 1 or 0
      return calm >= 240
    end
  end)(), 30000, { H.call(function() H.setPad({}) end) }, "party wiped, battle gone"),
  H.call(function()
    snap("post-wipe")
    H.screenshot("wipe_post")
  end),
  -- now mash A the way a stuck player would, screenshotting as we go
  H.driveUntil(function()
    return gameOverAt ~= nil
  end, 15000, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      H.setPad(aPhase < 4 and { "a" } or {})
      if H.frame % 3000 == 0 then
        snap("mash")
        shotN = shotN + 1
        H.screenshot("wipe_mash_" .. shotN)
      end
    end),
  }, "GameOver fires under A-mash"),
  H.call(function()
    snap("game over")
    H.log(string.format("VERDICT: GameOver exec at f%d under A-mash", gameOverAt or -1))
  end),
})
