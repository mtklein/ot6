-- probe_v07_385win.lua -- the map-385 REWRITE-WINDOW instrument (issue
-- #31, leg G->H).  NOT a suite test.  Tests the crossing hypothesis that
-- probe_v07_385walk.lua's phaseWalk was missing:
--
--   1. Every swap callback rewrites the tilemap BEFORE it flips the phase
--      switches (_cb2bb2 event_main.asm:44700: `call _cb2b24` then
--      `switch $01F5=0 / $01F6=1`; same shape at _cb2c57:44735,
--      _cb2d1e:44812, _cb2d97:44853).  The ASYNC mod_bg_tiles + wait_bg
--      take the ~14 frames by which the measured period (158) exceeds the
--      timer's 144.  So there is a WINDOW where the NEXT phase's floor is
--      already physically in place -- H.canStep sees it, because the
--      passability model reads the live tilemap -- while $01F5/$01F6
--      still show the OLD phase.
--   2. Every hurt tile is an event-trigger tile (_cb2dbb/_cb2dd2,
--      event_trigger.asm:1849-1883), and a stood-on trigger tile re-enters
--      its script every frame (the re-entry-trap class)
--      -- which kills hasControl(), which is why phaseWalk went
--      PASSIVE at (6,2) and ate the swap.  The documented escape is an
--      UNCONDITIONAL HELD PRESS.
--
-- So the crossing should be: stand at (6,2) during $01F5 holding RIGHT
-- unconditionally; the engine takes the step the frame the rewrite opens
-- (7,2), ~14 frames before $01F6=1 arms (6,2)'s hurt trigger; then keep
-- holding RIGHT through the fresh $01F6 stretch to (11,2), where the east
-- column is walkable in both phases.
--
-- Part 2: arm cycle B at (11,3) and dump the east half's tilemap +
-- reachable set in BOTH phases -- the data the (11,3) -> (13,13) plan
-- needs, which no prior run has measured (cycle B has never been armed
-- with the room in a driveable state).
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function prop(x, y) return H.readByte(0x7E7600 + H.maptile(x, y)) end
local function hpsum()
  return H.readWord(0x1609) + H.readWord(0x1609 + 37)
       + H.readWord(0x1609 + 74) + H.readWord(0x1609 + 111)
end

-- the flip clock: an edge on $01F6 (either direction) is a swap instant --
-- only the four timer callbacks touch $01F6 (the arming scripts' trailing
-- `wait 144 / switch $01F5=1` touches $01F5 alone).
local lastF6, lastFlipFrame, flips = nil, nil, 0
local function clockTick()
  local cur = sw(0x01F6)
  if lastF6 ~= nil and cur ~= lastF6 then
    flips = flips + 1
    H.log(string.format("[clock] flip %d at f%d ($01F6 %d->%d, gap %s)",
      flips, H.frame, lastF6, cur,
      lastFlipFrame and tostring(H.frame - lastFlipFrame) or "-"))
    lastFlipFrame = H.frame
  end
  lastF6 = cur
end
local function fsf()
  return lastFlipFrame and (H.frame - lastFlipFrame) or -1
end

local W, Hh = 17, 16
local function dumpRoom(tag)
  H.log(string.format("[%s] pos=(%d,%d) $01F0=%d $01F1=%d $01F3=%d $01F4=%d "
    .. "$01F5=%d $01F6=%d", tag, H.fieldX(), H.fieldY(),
    sw(0x01F0), sw(0x01F1), sw(0x01F3), sw(0x01F4), sw(0x01F5), sw(0x01F6)))
  for y = 0, Hh - 1 do
    local r1 = {}
    for x = 0, W - 1 do r1[#r1 + 1] = string.format("%02X", prop(x, y)) end
    H.log(string.format("[%s p1 y=%02d] %s", tag, y, table.concat(r1, " ")))
  end
end
local function reach(tag)
  local sx, sy = H.fieldX(), H.fieldY()
  local seen = { [sy * 64 + sx] = true }
  local q, qi = { { sx, sy } }, 1
  local MOVES = { "up", "right", "down", "left" }
  local D = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }
  while qi <= #q do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    for _, m in ipairs(MOVES) do
      if H.canStep(x, y, m) then
        local d = D[m]
        local nx, ny = x + d[1], y + d[2]
        if nx >= 0 and nx < W and ny >= 0 and ny < Hh
           and not seen[ny * 64 + nx] then
          seen[ny * 64 + nx] = true
          q[#q + 1] = { nx, ny }
        end
      end
    end
  end
  local out = {}
  for y = 0, Hh - 1 do
    local row = {}
    for x = 0, W - 1 do row[#row + 1] = seen[y * 64 + x] and "o" or "." end
    out[#out + 1] = table.concat(row, "")
  end
  H.log(string.format("[%s reach from (%d,%d)] %d tiles", tag, sx, sy, #q))
  for y, r in ipairs(out) do
    H.log(string.format("[%s reach y=%02d] %s", tag, y - 1, r))
  end
end

-- hold `dir` unconditionally (the re-entry-trap escape idiom) until pred
-- or a hurt fires; per-frame trace while `traceOn()` holds.
local function holdWalk(dir, pred, maxFrames, traceOn, what)
  local hp0 = nil
  return H.driveUntil(function()
    if hp0 == nil then hp0 = hpsum() end
    return pred() or hpsum() < hp0
  end, maxFrames, {
    H.call(function()
      clockTick()
      if traceOn and traceOn() then
        H.log(string.format(
          "[win] f%d fsf=%d (%d,%d) al=%d ctl=%d p62=%02X p72=%02X "
          .. "p82=%02X $01F5=%d $01F6=%d hp=%d",
          H.frame, fsf(), H.fieldX(), H.fieldY(),
          H.tileAligned() and 1 or 0, H.hasControl() and 1 or 0,
          prop(6, 2), prop(7, 2), prop(8, 2),
          sw(0x01F5), sw(0x01F6), hpsum()))
      end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/v07q_385_entry.mss.lua"),
  H.waitFrames(180),
  H.call(function()
    H.assertEq(map(), 385, "booted on BASEMENT 2 (map 385)")
    H.assertEq(H.fieldX(), 1, "boot x")
    H.assertEq(H.fieldY(), 2, "boot y")
    H.log(string.format("[boot] hpsum=%d", hpsum()))
  end),

  -- arm cycle A at (3,2).  Release the pad on ARRIVAL (x flips at step
  -- completion moving right), not on $01F0 -- the switch sets a few frames
  -- into the arming script, and a hold still up would walk the party onto
  -- (4,2), a hurt-$01F6 tile, right as timer 0 fires _cb2bb2.
  holdWalk("right", function() return H.fieldX() >= 3 end, 1800, nil,
    "held RIGHT onto the cycle-A trigger (3,2)"),
  H.waitUntil(function() return sw(0x01F0) == 1 end, 900,
    "cycle A armed ($01F0)", 2),
  H.call(function()
    H.log(string.format("[armed] at (%d,%d) $01F0=%d", H.fieldX(),
      H.fieldY(), sw(0x01F0)))
  end),

  -- settle onto (3,2) exactly (the hold can overshoot the trigger fire),
  -- then wait for a FRESH $01F5 stretch: a $01F6 1->0 edge.
  (function()
    local seen10 = false
    return H.driveUntil(function() return seen10 end, 2000, {
      H.call(function()
        local before = lastF6
        clockTick()
        if before == 1 and lastF6 == 0 then seen10 = true end
        -- park on (3,2): safe in both phases
        local x = H.fieldX()
        if x > 3 then H.setPad({ left = true })
        elseif x < 3 then H.setPad({ right = true })
        else H.setPad({}) end
      end),
    }, "a fresh $01F5 stretch (park at (3,2))")
  end)(),
  H.call(function()
    H.assertEq(sw(0x01F5), 1, "$01F5 stretch begun")
    H.log(string.format("[p5] fresh stretch at f%d, party (%d,%d)",
      H.frame, H.fieldX(), H.fieldY()))
  end),

  -- THE CROSSING ATTEMPT: hold RIGHT from (3,2).  The party walks 4,5,6
  -- (open in $01F5), stalls against the (7,2) wall, and -- hypothesis --
  -- steps through the moment the rewrite window opens it, ~14 frames
  -- before $01F6 arms (6,2)'s hurt trigger.  Then it keeps walking the
  -- fresh $01F6 stretch 7,8,9,10 to (11,2).  Trace every frame once past
  -- x=5 or once fsf>=120.
  holdWalk("right", function()
    return H.fieldX() >= 11 and H.fieldY() == 2 and H.tileAligned()
  end, 2400, function()
    return H.fieldX() >= 5 or fsf() >= 120
  end, "held RIGHT across the row-2 phase boundary to (11,2)"),
  H.call(function()
    H.log(string.format("[crossed?] at (%d,%d) hp=%d $01F0=%d $01F5=%d "
      .. "$01F6=%d", H.fieldX(), H.fieldY(), hpsum(), sw(0x01F0),
      sw(0x01F5), sw(0x01F6)))
    H.assertEq(H.fieldX(), 11, "party crossed row 2 to x=11")
    H.assertEq(H.fieldY(), 2, "party still on row 2")
    H.assertEq(sw(0x01F0), 1, "cycle A still armed -- no hurt/wipe fired")
    H.screenshot("v07_385win_crossed")
  end),

  -- Part 2: arm cycle B at (11,3), then dump the east half in both phases.
  -- Same arrival-release rule: (11,4) below is a hurt-$01F6 tile and B's
  -- timer 0 flips to $01F6 one frame after arming.
  holdWalk("down", function() return H.fieldY() >= 3 end, 1800, nil,
    "held DOWN onto the cycle-B trigger (11,3)"),
  H.waitUntil(function() return sw(0x01F1) == 1 end, 900,
    "cycle B armed ($01F1)", 2),
  H.call(function()
    H.log(string.format("[armedB] at (%d,%d) $01F1=%d $01F0=%d",
      H.fieldX(), H.fieldY(), sw(0x01F1), sw(0x01F0)))
    -- reset the clock: arming B stopped every timer and started its own
    lastFlipFrame = nil
    H.screenshot("v07_385win_armedB")
  end),
  H.waitUntil(function() return sw(0x01F6) == 1 end, 900, "B $01F6", 1),
  H.waitFrames(20),
  H.call(function() dumpRoom("B6"); reach("B6") end),
  H.waitUntil(function() return sw(0x01F5) == 1 and sw(0x01F6) == 0 end,
    900, "B $01F5", 1),
  H.waitFrames(20),
  H.call(function() dumpRoom("B5"); reach("B5") end),
  H.call(function()
    H.log(string.format("[done] at (%d,%d) hp=%d", H.fieldX(), H.fieldY(),
      hpsum()))
  end),
  H.logStep("385 window instrument complete"),
})
