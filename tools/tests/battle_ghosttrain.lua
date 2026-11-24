-- @suite savestate=train_b68_entry slow
-- battle_ghosttrain.lua -- the GhostTrain under the boss contract (docs/design/bosses-wob.md block 8,
-- wt/v051-tg-wob2): Evil Toot is its telegraph, and a break cancels it.
--
-- The GhostTrain's script (ai_script.asm AIScript::_262): vanilla tooted on the turn its count of ordinary turns
-- (battle variable 3) reached 2 with two of the party standing.  Now those conditions (the count read one turn
-- earlier) ARM the fuse, monster switch 0, on a turn it spends on its ordinary attacks; the next turn announces it
-- -- "Whistle blows!" (battle dialogue $99) and a glow -- a second glowing turn follows, and Evil Toot (attack $D3,
-- command $0C) comes on the turn after that: two of its turns of fuse (the lab: a full gauge broke in two).  Under the contract (ot6_fuse.asm, Ot6FuseTbl's row $0106) a break while it is lit cancels it: the
-- script waits nowhere, switch 0 and the count are cleared, so an ordinary turn has to come round again before it
-- arms.  Its opening turn (Battle, Special or Evil Toot, once), Acid Rain's clock and the Suplex that ends it
-- (battle_suplextrain, the same fixture) are vanilla's and OT6's, unchanged.
--
-- Boots train_b68_entry (gen_sabin_train: SABIN, CYAN and SHADOW in the corridor before the smokestack), walks to the
-- switch at (32,7) and pulls it (battle 68, formation 437: the train alone), and plays the battle three times from
-- a snapshot at its open (M.fuseCases, lib/ot6.lua, where the cases and the DECLARED staging are written out: the
-- gauge, the row's classes for the breaking Fight, and HP held):
--   unbroken  the party Fights (the gauge staged out of their reach while it arms: SHADOW's Interceptor chips on
--             the train's turns whatever the party does); the line shows on its fourth turn or so; the lit-fuse
--             mark stands before its shield emblem; Evil Toot is dispatched on its second turn after, a glow on
--             each; the mark goes.
--   broken    one member's aimed Fight is confirmed once the mark is up and breaks it: the cancel fires, the mark
--             goes with the hit, switch 0 and the count read clear, no Evil Toot on its first turns back, and the
--             line returns only after an ordinary turn has counted again; Evil Toot follows.
--   outside   a break after its opening turn, nothing counted and nothing lit: nothing is cancelled and the
--             script's cells stand, two Fights in the window wind nothing, and the toot then lights and fires as in
--             the first case.
-- Mutants (tools/build/mutant_rom.py, on the branch's ROM; build/attempts/wt/v051-tg-wob2/mutants/): fuse_never
-- (Ot6FuseCancel+3=80) is red at "the break during the fuse cancels it"; train_no_trigger (its row keeps every bit
-- and clears no count: Ot6FuseTbl+117=FF, +119=00 on the merged table; +77/+79 before) at "monster switch 0 is clear after the cancel".  A mechanism test,
-- not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/train_b68_entry.mss.lua"

local TRAIN = 0x106

-- The cap: its run ended at f34,113 on the merged ROM (wt/v051-tg-wob1), so 70,000 is about 2x the longest.
H.run({ maxFrames = 70000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control in the corridor"),
  H.fuseEngage(function()
    local ph = 0
    return H.seqStep({
      H.navTo(32, 7, { maxFrames = 8000, playBattles = "tactical" }),
      H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
        H.call(function()
          ph = (ph + 1) % 8
          if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
          if not H.hasControl() then H.setPad({}); return end
          H.setPad(ph < 4 and { "up", "a" } or { "up" })
        end),
      }, "the smokestack switch -> battle 68"),
      H.call(function() H.setPad({}) end),
    })
  end, TRAIN, "the GhostTrain"),
  H.waitUntil(function() return H.battleActive() end, 3000, "the train's battle is up", 2),
  H.call(function()
    H.assertEq(H.readWord(0x11E0) & 0x3FF, 437, "battle 68 is formation 437")
    local t = {}
    for i = 0, 3 do
      local id = H.readByte(0x3ED8 + 2 * i)
      if id ~= 0xFF then t[#t + 1] = string.format("%d: %d/%d", id, H.readWord(0x3BF4 + 2 * i), H.readWord(0x3C1C + 2 * i)) end
    end
    H.log("[ghosttrain] seated: " .. table.concat(t, ", "))
  end),
  H.fuseCases({
    tag = "ghosttrain", species = TRAIN, write = WRITE,
    line = 0x99, move = { cmd = 0x0C, atk = 0xD3 }, turns = 2, glows = 2,
    -- (the party Fights while it arms, the gauge staged past their reach: SHADOW's Interceptor counters on the
    -- train's turns, and three of its blows broke it in a second fuse when the party only Defended)
    arm = "fight",
    bossHp = 2600,
    -- its opening turn taken, nothing counted, nothing armed
    partway = function(W)
      local c = W.cells()
      return c ~= nil and #W.turns >= 1 and c.bvar3 == 0 and c.mvar & 0x01 == 0
    end,
    earned = function(C, W)
      local post, l1, l2 = C.brk.post, C.lines[1], C.lines[2]
      H.assertEq(post.mvar & 0x01, 0, "ghosttrain: monster switch 0 is clear after the cancel")
      H.assertEq(post.bvar3, 0, "ghosttrain: the count of ordinary turns (battle variable 3) is clear after the "
        .. "cancel")
      H.assertEq(l1.max.bvar3 >= 1, true, string.format("ghosttrain: the first arming's count was read climbing (to "
        .. "%d)", l1.max.bvar3))
      H.assertEq(l2.max.bvar3 >= 1, true, string.format("ghosttrain: the trigger was earned again: the count "
        .. "climbed from 0 to %d before the second line", l2.max.bvar3))
    end,
  }),
  H.logStep("[ghosttrain] PASS: the announce, the schedule, the cancel and the trigger earned again"),
})
