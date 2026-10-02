-- @suite slow
-- battle_passretarget.lua -- a pass OT6 added to an action goes to another
-- body when the one it was on has fallen (guidelines.md "Boost pays once";
-- kits.md "a hire that outlives its target goes to another body").
--
-- OT6 buys extra passes of an action through the engine's multi-hit counter
-- $3a70: a boosted Fight or Capture (two swings a point), Setzer's Coin Toss,
-- Hired Help and Jackpot (one toss, hire or roll a point), Pummel, Bum Rush
-- and Drill (Ot6HitCountTbl), a dumped Throw.  Vanilla's loop does not
-- retarget a pass whose body fell on the pass before: a hire's next pass
-- landed nowhere and the one after retargeted (wt/hire-sprite: a 3 BP Hired
-- Help on three bodies landed passes 1 and 3), and a Fight's every later
-- swing went to the corpse (Fight's targeting puts an emptied mask back on
-- the backup targets, $3a4e), while a body still stood.
--
-- Played, no writes: Continue the wor-tomb-v1 battery, walk Darill's Tomb's
-- east room into random battles (field group 151: a Mad Oscar; a Mad Oscar
-- and an Exoray; a PowerDemon and two Exorays) and fight each out with the
-- route's fight driver (boost on: every member boost-Fights at what it has
-- banked), care after each.  In a crowd (two or more monsters, one
-- special-weak) past the first PASS_SKIP, SETZER first plays each kind still
-- unmet through the real menu (H.setzerBattle), each from the battle's
-- opening snapshot (TESTING.md: branch one legitimately reached state):
--   hire:    Hired Help at 1 BP on the weakest body (a hire kills an Exoray,
--            1,200 HP, so the next must find another body);
--   jackpot: Jackpot at 1 BP on the default target (a face of 3 or more
--            kills any body of the crowd);
--   resplit: Hired Help unboosted on the strongest body (2,058 -> 458 on a
--            PowerDemon), then Coin Toss at 2 BP over the group, so a toss
--            fells one body and the next splits over the rest; or Coin Toss
--            at 1 BP over a crowd the party's swings have worn down.
-- A kind gets two candidates a crowd (three for the re-split): the rest of
-- the party Defends until SETZER has thrown, or Fights (moving the battle
-- RNG and the bodies' HP).  What does not move a throw (measured, the
-- suite's own labs): the frames the party stands before its first input
-- (the battle waits while a command window is open), and SETZER Defending
-- first (in the tomb's crowds his second turn rarely came).  The last
-- candidate played goes on to the fight driver.  PASS_SKIP (default 0)
-- crowds are fought out first, to vary the draw: the encounters they use
-- up move the formations and keys every later battle meets.
--
-- The instrument, every action of every character: each pass at
-- CalcAttackEffect's ChooseTarget (the mask it starts with, at
-- Ot6Life3Targeting's entry just before; the mask it chose, at
-- Ot6Oblivion's entry just after) and which monsters stand there
-- (CheckTargetsPresent's test).  An action OT6 extended is a Fight or
-- Capture whose first pass counts above vanilla's (one, or seven with
-- Offering: the player's boost or an engine-driven actor's dumped bank), a
-- Setzer row or a character's GP Rain at 1 BP or more, or a Blitz or Tool
-- with a row in the ROM's Ot6HitCountTbl.  For each of its passes after the
-- first that starts on monsters while a monster stands (a weapon's
-- follow-up spell, $b5 = $02, keeps vanilla's "same target" and is not one):
--   F. the pass stays on the side its target was on, the monsters (a
--      muddled actor's Retarget would turn on the party);
--   A. it lands on a body (its mask is not empty);
--   D. a pass that starts on a group with a fallen body lands on the
--      group's survivors: the coins re-split over the bodies left;
--   B. on standing bodies only;
--   C. one body, for the one-body actions (Fight, Capture, Hired Help,
--      Jackpot, Pummel, Bum Rush, Drill);
--   E. a Setzer row runs 1 + boost passes: the retarget buys no pass.
-- And vanilla's own, whenever the run meets one: an unboosted two-hand
-- Fight (a Genji pair, two passes) keeps vanilla's rule, its second hand
-- swinging at the body the first hand felled.
-- The draws the property needs, each kind or the suite fails naming it: a
-- pass whose starting body has fallen while another stands, for Hired
-- Help, Jackpot and a boosted Fight, and a Coin Toss pass whose group lost
-- a body and kept another.  The budget: a crowd within
-- M.setzerCrowdBudget's decoded worst case of the last; the kind's crowds
-- (4, 6, 10); a boosted Fight's within FIGHTAFTER battles of SETZER's last.  Each
-- battle's key ($be at the open and the formation) is logged, and the
-- draws are counted by distinct key.
-- Negative controls: the ROM before the fix and the mutant ROMs in
-- build/attempts/wt/pass-retarget/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

PASS_SKIP = PASS_SKIP or 0
local COIN, HIRE, JACKPOT = 0x59, 0x5A, 0x5B
local DRILL = 0xA8                     -- the Drill's item id (Ot6HitCountTbl: x2)
local SETZERROW = 0xEDCD               -- OT6_SETZERROW (ot6_memory.inc)
local MARK = 0xEDCE                    -- OT6_PASSRETARGET: logged, never asserted
local TAG = "passretarget"

local function bits(m)
  local n = 0
  while m ~= 0 do n = n + (m & 1); m = m >> 1 end
  return n
end

-- the monsters ChooseTarget would keep: present ($3AA0+x bit 0), in the
-- battle's target mask ($3A78 high byte), not Wounded, Petrified or Zombie
-- ($3EE4+x & $C2: a monster's test) and not hidden ($3EF9+x bit 5) --
-- CheckTargetsPresent's test, x = 8 + 2s.  (A petrified body keeps its HP
-- and stays present: measured, a Mad Oscar at 1,266 HP with $3EE4 = $40.)
local function standing()
  local m, tm = 0, H.readByte(0x3A79)
  for s = 0, 5 do
    local x = 8 + s * 2
    if (H.readByte(0x3AA0 + x) & 1) == 1 and ((tm >> s) & 1) == 1 and (H.readByte(0x3EE4 + x) & 0xC2) == 0
        and (H.readByte(0x3EF9 + x) & 0x20) == 0 then
      m = m | (1 << s)
    end
  end
  return m
end

-- the standing monster slot with the least (or most) HP, read when the
-- cursor needs it
local function pick(most)
  local best, hp = nil, nil
  local m = standing()
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

-- ---- the instrument ------------------------------------------------------
local hitTbl = nil
local function hitCountIds()
  if hitTbl then return hitTbl end
  hitTbl = {}
  local t = H.sym("Ot6HitCountTbl") & 0x3FFFFF
  for i = 0, 63 do
    local id = H.readRomByte(t + i * 2)
    if id == 0xFF then break end
    hitTbl[id] = H.readRomByte(t + i * 2 + 1)
  end
  return hitTbl
end

local acts, open, key = {}, {}, nil
local KIND = { [0x00] = "fight", [0x06] = "capture", [0x0A] = "blitz", [0x09] = "tool", [0x18] = "gprain" }
local function kindOf(a)
  if a.cmd == 0x0F then
    return ({ [COIN] = "coin", [HIRE] = "hire", [JACKPOT] = "jackpot" })[a.row] or "slot"
  end
  return KIND[a.cmd] or string.format("cmd%02X", a.cmd or 0xFF)
end
local ONE = { fight = true, capture = true, hire = true, jackpot = true, blitz = true, tool = true }
-- a Fight's or Capture's own count: one pass a hand, eight with Offering
-- (FightAttack: $3a70 = 1, or 7 when $3C58 bit 0); what the first pass
-- finds above that is OT6's, two a point -- the player's boost or an
-- engine-driven actor's dumped bank (Ot6Retaliate), which the pending byte
-- at ExecCmd does not show
local function fightBase(a) return a.offering and 7 or 1 end
local function extended(a)
  local k = a.kind
  if k == "fight" or k == "capture" then return a.passes[1].a70 > fightBase(a) end
  if k == "gprain" or k == "coin" or k == "hire" or k == "jackpot" then return a.boost >= 1 end
  if k == "blitz" or k == "tool" then return a.ab ~= nil and hitCountIds()[a.ab] ~= nil end
  return false
end

local seen = { hire = {}, jackpot = {}, coin = {}, fight = {}, resplit = {}, vanilla = {}, blitz = {}, tool = {},
  gprain = {} }
local checked = { acts = 0, passes = 0 }
local function note(k, key0) seen[k][key0 or "?"] = (seen[k][key0 or "?"] or 0) + 1 end

local function judge(a)
  a.kind = kindOf(a)
  local ext = extended(a)
  if a.kind == "fight" or a.kind == "capture" then a.boost = (a.passes[1].a70 - fightBase(a)) // 2 end
  local lines = {}
  for p, q in ipairs(a.passes) do
    lines[#lines + 1] = string.format("p%d $3A70=%d mark=%d b5=%02X ba=%02X bb=%02X in $%04X stand %02X -> $%04X", p,
      q.a70, q.mark, q.b5, q.ba, q.bb, q.pre, q.stand, q.post or 0xFFFF)
  end
  H.log(string.format("[%s] %s by e%d at %d BP%s%s, %d pass(es), key %s: %s", TAG, a.kind, a.e, a.boost,
    a.ab and string.format(" (id $%02X)", a.ab) or "", a.offering and " (Offering)" or "", #a.passes, a.key or "?",
    table.concat(lines, "; ")))
  if a.cmd == 0x0F and a.row and a.row >= COIN and a.row <= JACKPOT and a.boost >= 1 then
    H.assertEq(#a.passes, 1 + a.boost, string.format("E: %s at %d BP runs 1 + boost passes", a.kind, a.boost))
  end
  -- the action's own passes: not a weapon's follow-up spell ($b5 = $02,
  -- which keeps vanilla's "same target"; the rows' own $b5 moves with their
  -- animation, Jackpot's to the dice' $26)
  local famN = 0
  for _, q in ipairs(a.passes) do if q.b5 ~= 0x02 then famN = famN + 1 end end
  for p, q in ipairs(a.passes) do
    -- a pass after the first, of the action's own, starting on monsters
    -- only, while a monster stands
    if p >= 2 and q.b5 ~= 0x02 and q.post ~= nil and q.pre ~= 0 and (q.pre & 0xFF) == 0 and q.stand ~= 0 then
      local pre, post, stand = q.pre >> 8, q.post >> 8, q.stand
      local fell = pre & ~stand & 0x3F
      local what = string.format("%s by e%d at %d BP, pass %d of %d (key %s; started on $%02X, standing $%02X, "
        .. "landed on $%04X)", a.kind, a.e, a.boost, p, #a.passes, a.key or "?", pre, stand, q.post)
      if ext then
        checked.passes = checked.passes + 1
        H.assertEq(q.post & 0xFF, 0, "F: a pass OT6 added stays on the side its target was on (the monsters) -- "
          .. what)
        H.assertEq(post ~= 0, true, "A: it lands on a body while one stands -- " .. what)
        if bits(pre) >= 2 and (pre & stand) ~= 0 then
          H.assertEq(post, pre & stand, "D: a group pass lands on the group's survivors -- " .. what)
        end
        H.assertEq(post & ~stand & 0x3F, 0, "B: it lands on standing bodies only -- " .. what)
        if ONE[a.kind] then
          H.assertEq(bits(post), 1, "C: a one-body action's pass lands on one body -- " .. what)
        end
        if (pre & stand) == 0 then
          if seen[a.kind == "capture" and "fight" or a.kind] then note(a.kind == "capture" and "fight" or a.kind, a.key) end
          H.log(string.format("[%s]   retarget: %s", TAG, what))
        end
        if a.kind == "coin" and bits(pre) >= 2 and fell ~= 0 and (pre & stand) ~= 0 then
          note("resplit", a.key)
          H.log(string.format("[%s]   re-split: %s", TAG, what))
        end
      elseif a.kind == "fight" and famN == 2 and (q.ba & 0x40) == 0 and (pre & stand) == 0 then
        -- vanilla's own two passes (a Genji pair, one a hand): Fight's
        -- targeting ($ba bit 5, CmdTargetTbl) puts an emptied mask back on
        -- the backup targets ($3a4e), so the second hand swings at the body
        -- the first hand felled
        H.assertEq(q.post, q.pre, "vanilla: an unboosted two-hand Fight's second hand swings at the body the first "
          .. "hand felled -- " .. what)
        note("vanilla", a.key)
        H.log(string.format("[%s]   vanilla: %s", TAG, what))
      end
    end
  end
  if ext then checked.acts = checked.acts + 1 end
end

-- the battle's seed as InitBattle sets it ($021e << 2 into $be, just before
-- its jsr LoadBattleProp): with the formation, the battle's key
local seed0 = nil
local function arm()
  local lb = H.sym("LoadBattleProp")
  emu.addMemoryCallback(function() seed0 = H.readByte(0xBE) end, emu.callbackType.exec, lb, lb)
  local ec = H.sym("ExecCmd@battle_code")
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xff
    if x >= 8 then return end
    open[x] = { e = x, boost = H.readByte(0x3E9D + x), passes = {}, key = key, f = H.frame,
      offering = (H.readByte(0x3C58 + x) & 1) == 1 }
  end, emu.callbackType.exec, ec, ec)
  -- the Blitz or Tool id, as Cmd_0a / Cmd_09 hand it to Ot6HitCount (A; y =
  -- the attacker): a failed Blitz input arrives as Pummel's
  local hc = H.sym("Ot6HitCount")
  emu.addMemoryCallback(function()
    local y = emu.getState()["cpu.y"] & 0xff
    if open[y] then open[y].ab = emu.getState()["cpu.a"] & 0xff end
  end, emu.callbackType.exec, hc, hc)
  local pre = H.sym("Ot6Life3Targeting")
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xff
    local a = open[x]
    if not a then return end
    if a.cmd == nil then
      a.cmd = H.readByte(0x3A7C)
      if a.cmd == 0x0F then a.row = H.readByte(SETZERROW) end
    end
    a.passes[#a.passes + 1] = { pre = H.readByte(0xB8) | (H.readByte(0xB9) << 8), stand = standing(),
      a70 = H.readByte(0x3A70), b5 = H.readByte(0xB5), ba = H.readByte(0xBA), bb = H.readByte(0xBB),
      mark = H.readByte(MARK) }
  end, emu.callbackType.exec, pre, pre)
  local post = H.sym("Ot6Oblivion")
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xff
    local a = open[x]
    local q = a and a.passes[#a.passes]
    if q and q.post == nil then q.post = H.readByte(0xB8) | (H.readByte(0xB9) << 8) end
  end, emu.callbackType.exec, post, post)
  local fin = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xff
    local a = open[x]
    if not a then return end
    open[x] = nil
    if #a.passes >= 1 then acts[#acts + 1] = a end
  end, emu.callbackType.exec, fin, fin)
end

-- judged off the callbacks (an assertion inside one would not stop the run)
local judgedN = 0
local function judgeNew()
  while judgedN < #acts do
    judgedN = judgedN + 1
    judge(acts[judgedN])
  end
end

-- ---- the walk ------------------------------------------------------------
-- SETZER's plans, one kind at a time, each played from the crowd battle's
-- opening snapshot (TESTING.md: branch one legitimately reached state into
-- experiments) on SETZER's first turn, or his first two for the re-split.
-- One battle gives a kind two candidates: the rest of the party Defends
-- until SETZER has thrown, or Fights (unboosted), which moves the battle RNG
-- and the bodies' HP before his turn.  A kind that misses its draw in both
-- -- the kill came on the last pass, a counter felled the crowd, SETZER was
-- turned to a zombie before his turn -- tries again in the next crowd, up
-- to the kind's crowds.  The bounds are the measured rates' (eight entry
-- variations, wt/pass-retarget's sweep): a hire met its draw in the first
-- crowd every time (4 allowed); a Jackpot in 7 of 8 first crowds (6); the
-- re-split in 8 of 15 crowds tried (10: about 0.47^10 = 0.05% to miss).  What does not vary a throw (measured): the frames the
-- party stands before the first input (eight stands of 0-840 frames gave
-- one Jackpot throw: the battle waits while a command window is open), and
-- SETZER Defending first to bank more (in the tomb's crowds a second turn
-- rarely came: he was felled or turned to a zombie first).
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
  -- a hire kills an Exoray (1,200 HP; 1,550 shielded at L31), so the next
  -- must find another body
  { kind = "hire", crowds = 4, cands = cands(function() return { aim({ row = HIRE, boost = 1 }, "weak") } end) },
  -- a face of 3 or more kills any body of the crowd at full HP; the throw
  -- goes to the default target (an aim the cursor walk cannot reach falls
  -- back to confirming where the cursor stands: once a party member)
  { kind = "jackpot", crowds = 6, cands = cands(function() return { { row = JACKPOT, boost = 1 } } end) },
  -- a hire takes most of the strongest body (2,058 -> 458 on a
  -- PowerDemon), so a toss over the group fells it and the next splits;
  -- or, on SETZER's first turn, two tosses over a crowd the party's swings
  -- have worn down
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
      H.log(string.format("[%s] battle %d, key %s: %d monster(s)%s -- %s", TAG, battles, key, alive,
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
      open = {}
      S.phase = "stand"
    end
    if S.phase == "stand" then
      local p = S.kinds[S.ki]
      local c = p.cands[S.try]
      S.mark = #acts
      H.log(string.format("[%s] %s, crowd %d of %d, candidate %d of %d: the party %ss until SETZER has thrown",
        TAG, p.kind, (crowdsFor[p.kind] or 0) + 1, p.crowds, S.try, #p.cands, c.others))
      S.step, S.phase = H.setzerBattle(c.fn(c), { untilPlanDone = true, others = c.others }), "plan"
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
      for n = S.mark + 1, #acts do
        if acts[n].cmd == 0x0F then
          for _, q in ipairs(acts[n].passes) do sig[#sig + 1] = string.format("%04X>%04X", q.pre, q.post or 0) end
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
    key = string.format("%02X/%03X", seed0 or 0xFF, H.readWord(0x11E0))
  end),
  play(),
  H.waitFrames(60),
  H.call(judgeNew),
  H.careStop(TAG .. " care after the battle"),
}

H.run({ maxFrames = 2400000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function()
    arm()
    W = H.setzerCrowdBudget(H.fieldEncounterGroup(H.mapId() & 0x1ff), TAG)
  end),
  H.driveUntil(function() return allSeen() end, 2200000, steps,
    "every kind meets a pass whose body fell while another stands"),
  H.call(function()
    judgeNew()
    local t = {}
    for _, k in ipairs({ "hire", "jackpot", "coin", "fight", "resplit", "blitz", "tool", "vanilla" }) do
      local n, d = 0, 0
      for _, c in pairs(seen[k]) do n, d = n + c, d + 1 end
      t[#t + 1] = string.format("%s %d pass(es) over %d distinct key(s)", k, n, d)
    end
    H.log(string.format("[%s] PASSED: %d extended action(s), %d later pass(es) held while a body stood, over %d "
      .. "battle(s) (%d crowds); %s", TAG, checked.acts, checked.passes, battles, crowds, table.concat(t, "; ")))
  end),
})
