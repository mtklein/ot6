-- @suite savestate=minecart_entry slow
-- battle_number128.lua -- Number 128 under the boss contract (docs/design/bosses-wob.md block 15,
-- wt/v052-tg-wob2): Atomic Ray is his telegraph, the blades its trigger, and a break cancels it.
--
-- His script (ai_script.asm AIScript::_267): alone (both blades down) he Hastes himself once and runs his sweep,
-- whose first turn (A: Battle, Gale Cut or Atomic Ray) now also ARMS the fuse (monster switch 1).  On his next turn
-- "Its core heats!" (battle dialogue $97) and a glow announce it, and Atomic Ray (attack $B4, command $0C) on every
-- standing member comes on the turn after, whether or not a blade has grown back.  Turn B follows the ray on his
-- next turn alone.  Under the contract (Ot6FuseTbl's row $010B) a break while it is lit cancels it: the script waits
-- nowhere, switch 1 is clear, and the sweep starts over from turn A, alone.
--
-- Boots minecart_entry (gen_minecart_entry: beside CID on the minecart platform), takes the ride, fights the
-- Roaders out through the menu (everyone Fights) until the ride deals him, and plays his battle from a snapshot at
-- its open (M.fuseCases, lib/ot6.lua, where the cases and the DECLARED staging are written out: the gauge, the
-- row's classes for the breaking Fight, HP held -- his at 2,500).  The party earns the trigger as a player does:
-- it Fights the blades down (the right blade first, then the left), and Defends once both are down.
--   unbroken  the blades fall; his first alone turns are his Haste and turn A; the line shows on the turn after;
--             the lit-fuse mark stands; Atomic Ray is dispatched on his next turn, on every standing member, a glow
--             between; the mark goes.
--   broken    an aimed Fight confirmed once the mark is up breaks him: the cancel fires, the mark goes, switch 1
--             reads clear, no ray on his first turns back, and the line returns only after a turn A of his taken
--             alone (two or more of his turns back); the ray follows.
--   outside   a break after his first turn, before any line: nothing is cancelled and the cells stand, two aimed
--             Fights in the window wind nothing, and the fuse then lights and fires as in the first case.
-- Mutants (build/attempts/wt/v052-tg-wob2/mutants/): fuse_never (Ot6FuseCancel+3=80) is red at "the break during
-- the fuse cancels it"; n128_no_clear (his row keeps every monster bit) at "monster switch 1 is clear after the
-- cancel".  A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/minecart_entry.mss.lua"

local N128, RBLADE, LBLADE = 0x10B, 0x13F, 0x140
local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function present(sp)
  for s = 0, 5 do
    if H.readByte(0x3AA8 + s * 2) & 1 == 1 and H.readWord(0x57C0 + s * 2) == sp then return s end
  end
  return nil
end
local function alone() return present(RBLADE) == nil and present(LBLADE) == nil end

-- each turn of his: { f, alone }
local turns, turnsOn = {}, false

-- the party's play while the fuse arms: the blades Fought down (each member's Fight aimed at a standing blade, the
-- right one first), then Defends
local function armByBlades(pred, max, W)
  local t0 = nil
  return H.lazy(function()
    t0 = H.frame
    local seats = {}
    for i = 0, 3 do
      local id = H.readByte(0x3ED8 + 2 * i)
      if id ~= 0xFF then seats[#seats + 1] = id end
    end
    local plan = {}
    local rs, ls = present(RBLADE), present(LBLADE)
    for k = 1, 18 do
      local s = (k <= 6 and rs) or ls or rs
      if s ~= nil then plan[#plan + 1] = { who = seats[(k - 1) % #seats + 1], cmd = 0x00, boost = 0, slot = s } end
    end
    return H.kitBattle(plan, { idle = "defend", care = false, maxFrames = max + 600,
      giveUp = function() return pred() or H.frame - t0 >= max end })
  end)
end

-- the ride, battle by battle, until it deals him
local function ride(k)
  return H.seqStep({
    H.driveUntil(function() return H.battleLoadStarted() and H.monstersPresent() > 0 end, 20000, {
      H.call(function()
        local ph = H.frame % 8
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, string.format("the ride deals battle %d", k)),
    H.call(function() H.setPad({}) end),
    H.waitUntil(function() return H.battleActive() end, 3000, "the battle is up", 2),
    H.lazy(function()
      local w = H.formationWords()
      H.log(string.format("[number128] ride battle %d at f%d: formation %04X %04X %04X %04X %04X %04X", k, H.frame,
        w[1], w[2], w[3], w[4], w[5], w[6]))
      if w[1] == N128 then return H.waitFrames(1) end
      H.assertEq(k < 6, true, "the ride deals Number 128 within six battles (gen_n128: the sixth)")
      return H.seqStep({
        H.kitBattle({}, { care = true, maxFrames = 20000 }),
        H.waitUntil(function() return not H.battleLoadStarted() end, 3000, "the Roaders' battle ends", 2),
        ride(k + 1),
      })
    end),
  })
end

-- The cap: the ride to him is about 26,000 frames (gen_n128) and three cases of about 10,000 each follow, so
-- 120,000 is about 2x.
H.run({ maxFrames = 120000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control beside CID"),
  H.call(function() H.assertEq(map(), 272, "minecart_entry stands on map 272, the minecart platform") end),
  (function()
    local ph = 0
    return H.driveUntil(function() return sw(0x02BC) == 1 end, 20000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() or not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad(ph < 4 and { "a", "up" } or { "up" }) end
      end),
    }, "A into CID -> $02BC: the ride begins")
  end)(),
  ride(1),
  H.call(function()
    H.assertEq(present(N128), 0, "Number 128 stands in slot 0")
    H.assertEq(present(RBLADE) ~= nil and present(LBLADE) ~= nil, true, "both blades stand at the open")
    local ex = H.sym("ExecMonsterAction")
    emu.addMemoryCallback(function()
      if not turnsOn then return end
      local s = present(N128)
      if s and (emu.getState()["cpu.x"] & 0xFF) == 8 + 2 * s then turns[#turns + 1] = { f = H.frame, alone = alone() } end
    end, emu.callbackType.exec, ex, ex)
    turnsOn = true
  end),
  H.fuseCases({
    tag = "number128", species = N128, write = WRITE,
    line = 0x97, move = { cmd = 0x0C, atk = 0xB4 }, turns = 1, glows = 1,
    arm = armByBlades, aim = true, allTargets = true,
    bossHp = 2500,
    onOpen = function() turns = {} end,
    partway = function(W)
      local c = W.cells()
      return c ~= nil and #W.turns >= 1 and (c.mvar & 0x02) == 0
    end,
    earned = function(C, W)
      local post, l2 = C.brk.post, C.lines[2]
      H.assertEq(post.mvar & 0x02, 0, "number128: monster switch 1 is clear after the cancel")
      local back = l2.turn - C.rec.turn
      H.assertEq(back >= 2, true, string.format("number128: the line returned on his turn %d back, after a turn A "
        .. "(two or more)", back))
      local n = 0
      for _, t in ipairs(turns) do if t.f > C.brk.f and t.f < l2.f and t.alone then n = n + 1 end end
      H.assertEq(n >= 1, true, string.format("number128: he took a turn alone between the cancel and the second line "
        .. "(%d)", n))
    end,
  }),
  H.logStep("[number128] PASS: the blades, the announce, the ray, the cancel and the sweep earned again"),
})
