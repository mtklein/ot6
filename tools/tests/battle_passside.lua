-- @suite slow
-- battle_passside.lua -- the mechanism twin of battle_passretarget: a pass
-- OT6 added retargets only on the monster side (ot6_passes.asm).  When the
-- body it fell from was a party member it spreads to no other one, and once
-- the monster side has emptied it lands nowhere -- never on the party, even
-- for a muddled actor, whose vanilla Retarget picks its own party.
--
-- A mechanism test, not play: the draws it needs (an ally felled by the
-- first swing; a muddled actor with banked boost against a crowd it can
-- empty) do not come on cue, so it sets them up with declared writes
-- (tools/state_write_waivers.txt) from a battle reached by play: Continue
-- the wor-tomb-v1 battery, walk Darill's Tomb's east room into the first
-- battle with two or more monsters (fighting out any other, care after,
-- within M.setzerCrowdBudget's decoded worst case), and snapshot its
-- opening.  Each case restores that snapshot, writes, and plays:
--   party:   one ally's HP is set to 1, and SETZER (one weapon: two swings a
--            boost point) Fights it at 1 BP through the real menu (an entry
--            with `ally`, H.setzerBattle's party-side aim): the first swing
--            fells the ally, and the second must stay on that ally (the
--            Fight's backup target) or land nowhere, not spread to another
--            (check H).  Each ally in turn until one falls to the first swing.
--   emptied: every monster's HP is set to 1 and SETZER's bank to 3; he
--            Fights his default target at 3 BP (2 BP the second candidate)
--            through the real menu, and as the action starts (ExecCmd for
--            him) he is Muddled ($3EE5 bit 5, the bit vanilla's Retarget
--            reads to turn an attacker on its own party).  Each swing fells
--            a monster and the next goes to another (checks F, A, B, C); the
--            swings after the last falls land on no party member (check G).
--            (Muddling him at the menu instead does not take: a status
--            written there leaves the command window his, measured --
--            build/attempts/wt/pass-retarget/side/.)
-- The other members Defend throughout.  Every pass of every action is
-- held to M.passCheck, whose checks name what they assert.
-- A charmed actor is not exercised: nothing in this room charms, and
-- vanilla's Retarget turns on the party by the Muddle bit and by $3395
-- (Charm) alike, the one branch check G holds shut.
-- Negative controls (build/attempts/wt/pass-retarget/round2/mutants/): a
-- ROM whose pass spreads to the party side fails H here; one whose OT6
-- pass falls through to vanilla's Retarget fails F here (the muddled
-- SETZER's second swing went to the party while a monster stood); one
-- that retargets to the party side fails G in battle_passretarget.  The
-- ROM before the fix fails A here (its second swing landed nowhere).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TAG = "passside"
local SETZER = 9

local function want(got, exp, what) return H.assertEq(got, exp, what) end
local seen = { party = {}, emptied = {} }
local function note(event, kind, key0, what)
  if seen[event] then seen[event][#seen[event] + 1] = what end
  H.log(string.format("[%s]   %s: %s", TAG, event, what))
end
local PW, judgedN = nil, 0
-- the "emptied" case's Muddle, written as SETZER's action starts (ExecCmd,
-- x = the actor) and only for the case that armed it
local muddleAt = nil
local function armMuddle()
  local ec = H.sym("ExecCmd@battle_code")
  emu.addMemoryCallback(function()
    if muddleAt == nil then return end
    local x = emu.getState()["cpu.x"] & 0xff
    if x ~= muddleAt or H.readByte(0x3A7C) ~= 0x00 then return end
    H.writeByte(0x3EE5 + x, H.readByte(0x3EE5 + x) | 0x20)
    H.log(string.format("[%s] f%d SETZER's Fight starts: Muddled ($3EE5 = %02X)", TAG, H.frame, H.readByte(0x3EE5 + x)))
    muddleAt = nil
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

local W, since, wp, done = nil, 0, 1, false
local WPS = { { 124, 26 }, { 120, 11 } }

-- one case: restore, write, play until `met` or the case's battle step ends
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
      S.cases = {}
      for _, e in ipairs(S.allies) do S.cases[#S.cases + 1] = { kind = "party", e = e } end
      for _, b in ipairs({ 3, 2 }) do S.cases[#S.cases + 1] = { kind = "emptied", e = slotOf(SETZER), boost = b } end
      S.ci, S.phase = 1, "write"
      S.met = {}
    end
    if S.phase == "restore" then
      if not S.req.done then return "frame" end
      H.checkReq(S.req, "restoring the opening snapshot")
      PW.open = {}
      S.phase = "write"
    end
    if S.phase == "write" then
      local c = S.cases[S.ci]
      S.mark, S.before = #PW.acts, #seen[c.kind]
      if c.kind == "party" then
        H.writeWord(0x3BF4 + c.e * 2, 1)
        H.log(string.format("[%s] party, ally slot %d: its HP set to 1; SETZER Fights it at 1 BP", TAG, c.e))
        S.step = H.setzerBattle({ { row = "fight", cmd = 0x00, boost = 1, ally = c.e }, { row = "defend" },
          { row = "defend" } }, { untilPlanDone = true })
      else
        for s = 0, 5 do
          if (alive() >> s) & 1 == 1 then H.writeWord(0x3BFC + s * 2, 1) end
        end
        H.writeByte(0x3E9C + c.e * 2, 3)
        muddleAt = c.e * 2
        H.log(string.format("[%s] emptied: every monster at 1 HP, SETZER's bank 3; he Fights at %d BP, Muddled as it "
          .. "starts", TAG, c.boost))
        S.step = H.setzerBattle({ { row = "fight", cmd = 0x00, boost = c.boost }, { row = "defend" },
          { row = "defend" } }, { untilPlanDone = true })
      end
      S.phase = "play"
    end
    if S.phase == "play" then
      local c = S.cases[S.ci]
      local r = S.step:tick()
      judgeNew()
      -- the case's action: the first act of its actor since the restore
      local actor = c.kind == "party" and slotOf(SETZER) * 2 or c.e * 2
      local got = nil
      for n = S.mark + 1, #PW.acts do
        local a = PW.acts[n]
        if a.e == actor and a.kind == "fight" then got = a; break end
      end
      if got == nil and r ~= "done" and H.battleLoadStarted() then return r end
      local met = #seen[c.kind] > S.before
      muddleAt = nil
      H.log(string.format("[%s] %s, slot %d: %s", TAG, c.kind, c.e, got == nil and "the actor's Fight never "
        .. "ran" or met and "the draw is met" or "no draw (the Fight went elsewhere or felled nothing)"))
      if met then S.met[c.kind] = true end
      -- next case: the first of the next kind once this kind is met
      S.ci = S.ci + 1
      while S.cases[S.ci] and S.met[S.cases[S.ci].kind] do S.ci = S.ci + 1 end
      if S.cases[S.ci] then
        S.req, S.phase = H.requestLoadState(S.blob), "restore"
        return "frame"
      end
      H.assertEq(S.met.party == true, true, string.format("party: an ally felled by the first swing, the next held "
        .. "(tried %d allies)", #S.allies))
      H.assertEq(S.met.emptied == true, true, "emptied: SETZER's muddled boosted Fight emptied the monster side "
        .. "with a swing to spare (at 3 BP, then 2 BP)")
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

H.run({ maxFrames = 800000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function()
    PW = H.passWatch()
    armMuddle()
    W = H.setzerCrowdBudget(H.fieldEncounterGroup(H.mapId() & 0x1ff), TAG)
  end),
  H.driveUntil(function() return done end, 760000, {
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
    H.log(string.format("[%s] PASSED: %d party draw(s) (%s); %d emptied draw(s) (%s)", TAG, #seen.party,
      seen.party[1] or "-", #seen.emptied, seen.emptied[1] or "-"))
  end),
})
