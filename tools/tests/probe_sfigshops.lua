-- probe_sfigshops.lua -- drives South Figaro's other three shops, the
-- relic equips and the inn.
--
-- It boots build/states/south_figaro.mss -- map 75 (1,28), the town's west
-- gate, TERRA + LOCKE + EDGAR -- and drives, in order:
--
--   * shop 5, the weapon shop.  Doorstep map 75 (29,19), hold UP into the
--     $F7 door at (29,17) -> map 77 (103,16); merchant {103,9}, counter
--     talk from (103,11) facing UP.  Buys a MithrilBlade ($0A, row 2, 450).
--   * shop 6, the armor shop.  Doorstep (35,19) -> map 77 (114,16);
--     merchant {114,10}, counter talk from (114,12).  Buys a Heavy Shld
--     ($5B, row 1, 400) for LOCKE's empty left hand.
--   * the two equips, through the real Equip menu.
--   * shop 7, the relic shop, and the inn, which share map 76.  The
--     doorstep is (15,39) -> map 76 (52,14), region A; the relic
--     demonstrator (NPC index 4 = object 20, spawn switch $0358) stands on
--     (51,11), the only tile the shopkeeper at {51,9} can be
--     counter-talked from, and his own scene ends `switch $0358=0`, so he
--     is talked to first and then walks off.  Region A reaches region B --
--     the inn -- only through the same-map short entrance (48,3) ->
--     (69,10).
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function seq(steps) return H.cond(function() return true end, steps) end
local FACE = { up = 0, right = 1, down = 2, left = 3 }
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end

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
local function weaponOf(c) return H.readByte(0x1600 + 37 * c + 0x1f) end
local function shieldOf(c) return H.readByte(0x1600 + 37 * c + 0x20) end
local function relic1(c) return H.readByte(0x1600 + 37 * c + 0x23) end
local function relic2(c) return H.readByte(0x1600 + 37 * c + 0x24) end

local function where(tag)
  local out = {}
  for _, c in ipairs(H.partyMembers()) do
    local b = 0x1600 + 37 * c
    out[#out + 1] = string.format("c%d L%d %d/%d hp w=%02X s=%02X r=%02X/%02X",
      c, H.readByte(b + 8), H.readWord(b + 9), H.readWord(b + 11),
      weaponOf(c), shieldOf(c), relic1(c), relic2(c))
  end
  H.log(string.format("[%s] f%d map=%d (%d,%d) gil=%d | %s", tag, H.frame,
    map(), H.fieldX(), H.fieldY(), gil(), table.concat(out, " | ")))
end

-- settle: a lit screen plus the caller's terms, held for 20 consecutive
-- frames, driven rather than waited
local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end
local function settleField(what, dstMap, maxF)
  return seq({
    H.waitFrames(60),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), maxF or 12000, { playBattles = "flee" }),
    H.waitFrames(30),
  })
end

local function tapUntil(btn, pred, what, maxF)
  return H.driveUntil(pred, maxF or 1800, {
    H.call(function() H.setPad((H.frame % 10 < 4) and { btn } or {}) end),
  }, what)
end

-- ------------------------------------------------------------- the shop --
local function mstate() return H.readByte(0x0026) end
local function shopRow() return H.readByte(0x004b) end
local function shopQty() return H.readByte(0x0028) end
local function rowItem(r) return H.readByte(0x9d89 + r) end
local function inState(v) return function() return mstate() == v end end

-- map 75's walk-onto transitions to avoid
local M75_AVOID = {
  { 8, 32 }, { 9, 32 }, { 10, 32 },        -- -> map 80
  { 18, 55 }, { 19, 55 }, { 20, 55 },      -- -> map 91
  { 48, 37 }, { 34, 35 }, { 22, 14 },      -- -> map 86
}

-- Walk to a $F7 bump door's doormat and hold UP through it.  CheckDoor
-- opens the $05/$15 pair only for a party standing directly below it, so
-- the door tile can never be the goal of a navTo.
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

-- Stand on (sx,sy), face UP, tap A until the shop options window is up.
-- CheckNPCs reaches one tile past a counter (p1 & 7 == 7), which is why
-- these talk spots are two tiles below the merchant rather than adjacent.
local function counterShop(sx, sy, what)
  return seq({
    H.navTo(sx, sy, { maxFrames = 20000, playBattles = "flee" }),
    H.release(), H.waitFrames(20),
    H.driveUntil(inState(0x25), 6000, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        if H.fieldX() ~= sx or H.fieldY() ~= sy then H.setPad({}); return end
        if facing() ~= FACE.up then H.setPad({ up = true }); return end
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

-- buyTo: the row is verified to hold the expected item before any money
-- moves, the quantity is steered and read back, and the purchase is
-- confirmed by gil falling by quantity x price.
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

-- ------------------------------------------------------------ the equips --
-- Two menus, not one.  Equip (main row 2) reaches R-Hand / L-Hand / Head /
-- Body and NOTHING else.  Relics have their own menu (main row 3) with its
-- own two-slot cursor and its own state chain $59 -> $5a -> $5b.
local ZM, CUR = 0x26, 0x4b
local ST_MAIN, ST_CHAR = 0x05, 0x06
local ST_EQOPT, ST_EQSLOT, ST_EQITEM = 0x36, 0x55, 0x57
local ST_RLOPT, ST_RLSLOT, ST_RLITEM = 0x59, 0x5a, 0x5b

-- `pos` may be a function: the char-select position is read from $1850, and
-- every step in an H.run list is CONSTRUCTED before the boot state is
-- loaded, so a position resolved at build time is read out of whatever RAM
-- the emulator happened to hold at frame 0.
local function menuEquip(mainRow, pos, optRow, slot, slotState, itemState,
                         itemId, tag)
  local ph = 0
  local function tap(btn) ph = (ph + 1) % 12; H.setPad(ph < 4 and { btn } or {}) end
  local function st() return H.readByte(ZM) end
  local function seek(state, wantIn, back, fwd, label, maxF)
    local function want()
      return type(wantIn) == "function" and wantIn() or wantIn
    end
    return H.driveUntil(function()
      return st() == state and H.readByte(CUR) == want()
    end, maxF or 1800, {
      H.call(function()
        if st() ~= state then H.setPad({}); return end
        local cur = H.readByte(CUR)
        ph = (ph + 1) % 12
        H.setPad(ph < 4 and { [cur < want() and fwd or back] = true } or {})
      end),
    }, tag .. ": " .. label)
  end
  local function press(state, label, maxF)
    return seq({
      H.driveUntil(function() return st() == state end, maxF or 1800, {
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
    press(slotState == ST_EQSLOT and ST_EQOPT or ST_RLOPT, "options row"),
    seek(slotState == ST_EQSLOT and ST_EQOPT or ST_RLOPT, optRow,
      "left", "right", "cursor on Equip"),
    H.release(), H.waitFrames(10),
    press(slotState, "slot select"),
    seek(slotState, slot, "up", "down", "slot cursor"),
    H.release(), H.waitFrames(10),
    press(itemState, "item list"),
    -- the list rows at $7e9d8a are bag indexes into $1869, so the seek
    -- compares the item id under the cursor rather than counting rows; the
    -- list is pre-filtered by GetValidEquip, so an un-equippable item makes
    -- this time out rather than equip something else
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
  return menuEquip(2, pos, 0, slot, ST_EQSLOT, ST_EQITEM, itemId, tag)
end
local function equipRelic(pos, slot, itemId, tag)
  return menuEquip(3, pos, 0, slot, ST_RLSLOT, ST_RLITEM, itemId, tag)
end

-- char-select position of a character id, answered from $1850 rather than
-- from the menu's own $69+slot copy, which is stale on the field
local function posOf(c)
  for i, m in ipairs(H.partyMembers()) do
    if m == c then return i - 1 end
  end
  return nil
end

-- ---------------------------------------------------------- the NPC talk --
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end

-- Approach a posted NPC, face it and edge-tap A until an event engages, then
-- ride the scene out to a settled, controllable field.
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

-- ------------------------------------------------------------- the inn ---
-- `dlg $0B89` is "80 GP per night! Well? 0: Yes 1: No" and `take_gil 80`
-- sets $01BE when the party cannot pay, in which case the script does not
-- rest -- so the gold is asserted before the talk rather than the rest
-- being assumed.  The rest restores `and_status {MAGITEK, INTERCEPTOR}` +
-- max_hp + max_mp on all four slots: full HP, full MP, and every other
-- persistent status bit cleared, KO and poison included.
local CH_SEL, CH_MAX = 0x056E, 0x056F
local function innRest(what)
  local ph, ci, inChoice, calm = 0, 0, false, 0
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
        if facing() ~= FACE.up then H.setPad({ up = true }); return end
        H.setPad((H.frame % 8 < 4) and { "a" } or {})
      end),
    }, what .. ": engage the innkeeper"),
    H.release(),
    -- ride the "80 GP per night!" choice: option 0 = Yes
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
            H.log(string.format("%s: choice #%d up (%d options) -- taking 0 (Yes)",
              what, ci, chMax))
          end
          local sel = H.readByte(CH_SEL)
          if sel > 0 then H.setPad(ph < 4 and { "up" } or {})
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

-- ========================================================================= --
H.run({ maxFrames = 250000 }, {
  H.loadState("build/states/south_figaro.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 75, "booted on map 75, SOUTH FIGARO")
    H.assertEq(H.hasControl(), true, "controllable")
    where("boot")
    H.log(string.format("party positions: TERRA=%s LOCKE=%s EDGAR=%s",
      tostring(posOf(0)), tostring(posOf(1)), tostring(posOf(4))))
  end),

  -- ---- shop 5, the weapon shop ----------------------------------------
  enterDoor(29, 19, 77, "weapon shop"),
  counterShop(103, 11, "shop 5 (weapon)"),
  buyTo(0x0A, 2, 1, 450, "MITHRILBLADE to 1"),
  closeShop(77, "shop 5"),
  H.navTo(103, 16, { maxFrames = 20000, playBattles = "flee" }),
  H.release(), H.waitFrames(20),
  H.driveUntil(function() return map() == 75 end, 1800, {
    H.hold({ "down" }), H.waitFrames(8),
  }, "out of the weapon shop"),
  H.release(),
  settleField("back in town", 75),
  H.call(function() where("after shop 5") end),

  -- ---- shop 6, the armor shop -----------------------------------------
  enterDoor(35, 19, 77, "armor shop"),
  counterShop(114, 12, "shop 6 (armor)"),
  buyTo(0x5B, 1, 1, 400, "HEAVY SHLD to 1"),
  closeShop(77, "shop 6"),
  H.navTo(114, 16, { maxFrames = 20000, playBattles = "flee" }),
  H.release(), H.waitFrames(20),
  H.driveUntil(function() return map() == 75 end, 1800, {
    H.hold({ "down" }), H.waitFrames(8),
  }, "out of the armor shop"),
  H.release(),
  settleField("back in town", 75),

  -- ---- LOCKE puts them on ---------------------------------------------
  H.call(function()
    H.assertEq(invCount(0x0A) >= 1, true, "the MithrilBlade is in the bag")
    H.assertEq(invCount(0x5B) >= 1, true, "the Heavy Shld is in the bag")
  end),
  equipGear(function() return posOf(1) end, 0, 0x0A, "locke blade"),
  equipGear(function() return posOf(1) end, 1, 0x5B, "locke shield"),
  H.call(function()
    H.assertEq(weaponOf(1), 0x0A, "LOCKE holds the MithrilBlade")
    H.assertEq(shieldOf(1), 0x5B, "LOCKE holds the Heavy Shld")
    H.assertEq(invCount(0x00) >= 1, true,
      "and his own Dirk is back in the shared bag")
    where("locke armed")
  end),

  -- ---- shop 7 and the inn, both on map 76 ------------------------------
  enterDoor(15, 39, 76, "the inn's door"),
  H.call(function()
    H.assertEq(sw(0x0358), 1,
      "$0358 set -- the relic demonstrator is standing on the talk spot")
    H.log(string.format("demonstrator (obj 20) at (%d,%d)", objX(20), objY(20)))
  end),
  talkOut(20, function() return sw(0x0358) == 0 end,
    "the relic demonstrator (_ca78dc)"),
  H.call(function()
    H.assertEq(sw(0x0358), 0, "the demonstrator has gone ($0358 cleared)")
    where("demonstrator gone")
  end),
  counterShop(51, 11, "shop 7 (relics)"),
  buyTo(0xB1, 2, 3, 500, "STAR PENDANT to 3"),
  closeShop(76, "shop 7"),
  H.call(function()
    H.assertEq(invCount(0xB1), 3, "three Star Pendants in the bag")
  end),
  equipRelic(function() return posOf(0) end, 0, 0xB1, "terra pendant"),
  equipRelic(function() return posOf(1) end, 0, 0xB1, "locke pendant"),
  equipRelic(function() return posOf(4) end, 0, 0xB1, "edgar pendant"),
  H.call(function()
    for _, c in ipairs({ 0, 1, 4 }) do
      H.assertEq(relic1(c) == 0xB1 or relic2(c) == 0xB1, true,
        string.format("char %d wears a Star Pendant", c))
    end
    where("pendants on")
  end),

  -- region A -> region B (the inn) through the same-map short entrance
  H.navTo(48, 3, { maxFrames = 20000, playBattles = "flee",
    arrive = function() return H.fieldX() == 69 and H.fieldY() == 10 end }),
  H.release(),
  settleField("inn wing", 76),
  H.call(function()
    H.assertEq(H.fieldX(), 69, "through the staircase warp, x=69")
    H.assertEq(H.fieldY(), 10, "through the staircase warp, y=10")
    where("inn wing")
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
  end),

  -- back out: region B -> region A -> map 75
  H.navTo(70, 11, { maxFrames = 20000, playBattles = "flee",
    arrive = function() return H.fieldX() == 49 and H.fieldY() == 4 end }),
  H.release(),
  settleField("relic wing", 76),
  H.navTo(52, 14, { maxFrames = 20000, playBattles = "flee" }),
  H.release(), H.waitFrames(20),
  H.driveUntil(function() return map() == 75 end, 1800, {
    H.hold({ "down" }), H.waitFrames(8),
  }, "out of the inn's building"),
  H.release(),
  settleField("back in town", 75),
  H.call(function()
    H.assertEq(map(), 75, "back on map 75 with the shopping done")
    where("done")
  end),
})
