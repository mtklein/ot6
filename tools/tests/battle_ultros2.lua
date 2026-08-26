-- @suite savestate=ultros2_entry slow
-- battle_ultros2.lua -- the Opera's Ultros 2 break gauge. Boots
-- ultros2_entry, rides into battle 104, and asserts:
--   1. Ultros 2 ($012d) seeds 6/6 shields, class-weak OT6_SLASH|OT6_PIERCE.
--   2. Nothing is revealed on the fixture's codex at seed.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/ultros2_entry.mss.lua"

local ULTROS2 = 0x012d
local OT6_SLASH, OT6_PIERCE = 0x01, 0x02

-- monster slot s -> entity offset 8 + 2s
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

  -- ride the last interaction into battle 104
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function()
      aPh = (aPh + 1) % 8
      if H.monstersPresent() > 0 then
        for s = 0, 5 do
          if H.readByte(0x3aa8 + s * 2) % 2 == 1 then end  -- (no forced clear; goal fight)
        end
      end
      H.setPad(aPh < 4 and { "a" } or {})
    end),
  }, "the rafter scene reaches battle 104"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 3000, "Ultros 2 up", 10),
  H.waitFrames(120),

  -- 1 + 2: the seed, read before anything is poked.
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

  -- Ultros occupies four formation positions and moves between them.
  H.logStep(function()
    return string.format("Ultros 2 ($012d) verified in battle 104 at frame %d",H.frame)
  end),
})
