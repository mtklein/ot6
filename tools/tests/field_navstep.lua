-- @suite savestate=vector_sneak
-- field_navstep: navTo must land exactly on the tile it was asked for, and
-- must never report success from a tile the party has already left.
--
-- Map 242's Vector corridor walks ~1 px/frame, which reproduces navTo's
-- overshoot; the base whelk_entry fixture (map 41) walks faster and jitters,
-- and does not.  Each segment is a single tile: a multi-tile navTo can hide
-- an overshoot because the remaining path re-plans around it.  Each segment
-- asserts both the step it is about to take and, for the two directions the
-- engine latches (right, down), that the tile beyond the goal is passable,
-- so the overshoot is observable rather than blocked by a wall.
-- watchTile holds the arrival assertion open for 48 frames (three tiles of
-- walking) rather than checking once on return, since an overshoot is only
-- visible on the frames after navTo returns.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vector_sneak.mss.lua"

-- Hold the arrival assertion open for n frames: the party must stay on
-- (tx,ty) the whole time.  A stray Vector encounter is fled by holding L+R
-- (the engine's own run mechanic), and the count restarts once control is
-- back.
local function watchTile(tx, ty, n, what)
  local seen = 0
  return H.driveUntil(function() return seen >= n end, n * 8 + 1200, {
    H.call(function()
      H.setPad({})
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true })
        seen = 0
        return
      end
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

-- one segment: assert the step is real (and, for the two latching directions,
-- that the overshoot tile is passable, so that the bug would be observable),
-- walk it, then check the party stopped there.
local function segment(fx, fy, dir, tx, ty, what)
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
    H.navTo(tx, ty, { maxFrames = 3000, playBattles = "flee" }),
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

  -- down and right are the two the engine latches at the boundary; left and
  -- up are here so the fix cannot trade one direction for another.  The route
  -- stays inside the three-wide column x=56..58 the sneak lands in.
  -- ((57,35) cannot be left upward and (57,33) cannot be left downward,
  -- which is why the up segment is taken from (57,36).)
  segment(57, 34, "down", 57, 35, "one tile DOWN"),
  segment(57, 35, "down", 57, 36, "a second tile DOWN"),
  segment(57, 36, "up", 57, 35, "one tile UP"),
  segment(57, 35, "left", 56, 35, "one tile LEFT"),
  segment(56, 35, "right", 57, 35, "one tile RIGHT"),

  H.logStep("navTo lands exactly and comes to REST, in all four directions"),
})
