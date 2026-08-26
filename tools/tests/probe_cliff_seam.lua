-- probe_cliff_seam.lua -- the last gap: map 21 (32,21) -> (36,2).  Drives
-- the seam directly with long holds, staying east of x=31 so the
-- (30,20) row cannot teleport the party to 43.
local H = dofile("tools/tests/lib/ot6.lua")
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
local t, phase = 0, 1
local holds = { {up=true}, {up=true,right=true}, {right=true}, {up=true},
                {up=true,left=true}, {up=true} }
H.run({ maxFrames = 30000 }, {
  H.loadState("build/states/wob_chase23C.mss.lua"),
  H.waitFrames(8),
  -- wob_chase23C starts on map 21 at (30,22); shift east to (32,21) first
  H.navTo(32, 21, { maxFrames = 6000, playBattles = "flee" }),
  H.call(function()
    H.log(string.format("start seam at (%d,%d)", H.fieldX(), H.fieldY()))
  end),
  H.driveUntil(function()
    return mapIs(22) or (mapIs(21) and H.fieldY() <= 4)
  end, 15000, {
    H.call(function()
      t = t + 1
      if H.dialogWaiting() then H.setPad(t % 8 < 4 and { "a" } or {}); return end
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      if t % 350 == 0 then phase = (phase % #holds) + 1 end
      H.setPad(holds[phase])
      if t % 600 == 0 then
        H.log(string.format("  seam t=%d map=%d (%d,%d)", t,
          H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
      end
    end),
  }, "up the seam"),
  H.call(function()
    H.log(string.format("SEAM RESULT map=%d (%d,%d)", H.mapId() & 0x1ff,
      H.fieldX(), H.fieldY()))
    H.screenshot("seam")
  end),
  H.logStep(function() return "done" end),
})
