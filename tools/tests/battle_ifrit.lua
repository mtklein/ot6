-- @suite savestate=ifrit_entry slow
-- battle_ifrit.lua -- Ifrit and Shiva under the boss contract (docs/design/bosses-wob.md block 13,
-- wt/v052-tg-wob2): each sibling's spell on the party is its telegraph, and a break cancels it.
--
-- The scripts (ai_script.asm AIScript::_265 Ifrit, _264 Shiva): each sibling's two-turn rotation is vanilla's, and
-- its second turn now also ARMS the fuse (Ifrit battle switch 0, Shiva battle switch 1: a monster variable here is
-- the counter's tally of spells, so the switch lives in battle variable 0, which nothing else in this fight
-- touches).  "It inhales!" (battle dialogue $94) and a glow announce it on the sibling's next turn, and the spell
-- -- Fire 2 (attack $05) from Ifrit, Ice 2 ($06) from Shiva, command $02 -- on every standing member follows on
-- the turn after.  Under the contract (Ot6FuseTbl's rows $0109 and $0108) a break while it is lit cancels it: the
-- script waits nowhere, the switch is clear, and the rotation's two turns earn it again.  The fuse block is each
-- script's first, so the swap (six hits) and the Fire 3 / Rflect blocks wait until the spell has fired.
--
-- Boots ifrit_entry (gen_ifrit_entry: the alcove, one A press from battle 70), opens the battle with Ifrit on the
-- field and plays his cases from a snapshot at its open (M.fuseCases, lib/ot6.lua, where the cases and the DECLARED
-- staging are written out: the gauge, the row's classes for the breaking Fight, HP held -- his at 3,000):
--   unbroken  the party Defends; the line shows on the turn after his rotation's second; the lit-fuse mark stands;
--             Fire 2 is dispatched on his next turn, on every standing member, a glow between; the mark goes.
--   broken    an aimed Fight confirmed once the mark is up breaks him: the cancel fires, the mark goes, battle
--             switch 0 reads clear, no Fire 2 on his first turns back, and the line returns only after his
--             rotation's two turns again; Fire 2 follows.
--   outside   a break after his rotation's first turn, before any line: nothing is cancelled and the cells stand,
--             two aimed Fights in the window wind nothing, and the fuse then lights and fires as in the first case.
-- Then the party brings Shiva in the way the fight does (EDGAR Fights Ifrit, the others Defend, until his tally of
-- hits swaps her in) and plays her three cases from a snapshot there, the same with Ice 2 and battle switch 1.
-- Mutants (build/attempts/wt/v052-tg-wob2/mutants/): fuse_never (Ot6FuseCancel+3=80) is red at "the break during
-- the fuse cancels it"; ifrit_no_clear (Ifrit's row keeps every battle switch) at "battle switch 0 is clear after
-- the cancel".  A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/ifrit_entry.mss.lua"

local IFRIT, SHIVA, EDGAR = 0x109, 0x108, 0x04
local function map() return H.mapId() & 0x1ff end
local function present(sp)
  for s = 0, 5 do
    if H.readByte(0x3AA8 + s * 2) & 1 == 1 and H.readWord(0x57C0 + s * 2) == sp then return true end
  end
  return false
end

-- one sibling's cases: its own switch bit in battle variable 0
local function cases(tag, species, bit, atk)
  return H.fuseCases({
    tag = tag, species = species, write = WRITE,
    line = 0x94, move = { cmd = 0x02, atk = atk }, turns = 1, glows = 1,
    arm = "idle", aim = true, allTargets = true,
    bossHp = 2800,
    -- its rotation's first turn taken, no fuse armed yet
    partway = function(W)
      local c = W.cells()
      return c ~= nil and #W.turns >= 1 and (c.bsw & bit) == 0 and c.blk ~= 0xFF
    end,
    earned = function(C, W)
      local pre, post, l2 = C.brk.pre, C.brk.post, C.lines[2]
      H.assertEq(pre.bsw & bit ~= 0, true, string.format("%s: its battle switch stood at the break (the fuse was "
        .. "armed)", tag))
      H.assertEq(post.bsw & bit, 0, string.format("%s: battle switch %d is clear after the cancel", tag,
        bit == 1 and 0 or 1))
      local back = l2.turn - C.rec.turn
      H.assertEq(back >= 3, true, string.format("%s: the trigger was earned again in full: the line returned on its "
        .. "turn %d back, after the rotation's two turns", tag, back))
    end,
  })
end

-- The cap: six cases of about 8,000 frames each and the swap between, so 120,000 is about 2x.
H.run({ maxFrames = 120000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(60),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control in the alcove"),
  H.fuseEngage(function()
    H.assertEq(map(), 264, "ifrit_entry stands on map 264, the Ifrit/Shiva alcove")
    return H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
      H.pressButtons({ "a" }, 4), H.waitFrames(6),
    }, "one A press -> battle 70")
  end, IFRIT, "Ifrit"),
  H.call(function()
    local edgar = false
    for i = 0, 3 do if H.readByte(0x3ED8 + 2 * i) == EDGAR then edgar = true end end
    H.assertEq(edgar, true, "EDGAR is seated in battle 70 (the factory party: his Fight brings Shiva in)")
    H.assertEq(present(IFRIT) and not present(SHIVA), true, "battle 70 opens with Ifrit on the field, Shiva away")
  end),
  cases("ifrit", IFRIT, 0x01, 0x05),
  -- Shiva in: EDGAR's Fights on Ifrit, the others Defending, until his tally of hits swaps her in
  H.lazy(function()
    local plan = {}
    for k = 1, 12 do plan[k] = { who = EDGAR, cmd = 0x00, boost = 0 } end
    return H.kitBattle(plan, { idle = "defend", care = true, maxFrames = 30000,
      giveUp = function() return present(SHIVA) or not H.battleLoadStarted() end })
  end),
  H.waitUntil(function() return present(SHIVA) end, 3000, "Shiva swapped in", 2),
  H.call(function() H.log(string.format("[ifrit] f%d Shiva is on the field", H.frame)) end),
  cases("shiva", SHIVA, 0x02, 0x06),
  H.logStep("[ifrit] PASS: both siblings announce, fire, are cancelled by a break and earn it again"),
})
