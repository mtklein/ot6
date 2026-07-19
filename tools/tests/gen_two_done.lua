-- gen_two_done.lua -- the scenario STACK's acceptance gate: boot the
-- stacked Terra ending (t2_terra_done, minted by the Terra chain replayed
-- on top of locke_done via OT6_STACK=t2_) and prove ONE playthrough now
-- carries BOTH completions.  Mints:
--   two_done.mss  map 9 (8,3), SCENARIO_MOG alone, controllable, with
--                 $001E AND $0021 both set -- the state no single honest
--                 chain could reach, and the canonical boot for anything
--                 that wants "two scenarios down, Sabin's to go".
--
-- WHY A SEPARATE GENERATOR RATHER THAN NAMING t2_terra_done "two_done":
-- the stack rewrite is mechanical (every basename gets the prefix), so the
-- stacked chain's own artifacts all carry t2_.  This file is the one place
-- the combined claim is ASSERTED rather than implied by construction --
-- if the stack ever silently replayed the wrong boot (the exact failure
-- class compose.py's selftest guards), the honest chain would still mint a
-- t2_terra_done and only these asserts would catch that its flags are
-- wrong.  The mint itself is a re-save of the same controllable moment
-- under the canonical name, ~0 replay cost.
--
-- WHAT THE HUB LOOKS LIKE HERE (all facts from the honest endpoints):
--  * _caad4c reloaded map 9 with SCENARIO_MOG at (8,3) facing DOWN and
--    played _caadb4's "Choose a scenario…kupo!" -- NOT the reunion: the
--    if_all at event_main.asm:26654 needs $0044 too.
--  * LOCKE's hub NPC is gone ($0329=0, cleared by his own ending) and so
--    are BANON/TERRA/EDGAR's ($032B/C/D=0, _ccb3fa:104956-104958); only
--    SABIN's remains ($032A=1) -- the hub is down to ONE choice.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STACKED = "/Users/mtklein/ot6/build/states/t2_terra_done.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end

H.run({ maxFrames = 2000 }, {
  H.loadState(STACKED),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 9, "on map 9, the scenario hub")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    H.assertEq(sw(0x001E), 1, "$001E SET -- LOCKE's scenario complete (from the boot)")
    H.assertEq(sw(0x0021), 1, "$0021 SET -- TERRA/BANON's complete (this chain)")
    H.assertEq(sw(0x0044), 0, "$0044 clear -- SABIN's scenario still open")
    H.assertEq(sw(0x0329), 0, "$0329 clear -- LOCKE's hub NPC gone")
    H.assertEq(sw(0x032B), 0, "$032B clear -- BANON's hub NPC gone")
    H.assertEq(sw(0x032C), 0, "$032C clear -- TERRA's gone")
    H.assertEq(sw(0x032D), 0, "$032D clear -- EDGAR's gone")
    H.assertEq(sw(0x032A), 1, "$032A set -- SABIN's NPC is the one choice left")
    H.assertEq((H.readByte(0x185d) & 0x07) ~= 0, true, "SCENARIO_MOG is the party")
    H.log(string.format("[two_done] f%d map=%d (%d,%d) $001E=%d $0021=%d $0044=%d",
      H.frame, map(), H.fieldX(), H.fieldY(),
      sw(0x001E), sw(0x0021), sw(0x0044)))
    H.screenshot("two_done")
  end),
  H.saveState("two_done.mss"),
  H.logStep(function()
    return string.format("two_done minted at frame %d -- two scenarios in one playthrough", H.frame)
  end),
})
