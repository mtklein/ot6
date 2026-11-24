-- @suite savestate=whelk_entry slow
-- battle_whelk.lua -- the Whelk under the boss contract (#561; docs/design/bosses-wob.md block 1): the game's first
-- telegraph, "Static builds!" -> Mega Volt, and the break that cancels it.
--
-- The Whelk is two bodies: the shell (AIScript::_256, no gauge) and the head (_308, 4 shields, the gauge), which
-- the shell hides and shows on its own clock.  The telegraph rides on the head, the body a break lands on.  Its
-- first turn arms the fuse (monster switches 6, "it has charged", and 7, the fuse), the next says "Static builds!"
-- (dlg $8E) and glows, and the one after it is Mega Volt on the party; after that its turns count in its monster
-- variable and the second arms it again.  From its first turn to its Mega Volt it holds battle switch 0, which
-- keeps the shell from hiding it.  Under the contract (ot6_fuse.asm, Ot6FuseTbl's row $0134) a break while the
-- fuse is lit cancels it: switch 7 and the count are cleared as the move's own turn clears them (switch 6 and the
-- shell's hold stand), so the head takes a plain turn and its arming turn again before the next announce, and the
-- Broken head stays out of its shell for the break's window.
--
-- Boots whelk_entry (gen_whelk_poweron: one tile south of the Whelk's trigger in the mines), steps onto the trigger
-- and pages the guards' lines into the battle, and plays it three times from a snapshot at its open (M.fuseCases,
-- lib/ot6.lua, where the cases and the DECLARED staging are written out: the gauge, the row's classes for the
-- breaking hit, and HP held).  A Magitek rider has no Fight (InitCmdList turns it into Magitek), so the breaking
-- action, and the two in the "outside" window, are TERRA's or a soldier's Fire Beam aimed at the head:
--   unbroken  the party Defends; the line shows on the head's second turn; the lit-fuse mark stands before its
--             shield emblem; Mega Volt is dispatched on its next turn, with one glow between; the mark goes.
--   broken    a Fire Beam confirmed once the mark is up breaks the head: the cancel fires, the mark goes with the
--             hit, its first turns back hold no Mega Volt, its byte reads $40 (switch 6 alone), the shell's hold
--             stands, and the line returns on its third turn back (a plain turn, the arming, the line); Mega Volt
--             follows that.
--   outside   a break after its first Mega Volt and a plain turn, before the next line: nothing is cancelled, and
--             the fuse lights and fires as in the first case.
-- And the shell stays vanilla but for the one guard: while battle switch 0 is set the shell does not hide the
-- head (the shell's hide block, if_battle_switch_clr 0, 0).
-- A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/whelk_entry.mss.lua"

local WHELK, HEAD = 0x100, 0x134
local MAGITEK, FIRE_BEAM = 0x1D, 0          -- the command, and the MagiTek list's entry (attack $83 + entry)

H.run({ maxFrames = 400000 }, {
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
    line = 0x8E, move = { cmd = 0x0C, atk = 0xB8 }, turns = 1, glows = 1,
    arm = "idle", hides = true,
    breaker = { name = "Fire Beam", cmd = MAGITEK, mtek = FIRE_BEAM, open = true },
    lineShot = 30,
    -- a Mega Volt fired and a plain turn counted since (switch 6 set, 7 clear, the count 1, the shell's hold set):
    -- no fuse lit, and the shell holds the Broken head out through the window
    partway = function(W)
      local c = W.cells()
      return c ~= nil and (c.mvar & 0xC0) == 0x40 and (c.mvar & 0x3F) >= 1 and (c.bsw & 0x01) ~= 0
    end,
    earned = function(C, W)
      local pre, post, l1, l2 = C.brk.pre, C.brk.post, C.lines[1], C.lines[2]
      H.assertEq(l1.turn, 2, "whelk: the first announce came on the head's second turn (its first armed the fuse)")
      H.assertEq(pre.mvar & 0xC0, 0xC0, "whelk: monster switches 6 and 7 stood at the break (the fuse was armed)")
      H.assertEq(post.mvar, 0x40, "whelk: the head's byte reads $40 after the cancel: switch 7 and the count clear, "
        .. "switch 6 kept, as its move's own turn leaves them")
      H.assertEq(post.bsw & 0x01, 1, "whelk: battle switch 0 (the shell's hold on the head) still stands after the "
        .. "cancel: the Broken head stays out of its shell until its next Mega Volt")
      local back = l2.turn - C.rec.turn
      H.assertEq(back, 3, string.format("whelk: the trigger was earned again in full: the line returned on the "
        .. "head's turn %d back (a plain turn, the arming turn, then the line)", back))
    end,
  }),
  H.logStep("[whelk] PASS: the announce, the schedule, the cancel and the trigger earned again"),
})
