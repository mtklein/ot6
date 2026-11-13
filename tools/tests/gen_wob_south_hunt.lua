-- gen_wob_south_hunt.lua -- a branch beside gen_vector_entry (docs/design/wob-side-trips.md, #282): Continue the
-- `post-opera-v1` battery (CELES, LOCKE, EDGAR and SABIN on foot at (137,203), set down on the southern continent
-- after the opera) and walk the forests there that no story leg walks until every formation of each pool has been
-- won (K.worldHunt, lib/ot6_field.lua: the pool asserted against the ROM's, the hunt bounded by the worst draws):
-- the forest east of the save (world group 20: Bug, FossilFang) and the forest north-west of it (group 17: Ralph,
-- Wyvern, ChickenLip; group 18 by Maranda deals the same pool, so one walk wins both).  No leg boots what it leaves
-- (the state `wob_south_hunt`); gen_vector_entry goes on from the same save.
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

local function zone(z)
  local steps = {}
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
  H.saveState("wob_south_hunt.mss"),
  H.logStep(function()
    local t = {}
    for f in pairs(won) do t[#t + 1] = f end
    table.sort(t)
    for i, f in ipairs(t) do t[i] = tostring(f) end
    return string.format("wob_south_hunt generated: CELES L%d, LOCKE L%d, EDGAR L%d, SABIN L%d at world (%d,%d); "
      .. "formations won: %s", lv(CELES), lv(LOCKE), lv(EDGAR), lv(SABIN), H.worldX(), H.worldY(),
      table.concat(t, " "))
  end),
})
