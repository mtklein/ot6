-- @suite frontier=vector_sneak
-- field_navstep: navTo must land EXACTLY on the tile it was asked for, and
-- must never report success from a tile the party has already left (#22).
--
-- THE DEFECT THIS IS THE POSITIVE CONTROL FOR.  Pre-fix, navTo held a step's
-- direction until the tile coord (pixel>>4) changed and released there.
-- Moving up or left that coord flips ~1px in, so the release was early
-- enough; moving RIGHT or DOWN it flips only AT completion -- the same frame
-- the engine re-reads the pad -- and a setPad reaches the ROM only at the
-- NEXT input poll.  So the release landed one poll late, the engine latched
-- a second step whenever the tile beyond was passable, and the terminator
-- ("on the tile, controlled, tile-aligned") fired on that single aligned
-- frame while the party was already walking off it.
--
-- WHY THIS FIXTURE.  The overshoot needs a map that walks 1 px/frame; the
-- base whelk_doorstep fixture (map 41) walks ~1.33 px/frame with jitter and
-- does NOT reproduce it -- a control written there is exactly the quiet test
-- CONTRIBUTING.md warns about.  Map 242's Vector corridor does: measured
-- with probe_step2, py 544 -> 560 over frames 6..21, then straight on to 576.
--
-- WHY ONE-TILE LEGS.  A multi-tile navTo hides the bug: the overshoot is
-- re-planned around (a slide along the same move leaves the edge proven
-- good), and an even overshoot can land on the goal by luck.  It is only
-- visible when the LAST planned step is the one that reaches the goal.
--
-- WHY THE CARRY-TILE ASSERTIONS.  The engine can only carry the party past
-- the goal if the tile BEYOND it is passable -- against a wall the bug is
-- invisible.  Each leg therefore asserts both the step it is about to take
-- and the overshoot tile it would land on, so a map or fixture change that
-- walls the corridor fails loudly instead of quietly measuring nothing.
--
-- WHY THE WATCH, NOT A SINGLE ASSERT.  At the instant the broken terminator
-- fires the party IS on the goal tile; it leaves on the frames AFTER.  A
-- check taken the frame navTo returns therefore passes on the unfixed
-- library.  watchTile holds the assertion open for 48 frames -- three full
-- tiles of walking -- and fails the moment the party moves off.
--
-- FAIL-BEFORE / PASS-AFTER, measured: on the pre-fix library the DOWN leg
-- reported navTo success at (57,35) with the party at (57,36) sixty frames
-- later; watchTile catches it 16 frames in.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vector_sneak.mss.lua"

local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

-- Hold the arrival assertion open for n frames: the party must stay on
-- (tx,ty) the whole time.  A stray Vector encounter is not a navigation
-- failure, so it is kill-bitted and the count restarts once control is back.
local function watchTile(tx, ty, n, what)
  local seen = 0
  return H.driveUntil(function() return seen >= n end, n * 8 + 1200, {
    H.call(function()
      H.setPad({})
      if H.battleLoadStarted() then killBitAll(); seen = 0; return end
      if not H.hasControl() then seen = 0; return end
      local x, y = H.fieldX(), H.fieldY()
      if x ~= tx or y ~= ty then
        error(string.format(
          "%s: navTo reported (%d,%d), but %d frames later the party is at " ..
          "(%d,%d) -- it was still walking when navTo terminated",
          what, tx, ty, seen, x, y), 0)
      end
      seen = seen + 1
    end),
  }, what)
end

-- one leg: assert the step is real (and, for the two latching directions,
-- that the overshoot tile is passable so the bug WOULD be observable), walk
-- it, then prove the party stopped there.
local function leg(fx, fy, dir, tx, ty, what)
  local latching = (dir == "right" or dir == "down")
  return H.cond(function() return true end, {
    H.call(function()
      H.assertEq(H.fieldX() == fx and H.fieldY() == fy, true,
        string.format("%s: starts from (%d,%d)", what, fx, fy))
      H.assertEq(H.canStep(fx, fy, dir), true, what .. ": the step is real")
      if latching then
        H.assertEq(H.canStep(tx, ty, dir), true,
          what .. ": the overshoot tile is passable (the bug is observable)")
      end
    end),
    H.navTo(tx, ty, { maxFrames = 3000 }),
    H.call(function()
      H.log(string.format("[navstep] %s: navTo returned at (%d,%d)",
        what, H.fieldX(), H.fieldY()))
    end),
    watchTile(tx, ty, 48, what),
  })
end

H.run({ maxFrames = 30000 }, {
  H.loadState(STATE),
  H.waitFrames(60),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end,
    1800, "field control on the Vector sneak ledge", 5),
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 242, "vector_sneak is VECTOR (map 242)")
    H.assertEq(H.fieldX(), 57, "sneak landing x")
    H.assertEq(H.fieldY(), 34, "sneak landing y")
  end),

  -- DOWN and RIGHT are the two the engine latches at the boundary; LEFT and
  -- UP are here so the fix cannot buy one direction with another.  The route
  -- stays inside the three-wide column x=56..58 the sneak lands in, north of
  -- the gate guards' forced-battle row.  (The column is one-way in places --
  -- (57,35) cannot be left upward, (57,33) cannot be left downward -- which
  -- is why the UP leg is taken from (57,36).)
  leg(57, 34, "down", 57, 35, "one tile DOWN"),
  leg(57, 35, "down", 57, 36, "a second tile DOWN"),
  leg(57, 36, "up", 57, 35, "one tile UP"),
  leg(57, 35, "left", 56, 35, "one tile LEFT"),
  leg(56, 35, "right", 57, 35, "one tile RIGHT"),

  H.logStep("navTo lands exactly and comes to REST, in all four directions"),
})
