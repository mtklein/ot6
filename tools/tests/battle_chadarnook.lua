-- @suite savestate=chadarnook_entry slow
-- battle_chadarnook.lua -- the demon Chadarnook under the boss contract (docs/design/bosses-wor.md block 11,
-- wt/v052-tg-wor1): his clock's swap to the goddess is his telegraph, and a break holds him on the canvas.
--
-- The demon's script (ai_script.asm AIScript::_328): his turn with his clock run (40 counts) says "The paint runs!"
-- (battle dialogue $A3) and glows, a turn of its own, and on his next turn the swap: the goddess shown, the demon
-- gone (command $24, the entry/exit, dispatched by him).  While it is lit his counter's swap (the fifth hit of his
-- tally) waits on monster switch 0, which the announce sets: the swap that comes is the announced one.  Under the
-- contract (Ot6FuseTbl's row $0148, OT6_FUSE_TIMER | OT6_FUSE_VAR2) a break while it is lit cancels it: switch 0
-- goes, his clock restarts and his tally of hits (battle variable 2 now, vanilla 0) is cleared.  The goddess has no
-- gauge and no row: hitting her is the fight's mistake (Phantasm), so every Fight here is aimed at the demon.
--
-- Boots chadarnook_entry (gen_wor_relm: Chadarnook's battle, event battle 86, as it comes up: the goddess on the
-- canvas; she swaps the demon in on her second turn).  From a snapshot at the battle's open:
--   landed    (M.fuseLanded, lib/ot6.lua) nothing staged and nothing held: the party Defends; the goddess brings the
--             demon in, his clock runs, the line comes and the swap on his next turn: the demon leaves the field.
--   then the three cases from the same snapshot (M.fuseCases, where the cases and the DECLARED staging are written
--   out: the gauge, the row's classes for the breaking Fight, HP held -- his at 12,000, under the 15,360 line of his
--   Flash Rain rotation, the band the landed case's demon (at full HP) does not meet, and the party's at 9,999):
--   unbroken  two aimed Fights on the demon, then the party Defends; the line shows once his clock has run; the
--             lit-fuse mark stands; the swap is dispatched on his next turn, a glow between; the mark goes; the line
--             reads "The paint runs!" where the relocated dialogue table points.
--   broken    two aimed Fights (his tally at 2), the line, then an aimed Fight confirmed once the mark is up breaks
--             him: the cancel fires, the mark goes, switch 0 and his clock read 0 and his tally 0 (or the breaking
--             blow's own 1), no swap on his first turns back, and the line returns only once his clock has run 40
--             counts again; the swap follows.
--   outside   a break with no fuse lit and his clock short of 40: nothing is cancelled and the cells stand, and the
--             fuse then lights and fires.
--   held      (below) the counter's swap held while lit: his tally staged to 4 at the line (DECLARED: the fifth hit
--             swaps him), his gauge held at 63 (DECLARED), and an aimed Fight in the fuse: the hit lands and is counted,
--             he stays on the canvas, and the swap comes on his next turn, the announced one (three tries: a draw can
--             bring his turn before the hit).
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wor1/mutants*/): fuse_never (Ot6FuseCancel+3=80) is red
-- at "the break during the fuse cancels it"; chad_no_var2 (his row's flags without OT6_FUSE_VAR2) at "his tally is
-- cleared by the cancel"; chad_no_timer (his row's flags without OT6_FUSE_TIMER) at "his clock restarts at the
-- cancel"; chad_no_hold (the counter's hold reads switch 7) at "held: he stays on the canvas".  A mechanism test, not
-- play (the landed case writes nothing).
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them; the held case stages
-- the tally and holds the gauge through the same pair; nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/chadarnook_entry.mss.lua"

local GODDESS, DEMON, LINE = 0x11E, 0x148, 0xA3
local function present(sp)
  for s = 0, 5 do
    if H.readByte(0x3AA8 + s * 2) & 1 == 1 and H.readWord(0x57C0 + s * 2) == sp then return s end
  end
  return nil
end

-- the party's play while the fuse arms: two aimed Fights on the demon (his tally to 2: the fifth hit swaps him), then
-- Defends; the others Defend throughout
local function armTwo(pred, max, W)
  local t0 = nil
  return H.lazy(function()
    t0 = H.frame
    local plan = {}
    for i = 0, 3 do
      local id = H.readByte(0x3ED8 + 2 * i)
      if id ~= 0xFF and #plan < 2 then plan[#plan + 1] = { who = id, cmd = 0x00, boost = 0, slot = W.slot() } end
    end
    return H.kitBattle(plan, { idle = "defend", care = false, maxFrames = max + 600,
      giveUp = function() return pred() or H.frame - t0 >= max end })
  end)
end

-- held: the counter's swap waits while the paint runs
local function heldCase(S)
  local W = H.fuseWatch(DEMON, WRITE)
  local C = { tries = 0 }
  local function say(s) H.log(string.format("[chadarnook] f%d held: %s", H.frame, s)) end
  local function lineFrom(i) return W.find(0x21, LINE, i) end
  local function swapFrom(i) return W.find(0x24, nil, i) end
  local function one()
    return H.cond(function() return C.done == nil and C.tries < 3 end, {
      H.call(function()
        C.tries = C.tries + 1
        C.from = #W.cmds + 1
        C.hold = true
        say(string.format("try %d: the party Defends until the demon announces", C.tries))
      end),
      H.lazy(function()
        local t0 = H.frame
        return H.kitBattle({}, { idle = "defend", care = false, maxFrames = 40000,
          giveUp = function() return lineFrom(C.from) ~= nil or H.frame - t0 >= 39000 end })
      end),
      H.call(function()
        local li, lc = lineFrom(C.from)
        H.assertEq(li ~= nil, true, "held: the demon announced (his clock ran)")
        C.li = li
        WRITE.byte(0x3EB2, 4)  -- (DECLARED: his tally staged to 4, so the next hit is the fifth)
        C.partyAt = #W.party
        say(string.format("the line on his turn %d (f%d); his tally staged to 4; one aimed Fight follows", lc.turn,
          lc.f))
      end),
      H.lazy(function()
        local who = nil
        for i = 0, 3 do
          local id = H.readByte(0x3ED8 + 2 * i)
          if id ~= 0xFF and H.readWord(0x3BF4 + 2 * i) > 0 and who == nil then who = id end
        end
        local t0 = H.frame
        return H.kitBattle({ { who = who, cmd = 0x00, boost = 0, slot = W.slot() } }, { idle = "defend", care = false,
          maxFrames = 4000, giveUp = function()
            return #W.party > C.partyAt or swapFrom(C.li) ~= nil or W.ent() == nil or H.frame - t0 >= 3600
          end })
      end),
      -- the hit's counter runs after the hit: a few frames, then his next turn and its swap
      H.lazy(function()
        local t0 = H.frame
        return H.kitBattle({}, { idle = "defend", care = false, maxFrames = 6000,
          giveUp = function() return swapFrom(C.li) ~= nil or H.frame - t0 >= 5400 end })
      end),
      H.call(function()
        local sw = swapFrom(C.li)
        local hitF = W.party[C.partyAt + 1] and W.party[C.partyAt + 1].f
        say(string.format("the Fight dispatched at %s; the swap at %s", tostring(hitF), sw and ("f" .. W.cmds[sw].f)
          or "none"))
        if hitF == nil or sw == nil or hitF > W.cmds[sw].f then
          say("his turn came before the hit: the case waits for his next visit")
          C.hold = true
          return
        end
        C.done = { li = C.li, sw = sw, hitF = hitF, tally = H.readByte(0x3EB2) }
      end),
    }, {})
  end
  return H.seqStep({
    H.fuseRestore(S, "chadarnook held"),
    H.call(function()
      W.reset(); W.on = true; W.pin = { party = true }
      -- (DECLARED: his gauge held at 63, so no hit of the case breaks him; the frame callback below)
      emu.addEventCallback(function()
        if not W.on or not C.hold then return end
        local e = W.ent()
        if e and H.readByte(0x3E88 + e) == 0 and H.readByte(0x3E38 + e) ~= 63 then WRITE.byte(0x3E38 + e, 63) end
      end, emu.eventType.endFrame)
    end),
    one(), one(), one(),
    H.call(function()
      H.assertEq(C.done ~= nil, true, "held: an aimed Fight landed in the fuse, before his next turn, in one of three "
        .. "tries")
      local d = C.done
      local l, s = W.cmds[d.li], W.cmds[d.sw]
      H.log(string.format("[chadarnook] held: line f%d (turn %d), the fifth hit dispatched f%d, the swap f%d (turn %d, "
        .. "%s); his tally then %d", l.f, l.turn, d.hitF, s.f, s.turn, s.retal and "a counter's" or "his turn's",
        d.tally))
      H.assertEq(s.retal, false, "held: the swap that came is his turn's (the announced one), not his counter's: the "
        .. "fifth hit in the fuse did not send him off")
      H.assertEq(s.turn - l.turn, 1, "held: he stays on the canvas, and the swap comes on his next turn after the line")
      W.on = false
      say("PASS held")
    end),
  })
end

-- his tally (battle variable 2) at each break of the demon (Ot6HitBroke, before the cancel's clears) and two frames
-- after it
local tallyAt = {}
local function tallyWatch()
  emu.addMemoryCallback(function()
    local s = present(DEMON)
    if s and (emu.getState()["cpu.y"] & 0xFF) == 8 + 2 * s then
      tallyAt[#tallyAt + 1] = { f = H.frame, pre = H.readByte(0x3EB2) }
    end
  end, emu.callbackType.exec, H.sym("Ot6HitBroke"), H.sym("Ot6HitBroke"))
  emu.addEventCallback(function()
    local t = tallyAt[#tallyAt]
    if t and t.post == nil and H.frame >= t.f + 2 then t.post = H.readByte(0x3EB2) end
  end, emu.eventType.endFrame)
end

local S = {}
-- The cap: the goddess's two turns and the demon's clock are about 3,000 frames a case; five cases; 120,000 is about
-- 2x.
H.run({ maxFrames = 120000 }, {
  H.loadState(STATE),
  H.waitUntil(function() return H.battleActive() end, 3000, "Chadarnook's battle is up", 2),
  H.call(function()
    H.assertEq(present(GODDESS) ~= nil, true, "the goddess stands at the open (chadarnook_entry)")
    H.assertEq(present(DEMON), nil, "the demon is not on the field at the open (the goddess swaps him in)")
    tallyWatch()
  end),
  H.fuseSnap(S),
  H.fuseLanded({
    tag = "chadarnook", species = DEMON, line = LINE, move = { cmd = 0x24 }, turns = 1,
    landed = function(W, l, m)
      H.log(string.format("[chadarnook] landed: the swap dispatched at f%d; the demon %s, the goddess %s", m.f,
        present(DEMON) and "still on the field" or "gone", present(GODDESS) and "on the field" or "gone"))
      H.assertEq(present(DEMON) == nil and present(GODDESS) ~= nil, true, "chadarnook landed: the swap landed (the "
        .. "demon gone, the goddess shown)")
    end,
  }),
  H.fuseRestore(S, "chadarnook"),
  H.fuseCases({
    tag = "chadarnook", species = DEMON, write = WRITE,
    line = LINE, move = { cmd = 0x24 }, turns = 1, glows = 1,
    lineText = "The paint runs!{wait}",
    arm = armTwo, aim = true,
    bossHp = 12000,
    -- the demon on the field, no fuse lit, his clock short of 40 counts
    partway = function(W)
      local c = W.cells()
      return c ~= nil and not W.litBit() and c.timer < 60
    end,
    earned = function(C, W)
      local pre, post = C.brk.pre, C.brk.post
      local var2 = H.readByte(0x3EB2)
      for _, t in ipairs(tallyAt) do if t.f == C.brk.f then C.tally = t end end
      H.log(string.format("[chadarnook] at the break: switches $%02X, clock %d; after: switches $%02X, clock %d; his "
        .. "tally %d now", pre.mvar, pre.timer, post.mvar, post.timer, var2))
      H.assertEq(pre.mvar & 0x01, 0x01, "chadarnook: monster switch 0 (the counter's hold) stood at the break")
      H.assertEq(post.mvar & 0x01, 0, "chadarnook: monster switch 0 is clear after the cancel")
      H.assertEq(post.timer < 16, true, string.format("chadarnook: his clock restarts at the cancel (%d after it)",
        post.timer))
      H.assertEq(C.tally ~= nil and C.tally.pre >= 2, true, string.format("chadarnook: his tally stood at 2 or more at "
        .. "the break (%s)", tostring(C.tally and C.tally.pre)))
      H.assertEq(C.tally.post <= 1, true, string.format("chadarnook: his tally is cleared by the cancel (%d two frames "
        .. "after it: the breaking blow's own count may stand)", C.tally.post))
      local l2 = C.lines[2]
      H.log(string.format("[chadarnook] the second line with his clock at %d", l2.cells.timer))
      H.assertEq(l2.cells.timer >= 80, true, "chadarnook: the line returns only once his clock has run 40 counts again")
    end,
  }),
  heldCase(S),
  H.logStep("[chadarnook] PASS: the clock's announce, the swap, the cancel that holds him, and the hold of his "
    .. "counter's swap"),
})
