-- @suite

-- visual canary for fight 1 (idle): OT6 font cells intact (vs ROM
-- source), the under-monster hud on the bg3 field map, and bp pips in
-- the party window. the ability-list icon assert lives in battle_break,
-- whose drive reliably traverses the list.
--
-- THE PIP HALF READS THE LIVE CELL, NOT ROW 0.  The party window has
-- exactly one bp-pip cell.  Ot6PipStage moves it -- to the active
-- character while a menu is open, to whoever just spent or gained bp for
-- OT6_PIPTAIL frames after -- and the flush blanks the row it leaves to
-- $21ff on the way (ot6_hud.asm @pipline).  So which row holds pips on
-- any one frame is where the line happens to be parked, and this file
-- used to pin row 0 at $2173: it passed on a glyph nothing had blanked
-- yet, the same luck visual_f2 lost when #236 moved its fight by a hair
-- (#240).  It now follows OT6_PIPPREV through H.livePipCell(), the way
-- visual_f2 does, and keeps what it always asked: the opening bank is
-- Ot6InitBP's 1, nobody spends or banks in this idle stretch, so every
-- frame the line is live it must show exactly the one-pip cluster
-- ($2173: Ot6PipCellTbl[1] = $73 under the party-window attribute $21),
-- and it must be live on at least one sampled frame.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"
local ONE_PIP = 0x2173

local pip = { seen = 0, live = 0, good = 0, wrong = nil }
local function samplePip()
  pip.seen = pip.seen + 1
  local row, w = H.livePipCell()
  if row == nil then return end             -- the line is legitimately off
  pip.live = pip.live + 1
  if w == ONE_PIP then
    pip.good = pip.good + 1
  elseif pip.wrong == nil then
    pip.wrong = string.format("row %d holds $%04x", row, w)
  end
end

H.run({ maxFrames = 20000 }, {
  -- this file's own counters, cleared in the body's first call so a retry
  -- starts from zero (the library's state is the library's; #196)
  H.call(function() pip.seen, pip.live, pip.good, pip.wrong = 0, 0, 0, nil end),
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(200),
  H.call(function()
    H.glyphCanary()
    H.assertEq(H.fieldHudPresent(), true, "under-monster hud on the field map")
  end),
  H.repeatN(30, { H.waitFrames(2), H.call(samplePip) }),
  H.call(function()
    H.log(string.format("[pips] %d sample(s); the line was live on %d of them "
      .. "and %d of those showed the one-pip cluster%s", pip.seen, pip.live,
      pip.good, pip.wrong and ("; wrong: " .. pip.wrong) or ""))
    H.assertEq(pip.wrong, nil,
      "every frame the live pip cell was painted it showed 1 spendable bp")
    H.assertEq(pip.good > 0, true,
      "the party window shows 1 spendable bp on the live row")
  end),
})
