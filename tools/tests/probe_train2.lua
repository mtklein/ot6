-- probe_train2.lua -- mainline drive instrument: forest_done -> the DETACH.
-- Rides the route probe_train measured open: departure, car A west door,
-- strip (66,8)->(58,8) into car B ($017E=1), across B to (50,8), the strip
-- to car C's side door (41,8) facing up ($0180=1, $0509=1), the trap ghost
-- talk (_cbb265: $017C=1, battle 47 -- REAL WIN, its tail is _ca5ea9's
-- win-bit check), the mob scene at 142 (41,9), the roof climb at x=40
-- (_cbb3e6), the run west to (34,5) (_cbb4d5, SABIN's jump), the mob catch
-- at (11,8) ($0182), car 149, the interior ladder x=26, and the roof lever
-- (28,5) facing-up+A (_cbb645: $0183=1, cinematic -> 141 (117,8)).
-- Floods each new pocket so a blocked step names itself.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/forest_done.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local function inBattle()
  for i = 0, 3 do
    local hp = H.readWord(0x3bf4 + i * 2)
    if hp == 0xFFFF or hp == 0 then
    elseif hp < 10000 then return true
    else return false end
  end
  return false
end

local function swDump(tag)
  H.log(string.format(
    "[%s] map=%d (%d,%d) $0039=%d $017C=%d $017D=%d $017E=%d $017F=%d "..
    "$0180=%d $0182=%d $0183=%d $0506=%d $0507=%d $0509=%d",
    tag, mapIdx(), H.fieldX(), H.fieldY(), sw(0x39), sw(0x17C), sw(0x17D),
    sw(0x17E), sw(0x17F), sw(0x180), sw(0x182), sw(0x183), sw(0x506),
    sw(0x507), sw(0x509)))
end

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
        if not seen[k] then seen[k] = true; q[#q + 1] = { x + d[1], y + d[2] } end
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
        if a then runs[#runs + 1] = (a == b) and tostring(a) or (a.."-"..b) end
        a, b = x, x
      end
    end
    if a then runs[#runs + 1] = (a == b) and tostring(a) or (a.."-"..b) end
    H.log(string.format("  y=%2d: x=%s", y, table.concat(runs, ",")))
  end
end

-- flap-tolerant hold; tap-A dialogs; battles get REAL tap-A wins (the train's
-- scripted fights all tail into _ca5ea9's win-bit check -- kill-bit would
-- GameOver), EXCEPT pure random trash when spareReal is false.  On the train
-- every fight ends up tap-A: cheap, and uniformly safe.
local function holdDrive(dir, pred, what, budget)
  local phase, hb = 0, -600
  return H.driveUntil(pred, budget or 15000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 600 then
        hb = H.frame
        H.log(string.format("drive[%s] f%d map=%d (%d,%d) ctl=%s dlg=%s b=%s",
          what, H.frame, mapIdx(), H.fieldX(), H.fieldY(),
          tostring(H.hasControl()), tostring(H.dialogWaiting()),
          tostring(inBattle())))
      end
      if inBattle() or H.battleLoadStarted() then
        H.setPad(phase < 4 and { "a" } or {}); return
      end
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

local function settle(toMap, what)
  return H.cond(function() return true end, {
    H.waitUntil(function()
      return mapIdx() == toMap and H.hasControl() and H.tileAligned()
         and bright() >= 15
    end, 4000, what, 5),
    H.waitFrames(20),
    H.call(function() swDump(what) end),
  }, {})
end

H.run({ maxFrames = 120000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function() swDump("start") end),

  -- departure, then car A's west door
  holdDrive("down", function() return sw(0x39) == 1 end, "departure", 6000),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
  end, 4000, "post-departure", 5),
  H.navTo(2, 7, { maxFrames = 12000 }),
  holdDrive("left", function() return mapIdx() == 142 end, "A west exit", 4000),
  settle(142, "west pocket (66,8)"),

  -- strip west to (58,8) -> car B
  holdDrive("left", function() return mapIdx() == 145 end, "-> car B", 4000),
  settle(145, "car B east (29,7)"),
  H.call(function()
    H.assertEq(sw(0x17E), 1, "$017E set -- this 145 is car B")
  end),

  -- across car B, out the west door
  H.navTo(2, 7, { maxFrames = 12000 }),
  holdDrive("left", function() return mapIdx() == 142 end, "B west exit", 4000),
  settle(142, "pocket (50,8)"),
  H.call(function() flood("west of car B") end),

  -- strip to (41,8), then face UP into car C's side door
  H.navTo(41, 8, { maxFrames = 8000, arrive = function()
    return mapIdx() == 145 or (H.fieldX() == 41 and H.fieldY() == 8
       and H.hasControl() and H.tileAligned()) end }),
  holdDrive("up", function() return mapIdx() == 145 and sw(0x180) == 1 end,
    "-> car C", 4000),
  settle(145, "car C south door (26,10)"),
  H.call(function()
    H.assertEq(sw(0x509), 1, "$0509 set -- car C's ghost cast")
  end),

  -- step up to (26,8): _cbb399 relocates the trap ghost to (26,11)->(26,10)
  holdDrive("up", function()
    return sw(0x3D) == 1 and H.hasControl() and H.tileAligned()
  end, "bait the follower ghost", 4000),
  H.call(function() swDump("ghost baited") end),

  -- walk down to (26,9), face the ghost at (26,10), talk: _cbb265
  -- ($017C=1, battle 47 REAL, mob scene -> 142 (41,9) pocket)
  H.navTo(26, 9, { maxFrames = 3000 }),
  (function()
    local phase = 0
    return H.driveUntil(function() return sw(0x17C) == 1 end, 3000, {
      H.call(function()
        phase = (phase + 1) % 8
        -- face down (ghost below), edge-tap A
        H.setPad(phase < 4 and { "down", "a" } or { "down" })
      end),
    }, "talk to the trap ghost")
  end)(),
  holdDrive("down", function()
    return mapIdx() == 142 and H.hasControl() and H.tileAligned()
       and not inBattle() and bright() >= 15
  end, "battle 47 + mob scene", 30000),
  H.call(function()
    swDump("mob pocket")
    flood("mob pocket (41,9)")
  end),

  -- roof: climb at x=40 (the (40,6) trigger fires the roof-mob beat)
  H.navTo(40, 8, { maxFrames = 4000 }),
  holdDrive("up", function()
    return H.fieldY() <= 6 and H.hasControl() and H.tileAligned()
  end, "climb to the roof", 15000),
  H.call(function() swDump("roof") ; flood("roof at x=40") end),

  -- west along the roof to (34,5): _cbb4d5, SABIN's jump (auto, dialogs)
  holdDrive("up", function()
    return H.fieldY() == 5 and H.hasControl() and H.tileAligned()
  end, "top of roof", 4000),
  holdDrive("left", function()
    return H.fieldX() <= 13 and H.hasControl() and H.tileAligned()
  end, "jump scene west", 30000),
  H.call(function() swDump("landed") ; flood("post-jump") end),

  -- (11,8) mob catch ($0182), then (10,8) -> car 149
  holdDrive("down", function()
    return H.fieldY() >= 8 and H.hasControl() and H.tileAligned()
  end, "down to the strip", 6000),
  holdDrive("left", function() return mapIdx() == 149 end,
    "mob catch + into 149", 30000),
  settle(149, "car 149 east (30,7)"),
  H.call(function() flood("car 149") end),

  -- the east vestibule climbs inside: (28,5) is directly reachable
  -- (measured: 149's flood from (30,7) is x=27..31, y=5..10 -- the ladder
  -- column x=26 the exterior implies is NOT the way; the lever tile is).
  H.navTo(28, 5, { maxFrames = 6000 }),
  (function()
    local phase = 0
    return H.driveUntil(function() return sw(0x183) == 1 end, 3000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(phase < 4 and { "up", "a" } or { "up" })
      end),
    }, "pull the detach lever")
  end)(),
  holdDrive("down", function()
    return mapIdx() == 141 and H.hasControl() and H.tileAligned()
       and bright() >= 15
  end, "detach cinematic", 30000),
  H.call(function()
    swDump("DETACHED -- on the 141 strip")
    flood("141 after detach")
    H.screenshot("ptrain2_detached")
    H.assertEq(mapIdx(), 141, "on map 141")
    H.assertEq(sw(0x183), 1, "$0183 set -- rear cars detached")
    H.assertEq(sw(0x180), 0, "$0180 cleared by the detach")
  end),
})
