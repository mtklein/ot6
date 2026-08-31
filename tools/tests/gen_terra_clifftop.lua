-- gen_terra_clifftop.lua -- from terra_caves.mss, the length of the Narshe
-- caves: map 41 -> a walled-off pocket of map 20 -> maps 48, 49, 50 -> out
-- onto the clifftop above Narshe, behind the checkpoint that turned the
-- party away.
-- Generates one state:
--   terra_clifftop.mss  map 20 (27,8), the ledge the caves come out on,
--                       first controllable frame, one short walk from
--                       Arvis's back door and the end of the scenario.

-- Six crossings, none of which can be derived from the tables.
-- Every pocket on this route is small and sealed, and H.bfsPath cannot show
-- that: these maps are 128x64 ($86/$87 = $7F/$3F) and its 4096-node hang
-- guard trips long before it has covered one of them.  An uncapped flood over
-- the same passability rules (run as a reachability probe during
-- development) mapped them instead.  What that found:

--   map 41  (7,33)  82 tiles, two exits: (7,34) straight back to map 20
--                   (15,57), and (21,9) -> map 20 (23,44).
--   map 20  (23,44) 86 tiles, and not the town: a sealed pocket whose only
--                   other door is (10,36) -> map 48 (87,31).
--   map 48  (87,31) -> (79,9) -> map 49 (111,28)
--   map 49  (111,28) the block maze, described below
--   map 50  (37,23) -> (79,58) -> map 20 (27,8)
--   map 20  (27,8)  the clifftop: 39 tiles along y=8, x 26..53, holding
--                   (26,8) back into map 50 and (53,9) into map 30 (67,28),
--                   which is Arvis's house.  This is the ledge
--                   narshe_streets sits on and gen_mines_chase walks west
--                   along: the scenario comes back up the way Terra
--                   originally escaped.

-- A decoding hazard worth recording, because it sent this route to the wrong
-- house first: short_entrance.dat's DestX is seven bits on a 128-wide map.
-- Masking it with $3F turns map 20 (53,9)'s destination from map 30 (67,28),
-- Arvis's back corridor and the reciprocal of map 30 (67,26) -> map 20
-- (53,8), into map 30 (3,28), a room on the far side of the map, and makes
-- every 128-wide map's doors look like they do not pair up.

-- Both flag bytes in that guard are engine state rather than story switches,
-- the same aliasing the scenario brief flagged for the river:
--     $01A0-$01A7 alias $1EB4, where cmp_var leaves its result:
--         1 = equal, 2 = greater, 4 = less (field/event.asm:4519-4533).
--         So `if_switch $01A0=1` reads "if var 0 == K".
--     $01B0-$01B7 alias $1EB6, the control-flags byte; $01B5 is the
--         once-per-tile event latch.
-- Event variables themselves live at $1FC2 + 2n (EventCmd_e8, :4458-4464),
-- so var 0 is the word at $1FC2 and every gate below asserts it.

-- The order is fixed and one-way; it is seeded by the trigger on (111,26),
-- _ccd9c4 (:111026), which is the maze's own intro cutscene and ends
-- `switch $01F0=1 / set_var 0, 0 / set_var 1, 0` (:111068-111070).  The
-- thirteen gates then run 0 -> 1 -> 3 -> 4 -> 9 -> 16 -> 6 -> 7 -> 2 -> 21
-- -> 8 -> 18 -> 17 -> 20, snaking the party twice around the level, and the
-- trigger at (111,12) on the way out (_cce3f4, :112833) resets var 0 to 0
-- behind it.
local H = dofile("tools/tests/lib/ot6.lua")
local CAVES = "build/states/terra_caves.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function var0() return H.readWord(0x1fc2) end
local function seq(steps) return H.cond(function() return true end, steps) end

local DD = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 },
             right = { 1, 0 }, upleft = { -1, -1 }, upright = { 1, -1 },
             downleft = { -1, 1 }, downright = { 1, 1 } }
local function planAvoids(tx, ty, bad, what)
  return H.cond(function() return true end, {
    H.waitUntil(function() return H.bfsPath(tx, ty) ~= nil end,
                900, what .. ": a path exists (45f poll)", 45),
    H.call(function()
    local p = H.bfsPath(tx, ty)
    H.assertEq(p ~= nil, true, what .. ": a path exists")
    local x, y, hx, hy = H.fieldX(), H.fieldY(), nil, nil
    for _, d in ipairs(p) do
      x, y = x + DD[d][1], y + DD[d][2]
      for _, b in ipairs(bad) do
        if x == b[1] and y == b[2] then hx, hy = x, y end
      end
    end
    H.log(string.format("%s: %d steps, clean: %s", what, #p, tostring(hx == nil)))
    H.assertEq(hx == nil, true, what .. ": plan avoids the forbidden tiles" ..
      (hx and string.format(" (hits %d,%d)", hx, hy) or ""))
  end),
  })
end

local encounters = {}
local function watch()
  local seen = 0
  return function()
    if H.battleLoadStarted() then
      seen = seen + 1
      if seen == 3 then
        local w = H.formationWords()
        encounters[#encounters + 1] = { map = map(), f = H.frame, w = w }
        H.log(string.format("cave encounter #%d f%d map=%d: %04X %04X %04X " ..
          "%04X %04X %04X", #encounters, H.frame, map(), w[1], w[2], w[3],
          w[4], w[5], w[6]))
      end
    else
      seen = 0
    end
  end
end
local seeBattles = watch()

local PRESS = { up = "up", right = "right", down = "down", left = "left" }
local STEP = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }

local function mazeWalk(gx, gy, what, budget)
  local plan, idx, tx, ty, startMap = nil, 1, nil, nil, nil
  local aPh, battN, dlgN = 0, 0, 0
  return H.driveUntil(function()
    local done = (H.fieldX() == gx and H.fieldY() == gy)
              or (startMap ~= nil and (H.mapId() & 0x1ff) ~= startMap)
    if done then H.setPad({}) end
    return done
  end, budget or 30000, {
    H.call(function()
      if startMap == nil then startMap = H.mapId() & 0x1ff end
      aPh = (aPh + 1) % 8
      battN = H.battleLoadStarted() and battN + 1 or 0
      dlgN  = H.dialogWaiting() and dlgN + 1 or 0
      if battN >= 3 then
        plan, tx, ty = nil, nil, nil
        seeBattles()
        H.setPad(aPh < 4 and { "a" } or {})
        return
      end
      if dlgN >= 3 then plan, tx, ty = nil, nil, nil
        H.setPad(aPh < 4 and { "a" } or {}); return end
      if not H.hasControl() then plan, tx, ty = nil, nil, nil
        H.setPad({}); return end
      if not plan then
        if not H.tileAligned() then H.setPad({}); return end
        local p = H.bfsPath(gx, gy)
        if not p then H.setPad({}); return end
        for _, d in ipairs(p) do
          if not STEP[d] then
            error(string.format("%s: BFS returned a diagonal (%s) in the " ..
              "maze -- corridors should be 1-wide cardinal", what, d), 0)
          end
        end
        plan, idx = p, 1
        if #plan == 0 then H.setPad({}); return end
      end
      local dir = plan[idx]
      if not tx then
        tx, ty = H.fieldX() + STEP[dir][1], H.fieldY() + STEP[dir][2]
      end
      if H.fieldX() == tx and H.fieldY() == ty then
        idx = idx + 1
        tx, ty = nil, nil
        if idx > #plan then plan = nil end
        return
      end
      H.setPad({ [PRESS[dir]] = true })
    end),
  }, what)
end

local function gateStep(gx, gy, what, budget)
  local aPh, battN = 0, 0
  return H.driveUntil(function()
    local done = H.fieldX() == gx and H.fieldY() == gy
    if done then H.setPad({}) end
    return done
  end, budget or 15000, {
    H.call(function()
      aPh = (aPh + 1) % 8
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 3 then
        seeBattles()
        H.setPad(aPh < 4 and { "a" } or {})
        return
      end
      if H.dialogWaiting() then H.setPad(aPh < 4 and { "a" } or {}); return end
      -- Push toward the target one axis at a time, choosing the axis whose
      -- immediate neighbour is actually walkable so an L-corridor is turned
      -- correctly (the corners on this map are single-tile).  canStep uses the
      -- live tile props, so it is only meaningful at rest, but between held
      -- steps the party is at rest for a frame, and holding a wrong direction
      -- into a wall does not move, so a wrong pick corrects itself on the next
      -- aligned frame.  The candidate list is ordered by the larger delta.
      local x, y = H.fieldX(), H.fieldY()
      local dx, dy = gx - x, gy - y
      local cand = {}
      local function add(dir) if dir then cand[#cand + 1] = dir end end
      if math.abs(dy) >= math.abs(dx) then
        add(dy < 0 and "up" or dy > 0 and "down")
        add(dx < 0 and "left" or dx > 0 and "right")
      else
        add(dx < 0 and "left" or dx > 0 and "right")
        add(dy < 0 and "up" or dy > 0 and "down")
      end
      local pick
      for _, dir in ipairs(cand) do
        if H.canStep(x, y, dir) then pick = dir; break end
      end
      pick = pick or cand[1]
      H.setPad(pick and { [PRESS[pick]] = true } or {})
    end),
  }, what)
end

local function landed(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d) f%d blocked: map=%d ctl=%s algn=%s " ..
        "bright=%d batt=%s dlg=%s at (%d,%d) ev=%s var0=%d", m, H.frame, map(),
        tostring(H.hasControl()), tostring(H.tileAligned()), bright(),
        tostring(H.battleLoadStarted()), tostring(H.dialogWaiting()),
        H.fieldX(), H.fieldY(), tostring(H.eventRunning()), var0()))
    end
    return cnt >= (n or 20)
  end
end

-- One map crossing: plan it clear of the way straight back, walk it, settle
-- on the far side.  Each `settle` closure is built once, here, because
-- landed() carries a consecutive-frame counter and building it inline per
-- frame pins the count at 1.
local function cross(tx, ty, dstMap, ax, ay, bad, what, budget)
  local settle = landed(dstMap)
  return seq({
    planAvoids(tx, ty, bad, what),
    H.navTo(tx, ty, { maxFrames = budget or 60000, playBattles = "tactical",
      arrive = function()
        seeBattles()
        return map() == dstMap
      end }),
    H.release(),
    H.advanceStory(settle, 20000, { playBattles = "tactical" }),
    H.waitFrames(30),
    -- and the layer of care, every crossing, exactly as gen_kolts does it
    H.fieldCare({ tag = "care " .. what, threshold = 0.8 }),
    H.call(function()
      H.assertEq(map(), dstMap, what .. ": landed on map " .. dstMap)
      H.assertEq(H.fieldX(), ax, what .. ": arrival x")
      H.assertEq(H.fieldY(), ay, what .. ": arrival y")
      H.log(string.format("[%s] f%d map=%d (%d,%d) encounters=%d",
        what, H.frame, map(), H.fieldX(), H.fieldY(), #encounters))
    end),
  })
end

-- x, y, the var-0 value the gate demands, the value it leaves behind, and an
-- optional waypoint to route through on the way there.

-- Gate 2 is the only one that needs the waypoint, and it needs it because of
-- a tie rather than a wall.  From gate 1 at (110,23) there are two seven-step
-- routes to (106,20): west along y=23 to (106,23) and up the x=106 column, or
-- up the x=110 column and west along y=20.  The second steps on (109,20),
-- which is gate 3 and wants var 0 = 3 when it is about to be 1.  BFS picked
-- it, planAvoids caught it, and the fix is to state which of the two equal
-- paths this route means.
local GATES = {
  { 110, 23,  0,  1 }, { 106, 20,  1,  3, { 106, 23 } },
  { 109, 20,  3,  4 }, { 109, 17,  4,  9 },
  { 112, 17,  9, 16 }, { 112, 20, 16,  6 },
  { 113, 20,  6,  7 }, { 113, 23,  7,  2 }, { 116, 23,  2, 21 },
  { 116, 20, 21,  8 }, { 116, 16,  8, 18 }, { 112, 16, 18, 17 },
  { 112, 13, 17, 20 },
}
local ALL_GATES = {}
for _, g in ipairs(GATES) do ALL_GATES[#ALL_GATES + 1] = { g[1], g[2] } end
-- every gate except #i, so a hop is asserted not to step onto a gate that
-- is not its own, which is the only way this maze can go wrong
local function othersThan(i)
  local t = {}
  for j, g in ipairs(GATES) do
    if j ~= i then t[#t + 1] = { g[1], g[2] } end
  end
  return t
end

local mazeSteps = {}
for i, g in ipairs(GATES) do
  local gx, gy, want, becomes, via = g[1], g[2], g[3], g[4], g[5]
  mazeSteps[#mazeSteps + 1] = seq({
    H.call(function()
      H.assertEq(var0(), want, string.format(
        "maze gate %d/%d (%d,%d): var 0 is %d as the gate demands",
        i, #GATES, gx, gy, want))
    end),
    -- an explicit waypoint disambiguates a tie rather than a wall: two
    -- equal-length
    -- routes to the next gate, one of which brushes a third gate tile
    via and seq({
      planAvoids(via[1], via[2], ALL_GATES,
        string.format("maze gate %d/%d: via (%d,%d)", i, #GATES, via[1], via[2])),
      gateStep(via[1], via[2],
        string.format("maze gate %d/%d: via (%d,%d)", i, #GATES, via[1], via[2])),
    }) or H.call(function() end),
    planAvoids(gx, gy, othersThan(i),
      string.format("maze gate %d/%d -> (%d,%d)", i, #GATES, gx, gy)),
    gateStep(gx, gy, string.format("maze gate %d/%d -> (%d,%d)", i, #GATES, gx, gy)),
    H.release(),
    H.waitFrames(20),
    H.call(function()
      seeBattles()
      H.assertEq(H.fieldX(), gx, string.format("gate %d: standing on x=%d", i, gx))
      H.assertEq(H.fieldY(), gy, string.format("gate %d: standing on y=%d", i, gy))
      H.assertEq(var0(), becomes, string.format(
        "gate %d/%d passed CLEAN: var 0 -> %d (a ring would have left it %d)",
        i, #GATES, becomes, want))
      H.log(string.format("maze: gate %d/%d (%d,%d) f%d var0=%d var1=%d",
        i, #GATES, gx, gy, H.frame, var0(), H.readWord(0x1fc4)))
    end),
  })
end

H.run({ maxFrames = 250000 }, {
  H.loadState(CAVES),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 41, "booted on map 41, the Narshe mines")
    H.assertEq(H.fieldX(), 7, "at the arrival tile x=7")
    H.assertEq(H.fieldY(), 33, "at the arrival tile y=33")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(sw(0x0019), 1, "$0019 set -- the river was run")
    H.assertEq(sw(0x001F), 1, "$001F set -- the townsfolk turned us away")
    H.assertEq(sw(0x0020), 1, "$0020 set -- the wall was opened")
    H.assertEq(sw(0x0021), 0, "$0021 clear -- the scenario is not done")
    H.assertEq((H.readByte(0x185e) & 0x07) ~= 0, true, "BANON in the party")
  end),

  cross(21,  9, 20, 23, 44, { {  7, 34 } }, "map 41 -> map 20's sealed pocket"),
  cross(10, 36, 48, 87, 31, { { 22, 44 } }, "the pocket -> map 48"),
  cross(79,  9, 49, 111, 28, { { 87, 32 } }, "map 48 -> map 49"),

  -- ===================================================================== --
  -- The maze.  (111,26) first: _ccd9c4 is its intro and also what
  -- seeds var 0, so the gates below are meaningless until it has run.
  -- ===================================================================== --
  H.call(function()
    H.log(string.format("[maze] entering at (%d,%d), var0=%d $01F0=%d",
      H.fieldX(), H.fieldY(), var0(), sw(0x01F0)))
  end),
  planAvoids(111, 24, ALL_GATES, "map 49: onto the maze floor (111,24)"),
  mazeWalk(111, 24, "map 49: onto the maze floor (111,24)"),
  H.release(),
  H.advanceStory(landed(49), 20000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x01F0), 1, "$01F0 set -- _ccd9c4, the maze intro, ran")
    H.assertEq(var0(), 0, "var 0 seeded to 0 (_ccd9c4, :111069)")
    H.screenshot("terra_maze_start")
  end),
  seq(mazeSteps),

  -- Out of the maze.  Gate 13 (112,13) is left the way every gate is left:
  -- push through with gateStep, here to (111,13), so the re-fire cannot close
  -- a ring behind the party.  From there (111,12) is _cce3f4 (:112833), which
  -- resets both vars and returns, with no ring, so the last hop up onto
  -- (111,10) and the map-50 load uses the release-aware mazeWalk again.
  gateStep(111, 13, "map 49: off gate 13 to (111,13)"),
  H.release(),
  planAvoids(111, 10, ALL_GATES, "map 49: the maze exit (111,10)"),
  mazeWalk(111, 10, "map 49: to the exit (111,10)", 30000),
  H.release(),
  H.advanceStory(landed(50), 20000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 50, "map 49 -> map 50")
    H.assertEq(H.fieldX(), 37, "map 50 arrival x=37")
    H.assertEq(H.fieldY(), 23, "map 50 arrival y=23")
    H.log(string.format("[map 49 -> map 50] f%d (%d,%d) encounters=%d",
      H.frame, H.fieldX(), H.fieldY(), #encounters))
  end),
  -- The map-50 cave save point (66,41) -- vanilla's, taken in passing on
  -- the way up.  gen_seed_terracave.lua lifts the battery riding
  -- terra_clifftop.mss as the terra-caves-v1 seed.  Tolerant: skip with
  -- a log rather than fail the scenario if the tile proves unreachable.
  H.cond(function() return H.bfsPath(66, 41) ~= nil end, {
    H.navTo(66, 41, { maxFrames = 20000, playBattles = "tactical" }),
    H.waitFrames(30),
    H.call(function()
      H.assertEq((H.readByte(0x1EB7) & 0x80) ~= 0, true,
        "$01BF SET -- the map-50 save point (66,41)")
    end),
    H.saveGame({ tag = "terra cave save" }),
  }, {
    H.logStep("map-50 save point (66,41) not reachable from here; skipped"),
  }),
  cross(79, 58, 20, 27,  8, { { 37, 24 }, { 49, 11 }, { 49, 21 } },
        "map 50 -> the clifftop", 60000),

  H.call(function()
    H.assertEq(map(), 20, "on map 20, the CLIFFTOP above Narshe")
    H.assertEq(H.fieldX(), 27, "arrival tile x=27")
    H.assertEq(H.fieldY(), 8, "arrival tile y=8 (map 50 (79,58) -> map 20 (27,8))")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    H.assertEq(sw(0x0021), 0, "$0021 clear -- the scenario is not done")
    H.assertEq((H.readByte(0x185e) & 0x07) ~= 0, true, "BANON still in the party")
    local p = H.bfsPath(53, 9)
    H.assertEq(p ~= nil, true, "(53,9) -> map 30 (67,28) is reachable from here")
    H.log(string.format("   to Arvis's back door (53,9): %d steps", #p))
    H.log(string.format("   %d random encounter(s) crossing the caves",
      #encounters))
    for i, e in ipairs(encounters) do
      H.log(string.format("   encounter %d map=%d f%d: %04X %04X %04X %04X",
        i, e.map, e.f, e.w[1], e.w[2], e.w[3], e.w[4]))
    end
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d mp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11),
          H.readWord(base + 13), H.readWord(base + 15)))
      end
    end
    H.log(string.format("[terra_clifftop] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.screenshot("terra_clifftop")
  end),
  H.saveState("terra_clifftop.mss"),
  H.logStep(function()
    return string.format("terra_clifftop generated at frame %d (%d encounters)",
      H.frame, #encounters)
  end),
})
