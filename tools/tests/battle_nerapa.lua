-- @suite savestate=nerapa_entry slow
-- battle_nerapa.lua -- Nerapa under the boss contract (docs/design/bosses-wob.md block 22, wt/v052-tg-wob3): Roulette
-- is its telegraph, and a break cancels it.
--
-- Its script (ai_script.asm AIScript::_280): vanilla counted the party's Fights at it (its counter: a Battle back,
-- and the tally) and spun Roulette on its first turn with six counted.  Now that turn says "The wheel turns!" (battle
-- dialogue $9F) and glows, and Roulette (attack $8C, command $0C) comes on its next turn.  The tally is the fuse
-- block's own condition, in battle variable 3 now (vanilla's was 0).  Under the contract (Ot6FuseTbl's row $0118,
-- OT6_FUSE_VAR3) a break while it is lit cancels Roulette and clears the tally: six more Fights earn it again.
-- Fights on a Broken Nerapa count nothing.  Its Fight counter is no dying counter; it is vanilla's but for the
-- tally's cell.
--
-- Boots nerapa_entry (gen_fc_escape: the doorstep under the escape clock, the party TERRA, LOCKE, EDGAR and CELES),
-- talks to it (battle 81) and plays the battle from a snapshot at its open (M.fuseCases, lib/ot6.lua, where the
-- cases and the DECLARED staging are written out: the gauge -- to 63 while the party's Fights earn the spin, to 1
-- with every class for the breaking Fight -- and HP held, its at 2,000):
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

-- The cap: three cases of about 6,000 frames each, so 40,000 is about 2x.
H.run({ maxFrames = 40000 }, {
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
  H.call(function() H.setPad({}) end),
  H.fuseCases({
    tag = "nerapa", species = NERAPA, write = WRITE,
    line = 0x9F, move = { cmd = 0x0C, atk = 0x8C }, turns = 1, glows = 1,
    lineText = "The wheel turns!{wait}",
    arm = "fight", openHold = true,
    bossHp = 2000,
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
