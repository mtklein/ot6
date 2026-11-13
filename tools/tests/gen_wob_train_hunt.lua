-- gen_wob_train_hunt.lua -- a branch beside gen_sabin_train's end (docs/design/wob-side-trips.md, #286): boot the
-- graph's capture `train_b68_entry` (SABIN, CYAN and SHADOW on the Phantom Train's front cars, map 141 (38,9),
-- before the smokestack's fight), step back through the passenger car's door 141 (59,8) into the hallway (151,
-- group 72: Bomb, Hazer, Whisper, StillGoing), which gen_sabin_train never enters, and walk a lap there until every
-- formation of its pool has been won (K.hunt, lib/ot6_field.lua: the pool asserted against the ROM's, the hunt
-- bounded by the worst draws).  No leg boots what it leaves (the state `wob_train_hunt`).
local H = dofile("tools/tests/lib/ot6.lua")

local CYAN, SHADOW, SABIN = 2, 3, 5
local NAMES = { [CYAN] = "CYAN", [SHADOW] = "SHADOW", [SABIN] = "SABIN" }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, lv, say, kitLine, watches, settled = K.map, K.lv, K.say, K.kitLine, K.watches, K.settled
local won = {}
local MAP_CARS, MAP_HALL = 141, 151
-- the hallway's step-on events (route_data map 151): its two ends and its two compartment doors
local HALL_TRIGGERS = { { 26, 8 }, { 26, 9 }, { 1, 8 }, { 1, 9 }, { 19, 7 }, { 9, 7 } }
local HALL = { [72] = "Bomb x2, Hazer x2", [80] = "Whisper, StillGoing, Hazer x2", [90] = "Whisper" }
local function seated()
  local t = {}
  for _, ch in ipairs({ SABIN, CYAN, SHADOW }) do if K.partyOf(ch) == 1 then t[#t + 1] = ch end end
  return t
end

H.run({ maxFrames = 1500000 }, {
  H.loadState("build/states/train_b68_entry.mss.lua"),
  watches(),
  H.call(function()
    say("wob", "boot")
    H.log("[kit] " .. kitLine(seated()))
    H.assertEq(map(), MAP_CARS, "the boot stands on the train's front cars (141): gen_sabin_train's train_b68_entry")
  end),
  -- @@setup-end
  -- the passenger car's door (_cba694: 141 (59,8) -> 151 (2,8))
  H.navTo(59, 8, { maxFrames = 16000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_HALL end }),
  H.waitUntil(function() return map() == MAP_HALL and settled() end, 4000, "the hallway, map 151", 5),
  H.call(function()
    say("route", "141 (59,8) -> the hallway 151")
    H.assertEq(H.bfsPath(3, 8) ~= nil and H.bfsPath(4, 8) ~= nil, true, "the hallway's lap (3,8)-(4,8) is walkable")
  end),
  H.navTo(3, 8, { maxFrames = 3000, avoid = HALL_TRIGGERS }),
  H.fieldCare({ threshold = 1.0, tag = "before the hallway (group 72)" }),
  K.hunt({ what = "the train's hallway (151, group 72)", lap = { { 3, 8 }, { 4, 8 } }, forms = HALL, won = won,
    avoid = HALL_TRIGGERS }),
  H.fieldCare({ threshold = 1.0, tag = "after the hallway" }),
  H.call(function() H.log("[kit] " .. kitLine(seated())) end),
  H.saveState("wob_train_hunt.mss"),
  H.logStep(function()
    local t = {}
    for f in pairs(won) do t[#t + 1] = f end
    table.sort(t)
    for i, f in ipairs(t) do t[i] = tostring(f) end
    return string.format("wob_train_hunt generated: SABIN L%d, CYAN L%d, SHADOW L%d on map %d (%d,%d); formations "
      .. "won: %s", lv(SABIN), lv(CYAN), lv(SHADOW), map(), H.fieldX(), H.fieldY(), table.concat(t, " "))
  end),
})
