-- probe_zozo3_chests.lua -- can the walked region on map 225 (the clock
-- room, stairs revealed) reach the chest pair (104,9) Tincture / (105,9)
-- Potion?  Those chests sit in the west room, entered only through door
-- 221(15,39).  This asks the live tilemap from zozo_clock_solved, where
-- the party stands at (98,60) with the clock staircase already open
-- ($01F0 set).  Reads only.
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function sw(id)
  return (H.readByte(0x1E80 + math.floor(id / 8)) >> (id % 8)) & 1
end

H.run({ maxFrames = 9000 }, {
  H.loadState("build/states/zozo_clock_solved.mss.lua"),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 1000, "ctl", 5),
  H.call(function()
    H.assertEq(map(), 225, "zozo_clock_solved sits on map 225")
    H.log(string.format("[probe] party (%d,%d) z=%d $01F0=%d",
      H.fieldX(), H.fieldY(), H.readByte(0x00b2) & 3, sw(0x01F0)))
    -- z-aware BFS (H.bfsPath) from the party to each candidate: the two
    -- chest tiles, every cardinal stand tile beside them, and controls --
    -- the landing tile (must be reachable) plus the staircase top and the
    -- Chain Saw room the stairs lead to (what the clock island CAN reach).
    local targets = {
      { 98, 61, "landing (control: reachable)" },
      { 101, 45, "staircase top" },
      { 111, 53, "below the Chain Saw chest" },
      { 104, 10, "below the Tincture chest" },
      { 105, 10, "below the Potion chest" },
      { 103, 9, "left of the pair" },
      { 106, 9, "right of the pair" },
      { 104, 8, "above the Tincture chest" },
      { 105, 8, "above the Potion chest" },
      { 104, 9, "the Tincture chest tile" },
      { 105, 9, "the Potion chest tile" },
    }
    for _, t in ipairs(targets) do
      local p = H.bfsPath(t[1], t[2])
      H.log(string.format("[bfs] (%3d,%2d) %-30s %s", t[1], t[2], t[3],
        p and string.format("PATH, %d steps", #p) or "NO PATH"))
    end
    -- The recipe's walkability dump around the pair, for the report.
    -- Caveat: canStep evaluates at the party's live z, so upper-level
    -- (z=3) shelf tiles in the west room can read as walls from here.
    local CX, CY = 104, 9
    for y = CY - 4, CY + 4 do
      local row = {}
      for x = CX - 5, CX + 6 do
        local r = H.canStep(x, y - 1, "down") or H.canStep(x, y + 1, "up")
          or H.canStep(x - 1, y, "right") or H.canStep(x + 1, y, "left")
        row[#row + 1] = ((x == 104 or x == 105) and y == 9) and "C"
          or (r and "." or "#")
      end
      H.log(string.format("[walk] y=%2d %s", y, table.concat(row)))
    end
  end),
})
