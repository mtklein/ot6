-- @suite savestate=camp_escaped slow
-- battle_statuses.lua -- the fight driver plans around a turn-denying
-- status (#187), measured in play rather than staged.
--
-- The exposure is the route's own: camp_escaped's world walk to the
-- Phantom Forest entrance (178,82) rolls CrassHoppr ($02F, special $4C =
-- Berserk, its script's SPECIAL on the first line) -- on this boot's
-- seed the first random lands Berserk on SHADOW as his window opens
-- (probe_statuses.lua, 2026-09-16: `[landed f610] Berserk on entity 1
-- INTO ITS OWN OPEN WINDOW: atb=0097 $3AA0=8F menu=01 st=01 actor=1`),
-- and the second on CYAN.  Before the fix the driver logged `actor=1
-- char=3 plan=fight` for the berserked SHADOW and lost the plan as
-- actor_changed when the engine took the window; a Stop or Sleep in a
-- list would have parked until the watchdog.
--
-- The two battles the direct walk happens to draw are not the exposure,
-- though -- SPECIAL is the monster's own roll inside them.  A seed sweep
-- of the direct walk (build/sweeps/statuses-fix2) fought the same
-- CrassHoppr formation on every seed and still came away with nothing on
-- 2 of 8: `a turn-denying status landed on the walk (the exposure; 2
-- battle(s) fought): got false, want true` at shifts 7 and 13.  So the
-- walk PACES the route's own leg between (176,71) and (178,81) until a
-- turn-denying status has actually landed, and only then turns into the
-- forest: the run reaches the exposure instead of hoping the two battles
-- on the direct line contain it.  The lap count is bounded, so a walk
-- that really cannot draw one still fails loudly at the same assertion.
--
-- The walk is navTo's playBattles="tactical" (M.newFightDriver with the
-- walk options), the driver every route segment fights with.  The test
-- captures the driver's log through H.log and watches the four status
-- bytes on a startFrame callback (reads only), and asserts:
--   * Berserk landed on a party member at least once (the exposure; a
--     walk that no longer draws it fails here, loudly, rather than pass
--     on nothing);
--   * the driver said `[status] ... is under BERSERK` once per
--     (entity, battle) it landed on, with the cure verdict from the ROM
--     ("none in the bag": Remedy's STATUS2 byte is $48) -- counted over
--     the whole battle, which is the span the driver's own statusSaid
--     table is keyed by, and not over this watcher's window: the driver
--     and this watcher log on different callbacks within one frame, so
--     which side of the window boundary that one line falls on is not a
--     property of the driver at all (see the comment at the count);
--   * it never planned for that entity while the status stood (no
--     `actor=<e> char=.. plan=` line inside the window), never counted a
--     park or a pulse budget against it, and the recovery cap never fired;
--   * the walk arrived (map 132), so the fights ended in wins.
-- If a `[layout] ... preemptive` line occurs (#186, a 1/8 roll), the
-- free-round line must follow it in that battle before any top-up heal.
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/camp_escaped.mss.lua"
local MENU, ACTOR = 0x7BCA, 0x62CA
local S1, S2, S3 = 0x3EE4, 0x3EE5, 0x3EF8

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end

-- the driver's log, captured line by line (H.log is the lib's M.log;
-- every driver line goes through it)
local lines = {}
local rawLog = H.log
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  return rawLog(msg)
end

-- status watch: per battle, per entity, when a denying status landed
-- and cleared (in captured-line indices, so the plan lines can be
-- located between them)
local battles, cur = {}, nil
local last = {}
-- set the frame a turn-denying status first lands anywhere in the party:
-- the pacing laps below end on it
local landedAny = false
local function observe()
  if not H.battleLoadStarted() then
    if cur then
      -- a status that ended with the battle closes its window here, at
      -- this battle's last line, not at the end of the run
      for e, o in pairs(cur.open) do
        o.to = #lines
        cur.landed[#cur.landed + 1] = o
        H.log(string.format("[test] battle %d: %s on entity %d ended with the battle (line %d)",
          cur.n, o.name, e, #lines))
      end
      cur.open = {}
      cur.to = #lines
      battles[#battles + 1] = cur; cur = nil; last = {}
    end
    return
  end
  if cur == nil then cur = { n = #battles + 1, landed = {}, open = {}, from = #lines } end
  for e = 0, 3 do
    if H.readWord(0x3C1C + e * 2) > 0 then
      local s1, s2, s3 = H.readByte(S1 + e * 2), H.readByte(S2 + e * 2), H.readByte(S3 + e * 2)
      local den = H.turnDenied({ s1 = s1, s2 = s2, s3 = s3 })
      local was = last[e]
      if den ~= nil and was == nil then
        landedAny = true
        cur.open[e] = { name = den, entity = e, at = #lines, frame = H.frame,
                        ownWindow = H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) == e }
        H.log(string.format("[test] battle %d: %s landed on entity %d at f%d (line %d)%s",
          cur.n, den, e, H.frame, #lines, cur.open[e].ownWindow and " in its own window" or ""))
      elseif den == nil and was ~= nil then
        local o = cur.open[e]
        o.to = #lines
        cur.landed[#cur.landed + 1] = o
        cur.open[e] = nil
        H.log(string.format("[test] battle %d: %s off entity %d at f%d (line %d)",
          cur.n, was, e, H.frame, #lines))
      end
      last[e] = den
    end
  end
end

-- the route's own leg, paced: (176,71) and (178,81) are both on the line
-- camp_escaped's walker already plans through to the forest mouth (the
-- wnav trace logs both), so a lap between them is the same walk, walked
-- again, and draws the same randoms.
local PACE_A, PACE_B = { 176, 71 }, { 178, 81 }
-- How many laps is measured, not guessed.  build/lab/statuses/probe_pace.lua
-- walked this leg with a 14-lap budget and logged the stage species and
-- every monster dispatch: CrassHopprs are in the formation on every seed, but the
-- Berserk needs one of them to live to its turn AND its script to pick
-- SPECIAL AND the rider to stick.  It arrived in battle 5 at shift 13
-- (probe_shift13_deep.log, f10311) and in battle 8 at shift 7
-- (probe_shift7_deep.log, f21617, whole run 24076 frames).  Across the
-- eight sweep seeds the legs actually entered before it landed were
-- 1,1,1,2,2,2,4,11 (build/sweeps/statuses-paced): twelve laps is
-- twenty-four legs, better than twice the worst of those, and only an
-- unlucky seed ever walks past the second.
local PACE_LAPS = 12
local function leftTheWorld() return not H.worldMode() end
-- A lap is taken or skipped WHOLE: the decision is made at the leg's own
-- start, never mid-battle.  Cutting a leg short inside a battle would
-- hand that battle to the next leg's freshly built fight driver, whose
-- statusSaid table starts empty -- it would say the [status] line a
-- second time for a status it had already reported, and the count below
-- would read 2 for one landing.
local function walk()
  local steps = {
    H.worldNavTo(PACE_A[1], PACE_A[2], { maxFrames = 25000,
      playBattles = "tactical", arrive = leftTheWorld }),
  }
  for lap = 1, PACE_LAPS do
    for _, wp in ipairs({ PACE_B, PACE_A }) do
      local x, y = wp[1], wp[2]
      steps[#steps + 1] = H.cond(function() return not landedAny end, {
        H.call(function()
          H.log(string.format("[test] lap %d: no turn-denying status yet after "
            .. "%d battle(s) -- pacing to (%d,%d) to draw more",
            lap, #battles + (cur and 1 or 0), x, y))
        end),
        H.worldNavTo(x, y, { maxFrames = 25000, playBattles = "tactical",
          arrive = leftTheWorld }),
      })
    end
  end
  steps[#steps + 1] = H.worldNavTo(178, 82, { maxFrames = 25000,
    playBattles = "tactical", arrive = leftTheWorld })
  return steps
end

H.run({ maxFrames = 120000 }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "camp_escaped boots on the World of Balance")
    emu.addEventCallback(function() observe() end, emu.eventType.startFrame)
  end),
  H.cond(function() return true end, walk()),   -- the library's own list fold
  H.waitUntil(function() return mapIdx() == 132 end, 4000, "the forest loads", 5),
  H.call(function()
    -- close a battle still open in the watch (none expected on the field)
    if cur then cur.to = #lines; battles[#battles + 1] = cur; cur = nil end
    for _, b in ipairs(battles) do
      b.to = b.to or #lines
      for _, o in pairs(b.open) do o.to = b.to; b.landed[#b.landed + 1] = o end
    end
    local seen = 0
    for _, b in ipairs(battles) do
      -- The [status] line is counted over the WHOLE BATTLE, not over the
      -- watcher's own window.  The driver says it "the frame it lands"
      -- (lib/ot6.lua, statusSaid: once per battle per entity per status);
      -- this watcher runs on startFrame and so first SEES the bit on the
      -- next frame, by which time the driver has already logged the
      -- [status] line and whatever else that frame produced.  Whether
      -- the line falls inside [o.at, o.to] was therefore decided by how
      -- many other lines the driver happened to emit in between: on
      -- main's camp_escaped walk battle 1's [status] line was the last
      -- line before o.at (counted, verdict 1) and battle 2's was followed
      -- by one `battle f+300 ...` heartbeat (not counted, verdict 0) --
      -- the same run, the same driver, the same status, opposite
      -- verdicts.  The battle span is the boundary the property is
      -- actually stated against, and it does not move.
      local said = {}
      for i = b.from, b.to do
        local s = lines[i]
        local e, name = s:match("%[status%] f%+%d+ entity (%d+) char %d+ is under (%u+)")
        if e then
          local key = tonumber(e) .. ":" .. name
          said[key] = (said[key] or 0) + 1
        end
      end
      -- one verdict per (entity, status) the watch saw land, in landing
      -- order, so a status that landed twice in one battle is still one
      -- verdict -- statusSaid says the line once per battle, not once per
      -- landing
      local asked = {}
      for _, o in ipairs(b.landed) do
        local key = o.entity .. ":" .. o.name:upper()
        if not asked[key] then
          asked[key] = true
          H.assertEq(said[key] or 0, 1, string.format(
            "battle %d: one [status] line for the %s that landed on entity %d",
            b.n, o.name, o.entity))
        end
      end
      for _, o in ipairs(b.landed) do
        seen = seen + 1
        local e, name = o.entity, o.name
        local planLines, parkLines = 0, 0
        for i = o.at, o.to do
          local s = lines[i]
          if s:find("actor=" .. e .. " char=%d+ plan=") then planLines = planLines + 1 end
          if s:find("parked %d+ pulses") or s:find("consumed %d+ pulses")
             or s:find("FIGHT DRIVER STUCK") or s:find("recovery cap") then
            parkLines = parkLines + 1
          end
        end
        H.assertEq(planLines, 0, string.format("battle %d: no plan made for entity %d while under %s",
          b.n, e, name))
        H.assertEq(parkLines, 0, string.format("battle %d: no park, pulse-budget or recovery-cap line under %s",
          b.n, name))
        if name == "Berserk" then
          local cureSaid = false
          for i = b.from, b.to do
            if lines[i]:find("cure: none in the bag %(Remedy x%d+ carries no Berserk bit%)") then cureSaid = true end
          end
          H.assertEq(cureSaid, true, string.format("battle %d: the [status] line carries the ROM's cure verdict", b.n))
        end
      end
    end
    H.assertEq(seen >= 1, true, "a turn-denying status landed on the walk (the exposure; "
      .. #battles .. " battle(s) fought)")
    -- #186: a preemptive layout line is followed by the free-round line
    -- before any top-up in that battle
    local pre, free, topUp = nil, nil, nil
    for i, s in ipairs(lines) do
      if s:find("%[layout%] battle type .* preemptive") and pre == nil then pre = i end
      if pre and free == nil and s:find("the preemptive strike's free round") then free = i end
      if pre and topUp == nil and s:find(" heal entity %d+ %(") then topUp = i end
    end
    if pre ~= nil then
      H.assertEq(free ~= nil and (topUp == nil or free < topUp), true,
        "the free-round line follows the preemptive layout before any top-up")
      H.log("[test] preemptive strike measured at line " .. pre)
    else
      H.log("[test] no preemptive strike rolled on this walk (a 1/8 roll per battle)")
    end
    H.log(string.format("[test] statuses landed: %d over %d battle(s); driver planned around every one",
      seen, #battles))
  end),
})
