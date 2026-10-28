-- gen_wor_island_plain.lua -- a branch beside the World of Ruin's first leg, gen_wor_start (#488, the early continent's draw gaps; wor-coverage.md
-- section 11): Continue the `wor-island-v1` battery (CELES alone on the Solitary Island's World of Ruin tile, before Cid's fish), then walk a lap of two tiles in each of the island's ground (world group 29)
-- until every formation of its pool is won (K.worldHunt: the list asserted to be the group's pool, the battle
-- bound the pool's worst case), as a player who pauses there meets them, and back to the save's tile.  No leg
-- boots what it leaves (the state `wor_island_plain`): the hunts' XP stays off the main line, which goes on from
-- the same save (the coordinator's rule for v0.38's sweeps, model gen_wor_thamasa_plain).
-- Nothing is written; every step, menu and fight is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = { [0] = "TERRA", [1] = "LOCKE", [2] = "CYAN", [3] = "SHADOW", [4] = "EDGAR", [5] = "SABIN", [6] = "CELES",
  [7] = "STRAGO", [8] = "RELM", [9] = "SETZER", [10] = "MOG", [11] = "GAU", [12] = "GOGO", [13] = "UMARO" }
local FIGHT = {}
local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local say = K.say
-- the save's tile, and the doors the laps keep off
local HOME = { 76, 239 }
local DOORS = { { 76, 240 } }
local LAPS = {
  { what = "the Solitary Island (group 29)", lap = { { 75, 236 }, { 75, 235 } },
    forms = { [192] = "Peepers x2", [193] = "Peepers x3" } },
}
local won = {}

local steps = {
  H.bootCheckpoint("wor-island-v1"),
  K.watches(),
  H.call(function()
    say("wor", "boot")
    H.assertEq(H.worldMode() and H.worldX() == HOME[1] and H.worldY() == HOME[2], true,
      string.format("booted on the World of Ruin map at the save's tile (%d,%d)", HOME[1], HOME[2]))
  end),
  -- @@setup-end
  H.fieldCare({ threshold = 1.0, tag = "before the laps" }),
}
for _, l in ipairs(LAPS) do
  steps[#steps + 1] = K.worldHunt({ what = l.what, lap = l.lap, forms = l.forms, won = won,
    avoid = H.worldAvoidSet(DOORS) })
end
steps[#steps + 1] = H.worldNavTo(HOME[1], HOME[2], { maxFrames = 12000, playBattles = "tactical", fight = FIGHT,
  avoid = H.worldAvoidSet(DOORS) })
steps[#steps + 1] = H.fieldCare({ threshold = 1.0, tag = "back at the save's tile" })
steps[#steps + 1] = H.call(function() say("wor", "the laps done") end)
steps[#steps + 1] = H.saveState("wor_island_plain.mss")
steps[#steps + 1] = H.logStep(function()
  return string.format("wor_island_plain generated: %s; every formation of the island's ground (world group 29) won", H.partiesLine())
end)
H.run({ maxFrames = 600000 }, steps)
