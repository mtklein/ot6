-- gen_wor_owzer.lua -- the World of Ruin from Narshe to Owzer's basement:
-- Continue the `wor-narshe-v1` battery (UMARO, MOG, TERRA and CELES beside
-- the Falcon outside Narshe), the cabin (CYAN, TERRA and CELES; the fourth
-- seat waits for RELM, MOG and UMARO aboard), the Falcon to Jidoor, the item
-- counter, the auction (one item a visit, re-entered while Golem or ZoneSeek
-- has not come up, bounded), Owzer's house: the two paintings that fight,
-- the basement's lamp and its rotating doors, the painting warp, Still Life,
-- and the save point beside the goddess's door: the `wor-owzer-v1` battery,
-- the retry point for Chadarnook.
-- docs/design/route-wor-thamasa.md has the plan and what this measured.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CYAN, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, UMARO = 0, 2, 4, 5, 6, 7, 8, 9, 10, 13
local TONIC, POTION, FENIX, REMEDY, SOFT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4
local REVIVIFY, TENT, XPOTION, ETHER, ELIXIR, TINCTURE = 0xF1, 0xF7, 0xEA, 0xEC, 0xEE, 0xEB
local MOOGLE_SUIT, RELIC_RING = 0x9F, 0xDD
local MAP_JIDOOR, MAP_JIDOOR_SHOP, MAP_AUCTION = 198, 201, 200
local MAP_HALL, MAP_BASEMENT, MAP_GODDESS = 209, 207, 208
local JIDOOR_DOOR, JIDOOR_LANDING, JIDOOR_WORLD = { 35, 156 }, { 36, 156 }, { { 34, 156 }, { 35, 156 } }
-- magicite: give_genju's receipt order (Ramuh 0); Golem and ZoneSeek are
-- the auction's (route-wor-thamasa.md 6.1)
local GOLEM, ZONESEEK = 22, 18
-- the Potions the arc's legs spend before Thamasa's counter (Owzer's
-- randoms, the paintings, Chadarnook, the plains); the stack caps at 99
local POTION_SPEND = 60
local function potionTarget() return H.careStockPotions(H.activeTopLevel(), { spend = POTION_SPEND }) end
-- Tents: one at the basement's save point before Chadarnook, one for the
-- world-map save beside the tower (Thamasa sells more)
local TENT_TARGET = 3
local BOSS_SPECIES = {}
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
  { STRAGO, "STRAGO" }, { RELM, "RELM" }, { SETZER, "SETZER" }, { MOG, "MOG" }, { UMARO, "UMARO" } }
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
-- through a door in a wall: stand below it and hold Up until the map
-- changes (gen_wor_cyan's enterUp: Narshe's elder's door (49,12) is a wall
-- tile; (49,13) below it takes the press)
local function enterUp(x, y, dst, what, avoid)
  return H.seqStep({
    H.navTo(x, y + 1, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, avoid = avoid }),
    H.driveUntil(function() return map() == dst end, 600, { H.hold({ "up" }), H.waitFrames(4) }, what),
    H.release(),
    H.waitUntil(function() return map() == dst and settled() end, 1200, what .. ": control on map " .. dst, 1),
    H.call(function() H.log(string.format("[route] %s: on map %d at (%d,%d)", what, map(), H.fieldX(), H.fieldY())) end),
  })
end
-- a door: walked onto when the planner reaches its tile, else entered from
-- below it (a door in a wall)
local function door(x, y, dst, what, avoid)
  return lazy(function()
    local av = {}
    for _, d in ipairs(avoid or {}) do av[((d[2] & 0xFF) << 8) | (d[1] & 0xFF)] = true end
    if H.bfsPath(x, y, nil, av) then return walkInto(x, y, dst, what, avoid) end
    H.log(string.format("[route] %s: (%d,%d) is not walked onto from (%d,%d); entered from below", what, x, y,
      H.fieldX(), H.fieldY()))
    return enterUp(x, y, dst, what, avoid)
  end)
end
-- a door that leads to another place on the same map (the mines' inner
-- doors): walk onto it until the party's tile jumps (a step moves one)
local function warpVia(x, y, what, avoid)
  local lx, ly, jumped = nil, nil, false
  local function track()
    local fx, fy = H.fieldX(), H.fieldY()
    if lx ~= nil and math.abs(fx - lx) + math.abs(fy - ly) > 2 then jumped = true end
    lx, ly = fx, fy
    return jumped
  end
  return H.withReset(H.seqStep({
    H.call(function() lx, ly, jumped = nil, nil, false; track() end),
    H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT, avoid = avoid,
      arrive = function() return not H.battleLoadStarted() and track() end }),
    H.release(),
    H.waitUntil(function() track(); return jumped and settled() end, 1200, what .. ": through the door", 1),
    H.call(function() H.log(string.format("[route] %s: on map %d at (%d,%d)", what, map(), H.fieldX(), H.fieldY())) end),
  }), function() lx, ly, jumped = nil, nil, false end)
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
-- a walk by waypoints: the library's planner gives up past 4096 search
-- nodes (bfsPath's radius cap), so a far target is reached through near
-- ones (the waypoints read off route_data's step model, build/lab/mypath.py
-- in the route's evidence)
local function via(points, what, avoid)
  local steps = {}
  for _, p in ipairs(points) do
    steps[#steps + 1] = H.navTo(p[1], p[2], { maxFrames = 8000, playBattles = "tactical", fight = FIGHT, avoid = avoid })
  end
  steps[#steps + 1] = H.call(function()
    H.log(string.format("[route] %s: at (%d,%d)", what, H.fieldX(), H.fieldY()))
  end)
  return H.seqStep(steps)
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
-- the cabin's NPCs (map 12): NPC_n is object $10 + n - 1 (route_data map 12)
local CABIN_NPCS = { { "CYAN", 0x12, 0x038B }, { "EDGAR", 0x14, 0x038C }, { "SETZER", 0x19, 0x0391 },
  { "SABIN", 0x15, 0x038D }, { "CELES", 0x16, 0x038E }, { "TERRA", 0x10, 0x0388 }, { "MOG", 0x1A, 0x0392 },
  { "UMARO", 0x1D, 0x0395 }, { "STRAGO", 0x17, 0x038F }, { "RELM", 0x18, 0x0390 } }
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
      for _, ch in ipairs(aboard or {}) do
        H.assertEq(inParty(ch), false, string.format("char %d waits aboard", ch))
      end
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

-- walk onto a trigger tile: the walk ends on the tile with its event
-- running (gen_wor_cyan's stepOn); a random battle on the way is fought
local function stepOn(x, y, done, avoid)
  local drv = H.fightDriverFor("stepOn", { tactical = true, boost = true, items = true, healPercent = 55 }, FIGHT)
  local fought = false
  local function arrived()
    if H.battleLoadStarted() then return false end
    return done() or (H.fieldX() == x and H.fieldY() == y and not H.hasControl())
  end
  local nb = nil
  local function pick()
    if nb then return nb end
    local px, py = H.fieldX(), H.fieldY()
    if math.abs(px - x) + math.abs(py - y) == 1 then nb = { px, py }; return nb end
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      if H.bfsPath(x + d[1], y + d[2]) then nb = { x + d[1], y + d[2] }; return nb end
    end
    nb = { x, y + 1 }
    return nb
  end
  local n = 0
  return H.withReset(H.seqStep({
    H.cond(function() return not arrived() end, {
      H.call(function() nb = nil; pick() end),
      H.navTo(function() return pick()[1] end, function() return pick()[2] end,
        { maxFrames = 3000, playBattles = "tactical", fight = FIGHT, arrive = arrived, avoid = avoid }),
      H.driveUntil(arrived, 6000, {
        H.call(function()
          if H.battleLoadStarted() then fought = true; drv.frame(); return end
          if fought then drv.idle(); fought = false end
          n = n + 1
          local dx, dy = x - H.fieldX(), y - H.fieldY()
          local dir = dx > 0 and "right" or dx < 0 and "left" or dy > 0 and "down" or "up"
          H.setPad((n % 24) < 16 and { dir } or {})
        end),
      }, string.format("step onto the trigger (%d,%d)", x, y)),
      H.release(),
    }, {}),
  }), function() n = 0; nb = nil; fought = false end)
end

-- ---- the bosses' fights (reads only) ----------------------------------------
-- every boss action at ExecCmd ([monact]), and the boss's gauge each frame
-- ([brk]: OT6_SHIELD_CUR/MAX at $3E40/$3E41 + 2 x its monster slot, its HP
-- word $3BFC + 2 x slot), as gen_wor_storm's lines.  The boss's slot is
-- read from the formation ($57C0 + 2 x slot): the Ice Dragon stands in
-- slot 4, not 0 (build/lab/narshe/n2: '[death] ... by slot 4')
local BOSSES = BOSS_SPECIES
local ATTACKS = { [0xEE] = "Battle", [0xEF] = "Special" }
local function bossSlot()
  for sl = 0, 5 do
    local sp = H.readWord(0x57C0 + sl * 2)
    if BOSSES[sp] then return sl, sp end
  end
end
local fightOn = false
local function fightWatch()
  return H.call(function()
    if fightOn then return end
    fightOn = true
    local a = H.sym("ExecCmd@battle_code")
    local lastAct = "-"
    emu.addMemoryCallback(function()
      if not H.battleLoadStarted() then return end
      local sl, boss = bossSlot()
      if sl == nil then return end
      local x = emu.getState()["cpu.x"] & 0xffff
      if x < 8 and x % 2 == 0 then
        lastAct = string.format("entity %d cmd $%02X atk $%02X", x // 2, H.readByte(0xB5), H.readByte(0xB6))
      end
      if x == 8 + sl * 2 then
        local cmd, atk = H.readByte(0xB5), H.readByte(0xB6)
        if cmd ~= 0x2E and cmd ~= 0x2F then
          H.log(string.format("[monact] f%d slot %d $%03X cmd $%02X atk $%02X%s", H.frame, sl, boss, cmd,
            atk, ATTACKS[atk] and (" " .. ATTACKS[atk]) or ""))
        end
      end
    end, emu.callbackType.exec, a, a)
    local was, since = nil, 0
    emu.addEventCallback(function()
      if not H.battleLoadStarted() then was = nil; return end
      local sl, boss = bossSlot()
      if sl == nil then return end
      local cur, max = H.readByte(0x3E40 + sl * 2), H.readByte(0x3E41 + sl * 2)
      local broken = max > 0 and cur == 0
      if was == nil then was = broken; return end
      if broken and not was then
        since = H.frame
        H.log(string.format("[brk] f%d $%03X broken (0 of %d shields) at HP %d, the last party action %s", H.frame,
          boss, max, H.readWord(0x3BFC + sl * 2), lastAct))
      elseif was and not broken then
        H.log(string.format("[brk] f%d $%03X window over after %d frames: shields %d of %d, HP %d", H.frame, boss,
          H.frame - since, cur, max, H.readWord(0x3BFC + sl * 2)))
      end
      was = broken
    end, emu.eventType.endFrame)
  end)
end
-- the fights of one formation, logged and counted
local function fought(form, what)
  return H.call(function()
    local n = 0
    for _, o in ipairs(H.outcomes) do
      if (o.form & 0x1FF) == form then
        n = n + 1
        H.log(string.format("[boss] %s: battle $%03X %s after %d ticks, %d seated", what, o.form & 0x1FF, o.kind,
          o.tick or -1, o.seatedN or -1))
      end
    end
    H.assertEq(n, 1, what .. ": its formation was fought once")
    say("boss", what .. " won")
  end)
end

-- ---- a touch-to-fight NPC: walk beside it and press into it ----------------
-- (gen_wor_storm's touchDragon) the object's live tile is read every step:
-- the Ice Dragon's object stands away from its posted tile (build/lab/
-- narshe/t1: $11 at (20,16), posted (22,20)) and may walk
local function touchNpc(find, begun, what)
  local ph = 0
  return H.seqStep({
    H.cond(function() return not begun() end, {
      lazy(function()
        local o = find()
        local function side()
          local ox, oy = H.objX(o), H.objY(o)
          for _, d in ipairs({ { 0, -1 }, { -1, 0 }, { 1, 0 }, { 0, 1 } }) do
            if H.bfsPath(ox + d[1], oy + d[2]) then return { ox + d[1], oy + d[2] } end
          end
          return { ox, oy - 1 }
        end
        return H.seqStep({
          H.navTo(function() return side()[1] end, function() return side()[2] end,
            { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, arrive = function()
              return begun() or math.abs(H.objX(o) - H.fieldX()) + math.abs(H.objY(o) - H.fieldY()) == 1
            end }),
          H.withReset(H.driveUntil(begun, 1200, {
            H.call(function()
              ph = (ph + 1) % 8
              if H.battleLoadStarted() or not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
              local dx, dy = H.objX(o) - H.fieldX(), H.objY(o) - H.fieldY()
              local dir = dx > 0 and "right" or dx < 0 and "left" or dy > 0 and "down" or "up"
              H.setPad(ph < 4 and { [dir] = true, a = true } or { [dir] = true })
            end),
          }, what .. ": touch it"), function() ph = 0 end),
          H.release(),
        })
      end),
    }, {}),
  })
end

-- map 34's live objects are its two NPCs: the save point (NPC_1, posted on
-- (25,5)) and the Ice Dragon (NPC_2), which wanders (build/lab/narshe: $11
-- at (20,16), (17,18), (16,20) in three runs), so it is the one object
-- standing anywhere but the save point

local function owns(esper) return (H.readByte(0x1A69 + (esper >> 3)) >> (esper & 7)) & 1 == 1 end

-- ---- the auction (map 200) ---------------------------------------------------
-- The desk (NPC_12 at (19,24), _cb4e47): "join?" (dlg $0A41) row 0, then one
-- item a visit from the World of Ruin's chain of if_rand (_cb55b0: the Hero
-- Ring, then _cb570c's item, then Golem _cb58fa, then ZoneSeek _cb5a39, each
-- a coin flip: Golem comes up one visit in eight, ZoneSeek one in sixteen
-- until Golem is owned; route-wor-thamasa.md finding 8).  Golem's bids are
-- "Buy it for 12000 GP" ($0A57) then "20000" ($0A5E); ZoneSeek's "7000"
-- ($0A55) then "10000" ($0A5B, which other items' first bids share).  The
-- magicite's last bid is taken (row 0), every other prompt passed (row 1).
-- A visit ends when control is back for 60 frames after a prompt resolved;
-- the party leaves by the door and comes back for the next (the desk's $01F0
-- closes a day's sale).  A person who came for the magicite re-enters until
-- it comes up: bounded at 16 visits, each counted.
local AUCTION_VISITS = 16
local function auctionVisit(k)
  local quiet, stepRef = 0, nil
  local function want(dlg)
    if dlg == 0x0A41 then return 0 end
    local C = stepRef and stepRef.choice
    local prev = C and C.last and C.last.dlg
    if (dlg == 0x0A5E and prev == 0x0A57) or (dlg == 0x0A5B and prev == 0x0A55) then
      H.log(string.format("[auction] visit %d: the magicite's last bid (dlg $%04X after $%04X), gil %d", k, dlg,
        prev, H.gil()))
      return 0
    end
    return 1
  end
  local dlgStep = H.dialogChoice(want, {
    inBattle = false, what = "the auction", tag = "the auction", maxFrames = 9000,
    done = function(C)
      if C.resolved >= 1 and settled() and map() == MAP_AUCTION then quiet = quiet + 1 else quiet = 0 end
      return quiet >= 60
    end,
  })
  stepRef = dlgStep
  return H.seqStep({
    H.call(function() quiet = 0 end),
    talkTo(19, 24, "the auction's desk (200 NPC_12)"),
    dlgStep,
    H.call(function()
      local items = {}
      for _, h in ipairs(dlgStep.choice.history) do items[#items + 1] = string.format("$%04X:%d", h.dlg, h.row) end
      H.log(string.format("[auction] visit %d over: prompts %s; Golem %s, ZoneSeek %s; gil %d", k,
        table.concat(items, " "), tostring(owns(GOLEM)), tostring(owns(ZONESEEK)), H.gil()))
    end),
  })
end
local function auction()
  local steps = {
    H.crossDoor(26, 27, MAP_AUCTION, 18, 25, "Jidoor -> the auction (200)", { fight = FIGHT }),
  }
  for k = 1, AUCTION_VISITS do
    steps[#steps + 1] = H.cond(function() return not (owns(GOLEM) and owns(ZONESEEK)) end, {
      H.cond(function() return k > 1 end, {
        H.crossDoor(18, 26, MAP_JIDOOR, 26, 29, "the auction -> Jidoor", { fight = FIGHT }),
        H.crossDoor(26, 27, MAP_AUCTION, 18, 25, "Jidoor -> the auction again", { fight = FIGHT }),
      }, {}),
      auctionVisit(k),
    }, {})
  end
  steps[#steps + 1] = H.call(function()
    say("auction", string.format("Golem %s, ZoneSeek %s", tostring(owns(GOLEM)), tostring(owns(ZONESEEK))))
  end)
  steps[#steps + 1] = H.crossDoor(18, 26, MAP_JIDOOR, 26, 29, "the auction -> Jidoor", { fight = FIGHT })
  return H.seqStep(steps)
end

-- ---- an A-facing-up event: the paintings, the goddess's stone --------------
-- (route-wor-thamasa.md 9) the trigger answers A pressed facing up on its
-- tile (if_any $01B0=0 / $01B4=0); the walk stands on it, then turns up and
-- presses A until `begun`
local function examineUp(x, y, begun, what, avoid)
  return H.seqStep({
    H.cond(function() return not begun() end, {
      H.navTo(x, y, { maxFrames = 8000, playBattles = "tactical", fight = FIGHT, avoid = avoid }),
      H.faceAndHoldA("up", function() return begun() end, 1200, what),
      H.release(),
    }, {}),
  })
end

-- the rotating doors (207 (88,50), (90,50), (92,50)): the lamp (95,60)
-- starts a 160-frame turn (_cb4962); (88,50) leads on, to (90,61), while
-- $01FC is set (_cb4987 opens it and posts the blockers on the other two;
-- the two others drop the party into the cell at (113,54)).  The walk waits
-- below (88,51) and presses up when $01FC reads set.
local function rotatingDoor()
  local ph, phase = 0, nil
  local function through() return H.fieldY() >= 55 and map() == MAP_BASEMENT end
  return H.withReset(H.seqStep({
    H.navTo(88, 51, { maxFrames = 8000, playBattles = "tactical", fight = FIGHT,
      avoid = { { 90, 50 }, { 92, 50 }, { 90, 51 }, { 92, 51 } } }),
    H.driveUntil(function() return through() and settled() end, 3000, {
      H.call(function()
        ph = (ph + 1) % 8
        local p = string.format("%d%d%d", sw(0x01FC), sw(0x01FD), sw(0x01FE))
        if p ~= phase then
          phase = p
          H.log(string.format("[doors] f%d $01FC-$01FE %s, blockers $0494-$0496 %d%d%d at (%d,%d)", H.frame, p,
            sw(0x0494), sw(0x0495), sw(0x0496), H.fieldX(), H.fieldY()))
        end
        if through() then H.setPad({}); return end
        if sw(0x01FC) == 1 and H.hasControl() and H.fieldX() == 88 then
          H.setPad({ "up" })
        else
          H.setPad({})
        end
      end),
    }, "through the turning door (88,50) -> (90,61)"),
    H.release(),
    H.call(function()
      H.log(string.format("[route] through the turning door: map %d (%d,%d)", map(), H.fieldX(), H.fieldY()))
      H.assertEq(H.fieldX() == 113 and H.fieldY() == 54, false, "the turning door did not drop the party into the cell")
    end),
  }), function() ph, phase = 0, nil end)
end

-- a warp on the same map (an inner door, a painting): walk onto (x, y) until
-- the party stands within two tiles of where it leads, (dx, dy).  The test
-- is the landing, not a jump in the tile: an event fight on the way (the
-- old woman at (107,56)) moved the read and passed for a warp
-- (build/attempts/wt/v030-route/lab/owzer/h1: 'on map 207 at (107,56)', then 'no path')
local function warpTo(x, y, dx, dy, what, avoid)
  local function landed()
    return not H.battleLoadStarted() and map() == MAP_BASEMENT
      and math.abs(H.fieldX() - dx) + math.abs(H.fieldY() - dy) <= 2
  end
  return H.seqStep({
    H.cond(function() return not landed() end, {
      H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT, avoid = avoid, arrive = landed }),
    }, {}),
    H.release(),
    H.waitUntil(function() return landed() and settled() end, 1800, what .. ": the landing", 1),
    H.call(function() H.log(string.format("[route] %s: on map %d at (%d,%d)", what, map(), H.fieldX(), H.fieldY())) end),
  })
end
local function chestIfReachable(cx, cy, bit, what, item)
  return lazy(function()
    for _, o in ipairs({ { 0, 1 }, { -1, 0 }, { 1, 0 }, { 0, -1 } }) do
      if H.bfsPath(cx + o[1], cy + o[2]) then return chestAt(cx, cy, bit, what, item) end
    end
    H.log(string.format("[chest] %s (%d,%d): no side reachable from (%d,%d); left", what, cx, cy, H.fieldX(),
      H.fieldY()))
    return H.call(function() end)
  end)
end

local PARTY = { { CYAN, "CYAN" }, { TERRA, "TERRA" }, { CELES, "CELES" } }

H.run({ maxFrames = 500000 }, {
  H.bootCheckpoint("wor-narshe-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[wor] " .. kitLine())
  end),
  -- @@setup-end

  -- ---- 1. the cabin: CYAN, TERRA and CELES; a seat for RELM -----------------
  -- @@stage cabin
  regroup({ CYAN, TERRA, CELES }, { MOG, UMARO }),
  H.call(function() say("regroup", "CYAN, TERRA and CELES") end),
  liftOff(),
  H.flyTo(JIDOOR_LANDING[1], JIDOOR_LANDING[2], { what = "the Falcon to Jidoor" }),
  H.worldNavTo(JIDOOR_DOOR[1], JIDOOR_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_JIDOOR and not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_JIDOOR and settled() end, 2400, "Jidoor: map 198", 1),
  H.call(function()
    say("route", "in Jidoor")
    H.assertEq(sw(0x025F), 1, "Jidoor's World of Ruin gate $025F set (_cb43e4), which Owzer's events test")
  end),
  H.saveState("wor_owzer_jidoor.mss"),

  -- ---- 2. Jidoor: the item counter and the auction ----------------------------
  -- @@stage shop
  H.crossDoor(27, 41, MAP_JIDOOR_SHOP, 34, 20, "Jidoor's item shop door 198 (27,41) -> 201", { fight = FIGHT }),
  H.shopTalk(34, 15, "Jidoor's item shop", { fight = FIGHT }),
  H.call(function() H.assertEq(H.shopId(), 78, "the counter opened shop 78 ($0201)") end),
  H.buyItem(POTION, function() return math.max(0, potionTarget() - H.invCountOf(POTION)) end,
    "POTION to the band and the arc's spend"),
  H.buyItem(FENIX, function() return math.max(0, math.min(20, H.activeTopLevel()) - H.invCountOf(FENIX)) end,
    "FENIX DOWN to the level, capped at 20"),
  H.buyItem(TINCTURE, function() return math.max(0, math.ceil(H.activeTopLevel() / 4) - H.invCountOf(TINCTURE)) end,
    "TINCTURE to the level / 4"),
  H.buyItem(TENT, function() return math.max(0, TENT_TARGET - H.invCountOf(TENT)) end, "TENT to 3"),
  H.shopClose("Jidoor's item shop"),
  H.bagArrange({ POTION, FENIX, TONIC, REMEDY }, { tag = "bag: combat items on top (Jidoor)" }),
  H.call(function() say("shop", "Jidoor") end),
  H.crossDoor(34, 21, MAP_JIDOOR, 27, 43, "Jidoor's item shop -> the street", { fight = FIGHT }),
  auction(),
  H.saveState("wor_owzer_auction.mss"),

  -- ---- 3. Owzer's hall: the paintings --------------------------------------------
  -- @@stage hall
  H.crossDoor(16, 12, MAP_HALL, 118, 28, "Jidoor -> Owzer's house (209)", { fight = FIGHT }),
  H.call(function() say("route", "in Owzer's hall") end),
  -- the switch at the stair's foot (118,14), _cb4930: A facing up lights the
  -- hall ($0243); dark, the landing (114,11) answers "Stay...away..." and
  -- turns the party back (_cb4776; build/attempts/wt/v030-route/lab/owzer/a1: 'control lost at
  -- (114,11)', then 'planned 20 steps from (118,14)', until no-progress)
  examineUp(118, 14, function() return sw(0x0243) == 1 end, "the hall's switch (209 (118,14)): face up, A"),
  H.call(function() H.log(string.format("[route] the hall's switch: $0243 %d", sw(0x0243))) end),
  -- the still-life of flowers (111,18), _cb47f4: battle 147 (Nightshade x3)
  examineUp(111, 18, function() return sw(0x0156) == 1 or H.battleLoadStarted() end,
    "the still-life (209 (111,18)): face up, A"),
  H.advanceStory(function() return sw(0x0156) == 1 and not H.battleLoadStarted() and map() == MAP_HALL and settled() end,
    60000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("route", "the still-life fought") end),
  -- the lovely lady (99,30), _cb47ae: battle 146 (Dahling x2), then the
  -- door above her opens (_cb4728's tiles) onto the basement
  examineUp(99, 30, function() return sw(0x0252) == 1 or H.battleLoadStarted() end,
    "the lady's portrait (209 (99,30)): face up, A"),
  H.advanceStory(function() return sw(0x0252) == 1 and not H.battleLoadStarted() and map() == MAP_HALL and settled() end,
    60000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("route", "the lady's portrait fought") end),
  H.fieldCare({ tag = "after the paintings" }),
  door(99, 29, MAP_BASEMENT, "Owzer's hall -> the basement (207 (127,51))"),
  H.saveState("wor_owzer_basement.mss"),

  -- ---- 4. the basement: the lamp, the turning doors, the painting warp ---------
  -- @@stage basement
  warpTo(124, 52, 112, 47, "the basement (124,52) -> (112,47)"),
  warpTo(106, 46, 95, 61, "the basement (106,46) -> (95,61)"),
  -- the lamp (95,60), _cb4962: the doors start turning
  stepOn(95, 60, function() return sw(0x01B5) == 1 end),
  H.call(function() H.log(string.format("[doors] the lamp: $01B5 %d", sw(0x01B5))) end),
  rotatingDoor(),
  H.call(function() say("route", "past the turning door") end),
  -- the painting (85,50), _cb4bb5: the party is carried to (71,49), then down
  warpTo(85, 50, 71, 52, "the painting (85,50) -> (71,49), down to (71,52)"),
  H.call(function() H.assertEq(sw(0x024C), 1, "the painting warp ran ($024C)") end),
  H.saveState("wor_owzer_stilllife.mss"),

  -- ---- 5. Still Life and the save point -----------------------------------------
  -- @@stage stilllife
  examineUp(76, 52, function() return sw(0x0254) == 1 or H.battleLoadStarted() end,
    "Still Life (207 (76,52)): face up, A"),
  H.advanceStory(function()
    return sw(0x0254) == 1 and not H.battleLoadStarted() and map() == MAP_BASEMENT and settled()
  end, 60000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("route", "Still Life fought") end),
  -- (76,51), _cb4c94: through the opened painting to (85,46)
  warpTo(76, 51, 85, 46, "the opened painting (76,51) -> (85,46)"),
  chestIfReachable(92, 58, 0x0D5, "Moogle Suit (207 (92,58))", MOOGLE_SUIT),
  chestIfReachable(90, 47, 0x102, "Relic Ring (207 (90,47))", RELIC_RING),
  H.fieldCare({ tag = "at the basement's save point", threshold = H.CARE_BEFORE_FIGHTS }),
  H.call(function()
    say("wor", "at the basement's save point")
    H.log("[wor] " .. kitLine())
  end),
  H.saveState("wor_owzer_savept.mss"),
  H.saveAtCheckpoint("wor-owzer-v1"),
  H.saveState("wor_owzer.mss"),
  H.logStep(function()
    return string.format("wor_owzer generated: CYAN L%d, TERRA L%d and CELES L%d on the basement's save point, "
      .. "map %d (%d,%d), saved in slot 3; Golem %s, ZoneSeek %s", level(CYAN), level(TERRA), level(CELES), map(),
      H.fieldX(), H.fieldY(), tostring(owns(GOLEM)), tostring(owns(ZONESEEK)))
  end),
})
