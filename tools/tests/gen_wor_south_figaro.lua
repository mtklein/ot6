-- gen_wor_south_figaro.lua -- the World of Ruin from Nikeah's door to the
-- world map outside South Figaro: cold-Continue the `wor-nikeah-v1` battery
-- (CELES and SABIN at world (148,76)), go into Nikeah, stock up, talk the
-- four thieves in the cafe into leaving, talk to Gerad in the street until
-- he gives up his act, board the thieves' ship to South Figaro, find Gerad
-- upstairs in South Figaro's inn, stock up again, and save on the world map
-- outside South Figaro: the `wor-south-figaro-v1` battery, the boot for the
-- Figaro cave, the castle and the Tentacles.  Generates
-- wor_south_figaro.mss, and its capture run (OT6_CAPTURE_SRM) cuts
-- `wor-south-figaro-v1`.  docs/design/route-wor-edgar.md has the plan
-- (sections 2.3, 2.4, 4.3, 7) and what this measured (section 11).
--
-- The story's gates, each asserted as it is passed:
--   the cafe's four thieves ($00A7-$00AA) -> "All right, let's go!" ($0376);
--   Gerad's three talks ($01F0-$01F3) -> $0378;
--   the ship's trigger (187 (17,4)) -> South Figaro's dock house (map 91),
--     $00AC, with the world tile outside South Figaro as the parent;
--   Gerad upstairs in the inn -> $037F (the thieves leave for the cave).
-- No random battles: every map here has them off (route-wor-edgar 2.3-2.4).
-- Nothing is written; every step, menu and talk is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, SABIN = 6, 5
local TONIC, POTION, FENIX, REMEDY, SOFT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4
local REVIVIFY, GREEN_CHERRY = 0xF1, 0xF8
local NIKEAH_DOOR = { 147, 76 }
local SAVE_TILE = { 113, 96 }                       -- where South Figaro's exit returns the party (measured)
local MAP_NIKEAH, MAP_NK_INN, MAP_CAFE, MAP_SHIP = 169, 171, 172, 187
local MAP_DOCK, MAP_SF, MAP_SF_INN, MAP_SF_ITEMS = 91, 74, 76, 85
local SHOP_NK_ITEMS, SHOP_SF_ITEMS, SHOP_SF_WEAPONS = 58, 63, 60
local MAP_SF_ARSENAL = 77
local ENHANCER, THUNDERBLADE = 0x13, 0x0F
-- objects: NPC_n is object 15 + n
local OBJ_THIEVES = { 19, 20, 21, 22 }              -- cafe NPC_4..NPC_7
local OBJ_GERAD = 26                                -- Nikeah NPC_11 (20,46)
local OBJ_SF_GERAD = 21                             -- South Figaro inn NPC_6 (88,11)
-- The supply band (guidelines "Supply band"; route-wor-edgar 4.3): no Tonic
-- seller, so Potions carry the combat band (level x 1.5) plus the field
-- care the legs to the next shop spend; Fenix Downs to about the level.
-- FIELD_CARE_POTIONS is the Tzen -> Nikeah walk's measured spend, rounded
-- up (build/attempts/wt/wor-edgar/leg1/: potion 47 -> 43, tonic 5 -> 4).
local FIELD_CARE_POTIONS = 6

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function c(ch, off) return 0x1600 + 37 * ch + off end
local function level(ch) return H.readByte(c(ch or CELES, 8)) end
local function topLevel() return math.max(level(CELES), level(SABIN)) end
local function kit(ch)
  local t = {}
  for k = 0x1E, 0x24 do t[#t + 1] = string.format("%02X", H.readByte(c(ch, k))) end
  return table.concat(t, " ")
end
local function supplies()
  return string.format("tonic=%d potion=%d fenix=%d remedy=%d soft=%d revivify=%d greencherry=%d gil=%d",
    H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX), H.invCountOf(REMEDY),
    H.invCountOf(SOFT), H.invCountOf(REVIVIFY), H.invCountOf(GREEN_CHERRY), H.gil())
end
local function member(ch, name)
  return string.format("%s L%d HP %d/%d MP %d/%d status1 $%02X", name, level(ch), H.charHp(ch),
    H.charMaxHp(ch), H.charMp(ch), H.charMaxMp(ch), H.charStatus1(ch))
end
local function whereLine() return member(CELES, "CELES") .. "; " .. member(SABIN, "SABIN") end
local function say(tag, what)
  H.log(string.format("[%s] f%d %s map %d (%d,%d): %s; %s", tag, H.frame, what, map(),
    H.fieldX(), H.fieldY(), whereLine(), supplies()))
end
local function whole(ch)
  return H.charHp(ch) == H.charMaxHp(ch) and H.charMp(ch) == H.charMaxMp(ch) and H.charStatus1(ch) == 0
end
local function potionBand() return math.ceil(topLevel() * 1.5) + FIELD_CARE_POTIONS end

-- hold a direction onto an exit until the map changes, paging any dialog
local function holdOut(dir, dst, what)
  local hb = 0
  return H.seqStep({
    H.driveUntil(function() return map() == dst end, 900, {
      H.call(function()
        hb = hb + 1
        if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
        H.setPad({ [dir] = true })
      end),
    }, what),
    H.release(),
    H.waitUntil(function()
      return map() == dst and H.hasControl() and H.tileAligned() and bright() >= 15
    end, 2400, what .. ": control", 5),
    H.waitFrames(20),
  })
end
local function settled(what)
  return H.advanceStory(function()
    return H.hasControl() and H.tileAligned() and not H.dialogWaiting() and bright() >= 15
  end, 6000, {})
end

-- an item counter: Potions to the band, Fenix Downs to the level, Remedies
-- to 5, the combat items on top
local function stock(shopId, what)
  local gil0 = 0
  return H.seqStep({
    H.call(function()
      gil0 = H.gil()
      H.assertEq(H.shopId(), shopId, string.format("the counter opened shop %d ($0201)", shopId))
    end),
    H.buyItem(POTION, function() return math.max(0, potionBand() - H.invCountOf(POTION)) end,
      "POTION to the band"),
    H.buyItem(REMEDY, function() return math.max(0, 5 - H.invCountOf(REMEDY)) end, "REMEDY to 5"),
    H.buyItem(FENIX, function() return math.max(0, topLevel() - H.invCountOf(FENIX)) end,
      "FENIX DOWN to the level"),
    H.call(function()
      H.log(string.format("[shop] %s: bought: %s (spent %d GP)", what, supplies(), gil0 - H.gil()))
      H.assertEq(H.invCountOf(POTION) >= potionBand(), true, "Potions at the band")
      H.assertEq(H.invCountOf(FENIX) >= topLevel(), true, "Fenix Downs at about the level")
    end),
    H.shopClose(what),
    H.bagArrange({ POTION, FENIX, REMEDY, SOFT, REVIVIFY, GREEN_CHERRY, TONIC },
      { tag = "bag: combat items on top (" .. what .. ")" }),
  })
end

H.run({ maxFrames = 120000 }, {
  -- ---- 0. cold Continue of wor-nikeah-v1 ----------------------------------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end, 3000,
    "cold Continue onto the World of Ruin outside Nikeah", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "cold Continue fade-in", 10),
  H.waitFrames(20),
  H.call(function()
    H.assertEntryContract("wor-nikeah-v1")
    H.log(string.format("[wor] boot f%d: world %d (%d,%d), %s; kit CELES %s, SABIN %s; %s", H.frame,
      H.worldId(), H.worldX(), H.worldY(), whereLine(), kit(CELES), kit(SABIN), supplies()))
  end),

  -- ---- 1. into Nikeah -----------------------------------------------------------------
  H.worldNavTo(NIKEAH_DOOR[1], NIKEAH_DOOR[2], { maxFrames = 3000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  H.waitUntil(function()
    return map() == MAP_NIKEAH and H.hasControl() and H.tileAligned() and bright() >= 15
  end, 2400, "Nikeah: control", 5),
  H.waitFrames(20),
  H.call(function() say("nikeah", "in town") end),

  -- ---- 2. the item seller, NPC_1 at (24,39) (shop 58) -----------------------------------
  H.shopTalk(24, 39, "Nikeah item seller"),
  stock(SHOP_NK_ITEMS, "Nikeah item seller"),

  -- ---- 3. the cafe's four thieves -----------------------------------------------------
  H.crossDoor(16, 54, MAP_CAFE, 26, 37, "Nikeah cafe door 169(16,54)->172(26,37)"),
  H.call(function() say("nikeah", "in the cafe") end),
  -- the four wander between the tables: H.chaseTalk re-plans the approach
  -- every aligned frame (no battles on this map)
  H.chaseTalk(OBJ_THIEVES[1], 6000, "the thief NPC_4 ($00A7)", { done = function() return sw(0x00A7) == 1 end }),
  settled("thief 1"),
  H.chaseTalk(OBJ_THIEVES[2], 6000, "the thief NPC_5 ($00A8)", { done = function() return sw(0x00A8) == 1 end }),
  settled("thief 2"),
  H.chaseTalk(OBJ_THIEVES[3], 6000, "the thief NPC_6 ($00A9)", { done = function() return sw(0x00A9) == 1 end }),
  settled("thief 3"),
  H.chaseTalk(OBJ_THIEVES[4], 6000, "the thief NPC_7 ($00AA)", { done = function() return sw(0x00AA) == 1 end }),
  settled("thief 4"),
  H.call(function()
    say("nikeah", "the thieves have talked")
    for i, s in ipairs({ 0x00A7, 0x00A8, 0x00A9, 0x00AA }) do
      H.assertEq(sw(s), 1, string.format("thief %d has talked ($%04X)", i, s))
    end
    H.assertEq(sw(0x0376), 1, "Gerad is in the street ($0376, _ca91b1)")
    H.assertEq(sw(0x0374), 0, "the thieves have left the cafe ($0374)")
  end),
  H.navTo(26, 37, { maxFrames = 3000, playBattles = "tactical" }),
  holdOut("down", MAP_NIKEAH, "the cafe's (26,38) exit -> Nikeah 169"),

  -- ---- 4. Gerad: three talks, the NPC walking off between them ---------------------------
  H.talkToObj(OBJ_GERAD, "Gerad (NPC_11), first talk"), settled("Gerad 1"),
  H.call(function() H.assertEq(sw(0x01F0), 1, "Gerad's first talk ($01F0)") end),
  H.waitUntil(function() return sw(0x01F1) == 1 end, 1200, "Gerad walks off ($01F1)", 5),
  H.talkToObj(OBJ_GERAD, "Gerad (NPC_11), second talk"), settled("Gerad 2"),
  H.call(function() H.assertEq(sw(0x01F2), 1, "Gerad's second talk ($01F2)") end),
  H.waitUntil(function() return sw(0x01F3) == 1 end, 1200, "Gerad walks off again ($01F3)", 5),
  H.talkToObj(OBJ_GERAD, "Gerad (NPC_11), third talk"),
  H.advanceStory(function()
    return sw(0x0378) == 1 and H.hasControl() and H.tileAligned() and not H.dialogWaiting()
  end, 6000, {}),
  H.call(function()
    say("nikeah", "Gerad gave up his act")
    H.assertEq(sw(0x0378), 1, "Gerad's act is over ($0378, _ca921a)")
    H.assertEq(sw(0x0376), 0, "Gerad has left the street ($0376)")
  end),

  -- ---- 5. the inn, when anyone is short (150 GP) ----------------------------------------
  H.cond(function()
    local s = not whole(CELES) or not whole(SABIN)
    if not s then H.log("[nikeah] the party is whole; no inn") end
    return s
  end, {
    H.crossDoor(19, 31, MAP_NK_INN, 44, 52, "Nikeah inn door 169(19,31)->171(44,52)"),
    H.innRest({ spot = { 46, 50 }, face = "up", price = 150, tag = "Nikeah inn" }),
    H.navTo(44, 52, { maxFrames = 6000, playBattles = "tactical" }),
    holdOut("down", MAP_NIKEAH, "the inn's (44,53) exit -> Nikeah 169"),
  }, {}),

  -- ---- 6. the ship ------------------------------------------------------------------
  H.navTo(13, 62, { maxFrames = 9000, playBattles = "tactical" }),
  holdOut("down", MAP_SHIP, "the dock (13,63) -> the ship 187"),
  H.call(function() say("ship", "aboard") end),
  H.navTo(17, 4, { maxFrames = 3000, playBattles = "tactical",
    arrive = function() return H.eventRunning() or map() ~= MAP_SHIP end }),
  H.advanceStory(function()
    return map() == MAP_DOCK and sw(0x00AC) == 1 and H.hasControl() and H.tileAligned()
      and not H.dialogWaiting() and bright() >= 15
  end, 20000, {}),
  H.call(function()
    say("sfigaro", "off the ship")
    H.assertEq(sw(0x00AC), 1, "the ship has sailed ($00AC, _ca9282)")
    H.assertEq(sw(0x037E), 1, "Gerad waits in South Figaro's inn ($037E)")
  end),

  -- ---- 7. South Figaro: Gerad upstairs in the inn -------------------------------------------
  H.navTo(8, 2, { maxFrames = 3000, playBattles = "tactical" }),
  holdOut("up", MAP_SF, "the dock house's (8,1) exit -> South Figaro 74"),
  H.call(function() say("sfigaro", "in town") end),
  H.crossDoor(15, 37, MAP_SF_INN, 52, 14, "South Figaro inn door 74(15,37)->76(52,14)"),
  -- the stairs are a same-map link, (48,3) -> (69,10)
  H.navTo(48, 3, { maxFrames = 3000, playBattles = "tactical",
    arrive = function() return H.fieldX() > 60 end }),
  H.release(),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 600, "upstairs", 5),
  H.talkToObj(OBJ_SF_GERAD, "Gerad upstairs (NPC_6)"),
  H.advanceStory(function()
    return sw(0x037F) == 1 and H.hasControl() and H.tileAligned() and not H.dialogWaiting()
  end, 6000, {}),
  H.call(function()
    say("sfigaro", "the thieves leave for the cave")
    H.assertEq(sw(0x037F), 1, "the thieves are bound for the cave ($037F, _ca808d)")
    H.assertEq(sw(0x0398), 1, "Siegfried waits at the cave's mouth ($0398)")
  end),
  H.navTo(70, 11, { maxFrames = 3000, playBattles = "tactical",
    arrive = function() return H.fieldX() < 60 end }),
  H.release(),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 600, "downstairs", 5),
  H.navTo(52, 14, { maxFrames = 3000, playBattles = "tactical" }),
  holdOut("down", MAP_SF, "the inn's (52,15) exit -> South Figaro 74"),

  -- ---- 8. the item shop (map 85, shop 63) ----------------------------------------------
  H.crossDoor(44, 30, MAP_SF_ITEMS, 104, 57, "South Figaro item shop door 74(44,30)->85(104,57)"),
  H.shopTalk(106, 52, "South Figaro item shop"),
  stock(SHOP_SF_ITEMS, "South Figaro item shop"),
  H.navTo(104, 57, { maxFrames = 3000, playBattles = "tactical" }),
  holdOut("down", MAP_SF, "the item shop's (104,58) exit -> South Figaro 74"),
  H.call(function() say("sfigaro", "stocked") end),

  -- ---- 8b. the arsenal (map 77, shop 60): the Enhancer for CELES --------------------
  -- 135 attack, no element, against the Blizzard's 108 ice: the upgrade
  -- the stretch's shops offer her.  It also keeps the bag's best sword for
  -- EDGAR non-elemental: the game dresses him from the bag (opt_equip,
  -- :15936) straight into the Tentacles, which absorb fire, ice and bolt
  -- between them (route-wor-edgar 6), and the Optimum takes the strongest
  -- blade left -- the Break Blade (117) once she wears the Enhancer, not
  -- the Blizzard or ThunderBlade (108) that one of the Tentacles drinks.
  H.crossDoor(29, 17, MAP_SF_ARSENAL, 103, 16, "South Figaro arsenal door 74(29,17)->77(103,16)"),
  H.shopTalk(103, 9, "South Figaro weapon shop"),
  H.call(function() H.assertEq(H.shopId(), SHOP_SF_WEAPONS, "the counter opened shop 60 ($0201)") end),
  H.buyItem(ENHANCER, function() return math.max(0, 1 - H.invCountOf(ENHANCER)) end, "ENHANCER for CELES"),
  H.shopClose("South Figaro weapon shop"),
  H.navTo(103, 16, { maxFrames = 3000, playBattles = "tactical" }),
  holdOut("down", MAP_SF, "the arsenal's (103,17) exit -> South Figaro 74"),
  H.equipKit(CELES, { { 0, ENHANCER } }, { tag = "CELES: the Enhancer in the right hand" }),
  H.call(function()
    say("sfigaro", "CELES wears the Enhancer, kit " .. kit(CELES))
    H.assertEq(H.readByte(c(CELES, 0x1F)), ENHANCER, "CELES's right hand holds the Enhancer")
    H.assertEq(H.readByte(c(CELES, 0x20)), THUNDERBLADE, "CELES's left hand keeps the ThunderBlade")
  end),

  -- ---- 9. out to the World of Ruin map, and the save ------------------------------------
  -- the west column (0,0) len 47 -> map 511: the parent map, which the ship
  -- set to world (113,95) (_ca92ca, set_parent_map 1, {113, 95}, UP)
  H.navTo(1, 28, { maxFrames = 6000, playBattles = "tactical" }),
  H.driveUntil(function() return H.worldMode() end, 3000, { H.hold({ "left" }) }, "out of South Figaro by the west edge"),
  H.release(),
  (function()
    local n = 0
    return H.withReset(H.waitUntil(function()
      local ok = H.worldSettled() and H.worldAligned() and H.worldPassable(H.worldX(), H.worldY())
      n = ok and n + 1 or 0
      return n >= 30
    end, 2400, "back on the World of Ruin map"), function() n = 0 end)
  end)(),
  H.call(function()
    H.log(string.format("[wor] out of South Figaro f%d: world %d (%d,%d); %s; %s", H.frame, H.worldId(),
      H.worldX(), H.worldY(), whereLine(), supplies()))
    H.assertEq(H.worldId() == 1 and H.worldX() == SAVE_TILE[1] and H.worldY() == SAVE_TILE[2], true,
      string.format("on the World of Ruin map at (%d,%d), outside South Figaro", SAVE_TILE[1], SAVE_TILE[2]))
  end),
  H.saveGame({ slot = 3, tag = "wor-south-figaro-v1 save" }),
  H.call(function()
    H.assertSavedSlotWorld(SAVE_TILE[1], SAVE_TILE[2], "wor-south-figaro-v1", 3, 1)
    H.assertExitContract("wor-south-figaro-v1")
    H.log(string.format("[wor] the stretch: no battles (Nikeah, the ship and South Figaro roll none); %s; kit CELES %s, SABIN %s; %s",
      whereLine(), kit(CELES), kit(SABIN), supplies()))
    H.screenshot("wor_south_figaro")
  end),
  H.saveState("wor_south_figaro.mss"),
  H.logStep(function()
    return string.format("wor_south_figaro generated: CELES L%d and SABIN L%d on the World of Ruin at (%d,%d), outside South Figaro, saved in slot 3",
      level(CELES), level(SABIN), H.worldX(), H.worldY())
  end),
})
