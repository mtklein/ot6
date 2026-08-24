-- probe_chart21.lua -- chart map 21's reachable set from the chase entry
-- (pre-trigger), every tile, to settle whether the cliff-side top rows
-- connect at all (#133).
local H = dofile("tools/tests/lib/ot6.lua")
H.run({ maxFrames = 9000, }, {
  H.loadState("build/states/wob_chase21.mss.lua"),
  H.waitFrames(8),
  H.call(function()
    H.log(string.format("charting map %d from (%d,%d)", H.mapId() & 0x1ff,
      H.fieldX(), H.fieldY()))
    for y = 0, 60, 2 do
      local row = {}
      for x = 0, 62, 2 do
        row[#row+1] = H.bfsPath(x, y) and "O" or "."
      end
      H.log(string.format("  y%02d %s", y, table.concat(row)))
    end
  end),
  H.logStep(function() return "done" end),
})
