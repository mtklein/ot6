-- @manual
-- probe_wipe_canary.lua -- #153(b): what does the GameOver canary see when
-- the party is wiped INSIDE a battle?  Boots fc_alcove, steps out onto 394
-- the way gen_fc_escape does, walks until a random comes up, then stands
-- with the pad released for the whole fight (a person who never presses a
-- button), logging the battle HP table, the wipe predicate, the game-over
-- flags and the canary counter every 300 frames until the run's own
-- verdict or the frame cap.  allowGameOver so the run keeps observing
-- after the canary fires.  Reads and pad presses only.
local H = dofile("tools/tests/lib/ot6.lua")

local FIX = "build/states/fc_alcove.mss.lua"
-- ALLOW=true keeps observing past the canary (the ladders' shape); false
-- is every ordinary run: the canary must END it.
local ALLOW = false
local function map() return H.mapId() & 0x3ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local t, wipedAt, firedAt = 0, nil, nil

local function status(tag)
  H.log(string.format("[wipe probe] %s t=%d f%d hp=%d,%d,%d,%d max=%d,%d,%d,%d wipedInBattle=%s battleLoadStarted=%s monsters=%d $3ebc=%02X map=%d ctrl=%s zMenu=$%02X bright=%d gameOverFired=%d",
    tag, t, H.frame, H.readWord(0x3BF4), H.readWord(0x3BF6), H.readWord(0x3BF8), H.readWord(0x3BFA),
    H.readWord(0x3C1C), H.readWord(0x3C1E), H.readWord(0x3C20), H.readWord(0x3C22),
    tostring(H.partyWipedInBattle()), tostring(H.battleLoadStarted()), H.monstersPresent(),
    H.readByte(0x3ebc), map(), tostring(H.hasControl()), H.readByte(0x26), bright(), H.gameOverFired or 0))
end

H.run({ maxFrames = 200000, allowGameOver = ALLOW }, {
  H.loadState(FIX),
  H.waitFrames(60),
  H.waitUntil(function() return H.hasControl() end, 1200, "field control", 5),
  H.navTo(8, 9, { maxFrames = 3000, playBattles = "tactical", care = false }),
  H.driveUntil(function() t = t + 1; return map() == 394 end, 1800, {
    H.call(function()
      if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad({ up = true })
    end),
  }, "alcove (8,9) -> up through (8,8) -> 394"),
  H.release(),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 900, "control back on 394", 10),
  H.waitFrames(30),
  H.navTo(82, 30, { maxFrames = 20000, playBattles = "tactical", care = false,
    arrive = function() return H.battleLoadStarted() end }),
  H.release(),
  H.call(function() t = 0; status("battle up, pad released") end),
  H.driveUntil(function()
    t = t + 1
    if wipedAt == nil and H.partyWipedInBattle() then
      wipedAt = t
      status("WIPE (every battle HP word 0)")
    end
    if firedAt == nil and (H.gameOverFired or 0) > 0 then
      firedAt = t
      status(string.format("CANARY fired %d frames after the wipe", wipedAt and (t - wipedAt) or -1))
    end
    -- keep watching 1200 frames past the canary, or 30000 past the wipe
    if firedAt and t - firedAt >= 1200 then return true end
    if wipedAt and t - wipedAt >= 30000 then return true end
    return false
  end, 90000, {
    H.call(function()
      H.setPad({})
      if t % 300 == 0 then status("watch") end
    end),
  }, "the passive fight to its end"),
  H.call(function()
    status("end")
    H.log(string.format("[wipe probe] wipedAt=%s firedAt=%s (frames after battle up)", tostring(wipedAt), tostring(firedAt)))
  end),
})
