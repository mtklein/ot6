-- @suite savestate=first_battle
-- battle_loadtail.lua -- a state captured just after a battle does not
-- count that battle again (#491).
--
-- A walker returns on a battle's [outcome], and the build captures the
-- state there, while the battle module's RAM still reads as the battle it
-- just finished (~35 frames: the hand-back tail, watchLeavers).  The first
-- driver to step after loading such a capture read it as a battle of its
-- own and said "[outcome] battle $13F WON after 41 ticks (no end reading:
-- the last frame's) ... CONTRADICTION", which a lab counting H.outcomes
-- after H.loadState took for a real win (#483's p1 miscounted K; every run
-- in build/attempts/wt/v038-grind-plains/lab/out/p1_*).
--
-- This fights first_battle out under the fight driver, captures the state
-- the frame its [outcome] is said (inside the tail), then loads it twice
-- the way a fresh process would meet it (the lib's battle-end reading
-- dropped first: a lab's Lua starts with none) and steps a new driver for
-- 150 frames each time:
--   * with M.LOAD_TAIL = false (the mutant: the old behaviour) the stale
--     battle is recorded as an outcome -- the negative control, so the
--     check below can fail;
--   * with the fix, no outcome is recorded and the driver says [tail].
-- A mechanism test: the snapshot is a complete machine state restored by
-- the supported path (H.requestSaveState / H.requestLoadState); nothing
-- else is written.
local H = dofile("tools/tests/lib/ot6.lua")

local F1, blob
local n0

-- load blob as a new process would find it, step a fresh driver, and
-- return how many outcomes it recorded and whether it said [tail]
local function reloadAndStep(label, mutant, result)
  local req, F, frames, before
  return {
    H.call(function()
      H.LOAD_TAIL = not mutant
      H.forgetBattleEnd()
      before = #H.outcomes
      req = H.requestLoadState(blob)
    end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "reload of the captured tail")
      F = H.newFightDriver("loadtail_" .. label)
      frames = 0
    end),
    H.driveUntil(function() return frames >= 150 end, 400,
      { H.call(function() frames = frames + 1; F.frame() end) }, "150 frames of a fresh driver"),
    -- the walkers idle a driver once its battle has handed back
    H.call(function() F.idle() end),
    H.call(function()
      result.added = #H.outcomes - before
      result.kinds = {}
      for i = before + 1, #H.outcomes do
        local o = H.outcomes[i]
        result.kinds[#result.kinds + 1] = string.format("%s $%03X atEnd=%s", o.kind, o.form & 0x3FF, tostring(o.atEnd))
      end
      H.log(string.format("battle_loadtail: %s (LOAD_TAIL=%s): %d outcome(s) recorded by the fresh driver: %s",
        label, tostring(H.LOAD_TAIL), result.added, table.concat(result.kinds, "; ")))
    end),
  }
end

local mutant, fixed = {}, {}

local steps = {
  H.waitFrames(20),
  H.loadState("build/states/first_battle.mss.lua"),
  H.call(function() F1 = H.newFightDriver("loadtail_fight") end),
  H.driveUntil(function() return #H.outcomes >= 1 end, 20000,
    { H.call(function() F1.frame() end) }, "first_battle fought to its [outcome]"),
  H.call(function()
    n0 = #H.outcomes
    H.assertEq(H.outcomes[n0].atEnd, true, "the fought battle's outcome has its end reading")
    H.log(string.format("battle_loadtail: first_battle fought: %s $%03X, capturing inside the tail",
      H.outcomes[n0].kind, H.outcomes[n0].form & 0x3FF))
    blob = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(blob, "capture inside the tail")
    blob = blob.blob
  end),
}
for _, s in ipairs(reloadAndStep("mutant", true, mutant)) do steps[#steps + 1] = s end
for _, s in ipairs(reloadAndStep("fixed", false, fixed)) do steps[#steps + 1] = s end
steps[#steps + 1] = H.call(function()
  H.LOAD_TAIL = true
  H.assertEq(mutant.added >= 1, true,
    "negative control: with the old behaviour the captured tail is recorded as an outcome (else this "
    .. "test cannot see the defect)")
  H.assertEq(fixed.added, 0,
    "a state captured after a battle: the fresh driver records no outcome for the battle that ended before it")
  H.log("battle_loadtail: the captured battle is not counted again (#491)")
end)

H.run({ maxFrames = 60000 }, steps)
