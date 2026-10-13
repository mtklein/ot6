-- gen_wor_narshe.lua -- the World of Ruin from Jidoor to the cliffs above
-- Narshe: Continue the `wor-cyan-v1` battery (CYAN, TERRA, CELES and SABIN on
-- foot beside the Falcon outside Jidoor), Jidoor's weapon counter (a Partisan
-- for MOG) and item counter, the cabin (CYAN, TERRA and CELES; SABIN waits
-- aboard, Ifrit to CYAN), Narshe, the elder's house to the moogle cave, MOG
-- (he joins into the empty seat), back through the town and up the cliffs to
-- their save point: the `wor-narshe-cliffs-v1` battery, the retry point for
-- the Ice Dragon, Tritoch and Umaro's cave.
-- docs/design/route-wor-narshe.md has the plan and what this measured.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CYAN, EDGAR, SABIN, CELES, SETZER, MOG = 0, 2, 4, 5, 6, 9, 10
local TONIC, POTION, FENIX, REMEDY, SOFT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4
local REVIVIFY, TENT, XPOTION, ETHER, ELIXIR, TINCTURE = 0xF1, 0xF7, 0xEA, 0xEC, 0xEE, 0xEB
local PARTISAN, RIBBON, MOOGLE_CHARM = 0x20, 0xCA, 0xDE
local MAP_JIDOOR, MAP_JIDOOR_SHOP, MAP_JIDOOR_WEAPON = 198, 201, 204
local MAP_NARSHE, MAP_ELDER, MAP_CLIFF_LO, MAP_CLIFF_SAVE, MAP_MINES = 32, 30, 33, 34, 36
local MAP_MOOGLE, MAP_MOOGLE_B, MAP_MOG = 38, 37, 44
local JIDOOR_DOOR = { 35, 156 }
local JIDOOR_WORLD = { { 34, 156 }, { 35, 156 } }
-- Narshe's gate (world 1 (115,33) -> map 32 (38,61); route_data.py
-- world-entrances 1) and the Falcon's landing a step south of it
local NARSHE_DOOR, NARSHE_LANDING = { 115, 33 }, { 115, 35 }
local NARSHE_WORLD = { { 115, 33 } }
-- magicite: give_genju's receipt order (Ramuh 0)
local IFRIT = 1
-- the Potions the arc's legs spend from Jidoor to the next counter (the
-- Ice Dragon, Tritoch, Umaro and the cave's randoms; the Storm Dragon alone
-- cost 0-24, route-wor-cyan.md 8.2); the stack caps at 99
local POTION_SPEND = 60
local function potionTarget() return H.careStockPotions(H.activeTopLevel(), { spend = POTION_SPEND }) end
-- Tents for the cliffs' save point, the arc's only rest (Narshe's inn is
-- behind LOCKE's lock): one before each of the three fights
local TENT_TARGET = 4
-- Narshe's doors (route_data.py map 32): a walk keeps off every door but its
-- own; the lock objects stand on the tiles below six of them
local NARSHE_DOORS = { { 41, 36 }, { 52, 37 }, { 32, 30 }, { 29, 25 }, { 18, 22 }, { 32, 16 }, { 41, 22 },
  { 43, 11 }, { 46, 10 }, { 49, 12 }, { 53, 9 }, { 15, 56 }, { 22, 44 }, { 10, 36 }, { 26, 8 }, { 33, 54 } }
-- the elder's house (map 30): its exits to the town
local ELDER_DOORS = { { 55, 35 }, { 67, 26 }, { 110, 26 }, { 80, 36 }, { 79, 18 } }

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function c(ch, off) return 0x1600 + 37 * ch + off end
local function level(ch) return H.readByte(c(ch, 8)) end
local function partyOf(ch) return H.readByte(0x1850 + ch) & 7 end
local function inParty(ch) return partyOf(ch) ~= 0 end
local function kit(ch)
  local t = {}
  for k = 0x1E, 0x24 do t[#t + 1] = string.format("%02X", H.readByte(c(ch, k))) end
  return table.concat(t, " ")
end
local MEMBERS = { { TERRA, "TERRA" }, { CYAN, "CYAN" }, { EDGAR, "EDGAR" }, { SABIN, "SABIN" }, { CELES, "CELES" },
  { SETZER, "SETZER" }, { MOG, "MOG" } }
local function supplies()
  return string.format("tonic=%d potion=%d xpotion=%d ether=%d elixir=%d tincture=%d fenix=%d remedy=%d soft=%d "
    .. "revivify=%d tent=%d gil=%d", H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(XPOTION),
    H.invCountOf(ETHER), H.invCountOf(ELIXIR), H.invCountOf(TINCTURE), H.invCountOf(FENIX), H.invCountOf(REMEDY),
    H.invCountOf(SOFT), H.invCountOf(REVIVIFY), H.invCountOf(TENT), H.gil())
end
local function member(ch, name)
  return string.format("%s(p%d) L%d HP %d/%d MP %d/%d status1 $%02X", name, partyOf(ch), level(ch), H.charHp(ch),
    H.charMaxHp(ch), H.charMp(ch), H.charMaxMp(ch), H.charStatus1(ch))
end
local function whereLine()
  local t = {}
  for _, p in ipairs(MEMBERS) do if inParty(p[1]) then t[#t + 1] = member(p[1], p[2]) end end
  return table.concat(t, "; ")
end
local function kitLine()
  local t = {}
  for _, p in ipairs(MEMBERS) do t[#t + 1] = p[2] .. " " .. kit(p[1]) end
  return "kit " .. table.concat(t, ", ")
end
local function say(tag, what)
  local pos = H.worldMode() and string.format("world (%d,%d)", H.worldX(), H.worldY())
    or string.format("map %d (%d,%d)", map(), H.fieldX(), H.fieldY())
  H.log(string.format("[%s] f%d %s %s: %s; %s", tag, H.frame, what, pos, whereLine(), supplies()))
end

local FIGHT = {}
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
end
-- a step built when it is first reached (its arguments decided live)
local function lazy(build)
  local step = nil
  return {
    tick = function()
      if step == nil then step = build() end
      return step:tick()
    end,
    reset = function()
      if step and step.reset then step:reset() end
      step = nil
    end,
  }
end
-- the doors of `list` but (x, y), for a walk's avoid list
local function exceptOf(list, x, y)
  local out = {}
  for _, d in ipairs(list) do if not (d[1] == x and d[2] == y) then out[#out + 1] = d end end
  return out
end
-- walk onto (x, y) until the map reads dst
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
    H.call(function()
      H.log(string.format("[route] %s: on map %d at (%d,%d)", what, map(), H.fieldX(), H.fieldY()))
      H.assertEq(map(), dst, what .. ": on map " .. dst)
    end),
  })
end
-- a door that leads to another place on the same map (the moogle cave's
-- inner doors): walk onto it until the party stands far from it
local function warpVia(x, y, what, avoid)
  local function moved()
    return math.abs(H.fieldX() - x) + math.abs(H.fieldY() - y) > 4 and H.hasControl() and H.tileAligned()
      and bright() >= 15
  end
  local x0, y0 = nil, nil
  return H.withReset(H.seqStep({
    H.call(function() x0, y0 = H.fieldX(), H.fieldY() end),
    H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT, avoid = avoid,
      arrive = function()
        return math.abs(H.fieldX() - x) + math.abs(H.fieldY() - y) > 4
          and math.abs(H.fieldX() - x0) + math.abs(H.fieldY() - y0) > 4
      end }),
    H.release(),
    H.waitUntil(moved, 1200, what .. ": through the door", 1),
    H.call(function() H.log(string.format("[route] %s: on map %d at (%d,%d)", what, map(), H.fieldX(), H.fieldY())) end),
  }), function() x0, y0 = nil, nil end)
end
-- the live object an NPC's posted tile names, the nearest within four tiles
local function npcAt(x, y, what)
  local best, bd = nil, 99
  for o = 0x10, 0x2F do
    local d = math.abs(H.objX(o) - x) + math.abs(H.objY(o) - y)
    if d < bd then best, bd = o, d end
  end
  if bd > 4 then
    local t = {}
    for o = 0x10, 0x2F do t[#t + 1] = string.format("$%02X(%d,%d)", o, H.objX(o), H.objY(o)) end
    H.log(string.format("[npc] %s: the objects: %s", what, table.concat(t, " ")))
  end
  H.assertEq(bd <= 4, true, string.format("%s: an object stands within 4 tiles of (%d,%d)", what, x, y))
  H.log(string.format("[npc] %s: object $%02X at (%d,%d)", what, best, H.objX(best), H.objY(best)))
  return best
end
local function talkTo(x, y, what)
  return lazy(function() return H.talkToObj(npcAt(x, y, what), what) end)
end
local function walkTo(x, y, what, avoid)
  return H.seqStep({
    H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT, avoid = avoid }),
    H.call(function() H.log(string.format("[route] %s: at (%d,%d)", what, H.fieldX(), H.fieldY())) end),
  })
end
-- a story stretch that may open a naming menu (MOG's, `name_menu`): the
-- ride taps A through the dialogs, and while a field menu is up ($0059)
-- presses START, which commits the default name (gen_moogle's LOCKE)
local function rideNaming(pred, maxF, what)
  local ph = 0
  return H.withReset(H.seqStep({
    H.driveUntil(function() return pred() and settled() end, maxF, {
      H.call(function()
        ph = (ph + 1) % 16
        if H.readByte(0x0059) ~= 0 then H.setPad(ph < 6 and { "start" } or {}); return end
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, what),
    H.release(),
    H.call(function() say("story", what) end),
  }), function() ph = 0 end)
end
-- a chest from whichever side of it the party can reach
local function chestAt(cx, cy, bit, what, item, avoid)
  return lazy(function()
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
      H.call(function()
        H.log(string.format("[board] f%d on (%d,%d), the Falcon parked at (%d,%d): walking back onto it", H.frame,
          H.worldX(), H.worldY(), H.readByte(0x1F62), H.readByte(0x1F63)))
      end),
      H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
        { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
    }, {}),
    H.call(function()
      if H.battleLoadStarted() then
        battleFrames = battleFrames + 1
        if battleFrames == 3 then
          local w = H.formationWords()
          H.log(string.format("[board] f%d a battle came up while boarding (%04X %04X %04X %04X)", H.frame,
            w[1], w[2], w[3], w[4]))
        end
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
-- out of a town by its edge: walk to (x, y), then hold `dir` off the map,
-- and back onto the parked Falcon's tile
local function toFalconBy(x, y, dir, what, worldDoors)
  return H.seqStep({
    H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT }),
    H.driveUntil(function() return H.worldMode() end, 6000, { H.hold({ dir }), H.waitFrames(4) }, "off " .. what .. "'s edge"),
    H.release(),
    H.waitWorldSettled("out of " .. what, 1800, 30),
    H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
      { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, avoid = worldDoors }),
  })
end

-- ---- the key of every battle (reads only) --------------------------------
local watchOn = false
local function watches()
  return H.call(function()
    if watchOn then return end
    watchOn = true
    local addr = H.seedStoreAddr()
    emu.addMemoryCallback(function()
      H.log(string.format("[key] battle key be%02X-g%04X f%d map %d", emu.getState()["cpu.a"] & 0xff,
        H.readWord(0x11e0), H.frame, map()))
    end, emu.callbackType.exec, addr, addr)
  end)
end

-- ---- the Falcon's cabin: CYAN, TERRA and CELES -----------------------------
-- (gen_wor_cyan's regroup) the cabin's waiting members (map 12) each ask
-- "Change party members?" (_caf59d); the party menu seats the three, and the
-- fourth seat stays empty for MOG, who joins into it (_cc3a4c: char_party
-- MOG when the party has room).  SABIN waits aboard with EDGAR and SETZER
-- (route-wor-narshe.md 5.4).
local MAP_DECK, MAP_CABIN = 11, 12
local REGROUP = { CYAN, TERRA, CELES }
local CABIN_NPCS = { { "CYAN", 0x12, 0x038B }, { "EDGAR", 0x14, 0x038C }, { "SETZER", 0x19, 0x0391 },
  { "SABIN", 0x15, 0x038D }, { "CELES", 0x16, 0x038E }, { "TERRA", 0x10, 0x0388 } }
local function regroup(members)
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
    H.call(function()
      local t = {}
      for _, p in ipairs(MEMBERS) do t[#t + 1] = string.format("%s $1850=%02X", p[2], H.readByte(0x1850 + p[1])) end
      H.log("[regroup] in the cabin: " .. table.concat(t, " "))
      pickTalker()
    end),
    H.cond(function() return obj == nil end, {
      H.navTo(23, 44, { maxFrames = 3000, arrive = function() return H.fieldY() < 40 end }),
      H.waitUntil(function() return settled() and H.fieldY() < 40 end, 1200, "up the cabin's stairs", 1),
      H.call(function() pickTalker() end),
    }, {}),
    H.call(function()
      H.assertEq(obj ~= nil, true, "a member waits in the cabin to talk to")
      H.log(string.format("[regroup] talking to %s (obj $%02X, show-switch $%04X)", obj[1], obj[2], obj[3]))
    end),
    lazy(function() return H.talkToObj(obj[2], obj[1] .. " in the cabin") end),
    H.dialogChoice(1, { inBattle = false, what = "Change party members? Yes", tag = "the cabin" }),
    H.partySelect(members, { tag = "the Falcon's cabin" }),
    H.waitUntil(function() return map() == MAP_DECK and settled() end, 2400, "back on the deck after the menu", 5),
    H.call(function()
      for _, ch in ipairs(members) do
        H.assertEq(partyOf(ch) == 1, true, string.format("char %d is in party 1 after the regroup", ch))
      end
      H.assertEq(inParty(SABIN), false, "SABIN waits aboard")
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

-- ---- gear ------------------------------------------------------------------
-- ItemProp (30-byte records): +0 type (low 3 bits: 1 weapon, 2 armor, 3
-- shield, 4 helmet, 5 relic), +1 the actor mask (a word), +$14 power or
-- defense, +$15 magic defense
local IP = nil
local function ip(id, off)
  IP = IP or (H.sym("ItemProp") & 0x3FFFFF)
  return H.readRomByte(IP + id * 30 + off)
end
local function wearable(ch, id)
  local mask = ip(id, 1) | (ip(id, 2) << 8)
  return (mask >> H.charActor(ch)) & 1 == 1
end
local function guard(id) return (id == 0xFF) and 0 or (ip(id, 0x14) + ip(id, 0x15)) end
local function bestInBag(ch, kind)
  local best, bs = nil, -1
  for s = 0, 255 do
    local id, n = H.readByte(0x1869 + s), H.readByte(0x1969 + s)
    if id ~= 0xFF and n > 0 and (ip(id, 0) & 7) == kind and wearable(ch, id) then
      local sc = kind == 1 and ip(id, 0x14) or guard(id)
      if sc > bs then best, bs = id, sc end
    end
  end
  return best, bs
end
-- dress a character's hand and armor slots from the bag where the bag holds
-- better than what is worn (slots: 0 weapon, 1 shield, 2 helmet, 3 armor)
local function dressFromBag(ch, name)
  return lazy(function()
    local items = {}
    for _, sl in ipairs({ { 0, 1 }, { 1, 3 }, { 2, 4 }, { 3, 2 } }) do
      local cur = H.readByte(c(ch, 0x1F + sl[1]))
      -- a second weapon in the left hand (a Genji Glove's) stays
      if sl[1] == 1 and cur ~= 0xFF and (ip(cur, 0) & 7) == 1 then goto continue end
      local id, sc = bestInBag(ch, sl[2])
      local cs = (cur == 0xFF) and -1 or (sl[2] == 1 and ip(cur, 0x14) or guard(cur))
      if id and sc > cs then items[#items + 1] = { sl[1], id } end
      H.log(string.format("[kit] %s slot %d: wears $%02X (%d), the bag's best $%02X (%d)", name, sl[1], cur, cs,
        id or 0xFF, sc or -1))
      ::continue::
    end
    if #items == 0 then return H.call(function() end) end
    return H.equipKit(ch, items, { tag = name .. " from the bag" })
  end)
end
local function posOf(ch) return (H.readByte(0x1850 + ch) >> 3) & 3 end

H.run({ maxFrames = 400000 }, {
  H.bootCheckpoint("wor-cyan-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[wor] " .. kitLine())
  end),
  -- @@setup-end

  -- ---- 1. Jidoor: a Partisan for MOG, and the arc's supplies ----------------
  -- @@stage jidoor
  H.worldNavTo(JIDOOR_DOOR[1], JIDOOR_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_JIDOOR and not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_JIDOOR and settled() end, 2400, "Jidoor: map 198", 1),
  -- the weapon shop (198 (16,41) -> 204, the counter at (39,43), shop 76):
  -- a Partisan (pow 150, pierce) for MOG, who joins with a Mithril Pike at
  -- best (route-wor-narshe.md 6.2)
  H.crossDoor(16, 41, MAP_JIDOOR_WEAPON, 39, 50, "Jidoor's weapon shop door 198 (16,41) -> 204", { fight = FIGHT }),
  H.shopTalk(39, 43, "Jidoor's weapon shop", { fight = FIGHT }),
  H.call(function() H.assertEq(H.shopId(), 76, "the counter opened shop 76 ($0201)") end),
  H.buyItem(PARTISAN, function() return math.max(0, 1 - H.invCountOf(PARTISAN)) end, "PARTISAN for MOG"),
  H.shopClose("Jidoor's weapon shop"),
  H.crossDoor(39, 51, MAP_JIDOOR, 16, 43, "Jidoor's weapon shop -> the street", { fight = FIGHT }),
  H.crossDoor(27, 41, MAP_JIDOOR_SHOP, 34, 20, "Jidoor's item shop door 198 (27,41) -> 201", { fight = FIGHT }),
  H.shopTalk(34, 15, "Jidoor's item shop", { fight = FIGHT }),
  H.call(function() H.assertEq(H.shopId(), 78, "the counter opened shop 78 ($0201)") end),
  H.buyItem(POTION, function() return math.max(0, potionTarget() - H.invCountOf(POTION)) end,
    "POTION to the band and the arc's spend"),
  H.buyItem(FENIX, function() return math.max(0, math.min(20, H.activeTopLevel()) - H.invCountOf(FENIX)) end,
    "FENIX DOWN to the level, capped at 20"),
  H.buyItem(REVIVIFY, function() return math.max(0, 3 - H.invCountOf(REVIVIFY)) end, "REVIVIFY to 3"),
  H.buyItem(TINCTURE, function() return math.max(0, math.ceil(H.activeTopLevel() / 4) - H.invCountOf(TINCTURE)) end,
    "TINCTURE to the level / 4"),
  H.buyItem(TENT, function() return math.max(0, TENT_TARGET - H.invCountOf(TENT)) end, "TENT for the cliffs' save point"),
  H.shopClose("Jidoor's item shop"),
  H.bagArrange({ POTION, FENIX, TONIC, REMEDY }, { tag = "bag: combat items on top (Jidoor)" }),
  H.call(function()
    say("shop", "Jidoor")
    H.assertEq(H.invCountOf(PARTISAN) >= 1, true, "a Partisan in the bag for MOG")
    H.assertEq(H.invCountOf(POTION) >= potionTarget(), true, "Potions at the target leaving Jidoor")
  end),
  H.crossDoor(34, 21, MAP_JIDOOR, 27, 43, "Jidoor's item shop -> the street", { fight = FIGHT }),
  toFalconBy(16, 61, "down", "Jidoor", JIDOOR_WORLD),
  -- Ifrit from SABIN, who waits aboard, to CYAN, so a third member learns
  -- fire for the arc's fire-weak bosses (route-wor-narshe.md 5.4); CYAN's
  -- Palidor goes back in the bag (the one-owner rule frees it first)
  H.equipEsper(function() return posOf(CYAN) end, IFRIT, { tag = "IFRIT -> CYAN" }),
  H.saveState("wor_narshe_jidoor.mss"),

  -- ---- 2. the cabin: CYAN, TERRA and CELES; a seat for MOG -----------------
  -- @@stage cabin
  regroup(REGROUP),
  H.call(function() say("regroup", "CYAN, TERRA and CELES") end),
  liftOff(),
  H.flyTo(NARSHE_LANDING[1], NARSHE_LANDING[2], { what = "the Falcon to Narshe" }),
  H.worldNavTo(NARSHE_DOOR[1], NARSHE_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_NARSHE and not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_NARSHE and settled() end, 2400, "Narshe: map 32", 1),
  H.call(function() say("route", "in Narshe") end),
  H.saveState("wor_narshe_town.mss"),

  -- ---- 3. through the elder's house to the moogle cave ---------------------
  -- @@stage town
  -- the gate's pickpocket (_cc36f2, (37-39,50)) is one dialog the walk taps
  -- through.  The elder's house (map 32 (49,12) -> 30 (55,34)): an Elixir
  -- (55,30); its back door (67,26) -> 32 (53,8), the pocket that holds the
  -- moogle cave's upper door (26,8) -> 38 (78,58)
  walkInto(49, 12, MAP_ELDER, "Narshe -> the elder's house (30)", exceptOf(NARSHE_DOORS, 49, 12)),
  chestAt(55, 30, 0x002, "Elixir (30 (55,30))", ELIXIR, ELDER_DOORS),
  walkInto(67, 26, MAP_NARSHE, "the elder's house -> Narshe's north ledge (32 (53,8))", exceptOf(ELDER_DOORS, 67, 26)),
  walkInto(26, 8, MAP_MOOGLE, "Narshe -> the moogle cave (38)", exceptOf(NARSHE_DOORS, 26, 8)),
  H.saveState("wor_narshe_cave.mss"),

  -- ---- 4. the moogle cave and MOG --------------------------------------------
  -- @@stage cave
  chestAt(65, 28, 0x00B, "Pod Bracelet (38 (65,28))", 0xC8, {}),
  chestAt(52, 33, 0x00C, "Elixir (38 (52,33))", ELIXIR, {}),
  walkInto(49, 21, MAP_MOG, "the moogle cave -> MOG's room (44)", { { 49, 11 }, { 37, 24 }, { 79, 58 } }),
  chestAt(98, 53, 0x00D, "Ribbon (44 (98,53))", RIBBON, { { 106, 55 }, { 121, 61 } }),
  -- MOG (44 NPC_1 (121,46), _cc396c): $029F clear, so his first meeting
  -- (_cc3a4c): the naming menu, and he joins into the empty seat
  walkTo(121, 47, "below MOG", { { 106, 55 }, { 121, 61 } }),
  talkTo(121, 46, "MOG (44 NPC_1)"),
  rideNaming(function() return sw(0x02FA) == 1 and inParty(MOG) and map() == MAP_MOG end, 20000, "MOG joins"),
  H.call(function()
    say("wor", "MOG joined")
    H.assertEq(sw(0x02FA), 1, "MOG is available ($02FA, _cc3a4c)")
    H.assertEq(partyOf(MOG), 1, "MOG joined the party, into the empty seat")
  end),
  chestAt(121, 45, 0x0CF, "Moogle Charm (44 (121,45))", MOOGLE_CHARM, { { 106, 55 }, { 121, 61 } }),
  -- dressed: the Partisan, the bag's best armor he can wear, and relics (the
  -- Ribbon goes on at once; the Moogle Charm, which stops random battles,
  -- stays in the bag: the route fights them)
  lazy(function() return H.equipKit(MOG, { { 0, PARTISAN } }, { tag = "MOG: the Partisan" }) end),
  dressFromBag(MOG, "MOG"),
  H.dressRelics({ { CYAN, "CYAN" }, { TERRA, "TERRA" }, { CELES, "CELES" }, { MOG, "MOG" } },
    { tag = "relics with MOG" }),
  H.call(function()
    H.assertEq(H.readByte(c(MOG, 0x1F)), PARTISAN, "MOG holds the Partisan")
    local ribbon = false
    for _, ch in ipairs({ CYAN, TERRA, CELES, MOG }) do
      if H.readByte(c(ch, 0x23)) == RIBBON or H.readByte(c(ch, 0x24)) == RIBBON then ribbon = true end
    end
    H.assertEq(ribbon, true, "the Ribbon is worn")
    H.assertEq(H.readByte(c(MOG, 0x23)) ~= MOOGLE_CHARM and H.readByte(c(MOG, 0x24)) ~= MOOGLE_CHARM, true,
      "the Moogle Charm stays in the bag")
    say("wor", "MOG dressed: " .. kitLine())
  end),
  H.saveState("wor_narshe_mog.mss"),

  -- ---- 5. back through the town and up the cliffs ----------------------------
  -- @@stage cliffs
  -- out the way in: 44 -> 38 (49,22), the upper door (79,58) -> 32 (27,8),
  -- the elder's back door (53,9) -> 30 (67,28), (55,35) -> 32 (49,14); the
  -- main street north to the long exit (35-38,1) -> 33 (26,50)
  walkInto(106, 55, MAP_MOOGLE, "MOG's room -> the moogle cave", { { 121, 61 } }),
  walkInto(79, 58, MAP_NARSHE, "the moogle cave -> Narshe's north ledge", { { 49, 11 }, { 37, 24 }, { 49, 21 } }),
  walkInto(53, 9, MAP_ELDER, "Narshe's north ledge -> the elder's house", exceptOf(NARSHE_DOORS, 53, 9)),
  walkInto(55, 35, MAP_NARSHE, "the elder's house -> Narshe", exceptOf(ELDER_DOORS, 55, 35)),
  walkInto(36, 1, MAP_CLIFF_LO, "Narshe -> the cliffs (33)", NARSHE_DOORS),
  -- map 33 to map 34 is a chain through the mines (route-wor-narshe.md 2.5):
  -- 33's (30-32,20) -> 36 (108,59); 36 (18,51) -> 33 (36,25); 33 (24,10) ->
  -- 36 (108,12); 36 (117,12) -> 33 (32,10); 33 (34-38,1) -> 34 (19,39)
  walkInto(31, 20, MAP_MINES, "the cliffs -> the mines (36 (108,59))", { { 37, 25 }, { 24, 10 }, { 31, 10 } }),
  walkInto(18, 51, MAP_CLIFF_LO, "the mines -> the cliffs (33 (36,25))", { { 107, 12 }, { 117, 12 }, { 108, 60 } }),
  walkInto(24, 10, MAP_MINES, "the cliffs -> the mines (36 (108,12))", { { 37, 25 }, { 31, 10 } }),
  walkInto(117, 12, MAP_CLIFF_LO, "the mines -> the cliffs (33 (32,10))", { { 107, 12 }, { 18, 51 }, { 108, 60 } }),
  walkInto(35, 1, MAP_CLIFF_SAVE, "the cliffs -> the cliffs' save point (34)", { { 24, 10 }, { 31, 10 }, { 37, 25 } }),
  -- the save point (25,5), the walk kept off the Ice Dragon's tile (22,20)
  -- and the tiles beside it (route-wor-narshe.md 9)
  walkTo(25, 6, "below the cliffs' save point",
    { { 22, 20 }, { 21, 20 }, { 23, 20 }, { 22, 21 }, { 22, 19 }, { 18, 1 }, { 19, 1 }, { 20, 1 }, { 21, 1 } }),
  H.fieldCare({ tag = "at the cliffs' save point", threshold = H.CARE_BEFORE_FIGHTS }),
  H.call(function()
    say("wor", "at the cliffs' save point")
    H.log("[wor] " .. kitLine())
  end),
  H.saveState("wor_narshe_savept.mss"),
  H.saveAtCheckpoint("wor-narshe-cliffs-v1"),
  H.saveState("wor_narshe.mss"),
  H.logStep(function()
    return string.format("wor_narshe generated: CYAN L%d, TERRA L%d, CELES L%d and MOG L%d on the cliffs' save point, "
      .. "map %d (%d,%d), saved in slot 3", level(CYAN), level(TERRA), level(CELES), level(MOG), map(), H.fieldX(),
      H.fieldY())
  end),
})
