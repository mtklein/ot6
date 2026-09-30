-- @suite savestate=moogle_cleared slow
-- battle_dancestumble.lua -- a boosted Dance start that stumbles costs
-- nothing: no MP, no pips (#313).
--
-- Off its terrain a Dance start stumbles half the time (vanilla's roll in
-- Cmd_13, kept): the DANCE status is cleared, MOG spends the turn on
-- "Stumbled!!" and no dance begins, so neither the boost's multiplier nor
-- the whole-battle state was bought.  Before #313 the stumble still paid the
-- boosted price (CalcAttackEffect charged the queued $3a4c on the stumble's
-- self-action) and spent the pips (Ot6ActionEnd found the pending boost).
-- Ot6DanceStumble now drops both before either is charged, so the turn ends
-- as an unboosted stumble would: MP untouched, nothing pending, the regen
-- pip banked.  The dance that does start still pays the boosted price and
-- the pip, and is the control that the boost is not simply switched off.
--
-- The run is the real MOG in the moogle defense (battle_danceboost's
-- fixture and march).  He learns the terrain's dance by winning P2's first
-- wave.  SYNTHETIC SETUP (waivered): that fixture is the route's only
-- MOG-with-Dance window and holds one terrain, so no dance he can know
-- there is ever off its terrain and the stumble roll never runs.  Between
-- the waves the known-dance mask ($1D4C) gains one more dance, the lowest
-- id whose terrain is not this one -- what learning it elsewhere would have
-- written.  Everything after that is real menus: in the second wave he
-- takes the pip every character opens with, presses R once, and starts
-- that dance.  His squad Defends.  The first command window is snapshotted
-- and branched (each branch idles 7 frames longer there, its own draw of the
-- 50% roll) at least MIN_BRANCHES times and until both outcomes, a stumble
-- and a started dance, have been seen, at most MAX_BRANCHES.  Observed,
-- never written: the stumble arm's execution (Cmd_13's `lda #$06 / sta
-- $3401`, "Stumbled!!", found by its bytes so the same test runs on any
-- build), MOG's pending boost, bank, MP and DANCE status at the start
-- turn's Ot6ActionEnd, and his bank 20 frames after it.
-- Asserted, per branch whose start turn resolved:
--   1. it stumbled exactly when the dance did not lock in;
--   2. a stumble: MP unchanged, nothing pending at the turn's end, and the
--      bank one pip up (capped at 5) -- the unboosted turn's regen, no spend;
--   3. a started dance: the boosted price (H.boostPrice(8, 1)) charged, the
--      pip pending at the turn's end, and the bank one pip down;
-- and across branches: at least one stumble and one started dance.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/moogle_defense.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_DANCE = 0x05, 0x21
local ST_DEF = 0x27
local CMD_DANCE = 0x13
local CMDTBL = 0x202E
local MOG = 0x0A
local DANCES = 0x1D4C                   -- known-dance mask
local FIGHTPARTY = 0x1A6D               -- which party a defense battle engaged
local BOOST = 1                         -- the pip every character opens with
local MIN_BRANCHES, MAX_BRANCHES = 8, 16

local function bp(s) return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function mpOf(s) return H.readWord(0x3C08 + s * 2) end
local function dancing(s) return (H.readByte(0x3EF8 + s * 2) & 0x01) ~= 0 end

-- squads (gen_moogle's tables): P2 = MOG + three moogles, leader obj $019A
local LEADER_OFF = { [1] = 0x0029, [2] = 0x019A, [3] = 0x0148 }
local function ySwitchTo(p)
  return H.driveUntil(function()
    return H.readWord(0x0803) == LEADER_OFF[p]
  end, 1800, {
    H.pressButtons({ "y" }, 6),
    H.waitFrames(40),
  }, "Y-switch to party " .. p)
end

local mogSlot, danceId, offId = nil, nil, nil
local ph, hb = 0, -600

-- fight every non-P2 battle with plain tap-A; stop when a battle engages P2
local function untilP2Battle(what)
  local battN = 0
  return H.driveUntil(function()
    battN = H.battleLoadStarted() and battN + 1 or 0
    return battN >= 30 and H.readByte(FIGHTPARTY) == 2
  end, 60000, {
    H.call(function()
      ph = ph + 1
      if H.frame - hb >= 600 then
        hb = H.frame
        H.log(string.format("[hb f%d] batt=%s party=%d menu=%02x",
          H.frame, tostring(H.battleLoadStarted()), H.readByte(FIGHTPARTY),
          H.readByte(MENU)))
      end
      if H.battleLoadStarted() and H.readByte(FIGHTPARTY) == 2 then
        H.setPad({})
      else
        H.setPad(ph % 8 < 4 and { a = true } or {})
      end
    end),
    H.waitFrames(1),
  }, what)
end

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

local function winByTapA(what)
  return H.driveUntil(function() return not H.battleLoadStarted() end, 30000, {
    H.call(function()
      ph = ph + 1
      H.setPad(ph % 8 < 4 and { a = true } or {})
    end),
    H.waitFrames(1),
  }, what)
end

local function findMog()
  mogSlot = nil
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) == MOG then mogSlot = s end
  end
  assert(mogSlot, "MOG is in P2's battle party")
end

local function mogMenu(what)
  return H.driveUntil(function()
    return H.battleLoadStarted() and H.readByte(MENU) ~= 0
       and H.readByte(ACTOR) == mogSlot and H.readByte(MSTATE) == ST_CMD
  end, 30000, {
    H.call(function()
      ph = ph + 1
      if not H.battleLoadStarted() then H.setPad({}) return end
      if H.readByte(MENU) == 0 then
        H.setPad(ph % 8 < 4 and { a = true } or {})
      elseif H.readByte(ACTOR) ~= mogSlot then bystander()
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, what)
end

-- R until MOG's pending boost reads BOOST (edge presses, read back)
local function raiseBoost(what)
  return H.driveUntil(function()
    return H.readByte(ACTOR) == mogSlot and H.readByte(MSTATE) == ST_CMD
       and pend(mogSlot) == BOOST
  end, 900, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MSTATE) ~= ST_CMD or H.readByte(ACTOR) ~= mogSlot then
        H.setPad({}) return
      end
      local p = pend(mogSlot)
      if p < BOOST then H.setPad(ph % 10 < 5 and { r = true } or {})
      elseif p > BOOST then H.setPad(ph % 10 < 5 and { l = true } or {})
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, what)
end

local function openDance(what)
  return H.driveUntil(function() return H.readByte(MSTATE) == ST_DANCE end,
    1200, {
      H.call(function()
        ph = ph + 1
        local edge = ph % 10 < 5
        local a = H.readByte(ACTOR)
        if H.readByte(MSTATE) ~= ST_CMD then H.setPad({}) return end
        local wantCell = nil
        for i = 0, 3 do
          if H.readByte(CMDTBL + a * 12 + i * 3) == CMD_DANCE then wantCell = i end
        end
        assert(wantCell, "MOG's real battle command list carries Dance now")
        local cur = H.readByte(0x890F + a)
        if cur == wantCell then H.setPad(edge and { a = true } or {})
        elseif cur < wantCell then H.setPad(edge and { down = true } or {})
        else H.setPad(edge and { up = true } or {}) end
      end),
      H.waitFrames(1),
    }, what)
end

local function danceCursorTo(what)   -- onto offId, read when it runs
  return H.driveUntil(function()
    local id = offId
    local a = H.readByte(ACTOR)
    return H.readByte(MSTATE) == ST_DANCE
       and H.readByte(0x8937 + a) == id % 2
       and H.readByte(0x893B + a) == id // 2
  end, 900, {
    H.call(function()
      ph = ph + 1
      local edge = ph % 10 < 5
      local a = H.readByte(ACTOR)
      if H.readByte(MSTATE) ~= ST_DANCE then H.setPad({}) return end
      local id = offId
      local row, col = id // 2, id % 2
      local cr, cc = H.readByte(0x893B + a), H.readByte(0x8937 + a)
      if cr ~= row then H.setPad(edge and { [(cr < row) and "down" or "up"] = true } or {})
      elseif cc ~= col then H.setPad(edge and { [(cc < col) and "right" or "left"] = true } or {})
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, what)
end

-- ---- observers --------------------------------------------------------------
local recs = {}           -- one per branch
local rec = nil           -- the live branch's record

-- the stumble arm, by its bytes: `lda #$06 / sta $3401` ("Stumbled!!")
-- inside Cmd_13, so the observer needs no symbol a given build may lack
local function findStumbleArm()
  local base = H.sym("Cmd_13") & 0x3FFFFF
  local pat = { 0xA9, 0x06, 0x8D, 0x01, 0x34 }
  for off = 0, 0x7F do
    local hit = true
    for i = 1, #pat do
      if H.readRomByte(base + off + i - 1) ~= pat[i] then hit = false; break end
    end
    if hit then return (H.sym("Cmd_13") + off) end
  end
  error("Cmd_13's stumble arm (lda #$06 / sta $3401) not found")
end

local function installObservers()
  local arm = findStumbleArm()
  emu.addMemoryCallback(function()
    if not (rec and mogSlot) then return end
    if (emu.getState()["cpu.y"] & 0xFF) ~= mogSlot * 2 then return end
    rec.stumbled = true
  end, emu.callbackType.exec, arm, arm)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if not (rec and rec.committed and mogSlot) or rec.done then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= mogSlot * 2 then return end
    if H.readByte(0x3A7C) ~= CMD_DANCE then return end
    rec.done = { f = H.frame, pend = pend(mogSlot), bank = bp(mogSlot),
                 mp = mpOf(mogSlot), dancing = dancing(mogSlot) }
  end, emu.callbackType.exec, ae, ae)
  H.log(string.format("[dancestumble] stumble arm $%06X, Ot6ActionEnd $%06X",
    arm, ae))
end

local function tally()
  local st, dn = 0, 0
  for _, r in ipairs(recs) do
    if r.after then
      if r.stumbled then st = st + 1 elseif r.done.dancing then dn = dn + 1 end
    end
  end
  return st, dn
end

local snap = nil
local function branch(k, wait)
  local req
  return H.cond(function()
    local st, dn = tally()
    return #recs < MIN_BRANCHES or st == 0 or dn == 0
  end, {
    H.call(function() H.setPad({}); rec = nil; req = H.requestLoadState(snap.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load (branch " .. k .. ")")
      H.rearmInputInjection()
      rec = { k = k, wait = wait }
      recs[#recs + 1] = rec
      H.log(string.format("[dancestumble] branch %d: %d idle frames at MOG's window", k, wait))
    end),
    H.waitFrames(wait + 1),
    raiseBoost("R to boost " .. BOOST),
    openDance("the dance list opens"),
    H.waitFrames(20),
    danceCursorTo("cursor onto the off-terrain dance's cell"),
    H.call(function()
      rec.pend0, rec.bank0, rec.mp0 = pend(mogSlot), bp(mogSlot), mpOf(mogSlot)
      H.log(string.format("[dancestumble] confirm: pending %d, bank %d, %d MP",
        rec.pend0, rec.bank0, rec.mp0))
    end),
    H.driveUntil(function()
      return H.readByte(0x32CC + mogSlot * 2) ~= 0xFF or dancing(mogSlot)
    end, 1800, {
      H.call(function()
        ph = ph + 1
        if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == mogSlot then
          H.setPad(ph % 10 < 5 and { a = true } or {})
        else H.setPad({}) end
      end),
      H.waitFrames(1),
    }, "the dance commits"),
    H.call(function() rec.committed = true end),
    -- run until 20 frames past the start turn's end (or the wave's end)
    H.driveUntil(function()
      if not H.battleLoadStarted() then return true end
      if rec.done and H.frame >= rec.done.f + 20 then
        rec.after = { bank = bp(mogSlot), mp = mpOf(mogSlot) }
        return true
      end
      return false
    end, 20000, {
      H.call(function()
        ph = ph + 1
        if not H.battleLoadStarted() or H.readByte(MENU) == 0 then
          H.setPad(ph % 8 < 4 and { a = true } or {})
        elseif H.readByte(ACTOR) ~= mogSlot then bystander()
        else H.setPad({}) end
      end),
      H.waitFrames(1),
    }, "MOG's dance start turn resolves"),
    H.call(function()
      local d, a = rec.done, rec.after
      if not (d and a) then
        H.log(string.format("[dancestumble] branch %d: the wave ended before "
          .. "the start turn resolved (no outcome)", k))
        return
      end
      H.log(string.format("[dancestumble] branch %d %s: confirm pending %d "
        .. "bank %d MP %d | turn end f%d pending %d bank %d MP %d dancing=%s "
        .. "| +20f bank %d MP %d", k, rec.stumbled and "STUMBLED" or
        (d.dancing and "DANCED" or "NEITHER"), rec.pend0, rec.bank0, rec.mp0,
        d.f, d.pend, d.bank, d.mp, tostring(d.dancing), a.bank, a.mp))
    end),
  })
end

local body = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "control on the defense map"),
  H.call(function()
    H.assertEq(H.mapId(), 51, "moogle_defense on map 51")
    installObservers()
  end),
  -- deployment, gen_moogle's exact march order
  H.navTo(15, 15, { maxFrames = 2500, playBattles = true }),
  ySwitchTo(3),
  H.navTo(20, 20, { maxFrames = 4000, playBattles = true }),
  ySwitchTo(2),
  H.navTo(10, 21, { maxFrames = 4000, playBattles = true }),
  ySwitchTo(1),
  H.navTo(14, 14, { maxFrames = 2500, playBattles = true }),
  -- P2's first wave teaches the terrain's dance
  untilP2Battle("the west arm's first wave engages MOG's squad"),
  H.waitFrames(240),
  H.call(function()
    findMog()
    danceId = H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF) + H.readByte(0x11E2))
    H.assertEq(danceId < 8, true, "this background HAS a dance to teach")
  end),
  winByTapA("P2's first wave won with plain Fights"),
  H.waitFrames(60),
  H.call(function()
    local mask = H.readByte(DANCES)
    H.assertEq(mask & (1 << danceId) ~= 0, true,
      "the victory taught the background's dance")
    for d = 0, 7 do
      if d ~= danceId then offId = d; break end
    end
    -- SYNTHETIC SETUP (see header): one dance from another terrain
    H.writeByte(DANCES, mask | (1 << offId))
    H.log(string.format("[dancestumble] terrain dance %d; known mask %02X -> "
      .. "%02X (dance %d added, synthetic)", danceId, mask, H.readByte(DANCES), offId))
  end),
}
body[#body + 1] = untilP2Battle("the west arm's second wave engages MOG's squad")
body[#body + 1] = H.waitFrames(240)
body[#body + 1] = H.call(function()
  findMog()
  local bgDance = H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF) + H.readByte(0x11E2))
  H.assertEq(bgDance ~= offId, true,
    "the chosen dance is off this terrain: vanilla's stumble roll is live")
  H.log(string.format("[dancestumble] second wave: MOG slot %d, %d MP, %d BP, "
    .. "terrain dance %d, chosen dance %d", mogSlot, mpOf(mogSlot), bp(mogSlot),
    bgDance, offId))
end)
body[#body + 1] = mogMenu("MOG's command window")
body[#body + 1] = H.call(function()
  H.assertEq(bp(mogSlot) >= BOOST, true,
    "MOG holds the pip every character opens with")
  H.assertEq(mpOf(mogSlot) >= H.boostPrice(8, BOOST), true, string.format(
    "MOG's real pool (%d) pays a boost-%d dance start (%d)",
    mpOf(mogSlot), BOOST, H.boostPrice(8, BOOST)))
  H.setPad({})
  snap = H.requestSaveState()
end)
body[#body + 1] = H.waitFrames(2)
body[#body + 1] = H.call(function() H.checkReq(snap, "snapshot at MOG's window") end)
for k = 1, MAX_BRANCHES do body[#body + 1] = branch(k, (k - 1) * 7) end
body[#body + 1] = H.call(function()
  H.setPad({})
  local price = H.boostPrice(8, BOOST)
  local st, dn = tally()
  local resolved = 0
  for _, r in ipairs(recs) do if r.after then resolved = resolved + 1 end end
  H.log(string.format("[dancestumble] SUMMARY branches=%d resolved=%d "
    .. "stumbled=%d danced=%d (boost %d, boosted price %d)",
    #recs, resolved, st, dn, BOOST, price))
  local fails = {}
  local function check(ok, msg) if not ok then fails[#fails + 1] = msg end end
  for _, r in ipairs(recs) do
    local d, a = r.done, r.after
    if a then
      check(r.pend0 == BOOST, string.format(
        "branch %d: the start was confirmed with pending %d (want %d)", r.k, r.pend0, BOOST))
      check((r.stumbled or false) == (not d.dancing), string.format(
        "branch %d: stumbled=%s but dancing=%s", r.k, tostring(r.stumbled), tostring(d.dancing)))
      if r.stumbled then
        check(d.mp == r.mp0, string.format(
          "branch %d: a stumbled start charged %d MP (want 0)", r.k, r.mp0 - d.mp))
        check(d.pend == 0, string.format(
          "branch %d: a stumbled start ended its turn with %d pip(s) pending to spend (want 0)",
          r.k, d.pend))
        check(a.bank == math.min(5, r.bank0 + 1), string.format(
          "branch %d: bank %d -> %d after a stumble (want %d: no spend, the unboosted regen)",
          r.k, r.bank0, a.bank, math.min(5, r.bank0 + 1)))
      elseif d.dancing then
        check(r.mp0 - d.mp == price, string.format(
          "branch %d: a started dance charged %d MP (want the boosted %d)", r.k, r.mp0 - d.mp, price))
        check(d.pend == BOOST, string.format(
          "branch %d: a started dance ended its turn with %d pending (want %d)", r.k, d.pend, BOOST))
        check(a.bank == r.bank0 - BOOST, string.format(
          "branch %d: bank %d -> %d after a started dance (want %d)",
          r.k, r.bank0, a.bank, r.bank0 - BOOST))
      end
    end
  end
  for _, m in ipairs(fails) do H.log("[dancestumble] FAIL " .. m) end
  H.assertEq(st >= 1, true, "at least one branch stumbled (else the stumble was not measured)")
  H.assertEq(dn >= 1, true, "at least one branch started the dance (the control)")
  H.assertEq(#fails, 0, "every resolved branch: a stumble cost nothing, a started dance paid (#313)")
end)

H.run({ maxFrames = 400000 }, body)
