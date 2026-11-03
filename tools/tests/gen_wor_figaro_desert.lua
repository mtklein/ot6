-- gen_wor_figaro_desert.lua -- a branch beside the Falcon arc's first leg, gen_wor_figaro_sweep (#498, the Figaro
-- desert's draw gap; wor-coverage.md section 11): Continue the `wor-edgar-v1` battery (EDGAR, SABIN and CELES on the
-- surfaced castle's tile), then walk a lap of two tiles of the desert around the castle (world group 44) until
-- every formation of its pool is won (K.worldHunt: the list asserted to be the group's pool, the battle bound the
-- pool's worst case): the Sand Horse pair (222), the Sand Horse with two Maligas (223) and the Maliga trio (138), as
-- a player who crosses the desert meets them, and back to the save's tile.  No leg boots what it leaves (the state
-- `wor_figaro_desert`): the hunt's XP stays off the main line, which goes on from the same save (the canon line
-- is the middle path, docs/TESTING.md; model gen_wor_tzen_plain).
-- Nothing is written; every step, menu and fight is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = { [0] = "TERRA", [1] = "LOCKE", [2] = "CYAN", [3] = "SHADOW", [4] = "EDGAR", [5] = "SABIN", [6] = "CELES",
  [7] = "STRAGO", [8] = "RELM", [9] = "SETZER", [10] = "MOG", [11] = "GAU", [12] = "GOGO", [13] = "UMARO" }
local FIGHT = {}
local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local say = K.say
-- the save's tile, south of the castle's doors, which the lap keeps off
local HOME = { 81, 86 }
local DOORS = { { 81, 85 }, { 82, 85 } }
local AV = nil
local function avoid()
  if AV == nil then AV = H.worldAvoidSet(DOORS) end
  return AV
end
local LAPS = {
  { what = "the desert around Figaro Castle (group 44)", lap = { { 81, 88 }, { 81, 89 } },
    forms = { [222] = "Sand Horse x2", [223] = "Sand Horse, Maliga x2", [138] = "Maliga x3" } },
}
local won = {}

local steps = {
  H.bootCheckpoint("wor-edgar-v1"),
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
  steps[#steps + 1] = K.worldHunt({ what = l.what, lap = l.lap, forms = l.forms, won = won, avoid = avoid })
end
steps[#steps + 1] = H.worldNavTo(HOME[1], HOME[2], { maxFrames = 12000, playBattles = "tactical", fight = FIGHT,
  avoid = avoid })
steps[#steps + 1] = H.fieldCare({ threshold = 1.0, tag = "back at the save's tile" })
steps[#steps + 1] = H.call(function() say("wor", "the laps done") end)
steps[#steps + 1] = H.saveState("wor_figaro_desert.mss")
steps[#steps + 1] = H.logStep(function()
  return string.format("wor_figaro_desert generated: %s; every formation of the desert around Figaro Castle (world "
    .. "group 44) won", H.partiesLine())
end)
H.run({ maxFrames = 600000 }, steps)
