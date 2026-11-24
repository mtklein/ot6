-- @suite savestate=moogle_defense slow
-- battle_marshal.lua -- the Marshal under the boss contract (#561; docs/design/bosses-wob.md block 2): "Strike as
-- one!" -> the Lobos' gauges filled and two Battles from him, and the break that cancels it.
--
-- The Marshal's script (ai_script.asm AIScript::_100) is vanilla's below its fuse block, but for the arming: his
-- rotation's second turn (and every turn of his once the Lobos are down, vanilla's `if_num_monsters 1` block) sets
-- monster switch 0.  With the switch set his turn is the fuse block, first in the script: "Strike as one!"
-- (dlg $8F) and a glow; the turn after it clears the switch, fills both Lobos' gauges (they come in with him)
-- and strikes twice.  Under the contract (ot6_fuse.asm, Ot6FuseTbl's row $0064) a break while the fuse is lit
-- cancels it: the switch is cleared and the script waits nowhere, so his rotation starts over from its first turn.
--
-- Boots moogle_defense (gen_moogle: the defense's first controllable frame, LOCKE's squad at (14,14)), deploys the
-- squads and fights the six waves as gen_moogle does (the fight driver), walks LOCKE's squad beside the Marshal
-- at (15,40), engages battle 6, and plays it three times from a snapshot at its open (M.fuseCases, lib/ot6.lua,
-- where the cases and the DECLARED staging are written out: the gauge, the row's classes for the breaking Fight,
-- and HP held -- the Marshal's at 400 of 420, so the Fights that land on him do not end the fight):
--   unbroken  the squad Defends; the line shows on his third turn; the lit-fuse mark stands before his shield
--             emblem; the two Battles are dispatched on his next turn, with one glow between; the mark goes.
--   broken    a Fight aimed at him and confirmed once the mark is up breaks him: the cancel fires, the mark goes
--             with the hit, his first turns back hold no strike, switch 0 reads clear, and the line returns only
--             after his rotation's two turns again; the strike follows that.
--   outside   a break after his first turn, before any line: nothing is cancelled, and the fuse lights and fires
--             as in the first case.
-- Mutant (build/attempts/wt/v051-tg-wob1/merged/mutants-merged/): marshal_no_clear (Ot6FuseTbl+61=FF) is red at "monster switch 0 is clear after the cancel".
-- A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/moogle_defense.mss.lua"

local MARSHAL, LOBO = 0x064, 0x019
local MX, MY = 15, 40                    -- the Marshal's post: npc_prop.asm map 51 NPC_3, static
local LEADER_OFF = { [1] = 0x0029, [2] = 0x019A, [3] = 0x0148 }
local aPhase = 0
local battleSnap, aloneW = nil, nil
local MENT = 8 + 2 * 2                   -- the Marshal's entity (formation slot 2)
local function marshalMvar() return H.readByte(0x3DAC + MENT) end
local function lobosStanding()
  local t = {}
  for s = 0, 5 do
    if H.readWord(0x57C0 + s * 2) == 0x019 and H.monStanding(s) then t[#t + 1] = s end
  end
  return t
end
-- one aimed Fight on a Lobo, by the first standing member, once `when` says so (the member waits on its command
-- window meanwhile; the others Defend)
local LOCKE = 0x01
-- Fights on the Lobo in `slot` until it is down.  Without `when`, by each standing member in turn (one Fight does
-- not always kill an unbroken Lobo).  With it, LOCKE banks a point (a Defend) and then waits on his command window,
-- his turn up and the battle running, until when() says so, and Fights it at 2 BP (three swings), so the hit comes
-- at that moment; the others Defend.  A moment his window missed comes round again with the Marshal's next
-- rotation.
local function fightLobo(slot, when, what)
  return H.lazy(function()
    local plan = {}
    if when then
      plan = { { who = LOCKE, defend = true }, { who = LOCKE, cmd = 0x00, slot = slot, boost = 2, openWhen = when } }
    else
      for round = 1, 3 do
        for i = 0, 3 do
          local id = H.readByte(0x3ED8 + 2 * i)
          if id ~= 0xFF and H.readWord(0x3BF4 + 2 * i) > 0 then
            plan[#plan + 1] = { who = id, cmd = 0x00, slot = slot }
          end
        end
      end
    end
    H.assertEq(#plan >= 1, true, "marshal (" .. what .. "): a member stands to Fight a Lobo")
    local function down()
      for _, s in ipairs(lobosStanding()) do if s == slot then return false end end
      return true
    end
    return H.seqStep({
      H.kitBattle(plan, { idle = "defend", care = false, maxFrames = 20000, giveUp = down }),
      H.call(function()
        H.assertEq(down(), true, string.format("marshal (%s): the Lobo in slot %d fell", what, slot))
      end),
    })
  end)
end
function aloneCase(kind)
  local W, t0
  local function lineAfter(i) return W.find(0x21, 0x8F, i) end
  local steps = {
    H.call(function()
      W = aloneW
      H.setPad({})
      W.req = H.requestLoadState(battleSnap.blob)
    end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(W.req, "the battle's open restored (" .. kind .. ")")
      H.rearmInputInjection()
      W.reset()
      W.on = true
      H.log(string.format("[marshal] f%d alone case %s, from the battle's open", H.frame, kind))
    end),
  }
  if kind == "alone" then
    steps[#steps + 1] = fightLobo(0, nil, kind)
    steps[#steps + 1] = fightLobo(1, nil, kind)
    steps[#steps + 1] = H.call(function()
      t0 = { turn = #W.turns, i = #W.cmds + 1, f = H.frame, announced = (marshalMvar() & 0x02) ~= 0 }
      H.log(string.format("[marshal] f%d both Lobos down at his turn %d%s", H.frame, t0.turn,
        t0.announced and " (already announced: the move comes first, the announced case's rule)" or ""))
    end)
    -- (an announce made before the last Lobo fell fires first; the count starts after it)
    steps[#steps + 1] = H.cond(function() return t0.announced end, {
      H.kitBattle({}, { idle = "defend", care = true, maxFrames = 6000,
        giveUp = function() return W.find(0x30, 0x08, t0.i) ~= nil end }),
      H.call(function()
        H.assertEq(W.find(0x30, 0x08, t0.i) ~= nil, true, "marshal (alone): the move announced before the last Lobo "
          .. "fell came")
        t0 = { turn = #W.turns, i = #W.cmds + 1, f = H.frame }
      end),
    }, {})
    steps[#steps + 1] = H.kitBattle({}, { idle = "defend", care = true, maxFrames = 12000,
      giveUp = function() return #W.turns >= t0.turn + 4 end })
    steps[#steps + 1] = H.call(function()
      H.assertEq(#W.turns >= t0.turn + 4, true, "marshal (alone): four more of his turns came")
      H.assertEq(lineAfter(t0.i) == nil, true, "marshal (alone): no announce in four of his turns alone")
      local bad = {}
      for j = t0.i, #W.cmds do
        local c = W.cmds[j]
        if c.turn > t0.turn and not (c.cmd == 0x00 and (c.arg == 0xEE or c.arg == 0xEF)) and c.cmd ~= 0x2F then
          bad[#bad + 1] = string.format("$%02X/$%02X", c.cmd, c.arg)
        end
      end
      H.assertEq(table.concat(bad, " "), "", "marshal (alone): his turns are vanilla's alone block (Battle or "
        .. "Special, the switch's clear aside)")
      H.log("[marshal] PASS alone")
    end)
  else
    local armedAt, lined
    steps[#steps + 1] = fightLobo(0, nil, kind)
    if kind == "dropped" then
      -- armed (switch 0) and not yet announced (switch 1, set by the announce)
      steps[#steps + 1] = fightLobo(1, function()
        if (marshalMvar() & 0x03) == 0x01 then
          armedAt = { turn = #W.turns, f = H.frame, i = #W.cmds + 1 }
          return true
        end
        return false
      end, kind)
      steps[#steps + 1] = H.call(function()
        H.assertEq(#W.turns, armedAt.turn, "marshal (dropped): the last Lobo fell before his next turn (the "
          .. "case's precondition)")
        H.assertEq(lineAfter(armedAt.i), nil, "marshal (dropped): no announce since he armed when the last Lobo fell")
      end)
      steps[#steps + 1] = H.kitBattle({}, { idle = "defend", care = true, maxFrames = 6000,
        giveUp = function() return #W.turns >= armedAt.turn + 2 end })
      steps[#steps + 1] = H.call(function()
        H.assertEq(lineAfter(armedAt.i), nil, "marshal (dropped): no announce on his turns alone")
        H.assertEq(marshalMvar() & 0x03, 0, "marshal (dropped): his armed fuse was dropped (switches 0 and 1 clear)")
        H.log("[marshal] PASS dropped")
      end)
    else
      -- announced (switch 1): the line said, the move to come
      steps[#steps + 1] = fightLobo(1, function()
        if (marshalMvar() & 0x02) ~= 0 then
          lined = { turn = #W.turns, i = #W.cmds + 1 }
          return true
        end
        return false
      end, kind)
      steps[#steps + 1] = H.call(function()
        H.assertEq(#W.turns, lined.turn, "marshal (announced): the last Lobo fell before his move's turn (the "
          .. "case's precondition)")
      end)
      steps[#steps + 1] = H.kitBattle({}, { idle = "defend", care = true, maxFrames = 6000,
        giveUp = function() return #W.turns >= lined.turn + 1 and W.find(0x30, 0x08, lined.i) ~= nil end })
      steps[#steps + 1] = H.call(function()
        local i = W.find(0x30, 0x08, lined.i)
        H.assertEq(i ~= nil and W.cmds[i].turn == lined.turn + 1, true, "marshal (announced): the move (fill_atb, "
          .. "$30/$08) came on his next turn, alone")
        H.log("[marshal] PASS announced")
      end)
    end
  end
  steps[#steps + 1] = H.call(function() W.on = false end)
  return H.seqStep(steps)
end
-- every command a Lobo dispatches (ExecCmd with x a Lobo's entity), for "the Lobos come in with him"
LOBO_ACTS = {}
emu.addMemoryCallback(function()
  local x = emu.getState()["cpu.x"] & 0xFF
  if x >= 8 and x < 20 and H.readWord(0x57C0 + (x - 8)) == 0x019 then
    LOBO_ACTS[#LOBO_ACTS + 1] = { f = H.frame, cmd = H.readByte(0xB5) }
  end
end, emu.callbackType.exec, H.sym("_dispatcher"), H.sym("_dispatcher"))

local function defenseWon() return (H.readByte(0x1f46) & 0x02) == 0 end
local function calm(n)
  local cnt = 0
  return function()
    cnt = (H.hasControl() and H.tileAligned()) and cnt + 1 or 0
    return cnt >= n
  end
end
local function marshalAdjacent()
  return math.abs(MX - H.fieldX()) + math.abs(MY - H.fieldY()) == 1
end
-- gen_moogle's Y-switch: tap Y until the leader offset says squad p is active; a wave that collides mid-switch is
-- fought by the fight driver the waves use
local function ySwitchTo(p)
  local n, own = 0, 0
  local fights = H.climbFights("Y-switch to party " .. p)
  return H.withReset(H.driveUntil(function()
    return H.readWord(0x0803) == LEADER_OFF[p]
  end, 1800 + 40000, {
    H.call(function()
      if fights() then n = 0; return end
      own = own + 1
      H.assertEq(own <= 1800, true, string.format("Y-switch to party %d within 1800 frames outside battle", p))
      if H.dialogWaiting() then
        aPhase = (aPhase + 1) % 8
        H.setPad(aPhase < 4 and { "a" } or {})
        n = 0
        return
      end
      if not H.hasControl() then H.setPad({}); n = 0; return end
      n = n % 46 + 1
      H.setPad(n <= 6 and { "y" } or {})
    end),
  }, "Y-switch to party " .. p), function() n, own = 0, 0 end)
end

-- The cap: the waves, its three cases and the three alone cases ran to f42,801 (wt/v051-tg-wob1), so 90,000 is about
-- 2x the longest.
H.run({ maxFrames = 90000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "control on the defense map"),
  H.call(function()
    H.assertEq(H.mapId(), 51, "moogle_defense stands on map 51")
    H.assertEq(defenseWon(), false, "the defense is not won yet ($0631 set)")
  end),
  -- gen_moogle's deployment and waves: KUSHU's squad on (20,20), MOG's on (15,19), LOCKE's on (14,14)
  H.navTo(15, 15, { maxFrames = 2500, playBattles = true }),
  ySwitchTo(3),
  H.navTo(20, 20, { maxFrames = 4000, playBattles = true }),
  ySwitchTo(2),
  H.navTo(15, 19, { maxFrames = 4000, playBattles = true }),
  ySwitchTo(1),
  H.navTo(14, 14, { maxFrames = 2500, playBattles = true }),
  H.advanceStory(function() return (H.readByte(0x1f41) & 0xFC) == 0 end, 60000,
    { playBattles = "tactical", reserve = {} }),
  H.waitUntil(calm(30), 1800, "the waves are over"),
  -- (15,19) is on the x=15 corridor every squad walks to the Marshal: MOG's squad steps off it, as in gen_moogle
  ySwitchTo(2),
  H.waitUntil(calm(30), 1800, "MOG's squad active and calm"),
  H.navTo(10, 21, { maxFrames = 4000, playBattles = true }),
  ySwitchTo(1),
  H.waitUntil(calm(30), 1800, "LOCKE's squad active and calm"),
  H.fuseEngage(function()
    local nav = H.navTo(MX, MY - 1, { maxFrames = 15000, playBattles = true,
      arrive = function() return marshalAdjacent() and H.hasControl() and H.tileAligned() end })
    local battN, ph = 0, 0
    return H.seqStep({
      H.cond(function() return marshalAdjacent() end, {}, { nav }),
      H.driveUntil(function()
        battN = (H.battleLoadStarted() and H.monstersPresent() > 0) and battN + 1 or 0
        return battN >= 3
      end, 900, {
        H.call(function()
          ph = (ph + 1) % 8
          if not (H.hasControl() and marshalAdjacent()) then H.setPad({}); return end
          local dx, dy = MX - H.fieldX(), MY - H.fieldY()
          local dir = dx == 1 and "right" or dx == -1 and "left" or dy == 1 and "down" or "up"
          if ph < 2 then H.setPad({ [dir] = true }) elseif ph < 6 then H.setPad({ "a" }) else H.setPad({}) end
        end),
      }, "battle 6 engages"),
    })
  end, MARSHAL, "the Marshal"),
  H.call(function()
    local lobos = 0
    for s = 0, 5 do
      if H.readWord(0x57C0 + s * 2) == LOBO and (H.readByte(0x3AA8 + s * 2) & 1) == 1 then lobos = lobos + 1 end
    end
    H.assertEq(lobos, 2, "the Marshal's battle opens with two Lobos (the fuse's move fills their gauges)")
    battleSnap = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(battleSnap, "the battle's open (the alone cases' snapshot)") end),
  H.fuseCases({
    tag = "marshal", species = MARSHAL, write = WRITE,
    -- the move is marked by its first command, fill_atb on the Lobos (AI $FB $08, dispatched as $30/$08), which only
    -- the fire turn has: his ordinary turns Battle too, so a Battle alone does not single the move out (on the merged
    -- ROM's draw his first turn back was a plain Battle).  The two Battles follow it, asserted in `fired`.
    line = 0x8F, move = { cmd = 0x30, atk = 0x08 }, turns = 1, glows = 1,
    arm = "idle", aim = true, openHold = true,
    bossHp = 400,
    lineShot = 30,
    -- his rotation's first turn taken, no fuse armed yet
    partway = function(W)
      local c = W.cells()
      return c ~= nil and #W.turns >= 1 and (c.mvar & 0x01) == 0
    end,
    fired = function(C, W, n)
      local function battles()
        local k = 0
        for j = C.lines[n].move.i + 1, #W.cmds do
          local c = W.cmds[j]
          if c.turn == C.lines[n].move.turn and c.cmd == 0x00 and c.arg == 0xEE then k = k + 1 end
        end
        return k
      end
      local mv = C.lines[n].move
      local function lobosActed()
        local n2 = 0
        for _, a in ipairs(LOBO_ACTS) do if a.f > mv.f then n2 = n2 + 1 end end
        return n2
      end
      local want = 0
      for s = 0, 5 do
        if H.readWord(0x57C0 + s * 2) == LOBO and H.monStanding(s) then want = want + 1 end
      end
      return H.seqStep({
        H.waitUntil(function() return battles() >= 2 end, 1200, "marshal: his two Battles after the Lobos' gauges"),
        H.call(function()
          H.assertEq(battles(), 2, string.format("marshal: two Battles ($00/$EE) follow the Lobos' gauges in the fire "
            .. "turn (case %s)", C.name))
        end),
        H.waitUntil(function() return lobosActed() >= want or #W.turns > mv.turn end, 1500,
          "marshal: the Lobos act, or his next turn"),
        H.call(function()
          H.assertEq(lobosActed() >= want, true, string.format("marshal: each standing Lobo (%d) acted after its gauge "
            .. "was filled and before his next turn (%d did; case %s)", want, lobosActed(), C.name))
        end),
      })
    end,
    earned = function(C, W)
      local pre, post, l2 = C.brk.pre, C.brk.post, C.lines[2]
      H.assertEq(pre.mvar & 0x01, 1, "marshal: monster switch 0 stood at the break (the fuse was armed)")
      H.assertEq(post.mvar & 0x01, 0, "marshal: monster switch 0 is clear after the cancel")
      H.assertEq(post.mvar & 0x02, 0, "marshal: monster switch 1 (announced) is clear after the cancel")
      -- his rotation from its first turn: two turns, then the line (he announces only while a Lobo stands, and the
      -- case's Lobos stand: the others Defend)
      local back = l2.turn - C.rec.turn
      H.assertEq(back, 3, string.format("marshal: the trigger was earned again in full: the line returned on his "
        .. "turn %d back (his rotation's two turns, then the line)", back))
    end,
  }),
  H.logStep("[marshal] PASS: the announce, the schedule, the cancel and the trigger earned again"),
  -- The alone cases (the lead, 2026-11-24: the line plays only while a Lobo stands), each from the battle's open,
  -- played through the menu (the Lobos Fought down by aimed Fights; nothing written):
  --   alone      both Lobos down at once: for four of his turns no line, and each turn vanilla's alone block
  --              (one of Battle or Special, $00/$EE or $00/$EF);
  --   dropped    one Lobo down, then the other as soon as his rotation arms the fuse (monster switch 0) and before
  --              his next turn: that turn is the alone block, no line, and switch 0 is clear after it;
  --   announced  one Lobo down, then the other once he has said "Strike as one!": the move (fill_atb, $30/$08)
  --              comes on his next turn all the same.
  -- Mutant: marshal_never_alone (his alone block's `if_num_monsters 1` made 0) is red at "alone: no announce".
  H.call(function() aloneW = H.fuseWatch(MARSHAL, WRITE) end),
  aloneCase("alone"),
  aloneCase("dropped"),
  aloneCase("announced"),
  H.logStep("[marshal] PASS: the alone cases"),
})
