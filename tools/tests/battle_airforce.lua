-- @suite savestate=airforce_entry slow
-- battle_airforce.lua -- the Air Force under the boss contract (docs/design/bosses-wob.md block 20, wt/v052-tg-wob3):
-- the MissileBay's Launcher is its telegraph under 1,536 HP, breaking the BAY cancels it, breaking the body does
-- not, and a bay that dies in the fuse fires nothing.
--
-- The bay's script (ai_script.asm AIScript::_327): above 1,536 HP it fires Missiles only, as vanilla.  Under 1,536 HP
-- (vanilla's gate for its barrage) each Missile turn ARMS the fuse (monster switch 0); "Missiles lock on!" (battle
-- dialogue $9E) and a glow announce it on its next turn, and the Launcher (attack $CD, command $0C) comes on the turn
-- after.  Under the contract (Ot6FuseTbl's row $0147) a break of the bay while it is lit cancels it: switch 0 goes,
-- and its next Missile turn earns it again.  The Launcher comes only announced (its script names it once, in the
-- fuse block: asserted from the ROM).  (The first cut armed it from the open at any HP; the line's own fighter lost
-- the battle on 4 of 5 keys: build/attempts/wt/v052-tg-wob3/F-bay/.)
--
-- Boots airforce_entry (gen_fc_landing: the Air Force's battle as it comes up, TERRA, LOCKE and EDGAR, straight
-- from the deck):
--   high      the bay's HP held at 2,500, above its gate (DECLARED): three of its turns, the party Defending, bring
--             Missiles only and no line.
--   then the bay's cases from a snapshot (M.fuseCases, lib/ot6.lua, where the cases and the DECLARED staging are
--   written out: the gauge, the row's classes for the breaking Fight, HP held -- the bay's at 1,000, under its gate):
--   unbroken  the party Defends; the line shows on the turn after a Missile; the lit-fuse mark stands before the
--             bay's shield emblem; the Launcher is dispatched on its next turn, a glow between; the mark goes; the
--             line reads "Missiles lock on!" where the relocated dialogue table points.
--   broken    an aimed Fight confirmed once the mark is up breaks the bay: the cancel fires, the mark goes, switch
--             0 reads clear, no Launcher on its first turns back, and the line returns only after another Missile
--             turn; the Launcher follows.
--   outside   a break after its first Missile, before any line: nothing is cancelled and the cells stand, two aimed
--             Fights in the window wind nothing, and the fuse then lights and fires as in the first case.
--   the body  (below) with the bay's fuse lit, an aimed Fight breaks the Air Force's BODY (its gauge staged to 1 with
--             every class, DECLARED): the body breaks, the bay's fuse is not cancelled, and the Launcher comes on
--             the bay's next turn.
--   killed    (below) with the bay's fuse lit, the bay is killed (its HP staged to 1, DECLARED, and an aimed Fight):
--             no Launcher comes, and the lit bit and the "!" clear.
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wob3/mutants-*/): fuse_never (Ot6FuseCancel+3=80) is
-- red at "the break during the fuse cancels it"; bay_row_keeps (its row keeps switch 0: +5 = $FF) at "monster switch
-- 0 is clear after the cancel"; bay_launcher_back (a Missile of its rotation fires the Launcher again) at "the
-- Launcher comes only announced"; bay_no_gate (its gate at 3,584 HP) at "high: no line above 1,536 HP".  A mechanism
-- test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them; the high, body and
-- killed cases stage HP and gauges through the same pair; nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/airforce_entry.mss.lua"

local AIRFORCE, BAY, LAUNCHER, MISSILE = 0x113, 0x147, 0xCD, 0xDD

-- the bay's Missiles dispatched between two frames (W.cmds: since the case's open)
local function missilesBetween(W, f0, f1)
  local n = 0
  for _, c in ipairs(W.cmds) do if c.arg == MISSILE and c.cmd ~= 0x21 and c.f > f0 and c.f < f1 then n = n + 1 end end
  return n
end

-- the next line of the bay's from frame f (B's records)
local function lineFrom(B, f)
  for i, c in ipairs(B.cmds) do if c.cmd == 0x21 and c.arg == 0x9E and c.f >= f then return i, c end end
  return nil
end
local function firstStanding()
  for i = 0, 3 do
    local id = H.readByte(0x3ED8 + 2 * i)
    if id ~= 0xFF and H.readWord(0x3BF4 + 2 * i) > 0 and (H.readByte(0x3EE4 + 2 * i) & 0xC2) == 0 then return id end
  end
  return nil
end

-- high: above the gate, Missiles only
local function highCase()
  local B = nil
  return H.seqStep({
    H.call(function()
      B = H.fuseWatch(BAY, WRITE); B.on = true; B.pin = { boss = 2500, party = true }
    end),
    H.kitBattle({}, { idle = "defend", care = false, maxFrames = 12000,
      giveUp = function() return #B.turns >= 3 or not H.battleLoadStarted() end }),
    H.call(function()
      local miss, other, lines = 0, 0, 0
      for _, c in ipairs(B.cmds) do
        if c.cmd == 0x21 and c.arg == 0x9E then lines = lines + 1
        elseif c.arg == MISSILE then miss = miss + 1
        elseif c.cmd < 0x20 then other = other + 1 end
      end
      H.log(string.format("[airforce] high: %d bay turn(s) at 2,500 HP: %d Missile(s), %d other attack(s), %d line(s)",
        #B.turns, miss, other, lines))
      H.assertEq(#B.turns >= 3, true, "high: three of the bay's turns came (the case's precondition)")
      H.assertEq(lines, 0, "high: no line above 1,536 HP (vanilla's gate)")
      H.assertEq(miss >= 3 and other == 0, true, "high: above 1,536 HP the bay fires Missiles only, as vanilla")
      B.on, B.pin = false, nil
    end),
  })
end

-- the body case: the bay's fuse lit, the body broken
local function bodyCase()
  local B, A, brokeF, from = nil, nil, nil, nil
  return H.seqStep({
    H.call(function()
      B = H.fuseWatch(BAY, WRITE); B.on = true; B.pin = { boss = 1000, party = true }
      A = H.fuseWatch(AIRFORCE, WRITE); A.on = true; A.pin = { boss = 6000 }
      from = H.frame
    end),
    H.kitBattle({}, { idle = "defend", care = false, maxFrames = 30000,
      giveUp = function() return lineFrom(B, from) ~= nil and B.litBit() end }),
    H.lazy(function()
      local li, lc = lineFrom(B, from)
      H.assertEq(li ~= nil and B.litBit(), true, "the body case: the bay's line came and its fuse is lit")
      local who = firstStanding()
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
      local li = lineFrom(B, from)
      H.assertEq(#A.breaks >= 1, true, "the body case: the Fight broke the Air Force's body")
      brokeF = A.breaks[1].f
      H.assertEq(B.find(0x0C, LAUNCHER, li) == nil or B.cmds[B.find(0x0C, LAUNCHER, li)].f > brokeF, true,
        "the body case: the body broke inside the bay's fuse (the case's precondition)")
    end),
    H.kitBattle({}, { idle = "defend", care = false, maxFrames = 8000,
      giveUp = function() return B.find(0x0C, LAUNCHER, (lineFrom(B, from))) ~= nil end }),
    H.call(function()
      local li, lc = lineFrom(B, from)
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

-- the killed case: the bay's fuse lit, the bay killed
local function killedCase()
  local B, from, diedF, s0 = nil, nil, nil, nil
  return H.seqStep({
    H.call(function()
      B = H.fuseWatch(BAY, WRITE); B.on = true; B.pin = { boss = 1000, party = true }; from = H.frame
      s0 = B.slot()
    end),
    H.kitBattle({}, { idle = "defend", care = false, maxFrames = 30000,
      giveUp = function() return lineFrom(B, from) ~= nil and B.litBit() end }),
    H.lazy(function()
      local li, lc = lineFrom(B, from)
      H.assertEq(li ~= nil and B.litBit(), true, "killed: the bay's line came and its fuse is lit")
      B.pin = { party = true }
      WRITE.word(0x3BF4 + B.ent(), 1)    -- (DECLARED: the bay's HP at 1, so one Fight kills it)
      WRITE.byte(0x3E38 + B.ent(), 63)   -- (DECLARED: its gauge held, so the Fight does not break it first)
      local who = firstStanding()
      H.log(string.format("[airforce] killed: the bay lit (line f%d), its HP staged to 1; char %d aims a Fight at it",
        lc.f, who))
      return H.kitBattle({ { who = who, cmd = 0x00, boost = 0, slot = s0 } }, { idle = "defend", care = false,
        maxFrames = 6000, giveUp = function()
          if diedF == nil and (H.readByte(0x3EEC + 2 * s0) & 0x80 ~= 0 or H.readByte(0x3AA8 + 2 * s0) & 1 == 0) then
            diedF = H.frame
          end
          return diedF ~= nil or B.find(0x0C, LAUNCHER, li) ~= nil
        end })
    end),
    -- (the party Defends a while: the turns the bay would have had)
    H.kitBattle({}, { idle = "defend", care = false, maxFrames = 3000,
      giveUp = function() return not H.battleLoadStarted() end }),
    H.call(function()
      local li, lc = lineFrom(B, from)
      local launched = false
      for _, c in ipairs(B.cmds) do if c.arg == LAUNCHER and c.cmd ~= 0x21 and c.f > lc.f then launched = true end end
      local poll = H.readByte(0x7EED46 + 2 * s0)
      H.log(string.format("[airforce] killed: the bay died at f%s, its line at f%d; a Launcher after the line: %s; its "
        .. "OT6_FUSE byte $%02X", tostring(diedF), lc.f, tostring(launched), poll))
      H.assertEq(diedF ~= nil, true, "killed: the Fight killed the bay inside its fuse (the case's precondition)")
      H.assertEq(launched, false, "killed: no Launcher came from a bay that died in its fuse")
      H.assertEq(poll & 0x01, 0, "killed: the lit bit (OT6_FUSE bit 0) of the bay's slot is clear: the \"!\" is gone")
      B.on, B.pin = false, nil
    end),
  })
end

-- The cap: the high case's 6,000 frames, three cases of about 10,000 frames each (the bay is slow: speed 20) and the
-- body and killed cases' about 12,000 each, so 140,000 is about 2x.
H.run({ maxFrames = 140000 }, {
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
  highCase(),
  H.fuseCases({
    tag = "missilebay", species = BAY, write = WRITE,
    line = 0x9E, move = { cmd = 0x0C, atk = LAUNCHER }, turns = 1, glows = 1,
    lineText = "Missiles lock on!{wait}",
    arm = "idle", aim = true,
    bossHp = 1000,
    -- one Missile fired since the case's open (under the gate it arms the fuse), no line
    partway = function(W)
      return W.cells() ~= nil and missilesBetween(W, 0, H.frame + 1) >= 1
    end,
    earned = function(C, W)
      local pre, post = C.brk.pre, C.brk.post
      H.assertEq(pre.mvar & 0x01, 0x01, "missilebay: monster switch 0 stood at the break (armed)")
      H.assertEq(post.mvar & 0x01, 0, "missilebay: monster switch 0 is clear after the cancel")
      local n = missilesBetween(W, C.brk.f, C.lines[2].f)
      H.log(string.format("[airforce] %d Missile(s) between the cancel (f%d) and the second line (f%d)", n, C.brk.f,
        C.lines[2].f))
      H.assertEq(n >= 1, true, "missilebay: another Missile turn came between the cancel and the second line")
    end,
  }),
  bodyCase(),
  killedCase(),
  H.logStep("[airforce] PASS: Missiles only above the gate; under it the Launcher announced, cancelled by the bay's "
    .. "break, not by the body's, and gone with a bay that dies"),
})
