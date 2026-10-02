-- @suite slow
-- battle_passretarget.lua -- a pass OT6 added to an action goes to another
-- monster when the one it was on has fallen, and never to the party
-- (guidelines.md "Boost pays once"; kits.md "a hire that outlives its
-- target goes to another body"; ot6_passes.asm).
--
-- OT6 buys extra passes of an action through the engine's multi-hit counter
-- $3a70: a boosted Fight or Capture (two swings a point), Setzer's Coin Toss,
-- Hired Help and Jackpot (one toss, hire or roll a point), Pummel, Bum Rush
-- and Drill (Ot6HitCountTbl), a dumped Throw.  Vanilla's loop does not
-- retarget a pass whose body fell on the pass before: a hire's next pass
-- landed nowhere and the one after retargeted (wt/hire-sprite: a 3 BP Hired
-- Help on three bodies landed passes 1 and 3), and a Fight's later swings
-- went to the corpse (Fight's targeting puts an emptied mask back on the
-- backup targets, $3a4e) or nowhere, while a body still stood.
--
-- Played, no writes: Continue the wor-tomb-v1 battery, walk Darill's Tomb's
-- east room into random battles (field group 151: a Mad Oscar; a Mad Oscar
-- and an Exoray; a PowerDemon and two Exorays) and fight each out with the
-- route's fight driver (boost on: every member boost-Fights at what it has
-- banked; SABIN's Blitz is Pummel), care after each.  In a crowd (two or
-- more monsters, one special-weak) past the first PASS_SKIP, SETZER first
-- plays each kind still unmet through the real menu (H.setzerBattle, whose
-- confirm lands only on the target asked for), each from the battle's
-- opening snapshot (TESTING.md: branch one legitimately reached state):
--   hire:    Hired Help at 1 BP on the weakest body: a hire lands 1,550 on
--            a shielded body at L31 (kits.md) and an Exoray has 1,200 HP, so
--            the first hire kills it and the second must find another body;
--   jackpot: Jackpot at 1 BP on the default target (a face of 3 or more,
--            2,511 shielded at L31, kills any body of the crowd at full HP);
--   resplit: Hired Help unboosted on the strongest body (2,058 -> 458 on a
--            PowerDemon), then Coin Toss at 2 BP over the group, so a toss
--            fells one body and the next splits over the rest; or Coin Toss
--            at 1 BP over a crowd the party's swings have worn down.
-- A kind gets two candidates a crowd (three for the re-split): the rest of
-- the party Defends until SETZER has thrown, or Fights (moving the battle
-- RNG and the bodies' HP).  The last candidate played goes on to the fight
-- driver.  PASS_SKIP (default 0) crowds are fought out first, to vary the
-- draw: the encounters they use up move the formations and keys every
-- later battle meets.
--
-- The instrument and its checks are the library's (M.passWatch,
-- M.passCheck): every pass of every character's action, and for an action
-- OT6 extended F (stays on the monster side), A (lands on a body while one
-- stands), D (a group's survivors: the coins re-split), B (standing bodies
-- only), C (one body for a one-body action), G (once the monster side has
-- emptied, no party member), H (a pass that starts on a party member
-- spreads to no other one) and E (a Setzer row runs 1 + boost passes), and
-- vanilla's own two-hand Fight rule.  G and H are met here only when the
-- draw deals them; battle_passside makes them on purpose.
-- The draws the property needs, each kind or the suite fails naming it: a
-- pass whose starting body has fallen while another stands, for Hired
-- Help, Jackpot and a boosted Fight, and a Coin Toss pass whose group lost
-- a body and kept another.  The budget: a crowd within
-- M.setzerCrowdBudget's decoded worst case of the last, and per kind (the
-- plans' comments give the measured basis) at most `crowds` crowds; a
-- boosted Fight's within FIGHTAFTER battles of SETZER's last.  Each
-- battle's key ($be at the open and the formation) is logged, and the
-- draws are counted by distinct key.
-- Negative controls: the ROM before the fix (PASS_TALLY) and the mutant
-- ROMs in build/attempts/wt/pass-retarget/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

PASS_SKIP = PASS_SKIP or 0
local COIN, HIRE, JACKPOT = 0x59, 0x5A, 0x5B
local DRILL = 0xA8                     -- the Drill's item id (Ot6HitCountTbl: x2)
local TAG = "passretarget"

-- the standing monster slot with the least (or most) HP, read when the
-- cursor needs it
local function pick(most)
  local best, hp = nil, nil
  local m = H.passStanding()
  for s = 0, 5 do
    if (m >> s) & 1 == 1 then
      local h = H.readWord(0x3BFC + s * 2)
      if hp == nil or (most and h > hp) or (not most and h < hp) then best, hp = s, h end
    end
  end
  return best
end
local function aimed(t, most)
  return setmetatable(t, { __index = function(_, k) if k == "slot" then return pick(most) end end })
end

local EVENTS = { "hire", "jackpot", "coin", "fight", "blitz", "tool", "gprain" }
local seen = { resplit = {}, vanilla = {}, emptied = {}, party = {} }
for _, k in ipairs(EVENTS) do seen[k] = {} end
local function note(event, kind, key0, what)
  local k = event == "retarget" and kind or event
  if seen[k] then seen[k][key0 or "?"] = (seen[k][key0 or "?"] or 0) + 1 end
  H.log(string.format("[%s]   %s: %s", TAG, event, what))
end

-- PASS_TALLY (a lab switch, off in the suite): count each failed check by
-- assertion, kind and battle key and play on, so one run on an old or
-- mutant ROM shows where across its draws the rule breaks
PASS_TALLY = PASS_TALLY or false
local tally = {}
local function want(got, exp, what, kind, key0)
  if not PASS_TALLY then return H.assertEq(got, exp, what) end
  if got ~= exp then
    local t = what:match("^(%u):") or what:sub(1, 8)
    local k = string.format("%s %s %s", t, kind, key0 or "?")
    tally[k] = (tally[k] or 0) + 1
    H.log(string.format("[%s] TALLY fail: %s (got %s, want %s)", TAG, what, tostring(got), tostring(exp)))
  end
end

local PW = nil
local checked = 0
-- judged off the callbacks (an assertion inside one would not stop the run)
local judgedN = 0
local function judgeNew()
  while judgedN < #PW.acts do
    judgedN = judgedN + 1
    local a = H.passCheck(PW.acts[judgedN], want, note, TAG)
    if a.ext then checked = checked + 1 end
  end
end

-- ---- the walk ------------------------------------------------------------
-- SETZER's plans, one kind at a time, each played from the crowd battle's
-- opening snapshot on SETZER's first turn, or his first two for the
-- re-split.  A kind that misses its draw in every candidate -- the kill
-- came on the last pass, a counter felled the crowd, SETZER was turned to a
-- zombie before his turn -- tries again in the next crowd, up to its
-- `crowds`.  The bounds' basis (the eight-variation sweep in
-- build/attempts/wt/pass-retarget/sweep/):
--   hire, 4: the first hire kills the weakest body whenever SETZER has his
--     first turn on the crowd (the damage arithmetic above); met in the
--     first crowd in 8 of 8 variations;
--   jackpot, 6: a face of 3+ is 4 of 6; met in the first crowd in 7 of 8;
--   resplit, 10: met in 6 of 12 crowds tried (by key), so a miss within ten
--     is about 0.5^10 = 0.1%.
local function aim(e, how)
  if how == nil then return e end
  return aimed(e, how == "strong")
end
local function cands(fn, more)
  local t = { { others = "defend", fn = fn }, { others = "fight", fn = fn } }
  if more then t[#t + 1] = more end
  return t
end
local PLANS = {
  { kind = "hire", crowds = 4, cands = cands(function() return { aim({ row = HIRE, boost = 1 }, "weak") } end) },
  { kind = "jackpot", crowds = 6, cands = cands(function() return { { row = JACKPOT, boost = 1 } } end) },
  { kind = "resplit", crowds = 10, cands = cands(function() return { aim({ row = HIRE, boost = 0 }, "strong"),
    { row = COIN, boost = 2 } } end, { others = "fight", fn = function() return { { row = COIN, boost = 1 } } end }) },
}
local tries, throws, crowdsFor = {}, {}, {}
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function pending()
  local t = {}
  for _, p in ipairs(PLANS) do if count(seen[p.kind]) == 0 then t[#t + 1] = p end end
  return t
end
local W, since, battles, crowds = nil, 0, 0, 0
-- a boosted Fight's draw (a swing whose body fell while another stands)
-- within FIGHTAFTER battles of SETZER's kinds: the sweep met it before
-- SETZER's kinds were done in every variation (the fight-outs between his
-- crowds deal it), so 8 is a stated margin, not a measured tail
local FIGHTAFTER = 8
local setzerDoneAt = nil
local function allSeen()
  if #pending() > 0 then return false end
  setzerDoneAt = setzerDoneAt or battles
  if count(seen.fight) > 0 then return true end
  H.assertEq(battles - setzerDoneAt < FIGHTAFTER, true, string.format("fight: the draw this needs (a boosted swing "
    .. "whose body fell while another stands) within %d battles after SETZER's (none in %d battles)", FIGHTAFTER,
    battles))
  return false
end

local wp = 1
local WPS = { { 124, 26 }, { 120, 11 } }

local function crowdHere()
  local alive, weak = 0, 0
  local mask = H.readByte(0x3A75)
  for b = 0, 5 do
    if (mask >> b) & 1 == 1 then
      alive = alive + 1
      if (H.readByte(0x3EA4 + b * 2) & 0x08) ~= 0 and H.readByte(0x3E40 + b * 2) > 0 then weak = weak + 1 end
    end
  end
  return alive >= 2 and weak >= 1, alive
end

-- one battle: SETZER's pending kinds from its opening snapshot (a crowd past
-- PASS_SKIP), then the fight driver to its end
local function play()
  local S = {}
  local function fresh() S = { phase = "start" } end
  fresh()
  return { tick = function()
    if S.phase == "start" then
      local crowd, alive = crowdHere()
      S.kinds = (crowd and crowds >= PASS_SKIP) and pending() or {}
      H.log(string.format("[%s] battle %d, key %s: %d monster(s)%s -- %s", TAG, battles, PW.key, alive,
        crowd and ", a crowd" or "", #S.kinds > 0 and ("SETZER plays " .. (function()
          local t = {} for _, p in ipairs(S.kinds) do t[#t + 1] = p.kind end return table.concat(t, ", ") end)())
        or "fight it out"))
      if crowd then crowds, since = crowds + 1, 0 end
      if #S.kinds == 0 then S.phase = "fight" else S.req, S.phase = H.requestSaveState(), "snap" end
    end
    if S.phase == "snap" then
      if not S.req.done then return "frame" end
      H.checkReq(S.req, "the crowd battle's opening snapshot")
      S.blob, S.ki, S.try, S.phase = S.req.blob, 1, 1, "stand"
    end
    if S.phase == "restore" then
      if not S.req.done then return "frame" end
      H.checkReq(S.req, "restoring the crowd battle's opening snapshot")
      PW.open = {}
      S.phase = "stand"
    end
    if S.phase == "stand" then
      local p = S.kinds[S.ki]
      local c = p.cands[S.try]
      S.mark = #PW.acts
      H.log(string.format("[%s] %s, crowd %d of %d, candidate %d of %d: the party %ss until SETZER has thrown",
        TAG, p.kind, (crowdsFor[p.kind] or 0) + 1, p.crowds, S.try, #p.cands, c.others))
      S.step, S.phase = H.setzerBattle(c.fn(c), { untilPlanDone = true, othersFight = c.others == "fight" }), "plan"
    end
    if S.phase == "plan" then
      local r = S.step:tick()
      judgeNew()
      -- SETZER out before his throw (Wounded, Petrified or a Zombie;
      -- Berserk, Muddled or asleep; Stopped): the party would Defend on
      -- waiting for a turn that cannot come, so this candidate ends here
      if r ~= "done" then
        local out = nil
        for e = 0, 6, 2 do
          if H.readByte(0x3ED8 + e) == 9 then
            local s1, s2, s3 = H.readByte(0x3EE4 + e), H.readByte(0x3EE5 + e), H.readByte(0x3EF8 + e)
            if (s1 & 0xC2) ~= 0 or (s2 & 0xB0) ~= 0 or (s3 & 0x10) ~= 0 then
              out = string.format("status %02X %02X %02X", s1, s2, s3)
            end
          end
        end
        if out == nil or not H.battleLoadStarted() then return r end
        H.log(string.format("[%s] SETZER cannot act (%s): this candidate ends", TAG, out))
        H.setPad({})
      end
      local p = S.kinds[S.ki]
      local sig = {}
      for n = S.mark + 1, #PW.acts do
        if PW.acts[n].cmd == 0x0F then
          for _, q in ipairs(PW.acts[n].passes) do sig[#sig + 1] = string.format("%04X>%04X", q.pre, q.post or 0) end
        end
      end
      sig = table.concat(sig, " ")
      throws[p.kind] = throws[p.kind] or {}
      if sig ~= "" then throws[p.kind][sig] = true end   -- "": SETZER never threw
      tries[p.kind] = (tries[p.kind] or 0) + 1
      local met = count(seen[p.kind]) > 0
      H.log(string.format("[%s] %s, try %d: %s | %s | %d distinct throw(s) so far", TAG, p.kind, S.try,
        met and "the draw is met" or "no draw", sig, count(throws[p.kind])))
      if met then
        S.ki, S.try = S.ki + 1, 1
      elseif S.try < #p.cands then
        S.try = S.try + 1
      else
        crowdsFor[p.kind] = (crowdsFor[p.kind] or 0) + 1
        H.assertEq(crowdsFor[p.kind] < p.crowds, true, string.format("%s: the draw this needs (a pass whose body "
          .. "fell while another stands) within %d crowds, %d candidates each (%d distinct throws)", p.kind,
          p.crowds, #p.cands, count(throws[p.kind])))
        S.ki, S.try = S.ki + 1, 1
      end
      if S.ki <= #S.kinds then
        S.req, S.phase = H.requestLoadState(S.blob), "restore"
        return "frame"
      end
      S.phase = "fight"
      if not H.battleLoadStarted() then return "done" end
    end
    if S.F == nil then
      -- the route's driver, but SABIN's Blitz is Pummel (x2) and EDGAR's
      -- Tool the Drill (x2) when the bag holds one, whatever the chip model
      -- would key (keyed = false), so their OT6 passes meet the draws too
      S.F = H.newFightDriver(TAG .. " fight " .. battles, { tactical = true, boost = true, items = true, bank = 0,
        healPercent = 55, setzer = false, keyed = false, tool = DRILL })
    end
    judgeNew()
    if not H.battleLoadStarted() then return "done" end
    S.F.frame()
    return "frame"
  end, reset = function() fresh() end }
end

local steps = {
  H.call(function()
    battles, since = battles + 1, since + 1
    H.assertEq(since <= W, true, string.format("a crowd within %d encounters of the last (the worst of the 65536 "
      .. "counter states); this is encounter %d since", W, since))
  end),
  H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
    H.navTo(function() return WPS[wp][1] end, function() return WPS[wp][2] end,
      { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() wp = wp % #WPS + 1 end),
  }, "a random battle"),
  H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 2),
  H.call(function()
    PW.key = string.format("%02X/%03X", PW.seed0 or 0xFF, H.readWord(0x11E0))
  end),
  play(),
  H.waitFrames(60),
  H.call(judgeNew),
  H.careStop(TAG .. " care after the battle"),
}

H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function()
    PW = H.passWatch()
    W = H.setzerCrowdBudget(H.fieldEncounterGroup(H.mapId() & 0x1ff), TAG)
  end),
  H.driveUntil(function() return allSeen() end, 2200000, steps,
    "every kind meets a pass whose body fell while another stands"),
  H.call(function()
    judgeNew()
    local t = {}
    for _, k in ipairs({ "hire", "jackpot", "coin", "fight", "resplit", "blitz", "tool", "gprain", "emptied",
        "party", "vanilla" }) do
      local n, d = 0, 0
      for _, c in pairs(seen[k]) do n, d = n + c, d + 1 end
      t[#t + 1] = string.format("%s %d pass(es) over %d distinct key(s)", k, n, d)
    end
    if PASS_TALLY then
      local tt, n = {}, 0
      for k, c in pairs(tally) do tt[#tt + 1] = string.format("%s x%d", k, c); n = n + c end
      table.sort(tt)
      H.log(string.format("[%s] TALLY: %d failed check(s): %s", TAG, n, table.concat(tt, "; ")))
    end
    H.log(string.format("[%s] PASSED: %d extended action(s) held, over %d battle(s) (%d crowds); %s", TAG, checked,
      battles, crowds, table.concat(t, "; ")))
  end),
})
