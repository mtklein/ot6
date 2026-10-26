-- gen_wor_tritoch.lua -- the cliffs above Narshe to UMARO: Continue the
-- `wor-narshe-cliffs-v1` battery (CYAN, TERRA, CELES and MOG on map 34's save
-- point), the Ice Dragon (event battle 132, touched beside the save point),
-- Tritoch (event battle 119, map 35), Umaro's cave (the X-Ether and the
-- Gauntlet), the carving: Terrato and Umaro (event battle 117), UMARO's join,
-- down through the cliffs and the mines to the town and the Falcon, the cabin
-- (UMARO and MOG with TERRA and CELES; the stones onto wearers), and save
-- beside the Falcon outside Narshe: the `wor-narshe-v1` battery.  Each of
-- the three fights is a game over when lost; the runner retries from the
-- save point, as a person reloads (Umaro's cave has no save point).
-- docs/design/route-wor-narshe.md has the plan and what this measured.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CYAN, EDGAR, SABIN, CELES, SETZER, MOG, UMARO = 0, 2, 4, 5, 6, 9, 10, 13
local TONIC, POTION, FENIX, REMEDY, SOFT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4
local REVIVIFY, TENT, XPOTION, ETHER, ELIXIR, TINCTURE = 0xF1, 0xF7, 0xEA, 0xEC, 0xEE, 0xEB
local X_ETHER, GAUNTLET = 0xED, 0xD0
local MAP_NARSHE, MAP_CLIFF_LO, MAP_CLIFF_SAVE, MAP_TRITOCH, MAP_MINES = 32, 33, 34, 35, 36
local MAP_CAVE, MAP_CAVE_B, MAP_LAIR = 281, 282, 283
local NARSHE_WORLD = { { 115, 33 } }
-- after the regroup the Falcon lifts off and lands three tiles south of
-- where it waited, and the arc saves there: a lift-off and a landing on
-- the same tile stalled the pilot one tile off it (build/attempts/wt/
-- v029-narshe-route/varA/tritoch_k2_s12.log, '[fly] ... tile (115,36) ->
-- (115,35): 0.7 tiles ... speed 0', then 'timeout after 6000 frames')
local SAVE_LANDING = { 115, 38 }
-- magicite: give_genju's receipt order (Ramuh 0)
local TERRATO, TRITOCH = 4, 10
-- the bosses (route_data.py pool event 132, 119, 117)
local ICEDRAGON, TRITOCH_SP, UMARO_SP = 0x149, 0x144, 0x110
local ICEDRAGON_FORMATION, TRITOCH_FORMATION, UMARO_FORMATION = 366, 487, 444
-- the fight driver for the three: fire, which each of them is weak to, from
-- whoever knows it (TERRA's natural Fire; the Ifrit and Maduin wearers once
-- they learn it), boosted toward Fire 2 and 3; CELES on Runic (N. Cross, Ice
-- 3 and Blizzard are Runic-able), CYAN on his SwdTech (route-wor-narshe.md
-- 5).  The first Tritoch fight without fire (build/lab/narshe/t2) broke it
-- three times on Fight and took 485 of its 30,000 HP in 17,100 frames.
local FIRE = 0x00
-- TERRA opens with Trance once three points are banked (her Morph at 3 BP,
-- which lasts the battle: magic x2, damage taken halved; kits.md, Terra),
-- as a player spends her divine on a boss.
local BOSS_FIGHT = { runic = true, bushido = true, magic = { [0] = { spell = FIRE } }, nuke = { FIRE },
  trance = true }
-- The Ice Dragon (defence 74, not Tritoch's 254): CELES swings the fire
-- blades armForFire put in her hands rather than casting, so her Fight
-- lands the weakness on every swing and the fire key on each; TERRA and
-- CYAN cast fire as before.
local DRAGON_FIGHT = { bushido = true, magic = { [TERRA] = { spell = FIRE }, [CYAN] = { spell = FIRE } },
  trance = true }
-- their threats for the relic rule (an informed reading of their scripts:
-- ice spells and Frozen, which no relic in the bag guards; the damage is
-- mostly magic)
local ICE_THREATS = { s1 = 0x00, s2 = 0x00, magic = true, boss = true }
-- the town's doors and the mines' and cliffs' (gen_wor_narshe's tables)
local NARSHE_DOORS = { { 41, 36 }, { 52, 37 }, { 32, 30 }, { 29, 25 }, { 18, 22 }, { 32, 16 }, { 41, 22 },
  { 43, 11 }, { 46, 10 }, { 49, 12 }, { 53, 9 }, { 15, 56 }, { 22, 44 }, { 10, 36 }, { 26, 8 }, { 33, 54 } }
local MINES_DOORS = { { 57, 11 }, { 57, 21 }, { 25, 59 }, { 18, 51 }, { 107, 12 }, { 117, 12 }, { 113, 45 },
  { 108, 60 }, { 73, 61 }, { 111, 29 }, { 112, 29 }, { 113, 29 } }
local CLIFF_DOORS = { { 37, 25 }, { 24, 10 }, { 31, 10 }, { 30, 20 }, { 31, 20 }, { 32, 20 } }
-- the Ice Dragon's tile on map 34, and the long exit to map 33
local DRAGON_TILE = { 22, 20 }
local CLIFF_SAVE_AVOID = { { 16, 41 }, { 17, 41 }, { 18, 41 }, { 19, 41 }, { 20, 41 } }
-- Umaro's cave: the floor drops (route-wor-narshe.md 2.9), kept off a walk
-- that does not mean to take them
local DROPS_281 = { { 10, 54 }, { 11, 53 } }
local DROPS_282 = { { 14, 30 }, { 33, 26 } }
local CAVE_DOORS = { { 9, 52 }, { 15, 51 }, { 24, 51 }, { 52, 47 }, { 53, 36 }, { 27, 14 } }

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
  { SETZER, "SETZER" }, { MOG, "MOG" }, { UMARO, "UMARO" } }
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
-- presses START, which commits the default name (gen_moogle's LOCKE).
-- A random battle that comes up instead (the talk's approach stepped onto
-- an encounter: build/attempts/wt/v037-tritoch/lab/baseK/k1_s33.log.gz,
-- UMARO's talk at f44155, then "[seed] battle ... g0102" and START pressed
-- into the battle until the no-effect watchdog) is fought with the
-- tactical driver; when, after such a battle, the party stands in control
-- with no event running for 120 frames, the talk did not take: the ride
-- ends with `pred` still false and the caller talks again (the repeatN
-- around UMARO's talk).  Without a battle the ride waits for `pred` to
-- its budget and fails there, as before.
local function rideNaming(pred, maxF, what)
  local ph, idle, inBattle, battled = 0, 0, false, false
  local drv = H.fightDriverFor("rideNaming", { tactical = true, boost = true, items = true, healPercent = 55 }, FIGHT)
  return H.withReset(H.seqStep({
    H.driveUntil(function() return (pred() and settled()) or (battled and idle >= 120) end, maxF, {
      H.call(function()
        if H.battleLoadStarted() then inBattle, battled, idle = true, true, 0; drv.frame(); return end
        if inBattle then drv.idle(); inBattle = false end
        ph = (ph + 1) % 16
        idle = (settled() and not H.eventRunning() and not pred()) and idle + 1 or 0
        if H.readByte(0x0059) ~= 0 then H.setPad(ph < 6 and { "start" } or {}); return end
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, what),
    H.release(),
    H.call(function()
      if not pred() then H.log(string.format("[story] f%d %s: a random battle came up instead of the event, and "
        .. "the party stands in control with the event not run; talking again", H.frame, what)) end
      say("story", what)
    end),
  }), function() ph, idle, inBattle, battled = 0, 0, false, false end)
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

-- a drawn frame (render on demand, #394), asked for until one comes
local function drawnFrame()
  return H.seqStep({
    H.call(function() H.requestRender() end),
    H.waitUntil(function()
      if H.frameDrawn() then return true end
      H.requestRender()
      return false
    end, 30, "a drawn frame", 1),
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
local BOSSES = { [ICEDRAGON] = true, [TRITOCH_SP] = true, [UMARO_SP] = true }
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
  local ph, pressed, inBattle = 0, 0, false
  local drv = H.fightDriverFor("touchNpc", { tactical = true, boost = true, items = true, healPercent = 55 }, FIGHT)
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
          -- a random battle that comes up during the presses is fought
          -- (build/attempts/wt/v037-tritoch/lab/fixK2C/k1_s9.log.gz: "[seed]
          -- battle ... g0114" at f13681, then "timeout after 1200 frames
          -- driving toward the Ice Dragon (34 NPC_2): touch it"); the 1200
          -- frames bound the presses, not the battle
          H.withReset(H.driveUntil(begun, 40000, {
            H.call(function()
              ph = (ph + 1) % 8
              if H.battleLoadStarted() then
                -- the touched body's own battle is begun(), the caller's to play
                if H.formationHas({ [ICEDRAGON] = true }) then H.setPad({}); return end
                inBattle = true; drv.frame(); return
              end
              if inBattle then drv.idle(); inBattle = false end
              pressed = pressed + 1
              if pressed > 1200 then
                error(string.format("timeout after 1200 frames of presses toward %s: touch it", what))
              end
              if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
              local dx, dy = H.objX(o) - H.fieldX(), H.objY(o) - H.fieldY()
              local dir = dx > 0 and "right" or dx < 0 and "left" or dy > 0 and "down" or "up"
              H.setPad(ph < 4 and { [dir] = true, a = true } or { [dir] = true })
            end),
          }, what .. ": touch it"), function() ph, pressed, inBattle = 0, 0, false end),
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
local function dragonObj()
  local found = {}
  for o = 0x10, 0x2F do
    local ox, oy = H.objX(o), H.objY(o)
    if not (ox == 0 and oy == 0) and not (ox == 25 and oy == 5) then found[#found + 1] = o end
  end
  H.assertEq(#found, 1, "map 34 holds one live object besides the save point (the Ice Dragon)")
  H.log(string.format("[npc] the Ice Dragon: object $%02X at (%d,%d)", found[1], H.objX(found[1]), H.objY(found[1])))
  return found[1]
end

-- ---- armed for the ice ------------------------------------------------------
-- Every boss here absorbs ice and its spells are ice (route-wor-narshe.md
-- 5): each of the four wears, in each armor slot, the bag's piece that best
-- answers ice (absorbs, then nulls, then halves; then defense), when it
-- answers ice better than what is worn.  A person reading "ice everywhere"
-- does this much.  ItemProp armor: +$0F halves, +$16 absorbs, +$17 nulls.
local ICE = 0x02
local function iceScore(id)
  if id == 0xFF then return 0 end
  local k = ip(id, 0) & 7
  if k ~= 2 and k ~= 3 and k ~= 4 then return 0 end
  if (ip(id, 0x16) & ICE) ~= 0 then return 3 end
  if (ip(id, 0x17) & ICE) ~= 0 then return 2 end
  if (ip(id, 0x0F) & ICE) ~= 0 then return 1 end
  return 0
end
local function armForIce(party)
  local plan = {}
  local steps = { H.call(function()
    plan = {}
    local bag = {}
    for s = 0, 255 do
      local id, n = H.readByte(0x1869 + s), H.readByte(0x1969 + s)
      if id ~= 0xFF and n > 0 and iceScore(id) > 0 then bag[id] = n end
    end
    for _, m in ipairs(party) do
      local items = {}
      for _, sl in ipairs({ { 1, 3 }, { 2, 4 }, { 3, 2 } }) do
        local cur = H.readByte(c(m[1], 0x1F + sl[1]))
        local skip = sl[1] == 1 and cur ~= 0xFF and (ip(cur, 0) & 7) == 1   -- a Genji Glove's second weapon
        local best, bs, bg = cur, iceScore(cur), guard(cur)
        for id, n in pairs(bag) do
          if n > 0 and (ip(id, 0) & 7) == sl[2] and wearable(m[1], id) then
            local sc = iceScore(id)
            if sc > bs or (sc == bs and sc > 0 and guard(id) > bg) then best, bs, bg = id, sc, guard(id) end
          end
        end
        if not skip and best ~= cur then
          bag[best] = bag[best] - 1
          items[#items + 1] = { sl[1], best }
          H.log(string.format("[kit] %s slot %d: $%02X (ice %d) -> $%02X (ice %d)", m[2], sl[1], cur, iceScore(cur),
            best, bs))
        end
      end
      if #items > 0 then plan[#plan + 1] = { ch = m[1], name = m[2], items = items } end
    end
  end) }
  for i = 1, 4 do
    steps[#steps + 1] = H.cond(function() return plan[i] ~= nil end, {
      lazy(function() return H.equipKit(plan[i].ch, plan[i].items, { tag = plan[i].name .. " for the ice" }) end),
    }, {})
  end
  steps[#steps + 1] = H.call(function() say("kit", "armed for the ice: " .. kitLine()) end)
  return H.seqStep(steps)
end

-- ---- armed with fire -------------------------------------------------------
-- The three bosses are weak to fire, and the bag holds fire blades (two
-- Flame Sabres on wor-narshe-cliffs-v1).  A fire blade's Fight lands the
-- weakness on every swing: double damage, and the fire key chips a shield
-- (break-coverage-vector.md: "its vanilla fire weakness (Ifrit's
-- magicite, or the Flame Sabre)").  So the bag's fire blades go into the
-- hands of whoever swings most -- a two-weapon relic's wearer first (both
-- hands), then by vigor -- where the blade's power doubled beats what the
-- hand holds and it keeps the hand's Runic and SwdTech (ItemProp +$13 bits
-- 7 and 1).  An ice blade counts for nothing here: every boss absorbs ice.
-- What each hand held goes back on after Umaro, so the legs after this
-- one keep their kit.  Reads only; the dressing is the Equip menu's presses.
local FIRE_EL = 0x01
local FIRE_WORN = {}
local function fireBlade(id)
  return id ~= 0xFF and (ip(id, 0) & 7) == 1 and (H.weaponElement(id) & FIRE_EL) ~= 0
end
local function twoHands(ch)
  for _, off in ipairs({ 0x23, 0x24 }) do
    local r = H.readByte(c(ch, off))
    if r ~= 0xFF and (ip(r, 0) & 7) == 5 and (ip(r, 12) & 0x38) ~= 0 then return true end
  end
  return false
end
local function bladeScore(id)
  if id == 0xFF or (ip(id, 0) & 7) ~= 1 then return 0 end
  local el = H.weaponElement(id)
  if (el & ICE) ~= 0 then return 0 end
  return ip(id, 0x14) * (((el & FIRE_EL) ~= 0) and 2 or 1)
end
local function armForFire(party)
  local plan = {}
  local steps = { H.call(function()
    plan, FIRE_WORN = {}, {}
    local bag = {}
    for s = 0, 255 do
      local id, n = H.readByte(0x1869 + s), H.readByte(0x1969 + s)
      if n > 0 and fireBlade(id) then bag[id] = (bag[id] or 0) + n end
    end
    local order = {}
    for i, m in ipairs(party) do order[#order + 1] = { m = m, i = i, two = twoHands(m[1]), vig = H.readByte(c(m[1], 0x1A)) } end
    table.sort(order, function(a, b)
      if a.two ~= b.two then return a.two end
      if a.vig ~= b.vig then return a.vig > b.vig end
      return a.i < b.i
    end)
    for _, o in ipairs(order) do
      local ch, name = o.m[1], o.m[2]
      local items = {}
      local hands = { 0 }
      local left = H.readByte(c(ch, 0x20))
      if o.two and left ~= 0xFF and (ip(left, 0) & 7) == 1 then hands[2] = 1 end
      for _, sl in ipairs(hands) do
        local cur = H.readByte(c(ch, 0x1F + sl))
        local need = (cur ~= 0xFF and (ip(cur, 0) & 7) == 1) and (ip(cur, 0x13) & 0x82) or 0
        local best, bs = nil, bladeScore(cur)
        -- an empty hand stays empty: the Equip menu has no unequip to put
        -- it back after Umaro, so only a hand holding a weapon is swapped
        if cur == 0xFF then bs = math.huge end
        for id, n in pairs(bag) do
          if n > 0 and wearable(ch, id) and (ip(id, 0x13) & need) == need and bladeScore(id) > bs then
            best, bs = id, bladeScore(id)
          end
        end
        H.log(string.format("[kit] %s hand %d: $%02X (score %d), the bag's best fire blade %s", name, sl, cur,
          bladeScore(cur), best and string.format("$%02X (score %d)", best, bs) or "none better"))
        if best then
          bag[best] = bag[best] - 1
          items[#items + 1] = { sl, best }
          FIRE_WORN[#FIRE_WORN + 1] = { ch = ch, name = name, slot = sl, old = cur }
        end
      end
      if #items > 0 then plan[#plan + 1] = { ch = ch, name = name, items = items } end
    end
  end) }
  for i = 1, 4 do
    steps[#steps + 1] = H.cond(function() return plan[i] ~= nil end, {
      lazy(function() return H.equipKit(plan[i].ch, plan[i].items, { tag = plan[i].name .. " with fire" }) end),
    }, {})
  end
  steps[#steps + 1] = H.call(function() say("kit", "armed with fire: " .. kitLine()) end)
  return H.seqStep(steps)
end
-- each hand armForFire changed back to what it held
local function unarmFire()
  local steps = {}
  for _, ch in ipairs({ CYAN, TERRA, CELES, MOG }) do
    steps[#steps + 1] = lazy(function()
      local items = {}
      for _, w in ipairs(FIRE_WORN) do
        if w.ch == ch then items[#items + 1] = { w.slot, w.old } end
      end
      if #items == 0 then return H.call(function() end) end
      return H.equipKit(ch, items, { tag = "char " .. ch .. " back from fire" })
    end)
  end
  steps[#steps + 1] = H.call(function() say("kit", "the fire blades back in the bag: " .. kitLine()) end)
  return H.seqStep(steps)
end

local PARTY = { { CYAN, "CYAN" }, { TERRA, "TERRA" }, { CELES, "CELES" }, { MOG, "MOG" } }
local REGROUP = { UMARO, MOG, TERRA, CELES }
local REGROUP_MEMBERS = { { UMARO, "UMARO" }, { MOG, "MOG" }, { TERRA, "TERRA" }, { CELES, "CELES" } }
-- relics are dressed for the arc's bosses once, before the Ice Dragon (the
-- three share their threats); dressing them again before Umaro, after the
-- Gauntlet came into the bag, planned a swap between two members that the
-- relic rule cannot make from the bag (build/lab/narshe/t4: 'a member's new
-- relics are all in the bag (no swap deadlock)')
local function ready(tag, relics)
  return H.seqStep({
    relics and H.dressRelics(PARTY, { threats = ICE_THREATS, tag = "relics for " .. tag }) or H.call(function() end),
    H.fieldCare({ threshold = 1.0, tag = "before " .. tag }),
    H.call(function() say("boss", "ready for " .. tag .. ": " .. kitLine()) end),
  })
end

H.run({ maxFrames = 500000 }, {
  H.bootCheckpoint("wor-narshe-cliffs-v1"),
  watches(),
  fightWatch(),
  H.call(function()
    say("wor", "boot")
    H.log("[wor] " .. kitLine())
  end),
  -- @@setup-end

  -- ---- 1. the Ice Dragon, beside the save point -----------------------------
  -- @@stage dragon
  armForIce(PARTY),
  ready("the Ice Dragon", true),
  -- after the relics, so the two-weapon relic it reads is the one worn
  armForFire(PARTY),
  H.saveState("wor_tritoch_ready.mss"),
  -- map 34 NPC_2 (posted (22,20)), _cc36df: touched, event battle 132, a
  -- game over when lost (_ca5ea9)
  -- It walks at random (npc_prop.asm: set_npc_movement RANDOM), so a walk
  -- past it can bump into it; the walk up in gen_wor_narshe keeps to the
  -- cliffs' west side, and a fight it started there is the same fight
  H.cond(function() return sw(0x0695) == 1 end, {
    touchNpc(dragonObj, function()
      return (H.battleLoadStarted() and H.formationHas({ [ICEDRAGON] = true })) or sw(0x0695) == 0
    end, "the Ice Dragon (34 NPC_2)"),
    H.advanceStory(function()
      return sw(0x0695) == 0 and not H.battleLoadStarted() and map() == MAP_CLIFF_SAVE and settled()
    end, 120000, { playBattles = "tactical", fight = DRAGON_FIGHT }),
    fought(ICEDRAGON_FORMATION, "the Ice Dragon"),
  }, {
    H.call(function() H.log("[boss] the Ice Dragon was met on the walk up (gen_wor_narshe): $0695 already clear") end),
    -- no battle between the two saves on this branch: a drawn frame between
    -- them, or the second carries the PPU's palette address unknown
    -- (render on demand, #394; build/attempts/wt/v037-tritoch/lab/fixBK/
    -- k2_s42.log.gz: "fixture wor_tritoch_dragon.mss: its savestate
    -- carries the PPU's palette address UNKNOWN")
    drawnFrame(),
  }),
  H.saveState("wor_tritoch_dragon.mss"),

  -- ---- 2. Tritoch -------------------------------------------------------------
  -- @@stage tritoch
  walkTo(25, 6, "below the save point"),
  ready("Tritoch"),
  walkInto(20, 1, MAP_TRITOCH, "the cliffs' save point -> Tritoch's ledge (35)", CLIFF_SAVE_AVOID),
  via({ { 23, 20 }, { 12, 19 } }, "Tritoch's ledge to the ice", { { 9, 14 }, { 9, 12 } }),
  -- (9,14), _cc3719: the thaw and event battle 119, a game over when lost;
  -- Tritoch is given ($029E) and the cave's mouth opens (9,12)
  stepOn(9, 14, function() return sw(0x029E) == 1 or H.battleLoadStarted() end, { { 9, 12 } }),
  H.advanceStory(function()
    return sw(0x029E) == 1 and not H.battleLoadStarted() and map() == MAP_TRITOCH and settled()
  end, 120000, { playBattles = "tactical", fight = BOSS_FIGHT }),
  fought(TRITOCH_FORMATION, "Tritoch"),
  H.call(function()
    H.assertEq(sw(0x029E), 1, "Tritoch freed ($029E, _cc3719)")
    H.assertEq((H.readByte(0x1A69 + (TRITOCH >> 3)) >> (TRITOCH & 7)) & 1, 1, "Tritoch owned (give_genju)")
  end),
  H.saveState("wor_tritoch_tritoch.mss"),

  -- ---- 3. Umaro's cave ----------------------------------------------------------
  -- @@stage cave
  H.fieldCare({ tag = "after Tritoch" }),
  -- (9,12), _cc37e7: "Hop into it?" Yes drops the party to 281 (14,55)
  stepOn(9, 12, function() return H.dialogWaiting() end),
  H.dialogChoice(0, { inBattle = false, what = "Hop into it? Yes", tag = "the cave's mouth" }),
  H.waitUntil(function() return map() == MAP_CAVE and settled() end, 6000, "Umaro's cave: map 281", 1),
  H.call(function() say("route", "in Umaro's cave") end),
  -- the landing's pocket: (15,51) -> 282 (22,31), the X-Ether (282
  -- (14,25)), then the floor drop (14,30) -> 281 (42,53), the main pocket
  walkInto(15, 51, MAP_CAVE_B, "the landing -> 282 (22,31)", DROPS_281),
  via({ { 20, 27 } }, "282 to the X-Ether", DROPS_282),
  chestAt(14, 25, 0x0A8, "X-Ether (282 (14,25))", X_ETHER, DROPS_282),
  stepOn(14, 30, function() return map() == MAP_CAVE end),
  H.waitUntil(function() return map() == MAP_CAVE and settled() end, 3000, "the drop (14,30) -> 281", 1),
  H.call(function() say("route", "dropped into the cave's main pocket") end),
  via({ { 47, 50 } }, "the cave to the Gauntlet", CAVE_DOORS),
  chestAt(41, 58, 0x0A9, "Gauntlet (281 (41,58))", GAUNTLET, CAVE_DOORS),
  via({ { 50, 54 }, { 57, 51 }, { 55, 41 } }, "the cave to its inner door", CAVE_DOORS),
  warpVia(53, 36, "the cave (53,36) -> (27,13)", exceptOf(CAVE_DOORS, 53, 36)),
  -- (40,12), _ccd967: A held facing up drops the party into the lair 283
  via({ { 29, 10 }, { 37, 12 } }, "the cave to the lair's floor", { { 31, 9 } }),
  H.navTo(40, 12, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, avoid = { { 31, 9 } } }),
  H.faceAndHoldA("up", function() return map() == MAP_LAIR end, 1200, "the lair's floor (281 (40,12)): face up, A"),
  H.release(),
  H.waitUntil(function() return map() == MAP_LAIR and settled() end, 3000, "the lair: map 283", 1),
  H.saveState("wor_tritoch_lair.mss"),

  -- ---- 4. Terrato and UMARO ----------------------------------------------------
  -- @@stage lair
  ready("Umaro"),
  -- the carving (283 NPC_1 (57,15), _ccd6eb): "Remove the Magicite?" Yes,
  -- event battle 117, a game over when lost; Terrato given ($027A)
  walkTo(57, 16, "below the carving"),
  talkTo(57, 15, "the carving (283 NPC_1)"),
  H.dialogChoice(0, { inBattle = false, what = "Remove the Magicite? Yes", tag = "the carving" }),
  H.advanceStory(function()
    return sw(0x027A) == 1 and not H.battleLoadStarted() and map() == MAP_LAIR and settled()
  end, 120000, { playBattles = "tactical", fight = BOSS_FIGHT }),
  fought(UMARO_FORMATION, "Umaro"),
  H.call(function()
    H.assertEq(sw(0x027A), 1, "Terrato taken ($027A, _ccd709)")
    H.assertEq((H.readByte(0x1A69 + (TERRATO >> 3)) >> (TERRATO & 7)) & 1, 1, "Terrato owned (give_genju)")
  end),
  H.saveState("wor_tritoch_umaro.mss"),
  unarmFire(),
  -- UMARO (283 NPC_2 (59,13), _ccd793, MOG in the party): his naming menu,
  -- and "me wait for you in big airship" ($02FD, $007E)
  H.fieldCare({ tag = "after Umaro" }),
  H.repeatN(3, {
    H.cond(function() return not (sw(0x02FD) == 1 and sw(0x007E) == 1) end, {
      H.fieldCare({ tag = "before UMARO's talk" }),
      talkTo(59, 13, "UMARO (283 NPC_2)"),
      rideNaming(function() return sw(0x02FD) == 1 and sw(0x007E) == 1 and map() == MAP_LAIR end, 20000, "UMARO joins"),
    }, {}),
  }),
  H.call(function()
    H.assertEq(sw(0x02FD), 1, "UMARO is available ($02FD, _ccd793)")
    say("wor", "UMARO joined")
  end),

  -- ---- 5. out: the cliffs, the mines, the town, the Falcon -------------------
  -- @@stage out
  -- the lair's exit (57,7), _cc3839: a slide down to map 33 below (35,17);
  -- that ledge's door (37,25) -> the mines (19,51); in the mines (25,59) ->
  -- (57,23), (57,11) -> (112,45), (108,60) -> 33 (31,22); 33's long exit
  -- (23-28,52) -> the town (38,2); the gate south onto the world
  stepOn(57, 7, function() return map() == MAP_CLIFF_LO end),
  H.waitUntil(function() return map() == MAP_CLIFF_LO and settled() end, 3000, "out of the lair: map 33", 1),
  H.call(function() say("route", "out of the lair") end),
  walkInto(37, 25, MAP_MINES, "the ledge -> the mines (36 (19,51))", { { 24, 10 } }),
  warpVia(25, 59, "the mines (25,59) -> (57,23)", exceptOf(MINES_DOORS, 25, 59)),
  via({ { 62, 22 }, { 63, 11 } }, "the mines to their upper inner door", MINES_DOORS),
  warpVia(57, 11, "the mines (57,11) -> (112,45)", exceptOf(MINES_DOORS, 57, 11)),
  via({ { 110, 49 } }, "the mines to their mouth", MINES_DOORS),
  walkInto(108, 60, MAP_CLIFF_LO, "the mines -> the cliffs (33 (31,22))", exceptOf(MINES_DOORS, 108, 60)),
  via({ { 29, 32 }, { 28, 41 } }, "the cliffs down to the town", CLIFF_DOORS),
  walkInto(26, 52, MAP_NARSHE, "the cliffs -> Narshe (32 (38,2))", CLIFF_DOORS),
  via({ { 38, 14 }, { 38, 26 }, { 38, 38 }, { 38, 50 } }, "Narshe's street to the gate", NARSHE_DOORS),
  H.navTo(38, 61, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, avoid = NARSHE_DOORS,
    arrive = function() return H.worldMode() end }),
  H.driveUntil(function() return H.worldMode() end, 3000, { H.hold({ "down" }), H.waitFrames(4) }, "off Narshe's gate"),
  H.release(),
  H.waitWorldSettled("out of Narshe", 1800, 30),
  H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
    { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, avoid = NARSHE_WORLD }),
  H.saveState("wor_tritoch_out.mss"),

  -- ---- 6. the cabin: UMARO, MOG, TERRA and CELES; the stones -------------------
  -- @@stage cabin
  regroup(REGROUP),
  H.call(function() say("regroup", "UMARO, MOG, TERRA and CELES") end),
  dressFromBag(UMARO, "UMARO"),
  H.dressRelics(REGROUP_MEMBERS, { tag = "relics with UMARO" }),
  -- the new stones: Terrato (Quake) on MOG, who wears none; Tritoch (Bolt
  -- among its three) on CELES in place of Maduin (route-wor-narshe.md 6.1)
  H.equipEsper(function() return posOf(MOG) end, TERRATO, { tag = "TERRATO -> MOG" }),
  H.equipEsper(function() return posOf(CELES) end, TRITOCH, { tag = "TRITOCH -> CELES" }),
  H.fieldCare({ tag = "after the regroup", threshold = H.CARE_BEFORE_FIGHTS }),
  H.call(function()
    H.assertEq(H.readByte(c(MOG, 0x1E)), TERRATO, "MOG holds Terrato")
    H.assertEq(H.readByte(c(CELES, 0x1E)), TRITOCH, "CELES holds Tritoch")
    say("regroup", "dressed: " .. kitLine())
  end),
  liftOff(),
  H.flyTo(SAVE_LANDING[1], SAVE_LANDING[2], { what = "the Falcon to the plain south of Narshe" }),
  H.waitWorldSettled("landed beside Narshe", 1800, 30),
  H.saveAtCheckpoint("wor-narshe-v1"),
  H.call(function()
    H.log(string.format("[wor] the stretch: %s; %s; %s", whereLine(), kitLine(), supplies()))
  end),
  H.saveState("wor_tritoch.mss"),
  H.logStep(function()
    return string.format("wor_tritoch generated: UMARO L%d, MOG L%d, TERRA L%d and CELES L%d on foot beside the "
      .. "Falcon, world (%d,%d), saved in slot 3", level(UMARO), level(MOG), level(TERRA), level(CELES), H.worldX(),
      H.worldY())
  end),
})
