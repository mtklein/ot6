-- @suite savestate=vector_sneak
-- field_navstep: navTo must land exactly on the tile it was asked for, and
-- must never report success from a tile the party has already left (#22).
--
-- The defect this is the positive control for: pre-fix, navTo held a step's
-- direction until the tile coord (pixel>>4) changed and released there.
-- Moving up or left, that coord flips ~1px in, so the release was early
-- enough; moving right or down it flips only at completion, on the same frame
-- the engine re-reads the pad, and a setPad reaches the ROM only at the next
-- input poll.  So the release landed one poll late, the engine latched
-- a second step whenever the tile beyond was passable, and the terminator
-- ("on the tile, controlled, tile-aligned") fired on that single aligned
-- frame while the party was already walking off it.
--
-- Why this fixture: the overshoot needs a map that walks 1 px/frame.  The
-- base whelk_entry fixture (map 41) walks ~1.33 px/frame with jitter and
-- does not reproduce it, so a control written there would be the kind of
-- quiet test CONTRIBUTING.md warns about.  Map 242's Vector corridor does
-- reproduce it: measured with probe_step2, py 544 -> 560 over frames 6..21,
-- then straight on to 576.
--
-- Why one-tile segments: a multi-tile navTo hides the bug, because the
-- overshoot is re-planned around (a slide along the same move leaves the edge
-- proven good), and an even overshoot can land on the goal by chance.  It is
-- only visible when the last planned step is the one that reaches the goal.
--
-- Why the carry-tile assertions: the engine can only carry the party past
-- the goal if the tile beyond it is passable, so against a wall the bug is
-- invisible.  Each segment therefore asserts both the step it is about to take
-- and the overshoot tile it would land on, so a map or fixture change that
-- walls the corridor fails instead of measuring nothing.
--
-- Why a watch instead of a single assert: at the instant the broken
-- terminator fires the party is on the goal tile, and it leaves on the frames
-- after.  A check taken on the frame navTo returns therefore passes on the
-- unfixed library.  watchTile holds the assertion open for 48 frames, three
-- full tiles of walking, and fails the moment the party moves off.
--
-- Fail-before / pass-after, measured: on the pre-fix library the down segment
-- reported navTo success at (57,35) with the party at (57,36) sixty frames
-- later; watchTile catches it 16 frames in.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vector_sneak.mss.lua"

-- Hold the arrival assertion open for n frames: the party must stay on
-- (tx,ty) the whole time.  A stray Vector encounter is not a navigation
-- failure, so it is fled by holding L+R, the engine's own run mechanic (the
-- 1914283 idiom; the battle-clearing flag poke this replaced is an issue-#75
-- write), and the count restarts once control is back.  A formation that
-- refuses to release fails the driveUntil budget rather than being poked out
-- of existence.  The subject here, navTo's release timing on map 242, is
-- unaffected by how an interrupting fight ends.
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

  -- down and right are the two the engine latches at the boundary; left and
  -- up are here so the fix cannot trade one direction for another.  The route
  -- stays inside the three-wide column x=56..58 the sneak lands in, north of
  -- the gate guards' forced-battle row.  (The column is one-way in places:
  -- (57,35) cannot be left upward and (57,33) cannot be left downward, which
  -- is why the up segment is taken from (57,36).)
  segment(57, 34, "down", 57, 35, "one tile DOWN"),
  segment(57, 35, "down", 57, 36, "a second tile DOWN"),
  segment(57, 36, "up", 57, 35, "one tile UP"),
  segment(57, 35, "left", 56, 35, "one tile LEFT"),
  segment(56, 35, "right", 57, 35, "one tile RIGHT"),

  H.logStep("navTo lands exactly and comes to REST, in all four directions"),
})
