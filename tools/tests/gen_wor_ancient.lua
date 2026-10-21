-- gen_wor_ancient.lua -- the Dreams arc's third leg (docs/design/route-wor-dreams.md): Continue the
-- `wor-doma-v1` battery (CELES, RELM, CYAN and TERRA beside the Falcon by Doma), the Falcon down by Figaro
-- Castle on the Kohlingen side, the engineer's ride stopped under the stratum ($00CD: _ca694f; "(Stop and
-- explore)"), the cave below basement 1 (401) to the Ancient Castle: the save point (402), the courtyard and
-- the flashback (407: $02DF), Odin (406), the queen's floor (408): the book, the queen (Odin -> Raiden) and the
-- Blue Dragon (event battle 137, a game over when lost: the runner retries from the leg's boot); back to the
-- castle, two rides (South Figaro, then Kohlingen again), out, and the save on the Falcon's tile: the
-- `wor-ancient-v1` battery, the next arc's boot.
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

-- ---- Kohlingen: the arc's counter ----
-- No town on the arc sells anything but Kohlingen, beside Figaro Castle's Kohlingen side: its general store
-- (189 (11,11) -> 194 (12,39); the item counter's keeper (19,35), shop 67) tops the bag up to the band (guidelines
-- "Supply band": Potions about level x 1.5 before a boss gauntlet and the field care's own, careStockPotions;
-- Fenix Downs about the level, capped at 20; Remedies for the dream's Petrify and Sap), and its weapon and armor
-- counters are the gear stop (H.gearStop, #434).  The town's south edge returns the party to the world.
local MAP_KOHLINGEN, MAP_KSTORE, KOHLINGEN_DOOR, SHOP_KITEMS = 189, 194, { 38, 45 }, 67
local function kohlingenStop(what)
  return H.seqStep({
    H.waitUntil(function() return H.airshipControl() end, 3000, what .. ": the pilot's controls", 5),
    landNear(KOHLINGEN_DOOR[1], KOHLINGEN_DOOR[2], what .. ": the Falcon down by Kohlingen"),
    H.worldNavTo(KOHLINGEN_DOOR[1], KOHLINGEN_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
      arrive = function() return not H.worldMode() end }),
    H.waitUntil(function() return map() == MAP_KOHLINGEN and settled() end, 2400, what .. ": Kohlingen, map 189", 1),
    H.gearStop({ tag = what .. ": gear Kohlingen", fight = FIGHT }),
    H.crossDoor(11, 11, MAP_KSTORE, 12, 39, what .. ": Kohlingen's store 189 (11,11) -> 194", { fight = FIGHT }),
    H.shopTalk(19, 35, what .. ": Kohlingen's item counter", { fight = FIGHT }),
    H.call(function() H.assertEq(H.shopId(), SHOP_KITEMS, "the counter opened shop 67 ($0201)") end),
    H.buyItem(POTION, function() return math.max(0, H.careStockPotions(H.activeTopLevel(), { spend = 30 })
      - H.invCountOf(POTION)) end, "POTION to the band"),
    H.buyItem(REMEDY, function() return math.max(0, 20 - H.invCountOf(REMEDY)) end, "REMEDY to 20"),
    H.buyItem(FENIX, function() return math.max(0, math.min(20, H.activeTopLevel()) - H.invCountOf(FENIX)) end,
      "FENIX DOWN to the level, capped at 20"),
    H.shopClose(what .. ": Kohlingen's item counter"),
    H.bagArrange({ POTION, FENIX, REMEDY, TINCTURE }, { tag = what .. ": bag: combat items on top" }),
    H.call(function() say("shop", what .. ": Kohlingen") end),
    walkInto(12, 40, MAP_KOHLINGEN, what .. ": the store -> Kohlingen"),
    H.navTo(23, 29, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
    outToWorld("down", what .. ": out of Kohlingen by the south edge"),
    board(),
  })
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
            H.waitUntil(function() return settled() end, 600, "control after the lever", 1),
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
local MAP_FCASTLE, MAP_FHALL, MAP_FB1 = 55, 59, 61
local MAP_ACAVE, MAP_ASAVE, MAP_AYARD, MAP_AHALL, MAP_AQUEEN = 401, 402, 407, 406, 408
local CASTLE_K = { 53, 58 }                 -- Figaro Castle on the Kohlingen side (_ca5f18)
local ODIN, RAIDEN = 11, 12                 -- the stones' indices (GenjuProp order)
local WALL_RING = 0xBB
local function owns(esper) return (H.readByte(0x1A69 + (esper >> 3)) >> (esper & 7)) & 1 == 1 end
local FOUR = { CELES, RELM, CYAN, TERRA }
-- 401's same-map doors (route_data.py map 401: its shorts and its two one-tile longs); 406's; 408's
-- (a long entrance covers its tile and `len` more, and every one of them lands on its one destination:
-- CheckLongEntrance, DoEntrance)
LINKS[MAP_ACAVE] = links({ { 43, 26, 43, 41 }, { 43, 39, 43, 25 }, { 50, 26, 50, 38 }, { 50, 36, 50, 25 },
  { 58, 26, 58, 38 }, { 58, 36, 58, 25 }, { 33, 41, 27, 6 }, { 33, 42, 27, 6 }, { 28, 6, 34, 41 }, { 28, 7, 34, 41 } })
LINKS[MAP_AHALL] = links({ { 15, 14, 24, 13 }, { 54, 28, 38, 9 }, { 45, 56, 35, 51 }, { 38, 7, 54, 27 },
  { 24, 12, 15, 13 }, { 9, 31, 33, 30 }, { 10, 31, 33, 30 }, { 11, 31, 33, 30 }, { 33, 31, 10, 32 },
  { 34, 31, 10, 32 } })
LINKS[MAP_AQUEEN] = links({ { 36, 52, 46, 57 }, { 45, 56, 35, 51 } })
-- a door onto another map, the walk playing its battles; arrives when the map reads dst
local function door(x, y, dst, what)
  return H.seqStep({
    walk(x, y, what, nil, function() return map() == dst end),
    H.waitUntil(function() return map() == dst and settled() end, 3000, what .. ": control on map " .. dst, 1),
    H.call(function() say("route", what) end),
  })
end
-- onto (x, y) from (x, y + 1), so the party faces up there, then A until done() (a step-on tile whose script
-- reads the facing and A, where the tile above can be walked into: H.faceAndHoldA refuses those)
local function upThenA(x, y, done, what)
  local ph = 0
  return H.seqStep({
    walk(x, y + 1, what .. ": below it"),
    H.driveUntil(function() return H.fieldY() == y and H.tileAligned() end, 300, { H.hold({ "up" }) }, what .. ": up onto it"),
    H.release(),
    H.withReset(H.driveUntil(done, 900, {
      H.call(function() ph = (ph + 1) % 8; H.setPad(ph < 4 and { "a" } or {}) end),
    }, what .. ": A"), function() ph = 0 end),
    H.release(),
    H.advanceStory(function() return settled() end, 3000, { playBattles = "tactical", fight = FIGHT }),
    H.call(function() say("story", what) end),
  })
end
-- the engineer (61 NPC_6 (6,33)) and a ride: the first prompt's row, then, under the stratum ($00CD), the
-- second's ("(Continue journey)" 0, "(Stop and explore)" 1, dlg $01DF)
local function ride(first, stratum, what)
  return H.seqStep({
    H.lazy(function()
      local o = objOn(6, 33)
      H.assertEq(o ~= nil, true, "the engineer stands at 61 (6,33)")
      return H.talkToObj(o, "the engineer (61 (6,33))")
    end),
    first and H.dialogChoice(first, { what = what .. ": the engineer's prompt, row " .. first, maxFrames = 3000 })
      or H.call(function() end),
    H.dialogChoice(stratum, { what = what .. ": the stratum's prompt (dlg $01DF), row " .. stratum, maxFrames = 6000 }),
    H.advanceStory(function() return map() == MAP_FB1 and settled() end, 12000, { playBattles = "tactical", fight = FIGHT }),
    H.call(function()
      say("castle", what)
      H.log(string.format("[castle] %s: $00DC=%d $0106=%d $026F=%d $02B7=%d $02B9=%d", what, sw(0x00DC), sw(0x0106),
        sw(0x026F), sw(0x02B7), sw(0x02B9)))
    end),
  })
end
-- the Wall Rings off for the Blue Dragon (the tower put them on CELES, RELM and TERRA: they turn the party's
-- own Cure and Shell away, route-wor-gogo.md section 4), each for the bag relic the relic rule ranks next
local wallOff = {}
local function wallRingsOff(tag)
  local steps = {}
  for _, ch in ipairs(FOUR) do
    steps[#steps + 1] = H.lazy(function()
      if H.readByte(c(ch, 0x24)) ~= WALL_RING then return H.call(function() end) end
      local pick = nil
      for _, id in ipairs({ 0xC1, 0xB7, 0xC3, 0xCA, 0xB2, 0xB1 }) do
        if pick == nil and H.invCountOf(id) > 0 and id ~= H.readByte(c(ch, 0x23)) then pick = id end
      end
      if pick == nil then return H.call(function() end) end
      wallOff[#wallOff + 1] = ch
      return H.equipKit(ch, { { 5, pick } }, { tag = NAMES[ch] .. ": the Wall Ring off " .. tag })
    end)
  end
  steps[#steps + 1] = H.call(function() H.log("[kit] relics " .. tag .. ": " .. kitLine(FOUR)) end)
  return H.seqStep(steps)
end
local function wallRingsBack(tag)
  return H.lazy(function()
    local steps = {}
    for _, ch in ipairs(wallOff) do
      steps[#steps + 1] = H.equipKit(ch, { { 5, WALL_RING } }, { tag = NAMES[ch] .. ": the Wall Ring back " .. tag })
    end
    steps[#steps + 1] = H.call(function() H.log("[kit] relics " .. tag .. ": " .. kitLine(FOUR)) end)
    return H.seqStep(steps)
  end)
end
-- the Blue Dragon (408 NPC_4, shown by $06A1, wandering: _cc205b on touch, event battle 137)
local function dragonObj()
  for o = 0x10, 0x14 do
    if H.objX(o) ~= 0 and H.objY(o) >= 45 and H.objX(o) >= 40 then return o end
  end
  return nil
end
-- walk to the wandering dragon and touch it (A, facing it, from a neighbouring tile) until its battle opens: each
-- aligned frame the way to a tile beside it is planned again from its live tile; when no tile beside it can be
-- reached (it stands in a nook), the party waits on the reachable tile nearest it until it steps out
local function touchDragon(o, maxFrames, what)
  local ph, said = 0, -1000
  return H.withReset(H.driveUntil(function() return H.battleLoadStarted() end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
      local ox, oy, px, py = H.objX(o), H.objY(o), H.fieldX(), H.fieldY()
      local dx, dy = ox - px, oy - py
      if H.frame - said >= 240 then
        said = H.frame
        H.log(string.format("[dragon] %s: f%d the dragon at (%d,%d), the party at (%d,%d)", what, H.frame, ox, oy, px, py))
      end
      if math.abs(dx) + math.abs(dy) == 1 then
        local dir = dx == 1 and "right" or dx == -1 and "left" or dy == 1 and "down" or "up"
        H.setPad(ph < 4 and { "a", dir } or { dir })
        return
      end
      local best
      for _, n in ipairs({ { ox, oy + 1 }, { ox - 1, oy }, { ox + 1, oy }, { ox, oy - 1 } }) do
        local p = H.bfsPath(n[1], n[2])
        if p and (best == nil or #p < #best) then best = p end
      end
      if best == nil then
        local reach, bt, bd = H.bfsReach(nil, nil, nil, {}), nil, 1e9
        for k in pairs(reach) do
          local x, y = k & 0xFF, k >> 8
          local d = math.abs(x - ox) + math.abs(y - oy)
          if d < bd then bt, bd = { x, y }, d end
        end
        if bt and not (bt[1] == px and bt[2] == py) then best = H.bfsPath(bt[1], bt[2]) end
      end
      if best and #best > 0 then H.setPad({ [H.movePress(best[1])] = true }) else H.setPad({}) end
    end),
  }, what), function() ph, said = 0, -1000 end)
end
H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-doma-v1"),
  watches(),
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine(FOUR))
  end),
  -- @@setup-end

  -- ---- 1. Figaro Castle: the ride stopped under the stratum ---------------------------------------------
  -- @@stage castle
  H.call(function()
    H.assertEq(sw(0x00DC), 1, "Figaro Castle stands on the Kohlingen side ($00DC)")
    H.assertEq(sw(0x0106), 0, "its engineer offers the ride to Figaro ($0106 clear: _ca68fd)")
    H.assertEq(sw(0x00CD), 1, "the stratum stops the ride ($00CD, set at the Falcon's return)")
  end),
  board(),
  -- Kohlingen beside the castle: the bag topped up for the Ancient Castle and its dragon
  kohlingenStop("the top-up before the Ancient Castle"),
  landNear(CASTLE_K[1], CASTLE_K[2], "the Falcon down by Figaro Castle"),
  H.worldNavTo(CASTLE_K[1], CASTLE_K[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_FCASTLE and settled() end, 2400, "Figaro Castle: map 55", 1),
  H.call(function() say("route", "Figaro Castle") end),
  -- the court's gate (28,38) reads impassable from below: the lib's door crossing (gen_wor_kohlingen's)
  H.crossDoor(28, 38, MAP_FHALL, -1, -1, "the court -> the lower hall", { fight = FIGHT }),
  H.release(),
  H.waitUntil(function() return map() == MAP_FHALL and settled() end, 3000, "the lower hall: map 59", 5),
  door(9, 49, MAP_FB1, "the lower hall -> basement 1's west room"),
  ride(0, 1, "the ride to Figaro, stopped under the stratum"),
  H.call(function() H.assertEq(sw(0x026F), 1, "the castle stands under the stratum ($026F)") end),
  -- the cave's mouth (35,40) opens when the map loads with $02B7 set (_caeaa2), and the stop loaded basement 1
  -- before it set the switch: up to the hall and down again
  door(11, 32, MAP_FHALL, "basement 1 -> the lower hall"),
  door(15, 49, MAP_FB1, "the lower hall -> basement 1's east side"),
  door(35, 35, MAP_ACAVE, "basement 1 (35,35) -> the cave (401)"),

  -- ---- 2. the cave and the castle's courtyard ----------------------------------------------------------------
  -- @@stage cave
  door(19, 16, MAP_ASAVE, "the cave (19,16) -> 402"),
  H.fieldCare({ tag = "at the Ancient Castle's save point" }),
  door(15, 41, MAP_AYARD, "402 (15,41) -> the courtyard (407)"),
  -- the flashback: (16,33) entered from below (_cc1a60: $02DF; the statue's Atom Edge, Odin's legend)
  walk(16, 34, "below the courtyard's statue (16,34)"),
  H.driveUntil(function() return not H.hasControl() or H.dialogWaiting() end, 600, { H.hold({ "up" }) }, "up onto (16,33)"),
  H.release(),
  H.advanceStory(function() return settled() and sw(0x02DF) == 1 end, 30000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("story", "the flashback ($02DF)") end),
  door(15, 10, MAP_AHALL, "407 (15,10) -> the castle (406)"),

  -- ---- 3. the castle: Odin, the queen's passage, the chests ---------------------------------------------------
  -- @@stage castle_in
  -- Odin's statue (406 (33,11), shown by $0696 after the flashback: _cc1ea5), faced up from (33,12)
  walk(33, 12, "below Odin's statue (33,12)"),
  H.faceAndHoldA("up", function() return owns(ODIN) or H.dialogWaiting() end, 900, "Odin's statue"),
  H.release(),
  H.advanceStory(function() return settled() and owns(ODIN) end, 6000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("story", "Odin") end),
  chestAt(55, 23, 0x0CB, "the Gold Hairpin (406 (55,23))", 0xCD),
  chestAt(53, 23, 0x0CA, "the Blizzard Orb (406 (53,23))", nil),
  -- "...when the queen stands and takes 5 steps": (34,14) faced up with A opens the queen's floor's east
  -- passage ($02DE: _cc1f8b, drawn at 408's load, _cc19fd)
  upThenA(34, 14, function() return sw(0x02DE) == 1 end, "the queen's passage (406 (34,14))"),
  door(42, 20, MAP_AQUEEN, "406 (42,20) -> the queen's floor (408)"),

  -- ---- 4. the queen's floor: the book, Raiden, the Blue Dragon --------------------------------------------------
  -- @@stage queen
  H.lazy(function()
    local o = objOn(28, 43)
    if o == nil then return H.call(function() end) end
    return talkNpc(o, function() return sw(0x06A0) == 0 end, "the queen's book (408 (28,43))")
  end),
  -- the dragon wanders the east room the queen stands in and fights when it touches the party (sweep sa: in 3 of
  -- 12 runs it met the party on the way to the queen), so the care for it comes before the east room
  wallRingsOff("for the Blue Dragon"),
  H.absorbSafeArms(nil, { 0x152 }, { tag = "arms for the Blue Dragon" }),
  H.bagArrange({ POTION, FENIX, 0xEA, 0xEE, 0xEC, REMEDY, TINCTURE }, { tag = "bag: the battle heals on top" }),
  H.fieldCare({ threshold = 1.0, tag = "before the Blue Dragon" }),
  H.call(function() H.log("[kit] " .. kitLine(FOUR)) end),
  H.saveState("wor_ancient_dragon.mss"),
  H.lazy(function()
    local o = objOn(52, 41)
    H.assertEq(o ~= nil, true, "the queen's statue stands at 408 (52,41)")
    return talkNpc(o, function() return owns(RAIDEN) end, "the queen's statue: Odin becomes Raiden")
  end),
  H.call(function()
    H.assertEq(owns(RAIDEN), true, "Raiden is the party's")
    H.assertEq(owns(ODIN), false, "Odin was traded in (take_genju ODIN)")
  end),
  H.cond(function() return sw(0x06A1) == 1 end, {
    H.lazy(function()
      local o = dragonObj()
      H.assertEq(o ~= nil, true, "the Blue Dragon wanders the queen's floor")
      return touchDragon(o, 12000, "the Blue Dragon")
    end),
  }, {
    H.call(function() H.log("[dragon] the Blue Dragon met the party on the way to the queen ($06A1 clear)") end),
  }),
  H.advanceStory(function() return settled() and sw(0x06A1) == 0 end, 300000, { playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("story", "the Blue Dragon beaten ($06A1 clear)") end),
  wallRingsBack("after the Blue Dragon"),
  H.fieldCare({ tag = "after the Blue Dragon" }),
  chestAt(34, 43, 0x0CC, "the X-Ether (408 (34,43))", nil),

  -- ---- 5. back to Figaro Castle, two rides, and the save ---------------------------------------------------------
  -- @@stage back
  door(25, 41, MAP_AHALL, "408 (25,41) -> the castle (406)"),
  walk(9, 47, "406 (9,47) -> the courtyard", nil, function() return map() == MAP_AYARD end),
  H.waitUntil(function() return map() == MAP_AYARD and settled() end, 3000, "the courtyard: map 407", 1),
  walk(15, 47, "407's south edge -> 402", nil, function() return map() == MAP_ASAVE end),
  H.waitUntil(function() return map() == MAP_ASAVE and settled() end, 3000, "402", 1),
  door(22, 42, MAP_ACAVE, "402 (22,42) -> the cave (401)"),
  door(42, 4, MAP_FB1, "the cave (42,4) -> basement 1"),
  -- the cave's mouth opens on basement 1's east side; the engineer stands in its west room, which the lower hall
  -- joins: 61 (27,31) -> 59 (14,48), 59 (9,49) -> 61 (10,33)
  door(27, 31, MAP_FHALL, "basement 1's east side -> the lower hall"),
  door(9, 49, MAP_FB1, "the lower hall -> basement 1's west room"),
  -- under the stratum the engineer asks at once; the ride on goes to South Figaro (_ca6969 -> _ca69ad), and
  -- the next ride, to Kohlingen, stops under it again and goes on to the Kohlingen side (_ca6931), where the
  -- Falcon waits
  ride(nil, 0, "on to South Figaro"),
  ride(0, 0, "back to Kohlingen"),
  H.call(function() H.assertEq(sw(0x00DC), 1, "the castle stands on the Kohlingen side again ($00DC)") end),
  door(11, 32, MAP_FHALL, "basement 1 -> the lower hall"),
  door(12, 50, MAP_FCASTLE, "the lower hall -> the court"),
  H.navTo(28, 42, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
  outToWorld("down", "out of Figaro Castle"),
  H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
    { maxFrames = 3000, playBattles = "tactical", fight = FIGHT, avoid = { { 53, 58 }, { 54, 58 } } }),
  H.fieldCare({ threshold = 1.0, tag = "on the Falcon's tile" }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled on the save tile", 5),
  H.call(function()
    say("wor", "on the save tile")
    H.log("[kit] " .. kitLine(FOUR))
  end),
  H.saveAtCheckpoint("wor-ancient-v1"),
  H.saveState("wor_ancient.mss"),
  H.logStep(function()
    return string.format("wor_ancient generated: CELES L%d, RELM L%d, CYAN L%d and TERRA L%d beside the Falcon by Figaro "
      .. "Castle, world (%d,%d), saved in slot 3", lv(CELES), lv(RELM), lv(CYAN), lv(TERRA), H.worldX(), H.worldY())
  end),
})
