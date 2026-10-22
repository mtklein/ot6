-- @suite slow
-- battle_multipassfizzle.lua -- an action of several passes that fails for
-- lack of MP does nothing: no pass after the refusal, no damage (#451).
--
-- OT6 buys extra passes of an action through $3a70, the engine's
-- multi-attack count, from the command handler, before the first pass runs:
-- Pummel, Bum Rush and Drill (Ot6HitCount) and Edgar's Overclock
-- (Ot6OverclockPasses) among them.  The MP price is checked once, in the
-- first pass's CalcAttackEffect (the $3a4c subtract, cleared as it is
-- read).  A refusal there ends that pass; ExecAttack's tail (`dec $3a70 /
-- bmi`) used to run the passes still counted, which found $3a4c already
-- cleared and landed unpaid.  The refusal now ends the action's passes
-- too.  (Quadra Slam, Quadra Slice and Empowerer set their passes from the
-- attacker effect, after the MP check, so a refused one never had more than
-- the one pass: build/attempts/wt/v033-multipass-fizzle/.)
--
-- The menus refuse an unpayable pick, so an unpayable action reaches
-- resolve only when the pool moves between the commit and the resolve (an
-- enemy's Rasp or Osmose in the advance wait).  No fixture holds an
-- MP-draining enemy beside these verbs, so the file's one state write
-- (tools/state_write_waivers.txt) is battle_mpfizzle's: the moment the
-- verb's commit is queued, its caster's pool is set to 1, what a drain
-- leaves.
--
-- Played: Continue the wor-tomb-v1 battery (EDGAR, SABIN, CELES, SETZER in
-- Darill's Tomb), walk the east room into random battles, and play through
-- the real menu (H.kitBattle; the others Defend):
--   SABIN  Blitz, Pummel at 1 BP (two strikes, Ot6HitCount);
--   EDGAR  Tools at 3 BP, Overclocked (twice the firings,
--          Ot6OverclockPasses): Drill when the bag has one (its own x2 as
--          well), else a Tool that deals damage (AutoCrossbow, Bio Blaster,
--          Air Anchor), else Flash, NoiseBlaster or Debilitator.
-- MPASS_SKIP (a global a lab sets; default 0) battles are fought out
-- first, to vary the encounter history the uses meet; MPASS_CHECKPOINT
-- names another battery for a lab (its OT6_SRAM_CHECKPOINT to match).
-- The verbs are the seated party's: a CYAN seated (a lab on wor-cyan-v1)
-- plays his SwdTech window's first multi-pass row.
-- Watched, never written: Ot6FizzleDropBoost (the refusal) with x = the
-- caster, and $3a70 there; Ot6PassTargeted after ChooseTarget (one call a
-- pass); the monsters' HP; Ot6ActionEnd's pending boost, bank and pool.
-- Asserted per resolved use (all are collected, then reported):
--   the refusal was reached with passes still counted ($3a70 >= 1 there;
--     a SwdTech, whose passes come later, is exempt);
--   no pass of the action targeted after the refusal;
--   no monster lost HP from the refusal to 20 frames after the turn's end;
--   the pool untouched (1 at the turn's end);
--   the boost dropped (#450): nothing pending at the turn's end and the
--     bank one pip up (capped at 5) 20 frames later.
-- And: every verb of the seated party resolved within BATTLES battles.
-- Old-ROM red and mutants: build/attempts/wt/v033-multipass-fizzle/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CYAN, EDGAR, SABIN = 0x02, 0x04, 0x05
local CMD_SWDTECH, CMD_TOOLS, CMD_BLITZ = 0x07, 0x09, 0x0A
local PUMMEL = 0x5D
-- Drill (its own x2 as well), then the Tools that deal damage, then the
-- rest; never Chain Saw (its instant kill ends small battles)
local TOOL_PREF = { 0xA8, 0xAA, 0xA4, 0xA9, 0xA5, 0xA3, 0xA7 }
local MULTI_SWDTECH = { [0x58] = "Quadra Slam", [0x59] = "Empowerer", [0x5B] = "Quadra Slice" }
local BATTLES = 4
MPASS_SKIP = MPASS_SKIP or 0
MPASS_CHECKPOINT = MPASS_CHECKPOINT or "wor-tomb-v1"   -- a lab's other battery

local function seatOf(c)
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) == c and (H.readByte(0x3AA0 + s * 2) & 1) ~= 0 then return s end
  end
end
local function mp(s) return H.readWord(0x3C08 + s * 2) end
local function bank(s) return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function monsterHp()
  local t, parts = 0, {}
  for m = 0, 5 do
    local hp = H.readWord(0x3BFC + m * 2)
    if hp ~= 0xFFFF then t = t + hp end
    parts[#parts + 1] = tostring(hp)
  end
  return t, table.concat(parts, "/")
end

-- the verbs, each played (and drained) once
local VERBS = {
  { name = "Pummel", who = SABIN, cmd = CMD_BLITZ, row = PUMMEL, boost = 1, direct = true },
  { name = "Overclock", who = EDGAR, cmd = CMD_TOOLS, boost = 3, peek = "tools" },
  { name = "SwdTech", who = CYAN, cmd = CMD_SWDTECH, peek = "swdtech", direct = true, late = true },
}

local active = nil        -- the use being drained: { verb, seat, ... }
local recs = {}

local function arm()
  -- the commit is queued (CreateAction's `sta $3620,y`, x = the actor): the
  -- synthetic drain
  emu.addMemoryCallback(function(_, v)
    if active == nil or active.queued then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= active.seat * 2 then return end
    if H.readByte(0x3A7A) ~= active.verb.cmd then return end
    local mp0 = mp(active.seat)
    active.queued = { f = H.frame, price = v, mp = mp0, pend = pend(active.seat), bank = bank(active.seat),
      atk = H.readByte(0x3A7B) }
    H.writeWord(0x3C08 + active.seat * 2, 1)   -- the file's one write: what a drain leaves
    H.log(string.format("[mpass] %s queued f%d: id $%02X price %d, pending %d, bank %d, pool %d -> %d "
      .. "(synthetic drain)", active.verb.name, H.frame, active.queued.atk, v, active.queued.pend,
      active.queued.bank, mp0, mp(active.seat)))
  end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
  local fd = H.sym("Ot6FizzleDropBoost")
  emu.addMemoryCallback(function()
    if active == nil or not active.queued or active.done then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= active.seat * 2 then return end
    local t, s = monsterHp()
    active.refusals = (active.refusals or 0) + 1
    if active.refused == nil then
      active.refused = { f = H.frame, passes = H.readByte(0x3A70), pend = pend(active.seat), hp = t, hps = s,
        before = active.passes or 0 }
      H.log(string.format("[mpass] %s refused f%d: $3a70=%d at the refusal, pending %d, pass %d of "
        .. "the action, monsters' HP %s", active.verb.name, H.frame, active.refused.passes, active.refused.pend,
        active.refused.before, s))
    end
  end, emu.callbackType.exec, fd, fd)
  local pt = H.sym("Ot6PassTargeted")
  emu.addMemoryCallback(function()
    if active == nil or not active.queued or active.done then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= active.seat * 2 then return end
    active.passes = (active.passes or 0) + 1
    if active.refused then
      active.after = (active.after or 0) + 1
      H.log(string.format("[mpass] %s f%d: a pass targeted after the refusal ($3a70=%d, targets %02X%02X)",
        active.verb.name, H.frame, H.readByte(0x3A70), H.readByte(0xB9), H.readByte(0xB8)))
    end
  end, emu.callbackType.exec, pt, pt)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if active == nil or not active.queued or active.done then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= active.seat * 2 then return end
    if H.readByte(0x3A7C) ~= active.verb.cmd then return end
    local t, s = monsterHp()
    active.done = { f = H.frame, pend = pend(active.seat), bank = bank(active.seat), mp = mp(active.seat),
      hp = t, hps = s }
  end, emu.callbackType.exec, ae, ae)
  -- a status that takes the caster's turn (Sleep, Muddle, Stop, a fall...)
  -- empties its queue through RemoveAllActions before the action runs: the
  -- use never resolves, and nothing of it is evidence (#468: EDGAR's queued
  -- Overclock slept away under Sleep/Muddle/Imp, status 25 A8, and the
  -- others Defended 40,000 frames waiting for its turn's end)
  local ra = H.sym("RemoveAllActions")
  emu.addMemoryCallback(function()
    if active == nil or not active.queued or active.done or active.refused or active.cancelled then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= active.seat * 2 then return end
    active.cancelled = { f = H.frame, s1 = H.readByte(0x3EE4 + active.seat * 2),
      s2 = H.readByte(0x3EE5 + active.seat * 2), s3 = H.readByte(0x3EF8 + active.seat * 2) }
  end, emu.callbackType.exec, ra, ra)
end

-- the use is over 20 frames after its turn's end, or its queue was emptied
-- before it ran (not counted: the verb stays pending for the next battle)
local function closed()
  local r = active
  if r ~= nil and r.cancelled and not r.done and not r.refused then
    H.log(string.format("[mpass] %s: the caster's queue was emptied at f%d before the action ran (status %02X %02X "
      .. "%02X): not counted, the battle is fought out and the next taken", r.verb.name, r.cancelled.f,
      r.cancelled.s1, r.cancelled.s2, r.cancelled.s3))
    active = nil
    return true
  end
  if r == nil or not r.done or H.frame < r.done.f + 20 then return false end
  local t, s = monsterHp()
  r.later = { bank = bank(r.seat), hp = t, hps = s }
  H.log(string.format("[mpass] %s resolved: passes %d (after the refusal %d), turn end f%d pending %d bank %d "
    .. "pool %d | +20f bank %d, monsters' HP %s -> %s", r.verb.name, r.passes or 0, r.after or 0, r.done.f,
    r.done.pend, r.done.bank, r.done.mp, r.later.bank, r.refused and r.refused.hps or "?", s))
  recs[#recs + 1] = r
  r.verb.resolved = true
  active = nil
  return true
end

local function walkToBattle()
  local wp, A, B = 1, nil, nil
  local WPS = { { 124, 26 }, { 120, 11 } }       -- Darill's Tomb's east room
  return H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
    H.cond(function() return H.worldMode() end, {
      H.call(function()
        if A ~= nil then return end
        local x0, y0 = H.worldX(), H.worldY()
        for _, d in ipairs({ { 0, 2 }, { 0, -2 }, { 2, 0 }, { -2, 0 }, { 0, 1 }, { 1, 0 }, { -1, 0 }, { 0, -1 } }) do
          if H.worldBfs(x0 + d[1], y0 + d[2]) then A, B = { x0, y0 }, { x0 + d[1], y0 + d[2] }; break end
        end
        H.assertEq(A ~= nil, true, string.format("a walkable pace from world (%d,%d)", x0, y0))
      end),
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, {
      H.navTo(function() return WPS[wp][1] end, function() return WPS[wp][2] end,
        { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() wp = wp % #WPS + 1 end),
    }),
  }, "a random battle")
end

local function lazy(build)
  local s = nil
  return {
    tick = function()
      if s == nil then s = build() end
      return s:tick()
    end,
    reset = function() if s then s:reset() end; s = nil end,
  }
end

-- the list's rows (the Tools-shell list at $4005, 3 bytes a row)
local function listRows()
  local t = {}
  for i = 0, 7 do t[i] = H.readByte(0x4005 + i * 3) end
  return t
end

-- one verb in this battle: read its list when the row is the live party's,
-- then the drained use, then 20 frames
local function useStep(v)
  return lazy(function()
    if not H.battleLoadStarted() or v.resolved or seatOf(v.who) == nil then return H.seqStep({}) end
    local steps = {}
    if v.peek and v.row == nil then
      steps[#steps + 1] = H.kitBattle({ { who = v.who, cmd = v.cmd, boost = v.boost or 1, peek = true } }, {
        untilPlanDone = true, idle = "defend", maxFrames = 30000,
        onList = function()
          local rows = listRows()
          local seen = {}
          for i = 0, 7 do seen[#seen + 1] = string.format("%02X", rows[i]) end
          if v.peek == "tools" then
            for _, id in ipairs(TOOL_PREF) do
              for i = 0, 7 do if v.row == nil and rows[i] == id then v.row = id end end
            end
          else
            for i = 0, 7 do
              if v.row == nil and MULTI_SWDTECH[rows[i]] then v.row, v.boost = rows[i], i + 1 end
            end
          end
          H.log(string.format("[mpass] %s list: %s -> row %s at %s BP", v.name, table.concat(seen, " "),
            v.row and string.format("$%02X", v.row) or "none", tostring(v.boost)))
        end })
    end
    steps[#steps + 1] = lazy(function()
      if not H.battleLoadStarted() then return H.seqStep({}) end
      local s = seatOf(v.who)
      if s == nil then return H.seqStep({}) end
      H.assertEq(v.row ~= nil, true, v.name .. ": the caster's list holds a row this suite plays")
      active = { verb = v, seat = s }
      H.log(string.format("[mpass] %s: seat %d, pool %d, bank %d", v.name, s, mp(s), bank(s)))
      return H.kitBattle({ { who = v.who, cmd = v.cmd, row = v.row, boost = v.boost, direct = v.direct } }, {
        untilPlanDone = true, idle = "defend", maxFrames = 40000, planDone = closed })
    end)
    steps[#steps + 1] = H.call(function()
      if active ~= nil then
        H.log(string.format("[mpass] %s: the battle ended before the use resolved (no outcome)", v.name))
        active = nil
      end
    end)
    return H.seqStep(steps)
  end)
end

local battles = 0
local function pending()
  local n = 0
  for _, v in ipairs(VERBS) do if not v.resolved and v.present then n = n + 1 end end
  return n
end

local body = {
  H.bootCheckpoint(MPASS_CHECKPOINT),
  H.call(function()
    arm()
    local party = H.readByte(0x1A6D) & 7
    local names = {}
    for _, v in ipairs(VERBS) do
      v.present = (H.readByte(0x1850 + v.who) & 7) == party
      if v.present then names[#names + 1] = v.name end
    end
    H.log("[mpass] the seated party's verbs: " .. table.concat(names, ", "))
    H.assertEq(pending() >= 1, true, "a multi-pass verb's character is in the party")
  end),
}

body[#body + 1] = H.repeatN(MPASS_SKIP, {
  H.waitUntil(function() return H.hasControl() or H.worldHasControl() end, 3000, "control", 5),
  H.fieldCare({ tag = "mpass: care before a skipped battle", threshold = 0.95, mpBand = 0.9 }),
  walkToBattle(),
  H.kitBattle({}, { maxFrames = 60000 }),
  H.call(function() H.log("[mpass] a skipped battle fought out (MPASS_SKIP)") end),
})
body[#body + 1] = H.driveUntil(function() return pending() == 0 and not H.battleLoadStarted() end, 400000, {
  H.call(function()
    battles = battles + 1
    H.assertEq(battles <= BATTLES, true, string.format("every verb resolved within %d battles", BATTLES))
  end),
  H.cond(function() return not H.battleLoadStarted() end, {
    H.waitUntil(function() return H.hasControl() or H.worldHasControl() end, 3000, "control", 5),
    H.fieldCare({ tag = "mpass: care between battles", threshold = 0.95, mpBand = 0.9 }),
    walkToBattle(),
    H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 2),
    H.waitFrames(30),
  }, {}),
  useStep(VERBS[1]),
  useStep(VERBS[2]),
  useStep(VERBS[3]),
  H.cond(function() return H.battleLoadStarted() end, { H.kitBattle({}, { maxFrames = 60000 }) }, {}),
}, "every verb of the seated party resolves")

body[#body + 1] = H.call(function()
  local fails = {}
  local function check(ok, msg) if not ok then fails[#fails + 1] = msg end end
  for _, r in ipairs(recs) do
    local tag, q, f, d, l = r.verb.name, r.queued, r.refused, r.done, r.later
    check(q.price >= 2, string.format("%s: the queued price %d is above the drained pool", tag, q.price))
    check(f ~= nil, tag .. ": the refusal was never reached")
    if f then
      if r.verb.cmd ~= CMD_SWDTECH then
        check(f.passes >= 1, string.format("%s: $3a70 = %d at the refusal (the action's passes were not "
          .. "counted yet: the property is not exercised)", tag, f.passes))
      end
      check((r.after or 0) == 0, string.format("%s: %d pass(es) targeted after the refusal", tag, r.after or 0))
      check(l.hp == f.hp, string.format("%s: the monsters' HP went %s -> %s after the refusal", tag, f.hps,
        l.hps))
    end
    check(d.mp == 1, string.format("%s: the pool read %d at the turn's end (want the drained 1)", tag, d.mp))
    check(d.pend == 0, string.format("%s: the pending boost was kept for spending (it read %d at the turn's "
      .. "end)", tag, d.pend))
    check(l.bank == math.min(5, q.bank + 1), string.format("%s: bank %d -> %d (want %d: no spend, the "
      .. "unboosted turn's regen)", tag, q.bank, l.bank, math.min(5, q.bank + 1)))
  end
  for _, m in ipairs(fails) do H.log("[mpass] FAIL " .. m) end
  local names = {}
  for _, r in ipairs(recs) do
    names[#names + 1] = string.format("%s(passes %d, after %d, $3a70 %s)", r.verb.name, r.passes or 0, r.after or 0,
      r.refused and tostring(r.refused.passes) or "-")
  end
  H.log(string.format("[mpass] SUMMARY %d use(s) over %d battle(s): %s", #recs, battles, table.concat(names, " ")))
  H.assertEq(#fails, 0, "every drained multi-pass action did nothing")
end)

H.run({ maxFrames = 400000 }, body)
