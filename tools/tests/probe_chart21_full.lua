-- probe_chart21_full.lua -- full-resolution (step 1) chart of map 21
-- from the post-$023C chase state.
local H = dofile("tools/tests/lib/ot6.lua")
H.run({ maxFrames = 9000 }, {
  H.loadState("build/states/wob_chase23C.mss.lua"),
  H.waitFrames(8),
  H.call(function()
    H.log(string.format("charting map %d from (%d,%d)", H.mapId() & 0x1ff,
      H.fieldX(), H.fieldY()))
    for y = 0, 34 do
      local row = {}
      for x = 8, 48 do
        row[#row+1] = H.bfsPath(x, y) and "O" or "."
      end
      H.log(string.format("  y%02d %s", y, table.concat(row)))
    end
  end),
  H.logStep(function() return "done" end),
})
