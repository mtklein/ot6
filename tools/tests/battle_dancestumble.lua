-- @suite savestate=wor_tritoch slow
-- battle_dancestumble.lua -- a boosted Dance start that stumbles charges no
-- MP and spends its boost (#313, #473).
--
-- Off its terrain a Dance start can stumble (Cmd_13's roll; the start's
-- boost tilts it, battle_danceodds): the DANCE status is cleared, MOG spends
-- the turn on "Stumbled!!" and no dance begins, so the MP price, which buys
-- the dance's whole-battle state at its multiplier, is not charged
-- (Ot6DanceStumble clears the queued $3a4c before CalcAttackEffect charges
-- it, #313).  The boost bought the odds of the roll that was taken, so it is
-- spent (owner, #473): Ot6ActionEnd finds it pending and charges the bank,
-- with no regen pip.  Before #473 Ot6DanceStumble dropped the pending boost
-- too, and the turn ended as an unboosted stumble (bank one pip up).  The
-- dance that does start pays the boosted price and the pip, the control that
-- the MP rule is not simply switched off.
--
-- The run is the real MOG on the World of Ruin map (wor_tritoch: he is in
-- the party and knows five dances, carried from the World of Balance and the
-- Water Rondo detour).  A world-map encounter is walked into, and the dance
-- chosen is the lowest-numbered known dance that is not the encounter
-- background's own, so the stumble roll is live with nothing written: no
-- state is touched anywhere in this file.  MOG takes the pip every
-- character opens with, presses R once and starts that dance.  His party
-- Defends.  The first command window is snapshotted and branched (each branch
-- idles 7 frames longer there and Defends (k-1) % 4 + (k-1)//4 % 3 turns
-- first, its own draw of the roll) at least MIN_BRANCHES times and until both outcomes, a
-- stumble and a started dance, have been seen, at most MAX_BRANCHES.  At one
-- point a start stumbles a quarter of the time (Ot6DanceStumbleOdds).
-- Observed, never written: the stumble arm's execution (Cmd_13's `lda #$06 /
-- sta $3401`, "Stumbled!!", found by its bytes so the same test runs on any
-- build), MOG's pending boost, bank, MP and DANCE status at the start
-- turn's Ot6ActionEnd, and his bank 20 frames after it.
-- Asserted, per branch whose start turn resolved:
--   1. it stumbled exactly when the dance did not lock in;
--   2. a stumble: MP unchanged, the pip still pending at the turn's end, and
--      the bank one pip down -- the boost spent, no regen;
--   3. a started dance: the boosted price (H.boostPrice(8, 1)) charged, the
--      pip pending at the turn's end, and the bank one pip down;
-- and across branches: at least one stumble and one started dance.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_tritoch.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_DANCE = 0x05, 0x21
local ST_DEF = 0x27
local CMD_DANCE = 0x13
local CMDTBL = 0x202E
local MOG = 0x0A
local DANCES = 0x1D4C                   -- known-dance mask
local BOOST = 1                         -- the pip every character opens with
local MIN_BRANCHES, MAX_BRANCHES = 8, 24
-- The encounter is whatever the world deals (#454).  One that ends, or where
-- MOG falls, before a branch's start turn resolves gives that branch no
-- outcome (on v0.34's first chain the Mantodea, formation group $0143,
-- killed MOG, and UMARO's berserk swings ended another, before the turn
-- came); once LOST_RUN branches of an encounter in a row give none, or its
-- MAX_BRANCHES are used, the next encounter is taken: the world map before
-- this one is restored, this one is fought out by the walker, the party is
-- cared for, and the next one is walked into.  At most MAX_ENCOUNTERS.
-- Measured over K 0-5 encounters used up first (build/attempts/wt/
-- v034-tzen-wipe/suitelab/sfix/): 6 of 6 pass; K1 ($0143) and K4 ($0145)
-- lost MOG in 3 branches and took encounter 2.  The same draws failed the
-- suite before (sbase/: K1, K2 and K4 timed out; K2 walked in with MOG
-- dead, which the care before the walk now lifts).
local LOST_RUN, MAX_ENCOUNTERS = 3, 4

local function bp(s) return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function mpOf(s) return H.readWord(0x3C08 + s * 2) end
local function dancing(s) return (H.readByte(0x3EF8 + s * 2) & 0x01) ~= 0 end

local mogSlot, danceId, offId = nil, nil, nil
local enc, encs, encLost, lostRun = 0, {}, nil, 0

-- why MOG's turn can no longer come in this battle, or nil: the battle
-- ended, or he is down (no HP, or Wound / Petrify / Zombie in STATUS1)
local function lostWhy()
  if not H.battleLoadStarted() then return "the battle ended" end
  local s = mogSlot
  local hp, st1 = H.readWord(0x3BF4 + s * 2), H.readByte(0x3EE4 + s * 2)
  if hp == 0 or (st1 & 0xC2) ~= 0 then
    return string.format("MOG (slot %d) is down (HP %d, STATUS1 $%02X)", s, hp, st1)
  end
  return nil
end
local ph, hb = 0, -600

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

local function findMog()
  mogSlot = nil
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) == MOG then mogSlot = s end
  end
  assert(mogSlot, "MOG is in the battle party")
end

local rec = nil           -- the live branch's record
local function lostNow()
  if rec == nil then encLost = encLost or lostWhy(); return encLost ~= nil end
  rec.lost = rec.lost or lostWhy()
  return rec.lost ~= nil
end

local function mogMenu(what)
  return H.driveUntil(function()
    if rec and rec.lost then return true end
    if H.battleLoadStarted() and H.readByte(MENU) ~= 0
       and H.readByte(ACTOR) == mogSlot and H.readByte(MSTATE) == ST_CMD then return true end
    return lostNow()
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
    if rec.lost or lostNow() then return true end
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
  return H.driveUntil(function()
      if rec.lost or lostNow() then return true end
      return H.readByte(MSTATE) == ST_DANCE
    end, 1200, {
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
    if rec.lost or lostNow() then return true end
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
  local st, dn, res = 0, 0, 0
  for _, r in ipairs(recs) do
    if r.after then
      res = res + 1
      if r.stumbled then st = st + 1 elseif r.done.dancing then dn = dn + 1 end
    end
  end
  return st, dn, res
end
-- more branches wanted: fewer than MIN_BRANCHES resolved, or either outcome unseen
local function needMore()
  local st, dn, res = tally()
  return res < MIN_BRANCHES or st == 0 or dn == 0
end

local snap = nil
local function branch(k, wait)
  local req
  return H.cond(function()
    return needMore() and encLost == nil and lostRun < LOST_RUN
  end, {
    H.call(function() H.setPad({}); rec = nil; req = H.requestLoadState(snap.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load (branch " .. k .. ")")
      H.rearmInputInjection()
      rec = { k = k, wait = wait, enc = enc }
      recs[#recs + 1] = rec
      H.log(string.format("[dancestumble] branch %d (encounter %d): %d idle frames at MOG's window",
        k, enc, wait))
    end),
    H.waitFrames(wait + 1),
    -- the draw: MOG Defends (k-1) % 4 + (k-1)//4 % 3 turns first, so
    -- monster turns and ATB time move the battle RNG ($be) between branches; idling at his
    -- window alone left it within a few entries of one place, and on the
    -- fixture this ROM's play made every one of them stumbled (16 of 16,
    -- $be $73-$AF, build/attempts/wt/v028-kits/px13-lab2/stumble/lab.out)
    H.repeatN((k - 1) % 4 + ((k - 1) // 4) % 3, {
      H.driveUntil(function()
        if rec.lost or lostNow() then return true end
        return H.readByte(MENU) == 0 or H.readByte(ACTOR) ~= mogSlot
      end, 1800, {
        H.call(function()
          ph = ph + 1
          if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == mogSlot then
            if pend(mogSlot) > 0 and H.readByte(MSTATE) == ST_CMD then
              H.setPad(ph % 10 < 5 and { l = true } or {})
            else bystander() end
          else H.setPad({}) end
        end),
        H.waitFrames(1),
      }, "MOG Defends (the draw)"),
      mogMenu("MOG's next window"),
    }),
    raiseBoost("R to boost " .. BOOST),
    openDance("the dance list opens"),
    H.waitFrames(20),
    danceCursorTo("cursor onto the off-terrain dance's cell"),
    H.call(function()
      if rec.lost then return end
      rec.pend0, rec.bank0, rec.mp0 = pend(mogSlot), bp(mogSlot), mpOf(mogSlot)
      H.log(string.format("[dancestumble] confirm: pending %d, bank %d, %d MP",
        rec.pend0, rec.bank0, rec.mp0))
    end),
    H.driveUntil(function()
      if rec.lost or lostNow() then return true end
      return H.readByte(0x32CC + mogSlot * 2) ~= 0xFF or dancing(mogSlot)
    end, 1800, {
      -- the wave can end under the confirm (the battle goes on while MOG's
      -- list is open): the victory pages wait for A, as in the
      -- resolve step below, so A is pressed with no menu up and the end
      -- reads as lostNow's "the battle ended".  v036-fragile's K2 woc s7 k1
      -- sat on "Got 4808 Exp. point(s)" with nothing pressed until this
      -- step timed out (build/attempts/wt/v036-fragile-fix/g4/).
      H.call(function()
        ph = ph + 1
        if not H.battleLoadStarted() or H.readByte(MENU) == 0 then
          H.setPad(ph % 8 < 4 and { a = true } or {})
        elseif H.readByte(ACTOR) == mogSlot then
          H.setPad(ph % 10 < 5 and { a = true } or {})
        else bystander() end
      end),
      H.waitFrames(1),
    }, "the dance commits"),
    H.call(function() if not rec.lost then rec.committed = true end end),
    -- run until 20 frames past the start turn's end (or the wave's end)
    H.driveUntil(function()
      if rec.lost then return true end
      if not H.battleLoadStarted() then return true end
      if rec.done and H.frame >= rec.done.f + 20 then
        rec.after = { bank = bp(mogSlot), mp = mpOf(mogSlot) }
        return true
      end
      -- MOG down before the start turn resolved: that turn never comes
      if not rec.done then return lostNow() end
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
        lostRun = lostRun + 1
        H.log(string.format("[dancestumble] branch %d (encounter %d): %s before "
          .. "the start turn resolved (no outcome; %d in a row here)", k, enc,
          rec.lost or "the wave ended", lostRun))
        return
      end
      lostRun = 0
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
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 6000, "world control on the World of Ruin map"),
  H.call(function() installObservers() end),
}

local function worldControl(what)
  return H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 6000, what)
end

-- battle_gaufight's walk: alternate left/right at tile boundaries until the
-- world's own encounter roll wins
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

-- encounter e: from encounter e-1's world map (restored, and that encounter
-- fought out by the walker), the party cared for, the world map
-- snapshotted, the walk in, MOG's first window snapshotted, the branches
local function encounter(e)
  local req
  local out = {
    H.cond(function() return e > 1 end, {
      H.call(function()
        H.setPad({}); rec = nil
        req = H.requestLoadState(encs[e - 1].blob)
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
      H.assertEq(H.charHp(MOG) > 0 and (H.charStatus1(MOG) & 0xC2) == 0, true, string.format(
        "encounter %d: MOG stands before the walk in (HP %d, STATUS1 $%02X)", e,
        H.charHp(MOG), H.charStatus1(MOG)))
      rec, enc, encLost, lostRun = nil, e, nil, 0
      encs[e] = H.requestSaveState()
    end),
    H.waitFrames(2),
    H.call(function() H.checkReq(encs[e], "world-map snapshot (encounter " .. e .. ")") end),
    walkIn(),
    H.call(function()
      findMog()
      local mask = H.readByte(DANCES)
      danceId = H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF) + H.readByte(0x11E2))
      offId = nil
      for d = 0, 7 do
        if mask & (1 << d) ~= 0 and d ~= danceId then offId = d; break end
      end
      H.assertEq(offId ~= nil, true, string.format(
        "MOG knows a dance that is not this background's (mask %02X, terrain dance %d)",
        mask, danceId))
      H.log(string.format("[dancestumble] encounter %d: formation group $%04X; known mask %02X, "
        .. "terrain dance %d, chosen dance %d", e, H.readWord(0x11E0), mask, danceId, offId))
      local bgDance = H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF) + H.readByte(0x11E2))
      H.assertEq(bgDance ~= offId, true,
        "the chosen dance is off this terrain: vanilla's stumble roll is live")
      H.log(string.format("[dancestumble] MOG slot %d, %d MP, %d BP, "
        .. "terrain dance %d, chosen dance %d", mogSlot, mpOf(mogSlot), bp(mogSlot),
        bgDance, offId))
    end),
    mogMenu("MOG's command window"),
    H.cond(function() return encLost == nil end, {
      H.call(function()
        H.assertEq(bp(mogSlot) >= BOOST, true,
          "MOG holds the pip every character opens with")
        H.assertEq(mpOf(mogSlot) >= H.boostPrice(8, BOOST), true, string.format(
          "MOG's real pool (%d) pays a boost-%d dance start (%d)",
          mpOf(mogSlot), BOOST, H.boostPrice(8, BOOST)))
        H.setPad({})
        snap = H.requestSaveState()
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(snap, "snapshot at MOG's window") end),
    }, {
      H.call(function()
        H.log(string.format("[dancestumble] encounter %d: %s before MOG's first window: "
          .. "no branch here", e, encLost))
      end),
    }),
  }
  for k = 1, MAX_BRANCHES do out[#out + 1] = branch(k, (k - 1) * 7) end
  return H.seqStep(out)
end
for e = 1, MAX_ENCOUNTERS do
  body[#body + 1] = H.cond(function() return needMore() end, { encounter(e) }, {})
end
body[#body + 1] = H.call(function()
  H.setPad({})
  local price = H.boostPrice(8, BOOST)
  local st, dn, resolved = tally()
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
        check(d.pend == BOOST, string.format(
          "branch %d: a stumbled start ended its turn with %d pip(s) pending to spend (want %d)",
          r.k, d.pend, BOOST))
        check(a.bank == r.bank0 - BOOST, string.format(
          "branch %d: bank %d -> %d after a stumble (want %d: the boost spent, no regen)",
          r.k, r.bank0, a.bank, r.bank0 - BOOST))
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
  H.assertEq(#fails, 0, "every resolved branch: a stumble charged no MP and spent its boost, a started dance paid both (#313, #473)")
end)

H.run({ maxFrames = 400000 }, body)
