-- probe_m86_pockets.lua -- #218, third measurement.  Map 86 is built out of
-- same-map warps, and probe_basement_save2 showed the pocket the escape
-- lands in (86 (49,31), from map 87 (57,48)) is 20 tiles wide and does not
-- contain (57,57), the door into map 84's save-point pocket
-- (short_entrance.dat: 86 (57,57) -> 84 (56,55), 84 (57,54) -> 86 (58,56)).
--
-- This floods map 86 from the OTHER end the route touches -- the
-- sfigaro_passage fixture, LOCKE at 86 (7,51) -- to find which pocket the
-- (57,57) door lives in.  Read-only, no walking.
-- @manual
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function seq(steps) return H.cond(function() return true end, steps) end

local MOVES = { "up", "down", "left", "right",
                "upleft", "upright", "downleft", "downright" }
local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 },
                right = { 1, 0 }, upleft = { -1, -1 }, upright = { 1, -1 },
                downleft = { -1, 1 }, downright = { 1, 1 } }

local function flood(tag, marks)
  local seen, q, qi, done, order = nil, nil, 1, false, nil
  return seq({
    H.call(function()
      local sx, sy = H.fieldX(), H.fieldY()
      seen = { [sy * 256 + sx] = true }
      order = { [sy * 256 + sx] = 1 }
      q, qi, done = { { sx, sy } }, 1, false
      H.log(string.format("=== flood %s: map %d from (%d,%d) ===",
        tag, map(), sx, sy))
    end),
    H.driveUntil(function() return done end, 12000, {
      H.call(function()
        H.setPad({})
        local budget = 200
        while qi <= #q and budget > 0 do
          local x, y = q[qi][1], q[qi][2]
          qi = qi + 1
          budget = budget - 1
          for _, d in ipairs(MOVES) do
            if H.canStep(x, y, d) then
              local nx, ny = x + DELTA[d][1], y + DELTA[d][2]
              local k = ny * 256 + nx
              if not seen[k] and nx >= 0 and ny >= 0 and nx < 256 and ny < 256 then
                seen[k] = true
                q[#q + 1] = { nx, ny }
                order[k] = #q
              end
            end
          end
        end
        if qi > #q or #q > 20000 then done = true end
      end),
    }, "flood " .. tag),
    H.call(function()
      local minx, miny, maxx, maxy, n = 999, 999, -1, -1, 0
      for k in pairs(seen) do
        local x, y = k % 256, k // 256
        n = n + 1
        if x < minx then minx = x end
        if x > maxx then maxx = x end
        if y < miny then miny = y end
        if y > maxy then maxy = y end
      end
      H.log(string.format("%s: %d tiles enqueued (queue %d), bbox (%d,%d)-(%d,%d)",
        tag, n, #q, minx, miny, maxx, maxy))
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
        local k = m[2] * 256 + m[1]
        H.log(string.format("   %s (%d,%d) %-34s %s%s", m[3], m[1], m[2], m[4],
          seen[k] and "REACHABLE" or "not reachable",
          seen[k] and string.format(" (flood enqueue #%d of %d)", order[k], #q) or ""))
      end
    end),
  })
end

local MARKS = {
  { 57, 57, "W", "-> 84 (56,55), the save pocket" },
  { 58, 56, "w", "<- 84 (57,54) comes back here" },
  {  7, 51, "s", "sfigaro_passage start" },
  {  3, 53, "a", "event warp -> (6,36)" },
  {  7, 49, "b", "warp -> (4,14)" },
  {  4, 15, "c", "warp -> (7,51)" },
  { 49, 55, "d", "-> town 75 (46,41)" },
  { 48, 32, "e", "-> map 87 (56,49)" },
  { 49, 31, "f", "the escape's landing from 87" },
  { 52, 27, "g", "-> town 75 (48,36)" },
  { 36, 23, "h", "-> town 75 (37,42)" },
  {  8, 25, "i", "-> town 75 (22,13)" },
  {  4,  4, "j", "-> town 75 (34,34)" },
  { 32, 11, "k", "warp -> (9,8)" },
  { 10,  7, "l", "warp -> (33,10)" },
}

H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/sfigaro_passage.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[probe] boot map=%d (%d,%d)", map(),
      H.fieldX(), H.fieldY()))
    H.assertEq(map(), 86, "sfigaro_passage is on map 86")
  end),
  flood("map 86 from the passage start", MARKS),
  (function()
    local steps = {}
    for _, m in ipairs(MARKS) do
      steps[#steps + 1] = H.call(function()
        local q = H.bfsPath(m[1], m[2])
        H.log(string.format("  H.bfsPath (%d,%d) -> (%2d,%2d) %-34s %s",
          H.fieldX(), H.fieldY(), m[1], m[2], m[4],
          q and (#q .. " steps") or "NO PATH (nil)"))
      end)
      steps[#steps + 1] = H.waitFrames(1)
    end
    return seq(steps)
  end)(),
})
