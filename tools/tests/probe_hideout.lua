-- probe_hideout.lua -- what the party can actually reach inside the RETURNER
-- HIDEOUT, measured rather than read off the entrance table.
--
-- gen_banon's first cut planned map 109 (9,29) -> (25,15) straight off
-- ShortEntrance::_109 and got "no path" -- the same way gen_kolts's first cut
-- planned Mt. Kolts off its table.  Two things turned out to be true and
-- neither is in any table:
--   * the greeter NPC at map 109 (9,25) is a WALL.  The arrival vestibule
--     reaches exactly one tile besides itself, (9,26), which is the tile
--     directly under him.  Talking to him runs the escort (_caf68a,
--     event_main.asm:36275) which walks the party to (22,21) and opens the
--     map -- the same shape as map 71's Figaro guards.
--   * both 109 and 110 are PARTITIONED, so "the map has a door to X" says
--     nothing about whether this end of it can get there.
-- So this floods the engine's own passability model from wherever the party
-- is standing, ~200 nodes per frame (a whole flood in one Lua slice is what
-- gen_kolts warns trips Mesen's script watchdog silently), and prints the
-- reachable set as a map.  '@' party, '.' reachable, ' ' not.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/returner_hideout.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function seq(steps) return H.cond(function() return true end, steps) end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end

local MOVES = { "up", "down", "left", "right",
                "upleft", "upright", "downleft", "downright" }
local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 },
                right = { 1, 0 }, upleft = { -1, -1 }, upright = { 1, -1 },
                downleft = { -1, 1 }, downright = { 1, 1 } }

-- Flood from the party's tile, budgeted per frame, then print the region.
-- `marks` labels interesting tiles inside the dump so the answer is legible
-- without cross-referencing coordinates by hand.
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
    H.driveUntil(function() return done end, 6000, {
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
              if not seen[k] and nx >= 0 and ny >= 0 and nx < 128 and ny < 128 then
                seen[k] = true
                q[#q + 1] = { nx, ny }
              end
            end
          end
        end
        if qi > #q or #q > 4000 then done = true end
      end),
    }, "flood " .. tag),
    H.call(function()
      local minx, miny, maxx, maxy = 999, 999, -1, -1
      local n = 0
      for k in pairs(seen) do
        local x, y = k % 256, k // 256
        n = n + 1
        if x < minx then minx = x end
        if x > maxx then maxx = x end
        if y < miny then miny = y end
        if y > maxy then maxy = y end
      end
      H.log(string.format("%s: %d tiles, bbox (%d,%d)-(%d,%d)",
        tag, n, minx, miny, maxx, maxy))
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
      -- and say, for each mark, whether it is in the region
      for _, m in ipairs(marks or {}) do
        H.log(string.format("   %s (%d,%d) %-28s %s", m[3], m[1], m[2], m[4],
          seen[m[2] * 256 + m[1]] and "REACHABLE" or "not reachable"))
      end
    end),
  })
end

local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end
local function settleField(dstMap)
  return seq({
    H.waitFrames(90),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), 12000),
    H.waitFrames(30),
  })
end

local function talkAt(nx, ny, sx, sy, dir, what)
  local FACE = { up = 0, right = 1, down = 2, left = 3 }
  local aPh, started = 0, 0
  return seq({
    H.navTo(sx, sy, { maxFrames = 12000 }),
    H.release(),
    H.driveUntil(function()
      started = (H.eventRunning() or H.dialogWaiting()) and started + 1 or 0
      return started >= 4
    end, 9000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        if H.readByte(0x087f + H.readWord(0x0803)) ~= FACE[dir] then
          H.setPad({ [dir] = true }); return
        end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, what),
    H.release(),
  })
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  flood("108 entry hall", {
    { 10, 48, "D", "-> map 109" },
    { 14, 49, "B", "BANON's later tile" },
  }),

  H.navTo(10, 48, { maxFrames = 20000,
    arrive = function() return map() ~= 108 end }),
  H.release(),
  settleField(109),
  flood("109 vestibule (before the greeter)", {
    { 9, 25, "G", "the greeter" },
  }),

  talkAt(9, 25, 9, 26, "up", "engage the greeter"),
  H.advanceStory(function()
    return map() == 109 and H.hasControl() and H.tileAligned()
       and bright() >= 15
  end, 20000),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("after the escort: (%d,%d) $01F0=%d $01F1=%d " ..
      "$01F2=%d $031D=%d", H.fieldX(), H.fieldY(),
      sw(0x01F0), sw(0x01F1), sw(0x01F2), sw(0x031D)))
  end),
  flood("109 after the escort", {
    { 11,  8, "A", "door A -> 110 (44,27)" },
    { 14, 17, "B", "door B -> 110 (22,53)" },
    { 25, 15, "C", "door C -> 110 (42,44)" },
    { 22, 34, "E", "-> map 111" },
    { 26, 28, "S", "SABIN's later tile" },
    {  9, 30, "D", "-> map 108" },
    { 25, 23, "P", "the paper trigger" },
  }),

  -- WHO is standing where, and what exactly walls off the upper half
  H.call(function()
    H.log("map 109 objects and spawn switches:")
    local SWI = { [16] = 0x0413, [17] = 0x0414, [18] = 0x0415, [19] = 0x0416,
                  [20] = 0x0417, [21] = 0x0418, [22] = 0x0419, [23] = 0x041A,
                  [24] = 0x041B, [25] = 0x041C, [26] = 0x043A }
    for i = 16, 26 do
      H.log(string.format("  obj %2d at (%3d,%3d)  $%04X=%d", i,
        H.readWord(0x086a + 0x29 * i) >> 4,
        H.readWord(0x086d + 0x29 * i) >> 4, SWI[i], sw(SWI[i])))
    end
  end),
  (function()
    -- one z-correct bfsPath per frame (H.bfsPath tracks the carried z-level;
    -- the flood above uses the LIVE z for every tile and is only a sketch)
    local pts = {
      { 11, 16, "under the (11,15) NPC" }, { 11, 15, "the (11,15) NPC tile" },
      { 11, 14, "north of him" },          { 10, 15, "west of him" },
      { 12, 15, "east of him" },           { 14, 16, "north of door B" },
      { 14, 15, "two north of door B" },   { 24, 17, "east arm" },
      { 24, 16, "north of the east arm" }, { 25, 16, "under door C" },
      { 25, 17, "under-under door C" },    { 23, 16, "west of that" },
      { 12, 16, "top of the west arm" },   { 10, 16, "top of the west arm w" },
    }
    local steps = {}
    for _, p in ipairs(pts) do
      steps[#steps + 1] = H.call(function()
        local q = H.bfsPath(p[1], p[2])
        H.log(string.format("  chokepoint (%2d,%2d) %-26s %s",
          p[1], p[2], p[3], q and (#q .. " steps") or "NO PATH"))
      end)
      steps[#steps + 1] = H.waitFrames(1)
    end
    return seq(steps)
  end)(),

  -- DOOR C (25,15) is a door TILE -- a wall until CheckDoor swaps it open
  -- for a party pressing into it (player.asm:959), which is why bfsPath says
  -- NO PATH to it while (25,16) directly under it is 8 steps away.  So it is
  -- crossed gen_edgar-style: stage on the neighbour, then HOLD into it.
  H.navTo(25, 16, { maxFrames = 20000 }),
  H.release(),
  (function()
    local aPh = 0
    return H.driveUntil(function() return map() ~= 109 end, 1800, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.dialogWaiting() then H.setPad(aPh < 4 and { "a" } or {}); return end
        H.setPad({ up = true })
      end),
    }, "hold UP into door C")
  end)(),
  H.release(),
  settleField(110),
  H.call(function()
    H.log(string.format("map 110 NPC switches: $041D(BANON)=%d $041E=%d " ..
      "$041F(EDGAR)=%d $0420(LOCKE)=%d $0423=%d $0424=%d $0497=%d",
      sw(0x041D), sw(0x041E), sw(0x041F), sw(0x0420), sw(0x0423),
      sw(0x0424), sw(0x0497)))
    for i = 16, 23 do
      H.log(string.format("  obj %d at (%d,%d)", i,
        H.readWord(0x086a + 0x29 * i) >> 4, H.readWord(0x086d + 0x29 * i) >> 4))
    end
  end),
  flood("110 from door B", {
    { 51, 50, "N", "BANON $041d" },
    { 52, 48, "E", "EDGAR's later tile" },
    { 27, 48, "L", "LOCKE's later tile" },
    { 21, 48, "S", "where the speech parks the party" },
    { 50, 54, "R", "-> map 112, the river" },
    { 44, 28, "1", "-> map 109 (11,10)" },
    { 42, 45, "2", "-> map 109 (25,16)" },
    { 22, 54, "3", "-> map 109 (14,18)" },
    { 50, 39, "V", "the save point" },
    { 27, 50, "I", "_cb0412 invasion trigger" },
  }),
})
