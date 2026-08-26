-- probe_kolts_walk.lua -- walkability dumps around the seven South Figaro
-- chests, from south_figaro.mss.  For each chest, print which
-- neighbouring tiles accept a step in from some direction, plus whether the
-- party's BFS can actually reach each candidate stand tile.
local H = dofile("tools/tests/lib/ot6.lua")
local CHESTS = {
  { 6, 31, "Tonic" }, { 14, 28, "Green Cherry" }, { 11, 23, "Warp Stone" },
  { 22, 18, "Fenix Down" }, { 32, 16, "Tonic (measured)" },
  { 15, 45, "Antidote" }, { 15, 47, "Eyedrop" },
}
H.run({ maxFrames = 9000 }, {
  H.loadState("build/states/south_figaro.mss.lua"),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 1000, "ctl", 5),
  H.call(function()
    for _, c in ipairs(CHESTS) do
      local CX, CY = c[1], c[2]
      H.log(string.format("[walk] ==== %s at (%d,%d) ====", c[3], CX, CY))
      for y = CY - 4, CY + 4 do
        local row = {}
        for x = CX - 5, CX + 5 do
          local r = H.canStep(x, y - 1, "down") or H.canStep(x, y + 1, "up")
            or H.canStep(x - 1, y, "right") or H.canStep(x + 1, y, "left")
          row[#row + 1] = (x == CX and y == CY) and "C" or (r and "." or "#")
        end
        H.log(string.format("[walk] y=%2d %s", y, table.concat(row)))
      end
      local below = H.bfsPath(CX, CY + 1)
      local left = H.bfsPath(CX - 1, CY)
      local right = H.bfsPath(CX + 1, CY)
      local above = H.bfsPath(CX, CY - 1)
      H.log(string.format(
        "[walk] bfs from party: below=%s left=%s right=%s above=%s",
        below and #below or "no", left and #left or "no",
        right and #right or "no", above and #above or "no"))
    end
  end),
})
