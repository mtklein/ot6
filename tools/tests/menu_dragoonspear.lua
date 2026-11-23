-- @suite savestate=wor_leo_pre
-- menu_dragoonspear.lua -- the Dragoon Boots let the wearer equip a spear (#567, ot6_spear.asm).
--
-- Played from wor_leo_pre (the World of Ruin's Thamasa, map 344): STRAGO, who cannot hold a spear by his own
-- equip bit, and the bag's Dragoon Boots (the line's, from the Magitek factory's chest, gen_mrf_kefka) and
-- spears.  Everything goes through the real menus:
--   A. without the boots: the Equip menu's weapon list does not offer the bag's spear; the Item menu's details
--      for it do not name him; in Thamasa's weapon shop (shop 72) his sprite stands still on the Gold Lance's row
--      and jumps on a row he can wear (the Gravity Rod: the instrument's positive control).
--   B. the boots on (Relic menu, his empty relic slot): the Relic menu's re-equip (CheckReequipRelics, as for the
--      Genji Glove, Gauntlet and Merit Award) runs the game's Optimum, which hands him the bag's strongest
--      weapon he can now wear: a spear, since the bag's best spear outranks every rod and staff of his that
--      Optimum would take (Optimum skips the Imp items, equip.asm ImpItem); the Equip menu then offers another
--      spear; the Item menu's details name him; the shop's Gold Lance row makes him jump; Empty and Optimum in
--      the Equip menu give him the spear again.
--   C. the boots off (Relic menu, Remove): the re-equip runs again and leaves no spear in either hand; what he
--      holds is legal by his own equip bit; the spear is back in the bag.
-- Which spears count and which relic lends them are this suite's own spec (the owner's, #567): ids $1D-$24 and
-- the Dragoon Boots $BF, never read from the ROM's permit, so a mutant that switches the permit off goes red
-- here.  The spear and the comparison rod are chosen from the bag and ItemProp at run time.  Nothing is written.
local H = dofile("tools/tests/lib/ot6.lua")

local STRAGO = 7
local REC = 0x1600 + 37 * STRAGO
local BOOTS = 0xBF
local GOLD_LANCE, SHOP = 0x22, 72
local function isSpear(id) return id ~= nil and id >= 0x1D and id <= 0x24 end
local function st() return H.menuRunning() and H.readByte(0x26) or -1 end
local function ctl() if H.worldMode() then return H.worldHasControl() end return H.hasControl() end
local function pos()
  local b = H.readByte(0x1850 + STRAGO)
  if (b & 7) ~= H.activeParty() then return nil end
  return (b >> 3) & 3
end
local function itemProp(id, off) return H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30 + off) end
local function baseWord(id) return itemProp(id, 1) | (itemProp(id, 2) << 8) end
local function isWeapon(id) return id ~= 0xFF and (itemProp(id, 0) & 0x87) == 1 end
local function power(id) return itemProp(id, 20) end
local function ownBit(id) return (baseWord(id) >> STRAGO) & 1 == 1 end
local imp = nil
local function isImp(id)
  if imp == nil then
    imp = {}
    local t = H.sym("ImpItem") & 0x3FFFFF
    for i = 0, 15 do imp[H.readRomByte(t + i)] = true end
    imp[0xFF] = nil
  end
  return imp[id] == true
end
local function hands() return H.readByte(REC + 0x1F), H.readByte(REC + 0x20) end
local function wearsBoots() return H.readByte(REC + 0x23) == BOOTS or H.readByte(REC + 0x24) == BOOTS end

-- the weapons the game's Optimum would weigh for him (bag plus hands, Imp items out), the strongest one, by the
-- spec: his own bit, or a spear while he wears the boots
local function optimumBest(withBoots)
  local best, bp = nil, -1
  local seen = {}
  local a, b = hands()
  local pool = { a, b }
  for slot = 0, 255 do
    local id = H.readByte(0x1869 + slot)
    if id ~= 0xFF and H.readByte(0x1969 + slot) > 0 then pool[#pool + 1] = id end
  end
  for _, id in ipairs(pool) do
    if id ~= 0xFF and not seen[id] and isWeapon(id) and not isImp(id)
        and (ownBit(id) or (withBoots and isSpear(id))) then
      seen[id] = true
      if power(id) > bp then best, bp = id, power(id) end
    end
  end
  return best, bp
end

-- ---- the Equip menu's weapon list ----------------------------------------------------------------------------
local function weaponList(tag, id, res)
  return H.equipWeapon(function() return pos() end, id,
    { slot = 0, tag = string.format("%s: weapon $%02X", tag, id), result = res })
end

-- ---- the Item menu's details (menu_leo's walk): who can equip, at $7E9D89, $FF-terminated -----------------------
local function itemWho(tag, id, out)
  local ph, phase = 0, "in"
  return H.withReset(H.driveUntil(function() return phase == "done" and not H.menuRunning() and ctl() end, 20000, {
    H.call(function()
      ph = (ph + 1) % 12
      local s, held = st(), {}
      if phase == "in" then
        if s == -1 then
          if ctl() then held = { "x" } end
        elseif s == 0x05 then
          held = H.readByte(0x4B) == 0 and { "a" } or { up = true }
        elseif s == 0x08 or s == 0x19 then
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
          H.log(string.format("[spear] %s: the Item menu's details for $%02X: who can equip {%s}", tag, id,
            table.concat(out.who, ",")))
          H.screenshot("menu_dragoonspear_" .. tag .. "_itemwho")
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
local function lists(t, c) for _, v in ipairs(t or {}) do if v == c then return true end end return false end

-- ---- Thamasa's weapon shop: his sprite's pose on a row ---------------------------------------------------------
-- ShopCharSpriteTask_01 (shop.asm): while the Buy list is up, a member who can equip the row's item (_c3c19c,
-- the Ot6EquipWord site) is drawn with the jumping animation, wTaskAnimPtr = wTaskSpeedX + 9; else
-- wTaskAnimPtr = wTaskSpeedX.  The task's member is w7e35c9 at the task's offset.
local function shopPose(actor)
  local code = H.sym("ShopCharSpriteTask") & 0xFFFF
  local cp, ap, sp, who = H.sym("wTaskCodePtr"), H.sym("wTaskAnimPtr"), H.sym("wTaskSpeedX"), H.sym("w7e35c9")
  for x = 0, 0x7E, 2 do
    if H.readWord(cp + x) == code and H.readByte(who + x) == actor then
      local a, s = H.readWord(ap + x), H.readWord(sp + x)
      if a == s + 9 then return "jump" end
      if a == s then return "stand" end
      return string.format("anim %04X speed %04X", a, s)
    end
  end
  return "none"
end
local function shop(tag, rows, out)
  local ph, phase, k = 0, "buy", 1
  return H.seqStep({
    H.cond(function() return H.worldMode() end, {
      H.worldNavTo(251, 230, { maxFrames = 6000, playBattles = "tactical",
        arrive = function() return (H.mapId() & 0x1FF) == 344 and not H.worldMode() end }),
      H.waitUntil(function() return (H.mapId() & 0x1FF) == 344 and H.hasControl() end, 2400, tag .. ": Thamasa", 1),
    }, {}),
    -- (the second visit starts inside: the first one left the party at the counter)
    H.cond(function() return (H.mapId() & 0x1FF) ~= 345 end, {
      H.crossDoor(14, 37, 345, 10, 47, tag .. ": Thamasa's weapon shop 344 (14,37) -> 345"),
    }, {}),
    H.shopTalk(11, 37, tag .. ": Thamasa's weapon shop"),
    H.call(function() H.assertEq(H.shopId(), SHOP, tag .. ": the counter opened shop " .. SHOP) end),
    H.withReset(H.driveUntil(function() return phase == "done" end, 6000, {
      H.call(function()
        ph = ph + 1
        if phase == "buy" then
          H.setPad(ph > 20 and ph < 25 and { "a" } or {})
          if ph > 40 then phase, ph = "seek", 0 end
        elseif phase == "seek" then
          local want = rows[k]
          local row = H.readByte(0x4B)
          if H.readByte(0x7E9D89 + row) == want then
            H.setPad({})
            if ph >= 40 then
              local pose = shopPose(STRAGO)
              out[want] = pose
              H.log(string.format("[spear] %s: shop %d, row %d ($%02X): STRAGO's sprite %s", tag, SHOP, row, want, pose))
              H.screenshot(string.format("menu_dragoonspear_%s_shop_%02X", tag, want))
              k, ph = k + 1, 0
              if rows[k] == nil then phase = "done" end
            end
          else
            local wantRow = nil
            for r = 0, 7 do if H.readByte(0x7E9D89 + r) == want then wantRow = r end end
            if wantRow == nil then error(string.format("%s: shop %d sells no $%02X", tag, SHOP, want), 0) end
            H.setPad((ph % 12) < 3 and { [row < wantRow and "down" or "up"] = true } or {})
            if (ph % 12) == 11 then ph = 0 end
          end
        end
      end),
    }, tag .. ": the shop's rows"), function() ph, phase, k = 0, "buy", 1 end),
    H.release(),
    H.shopClose(tag .. ": Thamasa's weapon shop"),
  })
end

-- ---- Empty, then Optimum (menu_leo's walk): the game's own pick --------------------------------------------------
local function optimum(tag, out)
  local ph, phase = 0, "in"
  return H.seqStep({
    H.emptyEquip(STRAGO, { tag = tag .. ": Empty" }),
    H.withReset(H.driveUntil(function() return phase == "done" and not H.menuRunning() and ctl() end, 6000, {
      H.call(function()
        ph = (ph + 1) % 12
        local s, held = st(), {}
        if phase == "in" then
          if s == -1 then
            if ctl() then held = { "x" } end
          elseif s == 0x05 then
            held = H.readByte(0x4B) == 2 and { "a" } or { [H.readByte(0x4B) < 2 and "down" or "up"] = true }
          elseif s == 0x06 then
            local p = pos()
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

local SPEAR, OTHER = nil, nil
local ROD = 0x3A          -- the Gravity Rod: shop 72 sells it and it is STRAGO's own (asserted below)
local pre, post = {}, {}
local preWho, postWho = {}, {}
local preShop, postShop = {}, {}
local opt = {}
local onBest, spearsBefore = nil, 0
H.run({ maxFrames = 200000 }, {
  H.loadState("build/states/wor_leo_pre.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(pos() ~= nil, true, "precondition: STRAGO in the active party (gen_wor_leo seats him)")
    H.assertEq(H.invCountOf(BOOTS) > 0, true,
      "precondition: the Dragoon Boots in the bag (the Magitek factory's chest, gen_mrf_kefka)")
    for c = 0, 15 do
      local r = 0x1600 + 37 * c
      H.assertEq(H.readByte(r + 0x23) ~= BOOTS and H.readByte(r + 0x24) ~= BOOTS, true,
        string.format("precondition: nobody wears the Dragoon Boots yet (block %d)", c))
    end
    H.assertEq(H.readByte(REC + 0x23), 0xFF, "precondition: STRAGO's first relic slot is empty (the boots' slot)")
    -- the bag's spears he cannot hold by his own bit, strongest first
    local sp = {}
    for slot = 0, 255 do
      local id = H.readByte(0x1869 + slot)
      if isSpear(id) and H.readByte(0x1969 + slot) > 0 and not ownBit(id) and not isImp(id) then sp[#sp + 1] = id end
    end
    table.sort(sp, function(a, b) return power(a) > power(b) end)
    H.assertEq(#sp >= 2, true, "precondition: two kinds of spear STRAGO cannot hold by his own bit in the bag")
    SPEAR, OTHER = sp[1], sp[2]
    spearsBefore = H.invCountOf(SPEAR)
    H.assertEq(isWeapon(ROD) and ownBit(ROD), true, "the Gravity Rod is a weapon of STRAGO's own")
    H.assertEq(ownBit(GOLD_LANCE), false, "the Gold Lance is not his by his own bit")
    local best, bp = optimumBest(true)
    H.log(string.format("[spear] the bag's spears: $%02X (power %d), $%02X (power %d); with the boots Optimum's "
      .. "best for him is $%02X (power %d); without, $%s", SPEAR, power(SPEAR), OTHER, power(OTHER), best, bp,
      string.format("%02X", optimumBest(false) or 0xFF)))
    H.assertEq(isSpear(best), true, string.format("precondition: with the boots, the strongest weapon Optimum would "
      .. "give him is a spear (best $%02X): the bag's best spear outranks his own rods", best))
    onBest = best
  end),

  -- ---- A. without the boots --------------------------------------------------------------------------------------
  H.lazy(function() return weaponList("pre", SPEAR, pre) end),
  H.call(function()
    H.assertEq(pre.found, false, string.format("without the boots: the Equip menu does not offer $%02X", SPEAR))
    H.assertEq(isSpear((hands())), false, "without the boots: no spear in his hand")
  end),
  H.lazy(function() return itemWho("pre", SPEAR, preWho) end),
  H.call(function()
    H.assertEq(lists(preWho.who, STRAGO), false,
      string.format("without the boots: the Item menu does not name STRAGO for $%02X", SPEAR))
  end),
  shop("pre", { ROD, GOLD_LANCE }, preShop),
  H.call(function()
    H.assertEq(preShop[ROD], "jump", "the shop's control: STRAGO jumps on the Gravity Rod's row (his own weapon)")
    H.assertEq(preShop[GOLD_LANCE], "stand", "without the boots: he stands still on the Gold Lance's row")
  end),

  -- ---- B. the boots on ----------------------------------------------------------------------------------------
  H.equipWeapon(function() return pos() end, BOOTS, { slot = 4, tag = "the Dragoon Boots on STRAGO" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(REC + 0x23), BOOTS, "STRAGO wears the Dragoon Boots")
    local a, b = hands()
    H.log(string.format("[spear] after the Relic menu's re-equip: hands $%02X $%02X", a, b))
    H.assertEq(a, onBest, string.format("the boots on: the Relic menu's re-equip (Optimum) gave him $%02X, the "
      .. "strongest weapon he can now wear (a spear)", onBest))
  end),
  H.lazy(function() return weaponList("post", OTHER, post) end),
  H.call(function()
    H.assertEq(post.found, true, string.format("the boots on: the Equip menu offers $%02X", OTHER))
    H.assertEq(H.readByte(REC + 0x1F), OTHER, string.format("and he holds $%02X", OTHER))
  end),
  H.lazy(function() return itemWho("post", SPEAR, postWho) end),
  H.call(function()
    H.assertEq(lists(postWho.who, STRAGO), true,
      string.format("the boots on: the Item menu names STRAGO for $%02X", SPEAR))
  end),
  shop("post", { GOLD_LANCE }, postShop),
  H.call(function()
    H.assertEq(postShop[GOLD_LANCE], "jump", "the boots on: he jumps on the Gold Lance's row")
  end),
  optimum("post", opt),
  H.call(function()
    H.log(string.format("[spear] Empty, then Optimum: $%02X (power %d)", opt.weapon, power(opt.weapon)))
    H.assertEq(opt.weapon, onBest, string.format("the boots on: the Equip menu's Optimum picks $%02X, the spear", onBest))
  end),

  -- ---- C. the boots off ---------------------------------------------------------------------------------------
  H.call(function() spearsBefore = 0; for _, id in ipairs({ SPEAR, OTHER }) do spearsBefore = spearsBefore + H.invCountOf(id) end end),
  H.unequipRelics(STRAGO, { 4 }, { tag = "the Dragoon Boots off STRAGO" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(wearsBoots(), false, "STRAGO no longer wears the Dragoon Boots")
    local a, b = hands()
    H.log(string.format("[spear] after the boots came off: hands $%02X $%02X", a, b))
    H.assertEq(isSpear(a) or isSpear(b), false, "the boots off: no spear is left in either hand")
    for _, id in ipairs({ a, b }) do
      if id ~= 0xFF then
        H.assertEq(ownBit(id), true, string.format("the boots off: $%02X in hand is his by his own bit", id))
      end
    end
    local now = 0
    for _, id in ipairs({ SPEAR, OTHER }) do now = now + H.invCountOf(id) end
    H.assertEq(now, spearsBefore + 1, "the boots off: the spear he held is back in the bag")
    H.log("[spear] PASS: the boots lend a spear in the Equip menu, Optimum, the Item menu and the shop, and take "
      .. "it back when they come off")
  end),
})
