-- gen_wor_dream_cave_hunt.lua -- a branch beside gen_wor_dream (docs/design/route-wor-dreams.md section 10,
-- #488): boot the graph's capture `wor_dream_cave` (the party in Magitek armor in the cave below the dream's
-- engine, 319) and walk a lap until each formation of its pool is won (K.hunt).  Nothing boots what it leaves
-- (the state `wor_dream_cave_hunt`).
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
local CAVE182 = { [311] = "PlutoArmor x2", [313] = "PlutoArmor, Sky Cap", [137] = "Io" }

H.run({ maxFrames = 800000 }, {
  -- the state this leaves is saved in the cave after its battles, where render on demand left the PPU's palette
  -- address unknown (the first try: "saved with the PPU's palette address unknown (#394)"): every frame drawn
  H.call(H.renderAlways),
  H.loadState("build/states/wor_dream_cave.mss.lua"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    H.assertEq(map(), 319, "the boot stands in the dream's cave (319): gen_wor_dream's capture wor_dream_cave")
  end),
  -- @@setup-end
  H.fieldCare({ threshold = 1.0, tag = "before the hunt: the dream's cave (group 182)" }),
  K.hunt({ what = "the dream's cave (group 182)", lap = { { 16, 25 }, { 17, 25 } }, forms = CAVE182, won = won, castFirst = true }),
  H.fieldCare({ threshold = 1.0, tag = "after the hunt: the dream's cave (group 182)" }),
  H.call(function() H.log("[kit] " .. kitLine(FOUR)) end),
  H.saveState("wor_dream_cave_hunt.mss"),
  H.logStep(function()
    return string.format("wor_dream_cave_hunt generated: map %d (%d,%d); formations won: %s", map(), H.fieldX(), H.fieldY(),
      wonLine())
  end),
})
