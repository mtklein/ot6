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
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_tritoch.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_TRANS, ST_CMD, ST_MAGIC, ST_DANCE, ST_TGT = 0x01, 0x05, 0x0E, 0x21, 0x38
local ST_DEF = 0x27
local CMDTBL = 0x202E
local CMD_MAGIC, CMD_DANCE = 0x02, 0x13
local MLISTPTR = 0x302C
local QCMD = 0x3A7A
local MOG = 0x0A
local DANCES = 0x1D4C
local BOOST = 1
local BRANCHES, MIN_EACH = 8, 3

local function bp(s) return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function mp(s) return H.readWord(0x3C08 + s * 2) end
local function dancing(s) return (H.readByte(0x3EF8 + s * 2) & 0x01) ~= 0 end

local function cmdCellOf(slot, cmd)
  for i = 0, 3 do
    if H.readByte(CMDTBL + slot * 12 + i * 3) == cmd then return i end
  end
  return nil
end

local ph = 0
local snap0, snap = nil, nil
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
    local wantRow, wantCol = cell // 2, cell % 2
    local absRow = H.readByte(0x8913 + a) + H.readByte(0x891B + a)
    local col = H.readByte(0x8917 + a)
    if absRow ~= wantRow then btn = (absRow < wantRow) and "down" or "up"
    elseif col ~= wantCol then btn = (col < wantCol) and "right" or "left"
    else
      rec.spell, rec.price = id, cost
      btn = "a"
    end
  elseif st == ST_DANCE and V.cmd == CMD_DANCE then
    local row, col = danceId // 2, danceId % 2
    local cr, cc = H.readByte(0x893B + a), H.readByte(0x8937 + a)
    if cr ~= row then btn = (cr < row) and "down" or "up"
    elseif cc ~= col then btn = (cc < col) and "right" or "left"
    else rec.price = danceCost(); btn = "a" end
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

local function window(what)
  return step(what, function()
    return H.battleLoadStarted() and H.readByte(MENU) ~= 0
       and H.readByte(ACTOR) == who and H.readByte(MSTATE) == ST_CMD
  end)
end

-- ------------------------------------------------------------ observers --
local function installObservers()
  emu.addMemoryCallback(function()
    if not (rec and V) or rec.queued then return end
    if H.readByte(QCMD) ~= V.cmd then return end
    rec.queued = { f = H.frame, mp = mp(who), pend = pend(who),
                   fz = H.fizzles.n }
  end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if not (rec and rec.queued) or rec.done then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= who * 2 then return end
    if H.readByte(0x3A7C) ~= V.cmd then return end
    local note = H.fizzles.rows[#H.fizzles.rows]
    rec.done = { f = H.frame, pend = pend(who), bank = bp(who), mp = mp(who),
                 dancing = dancing(who), fizzled = H.fizzles.n > rec.queued.fz,
                 note = (H.fizzles.n > rec.queued.fz) and note or nil }
  end, emu.callbackType.exec, ae, ae)
end

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
      rec = { k = k, drain = drain, verb = V.name }
      recs[#recs + 1] = rec
      want = "idle"
      H.log(string.format("[mpfizzle] %s branch %d (%s): %d idle frames at "
        .. "the caster's window", V.name, k, drain and "drained" or "control",
        (k - 1) * 9))
    end),
    H.waitFrames((k - 1) * 9 + 1),
    H.call(function()
      rec.bank0, rec.mp0 = bp(who), mp(who)
      want = "press"
    end),
    step(V.name .. " commits, boosted", function() return rec.queued ~= nil end, 3000),
    H.call(function()
      rec.pend0 = rec.queued.pend
      if drain then
        H.writeWord(0x3C08 + who * 2, 1)
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
      if not H.battleLoadStarted() then return true end
      if rec.done and H.frame >= rec.done.f + 20 then
        rec.after = { bank = bp(who), mp = mp(who), dancing = dancing(who) }
        return true
      end
      return false
    end, 6000, {
      H.call(function()
        ph = ph + 1
        if not H.battleLoadStarted() then H.setPad({}) return end
        if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == who then
          H.setPad({})
        else
          pulse()
        end
      end),
      H.waitFrames(1),
    }, V.name .. " start turn resolves"),
    H.call(function()
      local d, a = rec.done, rec.after
      if not (d and a) then
        H.log(string.format("[mpfizzle] %s branch %d: the fight ended before "
          .. "the turn resolved (no outcome)", V.name, k))
        return
      end
      H.log(string.format("[mpfizzle] %s branch %d %s: commit pending %d bank "
        .. "%d pool %d | turn end f%d pending %d bank %d pool %d fizzled=%s "
        .. "dancing=%s | +20f bank %d pool %d%s", V.name, k,
        drain and "DRAINED" or "CONTROL", rec.pend0, rec.bank0, rec.mp0, d.f,
        d.pend, d.bank, d.mp, tostring(d.fizzled), tostring(d.dancing), a.bank,
        a.mp, d.note and ("\n[mpfizzle] note: " .. d.note) or ""))
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
    window(verb.name .. " caster's command window"),
    H.call(function()
      H.setPad({})
      H.assertEq(bp(who) >= BOOST, true, "the caster holds the opening pip")
      snap = H.requestSaveState()
    end),
    H.waitFrames(2),
    H.call(function() H.checkReq(snap, "snapshot at the caster's window") end),
  }
  for k = 1, BRANCHES do out[#out + 1] = branch(k) end
  return H.seqStep(out)
end

local body = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 6000, "world control on the World of Ruin map"),
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
  H.call(function()
    installObservers()
    H.setPad({})
    snap0 = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap0, "battle-start snapshot") end),
}

local function slotOfChar(c)
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) == c then return s end
  end
end
local function magicCaster()
  for s = 0, 3 do
    if cmdCellOf(s, CMD_MAGIC) then return s end
  end
end
body[#body + 1] = phase({ name = "Magic", cmd = CMD_MAGIC }, function()
  local s = magicCaster()
  assert(s, "a party member with a Magic row")
  return s
end)
body[#body + 1] = phase({ name = "Dance", cmd = CMD_DANCE }, function()
  local s = slotOfChar(MOG)
  assert(s, "MOG is in the party")
  assert(cmdCellOf(s, CMD_DANCE), "MOG's command list carries Dance")
  return s
end)
body[#body + 1] = H.call(function()
  H.setPad({})
  local n = { Magic = { c = 0, d = 0 }, Dance = { c = 0, d = 0 } }
  local fails = {}
  local function check(ok, msg) if not ok then fails[#fails + 1] = msg end end
  for _, r in ipairs(recs) do
    local d, a = r.done, r.after
    if d and a then
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
    .. "control=%d drained=%d (boost %d)", n.Magic.c, n.Magic.d, n.Dance.c,
    n.Dance.d, BOOST))
  H.assertEq(#fails, 0, "every resolved branch: a refused boosted action kept its pips")
  for _, v in ipairs({ "Magic", "Dance" }) do
    H.assertEq(n[v].d >= MIN_EACH, true, v .. ": enough drained branches resolved")
    H.assertEq(n[v].c >= 1, true, v .. ": a paid control branch resolved")
  end
end)
H.run({ maxFrames = 400000 }, body)
