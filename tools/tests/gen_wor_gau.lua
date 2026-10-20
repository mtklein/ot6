-- gen_wor_gau.lua -- the Gau arc's second leg (docs/design/route-wor-gau.md):
-- Continue the `wor-veldt-cave-v1` battery (TERRA, CELES, RELM and GAU on
-- the Veldt cave's save point), the door to the dog's master (59,18) and
-- the scene there (_cb7a18): the SrBehemoth (event battle 82, a game over
-- when lost: the runner retries from the save point), SHADOW carried to
-- Thamasa on the Falcon and his dream (_cb7b..), Strago's house (the
-- Memento Ring), Thamasa's item counter, and off the town's edge, where
-- SHADOW leaves for the Colosseum (_cb7d69: $019F), then the save beside
-- the Falcon: the `wor-gau-v1` battery, the next arc's boot.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CELES, RELM, GAU = 0, 6, 8, 11
local POTION, FENIX, REMEDY, TENT, TINCTURE, REVIVIFY = 0xE9, 0xF0, 0xF5, 0xF7, 0xEB, 0xF1
local MEMENTO = 0xDB
local MAP_VCAVE, MAP_HOUSE, MAP_THAMASA, MAP_THAMASA_ITEMS = 353, 349, 344, 347
local SEATED = { TERRA, CELES, RELM, GAU }
local NAMES = { [TERRA] = "TERRA", [CELES] = "CELES", [RELM] = "RELM", [GAU] = "GAU" }
local SHOP_ITEMS = 74
-- the cave's doors (gen_wor_veldt's), the way from the save point to the
-- dog's master: (52,53) and through the door (51,53) onto (59,18)
local DOORS353 = { { 41, 55, 13, 32 }, { 12, 32, 40, 55 }, { 14, 18, 7, 48 }, { 7, 47, 14, 17 }, { 8, 55, 17, 25 },
  { 17, 24, 8, 54 }, { 40, 45, 13, 25 }, { 12, 25, 39, 45 }, { 23, 52, 42, 7 }, { 42, 6, 23, 51 }, { 55, 8, 50, 47 },
  { 50, 48, 55, 9 }, { 60, 18, 52, 53 }, { 51, 53, 59, 18 } }
-- Strago's house (map 349): the bedroom where the scene leaves the party
-- and the hall, joined by two doors
local DOORS349 = { { 39, 10, 61, 20 }, { 60, 21, 38, 11 } }
local function links(doors)
  local out = {}
  for _, d in ipairs(doors) do
    for _, dir in ipairs({ "up", "down", "left", "right" }) do out[#out + 1] = { d[1], d[2], dir, d[3], d[4] } end
  end
  return out
end
local LINKS = { [MAP_VCAVE] = links(DOORS353), [MAP_HOUSE] = links(DOORS349) }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function c(ch, off) return 0x1600 + 37 * ch + off end
local function lv(ch) return H.readByte(c(ch, 8)) end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
end
local function supplies()
  return string.format("potion=%d tincture=%d fenix=%d remedy=%d revivify=%d tent=%d gil=%d", H.invCountOf(POTION),
    H.invCountOf(TINCTURE), H.invCountOf(FENIX), H.invCountOf(REMEDY), H.invCountOf(REVIVIFY), H.invCountOf(TENT),
    H.gil())
end
local function say(tag, what)
  local pos = H.worldMode() and string.format("world (%d,%d)", H.worldX(), H.worldY())
    or string.format("map %d (%d,%d)", map(), H.fieldX(), H.fieldY())
  H.log(string.format("[%s] f%d %s %s; %s; %s", tag, H.frame, what, pos, H.partiesLine(), supplies()))
end
local function kitLine()
  local t = {}
  for _, ch in ipairs(SEATED) do
    local g = {}
    for k = 0x1E, 0x24 do g[#g + 1] = string.format("%02X", H.readByte(c(ch, k))) end
    t[#t + 1] = string.format("%s L%d kit %s", NAMES[ch], lv(ch), table.concat(g, " "))
  end
  return table.concat(t, "; ")
end
-- a walk over a map's floor and its doors
local function walk(x, y, what, avoid, arrive)
  return H.seqStep({
    H.lazy(function()
      return H.navLinks(x, y, LINKS[map()] or {}, { what = what, maxFrames = 12000, playBattles = "tactical",
        fight = FIGHT, avoid = avoid, arrive = arrive })
    end),
    H.call(function() say("route", what) end),
  })
end
-- a chest from whichever side of it the party can reach (gen_wor_ragnarok's)
local function chestAt(cx, cy, bit, what, item)
  return H.lazy(function()
    for _, o in ipairs({ { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }) do
      local legs = H.bfsReach(nil, nil, nil, LINKS[map()] or {}, cx + o[1], cy + o[2])
      if legs then
        return H.seqStep({
          walk(cx + o[1], cy + o[2], what .. ": beside it"),
          H.openChest({ stand = { cx + o[1], cy + o[2] }, face = o[3], bit = bit, what = what, item = item,
            nav = { fight = FIGHT } }),
        })
      end
    end
    error(string.format("[chest] %s (%d,%d): no side of it is reachable from (%d,%d)", what, cx, cy,
      H.fieldX(), H.fieldY()))
  end)
end
-- boarding: on foot on the parked airship's tile, A boards (gen_wor_locke's)
local watchOn = false
local function watches()
  return H.call(function()
    if watchOn then return end
    watchOn = true
    local addr = H.seedStoreAddr()
    emu.addMemoryCallback(function()
      H.log(string.format("[key] battle key be%02X-g%04X f%d map %d party %d", emu.getState()["cpu.a"] & 0xff,
        H.readWord(0x11e0), H.frame, map(), H.activeParty()))
    end, emu.callbackType.exec, addr, addr)
  end)
end
local falcon = nil

H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-veldt-cave-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine())
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

  -- ---- 3. off the edge, and the save ----------------------------------------------------
  -- @@stage save
  -- the south edge's triggers (344 (20-25,48), _cb7d69): with SHADOW
  -- resting ($0196) and the dream seen ($019E), he leaves for the
  -- Colosseum ($019F) as the party goes
  H.navTo(22, 47, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT }),
  H.driveUntil(function() return H.worldMode() end, 6000, { H.hold({ "down" }), H.waitFrames(4) }, "off Thamasa's edge"),
  H.release(),
  H.waitWorldSettled("out of Thamasa", 1800, 30),
  H.call(function()
    falcon = { H.readByte(0x1F62), H.readByte(0x1F63) }
    say("wor", string.format("out of Thamasa; the Falcon at (%d,%d)", falcon[1], falcon[2]))
    H.assertEq(sw(0x019F), 1, "SHADOW left for the Colosseum ($019F, _cb7d69)")
  end),
  H.lazy(function()
    return H.worldNavTo(falcon[1], falcon[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT })
  end),
  H.waitFrames(90),
  H.lazy(function()
    return H.worldNavTo(falcon[1], falcon[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT })
  end),
  H.fieldCare({ threshold = 1.0, tag = "on the save tile" }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled on the save tile", 5),
  H.call(function()
    say("wor", "on the save tile")
    H.log("[kit] " .. kitLine())
  end),
  H.saveAtCheckpoint("wor-gau-v1"),
  H.saveState("wor_gau.mss"),
  H.logStep(function()
    return string.format("wor_gau generated: TERRA L%d, CELES L%d, RELM L%d and GAU L%d beside the Falcon outside "
      .. "Thamasa, world (%d,%d), saved in slot 3", lv(TERRA), lv(CELES), lv(RELM), lv(GAU), H.worldX(), H.worldY())
  end),
})
