-- @suite

-- visual canary for fight 2 (second formation): same checks as fight 1,
-- run again after an attack round since effect art loads mid-fight.
--
-- WHAT THE PIP HALF ASKS, AND WHY IT IS NOT "ROW 0".  The party window has
-- exactly ONE bp-pip cell.  Ot6PipStage moves it -- to the active character
-- while a menu is open, to whoever just spent or gained bp for OT6_PIPTAIL
-- frames after their action resolves -- and the flush blanks the row it
-- leaves to $21ff on the way ("one cell can only show one row",
-- ot6_hud.asm).  So which row holds pips on any one frame is where the line
-- happened to be parked, not a property of the HUD, and this file used to
-- read row 0: it passed on a glyph nothing had blanked yet, and went red
-- the day #236 moved the fight by a hair and WEDGE's pip gain pulled the
-- cell to row 2 four frames before the sample (measured:
-- build/attempts/<branch>/attempts/bisect/lab-probe_pips.log, "f1454 ...
-- tail=25 slot=2 cur=$78b4 cell=$2175 word=$21ff", the $21ff being row 0
-- blanked behind the move -- and the pre-merge ROM, with this fixture's
-- chain regenerated on it, passing at the very same frame).
--
-- What the canary is for is that effect art has not clobbered the OT6 font
-- cells and that the HUD is still drawing bp.  That is asked here as: over
-- this stretch the live cell was painted at least once, everything painted
-- into it was a pip cluster or the boost arrow, and never junk.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle2_entry.mss.lua"

local pip = { seen = 0, live = 0, good = 0, junk = nil }
local function samplePip()
  pip.seen = pip.seen + 1
  local row, w = H.livePipCell()
  if row == nil then return end             -- the line is legitimately off
  pip.live = pip.live + 1
  if H.isPipGlyph(w) or H.isArrowGlyph(w) then
    pip.good = pip.good + 1
  elseif pip.junk == nil then
    pip.junk = string.format("row %d holds $%04x", row, w)
  end
end
local function pipVerdict(what)
  H.log(string.format("[pips] %s: %d sample(s); the line was live on %d of "
    .. "them and %d of those showed a pip cluster or the boost arrow%s",
    what, pip.seen, pip.live, pip.good,
    pip.junk and ("; junk: " .. pip.junk) or ""))
  H.assertEq(pip.junk, nil,
    what .. ": everything painted into the live pip cell is an OT6 cluster")
  H.assertEq(pip.good > 0, true, what)
  pip.seen, pip.live, pip.good, pip.junk = 0, 0, 0, nil
end

H.run({ maxFrames = 20000 }, {
  -- this file's own counters, cleared in the body's first call so a retry
  -- starts from zero (the library's state is the library's; #196)
  H.call(function() pip.seen, pip.live, pip.good, pip.junk = 0, 0, 0, nil end),
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 8000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle 2 load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle 2 active", 30),
  H.waitFrames(200),
  H.call(function()
    H.screenshot("visual_f2_idle")
    H.glyphCanary()
    H.assertEq(H.fieldHudPresent(), true, "under-monster hud on the field map")
    -- the species override table takes precedence over the level formula:
    -- lobos seed 3
    H.assertEq(H.readByte(0x3e40), 3, "lobo shields come from the species table")
  end),
  H.repeatN(30, { H.waitFrames(2), H.call(samplePip) }),
  H.call(function() pipVerdict("the party window shows bp pips") end),
  H.pressButtons({ "a" }, 6), H.waitFrames(30),
  H.pressButtons({ "a" }, 6), H.waitFrames(30),
  H.pressButtons({ "a" }, 6),
  -- the same 600 frames this step always spent, sampled instead of slept
  H.repeatN(60, { H.waitFrames(10), H.call(samplePip) }),
  H.call(function()
    H.screenshot("visual_f2_after_action")
    H.glyphCanary()   -- effect art must not clobber our font cells
    local alive = false
    for slot = 0, 5 do
      -- the hud draws cells only for monsters that are present and not
      -- dead: match the builder's own criterion ($3aa8 bit 0, $3eec $c2
      -- clear)
      if (H.readByte(0x3aa8 + slot*2) & 1) == 1
        and (H.readByte(0x3eec + slot*2) & 0xc2) == 0 then alive = true end
    end
    -- the premise is asserted: this file stages a fight precisely so the
    -- HUD has somebody to draw.
    H.assertEq(alive, true,
      "a monster survived the attack round (premise: the headline HUD " ..
      "check below must run, not be skipped by a double kill)")
    H.assertEq(H.fieldHudPresent(), true, "hud survives the attack round")
    pipVerdict("pips survive the attack round")
  end),
})
