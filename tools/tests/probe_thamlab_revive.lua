-- probe_thamlab_revive.lua -- Thamasa fire lab, revive-targeting agent.
--
-- Chases the ambush agent's measured whiff loop: on bad draws (seed 21)
-- the item plan's ST_TGT steer (H.targetCursor over $7B7D) never settles
-- on the dead slot, times out at 240 spins, and the blind A burns a Fenix
-- Down on the wrong target -- 8 episodes x ~1740 frames in
-- build/thamlab/ambush_fix_s21.log (10 Fenix for 2 deaths).
--
-- Base copied from probe_thamlab_ambush_fix.lua (its lore fix kept), plus
-- ST_TGT instrumentation and a revive-targeting fix under test.
--
-- Strategies (@STRATEGY@):
--   ambush-revive      ambush-fix behavior verbatim + [tgtopen]/[tgtdump]/
--                      [tgtconfirm] instrumentation of item target-selects
--   ambush-revive-fix  same instrumentation, steering replaced by the
--                      measured fix (see FIX note at buttonFor)
--
-- Everything else (fixture boot, seed knob, walk-in, watches, [result]
-- line) matches probe_thamlab_template.lua verbatim so numbers compare.

local H = dofile("tools/tests/lib/ot6.lua")

local LAB      = "ambush"
local STRATEGY = "@STRATEGY@"
local SEED     = tonumber("@SEED@") or 0
if STRATEGY:find("@") then STRATEGY = "ambush-revive" end
local REVIVE_FIX = (STRATEGY == "ambush-revive-fix")
local MAP_MODE   = (STRATEGY == "ambush-revive-map")

local TERRA, LOCKE, STRAGO = 0, 1, 7
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local ICE_SPELL = 0x01
local CONFIRM_BATTLE_GONE = 90
local MAXBATT = 150000                  -- fight frames before "fight-timeout"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function seq(steps) return H.cond(function() return true end, steps) end

-- the gen's own walk profile for these corridors
local FLEE_WALK = { playBattles = "flee", healer = TERRA, bank = 3,
                     items = true, maxFrames = 20000, healPercent = 85,
                     magic = { [TERRA] = { spell = ICE_SPELL, boost = false } } }

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
-- The gen's bespoke per-turn ambush battle plan, with the lore-row fix and
-- the variant knobs described in the header.
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
local function loreOfferedA(id) return H.readByte(TBL_306A_A + id) == id + 0x8B end
-- THE FIX under test.  The gen's loreRowForA compacts the list (row =
-- count of offered ids below targetId); measured-wrong -- the battle lore
-- window is positional by lore id, one row per id, empty rows included.
local function loreRowForA(targetId) return targetId end
local ambushCharTC = H.targetCursor({ mask = 0x7B7D, dirs = { "down", "up", "left", "right" } })

-- ---------------------------------------- ST_TGT instrumentation (items) --
-- Ground truth from ff6/src/btlgfx/btlgfx_main.asm (UpdateMenuState_38 and
-- TargetSelect*): the char cursor mask $7B7D is only ever stored as
-- (groupmask & $201d & $61AC & $61AD & $6193 & rowbit); $7ACE is the
-- target group (odd = characters), $7ACF the cursor row in that group,
-- $7A86.. the row -> target-number map; A-confirm queues the live
-- $7B7D/$7B7E verbatim ($2bb1,y / $2bb2,y).  Dump all of it.
local tgtDumpBudget = 900
local function tgtLog(fmt, ...)
  if tgtDumpBudget > 0 then
    tgtDumpBudget = tgtDumpBudget - 1
    H.log(string.format(fmt, ...))
  end
end
local function tgtSample(tag, actor, plan, mf)
  local d7d, d7e, d7f = H.readByte(0x7B7D), H.readByte(0x7B7E), H.readByte(0x7B7F)
  local ace, acf = H.readByte(0x7ACE), H.readByte(0x7ACF)
  if not plan.tgtOpened then
    plan.tgtOpened = true
    local m = {}
    for i = 0, 23 do m[#m + 1] = string.format("%02X", H.readByte(0x7A86 + i)) end
    tgtLog("[tgtopen] f%d actor=%d tgt=%s 201d=%02X 61ac=%02X 61ad=%02X " ..
      "6193=%02X 7a84=%02X 7a85=%02X ace=%02X acf=%02X btype=%02X " ..
      "grp=%02X,%02X,%02X,%02X 7a86..=%s hp=%d,%d,%d,%d",
      H.frame, actor, tostring(plan.target),
      H.readByte(0x201D), H.readByte(0x61AC), H.readByte(0x61AD),
      H.readByte(0x6193), H.readByte(0x7A84), H.readByte(0x7A85),
      ace, acf, H.readByte(0x201F),
      H.readByte(0x7B79), H.readByte(0x7B7A),
      H.readByte(0x7B7B), H.readByte(0x7B7C), table.concat(m, ","),
      H.readWord(BCHP_A), H.readWord(BCHP_A + 2),
      H.readWord(BCHP_A + 4), H.readWord(BCHP_A + 6))
  end
  local sig = string.format("%02X.%02X.%02X.%02X.%02X", d7d, d7e, d7f, ace, acf)
  if sig ~= plan.tgtSig then
    plan.tgtSig = sig
    tgtLog("[tgtdump] f%d mf=%d actor=%d tgt=%s spin=%d 7b7d=%02X 7b7e=%02X " ..
      "7b7f=%02X ace=%02X acf=%02X latch=%s age=%d press=%d lastbtn=%s",
      H.frame, mf, actor, tostring(plan.target), plan.tgtSpin or 0,
      d7d, d7e, d7f, ace, acf,
      tostring(ambushCharTC.mask), ambushCharTC.age, ambushCharTC.press,
      tostring(plan.lastBtn))
  end
end

local function newAmbushPlan(tag, opts)
  opts = opts or {}
  local tlKind   = opts.tlKind   or "magic"   -- "magic" | "fight" for TERRA/LOCKE
  local iceBoost = opts.iceBoost ~= false     -- bank BP into the Ice cast?
  local F = {}
  local phase, mf = 0, 0
  local turnActor, turnPlan = nil, nil
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
  local function decideTurn(actor)
    if not openerLogged then
      openerLogged = true
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
    -- 3. offense
    if charId == STRAGO then
      return { kind = "lore", loreId = AQUA_RAKE_LORE_ID }
    end
    if (charId == TERRA or charId == LOCKE) and tlKind == "magic" then
      if spellCellA(actor, ICE_SPELL, true) then
        return { kind = "magic", spell = ICE_SPELL, boost = iceBoost }
      end
    end
    if charId == LOCKE and tlKind ~= "magic" then
      if anyShielded() then return { kind = "filch" } end
      return { kind = "fight", boost = true }
    end
    return { kind = "fight", boost = true }
  end
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
        local btn
        if MAP_MODE then
          -- cursor-graph mapping: spaced single edges (2 frames on, 22
          -- off -- no auto-repeat can fire), fixed sequence, sampler logs
          -- the state after each.  Ends with blind A so the run goes on.
          local SEQ = { "down", "down", "down", "down",
                        "up", "up", "up", "up",
                        "left", "left", "right", "right" }
          plan.mapMf = (plan.mapMf or -1) + 1
          local step, ph = plan.mapMf // 24, plan.mapMf % 24
          if step < #SEQ then
            btn = (ph < 2) and SEQ[step + 1] or nil
            if ph == 0 then
              tgtLog("[tgtpress] f%d actor=%d step=%d btn=%s", H.frame,
                actor, step, SEQ[step + 1])
            end
          else
            btn = (ph < 2) and "a" or nil
          end
          plan.lastBtn = btn or plan.lastBtn
          return btn
        end
        if REVIVE_FIX then
          -- THE FIX (all measured, ambush_revive_map_s21.log):
          --  * plan-local state: nothing carries over between episodes
          --    (H.targetCursor's press counter never reset, so each episode
          --    opened at an arbitrary rotation phase);
          --  * never emit a direction before a deliberate press (steer()'s
          --    press-0 frame emits dirs[#dirs] = "right", which exiles the
          --    cursor from the char column into the right monster group);
          --  * up/down only -- left/right switch target GROUPS (char column
          --    <-> monster groups) in this pincer formation, they do not
          --    walk char slots; if we somehow land on a monster group,
          --    left (from grp 2) / right (from grp 0) returns to char slot 0;
          --  * single 2-frame taps with a long dwell -- battle directions
          --    bypass edge filtering (UpdateCtrl ANDs edges with #$f0f0,
          --    dpad bits fall outside) and run on the auto-repeat machine,
          --    so held/fast presses fire extra moves or none;
          --  * closed loop: reread $7B7D (latched across the blink) and
          --    press A only once it equals 1 << target.
          plan.fixMf = (plan.fixMf or -1) + 1
          local want = 1 << plan.target
          local d7d = H.readByte(0x7B7D)
          if d7d ~= 0 then plan.fixSeen = d7d end
          local ace = H.readByte(0x7ACE)
          if plan.tgtSpin > 600 then btn = "a"      -- safety net only
          elseif plan.fixSeen == want then btn = "a"
          else
            local ph = plan.fixMf % 16
            if ph >= 2 then btn = nil
            elseif ace % 2 == 0 then btn = (ace == 0) and "right" or "left"
            else btn = "down" end
          end
        else
          if plan.tgtSpin > 240 then
            btn = "a"
          else
            ambushCharTC.observe()
            btn = ambushCharTC.steer(plan.target, mf)
          end
        end
        if btn == "a" then
          tgtLog("[tgtconfirm] f%d actor=%d tgt=%s spin=%d 7b7d=%02X " ..
            "7b7e=%02X ace=%02X acf=%02X latch=%s age=%d",
            H.frame, actor, tostring(plan.target), plan.tgtSpin,
            H.readByte(0x7B7D), H.readByte(0x7B7E),
            H.readByte(0x7ACE), H.readByte(0x7ACF),
            tostring(ambushCharTC.mask), ambushCharTC.age)
        end
        plan.lastBtn = btn
        return btn
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
        return "a"
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
        local want = cmdRowA(actor, CMD_MAGIC_A)
        if want == nil then return "b" end
        local cur = H.readByte(CMDROW_A + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_MAGIC_A then
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
      return "a"
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
    if turnPlan.kind == "item" and st == ST_TGT_A then
      tgtSample(tag, actor, turnPlan, mf)
    end
    -- LORE-STALL watchdog kept as a safety net (should never fire with the
    -- positional fix; if it does, that's a headline finding -- it logs
    -- LOUDLY and falls back to Fight so the run still terminates).
    if turnPlan.kind == "lore" and st == ST_LORE_A then
      turnPlan.loreStall = (turnPlan.loreStall or 0) + 1
      if turnPlan.loreStall == 600 then
        H.log(string.format(
          "[%s] LORE-STALL WITH FIX (positional model ALSO wrong!) f%d: " ..
          "actor=%d loreId=%d cursor(8927+a)=%d want=%d offered=%s",
          tag, H.frame, actor, turnPlan.loreId,
          H.readByte(LROW_A + actor), loreRowForA(turnPlan.loreId),
          tostring(loreOfferedA(turnPlan.loreId))))
        turnPlan = { kind = "fight", boost = true }
      end
    end
    local slow = (st == ST_ITEM_A)
    local period = slow and 30 or 8
    local on = slow and 6 or 4
    if mf % period >= on then H.setPad({}); return end
    local btn = buttonFor(actor, st)
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
        H.log(string.format("[%s] Ice cast #%d confirmed f%d (boost=%s)", tag,
          iceCasts, H.frame, tostring(turnPlan.boost or false)))
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

local function newStrategyDriver()
  if STRATEGY == "ambush-revive" then
    return newAmbushPlan("thamlab-ambush-revive", { tlKind = "magic", iceBoost = true })
  end
  if STRATEGY == "ambush-revive-fix" then
    return newAmbushPlan("thamlab-ambush-revive-fix", { tlKind = "magic", iceBoost = true })
  end
  if STRATEGY == "ambush-revive-map" then
    return newAmbushPlan("thamlab-ambush-revive-map", { tlKind = "magic", iceBoost = true })
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

local function armSeedWatch()
  local addr = H.seedStoreAddr()
  emu.addMemoryCallback(function()
    local seed = emu.getState()["cpu.a"] & 0xff
    res.seeds[#res.seeds + 1] = seed
    H.log(string.format("[lab] battle seeded $be=$%02X from $021e=%d at f%d",
      seed, H.readByte(0x021E), H.frame))
  end, emu.callbackType.exec, addr, addr)
end

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
  H.loadState("build/states/thamlab_ambush.mss.lua"),
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
  seq({
    creepNav(21, 23, FLEE_WALK),
    pressWalk("up", function()
      return H.battleLoadStarted() or not H.hasControl()
    end, 1800, "step onto (21,22) -> battle 45"),
    H.waitUntil(function() return H.battleActive() end, 6000,
      "ambush battle up", 10),
    H.waitFrames(90),
  }),

  mainFight("thamlab ambush fight (" .. STRATEGY .. ")"),
  H.call(function()
    if F.idle then F.idle() end
    res.fenix1  = H.invCountOf(FENIX_DOWN)
    res.tonic1  = H.invCountOf(TONIC)
    res.potion1 = H.invCountOf(POTION)
    res.mpT, res.mpL, res.mpS =
      H.charMp(TERRA), H.charMp(LOCKE), H.charMp(STRAGO)
    res.standing1 = allStanding()
    H.log(string.format("[lab] battle module gone at f%d (lost=%s)",
      H.frame, tostring(lost)))
  end),

  winTail(function()
    return map() == 351 and H.hasControl() and H.tileAligned()
  end, "ambush win-tail settle"),

  H.call(function()
    H.setPad({})
    local won = H.gameOverFired == 0 and lost == nil and map() == 351
      and partyOf(STRAGO) ~= 0
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
