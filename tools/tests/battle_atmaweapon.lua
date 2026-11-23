-- @suite savestate=atmaweapon_entry slow
-- battle_atmaweapon.lua -- AtmaWeapon under the boss contract (#561; docs/design/bosses-wob.md block 21): vanilla's
-- own telegraph, "Vast energy focused" -> Flare Star, and the break that cancels it.
--
-- AtmaWeapon's script (ai_script.asm AIScript::_279) is vanilla's, unchanged.  Under 12,800 HP its turns are a
-- rotation of four (Bio/Quake/Meteo, Battle/Special, Fire 2 on the party, Mind Blast), and the fourth sets monster
-- switches 0 and 1.  With switch 0 set its turn is the fuse block: "Vast energy focused" (dlg $65), Shell, Safe and
-- Haste, a glow; a second glowing turn; then the long glow and Flare Star on the third, which clears both
-- switches.  Under the contract (ot6_fuse.asm, Ot6FuseTbl's row $0117) a break while the fuse is lit cancels it:
-- the script waits nowhere and both switches are cleared, so the rotation starts over and has to run its four
-- turns again before the next announce.
--
-- Boots atmaweapon_entry (gen_fc_escape: the party on AtmaWeapon's doorstep on the Floating Continent), talks to
-- it (battle 108's event), and plays the battle three times from a snapshot at its open (M.fuseCases, lib/ot6.lua,
-- where the cases and the DECLARED staging are written out: the gauge, the row's classes for the breaking Fight,
-- and HP held -- AtmaWeapon's at 12,000, inside the rotation's band, 6,144 to 12,800, from the open):
--   unbroken  the party Defends; the line shows on the turn after Mind Blast; the lit-fuse mark stands before the
--             shield emblem; Flare Star is dispatched on the second turn after the announce, with three glow
--             commands between; the mark goes.
--   broken    one member's aimed Fight is confirmed once the mark is up and breaks it: the cancel fires, the mark
--             goes with the hit, its first turns back hold no Flare Star, both switches read clear, and the line
--             returns only after as many of its own turns as the first arming took; Flare Star follows that.
--   outside   a break two turns into the rotation, before any line: nothing is cancelled, the script resumes where
--             it waited, and the fuse lights and fires as in the first case.
-- The ROM before the cancel (f3f644c7) is red at "the move does not fire when the boss recovers": there Flare Star
-- came on its second turn back with no new line (build/attempts/wt/v051-fuse/measure/atmaweapon.log).  Mutants
-- (build/attempts/wt/v051-fuse/mutants/): fuse_never is red at "the break during the fuse cancels it",
-- fuse_no_trigger at "monster switches 0 and 1 are clear after the cancel".
-- A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/atmaweapon_entry.mss.lua"

local ATMAWEAPON, INTRO = 0x117, 0x85
local function atmaUp() return (H.readByte(0x1EEB) >> 7) & 1 == 1 end      -- $035F: AtmaWeapon stands at (60,15)

H.run({ maxFrames = 400000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control on AtmaWeapon's doorstep"),
  H.fuseEngage(function()
    H.assertEq(atmaUp(), true, "$035F set -- AtmaWeapon stands at (60,15)")
    H.assertEq(H.fieldX() == 60 and (H.fieldY() == 16 or H.fieldY() == 14), true,
      "atmaweapon_entry stands on the doorstep, (60,16) or (60,14)")
    -- gen_fc_escape's talk: turn to face it, release, tap A while standing still, until a battle loads
    local face, t = H.fieldY() == 16 and "up" or "down", 0
    return H.driveUntil(function()
      t = t + 1
      return H.battleActive() or H.battleLoadStarted()
    end, 4000, {
      H.call(function()
        local c = t % 48
        if c < 4 then H.setPad({ [face] = true })
        elseif c >= 24 and c < 28 then H.setPad({ a = true })
        else H.setPad({}) end
      end),
    }, "AtmaWeapon engaged")
  end, ATMAWEAPON, "AtmaWeapon"),
  H.fuseCases({
    tag = "atmaweapon", species = ATMAWEAPON, write = WRITE,
    line = 0x65, move = { cmd = 0x0C, atk = 0xC6 }, turns = 2, glows = 3,
    arm = "idle",
    bossHp = 12000,
    -- two turns into the rotation (its first turn is the speech, dlg $85), no line yet
    partway = function(W) return #W.turns >= 3 end,
    earned = function(C, W)
      local post, l1, l2 = C.brk.post, C.lines[1], C.lines[2]
      H.assertEq(post.mvar & 0x03, 0, "atmaweapon: monster switches 0 and 1 are clear after the cancel")
      local _, intro = W.find(0x21, INTRO, 1)
      local first = l1.turn - (intro and intro.turn or 0)
      local back = l2.turn - C.rec.turn
      H.assertEq(first >= 2, true, string.format("atmaweapon: the first arming took turns of its own (%d, after "
        .. "the speech)", first))
      H.assertEq(back, first, string.format("atmaweapon: the trigger was earned again in full: the line returned "
        .. "on its turn %d back, as many turns as the first arming took (%d)", back, first))
    end,
  }),
  H.logStep("[atmaweapon] PASS: the announce, the schedule, the cancel and the trigger earned again"),
})
