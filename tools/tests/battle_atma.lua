-- @suite savestate=atma_entry slow
-- battle_atma.lua -- Atma under the boss contract (#561; docs/design/bosses-wor.md block 25): the charge the
-- party arms, and the break that cancels it.
--
-- Atma's script (ai_script.asm AIScript::_381) is vanilla's, but for one order: its fire turn clears monster
-- switch 0 before Ultima, not after it (ot6_fuse.asm, the idiom).  His counter tallies the hits that land
-- on him in battle variable 3 while monster switch 0 is clear (`if_hit / if_monster_switch_clr 0 / ... /
-- add_battle_var 3, 1 / if_battle_var_greater 3, 12 / set_monster_switch 0 / set_battle_var 3, 0`), and with the
-- switch set his turn is the fuse block: "Unknown light surrounded Atma!" (dlg $83) and a glow, a second glowing
-- turn, then the long glow and Ultima on the third.  Under the contract (ot6_fuse.asm, Ot6FuseTbl's row $017D) a
-- break while that fuse is lit cancels it: the script waits nowhere, the switch and the tally are cleared, and
-- the hits have to be landed again.
--
-- Boots atma_entry (gen_wor_kt_atma: party 2 two tiles below him, map 331), talks to him (event battle 112), and
-- plays the battle three times from a snapshot at its open (M.fuseCases, lib/ot6.lua, where the cases and the
-- DECLARED staging are written out: the gauge, the row's classes for the breaking Fight, and HP held):
--   unbroken  the party Fights until the line shows; the lit-fuse mark stands before his shield emblem; Ultima is
--             dispatched on his second turn after the announce, with three glow commands between; the mark goes.
--   broken    the same to the announce, then a Fight breaks him: the cancel fires, the mark goes with the hit,
--             his first turns back hold no Ultima, the tally and the switch read clear, and the line returns only
--             after the tally has climbed as high as it did the first time; Ultima follows that announce.
--   outside   a break after three counted hits, before any line: nothing is cancelled, the tally stands, two
--             Fights on the Broken Atma add nothing to it, and the fuse then lights and fires as in the first case.
-- The ROM before the cancel (f3f644c7) is red at "the move does not fire when the boss recovers": there Ultima
-- came on his second turn back with no new line (build/attempts/wt/v051-fuse/measure/atma.log).  Mutants
-- (build/attempts/wt/v051-fuse/mutants-review/): fuse_never (no break cancels) is red at "the break during the fuse
-- cancels it", fuse_no_trigger (the cancel forgets the row's clears) at "monster switch 0 is clear after the
-- cancel", fuse_always (a break cancels whether or not a fuse is lit) at "a break outside the fuse cancels
-- nothing".
-- A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/atma_entry.mss.lua"

local ATMA, MAP, AT = 0x17D, 331, { 76, 51 }
local function map() return H.mapId() & 0x1ff end

H.run({ maxFrames = 400000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control below Atma"),
  H.fuseEngage(function()
    H.assertEq(map(), MAP, "atma_entry stands on map 331")
    local o = nil
    for ob = 0x10, 0x3F do
      if H.objX(ob) == AT[1] and H.objY(ob) == AT[2] then o = ob; break end
    end
    H.assertEq(o ~= nil, true, "Atma's object stands on 331 (76,51)")
    return H.talkToObj(o, "Atma", nil, function() return H.battleLoadStarted() end)
  end, ATMA, "Atma"),
  H.fuseCases({
    tag = "atma", species = ATMA, write = WRITE,
    line = 0x83, move = { cmd = 0x02, atk = 0x14 }, turns = 2, glows = 3,
    arm = "fight",
    -- held above his low rotation's line (32,640), so the arming Fights and the break's doubled ones change no turn
    bossHp = 50000,
    -- three hits counted, no line yet
    partway = function(W) return W.cells().bvar3 >= 3 end,
    earned = function(C, W)
      local post, l1, l2 = C.brk.post, C.lines[1], C.lines[2]
      H.assertEq(post.mvar & 0x01, 0, "atma: monster switch 0 is clear after the cancel (the counter tallies again)")
      H.assertEq(post.bvar3, 0, "atma: the tally (battle variable 3) reads 0 after the cancel")
      H.assertEq(l1.max.bvar3 >= 2, true, string.format("atma: the first arming's tally was read climbing (to %d)",
        l1.max.bvar3))
      H.assertEq(l2.max.bvar3, l1.max.bvar3, string.format("atma: the trigger was earned again in full: the tally "
        .. "climbed from 0 to %d before the second line, as before the first (%d)", l2.max.bvar3, l1.max.bvar3))
    end,
  }),
  H.logStep("[atma] PASS: the announce, the schedule, the cancel and the trigger earned again"),
})
