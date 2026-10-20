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
local function partyOf(ch) return H.readByte(0x1850 + ch) & 7 end
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
local function kitLine(members)
  local t = {}
  for _, ch in ipairs(members) do
    local g = {}
    for k = 0x1E, 0x24 do g[#g + 1] = string.format("%02X", H.readByte(c(ch, k))) end
    t[#t + 1] = string.format("%s L%d kit %s", NAMES[ch], lv(ch), table.concat(g, " "))
  end
  return table.concat(t, "; ")
end
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
-- walk onto (x, y) until the map reads dst (gen_wor_relm's)
local function walkInto(x, y, dst, what, avoid)
  local function there() return map() == dst and H.hasControl() and H.tileAligned() and bright() >= 15 end
  return H.seqStep({
    H.repeatN(3, {
      H.cond(function() return not there() end, {
        H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT, avoid = avoid,
          arrive = function() return map() == dst end }),
        H.release(),
        H.waitUntil(function() return map() == dst end, 600, what .. ": onto map " .. dst, 5),
      }, {}),
    }),
    H.waitUntil(there, 1200, what .. ": control on map " .. dst, 1),
    H.call(function() say("route", what) end),
  })
end
-- off a field map's edge onto the world map (gen_wor_locke's outToWorld)
local function outToWorld(dir, what)
  local n = 0
  return H.seqStep({
    H.driveUntil(function() return H.worldMode() end, 3000, { H.hold({ dir }) }, what),
    H.release(),
    H.withReset(H.waitUntil(function()
      local ok = H.worldSettled() and H.worldAligned() and H.worldPassable(H.worldX(), H.worldY())
      n = ok and n + 1 or 0
      return n >= 30
    end, 2400, what .. ": back on the World of Ruin map"), function() n = 0 end),
    H.call(function() say("wor", what) end),
  })
end
-- onto a world door until its field map holds the screen
local function enterFrom(door, dst, what)
  return H.seqStep({
    H.worldNavTo(door[1], door[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
      arrive = function() return map() == dst and not H.worldMode() end }),
    H.waitUntil(function() return map() == dst and settled() end, 2400, what .. ": map " .. dst, 1),
    H.call(function() say("route", what) end),
  })
end
-- boarding: on foot on the parked airship's tile, A boards (gen_wor_locke's)
local function board()
  local n, ph = 0, 0
  local drv = H.fightDriverFor("board", { tactical = true, boost = true, items = true, healPercent = 55 }, FIGHT)
  local battleFrames = 0
  local function offTile()
    return not H.battleLoadStarted() and H.worldSettled() and not H.aboardAirship()
      and (H.worldX() ~= H.readByte(0x1F62) or H.worldY() ~= H.readByte(0x1F63))
  end
  return H.withReset(H.driveUntil(function()
    n = H.airshipControl() and n + 1 or 0
    return n >= 30
  end, 30000, {
    H.cond(offTile, {
      H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
        { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
    }, {}),
    H.call(function()
      if H.battleLoadStarted() then
        battleFrames = battleFrames + 1
        if battleFrames >= 3 then drv.frame() end
        return
      end
      if battleFrames > 0 then drv.idle() end
      ph = (ph + 1) % 16
      if H.aboardAirship() then H.setPad({}); return end
      H.setPad(ph < 4 and { "a" } or {})
    end),
  }, "board the Falcon"), function() n, ph, battleFrames = 0, 0, 0 end)
end
-- the cabin's waiting members (map 12) each ask "Change party members?"
-- (_caf59d); NPC_n is object $10 + n - 1, shown by its switch
-- (gen_wor_locke's regroup)
local CABIN_NPCS = { { "TERRA", 0x10, 0x0388 }, { "CYAN", 0x12, 0x038B }, { "SABIN", 0x15, 0x038D },
  { "CELES", 0x16, 0x038E }, { "STRAGO", 0x17, 0x038F }, { "RELM", 0x18, 0x0390 }, { "MOG", 0x1A, 0x0392 },
  { "UMARO", 0x1D, 0x0395 }, { "EDGAR", 0x14, 0x038C }, { "SETZER", 0x19, 0x0391 } }
local function regroup(members)
  local obj = nil
  local function pickTalker()
    obj = nil
    for _, n in ipairs(CABIN_NPCS) do
      local ox, oy = H.objX(n[2]), H.objY(n[2])
      local reach = H.bfsPath(ox, oy + 1) or H.bfsPath(ox - 1, oy) or H.bfsPath(ox + 1, oy) or H.bfsPath(ox, oy - 1)
      if obj == nil and sw(n[3]) == 1 and reach then obj = n end
    end
    return obj
  end
  return H.seqStep({
    board(),
    H.withReset((function()
      local ph = 0
      return H.driveUntil(function() return map() == MAP_DECK and settled() end, 2400, {
        H.call(function()
          ph = (ph + 1) % 16
          H.setPad((H.airshipControl() and ph < 4) and { "x" } or {})
        end),
      }, "X: to the Falcon's deck (map 11)")
    end)(), function() end),
    walkInto(24, 8, MAP_CABIN, "the deck -> the cabin (map 12)"),
    H.call(function() pickTalker() end),
    H.cond(function() return obj == nil end, {
      H.navTo(23, 44, { maxFrames = 3000, arrive = function() return H.fieldY() < 40 end }),
      H.waitUntil(function() return settled() and H.fieldY() < 40 end, 1200, "up the cabin's stairs", 1),
      H.call(function() pickTalker() end),
    }, {}),
    H.call(function()
      H.assertEq(obj ~= nil, true, "a member waits in the cabin to talk to")
      H.log(string.format("[regroup] talking to %s (obj $%02X, show-switch $%04X)", obj[1], obj[2], obj[3]))
    end),
    H.lazy(function() return H.talkToObj(obj[2], obj[1] .. " in the cabin") end),
    H.dialogChoice(1, { inBattle = false, what = "Change party members? Yes", tag = "the cabin" }),
    H.partySelect(members, { tag = "the Falcon's cabin" }),
    H.waitUntil(function() return map() == MAP_DECK and settled() end, 2400, "back on the deck after the menu", 5),
    H.call(function()
      local n = 0
      for ch = 0, 13 do if partyOf(ch) == 1 then n = n + 1 end end
      for _, ch in ipairs(members) do
        H.assertEq(partyOf(ch), 1, string.format("%s is in party 1 after the regroup", NAMES[ch]))
      end
      H.assertEq(n, #members, "party 1 holds exactly the regroup's members")
      say("regroup", "after the menu")
    end),
  })
end
-- lift off from the deck's wheel (_caf532: face left, A held on (15,8))
local function liftOff()
  return H.seqStep({
    H.navTo(15, 8, { maxFrames = 3000 }),
    H.faceAndHoldA("left", function() return H.dialogWaiting() end, 1200, "the Falcon's wheel (11 (15,8)): face left, A"),
    H.release(),
    H.dialogChoice(0, { inBattle = false, what = "the wheel: (Lift-off)", tag = "the wheel" }),
  })
end
-- the key of every battle (reads only)
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
