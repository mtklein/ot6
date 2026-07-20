-- gen_reunion_ready.lua -- the FULL STACK's acceptance gate, gen_two_done's
-- shape one layer up: boot the t3_ chain's ending (t3_reunion_ready, minted
-- by gen_terra_done's reunion fork on the all-three boot) and prove ONE
-- playthrough now carries ALL THREE scenario completions plus the reunion.
-- Mints:
--   reunion_ready.mss  map 22 (20,9), the Battle-for-Narshe staging, first
--                      controllable frame after the reunion cutscene --
--                      the canonical boot for gen_narshe_battle.
--
-- The stack under this state: locke_done (honest, $001E) -> s2_ = SABIN's
-- whole chain replayed on top of it ($0044) -> t3_ = TERRA/BANON's chain
-- replayed on top of that ($0021) -- and with all three set, _ccb3fa's hub
-- return opened the if_all at event_main.asm:26654 and rode _caadb9's
-- reunion ("The three have reached Narshe...") to the map-22 staging
-- instead of the hub.  This file is where the combined claim is ASSERTED
-- rather than implied by construction; the mint is a re-save of the same
-- controllable moment under the canonical name, ~0 replay cost.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STACKED = "/Users/mtklein/ot6/build/states/t3_reunion_ready.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end

H.run({ maxFrames = 2000 }, {
  H.loadState(STACKED),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 22, "on map 22, the battlefield staging")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    H.assertEq(sw(0x001E), 1, "$001E SET -- LOCKE's scenario (the honest base)")
    H.assertEq(sw(0x0044), 1, "$0044 SET -- SABIN's scenario (the s2_ layer)")
    H.assertEq(sw(0x0021), 1, "$0021 SET -- TERRA/BANON's (the t3_ layer)")
    H.assertEq(sw(0x0045), 1, "$0045 SET -- the reunion has played")
    H.log(string.format(
      "[reunion_ready] f%d map=%d (%d,%d) $001E=%d $0044=%d $0021=%d $0045=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), sw(0x001E), sw(0x0044),
      sw(0x0021), sw(0x0045)))
    H.screenshot("reunion_ready")
  end),
  H.saveState("reunion_ready.mss"),
  H.logStep(function()
    return string.format("reunion_ready minted at frame %d -- three "..
      "scenarios, one playthrough, the Battle for Narshe next", H.frame)
  end),
})
