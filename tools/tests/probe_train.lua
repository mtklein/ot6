-- probe_train.lua -- recon instrument for the Phantom Train door maze.
-- Boots forest_done (map 145 (26,8), pre-departure), fires the departure
-- (step DOWN onto (26,10) -> _cbaa26 -> $0039=1), exits car A through the
-- EAST door ((30,7) facing right -> _cba76c -> 142 (75,8) on a fresh board),
-- and BFS-FLOODS the exterior strip from the landing over the live
-- passability model (H.canStep's stepAllowed on $7E7600/$7E7700), dumping
-- every reachable tile plus the verdict on each named door tile.  Then walks
-- back into car A, out the WEST door ((1,7) facing left -> _cba77f -> 142
-- (66,8)), and floods again.  Pure measurement: no ghost talk, no switches
-- flipped beyond what the walk itself fires.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/forest_done.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end

local function swDump(tag)
  H.log(string.format(
    "[%s] map=%d (%d,%d) $0037=%d $0038=%d $0039=%d $003A=%d $003D=%d "..
    "$017C=%d $017D=%d $017E=%d $017F=%d $0180=%d $0182=%d $0183=%d "..
    "$0501=%d $0506=%d $0507=%d $0508=%d $0509=%d $0567=%d",
    tag, mapIdx(), H.fieldX(), H.fieldY(), sw(0x37), sw(0x38), sw(0x39),
    sw(0x3A), sw(0x3D), sw(0x17C), sw(0x17D), sw(0x17E), sw(0x17F),
    sw(0x180), sw(0x182), sw(0x183), sw(0x501), sw(0x506), sw(0x507),
    sw(0x508), sw(0x509), sw(0x567)))
end

-- flood-fill the passability graph from the party's tile (bfsPath's edge
-- relation, no target), and report reachability compactly: per-row x RLE.
local MOVES = { "up", "down", "left", "right",
                "upleft", "upright", "downleft", "downright" }
local DELTA = { up = {0,-1}, down = {0,1}, left = {-1,0}, right = {1,0},
                upleft = {-1,-1}, upright = {1,-1},
                downleft = {-1,1}, downright = {1,1} }
local function flood(tag)
  local sx, sy = H.fieldX(), H.fieldY()
  local seen = { [sy * 256 + sx] = true }
  local q, qi = { { sx, sy } }, 1
  while qi <= #q and qi <= 4096 do
    local x, y = q[qi][1], q[qi][2]
    qi = qi + 1
    for _, dir in ipairs(MOVES) do
      if H.canStep(x, y, dir) then
        local d = DELTA[dir]
        local k = (y + d[2]) * 256 + (x + d[1])
        if not seen[k] then
          seen[k] = true
          q[#q + 1] = { x + d[1], y + d[2] }
        end
      end
    end
  end
  local rows = {}
  for k in pairs(seen) do
    local y, x = k >> 8, k & 0xFF
    rows[y] = rows[y] or {}
    rows[y][#rows[y] + 1] = x
  end
  local ys = {}
  for y in pairs(rows) do ys[#ys + 1] = y end
  table.sort(ys)
  H.log(string.format("[flood %s] from (%d,%d): %d tiles", tag, sx, sy, #q))
  for _, y in ipairs(ys) do
    table.sort(rows[y])
    local runs, a, b = {}, nil, nil
    for _, x in ipairs(rows[y]) do
      if a and x == b + 1 then b = x
      else
        if a then runs[#runs + 1] = (a == b) and tostring(a)
                                    or (a .. "-" .. b) end
        a, b = x, x
      end
    end
    if a then runs[#runs + 1] = (a == b) and tostring(a) or (a .. "-" .. b) end
    H.log(string.format("  y=%2d: x=%s", y, table.concat(runs, ",")))
  end
  return seen
end

local function verdicts(seen, targets)
  for _, t in ipairs(targets) do
    local k = t[2] * 256 + t[1]
    H.log(string.format("  target (%d,%d) %-28s %s", t[1], t[2], t[3],
      seen[k] and "REACHABLE" or "no"))
  end
end

-- drive one direction persistently (flap-tolerant), tap-A through dialogs
-- and battles (kill-bit random trash during load), until pred.
local function holdDrive(dir, pred, what, budget)
  local phase, hb = 0, -600
  return H.driveUntil(pred, budget or 12000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 600 then
        hb = H.frame
        H.log(string.format("drive[%s] f%d map=%d (%d,%d) ctl=%s dlg=%s",
          what, H.frame, mapIdx(), H.fieldX(), H.fieldY(),
          tostring(H.hasControl()), tostring(H.dialogWaiting())))
      end
      if H.battleLoadStarted() then
        if H.monstersPresent() > 0 then
          for s = 0, 5 do
            if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
              H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
            end
          end
        end
        H.setPad(phase < 4 and { "a" } or {}); return
      end
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    swDump("start")
    H.assertEq(mapIdx(), 145, "boot on the train, map 145")
    H.assertEq(sw(0x39), 0, "$0039 clear -- not yet departed")
  end),

  -- fire the departure: step DOWN onto (26,10); ride _cbaa26 (dialogs)
  holdDrive("down", function() return sw(0x39) == 1 end, "departure", 6000),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
  end, 4000, "post-departure control", 5),
  H.waitFrames(30),
  H.call(function() swDump("departed") end),

  -- east door: navTo the interior tile beside it, then hold right through
  H.navTo(29, 7, { maxFrames = 8000 }),
  holdDrive("right", function() return mapIdx() == 142 end, "east exit", 4000),
  H.waitUntil(function()
    return mapIdx() == 142 and H.hasControl() and H.tileAligned()
       and bright() >= 15
  end, 3000, "142 settle", 5),
  H.waitFrames(30),
  H.call(function()
    swDump("east pocket")
    local seen = flood("east of car A")
    verdicts(seen, {
      { 83, 8, "-> 152 west door" }, { 85, 8, "-> 152 side door" },
      { 86, 8, "-> 152 east door" }, { 74, 8, "-> back into A east" },
      { 72, 8, "-> A side door" }, { 67, 8, "-> back into A west" },
      { 66, 8, "west pocket landing" }, { 58, 8, "-> car B east" },
      { 51, 8, "-> car B west" }, { 56, 5, "roof hatch drop" },
      { 55, 5, "roof hatch open" }, { 41, 8, "-> car C side" },
      { 34, 8, "C west pocket" }, { 11, 8, "mob scene" },
      { 10, 8, "-> car 149" },
    })
  end),

  -- back into car A ((74,8) facing left), out the WEST door, flood again
  holdDrive("left", function() return mapIdx() == 145 end, "re-enter A", 4000),
  H.waitUntil(function()
    return mapIdx() == 145 and H.hasControl() and H.tileAligned()
       and bright() >= 15
  end, 3000, "145 settle", 5),
  H.waitFrames(30),
  H.call(function() swDump("back in car A") end),
  H.navTo(2, 7, { maxFrames = 10000 }),
  holdDrive("left", function() return mapIdx() == 142 end, "west exit", 4000),
  H.waitUntil(function()
    return mapIdx() == 142 and H.hasControl() and H.tileAligned()
       and bright() >= 15
  end, 3000, "142 west settle", 5),
  H.waitFrames(30),
  H.call(function()
    swDump("west pocket")
    local seen = flood("west of car A")
    verdicts(seen, {
      { 58, 8, "-> car B east" }, { 51, 8, "-> car B west" },
      { 56, 5, "roof hatch drop" }, { 55, 5, "roof hatch open" },
      { 67, 8, "-> back into A west" }, { 41, 8, "-> car C side" },
    })
    H.screenshot("ptrain_west_pocket")
  end),
})
