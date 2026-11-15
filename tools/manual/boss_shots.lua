-- tools/manual/boss_shots.lua: the manual's cover frame, a boss whose shield
-- line shows weaknesses being found.  Not a test; tools/manual/shots.py runs
-- it with OT6_NO_PUBLISH=1.
--
-- Boots the graph's ultros2_entry (the Opera House rafters), rides the scene
-- into the Ultros battle, and fights it with the library's menu driver (real
-- inputs only).  Each time the number of Ultros's weaknesses on show grows,
-- it takes "boss_rev<N>" (N = weaknesses revealed), and "boss_rev<N>_late"
-- 40 frames on, once the hit's message and numbers have settled.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/ultros2_entry.mss.lua"
local ULTROS2 = 0x012d

local function RVE(s) return 0x3E89 + (8 + s * 2) end   -- revealed elements
local function RVC(s) return 0x3E9D + (8 + s * 2) end   -- revealed weapon types
local function SH(s) return 0x3E38 + (8 + s * 2) end    -- current shields
local function bits(v) local n = 0; while v > 0 do n = n + (v & 1); v = v >> 1 end; return n end

local slot, best, late, aPh = nil, 0, nil, 0
local F

local function watch()
  if slot == nil then
    for s = 0, 5 do
      if H.readWord(0x57C0 + s * 2) == ULTROS2 and (H.readByte(0x3aa8 + s * 2) & 1) ~= 0 then slot = s end
    end
    if slot == nil then return end
  end
  local n = bits(H.readByte(RVE(slot))) + bits(H.readByte(RVC(slot)))
  if n > best then
    best = n
    H.log(string.format("[boss] f%d: %d weaknesses shown, %d shields", H.frame, n, H.readByte(SH(slot))))
    H.screenshot("boss_rev" .. n)
    late = { at = H.frame + 40, tag = "boss_rev" .. n .. "_late" }
  end
  if late and H.frame >= late.at then
    H.screenshot(late.tag)
    late = nil
  end
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function()
      aPh = (aPh + 1) % 8
      H.setPad(aPh < 4 and { "a" } or {})
    end),
  }, "the rafter scene reaches the Ultros battle"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 3000, "Ultros up", 10),
  H.call(function() F = H.newFightDriver("manual_boss", H.fightByMenuOpts()) end),
  H.driveUntil(function() return not H.battleLoadStarted() end, 40000, {
    H.call(function() F.frame(); watch() end),
  }, "fight Ultros through the menus"),
  H.call(function() H.log(string.format("[boss] done: %d weaknesses shown at most", best)) end),
})
