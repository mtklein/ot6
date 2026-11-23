-- @suite savestate=kefka_tier slow
-- battle_goner.lua -- Kefka under the boss contract (#561; docs/design/bosses-wor.md block 33): vanilla's own
-- telegraph, "The end comes...beyond chaos." -> Goner, and the break that cancels it.
--
-- Kefka's script (ai_script.asm AIScript::_298) is vanilla's, unchanged.  Under 32,640 HP his turns are a rotation
-- of four: the line (dlg $8C), battle switches 0 and 1 and his head's animation; Goner on the next turn; then two
-- turns of attacks, the first of which clears the switches.  (Under 7,680 the block before it does the same with
-- Meteor behind Goner.)  While switch 0 is set his counters, HyperDrive and Ultima, stand down.  Under the
-- contract (ot6_fuse.asm, Ot6FuseTbl's two rows $012A) a break while the fuse is lit cancels it: the script waits
-- nowhere and both switches are cleared, the state his rotation's end leaves.  His HP arms the fuse, so he says the
-- line again on his first turn back, and Goner needs the full turn after it again.
--
-- Boots kefka_tier (gen_wor_kefka: the battle as Kefka's formation, 514, begins, the party as the three tiers
-- left it) and plays his tier three times from a snapshot at its open (M.fuseCases, lib/ot6.lua, where the cases
-- and the DECLARED staging are written out: the gauge, the row's classes for the breaking Fight, and HP held --
-- Kefka's at 30,000, under the line, from the open; at 50,000 in the "outside" case until its break ends):
--   unbroken  the party Defends; the line shows; the lit-fuse mark stands before his shield emblem; Goner is
--             dispatched on his next turn, with his head's animation between; the mark goes.
--   broken    one member's aimed Fight is confirmed once the mark is up and breaks him: the cancel fires, the mark
--             goes with the hit, both switches read clear, his first turn back is the line again and not Goner,
--             and Goner follows it.
--   outside   above the line (50,000): a break two turns into his opening rotation, before any line: nothing is
--             cancelled and the script's cells stand; then, under the line, the fuse lights and fires as in the
--             first case.
-- The ROM before the cancel (f3f644c7) is red at "the move does not fire when the boss recovers": there Goner
-- came on his first turn back with no new line (build/attempts/wt/v051-fuse/measure/goner.log).
-- A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/kefka_tier.mss.lua"

local KEFKA = 0x12A

H.run({ maxFrames = 400000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function()
    if not H.battleActive() then return false end
    for s = 0, 5 do
      if H.readByte(0x3AA8 + s * 2) & 1 == 1 and H.readWord(0x57C0 + s * 2) == KEFKA then return true end
    end
    return false
  end, 6000, "Kefka's tier is up (formation 514)", 2),
  H.call(function()
    H.assertEq(H.readWord(0x11E0), 0x0202, "kefka_tier is the battle at Kefka's formation ($0202)")
    local t = {}
    for i = 0, 3 do
      local id = H.readByte(0x3ED8 + 2 * i)
      if id ~= 0xFF then t[#t + 1] = string.format("%d: %d/%d", id, H.readWord(0x3BF4 + 2 * i), H.readWord(0x3C1C + 2 * i)) end
    end
    H.log("[goner] seated: " .. table.concat(t, ", "))
  end),
  H.fuseCases({
    tag = "goner", species = KEFKA, write = WRITE,
    line = 0x8C, move = { cmd = 0x0C, atk = 0xDE }, turns = 1, glows = 1,
    arm = "idle",
    bossHp = 30000, outsideHp = 50000,
    -- two turns into the tier above the line (his speech's turn, then Fallen One), no line yet
    partway = function(W) return #W.turns >= 2 end,
    earned = function(C, W)
      local post, l2 = C.brk.post, C.lines[2]
      H.assertEq(post.bsw & 0x03, 0, "goner: battle switches 0 and 1 are clear after the cancel (his counters "
        .. "stand again)")
      H.assertEq(l2.turn - C.rec.turn, 1, string.format("goner: his first turn back is the line again (the fuse "
        .. "starts over: announce on turn %d, %d turn(s) after the break ended)", l2.turn, l2.turn - C.rec.turn))
    end,
  }),
  H.logStep("[goner] PASS: the announce, the schedule, the cancel and the fuse started again"),
})
