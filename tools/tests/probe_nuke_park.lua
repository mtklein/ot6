-- @manual
-- probe_nuke_park.lua -- #153(a): with nuke={2} on a walk, the navTo
-- driver's Bolt plan parked in menu state $05 ("consumed 41 pulses ...
-- without landing") on the FC escape.  Boots fc_alcove (the FC save
-- alcove, map 358), steps out onto 394 the way gen_fc_escape does, and
-- walks its first leg to the (82,30) reveal under the lab's nuke walk
-- policy.  A startFrame observer samples the battle menu every 30 frames
-- while a menu is open so the park's window state and cursor cells are on
-- the record.  Reads and pad presses only.
local H = dofile("tools/tests/lib/ot6.lua")

local FIX = "build/states/fc_alcove.mss.lua"
local TERRA = 0x00
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW, BCHID = 0x202E, 0x890F, 0x3ED8
local function map() return H.mapId() & 0x3ff end
local battles, inBattle, bN = 0, false, 0

emu.addEventCallback(function()
  local live = H.battleLoadStarted()
  if live and not inBattle then inBattle, bN = true, 0; battles = battles + 1
    H.log(string.format("[park probe] battle %d up at f%d formation %04X", battles, H.frame, H.readWord(0x57C0)))
  end
  if inBattle then
    bN = bN + 1
    if H.readByte(MENU) ~= 0 and bN % 30 == 0 then
      local a = H.readByte(ACTOR) & 3
      -- the command table: 3 bytes a row -- id, flags (bit 7 = the row is
      -- DISABLED and the cursor skips it: btlgfx check_command), targeting
      local rows = {}
      for r = 0, 3 do
        rows[#rows + 1] = string.format("%02X/%02X/%02X", H.readByte(CMDTBL + a * 12 + r * 3),
          H.readByte(CMDTBL + a * 12 + r * 3 + 1), H.readByte(CMDTBL + a * 12 + r * 3 + 2))
      end
      H.log(string.format("[park probe] b%d +%d menu=%02X st=$%02X actor=%d char=%d cmdrow=%02X cmds=%s status=%02X,%02X,%02X,%02X $b1=%02X bp=%d mp=%d hp=%d,%d,%d,%d",
        battles, bN, H.readByte(MENU), H.readByte(MSTATE), a, H.readByte(BCHID + a * 2),
        H.readByte(CMDROW + a), table.concat(rows, ","),
        H.readByte(0x3EE4 + a * 2), H.readByte(0x3EE5 + a * 2), H.readByte(0x3EF8 + a * 2), H.readByte(0x3EF9 + a * 2),
        H.readByte(0x00b1),
        H.readByte(0x3E9C + a * 2), H.readWord(0x3C08 + a * 2),
        H.readWord(0x3BF4), H.readWord(0x3BF6), H.readWord(0x3BF8), H.readWord(0x3BFA)))
    end
  end
  if not live and inBattle then inBattle = false
    H.log(string.format("[park probe] battle %d down at f%d after %d frames", battles, H.frame, bN))
  end
end, emu.eventType.startFrame)

local t = 0
H.run({ maxFrames = 120000 }, {
  H.loadState(FIX),
  H.waitFrames(60),
  H.waitUntil(function() return H.hasControl() end, 1200, "field control", 5),
  H.call(function()
    H.assertEq(map(), 358, "fc_alcove is the alcove (358)")
    H.log(string.format("[park probe] alcove at (%d,%d)", H.fieldX(), H.fieldY()))
  end),
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
  H.call(function() H.log(string.format("[park probe] on 394 at (%d,%d)", H.fieldX(), H.fieldY())) end),
  H.navTo(82, 30, { maxFrames = 20000, playBattles = "tactical", bank = 0, healPercent = 60,
    care = false, nuke = { 2 },
    arrive = function() return battles >= 2 and not H.battleLoadStarted() end }),
  H.call(function()
    H.log(string.format("[park probe] done at f%d after %d battle(s) at (%d,%d)", H.frame, battles, H.fieldX(), H.fieldY()))
  end),
})
