-- probe_banquet_interior.lua -- I->J leg development (issue #31): map
-- 250's interior topology, measured live from the banquet_250_entry
-- savestate (probe_banquet_stage.lua).  The offline stair/door tables
-- (banquet-decode §3) name the pairs but not the walk components; run 7's
-- census showed the entrance is a 3-tile pocket whose {22,29} doorway the
-- BFS model reads as a wall (door tiles) -- crossings here are held
-- presses, components are censused between crossings.
--
--   tools/tests/run.sh tools/tests/probe_banquet_interior.lua
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

local KEY = {
  { 54, 17, "dais south" }, { 54, 16, "dais trigger" },
  { 21, 24, "hall SW soldier" }, { 25, 24, "hall SE soldier" },
  { 21, 18, "hall NW soldier" }, { 25, 18, "hall NE soldier" },
  { 23, 12, "messenger tile" }, { 23, 9, "stairs (23,9)" },
  { 15, 21, "stairs (15,21)" }, { 31, 21, "stairs (31,21)" },
  { 37, 14, "stairs (37,14)" }, { 37, 9, "stairs (37,9)" },
  { 9, 9, "stairs (9,9)" }, { 9, 14, "252W door (9,14)" },
  { 53, 11, "251 exit landing" }, { 52, 13, "dais servant W" },
  { 24, 52, "stairs low (24,52)" }, { 9, 49, "low soldier (9,49)" },
  { 9, 52, "244 door (9,52)" }, { 51, 50, "low soldier (51,50)" },
  { 51, 53, "252E door (51,53)" }, { 65, 52, "244C exit landing" },
  { 98, 51, "low E soldier" }, { 110, 51, "low E fight" },
  { 97, 47, "stairs (97,47)" }, { 115, 22, "stairs (115,22)" },
  { 115, 16, "up E soldier" }, { 120, 13, "up E soldier2" },
  { 101, 16, "stairs (101,16)" }, { 101, 10, "stairs (101,10)" },
  { 120, 23, "stairs (120,23)" }, { 60, 61, "stairs (60,61)" },
  { 14, 60, "stairs (14,60)" }, { 81, 59, "stairs (81,59)" },
  { 22, 34, "exit door row (22,34)" }, { 23, 33, "entry landing" },
}

-- ASCII component dump: flood from the party over H.canStep (all eight
-- moves) and print the rows that contain component tiles -- the live map,
-- as the walker sees it.  '#'=in component, '.'=not.
local function floodDump(tag)
  return H.call(function()
    local MOVES = { "up", "right", "down", "left",
                    "upright", "downright", "downleft", "upleft" }
    local D = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 },
                left = { -1, 0 }, upright = { 1, -1 },
                downright = { 1, 1 }, downleft = { -1, 1 },
                upleft = { -1, -1 } }
    local sx, sy = H.fieldX(), H.fieldY()
    local seen = { [sy * 256 + sx] = true }
    local q, qi = { { sx, sy } }, 1
    while qi <= #q and #q < 4000 do
      local x, y = q[qi][1], q[qi][2]
      qi = qi + 1
      for _, m in ipairs(MOVES) do
        if H.canStep(x, y, m) then
          local nx, ny = x + D[m][1], y + D[m][2]
          local k = ny * 256 + nx
          if not seen[k] then
            seen[k] = true
            q[#q + 1] = { nx, ny }
          end
        end
      end
    end
    local minx, maxx, miny, maxy = 999, 0, 999, 0
    for k in pairs(seen) do
      local y, x = k >> 8, k & 0xFF
      if x < minx then minx = x end
      if x > maxx then maxx = x end
      if y < miny then miny = y end
      if y > maxy then maxy = y end
    end
    H.log(string.format("== flood [%s] from (%d,%d): %d tiles, x %d..%d y %d..%d ==",
      tag, sx, sy, #q, minx, maxx, miny, maxy))
    for y = miny, maxy do
      local row = {}
      for x = minx, maxx do
        row[#row + 1] = seen[y * 256 + x] and "#" or "."
      end
      H.log(string.format("[%s] y=%3d x%3d| %s", tag, y, minx,
        table.concat(row)))
    end
  end)
end

local function census(tag)
  return H.call(function()
    H.log(string.format("== census [%s] from (%d,%d) map=%d ==",
      tag, H.fieldX(), H.fieldY(), map()))
    for _, t in ipairs(KEY) do
      local p = H.bfsPath(t[1], t[2])
      if p then
        H.log(string.format("[%s] (%3d,%3d) %-22s reach %d",
          tag, t[1], t[2], t[3], #p))
      end
    end
  end)
end

local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        killBitAll(); H.setPad(ph < 4 and { "a" } or {}); return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

-- one door-sweep: stand at (sx,sy), hold `dir` 240 frames, log the result
local function sweep(sx, sy, dir)
  local tag = string.format("(%d,%d)%s", sx, sy, dir)
  local seq = {
    H.navTo(sx, sy, { maxFrames = 4000, calmFrames = 4 }),
    (function() local n = 0
      return H.driveUntil(function()
        n = n + 1
        return n >= 240
          or math.abs(H.fieldX() - sx) + math.abs(H.fieldY() - sy) >= 2
      end, 400, {
        H.call(function()
          if H.dialogWaiting() then H.setPad(n % 8 < 4 and { "a" } or {})
          else H.setPad({ [dir] = true }) end
        end),
      }, "sweep " .. tag)
    end)(),
    H.call(function()
      H.setPad({})
      H.log(string.format("[sweep] %s -> (%d,%d)", tag,
        H.fieldX(), H.fieldY()))
    end),
    H.waitFrames(20),
  }
  local i = 0
  return {
    tick = function(self)
      i = i == 0 and 1 or i
      while i <= #seq do
        local ok, r = pcall(function() return seq[i]:tick() end)
        if not ok then
          H.log(string.format("[sweep] %s ABORTED: %s", tag, tostring(r)))
          i = #seq + 1
          return "done"
        end
        if r == "frame" then return "frame" end
        i = i + 1
      end
      return "done"
    end,
    reset = function(self) i = 0 end,
  }
end

-- sweeps can strand the party in a new component; walk back toward the
-- corridor center (23,27) best-effort so the next sweep can navTo.  A
-- failed walk-back is fine -- the sweep after it just logs a nav error.
local function sweepBack()
  local nav = nil
  return {
    tick = function(self)
      nav = nav or H.navTo(23, 27, { maxFrames = 4000, calmFrames = 4 })
      local ok, r = pcall(function() return nav:tick() end)
      if not ok then return "done" end   -- unreachable: stay put
      return r
    end,
    reset = function(self) nav = nil end,
  }
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/banquet_250_entry.mss.lua"),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(map(), 250, "booted on 250")
    H.log(string.format("[boot] (%d,%d) $013B=%d", H.fieldX(), H.fieldY(),
      sw(0x013B)))
  end),
  census("entry"),

  -- cross the {22,29} doorway with a held UP press
  H.navTo(23, 30, { maxFrames = 3000 }),
  pressWalk("up", function()
    return H.fieldY() <= 28 and H.tileAligned()
  end, 900, "held UP through the {22,29} doorway"),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[door] now at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("bq_interior_above_door")
  end),
  census("above-door"),
  floodDump("corridor"),

  -- the hall soldiers' own tiles are OBJECT-BLOCKED (they stand on them);
  -- probe their adjacents instead
  H.call(function()
    local adj = {
      { 22, 24 }, { 24, 24 }, { 21, 23 }, { 21, 25 },
      { 24, 18 }, { 26, 18 }, { 25, 17 }, { 25, 19 },
      { 22, 18 }, { 20, 18 }, { 21, 17 }, { 21, 19 },
      { 26, 24 }, { 25, 23 }, { 25, 25 },
    }
    for _, t in ipairs(adj) do
      local p = H.bfsPath(t[1], t[2])
      if p then
        H.log(string.format("[hall-adj] (%d,%d) reach %d", t[1], t[2], #p))
      end
    end
  end),

  -- DOOR SWEEP: candidate tiles where a held press might cross a door
  -- tile the BFS model reads as a wall (the {22,29} class).  Each probe:
  -- navTo the stand tile, hold the direction 240 frames, log where the
  -- party ended.  A sweep that breaks into a new component floods it.
  -- raw per-tile map dump: p1 (prop byte) wall test only, no
  -- connectivity, no object map -- shows every room and door tile.
  -- '#' = p1&7 ~= 7 (not a counter/wall), '.' = wall, digits = the low
  -- exit nibble of p2 for tiles beside suspected doors.
  H.call(function()
    -- per tile: '.' = no exit bits (solid), 'X' = counter/wall (p1&7==7),
    -- 'o' = all four exits (plain floor), else the hex exit nibble
    -- (partial exits = doors/one-way lips)
    for y = 0, 63 do
      local row = {}
      for x = 0, 127 do
        local id = H.maptile(x, y)
        local p1 = H.readByte(0x7600 + id)
        local p2 = H.readByte(0x7700 + id) & 0x0F
        local c
        if (p1 & 7) == 7 then c = "X"
        elseif p2 == 0 then c = "."
        elseif p2 == 0x0F then c = "o"
        else c = string.format("%X", p2) end
        row[#row + 1] = c
      end
      H.log(string.format("[raw] y=%2d %s", y, table.concat(row)))
    end
  end),
})
