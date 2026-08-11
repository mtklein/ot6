-- probe_fieldcare.lua -- exercise H.fieldCare on the exact party the
-- input-driven Mt. Kolts route currently delivers: TERRA dead at 0/94,
-- LOCKE untouched, EDGAR on 1/145, five Tonics and seven Potions in the bag
-- and NO Fenix Down.  Reads and pad presses only (issue #75).
--
-- What this pins down:
--   * EDGAR is healed through the real Item -> use -> target windows;
--   * TERRA is NOT, and the driver says so once and moves on instead of
--     mashing A at a window the game will never accept -- there is no Fenix
--     Down to raise her with, and CheckCanUseItem refuses everything else
--     on a KO'd target (item.asm:2243-2330);
--   * the menu is left closed with the party back in control.
--
-- Run it directly:
--   OT6_KEEP_RUNS=1 OT6_NO_PUBLISH=1 tools/tests/run.sh tools/tests/probe_fieldcare.lua
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vargas_doorstep.mss.lua"

local function line()
  local out = {}
  for _, c in ipairs(H.partyMembers()) do
    out[#out + 1] = string.format("c%d %d/%d", c, H.charHp(c), H.charMaxHp(c))
  end
  return string.format("%s | tonic=%d potion=%d fenix=%d",
    table.concat(out, " "), H.invCountOf(0xE8), H.invCountOf(0xE9),
    H.invCountOf(0xF0))
end

local before = {}

H.run({ maxFrames = 60000 }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 600, "field control", 5),
  H.call(function()
    H.log("before: " .. line())
    for _, c in ipairs(H.partyMembers()) do before[c] = H.charHp(c) end
    H.assertEq(H.charHp(0), 0, "TERRA is down at the entry point")
    H.assertEq(H.invCountOf(0xF0), 0, "and there is no Fenix Down to raise her")
    H.screenshot("care_before")
  end),

  H.fieldCare({ tag = "kolts care", threshold = 0.9, reserve = { [0xE9] = 3 } }),

  H.call(function()
    H.log("after: " .. line())
    H.screenshot("care_after")
    H.assertEq(H.charHp(4) > before[4], true,
      "EDGAR was healed through the real item menu")
    H.assertEq(H.charHp(4) >= H.charMaxHp(4) * 0.9, true,
      string.format("EDGAR is back above 90%% (%d/%d)",
        H.charHp(4), H.charMaxHp(4)))
    H.assertEq(H.charHp(0), 0, "TERRA is still down -- nothing could raise her")
    H.assertEq(H.invCountOf(0xE9) >= 3, true,
      "the Potion reserve was respected")
    H.assertEq(H.hasControl() and H.tileAligned(), true,
      "the menu is closed and the party has control back")
  end),
})
