-- gen_kefka_won.lua -- v0.4's FIRST link, deliberately OUTSIDE the v0.3
-- frontier: boot kefka_doorstep, win battle 57 again (kill-bit; the $40
-- scripted win), then ride the win tail -- the esper scene on map 23,
-- Arvis's house -- to the first controllable frame and mint kefka_won.mss.
--
-- KNOWN BLOCKED by issue #3: the esper scene presents its dialogs without
-- setting the field dialog flags ($00BA/$00D3 read 0 throughout, MEASURED),
-- and the unconditional-tap drive below -- which walked the PC off $CCBEBA
-- in probe_esper_stall's measurement -- still timed out on the integrated
-- ROM's lineage.  The stall reproduces on EVERY boot lineage, honest
-- included; it is a scene-driving gap, not a rostering bug (632af69
-- retracted that theory).  probe_esper_stall's dump is the diagnosis
-- starting point.  Until #3 closes, this generator FAILS at "the win tail
-- to control" -- loudly, in its own rule, gating nothing the v0.3 release
-- needs.  That isolation is the point: a past-the-stop-line bug must not
-- halt the chain that mints the release's fixtures (it did, once).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local KEFKA = 0x014A

local function sw(id)
  return (H.readByte(0x1E80 + math.floor(id / 8)) >> (id % 8)) & 1
end
local function bright() return H.readByte(0x2100) & 0x0F end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

H.run({ maxFrames = 90000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/kefka_doorstep.mss.lua"),
  H.waitFrames(30),

  -- the doorstep is one clean edge-A from battle 57 (gen_narshe_battle
  -- minted it there and proved the activation)
  H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
    H.cond(function() return true end, {
      H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
    }),
  }, "clean A into KEFKA -> battle 57"),
  H.waitUntil(function() return H.battleActive() end, 3000, "Kefka up", 10),
  H.waitFrames(150),
  (function()
    local aPh = 0
    return H.driveUntil(function() return not H.battleLoadStarted() end,
      20000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.monstersPresent() > 0 then killBitAll() end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, "Kefka down (kill-bit; the $40 win)")
  end)(),

  -- THE WIN TAIL (issue #3 lives here): tap A unconditionally through the
  -- flag-less esper dialogs; kill-bit any battle that loads; require 60
  -- consecutive plain-field-control frames before believing the arrival.
  (function()
    local aPh, cnt = 0, 0
    return H.driveUntil(function()
      local ok = H.hasControl() and H.tileAligned() and bright() >= 15
             and not H.dialogWaiting() and not H.eventRunning()
             and not H.battleLoadStarted() and not H.worldMode()
      cnt = ok and cnt + 1 or 0
      return cnt >= 60
    end, 60000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.battleLoadStarted() then
          if H.monstersPresent() > 0 then killBitAll() end
          H.setPad(aPh < 4 and { "a" } or {}); return
        end
        if not (H.hasControl() and H.tileAligned()) or H.dialogWaiting() then
          H.setPad(aPh < 4 and { "a" } or {})
        else
          H.setPad({})
        end
      end),
    }, "the win tail to control (tap through the esper scene -- issue #3)")
  end)(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x0139), 1, "$0139 SET -- the battle-won latch")
    H.assertEq(sw(0x0612), 0, "$0612 clear -- KEFKA gone")
    H.assertEq(sw(0x061D), 0, "raiders retired")
    H.log(string.format("[kefka_won] f%d map=%d (%d,%d)",
      H.frame, H.mapId(), H.fieldX(), H.fieldY()))
    H.screenshot("kefka_won")
  end),
  H.saveState("kefka_won.mss"),
  H.logStep(function()
    return string.format("kefka_won minted at frame %d -- v0.4's first link", H.frame)
  end),
})
