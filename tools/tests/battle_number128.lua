-- @suite savestate=minecart_entry slow
-- battle_number128.lua -- Number 128 under the boss contract (docs/design/bosses-wob.md block 15,
-- wt/v052-tg-wob2): Atomic Ray is his telegraph, a falling blade its trigger, and a break cancels it.
--
-- His script (ai_script.asm AIScript::_267, and the blades' _319 and _320): each blade's death now sets battle
-- switch 0; on the body's next turn "Its core heats!" (battle dialogue $97) and a glow announce the ray, and Atomic
-- Ray (attack $B4, command $0C) on every standing member comes on the turn after, whatever the blades do meanwhile.
-- Under the contract (Ot6FuseTbl's row $010B) a break while it is lit cancels it: the script waits nowhere, the
-- switch is clear, and another blade has to fall.
--
-- Boots minecart_entry (gen_minecart_entry: beside CID on the minecart platform), takes the ride, fights the
-- Roaders out through the menu (everyone Fights) until the ride deals him, and plays his battle from a snapshot at
-- its open (M.fuseCases, lib/ot6.lua, where the cases and the DECLARED staging are written out: the gauge, the
-- row's classes for the breaking Fight, HP held -- his at 2,500).  The party earns the trigger as a player does:
-- its Fights are aimed at a standing blade (the right one, 400 HP, first) until one falls, and it Defends after.
--   unbroken  a blade falls; the line shows on his next turn; the lit-fuse mark stands; Atomic Ray is dispatched
--             on his next turn, on every standing member, a glow between; the mark goes.
--   broken    an aimed Fight confirmed once the mark is up breaks him: the cancel fires, the mark goes, battle
--             switch 0 reads clear, no ray on his first turns back, and the line returns only after another blade
--             has fallen; the ray follows.
--   outside   a break after his first turn, before any blade has fallen: nothing is cancelled and the cells stand,
--             two aimed Fights in the window wind nothing, and the fuse then lights and fires as in the first case.
-- Mutants (build/attempts/wt/v052-tg-wob2/mutants/): fuse_never (Ot6FuseCancel+3=80) is red at "the break during
-- the fuse cancels it"; n128_no_clear (his row keeps every battle switch) at "battle switch 0 is clear after the
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
local function bladesUp()
  local n = 0
  if present(RBLADE) then n = n + 1 end
  if present(LBLADE) then n = n + 1 end
  return n
end

-- each blade's fall, as the frame it left the field: { f }
local falls, fallsOn, lastUp = {}, false, nil

-- the party's play while the fuse arms: Fights aimed at a standing blade (the right one first) until pred(), then
-- Defends
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
    for k = 1, 24 do
      plan[#plan + 1] = { who = seats[(k - 1) % #seats + 1], cmd = 0x00, boost = 0,
        slot = present(RBLADE) or present(LBLADE) or 0,
        slotFn = function() return present(RBLADE) or present(LBLADE) end }
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
    emu.addEventCallback(function()
      if not fallsOn then return end
      local up = bladesUp()
      if lastUp ~= nil and up < lastUp then
        falls[#falls + 1] = { f = H.frame }
        H.log(string.format("[number128] f%d a blade falls (%d standing)", H.frame, up))
      end
      lastUp = up
    end, emu.eventType.endFrame)
    fallsOn = true
  end),
  H.fuseCases({
    tag = "number128", species = N128, write = WRITE,
    line = 0x97, move = { cmd = 0x0C, atk = 0xB4 }, turns = 1, glows = 1,
    arm = armByBlades, aim = true, allTargets = true,
    bossHp = 2500,
    onOpen = function() falls, lastUp = {}, nil end,
    -- his first turn taken, both blades standing, nothing armed
    partway = function(W)
      local c = W.cells()
      return c ~= nil and #W.turns >= 1 and (c.bsw & 0x01) == 0 and bladesUp() == 2
    end,
    earned = function(C, W)
      local pre, post, l2 = C.brk.pre, C.brk.post, C.lines[2]
      H.assertEq(pre.bsw & 0x01, 1, "number128: battle switch 0 stood at the break (a blade had fallen)")
      H.assertEq(post.bsw & 0x01, 0, "number128: battle switch 0 is clear after the cancel")
      local n = 0
      for _, f in ipairs(falls) do if f.f > C.brk.f and f.f < l2.f then n = n + 1 end end
      H.assertEq(n >= 1, true, string.format("number128: another blade fell between the cancel and the second line "
        .. "(%d)", n))
    end,
  }),
  H.logStep("[number128] PASS: the blades, the announce, the ray, the cancel and the sweep earned again"),
})
