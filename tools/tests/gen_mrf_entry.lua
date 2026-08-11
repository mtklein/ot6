-- gen_mrf_entry.lua -- v0.6 leg 3: vector_sneak (VECTOR map 242, {57,34})
-- -> the column north to the factory door -> map 262, the MAGITEK FACTORY
-- upper floor, at {28,8}.  Mints mrf_entry.
--
-- The door is map 242's LONG entrance, decoded from LongEntrance
-- ($EDF480/$EDF882): src {57,2}, horizontal, length 2 -> map 262 dest
-- {28,8}.  So x=57..59 on row y=2 all fire it.  From the sneak exit at
-- {57,34} the column is clean -- the party is already north of the guard
-- lanes (y=39..41) and of the "You!? How'd you get in here?" trap row
-- (56..58,39), which is the entire reason leg 2 exists.
--
-- This leg also carries the live NAVIGATION CENSUS the route recon asked
-- for as its probe 2.  Offline BFS over
-- the static tilemap said map 262 has only ~130 tiles reachable from the
-- door and that (4,22), (11,45), (12,60), (22,53) and (22,54) are all
-- NO-PATH -- because the map is stitched by scripted obj_script
-- transitions and because several of its triggers rewrite BG1 at runtime
-- with `mod_bg_tiles` (event_main.asm:94962-95060).  The census below is
-- measured against the LIVE tilemap the engine actually loaded, so the
-- next leg can be routed off a fact instead of an offline guess.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

local MAP_TITLE_PTRS, MAP_TITLE = 0x268400, 0x0EF100
local function mapTitleHere()
  local p = H.readRomWord(MAP_TITLE_PTRS + H.readByte(0x0520) * 2)
  local a, s = MAP_TITLE + p, ""
  for _ = 1, 24 do
    local c = H.readRomByte(a)
    if c == 0 then break end
    if     c >= 0x20 and c <= 0x39 then s = s .. string.char(65 + c - 0x20)
    elseif c >= 0x3A and c <= 0x53 then s = s .. string.char(97 + c - 0x3A)
    elseif c >= 0x54 and c <= 0x5D then s = s .. string.char(48 + c - 0x54)
    elseif c == 0x65 then s = s .. "."
    elseif c == 0x7F then s = s .. " "
    else s = s .. string.format("<%02X>", c) end
    a = a + 1
  end
  return s
end

local CHARS = { "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN",
                "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU",
                "GOGO", "UMARO" }
local function partyReport(tag)
  local party, raw = {}, {}
  local cur = H.readByte(0x1A6D)
  for c = 0, 13 do
    local b = H.readByte(0x1850 + c)
    raw[#raw + 1] = string.format("%s=%02X", CHARS[c + 1], b)
    if (b & 0x07) == cur and b ~= 0 then
      local base = 0x1600 + 37 * c
      party[#party + 1] = string.format("%s(order %d, L%d, weapon %02X)",
        CHARS[c + 1], (b >> 3) & 3, H.readByte(base + 0x08),
        H.readByte(base + 0x1F))
    end
  end
  return string.format("[party @ %s] party#%d = %s   | $1850: %s | $1EDE=%02X $1EDF=%02X",
    tag, cur, table.concat(party, ", "), table.concat(raw, " "),
    H.readByte(0x1EDE), H.readByte(0x1EDF))
end

local DELTA = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }

-- Flood the live map with H.canStep from the party's tile.  This is the
-- LIB's own passability model against the tilemap the engine has actually
-- loaded (including anything mod_bg_tiles rewrote), so it answers "is this
-- map statically navigable from here" for real.  Caveat, stated: canStep
-- uses the party's CURRENT z-level for every node, where bfsPath tracks z
-- along the path -- so this is a lower bound on a z-split map.
local function census(tag, targets)
  local sx, sy = H.fieldX(), H.fieldY()
  local seen, q, qi = { [sy * 256 + sx] = true }, { { sx, sy } }, 1
  local minx, maxx, miny, maxy = sx, sx, sy, sy
  while qi <= #q and qi <= 3000 do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    if x < minx then minx = x end
    if x > maxx then maxx = x end
    if y < miny then miny = y end
    if y > maxy then maxy = y end
    for d, v in pairs(DELTA) do
      if H.canStep(x, y, d) then
        local nx, ny = x + v[1], y + v[2]
        local k = (ny & 0xFF) * 256 + (nx & 0xFF)
        if not seen[k] then seen[k] = true; q[#q + 1] = { nx, ny } end
      end
    end
  end
  H.log(string.format(
    "[census %s] from (%d,%d) on map %d: %d tiles reachable, bbox x %d..%d y %d..%d",
    tag, sx, sy, map(), #q, minx, maxx, miny, maxy))
  for _, t in ipairs(targets or {}) do
    local p = H.bfsPath(t[1], t[2])
    H.log(string.format("[census %s] bfsPath -> (%d,%d) %s : %s", tag,
      t[1], t[2], t[3] or "",
      p and (#p .. " steps") or "NO PATH"))
  end
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/vector_sneak.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(mapTitleHere(), "VECTOR", "booted in VECTOR (live map title)")
    H.assertEq(map(), 242, "booted on map 242")
    H.assertEq(H.fieldX(), 57, "boot x -- the sneak exit")
    H.assertEq(H.fieldY(), 34, "boot y -- the sneak exit")
    H.log(partyReport("vector_sneak"))
  end),

  -- 1. north up the column to {57,3}, one tile short of the door row.
  H.navTo(57, 3, { maxFrames = 40000, honest = "flee",
    arrive = function() return map() == 262 end }),
  H.navTo(57, 3, { maxFrames = 18000, honest = "flee" }), -- doorstep
  H.call(function()
    H.assertEq(map(), 242, "still in VECTOR at the factory doorstep")
    H.assertEq(H.fieldX(), 57, "factory doorstep x")
    H.assertEq(H.fieldY(), 3, "factory doorstep y")
    H.screenshot("mrf_doorstep")
  end),

  -- 2. UP onto row y=2 -> LongEntrance {57,2} len 2 -> map 262 {28,8}
  (function() local hb = 0
    return H.driveUntil(function() return map() == 262 end, 4000, {
      H.call(function() hb = hb + 1
        if H.battleLoadStarted() then
          H.setPad({ l = true, r = true }); return
        end
        if H.dialogWaiting() then
          H.setPad(hb % 8 < 4 and { "a" } or {}); return
        end
        H.setPad({ up = true })
      end) }, "UP through the factory door -> map 262") end)(),
  H.waitUntil(function() return map() == 262 and settled() end,
    6000, "MAGITEK FACTORY control", 5),
  H.waitFrames(120),

  H.call(function()
    H.assertEq(mapTitleHere(), "MAGITEK FACTORY",
      "the map the party is standing on calls itself MAGITEK FACTORY")
    H.assertEq(map(), 262, "the factory upper floor is map 262")
    H.assertEq(H.fieldX(), 28, "factory landing x (LongEntrance dest)")
    H.assertEq(H.fieldY(), 8, "factory landing y")
    H.assertEq(sw(0x0069), 0,
      "$0069 CLEAR -- the escape has not run, so (28,9) still exits to 242")
    H.assertEq(sw(0x005F), 0, "$005F CLEAR -- Kefka's esper-drain scene is ahead")
    H.log(string.format("[mrf_entry] f%d map=%d title=%q (%d,%d)",
      H.frame, map(), mapTitleHere(), H.fieldX(), H.fieldY()))
    H.log(partyReport("mrf_entry"))
    H.screenshot("mrf_entry")
  end),
  H.saveState("mrf_entry.mss"),

  -- 3. THE CENSUS (recon probe 2).  Run AFTER the mint so the banked state
  --    is untouched by it.  The targets are every tile the recon's offline
  --    pass called NO-PATH plus the two doors onward.
  H.call(function()
    census("mrf_entry", {
      { 22, 53, "the scripted 263 transition trigger" },
      { 22, 54, "its twin" },
      { 12, 60, "the short entrance to 263" },
      { 15, 60, "the long entrance to 263" },
      { 4, 22, "the west platform hop trigger" },
      { 9, 22, "the east platform hop trigger" },
      { 11, 45, "the mid-map trigger" },
      { 6, 31, "_cc76a7" },
      { 19, 24, "the door-opening trigger pair" },
      { 21, 24, "its twin" },
      { 28, 9, "back out to VECTOR" },
    })
  end),
  H.logStep(function()
    return string.format(
      "mrf_entry minted at frame %d -- MAGITEK FACTORY (map 262) at (28,8)",
      H.frame)
  end),
})
