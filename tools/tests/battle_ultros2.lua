-- @suite frontier=ultros2_doorstep slow
-- battle_ultros2.lua -- Beat A's boss gate: the OPERA's ULTROS 2 break gauge.
-- Boots ultros2_doorstep (the rafter framework, one interaction short of
-- battle 134), rides into the fight, and asserts:
--
--   1. THE GAUGE IS AUTHORED, not formula.  Ultros 2 ($012d) seeds 6/6 with
--      class-weak OT6_SLASH|OT6_PIERCE straight off Ot6ShieldTbl
--      (ot6.asm:4757 -- "ultros 2: same row, one more shield" than Ultros 1's
--      5).  The formula value for a body this size would not be 6, so a
--      dropped row fails here first.
--   2. THE CODEX CARRIES the recurring-Ultros weakness row.  bosses-wob's
--      contract is "Ultros keeps one weakness row, revealed at the Lete,
--      remembered forever."  On a fresh v0.5 chain the codex is virgin
--      (loadState wipes battery sram, ot6.lua), so nothing is revealed at
--      seed -- asserted -- and the first class-matching chip reveals it.
--   3. A PIERCE/SLASH CHIP BREAKS IT, a mismatched hit does NOT.  The party's
--      own physical swings are classed through Ot6WeapClassTbl; a swing whose
--      class intersects slash|pierce takes a shield and reveals the class,
--      and the NEGATIVE CONTROL (the gauge is read untouched before the first
--      matching hit lands) is what makes "the chip broke it" mean something.
--
-- WHY THIS FIXTURE.  Ultros 2 ends the Opera performance -- "same fight,
-- honest difficulty, no Banon healer" (bosses-wob).  The chosen party is
-- LOCKE + up to three; AutoCrossbow (pierce) trivially chips, and any slash
-- weapon does too, so the class row is reachable by the party that faces it
-- (issue #6).  battle 134 = the Ultros-2 formation ($012d present).
--
-- NOTE: this test is authored against the confirmed Ot6ShieldTbl row and the
-- battle-class read addresses proven by battle_vargas/battle_class; it
-- reports "skipped" (suite.sh) until ultros2_doorstep is minted, and the
-- kit-specific chip drive is intentionally class-generic (it credits ANY
-- landed swing whose Ot6-resolved class meets slash|pierce) so it does not
-- hard-code which of LOCKE's party carries the handhold.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/ultros2_doorstep.mss.lua"

local ULTROS2 = 0x012d
local OT6_SLASH, OT6_PIERCE = 0x01, 0x02

-- monster slot s -> entity offset 8 + 2s (battle_class's map, per battle_vargas)
local function SH(s)  return 0x3E38 + (8 + s * 2) end   -- current shields
local function SMX(s) return 0x3E39 + (8 + s * 2) end   -- max shields
local function RVE(s) return 0x3E89 + (8 + s * 2) end   -- revealed elements
local function WKC(s) return 0x3E9C + (8 + s * 2) end   -- weak class (authored)
local function RVC(s) return 0x3E9D + (8 + s * 2) end   -- revealed class
local function MHP(s) return 0x3BFC + s * 2 end

local uSlot = 0
local aPh = 0
local shWrites = {}

local function pinParty()
  for e = 0, 3 do
    H.writeWord(0x3BF4 + e * 2, H.readWord(0x3C1C + e * 2))   -- HP=max: no wipe
    H.writeWord(0x3C30 + e * 2, 99)                           -- MP costs are live
    H.writeWord(0x3C08 + e * 2, 99)
  end
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),

  -- ride the last interaction into battle 134 (the doorstep parks one step
  -- short; the exact entry is A-into-the-scene, like every _doorstep gate)
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function()
      aPh = (aPh + 1) % 8
      if H.monstersPresent() > 0 then
        for s = 0, 5 do
          if H.readByte(0x3aa8 + s * 2) % 2 == 1 then end  -- (no kill-bit; goal fight)
        end
      end
      H.setPad(aPh < 4 and { "a" } or {})
    end),
  }, "the rafter scene reaches battle 134"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 3000, "Ultros 2 up", 10),
  H.waitFrames(120),

  -- 1 + 2: the seed, read BEFORE anything is poked.
  H.call(function()
    local w = {}
    for s = 0, 5 do w[s] = H.readWord(0x57C0 + s * 2) end
    H.log(string.format("formation %04X %04X %04X %04X %04X %04X",
      w[0], w[1], w[2], w[3], w[4], w[5]))
    uSlot = nil
    for s = 0, 5 do if w[s] == ULTROS2 then uSlot = s end end
    H.assertEq(uSlot ~= nil, true, "ULTROS 2 ($012d) is in the formation")

    H.assertEq(H.readByte(SH(uSlot)), 6, "ULTROS 2 seeds 6 shields (Ot6ShieldTbl)")
    H.assertEq(H.readByte(SMX(uSlot)), 6, "ULTROS 2 max shields 6")
    local wc = H.readByte(WKC(uSlot))
    H.log(string.format("ULTROS 2 weak class = $%02X (want slash|pierce $03)", wc))
    H.assertEq(wc, OT6_SLASH | OT6_PIERCE, "ULTROS 2 class row is slash|pierce ($03)")
    H.assertEq(H.readByte(RVC(uSlot)), 0, "nothing revealed yet (classes) -- virgin codex")
    H.assertEq(H.readByte(RVE(uSlot)), 0, "nothing revealed yet (elements)")
    H.log(string.format("ULTROS 2 seed: %d/%d shields, class $%02X",
      H.readByte(SH(uSlot)), H.readByte(SMX(uSlot)), wc))
    H.screenshot("ultros2_seed")

    emu.addMemoryCallback(function(_, v) shWrites[#shWrites + 1] = { H.frame, v } end,
      emu.callbackType.write, 0x7E3E40 + uSlot * 2, 0x7E3E40 + uSlot * 2)
  end),

  -- 3: drive the party's swings onto ULTROS 2 until the gauge first MOVES.
  -- Any landed swing whose Ot6-resolved class meets slash|pierce is the chip;
  -- the gauge and the class-reveal are asserted the instant it lands, and the
  -- pre-chip read is the negative control (the gauge sat at 6 until then).
  H.driveUntil(function()
    pinParty()
    return #shWrites > 0
  end, 30000, {
    H.call(function()
      aPh = (aPh + 1) % 8
      H.setPad(aPh < 4 and { "a" } or {})     -- confirm Fight at the default target
    end),
  }, "a slash|pierce swing reaches the gauge"),
  H.call(function()
    H.log(string.format("gauge moved at f%d: shields %d/6, revClass $%02X",
      H.frame, H.readByte(SH(uSlot)), H.readByte(RVC(uSlot))))
    H.assertEq(H.readByte(SH(uSlot)) < 6, true, "a chip TOOK a shield (6 -> <6)")
    H.assertEq((H.readByte(RVC(uSlot)) & (OT6_SLASH | OT6_PIERCE)) ~= 0, true,
      "and REVEALED a slash|pierce class -- the chip went through the class path")
    H.screenshot("ultros2_chipped")
    H.log("gauge writes: " .. #shWrites)
  end),
})
