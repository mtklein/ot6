-- gen_wor_relm.lua -- Chadarnook to the Fanatics' Tower's door: Continue the
-- `wor-owzer-v1` battery (CYAN, TERRA and CELES on the basement's save
-- point), the goddess's room: Owzer, Chadarnook (event battle 86, a game over
-- when lost: the runner retries from the save point), Starlet and RELM into
-- the empty seat; out of Jidoor to the Falcon, the tower's foot, where STRAGO
-- joins (he waits aboard: the party is full), the cabin (TERRA, CELES, RELM
-- and STRAGO; CYAN, MOG and UMARO aboard), the plain north-west of Jidoor (world
-- group 48, no Mantodea) to the level the tower asks, Thamasa's item counter,
-- and the save beside the Falcon at the tower: the `wor-tower-v1` battery.
-- docs/design/route-wor-thamasa.md has the plan and what this measured.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CYAN, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, UMARO = 0, 2, 4, 5, 6, 7, 8, 9, 10, 13
local TONIC, POTION, FENIX, REMEDY, SOFT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4
local REVIVIFY, TENT, XPOTION, ETHER, ELIXIR, TINCTURE = 0xF1, 0xF7, 0xEA, 0xEC, 0xEE, 0xEB
local MAP_JIDOOR, MAP_JIDOOR_SHOP, MAP_BASEMENT, MAP_GODDESS = 198, 201, 207, 208
local MAP_TOWER_FOOT, MAP_THAMASA, MAP_THAMASA_ITEMS, MAP_THAMASA_RELICS = 362, 344, 347, 350
local WALL_RING = 0xBB
local TOWER_DOOR, TOWER_LANDING = { 160, 126 }, { 160, 127 }
local THAMASA_DOOR, THAMASA_LANDING = { 251, 230 }, { 250, 229 }
local THAMASA_AVOID = { { 22, 39 }, { 23, 39 } }
-- the plain north-west of Jidoor: world row 135, x 16-22, is group 48 alone
-- (Crawler x3; Geckorex x2 and Reach Frog), no Mantodea, walkable end to end
-- and (17,135) takes a landing (build/attempts/wt/v030-route/grind/:
-- grindspot.txt, wg_lap.txt).  The plan's spot south of the gate (rows
-- 160-162) cannot be reached on foot from any landing ('worldNavTo: no path
-- (34,158)->(31,161)', build/attempts/wt/v030-route/lab/relm/s1; route_data world-path agrees)
local GRIND_LANDING, GRIND_LAP = { 17, 135 }, { { 16, 135 }, { 22, 135 } }
-- the level the tower asks of its four (route-wor-thamasa.md 5): the lowest
-- of TERRA, CELES, RELM and STRAGO, bounded by GRIND_BATTLES.  At L46 (TERRA and
-- CELES L49) the four lost the fourth floor's L.90 and L.80 Magic in all three
-- attempts of a run, the L.90's Merton taking 2,300 from each, after the Holy
-- Dragon fell in all three (build/attempts/wt/v030-route/lab/tower/cap2); at
-- L50 (TERRA L52, CELES L53; 95 fights, 533,402 frames) they lost the same
-- floor's first fight (lab/tower/c18), so the levels are not the answer
-- there and the grind stays at L46 (route-wor-thamasa.md 11.4)
local GRIND_LEVEL, GRIND_BATTLES = 46, 90
-- magicite: give_genju's receipt order (Ramuh 0)
local STARLET, GOLEM, ZONESEEK = 25, 22, 18
-- Chadarnook (route_data pool event 86: formation 456; the goddess $11E,
-- the demon $148)
local GODDESS_SP, DEMON_SP, CHADARNOOK_FORMATION = 0x11E, 0x148, 456
local BOSS_SPECIES = { [GODDESS_SP] = true, [DEMON_SP] = true }
-- the fight driver for the demon (route-wor-thamasa.md 5.2): the demon only
-- (focus; the goddess absorbs holy and water and counters every hit with
-- Phantasm), fire (TERRA's natural Fire, CYAN's Ifrit) toward Fire 2 and 3,
-- CELES on Runic for its Bolt 2 and 3, CYAN's SwdTech; TERRA's Trance at
-- three points.  Pearl stays out: the goddess absorbs holy (the cast guard
-- refuses it)
local FIRE = 0x00
local BOSS_FIGHT = { runic = true, bushido = true, magic = { [0] = { spell = FIRE } }, nuke = { FIRE },
  trance = true, focus = { { species = DEMON_SP } } }
-- STRAGO's kit on the plains (#388): Aqua Rake as the nuke (water: the Reach
-- Frog's... and the Spek Tors'), Pearl Wind as the party heal, Dischord on
-- the Mantodea (it halves the killer's level), Study at three points on a
-- body that can teach him a lore
local AQUA_RAKE = 3
local STRAGO_KIT = { study = true, pearlWind = true, dischord = { [0x0D2] = true } }
local FIGHT = { nukeLore = { AQUA_RAKE }, strago = STRAGO_KIT }
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
local function lores() return H.readByte(0x1D29) | (H.readByte(0x1D2A) << 8) | (H.readByte(0x1D2B) << 16) end

-- an A-facing-up event (route-wor-thamasa.md 9): stand on the tile, turn up,
-- press A until `begun`
local function examineUp(x, y, begun, what, avoid)
  return H.seqStep({
    H.cond(function() return not begun() end, {
      H.navTo(x, y, { maxFrames = 8000, playBattles = "tactical", fight = FIGHT, avoid = avoid }),
      H.faceAndHoldA("up", function() return begun() end, 1200, what),
      H.release(),
    }, {}),
  })
end

-- ---- the grind on the plain north-west of Jidoor ---------------------------------
local FOUR = { TERRA, CELES, RELM, STRAGO }
local function lowest()
  local m = 99
  for _, ch in ipairs(FOUR) do m = math.min(m, level(ch)) end
  return m
end
local function grind()
  local wp, n0, seen = 1, nil, nil
  return H.withReset(H.seqStep({
    H.call(function()
      n0, seen, wp = #H.outcomes, #H.outcomes, 1
      say("grind", string.format("to L%d for the lowest (now L%d); lores $%06X", GRIND_LEVEL, lowest(), lores()))
    end),
    H.driveUntil(function()
      while seen < #H.outcomes do
        seen = seen + 1
        local o = H.outcomes[seen]
        H.log(string.format("[grind] battle %d $%03X %s after %d ticks: %s; lores $%06X", seen - n0, o.form & 0x1FF,
          o.kind, o.tick or -1, whereLine(), lores()))
      end
      if #H.outcomes - n0 >= GRIND_BATTLES then
        error(string.format("the grind: %d battles and the lowest member is L%d, short of L%d", #H.outcomes - n0,
          lowest(), GRIND_LEVEL))
      end
      return not H.battleLoadStarted() and H.worldSettled() and lowest() >= GRIND_LEVEL
    end, 1500000, {
      H.worldNavTo(function() return GRIND_LAP[wp][1] end, function() return GRIND_LAP[wp][2] end,
        { maxFrames = 20000, playBattles = "tactical", fight = FIGHT }),
      H.call(function() wp = wp % 2 + 1 end),
      H.cond(function() return not H.battleLoadStarted() end, { H.fieldCare({ tag = "care on the grind" }) }, {}),
    }, "the grind north-west of Jidoor"),
    H.call(function() say("grind", string.format("done after %d battles; lores $%06X", #H.outcomes - n0, lores())) end),
  }), function() n0, seen, wp = nil, nil, 1 end)
end

local PARTY = { { TERRA, "TERRA" }, { CELES, "CELES" }, { RELM, "RELM" }, { STRAGO, "STRAGO" } }

H.run({ maxFrames = 1800000 }, {
  H.bootCheckpoint("wor-owzer-v1"),
  watches(),
  fightWatch(),
  H.call(function()
    say("wor", "boot")
    H.log("[wor] " .. kitLine())
  end),
  -- @@setup-end

  -- ---- 1. Chadarnook ------------------------------------------------------------
  -- @@stage goddess
  H.fieldCare({ threshold = 1.0, tag = "before Chadarnook" }),
  H.dressRelics({ { CYAN, "CYAN" }, { TERRA, "TERRA" }, { CELES, "CELES" } }, { tag = "relics for Chadarnook" }),
  door(88, 35, MAP_GODDESS, "the basement -> the goddess's room (208 (75,36))"),
  -- Owzer (208 NPC_2 at (75,14), _cb4cfa): his lines, then event battle 86
  -- (a game over when lost), then $0253
  walkTo(75, 15, "below Owzer"),
  talkTo(75, 14, "Owzer (208 NPC_2)"),
  H.advanceStory(function()
    return sw(0x0253) == 1 and not H.battleLoadStarted() and map() == MAP_GODDESS and settled()
  end, 150000, { playBattles = "tactical", fight = BOSS_FIGHT }),
  fought(CHADARNOOK_FORMATION, "Chadarnook"),
  H.saveState("wor_relm_chadarnook.mss"),

  -- ---- 2. Starlet and RELM ------------------------------------------------------
  -- @@stage relm
  -- the painting (80,14), A facing up (_cb4dc6): Starlet, then RELM into the
  -- empty seat; the map reloads to Jidoor (198 (16,14))
  examineUp(80, 14, function() return sw(0x0240) == 1 end, "the goddess's painting (208 (80,14)): face up, A"),
  H.advanceStory(function() return sw(0x02F8) == 1 and map() == MAP_JIDOOR and settled() end, 20000,
    { playBattles = "tactical", fight = FIGHT }),
  H.call(function()
    say("wor", "RELM joined")
    H.assertEq(owns(STARLET), true, "Starlet owned (give_genju, _cb4dc6)")
    H.assertEq(partyOf(RELM), 1, "RELM joined the party, into the empty seat")
  end),
  dressFromBag(RELM, "RELM"),
  H.dressRelics({ { CYAN, "CYAN" }, { TERRA, "TERRA" }, { CELES, "CELES" }, { RELM, "RELM" } },
    { tag = "relics with RELM" }),
  H.call(function() say("wor", "RELM dressed: " .. kitLine()) end),
  -- the item counter again before the grind (RELM's join lands the party in
  -- Jidoor): the plain's fights are cared for with Potions (Jidoor sells no
  -- Tonics) and the poison the plain deals with Remedies; the first grind
  -- left Jidoor with 95 Potions and no Remedy and came off the plain with 2
  -- and STRAGO poisoned (build/attempts/wt/v030-route/lab/relm/r1: 'potion=2 ... remedy=0', 'c7
  -- ... status1=04')
  H.crossDoor(27, 41, MAP_JIDOOR_SHOP, 34, 20, "Jidoor's item shop door 198 (27,41) -> 201", { fight = FIGHT }),
  H.shopTalk(34, 15, "Jidoor's item shop", { fight = FIGHT }),
  H.call(function() H.assertEq(H.shopId(), 78, "the counter opened shop 78 ($0201)") end),
  H.buyItem(POTION, function() return math.max(0, 99 - H.invCountOf(POTION)) end, "POTION to 99 for the grind"),
  -- the grind to L46 is some 55 fights: 99 Potions and 10 Remedies were
  -- gone by its 33rd (build/attempts/wt/v030-route/lab/var/relm_k3: 'potion=2
  -- ... remedy=0'), so Remedies to 20 and Tents, which the care pitches on
  -- the world map when the heals would cost more
  H.buyItem(REMEDY, function() return math.max(0, 20 - H.invCountOf(REMEDY)) end, "REMEDY to 20"),
  H.buyItem(TENT, function() return math.max(0, 15 - H.invCountOf(TENT)) end, "TENT to 15 for the grind"),
  H.buyItem(FENIX, function() return math.max(0, math.min(20, H.activeTopLevel()) - H.invCountOf(FENIX)) end,
    "FENIX DOWN to the level, capped at 20"),
  H.shopClose("Jidoor's item shop"),
  H.bagArrange({ POTION, FENIX, TONIC, REMEDY }, { tag = "bag: combat items on top (Jidoor, with RELM)" }),
  H.crossDoor(34, 21, MAP_JIDOOR, 27, 43, "Jidoor's item shop -> the street", { fight = FIGHT }),
  toFalconBy(16, 61, "down", "Jidoor", { { 34, 156 }, { 35, 156 } }),
  H.saveState("wor_relm_jidoor.mss"),

  -- ---- 3. the tower's foot: STRAGO ----------------------------------------------
  -- @@stage strago
  board(),
  H.flyTo(TOWER_LANDING[1], TOWER_LANDING[2], { what = "the Falcon to the tower" }),
  H.worldNavTo(TOWER_DOOR[1], TOWER_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_TOWER_FOOT and not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_TOWER_FOOT and settled() end, 2400, "the tower's foot: map 362", 1),
  -- any of (8,12), (7,13), (9,13), (8,14) with RELM seated (_cc5275):
  -- STRAGO's scene; the party is full, so he waits aboard; the map reloads
  -- at (8,13)
  stepOn(8, 12, function() return sw(0x02F7) == 1 or not H.hasControl() end),
  H.advanceStory(function() return sw(0x02F7) == 1 and map() == MAP_TOWER_FOOT and settled() end, 30000,
    { playBattles = "tactical", fight = FIGHT }),
  H.call(function()
    say("wor", "STRAGO joined")
    H.assertEq(sw(0x02F7), 1, "STRAGO available ($02F7, _cc5275)")
  end),
  toFalconBy(8, 14, "down", "the tower's foot", { { TOWER_DOOR[1], TOWER_DOOR[2] } }),
  H.saveState("wor_relm_strago.mss"),

  -- ---- 4. the cabin and the grind ---------------------------------------------------
  -- @@stage grind
  regroup({ TERRA, CELES, RELM, STRAGO }, { CYAN, MOG, UMARO }),
  H.call(function() say("regroup", "TERRA, CELES, RELM and STRAGO") end),
  dressFromBag(STRAGO, "STRAGO"),
  H.dressRelics(PARTY, { tag = "relics for the four" }),
  liftOff(),
  H.flyTo(GRIND_LANDING[1], GRIND_LANDING[2], { what = "the Falcon to the plain north-west of Jidoor" }),
  grind(),
  H.saveState("wor_relm_grind.mss"),

  -- ---- 5. Thamasa's item counter, and the save beside the tower ---------------------
  -- @@stage thamasa
  board(),
  H.flyTo(THAMASA_LANDING[1], THAMASA_LANDING[2], { what = "the Falcon to Thamasa" }),
  H.worldNavTo(THAMASA_DOOR[1], THAMASA_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_THAMASA and not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_THAMASA and settled() end, 2400, "Thamasa: map 344", 1),
  -- care before the counter, so the Potions it spends are bought back
  -- there.  Healed after the counter instead, beside the tower, the four
  -- (3221-4023 max HP, 250 a Potion, no Tents or Tonics left) spent 34 of
  -- the 99 and reached the tower at "potion=65", under the band ("POTION
  -- SHORT wor_relm potion= 65 < band 74 (L49)": build/attempts/wt/
  -- v031-robust/final/wor_relm_rerun.log, build/attempts/wt/
  -- v031-robust-2/base/audit_supplies_v.txt)
  H.fieldCare({ threshold = 1.0, tag = "at Thamasa, before the counter" }),
  -- (22,39) and (23,39) start STRAGO and RELM's scene at their house
  -- (_cb75bf, with both seated; the Hidon side quest, not this arc:
  -- build/attempts/wt/v030-route/lab/relm/r1 'control lost at (23,39)'), so the walks keep off them
  H.crossDoor(26, 37, MAP_THAMASA_ITEMS, 36, 44, "Thamasa's item shop door 344 (26,37) -> 347",
    { fight = FIGHT, avoid = THAMASA_AVOID }),
  H.shopTalk(36, 39, "Thamasa's item shop", { fight = FIGHT }),
  H.call(function() H.assertEq(H.shopId(), 74, "the counter opened shop 74 ($0201)") end),
  -- the tower is MP: every random is fought with spells and pays nothing
  -- back (route-wor-thamasa.md 7).  A Tincture gives 50 MP; the climb from
  -- the second floor to the top spent 32 of them and reached MagiMaster's
  -- floor with TERRA at 6 MP and RELM at 2, and the four fell there
  -- (build/attempts/wt/v030-route/lab/tower/c10).  So the stack, 99
  H.buyItem(TINCTURE, function() return math.max(0, 99 - H.invCountOf(TINCTURE)) end, "TINCTURE to 99 for the tower"),
  H.buyItem(POTION, function() return math.max(0, H.careStockPotions(H.activeTopLevel(), { spend = 40 })
    - H.invCountOf(POTION)) end, "POTION to the band"),
  H.buyItem(FENIX, function() return math.max(0, math.min(20, H.activeTopLevel()) - H.invCountOf(FENIX)) end,
    "FENIX DOWN to the level, capped at 20"),
  -- the plain's poison outlasts the grind's Remedies (the L50 grind reached
  -- Thamasa with CELES and STRAGO poisoned and 'remedy=0', and the care
  -- beside the tower spent 34 Potions on the poison: build/attempts/wt/
  -- v030-route/lab/relm/cap3), so Remedies to 10 here, for the care and
  -- the tower (no counter inside)
  H.buyItem(REMEDY, function() return math.max(0, 10 - H.invCountOf(REMEDY)) end, "REMEDY to 10"),
  H.shopClose("Thamasa's item shop"),
  H.bagArrange({ POTION, FENIX, TONIC, REMEDY }, { tag = "bag: combat items on top (Thamasa)" }),
  H.call(function() say("shop", "Thamasa") end),
  H.crossDoor(36, 45, MAP_THAMASA, 26, 39, "Thamasa's item shop -> the street", { fight = FIGHT }),
  -- the relic counter (344 (40,30) -> 350, shop 75): a Wall Ring for each of
  -- the four.  Inside the tower the monsters only cast, mostly reflectable
  -- tier spells, and the four at L43-47 lost the first floor's L.30 Magic
  -- three times over on casts alone (build/attempts/wt/v030-route/lab/
  -- tower/c1, c4, c5: 'battle $0AD LOST'); a person who reads the tower's
  -- spell lists wears Reflect there and lets the spells bounce
  -- (route-wor-thamasa.md 5.3 named it a lab branch)
  H.crossDoor(40, 30, MAP_THAMASA_RELICS, 44, 13, "Thamasa's relic shop door 344 (40,30) -> 350",
    { fight = FIGHT, avoid = THAMASA_AVOID }),
  H.shopTalk(43, 8, "Thamasa's relic shop", { fight = FIGHT }),
  H.call(function() H.assertEq(H.shopId(), 75, "the counter opened shop 75 ($0201)") end),
  H.buyItem(WALL_RING, function() return math.max(0, 4 - H.invCountOf(WALL_RING)) end, "WALL RING for each of the four"),
  H.shopClose("Thamasa's relic shop"),
  H.crossDoor(44, 14, MAP_THAMASA, 40, 32, "Thamasa's relic shop -> the street", { fight = FIGHT }),
  H.navTo(22, 47, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT, avoid = THAMASA_AVOID }),
  H.driveUntil(function() return H.worldMode() end, 6000, { H.hold({ "down" }), H.waitFrames(4) }, "off Thamasa's edge"),
  H.release(),
  H.waitWorldSettled("out of Thamasa", 1800, 30),
  board(),
  H.flyTo(TOWER_LANDING[1], TOWER_LANDING[2], { what = "the Falcon back to the tower" }),
  H.fieldCare({ threshold = 1.0, tag = "beside the tower" }),
  H.call(function()
    say("wor", "beside the tower")
    H.log("[wor] " .. kitLine())
  end),
  H.saveState("wor_relm_savept.mss"),
  H.saveAtCheckpoint("wor-tower-v1"),
  H.saveState("wor_relm.mss"),
  H.logStep(function()
    return string.format("wor_relm generated: TERRA L%d, CELES L%d, RELM L%d and STRAGO L%d beside the tower, "
      .. "world (%d,%d), saved in slot 3; lores $%06X", level(TERRA), level(CELES), level(RELM), level(STRAGO),
      H.worldX(), H.worldY(), lores())
  end),
})
