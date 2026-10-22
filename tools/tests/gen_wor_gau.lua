-- gen_wor_gau.lua -- the Gau arc's second leg (docs/design/route-wor-gau.md):
-- Continue the `wor-veldt-cave-v1` battery (TERRA, CELES, RELM and GAU on
-- the Veldt cave's save point), the door to the dog's master (59,18) and
-- the scene there (_cb7a18): the SrBehemoth (event battle 82, a game over
-- when lost: the runner retries from the save point), SHADOW carried to
-- Thamasa on the Falcon and his dream, Strago's house (the Memento Ring),
-- Thamasa's item counter, and off the town's edge, where SHADOW leaves for
-- the Colosseum (_cb7d69: $019F).  Then the Falcon's cabin (SABIN, GAU,
-- TERRA and CELES), the father's house (SABIN and GAU: the scene), Duncan's
-- house north of Narshe (SABIN's Bum Rush), and the save beside the Falcon
-- there: the `wor-gau-v1` battery, the next arc's boot.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, SABIN, CELES, RELM, GAU = 0, 1, 5, 6, 8, 11
local POTION, FENIX, REMEDY, TENT, TINCTURE, REVIVIFY = 0xE9, 0xF0, 0xF5, 0xF7, 0xEB, 0xF1
local MEMENTO = 0xDB
local MAP_DECK, MAP_CABIN, MAP_VCAVE, MAP_HOUSE, MAP_THAMASA, MAP_THAMASA_ITEMS = 11, 12, 353, 349, 344, 347
local MAP_DUNCAN, MAP_FATHER, MAP_FATHER_IN = 127, 131, 116
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [SABIN] = "SABIN", [CELES] = "CELES", [RELM] = "RELM",
  [GAU] = "GAU" }
local SHOP_ITEMS = 74
-- world tiles (route_data world-entrances 1; landable: the property word's
-- bit 1 clear): the father's house (178,45) -> map 131 (7,13), the Falcon
-- down on (178,46); Duncan's house (140,20) -> map 127 (7,13), down on
-- (139,21), where the arc saves
local FATHER_DOOR, FATHER_LANDING = { 178, 45 }, { 178, 46 }
local DUNCAN_DOOR, DUNCAN_LANDING = { 140, 20 }, { 139, 21 }
-- the cave's doors (gen_wor_veldt's), the way from the save point to the
-- dog's master: (52,53) and through the door (51,53) onto (59,18)
local DOORS353 = { { 41, 55, 13, 32 }, { 12, 32, 40, 55 }, { 14, 18, 7, 48 }, { 7, 47, 14, 17 }, { 8, 55, 17, 25 },
  { 17, 24, 8, 54 }, { 40, 45, 13, 25 }, { 12, 25, 39, 45 }, { 23, 52, 42, 7 }, { 42, 6, 23, 51 }, { 55, 8, 50, 47 },
  { 50, 48, 55, 9 }, { 60, 18, 52, 53 }, { 51, 53, 59, 18 } }
-- Strago's house (map 349): the bedroom where the scene leaves the party
-- and the hall, joined by two doors
local DOORS349 = { { 39, 10, 61, 20 }, { 60, 21, 38, 11 } }
local links = H.doorLinks
local LINKS = { [MAP_VCAVE] = links(DOORS353), [MAP_HOUSE] = links(DOORS349) }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

-- the World of Ruin legs' helpers (lib/ot6_field.lua, H.worLegKit); the cabin's regroup talks with
-- H.talkToObj, as this leg was played
local K = H.worLegKit({ fight = FIGHT, links = LINKS, names = NAMES, talkToObj = true })
local map, sw, lv, partyOf, settled = K.map, K.sw, K.lv, K.partyOf, K.settled
local say, kitLine, outToWorld, enterFrom, board = K.say, K.kitLine, K.outToWorld, K.enterFrom, K.board
local regroup, liftOff, watches, walk, chestAt = K.regroup, K.liftOff, K.watches, K.walk, K.chestAt
-- the rages GAU knows ($1D2C, one bit a species) and the loadout's eight
-- bytes ($1E1F, rage id + 1, all zero AUTO: kit-gau.md section 4)
local function rageLine()
  local n, ids = 0, {}
  for i = 0, 255 do
    if (H.readByte(0x1D2C + (i >> 3)) >> (i & 7)) & 1 == 1 then n = n + 1; ids[#ids + 1] = string.format("$%02X", i) end
  end
  local l = {}
  for i = 0, 7 do l[#l + 1] = string.format("%02X", H.readByte(0x1E1F + i)) end
  return string.format("GAU knows %d rages (%s); loadout %s", n, table.concat(ids, " "), table.concat(l, " "))
end
H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-veldt-cave-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine({ TERRA, CELES, RELM, GAU }))
  end),
  -- @@setup-end

  -- ---- 1. the dog's master: the SrBehemoth -------------------------------------------
  -- @@stage srbehemoth
  -- the door (51,53) lands on (59,18), whose trigger (_cb7a18) runs the
  -- scene: the dog leads, the beast leaps, battle 82 (formation 452, the
  -- SrBehemoth: L43, 19,000 HP; weak fire and poison, absorbs ice), then
  -- the Falcon to Thamasa, the dream, and Strago's house
  H.fieldCare({ threshold = 1.0, tag = "before the dog's master" }),
  walk(59, 18, "through the door (51,53) onto (59,18): the dog's master", nil,
    function() return not H.hasControl() end),
  H.advanceStory(function() return sw(0x0199) == 1 and map() == MAP_HOUSE and settled() end, 300000,
    { playBattles = "tactical", fight = FIGHT }),
  H.call(function()
    say("story", "the scene done ($0199): Strago's house")
    H.assertEq(sw(0x0196), 1, "SHADOW rests in Thamasa ($0196)")
  end),
  H.saveState("wor_gau_house.mss"),

  -- ---- 2. Strago's house, Thamasa ------------------------------------------------------
  -- @@stage thamasa
  -- the Memento Ring (349 (56,16), treasure bit $0E3), from the side the
  -- bedroom reaches; out by the hall's door (37,25) to the street
  chestAt(56, 16, 0x0E3, "Memento Ring (349 (56,16))", MEMENTO),
  H.dressRelics({ { TERRA, "TERRA" }, { CELES, "CELES" }, { RELM, "RELM" }, { GAU, "GAU" } },
    { tag = "relics with the Memento Ring" }),
  walk(37, 24, "Strago's house: the hall, by the door"),
  H.navTo(37, 25, { maxFrames = 3000, arrive = function() return map() ~= MAP_HOUSE end }),
  H.waitUntil(function() return map() == MAP_THAMASA and settled() end, 2400, "Thamasa: map 344", 1),
  H.call(function() say("route", "Thamasa's street") end),
  H.crossDoor(26, 37, MAP_THAMASA_ITEMS, 36, 44, "Thamasa's item shop door 344 (26,37) -> 347", { fight = FIGHT }),
  H.shopTalk(36, 39, "Thamasa's item shop", { fight = FIGHT }),
  H.call(function() H.assertEq(H.shopId(), SHOP_ITEMS, "the counter opened shop 74 ($0201)") end),
  -- the bag for the next arc at the four's level (gen_wor_locke's bands)
  H.buyItem(POTION, function() return math.max(0, H.careStockPotions(H.activeTopLevel(), { spend = 40 })
    - H.invCountOf(POTION)) end, "POTION to the band"),
  H.buyItem(FENIX, function() return math.max(0, math.min(20, H.activeTopLevel()) - H.invCountOf(FENIX)) end,
    "FENIX DOWN to the level, capped at 20"),
  H.buyItem(TINCTURE, function() return math.max(0, -(-H.activeTopLevel() // 4) - H.invCountOf(TINCTURE)) end,
    "TINCTURE to the band"),
  H.buyItem(REMEDY, function() return math.max(0, 10 - H.invCountOf(REMEDY)) end, "REMEDY to 10"),
  H.shopClose("Thamasa's item shop"),
  H.bagArrange({ POTION, FENIX, REMEDY, TINCTURE }, { tag = "bag: combat items on top (Thamasa)" }),
  H.call(function() say("shop", "Thamasa") end),
  H.crossDoor(36, 45, MAP_THAMASA, 26, 39, "Thamasa's item shop -> the street", { fight = FIGHT }),
  H.saveState("wor_gau_thamasa.mss"),

  -- ---- 3. off the edge: SHADOW goes ---------------------------------------------------
  -- @@stage edge
  -- the south edge's triggers (344 (20-25,48), _cb7d69): with SHADOW
  -- resting ($0196) and the dream seen ($019E), he leaves for the
  -- Colosseum ($019F) as the party goes
  H.navTo(22, 47, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT }),
  H.driveUntil(function() return H.worldMode() end, 6000, { H.hold({ "down" }), H.waitFrames(4) }, "off Thamasa's edge"),
  H.release(),
  H.waitWorldSettled("out of Thamasa", 1800, 30),
  H.call(function()
    say("wor", string.format("out of Thamasa; the Falcon at (%d,%d)", H.readByte(0x1F62), H.readByte(0x1F63)))
    H.assertEq(sw(0x019F), 1, "SHADOW left for the Colosseum ($019F, _cb7d69)")
  end),

  -- ---- 4. the cabin, the father's house ----------------------------------------------------
  -- @@stage father
  -- SABIN and GAU for the father's house and Duncan's, with TERRA and
  -- CELES; RELM, LOCKE and the rest wait aboard.  Map 131 (7,6) -> 116,
  -- the old man (116 NPC_1 (115,9), _cb6828 .. _cb645b: face up, A): the
  -- reveal ($0245), Jidoor's tailor, the father, and the scene ends on the
  -- world map beside the Falcon ($0249: char_party GAU, 1)
  regroup({ SABIN, GAU, TERRA, CELES }),
  H.gearDress({ tag = "gear for the four" }),
  H.dressRelics({ { SABIN, "SABIN" }, { GAU, "GAU" }, { TERRA, "TERRA" }, { CELES, "CELES" } },
    { tag = "relics for the four" }),
  liftOff(),
  H.flyTo(FATHER_LANDING[1], FATHER_LANDING[2], { what = "the Falcon down by the father's house", fight = FIGHT }),
  enterFrom(FATHER_DOOR, MAP_FATHER, "the father's house (131)"),
  H.navTo(7, 6, { maxFrames = 3000, arrive = function() return map() == MAP_FATHER_IN end }),
  H.waitUntil(function() return map() == MAP_FATHER_IN and settled() end, 2400, "the back room: map 116", 1),
  H.navTo(115, 10, { maxFrames = 3000 }),
  H.faceAndHoldA("up", function() return H.dialogWaiting() or not H.hasControl() end, 600,
    "the old man (116 NPC_1 (115,9)): face up, A"),
  H.release(),
  H.advanceStory(function() return sw(0x0249) == 1 and H.worldMode() and H.worldSettled() end, 60000,
    { playBattles = "tactical", fight = FIGHT }),
  H.call(function()
    say("story", "the father's house ($0245, $0247, $0249)")
    H.assertEq(sw(0x0245), 1, "the father found ($0245)")
    H.assertEq(partyOf(GAU), 1, "GAU back in the party (char_party GAU, 1)")
  end),
  H.saveState("wor_gau_father.mss"),

  -- ---- 5. Duncan -------------------------------------------------------------------------
  -- @@stage duncan
  -- the trigger (7,11) (_cc0bd8: SABIN in the party, $02AF clear): the
  -- scene, and give_blitz (Bum Rush)
  board(),
  H.flyTo(DUNCAN_LANDING[1], DUNCAN_LANDING[2], { what = "the Falcon down by Duncan's house", fight = FIGHT }),
  enterFrom(DUNCAN_DOOR, MAP_DUNCAN, "Duncan's house (127)"),
  H.navTo(7, 11, { maxFrames = 3000, arrive = function() return not H.hasControl() end }),
  H.advanceStory(function() return sw(0x02AF) == 1 and settled() end, 60000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function()
    say("story", "Duncan ($02AF)")
    H.assertEq(H.readByte(0x1D28) & 0x80, 0x80, "SABIN knows Bum Rush ($1D28 bit 7, give_blitz)")
  end),
  H.navTo(7, 13, { maxFrames = 3000 }),
  outToWorld("down", "out of Duncan's house"),

  -- ---- 6. the save ------------------------------------------------------------------------
  -- @@stage save
  H.worldNavTo(DUNCAN_LANDING[1], DUNCAN_LANDING[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    avoid = { DUNCAN_DOOR } }),
  H.waitFrames(90),
  H.worldNavTo(DUNCAN_LANDING[1], DUNCAN_LANDING[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    avoid = { DUNCAN_DOOR } }),
  H.fieldCare({ threshold = 1.0, tag = "on the save tile" }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled on the save tile", 5),
  H.call(function()
    say("wor", "on the save tile")
    H.log("[kit] " .. kitLine({ SABIN, GAU, TERRA, CELES }))
  end),
  H.saveAtCheckpoint("wor-gau-v1"),
  H.saveState("wor_gau.mss"),
  H.logStep(function()
    return string.format("wor_gau generated: SABIN L%d, GAU L%d, TERRA L%d and CELES L%d beside the Falcon by Duncan's "
      .. "house, world (%d,%d), saved in slot 3", lv(SABIN), lv(GAU), lv(TERRA), lv(CELES), H.worldX(), H.worldY())
  end),
})
