-- @suite savestate=nerapa_entry slow
-- battle_nerapa.lua -- Nerapa under the boss contract (docs/design/bosses-wob.md block 22, wt/v052-tg-wob3): Roulette
-- is its telegraph, and a break cancels it.
--
-- Its script (ai_script.asm AIScript::_280): vanilla counted the party's Fights at it (its counter: a Battle back,
-- and the tally) and spun Roulette on its first turn with six counted.  Now that turn says "The wheel turns!" (battle
-- dialogue $9F) and glows, and Roulette (attack $8C, command $1E, as ExecCmd dispatches it) comes on its next turn.  The tally is the fuse
-- block's own condition, in battle variable 3 now (vanilla's was 0).  Under the contract (Ot6FuseTbl's row $0118,
-- OT6_FUSE_VAR3) a break while it is lit cancels Roulette and clears the tally: six more Fights earn it again.
-- Fights on a Broken Nerapa count nothing.  Its Fight counter is no dying counter; it is vanilla's but for the
-- tally's cell.
--
-- Boots nerapa_entry (gen_fc_escape: the doorstep under the escape clock, the party TERRA, LOCKE, EDGAR and CELES),
-- talks to it (battle 81) and plays the battle from a snapshot at its open (M.fuseCases, lib/ot6.lua, where the
-- cases and the DECLARED staging are written out: the gauge -- to 63 while the party's Fights earn the spin, to 1
-- with every class for the breaking Fight -- HP held, its at 30,000 (no one boosted Fight takes that), and, below, the party's Condemned clocks and the escape's clocks held and Nerapa kept from instant death):
--   unbroken  the party Fights it; six Fights counted, the line shows on its next turn; the lit-fuse mark stands;
--             Roulette is dispatched on its turn after, a glow between; the mark goes; the line reads "The wheel
--             turns!" where the relocated dialogue table points.
--   broken    the party Fights until the line, then one member's Fight confirmed once the mark is up breaks it:
--             the cancel fires, the mark goes, battle variable 3 reads 0, no Roulette on its first turns back, and
--             the line returns only after six more Fights; Roulette follows.
--   outside   a break with one to five Fights counted: nothing is cancelled and the cells (the tally among them)
--             stand, two Fights in the window count nothing, and the fuse then lights and fires.
-- The escape clock runs through every case: each opens on the battle's snapshot, the clock as the doorstep left it.
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wob3/mutants/): fuse_never (Ot6FuseCancel+3=80) is red
-- at "the break during the fuse cancels it"; nerapa_no_var3 (its row's flags byte 0) at "battle variable 3, its
-- tally, is 0 after the cancel".  A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/nerapa_entry.mss.lua"

local NERAPA = 0x118
local function nerapaUp() return (H.readByte(0x1EEC) >> 1) & 1 == 1 end    -- $0361: Nerapa stands

-- The cap: its run ended at f32,883 (build/attempts/wt/v052-tg-wob3/regen2/suites/battle_nerapa-dev9.log), so 70,000 is
-- about 2x.
H.run({ maxFrames = 70000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 3000, "field control on Nerapa's doorstep"),
  H.call(function()
    H.assertEq(nerapaUp(), true, "$0361 set -- Nerapa stands at the doorstep")
    H.log(string.format("[nerapa] the doorstep at (%d,%d), the master clock %d", H.fieldX(), H.fieldY(),
      H.readWord(0x1189)))
  end),
  H.fuseEngage(function()
    -- gen_fc_escape's talk: face right, release, tap A while standing still
    local t = 0
    return H.driveUntil(function()
      t = t + 1
      return H.battleActive() or H.battleLoadStarted()
    end, 4000, {
      H.call(function()
        local c = t % 48
        if c < 4 then H.setPad({ right = true })
        elseif c >= 24 and c < 28 then H.setPad({ a = true })
        else H.setPad({}) end
      end),
    }, "Nerapa engaged")
  end, NERAPA, "Nerapa"),
  H.call(function()
    H.setPad({})
    -- DECLARED: the Condemned clocks held.  Its opening Condemns every member (its first turn, once), and Doom came
    -- before a case could end: the first cut's broken case wiped at f15988, 9,500 frames after the battle's open
    -- (build/attempts/wt/v052-tg-wob3/regen2/suites/battle_nerapa-dev2.log).  A member's count ($3B05,x, StartCondemn)
    -- under 10 goes back to 30, so no Doom ends a case; Roulette's own death stands (each case opens on the snapshot).
    emu.addEventCallback(function()
      if not H.battleActive() then return end
      for i = 0, 3 do
        local n = H.readByte(0x3B05 + 2 * i)
        if n > 0 and n < 10 then WRITE.byte(0x3B05 + 2 * i, 30) end
      end
      -- DECLARED: the escape's clocks (the event timers' counters, $1189 + 6k: the master clock and Shadow's) held
      -- at 6,000 frames or more: the second cut's broken case ran one out ("the boss still stands and the battle is
      -- up (broken): got false" at f17943, 11,474 frames after the battle's open; battle_nerapa-dev3.log), and
      -- holding the master clock alone did not help (dev4)
      -- DECLARED: Nerapa protected from instant death ($3AA1,x bit 2, as FixImmuneStatus sets it for a body immune
      -- to Wound).  LOCKE's Assassin kills at random on a hit, and on this branch's cuts a Fight of the broken
      -- case's arming killed it at f17326 every time (its HP held at 30,000 read 0 a frame later, its status $80:
      -- build/lab/tg-wob3/nerapa_probe.log, retained under build/attempts/wt/v052-tg-wob3/regen2/suites/), and the
      -- battle ended
      for sl = 0, 5 do
        if H.readWord(0x57C0 + sl * 2) == NERAPA and H.readByte(0x3AA8 + sl * 2) & 1 == 1 then
          local x = 0x3AA1 + 8 + 2 * sl
          if H.readByte(x) & 0x04 == 0 then WRITE.byte(x, H.readByte(x) | 0x04) end
        end
      end
      for k = 0, 3 do
        local c = H.readWord(0x1189 + 6 * k)
        if c > 0 and c < 6000 then WRITE.word(0x1189 + 6 * k, 12000) end
      end
    end, emu.eventType.endFrame)
  end),
  H.fuseCases({
    tag = "nerapa", species = NERAPA, write = WRITE,
    line = 0x9F, move = { cmd = 0x1E, atk = 0x8C }, turns = 1, glows = 1,
    lineText = "The wheel turns!{wait}",
    arm = "fight", openHold = true,
    bossHp = 30000,  -- (far above its 2,800: the arming Fights are boosted, and a dumped Fight on a body held at 2,000
                     --   and then 9,000 took it whole in one action, the battle ending at f17943 on the cuts dev4-dev7,
                     --   battle_nerapa-dev7.log: Nerapa on screen at f17408, gone at f17792)
    -- one to five Fights counted, no line
    partway = function(W)
      local v = H.readByte(0x3EB3)
      return W.cells() ~= nil and v >= 1 and v <= 5
    end,
    earned = function(C, W)
      local pre, post, l2 = C.brk.pre, C.brk.post, C.lines[2]
      H.assertEq(pre.bvar3 >= 6, true, string.format("nerapa: six Fights were counted at the break (%d)", pre.bvar3))
      H.assertEq(post.bvar3, 0, "nerapa: battle variable 3, its tally, is 0 after the cancel")
      local n = 0
      for _, p in ipairs(W.party) do if p.f > C.rec.f and p.f < l2.f then n = n + 1 end end
      H.log(string.format("[nerapa] %d Fight(s) between its recovery (f%d) and the second line (f%d); the tally at "
        .. "the line %d", n, C.rec.f, l2.f, l2.max and l2.max.bvar3 or -1))
      H.assertEq(n >= 6, true, "nerapa: six more Fights came between the cancel and the second line")
    end,
  }),
  H.logStep("[nerapa] PASS: the Fights counted, the announce, Roulette, the cancel and the tally again"),
})
