-- gen_wor_tzen_plain.lua -- a branch beside the Sabin arc's last leg, gen_wor_nikeah (#488, the early continent's draw gaps; wor-coverage.md
-- section 11): Continue the `wor-sabin-v1` battery (CELES and SABIN one step east of Tzen's door), then walk a lap of two tiles in each of the forest west of Tzen (world group 33)
-- until every formation of its pool is won (K.worldHunt: the list asserted to be the group's pool, the battle
-- bound the pool's worst case), as a player who pauses there meets them, and back to the save's tile.  No leg
-- boots what it leaves (the state `wor_tzen_plain`): the hunts' XP stays off the main line, which goes on from
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
local HOME = { 131, 179 }
local DOORS = { { 130, 179 }, { 141, 209 }, { 140, 209 } }
-- the desert beside Tzen's door (world group 36, the Black Drgn's) is kept off on the way to the lap
local OFF = { group = 36, box = { 118, 160, 159, 223 } }
local AV = nil
local function avoid()
  if AV == nil then
    local list = {}
    for _, d in ipairs(DOORS) do list[#list + 1] = d end
    if OFF then
      for y = OFF.box[2], OFF.box[4] do for x = OFF.box[1], OFF.box[3] do
        if H.worldEncounterGroup(x, y, x, y) == OFF.group then list[#list + 1] = { x, y } end
      end end
    end
    AV = H.worldAvoidSet(list)
  end
  return AV
end
local LAPS = {
  { what = "the forest west of Tzen (group 33)", lap = { { 127, 182 }, { 127, 183 } },
    forms = { [203] = "Lunaris x2", [201] = "Chitonid, Gigan Toad x2" } },
}
local won = {}

local steps = {
  H.bootCheckpoint("wor-sabin-v1"),
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
    avoid = avoid })
end
steps[#steps + 1] = H.worldNavTo(HOME[1], HOME[2], { maxFrames = 12000, playBattles = "tactical", fight = FIGHT,
  avoid = avoid })
steps[#steps + 1] = H.fieldCare({ threshold = 1.0, tag = "back at the save's tile" })
steps[#steps + 1] = H.call(function() say("wor", "the laps done") end)
steps[#steps + 1] = H.saveState("wor_tzen_plain.mss")
steps[#steps + 1] = H.logStep(function()
  return string.format("wor_tzen_plain generated: %s; every formation of the forest west of Tzen (world group 33) won", H.partiesLine())
end)
H.run({ maxFrames = 600000 }, steps)
