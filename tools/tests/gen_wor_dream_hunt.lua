-- gen_wor_dream_hunt.lua -- a branch beside gen_wor_dream (docs/design/route-wor-dreams.md section 10, #488):
-- boot the graph's capture `wor_dream_scape` (TERRA, CELES and RELM in the dreamscape, 317, before the stooges)
-- and walk a lap until each formation of its pool is won (K.hunt).  Nothing boots what it leaves (the state
-- `wor_dream_hunt`).
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [CYAN] = "CYAN", [EDGAR] = "EDGAR", [SABIN] = "SABIN",
  [CELES] = "CELES", [STRAGO] = "STRAGO", [RELM] = "RELM", [SETZER] = "SETZER", [MOG] = "MOG", [GAU] = "GAU",
  [GOGO] = "GOGO", [UMARO] = "UMARO" }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true
local LINKS = {}

-- the World of Ruin legs' helpers (lib/ot6_field.lua, H.worLegKit)
local K = H.worLegKit({ fight = FIGHT, links = LINKS, names = NAMES })
local map, lv, say, kitLine, watches, walk, walkInto = K.map, K.lv, K.say, K.kitLine, K.watches, K.walk, K.walkInto
local FOUR = { CELES, RELM, TERRA }
local won = {}
local function wonLine()
  local t = {}
  for f in pairs(won) do t[#t + 1] = tostring(f) end
  table.sort(t)
  return table.concat(t, " ")
end
local SCAPE183 = { [312] = "Barb-e, Critic", [314] = "Allosaurus, Parasite x3", [315] = "Critic, Pan Dora x3",
  [316] = "Allosaurus" }

H.run({ maxFrames = 800000 }, {
  H.loadState("build/states/wor_dream_scape.mss.lua"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    H.assertEq(map(), 317, "the boot stands in the dreamscape (317): gen_wor_dream's capture wor_dream_scape")
  end),
  -- @@setup-end
  H.fieldCare({ threshold = 1.0, tag = "before the hunt: the dreamscape (group 183)" }),
  K.hunt({ what = "the dreamscape (group 183)", lap = { { 26, 52 }, { 26, 53 } }, forms = SCAPE183, won = won, castFirst = true }),
  H.fieldCare({ threshold = 1.0, tag = "after the hunt: the dreamscape (group 183)" }),
  H.call(function() H.log("[kit] " .. kitLine(FOUR)) end),
  H.saveState("wor_dream_hunt.mss"),
  H.logStep(function()
    return string.format("wor_dream_hunt generated: map %d (%d,%d); formations won: %s", map(), H.fieldX(), H.fieldY(),
      wonLine())
  end),
})
