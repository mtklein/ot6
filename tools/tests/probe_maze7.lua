-- probe_maze7.lua -- decisive: does the DIAGONAL-aware bfsPath (the library's
-- real pathfinder, MOVES incl. the 4 diagonals) reach the maze from arrival?
-- My earlier floods were CARDINAL-only and may have fragmented islands that
-- diagonal seams actually connect.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

H.run({ maxFrames = 12000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/zozo_arrival.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.log(string.format("[bfs] from (%d,%d) map %d",
      H.fieldX(), H.fieldY(), H.mapId() & 0x1ff))
    for _, t in ipairs({
        -- cardinal-flood "leak" destinations
        { 41, 30, "leak 41,30" }, { 27, 29, "leak 27,29" },
        { 20, 32, "leak 20,32" }, { 12, 8, "leak 12,8" },
        { 16, 14, "leak 16,14" }, { 41, 32, "leak 41,32" },
        { 39, 38, "leak 39,38" }, { 10, 39, "leak 10,39" },
        -- the maze proper
        { 28, 39, "jumpL39" }, { 25, 39, "jumpR39" },
        { 28, 33, "jumpL33" }, { 35, 41, "CRANE" },
        { 30, 14, "DADALUMA" }, { 33, 9, "tower door" },
        { 30, 42, "d->225(47,10)" }, { 30, 21, "d->225(30,33)" },
      }) do
      local p = H.bfsPath(t[1], t[2])
      H.log(string.format("  (%d,%d) %-16s %s", t[1], t[2], t[3],
        p and ("REACHABLE " .. #p) or "no"))
    end
  end),
})
