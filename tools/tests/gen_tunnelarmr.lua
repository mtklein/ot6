-- gen_tunnelarmr.lua -- from celes_freed.mss (LOCKE + CELES in the South
-- Figaro basement) out through the clock's secret passage, across the world
-- to the Figaro cave, to the doorstep of the TunnelArmr fight that ends the
-- Locke scenario.
-- Mints:
--   sfigaro_escape.mss    on the world map, out of occupied South Figaro
--   tunnelarmr_doorstep.mss  map 70, one tile short of the (47,38) trigger
--
-- THE CLOCK IS THE ESCAPE, and this is the correction to gen_celes's note 6.
-- All three of the basement's forward exits are dead-end pockets -- map 84's
-- (8,57) landing does not reach its (57,54) door, map 88 is a save closet,
-- map 89's (106,54) landing reaches only the way back -- and the way UP is
-- blocked by _ca8632's "This passage leads out" shove at (29,9).  The ONLY
-- way on is the clock: winding it (map 84 (18,49)) opens BG at (13,50)
-- (_caecf8, map 84's init _caecf2) and THAT is what makes (15,51) -> map 87
-- reachable.  Measured: (15,51) is walled off before the wind and 17 steps
-- away after it.  So the escape is 84 (clock) -> 87 -> 86 -> town -> world.
--
-- THE CLOCK'S WIND GATE is the $01Bx control-flag alias (gen_celes's note),
-- and the interaction that satisfies it: stand ON the trigger tile (18,49)
-- FACING UP with A held.  CheckEventTriggers re-fires _ca7913 every frame
-- the party is aligned there (field/event.asm:5740), UpdateCtrlFlags (:5416)
-- sets $1EB6 bit0 (facing up) and bit4 (A) the frame before, and the "Wind
-- the clock?" prompt then appears (option 0 = Yes).  (18,48) above is a wall
-- so holding UP pins the facing without moving; A is EDGED so the prompt is
-- not confirmed on the same hold.  Standing BELOW it, or holding UP+A as one
-- continuous press, both fail (measured).
--
-- THE CAVE, with $001A=1 (set on the raft for every scenario), loads map 70
-- -- the TunnelArmr copy -- from its lobby trigger _ca5ef7, where gen_kolts
-- with $001A=0 got map 73.  The cave graph is gen_kolts's, walked the other
-- way: world (75,103) -> map 72 -> ... -> map 71 -> [trigger] -> map 70.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/celes_freed.mss.lua"

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
local function stealDriver(what, maxF)
  local prog = { { 6, { "down" } }, { 10, {} }, { 6, { "a" } }, { 14, {} },
                 { 6, { "a" } }, { 14, {} } }
  local pi, pc, running, tries, idle = 1, 0, false, 0, 0
  return H.driveUntil(function() return not H.battleLoadStarted() end,
    maxF or 20000, {
      H.call(function()
        pinParty()
        if running then
          local s = prog[pi]
          H.setPad(s[2])
          pc = pc + 1
          if pc >= s[1] then pi, pc = pi + 1, 0 end
          if pi > #prog then running = false end
          return
        end
        if H.readByte(MENU) ~= 0 then
          if H.readByte(MSTATE) == ST_CMD then
            tries = tries + 1
            H.log(string.format("%s: STEAL attempt %d at f%d actor=%d $3EBD=%02X",
              what, tries, H.frame, H.readByte(ACTOR),
              H.readByte(B_SWITCH_LIVE)))
            running, pi, pc = true, 1, 0
          end
          H.setPad({})           -- a menu is up but not the command list:
          return                 -- never mash A into it
        end
        idle = (idle + 1) % 8    -- no menu: edge-tap through battle messages
        H.setPad(idle < 4 and { "a" } or {})
      end),
    }, what .. ": steal the clothes")
end


-- Wind the South Figaro clock: stand ON (18,49) facing UP, edge-tap A until
-- the "Wind the clock?" prompt confirms ($010D=1).  See the header.
-- STEP-BY-STEP BFS WALK to (tx,ty), re-planning EVERY frame and taking only
-- the first step, tapping A through dialogs.  Map 70 needs this over navTo:
-- its verify/re-plan machinery bounces the party off the (47,40)->map 71
-- mouth and the (50,31) "what IS that noise?" trigger into a teleport to
-- (8,3), while a plain "one BFS step at a time" walk threads the same route
-- to (47,38) cleanly (measured: navTo -> (8,3), safeWalk -> (47,38)).
local function safeWalk(tx, ty, what, budget)
  local ph = 0
  local DP = { up = "up", down = "down", left = "left", right = "right",
    upleft = "left", upright = "right", downleft = "left", downright = "right" }
  return seq({
    H.driveUntil(function()
      return H.fieldX() == tx and H.fieldY() == ty and H.hasControl()
    end, budget or 8000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        local p = H.bfsPath(tx, ty)
        if p and #p > 0 then H.setPad({ [DP[p[1]]] = true })
        else H.setPad({}) end
      end),
    }, what),
    H.release(),
  })
end

-- Cross a SAME-MAP warp: walk onto (sx,sy), arrival is the destination tile
-- (dx,dy) -- `map changed` is no signal inside a map built of warps.
local function warpTo(sx, sy, dx, dy, dmap, what)
  return seq({
    H.logStep(function()
      return string.format("%s: from (%d,%d)", what, H.fieldX(), H.fieldY())
    end),
    H.navTo(sx, sy, { maxFrames = 20000, arrive = function()
      return H.fieldX() == dx and H.fieldY() == dy
    end }),
    H.release(),
    settleField(dmap),
    H.call(function()
      H.assertEq(H.fieldX(), dx, what .. ": landed at x=" .. dx)
      H.assertEq(H.fieldY(), dy, what .. ": landed at y=" .. dy)
    end),
  })
end

local function windClock()
  local ph = 0
  return seq({
    hop(18, 49, "onto the clock trigger (18,49)"),
    H.driveUntil(function() return sw(0x010D) == 1 end, 900, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        if facing() ~= FACE.up then H.setPad({ up = true }); return end
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, "wind the clock ($010D)"),
    H.release(),
    settleField(84),
    H.call(function()
      H.assertEq(sw(0x010D), 1, "$010D -- the clock is wound")
      H.assertEq(H.bfsPath(15, 51) ~= nil, true,
        "the clock passage opened the way to (15,51) -> map 87")
      where("clock wound")
    end),
  })
end

-- gen_kolts's world settle: control + alignment + a lit screen on the
-- overworld engine, held for a while.
local function settleWorld(n)
  local cnt = 0
  return function()
    local ok = H.worldMode() and H.worldHasControl() and H.worldAligned()
      and (emu.getState()["ppu.screenBrightness"] or 0) >= 15
    cnt = ok and cnt + 1 or 0
    return cnt >= (n or 20)
  end
end

H.run({ maxFrames = 200000 }, {
  H.loadState(DOOR),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 83, "booted in the basement (map 83)")
    H.assertEq(sw(0x001D), 1, "$001D -- Celes is freed")
    H.assertEq(sw(0x01D1), 1, "$01D1 -- the clock key is in hand")
    H.assertEq(sw(0x001A), 1, "$001A -- the cave will load map 70")
    where("boot (celes_freed)")
  end),

  -- ===================================================================== --
  -- PHASE 1: THE CLOCK.  Down to map 84, wind it, and take the passage it
  -- opens: (15,51) -> map 87 -> (57,48) -> map 86.
  -- ===================================================================== --
  go(57, 13, 83, 35, 14, "celes room -> corridor"),
  go(45, 12, 84, 8, 57, "corridor (45,12) -> map 84 (8,57)"),
  windClock(),
  go(15, 51, 87, 20, 33, "clock passage (15,51) -> map 87 (20,33)"),
  go(57, 48, 86, 49, 31, "map 87 (57,48) -> map 86 (49,31)"),

  -- ===================================================================== --
  -- PHASE 2: OUT OF SOUTH FIGARO.  The "why are you helping me" scene at
  -- (52,29), then (52,27) -> town, then the world.
  -- ===================================================================== --
  -- (52,29)'s "why are you helping me" scene (_ca8973) is flavor -- pure
  -- conversation, sets only $001B.  The crossing to the town door (52,27)
  -- passes right by it; go's driveUntil taps A through whatever it says.
  -- Not required, so not asserted.
  go(52, 27, 75, 48, 36, "map 86 (52,27) -> town (map 75) (48,36)"),
  H.call(function() where("back in occupied town") end),
  -- exit via the x=56 column -> world (87,112)
  H.navTo(56, 34, { maxFrames = 12000, arrive = function() return H.worldMode() end }),
  H.release(),
  (function()
    local cnt = 0
    return H.advanceStory(function()
      local ok = H.worldMode() and H.worldHasControl() and H.worldAligned()
        and bright() >= 15
      cnt = ok and cnt + 1 or 0; return cnt >= 20
    end, 12000)
  end)(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "out on the world map, south of the range")
    where("sfigaro_escape (world)")
    H.assertEq(H.worldBfs(75, 102) ~= nil, true,
      "the south cave mouth (75,102) is reachable")
    H.screenshot("sfigaro_escape")
  end),
  H.saveState("sfigaro_escape.mss"),
  H.logStep(function()
    return string.format("sfigaro_escape minted at frame %d", H.frame)
  end),

  -- ===================================================================== --
  -- PHASE 3: THE FIGARO CAVE, walked into from the SOUTH.  world (75,102)
  -- is a world EVENT TRIGGER, not an entrance record (event_trigger.asm:38):
  -- _ca5ee3 with $001A=1 loads map 69 (the TunnelArmr side), where $001A=0
  -- would load map 72.  From map 69, (10,2)/(4,4) -> map 70, and (47,38) on
  -- map 70 is the TunnelArmr trigger _ca89af.
  -- ===================================================================== --
  H.worldNavTo(75, 102, { maxFrames = 30000,
    arrive = function() return not H.worldMode() end }),
  H.release(),
  settleField(69),
  H.call(function()
    H.assertEq(map(), 69, "world (75,102) -> map 69, the cave (map 70 side)")
    where("cave map 69 (16,42)")
  end),

  -- Map 69 is a warp maze (gen_kolts's map 72, mirrored): the landing does
  -- not reach the map-70 mouths.  Two same-map warps then a crossing, each
  -- verified by re-flooding the far side:
  --   (16,42) --walk--> (14,33) --warp--> (55,56)  [reaches (61,57)]
  --   (55,56) --walk--> (61,57) --warp--> (17,21)  [276 tiles, reaches (10,2)]
  --   (17,21) --walk--> (10,2)  --> map 70 (55,31)
  warpTo(14, 33, 55, 56, 69, "cave warp A (14,33) -> (55,56)"),
  warpTo(61, 57, 17, 21, 69, "cave warp B (61,57) -> (17,21)"),
  go(10, 2, 70, 55, 31, "cave (10,2) -> map 70 (55,31)"),
  H.call(function()
    H.assertEq(map(), 70, "on map 70 -- the TunnelArmr cave")
    H.assertEq(H.bfsPath(47, 38) ~= nil, true,
      "the TunnelArmr trigger (47,38) is reachable")
    where("map 70")
  end),

  -- ===================================================================== --
  -- PHASE 4: THE DOORSTEP.  (47,38) fires _ca89af (event_main.asm:20990) ->
  -- battle 67.  Mint one tile SOUTH of it: (47,39), the reachable approach.
  -- (47,40) is past one of map 70's same-map warps -- navTo to it lands the
  -- party at (8,3) instead -- so the doorstep is (47,39), which the flood
  -- from the (55,31) landing reaches on foot.
  -- ===================================================================== --
  -- walk to (47,37), one tile NORTH of the (47,38) trigger.  The approach
  -- from the (55,31) landing threads the (50,31) noise dialog; safeWalk taps
  -- through it.  (47,37) is the last tile before the trigger on that path.
  safeWalk(47, 37, "approach the TunnelArmr trigger", 10000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 70, "still on map 70")
    H.assertEq(H.fieldX() == 47 and H.fieldY() == 37, true,
      "at the (47,37) doorstep, one tile above the trigger")
    H.assertEq(H.hasControl(), true, "controllable at the doorstep")
    H.assertEq(sw(0x001E), 0, "$001E clear -- TunnelArmr not fought yet")
    where("tunnelarmr_doorstep")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11)))
      end
    end
    H.screenshot("tunnelarmr_doorstep")
  end),
  H.saveState("tunnelarmr_doorstep.mss"),
  H.logStep(function()
    return string.format("tunnelarmr_doorstep minted at frame %d", H.frame)
  end),

  -- ===================================================================== --
  -- PHASE 5: TUNNELARMR.  Step DOWN onto (47,38) -> _ca89af -> battle 67
  -- (formation 436, TunnelArmr $0104: hp 1300, 5/5 shields OT6_PIERCE, plus
  -- the OT6 ice element-add on vanilla's bolt|water).  Win it with the
  -- kill-bit idiom -- measured to end this fight cleanly, exactly as it ends
  -- Vargas -- then ride _ca89af's tail ("Whew!" / switch $001E=1 / fade /
  -- call _caad4c) back to the hub (map 9).  $001E=1 IS the Locke scenario
  -- complete.  The shields do not chip under kill-bit (it sets the death bit
  -- and never routes damage through Ot6ShieldedDmg); the fixture only needs
  -- the win, and the scripted finish is identical either way.
  -- ===================================================================== --
  H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      if H.fieldX() == 47 and H.fieldY() == 37 then H.setPad({ down = true }); return end
      H.setPad({})
    end),
  }, "step onto (47,38) -> battle 67"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 6000, "TunnelArmr up", 10),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(H.formationHas({ [0x0104] = true }), true,
      "battle 67 is TunnelArmr $0104")
    local sh = -1
    for i = 0, 5 do
      if H.readByte(0x3aa8 + i * 2) % 2 == 1 and H.readWord(0x57c0 + i * 2) == 0x0104 then
        sh = H.readByte(0x3e40 + i * 2)
      end
    end
    H.log(string.format("TunnelArmr up: hp=%d shields=%d/%d (table authors 5, OT6_PIERCE)",
      H.readWord(0x3bfc), sh, H.readByte(0x3e41)))
    H.assertEq(sh, 5, "5 shields seeded, per Ot6ShieldTbl $0104")
  end),
  H.driveUntil(function() return not H.battleLoadStarted() end, 20000, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.monstersPresent() > 0 then
        for slot = 0, 5 do
          if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
            H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
          end
        end
      end
      H.setPad(aPhase < 4 and { "a" } or {})
    end),
  }, "TunnelArmr down (kill-bit)"),
  H.logStep(function() return string.format("TunnelArmr down at f%d", H.frame) end),

  -- ride the tail to the hub; $001E flips on map 70, then _caad4c warps home
  (function()
    local calm = 0
    return H.driveUntil(function()
      local ok = sw(0x001E) == 1 and map() == 9 and H.hasControl()
             and H.tileAligned() and bright() >= 15 and not H.battleLoadStarted()
      calm = ok and calm + 1 or 0
      return calm >= 20
    end, 30000, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if H.battleLoadStarted() and H.monstersPresent() > 0 then
          for slot = 0, 5 do
            if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
        if not H.hasControl() then H.setPad(aPhase < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, "ride back to the scenario hub")
  end)(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x001E), 1, "$001E=1 -- LOCKE's scenario is COMPLETE")
    H.assertEq(map(), 9, "back at the three-way scenario hub (map 9)")
    H.assertEq(H.hasControl(), true, "controllable at the hub")
    where("locke_done")
    H.screenshot("locke_done")
  end),
  H.saveState("locke_done.mss"),
  H.logStep(function()
    return string.format("locke_done minted at frame %d -- scenario complete", H.frame)
  end),
})
