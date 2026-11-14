-- gen_wob_train_specter.lua -- a branch beside gen_sabin_train's end (#285, docs/design/wob-towns-boxes.md
-- section 4): boot the graph's capture `train_b68_entry` (SABIN, CYAN and SHADOW on the Phantom Train's front cars,
-- map 141 (38,9), before the smokestack's fight), back through the passenger car's door 141 (59,8) into the
-- hallway (151, gen_wob_train_hunt's way in), and through the hallway's compartment doors (19,7) and (9,7)
-- (_cba6bd, _cba6ca: into 153 at (8,28), (23,11) or (23,28) by the car's $017E) until the compartment with the
-- monster box at 153 (22,24) is the one the party stands in (lab: from 141 (48,8) the party lands in 153's
-- corridor, (8,11), where no side of the box is on foot).  Win the box (treasure bit 243, event battle group 34:
-- formation 476, Specter $156 alone).  No leg boots what it leaves (the state `wob_train_specter`).
local H = dofile("tools/tests/lib/ot6.lua")

local CYAN, SHADOW, SABIN = 2, 3, 5
local NAMES = { [CYAN] = "CYAN", [SHADOW] = "SHADOW", [SABIN] = "SABIN" }
local FIGHT = { tactical = true, boost = true, items = true, healPercent = 50 }
H.NAV_REFIRE_HOLD = true
local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, lv, say, kitLine, settled = K.map, K.lv, K.say, K.kitLine, K.settled
local MAP_CARS, MAP_HALL, MAP_ROOMS = 141, 151, 153
local HALL_TRIGGERS = { { 26, 8 }, { 26, 9 }, { 1, 8 }, { 1, 9 }, { 19, 7 }, { 9, 7 } }
-- the front cars' other doors and triggers (gen_wob_train_hunt's and the rooms car's (48,8)), off the walk to (59,8)
local CAR_DOORS = { { 91, 8 }, { 100, 8 }, { 109, 8 }, { 103, 8 }, { 116, 8 }, { 82, 8 }, { 75, 8 },
  { 66, 8 }, { 38, 8 }, { 31, 7 }, { 48, 8 } }
-- the compartments' own triggers (route_data.py map 153): (23,29), (23,12) and (8,29) lead back to the hallway
local ROOM_EXITS = { { 23, 29 }, { 23, 12 }, { 8, 29 } }
local ROOM_TRIGGERS = { { 23, 29 }, { 23, 12 }, { 8, 29 }, { 5, 25 }, { 8, 9 }, { 8, 12 } }
local function boxSide()
  for _, d in ipairs({ { 0, 1 }, { -1, 0 }, { 1, 0 }, { 0, -1 } }) do
    if H.bfsPath(22 + d[1], 24 + d[2]) then return true end
  end
  return false
end
-- one compartment door: in, and back out to the hallway unless the box is on foot there
local tried = {}
local function compartment(door)
  return H.cond(function() return map() == MAP_HALL end, {
    -- the door is in the hallway's wall: crossDoor stages below it and holds up (its landing depends on $017E)
    H.crossDoor(door[1], door[2], MAP_ROOMS, -1, -1, string.format("the hallway's door 151 (%d,%d) -> 153",
      door[1], door[2]), { fight = FIGHT }),
    H.advanceStory(function() return map() == MAP_ROOMS and settled() end, 6000,
      { playBattles = "tactical", fight = FIGHT }),
    H.call(function()
      tried[#tried + 1] = string.format("(%d,%d) -> 153 (%d,%d): box %s", door[1], door[2], H.fieldX(), H.fieldY(),
        boxSide() and "on foot" or "not on foot")
      say("route", "hallway door " .. tried[#tried])
    end),
    H.cond(function() return not boxSide() end, {
      H.lazy(function()
        for _, t in ipairs(ROOM_EXITS) do
          if H.bfsPath(t[1], t[2]) then
            return H.navTo(t[1], t[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
              arrive = function() return map() == MAP_HALL end })
          end
        end
        error("153: no way back to the hallway from (" .. H.fieldX() .. "," .. H.fieldY() .. ")")
      end),
      H.advanceStory(function() return map() == MAP_HALL and settled() end, 6000,
        { playBattles = "tactical", fight = FIGHT }),
      H.navTo(4, 8, { maxFrames = 3000, avoid = HALL_TRIGGERS }),
    }, {}),
  }, {})
end
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
  H.navTo(59, 8, { maxFrames = 16000, playBattles = "tactical", fight = FIGHT, avoid = CAR_DOORS,
    arrive = function() return map() == MAP_HALL end }),
  H.waitUntil(function() return map() == MAP_HALL and settled() end, 4000, "the hallway, map 151", 5),
  H.navTo(4, 8, { maxFrames = 3000, avoid = HALL_TRIGGERS }),
  H.fieldCare({ threshold = 1.0, tag = "in the hallway" }),
  compartment({ 19, 7 }),
  compartment({ 9, 7 }),
  H.call(function()
    H.log("[route] compartments: " .. table.concat(tried, "; "))
    H.assertEq(map() == MAP_ROOMS and boxSide(), true, "the box's compartment reached through the hallway's doors")
  end),

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
