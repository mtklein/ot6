-- gen_wor_dream.lua -- the Dreams arc's first leg (docs/design/route-wor-dreams.md): Continue the
-- `wor-opera-v1` battery (CELES, RELM, GOGO and STRAGO beside the Falcon by the Opera House), the cabin
-- (CYAN, CELES, RELM, TERRA), the Falcon down by Doma Castle, the King's room's bed (123 (4,12): CYAN's dream,
-- _cb82b1), the dreamscape (317: TERRA alone until the two stooges run and CELES and RELM rejoin; the three
-- Dream Stooges, event battle 90, a game over when lost: the runner retries from the leg's boot), the dream's
-- train (143: the last car 322, the scene at (88,8), the second car 144 and its Lump of Metal, Flame Shld and
-- Genji Glove, the first car 321's levers, panel and check), the engine (146) and the cave below it (320/319,
-- in Magitek armor), and the save point in the dream's Doma (126 (8,8)): the `wor-dream-v1` battery, the
-- boot for Wrexsoul.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local POTION, FENIX, REMEDY, TENT, TINCTURE, REVIVIFY = 0xE9, 0xF0, 0xF5, 0xF7, 0xEB, 0xF1
local MAP_DECK, MAP_CABIN, MAP_HOUSE, MAP_THAMASA, MAP_THAMASA_ITEMS = 11, 12, 349, 344, 347
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [CYAN] = "CYAN", [EDGAR] = "EDGAR", [SABIN] = "SABIN",
  [CELES] = "CELES", [STRAGO] = "STRAGO", [RELM] = "RELM", [SETZER] = "SETZER", [MOG] = "MOG", [GAU] = "GAU",
  [GOGO] = "GOGO", [UMARO] = "UMARO" }
local SHOP_ITEMS = 74
local function links(doors)
  local out = {}
  for _, d in ipairs(doors) do
    for _, dir in ipairs({ "up", "down", "left", "right" }) do out[#out + 1] = { d[1], d[2], dir, d[3], d[4] } end
  end
  return out
end
-- Strago's house (map 349): the bedroom where Hidon's scene leaves the party and the hall, joined by two
-- doors (gen_wor_gau's)
local DOORS349 = { { 39, 10, 61, 20 }, { 60, 21, 38, 11 } }
local LINKS = { [MAP_HOUSE] = links(DOORS349) }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function c(ch, off) return 0x1600 + 37 * ch + off end
local function lv(ch) return H.readByte(c(ch, 8)) end
local function partyOf(ch) return H.readByte(0x1850 + ch) & 7 end
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
local function kitLine(members)
  local t = {}
  for _, ch in ipairs(members) do
    local g = {}
    for k = 0x1E, 0x24 do g[#g + 1] = string.format("%02X", H.readByte(c(ch, k))) end
    t[#t + 1] = string.format("%s L%d kit %s", NAMES[ch], lv(ch), table.concat(g, " "))
  end
  return table.concat(t, "; ")
end
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
-- off a field map's edge onto the world map (gen_wor_locke's outToWorld)
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
-- onto a world door until its field map holds the screen
local function enterFrom(door, dst, what)
  return H.seqStep({
    H.worldNavTo(door[1], door[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
      arrive = function() return map() == dst and not H.worldMode() end }),
    H.waitUntil(function() return map() == dst and settled() end, 2400, what .. ": map " .. dst, 1),
    H.call(function() say("route", what) end),
  })
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
-- the cabin's waiting members (map 12) each ask "Change party members?"
-- (_caf59d); NPC_n is object $10 + n - 1, shown by its switch
-- (gen_wor_locke's regroup)
local CABIN_NPCS = { { "TERRA", 0x10, 0x0388 }, { "CYAN", 0x12, 0x038B }, { "SABIN", 0x15, 0x038D },
  { "CELES", 0x16, 0x038E }, { "STRAGO", 0x17, 0x038F }, { "RELM", 0x18, 0x0390 }, { "MOG", 0x1A, 0x0392 },
  { "UMARO", 0x1D, 0x0395 }, { "EDGAR", 0x14, 0x038C }, { "SETZER", 0x19, 0x0391 } }
local function regroup(members)
  local obj = nil
  local function pickTalker()
    obj = nil
    for _, n in ipairs(CABIN_NPCS) do
      local ox, oy = H.objX(n[2]), H.objY(n[2])
      local reach = H.bfsPath(ox, oy + 1) or H.bfsPath(ox - 1, oy) or H.bfsPath(ox + 1, oy) or H.bfsPath(ox, oy - 1)
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
    -- the waiting members wander: chaseTalk re-plans its approach every step and stops on the prompt
    H.lazy(function() return H.chaseTalk(obj[2], 6000, obj[1] .. " in the cabin") end),
    H.dialogChoice(1, { inBattle = false, what = "Change party members? Yes", tag = "the cabin" }),
    H.partySelect(members, { tag = "the Falcon's cabin" }),
    H.waitUntil(function() return map() == MAP_DECK and settled() end, 2400, "back on the deck after the menu", 5),
    H.call(function()
      local n = 0
      for ch = 0, 13 do if partyOf(ch) == 1 then n = n + 1 end end
      for _, ch in ipairs(members) do
        H.assertEq(partyOf(ch), 1, string.format("%s is in party 1 after the regroup", NAMES[ch]))
      end
      H.assertEq(n, #members, "party 1 holds exactly the regroup's members")
      say("regroup", "after the menu")
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
-- a walk over a map's floor and its doors
local function walk(x, y, what, avoid, arrive)
  return H.seqStep({
    H.lazy(function()
      return H.navLinks(x, y, LINKS[map()] or {}, { what = what, maxFrames = 12000, playBattles = "tactical",
        fight = FIGHT, avoid = avoid, arrive = arrive })
    end),
    H.call(function() say("route", what) end),
  })
end
-- a chest from whichever side of it the party can reach (gen_wor_ragnarok's)
local function chestAt(cx, cy, bit, what, item)
  return H.lazy(function()
    for _, o in ipairs({ { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }) do
      local legs = H.bfsReach(nil, nil, nil, LINKS[map()] or {}, cx + o[1], cy + o[2])
      if legs then
        return H.seqStep({
          walk(cx + o[1], cy + o[2], what .. ": beside it"),
          H.openChest({ stand = { cx + o[1], cy + o[2] }, face = o[3], bit = bit, what = what, item = item,
            nav = { fight = FIGHT } }),
        })
      end
    end
    error(string.format("[chest] %s (%d,%d): no side of it is reachable from (%d,%d)", what, cx, cy,
      H.fieldX(), H.fieldY()))
  end)
end
local function objLine(o0, o1)
  local t = {}
  for o = o0 or 0x10, o1 or 0x14 do t[#t + 1] = string.format("$%02X(%d,%d)", o, H.objX(o), H.objY(o)) end
  return table.concat(t, " ")
end
-- ---- the Dreams arc's helpers ----
local function inParty(ch) return partyOf(ch) == 1 end
local function partyCount()
  local n = 0
  for ch = 0, 13 do if partyOf(ch) == 1 then n = n + 1 end end
  return n
end
-- land the Falcon on the landable tile nearest (tx, ty) that a walk reaches it from (the world's own tile
-- properties: H.airshipCanLandAt, H.worldPassable, H.worldBfs), read once the pilot has the controls
local function landNear(tx, ty, what)
  return H.seqStep({
    H.waitUntil(function() return H.airshipControl() end, 3000, what .. ": the pilot's controls", 5),
    H.lazy(function()
      local best, bd = nil, 1e9
      for dy = -6, 6 do
        for dx = -6, 6 do
          local x, y = tx + dx, ty + dy
          if not (dx == 0 and dy == 0) and H.airshipCanLandAt(x, y) and H.worldPassable(x, y) then
            local d = dx * dx + dy * dy
            if d < bd and H.worldBfs(tx, ty, nil, x, y) then best, bd = { x, y }, d end
          end
        end
      end
      H.assertEq(best ~= nil, true, string.format("%s: a landable tile near (%d,%d) with a walk to it", what, tx, ty))
      H.log(string.format("[land] %s: landing on (%d,%d) for (%d,%d)", what, best[1], best[2], tx, ty))
      return H.flyTo(best[1], best[2], { what = what, fight = FIGHT })
    end),
  })
end
-- talk to object o from whichever side of it the party can reach, the walk playing its battles; done() ends it
local function talkNpc(o, done, what)
  return H.seqStep({
    H.lazy(function()
      local ox, oy = H.objX(o), H.objY(o)
      for _, s in ipairs({ { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }) do
        if H.bfsReach(nil, nil, nil, LINKS[map()] or {}, ox + s[1], oy + s[2]) then
          return H.seqStep({
            walk(ox + s[1], oy + s[2], what .. ": beside it"),
            H.faceAndHoldA(s[3], function() return done() or H.dialogWaiting() end, 900, what),
            H.release(),
          })
        end
      end
      error(string.format("[talk] %s: no side of obj $%02X (%d,%d) is reachable", what, o, ox, oy))
    end),
    H.advanceStory(function() return done() and settled() end, 6000, { playBattles = "tactical", fight = FIGHT }),
    H.call(function() say("story", what) end),
  })
end
-- stand on (x, y) and face up with A until done() (a step-on switch that reads the facing and the A button,
-- $01B0 and $01B4)
local function pressUp(x, y, done, what)
  return H.seqStep({
    H.cond(function() return not done() end, {
      walk(x, y, what .. ": onto (" .. x .. "," .. y .. ")"),
      H.faceAndHoldA("up", function() return done() end, 900, what),
      H.release(),
      H.advanceStory(function() return settled() end, 3000, { playBattles = "tactical", fight = FIGHT }),
    }, {}),
    H.call(function() say("story", what) end),
  })
end
-- the object standing on (x, y), or nil (an unshown object reads (0,0))
local function objOn(x, y)
  for o = 0x10, 0x3F do
    if H.objX(o) == x and H.objY(o) == y then return o end
  end
  return nil
end

-- ---- Doma and the dream's maps ----
local DOMA_DOOR = { 171, 75 }
local MAP_COURT, MAP_KING, MAP_SCAPE, MAP_TRAIN = 285, 123, 317, 143
local MAP_CAR1, MAP_CAR2, MAP_CAR3, MAP_ENGINE = 321, 144, 322, 146
local MAP_CAVE_A, MAP_CAVE_B, MAP_DREAM_DOMA = 320, 319, 126
-- 123's same-map doors (route_data.py map 123); 126, the dream's copy of it, has the same and two more
local DOORS123 = { { 4, 14, 42, 9 }, { 42, 7, 4, 13 }, { 25, 18, 10, 36 }, { 10, 34, 25, 17 }, { 40, 7, 56, 53 },
  { 56, 54, 40, 9 }, { 40, 12, 5, 45 }, { 5, 43, 40, 11 }, { 49, 12, 15, 45 }, { 15, 43, 49, 11 }, { 6, 24, 49, 27 },
  { 48, 28, 5, 25 } }
LINKS[MAP_KING] = links(DOORS123)
-- the dreamscape's same-map warps (route_data.py map 317, flags $21)
LINKS[MAP_SCAPE] = links({ { 11, 38, 24, 43 }, { 9, 44, 9, 50 }, { 3, 47, 5, 44 }, { 19, 39, 5, 44 }, { 12, 48, 15, 41 },
  { 13, 47, 18, 59 }, { 14, 48, 24, 43 }, { 23, 41, 25, 58 }, { 25, 57, 23, 42 }, { 25, 41, 27, 47 }, { 22, 46, 18, 59 },
  { 21, 58, 20, 54 }, { 8, 55, 46, 47 }, { 46, 46, 8, 56 } })
-- the dream (the party asleep in Doma's King's room, 123 (4,12): "Need a rest?", _cb827d -> _cb82b1): CYAN is
-- taken and the two members ahead of the last in the party's order are set down in the dreamscape (317) as
-- NPCs at (17,46) and (27,52) (_cb84ff/_cb854f, the top member each time); the last walks alone.  The order the
-- cabin leaves is CYAN, CELES, RELM, TERRA, so TERRA walks (L50, her Ultima at 3 BP and her Morph) and CELES
-- and RELM wait
local DREAM = { CYAN, CELES, RELM, TERRA }
-- the first car's levers (321: _cb8dc3, _cb8e1d, _cb8e7d toggle $0184-$0186, which move its walls) and its
-- panel: six switches (map switches $01F1-$01F6, cleared at every map load) that the check (9,5) wants at
-- 0 0 1 1 1 0 (_cb8ec1), the pattern the second car's lever shows (_cb911a, "Memorize the positions.")
local LEVERS = { { 22, 5, 0x0184 }, { 17, 5, 0x0185 }, { 14, 5, 0x0186 } }
local PANEL = { { 8, 7, 0x01F1, 0 }, { 9, 7, 0x01F2, 0 }, { 10, 7, 0x01F3, 1 }, { 8, 9, 0x01F4, 1 }, { 9, 9, 0x01F5, 1 },
  { 10, 9, 0x01F6, 0 } }
-- press reachable levers, one at a time and never the one just pressed, until the panel's check (9,5) is
-- reachable: each press is the walls the game moves, read again from the live map (a search over at most the
-- eight lever settings, each tried once from each)
local function leversToCheck()
  local tried, last, n = {}, nil, 0
  local function cfg() return string.format("%d%d%d", sw(0x0184), sw(0x0185), sw(0x0186)) end
  local function reach(x, y) return H.bfsReach(nil, nil, nil, {}, x, y) ~= nil end
  local function step()
    return H.lazy(function()
      if reach(9, 5) then return H.call(function() end) end
      for _, l in ipairs(LEVERS) do
        local k = cfg() .. ":" .. l[1]
        if not tried[k] and l ~= last and reach(l[1], l[2]) then
          tried[k], last, n = true, l, n + 1
          local v0 = sw(l[3])
          return H.seqStep({
            walk(l[1], l[2], "the first car's lever (" .. l[1] .. "," .. l[2] .. ")"),
            H.faceAndHoldA("up", function() return sw(l[3]) ~= v0 end, 900, "the lever (" .. l[1] .. "," .. l[2] .. ")"),
            H.release(),
            H.waitUntil(function() return settled() end, 600, "control after the lever", 20),
            H.call(function() H.log(string.format("[lever] pressed (%d,%d): levers now %s", l[1], l[2], cfg())) end),
          })
        end
      end
      return H.call(function() end)
    end)
  end
  local steps = {}
  for _ = 1, 10 do steps[#steps + 1] = step() end
  steps[#steps + 1] = H.call(function()
    H.assertEq(reach(9, 5), true, string.format("the first car's check (9,5) is reachable (levers %s after %d press(es))",
      cfg(), n))
  end)
  return H.seqStep(steps)
end
local function setPanel()
  local steps = {}
  for _, p in ipairs(PANEL) do
    steps[#steps + 1] = H.cond(function() return sw(p[3]) ~= p[4] end, {
      pressUp(p[1], p[2], function() return sw(p[3]) == p[4] end, "the panel's switch (" .. p[1] .. "," .. p[2] .. ")"),
    }, {})
  end
  steps[#steps + 1] = H.call(function()
    local t = {}
    for _, p in ipairs(PANEL) do
      t[#t + 1] = tostring(sw(p[3]))
      H.assertEq(sw(p[3]), p[4], string.format("the panel's switch $%04X", p[3]))
    end
    H.log("[panel] the six switches read " .. table.concat(t, " "))
  end)
  return H.seqStep(steps)
end
H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-opera-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine({ CELES, RELM, GOGO, STRAGO }))
  end),
  -- @@setup-end

  -- ---- 1. Doma Castle: the King's room's bed -------------------------------------------------------------
  -- @@stage doma
  -- the cabin: CYAN, CELES, RELM and TERRA, in that order (the dream sets the two ahead of the last down as
  -- NPCs and the last walks alone: DREAM above)
  regroup(DREAM),
  H.call(function()
    for i, ch in ipairs(DREAM) do
      H.assertEq((H.readByte(0x1850 + ch) >> 3) & 3, i - 1, string.format("%s is in battle order %d after the cabin",
        NAMES[ch], i - 1))
    end
  end),
  H.gearDress({ tag = "gear for Doma" }),
  H.dressRelics({ { CYAN, "CYAN" }, { CELES, "CELES" }, { RELM, "RELM" }, { TERRA, "TERRA" } },
    { tag = "relics for Doma" }),
  H.call(function() H.log("[kit] " .. kitLine(DREAM)) end),
  H.fieldCare({ threshold = 1.0, tag = "before Doma" }),
  liftOff(),
  landNear(DOMA_DOOR[1], DOMA_DOOR[2], "the Falcon down by Doma Castle"),
  H.call(function() say("wor", "down by Doma") end),
  H.worldNavTo(DOMA_DOOR[1], DOMA_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_COURT and settled() end, 2400, "Doma Castle's courtyard: map 285", 1),
  H.call(function() say("route", "Doma Castle") end),
  -- the courtyard's west door (28,31) -> 123 (10,49), and 123's doors to the King's room: (5,43) -> (40,11),
  -- (42,7) -> (4,13); the bed's trigger (4,12) is entered facing up (_cb827d: $01B0)
  walkInto(28, 31, MAP_KING, "285 (28,31) -> 123"),
  walk(4, 13, "below the King's room's bed (4,13)"),
  H.fieldCare({ threshold = 1.0, tag = "before the bed" }),
  H.driveUntil(function() return H.dialogWaiting() end, 600, { H.hold({ "up" }) }, "up onto the bed (4,12)"),
  H.release(),
  H.dialogChoice(0, { inBattle = false, what = "Need a rest? (Yes)", tag = "the bed" }),
  H.advanceStory(function() return map() == MAP_SCAPE and settled() end, 60000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function()
    say("story", "in the dream (317)")
    H.assertEq(inParty(CYAN), false, "CYAN is taken by the dream ($0523)")
    H.assertEq(partyCount(), 1, "one member walks the dreamscape")
  end),

  -- ---- 2. the dreamscape: the two members the stooges guard, and the three stooges -----------------------
  -- @@stage dreamscape
  -- the stooge by (17,46) runs from (15,43)/(19,43) (_cb8b83: "I'm not gonna mess with ya unless my brothers
  -- are here!", $0189), the one by (27,52) from (25,51)/(28,49) (_cb8b69: $018B); each member set down there
  -- rejoins when spoken to (_cb866f ..)
  walk(19, 43, "the first stooge's tile (19,43)"),
  H.advanceStory(function() return settled() and sw(0x0189) == 1 end, 3000, { playBattles = "tactical", fight = FIGHT }),
  H.lazy(function()
    local o, n0 = objOn(17, 46), partyCount()
    H.assertEq(o ~= nil, true, "a member waits at 317 (17,46)")
    return talkNpc(o, function() return partyCount() == n0 + 1 end, "the member at (17,46) rejoins")
  end),
  walk(25, 51, "the second stooge's tile (25,51)"),
  H.advanceStory(function() return settled() and sw(0x018B) == 1 end, 3000, { playBattles = "tactical", fight = FIGHT }),
  H.lazy(function()
    local o, n0 = objOn(27, 52), partyCount()
    H.assertEq(o ~= nil, true, "a member waits at 317 (27,52)")
    return talkNpc(o, function() return partyCount() == n0 + 1 end, "the member at (27,52) rejoins")
  end),
  H.call(function()
    for _, ch in ipairs({ CELES, RELM, TERRA }) do
      H.assertEq(inParty(ch), true, NAMES[ch] .. " walks the dreamscape")
    end
  end),
  -- the three at (46,55) (_cb8bd1: event battle 90, the Dream Stooges); a second step on the tile with
  -- $0179 set goes on into the dream's train (_cb8c59: 143 (107,8))
  walk(46, 56, "below the third stooge (46,56)"),
  H.absorbSafeArms(nil, { 0x11F, 0x120, 0x121 }, { tag = "arms for the stooges" }),
  H.fieldCare({ threshold = 1.0, tag = "before the stooges" }),
  H.call(function() H.log("[kit] " .. kitLine({ CELES, RELM, TERRA })) end),
  H.driveUntil(function() return H.dialogWaiting() or H.battleLoadStarted() end, 900, { H.hold({ "up" }) },
    "up onto (46,55)"),
  H.release(),
  H.advanceStory(function() return settled() and sw(0x0179) == 1 end, 300000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("story", "the stooges beaten ($0179)") end),
  H.fieldCare({ tag = "after the stooges" }),
  H.navTo(46, 56, { maxFrames = 600 }),
  H.driveUntil(function() return map() ~= MAP_SCAPE or H.dialogWaiting() end, 900, { H.hold({ "up" }) },
    "back onto (46,55)"),
  H.release(),
  H.advanceStory(function() return settled() and map() == MAP_TRAIN end, 6000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("story", "the dream's train (143)") end),

  -- ---- 3. the train: the last car, the second (its lump and its doors), the first (levers and panel) -----
  -- @@stage train
  walkInto(100, 8, MAP_CAR3, "143 (100,8) -> 322"),
  walkInto(1, 7, MAP_TRAIN, "322 (1,7) -> 143"),
  -- the scene at (88,8) (_cb9335: $0197), entered moving west
  H.navTo(89, 8, { maxFrames = 3000, playBattles = "tactical", fight = FIGHT }),
  H.driveUntil(function() return not H.hasControl() or H.dialogWaiting() end, 600, { H.hold({ "left" }) },
    "left onto (88,8)"),
  H.release(),
  H.advanceStory(function() return sw(0x0197) == 1 and settled() end, 12000, { playBattles = "tactical", fight = FIGHT }),
  walkInto(82, 8, MAP_CAR2, "143 (82,8) -> 144"),
  -- the second car: the Lump of Metal (3,6) ($01D6: _cb91b6) set in the middle slot (14,8) ($0187: _cb926c)
  -- lets the party past the blocks to the Flame Shld (14,5); its button (27,5) pressed twice (_cb9297, then
  -- _cb9300 while the first press's 240 frames run: $01FB) opens both doors by the Genji Glove (25,5).  The
  -- lever (9,5) shows the first car's pattern (_cb911a); the switches are map switches, so it is read, not
  -- carried
  pressUp(3, 6, function() return sw(0x01D6) == 1 end, "the Lump of Metal (3,6)"),
  pressUp(14, 8, function() return sw(0x0187) == 1 end, "the lump in the middle slot (14,8)"),
  chestAt(14, 5, 0x0BD, "the Flame Shld (14,5)", 0x60),
  walk(27, 5, "the second car's button (27,5)"),
  H.faceAndHoldA("up", function() return sw(0x01F9) == 1 end, 600, "the button (27,5), once"),
  H.release(),
  H.waitFrames(20),
  H.faceAndHoldA("up", function() return sw(0x01FB) == 1 end, 200, "the button (27,5), again"),
  H.release(),
  H.waitUntil(function() return settled() end, 600, "control after the doors", 20),
  chestAt(25, 5, 0x0BC, "the Genji Glove (25,5)", 0xD1),
  walkInto(1, 7, MAP_TRAIN, "144 (1,7) -> 143"),
  walkInto(65, 8, MAP_CAR1, "143 (65,8) -> 321"),
  leversToCheck(),
  setPanel(),
  pressUp(9, 5, function() return sw(0x017A) == 1 end, "the first car's check (9,5)"),
  walkInto(1, 7, MAP_TRAIN, "321 (1,7) -> 143"),
  -- (38,8) loads the engine (146 (8,12)); (8,13) below it is, in the World of Ruin, the cave (_cba808 ->
  -- _cb93bf: 320 (6,10), the party in Magitek armor)
  walkInto(38, 8, MAP_ENGINE, "143 (38,8) -> 146"),
  H.driveUntil(function() return map() ~= MAP_ENGINE or not H.hasControl() end, 600, { H.hold({ "down" }) },
    "down onto (8,13)"),
  H.release(),
  H.advanceStory(function() return settled() and map() == MAP_CAVE_A end, 20000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("story", "the dream's cave (320), in Magitek armor") end),

  -- ---- 4. the cave: Magitek armor (the MagiTek line, #373) ----------------------------------------------
  -- @@stage cave
  -- 320 (6,22) -> 319 (6,8); 319 (24,5) -> 320 (22,24) (_cb94a1); 320 (22,25) -> 319 (24,25), the Cyan scene
  -- (_cb94b2: $0184); and 319 (14,25), entered from (15,25), drops the party into the dream's Doma (_cb94e7:
  -- 126 (8,8), out of the armor)
  walkInto(6, 22, MAP_CAVE_B, "320 (6,22) -> 319"),
  walkInto(24, 5, MAP_CAVE_A, "319 (24,5) -> 320"),
  H.advanceStory(function() return settled() end, 3000, { playBattles = "tactical", fight = FIGHT }),
  walkInto(22, 25, MAP_CAVE_B, "320 (22,25) -> 319"),
  H.advanceStory(function() return settled() and sw(0x0184) == 1 end, 6000, { playBattles = "tactical", fight = FIGHT }),
  walk(15, 25, "beside the drop (15,25)"),
  H.driveUntil(function() return not H.hasControl() or map() ~= MAP_CAVE_B end, 600, { H.hold({ "left" }) },
    "left onto (14,25)"),
  H.release(),
  H.advanceStory(function() return settled() and map() == MAP_DREAM_DOMA end, 30000,
    { playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("story", "the dream's Doma (126)") end),

  -- ---- 5. the save point (126 (8,8), shown on the arrival: $0548) ----------------------------------------
  -- @@stage save
  H.fieldCare({ threshold = 1.0, tag = "at the dream's save point" }),
  H.call(function()
    say("wor", "at the save point")
    H.log("[kit] " .. kitLine({ CELES, RELM, TERRA }))
  end),
  H.saveAtCheckpoint("wor-dream-v1"),
  H.saveState("wor_dream.mss"),
  H.logStep(function()
    return string.format("wor_dream generated: CELES L%d, RELM L%d and TERRA L%d at the dream's save point, map %d "
      .. "(%d,%d), saved in slot 3", lv(CELES), lv(RELM), lv(TERRA), map(), H.fieldX(), H.fieldY())
  end),
})
