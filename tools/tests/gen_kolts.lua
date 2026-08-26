-- gen_kolts.lua -- from figaro_cleared.mss (TERRA + LOCKE + EDGAR on a
-- chocobo in the Figaro desert) to the Vargas entry point on Mt. Kolts.
-- Generates three states:
--   south_figaro.mss map 75 (1,28), the town's west gate
--   kolts_entry.mss  map 95 (14,35), the mountain's entrance map
--   vargas_entry.mss map 98, party tile-aligned next to VARGAS with his
--                    approach event already run, one interaction short
--                    of `battle 66`
--
-- The party arrives on a chocobo, and the world navigator cannot read its
-- position until it dismounts (InitChoco never writes $E0/$E2; InitWorld
-- does). Dismounting is B held while riding; LandAirship sets $19=3 and
-- locks input, the descent sets $19=($19&$FE)|$04 once grounded, and
-- ExitVehicle's ReloadMap dispatch then runs InitWorld, seeding $E0/$E2.
--
-- The Figaro desert does not reach South Figaro on foot: it is a separate
-- flood-fill region from South Figaro/Mt. Kolts. The link is a cave (named
-- by the castle's own NPC dialogue), three field maps: world (73,93) ->
-- map 71 (10,54) [short entrance] -> event _ca5ef7 (switch $001A picks map
-- 70 or 73, identical entrance coordinates either way) -> map 73 (41,14)
-- -> map 72 (4,5) [short entrance] -> map 72 (16,43) -> world (75,103)
-- [short entrance]. The cave mouth is guarded by two Figaro guards
-- (NPCProp::_71, spawn switch $0312) blocking the only way north; talking
-- to the one at (10,49) (gated by switch $0108, asserted open) despawns
-- both permanently, so the lobby crossing is: walk under the guard, face
-- up, talk, then walk through the tile he was standing on.
--
-- Two world-exit rows to stay clear of mid-crossing: map 75's long
-- entrances at x=0/x=56 (y=0..47) and y=1 lead to the world map, so the
-- party enters at (1,28) and the exit is a single deliberate press; map
-- 95's long entrance at y=37 (x=0..27) does the same, so every step there
-- stays off y=37 until the deliberate exit.
--
-- No state writes; every encounter is answered by the pad. The cave, town
-- and world steps flee (L+R); Mt. Kolts and map 98 are fought tactically
-- (EDGAR's Tools, boosted Fights, the fight driver's Potion medic line) --
-- crossing Mt. Kolts on foot is what levels the party for VARGAS. A
-- formation that will not release the party inside M.FLEE_CAP frames is
-- fought out by the same tactical driver.
--
-- The care layer: every crossing ends with a check of the party's hit
-- points, and the route stops at the shop in South Figaro.
local H = dofile("tools/tests/lib/ot6.lua")
local CLEARED = "build/states/figaro_cleared.mss.lua"

-- map compares stay masked: loaders leave flag bits in $1F64's high byte
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
-- event switch id -> live bit (event bitfield base $1E80, bit = id & 7)
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
-- field object i's live tile (pixel coords >> 4, block stride $29)
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end

-- field inventory: ids at $1869+i, counts at $1969+i (256 slots)
local function invCount(id)
  for i = 0, 255 do
    if H.readByte(0x1869 + i) == id then return H.readByte(0x1969 + i) end
  end
  return 0
end
local function gil()
  return H.readByte(0x1860) + (H.readByte(0x1861) << 8)
       + (H.readByte(0x1862) << 16)
end

-- Roster line, printed by every `where` so the damage profile of the route
-- is legible step by step. $1600 + 37*c: +8 level, +9/+11 cur/max hp,
-- +13/+15 cur/max mp; a character is in the party when $1850+c has a low
-- nibble bit set.
local function rosterLine()
  local out = {}
  for c = 0, 15 do
    if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
      local b = 0x1600 + 37 * c
      out[#out + 1] = string.format("c%d L%d %d/%d hp %d/%d mp", c,
        H.readByte(b + 8), H.readWord(b + 9), H.readWord(b + 11),
        H.readWord(b + 13), H.readWord(b + 15))
    end
  end
  return string.format("%s | gil=%d tonic=%d potion=%d fenix=%d",
    table.concat(out, " | "), gil(),
    invCount(0xE8), invCount(0xE9), invCount(0xF0))
end

local function where(tag)
  H.log(string.format("[%s] f%d map=%d field=(%d,%d) world=(%d,%d) " ..
    "$11FA=%02X $010A=%d bright=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), H.worldX(), H.worldY(),
    H.readByte(0x11fa), sw(0x010A), bright()))
  H.log(string.format("[%s] %s", tag, rosterLine()))
end

local POTION = 0xE9
local function care(tag, threshold)
  return H.fieldCare({ tag = "care " .. tag, threshold = threshold or 0.85,
                       reserve = { [POTION] = 5 }, mpFloor = 0.75 })
end

-- H.cond with an always-true predicate wraps a list into a single step
-- (a bare list can't be spliced into a step list).
local function seq(steps) return H.cond(function() return true end, steps) end

-- An `arrive` predicate that fires when the map id changes from whatever it
-- read the first time it was called.  Latching lazily (rather than at
-- script-build time) is what makes it correct inside route(), whose steps are
-- all constructed before any of them runs.
local function mapChanged()
  local m0
  return function()
    if m0 == nil then m0 = map() end
    return map() ~= m0
  end
end

local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

local function settleField(what, dstMap, maxF, mode)
  return seq({
    H.waitFrames(90),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), maxF or 24000, { playBattles = mode or "flee" }),
    H.waitFrames(30),
  })
end

local function settleWorld(what, maxF)
  return seq({
    H.advanceStory(settled(20, function()
      return H.worldHasControl() and H.worldAligned()
    end), maxF or 12000, { playBattles = "flee" }),
    H.waitFrames(30),
  })
end

-- Walk to (tx,ty) on the current field map, expecting the map to change
-- on arrival.  Mt. Kolts and the cave use plain walkable floor for their
-- entrances, unlike Figaro's castle doors, which are walls until
-- CheckDoor, so BFS can route straight onto them.  The map id is
-- asserted afterwards, so a missed crossing cannot pass for one.
local function crossTo(tx, ty, dstMap, what, mode, maxF)
  return seq({
    H.logStep(function()
      return string.format("cross %s: (%d,%d) -> (%d,%d) -> map %d [%s]",
        what, H.fieldX(), H.fieldY(), tx, ty, dstMap, mode or "flee")
    end),
    H.navTo(tx, ty, { maxFrames = maxF or 40000, arrive = mapChanged(),
             playBattles = mode or "flee", reserve = { [POTION] = 5 } }),
    H.release(),
    settleField(what, dstMap, nil, mode),
    H.call(function()
      H.assertEq(map(), dstMap, what .. ": landed on map " .. dstMap)
      where(what)
    end),
    care(what),
  })
end

local FACE = { up = 0, right = 1, down = 2, left = 3 }
local function talkAt(sx, sy, dir, what, maxF)
  local aPh, started = 0, 0
  return seq({
    H.navTo(sx, sy, { maxFrames = 20000, playBattles = "flee" }),
    H.release(),
    H.driveUntil(function()
      started = (H.eventRunning() or H.dialogWaiting()) and started + 1 or 0
      return started >= 4
    end, maxF or 9000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        if H.fieldX() ~= sx or H.fieldY() ~= sy then H.setPad({}); return end
        if H.readByte(0x087f + H.readWord(0x0803)) ~= FACE[dir] then
          H.setPad({ [dir] = true })
          return
        end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, what),
    H.release(),
  })
end

-- Cross an entrance whose destination is the same map.  Map 72 is built out
-- of four of them, so `map changed` is no signal there.  Arrival is the
-- destination tile instead.
local function warpTo(sx, sy, dx, dy, what, maxF)
  return seq({
    H.logStep(function()
      return string.format("warp %s: (%d,%d) -> (%d,%d) -> (%d,%d)",
        what, H.fieldX(), H.fieldY(), sx, sy, dx, dy)
    end),
    H.navTo(sx, sy, { maxFrames = maxF or 20000, playBattles = "flee",
                      arrive = function()
      return H.fieldX() == dx and H.fieldY() == dy
    end }),
    H.release(),
    settleField(what, 72),
    H.call(function()
      H.assertEq(H.fieldX(), dx, what .. ": landed at x=" .. dx)
      H.assertEq(H.fieldY(), dy, what .. ": landed at y=" .. dy)
      where(what)
    end),
    care(what),
  })
end

-- Assert the BFS plan to (tx,ty) exists and never touches row `badY`, the
-- map's world-exit row.  BFS models passability, not entrance triggers, so
-- this check is what keeps a shortest path from walking out of the mountain.
local function planAvoidsRow(tx, ty, badY, what)
  return H.cond(function() return true end, {
    H.waitUntil(function() return H.bfsPath(tx, ty) ~= nil end,
                900, what .. ": a path exists (45f poll)", 45),
    H.call(function()
    local p = H.bfsPath(tx, ty)
    H.assertEq(p ~= nil, true, what .. ": a path exists")
    local x, y = H.fieldX(), H.fieldY()
    local hit = (y == badY)
    for _, d in ipairs(p) do
      local dd = ({ up = { 0, -1 }, down = { 0, 1 },
                    left = { -1, 0 }, right = { 1, 0 },
                    upleft = { -1, -1 }, upright = { 1, -1 },
                    downleft = { -1, 1 }, downright = { 1, 1 } })[d]
      x, y = x + dd[1], y + dd[2]
      if y == badY then hit = true end
    end
    H.log(string.format("%s: %d steps, touches y=%d: %s",
      what, #p, badY, tostring(hit)))
    H.assertEq(hit, false, what .. ": plan stays off the world-exit row " .. badY)
  end),
  })
end

-- ------------------------------------------------------------- the shop --
-- Menu states: $25 options, $26 buy list, $27 quantity, $28 post-buy wait
-- -> $26.  The list row is $4B; row r's item id is $7E9D89+r.  The
-- quantity widget is zSelIndex, DP $28 -- RIGHT +1, LEFT -1, UP +10,
-- DOWN -10, gil-clamped by the handler.  Both cells are read and steered
-- toward a target, never press-counted: menu auto-repeat overshoots.
--
-- The five map-75 short entrances a BFS would route through.  Four are
-- far from this walk; (8..10,32) is sixteen steps from the spawn, in the
-- quadrant the shop walk crosses.
local M75_AVOID = {
  { 8, 32 }, { 9, 32 }, { 10, 32 },        -- -> map 80
  { 18, 55 }, { 19, 55 }, { 20, 55 },      -- -> map 91
  { 48, 37 }, { 34, 35 }, { 22, 14 },
}

local function mstate() return H.readByte(0x0026) end
local function shopRow() return H.readByte(0x004b) end
local function shopQty() return H.readByte(0x0028) end
local function rowItem(r) return H.readByte(0x9d89 + r) end
local function inState(v) return function() return mstate() == v end end

local function tapUntil(btn, pred, what, maxF)
  return H.driveUntil(pred, maxF or 1800, {
    H.call(function() H.setPad((H.frame % 10 < 4) and { btn } or {}) end),
  }, what)
end

local function leaveTo(dstMap, dirs, what, maxF)
  local n = 0
  return seq({
    H.driveUntil(function() return map() == dstMap end, maxF or 3000, {
      H.call(function()
        n = n + 1
        H.setPad({ [dirs[((n // 40) % #dirs) + 1]] = true })
      end),
    }, what),
    H.release(),
  })
end

-- Buy up to `target` of item `id`, sitting on buy-list row `row`.  Every step
-- is checked: the row is verified to hold the expected item before any money
-- moves, the quantity is steered to the number we want and read back, and the
-- purchase is confirmed by gil falling by quantity x price.  With too little
-- gil it buys what it can and logs the count.
local function buyTo(id, row, target, unit, name)
  local want, before = 0, 0
  return seq({
    H.driveUntil(function() return shopRow() == row end, 3000, {
      H.call(function()
        local cur = shopRow()
        H.setPad((H.frame % 10 < 4)
          and { [cur < row and "down" or "up"] = true } or {})
      end),
    }, "shop: cursor -> row " .. row),
    H.release(), H.waitFrames(20),
    H.call(function()
      H.assertEq(rowItem(row), id,
        string.format("shop row %d really is item $%02X", row, id))
      before = gil()
      want = target - invCount(id)
      local afford = before // unit
      if want > afford then want = afford end
      H.log(string.format("[shop] %s: have %d, buying %d at %d gp (gil %d)",
        name, invCount(id), want, unit, before))
    end),
    H.cond(function() return want >= 1 end, {
      tapUntil("a", inState(0x27), "shop: quantity window"),
      H.driveUntil(function() return shopQty() == want end, 3000, {
        H.call(function()
          local q = shopQty()
          local btn = (q < want) and ((want - q >= 10) and "up" or "right")
                                 or ((q - want >= 10) and "down" or "left")
          H.setPad((H.frame % 8 < 3) and { [btn] = true } or {})
        end),
      }, "shop: quantity steered to the wanted count"),
      H.release(), H.waitFrames(20),
      tapUntil("a", function() return gil() < before end,
        "shop: purchase goes through"),
      H.release(),
      H.waitUntil(inState(0x26), 2400, "shop: back to the buy list", 2),
      H.call(function()
        H.assertEq(before - gil(), want * unit,
          string.format("%s cost %d x %d gp", name, want, unit))
      end),
    }, {}),
  })
end

local function shopTrip()
  return seq({
    H.logStep(function()
      return string.format("[shop] heading in: gil=%d tonic=%d potion=%d " ..
        "fenix=%d", gil(), invCount(0xE8), invCount(0xE9), invCount(0xF0))
    end),
    H.navTo(44, 32, { maxFrames = 30000, playBattles = "flee", avoid = M75_AVOID }),
    H.release(), H.waitFrames(20),
    H.call(function()
      H.assertEq(H.fieldX(), 44, "on the shop's door mat, x=44")
      H.assertEq(H.fieldY(), 32, "on the shop's door mat, y=32")
    end),
    -- (44,30) is a bump door: a wall until CheckDoor runs, so this is a
    -- held press, never a navTo whose goal it is
    H.driveUntil(function() return map() == 85 end, 1200, {
      H.hold({ "up" }), H.waitFrames(8),
    }, "into the item shop (the bump door at (44,30))"),
    H.release(),
    settleField("item shop", 85),
    H.call(function()
      H.assertEq(map(), 85, "inside the item shop, map 85")
      where("item shop")
    end),
    H.navTo(106, 54, { maxFrames = 20000, playBattles = "flee" }),
    H.release(), H.waitFrames(20),
    -- Counter talk: the merchant is at (106,52) with the counter tile
    -- (106,53) between him and the party, and CheckNPCs reaches through it
    -- (player.asm:188-200).  UP is held until the facing byte reads back,
    -- because a two-frame turn press does not set it, and (106,53) is
    -- impassable, so the hold cannot walk anyone into the counter.
    H.driveUntil(inState(0x25), 6000, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        if H.fieldX() ~= 106 or H.fieldY() ~= 54 then H.setPad({}); return end
        if H.readByte(0x087f + H.readWord(0x0803)) ~= FACE.up then
          H.setPad({ up = true }); return
        end
        H.setPad((H.frame % 8 < 4) and { "a" } or {})
      end),
    }, "open the item shop (counter talk -> shop_menu 8)"),
    H.release(),
    H.call(function() H.screenshot("sfigaro_shop") end),
    tapUntil("a", inState(0x26), "shop: the buy list opens"),
    H.release(), H.waitFrames(20),
    H.call(function()
      local rows = {}
      for r = 0, 7 do rows[#rows + 1] = string.format("%02X", rowItem(r)) end
      H.log("[shop] stock: " .. table.concat(rows, " "))
    end),
    buyTo(0xF0, 5, 5, 500, "FENIX DOWN to 5"),
    buyTo(0xF2, 1, 3, 50, "ANTIDOTE to 3"),
    buyTo(0xF4, 2, 2, 200, "SOFT to 2"),
    buyTo(0xE8, 0, 25, 50, "TONIC to 25"),
    tapUntil("b", inState(0x25), "shop: back to the options window"),
    tapUntil("b", function() return H.hasControl() and map() == 85 end,
      "shop: closed"),
    H.release(), H.waitFrames(30),
    H.call(function()
      H.log(string.format(
        "[shop] done: gil=%d tonic=%d potion=%d fenix=%d antidote=%d",
        gil(), invCount(0xE8), invCount(0xE9), invCount(0xF0),
        invCount(0xF2)))
      H.assertEq(invCount(0xF0) >= 3, true,
        "the party leaves with Fenix Downs -- a death is answerable now")
      H.assertEq(invCount(0xE8) >= 10, true, "Tonics restocked for the climb")
      H.assertEq(invCount(0xF2) >= 2, true,
        "the party leaves with Antidotes -- poison is answerable now, and " ..
        "there is no other counter between here and the Returner Hideout")
      H.assertEq(invCount(0xF4) >= 2, true,
        "the party leaves with two Softs -- Petrify recovery backs up the " ..
        "route, not merely the next encounter")
    end),
    H.navTo(104, 57, { maxFrames = 20000, playBattles = "flee" }),
    H.release(), H.waitFrames(20),
    leaveTo(75, { "down", "left", "right", "up" }, "out of the item shop"),
    settleField("back in town", 75),
    H.call(function()
      H.assertEq(map(), 75, "back on map 75 with the shopping done")
      where("shop done")
    end),
  })
end

-- ================================================================ the stop --
-- The South Figaro stop as a player would take it: fight the ground
-- outside the gate for a while, then spend what that paid on the four
-- shops and a night at the inn.  LOCKE's level is fixed from
-- `banon_joined` onward (he leaves the party there), so this is the last
-- window in which it can still move.

local LOCKE = 1
local function expOf(c)
  local b = 0x1600 + 37 * c + 0x11        -- 3 bytes
  return H.readByte(b) + (H.readByte(b + 1) << 8) + (H.readByte(b + 2) << 16)
end
local function levelOf(c) return H.readByte(0x1600 + 37 * c + 8) end

local EXP_TARGET = 2250
local GIL_TARGET = 8300   -- +250: the second Plumed Hat
local grindLaps = 0
local function grindDone()
  return expOf(LOCKE) >= EXP_TARGET and gil() >= GIL_TARGET
end
local function lap(n)
  return H.cond(function() return not grindDone() end, {
    H.logStep(function()
      return string.format("grind lap %d: LOCKE L%d xp=%d/%d gil=%d f%d", n,
        levelOf(LOCKE), expOf(LOCKE), EXP_TARGET, gil(), H.frame)
    end),
    H.worldNavTo(100, 105, { maxFrames = 40000, playBattles = "tactical",
                             reserve = { [POTION] = 3 } }),
    H.release(),
    H.worldNavTo(87, 105, { maxFrames = 40000, playBattles = "tactical",
                            reserve = { [POTION] = 3 } }),
    H.release(),
    H.call(function() grindLaps = n; where("grind lap " .. n) end),
    care("grind lap " .. n, 0.85),
  }, {})
end

local function grindTrip()
  return seq({
    -- out of town by the x=0 column -> world (84,112)
    H.navTo(1, 28, { maxFrames = 30000, playBattles = "flee",
                     avoid = M75_AVOID }),
    H.release(), H.waitFrames(30),
    H.driveUntil(function() return H.worldMode() end, 900, {
      H.hold({ "left" }), H.waitFrames(8),
    }, "leave South Figaro for the grind (x=0 column)"),
    H.release(),
    settleWorld("outside the gate"),
    H.worldNavTo(84, 108, { maxFrames = 20000, playBattles = "tactical" }),
    H.release(),
    H.call(function()
      H.assertEq(H.worldMode(), true,
        "still outside -- the town's own entrance tiles were stepped around")
      H.assertEq(H.worldX(), 84, "staged north of the gate, x=84")
      H.assertEq(H.worldY(), 108, "staged north of the gate, y=108")
      where("grind start")
    end),
    lap(1), lap(2), lap(3), lap(4), lap(5), lap(6), lap(7), lap(8), lap(9),
    lap(10), lap(11), lap(12), lap(13), lap(14), lap(15), lap(16), lap(17),
    lap(18), lap(19), lap(20), lap(21), lap(22), lap(23), lap(24),
    H.call(function()
      H.log(string.format(
        "[grind] %d laps: LOCKE L%d xp=%d (target %d), gil=%d",
        grindLaps, levelOf(LOCKE), expOf(LOCKE), EXP_TARGET, gil()))
      H.assertEq(expOf(LOCKE) >= EXP_TARGET, true,
        string.format("the grind reached its experience target in %d laps " ..
          "(LOCKE %d of %d)", grindLaps, expOf(LOCKE), EXP_TARGET))
      H.assertEq(gil() >= GIL_TARGET, true,
        string.format("the grind paid for the town's whole shopping list " ..
          "(%d of %d gil)", gil(), GIL_TARGET))
    end),
    -- back in at (86,111) -> map 75 (1,28)
    H.worldNavTo(86, 111, { maxFrames = 40000, playBattles = "tactical",
      arrive = function() return not H.worldMode() end }),
    H.release(),
    settleField("back in town", 75),
    H.call(function()
      H.assertEq(map(), 75, "back inside South Figaro after the grind")
      where("grind done")
      H.screenshot("sfigaro_grind_done")
    end),
  })
end

-- ------------------------------------------------- the other three shops --
-- All three doors are $F7 bump doors, so the door tile can never be the
-- goal of a navTo: CheckDoor opens the $05/$15 pair only for a party
-- standing directly below it.
local function enterDoor(mx, my, dstMap, what)
  return seq({
    H.logStep(function()
      return string.format("%s: doormat (%d,%d) -> map %d", what, mx, my, dstMap)
    end),
    H.navTo(mx, my, { maxFrames = 30000, playBattles = "flee",
                      avoid = M75_AVOID }),
    H.release(), H.waitFrames(20),
    H.call(function()
      H.assertEq(H.fieldX(), mx, what .. ": on the doormat, x=" .. mx)
      H.assertEq(H.fieldY(), my, what .. ": on the doormat, y=" .. my)
    end),
    H.driveUntil(function() return map() == dstMap end, 1800, {
      H.hold({ "up" }), H.waitFrames(8),
    }, what .. ": hold UP into the door"),
    H.release(),
    settleField(what, dstMap),
    H.call(function()
      H.assertEq(map(), dstMap, what .. ": inside map " .. dstMap)
      where(what)
    end),
  })
end

-- Leave an interior by walking back onto its arrival tile and holding DOWN
-- through the door under it.
local function leaveDoor(ax, ay, what)
  return seq({
    H.navTo(ax, ay, { maxFrames = 20000, playBattles = "flee" }),
    H.release(), H.waitFrames(20),
    H.driveUntil(function() return map() == 75 end, 1800, {
      H.hold({ "down" }), H.waitFrames(8),
    }, what .. ": back out to the town"),
    H.release(),
    settleField("back in town", 75),
  })
end

-- Stand on (sx,sy), face UP, tap A until the shop options window is up.
-- CheckNPCs reaches one tile past a counter (p1 & 7 == 7,
-- field/player.asm:188-200), which is why these talk spots are two tiles
-- below the merchant rather than adjacent to him.
local function counterShop(sx, sy, what)
  return seq({
    H.navTo(sx, sy, { maxFrames = 20000, playBattles = "flee" }),
    H.release(), H.waitFrames(20),
    H.driveUntil(inState(0x25), 6000, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        if H.fieldX() ~= sx or H.fieldY() ~= sy then H.setPad({}); return end
        if H.readByte(0x087f + H.readWord(0x0803)) ~= FACE.up then
          H.setPad({ up = true }); return
        end
        H.setPad((H.frame % 8 < 4) and { "a" } or {})
      end),
    }, what .. ": counter talk opens the shop"),
    H.release(),
    tapUntil("a", inState(0x26), what .. ": the buy list opens"),
    H.release(), H.waitFrames(20),
    H.call(function()
      local rows = {}
      for r = 0, 7 do rows[#rows + 1] = string.format("%02X", rowItem(r)) end
      H.log("[shop] " .. what .. " stock: " .. table.concat(rows, " "))
    end),
  })
end

local function closeShop(onMap, what)
  return seq({
    tapUntil("b", inState(0x25), what .. ": back to the options window"),
    tapUntil("b", function() return H.hasControl() and map() == onMap end,
      what .. ": closed"),
    H.release(), H.waitFrames(30),
  })
end

-- ------------------------------------------------------------ the equips --
-- Two menus, not one.  Equip (main menu row 2) reaches R-Hand / L-Hand /
-- Head / Body, four rows.  Relics have their own menu (main row 3) with a
-- two-slot cursor and its own state chain $59 -> $5a -> $5b.  Main menu
-- rows are Item / Skills / Equip / Relic / Status / Config / Save.
local ZM, CUR = 0x26, 0x4b
local ST_MAIN, ST_CHAR = 0x05, 0x06
local ST_EQOPT, ST_EQSLOT, ST_EQITEM = 0x36, 0x55, 0x57
local ST_RLOPT, ST_RLSLOT, ST_RLITEM = 0x59, 0x5a, 0x5b

-- char-select position of a character id, answered from $1850 rather than
-- from the menu's own $69+slot copy, which is stale on the field.  It is
-- resolved lazily because every step in an H.run list is CONSTRUCTED before
-- the boot state is loaded.
local function posOf(c)
  return function()
    for i, m in ipairs(H.partyMembers()) do
      if m == c then return i - 1 end
    end
    return 0
  end
end

local function menuEquip(mainRow, pos, slot, slotState, itemState, itemId, tag)
  local optState = (slotState == ST_EQSLOT) and ST_EQOPT or ST_RLOPT
  local ph = 0
  local function tap(btn) ph = (ph + 1) % 12; H.setPad(ph < 4 and { btn } or {}) end
  local function st() return H.readByte(ZM) end
  local function seek(state, wantIn, back, fwd, label)
    local function want()
      return type(wantIn) == "function" and wantIn() or wantIn
    end
    return H.driveUntil(function()
      return st() == state and H.readByte(CUR) == want()
    end, 1800, {
      H.call(function()
        if st() ~= state then H.setPad({}); return end
        local cur = H.readByte(CUR)
        ph = (ph + 1) % 12
        H.setPad(ph < 4 and { [cur < want() and fwd or back] = true } or {})
      end),
    }, tag .. ": " .. label)
  end
  local function press(state, label)
    return seq({
      H.driveUntil(function() return st() == state end, 1800, {
        H.call(function() tap("a") end),
      }, tag .. ": " .. label),
      H.release(), H.waitFrames(10),
    })
  end
  return seq({
    H.driveUntil(function() return st() == ST_MAIN end, 1800, {
      H.call(function() tap("x") end),
    }, tag .. ": main menu"),
    H.release(), H.waitFrames(10),
    seek(ST_MAIN, mainRow, "up", "down", "main cursor"),
    H.release(), H.waitFrames(10),
    press(ST_CHAR, "character select"),
    seek(ST_CHAR, pos, "up", "down", "character cursor"),
    H.release(), H.waitFrames(10),
    press(optState, "options row"),
    seek(optState, 0, "left", "right", "cursor on Equip"),
    H.release(), H.waitFrames(10),
    press(slotState, "slot select"),
    seek(slotState, slot, "up", "down", "slot cursor"),
    H.release(), H.waitFrames(10),
    press(itemState, "item list"),
    -- the list rows at $7e9d8a are bag indexes into $1869, so this compares
    -- the item id under the cursor rather than counting rows; the list is
    -- pre-filtered by GetValidEquip, so an un-equippable item makes the seek
    -- time out rather than equip something else
    H.driveUntil(function()
      return st() == itemState
         and H.readByte(0x1869 + H.readByte(0x9d8a + H.readByte(CUR))) == itemId
    end, 3000, {
      H.call(function()
        if st() ~= itemState then H.setPad({}); return end
        tap("down")
      end),
    }, tag .. ": list cursor on the item"),
    H.release(), H.waitFrames(10),
    H.driveUntil(function() return st() == slotState end, 1800, {
      H.call(function() tap("a") end),
    }, tag .. ": equipped, back on the slot list"),
    H.release(),
    H.driveUntil(function() return H.hasControl() end, 2400, {
      H.call(function() tap("b") end),
    }, tag .. ": back out to the field"),
    H.release(), H.waitFrames(20),
  })
end
local function equipGear(pos, slot, itemId, tag)
  return menuEquip(2, pos, slot, ST_EQSLOT, ST_EQITEM, itemId, tag)
end
local function equipRelic(pos, slot, itemId, tag)
  return menuEquip(3, pos, slot, ST_RLSLOT, ST_RLITEM, itemId, tag)
end

-- -------------------------------------------------- the relic shop + inn --
-- Both are on map 76, which is two disjoint regions joined by a same-map
-- short entrance: region A (the relic shop) is where map 75's door lands,
-- and (48,3) -> (69,10) is the only way to region B (the inn).
--
-- The relic demonstrator (NPC index 4 = object 20, spawn switch $0358)
-- stands on (51,11), the only tile the shopkeeper at {51,9} can be
-- counter-talked from.  His own scene clears $0358 and he walks off, so
-- he is talked to first.
local function talkOut(obj, done, what, budget)
  local calm, ph = 0, 0
  return seq({
    H.talkToObj(obj, what),
    H.driveUntil(function()
      local ok = H.hasControl() and H.tileAligned() and bright() >= 15
             and not H.dialogWaiting() and not H.eventRunning()
             and not H.battleLoadStarted() and done()
      calm = ok and calm + 1 or 0
      return calm >= 30
    end, budget or 20000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.hasControl() and not H.dialogWaiting() then H.setPad({}); return end
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, what .. ": ride it out"),
    H.release(),
  })
end

-- The 80 GP is paid on purpose: there is no free rest on this road.
--
-- `dlg $0B89` is "80 GP per night! Well?  0: Yes  1: No", and `take_gil 80`
-- sets $01BE when the party cannot pay, in which case the script says
-- "……Not enough money." and does not rest -- so the gold is asserted
-- before the talk rather than the rest being assumed.  The rest restores
-- full HP, full MP, and clears every other persistent status bit -- KO
-- and poison included.
local CH_SEL, CH_MAX = 0x056E, 0x056F
local function innRest(what)
  local ph, ci, calm = 0, 0, 0
  local inChoice = false
  return seq({
    H.call(function()
      H.assertEq(gil() >= 80, true, what .. ": the party can pay the 80 GP")
    end),
    H.navTo(81, 19, { maxFrames = 20000, playBattles = "flee" }),
    H.release(), H.waitFrames(20),
    H.call(function()
      H.assertEq(H.fieldX(), 81, what .. ": on the innkeeper's talk spot x=81")
      H.assertEq(H.fieldY(), 19, what .. ": on the innkeeper's talk spot y=19")
    end),
    H.driveUntil(function()
      return H.eventRunning() or H.dialogWaiting()
    end, 6000, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        if H.readByte(0x087f + H.readWord(0x0803)) ~= FACE.up then
          H.setPad({ up = true }); return
        end
        H.setPad((H.frame % 8 < 4) and { "a" } or {})
      end),
    }, what .. ": engage the innkeeper"),
    H.release(),
    H.driveUntil(function()
      local ok = H.hasControl() and H.tileAligned() and bright() >= 15
             and not H.dialogWaiting() and not H.eventRunning()
      calm = ok and calm + 1 or 0
      return calm >= 30
    end, 30000, {
      H.call(function()
        ph = (ph + 1) % 8
        local chMax = (not H.battleLoadStarted()) and H.readByte(CH_MAX) or 0
        if chMax >= 2 then
          if not H.dialogWaiting() then H.setPad({}); return end
          if not inChoice then
            inChoice = true; ci = ci + 1
            H.log(string.format(
              "%s: choice #%d up (%d options) -- taking 0 (Yes)",
              what, ci, chMax))
          end
          if H.readByte(CH_SEL) > 0 then H.setPad(ph < 4 and { "up" } or {})
          else H.setPad(ph < 4 and { "a" } or {}) end
          return
        end
        inChoice = false
        if H.hasControl() and not H.dialogWaiting() then H.setPad({}); return end
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, what .. ": the night passes"),
    H.release(), H.waitFrames(30),
  })
end

local MITHRILBLADE, HEAVYSHLD, PLUMEDHAT, STARPENDANT = 0x0A, 0x5B, 0x6B, 0xB1
local JEWELRING = 0xB5
local MITHRILKNIFE = 0x01

local function gearTrip()
  return seq({
    enterDoor(29, 19, 77, "weapon shop"),
    counterShop(103, 11, "shop 5 (weapon)"),
    buyTo(MITHRILBLADE, 2, 1, 450, "MITHRILBLADE to 1"),
    buyTo(MITHRILKNIFE, 1, 1, 300, "MITHRILKNIFE to 1"),
    closeShop(77, "shop 5"),
    leaveDoor(103, 16, "shop 5"),
    enterDoor(35, 19, 77, "armor shop"),
    counterShop(114, 12, "shop 6 (armor)"),
    buyTo(HEAVYSHLD, 1, 2, 400, "HEAVY SHLD to 2"),
    buyTo(PLUMEDHAT, 3, 2, 250, "PLUMED HAT to 2 -- one per scenario order, the Heavy Shld precedent: the Locke lineage wears one onto a head before the split hands the bag to SABIN's train"),
    closeShop(77, "shop 6"),
    leaveDoor(114, 16, "shop 6"),
    H.call(function()
      H.assertEq(invCount(MITHRILBLADE) >= 1, true,
        "the MithrilBlade is in the bag")
      H.assertEq(invCount(HEAVYSHLD) >= 2, true,
        "two Heavy Shlds cover both scenario orders")
      H.assertEq(invCount(PLUMEDHAT) >= 2, true,
        "two Plumed Hats cover SHADOW in either scenario order (#84 wave: "
        .. "one hat was worn by the Locke lineage and s2_train found the bag "
        .. "empty)")
      H.assertEq(invCount(MITHRILKNIFE) >= 1, true,
        "a spare MithrilKnife is in the bag -- nobody wears it here; it is " ..
        "LOCKE's second PIERCE weapon at TunnelArmr, past the split")
    end),
    equipGear(posOf(1), 0, MITHRILBLADE, "locke blade"),
    equipGear(posOf(1), 1, HEAVYSHLD, "locke shield"),
    H.call(function()
      H.assertEq(H.readByte(0x1600 + 37 * 1 + 0x1f), MITHRILBLADE,
        "LOCKE holds the MithrilBlade")
      H.assertEq(H.readByte(0x1600 + 37 * 1 + 0x20), HEAVYSHLD,
        "LOCKE holds the Heavy Shld")
      H.assertEq(invCount(HEAVYSHLD) >= 1, true,
        "a second Heavy Shld remains in the common bag for CYAN")
      H.assertEq(invCount(0x00) >= 1, true,
        "and his own Dirk is unequipped in the shared bag, which is what " ..
        "carries a pierce weapon into his solo scenario for TunnelArmr")
      where("locke armed")
    end),
  })
end

local function relicTrip()
  return seq({
    enterDoor(15, 39, 76, "the relic shop and the inn"),
    H.call(function()
      H.assertEq(sw(0x0358), 1,
        "$0358 set -- the relic demonstrator is standing on the talk spot")
      H.log(string.format("demonstrator (obj 20) at (%d,%d)",
        objX(20), objY(20)))
    end),
    talkOut(20, function() return sw(0x0358) == 0 end,
      "the relic demonstrator (_ca78dc)"),
    H.call(function()
      H.assertEq(sw(0x0358), 0, "the demonstrator has gone ($0358 cleared)")
    end),
    counterShop(51, 11, "shop 7 (relics)"),
    buyTo(STARPENDANT, 2, 3, 500, "STAR PENDANT to 3"),
    buyTo(JEWELRING, 3, 3, 1000, "JEWEL RING to 3"),
    closeShop(76, "shop 7"),
    H.call(function()
      H.assertEq(invCount(STARPENDANT), 3, "three Star Pendants in the bag")
      H.assertEq(invCount(JEWELRING), 3, "three Jewel Rings in the bag")
    end),
    equipRelic(posOf(0), 0, STARPENDANT, "terra pendant"),
    equipRelic(posOf(1), 0, STARPENDANT, "locke pendant"),
    equipRelic(posOf(4), 0, STARPENDANT, "edgar pendant"),
    equipRelic(posOf(0), 1, JEWELRING, "terra jewel ring"),
    equipRelic(posOf(1), 1, JEWELRING, "locke jewel ring"),
    equipRelic(posOf(4), 1, JEWELRING, "edgar jewel ring"),
    H.call(function()
      for _, c in ipairs({ 0, 1, 4 }) do
        H.assertEq(H.readByte(0x1600 + 37 * c + 0x23) == STARPENDANT
                or H.readByte(0x1600 + 37 * c + 0x24) == STARPENDANT, true,
          string.format("char %d wears a Star Pendant -- Mt Kolts cannot " ..
            "poison this party", c))
        H.assertEq(H.readByte(0x1600 + 37 * c + 0x23) == JEWELRING
                or H.readByte(0x1600 + 37 * c + 0x24) == JEWELRING, true,
          string.format("char %d wears a Jewel Ring -- Mt Kolts cannot " ..
            "petrify this party", c))
      end
      where("pendants on")
    end),
    -- region A -> region B, the inn wing
    H.navTo(48, 3, { maxFrames = 20000, playBattles = "flee",
      arrive = function() return H.fieldX() == 69 and H.fieldY() == 10 end }),
    H.release(),
    settleField("inn wing", 76),
    H.call(function()
      H.assertEq(H.fieldX(), 69, "through the staircase warp, x=69")
      H.assertEq(H.fieldY(), 10, "through the staircase warp, y=10")
    end),
    innRest("the inn"),
    H.call(function()
      where("after the night")
      for _, c in ipairs(H.partyMembers()) do
        H.assertEq(H.charHp(c), H.charMaxHp(c),
          string.format("char %d woke at full hp", c))
        H.assertEq(H.charMp(c), H.charMaxMp(c),
          string.format("char %d woke at full mp", c))
      end
      H.screenshot("sfigaro_inn")
    end),
    -- back out: region B -> region A -> map 75
    H.navTo(70, 11, { maxFrames = 20000, playBattles = "flee",
      arrive = function() return H.fieldX() == 49 and H.fieldY() == 4 end }),
    H.release(),
    settleField("relic wing", 76),
    leaveDoor(52, 14, "the inn's building"),
    H.call(function()
      H.assertEq(map(), 75, "back on map 75 with the shopping done")
      where("town stop done")
    end),
  })
end

H.run({ maxFrames = 700000 }, {
  H.loadState(CLEARED),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(H.worldMode(), true, "booted on the world map")
    H.assertEq(H.readByte(0x11fa) & 3, 2, "booted riding the chocobo")
    where("booted")
  end),

  -- ===================================================================== --
  -- PHASE 1: get off the chocobo.  Hold B; LandAirship stages the tile into
  -- $1F60/$1F61, the descent releases the exit, ExitVehicle clears $11FA
  -- and ReloadMap comes back through InitWorld with $E0/$E2 finally live.
  -- ===================================================================== --
  H.hold({ "b" }),
  H.driveUntil(function() return H.readByte(0x11fa) & 3 == 0 end, 900, {
    H.waitFrames(1),
  }, "chocobo dismount ($11FA cleared)"),
  H.release(),
  settleWorld("dismount"),
  H.call(function()
    H.assertEq(H.readByte(0x11fa) & 3, 0, "off the chocobo")
    H.assertEq(H.worldX(), H.readByte(0x1f60), "$E0 seeded from $1F60")
    H.assertEq(H.worldY(), H.readByte(0x1f61), "$E2 seeded from $1F61")
    H.assertEq(H.worldX() ~= 0 or H.worldY() ~= 0, true,
      "world position is live (InitWorld ran, not InitChoco)")
    where("dismounted")
    H.screenshot("kolts_dismount")
  end),

  -- ===================================================================== --
  -- PHASE 2: the South Figaro cave, the desert's only way south.  Four
  -- steps; the middle one is an event trigger, not an entrance, so it is
  -- driven as a plain navTo whose arrival is the map change.
  -- ===================================================================== --
  H.call(function()
    H.assertEq(sw(0x001A), 0,
      "$001A clear -> the cave's map-73/72 copy (event_main.asm:14219)")
  end),
  settleWorld("desert"),
  H.worldNavTo(73, 93, { maxFrames = 30000, playBattles = "flee",
    arrive = function() return not H.worldMode() end }),
  H.release(),
  settleField("cave mouth", 71),
  H.call(function()
    H.assertEq(map(), 71, "world (73,93) -> map 71, the cave lobby")
    where("cave lobby")
  end),
  care("cave lobby"),

  -- The guards first: they stand on the only two tiles that reach the
  -- trigger.  Stage at (10,50), directly under the one with the event, face
  -- UP, talk; the scene ends by clearing their spawn switch $0312.
  H.call(function()
    H.assertEq(sw(0x0108), 1,
      "$0108 set -- the guards recognise EDGAR (else _ca7668: cave closed)")
    H.assertEq(sw(0x0312), 1, "$0312 set -- both guards are on the map")
    H.log(string.format("guards at (%d,%d) and (%d,%d)",
      objX(18), objY(18), objX(19), objY(19)))
  end),
  talkAt(10, 50, "up", "engage the cave guard (_ca75ee)"),
  H.advanceStory(function()
    return H.hasControl() and H.tileAligned() and sw(0x0312) == 0
       and map() == 71
  end, 20000, { playBattles = "flee" }),
  H.call(function()
    H.assertEq(sw(0x0312), 0, "the guards are gone ($0312 cleared)")
    where("cave opened")
    H.screenshot("kolts_cave_guards")
  end),

  -- map 71's event trigger at (10,48)/(11,48) opens the cave (_ca5ef7); the
  -- lobby has no short entrance onward.
  H.navTo(11, 48, { maxFrames = 20000, arrive = mapChanged(),
           playBattles = "flee" }),
  H.release(),
  settleField("cave body"),
  H.call(function()
    H.assertEq(map() == 73 or map() == 70, true,
      "map 71's trigger loaded the cave body (73 or 70), got " .. map())
    where("cave body")
  end),
  care("cave body"),

  crossTo(55, 32, 72, "cave body -> cave exit hall"),

  warpTo(17, 20, 61, 56, "cave warp A"),
  warpTo(55, 57, 14, 34, "cave warp B"),

  -- map 72 (16,43) drops onto the world at (75,103), inside the southern
  -- region.  (16,42), one tile north of it, carries a harmless b-switch
  -- event the walk crosses on the way.
  H.logStep(function()
    return string.format("cave exit: (%d,%d) -> (16,43) -> world (75,103)",
      H.fieldX(), H.fieldY())
  end),
  H.navTo(16, 43, { maxFrames = 20000, playBattles = "flee",
    arrive = function() return H.worldMode() end }),
  H.release(),
  settleWorld("south region"),
  H.call(function()
    H.assertEq(H.worldMode(), true, "back on the world, south of the range")
    where("cave cleared")
    H.screenshot("kolts_cave_out")
    local p = H.worldBfs(86, 111)
    H.assertEq(p ~= nil, true, "South Figaro is reachable from here")
    local q = H.worldBfs(102, 100)
    H.assertEq(q ~= nil, true, "Mt. Kolts is reachable from here")
    H.log(string.format("south region: S.Figaro %d steps, Kolts %d steps",
      #p, #q))
  end),

  -- ===================================================================== --
  -- PHASE 3: South Figaro.  One world tile of the four that lead in
  -- ((86,111)/(85,112)/(86,112)/(85,113) -> map 75 (1,28)); generate on
  -- arrival, then leave by the x=0 column the party is already beside.
  -- ===================================================================== --
  H.worldNavTo(86, 111, { maxFrames = 30000, playBattles = "flee",
    arrive = function() return not H.worldMode() end }),
  H.release(),
  settleField("south figaro", 75),
  H.call(function()
    H.assertEq(map(), 75, "on map 75, SOUTH FIGARO")
    H.assertEq(H.fieldX(), 1, "at the west gate x=1")
    H.assertEq(H.fieldY(), 28, "at the west gate y=28")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    where("south figaro")
  end),
  care("south figaro"),
  H.call(function() H.screenshot("south_figaro") end),
  H.saveState("south_figaro.mss"),
  H.logStep(function()
    return string.format("south_figaro generated at frame %d", H.frame)
  end),

  H.openChest{ stand = {5, 31}, face = "right", bit = 24, what = "Tonic",
               item = 0xE8, nav = { playBattles = "flee", avoid = M75_AVOID } },
  H.openChest{ stand = {13, 28}, face = "right", bit = 25,
               what = "Green Cherry",
               nav = { playBattles = "flee", avoid = M75_AVOID } },
  H.openChest{ stand = {11, 24}, face = "up", bit = 231, what = "Warp Stone",
               nav = { playBattles = "flee", avoid = M75_AVOID } },

  enterDoor(15, 20, 81, "chest yard house"),
  H.navTo(16, 15, { maxFrames = 20000, playBattles = "flee",
                    avoid = { { 4, 17 }, { 16, 16 } } }),
  H.release(), H.waitFrames(20),
  H.driveUntil(function() return map() == 75 end, 1800, {
    H.hold({ "down" }), H.waitFrames(8),
  }, "chest yard: out the back door onto (23,17)"),
  H.release(),
  settleField("chest yard", 75),
  H.call(function()
    H.assertEq(map(), 75, "in the chest yard, back on map 75")
  end),
  H.openChest{ stand = {22, 19}, face = "up", bit = 20, what = "Fenix Down",
               item = 0xF0, nav = { playBattles = "flee" } },
  enterDoor(23, 17, 81, "chest yard house, back through"),
  H.navTo(4, 16, { maxFrames = 20000, playBattles = "flee",
                   avoid = { { 16, 16 }, { 4, 17 } } }),
  H.release(), H.waitFrames(20),
  H.driveUntil(function() return map() == 75 end, 1800, {
    H.hold({ "down" }), H.waitFrames(8),
  }, "chest yard: back out to the street"),
  H.release(),
  settleField("back in town", 75),
  H.call(function()
    H.assertEq(map(), 75, "back on the street with the Fenix Down")
  end),

  H.openChest{ stand = {32, 17}, face = "up", bit = 21, what = "Tonic",
               item = 0xE8, nav = { playBattles = "flee", avoid = M75_AVOID } },

  shopTrip(),

  grindTrip(),
  gearTrip(),

  -- Back to the item shop with the grind's money: the mountain is nine
  -- crossings plus the map-98 approach, and this is the last counter
  -- before the Returner Hideout.  Seven revives and thirty Tonics leave a
  -- reserve while preserving gil for the relic shop and inn below.
  enterDoor(44, 32, 85, "item shop (second visit)"),
  counterShop(106, 54, "shop 8 (item, top-up)"),
  buyTo(0xF0, 5, 7, 500, "FENIX DOWN to 7"),
  buyTo(0xE8, 0, 30, 50, "TONIC to 30"),
  closeShop(85, "shop 8"),
  leaveDoor(104, 57, "the item shop"),
  H.call(function()
    H.assertEq(invCount(0xF0) >= 6, true,
      "the mountain is walked with real revives now")
    where("restocked")
  end),

  H.openChest{ stand = {15, 46}, face = "up", bit = 22, what = "Antidote",
               item = 0xF2, nav = { playBattles = "flee", avoid = M75_AVOID } },
  H.openChest{ stand = {15, 46}, face = "down", bit = 23, what = "Eyedrop",
               nav = { playBattles = "flee", avoid = M75_AVOID } },

  relicTrip(),

  H.setRows({ [0] = true, [1] = false, [4] = true }, { tag = "rows" }),

  -- Out the way we came: x=0 is the vertical long entrance -> world
  -- (84,112).  One press, not a navTo, because the target tile is the
  -- trigger.
  H.navTo(1, 28, { maxFrames = 20000, playBattles = "flee", avoid = M75_AVOID }),
  H.release(),
  H.waitFrames(30),
  H.driveUntil(function() return H.worldMode() end, 900, {
    H.hold({ "left" }), H.waitFrames(8),
  }, "leave South Figaro (x=0 column)"),
  H.release(),
  settleWorld("back outside"),
  H.call(function() where("left south figaro") end),

  -- ===================================================================== --
  -- PHASE 4: Mt. Kolts.  World (102,100) -> map 95 (14,35).  Map 95's own
  -- exit row y=37 is two tiles south of the spawn, so every step here is
  -- pre-checked against it.
  -- ===================================================================== --
  H.worldNavTo(102, 100, { maxFrames = 40000, playBattles = "flee",
    arrive = function() return not H.worldMode() end }),
  H.release(),
  settleField("mt kolts", 95),
  H.call(function()
    H.assertEq(map(), 95, "on map 95, MT. KOLTS")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    where("kolts entry point")
  end),
  care("kolts entry point"),
  H.call(function()
    H.assertEq(invCount(0xF4) >= 2, true,
      "at least two Softs survive the South Figaro-to-Kolts journey -- " ..
      "the scenario branches still have a Petrify answer")
  end),
  H.call(function() H.screenshot("kolts_entry") end),
  H.saveState("kolts_entry.mss"),
  H.logStep(function()
    return string.format("kolts_entry generated at frame %d", H.frame)
  end),

  -- ===================================================================== --
  -- The mountain.  Nine crossings.  Map 100 is six disconnected shelves
  -- (F, D, E, B, C, A), connected only through caves 96/97/102; map 96 is
  -- itself four sub-regions (P, R, Q, S).  Shelf A -- (7,48)->98 -- has no
  -- route in from the rest of the graph; it's the way out, not in, and
  -- Vargas's walk-on parks him on top of it.  The way into the graph is a
  -- long entrance, map 96 (12,8) -> map 102 (51,46), which drops onto
  -- shelf B; B carries the summit chain 97 -> 103 -> 98.
  planAvoidsRow(11, 26, 37, "map 95 -> (11,26)"),
  crossTo(11, 26, 100, "K1 entrance -> shelf F", "tactical"),
  crossTo(19, 17, 96, "K2 shelf F -> cave 96 P", "tactical"),
  crossTo(22, 21, 100, "K3 cave 96 P -> shelf D", "tactical"),
  crossTo(34, 7, 96, "K4 shelf D -> cave 96 R", "tactical"),
  crossTo(12, 8, 102, "K5 cave 96 R -> the bridge (LONG entrance)", "tactical"),
  crossTo(35, 50, 100, "K6 bridge -> shelf B", "tactical"),
  crossTo(58, 45, 97, "K7 shelf B -> cave 97", "tactical"),
  crossTo(55, 10, 103, "K8 cave 97 -> the summit", "tactical"),
  crossTo(60, 9, 98, "K9 summit -> VARGAS's ledge", "tactical"),

  H.call(function()
    H.assertEq(map(), 98, "on map 98")
    H.assertEq(sw(0x010A), 0, "$010A still clear -- Vargas has not appeared")
    where("map 98 arrival")
  end),
  care("map 98 arrival"),
  H.navTo(11, 32, { maxFrames = 40000, playBattles = "tactical",
    reserve = { [POTION] = 5 },
    arrive = function() return sw(0x010A) == 1 end }),
  H.release(),
  H.advanceStory(function()
    return H.hasControl() and H.tileAligned() and sw(0x010A) == 1
       and objX(16) == 23 and objY(16) == 32
  end, 20000, { playBattles = "tactical", reserve = { [POTION] = 5 } }),
  H.call(function()
    H.assertEq(sw(0x010A), 1, "the approach trigger ran ($010A set)")
    H.assertEq(sw(0x031C), 1, "$031C set (Vargas NPC armed)")
    H.log(string.format("VARGAS (obj 16) at (%d,%d)", objX(16), objY(16)))
    where("vargas spawned")
    H.screenshot("vargas_spawn")
  end),
  care("vargas spawned"),

  H.navTo(22, 32, { maxFrames = 40000, playBattles = "tactical",
                    reserve = { [POTION] = 5 } }),
  H.release(),
  H.driveUntil(function()
    return H.readByte(0x087f + H.readWord(0x0803)) == 1
       and H.hasControl() and H.tileAligned()
       and H.fieldX() == 22 and H.fieldY() == 32
  end, 900, {
    H.hold({ "right" }), H.waitFrames(4),
  }, "face VARGAS (facing byte = 1)"),
  H.release(),
  H.waitFrames(30),

  care("vargas entry point", 0.95),
  H.driveUntil(function()
    return H.readByte(0x087f + H.readWord(0x0803)) == 1
       and H.hasControl() and H.tileAligned()
       and H.fieldX() == 22 and H.fieldY() == 32
  end, 900, {
    H.hold({ "right" }), H.waitFrames(4),
  }, "face VARGAS again after the care stop"),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 98, "on map 98")
    H.assertEq(H.fieldX(), 22, "party at x=22")
    H.assertEq(H.fieldY(), 32, "party at y=32")
    H.assertEq(objX(16), 23, "VARGAS at x=23, one tile east")
    H.assertEq(objY(16), 32, "VARGAS at y=32, same row")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 1, "facing RIGHT, at him")
    H.assertEq(H.battleLoadStarted(), false, "not in a battle")
    -- the tools this route carries to the fight
    H.assertEq(invCount(0xA4), 1, "BioBlaster still carried (the poison key)")
    H.assertEq(invCount(0xA3), 1, "NoiseBlaster still carried")
    H.assertEq(invCount(0xAA), 1, "AutoCrossbow still carried")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d mp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11),
          H.readWord(base + 13), H.readWord(base + 15)))
      end
    end
    for _, c in ipairs(H.partyMembers()) do
      H.assertEq(H.charHp(c) > 0, true,
        string.format("char %d reached VARGAS alive", c))
      H.assertEq(H.charHp(c) * 2 >= H.charMaxHp(c), true,
        string.format("char %d is at or above half hp (%d/%d)",
          c, H.charHp(c), H.charMaxHp(c)))
    end
    local terra = 0
    H.assertEq(H.charMaxMp(terra) > 0, true, "TERRA has an MP pool to check")
    H.assertEq(H.charMp(terra) * 3 >= H.charMaxMp(terra) * 2, true,
      string.format("TERRA reaches VARGAS with her Cure line intact " ..
        "(%d/%d mp)", H.charMp(terra), H.charMaxMp(terra)))
    -- The party also still has a way to answer a death.  gen_vargas raises
    -- TERRA after the fight; an entry point with an empty bag makes that
    -- impossible, and the failure would surface an edge later.
    H.assertEq(invCount(0xF0) >= 1, true,
      string.format("a Fenix Down is still in reserve for the fight (%d)",
        invCount(0xF0)))
    -- the rows the shop stop set are still set (nothing on this mountain
    -- rearranges the party, and if something did we want to know here)
    H.assertEq((H.readByte(0x1850 + 0) & 0x20) ~= 0, true, "TERRA back row")
    H.assertEq((H.readByte(0x1854 + 0) & 0x20) ~= 0, true, "EDGAR back row")
    H.assertEq((H.readByte(0x1851 + 0) & 0x20) == 0, true, "LOCKE front row")
    where("vargas entry point")
    H.screenshot("vargas_entry")
  end),
  H.saveState("vargas_entry.mss"),
  H.logStep(function()
    return string.format("vargas_entry generated at frame %d", H.frame)
  end),
})
