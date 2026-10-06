-- @suite slow
-- battle_slotcancel.lua -- a boosted Slot spin that never runs costs
-- nothing (#346; "boost pays once": a boost that costs pips and buys
-- nothing is a bug).
--
-- A committed action waits in the battle's action queue ($3820) behind
-- whatever is already queued.  If its character loses the action while it
-- waits -- falls, is petrified or falls asleep -- vanilla's RemoveAllActions
-- empties his command list and the advance-wait queue, but not the action
-- queue, and ExecAction runs the stale entry as its placeholder,
-- CmdNoEffect ($b5 = $12): nothing happens.  Ot6ActionEnd charged the
-- pending boost there, so a Setzer who lost a boosted spin that way paid
-- for a spin that never ran.  Now the ROM marks such a turn at ExecAction's
-- head (Ot6NoActionMark, OT6_NOACTION bit 7: a fresh turn with nothing to
-- run) and Ot6ActionEnd drops the pending tier there instead of spending
-- it.  The lost turn's regen pip follows the TLM's ruling: earned if he is
-- still in the fight at the turn's end (a sleep), not if he is out of it
-- (KO'd or petrified, $3ee4 & $c0).
--
-- THE CANCEL IS A DECLARED FAULT INJECTION (docs/TESTING.md, "Synthetic
-- mechanism tests"; the coordinator's ruling on #377, v0.26).  The property
-- is the ROM's handling of a spin whose caster loses his action while it
-- waits, not whether a party can arrange that by play: three play policies
-- -- members felling Setzer with a blow timed into his wait -- failed 2 to
-- 3 of 12 draws each, the queued blow landing before his ~100-frame commit
-- and every fall between branch points spending a Fenix Down
-- (build/attempts/wt/v026-rom2/slotcancel/).  Nothing in these fights puts
-- him to sleep or stone by play: the party knows no Sleep and carries no
-- item that inflicts it, and every monster action measured on him was a
-- plain Fight ($b5 = $00, 12 traced runs).
--
-- So: Sleep, injected in the shape its own handler leaves -- the four
-- bytes SetStatus_0f and UpdateStatus write when a Sleep lands: STATUS2
-- bit 7 ($3ee5), the sleep counter $12 ($3cf9), $3aa0.7 cleared, and
-- $3204's RemoveAllActions request ($40) -- written once his committed
-- spin stands in the action queue behind another entity's entry (the
-- measured point, below).  Everything after is the engine's: that entry's
-- action runs, its AfterAction2 serves the $3204 request for every entity
-- (RemoveAllActions: his command list and the advance-wait queue emptied,
-- the action queue left alone), and his stale entry comes up.  Sleep's own
-- allowed-mask ($331d) is read first and asserted.  Sleep and not Wound or
-- Petrify: of the three statuses that empty the advance-wait queue it is
-- the one whose handler leaves nothing else to fake (a Wound also needs HP
-- 0, the death machinery and a Fenix Down; a Petrify the dead flag), and it
-- is the "falls asleep" half of what this file always meant, the
-- in-the-fight arm of the TLM's ruling -- so no Fenix Down is spent by it
-- and none enters the verdict.  The writes are this file's line in
-- tools/state_write_waivers.txt.
--
-- The measured point.  A commit puts his entry in the advance-wait queue
-- ($3720), and the battle loop moves those entries, in order, into the
-- action queue between actions; first in line, his runs at once and
-- nothing can come between ("aw=[02] aq=[]" at the commit, "aq=[02]" 154
-- frames later with nothing running, his ExecAction 26 frames after,
-- build/attempts/wt/v026-rom2/r3/sc/dbg_k0.log.gz).  So his commit is held
-- (the last reel's press) until another entity's entry stands in the
-- advance-wait queue; his follows it into the action queue, and the
-- injection is made there.  First cuts injected as a status to set behind
-- a running monster action, or held the commit for a monster's action to
-- begin, and reached the precondition on 5 to 7 of 12 draws (r3/sc/inj*).
--
-- Played around the injection: a natural boot of the terra-returned-v1
-- checkpoint, a drawn battle, and real inputs only.  The members never
-- attack; they raise the fallen with Fenix Downs (Setzer first), give
-- Potions below CARE_PCT, and otherwise Defend.  Setzer:
--   * the control first: a boosted spin (one pip, R) that runs ($0F);
--   * then, at each window of his with 1 to 4 pips banked (below the cap,
--     where the regen pip shows), a boosted spin whose commit is held as
--     above, and the injection once his entry waits behind another.  A
--     spin that still reached the front first ran, uninjected; the next
--     window tries again, at most MAX_ATTEMPTS of them;
--   * other windows Defend (a pip at 5 is spent on a boosted spin first,
--     to bring the bank below the cap).
-- Asserted, over every attempt:
--   1. a spin that ran ($0F, unmarked), the control's and any attempt's:
--      pending -> 0 and the bank down by the tier;
--   2. a boosted spin whose turn came up marked: pending -> 0, nothing
--      charged, and the bank up one (capped at 5) when he is in the fight at
--      the turn's end -- asleep, as injected -- or UNCHANGED if out of it;
--   3. a marked turn with him in the fight came after the injected Sleep
--      was applied (the bit seen set; a blow may wake him again before the
--      stale entry comes up), and the Sleep was allowed by his $331c;
-- and the control, and at least one of 2 below bank 5 that the injection
-- made (in the fight, Sleep applied).  A spin a monster's blow cancels by
-- felling him (out of the fight) is booked by 2 like any other, but does
-- not count toward the precondition.
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
-- injection attempts: 8 of 20 attempts over 12 drawn histories ran
-- uninjected (r3/sc/inj6_k*), q = 0.4, and q^8 <= 1e-3
local MAX_ATTEMPTS = 8

local slept = nil           -- whether SETZER was asleep at his last ExecAction
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
-- The queue is a ring: both indices are bytes the engine inc's (wrapping
-- at 256, _c24e77 and the battle loop), so it is walked modulo 256 (a
-- plain start..end-1 loop read a wrapped queue as empty).
local function aheadOf(x)
  local n, i, stop = 0, H.readByte(0x3A66), H.readByte(0x3A67)
  while i ~= stop do
    local e = H.readByte(0x3820 + i)
    if e == x then return n end
    if e ~= 0xFF then n = n + 1 end
    i = (i + 1) & 0xFF
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
local attackSetzer = false   -- the members never attack him now
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
local rec = nil              -- the live branch's record
local recs = {}
local commitHit, endHit = false, nil

local SS = { n = 0, rTaps = 0 }
-- A committed action enters the advance-wait queue ($3720, ring
-- $3a64..$3a65) and the battle loop moves those entries, in order, into the
-- action queue ($3820) between actions.  Measured after a commit (round-3
-- dbg_k0.log): "aw=[02] aq=[]" at +0, "aq=[02]" at +154 with nothing
-- executing, ExecAction at +180 -- his entry first in line, so nothing
-- ran between its entry and its turn.  With another entity's entry ahead
-- of his in the advance-wait queue, his follows it and waits behind it.
local function otherWaiting()
  local i, stop = H.readByte(0x3A64), H.readByte(0x3A65)
  while i ~= stop do
    local e = H.readByte(0x3720 + i)
    if e ~= 0xFF and e ~= actor * 2 then return true end
    i = (i + 1) & 0xFF
  end
  return false
end
-- another entity has an action committed and not yet started ($32cc, its
-- command list, set as the action is queued and cleared as it starts)
local function setzerSpin()
  SS.n = SS.n + 1
  local ph = SS.n % 6                -- quick hands: the blow is already queued
  local st = H.readByte(MSTATE)
  local function tap(b) H.setPad(ph < 3 and { [b] = true } or {}) end
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
    elseif SS.hold and H.readByte(PRESS[3]) ~= 0 and not otherWaiting() then
      -- the injection attempt's commit waits until another entity's action
      -- stands in the advance-wait queue, so his entry follows it into the
      -- action queue and waits there behind it
      H.setPad({})
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

-- ------------------------------------------------------------- the draws
local msPresent = {}
local function drawBattle(tag, tries)
  local steps = { H.call(function() H.vars.suitable = false end) }
  -- a closed square: the walk comes back where it started, so six draws
  -- (and the encounters a varied history used up first) do not drift the
  -- party off the plain into a town, where no encounter fires ("down, down,
  -- right, right, down, down, left, left" walked four steps south a lap)
  local pattern = { "down", "down", "right", "right", "up", "up",
                    "left", "left" }
  for n = 1, tries do
    local w = {
      (function()
        local ph = 0
        return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
          H.call(function()
            ph = ph + 1
            H.setPad({ [pattern[(math.floor(ph / 20) % #pattern) + 1]] = true })
          end),
        }, tag .. ": a real world encounter fires (draw " .. n .. ")")
      end)(),
      H.release(),
      H.waitUntil(function() return H.battleActive() end, 900,
        tag .. ": battle active (draw " .. n .. ")", 30),
      H.waitFrames(240),
      H.call(function()
        msPresent = {}
        for m = 0, 5 do
          if H.readByte(0x3AA8 + m * 2) % 2 == 1 then msPresent[#msPresent + 1] = m end
        end
        local mhp = 0
        for _, m in ipairs(msPresent) do mhp = mhp + H.readWord(0x3BFC + m * 2) end
        -- the monsters have to outlast the members' turns and the branches
        H.vars.suitable = (#msPresent >= 2 and mhp >= 900)
        H.log(string.format("%s draw %d: %d bodies, %d total max HP -> %s",
          tag, n, #msPresent, mhp, H.vars.suitable and "FIGHT" or "flee"))
      end),
      H.cond(function() return not H.vars.suitable end, {
        H.fleeBattle(9000, { onCantRun = "fight" }),
        H.waitUntil(function()
          return H.worldMode() and H.worldHasControl()
        end, 1200, tag .. ": back on the plain after draw " .. n, 10),
        H.waitFrames(30),
      }, {}),
    }
    if n == 1 then
      for _, s in ipairs(w) do steps[#steps + 1] = s end
    else
      steps[#steps + 1] = H.cond(function() return not H.vars.suitable end, w, {})
    end
  end
  steps[#steps + 1] = H.call(function()
    H.assertEq(H.vars.suitable, true, tag .. ": the pool dealt a formation that lasts")
    actor = nil
    for s = 0, 3 do if chid(s) == SETZER then actor = s end end
    H.assertEq(actor ~= nil, true, tag .. ": SETZER present")
    H.log(string.format("%s: setzer slot %d monsters={%s} | party %s | bag: %d Fenix Down, " ..
      "%d Potion", tag, actor, table.concat(msPresent, ","), partyLine(), invCount(FENIX),
      invCount(POTION)))
  end)
  return steps
end


-- ------------------------------------------------------------ the approach
-- The control first (a boosted spin that runs), then injection attempts.
local SLEEP_BIT = 0x80                -- STATUS2 bit 7 (SetStatusTbl's $0f)
local ALLOWED2 = 0x331D               -- statuses 2 that can be set (+entity*2)
local attempts = {}                   -- every injection attempt's record
local A = nil                         -- the live attempt
local spinOpen = nil
local function asleep() return (H.readByte(0x3EE5 + actor * 2) & SLEEP_BIT) ~= 0 end
local function cancelledBelowCap()
  local n = 0
  for _, a in ipairs(attempts) do
    -- the injection's own cancel: in the fight at the turn's end, and the
    -- injected Sleep seen applied before it (a fall to a monster's blow
    -- that cancels a spin is booked the same way but is play's, not the
    -- precondition)
    if a.done and a.done.kind == "cancelled" and a.commit.p > 0 and a.commit.b < 5
       and not a.done.ko and a.sleptF ~= nil and a.sleptF <= a.done.f then n = n + 1 end
  end
  return n
end
local function found() return cancelledBelowCap() >= 1 end

local function approachFrame()
  if commitHit then
    commitHit = false
    if ctl and not ctl.commit and not ctlDone then
      ctl.commit = { f = H.frame, p = pend(actor), b = bp(actor), hp = php(actor) }
    elseif A and not A.commit then
      A.commit = { f = H.frame, p = pend(actor), b = bp(actor), hp = php(actor) }
      H.log(string.format("[inject] attempt %d f%d commit: pending %d bank %d; a monster's "
        .. "action began %s frame(s) ago | party %s", #attempts, H.frame, A.commit.p, A.commit.b,
        monsterActing and tostring(H.frame - monsterStart) or "-", partyLine()))
    end
  end
  -- the injection: once, as his committed spin waits in the action queue
  if A and A.commit and not A.injected and not A.done then
    -- only behind another entry in the action queue: that action's
    -- AfterAction2 is what empties his lists (RemoveAllActions) before his
    -- entry comes up.  An entry first in line runs at once and is not
    -- injected.
    local ahead = aheadOf(actor * 2)
    if ahead ~= nil and ahead >= 1 and executing ~= actor * 2 then
      A.allowed = (H.readByte(ALLOWED2 + actor * 2) & SLEEP_BIT) ~= 0
      H.assertEq(A.allowed, true, "precondition: Sleep can be set on SETZER ($331c allows it)")
      -- ---- STATE WRITES 1-4 of 4 (waiver file): what SetStatus_0f and
      -- UpdateStatus leave for a Sleep that lands -- STATUS2 bit 7, the
      -- sleep counter $12, $3aa0.7 cleared (the battle menu may open), and
      -- $3204's RemoveAllActions request ($40), which the running action's
      -- AfterAction2 serves for every entity -------------------------------- --
      local e = actor * 2
      H.writeByte(0x3EE5 + e, H.readByte(0x3EE5 + e) | SLEEP_BIT)
      H.writeByte(0x3CF9 + e, 0x12)
      H.writeByte(0x3AA0 + e, H.readByte(0x3AA0 + e) & 0x7F)
      H.writeByte(0x3204 + e, H.readByte(0x3204 + e) | 0x40)
      A.injected = { f = H.frame, ahead = aheadOf(actor * 2), executing = executing }
      H.log(string.format("[inject] attempt %d f%d Sleep written in its handler's shape: the spin "
        .. "waits with %d action(s) ahead, entity %s executing", #attempts, H.frame,
        A.injected.ahead, tostring(executing)))
    end
  end
  if A and A.injected and not A.sleptF and asleep() then A.sleptF = H.frame end
  if endHit then
    local e = endHit
    endHit = nil
    if ctl and ctl.commit and not ctl.done and not ctlDone then
      if e.cmd == CMD_SLOT and not e.noaction then
        ctl.done = { f = H.frame, cmd = e.cmd, hp = e.hp, p = pend(actor), b = bp(actor) }
        ctlDone = true
        H.log(string.format("[cancel] control f%d: a boosted spin RAN: commit f%d pending %d " ..
          "bank %d | turn end $b5=$0F -> pending %d bank %d", H.frame, ctl.commit.f,
          ctl.commit.p, ctl.commit.b, ctl.done.p, ctl.done.b))
      else
        ctl = nil
      end
    elseif A and A.commit and not A.done then
      if e.noaction or e.cmd == CMD_SLOT then
        A.done = { f = H.frame, cmd = e.cmd, hp = e.hp, p = pend(actor), b = bp(actor),
                   kind = e.noaction and "cancelled" or "ran", ko = e.ko, sleptAtExec = e.slept }
        H.log(string.format("[inject] attempt %d %s: commit f%d pending %d bank %d | turn end " ..
          "f%d no-action mark %s $b5=$%02X%s, asleep at its ExecAction %s -> pending %d bank %d",
          #attempts, A.done.kind == "ran" and "RAN" or "CANCELLED", A.commit.f, A.commit.p,
          A.commit.b, H.frame, e.noaction and "SET" or "clear", e.cmd,
          e.ko and " out of the fight" or "", tostring(e.slept), A.done.p, A.done.b))
      else
        A.done = { kind = "other", cmd = e.cmd }
      end
      A = nil
    end
  end
  if H.readByte(MENU) ~= 0 and php(actor) == 0 and raising == nil and invCount(FENIX) == 0 then
    H.assertEq(false, true, string.format("precondition: a Fenix Down to raise SETZER " ..
      "(f%d: the bag is out)", H.frame))
  end
  if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == actor then
    W = {}
    if ctl and ctl.commit and ctl.away and not ctl.done then ctl = nil end
    if A and not A.commit and A.away then A = nil end      -- the window went by
    if not ctlDone then
      if (ctl == nil or not ctl.commit) and not low() and bp(actor) >= 1 then
        ctl = ctl or {}
        SS.hold = false
        setzerSpin()
      else
        setzerDefend()
      end
    elseif A == nil and #attempts < MAX_ATTEMPTS and bp(actor) >= 1 and bp(actor) <= 4 then
      A = { n = #attempts + 1 }
      attempts[#attempts + 1] = A
      SS.hold = true
      setzerSpin()
    elseif A ~= nil and not A.commit then
      setzerSpin()
    elseif bp(actor) >= 5 then
      SS.hold = false
      setzerSpin()      -- a spin that runs brings the bank under the cap
    else
      setzerDefend()
    end
  else
    if ctl and ctl.commit then ctl.away = true end
    if A and not A.commit then A.away = true end
    SD.n, SS.n, SS.rTaps = 0, 0, 0
    pageOrOther()
  end
end

-- Rounds: draw when no battle is up, play on until the injection has a
-- cancelled turn below the cap, MAX_ATTEMPTS attempts have been made, or
-- the battle ends.
local battles = 0
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
  for _, st in ipairs(drawBattle("battle", 6)) do draw[#draw + 1] = st end
  return {
    H.cond(function() return not H.battleLoadStarted() end, draw, {}),
    H.driveUntil(function()
      if not H.battleLoadStarted() then return true end
      return found() or (#attempts >= MAX_ATTEMPTS and A == nil)
    end, 60000, { H.call(approachFrame), H.waitFrames(1) },
      "the control, then an injected spin's turn ends, or the battle ends"),
    H.cond(function() return not found() and not H.battleLoadStarted() end, {
      H.call(function()
        H.log(string.format("[cancel] battle %d ended | party %s", battles, partyLine()))
      end),
      backToPlain(),
      H.waitFrames(60),
    }, {}),
  }
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
                   ko = (H.readByte(0x3EE4 + x) & 0xC0) ~= 0,     -- KO'd or petrified
                   slept = slept }
      end
    end, emu.callbackType.exec, ae, ae)
    local ea = H.sym("ExecAction")
    emu.addMemoryCallback(function()
      local x = emu.getState()["cpu.x"] & 0xff
      executing, execStart = x, H.frame
      if x >= 8 then monsterActing, monsterStart = x, H.frame end
      if actor ~= nil and x == actor * 2 then
        slept = (H.readByte(0x3EE5 + x) & 0x80) ~= 0       -- asleep as his turn comes up
      end
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
    return found() or #attempts >= MAX_ATTEMPTS
      or (battles >= MAX_BATTLES and not H.battleLoadStarted())
  end, 400000, round(), "rounds until an injected spin's turn comes up with nothing to run"),
}
steps[#steps + 1] = H.call(function()
  H.setPad({})
  local fails, ran, cancelled = {}, 0, 0
  for _, a in ipairs(attempts) do
    local c, d = a.commit, a.done
    if c and d and d.kind == "ran" then
      ran = ran + 1
      if not (d.p == 0 and d.b == c.b - c.p) then
        fails[#fails + 1] = string.format("attempt %d: a spin that ran (pending %d, bank %d) "
          .. "left pending %d, bank %d (want 0, %d)", a.n, c.p, c.b, d.p, d.b, c.b - c.p)
      end
    elseif c and d and d.kind == "cancelled" then
      cancelled = cancelled + 1
      local wantB = d.ko and c.b or math.min(c.b + 1, 5)
      if not (d.p == 0 and d.b == wantB) then
        fails[#fails + 1] = string.format("attempt %d: a spin that never ran (no-action mark "
          .. "set, pending %d, bank %d at its commit, %s at its end) left pending %d, bank %d "
          .. "(want 0, %d: nothing charged, %s)", a.n, c.p, c.b,
          d.ko and "out of the fight" or "in the fight", d.p, d.b, wantB,
          d.ko and "no regen out of the fight" or "the unboosted regen")
      end
      if not d.ko and not (a.sleptF ~= nil and a.sleptF <= d.f) then
        fails[#fails + 1] = string.format("attempt %d: the turn came up marked with him in the "
          .. "fight but no Sleep applied before it (injected %s)", a.n, tostring(a.injected ~= nil))
      end
    end
  end
  H.log(string.format("[cancel] SUMMARY battles=%d attempts=%d ran(boosted)=%d " ..
    "cancelled(boosted)=%d", battles, #attempts, ran, cancelled))
  for _, f in ipairs(fails) do H.log("[cancel] FAIL " .. f) end
  H.assertEq(#fails, 0, "every attempt's books: a spin that ran paid its tier, a spin " ..
    "that never ran cost nothing and took the in-the-fight regen (#346)")
  H.assertEq(ctlDone, true, "precondition: the control -- a boosted spin of his ran")
  local c, d = ctl.commit, ctl.done
  H.assertEq(d.p == 0 and d.b == c.b - c.p, true, string.format("the control: a boosted " ..
    "spin that ran paid its tier: pending %d -> %d (want 0), bank %d -> %d (want %d)",
    c.p, d.p, c.b, d.b, c.b - c.p))
  H.assertEq(found(), true, string.format("precondition: an injected attempt's boosted spin " ..
    "came up with nothing to run below bank 5, within %d attempts (%d marked in all)",
    MAX_ATTEMPTS, cancelled))
end)

H.run({ maxFrames = 400000 }, steps)
