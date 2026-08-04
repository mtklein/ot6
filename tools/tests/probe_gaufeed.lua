-- probe_gaufeed.lua -- measurement instrument for the GAU Dried-Meat feed
-- (#75).  The disassembly says the appearance window is INDEFINITE:
--   * GauAppears (battle_main.asm:12214) makes GAU a targetable enemy
--     character ($2f4e + $3a40), and UpdateDead counts enemy characters
--     into $3a77 ("number of enemies alive", battle_main.asm:12559-12562),
--     so CheckBattleEnd's "$3a77 == 0" win test can never pass while he is
--     on stage -- the battle cannot end on its own.
--   * His AI (AIScript::_370) on a first visit (battle switch 13 clear) is
--     dlg "Ooh_I'm hungry!" + end_if -- a dialog loop.  NOTHING in the
--     script makes him leave voluntarily; only if_hit (attack him) or the
--     if_item DRIED_MEAT reaction (feed him) end the battle.
--   * ResetForVeldtGau clears the party's queued actions and restarts
--     their ATB, and CheckPlayerAction reopens battle menus whenever a
--     gauge refills -- so a menu SHOULD open a few hundred frames after
--     the appearance, exactly like a human experiences.
-- The prior measurement ("no character command menu is open on the frames
-- GAU is targetable; the window is short") contradicts all three points,
-- so this probe measures the ground truth:
--   1. route falls_done -> Mobliz (buy the meat) -> Veldt staging, all by
--      the gen's own honest machinery;
--   2. capture + emit a grind-staging savestate (_scratch_gau_grind.mss)
--      and a first-appearance savestate (_scratch_gau_appear.mss) so later
--      probes iterate in seconds, not tens of minutes;
--   3. at the first appearance go HANDS OFF and log the engine's own menu
--      state every few frames: $7BCA open-menu count, $7BC2 menu state,
--      per-slot $3aa0 flags / $3219 ATB / $32cc pending-action, $2f4e/f,
--      $3a74-77 alive masks, $b1 (bit7 = menus disabled), $3a46, $340a;
--   4. the moment a command menu opens, drive Item -> Dried Meat -> LEFT
--      onto the monster column -> confirm, and watch AIScript::_370's
--      reaction recruit him ($1EDF bit 3, then $1850 party slot).
-- Everything here is pad presses and RAM reads; the only state ops are
-- savestate capture/reload, the same accelerator every gen uses.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/falls_done.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local DRIED_MEAT, TONIC = 0xFE, 0xE8
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
local ST_CMD, ST_ITEM, ST_TGT = 0x05, 0x0A, 0x38
local CMD_ITEM = 0x01
local CMDTBL, CMDROW = 0x202E, 0x890F
local ITEMSCR, ITEMROW = 0x8947, 0x894F
local BATTINV = 0x2686
local TGTCHARS, TGTMONS = 0x7B7D, 0x7B7E
local BP = 0x3E9C
local function pHP(e) return H.readWord(0x3BF4 + e * 2) end
local function pMaxHP(e) return H.readWord(0x3C1C + e * 2) end
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
local function gauOn() return H.readByte(0x2f4e) ~= 0 end
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
local grind = { fights = 0 }
local appeared = false
local function grindToAppearance()
  local tick = 0
  local plan, planActor, btn, mstreak = nil, nil, nil, 0
  local dirFlip, decided, hb = false, false, -1800
  local function makePlan(actor)
    local row = cmdRowOf(actor, CMD_ITEM)
    if pHP(actor) > 0 and pMaxHP(actor) > 0
       and pHP(actor) * 10 < pMaxHP(actor) * 4
       and invCount(TONIC) > 0 and row then
      return { kind = "item", item = TONIC, row = row }
    end
    local bp = H.readByte(BP + actor * 2)
    local boost = bp >= 2 and math.min(bp, 3) or 0
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
    appeared = gauOn()
    return appeared or lost ~= nil
  end, 200000, {
    H.call(function()
      if gauOn() then H.setPad({}); return end   -- pred fires next check
      if H.frame - hb >= 1800 then
        hb = H.frame
        H.log(string.format("[gaufeed] grind f%d fights=%d [%s]", H.frame,
          grind.fights, partyLine()))
      end
      if H.battleLoadStarted() then
        if not decided then
          decided = true
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
      decided = false
      plan, planActor = nil, nil
      if not H.worldHasControl() then H.setPad({}); return end
      if not H.worldAligned() then return end
      dirFlip = not dirFlip
      H.setPad({ [dirFlip and "left" or "right"] = true })
    end),
  }, "grind to GAU's first appearance")
end

-- hands-off observation: does a command menu open while GAU is on stage?
local menuOpenedAt, windowEndedAt = nil, nil
local function observeHandsOff()
  local last, lastLog = "", -100
  return H.driveUntil(function()
    if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD then
      menuOpenedAt = menuOpenedAt or H.frame
      return true
    end
    if not gauOn() then
      windowEndedAt = windowEndedAt or H.frame
      return true
    end
    return false
  end, 12000, {
    H.call(function()
      H.setPad({})
      local line = engineLine()
      if line ~= last or H.frame - lastLog >= 120 then
        last, lastLog = line, H.frame
        H.log(string.format("[observe] f%d %s", H.frame, line))
      end
    end),
  }, "hands-off: menu opens or GAU leaves")
end

-- the feed itself, driven closed-loop off the engine's cursor cells
local fed, joined = false, false
local function driveFeed()
  local lastLog = -100
  return H.driveUntil(function()
    joined = inParty(11)
    return joined or not gauOn()
  end, 20000, {
    H.call(function()
      local st = H.readByte(MSTATE)
      local actor = H.readByte(ACTOR)
      if H.frame - lastLog >= 60 then
        lastLog = H.frame
        H.log(string.format("[feed] f%d %s", H.frame, engineLine()))
      end
      if fed then H.setPad({}); return end
      if H.readByte(MENU) == 0 then H.setPad({}); return end
      if st == ST_CMD then
        local row = cmdRowOf(actor, CMD_ITEM)
        if row == nil then H.setPad({}); return end
        local cur = H.readByte(CMDROW + actor) & 3
        if cur == row then H.setPad(H.frame % 4 < 2 and { "a" } or {})
        else H.setPad({ [cur < row and "down" or "up"] = true }) end
        return
      end
      if st == ST_ITEM then
        local want = battInvIdx(DRIED_MEAT)
        if want == nil then
          H.log("[feed] MEAT NOT IN BATTLE LIST -- " .. engineLine())
          H.setPad({})
          return
        end
        local cur = H.readByte(ITEMSCR + actor) + H.readByte(ITEMROW + actor)
        if cur == want then H.setPad(H.frame % 4 < 2 and { "a" } or {})
        else H.setPad({ [cur < want and "down" or "up"] = true }) end
        return
      end
      if st == ST_TGT then
        local mons = H.readByte(TGTMONS)
        H.log(string.format("[feed] tgt f%d chars=%02X mons=%02X 92=%02X",
          H.frame, H.readByte(TGTCHARS), mons, H.readByte(0x0092)))
        if mons == 0x20 then
          fed = true
          H.log("[feed] cursor ON GAU -- confirming the meat")
          H.setPad({ "a" })
        else
          H.setPad(H.frame % 4 < 2 and { "left" } or {})
        end
        return
      end
      H.setPad({})
    end),
  }, "feed: item->meat->left->confirm")
end

H.run({ maxFrames = 700000 }, {
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

  observeHandsOff(),
  H.call(function()
    if menuOpenedAt then
      H.log(string.format("[gaufeed] MEASUREMENT: command menu OPEN at f%d " ..
        "with GAU on stage -- %s", menuOpenedAt, engineLine()))
      H.screenshot("gaufeed_menu_open")
    else
      H.log(string.format("[gaufeed] MEASUREMENT: NO menu before window end " ..
        "(ended f%s) -- %s", tostring(windowEndedAt), engineLine()))
      H.screenshot("gaufeed_no_menu")
      error("hands-off: GAU left before any command menu opened -- see the " ..
        "[observe] rows above for the engine state timeline", 0)
    end
  end),

  driveFeed(),
  H.call(function()
    H.log(string.format("[gaufeed] after feed: fed=%s joined=%s sw13=%s " ..
      "roster=%02X meatInBag=%d", tostring(fed), tostring(joined),
      tostring(fedSwitch()), H.readByte(0x1EDF), invCount(DRIED_MEAT)))
    H.screenshot("gaufeed_after")
  end),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl()
  end, 20000, "world after the join/leave", 5),
  H.call(function()
    H.log(string.format("[gaufeed] FINAL: GAU inParty=%s roster bit=%s " ..
      "fed=%s sw13=%s", tostring(inParty(11)),
      tostring((H.readByte(0x1EDF) & 0x08) ~= 0), tostring(fed),
      tostring(fedSwitch())))
  end),
})
