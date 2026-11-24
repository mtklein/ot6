-- @suite savestate=whelk_entry slow
-- battle_whelk.lua -- the Whelk under the boss contract (#561; docs/design/bosses-wob.md block 1): the game's first
-- telegraph is the fight's own rhythm, "It draws in!" -> the head draws into its shell, and the break that cancels
-- it keeps the Broken head out.
--
-- The Whelk is two bodies: the shell (AIScript::_256, no gauge) and the head (_308, 4 shields, the gauge).  Where
-- vanilla's shell drew the head in on its clock, it now calls the head in (battle switch 1); the head announces it,
-- "It draws in!" (dlg $8E) and a glow, glows again on its next turn, and on the turn after that draws in itself:
-- vanilla's "Gruuu" (dlg $05) and FADE_DOWN (kill_monsters MONSTER_2, dispatched as command $24 with the animation
-- $08).  Under the contract (ot6_fuse.asm, Ot6FuseTbl's row $0134) a break while the fuse is lit cancels the hide:
-- the call is cleared, and every break of the head sets battle switch 0 (OT6_FUSE_HOLD), which keeps the shell from
-- calling it in again until the head's first turn back.  No new damage: on its other turns the head attacks as
-- vanilla's did, and the shell's Mega Volt counter is vanilla's.
--
-- Boots whelk_entry (gen_whelk_poweron: one tile south of the Whelk's trigger in the mines), steps onto the trigger
-- and pages the guards' lines into the battle, and plays it from a snapshot at its open (M.fuseCases, lib/ot6.lua,
-- where the cases and the DECLARED staging are written out: the gauge, the row's classes for the breaking hit,
-- and HP held).  A Magitek rider has no Fight (InitCmdList turns it into Magitek), so the breaking action, and the
-- two in the "outside" window, are TERRA's or a soldier's Fire Beam aimed at the head:
--   unbroken  the party Defends; the shell calls the head in; the line shows; the lit-fuse mark stands before its
--             shield emblem; the head draws in on its second turn after the line, two glows between; the mark goes.
--   broken    a Fire Beam confirmed once the mark is up breaks the head: the cancel fires, the call is cleared and
--             the hold set, the mark goes with the hit, its first turns back hold no hide, and the line returns only
--             after the head's first turn back has ended the hold and the shell has called it again; the hide
--             follows.
--   outside   a break with no call pending: nothing is cancelled (the hold aside), and the fuse lights and fires as
--             in the first case.
--   after the hide  the head broken as soon as it is back out of its shell: it stays on the field for its whole
--             window, and the shell does not call it in during it (battle switch 1 stays clear).
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v051-tg-wob1/): whelk_no_hold (Ot6FuseTbl+55=00: no
-- OT6_FUSE_HOLD) is red at "the shell's call stays clear held for the whole window"; whelk_no_clear (Ot6FuseTbl+54=FF:
-- the cancel keeps the call) at "battle switch 1 (the shell's call) is clear after the cancel".
-- A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/whelk_entry.mss.lua"

local WHELK, HEAD = 0x100, 0x134
local MAGITEK, FIRE_BEAM = 0x1D, 0          -- the command, and the MagiTek list's entry (attack $83 + entry)

-- The cap: its four cases ran to f23,485 on the Mega Volt build (wt/v051-tg-wob1), so 50,000 is about 2x that.
H.run({ maxFrames = 50000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 300, "control at the Whelk's entry point", 5),
  H.fuseEngage(function()
    H.assertEq(H.mapId(), 41, "whelk_entry stands in the Narshe mines (map 41)")
    H.assertEq(H.readByte(0x1ea6) & 0x20, 0, "the Whelk is not fought yet (switch $0135 clear)")
    -- gen_arvis's approach: onto (42,5), whose event walks the party back and opens the guards' lines; A pages them
    local aPh = 0
    return H.driveUntil(function() return H.battleLoadStarted() end, 8000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.dialogWaiting() then H.setPad(aPh < 4 and { "a" } or {}); return end
        if not H.hasControl() or not H.tileAligned() then H.setPad({}); return end
        H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
      end),
    }, "the Whelk's event opens a battle")
  end, HEAD, "the Whelk"),
  H.call(function()
    H.assertEq(H.formationHas({ [WHELK] = true }), true, "the battle is the Whelk's (shell $100 and head $134)")
  end),
  H.fuseCases({
    tag = "whelk", species = HEAD, write = WRITE,
    line = 0x8E, move = { cmd = 0x24, atk = 0x08 }, turns = 2, glows = 2,
    arm = "idle", hides = true,
    bossHp = 1600,
    breaker = { name = "Fire Beam", cmd = MAGITEK, mtek = FIRE_BEAM, open = true },
    lineShot = 30,
    bswIgnore = 0x01,             -- (the hold every break sets)
    -- no call pending and no hold, the head out and a turn of its taken
    partway = function(W)
      local c = W.cells()
      return c ~= nil and #W.turns >= 1 and (c.bsw & 0x03) == 0
    end,
    earned = function(C, W)
      local pre, post, l2 = C.brk.pre, C.brk.post, C.lines[2]
      H.assertEq(pre.bsw & 0x02, 0x02, "whelk: battle switch 1 (the shell's call) stood at the break")
      H.assertEq(post.bsw & 0x02, 0, "whelk: battle switch 1 (the shell's call) is clear after the cancel")
      H.assertEq(post.bsw & 0x01, 0x01, "whelk: battle switch 0 (the hold) is set by the break")
      local back = l2.turn - C.rec.turn
      H.assertEq(back >= 2, true, string.format("whelk: the call was earned again: the line returned on the head's "
        .. "turn %d back (its first turn back ends the hold, then the shell calls)", back))
    end,
    -- a fourth case: the head broken as soon as it is back out of its shell after the hide
    afterMove = true,
    afterMoveWhen = function(W, C)
      local c = W.cells()
      return c ~= nil and (c.bsw & 0x02) == 0 and #W.turns > C.mv.turn
    end,
    windowBad = function(W) return (H.readByte(0x3EB0) & 0x02) ~= 0 end,
    windowWhat = "the shell's call stays clear (battle switch 1)",
  }),
  H.logStep("[whelk] PASS: the announce, the schedule, the cancel and the trigger earned again"),
})
