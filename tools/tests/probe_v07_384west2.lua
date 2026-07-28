-- probe_v07_384west2.lua -- 384 WEST traverse census, iteration 2 (issue
-- #31, leg H->I).  NOT a suite test.  Boots v07i_384_span.mss (party at
-- (58,24) after the (58,18) drop; $01F9/$01FA/$0173 set) and drives the
-- (71,15) face-UP+A switch (_cb3176, event_main.asm:45276 -- extends the
-- x=76 column bridge, tiles (76,16..27), persistent $0174), then floods the
-- live model.  Iteration 1's lesson, re-learned: the switch tile is a
-- STOOD-ON re-entry trigger (the §1.7 class -- _cb3176's first line
-- EventReturns on $0174=1, and it re-enters every frame), so hasControl()
-- never settles there; the escape is an unconditional held press, and the
-- settle gate afterwards counts ALIGNMENT, not control.
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

local GOALS = {
  { 9, 27, "gate door (9,27)" },
  { 5, 43, "shortcut trigger (5,43)" },
  { 4, 36, "teleport W-out (4,36)" },
  { 4, 37, "teleport W-in (4,37)" },
  { 121, 22, "teleport E-in (121,22)" },
  { 121, 23, "teleport E-out (121,23)" },
  { 94, 25, "teleport C1-out (94,25)" },
  { 90, 58, "alcove landing (90,58)" },
  { 89, 29, "walk-over (89,29)" },
  { 96, 18, "walk-over (96,18)" },
  { 99, 18, "walk-over (99,18)" },
  { 104, 17, "toggle (104,17)" },
  { 112, 16, "toggle (112,16)" },
  { 99, 13, "choice switch (99,13)" },
  { 113, 10, "$01F7 tile (113,10)" },
  { 26, 8, "the 385 entry (26,8)" },
  { 29, 48, "side-loop door (29,48)" },
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

-- escape a stood-on re-entry trigger: unconditional held presses, cycling
-- the four directions 40 frames each, until the party tile changes; then
-- let the glide finish (alignment, not control)
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

H.run({ maxFrames = 30000 }, {
  H.loadState("build/states/v07i_384_span.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(map(), 384, "booted on BASEMENT 3")
    switchLine("boot")
  end),
  H.navTo(71, 15, { maxFrames = 20000 }),
  upA(0x0174, 4500, "face-UP+A on (71,15) -> $0174 (the x=76 column)"),
  H.waitFrames(90),
  stepOff({ "down", "left", "right", "up" }, 2400,
    "step off the (71,15) trigger"),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[C] after (71,15): party (%d,%d)",
      H.fieldX(), H.fieldY()))
    switchLine("C")
    reach("census-C")
    H.screenshot("v07w2_column")
  end),
  H.saveState("v07i_384_col.mss"),
  H.logStep(function()
    return string.format("384 census C complete at frame %d", H.frame)
  end),
})
