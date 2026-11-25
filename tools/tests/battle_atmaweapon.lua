-- @suite savestate=atmaweapon_entry slow
-- battle_atmaweapon.lua -- AtmaWeapon under the boss contract (#561; docs/design/bosses-wob.md block 21): vanilla's
-- own telegraph, "Vast energy focused" -> Flare Star, and the break that cancels it.
--
-- AtmaWeapon's script (ai_script.asm AIScript::_279) is vanilla's, but for one order: its fire turn clears the
-- two switches before Flare Star, not after it (ot6_fuse.asm, the idiom).  Under 12,800 HP its turns are a
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
--   via Break spell  TERRA's Break (Magic, spell $0C) confirmed once the mark is up takes the last shield through
--             Ot6TakeShields, entered with 8-bit index registers, and cancels the fuse; the mark goes (Filch, the
--             other caller of that leaf, is battle_fuse's).
--   outside   a break two turns into the rotation, before any line: nothing is cancelled, the script resumes where
--             it waited, and the fuse lights and fires as in the first case.
-- The ROM before the cancel (f3f644c7) is red at "the move does not fire when the boss recovers": there Flare Star
-- came on its second turn back with no new line (build/attempts/wt/v051-fuse/measure/atmaweapon.log).  Mutants
-- (build/attempts/wt/v051-fuse/mutants-review/): fuse_never is red at "the break by Break spell during the fuse
-- cancels it",
-- fuse_no_trigger at "monster switches 0 and 1 are clear after the cancel".
-- The last phase (wt/v052-tg-wob3, bosses-wob.md block 21): under 6,144 HP vanilla's rotation (Battle/Quartr, then
-- Rasp/W.Wind/Blaze) no longer reaches Mind Blast; its second turn now arms a second fuse (monster switch 2): "Vast
-- energy focused" (the same line) and a glow, and Flare Star on its next turn, one turn of warning.  Its three cases
-- (tag atmaweapon_low) open on a snapshot of their own, its HP held at 5,000: unbroken, broken (switch 2 clear after
-- the cancel, the line on its turn 3 back), outside.  Mutant atma_low_keeps (the second row keeps switch 2: +5 =
-- $FF; build/attempts/wt/v052-tg-wob3/mutants/) is red at "monster switch 2 is clear after the cancel".
-- Crossing (wt/v052-tg-wob3's review): with the first fuse lit its held HP is moved from 12,000 to 5,000, and with the
-- last phase's lit from 5,000 to 7,000 (DECLARED, at the line); Flare Star comes on each fuse's schedule.
-- A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/atmaweapon_entry.mss.lua"

local ATMAWEAPON, INTRO = 0x117, 0x85

-- crossing: a fuse lit, its HP moved across 6,144 (DECLARED: the held HP changed at the line), and the move still
-- comes on its schedule.  hi: the 12,800 rotation's fuse (switch 0), held at 12,000, then at 5,000 from its line (the
-- last phase's rotation would be the one read on a fresh turn); lo: the last phase's (switch 2), held at 5,000, then at
-- 7,000 (a heal back over the line).  The fuse block's condition is its switch alone, so neither crossing drops it.
local function crossing(tag, before, after, mask, turns)
  local W, from, at, li = nil, nil, nil, nil
  local function lastLine()
    local k = nil
    for i, c in ipairs(W.cmds) do if c.cmd == 0x21 and c.arg == 0x65 then k = i end end
    return k
  end
  return H.seqStep({
    H.call(function()
      W = H.fuseWatch(ATMAWEAPON, WRITE); W.on = true; W.pin = { boss = before, party = true }; from = H.frame
      WRITE.byte(0x3E38 + W.ent(), 63)   -- (DECLARED: the gauge held, so no counter breaks it in the case)
    end),
    H.kitBattle({}, { idle = "defend", care = false, maxFrames = 40000,
      giveUp = function()
        local c = W.cells()
        local i = lastLine()
        return (i ~= nil and c ~= nil and c.mvar & mask ~= 0 and W.litBit()) or not H.battleLoadStarted()
      end }),
    H.call(function()
      li = lastLine()
      local i, l = li, li and W.cmds[li]
      H.assertEq(i ~= nil and W.litBit(), true, string.format("%s: its line came and the fuse is lit (switch mask "
        .. "$%02X)", tag, mask))
      W.pin.boss = after
      at = H.frame
      H.log(string.format("[atmaweapon] %s: the line at f%d on its turn %d; its HP held at %d from f%d", tag, l.f,
        l.turn, after, at))
    end),
    H.kitBattle({}, { idle = "defend", care = false, maxFrames = 12000,
      giveUp = function() return W.find(0x0C, 0xC6, li) ~= nil or not H.battleLoadStarted() end }),
    H.call(function()
      local i, l = li, W.cmds[li]
      local mi, mc = W.find(0x0C, 0xC6, i)
      H.assertEq(mi ~= nil, true, string.format("%s: Flare Star came after its HP crossed 6,144 inside the fuse", tag))
      H.log(string.format("[atmaweapon] %s: Flare Star at f%d on its turn %d (the line's %d), HP %d", tag, mc.f,
        mc.turn, l.turn, (W.cells() or { hp = -1 }).hp))
      H.assertEq(mc.turn - l.turn, turns, string.format("%s: on its schedule, %d turn(s) after the line", tag, turns))
      H.assertEq(#W.snuffs, 0, tag .. ": no cancel")
      W.on, W.pin = false, nil
    end),
  })
end
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
    -- the break by OT6's Break spell (TERRA's, Magic $02, spell $0C), the Ot6TakeShields route (Filch is
    -- battle_fuse's)
    via = { { name = "Break spell", who = 0x00, cmd = 0x02, spell = 0x0C } },
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
  -- the last phase (wt/v052-tg-wob3): under 6,144 HP its rotation's second turn arms a second fuse (monster switch
  -- 2), "Vast energy focused" and a glow on its next turn, Flare Star on the turn after; a break between cancels it
  -- (Ot6FuseTbl's second row $0117) and the rotation earns it again from its first turn.  The cases open on a
  -- snapshot of their own, its HP held at 5,000 from there.
  H.fuseCases({
    tag = "atmaweapon_low", species = ATMAWEAPON, write = WRITE,
    line = 0x65, move = { cmd = 0x0C, atk = 0xC6 }, turns = 1, glows = 2,
    arm = "idle",
    bossHp = 5000,
    -- the low rotation's first turn taken, switch 2 clear
    partway = function(W)
      local c = W.cells()
      return c ~= nil and #W.turns >= 1 and (c.mvar & 0x05) == 0
    end,
    earned = function(C, W)
      local pre, post, l2 = C.brk.pre, C.brk.post, C.lines[2]
      H.assertEq(pre.mvar & 0x04, 0x04, "atmaweapon_low: monster switch 2 stood at the break (armed)")
      H.assertEq(post.mvar & 0x04, 0, "atmaweapon_low: monster switch 2 is clear after the cancel")
      local back = l2.turn - C.rec.turn
      H.assertEq(back, 3, string.format("atmaweapon_low: the line returned on its turn 3 back, after the low "
        .. "rotation's two turns (turn %d)", back))
      -- the last phase is the rotation under 6,144: no Mind Blast, so the first fuse is never armed in it
      local mind = 0
      for _, c in ipairs(W.cmds) do if c.arg == 0xC4 and c.cmd ~= 0x21 then mind = mind + 1 end end
      H.assertEq(mind, 0, "atmaweapon_low: no Mind Blast in the last phase (its rotation is the low one)")
    end,
  }),
  crossing("cross down (the first fuse lit)", 12000, 5000, 0x01, 2),
  crossing("cross up (the last phase's fuse lit)", 5000, 7000, 0x04, 1),
  H.logStep("[atmaweapon] PASS: the announce, the schedule, the cancel and the trigger earned again, in both phases, "
    .. "and a lit fuse fires across the 6,144 line either way"),
})
