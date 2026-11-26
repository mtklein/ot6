-- @suite savestate=wor_grave slow
-- battle_dullahan.lua -- Dullahan under the boss contract (docs/design/bosses-wor.md block 2, wt/v052-tg-wor1): the
-- hit counter is his telegraph, and a break cancels Absolute 0 and clears the count.
--
-- His script (ai_script.asm AIScript::_284): every blow that strikes him is counted (his counter, battle variable 3
-- now, vanilla 1); on his first turn with eight counted, "Its blade rimes over!" (battle dialogue $A1) and a glow
-- announce it, a turn of its own, and Absolute 0 (attack $BB, command $0C) comes on his next turn.  The count is the
-- fuse block's own condition.  Under the contract (Ot6FuseTbl's row $011C, OT6_FUSE_VAR3) a break while it is lit
-- cancels Absolute 0 and clears the count: eight more blows earn it again.  Blows on a Broken Dullahan count nothing.
-- Absolute 0 comes only announced (his script names it once, in the fuse block: asserted from the ROM).
--
-- Boots wor_grave (gen_wor_falcon: the party on the grave, before the press) and presses the grave as the route does
-- (event battle 85).  Then, from a snapshot at the battle's open:
--   landed    (M.fuseLanded, lib/ot6.lua) nothing staged and nothing held: aimed Fights from the members whose hands
--             chip nothing on his row (M.quietArm: no dagger, blunt or ranged, no fire) earn the count from his full
--             HP down, then the party Defends; Absolute 0 is dispatched on his next turn after the line and lands: a
--             member's HP falls.
--   then the three cases from the same snapshot (M.fuseCases, where the cases and the DECLARED staging are written
--   out: the gauge, the row's classes for the breaking Fight, HP held -- his at 20,000, above Cure 2's line, the
--   band the landed case passes through, and the party's at 9,999):
--   unbroken  eight blows counted; the line shows on his next turn; the lit-fuse mark stands; Absolute 0 is
--             dispatched on his turn after, on every standing member, a glow between; the mark goes; the line reads
--             "Its blade rimes over!" where the relocated dialogue table points.
--   broken    an aimed Fight confirmed once the mark is up breaks him: the cancel fires, the mark goes, battle
--             variable 3 reads 0, no Absolute 0 on his first turns back, and the line returns only after eight more
--             blows are counted; Absolute 0 follows.
--   outside   a break with one to seven blows counted, before any line: nothing is cancelled and the cells (the
--             count among them) stand, two aimed Fights in the window count nothing, and the fuse then lights and
--             fires.
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wor1/mutants*/): fuse_never (Ot6FuseCancel+3=80) is red
-- at "the break during the fuse cancels it"; dull_no_var3 (his row's flags byte 0) at "battle variable 3, his count,
-- is 0 after the cancel"; dull_combo_back (his rotation's Ice 3 turn picks Absolute 0) at "Absolute 0 comes only
-- announced".  A mechanism test, not play (the landed case writes nothing).
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/wor_grave.mss.lua"

local DULLAHAN, ABSOLUTE0, LINE = 0x11C, 0xBB, 0xA1
local function map() return H.mapId() & 0x3ff end

-- battle variable 3, his count, frame by frame while on: each rise is a blow counted
local count, countOn = {}, false
local function risesBetween(f0, f1)
  local n = 0
  for k = 2, #count do
    if count[k].f > f0 and count[k].f < f1 and count[k].v == count[k - 1].v + 1 then n = n + 1 end
  end
  return n
end

-- the party's play while the fuse arms: every member Fights Dullahan, aimed at his slot
local function armByBlows(pred, max, W)
  local t0 = nil
  return H.lazy(function()
    t0 = H.frame
    local plan = {}
    for k = 1, 8 do
      for i = 0, 3 do
        local id = H.readByte(0x3ED8 + 2 * i)
        if id ~= 0xFF then plan[#plan + 1] = { who = id, cmd = 0x00, boost = 0, slot = W.slot() } end
      end
    end
    return H.kitBattle(plan, { idle = "defend", care = true, maxFrames = max + 600,
      giveUp = function() return pred() or H.frame - t0 >= max end })
  end)
end

local S = {}
-- The cap: the press and the open are about 2,000 frames; the landed case about 6,000; three cases of about 12,000
-- each follow; 90,000 is about 2x.
H.run({ maxFrames = 90000 }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.call(function()
    local at = H.aiAttacks(DULLAHAN, ABSOLUTE0)
    H.log(string.format("[dullahan] his turn script names Absolute 0 at %d place(s)", #at))
    H.assertEq(#at, 1, "Absolute 0 comes only announced: Dullahan's turn script names it once (the fuse block)")
    emu.addEventCallback(function()
      if not countOn then return end
      local v = H.readByte(0x3EB3)
      local r = count[#count]
      if r == nil or r.v ~= v then count[#count + 1] = { f = H.frame, v = v } end
    end, emu.eventType.endFrame)
  end),
  H.faceAndHoldA("up", function() return H.battleLoadStarted() end, 3000,
    "the grave (100,14): face up, A (_ca42f1, battle 85)"),
  H.release(),
  H.waitUntil(function()
    for s = 0, 5 do
      if H.readByte(0x3AA8 + s * 2) & 1 == 1 and H.readWord(0x57C0 + s * 2) == DULLAHAN then return H.battleActive() end
    end
    return false
  end, 6000, "Dullahan's battle is up", 2),
  H.call(function()
    H.log(string.format("[dullahan] f%d his battle is up; his count reads %d", H.frame, H.readByte(0x3EB3)))
    H.assertEq(H.readByte(0x3EB3), 0, "his count (battle variable 3) reads 0 at the open")
    countOn = true
  end),
  H.fuseSnap(S),
  H.fuseLanded({
    tag = "dullahan", species = DULLAHAN, line = LINE, move = { cmd = 0x0C, atk = ABSOLUTE0 }, turns = 1,
    -- (the members whose Fight chips nothing on his row -- no dagger, blunt or ranged hand, no fire -- earn the
    -- count, so nothing of the case's own breaks him: a Broken Dullahan's count stands still, and the first run's
    -- Fights through a break took him to 7,435 HP before the line)
    arm = H.quietArm(DULLAHAN, 0x01),
    landed = function(W, l, m)
      local fell = {}
      for i = 0, 3 do
        if H.readByte(0x3ED8 + 2 * i) ~= 0xFF and m.tchars & (1 << i) ~= 0 then
          local now = H.readWord(0x3BF4 + 2 * i)
          if now < m.hp[i] then fell[#fell + 1] = string.format("seat %d %d -> %d", i, m.hp[i], now) end
        end
      end
      H.log(string.format("[dullahan] landed: Absolute 0 on targets $%02X at his HP %d; HP fell: %s", m.tchars,
        H.readWord(0x3BF4 + W.ent()), table.concat(fell, ", ")))
      H.assertEq(#fell >= 1, true, "dullahan landed: Absolute 0 landed (a target's HP fell within 420 frames)")
    end,
  }),
  H.fuseRestore(S, "dullahan"),
  H.fuseCases({
    tag = "dullahan", species = DULLAHAN, write = WRITE,
    line = LINE, move = { cmd = 0x0C, atk = ABSOLUTE0 }, turns = 1, glows = 1,
    lineText = "Its blade rimes over!{wait}",
    arm = armByBlows, aim = true, allTargets = true,
    bossHp = 20000,
    -- one to seven blows counted, no line
    partway = function(W)
      local v = H.readByte(0x3EB3)
      return W.cells() ~= nil and v >= 1 and v <= 7
    end,
    earned = function(C, W)
      local pre, post = C.brk.pre, C.brk.post
      H.assertEq(pre.bvar3 >= 8, true, string.format("dullahan: eight blows were counted at the break (%d)", pre.bvar3))
      H.assertEq(post.bvar3, 0, "dullahan: battle variable 3, his count, is 0 after the cancel")
      local n = risesBetween(C.brk.f, C.lines[2].f)
      H.log(string.format("[dullahan] %d blow(s) counted between the cancel (f%d) and the second line (f%d)", n,
        C.brk.f, C.lines[2].f))
      H.assertEq(n >= 8, true, "dullahan: eight blows were counted afresh between the cancel and the second line")
      -- (the gate itself, the fuse block's `if_battle_var_greater 3, 8`: the count read 8 or more as the second line's
      -- turn began, and under 8 as his turn before it began -- else that turn would have said it; a gate at seven,
      -- the dull_hand mutant, says the line with seven counted)
      local function countAt(f)
        local v = 0
        for _, r in ipairs(count) do if r.f <= f then v = r.v end end
        return v
      end
      local t2 = C.lines[2].turn
      local atLine, before = countAt(W.turns[t2].f), (t2 > 1 and countAt(W.turns[t2 - 1].f) or 0)
      H.log(string.format("[dullahan] the count as his turn %d (the second line's) began: %d; as his turn before it "
        .. "began: %d", t2, atLine, before))
      H.assertEq(atLine >= 8 and before < 8, true, "dullahan: his gate is eight blows (the count read 8 or more as the "
        .. "line's turn began, under 8 as the turn before it began)")
    end,
  }),
  H.logStep("[dullahan] PASS: his count, the announce, Absolute 0, the cancel and the count again"),
})
