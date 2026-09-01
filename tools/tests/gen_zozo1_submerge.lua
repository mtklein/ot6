-- gen_zozo1_submerge.lua -- v0.4 step 1a: kefka_won (Arvis's house, map 30
-- {60,37}, LOCKE+CELES+EDGAR+SABIN) -> Narshe streets -> the world -> the
-- east Figaro castle -> the engine-room attendant -> the Kohlingen crossing
-- -> generate figaro_submerged.mss (map 61 {6,34}, castle parked west).

local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id)
  return (H.readByte(0x1E80 + math.floor(id / 8)) >> (id % 8)) & 1
end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end

-- calm-arrival pred (gen_kefka_won's): n consecutive controllable
-- full-bright field frames on map m
local function landed(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d) f%d: map=%d ctl=%s dlg=%s ev=%s (%d,%d)",
        m, H.frame, map(), tostring(H.hasControl()),
        tostring(H.dialogWaiting()), tostring(H.eventRunning()),
        H.fieldX(), H.fieldY()))
    end
    return cnt >= (n or 20)
  end
end

-- cross a CheckDoor door: stand beside it (navTo), then hold `dir` until
-- the destination map is up, then settle.  Doors are walls to bfsPath, so
-- the held press is the only way through (gen_edgar).
local function door(nx, ny, dir, m, what)
  return H.cond(function() return true end, {
    H.navTo(nx, ny, { maxFrames = 12000, playBattles = "tactical" }),
    H.driveUntil(function() return map() == m end, 900, {
      H.hold({ dir }), H.waitFrames(4),
    }, what .. ": through the door"),
    H.advanceStory(landed(m, 10), 2400, { playBattles = "tactical" }),
    H.waitFrames(150),
  })
end

H.run({ maxFrames = 90000 }, {
  H.loadState("build/states/kefka_won.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 30, "booted in Arvis's house (map 30)")
    H.assertEq(H.fieldX() == 60 and H.fieldY() == 37, true, "at {60,37}")
    H.assertEq(sw(0x010B), 1, "$010B SET -- castle parked EAST")
    H.assertEq(sw(0x0048), 1, "$0048 SET -- the attendant will offer the ride")
    H.assertEq(partyOf(0x01), 1, "LOCKE aboard")
  end),

  -- 1. Arvis's house -> Narshe town by the front door (55,35) -> map 20
  --    {49,14}.  Tier 1's invisible door-NPC no longer stands there
  --    (probe_n30: reachable in 9, tile unoccupied), and the tier-1
  --    corridor exit's (53,8) clifftop position is isolated after the
  --    battle (probe_n20 census after full settle: zero reachable tiles),
  --    so the front door is now the only way to the streets.
  H.navTo(55, 35, { arrive = function() return map() == 20 end,
                    maxFrames = 12000, playBattles = "tactical" }),
  H.waitUntil(landed(20, 10), 1200, "landed on the streets", 1),
  H.waitFrames(150),

  -- 2. the south gate at (38,61) (gen_worldmap's verified tile), then one
  --    held step south onto the y=62 exit row -> world {83,36}
  H.navTo(38, 61, { maxFrames = 20000, playBattles = "tactical" }),
  H.driveUntil(function() return H.worldMode() end, 900, {
    H.hold({ "down" }), H.waitFrames(4),
  }, "off the south edge to the world"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
  end, 1200, "world control", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[world] at (%d,%d)", H.worldX(), H.worldY()))
  end),

  -- 3. to the east castle trigger (64,76): stop one tile north, then step
  --    onto it (the trigger checks $010B and loads map 55 {28,42}).  The
  --    arrive bails if a stray step fires the trigger early; the next
  --    drive's map-55 pred is then already true and holds nothing (holding
  --    down at the gate would step onto y=43, the world-exit row).
  H.worldNavTo(64, 75, { maxFrames = 30000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  H.driveUntil(function() return not H.worldMode() and map() == 55 end, 900, {
    H.hold({ "down" }), H.waitFrames(4),
  }, "onto the castle trigger"),
  H.waitUntil(landed(55, 10), 1500, "castle gate up", 1),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[castle] map 55 at (%d,%d)", H.fieldX(), H.fieldY()))
  end),

  door(28, 39, "up", 59, "into the keep"),
  H.saveState("_scratch_keep59.mss"),   -- cheap re-entry for route iteration
  H.navTo(9, 49, { arrive = function() return map() == 61 end,
                   maxFrames = 9000, playBattles = "tactical" }),
  H.waitUntil(landed(61, 10), 1500, "engine room", 1),
  H.waitFrames(150),

  -- 5. the attendant at {6,33}: stand below at (6,34), face up (a held up
  --    turns in place, because the NPC blocks the step), then edge-A.
  --    (6,34) keeps the route off (5,35), the "That's dangerous!" shoo
  --    trigger (_ca69cd) that takes control every frame it is stood on.
  H.navTo(6, 34, { maxFrames = 9000, playBattles = "tactical" }),
  H.hold({ "up" }), H.waitFrames(8), H.release(), H.waitFrames(4),
  (function()
    local aPh = 0
    return H.driveUntil(function() return H.dialogWaiting() end, 600, {
      H.call(function()
        aPh = (aPh + 1) % 12
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, "the attendant answers")
  end)(),
  H.call(function()
    H.log(string.format("[attendant] dlg up, $056E=%d", H.readByte(0x056e)))
  end),

  -- 6. tap through the greeting into the choice; index 0 = Kohlingen; then
  --    ride the crossing hands-off (advanceStory: dialog-gated taps only)
  H.advanceStory(landed(61, 60), 30000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 61, "back in the engine room")
    H.assertEq(sw(0x010C), 1, "$010C SET -- castle parked WEST")
    H.assertEq(sw(0x010B), 0, "$010B clear -- no longer east")
    H.log(string.format("[figaro_submerged] f%d map=%d (%d,%d) parent=(%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY(),
      H.readByte(0x1f69 + 2), H.readByte(0x1f69 + 3)))
    H.screenshot("figaro_submerged")
  end),
  H.saveState("figaro_submerged.mss"),
  H.logStep(function()
    return string.format("figaro_submerged generated at frame %d", H.frame)
  end),
})
