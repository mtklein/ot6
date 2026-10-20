-- @suite slow savestate=gau_joined
-- battle_ragefizzle.lua -- a boosted Rage start that cannot pay at resolve
-- costs nothing: no MP, no pips (#330, the Dance stumble's shape, #313).
--
-- The Rage window refuses a pick Gau cannot pay (#225), so an unpayable start
-- is reached only when the pool moves between the commit and the resolve
-- (an enemy's Rasp or Osmose landing in the advance wait).  Ot6RageStartGate
-- then sends Cmd_10 to the plain exec: no RAGE status, no beast flag, and
-- CalcAttackEffect's universal fizzle refuses the cast, so no MP leaves the
-- pool.  The pips are another matter: the boost was raised for the
-- possession's coin and no possession began, and Ot6ActionEnd still found the
-- pending boost and spent it.  Ot6RageStartGate now drops the pending boost
-- on its refusal, as Ot6DanceStumble does for a stumbled dance, so the turn
-- ends as an unboosted one: pool untouched, nothing pending, the regen pip
-- banked.
--
-- The run is the Veldt battle of battle_ragerefuse and battle_gaufight (the
-- bench of SABIN and CYAN cycling their windows, Gau at his own).  The first
-- command window is snapshotted and branched BRANCHES times, each branch its
-- own idle length and its own draw.  Every branch raises one pip with R,
-- opens the rage window on entry 0 and commits.  Even branches are the
-- control: nothing is touched and the start must pay the flat price, start
-- the trance and spend the pip.  Odd branches carry the file's one state
-- write (tools/state_write_waivers.txt): the moment the commit is queued, the
-- pool is set one under the flat price, what a drain in the advance wait
-- leaves, because no fixture holds an MP-draining enemy at this point.
-- Observed, never written: Ot6ActionEnd's pending boost, bank, pool and the
-- RAGE status at Gau's start turn, and his bank 20 frames later.
-- Asserted per branch whose start turn resolved:
--   control  the flat price charged, RAGE set, pip spent (pending 1 at the
--            turn's end, bank one down);
--   drained  the pool untouched, no RAGE, nothing pending at the turn's end,
--            the bank one pip up (capped at 5): the unboosted turn's regen;
-- and across branches: at least MIN_EACH of each kind resolved.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/gau_joined.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_TRANS, ST_CMD, ST_RAGE, ST_TGT = 0x01, 0x05, 0x1E, 0x38
local CMDTBL = 0x202E
local CMD_RAGE = 0x10
local RAGELIST = 0x257E
local RSCROLL, RCOL, RROW = 0x892B, 0x892F, 0x8933
local QCMD = 0x3A7A
local GAU = 0x0B
local BOOST = 1                          -- the pip every character opens with
local BRANCHES, MIN_EACH = 8, 3

local function bp(s) return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function mp(s) return H.readWord(0x3C08 + s * 2) end
local function raging(s) return (H.readByte(0x3EF9 + s * 2) & 0x01) ~= 0 end

-- the flat price, read off the ROM as battle_ragerefuse reads it
local RAGE_COST
do
  local dance = H.sym("Ot6DanceCost")
  H.assertEq(H.readRomByte(dance & 0x3FFFFF), 0xa9,
    "Ot6DanceCost still opens with LDA #imm -- the +1 read is the price")
  RAGE_COST = H.readRomByte((dance & 0x3FFFFF) + 1)
end

local gau = nil
local ph = 0
local want = { mode = "idle", boost = 0 }
local rec = nil
local recs = {}

local function cmdCellOf(slot, cmd)
  for i = 0, 3 do
    if H.readByte(CMDTBL + slot * 12 + i * 3) == cmd then return i end
  end
  return nil
end

local function field()
  local mons = {}
  for m = 0, 5 do
    if H.readByte(0x3AA8 + m * 2) % 2 == 1 then
      mons[#mons + 1] = tostring(H.readWord(0x3BFC + m * 2))
    end
  end
  return "monster hp " .. table.concat(mons, " ")
end

-- the per-frame hands: Gau follows want.mode; the bench X-cycles
local function pulse()
  ph = ph + 1
  local edge = ph % 10 < 5
  if H.readByte(MENU) == 0 then
    H.setPad(ph % 8 < 4 and { a = true } or {})
    return
  end
  local a, st = H.readByte(ACTOR) & 3, H.readByte(MSTATE)
  if st == ST_TRANS then H.setPad({}) return end
  if a ~= gau then
    H.setPad((ph % 8 < 4) and { [(st == ST_CMD) and "x" or "b"] = true } or {})
    return
  end
  local btn
  if want.mode == "idle" or want.mode == "defer" then
    H.setPad({})
    return
  elseif st == ST_CMD then
    if pend(gau) ~= want.boost then
      btn = (pend(gau) < want.boost) and "r" or "l"
    else
      local cell = cmdCellOf(a, CMD_RAGE)
      assert(cell, "GAU's command list carries RAGE")
      local cur = H.readByte(CMDROW + a) & 3
      btn = (cur == cell) and "a" or ((cur < cell) and "down" or "up")
    end
  elseif st == ST_RAGE then
    if H.readByte(RCOL + gau) > 0 then btn = "left"
    elseif H.readByte(RSCROLL + gau) + H.readByte(RROW + gau) > 0 then btn = "up"
    else btn = "a" end
  elseif st == ST_TGT then
    btn = "a"
  else
    btn = "b"
  end
  H.setPad((edge and btn) and { [btn] = true } or {})
end

local function step(what, cond, budget)
  return H.driveUntil(cond, budget or 20000,
    { H.call(pulse), H.waitFrames(1) }, what)
end

local function gauCommandWindow(what)
  return step(what, function()
    return H.battleLoadStarted() and H.readByte(MENU) ~= 0
       and (H.readByte(ACTOR) & 3) == gau and H.readByte(MSTATE) == ST_CMD
  end)
end

-- ------------------------------------------------------------ observers --
local function installObservers()
  -- the commit: CreateAction's store of GAU's rage into the cost queue
  emu.addMemoryCallback(function()
    if not (rec and gau) or rec.queued then return end
    if H.readByte(QCMD) ~= CMD_RAGE then return end
    rec.queued = { f = H.frame, mp = mp(gau), pend = pend(gau) }
  end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
  -- the turn's end, where the pending boost is spent or dropped
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if not (rec and rec.queued) or rec.done then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= gau * 2 then return end
    if H.readByte(0x3A7C) ~= CMD_RAGE then return end
    rec.done = { f = H.frame, pend = pend(gau), bank = bp(gau),
                 mp = mp(gau), raging = raging(gau) }
  end, emu.callbackType.exec, ae, ae)
end

local snap = nil
local function branch(k)
  local req
  local drain = (k % 2 == 1)
  return H.cond(function() return true end, {
    H.call(function()
      H.setPad({})
      rec = nil
      req = H.requestLoadState(snap.blob)
    end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load (branch " .. k .. ")")
      H.rearmInputInjection()
      rec = { k = k, drain = drain }
      recs[#recs + 1] = rec
      want.mode, want.boost = "idle", BOOST
      H.log(string.format("[ragefizzle] branch %d (%s): %d idle frames at "
        .. "GAU's window", k, drain and "drained" or "control", (k - 1) * 9))
    end),
    H.waitFrames((k - 1) * 9 + 1),
    H.call(function()
      rec.bank0, rec.mp0 = bp(gau), mp(gau)
      want.mode = "press"
    end),
    -- the commit; on a drained branch the pool is set under the price the
    -- frame the commit is queued
    step("GAU commits a boosted rage", function()
      return rec.queued ~= nil
    end, 3000),
    H.call(function()
      rec.pend0 = rec.queued.pend
      if drain then
        H.writeWord(0x3C08 + gau * 2, RAGE_COST - 1)
        H.log(string.format("[ragefizzle] branch %d: queued f%d pending %d "
          .. "bank %d, pool %d -> %d (synthetic drain)", k, rec.queued.f,
          rec.pend0, rec.bank0, rec.mp0, mp(gau)))
      else
        H.log(string.format("[ragefizzle] branch %d: queued f%d pending %d "
          .. "bank %d pool %d; %s", k, rec.queued.f, rec.pend0, rec.bank0,
          rec.mp0, field()))
      end
      want.mode = "defer"
    end),
    H.driveUntil(function()
      if not H.battleLoadStarted() then return true end
      if rec.done and H.frame >= rec.done.f + 20 then
        rec.after = { bank = bp(gau), mp = mp(gau), raging = raging(gau) }
        return true
      end
      return false
    end, 6000, {
      H.call(function()
        ph = ph + 1
        if not H.battleLoadStarted() then H.setPad({}) return end
        if H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) == gau then
          H.setPad({})
        else
          pulse()
        end
      end),
      H.waitFrames(1),
    }, "GAU's rage start turn resolves"),
    H.call(function()
      local d, a = rec.done, rec.after
      if not (d and a) then
        H.log(string.format("[ragefizzle] branch %d: the fight ended before "
          .. "the start turn resolved (no outcome)", k))
        return
      end
      H.log(string.format("[ragefizzle] branch %d %s: commit pending %d bank "
        .. "%d pool %d | turn end f%d pending %d bank %d pool %d raging=%s "
        .. "| +20f bank %d pool %d raging=%s", k, drain and "DRAINED" or
        "CONTROL", rec.pend0, rec.bank0, rec.mp0, d.f, d.pend, d.bank, d.mp,
        tostring(d.raging), a.bank, a.mp, tostring(a.raging)))
    end),
  })
end

local body = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 6000, "world control on the Veldt"),
  H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.call(function()
      if H.battleLoadStarted() or not H.worldHasControl() then H.setPad({}) return end
      if not H.worldAligned() then return end
      ph = ph + 1
      H.setPad({ [(ph % 2 == 0) and "left" or "right"] = true })
    end),
  }, "a Veldt encounter fires"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 1200, "battle armed", 5),
  H.waitFrames(90),
  H.call(function()
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) == GAU then gau = s end
    end
    H.assertEq(gau ~= nil, true, "GAU is in this party")
    H.assertEq(cmdCellOf(gau, CMD_RAGE) ~= nil, true, "...with a RAGE row")
    H.assertEq(mp(gau) >= RAGE_COST, true, string.format(
      "GAU's real pool (%d) can pay the flat %d", mp(gau), RAGE_COST))
    installObservers()
  end),
  gauCommandWindow("GAU's command window"),
  H.call(function()
    H.setPad({})
    H.assertEq(bp(gau) >= BOOST, true, "GAU holds the pip every character opens with")
    snap = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap, "snapshot at GAU's window") end),
}
for k = 1, BRANCHES do body[#body + 1] = branch(k) end
body[#body + 1] = H.call(function()
  H.setPad({})
  local nC, nD = 0, 0
  for _, r in ipairs(recs) do
    local d, a = r.done, r.after
    if d and a then
      if r.drain then
        nD = nD + 1
        H.assertEq(d.mp, RAGE_COST - 1, string.format(
          "branch %d (drained): no MP charged for a start that could not pay", r.k))
        H.assertEq(d.raging, false, string.format(
          "branch %d (drained): no trance began", r.k))
        H.assertEq(d.pend, 0, string.format(
          "branch %d (drained): the pending boost was dropped, not spent "
          .. "(it read %d at the turn's end)", r.k, d.pend))
        H.assertEq(a.bank, math.min(5, r.bank0 + 1), string.format(
          "branch %d (drained): bank %d -> %d (want %d: no spend, the "
          .. "unboosted turn's regen)", r.k, r.bank0, a.bank,
          math.min(5, r.bank0 + 1)))
      else
        nC = nC + 1
        H.assertEq(d.raging, true, string.format(
          "branch %d (control): the paid start began the trance", r.k))
        H.assertEq(d.mp, r.mp0 - RAGE_COST, string.format(
          "branch %d (control): the flat %d charged", r.k, RAGE_COST))
        H.assertEq(d.pend, r.pend0, string.format(
          "branch %d (control): the pip still pending at the turn's end", r.k))
        H.assertEq(a.bank, r.bank0 - r.pend0, string.format(
          "branch %d (control): the pip spent", r.k))
      end
    end
  end
  H.log(string.format("[ragefizzle] SUMMARY branches=%d control=%d drained=%d "
    .. "(boost %d, flat price %d)", #recs, nC, nD, BOOST, RAGE_COST))
  H.assertEq(nC >= MIN_EACH, true, "enough control branches resolved")
  H.assertEq(nD >= MIN_EACH, true, "enough drained branches resolved")
end)
H.run({ maxFrames = 120000 }, body)
