-- gen_sabin_gau.lua -- step 10 of SABIN's scenario: GAU.  Generates:
--   gau_joined.mss   world (214,147), Crescent Mountain's entry point, party
--                    SABIN+CYAN+GAU.  The trench step starts from here.

-- Every Crescent Mountain helmet-scene variant gates on $01AB (GAU in the
-- party), so the trench cannot open without him.  The route: off the shore
-- (159's y=14 edge row; its "map 0" long-entrance records return to the
-- parent slot, which this chain last pushed at Doma, so the landing is
-- (240,16) rather than the record's coords), Mobliz (world (220,115) -> map 157;
-- the item shop 164 via (26,21); keeper (29,48) talked across his counter
-- from (29,50); shop 12 row 0 = DRIED MEAT, row 1 = TONIC), then the
-- Veldt grind.

-- The generator therefore selects Active battle mode through Config, arms
-- Cyan's delayed Retort, and parks a Tonic target cursor while Retort kills
-- the last monster.  When Gau appears, that already-selected Tonic is sent
-- left to his $20 monster target and submitted as the harmless normalizing
-- action.  The fresh menu then selects Dried Meat from inventory slot zero,
-- targets the now-normalized Gau the same way, and submits it.  AIScript::_370
-- consumes the meat, sets battle switch 13, and recruits Gau in that same
-- encounter.  Every gameplay change is controller input; all addresses here
-- are observations used to close the loop. Wins are earned by the house
-- menu-episode machine (bank boost to 2, dump on Fight), with a self-heal
-- branch under 40% HP. A wipe reloads a pre-grind checkpoint behind a
-- three-attempt retry ladder (17-frame stagger).
--
-- The generated state is verified by reload, not just a calm capture: a
-- capture taken with full world control satisfied can still boot into a
-- pending battle on reload (a calm capture does not imply a calm boot), so
-- generation replays the captured blob and requires the same calm the
-- fixture promises to its consumers.

local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/falls_done.mss.lua"
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
local ST_CMD, ST_ITEM, ST_RAGE, ST_TGT, ST_TOOLS =
  0x05, 0x0A, 0x1E, 0x38, 0x30
local CMD_FIGHT, CMD_ITEM, CMD_SWDTECH, CMD_BLITZ, CMD_RAGE, CMD_LEAP =
  0x00, 0x01, 0x07, 0x0A, 0x10, 0x11
local RETORT, PUMMEL, SUPLEX = 0x56, 0x5D, 0x5F
local CMDTBL, CMDROW, ITEMLIST = 0x202E, 0x890F, 0x4005
local ITEMSCR, ITEMROW = 0x8947, 0x894F
local BLCOL, BLROW = 0x8963, 0x8967
local RAGESCR, RAGECOL, RAGEROW = 0x892B, 0x892F, 0x8933
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

-- Put Dried Meat first through the ordinary field Item/Use move UI.  Battle
-- inventory preserves this order, making the live post-normalization select a
-- short, deterministic controller path.
local function moveMeatToFront(keepMenu)
  local phase = 0
  local function driveCursor(state, target, what)
    return H.driveUntil(function()
      return H.readByte(ZMENUSTATE) == state and H.readByte(0x4B) == target
    end, 2400, {
      H.call(function()
        phase = (phase + 1) % 8
        local cur = H.readByte(0x4B)
        H.setPad(phase < 4 and
          { [cur < target and "down" or "up"] = true } or {})
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
    H.release(), H.waitFrames(30), H.pressButtons({ "a" }, 4),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x19 end,
      600, "field item move mode", 5),
    driveCursor(0x19, 0, "move Dried Meat to slot 0"),
    H.release(), H.waitFrames(30), H.pressButtons({ "a" }, 4),
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
    H.cond(function() return not keepMenu end, {
      H.pressButtons({ "b" }, 4),
      H.waitUntil(function()
        return H.worldMode() and H.worldHasControl() and H.worldAligned()
            or not H.worldMode() and H.hasControl() and H.tileAligned()
      end, 1800, "field after inventory move", 5),
    }, {}),
  }, {})
end

-- Open the main menu if it is not already up.  moveMeatToFront opens it as
-- a side effect of needing it, but its whole body sits behind "the meat is
-- not already in slot 0" (`invSlot(DRIED_MEAT) ~= 0`), so when the meat is
-- already at the front the menu is never opened and the caller is left
-- pressing buttons at the field.

-- Why the two lineages differ in where the meat lands is UNVERIFIED: the
-- observable difference is that this one arrived at the counter with
-- tonic=0 in the bag and s2 arrived with tonic=99, and an emptied stack
-- plausibly frees the front slot the purchase then takes.  The repair does
-- not depend on that being the reason -- the drive must not assume a menu
-- it did not open -- so it is recorded as the open question it is.
local function openMainMenu(what)
  return H.cond(function() return H.readByte(ZMENUSTATE) ~= MAIN_MENU end, {
    H.pressButtons({ "x" }, 4),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == MAIN_MENU end,
      600, what, 5),
  }, {})
end

local function prepareFeed()
  return H.cond(function() return true end, {
    H.release(),
    H.waitFrames(30),
    moveMeatToFront(true),
    H.release(),
    H.waitFrames(30),
    openMainMenu("main menu for Config"),
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
      return H.hasControl() and H.tileAligned()
    end, 1800, "field after Config", 5),
  }, {})
end

-- shop buys ride the library's closed-loop, purse-clamp-accepting
-- drive (M.buyItem, promoted from this file's local copy -- the
-- cursor cells, the widget deltas, and the clamp acceptance are
-- documented at the definition)
local buyItem = H.buyItem

-- ------------------------------------------------------- the grind driver --
-- One driveUntil to GAU's join: world wander for encounters; input-driven
-- fights (boost + Fight, Tonic-self under 40%); the FEED the moment $2F4E
-- holds with the meat still in the bag; hands-off-plus-taps for the return
-- visit.  All cursor state read live, all input by pad.
local lost = nil
local fightTier = 1
local wipeN = 0
local fed = false                        -- observed feed reaction completed
local grind = { fights = 0, appearances = 0 }
local function gauOn()
  local targettable = H.readByte(0x2f4e)
  local enemyChar = H.readByte(0x3a40)
  return targettable ~= 0xff and enemyChar ~= 0xff
     and (targettable & enemyChar) ~= 0
end
local function gauPresent()
  local slot = H.readByte(0x300b)
  if slot == 0xff or slot > 6 then return false end
  local mask = H.readByte(0x3018 + slot)
  return (H.readByte(0x3aa0 + slot) & 1) ~= 0
     and (H.readByte(0x3a40) & mask) ~= 0
end
local function fedSwitch() return (H.readByte(0x3EBD) & 0x02) ~= 0 end

-- The "unrunnable" measurement is one formation at one tile, not a rule
-- about the Veldt: nothing in the run path reads the Veldt flag ($11E4 is
-- read at battle_main.asm:14150, :14211 and :15779 only, none of them the
-- run code), so whether a given pack can be fled is that formation's own
-- data.  Do not widen it to "no Veldt battle can be fled" without a
-- decode of the pool.

-- Every caller that crosses open Veldt now passes opts.segment and runs
-- behind a ladder with an H.fieldCare stop between battles.  Do not add a
-- bare continuous one back: all three of them wiped a party that way.
local function worldWalkFight(tx, ty, budget, what, arriveOffWorld, opts)
  opts = opts or {}
  local tick, dirFlip, hb = 0, false, -1800
  local plan, planActor, btn, mstreak = nil, nil, nil, 0
  local calm = 0
  local fought, wasBattle = 0, false
  local stuckN, battleFrames, segFrames = 0, 0, 0
  local segCalm, coasting = 0, false
  local fleeN, refusedN = 0, 0      -- opts.flee: frames held / cant-run debounce
  local function makePlan(actor)
    -- `worldWalkFight()` episodes are constructed before H.run starts, so
    -- resolve this at execution time.  The field party byte is repurposed in
    -- battle; the observed completed feed is the durable third-member fact.
    local partyEntities = fed and 3 or 2
    local row = cmdRowOf(actor, CMD_ITEM)
    if row then
      for e = 0, partyEntities - 1 do
        if pMaxHP(e) > 0 and pHP(e) == 0 and battInvIdx(FENIX_DOWN) then
          H.log(string.format("[gau] walk revive e%d with Fenix Down [%s]",
            e, partyLine()))
          return { kind = "item", item = FENIX_DOWN, target = e, row = row }
        end
      end
      local target, worst = nil, 8
      for e = 0, partyEntities - 1 do
        if pHP(e) > 0 and pMaxHP(e) > 0 then
          local frac = pHP(e) * 10 // pMaxHP(e)
          local healBelow = 4
          if frac < worst and frac < healBelow then target, worst = e, frac end
        end
      end
      if target then
        local missing = pMaxHP(target) - pHP(target)
        local item = missing >= 80 and battInvIdx(POTION) and POTION
                  or battInvIdx(TONIC) and TONIC
                  or battInvIdx(POTION) and POTION or nil
        if item then
          H.log(string.format("[gau] walk heal e%d with $%02X [%s]", target,
            item, partyLine()))
          return { kind = "item", item = item, target = target, row = row }
        end
      end
    end
    -- Gau's shared row is terrain-dependent: LEAP on the Veldt, FIGHT off it.
    -- Read the built list.  Never select Leap on this fixture-generating
    -- route (it deliberately removes Gau).  On the Veldt, use his actual
    -- attack verb instead: Rage row 1, entry 0 (Brawler from InitRage).
    -- Skipping Gau made every post-join encounter a two-character fight;
    -- the Nautiloid/Exocite/Pterodon pack then outdamaged Tonics on three
    -- staggered timelines.  Off the Veldt the real Fight row remains valid.
    if fed and actor == 2 then
      local row0 = H.readByte(CMDTBL + actor * 12)
      if row0 == CMD_FIGHT then return { kind = "fight", boostLeft = 0 } end
      local rageRow = cmdRowOf(actor, CMD_RAGE)
      if row0 == CMD_LEAP and rageRow then
        return { kind = "rage", row = rageRow }
      end
      return { kind = "switch" }
    end
    local blitzRow = cmdRowOf(actor, CMD_BLITZ)
    if fed and actor == 0 and pMP(actor) >= 4 and blitzRow then
      return { kind = "blitz",
               skill = pMP(actor) >= 13 and SUPLEX or PUMMEL,
               row = blitzRow }
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
      if plan.kind == "switch" then return { "x" } end
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
    if st == ST_RAGE and plan.kind == "rage" then
      local scroll = H.readByte(RAGESCR + actor)
      local col = H.readByte(RAGECOL + actor)
      local row = H.readByte(RAGEROW + actor)
      if col > 0 then return { "left" } end
      if scroll + row > 0 then return { "up" } end
      return { "a" }
    end
    if st == ST_TGT then
      if plan.kind == "item" and plan.target ~= nil then
        local chars, mons = H.readByte(TGTCHARS), H.readByte(TGTMONS)
        if mons ~= 0 then return { "right" } end
        local wantMask = 1 << plan.target
        if chars == wantMask then
          plan, planActor = nil, nil
          return { "a" }
        end
        local cur = 0
        for e = 0, 3 do
          if chars & (1 << e) ~= 0 then cur = e; break end
        end
        return { cur < plan.target and "down" or "up" }
      end
      plan, planActor = nil, nil
      return { "a" }                       -- Fight: default enemy
    end
    if st == ST_TOOLS and plan.kind == "blitz" then
      local want
      for i = 0, 7 do
        if H.readByte(ITEMLIST + i * 3) == plan.skill then want = i end
      end
      if want == nil then
        plan, planActor = nil, nil
        return { "b" }
      end
      local wc, wr = want % 2, want // 2
      local cc, cr = H.readByte(BLCOL + actor), H.readByte(BLROW + actor)
      if cc ~= wc then return { wc > cc and "right" or "left" } end
      if cr ~= wr then return { wr > cr and "down" or "up" } end
      return { "a" }
    end
    if st == ST_TOOLS then return { "b" } end
    return nil
  end
  return H.driveUntil(function()
    local parked = H.worldMode() and H.worldX() == tx and H.worldY() == ty
       and H.worldHasControl() and H.worldAligned()
       and not H.battleLoadStarted() and (H.readByte(0x00E8) & 0x20) == 0
    calm = parked and calm + 1 or 0

    if opts.segment and H.worldMode() and H.worldHasControl()
       and H.worldAligned() and not H.battleLoadStarted()
       and (fought >= 1
            or (not arriveOffWorld and H.worldX() == tx
                and H.worldY() == ty)) then
      segCalm = segCalm + 1
      coasting = true
      if segCalm >= 60 then return true end
    else
      segCalm, coasting = 0, false
    end
    if opts.segment then
      segFrames = segFrames + 1
      if segFrames > (budget or 40000) - 400 and lost == nil then
        lost = string.format("segment %s timed out (%d frames, at %d,%d) " ..
          "-- a stiff draw; the ladder reloads", what, segFrames,
          H.worldX(), H.worldY())
        H.log("[gau] " .. lost)
      end
    end
    return lost ~= nil or (arriveOffWorld and not H.worldMode()) or calm >= 30
  end, budget or 40000, {
    H.call(function()
      if H.battleLoadStarted() then
        battleFrames = (battleFrames or 0) + 1
        if battleFrames == 120 then
          local sp = {}
          for s = 0, 5 do sp[#sp + 1] = string.format("%04X",
            H.readWord(0x57C0 + s * 2)) end
          H.log(string.format("[gau] walk[%s] battle up f%d species %s [%s]",
            what, H.frame, table.concat(sp, " "), partyLine()))
        end
        wasBattle = true
      elseif wasBattle then
        wasBattle, fought, battleFrames = false, fought + 1, 0
      end
      if H.frame - hb >= 1800 then
        hb = H.frame
        H.log(string.format("[gau] walk[%s] f%d (%d,%d) b=%s [%s]", what,
          H.frame, H.worldX(), H.worldY(),
          tostring(H.battleLoadStarted()), partyLine()))
      end
      if H.battleLoadStarted() then
        local partyEntities = fed and 3 or 2
        local wiped = true
        for e = 0, partyEntities - 1 do
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
        if opts.flee then
          refusedN = ((H.readByte(0x00b1) & 0x02) ~= 0) and refusedN + 1 or 0
          fleeN = fleeN + 1
          if refusedN < 60 and fleeN <= 1800 then
            local pad = { l = true, r = true }
            if tick % 16 < 3 then pad.b = true end
            H.setPad(pad)
            return
          end
          if fleeN == 1801 or refusedN == 60 then
            H.log(string.format("[gau] walk[%s] flee %s at f%d -- " ..
              "fighting this one out", what,
              refusedN >= 60 and "REFUSED ($b1 can't-run)" or "capped",
              H.frame))
            fleeN = fleeN + 1     -- log once
          end
        end
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
      fleeN, refusedN = 0, 0
      local live = H.worldHasControl() and H.worldAligned()
         and bright() >= 15
      if not live then
        local partyEntities = fed and 3 or 2
        local sane, alive = 0, 0
        for e = 0, partyEntities - 1 do
          local mx = pMaxHP(e)
          if mx > 0 and mx < 1000 then
            sane = sane + 1
            if pHP(e) > 0 then alive = alive + 1 end
          end
        end
        if sane >= partyEntities and alive == 0 then
          wipeN = wipeN + 1
          if wipeN >= 90 and not lost then
            lost = string.format("wiped (game over) during %s at f%d [%s]",
              what, H.frame, partyLine())
            H.log("[gau] LOST -- " .. lost)
          end
          H.setPad({})
          return
        end
        wipeN = 0
        stuckN = stuckN + 1
        if stuckN == 601 then
          H.log(string.format("[gau] walk[%s] STUCK 600 frames off-world " ..
            "f%d: menu=%02X map=%d field(%d,%d) ctl=%s dlg=%s -- B taps",
            what, H.frame, H.readByte(0x0026), mapIdx(),
            H.fieldX(), H.fieldY(), tostring(H.hasControl()),
            tostring(H.dialogWaiting())))
        end
        if stuckN > 600 then
          local ph = stuckN % 24
          if stuckN > 2400 and ph >= 16 and ph < 20 then
            H.setPad({ "a" })
          elseif ph < 4 then
            H.setPad({ "b" })
          else
            H.setPad({})
          end
        else
          H.setPad({})
        end
        return
      end
      stuckN = 0
      -- Coasting toward a segment exit (see the predicate): stand still.
      -- A step here would start a fresh encounter roll, which is the
      -- exact race the coast exists to flush out.
      if coasting then H.setPad({}); return end
      local p = H.worldBfs(tx, ty)
      if p and #p > 0 then
        H.setPad({ [p[1]] = true })
      else
        -- No path.  Two causes: a fresh danger reload can transiently
        -- block one, and a walk parked ON its goal tile has an empty one,
        -- which is how an arriveOffWorld transit re-enters a town
        -- entrance it is already standing on.  Flip on a period rather
        -- than per frame: a direction that changes every frame never
        -- completes a step, so the old per-frame flip could only jitter.
        dirFlip = (H.frame // 24) % 2 == 0
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
  local meatPrimed = {}
  local retortArmed, retortUnavailable = false, false
  local feeding, targetBankLogged = false, false
  local feedConfirmUntil, feedSubmissions = nil, 0
  local function makePlan(actor)
    local row = cmdRowOf(actor, CMD_ITEM)
    local nmon = liveMonsters()
    if row then
      for e = 0, 1 do
        if pMaxHP(e) > 0 and pHP(e) == 0 and battInvIdx(FENIX_DOWN) then
          H.log(string.format("[gau] revive e%d with Fenix Down [%s]",
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
          H.log(string.format("[gau] heal e%d with $%02X [%s]", target,
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
        H.log(string.format("[gau] Cyan banks BP with $%02X (bp=%d)",
          safeItem, H.readByte(BP + actor * 2)))
        return { kind = "item", item = safeItem, target = actor, row = row }
      end
    end
    if actor == 1 and nmon == 1 and not retortArmed
       and not retortUnavailable and bushidoRow then
      H.log(string.format("[gau] Cyan plans Retort: row=%d bp=%d mp=%d",
        bushidoRow, H.readByte(BP + actor * 2), pMP(actor)))
      return { kind = "retort", skill = RETORT, row = bushidoRow }
    end
    if nmon == 1 and retortArmed and row and not meatPrimed[actor]
       and battInvIdx(TONIC) then
      H.log(string.format("[gau] park actor %d in Tonic targeting", actor))
      return { kind = "prime", item = TONIC, row = row }
    end
    if actor == 0 and nmon == 1 and not retortArmed and row then
      local safeItem = battInvIdx(TONIC) and TONIC
                    or battInvIdx(POTION) and POTION or nil
      if safeItem then
        return { kind = "item", item = safeItem, target = 1, row = row }
      end
    end
    if actor == 0 and nmon == 1 and pMP(actor) < 13 and row then
      local mpItem = battInvIdx(ETHER) and ETHER
                  or battInvIdx(TINCTURE) and TINCTURE or nil
      if mpItem then
        return { kind = "item", item = mpItem, target = actor, row = row }
      end
    end
    local blitzRow = cmdRowOf(actor, CMD_BLITZ)
    if actor == 0 and nmon == 1 and pMP(actor) >= 4 and blitzRow then
      return { kind = "blitz",
               skill = pMP(actor) >= 13 and SUPLEX or PUMMEL,
               row = blitzRow }
    end
    local bp = H.readByte(BP + actor * 2)
    local boostMin = fightTier >= 2 and 1 or 2
    local boost = bp >= boostMin and math.min(bp, 3) or 0
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
      plan = makePlan(actor)
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
      local want
      for i = 0, 7 do
        if H.readByte(ITEMLIST + i * 3) == plan.skill then want = i end
      end
      if want == nil then
        if plan.kind == "retort" then retortUnavailable = true end
        plan, planActor = nil, nil
        return { "b" }
      end
      local wc, wr = want % 2, want // 2
      local cc, cr = H.readByte(BLCOL + actor), H.readByte(BLROW + actor)
      if cc ~= wc then return { wc > cc and "right" or "left" } end
      if cr ~= wr then return { wr > cr and "down" or "up" } end
      if plan.kind == "retort" then
        retortArmed = true
        H.log(string.format("[gau] Retort armed at f%d with monster HP=%d",
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
      if plan.kind == "item" then
        local chars, mons = H.readByte(TGTCHARS), H.readByte(TGTMONS)
        if mons ~= 0 then return { "right" } end
        local wantMask = 1 << plan.target
        if chars == wantMask then
          plan, planActor = nil, nil
          return { "a" }
        end
        local cur = 0
        for e = 0, 3 do
          if chars & (1 << e) ~= 0 then cur = e; break end
        end
        return { cur < plan.target and "down" or "up" }
      end
      plan, planActor = nil, nil
      return { "a" }
    end
    return nil
  end
  -- per-frame feed driver (see the call site).  Holds directions for the
  -- engine's cursor auto-repeat; every branch reads live state.
  local function feedDrive()
    local st = H.readByte(MSTATE)
    local actor = H.readByte(ACTOR)
    phase = (phase + 1) % 8
    fed = fedSwitch() or invCount(DRIED_MEAT) == 0
    if fed or feedSubmissions >= 2 then
      H.setPad({})
      return
    end
    if H.readByte(MENU) == 0 then
      -- Dismiss Gau's hungry turn so the already-selected normalizing item
      -- can execute.  This is safe only while no party menu owns input.
      H.setPad(H.frame % 30 < 4 and { "a" } or {})
      return
    end
    if st ~= ST_TGT then feedConfirmUntil = nil end
    if st == ST_CMD then
      local row = cmdRowOf(actor, CMD_ITEM) or 0
      local cur = H.readByte(CMDROW + actor) & 3
      if cur == row then H.setPad(phase < 2 and { "a" } or {})
      else H.setPad(phase < 2 and
        { [cur < row and "down" or "up"] = true } or {}) end
      return
    end
    if st == ST_ITEM then
      local want = battInvIdx(DRIED_MEAT)
      if want == nil then H.setPad({}); return end
      local cur = H.readByte(ITEMSCR + actor) + H.readByte(ITEMROW + actor)
      if cur == want then H.setPad(phase < 2 and { "a" } or {})
      else H.setPad(phase < 2 and
        { [cur < want and "down" or "up"] = true } or {}) end
      return
    end
    if st == ST_TGT then
      local mons = H.readByte(TGTMONS)
      if mons == 0x20 then
        if feedConfirmUntil == nil then
          feedSubmissions = feedSubmissions + 1
          feedConfirmUntil = H.frame + 3
          H.log(string.format("[gau feed] confirm item $%02X submission #%d " ..
            "on Gau (%s target model)", H.readByte(0x7a85), feedSubmissions,
            gauOn() and "appearance" or gauPresent() and "normalized"
              or "unknown"))
        end
        H.setPad(H.frame <= feedConfirmUntil and { "a" } or {})
      else
        H.setPad(H.frame % 4 < 2 and { "left" } or {})
      end
      return
    end
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
      -- Gau's special appearance can flicker battleLoadStarted() false, so
      -- latch it before the ordinary battle gate.  Retort has delivered the
      -- final blow while a Tonic target screen remained open.
      if not feeding and gauOn() then
        feeding = true
        grind.appeared = true
        grind.appearances = grind.appearances + 1
        H.log(string.format("[gau] *** APPEARANCE #%d at fight #%d f%d",
          grind.appearances, grind.fights, H.frame))
        H.screenshot(string.format("gau_appear%d", grind.appearances))
      end
      if feeding then
        feedDrive()
        return
      end
      if H.battleLoadStarted() then
        if not decided then
          decided = true
          meatPrimed = {}
          retortArmed = false
          targetBankLogged = false
          plan, planActor = nil, nil
          grind.fights = grind.fights + 1
          local w = H.formationWords()
          H.log(string.format("[gau] fight #%d up f%d (%04X %04X %04X %04X)",
            grind.fights, H.frame, w[1], w[2], w[3], w[4]))
        end
        -- wipe watch (a random-encounter wipe is a Game Over)
        -- This step's live party is exactly Sabin+Cyan.  Unused battle slots
        -- retain stale nonzero HP words, so counting all four masks a real
        -- two-character wipe and leaves the driver wandering through Game
        -- Over memory.
        local wiped = pHP(0) == 0 and pHP(1) == 0
        wipeN = wiped and wipeN + 1 or 0
        if wipeN >= 90 and not lost then
          lost = string.format("wiped in fight #%d at f%d (tier %d) [%s]",
            grind.fights, H.frame, fightTier, partyLine())
          H.log("[gau] LOST -- " .. lost)
          H.setPad({})
          return
        end
        tick = tick + 1
        local ph = tick % 30
        local activeActor = H.readByte(ACTOR)
        if (H.readByte(MSTATE) == ST_ITEM or H.readByte(MSTATE) == ST_TGT)
           and meatPrimed[activeActor] then
          if not targetBankLogged then
            targetBankLogged = true
            H.log(string.format("[gau] RETORT TONIC BANK READY f%d hp=%d",
              H.frame, select(2, liveMonsters())))
          end
          H.setPad({})
          return
        end
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
    H.call(function()
      lost, fightTier, wipeN, fed = nil, n, 0, false
    end),
    grindStep(),
    (function()
      local phase = 0
      return H.cond(function() return lost == nil and inParty(11) end, {
        H.driveUntil(function()
          return H.worldMode() and H.worldHasControl() and H.worldAligned()
        end, 20000, {
          H.call(function()
            phase = (phase + 1) % 12
            H.setPad(phase < 4 and { "a" } or {})
          end),
        }, "advance Gau's join event to the world"),
      }, {})
    end)(),
    H.call(function()
      fed = fedSwitch() or invCount(DRIED_MEAT) == 0
      if lost == nil and inParty(11) and fed then
        grindWon = true
        H.log(string.format("[gau] attempt %d: GAU JOINED after %d fights, " ..
          "%d appearances, fed=%s", n, grind.fights, grind.appearances,
          tostring(fed)))
      end
    end),
  }, {})
end

-- THE RELOAD-VERIFIED GENERATE (see the header).
local genBlob, genDone = nil, false
local function genAttempt(n)
  local tag = string.format("[gau_joined] generation attempt %d", n)
  local saveReq, loadReq
  return H.cond(function() return not genDone end, {
    H.call(function() saveReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(saveReq, tag .. ": capture")
      genBlob = saveReq.blob
      H.log(string.format("%s: captured %d bytes at (%d,%d) f%d -- " ..
        "reloading to verify the consumer's boot", tag, #genBlob,
        H.worldX(), H.worldY(), H.frame))
      loadReq = H.requestLoadState(genBlob)
    end),
    H.waitFrames(2),
    H.call(function() H.checkReq(loadReq, tag .. ": verify reload") end),
    H.waitFrames(300),
    H.cond(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned()
         and H.worldX() == 214 and H.worldY() == 149
    end, {
      H.call(function()
        genDone = true
        H.log(tag .. ": reload stayed calm at the entry point -- verified")
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
            H.setPad({ l = true, r = true })   -- flee, with real input
          else
            H.setPad({})
          end
        end),
      }, tag .. ": flee the boot battle, ride out the world reload"),
      H.call(function() H.setPad({}) end),
      H.worldNavTo(214, 149, { maxFrames = 8000, playBattles = true }),
      H.waitFrames(30),
    }),
  }, {})
end

-- Fighting the crossing earns nothing but gil: a Veldt battle's experience
-- sum is skipped monster by monster while $11E4 bit 1 is set
-- (battle_main.asm:15778-15781), which is why the party cannot level its
-- way out of this stretch and why the answer has to be the heal rate.
local transitBlob, transitDone = nil, false
local function transitCheckpoint()
  local ckReq
  return H.cond(function() return true end, {
    H.call(function() ckReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(ckReq, "shore-transit checkpoint")
      transitBlob = ckReq.blob
      H.log(string.format("[gau] shore-transit checkpoint captured " ..
        "(%d bytes) f%d [%s]", #transitBlob, H.frame, partyLine()))
    end),
  }, {})
end
local function transitAttempt(n)
  local ldReq
  local reloadSteps = {
    H.logStep(function()
      return string.format("[gau] shore transit ATTEMPT %d -- reloading " ..
        "(%s)", n, tostring(lost))
    end),
    H.call(function() ldReq = H.requestLoadState(transitBlob) end),
    H.waitFrames(2),
    H.call(function() H.checkReq(ldReq, "transit attempt " .. n) end),
    H.waitFrames(60 + (n - 1) * 17),
  }

  -- The pacing MUST run after the `lost` reset below: worldWalkFight's
  -- terminator treats a set `lost` as done, and the first draft put the
  -- pacing inside the reload block, where attempt n-1's loss string was
  -- still live -- every jitter step "satisfied after 0 frames" and the
  -- rungs replayed identically anyway.
  -- The 12000-frame budget matches the transit segments': the accumulator
  -- is primed enough that the jitter's very first step can (and does) eat
  -- the route's opening fight, and a 3000 budget timed out inside it.
  local jitterSteps = {}
  for j = 2, n do
    jitterSteps[#jitterSteps + 1] = worldWalkFight(193, 105, 12000,
      string.format("transit a%d jitter %d out", n, j), false, { flee = true })
    jitterSteps[#jitterSteps + 1] = worldWalkFight(192, 105, 12000,
      string.format("transit a%d jitter %d back", n, j), false, { flee = true })
  end
  local steps = {
    H.cond(function() return n > 1 end, reloadSteps, {}),
    H.call(function() lost, wipeN = nil, 0 end),
    H.cond(function() return n > 1 end, jitterSteps, {}),
  }
  -- The transit ends OFF the world (Mobliz's entrance tile loads map 157),
  -- so "still on the world" is the loop condition rather than a tile test.
  for i = 1, 20 do
    steps[#steps + 1] = H.cond(function()
      return lost == nil and H.worldMode()
    end, {
      worldWalkFight(220, 115, 12000,
        string.format("transit a%d seg %d", n, i), true,
        { segment = true, flee = true }),
      H.cond(function() return lost == nil and H.worldMode() end, {
        H.fieldCare({ tag = string.format("transit a%d care %d", n, i),
                      threshold = 0.9, maxFrames = 12000 }),
      }, {}),
    }, {})
  end
  steps[#steps + 1] = H.call(function()
    if lost == nil and not H.worldMode() then
      transitDone = true
      H.log(string.format("[gau] shore transit attempt %d ARRIVED at " ..
        "Mobliz f%d [%s]", n, H.frame, partyLine()))
    elseif lost == nil then
      lost = string.format("transit attempt %d never reached Mobliz in 20 " ..
        "segments; at (%d,%d) f%d", n, H.worldX(), H.worldY(), H.frame)
      H.log("[gau] " .. lost)
    end
  end)
  return H.cond(function() return not transitDone end, steps, {})
end

-- The staging-walk ladder (see the SIEGE comment at the call site): the
-- checkpoint is cut on the live world just south of Mobliz, and an
-- attempt is the whole segmented siege -- fight one battle, field-care,
-- repeat -- ending parked at (215,119).  A wipe reloads with the house
-- 17-frame stagger for a different formation timeline.
local walkBlob, walkDone = nil, false
local function walkCheckpoint()
  local ckReq
  return H.cond(function() return true end, {
    H.call(function() ckReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(ckReq, "staging-walk checkpoint")
      walkBlob = ckReq.blob
      H.log(string.format("[gau] staging-walk checkpoint captured " ..
        "(%d bytes) f%d", #walkBlob, H.frame))
    end),
  }, {})
end
local function walkAttempt(n)
  local ldReq
  local steps = {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[gau] staging-walk ATTEMPT %d -- reloading " ..
          "(%s)", n, tostring(lost))
      end),
      H.call(function() ldReq = H.requestLoadState(walkBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(ldReq, "walk attempt " .. n) end),
      H.waitFrames(60 + (n - 1) * 17),
    }, {}),
    H.call(function() lost, wipeN = nil, 0 end),
  }
  for i = 1, 30 do
    steps[#steps + 1] = H.cond(function()
      return lost == nil and not (H.worldMode() and H.worldX() == 215
         and H.worldY() == 119 and H.worldHasControl() and H.worldAligned())
    end, {
      worldWalkFight(215, 119, 12000,
        string.format("staging a%d seg %d", n, i), nil,
        { segment = true, flee = true }),
      H.cond(function() return lost == nil end, {
        H.fieldCare({ tag = string.format("staging a%d care %d", n, i),
                      threshold = 0.9, maxFrames = 12000 }),
      }, {}),
    }, {})
  end
  -- no non-segmented closer here: a raising driveUntil inside an attempt
  -- would abort the LADDER, and 30 fought-and-cared segments that never
  -- parked is a loss for THIS timeline, not for the step
  steps[#steps + 1] = H.call(function()
    if lost == nil and H.worldMode() and H.worldX() == 215
       and H.worldY() == 119 then
      walkDone = true
      H.log(string.format("[gau] staging walk attempt %d ARRIVED f%d",
        n, H.frame))
    elseif lost == nil then
      lost = string.format("staging attempt %d never arrived (at %d,%d) " ..
        "f%d", n, H.worldX(), H.worldY(), H.frame)
      H.log("[gau] " .. lost)
    end
  end)
  return H.cond(function() return not walkDone end, steps, {})
end

local ROUTE = {
  { 216, 128, "fence north" },
  { 218, 140, "east bend" },
  { 220, 149, "south bend" },
  { 219, 153, "south bend 1" },
  { 217, 155, "south bend 2" },
  { 212, 156, "south run" },
  { 205, 153, "west bend" },
  { 207, 151, "northwest bend" },
  { 214, 149, "Crescent entry point" },
}
local routeBlob, routeDone = nil, false
local function routeCheckpoint()
  local ckReq
  return H.cond(function() return true end, {
    H.call(function() ckReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(ckReq, "post-join route checkpoint")
      routeBlob = ckReq.blob
      H.log(string.format("[gau] post-join route checkpoint captured " ..
        "(%d bytes) f%d", #routeBlob, H.frame))
    end),
  }, {})
end
local function routeAttempt(n)
  local ldReq
  local reloadSteps = {
    H.logStep(function()
      return string.format("[gau] post-join route ATTEMPT %d -- " ..
        "reloading (%s)", n, tostring(lost))
    end),
    H.call(function() ldReq = H.requestLoadState(routeBlob) end),
    H.waitFrames(2),
    H.call(function() H.checkReq(ldReq, "route attempt " .. n) end),
    H.waitFrames(60 + (n - 1) * 17),
  }

  -- The pacing MUST run after the `lost` reset below, for the same
  -- reason transitAttempt's does: worldWalkFight's terminator treats a
  -- set `lost` as done, and pacing inside the reload block would see
  -- attempt n-1's loss string still live and skip straight through.
  local jitterSteps = {}
  for j = 2, n do
    jitterSteps[#jitterSteps + 1] = worldWalkFight(217, 119, 12000,
      string.format("route a%d jitter %d out", n, j), nil, { flee = true })
    jitterSteps[#jitterSteps + 1] = worldWalkFight(219, 119, 12000,
      string.format("route a%d jitter %d back", n, j), nil, { flee = true })
  end
  local steps = {
    H.cond(function() return n > 1 end, reloadSteps, {}),
    H.call(function() lost, wipeN = nil, 0 end),
    H.cond(function() return n > 1 end, jitterSteps, {}),
  }
  for w = 1, #ROUTE do
    local tx, ty, name = ROUTE[w][1], ROUTE[w][2], ROUTE[w][3]
    for i = 1, 12 do
      steps[#steps + 1] = H.cond(function()
        return lost == nil and not (H.worldMode() and H.worldX() == tx
           and H.worldY() == ty and H.worldHasControl()
           and H.worldAligned())
      end, {
        worldWalkFight(tx, ty, 12000,
          string.format("route a%d %s seg %d", n, name, i), nil,
          { segment = true, flee = true }),
        H.cond(function() return lost == nil end, {
          H.fieldCare({ tag = string.format("route a%d %s care %d",
                          n, name, i),
                        threshold = 0.75, maxFrames = 12000 }),
        }, {}),
      }, {})
    end
    steps[#steps + 1] = H.call(function()
      if lost == nil and not (H.worldMode() and H.worldX() == tx
         and H.worldY() == ty) then
        lost = string.format("route attempt %d never reached %s (%d,%d) " ..
          "in 12 segments; at (%d,%d) f%d", n, name, tx, ty,
          H.worldX(), H.worldY(), H.frame)
        H.log("[gau] " .. lost)
      end
    end)
  end
  steps[#steps + 1] = H.call(function()
    if lost == nil then
      routeDone = true
      H.log(string.format("[gau] post-join route attempt %d ARRIVED at " ..
        "the Crescent entry point f%d [%s]", n, H.frame, partyLine()))
    end
  end)
  return H.cond(function() return not routeDone end, steps, {})
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
  H.navTo(8, 14, { maxFrames = 6000, playBattles = "tactical", arrive = function()
    return H.worldMode() end }),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end,
    3000, "on the world", 5),
  H.fieldCare({ tag = "care before the Veldt crossing", threshold = 0.95,
                maxFrames = 12000 }),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 6000, "world live before the crossing", 5),
  transitCheckpoint(),
  transitAttempt(1),
  transitAttempt(2),
  transitAttempt(3),
  transitAttempt(4),
  transitAttempt(5),
  H.call(function()
    if not transitDone then
      error("gau: the Veldt transit to Mobliz was lost -- " .. tostring(lost)
        .. " (a #74-style balance finding; do not rig)", 0)
    end
    lost, wipeN = nil, 0
  end),
  settle(157, "Mobliz"),
  H.navTo(26, 22, { maxFrames = 10000, playBattles = "tactical", arrive = function()
    return mapIdx() == 164 end }),
  H.cond(function() return mapIdx() ~= 164 end, {
    H.navTo(26, 21, { maxFrames = 3000, playBattles = "tactical", arrive = function()
      return mapIdx() == 164 end }),
  }, {}),
  settle(164, "item shop"),
  H.navTo(29, 50, { maxFrames = 6000, playBattles = "tactical" }),
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
  -- the grind's medicine, bought the verified-loop way.  Mobliz's shop 12
  -- also stocks Fenix Down at row 5 (shop_prop.dat): the route-wide revive
  -- floor, bought BEFORE the Tonic soak so a short purse shorts Tonics, not
  -- the revives.  Fenix -> 15, Tonic -> 99 are ceilings; H.buyItem
  -- purse-clamps each to the merchant's gil.
  H.call(function()
    H.assertEq(H.readByte(0x9d89 + 5), FENIX_DOWN, "shop 12 row 5 is Fenix Down")
  end),
  buyItem(FENIX_DOWN, 5, function() return 15 - invCount(FENIX_DOWN) end,
    "FENIX DOWN to 15"),
  buyItem(TONIC, 1, function() return 99 - invCount(TONIC) end, "TONIC to 99"),
  tapUntil("b", inState(0x25), "options again"),
  tapUntil("b", function() return H.hasControl() end, "shop closed", 2400),
  H.call(function()
    H.assertEq(invSlot(DRIED_MEAT) ~= nil, true, "Dried Meat in the bag")
    H.assertEq(invCount(FENIX_DOWN) >= 6, true,
      "the party leaves Mobliz with Fenix Downs -- a death is answerable now")
    H.log(string.format("[gau] leaving the shop: gil=%d tonics=%d fenix=%d",
      gil(), invCount(TONIC), invCount(FENIX_DOWN)))
  end),
  -- Prepare the feed while Mobliz is reliably menu-capable.  The Veldt
  -- staging tile can remain field-menu hostile briefly after a random battle.
  prepareFeed(),

  H.navTo(29, 53, { maxFrames = 4000, playBattles = "tactical", arrive = function()
    return mapIdx() == 157 end }),
  settle(157, "town again"),
  -- (18,41) is Mobliz's south exit ROW, and a row you leave a town by is a
  -- tile you STEP THROUGH, never one you come to rest on.  navTo to the
  -- entry point and press SOUTH through the row.
  H.navTo(18, 40, { maxFrames = 8000, playBattles = "tactical", arrive = function()
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

  walkCheckpoint(),
  walkAttempt(1),
  walkAttempt(2),
  walkAttempt(3),
  H.call(function()
    if not walkDone then
      error(string.format("gau: the walk to the Veldt staging was lost " ..
        "on all 3 staggered attempts -- last: %s", tostring(lost)), 0)
    end
  end),

  -- the grind, with real input, behind the ladder (see the header)
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
        "any of 3 attempts -- last: %s", tostring(lost)), 0)
    end
    H.assertEq(fed, true,
      "the Dried Meat was fed to GAU through the real battle Item menu " ..
      "(the old 'measured undrivable' claim is retired -- see the header)")
    H.assertEq(invCount(DRIED_MEAT), 0, "the meat left the bag with GAU")
    H.assertEq(fedSwitch(), true,
      "the Dried-Meat reaction set Gau's battle switch")
  end),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 20000, "world after the join", 5),
  H.waitFrames(120),

  -- park on Crescent Mountain's entry point (one short of the (214,148)
  -- entrance) and generate.  The route rides the ladder defined above (the
  -- SIEGE comment there carries the measurements); the Veldt's
  -- encounters are unrunable, so every one is fought by the input-driven menu
  -- fighter, one per segment, with field care between.
  routeCheckpoint(),
  routeAttempt(1),
  routeAttempt(2),
  routeAttempt(3),
  routeAttempt(4),
  routeAttempt(5),
  H.call(function()
    if not routeDone then
      error(string.format("gau: post-join walk to Crescent Mountain was " ..
        "lost on all 5 staggered attempts -- last: %s", tostring(lost)), 0)
    end
  end),
  -- The landing step itself can WIN the encounter roll ($E8 bit5 the
  -- instant it wins); require REAL control before generating, fleeing any
  -- landing-roll battle -- the post-battle reload restores this tile.
  H.driveUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 20000, {
    H.call(function()
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true })   -- flee, with real input
      else
        H.setPad({})
      end
    end),
  }, "calm, controllable entry point (flee any landing-roll battle)"),
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
  genAttempt(1),
  genAttempt(2),
  genAttempt(3),
  H.call(function()
    H.assertEq(genDone, true,
      "a reload-verified calm entry point capture within 3 attempts")
    H.emitBlob("gau_joined.mss", genBlob)
  end),
  H.logStep(function()
    return string.format("gau_joined generated at frame %d world (%d,%d) -- " ..
      "GAU fed and recruited through real menus", H.frame,
      H.worldX(), H.worldY())
  end),
})
