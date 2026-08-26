-- probe_chart20.lua -- full chart of Narshe town (map 20).
local H = dofile("tools/tests/lib/ot6.lua")
H.run({ maxFrames = 9000 }, {
  H.loadState("build/states/wob_narshe_town.mss.lua"),
  H.waitFrames(8),
  H.call(function()
    H.log(string.format("charting map %d from (%d,%d)", H.mapId() & 0x1ff,
      H.fieldX(), H.fieldY()))
    for y = 0, 62, 2 do
      local row = {}
      for x = 0, 62, 2 do
        row[#row+1] = H.bfsPath(x, y) and "O" or "."
      end
      H.log(string.format("  y%02d %s", y, table.concat(row)))
    end
  end),
  H.logStep(function() return "done" end),
})
