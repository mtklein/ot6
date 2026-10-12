-- gen_wor_cyan.lua -- the World of Ruin from Mobliz to Mt. Zozo's save point:
-- Continue the `wor-terra-v1` battery (TERRA, CELES, SABIN and EDGAR on foot
-- beside the Falcon outside Mobliz), Maranda's letters (Lola, the reply sent
-- by carrier pigeon), Zozo's Rust-Rid and the rusted door, Mt. Zozo to CYAN
-- (he joins), out to the Falcon, CYAN into the party, Lola again with him,
-- and back up Mt. Zozo to its save point: the `wor-mtzozo-v1` battery, the
-- Storm Dragon's retry point.
-- docs/design/route-wor-cyan.md has the plan and what this measured.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CYAN, EDGAR, SABIN, CELES, SETZER = 0, 2, 4, 5, 6, 9
local TONIC, POTION, FENIX, REMEDY, SOFT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4
local REVIVIFY, TENT, XPOTION, ETHER, ELIXIR, TINCTURE = 0xF1, 0xF7, 0xEA, 0xEC, 0xEE, 0xEB
local MAP_MARANDA, MAP_LOLA = 284, 196
local MAP_ZOZO, MAP_ZOZO_IN = 221, 225
local MAP_MTZOZO, MAP_MTZOZO_W, MAP_MTZOZO_E, MAP_CLIFF, MAP_CAVE = 179, 177, 178, 180, 181
local MAP_MTZOZO_N = 176
-- Mt. Zozo's main map's doors (route_data.py map 179)
local MZ_DOORS = { { 25, 30 }, { 11, 10 }, { 18, 5 }, { 56, 16 }, { 51, 40 },
  -- and the Storm Dragon's trigger and the save point, kept off a walk past them
  { 48, 11 }, { 40, 15 } }
local MARANDA_DOOR, MARANDA_LANDING = { 69, 184 }, { 68, 184 }
local ZOZO_DOOR, ZOZO_LANDING = { 44, 130 }, { 45, 130 }
local JIDOOR_DOOR, JIDOOR_LANDING = { 35, 156 }, { 36, 156 }
local MAP_JIDOOR, MAP_JIDOOR_SHOP, MAP_MARANDA_ARMOR = 198, 201, 290
-- the towns' world entrances (route_data.py world-entrances 1)
local MARANDA_WORLD = { { 69, 184 }, { 70, 184 } }
local ZOZO_WORLD = { { 43, 130 }, { 43, 131 }, { 44, 130 } }
local JIDOOR_WORLD = { { 34, 156 }, { 35, 156 } }
-- magicite owned: give_genju's receipt bits from $1A69 (Ramuh = 0)
local PALIDOR = 0x3F - 0x36
-- Potions the legs from Jidoor to the next counter spend (route-wor-cyan.md
-- 4: Maranda and the climb 5, the grind 7, the Storm Dragon 0-19, the walk
-- down; the next counter is Jidoor's again, after the dragon): 33, which
-- the stack caps at 99 (H.careStockPotions, #419)
local POTION_SPEND = 33
local function potionTarget() return H.careStockPotions(H.activeTopLevel(), { spend = POTION_SPEND }) end
-- the gil the armor counter leaves untouched
local GIL_FLOOR = 100000
-- Zozo's doors (route_data.py map 221 / 225): a walk on one map keeps off
-- every door but its own
local ZOZO_DOORS = { { 13, 21 }, { 23, 17 }, { 42, 28 }, { 43, 24 }, { 44, 48 }, { 44, 41 }, { 49, 38 }, { 54, 35 },
  { 38, 57 }, { 35, 53 }, { 34, 50 }, { 30, 42 }, { 35, 33 }, { 31, 30 }, { 30, 21 }, { 35, 15 }, { 15, 39 },
  { 12, 36 }, { 49, 31 }, { 33, 9 } }
local ZOZO_IN_DOORS = { { 12, 44 }, { 11, 17 }, { 21, 15 }, { 52, 57 }, { 47, 47 }, { 59, 35 }, { 46, 9 },
  { 118, 27 }, { 104, 27 }, { 83, 62 }, { 124, 56 }, { 98, 62 }, { 110, 55 }, { 66, 57 }, { 11, 62 }, { 30, 62 },
  { 30, 34 }, { 35, 14 }, { 98, 59 }, { 103, 55 }, { 125, 46 } }

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
-- a walk by waypoints: the library's planner gives up past 4096 search
-- nodes (bfsPath's radius cap), which a long walk across Maranda or Zozo
-- passes, so a far target is reached through near ones
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
-- fly and land on (lx, ly), then walk onto the door (dx, dy) to `dst`
local function flyIn(lx, ly, dx, dy, dst, what)
  return H.seqStep({
    board(),
    H.flyTo(lx, ly, { what = "the Falcon to " .. what }),
    H.worldNavTo(dx, dy, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
      arrive = function() return map() == dst and not H.worldMode() end }),
    H.waitUntil(function() return map() == dst and settled() end, 2400, what .. ": map " .. dst, 1),
    H.call(function() say("route", "in " .. what) end),
  })
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

-- through a door in a wall: stand below it and hold Up until the map
-- changes (Maranda's armor shop: its door (6,12) is a wall tile, $F7, and
-- (6,13) below it the tile that takes the press)
local function enterUp(x, y, dst, what)
  return H.seqStep({
    H.navTo(x, y + 1, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
    H.driveUntil(function() return map() == dst end, 600, { H.hold({ "up" }), H.waitFrames(4) }, what),
    H.release(),
    H.waitUntil(function() return map() == dst and settled() end, 1200, what .. ": control on map " .. dst, 1),
    H.call(function() H.log(string.format("[route] %s: on map %d at (%d,%d)", what, map(), H.fieldX(), H.fieldY())) end),
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
local function climbStair()
  return pressSeq({ { "down", function() return H.fieldY() >= 40 end },
    { "right", function() return H.fieldY() <= 37 end },
    { "up", function() return H.fieldY() <= 36 end } })
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

-- ---- the Falcon's cabin: CYAN into the party -------------------------------
-- The party CYAN joins is full, so he waits aboard; the cabin's members
-- (map 12) each ask "Change party members?" (_caf59d), and the party menu
-- takes the swap.  Show-switches are $0388 + the character.  The four for
-- the Storm Dragon and the arcs after: CYAN, who joined, TERRA, CELES and
-- SABIN; EDGAR waits aboard with SETZER (route-wor-cyan.md 2).
local MAP_DECK, MAP_CABIN = 11, 12
local REGROUP = { CYAN, TERRA, CELES, SABIN }
local REGROUP_MEMBERS = { { CYAN, "CYAN" }, { TERRA, "TERRA" }, { CELES, "CELES" }, { SABIN, "SABIN" } }
-- (the deck's map init, _cae90b, shows the available members not in the
-- party: $02F0 + n sets $0388 + n, CYAN's and SHADOW's swapped, $038B and
-- $038A; route_data.py map 12)
local CABIN_NPCS = { { "CYAN", 0x12, 0x038B }, { "EDGAR", 0x14, 0x038C }, { "SETZER", 0x19, 0x0391 },
  { "SABIN", 0x15, 0x038D }, { "CELES", 0x16, 0x038E }, { "TERRA", 0x10, 0x0388 } }
local function regroup()
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
    -- with every member of the main room in the party, the waiting ones are
    -- in the rooms up the cabin's stairs: (23,44) -> (36,37), SETZER's
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
    H.partySelect(REGROUP, { tag = "the Falcon's cabin" }),
    H.waitUntil(function() return map() == MAP_DECK and settled() end, 2400, "back on the deck after the menu", 5),
    H.call(function()
      for _, ch in ipairs(REGROUP) do
        H.assertEq(partyOf(ch) == 1, true, string.format("char %d is in party 1 after the regroup", ch))
      end
      H.assertEq(inParty(EDGAR), false, "EDGAR waits aboard")
    end),
  })
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
-- dress a character's hand and armor slots from the bag where the bag holds
-- better than what is worn (slots: 0 weapon, 1 shield, 2 helmet, 3 armor)
local function dressFromBag(ch, name, noElem)
  return lazy(function()
    local items = {}
    for _, sl in ipairs({ { 0, 1 }, { 1, 3 }, { 2, 4 }, { 3, 2 } }) do
      local cur = H.readByte(c(ch, 0x1F + sl[1]))
      -- a second weapon in the left hand (a Genji Glove's) stays
      if sl[1] == 1 and cur ~= 0xFF and (ip(cur, 0) & 7) == 1 then goto continue end
      local id, sc = bestInBag(ch, sl[2], noElem)
      local cs = (cur == 0xFF) and -1 or (sl[2] == 1 and ip(cur, 0x14) or guard(cur))
      if sl[2] == 1 and cur ~= 0xFF and noElem and (ip(cur, 0x0F) & noElem) ~= 0 then cs = -1 end
      if id and sc > cs then items[#items + 1] = { sl[1], id } end
      H.log(string.format("[kit] %s slot %d: wears $%02X (%d), the bag's best $%02X (%d)", name, sl[1], cur, cs,
        id or 0xFF, sc or -1))
      ::continue::
    end
    if #items == 0 then return H.call(function() end) end
    return H.equipKit(ch, items, { tag = name .. " from the bag" })
  end)
end
-- the armor counter (Maranda's shop 81): for each of the four, each slot's
-- best piece on the shelf that beats both what is worn and the bag's best,
-- bought while the purse stays over GIL_FLOOR, dearest need first
local function armorBuys()
  local plan = {}
  local steps = { H.call(function()
    plan = {}
    local stock = H.shopStock(81)
    local gil = H.gil()
    for _, ch in ipairs(REGROUP) do
      for _, kind in ipairs({ 2, 4, 3 }) do
        local slot = ({ [2] = 3, [3] = 1, [4] = 2 })[kind]
        local cur = H.readByte(c(ch, 0x1F + slot))
        local skip = slot == 1 and cur ~= 0xFF and (ip(cur, 0) & 7) == 1
        local have = math.max(guard(cur), select(2, bestInBag(ch, kind)) or -1)
        local best, bs = nil, have
        for _, id in pairs(stock) do
          if (ip(id, 0) & 7) == kind and wearable(ch, id) and guard(id) > bs then best, bs = id, guard(id) end
        end
        local price = best and (ip(best, 0x1C) | (ip(best, 0x1D) << 8)) or 0
        if best and not skip and gil - price >= GIL_FLOOR then
          plan[best] = (plan[best] or 0) + 1
          gil = gil - price
          H.log(string.format("[shop] armor: char %d slot %d $%02X (%d) -> $%02X (%d), %d GP", ch, slot, cur,
            have, best, bs, price))
        end
      end
    end
  end) }
  for _, id in ipairs({ 0x98, 0x96, 0x97, 0x7E, 0x7F, 0x63 }) do
    steps[#steps + 1] = H.buyItem(id, function() return plan[id] or 0 end, string.format("armor $%02X", id))
  end
  return H.seqStep(steps)
end
-- ---- the grind before the Storm Dragon ---------------------------------------
-- The dragon at the levels the walk arrives with (CYAN L33, the others
-- L35-36) won 11 of 14 lab fights with 34 party deaths (route-wor-cyan.md
-- 5); level-curve.md puts its healthy level at 38-40.  So the party walks
-- Mt. Zozo's east face between the passage's door and the save point,
-- fighting what comes (field group 160) and cared for after each fight,
-- until its lowest member reaches GRIND_LEVEL; the lab's walk took 41
-- battles and no death for CYAN 33 -> 38.  GRIND_BATTLES bounds it.
local GRIND_LEVEL, GRIND_BATTLES = 38, 90
local function lowest()
  local m = 99
  for _, ch in ipairs(REGROUP) do m = math.min(m, level(ch)) end
  return m
end
local function grind()
  local wps, wp, n0, seen = { { 54, 16 }, { 40, 16 } }, 1, nil, nil
  return H.withReset(H.seqStep({
    H.call(function()
      n0, seen, wp = #H.outcomes, #H.outcomes, 1
      say("grind", string.format("to L%d for the lowest (now L%d)", GRIND_LEVEL, lowest()))
    end),
    H.driveUntil(function()
      while seen < #H.outcomes do
        seen = seen + 1
        local o = H.outcomes[seen]
        H.log(string.format("[grind] battle %d $%03X %s after %d ticks: %s", seen - n0, o.form & 0x1FF, o.kind,
          o.tick or -1, whereLine()))
      end
      if #H.outcomes - n0 >= GRIND_BATTLES then
        error(string.format("the grind: %d battles and the lowest member is L%d, short of L%d", #H.outcomes - n0,
          lowest(), GRIND_LEVEL))
      end
      return not H.battleLoadStarted() and settled() and lowest() >= GRIND_LEVEL
    end, 900000, {
      H.navTo(function() return wps[wp][1] end, function() return wps[wp][2] end,
        { maxFrames = 20000, playBattles = "tactical", fight = FIGHT, avoid = MZ_DOORS }),
      H.call(function() wp = wp % 2 + 1 end),
    }, "the grind on Mt. Zozo's east face"),
    H.call(function() say("grind", string.format("done after %d battles", #H.outcomes - n0)) end),
  }), function() n0, seen, wp = nil, nil, 1 end)
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

H.run({ maxFrames = 400000 }, {
  H.bootCheckpoint("wor-terra-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[wor] " .. kitLine())
  end),

  -- ---- 1. Maranda: Lola's letters ------------------------------------------
  flyIn(MARANDA_LANDING[1], MARANDA_LANDING[2], MARANDA_DOOR[1], MARANDA_DOOR[2], MAP_MARANDA, "Maranda"),
  -- the entrance walk is the upper level: east along it, up to the inn's
  -- landing, down the stair to the street, and north to Lola's door
  via({ { 14, 27 }, { 13, 23 }, { 9, 25 }, { 20, 17 }, { 26, 12 } }, "Maranda's street to Lola's door"),
  walkInto(26, 11, MAP_LOLA, "Maranda -> Lola's house (196)"),
  -- Lola (196 NPC_2, _cc3d73): her flowers and letters, and the envelope
  -- (NPC_3) comes out ($0294)
  talkTo(55, 51, "Lola (196 NPC_2)"),
  ride(function() return sw(0x0294) == 1 end, 6000, "Lola's flowers"),
  -- the envelope (NPC_3, _cc3e00): "Read the letter?" Yes; the letter, the
  -- party's reading of the hand ($0295), and Lola's "attach this reply to a
  -- carrier pigeon?" Yes ($0296, $01D7)
  talkTo(54, 50, "the letters (196 NPC_3)"),
  H.dialogChoice({ 0, 0 }, { inBattle = false, what = "Read the letter? Yes; the reply to the pigeon? Yes",
    tag = "Lola" }),
  ride(function() return sw(0x0296) == 1 end, 6000, "Lola's reply"),
  H.call(function()
    H.assertEq(sw(0x01D7), 1, "the reply is in hand for the pigeon ($01D7, _cc3deb)")
  end),
  walkInto(60, 62, MAP_MARANDA, "Lola's house -> Maranda"),
  -- the carrier pigeon (284 NPC_18, _cc3f12): the reply flies off ($0298:
  -- Zozo's merchant now tells of Mt. Zozo)
  talkTo(23, 9, "the carrier pigeon (284 NPC_18)"),
  ride(function() return sw(0x0298) == 1 and map() == MAP_MARANDA end, 12000, "the pigeon flies"),
  H.saveState("wor_cyan_maranda.mss"),

  -- ---- 2. Zozo: the Rust-Rid and the rusted door -----------------------------
  via({ { 20, 17 }, { 9, 25 }, { 13, 23 }, { 14, 27 }, { 11, 29 } }, "Maranda's street to the gate"),
  toFalcon(11, 31, "Maranda", MARANDA_WORLD),
  flyIn(ZOZO_LANDING[1], ZOZO_LANDING[2], ZOZO_DOOR[1], ZOZO_DOOR[2], MAP_ZOZO, "Zozo"),
  -- the merchant (221 NPC_3 at (43,29), _ca9513): with $0298 he tells of the
  -- path to Mt. Zozo and sells the Rust-Rid, 1000 GP ($01DB)
  walkTo(42, 30, "near the merchant", ZOZO_DOORS),
  talkTo(43, 29, "the merchant (221 NPC_3)"),
  H.dialogChoice(0, { inBattle = false, what = "the Rust-Rid for 1000 GP? Yes", tag = "Zozo" }),
  ride(function() return sw(0x01DB) == 1 end, 3000, "the Rust-Rid"),
  H.saveState("wor_cyan_rustrid.mss"),
  -- to the rusted door: the café building (44,48) -> 225, its stair to (21,15)
  -- -> the balcony 221 (49,39), the stair to the landing, the door (49,35)
  walkInto(44, 48, MAP_ZOZO_IN, "Zozo -> the café (225)", exceptOf(ZOZO_DOORS, 44, 48)),
  walkInto(21, 15, MAP_ZOZO, "the café -> the balcony (221 (49,39))", exceptOf(ZOZO_IN_DOORS, 21, 15)),
  climbStair(),
  walkTo(49, 36, "below the rusted door", ZOZO_DOORS),
  talkTo(49, 35, "the rusted door (221 NPC_8)"),
  ride(function() return sw(0x0356) == 0 end, 3000, "Rust dissolved"),
  walkInto(49, 31, MAP_MTZOZO, "Zozo -> Mt. Zozo (179)", exceptOf(ZOZO_DOORS, 49, 31)),
  H.saveState("wor_cyan_mtzozo_in.mss"),

  -- ---- 3. Mt. Zozo: the chests, and up to CYAN ------------------------------
  -- The west face (from the Zozo door): four chests, and map 177's Gold
  -- Hairpin through (11,10).  Map 176 is the passage to the east face
  -- (179 (18,5) -> 176 (35,15), 176 (8,11) -> 179 (55,16)); the east face
  -- holds the save point (40,15), the Storm Dragon's ledge (48,11) and the
  -- way on (51,40) -> 178 -> (22,10) -> the cliff 180.
  chestAt(19, 30, 0x0A2, "Red Cap (179 (19,30))", 0x78, MZ_DOORS),
  chestAt(11, 21, 0x0A3, "Ice Shld (179 (11,21))", 0x61, MZ_DOORS),
  chestAt(3, 51, 0x0A5, "Thunder Shld (179 (3,51))", 0x62, MZ_DOORS),
  chestAt(13, 16, 0x0A4, "Aegis Shld (179 (13,16))", 0x5E, MZ_DOORS),
  walkInto(11, 10, MAP_MTZOZO_W, "Mt. Zozo -> the west cave (177)", exceptOf(MZ_DOORS, 11, 10)),
  chestAt(9, 7, 0x0A6, "Gold Hairpin (177 (9,7))", 0xCD, { { 8, 5 } }),
  walkInto(8, 5, MAP_MTZOZO, "the west cave -> Mt. Zozo", {}),
  walkInto(18, 5, MAP_MTZOZO_N, "Mt. Zozo -> the passage (176)", exceptOf(MZ_DOORS, 18, 5)),
  walkInto(8, 11, MAP_MTZOZO, "the passage -> Mt. Zozo's east face", { { 9, 11 }, { 36, 15 } }),
  H.fieldCare({ tag = "Mt. Zozo's east face" }),
  walkInto(51, 40, MAP_MTZOZO_E, "Mt. Zozo -> the east cave (178)", exceptOf(MZ_DOORS, 51, 40)),
  walkInto(22, 10, MAP_CLIFF, "the east cave -> the cliff (180)", { { 9, 11 } }),
  H.saveState("wor_cyan_cliff.mss"),
  -- CYAN: the trigger by the flowers (180 (44,55), _cc3fa7) plays the scene
  -- in the cave (181) and joins him ($00D2; char_party only when the party
  -- has room, so with four he waits aboard)
  stepOn(44, 55, function() return sw(0x00D2) == 1 end),
  ride(function() return sw(0x00D2) == 1 and map() == MAP_CLIFF end, 30000, "CYAN joins"),
  H.call(function()
    say("wor", "CYAN joined")
    H.log(string.format("[wor] CYAN's record: %s; %s", member(CYAN, "CYAN"), kitLine()))
    H.assertEq(sw(0x00D2), 1, "CYAN joined ($00D2, _cc3fa7)")
  end),
  -- the key to his chest (181 NPC_4, shown once he joined: $0685) and the
  -- chest (180 NPC_10, _cc42bf with $0297)
  walkInto(44, 55, MAP_CAVE, "the cliff -> CYAN's cave (181)", { { 35, 56 } }),
  talkTo(9, 11, "the key's glint (181 NPC_4)"),
  ride(function() return sw(0x0297) == 1 end, 3000, "the key to CYAN's chest"),
  walkInto(15, 21, MAP_CLIFF, "CYAN's cave -> the cliff", {}),
  talkTo(42, 54, "CYAN's chest (180 NPC_10)"),
  ride(function() return sw(0x01D9) == 1 end, 6000, "CYAN's chest"),
  H.saveState("wor_cyan_joined.mss"),

  -- ---- 4. down to the Falcon ------------------------------------------------
  walkInto(35, 56, MAP_MTZOZO_E, "the cliff -> the east cave", { { 44, 55 } }),
  walkInto(9, 11, MAP_MTZOZO, "the east cave -> Mt. Zozo's east face", { { 22, 10 } }),
  walkInto(56, 16, MAP_MTZOZO_N, "the east face -> the passage", exceptOf(MZ_DOORS, 56, 16)),
  walkInto(36, 15, MAP_MTZOZO, "the passage -> the west face", { { 8, 11 }, { 9, 11 } }),
  walkInto(25, 30, MAP_ZOZO, "Mt. Zozo -> Zozo", exceptOf(MZ_DOORS, 25, 30)),
  walkTo(53, 36, "the landing above the stair", ZOZO_DOORS),
  descendStair(),
  walkInto(49, 38, MAP_ZOZO_IN, "the balcony -> the café (225)", exceptOf(ZOZO_DOORS, 49, 38)),
  walkInto(12, 44, MAP_ZOZO, "the café -> Zozo's street", exceptOf(ZOZO_IN_DOORS, 12, 44)),
  toFalcon(63, 44, "Zozo", ZOZO_WORLD),
  H.call(function() say("wor", "back at the Falcon") end),
  H.saveState("wor_cyan_down.mss"),

  -- ---- 5. CYAN into the party, dressed --------------------------------------
  regroup(),
  H.call(function() say("regroup", "CYAN in the party") end),
  -- he joins with nothing equipped: the bag's best he can wear, and a stone
  -- (Palidor, owned and worn by no one since the Solitary Island)
  dressFromBag(CYAN, "CYAN"),
  H.fieldCare({ tag = "after the regroup", threshold = H.CARE_BEFORE_FIGHTS }),
  H.dressRelics(REGROUP_MEMBERS, { tag = "relics with CYAN" }),
  H.equipEsper(function() return (H.readByte(0x1850 + CYAN) >> 3) & 3 end, PALIDOR, { tag = "PALIDOR -> CYAN" }),
  H.call(function()
    H.assertEq(H.readByte(c(CYAN, 0x1F)) ~= 0xFF, true, "CYAN holds a weapon")
    H.assertEq(H.readByte(c(CYAN, 0x22)) ~= 0xFF, true, "CYAN wears armor")
    H.assertEq(H.readByte(c(CYAN, 0x1E)), PALIDOR, "CYAN holds Palidor")
    say("regroup", "dressed: " .. kitLine())
  end),
  H.saveState("wor_cyan_regrouped.mss"),

  -- ---- 6. Jidoor: the item counter ------------------------------------------
  liftOff(),
  H.flyTo(JIDOOR_LANDING[1], JIDOOR_LANDING[2], { what = "the Falcon to Jidoor" }),
  H.worldNavTo(JIDOOR_DOOR[1], JIDOOR_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_JIDOOR and not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_JIDOOR and settled() end, 2400, "Jidoor: map 198", 1),
  H.crossDoor(27, 41, MAP_JIDOOR_SHOP, 34, 20, "Jidoor's item shop door 198 (27,41) -> 201", { fight = FIGHT }),
  H.shopTalk(34, 15, "Jidoor's item shop", { fight = FIGHT }),
  H.call(function() H.assertEq(H.shopId(), 78, "the counter opened shop 78 ($0201)") end),
  H.buyItem(POTION, function() return math.max(0, potionTarget() - H.invCountOf(POTION)) end,
    "POTION to the band and the field care"),
  H.buyItem(FENIX, function() return math.max(0, math.min(20, H.activeTopLevel()) - H.invCountOf(FENIX)) end,
    "FENIX DOWN to the level, capped at 20"),
  H.buyItem(REVIVIFY, function() return math.max(0, 3 - H.invCountOf(REVIVIFY)) end, "REVIVIFY to 3"),
  H.buyItem(TINCTURE, function() return math.max(0, math.ceil(H.activeTopLevel() / 4) - H.invCountOf(TINCTURE)) end,
    "TINCTURE to the level / 4"),
  H.shopClose("Jidoor's item shop"),
  H.bagArrange({ POTION, FENIX, TONIC, REMEDY }, { tag = "bag: combat items on top (Jidoor)" }),
  H.call(function()
    say("shop", "Jidoor")
    H.assertEq(H.invCountOf(POTION) >= potionTarget(), true, "Potions at the target leaving Jidoor")
  end),
  H.crossDoor(34, 21, MAP_JIDOOR, 27, 43, "Jidoor's item shop -> the street", { fight = FIGHT }),
  toFalconBy(16, 61, "down", "Jidoor", JIDOOR_WORLD),

  -- ---- 7. Maranda: Lola again, with CYAN; the armor counter -----------------
  flyIn(MARANDA_LANDING[1], MARANDA_LANDING[2], MARANDA_DOOR[1], MARANDA_DOOR[2], MAP_MARANDA, "Maranda"),
  via({ { 14, 27 }, { 13, 23 }, { 9, 25 } }, "Maranda's street"),
  -- the armor shop (284 (6,12) -> 290, the counter at (44,8), shop 81):
  -- the pieces that beat what each of the four wears
  enterUp(6, 12, MAP_MARANDA_ARMOR, "Maranda -> the armor shop (290)"),
  H.shopTalk(44, 8, "Maranda's armor shop", { fight = FIGHT }),
  H.call(function() H.assertEq(H.shopId(), 81, "the counter opened shop 81 ($0201)") end),
  armorBuys(),
  H.shopClose("Maranda's armor shop"),
  dressFromBag(CYAN, "CYAN"),
  dressFromBag(TERRA, "TERRA"),
  dressFromBag(CELES, "CELES"),
  dressFromBag(SABIN, "SABIN"),
  H.call(function() say("shop", "Maranda's armor: " .. kitLine()) end),
  walkInto(44, 14, MAP_MARANDA, "the armor shop -> Maranda"),
  via({ { 9, 25 }, { 20, 17 }, { 26, 12 } }, "Maranda's street to Lola's door"),
  walkInto(26, 11, MAP_LOLA, "Maranda -> Lola's house (196)"),
  -- Lola with CYAN (_cc3e45, $029C), and the letters he exchanges
  -- (_cc3eef, $029D)
  talkTo(55, 51, "Lola (196 NPC_2)"),
  ride(function() return sw(0x029C) == 1 end, 12000, "Lola meets CYAN"),
  talkTo(54, 50, "the letters (196 NPC_3)"),
  ride(function() return sw(0x029D) == 1 end, 6000, "CYAN exchanges the letters"),
  walkInto(60, 62, MAP_MARANDA, "Lola's house -> Maranda"),
  via({ { 20, 17 }, { 9, 25 }, { 13, 23 }, { 14, 27 }, { 11, 29 } }, "Maranda's street to the gate"),
  toFalcon(11, 31, "Maranda", MARANDA_WORLD),
  H.saveState("wor_cyan_lola.mss"),

  -- ---- 8. Mt. Zozo again, to its save point ---------------------------------
  flyIn(ZOZO_LANDING[1], ZOZO_LANDING[2], ZOZO_DOOR[1], ZOZO_DOOR[2], MAP_ZOZO, "Zozo"),
  walkInto(44, 48, MAP_ZOZO_IN, "Zozo -> the café (225)", exceptOf(ZOZO_DOORS, 44, 48)),
  walkInto(21, 15, MAP_ZOZO, "the café -> the balcony (221 (49,39))", exceptOf(ZOZO_IN_DOORS, 21, 15)),
  climbStair(),
  walkTo(49, 36, "below the open door", ZOZO_DOORS),
  walkInto(49, 31, MAP_MTZOZO, "Zozo -> Mt. Zozo (179)", exceptOf(ZOZO_DOORS, 49, 31)),
  walkInto(18, 5, MAP_MTZOZO_N, "Mt. Zozo -> the passage (176)", exceptOf(MZ_DOORS, 18, 5)),
  walkInto(8, 11, MAP_MTZOZO, "the passage -> Mt. Zozo's east face", { { 9, 11 }, { 36, 15 } }),
  grind(),
  walkTo(40, 16, "below the save point", MZ_DOORS),
  H.fieldCare({ tag = "at Mt. Zozo's save point", threshold = H.CARE_BEFORE_FIGHTS }),
  H.call(function()
    say("wor", "at Mt. Zozo's save point")
    H.log("[wor] " .. kitLine())
  end),
  H.saveState("wor_cyan_savept.mss"),
  H.saveAtCheckpoint("wor-mtzozo-v1"),
  H.saveState("wor_cyan.mss"),
  H.logStep(function()
    return string.format("wor_cyan generated: CYAN L%d, TERRA L%d, CELES L%d and SABIN L%d on Mt. Zozo's save point, "
      .. "map %d (%d,%d), saved in slot 3", level(CYAN), level(TERRA), level(CELES), level(SABIN), map(), H.fieldX(),
      H.fieldY())
  end),
})
