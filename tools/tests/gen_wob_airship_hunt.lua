-- gen_wob_airship_hunt.lua -- a branch beside gen_vector_entry (docs/design/wob-side-trips.md, #279 #280 #282):
-- Continue the `post-opera-v1` battery (CELES, LOCKE, EDGAR and SABIN on foot at (137,203), the Blackjack parked
-- beside them), the first point the airship lets a player reach the World of Balance's open country, and walk each
-- zone no story leg walks until every formation of its pool has been won (K.worldHunt, lib/ot6_field.lua: the
-- pool asserted against the ROM's, the hunt bounded by the worst draws):
--   on foot from the save: the forests between Vector and Maranda (world groups 20 and 17: Bug, FossilFang,
--     ChickenLip, Ralph and Wyvern; #282; group 18 by Maranda deals group 17's pool, so one walk wins both);
--   by the Blackjack: the bomb isle (group 27: Bomb, Grenade; #282), the north isles (group 22: Cephaler,
--     Chimera; #279), the plain north of Thamasa (group 25: Chimera, Cephaler; #279) and Triangle Island (group
--     124: Leafer, Dark Wind, Intangir; #280).
-- No leg boots what it leaves (the state `wob_airship_hunt`); gen_vector_entry goes on from the same save.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local LOCKE, EDGAR, SABIN, CELES = 1, 4, 5, 6
local NAMES = { [LOCKE] = "LOCKE", [EDGAR] = "EDGAR", [SABIN] = "SABIN", [CELES] = "CELES" }
local FOUR = { CELES, LOCKE, EDGAR, SABIN }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, settled, lv, say, kitLine, watches = K.map, K.settled, K.lv, K.say, K.kitLine, K.watches

-- the zones (laps and landing tiles read from the ROM's world map: WorldTileProp's passable and landable bits,
-- WorldBattleGroup for each tile's group; docs/design/wob-side-trips.md section 1)
local ZONES = {
  { what = "the forest east of the save (group 20)", lap = { { 142, 203 }, { 143, 203 } },
    forms = { [139] = "FossilFang x2", [140] = "FossilFang, Bug x3", [141] = "Bug x3", [142] = "Bug x6" } },
  { what = "the forest north-west of the save (group 17)", lap = { { 119, 193 }, { 119, 194 } },
    forms = { [145] = "Ralph, Wyvern, ChickenLip x2", [149] = "ChickenLip x5" } },
  { what = "the bomb isle (group 27)", land = { 171, 112 }, lap = { { 174, 109 }, { 175, 109 } },
    forms = { [135] = "Bomb", [136] = "Bomb x6", [189] = "Grenade" } },
  { what = "the north isles (group 22)", land = { 110, 17 }, lap = { { 110, 17 }, { 110, 18 } },
    forms = { [163] = "Cephaler x3", [190] = "Chimera, Cephaler x2" } },
  { what = "the plain north of Thamasa (group 25)", land = { 249, 126 }, lap = { { 250, 126 }, { 251, 126 } },
    forms = { [161] = "Chimera", [163] = "Cephaler x3", [190] = "Chimera, Cephaler x2" } },
  { what = "Triangle Island (group 124)", land = { 243, 39 }, lap = { { 243, 38 }, { 244, 38 } },
    forms = { [6] = "Leafer", [7] = "Leafer x2, Dark Wind", [210] = "Intangir" } },
}
-- every World of Balance entrance and event trigger (route_data's short entrances and triggers of world 0),
-- kept off every walk: Albrook's door (138,203) is the tile east of the save
local DOORS = { {21,92}, {22,92}, {22,93}, {26,39}, {26,131}, {27,39}, {27,130}, {28,131}, {30,6}, {30,48}, {31,48},
  {33,9}, {45,154}, {54,85}, {64,76}, {65,76}, {66,226}, {66,227}, {73,93}, {75,102}, {77,235}, {84,33}, {85,112},
  {85,113}, {86,111}, {86,112}, {90,99}, {98,92}, {102,100}, {104,64}, {117,61}, {118,61}, {119,149}, {120,149},
  {120,187}, {121,187}, {125,150}, {138,203}, {139,203}, {156,84}, {157,84}, {165,35}, {165,194}, {166,194},
  {169,194}, {177,92}, {178,82}, {178,92}, {179,71}, {185,93}, {214,148}, {220,115}, {229,130}, {250,128} }
local won = {}
local function lowest()
  local m = 99
  for _, ch in ipairs(FOUR) do m = math.min(m, lv(ch)) end
  return m
end

-- aboard the Blackjack and into the air: A on the parked ship takes the party into its hold (map 7), the hold's
-- stair (40,10) up to the deck (map 6), and the wheel (_caf532, beside (15,6)) lifts off -- straight away the
-- first time ($0170 clear), by its (Lift-off) choice after
local MAP_HOLD, MAP_DECK = 7, 6
local function board()
  local ph = 0
  return H.seqStep({
    H.withReset(H.driveUntil(function() return map() == MAP_HOLD and settled() end, 6000, {
      H.cond(function() return H.worldMode() and H.worldSettled() and (H.worldX() ~= H.readByte(0x1F62)
          or H.worldY() ~= H.readByte(0x1F63)) end, {
        H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
          { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
      }, {}),
      H.call(function()
        ph = (ph + 1) % 16
        H.setPad((H.worldMode() and ph < 4) and { "a" } or {})
      end),
    }, "A on the parked Blackjack: its hold (map 7)"), function() ph = 0 end),
    H.release(),
    -- the hold's stairs are in-map links (route_data map 7): (10,29) -> (50,61), (50,50) -> (40,17), and (40,10)
    -- up to the deck
    H.navTo(10, 29, { maxFrames = 6000, arrive = function() return H.fieldX() >= 45 and H.fieldY() >= 55 end }),
    H.waitUntil(function() return settled() and H.fieldX() >= 45 end, 2400, "the hold's stair (10,29) -> (50,61)", 5),
    H.navTo(50, 50, { maxFrames = 6000, arrive = function() return H.fieldX() == 40 and H.fieldY() <= 17 end }),
    H.waitUntil(function() return settled() and H.fieldX() == 40 end, 2400, "the hold's stair (50,50) -> (40,17)", 5),
    H.navTo(40, 10, { maxFrames = 6000, arrive = function() return map() == MAP_DECK end }),
    H.waitUntil(function() return map() == MAP_DECK and settled() end, 2400, "the Blackjack's deck (map 6)", 5),
    H.navTo(15, 6, { maxFrames = 3000 }),
    H.faceAndHoldA("left", function() return H.dialogWaiting() or H.aboardAirship() end, 1200,
      "the Blackjack's wheel (6 (14,6)): face left, A"),
    H.release(),
    H.cond(function() return H.dialogWaiting() end, {
      H.dialogChoice(0, { inBattle = false, what = "the wheel: (Lift-off)", tag = "the wheel" }),
    }, {}),
    H.waitUntil(function() return H.airshipControl() end, 3000, "the pilot's controls", 5),
    H.call(function() say("fly", "aboard the Blackjack") end),
  })
end

local function zone(z)
  local steps = {}
  if z.land then
    -- onto a tile beside the parked Blackjack by a walk that keeps off the doors, then aboard
    steps[#steps + 1] = H.lazy(function()
      local ax, ay = H.readByte(0x1F62), H.readByte(0x1F63)
      for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { -1, 0 }, { 1, 0 } }) do
        local bx, by = ax + d[1], ay + d[2]
        local door = false
        for _, t in ipairs(DOORS) do if t[1] == bx and t[2] == by then door = true end end
        if not door and H.worldPassable(bx, by) and H.worldBfs(bx, by, nil, nil, nil, H.worldAvoidSet(DOORS)) then
          return H.worldNavTo(bx, by, { maxFrames = 20000, playBattles = "tactical", fight = FIGHT, avoid = DOORS })
        end
      end
      error(string.format("no tile beside the Blackjack at (%d,%d) is reachable", ax, ay))
    end)
    steps[#steps + 1] = board()
    steps[#steps + 1] = H.flyTo(z.land[1], z.land[2], { what = "the Blackjack to " .. z.what, fight = FIGHT })
  end
  steps[#steps + 1] = H.fieldCare({ threshold = 1.0, tag = "before " .. z.what })
  steps[#steps + 1] = H.call(function()
    say("hunt", string.format("%s: lowest L%d", z.what, lowest()))
    H.log("[kit] " .. kitLine(FOUR))
  end)
  steps[#steps + 1] = K.worldHunt({ what = z.what, lap = z.lap, forms = z.forms, won = won, avoid = DOORS })
  steps[#steps + 1] = H.call(function()
    say("hunt", string.format("%s: done; lowest L%d", z.what, lowest()))
  end)
  return H.seqStep(steps)
end

local route = {}
for _, z in ipairs(ZONES) do route[#route + 1] = zone(z) end

H.run({ maxFrames = 3000000 }, {
  H.bootCheckpoint("post-opera-v1"),
  watches(),
  H.call(function()
    say("wob", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    H.log(string.format("[wob] the Blackjack parked at (%d,%d)", H.readByte(0x1F62), H.readByte(0x1F63)))
    for _, ch in ipairs(FOUR) do
      H.assertEq(K.partyOf(ch), 1, string.format("%s is seated (post-opera-v1: gen_post_opera_checkpoint's party)",
        NAMES[ch]))
    end
  end),
  -- @@setup-end
  H.seqStep(route),
  H.fieldCare({ threshold = 1.0, tag = "after the hunts" }),
  H.call(function() H.log("[kit] " .. kitLine(FOUR)) end),
  H.saveState("wob_airship_hunt.mss"),
  H.logStep(function()
    local t = {}
    for f in pairs(won) do t[#t + 1] = f end
    table.sort(t)
    for i, f in ipairs(t) do t[i] = tostring(f) end
    return string.format("wob_airship_hunt generated: CELES L%d, LOCKE L%d, EDGAR L%d, SABIN L%d at world (%d,%d); "
      .. "formations won: %s", lv(CELES), lv(LOCKE), lv(EDGAR), lv(SABIN), H.worldX(), H.worldY(),
      table.concat(t, " "))
  end),
})
