-- probe_fig59_chests.lua -- can gen_zozo2_arrival reach the map-59 chests
-- at (43,12) Tonic bit 14 and (44,12) Antidote bit 15?
--
-- The generator's only map-59 ground is the west stairwell corridor
-- (x 10..12, y 41..50).  The chests sit at y=12 near x=44, a region
-- gen_figaro_intro walks (44,16..19).  This probe loads figaro_submerged,
-- walks the generator's own first step into map 59, and asks BFS whether
-- any stand tile beside the chests is reachable from the corridor; it
-- also dumps the local walkability grid around the chests.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

local function landed(m, n)
  local cnt = 0
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    return cnt >= (n or 10)
  end
end

H.run({ maxFrames = 20000 }, {
  H.loadState("build/states/figaro_submerged.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 61, "booted in the engine room (map 61)")
  end),
  -- the generator's step 1: engine room -> map 59 keep hall
  H.navTo(11, 32, { arrive = function() return map() == 59 end,
                    maxFrames = 9000, playBattles = "tactical" }),
  H.waitUntil(landed(59, 10), 1500, "keep hall", 1),
  H.waitFrames(150),
  H.call(function()
    H.log(string.format("[probe] on map %d at (%d,%d)",
      map(), H.fieldX(), H.fieldY()))
    -- walkability grid around the chests (43,12)/(44,12)
    for y = 8, 18 do
      local row = {}
      for x = 37, 50 do
        local r = H.canStep(x, y - 1, "down") or H.canStep(x, y + 1, "up")
          or H.canStep(x - 1, y, "right") or H.canStep(x + 1, y, "left")
        local c = r and "." or "#"
        if (x == 43 or x == 44) and y == 12 then c = "C" end
        row[#row + 1] = c
      end
      H.log(string.format("[walk] y=%2d x37..50 %s", y, table.concat(row)))
    end
    -- BFS from the corridor to candidate stand tiles and known landmarks
    local goals = {
      { 43, 13, "stand below Tonic" },
      { 44, 13, "stand below Antidote" },
      { 42, 12, "stand left of Tonic" },
      { 45, 12, "stand right of Antidote" },
      { 43, 11, "stand above Tonic" },
      { 44, 11, "stand above Antidote" },
      { 44, 16, "figaro_intro's walked tile" },
      { 12, 45, "own corridor (sanity: reachable)" },
    }
    for _, g in ipairs(goals) do
      local p = H.bfsPath(g[1], g[2])
      H.log(string.format("[bfs] (%d,%d) %s: %s", g[1], g[2], g[3],
        p and (#p .. " steps") or "NO PATH"))
    end
  end),
})
