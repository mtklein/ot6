-- gen_wor_tower.lua -- the Fanatics' Tower: Continue the `wor-tower-v1`
-- battery (TERRA, CELES, RELM and STRAGO beside the Falcon at the tower), the
-- stones for the climb, the climb (magic-only: battle switch $38, the
-- randoms fought for no XP), each floor's side room (the Safety Bit and the
-- switch to the Air Anchor's room, the Genji Shld, the Stunner and the Holy
-- Dragon, the Force Armor), the top: the Gem Box onto the main caster, and
-- MagiMaster (event battle 145, a game over when lost: the runner retries
-- from the battery), down and out to the Falcon, and the save beside it: the
-- `wor-thamasa-v1` battery.
-- docs/design/route-wor-thamasa.md has the plan and what this measured.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CYAN, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, UMARO = 0, 2, 4, 5, 6, 7, 8, 9, 10, 13
local TONIC, POTION, FENIX, REMEDY, SOFT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4
local REVIVIFY, TENT, XPOTION, ETHER, ELIXIR, TINCTURE = 0xF1, 0xF7, 0xEA, 0xEC, 0xEE, 0xEB
local SAFETY_BIT, GEM_BOX, GENJI_SHLD, STUNNER, FORCE_ARMOR, AIR_ANCHOR, PEARL_LANCE = 0xDC, 0xD8, 0x64, 0x2A,
  0x94, 0xA9, 0x21
local MAP_FOOT, MAP_F1, MAP_F2, MAP_F3, MAP_F4, MAP_TOP = 362, 363, 359, 360, 361, 364
local MAP_SAFETY, MAP_GEMBOX, MAP_GENJI, MAP_DRAGON, MAP_FORCE, MAP_ANCHOR = 365, 366, 367, 368, 369, 370
local TOWER_DOOR, TOWER_LANDING = { 160, 126 }, { 160, 127 }
-- magicite: give_genju's receipt order (Ramuh 0)
local SHIVA, MADUIN, PALIDOR, TRITOCH, ZONESEEK, SRAPHIM = 2, 6, 9, 10, 18, 21
-- the bosses (route_data pool event 139, 145)
local WHITE_DRGN, MAGIMASTER = 0x024, 0x166
local DRAGON_FORMATION, MAGIMASTER_FORMATION = 481, 354
local BOSS_SPECIES = { [WHITE_DRGN] = true, [MAGIMASTER] = true }
-- the tower is magic-only: the driver's magic-only line casts what the
-- target answers to (lib Driver:magicOnlyLine); the care block heals and
-- revives as everywhere
-- the randoms are fought in Wall Rings (Reflect: the monsters' tier spells
-- bounce), so the care block heals with items, not cures (a cure on a
-- reflecting member lands on the monsters); the bosses are fought without
-- them (the Holy Dragon absorbs the holy its Pearl would bounce back,
-- MagiMaster absorbs one element and nulls the rest), cures allowed
-- Shell goes up while an L.90 Magic stands (its Bolt 3, Merton, Meteor and
-- Flare), and on all four against MagiMaster (route-wor-thamasa.md 5.3)
local FIGHT = { cure = false, shellVs = { [0x164] = true } }
local BOSS_FIGHT = { shellVs = { [0x166] = true }, reraiseVs = { [0x166] = 0.3 } }
local WALL_RING = 0xBB
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
local function examineUp(x, y, begun, what, avoid)
  return H.seqStep({
    H.cond(function() return not begun() end, {
      H.navTo(x, y, { maxFrames = 8000, playBattles = "tactical", fight = FIGHT, avoid = avoid }),
      H.faceAndHoldA("up", function() return begun() end, 1200, what),
      H.release(),
    }, {}),
  })
end
local PARTY = { { TERRA, "TERRA" }, { CELES, "CELES" }, { RELM, "RELM" }, { STRAGO, "STRAGO" } }
-- the Wall Rings on and off: each member's second relic (slot 5) gives way
-- to a Wall Ring and comes back before a boss
local heldRelic = {}
local function wallRingsOn()
  local steps = {}
  for _, m in ipairs(PARTY) do
    steps[#steps + 1] = lazy(function()
      heldRelic[m[1]] = H.readByte(c(m[1], 0x24))
      if heldRelic[m[1]] == WALL_RING or H.readByte(c(m[1], 0x23)) == WALL_RING then return H.call(function() end) end
      return H.equipKit(m[1], { { 5, WALL_RING } }, { tag = m[2] .. ": a Wall Ring" })
    end)
  end
  steps[#steps + 1] = H.call(function()
    local n = 0
    for _, m in ipairs(PARTY) do
      if H.readByte(c(m[1], 0x24)) == WALL_RING or H.readByte(c(m[1], 0x23)) == WALL_RING then n = n + 1 end
    end
    H.assertEq(n, 4, "each of the four wears a Wall Ring")
    say("wor", "Wall Rings on: " .. kitLine())
  end)
  return H.seqStep(steps)
end
local function wallRingsOff(tag, keep)
  local steps = {}
  for _, m in ipairs(PARTY) do
    steps[#steps + 1] = lazy(function()
      if keep == m[1] then return H.call(function() end) end
      local old = heldRelic[m[1]]
      if H.readByte(c(m[1], 0x24)) ~= WALL_RING or old == nil or old == WALL_RING then return H.call(function() end) end
      return H.equipKit(m[1], { { 5, old } }, { tag = m[2] .. ": the Wall Ring off for " .. tag })
    end)
  end
  steps[#steps + 1] = H.call(function() say("wor", "Wall Rings off for " .. tag .. ": " .. kitLine()) end)
  return H.seqStep(steps)
end
-- the climb's spend (route-wor-thamasa.md 10.1: the randoms are fought, the
-- MP drain answered with supplies), logged floor by floor
local function spend(what)
  return H.call(function()
    local t = {}
    for _, m in ipairs(PARTY) do
      t[#t + 1] = string.format("%s MP %d/%d", m[2], H.charMp(m[1]), H.charMaxMp(m[1]))
    end
    say("climb", what .. ": " .. table.concat(t, ", "))
  end)
end
-- a side room off a floor's (10,10): in, its chest, back to the floor
local function sideRoom(floorMap, roomMap, bit, item, what, extra)
  local steps = {
    door(10, 10, roomMap, what .. ": the floor -> its side room (" .. roomMap .. ")"),
    chestAt(7, 6, bit, what, item),
  }
  for _, s in ipairs(extra or {}) do steps[#steps + 1] = s end
  steps[#steps + 1] = door(7, 13, floorMap, what .. ": back to the floor (" .. floorMap .. ")")
  return H.seqStep(steps)
end

H.run({ maxFrames = 1500000 }, {
  H.bootCheckpoint("wor-tower-v1"),
  watches(),
  fightWatch(),
  -- every fight inside is spells: the casters are topped up past half MP
  -- after each (Tinctures; the lib default band is a quarter); Float is kept
  -- on the four (the L.60 Magic's Quake); and the care after each fight
  -- casts cures when the bag runs short: a Potion gives 250 HP, no counter
  -- in reach sells better, and the four reached the top at 448 and 1 HP
  -- with 'casting off' (build/attempts/wt/v030-route/lab/tower/c12); and
  -- the four walk into each fight near whole (c15 met the fourth floor's
  -- L.90 Magic with TERRA at 2,478 of 3,591 and CELES at 2,642 of 3,595)
  H.call(function() H.careMpBand = 0.6; H.careFloat = true; H.careMagic = true; H.careThreshold = 0.95 end),
  H.call(function()
    say("wor", "boot")
    H.log("[wor] " .. kitLine())
  end),
  -- @@setup-end

  -- ---- 1. the stones for the climb, and in -------------------------------------
  -- @@stage stones
  -- every seat casts something that hurts: inside the Fanatics' Tower a
  -- seat with no attack spell has no attack turn (Fight is Magic there),
  -- and the plan's RELM on ZoneSeek and STRAGO on Sraphim passed every turn
  -- of the first floor's second fight while the L.30 and L.40 Magic killed
  -- the party (build/attempts/wt/v030-route/lab/tower/c1: 'actor=2 char=8 plan=switch', 'battle
  -- $0AD LOST').  TERRA Maduin (fire, ice, bolt over her own Fire, Drain,
  -- Break, Pearl, Life), CELES Tritoch (ice, bolt, poison), RELM Shiva (ice,
  -- Osmose for MP, Shell for MagiMaster's Ultima; Ifrit is CYAN's, aboard,
  -- and the party menu cannot free a stone a waiting member wears), STRAGO
  -- Palidor (Float, which the care keeps on the four from the menu: the
  -- L.60 Magic's Quake took 3,400 of 3,600 from each of them, twice, and
  -- wiped them on the second floor; build/attempts/wt/v030-route/lab/tower/
  -- c8 'by slot 2 cmd $02 atk $15').  The Wall Rings carry the attack
  -- through the reflecting L.20 and L.70 Magic: a spell cast on a member in
  -- Reflect rebounds onto the monsters (Driver:magicOnlyLine)
  H.equipEsper(function() return posOf(TERRA) end, MADUIN, { tag = "MADUIN -> TERRA" }),
  H.cond(function() return H.readByte(c(CELES, 0x1E)) ~= TRITOCH end, {
    H.equipEsper(function() return posOf(CELES) end, TRITOCH, { tag = "TRITOCH -> CELES" }),
  }, {}),
  H.equipEsper(function() return posOf(RELM) end, SHIVA, { tag = "SHIVA -> RELM" }),
  H.equipEsper(function() return posOf(STRAGO) end, PALIDOR, { tag = "PALIDOR -> STRAGO" }),
  H.call(function() say("wor", "stones: " .. kitLine()) end),
  wallRingsOn(),
  H.fieldCare({ tag = "Float on the four" }),
  H.worldNavTo(TOWER_DOOR[1], TOWER_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_FOOT and not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_FOOT and settled() end, 2400, "the tower's foot: map 362", 1),
  door(8, 1, MAP_F1, "the tower's foot -> the first floor (363)"),
  spend("on the first floor"),
  H.saveState("wor_tower_f1.mss"),

  -- ---- 2. the first floor: the Safety Bit and the Air Anchor -------------------------
  -- @@stage f1
  -- 365 (off 363 (10,10)): the Safety Bit (7,6); (8,6), A facing up
  -- (_cc55a6) sets $02DC, which opens 363 (10,12)-(10,14) to room 370
  sideRoom(MAP_F1, MAP_SAFETY, 0x0B4, SAFETY_BIT, "Safety Bit (365 (7,6))", {
    examineUp(8, 6, function() return sw(0x02DC) == 1 end, "365's switch (8,6): face up, A"),
  }),
  door(10, 13, MAP_ANCHOR, "the first floor -> the Air Anchor's room (370)"),
  chestAt(7, 6, 0x0B9, "Air Anchor (370 (7,6))", AIR_ANCHOR),
  door(7, 13, MAP_F1, "the Air Anchor's room -> the first floor (363 (10,14))"),
  door(8, 1, MAP_F2, "the first floor -> the second (359)"),
  spend("on the second floor"),
  H.saveState("wor_tower_f2.mss"),

  -- ---- 3. the second floor: the Genji Shld; the third: the Stunner and the Holy Dragon
  -- @@stage f2
  sideRoom(MAP_F2, MAP_GENJI, 0x0B5, GENJI_SHLD, "Genji Shld (367 (7,6))"),
  door(8, 1, MAP_F3, "the second floor -> the third (360)"),
  spend("on the third floor"),
  door(10, 10, MAP_DRAGON, "the third floor -> the Holy Dragon's room (368)"),
  chestAt(7, 6, 0x0B6, "Stunner (368 (7,6))", STUNNER, { { 5, 9 }, { 4, 9 }, { 6, 9 }, { 5, 8 }, { 5, 10 } }),
  wallRingsOff("the Holy Dragon"),
  H.fieldCare({ threshold = 1.0, mpBand = 0.9, tag = "before the Holy Dragon" }),
  H.call(function() say("boss", "ready for the Holy Dragon: " .. kitLine()) end),
  H.saveState("wor_tower_dragon.mss"),
  -- @@stage dragon
  -- 368 NPC_1 (5,9), touch-to-fight (_cc558b): event battle 139, then the
  -- Pearl Lance (route-wor-thamasa.md 5.4)
  H.cond(function() return sw(0x0694) == 1 end, {
    touchNpc(function() return npcAt(5, 9, "the Holy Dragon (368 NPC_1)") end, function()
      return (H.battleLoadStarted() and H.formationHas({ [WHITE_DRGN] = true })) or sw(0x0694) == 0
    end, "the Holy Dragon (368 NPC_1)"),
    H.advanceStory(function()
      return sw(0x0694) == 0 and not H.battleLoadStarted() and map() == MAP_DRAGON and settled()
    end, 150000, { playBattles = "tactical", fight = BOSS_FIGHT }),
    fought(DRAGON_FORMATION, "the Holy Dragon"),
  }, {}),
  H.call(function() H.assertEq(H.invCountOf(PEARL_LANCE) >= 1, true, "the Pearl Lance in the bag (_cc558b)") end),
  H.fieldCare({ tag = "after the Holy Dragon" }),
  wallRingsOn(),
  door(7, 13, MAP_F3, "the Holy Dragon's room -> the third floor (360)"),
  door(8, 1, MAP_F4, "the third floor -> the fourth (361)"),
  -- above the third floor no L.20 or L.70 Magic stands (groups 155 and 156:
  -- L.50, L.60, L.80, L.90), and the L.90's Merton and Meteor are not
  -- reflectable: in Wall Rings the four could heal only with Potions, 250
  -- HP against a 2,300-HP Merton, and two climbs fell at the top
  -- (build/attempts/wt/v030-route/lab/tower/c10, c11: 'atk $17').  So the
  -- rings come off here and the care casts again, but for STRAGO's: the
  -- L.90 reflects too, and a rebound off him is the party's way through it
  wallRingsOff("the fourth floor and the top", STRAGO),
  H.call(function() FIGHT.cure = nil end),
  spend("on the fourth floor"),
  H.saveState("wor_tower_f4.mss"),

  -- ---- 4. the fourth floor: the Force Armor; the top: the Gem Box --------------------
  -- @@stage f4
  H.call(function() FIGHT.cure = nil end),   -- (as set on arriving: a stage boots here too)
  sideRoom(MAP_F4, MAP_FORCE, 0x0B7, FORCE_ARMOR, "Force Armor (369 (7,6))"),
  door(8, 1, MAP_TOP, "the fourth floor -> the top (364)"),
  spend("at the top"),
  -- 364 (7,6) -> 366: the Gem Box (7,7); its tile (7,8) (_cc5440) sets
  -- $02DA and shows the cultists: MagiMaster waits on 364 (8,8)
  door(7, 6, MAP_GEMBOX, "the top -> the Gem Box's room (366)"),
  chestAt(7, 7, 0x0B8, "Gem Box (366 (7,7))", GEM_BOX),
  -- the relics, then the Gem Box onto TERRA (X-Magic: two casts a turn,
  -- route-wor-thamasa.md finding 6) and the Force Armor (halves fire, ice
  -- and bolt) onto CELES
  wallRingsOff("MagiMaster"),
  lazy(function() return H.equipKit(TERRA, { { 4, GEM_BOX } }, { tag = "TERRA: the Gem Box" }) end),
  lazy(function() return H.equipKit(CELES, { { 3, FORCE_ARMOR } }, { tag = "CELES: the Force Armor" }) end),
  H.call(function() say("wor", "dressed for MagiMaster: " .. kitLine()) end),
  door(7, 13, MAP_TOP, "the Gem Box's room -> the top (364 (7,7))"),
  H.fieldCare({ threshold = 1.0, mpBand = 0.9, tag = "before MagiMaster" }),
  H.saveState("wor_tower_magimaster.mss"),

  -- ---- 5. MagiMaster ---------------------------------------------------------------
  -- @@stage magimaster
  H.call(function() H.assertEq(sw(0x02DA), 1, "the Gem Box's tile armed MagiMaster ($02DA, _cc5440)") end),
  stepOn(8, 8, function() return H.battleLoadStarted() or sw(0x02DB) == 1 end),
  H.advanceStory(function()
    return sw(0x02DB) == 1 and not H.battleLoadStarted() and map() == MAP_TOP and settled()
  end, 200000, { playBattles = "tactical", fight = BOSS_FIGHT }),
  fought(MAGIMASTER_FORMATION, "MagiMaster"),
  H.fieldCare({ tag = "after MagiMaster" }),
  H.saveState("wor_tower_won.mss"),

  -- ---- 6. down and out, and the save -------------------------------------------------
  -- @@stage down
  door(7, 14, MAP_F4, "the top -> the fourth floor (361 (7,2))"),
  door(7, 29, MAP_F3, "the fourth floor -> the third (360 (7,2))"),
  door(7, 29, MAP_F2, "the third floor -> the second (359 (7,2))"),
  door(7, 29, MAP_F1, "the second floor -> the first (363 (7,2))"),
  door(7, 29, MAP_FOOT, "the first floor -> the tower's foot (362 (7,2))"),
  toFalconBy(8, 14, "down", "the tower's foot", { { TOWER_DOOR[1], TOWER_DOOR[2] } }),
  H.fieldCare({ threshold = 1.0, tag = "beside the Falcon" }),
  H.call(function()
    say("wor", "beside the Falcon after the tower")
    H.log("[wor] " .. kitLine())
  end),
  H.saveState("wor_tower_savept.mss"),
  H.saveAtCheckpoint("wor-thamasa-v1"),
  H.saveState("wor_tower.mss"),
  H.logStep(function()
    return string.format("wor_tower generated: TERRA L%d, CELES L%d, RELM L%d and STRAGO L%d beside the Falcon at "
      .. "the tower, world (%d,%d), saved in slot 3", level(TERRA), level(CELES), level(RELM), level(STRAGO),
      H.worldX(), H.worldY())
  end),
})
