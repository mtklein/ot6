-- @suite savestate=tunnelarmr_entry slow
-- battle_tunnelarmr.lua -- TunnelArmr under the boss contract (#561; docs/design/bosses-wob.md block 5): "Laser
-- charging" -> TekLaser on the party, the telegraph CELES's Runic answers, and the break that cancels it.
--
-- TunnelArmr's script (ai_script.asm AIScript::_260) is vanilla's below its fuse block: its first turn plays the
-- Runic tutorial (battle_event $10), then its rotation of two (Battle/Bolt/Fire, Poison/Special/Fire), whose second
-- turn now sets monster switch 0.  With the switch set its turn is the fuse block, first in the script: "Laser
-- charging" (dlg $92) and a glow; the turn after it clears the switch and fires TekLaser on the whole party
-- (Runic-absorbable).  Under the contract (ot6_fuse.asm, Ot6FuseTbl's row $0104) a break while the fuse is lit
-- cancels it: the switch is cleared and the script waits nowhere, so the rotation starts over from its first turn.
--
-- Boots tunnelarmr_entry (gen_tunnelarmr: LOCKE and CELES one tile short of the (47,38) trigger in the Figaro cave),
-- steps onto the trigger, and plays battle 67 three times from a snapshot at its open (M.fuseCases, lib/ot6.lua,
-- where the cases and the DECLARED staging are written out: the gauge, the row's classes for the breaking Fight,
-- and HP held -- TunnelArmr's at 1,200, above its low-HP line, 384):
--   unbroken  the party Defends; the tutorial plays on its first turn; the line shows on the turn after its
--             rotation's second; the lit-fuse mark stands before the shield emblem; TekLaser is dispatched on its
--             next turn, with one glow between; the mark goes.
--   broken    a Fight confirmed once the mark is up breaks it: the cancel fires, the mark goes with the hit, its
--             first turns back hold no TekLaser, switch 0 reads clear, and the line returns only after the
--             rotation's two turns again; TekLaser follows that.
--   outside   a break after the rotation's first turn, before any line: nothing is cancelled, and the fuse lights
--             and fires as in the first case.
-- A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/tunnelarmr_entry.mss.lua"

local ARMR, TUTORIAL = 0x104, 0x10
local function map() return H.mapId() & 0x1ff end

H.run({ maxFrames = 400000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(60),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control in the Figaro cave"),
  H.fuseEngage(function()
    H.assertEq(map(), 70, "tunnelarmr_entry stands on map 70, the TunnelArmr cave")
    H.assertEq(H.fieldX() == 47 and H.fieldY() == 37, true, "one tile short of the (47,38) trigger")
    local aPh = 0
    return H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.dialogWaiting() then H.setPad(aPh < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        if H.fieldX() == 47 and H.fieldY() == 37 then H.setPad({ down = true }); return end
        H.setPad({})
      end),
    }, "onto (47,38): battle 67")
  end, ARMR, "TunnelArmr"),
  H.fuseCases({
    tag = "tunnelarmr", species = ARMR, write = WRITE,
    line = 0x92, move = { cmd = 0x0C, atk = 0xB5 }, turns = 1, glows = 1,
    arm = "idle", openHold = true,
    bossHp = 1200,
    lineShot = 30,
    -- the rotation's first turn taken (the tutorial's turn before it), no fuse armed yet
    partway = function(W)
      local c = W.cells()
      return c ~= nil and #W.turns >= 2 and (c.mvar & 0x01) == 0 and (c.bsw & 0x01) ~= 0
    end,
    earned = function(C, W)
      local pre, post, l2 = C.brk.pre, C.brk.post, C.lines[2]
      H.assertEq(pre.mvar & 0x01, 1, "tunnelarmr: monster switch 0 stood at the break (the fuse was armed)")
      H.assertEq(post.mvar & 0x01, 0, "tunnelarmr: monster switch 0 is clear after the cancel")
      local back = l2.turn - C.rec.turn
      H.assertEq(back >= 3, true, string.format("tunnelarmr: the trigger was earned again in full: the line "
        .. "returned on its turn %d back, after the rotation's two turns", back))
      -- the tutorial played once, on its first turn, and not again
      local n = 0
      for _, c in ipairs(W.cmds) do if c.cmd == 0x23 and c.arg == TUTORIAL then n = n + 1 end end
      H.assertEq(n, 1, string.format("tunnelarmr: the Runic tutorial (battle_event $%02X, command $23) played once "
        .. "in the case, on its first turn", TUTORIAL))
    end,
  }),
  H.logStep("[tunnelarmr] PASS: the announce, the schedule, the cancel and the trigger earned again"),
})
