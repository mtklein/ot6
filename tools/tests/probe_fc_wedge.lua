-- probe_fc_wedge.lua -- anatomy of the chute-landing wedge (#132).
-- Boot fc_shadow, walk the proven route to (82,30), ride the (89,25)
-- tunnel, then dump the party's fine-position/object state and probe
-- each direction, logging what the engine does with each hold.
local H = dofile("tools/tests/lib/ot6.lua")
local function mapIs(m) return (H.mapId() & 0x3ff) == m end
local function snap(tag)
  local b = {}
  for _, a in ipairs({0x0866,0x0867,0x0868,0x0869,0x086A,0x086B,0x086C,0x086D}) do
    b[#b+1] = string.format("%02X", H.readByte(a))
  end
  H.log(string.format("[wedge %s] (%d,%d) ctrl=%s aligned=%s $b2=%02X 866-86D=%s",
    tag, H.fieldX(), H.fieldY(), tostring(H.hasControl()),
    tostring(H.tileAligned and H.tileAligned() or "?"), H.readByte(0xb2),
    table.concat(b, " ")))
end
H.run({ maxFrames = 80000 }, {
  H.loadState("build/states/fc_shadow.mss.lua"),
  H.waitFrames(60),
  -- proven prefix: frontier not needed; direct navTos with generous frames
  H.navTo(19, 12, { maxFrames = 9000, playBattles = "tactical",
    magic = { [0x07] = { spell = 2, boost = false } } }),
  H.navTo(25, 19, { maxFrames = 9000, playBattles = "tactical",
    magic = { [0x07] = { spell = 2, boost = false } } }),
  H.call(function() snap("pre-ride baseline") end),
  -- continue the proven route: (40,12), (44,11), (40,6)-chute, (36,28),
  -- (67,39)-walk, (40,24)-tunnel... simplest: go straight for the
  -- (89,25) tunnel region via (36,28)/(67,39)/(40,24) legs is long;
  -- instead ride the FIRST chute (40,6) and snapshot around IT -- same
  -- ride class, minutes sooner
  H.navTo(40, 12, { maxFrames = 12000, playBattles = "tactical",
    magic = { [0x07] = { spell = 2, boost = false } } }),
  H.call(function() snap("pre (40,6) approach") end),
  (function()
    local near, t2 = false, 0
    return H.navTo(40, 6, { maxFrames = 9000, playBattles = "tactical",
      magic = { [0x07] = { spell = 2, boost = false } },
      arrive = function()
        if H.fieldX() == 40 and H.fieldY() == 6 then near = true end
        return near
      end })
  end)(),
  H.call(function() snap("latched on the chute") end),
  -- absorb the ride with ZERO pad input, snapping through it
  (function()
    local t3 = 0
    return H.driveUntil(function()
      t3 = t3 + 1
      if t3 % 120 == 0 then snap("ride t" .. t3) end
      return t3 >= 900
    end, 1200, { H.call(function() H.setPad({}) end) }, "ride absorbed")
  end)(),
  H.call(function() snap("post-ride settled") end),
  -- directional probes: hold each way 300f, snap after each
  (function()
    local steps = {}
    for _, d in ipairs({ "left", "right", "up", "down" }) do
      steps[#steps+1] = H.hold({ d })
      steps[#steps+1] = H.waitFrames(300)
      steps[#steps+1] = H.release()
      steps[#steps+1] = H.call(function() snap("after hold " .. d) end)
    end
    return H.cond(function() return true end, steps, {})
  end)(),
  H.logStep(function() return "done" end),
})
