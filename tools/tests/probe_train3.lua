-- probe_train3.lua -- front-half instrument: the DETACH -> the smokestack ->
-- battle 68 battle-up, with the GhostTrain seed rows dumped.  Rides
-- probe_train2's proven rear half verbatim, then:
--   * re-enters 149 and pulls the lever a SECOND time ((28,5) facing-up+A,
--     _cbb7c7: $017F=1 + the x=26 inner-door mod -- the east vestibule is
--     walled off from the car proper until this pull, measured by flood)
--   * crosses 149 -> 141 (108,8), the dining car 147 -> (90,8), car 151
--     twice (the $0506 instance -> (74,8), the $017E=1/$0507 instance ->
--     (58,8)), the ghost-leave tile (55,8) (a no-op for a ghostless party:
--     _cbad52 -> $01A3=SHADOW -> _cbae77 -> _cac5c1 party-size $01A2=3 ->
--     EventReturn), the engineer's room 146 via (38,8) facing up
--   * sets the valves SHUT/OPEN/SHUT ($0184=1, $0185=0, $0186=1) by
--     facing-up+A on (7,7) and (9,7)
--   * exits (8,13) -> 141 (38,9), walks to the smokestack (32,7), and
--     faces-up+A into _cbb9d4 -> $003A=1 -> battle 68.
-- Stops at battle-up: dumps every monster slot's species/hp/shield/weak/
-- class rows (battle_vargas's model) and SABIN's entity + level.  No fight.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/forest_done.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
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
    "[%s] map=%d (%d,%d) $0039=%d $017E=%d $017F=%d $0180=%d $0182=%d "..
    "$0183=%d $0184=%d $0185=%d $0186=%d $003A=%d $0506=%d $0507=%d $0509=%d",
    tag, mapIdx(), H.fieldX(), H.fieldY(), sw(0x39), sw(0x17E), sw(0x17F),
    sw(0x180), sw(0x182), sw(0x183), sw(0x184), sw(0x185), sw(0x186),
    sw(0x3A), sw(0x506), sw(0x507), sw(0x509)))
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

-- battle handling per leg: "killbit" for random trash (PopDP resume, the
-- house idiom), "real" for SCRIPTED fights whose event tail is _ca5ea9's
-- win-bit check (kill-bit there = GameOver-park, measured: a lost battle 47
-- left map 145 ctl=false forever).  "real" earns the win bit fast and
-- deterministically: party HP pinned to max per frame (battle_vargas's
-- pinParty) and monsters clamped to 1 hp (its Ipooh idiom) so the next
-- landed swing ends it -- the win is still the engine's own.
local function driveBattle(mode, phase)
  if mode == "real" then
    for e = 0, 3 do H.writeWord(0x3BF4 + e * 2, H.readWord(0x3C1C + e * 2)) end
    for s = 0, 5 do
      if H.readByte(0x3aa8 + s * 2) % 2 == 1
         and H.readWord(0x3BFC + s * 2) > 1 then
        H.writeWord(0x3BFC + s * 2, 1)
      end
    end
  else
    if H.monstersPresent() > 0 then
      for s = 0, 5 do
        if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
          H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
        end
      end
    end
  end
  H.setPad(phase < 4 and { "a" } or {})
end

local function holdDrive(dir, pred, what, budget, fightMode)
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
        driveBattle(fightMode or "killbit", phase); return
      end
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

-- face up + edge-tap A until pred (the lever/valve idiom: the guards read
-- UpdateCtrlFlags' live facing/A bits, so a held UP into the wall plus an
-- A edge fires the trigger's re-check on the next aligned frame)
local function upA(pred, what, budget)
  local phase = 0
  return H.driveUntil(pred, budget or 3000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad(phase < 4 and { "up", "a" } or { "up" })
    end),
  }, what)
end

local function settle(toMap, what)
  local phase = 0
  return H.cond(function() return true end, {
    H.driveUntil(function()
      return mapIdx() == toMap and H.hasControl() and H.tileAligned()
         and bright() >= 15
    end, 4000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(H.dialogWaiting() and phase < 4 and { "a" } or {})
      end),
    }, what),
    H.waitFrames(20),
    H.call(function() swDump(what) end),
  }, {})
end

H.run({ maxFrames = 200000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  -- ---- rear half, exactly as probe_train2 proved it ----
  holdDrive("down", function() return sw(0x39) == 1 end, "departure", 6000),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
  end, 4000, "post-departure", 5),
  H.navTo(2, 7, { maxFrames = 12000 }),
  holdDrive("left", function() return mapIdx() == 142 end, "A west exit", 4000),
  settle(142, "west pocket"),
  holdDrive("left", function() return mapIdx() == 145 end, "-> car B", 4000),
  settle(145, "car B"),
  H.navTo(2, 7, { maxFrames = 12000 }),
  holdDrive("left", function() return mapIdx() == 142 end, "B west exit", 4000),
  settle(142, "pocket (50,8)"),
  H.navTo(41, 8, { maxFrames = 8000, arrive = function()
    return mapIdx() == 145 or (H.fieldX() == 41 and H.fieldY() == 8
       and H.hasControl() and H.tileAligned()) end }),
  holdDrive("up", function() return mapIdx() == 145 and sw(0x180) == 1 end,
    "-> car C", 4000),
  settle(145, "car C"),
  holdDrive("up", function()
    return sw(0x3D) == 1 and H.hasControl() and H.tileAligned()
  end, "bait the follower ghost", 4000),
  H.navTo(26, 9, { maxFrames = 3000 }),
  (function()
    local phase = 0
    return H.driveUntil(function() return sw(0x17C) == 1 end, 3000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(phase < 4 and { "down", "a" } or { "down" })
      end),
    }, "talk to the trap ghost")
  end)(),
  holdDrive("down", function()
    return mapIdx() == 142 and H.hasControl() and H.tileAligned()
       and not inBattle() and bright() >= 15
  end, "battle 47 + mob scene", 30000, "real"),
  H.navTo(40, 8, { maxFrames = 4000 }),
  holdDrive("up", function()
    return H.fieldY() <= 6 and H.hasControl() and H.tileAligned()
  end, "climb to the roof", 15000),
  holdDrive("up", function()
    return H.fieldY() == 5 and H.hasControl() and H.tileAligned()
  end, "top of roof", 4000),
  holdDrive("left", function()
    return H.fieldX() <= 13 and H.hasControl() and H.tileAligned()
  end, "jump scene west", 30000),
  holdDrive("down", function()
    return H.fieldY() >= 8 and H.hasControl() and H.tileAligned()
  end, "down to the strip", 6000),
  holdDrive("left", function() return mapIdx() == 149 end,
    "mob catch + into 149", 30000),
  settle(149, "car 149"),
  H.navTo(28, 5, { maxFrames = 6000 }),
  upA(function() return sw(0x183) == 1 end, "detach lever", 3000),
  holdDrive("down", function()
    return mapIdx() == 141 and H.hasControl() and H.tileAligned()
       and bright() >= 15
  end, "detach cinematic", 30000),
  H.call(function() swDump("detached at 141 (117,8)") end),

  -- ---- the front half ----
  holdDrive("left", function() return mapIdx() == 149 end, "re-enter 149", 4000),
  settle(149, "149 vestibule again"),
  H.navTo(28, 5, { maxFrames = 6000 }),
  upA(function() return sw(0x17F) == 1 end, "second lever pull", 3000),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end,
    2000, "post second pull", 5),
  H.call(function()
    swDump("inner door open")
    flood("149 after the second pull")
  end),
  H.navTo(2, 7, { maxFrames = 10000 }),
  holdDrive("left", function() return mapIdx() == 141 end, "149 west exit", 4000),
  settle(141, "pocket (108,8)"),
  H.call(function() flood("141 at 108") end),

  -- THE STRIP IS THE ROUTE.  The flood above shows the whole front half is
  -- one walkway: ground lanes y=8/y=9 weave under the car-door pockets, and
  -- the two ground gaps (x=61-64, x=77-80) are bridged by the ROOF (y=5)
  -- via the ladder columns x=60/65 and x=76/81.  No car interior is entered
  -- (their props wrap the tilemap and poison the BFS -- measured on 147).
  -- Waypoints are chosen so no leg's shortest path can clip an UNGUARDED
  -- door trigger ((100,8)/(91,8) -> 147, (82,8)/(75,8) -> 151A,
  -- (66,8)/(59,8) -> 151B, (48,8) -> the duct); the ghost-leave event
  -- (55,8) is crossed on purpose -- a measured no-op for a ghostless party.
  H.navTo(101, 9, { maxFrames = 4000 }),
  H.navTo(90, 9, { maxFrames = 4000 }),
  H.navTo(84, 8, { maxFrames = 3000 }),
  H.navTo(83, 9, { maxFrames = 2000 }),
  H.navTo(81, 9, { maxFrames = 2000 }),
  H.navTo(81, 6, { maxFrames = 2000 }),
  H.navTo(76, 5, { maxFrames = 3000 }),
  H.navTo(76, 7, { maxFrames = 2000 }),
  H.navTo(76, 9, { maxFrames = 2000 }),
  H.navTo(74, 9, { maxFrames = 2000 }),
  H.navTo(74, 8, { maxFrames = 2000 }),
  H.navTo(67, 8, { maxFrames = 3000 }),
  H.navTo(67, 9, { maxFrames = 2000 }),
  H.navTo(65, 9, { maxFrames = 2000 }),
  H.navTo(65, 6, { maxFrames = 2000 }),
  H.navTo(60, 5, { maxFrames = 3000 }),
  H.navTo(60, 8, { maxFrames = 2000 }),
  H.navTo(60, 9, { maxFrames = 2000 }),
  H.navTo(58, 9, { maxFrames = 2000 }),
  H.navTo(52, 8, { maxFrames = 4000 }),
  H.navTo(51, 9, { maxFrames = 2000 }),
  H.navTo(45, 9, { maxFrames = 3000 }),
  H.navTo(45, 8, { maxFrames = 2000 }),
  H.navTo(38, 9, { maxFrames = 3000 }),
  H.call(function() swDump("engineer doorstep") end),
  -- the door is entered from the lane below, facing up -- which is exactly
  -- _cba6a5's $01B0 facing gate ((39,8) -> left is engine-refused; the door
  -- tile only accepts entry from (38,9))
  holdDrive("up", function() return mapIdx() == 146 end, "engineer entrance", 3000),
  settle(146, "engineer's room"),
  H.call(function() flood("146") end),

  -- valves: SHUT ($0184=1) / leave open / SHUT ($0186=1)
  H.navTo(7, 7, { maxFrames = 5000 }),
  upA(function() return sw(0x184) == 1 end, "valve 1 SHUT", 3000),
  H.navTo(9, 7, { maxFrames = 3000 }),
  upA(function() return sw(0x186) == 1 end, "valve 3 SHUT", 3000),
  H.call(function() swDump("valves set") end),

  -- out (8,13) -> 141 (38,9), then the smokestack
  H.navTo(8, 13, { maxFrames = 5000, arrive = function()
    return mapIdx() == 141 end }),
  settle(141, "outside the engineer room"),
  H.navTo(32, 7, { maxFrames = 8000 }),
  H.call(function() swDump("at the smokestack") end),
  upA(function() return sw(0x3A) == 1 end, "throw the smokestack switch", 4000),
  H.waitUntil(function() return H.battleLoadStarted() end, 3000, "battle 68 up"),
  H.waitUntil(function()
    for s = 0, 5 do
      if H.readWord(0x57C0 + s * 2) == 0x0106 then return true end
    end
    return false
  end, 1200, "GhostTrain in the formation", 5),
  H.waitFrames(120),
  H.call(function()
    H.log("[battle 68] formation + seed rows:")
    for s = 0, 5 do
      local sp = H.readWord(0x57C0 + s * 2)
      if sp ~= 0xFFFF then
        H.log(string.format(
          "  slot %d: species=$%04X hp=%d shields=%d/%d weakElem=$%02X "..
          "weakClass=$%02X revElem=$%02X revClass=$%02X present=%d",
          s, sp, H.readWord(0x3BFC + s * 2),
          H.readByte(0x3E38 + 8 + s * 2), H.readByte(0x3E39 + 8 + s * 2),
          H.readByte(0x3BE0 + 8 + s * 2), H.readByte(0x3E9C + 8 + s * 2),
          H.readByte(0x3E89 + 8 + s * 2), H.readByte(0x3E9D + 8 + s * 2),
          H.readByte(0x3AA8 + s * 2) & 1))
      end
    end
    for e = 0, 3 do
      H.log(string.format("  entity %d: char=$%02X level=%d hp=%d",
        e, H.readByte(0x3ED8 + e * 2), H.readByte(0x3B18 + e * 2),
        H.readWord(0x3BF4 + e * 2)))
    end
    H.screenshot("ptrain3_battle68")
  end),
})
