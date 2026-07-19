-- gen_terra_clifftop.lua -- from terra_caves.mss, the length of the Narshe
-- caves: map 41 -> a walled-off pocket of map 20 -> maps 48, 49, 50 -> out
-- onto the CLIFFTOP above Narshe, behind the checkpoint that turned the
-- party away.
-- Mints one state:
--   terra_clifftop.mss  map 20 (27,8), the ledge the caves come out on,
--                       first controllable frame -- one short walk from
--                       Arvis's back door and the end of the scenario.
--
-- ===================== SIX CROSSINGS, NONE OF THEM GUESSABLE ==============
-- Every pocket on this route is small and sealed, and H.bfsPath cannot show
-- you that: these maps are 128x64 ($86/$87 = $7F/$3F) and its 4096-node hang
-- guard trips long before it has seen one of them.  An uncapped flood over
-- the same passability rules (run as a reachability probe during
-- development) mapped them instead.  What that found:
--
--   map 41  (7,33)  82 tiles, two exits: (7,34) straight back to map 20
--                   (15,57), and (21,9) -> map 20 (23,44).
--   map 20  (23,44) 86 tiles, and NOT the town -- a sealed pocket whose only
--                   other door is (10,36) -> map 48 (87,31).
--   map 48  (87,31) -> (79,9) -> map 49 (111,28)
--   map 49  (111,28) THE BLOCK MAZE, below
--   map 50  (37,23) -> (79,58) -> map 20 (27,8)
--   map 20  (27,8)  the CLIFFTOP: 39 tiles along y=8, x 26..53, holding
--                   (26,8) back into map 50 and (53,9) into map 30 (67,28),
--                   which is ARVIS'S HOUSE.  This is the ledge
--                   narshe_streets sits on and gen_mines_chase walks west
--                   along: the scenario comes back up the way Terra
--                   originally escaped.
--
-- A DECODING TRAP WORTH RECORDING, because it sent this route to the wrong
-- house first: short_entrance.dat's DestX is SEVEN bits on a 128-wide map.
-- Masking it with $3F turns map 20 (53,9)'s destination from map 30 (67,28)
-- -- Arvis's back corridor, the exact reciprocal of map 30 (67,26) -> map 20
-- (53,8) -- into map 30 (3,28), a room on the far side of the map, and makes
-- every 128-wide map's doors look like they do not pair up.
--
-- ===================== MAP 49 IS AN ORDERED MAZE ==========================
-- EventTrigger::_49 carries TWENTY triggers (event_trigger.asm:242-261) and
-- thirteen of them are gates.  Each opens
--     cmp_var 0, K  /  if_switch $01A0=1, <pass>  /  if_switch $01B5=1, ...
--     call _cce405  /  <spawn eight NPCs in a ring>          (:111113-:112838)
-- and _cce405 is `pass_off NPC_1..NPC_8` (:112839) -- eight SOLID objects,
-- all circling the eight cells around the gate tile in lockstep on 8-move
-- loops.  Step on a gate out of turn and the ring closes around the party
-- and never opens: measured as navTo burning its 20 no-path retries at
-- (113,23) with a full ring and no instant at which a whole path exists.
--
-- BOTH FLAG BYTES IN THAT GUARD ARE ENGINE STATE, NOT STORY SWITCHES, and it
-- is the same aliasing the scenario brief flagged for the river:
--     $01A0-$01A7 alias $1EB4, where cmp_var leaves its result --
--         1 = equal, 2 = greater, 4 = less (field/event.asm:4519-4533).
--         So `if_switch $01A0=1` reads "if var 0 == K".
--     $01B0-$01B7 alias $1EB6, the control-flags byte; $01B5 is the
--         once-per-tile event latch.
-- Event variables themselves live at $1FC2 + 2n (EventCmd_e8, :4458-4464),
-- so var 0 is the word at $1FC2 and every gate below asserts it.
--
-- The order is fixed and one-way; it is seeded by the trigger on (111,26),
-- _ccd9c4 (:111026), which is the maze's own intro cutscene and ends
-- `switch $01F0=1 / set_var 0, 0 / set_var 1, 0` (:111068-111070).  The
-- thirteen gates then run 0 -> 1 -> 3 -> 4 -> 9 -> 16 -> 6 -> 7 -> 2 -> 21
-- -> 8 -> 18 -> 17 -> 20, snaking the party twice around the level, and the
-- trigger at (111,12) on the way out (_cce3f4, :112833) resets var 0 to 0
-- behind it.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local CAVES = "/Users/mtklein/ot6/build/states/terra_caves.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function var0() return H.readWord(0x1fc2) end
local function seq(steps) return H.cond(function() return true end, steps) end

local DD = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 },
             right = { 1, 0 }, upleft = { -1, -1 }, upright = { 1, -1 },
             downleft = { -1, 1 }, downright = { 1, 1 } }
local function planAvoids(tx, ty, bad, what)
  return H.call(function()
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
  end)
end

-- THE MAZE NEEDS A HOLD-WALKER, NOT navTo.  Measured on map 49: the party
-- moves one tile per ~15 held frames perfectly, but H.tileAligned() reads
-- false for EVERY one of those frames (the sub-pixel bytes $0869/$086C only
-- zero at rest), and navTo gates both its step launch and its landing check
-- on alignment -- so it releases after one tile, waits for an alignment that
-- only comes once it has already stopped, and on the next launch condemns the
-- edge as "blocked in reality" though a plain held UP walks the whole column.
-- So the maze is driven by holding the BFS plan's direction and watching the
-- tile coordinate advance, never releasing mid-run and never asking about
-- alignment.  BFS still does the pathfinding; only the executor changes.
-- Battle watcher (shared by every crossing and the maze driver): names each
-- encounter once on its third consecutive loading frame, the suite's debounce.
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

-- WHY THE MAZE CANNOT USE navTo.  Measured on map 49: the party moves one
-- tile per ~15 held frames perfectly, but H.tileAligned() reads false for
-- EVERY one of those frames (the sub-pixel bytes $0869/$086C only zero at
-- rest), and navTo gates both its step launch and its landing check on
-- alignment -- so it releases after one tile, waits for an alignment that
-- only comes once stopped, and on the next launch condemns the edge as
-- "blocked in reality" though a plain held UP walks the whole column.  Both
-- drivers below hold-walk instead.
--
-- mazeWalk -- RELEASES on event/dialog.  For the intro passage and the exit:
-- the intro cutscene (_ccd9c4, walked onto at (111,26)) shows dlg $01AC
-- (EDGAR/TERRA explaining the light, :111093) and moves the party with
-- obj_scripts, and a direction held into it jams it.  So this one taps
-- dialogs, kill-bits battles, and otherwise releases and waits.
local function mazeWalk(gx, gy, what, budget)
  local plan, idx, tx, ty, startMap = nil, 1, nil, nil, nil
  local aPh, battN, dlgN = 0, 0, 0
  return H.driveUntil(function()
    local done = (H.fieldX() == gx and H.fieldY() == gy)
              or (startMap ~= nil and (H.mapId() & 0x1ff) ~= startMap)
    if done then H.setPad({}) end
    return done
  end, budget or 12000, {
    H.call(function()
      if startMap == nil then startMap = H.mapId() & 0x1ff end
      aPh = (aPh + 1) % 8
      battN = H.battleLoadStarted() and battN + 1 or 0
      dlgN  = H.dialogWaiting() and dlgN + 1 or 0
      if battN >= 3 then
        plan, tx, ty = nil, nil, nil
        seeBattles()
        if H.monstersPresent() > 0 then
          for slot = 0, 5 do
            if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
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

-- gateStep -- PUSHES THROUGH.  For stepping from one solved gate to the next.
-- The moment a gate passes, its pass path sets $01B5 (the once-per-tile latch)
-- and returns control -- but the party is standing ON the trigger tile, and
-- the instant the first step off clears $01B5 the trigger re-fires, now with
-- var 0 already advanced past what it wants, and FALLS THROUGH to `call
-- _cce405` -- the ring of eight solid NPCs (event_main.asm, e.g. _cce35f).
-- Release for even one frame in that window and the ring closes and never
-- opens: measured as the party frozen on (116,23) with the event PC parked in
-- _cce35f for the whole budget.  A held direction walks straight off before
-- the re-fire resolves (a plain held UP was measured blowing through gates 10
-- and 11 without stopping), so this driver NEVER releases for an event -- it
-- keeps pressing toward the target, only pausing the press to tap a dialog or
-- kill-bit a battle.  It stops one tile short of overshoot by ending the frame
-- the tile coordinate first reads the target (which, moving up/left, is ~1px
-- into the final step -- exactly enough to have triggered the gate).
local function gateStep(gx, gy, what, budget)
  local aPh, battN = 0, 0
  return H.driveUntil(function()
    local done = H.fieldX() == gx and H.fieldY() == gy
    if done then H.setPad({}) end
    return done
  end, budget or 4000, {
    H.call(function()
      aPh = (aPh + 1) % 8
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 3 then
        seeBattles()
        if H.monstersPresent() > 0 then
          for slot = 0, 5 do
            if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
        H.setPad(aPh < 4 and { "a" } or {})
        return
      end
      if H.dialogWaiting() then H.setPad(aPh < 4 and { "a" } or {}); return end
      -- Push toward the target one axis at a time, choosing the axis whose
      -- immediate neighbour is actually walkable so an L-corridor is turned
      -- correctly (the corners on this map are single-tile).  canStep uses the
      -- LIVE tile props, so it is only meaningful at rest -- but between held
      -- steps the party IS at rest for a frame, and holding a wrong direction
      -- into a wall simply does not move, so a mis-pick self-corrects next
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
-- on the far side.  Each `settle` closure is built ONCE, here -- landed()
-- carries a consecutive-frame counter and building it inline per frame pins
-- the count at 1 forever.
local function cross(tx, ty, dstMap, ax, ay, bad, what, budget)
  local settle = landed(dstMap)
  return seq({
    planAvoids(tx, ty, bad, what),
    H.navTo(tx, ty, { maxFrames = budget or 40000, arrive = function()
      seeBattles()
      return map() == dstMap
    end }),
    H.release(),
    H.advanceStory(settle, 20000),
    H.waitFrames(30),
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
--
-- GATE 2 IS THE ONLY ONE THAT NEEDS THE WAYPOINT, and it needs it because of
-- a TIE, not a wall.  From gate 1 at (110,23) there are two seven-step routes
-- to (106,20): west along y=23 to (106,23) and up the x=106 column, or up the
-- x=110 column and west along y=20 -- and the second one steps on (109,20),
-- which is gate 3 and wants var 0 = 3 when it is about to be 1.  BFS picked
-- it, planAvoids caught it, and the fix is to say which of the two equal
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
-- every gate except #i, so a hop is asserted not to blunder onto a gate that
-- is not its own -- which is the only way this maze can go wrong
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
    -- an explicit waypoint disambiguates a TIE, not a wall: two equal-length
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
  -- THE MAZE.  (111,26) first: _ccd9c4 is its intro AND the thing that
  -- seeds var 0, so the gates below are meaningless until it has run.
  -- ===================================================================== --
  H.call(function()
    H.log(string.format("[maze] entering at (%d,%d), var0=%d $01F0=%d",
      H.fieldX(), H.fieldY(), var0(), sw(0x01F0)))
  end),
  planAvoids(111, 24, ALL_GATES, "map 49: onto the maze floor (111,24)"),
  mazeWalk(111, 24, "map 49: onto the maze floor (111,24)"),
  H.release(),
  H.advanceStory(landed(49), 20000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x01F0), 1, "$01F0 set -- _ccd9c4, the maze intro, ran")
    H.assertEq(var0(), 0, "var 0 seeded to 0 (_ccd9c4, :111069)")
    H.screenshot("terra_maze_start")
  end),
  seq(mazeSteps),

  -- OUT OF THE MAZE.  Gate 13 (112,13) is left the way every gate is left --
  -- push through with gateStep, here to (111,13), so the re-fire cannot close
  -- a ring behind us.  From there (111,12) is _cce3f4 (:112833), which resets
  -- both vars and just returns -- not a ring -- so the last hop up onto
  -- (111,10) and the map-50 load is the release-aware mazeWalk again.
  gateStep(111, 13, "map 49: off gate 13 to (111,13)"),
  H.release(),
  planAvoids(111, 10, ALL_GATES, "map 49: the maze exit (111,10)"),
  mazeWalk(111, 10, "map 49: to the exit (111,10)", 20000),
  H.release(),
  H.advanceStory(landed(50), 20000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 50, "map 49 -> map 50")
    H.assertEq(H.fieldX(), 37, "map 50 arrival x=37")
    H.assertEq(H.fieldY(), 23, "map 50 arrival y=23")
    H.log(string.format("[map 49 -> map 50] f%d (%d,%d) encounters=%d",
      H.frame, H.fieldX(), H.fieldY(), #encounters))
  end),
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
    return string.format("terra_clifftop minted at frame %d (%d encounters)",
      H.frame, #encounters)
  end),
})
