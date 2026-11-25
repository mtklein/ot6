-- @suite savestate=airforce_entry slow
-- battle_airforce.lua -- the Air Force under the boss contract (docs/design/bosses-wob.md block 20, wt/v052-tg-wob3):
-- the MissileBay's Launcher is its telegraph, breaking the BAY cancels it, and breaking the body does not.
--
-- The bay's script (ai_script.asm AIScript::_327): its second Missile turn ARMS the fuse (monster switch 0; under
-- 1,536 HP every Missile turn does); "Missiles lock on!" (battle dialogue $9E) and a glow announce it on its next
-- turn, and the Launcher (attack $CD, command $0C) comes on the turn after.  Under the contract (Ot6FuseTbl's row
-- $0147) a break of the bay while it is lit cancels it: switch 0 goes, and two more Missile turns earn it again.
-- The Launcher comes only announced (its script names it once, in the fuse block: asserted from the ROM).
--
-- Boots airforce_entry (gen_fc_landing: the Air Force's battle as it comes up, TERRA, LOCKE and EDGAR, straight
-- from the deck) and plays the bay's cases from a snapshot at the open (M.fuseCases, lib/ot6.lua, where the cases
-- and the DECLARED staging are written out: the gauge, the row's classes for the breaking Fight, HP held -- the
-- bay's at 2,500, above its low line):
--   unbroken  the party Defends; the line shows on the turn after its second Missile; the lit-fuse mark stands
--             before the bay's shield emblem; the Launcher is dispatched on its next turn, a glow between; the mark
--             goes; the line reads "Missiles lock on!" where the relocated dialogue table points.
--   broken    an aimed Fight confirmed once the mark is up breaks the bay: the cancel fires, the mark goes, switch
--             0 reads clear, no Launcher on its first turns back, and the line returns only after two more Missile
--             turns; the Launcher follows.
--   outside   a break after its first Missile, before any line: nothing is cancelled and the cells stand, two aimed
--             Fights in the window wind nothing, and the fuse then lights and fires as in the first case.
--   the body  (below) with the bay's fuse lit, an aimed Fight breaks the Air Force's BODY (its gauge staged to 1 with
--             every class, DECLARED): the body breaks, the bay's fuse is not cancelled, and the Launcher comes on
--             the bay's next turn.
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wob3/mutants/): fuse_never (Ot6FuseCancel+3=80) is red
-- at "the break during the fuse cancels it"; bay_row_keeps (its row keeps switch 0: +5 = $FF) at "monster switch 0
-- is clear after the cancel"; bay_launcher_back (its low rotation fires the Launcher again) at "the Launcher comes
-- only announced".  A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them; the body case
-- stages the body's gauge and the bay's through the same pair; nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/airforce_entry.mss.lua"

local AIRFORCE, BAY, LAUNCHER, MISSILE = 0x113, 0x147, 0xCD, 0xDD

-- the bay's Missiles dispatched between two frames (W.cmds: since the case's open)
local function missilesBetween(W, f0, f1)
  local n = 0
  for _, c in ipairs(W.cmds) do if c.arg == MISSILE and c.cmd ~= 0x21 and c.f > f0 and c.f < f1 then n = n + 1 end end
  return n
end

-- the body case: the bay's fuse lit, the body broken
function bodyCase()
  local B, A, brokeF = nil, nil, nil
  return H.seqStep({
    H.call(function()
      B = H.fuseWatch(BAY, WRITE); B.on = true; B.pin = { boss = 2500, party = true }
      A = H.fuseWatch(AIRFORCE, WRITE); A.on = true; A.pin = { boss = 6000 }
    end),
    -- (no fuse lit or armed as the case opens: Defend until the bay's switch 0 is clear)
    H.kitBattle({}, { idle = "defend", care = false, maxFrames = 12000,
      giveUp = function() local c = B.cells(); return c == nil or (c.mvar & 1 == 0 and not B.litBit()) end }),
    H.kitBattle({}, { idle = "defend", care = false, maxFrames = 30000,
      giveUp = function() return B.find(0x21, 0x9E, 1) ~= nil and B.litBit() end }),
    H.lazy(function()
      local li, lc = B.find(0x21, 0x9E, 1)
      H.assertEq(li ~= nil and B.litBit(), true, "the body case: the bay's line came and its fuse is lit")
      local who = nil
      for i = 0, 3 do
        local id = H.readByte(0x3ED8 + 2 * i)
        if id ~= 0xFF and H.readWord(0x3BF4 + 2 * i) > 0 then who = id; break end
      end
      local e = A.ent()
      WRITE.byte(0x3E9C + e, 0x3F)       -- (DECLARED: every class a key on the body)
      WRITE.byte(0x3E38 + e, 1)          -- (DECLARED: the body's gauge at 1)
      WRITE.byte(0x3E38 + B.ent(), 63)   -- (DECLARED: the bay's gauge held, so no stray hit breaks it)
      H.log(string.format("[airforce] the body case: the bay lit (line f%d); char %d aims a Fight at the body", lc.f,
        who))
      return H.kitBattle({ { who = who, cmd = 0x00, boost = 0, slot = A.slot() } }, { idle = "defend", care = false,
        maxFrames = 6000, giveUp = function() return #A.breaks > 0 or B.find(0x0C, LAUNCHER, li) ~= nil end })
    end),
    H.call(function()
      local li = B.find(0x21, 0x9E, 1)
      H.assertEq(#A.breaks >= 1, true, "the body case: the Fight broke the Air Force's body")
      brokeF = A.breaks[1].f
      H.assertEq(B.find(0x0C, LAUNCHER, li) == nil or B.cmds[B.find(0x0C, LAUNCHER, li)].f > brokeF, true,
        "the body case: the body broke inside the bay's fuse (the case's precondition)")
    end),
    H.kitBattle({}, { idle = "defend", care = false, maxFrames = 8000,
      giveUp = function() return B.find(0x0C, LAUNCHER, B.find(0x21, 0x9E, 1)) ~= nil end }),
    H.call(function()
      local li, lc = B.find(0x21, 0x9E, 1)
      local mi, mc = B.find(0x0C, LAUNCHER, li)
      H.assertEq(#B.snuffs, 0, "the body case: breaking the body cancelled no fuse of the bay's")
      H.assertEq(mi ~= nil, true, "the body case: the Launcher came after the body's break")
      H.assertEq(mc.turn - lc.turn, 1, string.format("the body case: the Launcher came on the bay's next turn after "
        .. "its line (turn %d, the line's %d)", mc.turn, lc.turn))
      H.log(string.format("[airforce] the body case: the body broke at f%d inside the bay's fuse (line f%d); the "
        .. "Launcher at f%d, on the bay's next turn", brokeF, lc.f, mc.f))
      B.on, A.on, B.pin, A.pin = false, false, nil, nil
    end),
  })
end

-- The cap: three cases of about 10,000 frames each (the bay is slow: speed 20) and the body case's about 12,000, so
-- 100,000 is about 2x.
H.run({ maxFrames = 100000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitUntil(function() return H.battleActive() end, 3000, "the Air Force's battle is up", 2),
  H.call(function()
    local at = H.aiAttacks(BAY, LAUNCHER)
    H.log(string.format("[airforce] the bay's turn script names the Launcher at %d place(s)", #at))
    H.assertEq(#at, 1, "the Launcher comes only announced: the bay's turn script names it once (the fuse block)")
    local present = 0
    for s = 0, 5 do
      local sp = H.readWord(0x57C0 + s * 2)
      if H.readByte(0x3AA8 + s * 2) & 1 == 1 and (sp == AIRFORCE or sp == BAY) then present = present + 1 end
    end
    H.assertEq(present, 2, "the Air Force and its MissileBay stand at the open (airforce_entry)")
  end),
  H.fuseCases({
    tag = "missilebay", species = BAY, write = WRITE,
    line = 0x9E, move = { cmd = 0x0C, atk = LAUNCHER }, turns = 1, glows = 1,
    lineText = "Missiles lock on!{wait}",
    arm = "idle", aim = true,
    bossHp = 2500,
    -- one Missile fired, switch 0 clear
    partway = function(W)
      local c = W.cells()
      return c ~= nil and missilesBetween(W, 0, H.frame + 1) >= 1 and (c.mvar & 0x01) == 0
    end,
    earned = function(C, W)
      local pre, post = C.brk.pre, C.brk.post
      H.assertEq(pre.mvar & 0x01, 0x01, "missilebay: monster switch 0 stood at the break (armed)")
      H.assertEq(post.mvar & 0x01, 0, "missilebay: monster switch 0 is clear after the cancel")
      local n = missilesBetween(W, C.brk.f, C.lines[2].f)
      H.log(string.format("[airforce] %d Missile(s) between the cancel (f%d) and the second line (f%d)", n, C.brk.f,
        C.lines[2].f))
      H.assertEq(n >= 2, true, "missilebay: two more Missile turns came between the cancel and the second line")
    end,
  }),
  bodyCase(),
  H.logStep("[airforce] PASS: the bay's Launcher announced, cancelled by the bay's break, not by the body's"),
})
