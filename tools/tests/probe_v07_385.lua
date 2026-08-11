-- probe_v07_385.lua -- the basement 2 timed-floor instrument (issue #31,
-- step G->H).  Not a suite test.  Boots v07q_385_entry.mss (map 385 (1,2),
-- party TERRA LOCKE EDGAR SABIN) and measures, live:
--   * what the room's reachable set is in the unarmed state (map-init
--     _cb2b0f -> _cb2bc9, event_main.asm:44714 region);
--   * which arming trigger the entry tile can reach ((3,2)/(10,2) arm
--     cycle A via _cb2aca/_cb2ae8 :44634/:44646; (11,3)/(13,11) arm cycle
--     B via _cb2c6e/_cb2c8c :44746/:44758);
--   * how the live tilemap differs between phase $01F5 and phase $01F6,
--     and whether a path to the (13,13) exit exists in either;
--   * whether a safe path exists that never steps on a hurt trigger
--     (_cb2dbb tiles hurt while $01F5, _cb2dd2 while $01F6, (15,10)
--     always; event_trigger.asm:1844-1885).
-- Everything is a dump; it never tries to cross.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- Issue #75: playBattles = "flee" keeps this walk out of the library's
-- monster-dead flag write, and here it is not a no-op: this Magitek Research
-- Facility basement draws random battles (map_prop.dat byte +5 bit 7 set).
-- "flee" is the spelling every gen_mrf_* generator already uses on these
-- floors: the instrument is measuring a floor mechanism, not a fight.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

local W, Hh = 17, 16
local function dumpRoom(tag)
  H.log(string.format("[%s] pos=(%d,%d) $01F0=%d $01F1=%d $01F2=%d $01F3=%d "
    .. "$01F4=%d $01F5=%d $01F6=%d", tag, H.fieldX(), H.fieldY(),
    sw(0x01F0), sw(0x01F1), sw(0x01F2), sw(0x01F3), sw(0x01F4),
    sw(0x01F5), sw(0x01F6)))
  for y = 0, Hh - 1 do
    local r1, r2 = {}, {}
    for x = 0, W - 1 do
      local t = H.maptile(x, y)
      r1[#r1 + 1] = string.format("%02X", H.readByte(0x7E7600 + t))
      r2[#r2 + 1] = string.format("%02X", H.readByte(0x7E7700 + t))
    end
    H.log(string.format("[%s p1 y=%02d] %s", tag, y, table.concat(r1, " ")))
    H.log(string.format("[%s p2 y=%02d] %s", tag, y, table.concat(r2, " ")))
  end
end

-- reachable set from the party tile over the live model (H.canStep)
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
  for y, r in ipairs(out) do H.log(string.format("[%s reach y=%02d] %s", tag, y - 1, r)) end
  local function say(x, y, label)
    H.log(string.format("[%s] %s (%d,%d): %s", tag, label, x, y,
      seen[y * 64 + x] and "REACHABLE" or "no"))
  end
  say(3, 2, "cycle-A trigger");  say(10, 2, "cycle-A trigger")
  say(11, 3, "cycle-B trigger"); say(13, 11, "cycle-B trigger")
  say(13, 13, "the 384 exit door")
  return seen
end

local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/v07q_385_entry.mss.lua"),
  H.waitFrames(180),
  H.call(function()
    H.assertEq(map(), 385, "booted on BASEMENT 2 (map 385)")
    H.assertEq(H.fieldX(), 1, "boot x")
    H.assertEq(H.fieldY(), 2, "boot y")
  end),
  H.call(function() dumpRoom("unarmed") end),
  H.call(function() reach("unarmed") end),

  -- arm cycle A: walk to (3,2)
  H.navTo(3, 2, { maxFrames = 12000, playBattles = "flee",
    arrive = function() return sw(0x01F0) == 1 end }),
  H.waitUntil(function() return sw(0x01F0) == 1 end, 3000,
    "cycle A armed ($01F0)", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[armed] at (%d,%d) $01F0=%d $01F2=%d $01F5=%d $01F6=%d",
      H.fieldX(), H.fieldY(), sw(0x01F0), sw(0x01F2), sw(0x01F5), sw(0x01F6)))
    H.screenshot("v07_385_armed")
  end),

  -- watch the phase flip and dump the room in both phases
  H.waitUntil(function() return sw(0x01F5) == 1 end, 900, "phase $01F5", 1),
  H.call(function() dumpRoom("phase5"); reach("phase5") end),
  H.waitUntil(function() return sw(0x01F6) == 1 end, 900, "phase $01F6", 1),
  H.call(function() dumpRoom("phase6"); reach("phase6") end),
  H.waitUntil(function() return sw(0x01F5) == 1 end, 900, "phase $01F5 again", 1),
  H.call(function() reach("phase5b") end),

  -- phase length: count frames between flips
  (function()
    local n, flips, last = 0, 0, 1
    return H.driveUntil(function() return flips >= 4 end, 3000, {
      H.call(function()
        n = n + 1
        local cur = sw(0x01F5)
        if cur ~= last then
          flips = flips + 1
          H.log(string.format("[phase] flip %d at local frame %d -> $01F5=%d $01F6=%d",
            flips, n, sw(0x01F5), sw(0x01F6)))
          n = 0
          last = cur
        end
        H.setPad({})
      end),
    }, "four phase flips")
  end)(),
  H.logStep("385 instrument complete"),
})
