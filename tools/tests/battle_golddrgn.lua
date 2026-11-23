-- @suite savestate=golddrgn_entry slow
-- battle_golddrgn.lua -- the Gold Dragon under the boss contract (#561; docs/design/bosses-wor.md block 26): Fights
-- wind it, and the break cancels what they wound.
--
-- The Gold Dragon's script (ai_script.asm AIScript::_336) is vanilla's, unchanged.  Its counter counts the Fights
-- that land on it in its monster variable while battle switch 0 is clear (`if_cmd FIGHT / if_battle_switch_clr 0,
-- 0 / add_monster_var 1 / if_battle_var_greater 36, 4 / set_battle_switch 0, 0 / dlg $73`), and the fourth sets
-- the switch and says "Gold Dragon begins to store energy!".  With the switch set, two of its turns only count
-- (battle variable 3) and the third is Bolt 3 on the whole party, which clears the switch, the count and the
-- variable.  Under the contract (ot6_fuse.asm, Ot6FuseTbl's switch row $0150) a break while the switch is set
-- cancels the charge: the switch, the count and the monster variable are cleared, so four more Fights are needed.
-- And the announce is no story (Ot6FuseLineTbl), so the arming block is skipped while the dragon is Broken like
-- any counter that only counts: Fights on a Broken dragon wind nothing.
--
-- Boots golddrgn_entry (gen_wor_kt_guardian: party 2 two tiles below it, map 335), talks to it (event battle 135),
-- and plays the battle three times from a snapshot at its open (M.fuseCases, lib/ot6.lua, where the cases and the
-- DECLARED staging are written out: the gauge, the row's classes for the breaking Fight, and HP held):
--   unbroken  the party Fights until the line shows (its counter's); the lit-fuse mark stands before the shield
--             emblem; Bolt 3 is dispatched on its third turn after; the mark goes.
--   broken    the same to the announce, then a Fight breaks it: the cancel fires, the mark goes with the hit, its
--             first turns back hold no Bolt 3, the switch, the count and the monster variable read clear, and the
--             line returns only after the variable has climbed as high as it did the first time; Bolt 3 follows.
--   outside   a break after two counted Fights, before any line: nothing is cancelled, the variable stands, two
--             Fights on the Broken dragon add nothing to it, and the charge then lights and fires as in the first
--             case.
-- The ROM before the cancel (f3f644c7) is red at "the move does not fire when the boss recovers" and at "Fights
-- on the Broken boss wound nothing" (build/attempts/wt/v051-fuse/measure/golddrgn.log).  A mechanism test, not
-- play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/golddrgn_entry.mss.lua"

local GOLD, MAP, AT = 0x150, 335, { 82, 33 }
local function map() return H.mapId() & 0x1ff end

H.run({ maxFrames = 400000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control below the Gold Dragon"),
  H.fuseEngage(function()
    H.assertEq(map(), MAP, "golddrgn_entry stands on map 335")
    local o = nil
    for ob = 0x10, 0x3F do
      if H.objX(ob) == AT[1] and H.objY(ob) == AT[2] then o = ob; break end
    end
    H.assertEq(o ~= nil, true, "the Gold Dragon's object stands on 335 (82,33)")
    return H.talkToObj(o, "the Gold Dragon", nil, function() return H.battleLoadStarted() end)
  end, GOLD, "the Gold Dragon"),
  H.fuseCases({
    tag = "golddrgn", species = GOLD, write = WRITE,
    line = 0x73, move = { cmd = 0x02, atk = 0x0B }, turns = 3, glows = 0,
    arm = "fight",
    bossHp = 30000,
    -- two Fights counted, no line yet
    partway = function(W) return (W.cells().mvar & 0x7F) >= 2 end,
    earned = function(C, W)
      local post, l1, l2 = C.brk.post, C.lines[1], C.lines[2]
      H.assertEq(post.bsw & 0x01, 0, "golddrgn: battle switch 0 is clear after the cancel")
      H.assertEq(post.mvar, 0, "golddrgn: the Fights' count (the monster variable) reads 0 after the cancel")
      H.assertEq(post.bvar3, 0, "golddrgn: the turns' count (battle variable 3) reads 0 after the cancel")
      H.assertEq(l1.max.mvar >= 2, true, string.format("golddrgn: the first arming's count was read climbing (to "
        .. "%d)", l1.max.mvar))
      H.assertEq(l2.max.mvar, l1.max.mvar, string.format("golddrgn: the trigger was earned again in full: the "
        .. "count climbed from 0 to %d before the second line, as before the first (%d)", l2.max.mvar, l1.max.mvar))
    end,
  }),
  H.logStep("[golddrgn] PASS: the announce, the schedule, the cancel and the trigger earned again"),
})
