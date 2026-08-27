-- probe_rafterlab_fightsmart.lua -- rafter-crossing lab: cheap-fight probe.
-- Copied from probe_rafterlab_template.lua.  The field walker is fightline
-- verbatim; what varies is the BATTLE handling (@STRATEGY@ names a
-- fightsmart-<variant> that picks newFightDriver opts).  Levers under test:
--   cadence  press pacing (default 30 = 6on/24off; 12 = 6on/6off, the
--            fastest pacing the driver's own comment endorses)
--   boost    the 3 R-presses per turn (halved vs shields anyway)
--   tools    Edgar AutoCrossbow (long anim) vs plain pierce Fight
--   tactical Sabin Pummel + Edgar Tools vs everyone plain Fight
--
-- Hand-run instrument (probe_): boots build/states/rafterlab_catwalk.mss
-- (banked by probe_rafterlab_catwalk.lua: catwalk tile (6,11), chase clock
-- live at ~14760) and runs ONE crossing attempt under one strategy and one
-- RNG stagger, then reports a machine-readable [result] line and PASSes
-- either way -- this file measures, it does not assert.
--
-- The batch runner substitutes the @TOKEN@ defaults below (sed) and runs
-- many staggers per strategy; the stagger (standing still HOLD aligned
-- frames before setting off) advances the field RNG, which is what moves
-- the rats into a different arrangement per seed.
--
--   STRATEGY  fightline | avoid | hybrid
--   HOLD      aligned frames to stand still before setting off
--   RUNTRY    frames of L+R to try fleeing before the driver fights
--             (the 2026-08-26 logs show $b1=$06 held: these fights refuse
--             the run, so the default goes straight to the driver)
--   RADIUS    avoid/hybrid: manhattan keep-away radius from live rats
--   STUCKCAP  hybrid: aligned frames without progress before fighting
--   PANIC     hybrid: timer floor; below it, stop dodging and fight
--
-- Measured mechanics this file leans on (build/states/rafterlab_*.log):
--   * the chase clock $1189 ticks during battle, 1 per frame;
--   * a rat collision is ADJACENCY-triggered, object-side (obj.asm
--     DoCollision: the four tiles around the object), so a fight fires
--     with no press the moment a rat closes to manhattan 1;
--   * a WON fight's exp/gil boxes are battle-module text pages (menu==0),
--     which newFightDriver taps A through; monstersPresent() stays >0 for
--     dead-but-present rats, so it is NOT a victory signal;
--   * the win despawns the rat and clears its $034C+k switch.

local H = dofile("tools/tests/lib/ot6.lua")

local STRATEGY = "@STRATEGY@"
local HOLD     = tonumber("@HOLD@")     or 0
local RUNTRY   = tonumber("@RUNTRY@")   or 0
local RADIUS   = tonumber("@RADIUS@")   or 2
local STUCKCAP = tonumber("@STUCKCAP@") or 600
local PANIC    = tonumber("@PANIC@")    or 6000
if STRATEGY:find("@") then STRATEGY = "fightsmart-base" end

-- The battle configurations under test.  `base` is the control: the exact
-- opts the shared template hands newFightDriver.
local FIGHTOPTS = {
  ["fightsmart-base"] =
    { tactical = true,  boost = true,  cure = false, items = false },
  -- faster press pacing only
  ["fightsmart-cad12"] =
    { tactical = true,  boost = true,  cure = false, items = false,
      cadence = 12 },
  -- fast pacing, no boost R-presses
  ["fightsmart-noboost12"] =
    { tactical = true,  boost = false, cure = false, items = false,
      cadence = 12 },
  -- fast pacing, Sabin Pummel kept, Edgar plain pierce Fight (no Tools menu,
  -- no AutoCrossbow animation)
  ["fightsmart-notools12"] =
    { tactical = true,  boost = true,  tools = false, cure = false,
      items = false, cadence = 12 },
  -- fast pacing, everyone plain Fight, no boost: the cheapest menus possible
  ["fightsmart-fightonly12"] =
    { tactical = false, boost = false, cure = false, items = false,
      cadence = 12 },
  -- fast pacing, plain Fight but with boost spending
  ["fightsmart-fightboost12"] =
    { tactical = false, boost = true,  cure = false, items = false,
      cadence = 12 },
  -- boost only once 3 BP are banked: early turns act unboosted (shields
  -- halve boosted damage anyway), late turns spend 3 on broken monsters
  ["fightsmart-bank12"] =
    { tactical = true,  boost = true,  bank = 3, cure = false,
      items = false, cadence = 12 },
  -- the two winning levers combined: no boost R-presses, Edgar plain
  -- pierce Fight (no Tools menu/animation), Sabin Pummel kept
  ["fightsmart-lean12"] =
    { tactical = true,  boost = false, tools = false, cure = false,
      items = false, cadence = 12 },
  -- lean12 minus Pummel: everyone plain Fight, no boost (same as
  -- fightonly12; kept as the name the generator would use if Pummel loses)
  ["fightsmart-lean12-nopummel"] =
    { tactical = false, boost = false, cure = false, items = false,
      cadence = 12 },
}
local FOPTS = FIGHTOPTS[STRATEGY]
    or { tactical = true, boost = true, cure = false, items = false }

local GX, GY = 14, 7                    -- the Ultros entry tile
local MAXF = 20000

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + math.floor(id/8)) >> (id%8)) & 1 end
local RAT_GATE0, RAT_OBJ0 = 0x034C, 24
local function ratXY(k)
  local obj = RAT_OBJ0 + k
  return H.readWord(0x086a + 0x29 * obj) >> 4,
         H.readWord(0x086d + 0x29 * obj) >> 4
end
local function ratLine()
  local t = {}
  for k = 0, 4 do
    local ox, oy = ratXY(k)
    t[#t + 1] = string.format("%d%s@(%d,%d)", k,
      sw(RAT_GATE0 + k) == 1 and "+" or "-", ox, oy)
  end
  return table.concat(t, " ")
end
local function liveRats()
  local t = {}
  for k = 0, 4 do
    if sw(RAT_GATE0 + k) == 1 then
      local ox, oy = ratXY(k)
      t[#t + 1] = { k = k, x = ox, y = oy }
    end
  end
  return t
end
local function minRatDist(x, y)
  local best = 99
  for _, r in ipairs(liveRats()) do
    local d = math.abs(r.x - x) + math.abs(r.y - y)
    if d < best then best = d end
  end
  return best
end
local function allStanding()
  for _, c in ipairs(H.partyMembers()) do
    local hp, mx = H.charHp(c), H.charMaxHp(c)
    if not (hp > 0 and (H.charStatus1(c) & 0xC6) == 0 and hp > (mx >> 3)) then
      return false
    end
  end
  return true
end

-- one crossing attempt; fills `res`
local function cross(res)
  local hb, battN, wipeN, notBattN = 0, 0, 0, 0
  local held, lost = 0, nil
  local battleUp, wasInBattle, fightStart = false, false, 0
  local stuckN, panicking, lastDistToGoal = 0, false, 999
  local fight = H.newFightDriver("lab", FOPTS)

  local killedAt = nil                 -- hb when the last monster HP hit 0
  local function battleFrame()
    -- Neutral pad until the battle module shows its first interactive menu
    -- ($7BCA ~= 0): before that the module is loading, and an A queued
    -- during load is the suspected event-starvation hazard from the
    -- 2026-08-26 header.  After the first menu the driver owns every
    -- frame; its own menu==0 branch taps A through victory text, which is
    -- what un-parks the "Got ... Exp. point(s)" box.
    if not battleUp then
      if H.readByte(0x7BCA) ~= 0 then
        battleUp = true
        H.log(string.format("[lab] phase: first menu at f+%d", hb - fightStart))
      end
      H.setPad({})
      return
    end
    -- phase probe (read-only): the frame the last live monster HP reaches 0
    -- splits combat from the victory chew.
    if not killedAt then
      local alive = 0
      for s = 0, 5 do
        local id = H.readWord(0x3F46 + s * 2)
        if id ~= 0 and id ~= 0xFFFF and H.readWord(0x3BFC + s * 2) > 0 then
          alive = alive + 1
        end
      end
      if alive == 0 then
        killedAt = hb
        H.log(string.format("[lab] phase: last monster dead at f+%d",
          hb - fightStart))
      end
    end
    if battN < RUNTRY then H.setPad({ l = true, r = true }); return end
    fight.frame()
  end

  -- press one step of `plan` (a bfsPath list); true if it pressed
  local function pressStep(plan)
    if plan and #plan > 0 then
      H.setPad({ [H.movePress(plan[1])] = true })
      return true
    end
    return false
  end

  -- fightline's field policy: straight at the goal, push into whatever
  -- stands in the way, let adjacency fire the fight.
  local function fightlineStep(x, y)
    local plan = H.bfsPath(GX, GY)
    if pressStep(plan) then return end
    -- no geometric route: a rat plugs a corridor tile.  If one is already
    -- adjacent, press into it; otherwise walk to the nearest live rat's
    -- side and let adjacency fire.
    local rats = liveRats()
    for _, r in ipairs(rats) do
      local dx, dy = r.x - x, r.y - y
      if math.abs(dx) + math.abs(dy) <= 1 then
        local mv = (math.abs(dx) > math.abs(dy))
          and (dx > 0 and "right" or "left")
          or  (dy > 0 and "down" or "up")
        H.setPad({ [mv] = true })
        return
      end
    end
    local bestPlan
    for _, r in ipairs(rats) do
      for _, d in ipairs({ {0,-1}, {1,0}, {0,1}, {-1,0} }) do
        local pl = H.bfsPath(r.x + d[1], r.y + d[2])
        if pl and (not bestPlan or #pl < #bestPlan) then bestPlan = pl end
      end
    end
    if not pressStep(bestPlan) then H.setPad({}) end
  end

  -- avoid's field policy: BFS with a keep-away halo around every live rat;
  -- no safe route means wait (or back away when a rat closes in).
  local function avoidStep(x, y)
    local avoid = {}
    for _, r in ipairs(liveRats()) do
      for dx = -RADIUS, RADIUS do
        for dy = -(RADIUS - math.abs(dx)), RADIUS - math.abs(dx) do
          avoid[(((r.y + dy) & 0xFF) << 8) | ((r.x + dx) & 0xFF)] = true
        end
      end
    end
    local plan = H.bfsPath(GX, GY, nil, avoid)
    if plan and #plan > 0 then
      stuckN = 0
      H.setPad({ [H.movePress(plan[1])] = true })
      return
    end
    stuckN = stuckN + 1
    -- no safe route right now.  If a rat is closing in, greedily step to
    -- the neighbor that maximizes rat distance; otherwise stand still and
    -- let the wander open a gap.
    if minRatDist(x, y) <= 2 then
      local bestMv, bestD = nil, minRatDist(x, y)
      for _, mv in ipairs({ "up", "down", "left", "right" }) do
        if H.canStep(x, y, mv) then
          local d = { up = {0,-1}, down = {0,1}, left = {-1,0}, right = {1,0} }
          local nd = minRatDist(x + d[mv][1], y + d[mv][2])
          if nd > bestD then bestMv, bestD = mv, nd end
        end
      end
      if bestMv then H.setPad({ [bestMv] = true }); return end
    end
    H.setPad({})
  end

  local function fieldStep(x, y)
    -- fightsmart varies only the battle handling; the walker is always the
    -- fightline policy, so per-fight bframes compare apples to apples.
    fightlineStep(x, y)
  end

  return H.driveUntil(function()
    if H.fieldX() == GX and H.fieldY() == GY
       and H.hasControl() and H.tileAligned() then
      res.arrived = true
      H.setPad({})
      return true
    end
    if lost then H.setPad({}); return true end
    return false
  end, MAXF, { H.call(function()
    hb = hb + 1
    if hb % 600 == 0 then
      H.log(string.format("lab f%d (%d,%d) timer=%d batt=%d panic=%s rats: %s",
        H.frame, H.fieldX(), H.fieldY(), H.readWord(0x1189), battN,
        tostring(panicking), ratLine()))
    end
    if H.readWord(0x1189) == 0 and not lost then
      lost = "timeout"
      H.setPad({}); return
    end
    if map() ~= 235 and not lost then
      lost = "left map 235"
      H.setPad({}); return
    end
    wipeN = H.partyWiped() and wipeN + 1 or 0
    if wipeN >= 300 and not lost then
      lost = "wipe"
      H.setPad({}); return
    end
    if lost then H.setPad({}); return end
    -- battleLoadStarted flickers mid-battle (its RAM is shared with the
    -- field module), so neither edge is trusted raw: battN>=3 latches
    -- "really in a battle", and only ten consecutive battle-free frames
    -- count as really out.  Between the two, the pad stays neutral --
    -- field reads (dialogWaiting, hasControl) taken on flicker frames
    -- inject rogue presses into the fight's menus.
    battN = H.battleLoadStarted() and battN + 1 or 0
    notBattN = (not H.battleLoadStarted()) and notBattN + 1 or 0
    if battN >= 3 and not wasInBattle then
      wasInBattle = true
      res.fights = (res.fights or 0) + 1
      fightStart = hb
      H.log(string.format("lab: fight %d fired at (%d,%d) timer=%d rats: %s",
        res.fights, H.fieldX(), H.fieldY(), H.readWord(0x1189), ratLine()))
    end
    if wasInBattle and notBattN >= 10 then
      wasInBattle = false
      battleUp = false
      killedAt = nil
      res.bframes = (res.bframes or 0) + (hb - fightStart)
      H.log(string.format("lab: fight %d done after %d frames, timer=%d, %s standing, rats: %s",
        res.fights, hb - fightStart, H.readWord(0x1189),
        allStanding() and "all" or "NOT all", ratLine()))
    end
    if battN >= 3 then battleFrame(); return end
    if notBattN < 10 then H.setPad({}); return end
    fight.idle()
    if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
    if not H.hasControl() then H.setPad({}); return end
    if not H.tileAligned() then return end
    if held < HOLD then
      held = held + 1
      -- hold diagnostics: the screening runs collapsed h0==h120==h240 to
      -- identical trajectories, so log what the hold actually does.
      if held % 60 == 0 or held == HOLD then
        H.log(string.format("[lab] holding %d/%d at (%d,%d) hb=%d timer=%d",
          held, HOLD, H.fieldX(), H.fieldY(), hb, H.readWord(0x1189)))
      end
      H.setPad({})
      return
    end
    fieldStep(H.fieldX(), H.fieldY())
  end) }, "rafterlab cross: " .. STRATEGY)
end

local res = { arrived = false, fights = 0, bframes = 0 }
H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/rafterlab_catwalk.mss.lua"),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(map(), 235, "lab fixture boots on the rafters (map 235)")
    res.start = H.readWord(0x1189)
    H.log(string.format("[lab] set-off strategy=%s hold=%d runtry=%d radius=%d " ..
      "stuckcap=%d panic=%d timer=%d rats: %s",
      STRATEGY, HOLD, RUNTRY, RADIUS, STUCKCAP, PANIC, res.start, ratLine()))
  end),
  cross(res),
  H.call(function()
    local margin = res.arrived and H.readWord(0x1189) or 0
    local live = 0
    for k = 0, 4 do if sw(RAT_GATE0 + k) == 1 then live = live + 1 end end
    H.log(string.format("[result] strategy=%s hold=%d runtry=%d radius=%d " ..
      "stuckcap=%d panic=%d start=%d margin=%d arrived=%d standing=%d " ..
      "fights=%d bframes=%d ratsleft=%d pos=%d,%d",
      STRATEGY, HOLD, RUNTRY, RADIUS, STUCKCAP, PANIC, res.start, margin,
      res.arrived and 1 or 0, allStanding() and 1 or 0,
      res.fights or 0, res.bframes or 0, live, H.fieldX(), H.fieldY()))
  end),
})
