-- @suite savestate=ultros2_entry slow
-- battle_ultros2.lua -- the Opera's Ultros 2 break gauge. Boots
-- ultros2_entry, rides into battle 104, and asserts:
--   1. Ultros 2 ($012d) seeds 6/6 shields and his Ot6ShieldTbl class row: two
--      of the six classes (#566; v0.50's slash|pierce $03), the sword one of
--      them (his slash is the party's swords).
--   2. Nothing is revealed on the fixture's codex at seed.
--   3. His song is his telegraph (bosses-wob.md block 12, wt/v052-tg-wob2; ai_script.asm AIScript::_301).
--      Vanilla sang Imp Song (attack $A3, command $0C) on the turn the battle timer reached 60, with its line "Imp!
--      Pal! Buddy!" (battle dialogue $62) in the same turn.  Now the line and a glow come on that turn and the song
--      on his next; his slot moves wait while it is lit (monster switch 0).  Under the contract (Ot6FuseTbl's row
--      $012D, OT6_FUSE_BTIMER) a break while it is lit cancels it and the battle timer starts again from zero.
--      M.fuseCases (lib/ot6.lua, where the cases and the DECLARED staging are written out: the gauge, the row's
--      classes for the breaking Fight, HP held -- his at 1,500) plays three cases from a snapshot after the seed:
--        unbroken  the party Defends; the line shows once the timer has run; the lit-fuse mark stands; Imp Song is
--                  dispatched on his next turn, a glow between; the mark goes.
--        broken    an aimed Fight confirmed once the mark is up breaks him: the cancel fires, the mark goes, the
--                  battle timer reads 0 after it, no song on his first turns back, and the line returns only once
--                  the timer has run again (a body his counter swaps in meanwhile starts its script from the top);
--                  the song follows.
--        outside   a break after his first turn, before his first slot move can come (his tally of turns, battle
--                  variable 3, at most 1): nothing is cancelled and the cells stand, two aimed Fights in the window
--                  wind nothing, and the fuse then lights and fires as in the first case.
--      Mutants (build/attempts/wt/v052-tg-wob2/mutants/): fuse_never (Ot6FuseCancel+3=80) is red at "the break during
--      the fuse cancels it"; ultros2_no_btimer (his row's flags byte 0) at "the battle timer reads 0 after the
--      cancel".  A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
-- the battle timer ($3A44), frame by frame (the cancel's reset is read two frames after the break)
local btimer, btOn = {}, false
local DOOR = "build/states/ultros2_entry.mss.lua"

local ULTROS2 = 0x012d
local OT6_SWORD = 0x01
local ULTROS2 = 0x012D

-- monster slot s -> entity offset 8 + 2s
local function SH(s)  return 0x3E38 + (8 + s * 2) end   -- current shields
local function SMX(s) return 0x3E39 + (8 + s * 2) end   -- max shields
local function RVE(s) return 0x3E89 + (8 + s * 2) end   -- revealed elements
local function WKC(s) return 0x3E9C + (8 + s * 2) end   -- weak class (authored)
local function RVC(s) return 0x3E9D + (8 + s * 2) end   -- revealed class
local function MHP(s) return 0x3BFC + s * 2 end

local uSlot = 0
local aPh = 0

-- The cap: the seed check ends near f2,000 and three cases of about 12,000 frames each follow, so 90,000 is about
-- 2x.
H.run({ maxFrames = 90000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),

  -- ride the last interaction into battle 104
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function()
      aPh = (aPh + 1) % 8
      if H.monstersPresent() > 0 then
        for s = 0, 5 do
          if H.readByte(0x3aa8 + s * 2) % 2 == 1 then end  -- (no forced clear; goal fight)
        end
      end
      H.setPad(aPh < 4 and { "a" } or {})
    end),
  }, "the rafter scene reaches battle 104"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 3000, "Ultros 2 up", 10),
  H.waitFrames(120),

  -- 1 + 2: the seed, read before anything is poked.
  H.call(function()
    local w = {}
    for s = 0, 5 do w[s] = H.readWord(0x57C0 + s * 2) end
    H.log(string.format("formation %04X %04X %04X %04X %04X %04X",
      w[0], w[1], w[2], w[3], w[4], w[5]))
    uSlot = nil
    for s = 0, 5 do
      if w[s] == ULTROS2 and (H.readByte(0x3aa8+s*2)&1)~=0 then uSlot = s; break end
    end
    H.assertEq(uSlot ~= nil, true, "ULTROS 2 ($012d) is in the formation")

    H.assertEq(H.readByte(SH(uSlot)), 6, "ULTROS 2 seeds 6 shields (Ot6ShieldTbl)")
    H.assertEq(H.readByte(SMX(uSlot)), 6, "ULTROS 2 max shields 6")
    local wc = H.readByte(WKC(uSlot))
    local row = H.speciesClassRow(ULTROS2)
    H.log(string.format("ULTROS 2 weak class = $%02X (the ROM's row $%02X)", wc, row))
    H.assertEq(wc, row, "ULTROS 2 class row is the ROM's (Ot6ShieldTbl $012D)")
    local bits = 0
    for b = 0, 5 do if row & (1 << b) ~= 0 then bits = bits + 1 end end
    H.assertEq(bits, 2, "and holds two weapon classes (v0.50's slash|pierce, split)")
    H.assertEq(row & OT6_SWORD, OT6_SWORD, "the sword one of them")
    H.assertEq(H.readByte(RVC(uSlot)), 0, "nothing revealed yet (classes) -- virgin codex")
    H.assertEq(H.readByte(RVE(uSlot)), 0, "nothing revealed yet (elements)")
    H.log(string.format("ULTROS 2 seed: %d/%d shields, class $%02X",
      H.readByte(SH(uSlot)), H.readByte(SMX(uSlot)), wc))
    H.screenshot("ultros2_seed")
  end),

  -- Ultros occupies four formation positions and moves between them.
  H.logStep(function()
    return string.format("Ultros 2 ($012d) verified in battle 104 at frame %d",H.frame)
  end),

  -- 3: the telegraph
  H.call(function()
    btOn = true
    emu.addEventCallback(function()
      if btOn then btimer[H.frame] = H.readWord(0x3A44); btimer[H.frame - 60000] = nil end
    end, emu.eventType.endFrame)
  end),
  H.fuseCases({
    tag = "ultros2", species = ULTROS2, write = WRITE,
    line = 0x62, move = { cmd = 0x0C, atk = 0xA3 }, turns = 1, glows = 1,
    arm = "idle", aim = true,
    bossHp = 1500,
    -- his first turn taken (his greeting), his tally of turns still under his first slot move's
    partway = function(W)
      return #W.turns >= 1 and H.readByte(0x3EB3) <= 1
    end,
    earned = function(C, W)
      local t = btimer[C.brk.f + 2]
      H.log(string.format("[ultros2] the battle timer %s before the break, %s two frames after",
        tostring(btimer[C.brk.f - 1]), tostring(t)))
      H.assertEq(t ~= nil and t < 4, true, "ultros2: the battle timer reads 0 after the cancel (the song is earned "
        .. "from the cancel)")
      local l1, l2 = C.lines[1], C.lines[2]
      H.assertEq(l2.f - C.brk.f >= 600, true, string.format("ultros2: the second line came a whole clock after the "
        .. "cancel (%d frames)", l2.f - C.brk.f))
    end,
  }),
  H.call(function() btOn = false end),
  H.logStep("[ultros2] PASS: the seed, and the song announced, cancelled by a break and earned again"),
})
