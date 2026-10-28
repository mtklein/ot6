-- gen_wor_doma.lua -- the Dreams arc's second leg (docs/design/route-wor-dreams.md): Continue the
-- `wor-dream-v1` battery (CELES, RELM and TERRA at the save point in CYAN's dream, the dream's Doma, map
-- 126), the walk to its throne (25,11) and Wrexsoul (_cb97d6: event battle 92, a game over when lost: the
-- runner retries from the leg's boot; the driver's Zinger line fells the member it hides in), the wake in Doma
-- Castle's King's room (123: CYAN back, every SwdTech, $00DA), the Magicite Alexandr (_cb9a7a) and its stone
-- on CYAN, the gear and relic care, out of the castle, and the save on the Falcon's tile by Doma: the
-- `wor-doma-v1` battery, the boot for the Ancient Castle.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local POTION, FENIX, REMEDY, TENT, TINCTURE, REVIVIFY = 0xE9, 0xF0, 0xF5, 0xF7, 0xEB, 0xF1
local MAP_DECK, MAP_CABIN, MAP_HOUSE, MAP_THAMASA, MAP_THAMASA_ITEMS = 11, 12, 349, 344, 347
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [CYAN] = "CYAN", [EDGAR] = "EDGAR", [SABIN] = "SABIN",
  [CELES] = "CELES", [STRAGO] = "STRAGO", [RELM] = "RELM", [SETZER] = "SETZER", [MOG] = "MOG", [GAU] = "GAU",
  [GOGO] = "GOGO", [UMARO] = "UMARO" }
local SHOP_ITEMS = 74
local links = H.doorLinks
-- Strago's house (map 349): the bedroom where Hidon's scene leaves the party and the hall, joined by two
-- doors (gen_wor_gau's)
local DOORS349 = { { 39, 10, 61, 20 }, { 60, 21, 38, 11 } }
local LINKS = { [MAP_HOUSE] = links(DOORS349) }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

-- the World of Ruin legs' helpers (lib/ot6_field.lua, H.worLegKit)
local K = H.worLegKit({ fight = FIGHT, links = LINKS, names = NAMES })
local map, sw, c, lv, settled = K.map, K.sw, K.c, K.lv, K.settled
local say, kitLine, outToWorld, watches, walk = K.say, K.kitLine, K.outToWorld, K.watches, K.walk
local inParty, talkNpc, objOn = K.inParty, K.talkNpc, K.objOn

-- ---- Doma's maps ----
local DOMA_DOOR = { 171, 75 }
local MAP_COURT, MAP_KING, MAP_DREAM_DOMA = 285, 123, 126
-- 123's same-map doors (route_data.py map 123); 126, the dream's copy of it, has the same and two more
local DOORS123 = { { 4, 14, 42, 9 }, { 42, 7, 4, 13 }, { 25, 18, 10, 36 }, { 10, 34, 25, 17 }, { 40, 7, 56, 53 },
  { 56, 54, 40, 9 }, { 40, 12, 5, 45 }, { 5, 43, 40, 11 }, { 49, 12, 15, 45 }, { 15, 43, 49, 11 }, { 6, 24, 49, 27 },
  { 48, 28, 5, 25 } }
LINKS[MAP_KING] = links(DOORS123)
-- the dream's Doma (126) has 123's doors and two more (route_data.py map 126)
local DOORS126 = { { 16, 32, 28, 36 }, { 28, 37, 16, 34 } }
for _, d in ipairs(DOORS123) do DOORS126[#DOORS126 + 1] = d end
LINKS[MAP_DREAM_DOMA] = links(DOORS126)
local ALEXANDR = 14                 -- the stone's index (GenjuProp order: Ramuh 0 .. Alexandr 14)
local function owns(esper) return (H.readByte(0x1A69 + (esper >> 3)) >> (esper & 7)) & 1 == 1 end
local function posOf(ch) return (H.readByte(0x1850 + ch) >> 3) & 3 end
local FOUR = { CELES, RELM, CYAN, TERRA }
-- the castle's chests (#485, wor-coverage.md 5.1), which the waking Doma (123) and the dream's copy (126) share by
-- their bits.  Four are opened in the dream's Doma from its save point: the Elixir, the Ether, the Remedy and the
-- X-Potion, which in 123 stands behind the door (16,32) to map 124 but in 126 on the same map ((16,32) -> (28,36);
-- in 123 no way from (55,6) reached it).  The Fenix Down and the Beads stand in a room no door of 126's floor
-- reaches (126 (33,35): no side of (28,49) reachable); in 123 the ramparts' east door (285 (50,37) -> 123 (28,54))
-- opens on it, so they are opened on the way out (route_data field-path 123 (28,54) -> (28,50), (30,50))
local DREAM_CHESTS = { { 52, 47, 0x033, "the Elixir", 0xEE }, { 56, 47, 0x0B3, "the Ether", 0xEC },
  { 55, 5, 0x034, "the Remedy", REMEDY }, { 33, 34, 0x060, "the X-Potion", 0xEA } }
local WAKE_CHESTS = { { 28, 49, 0x035, "the Fenix Down", FENIX }, { 31, 50, 0x036, "the Beads", 0xD4 } }
local function domaChests(list, mp)
  local steps = {}
  for _, ch in ipairs(list) do
    steps[#steps + 1] = K.chestAt(ch[1], ch[2], ch[3], string.format("%s (%d (%d,%d))", ch[4], mp, ch[1], ch[2]), ch[5])
  end
  steps[#steps + 1] = H.call(function()
    for _, ch in ipairs(list) do
      H.assertEq(H.chestOpen(ch[3]), true, string.format("%d: %s's chest (bit %d) is open", mp, ch[4], ch[3]))
    end
  end)
  return H.seqStep(steps)
end
H.run({ maxFrames = 1800000 }, {
  H.bootCheckpoint("wor-dream-v1"),
  watches(),
  H.call(function()
    say("story", "boot")
    H.log("[kit] " .. kitLine({ CELES, RELM, TERRA }))
  end),
  -- @@setup-end

  -- ---- 1. Wrexsoul ---------------------------------------------------------------------------------------
  -- @@stage chests
  H.call(function() H.assertEq(map(), MAP_DREAM_DOMA, "the boot stands in the dream's Doma (126): wor_dream's save") end),
  domaChests(DREAM_CHESTS, MAP_DREAM_DOMA),

  -- @@stage wrexsoul
  -- the throne (25,11) is entered from below (25,12) (_cb97d6); Wrexsoul and its two Soul Savers absorb fire
  -- and holy (RELM's Pearl Rod is holy), so the arms go first
  walk(25, 12, "below the dream's throne (25,12)"),
  H.absorbSafeArms(nil, { 0x122, 0x167 }, { tag = "arms for Wrexsoul" }),
  H.fieldCare({ threshold = 1.0, tag = "before Wrexsoul" }),
  H.call(function() H.log("[kit] " .. kitLine({ CELES, RELM, TERRA })) end),
  H.saveState("wor_doma_throne.mss"),
  H.driveUntil(function() return H.dialogWaiting() or not H.hasControl() end, 900, { H.hold({ "up" }) },
    "up onto the throne (25,11)"),
  H.release(),
  H.advanceStory(function() return settled() and map() == MAP_KING end, 400000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function()
    say("story", "awake in Doma Castle (123)")
    H.assertEq(sw(0x00DA), 1, "CYAN's dream ended ($00DA, _cb97d6)")
    H.assertEq(inParty(CYAN), true, "CYAN is back in the party")
    H.assertEq(H.readByte(0x1CF7), 0xFF, "CYAN knows every SwdTech ($1CF7: give_bushido)")
  end),

  -- ---- 2. Alexandr, the stone, the care -------------------------------------------------------------------
  -- @@stage alexandr
  -- the Magicite on the throne's dais (123 NPC_9 (25,5), shown by $0549: _cb9a7a)
  H.lazy(function()
    local o = objOn(25, 5)
    H.assertEq(o ~= nil, true, "the Magicite stands at 123 (25,5)")
    return talkNpc(o, function() return owns(ALEXANDR) end, "the Magicite Alexandr")
  end),
  H.call(function() H.assertEq(owns(ALEXANDR), true, "Alexandr is the party's") end),
  -- the stone ends CYAN's quest and its stat package is a front-liner's (magicite.md): his
  H.cond(function() return H.readByte(c(CYAN, 0x1E)) ~= ALEXANDR end, {
    H.equipEsper(function() return posOf(CYAN) end, ALEXANDR, { tag = "Alexandr -> CYAN" }),
  }, {}),
  H.gearDress({ tag = "gear after the dream" }),
  H.dressRelics({ { CELES, "CELES" }, { RELM, "RELM" }, { CYAN, "CYAN" }, { TERRA, "TERRA" } },
    { tag = "relics after the dream" }),
  H.call(function() H.log("[kit] " .. kitLine(FOUR)) end),
  H.fieldCare({ threshold = 1.0, tag = "in the King's room" }),

  -- ---- 3. out of Doma, and the save ---------------------------------------------------------------------
  -- @@stage save
  -- the room of the Fenix Down and the Beads: 123 (17,39) -> the ramparts (285 (37,13): _cba0d2), their east
  -- door (50,37) -> 123 (28,54), and back by (28,55) -> 285 (50,39) and (37,11) -> 123 (17,38) (route_data
  -- field-path 285 (37,13) -> (50,37), (50,39) -> (37,12); the ramparts do not reach the gate)
  walk(17, 39, "123 (17,39) -> the ramparts", nil, function() return map() == MAP_COURT end),
  H.waitUntil(function() return map() == MAP_COURT and settled() end, 3000, "the ramparts: map 285", 1),
  walk(50, 37, "285 (50,37) -> 123's south-east room", nil, function() return map() == MAP_KING end),
  H.waitUntil(function() return map() == MAP_KING and settled() end, 3000, "123's south-east room", 1),
  domaChests(WAKE_CHESTS, MAP_KING),
  walk(28, 55, "123 (28,55) -> the ramparts", nil, function() return map() == MAP_COURT end),
  H.waitUntil(function() return map() == MAP_COURT and settled() end, 3000, "the ramparts again: map 285", 1),
  walk(37, 11, "285 (37,11) -> 123 (17,38)", nil, function() return map() == MAP_KING end),
  H.waitUntil(function() return map() == MAP_KING and settled() end, 3000, "123 again", 1),
  -- the way in, backwards: 123 (10,50) -> the courtyard (285 (28,33)), its gate (33,62) and the south edge
  walk(10, 50, "123 (10,50) -> the courtyard", nil, function() return map() == MAP_COURT end),
  H.waitUntil(function() return map() == MAP_COURT and settled() end, 3000, "the courtyard: map 285", 1),
  walk(33, 62, "the courtyard's gate (33,62)"),
  outToWorld("down", "out of Doma Castle"),
  H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
    { maxFrames = 3000, playBattles = "tactical", fight = FIGHT, avoid = { DOMA_DOOR } }),
  H.fieldCare({ threshold = 1.0, tag = "on the Falcon's tile" }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled on the save tile", 5),
  H.call(function()
    say("wor", "on the save tile")
    H.log("[kit] " .. kitLine(FOUR))
  end),
  H.saveAtCheckpoint("wor-doma-v1"),
  H.saveState("wor_doma.mss"),
  H.logStep(function()
    return string.format("wor_doma generated: CELES L%d, RELM L%d, CYAN L%d and TERRA L%d beside the Falcon by Doma, "
      .. "world (%d,%d), saved in slot 3", lv(CELES), lv(RELM), lv(CYAN), lv(TERRA), H.worldX(), H.worldY())
  end),
})
