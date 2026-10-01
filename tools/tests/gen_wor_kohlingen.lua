-- gen_wor_kohlingen.lua -- the World of Ruin from Figaro Castle to SETZER:
-- Continue the `wor-edgar-v1` battery (CELES, SABIN and EDGAR at world
-- (81,86), outside the surfaced castle), ride the castle to Kohlingen,
-- walk into town, take SETZER at the inn, dress him, and save on the world
-- map outside Kohlingen: the `wor-kohlingen-v1` battery, the boot for the
-- walk to Darill's Tomb.  Generates wor_kohlingen.mss; its capture run
-- (OT6_CAPTURE_SRM) cuts `wor-kohlingen-v1`.  docs/design/route-wor-falcon.md
-- has the plan (sections 2.3-2.4, 4.4, 7) and what this measured (section
-- 11).
--
-- The route:
--   1. Field care at the boot (the checkpoint was saved hurt), and into the
--      castle from its world tile (81,85).
--   2. Down to basement 1's west room by the court's stairs and the lower
--      hall, and the Regal Crown (#322) off basement 2: 61 (2,37) -> 62,
--      62 (4,6) -> 66, the chest (3,53), and back.  Basement 2 rolls the
--      cave's Muddle pool (group 137), fought as gen_wor_edgar fights it
--      (CAVE_FIGHT).  The crown goes on whichever of EDGAR and SABIN (the
--      two who can wear it) it improves most, by defense plus magic
--      defense read from the ROM.
--   3. The engineer (61 NPC_6 at (6,33)): "(Go to Kohlingen?)", row 0; the
--      castle burrows and comes up by Kohlingen ($00DC=1, $0106=0).
--   4. Out of the castle and the walk to Kohlingen's door (38,45), fought
--      as it comes; the castle's own trigger tiles are kept off the plan.
--   5. Kohlingen: the town's two chests (Green Beret, Elixir), the inn
--      (200 GP) when anyone is short, SETZER at the inn (he joins: $00CA).
--   6. SETZER joins with nothing on and no Esper; the game does not dress
--      him (no opt_equip), so the party does, from the bag and the town's
--      shops (dressSetzer below), and stocks the item counter (stock below).
--   7. Out by the town's south edge, the field care, and the real Save UI
--      into slot 3 on the world tile the exit returns the party to
--      (H.saveAtCheckpoint "wor-kohlingen-v1").
-- Every battle's [outcome] is asserted said, judged on the battle's own end
-- reading, and paid as due; every battle's draw is logged as a [key] line
-- (the seed $be at InitBattle's store and the battle group $11E0) so a set
-- of runs can be counted by distinct battle key.  Nothing is written; every
-- step, menu and fight is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, SABIN, EDGAR, SETZER = 6, 5, 4, 9
local TONIC, POTION, FENIX, REMEDY, SOFT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4
local REVIVIFY, GREEN_CHERRY, ELIXIR = 0xF1, 0xF8, 0xEE
local REGAL_CROWN, GREEN_BERET = 0x7B, 0x72
local STAR_PENDANT, JEWEL_RING = 0xB1, 0xB5
local UNICORN = 23                                  -- esper index (GenjuProp order)
local MAP_CASTLE, MAP_HALL, MAP_B1, MAP_B2, MAP_B3, MAP_CROWN = 55, 59, 61, 62, 63, 66
local MAP_KOHLINGEN, MAP_INN, MAP_STORE = 189, 191, 194
local MAP_K_HOUSE, MAP_K_WEST = 195, 197
local SHOP_WEAPONS, SHOP_ARMOR, SHOP_ITEMS = 65, 66, 67
local CASTLE_TILE = { 81, 85 }                      -- the castle by South Figaro (_ca5f0b)
local CASTLE_K = { { 53, 58 }, { 54, 58 } }         -- the castle by Kohlingen (_ca5f18)
local KOHLINGEN_DOOR = { 38, 45 }
local K_DOORS = { { 38, 45 }, { 39, 45 } }          -- Kohlingen's world entrances
local SAVE_TILE = { 40, 45 }                        -- east of the door: the wor-kohlingen-v1 save
local B2_EXITS = { { 13, 12 }, { 14, 8 }, { 2, 13 }, { 4, 6 }, { 8, 18 }, { 8, 6 } }  -- map 62's doors
local B3_EXITS = { { 53, 5 }, { 47, 8 }, { 56, 15 }, { 44, 15 }, { 87, 5 }, { 81, 5 }, { 84, 3 } }  -- map 63's
local OBJ_ENGINEER = 21                             -- 61 NPC_6 (6,33)
local OBJ_SETZER = 21                               -- 191 NPC_6 (23,15)
-- the cave's fights leave a Muddled ally to the monsters' hits rather than
-- a Genji pair's cure-hit (gen_wor_edgar CAVE_FIGHT; route-wor-edgar 12.5)
local CAVE_FIGHT = { unmuddle = false }

local function map() return H.mapId() & 0x1ff end
-- a step built when it is first reached, for a step whose arguments are
-- decided live (who wears the crown, what SETZER is dressed in)
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
local MEMBERS = { { CELES, "CELES" }, { SABIN, "SABIN" }, { EDGAR, "EDGAR" }, { SETZER, "SETZER" } }
local function topLevel()
  local m = 0
  for _, p in ipairs(MEMBERS) do if inParty(p[1]) then m = math.max(m, level(p[1])) end end
  return m
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
local function whereLine()
  local t = {}
  for _, p in ipairs(MEMBERS) do if inParty(p[1]) then t[#t + 1] = member(p[1], p[2]) end end
  return table.concat(t, "; ")
end
local function say(tag, what)
  H.log(string.format("[%s] f%d %s map %d (%d,%d): %s; %s", tag, H.frame, what, map(),
    H.fieldX(), H.fieldY(), whereLine(), supplies()))
end

-- ---- the item records (ItemProp, 30 bytes: +0 type, +1/+2 who can wear it,
-- +20 battle power or defense, +21 magic defense, +28 price) ----------------
local function prop(id, off) return H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30 + off) end
local function itemType(id) return prop(id, 0) & 7 end      -- 1 weapon 2 armor 3 shield 4 helmet 5 relic
local function wears(ch, id) return (((prop(id, 1) | (prop(id, 2) << 8)) >> ch) & 1) == 1 end
local function defScore(id) return prop(id, 20) + prop(id, 21) end
local function price(id) return prop(id, 28) | (prop(id, 29) << 8) end

-- ---- the battles --------------------------------------------------------
-- Every battle the walkers and the story driver fight ends in an [outcome];
-- each is asserted judged on its own end reading and paid as due, and the
-- count is asserted against the runner's own battle count (gen_wor_edgar's
-- shape).
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
-- Every battle's draw, at InitBattle's seed store (H.seedStoreAddr; the
-- shape of gen_sabin_train's key watch): the seed $be and the battle group
-- $11E0.  With the formation from the battle's [outcome] it is the battle
-- key docs/TESTING.md counts outcomes by.  Registered once per run.
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
-- walk onto a door tile until the map changes (gen_wor_edgar's walkInto:
-- the arrival counts once the new map is lit and in control, and a party
-- carried on through a second door goes again, up to three times)
local function walkInto(x, y, dst, what, avoid)
  local function there()
    return map() == dst and H.hasControl() and H.tileAligned() and bright() >= 15
  end
  return H.seqStep({
    H.repeatN(3, {
      H.cond(function() return not there() end, {
        -- a door tile the map's BFS cannot step onto (the court's gate
        -- (28,38): its tile reads impassable from below) is crossed the
        -- lib's way, staged on a neighbour with the direction held into it
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
local function exceptOf(list, x, y)
  local out = {}
  for _, t in ipairs(list) do if not (t[1] == x and t[2] == y) then out[#out + 1] = t end end
  return out
end
-- step onto a same-map link tile until `across` holds (the party has been
-- moved to the link's far side), fighting what comes on the way
-- (gen_wor_edgar's crossLink, with the map's other doors kept off the plan)
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
-- stands, else said and left (gen_wor_edgar's chest).  H.openChest is
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
-- out of a map by holding a direction until the World of Ruin map is
-- settled under the party (gen_wor_edgar's castle exit)
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

-- ---- the Regal Crown (#322): on whoever it improves most -------------------
-- EDGAR and SABIN are the two who can wear it (ItemProp +1/+2); each one's
-- gain is the crown's defense plus magic defense over the helmet he wears.
local crownTo = nil
local function crownPick()
  return H.call(function()
    crownTo = nil
    local best = 0
    for _, p in ipairs({ { EDGAR, "EDGAR" }, { SABIN, "SABIN" } }) do
      local cur = H.readByte(c(p[1], 0x21))
      local gain = defScore(REGAL_CROWN) - (cur == 0xFF and 0 or defScore(cur))
      H.log(string.format("[kit] the Regal Crown on %s: def+mdef %d over his $%02X's %d (gain %d); wears it %s",
        p[2], defScore(REGAL_CROWN), cur, cur == 0xFF and 0 or defScore(cur), gain,
        tostring(wears(p[1], REGAL_CROWN))))
      if wears(p[1], REGAL_CROWN) and gain > best then crownTo, best = p, gain end
    end
    H.log(string.format("[kit] the Regal Crown goes to %s", crownTo and crownTo[2] or "nobody"))
  end)
end

-- ---- dressing SETZER ---------------------------------------------------------
-- He joins with every slot empty (the World of Balance ending's
-- remove_equip) and the join runs no opt_equip, so the party dresses him
-- from the bag first and the town's shops second, the way a person watching
-- their gil does:
--   * each armour slot (shield, helmet, body) takes the bag's best piece he
--     can wear, by defense plus magic defense; the armour counter's best
--     piece for that slot is bought only when it beats the bag's and costs
--     no more than GIL_SHARE of the purse at the counter;
--   * the weapon is chosen by what it breaks, then by power: for each
--     weapon he can wear (the bag's and the weapon counter's), the number of
--     species on the arc ahead whose shield row (Ot6ShieldTbl, else the
--     generated floor OT6_FLOOR_CLASS) its class keys -- an experienced
--     player's reading of the ROM's data, so the choice follows whichever
--     break rows the ROM carries -- and the same GIL_SHARE bar for a bought
--     one;
--   * the relics are the bag's spare guards (a Star Pendant and the Jewel
--     Ring: Poison, Dark, Petrify), not the Coin Toss (it turns Slot into
--     GP Rain, a verb the driver does not play);
--   * the Esper is UNICORN: Pearl, the holy spell four of the tomb's five
--     species are weak to, and Remedy (route-wor-falcon 4.2).
local GIL_SHARE = 0.10
-- the species of world groups 45-47, Darill's Tomb's three pools and
-- Dullahan (route-wor-falcon 3.2, 3.3)
local ARC_SPECIES = { 0x089, 0x0DB, 0x0A7, 0x0D3, 0x005, 0x010, 0x06F, 0x061, 0x091, 0x11C }
local function shieldClasses(sp)
  local tbl = H.sym("Ot6ShieldTbl") & 0x3FFFFF
  for i = 0, 400 do
    local w = H.readRomByte(tbl + 4 * i) | (H.readRomByte(tbl + 4 * i + 1) << 8)
    if w == 0xFFFF then break end
    if w == sp then
      if H.readRomByte(tbl + 4 * i + 2) == 0 then return 0 end   -- no gauge
      return H.readRomByte(tbl + 4 * i + 3)
    end
  end
  return H.readRomByte((H.sym("OT6_FLOOR_CLASS") & 0x3FFFFF) + sp)
end
local function weaponKeys(id)
  local cls, n = H.weaponClass(id), 0
  for _, sp in ipairs(ARC_SPECIES) do
    if (shieldClasses(sp) & cls) ~= 0 then n = n + 1 end
  end
  return n
end
local function bagIds()
  local out = {}
  for s = 0, 255 do
    local id = H.readByte(0x1869 + s)
    if id ~= 0xFF and H.readByte(0x1969 + s) > 0 then out[#out + 1] = id end
  end
  return out
end
-- the bag's best piece of `typ` SETZER can wear, and its score
local function bagBest(typ, score)
  local best, bs = nil, -1
  for _, id in ipairs(bagIds()) do
    if itemType(id) == typ and wears(SETZER, id) and score(id) > bs then best, bs = id, score(id) end
  end
  return best, bs
end
local function weaponScore(id) return weaponKeys(id) * 1000 + prop(id, 20) end
-- the counter's best piece of `typ` SETZER can wear that beats the bag's
-- and passes the gil bar, or nil
local function shopPick(shop, typ, score, what)
  local _, bs = bagBest(typ, score)
  local best, sc = nil, bs
  for _, id in pairs(H.shopStock(shop)) do
    if itemType(id) == typ and wears(SETZER, id) then
      local ok = price(id) <= GIL_SHARE * H.gil()
      H.log(string.format("[kit] %s: shop %d's $%02X scores %d against the bag's best %d; %d GP %s %.0f%% of %d",
        what, shop, id, score(id), bs, price(id), ok and "within" or "over", GIL_SHARE * 100, H.gil()))
      if ok and score(id) > sc then best, sc = id, score(id) end
    end
  end
  return best
end
local buys = {}
local function buyFor(shop, typ, score, what)
  return H.seqStep({
    H.call(function() buys[what] = shopPick(shop, typ, score, what) end),
    H.cond(function() return buys[what] ~= nil end, {
      lazy(function() return H.buyItem(buys[what], 1, what) end),
    }, { H.call(function() H.log("[kit] " .. what .. ": the bag's piece stands; nothing bought") end) }),
  })
end
local setzerKit = nil
local function setzerPlan()
  return H.call(function()
    local weapon = bagBest(1, weaponScore)
    local shield = bagBest(3, defScore)
    local helmet = bagBest(4, defScore)
    local armor = bagBest(2, defScore)
    setzerKit = { { 0, weapon }, { 1, shield }, { 2, helmet }, { 3, armor } }
    -- relics: the bag's spare guards
    local r = {}
    for _, id in ipairs({ STAR_PENDANT, JEWEL_RING }) do
      if H.invCountOf(id) > 0 and wears(SETZER, id) then r[#r + 1] = id end
    end
    for i, id in ipairs(r) do setzerKit[#setzerKit + 1] = { 3 + i, id } end
    local t = {}
    for _, e in ipairs(setzerKit) do
      t[#t + 1] = string.format("slot %d $%02X", e[1], e[2] or 0xFF)
      H.assertEq(e[2] ~= nil, true, string.format("SETZER's slot %d has a piece in the bag", e[1]))
    end
    H.log(string.format("[kit] SETZER's kit: %s (weapon $%02X keys %d of the arc's %d species, power %d)",
      table.concat(t, ", "), weapon, weaponKeys(weapon), #ARC_SPECIES, prop(weapon, 20)))
  end)
end

-- ---- the item counter: Potions to the band, Fenix Downs to the level, and
-- Remedies and Revivifies for the tomb -------------------------------------
-- No shop on the arc sells Tonics, so Potions carry the combat band (level x
-- 1.5) plus the field care the legs to the next shop spend
-- (FIELD_CARE_POTIONS, gen_wor_south_figaro's).  Kohlingen is the last shop
-- before Darill's Tomb, whose bodies Zombie (four of five) and Sour-Mouth
-- (the Mad Oscar): Remedy and Revivify to TOMB_CURES each (informed: the
-- tomb's scripts, route-wor-falcon 3.5 and 4.4).  The scarcest-by-price
-- item last.
local FIELD_CARE_POTIONS, TOMB_CURES = 6, 10
-- Fenix Downs: about the level, capped near 20 (guidelines "Supply band")
local FENIX_CAP = 20
local function potionBand() return math.ceil(topLevel() * 1.5) + FIELD_CARE_POTIONS end
local function stock(shopId, what)
  local gil0 = 0
  return H.seqStep({
    H.call(function()
      gil0 = H.gil()
      H.assertEq(H.shopId(), shopId, string.format("the counter opened shop %d ($0201)", shopId))
    end),
    H.buyItem(POTION, function() return math.max(0, potionBand() - H.invCountOf(POTION)) end,
      "POTION to the band"),
    H.buyItem(REVIVIFY, function() return math.max(0, TOMB_CURES - H.invCountOf(REVIVIFY)) end,
      "REVIVIFY for the tomb"),
    H.buyItem(FENIX, function() return math.max(0, math.min(FENIX_CAP, topLevel()) - H.invCountOf(FENIX)) end,
      "FENIX DOWN to the level, capped at the band"),
    H.buyItem(REMEDY, function() return math.max(0, TOMB_CURES - H.invCountOf(REMEDY)) end,
      "REMEDY for the tomb"),
    H.call(function()
      H.log(string.format("[shop] %s: bought: %s (spent %d GP)", what, supplies(), gil0 - H.gil()))
    end),
    H.shopClose(what),
    H.call(function()
      H.assertEq(H.invCountOf(POTION) >= potionBand(), true, "Potions at the band")
      H.assertEq(H.invCountOf(FENIX) >= math.min(FENIX_CAP, topLevel()), true, "Fenix Downs at about the level")
      H.assertEq(H.invCountOf(REMEDY) >= TOMB_CURES, true, "Remedies for the tomb")
      H.assertEq(H.invCountOf(REVIVIFY) >= TOMB_CURES, true, "Revivifies for the tomb")
    end),
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
  end),
  -- the checkpoint was saved hurt (EDGAR 948/1600 and SABIN 75/291 MP at
  -- the tracked save): the care before the castle
  H.fieldCare({ tag = "care at the boot" }),

  -- ---- 1. into the castle --------------------------------------------------------------
  H.worldNavTo(CASTLE_TILE[1], CASTLE_TILE[2], { maxFrames = 6000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_CASTLE end, 2400, "Figaro Castle: map 55", 5),
  control("Figaro Castle: control"),
  H.call(function() say("castle", "in the castle") end),
  -- the court's stairs (28,38) -> the lower hall 59 (12,49), its (9,49) ->
  -- basement 1's west room 61 (10,33) (route-wor-edgar 12.1)
  walkInto(28, 38, MAP_HALL, "the court -> the lower hall"),
  walkInto(9, 49, MAP_B1, "the lower hall -> basement 1's west room"),

  -- ---- 2. the Regal Crown (#322) ----------------------------------------------------------
  -- Map 62's door to the crown's room (4,6) is in a west pocket of basement
  -- 2 that only basement 3 reaches (measured: no path from the arrival
  -- (12,13) to (4,7) once map 62's other doors are kept off the plan; the
  -- offline region graph walked through door tiles): 62 (14,8) -> 63
  -- (54,6), its link (56,15) -> the chest room (87,7), the stairs (81,5)
  -- -> (44,14), and (47,8) -> 62 (3,12).  The way back is the pocket's
  -- (2,13) -> 63 (46,9), the stairs (44,15) -> (81,7), and gen_wor_edgar's
  -- way to basement 1: (87,5) -> (56,14), (53,5) -> 62 (13,7), (13,12) ->
  -- 61 (3,36).  Basements 2 and 3 roll the cave's pools (groups 137, 138).
  walkInto(2, 37, MAP_B2, "basement 1 -> basement 2"),
  walkInto(14, 8, MAP_B3, "basement 2 -> basement 3"),
  crossLink(56, 15, function() return H.fieldX() > 70 end, "basement 3: the link (56,15) -> (87,7)"),
  H.crossDoor(81, 5, MAP_B3, 44, 14, "basement 3's stairs 63(81,5)->63(44,14)",
    { fight = CAVE_FIGHT, avoid = exceptOf(B3_EXITS, 81, 5) }),
  walkInto(47, 8, MAP_B2, "basement 3 -> basement 2's west pocket", exceptOf(B3_EXITS, 47, 8)),
  walkInto(4, 6, MAP_CROWN, "basement 2 -> the crown's room (map 66)", exceptOf(B2_EXITS, 4, 6)),
  chest(3, 53, 0x09A, "Regal Crown", REGAL_CROWN),
  H.call(function()
    H.assertEq(H.chestOpen(0x09A), true, "the Regal Crown's chest is open (bit $09A)")
    say("castle", "the Regal Crown")
  end),
  walkInto(3, 56, MAP_B2, "the crown's room -> basement 2"),
  walkInto(2, 13, MAP_B3, "basement 2's west pocket -> basement 3", exceptOf(B2_EXITS, 2, 13)),
  H.crossDoor(44, 15, MAP_B3, 81, 7, "basement 3's stairs 63(44,15)->63(81,7)",
    { fight = CAVE_FIGHT, avoid = exceptOf(B3_EXITS, 44, 15) }),
  H.crossDoor(87, 5, MAP_B3, 56, 14, "basement 3's stairs 63(87,5)->63(56,14)", { fight = CAVE_FIGHT }),
  H.crossDoor(53, 5, MAP_B2, 13, 7, "basement 3's stairs 63(53,5)->62(13,7)", { fight = CAVE_FIGHT }),
  walkInto(13, 12, MAP_B1, "basement 2 -> basement 1", exceptOf(B2_EXITS, 13, 12)),
  checkOutcomes("the castle's basements"),
  H.fieldCare({ tag = "after basement 2" }),
  crownPick(),
  H.cond(function() return crownTo ~= nil end, {
    lazy(function() return H.equipKit(crownTo[1], { { 2, REGAL_CROWN } }, { tag = "the Regal Crown on " .. crownTo[2] }) end),
  }, {}),
  H.call(function()
    H.assertEq(crownTo ~= nil and H.readByte(c(crownTo[1], 0x21)) == REGAL_CROWN, true,
      "the Regal Crown is worn")
    say("castle", "kit EDGAR " .. kit(EDGAR) .. ", SABIN " .. kit(SABIN))
  end),

  -- ---- 3. the engineer: "(Go to Kohlingen?)" ----------------------------------------
  H.talkToObj(OBJ_ENGINEER, "the engineer (61 NPC_6)"),
  H.dialogChoice(0, { what = "(Go to Kohlingen?): row 0 (dlg $03D4)", maxFrames = 3000 }),
  H.advanceStory(function()
    return sw(0x00DC) == 1 and map() == MAP_B1 and H.hasControl() and H.tileAligned()
      and not H.dialogWaiting() and bright() >= 15
  end, 12000, { playBattles = "tactical", fight = CAVE_FIGHT }),
  H.call(function()
    say("castle", "the castle has sailed for Kohlingen")
    H.assertEq(sw(0x00DC), 1, "the castle stands by Kohlingen ($00DC, _ca6908 :15690)")
    H.assertEq(sw(0x0106), 0, "the castle no longer stands by South Figaro ($0106)")
  end),

  -- ---- 4. out of the castle, and the walk to Kohlingen -------------------------------------
  -- 61's stairs (11,32) -> 59 (10,48), (12,50) -> the court 55 (28,40), and
  -- out by the south row (route-wor-edgar 12.1)
  walkInto(11, 32, MAP_HALL, "basement 1 -> the lower hall"),
  walkInto(12, 50, MAP_CASTLE, "the lower hall -> the court"),
  H.navTo(28, 42, { maxFrames = 6000, playBattles = "tactical" }),
  outToWorld("down", "out of Figaro Castle by Kohlingen"),
  H.worldNavTo(KOHLINGEN_DOOR[1], KOHLINGEN_DOOR[2], { maxFrames = 20000, playBattles = "tactical",
    avoid = CASTLE_K, arrive = function() return not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_KOHLINGEN end, 2400, "Kohlingen: map 189", 5),
  control("Kohlingen: control"),
  H.call(function() say("kohlingen", "in town") end),
  checkOutcomes("the walk to Kohlingen"),
  H.fieldCare({ tag = "in Kohlingen" }),

  -- ---- 5. the town's chests -------------------------------------------------------------
  -- the Green Beret, 195 (37,53), by the house door 189 (26,4) -> 195 (38,53);
  -- the Elixir, 197 (42,10), by 189 (4,7) -> 197 (39,18)
  H.crossDoor(26, 4, MAP_K_HOUSE, 38, 53, "Kohlingen house door 189(26,4)->195(38,53)"),
  chest(37, 53, 0x041, "Green Beret", GREEN_BERET),
  walkInto(38, 51, MAP_KOHLINGEN, "the house -> Kohlingen"),
  H.crossDoor(4, 7, MAP_K_WEST, 39, 18, "Kohlingen west house door 189(4,7)->197(39,18)"),
  chest(42, 10, 0x045, "Elixir", ELIXIR),
  walkInto(39, 19, MAP_KOHLINGEN, "the west house -> Kohlingen"),
  H.call(function() say("kohlingen", "the chests") end),

  -- ---- 6. the inn, when anyone is short, and SETZER -------------------------------------
  H.crossDoor(16, 22, MAP_INN, 17, 20, "Kohlingen inn door 189(16,22)->191(17,20)"),
  H.cond(function()
    local short = false
    for _, p in ipairs(MEMBERS) do
      if inParty(p[1]) and (H.charHp(p[1]) < H.charMaxHp(p[1]) or H.charMp(p[1]) < H.charMaxMp(p[1])
          or H.charStatus1(p[1]) ~= 0) then short = true end
    end
    if not short then H.log("[kohlingen] the party is whole; no inn") end
    return short
  end, {
    H.cond(function() return H.bfsPath(17, 12) ~= nil end, {
      H.innRest({ spot = { 17, 12 }, face = "up", price = 200, tag = "Kohlingen inn" }),
    }, {
      H.innRest({ spot = { 17, 13 }, face = "up", price = 200, tag = "Kohlingen inn" }),
    }),
  }, {}),
  H.talkToObj(OBJ_SETZER, "SETZER at the inn (191 NPC_6)"),
  H.advanceStory(function()
    return sw(0x00CA) == 1 and map() == MAP_KOHLINGEN and H.hasControl() and H.tileAligned()
      and not H.dialogWaiting() and bright() >= 15
  end, 20000, {}),
  H.call(function()
    say("kohlingen", "SETZER joined, kit " .. kit(SETZER))
    H.assertEq(sw(0x00CA), 1, "SETZER joined ($00CA, :85777)")
    H.assertEq(sw(0x02F9), 1, "SETZER is available ($02F9)")
    H.assertEq(inParty(SETZER), true, "SETZER is in the party")
  end),

  -- ---- 7. the shops, and SETZER dressed ---------------------------------------------------
  H.crossDoor(11, 11, MAP_STORE, 12, 39, "Kohlingen store door 189(11,11)->194(12,39)"),
  H.shopTalk(9, 35, "Kohlingen weapon counter"),
  H.call(function() H.assertEq(H.shopId(), SHOP_WEAPONS, "the counter opened shop 65 ($0201)") end),
  buyFor(SHOP_WEAPONS, 1, weaponScore, "SETZER's weapon"),
  H.shopClose("Kohlingen weapon counter"),
  H.shopTalk(15, 35, "Kohlingen armor counter"),
  H.call(function() H.assertEq(H.shopId(), SHOP_ARMOR, "the counter opened shop 66 ($0201)") end),
  buyFor(SHOP_ARMOR, 3, defScore, "SETZER's shield"),
  buyFor(SHOP_ARMOR, 4, defScore, "SETZER's helmet"),
  buyFor(SHOP_ARMOR, 2, defScore, "SETZER's armor"),
  H.shopClose("Kohlingen armor counter"),
  H.shopTalk(19, 35, "Kohlingen item counter"),
  stock(SHOP_ITEMS, "Kohlingen item counter"),
  H.bagArrange({ POTION, FENIX, REMEDY, REVIVIFY, SOFT, GREEN_CHERRY, TONIC },
    { tag = "bag: combat items on top" }),
  setzerPlan(),
  lazy(function() return H.equipKit(SETZER, setzerKit, { tag = "SETZER dressed" }) end),
  H.equipEsper(function() return (H.readByte(0x1850 + SETZER) >> 3) & 3 end, UNICORN,
    { tag = "UNICORN -> SETZER" }),
  H.call(function()
    for _, e in ipairs(setzerKit) do
      H.assertEq(H.readByte(c(SETZER, 0x1F + e[1])), e[2],
        string.format("SETZER's slot %d holds $%02X", e[1], e[2]))
    end
    H.assertEq(H.readByte(c(SETZER, 0x1E)), UNICORN, "SETZER holds UNICORN")
    say("kohlingen", "SETZER dressed: " .. kit(SETZER))
  end),
  -- SETZER's row: he joins in the front row, the trio stands in the back.
  -- A weapon without the row penalty (ItemProp +19 bit 5; the Darts and
  -- his cards have it) loses nothing in the back row, where physical hits
  -- taken are halved (lib setRows), so he goes back when his weapon says so.
  H.cond(function()
    local w = H.readByte(c(SETZER, 0x1F))
    local free = w ~= 0xFF and (prop(w, 19) & 0x20) ~= 0
    H.log(string.format("[kit] SETZER's weapon $%02X %s the row penalty; party byte $%02X", w,
      free and "ignores" or "carries", H.readByte(0x1850 + SETZER)))
    return free
  end, {
    H.setRows({ [SETZER] = true }, { tag = "SETZER to the back row" }),
  }, {}),
  control("the store, after the menu"),
  H.waitFrames(30),
  walkInto(12, 40, MAP_KOHLINGEN, "the store -> Kohlingen"),

  -- ---- 8. out to the world map, and the save ----------------------------------------------
  -- the town's arrival tile (23,29), then down off the south edge (the
  -- long exit (1,31) len 30 -> world (38,46))
  H.fieldCare({ threshold = 1.0, tag = "before the save" }),
  H.navTo(23, 29, { maxFrames = 6000, playBattles = "tactical" }),
  outToWorld("down", "out of Kohlingen by the south edge"),
  -- The exit returns the party to the tile it stepped into the town from
  -- (measured: (40,45) after a walk in from the east, the castle's side),
  -- so the save is made on a fixed tile, SAVE_TILE, walked to with the
  -- town's entrance tiles kept off the plan.  A step can roll an encounter
  -- that opens after the walker has arrived (gen_wor_nikeah's finding), so
  -- the party stands a moment and walks there again, fighting what came,
  -- and the care runs on the tile.
  H.worldNavTo(SAVE_TILE[1], SAVE_TILE[2], { maxFrames = 6000, playBattles = "tactical", avoid = K_DOORS }),
  H.waitFrames(90),
  H.worldNavTo(SAVE_TILE[1], SAVE_TILE[2], { maxFrames = 6000, playBattles = "tactical", avoid = K_DOORS }),
  H.fieldCare({ threshold = 1.0, tag = "on the save tile" }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled on the save tile", 5),
  H.saveAtCheckpoint("wor-kohlingen-v1"),
  checkOutcomes("the stretch"),
  H.call(function()
    local forms = {}
    for _, k in ipairs(tally.order) do forms[#forms + 1] = string.format("%s x%d", k, tally.forms[k]) end
    H.log(string.format("[wor] the battles: %d (%s): %d won, %d the party left, %d monster escape(s)",
      seen - outcome0, table.concat(forms, ", "), tally.won, tally["party left"], tally.escaped))
    H.log(string.format("[wor] the stretch: %s; kit CELES %s, SABIN %s, EDGAR %s, SETZER %s; %s", whereLine(),
      kit(CELES), kit(SABIN), kit(EDGAR), kit(SETZER), supplies()))
    H.screenshot("wor_kohlingen")
  end),
  H.saveState("wor_kohlingen.mss"),
  H.logStep(function()
    return string.format("wor_kohlingen generated: CELES L%d, SABIN L%d, EDGAR L%d and SETZER L%d on the World of Ruin at (%d,%d), outside Kohlingen, saved in slot 3",
      level(CELES), level(SABIN), level(EDGAR), level(SETZER), H.worldX(), H.worldY())
  end),
})
