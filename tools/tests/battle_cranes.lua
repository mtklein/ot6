-- @suite savestate=n128_won slow
-- battle_cranes.lua -- the Left and Right Cranes under the boss contract (docs/design/bosses-wob.md block 16,
-- wt/v052-tg-wob2): each Crane's quake is its telegraph, on its own clock, and a break cancels it.
--
-- The scripts (ai_script.asm AIScript::_269 the left Crane $010D, _270 the right $010E): vanilla quaked
-- (Magnitude8, "The crane shook the deck!") on whichever Crane's turn came once the battle timer reached 60.  Now
-- each Crane's own timer arms it, the left's at 60 and the right's at 90, on one of its ordinary turns (monster
-- switch 1); "Deck groans!" (battle dialogue $9C) and a glow announce it on its next turn, and the quake (attack
-- $BC, command $0C) follows on the turn after.  Under the contract (Ot6FuseTbl's rows $010D and $010E, OT6_FUSE_TIMER) a break while one is lit cancels
-- that Crane's quake: the script waits nowhere, switch 1 is clear, its clock restarts, and the other Crane's clock
-- runs on.
--
-- Boots n128_won (gen_n128: the escape map's save point), walks gen_terra_returned_checkpoint's way onto the
-- reunion trigger and the Blackjack's deck, opens the Cranes' battle and plays each Crane's three cases from a
-- snapshot (the left Crane's at the open, the right Crane's after them) (M.fuseCases, lib/ot6.lua, where the cases
-- and the DECLARED staging are written out: the gauge, the row's classes for the breaking Fight, HP held -- each
-- Crane's at 1,500):
--   unbroken  the party Defends; the line shows on the turn after the Crane's clock arms it; the lit-fuse mark
--             stands before its shield emblem; Magnitude8 is dispatched on its next turn, a glow between; the mark
--             goes.
--   broken    an aimed Fight confirmed once the mark is up breaks it: the cancel fires, the mark goes, switch 1 is
--             clear and its timer reads 0 after it, no quake on its first turns back, and the line returns only once
--             its clock has run again; the quake follows.
--   outside   a break after its first turn, before any line: nothing is cancelled and the cells stand, two aimed
--             Fights in the window wind nothing, and the fuse then lights and fires as in the first case.
-- Mutants (build/attempts/wt/v052-tg-wob2/mutants/): fuse_never (Ot6FuseCancel+3=80) is red at "the break during
-- the fuse cancels it"; crane_no_clock (the left Crane's row's flags byte 0) at "the left Crane's timer reads 0
-- after the cancel".  A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/n128_won.mss.lua"

local LEFT, RIGHT = 0x10D, 0x10E
local function map() return H.mapId() & 0x1ff end
local function present(sp)
  for s = 0, 5 do
    if H.readByte(0x3AA8 + s * 2) & 1 == 1 and H.readWord(0x57C0 + s * 2) == sp then return true end
  end
  return false
end

local function cases(tag, name, species, clock)
  return H.fuseCases({
    tag = tag, species = species, write = WRITE,
    line = 0x9C, move = { cmd = 0x0C, atk = 0xBC }, turns = 1, glows = 1,
    arm = "idle", aim = true,
    bossHp = 1500,
    partway = function(W)
      local c = W.cells()
      return c ~= nil and #W.turns >= 1 and (c.mvar & 0x02) == 0
    end,
    earned = function(C, W)
      local pre, post, l2 = C.brk.pre, C.brk.post, C.lines[2]
      H.assertEq(pre.mvar & 0x02 ~= 0, true, string.format("%s: monster switch 1 stood at the break (armed)", name))
      H.assertEq(post.mvar & 0x02, 0, string.format("%s: monster switch 1 is clear after the cancel", name))
      H.assertEq(post.timer < 4, true, string.format("%s's timer reads 0 after the cancel (%d): its clock restarts",
        name, post.timer))
      H.assertEq(l2.cells.timer >= 2 * clock, true, string.format("%s: the second line came once its clock had run "
        .. "again (its timer %d at the line, %d its arming)", name, l2.cells.timer, 2 * clock))
    end,
  })
end

-- the deck's scene, battle by battle, until it opens the Cranes' (a random battle on the way is fought out)
local function deck(k)
  return H.seqStep({
    H.driveUntil(function() return H.battleLoadStarted() and H.monstersPresent() > 0 end, 40000, {
      H.call(function() H.setPad(H.frame % 8 < 4 and { "a" } or {}) end),
    }, "the deck's scene opens a battle"),
    H.call(function() H.setPad({}) end),
    H.waitUntil(function() return H.battleActive() end, 3000, "the battle is up", 2),
    H.lazy(function()
      if present(LEFT) then return H.waitFrames(1) end
      H.assertEq(k < 4, true, "the deck's scene opens the Cranes' battle within four battles")
      H.log(string.format("[cranes] f%d a battle before the Cranes': fought out", H.frame))
      return H.seqStep({
        H.kitBattle({}, { care = true, maxFrames = 20000 }),
        H.waitUntil(function() return not H.battleLoadStarted() end, 3000, "that battle ends", 2),
        deck(k + 1),
      })
    end),
  })
end

-- The cap: the walk to the deck is about 12,000 frames (gen_terra_returned_checkpoint) and six cases of about
-- 10,000 each follow, so 150,000 is about 2x.
H.run({ maxFrames = 150000 }, {
  H.loadState(STATE),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 240, "booted on the escape map (n128_won)")
  end),
  -- (the line's own kit for the Cranes, gen_terra_returned_checkpoint's: the Cranes absorb bolt and fire, so LOCKE's
  -- ThunderBlade leaves his right hand for a plain dagger, whichever the bag holds; the harness's absorb guard fails
  -- a fight entered with a weapon the formation absorbs)
  H.cond(function() return H.invSlotOf(0x00) ~= nil end,
    { H.equipWeapon(2, 0x00, { tag = "LOCKE R-hand Dirk (no element)" }) }, {}),
  H.cond(function() return H.invSlotOf(0x01) ~= nil end,
    { H.equipWeapon(2, 0x01, { tag = "LOCKE R-hand MithrilKnife" }) }, {}),
  H.cond(function() return H.invSlotOf(0x04) ~= nil end,
    { H.equipWeapon(2, 0x04, { tag = "LOCKE R-hand ThiefKnife" }) }, {}),
  H.call(function()
    H.assertEq(H.readByte(0x1600 + 37 * 1 + 0x1F) ~= 0x0F, true,
      "LOCKE's right hand is no longer the ThunderBlade (the Cranes absorb bolt)")
  end),
  H.navTo(54, 40, { playBattles = "tactical", maxFrames = 25000 }),
  (function()
    local ph = 0
    local F = H.newWalkFighter("onto the reunion trigger")
    return H.driveUntil(function() return map() == 6 end, 9000, {
      H.call(function()
        ph = (ph + 1) % 8
        if F.frame() then return end
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({ left = true })
      end),
    }, "held LEFT onto the reunion trigger -> the Blackjack deck")
  end)(),
  H.release(),
  deck(1),
  H.call(function()
    H.assertEq(present(LEFT) and present(RIGHT), true, "both Cranes stand at the open")
  end),
  cases("crane_left", "the left Crane", LEFT, 60),
  -- (the right Crane's cases open on a snapshot of their own, taken with its quake neither armed nor lit: the party
  -- Defends, with care, until its armed switch is clear)
  H.lazy(function()
    local function armed()
      for sl = 0, 5 do
        if H.readByte(0x3AA8 + sl * 2) & 1 == 1 and H.readWord(0x57C0 + sl * 2) == RIGHT then
          return H.readByte(0x3DAC + 8 + 2 * sl) & 0x02 ~= 0
        end
      end
      return false
    end
    return H.kitBattle({}, { idle = "defend", care = true, maxFrames = 20000,
      giveUp = function() return not armed() or not H.battleLoadStarted() end })
  end),
  H.call(function()
    H.assertEq(present(RIGHT), true, "the right Crane still stands for its cases")
  end),
  cases("crane_right", "the right Crane", RIGHT, 90),
  H.logStep("[cranes] PASS: each Crane's quake announced on its own clock, cancelled by a break and earned again"),
})
