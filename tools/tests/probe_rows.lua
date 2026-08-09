-- probe_rows.lua -- drive the real Order screen and flip TERRA and EDGAR into
-- the back row, off a live fixture.  Reads and pad presses only (issue #75).
--
-- The owner's note, 2026-08-09: "a lot of ranged attackers can just sit in
-- the back row forever at no cost."  In this ROM the gap is wider than that
-- -- ExecCmd sets $B3 = $FF for every command and only the weapon swing
-- clears the "ignore attacker row" bit, so Tools, Magic, Blitz, SwdTech,
-- Throw and Steal are ALL row-exempt (battle_main.asm:3131-3133, :7127-7133;
-- docs/research/row-menu.md).  EDGAR fights with Tools and TERRA with Magic,
-- so the back row costs them nothing and halves the physical damage they
-- take.  LOCKE's only damage is Fight, so he stays in front.
--
-- This is the falsification the research asked for: log $26 and the row bit
-- across a real toggle and check it against the documented path.
--
-- Run it directly:
--   OT6_KEEP_RUNS=1 OT6_NO_PUBLISH=1 tools/tests/run.sh tools/tests/probe_rows.lua
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_doorstep.mss.lua"

local function rowOf(c) return (H.readByte(0x1850 + c) & 0x20) ~= 0 end
local function line()
  local out = {}
  for _, c in ipairs(H.partyMembers()) do
    out[#out + 1] = string.format("c%d=%s", c, rowOf(c) and "back" or "front")
  end
  return table.concat(out, " ")
end

H.run({ maxFrames = 40000 }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 600, "field control", 5),
  H.call(function()
    H.log("rows before: " .. line())
    H.screenshot("rows_before")
  end),

  H.setRows({ [0] = true, [4] = true, [1] = false }, { tag = "rows" }),

  H.call(function()
    H.log("rows after: " .. line())
    H.screenshot("rows_after")
    H.assertEq(rowOf(0), true, "TERRA is in the back row (Magic is exempt)")
    H.assertEq(rowOf(4), true, "EDGAR is in the back row (Tools are exempt)")
    H.assertEq(rowOf(1), false, "LOCKE stays in front -- Fight is all he has")
    H.assertEq(H.hasControl() and H.tileAligned(), true,
      "the menu is closed and the party has control back")
    -- the party is still the party: a mis-aimed second A would have
    -- REORDERED it instead of flipping a row (field_menu.asm:1859-1870)
    H.assertEq((H.readByte(0x1850) & 0x07) ~= 0, true, "TERRA still in party")
    H.assertEq((H.readByte(0x1851) & 0x07) ~= 0, true, "LOCKE still in party")
    H.assertEq((H.readByte(0x1854) & 0x07) ~= 0, true, "EDGAR still in party")
  end),

  -- idempotence: a second call must not open the menu at all
  H.setRows({ [0] = true, [4] = true, [1] = false }, { tag = "rows again" }),
  H.call(function()
    H.log("rows still: " .. line())
    H.assertEq(rowOf(0) and rowOf(4) and not rowOf(1), true,
      "a second setRows left everything alone")
  end),
})
