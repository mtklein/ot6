-- gen_wob_train_specter.lua -- a branch beside gen_sabin_train's end (#285, docs/design/wob-towns-boxes.md
-- section 4): boot the graph's capture `train_b68_entry` (SABIN, CYAN and SHADOW on the Phantom Train's front cars,
-- map 141 (38,9), before the smokestack's fight), in by the rooms car's door 141 (48,8) -> 153 (8,11), which
-- gen_sabin_train walks past, and win its monster box at 153 (22,24) (treasure bit 243, event battle group 34:
-- formation 476, Specter $156 alone).  No leg boots what it leaves (the state `wob_train_specter`).
local H = dofile("tools/tests/lib/ot6.lua")

local CYAN, SHADOW, SABIN = 2, 3, 5
local NAMES = { [CYAN] = "CYAN", [SHADOW] = "SHADOW", [SABIN] = "SABIN" }
local FIGHT = { tactical = true, boost = true, items = true, healPercent = 50 }
H.NAV_REFIRE_HOLD = true
local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, lv, say, kitLine, settled = K.map, K.lv, K.say, K.kitLine, K.settled
local MAP_CARS, MAP_ROOMS = 141, 153
-- the front cars' other doors and triggers (gen_wob_train_hunt's), kept off the walk to (48,8)
local CAR_DOORS = { { 91, 8 }, { 100, 8 }, { 109, 8 }, { 59, 8 }, { 103, 8 }, { 116, 8 }, { 82, 8 }, { 75, 8 },
  { 66, 8 }, { 38, 8 }, { 31, 7 }, { 55, 8 } }
-- the rooms car's own triggers (route_data.py map 153), off the walk to the box
local ROOM_TRIGGERS = { { 23, 29 }, { 23, 12 }, { 8, 29 }, { 5, 25 }, { 8, 9 }, { 8, 12 } }
local function seated()
  local t = {}
  for _, ch in ipairs({ SABIN, CYAN, SHADOW }) do if K.partyOf(ch) == 1 then t[#t + 1] = ch end end
  return t
end

local won = nil
H.run({ maxFrames = 600000 }, {
  H.loadState("build/states/train_b68_entry.mss.lua"),
  K.watches(),
  H.call(function()
    say("wob", "boot")
    H.log("[kit] " .. kitLine(seated()))
    H.assertEq(map(), MAP_CARS, "the boot stands on the train's front cars (141): gen_sabin_train's train_b68_entry")
  end),
  -- @@setup-end

  -- @@stage rooms
  H.navTo(48, 8, { maxFrames = 16000, playBattles = "tactical", fight = FIGHT, avoid = CAR_DOORS,
    arrive = function() return map() == MAP_ROOMS end }),
  H.advanceStory(function() return map() == MAP_ROOMS and settled() end, 6000,
    { playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("route", "141 (48,8) -> the rooms car 153") end),

  -- @@stage box
  K.monsterBox({ x = 22, y = 24, bit = 243, form = 476, species = 0x156, what = "the Specter box (153 (22,24))",
    avoid = ROOM_TRIGGERS, done = function(line) won = line end }),
  H.call(function()
    say("wob", "after the box")
    H.log("[kit] " .. kitLine(seated()))
  end),
  H.saveState("wob_train_specter.mss"),
  H.logStep(function()
    return string.format("wob_train_specter generated: SABIN L%d, CYAN L%d, SHADOW L%d on map %d (%d,%d); the "
      .. "Specter box: %s", lv(SABIN), lv(CYAN), lv(SHADOW), map(), H.fieldX(), H.fieldY(), tostring(won))
  end),
})
