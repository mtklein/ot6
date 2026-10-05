-- @suite savestate=moogle_cleared slow
-- battle_danceboost.lua -- a boosted Dance multiplies every step of the
-- dance its start began, not only the first (#294).
--
-- Dance is a multiplier verb: cmd $13 is outside Ot6BoostDmg's exemption
-- gate, so its boost buys x2/x4/x8 and the start is priced at 2.5x per level
-- (Ot6AbilityCost's @dance arm, battle_boostprice / battle_costtable).  The
-- start is the only turn a dancer chooses; every later step is an automatic
-- turn (RandDanceAction) with no menu and so no pending boost, and
-- Ot6ActionEnd spends the start's pips at the end of the start turn.  Before
-- #294 that meant the boost multiplied the first step and nothing after it,
-- while the price comment promised every step.  Ot6DanceStartGate now
-- records the start's tier (OT6_DANCETIER) and Ot6BoostLevel hands it to
-- Ot6BoostDmg on every step of that dance.
--
-- The run is the real MOG in the moogle defense (the fixture
-- battle_dancemp uses): he learns his dance by winning P2's first wave on
-- this terrain, then in the second wave he takes the pip every character
-- opens with, presses R once, and starts the dance -- real menus, no state
-- writes.  His squad Defends.  The second wave's first command window is
-- snapshotted and branched (up to BRANCHES times, each idling 9 frames
-- longer there, so each is its own draw of steps and monster turns) until a
-- branch has seen a later step deal damage: a boosted first step often ends
-- the wave by itself.  Every branch's steps are checked.  Observed, never
-- written: every Ot6BoostDmg call made for MOG on a Dance action, with the
-- base damage it was handed ($11b0 at entry) and what it handed back
-- ($11b0 at its one exit, the rtl before Ot6FoldCmdTbl), his pending boost
-- there, and his pending boost, bank and MP at each Ot6ActionEnd while he
-- dances.
-- Asserted:
--   1. the start was boosted: pending 1 at the start step, and each start
--      charged the boosted price (H.boostPrice(8, 1)) from the real pool;
--   2. at least one LATER step (one after the branch's start turn ended)
--      dealt damage (base > 0) -- without it this run says nothing about
--      the steps after the first;
--   3. every step with damage, the start and each later one, came back
--      multiplied by 2 (saturating at $ffff, the proc's own cap, #359);
--   4. no later step spent a pip: Ot6ActionEnd found MOG's pending boost
--      at 0 on every dancing turn but the start.

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
local BRANCHES = 4                      -- draws of the second wave, at most

local BD = H.sym("Ot6BoostDmg")
local BD_EXIT = H.sym("Ot6FoldCmdTbl") - 1   -- `done: plp / rtl`, the rtl

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

local mogSlot, danceId = nil, nil
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

local function danceCursorToKnown(what)
  return H.driveUntil(function()
    local a = H.readByte(ACTOR)
    return H.readByte(MSTATE) == ST_DANCE
       and H.readByte(0x8937 + a) == danceId % 2
       and H.readByte(0x893B + a) == danceId // 2
  end, 900, {
    H.call(function()
      ph = ph + 1
      local edge = ph % 10 < 5
      local a = H.readByte(ACTOR)
      if H.readByte(MSTATE) ~= ST_DANCE then H.setPad({}) return end
      local row, col = danceId // 2, danceId % 2
      local cr, cc = H.readByte(0x893B + a), H.readByte(0x8937 + a)
      if cr ~= row then H.setPad(edge and { [(cr < row) and "down" or "up"] = true } or {})
      elseif cc ~= col then H.setPad(edge and { [(cc < col) and "right" or "left"] = true } or {})
      else H.setPad({}) end
    end),
    H.waitFrames(1),
  }, what)
end

-- ---- observers --------------------------------------------------------------
local steps = {}          -- one per Ot6BoostDmg call for MOG on a Dance action
local cur = nil
local ends = {}           -- Ot6ActionEnd for a dancing MOG: { f, pend, bank, mp, branch }
local startMps = {}       -- [branch] = MOG's MP at the dance confirm
local branches = 0        -- snapshot branches of the second wave run so far
local startEnded = {}     -- [branch] = that branch's dance start turn has ended
local startMp, startBank = nil, nil

local function installObservers()
  H.assertEq(H.readRomByte(BD_EXIT & 0x3FFFFF), 0x6B,
    "the byte before Ot6FoldCmdTbl is Ot6BoostDmg's rtl")
  H.assertEq(H.readRomByte((BD_EXIT - 1) & 0x3FFFFF), 0x28,
    "...after its plp: the proc's one exit, `done`")
  emu.addMemoryCallback(function()
    if not mogSlot then return end
    local x = emu.getState()["cpu.x"] & 0xFF
    if x ~= mogSlot * 2 or H.readByte(0x3A7C) ~= CMD_DANCE then return end
    -- a step is LATER when this branch's start turn has already ended:
    -- position, not the pending byte, so a build that re-banked a pending
    -- boost on every step is still read as later steps and caught below
    cur = { f = H.frame, base = H.readWord(0x11B0), pend = pend(mogSlot),
            dancing = dancing(mogSlot), bank = bp(mogSlot),
            branch = branches, later = startEnded[branches] or false }
  end, emu.callbackType.exec, BD, BD)
  emu.addMemoryCallback(function()
    if not cur then return end
    cur.final = H.readWord(0x11B0)
    steps[#steps + 1] = cur
    cur = nil
  end, emu.callbackType.exec, BD_EXIT, BD_EXIT)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if not mogSlot then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= mogSlot * 2 then return end
    if not dancing(mogSlot) then return end
    ends[#ends + 1] = { f = H.frame, pend = pend(mogSlot), bank = bp(mogSlot),
                        mp = mpOf(mogSlot), branch = branches,
                        start = not startEnded[branches] }
    startEnded[branches] = true
  end, emu.callbackType.exec, ae, ae)
  H.log(string.format("[danceboost] Ot6BoostDmg $%06X, exit $%06X, "
    .. "Ot6ActionEnd $%06X", BD, BD_EXIT, ae))
end

local function multiplied(base, n)
  local v = base
  for _ = 1, n do
    v = v << 1
    if v > 0xFFFF then return 0xFFFF end    -- #359: saturates at $ffff
  end
  return v
end

local function laterDamaging()
  local n = 0
  for _, s in ipairs(steps) do
    if s.later and s.dancing and s.base > 0 then n = n + 1 end
  end
  return n
end

-- one branch of the second wave from the snapshot at MOG's command window:
-- idle `wait` frames there (the battle RNG steps with every battle-loop
-- frame, so each branch is its own draw of dance steps and monster turns),
-- then boost, dance and run the battle to its end.  Branches stop once a
-- later step has dealt damage; every branch's steps are checked.
local snap = nil
local function branch(k, wait)
  local req
  return H.cond(function() return laterDamaging() == 0 end, {
    H.call(function() H.setPad({}); req = H.requestLoadState(snap.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load (branch " .. k .. ")")
      H.rearmInputInjection()
      branches = branches + 1
      cur = nil
      H.log(string.format("[danceboost] branch %d: %d idle frames at MOG's window", k, wait))
    end),
    H.waitFrames(wait + 1),
    raiseBoost("R to boost " .. BOOST),
    openDance("the dance list opens"),
    H.waitFrames(20),
    danceCursorToKnown("cursor onto the learned dance's cell"),
    H.call(function()
      startMp, startBank = mpOf(mogSlot), bp(mogSlot)
      startMps[branches] = startMp
      H.log(string.format("[danceboost] confirm: pending %d, bank %d, %d MP",
        pend(mogSlot), startBank, startMp))
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
    H.driveUntil(function() return not H.battleLoadStarted() end, 40000, {
      H.call(function()
        ph = ph + 1
        if not H.battleLoadStarted() or H.readByte(MENU) == 0 then
          H.setPad(ph % 8 < 4 and { a = true } or {})
        elseif H.readByte(ACTOR) ~= mogSlot then bystander()
        else H.setPad({}) end
      end),
      H.waitFrames(1),
    }, "the dance battle runs to its end"),
    H.call(function()
      H.log(string.format("[danceboost] branch %d over: %d boost calls so far, "
        .. "%d later damaging steps", k, #steps, laterDamaging()))
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
  -- P2's first wave teaches the dance
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
    H.assertEq(H.readByte(DANCES) & (1 << danceId) ~= 0, true,
      "the victory taught the background's dance")
  end),
}
-- the second wave: MOG's first command window is the branch point
body[#body + 1] = untilP2Battle("the west arm's second wave engages MOG's squad")
body[#body + 1] = H.waitFrames(240)
body[#body + 1] = H.call(function()
  findMog()
  local bg = H.readByte(0x11E2)
  H.assertEq(H.readRomByte((H.sym("BattleBGDance") & 0x3FFFFF) + bg), danceId,
    "same terrain, same dance: the bg-mismatch stumble cannot fire")
  H.log(string.format("[danceboost] second wave: MOG slot %d, %d MP, %d BP",
    mogSlot, mpOf(mogSlot), bp(mogSlot)))
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
for k = 1, BRANCHES do body[#body + 1] = branch(k, (k - 1) * 9) end
body[#body + 1] = H.call(function()
  H.setPad({})
  for i, s in ipairs(steps) do
    H.log(string.format("[danceboost] step %d f%d branch %d %s pending=%d "
      .. "dancing=%s bank=%d base=%d -> %d (x%s)", i, s.f, s.branch,
      s.later and "later" or "start", s.pend, tostring(s.dancing),
      s.bank, s.base, s.final,
      s.base > 0 and string.format("%.2f", s.final / s.base) or "-"))
  end
  local start, later, wrong = nil, 0, {}
  for _, s in ipairs(steps) do
    if not s.later and not start then start = s end
    if s.base > 0 then
      local want = multiplied(s.base, BOOST)
      if s.final ~= want then wrong[#wrong + 1] = s end
      if s.later and s.dancing then later = later + 1 end
    end
  end
  local spends, charges = 0, {}
  for i, e in ipairs(ends) do
    H.log(string.format("[danceboost] action end %d f%d (branch %d): pending "
      .. "%d, bank %d, MP %d", i, e.f, e.branch, e.pend, e.bank, e.mp))
    if e.pend ~= 0 then spends = spends + 1 end
    if e.start then
      charges[#charges + 1] = (startMps[e.branch] or -1) - e.mp
    end
  end
  H.log(string.format("[danceboost] SUMMARY branches=%d calls=%d later "
    .. "damaging steps=%d not x%d=%d; start MP %d bank %d; dancing turn ends "
    .. "%d, of them spending pips %d", branches, #steps, later, 1 << BOOST,
    #wrong, startMp or -1, startBank or -1, #ends, spends))
  H.assertEq(start ~= nil, true, "the dance's start step was observed")
  H.assertEq(start.pend, BOOST,
    "the start step ran with MOG's pending boost at " .. BOOST)
  H.assertEq(start.dancing, true, "and the dance locked in on it")
  H.assertEq(#charges, branches, "every branch's dance start turn ended")
  H.assertEq(later > 0, true,
    "at least one LATER step dealt damage (without it nothing after the "
    .. "first step was measured)")
  H.assertEq(#wrong, 0, string.format(
    "every damaging step of the boosted dance came back x%d, the start and "
    .. "each later step alike (#294)", 1 << BOOST))
  for i, c in ipairs(charges) do
    H.assertEq(c, H.boostPrice(8, BOOST), string.format(
      "dance start %d charged the boost-%d price from the real pool", i, BOOST))
  end
  H.assertEq(#ends > branches, true,
    "the dance ran past its start: more dancing turn ends than starts")
  H.assertEq(spends, branches,
    "pips were spent once per dance, at its start (one per branch); every "
    .. "later step ended with nothing pending, so it spent none")
end)

H.run({ maxFrames = 400000 }, body)
