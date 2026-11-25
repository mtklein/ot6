-- @suite savestate=ultros4_entry slow
-- battle_chupon.lua -- the airship deck under the boss contract (docs/design/bosses-wob.md block 19,
-- wt/v052-tg-wob3): Chupon's temper is the deck's telegraph, and a break cancels it.
--
-- Chupon's script (ai_script.asm AIScript::_303): every blow that strikes him is counted (his counter, battle
-- variable 3); on his first turn with three counted, "It inhales!" (battle dialogue $94, Ifrit's line) and a glow
-- announce it, and Fire Ball (attack $B3, command $0C) on the whole party comes on his next turn.  The count is the
-- fuse block's own condition.  Under the contract (Ot6FuseTbl's row $012F, OT6_FUSE_VAR3) a break while it is lit
-- cancels it and clears the count: three more blows earn it again.  Blows on a Broken Chupon count nothing.  Fire
-- Ball comes only announced (his script names it once, in the fuse block: asserted from the ROM).  His dying
-- Sneeze, which ends the battle, is vanilla's and is not played here; Ultros announces nothing on the deck.
--
-- Boots ultros4_entry (gen_fc_landing: the deck at the Ultros teaser), walks to the deck's right edge to arm Ultros
-- IV (battle_ultros4's walk), brings Chupon in -- Ultros's HP staged to 12,900 (DECLARED) and one member's Fight
-- takes him under his story line, 12,800, so that his counter calls Chupon down -- and plays Chupon's battle from a
-- snapshot once he stands (M.fuseCases, lib/ot6.lua, where the cases and the DECLARED staging are written out: the
-- gauge, the row's classes for the breaking Fight, HP held -- Chupon's at 5,000).  The party earns the trigger the
-- way a player does: its Fights strike Chupon (aimed at his slot).
--   unbroken  three blows counted; the line shows on his next turn; the lit-fuse mark stands; Fire Ball is
--             dispatched on his turn after, a glow between; the mark goes.
--   broken    an aimed Fight confirmed once the mark is up breaks him: the cancel fires, the mark goes, battle
--             variable 3 reads 0, no Fire Ball on his first turns back, and the line returns only after three more
--             blows are counted; Fire Ball follows.
--   outside   a break with one or two blows counted, before any line: nothing is cancelled and the cells (the count
--             among them) stand, two aimed Fights in the window count nothing, and the fuse then lights and fires.
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wob3/mutants/): fuse_never (Ot6FuseCancel+3=80) is red
-- at "the break during the fuse cancels it"; chupon_no_var3 (his row's flags byte 0) at "battle variable 3, his
-- count, is 0 after the cancel"; chupon_ball_back (his rotation's second turn picks Fire Ball again) at "Fire Ball
-- comes only announced".  A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them; the suite stages
-- Ultros's HP once through the same pair; nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/ultros4_entry.mss.lua"

local ULTROS4, CHUPON, FIRE_BALL, LINE = 0x168, 0x12F, 0xB3, 12800
local function map() return H.mapId() & 0x3ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function slotOf(sp)
  for s = 0, 5 do
    if H.readByte(0x3AA8 + s * 2) & 1 == 1 and H.readWord(0x57C0 + s * 2) == sp then return s end
  end
  return nil
end

-- battle variable 3, his count, frame by frame while on: each rise is a blow counted
local count, countOn = {}, false
local function risesBetween(f0, f1)
  local n = 0
  for k = 2, #count do
    if count[k].f > f0 and count[k].f < f1 and count[k].v == count[k - 1].v + 1 then n = n + 1 end
  end
  return n
end

-- the party's play while the fuse arms: every member Fights Chupon (the library holds his gauge meanwhile)
local function armByBlows(pred, max, W)
  local t0 = nil
  return H.lazy(function()
    t0 = H.frame
    local plan = {}
    for k = 1, 8 do
      for i = 0, 3 do
        local id = H.readByte(0x3ED8 + 2 * i)
        if id ~= 0xFF then plan[#plan + 1] = { who = id, cmd = 0x00, boost = 0, slot = W.slot() } end
      end
    end
    return H.kitBattle(plan, { idle = "defend", care = false, maxFrames = max + 600,
      giveUp = function() return pred() or H.frame - t0 >= max end })
  end)
end

-- The cap: Chupon's arrival is about 3,000 frames, and three cases of about 10,000 each follow (he is slow: speed
-- 10), so 90,000 is about 2x.
H.run({ maxFrames = 90000 }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 10, "booted on the Blackjack's deck (map 10)")
    H.assertEq(sw(0x01F0), 1, "the Ultros teaser is up ($01F0)")
    local at = H.aiAttacks(CHUPON, FIRE_BALL)
    H.log(string.format("[chupon] his turn script names Fire Ball at %d place(s)", #at))
    H.assertEq(#at, 1, "Fire Ball comes only announced: Chupon's turn script names it once (the fuse block)")
    emu.addEventCallback(function()
      if not countOn then return end
      local v = H.readByte(0x3EB3)
      local r = count[#count]
      if r == nil or r.v ~= v then count[#count + 1] = { f = H.frame, v = v } end
    end, emu.eventType.endFrame)
  end),
  H.fuseEngage(function()
    return H.seqStep({
      H.navTo(22, 6, { maxFrames = 6000, arrive = function() return not H.hasControl() or H.fieldX() == 22 end }),
      H.driveUntil(function() return H.battleLoadStarted() end, 6000,
        { H.call(function() H.setPad(H.frame % 8 < 4 and { "a" } or {}) end) }, "Ultros IV's battle is loading"),
    })
  end, ULTROS4, "Ultros IV"),
  H.waitUntil(function() return H.battleActive() end, 3000, "Ultros IV's battle is up", 2),
  -- Chupon's arrival: Ultros's HP staged just above his story line, and one member's Fight takes him under it
  H.call(function()
    local s = slotOf(ULTROS4)
    H.assertEq(s ~= nil, true, "Ultros IV stands")
    WRITE.word(0x3BF4 + 8 + 2 * s, LINE + 100)   -- (DECLARED: Ultros's HP, once, just above his story line)
    H.log(string.format("[chupon] Ultros IV's HP staged to %d (slot %d)", LINE + 100, s))
  end),
  H.lazy(function()
    local s, plan = slotOf(ULTROS4), {}
    for k = 1, 6 do
      for i = 0, 3 do
        local id = H.readByte(0x3ED8 + 2 * i)
        if id ~= 0xFF then plan[#plan + 1] = { who = id, cmd = 0x00, boost = 0, slot = s } end
      end
    end
    return H.kitBattle(plan, { idle = "defend", care = true, maxFrames = 12000,
      giveUp = function() return slotOf(CHUPON) ~= nil or not H.battleLoadStarted() end })
  end),
  H.kitBattle({}, { idle = "defend", care = true, maxFrames = 3000,
    giveUp = function() return slotOf(CHUPON) ~= nil and H.battleActive() and not H.dialogWaiting() end }),
  H.call(function()
    H.assertEq(slotOf(CHUPON) ~= nil, true, "Chupon came down (Ultros's counter under 12,800 HP)")
    H.log(string.format("[chupon] f%d Chupon stands in slot %d; his count reads %d", H.frame, slotOf(CHUPON),
      H.readByte(0x3EB3)))
    countOn = true
  end),
  H.fuseCases({
    tag = "chupon", species = CHUPON, write = WRITE,
    line = 0x94, move = { cmd = 0x0C, atk = FIRE_BALL }, turns = 1, glows = 1,
    lineText = "It inhales!{wait}",
    arm = armByBlows, aim = true, allTargets = true,
    bossHp = 5000,
    -- one or two blows counted, no line
    partway = function(W)
      local v = H.readByte(0x3EB3)
      return W.cells() ~= nil and v >= 1 and v <= 2
    end,
    earned = function(C, W)
      local pre, post = C.brk.pre, C.brk.post
      H.assertEq(pre.bvar3 >= 3, true, string.format("chupon: three blows were counted at the break (%d)", pre.bvar3))
      H.assertEq(post.bvar3, 0, "chupon: battle variable 3, his count, is 0 after the cancel")
      local n = risesBetween(C.brk.f, C.lines[2].f)
      H.log(string.format("[chupon] %d blow(s) counted between the cancel (f%d) and the second line (f%d)", n, C.brk.f,
        C.lines[2].f))
      H.assertEq(n >= 3, true, "chupon: three blows were counted afresh between the cancel and the second line")
    end,
  }),
  H.logStep("[chupon] PASS: his temper counted, the announce, the Fire Ball, the cancel and the count again"),
})
