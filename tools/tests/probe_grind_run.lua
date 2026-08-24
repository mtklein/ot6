-- probe_grind_run.lua -- one resumable CHUNK of the Chimera-pocket grind
-- (#133): up to 5 fights, state re-published after each.
--
-- The full grind (L15-17 -> L21-22) is ~19-24 fights at the measured 786
-- XP/char (probe_grind_fight; LevelUpExp puts L21 at 26360 cumulative XP
-- and L22 at 30232), which is too long for one testrunner invocation --
-- run.sh's wall-clock cap would either kill it or a late wipe would lose
-- everything, since artifacts only publish on a PASS.  So the grind runs as
-- chunks over a rolling fixture:
--
--   cp build/states/wob_grind.mss     build/states/wob_grind_run.mss      # seed
--   cp build/states/wob_grind.mss.lua build/states/wob_grind_run.mss.lua
--   OT6_TIMEOUT=3600 tools/tests/run.sh tools/tests/probe_grind_run.lua   # repeat
--
-- Each invocation loads wob_grind_run.mss, fights up to 5 pocket encounters
-- tactically (pacing X 114..118 on Y 25), logs the party after each, and
-- re-publishes wob_grind_run.mss, so the chunk chain accumulates XP and at
-- most one fight is ever lost to a wipe or a kill.  The run stops early
-- (still green, still publishing) when every character who gained XP this
-- chunk is at least GOAL_LEVEL, and logs GOAL REACHED; rerun-until-you-see-it
-- is the loop.  A wipe ends the chunk without saving (the last good save
-- stands) and logs WIPE.
local H = dofile("tools/tests/lib/ot6.lua")

local GOAL_LEVEL = 21
local FIGHTS = 5

local CHAR, REC = 0x1600, 37
local function party()
  local out = {}
  for slot = 0, 15 do
    local base = CHAR + slot * REC
    local hp = H.readWord(base + 9)
    local actor = H.readByte(base)
    if actor < 16 and hp > 0 and hp < 10000 then
      out[#out + 1] = { slot = slot, actor = actor,
        level = H.readByte(base + 8), hp = hp,
        maxhp = H.readWord(base + 0xb),
        xp = H.readByte(base + 0x11) | (H.readByte(base + 0x12) << 8)
             | (H.readByte(base + 0x13) << 16) }
    end
  end
  return out
end

local xp0 = {}                 -- slot -> xp at chunk start
local wiped, goal = false, false
local tactical = H.newFightDriver("grind_run",
  { tactical = true, boost = true, items = true, healPercent = 55 })
local paceDir = "left"
local battN, sawBattle, cycleDone = 0, false, false
local function resetCycle() battN, sawBattle, cycleDone = 0, false, false end
local function frame()
  battN = H.battleLoadStarted() and battN + 1 or 0
  if battN == 0 then tactical.idle() end
  if battN >= 3 then
    sawBattle = true
    if battN == 3 then
      local w = H.formationWords()
      H.log(string.format("fight up: species %04X %04X %04X %04X %04X %04X",
        w[1], w[2], w[3], w[4], w[5], w[6]))
    end
    -- wipe = the battle module owns the HP table and every slot reads 0
    if battN > 60 then
      local alive = false
      for _, hp in ipairs(H.partyHp()) do
        if hp > 0 and hp < 10000 then alive = true end
      end
      if not alive then wiped = true; H.setPad({}); return end
    end
    tactical.frame()
    return
  end
  if sawBattle and battN == 0 and H.worldHasControl() then
    cycleDone = true
    H.setPad({})
    return
  end
  if not H.worldHasControl() then H.setPad({}); return end
  local x = H.worldX()
  if x <= 114 then paceDir = "right" elseif x >= 118 then paceDir = "left" end
  H.setPad({ [paceDir] = true })
end

local function afterFight(i)
  local ps = party()
  local minL
  for _, c in ipairs(ps) do
    local gained = xp0[c.slot] and c.xp > xp0[c.slot]
    H.log(string.format("  fight %d: slot%02d actor%02d L%d hp=%d/%d xp=%d%s",
      i, c.slot, c.actor, c.level, c.hp, c.maxhp, c.xp,
      gained and " (grinding)" or ""))
    if gained and (not minL or c.level < minL) then minL = c.level end
  end
  if minL and minL >= GOAL_LEVEL then
    goal = true
    H.log(string.format("GOAL REACHED: every grinding character is L%d+", GOAL_LEVEL))
  end
end

local steps = {
  H.loadState("build/states/wob_grind_run.mss.lua"),
  H.waitFrames(8),
  H.call(function()
    for _, c in ipairs(party()) do xp0[c.slot] = c.xp end
  end),
}
for i = 1, FIGHTS do
  steps[#steps + 1] = H.cond(function() return not (wiped or goal) end, {
    H.call(resetCycle),
    H.driveUntil(function() return cycleDone or wiped end, 14000,
      { H.call(frame) }, "grind fight " .. i),
    H.call(function()
      if wiped then
        H.log(string.format("WIPE in fight %d -- chunk ends, last save stands", i))
      else
        afterFight(i)
      end
    end),
    H.cond(function() return not wiped end,
      { H.saveState("wob_grind_run.mss") }, {}),
  }, {})
end
steps[#steps + 1] = H.call(function()
  H.log(string.format("chunk done: wiped=%s goal=%s", tostring(wiped), tostring(goal)))
end)
steps[#steps + 1] = H.logStep(function() return "done" end)
H.run({ maxFrames = 80000 }, steps)
