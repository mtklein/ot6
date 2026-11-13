-- gen_wob_forest_hunt.lua -- a branch beside gen_sabin_forest (docs/design/wob-side-trips.md, #286): Continue the
-- `camp-escaped-v1` battery (SABIN, CYAN and SHADOW on the World of Balance at (179,71), the Imperial Camp behind
-- them) and walk the Phantom Forest's two pools until every formation of each has been won (K.hunt,
-- lib/ot6_field.lua: the pool asserted against the ROM's, the hunt bounded by the worst draws): the forest's first
-- clearing, 132 (group 68: Ghost, Poplium; the pool of the springs, 130 and 133, too), and the fork past the
-- spring, 134 (group 69).  gen_sabin_forest walks the same maps on the way to the train and leaves formations to
-- the draw.  No leg boots what it leaves (the state `wob_forest_hunt`); gen_sabin_forest goes on from the same
-- save.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CYAN, SHADOW, SABIN = 2, 3, 5
local NAMES = { [CYAN] = "CYAN", [SHADOW] = "SHADOW", [SABIN] = "SABIN" }
local THREE = { SABIN, CYAN, SHADOW }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, lv, say, kitLine, watches, settled, sw = K.map, K.lv, K.say, K.kitLine, K.watches, K.settled, K.sw
local won = {}

-- through an exit tile: navTo it until the map is `dst`, then settle
local function cross(tx, ty, dst, what)
  return H.seqStep({
    H.navTo(tx, ty, { maxFrames = 16000, playBattles = "tactical", fight = FIGHT,
      arrive = function() return map() == dst end }),
    H.waitUntil(function() return map() == dst and settled() end, 4000, what, 5),
    H.call(function() say("route", what) end),
  })
end
local CLEARING = { [65] = "Ghost", [68] = "Ghost, Poplium x2" }
local FORK = { [66] = "Ghost x3", [69] = "Ghost x2, Poplium x3" }

H.run({ maxFrames = 2000000 }, {
  H.bootCheckpoint("camp-escaped-v1"),
  watches(),
  H.call(function()
    say("wob", "boot")
    H.log("[kit] " .. kitLine(THREE))
    for _, ch in ipairs(THREE) do
      H.assertEq(K.partyOf(ch), 1, string.format("%s is seated (camp-escaped-v1: gen_sabin_magitek's party)",
        NAMES[ch]))
    end
  end),
  -- @@setup-end
  -- the world into the forest (gen_sabin_forest's)
  H.worldNavTo(178, 82, { maxFrames = 25000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return not H.worldMode() end }),
  H.waitUntil(function() return map() == 132 and settled() end, 4000, "the Phantom Forest, map 132", 5),
  H.call(function()
    H.assertEq(H.fieldX() == 1 and H.fieldY() == 9, true, "map 132's arrival tile (1,9)")
    -- the lap is the arrival and the tile east of it: the west edge (0,9) is the way out
    H.assertEq(H.bfsPath(2, 9) ~= nil and #H.bfsPath(2, 9) == 1, true, "(2,9) is one step from the arrival")
  end),
  H.fieldCare({ threshold = 1.0, tag = "before the clearing (group 68)" }),
  K.hunt({ what = "the forest's clearing (132, group 68)", lap = { { 1, 9 }, { 2, 9 } }, forms = CLEARING,
    won = won }),
  H.fieldCare({ threshold = 1.0, tag = "after the clearing" }),
  -- 132 -> 133, the spring's conveyor (stepping UP onto (3,12) carries the party past the back exit), 133 -> 134
  cross(28, 7, 133, "132 (28,7) -> 133"),
  H.driveUntil(function() return sw(0x0192) == 1 and map() == 133 and settled() end, 8000, {
    H.call(function()
      if H.dialogWaiting() then H.setPad((H.frame % 8) < 4 and { "a" } or {}); return end
      if H.eventRunning() or not H.hasControl() then H.setPad({}); return end
      H.setPad({ up = true })
    end),
  }, "map 133's spring"),
  H.release(),
  cross(20, 14, 134, "133 (20,14) -> 134"),
  -- 134's arrival (5,8) is under the back exit (5,7); the lap is two tiles east along the row gen_sabin_forest
  -- walks to (11,8)
  H.navTo(8, 8, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
  H.fieldCare({ threshold = 1.0, tag = "before the fork (group 69)" }),
  K.hunt({ what = "the forest's fork (134, group 69)", lap = { { 8, 8 }, { 9, 8 } }, forms = FORK, won = won }),
  H.fieldCare({ threshold = 1.0, tag = "after the fork" }),
  H.call(function() H.log("[kit] " .. kitLine(THREE)) end),
  H.saveState("wob_forest_hunt.mss"),
  H.logStep(function()
    local t = {}
    for f in pairs(won) do t[#t + 1] = f end
    table.sort(t)
    for i, f in ipairs(t) do t[i] = tostring(f) end
    return string.format("wob_forest_hunt generated: SABIN L%d, CYAN L%d, SHADOW L%d on map %d (%d,%d); formations "
      .. "won: %s", lv(SABIN), lv(CYAN), lv(SHADOW), map(), H.fieldX(), H.fieldY(), table.concat(t, " "))
  end),
})
