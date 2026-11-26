-- @suite savestate=tritoch_entry slow
-- battle_tritoch.lua -- Tritoch under the boss contract (docs/design/bosses-wor.md block 8, wt/v052-tg-wor1): Ice 3 is
-- its telegraph, and a break cancels it.
--
-- Its script (ai_script.asm AIScript::_324): the first turn of its rotation of three says "Frost climbs the cliff!"
-- (battle dialogue $A5), glows and Rasps (the line rides that turn); Ice 3 (attack $0A, command $02) comes on the
-- second (vanilla rolled Ice 3, Ice 3 or Rasp there, and Rasp, Rasp or Ice 3 on the first); the third is vanilla's
-- (Rasp, Cold Dust or Ice 3).  Under the contract (Ot6FuseTbl's row $0144) a break while it is lit cancels it: the
-- script forgets its `wait`, and the rotation starts again from its first turn, the line with it.  Tritoch has no HP
-- phase: its rotation is the same at every HP.  Its counters (Rasp for fire, Cold Dust on a skill's user) are
-- vanilla's; a Fight draws nothing, so the party's Fights here draw no counter.
--
-- Boots tritoch_entry (gen_wor_tritoch: Tritoch's battle, event battle 119, as it comes up).  From a snapshot at the
-- battle's open:
--   landed    (M.fuseLanded, lib/ot6.lua) nothing staged and nothing held: the party Defends; the line comes on its
--             rotation's first turn and Ice 3 on its next, and lands: a member's HP falls.
--   then the three cases from the same snapshot (M.fuseCases, where the cases and the DECLARED staging are written
--   out: the gauge, the row's classes for the breaking Fight, the party's HP held; Tritoch's HP is not held):
--   unbroken  the party Defends; the line shows on the rotation's first turn; the lit-fuse mark stands; Ice 3 is
--             dispatched on its next turn, a glow between; the mark goes; the line reads "Frost climbs the cliff!"
--             where the relocated dialogue table points.
--   broken    an aimed Fight confirmed once the mark is up breaks it: the cancel fires, the mark goes, the script
--             waits nowhere, no Ice 3 on its first turns back, and the line returns on its first turn back (the
--             rotation's first turn again); Ice 3 follows.
--   outside   a break with no fuse lit: nothing is cancelled and the cells stand, and the fuse then lights and fires.
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wor1/mutants*/): fuse_never (Ot6FuseCancel+3=80) is red
-- at "the break during the fuse cancels it"; tritoch_no_row (its row's species $0144 -> $0145: no row) at "the
-- lit-fuse mark stands".  A mechanism test, not play (the landed case writes nothing).
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge and the row's classes, and holds the party's HP, through
-- them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/tritoch_entry.mss.lua"

local TRITOCH, ICE3, LINE = 0x144, 0x0A, 0xA5

local S = {}
-- The cap: the landed case is about 4,000 frames; three cases of about 8,000 each follow; 60,000 is about 2x.
H.run({ maxFrames = 60000 }, {
  H.loadState(STATE),
  H.waitUntil(function() return H.battleActive() end, 3000, "Tritoch's battle is up", 2),
  H.call(function()
    local at = H.aiAttacks(TRITOCH, ICE3)
    H.log(string.format("[tritoch] its turn script names Ice 3 at %d place(s)", #at))
    H.assertEq(#at, 2, "Tritoch's turn script names Ice 3 twice: the fuse's move and its rotation's third turn's pick "
      .. "(vanilla's), and not its first turn, where the line is")
  end),
  H.fuseSnap(S),
  H.fuseLanded({
    tag = "tritoch", species = TRITOCH, line = LINE, move = { cmd = 0x02, atk = ICE3 }, turns = 1,
    landed = function(W, l, m)
      local fell = {}
      for i = 0, 3 do
        if H.readByte(0x3ED8 + 2 * i) ~= 0xFF and m.tchars & (1 << i) ~= 0 then
          local now = H.readWord(0x3BF4 + 2 * i)
          if now < m.hp[i] then fell[#fell + 1] = string.format("seat %d %d -> %d", i, m.hp[i], now) end
        end
      end
      H.log(string.format("[tritoch] landed: Ice 3 on targets $%02X; HP fell: %s", m.tchars, table.concat(fell, ", ")))
      H.assertEq(#fell >= 1, true, "tritoch landed: Ice 3 landed (a target's HP fell within 420 frames)")
    end,
  }),
  H.fuseRestore(S, "tritoch"),
  H.fuseCases({
    tag = "tritoch", species = TRITOCH, write = WRITE,
    line = LINE, move = { cmd = 0x02, atk = ICE3 }, turns = 1, glows = 1,
    lineText = "Frost climbs the cliff!{wait}",
    arm = "idle", aim = true,
    -- no fuse lit (its rotation's first turn announces: any moment with no line lit is before one)
    partway = function(W) return W.cells() ~= nil and not W.litBit() end,
    earned = function(C, W)
      H.assertEq(C.brk.post.blk, 0xFF, "tritoch: the rotation is forgotten after the cancel ($3240 = $FF)")
      local l2 = C.lines[2]
      H.log(string.format("[tritoch] the second line on its turn %d; it recovered after turn %d", l2.turn, C.rec.turn))
      H.assertEq(l2.turn, C.rec.turn + 1, "tritoch: the line returns on its first turn back (the rotation's first "
        .. "turn again)")
    end,
  }),
  H.logStep("[tritoch] PASS: the announce on the rotation's first turn, Ice 3 on its second, the cancel and the "
    .. "rotation again"),
})
