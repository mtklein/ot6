-- @suite savestate=whelk_entry
-- watchdog_cantrun.lua -- the escape-cells exemption's negative control
-- (#200): a held L+R at a formation the engine refuses to run from MUST
-- still trip the battle no-effect watchdog.
--
-- The watchdog (lib/ot6.lua, watchTick) counts a held L+R in a battle as
-- answered while the formation can be run from and the escape cells
-- ($2F45, $3A38/$3A39, the run counters $3D70,x) keep moving, because
-- that is the run mechanic answering the press in cells the menu never
-- shows (b99a4dcb).  The rule's narrow half is what this suite holds: when
-- the formation cannot be run from ($B1 bit 1 or $2F4B bit 0) the press is
-- unanswered whatever the counters do, and the trip must land.  The Whelk
-- event fight (battle 64) is that formation: measured 2026-09-16 with
-- probe_noeffect_cantrun.lua, $B1=07 $2F4B=0C, counters ticking under the
-- held L+R, "can't run away!!" from the run command itself.
--
-- A suite cannot expect a red run, so the trip is observed through the
-- segment runner: attempt 1 walks onto the trigger, pages the opening
-- dialog to the command window, and holds L+R with the watchdogs
-- enforcing; the trip is a seed-dependent class, so the runner replays
-- the body, and attempt 2 reads H.attemptFailures() and asserts that
-- attempt 1 fell to `no-effect` naming the can't-run formation.  The
-- verdict of a healthy tree is PASS attempts=2/2.  A widened exemption
-- shows as attempt 1 holding L+R for HOLD_MAX frames with no trip, which
-- is a contract failure (no replay): the suite is red at once, naming the
-- widening.  probe_noeffect_cantrun.lua stays the hand-run instrument
-- that prints the cells themselves every 120 frames.
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/whelk_entry.mss.lua"
local HOLD_MAX = 1500      -- 5x the no-effect window; the trip lands well inside
local failures = H.attemptFailures()
local attempt = #failures + 1
local aPhase, held = 0, 0

local function cellsLine(tag)
  H.log(string.format("[cantrun] %s f%d $2F45=%02X $B1=%02X $2F4B=%02X "
    .. "$3A3B=%02X $3A38=%02X $3A39=%02X rc=%02X,%02X,%02X,%02X menu=%02X.%02X",
    tag, H.frame, H.readByte(0x2F45), H.readByte(0x00B1), H.readByte(0x2F4B),
    H.readByte(0x3A3B), H.readByte(0x3A38), H.readByte(0x3A39),
    H.readByte(0x3D70), H.readByte(0x3D72), H.readByte(0x3D74),
    H.readByte(0x3D76), H.readByte(0x7BCA), H.readByte(0x7BC2)))
end

local steps
if attempt == 1 then
  steps = {
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
    H.call(function()
      H.setPad({})
      cellsLine("loaded")
      -- the fixture is the negative only while the engine refuses the run
      local cantRun = (H.readByte(0x00B1) & 0x02) ~= 0
        or (H.readByte(0x2F4B) & 0x01) ~= 0
      H.assertEq(cantRun, true,
        "the Whelk formation cannot be run from ($B1 bit 1 or $2F4B bit 0)")
    end),

    -- hold L+R: the watchdog is expected to end this attempt inside
    -- HOLD_MAX frames; the battle ending, or the hold running its full
    -- length, are both findings
    H.driveUntil(function()
      return held >= HOLD_MAX or not H.battleLoadStarted()
    end, HOLD_MAX + 300, {
      H.call(function()
        held = held + 1
        H.setPad({ l = true, r = true })
        if H.frame % 120 == 0 then cellsLine("l+r") end
      end),
    }, "L+R held at the Whelk fight"),
    H.call(function()
      H.setPad({})
      cellsLine("after")
      H.assertEq(H.battleLoadStarted(), true,
        "the Whelk fight is still up under the held L+R (it cannot be run from)")
      H.assertEq(held < HOLD_MAX, true,
        string.format("the no-effect watchdog tripped on %d frames of L+R at a "
          .. "formation that cannot be run from -- it did not: the escape-cells "
          .. "exemption has widened past the can't-run bits", held))
    end),
  }
else
  steps = {
    H.call(function()
      local f = failures[1]
      H.log(string.format("[cantrun] attempt %d ended class=%s at f%d: %s",
        f.attempt, f.class, f.frame, f.msg))
      H.assertEq(#failures, 1, "exactly one attempt fell before this one")
      H.assertEq(f.class, "noeffect",
        "attempt 1 fell to the no-effect watchdog (class)")
      H.assertEq(f.msg:find("no-effect: l+r for", 1, true) ~= nil, true,
        "the trip names the held L+R as the unanswered press")
      H.assertEq(f.msg:find("cannot be run from", 1, true) ~= nil, true,
        "the trip names the formation that cannot be run from")
      H.log("[cantrun] the escape-cells exemption still stops at the "
        .. "can't-run bits: a held L+R the game refuses trips no-effect")
    end),
  }
end

H.run({ maxFrames = 12000, retries = 2, watchdog = true }, steps)
