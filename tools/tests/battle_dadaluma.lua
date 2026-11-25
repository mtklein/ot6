-- @suite savestate=dadaluma_entry slow
-- battle_dadaluma.lua -- Dadaluma under the boss contract (docs/design/bosses-wob.md block 11, wt/v052-tg-wob2): his
-- leap is his telegraph, and a break cancels it.
--
-- Dadaluma's script (ai_script.asm AIScript::_263): vanilla leapt once the party had used Magic on him three times
-- (battle variable 2, counted by his counter's `if_cmd MAGIC`) and he was not Slowed -- a fan of knives at the whole
-- party, then Jump on his next turn.  Now the knife fan ARMS the fuse (monster switch 0); "He crouches!" (battle
-- dialogue $93) and a glow announce it on his next turn, and Jump (command $16) comes on the turn after.  Under the
-- contract (ot6_fuse.asm, Ot6FuseTbl's row $0107, OT6_FUSE_VAR2) a break while it is lit cancels it: the script waits
-- nowhere, switch 0 and the tally are clear, and three more spells earn it again.
--
-- Boots dadaluma_entry (gen_zozo4_dadaluma: the party on (30,13), facing him, one A press from battle 69), opens
-- the battle and plays it from a snapshot at its open (M.fuseCases, lib/ot6.lua, where the cases and the DECLARED
-- staging are written out: the gauge, the row's classes for the breaking Fight, HP held -- his at 3,000, above his
-- potion line, 1,920).  The party earns the trigger the way a player does: CELES casts a spell she knows at him
-- (Magic, aimed at his slot) and the others Defend.
--   unbroken  the third spell's counter makes the knife fan arm it; the line shows on his next turn; the lit-fuse
--             mark stands before his shield emblem; Jump is dispatched on his next turn, a glow between; the mark goes.
--   broken    one member's aimed Fight confirmed once the mark is up breaks him: the cancel fires, the mark goes
--             with the hit, switch 0 and battle variable 2 read clear, no Jump on his first turns back, and the line
--             returns only after three more of CELES's spells; Jump follows.
--   outside   a break after one spell, before any line: nothing is cancelled and the cells stand, two aimed Fights
--             in the window wind nothing, and the fuse then lights and fires as in the first case.
-- Mutants (tools/build/mutant_rom.py, on the branch's ROM; build/attempts/wt/v052-tg-wob2/mutants/): fuse_never
-- (Ot6FuseCancel+3=80) is red at "the break during the fuse cancels it"; dada_no_tally (his row keeps the tally:
-- its flags byte 0) at "three of CELES's spells came between the cancel and the second line".  A mechanism test,
-- not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/dadaluma_entry.mss.lua"

local DADA, CELES = 0x107, 0x06
local function map() return H.mapId() & 0x1ff end

-- CELES's attack spell: the first of Ice, Fire, Bolt, Poison she has learned ($1A6E + 54 * 6: $FF learned)
local SPELL = nil
local function pickSpell()
  for _, sp in ipairs({ 0x01, 0x00, 0x02, 0x03 }) do
    if H.readByte(0x1A6E + 54 * CELES + sp) == 0xFF then return sp end
  end
  return nil
end

-- every Magic command the party dispatches in the battle: { f, actor } (the counter that tallies it is his)
local casts, castsOn, tally = {}, false, {}
local function castsBetween(f0, f1)
  local n = 0
  for _, c in ipairs(casts) do if c.f > f0 and c.f < f1 then n = n + 1 end end
  return n
end

-- the party's play while the fuse arms: CELES casts at him, one spell a turn of hers, the others Defend
local function armByMagic(pred, max, W)
  local t0 = nil
  return H.lazy(function()
    t0 = H.frame
    local plan = {}
    for k = 1, 8 do plan[k] = { who = CELES, cmd = 0x02, spell = SPELL, boost = 0, slot = W.slot() } end
    return H.kitBattle(plan, { idle = "defend", care = false, maxFrames = max + 600,
      giveUp = function() return pred() or H.frame - t0 >= max end })
  end)
end

-- The cap: three cases of about 9,000 frames each, so 60,000 is about 2x.
H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control before Dadaluma"),
  H.call(function()
    H.assertEq(map(), 221, "dadaluma_entry stands on map 221, the Zozo tower roof")
    H.assertEq(H.fieldX() == 30 and H.fieldY() == 13, true, "on (30,13), facing him")
    SPELL = pickSpell()
    H.assertEq(SPELL ~= nil, true, "CELES knows an attack spell (Ice, Fire, Bolt or Poison): her natural magic "
      .. "(gen_zozo4_dadaluma's party carries her)")
    H.log(string.format("[dadaluma] CELES casts spell $%02X to earn the leap", SPELL))
    local d = H.sym("_dispatcher")
    emu.addMemoryCallback(function()
      if not castsOn then return end
      local x = emu.getState()["cpu.x"] & 0xFF
      if x < 8 and H.readByte(0xB5) == 0x02 then casts[#casts + 1] = { f = H.frame, actor = x // 2 } end
    end, emu.callbackType.exec, d, d)
    -- battle variable 2, his tally, frame by frame (the cancel's clear is read two frames after the break)
    emu.addEventCallback(function()
      if castsOn then tally[H.frame] = H.readByte(0x3EB2); tally[H.frame - 60000] = nil end
    end, emu.eventType.endFrame)
  end),
  H.fuseEngage(function()
    local aPh = 0
    -- (facing him: DOWN held, then A, as gen_zozo4_dadaluma talks to him)
    return H.seqStep({
      H.hold({ "down" }), H.waitFrames(8), H.release(), H.waitFrames(4),
      H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
        H.call(function()
          aPh = (aPh + 1) % 8
          H.setPad(aPh < 4 and { "a" } or {})
        end),
      }, "the talk opens battle 69"),
    })
  end, DADA, "Dadaluma"),
  H.call(function()
    H.setPad({})
    local inParty = false
    for i = 0, 3 do if H.readByte(0x3ED8 + 2 * i) == CELES then inParty = true end end
    H.assertEq(inParty, true, "CELES is seated in battle 69 (gen_zozo4_dadaluma's party)")
    castsOn = true
  end),
  H.fuseCases({
    tag = "dadaluma", species = DADA, write = WRITE,
    line = 0x93, move = { cmd = 0x16 }, turns = 1, glows = 1,
    arm = armByMagic, aim = true,
    bossHp = 3000,
    onOpen = function() casts = {} end,
    -- one spell's tally counted, no fuse armed
    partway = function(W)
      local c = W.cells()
      return c ~= nil and H.readByte(0x3EB2) >= 1 and (c.mvar & 0x01) == 0
    end,
    earned = function(C, W)
      local post = C.brk.post
      H.assertEq(post.mvar & 0x01, 0, "dadaluma: monster switch 0 is clear after the cancel")
      local t = tally[C.brk.f + 2]
      H.log(string.format("[dadaluma] the tally (battle variable 2) %s before the break, %s two frames after",
        tostring(tally[C.brk.f - 1]), tostring(t)))
      H.assertEq(t, 0, "dadaluma: battle variable 2, his tally of spells, is clear after the cancel")
      local n = castsBetween(C.brk.f, C.lines[2].f)
      H.log(string.format("[dadaluma] %d of CELES's spells between the cancel (f%d) and the second line (f%d)", n,
        C.brk.f, C.lines[2].f))
      H.assertEq(n >= 3, true, "dadaluma: three of CELES's spells came between the cancel and the second line (the "
        .. "tally starts over)")
    end,
    outside = function(C, W)
      local n = castsBetween(0, C.lines[1].f)
      H.assertEq(n >= 3, true, string.format("dadaluma: the line came after three spells in the case (%d)", n))
    end,
  }),
  H.logStep("[dadaluma] PASS: the spells, the announce, the leap, the cancel and the tally earned again"),
})
