-- probe_m88_save.lua -- #218: the South Figaro mansion-basement save point
-- that IS on the escape route.
--
-- event_trigger.asm puts a SavePoint on map 84 at (53,57) -- the tile
-- gen_tunnelarmr aims at -- and another on map 88 at (11,34).  Map 88 has
-- exactly one door, 88 (11,37) -> 83 (40,14), with 83 (40,12) -> 88 (11,36)
-- coming the other way, and 83 (40,12) sits on the very corridor the escape
-- already walks between the same-map warp at (35,14) and the map-84 door at
-- (45,12).  Map 84's (53,57) is in a pocket of map 84 reached only from map
-- 86 (57,57), which is in a pocket of map 86 reached only from the occupied
-- town's (46,40) door, in a quarter the escape's landing cannot reach
-- (probe_basement_save, ...save2, ...save3, probe_m86_pockets,
-- probe_m75_pockets).
--
-- This boots celes_freed, takes the corridor warp the generator takes, and
-- measures: is 83 (40,12) reachable from the corridor landing, does it lead
-- to map 88, and does the party stand on a tile where $01BF (the save-point
-- control flag) reads set.  Read-only: no save is taken here.
-- @manual
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function seq(steps) return H.cond(function() return true end, steps) end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end

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
        tag, map(), sx, sy))
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
        H.log(string.format("   %s (%d,%d) %-30s %s", m[3], m[1], m[2], m[4],
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
      H.log(string.format("  H.bfsPath map %d from (%d,%d) -> (%2d,%2d) %-28s %s",
        map(), H.fieldX(), H.fieldY(), p[1], p[2], p[3],
        q and (#q .. " steps") or "NO PATH (nil)"))
    end)
    steps[#steps + 1] = H.waitFrames(1)
  end
  return seq(steps)
end

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
    end), maxF or 12000, { playBattles = "tactical" }),
    H.waitFrames(30),
  })
end

local DIAGSTAGE = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { -1, 1, "upright" }, { -1, -1, "downright" },
  { 1, -1, "downleft" }, { 1, 1, "upleft" },
}
local aPhase = 0
local function go(sx, sy, dm, dx, dy, what)
  local pick, startMap
  local function arrived()
    if dm ~= startMap then return map() ~= startMap end
    return H.fieldX() == dx and H.fieldY() == dy
  end
  local pickAt = -1000
  local function stage()
    if pick == nil or (H.frame - pickAt >= 90 and not arrived()) then
      pickAt = H.frame
      local fresh
      if H.bfsPath(sx, sy) then
        fresh = { sx, sy, nil }
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
      { maxFrames = 40000, arrive = arrived, playBattles = "tactical" }),
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

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/celes_freed.mss.lua"),
  H.waitFrames(60),
  go(57, 13, 83, 35, 14, "celes room -> corridor"),
  H.call(function()
    H.log(string.format("[probe] on the corridor at (%d,%d)",
      H.fieldX(), H.fieldY()))
  end),
  askBfs({
    { 40, 12, "-> map 88 (11,36)" },
    { 40, 13, "under that door" },
    { 40, 14, "where 88 (11,37) returns" },
    { 45, 12, "-> map 84 (8,57)" },
  }),
  flood("map 83 corridor from (35,14)", {
    { 40, 12, "S", "-> map 88 (11,36)" },
    { 45, 12, "C", "-> map 84 (8,57), the clock map" },
    { 40, 14, "r", "where 88 (11,37) returns" },
  }),
  go(40, 12, 88, 11, 36, "corridor (40,12) -> map 88 (11,36)"),
  H.call(function()
    H.log(string.format("[probe] map 88 at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("m88_arrival")
  end),
  askBfs({ { 11, 34, "the SavePoint trigger" } }),
  flood("map 88 from (11,36)", {
    { 11, 34, "S", "the SavePoint trigger" },
    { 11, 37, "O", "-> map 83 (40,14)" },
  }),
  H.navTo(11, 34, { maxFrames = 8000, playBattles = "tactical" }),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[probe] standing on (%d,%d) map %d: $01BF=%d ($1EB7=$%02X)",
      H.fieldX(), H.fieldY(), map(), sw(0x01BF), H.readByte(0x1EB7)))
    H.assertEq((H.readByte(0x1EB7) & 0x80) ~= 0, true,
      "$01BF SET -- map 88 (11,34) really is a save point")
    H.screenshot("m88_on_savepoint")
  end),
  go(11, 37, 83, 40, 14, "map 88 (11,37) -> corridor 83 (40,14)"),
  askBfs({ { 45, 12, "-> map 84 (8,57), from the return tile" } }),
  H.call(function()
    H.log(string.format("[probe] back on the corridor at (%d,%d) map %d",
      H.fieldX(), H.fieldY(), map()))
    H.screenshot("m88_back_on_corridor")
  end),
})
