-- probe_zozo2.lua -- pure BFS census from the clock-solved boot (map 225,
-- {98,61}).  Where does the revealed staircase go?  Which 225 doors back
-- to 221 are reachable, and which land in the upper city?  No navTo -- just
-- read the live tilemap.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end

H.run({ maxFrames = 12000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/zozo_clock_solved.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.log(string.format("[census] map %d from (%d,%d)", map(),
      H.fieldX(), H.fieldY()))
    -- the revealed staircase column x=101..102, y=44..57
    for y = 44, 58 do
      local a = H.bfsPath(101, y)
      local b = H.bfsPath(102, y)
      H.log(string.format("  stair y=%2d: (101,%d)=%s (102,%d)=%s", y,
        y, a and ("ok"..#a) or "no", y, b and ("ok"..#b) or "no"))
    end
    -- every 225->221 door (short_entrance _225)
    for _, t in ipairs({
        { 98, 61, "self" }, { 125, 46, "hint" }, { 103, 55, "reopen" },
        { 104, 26, "d->221(12,37)" }, { 118, 26, "d->221(15,40)" },
        { 110, 54, "d->221(43,25)" }, { 124, 55, "d->221(13,22)" },
        { 83, 61, "d->221(23,18)" }, { 98, 61, "d->221(42,29)?" },
        { 66, 56, "d->221(54,35)" }, { 52, 56, "d->221(38,57)" },
        { 48, 48, "d->221(35,53)" }, { 59, 34, "d->221(34,50)" },
        { 47, 10, "d->221(30,42)" }, { 11, 61, "d->221(35,33)" },
        { 30, 61, "d->221(31,30)" }, { 30, 33, "d->221(30,21)" },
        { 35, 13, "d->221(35,15)" }, { 21, 14, "d->221(49,38)" },
        { 11, 16, "d->221(44,41)" }, { 12, 43, "d->221(44,48)" },
      }) do
      local p = H.bfsPath(t[1], t[2])
      if p then
        H.log(string.format("  door (%d,%d) %-18s ok %d", t[1], t[2], t[3], #p))
      end
    end
  end),
})
