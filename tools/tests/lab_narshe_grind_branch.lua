-- @manual
-- lab_narshe_grind_branch.lua -- DIAGNOSTIC branch of the Narshe-mission
-- grind: boot one of lab_narshe_grind_snap's leg-start snapshots and play
-- N grind legs with exactly the generator's leg options, ending the ride
-- on a wipe instead of raising, so the same approach to a wiping fight can
-- be replayed under different fight-driver versions (swap the lib halves
-- in a scratch tree; the snapshot is machine state and does not care).
-- Configure through globals the composer's preamble can set, else the
-- defaults below.
local H = dofile("tools/tests/lib/ot6.lua")

local SNAP = OT6_BRANCH_SNAP or "build/states/narshe_grind_leg68.mss.lua"
local LEGS = OT6_BRANCH_LEGS or 4
local FIRST_LEG = OT6_BRANCH_FIRST_LEG or 68

local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function maxLvl()
  local m = 0
  for c = 0, 15 do
    if partyOf(c) ~= 0 then
      local l = H.readByte(0x1600 + 37 * c + 8)
      if l > m then m = l end
    end
  end
  return m
end
local TONIC, POTION, FENIX = 0xE8, 0xE9, 0xF0
local function bagLine(tag)
  local t = {}
  for _, c in ipairs(H.partyMembers()) do
    t[#t + 1] = string.format("c%d %d/%d hp %d/%d mp", c, H.charHp(c),
      H.charMaxHp(c), H.charMp(c), H.charMaxMp(c))
  end
  return string.format("[%s] %s | tonic=%d potion=%d fenix=%d",
    tag, table.concat(t, "  "), H.invCountOf(TONIC), H.invCountOf(POTION),
    H.invCountOf(FENIX))
end

-- the generator's pacing pair (its survey picks these on this plain)
local ax, ay, bx, by = 38, 112, 24, 120
local wiped = false
local steps = {
  H.loadState(SNAP),
  H.waitFrames(30),
  H.logStep(function()
    return string.format("[branch] booted %s at world (%d,%d) f%d best level %d; %s",
      SNAP, H.worldX(), H.worldY(), H.frame, maxLvl(), bagLine("bag"))
  end),
}
for i = 0, LEGS - 1 do
  local leg = FIRST_LEG + i
  steps[#steps + 1] = H.cond(function() return not wiped end, {
    H.worldNavTo(function() return leg % 2 == 1 and ax or bx end,
                 function() return leg % 2 == 1 and ay or by end, {
      maxFrames = 45000, playBattles = "tactical",
      careThreshold = 0.7, healPercent = 45, wipeEndsRide = true,
      summon = { [1] = { mp = 36 }, [4] = { mp = 50 }, [5] = { mp = 27 } } }),
    H.call(function()
      if (H.gameOverFired or 0) > 0 then wiped = true end
      H.log(string.format("[branch] leg %d done f%d wiped=%s %s", leg, H.frame,
        tostring(wiped), bagLine("bag")))
    end),
  }, {})
end
steps[#steps + 1] = H.logStep(function()
  return string.format("[branch] verdict: %s after %d legs from %s (frame %d)",
    wiped and "WIPED" or "survived", LEGS, SNAP, H.frame)
end)

H.run({ maxFrames = 400000, allowGameOver = true }, steps)
