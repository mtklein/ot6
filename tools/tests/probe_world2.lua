-- probe_world2.lua -- why did 428 paced world steps roll zero encounters?
-- (probe_world run 1: zone rate byte $45 says rate 1, WorldBattleRateTbl
-- says +96 vanilla / +48 ot6-scaled per step, yet nothing fired.)  Walk a
-- few steps and watch every gate in the chain: $1EB9 bit5 (the battles-
-- disabled switch move.asm:870 checks), $11DF & 3 (moogle charm / charm
-- bangle row select -- rows 2/3 of WorldBattleRateTbl are all zeros), and
-- the $1F6E danger word itself.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/worldmap_narshe.mss.lua"

local function P(fmt, ...) print("[probe] " .. string.format(fmt, ...)) end
local function wx() return H.readByte(0x00e0) end
local function wy() return H.readByte(0x00e2) end

local steps = 0
H.run({ maxFrames = 6000 }, {
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function()
    P("gates at boot: $1EB9=%02X $11DF=%02X $1F6E=%04X $11F9=%02X",
      H.readByte(0x1eb9), H.readByte(0x11df), H.readWord(0x1f6e),
      H.readByte(0x11f9))
  end),
  H.repeatN(12, {
    H.hold({ "down" }), H.waitFrames(18), H.release(), H.waitFrames(4),
    H.call(function()
      steps = steps + 1
      P("step %2d at (%d,%d): $1EB9=%02X $11DF=%02X danger $1F6E=%04X",
        steps, wx(), wy(), H.readByte(0x1eb9), H.readByte(0x11df),
        H.readWord(0x1f6e))
    end),
  }),
})
