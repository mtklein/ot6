-- @suite savestate=flameeater_entry slow
-- battle_flameeater.lua -- FlameEater under the boss contract (docs/design/bosses-wob.md block 18, wt/v052-tg-wob3):
-- Fire Ball is its telegraph, and a break cancels it.
--
-- Its script (ai_script.asm AIScript::_278): the last turn of its rotation of three ARMS the fuse (monster switch 2;
-- 0 and 1 are its opening and its Bomblet calls); "It swells with flame!" (battle dialogue $9D) and a glow announce it
-- on its next turn, and Fire Ball (attack $B3, command $0C) on the whole party comes on the turn after.  Under the
-- contract (Ot6FuseTbl's row $0116) a break while it is lit cancels it: switch 2 goes, and the rotation's three turns
-- earn it again.  Fire Ball comes only announced: its rotation casts Fire where vanilla could pick it, so the script
-- names Fire Ball once, in the fuse block (asserted from the ROM).  (The first cut armed it from its counter when
-- fire struck it; an absorbed spell starts no counter and the fuse never armed:
-- build/attempts/wt/v052-tg-wob3/regen2/suites/battle_flameeater-red.log.)
--
-- Boots flameeater_entry (gen_thamasa_fire: the sweep's entry checkpoint in FlameEater's chamber, the party
-- STRAGO, TERRA and LOCKE), walks onto the (46,53) trigger (battle 79) and plays the battle from a snapshot at its
-- open (M.fuseCases, lib/ot6.lua, where the cases and the DECLARED staging are written out: the gauge, the row's
-- classes for the breaking Fight, HP held -- its at 6,000):
--   unbroken  the party Defends; the line shows on the turn after its rotation's last; the lit-fuse mark stands
--             before its shield emblem; Fire Ball is dispatched on the turn after, a glow between, on every
--             standing member; the mark goes; the line reads "It swells with flame!" where the relocated dialogue
--             table points.
--   broken    one member's aimed Fight confirmed once the mark is up breaks it: the cancel fires, the mark goes,
--             switch 2 reads clear, no Fire Ball on its first turns back, and the line returns only after three or
--             more of its turns (its rotation again); Fire Ball follows.
--   outside   a break after its first turn, before any line: nothing is cancelled and the cells stand, two aimed
--             Fights in the window wind nothing, and the fuse then lights and fires as in the first case.
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wob3/mutants/): fuse_never (Ot6FuseCancel+3=80) is red
-- at "the break during the fuse cancels it"; fe_row_keeps (its row keeps switch 2: +5 = $FF) at "monster switch 2 is
-- clear after the cancel"; fe_ball_back (its rotation's second turn picks Fire Ball again) at "Fire Ball comes only
-- announced".  A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/flameeater_entry.mss.lua"

local FLAMEEATER, TERRA, FIRE_BALL = 0x116, 0x00, 0xB3
local function map() return H.mapId() & 0x3ff end

-- The cap: three cases of about 10,000 frames each, so 60,000 is about 2x.
H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(90),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control in FlameEater's chamber"),
  H.call(function()
    -- Fire Ball comes only announced: the script names it once, in the fuse block (the script's first)
    local at = H.aiAttacks(FLAMEEATER, FIRE_BALL)
    H.log(string.format("[flameeater] its turn script names Fire Ball at %d place(s): %s", #at,
      table.concat((function() local t = {}; for _, x in ipairs(at) do t[#t + 1] = string.format("+$%04X", x) end
        return t end)(), " ")))
    H.assertEq(#at, 1, "Fire Ball comes only announced: its turn script names it once (the fuse block)")
  end),
  H.fuseEngage(function()
    local ph = 0
    return H.seqStep({
      H.navTo(46, 52, { playBattles = "tactical", maxFrames = 20000 }),
      H.driveUntil(function() return H.battleLoadStarted() end, 8000, {
        H.call(function()
          ph = (ph + 1) % 8
          if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
          H.setPad({ down = true })
        end),
      }, "walk onto (46,53): battle 79"),
    })
  end, FLAMEEATER, "FlameEater"),
  H.call(function()
    H.setPad({})
    local inParty = false
    for i = 0, 3 do if H.readByte(0x3ED8 + 2 * i) == TERRA then inParty = true end end
    H.assertEq(inParty, true, "TERRA is seated in battle 79 (the trigger re-forces STRAGO, TERRA, LOCKE)")
  end),
  H.fuseCases({
    tag = "flameeater", species = FLAMEEATER, write = WRITE,
    line = 0x9D, move = { cmd = 0x0C, atk = FIRE_BALL }, turns = 1, glows = 1,
    lineText = "It swells with flame!{wait}",
    arm = "idle", aim = true, allTargets = true,
    bossHp = 6000,
    -- its first turn taken (the Balloons called), switch 2 clear
    partway = function(W)
      local c = W.cells()
      return c ~= nil and #W.turns >= 1 and (c.mvar & 0x04) == 0
    end,
    earned = function(C, W)
      local pre, post, l2 = C.brk.pre, C.brk.post, C.lines[2]
      H.assertEq(pre.mvar & 0x04, 0x04, "flameeater: monster switch 2 stood at the break (armed)")
      H.assertEq(post.mvar & 0x04, 0, "flameeater: monster switch 2 is clear after the cancel")
      local back = l2.turn - C.rec.turn
      H.log(string.format("[flameeater] the second line on its turn %d back", back))
      H.assertEq(back >= 4, true, string.format("flameeater: the second line came only after its rotation's three "
        .. "turns again (on its turn %d back)", back))
    end,
  }),
  H.logStep("[flameeater] PASS: the rotation, the announce, the Fire Ball, the cancel and the rotation again"),
})
