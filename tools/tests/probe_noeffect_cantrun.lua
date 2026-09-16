-- @manual
-- probe_noeffect_cantrun.lua -- the battle no-effect rule on a held L+R the
-- formation refuses: the negative of probe_escape_cells.lua.
--
--   tools/tests/run.sh tools/tests/probe_noeffect_cantrun.lua build/states/noeffect_cantrun.log
--
-- Boots whelk_entry.mss (the field tile one south of the Whelk trigger,
-- map 41 (42,5)), walks onto the trigger the way battle_absorbguard does,
-- and once the Whelk event fight is up holds L+R at the command window
-- with the watchdogs enforcing, the way the world walkers do.  The
-- escape-aware rule counts a held L+R as answered only while the
-- formation can be run from and the escape cells move; the Whelk fight is
-- an event battle (`battle 64`, event_main.asm ~101431) whose formation
-- refuses to run, so the expected verdict is
--
--   FAIL: no-effect: l+r for ... -- ... L+R is held but this formation
--   cannot be run from ($B1=.. $2F4B=..) ...
--
-- with class=noeffect on the [retry] line: the rule still bites on a press
-- the game is not answering.  A PASS here, or a FAIL of another class, is
-- the finding to report.  (The game's opening fight, first_battle.mss,
-- was tried first and turned out to be runnable -- $2F4B=00, the party out
-- by f701 -- so it is the positive case, not this one.)  The suite
-- counterpart is watchdog_cantrun.lua (#200): the same walk and hold on
-- attempt 1, and attempt 2 asserting that attempt 1 fell to the trip.
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/whelk_entry.mss.lua"
local aPhase = 0

local function cellsLine(tag)
  H.log(string.format("[cantrun] %s f%d $2F45=%02X $B1=%02X $2F4B=%02X "
    .. "$3A3B=%02X $3A38=%02X $3A39=%02X rc=%02X,%02X,%02X,%02X menu=%02X.%02X",
    tag, H.frame, H.readByte(0x2F45), H.readByte(0x00B1), H.readByte(0x2F4B),
    H.readByte(0x3A3B), H.readByte(0x3A38), H.readByte(0x3A39),
    H.readByte(0x3D70), H.readByte(0x3D72), H.readByte(0x3D74),
    H.readByte(0x3D76), H.readByte(0x7BCA), H.readByte(0x7BC2)))
end

H.run({ maxFrames = 12000, retries = 1, watchdog = true }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),

  -- walk onto the trigger tile (battle_absorbguard.lua's recipe)
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
  -- the fight opens on a battle dialog ("VICKS: Hold it!") that only A
  -- pages; tap A until the command window is up, as a person would
  H.driveUntil(function()
    return H.readByte(0x7BCA) ~= 0 and H.readByte(0x7BC2) ~= 0
  end, 1800, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      H.setPad(aPhase < 4 and { "a" } or {})
    end),
  }, "command window open at the Whelk fight"),
  H.call(function() H.setPad({}); cellsLine("loaded") end),

  -- hold L+R until the fight ends or the rule speaks
  H.driveUntil(function() return not H.battleLoadStarted() end, 6000, {
    H.call(function()
      H.setPad({ l = true, r = true })
      if H.frame % 120 == 0 then cellsLine("l+r") end
    end),
  }, "L+R held at the Whelk fight"),
  H.call(function()
    H.log("[cantrun] the battle ended under L+R: this formation could be "
      .. "run from after all; pick another fixture for the negative")
  end),
})
