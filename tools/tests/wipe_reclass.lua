-- @suite savestate=locke_scenario
-- wipe_reclass.lua -- the run canary's negative control for a lost fight
-- under allowGameOver (#205): a battle the party loses and the body never
-- handles MUST file as class=wipe, with its `wipe context:` line, and not
-- as the stall that follows the loss.
--
-- The shape of the bug (docs/design/sfigaro-gate.md): gen_sfigaro runs
-- with allowGameOver for its cider sweep; the seat-based wipe count fired
-- on a lost battle 11, froze the pad, the Annihilated screen never got its
-- press, and 1800 still frames later the no-progress watchdog filed the
-- attempt as `noprogress` with a stale field signature -- the v0.17
-- qualification's attempt 1.  The runner now (a) leaves the pad alone on
-- the battle-wipe count under allowGameOver and (b) files a stall that
-- follows an unhandled counted game over as the wipe it is.
--
-- A suite cannot expect a red run, so the trip is observed through the
-- segment runner the way watchdog_cantrun / watchdog_listend do: attempt
-- 1 talks solo L12 LOCKE into battle 11 (the gate soldier, HeavyArmor
-- $09F, formation 64) and never presses -- the soldier wears 279 HP down
-- in ~750 frames (probe, 2026-09-16), the canary counts the wipe at 300
-- frames of the wipe shape, nothing presses the Annihilated screen, and
-- the no-progress watchdog ends the attempt; `wipe` is a seed-dependent
-- class, so the runner replays the body, and attempt 2 reads
-- H.attemptFailures() and asserts that attempt 1 was filed as `wipe`,
-- naming the counted battle wipe and the stall it absorbed, with a
-- context naming formation $009F and LOCKE's seat.  A healthy tree reads
-- PASS attempts=2/2.  The attempt-1 branch's own assert is the finding
-- when nothing ends the attempt at all.
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/locke_scenario.mss.lua"
local HEAVYARMOR = 0x009F
local failures = H.attemptFailures()
local attempt = #failures + 1
local ph, wipedN, battleAt = 0, 0, nil

local steps
if attempt == 1 then
  steps = {
    H.waitFrames(20),
    H.loadState(STATE),
    H.waitFrames(60),
    H.call(function()
      H.assertEq(H.mapId() & 0x1ff, 75, "booted on map 75, occupied South Figaro")
      H.assertEq(H.hasControl(), true, "controllable")
      H.assertEq(H.objX(26) == 30 and H.objY(26) == 42, true,
        "the gate soldier is on his post (30,42)")
    end),
    H.talkToObj(26, "the gate soldier (battle 11)"),
    -- "Halt!" wants A; tap it into the fight the way rideOut's drive does
    H.driveUntil(function() return H.battleLoadStarted() end, 3000, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, "into battle 11"),
    H.call(function()
      H.setPad({})
      battleAt = H.frame
      H.log(string.format("[wipe_reclass] battle up f%d; LOCKE %d/%d; the pad "
        .. "stays neutral from here", H.frame, H.readWord(0x3BF4), H.readWord(0x3C1C)))
    end),
    H.waitUntil(function() return H.formationHas({ [HEAVYARMOR] = true }) end,
      600, "formation 64 (HeavyArmor $009F) on stage", 10),
    -- the loss, unpressed: the predicate never returns true on its own --
    -- the watchdog is expected to end the attempt within its window
    -- (1800 quiet frames after the Annihilated screen settles); the
    -- drive's own budget is the backstop, and either way the runner must
    -- file the attempt as the wipe it was
    H.driveUntil(function()
      wipedN = H.partyWipedInBattle() and wipedN + 1 or 0
      if wipedN == 1 then
        H.log(string.format("[wipe_reclass] the wipe shape at f%d (+%d): LOCKE "
          .. "%d/%d $3ebc=%02X", H.frame, H.frame - battleAt, H.readWord(0x3BF4),
          H.readWord(0x3C1C), H.readByte(0x3EBC)))
      end
      if wipedN == 320 then
        H.log(string.format("[wipe_reclass] 320 frames of the wipe shape at f%d: "
          .. "gameOverFired=%d padFrozen=%s (allowGameOver: the pad must not be "
          .. "frozen by the battle-wipe count)", H.frame, H.gameOverFired,
          tostring(H.padFrozen)))
        H.assertEq(H.gameOverFired >= 1, true,
          "the canary counted the battle wipe at 300 frames")
        H.assertEq(H.padFrozen, false,
          "the battle-wipe count did not freeze the pad under allowGameOver (#205 a)")
      end
      return false
    end, 6000, { H.call(function() H.setPad({}) end) }, "the loss, unpressed"),
    H.call(function()
      H.assertEq(false, true, string.format("nothing ended attempt 1 after the "
        .. "counted wipe (wipe shape held %d frames): the drive ran its budget "
        .. "out without the watchdog or the timeout filing it", wipedN))
    end),
  }
else
  steps = {
    H.call(function()
      local f = failures[1]
      H.log(string.format("[wipe_reclass] attempt %d ended class=%s at f%d: %s",
        f.attempt, f.class, f.frame, f.msg))
      H.log(string.format("[wipe_reclass] attempt %d context: %s", f.attempt,
        tostring(f.context)))
      H.assertEq(#failures, 1, "exactly one attempt fell before this one")
      H.assertEq(f.class, "wipe",
        "attempt 1 was filed as a wipe, not as the stall that followed it (#205 b)")
      H.assertEq(f.msg:find("battle wipe x1", 1, true) ~= nil, true,
        "the message names the counted battle wipe")
      H.assertEq(f.msg:find("no-progress:", 1, true) ~= nil
                 or f.msg:find("timeout after", 1, true) ~= nil, true,
        "the message carries the stall it absorbed (no-progress or the drive's timeout)")
      H.assertEq(type(f.context) == "string" and f.context:find("009F", 1, true) ~= nil,
        true, "the wipe context names formation 64 (HeavyArmor $009F)")
      H.assertEq(f.context:find("a1:", 1, true) ~= nil, true,
        "the wipe context names LOCKE's seat (actor 1)")
      H.log("[wipe_reclass] a lost fight under allowGameOver files as the wipe "
        .. "it is, with its formation and seats")
    end),
  }
end

H.run({ maxFrames = 15000, retries = 2, watchdog = true, allowGameOver = true }, steps)
