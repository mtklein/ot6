-- probe_v07_384west.lua -- the 384 WEST traverse census, leg H->I's first
-- unknown (issue #31).  NOT a suite test.
--
-- The recon (sealed-gate-recon.md §1 leg 3) and addendum 2.2 say: from the
-- (26,8) entry the live reachable set is the 263-tile SOUTH loop and the
-- gate door (9,27) is NOT in it; the (58,18) switch (_cb2fe7,
-- event_main.asm:45071) opens the (48..50,12) span; the teleport pairs
-- (4,36)<->(121,22) and (94,25)<->(90,58) and the (104,17)/(112,16)
-- face-UP+A toggles are UNMEASURED.  This probe boots the minted boundary-H
-- state (gate_cave_save.mss -- parked ON the 386 save tile, pre-menu),
-- walks back down to 384, and answers stage by stage:
--   A. where the 386 exit door lands on 384, and the fresh-map reachable
--      set from there (the south loop again, or something new);
--   B. what the (58,18) face-UP+A switch actually does to the party (the
--      event script scripts a 6-tile DOWN descent -- obj_script move DOWN,5
--      + jump_low + DOWN,1 -- so the switch is suspected one-way) and what
--      its (48..50,12) span opens up.
-- Each stage floods the live model and reports the named goals; a
-- savestate is minted after B so later iterations skip the walk-out.
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function prop(x, y) return H.readByte(0x7E7600 + H.maptile(x, y)) end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

local GOALS = {
  { 9, 27, "gate door (9,27)" },
  { 10, 27, "gate doorstep (10,27)" },
  { 5, 43, "shortcut trigger (5,43)" },
  { 4, 36, "teleport W (4,36)" },
  { 121, 22, "teleport E (121,22)" },
  { 94, 25, "teleport C1 (94,25)" },
  { 90, 58, "teleport C2 (90,58)" },
  { 58, 18, "the (58,18) switch" },
  { 48, 12, "span W (48,12)" },
  { 50, 12, "span E (50,12)" },
  { 46, 11, "retract trigger (46,11)" },
  { 40, 11, "crumble trigger (40,11)" },
  { 62, 11, "door switch (62,11)" },
  { 66, 11, "ninja trap (66,11)" },
  { 71, 15, "the (71,15) switch" },
  { 89, 29, "walk-over (89,29)" },
  { 96, 18, "walk-over (96,18)" },
  { 99, 18, "walk-over (99,18)" },
  { 104, 17, "toggle (104,17)" },
  { 112, 16, "toggle (112,16)" },
  { 99, 13, "choice switch (99,13)" },
  { 113, 10, "$01F7 tile (113,10)" },
  { 26, 8, "the 385 entry (26,8)" },
  { 64, 10, "save-room door (64,10)" },
  { 29, 48, "side-loop door (29,48)" },
}

local function switchLine(tag)
  H.log(string.format("[%s] $01F3=%d F4=%d F5=%d F6=%d F7=%d F9=%d FA=%d "
    .. "FB=%d $0173=%d $0174=%d $0175=%d", tag,
    sw(0x01F3), sw(0x01F4), sw(0x01F5), sw(0x01F6), sw(0x01F7),
    sw(0x01F9), sw(0x01FA), sw(0x01FB),
    sw(0x0173), sw(0x0174), sw(0x0175)))
end

-- flood the live model from the party tile and report the goals
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

local function settled(m, n)
  local cnt = 0
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    return cnt >= (n or 15)
  end
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/gate_cave_save.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(map(), 386, "booted in the save room (map 386)")
    H.assertEq(H.fieldX(), 74, "on the save tile x")
    H.assertEq(H.fieldY(), 53, "on the save tile y")
  end),

  -- ---- back down to 384 --------------------------------------------------
  H.navTo(73, 58, { maxFrames = 9000 }),
  pressWalk("down", function() return map() == 384 end, 1200,
    "held DOWN off 386 (73,58) -> map 384"),
  H.waitUntil(settled(384, 15), 2400, "384 re-entry settles", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[384-back] landed (%d,%d)", H.fieldX(), H.fieldY()))
    switchLine("384-back")
  end),
  H.call(function() reach("census-A") end),

  -- ---- the (58,18) switch ------------------------------------------------
  H.navTo(58, 18, { maxFrames = 20000 }),
  H.call(function()
    H.log(string.format("[58-18] parked (%d,%d) before the switch",
      H.fieldX(), H.fieldY()))
  end),
  (function() local ph = 0
    return H.driveUntil(function() return sw(0x01F9) == 1 end, 3000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.battleLoadStarted() then
          killBitAll(); H.setPad(ph < 4 and { "a" } or {}); return
        end
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad(ph < 4 and { "up", "a" } or { "up" })
      end),
    }, "face-UP+A on (58,18) -> $01F9 (the west span)")
  end)(),
  -- the event scripts a descent (move DOWN,5 + jump + DOWN,1); let it run out
  H.waitUntil(settled(384, 15), 3600, "post-switch control", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[58-18] after the scene: party (%d,%d)",
      H.fieldX(), H.fieldY()))
    switchLine("post-58-18")
    H.screenshot("v07w_post5818")
  end),
  H.call(function() reach("census-B") end),
  H.saveState("v07i_384_span.mss"),
  H.logStep(function()
    return string.format("384-west census stages A+B complete at frame %d",
      H.frame)
  end),
})
