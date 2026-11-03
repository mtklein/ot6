-- gen_wor_figaro_sweep.lua -- the Falcon arc's optional side leg, the
-- South Figaro continent's missed items (#322) and its desert (#321):
-- Continue the `wor-edgar-v1` battery (CELES, SABIN and EDGAR at world
-- (81,86), outside the surfaced Figaro Castle), walk the desert and the
-- plain to South Figaro, take the ruined town's chests, take the Hero Ring
-- through the Figaro cave's other door, walk back through the desert, and
-- save on the castle's tile again: the
-- `wor-figaro-sweep-v1` battery, the boot for the Kohlingen leg (the side
-- trip is on the chain: guidelines "Ribbons are worth going out of your way
-- for").  Generates wor_figaro_sweep.mss; its capture run (OT6_CAPTURE_SRM)
-- cuts `wor-figaro-sweep-v1`.  docs/design/route-wor-falcon.md has the plan
-- (section 2.2) and what this measured (section 10).
--
-- The route:
--   1. Field care at the boot (the checkpoint was saved hurt), then the
--      world walk to South Figaro's door (113,95): the castle's desert
--      (group 44) first, fought as it comes.
--   2. South Figaro (map 74): the Elixir at (2,43) and the six chests whose
--      World of Balance copies the route leaves closed for these prizes
--      (#350; tools/chests_opened.txt "keep closed in the WoB"): an
--      X-Potion, two Tents, a Remedy, a Revivify and a Fenix Down.  The
--      basement passage and its cellar (the Iron Armor, the Earrings, the
--      Ribbon, the Hyper Wrist, the RunningShoes, an X-Potion and an Ether)
--      were taken in the World of Balance, on LOCKE's escape
--      (gen_tunnelarmr, #350), so this leg asserts them open at the boot
--      and does not go back down.
--   3. Out of town by the west edge.
--   4. The Figaro cave (106,98): map 68's pieces by their links to the
--      piece of (4,4), its door -> 90 (41,13), the Hero Ring (52,14), and
--      back out to the world (the cave rolls groups 138 and 140, fought
--      as gen_wor_edgar fights them: CAVE_FIGHT).
--   5. The walk back to the castle's tile (81,86) through the desert, the
--      field care to full, and the real Save UI into slot 3 there
--      (H.saveAtCheckpoint "wor-figaro-sweep-v1").
-- The Hero Ring goes on the moment it is in the bag (guidelines "Relics
-- matter"): the party's relic slots are re-planned by the lib's relic rule
-- (H.dressRelics, lib/ot6_field.lua: the Ribbon to the party's caster, then
-- Haste, damage and vigor over plain guards) and dressed through the Relic
-- menu; the contract pins CELES's Ribbon.
-- Every battle's [outcome] is asserted said, judged on the battle's own end
-- reading, and paid as due; every battle's draw is logged as a [key] line
-- (the seed $be at InitBattle's store and the battle group $11E0) so a set
-- of runs can be counted by distinct battle key.  Nothing is written; every
-- step, menu and fight is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, SABIN, EDGAR = 6, 5, 4
local TONIC, POTION, FENIX, REMEDY, SOFT, TENT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4, 0xF7
local REVIVIFY, GREEN_CHERRY = 0xF1, 0xF8
local X_POTION, ETHER, ELIXIR = 0xEA, 0xEC, 0xEE
local IRON_ARMOR, EARRINGS, RUNNINGSHOES, HERO_RING, RIBBON, HYPER_WRIST = 0x87, 0xC3, 0xBA, 0xC9, 0xCA, 0xD2
local MAP_SF = 74
local MAP_CAVE, MAP_CAVE2 = 68, 90
local SF_DOOR, CAVE_DOOR = { 113, 95 }, { 106, 98 }
local SAVE_TILE = { 81, 86 }                        -- the castle's exit tile: the wor-figaro-sweep-v1 save
-- the world's doors kept off every plan but the one walked to
local DOORS = { { 113, 95 }, { 106, 98 }, { 81, 85 }, { 82, 85 } }
-- the chests this leg is for, by treasure bit (route_data.py map 74/90)
local CHESTS = {
  { 0x013, "Hero Ring" }, { 0x0E6, "Elixir" },
  { 0x015, "X-Potion" }, { 0x016, "Tent" }, { 0x017, "Remedy" }, { 0x018, "Revivify" }, { 0x019, "Tent" },
  { 0x0E7, "Fenix Down" },
}
-- the chests the World of Balance took on LOCKE's escape (gen_tunnelarmr,
-- #350): the passage's (map 87) and its cellar's (map 89), a hard input
local WOB_CHESTS = {
  { 0x020, "Iron Armor" }, { 0x021, "Earrings" },
  { 0x0FC, "Hyper Wrist" }, { 0x0FD, "X-Potion" }, { 0x0FE, "Ribbon" }, { 0x0FF, "Ether" },
  { 0x100, "RunningShoes" },
}
-- the cave's fights leave a Muddled ally to the monsters' hits rather than
-- a Genji pair's cure-hit (gen_wor_edgar CAVE_FIGHT; route-wor-edgar 12.5)
local CAVE_FIGHT = { unmuddle = false }

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function c(ch, off) return 0x1600 + 37 * ch + off end
local function level(ch) return H.readByte(c(ch or CELES, 8)) end
local function inParty(ch) return (H.readByte(0x1850 + ch) & 7) ~= 0 end
local function kit(ch)
  local t = {}
  for k = 0x1E, 0x24 do t[#t + 1] = string.format("%02X", H.readByte(c(ch, k))) end
  return table.concat(t, " ")
end
local MEMBERS = { { CELES, "CELES" }, { SABIN, "SABIN" }, { EDGAR, "EDGAR" } }
-- the statuses the arc's coming fights inflict, for the relic rule's
-- guards (lib/ot6_field.lua M.ARC_THREATS, shared by the arc's generators)
local ARC_THREATS = H.ARC_THREATS["wor-falcon"]
local function supplies()
  return string.format("tonic=%d potion=%d fenix=%d remedy=%d soft=%d revivify=%d greencherry=%d gil=%d",
    H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX), H.invCountOf(REMEDY),
    H.invCountOf(SOFT), H.invCountOf(REVIVIFY), H.invCountOf(GREEN_CHERRY), H.gil())
end
local function member(ch, name)
  return string.format("%s L%d HP %d/%d MP %d/%d status1 $%02X", name, level(ch), H.charHp(ch),
    H.charMaxHp(ch), H.charMp(ch), H.charMaxMp(ch), H.charStatus1(ch))
end
local function whereLine()
  local t = {}
  for _, p in ipairs(MEMBERS) do if inParty(p[1]) then t[#t + 1] = member(p[1], p[2]) end end
  return table.concat(t, "; ")
end
local function say(tag, what)
  H.log(string.format("[%s] f%d %s map %d (%d,%d): %s; %s", tag, H.frame, what, map(),
    H.fieldX(), H.fieldY(), whereLine(), supplies()))
end
local function taken()
  local t = {}
  for _, ch in ipairs(CHESTS) do
    t[#t + 1] = string.format("%s %s", ch[2], H.chestOpen(ch[1]) and "OPEN" or "closed")
  end
  return table.concat(t, ", ")
end

-- ---- the battles --------------------------------------------------------
-- Every battle the walkers fight ends in an [outcome]; each is asserted
-- judged on its own end reading and paid as due, and the count is asserted
-- against the runner's own battle count (gen_wor_kohlingen's shape).
local seen, tally, outcome0, battles0
local function tallyReset()
  tally = { won = 0, ["party left"] = 0, lost = 0, escaped = 0, forms = {}, order = {} }
  outcome0, battles0 = #H.outcomes, H.absorbGuardBattles
  seen = outcome0
end
tallyReset()
local function checkOutcomes(what)
  return H.call(function()
    for i = seen + 1, #H.outcomes do
      local o = H.outcomes[i]
      H.assertEq(o.atEnd, true, string.format("%s: battle %d ($%03X, %s) was judged on its own "
        .. "end reading (the UpdateSRAM hook), not the last per-frame one", what, i - outcome0,
        o.form & 0x1FF, o.kind))
      H.assertEq(o.ok, true, string.format("%s: battle %d ($%03X, %s) paid its reward as due",
        what, i - outcome0, o.form & 0x1FF, o.kind))
      tally[o.kind] = (tally[o.kind] or 0) + 1
      tally.escaped = tally.escaped + #o.escaped
      local k = string.format("$%03X", o.form & 0x1FF)
      if not tally.forms[k] then tally.order[#tally.order + 1] = k end
      tally.forms[k] = (tally.forms[k] or 0) + 1
    end
    H.assertEq(#H.outcomes - outcome0, H.absorbGuardBattles - battles0,
      string.format("%s: an [outcome] said for every battle fought (the runner's battle count)", what))
    if #H.outcomes > seen then
      seen = #H.outcomes
      H.log(string.format("[route] %s: %d battle(s) so far, %d [outcome] line(s) (%d won, %d the "
        .. "party left, %d monster escape(s)); %s; %s", what, H.absorbGuardBattles - battles0,
        seen - outcome0, tally.won, tally["party left"], tally.escaped, whereLine(), supplies()))
    end
  end)
end
-- Every battle's draw, at InitBattle's seed store (H.seedStoreAddr): the
-- seed $be and the battle group $11E0.  With the formation from the
-- battle's [outcome] it is the battle key docs/TESTING.md counts outcomes
-- by.  Registered once per run.
local keyWatchOn = false
local function keyWatch()
  return H.call(function()
    if keyWatchOn then return end
    keyWatchOn = true
    local addr = H.seedStoreAddr()
    emu.addMemoryCallback(function()
      local seed = emu.getState()["cpu.a"] & 0xff
      H.log(string.format("[key] battle key be%02X-g%04X f%d map %d", seed, H.readWord(0x11e0),
        H.frame, map()))
    end, emu.callbackType.exec, addr, addr)
  end)
end

local function control(what)
  return H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
  end, 3000, what, 5)
end
-- walk onto a door tile until the map changes (gen_wor_kohlingen's
-- walkInto: the arrival counts once the new map is lit and in control, and
-- a party carried on through a second door goes again, up to three times;
-- a door tile the map's BFS cannot step onto is crossed the lib's way)
local function walkInto(x, y, dst, what, avoid)
  local function there()
    return map() == dst and H.hasControl() and H.tileAligned() and bright() >= 15
  end
  return H.seqStep({
    H.repeatN(3, {
      H.cond(function() return not there() end, {
        H.cond(function() return H.bfsPath(x, y) ~= nil end, {
          H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = CAVE_FIGHT, avoid = avoid,
            arrive = function() return map() == dst end }),
        }, {
          H.crossDoor(x, y, dst, -1, -1, what, { fight = CAVE_FIGHT, avoid = avoid }),
        }),
        H.release(),
        H.waitUntil(function() return map() == dst end, 600, what .. ": onto map " .. dst, 5),
        H.waitUntil(function()
          return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
        end, 3000, what .. ": control", 5),
        H.call(function()
          if map() ~= dst then
            H.log(string.format("[route] %s: carried on to map %d (%d,%d); going again", what, map(),
              H.fieldX(), H.fieldY()))
          end
        end),
      }, {}),
    }),
    H.call(function()
      H.log(string.format("[route] %s: on map %d at (%d,%d)", what, map(), H.fieldX(), H.fieldY()))
      H.assertEq(map(), dst, what .. ": on map " .. dst)
    end),
  })
end
-- step onto a same-map link tile until `across` holds (the party has been
-- moved to the link's far side), fighting what comes on the way
local function crossLink(x, y, across, what, avoid)
  return H.seqStep({
    H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = CAVE_FIGHT, avoid = avoid,
      arrive = across }),
    H.release(),
    H.waitUntil(function() return across() and H.hasControl() and H.tileAligned() end, 900,
      what .. ": across", 5),
    H.call(function()
      H.log(string.format("[route] %s: at (%d,%d)", what, H.fieldX(), H.fieldY()))
    end),
  })
end
-- A chest: opened from whichever neighbour the party can reach where it
-- stands, else said and left (gen_wor_kohlingen's chest).  H.openChest is
-- idempotent on the treasure bit.
local function chest(x, y, bit, what, item)
  local steps = {}
  for _, d in ipairs({ { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" } }) do
    local sx, sy = x + d[1], y + d[2]
    steps[#steps + 1] = H.cond(function()
      return not H.chestOpen(bit) and H.bfsPath(sx, sy) ~= nil
    end, { H.openChest({ stand = { sx, sy }, face = d[3], bit = bit, what = what, item = item,
             nav = { fight = CAVE_FIGHT } }) }, {})
  end
  steps[#steps + 1] = H.call(function()
    if not H.chestOpen(bit) then
      H.log(string.format("[chest] %s (%d,%d) bit $%03X: no neighbour reachable from (%d,%d); left",
        what, x, y, bit, H.fieldX(), H.fieldY()))
    end
  end)
  return H.seqStep(steps)
end
-- a chest this leg is for: opened, and asserted
local function mustChest(x, y, bit, what, item)
  return H.seqStep({
    chest(x, y, bit, what, item),
    H.call(function()
      H.assertEq(H.chestOpen(bit), true, string.format("%s's chest is open (bit $%03X)", what, bit))
    end),
  })
end
-- out of a map by holding a direction until the World of Ruin map is
-- settled under the party (gen_wor_kohlingen's outToWorld)
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
    H.call(function()
      H.log(string.format("[wor] %s f%d: world %d (%d,%d); %s; %s", what, H.frame, H.worldId(),
        H.worldX(), H.worldY(), whereLine(), supplies()))
    end),
  })
end
-- a world walk to a door, the other doors kept off the plan, into map `dst`
local function worldInto(door, dst, what)
  return H.seqStep({
    H.worldNavTo(door[1], door[2], { maxFrames = 20000, playBattles = "tactical", avoid = DOORS,
      arrive = function() return not H.worldMode() end }),
    H.waitUntil(function() return map() == dst end, 2400, what .. ": map " .. dst, 5),
    control(what .. ": control"),
    H.call(function() say("route", what) end),
  })
end

H.run({ maxFrames = 200000 }, {
  -- ---- 0. Continue wor-edgar-v1 ----------------------------------------------------------
  H.bootCheckpoint("wor-edgar-v1"),
  keyWatch(),
  H.call(function()
    tallyReset()
    H.log(string.format("[wor] boot f%d: world %d (%d,%d), %s; kit CELES %s, SABIN %s, EDGAR %s; %s", H.frame,
      H.worldId(), H.worldX(), H.worldY(), whereLine(), kit(CELES), kit(SABIN), kit(EDGAR), supplies()))
    H.log("[sweep] at the boot: " .. taken())
    for _, ch in ipairs(WOB_CHESTS) do
      H.assertEq(H.chestOpen(ch[1]), true, string.format("the cellar's %s (bit $%03X) was taken in the World of "
        .. "Balance, on LOCKE's escape (gen_tunnelarmr)", ch[2], ch[1]))
    end
    for _, ch in ipairs(CHESTS) do
      H.assertEq(H.chestOpen(ch[1]), false, string.format("the %s's chest (bit $%03X) is still closed at the boot "
        .. "(the World of Balance keeps it closed: audit_chests 'keep closed in the WoB')", ch[2], ch[1]))
    end
  end),
  -- the checkpoint was saved hurt (EDGAR 948/1600 and SABIN 75/291 MP at
  -- the tracked save): the care before the walk
  H.fieldCare({ tag = "care at the boot", threshold = H.CARE_BEFORE_FIGHTS }),

  -- ---- 1. the desert and the plain to South Figaro --------------------------------------------
  worldInto(SF_DOOR, MAP_SF, "into South Figaro"),
  checkOutcomes("the walk to South Figaro"),
  H.fieldCare({ tag = "in South Figaro" }),

  -- ---- 2. South Figaro: the Elixir and the six the World of Balance left ---------------------
  -- each from a neighbour the map's BFS reaches from the west gate (1,28)
  -- (route_data.py field-path 74: (5,31)/(6,30), (13,28), (3,43), (14,45),
  -- (14,47), (32,17), and (11,24) the long way round, 120 steps)
  mustChest(6, 31, 0x018, "Revivify", REVIVIFY),
  mustChest(14, 28, 0x019, "Tent", TENT),
  mustChest(2, 43, 0x0E6, "Elixir", ELIXIR),
  mustChest(15, 45, 0x016, "Tent", TENT),
  mustChest(15, 47, 0x017, "Remedy", REMEDY),
  mustChest(32, 16, 0x015, "X-Potion", X_POTION),
  mustChest(11, 23, 0x0E7, "Fenix Down", FENIX),
  H.call(function() say("sweep", "South Figaro: " .. taken()) end),
  -- (the passage's pool is hunted on a branch from this capture, gen_wor_passage_hunt, #488)
  H.saveState("wor_figaro_sweep_town.mss"),
  checkOutcomes("South Figaro"),
  H.fieldCare({ tag = "after South Figaro's chests" }),

  -- out by the west edge (the long exit (0,0) len 47 -> the world)
  H.navTo(1, 28, { maxFrames = 6000, playBattles = "tactical" }),
  outToWorld("left", "out of South Figaro by the west edge"),

  -- ---- 4. the Figaro cave's other door: the Hero Ring -------------------------------------------
  worldInto(CAVE_DOOR, MAP_CAVE, "into the Figaro cave"),
  -- map 68 is three pieces joined by same-map links (gen_wor_edgar); the
  -- door (4,4) is in the third, with the turtle's door (10,2)
  crossLink(14, 33, function() return H.fieldX() > 40 end, "the cave: the link (14,33) -> (55,56)"),
  crossLink(61, 57, function() return H.fieldX() < 40 end, "the cave: the link (61,57) -> (17,21)"),
  walkInto(4, 4, MAP_CAVE2, "the cave: the other door (4,4) -> 90 (41,13)", { { 10, 2 } }),
  mustChest(52, 14, 0x013, "Hero Ring", HERO_RING),
  H.call(function() say("sweep", "the Hero Ring: " .. taken()) end),
  H.dressRelics(MEMBERS, { threats = ARC_THREATS, tag = "relics after the Hero Ring" }),
  walkInto(41, 14, MAP_CAVE, "map 90 -> the cave (68 (4,5))"),
  crossLink(17, 20, function() return H.fieldX() > 40 end, "the cave: the link (17,20) -> (61,56)",
    { { 10, 2 }, { 4, 4 } }),
  crossLink(55, 57, function() return H.fieldX() < 40 end, "the cave: the link (55,57) -> (14,34)"),
  H.navTo(16, 42, { maxFrames = 6000, playBattles = "tactical", fight = CAVE_FIGHT }),
  outToWorld("down", "out of the Figaro cave"),
  checkOutcomes("the cave"),
  H.fieldCare({ tag = "out of the cave" }),

  -- ---- 5. back through the desert to the castle's tile, and the save ----------------------------
  -- A step can roll an encounter that opens after the walker has arrived
  -- (gen_wor_nikeah's finding), so the party stands a moment and walks
  -- there again, fighting what came, and the care runs on the tile.
  H.worldNavTo(SAVE_TILE[1], SAVE_TILE[2], { maxFrames = 20000, playBattles = "tactical", avoid = DOORS }),
  H.waitFrames(90),
  H.worldNavTo(SAVE_TILE[1], SAVE_TILE[2], { maxFrames = 6000, playBattles = "tactical", avoid = DOORS }),
  H.fieldCare({ threshold = 1.0, tag = "on the save tile" }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled on the save tile", 5),
  checkOutcomes("the walk back"),
  H.call(function()
    for _, ch in ipairs(CHESTS) do
      H.assertEq(H.chestOpen(ch[1]), true, string.format("%s's chest is open (bit $%03X)", ch[2], ch[1]))
    end
    H.assertEq(H.chestOpen(0x09A), false, "the Regal Crown's chest is left for the Kohlingen leg (bit $09A)")
    -- the finds are worn, not carried: each one the rule placed is on
    local worn = {}
    for _, p in ipairs(MEMBERS) do
      worn[H.readByte(c(p[1], 0x23))] = p[2]
      worn[H.readByte(c(p[1], 0x24))] = p[2]
    end
    for _, r in ipairs({ { RIBBON, "the Ribbon" }, { HERO_RING, "the Hero Ring" }, { HYPER_WRIST, "the Hyper Wrist" },
                         { RUNNINGSHOES, "the RunningShoes" } }) do
      H.log(string.format("[sweep] %s ($%02X) is worn by %s", r[2], r[1], worn[r[1]] or "nobody (the bag)"))
    end
    H.assertEq(worn[RIBBON] ~= nil, true, "the Ribbon is worn, not carried")
  end),
  H.saveAtCheckpoint("wor-figaro-sweep-v1"),
  H.call(function()
    local forms = {}
    for _, k in ipairs(tally.order) do forms[#forms + 1] = string.format("%s x%d", k, tally.forms[k]) end
    H.log(string.format("[wor] the battles: %d (%s): %d won, %d the party left, %d monster escape(s)",
      seen - outcome0, table.concat(forms, ", "), tally.won, tally["party left"], tally.escaped))
    H.log(string.format("[wor] the stretch: %s; kit CELES %s, SABIN %s, EDGAR %s; %s", whereLine(),
      kit(CELES), kit(SABIN), kit(EDGAR), supplies()))
    H.log(string.format("[sweep] taken: %s; the bag: Ribbon %d, Hero Ring %d, Hyper Wrist %d, RunningShoes %d, "
      .. "Earrings %d, Iron Armor %d, X-Potion %d, Ether %d, Elixir %d", taken(), H.invCountOf(RIBBON),
      H.invCountOf(HERO_RING), H.invCountOf(HYPER_WRIST), H.invCountOf(RUNNINGSHOES), H.invCountOf(EARRINGS),
      H.invCountOf(IRON_ARMOR), H.invCountOf(X_POTION), H.invCountOf(ETHER), H.invCountOf(ELIXIR)))
    H.screenshot("wor_figaro_sweep")
  end),
  H.saveState("wor_figaro_sweep.mss"),
  H.logStep(function()
    return string.format("wor_figaro_sweep generated: CELES L%d, SABIN L%d and EDGAR L%d on the World of Ruin at (%d,%d), outside Figaro Castle, saved in slot 3",
      level(CELES), level(SABIN), level(EDGAR), H.worldX(), H.worldY())
  end),
})
