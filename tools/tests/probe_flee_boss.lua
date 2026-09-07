-- @manual
-- probe_flee_boss.lua -- #150: on an UNRUNNABLE formation, does the
-- mustflee helper report refusal (and hand the fight to the tactical
-- driver) rather than stand in L+R for the cap?  Boots vargas_entry (Mt.
-- Kolts, one interaction from the VARGAS scene -> battle 66), A-taps into
-- the scene the way gen_vargas does, then hands the live battle to
-- navTo(playBattles="mustflee") so the lib's own flee helper drives it.
-- The same observer as probe_flee_world logs the engine's run machinery.
-- Reads and pad presses only.
local H = dofile("tools/tests/lib/ot6.lua")

local FIX = "build/states/vargas_entry.mss.lua"
local VARGAS = 0x0103
local OBSERVE = 2400        -- battle frames to watch before ending the probe

local inBattle, bN, ranLatch = false, 0, false
emu.addEventCallback(function()
  local live = H.battleLoadStarted()
  if live and not inBattle then
    inBattle, bN, ranLatch = true, 0, false
    H.log(string.format("[flee probe] battle up at f%d formation %04X %04X %04X %04X %04X %04X",
      H.frame, H.readWord(0x57C0), H.readWord(0x57C2), H.readWord(0x57C4),
      H.readWord(0x57C6), H.readWord(0x57C8), H.readWord(0x57CA)))
  end
  if inBattle then
    bN = bN + 1
    if H.readByte(0x3a38) ~= 0 and not ranLatch then
      ranLatch = true
      H.log(string.format("[flee probe] $3a38=%02X -- a character JUST RAN AWAY at battle frame %d",
        H.readByte(0x3a38), bN))
    end
    if bN <= 4 or bN % 60 == 0 then
      H.log(string.format("[flee probe] +%d $b1=%02X $2f45=%d $3a3b=%d counters=%d,%d,%d,%d $3a38=%02X $b0=%02X $2f4b=%02X mon0 $3c88=%02X",
        bN, H.readByte(0x00b1), H.readByte(0x2f45), H.readByte(0x3a3b),
        H.readByte(0x3d70), H.readByte(0x3d72), H.readByte(0x3d74), H.readByte(0x3d76),
        H.readByte(0x3a38), H.readByte(0x00b0), H.readByte(0x2f4b), H.readByte(0x3c88)))
    end
  end
  if not live and inBattle then
    inBattle = false
    H.log(string.format("[flee probe] battle down at f%d after %d frames: ran=%s", H.frame, bN, tostring(ranLatch)))
  end
end, emu.eventType.startFrame)

H.run({ maxFrames = 60000 }, {
  H.loadState(FIX),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[flee probe] vargas_entry at (%d,%d) map %d", H.fieldX(), H.fieldY(), H.mapId() & 0x3ff))
  end),
  (function()
    local aPh = 0
    return H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, "the VARGAS scene reaches battle 66")
  end)(),
  H.release(),
  H.navTo(22, 32, { maxFrames = 30000, playBattles = "mustflee", fleeCap = 1800, care = false,
    arrive = function() return bN >= OBSERVE end }),
  H.call(function()
    H.assertEq(H.readWord(0x57C0), VARGAS, "VARGAS ($0103) leads the formation")
    H.log(string.format("[flee probe] observed %d battle frames; ending the probe mid-fight (the fight itself is gen_vargas's job)", bN))
  end),
})
