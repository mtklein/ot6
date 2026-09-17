-- @manual
-- probe_locke_tonic.lua -- DIAGNOSTIC probe for #213's Locke-scenario Tonic
-- stop.  Boots locke_scenario.mss (LOCKE alone, map 75 (47,43), the
-- starting pocket the gate soldier at (30,42) closes), walks to the item
-- shop's bump door (44,30), talks to the shopkeeper across the counter
-- (map 85, npc at (106,52), `_ca7884`: shop 8 while $00A4 is clear), buys
-- Tonics, and walks back to (47,43).  Every coordinate the generator stop
-- uses is measured here; the log is the evidence.
--
-- Found on the way: the first version booted sfigaro_town.mss (after the
-- cider, (22,44)) and the shop is not reachable from the west side of town
-- -- the reachable set from the main street (24,34) ends at x=37, and the
-- shop's door mat (44,32) is in the starting pocket east of the gate
-- soldier (the grid this probe logs from the boot tile).
--
--   tools/tests/run.sh tools/tests/probe_locke_tonic.lua
local H = dofile("tools/tests/lib/ot6.lua")

local TONIC, POTION, FENIX = 0xE8, 0xE9, 0xF0
local ANTIDOTE, REMEDY = 0xF2, 0xF5
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function seq(steps) return H.cond(function() return true end, steps) end
local function bag(tag)
  return string.format("[%s] map=%d (%d,%d) gil=%d tonic=%d potion=%d fenix=%d f%d",
    tag, map(), H.fieldX(), H.fieldY(), H.gil(), H.invCountOf(TONIC),
    H.invCountOf(POTION), H.invCountOf(FENIX), H.frame)
end

-- the map-75 entrances a BFS would route through on this walk (gen_kolts's
-- list, plus the doors gen_sfigaro itself uses)
local AVOID = {
  { 8, 32 }, { 9, 32 }, { 10, 32 }, { 18, 55 }, { 19, 55 }, { 20, 55 },
  { 48, 37 }, { 34, 35 }, { 22, 14 }, { 37, 40 }, { 22, 42 },
}

local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end
local function settleField(dstMap)
  return seq({
    H.waitFrames(60),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and map() == dstMap
    end), 12000, { playBattles = true }),
    H.waitFrames(30),
  })
end
local function hop(tx, ty, what)
  return seq({
    H.navTo(tx, ty, { maxFrames = 12000, playBattles = true, avoid = AVOID }),
    H.release(),
    H.logStep(function() return bag(what) end),
  })
end

H.run({ maxFrames = 120000 }, {
  H.loadState("build/states/locke_scenario.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 75, "booted on map 75")
    H.log(bag("boot") .. string.format(" $00A4=%d $0104=%d", sw(0x00A4), sw(0x0104)))
  end),
  H.call(function()
    for _, t in ipairs({ { 44, 32 }, { 44, 31 }, { 43, 32 }, { 45, 32 } }) do
      H.log(string.format("[probe] bfs (%d,%d) from (%d,%d): %s", t[1], t[2],
        H.fieldX(), H.fieldY(), H.bfsPath(t[1], t[2]) and "path" or "none"))
    end
    -- the reachable set around the shop, one row per y ('#' reachable)
    for y = 26, 46 do
      local row = {}
      for x = 20, 52 do
        row[#row + 1] = (x == H.fieldX() and y == H.fieldY()) and "@"
          or (H.bfsPath(x, y) and "#" or ".")
      end
      H.log(string.format("[probe] y=%2d x20..52 %s", y, table.concat(row)))
    end
    for i = 16, 60 do
      local ox = H.readWord(0x086a + 0x29 * i) >> 4
      local oy = H.readWord(0x086d + 0x29 * i) >> 4
      if ox > 0 or oy > 0 then
        H.log(string.format("[probe] obj %d at (%d,%d)", i, ox, oy))
      end
    end
  end),
  hop(44, 32, "shop door mat"),
  H.driveUntil(function() return map() == 85 end, 1200, {
    H.hold({ "up" }), H.waitFrames(8),
  }, "into the item shop (bump door (44,30))"),
  H.release(),
  settleField(85),
  H.logStep(function() return bag("inside map 85") end),
  H.shopTalk(106, 52, "South Figaro item shop (occupied)"),
  H.call(function()
    H.log(string.format("[probe] shop id %d", H.shopId()))
    H.assertEq(H.shopRowOf(H.shopId(), TONIC) ~= nil, true, "the counter sells Tonics")
  end),
  H.buyItem(TONIC, function() return 78 - H.invCountOf(TONIC) end, "TONIC to 78"),
  H.shopClose("South Figaro item shop (occupied)"),
  H.bagArrange({ POTION, FENIX, TONIC, ANTIDOTE, REMEDY },
    { tag = "bag: combat items on top (South Figaro item shop)" }),
  H.logStep(function() return bag("shop done") end),
  H.navTo(104, 57, { maxFrames = 20000, playBattles = true }),
  H.driveUntil(function() return map() == 75 end, 3000, {
    H.hold({ "down" }), H.waitFrames(8),
  }, "out of the item shop"),
  H.release(),
  settleField(75),
  H.logStep(function() return bag("back in town") end),
  hop(47, 43, "back on the boot tile"),
  H.call(function() H.screenshot("probe_locke_tonic_end") end),
})
