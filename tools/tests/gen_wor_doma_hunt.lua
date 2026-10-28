-- gen_wor_doma_hunt.lua -- a branch beside gen_wor_doma (docs/design/route-wor-dreams.md section 10, #488):
-- Continue the `wor-dream-v1` battery (CELES, RELM and TERRA at the save point in the dream's Doma, 126) and walk
-- a lap beside the save point until each formation of its pool is won (K.hunt; group 181 is also the dream
-- train's cars 144 and 321).  Nothing boots what it leaves (the state `wor_doma_hunt`).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
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
local DOMA181 = { [309] = "Rain Man x2", [310] = "Samurai, Rain Man x2", [317] = "Barb-e, Samurai, Suriander",
  [318] = "Suriander, Pan Dora, Parasite x2" }

H.run({ maxFrames = 800000 }, {
  H.bootCheckpoint("wor-dream-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    H.assertEq(map(), 126, "the boot stands in the dream's Doma (126): gen_wor_dream's save wor-dream-v1")
  end),
  -- @@setup-end
  H.fieldCare({ threshold = 1.0, tag = "before the hunt: the dream's Doma (group 181)" }),
  K.hunt({ what = "the dream's Doma (group 181)", lap = { { 8, 9 }, { 8, 10 } }, forms = DOMA181, won = won, castFirst = true }),
  H.fieldCare({ threshold = 1.0, tag = "after the hunt: the dream's Doma (group 181)" }),
  H.call(function() H.log("[kit] " .. kitLine(FOUR)) end),
  H.saveState("wor_doma_hunt.mss"),
  H.logStep(function()
    return string.format("wor_doma_hunt generated: map %d (%d,%d); formations won: %s", map(), H.fieldX(), H.fieldY(),
      wonLine())
  end),
})
