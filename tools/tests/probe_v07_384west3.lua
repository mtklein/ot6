-- probe_v07_384west3.lua -- 384 WEST traverse census, iteration 3 (issue
-- #31, leg H->I).  NOT a suite test.  Boots v07i_384_col.mss (party at
-- (70,15); $01F9/$01FA/$0173/$0174 set, the whole east half open -- 587
-- tiles) and drives:
--   F. the (104,17) face-UP+A TOGGLE (_cb33c9, event_main.asm:45485,
--      $01F5 -- flips the 5x13 tower region (109..113,10..22)); census;
--   G. the (121,23) -> (4,37) teleport (short-entrance record, decoded:
--      src(121,23) raw 2180 dest(4,37)); census the WEST side, dump the
--      reachable map around the gate door row (9..11,27) -- the long
--      entrance spans x 9..11 at y=27 (len 2 H), so the doorstep must be
--      chosen OFF that row -- and around the (5,43) shortcut.
-- Whether the teleport's LoadMap wipes the $01Fx session switches is
-- measured here too (switchLine before/after).
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
  { 94, 25, "teleport C1-out (94,25)" },
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

-- ASCII map of the flood around a rectangle: '#' reachable, '.' not
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

local function upA(swId, maxFrames, what)
  local ph = 0
  return H.driveUntil(function() return sw(swId) == 1 end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        killBitAll(); H.setPad(ph < 4 and { "a" } or {}); return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad(ph < 4 and { "up", "a" } or { "up" })
    end),
  }, what)
end

local function stepOff(dirs, maxFrames, what)
  local x0, y0, moved, calm, n = nil, nil, false, 0, 0
  return H.driveUntil(function()
    if not x0 then return false end
    if H.fieldX() ~= x0 or H.fieldY() ~= y0 then moved = true end
    calm = (moved and H.tileAligned() and not H.dialogWaiting()
            and not H.battleLoadStarted()) and calm + 1 or 0
    return calm >= 10
  end, maxFrames, {
    H.call(function()
      if not x0 then x0, y0 = H.fieldX(), H.fieldY() end
      if H.battleLoadStarted() then killBitAll(); H.setPad({ "a" }); return end
      if H.dialogWaiting() then H.setPad({ "a" }); return end
      if moved then H.setPad({}); return end
      n = n + 1
      local dir = dirs[((n // 40) % #dirs) + 1]
      H.setPad({ [dir] = true })
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
  H.loadState("build/states/v07i_384_col.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(map(), 384, "booted on BASEMENT 3")
    switchLine("boot")
  end),

  -- ---- F: the (104,17) toggle ---------------------------------------------
  H.navTo(104, 17, { maxFrames = 20000 }),
  upA(0x01F5, 4500, "face-UP+A on (104,17) -> $01F5 (the tower toggle)"),
  H.waitFrames(90),
  stepOff({ "down", "left", "right", "up" }, 2400,
    "step off the (104,17) trigger"),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[F] after (104,17): party (%d,%d)",
      H.fieldX(), H.fieldY()))
    switchLine("F")
    reach("census-F")
    H.screenshot("v07w3_toggle")
  end),
  H.saveState("v07i_384_toggle.mss"),

  -- ---- G: the (121,23) -> (4,37) teleport ---------------------------------
  H.navTo(121, 24, { maxFrames = 20000 }),
  pressWalk("up", function()
    return H.fieldX() <= 8 and H.tileAligned()
  end, 2400, "held UP onto the (121,23) teleport -> (4,37)"),
  H.waitUntil(function()
    local cnt = map() == 384 and H.hasControl() and H.tileAligned()
            and bright() >= 15
    return cnt
  end, 3600, "west-side control after the teleport", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[G] west side: party (%d,%d)",
      H.fieldX(), H.fieldY()))
    switchLine("G")
    local seen = reach("census-G")
    dumpReach("west", seen, 0, 32, 20, 46)
    H.screenshot("v07w3_west")
  end),
  H.saveState("v07i_384_west.mss"),
  H.logStep(function()
    return string.format("384 census F+G complete at frame %d", H.frame)
  end),
})
