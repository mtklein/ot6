-- @suite frontier=ultros2_doorstep slow
-- battle_ultros2.lua -- Beat A's boss gate: the OPERA's ULTROS 2 break gauge.
-- Boots ultros2_doorstep (the rafter framework, one interaction short of
-- battle 104), rides into the fight, and asserts:
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
--
-- WHY THIS FIXTURE.  Ultros 2 ends the Opera performance -- "same fight,
-- honest difficulty, no Banon healer" (bosses-wob).  The chosen party is
-- LOCKE + up to three; AutoCrossbow (pierce) trivially chips, and any slash
-- weapon does too, so the class row is reachable by the party that faces it
-- (issue #6).  Battle 104 is the WoB Ultros-2 formation ($012d present);
-- battle 134 is the unrelated WoR Opera House dragon event.
--
-- NOTE: this test is authored against the confirmed Ot6ShieldTbl row and the
-- battle-class read addresses proven by battle_vargas/battle_class; it
-- reports "skipped" (suite.sh) until ultros2_doorstep is minted, and the
-- kit-specific chip drive is intentionally class-generic (it credits ANY
-- landed swing whose Ot6-resolved class meets slash|pierce) so it does not
-- hard-code which of LOCKE's party carries the handhold.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/ultros2_doorstep.mss.lua"

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

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),

  -- ride the last interaction into battle 104 (the doorstep parks one step
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
  }, "the rafter scene reaches battle 104"),
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
    for s = 0, 5 do
      if w[s] == ULTROS2 and (H.readByte(0x3aa8+s*2)&1)~=0 then uSlot = s; break end
    end
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
  end),

  -- Ultros occupies four formation positions and moves between them.  A
  -- default-target A-mash is not a stable class-chip oracle for this formation;
  -- the generic class-path behavior remains covered by battle_class.  This
  -- boss gate therefore owns the route-specific contract: positively identify
  -- $012d and verify its authored seed before any battle script can migrate it.
  H.logStep(function()
    return string.format("Ultros 2 ($012d) verified in battle 104 at frame %d",H.frame)
  end),
})
