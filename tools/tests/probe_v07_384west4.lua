-- probe_v07_384west4.lua -- 384 WEST traverse census, iteration 4 (issue
-- #31, leg H->I).  NOT a suite test.
--
-- Iteration 3's lesson: (104,17) is a TOGGLE (_cb33c9,
-- event_main.asm:45485 -- $01F5=1 branch runs the REVERSE rewrite), and
-- an A-spam drive re-fires it -- census F read $01F5=0 after upA had
-- seen it hit 1.  The correct drive is probe_v07_384toggle's measured
-- idiom (toggleOnce below): ONE 8-frame up+A tap, then hold up with A
-- released -- the switch flips at the event's END (~70 frames) and a
-- held UP never re-fires it.
--
-- Boots v07i_384_toggle.mss (party (105,17), $01F5=0, east half open),
-- fires the toggle once, floods the $01F5=1 state (tower-region dump:
-- 587 -> 655 tiles, the (120..121,17..23) descent to both teleport
-- tiles), then rides the (121,23)->(4,37) teleport and floods the WEST
-- side (gate-door-region dump).  The teleport navTo failed in this
-- probe's own run ((121,24) is not walkable); probe_v07_384west5 carries
-- the teleport leg from the v07i_384_toggled.mss state this one mints.
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

local GOALS = {
  { 9, 27, "gate door W (9,27)" },
  { 10, 27, "gate door M (10,27)" },
  { 11, 27, "gate door E (11,27)" },
  { 10, 26, "above door (10,26)" },
  { 12, 27, "right of door (12,27)" },
  { 5, 43, "shortcut trigger (5,43)" },
  { 4, 36, "teleport W-out (4,36)" },
  { 121, 22, "teleport E-in (121,22)" },
  { 121, 23, "teleport E-out (121,23)" },
  { 121, 24, "teleport E doorstep (121,24)" },
  { 112, 16, "toggle (112,16)" },
  { 113, 10, "$01F7 tile (113,10)" },
  { 26, 8, "the 385 entry (26,8)" },
}

local function switchLine(tag)
  H.log(string.format("[%s] $01F3=%d F4=%d F5=%d F6=%d F7=%d F9=%d FA=%d "
    .. "FB=%d $0173=%d $0174=%d $0175=%d", tag,
    sw(0x01F3), sw(0x01F4), sw(0x01F5), sw(0x01F6), sw(0x01F7),
    sw(0x01F9), sw(0x01FA), sw(0x01FB),
    sw(0x0173), sw(0x0174), sw(0x0175)))
end

local function reach(tag)
  local sx, sy = H.fieldX(), H.fieldY()
  local seen = { [sy * 256 + sx] = true }
  local q, qi = { { sx, sy } }, 1
  local D = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 },
              left = { -1, 0 } }
  while qi <= #q and #q < 20000 do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    for m, d in pairs(D) do
      if H.canStep(x, y, m) then
        local nx, ny = x + d[1], y + d[2]
        if nx >= 0 and nx < 128 and ny >= 0 and ny < 64
           and not seen[ny * 256 + nx] then
          seen[ny * 256 + nx] = true
          q[#q + 1] = { nx, ny }
        end
      end
    end
  end
  H.log(string.format("[%s] flood from (%d,%d): %d tiles", tag, sx, sy, #q))
  for _, g in ipairs(GOALS) do
    H.log(string.format("[%s] %s: %s", tag, g[3],
      seen[g[2] * 256 + g[1]] and "REACHABLE" or "no"))
  end
  return seen
end

local function dumpReach(tag, seen, x0, x1, y0, y1)
  for y = y0, y1 do
    local r = {}
    for x = x0, x1 do
      r[#r + 1] = seen[y * 256 + x] and "#" or "."
    end
    H.log(string.format("[%s y=%02d] %s", tag, y, table.concat(r)))
  end
end

local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

-- The measured toggle idiom (probe_v07_384toggle): ONE 8-frame up+A tap
-- fires the event (~70 frames, the switch flips at the END); holding UP
-- with A released NEVER re-fires it; any further A press on the tile
-- toggles it back.  So: single tap, hold up, wait for the flip.
local function toggleOnce(swId, want, maxFrames, what)
  local n = 0
  return H.driveUntil(function() return sw(swId) == want end, maxFrames, {
    H.call(function()
      n = n + 1
      H.setPad(n <= 8 and { up = true, a = true } or { up = true })
    end),
  }, what)
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

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/v07i_384_toggle.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(map(), 384, "booted on BASEMENT 3")
    switchLine("boot")
  end),
  H.navTo(104, 17, { maxFrames = 9000 }),
  toggleOnce(0x01F5, 1, 600, "toggle (104,17) to $01F5=1"),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[F2] after the toggle: party (%d,%d)",
      H.fieldX(), H.fieldY()))
    switchLine("F2")
    local seen = reach("census-F2")
    dumpReach("tower", seen, 100, 127, 8, 30)
    H.screenshot("v07w4_toggled")
  end),
  H.saveState("v07i_384_toggled.mss"),

  -- ---- the (121,23) -> (4,37) teleport ------------------------------------
  H.navTo(121, 24, { maxFrames = 20000 }),
  pressWalk("up", function()
    return H.fieldX() <= 8 and H.tileAligned()
  end, 2400, "held UP onto the (121,23) teleport -> (4,37)"),
  H.waitUntil(function()
    return map() == 384 and H.hasControl() and H.tileAligned()
       and bright() >= 15
  end, 3600, "west-side control after the teleport", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[G] west side: party (%d,%d)",
      H.fieldX(), H.fieldY()))
    switchLine("G")
    local seen = reach("census-G")
    dumpReach("west", seen, 0, 32, 20, 46)
    H.screenshot("v07w4_west")
  end),
  H.saveState("v07i_384_west.mss"),
  H.logStep(function()
    return string.format("384 census F2+G complete at frame %d", H.frame)
  end),
})
