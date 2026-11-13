-- gen_wob_airship_hunt.lua -- a branch beside gen_vector_entry (docs/design/wob-side-trips.md, #279 #280 #282):
-- Continue the `post-opera-v1` battery (CELES, LOCKE, EDGAR and SABIN on foot at (137,203), the Blackjack parked
-- beside them), the first point the airship lets a player reach the World of Balance's open country, and walk each
-- zone no story leg walks until every formation of its pool has been won (K.worldHunt, lib/ot6_field.lua: the
-- pool asserted against the ROM's, the hunt bounded by the worst draws):
--   on foot from the save: the forests between Vector and Maranda (world groups 20, 17 and 18: Bug, FossilFang,
--     ChickenLip, Ralph and Wyvern; #282);
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
local lv, say, kitLine, watches = K.lv, K.say, K.kitLine, K.watches

-- the zones (laps and landing tiles read from the ROM's world map: WorldTileProp's passable and landable bits,
-- WorldBattleGroup for each tile's group; docs/design/wob-side-trips.md section 1)
local ZONES = {
  { what = "the forest east of the save (group 20)", lap = { { 142, 203 }, { 143, 203 } },
    forms = { [139] = "FossilFang x2", [140] = "FossilFang, Bug x3", [141] = "Bug x3", [142] = "Bug x6" } },
  { what = "the forest north-west of the save (group 17)", lap = { { 119, 193 }, { 119, 194 } },
    forms = { [145] = "Ralph, Wyvern, ChickenLip x2", [149] = "ChickenLip x5" } },
  { what = "the forest by Maranda (group 18)", lap = { { 71, 227 }, { 72, 227 } },
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
local won = {}
local function lowest()
  local m = 99
  for _, ch in ipairs(FOUR) do m = math.min(m, lv(ch)) end
  return m
end

local function zone(z)
  local steps = {}
  if z.land then
    steps[#steps + 1] = K.board()
    steps[#steps + 1] = H.flyTo(z.land[1], z.land[2], { what = "the Blackjack to " .. z.what, fight = FIGHT })
  end
  steps[#steps + 1] = H.fieldCare({ threshold = 1.0, tag = "before " .. z.what })
  steps[#steps + 1] = H.call(function()
    say("hunt", string.format("%s: lowest L%d", z.what, lowest()))
    H.log("[kit] " .. kitLine(FOUR))
  end)
  steps[#steps + 1] = K.worldHunt({ what = z.what, lap = z.lap, forms = z.forms, won = won })
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
