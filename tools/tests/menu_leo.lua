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
--                the Equip menu offers that sword and he wears it, and still offers the bag's weapon GOGO
--                could already wear.
-- The items are chosen from the bag and the ROM's ItemProp at run time (a weapon with Leo's bit 15 and not
-- GOGO's bit 12; a weapon with GOGO's bit 12), so the suite copes with whatever the play left in the bag.
-- Screenshots (build/states/shots/menu_leo_*): the main menu, the Status screen, the command list, the
-- weapon list.  Nothing is written.
local H = dofile("tools/tests/lib/ot6.lua")

local GOGO = 12
local REC = 0x1600 + 37 * GOGO
local SHOCK = 0x1B
local ST_MAIN, ST_CHAR, ST_STATUS, ST_CMDLIST = 0x05, 0x06, 0x0C, 0x6A
local GOGO_ROW, LEO_ROW = 12 * 22, 15 * 22                -- CharProp rows (22 bytes)
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
    if equipShot and st() == 0x57 and H.menuListSettled() then
      H.screenshot(equipShot)
      equipShot = nil
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
local equipShot = nil
local function weaponList(tag, id, res)
  return H.seqStep({
    H.call(function() equipShot = "menu_leo_" .. tag .. "_equip" end),
    H.equipWeapon(function() return gogoPos() end, id,
      { slot = 0, tag = string.format("%s: weapon $%02X", tag, id), result = res }),
    H.call(function() equipShot = nil end),
  })
end
local preList, postList, againList = {}, {}, {}
local preNew, postNew, postOld = {}, {}, {}
local pre = {}
H.run({ maxFrames = 60000 }, {
  -- ---- before the reveal ----------------------------------------------------------------------------------
  H.loadState("build/states/wor_leo_pre.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    arm()
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
  end),
  -- once picked, the list still holds Shock exactly once (his own record now holds it)
  statusList("again", 2, nil, againList),
  H.call(function()
    local n = 0
    for _, c in ipairs(againList) do if c == SHOCK then n = n + 1 end end
    H.assertEq(n, 1, "once picked: Shock still listed once (his record's own Shock is not listed again)")
  end),
  H.lazy(function() return weaponList("post", NEW, postNew) end),
  H.call(function()
    H.assertEq(postNew.found, true, string.format("after: the Equip menu offers $%02X (Leo's set)", NEW))
    H.assertEq(H.readByte(REC + 0x1F), NEW, string.format("after: he wears $%02X", NEW))
  end),
  H.lazy(function() return weaponList("old", OLD, postOld) end),
  H.call(function()
    H.assertEq(postOld.found, true, string.format("after: the Equip menu still offers $%02X (GOGO's)", OLD))
    H.log("[menu_leo] PASS: the menu shows Leo, reads his row, offers Shock and his whole set")
  end),
})
