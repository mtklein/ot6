-- @suite savestate=opera_stage
-- field_choice.lua -- #190: H.dialogChoice steers a real choice window by
-- the cursor and reports the row the engine took.
--
-- The aria (gen_opera5_dance): from opera_stage the trigger at (97,7) loads
-- map 236 and three chained lyric choices follow, answered {0,1,0}.  One
-- snapshot on map 236, two branches from it:
--   A. the three forks with the lib's default ("waiting") steering: three
--      [choice] lines, landed rows 0,1,0, and the aria's own postfork
--      landing at (5,21) -- the rows the route needs are the rows the game
--      acted on;
--   B. fork 1 answered with row 1 instead: the same dialog id as A's first
--      window, landed row 1 of the same count.  A helper that counted
--      presses or read a stale cell could not tell A's row 0 from B's row 1.
-- Reads and presses only; the snapshot is a complete machine state.
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end

local blob, req
local A = H.dialogChoice({ 0, 1, 0 }, {
  tag = "aria A", what = "aria forks {0,1,0}", maxFrames = 15000,
  done = function(c) return c.resolved >= 3 end,
})
local B = H.dialogChoice(1, {
  tag = "aria B", what = "aria fork 1 answered 1", maxFrames = 15000,
  done = function(c) return c.resolved >= 1 end,
})

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/opera_stage.mss.lua"),
  H.waitFrames(60),
  H.call(function() H.assertEq(map(), 238, "boot on the stage (map 238)") end),
  H.navTo(97, 7, { maxFrames = 8000, playBattles = "tactical",
                   arrive = function() return map() ~= 238 end }),
  H.waitUntil(function() return map() == 236 end, 6000, "aria loads map 236", 10),
  H.call(function() req = H.requestSaveState() end),
  H.waitFrames(2),
  H.call(function() H.checkReq(req, "map 236 snapshot"); blob = req.blob end),

  -- A
  A,
  H.waitUntil(function()
    return map() == 236 and H.hasControl() and H.tileAligned()
  end, 6000, "control on 236 after the forks", 5),
  H.call(function()
    local h = A.choice.history
    H.assertEq(#h, 3, "A: three choice windows resolved")
    for i, want in ipairs({ 0, 1, 0 }) do
      H.assertEq(h[i].row, want, string.format("A: fork %d landed row", i))
      H.assertEq(h[i].max >= 2, true, string.format("A: fork %d is a choice", i))
    end
    H.assertEq(H.fieldX() == 5 and H.fieldY() == 21, true,
      "A: the aria's postfork landing (5,21)")
  end),

  -- B
  H.call(function() req = H.requestLoadState(blob) end),
  H.waitFrames(2),
  H.call(function() H.checkReq(req, "map 236 snapshot reload") end),
  B,
  H.call(function()
    local a, b = A.choice.history[1], B.choice.last
    H.assertEq(b.dlg, a.dlg, "B: the same first window as A")
    H.assertEq(b.max, a.max, "B: the same option count as A")
    H.assertEq(b.row, 1, "B: fork 1 landed row 1")
    H.log(string.format("field_choice: dlg $%04X A row %d, B row %d, of %d",
      a.dlg, a.row, b.row, a.max))
  end),
})
