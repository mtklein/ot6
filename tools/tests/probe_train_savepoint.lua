-- probe_train_savepoint.lua -- #218: where the Phantom Train's save point
-- actually is, relative to the route gen_sabin_train walks.
--
-- Measured by the #218 diagnostic run (build/lab/218-train-diag.log):
--   * the engineer's room pocket the generator stands in is 31 tiles,
--     bbox (5,7)-(9,13); map 146's SavePoint (20,10) is NOT in it, and
--     neither is 146 (23,13), the door to map 152.
--   * the car-149 vestibule pocket is 21 tiles, bbox (27,5)-(31,10); map
--     149's SavePoint (24,6) is NOT in it either.
-- short_entrance.dat says map 146's east half is entered from map 152
-- (8,7) -> 146 (23,12), and map 152 hangs off the REAR strip, map 142, at
-- (83,8)/(85,8)/(86,8) -- east of (66,8), where the route first steps onto
-- the strip out of car A and immediately turns west.
--
-- This boots forest_done, rides the departure, takes car A's west door the
-- way the generator does, and then measures EAST instead: how far the strip
-- reaches, whether the map-152 doors are on it, and whether the save point
-- is reachable through them.  Read-only: no save is taken here.
-- @manual
local H = dofile("tools/tests/lib/ot6.lua")

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function seq(steps) return H.cond(function() return true end, steps) end
local function inBattle() return H.battleLoadStarted() end

local MOVES = { "up", "down", "left", "right",
                "upleft", "upright", "downleft", "downright" }
local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 },
                right = { 1, 0 }, upleft = { -1, -1 }, upright = { 1, -1 },
                downleft = { -1, 1 }, downright = { 1, 1 } }

local function flood(tag, marks)
  local seen, q, qi, done = nil, nil, 1, false
  return seq({
    H.call(function()
      local sx, sy = H.fieldX(), H.fieldY()
      seen = { [sy * 256 + sx] = true }
      q, qi, done = { { sx, sy } }, 1, false
      H.log(string.format("=== flood %s: map %d from (%d,%d) ===",
        tag, mapIdx(), sx, sy))
    end),
    H.driveUntil(function() return done end, 12000, {
      H.call(function()
        H.setPad({})
        local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
        local budget = 200
        while qi <= #q and budget > 0 do
          local x, y = q[qi][1], q[qi][2]
          qi = qi + 1
          budget = budget - 1
          for _, d in ipairs(MOVES) do
            if H.canStep(x, y, d) then
              local nx, ny = (x + DELTA[d][1]) & xm, (y + DELTA[d][2]) & ym
              local k = ny * 256 + nx
              if not seen[k] then
                seen[k] = true
                q[#q + 1] = { nx, ny }
              end
            end
          end
        end
        if qi > #q or #q > 20000 then done = true end
      end),
    }, "flood " .. tag),
    H.call(function()
      local minx, miny, maxx, maxy = 999, 999, -1, -1
      for k in pairs(seen) do
        local x, y = k % 256, k // 256
        if x < minx then minx = x end
        if x > maxx then maxx = x end
        if y < miny then miny = y end
        if y > maxy then maxy = y end
      end
      H.log(string.format("%s: %d tiles, bbox (%d,%d)-(%d,%d)",
        tag, #q, minx, miny, maxx, maxy))
      local px, py = H.fieldX(), H.fieldY()
      local mk = {}
      for _, m in ipairs(marks or {}) do mk[m[2] * 256 + m[1]] = m[3] end
      for y = miny, maxy do
        local row = {}
        for x = minx, maxx do
          local k = y * 256 + x
          if x == px and y == py then row[#row + 1] = "@"
          elseif mk[k] then row[#row + 1] = mk[k]
          elseif seen[k] then row[#row + 1] = "."
          else row[#row + 1] = " " end
        end
        H.log(string.format("%3d |%s|", y, table.concat(row)))
      end
      for _, m in ipairs(marks or {}) do
        H.log(string.format("   %s (%d,%d) %-32s %s", m[3], m[1], m[2], m[4],
          seen[m[2] * 256 + m[1]] and "REACHABLE" or "not reachable"))
      end
    end),
  })
end

local function askBfs(pts)
  local steps = {}
  for _, p in ipairs(pts) do
    steps[#steps + 1] = H.call(function()
      local q = H.bfsPath(p[1], p[2])
      H.log(string.format("  H.bfsPath map %d from (%d,%d) -> (%2d,%2d) %-30s %s",
        mapIdx(), H.fieldX(), H.fieldY(), p[1], p[2], p[3],
        q and (#q .. " steps") or "NO PATH (nil)"))
    end)
    steps[#steps + 1] = H.waitFrames(1)
  end
  return seq(steps)
end

local function holdDrive(dir, pred, what, budget)
  local phase, hb = 0, -600
  local W = H.newWalkFighter("holdDrive " .. what)
  return H.driveUntil(pred, budget or 15000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 600 then
        hb = H.frame
        H.log(string.format("drive[%s] f%d map=%d (%d,%d) ctl=%s",
          what, H.frame, mapIdx(), H.fieldX(), H.fieldY(),
          tostring(H.hasControl())))
      end
      if W.frame() then return end
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

local function settle(toMap, what)
  local phase = 0
  return seq({
    H.driveUntil(function()
      return mapIdx() == toMap and H.hasControl() and H.tileAligned()
         and bright() >= 15
    end, 6000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(H.dialogWaiting() and phase < 4 and { "a" } or {})
      end),
    }, what),
    H.waitFrames(20),
    H.call(function()
      H.log(string.format("[settle %s] map=%d (%d,%d)", what, mapIdx(),
        H.fieldX(), H.fieldY()))
    end),
  })
end

local function nav(x, y, o)
  o = o or {}
  o.playBattles = "tactical"
  o.maxFrames = (o.maxFrames or 20000) + 12000
  return H.navTo(x, y, o)
end

local STRIP = {
  { 75, 8, "A", "car A's east door lands here" },
  { 74, 8, "a", "back into car A (145 (29,7))" },
  { 66, 8, "W", "car A's west door pocket (the route's turn)" },
  { 58, 8, "B", "car B's east door" },
  { 83, 8, "1", "-> map 152 (2,8)" },
  { 85, 8, "2", "-> map 152 (9,11)" },
  { 86, 8, "3", "-> map 152 (13,8)" },
}

H.run({ maxFrames = 120000 }, {
  H.loadState("build/states/forest_done.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIdx(), 145, "boot aboard the train, map 145")
    H.log(string.format("[probe] boot map=%d (%d,%d) $0038=%d $0039=%d",
      mapIdx(), H.fieldX(), H.fieldY(), sw(0x38), sw(0x39)))
  end),
  holdDrive("down", function() return sw(0x39) == 1 end, "departure", 6000),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
  end, 4000, "post-departure", 5),
  -- car A's EAST door (145 (30,7)/(30,8) -> _cbaaaf -> _cba76c ->
  -- load_map 142 {75,8}), the one the route never takes: it turns west at
  -- (2,7) instead.  The map-152 doors at 142 (83,8)/(85,8)/(86,8) are in
  -- THAT pocket, not the (66,8) one.
  nav(29, 7, { maxFrames = 12000 }),
  holdDrive("right", function() return mapIdx() == 142 end, "A east exit", 4000),
  settle(142, "east pocket (75,8)"),
  H.call(function() H.screenshot("trainsave_strip142") end),
  askBfs({
    { 83, 8, "-> map 152 (2,8)" },
    { 85, 8, "-> map 152 (9,11)" },
    { 86, 8, "-> map 152 (13,8)" },
    { 74, 8, "back into car A (145 (29,7))" },
    { 66, 8, "car A's west door pocket" },
  }),
  flood("rear strip 142 from car A's east door", STRIP),

  -- east along the strip and into map 152
  nav(83, 8, { maxFrames = 20000, arrive = function() return mapIdx() ~= 142 end }),
  H.release(),
  settle(152, "map 152 (the rear car)"),
  H.call(function() H.screenshot("trainsave_m152") end),
  askBfs({
    { 8, 7, "-> map 146 (23,12), the save car" },
    { 1, 8, "back out to 142 (82,8)" },
  }),
  flood("map 152", {
    { 8, 7, "D", "-> map 146 (23,12)" },
    { 1, 8, "W", "-> 142 (82,8)" },
    { 14, 8, "E", "-> 142 (87,8)" },
  }),

  nav(8, 7, { maxFrames = 20000, arrive = function() return mapIdx() ~= 152 end }),
  H.release(),
  settle(146, "map 146 east half"),
  H.call(function() H.screenshot("trainsave_m146east") end),
  askBfs({ { 20, 10, "map 146's SavePoint" } }),
  flood("map 146 east half", {
    { 20, 10, "V", "the SavePoint" },
    { 23, 12, "I", "the arrival from 152" },
    { 23, 13, "O", "-> map 152 (8,8)" },
  }),
  nav(20, 10, { maxFrames = 12000 }),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[probe] standing on (%d,%d) map %d: $01BF=%d ($1EB7=$%02X)",
      H.fieldX(), H.fieldY(), mapIdx(), sw(0x01BF), H.readByte(0x1EB7)))
    H.screenshot("trainsave_on_savepoint")
  end),
})
