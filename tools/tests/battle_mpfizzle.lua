-- @suite slow savestate=wor_tritoch
-- battle_mpfizzle.lua -- a boosted action that fails for lack of MP keeps its
-- boost points (#450; the Rage case was #330, battle_ragefizzle).
--
-- A boosted Magic cast or Dance start whose caster cannot pay at resolve is
-- refused by CalcAttackEffect's universal MP check: no MP leaves the pool and
-- nothing happens.  The pips raised for it were only pending, and
-- Ot6ActionEnd used to spend them on the cast that never happened.  Now the
-- refusal drops the pending boost (Ot6FizzleDropBoost, one place for every
-- costed verb; Ot6DanceStartGate's refusal is not special), so the turn ends
-- as an unboosted one: pool untouched, nothing pending, the regen pip banked.
--
-- The menus refuse an unpayable pick (the grey row's confirm buzzes), so an
-- unpayable action reaches resolve only when the pool moves between the
-- commit and the resolve (an enemy's Rasp or Osmose in the advance wait).
-- No fixture holds an MP-draining enemy here, so the drained branches carry
-- the file's one state write (tools/state_write_waivers.txt): the moment the
-- commit is queued, the caster's pool is set to 1, what a drain leaves.
--
-- The run is the World of Ruin party of wor_tritoch (UMARO, MOG, TERRA,
-- CELES) in a world-map encounter.  The battle's first frame is snapshotted;
-- for each verb the snapshot is loaded and driven to the caster's window
-- (the others Defend), snapshotted again, and branched BRANCHES times, each
-- branch its own idle length (its own draw).  Odd branches are drained; even
-- branches are the control and pay.  Every branch raises one pip with R, opens
-- the verb's list and commits its first affordable entry (Magic: the first
-- lit row; Dance: the encounter background's own dance when MOG knows it,
-- else his lowest known).  Observed, never written: the harness's own
-- [fizzle] note (lib/ot6.lua fizzleNote: asked= the pending pips at ExecCmd,
-- boost= what was still pending after the body), Ot6ActionEnd's pending boost,
-- bank and pool, and the bank 20 frames later.
-- Asserted per branch whose start turn resolved:
--   drained  the fizzle was noted, the pool untouched, nothing pending at the
--            turn's end (and the note's boost= 0), no dance began, the bank
--            one pip up (capped at 5): the unboosted turn's regen;
--   control  no fizzle, the listed (Magic) or boosted (Dance) price charged,
--            the pip pending at the turn's end and spent: bank one down.  A
--            dance that stumbled off its terrain is neither (#313,
--            battle_dancestumble) and is not counted;
-- and across branches: at least MIN_EACH of each kind resolved, per verb.
--
-- X-Magic queues two spells on one pending boost, both folded to the boosted
-- tier at the commit, and its turn ends once, after the second.  So the boost
-- goes with the turn's last spell: a first spell refused with a second still
-- to cast keeps it for the second.  No fixture holds a Gem Box this early, so
-- a second declared write (the battle_mimic expedient) turns the Magic
-- caster's third command (Morph or Runic) into X-Magic in the field record
-- before the encounter; battle init builds the battle's menus from it.  The
-- X-Magic caster commits two different lit rows, the dearer first (A, then
-- B), that the pool pays together, and its branches take four kinds in turn:
--   control  both spells charged their queued prices; the pip spent;
--   first    the pool set to B's price at the commit: A refused, B cast at
--            the id and price it was queued at; the pip pending at the
--            turn's end and spent;
--   second   the pool set under B's price once A has cast: A charged, B
--            refused; the pip spent (it bought A);
--   both     the pool set under B's price at the commit: both refused,
--            nothing pending at the turn's end, the bank one pip up.
-- At least one of each kind resolved.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_tritoch.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_TRANS, ST_CMD, ST_MAGIC, ST_DANCE, ST_TGT = 0x01, 0x05, 0x0E, 0x21, 0x38
local ST_DEF = 0x27
local CMDTBL = 0x202E
local CMD_MAGIC, CMD_DANCE, CMD_XMAGIC = 0x02, 0x13, 0x17
local XKINDS = { "control", "first", "second", "both" }
-- the spell list and its two scroll states (ScrollMagicListDown/Up)
local XLIST = { [0x0E] = true, [0x17] = true, [0x18] = true }
local MLISTPTR = 0x302C
local QCMD = 0x3A7A
local MOG = 0x0A
local DANCES = 0x1D4C
local BOOST = 1
local BRANCHES, MIN_EACH = 8, 3
-- The encounter is whatever the world deals (#454).  One where the caster
-- falls before a branch's turn resolves (the Mantodea, formation group
-- $0143, killed MOG inside every Dance branch on v0.34's first chain) or
-- that ends before it yields no outcome for that branch; a verb still
-- short of its counts after an encounter's branches goes on to the next
-- encounter: the world map before this one is restored, this one is fought
-- out by the walker, the party is cared for, and the next one is walked
-- into.  At most MAX_ENCOUNTERS.
local MAX_ENCOUNTERS = 4

local function bp(s) return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function mp(s) return H.readWord(0x3C08 + s * 2) end
local function dancing(s) return (H.readByte(0x3EF8 + s * 2) & 0x01) ~= 0 end
-- why slot s's turn can no longer come in this battle, or nil: the battle
-- ended, or s is down (no HP, or Wound / Petrify / Zombie in STATUS1)
local function lostWhy(s)
  if not H.battleLoadStarted() then return "the battle ended" end
  local hp, st1 = H.readWord(0x3BF4 + s * 2), H.readByte(0x3EE4 + s * 2)
  if hp == 0 or (st1 & 0xC2) ~= 0 then
    return string.format("slot %d is down (HP %d, STATUS1 $%02X)", s, hp, st1)
  end
  return nil
end
-- the file's one pool write (see the header): what a drain leaves
local function drainTo(s, v) H.writeWord(0x3C08 + s * 2, v) end

local function cmdCellOf(slot, cmd)
  for i = 0, 3 do
    if H.readByte(CMDTBL + slot * 12 + i * 3) == cmd then return i end
  end
  return nil
end

local ph = 0
local xChar = nil                   -- the X-Magic caster's character id
local snap0, snap = nil, nil
local enc, encs, phaseLost = 0, {}, nil   -- the encounter in use, each one's snapshots
local V = nil                       -- the verb under test
local who = nil                     -- its caster's slot
local rec, recs = nil, {}
local want = "idle"                 -- idle | press | defer

-- the bystanders' hands: Defend from the command window, page dialogs
local function bystander()
  local st = H.readByte(MSTATE)
  local step = ph % 40
  if st == ST_DEF then H.setPad(ph % 10 < 5 and { a = true } or {})
  elseif st ~= ST_CMD then H.setPad(ph % 10 < 5 and { b = true } or {})
  elseif step < 4 then H.setPad({ right = true })      -- Fight -> Def
  elseif step >= 20 and step < 24 then H.setPad({ a = true })
  else H.setPad({}) end
end

local function listEntry(a, cell)
  local base = H.readWord(MLISTPTR + a * 2)
  if base < 0x2000 or base > 0x2600 then return nil end
  local at = base + (cell + 1) * 4
  return H.readByte(at), H.readByte(at + 1), H.readByte(at + 3)
end

-- the first lit Magic row the pool pays at the raised boost
local function magicCell(a)
  for cell = 0, 53 do
    local id, flags, cost = listEntry(a, cell)
    if id == nil then return nil end
    if id ~= 0xFF and (flags & 0x80) == 0 and cost > 0 and mp(a) >= cost then
      return cell, id, cost
    end
  end
  return nil
end

-- X-Magic's two picks: B the cheapest lit row, A the dearest lit row dearer
-- than B that the pool pays together with B
local function xPicks(a)
  local rows = {}
  for cell = 0, 53 do
    local id, flags, cost = listEntry(a, cell)
    if id == nil then break end
    if id ~= 0xFF and (flags & 0x80) == 0 and cost > 0 then
      rows[#rows + 1] = { cell = cell, id = id, cost = cost }
    end
  end
  local A, B = nil, nil
  for _, r in ipairs(rows) do if B == nil or r.cost < B.cost then B = r end end
  for _, r in ipairs(rows) do
    if B and r.cost > B.cost and r.cost + B.cost <= mp(a)
       and (A == nil or r.cost > A.cost) then A = r end
  end
  return A, B
end

local function steerTo(a, cell)
  local wantRow, wantCol = cell // 2, cell % 2
  local absRow = H.readByte(0x8913 + a) + H.readByte(0x891B + a)
  local col = H.readByte(0x8917 + a)
  if absRow ~= wantRow then return (absRow < wantRow) and "down" or "up" end
  if col ~= wantCol then return (col < wantCol) and "right" or "left" end
  return "a"
end

local danceId = nil
local function danceCost() return H.boostPrice(8, BOOST) end

-- the hands of the caster for the live verb: R to the boost, open the list,
-- park on the entry, confirm (and the target)
local function pulse()
  ph = ph + 1
  local edge = ph % 10 < 5
  if H.readByte(MENU) == 0 then
    H.setPad(ph % 8 < 4 and { a = true } or {})
    return
  end
  local a, st = H.readByte(ACTOR), H.readByte(MSTATE)
  if st == ST_TRANS then H.setPad({}) return end
  if a ~= who then bystander() return end
  if want ~= "press" then H.setPad({}) return end
  local btn
  if st == ST_CMD then
    if pend(who) ~= BOOST then
      btn = (pend(who) < BOOST) and "r" or "l"
    else
      local cell = cmdCellOf(a, V.cmd)
      assert(cell, "the caster's command list carries the verb")
      local cur = H.readByte(CMDROW + a) & 3
      btn = (cur == cell) and "a" or ((cur < cell) and "down" or "up")
    end
  elseif st == ST_MAGIC and V.cmd == CMD_MAGIC then
    local cell, id, cost = magicCell(a)
    assert(cell, "the caster has a lit Magic row the pool pays at the boost")
    btn = steerTo(a, cell)
    if btn == "a" then rec.spell, rec.price = id, cost end
  elseif XLIST[st] and V.cmd == CMD_XMAGIC then
    if rec.picks == nil then
      local A, B = xPicks(a)
      assert(A and B, "the X-Magic caster has two lit rows, one dearer, that "
        .. "the pool pays together")
      rec.picks, rec.pi = { A, B }, 1
      H.log(string.format("[mpfizzle] X-Magic picks: A $%02X (%d MP), B $%02X "
        .. "(%d MP), pool %d", A.id, A.cost, B.id, B.cost, mp(a)))
    end
    -- back in the list after a pick was taken: the next pick
    if not XLIST[rec.lastSt or 0] and rec.pressed == rec.pi then rec.pi = rec.pi + 1 end
    local p = rec.picks[rec.pi]
    if p then
      btn = steerTo(a, p.cell)
      if btn == "a" then rec.pressed = rec.pi end
    end
  elseif st == ST_DANCE and V.cmd == CMD_DANCE then
    local row, col = danceId // 2, danceId % 2
    local cr, cc = H.readByte(0x893B + a), H.readByte(0x8937 + a)
    if cr ~= row then btn = (cr < row) and "down" or "up"
    elseif cc ~= col then btn = (cc < col) and "right" or "left"
    else rec.price = danceCost(); btn = "a" end
  elseif st == ST_TGT then
    btn = "a"
  elseif V.cmd == CMD_XMAGIC and rec.pressed then
    -- between X-Magic's picks the menu passes through its own states: wait
    if st ~= rec.lastSt then
      H.log(string.format("[mpfizzle] X-Magic menu state $%02X after pick %d", st, rec.pressed))
    end
  else
    btn = "b"
  end
  rec.lastSt = st
  H.setPad((edge and btn) and { [btn] = true } or {})
end

local function step(what, cond, budget)
  return H.driveUntil(cond, budget or 20000,
    { H.call(pulse), H.waitFrames(1) }, what)
end

local function window(what)
  return step(what, function()
    return H.battleLoadStarted() and H.readByte(MENU) ~= 0
       and H.readByte(ACTOR) == who and H.readByte(MSTATE) == ST_CMD
  end)
end

-- ------------------------------------------------------------ observers --
local function installObservers()
  emu.addMemoryCallback(function(addr, v)
    if not (rec and V) or rec.spells then return end
    local q = H.readByte(QCMD)
    -- an X-Magic queues its first spell as Magic ($02), its second as $17
    local xfirst = V.cmd == CMD_XMAGIC and q == CMD_MAGIC
      and (emu.getState()["cpu.x"] & 0xFF) == who * 2
    if q ~= V.cmd and not xfirst then return end
    -- the queued price and attack id, per queue slot (the fold's write last)
    rec.qw = rec.qw or {}
    rec.qw[#rec.qw + 1] = { addr = addr & 0xFFFF, v = v, id = H.readByte(0x3A7B),
                            cmd = q }
    if rec.queued or xfirst then return end
    rec.queued = { f = H.frame, mp = mp(who), pend = pend(who),
                   fz = H.fizzles.n }
  end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
  -- each spell of an X-Magic as its body ends: what ran, and the pool
  local sfm = H.sym("SaveForMimic")
  emu.addMemoryCallback(function()
    if not (rec and rec.queued and V and V.cmd == CMD_XMAGIC) or rec.done then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= who * 2 then return end
    rec.spells = rec.spells or {}
    rec.spells[#rec.spells + 1] = { f = H.frame, cmd = H.readByte(0x3A7C),
      atk = H.readByte(0x3A7D), mp = mp(who), pend = pend(who) }
  end, emu.callbackType.exec, sfm, sfm)
  -- what the refusal sees: the next list entry, $3406, the refusal mark
  local fd = H.sym("Ot6FizzleDropBoost")
  emu.addMemoryCallback(function()
    if not (rec and rec.queued) or rec.done then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= who * 2 then return end
    H.log(string.format("[mpfizzle] refusal f%d: next entry $32cc=$%02X $3406=$%02X "
      .. "mark=$%02X pending %d", H.frame, H.readByte(0x32CC + who * 2),
      H.readByte(0x3406), H.readByte(0xEE20), pend(who)))
  end, emu.callbackType.exec, fd, fd)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if not (rec and rec.queued) or rec.done then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= who * 2 then return end
    local c = H.readByte(0x3A7C)
    if c ~= V.cmd and not (V.cmd == CMD_XMAGIC and c == CMD_MAGIC) then return end
    local note = H.fizzles.rows[#H.fizzles.rows]
    rec.done = { f = H.frame, pend = pend(who), bank = bp(who), mp = mp(who),
                 dancing = dancing(who), fizzled = H.fizzles.n > rec.queued.fz,
                 nfz = H.fizzles.n - rec.queued.fz,
                 note = (H.fizzles.n > rec.queued.fz) and note or nil }
  end, emu.callbackType.exec, ae, ae)
end

local function branch(k, verb)
  local req
  local drain = (k % 2 == 1)
  local kind = (verb.cmd == CMD_XMAGIC) and XKINDS[(k - 1) % #XKINDS + 1] or nil
  if kind then drain = (kind ~= "control") end
  return H.cond(function() return not phaseLost end, {
    H.call(function()
      H.setPad({})
      rec = nil
      req = H.requestLoadState(snap.blob)
    end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load (branch " .. k .. ")")
      H.rearmInputInjection()
      rec = { k = k, drain = drain, verb = V.name, kind = kind }
      recs[#recs + 1] = rec
      want = "idle"
      H.log(string.format("[mpfizzle] %s branch %d (%s): %d idle frames at "
        .. "the caster's window", V.name, k, kind or (drain and "drained" or "control"),
        (k - 1) * 9))
    end),
    H.waitFrames((k - 1) * 9 + 1),
    H.call(function()
      rec.bank0, rec.mp0 = bp(who), mp(who)
      want = "press"
    end),
    step("the caster commits, boosted", function()
      if rec.queued ~= nil then return true end
      rec.lost = lostWhy(who)
      return rec.lost ~= nil
    end, 3000),
    H.call(function()
      if rec.lost then return end
      rec.pend0 = rec.queued.pend
      -- the property needs a raised boost to keep or drop: assert it was raised
      H.assertEq(rec.pend0, BOOST, string.format(
        "%s branch %d: the commit queued with the boost raised", V.name, k))
      if kind then
        local cb = rec.picks[2].cost
        if kind == "first" then drainTo(who, cb)
        elseif kind == "both" then drainTo(who, cb - 1) end
        H.log(string.format("[mpfizzle] %s branch %d (%s): queued f%d pending "
          .. "%d bank %d, pool %d -> %d%s", V.name, k, kind, rec.queued.f,
          rec.pend0, rec.bank0, rec.mp0, mp(who),
          (kind == "first" or kind == "both") and " (synthetic drain)" or ""))
      elseif drain then
        drainTo(who, 1)
        H.log(string.format("[mpfizzle] %s branch %d: queued f%d pending %d "
          .. "bank %d, pool %d -> %d (synthetic drain)", V.name, k,
          rec.queued.f, rec.pend0, rec.bank0, rec.mp0, mp(who)))
      else
        H.log(string.format("[mpfizzle] %s branch %d: queued f%d pending %d "
          .. "bank %d pool %d", V.name, k, rec.queued.f, rec.pend0, rec.bank0,
          rec.mp0))
      end
      want = "defer"
    end),
    H.driveUntil(function()
      if rec.lost then return true end
      if not H.battleLoadStarted() then return true end
      if rec.done and H.frame >= rec.done.f + 20 then
        rec.after = { bank = bp(who), mp = mp(who), dancing = dancing(who) }
        return true
      end
      -- the caster down before its turn resolved: that turn never comes
      if not rec.done then rec.lost = lostWhy(who) end
      return rec.lost ~= nil
    end, 6000, {
      H.call(function()
        ph = ph + 1
        if not H.battleLoadStarted() then H.setPad({}) return end
        -- the second kind's drain: once A's body has ended, before B's
        if rec.kind == "second" and rec.spells and #rec.spells == 1
           and not rec.drained2 then
          rec.drained2 = { f = H.frame, from = mp(who) }
          drainTo(who, rec.picks[2].cost - 1)
          H.log(string.format("[mpfizzle] %s branch %d (second): A's body ended "
            .. "f%d, pool %d -> %d (synthetic drain)", V.name, k,
            rec.spells[1].f, rec.drained2.from, mp(who)))
        end
        if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == who then
          H.setPad({})
        else
          pulse()
        end
      end),
      H.waitFrames(1),
    }, "the start turn resolves"),
    H.call(function()
      local d, a = rec.done, rec.after
      if rec.lost then
        H.log(string.format("[mpfizzle] %s branch %d (encounter %d): %s before "
          .. "the turn resolved (no outcome)", V.name, k, enc, rec.lost))
        return
      end
      if not (d and a) then
        H.log(string.format("[mpfizzle] %s branch %d: the fight ended before "
          .. "the turn resolved (no outcome)", V.name, k))
        return
      end
      local sp = {}
      for i, e in ipairs(rec.spells or {}) do
        sp[#sp + 1] = string.format("spell%d f%d cmd $%02X atk $%02X pool %d "
          .. "pending %d", i, e.f, e.cmd, e.atk, e.mp, e.pend)
      end
      H.log(string.format("[mpfizzle] %s branch %d %s: commit pending %d bank "
        .. "%d pool %d | turn end f%d pending %d bank %d pool %d fizzled=%s "
        .. "(%d) dancing=%s | +20f bank %d pool %d%s%s", V.name, k,
        kind and kind:upper() or (drain and "DRAINED" or "CONTROL"), rec.pend0,
        rec.bank0, rec.mp0, d.f, d.pend, d.bank, d.mp, tostring(d.fizzled),
        d.nfz, tostring(d.dancing), a.bank, a.mp,
        #sp > 0 and (" | " .. table.concat(sp, "; ")) or "",
        d.note and ("\n[mpfizzle] note: " .. d.note) or ""))
    end),
  })
end

-- one verb: back to the battle's first frame, to the caster's window, branch
local function phase(verb, pick)
  local req
  local out = {
    H.call(function()
      H.setPad({}); rec = nil; want = "idle"
      V = verb
      req = H.requestLoadState(snap0.blob)
    end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "battle-start snapshot load (" .. verb.name .. ")")
      H.rearmInputInjection()
      who = pick()
      danceId = nil
      if verb.cmd == CMD_DANCE then
        local mask = H.readByte(DANCES)
        local terrain = H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF)
          + H.readByte(0x11E2))
        if mask & (1 << terrain) ~= 0 then danceId = terrain
        else
          for d = 0, 7 do
            if mask & (1 << d) ~= 0 then danceId = d; break end
          end
        end
        H.assertEq(danceId ~= nil, true, "MOG knows a dance")
        H.log(string.format("[mpfizzle] dance %d (terrain %d, known mask %02X)",
          danceId, terrain, mask))
      end
      H.log(string.format("[mpfizzle] %s: caster slot %d, %d MP, %d BP",
        verb.name, who, mp(who), bp(who)))
    end),
    step(verb.name .. " caster's command window", function()
      if H.battleLoadStarted() and H.readByte(MENU) ~= 0
         and H.readByte(ACTOR) == who and H.readByte(MSTATE) == ST_CMD then return true end
      phaseLost = lostWhy(who)
      return phaseLost ~= nil
    end),
    H.cond(function() return phaseLost == nil end, {
      H.call(function()
        H.setPad({})
        H.assertEq(bp(who) >= BOOST, true, "the caster holds the opening pip")
        snap = H.requestSaveState()
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(snap, "snapshot at the caster's window") end),
    }, {
      H.call(function()
        H.log(string.format("[mpfizzle] %s (encounter %d): %s before the caster's "
          .. "first window: no branch here", verb.name, enc, phaseLost))
      end),
    }),
  }
  for k = 1, BRANCHES do out[#out + 1] = branch(k, verb) end
  return H.seqStep(out)
end

local body = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 6000, "world control on the World of Ruin map"),
  H.call(function()
    -- the declared expedient (see the header): the Magic caster's third
    -- command becomes X-Magic in the field record, before battle init reads it
    local party = H.readByte(0x1A6D) & 7
    for _, c in ipairs({ 0x00, 0x06 }) do
      if (H.readByte(0x1850 + c) & 7) == party and xChar == nil then
        for r = 1, 3 do
          local at = 0x1600 + 37 * c + 0x16 + r
          local v = H.readByte(at)
          if xChar == nil and v ~= 0x00 and v ~= 0x01 and v ~= CMD_MAGIC then
            xChar = c
            H.writeByte(at, CMD_XMAGIC)
            H.log(string.format("[mpfizzle] EXPEDIENT: char %d command row %d "
              .. "$%02X -> $17 (X-Magic)", c, r, v))
          end
        end
      end
    end
    assert(xChar, "TERRA or CELES is in the party with a third command")
  end),
}

-- the walk into an encounter: battle_gaufight's, alternating left/right at
-- tile boundaries until the world's own encounter roll wins
local function walkIn()
  return H.seqStep({
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        if H.battleLoadStarted() or not H.worldHasControl() then H.setPad({}) return end
        if not H.worldAligned() then return end
        ph = ph + 1
        H.setPad({ [(ph % 2 == 0) and "left" or "right"] = true })
      end),
      H.waitFrames(1),
    }, "a world-map encounter fires"),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 1200, "battle armed", 5),
    H.waitFrames(240),
  })
end

local function worldControl(what)
  return H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 6000, what)
end

-- the walker fights the encounter the world map holds next, from here
local function fightThrough(what)
  local o0, wp, W = nil, 1, nil
  return H.withReset(H.driveUntil(function()
    return o0 ~= nil and #H.outcomes > o0
  end, 200000, {
    H.call(function()
      if o0 ~= nil then return end
      o0 = #H.outcomes
      local x, y = H.worldX(), H.worldY()
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if W == nil and H.worldPassable(x + d[1], y + d[2]) then W = { { x + d[1], y + d[2] }, { x, y } } end
      end
      assert(W, "a walkable tile beside the party")
    end),
    H.worldNavTo(function() return W[wp][1] end, function() return W[wp][2] end,
      { maxFrames = 20000, playBattles = "tactical" }),
    H.call(function() wp = wp % #W + 1 end),
  }, what), function() o0, wp, W = nil, 1, nil end)
end

-- encounter e, made once: from encounter e-1's world map (restored, and
-- that encounter fought out by the walker), the party cared for, the world
-- map snapshotted, the walk in, the battle's first frame snapshotted
local observersOn = false
local function meet(e)
  local req
  return H.seqStep({
    H.cond(function() return encs[e] == nil end, {
      H.cond(function() return e > 1 end, {
        H.call(function()
          H.setPad({}); rec = nil; V = nil
          req = H.requestLoadState(encs[e - 1].world.blob)
        end),
        H.waitFrames(2),
        H.call(function()
          H.checkReq(req, "world-map snapshot load (encounter " .. (e - 1) .. ")")
          H.rearmInputInjection()
        end),
        worldControl("world control before encounter " .. (e - 1)),
        fightThrough("the walker fights encounter " .. (e - 1) .. " out"),
      }, {}),
      worldControl("world control before encounter " .. e),
      H.fieldCare({ tag = "care before encounter " .. e, threshold = H.CARE_BEFORE_FIGHTS }),
      worldControl("world control after the care (encounter " .. e .. ")"),
      H.call(function()
        for _, c in ipairs({ MOG, xChar }) do
          H.assertEq(H.charHp(c) > 0 and (H.charStatus1(c) & 0xC2) == 0, true, string.format(
            "encounter %d: char %d stands before the walk in (HP %d, STATUS1 $%02X)", e, c,
            H.charHp(c), H.charStatus1(c)))
        end
        encs[e] = { world = H.requestSaveState() }
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(encs[e].world, "world-map snapshot (encounter " .. e .. ")") end),
      walkIn(),
      H.call(function()
        if not observersOn then installObservers(); observersOn = true end
        H.setPad({})
        encs[e].start = H.requestSaveState()
      end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(encs[e].start, "battle-start snapshot (encounter " .. e .. ")")
        H.log(string.format("[mpfizzle] encounter %d: formation group $%04X", e, H.readWord(0x11E0)))
      end),
    }, {}),
    H.call(function() enc, snap0, phaseLost = e, encs[e].start, nil end),
  })
end

-- what a verb's resolved branches count so far, and whether it needs more
local function counts(name)
  local c = { c = 0, d = 0, control = 0, first = 0, second = 0, both = 0 }
  for _, r in ipairs(recs) do
    if r.verb == name and r.done and r.after then
      if r.kind then
        if #(r.spells or {}) == 2 then c[r.kind] = c[r.kind] + 1 end
      elseif r.drain then c.d = c.d + 1
      elseif not (name == "Dance" and not r.done.dancing) then c.c = c.c + 1 end
    end
  end
  return c
end
local function needs(name)
  local c = counts(name)
  if name == "XMagic" then
    for _, k in ipairs(XKINDS) do if c[k] < 1 then return true end end
    return false
  end
  return c.d < MIN_EACH or c.c < 1
end
local function verbPhases(verb, pick)
  local out = {}
  for e = 1, MAX_ENCOUNTERS do
    out[#out + 1] = H.cond(function() return needs(verb.name) end, {
      meet(e),
      phase(verb, pick),
    }, {})
  end
  return H.seqStep(out)
end

local function slotOfChar(c)
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) == c then return s end
  end
end
local function magicCaster()
  -- a mage of the party first (TERRA, CELES), else whoever has the row
  for _, c in ipairs({ 0x00, 0x06 }) do
    local s = slotOfChar(c)
    if s and cmdCellOf(s, CMD_MAGIC) then return s end
  end
  for s = 0, 3 do
    if cmdCellOf(s, CMD_MAGIC) then return s end
  end
end
body[#body + 1] = verbPhases({ name = "Magic", cmd = CMD_MAGIC }, function()
  local s = magicCaster()
  assert(s, "a party member with a Magic row")
  return s
end)
body[#body + 1] = verbPhases({ name = "XMagic", cmd = CMD_XMAGIC }, function()
  local s = slotOfChar(xChar)
  assert(s and cmdCellOf(s, CMD_XMAGIC), "the X-Magic caster's battle list has X-Magic")
  return s
end)
body[#body + 1] = verbPhases({ name = "Dance", cmd = CMD_DANCE }, function()
  local s = slotOfChar(MOG)
  assert(s, "MOG is in the party")
  assert(cmdCellOf(s, CMD_DANCE), "MOG's command list carries Dance")
  return s
end)
body[#body + 1] = H.call(function()
  H.setPad({})
  local n = { Magic = { c = 0, d = 0 }, Dance = { c = 0, d = 0 } }
  local nx = { control = 0, first = 0, second = 0, both = 0 }
  local fails = {}
  local function check(ok, msg) if not ok then fails[#fails + 1] = msg end end
  for _, r in ipairs(recs) do
    local d, a = r.done, r.after
    local sp = r.spells or {}
    if d and a and r.kind and #sp ~= 2 then
      H.log(string.format("[mpfizzle] %s branch %d (%s): %d spell bodies ended "
        .. "before the turn's end (no outcome)", r.verb, r.k, r.kind, #sp))
    elseif d and a and r.kind then
      local tag = string.format("%s branch %d (%s)", r.verb, r.k, r.kind)
      nx[r.kind] = nx[r.kind] + 1
      -- the two queue slots in the order they were queued, each's last write
      local order, last = {}, {}
      for _, w in ipairs(r.qw or {}) do
        if last[w.addr] == nil then order[#order + 1] = w.addr end
        last[w.addr] = w
      end
      check(#order == 2, string.format("%s: %d queue slots written (want 2)", tag, #order))
      local qa, qb = last[order[1]] or {}, last[order[2]] or {}
      local mp0 = r.queued.mp
      if r.kind == "control" then
        check(d.nfz == 0, tag .. ": a payable spell fizzled")
        check(mp0 - sp[1].mp == qa.v and sp[1].mp - sp[2].mp == qb.v,
          string.format("%s: charged %d and %d (want the queued %s and %s)", tag,
          mp0 - sp[1].mp, sp[1].mp - sp[2].mp, tostring(qa.v), tostring(qb.v)))
      elseif r.kind == "first" then
        check(d.nfz == 1, string.format("%s: %d fizzles (want A's one)", tag, d.nfz))
        check(sp[1].mp == r.picks[2].cost, tag .. ": MP charged for the refused A")
        check(sp[1].mp - sp[2].mp == qb.v, string.format("%s: B charged %d "
          .. "(want its queued %s)", tag, sp[1].mp - sp[2].mp, tostring(qb.v)))
        check(sp[2].atk == qb.id, string.format("%s: B cast $%02X (want the "
          .. "queued, boosted $%s)", tag, sp[2].atk, string.format("%02X", qb.id or 0)))
      elseif r.kind == "second" then
        check(d.nfz == 1, string.format("%s: %d fizzles (want B's one)", tag, d.nfz))
        check(r.drained2 ~= nil, tag .. ": the drain after A never ran")
        check(mp0 - sp[1].mp == qa.v, string.format("%s: A charged %d (want its "
          .. "queued %s)", tag, mp0 - sp[1].mp, tostring(qa.v)))
        check(sp[2].mp == r.picks[2].cost - 1, tag .. ": MP charged for the refused B")
      else
        check(d.nfz == 2, string.format("%s: %d fizzles (want both)", tag, d.nfz))
        check(sp[1].mp == r.picks[2].cost - 1 and sp[2].mp == sp[1].mp,
          tag .. ": MP charged for a refused spell")
      end
      if r.kind == "both" then
        check(d.pend == 0, string.format("%s: the pending boost was kept for "
          .. "spending (it read %d at the turn's end)", tag, d.pend))
        check(a.bank == math.min(5, r.bank0 + 1), string.format("%s: bank %d -> "
          .. "%d (want %d: no spend, the unboosted turn's regen)", tag, r.bank0,
          a.bank, math.min(5, r.bank0 + 1)))
      else
        check(d.pend == r.pend0, string.format("%s: the pip not pending at the "
          .. "turn's end (it read %d)", tag, d.pend))
        check(a.bank == r.bank0 - r.pend0, string.format("%s: bank %d -> %d "
          .. "(want the pip spent)", tag, r.bank0, a.bank))
      end
    elseif d and a then
      local tag = string.format("%s branch %d", r.verb, r.k)
      if r.drain then
        n[r.verb].d = n[r.verb].d + 1
        check(d.fizzled, tag .. " (drained): the harness noted no fizzle")
        check(d.mp == 1, tag .. " (drained): MP charged for a refused action")
        check(not d.dancing, tag .. " (drained): a dance began")
        check(d.pend == 0, string.format("%s (drained): the pending boost "
          .. "was kept for spending (it read %d at the turn's end)", tag, d.pend))
        check(d.note ~= nil and d.note:find("boost=0 ", 1, true) ~= nil,
          tag .. " (drained): the fizzle note does not read boost=0: "
          .. tostring(d.note))
        check(a.bank == math.min(5, r.bank0 + 1), string.format("%s (drained): "
          .. "bank %d -> %d (want %d: no spend, the unboosted turn's regen)",
          tag, r.bank0, a.bank, math.min(5, r.bank0 + 1)))
      elseif r.verb == "Dance" and not d.dancing then
        -- stumbled off its terrain: battle_dancestumble's property
      else
        n[r.verb].c = n[r.verb].c + 1
        check(not d.fizzled, tag .. " (control): a payable action fizzled")
        check(r.mp0 - d.mp == r.price, string.format("%s (control): charged %d "
          .. "(want the listed %d)", tag, r.mp0 - d.mp, r.price))
        check(d.pend == r.pend0, tag .. " (control): the pip not pending at the turn's end")
        check(a.bank == r.bank0 - r.pend0, string.format("%s (control): bank "
          .. "%d -> %d (want the pip spent)", tag, r.bank0, a.bank))
      end
    end
  end
  for _, m in ipairs(fails) do H.log("[mpfizzle] FAIL " .. m) end
  H.log(string.format("[mpfizzle] SUMMARY Magic control=%d drained=%d, Dance "
    .. "control=%d drained=%d, XMagic control=%d first=%d second=%d both=%d "
    .. "(boost %d)", n.Magic.c, n.Magic.d, n.Dance.c, n.Dance.d, nx.control,
    nx.first, nx.second, nx.both, BOOST))
  H.assertEq(#fails, 0, "every resolved branch: a refused boosted action kept its pips")
  for _, v in ipairs({ "Magic", "Dance" }) do
    H.assertEq(n[v].d >= MIN_EACH, true, v .. ": enough drained branches resolved")
    H.assertEq(n[v].c >= 1, true, v .. ": a paid control branch resolved")
  end
  for _, k in ipairs(XKINDS) do
    H.assertEq(nx[k] >= 1, true, "XMagic: a " .. k .. " branch resolved")
  end
end)
H.run({ maxFrames = 400000 }, body)
