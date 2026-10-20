-- gen_wor_locke.lua -- the Phoenix Cave's second half and the arc's end:
-- Continue the `wor-phoenix-v1` battery (the cave's save point, party 1 on
-- it, party 2 beside the lava switch it pulled), the bridge (party 1 on
-- (23,19), party 2 over it), the Red Dragon (event battle 138), the jump
-- plate (party 2 on (12,23), party 1 across the jumps), the two steps that
-- open the last bridge (party 1 on (10,32), party 2 onto (12,32)), and
-- LOCKE (313 (6,53), _cc2b43): the scene, Phoenix, which ends in Kohlingen
-- with CELES and LOCKE alone.  Then the regroup in the Falcon's cabin
-- (LOCKE, TERRA, CELES and RELM), Kohlingen's inn, item counter and gear
-- counters, and the save outside Kohlingen: the `wor-locke-v1` battery,
-- the boot for the next arc.  docs/design/split-party.md has the cave,
-- docs/design/route-wor-locke.md the arc.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SABIN, CELES, STRAGO, RELM, MOG, UMARO = 0, 1, 2, 5, 6, 7, 8, 10, 13
local POTION, FENIX, REMEDY, TENT, TINCTURE, RIBBON = 0xE9, 0xF0, 0xF5, 0xF7, 0xEB, 0xCA
local MAP_CAVE, MAP_DEEP = 315, 313
-- the arc's end (route-wor-locke.md 5): the scene leaves CELES and LOCKE in
-- Kohlingen (map 189), the Falcon parked at world (38,48) (_cc3188:
-- airship_pos); the town's inn (191), store (194: shops 65, 66, 67) and
-- south edge, and the wor-kohlingen-v1 save tile east of its door
local MAP_KOHLINGEN, MAP_K_INN, MAP_K_STORE = 189, 191, 194
local MAP_DECK, MAP_CABIN = 11, 12
local K_DOORS = { { 38, 45 }, { 39, 45 } }
local K_LANDING = { 38, 48 }
local SAVE_TILE = { 40, 45 }
local SHOP_ITEMS = 67
-- the four who fly on: LOCKE with the three highest (TERRA L49, CELES L50,
-- RELM L47 in wor-phoenix-v1: data/wor-phoenix-v1_roster.txt); TERRA's
-- Cure and Life and CELES's Cure the medics
local SEATED = { LOCKE, TERRA, CELES, RELM }
local ABOARD = { CYAN, SABIN, STRAGO, MOG, UMARO }
local AQUA_RAKE = 3
local FIGHT = { nukeLore = { AQUA_RAKE }, strago = { study = true, pearlWind = true } }
-- the Red Dragon ($153, L67, 30,000 HP; weak ice and water, absorbs fire:
-- route_data pool event 138)
local RED_DRAGON = 0x153
local BOSS_FIGHT = { nukeLore = { AQUA_RAKE } }
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

-- the cave's links (gen_wor_phoenix's; docs/design/split-party.md)
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
local function walk(x, y, what, arrive)
  return H.lazy(function()
    return H.navLinks(x, y, LINKS[map()] or {}, { what = what, maxFrames = 12000, playBattles = "tactical",
      fight = FIGHT, arrive = arrive })
  end)
end
local function door(x, y, dst, what)
  return H.seqStep({
    walk(x, y, what, function() return map() == dst end),
    H.waitUntil(function() return map() == dst and settled() end, 1200, what .. ": on map " .. dst, 1),
    H.call(function() say("route", what) end),
  })
end
local function hold(x, y, id, what)
  return H.seqStep({
    walk(x, y, what),
    H.waitUntil(function() return sw(id) == 1 end, 600, what .. string.format(": $%04X set", id), 1),
    H.call(function() say("plate", what) end),
  })
end
-- a chest, when a side of it can be reached from here over the floor and
-- the links (the walk there by them, then the chest); else a line
local function chestIfNear(cx, cy, bit, what, item)
  return H.lazy(function()
    for _, o in ipairs({ { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }) do
      local sx, sy = cx + o[1], cy + o[2]
      for _, z in ipairs({ false, 1, 2 }) do
        if H.bfsReach(nil, nil, z or nil, LINKS[map()] or {}, sx, sy) then
          return H.seqStep({
            walk(sx, sy, what .. ": beside it"),
            H.openChest({ stand = { sx, sy }, face = o[3], bit = bit, what = what, item = item,
              nav = { fight = FIGHT, playBattles = "tactical" } }),
          })
        end
      end
    end
    return H.logStep(string.format("[chest] %s (%d,%d): no side of it is reachable from (%d,%d)", what, cx, cy,
      H.fieldX(), H.fieldY()))
  end)
end

-- ---- the arc's end: the Falcon, the cabin, Kohlingen ----------------------
local function partyOf(ch) return H.readByte(0x1850 + ch) & 7 end
local function lv(ch) return H.readByte(0x1600 + 37 * ch + 8) end
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
-- off a town's edge onto the world map (gen_wor_kohlingen's outToWorld)
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
-- boarding: on foot on the parked airship's tile, A boards (gen_wor_phoenix's)
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
        { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, avoid = K_DOORS }),
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
-- (_caf59d); NPC_n is object $10 + n - 1 (route_data map 12), shown by its
-- switch (gen_wor_relm's regroup)
local CABIN_NPCS = { { "TERRA", 0x10, 0x0388 }, { "CYAN", 0x12, 0x038B }, { "SABIN", 0x15, 0x038D },
  { "CELES", 0x16, 0x038E }, { "STRAGO", 0x17, 0x038F }, { "RELM", 0x18, 0x0390 }, { "MOG", 0x1A, 0x0392 },
  { "UMARO", 0x1D, 0x0395 }, { "EDGAR", 0x14, 0x038C }, { "SETZER", 0x19, 0x0391 } }
local function regroup(members, aboard)
  local obj = nil
  local function pickTalker()
    obj = nil
    for _, n in ipairs(CABIN_NPCS) do
      local ox, oy = H.objX(n[2]), H.objY(n[2])
      local reach = H.bfsPath(ox, oy + 1) or H.bfsPath(ox - 1, oy) or H.bfsPath(ox + 1, oy) or H.bfsPath(ox, oy - 1)
      H.log(string.format("[regroup] %s: show-switch $%04X = %d, obj $%02X at (%d,%d), %s", n[1], n[3], sw(n[3]),
        n[2], ox, oy, reach and "reachable" or "not reachable"))
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
      for _, ch in ipairs(members) do
        H.assertEq(partyOf(ch), 1, string.format("char %d is in party 1 after the regroup", ch))
      end
      for _, ch in ipairs(aboard) do
        H.assertEq(partyOf(ch), 0, string.format("char %d waits aboard", ch))
      end
    end),
  })
end
-- a stone for LOCKE, who joins wearing none: the first owned stone no one
-- wears, the healing ones first (gen_wor_phoenix's order)
local STONE_ORDER = { 25, 21, 2, 1, 3, 5, 9, 10, 18, 20, 6, 0, 4, 7, 8, 11, 12, 13, 14, 15, 16, 17, 19, 22, 23, 24 }
local function stoneFor()
  local worn = {}
  for c = 0, 15 do worn[H.readByte(0x1600 + 37 * c + 0x1E)] = true end
  for _, e in ipairs(STONE_ORDER) do
    if (H.readByte(0x1A69 + (e >> 3)) >> (e & 7)) & 1 == 1 and not worn[e] then return e end
  end
  return nil
end
local function stoneForLocke()
  return H.lazy(function()
    if H.readByte(0x1600 + 37 * LOCKE + 0x1E) ~= 0xFF then return H.logStep("[kit] LOCKE wears a stone already") end
    local e = stoneFor()
    if e == nil then return H.logStep("[kit] no stone left for LOCKE") end
    return H.equipEsper(function() return (H.readByte(0x1850 + LOCKE) >> 3) & 3 end, e,
      { tag = string.format("stone %d -> LOCKE", e) })
  end)
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

H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-phoenix-v1"),
  watches(),
  -- party 2 walks the longer half (the Red Dragon, four of the five
  -- battles in l2), so it takes two thirds of the bag's care stock
  H.splitBegin({ shares = { [1] = 1, [2] = 2 } }),
  H.call(function() say("wor", "boot") end),
  -- @@setup-end

  -- ---- 1. the bridge: party 1 on (23,19), party 2 over it -----------------------------
  -- @@stage bridge
  hold(23, 19, 0x02D2, "party 1 holds the bridge plate (23,19): the bridge north-south"),
  H.switchParty(2),
  walk(19, 25, "party 2 over the bridge (19,22) -> (19,25)"),

  -- ---- 2. the Red Dragon ---------------------------------------------------------------
  -- @@stage dragon
  -- touch-to-fight (315 NPC_1, _cc2048: battle 138, a game over when
  -- lost).  It wanders its room (18-21,44-48): the walk to its side met it
  -- in the corridor and fought it there under the walk's driver, then the
  -- talk waited on a dragon gone (lab/swl_k1_s0: 'battle $174 WON' then
  -- 'activation round 2' timed out), and a walk planned onto (20,45) found
  -- it in the way (swl_k2_s0: 'no route (19,25)->(20,45)').  So party 2
  -- tops up in the corridor above its room, and the talk, which finds it
  -- where it stands, is made only while it is still shown
  walk(16, 38, "party 2 in the corridor above the Red Dragon's room"),
  H.fieldCare({ threshold = 0.95, tag = "before the Red Dragon" }),
  H.cond(function() return sw(0x069C) == 1 end, {
    H.talkToObj(0x10, "the Red Dragon (315 NPC_1)", nil, function() return sw(0x069C) == 0 end),
  }, {}),
  H.advanceStory(function() return sw(0x069C) == 0 and map() == MAP_CAVE and settled() end, 200000,
    { playBattles = "tactical", fight = BOSS_FIGHT }),
  H.call(function() say("boss", "the Red Dragon beaten") end),
  H.saveState("wor_locke_dragon.mss"),

  -- ---- 3. the jump plate and the two steps ---------------------------------------------
  -- @@stage steps
  chestIfNear(20, 40, 0x0B1, "Dragon Horn (315 (20,40))"),
  hold(12, 23, 0x02D5, "party 2 holds the jump plate (12,23): the jumps (4,23)-(10,23)"),
  H.switchParty(1),
  walk(23, 21, "party 1 off the bridge plate"),
  door(11, 14, MAP_DEEP, "party 1: -> 313 (13,9)"),
  -- the Ribbon (313 (13,20), treasure bit 171), reached from below by the
  -- jumps of 313's west side; it goes on at once (guidelines.md, "Ribbons
  -- are worth going out of your way for")
  chestIfNear(13, 20, 0x0AB, "Ribbon (313 (13,20))", RIBBON),
  -- a care first: the Relic menu refuses a member who is down, and the care
  -- revives and cures Zombie with a Revivify (lab/swl2_k4_s7: STRAGO zombied
  -- at 0 HP, '4 A presses on the target were not taken')
  H.fieldCare({ tag = "before the Ribbon goes on" }),
  H.lazy(function()
    local m = {}
    for _, c in ipairs(H.partyRoster(1)) do m[#m + 1] = { c, H.SPLIT_NAMES[c] } end
    return H.dressRelics(m, { tag = "relics with the Ribbon, party 1" })
  end),
  door(6, 7, MAP_CAVE, "party 1: -> 315 (6,12)"),
  hold(10, 32, 0x02C5, "party 1 across the jumps, on the step (10,32)"),
  H.switchParty(2),
  walk(12, 32, "party 2 onto the step (12,32): the last bridge"),
  H.waitUntil(function() return sw(0x02D6) == 1 and settled() end, 1200, "the bridge (10,35) open ($02D6)", 1),
  H.call(function() say("route", "the last bridge") end),

  -- ---- 4. LOCKE -------------------------------------------------------------------------
  -- @@stage locke
  door(16, 52, MAP_DEEP, "party 2: -> 313 (18,52)"),
  walk(18, 54, "party 2 onto (18,54): LOCKE shown"),
  H.waitUntil(function() return sw(0x0698) == 1 end, 600, "LOCKE shown ($0698)", 1),
  walk(6, 53, "party 2 to LOCKE (313 (6,53))", function() return sw(0x00D7) == 1 end),
  H.splitEnd(),
  H.advanceStory(function() return sw(0x00D7) == 1 and sw(0x01F0) == 1 and settled() end, 60000,
    { playBattles = "tactical", fight = FIGHT }),
  H.call(function()
    say("wor", "LOCKE joined")
    H.assertEq(H.partyOfChar(LOCKE), 1, "LOCKE in party 1 (_cc3178: char_party LOCKE, 1)")
    H.assertEq(H.partyOfChar(CELES), 1, "CELES in party 1")
    H.assertEq(sw(0x02F1), 1, "LOCKE available ($02F1)")
    H.assertEq(sw(0x01CE), 0, "party switching off: one party again (_cc3178 .. $01CE)")
  end),
  -- LOCKE joins with nothing on (his record is empty since the World of
  -- Balance; the scene gives a ValiantKnife and a Flame Shld to the bag:
  -- _cc3178 .. give_item), so he is dressed from the bag at once
  -- (tools/audit_equipment.py: 'BARE wor_locke.mss: LOCKE', lab/l2)
  H.gearDress({ tag = "LOCKE's gear from the bag" }),
  H.dressRelics({ { CELES, "CELES" }, { LOCKE, "LOCKE" } }, { tag = "relics, CELES and LOCKE" }),
  H.call(function()
    H.assertEq(H.readByte(0x1600 + 37 * LOCKE + 0x1F) ~= 0xFF, true, "LOCKE holds a weapon")
    say("wor", "LOCKE dressed")
  end),
  H.saveState("wor_locke_joined.mss"),

  -- ---- 5. the regroup: the Falcon's cabin -----------------------------------------------
  -- @@stage regroup
  -- the scene leaves the two in Kohlingen's square (map 189); the town's
  -- arrival tile (23,29), then off its south edge (the long exit (1,31) ->
  -- world (38,46)), and aboard the Falcon the scene parked at (38,48)
  H.fieldCare({ tag = "CELES and LOCKE in Kohlingen" }),
  H.navTo(23, 29, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
  outToWorld("down", "out of Kohlingen by the south edge"),
  regroup(SEATED, ABOARD),
  H.call(function() say("regroup", "LOCKE, TERRA, CELES and RELM") end),
  H.dressRelics({ { LOCKE, "LOCKE" }, { TERRA, "TERRA" }, { CELES, "CELES" }, { RELM, "RELM" } },
    { tag = "relics for the four" }),
  stoneForLocke(),
  liftOff(),
  H.flyTo(K_LANDING[1], K_LANDING[2], { what = "the Falcon down by Kohlingen", fight = FIGHT }),
  H.worldNavTo(K_DOORS[1][1], K_DOORS[1][2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_KOHLINGEN and not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_KOHLINGEN and settled() end, 2400, "Kohlingen: map 189", 1),
  H.saveState("wor_locke_regroup.mss"),

  -- ---- 6. Kohlingen: the inn, the item counter, the gear --------------------------------
  -- @@stage kohlingen
  H.crossDoor(16, 22, MAP_K_INN, 17, 20, "Kohlingen inn door 189(16,22)->191(17,20)", { fight = FIGHT }),
  H.cond(function() return H.bfsPath(17, 12) ~= nil end, {
    H.innRest({ spot = { 17, 12 }, face = "up", price = 200, tag = "Kohlingen inn" }),
  }, {
    H.innRest({ spot = { 17, 13 }, face = "up", price = 200, tag = "Kohlingen inn" }),
  }),
  walkInto(17, 21, MAP_KOHLINGEN, "the inn -> Kohlingen"),
  H.crossDoor(11, 11, MAP_K_STORE, 12, 39, "Kohlingen store door 189(11,11)->194(12,39)", { fight = FIGHT }),
  H.shopTalk(19, 35, "Kohlingen item counter", { fight = FIGHT }),
  H.call(function() H.assertEq(H.shopId(), SHOP_ITEMS, "the counter opened shop 67 ($0201)") end),
  -- the bag for the next arc at the four's level (docs/design/supply.md,
  -- level-curve.md's bands): Potions to the band with the field care's
  -- share, Fenix Downs to the level (cap 20), Tinctures to a quarter of
  -- it, Remedies to 10
  H.buyItem(POTION, function() return math.max(0, H.careStockPotions(H.activeTopLevel(), { spend = 40 })
    - H.invCountOf(POTION)) end, "POTION to the band"),
  H.buyItem(FENIX, function() return math.max(0, math.min(20, H.activeTopLevel()) - H.invCountOf(FENIX)) end,
    "FENIX DOWN to the level, capped at 20"),
  H.buyItem(TINCTURE, function() return math.max(0, -(-H.activeTopLevel() // 4) - H.invCountOf(TINCTURE)) end,
    "TINCTURE to the band"),
  H.buyItem(REMEDY, function() return math.max(0, 10 - H.invCountOf(REMEDY)) end, "REMEDY to 10"),
  H.shopClose("Kohlingen item counter"),
  H.bagArrange({ POTION, FENIX, REMEDY, TINCTURE }, { tag = "bag: combat items on top (Kohlingen)" }),
  H.call(function() say("shop", "Kohlingen") end),
  walkInto(12, 40, MAP_KOHLINGEN, "the store -> Kohlingen"),
  H.gearStop({ tag = "gear Kohlingen (LOCKE)", fight = FIGHT }),     -- #434: buy power with gil
  -- LOCKE's row (gen_wor_kohlingen's rule for SETZER): a weapon without
  -- the row penalty (ItemProp +19 bit 5; the Wing Edge has it) loses
  -- nothing in the back row, where physical hits taken are halved, so he
  -- goes back when his weapon says so (the qualification's first play
  -- left him in front with the Wing Edge: audit_readiness, wor_locke.mss)
  H.cond(function()
    local w = H.readByte(0x1600 + 37 * LOCKE + 0x1F)
    local free = w ~= 0xFF and (H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + w * 30 + 19) & 0x20) ~= 0
    H.log(string.format("[kit] LOCKE's weapon $%02X %s the row penalty; party byte $%02X", w,
      free and "ignores" or "carries", H.readByte(0x1850 + LOCKE)))
    return free
  end, {
    H.setRows({ [LOCKE] = true }, { tag = "LOCKE to the back row" }),
  }, {}),
  H.saveState("wor_locke_kohlingen.mss"),

  -- ---- 7. out to the world map, and the save ----------------------------------------------
  -- @@stage save
  -- (gen_wor_kohlingen's: the exit returns the party to the tile it
  -- stepped in from, so the save is made on a fixed tile east of the door,
  -- walked to twice with a stand between, an encounter that opens after
  -- the walker arrived fought)
  H.fieldCare({ threshold = 1.0, tag = "before the save" }),
  H.navTo(23, 29, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
  outToWorld("down", "out of Kohlingen by the south edge, to the save"),
  H.worldNavTo(SAVE_TILE[1], SAVE_TILE[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    avoid = K_DOORS }),
  H.waitFrames(90),
  H.worldNavTo(SAVE_TILE[1], SAVE_TILE[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    avoid = K_DOORS }),
  H.fieldCare({ threshold = 1.0, tag = "on the save tile" }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled on the save tile", 5),
  H.call(function()
    say("wor", "on the save tile")
    for _, c in ipairs(SEATED) do
      local g = {}
      for k = 0, 5 do g[#g + 1] = string.format("%02X", H.readByte(0x1600 + 37 * c + 0x1F + k)) end
      H.log(string.format("[kit] char %d L%d gear %s stone $%02X", c, lv(c), table.concat(g, " "),
        H.readByte(0x1600 + 37 * c + 0x1E)))
    end
  end),
  H.saveAtCheckpoint("wor-locke-v1"),
  H.saveState("wor_locke.mss"),
  H.logStep(function()
    return string.format("wor_locke generated: LOCKE L%d, TERRA L%d, CELES L%d and RELM L%d outside Kohlingen, "
      .. "world (%d,%d), saved in slot 3", lv(LOCKE), lv(TERRA), lv(CELES), lv(RELM), H.worldX(), H.worldY())
  end),
})
