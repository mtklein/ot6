-- gen_wor_phoenix.lua -- into the Phoenix Cave, the first split-party
-- dungeon: Continue the `wor-thamasa-v1` battery (TERRA, CELES, RELM and
-- STRAGO beside the Falcon at the Fanatics' Tower), Thamasa's inn and item
-- counter, the Falcon to the cave (world (117,156): LandAirship's
-- VehicleEvent_03), the party menu's two groups, then the cave as two
-- parties to its save point (315 (37,28)) and Save there: the
-- `wor-phoenix-v1` battery, a save made mid-dungeon with both parties in it.
-- docs/design/split-party.md has the cave's switches, the order the two
-- parties take and what this measured; gen_wor_locke continues from the
-- save.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CYAN, SABIN, CELES, STRAGO, RELM, MOG, UMARO = 0, 2, 5, 6, 7, 8, 10, 13
local POTION, FENIX, REMEDY, TENT, TINCTURE = 0xE9, 0xF0, 0xF5, 0xF7, 0xEB
local MAP_THAMASA, MAP_THAMASA_ITEMS, MAP_THAMASA_INN = 344, 347, 346
local THAMASA_DOOR, THAMASA_LANDING = { 251, 230 }, { 250, 229 }
local THAMASA_AVOID = { { 22, 39 }, { 23, 39 } }
-- the cave's landing: the World of Ruin tile whose property word has bit
-- $4000 and takes a landing (LandAirship, world/init.asm; the scan in
-- build/attempts/wt/v032-splitparty/lab/phx1: '(117,156)4515')
local CAVE_LANDING = { 117, 156 }
local MAP_ENTRY, MAP_CAVE, MAP_DEEP = 318, 315, 313
-- the two groups (`party_menu 2`, EnterPhoenixCave): each keeps two of the
-- arc's four casters at L46-49 beside two of the bench at L36-38, a medic
-- in each (TERRA's Cure and Life; CELES's Cure), so either can meet what
-- the cave deals.  Party 1 holds the plates, party 2 walks the long way:
-- the rocks, the lava, the Red Dragon and LOCKE (docs/design/split-party.md)
local GROUPS = { { TERRA, STRAGO, SABIN, CYAN }, { CELES, RELM, MOG, UMARO } }
local AQUA_RAKE = 3
local FIGHT = { nukeLore = { AQUA_RAKE }, strago = { study = true, pearlWind = true } }
H.NAV_REFIRE_HOLD = true

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
end
local function supplies()
  return string.format("potion=%d tincture=%d fenix=%d remedy=%d revivify=%d tent=%d gil=%d", H.invCountOf(POTION),
    H.invCountOf(TINCTURE), H.invCountOf(FENIX), H.invCountOf(REMEDY), H.invCountOf(0xF1), H.invCountOf(TENT), H.gil())
end
local function say(tag, what)
  local pos = H.worldMode() and string.format("world (%d,%d)", H.worldX(), H.worldY())
    or string.format("map %d (%d,%d)", map(), H.fieldX(), H.fieldY())
  H.log(string.format("[%s] f%d %s %s; %s; %s", tag, H.frame, what, pos, H.partiesLine(), supplies()))
end

-- ---- the cave's switches and links (docs/design/split-party.md) -----------
-- the rock jumps: standing on (x, y), the press `move` carries the party to
-- (tx, ty) (event_main.asm _cc216f.._cc23dc); the cond is the switch the
-- script tests besides the facing
local function plate24() return sw(0x02D4) == 1 or sw(0x02D5) == 1 end
local LINKS = {
  [MAP_DEEP] = {
    { 36, 34, "right", 44, 34, function() return sw(0x02A8) == 1 end },
    { 36, 31, "right", 44, 31 }, { 44, 31, "left", 36, 31 }, { 44, 34, "left", 36, 34 },
    { 25, 17, "left", 9, 17 }, { 9, 17, "right", 25, 17 }, { 6, 19, "down", 6, 24 }, { 6, 23, "up", 6, 19 },
    { 8, 25, "right", 16, 25 }, { 16, 25, "left", 8, 25 }, { 18, 23, "up", 18, 15 }, { 18, 15, "down", 18, 25 },
    { 23, 20, "up", 23, 14 }, { 23, 14, "down", 23, 22 }, { 8, 50, "right", 14, 50 }, { 14, 50, "left", 8, 50 },
  },
  [MAP_CAVE] = {
    { 4, 23, "right", 10, 23, plate24 }, { 10, 23, "left", 4, 23, plate24 },
    { 19, 22, "down", 19, 25 }, { 19, 24, "up", 19, 21 },
  },
}
-- every tile of the cave whose trigger re-runs under a party standing on it
-- (plates and spikes): no party is left standing on one but to hold it
local SPIKES = {}
for _, t in ipairs({ { 33, 42 }, { 34, 41 }, { 33, 40 }, { 34, 39 }, { 33, 38 }, { 34, 37 }, { 43, 41 }, { 43, 43 },
  { 43, 45 }, { 42, 42 }, { 42, 44 }, { 49, 38 }, { 50, 39 }, { 51, 38 }, { 37, 9 }, { 39, 9 }, { 41, 9 }, { 43, 9 },
  { 36, 10 }, { 38, 10 }, { 40, 10 }, { 42, 10 }, { 44, 10 }, { 37, 11 }, { 39, 11 }, { 41, 11 }, { 43, 11 } }) do
  SPIKES[#SPIKES + 1] = t
end

-- walk to (x, y) on the cave's floor and its links; arrive() ends the walk
-- early (a door to the other map)
local function walk(x, y, what, arrive)
  return H.lazy(function()
    return H.navLinks(x, y, LINKS[map()] or {}, { what = what, maxFrames = 12000, playBattles = "tactical",
      fight = FIGHT, arrive = arrive })
  end)
end
-- through a door to the other map: onto (x, y) until the map reads dst
local function door(x, y, dst, what)
  return H.seqStep({
    walk(x, y, what, function() return map() == dst end),
    H.waitUntil(function() return map() == dst and settled() end, 1200, what .. ": on map " .. dst, 1),
    H.call(function() say("route", what) end),
  })
end
-- a plate: walk onto it and hold it (the switch reads set); the party is
-- left standing there
local function hold(x, y, id, what)
  return H.seqStep({
    walk(x, y, what),
    H.waitUntil(function() return sw(id) == 1 end, 600, what .. string.format(": $%04X set", id), 1),
    H.call(function() say("plate", what) end),
  })
end

-- boarding: on foot on the parked airship's tile, A boards (gen_wor_cyan's)
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

-- each party's kit once it walks: the relics in the bag, and a stone for
-- each member who wears none (UMARO takes none), from the owned stones no
-- one wears, the healing ones first
local STONE_ORDER = { 25, 21, 2, 1, 3, 5, 9, 10, 18, 20, 6, 0, 4, 7, 8, 11, 12, 13, 14, 15, 16, 17, 19, 22, 23, 24 }
local function owns(e) return (H.readByte(0x1A69 + (e >> 3)) >> (e & 7)) & 1 == 1 end
local function stoneFor()
  local worn = {}
  for c = 0, 15 do worn[H.readByte(0x1600 + 37 * c + 0x1E)] = true end
  for _, e in ipairs(STONE_ORDER) do
    if owns(e) and not worn[e] then return e end
  end
  return nil
end
local function dressParty(p)
  local steps = { H.switchParty(p, { tag = "dress party " .. p }) }
  for i = 1, 4 do
    steps[#steps + 1] = H.lazy(function()
      local roster = H.partyRoster(p)
      local c = roster[i]
      if c == nil or c == UMARO or H.readByte(0x1600 + 37 * c + 0x1E) ~= 0xFF then return H.call(function() end) end
      local e = stoneFor()
      if e == nil then return H.logStep("[kit] no stone left for " .. H.SPLIT_NAMES[c]) end
      return H.equipEsper(function() return (H.readByte(0x1850 + c) >> 3) & 3 end, e,
        { tag = string.format("stone %d -> %s (party %d)", e, H.SPLIT_NAMES[c], p) })
    end)
  end
  steps[#steps + 1] = H.lazy(function()
    local m = {}
    for _, c in ipairs(H.partyRoster(p)) do m[#m + 1] = { c, H.SPLIT_NAMES[c] } end
    return H.dressRelics(m, { tag = "relics, party " .. p })
  end)
  steps[#steps + 1] = H.call(function() say("kit", "party " .. p .. " dressed") end)
  return H.seqStep(steps)
end

H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-thamasa-v1"),
  watches(),
  H.call(function() say("wor", "boot") end),
  -- @@setup-end

  -- ---- 1. Thamasa: the inn and the item counter --------------------------------
  -- @@stage thamasa
  -- the bag came down from the tower dry (1 Potion, 2 Tonics, 1 Tincture:
  -- docs/design/split-party.md), and the cave splits it between two parties
  board(),
  H.flyTo(THAMASA_LANDING[1], THAMASA_LANDING[2], { what = "the Falcon to Thamasa", fight = FIGHT }),
  H.worldNavTo(THAMASA_DOOR[1], THAMASA_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_THAMASA and not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_THAMASA and settled() end, 2400, "Thamasa: map 344", 1),
  H.crossDoor(12, 19, MAP_THAMASA_INN, 23, 23, "Thamasa's inn door 344 (12,19) -> 346",
    { fight = FIGHT, avoid = THAMASA_AVOID }),
  H.innRest({ spot = { 24, 17 }, face = "up", price = 1, tag = "Thamasa inn" }),
  H.crossDoor(23, 24, MAP_THAMASA, 12, 21, "Thamasa's inn -> the street", { fight = FIGHT }),
  H.crossDoor(26, 37, MAP_THAMASA_ITEMS, 36, 44, "Thamasa's item shop door 344 (26,37) -> 347",
    { fight = FIGHT, avoid = THAMASA_AVOID }),
  H.shopTalk(36, 39, "Thamasa's item shop", { fight = FIGHT }),
  H.call(function() H.assertEq(H.shopId(), 74, "the counter opened shop 74 ($0201)") end),
  -- one bag for two parties: Potions to the stack (the cave's field care
  -- rides on them, no counter here sells Tonics), Tinctures for eight
  -- casters' MP, Fenix Downs to 20, Remedies, and Tents for the save point
  H.buyItem(POTION, function() return math.max(0, 99 - H.invCountOf(POTION)) end, "POTION to 99"),
  H.buyItem(TINCTURE, function() return math.max(0, 40 - H.invCountOf(TINCTURE)) end, "TINCTURE to 40"),
  H.buyItem(FENIX, function() return math.max(0, 20 - H.invCountOf(FENIX)) end, "FENIX DOWN to 20"),
  H.buyItem(REMEDY, function() return math.max(0, 20 - H.invCountOf(REMEDY)) end, "REMEDY to 20"),
  H.buyItem(TENT, function() return math.max(0, 6 - H.invCountOf(TENT)) end, "TENT to 6"),
  H.shopClose("Thamasa's item shop"),
  H.bagArrange({ POTION, FENIX, REMEDY, TINCTURE }, { tag = "bag: combat items on top (Thamasa)" }),
  H.call(function() say("shop", "Thamasa") end),
  H.crossDoor(36, 45, MAP_THAMASA, 26, 39, "Thamasa's item shop -> the street", { fight = FIGHT }),
  H.navTo(22, 47, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT, avoid = THAMASA_AVOID }),
  H.driveUntil(function() return H.worldMode() end, 6000, { H.hold({ "down" }), H.waitFrames(4) }, "off Thamasa's edge"),
  H.release(),
  H.waitWorldSettled("out of Thamasa", 1800, 30),
  H.saveState("wor_phoenix_thamasa.mss"),

  -- ---- 2. the split -------------------------------------------------------------
  -- @@stage split
  board(),
  H.flyTo(CAVE_LANDING[1], CAVE_LANDING[2], { what = "the Falcon to the Phoenix Cave", entersMap = true, fight = FIGHT,
    maxFrames = 12000 }),
  H.driveUntil(function() return H.readByte(0x0059) ~= 0 and H.readByte(0x26) == 0x2d end, 6000, {
    H.call(function() H.setPad((H.dialogWaiting() and H.frame % 8 < 4) and { "a" } or {}) end),
  }, "the cave's party menu (party_menu 2)"),
  H.waitFrames(20),
  H.partySelect(GROUPS, { tag = "the cave's two groups" }),
  H.advanceStory(function() return map() == MAP_ENTRY and settled() end, 6000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function()
    for g, ids in ipairs(GROUPS) do
      for _, c in ipairs(ids) do
        H.assertEq(H.partyOfChar(c), g, string.format("%s is in party %d", H.SPLIT_NAMES[c], g))
      end
    end
    H.assertEq((H.readByte(0x1EB9) & 0x40) ~= 0, true, "party switching on ($01CE, _cc2090)")
  end),
  H.splitBegin(),
  dressParty(2),
  dressParty(1),
  H.saveState("wor_phoenix_split.mss"),

  -- ---- 3. the gates: party 2 on the south plate, party 1 on the north --------------
  -- @@stage gates
  door(8, 5, MAP_CAVE, "party 1: the entry -> the cave (315 (35,58))"),
  H.switchParty(2),
  door(8, 5, MAP_CAVE, "party 2: the entry -> the cave"),
  hold(35, 55, 0x02A6, "party 2 holds the south plate (35,55): the west gate (32,52)"),
  H.switchParty(1),
  hold(35, 52, 0x02A3, "party 1 holds the north plate (35,52): the east gate (38,52)"),
  H.switchParty(2),
  -- off the south plate (the west gate closes behind party 1) and through
  -- the east gate party 1 holds, down to the rocks
  door(45, 52, MAP_DEEP, "party 2: the east gate -> 313 (46,47)"),
  walk(40, 38, "party 2 to the rocks (40,38)"),
  H.waitUntil(function() return sw(0x02A8) == 1 and settled() end, 1200, "the rocks raised ($02A8)", 1),
  H.saveState("wor_phoenix_gates.mss"),

  -- ---- 4. the passage north: party 1 sets it, party 2 takes it, then clears it -------------
  -- @@stage north
  H.switchParty(1),
  door(29, 38, MAP_DEEP, "party 1: the west side -> 313 (29,34)"),
  walk(41, 27, "party 1 onto (41,27): the passage north for the east side ($02AA)"),
  H.waitUntil(function() return sw(0x02AA) == 1 and settled() end, 1200, "$02AA set", 1),
  H.switchParty(2),
  door(49, 12, MAP_CAVE, "party 2: north -> 315 (50,23)"),
  door(46, 23, MAP_DEEP, "party 2: -> 313 (46,11)"),
  walk(46, 16, "party 2 onto (46,16): the passage back to the west side ($02AA clear)"),
  H.waitUntil(function() return sw(0x02AA) == 0 and settled() end, 1200, "$02AA clear", 1),
  door(46, 10, MAP_CAVE, "party 2: -> 315 (46,22)"),
  door(29, 18, MAP_DEEP, "party 2: -> 313 (29,13)"),
  door(23, 7, MAP_CAVE, "party 2: -> 315 (23,12)"),
  -- the lava: on (19,10), facing up, A (_cc2a1f)
  walk(19, 10, "party 2 onto the lava switch (19,10)"),
  (function()
    local ph = 0
    return H.withReset(H.driveUntil(function() return sw(0x02D0) == 1 or map() ~= MAP_CAVE end, 1800, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(ph < 4 and { "up", "a" } or { "up" })
      end),
    }, "the lava switch: up held, A"), function() ph = 0 end)
  end)(),
  H.release(),
  H.advanceStory(function() return sw(0x02D0) == 1 and map() == MAP_CAVE and settled() end, 6000,
    { playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("route", "the lava drained ($02D0)") end),
  walk(20, 11, "party 2 off the lava switch"),
  H.switchParty(1),
  door(43, 12, MAP_CAVE, "party 1: the jumps -> 315 (42,23)"),
  H.saveState("wor_phoenix_north.mss"),

  -- ---- 5. the save point ----------------------------------------------------------
  -- @@stage save
  -- party 1 cares on the save point, where a Tent is on offer (the care
  -- prices it against the Potions the hole would take); party 2, out of
  -- its reach at the lava switch, cares with the bag, kept off party 1's
  -- share (M.splitReserveFor)
  H.stepOntoSavePoint(37, 28),
  H.splitCare({ parties = { 2, 1 }, threshold = 0.9, tag = "care at the save point" }),
  H.call(function()
    say("wor", "at the save point")
    for _, l in ipairs(H.splitReport()) do H.log(l) end
  end),
  H.saveAtCheckpoint("wor-phoenix-v1"),
  H.splitEnd(),
  H.saveState("wor_phoenix.mss"),
  H.logStep(function()
    return string.format("wor_phoenix generated: %s, saved in slot 3", H.partiesLine())
  end),
})
