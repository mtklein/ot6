-- gen_sfigaro.lua -- from locke_scenario.mss (LOCKE alone, one step past the
-- three-way hub, map 75 at (47,43)) through occupied South Figaro to the
-- doorstep of the rich man's secret passage.  The first link of the v0.3
-- Locke chain.
-- Mints two states:
--   sfigaro_town.mss     map 75, the gate soldier beaten and LOCKE wearing
--                        the merchant's clothes with the old man's cider
--   sfigaro_passage.mss  map 86 (7,51), inside the secret passage the
--                        grandson's password opens
--
-- FIVE THINGS THIS SCRIPT HAD TO MEASURE, every one of which sent a first
-- attempt into a wall.
--
-- 1. THE DISGUISES COME OFF A *STEAL*, NOT OFF A WIN.  This is the finding
--    that shapes the whole file.  Merchant $13A and Officer $175 each carry
--    a reaction script whose only branch is `if_cmd STEAL`
--    (battle/ai_script.asm AIScript::_314 / _373): it sets battle switch
--    (13,4) / (13,5), swaps the monster for the b.day suit and ends the
--    fight.  Those are b_switch $4C / $4D, and the event script reads
--    exactly them -- `if_b_switch $4C, _ca8617` (event_main.asm:20385),
--    `if_b_switch $4D, _ca7ecf` (:19340).  EventCmd_b7 jumps when the bit is
--    CLEAR (field/event.asm:4053-4060), and the jump target is the branch
--    that SKIPS `obj_gfx LOCKE, MERCHANT` / `switch $0104=1`.  So a fight
--    finished any other way leaves Locke in his own clothes: measured, the
--    harness's kill-bit idiom beat the officer clean and $0103 stayed 0.
--    In battle those flags live at $3EB4+n -- the field copy $1DC9+n is
--    loaded in at battle start and written back at the end
--    (battle_main.asm:6088, :12182) -- so $4C is bit 4 of $3EBD live and of
--    $1DD2 afterwards.  Both are asserted below.
--
-- 2. AND THE MERCHANT'S CLOTHES ARE NOT OPTIONAL SCENERY.  Map 86's
--    grandson, npc 4 at {6,10}, is the gate: `if_switch $0104=1, _ca7bf8`
--    else "Only people dressed as merchants may pass through"
--    (event_main.asm:18747-18752).  Nothing else on the route opens.
--
-- 3. ONE FIGHT PAYS FOR BOTH ERRANDS.  The cafe's cider runner -- map 78
--    npc 6 at {75,39}, spawn switch $0307, `_ca7d7d` -> `_ca7db8` -- runs
--    `battle 10` and then, win or steal, ends `switch $01D0=1` ("Took the
--    old man's cider!", :19061).  Steal it and the same scene also hands
--    over the clothes.  The item-shop merchant on map 85 gives the clothes
--    alone, so the cafe is strictly the cheaper stop.
--
-- 4. THE TOWN IS NOT ONE-WAY -- THE PATHFINDER'S NODE CAP JUST LOOKS LIKE
--    IT.  H.bfsPath gives up at 4096 dequeues, and map 75 is a 64x64 town
--    with z-levels, so a long query runs the queue dry and answers "no
--    path" for a tile that is plainly walkable.  Measured, and it is a
--    ONE-TILE cliff: from (22,43) the plan to (37,41) is 49 steps and
--    found; from (22,44), one tile further along that same plan, the same
--    query returns nil.  A first cut read that as "the SE quarter is behind
--    a one-way z step" and rebuilt the route around a wall that is not
--    there.  Every long leg here is therefore walked as SHORT HOPS through
--    named waypoints, which keeps each query far inside the cap.
--
-- 5. A DESTINATION COORDINATE IS NOT AN ARRIVAL TEST.  `go` used to call
--    "standing on (dx,dy)" arrival for every crossing; map 78's front room
--    contains a walkable (22,44), the same tile the town door lands on, so
--    the walk to the exit "arrived" twenty tiles early on the wrong map and
--    the settle then waited 12000 frames for a map id that was never
--    coming.  Only a SAME-MAP warp has no map change to watch.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/locke_scenario.mss.lua"

-- map compares stay MASKED: loaders ride flag bits in $1F64's high byte
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
-- event switch id -> live bit (event bitfield base $1E80, bit = id & 7)
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
-- field object i's live tile (pixel coords >> 4, block stride $29)
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end
-- party facing, through the party-object offset ($0803)
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
-- a bare step list cannot be spliced into a step list (Lua truncates a
-- non-final table.unpack to one value); H.cond with an always-true
-- predicate is the library's public way to wrap a list into ONE step
local function seq(steps) return H.cond(function() return true end, steps) end

local FACE = { up = 0, right = 1, down = 2, left = 3 }
local NEIGHBOURS = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}
-- all EIGHT for door staging: a door at the head of a stair can only be
-- entered diagonally (gen_edgar's finding), and a diagonal candidate has to
-- clear one extra test -- the engine must actually produce that move there
local DIAGSTAGE = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { -1, 1, "upright" }, { -1, -1, "downright" },
  { 1, -1, "downleft" }, { 1, 1, "upleft" },
}

local WATCH = { 0x0103, 0x0104, 0x0105, 0x0107, 0x001C, 0x001D, 0x001E,
                0x0317, 0x01D0, 0x01F0, 0x01F1 }
local function where(tag)
  local out = {}
  for _, s in ipairs(WATCH) do out[#out + 1] = string.format("%04X=%d", s, sw(s)) end
  H.log(string.format("[%s] f%d map=%d (%d,%d) bright=%d ctl=%s | %s",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), bright(),
    tostring(H.hasControl()), table.concat(out, " ")))
end

-- Settle after a map load: a fully lit screen plus whatever else the caller
-- names, held for 20 CONSECUTIVE frames, then the 30-frame margin every
-- field fixture uses.  Both halves are load-bearing (gen_kolts's header):
-- a cutscene can report control on a black screen, and a single-sample gate
-- passes mid-load while the field module still holds the old map's state.
-- It DRIVES rather than waits so a dialog on the arrival tile cannot stall
-- it; on a quiet field advanceStory holds the pad empty.
local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end
local function settleField(dstMap, maxF)
  return seq({
    H.waitFrames(60),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), maxF or 12000),
    H.waitFrames(30),
  })
end

local aPhase = 0

-- Ride a scene out to a settled, controllable field, edge-tapping A on EVERY
-- frame the party is not in control and kill-bitting anything that comes up.
--
-- WHY NOT advanceStory HERE.  advanceStory taps A only while a battle is up
-- or H.dialogWaiting() is true, and holds the pad empty otherwise.  The tail
-- of `battle 11` has a window state that satisfies NEITHER: measured at the
-- third gate-soldier fight, $0059 = $52 (a menu module owns the CPU) with
-- $BA/$D3 both clear, so dialogWaiting() is false, the battle flag is
-- already down, and advanceStory sat with the pad empty for 20000 frames
-- while the event PC stayed parked at $CA85B9.  Tapping A on "no control"
-- rather than on "a signal I recognise" clears it, and it cannot misfire on
-- the open field because the tap is gated on NOT having control.
-- (Choice prompts are the one thing this must never meet -- an A press
-- always takes option 0 -- so every prompt on the route is answered by
-- rideUntil below, which steers the cursor explicitly.)
local function rideOut(what, budget, dstMap)
  local phase, calm = 0, 0
  return seq({
    H.driveUntil(function()
      local ok = H.hasControl() and H.tileAligned() and bright() >= 15
             and not H.battleLoadStarted() and not H.dialogWaiting()
             and (dstMap == nil or map() == dstMap)
      calm = ok and calm + 1 or 0
      return calm >= 20
    end, budget or 20000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.battleLoadStarted() then
          -- LOSING battle 11 IS A ROUTE FAILURE, not a retry.  `if_b_switch
          -- $40` jumps to the win branch when the bit is CLEAR; with it set
          -- the soldier's event falls through to `call _ca85ba`
          -- (event_main.asm:20300), which is `load_map 75, {47,43}` + "Ouch!!
          -- I gotta steal me some new clothes, fast!!" + `switch $0104=0` +
          -- `switch $0103=0` -- the scenario reset.  Measured: the THIRD
          -- gate-soldier fight killed LOCKE (194 hp against a HeavyArmor
          -- that had already been fought twice), the ride came back 230
          -- frames longer than usual, and the party was standing on the
          -- opening tile with both disguises gone.  So the party's hp is
          -- pinned to max for the duration, the same way gen_vargas pins
          -- it through a fight it only wants the SCRIPT's outcome from.
          for e = 0, 3 do
            H.writeWord(0x3BF4 + e * 2, H.readWord(0x3C1C + e * 2))
          end
          if H.monstersPresent() > 0 then
            for slot = 0, 5 do
              if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
                H.writeByte(0x3eec + slot * 2,
                  H.readByte(0x3eec + slot * 2) | 0x80)
              end
            end
          end
        end
        if H.hasControl() then H.setPad({}); return end
        H.setPad(phase < 4 and { "a" } or {})
      end),
    }, what),
    H.release(),
    H.waitFrames(30),
  })
end

-- One SHORT leg to a waypoint on the current map.  See note 4: long BFS
-- queries on map 75 run the 4096-node cap dry and answer "no path" for
-- tiles that are plainly walkable, so every cross-town walk is a chain of
-- these rather than one query.
local function hop(tx, ty, what)
  return seq({
    H.navTo(tx, ty, { maxFrames = 12000 }),
    H.release(),
    H.call(function()
      H.assertEq(H.fieldX(), tx, what .. ": at x=" .. tx)
      H.assertEq(H.fieldY(), ty, what .. ": at y=" .. ty)
    end),
  })
end

-- One crossing, all three flavours in one step:
--   * ordinary walkable entrance tile    -> navTo straight onto it
--   * door tile (a wall until CheckDoor)  -> stage on a neighbour, hold in
--   * same-map warp (maps 78/83/86 are built out of them)
-- CheckDoor (field/player.asm:958-1010) only opens a tile whose TILEMAP
-- BYTE is $15/$17/$1C, and only for a party standing directly above or
-- below it; anything else is a wall no amount of holding will move.
local function go(sx, sy, dm, dx, dy, what)
  local pick, startMap
  local function arrived()                       -- see note 5
    if dm ~= startMap then return map() ~= startMap end
    return H.fieldX() == dx and H.fieldY() == dy
  end
  -- THE STAGING TILE IS RE-RESOLVED, NOT LATCHED.  Town NPCs wander, and
  -- the object map they occupy is an input to every passability query, so
  -- the answer is only true for the instant it was asked: measured, the
  -- cafe's annex warp (33,46) resolved as "walkable, stand on it" on one
  -- run and, 36 frames earlier on the next, as "unreachable -- stage at
  -- (33,47)" -- and then navTo could not reach (33,47) either, because the
  -- npc had moved again by the time it planned.  Latching the first answer
  -- turns a transient into a route failure; re-asking every 90 frames lets
  -- the walk recover on its own.
  local pickAt = -1000
  local function stage()
    if pick == nil or (H.frame - pickAt >= 90 and not arrived()) then
      pickAt = H.frame
      local fresh
      if H.bfsPath(sx, sy) then
        fresh = { sx, sy, nil }                  -- walkable: stand on it
      else
        for _, c in ipairs(DIAGSTAGE) do
          local cx, cy, move = sx + c[1], sy + c[2], c[3]
          local press = H.movePress(move)
          if H.bfsPath(cx, cy)
             and (press == move or H.canStep(cx, cy, move)) then
            fresh = { cx, cy, press }; break
          end
        end
      end
      fresh = fresh or pick or { sx, sy + 1, "up" }
      if pick == nil or fresh[1] ~= pick[1] or fresh[2] ~= pick[2]
         or fresh[3] ~= pick[3] then
        pick = fresh
        H.log(string.format("%s: staging (%d,%d)%s at f%d", what,
          pick[1], pick[2],
          pick[3] and (", hold " .. pick[3] .. " into (" .. sx .. "," .. sy .. ")")
                  or " (walk straight onto the entrance tile)", H.frame))
      end
    end
    return pick
  end
  return seq({
    H.call(function() pick, startMap = nil, map() end),
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 20000, arrive = arrived }),
    H.cond(function() return stage()[3] ~= nil end, {
      H.driveUntil(arrived, 1800, {
        H.call(function()
          aPhase = (aPhase + 1) % 8
          if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
          H.setPad({ [stage()[3]] = true })
        end),
      }, what .. ": hold into the door"),
    }, {}),
    H.release(),
    settleField(dm),
    H.call(function()
      H.assertEq(map(), dm, what .. ": landed on map " .. dm)
      H.log(string.format("%s: DONE map=%d (%d,%d) f%d", what,
        map(), H.fieldX(), H.fieldY(), H.frame))
    end),
  })
end

-- gen_banon's talkToObj, unchanged in shape: approach re-resolved from live
-- object coords (NPCs wander), facing computed from the live delta, soft
-- rounds before a hard one.  CheckNPCs activates whatever the object map
-- holds ONE TILE IN THE PARTY'S FACING DIRECTION while A is held, and a
-- two-frame turn press does not set the facing byte -- so the direction is
-- HELD until it reads back, and only then is A edge-tapped.
local function talkToObj(obj, what, maxF)
  local engaged = false
  local function objAt() return objX(obj), objY(obj) end
  local function adjacent()
    local ox, oy = objAt()
    return math.abs(ox - H.fieldX()) + math.abs(oy - H.fieldY()) == 1
  end
  local apFrame, apPick = -1000, nil
  local function approach()
    if H.frame - apFrame >= 30 then
      apFrame = H.frame
      local ox, oy = objAt()
      apPick = { ox, oy + 1 }
      for _, c in ipairs(NEIGHBOURS) do
        local cx, cy = ox + c[1], oy + c[2]
        if H.bfsPath(cx, cy) then apPick = { cx, cy }; break end
      end
    end
    return apPick
  end
  local function walkStep()
    return H.navTo(function() return approach()[1] end,
                   function() return approach()[2] end, {
      maxFrames = maxF or 20000,
      arrive = function()
        return engaged or (adjacent() and H.hasControl() and H.tileAligned())
      end,
    })
  end
  local function pokeStep(round, budget, hard)
    local started, waited, aPh = 0, 0, 0
    return H.driveUntil(function()
      started = (H.eventRunning() or H.dialogWaiting()) and started + 1 or 0
      if started >= 6 then engaged = true; return true end
      waited = waited + 1
      return not hard and waited > budget
    end, budget + 120, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if not (H.hasControl() and H.tileAligned() and adjacent()) then
          H.setPad({}); return
        end
        local ox, oy = objAt()
        local dx, dy = ox - H.fieldX(), oy - H.fieldY()
        local dir = dx == 1 and "right" or dx == -1 and "left"
                 or dy == 1 and "down" or "up"
        if facing() ~= FACE[dir] then H.setPad({ [dir] = true }); return end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, string.format("%s: activation round %d", what, round))
  end
  return seq({
    H.call(function() engaged, apFrame, apPick = false, -1000, nil end),
    walkStep(), pokeStep(1, 600, false),
    -- flat, not repeatN: it cannot replay navTo/driveUntil bodies
    H.cond(function() return not engaged end,
      { walkStep(), pokeStep(2, 900, true) }, {}),
    H.release(),
  })
end

-- gen_scenario.lua's choice-steering idiom, unchanged in shape.  $056F is
-- the option count and is only final once dialogWaiting() is true (it is
-- built up as the text types out, and it is meaningless during a battle);
-- $056E is the 0-based selection; the steering presses are EDGES because
-- $056D latches a held direction to exactly one row (field/text.asm:368-425).
local CH_SEL, CH_MAX = 0x056E, 0x056F
local function rideUntil(pred, what, budget, choices)
  local phase, dlgN, ci, inChoice = 0, 0, 0, false
  return H.driveUntil(pred, budget or 20000, {
    H.call(function()
      phase = (phase + 1) % 8
      dlgN = H.dialogWaiting() and dlgN + 1 or 0
      local chMax = (not H.battleLoadStarted()) and H.readByte(CH_MAX) or 0
      if chMax >= 2 then
        if not H.dialogWaiting() then H.setPad({}); return end
        if not inChoice then
          inChoice = true; ci = ci + 1
          local c = (choices or {})[ci]
          if not c then
            error(string.format("%s: unexpected choice prompt #%d (%d options)",
              what, ci, chMax), 0)
          end
          H.assertEq(chMax, c.max,
            string.format("%s choice #%d option count (%s)", what, ci, c.what))
          H.log(string.format("%s: CHOICE #%d up (%d options) -- taking %d :: %s",
            what, ci, chMax, c.want, c.what))
        end
        local c, sel = choices[ci], H.readByte(CH_SEL)
        if sel < c.want then H.setPad(phase < 4 and { "down" } or {})
        elseif sel > c.want then H.setPad(phase < 4 and { "up" } or {})
        else H.setPad(phase < 4 and { "a" } or {}) end
        return
      elseif inChoice then
        inChoice = false
        H.log(string.format("%s: choice #%d resolved at f%d", what, ci, H.frame))
      end
      if dlgN >= 3 then H.setPad(phase < 4 and { "a" } or {}); return end
      H.setPad({})
    end),
  }, what)
end

-- talk to `obj`, then ride what it says (steering `choices`) back to a
-- settled, controllable field
local function talkThrough(obj, what, choices, budget)
  local calm = 0
  return seq({
    talkToObj(obj, what),
    rideUntil(function()
      local ok = H.hasControl() and H.tileAligned() and bright() >= 15
             and not H.dialogWaiting() and not H.eventRunning()
             and not H.battleLoadStarted()
      calm = ok and calm + 1 or 0
      return calm >= 30
    end, what, budget or 20000, choices),
    H.release(),
  })
end

-- THE GATE SOLDIER COMES BACK EVERY TIME MAP 75 RELOADS.  `hide_obj NPC_11`
-- (_ca856a, event_main.asm:20313) is a RUNTIME bit, not story state: leaving
-- town for an interior and coming back re-runs InitNPCs (field/init.asm:469
-- only skips it when reloading the SAME map) and re-creates every npc whose
-- spawn switch still holds.  His is $030C and nothing in the scenario clears
-- it.  So (30,42) -- the ONE tile joining the SE quarter to the rest of town
-- -- is plugged again on every return, and this route crosses that boundary
-- three times.  The soldier's uniform is no answer: `if_switch $0103=1` only
-- swaps his fight for a bare "Halt!" (:20296); it does not move him.
-- Gated on the SYMPTOM (a BFS probe to a tile on the far side) rather than
-- assumed, so the day the respawn stops happening this says so instead of
-- walking into a fight that is not there.
local function clearGateSoldier(probeX, probeY, tag)
  return H.cond(function() return H.bfsPath(probeX, probeY) == nil end, {
    H.logStep(function()
      return string.format("%s: (%d,%d) unreachable at f%d -- the gate " ..
        "soldier is back at (%d,%d); fighting him again",
        tag, probeX, probeY, H.frame, objX(26), objY(26))
    end),
    talkToObj(26, tag .. ": the gate soldier again"),
    rideOut(tag .. ": ride battle 11 out", 20000, 75),
    H.call(function()
      -- the reset's signature is the opening tile plus a bare LOCKE; if the
      -- fight went that way, say THAT rather than "no path"
      H.assertEq(H.fieldX() == 47 and H.fieldY() == 43, false,
        tag .. ": not dumped back on the scenario's opening tile")
      H.assertEq(H.bfsPath(probeX, probeY) ~= nil, true,
        tag .. ": the lane is open again")
      H.log(string.format("%s: done at (%d,%d) f%d, $0104=%d",
        tag, H.fieldX(), H.fieldY(), H.frame, sw(0x0104)))
    end),
  }, {
    H.logStep(function() return tag .. ": the lane is already open" end),
  })
end

-- ------------------------------------------------------------- the steal --
-- Locke's command window is `FIGHT, STEAL, MAGIC, ITEM`
-- (field/char_prop.asm:160), two columns by two rows, so STEAL is one DOWN
-- from the resting cursor.  A confirms it, and A again takes the single
-- enemy the target cursor already sits on.  Driven as discrete pad EDGES
-- into the command window, the same way gen_vargas enters Pummel.
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD = 0x05
local B_SWITCH_LIVE = 0x3EBD          -- $3EB4 + ($4C >> 3); bit4 = $4C
local function pinParty()
  for e = 0, 3 do H.writeWord(0x3BF4 + e * 2, H.readWord(0x3C1C + e * 2)) end
end
-- THREE OT6 corrections make this STEAL land (each measured; without them the
-- steal misses forever -- 32 attempts, identical frames, $3EBD never moves):
--  1. STEAL COSTS 2 MP (ot6.asm Ot6AbilityCost @steal, "flat small").  The
--     charge+refusal is universal, so a char below 2 MP has the command REFUSED
--     -- the menu confirms but no action queues (TargetEffect_52's $3401 never
--     fires).  Solo early Locke has too little, so pin battle MP ($3C08) up.
--  2. STEAL IS A BOOST-TIERED CHANCE VERB (ot6.asm Ot6StealBoostLevel, hooked
--     at battle_main.asm:9366): 0 bp rolls RAW vanilla odds (~0 for this
--     underleveled Locke vs the Merchant), 3 bp is CERTAIN.  Force banked+pending
--     boost ($3e9c/$3e9d, even char offsets 0,2,4,6) to the cap.
--  3. THE COMMAND CURSOR DOES NOT MOVE on a held d-pad here (measured), so the
--     old down+A picked FIGHT.  Poke STEAL ($05) into ALL of the actor's command
--     cells (CMDTBL 0x202E, stride 12/entity, 3/cell -- gen_vargas's Blitz-poke
--     idiom) so the resting cursor + A = STEAL; a second A takes the lone enemy.
local CMDTBL = 0x202E
local function stealDriver(what, maxF)
  local ph, tries = 0, 0
  return H.driveUntil(function() return not H.battleLoadStarted() end,
    maxF or 20000, {
      H.call(function()
        pinParty()
        for e = 0, 3 do H.writeWord(0x3C08 + e * 2, 99) end          -- (1) MP
        for i = 0, 6, 2 do H.writeByte(0x3e9c + i, 5); H.writeByte(0x3e9d + i, 3) end  -- (2)
        ph = (ph + 1) % 6
        if H.readByte(MENU) ~= 0 then
          local a = H.readByte(ACTOR)
          for i = 0, 3 do H.writeByte(CMDTBL + a * 12 + i * 3, 0x05) end  -- (3) STEAL
          if H.readByte(MSTATE) == ST_CMD and ph == 0 then
            tries = tries + 1
            H.log(string.format("%s: STEAL attempt %d f%d actor=%d $3EBD=%02X",
              what, tries, H.frame, a, H.readByte(B_SWITCH_LIVE)))
          end
          H.setPad(ph < 3 and { "a" } or {})
          return
        end
        H.setPad(ph < 3 and { "a" } or {})   -- no menu: edge-tap through messages
      end),
    }, what .. ": steal the clothes")
end

-- ========================================================================= --
H.run({ maxFrames = 150000 }, {
  H.loadState(DOOR),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 75, "booted on map 75, occupied South Figaro")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(sw(0x0105), 1, "$0105 -- LOCKE's scenario is live")
    H.assertEq(sw(0x001E), 0, "$001E clear -- the scenario is not done")
    where("boot")
  end),

  -- ===================================================================== --
  -- BEAT 1: the soldier who bars the gate.  Map 75 npc 10 = obj 26, spawn
  -- switch $030C, at {30,42}: _ca854f (event_main.asm:20296) opens
  -- `dlg $0174 "Halt!"` + `battle 11, TOWN_EXT` -> formation 64,
  -- HeavyArmor $09F.  He is a PLUG, not scenery: (30,42) is the only tile
  -- joining the starting pocket to the rest of town, and BFS reaches
  -- exactly 107 tiles until he is gone.  Won any way at all -- the clothes
  -- branches are a different fight -- so the kill-bit idiom is correct here.
  -- ===================================================================== --
  talkToObj(26, "the gate soldier (battle 11 -> HeavyArmor $09F)"),
  rideOut("ride battle 11 out", 20000, 75),
  H.call(function()
    H.assertEq(map(), 75, "still in town after battle 11")
    H.assertEq(H.bfsPath(22, 43) ~= nil, true,
      "the town opened: the cafe doorstep is reachable now")
    where("town open")
  end),

  -- ===================================================================== --
  -- BEAT 2: the cafe's cider runner.  Map 78 npc 6 = obj 22 at {75,39},
  -- behind the annex warp (33,46)->(74,43).  `battle 10, TOWN_INT` ->
  -- formation 43, Merchant $13A (slot 1, $13B, is the b.day suit the steal
  -- swaps him for).  STEAL, do not kill: see note 1.
  -- ===================================================================== --
  go(22, 42, 78, 26, 52, "C1 town (22,42) -> map 78 (26,52) [CAFE]"),
  go(33, 46, 78, 74, 43, "C2 map 78 (33,46) -> (74,43) [annex warp]"),
  talkToObj(22, "the cider runner"),
  -- ride the two dialogs into the fight BY HAND: advanceStory would
  -- kill-bit the merchant, and the clothes only come off a steal
  H.driveUntil(function() return H.battleLoadStarted() end, 9000, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      H.setPad(aPhase < 4 and { "a" } or {})
    end),
  }, "the cider scene reaches battle 10"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 6000, "battle 10 up", 10),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(H.formationHas({ [0x013A] = true }), true,
      "battle 10 is formation 43 -- Merchant $13A")
    local w = H.formationWords()
    H.log(string.format("battle 10: %04X %04X %04X %04X %04X %04X  $3EBD=%02X",
      w[1], w[2], w[3], w[4], w[5], w[6], H.readByte(B_SWITCH_LIVE)))
  end),
  stealDriver("the cider runner"),
  rideOut("ride the steal's aftermath out", 20000, 78),
  H.call(function()
    where("after the steal")
    H.log(string.format("post-fight $1DD2=%02X (b_switch $4C=%d $4D=%d)",
      H.readByte(0x1dd2), (H.readByte(0x1dd2) >> 4) & 1,
      (H.readByte(0x1dd2) >> 5) & 1))
    H.assertEq((H.readByte(0x1dd2) >> 4) & 1, 1,
      "b_switch $4C -- the steal's reaction script fired")
    H.assertEq(sw(0x01D0), 1, "$01D0 -- took the old man's cider")
    H.assertEq(sw(0x0104), 1, "$0104 -- wearing the merchant's clothes")
    H.assertEq(sw(0x0103), 0, "$0103 clear -- not the soldier's uniform")
  end),

  -- back out of the annex and into town
  go(75, 42, 78, 34, 45, "C3 map 78 (75,42) -> (34,45) [annex warp back]"),
  go(26, 53, 75, 22, 44, "C4 map 78 (26,53) -> town (22,44)"),
  H.call(function()
    H.assertEq(map(), 75, "back in South Figaro")
    where("sfigaro_town")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11)))
      end
    end
    H.screenshot("sfigaro_town")
  end),
  H.saveState("sfigaro_town.mss"),
  H.logStep(function()
    return string.format("sfigaro_town minted at frame %d", H.frame)
  end),

  -- ===================================================================== --
  -- BEAT 3: the cider buys the old man's story.  Map 86 npc 1 = obj 17 at
  -- {28,17}, reached ONLY through town (37,40) -> map 86 (36,22) -- the
  -- room has one outside door and one same-map warp, and the warp only
  -- leads to the little (9,8) landing and back.  _ca7b88 (:18670) takes the
  -- $01D0 branch _ca7bae: "there is one that leads to the rich man's
  -- house... give my grandson the password", ending `switch $0107=1`.
  -- The walk there is HOPPED (note 4): (22,44) -> (37,41) is a 49-step
  -- query and it is exactly the one that runs the BFS cap dry.
  -- ===================================================================== --
  hop(19, 44, "W1 west along the canal"),
  hop(19, 34, "W2 north to the main street"),
  hop(24, 34, "W3 east along the main street"),
  hop(30, 36, "W4 to the top of the SE lane"),

  clearGateSoldier(30, 43, "R1 (into the SE quarter)"),
  hop(30, 43, "W5 down the SE lane"),
  hop(34, 43, "W6 east"),
  hop(34, 46, "W7 south"),
  hop(36, 46, "W8 to the old man's doorstep"),
  go(37, 40, 86, 36, 22, "E1 town (37,40) -> map 86 (36,22)"),
  talkThrough(17, "the old man (cider -> $0107)"),
  H.call(function()
    where("after the old man")
    H.assertEq(sw(0x0107), 1, "$0107 -- he named the secret passage")
  end),

  -- ===================================================================== --
  -- BEAT 4: the grandson and the password.  Map 86 npc 4 = obj 20 at
  -- {6,10}, in the OTHER map-86 house -- the one town (34,35) enters at
  -- (4,6) -- so this is out to town and back in, not a warp.  _ca7bcd
  -- (:18738) tests $0107 BEFORE the "you may proceed" branch, so with the
  -- old man already told, one conversation goes straight to the prompt.
  -- ===================================================================== --
  go(36, 23, 75, 37, 42, "E2 map 86 (36,23) -> town (37,42)"),
  hop(34, 43, "W9 back west across the SE quarter"),
  -- and back OUT of the SE quarter, so the same plug is in the way again
  clearGateSoldier(34, 35, "R2 (out of the SE quarter)"),
  go(34, 35, 86, 4, 6, "E3 town (34,35) -> map 86 (4,6)"),
  talkThrough(20, "the grandson (the password)", {
    { want = 1, max = 3, what = 'dlg $00E0 "The password is..." -- 1 = ' ..
      '"Courage".  Options 0 ("Rose bud") and 2 ("Failure") BOTH jump to ' ..
      '_ca7c28, "You are an Imperial spy!", which fades out and calls ' ..
      '_ca85ba -- the scenario reset that dumps LOCKE back on (47,43) with ' ..
      'both disguise switches cleared (event_main.asm:18754-18762)' },
  }),
  H.call(function()
    where("after the password")
    H.assertEq(sw(0x01F1), 1, "$01F1 -- the secret entrance is open")
    -- _ca7c11 -> _caed21 rewrites BG1 at (4,15) (event_main.asm:100170):
    -- the staircase tile that read $E0/p1=$F7 (solid wall) is now floor
    H.log(string.format("(4,15) map byte=$%02X p1=$%02X",
      H.maptile(4, 15), H.readByte(0x7E7600 + H.maptile(4, 15))))
  end),

  go(4, 15, 86, 7, 51, "E4 map 86 (4,15) -> (7,51) [the secret passage]"),
  H.call(function()
    H.assertEq(map(), 86, "still map 86 -- the passage is a same-map warp")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    where("sfigaro_passage")
    H.screenshot("sfigaro_passage")
  end),
  H.saveState("sfigaro_passage.mss"),
  H.logStep(function()
    return string.format("sfigaro_passage minted at frame %d", H.frame)
  end),
})
