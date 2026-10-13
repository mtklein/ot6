-- gen_wor_storm.lua -- the Storm Dragon on Mt. Zozo, and down to the Falcon:
-- Continue the `wor-mtzozo-v1` battery (CYAN, TERRA, CELES and SABIN on Mt.
-- Zozo's save point), arm for the dragon (it absorbs wind, is weak to
-- bolt), open the ledge and fight it (event battle 133, a game over when
-- lost), walk down through Zozo to the Falcon parked outside it, and save
-- there: the `wor-cyan-v1` battery.
-- docs/design/route-wor-cyan.md has the plan and what this measured.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CYAN, EDGAR, SABIN, CELES, SETZER = 0, 2, 4, 5, 6, 9
local TONIC, POTION, FENIX, REMEDY, SOFT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4
local REVIVIFY, TENT, XPOTION, ETHER, ELIXIR, TINCTURE = 0xF1, 0xF7, 0xEA, 0xEC, 0xEE, 0xEB
local MAP_ZOZO, MAP_ZOZO_IN = 221, 225
local MAP_MTZOZO, MAP_MTZOZO_N = 179, 176
-- Mt. Zozo's main map's doors (route_data.py map 179), and the Storm
-- Dragon's trigger and the save point, kept off a walk past them
local MZ_DOORS = { { 25, 30 }, { 11, 10 }, { 18, 5 }, { 56, 16 }, { 51, 40 }, { 48, 11 }, { 40, 15 } }
local ZOZO_WORLD = { { 43, 130 }, { 43, 131 }, { 44, 130 } }
local JIDOOR_DOOR, JIDOOR_LANDING, JIDOOR_WORLD = { 35, 156 }, { 36, 156 }, { { 34, 156 }, { 35, 156 } }
local MAP_JIDOOR, MAP_JIDOOR_SHOP = 198, 201
-- the Potions the next arc's legs are stocked for at Jidoor's counter
-- (H.careStockPotions' spend; the next counter is the next arc's)
local POTION_SPEND = 10
-- Zozo's doors (route_data.py map 221 / 225)
local ZOZO_DOORS = { { 13, 21 }, { 23, 17 }, { 42, 28 }, { 43, 24 }, { 44, 48 }, { 44, 41 }, { 49, 38 }, { 54, 35 },
  { 38, 57 }, { 35, 53 }, { 34, 50 }, { 30, 42 }, { 35, 33 }, { 31, 30 }, { 30, 21 }, { 35, 15 }, { 15, 39 },
  { 12, 36 }, { 49, 31 }, { 33, 9 } }
local ZOZO_IN_DOORS = { { 12, 44 }, { 11, 17 }, { 21, 15 }, { 52, 57 }, { 47, 47 }, { 59, 35 }, { 46, 9 },
  { 118, 27 }, { 104, 27 }, { 83, 62 }, { 124, 56 }, { 98, 62 }, { 110, 55 }, { 66, 57 }, { 11, 62 }, { 30, 62 },
  { 30, 34 }, { 35, 14 }, { 98, 59 }, { 103, 55 }, { 125, 46 } }
local PARTY = { { CYAN, "CYAN" }, { TERRA, "TERRA" }, { CELES, "CELES" }, { SABIN, "SABIN" } }
-- event group 133's formation (route_data.py pool event 133: both slots 367)
local STORM_FORMATION = 367
-- the fight driver: CELES on Runic (Wind Slash and Aero are spells), CYAN
-- on his SwdTech (route-wor-cyan.md 5)
local STORM_FIGHT = { runic = true, bushido = true }
-- the dragon's threats for the relic rule (an informed reading of its
-- script, route_data.py species 0x14B: Aero, Cyclonic, Wind Slash; no
-- status a relic guards; its damage is mostly magic)
local STORM_THREATS = { s1 = 0x00, s2 = 0x00, magic = true, boss = true }

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
  { SETZER, "SETZER" } }
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
-- the live object an NPC's posted tile names (objects $10 and up; a map's
-- NPC_1 is not always $10: Zozo's street starts at $17), the nearest
-- within four tiles (Zozo's merchant wanders)
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
local function ride(pred, maxF, what, opts)
  opts = opts or {}
  return H.seqStep({
    H.advanceStory(function() return pred() and settled() end, maxF, {
      playBattles = "tactical", fight = opts.fight or FIGHT, wipeEndsRide = opts.wipeEndsRide }),
    H.call(function() say("story", what) end),
  })
end
-- boarding: on foot on the parked airship's tile, A boards (world/move.asm
-- @204e); a battle on the last step onto the tile is fought and the party
-- walks back onto it (gen_wor_terra's board)
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
-- out of a town onto the world map, and back onto the parked Falcon's tile
-- (worldDoors: the town's entrance tiles, kept off the world walk)
local function toFalcon(exitX, exitY, what, worldDoors)
  return H.seqStep({
    H.navTo(exitX, exitY, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT,
      arrive = function() return H.worldMode() end }),
    H.waitWorldSettled("out of " .. what, 1800, 30),
    H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
      { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, avoid = worldDoors }),
  })
end

-- out of a town by its edge: walk to (x, y), then hold `dir` off the map
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

-- ---- the stair up to the rusted door (221 (49,39) -> (53,36)) -------------
-- probe_dump's tile map (build/attempts/wt/v028-cyan-route/zozo/): from the
-- balcony (49,39) the stair is (49,40) down, then "/" tiles (50,40) ->
-- (53,37) climbed with Right, and Up onto the landing (53,36).  The
-- library's planner reads no path across it (its z-level model mispredicts
-- the stair, as gen_zozo4_dadaluma's corridor), so the climb is pressed:
-- each press held until the party leaves the tile, then released.
-- A random battle on the stair (Zozo's street rolls group 78) is fought
-- with the route's tactical driver and the presses go on after it (the
-- first variation set stalled on one with the pad released:
-- build/attempts/wt/v028-cyan-route/varA/varA_s4.log, 'no-progress').
local function pressSeq(SEQ)
  local i, rest, held = 1, 0, 0
  local drv = H.fightDriverFor("stair", { tactical = true, boost = true, items = true, healPercent = 55 }, FIGHT)
  local fought = false
  return H.withReset({
    tick = function()
      if i > #SEQ then H.setPad({}); return "done" end
      if H.battleLoadStarted() then fought = true; held = 0; drv.frame(); return "frame" end
      if fought then fought = false; drv.idle() end
      if not (H.hasControl() and H.tileAligned()) and held == 0 then H.setPad({}); return "frame" end
      if SEQ[i][2]() and H.tileAligned() then
        H.setPad({})
        rest = rest + 1
        if rest >= 8 then
          H.log(string.format("[stair] %s done at (%d,%d) z %d", SEQ[i][1], H.fieldX(), H.fieldY(),
            H.readByte(0xB2) & 3))
          i, rest, held = i + 1, 0, 0
        end
        return "frame"
      end
      held = held + 1
      if held > 600 then error(string.format("the stair: %s held 600 frames at (%d,%d)", SEQ[i][1], H.fieldX(), H.fieldY())) end
      H.setPad({ [SEQ[i][1]] = true })
      return "frame"
    end,
    reset = function() i, rest, held, fought = 1, 0, 0, false end,
  }, function() i, rest, held, fought = 1, 0, 0, false end)
end
-- and down it again, from the landing (53,36) to the balcony (49,39)
local function descendStair()
  return pressSeq({ { "down", function() return H.fieldY() >= 37 end },
    { "left", function() return H.fieldX() <= 49 and H.fieldY() >= 40 end },
    { "up", function() return H.fieldY() <= 39 end } })
end

-- walk onto a trigger tile: the walk ends when its event takes the party
-- (gen_wor_terra's stepOn)
-- The walk ends on the trigger tile itself, its event running: a random
-- battle on the way is fought, not taken for the trigger's event (the
-- triggers here start none; gen_wor_terra's form, which also ended on an
-- event running beside the tile, ended a battle's opening one tile short of
-- the Storm Dragon's ledge: build/attempts/wt/v028-cyan-route/dev/storm1.log,
-- `step onto the trigger (48,11)' satisfied after 0 frames`).
local function stepOn(x, y, done)
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
        { maxFrames = 3000, playBattles = "tactical", fight = FIGHT, arrive = arrived }),
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

-- ---- gear ------------------------------------------------------------------
-- ItemProp (30-byte records): +0 type (low 3 bits: 1 weapon, 2 armor, 3
-- shield, 4 helmet, 5 relic), +1 the actor mask (a word), +$14 power or
-- defense, +$15 magic defense, +$0F element
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
-- the bag's best piece of a type the character can wear (defense plus
-- magic defense; a weapon by power, none whose element is in `noElem`)
local function bestInBag(ch, kind, noElem)
  local best, bs = nil, -1
  for s = 0, 255 do
    local id, n = H.readByte(0x1869 + s), H.readByte(0x1969 + s)
    if id ~= 0xFF and n > 0 and (ip(id, 0) & 7) == kind and wearable(ch, id) then
      local sc = kind == 1 and ip(id, 0x14) or guard(id)
      if kind == 1 and noElem and (ip(id, 0x0F) & noElem) ~= 0 then sc = -1 end
      if sc > bs then best, bs = id, sc end
    end
  end
  return best, bs
end

-- ---- the Storm Dragon's fight (reads only) -------------------------------
-- every monster action at ExecCmd ([monact]), and the dragon's gauge each
-- frame ([brk]: OT6_SHIELD_CUR/MAX at $3E40/$3E41 for monster slot 0, its
-- HP word $3BFC), as gen_wor_terra's Phunbaba lines
local STORM = 0x14B
local ATTACKS = { [0xEE] = "Battle", [0xEF] = "Special" }
local fightOn = false
local function fightWatch()
  return H.call(function()
    if fightOn then return end
    fightOn = true
    local a = H.sym("ExecCmd@battle_code")
    local lastAct = "-"
    emu.addMemoryCallback(function()
      local x = emu.getState()["cpu.x"] & 0xffff
      if x < 8 and x % 2 == 0 and H.battleLoadStarted() and H.readWord(0x57C0) == STORM then
        -- a party member's action: who, which command and attack (the break
        -- line below names the last one before the shields ran out)
        lastAct = string.format("entity %d cmd $%02X atk $%02X", x // 2, H.readByte(0xB5), H.readByte(0xB6))
      end
      if x >= 8 and x < 20 and x % 2 == 0 and H.readWord(0x57C0 + (x - 8)) == STORM then
        local cmd, atk = H.readByte(0xB5), H.readByte(0xB6)
        if cmd ~= 0x2E and cmd ~= 0x2F then
          H.log(string.format("[monact] f%d slot %d $%03X cmd $%02X atk $%02X%s", H.frame, x // 2 - 4,
            H.readWord(0x57C0 + (x - 8)), cmd, atk, ATTACKS[atk] and (" " .. ATTACKS[atk]) or ""))
        end
      end
    end, emu.callbackType.exec, a, a)
    local was, since = nil, 0
    emu.addEventCallback(function()
      if not H.battleLoadStarted() then was = nil; return end
      if H.readWord(0x57C0) ~= STORM then return end
      local cur, max = H.readByte(0x3E40), H.readByte(0x3E41)
      local broken = max > 0 and cur == 0
      if was == nil then was = broken; return end
      if broken and not was then
        since = H.frame
        H.log(string.format("[brk] f%d $%03X broken (0 of %d shields) at HP %d, the last party action %s", H.frame,
          STORM, max, H.readWord(0x3BFC), lastAct))
      elseif was and not broken then
        H.log(string.format("[brk] f%d $%03X window over after %d frames: shields %d of %d, HP %d", H.frame, STORM,
          H.frame - since, cur, max, H.readWord(0x3BFC)))
      end
      was = broken
    end, emu.eventType.endFrame)
  end)
end

-- ---- the dragon on its ledge ----------------------------------------------
-- 179 NPC_1 (47,6) walks while shown (_cc439f), and touching it or A
-- beside it starts battle 133: the walk up to it ends when the battle is up
-- (or already behind), and the fight is the story ride's, with the
-- dragon's own fight options
local function touchDragon()
  local function begun()
    return (H.battleLoadStarted() and H.formationWords()[1] == STORM) or sw(0x029A) == 1
  end
  local ph = 0
  return H.seqStep({
    H.cond(function() return not begun() end, {
      lazy(function()
        local o = npcAt(47, 6, "the Storm Dragon (179 NPC_1)")
        local function side()
          local ox, oy = H.objX(o), H.objY(o)
          for _, d in ipairs({ { 0, 1 }, { -1, 0 }, { 1, 0 }, { 0, -1 } }) do
            if H.bfsPath(ox + d[1], oy + d[2]) then return { ox + d[1], oy + d[2] } end
          end
          return { ox, oy + 1 }
        end
        return H.seqStep({
          H.navTo(function() return side()[1] end, function() return side()[2] end,
            { maxFrames = 3000, playBattles = "tactical", fight = FIGHT, arrive = function()
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
          }, "the Storm Dragon: touch it"), function() ph = 0 end),
          H.release(),
        })
      end),
    }, {}),
    H.call(function()
      if H.battleLoadStarted() then
        local w = H.formationWords()
        H.log(string.format("[storm] f%d the battle is up (%04X)", H.frame, w[1]))
      end
    end),
  })
end

-- ---- armed for the dragon ---------------------------------------------------
-- The Storm Dragon absorbs wind and is weak to bolt (MonsterProp, vanilla):
-- each hand that holds a weapon takes the best the bag or the hand offers by
-- power, doubled for a bolt edge and nothing for a wind one (CYAN's
-- Tempest, the runner's absorb guard's case).  A person reading "absorbs
-- wind, weak to bolt" does this much.
local WIND, BOLT = 0x10, 0x04
local function scoreVs(id)
  if id == 0xFF or (ip(id, 0) & 7) ~= 1 then return -1 end
  local e = ip(id, 0x0F)
  if (e & WIND) ~= 0 then return 0 end
  return ip(id, 0x14) * (((e & BOLT) ~= 0) and 2 or 1)
end
local function armForDragon()
  local plan = {}
  local steps = { H.call(function()
    plan = {}
    local bag = {}
    for s = 0, 255 do
      local id, n = H.readByte(0x1869 + s), H.readByte(0x1969 + s)
      if id ~= 0xFF and n > 0 and (ip(id, 0) & 7) == 1 then bag[id] = n end
    end
    for _, m in ipairs(PARTY) do
      local ch = m[1]
      for hand = 0, 1 do
        local cur = H.readByte(c(ch, 0x1F + hand))
        if hand == 0 or (cur ~= 0xFF and (ip(cur, 0) & 7) == 1) then
          local best, bs = cur, scoreVs(cur)
          for id, n in pairs(bag) do
            if n > 0 and wearable(ch, id) and scoreVs(id) > bs then best, bs = id, scoreVs(id) end
          end
          H.log(string.format("[kit] %s hand %d: holds $%02X (%d against the dragon); the best is $%02X (%d)", m[2],
            hand, cur, scoreVs(cur), best, bs))
          if best ~= cur then
            bag[best] = bag[best] - 1
            if cur ~= 0xFF then bag[cur] = (bag[cur] or 0) + 1 end
            plan[#plan + 1] = { ch = ch, name = m[2], hand = hand, id = best }
          end
        end
      end
    end
  end) }
  for i = 1, 8 do
    steps[#steps + 1] = H.cond(function() return plan[i] ~= nil end, {
      lazy(function()
        local e = plan[i]
        return H.equipKit(e.ch, { { e.hand, e.id } }, { tag = string.format("%s hand %d -> $%02X", e.name, e.hand, e.id) })
      end),
    }, {})
  end
  steps[#steps + 1] = H.call(function()
    for _, m in ipairs(PARTY) do
      for hand = 0, 1 do
        local id = H.readByte(c(m[1], 0x1F + hand))
        H.assertEq(id ~= 0xFF and (ip(id, 0) & 7) == 1 and (ip(id, 0x0F) & WIND) ~= 0, false,
          string.format("%s's hand %d ($%02X) is not a wind weapon the dragon absorbs", m[2], hand, id))
      end
    end
    H.log("[kit] armed for the dragon: " .. kitLine())
  end)
  return H.seqStep(steps)
end
-- and back to the walk's: each hand's best by power, no element barred
local function armForWalk()
  local plan = {}
  local steps = { H.call(function()
    plan = {}
    for _, m in ipairs(PARTY) do
      local cur = H.readByte(c(m[1], 0x1F))
      local id, sc = bestInBag(m[1], 1)
      if id and sc > ip(cur, 0x14) and H.readByte(c(m[1], 0x20)) ~= id then
        plan[#plan + 1] = { ch = m[1], name = m[2], id = id }
      end
    end
  end) }
  for i = 1, 4 do
    steps[#steps + 1] = H.cond(function() return plan[i] ~= nil end, {
      lazy(function()
        local e = plan[i]
        return H.equipKit(e.ch, { { 0, e.id } }, { tag = string.format("%s hand 0 -> $%02X", e.name, e.id) })
      end),
    }, {})
  end
  return H.seqStep(steps)
end


H.run({ maxFrames = 300000 }, {
  H.bootCheckpoint("wor-mtzozo-v1"),
  watches(),
  fightWatch(),
  H.call(function()
    say("wor", "boot")
    H.log("[wor] " .. kitLine())
  end),

  -- ---- 1. armed and cared for, at the save point -----------------------------
  armForDragon(),
  H.dressRelics(PARTY, { threats = STORM_THREATS, tag = "relics for the Storm Dragon" }),
  H.fieldCare({ threshold = 1.0, tag = "before the Storm Dragon" }),
  H.call(function() say("storm", "ready: " .. kitLine()) end),
  H.saveState("wor_storm_ready.mss"),

  -- ---- 2. the Storm Dragon ------------------------------------------------------
  -- the ledge's trigger (179 (48,11), _cc4362) opens the rock and shows the
  -- dragon ($0299, NPC_1 at (47,6)); touching it is event battle 133
  -- (_cc43cd), a game over when lost (_ca5ea9): the runner retries from the
  -- save point, as a person reloads
  stepOn(48, 11, function() return sw(0x0299) == 1 end),
  ride(function() return sw(0x0299) == 1 end, 3000, "the Storm Dragon shows itself"),
  touchDragon(),
  H.advanceStory(function()
    return sw(0x029A) == 1 and not H.battleLoadStarted() and map() == MAP_MTZOZO and settled()
  end, 120000, { playBattles = "tactical", fight = STORM_FIGHT }),
  H.call(function()
    local n = 0
    for _, o in ipairs(H.outcomes) do
      if (o.form & 0x1FF) == STORM_FORMATION then
        n = n + 1
        H.log(string.format("[storm] battle $%03X %s after %d ticks, %d seated", o.form & 0x1FF, o.kind, o.tick or -1,
          o.seatedN or -1))
      end
    end
    H.assertEq(sw(0x029A), 1, "the Storm Dragon is beaten ($029A, _cc43cd)")
    H.assertEq(n, 1, "the Storm Dragon's formation was fought once")
    say("storm", "the Storm Dragon is beaten")
  end),
  H.saveState("wor_storm_won.mss"),

  -- ---- 3. down to the Falcon ------------------------------------------------
  armForWalk(),
  H.dressRelics(PARTY, { tag = "relics after the Storm Dragon" }),
  H.fieldCare({ tag = "after the Storm Dragon" }),
  walkInto(56, 16, MAP_MTZOZO_N, "the east face -> the passage", exceptOf(MZ_DOORS, 56, 16)),
  walkInto(36, 15, MAP_MTZOZO, "the passage -> the west face", { { 8, 11 }, { 9, 11 } }),
  walkInto(25, 30, MAP_ZOZO, "Mt. Zozo -> Zozo", exceptOf(MZ_DOORS, 25, 30)),
  walkTo(53, 36, "the landing above the stair", ZOZO_DOORS),
  descendStair(),
  walkInto(49, 38, MAP_ZOZO_IN, "the balcony -> the café (225)", exceptOf(ZOZO_DOORS, 49, 38)),
  walkInto(12, 44, MAP_ZOZO, "the café -> Zozo's street", exceptOf(ZOZO_IN_DOORS, 12, 44)),
  toFalcon(63, 44, "Zozo", ZOZO_WORLD),

  -- ---- 4. Jidoor's counter after the dragon, and Save beside the Falcon ---------
  board(),
  H.flyTo(JIDOOR_LANDING[1], JIDOOR_LANDING[2], { what = "the Falcon to Jidoor" }),
  H.worldNavTo(JIDOOR_DOOR[1], JIDOOR_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_JIDOOR and not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_JIDOOR and settled() end, 2400, "Jidoor: map 198", 1),
  H.crossDoor(27, 41, MAP_JIDOOR_SHOP, 34, 20, "Jidoor's item shop door 198 (27,41) -> 201", { fight = FIGHT }),
  H.shopTalk(34, 15, "Jidoor's item shop", { fight = FIGHT }),
  H.call(function() H.assertEq(H.shopId(), 78, "the counter opened shop 78 ($0201)") end),
  H.buyItem(POTION, function()
    return math.max(0, H.careStockPotions(H.activeTopLevel(), { spend = POTION_SPEND }) - H.invCountOf(POTION))
  end, "POTION to the band and the field care"),
  H.buyItem(FENIX, function() return math.max(0, math.min(20, H.activeTopLevel()) - H.invCountOf(FENIX)) end,
    "FENIX DOWN to the level, capped at 20"),
  H.buyItem(REVIVIFY, function() return math.max(0, 3 - H.invCountOf(REVIVIFY)) end, "REVIVIFY to 3"),
  H.buyItem(TINCTURE, function() return math.max(0, math.ceil(H.activeTopLevel() / 4) - H.invCountOf(TINCTURE)) end,
    "TINCTURE to the level / 4"),
  H.shopClose("Jidoor's item shop"),
  H.bagArrange({ POTION, FENIX, TONIC, REMEDY }, { tag = "bag: combat items on top (Jidoor)" }),
  H.call(function() say("shop", "Jidoor after the dragon") end),
  H.crossDoor(34, 21, MAP_JIDOOR, 27, 43, "Jidoor's item shop -> the street", { fight = FIGHT }),
  toFalconBy(16, 61, "down", "Jidoor", JIDOOR_WORLD),
  H.fieldCare({ tag = "beside the Falcon" }),
  H.saveAtCheckpoint("wor-cyan-v1"),
  H.call(function()
    H.log(string.format("[wor] the stretch: %s; %s; %s", whereLine(), kitLine(), supplies()))
  end),
  H.saveState("wor_storm.mss"),
  H.logStep(function()
    return string.format("wor_storm generated: CYAN L%d, TERRA L%d, CELES L%d and SABIN L%d on foot beside the Falcon, "
      .. "world (%d,%d), saved in slot 3", level(CYAN), level(TERRA), level(CELES), level(SABIN), H.worldX(), H.worldY())
  end),
})
