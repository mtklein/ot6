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
local links = H.doorLinks
-- Strago's house (map 349): the bedroom where Hidon's scene leaves the party and the hall, joined by two
-- doors (gen_wor_gau's)
local DOORS349 = { { 39, 10, 61, 20 }, { 60, 21, 38, 11 } }
local LINKS = { [MAP_HOUSE] = links(DOORS349) }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

-- the World of Ruin legs' helpers (lib/ot6_field.lua, H.worLegKit)
local K = H.worLegKit({ fight = FIGHT, links = LINKS, names = NAMES })
local map, bright, sw, lv, settled = K.map, K.bright, K.sw, K.lv, K.settled
local say, kitLine, walkInto, regroup, liftOff = K.say, K.kitLine, K.walkInto, K.regroup, K.liftOff
local watches, walk, chestAt, inParty, partyCount = K.watches, K.walk, K.chestAt, K.inParty, K.partyCount
local landNear, talkNpc, pressUp, objOn, kohlingenStop = K.landNear, K.talkNpc, K.pressUp, K.objOn, K.kohlingenStop

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
local WALL_RING = 0xBB
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
  -- Wall Rings for the dream and Doma (CELES, RELM and TERRA, the second relic slot): the Barb-e groups' Imp
  -- and their other spells rebound.  Without them (the tower took its rings off, #460) the party stalled on
  -- a lone Barb-e (formation $13D) in 7 of 24 runs of this leg and the next (build/attempts/wt/v036-route/lab/
  -- sd7_*, sdo7_*: 'timeout after 92000 frames', '[status] ... entity 1 char 8 is an IMP', every Fight
  -- 'took 0 off the monsters'), and with them the same four draws passed (rd_k1_s7, rd_k2_s7, rd_k5_s7,
  -- rdo_k1_s7).  The Ancient Castle's leg takes them off for the Blue Dragon (gen_wor_ancient)
  H.lazy(function()
    local steps = {}
    for _, ch in ipairs({ CELES, RELM, TERRA }) do
      if H.readByte(0x1600 + 37 * ch + 0x23) ~= WALL_RING and H.readByte(0x1600 + 37 * ch + 0x24) ~= WALL_RING
         and H.invCountOf(WALL_RING) > 0 then
        steps[#steps + 1] = H.equipKit(ch, { { 5, WALL_RING } }, { tag = NAMES[ch] .. ": a Wall Ring for the dream" })
      end
    end
    steps[#steps + 1] = H.call(function() end)
    return H.seqStep(steps)
  end),
  H.call(function() H.log("[kit] " .. kitLine(DREAM)) end),
  H.fieldCare({ threshold = 1.0, tag = "before Doma" }),
  liftOff(),
  -- the bag below the band (the Opera House's fights spent it): Kohlingen first
  kohlingenStop("the arc's counter"),
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
  -- (the car is dimmed while the doors stand open: control, not the screen's brightness, says the press is done)
  H.waitUntil(function() return H.hasControl() and H.tileAligned() and not H.dialogWaiting() end, 600,
    "control after the doors", 1),
  H.call(function() H.log(string.format("[doors] $01F9=%d $01FA=%d $01FB=%d $01FE=%d, brightness %d", sw(0x01F9),
    sw(0x01FA), sw(0x01FB), sw(0x01FE), bright())) end),
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
