-- probe_thamlab_template.lua -- Thamasa fire lab, experiment half.
--
-- Hand-run instrument (probe_): boots one of the two thamlab fixtures
-- banked by probe_thamlab_bake.lua (thamlab_ambush.mss: pre-ambush,
-- fully topped off, standing near (26,36) on map 351; thamlab_flame.mss:
-- pre-FlameEater, standing at (46,54)), stands still SEED frames to shift
-- the battle-RNG phase ($021e, period 60 -- the seed a battle draws is
-- phase*4), walks onto the trigger tile ((21,22) for the ambush, (46,53)
-- for FlameEater), runs the fight under one strategy, and reports one
-- machine-readable [result] line, PASSing either way -- this file
-- measures, it does not assert.
--
-- The batch runner (thamlab_batch.sh) substitutes the @TOKEN@ defaults
-- below (sed).  Tokens:
--   LAB       flame | ambush
--   STRATEGY  control (the gen's own approach for that lab: the lib
--             newFightDriver for flame, the gen's bespoke per-turn ambush
--             plan for ambush) | taps (blind A-taps, the floor)
--   SEED      frames to stand still before engaging; NOTE $021e has
--             period 60, so only SEED mod 60 matters
--   HEALPCT/BOOST/ITEMS/CURE  knobs on the flame control driver
--
-- Win/loss detection is the gen's own: FlameEater sets switch $0090 on the
-- win tail; the ambush win lands back on map 351 with control and STRAGO
-- still in party 1; a loss is the event GameOver, read-fired into
-- H.gameOverFired (allowGameOver).

local H = dofile("tools/tests/lib/ot6.lua")

local LAB      = "@LAB@"
local STRATEGY = "@STRATEGY@"
local FIXTURE  = "@FIXTURE@"
local SEED     = tonumber("@SEED@")    or 0
local HEALPCT  = tonumber("@HEALPCT@") or 60
local BOOST    = tonumber("@BOOST@")   or 1
local ITEMS    = tonumber("@ITEMS@")   or 1
local CURE     = tonumber("@CURE@")    or 1
if LAB:find("@") then LAB = "flame" end
if STRATEGY:find("@") then STRATEGY = "control" end
if FIXTURE:find("@") then FIXTURE = "thamlab_" .. LAB end

local TERRA, LOCKE, STRAGO = 0, 1, 7
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local ICE_SPELL = 0x01
local CONFIRM_BATTLE_GONE = 90
local MAXBATT = 150000                  -- fight frames before "fight-timeout"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function seq(steps) return H.cond(function() return true end, steps) end

-- the gen's own walk profiles for these corridors
local FLEE_WALK = { playBattles = "flee", healer = TERRA, bank = 3,
                     items = true, maxFrames = 20000, healPercent = 85,
                     magic = { [TERRA] = { spell = ICE_SPELL, boost = false } } }
local FLAMEEATER_WALK = { playBattles = "tactical", healer = TERRA, bank = 3,
  items = true, maxFrames = 100000, healPercent = 60 }

local function creepXY(tx, ty, step)
  step = step or 14
  local function pt()
    local px, py = H.fieldX(), H.fieldY()
    local dx, dy = tx - px, ty - py
    local dist = math.abs(dx) + math.abs(dy)
    if dist <= step or dist == 0 then return tx, ty end
    return px + math.floor(dx * step / dist), py + math.floor(dy * step / dist)
  end
  return function() return (pt()) end,
         function() local _, y = pt(); return y end
end
local function creepNav(tx, ty, opts, step)
  local fx, fy = creepXY(tx, ty, step)
  return H.navTo(fx, fy, opts)
end

local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true }); return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

-- ------------------------------------------------------------------------
-- The gen's bespoke per-turn ambush battle plan, verbatim (the "control"
-- strategy for lab=ambush).
local MENU_A, ACTOR_A, MSTATE_A = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL_A, CMDROW_A = 0x202E, 0x890F
local BCHID_A, BCHP_A, BCMAXHP_A = 0x3ED8, 0x3BF4, 0x3C1C
local BP_A = 0x3E9C
local ST_CMD_A, ST_TGT_A, ST_ITEM_A, ST_THIEF_A = 0x05, 0x38, 0x0A, 0x30
local KCOL_A, KROW_A = 0x8963, 0x8967
local ST_LORE_OPEN_A, ST_LORE_A = 0x19, 0x1B
local LROW_A = 0x8927
local TBL_306A_A = 0x306A
local CMD_FIGHT_A, CMD_ITEM_A, CMD_STEAL_A, CMD_LORE_A = 0x00, 0x01, 0x05, 0x0C
local ITEMSCR_A, ITEMROW_A, BATTINV_A = 0x8947, 0x894F, 0x2686
local AQUA_RAKE_LORE_ID = 3
local CMD_MAGIC_A, ST_MAGIC_A = 0x02, 0x0E
local MLISTPTR_A = 0x302C
local MSCROLL_A, MCOL_A, MROW_A = 0x8913, 0x8917, 0x891B
local CURMP_A = 0x3C08
local function spellCellA(actor, id, strict)
  local base = H.readWord(MLISTPTR_A + actor * 2)
  if base < 0x2000 or base > 0x2600 then return nil end
  for cell = 0, 53 do
    local a = base + (cell + 1) * 4
    if H.readByte(a) == id then
      local cost = H.readByte(a + 3)
      if H.readWord(CURMP_A + actor * 2) < cost then return nil end
      if strict and (H.readByte(a + 1) & 0x80) ~= 0 then return nil end
      return cell, cost
    end
  end
  return nil
end
local function monHpA(i) return H.readWord(0x3BFC + i * 2) end
local function monShieldsA(i) return H.readByte(0x3E40 + i * 2) end
local function monPresentA(i) return H.readByte(0x3AA8 + i * 2) % 2 == 1 end
local function cmdRowA(actor, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL_A + actor * 12 + r * 3) == cmd then return r end
  end
  return nil
end
local function bagIdxOfA(ids)
  for i = 0, 251 do
    local id = H.readByte(BATTINV_A + i * 5)
    for _, w in ipairs(ids) do
      if id == w and H.readByte(BATTINV_A + i * 5 + 3) > 0 then return i end
    end
  end
  return nil
end
-- battle_lore.lua's own tested fact: $306A+id reads id+$8B iff that lore
-- id is currently offered by Ot6LoreMask's live walk; otherwise whatever
-- InitBattle's own clear left there. Comparing against the exact expected
-- value (rather than measuring a separate "fill" byte first) sidesteps
-- needing that extra live-measurement step.
local function loreOfferedA(id) return H.readByte(TBL_306A_A + id) == id + 0x8B end
local function loreRowForA(targetId)
  local row = 0
  for id = 0, targetId - 1 do
    if loreOfferedA(id) then row = row + 1 end
  end
  return row
end
local ambushCharTC = H.targetCursor({ mask = 0x7B7D, dirs = { "down", "up", "left", "right" } })

local function newAmbushPlan(tag)
  local F = {}
  local phase, mf = 0, 0
  local turnActor, turnPlan = nil, nil
  local stepIdx = 0
  local aqCasts, filchCasts, fightBursts, iceCasts = 0, 0, 0, 0
  local openerLogged = false
  local function partyCounts()
    local balloonsAlive = 0
    for s = 0, 5 do if monPresentA(s) and monHpA(s) > 0 then balloonsAlive = balloonsAlive + 1 end end
    local stragoSlot, downSlots, anyAlive = nil, {}, false
    for e = 0, 3 do
      if H.readWord(BCMAXHP_A + e * 2) > 0 then
        local cid = H.readByte(BCHID_A + e * 2)
        if cid == STRAGO then stragoSlot = e end
        if H.readWord(BCHP_A + e * 2) > 0 then anyAlive = true
        else downSlots[#downSlots + 1] = e end
      end
    end
    return balloonsAlive, stragoSlot, downSlots, anyAlive
  end
  local function anyShielded()
    for s = 0, 5 do
      if monPresentA(s) and monHpA(s) > 0 and monShieldsA(s) > 0 then return true end
    end
    return false
  end
  -- built once per fresh ST_CMD (turnPlan == nil or a new actor's turn)
  local function decideTurn(actor)
    if not openerLogged then
      openerLogged = true
      local hp, mx = H.readWord(BCHP_A + actor * 2), H.readWord(BCMAXHP_A + actor * 2)
      H.log(string.format(
        "[%s] opener check f%d: first actor to get a turn is slot %d " ..
        "(char $%02X) at %d/%d hp -- the opener's own damage on whoever it " ..
        "caught is whatever's MISSING from THEIR max, logged separately " ..
        "per party member below", tag, H.frame, actor,
        H.readByte(BCHID_A + actor * 2), hp, mx))
      for e = 0, 3 do
        if H.readWord(BCMAXHP_A + e * 2) > 0 then
          H.log(string.format(
            "[%s] opener dbg: slot %d char $%02X hp=%d/%d (missing=%d)",
            tag, e, H.readByte(BCHID_A + e * 2), H.readWord(BCHP_A + e * 2),
            H.readWord(BCMAXHP_A + e * 2),
            H.readWord(BCMAXHP_A + e * 2) - H.readWord(BCHP_A + e * 2)))
        end
      end
    end
    local charId = H.readByte(BCHID_A + actor * 2)
    local hp, mx = H.readWord(BCHP_A + actor * 2), H.readWord(BCMAXHP_A + actor * 2)
    local balloonsAlive, stragoSlot, downSlots = partyCounts()
    -- 1. self-heal, always allowed (the fence lesson)
    if mx > 0 and hp > 0 and hp < mx * 0.40 then
      local idx = bagIdxOfA({ TONIC, POTION })
      if idx then return { kind = "item", ids = { TONIC, POTION }, target = actor } end
    end
    -- 2. revive window: at most one Balloon left, revive STRAGO first
    if balloonsAlive <= 1 and #downSlots > 0 then
      local idx = bagIdxOfA({ FENIX_DOWN })
      if idx then
        local tgt = downSlots[1]
        if stragoSlot then
          for _, s in ipairs(downSlots) do if s == stragoSlot then tgt = s end end
        end
        return { kind = "item", ids = { FENIX_DOWN }, target = tgt }
      end
    end
    -- 3. offense -- lead with AoE weakness magic: STRAGO's Aqua Rake is
    -- free every turn regardless; TERRA and
    -- LOCKE now both carry an Ice-granting esper (SHIVA/MADUIN), so they
    -- lead with a boosted, multi-target Ice cast (Balloons are weak to
    -- ice|water, thamasa-route.md) whenever they can pay for it, falling
    -- back to the pre-PREP break-and-burst kit (Filch/boosted Fight) only
    -- when the cast isn't available (esper unequipped, out of MP, or the
    -- greyed bit refuses it).
    if charId == STRAGO then
      return { kind = "lore", loreId = AQUA_RAKE_LORE_ID }
    end
    if charId == TERRA or charId == LOCKE then
      if spellCellA(actor, ICE_SPELL, true) then
        return { kind = "magic", spell = ICE_SPELL }
      end
    end
    if charId == LOCKE then
      if anyShielded() then return { kind = "filch" } end
      return { kind = "fight", boost = true }
    end
    return { kind = "fight", boost = true }
  end
  -- per-frame button for the CURRENT plan/state
  local function buttonFor(actor, st)
    local plan = turnPlan
    if plan.kind == "item" then
      if st == ST_CMD_A then
        local want = cmdRowA(actor, CMD_ITEM_A)
        if want == nil then return "a" end
        local cur = H.readByte(CMDROW_A + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_ITEM_A then
        local want = bagIdxOfA(plan.ids)
        if want == nil then return "b" end
        local cur = H.readByte(ITEMSCR_A + actor) + H.readByte(ITEMROW_A + actor)
        if cur < want then return "down" end
        if cur > want then return "up" end
        return "a"
      elseif st == ST_TGT_A then
        plan.tgtSpin = (plan.tgtSpin or 0) + 1
        if plan.tgtSpin > 240 then return "a" end
        ambushCharTC.observe()
        return ambushCharTC.steer(plan.target, mf)
      end
      return "b"
    end
    if plan.kind == "filch" then
      if st == ST_CMD_A then
        local want = cmdRowA(actor, CMD_STEAL_A)
        if want == nil then return "a" end
        local cur = H.readByte(CMDROW_A + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_THIEF_A then
        local cur = H.readByte(KROW_A + actor)
        if H.readByte(KCOL_A + actor) ~= 0 then return "left" end
        if cur < 1 then return "down" end
        if cur > 1 then return "up" end
        return "a"
      elseif st == ST_TGT_A then
        return "a"                       -- default enemy cursor, no steer
      end
      return "b"
    end
    if plan.kind == "lore" then
      if st == ST_CMD_A then
        local want = cmdRowA(actor, CMD_LORE_A)
        if want == nil then return "a" end
        local cur = H.readByte(CMDROW_A + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_LORE_OPEN_A then
        return nil                       -- transitional DMA fill, just wait
      elseif st == ST_LORE_A then
        local want = loreRowForA(plan.loreId)
        local cur = H.readByte(LROW_A + actor)
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_TGT_A then
        return "a"                       -- multi-target, no steer
      end
      return "b"
    end
    if plan.kind == "magic" then
      -- Same boost-bank shape the fight fallback uses below (spend BP,
      -- capped at 3, only once at least 2 is banked) -- OT6 folds a boosted
      -- base cast to its next tier via Ot6FoldTbl (Ice -> Ice2 -> Ice3), so
      -- this is how the plan gets the bigger AoE hit rather than the base
      -- 4 MP tier every single cast.
      if st == ST_CMD_A then
        if not plan.boosted then
          local bp = H.readByte(BP_A + actor * 2)
          local want = (bp >= 2) and math.min(bp, 3) or 0
          plan.boostLeft = plan.boostLeft or want
          if plan.boostLeft > 0 then
            plan.boostLeft = plan.boostLeft - 1
            return "r"
          end
          plan.boosted = true
        end
        local want = cmdRowA(actor, CMD_MAGIC_A)
        if want == nil then return "b" end
        local cur = H.readByte(CMDROW_A + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_MAGIC_A then
        -- re-read the cell every tick (not just at plan time): the list is
        -- rebuilt when the window opens, matching M.newFightDriver's own
        -- button()'s "re-read, don't trust the plan-time cell" note.
        local cell = spellCellA(actor, plan.spell, false)
        if cell == nil then return "b" end
        local wr, wc = cell // 2, cell % 2
        local ar = H.readByte(MSCROLL_A + actor) + H.readByte(MROW_A + actor)
        local col = H.readByte(MCOL_A + actor)
        if ar < wr then return "down" end
        if ar > wr then return "up" end
        if col < wc then return "right" end
        if col > wc then return "left" end
        return "a"
      elseif st == ST_TGT_A then
        return "a"                       -- multi-target, no steer
      end
      return "b"
    end
    -- fight (default/fallback)
    if st == ST_CMD_A then
      if plan.boost and not plan.boosted then
        local bp = H.readByte(BP_A + actor * 2)
        local want = (bp >= 2) and math.min(bp, 3) or 0
        plan.boostLeft = plan.boostLeft or want
        if plan.boostLeft > 0 then
          plan.boostLeft = plan.boostLeft - 1
          return "r"
        end
        plan.boosted = true
      end
      local want = cmdRowA(actor, CMD_FIGHT_A)
      local cur = H.readByte(CMDROW_A + actor) & 3
      if want == nil then return "a" end
      if cur == want then return "a" end
      return cur < want and "down" or "up"
    elseif st == ST_TGT_A then
      return "a"                         -- default enemy cursor, no steer
    end
    return "b"
  end
  function F.frame()
    phase = (phase + 1) % 8
    if H.readByte(MENU_A) == 0 then
      turnActor, turnPlan = nil, nil
      H.setPad(phase < 4 and { "a" } or {})
      return
    end
    mf = mf + 1
    local actor = H.readByte(ACTOR_A) & 3
    local st = H.readByte(MSTATE_A)
    if st == 0x01 then H.setPad({}); return end   -- ST_TRANS
    if (turnPlan == nil or turnActor ~= actor) and st ~= ST_CMD_A then
      -- a fresh actor turn hasn't reached the command list yet (a
      -- transitional state); hold still rather than build a plan off a
      -- read that might still be settling, matching H.newFightDriver's
      -- own "only build a plan at ST_CMD" convention.
      H.setPad({})
      return
    end
    if turnPlan == nil or turnActor ~= actor then
      turnActor = actor
      turnPlan = decideTurn(actor)
      H.log(string.format("[%s] f%d slot=%d char=$%02X plan=%s%s", tag,
        H.frame, actor, H.readByte(BCHID_A + actor * 2), turnPlan.kind,
        turnPlan.kind == "item" and (" tgt=" .. turnPlan.target) or ""))
    end
    -- LORE-STALL watchdog (thamlab addition, not in the gen): the gen's
    -- lore-row steering has stalled here before (cursor held on a wrong
    -- row, ~61k frames of refused confirms).  When a lore plan makes no
    -- progress for 600 frames, dump the evidence ONCE -- the offered-
    -- signature table $306A, lore count $3A87, the $1E27 loadout slots,
    -- the learned-lore bits $1D29-2B, the live cursor row, and the model's
    -- computed want row -- then abandon the lore plan for a plain Fight so
    -- the bake/measurement terminates.
    if turnPlan.kind == "lore" and st == ST_LORE_A then
      turnPlan.loreStall = (turnPlan.loreStall or 0) + 1
      if turnPlan.loreStall == 600 then
        local t306a = {}
        for i = 0, 23 do
          t306a[#t306a + 1] = string.format("%02X", H.readByte(TBL_306A_A + i))
        end
        local t1e27 = {}
        for i = 0, 4 do
          t1e27[#t1e27 + 1] = string.format("%02X", H.readByte(0x1E27 + i))
        end
        H.log(string.format(
          "[%s] LORE-STALL dump f%d: actor=%d loreId=%d 3A87(loreCnt)=$%02X " ..
          "306A+0..23=[%s] 1E27+0..4=[%s] 1D29..2B=%02X %02X %02X " ..
          "cursor(8927+a)=%d wantRow(compacted model)=%d offered(loreId)=%s",
          tag, H.frame, actor, turnPlan.loreId, H.readByte(0x3A87),
          table.concat(t306a, " "), table.concat(t1e27, " "),
          H.readByte(0x1D29), H.readByte(0x1D2A), H.readByte(0x1D2B),
          H.readByte(LROW_A + actor), loreRowForA(turnPlan.loreId),
          tostring(loreOfferedA(turnPlan.loreId))))
        H.log(string.format(
          "[%s] LORE-STALL: abandoning the lore plan for a plain boosted " ..
          "Fight so this run terminates", tag))
        turnPlan = { kind = "fight", boost = true }
      end
    end
    local slow = (st == ST_ITEM_A)
    local period = slow and 30 or 8
    local on = slow and 6 or 4
    if mf % period >= on then H.setPad({}); return end
    local btn = buttonFor(actor, st)
    -- count landed actions on the ST_TGT->confirm edge, logged once per
    -- kind so the report has real cadence numbers
    if st == ST_TGT_A and btn == "a" then
      if turnPlan.kind == "lore" and not turnPlan.counted then
        turnPlan.counted = true; aqCasts = aqCasts + 1
        H.log(string.format("[%s] Aqua Rake cast #%d confirmed f%d", tag, aqCasts, H.frame))
      elseif turnPlan.kind == "filch" and not turnPlan.counted then
        turnPlan.counted = true; filchCasts = filchCasts + 1
        H.log(string.format("[%s] Filch #%d confirmed f%d", tag, filchCasts, H.frame))
      elseif turnPlan.kind == "fight" and turnPlan.boost and not turnPlan.counted then
        turnPlan.counted = true; fightBursts = fightBursts + 1
        H.log(string.format("[%s] boosted burst Fight #%d confirmed f%d", tag, fightBursts, H.frame))
      elseif turnPlan.kind == "magic" and not turnPlan.counted then
        turnPlan.counted = true; iceCasts = iceCasts + 1
        H.log(string.format("[%s] Ice cast #%d confirmed f%d", tag, iceCasts, H.frame))
      end
    end
    H.setPad(btn and { [btn] = true } or {})
  end
  function F.idle()
    turnActor, turnPlan = nil, nil
    H.log(string.format(
      "[%s] tally: Aqua Rake x%d, Ice x%d, Filch x%d, boosted burst x%d",
      tag, aqCasts, iceCasts, filchCasts, fightBursts))
  end
  return F
end

-- ------------------------------------------------------------------------

local function newTapsDriver()
  local ph = 0
  local F = {}
  function F.frame()
    ph = (ph + 1) % 8
    H.setPad(ph < 4 and { "a" } or {})
  end
  function F.idle() end
  return F
end

local function newStrategyDriver()
  if STRATEGY == "taps" then return newTapsDriver() end
  if STRATEGY == "control" then
    if LAB == "ambush" then return newAmbushPlan("thamlab-ambush-control") end
    return H.newFightDriver("thamlab-flame-control", {
      tactical = true, boost = BOOST == 1, bank = 3, items = ITEMS == 1,
      cure = CURE == 1, healer = TERRA, healPercent = HEALPCT })
  end
  error("unknown STRATEGY " .. STRATEGY, 0)
end

local function allStanding()
  for _, c in ipairs(H.partyMembers()) do
    local hp, mx = H.charHp(c), H.charMaxHp(c)
    if not (hp > 0 and (H.charStatus1(c) & 0xC6) == 0 and hp > (mx >> 3)) then
      return false
    end
  end
  return true
end

-- ------------------------------------------------------------------------
local res = { seeds = {}, deaths = 0, bframes = 0 }

-- The lib's own GameOver canary NEVER arms in a composed run: ot6.lua
-- registers it via pcall(M.sym, "GameOver"), a form compose.py's
-- sym("...") literal scanner does not see, so OT6_SYMS lacks the names
-- and the pcall fails silently (measured 2026-08-27: a party wipe read
-- gameOverFired==0 and the win-tail's A-taps auto-Continued the save).
-- So the lab arms its own watches, with literals compose.py collects:
-- a READ watch on the GameOver event script and an EXEC watch on the
-- title-screen entry, both feeding H.gameOverFired.
local function armLossWatch()
  local ok, addr = pcall(function() return H.sym("GameOver") end)
  if ok then
    emu.addMemoryCallback(function()
      H.gameOverFired = H.gameOverFired + 1
    end, emu.callbackType.read, addr, addr)
  end
  local ok2, addr2 = pcall(function() return H.sym("TitleScreen") end)
  if ok2 then
    emu.addMemoryCallback(function()
      H.gameOverFired = H.gameOverFired + 1
    end, emu.callbackType.exec, addr2, addr2)
  end
  H.log(string.format("[lab] loss watch armed: GameOver(read)=%s TitleScreen(exec)=%s",
    tostring(ok), tostring(ok2)))
end

-- record every $be the seed store draws (random encounters en route seed it
-- too; the LAST one before the outcome is the main battle's seed)
local function armSeedWatch()
  local addr = H.seedStoreAddr()
  emu.addMemoryCallback(function()
    local seed = emu.getState()["cpu.a"] & 0xff
    res.seeds[#res.seeds + 1] = seed
    H.log(string.format("[lab] battle seeded $be=$%02X from $021e=%d at f%d",
      seed, H.readByte(0x021E), H.frame))
  end, emu.callbackType.exec, addr, addr)
end

-- per-frame death tracking off the battle slots (falling edge hp>0 -> 0)
local wasAlive = {}
local function trackDeaths()
  for e = 0, 3 do
    if H.readWord(0x3C1C + e * 2) > 0 then
      local alive = H.readWord(0x3BF4 + e * 2) > 0
      if wasAlive[e] and not alive then
        res.deaths = res.deaths + 1
        H.log(string.format("[lab] slot %d (char $%02X) DOWN at f%d (death #%d)",
          e, H.readByte(0x3ED8 + e * 2), H.frame, res.deaths))
      end
      wasAlive[e] = alive
    else
      wasAlive[e] = nil
    end
  end
end

local F = nil
local lost = nil

local function mainFight(what)
  local notBattle, fightF = 0, 0
  return H.driveUntil(function()
    if H.gameOverFired > 0 then lost = "gameover"; return true end
    if fightF >= MAXBATT then lost = "fight-timeout"; return true end
    if H.battleLoadStarted() or H.battleActive() then
      notBattle = 0
    else
      notBattle = notBattle + 1
    end
    return notBattle >= CONFIRM_BATTLE_GONE
  end, MAXBATT + 20000, {
    H.call(function()
      if H.gameOverFired > 0 then H.setPad({}); return end
      if H.battleLoadStarted() or H.battleActive() then
        fightF = fightF + 1
        res.bframes = res.bframes + 1
        trackDeaths()
      end
      F.frame()
    end),
  }, what)
end

local function winTail(pred, what)
  local giveUp = 0
  return H.driveUntil(function()
    if H.gameOverFired > 0 then lost = lost or "gameover"; return true end
    giveUp = giveUp + 1
    return pred() or giveUp >= 11800
  end, 13000, {
    H.call(function()
      if H.gameOverFired > 0 then H.setPad({}); return end
      local ph = (giveUp % 8)
      if not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
      else H.setPad({}) end
    end),
  }, what)
end

H.run({ maxFrames = 400000, allowGameOver = true }, {
  -- compose.py embeds savestates by scanning loadState string LITERALS,
  -- so both fixtures are spelled out and FIXTURE picks at runtime.
  (function()
    local fixtures = {
      thamlab_ambush = H.loadState("build/states/thamlab_ambush.mss.lua"),
      thamlab_flame  = H.loadState("build/states/thamlab_flame.mss.lua"),
    }
    return assert(fixtures[FIXTURE], "unknown FIXTURE " .. FIXTURE)
  end)(),
  H.waitFrames(90),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
       and not H.dialogWaiting() and not H.battleLoadStarted()
  end, 2400, "lab fixture settled", 5),
  H.call(function()
    H.assertEq(map(), 351, "lab fixture boots in the burning house (map 351)")
    armSeedWatch()
    armLossWatch()
    res.t0 = H.frame
    res.fenix0  = H.invCountOf(FENIX_DOWN)
    res.tonic0  = H.invCountOf(TONIC)
    res.potion0 = H.invCountOf(POTION)
    H.log(string.format(
      "[lab] set-off lab=%s strategy=%s seed=%d pos=(%d,%d) phase=%d " ..
      "hp T=%d/%d L=%d/%d S=%d/%d mp=%d,%d,%d bag f/t/p=%d/%d/%d",
      LAB, STRATEGY, SEED, H.fieldX(), H.fieldY(), H.readByte(0x021E),
      H.charHp(TERRA), H.charMaxHp(TERRA), H.charHp(LOCKE), H.charMaxHp(LOCKE),
      H.charHp(STRAGO), H.charMaxHp(STRAGO),
      H.charMp(TERRA), H.charMp(LOCKE), H.charMp(STRAGO),
      res.fenix0, res.tonic0, res.potion0))
    F = newStrategyDriver()
  end),

  -- the seed knob: stand still SEED frames ($021e ticks 1/frame, period 60)
  H.waitFrames(SEED),
  H.call(function()
    H.log(string.format("[lab] stood %d frames; phase now %d at f%d",
      SEED, H.readByte(0x021E), H.frame))
  end),

  -- walk onto the trigger tile, the gen's own approach steps
  LAB == "ambush" and seq({
    creepNav(21, 23, FLEE_WALK),
    pressWalk("up", function()
      return H.battleLoadStarted() or not H.hasControl()
    end, 1800, "step onto (21,22) -> battle 45"),
    H.waitUntil(function() return H.battleActive() end, 6000,
      "ambush battle up", 10),
    H.waitFrames(90),
  }) or seq({
    creepNav(46, 52, FLAMEEATER_WALK),
    pressWalk("down", function()
      return sw(0x0090) == 1 or H.battleLoadStarted() or H.battleActive()
    end, 8000, "walk onto (46,53) until battle 79 starts"),
  }),

  mainFight("thamlab " .. LAB .. " fight (" .. STRATEGY .. ")"),
  H.call(function()
    if F.idle then F.idle() end
    -- snapshot resources NOW: the field bag/roster just synced from the
    -- battle module; a loss that reaches the title screen would revert
    -- them (auto-Continue time travel) before the result read.
    res.fenix1  = H.invCountOf(FENIX_DOWN)
    res.tonic1  = H.invCountOf(TONIC)
    res.potion1 = H.invCountOf(POTION)
    res.mpT, res.mpL, res.mpS =
      H.charMp(TERRA), H.charMp(LOCKE), H.charMp(STRAGO)
    res.standing1 = allStanding()
    H.log(string.format("[lab] battle module gone at f%d (lost=%s)",
      H.frame, tostring(lost)))
  end),

  -- the win tail, per lab
  LAB == "ambush" and winTail(function()
    return map() == 351 and H.hasControl() and H.tileAligned()
  end, "ambush win-tail settle") or winTail(function()
    return sw(0x0090) == 1
  end, "the win tail flips $0090"),

  H.call(function()
    H.setPad({})
    local won
    if LAB == "ambush" then
      won = H.gameOverFired == 0 and lost == nil and map() == 351
        and partyOf(STRAGO) ~= 0
    else
      won = H.gameOverFired == 0 and lost == nil and sw(0x0090) == 1
    end
    local reason
    if won then reason = "win"
    elseif lost then reason = lost
    else reason = "verify-failed" end
    local be = #res.seeds > 0 and string.format("$%02X", res.seeds[#res.seeds])
      or "none"
    H.log(string.format(
      "[result] lab=%s strategy=%s seed=%d won=%d frames=%d bframes=%d " ..
      "deaths=%d fenix=%d tonic=%d potion=%d mp=%d,%d,%d standing=%d " ..
      "attempts=1 be=%s nseeds=%d reason=%s",
      LAB, STRATEGY, SEED, won and 1 or 0, H.frame - res.t0, res.bframes,
      res.deaths,
      res.fenix0 - (res.fenix1 or res.fenix0),
      res.tonic0 - (res.tonic1 or res.tonic0),
      res.potion0 - (res.potion1 or res.potion0),
      res.mpT or -1, res.mpL or -1, res.mpS or -1,
      res.standing1 and 1 or 0, be, #res.seeds, reason))
  end),
})
