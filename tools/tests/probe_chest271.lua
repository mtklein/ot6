-- probe_chest271.lua -- #84 scratch probe, not a fixture and not registered.
-- Boots magicite_ifrit_shiva (map 264), replays gen_n024_entry's first two
-- transitions (264 {9,5} -> 269 {44,53}, 269 {42,12} -> 271 {31,28}), then
-- measures walkability around the bit-94 Break Blade chest at (8,37) on the
-- encounter-bearing factory map 271: a canStep dump plus bfsPath lengths to
-- the candidate stand tiles from the (31,28) landing.  The factory has
-- one-way terrain in places, so this is run before editing the generator.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end
local CX, CY = 8, 37

H.run({ maxFrames = 90000 }, {
  H.loadState("build/states/magicite_ifrit_shiva.mss.lua"),
  H.waitFrames(150),
  H.navTo(9, 5, { maxFrames = 9000, playBattles = "flee",
    arrive = function() return map() == 269 end }),
  H.waitUntil(function() return map() == 269 and settled() end, 6000,
    "map 269 control", 5),
  H.waitFrames(60),
  H.navTo(42, 12, { maxFrames = 25000, playBattles = "flee",
    arrive = function() return map() == 271 end }),
  H.waitUntil(function() return map() == 271 and settled() end, 6000,
    "map 271 control", 5),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[probe271] map=%d at (%d,%d)", map(),
      H.fieldX(), H.fieldY()))
    for y = CY - 5, CY + 5 do
      local row = {}
      for x = CX - 6, CX + 7 do
        local r = H.canStep(x, y - 1, "down") or H.canStep(x, y + 1, "up")
          or H.canStep(x - 1, y, "right") or H.canStep(x + 1, y, "left")
        row[#row + 1] = (x == CX and y == CY) and "C" or (r and "." or "#")
      end
      H.log(string.format("[walk] y=%2d %s", y, table.concat(row)))
    end
    for _, t in ipairs({ { 8, 38, "below, face up" },
                         { 7, 37, "left, face right" },
                         { 9, 37, "right, face left" },
                         { 8, 36, "above, face down" },
                         { 3, 27, "the map-273 exit" } }) do
      local p = H.bfsPath(t[1], t[2])
      H.log(string.format("[probe271] stand (%d,%d) %-18s : %s", t[1], t[2],
        t[3], p and (#p .. " steps") or "NO PATH"))
    end
  end),
})
