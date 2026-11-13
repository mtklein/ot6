-- gen_wob_camp_telstar.lua -- a branch beside SABIN's scenario (#285, docs/design/wob-side-trips.md section 4):
-- boot `camp_intro` (SABIN and SHADOW in the Imperial Camp, map 117) and win the camp's monster box at (17,18)
-- (treasure bit 212, event battle group 32: formation 61, Telstar $044), and the MithrilGlove beside it (19,18),
-- which the route also walks past.  (The Barrier Ring's chest at (15,8) is not on foot from the box's yard: lab
-- camp1 stalled at (18,29) on the walk there.)  No leg boots what it leaves
-- (the state `wob_camp_telstar`); gen_sabin_camp goes on from camp_intro.
local H = dofile("tools/tests/lib/ot6.lua")

local SHADOW, SABIN = 3, 5
local NAMES = { [SHADOW] = "SHADOW", [SABIN] = "SABIN" }
local TWO = { SABIN, SHADOW }
local MAP_CAMP = 117
local FIGHT = { tactical = true, boost = true, items = true, healPercent = 50 }
H.NAV_REFIRE_HOLD = true
local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, say, kitLine = K.map, K.say, K.kitLine

local won = nil
H.run({ maxFrames = 300000 }, {
  H.loadState("build/states/camp_intro.mss.lua"),
  K.watches(),
  H.call(function()
    H.assertEq(map(), MAP_CAMP, "booted in the Imperial Camp (map 117; gen_sabin_camp's camp_intro)")
    say("camp", "boot")
    H.log("[kit] " .. kitLine(TWO))
  end),
  -- @@setup-end

  -- @@stage box
  K.monsterBox({ x = 17, y = 18, bit = 212, form = 61, species = 0x044, what = "the Telstar box (117 (17,18))",
    done = function(line) won = line end }),
  K.chestAt(19, 18, 211, "MithrilGlove", 0xB8),
  H.call(function()
    say("camp", "after the box")
    H.log("[kit] " .. kitLine(TWO))
  end),
  H.saveState("wob_camp_telstar.mss"),
  H.logStep(function()
    return string.format("wob_camp_telstar generated: map %d (%d,%d), SABIN L%d SHADOW L%d, the Telstar box: %s",
      map(), H.fieldX(), H.fieldY(), K.lv(SABIN), K.lv(SHADOW), tostring(won))
  end),
})
