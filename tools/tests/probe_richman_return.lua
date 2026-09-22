-- probe_richman_return.lua -- #244/#145.  Trace the RETURN route from the west
-- town back to the old man, via the rich man's house (map 81 -> 83 -> 84 -> 87
-- -> 86 old-man region).  The basement bypass is one-way (the grandson
-- re-blocks the NW->central corridor on re-entry), so after the cider LOCKE
-- gets back to the old man through the interiors, not the basement.
--
-- Ground-truth warp graph (decoded from short_entrance.dat):
--   town75 (15,18)->81(4,16), (23,15)->81(16,15)
--   81 (27,10)->83(7,5)
--   83 (45,12)->84(8,57)
--   84 (15,51)->87(20,33)      87 (57,48)->86(49,31)  [old-man region]
--   84 (57,54)->86(58,56)
-- This probe drives the real bypass to the west town, maps the reachable
-- doorsteps around the map-81 doors, and pushes 81->83->84->87->86.  @manual
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function setsw(id, v)
  local a = 0x1e80 + (id >> 3); local b = 1 << (id & 7)
  H.writeByte(a, v == 1 and (H.readByte(a) | b) or (H.readByte(a) & ~b))
end
local function reach(x, y) return H.bfsPath(x, y) and "YES" or "no" end
local function grid(x0, x1, y0, y1, tag)
  H.log(string.format("[grid %s] map=%d at (%d,%d)", tag, map(), H.fieldX(), H.fieldY()))
  for y = y0, y1 do
    local line = {}
    for x = x0, x1 do
      line[#line+1] = (x==H.fieldX() and y==H.fieldY()) and "@"
        or (H.bfsPath(x, y) and "." or "#")
    end
    H.log(string.format("  y%2d |%s|", y, table.concat(line)))
  end
end

H.run({ maxFrames = 120000 }, {
  H.loadState("build/states/locke_scenario.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.BFS_CAP = 20000
    setsw(0x0104, 1)   -- merchant disguise (basement bypass)
    setsw(0x01D0, 1)   -- pretend we already have the cider (test the return leg)
    H.log(string.format("[boot] map=%d (%d,%d) 0104=%d 0105=%d 01D0=%d",
      map(), H.fieldX(), H.fieldY(), sw(0x0104), sw(0x0105), sw(0x01D0)))
  end),
  -- basement bypass to the west town (as BEAT 1 does)
  H.navTo(37, 41, { maxFrames = 12000, playBattles = true }),
  H.release(),
  H.driveUntil(function() return map() == 86 end, 3000, { H.hold({ "up" }), H.waitFrames(8) },
    "into old man's house (37,40)->86"),
  H.release(), H.waitFrames(90),
  H.navTo(32, 11, { maxFrames = 12000, playBattles = true, arrive = function() return H.fieldX() < 15 end }),
  H.release(), H.waitFrames(60),
  H.navTo(7, 10, { maxFrames = 12000, playBattles = true }),
  H.release(),
  H.talkToObj(20, "grandson (steps aside)"),
  (function()
    local ph = 0
    return H.driveUntil(function()
      return H.hasControl() and not H.dialogWaiting() and not H.eventRunning()
    end, 12000, { H.call(function() ph = (ph + 1) % 8; H.setPad(ph < 4 and { "a" } or {}) end) },
    "ride grandson dialog")
  end)(),
  H.release(), H.waitFrames(60),
  H.navTo(4, 5, { maxFrames = 12000, playBattles = true }),
  H.driveUntil(function() return map() == 75 end, 3000, { H.hold({ "up" }), H.waitFrames(8) },
    "out west (4,4)->75(34,34)"),
  H.release(), H.waitFrames(90),
  H.call(function()
    H.log(string.format("[west] landed map=%d at (%d,%d)", map(), H.fieldX(), H.fieldY()))
    -- map the whole reachable west town so we can SEE where the map-81 doors are
  end),
  H.call(function() grid(10, 40, 12, 48, "west town") end),
  H.call(function()
    -- candidate doorsteps around the map-81 doors (15,18) and (23,15)
    for _, t in ipairs({ {15,19},{15,17},{14,18},{16,18},{23,16},{23,14},{22,15},{24,15},
                         {15,20},{23,17} }) do
      H.log(string.format("[west] near-81 (%d,%d) reach=%s tile=$%02X",
        t[1], t[2], reach(t[1], t[2]), H.maptile(t[1], t[2])))
    end
  end),
  -- CRUX: re-enter map 86 from the west (34,35)->86(4,6) and test whether the
  -- old-man warp (10,7) is reachable, i.e. whether the grandson re-blocks.
  -- Stepping on town (34,35) auto-warps (short entrance) to map 86 (4,6).
  H.navTo(34, 35, { maxFrames = 12000, playBattles = true,
                    arrive = function() return map() == 86 end }),
  H.release(), H.waitFrames(90),
  H.call(function()
    H.log(string.format("[reenter] map=%d at (%d,%d) grandson(obj20)=(%d,%d) 01F0=%d",
      map(), H.fieldX(), H.fieldY(), H.objX(20), H.objY(20), sw(0x01F0)))
  end),
  H.call(function() grid(2, 40, 4, 26, "grandson region re-entry") end),
  H.call(function()
    for _, t in ipairs({ {10,7,"old-man warp"}, {10,8,"warp doorstep"}, {9,8,"downstairs land"},
                         {7,10,"E of grandson"}, {6,10,"grandson tile"}, {33,10,"OLD-MAN region"} }) do
      H.log(string.format("[reenter] (%d,%d)%s reach=%s", t[1], t[2], t[3], reach(t[1], t[2])))
    end
    H.screenshot("reenter_grandson_region")
  end),
  -- $01F0=0 on re-entry: talk to the grandson from the WEST side (stand (5,10))
  -- so he steps aside again, and re-test whether the corridor east opens.
  H.navTo(5, 10, { maxFrames = 12000, playBattles = true }),
  H.release(),
  H.talkToObj(20, "grandson from the WEST (re-step-aside?)"),
  (function()
    local ph = 0
    return H.driveUntil(function()
      return H.hasControl() and not H.dialogWaiting() and not H.eventRunning()
    end, 12000, { H.call(function() ph = (ph + 1) % 8; H.setPad(ph < 4 and { "a" } or {}) end) },
    "ride grandson re-talk")
  end)(),
  H.release(), H.waitFrames(60),
  H.call(function()
    H.log(string.format("[retalk] 01F0=%d grandson(obj20)=(%d,%d) at (%d,%d)",
      sw(0x01F0), H.objX(20), H.objY(20), H.fieldX(), H.fieldY()))
    for _, t in ipairs({ {10,7,"old-man warp"}, {9,8,"downstairs land"}, {7,10,"E of grandson"},
                         {6,10,"grandson old tile"} }) do
      H.log(string.format("[retalk] (%d,%d)%s reach=%s", t[1], t[2], t[3], reach(t[1], t[2])))
    end
  end),
})
