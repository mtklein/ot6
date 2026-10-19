-- @suite slow
-- battle_passside.lua -- the mechanism twin of battle_passretarget for the
-- cases play does not deal on cue (ot6_passes.asm): a pass OT6 added
-- retargets only on the monster side.  When the body it fell from was a
-- party member it spreads to no other one; once the monster side has
-- emptied it lands nowhere, never on the party, even for an attacker whose
-- vanilla Retarget would pick its own party; and an action whose queued
-- target fell before it began still gets vanilla's first-pass retarget on
-- its first pass that targets, even when an empty hand's pass came first.
--
-- A mechanism test, not play: it stages its draws with declared writes
-- (tools/state_write_waivers.txt) from a battle reached by play.  Continue
-- the wor-tomb-v1 battery, walk Darill's Tomb's east room into the first
-- battle with two or more monsters (fighting out any other, care after,
-- within M.setzerCrowdBudget's decoded worst case), and snapshot its
-- opening.  Each case restores that snapshot, writes, and plays SETZER
-- through the real menu while the others Defend.  A case whose draw that
-- crowd does not meet is owed to the next crowd (at most MAX_CROWDS):
--   party:      one ally's HP is set to 1 as the selected Fight begins, and SETZER (one weapon: two swings
--               a boost point) Fights it at 1 BP (an entry with `ally`): the
--               first swing fells the ally, and the second stays on that
--               ally (the Fight's backup target) or lands nowhere (check H).
--               Each ally in turn until one falls to the first swing.
--   emptied:    every monster's HP is set to 1 as the selected Fight begins,
--               and SETZER's bank to 3 before the menu; he
--               Fights his default target at 3 BP (then 2 BP): each swing
--               fells a monster and the next goes to another (F, A, B, C),
--               and the swings after the last land on no party member (G).
--   emptystart: every monster's HP is set to 1 as Coin Toss begins,
--               and SETZER's bank to 3 before the menu; he
--               throws Coin Toss at 3 BP over the group, and the tosses
--               fell the crowd with tosses to spare: the toss after the last
--               body falls starts on the fallen and lands nowhere (G), and
--               the one after that starts empty and lands nowhere too (G) --
--               the branch where vanilla, seeing an empty start, would
--               Retarget.  (Measured: toss 1 felled two of three, toss 2
--               the third, toss 3 started on the fallen, and toss 4 was the
--               one empty start -- round3/side/r5_passside.log.)
--   offhand:    SETZER's weapon moves to his off hand (the per-hand battle
--               bytes swapped: power $3B68, element $3B90, props $3BA4, hit
--               rate $3B7C, spellcast $3D34, special $3CBC, item $3CA8), and
--               he Fights at 1 BP; as the action starts its queued target is
--               felled (HP 0, Wound).  The main hand's passes never reach
--               ChooseTarget, so the first that does is one down the count:
--               it must still get vanilla's first-pass retarget, onto the
--               side vanilla's Retarget picks for SETZER's state -- the
--               monsters (I).  Then 2 BP.
-- In emptied and emptystart SETZER is also Muddled as his action starts
-- ($3EE5 bit 5 written at ExecCmd): the bit vanilla's Retarget reads to
-- turn an attacker on its own party, so a pass that fell through to it
-- would land there.  That write is mechanism staging: the engine's
-- SetStatus_0d does not run.  Play reaches the same state another way: an
-- action queued before its actor's status changed keeps running, with its
-- targets cleared by InitPlayerAction, so its first pass starts empty and
-- vanilla's Retarget picks the side by the new status -- measured, a
-- Zombie SETZER's queued 1 BP Coin Toss (battle_passretarget's draw,
-- round3/sweep-strictI/r4_new_k4.log: `p1 ... in $0000 ... -> $0007`, the
-- party).  A Zombie with a queued boosted row is so a natural route to
-- the empty-start guard; that draw went to the party on its first pass,
-- so its later pass started on the party (H), not empty.
-- (Muddling an ally at the battle's start instead did not take: it kept
-- its command window and Defended at 3 BP --
-- build/attempts/wt/pass-retarget/round2/side/passside_menumuddle.log.)
-- HP staging is armed only for the selected command, actor, boost and target
-- side at ExecCmd, with SETZER's control free.  A hostile status that lands
-- after the window opens can cancel/re-aim a queued command: that interrupted
-- execution is logged without staging HP, the opening snapshot is restored,
-- and the same case is entered again with SETZER Defending once more before
-- its row (a different input sequence from the same opening, so a different
-- continuation, not the same draw replayed), at most MAX_LEAD times.  It
-- used to be entered again on the same continuation, which cannot survive
-- every interruption: on the v031-robust chain's wor-tomb-v1 SETZER was
-- Zombied after confirming the emptystart Coin Toss at 3 BP, the engine
-- aimed it at the party (#433's vanilla retarget) and the tosses killed the
-- other three ("emptystart command interrupted before its setup: Zombie",
-- then "BATTLE WIPE", build/attempts/wt/v031-robust/final/rerun/).
-- This replaces af45ec3f's rule ("entered again on the same continuation,
-- without snapshot rerolls"), by decision at the v031-robust-2 review: a
-- restore is acceptable here because what follows it is a different
-- deterministic input (one more Defend) from a fixed opening, not the same
-- draw re-rolled until it passes.  MAX_LEAD bounds those retries within one
-- crowd; a case still interrupted after them is owed to the next crowd, and
-- MAX_CROWDS is the assert (every case met within that many crowds).  A
-- wrong target side while SETZER's control is free is not an interruption
-- and is never retried: it fails the run.
-- If a command spent its pips, real Defends rebuild the requested bank.
-- Every pass of every action is held to M.passCheck, whose checks name
-- what they assert.
-- Negative controls (build/attempts/wt/pass-retarget/round3/mutants/): a
-- ROM whose pass spreads to the party side fails H; one that sends the
-- pass to the party once no monster stands fails G (emptied); one whose
-- empty-start pass falls through to vanilla's Retarget fails G
-- (emptystart); one whose "first pass" is the pass count, as 71224074's
-- was, fails I (offhand); one that sends a normal actor's first pass to
-- the party side fails I (round4/mutants/).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TAG = "passside"
local SETZER = 9
local COIN = 0x59

local function want(got, exp, what) return H.assertEq(got, exp, what) end
local seen = { party = {}, emptied = {}, emptystart = {}, first = {} }
local function note(event, kind, key0, what)
  if seen[event] then seen[event][#seen[event] + 1] = what end
  H.log(string.format("[%s]   %s: %s", TAG, event, what))
end
local PW, judgedN = nil, 0
-- what to write as SETZER's action starts (ExecCmd, x = the actor), armed
-- by the case that needs it: { e = entity, cmd = queued command, muddle =
-- bool, fell = bool (fell the queued monster target) }
local atExec = nil
-- the case's plan, its first entry noted on atExec: an action of SETZER's
-- that runs before that entry was confirmed (H.setzerBattle's confirmedAt)
-- was queued before the case -- a Zombie's own Fight that ran after his
-- cure (the v031-robust chain's wor-tomb-v1: "emptied: requested boost at
-- execution: got 0", build/attempts/wt/v031-robust/final/) -- and is not
-- the case's execution.  `lead` Defends go before the case's row: the
-- case's entry again after an interruption (MAX_LEAD, above).
-- MAX_LEAD is a chosen margin, not a measured need: over K 0-9 on the
-- v031-robust chain every interrupted case was met with one extra Defend
-- (build/attempts/wt/v031-robust-2/passside/batch2/).
local MAX_LEAD = 3
local function battleFor(plan, opts, lead)
  atExec.entry = plan[1]
  for _ = 1, lead or 0 do table.insert(plan, 1, { row = "defend" }) end
  return H.setzerBattle(plan, opts)
end
local function armExec()
  local ec = H.sym("ExecCmd@battle_code")
  emu.addMemoryCallback(function()
    local w = atExec
    if w == nil then return end
    local x = emu.getState()["cpu.x"] & 0xff
    if x ~= w.e or H.readByte(0x3A7C) ~= w.cmd then return end
    if w.entry and w.entry.confirmedAt == nil then
      H.log(string.format("[%s] f%d an action of SETZER's ($%02X) runs before the case's row was confirmed: "
        .. "queued before the case, not its execution", TAG, H.frame, w.cmd))
      return
    end
    atExec = nil
    local c = H.controlTaken(x // 2)
    local chars, mons = H.readByte(0xB8), H.readByte(0xB9)
    local eligible = c == nil and (w.ally ~= nil and chars == (1 << w.ally) and mons == 0
      or w.ally == nil and chars == 0 and mons ~= 0)
    w.valid = false
    if c == nil and not eligible then
      -- SETZER's control is free, so nothing re-aimed the command: a wrong
      -- side here is the ROM's or the driver's, and a retry must not hide it
      w.error = string.format("%s: with SETZER's control free, the selected command executes on its selected "
        .. "side (targets chars=%02X monsters=%02X, want %s)", w.kind, chars, mons,
        w.ally ~= nil and string.format("chars=%02X monsters=00", 1 << w.ally) or "chars=00, monsters nonzero")
      H.log(string.format("[%s] f%d %s", TAG, H.frame, w.error))
      return
    end
    if not eligible then
      w.interrupted = c and c.name or string.format("targets chars=%02X monsters=%02X", chars, mons)
      H.log(string.format("[%s] f%d %s command interrupted before its setup: %s; no mechanism HP staged",
        TAG, H.frame, w.kind, w.interrupted))
      return
    end
    -- CPU callback exceptions are not the suite's failure path. Preserve
    -- the first error and rethrow on the normal tick before consuming any
    -- eligibility or pass evidence. Only fully staged commands are valid.
    local ok, err = pcall(function()
    H.assertEq(H.readByte(0x3ED8 + x), SETZER, "the staged case executes as SETZER")
    H.assertEq(H.readByte(0x3A7C), w.cmd, w.kind .. ": its selected command executes")
    H.assertEq(H.readByte(0x3E9D + x), w.boost, w.kind .. ": requested boost at execution")
    H.assertEq(chars, w.ally ~= nil and (1 << w.ally) or 0, w.kind .. ": its selected party target")
    H.assertEq(w.ally ~= nil and mons == 0 or w.ally == nil and mons ~= 0, true,
      w.kind .. ": its selected target side at execution")
    if w.prepare then w.prepare() end
    if w.muddle then H.writeByte(0x3EE5 + x, H.readByte(0x3EE5 + x) | 0x20) end
    local t = H.readByte(0xB9)
    if w.fell then
      for s = 0, 5 do
        if (t >> s) & 1 == 1 then
          H.writeWord(0x3BFC + s * 2, 0)
          H.writeByte(0x3EEC + s * 2, H.readByte(0x3EEC + s * 2) | 0x80)
        end
      end
    end
    H.log(string.format("[%s] f%d SETZER's action $%02X starts: %s%s (queued on monsters $%02X)", TAG, H.frame,
      w.cmd, w.muddle and string.format("Muddled ($3EE5 = %02X)", H.readByte(0x3EE5 + x)) or "",
      w.fell and "its queued target felled" or "", t))
    end)
    if ok then w.valid = true else w.error = tostring(err) end
  end, emu.callbackType.exec, ec, ec)
end
local function judgeNew()
  while judgedN < #PW.acts do
    judgedN = judgedN + 1
    H.passCheck(PW.acts[judgedN], want, note, TAG)
  end
end

local function alive() return H.readByte(0x3A75) end
local function count(m) local n = 0 while m ~= 0 do n = n + (m & 1); m = m >> 1 end return n end
local function slotOf(id) for e = 0, 3 do if H.readByte(0x3ED8 + e * 2) == id then return e end end end
local function allies()
  local t, sz = {}, slotOf(SETZER)
  for e = 0, 3 do
    if e ~= sz and H.readWord(0x3BF4 + e * 2) > 0 then
      local fightRow = false
      for r = 0, 3 do if H.readByte(0x202E + e * 12 + r * 3) == 0x00 then fightRow = true end end
      if fightRow then t[#t + 1] = e end
    end
  end
  return t
end
local HAND = { 0x3B68, 0x3B90, 0x3BA4, 0x3B7C, 0x3D34, 0x3CBC, 0x3CA8 }
local function swapHands(x)
  for _, base in ipairs(HAND) do
    local m, o = H.readByte(base + x), H.readByte(base + x + 1)
    H.writeByte(base + x, o)
    H.writeByte(base + x + 1, m)
  end
end
local function crowdTo1()
  for s = 0, 5 do
    if (alive() >> s) & 1 == 1 then H.writeWord(0x3BFC + s * 2, 1) end
  end
end

local W, since, wp, done = nil, 0, 1, false
local WPS = { { 124, 26 }, { 120, 11 } }
local KINDS = { "party", "emptied", "emptystart", "first" }
-- the kinds whose draw is met so far, and the crowds the cases have used.
-- MAX_CROWDS is a chosen margin, not a measured need: over K 0-9 no run
-- used more than 2 crowds (passside/batch2/).  Three ways a crowd leaves a
-- case owed: the precondition is never dealt (K1: no second monster stands
-- for the offhand case), MAX_LEAD is reached, or the case's action never
-- runs -- K8's emptystart: after the restore SETZER was Zombied again, and
-- an ally cured of Zombie ran its queued 3-BP Fight through the crowd
-- before SETZER's Coin Toss reached ExecCmd, so the battle ended with "the
-- action never ran".  That last path counts no interruption, so only
-- MAX_CROWDS bounds it.
local metAll, crowds, MAX_CROWDS = {}, 0, 3

-- one case: restore, write, play until its action has run
local function play()
  local S = {}
  return { tick = function()
    if S.phase == nil then
      local m = alive()
      H.log(string.format("[%s] encounter %d: alive $%02X (%d monster(s))", TAG, since, m, count(m)))
      if count(m) < 2 or done then S.phase = "fight"
      else S.req, S.phase = H.requestSaveState(), "snap" end
    end
    if S.phase == "snap" then
      if not S.req.done then return "frame" end
      H.checkReq(S.req, "the battle's opening snapshot")
      S.blob, S.allies = S.req.blob, allies()
      H.assertEq(#S.allies >= 1, true, "an ally with a Fight row stands beside SETZER")
      local sz = slotOf(SETZER)
      crowds = crowds + 1
      S.cases = {}
      local function add(c) if not metAll[c.kind] then S.cases[#S.cases + 1] = c end end
      for _, e in ipairs(S.allies) do add({ kind = "party", e = e }) end
      for _, b in ipairs({ 3, 2 }) do add({ kind = "emptied", e = sz, boost = b }) end
      for _, b in ipairs({ 3, 2 }) do add({ kind = "emptystart", e = sz, boost = b }) end
      for _, b in ipairs({ 1, 2 }) do add({ kind = "first", e = sz, boost = b }) end
      S.ci, S.phase, S.met = 1, "write", {}
    end
    if S.phase == "restore" then
      if not S.req.done then return "frame" end
      H.checkReq(S.req, "restoring the opening snapshot")
      PW.open = {}
      -- the snapshot holds his weapon in its own hand again
      S.swappedCi = nil
      S.phase = "write"
    end
    if S.phase == "write" then
      local c = S.cases[S.ci]
      local x = c.e * 2
      S.mark, S.before = #PW.acts, #seen[c.kind]
      if c.kind == "party" then
        H.log(string.format("[%s] party, ally slot %d: its HP armed for 1 at controlled execution; SETZER Fights it at 1 BP", TAG, c.e))
        S.actor, S.want = slotOf(SETZER) * 2, "fight"
        atExec = { e = S.actor, cmd = 0x00, ally = c.e, kind = c.kind, boost = 1,
          prepare = function() H.writeWord(0x3BF4 + x, 1) end }
        S.step = battleFor({ { row = "fight", cmd = 0x00, boost = 1, ally = c.e }, { row = "defend" },
          { row = "defend" } }, { untilPlanDone = true, fullBoost = true }, c.lead)
      elseif c.kind == "emptied" then
        H.writeByte(0x3E9C + x, 3)
        atExec = { e = x, cmd = 0x00, muddle = true, kind = c.kind, boost = c.boost, prepare = crowdTo1 }
        H.log(string.format("[%s] emptied: monster HP armed for 1 at controlled execution, SETZER's bank 3; he Fights at %d BP", TAG, c.boost))
        S.actor, S.want = x, "fight"
        S.step = battleFor({ { row = "fight", cmd = 0x00, boost = c.boost }, { row = "defend" },
          { row = "defend" } }, { untilPlanDone = true, fullBoost = true }, c.lead)
      elseif c.kind == "emptystart" then
        H.writeByte(0x3E9C + x, 3)
        atExec = { e = x, cmd = 0x0F, muddle = true, kind = c.kind, boost = c.boost, prepare = crowdTo1 }
        H.log(string.format("[%s] emptystart: monster HP armed for 1 at controlled execution, SETZER's bank 3; Coin Toss at %d BP", TAG,
          c.boost))
        S.actor, S.want = x, "coin"
        S.step = battleFor({ { row = COIN, boost = c.boost }, { row = "defend" } }, { untilPlanDone = true, fullBoost = true }, c.lead)
      else
        if S.swappedCi ~= S.ci then swapHands(x); S.swappedCi = S.ci end
        H.assertEq(H.readByte(0x3B68 + x) == 0 and H.readByte(0x3B69 + x) ~= 0, true, "offhand: after the swap "
          .. "SETZER's main hand is empty and his off hand holds the weapon")
        atExec = { e = x, cmd = 0x00, fell = true, kind = c.kind, boost = c.boost }
        H.log(string.format("[%s] offhand: SETZER's weapon in his off hand (power $3B68/9 = %d/%d); he Fights at %d "
          .. "BP, his queued target felled as it starts", TAG, H.readByte(0x3B68 + x), H.readByte(0x3B69 + x),
          c.boost))
        S.actor, S.want = x, "fight"
        S.step = battleFor({ { row = "fight", cmd = 0x00, boost = c.boost }, { row = "defend" },
          { row = "defend" } }, { untilPlanDone = true, fullBoost = true }, c.lead)
      end
      S.exec, S.phase = atExec, "play"
    end
    if S.phase == "play" then
      if S.exec and S.exec.error then error(S.exec.error, 0) end
      local c = S.cases[S.ci]
      local r = S.step:tick()
      -- the exec check's failure, raised in this tick: left to the next,
      -- a battle ending now would move on and the next case would
      -- overwrite S.exec with it unraised
      if S.exec and S.exec.error then error(S.exec.error, 0) end
      judgeNew()
      local got = nil
      for n = S.mark + 1, #PW.acts do
        local a = PW.acts[n]
        if a.e == S.actor and a.kind == S.want then got = a; break end
      end
      -- an interruption seen at ExecCmd is acted on there and then: the
      -- engine's aim for it can be the party (the emptystart wipe above)
      local cut = S.exec and S.exec.interrupted ~= nil
      if got == nil and r ~= "done" and not cut and H.battleLoadStarted() then return r end
      local eligible = S.exec and S.exec.valid == true
      local owed = false
      if not eligible and H.battleLoadStarted() then
        local why = S.exec and S.exec.interrupted or "its selected command never executed"
        c.lead = (c.lead or 0) + 1
        c.why = c.why or {}
        c.why[#c.why + 1] = why
        if c.lead <= MAX_LEAD then
          H.log(string.format("[%s] %s interruption #%d: %s; restore the opening and enter the case again "
            .. "with %d Defend(s) of SETZER's first", TAG, c.kind, c.lead, why, c.lead))
          atExec = nil
          S.req, S.phase = H.requestLoadState(S.blob), "restore"
          return "frame"
        end
        -- MAX_LEAD reached: this opening does not let the case run (the
        -- v0.32 aura chain's wor-tomb-v1 crowd Zombies SETZER before his
        -- first command on every restore, so his own Zombie Fight runs
        -- whatever he Defends first).  The case is owed to the next crowd,
        -- the third way a crowd leaves a case owed (MAX_CROWDS, above),
        -- which bounds it.
        H.log(string.format("[%s] %s at %s BP: interrupted %d times from this opening (%s); owed to the next "
          .. "crowd", TAG, c.kind, tostring(c.boost or 1), c.lead, table.concat(c.why, "; ")))
        owed = true
      end
      local met = not owed and eligible and got ~= nil and #seen[c.kind] > S.before
      atExec = nil
      H.log(string.format("[%s] %s, slot %d%s: %s", TAG, c.kind, c.e, c.boost and (" at " .. c.boost .. " BP") or "",
        got == nil and "the action never ran" or met and "the draw is met" or "no draw"))
      if met then S.met[c.kind] = true end
      S.ci = S.ci + 1
      while S.cases[S.ci] and S.met[S.cases[S.ci].kind] do S.ci = S.ci + 1 end
      if S.cases[S.ci] then
        S.req, S.phase = H.requestLoadState(S.blob), "restore"
        return "frame"
      end
      local unmet = {}
      for _, k in ipairs(KINDS) do
        if S.met[k] then metAll[k] = true end
        if not metAll[k] then unmet[#unmet + 1] = k end
      end
      if #unmet == 0 then
        done = true
      else
        -- what this crowd deals can leave a case's precondition unmet: on
        -- the k1 history of this chain's wor-tomb-v1 (build/attempts/wt/
        -- v031-robust-2/passside/), an ally cured of Zombie ran its queued
        -- Fight into one of the two monsters before SETZER's offhand Fight,
        -- so with his queued target felled no monster stood for the first
        -- pass to retarget onto ("first, slot 3 at 1 BP: no draw", and at
        -- 2 BP).  The cases still owed go to the next crowd.
        H.assertEq(crowds < MAX_CROWDS, true, string.format("every case's draw is met within %d crowds "
          .. "(still owed: %s)", MAX_CROWDS, table.concat(unmet, ", ")))
        H.log(string.format("[%s] crowd %d left %s unmet: fight it out and take the next crowd for them", TAG,
          crowds, table.concat(unmet, ", ")))
        since = 0
      end
      S.phase = "fight"
      if not H.battleLoadStarted() then return "done" end
    end
    if S.F == nil then
      S.F = H.newFightDriver(TAG .. " fight", { tactical = true, boost = true, items = true, bank = 0,
        healPercent = 55, setzer = false })
    end
    judgeNew()
    if not H.battleLoadStarted() then return "done" end
    S.F.frame()
    return "frame"
  end, reset = function() S = {} end }
end

H.run({ maxFrames = 900000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function()
    PW = H.passWatch()
    armExec()
    W = H.setzerCrowdBudget(H.fieldEncounterGroup(H.mapId() & 0x1ff), TAG)
  end),
  H.driveUntil(function() return done end, 860000, {
    H.call(function()
      since = since + 1
      H.assertEq(since <= W, true, string.format("two or more monsters within %d encounters (the decoded worst "
        .. "case to a crowd, which deals three)", W))
    end),
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.navTo(function() return WPS[wp][1] end, function() return WPS[wp][2] end,
        { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() wp = wp % #WPS + 1 end),
    }, "a random battle"),
    H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 2),
    H.call(function() PW.key = string.format("%02X/%03X", PW.seed0 or 0xFF, H.readWord(0x11E0)) end),
    play(),
    H.waitFrames(60),
    H.call(judgeNew),
    H.careStop(TAG .. " care after the battle"),
  }, "a battle with two or more monsters"),
  H.call(function()
    local t = {}
    for _, k in ipairs(KINDS) do t[#t + 1] = string.format("%s %d (%s)", k, #seen[k], seen[k][1] or "-") end
    H.log(string.format("[%s] PASSED: %s", TAG, table.concat(t, "; ")))
  end),
})
