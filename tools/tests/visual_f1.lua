-- @suite

-- visual canary for fight 1 (idle): OT6 font cells intact (vs ROM
-- source), the under-monster hud on the bg3 field map, and bp pips in
-- the party window. the ability-list icon assert lives in battle_break,
-- whose drive reliably traverses the list.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"
H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(200),
  H.call(function()
    H.glyphCanary()
    H.assertEq(H.fieldHudPresent(), true, "under-monster hud on the field map")
    H.assertEq(H.pipWord(), 0x2173, "party row 1 shows 1 spendable bp")
  end),
})
