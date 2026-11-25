-- @suite savestate=ultros3_entry slow
-- battle_ultros3.lua -- the bridge Ultros under the boss contract (docs/design/bosses-wob.md block 17,
-- wt/v052-tg-wob3): his advance is his telegraph, and a break cancels it.
--
-- His script (ai_script.asm AIScript::_302): each rotation (two of his turns) he creeps a step forward (battle
-- variable 1, his steps), and the party's blows push him back a step (his counter's tally, battle variable 3: a
-- Fight 1, a spell 4; at 8, once he stands two steps out).  At 4 steps, the turn that finds him at the edge ARMS the
-- fuse (monster switch 0; switch 1: he holds the edge); "He looms over you!" (battle dialogue $96) and a glow
-- announce it on his next turn, Aqua Rake (attack $8E, command $0C) comes on the turn after, and his turn after
-- that is vanilla's sink back to the start (his steps to 0, switch 1 clear).  While he holds the edge no blow pushes
-- him back (the counter's step back waits on switch 1).  Under the contract (Ot6FuseTbl's row $012E) a break while
-- it is lit cancels the wave: switch 0 goes, switch 1 stays, and his first turn back is the sink.
--
-- Boots ultros3_entry (gen_ultros: the statue room after the lore scene, above his trigger), walks down onto it
-- (battle 125: TERRA, LOCKE, STRAGO and RELM) and plays the battle from a snapshot at its open (M.fuseCases,
-- lib/ot6.lua, where the cases and the DECLARED staging are written out: the gauge, the row's classes for the
-- breaking Fight, HP held -- his at 20,000, above his Haste line, 15,360, and RELM's scene, 10,240):
--   unbroken  the party Defends (no blow pushes him back); the line shows once he stands at the edge; the lit-fuse
--             mark stands before his shield emblem; Aqua Rake is dispatched on his next turn, a glow between; the
--             mark goes; the line reads "He looms over you!" where the relocated dialogue table points.
--   broken    an aimed Fight confirmed once the mark is up breaks him: the cancel fires, the mark goes, switch 0
--             reads clear and switch 1 set, no wave on his first turns back; his first turn back is the sink (his
--             steps 0, switch 1 clear after it), and the line returns only after four more steps; the wave follows.
--   outside   a break two steps out, before any line: nothing is cancelled and the cells stand, two aimed Fights in
--             the window wind nothing, and the fuse then lights and fires as in the first case.
--   held      (below) the party Fights through a whole fuse from the arming to the wave, past the tally that pushes
--             him back: his steps stay at 4 until the wave, and the sink follows it.
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wob3/mutants/): fuse_never (Ot6FuseCancel+3=80) is red
-- at "the break during the fuse cancels it"; u3_row_keeps (his row keeps switch 0: +5 = $FF) at "monster switch 0 is
-- clear after the cancel"; u3_no_hold (the counter's step-back gate reads switch 7) at "held: his steps stayed at 4
-- from the arming to the wave"; u3_no_sink (the sink block's `set_battle_var 1, 0` sets 3) at "his first turn back
-- is the sink"; dlg_ptr (line $96's table word one byte late) at "the line reads".  A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and the held case
-- the gauge, through the same pair, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/ultros3_entry.mss.lua"

local ULTROS3, EDGE = 0x12E, 4
local function map() return H.mapId() & 0x3ff end
local function steps() return H.readByte(0x3EB1) end    -- battle variable 1: his steps
local function tally() return H.readByte(0x3EB3) end    -- battle variable 3: the counter's tally of blows

-- his steps and his switches, frame by frame while on (the cancel's cells are read two frames after the break)
local track, trackOn = {}, false
local function trackRec() return track[#track] end

-- the held case: from a line's arming (switch 1 set) the whole party Fights (the gauge staged to 63, DECLARED, so
-- the Fights only chip) until the wave; his steps must stay at the edge though the tally passes 8, and the sink
-- must follow.
function held()
  local W, armedF, waveF, minSteps, maxTally, sinkSeen = nil, nil, nil, 99, 0, nil
  local function sw1()
    local e = W.ent()
    return e ~= nil and H.readByte(0x3DAC + e) & 0x02 ~= 0
  end
  return H.seqStep({
    H.call(function()
      W = H.fuseWatch(ULTROS3, WRITE); W.on = true; W.pin = { boss = 20000, party = true }
      emu.addEventCallback(function()
        if not W.on then return end
        if armedF and not waveF then
          minSteps = math.min(minSteps, steps())
          maxTally = math.max(maxTally, tally())
        end
      end, emu.eventType.endFrame)
    end),
    -- (no fuse armed or lit as the case opens: the party Defends until switch 1 is clear)
    H.kitBattle({}, { idle = "defend", care = false, maxFrames = 12000,
      giveUp = function() return not sw1() and not W.litBit() end }),
    H.kitBattle({}, { idle = "defend", care = false, maxFrames = 30000,
      giveUp = function() return sw1() or not H.battleLoadStarted() end }),
    H.call(function()
      H.assertEq(sw1(), true, "held: he reached the edge (monster switch 1 set) with the party Defending")
      armedF = H.frame
      WRITE.byte(0x3E38 + W.ent(), 63)   -- (DECLARED: the gauge held, so the Fights only chip)
      H.log(string.format("[ultros3] held: armed at f%d, steps %d, tally %d; the party Fights through the fuse",
        armedF, steps(), tally()))
    end),
    H.lazy(function()
      local plan = {}
      for k = 1, 24 do
        for i = 0, 3 do
          local id = H.readByte(0x3ED8 + 2 * i)
          if id ~= 0xFF then plan[#plan + 1] = { who = id, cmd = 0x00, boost = 0, slot = W.slot() } end
        end
      end
      return H.kitBattle(plan, { idle = "defend", care = false, maxFrames = 20000,
        giveUp = function() return W.find(0x0C, 0x8E, 1) ~= nil or not H.battleLoadStarted() end })
    end),
    H.call(function()
      local mi, mc = W.find(0x0C, 0x8E, 1)
      H.assertEq(mi ~= nil, true, "held: the wave came after the arming")
      waveF = mc.f
      H.log(string.format("[ultros3] held: the wave at f%d; from the arming the tally rose to %d, the steps fell to "
        .. "%d at the least", waveF, maxTally, minSteps))
      H.assertEq(maxTally >= 8, true, string.format("held: the party's Fights between the arming and the wave "
        .. "passed the tally that pushes him back (%d of 8; the case's precondition)", maxTally))
      H.assertEq(minSteps, EDGE, "held: his steps stayed at 4 from the arming to the wave (no blow pushed him back "
        .. "while he held the edge)")
    end),
    H.kitBattle({}, { idle = "defend", care = false, maxFrames = 8000,
      giveUp = function()
        if not sinkSeen and steps() == 0 and not sw1() then sinkSeen = H.frame end
        return sinkSeen ~= nil or not H.battleLoadStarted()
      end }),
    H.call(function()
      H.assertEq(sinkSeen ~= nil, true, "held: the sink followed the wave (his steps 0, switch 1 clear)")
      local n = 0
      for _, t in ipairs(W.turns) do if t.f > waveF and t.f <= sinkSeen then n = n + 1 end end
      H.assertEq(n, 1, string.format("held: the sink came on his turn after the wave (%d turn(s))", n))
      W.on = false; W.pin = nil
    end),
  })
end

-- The cap: three cases of about 12,000 frames each and the held case's about 15,000, so 120,000 is about 2x.
H.run({ maxFrames = 120000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control in the statue room"),
  H.call(function()
    H.assertEq(map(), 371, "ultros3_entry stands in the statue room (map 371)")
    H.assertEq(H.fieldX(), 15, "on column 15, above his trigger (15,22)")
    emu.addEventCallback(function()
      if not trackOn then return end
      local r = trackRec()
      local s = steps()
      if r == nil or r.steps ~= s then track[#track + 1] = { f = H.frame, steps = s } end
    end, emu.eventType.endFrame)
  end),
  H.fuseEngage(function()
    local ph = 0
    return H.driveUntil(function() return H.battleLoadStarted() end, 8000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({ down = true })
      end),
    }, "walk down onto (15,22): battle 125")
  end, ULTROS3, "the bridge Ultros"),
  H.call(function() H.setPad({}); trackOn = true end),
  H.fuseCases({
    tag = "ultros3", species = ULTROS3, write = WRITE,
    line = 0x96, move = { cmd = 0x0C, atk = 0x8E }, turns = 1, glows = 1,
    lineText = "He looms over you!{wait}",
    arm = "idle", aim = true,
    bossHp = 20000,
    -- two steps out, neither switch set
    partway = function(W)
      local c = W.cells()
      return c ~= nil and steps() >= 2 and (c.mvar & 0x03) == 0
    end,
    earned = function(C, W)
      local pre, post, l2 = C.brk.pre, C.brk.post, C.lines[2]
      H.assertEq(pre.mvar & 0x03, 0x03, "ultros3: switches 0 and 1 stood at the break (armed, at the edge)")
      H.assertEq(post.mvar & 0x01, 0, "ultros3: monster switch 0 is clear after the cancel")
      H.assertEq(post.mvar & 0x02, 0x02, "ultros3: monster switch 1 stands after the cancel (he is still at the edge)")
      -- the first turn back: the sink (monster entry/exit commands, $24; no attack), his steps 0 after it
      local first, k1 = nil, nil
      for k, t in ipairs(W.turns) do if t.f > C.brk.f and first == nil then first, k1 = t, k end end
      H.assertEq(first ~= nil, true, "ultros3: he took a turn after the break")
      local exits, attacks = 0, 0
      for _, c in ipairs(W.cmds) do
        if c.turn == k1 then
          if c.cmd == 0x24 then exits = exits + 1 end
          if c.cmd < 0x20 then attacks = attacks + 1 end
        end
      end
      local s0 = nil
      for _, r in ipairs(track) do if r.f > first.f and r.f < l2.f and r.steps == 0 then s0 = s0 or r.f end end
      H.log(string.format("[ultros3] his first turn back (f%d): %d entry/exit command(s), %d attack(s); his steps "
        .. "read 0 at f%s", first.f, exits, attacks, tostring(s0)))
      H.assertEq(exits >= 2 and attacks == 0 and s0 ~= nil, true, "ultros3: his first turn back is the sink (he sinks "
        .. "and returns, no attack, his steps 0 after it)")
      -- four more steps before the second line
      local ups = 0
      for k = 2, #track do
        if track[k].f > s0 and track[k].f < l2.f and track[k].steps == track[k - 1].steps + 1 then ups = ups + 1 end
      end
      H.log(string.format("[ultros3] %d step(s) forward between the sink and the second line", ups))
      H.assertEq(ups >= EDGE, true, "ultros3: the second line came only after four more steps from the start")
    end,
  }),
  held(),
  H.logStep("[ultros3] PASS: the advance, the announce, the wave, the cancel and the sink"),
})
