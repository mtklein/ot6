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
local links = H.doorLinks
-- Strago's house (map 349): the bedroom where Hidon's scene leaves the party and the hall, joined by two
-- doors (gen_wor_gau's)
local DOORS349 = { { 39, 10, 61, 20 }, { 60, 21, 38, 11 } }
local LINKS = { [MAP_HOUSE] = links(DOORS349) }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

-- the World of Ruin legs' helpers (lib/ot6_field.lua, H.worLegKit)
local K = H.worLegKit({ fight = FIGHT, links = LINKS, names = NAMES })
local map, sw, c, lv, settled = K.map, K.sw, K.c, K.lv, K.settled
local say, kitLine, outToWorld, board, watches = K.say, K.kitLine, K.outToWorld, K.board, K.watches
local walk, chestAt, landNear, talkNpc, objOn = K.walk, K.chestAt, K.landNear, K.talkNpc, K.objOn
local kohlingenStop = K.kohlingenStop

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
