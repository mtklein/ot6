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

-- The cap: the waves and its three cases ran to f30,874 (wt/v051-tg-wob1), so 65,000 is about 2x the longest.
H.run({ maxFrames = 65000 }, {
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
  end),
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
      -- his rotation from its first turn: two turns before the line with a Lobo standing, one (the alone block's,
      -- which arms on every turn) once both are down
      local lobos = 0
      for s = 0, 5 do
        if H.readWord(0x57C0 + s * 2) == LOBO and H.monStanding(s) then lobos = lobos + 1 end
      end
      local back, want = l2.turn - C.rec.turn, lobos > 0 and 3 or 2
      H.assertEq(back, want, string.format("marshal: the trigger was earned again in full: the line returned on "
        .. "his turn %d back (%d Lobo(s) standing: his rotation's %s)", back, lobos,
        lobos > 0 and "two turns, then the line" or "alone block arms, then the line"))
    end,
  }),
  H.logStep("[marshal] PASS: the announce, the schedule, the cancel and the trigger earned again"),
})
