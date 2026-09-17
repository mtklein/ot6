-- probe_basement_save2.lua -- #218, second measurement.  probe_basement_save
-- showed the map-84 pocket the escape lands in is 82 tiles wide and does not
-- contain the SavePoint trigger at (53,57) (event_trigger.asm
-- EventTrigger::_84).  short_entrance.dat says map 84 has exactly three
-- doors:
--     (15,51) -> map 87 (20,33)      the clock passage
--     ( 8,58) -> map 83 (45,14)      back up the way in
--     (57,54) -> map 86 (58,56)      <- and map 86 (57,57) -> 84 (56,55)
-- so the save-point room is a separate pocket of map 84 entered from map 86,
-- which the escape crosses AFTER the clock and map 87.  This walks the
-- generator's own route to the map-86 landing at (49,31) and measures
-- whether (57,57) is reachable from there, then crosses it and measures the
-- save-point pocket on the far side.  Read-only.
--
-- EXPECTED RESULT: it FAILS at the `go(57,57,...)` step, and that failure is
-- the measurement -- the map-86 pocket the escape lands in is 20 tiles, bbox
-- (48,27)-(53,33), and does not contain (57,57)
-- (build/lab/218-basement-probe2.log).
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
        H.log(string.format("   %s (%d,%d) %-32s %s%s", m[3], m[1], m[2], m[4],
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
      H.log(string.format("  H.bfsPath map %d from (%d,%d) -> (%2d,%2d) %-26s %s",
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
  { 49, 31, "L", "the landing from map 87" },
  { 52, 27, "T", "-> town 75 (48,36)" },
  { 48, 32, "8", "-> map 87 (56,49)" },
  { 52, 29, "S", "the why-are-you-helping-me scene" },
}
local M84B = {
  { 53, 57, "S", "the SavePoint trigger" },
  { 56, 55, "I", "the arrival tile from 86" },
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
  H.call(function()
    H.log(string.format("[probe] on map 86 at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("basement2_map86_landing")
  end),
  askBfs({
    { 57, 57, "the 84 door tile" },
    { 57, 56, "north of it" },
    { 56, 57, "west of it" },
    { 57, 58, "south of it" },
    { 52, 27, "the town door" },
  }),
  flood("map 86 from the (49,31) landing", M86),

  -- cross into the save pocket
  go(57, 57, 84, 56, 55, "map 86 (57,57) -> map 84 (56,55)"),
  H.call(function()
    H.log(string.format("[probe] save pocket: map=%d (%d,%d)",
      map(), H.fieldX(), H.fieldY()))
    H.screenshot("basement2_savepocket")
  end),
  askBfs({ { 53, 57, "the SavePoint trigger" } }),
  flood("map 84 save pocket from (56,55)", M84B),
  H.navTo(53, 57, { maxFrames = 12000, playBattles = "tactical" }),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[probe] standing on (%d,%d): $01BF=%d ($1EB7=$%02X)",
      H.fieldX(), H.fieldY(), sw(0x01BF), H.readByte(0x1EB7)))
    H.screenshot("basement2_on_savepoint")
  end),
})
