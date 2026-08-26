-- probe_v07_384toggle.lua -- instruments the (104,17) toggle frame by frame.
-- Not a suite test.  One clean edge: 8 frames of up+A, then up only.  Logs
-- $01F5, position, control every 20 frames for 900 frames.  Then a second
-- clean edge, same watch.
-- playBattles = "flee": this Magitek Research Facility basement draws
-- random battles.
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
