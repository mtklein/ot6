-- @suite savestate=wor_leo
-- menu_leo.lua -- the field menu before and after Leo's reveal (#552, docs/design/leo-reveal.md).
--
-- Two of gen_wor_leo's states, each played through the real menu (X, the cursor, A):
--   wor_leo_pre  Thamasa's street with GOGO seated, before the grave: the Status screen's command list for GOGO
--                holds no Shock ($1B), the Status screen read GOGO's battle-stat row (CharProp row 12) and not
--                Leo's, and the Equip menu's weapon list for him does not offer the bag's sword of Leo's set
--                that GOGO could not wear;
--   wor_leo      on the world map after the reveal and its save: the main menu loads Leo's portrait for the
--                slot (PortraitGfxPtrs entry $10 read, the record's graphics byte $10, the name LEO), the
--                Status screen reads Leo's row (CharProp row 15: battle power, defense, magic defense, evade,
--                magic block) and its command list ends in Shock, picked into his second row ($1617 = $1B);
--                the Item menu's details for that sword list slot 12 (before: not), the Equip menu offers it
--                and he wears it; Thamasa's weapon shop draws him in Leo's sprite and palette (before: GOGO's), and still offers the bag's weapon GOGO
--                could already wear.
-- Then Empty and Optimum: the game's own pick for him is a weapon he can wear, at least as strong as any GOGO
-- alone could, and from Leo's set when that set holds the stronger.
-- The items are chosen from the bag and the ROM's ItemProp at run time (a weapon with Leo's bit 15 and not
-- GOGO's bit 12; a weapon with GOGO's bit 12), so the suite copes with whatever the play left in the bag.
-- With a full roster the list is 16 rows, one past vanilla's 15: the 16th is drawn on BG3 screen D's row 0, where
-- the status menu's HDMA shows the cursor's 16th position (the cells there change from before the reveal).
-- Screenshots (build/states/shots/menu_leo_*): the main menu, the Status screen, the command list, the
-- weapon list.  Nothing is written.
local H = dofile("tools/tests/lib/ot6.lua")

local GOGO = 12
local REC = 0x1600 + 37 * GOGO
local SHOCK = 0x1B
local ST_MAIN, ST_CHAR, ST_STATUS, ST_CMDLIST = 0x05, 0x06, 0x0C, 0x6A
local GOGO_ROW, LEO_ROW = 12 * 22, 15 * 22                -- CharProp rows (22 bytes)
local ROW16 = 0x7E7849 + 0x1800                           -- wBG3Tiles::ScreenD (menu_ram.inc)
local function st() return H.menuRunning() and H.readByte(0x26) or -1 end
local function ctl() if H.worldMode() then return H.worldHasControl() end return H.hasControl() end
local function cmdByte(row) return H.readByte(REC + 0x16 + row) end
local function gogoPos()
  local b = H.readByte(0x1850 + GOGO)
  if (b & 7) ~= H.activeParty() then return nil end
  return (b >> 3) & 3
end

-- ROM reads of the battle-stat bytes (CharProp+10..+14) of a row, counted
local rowReads = { [GOGO_ROW] = 0, [LEO_ROW] = 0 }
local equipShot, equipFrames = nil, 0     -- the Equip list's screenshot (weaponList)
local portraitLeo = 0
local armed = false
local function arm()
  if armed then return end
  armed = true
  local cp = H.sym("CharProp")
  for row in pairs(rowReads) do
    emu.addMemoryCallback(function() rowReads[row] = rowReads[row] + 1 end, emu.callbackType.read,
      cp + row + 10, cp + row + 14)
  end
  emu.addEventCallback(function()
    if equipShot and H.menuRunning() and H.readByte(0x26) == 0x57 then
      equipFrames = equipFrames + 1
      if equipFrames == 30 then
        H.screenshot(equipShot)
        equipShot = nil
      end
    end
  end, emu.eventType.endFrame)
  local pp = H.sym("PortraitGfxPtrs@menu_code") + 2 * 0x10
  emu.addMemoryCallback(function() portraitLeo = portraitLeo + 1 end, emu.callbackType.read, pp, pp + 1)
end

-- the bag's weapons, by who can wear them (ItemProp: type byte & 7 = 1 weapon; +1 the equip word)
local function itemProp(id, off) return H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30 + off) end
local function bagWeapon(pred)
  for slot = 0, 255 do
    local id = H.readByte(0x1869 + slot)
    if id ~= 0xFF and H.readByte(0x1969 + slot) > 0 and (itemProp(id, 0) & 7) == 1 then
      local mask = itemProp(id, 1) | (itemProp(id, 2) << 8)
      if pred(mask) then return id end
    end
  end
  return nil
end
local NEW, OLD = nil, nil

-- the Status screen and GOGO's command list (gen_wor_gogo's gogoCommands, with a look at the list): main menu
-- row 4 (Status), his party position, A on command row `row`, then `pick` (a command id) chosen in the list,
-- or B out of the list when pick is nil; `seen` gets the list
local function statusList(tag, row, pick, seen)
  local ph, phase, shotS, shotL = 0, "in", false, false
  return H.withReset(H.seqStep({
    H.driveUntil(function() return phase == "done" and not H.menuRunning() and ctl() end, 6000, {
      H.call(function()
        ph = (ph + 1) % 12
        local s, held = st(), {}
        if phase == "in" then
          if s == -1 then
            if ctl() then held = { "x" } end
          elseif s == ST_MAIN then
            held = H.readByte(0x4B) == 4 and { "a" } or { [H.readByte(0x4B) < 4 and "down" or "up"] = true }
          elseif s == ST_CHAR then
            local p = gogoPos()
            if p == nil then error(tag .. ": GOGO's slot is not in the active party", 0) end
            held = H.readByte(0x4B) == p and { "a" } or { [H.readByte(0x4B) < p and "down" or "up"] = true }
          elseif s == ST_STATUS then
            if not shotS and ph == 0 then shotS = true; H.screenshot("menu_leo_" .. tag .. "_status") end
            if shotS then
              held = H.readByte(0x4B) == row and { "a" } or { [H.readByte(0x4B) < row and "down" or "up"] = true }
            end
          elseif s == ST_CMDLIST then
            local n = H.readByte(0x7E9D89)
            if #seen == 0 then
              for r = 0, n - 1 do seen[#seen + 1] = H.readByte(0x7E9D8A + r) end
              local t = {}
              for _, c in ipairs(seen) do t[#t + 1] = string.format("%02X", c) end
              H.log(string.format("[menu_leo] %s: GOGO's command list (%d): %s", tag, n, table.concat(t, " ")))
              -- the 16th row's text cells: BG3 screen D's row 0 (Ot6LeoRow16), the 64x64 map's row 32
              local cells = {}
              for i = 0, 13 do cells[#cells + 1] = string.format("%02X", H.readByte(ROW16 + i)) end
              seen.row16 = table.concat(cells, "")
            end
            if not shotL and ph == 0 then shotL = true; H.screenshot("menu_leo_" .. tag .. "_cmdlist") end
            if shotL then
              if pick == nil then
                phase = "out"
              else
                local want = nil
                for r = 0, n - 1 do if H.readByte(0x7E9D8A + r) == pick then want = r end end
                if want == nil then error(string.format("%s: command $%02X is not in the list", tag, pick), 0) end
                held = H.readByte(0x4B) == want and { "a" } or { [H.readByte(0x4B) < want and "down" or "up"] = true }
              end
            end
          end
          if pick ~= nil and cmdByte(row) == pick and s ~= ST_CMDLIST then phase = "out" end
        end
        if phase == "out" then
          if s == -1 then phase = "done" else held = { "b" } end
        end
        if ph < 4 then H.setPad(held) else H.setPad({}) end
      end),
    }, tag .. ": the Status screen and GOGO's command list"),
    H.release(),
  }), function() ph, phase, shotS, shotL = 0, "in", false, false end)
end

-- the Equip menu's weapon list: equipWeapon reports whether the item was offered (opts.result.found) and,
-- when it was, equips it; a screenshot the first frame the list is up and settled
local function weaponList(tag, id, res)
  return H.seqStep({
    H.call(function() equipShot, equipFrames = "menu_leo_" .. tag .. "_equip", 0 end),
    H.equipWeapon(function() return gogoPos() end, id,
      { slot = 0, tag = string.format("%s: weapon $%02X", tag, id), result = res }),
    H.call(function() equipShot = nil end),
  })
end
-- the Item menu's details for an item (main menu row 0, the list's cursor $4B on its bag slot, A): an item a
-- character can wear shows who can (item.asm @8515: the actor ids at $7E9D89, $FF-terminated); `out.who` gets them
local function itemWho(tag, id, out)
  local ph, phase = 0, "in"
  -- the list is one column of 256 rows a press each (lib ot6_field.lua: 12 frames a press): a long walk
  return H.withReset(H.driveUntil(function() return phase == "done" and not H.menuRunning() and ctl() end, 20000, {
    H.call(function()
      ph = (ph + 1) % 12
      local s, held = st(), {}
      if phase == "in" then
        if s == -1 then
          if ctl() then held = { "x" } end
        elseif s == ST_MAIN then
          held = H.readByte(0x4B) == 0 and { "a" } or { up = true }
        elseif s == 0x08 or s == 0x19 then
          -- $08 the list; A picks the slot up ($19), and A again on the same slot uses it: the details
          local slot = H.invSlotOf(id)
          if slot == nil then error(tag .. string.format(": $%02X is not in the bag", id), 0) end
          held = H.readByte(0x4B) == slot and { "a" } or { [H.readByte(0x4B) < slot and "down" or "up"] = true }
        elseif s == 0x64 and ph == 0 then
          out.who = {}
          for i = 0, 15 do
            local c = H.readByte(0x7E9D89 + i)
            if c == 0xFF then break end
            out.who[#out.who + 1] = c
          end
          H.log(string.format("[menu_leo] %s: the Item menu's details for $%02X: who can equip {%s}", tag, id,
            table.concat(out.who, ",")))
          H.screenshot("menu_leo_" .. tag .. "_itemwho")
          phase = "out"
        end
      end
      if phase == "out" then
        if s == -1 then phase = "done" else held = { "b" } end
      end
      if ph < 4 then H.setPad(held) else H.setPad({}) end
    end),
  }, tag .. ": the Item menu's details"), function() ph, phase = 0, "in" end)
end
-- Thamasa's weapon shop (344 (14,37) -> 345, shop 72; its first row, $3E, is of Leo's set and not GOGO's): Buy,
-- the list's cursor on its first row, where each seated member's sprite stands in the can-equip pose or not;
-- `out` counts the ROM reads of the revealed Leo's shop animation (Ot6ShopLeoAnim) and of Leo's sheet's
-- frames (map sprite graphics $10, the offsets LoadShopCharGfx loads: Ot6LeoShopGfx)
local shopReads = { anim = 0, sheet = 0 }
local function shopArm()
  local a = H.sym("Ot6ShopLeoAnim")
  emu.addMemoryCallback(function() shopReads.anim = shopReads.anim + 1 end, emu.callbackType.read, a, a + 1)
  local sp = H.sym("Ot6ShopLeoSprite")
  emu.addMemoryCallback(function() shopReads.anim = shopReads.anim + 1 end, emu.callbackType.read, sp, sp + 8)
  local sheet = 0xD50000 + 0x10 * 0x16A0 + 0x3C0
  emu.addMemoryCallback(function() shopReads.sheet = shopReads.sheet + 1 end, emu.callbackType.read, sheet, sheet + 0x1F)
end
local function shop(tag, out)
  local ph, phase = 0, "buy"
  return H.seqStep({
    H.cond(function() return H.worldMode() end, {
      H.worldNavTo(251, 230, { maxFrames = 6000, playBattles = "tactical",
        arrive = function() return (H.mapId() & 0x1FF) == 344 and not H.worldMode() end }),
      H.waitUntil(function() return (H.mapId() & 0x1FF) == 344 and H.hasControl() end, 2400, tag .. ": Thamasa", 1),
    }, {}),
    H.crossDoor(14, 37, 345, 10, 47, tag .. ": Thamasa's weapon shop 344 (14,37) -> 345"),
    H.call(function() shopReads.anim, shopReads.sheet = 0, 0 end),
    H.shopTalk(11, 37, tag .. ": Thamasa's weapon shop"),
    H.call(function() H.assertEq(H.shopId(), 72, tag .. ": the counter opened shop 72") end),
    H.withReset(H.driveUntil(function() return phase == "done" end, 1800, {
      H.call(function()
        ph = ph + 1
        if phase == "buy" then
          -- the shop's first window: Buy is its first row; one A opens the list on its first row
          H.setPad(ph > 20 and ph < 25 and { "a" } or {})
          if ph > 40 then phase, ph = "look", 0 end
        elseif phase == "look" then
          H.setPad({})
          if ph == 60 then
            H.screenshot("menu_leo_" .. tag .. "_shop")
            out.anim, out.sheet = shopReads.anim, shopReads.sheet
            H.log(string.format("[menu_leo] %s: the shop's list, row 0 ($%02X): Ot6ShopLeoAnim read %d, Leo's "
              .. "sheet read %d", tag, H.readByte(0x1869), out.anim, out.sheet))
            phase = "done"
          end
        end
      end),
    }, tag .. ": the shop's list"), function() ph, phase = 0, "buy" end),
    H.release(),
    H.shopClose(tag .. ": Thamasa's weapon shop"),
  })
end

-- Empty (H.emptyEquip), then Optimum (the Equip menu's options row, column 1, A): what the game's own pick puts
-- on him; `out` gets his weapon after it
local function optimum(tag, out)
  local ph, phase = 0, "in"
  return H.seqStep({
    H.emptyEquip(GOGO, { tag = tag .. ": Empty" }),
    H.withReset(H.driveUntil(function() return phase == "done" and not H.menuRunning() and ctl() end, 6000, {
      H.call(function()
        ph = (ph + 1) % 12
        local s, held = st(), {}
        if phase == "in" then
          if s == -1 then
            if ctl() then held = { "x" } end
          elseif s == ST_MAIN then
            held = H.readByte(0x4B) == 2 and { "a" } or { [H.readByte(0x4B) < 2 and "down" or "up"] = true }
          elseif s == ST_CHAR then
            local p = gogoPos()
            held = H.readByte(0x4B) == p and { "a" } or { [H.readByte(0x4B) < p and "down" or "up"] = true }
          elseif s == 0x36 then
            if H.readByte(REC + 0x1F) ~= 0xFF then
              phase = "out"
            else
              held = H.readByte(0x4B) == 1 and { "a" } or { [H.readByte(0x4B) < 1 and "right" or "left"] = true }
            end
          end
        end
        if phase == "out" then
          if s == -1 then phase = "done" else held = { "b" } end
        end
        if ph < 4 then H.setPad(held) else H.setPad({}) end
      end),
    }, tag .. ": Optimum"), function() ph, phase = 0, "in" end),
    H.call(function() out.weapon = H.readByte(REC + 0x1F) end),
  })
end

local function lists(t, c) for _, v in ipairs(t or {}) do if v == c then return true end end return false end

local preList, postList, againList = {}, {}, {}
local preWho, postWho = {}, {}
local preShop, postShop = {}, {}
local opt = {}
local preNew, postNew, postOld = {}, {}, {}
local pre = {}
H.run({ maxFrames = 120000 }, {
  -- ---- before the reveal ----------------------------------------------------------------------------------
  H.loadState("build/states/wor_leo_pre.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    arm()
    shopArm()
    H.assertEq(H.readByte(REC + 1), 0x0C, "before: slot 12 wears GOGO's sprite")
    H.assertEq(gogoPos() ~= nil, true, "before: GOGO in the active party")
    NEW = bagWeapon(function(m) return (m & 0x8000) ~= 0 and (m & 0x1000) == 0 end)
    OLD = bagWeapon(function(m) return (m & 0x1000) ~= 0 end)
    H.assertEq(NEW ~= nil and OLD ~= nil, true, "the bag holds a weapon of Leo's set GOGO cannot wear, and one he can")
    H.log(string.format("[menu_leo] the bag's weapons: $%02X (Leo's set, not GOGO's), $%02X (GOGO's)", NEW, OLD))
    rowReads[GOGO_ROW], rowReads[LEO_ROW] = 0, 0
  end),
  statusList("pre", 1, nil, preList),
  H.call(function()
    pre.gogo, pre.leo = rowReads[GOGO_ROW], rowReads[LEO_ROW]
    H.log(string.format("[menu_leo] pre: CharProp battle-stat reads: GOGO's row %d, Leo's row %d", pre.gogo, pre.leo))
    H.assertEq(pre.gogo > 0, true, "before: the Status screen read GOGO's battle-stat row")
    H.assertEq(pre.leo, 0, "before: the Status screen did not read Leo's")
    for _, c in ipairs(preList) do H.assertEq(c ~= SHOCK, true, "before: the command list holds no Shock") end
  end),
  H.lazy(function() return weaponList("pre", NEW, preNew) end),
  H.call(function()
    H.assertEq(preNew.found, false, string.format("before: the Equip menu does not offer $%02X", NEW))
  end),
  H.lazy(function() return itemWho("pre", NEW, preWho) end),
  shop("pre", preShop),
  H.call(function()
    H.assertEq(preShop.anim, 0, "before: the shop draws GOGO's own sprite (Ot6ShopLeoAnim unread)")
    H.assertEq(preShop.sheet, 0, "before: and loads no frame of Leo's sheet")
  end),
  H.call(function()
    H.assertEq(lists(preWho.who, GOGO), false, string.format("before: the Item menu does not list GOGO for $%02X", NEW))
  end),

  -- ---- after the reveal -----------------------------------------------------------------------------------
  H.loadState("build/states/wor_leo.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(REC + 1), 0x10, "after: slot 12 wears Leo's sprite")
    portraitLeo, rowReads[GOGO_ROW], rowReads[LEO_ROW] = 0, 0, 0
  end),
  H.driveUntil(function() return st() == ST_MAIN end, 1200, { H.pressButtons({ "x" }, 4), H.waitFrames(30) },
    "after: the main menu"),
  H.waitFrames(40),
  H.call(function()
    H.screenshot("menu_leo_post_main")
    H.log(string.format("[menu_leo] post: the main menu read Leo's portrait pointer %d time(s)", portraitLeo))
    H.assertEq(portraitLeo > 0, true, "after: the main menu loads Leo's portrait (PortraitGfxPtrs entry $10)")
    local nm = {}
    for i = 2, 7 do nm[#nm + 1] = string.format("%02X", H.readByte(REC + i)) end
    H.assertEq(table.concat(nm, " "), "8B 84 8E FF FF FF", "after: the slot's name is LEO")
  end),
  H.driveUntil(function() return not H.menuRunning() and ctl() end, 1200,
    { H.pressButtons({ "b" }, 4), H.waitFrames(30) }, "after: out of the main menu"),
  statusList("post", 1, SHOCK, postList),
  H.call(function()
    H.log(string.format("[menu_leo] post: CharProp battle-stat reads: GOGO's row %d, Leo's row %d",
      rowReads[GOGO_ROW], rowReads[LEO_ROW]))
    H.assertEq(rowReads[LEO_ROW] > 0, true, "after: the Status screen read Leo's battle-stat row")
    H.assertEq(rowReads[GOGO_ROW], 0, "after: and not GOGO's")
    H.assertEq(postList[#postList], SHOCK, "after: the command list ends in Shock")
    local n = 0
    for _, c in ipairs(postList) do if c == SHOCK then n = n + 1 end end
    H.assertEq(n, 1, "after: Shock listed once")
    H.assertEq(#postList, #preList + 1, "after: the list is the one before plus Shock")
    H.assertEq(cmdByte(1), SHOCK, "after: Shock picked into his second command row ($1617)")
    H.log(string.format("[menu_leo] the 16th row's cells (BG3 screen D, row 0): before %s, after %s", preList.row16,
      postList.row16))
    if #postList == 16 then
      H.assertEq(postList.row16 ~= preList.row16, true, "after: the 16th row (Shock) is drawn where the HDMA shows "
        .. "the cursor's 16th position (BG3 screen D's row 0)")
    end
  end),
  -- once picked, the list still holds Shock exactly once (his own record now holds it)
  statusList("again", 2, nil, againList),
  H.call(function()
    local n = 0
    for _, c in ipairs(againList) do if c == SHOCK then n = n + 1 end end
    H.assertEq(n, 1, "once picked: Shock still listed once (his record's own Shock is not listed again)")
  end),
  H.lazy(function() return itemWho("post", NEW, postWho) end),
  H.call(function()
    H.assertEq(lists(postWho.who, GOGO), true, string.format("after: the Item menu lists slot 12 for $%02X", NEW))
  end),
  H.lazy(function() return weaponList("post", NEW, postNew) end),
  H.call(function()
    H.assertEq(postNew.found, true, string.format("after: the Equip menu offers $%02X (Leo's set)", NEW))
    H.assertEq(H.readByte(REC + 0x1F), NEW, string.format("after: he wears $%02X", NEW))
  end),
  H.lazy(function() return weaponList("old", OLD, postOld) end),
  shop("post", postShop),
  H.call(function()
    H.assertEq(postShop.anim > 0, true, "after: the shop draws the slot with Leo's animation (Leo's palette)")
    H.assertEq(postShop.sheet > 0, true, "after: from Leo's sheet")
  end),
  optimum("post", opt),
  H.call(function()
    -- the bag's strongest weapon (ItemProp+20, its power) GOGO could wear, and the strongest of Leo's set
    local best = { gogo = 0, leo = 0 }
    for slot = 0, 255 do
      local id = H.readByte(0x1869 + slot)
      if id ~= 0xFF and H.readByte(0x1969 + slot) > 0 and (itemProp(id, 0) & 7) == 1 then
        local m, pw = itemProp(id, 1) | (itemProp(id, 2) << 8), itemProp(id, 20)
        if (m & 0x1000) ~= 0 then best.gogo = math.max(best.gogo, pw) end
        if (m & 0x8000) ~= 0 then best.leo = math.max(best.leo, pw) end
      end
    end
    local w = opt.weapon
    local m = itemProp(w, 1) | (itemProp(w, 2) << 8)
    H.log(string.format("[menu_leo] Optimum: weapon $%02X (power %d, mask $%04X); the bag's best GOGO could wear %d, "
      .. "the best of Leo's set %d", w, itemProp(w, 20), m, best.gogo, best.leo))
    H.assertEq((m & 0x9000) ~= 0, true, "Optimum put on a weapon he can wear")
    H.assertEq(itemProp(w, 20) >= best.gogo, true, "and one at least as strong as any GOGO alone could wear")
    if best.leo > best.gogo then
      H.assertEq((m & 0x8000) ~= 0, true, "Optimum reached into Leo's set when it held the stronger weapon")
    end
  end),
  H.call(function()
    H.assertEq(postOld.found, true, string.format("after: the Equip menu still offers $%02X (GOGO's)", OLD))
    H.log("[menu_leo] PASS: the menu shows Leo, reads his row, offers Shock and his whole set")
  end),
})
