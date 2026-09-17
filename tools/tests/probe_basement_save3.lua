-- probe_basement_save3.lua -- #218, fourth measurement: the way IN to the
-- map-84 save-point pocket.
--
-- Measured so far: map 84's SavePoint trigger (53,57) sits in a pocket the
-- escape's own map-84 pocket (82 tiles, bbox (5,49)-(22,58)) never touches,
-- and short_entrance.dat gives that pocket exactly one door, 86 (57,57) ->
-- 84 (56,55) / 84 (57,54) -> 86 (58,56).  Map 86 is itself cut into pockets
-- (14 tiles at the passage start, 20 at the escape's (49,31) landing), and
-- (57,57) is in neither.  The remaining door into map 86 near there is the
-- occupied town's own: 75 (46,39) -> 86 (49,54), with 86 (49,55) -> 75
-- (46,41) coming back (the _ca7ffa trigger on the same tile only fires
-- once $00A4 is set, i.e. after the liberation).
--
-- This walks the escape to the occupied town, takes that door, and measures
-- the pocket on the far side: is (57,57) in it, does it cross into map 84,
-- and does the party land on a tile where $01BF (the save-point control
-- flag) reads set.  Read-only.
--
-- EXPECTED RESULT: it FAILS at `go(46,39,...)` with "navTo: no path
-- (48,36)->(46,40)", and that failure is the measurement -- the occupied
-- town's quarters are walled off from each other, and the quarter the
-- escape lands in does not reach the (46,40) house door
-- (build/lab/218-basement-probe3.log, and probe_m75_pockets for the town's
-- own flood).  There is no way to the map-84 save point on this route,
-- which is why gen_tunnelarmr saves at map 88 (11,34) instead.
-- @manual
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/celes_freed.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function seq(steps) return H.cond(function() return true end, steps) end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end

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

local function askBfs(pts)
  local steps = {}
  for _, p in ipairs(pts) do
    steps[#steps + 1] = H.call(function()
      local q = H.bfsPath(p[1], p[2])
      H.log(string.format("  H.bfsPath map %d from (%d,%d) -> (%2d,%2d) %-30s %s",
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

local function windClock()
  local ph = 0
  return seq({
    H.navTo(18, 49, { maxFrames = 12000, playBattles = "tactical" }),
    H.release(),
    H.driveUntil(function() return sw(0x010D) == 1 end, 900, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        if facing() ~= 0 then H.setPad({ up = true }); return end
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, "wind the clock ($010D)"),
    H.release(),
    H.waitFrames(60),
  })
end

local M86 = {
  { 57, 57, "W", "-> map 84 (56,55), the save pocket" },
  { 58, 56, "w", "<- 84 (57,54) comes back here" },
  { 49, 54, "E", "arrival from town 75 (46,39)" },
  { 49, 55, "X", "-> town 75 (46,41)" },
}
local M84B = {
  { 53, 57, "S", "the SavePoint trigger" },
  { 56, 55, "I", "the arrival tile from 86 (57,57)" },
  { 57, 54, "O", "-> map 86 (58,56)" },
}

H.run({ maxFrames = 200000 }, {
  H.loadState(DOOR),
  H.waitFrames(60),
  go(57, 13, 83, 35, 14, "celes room -> corridor"),
  go(45, 12, 84, 8, 57, "corridor (45,12) -> map 84 (8,57)"),
  windClock(),
  go(15, 51, 87, 20, 33, "clock passage (15,51) -> map 87 (20,33)"),
  go(57, 48, 86, 49, 31, "map 87 (57,48) -> map 86 (49,31)"),
  go(52, 27, 75, 48, 36, "map 86 (52,27) -> occupied town 75 (48,36)"),
  H.call(function()
    H.log(string.format("[probe] town: (%d,%d) $00A4=%d", H.fieldX(),
      H.fieldY(), sw(0x00A4)))
    H.screenshot("basement3_town")
  end),
  askBfs({
    { 46, 39, "the house door 75 (46,39)" },
    { 46, 40, "under it" },
    { 46, 41, "two under it" },
    { 56, 34, "the escape's own town exit" },
  }),
  go(46, 39, 86, 49, 54, "town 75 (46,39) -> map 86 (49,54)"),
  H.call(function()
    H.log(string.format("[probe] through the house door: map=%d (%d,%d)",
      map(), H.fieldX(), H.fieldY()))
    H.screenshot("basement3_m86_house")
  end),
  askBfs({
    { 57, 57, "the map-84 door tile" },
    { 58, 56, "the return tile" },
    { 49, 55, "back out to town" },
  }),
  flood("map 86 from the town-house arrival (49,54)", M86),

  go(57, 57, 84, 56, 55, "map 86 (57,57) -> map 84 (56,55)"),
  H.call(function()
    H.log(string.format("[probe] save pocket: map=%d (%d,%d)",
      map(), H.fieldX(), H.fieldY()))
    H.screenshot("basement3_savepocket")
  end),
  askBfs({ { 53, 57, "the SavePoint trigger" } }),
  flood("map 84 save pocket from (56,55)", M84B),
  H.navTo(53, 57, { maxFrames = 12000, playBattles = "tactical" }),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[probe] standing on (%d,%d) map %d: $01BF=%d ($1EB7=$%02X)",
      H.fieldX(), H.fieldY(), map(), sw(0x01BF), H.readByte(0x1EB7)))
    H.screenshot("basement3_on_savepoint")
  end),
  -- and back out the way a player would leave
  go(57, 54, 86, 58, 56, "map 84 (57,54) -> map 86 (58,56)"),
  go(49, 55, 75, 46, 41, "map 86 (49,55) -> occupied town 75 (46,41)"),
  H.call(function()
    H.log(string.format("[probe] back in town at (%d,%d) map %d",
      H.fieldX(), H.fieldY(), map()))
    H.screenshot("basement3_back_in_town")
  end),
  askBfs({ { 56, 34, "the escape's town exit, from here" } }),
})
