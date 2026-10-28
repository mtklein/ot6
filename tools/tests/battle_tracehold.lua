-- @suite savestate=first_battle
-- battle_tracehold.lua -- the tile trace does not record the boot or a
-- state load's frames (#489).
--
-- The trace ([tiles] lines, tools/chest_visibility.py's input) samples every
-- aligned frame.  Before a run's first state load the machine is at its boot,
-- and its RAM read as a map: `[tiles] map=0 n=1 xy=0:0` at frame 21 and
-- `map=3 n=1 xy=0:0` at frame 22 on any fixture run, and on the WoR legs the
-- `map=1 ... xy=0:28`, `0:6`, `128:2` field coordinates under a world map
-- that the coverage audit (e348f864) found, so "stood on" counts were upper
-- bounds.  The load drops the boot's samples and holds the trace off for the
-- frames the restore takes (M.traceOnLoad).
--
-- After a 20-frame boot and the load, no [tiles] flush happened from the
-- load request on (the flushes are M.traceFlushes; the boot's own, before
-- the request, are not this test's): the only map the trace has seen since
-- is the fixture's own.  The same run with M.TRACE_HOLD = false (the old
-- behaviour; the negative control, run by hand, is kept under
-- build/attempts/wt/v038-harness-fixes/) flushes `map=3` at the frame after
-- the request.
local H = dofile("tools/tests/lib/ot6.lua")

H.run({ maxFrames = 600 }, {
  H.waitFrames(20),
  H.loadState("build/states/first_battle.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    local seen = {}
    for _, f in ipairs(H.traceFlushes) do
      if f[3] > H.loadedFrame then seen[#seen + 1] = string.format("map=%d n=%d f%d", f[1], f[2], f[3]) end
    end
    H.log("battle_tracehold: flushes after the load request (f" .. H.loadedFrame .. "): "
      .. (#seen > 0 and table.concat(seen, "; ") or "none"))
    H.assertEq(#seen, 0, "no [tiles] flush from the frames the load takes")
  end),
})
