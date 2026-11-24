-- @suite savestate=camp_intro slow
-- battle_telstar.lua -- Telstar under the boss contract (docs/design/bosses-wob.md block 7, wt/v051-tg-wob2): its
-- call for backup is the telegraph, and a break cancels the call.
--
-- Telstar's script (ai_script.asm AIScript::_68): vanilla's three calls for backup, the monster timer at 25, 80 and
-- 200, each once (battle switches 2, 1, 0), now each announced a turn ahead: "It radios in!" (battle dialogue $98)
-- and a glow, then on its next turn vanilla's own "Alarm's ringing!", its sound and the wave (restore_monsters,
-- command $24).  Under the contract (ot6_fuse.asm, Ot6FuseTbl's three rows $0044) a break while a call is lit
-- cancels it: the script waits nowhere and the clock restarts (the monster's timer to 0), so that wave is earned
-- again from zero; the call's switch is set only by the turn that fires it, so it stands clear.
--
-- Boots camp_intro (gen_sabin_camp: SABIN and SHADOW in the Imperial Camp, map 117), walks beside the camp's monster
-- box at (17,18) (treasure bit 212, formation 61: Telstar alone, the backup in slots 2-5 to be called), opens it,
-- and plays the battle three times from a snapshot at its open (M.fuseCases, lib/ot6.lua, where the cases and the
-- DECLARED staging are written out: the gauge, the row's classes for the breaking Fight, and HP held):
--   unbroken  the party Defends; its first call's line shows when its clock reaches 25; the lit-fuse mark stands
--             before its shield emblem; the wave is dispatched on its next turn, a glow and the alarm's sound
--             between; the mark goes; the alarm's own line comes with the wave and the bodies it calls stand.
--   broken    one member's aimed Fight is confirmed once the mark is up and breaks it: the cancel fires, the mark
--             goes with the hit, the clock reads 0 and the call's switch stands clear, no wave comes on its first
--             turns back, and the line returns only once the clock has climbed to 25 again; the wave follows.
--   outside   a break before the clock reaches 25, no line yet: nothing is cancelled and the script's cells stand,
--             two Fights in the window wind nothing, and the call then lights and fires as in the first case.
-- Mutants (tools/build/mutant_rom.py, on the branch's ROM; build/attempts/wt/v051-tg-wob2/mutants/): fuse_never
-- (Ot6FuseCancel+3=80) is red at "the break during the fuse cancels it"; telstar_no_clock (its three rows' flags 0:
-- Ot6FuseTbl+95/+103/+111=00 on the merged table, +55/+63/+71 before wt/v051-tg-wob1's five rows) at "the clock was restarted by the cancel".  A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/camp_intro.mss.lua"

local TELSTAR, MAP, BOX, BESIDE = 0x044, 117, { 17, 18 }, { 17, 19 }
local CLOCK = 2 * 25            -- the first call: if_monster_timer 25 reads half the timer word
local function map() return H.mapId() & 0x1ff end

local CFG
CFG = {
  tag = "telstar", species = TELSTAR, write = WRITE,
  line = 0x98, move = { cmd = 0x24, atk = 0x03 }, turns = 1, glows = 2,
  arm = "idle",
  bossHp = nil,                 -- its own maximum, read at the open (below)
  -- the clock part run, no call yet
  partway = function(W)
    local c = W.cells()
    return c ~= nil and c.timer >= 10 and c.timer < CLOCK - 20
  end,
  earned = function(C, W)
    local pre, post, l2 = C.brk.pre, C.brk.post, C.lines[2]
    H.assertEq(pre.timer >= CLOCK and post.timer <= 1, true, string.format("telstar: the clock was restarted by "
      .. "the cancel (the monster's timer read %d at the break and %d after it)", pre.timer, post.timer))
    H.assertEq(post.bsw & 0x04, 0, "telstar: the call's battle switch (2) stands clear after the cancel: the wave "
      .. "was not called")
    H.assertEq(l2.cells.timer >= CLOCK, true, string.format("telstar: the line returned only once the clock had "
      .. "climbed to 25 again (timer %d at the second line)", l2.cells.timer))
  end,
  -- the story with the wave: vanilla's alarm line ($44) on the turn that calls it, after the announce
  fired = function(C, W, n)
    local l = C.lines[n]
    local i = W.find(0x21, 0x44, l.i + 1)
    H.assertEq(i ~= nil and i < l.move.i and W.cmds[i].turn == l.move.turn, true, "telstar: vanilla's \"Alarm's "
      .. "ringing!\" (dlg $44) comes with the wave, on the turn that calls it")
  end,
}

-- the wave: the alarm's own line ($44) with it, and bodies standing in the slots it calls
local function waveCheck(what)
  return H.seqStep({
    H.waitFrames(240),
    H.call(function()
      local n = 0
      for s = 2, 5 do
        if H.readByte(0x3AA8 + s * 2) & 1 == 1 then n = n + 1 end
      end
      H.log(string.format("[telstar] %s: %d of the called slots stand", what, n))
      H.assertEq(n >= 1, true, "telstar: the wave it called stands (" .. what .. ")")
    end),
  })
end

H.run({ maxFrames = 400000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control in the Imperial Camp"),
  H.call(function()
    H.assertEq(map(), MAP, "camp_intro stands in the Imperial Camp (map 117)")
    H.assertEq(H.chestOpen(212), false, "the camp's monster box (bit 212) is shut")
  end),
  H.navTo(BESIDE[1], BESIDE[2], { maxFrames = 12000, playBattles = "tactical" }),
  H.fuseEngage(function()
    return H.seqStep({
      H.navTo(BESIDE[1], BESIDE[2], { maxFrames = 6000, playBattles = "tactical" }),
      H.faceAndHoldA("up", function() return H.battleLoadStarted() end, 3000,
        string.format("the monster box at (%d,%d): face up, A", BOX[1], BOX[2])),
      H.release(),
    })
  end, TELSTAR, "Telstar's box"),
  H.waitUntil(function() return H.battleActive() end, 3000, "the box's battle is up", 2),
  H.call(function()
    H.assertEq(H.readWord(0x11E0) & 0x3FF, 61, "the box's battle is formation 61")
    for s = 0, 5 do
      if H.readByte(0x3AA8 + s * 2) & 1 == 1 and H.readWord(0x57C0 + s * 2) == TELSTAR then
        CFG.bossHp = H.readWord(0x3C1C + 8 + 2 * s)
        H.log(string.format("[telstar] Telstar in slot %d, HP %d/%d, shields %d", s, H.readWord(0x3BF4 + 8 + 2 * s),
          CFG.bossHp, H.readByte(0x3E38 + 8 + 2 * s)))
      end
    end
    H.assertEq(CFG.bossHp ~= nil, true, "Telstar stands in the box's battle")
    local t = {}
    for s = 2, 5 do t[#t + 1] = string.format("$%03X", H.readWord(0x57C0 + s * 2)) end
    H.log("[telstar] the slots its calls fill hold " .. table.concat(t, " "))
  end),
  H.fuseCases(CFG),
  waveCheck("after the last case's wave"),
  H.logStep("[telstar] PASS: the announce, the schedule, the cancel and the clock earned again"),
})
