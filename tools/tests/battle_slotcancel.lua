-- @suite slow
-- battle_slotcancel.lua -- a boosted Slot spin that never runs costs
-- nothing (#346; "boost pays once": a boost that costs pips and buys
-- nothing is a bug).
--
-- A committed action waits in the battle's action queue ($3820) behind
-- whatever is already queued.  If its character loses the action while it
-- waits -- falls, or falls asleep -- vanilla's RemoveAllActions empties his
-- command list and the advance-wait queue, but not the action queue, and
-- ExecAction runs the stale entry as its placeholder, CmdNoEffect ($b5 =
-- $12): nothing happens.  Ot6ActionEnd charged the pending boost there, so a
-- Setzer felled with a boosted spin queued paid for a spin that never ran
-- (first seen in a fault-injected lab, build/attempts/wt/suites-2.2.1/;
-- played here).  Now the ROM marks such a turn at ExecAction's head
-- (Ot6NoActionMark, OT6_NOACTION bit 7: a fresh turn with nothing to run)
-- and Ot6ActionEnd drops the pending tier there instead of spending it.
-- The lost turn's regen pip follows the TLM's ruling: earned if he is still
-- in the fight at the turn's end (a sleep), not if he is out of it (KO'd or
-- petrified, $3ee4 & $c0).  A natural fall is enough; the Fenix Down that
-- raises him plays no part.  The cap hides the pip at bank 5, so the moment
-- the test waits for is a cancel below it: Setzer, whose Defends would hold
-- the bank at 5, spends a pip on a boosted spin whenever his window opens
-- outside a branch point on a bank of BANK_SPEND or more, so his windows
-- come up below the cap however long the fight runs.  (Spending only on a
-- full bank was not enough: a spin cancelled by his fall charges nothing
-- and earns nothing, so a Setzer felled again and again sat at 5 for a
-- whole fight, and the branch point came only when a fresh battle reset
-- his bank to 1 -- the v0.25 re-cut's terra-returned-v1 dealt a second
-- battle where it never did, build/attempts/wt/recut-fallout/slotcancel/.)
--
-- Played, not written: a natural boot of the terra-returned-v1 checkpoint,
-- a drawn battle, and real inputs only.  The party plays a policy a person
-- could (reading what it likes, pressing only buttons):
--   * first the control: Setzer spins boosted (one pip, R) until one such
--     spin has run, the members keeping everyone, him included, above
--     CARE_PCT with Potions;
--   * then the other members raise the fallen with Fenix Downs (Setzer
--     first), give Potions to each other below CARE_PCT, and otherwise
--     Fight Setzer (an ally can be targeted), one blow in flight at a time;
--     Setzer Defends (a guarded turn regenerates a pip).  Well above the
--     members' median blow (measured as they land) a Fight lands at once;
--     nearer, the member holds his window with the cursor on Setzer until
--     Setzer's gauge is full and a monster's action is starting, then
--     strikes, so Setzer's own window opens next with the blow queued
--     behind that action.
-- The branch point is Setzer's window opening on him below the median blow
-- (it fells him), a pip banked, and a member's Fight on him still in its
-- advance wait (read off the command lists and the action queue).  It is
-- snapshotted and branched BRANCHES_PER_POINT times: each branch idles 4
-- frames longer there, then banks one pip with R, spins and commits as fast
-- as a person taps, and is played on, the members now only caring and
-- guarding, until the spin's own turn ends (Ot6ActionEnd with his entity;
-- the no-action mark, the command that ran and his out-of-the-fight bits
-- read there).  Whether the blow lands before the commit (no spin), in the
-- spin's advance wait (vanilla drops the spin with him: no end of its own),
-- or once the spin waits in the action queue (it comes up with the
-- no-action mark) is the draw's business.  When no branch of a point came
-- up marked below bank 5, the snapshot is restored and play goes on from
-- it (Setzer Defends in that window) to the next branch point, at most
-- MAX_POINTS of them.
-- Asserted, per branch:
--   1. a spin that ran ($0F, unmarked), the control's and any branch's:
--      pending -> 0 and the bank down by the tier (the boost is still
--      charged when it buys the spin);
--   2. a boosted spin whose turn came up marked: pending -> 0, nothing
--      charged, and the bank UNCHANGED when he is out of the fight at the
--      turn's end (up one, capped at 5, if he is in it -- a raise came first);
--   3. (no assertion) a spin dropped before it reached the queue ends no
--      turn of its own; the branch is logged and counted, nothing more;
-- and at least one of each of 1 (the control) and 2, 2 below bank 5.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local STOP  = { 0x7B8F, 0x7B90, 0x7B91 }   -- reel stopped flags
local PRESS = { 0x7B92, 0x7B93, 0x7B94 }   -- press stores 1/2/3
local SETZER = 0x09
local CMD_FIGHT, CMD_ITEM, CMD_SLOT, CMD_NOEFFECT = 0x00, 0x01, 0x0F, 0x12
local ST_CMD, ST_ITEM, ST_TGT, ST_DEF, ST_REELS = 0x05, 0x0A, 0x38, 0x27, 0x08
local POTION, FENIX = 0xE9, 0xF0
local BATTINV, ITEMSCR, ITEMROW = 0x2686, 0x8947, 0x894F
local TGTCHARS, TGTMONS = 0x7B7D, 0x7B7E
local LOW_PCT = 15          -- the control spins only while he stands above this
local CARE_PCT = 40         -- ...and give a Potion to any other member below this
local MAX_BATTLES = 6
local BANK_SPEND = 3         -- off a branch point he spins boosted on a bank this high

local NOACTION = nil        -- OT6_NOACTION's WRAM offset (H.sym, at the first step)
local function bp(s)   return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function chid(s) return H.readByte(0x3ED8 + s * 2) end
local function php(s) return H.readWord(0x3BF4 + s * 2) end
local function pmax(s) return H.readWord(0x3C1C + s * 2) end
local function seated(s) return chid(s) ~= 0xFF and pmax(s) > 0 end
local function onFoot()
  return (H.readByte(0x11FA) & 3) == 0 and H.readByte(0x11F3) == 0
end
local actor = nil           -- Setzer's battle slot
local function low() return php(actor) * 100 <= pmax(actor) * LOW_PCT end
local function partyLine()
  local t = {}
  for s = 0, 3 do
    if seated(s) then
      t[#t + 1] = string.format("%02X:%d/%d bp%d p%d", chid(s), php(s), pmax(s),
        bp(s), pend(s))
    end
  end
  return table.concat(t, " ")
end
local function invIdx(item)
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == item and H.readByte(BATTINV + i * 5 + 3) > 0 then
      return i
    end
  end
end
local function invCount(item)
  local i = invIdx(item)
  return i and H.readByte(BATTINV + i * 5 + 3) or 0
end
local function cmdCell(a, cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + a * 12 + r * 3) == cmd then return r end
  end
end
-- An attack on him that is queued and has not run: an entity whose command
-- list holds an action ($32cc, set when the action is queued and cleared
-- as it starts) targeting his slot ($3520, the action's target masks).
-- Only the members' attacks show here: a monster's queued action is an AI
-- turn whose targets are chosen as it runs.
local function threatOn(slot)
  for x = 0, 18, 2 do
    if x ~= slot * 2 then
      local ptr = H.readByte(0x32CC + x)
      if ptr ~= 0xFF and (H.readByte(0x3520 + ptr * 2) & (1 << slot)) ~= 0 then
        return x
      end
    end
  end
end
-- How many actions wait ahead of entity x in the action queue ($3820 from
-- $3a66 to $3a67), or nil when x is not in it (still in its advance wait).
local function aheadOf(x)
  local n = 0
  for i = H.readByte(0x3A66), H.readByte(0x3A67) - 1 do
    local e = H.readByte(0x3820 + i)
    if e == x then return n end
    if e ~= 0xFF then n = n + 1 end
  end
end
-- His gauge is full and nothing of his is queued: his window is next in line.
local function setzerReady()
  return php(actor) > 0 and H.readByte(0x3219 + actor * 2) == 0
    and H.readByte(0x32CC + actor * 2) == 0xFF
end

-- ------------------------------------------------------ the other members
-- One plan per window, chosen when it opens:
--   * Setzer down -> a Fenix Down on him (one raise in flight);
--   * another member down -> a Fenix Down on that member;
--   * another member (Setzer too, before the control) below CARE_PCT -> a
--     Potion on the most hurt;
--   * (after the control, outside the branches) Fight on Setzer, held for
--     the moment when he is near the median blow (planFor, otherWindow);
--   * else Defend.
local attackSetzer = true
local monsterActing, monsterStart = nil, 0   -- a monster's action in progress (exec watches)
local executing, execStart = nil, 0          -- any entity's action in progress (ExecAction..Ot6ActionEnd)
local skipPoint = false      -- playing on from a branch point: not that window again
local ctl, ctlDone = nil, false   -- the control spin (the approach, below)
local blows = {}             -- what the members' Fights have taken off Setzer
local function blow()        -- the median measured blow (40 before any)
  if #blows == 0 then return 40 end
  local t = {}
  for i, v in ipairs(blows) do t[i] = v end
  table.sort(t)
  return t[(#t + 1) // 2]
end
local raising, healing, hitting = nil, {}, nil
local W = {}
local function planFor(a)
  if raising and (php(raising.s) > 0 or H.frame - raising.f > 900) then raising = nil end
  for s, h in pairs(healing) do
    if php(s) > h.hp or php(s) == 0 or H.frame - h.f > 900 then healing[s] = nil end
  end
  if hitting and php(actor) > 0 and php(actor) < hitting.hp then
    blows[#blows + 1] = hitting.hp - php(actor)                 -- a member's blow, measured
    hitting = nil
  elseif hitting and (php(actor) == 0 or H.frame - hitting.f > 900) then
    hitting = nil
  end
  local itemCell = cmdCell(a, CMD_ITEM)
  if itemCell and raising == nil and invIdx(FENIX) then
    if php(actor) == 0 then return { kind = "raise", tgt = actor, cell = itemCell, item = FENIX } end
    for s = 0, 3 do
      if s ~= actor and seated(s) and php(s) == 0 then
        return { kind = "raise", tgt = s, cell = itemCell, item = FENIX }
      end
    end
  end
  if itemCell and invIdx(POTION) then
    local pick, pickPct = nil, nil
    for s = 0, 3 do
      if (s ~= actor or not ctlDone) and seated(s) and php(s) > 0 and healing[s] == nil then
        local pct = php(s) * 100 // math.max(pmax(s), 1)
        if pct < CARE_PCT and (pick == nil or pct < pickPct) then pick, pickPct = s, pct end
      end
    end
    if pick then return { kind = "heal", tgt = pick, cell = itemCell, item = POTION } end
  end
  local fightCell = cmdCell(a, CMD_FIGHT)
  if attackSetzer and ctlDone and fightCell and php(actor) > 0 and hitting == nil then
    -- one blow in flight at a time.  Well above the median blow
    -- measured, a plain Fight wears him down; nearer, the blow may fell him,
    -- so it waits: the window is held, the cursor on him, until his gauge is
    -- full and a monster's action is starting (otherWindow), so his own
    -- window opens next with the blow still queued behind that action
    return { kind = "attack", tgt = actor, cell = fightCell,
             ambush = php(actor) < 2 * blow() }
  end
  return { kind = "defend" }
end

local function otherWindow()
  local a = H.readByte(ACTOR) & 3
  if W.actor ~= a then
    W = { actor = a, n = 0, via = nil, plan = planFor(a) }
    if W.plan.kind ~= "defend" then
      H.log(string.format("[cancel] f%d actor %d (%02X): %s slot %d (%02X) | party %s",
        H.frame, a, chid(a), W.plan.kind, W.plan.tgt, chid(W.plan.tgt), partyLine()))
    end
  end
  W.n = W.n + 1
  local ph = W.n % 10
  local st = H.readByte(MSTATE)
  local function tap(b) H.setPad(ph < 5 and { [b] = true } or {}) end
  local plan = W.plan
  if plan.ambush and not W.sprung and (php(actor) == 0 or W.n > 2400) then
    W.plan = { kind = "defend" }             -- he fell to the monsters, or never readied
    return
  end
  if plan.kind == "defend" then
    if st == ST_CMD then
      if pend(a) > 0 then tap("l") else tap("right") end
    elseif st == ST_DEF then tap("a")
    elseif st == ST_ITEM or st == 0x30 or st == 0x16 or st == 0x24 or st == 0x0E
        or st == ST_TGT then tap("b")
    else H.setPad({}) end
    return
  end
  if st == ST_CMD then
    local cur = H.readByte(0x890F + a)
    if cur ~= plan.cell then tap(cur < plan.cell and "down" or "up"); return end
    if pend(a) > 0 then tap("l"); return end             -- the members never boost
    W.via = plan.kind == "attack" and "list" or "cmd"
    tap("a")
  elseif st == ST_ITEM and plan.kind ~= "attack" then
    local idx = invIdx(plan.item)
    if idx == nil then tap("b"); return end
    local cur = H.readByte(ITEMSCR + a) + H.readByte(ITEMROW + a)
    if cur ~= idx then tap(cur < idx and "down" or "up"); return end
    W.via = "list"
    tap("a")
  elseif st == ST_TGT then
    if W.via ~= "list" and W.via ~= "confirmed" then tap("b"); return end
    local chars = H.readByte(TGTCHARS)
    if H.readByte(TGTMONS) ~= 0 or chars == 0 then
      tap(H.battleLayout().toChars[1])
      return
    end
    if chars ~= (1 << plan.tgt) then
      local cur = 0
      for s = 3, 0, -1 do if chars & (1 << s) ~= 0 then cur = s end end
      tap(cur < plan.tgt and "down" or "up")
      return
    end
    if plan.ambush and not W.sprung then
      -- the cursor rests on Setzer; strike as a monster's action begins
      -- with his gauge full, so the blow waits behind that action and his
      -- own window opens while it plays
      if not (setzerReady() and monsterActing and H.frame - monsterStart <= 12) then
        H.setPad({})
        return
      end
      W.sprung = true
      H.log(string.format("[cancel] f%d actor %d strikes: Setzer's gauge is full and a " ..
        "monster's action began %d frame(s) ago (a %d-frame hold) | party %s", H.frame, a,
        H.frame - monsterStart, W.n, partyLine()))
    end
    if ph < 5 and W.via == "list" then
      W.via = "confirmed"
      if plan.kind == "raise" then raising = { s = plan.tgt, f = H.frame }
      elseif plan.kind == "heal" then healing[plan.tgt] = { f = H.frame, hp = php(plan.tgt) }
      else hitting = { f = H.frame, hp = php(actor) } end
      H.log(string.format("[cancel] f%d actor %d confirms the %s on slot %d",
        H.frame, a, plan.kind, plan.tgt))
    end
    tap("a")
  elseif st == ST_ITEM or st == 0x30 or st == 0x16 or st == 0x24 or st == ST_DEF
      or st == 0x0E then
    tap("b")
  else
    H.setPad({})
  end
end

local function pageOrOther()
  if H.readByte(MENU) == 0 then
    W = {}
    H.setPad(H.frame % 8 < 4 and { a = true } or {})
  else
    otherWindow()
  end
end

-- ------------------------------------------------------ before the branch
-- Setzer's own window, until it opens on him low with a pip: Defend (L
-- first if a pip is pending, so the guard is unboosted).
local SD = { n = 0 }
local function setzerDefend()
  SD.n = SD.n + 1
  local ph = SD.n % 14
  local st = H.readByte(MSTATE)
  local function tap(b) H.setPad(ph < 3 and { [b] = true } or {}) end
  if st == ST_CMD then
    if pend(actor) > 0 then tap("l") else tap("right") end
  elseif st == ST_DEF then tap("a")
  elseif st == ST_ITEM or st == ST_TGT or st == 0x30 or st == 0x16 or st == 0x24
      or st == 0x0E or st == ST_REELS then tap("b")
  else H.setPad({}) end
end
local function branchPoint()
  return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == actor
    and H.readByte(MSTATE) == ST_CMD and php(actor) > 0 and low() and bp(actor) >= 1
    and threatOn(actor) ~= nil and php(actor) < blow() and ctlDone
    and bp(actor) < 5                     -- below the cap, where the pip shows
    and aheadOf(threatOn(actor)) == nil   -- the blow is still in its advance wait
end

-- ---------------------------------------------------------- the branches
-- Setzer's commits (Ot6SlotCommit, the reel commit press) and the ends of
-- his actions (Ot6ActionEnd with his entity, $b5 the command that ran) are
-- observed by exec watches and read on the next frame, when the books have
-- settled.
local rec = nil              -- the live branch's record
local recs = {}
local commitHit, endHit = false, nil

local SS = { n = 0, rTaps = 0 }
local function setzerSpin()
  SS.n = SS.n + 1
  local cyc = SS.cycle or 6          -- quick hands: the blow is already queued
  local ph = SS.n % cyc
  local st = H.readByte(MSTATE)
  local function tap(b) H.setPad(ph < cyc // 2 and { [b] = true } or {}) end
  if st == ST_CMD then
    local want = 1
    if pend(actor) < want then
      if SS.rTaps > 24 then
        error(string.format("R tapped %d times and pending reads %d (want %d)",
          SS.rTaps, pend(actor), want), 0)
      end
      if ph == 0 then SS.rTaps = SS.rTaps + 1 end
      tap("r")
      return
    end
    local cell = cmdCell(actor, CMD_SLOT)
    H.assertEq(cell ~= nil, true, "Setzer's menu offers Slot")
    local cur = H.readByte(0x890F + actor)
    if cur ~= cell then tap(cur < cell and "down" or "up"); return end
    tap("a")
  elseif st == 0x30 then
    tap(H.slotRowButton(actor))    -- Setzer's table: its first row is Slot
  elseif st == ST_REELS then
    if H.readByte(PRESS[3]) ~= 0 and H.readByte(STOP[3]) == 0 then
      H.setPad({})                 -- reel 3 settling: the commit waits for it
    else
      tap("a")                     -- reels 1-3, then the commit
    end
  elseif st == ST_ITEM or st == ST_TGT or st == 0x30 or st == 0x16 or st == 0x24
      or st == ST_DEF or st == 0x0E then
    tap("b")
  else
    H.setPad({})
  end
end

-- The approach.  The control comes first: while Setzer stands above
-- LOW_PCT with a pip, his window spins boosted (one pip) until one such spin
-- has run ($0F) and its books are kept (ctl); every other window of his
-- Defends.  A control spin that fails to run (dropped or cancelled) is
-- simply played again from a later window.
local function approachFrame()
  if commitHit then
    commitHit = false
    if ctl and not ctl.commit then
      ctl.commit = { f = H.frame, p = pend(actor), b = bp(actor), hp = php(actor) }
    end
  end
  if endHit then
    local e = endHit
    endHit = nil
    if ctl and ctl.commit and not ctl.done then
      if e.cmd == CMD_SLOT and not e.noaction then
        ctl.done = { f = H.frame, cmd = e.cmd, hp = e.hp, p = pend(actor), b = bp(actor) }
        ctlDone = true
        H.log(string.format("[cancel] control f%d: a boosted spin RAN: commit f%d pending %d " ..
          "bank %d | turn end $b5=$0F -> pending %d bank %d", H.frame, ctl.commit.f,
          ctl.commit.p, ctl.commit.b, ctl.done.p, ctl.done.b))
      else
        H.log(string.format("[cancel] control f%d: the spin ended as $%02X (no-action mark " ..
          "%s), not run; again", H.frame, e.cmd, tostring(e.noaction)))
        ctl = nil
      end
    end
  end
  if H.readByte(MENU) ~= 0 and php(actor) == 0 and raising == nil and invCount(FENIX) == 0 then
    -- a window is up and he is down with no Fenix Down left to raise him:
    -- no branch point can come (#377: wt/recut-fallout's sweep2 k5 spent
    -- 40000 frames healing around a fallen SETZER with an empty bag)
    H.assertEq(false, true, string.format("precondition: a Fenix Down to raise SETZER " ..
      "(f%d: the bag is out)", H.frame))
  end
  if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == actor then
    W = {}
    if ctl and ctl.commit and ctl.away and not ctl.done then ctl = nil end  -- dropped: again
    if not ctlDone and (ctl == nil or not ctl.commit) and not low() and bp(actor) >= 1 then
      ctl = ctl or {}
      setzerSpin()
    elseif ctlDone and bp(actor) >= BANK_SPEND then
      setzerSpin()      -- keep the bank off the cap, where it hides the pip
    else
      setzerDefend()
    end
  else
    if ctl and ctl.commit then ctl.away = true end
    skipPoint = false
    SD.n, SS.n = 0, 0
    pageOrOther()
  end
end

local function branchFrame()
  if commitHit then
    commitHit = false
    if rec.commit == nil then
      rec.commit = { f = H.frame, p = pend(actor), b = bp(actor), hp = php(actor) }
      rec.blowAtCommit = rec.threat and (aheadOf(rec.threat) and "queued" or
        (H.readByte(0x32CC + rec.threat) ~= 0xFF and "advance wait" or "gone")) or "-"
      H.log(string.format("[cancel] branch %d f%d commit: pending %d, bank %d, hp %d | party %s",
        rec.k, H.frame, rec.commit.p, rec.commit.b, rec.commit.hp, partyLine()))
    end
  end
  if endHit then
    local e = endHit
    endHit = nil
    if rec.commit and rec.done == nil and rec.dropped == nil then
      if e.noaction or e.cmd == CMD_SLOT then
        rec.done = { f = H.frame, cmd = e.cmd, hp = e.hp, p = pend(actor), b = bp(actor),
                     kind = e.noaction and "cancelled" or "ran", ko = e.ko }
      else
        -- a later turn of his (the Defend after a raise) ended first: the
        -- spin was dropped with him before it reached the action queue
        rec.dropped = { f = H.frame, cmd = e.cmd }
      end
    end
  end
  if not rec.hit and php(actor) < rec.hp0 then rec.hit = H.frame end  -- the blow lands
  if rec.commit and not rec.queued and aheadOf(actor * 2) ~= nil then
    rec.queued = H.frame                   -- the spin joins the action queue
  end
  if not rec.blowQueued and rec.threat and aheadOf(rec.threat) ~= nil then
    rec.blowQueued = H.frame
  end
  if not rec.commit and php(actor) == 0 then
    rec.lost = H.frame                     -- the blow landed before the commit
    return
  end
  if rec.commit and not rec.fell and php(actor) == 0 then
    rec.fell = H.frame
    H.log(string.format("[cancel] branch %d f%d SETZER fell with his spin (committed f%d) " ..
      "not yet run | party %s", rec.k, H.frame, rec.commit.f, partyLine()))
  end
  if rec.fell and not rec.raised and php(actor) > 0 then
    rec.raised = H.frame
    H.log(string.format("[cancel] branch %d f%d SETZER raised: hp %d, pending %d, bank %d",
      rec.k, H.frame, php(actor), pend(actor), bp(actor)))
  end
  if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == actor then
    W = {}
    if rec.commit then setzerDefend() else setzerSpin() end   -- one spin per branch
  else
    SS.n = 0
    pageOrOther()
  end
end

local function tally()
  local ran, cancelled = 0, 0
  for _, r in ipairs(recs) do
    -- counted once the branch has been logged (the outer drive stops on it)
    if r.logged and r.done and r.done.kind == "ran" and r.commit.p > 0 then ran = ran + 1 end
    if r.logged and r.done and r.done.kind == "cancelled" and r.commit.p > 0 then
      cancelled = cancelled + 1
    end
  end
  return ran, cancelled
end

local snap = nil
local points = 0
local function branch(j, wait)
  local req, k
  return H.cond(function() return true end, {
    H.call(function() H.setPad({}); rec = nil; req = H.requestLoadState(snap.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load (branch " .. j .. " of point " .. points .. ")")
      H.rearmInputInjection()
      k = #recs + 1
      rec = { k = k, cycle = wait, point = points, f0 = H.frame, hp0 = php(actor),
              threat = threatOn(actor) }
      recs[#recs + 1] = rec
      commitHit, endHit = false, nil
      attackSetzer = false
      raising, healing, hitting, W, SD = nil, {}, nil, {}, { n = 0 }
      SS = { n = 0, rTaps = 0, cycle = wait }
      H.log(string.format("[cancel] branch %d (point %d): SETZER taps every %d frames",
        k, points, wait))
    end),
    H.waitFrames(1),
    H.driveUntil(function()
      if not H.battleLoadStarted() then return true end
      if rec.done or rec.dropped or rec.lost then return true end
      return rec.commit ~= nil and H.frame - rec.commit.f > 3000
    end, 9000, { H.call(branchFrame), H.waitFrames(1) }, "a branch: the spin's turn ends"),
    H.call(function()
      local c, d = rec.commit, rec.done
      local function off(f) return f and string.format("+%d", f - rec.f0) or "-" end
      H.log(string.format("[cancel] branch %d timing from the window (taps every %d): blow " ..
        "queued %s, commit %s (the blow then: %s), spin queued %s, blow lands %s, fell %s", k,
        rec.cycle, off(rec.blowQueued), off(c and c.f), tostring(rec.blowAtCommit),
        off(rec.queued), off(rec.hit), off(rec.lost or rec.fell)))
      if not c then
        H.log(string.format("[cancel] branch %d: NO COMMIT: %s", k, rec.lost and
          string.format("he fell at f%d, before the commit press", rec.lost)
          or "the window was taken away"))
      elseif not d then
        H.log(string.format("[cancel] branch %d DROPPED: no end of the spin's own (%s; " ..
          "fell f%s, raised f%s): it never reached the action queue | pending %d bank %d",
          k, rec.dropped and string.format("his next turn ended as $%02X at f%d",
          rec.dropped.cmd, rec.dropped.f) or "3000 frames passed", tostring(rec.fell),
          tostring(rec.raised), pend(actor), bp(actor)))
      else
        local what = d.kind == "ran" and "RAN" or "CANCELLED"
        H.log(string.format("[cancel] branch %d %s: commit f%d pending %d bank %d | turn end " ..
          "f%d no-action mark %s $b5=$%02X hp %d%s -> pending %d bank %d (fell f%s, raised f%s)",
          k, what, c.f, c.p, c.b, d.f, d.kind == "cancelled" and "SET" or "clear", d.cmd,
          d.hp, d.ko and " out of the fight" or "", d.p, d.b, tostring(rec.fell), tostring(rec.raised)))
      end
      rec.logged = true
    end),
  })
end

-- ------------------------------------------------------------- the draws
-- The draw is battle_slots' (H.newEncounterDraw, lib/ot6_field.lua): pace a
-- stretch of the disembark row that rolls one group, budget the encounters
-- over every encounter-counter state from the pool's decode (#299), run from
-- the rest or fight out a pack that cannot be run from, care after each.
-- The floor is two bodies and 600 max HP with no monster that can take a
-- member's turn on any of its own (H.judgeFormation).  This file used to
-- take six clock-walked draws for two bodies and 900 max HP by live count:
-- a bare number, and on the Blackjack's plain (group 10) only Mind Candy
-- packs reach 900 (battle_slots' drawBattle comment), whose SleepSting
-- takes a turn on any of their own.  Nothing here attacks the formation but
-- SETZER's spins.
local msPresent = {}
local function drawBattle(tag)
  local D = H.newEncounterDraw({ tag = tag, minBodies = 2, minHp = 600 })
  local steps = D.steps()
  steps[#steps + 1] = H.call(function()
    msPresent = D.msPresent
    actor = nil
    for s = 0, 3 do if chid(s) == SETZER then actor = s end end
    H.assertEq(actor ~= nil, true, tag .. ": SETZER present")
    H.log(string.format("%s: setzer slot %d monsters={%s} | party %s | bag: %d Fenix Down, " ..
      "%d Potion", tag, actor, table.concat(msPresent, ","), partyLine(), invCount(FENIX),
      invCount(POTION)))
  end)
  return steps
end

-- Rounds, battle after battle: draw when no battle is up, play on until
-- the branch point or the battle's end; at a branch point, snapshot and play
-- BRANCHES_PER_POINT branches; if none of them ended as the placeholder,
-- restore the snapshot and play on from it (Setzer Defends in that window,
-- as at any other) to the next branch point, at most MAX_POINTS of them.
local battles, atPoint = 0, false
local BRANCHES_PER_POINT, MAX_POINTS = 2, 10
-- each branch's hands: a tap every CYCLES[j] frames, half of it held.  The
-- commit is a race with the blow (header), so the branches differ in how
-- fast SETZER's hands are, not in idle frames at the window: an idle wait
-- there does not re-draw the battle (#360)
local CYCLES = { 4, 6 }
local function belowCap()
  local n = 0
  for _, r in ipairs(recs) do
    if r.logged and r.done and r.done.kind == "cancelled" and r.commit.p > 0
       and r.commit.b < 5 then n = n + 1 end
  end
  return n
end
local function found() return belowCap() >= 1 end
local function backToPlain()
  local ph = 0
  return H.driveUntil(function()
    return H.worldMode() and H.worldHasControl()
  end, 3000, {
    H.call(function() ph = ph + 1; H.setPad(ph % 8 < 4 and { a = true } or {}) end),
  }, "back on the plain")
end
local function round()
  local draw = { H.call(function()
    battles = battles + 1
    raising, healing, hitting, W, SD = nil, {}, nil, {}, { n = 0 }
  end) }
  for _, st in ipairs(drawBattle("battle")) do draw[#draw + 1] = st end
  local body = {
    H.cond(function() return not H.battleLoadStarted() end, draw, {}),
    H.call(function() atPoint, attackSetzer = false, true end),
    H.driveUntil(function()
      if not H.battleLoadStarted() then return true end
      if not skipPoint and branchPoint() then atPoint = true; return true end
      return false
    end, 40000, { H.call(approachFrame), H.waitFrames(1) },
      "Setzer's window opens on him low with a pip and a blow queued, or the battle ends"),
  }
  local point = {
    H.call(function()
      points = points + 1
      local t = threatOn(actor)
      H.log(string.format("[cancel] branch point %d f%d (battle %d): hp %d/%d, pending %d, " ..
        "bank %d; entity %d's queued Fight targets him (%s), the members' median blow " ..
        "%s | party %s", points, H.frame, battles, php(actor), pmax(actor),
        pend(actor), bp(actor), t, aheadOf(t) and string.format(
        "%d action(s) ahead of it in the queue", aheadOf(t)) or "still in its advance wait",
        string.format("%d of %d", blow(), #blows), partyLine()) .. string.format(" | playing: %s",
        executing and string.format("entity %d for %d frame(s)", executing, H.frame - execStart)
        or "nothing"))
      H.setPad({})
      snap = H.requestSaveState()
    end),
    H.waitFrames(2),
    H.call(function() H.checkReq(snap, "snapshot at Setzer's window") end),
  }
  for j = 1, BRANCHES_PER_POINT do point[#point + 1] = branch(j, CYCLES[j]) end
  local req
  point[#point + 1] = H.cond(function() return not found() end, {
    H.call(function() H.setPad({}); req = H.requestLoadState(snap.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load (play on from branch point " .. points .. ")")
      H.rearmInputInjection()
      skipPoint, attackSetzer = true, true
      commitHit, endHit = false, nil
      raising, healing, hitting, W, SS, SD = nil, {}, nil, {}, { n = 0, rTaps = 0 }, { n = 0 }
      H.log(string.format("[cancel] no placeholder from branch point %d: playing on from it", points))
    end),
  }, {})
  body[#body + 1] = H.cond(function() return atPoint end, point, {
    H.call(function()
      H.log(string.format("[cancel] battle %d ended before a branch point | party %s",
        battles, partyLine()))
    end),
    H.cond(function() return H.battleLoadStarted() end, { H.fleeBattle(12000, { onCantRun = "fight" }) }, {}),
    backToPlain(),
    H.waitFrames(60),
  })
  return body
end

local steps = {
  H.call(function()
    NOACTION = H.sym("OT6_NOACTION")
    local cmt = H.sym("Ot6SlotCommit")
    emu.addMemoryCallback(function() commitHit = true end, emu.callbackType.exec, cmt, cmt)
    local ae = H.sym("Ot6ActionEnd")
    emu.addMemoryCallback(function()
      local x = emu.getState()["cpu.x"] & 0xffff
      if x == monsterActing then monsterActing = nil end
      if x == executing then executing = nil end
      if actor == nil then return end
      if x == actor * 2 then
        -- what ended: the ROM's own record of a fresh turn with nothing to
        -- run (OT6_NOACTION bit 7, written at ExecAction's head by
        -- Ot6NoActionMark), the command that ran, and whether he was out of
        -- the fight (KO'd or petrified)
        endHit = { cmd = H.readByte(0xB5), hp = php(actor),
                   noaction = (H.readByte(NOACTION) & 0x80) ~= 0,
                   ko = (H.readByte(0x3EE4 + x) & 0xC0) ~= 0 }   -- KO'd or petrified
      end
    end, emu.callbackType.exec, ae, ae)
    local ea = H.sym("ExecAction")
    emu.addMemoryCallback(function()
      local x = emu.getState()["cpu.x"] & 0xff
      executing, execStart = x, H.frame
      if x >= 8 then monsterActing, monsterStart = x, H.frame end
    end, emu.callbackType.exec, ea, ea)
    local addr = H.seedStoreAddr()
    emu.addMemoryCallback(function()
      local seed = emu.getState()["cpu.a"] & 0xff
      H.log(string.format("[cancel] battle f%d key %s", H.frame,
        H.firstBattleKey(seed, H.readWord(0x11e0))))
    end, emu.callbackType.exec, addr, addr)
  end),
  -- cold Continue (the checkpoint's $307ff0=3 preselects slot 3)
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000, "cold Continue to the world", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function() H.assertEntryContract("terra-returned-v1") end),
  (function()
    local ph2 = 0
    return H.driveUntil(function()
      return onFoot() and H.worldHasControl() and H.worldAligned()
    end, 8000, {
      H.call(function()
        ph2 = ph2 + 1
        H.setPad((ph2 % 45) < 6 and { b = true } or {})
      end),
    }, "disembark the grounded Blackjack")
  end)(),
  H.release(),
  H.waitFrames(30),
  H.driveUntil(function()
    return found() or points >= MAX_POINTS
      or (battles >= MAX_BATTLES and not H.battleLoadStarted())
  end, 300000, round(), "rounds until a boosted spin of his ends as the placeholder"),
}
steps[#steps + 1] = H.call(function()
  H.setPad({})
  local ran, cancelled = tally()
  local fails, n = {}, 0
  for _, r in ipairs(recs) do
    local c, d = r.commit, r.done
    if c and d then
      n = n + 1
      if d.kind == "ran" then
        local wantB = c.p > 0 and c.b - c.p or math.min(c.b + 1, 5)
        if not (d.p == 0 and d.b == wantB) then
          fails[#fails + 1] = string.format("branch %d: a spin that ran (pending %d, bank %d " ..
            "at its commit) left pending %d, bank %d (want 0, %d)", r.k, c.p, c.b, d.p, d.b, wantB)
        end
      else
        -- the TLM's ruling (#346): nothing charged either way; a lost turn
        -- earns the regen pip only if he still stands at its end
        local wantB = d.ko and c.b or math.min(c.b + 1, 5)
        if not (d.p == 0 and d.b == wantB) then
          fails[#fails + 1] = string.format("branch %d: a spin that never ran (no-action " ..
            "mark set, pending %d, bank %d at its commit, %s at its end) left pending %d, " ..
            "bank %d (want 0, %d: nothing charged, %s)", r.k, c.p, c.b,
            d.ko and "out of the fight" or "in the fight", d.p, d.b, wantB,
            d.ko and "no regen out of the fight" or "the unboosted regen")
        end
      end
    end
  end
  H.log(string.format("[cancel] SUMMARY battles=%d points=%d branches=%d ended=%d " ..
    "ran(boosted)=%d cancelled(boosted)=%d", battles, points, #recs, n, ran, cancelled))
  for _, f in ipairs(fails) do H.log("[cancel] FAIL " .. f) end
  H.assertEq(#fails, 0, "every branch's books: a spin that ran paid its tier, a spin " ..
    "that never ran cost nothing (#346)")
  H.assertEq(ctlDone, true, "precondition: the control -- a boosted spin of his ran " ..
    "on the approach")
  local c, d = ctl.commit, ctl.done
  H.assertEq(d.p == 0 and d.b == c.b - c.p, true, string.format("the control: a boosted " ..
    "spin that ran paid its tier: pending %d -> %d (want 0), bank %d -> %d (want %d)",
    c.p, d.p, c.b, d.b, c.b - c.p))
  H.assertEq(belowCap() >= 1, true, string.format("precondition: at least one branch's " ..
    "boosted spin came up with nothing to run (the no-action mark) below bank 5, where the " ..
    "regen pip shows -- Setzer fell with it queued (%d marked in all)", cancelled))
end)

H.run({ maxFrames = 400000 }, steps)
