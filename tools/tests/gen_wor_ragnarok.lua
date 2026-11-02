-- gen_wor_ragnarok.lua -- Narshe with LOCKE: Continue the `wor-locke-v1`
-- battery (LOCKE, TERRA, CELES and RELM on foot outside Kohlingen), the
-- Falcon to Narshe, and LOCKE's locks on map 32 (route-wor-narshe.md
-- findings 1-2): the elder's treasure room, the weapon shop and its back
-- room (the old man's Ragnarok, taken as the stone), the relic shop, the
-- Cursed Shld's old man, the item counter, the gear counters and the inn.
-- Ragnarok onto a wearer, and the save beside the Falcon outside Narshe:
-- the `wor-ragnarok-v1` battery, the next arc's boot.
-- docs/design/route-wor-narshe.md section 12 has what this measured.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CELES, RELM = 0, 1, 6, 8
local POTION, FENIX, REMEDY, TENT, TINCTURE, REVIVIFY = 0xE9, 0xF0, 0xF5, 0xF7, 0xEB, 0xF1
local HYPER_WRIST, SNEAK_RING, WALL_RING, THIEFKNIFE, EARRINGS, CURSED_SHLD = 0xD2, 0xC7, 0xBB, 0x04, 0xC3, 0x66
local BACK_GUARD = 0xE1                     -- no back or pincer attacks (ChooseBattleType @2e3a)
local MAP_NARSHE, MAP_ELDER, MAP_WEAPON, MAP_ITEMS, MAP_RELICS, MAP_INN = 32, 30, 24, 26, 27, 28
local SEATED = { LOCKE, TERRA, CELES, RELM }
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [CELES] = "CELES", [RELM] = "RELM" }
-- Narshe's gate (world 1 (115,33) -> map 32 (38,61)), and the plain south of
-- it where the Falcon lands and the arc saves (wor-narshe-v1's tile)
local NARSHE_DOOR, LANDING = { 115, 33 }, { 115, 38 }
local NARSHE_WORLD = { { 115, 33 } }
-- magicite: give_genju's receipt order (Ramuh 0); Ragnarok is 16
local RAGNAROK = 16
-- the town's doors (route_data.py map 32): a walk keeps off every door but
-- its own
local NARSHE_DOORS = { { 41, 36 }, { 52, 37 }, { 32, 30 }, { 29, 25 }, { 18, 22 }, { 32, 16 }, { 41, 22 },
  { 43, 11 }, { 46, 10 }, { 49, 12 }, { 53, 9 }, { 15, 56 }, { 22, 44 }, { 10, 36 }, { 26, 8 }, { 33, 54 } }
-- the six locks (map 32 NPC_2-NPC_7, npc_prop.asm:1798-1838): each stands on
-- the tile below its door, shown by its switch ($06C0-$06C5) until LOCKE,
-- in the party, picks it (_cc0a9e-_cc0aee: set_case PARTY_CHARS, $01A1)
local LOCKS = {
  inn = { obj = 0x11, sw = 0x06C0, door = { 41, 36 } },
  weapon = { obj = 0x12, sw = 0x06C1, door = { 32, 30 } },
  relic = { obj = 0x13, sw = 0x06C2, door = { 29, 25 } },
  treasure = { obj = 0x14, sw = 0x06C3, door = { 52, 37 } },
  cursed = { obj = 0x15, sw = 0x06C4, door = { 32, 16 } },
  items = { obj = 0x16, sw = 0x06C5, door = { 41, 22 } },
}
local FIGHT = {}

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
-- The Back Guard on the plain (#452).  The plain south of Narshe (world
-- group 51) deals the Mantodea pair (formation 325, 80/256) and permits a
-- pincer, which forces every member to the front row and lands the blows
-- from behind (InitBattleType_02, UpdateFacingDirection: +50%): vanilla's
-- arithmetic on a vanilla monster (L54, attack 180), one blow a member from
-- full in the Gau arc's sweep (build/attempts/wt/v033-wor-gau/lab/swa_k3_s7,
-- key be24-g0145).  The bag's Back Guard drops the pincer and the back attack
-- from the roll; it goes on LOCKE over his Star Pendant (he has no Ribbon
-- until the treasure room's relic plan hands him one, #490), and RELM goes to
-- the back row.  Measured from this leg's capture (build/attempts/wt/
-- v038-wor-fights/lab/narshe/): without it formation 325 rolled a pincer or
-- a back attack in 3 of 50 keys, be24 a pincer; with it none in 47, be24 a
-- side attack, won with no one down.
local function wearsBackGuard(ch)
  return H.readByte(c(ch, 0x23)) == BACK_GUARD or H.readByte(c(ch, 0x24)) == BACK_GUARD
end
local function backGuard(what)
  return H.seqStep({
    H.cond(function() return not wearsBackGuard(LOCKE) end, {
      H.equipKit(LOCKE, { { 5, BACK_GUARD } }, { tag = "LOCKE: the Back Guard (" .. what .. ")" }),
    }, {}),
    H.call(function()
      H.assertEq(wearsBackGuard(LOCKE), true, "LOCKE wears the Back Guard (" .. what .. ")")
    end),
  })
end
local function kitLine()
  local t = {}
  for _, ch in ipairs(SEATED) do
    local g = {}
    for k = 0x1E, 0x24 do g[#g + 1] = string.format("%02X", H.readByte(c(ch, k))) end
    t[#t + 1] = string.format("%s L%d vig %d mag %d kit %s", NAMES[ch], lv(ch), H.readByte(c(ch, 0x1A)),
      H.readByte(c(ch, 0x1D)), table.concat(g, " "))
  end
  return table.concat(t, "; ")
end
local function except(list, x, y)
  local out = {}
  for _, d in ipairs(list) do if not (d[1] == x and d[2] == y) then out[#out + 1] = d end end
  return out
end
local function walkTo(x, y, what, avoid)
  return H.seqStep({
    H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT, avoid = avoid }),
    H.call(function() H.log(string.format("[route] %s: at (%d,%d)", what, H.fieldX(), H.fieldY())) end),
  })
end
-- a walk by waypoints (the planner's radius cap: gen_wor_narshe's via)
local function via(points, what, avoid)
  local steps = {}
  for _, p in ipairs(points) do
    steps[#steps + 1] = H.navTo(p[1], p[2], { maxFrames = 8000, playBattles = "tactical", fight = FIGHT, avoid = avoid })
  end
  steps[#steps + 1] = H.call(function() H.log(string.format("[route] %s: at (%d,%d)", what, H.fieldX(), H.fieldY())) end)
  return H.seqStep(steps)
end
-- walk onto (x, y) until the map reads dst (gen_wor_narshe's)
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
-- a chest from whichever side of it the party can reach (gen_wor_narshe's)
local function chestAt(cx, cy, bit, what, item, avoid)
  return H.lazy(function()
    local av = {}
    for _, d in ipairs(avoid or {}) do av[((d[2] & 0xFF) << 8) | (d[1] & 0xFF)] = true end
    for _, o in ipairs({ { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }) do
      if H.bfsPath(cx + o[1], cy + o[2], nil, av) then
        return H.openChest({ stand = { cx + o[1], cy + o[2] }, face = o[3], bit = bit, what = what, item = item,
          nav = { fight = FIGHT, avoid = avoid } })
      end
    end
    error(string.format("[chest] %s (%d,%d): no side of it is reachable from (%d,%d)", what, cx, cy,
      H.fieldX(), H.fieldY()))
  end)
end
-- the live object an NPC's posted tile names, the nearest within two tiles
-- (gen_wor_narshe's npcAt); every object's tile is logged when none is
local function npcAt(x, y, what)
  local best, bd = nil, 99
  for o = 0x10, 0x2F do
    local d = math.abs(H.objX(o) - x) + math.abs(H.objY(o) - y)
    if d < bd then best, bd = o, d end
  end
  if bd > 2 then
    local t = {}
    for o = 0x10, 0x2F do t[#t + 1] = string.format("$%02X(%d,%d)", o, H.objX(o), H.objY(o)) end
    H.log(string.format("[npc] %s: the objects: %s", what, table.concat(t, " ")))
  end
  H.assertEq(bd <= 2, true, string.format("%s: an object stands within 2 tiles of (%d,%d)", what, x, y))
  H.log(string.format("[npc] %s: object $%02X at (%d,%d)", what, best, H.objX(best), H.objY(best)))
  return best
end
local function talkTo(x, y, what, done)
  return H.lazy(function() return H.talkToObj(npcAt(x, y, what), what, nil, done) end)
end
-- LOCKE picks a lock: stand below it (its door is the tile above), talk to
-- it, and ride the scene until its switch reads clear and the party has
-- control again
local function unlock(name)
  local L = LOCKS[name]
  local what = string.format("the %s lock (32 (%d,%d))", name, L.door[1], L.door[2] + 1)
  return H.seqStep({
    H.call(function() H.assertEq(H.partyOfChar(LOCKE), 1, what .. ": LOCKE in the party ($01A1 at set_case)") end),
    H.navTo(L.door[1], L.door[2] + 2, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT,
      avoid = NARSHE_DOORS }),
    H.cond(function() return sw(L.sw) == 1 end, {
      H.talkToObj(L.obj, what, nil, function() return sw(L.sw) == 0 end),
    }, {}),
    H.waitUntil(function() return sw(L.sw) == 0 and settled() end, 3000, what .. ": picked", 1),
    H.call(function() say("lock", what .. " picked") end),
  })
end
-- through an unlocked door onto its map (crossDoor stages below it)
local function enter(name, dst, lx, ly, what)
  local L = LOCKS[name]
  return H.crossDoor(L.door[1], L.door[2], dst, lx, ly, what, { fight = FIGHT })
end
-- out of a house by its exit tile, back to the street
local function out(x, y, what)
  return walkInto(x, y, MAP_NARSHE, what)
end

-- the town's keepers: every shop's and the inn's (maps 24-28 NPC_1) is
-- shown by switch $0600 (npc_prop.asm:1512-1575); a counter is talked to
-- only while its keeper stands there
local function keeper() return sw(0x0600) == 1 end
local function keeperLine(what)
  return H.call(function()
    H.log(string.format("[shop] %s: the keeper's switch $0600 = %d (%s)", what, sw(0x0600),
      keeper() and "the keeper stands at the counter" or "no keeper: the counter is empty"))
  end)
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

-- Ragnarok's wearer (kits.md, Terra: "everyone else gets Ultima by
-- equipping Ragnarok", a multiplier spell; magicite.md: the Last Word, a
-- BOSS package of vigor and magic): the seated member other than TERRA
-- (whose Fire folds into Ultima already) with the highest magic, which
-- Ultima's damage reads
local function ragnarokWearer()
  local best, bm = nil, -1
  for _, ch in ipairs(SEATED) do
    if ch ~= TERRA then
      local m = H.readByte(c(ch, 0x1D))
      if m > bm then best, bm = ch, m end
    end
  end
  return best
end
local wearer = nil

H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-locke-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine())
    -- what the plan depends on (#480): the Back Guard is the party's own,
    -- carried since the World of Balance and last worn in the Figaro cave
    -- (gen_wor_edgar puts it back in the bag); no counter on this leg sells one
    -- (backGuard() equips from the bag only, or leaves LOCKE's own: a Back
    -- Guard on another member is not one it can use, #490)
    local n = H.invCountOf(BACK_GUARD) + (wearsBackGuard(LOCKE) and 1 or 0)
    H.assertEq(n >= 1, true, "LOCKE wears a Back Guard ($E1) or the bag holds one for the plain's pincers (carried "
      .. "since the World of Balance; gen_wor_edgar puts it back in the bag after the Figaro cave)")
  end),
  -- @@setup-end
  backGuard("the plain south of Narshe"),
  -- RELM to the back row (#452): she stood in the front row since she
  -- joined, where a Mantodea's Battle took her from full in one blow (20 of
  -- the two arms' 24 deaths to formation 325 were hers, 18 of them "ONE
  -- ACTION from >= 80%"); the back row halves the blows a painter takes
  -- (lab/narshe/nc_*: 0.02 deaths a fight over 49 keys, against 0.09 over 47
  -- with the Back Guard alone and 0.12 over 50 with neither -- counted by
  -- distinct key; by fight the Back Guard alone cut no deaths, 11 in the
  -- first arm's 120 fights against 13 in the second's: it removed the
  -- pincer and back attacks, and the gain came from RELM's row; #490)
  H.setRows({ [RELM] = true }, { tag = "RELM to the back row" }),
  H.call(function()
    H.assertEq(H.readByte(0x1850 + RELM) & 0x20, 0x20, "RELM stands in the back row ($1850 bit 5)")
  end),

  -- ---- 1. the Falcon to Narshe ------------------------------------------------------
  -- @@stage flight
  board(),
  H.flyTo(LANDING[1], LANDING[2], { what = "the Falcon to the plain south of Narshe", fight = FIGHT }),
  H.waitWorldSettled("landed south of Narshe", 1800, 30),
  H.worldNavTo(NARSHE_DOOR[1], NARSHE_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_NARSHE and not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_NARSHE and settled() end, 2400, "Narshe: map 32", 1),
  H.call(function() say("route", "in Narshe") end),
  H.saveState("wor_ragnarok_town.mss"),

  -- ---- 2. the elder's treasure room ---------------------------------------------------
  -- @@stage treasure
  -- the lock below (52,37); the door lands in map 30 (79,17), the room of
  -- six chests (77-80, 8-12): Hyper Wrist, Sneak Ring, Wall Ring, ThiefKnife,
  -- Earrings and 5,000 GP (route_data.py map 30; bits $004-$009).  (77,9)
  -- is empty in the ROM (bit $003) and stands under an object; it stays shut
  via({ { 38, 48 }, { 40, 38 }, { 46, 32 }, { 48, 26 }, { 50, 21 }, { 53, 25 }, { 52, 32 }, { 49, 36 } },
    "Narshe's street to the treasure room's lock", NARSHE_DOORS),
  unlock("treasure"),
  enter("treasure", MAP_ELDER, 79, 17, "Narshe -> the elder's treasure room (30 (79,17))"),
  chestAt(78, 8, 0x004, "Hyper Wrist (30 (78,8))", HYPER_WRIST, { { 79, 18 } }),
  chestAt(79, 8, 0x005, "Sneak Ring (30 (79,8))", SNEAK_RING, { { 79, 18 } }),
  chestAt(80, 8, 0x006, "Wall Ring (30 (80,8))", WALL_RING, { { 79, 18 } }),
  chestAt(78, 10, 0x007, "ThiefKnife (30 (78,10))", THIEFKNIFE, { { 79, 18 } }),
  chestAt(79, 10, 0x008, "Earrings (30 (79,10))", EARRINGS, { { 79, 18 } }),
  chestAt(80, 12, 0x009, "5,000 GP (30 (80,12))", nil, { { 79, 18 } }),
  out(79, 18, "the treasure room -> Narshe (32 (52,39))"),
  H.saveState("wor_ragnarok_treasure.mss"),

  -- ---- 3. the weapon shop and Ragnarok -------------------------------------------------
  -- @@stage ragnarok
  -- the lock below (32,30); the shop (map 24) lands at (25,13), its back
  -- room door (31,13) -> (46,47); the old man (24 NPC_3 (43,50), _cc0b1e):
  -- "Make this stone into a sword?"  The stone (choice 0, give_genju
  -- RAGNAROK, $00B6): magicite.md's Last Word.  (45,51) is the room's bed
  -- (_cacd17), kept off the walk
  via({ { 49, 36 }, { 44, 37 }, { 38, 36 }, { 33, 34 } }, "Narshe's street to the weapon shop's lock", NARSHE_DOORS),
  unlock("weapon"),
  enter("weapon", MAP_WEAPON, 25, 13, "Narshe -> the weapon shop (24 (25,13))"),
  H.navTo(31, 12, { maxFrames = 3000 }),
  H.navTo(31, 13, { maxFrames = 3000, arrive = function() return H.fieldY() >= 40 end }),
  H.waitUntil(function() return H.fieldY() >= 40 and settled() end, 1200, "in the back room (24 (46,47))", 1),
  walkTo(44, 50, "beside the old man", { { 45, 51 }, { 46, 45 } }),
  H.talkToObj(0x12, "the old man (24 NPC_3 (43,50))"),
  H.dialogChoice(0, { inBattle = false, what = "Leave it the stone \"Ragnarok\"", tag = "Ragnarok" }),
  H.advanceStory(function() return sw(0x00B6) == 1 and settled() end, 3000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function()
    H.assertEq((H.readByte(0x1A69 + (RAGNAROK >> 3)) >> (RAGNAROK & 7)) & 1, 1, "Ragnarok owned (give_genju)")
    say("esper", "Ragnarok, the stone")
  end),
  walkTo(46, 46, "the back room's door", { { 45, 51 } }),
  H.navTo(46, 45, { maxFrames = 3000, arrive = function() return H.fieldY() < 20 end }),
  H.waitUntil(function() return H.fieldY() < 20 and settled() end, 1200, "back in the shop (24 (31,12))", 1),
  out(25, 14, "the weapon shop -> Narshe (32 (32,32))"),
  H.saveState("wor_ragnarok_stone.mss"),

  -- ---- 4. the relic shop, the Cursed Shld ------------------------------------------------
  -- @@stage relic
  -- the relic shop (29,25) -> map 27 (64,13), its keeper (64,7), shop 70;
  -- the elder's house door (32,16) -> map 30 (80,35), the old man (87,45),
  -- _cc0b70: the Cursed Shld ($00B8)
  unlock("relic"),
  enter("relic", MAP_RELICS, 64, 13, "Narshe -> the relic shop (27 (64,13))"),
  keeperLine("Narshe's relic shop"),
  H.cond(keeper, {
    H.shopTalk(64, 7, "Narshe's relic counter", { fight = FIGHT }),
    H.call(function()
      H.assertEq(H.shopId(), 70, "the counter opened shop 70 ($0201)")
      say("shop", "Narshe's relic counter (shop 70)")
    end),
    H.shopClose("Narshe's relic counter"),
  }, {}),
  out(64, 14, "the relic shop -> Narshe (32 (29,27))"),
  unlock("cursed"),
  enter("cursed", MAP_ELDER, 80, 35, "Narshe -> the elder's house (30 (80,35))"),
  walkTo(86, 45, "beside the Cursed Shld's old man (he lies in bed, facing right)", { { 80, 36 } }),
  talkTo(87, 45, "the old man (30 NPC_26 (87,45))", function() return sw(0x00B8) == 1 end),
  H.advanceStory(function() return sw(0x00B8) == 1 and settled() end, 3000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function()
    H.assertEq(H.invCountOf(CURSED_SHLD) >= 1, true, "a Cursed Shld in the bag")
    say("item", "the Cursed Shld")
  end),
  walkTo(80, 35, "the house's door", { { 80, 36 } }),
  out(80, 36, "the elder's house -> Narshe (32 (32,18))"),
  H.saveState("wor_ragnarok_relic.mss"),

  -- ---- 5. the item counter, the gear counters, the inn -------------------------------------
  -- @@stage shops
  unlock("items"),
  enter("items", MAP_ITEMS, 44, 13, "Narshe -> the item shop (26 (44,13))"),
  keeperLine("Narshe's item shop"),
  H.cond(keeper, {
    H.shopTalk(44, 8, "Narshe's item counter", { fight = FIGHT }),
    H.call(function() H.assertEq(H.shopId(), 71, "the counter opened shop 71 ($0201)") end),
    -- the bag for the next arc at the four's level (gen_wor_locke's bands)
    H.buyItem(POTION, function() return math.max(0, H.careStockPotions(H.activeTopLevel(), { spend = 40 })
      - H.invCountOf(POTION)) end, "POTION to the band"),
    H.buyItem(FENIX, function() return math.max(0, math.min(20, H.activeTopLevel()) - H.invCountOf(FENIX)) end,
      "FENIX DOWN to the level, capped at 20"),
    H.buyItem(TINCTURE, function() return math.max(0, -(-H.activeTopLevel() // 4) - H.invCountOf(TINCTURE)) end,
      "TINCTURE to the band"),
    H.buyItem(REMEDY, function() return math.max(0, 10 - H.invCountOf(REMEDY)) end, "REMEDY to 10"),
    H.shopClose("Narshe's item counter"),
    H.bagArrange({ POTION, FENIX, REMEDY, TINCTURE }, { tag = "bag: combat items on top (Narshe)" }),
    H.call(function() say("shop", "Narshe's item counter") end),
  }, {}),
  out(44, 14, "the item shop -> Narshe (32 (41,24))"),
  H.cond(keeper, {
    H.gearStop({ tag = "gear Narshe", fight = FIGHT, avoid = NARSHE_DOORS }),     -- #434: buy power with gil
  }, {
    keeperLine("Narshe's weapon and armor counters"),
  }),
  -- Ragnarok onto its wearer, the treasure room's relics and knife through
  -- the care
  H.call(function()
    wearer = ragnarokWearer()
    H.log(string.format("[kit] Ragnarok's wearer: %s (magic %d), who wore stone $%02X", NAMES[wearer],
      H.readByte(c(wearer, 0x1D)), H.readByte(c(wearer, 0x1E))))
  end),
  H.lazy(function()
    return H.equipEsper(function() return (H.readByte(0x1850 + wearer) >> 3) & 3 end, RAGNAROK,
      { tag = "RAGNAROK -> " .. NAMES[wearer] })
  end),
  H.gearDress({ tag = "gear from the treasure room" }),
  H.dressRelics({ { LOCKE, "LOCKE" }, { TERRA, "TERRA" }, { CELES, "CELES" }, { RELM, "RELM" } },
    { tag = "relics with the treasure room's" }),
  H.call(function()
    H.assertEq(H.readByte(c(wearer, 0x1E)), RAGNAROK, NAMES[wearer] .. " wears Ragnarok")
    H.log("[kit] " .. kitLine())
  end),
  unlock("inn"),
  enter("inn", MAP_INN, 8, 45, "Narshe -> the inn (28 (8,45))"),
  keeperLine("Narshe's inn"),
  H.cond(keeper, {
    H.lazy(function()
      for _, y in ipairs({ 39, 40, 41 }) do
        if H.bfsPath(8, y) then
          return H.innRest({ spot = { 8, y }, face = "up", price = 200, tag = "Narshe inn" })
        end
      end
      error(string.format("[inn] no tile below the keeper (8,38) is reachable from (%d,%d)", H.fieldX(), H.fieldY()))
    end),
  }, {}),
  out(8, 46, "the inn -> Narshe (32 (41,38))"),
  H.saveState("wor_ragnarok_shops.mss"),

  -- ---- 6. out of the gate, and the save -------------------------------------------------------
  -- @@stage save
  backGuard("the walk back to the Falcon"),
  via({ { 38, 40 }, { 38, 50 } }, "Narshe's street to the gate", NARSHE_DOORS),
  H.navTo(38, 61, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, avoid = NARSHE_DOORS,
    arrive = function() return H.worldMode() end }),
  H.driveUntil(function() return H.worldMode() end, 3000, { H.hold({ "down" }), H.waitFrames(4) }, "off Narshe's gate"),
  H.release(),
  H.waitWorldSettled("out of Narshe", 1800, 30),
  H.worldNavTo(LANDING[1], LANDING[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    avoid = NARSHE_WORLD }),
  H.waitFrames(90),
  H.worldNavTo(LANDING[1], LANDING[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    avoid = NARSHE_WORLD }),
  H.fieldCare({ threshold = 1.0, tag = "on the save tile" }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled on the save tile", 5),
  H.call(function()
    say("wor", "on the save tile")
    H.log("[kit] " .. kitLine())
  end),
  H.saveAtCheckpoint("wor-ragnarok-v1"),
  H.saveState("wor_ragnarok.mss"),
  H.logStep(function()
    return string.format("wor_ragnarok generated: LOCKE L%d, TERRA L%d, CELES L%d and RELM L%d beside the Falcon "
      .. "outside Narshe, world (%d,%d), saved in slot 3", lv(LOCKE), lv(TERRA), lv(CELES), lv(RELM), H.worldX(),
      H.worldY())
  end),
})
