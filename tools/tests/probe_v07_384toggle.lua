-- probe_v07_384toggle.lua -- instrument the (104,17) toggle (_cb33c9,
-- event_main.asm:45485) frame by frame (issue #31).  Not a suite test.
-- One clean edge: 8 frames of up+A, then up only.  Log $01F5, position,
-- control every 20 frames for 900 frames.  Then a second clean edge, same
-- watch.  This settles what iteration 3/4 could not: when the switch
-- flips, how long the event runs, and whether a lingering press re-fires.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- Issue #75: playBattles = "flee" keeps this walk out of the library's
-- monster-dead flag write, and here it is not a no-op: this Magitek Research
-- Facility basement draws random battles (map_prop.dat byte +5 bit 7 set).
-- "flee" is the spelling every gen_mrf_* generator already uses on these
-- floors: the instrument is measuring a floor mechanism, not a fight.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

local function watch(tag, frames)
  local n = 0
  return H.driveUntil(function() return n >= frames end, frames + 120, {
    H.call(function()
      n = n + 1
      H.setPad({ up = true })
      if n % 20 == 0 then
        H.log(string.format("[%s f+%d] $01F5=%d $01F6=%d pos(%d,%d) ctl=%s "
          .. "ev=%s", tag, n, sw(0x01F5), sw(0x01F6),
          H.fieldX(), H.fieldY(), tostring(H.hasControl()),
          tostring(H.eventRunning())))
      end
    end),
  }, tag)
end

H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/v07i_384_toggle.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(map(), 384, "booted on BASEMENT 3")
    H.log(string.format("[boot] (%d,%d) $01F5=%d", H.fieldX(), H.fieldY(),
      sw(0x01F5)))
  end),
  H.navTo(104, 17, { maxFrames = 12000, playBattles = "flee" }),
  H.call(function()
    H.log(string.format("[on tile] (%d,%d) $01F5=%d facing=%02X",
      H.fieldX(), H.fieldY(), sw(0x01F5), H.readByte(0x0757)))
  end),
  -- one clean edge
  (function() local n = 0
    return H.driveUntil(function() return n >= 8 end, 120, {
      H.call(function() n = n + 1; H.setPad({ up = true, a = true }) end),
    }, "8-frame up+A edge")
  end)(),
  watch("edge1", 900),
  H.call(function()
    H.log(string.format("[after edge1] (%d,%d) $01F5=%d", H.fieldX(),
      H.fieldY(), sw(0x01F5)))
  end),
  -- second clean edge, still standing on the tile
  (function() local n = 0
    return H.driveUntil(function() return n >= 8 end, 120, {
      H.call(function() n = n + 1; H.setPad({ up = true, a = true }) end),
    }, "second 8-frame up+A edge")
  end)(),
  watch("edge2", 900),
  H.call(function()
    H.log(string.format("[after edge2] (%d,%d) $01F5=%d", H.fieldX(),
      H.fieldY(), sw(0x01F5)))
  end),
  H.logStep("toggle instrumentation complete"),
})
