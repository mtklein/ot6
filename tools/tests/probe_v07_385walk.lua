-- probe_v07_385walk.lua -- THE PHASE-AWARE CROSSING of BASEMENT 2 (map
-- 385), the v0.7 band's first genuinely new driving idiom (issue #31,
-- recon §5 hazard 2).  NOT a suite test.
--
-- WHY navTo CANNOT DRIVE THIS ROOM, measured (probe_v07_385, 2026-07-28):
-- the floor is TWO INTERLEAVED TILEMAPS that swap every 158 frames once a
-- cycle is armed (event_main.asm:44634-44758; `wait 144` + `start_timer
-- ...,144,...` -- the extra ~14 frames are the timer callback's own
-- mod_bg_tiles/wait_bg), and each swap REWRITES the live BG1 tilemap.  So:
--   * from the entry (1,2), the reachable set in the unarmed state is 17
--     tiles and does NOT contain the (13,13) exit, the (10,2) cycle-A
--     trigger, or either cycle-B trigger -- a single BFS can never find a
--     path, in EITHER phase (measured: 17 tiles in $01F5, 12 in $01F6);
--   * the crossing only exists ACROSS TIME: walk as far as the current
--     phase allows, stand still while the floor swaps, walk on.  Measured
--     row 2 as the tilemap flips:
--         $01F5:  x=3..6 walkable (0A), x=7 WALL, x=8 walkable, x=9 WALL
--         $01F6:  x=3 walkable,  x=4..6 WALL,   x=7..9 walkable (02)
--     -- i.e. exactly complementary, and the party crosses by being at the
--     boundary tile when the swap happens.
--   * navTo's contract is "BFS a plan, execute it, condemn an edge that
--     never moved us".  Here every edge is legitimately dead half the time,
--     so navTo would blocklist the whole room and then error "no path".
--
-- THE IDIOM (`phaseWalk` below): each aligned frame, take the legal step
-- that most reduces distance to the waypoint, but ONLY if the destination
-- is safe in the CURRENT phase; otherwise hold still and let the floor
-- swap.  Safety is the STATIC hurt-trigger lists from
-- event_trigger.asm:1844-1885 (_cb2dbb hurts while $01F5, _cb2dd2 while
-- $01F6, (15,10) always) -- a belt-and-braces layer over the live model,
-- because the tilemap and the triggers do not have to agree and a mistake
-- costs the whole party HP/8 plus a teleport back to (2,6) and a full
-- $01F0-$01FF wipe (_cb2dae/_cb2e1b, :44858/:44905).
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

-- event_trigger.asm:1848-1884, transcribed
local HURT_F5 = { {7,2},{9,2},{9,4},{5,5},{6,5},{9,5},{13,5},{13,6},{5,7},
                  {11,7},{13,7},{14,7},{5,8},{12,9},{6,10},{14,10},{10,11} }
local HURT_F6 = { {4,2},{5,2},{6,2},{5,3},{7,3},{8,3},{9,3},{11,4},{11,5},
                  {3,7},{10,8},{11,8},{12,8},{13,8},{14,8},{7,9},{10,9},{9,11} }
local HURT_ALWAYS = { {15,10} }
local function keyOf(x, y) return y * 64 + x end
local hurt5, hurt6, hurtA = {}, {}, {}
for _, t in ipairs(HURT_F5) do hurt5[keyOf(t[1], t[2])] = true end
for _, t in ipairs(HURT_F6) do hurt6[keyOf(t[1], t[2])] = true end
for _, t in ipairs(HURT_ALWAYS) do hurtA[keyOf(t[1], t[2])] = true end

local function unsafe(x, y)
  local k = keyOf(x, y)
  if hurtA[k] then return true end
  if sw(0x01F5) == 1 and hurt5[k] then return true end
  if sw(0x01F6) == 1 and hurt6[k] then return true end
  return false
end

local DIRS = { "up", "right", "down", "left" }
local DELTA = { up = { 0, -1 }, right = { 1, 0 },
                down = { 0, 1 }, left = { -1, 0 } }

-- Walk toward (tx,ty) across the phase swaps.  Preference order per aligned
-- frame: (1) a full BFS plan's first step, when one exists and is safe --
-- BFS handles the corridors correctly; (2) otherwise the greedy legal step
-- that most reduces Manhattan distance and is safe; (3) otherwise WAIT.
-- `noRegress` forbids a step that increases the distance, so the walker can
-- never oscillate across a swapping boundary.
local function phaseWalk(tx, ty, maxFrames, what)
  local hb, waited, steps = -240, 0, 0
  local pend = nil
  return H.driveUntil(function()
    return H.fieldX() == tx and H.fieldY() == ty and H.tileAligned()
       and H.hasControl()
  end, maxFrames, {
    H.call(function()
      if H.dialogWaiting() then H.setPad({}); return end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
      local x, y = H.fieldX(), H.fieldY()
      if H.frame - hb >= 240 then
        hb = H.frame
        H.log(string.format("[385walk] f%d (%d,%d) -> (%d,%d) $01F5=%d "
          .. "$01F6=%d steps=%d waited=%d", H.frame, x, y, tx, ty,
          sw(0x01F5), sw(0x01F6), steps, waited))
      end
      if pend then
        if x ~= pend[1] or y ~= pend[2] then steps = steps + 1 end
        pend = nil
      end
      local function dist(ax, ay) return math.abs(tx - ax) + math.abs(ty - ay) end
      local d0 = dist(x, y)
      -- (1) a real BFS plan, if the room currently admits one.  NO-REGRESS
      -- applies to the BFS step too: measured run 1, from (6,2) in the
      -- phase where (7,2) is closed, BFS found a long way round and walked
      -- the party back WEST to (3,2), where the next phase walked it east
      -- again -- a 6000-frame oscillation.  The room's waypoints are
      -- straight lines; a step that increases the distance is always the
      -- walker giving up on the swap it should be waiting for.
      local plan = H.bfsPath(tx, ty)
      if plan and #plan > 0 then
        local d = DELTA[plan[1]]
        if d then
          local nx, ny = x + d[1], y + d[2]
          if not unsafe(nx, ny) and dist(nx, ny) <= d0 then
            pend = { x, y }
            H.setPad({ [H.movePress(plan[1])] = true })
            return
          end
        end
      end
      -- (2) greedy: the safe legal step that most reduces distance
      local best, bestd = nil, d0
      for _, dir in ipairs(DIRS) do
        if H.canStep(x, y, dir) then
          local d = DELTA[dir]
          local nx, ny = x + d[1], y + d[2]
          if not unsafe(nx, ny) and dist(nx, ny) < bestd then
            best, bestd = dir, dist(nx, ny)
          end
        end
      end
      if best then
        pend = { x, y }
        H.setPad({ [best] = true })
        return
      end
      -- (3) wait for the floor to swap
      waited = waited + 1
      if waited % 120 == 0 then
        local diag = {}
        for _, dir in ipairs(DIRS) do
          local d = DELTA[dir]
          local nx, ny = x + d[1], y + d[2]
          diag[#diag + 1] = string.format("%s:%s%s p1dst=%02X",
            dir, H.canStep(x, y, dir) and "step" or "----",
            unsafe(nx, ny) and "/HURT" or "",
            H.readByte(0x7E7600 + H.maptile(nx, ny)))
        end
        H.log(string.format("[385walk WAIT] (%d,%d) p1cur=%02X p2cur=%02X "
          .. "z=%d $01F5=%d $01F6=%d | %s", x, y,
          H.readByte(0x7E7600 + H.maptile(x, y)),
          H.readByte(0x7E7700 + H.maptile(x, y)),
          H.readByte(0x00b2) & 3, sw(0x01F5), sw(0x01F6),
          table.concat(diag, "  ")))
      end
      H.setPad({})
    end),
  }, what or string.format("phaseWalk (%d,%d)", tx, ty))
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/v07q_385_entry.mss.lua"),
  H.waitFrames(180),
  H.call(function()
    H.assertEq(map(), 385, "booted on BASEMENT 2 (map 385)")
    H.assertEq(H.fieldX(), 1, "boot x")
    H.assertEq(H.fieldY(), 2, "boot y")
  end),

  -- arm cycle A: the (3,2) trigger (_cb2aca, event_main.asm:44634)
  phaseWalk(3, 2, 6000, "to the cycle-A arming trigger (3,2)"),
  H.waitUntil(function() return sw(0x01F0) == 1 end, 1800,
    "cycle A armed ($01F0)", 5),
  H.call(function()
    H.log(string.format("[385] cycle A armed at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("v07_385_armedA")
  end),

  -- east along row 2, riding the swaps
  phaseWalk(6, 2, 6000, "east to (6,2) -- the $01F5 half of row 2"),
  phaseWalk(9, 2, 6000, "across the swap to (9,2) -- the $01F6 half"),
  phaseWalk(11, 2, 6000, "to (11,2), the solid east column"),
  -- arm cycle B: the (11,3) trigger (_cb2c6e, :44746)
  phaseWalk(11, 3, 6000, "to the cycle-B arming trigger (11,3)"),
  H.waitUntil(function() return sw(0x01F1) == 1 end, 1800,
    "cycle B armed ($01F1)", 5),
  H.call(function()
    H.log(string.format("[385] cycle B armed at (%d,%d) $01F1=%d",
      H.fieldX(), H.fieldY(), sw(0x01F1)))
    H.screenshot("v07_385_armedB")
    -- the east half's live picture, both halves now cycling
    for y = 0, 15 do
      local r = {}
      for x = 0, 16 do
        r[#r + 1] = string.format("%02X", H.readByte(0x7E7600 + H.maptile(x, y)))
      end
      H.log(string.format("[385B p1 y=%02d] %s", y, table.concat(r, " ")))
    end
  end),

  -- down the east half to the 384 door at (13,13)
  phaseWalk(11, 6, 9000, "down the x=11 column to (11,6)"),
  phaseWalk(13, 11, 12000, "to the cycle-B trigger / east floor (13,11)"),
  phaseWalk(13, 12, 6000, "to (13,12)"),
  H.call(function()
    H.log(string.format("[385] at (%d,%d) -- one step above the 384 door",
      H.fieldX(), H.fieldY()))
    H.screenshot("v07_385_door")
  end),
  (function() local ph = 0
    return H.driveUntil(function() return map() == 384 end, 2400, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({ down = true })
      end),
    }, "held DOWN onto (13,13) -> BASEMENT 3 (map 384)")
  end)(),
  H.waitUntil(function()
    return map() == 384 and H.hasControl() and H.tileAligned()
      and (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 2400, "384 control", 5),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(map(), 384, "BASEMENT 3 is map 384")
    H.assertEq(H.fieldX(), 26, "384 landing x (short entrance 385 (13,13))")
    H.assertEq(H.fieldY(), 8, "384 landing y")
    H.screenshot("v07_384_entry")
  end),
  H.saveState("v07q_384_entry.mss"),
  H.logStep("385 crossed; parked at the 384 entry"),
})
