-- probe_gaufeed.lua -- measurement instrument for #75's honest Gau feed.
-- It routes falls_done -> Mobliz -> Veldt through controller input, switches
-- Battle Mode to Active through Config, and wins the final monster with
-- Cyan's delayed Retort while a party member is parked in Item targeting.
--
-- The measured engine wrinkle is two-stage targeting.  GauAppears first makes
-- Gau a one-shot $2f4e target, before UpdateDead has placed him in $3a42.  An
-- item submitted in that state has no valid target, but its completed action
-- normalizes Gau into an ordinary present enemy-character and opens a fresh
-- party menu.  The probe therefore parks a Tonic for the normalizing action,
-- preserves Dried Meat, then selects and submits Dried Meat from the fresh
-- menu.  AIScript::_370 consumes it, sets battle switch 13, and recruits Gau
-- in the same encounter.  All gameplay changes are controller input; RAM is
-- observed only, apart from ordinary savestate capture/reload acceleration.
-- Everything here is pad presses and RAM reads; the only state ops are
-- savestate capture/reload, the same accelerator every gen uses.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/falls_done.mss.lua"
local FAST_STAGE = false
local ZMENUSTATE, MAIN_MENU, CONFIG_MENU = 0x26, 0x05, 0x0E

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local function monHP(i) return H.readWord(0x3BFC + i * 2) end
local function liveMonsters()
  local n, hp = 0, 0
  for i = 0, 5 do
    if monPresent(i) and monHP(i) > 0 then
      n, hp = n + 1, hp + monHP(i)
    end
  end
  return n, hp
end
local DRIED_MEAT, TONIC, POTION, TINCTURE, ETHER, FENIX_DOWN =
  0xFE, 0xE8, 0xE9, 0xEB, 0xEC, 0xF0
local function mstateMenu() return H.readByte(0x0026) end
local function inState(s) return function() return mstateMenu() == s end end
local function invSlot(id)
  for i = 0, 255 do
    if H.readByte(0x1869 + i) == id then return i end
  end
  return nil
end
local function invCount(id)
  local i = invSlot(id)
  return i and H.readByte(0x1969 + i) or 0
end
local function gil()
  return H.readByte(0x1860) + (H.readByte(0x1861) << 8)
       + (H.readByte(0x1862) << 16)
end

-- battle-menu model (battle_vargas / gen_sabin_train's map; all READS)
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_ITEM, ST_TGT, ST_TOOLS = 0x05, 0x0A, 0x38, 0x30
local CMD_ITEM, CMD_SWDTECH, CMD_BLITZ = 0x01, 0x07, 0x0A
local RETORT, PUMMEL, SUPLEX = 0x56, 0x5D, 0x5F
local CMDTBL, CMDROW, ITEMLIST = 0x202E, 0x890F, 0x4005
local ITEMSCR, ITEMROW = 0x8947, 0x894F
local BLCOL, BLROW = 0x8963, 0x8967
local BATTINV = 0x2686
local TGTCHARS, TGTMONS = 0x7B7D, 0x7B7E
local BP = 0x3E9C
local function pHP(e) return H.readWord(0x3BF4 + e * 2) end
local function pMaxHP(e) return H.readWord(0x3C1C + e * 2) end
local function pMP(e) return H.readWord(0x3C08 + e * 2) end
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("%d/%d", pHP(e), pMaxHP(e))
  end
  return table.concat(p, " ")
end
local function cmdRowOf(actor, cmdId)
  for i = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + i * 3) == cmdId then return i end
  end
  return nil
end
local function battInvIdx(id)
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == id
       and H.readByte(BATTINV + i * 5 + 3) > 0 then return i end
  end
  return nil
end
-- $2f4e is battle-module scratch and retains arbitrary nonzero bytes on the
-- world map, then reads $ff during the post-battle ownership gap.  Gau is on
-- stage only when the targettable-character and enemy-character masks agree
-- on a real, initialized character bit.  He is not monster slot 5: the old
-- monPresent(5) gate is what hid every usable command-menu frame.
local function gauOn()
  local targettable = H.readByte(0x2f4e)
  local enemyChar = H.readByte(0x3a40)
  return targettable ~= 0xff and enemyChar ~= 0xff
     and (targettable & enemyChar) ~= 0
end
-- The first action after GauAppears runs UpdateDead.  That converts Gau from
-- the one-shot $2f4e "can be targeted" exception into an ordinary present
-- enemy-character: $2f4e clears, while his character entity gains $3aa0.0 and
-- remains in $3a40.  This is not Gau leaving; it is the target model becoming
-- internally consistent for subsequent actions.
local function gauPresent()
  local slot = H.readByte(0x300b)
  if slot == 0xff or slot > 6 then return false end
  local mask = H.readByte(0x3018 + slot)
  return (H.readByte(0x3aa0 + slot) & 1) ~= 0
     and (H.readByte(0x3a40) & mask) ~= 0
end
local function fedSwitch() return (H.readByte(0x3EBD) & 0x02) ~= 0 end

-- one compact engine-state line for the observation log
local function engineLine()
  local slots = {}
  for e = 0, 3 do
    slots[#slots + 1] = string.format("s%d[id=%02X fl=%02X atb=%02X act=%02X]",
      e, H.readByte(0x3ed8 + e * 2), H.readByte(0x3aa0 + e * 2),
      H.readByte(0x3219 + e * 2), H.readByte(0x32cc + e * 2))
  end
  local mons = 0
  for i = 0, 5 do if monPresent(i) then mons = mons | (1 << i) end end
  return string.format(
    "MENU=%02X st=%02X actor=%02X b0=%02X b1=%02X 2f4e=%02X%02X " ..
    "3a40=%02X 3a42=%02X 3a74=%02X 3a76=%02X 3a77=%02X 3a46=%02X " ..
    "imm=%02X monP=%02X %s hp[%s]",
    H.readByte(MENU), H.readByte(MSTATE), H.readByte(ACTOR),
    H.readByte(0x00b0), H.readByte(0x00b1),
    H.readByte(0x2f4f), H.readByte(0x2f4e),
    H.readByte(0x3a40), H.readByte(0x3a42), H.readByte(0x3a74),
    H.readByte(0x3a76), H.readByte(0x3a77), H.readByte(0x3a46),
    H.readByte(0x340a), mons, table.concat(slots, " "), partyLine())
end

local function settle(toMap, what)
  local phase = 0
  return H.cond(function() return true end, {
    H.driveUntil(function()
      return mapIdx() == toMap and H.hasControl() and H.tileAligned()
         and bright() >= 15
    end, 5000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(H.dialogWaiting() and phase < 4 and { "a" } or {})
      end),
    }, what),
    H.waitFrames(20),
    H.call(function()
      H.log(string.format("[gaufeed] %s: map=%d (%d,%d)", what, mapIdx(),
        H.fieldX(), H.fieldY()))
    end),
  }, {})
end

local function tapUntil(btn, pred, what, budget)
  local phase = 0
  return H.driveUntil(pred, budget or 1500, {
    H.call(function()
      phase = (phase + 1) % 8
      H.setPad(phase < 4 and { btn } or {})
    end),
  }, what)
end

-- Put Dried Meat in field-inventory slot 0 through the ordinary Item/Use
-- move UI.  Battle inventory preserves field order, so this removes seventeen
-- cursor steps from Gau's short live-arrival window without touching state.
local function moveMeatToFront()
  local phase = 0
  local function driveCursor(state, target, what)
    return H.driveUntil(function()
      return H.readByte(ZMENUSTATE) == state and H.readByte(0x4B) == target
    end, 2400, {
      H.call(function()
        phase = (phase + 1) % 8
        local cur = H.readByte(0x4B)
        local btn = cur < target and "down" or "up"
        H.setPad(phase < 4 and { [btn] = true } or {})
      end),
    }, what)
  end
  return H.cond(function() return invSlot(DRIED_MEAT) ~= 0 end, {
    H.pressButtons({ "x" }, 4),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == MAIN_MENU end,
      600, "main menu for inventory move", 5),
    driveCursor(MAIN_MENU, 0, "main-menu cursor on Item"),
    H.pressButtons({ "a" }, 1),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x08 end,
      1200, "field item list", 5),
    H.driveUntil(function()
      return H.readByte(ZMENUSTATE) == 0x08
         and H.readByte(0x4B) == invSlot(DRIED_MEAT)
    end, 4000, {
      H.call(function()
        phase = (phase + 1) % 8
        local cur, want = H.readByte(0x4B), invSlot(DRIED_MEAT)
        H.setPad(phase < 4 and
          { [cur < want and "down" or "up"] = true } or {})
      end),
    }, "field cursor on Dried Meat"),
    H.release(),
    H.waitFrames(30),
    H.pressButtons({ "a" }, 4),
    H.call(function()
      H.log(string.format("[gaufeed] post meat-select: state=%02X cursor=%02X " ..
        "sel=%02X slot=%s", H.readByte(ZMENUSTATE), H.readByte(0x4B),
        H.readByte(0x28), tostring(invSlot(DRIED_MEAT))))
    end),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x19 end,
      600, "field item move mode", 5),
    driveCursor(0x19, 0, "move Dried Meat to slot 0"),
    H.release(),
    H.waitFrames(30),
    H.pressButtons({ "a" }, 4),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x08 end,
      600, "field item swap committed", 5),
    H.call(function()
      H.assertEq(invSlot(DRIED_MEAT), 0,
        "Dried Meat moved to inventory slot 0 through Item UI")
    end),
    H.pressButtons({ "b" }, 4),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x17 end,
      600, "Item options after move", 5),
    H.pressButtons({ "b" }, 4),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == MAIN_MENU end,
      900, "main menu after inventory move", 5),
    H.pressButtons({ "b" }, 4),
    H.waitUntil(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned()
    end, 1800, "world after inventory move", 5),
  }, {})
end

-- closed-loop shop buy (verbatim from gen_sabin_gau -- measured there)
local function buyItem(id, row, qtyFn, name)
  local phase = 0
  local seen27, bought = false, false
  local want = nil
  return H.driveUntil(function() return bought end, 20000, {
    H.call(function()
      phase = (phase + 1) % 8
      local st = mstateMenu()
      if want == nil then
        want = qtyFn()
        if want < 1 then want = 1 end
        H.log(string.format("[shop] %s: buying %d", name, want))
      end
      if st == 0x27 then
        seen27 = true
        local qty = H.readByte(0x0028)
        local btn = nil
        if qty < want then
          btn = (want - qty >= 10) and "up" or "right"
        elseif qty > want then
          btn = (qty - want >= 10) and "down" or "left"
        else
          btn = "a"
        end
        H.setPad(phase < 2 and { [btn] = true } or {})
      elseif seen27 then
        bought = true
        H.setPad({})
      elseif st == 0x25 then
        H.setPad(phase < 2 and { "a" } or {})
      elseif st == 0x26 then
        local cur = H.readByte(0x004E)
        local btn = cur < row and "down" or cur > row and "up" or "a"
        H.setPad(phase < 2 and { [btn] = true } or {})
      else
        H.setPad({})
      end
    end),
  }, "buy " .. name)
end

-- world walk that fights its randoms (verbatim machinery from gen_sabin_gau)
local lost = nil
local function worldWalkFight(tx, ty, budget, what)
  local tick, dirFlip, hb = 0, false, -1800
  local plan, planActor, btn, mstreak = nil, nil, nil, 0
  local function makePlan(actor)
    local row = cmdRowOf(actor, CMD_ITEM)
    if pHP(actor) > 0 and pMaxHP(actor) > 0
       and pHP(actor) * 10 < pMaxHP(actor) * 4
       and invCount(TONIC) > 0 and row then
      return { kind = "item", item = TONIC, row = row }
    end
    local bp = H.readByte(BP + actor * 2)
    local boost = bp >= 1 and math.min(bp, 3) or 0
    return { kind = "fight", boostLeft = boost }
  end
  local function button()
    local st = H.readByte(MSTATE)
    local actor = H.readByte(ACTOR)
    if plan == nil or planActor ~= actor then
      if st ~= ST_CMD then
        if st == ST_ITEM or st == ST_TGT then return { "b" } end
        return nil
      end
      plan, planActor = makePlan(actor), actor
      return nil
    end
    if st == ST_CMD then
      if plan.kind == "fight" then
        if plan.boostLeft > 0 then
          plan.boostLeft = plan.boostLeft - 1
          return { "r" }
        end
        local cur = H.readByte(CMDROW + actor) & 3
        if cur ~= 0 then return { "up" } end
        return { "a" }
      end
      local cur = H.readByte(CMDROW + actor) & 3
      if cur == plan.row then return { "a" } end
      return { cur < plan.row and "down" or "up" }
    end
    if st == ST_ITEM and plan.kind == "item" then
      local want = battInvIdx(plan.item)
      if want == nil then return { "b" } end
      local cur = H.readByte(ITEMSCR + actor) + H.readByte(ITEMROW + actor)
      if cur < want then return { "down" } end
      if cur > want then return { "up" } end
      return { "a" }
    end
    if st == ST_TGT then
      plan, planActor = nil, nil
      return { "a" }
    end
    return nil
  end
  return H.driveUntil(function()
    return lost ~= nil or not H.worldMode()
        or (H.worldX() == tx and H.worldY() == ty and H.worldHasControl())
  end, budget or 40000, {
    H.call(function()
      if H.frame - hb >= 1800 then
        hb = H.frame
        H.log(string.format("[gaufeed] walk[%s] f%d (%d,%d) b=%s [%s]", what,
          H.frame, H.worldX(), H.worldY(),
          tostring(H.battleLoadStarted()), partyLine()))
      end
      if H.battleLoadStarted() then
        local wiped = true
        for e = 0, 3 do
          if pMaxHP(e) > 0 and pHP(e) > 0 then wiped = false end
        end
        if wiped then
          if not lost then
            lost = string.format("wiped walking %s at f%d [%s]", what,
              H.frame, partyLine())
            H.log("[gaufeed] LOST -- " .. lost)
          end
          H.setPad({})
          return
        end
        tick = tick + 1
        local ph = tick % 30
        if H.readByte(MENU) == 0 then
          plan, planActor, mstreak = nil, nil, 0
          H.setPad(ph < 4 and { "a" } or {})
          return
        end
        mstreak = mstreak + 1
        if mstreak < 4 then H.setPad({}); return end
        if ph == 0 then btn = button() end
        H.setPad(ph < 6 and btn or {})
        return
      end
      plan, planActor = nil, nil
      if not H.worldHasControl() then H.setPad({}); return end
      if not H.worldAligned() then return end
      if bright() < 15 then H.setPad({}); return end
      local p = H.worldBfs(tx, ty)
      if p and #p > 0 then
        H.setPad({ [p[1]] = true })
      else
        dirFlip = not dirFlip
        H.setPad({ [dirFlip and "left" or "right"] = true })
      end
    end),
  }, "walk fighting -> " .. what)
end

-- --------------------------- grind to the FIRST appearance, then measure --
local grind = { fights = 0, appearances = 0 }
local appeared = false
local function grindToAppearance()
  local tick = 0
  local plan, planActor, btn, mstreak = nil, nil, nil, 0
  local dirFlip, decided, hb = false, false, -1800
  local bankedActor, bankReady = nil, false
  local bankStartFrame, bankStartHp = nil, nil
  local dismissingAppearance = false
  local meatPrimed = {}
  local retortArmed, retortUnavailable = false, false
  local targetBankLogged = false
  local reserveState, reserveLogAt = "", -300
  local function makePlan(actor)
    local row = cmdRowOf(actor, CMD_ITEM)
    local nmon, mhp = liveMonsters()
    if row then
      for e = 0, 1 do
        if pMaxHP(e) > 0 and pHP(e) == 0 and battInvIdx(FENIX_DOWN) then
          H.log(string.format("[gaufeed] revive e%d with Fenix Down [%s]",
            e, partyLine()))
          return { kind = "item", item = FENIX_DOWN, target = e, row = row }
        end
      end
      local target, worst = nil, 8
      for e = 0, 1 do
        if pHP(e) > 0 and pMaxHP(e) > 0 then
          local frac = pHP(e) * 10 // pMaxHP(e)
          if frac < worst and frac < 5 then target, worst = e, frac end
        end
      end
      if target then
        local missing = pMaxHP(target) - pHP(target)
        local item = missing >= 80 and battInvIdx(POTION) and POTION
                  or battInvIdx(TONIC) and TONIC
                  or battInvIdx(POTION) and POTION or nil
        if item then
          H.log(string.format("[gaufeed] heal e%d with $%02X [%s]", target,
            item, partyLine()))
          return { kind = "item", item = item, target = target, row = row }
        end
      end
    end
    local bushidoRow = cmdRowOf(actor, CMD_SWDTECH)
    if actor == 1 and nmon == 1 and not retortArmed
       and H.readByte(BP + actor * 2) < 2 and row then
      local safeItem = battInvIdx(TONIC) and TONIC
                    or battInvIdx(POTION) and POTION or nil
      if safeItem then
        H.log(string.format("[gaufeed] Cyan banks BP with a safe $%02X turn " ..
          "(bp=%d)", safeItem, H.readByte(BP + actor * 2)))
        return { kind = "item", item = safeItem, target = actor, row = row }
      end
    end
    if actor == 1 and nmon == 1 and not retortArmed
       and not retortUnavailable and bushidoRow then
      H.log(string.format("[gaufeed] Cyan plans Retort: row=%d bp=%d mp=%d",
        bushidoRow, H.readByte(BP + actor * 2), pMP(actor)))
      return { kind = "retort", skill = RETORT, row = bushidoRow }
    end
    if nmon == 1 and retortArmed and row
       and not meatPrimed[actor]
       and battInvIdx(TONIC) then
      H.log(string.format("[gaufeed] park actor %d in Tonic target " ..
        "selection for Retort", actor))
      return { kind = "prime", item = TONIC, row = row }
    end
    if actor == 0 and nmon == 1 and not retortArmed
       and not meatPrimed[1] and row then
      local safeItem = battInvIdx(TONIC) and TONIC
                    or battInvIdx(POTION) and POTION or nil
      if safeItem then
        H.log(string.format("[gaufeed] Sabin spends the held turn healing Cyan " ..
          "with $%02X", safeItem))
        return { kind = "item", item = safeItem, target = 1, row = row }
      end
    end
    local blitzRow = cmdRowOf(actor, CMD_BLITZ)
    if actor == 0 and nmon == 1 and pMP(actor) < 13 and row then
      local mpItem = battInvIdx(ETHER) and ETHER
                  or battInvIdx(TINCTURE) and TINCTURE or nil
      if mpItem then
        H.log(string.format("[gaufeed] restore Sabin MP with $%02X (mp=%d)",
          mpItem, pMP(actor)))
        return { kind = "item", item = mpItem, target = actor, row = row }
      end
    end
    if actor == 0 and nmon == 1 and pMP(actor) >= 4 and blitzRow then
      return { kind = "blitz",
               skill = pMP(actor) >= 13 and SUPLEX or PUMMEL,
               row = blitzRow }
    end
    local bp = H.readByte(BP + actor * 2)
    local boost = actor ~= 1 and bp >= 2 and math.min(bp, 3) or 0
    return { kind = "fight", boostLeft = boost }
  end
  local function button()
    local st = H.readByte(MSTATE)
    local actor = H.readByte(ACTOR)
    if plan == nil or planActor ~= actor then
      if st ~= ST_CMD then
        if st == ST_ITEM or st == ST_TGT then return { "b" } end
        return nil
      end
      plan, planActor = makePlan(actor), actor
      return nil
    end
    if st == ST_CMD then
      if plan.kind == "fight" then
        if plan.boostLeft > 0 then
          plan.boostLeft = plan.boostLeft - 1
          return { "r" }
        end
        local cur = H.readByte(CMDROW + actor) & 3
        if cur ~= 0 then return { "up" } end
        local live = liveMonsters()
        if actor == 0 and live == 1 and meatPrimed[1] and pHP(1) > 0
           and H.readByte(0x4002) == 0xff then return nil end
        return { "a" }
      end
      local cur = H.readByte(CMDROW + actor) & 3
      if cur == plan.row then
        local live = liveMonsters()
        if actor == 0 and live == 1 and meatPrimed[1] and pHP(1) > 0
           and H.readByte(0x4002) == 0xff then return nil end
        return { "a" }
      end
      return { cur < plan.row and "down" or "up" }
    end
    if st == ST_ITEM and (plan.kind == "item" or plan.kind == "prime") then
      local want = battInvIdx(plan.item)
      if want == nil then return { "b" } end
      local cur = H.readByte(ITEMSCR + actor) + H.readByte(ITEMROW + actor)
      if cur < want then return { "down" } end
      if cur > want then return { "up" } end
      return { "a" }
    end
    if st == ST_TOOLS and (plan.kind == "blitz" or plan.kind == "retort") then
      local want = nil
      for i = 0, 7 do
        if H.readByte(ITEMLIST + i * 3) == plan.skill then want = i end
      end
      if want == nil then
        if plan.kind == "retort" then
          retortUnavailable = true
          H.log("[gaufeed] Retort is absent from Cyan's honest Bushido window")
        end
        plan, planActor = nil, nil
        return { "b" }
      end
      local wc, wr = want % 2, want // 2
      local cc, cr = H.readByte(BLCOL + actor), H.readByte(BLROW + actor)
      if cc ~= wc then return { wc > cc and "right" or "left" } end
      if cr ~= wr then return { wr > cr and "down" or "up" } end
      if plan.kind == "retort" then
        retortArmed = true
        H.log(string.format("[gaufeed] Retort armed at f%d with monster HP=%d",
          H.frame, select(2, liveMonsters())))
        plan, planActor = nil, nil
      end
      return { "a" }
    end
    if st == ST_TGT then
      if plan.kind == "prime" then
        meatPrimed[actor] = true
        return nil
      end
      if plan.kind ~= "item" then
        local live = liveMonsters()
        if actor == 1 and live <= 2 and meatPrimed[1] then
          plan, planActor = nil, nil
          return { "b" }
        end
        if plan.kind == "retort" then
          retortArmed = true
          H.log(string.format("[gaufeed] Retort armed at f%d with monster HP=%d",
            H.frame, select(2, liveMonsters())))
        end
        plan, planActor = nil, nil
        return { "a" }
      end
      local chars, mons = H.readByte(TGTCHARS), H.readByte(TGTMONS)
      if mons ~= 0 then return { "right" } end
      local wantMask = 1 << plan.target
      if chars == wantMask then
        meatPrimed[actor] = false
        plan, planActor = nil, nil
        return { "a" }
      end
      local cur = 0
      for e = 0, 3 do
        if chars & (1 << e) ~= 0 then cur = e; break end
      end
      return { cur < plan.target and "down" or "up" }
    end
    return nil
  end
  return H.driveUntil(function()
    appeared = gauOn() and (bankReady or meatPrimed[0] or meatPrimed[1])
       and H.readByte(MENU) ~= 0
       and (H.readByte(MSTATE) == ST_ITEM or H.readByte(MSTATE) == ST_TGT)
    return appeared or inParty(11) or lost ~= nil
  end, 200000, {
    H.call(function()
      if gauOn() then
        if (bankReady or meatPrimed[0] or meatPrimed[1])
           and H.readByte(MENU) ~= 0
           and (H.readByte(MSTATE) == ST_ITEM
             or H.readByte(MSTATE) == ST_TGT) then
          H.setPad({})
          return                              -- pred fires next check
        end
        if bankedActor ~= nil and H.readByte(MENU) ~= 0 then
          -- The finishing action may land while a window transition is still
          -- underway.  Gau is already targetable, but the live Item menu is
          -- still ours to drive until battle event $1b closes it.
          local st = H.readByte(MSTATE)
          local pulse = tick % 8 < 2
          if st == ST_CMD then
            local row = cmdRowOf(bankedActor, CMD_ITEM)
            local cur = H.readByte(CMDROW + bankedActor) & 3
            if row == nil then H.setPad({})
            elseif cur == row then H.setPad(pulse and { "a" } or {})
            else H.setPad({ [cur < row and "down" or "up"] = true }) end
          elseif st == ST_ITEM then
            local want = battInvIdx(TONIC)
            local cur = H.readByte(ITEMSCR + bankedActor)
                      + H.readByte(ITEMROW + bankedActor)
            if want == nil then H.setPad({})
            elseif cur == want then H.setPad(pulse and { "a" } or {})
            else
              local dir = cur == 0 and want > 0 and "up"
                       or cur < want and "down" or "up"
              H.setPad({ [dir] = true })
            end
          elseif st == ST_TGT then
            bankReady = true
            H.log(string.format("[gaufeed] BANK READY during live arrival -- %s",
              engineLine()))
            H.setPad({})
          else
            H.setPad({})
          end
          tick = tick + 1
          return
        end
        if not dismissingAppearance then
          dismissingAppearance = true
          grind.appearances = grind.appearances + 1
          H.log(string.format("[gaufeed] appearance #%d had no live feed " ..
            "target; dismissing honestly -- %s", grind.appearances,
            engineLine()))
        end
        tick = tick + 1
        H.setPad(tick % 30 < 4 and { "a" } or {})
        return
      elseif dismissingAppearance then
        dismissingAppearance = false
        bankedActor, bankReady = nil, false
        bankStartFrame, bankStartHp = nil, nil
        plan, planActor = nil, nil
        H.log(string.format("[gaufeed] unprepared appearance dismissed at f%d",
          H.frame))
      end
      if H.frame - hb >= 1800 then
        hb = H.frame
        H.log(string.format("[gaufeed] grind f%d fights=%d bp=%d/%d [%s] -- %s",
          H.frame, grind.fights, H.readByte(BP), H.readByte(BP + 2),
          partyLine(), engineLine()))
      end
      if H.battleLoadStarted() then
        if not decided then
          decided = true
          meatPrimed = {}
          grind.fights = grind.fights + 1
          local w = H.formationWords()
          H.log(string.format("[gaufeed] fight #%d up f%d (%04X %04X %04X %04X)",
            grind.fights, H.frame, w[1], w[2], w[3], w[4]))
        end
        local wiped = true
        for e = 0, 3 do
          if pMaxHP(e) > 0 and pHP(e) > 0 then wiped = false end
        end
        if wiped and not lost then
          lost = string.format("wiped in fight #%d [%s]", grind.fights,
            partyLine())
          H.log("[gaufeed] LOST -- " .. lost)
          H.setPad({})
          return
        end
        tick = tick + 1
        local ph = tick % 30
        local nmon, mhp = liveMonsters()
        -- Gau's arrival runs ResetForVeldtGau, which removes every QUEUED
        -- party action.  It cannot create a new menu afterward because the
        -- battle-end path has already frozen normal ATB processing.  Vanilla
        -- therefore expects the player to have one command menu open while a
        -- previously queued action lands the final blow.  Bank exactly that
        -- state: one live monster, this actor has a command menu, and another
        -- living actor already has an action pending.  If the pending action
        -- does not kill, release the bank and continue fighting.
        if bankedActor ~= nil then
          if nmon == 0 or gauOn() then
            H.setPad({})
            return
          end
          local otherPending = false
          for e = 0, 3 do
            if e ~= bankedActor and pHP(e) > 0
               and H.readByte(0x32cc + e * 2) ~= 0xff then
              otherPending = true
            end
          end
          -- $32cc can clear just before the queued attack's animation applies
          -- damage.  Keep the menu bank alive until monster HP itself proves
          -- that the attack resolved, with a bounded grace for misses.
          local attackUnresolved = otherPending
             or (mhp == bankStartHp and H.frame - bankStartFrame < 360)
          if attackUnresolved then
            -- Spend the queued attack's animation time opening Item, selecting
            -- Dried Meat, and parking in target selection.  Arrival otherwise
            -- gives us only ~74 frames before battle event $1b closes a plain
            -- command menu -- too short for both window animations.
            local st = H.readByte(MSTATE)
            local pulse = tick % 8 < 2
            if st == ST_CMD then
              local row = cmdRowOf(bankedActor, CMD_ITEM)
              local cur = H.readByte(CMDROW + bankedActor) & 3
              if row == nil then
                H.setPad({})
              elseif cur == row then
                H.setPad(pulse and { "a" } or {})
              else
                H.setPad({ [cur < row and "down" or "up"] = true })
              end
            elseif st == ST_ITEM then
              local want = battInvIdx(TONIC)
              local cur = H.readByte(ITEMSCR + bankedActor)
                        + H.readByte(ITEMROW + bankedActor)
              if want == nil then
                H.setPad({})
              elseif cur == want then
                H.setPad(pulse and { "a" } or {})
              else
                -- HOLD so the menu's native auto-repeat accelerates through
                -- the long inventory; short pulses reset its repeat timer.
                local dir = cur == 0 and want > 0 and "up"
                         or cur < want and "down" or "up"
                H.setPad({ [dir] = true })
              end
            elseif st == ST_TGT then
              if not bankReady then
                bankReady = true
                H.log(string.format("[gaufeed] BANK READY in Tonic target " ..
                  "selection -- %s", engineLine()))
              end
              H.setPad({})
            else
              H.setPad({})
            end
            return
          end
          if H.readByte(MSTATE) ~= ST_CMD then
            H.setPad(tick % 8 < 2 and { "b" } or {})
            return
          end
          H.log(string.format("[gaufeed] bank released at f%d: attack resolved " ..
            "and monster survived (%d -> %d HP) -- %s", H.frame,
            bankStartHp, mhp, engineLine()))
          bankedActor, bankReady = nil, false
          bankStartFrame, bankStartHp = nil, nil
          plan, planActor = nil, nil
        end
        if H.readByte(MENU) == 0 then
          plan, planActor, mstreak = nil, nil, 0
          H.setPad(ph < 4 and { "a" } or {})
          return
        end
        mstreak = mstreak + 1
        if mstreak < 4 then H.setPad({}); return end
        -- Retort is delayed honest damage: once it is armed, park Cyan in
        -- a Tonic target selection and let Active mode advance the enemy.
        -- A physical hit on Cyan fires the counter while this target screen
        -- remains live, so Gau can arrive without any post-kill menu opening.
        local activeActor = H.readByte(ACTOR)
        if (H.readByte(MSTATE) == ST_ITEM or H.readByte(MSTATE) == ST_TGT)
           and meatPrimed[activeActor] then
          if not targetBankLogged then
            targetBankLogged = true
            H.log(string.format("[gaufeed] RETORT ITEM BANK READY f%d " ..
              "monsterHP=%d " ..
              "-- %s", H.frame, mhp, engineLine()))
          end
          H.setPad({})
          return
        end
        -- Once Cyan has prepared the Dried-Meat path, do not let him spend
        -- the finishing turn himself.  Hold his ready menu until Sabin's ATB
        -- is full, then use the ordinary battle character-switch button.
        -- Sabin commits the reserved Suplex; Cyan's still-ready menu returns
        -- during its animation and becomes the bank below.
        if H.readByte(MSTATE) == ST_CMD and nmon <= 2
           and H.readByte(ACTOR) == 1 and meatPrimed[1]
           and pHP(1) * 2 >= pMaxHP(1) then
          local sabinPending = H.readByte(0x32cc) ~= 0xff
          local rs = string.format("q0=%02X q1=%02X pend=%02X fl=%02X",
            H.readByte(0x4001), H.readByte(0x4002), H.readByte(0x32cc),
            H.readByte(0x3aa0))
          if rs ~= reserveState or H.frame - reserveLogAt >= 300 then
            reserveState, reserveLogAt = rs, H.frame
            H.log(string.format("[gaufeed] RESERVE f%d %s atb=%02X mp=%d",
              H.frame, rs, H.readByte(0x3219), pMP(0)))
          end
          if not sabinPending then
            H.setPad(H.readByte(0x4001) ~= 0xff and ph < 4 and { "x" } or {})
            return
          end
        end
        if H.readByte(MSTATE) == ST_CMD and nmon == 1 then
          local actor = H.readByte(ACTOR)
          for e = 0, 3 do
            if actor == 1 and pHP(actor) > 0 and meatPrimed[actor]
               and e == 0 and pHP(e) > 0
               and H.readByte(0x32cc + e * 2) ~= 0xff then
              bankedActor = actor
              bankStartFrame, bankStartHp = H.frame, mhp
              H.log(string.format("[gaufeed] BANK PREP f%d actor=%d with %d " ..
                "monster(s) at %d HP and actor %d queued; itemCursor=%d " ..
                "meatIdx=%s -- %s", H.frame, actor, nmon, mhp, e,
                H.readByte(ITEMSCR + actor) + H.readByte(ITEMROW + actor),
                tostring(battInvIdx(DRIED_MEAT)), engineLine()))
              H.setPad({})
              return
            end
          end
        end
        if ph == 0 then btn = button() end
        H.setPad(ph < 6 and btn or {})
        return
      end
      decided = false
      plan, planActor = nil, nil
      if not H.worldHasControl() then H.setPad({}); return end
      bankedActor, bankReady = nil, false
      bankStartFrame, bankStartHp = nil, nil
      if not H.worldAligned() then return end
      dirFlip = not dirFlip
      H.setPad({ [dirFlip and "left" or "right"] = true })
    end),
  }, "grind to GAU's first appearance")
end

-- observation: does a command menu open while GAU is on stage?  Stage 1 is
-- PURE hands-off (12000 frames).  If no menu opens, stage 2 taps A gently
-- (a human dismissing GAU's "Ooh_I'm hungry!" turn dialogs) -- this
-- distinguishes "menu blocked behind an un-dismissed battle dialog" from
-- "the engine never reopens menus post-appearance".
local menuOpenedAt, windowEndedAt, menuStage = nil, nil, nil
local function observeStage(stage, tapA, budget)
  local last, lastLog = "", -100
  local spent = 0
  return H.cond(function()
    return menuOpenedAt == nil and windowEndedAt == nil
  end, {
    H.driveUntil(function()
      spent = spent + 1
      if spent >= budget - 10 then return true end   -- stage over, no throw
      if H.readByte(MENU) ~= 0 and
         (H.readByte(MSTATE) == ST_CMD or H.readByte(MSTATE) == ST_ITEM
           or H.readByte(MSTATE) == ST_TGT) then
        menuOpenedAt, menuStage = menuOpenedAt or H.frame, stage
        return true
      end
      if not gauOn() then
        windowEndedAt = windowEndedAt or H.frame
        return true
      end
      return false
    end, budget, {
      H.call(function()
        if tapA then
          H.setPad(H.frame % 30 < 4 and { "a" } or {})
        else
          H.setPad({})
        end
        local line = engineLine()
        if line ~= last or H.frame - lastLog >= 120 then
          last, lastLog = line, H.frame
          H.log(string.format("[observe%s] f%d %s", stage, H.frame, line))
        end
      end),
    }, "observe stage " .. stage .. ": menu opens or GAU leaves"),
  }, {})
end

-- the feed itself, driven closed-loop off the engine's cursor cells
local fed, joined = false, false
local feedConfirmUntil = nil
local feedSubmissions = 0
local function driveFeed()
  local lastLog, lastState, lastMeatLog, phase = -100, "", -100, 0
  return H.driveUntil(function()
    joined = inParty(11)
    return joined or fedSwitch()
  end, 20000, {
    H.call(function()
      phase = (phase + 1) % 8
      local st = H.readByte(MSTATE)
      local actor = H.readByte(ACTOR)
      local state = string.format("%02X/%02X/%02X/%02X/%02X/%02X",
        H.readByte(MENU), st, actor, H.readByte(CMDROW + actor) & 3,
        H.readByte(ITEMSCR + actor), H.readByte(ITEMROW + actor))
      if state ~= lastState or H.frame - lastLog >= 60 then
        lastLog = H.frame
        lastState = state
        H.log(string.format("[feed] f%d ui=%s %s", H.frame, state,
          engineLine()))
      end
      fed = fedSwitch() or invCount(DRIED_MEAT) == 0
      if fed then
        H.setPad(H.frame % 30 < 4 and { "a" } or {})
        return
      end
      if H.readByte(MENU) == 0 then
        -- Gau's turn dialog can own the battle after ResetForVeldtGau.  Tap
        -- through it only while no command menu exists; the instant a real
        -- menu reopens, the closed-loop branches below take over.
        H.setPad(H.frame % 30 < 4 and { "a" } or {})
        return
      end
      if st ~= ST_TGT then feedConfirmUntil = nil end
      if st == ST_CMD then
        local row = cmdRowOf(actor, CMD_ITEM)
        if row == nil then H.setPad({}); return end
        local cur = H.readByte(CMDROW + actor) & 3
        if cur == row then H.setPad(phase < 2 and { "a" } or {})
        else H.setPad(phase < 2 and
          { [cur < row and "down" or "up"] = true } or {}) end
        return
      end
      if st == ST_ITEM then
        local want = battInvIdx(DRIED_MEAT)
        if want == nil then
          if H.frame - lastMeatLog >= 120 then
            lastMeatLog = H.frame
            H.log("[feed] MEAT NOT IN BATTLE LIST -- " .. engineLine())
          end
          H.setPad({})
          return
        end
        local cur = H.readByte(ITEMSCR + actor) + H.readByte(ITEMROW + actor)
        if cur == want then H.setPad(phase < 2 and { "a" } or {})
        else H.setPad(phase < 2 and
          { [cur < want and "down" or "up"] = true } or {}) end
        return
      end
      if st == ST_TGT then
        local mons = H.readByte(TGTMONS)
        H.log(string.format("[feed] tgt f%d chars=%02X mons=%02X 92=%02X",
          H.frame, H.readByte(TGTCHARS), mons, H.readByte(0x0092)))
        if mons == 0x20 then
          if feedConfirmUntil == nil then
            feedSubmissions = feedSubmissions + 1
            feedConfirmUntil = H.frame + 3
            H.log(string.format("[feed] cursor ON GAU -- confirming item " ..
              "$%02X submission #%d (%s target model)",
              H.readByte(0x7a85), feedSubmissions,
              gauOn() and "appearance" or gauPresent() and "normalized"
                or "unknown"))
          end
          H.setPad(H.frame <= feedConfirmUntil and { "a" } or {})
        else
          H.setPad(phase < 4 and { "left" } or {})
        end
        return
      end
      H.setPad({})
    end),
  }, "feed: item->meat->left->confirm")
end

H.run({ maxFrames = 700000 }, {
  H.cond(function() return not FAST_STAGE end, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIdx(), 159, "boot on the shore, map 159")
    H.assertEq(sw(0x3F), 1, "$003F set -- GAU met at the falls")
    H.assertEq(inParty(11), false, "GAU not yet in the party")
  end),
  H.navTo(8, 14, { maxFrames = 6000, honest = "flee", arrive = function()
    return H.worldMode() end }),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end,
    3000, "on the world", 5),
  worldWalkFight(220, 115, 60000, "shore -> Mobliz"),
  H.call(function()
    if lost ~= nil then error("transit lost -- " .. tostring(lost), 0) end
  end),
  settle(157, "Mobliz"),
  H.navTo(26, 22, { maxFrames = 10000, honest = "flee", arrive = function()
    return mapIdx() == 164 end }),
  H.cond(function() return mapIdx() ~= 164 end, {
    H.navTo(26, 21, { maxFrames = 3000, honest = "flee", arrive = function()
      return mapIdx() == 164 end }),
  }, {}),
  settle(164, "item shop"),
  H.navTo(29, 50, { maxFrames = 6000, honest = "flee" }),
  (function()
    local phase = 0
    return H.driveUntil(function() return mstateMenu() == 0x25 end, 3000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
        H.setPad(phase < 4 and { "up", "a" } or { "up" })
      end),
    }, "shop options open")
  end)(),
  tapUntil("a", inState(0x26), "buy list"),
  tapUntil("a", inState(0x27), "quantity"),
  tapUntil("a", function()
    return invSlot(DRIED_MEAT) ~= nil and mstateMenu() == 0x26
  end, "bought meat", 2400),
  buyItem(TONIC, 1, function() return 10 - invCount(TONIC) end, "TONIC to 10"),
  tapUntil("b", inState(0x25), "options again"),
  tapUntil("b", function() return H.hasControl() end, "shop closed", 2400),
  H.call(function()
    H.assertEq(invSlot(DRIED_MEAT) ~= nil, true, "Dried Meat in the bag")
    H.log(string.format("[gaufeed] leaving shop: gil=%d tonics=%d",
      gil(), invCount(TONIC)))
  end),
  H.navTo(29, 53, { maxFrames = 4000, honest = "flee", arrive = function()
    return mapIdx() == 157 end }),
  settle(157, "town again"),
  H.navTo(18, 40, { maxFrames = 8000, honest = "flee", arrive = function()
    return H.worldMode() end }),
  (function()
    return H.driveUntil(function() return H.worldMode() end, 1800, {
      H.call(function() H.setPad({ down = true }) end),
    }, "SOUTH out of Mobliz onto the world")
  end)(),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 3000, "world live again", 5),
  worldWalkFight(215, 119, 40000, "Mobliz -> Veldt staging"),
  H.call(function()
    if lost ~= nil then error("staging walk lost -- " .. tostring(lost), 0) end
  end),

  -- emit the grind-staging accelerator FIRST -- iteration currency
  (function()
    local req
    return H.cond(function() return true end, {
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "grind staging capture")
        H.emitBlob("_scratch_gau_grind.mss", req.blob)
        H.log(string.format("[gaufeed] STAGING state emitted (%d bytes) f%d " ..
          "at (%d,%d)", #req.blob, H.frame, H.worldX(), H.worldY()))
      end),
    }, {})
  end)(),
  }, {
    -- Keep this literal so compose_test.py can embed the state.
    H.loadState("build/states/_scratch_gau_grind.mss.lua"),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(H.worldMode(), true, "fast-path staging state is on world map")
      H.assertEq(invSlot(DRIED_MEAT) ~= nil, true,
        "fast-path staging state has Dried Meat")
      H.log(string.format("[gaufeed] FAST staging boot at (%d,%d); " ..
        "tonic=%d potion=%d tincture=%d ether=%d fenix=%d", H.worldX(),
        H.worldY(), invCount(TONIC), invCount(POTION), invCount(TINCTURE),
        invCount(ETHER), invCount(FENIX_DOWN)))
    end),
  }),

  moveMeatToFront(),

  -- Active mode is selected through the ordinary Config UI.  In Wait mode,
  -- opening Item/target selection freezes the queued attack that must deliver
  -- the final blow; Active mode lets that honest attack resolve while the
  -- Tonic target cursor is banked; it normalizes Gau's special target state
  -- before the real Dried-Meat submission.
  H.release(),
  H.waitFrames(30),
  H.pressButtons({ "x" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == MAIN_MENU end,
    600, "main menu for Active mode", 5),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == MAIN_MENU and H.readByte(0x4B) == 5
  end, 800, {
    H.pressButtons({ "down" }, 4), H.waitFrames(12),
  }, "main-menu cursor on Config"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == CONFIG_MENU end,
    900, "Config menu", 5),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == CONFIG_MENU and H.readByte(0x4B) == 0
  end, 600, {
    H.pressButtons({ "up" }, 4), H.waitFrames(12),
  }, "Config cursor on Battle Mode"),
  H.driveUntil(function() return (H.readByte(0x1D4D) & 0x08) == 0 end,
    300, {
      H.pressButtons({ "left" }, 4), H.waitFrames(12),
    }, "Battle Mode = Active"),
  H.call(function()
    H.assertEq(H.readByte(0x1D4D) & 0x08, 0,
      "Config Battle Mode is Active via UI")
  end),
  H.pressButtons({ "b" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == MAIN_MENU end,
    600, "back to main menu", 5),
  H.pressButtons({ "b" }, 4),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 1800, "world after Config", 5),

  grindToAppearance(),
  H.call(function()
    if lost ~= nil then error("grind lost -- " .. tostring(lost), 0) end
    H.log(string.format("[gaufeed] *** APPEARANCE at fight #%d f%d -- %s",
      grind.fights, H.frame, engineLine()))
    H.screenshot("gaufeed_appear")
  end),

  -- emit the appearance accelerator
  (function()
    local req
    return H.cond(function() return true end, {
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "appearance capture")
        H.emitBlob("_scratch_gau_appear.mss", req.blob)
        H.log(string.format("[gaufeed] APPEARANCE state emitted (%d bytes) f%d",
          #req.blob, H.frame))
      end),
    }, {})
  end)(),

  observeStage("1-handsoff", false, 12000),
  observeStage("2-tapA", true, 8000),
  H.call(function()
    if menuOpenedAt then
      H.log(string.format("[gaufeed] MEASUREMENT: command menu OPEN at f%d " ..
        "(stage %s) with GAU on stage -- %s", menuOpenedAt,
        tostring(menuStage), engineLine()))
      H.screenshot("gaufeed_menu_open")
    else
      H.log(string.format("[gaufeed] MEASUREMENT: NO menu opened " ..
        "(window ended f%s) -- %s", tostring(windowEndedAt), engineLine()))
      H.screenshot("gaufeed_no_menu")
      error("no command menu opened while GAU was on stage (hands-off AND " ..
        "A-taps) -- see the [observe*] rows for the engine state timeline", 0)
    end
  end),

  driveFeed(),
  H.call(function()
    H.log(string.format("[gaufeed] after feed: fed=%s joined=%s sw13=%s " ..
      "roster=%02X meatInBag=%d", tostring(fed), tostring(joined),
      tostring(fedSwitch()), H.readByte(0x1EDF), invCount(DRIED_MEAT)))
    H.screenshot("gaufeed_after")
  end),
  (function()
    local phase = 0
    return H.driveUntil(function()
      return H.worldMode() and H.worldHasControl()
    end, 20000, {
      H.call(function()
        phase = (phase + 1) % 12
        H.setPad(phase < 4 and { "a" } or {})
      end),
    }, "advance Gau's join event to the world")
  end)(),
  H.call(function()
    fed = fedSwitch() or invCount(DRIED_MEAT) == 0
    H.assertEq(fedSwitch(), true,
      "first Dried-Meat appearance set Gau's battle switch")
    H.assertEq(invCount(DRIED_MEAT), 0,
      "Dried Meat consumed on Gau's first appearance")
    H.assertEq(inParty(11), true,
      "Gau recruited by the Dried-Meat event in the same encounter")
    H.assertEq((H.readByte(0x1EDF) & 0x08) ~= 0, true,
      "GAU roster bit set by the event")
    H.log(string.format("[gaufeed] FINAL: GAU inParty=%s roster bit=%s " ..
      "fed=%s sw13=%s", tostring(inParty(11)),
      tostring((H.readByte(0x1EDF) & 0x08) ~= 0), tostring(fed),
      tostring(fedSwitch())))
  end),
})
