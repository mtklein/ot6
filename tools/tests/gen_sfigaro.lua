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
--
-- ISSUE #75 (the honesty conversion): ZERO state writes.  The two fights
-- on this route are PLAYED now:
--   * battle 11 (the gate soldier's HeavyArmor, up to three times -- he
--     respawns on every map-75 reload) is won by solo LOCKE on boosted
--     Fights: R raises pending boost out of the 1 bp Ot6InitBP grants,
--     A-A-A confirms the boosted Fight -- gen_moogle's Marshal drive.
--     The old HP pin is gone, so a loss is REAL (the _ca85ba scenario
--     reset: dumped on (47,43), disguises cleared) and is handled the
--     way a TAS handles it -- every engagement rides a phase-spread
--     retry ladder (a blob captured before the talk, reloaded with a
--     different frame offset; the battle RNG seed is the frame phase at
--     init, gen_whelk_poweron's measurement).
--   * the cider runner's Merchant is STOLEN from by real menu input
--     through the #55 thief submenu, with the boost banked honestly:
--     LOCKE opens with 1 bp and regens +1 per unboosted action
--     (Ot6ActionEnd), and a steal ATTEMPT is itself an action -- so the
--     driver steals unboosted while the bank grows (each attempt rolls
--     vanilla odds and may simply land), and from 3 bp on it presses
--     R-R-R first, which Ot6StealBoostLevel converts to a GUARANTEED
--     steal (kits.md's tier table).  Steal costs 4 MP (Ot6StealCost),
--     paid from LOCKE's own pool -- the driver logs bank/MP per attempt
--     so an empty wallet is visible in the mint log, not pinned over.
-- The stealDriver that poked STEAL into every command cell and forced
-- banked+pending boost to the cap, and the pinParty HP writes, are gone.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/locke_scenario.mss.lua"

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
    end), maxF or 12000, { honest = true }),
    H.waitFrames(30),
  })
end

local aPhase = 0

-- Ride a scene out to a settled, controllable field, edge-tapping A on EVERY
-- frame the party is not in control and FIGHTING anything that comes up --
-- honestly (issue #75; the HP pin + kill-bit this branch used to carry are
-- gone).  Battle frames drive gen_moogle's Marshal cycle: R raises the
-- active character's pending boost (1 bp at battle start, Ot6InitBP; the R
-- buzzes harmlessly on an empty bank), then three edge-tapped A's confirm
-- the boosted Fight and page victory text -- so solo LOCKE alternates
-- boosted and plain Fights against battle 11's HeavyArmor.  A LOSS is real
-- now (the _ca85ba scenario reset); the callers below wrap every
-- engagement in a phase-spread retry ladder rather than pinning it away.
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
-- ...AND WHY THE FIGHT ITSELF IS NOT A BUTTON PATTERN ANY MORE.  The first
-- honest version of this drove every battle with a fixed 32-frame cycle --
-- R to boost, then three edge-tapped A's -- which is a fine way to page
-- victory text and a poor way to survive.  Measured 2026-08-09 on the first
-- full-frontier run that ever reached this edge: solo LOCKE, level 8 with
-- 168 hp, LOST the gate soldier's HeavyArmor three attempts running, while
-- sixteen Tonics sat in the bag.  He never pressed a single one, because
-- the pattern has no idea what a menu is.  H.newFightDriver does: it reads
-- the live command table, boosts, and runs its own item medic line -- so
-- LOCKE now drinks a Tonic when he is under 60%, which is what a player
-- fighting a soldier alone in an occupied town would obviously do.
-- (The FIELD half of this routine is unchanged and still hand-rolled; see
-- the note above on why advanceStory cannot own the tail of battle 11.)
local function rideOut(what, budget, dstMap)
  local phase, calm = 0, 0
  local F = H.newFightDriver(what or "rideOut",
    -- bank = 3: unboosted Fights until LOCKE has three BP, then unload.
    -- Shielded damage is HALVED and a broken monster takes 4x
    -- (Ot6ShieldedMulW, ot6_break.asm:1487-1497), so the fight is won by
    -- breaking, not by chipping -- and a boosted Fight is what chips.
    { tactical = true, boost = true, bank = 3, items = true,
      healPercent = 60, cadence = 12 })
  return seq({
    H.driveUntil(function()
      local ok = H.hasControl() and H.tileAligned() and bright() >= 15
             and not H.battleLoadStarted() and not H.dialogWaiting()
             and (dstMap == nil or map() == dstMap)
      calm = ok and calm + 1 or 0
      return calm >= 20
    end, budget or 30000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.battleLoadStarted() then
          F.frame()
          return
        end
        F.idle()
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
    H.navTo(tx, ty, { maxFrames = 12000, honest = true }),
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
      { maxFrames = 20000, arrive = arrived, honest = true }),
    H.cond(function() return stage()[3] ~= nil end, {
      H.driveUntil(arrived, 1800, {
        H.call(function()
          aPhase = (aPhase + 1) % 8
          if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
          -- stage() RE-PICKS every call, so the H.cond above (which admitted
          -- us because the pick had a hold direction) does not guarantee the
          -- pick still has one now: a nav outcome can switch this to the
          -- walk-straight-onto-the-entrance variant mid-drive, and
          -- `{ [nil] = true }` is a "table index is nil" abort.  Observed
          -- 2026-07-29 -- the pick flipped at f2072 after the nav library
          -- gained its avoid-set, which changed which staging tile it
          -- reached first.  A directionless pick means walk straight, so
          -- hold nothing.
          local hold = stage()[3]
          H.setPad(hold and { [hold] = true } or {})
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
      maxFrames = maxF or 20000, honest = true,
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
--
-- EVERY ENGAGEMENT IS A RETRY LADDER NOW (issue #75).  With the HP pin
-- gone a lost battle 11 runs _ca85ba -- LOCKE revived on (47,43), both
-- disguise switches cleared -- so each fight captures a blob first, and a
-- loss reloads it and re-engages with a different frame offset (the
-- battle RNG seed is the frame phase at init, so each retry plays a
-- genuinely different fight).  Success = not dumped on the opening tile
-- AND the probe tile reachable; three losses fail the mint loudly.
local function clearGateSoldier(probeX, probeY, tag)
  local blob, won = nil, false
  local function fightOnce(n)
    local loadReq
    return H.cond(function() return won end, {}, {
      H.logStep(function()
        return string.format("%s: battle 11 attempt %d (offset %d) at f%d",
          tag, n, (n - 1) * 37, H.frame)
      end),
      n > 1 and seq({
        H.call(function() loadReq = H.requestLoadState(blob) end),
        H.waitFrames(2),
        H.call(function() H.checkReq(loadReq, tag .. ": pre-fight reload") end),
        H.waitFrames(90),
        H.waitFrames((n - 1) * 37),      -- vary the battle RNG seed
      }) or seq({}),
      talkToObj(26, tag .. ": the gate soldier (battle 11)"),
      rideOut(tag .. ": ride battle 11 out", 30000, 75),
      H.call(function()
        -- same reasoning as the branch above: $0104 is the gate scene's
        -- own record that the soldier is beaten.  A lost attempt runs the
        -- scenario reset (_ca85ba) and leaves it clear.
        won = sw(0x0104) == 1
        H.log(string.format("%s: attempt %d %s at (%d,%d) f%d, $0104=%d",
          tag, n, won and "WON" or "LOST (scenario reset)",
          H.fieldX(), H.fieldY(), H.frame, sw(0x0104)))
      end),
    })
  end
  -- CAN HE JUST WALK PAST HIM?  No, and that is measured, not assumed.
  -- South Figaro is a stealth chapter and the gate soldier looked like he
  -- wandered -- the old reachability probe answered "lane open" often
  -- enough to flip this branch by accident -- so the obvious move is to
  -- wait him out.  Measured 2026-08-09: polling H.bfsPath(22,43) every 60
  -- frames for 7200 frames (two minutes of game time) NEVER once found a
  -- path.  He does not step off the choke.  The fight is mandatory, which
  -- is what makes the balance finding below a real one and not a routing
  -- failure.
  --
  -- WHICH BRANCH, decided on the STORY SWITCH and not on a BFS probe.
  -- This used to ask "is (22,43) reachable this instant?", and the answer
  -- depends on where the gate soldier happens to be standing: he WANDERS,
  -- and when he steps off the choke the probe says "lane already open",
  -- the fight is skipped, and the next navTo walks into him and dies of
  -- "no path" twenty retries later.  Measured 2026-08-09 -- inserting a
  -- single menu visit ahead of this cond was enough to flip it.  $0104 is
  -- the switch the gate scene itself sets, it does not wander, and the
  -- loss path below already reads it.
  return H.cond(function() return sw(0x0104) == 0 end, {
    H.logStep(function()
      return string.format("%s: $0104 clear at f%d -- the gate soldier is " ..
        "still on duty at (%d,%d); fighting him",
        tag, H.frame, objX(26), objY(26))
    end),
    (function()
      local req
      return seq({
        H.call(function() req = H.requestSaveState() end),
        H.waitFrames(2),
        H.call(function()
          H.checkReq(req, tag .. ": retry blob")
          blob = req.blob
        end),
      })
    end)(),
    fightOnce(1), fightOnce(2), fightOnce(3),
    H.call(function()
      -- THIS IS THE WALL, and it is left standing on purpose (issue #75).
      -- Solo LOCKE, level 8, 168 hp, correctly equipped through the real
      -- Equip -> Optimum walk, healing himself with Tonics, deals ~21
      -- damage per 300 frames to a level-13 HeavyArmor with 495 hp and
      -- takes ~117 back.  He needs ~7200 frames of swings and survives
      -- ~2500.  Front row and back row measure identically.  Its
      -- weaknesses are bolt and water (monster_prop +25 = $84) and solo
      -- LOCKE can reach neither, so the break economy has no answer here
      -- either.  Bare-handed -- which is how the chain delivered him until
      -- H.equipOptimum landed -- it was eight damage a swing.
      -- This wants a balance call, not a cleverer drive.  Do not widen
      -- the attempt ladder until it gets lucky; that is the #74 mistake.
      H.assertEq(won, true,
        tag .. ": battle 11 won honestly within 3 attempts (boosted Fights)")
      H.assertEq(sw(0x0104), 1, tag .. ": the gate scene recorded the win")
    end),
  }, {
    H.logStep(function() return tag .. ": the lane is already open" end),
  })
end

-- ------------------------------------------------------------- the steal --
-- THE HONEST STEAL (issue #75).  Locke's command window is `FIGHT, STEAL,
-- MAGIC, ITEM` (char_prop.asm:157); MAGIC is removed at runtime for a
-- spell-less Locke (InitCmd_03), the rows stay four, and STEAL is one DOWN
-- from the resting cursor.  Since #55 the Steal row opens the THIEF
-- SUBMENU (tools shell, state $30) with Steal on row 0, so one attempt is
-- the edge sequence  down, A (submenu opens), A (row 0 = Steal), A (the
-- target cursor opens MANUAL|ONE_SIDE|ENEMY on the lone Merchant).
--
-- THE BOOST IS BANKED FOR REAL.  Steal is the shipped boost-tiered chance
-- verb (Ot6StealBoostLevel): 0 bp rolls raw vanilla odds, 3 bp clamps the
-- level term so vanilla's own `bcs` GUARANTEES the steal.  LOCKE opens
-- the fight with 1 bp (Ot6InitBP) and regens +1 per unboosted action
-- (Ot6ActionEnd) -- and a steal ATTEMPT is itself an action -- so the
-- driver simply steals unboosted while the bank grows (attempts 1-2 may
-- land on their own dice; each pays Ot6StealCost's 4 MP), and once the
-- bank reads >= 3 it presses R-R-R first and takes the guaranteed steal.
-- Worst case is three attempts, 12 MP, against the pool the fixture logs.
-- The merchant's reaction script (`if_cmd STEAL`, AIScript::_314) sets
-- b_switch $4C and ends the fight; the caller asserts $1DD2 bit 4.
--
-- The menu machine is armr-style: presses start only after the menu flag
-- holds 4 consecutive pulses, a NEW sequence is only built while the menu
-- is the COMMAND WINDOW (state $05 -- a stray A from any other state
-- could queue FIGHT and kill the merchant, the one outcome this fight
-- must never produce), and any other state without a running sequence is
-- backed out with B.
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD = 0x05
local B_SWITCH_LIVE = 0x3EBD          -- $3EB4 + ($4C >> 3); bit4 = $4C
local function stealDriver(what, maxF)
  local mStreak, mSeq, mIdx, mSub, mNoMenu, tries = 0, nil, 1, 0, 0, 0
  return H.driveUntil(function() return not H.battleLoadStarted() end,
    maxF or 30000, {
      H.call(function()
        if H.readByte(MENU) == 0 then
          mStreak, mSeq, mIdx, mSub = 0, nil, 1, 0
          mNoMenu = mNoMenu + 1
          H.setPad(mNoMenu % 2 == 0 and { "a" } or {})
          return
        end
        mNoMenu = 0
        mStreak = mStreak + 1
        if mStreak < 4 then H.setPad({}); return end
        if mSeq == nil then
          if H.readByte(MSTATE) ~= ST_CMD then
            H.setPad(mStreak % 8 < 4 and { "b" } or {})  -- unwind to the window
            return
          end
          local actor = H.readByte(ACTOR)
          local bank = H.readByte(0x3E9C + actor * 2)
          local mp = H.readWord(0x3C08 + actor * 2)
          tries = tries + 1
          if bank >= 3 then
            mSeq = { "r", "r", "r", "down", "a", "a", "a" }  -- guaranteed tier
          else
            mSeq = { "down", "a", "a", "a" }                 -- vanilla odds; bank grows
          end
          mIdx, mSub = 1, 0
          H.log(string.format(
            "%s: STEAL attempt %d f%d actor=%d bank=%d mp=%d %s $3EBD=%02X",
            what, tries, H.frame, actor, bank, mp,
            bank >= 3 and "(boost 3 -- guaranteed)" or "(unboosted)",
            H.readByte(B_SWITCH_LIVE)))
        end
        if mIdx <= #mSeq then
          -- one button per 16-frame window: 6 held, 10 released -- the
          -- edge cadence the old driver's measured prog used (a held
          -- d-pad does not move this cursor; a 6-frame edge does)
          H.setPad(mSub < 6 and { mSeq[mIdx] } or {})
          mSub = mSub + 1
          if mSub >= 16 then
            mSub = 0
            mIdx = mIdx + 1
            if mIdx > #mSeq then mSeq = nil end
          end
          return
        end
      end),
    }, what .. ": steal the clothes")
end

-- ========================================================================= --
-- Budget note (issue #75): honest fights cost real ATB rounds, and the
-- retry ladders can replay them -- the ceiling covers the worst case of
-- three three-attempt ladders plus the steal's.
H.run({ maxFrames = 350000 }, {
  H.loadState(DOOR),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 75, "booted on map 75, occupied South Figaro")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(sw(0x0105), 1, "$0105 -- LOCKE's scenario is live")
    H.assertEq(sw(0x001E), 0, "$001E clear -- the scenario is not done")
  end),
  -- LOCKE IS ALONE HERE, and alone is exactly when the back row is worth
  -- the trade.  He fights a level-13 HeavyArmor with 495 hp on 168 of his
  -- own; halving the physical damage he takes buys the turns his Tonics
  -- need to matter.  He gives up half his Fight for it -- Steal deals no
  -- damage, so Fight is all he has -- and this is the one stretch of the
  -- game where that is clearly the right side of the trade.
  -- LOCKE ARRIVES BARE-HANDED and nobody had ever noticed, because nobody
  -- had ever looked: measured 2026-08-09, $1600+37*1+$1F..$23 all read $FF
  -- at this fixture -- no weapon, no armor, no relics -- with his own Dirk
  -- sitting in the bag.  He then punched the gate soldier's level-13,
  -- 495-hp HeavyArmor for EIGHT damage a swing and lost three attempts
  -- running, which reads exactly like a balance finding and is nothing of
  -- the sort.  The story's own remove_equip returns gear to inventory
  -- (EventCmd_8d) and the mint chain never put it back on.  A player opens
  -- the Equip menu before walking into an occupied town; so does this.
  H.equipOptimum({ tag = "locke kit" }),
  H.call(function()
    where("boot")
  end),

  -- ===================================================================== --
  -- BEAT 1: the soldier who bars the gate.  Map 75 npc 10 = obj 26, spawn
  -- switch $030C, at {30,42}: _ca854f (event_main.asm:20296) opens
  -- `dlg $0174 "Halt!"` + `battle 11, TOWN_EXT` -> formation 64,
  -- HeavyArmor $09F.  He is a PLUG, not scenery: (30,42) is the only tile
  -- joining the starting pocket to the rest of town, and BFS reaches
  -- exactly 107 tiles until he is gone.  Won any way at all -- the clothes
  -- branches are a different fight -- but "any way" is HONEST now: solo
  -- LOCKE on boosted Fights, with the retry ladder around the engagement.
  -- The probe tile is the cafe doorstep the win must open.
  -- ===================================================================== --
  clearGateSoldier(22, 43, "B1 (open the town)"),
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
  -- THE STEAL, on its own retry ladder: an attempt that ends the fight
  -- without b_switch $4C (LOCKE down, or the fight somehow won another
  -- way) reloads the pre-talk blob and re-engages at a different frame
  -- phase.  The formation assert stays HARD on every attempt.
  (function()
    local blob, stolen = nil, false
    local function stealAttempt(n)
      local loadReq
      return H.cond(function() return stolen end, {}, {
        H.logStep(function()
          return string.format("cider steal attempt %d (offset %d) at f%d",
            n, (n - 1) * 37, H.frame)
        end),
        n > 1 and seq({
          H.call(function() loadReq = H.requestLoadState(blob) end),
          H.waitFrames(2),
          H.call(function() H.checkReq(loadReq, "cider: pre-talk reload") end),
          H.waitFrames(90),
          H.waitFrames((n - 1) * 37),    -- vary the battle RNG seed
        }) or seq({}),
        talkToObj(22, "the cider runner"),
        -- ride the two dialogs into the fight BY HAND: advanceStory's
        -- honest mode would blind-tap A in the fight, and A on the resting
        -- cursor is FIGHT -- the merchant must never be killed
        (function()
          local ph = 0
          return H.driveUntil(function() return H.battleLoadStarted() end, 9000, {
            H.call(function()
              ph = (ph + 1) % 8
              H.setPad(ph < 4 and { "a" } or {})
            end),
          }, "the cider scene reaches battle 10")
        end)(),
        H.release(),
        H.waitUntil(function() return H.battleActive() end, 6000,
          "battle 10 up", 10),
        H.waitFrames(90),
        H.call(function()
          H.assertEq(H.formationHas({ [0x013A] = true }), true,
            "battle 10 is formation 43 -- Merchant $13A")
          local w = H.formationWords()
          H.log(string.format(
            "battle 10: %04X %04X %04X %04X %04X %04X  $3EBD=%02X",
            w[1], w[2], w[3], w[4], w[5], w[6], H.readByte(B_SWITCH_LIVE)))
        end),
        stealDriver("the cider runner"),
        -- SOFT aftermath ride: on the steal the scene settles back on map
        -- 78; on a surprise loss the game-over screen never settles, and a
        -- hard timeout here would abort the whole mint instead of letting
        -- the ladder reload and retry -- so this ride gives up quietly
        -- after its budget and lets the $1DD2 check below decide.
        (function()
          local ph, calm, waited = 0, 0, 0
          return H.driveUntil(function()
            local ok = H.hasControl() and H.tileAligned() and bright() >= 15
                   and not H.battleLoadStarted() and not H.dialogWaiting()
                   and map() == 78
            calm = ok and calm + 1 or 0
            waited = waited + 1
            return calm >= 20 or waited >= 20000
          end, 20500, {
            H.call(function()
              ph = (ph + 1) % 8
              if H.hasControl() then H.setPad({}); return end
              H.setPad(ph < 4 and { "a" } or {})
            end),
          }, "ride the steal's aftermath out (soft)")
        end)(),
        H.release(),
        H.waitFrames(30),
        H.call(function()
          stolen = (H.readByte(0x1dd2) >> 4) & 1 == 1
            and map() == 78 and H.hasControl()
          H.log(string.format("cider attempt %d: $1DD2=%02X map=%d -> %s", n,
            H.readByte(0x1dd2), map(),
            stolen and "STOLEN" or "no steal; retrying"))
        end),
      })
    end
    return seq({
      (function()
        local req
        return seq({
          H.call(function() req = H.requestSaveState() end),
          H.waitFrames(2),
          H.call(function()
            H.checkReq(req, "cider: retry blob")
            blob = req.blob
          end),
        })
      end)(),
      stealAttempt(1), stealAttempt(2), stealAttempt(3),
      H.call(function()
        H.assertEq(stolen, true,
          "the clothes were STOLEN honestly within 3 attempts")
      end),
    })
  end)(),
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
