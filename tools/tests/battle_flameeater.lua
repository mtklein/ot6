-- @suite savestate=flameeater_entry slow
-- battle_flameeater.lua -- FlameEater under the boss contract (docs/design/bosses-wob.md block 18, wt/v052-tg-wob3):
-- the fire it drinks is its telegraph, and a break cancels it.
--
-- Its script (ai_script.asm AIScript::_278): it absorbs fire (vanilla), and a fire spell that strikes it now ARMS
-- the fuse (its counter, behind vanilla's hit count and Fire 2: monster switch 2).  "It drinks the fire!" (battle
-- dialogue $9D) and a glow announce it on its next turn, and Fire Ball (attack $B3, command $0C) on the whole party
-- comes on the turn after.  Under the contract (Ot6FuseTbl's row $0116) a break while it is lit cancels it: switch 2
-- goes, and the next fire that strikes it arms it again.  Fire Ball comes only announced: its rotation casts Fire
-- where vanilla could pick it, so the script names Fire Ball once, in the fuse block (asserted from the ROM).
--
-- Boots flameeater_entry (gen_thamasa_fire: the sweep's entry checkpoint in FlameEater's chamber, the party
-- STRAGO, TERRA and LOCKE), walks onto the (46,53) trigger (battle 79) and plays the battle from a snapshot at its
-- open (M.fuseCases, lib/ot6.lua, where the cases and the DECLARED staging are written out: the gauge, the row's
-- classes for the breaking Fight, HP held -- its at 6,000).  The party earns the trigger the way a player does:
-- TERRA casts Fire at it (Magic, aimed at its slot) and the others Defend.
--   unbroken  TERRA's Fire strikes it; the line shows on its next turn; the lit-fuse mark stands before its shield
--             emblem; Fire Ball is dispatched on the turn after, a glow between; the mark goes; the line reads "It
--             drinks the fire!" where the relocated dialogue table points.
--   broken    one member's aimed Fight confirmed once the mark is up breaks it: the cancel fires, the mark goes,
--             switch 2 reads clear, no Fire Ball on its first turns back, and the line returns only after another of
--             TERRA's Fires; Fire Ball follows.
--   outside   a break after its first turn, before any line: nothing is cancelled and the cells stand, two aimed
--             Fights in the window wind nothing, and the fuse then lights and fires as in the first case.
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wob3/mutants/): fuse_never (Ot6FuseCancel+3=80) is red
-- at "the break during the fuse cancels it"; fe_row_keeps (its row keeps switch 2: +5 = $FF) at "monster switch 2 is
-- clear after the cancel"; fe_ball_back (its rotation's second turn picks Fire Ball again) at "Fire Ball comes only
-- announced".  A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/flameeater_entry.mss.lua"

local FLAMEEATER, TERRA, FIRE, FIRE_BALL = 0x116, 0x00, 0x00, 0xB3
local function map() return H.mapId() & 0x3ff end

-- every Fire TERRA dispatches in the battle: { f }
local fires, firesOn = {}, false
local function firesBetween(f0, f1)
  local n = 0
  for _, c in ipairs(fires) do if c.f > f0 and c.f < f1 then n = n + 1 end end
  return n
end

-- the party's play while the fuse arms: TERRA casts Fire at it, one a turn of hers, the others Defend
local function armByFire(pred, max, W)
  local t0 = nil
  return H.lazy(function()
    t0 = H.frame
    local plan = {}
    for k = 1, 8 do plan[k] = { who = TERRA, cmd = 0x02, spell = FIRE, boost = 0, slot = W.slot() } end
    return H.kitBattle(plan, { idle = "defend", care = false, maxFrames = max + 600,
      giveUp = function() return pred() or H.frame - t0 >= max end })
  end)
end

-- The cap: three cases of about 8,000 frames each, so 60,000 is about 2x.
H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(90),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control in FlameEater's chamber"),
  H.call(function()
    H.assertEq(H.readByte(0x1A6E + 54 * TERRA + FIRE), 0xFF, "TERRA knows Fire (her natural magic)")
    -- Fire Ball comes only announced: the script names it once, in the fuse block (the script's first)
    local at = H.aiAttacks(FLAMEEATER, FIRE_BALL)
    H.log(string.format("[flameeater] its turn script names Fire Ball at %d place(s): %s", #at,
      table.concat((function() local t = {}; for _, x in ipairs(at) do t[#t + 1] = string.format("+$%04X", x) end
        return t end)(), " ")))
    H.assertEq(#at, 1, "Fire Ball comes only announced: its turn script names it once (the fuse block)")
    local d = H.sym("_dispatcher")
    emu.addMemoryCallback(function()
      if not firesOn then return end
      local x = emu.getState()["cpu.x"] & 0xFF
      if x < 8 and H.readByte(0xB5) == 0x02 and H.readByte(0xB6) == FIRE then fires[#fires + 1] = { f = H.frame } end
    end, emu.callbackType.exec, d, d)
  end),
  H.fuseEngage(function()
    local ph = 0
    return H.seqStep({
      H.navTo(46, 52, { playBattles = "tactical", maxFrames = 20000 }),
      H.driveUntil(function() return H.battleLoadStarted() end, 8000, {
        H.call(function()
          ph = (ph + 1) % 8
          if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
          H.setPad({ down = true })
        end),
      }, "walk onto (46,53): battle 79"),
    })
  end, FLAMEEATER, "FlameEater"),
  H.call(function()
    H.setPad({})
    local inParty = false
    for i = 0, 3 do if H.readByte(0x3ED8 + 2 * i) == TERRA then inParty = true end end
    H.assertEq(inParty, true, "TERRA is seated in battle 79 (the trigger re-forces STRAGO, TERRA, LOCKE)")
    firesOn = true
  end),
  H.fuseCases({
    tag = "flameeater", species = FLAMEEATER, write = WRITE,
    line = 0x9D, move = { cmd = 0x0C, atk = FIRE_BALL }, turns = 1, glows = 1,
    lineText = "It drinks the fire!{wait}",
    arm = armByFire, aim = true, allTargets = true,
    bossHp = 6000,
    onOpen = function() fires = {} end,
    -- its first turn taken (the Balloons called), no fire struck yet: switch 2 clear
    partway = function(W)
      local c = W.cells()
      return c ~= nil and #W.turns >= 1 and (c.mvar & 0x04) == 0
    end,
    earned = function(C, W)
      local pre, post = C.brk.pre, C.brk.post
      H.assertEq(pre.mvar & 0x04, 0x04, "flameeater: monster switch 2 stood at the break (armed)")
      H.assertEq(post.mvar & 0x04, 0, "flameeater: monster switch 2 is clear after the cancel")
      local n = firesBetween(C.brk.f, C.lines[2].f)
      H.log(string.format("[flameeater] %d of TERRA's Fires between the cancel (f%d) and the second line (f%d)", n,
        C.brk.f, C.lines[2].f))
      H.assertEq(n >= 1, true, "flameeater: a Fire of TERRA's came between the cancel and the second line (the next "
        .. "fire that strikes it arms it again)")
    end,
    outside = function(C, W)
      H.assertEq(firesBetween(0, C.lines[1].f) >= 1, true, "flameeater: the line in the outside case came after a "
        .. "Fire of TERRA's")
    end,
  }),
  H.logStep("[flameeater] PASS: the fire drunk, the announce, the Fire Ball, the cancel and the fire again"),
})
