-- gen_wor_tzen_door.lua -- the World of Ruin from the raft landing to the
-- world map outside Tzen: cold-Continue the `wor-start-v1` battery (CELES
-- alone at (146,212), L25, Cid saved), dress her for a solo stretch on the
-- world map's menu, stop in Albrook, fight the plains north of it up to
-- TARGET_LEVEL, stop in Albrook again, walk to Tzen off its desert, and
-- save one step east of Tzen's door, (131,179): the last save before the
-- timed house (docs/design/route-wor-sabin.md section 7).  Generates
-- wor_tzen_door.mss, and its capture run (OT6_CAPTURE_SRM) cuts the
-- `wor-tzen-door-v1` battery.
--
-- The route (docs/design/route-wor-sabin.md has the plan and what was
-- measured):
--   1. The kit, on the world map at the landing: MADUIN (Fire/Ice/Bolt
--      while worn, +7 magic behind her Cure), the Genji Glove and a Jewel
--      Ring (the Osprey's Beak petrifies, and a statue is a lost fight for
--      a party of one), Blizzard (ice: the Mesosaur, the Osprey and the
--      Gigan Toad) and ThunderBlade (bolt: the Chitonid, whose authored
--      row is bludgeoning only) on the Glove.  Her row stays BACK: on the
--      same walk from the same landing the back row finished 14 battles in
--      41,439 frames with 3 Potions of field care against the front row's
--      49,791 and 6, since a boosted Fight still kills a plains body a turn
--      and she takes half as much (build/attempts/wt/wor-tzen-door/lab/).
--   2. Every random is fought (the walkers' tactical driver: boost-Fight,
--      the designed break keys, its heal policy) and field care follows
--      each; nothing flees.  The walk never steps on a tile whose pool
--      deals a species outside the plains six the kit was designed and
--      measured against (SOLO_OK): Tzen's desert (the Black Drgn, whose
--      BonePowder zombifies -- a lost fight alone) is avoided, and every
--      leg's pools are asserted from the ROM (H.worldPathGroups) before it
--      is walked.
--   3. Albrook first, the stretch's one Remedy seller and no Tonic
--      seller: the item shop tops up Potions (field care runs on them
--      here), Fenix Downs to about her level and Remedies (the Lunaris's
--      Face Bite blinds, the field care cures it with one, no shop on the
--      stretch sells Eye Drops, and she lands holding one), the bag is
--      arranged, and the inn is taken when anything is short.
--   4. Grind the plains north of Albrook to TARGET_LEVEL: Sabin joins at
--      max(26, CELES's level) (norm_lvl), and the house's bodies are L26.
--   5. Albrook again: the band at the new level, the inn if she is short.
--   6. Tzen: the walk off the desert, with Tzen's door itself in the
--      avoid set, to (131,179), and the real Save UI into slot 3.
-- Every battle's [outcome] (lib/ot6.lua M.battleOutcome: a Mesosaur that
-- escapes, a Chitonid that sneezes her out) is asserted paid as due.
-- Nothing is written; every step, menu and fight is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

-- Sabin joins at max(26, CELES's level) (norm_lvl, field/event.asm:857),
-- and the house's Scorpions, HermitCrabs and Pm Stalkers are L26: one
-- level over them, healthy rather than minimal (guidelines: "Fight, don't
-- flee"), and measured at seven to eight plains fights from the landing's
-- L25 (build/attempts/wt/wor-tzen-door/lab/lab_grind_back4.log: L27 at
-- the eighth; gen5.log: at the seventh).
local TARGET_LEVEL = 27
local CELES = 6
local MADUIN = 6                                    -- esper index (magicite $3C - $36)
local BLIZZARD, THUNDERBLADE = 0x0E, 0x0F
local GENJI, JEWEL_RING = 0xD1, 0xB5
local TONIC, POTION, FENIX, REMEDY, SOFT, TENT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4, 0xF7
local ALBROOK_DOOR = { 141, 209 }                   -- ShortEntrance map 1 -> 324 (2,17)
local ALBROOK_OTHER = { 140, 209 }
local TZEN_DOOR = { 130, 179 }                      -- ShortEntrance map 1 -> 305 (23,29)
local SAVE_TILE = { 131, 179 }                      -- one step east of the door, not sand
local MAP_ALBROOK, MAP_ITEMSHOP, MAP_INN = 324, 328, 325
local SHOP_ALBROOK_ITEMS = 48
-- the plains north of Albrook, zone (4,6): grass (group 31) and plain
-- (group 34) tiles between the landing and the (136,185) bend
local GRIND = { { 141, 203 }, { 141, 196 }, { 136, 200 }, { 144, 199 } }
-- The six plains species the kit and the authored break rows were designed
-- for (docs/design/route-wor-sabin.md section 8.3), and the only ones a
-- walk here may meet.
local SOLO_OK = { [0x021] = "Mesosaur", [0x031] = "Gilomantis", [0x07C] = "Chitonid",
                  [0x098] = "Gigan Toad", [0x0CA] = "Lunaris", [0x0E6] = "Osprey" }
-- the box the avoid set is read over: the continent from the landing to
-- Tzen with a margin (world_corridor.txt: x 124..151, y 174..216)
local BOX = { x0 = 118, y0 = 160, x1 = 159, y1 = 223 }
-- The supply stop (guidelines "Supply band"; docs/design/route-wor-sabin.md
-- section 5.4).  No shop on the stretch sells Tonics, so Potions carry
-- both lines: the combat band (level x 1.5) plus the field care the legs
-- to the next shop spend -- the walk to Tzen, whose own item counter sells
-- Potions again.  FIELD_CARE_POTIONS is the measured field spend of a
-- plains grind (lab_grind_back4.log: potion 39 -> 34 over 14 battles),
-- rounded up.  Fenix Downs to about the level.  Remedies: the field care
-- cures the Lunaris's Dark with one (no Eye Drop is sold here or at Tzen),
-- one a run at most in the labs (lab_grind_back4.log, lab_grind_ifrit.log:
-- `plan: cure dark char 6 with $F5`), and the landing's bag holds one; Sap
-- ends with the battle.
local FIELD_CARE_POTIONS = 6
local REMEDY_TARGET = 5

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function c(off) return 0x1600 + 37 * CELES + off end
local function level() return H.readByte(c(8)) end
local function xp() return H.readByte(c(0x11)) + H.readByte(c(0x12)) * 256 + H.readByte(c(0x13)) * 65536 end
local function kit()
  local t = {}
  for k = 0x1E, 0x24 do t[#t + 1] = string.format("%02X", H.readByte(c(k))) end
  return table.concat(t, " ")
end
local function isBack() return (H.readByte(0x1850 + CELES) & 0x20) ~= 0 end
local function supplies()
  return string.format("tonic=%d potion=%d fenix=%d remedy=%d soft=%d tent=%d gil=%d",
    H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX), H.invCountOf(REMEDY),
    H.invCountOf(SOFT), H.invCountOf(TENT), H.gil())
end
local function whereLine()
  return string.format("CELES L%d xp %d HP %d/%d MP %d/%d status1 $%02X",
    level(), xp(), H.charHp(CELES), H.charMaxHp(CELES), H.charMp(CELES), H.charMaxMp(CELES),
    H.charStatus1(CELES))
end
-- ItemProp +6: the STATUS1 bits an equipped item protects from
-- (tools/route_data.py `item`: "protects from ... (ItemProp+6/+7)")
local function protects1(item)
  if item == 0xFF then return 0 end
  return H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + item * 30 + 6)
end

-- ---- the pools ---------------------------------------------------------
-- A group's formations, decoded from the ROM (H.encounterPool): ok when
-- every species it can deal is one of SOLO_OK, else the first that is not.
local poolCache = {}
local function poolVerdict(g)
  if poolCache[g] == nil then
    local bad = nil
    if g == 0xFF then
      bad = { species = 0, form = 0 }               -- a Veldt sector: not a four-word pool
    else
      local pool = H.encounterPool(g)
      for slot = 1, 4 do
        for _, f in ipairs(pool[slot].formations) do
          for _, sp in ipairs(f.species) do
            if not SOLO_OK[sp] and bad == nil then bad = { species = sp, form = f.id } end
          end
        end
      end
    end
    poolCache[g] = bad or false
  end
  return poolCache[g] == false, poolCache[g] or nil
end

-- The avoid set: every tile in BOX whose own zone's pool deals a species
-- outside SOLO_OK (the desert beside Tzen's door, group 36: the Black
-- Drgn), plus the two towns' doors, which a walk to somewhere else must
-- not step on.  A goal tile is exempt (H.worldBfs).  Read off the live
-- tilemap and the ROM once the world map is settled.
local AVOID = nil
local function buildAvoid()
  local list, n, sp = {}, {}, {}
  for y = BOX.y0, BOX.y1 do
    for x = BOX.x0, BOX.x1 do
      local g = H.worldEncounterGroup(x, y, x, y)
      if g ~= nil then
        local ok, bad = poolVerdict(g)
        if not ok then
          list[#list + 1] = { x, y }
          n[g] = (n[g] or 0) + 1
          sp[g] = bad.species
        end
      end
    end
  end
  local parts = {}
  for g = 0, 255 do
    if n[g] then parts[#parts + 1] = string.format("group %d x%d (deals $%03X)", g, n[g], sp[g]) end
  end
  local tiles = #list
  for _, t in ipairs({ ALBROOK_DOOR, ALBROOK_OTHER, TZEN_DOOR }) do list[#list + 1] = t end
  AVOID = H.worldAvoidSet(list)
  H.log(string.format("[route] avoid set: %d tiles in (%d..%d, %d..%d) off the plains pools: %s; "
    .. "plus Albrook's doors (140/141,209) and Tzen's (130,179)", tiles, BOX.x0, BOX.x1, BOX.y0,
    BOX.y1, #parts > 0 and table.concat(parts, ", ") or "none"))
  H.assertEq(AVOID[(TZEN_DOOR[2] + 1) * 256 + TZEN_DOOR[1]] == true, true,
    "the sand south of Tzen's door (130,180) is in the avoid set (the Black Drgn's pool)")
end
local function avoid() return AVOID end

-- Every group a walk through `waypoints` can roll (H.worldPathGroups with
-- the avoid set, and the entry pairings of the saved position's zone),
-- asserted inside SOLO_OK before the walk: the any-encounter precondition
-- for this kit, from the ROM rather than from what one run meets.
local function assertLegPools(what, waypoints)
  local order, entry = H.worldPathGroups(waypoints, AVOID)
  local zx, zy = H.worldZonePos()
  H.log(string.format("[route] %s: the walk can roll groups {%s}; its first encounter also {%s} "
    .. "(the saved position (%d,%d)'s zone)", what, table.concat(order, ", "),
    table.concat(entry, ", "), zx, zy))
  for _, list in ipairs({ order, entry }) do
    for _, g in ipairs(list) do
      local ok, bad = poolVerdict(g)
      H.assertEq(ok, true, string.format("%s: group %d deals only the plains six (not $%03X, formation %d)",
        what, g, bad and bad.species or 0, bad and bad.form or 0))
    end
  end
end

-- ---- the battles --------------------------------------------------------
-- Every battle the walkers fight ends in an [outcome] (the driver's
-- M.battleOutcome); each one's reward is asserted paid as the engine's
-- own arithmetic says, which is what keeps an escaped Mesosaur or a
-- sneezed-out party from being counted as a kill or a win.
local seen, tally
local function tallyReset()
  seen, tally = 0, { won = 0, ["party left"] = 0, lost = 0, escaped = 0, forms = {}, order = {} }
end
tallyReset()
local function checkOutcomes(what)
  return H.call(function()
    for i = seen + 1, #H.outcomes do
      local o = H.outcomes[i]
      H.assertEq(o.ok, true, string.format("%s: battle %d ($%03X, %s) paid its reward as due",
        what, i, o.form & 0x1FF, o.kind))
      tally[o.kind] = (tally[o.kind] or 0) + 1
      tally.escaped = tally.escaped + #o.escaped
      local k = string.format("$%03X", o.form & 0x1FF)
      if not tally.forms[k] then tally.order[#tally.order + 1] = k end
      tally.forms[k] = (tally.forms[k] or 0) + 1
    end
    if #H.outcomes > seen then
      seen = #H.outcomes
      H.log(string.format("[route] %s: %d battle(s) so far (%d won, %d the party left, %d monster escape(s)); %s; %s",
        what, seen, tally.won, tally["party left"], tally.escaped, whereLine(), supplies()))
    end
  end)
end

-- ---- the grind ------------------------------------------------------------
-- Leg after leg between the GRIND waypoints until CELES reaches
-- TARGET_LEVEL.  The level is read only between legs, never mid-walk, so
-- the battle that crosses it still gets its field care.
local wpi, grindDone, legs = 1, false, 0
local function grind()
  return H.withReset(H.driveUntil(function() return grindDone end, 500000, {
    H.worldNavTo(function() return GRIND[wpi][1] end, function() return GRIND[wpi][2] end,
      { maxFrames = 20000, playBattles = "tactical", avoid = avoid }),
    H.call(function()
      legs = legs + 1
      wpi = wpi % #GRIND + 1
      grindDone = level() >= TARGET_LEVEL
    end),
    checkOutcomes("the grind"),
  }, "the grind to L" .. TARGET_LEVEL), function() wpi, grindDone, legs = 1, false, 0 end)
end

-- hold a direction onto an exit trigger until the map changes, paging any
-- dialog on the way (the shop's and the inn's way out)
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

-- The world map back and READY after a town exit, held for 30 frames: world
-- control, aligned, the screen lit, and the tile the party stands on
-- walkable on foot.  H.worldSettled alone passes too early here: measured
-- leaving Albrook (build/attempts/wt/wor-tzen-door/lab/lab_exit2.log), the
-- map word turns to the world while the town fades out, the fade reads
-- brightness 15 for one frame (exit+16, f4165), and the world's tilemap
-- lands in $7F0000 only at exit+86 -- until then (141,208), where she
-- stands, reads the town's byte $96 (impassable) and a plan through it
-- finds "no world path from (141,208) to (141,203)".
local function worldReady(what)
  local n = 0
  return H.withReset(H.waitUntil(function()
    local ok = H.worldSettled() and H.worldAligned() and H.worldPassable(H.worldX(), H.worldY())
    n = ok and n + 1 or 0
    return n >= 30
  end, 2400, what), function() n = 0 end)
end

-- ---- Albrook ---------------------------------------------------------------
-- A stop in town from wherever the party stands on the world map: in by
-- the door (141,209), the item shop topped up to the band at the level she
-- has now, the bag arranged, a night at the inn when anything is short,
-- and out by the west edge to the parent map (world (141,208), measured).
-- `after` runs on the world map once she is back out.
local shopGil0, fenixBefore, fenix0, fenixBought = 0, 0, 0, 0
local function albrookStop(what, after)
  return H.seqStep({
    H.worldNavTo(ALBROOK_DOOR[1], ALBROOK_DOOR[2], { maxFrames = 20000, playBattles = "tactical",
      avoid = avoid, arrive = function() return not H.worldMode() end }),
    checkOutcomes("the walk to Albrook (" .. what .. ")"),
    H.waitUntil(function()
      return map() == MAP_ALBROOK and H.hasControl() and H.tileAligned() and bright() >= 15
    end, 2400, "Albrook: control", 5),
    H.waitFrames(20),
    H.call(function()
      H.log(string.format("[albrook] %s: in town f%d at (%d,%d): %s; %s", what, H.frame, H.fieldX(), H.fieldY(),
        whereLine(), supplies()))
      H.assertEq(map(), MAP_ALBROOK, "the World of Ruin's Albrook (map 324)")
    end),
    -- the item shop: door (7,13) -> 328 (37,54), keeper (37,47), shop 48
    -- while $00A4 is set (_cc60ba); out by the (37,55) trigger
    H.crossDoor(7, 13, MAP_ITEMSHOP, 37, 54, "Albrook item shop door 324(7,13)->328(37,54)"),
    H.shopTalk(37, 47, "Albrook item shop"),
    H.call(function()
      shopGil0, fenixBefore = H.gil(), H.invCountOf(FENIX)
      H.assertEq(H.shopId(), SHOP_ALBROOK_ITEMS, "the counter opened shop 48 ($0201)")
      H.log(string.format("[albrook] %s: shop open: %s; targets potion %d (L%d x1.5 + %d field care), fenix %d, remedy %d",
        what, supplies(), math.ceil(level() * 1.5) + FIELD_CARE_POTIONS, level(), FIELD_CARE_POTIONS, level(),
        REMEDY_TARGET))
    end),
    H.buyItem(POTION, function()
      return math.max(0, math.ceil(level() * 1.5) + FIELD_CARE_POTIONS - H.invCountOf(POTION))
    end, "POTION to the band"),
    H.buyItem(REMEDY, function() return math.max(0, REMEDY_TARGET - H.invCountOf(REMEDY)) end,
      "REMEDY to " .. REMEDY_TARGET),
    H.buyItem(FENIX, function() return math.max(0, level() - H.invCountOf(FENIX)) end,
      "FENIX DOWN to the level"),
    H.call(function()
      fenixBought = fenixBought + H.invCountOf(FENIX) - fenixBefore
      H.log(string.format("[albrook] %s: bought: %s (spent %d GP)", what, supplies(), shopGil0 - H.gil()))
      H.assertEq(H.invCountOf(POTION) >= math.ceil(level() * 1.5) + FIELD_CARE_POTIONS, true,
        "Potions at the band (level x 1.5 + the measured field care)")
      H.assertEq(H.invCountOf(FENIX) >= level(), true, "Fenix Downs at about the level")
      H.assertEq(H.invCountOf(REMEDY) >= REMEDY_TARGET, true, "Remedies at " .. REMEDY_TARGET)
    end),
    H.shopClose("Albrook item shop"),
    H.bagArrange({ POTION, FENIX, REMEDY, SOFT, TONIC }, { tag = "bag: combat items on top (Albrook)" }),
    H.navTo(37, 54, { maxFrames = 6000, playBattles = "tactical" }),
    holdOut("down", MAP_ALBROOK, "the item shop's (37,55) trigger -> Albrook 324"),
    -- the inn, 300 GP: door (54,12) -> 325 (58,56), keeper (56,51) behind the
    -- counter, talk spot (56,53) facing up; out by the (58,57) trigger.  A
    -- night when anything is short (HP, MP, a status the care left).
    H.cond(function()
      local short = H.charHp(CELES) < H.charMaxHp(CELES) or H.charMp(CELES) < H.charMaxMp(CELES)
        or H.charStatus1(CELES) ~= 0
      if not short then H.log("[albrook] " .. what .. ": CELES is whole; no night at the inn") end
      return short
    end, {
      H.crossDoor(54, 12, MAP_INN, 58, 56, "Albrook inn door 324(54,12)->325(58,56)"),
      H.innRest({ spot = { 56, 53 }, face = "up", price = 300, tag = "Albrook inn" }),
      H.navTo(58, 56, { maxFrames = 6000, playBattles = "tactical" }),
      holdOut("down", MAP_ALBROOK, "the inn's (58,57) trigger -> Albrook 324"),
    }, {}),
    -- out of town: 324's west column and north rows are long exits to the
    -- parent map (map 511 -> where the party came in, world (141,209))
    H.navTo(1, 17, { maxFrames = 12000, playBattles = "tactical" }),
    (function()
      local hb = 0
      return H.driveUntil(function() return H.worldMode() end, 3000, {
        H.call(function()
          hb = hb + 1
          if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
          H.setPad(hb % 240 < 120 and { left = true } or { up = true })
        end),
      }, "out of Albrook to the World of Ruin")
    end)(),
    H.release(),
    worldReady("back on the World of Ruin map"),
    H.call(function()
      H.log(string.format("[albrook] %s: left town f%d: world %d (%d,%d); %s; %s", what, H.frame, H.worldId(),
        H.worldX(), H.worldY(), whereLine(), supplies()))
      H.assertEq(H.worldId(), 1, "back on the World of Ruin map")
      if after then after() end
    end),
  })
end

H.run({ maxFrames = 600000 }, {
  -- ---- 0. cold Continue of wor-start-v1 -------------------------------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end, 3000,
    "cold Continue onto the World of Ruin at the raft's landing", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "cold Continue fade-in", 10),
  H.waitFrames(20),
  H.call(function()
    H.assertEntryContract("wor-start-v1")
    tallyReset()
    fenix0, fenixBought = H.invCountOf(FENIX), 0
    H.log(string.format("[wor] boot f%d: world %d (%d,%d), %s, row %s, esper+kit %s; %s",
      H.frame, H.worldId(), H.worldX(), H.worldY(), whereLine(), isBack() and "back" or "front",
      kit(), supplies()))
  end),

  -- ---- 1. the kit, on the world map ------------------------------------------
  -- Row BACK (measured, above; she arrives there, so this is a no-op then),
  -- MADUIN, the relics (Genji Glove kept, the Jewel Ring for the Czarina
  -- Ring), then the blades: ThunderBlade into the left hand first, so the
  -- Blizzard it displaces is in the bag for the right.  Leaving the Relic
  -- screen with the Genji Glove worn runs the game's own Optimum on the
  -- hands (lab_kit.log: `after=11 0F ...`), which the blade session then
  -- corrects to the pair this stretch wants.
  H.setRows({ [CELES] = true }, { tag = "CELES row" }),
  H.equipEsper(function() return (H.readByte(0x1850 + CELES) >> 3) & 3 end, MADUIN,
    { tag = "MADUIN -> CELES" }),
  H.equipKit(CELES, { { 4, GENJI }, { 5, JEWEL_RING } }, { tag = "CELES relics" }),
  H.equipKit(CELES, { { 1, THUNDERBLADE }, { 0, BLIZZARD } }, { tag = "CELES blades" }),
  H.waitUntil(function() return H.worldHasControl() and H.worldAligned() and bright() >= 15 end,
    1200, "the world map back after the kit", 5),
  H.call(function()
    local r, l = H.readByte(c(0x1F)), H.readByte(c(0x20))
    local prot = protects1(H.readByte(c(0x23))) | protects1(H.readByte(c(0x24)))
    H.log(string.format("[wor] kit: esper+kit %s, row %s; hands %02X (element %s) + %02X (element %s); "
      .. "relics protect STATUS1 $%02X", kit(), isBack() and "back" or "front", r,
      H.elemStr(H.weaponElement(r)), l, H.elemStr(H.weaponElement(l)), prot))
    H.assertEq(isBack(), true, "CELES stands in the back row")
    H.assertEq(H.readByte(c(0x1E)), MADUIN, "CELES wears MADUIN")
    H.assertEq(H.readByte(c(0x23)) == GENJI or H.readByte(c(0x24)) == GENJI, true,
      "CELES wears the Genji Glove")
    H.assertEq(prot & 0x40, 0x40, "a relic CELES wears protects her from Petrify (the Osprey's Beak)")
    H.assertEq((H.weaponElement(r) | H.weaponElement(l)) & 0x04, 0x04,
      "a blade in CELES's hands carries bolt (the Chitonid's key)")
    H.assertEq((H.weaponElement(r) | H.weaponElement(l)) & 0x02, 0x02,
      "a blade in CELES's hands carries ice")
  end),

  -- ---- 2. the pools the walk may meet -------------------------------------------
  H.waitUntil(function() return H.worldSettled() end, 600, "the world map settled", 5),
  H.call(function()
    buildAvoid()
    assertLegPools("the landing -> Albrook", { { H.worldX(), H.worldY() }, ALBROOK_DOOR })
    assertLegPools("the grind's last leg -> Albrook", { GRIND[#GRIND], ALBROOK_DOOR })
  end),

  -- ---- 3. Albrook first: the Remedies (the Lunaris blinds, and the landing's
  -- one Remedy is one Dark), Potions and Fenix Downs at the band ---------------
  albrookStop("before the grind", function()
    local g = { { H.worldX(), H.worldY() } }
    for _, t in ipairs(GRIND) do g[#g + 1] = t end
    g[#g + 1] = GRIND[1]
    assertLegPools("the grind (Albrook -> the four waypoints, round)", g)
  end),

  -- ---- 4. the grind -------------------------------------------------------------
  H.cond(function() return level() < TARGET_LEVEL end, { grind() }, {
    H.logStep(function() return string.format("[wor] CELES is already L%d: no grind", level()) end),
  }),
  H.call(function()
    H.log(string.format("[wor] grind done f%d after %d legs: %s; %s", H.frame, legs, whereLine(), supplies()))
    H.assertEq(level() >= TARGET_LEVEL, true, "CELES reached L" .. TARGET_LEVEL)
  end),

  -- ---- 5. Albrook again: the band at the new level, the inn -------------------
  albrookStop("after the grind", function()
    assertLegPools("Albrook -> Tzen's door", { { H.worldX(), H.worldY() }, SAVE_TILE })
  end),

  -- ---- 6. Tzen ----------------------------------------------------------------------
  H.worldNavTo(SAVE_TILE[1], SAVE_TILE[2], { maxFrames = 20000, playBattles = "tactical",
    avoid = avoid }),
  checkOutcomes("the walk to Tzen"),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "at Tzen's door", 5),
  H.call(function()
    H.log(string.format("[tzen] at the door f%d: world %d (%d,%d); %s; %s", H.frame, H.worldId(),
      H.worldX(), H.worldY(), whereLine(), supplies()))
    H.assertEq(H.worldMode() and H.worldId() == 1, true, "on the World of Ruin map, not in Tzen")
    H.assertEq(H.worldX() == SAVE_TILE[1] and H.worldY() == SAVE_TILE[2], true,
      "one step east of Tzen's door (131,179)")
    H.assertEq(AVOID[SAVE_TILE[2] * 256 + SAVE_TILE[1]] == nil, true, "the save tile is off the sand")
  end),

  -- ---- 7. the save --------------------------------------------------------------------
  H.saveGame({ slot = 3, tag = "wor-tzen-door-v1 save" }),
  H.call(function()
    H.assertSavedSlotWorld(SAVE_TILE[1], SAVE_TILE[2], "wor-tzen-door-v1", 3, 1)
    H.assertExitContract("wor-tzen-door-v1")
    local forms = {}
    for _, k in ipairs(tally.order) do forms[#forms + 1] = string.format("%s x%d", k, tally.forms[k]) end
    H.log(string.format("[wor] the stretch: %d battles (%s): %d won, %d the party left, %d monster "
      .. "escape(s); Fenix Downs held and bought %d, left %d; %s; %s", seen, table.concat(forms, ", "), tally.won,
      tally["party left"], tally.escaped, fenix0 + fenixBought, H.invCountOf(FENIX), whereLine(),
      supplies()))
    H.screenshot("wor_tzen_door")
  end),
  H.saveState("wor_tzen_door.mss"),
  H.logStep(function()
    return string.format("wor_tzen_door generated: CELES L%d on the World of Ruin at (%d,%d), one step east of Tzen's door, saved in slot 3",
      level(), H.worldX(), H.worldY())
  end),
})
