-- probe_m75_pockets.lua -- #218, fifth measurement.  The map-84 SavePoint
-- pocket's one door is map 86 (57,57), and map 86's own doors from the
-- occupied town are 75 (22,14)/(48,37)/(34,35)/(37,40)/(46,39).  The escape
-- lands in town at (48,36) and cannot reach (46,39) from there
-- (probe_basement_save3: "navTo: no path (48,36)->(46,40)").  This floods
-- the occupied town from the sfigaro_town fixture and marks every door, to
-- say which quarter (46,39) is in and whether the town is walkable to it at
-- all.  Read-only, no walking, so the flood sees the live object map (NPC
-- soldiers block tiles) exactly as it stands in that fixture.
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
          local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
          for _, d in ipairs(MOVES) do
            if H.canStep(x, y, d) then
              local nx, ny = (x + DELTA[d][1]) & xm, (y + DELTA[d][2]) & ym
              local k = ny * 256 + nx
              if not seen[k] then
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
  { 46, 39, "S", "-> 86 (49,54), the save pocket's way in" },
  { 46, 40, "1", "the tile under that door" },
  { 46, 41, "s", "<- 86 (49,55) comes back here" },
  { 45, 40, "2", "west of the tile under the door" },
  { 47, 40, "3", "east of the tile under the door" },
  { 46, 42, "4", "two under the door" },
  { 48, 37, "E", "-> 86 (52,29), the escape's door" },
  { 48, 36, "e", "the escape's landing from 86 (52,27)" },
  { 56, 34, "X", "the escape's town exit to the world" },
  { 22, 14, "a", "-> 86 (8,27)" },
  { 34, 35, "b", "-> 86 (4,6)" },
  { 37, 40, "c", "-> 86 (36,22)" },
  { 22, 42, "d", "-> map 78 (26,52)" },
  { 15, 37, "f", "-> map 76 (52,14)" },
  { 44, 30, "g", "-> map 85 (104,57)" },
  { 15, 18, "h", "-> map 81 (4,16)" },
  { 23, 15, "i", "-> map 81 (16,15)" },
  { 30, 42, "!", "the gate soldier's choke" },
}

H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/sfigaro_town.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[probe] boot map=%d (%d,%d)", map(),
      H.fieldX(), H.fieldY()))
    H.assertEq(map(), 75, "sfigaro_town is on map 75")
    for i = 16, 31 do
      local x = H.readWord(0x086a + 0x29 * i) >> 4
      local y = H.readWord(0x086d + 0x29 * i) >> 4
      H.log(string.format("  obj %2d at (%3d,%3d)", i, x, y))
    end
  end),
  flood("occupied town 75 from the fixture", MARKS),
  H.call(function()
    H.log("tilemap/property bytes around the (46,39) door "
      .. "(CheckDoor only opens $15/$17/$1C):")
    for y = 37, 43 do
      local row = {}
      for x = 43, 50 do
        row[#row + 1] = string.format("(%d,%d)=$%02X/p1=$%02X", x, y,
          H.maptile(x, y), H.readByte(0x7E7600 + H.maptile(x, y)))
      end
      H.log("  " .. table.concat(row, " "))
    end
  end),
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
