-- gen_sabin_gau.lua -- leg 10 of SABIN's scenario: GAU.  Mints:
--   gau_joined.mss   world (214,147), Crescent Mountain's doorstep, party
--                    SABIN+CYAN+GAU -- the trench leg steps in from here.
--
-- Every Crescent Mountain helmet-scene variant gates on $01AB (GAU in the
-- party), so the trench cannot open without him.  The route: off the shore
-- (159's y=14 edge row -- its "map 0" long-entrance records return to the
-- PARENT slot, which this chain last pushed at DOMA, so the landing is
-- (240,16), not the record's coords), Mobliz (world (220,115) -> map 157;
-- the item shop 164 via (26,21); keeper (29,48) talked across his counter
-- from (29,50); shop 12 row 0 = DRIED MEAT, row 1 = TONIC), then the
-- Veldt grind.
--
-- THE APPEARANCE, measured at battle_main.asm:11940-11960: GAU shows up at
-- the END of a veldt battle -- after every monster dies -- with 3/8 odds
-- (Rand cmp #$a0), party < 4, GAU not yet in the roster ($1EDF bit 3).
-- $2f49/$2f4a arm his character-ai on EVERY veldt battle; $2f4e going
-- nonzero is the appearance itself.
--
-- ================ THE DRIED-MEAT FEED, DRIVEN FOR REAL (#75) ================
-- The old header claimed the first-visit feed "could not be driven
-- honestly, on the vanilla base image too" -- the target cursor "cycles
-- $01<->$02 and can never land on his $04 because the target-group cells
-- ($7B79..$7B7C) were built before GauAppears and are never rebuilt" --
-- and poked $3EBD bit 1 (the switch the feed's reaction would have set)
-- instead.  Humans feed GAU in vanilla, so the probe had to have missed
-- something, and a source pass found it (btlgfx_main.asm):
--
--   * cur_poi_set (_c10659, :1036) is called from the battle gfx update
--     EVERY FRAME (:1742).  Its tail tests `$201d AND w7e61ac AND $2f47`
--     -- monsters-shown AND gau-appearance armed -- and while GAU is on
--     stage it assigns him the SIXTH monster slot's position/size entries
--     (the `+10` stores) and ORs $20 into BOTH the group-0 target cell
--     $7B79 (:1163) and the live targetable-monster mask $0092 (:791).
--     The cells are NOT frozen at battle init; GAU is in them, live, as
--     monster slot 5, every frame he is shown.
--   * What the probe watched cycle "$01<->$02" is $7B7D -- the CHARACTER
--     cursor mask -- because it only ever pressed up/down, which move the
--     cursor WITHIN the party column.  His "$04" expectation was the
--     wrong mask on the wrong side: GAU is monster slot 5, mask $20, in
--     $7B7E.  The input the probe never sent is LEFT -- the side switch
--     onto the monster column, whose only targetable occupant is GAU.
--
-- So the feed here is real play, closed-loop on the engine's own cursor
-- state: on a party menu while $2f4e holds, steer the command cursor
-- ($890F+actor) to ITEM, the item-list index ($8947+actor) to DRIED MEAT,
-- then in target select press LEFT until the monster mask $7B7E reads $20
-- and confirm.  The reaction script sets battle switch 13 itself (the bit
-- the old file poked -- read back and asserted here), GAU runs off with
-- the meat, and his RETURN VISIT (the same 3/8 roll, now branching at
-- :11957) recruits him with no menus at all.  Every target-select pulse
-- logs $7B79..$7B7E/$0092/$2F4E, so if the steer ever fails the run dies
-- WITH the frame evidence the capability-gap report would need.
--
-- THE GRIND IS FOUGHT, NOT KILL-BITTED (#75): the appearance rolls only
-- at a WIN, so wins are earned by the house menu-episode machine (bank
-- boost to 2, dump on Fight), with a self-heal branch (Item -> TONIC,
-- default self target) under 40% HP -- the Tonics are bought in Mobliz
-- alongside the meat.  A wipe reloads a pre-grind checkpoint (three
-- attempts, 17-frame stagger).  SHADOW is gone before this leg, so no
-- leave roll exists to manage.
--
-- THE MINT IS VERIFIED BY RELOAD, because calm-at-capture provably does not
-- imply calm-at-boot.  Measured landing the honest-root pilot (2026-08-03):
-- a capture taken at (214,149) with full world control -- $E8 gate clear,
-- aligned, the doorstep guard below satisfied in 0 frames -- REPRODUCIBLY
-- boots into a battle: every reload read $E8=$28 (bit5, battle pending)
-- within a frame and battle_gaufight's 'world control' wait timed out at
-- 4000 frames, while the live mint timeline sailed on calm past the same
-- capture point.  The only test that matters for a fixture is the
-- consumer's-eye one: reload what you captured and require the calm you
-- promised.
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
-- item cursor = scroll ($8947) + row-on-screen ($894F), get_item_poi's
-- own sum (measured, probe_itemuse)
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
      H.log(string.format("[gau] %s: map=%d (%d,%d)", what, mapIdx(),
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

-- buy `qtyFn()` MORE of shop row `row`, fully CLOSED-LOOP: the list
-- cursor row is MoveCursor's own cell (DP $4E, menu_common.asm:1318) and
-- the quantity is zSelIndex (DP $28, menu_ram.inc) -- both read and
-- steered, never press-counted (menu direction holds auto-repeat: a
-- counted 4-frame hold measurably bought 25 Tonics instead of 14 and
-- parked the potion lap on the wrong row).  Widget deltas (shop.asm
-- MenuState_27): RIGHT +1, LEFT -1, UP +10, DOWN -10, gil-clamped by the
-- handler.  Purchases are verified AFTER the shop closes; mid-menu
-- inventory reads measurably lie.
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

-- ------------------------------------------------------- the grind driver --
-- One driveUntil to GAU's join: world wander for encounters; honest fights
-- (boost + Fight, Tonic-self under 40%); the FEED the moment $2F4E holds
-- with the meat still in the bag; hands-off-plus-taps for the return
-- visit.  All cursor state read live, all input by pad.
local lost = nil
local fightTier = 1
local wipeN = 0
local fed = false                        -- the feed's confirm was pressed
local fedDump = false                    -- one-time battle-inv evidence dump
local feedFrames = {}                    -- target-select evidence rows
local grind = { fights = 0, appearances = 0 }
local function gauOn() return H.readByte(0x2f4e) ~= 0 end
local function fedSwitch() return (H.readByte(0x3EBD) & 0x02) ~= 0 end

-- ------------------------------------- world walk that FIGHTS its randoms --
-- The stretch from the falls shore to Mobliz crosses a VELDT band whose
-- packs are UNRUNNABLE (measured, probe_gaustuck: L+R never ended the
-- (203,116) encounter across 37000 frames) and too stiff for blind tap-A
-- (a SABIN+CYAN party whose row-0 commands are submenus stalls the pack
-- at mon=5).  So transit uses the SAME closed-loop boost-Fight machine
-- the grind does: BFS-step toward (tx,ty), and on any battle steer each
-- actor to Fight (command row 0), dump banked boost, self-Tonic under 40%,
-- until the battle tears down.  No GAU on stage here, so no feed branch.
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
        if st == ST_TOOLS or st == ST_ITEM or st == ST_TGT then
          return { "b" }
        end
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
      return { "a" }                       -- item: self; Fight: default enemy
    end
    if st == ST_TOOLS then return { "b" } end
    return nil
  end
  return H.driveUntil(function()
    return lost ~= nil or not H.worldMode()
        or (H.worldX() == tx and H.worldY() == ty and H.worldHasControl())
  end, budget or 40000, {
    H.call(function()
      if H.frame - hb >= 1800 then
        hb = H.frame
        H.log(string.format("[gau] walk[%s] f%d (%d,%d) b=%s [%s]", what,
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
            H.log("[gau] LOST -- " .. lost)
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
        -- no path (a fresh danger reload can transiently block): wander
        dirFlip = not dirFlip
        H.setPad({ [dirFlip and "left" or "right"] = true })
      end
    end),
  }, "walk fighting -> " .. what)
end

local function grindStep()
  local phase, tick = 0, 0
  local plan, planActor = nil, nil
  local dirFlip = false
  local decided = false
  local hb = -1800
  local mstreak = 0
  local function makePlan(actor)
    local row = cmdRowOf(actor, CMD_ITEM)
    if pHP(actor) > 0 and pMaxHP(actor) > 0
       and pHP(actor) * 10 < pMaxHP(actor) * 4
       and invCount(TONIC) > 0 and row then
      H.log(string.format("[gau] e%d self-heal (TONIC, %d left) [%s]",
        actor, invCount(TONIC), partyLine()))
      return { kind = "item", item = TONIC, row = row }
    end
    local bp = H.readByte(BP + actor * 2)
    local boostMin = fightTier >= 2 and 1 or 2
    local boost = bp >= boostMin and math.min(bp, 3) or 0
    return { kind = "fight", boostLeft = boost }
  end
  local function feedPlan(actor)
    local row = cmdRowOf(actor, CMD_ITEM)
    H.log(string.format("[gau] FEED plan: e%d ITEM row=%s meat idx=%s",
      actor, tostring(row), tostring(battInvIdx(DRIED_MEAT))))
    return { kind = "feed", item = DRIED_MEAT, row = row }
  end
  local function button()
    local st = H.readByte(MSTATE)
    local actor = H.readByte(ACTOR)
    -- while GAU is on stage and the feed is done (or the meat is gone
    -- from the FIELD bag), NOBODY acts: a queued Fight can only target
    -- him -- attacking an appeared GAU drives him off.  The gate is the
    -- FIELD bag ($1869), not the battle inv: measured, $2686 reads no
    -- Dried Meat during the appearance window even though the bag holds
    -- it, so gating on battInvIdx skipped the feed every time.
    if gauOn() and (fed or invCount(DRIED_MEAT) == 0) then
      plan, planActor = nil, nil
      return nil
    end
    if gauOn() and not fed and not fedDump then
      fedDump = true
      local inv = {}
      for i = 0, 15 do
        local id = H.readByte(BATTINV + i * 5)
        if id ~= 0xFF then
          inv[#inv + 1] = string.format("%d:$%02X x%d(f%02X)", i, id,
            H.readByte(BATTINV + i * 5 + 3), H.readByte(BATTINV + i * 5 + 1))
        end
      end
      H.log(string.format("[gau feed] APPEARANCE menu: st=%02X MENU=%02X " ..
        "battInv(meat)=%s fieldbag(meat)=%d | %s", st, H.readByte(MENU),
        tostring(battInvIdx(DRIED_MEAT)), invCount(DRIED_MEAT),
        table.concat(inv, " ")))
    end
    if plan == nil or planActor ~= actor then
      if st ~= ST_CMD then
        if st == ST_TOOLS or st == ST_ITEM or st == ST_TGT then
          return { "b" }        -- parked list state: back out (measured
        end                     -- in the b68 engine)
        return nil
      end
      plan = (gauOn() and not fed and invCount(DRIED_MEAT) > 0) and
        feedPlan(actor) or makePlan(actor)
      planActor = actor
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
      if plan.rowStall and plan.rowStall > 2 then
        plan.rowStall = 0
        return { ({ [0]="up", [1]="left", [2]="right", [3]="down" })[plan.row] }
      end
      plan.rowStall = (plan.rowStall or 0) + 1
      return { cur < plan.row and "down" or "up" }
    end
    if st == ST_ITEM and (plan.kind == "item" or plan.kind == "feed") then
      local want = battInvIdx(plan.item)
      if want == nil then
        if plan.kind == "feed" then
          -- the meat is in the field bag but not the battle item list:
          -- a real capability finding, reported with the list dump
          local inv = {}
          for i = 0, 15 do
            local id = H.readByte(BATTINV + i * 5)
            if id ~= 0xFF then
              inv[#inv + 1] = string.format("%d:$%02X x%d", i, id,
                H.readByte(BATTINV + i * 5 + 3))
            end
          end
          error("gau feed: Dried Meat ($FE) is in the field bag but NOT " ..
            "the battle item list at feed time -- " ..
            table.concat(inv, " "), 0)
        end
        return { "b" }
      end
      local cur = H.readByte(ITEMSCR + actor) + H.readByte(ITEMROW + actor)
      if cur < want then return { "down" } end
      if cur > want then return { "up" } end
      return { "a" }
    end
    if st == ST_TGT then
      if plan.kind == "feed" then
        local row = string.format(
          "f%d tgt: 7B79=%02X 7B7A=%02X 7B7B=%02X 7B7C=%02X chars=%02X " ..
          "mons=%02X $92=%02X 2f4e=%02X",
          H.frame, H.readByte(0x7B79), H.readByte(0x7B7A),
          H.readByte(0x7B7B), H.readByte(0x7B7C), H.readByte(TGTCHARS),
          H.readByte(TGTMONS), H.readByte(0x0092), H.readByte(0x2f4e))
        feedFrames[#feedFrames + 1] = row
        H.log("[gau feed] " .. row)
        local mons = H.readByte(TGTMONS)
        if mons == 0x20 then
          fed = true                     -- the confirm goes to GAU
          plan, planActor = nil, nil
          H.log("[gau feed] cursor ON GAU (mons=$20) -- confirming the meat")
          return { "a" }
        end
        plan.tgtStall = (plan.tgtStall or 0) + 1
        if plan.tgtStall > 40 then
          error("gau feed: 40 target pulses never put the cursor on the " ..
            "monster side -- the frame evidence above is the " ..
            "harness-capability report (see the header)", 0)
        end
        return { "left" }               -- the input the old probe never sent
      end
      if plan.kind == "item" then
        plan, planActor = nil, nil
        return { "a" }                   -- default target = self
      end
      plan, planActor = nil, nil
      return { "a" }                     -- Fight: default enemy
    end
    if st == ST_TOOLS then return { "b" } end   -- not a menu we ever want
    return nil
  end
  -- per-frame feed driver (see the call site).  Holds directions for the
  -- engine's cursor auto-repeat; every branch reads live state.
  local function feedDrive()
    local st = H.readByte(MSTATE)
    local actor = H.readByte(ACTOR)
    if H.readByte(MENU) == 0 then
      -- no character menu up in this instant of the appearance: keep one
      -- coming with a light A tap (the victory/ää dialog also advances)
      H.setPad(H.frame % 4 < 2 and { "a" } or {})
      return
    end
    if st == ST_CMD then
      -- steer the command cursor to ITEM (row known from feedPlan) and A
      local row = cmdRowOf(actor, CMD_ITEM) or 0
      local cur = H.readByte(CMDROW + actor) & 3
      if cur == row then H.setPad({ "a" })
      else H.setPad({ [cur < row and "down" or "up"] = true }) end
      return
    end
    if st == ST_ITEM then
      local want = battInvIdx(DRIED_MEAT)
      if want == nil then H.setPad({ "b" }); return end
      local cur = H.readByte(ITEMSCR + actor) + H.readByte(ITEMROW + actor)
      if cur == want then H.setPad({ "a" })            -- confirm the meat
      else H.setPad({ [cur < want and "down" or "up"] = true }) end  -- HOLD
      return
    end
    if st == ST_TGT then
      local mons = H.readByte(TGTMONS)
      if mons == 0x20 then
        fed = true
        H.log(string.format("[gau feed] cursor ON GAU (mons=$20) f%d -- " ..
          "confirming the meat [%s]", H.frame, partyLine()))
        H.setPad({ "a" })
      elseif mons ~= 0 then
        H.setPad({ "left" })          -- some other monster mask: keep going
      else
        -- on the party side: LEFT switches to the monster column (GAU)
        if H.frame % 20 == 0 then
          H.log(string.format("[gau feed] tgt f%d chars=%02X mons=%02X " ..
            "$92=%02X 2f4e=%02X", H.frame, H.readByte(TGTCHARS),
            H.readByte(TGTMONS), H.readByte(0x0092), H.readByte(0x2f4e)))
        end
        H.setPad(H.frame % 4 < 2 and { "left" } or {})
      end
      return
    end
    if st == ST_TOOLS or st == 0x2D then H.setPad({ "b" }); return end
    H.setPad({})
  end

  local frames = 0
  return H.driveUntil(function()
    frames = frames + 1
    if frames > 245000 and lost == nil then
      lost = string.format("grind deadline (245000 frames): fights=%d " ..
        "appearances=%d fed=%s [%s]", grind.fights, grind.appearances,
        tostring(fed), partyLine())
      H.log("[gau] LOST -- " .. lost)
    end
    return lost ~= nil or inParty(11)
  end, 250000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 1800 then
        hb = H.frame
        H.log(string.format(
          "[gau] grind f%d fights=%d apps=%d 2f4e=%02X fed=%s sw13=%s " ..
          "tonics=%d [%s]", H.frame, grind.fights, grind.appearances,
          H.readByte(0x2f4e), tostring(fed), tostring(fedSwitch()),
          invCount(TONIC), partyLine()))
      end
      -- GAU ON STAGE, handled INDEPENDENT of the battle detector: the
      -- party HP table reads $FFFF during his appearance, so
      -- battleLoadStarted() flickers FALSE and the feed block below is
      -- skipped exactly when the feed must happen (measured: apps counted,
      -- then 2f4e=FF frozen with sw13 toggling and the feed never run).
      if gauOn() and monPresent(5) then
        if fedSwitch() and not fed then
          fed = true
          H.log(string.format("[gau feed] reaction switch 13 SET at f%d " ..
            "-- GAU fed; letting the battle resolve", H.frame))
        end
        if not fed and invCount(DRIED_MEAT) > 0 then
          feedDrive()
          return
        end
        -- fed: the reaction switch 13 is SET (the return-visit recruit
        -- gate), but GAU will not leave the stage on his own in this
        -- build (measured: 2f4e stuck $FF, hands-off did not resolve it).
        -- With the switch already set, ATTACKING him is the honest way to
        -- END the battle -- the header's "attacking drives GAU off"
        -- warning is a PRE-feed concern; post-feed, driving him off just
        -- concludes the fight, and the next veldt appearance runs
        -- recruit_gau (branching on switch 13).  Steer to Fight and swing.
        local st = H.readByte(MSTATE)
        local actor = H.readByte(ACTOR)
        if H.readByte(MENU) == 0 then
          H.setPad(H.frame % 8 < 4 and { "a" } or {})
        elseif st == 0x05 then
          local cur = H.readByte(CMDROW + actor) & 3
          if cur ~= 0 then H.setPad({ up = true })
          else H.setPad({ "a" }) end
        elseif st == 0x38 then
          H.setPad({ "a" })                 -- default target = GAU (lone foe)
        elseif st == 0x30 or st == 0x0A or st == 0x2D then
          H.setPad({ "b" })                 -- back out of any submenu
        else
          H.setPad({})
        end
        return
      end
      if H.battleLoadStarted() then
        if not decided then
          decided = true
          grind.fights = grind.fights + 1
          local w = H.formationWords()
          H.log(string.format("[gau] fight #%d up f%d (%04X %04X %04X %04X)",
            grind.fights, H.frame, w[1], w[2], w[3], w[4]))
        end
        if gauOn() and grind.lastApp ~= grind.fights then
          grind.lastApp = grind.fights
          grind.appearances = grind.appearances + 1
          H.log(string.format(
            "[gau] *** APPEARANCE #%d at fight #%d f%d (2f4e=%02X, " ..
            "fed-switch=%s)", grind.appearances, grind.fights, H.frame,
            H.readByte(0x2f4e), tostring(fedSwitch())))
          H.screenshot(string.format("gau_appear%d", grind.appearances))
        end
        -- wipe watch (a random-encounter wipe is a Game Over)
        local wiped = true
        for e = 0, 3 do
          if pMaxHP(e) > 0 and pHP(e) > 0 then wiped = false end
        end
        wipeN = wiped and wipeN + 1 or 0
        if wipeN >= 90 and not lost then
          lost = string.format("wiped in fight #%d at f%d (tier %d) [%s]",
            grind.fights, H.frame, fightTier, partyLine())
          H.log("[gau] LOST -- " .. lost)
          H.setPad({})
          return
        end
        -- THE FEED runs UNCONDITIONALLY the instant GAU is up and unfed --
        -- BEFORE the menu/mstreak gates below.  GAU's appearance window
        -- flickers the character menu, so gating the feed on a settled
        -- menu (mstreak>=4) missed it every time (seven appearances, zero
        -- feeds).  feedDrive handles every state itself, MENU==0 included.
        tick = tick + 1
        local ph = tick % 30
        if H.readByte(MENU) == 0 then
          plan, planActor, mstreak = nil, nil, 0
          H.setPad(ph < 4 and { "a" } or {})
          return
        end
        mstreak = mstreak + 1
        if mstreak < 4 then H.setPad({}); return end
        if ph == 0 then grind.btn = button() end
        H.setPad(ph < 6 and grind.btn or {})
        return
      end
      decided = false
      plan, planActor = nil, nil
      if not H.worldHasControl() then H.setPad({}); return end
      if not H.worldAligned() then return end
      dirFlip = not dirFlip
      H.setPad({ [dirFlip and "left" or "right"] = true })
    end),
  }, "GAU joins the party")
end

-- ------------------------------------------------------ the retry ladder --
local grindBlob, grindWon = nil, false
local function grindAttempt(n)
  local ldReq
  return H.cond(function() return not grindWon end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[gau] ATTEMPT %d -- reloading the grind " ..
          "checkpoint after a loss (%s)", n, tostring(lost))
      end),
      H.call(function() ldReq = H.requestLoadState(grindBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(ldReq, "attempt " .. n .. ": reload") end),
      H.waitFrames(60 + (n - 1) * 17),
    }, {}),
    H.call(function() lost, fightTier, wipeN = nil, n, 0 end),
    grindStep(),
    H.call(function()
      if lost == nil and inParty(11) then
        grindWon = true
        H.log(string.format("[gau] attempt %d: GAU JOINED after %d fights, " ..
          "%d appearances, fed=%s", n, grind.fights, grind.appearances,
          tostring(fed)))
      end
    end),
  }, {})
end

-- THE RELOAD-VERIFIED MINT (see the header).
local mintBlob, mintDone = nil, false
local function mintAttempt(n)
  local tag = string.format("[gau_joined] mint attempt %d", n)
  local saveReq, loadReq
  return H.cond(function() return not mintDone end, {
    H.call(function() saveReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(saveReq, tag .. ": capture")
      mintBlob = saveReq.blob
      H.log(string.format("%s: captured %d bytes at (%d,%d) f%d -- " ..
        "reloading to verify the consumer's boot", tag, #mintBlob,
        H.worldX(), H.worldY(), H.frame))
      loadReq = H.requestLoadState(mintBlob)
    end),
    H.waitFrames(2),
    H.call(function() H.checkReq(loadReq, tag .. ": verify reload") end),
    H.waitFrames(300),
    H.cond(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned()
         and H.worldX() == 214 and H.worldY() == 149
    end, {
      H.call(function()
        mintDone = true
        H.log(tag .. ": reload stayed calm at the doorstep -- verified")
      end),
    }, {
      H.logStep(function()
        return string.format("%s: reload NOT calm ($E8=%02X bls=%s at " ..
          "%d,%d) -- flee, re-park, recapture", tag, H.readByte(0x00e8),
          tostring(H.battleLoadStarted()), H.worldX(), H.worldY())
      end),
      H.driveUntil(function()
        return H.worldMode() and H.worldHasControl() and H.worldAligned()
      end, 20000, {
        H.call(function()
          if H.battleLoadStarted() then
            H.setPad({ l = true, r = true })   -- flee, honestly
          else
            H.setPad({})
          end
        end),
      }, tag .. ": flee the boot battle, ride out the world reload"),
      H.call(function() H.setPad({}) end),
      H.worldNavTo(214, 149, { maxFrames = 8000, honest = true }),
      H.waitFrames(30),
    }),
  }, {})
end

H.run({ maxFrames = 500000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIdx(), 159, "boot on the shore, map 159")
    H.assertEq(sw(0x3F), 1, "$003F set -- GAU met at the falls")
    H.assertEq(inParty(11), false, "GAU not yet in the party")
  end),

  -- off the shore, to Mobliz, buy the Dried Meat and the grind's Tonics
  H.navTo(8, 14, { maxFrames = 6000, honest = "flee", arrive = function()
    return H.worldMode() end }),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end,
    3000, "on the world", 5),
  worldWalkFight(220, 115, 60000, "shore -> Mobliz"),
  H.call(function()
    if lost ~= nil then
      error("gau: the Veldt transit to Mobliz was lost -- " .. tostring(lost)
        .. " (a #74-style balance finding; do not rig)", 0)
    end
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
  H.call(function()
    H.assertEq(H.readByte(0x9d89), DRIED_MEAT, "shop 12 row 0 is Dried Meat")
    H.log(string.format("[gau] shopping: gil=%d", gil()))
  end),
  tapUntil("a", inState(0x27), "quantity"),
  tapUntil("a", function()
    return invSlot(DRIED_MEAT) ~= nil and mstateMenu() == 0x26
  end, "bought", 2400),
  -- the grind's medicine: Tonics from row 1, bought the verified-loop way
  buyItem(TONIC, 1, function() return 10 - invCount(TONIC) end, "TONIC to 10"),
  tapUntil("b", inState(0x25), "options again"),
  tapUntil("b", function() return H.hasControl() end, "shop closed", 2400),
  H.call(function()
    H.assertEq(invSlot(DRIED_MEAT) ~= nil, true, "Dried Meat in the bag")
    H.log(string.format("[gau] leaving the shop: gil=%d tonics=%d",
      gil(), invCount(TONIC)))
  end),

  -- out of town; settle the world fully (a stray press during the init
  -- transient walks back in -- measured), then clear of the entrance
  H.navTo(29, 53, { maxFrames = 4000, honest = "flee", arrive = function()
    return mapIdx() == 157 end }),
  settle(157, "town again"),
  -- (18,41) is Mobliz's south exit ROW, and a row you leave a town by is a
  -- tile you STEP THROUGH, never one you come to rest on.  navTo to the
  -- doorstep and press SOUTH through the row.
  H.navTo(18, 40, { maxFrames = 8000, honest = "flee", arrive = function()
    return H.worldMode() end }),
  (function()
    local hb = -600
    return H.driveUntil(function() return H.worldMode() end, 1800, {
      H.call(function()
        if H.frame - hb >= 300 then
          hb = H.frame
          H.log(string.format("[gau] leaving Mobliz f%d map=%d (%d,%d) ctl=%s",
            H.frame, mapIdx(), H.fieldX(), H.fieldY(),
            tostring(H.hasControl())))
        end
        H.setPad({ down = true })
      end),
    }, "SOUTH out of Mobliz onto the world")
  end)(),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 3000, "world live again", 5),
  worldWalkFight(215, 119, 40000, "Mobliz -> Veldt staging"),
  H.call(function()
    if lost ~= nil then
      error("gau: the walk to the Veldt staging was lost -- " ..
        tostring(lost), 0)
    end
  end),

  -- the grind, honestly, behind the ladder (see the header)
  (function()
    local ckReq
    return H.cond(function() return true end, {
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "grind checkpoint")
        grindBlob = ckReq.blob
        H.log(string.format("[gau] grind checkpoint captured (%d bytes) f%d",
          #grindBlob, H.frame))
      end),
    }, {})
  end)(),
  grindAttempt(1),
  grindAttempt(2),
  grindAttempt(3),
  H.call(function()
    if not grindWon then
      error(string.format("gau: the Veldt grind did not recruit GAU on " ..
        "any of 3 honest attempts -- last: %s", tostring(lost)), 0)
    end
    H.assertEq(fed, true,
      "the Dried Meat was fed to GAU through the real battle Item menu " ..
      "(the old 'measured undrivable' claim is retired -- see the header)")
    H.assertEq(invCount(DRIED_MEAT), 0, "the meat left the bag with GAU")
  end),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 20000, "world after the join", 5),
  H.waitFrames(120),

  -- park on Crescent Mountain's doorstep (one short of the (214,148)
  -- entrance) and mint; waypoints keep each BFS disc small (the fence
  -- S-curve -- see the route notes in the git history of this file)
  H.worldNavTo(216, 128, { maxFrames = 20000, honest = true }),
  H.worldNavTo(218, 140, { maxFrames = 15000, honest = true }),
  H.worldNavTo(220, 149, { maxFrames = 15000, honest = true }),
  H.worldNavTo(219, 153, { maxFrames = 8000, honest = true }),
  H.worldNavTo(217, 155, { maxFrames = 8000, honest = true }),
  H.worldNavTo(212, 156, { maxFrames = 8000, honest = true }),
  H.worldNavTo(205, 153, { maxFrames = 8000, honest = true }),
  H.worldNavTo(207, 151, { maxFrames = 8000, honest = true }),
  H.worldNavTo(214, 149, { maxFrames = 10000, honest = true }),
  -- The landing step itself can WIN the encounter roll ($E8 bit5 the
  -- instant it wins); require REAL control before minting, fleeing any
  -- landing-roll battle -- the post-battle reload restores this tile.
  H.driveUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 20000, {
    H.call(function()
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true })   -- flee, honestly
      else
        H.setPad({})
      end
    end),
  }, "calm, controllable doorstep (flee any landing-roll battle)"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "on the world")
    H.assertEq(H.worldX(), 214, "x=214")
    H.assertEq(H.worldY(), 149, "y=149 -- one short of the Crescent entrance")
    H.assertEq(inParty(11), true, "GAU in the party")
    H.assertEq(inParty(5), true, "SABIN in the party")
    H.assertEq(inParty(2), true, "CYAN in the party")
    H.assertEq((H.readByte(0x1EDF) & 0x08) ~= 0, true,
      "GAU in the available-characters roster")
    H.log(string.format("[gau_joined] f%d world (%d,%d)", H.frame,
      H.worldX(), H.worldY()))
    H.screenshot("gau_joined")
  end),
  mintAttempt(1),
  mintAttempt(2),
  mintAttempt(3),
  H.call(function()
    H.assertEq(mintDone, true,
      "a reload-verified calm doorstep capture within 3 attempts")
    H.emitBlob("gau_joined.mss", mintBlob)
  end),
  H.logStep(function()
    return string.format("gau_joined minted at frame %d world (%d,%d) -- " ..
      "GAU fed and recruited through real menus", H.frame,
      H.worldX(), H.worldY())
  end),
})
