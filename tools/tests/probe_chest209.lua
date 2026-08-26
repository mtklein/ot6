-- probe_chest209.lua -- boots opera_entry (map 209, parked at (117,20))
-- and measures walkability
-- around the bit-66 Tincture chest at (125,11): a canStep dump of the
-- neighbourhood plus bfsPath lengths to the candidate stand tiles.  Read-only
-- on the game: no A presses, no state writes.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local CX, CY = 125, 11

H.run({ maxFrames = 9000 }, {
  H.loadState("build/states/opera_entry.mss.lua"),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 1000, "ctl", 5),
  H.call(function()
    H.log(string.format("[probe209] map=%d at (%d,%d)", map(),
      H.fieldX(), H.fieldY()))
    for y = CY - 4, CY + 5 do
      local row = {}
      for x = CX - 6, CX + 5 do
        local r = H.canStep(x, y - 1, "down") or H.canStep(x, y + 1, "up")
          or H.canStep(x - 1, y, "right") or H.canStep(x + 1, y, "left")
        row[#row + 1] = (x == CX and y == CY) and "C" or (r and "." or "#")
      end
      H.log(string.format("[walk] y=%2d %s", y, table.concat(row)))
    end
    for _, t in ipairs({ { 125, 12, "below, face up" },
                         { 124, 11, "left, face right" },
                         { 126, 11, "right, face left" },
                         { 125, 10, "above, face down" } }) do
      local p = H.bfsPath(t[1], t[2])
      H.log(string.format("[probe209] stand (%d,%d) %-18s : %s", t[1], t[2],
        t[3], p and (#p .. " steps") or "NO PATH"))
    end
  end),
})
