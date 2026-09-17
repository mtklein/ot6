-- @suite savestate=battle_entry
-- seed_reroll.lua -- the segment runner's first-battle duplicate check (#208).
--
-- A retry is only worth an attempt if it fights something other than the
-- attempt it replaces.  fc_landing's shifts 0..32 all fought one first
-- battle (the idle was swallowed by a walk and a load that ran on the
-- game's own clock), so v0.17's retries there re-lost a known loss.  The
-- runner now records every attempt's first battle at InitBattle's seed
-- store and re-rolls a replay whose first battle repeats an earlier
-- attempt's, at an untried shift, without spending an attempt.
--
-- The duplicate is a measured one, not a forced one.  This fixture's first
-- battle comes on the game's own clock in 4-frame steps, so most shifts are
-- absorbed; `OT6_SHIFT_PROBE=1 sh tools/tests/run.sh tools/tests/seed_reroll.lua`
-- (2026-09-17) logged `[seedprobe] 60 shift(s) sampled, 8 distinct first
-- battle(s)`, with shifts 26..29 on shift 0's key (be7C) and shift 33 on
-- shift 1's (be8C).  seedGap = 26 therefore puts attempt 2 on attempt 1's
-- first battle.  Attempt 1 raises a `nopath`-shaped message once its
-- battle is up (a message, as segment_retry.lua injects, because the
-- classifier reads messages).  Attempt 2 at shift 26 must be re-rolled at
-- its seed store (to shift 33); the re-run attempt 2 then asserts exactly
-- one re-roll, a first battle different from attempt 1's, and three body
-- runs.  A healthy tree reads PASS attempts=2/3.  If shift 26 stops
-- reproducing attempt 1's battle (a changed fixture or walk), the
-- rerollCount assert says so rather than passing vacuously: re-measure
-- with the probe line above and pick a shift from its duplicates.
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/battle_entry.mss.lua"
_G.SEED_REROLL_RUNS = (_G.SEED_REROLL_RUNS or 0) + 1
local run = _G.SEED_REROLL_RUNS
local attempt = #H.attemptFailures() + 1

H.run({ maxFrames = 20000, retries = 3, seedGap = 26, watchdog = false }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.call(function()
    local fb = H.firstBattle()
    H.assertEq(fb ~= nil, true, "the first battle was recorded at the seed store")
    H.log(string.format("[seed_reroll] attempt %d (body run %d): first battle "
      .. "shift %d $021e=%d key %s, re-rolls %d", attempt, run, fb.shift,
      fb.phase, fb.key, H.rerollCount()))
    if attempt == 1 then
      error("navTo: no path (1,1)->(2,2) -- injected by seed_reroll.lua once "
        .. "the first battle (key " .. fb.key .. ") was up", 0)
    end
    local prev = H.earlierFirstBattles()[1]
    H.assertEq(prev ~= nil and prev.key ~= nil, true,
      "attempt 1's first battle is on record")
    H.assertEq(H.rerollCount(), 1,
      "attempt 2 at shift 26 fought attempt 1's first battle and was re-rolled once")
    H.assertEq(run, 3, "the body ran three times: attempt 1, attempt 2 at shift "
      .. "26 (re-rolled at its seed store), attempt 2 at the re-rolled shift")
    H.assertEq(fb.key ~= prev.key, true,
      "the re-rolled attempt fights a different first battle")
    H.log("[seed_reroll] a retry that repeated attempt 1's first battle was "
      .. "re-rolled onto a different one")
  end),
})
