-- probe_v07_384west5.lua -- 384 WEST traverse census, iteration 5 (issue
-- #31, leg H->I).  NOT a suite test.  Boots v07i_384_toggled.mss (party on
-- the (104,17) toggle, $01F5=1 -- the (120..121,17..23) descent to the
-- teleports is open, census F2's 655-tile flood) and:
--   G. navTo (121,22), held DOWN onto the (121,23) teleport (short
--      entrance src(121,23) -> dest(4,37) -- entrances fire on held
--      walks; only EVENT triggers demand a rest), settle, censor the WEST
--      side with a dump around the gate door row (9..11,27) and the (5,43)
--      shortcut, and log whether the LoadMap wiped the $01Fx sessions.
-- Mints v07i_384_west.mss on the west side.
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
  { 4, 37, "teleport W-in landing (4,37)" },
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
  H.loadState("build/states/v07i_384_toggled.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(map(), 384, "booted on BASEMENT 3")
    switchLine("boot")
    H.log(string.format("[boot] (%d,%d)", H.fieldX(), H.fieldY()))
  end),
  H.navTo(121, 22, { maxFrames = 20000 }),
  pressWalk("down", function()
    return H.fieldX() <= 8 and H.tileAligned()
  end, 2400, "held DOWN onto the (121,23) teleport -> (4,37)"),
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
    H.screenshot("v07w5_west")
  end),
  H.saveState("v07i_384_west.mss"),
  H.logStep(function()
    return string.format("384 census G complete at frame %d", H.frame)
  end),
})
