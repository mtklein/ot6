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
-- through the real menu while the others Defend:
--   party:      one ally's HP is set to 1, and SETZER (one weapon: two swings
--               a boost point) Fights it at 1 BP (an entry with `ally`): the
--               first swing fells the ally, and the second stays on that
--               ally (the Fight's backup target) or lands nowhere (check H).
--               Each ally in turn until one falls to the first swing.
--   emptied:    every monster's HP is set to 1 and SETZER's bank to 3; he
--               Fights his default target at 3 BP (then 2 BP): each swing
--               fells a monster and the next goes to another (F, A, B, C),
--               and the swings after the last land on no party member (G).
--   emptystart: every monster's HP is set to 1 and SETZER's bank to 3; he
--               throws Coin Toss at 3 BP over the group: the first toss
--               fells them all, the second (starting on the fallen) lands
--               nowhere, and the third and fourth start empty and land
--               nowhere too (G) -- the branch where vanilla, seeing an empty
--               start, would Retarget.
--   offhand:    SETZER's weapon moves to his off hand (the per-hand battle
--               bytes swapped: power $3B68, element $3B90, props $3BA4, hit
--               rate $3B7C, spellcast $3D34, special $3CBC, item $3CA8), and
--               he Fights at 1 BP; as the action starts its queued target is
--               felled (HP 0, Wound).  The main hand's passes never reach
--               ChooseTarget, so the first that does is one down the count:
--               it must still retarget onto a standing monster (I).  Then 2
--               BP.
-- In emptied and emptystart SETZER is also Muddled as his action starts
-- ($3EE5 bit 5 written at ExecCmd): the bit vanilla's Retarget reads to
-- turn an attacker on its own party, so a pass that fell through to it
-- would land there.  That write is mechanism staging only: the engine's
-- SetStatus_0d does not run, and a really Muddled (or Zombied) actor is
-- engine-driven -- InitPlayerAction would have picked its action and
-- targets -- so no played action reaches these passes in that state.  A
-- really Zombied actor's engine-driven Fight never starts a pass empty
-- (its emptied mask goes back to its backup targets, $3a4e), by the code.
-- (Muddling an ally at the battle's start instead did not take: it kept
-- its command window and Defended at 3 BP --
-- build/attempts/wt/pass-retarget/round2/side/passside_menumuddle.log.)
-- Every pass of every action is held to M.passCheck, whose checks name
-- what they assert.
-- Negative controls (build/attempts/wt/pass-retarget/round3/mutants/): a
-- ROM whose pass spreads to the party side fails H; one that sends the
-- pass to the party once no monster stands fails G (emptied); one whose
-- empty-start pass falls through to vanilla's Retarget fails G
-- (emptystart); one whose "first pass" is the pass count, as 71224074's
-- was, fails I (offhand).
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
local function armExec()
  local ec = H.sym("ExecCmd@battle_code")
  emu.addMemoryCallback(function()
    local w = atExec
    if w == nil then return end
    local x = emu.getState()["cpu.x"] & 0xff
    if x ~= w.e or H.readByte(0x3A7C) ~= w.cmd then return end
    atExec = nil
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
      S.cases = {}
      for _, e in ipairs(S.allies) do S.cases[#S.cases + 1] = { kind = "party", e = e } end
      for _, b in ipairs({ 3, 2 }) do S.cases[#S.cases + 1] = { kind = "emptied", e = sz, boost = b } end
      for _, b in ipairs({ 3, 2 }) do S.cases[#S.cases + 1] = { kind = "emptystart", e = sz, boost = b } end
      for _, b in ipairs({ 1, 2 }) do S.cases[#S.cases + 1] = { kind = "first", e = sz, boost = b } end
      S.ci, S.phase, S.met = 1, "write", {}
    end
    if S.phase == "restore" then
      if not S.req.done then return "frame" end
      H.checkReq(S.req, "restoring the opening snapshot")
      PW.open = {}
      S.phase = "write"
    end
    if S.phase == "write" then
      local c = S.cases[S.ci]
      local x = c.e * 2
      S.mark, S.before = #PW.acts, #seen[c.kind]
      if c.kind == "party" then
        H.writeWord(0x3BF4 + x, 1)
        H.log(string.format("[%s] party, ally slot %d: its HP set to 1; SETZER Fights it at 1 BP", TAG, c.e))
        S.actor, S.want = slotOf(SETZER) * 2, "fight"
        S.step = H.setzerBattle({ { row = "fight", cmd = 0x00, boost = 1, ally = c.e }, { row = "defend" },
          { row = "defend" } }, { untilPlanDone = true })
      elseif c.kind == "emptied" then
        crowdTo1()
        H.writeByte(0x3E9C + x, 3)
        atExec = { e = x, cmd = 0x00, muddle = true }
        H.log(string.format("[%s] emptied: every monster at 1 HP, SETZER's bank 3; he Fights at %d BP", TAG, c.boost))
        S.actor, S.want = x, "fight"
        S.step = H.setzerBattle({ { row = "fight", cmd = 0x00, boost = c.boost }, { row = "defend" },
          { row = "defend" } }, { untilPlanDone = true })
      elseif c.kind == "emptystart" then
        crowdTo1()
        H.writeByte(0x3E9C + x, 3)
        atExec = { e = x, cmd = 0x0F, muddle = true }
        H.log(string.format("[%s] emptystart: every monster at 1 HP, SETZER's bank 3; Coin Toss at %d BP", TAG,
          c.boost))
        S.actor, S.want = x, "coin"
        S.step = H.setzerBattle({ { row = COIN, boost = c.boost }, { row = "defend" } }, { untilPlanDone = true })
      else
        swapHands(x)
        H.assertEq(H.readByte(0x3B68 + x) == 0 and H.readByte(0x3B69 + x) ~= 0, true, "offhand: after the swap "
          .. "SETZER's main hand is empty and his off hand holds the weapon")
        atExec = { e = x, cmd = 0x00, fell = true }
        H.log(string.format("[%s] offhand: SETZER's weapon in his off hand (power $3B68/9 = %d/%d); he Fights at %d "
          .. "BP, his queued target felled as it starts", TAG, H.readByte(0x3B68 + x), H.readByte(0x3B69 + x),
          c.boost))
        S.actor, S.want = x, "fight"
        S.step = H.setzerBattle({ { row = "fight", cmd = 0x00, boost = c.boost }, { row = "defend" },
          { row = "defend" } }, { untilPlanDone = true })
      end
      S.phase = "play"
    end
    if S.phase == "play" then
      local c = S.cases[S.ci]
      local r = S.step:tick()
      judgeNew()
      local got = nil
      for n = S.mark + 1, #PW.acts do
        local a = PW.acts[n]
        if a.e == S.actor and a.kind == S.want then got = a; break end
      end
      if got == nil and r ~= "done" and H.battleLoadStarted() then return r end
      local met = #seen[c.kind] > S.before
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
      for _, k in ipairs(KINDS) do
        H.assertEq(S.met[k] == true, true, string.format("%s: the case's draw is met (its candidates tried)", k))
      end
      done = true
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
