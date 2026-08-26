-- probe_bridge_under.lua -- crosses the (23..28,52) row without the
-- teleport.  CheckEntrances only fires on BRIDGE tiles when the party is
-- on the upper z-level ($b8 bit2 + $b2==1); the row is the wooden bridge
-- over the town.  Tries each crossing column from the north side, logging
-- z and where the party lands; on a successful crossing (still on map 21,
-- y>52), takes the east arm and pushes north with long holds.
local H = dofile("tools/tests/lib/ot6.lua")
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
local function z() return H.readByte(0xb2) & 3 end
local crossed = false
local function flatten(t)
  local out = {}
  for _, v in ipairs(t) do
    if type(v) == "table" and v.tick == nil and v[1] ~= nil then
      for _, s in ipairs(v) do out[#out + 1] = s end
    else out[#out + 1] = v end
  end
  return out
end
local steps = {
  H.loadState("build/states/wob_chase23C.mss.lua"),
  H.waitFrames(8),
}
for _, x in ipairs({ 28, 27, 26, 25, 24, 23, 29, 30 }) do
  steps[#steps+1] = H.cond(function()
    return not crossed and mapIs(21) and H.bfsPath(x, 51) ~= nil
  end, flatten({
    H.navTo(x, 51, { maxFrames = 9000, playBattles = "flee" }),
    H.call(function()
      H.log(string.format("  cross x=%d from (%d,%d) z=%d", x,
        H.fieldX(), H.fieldY(), z()))
    end),
    H.hold({ "down" }), H.waitFrames(90), H.release(), H.waitFrames(30),
    H.call(function()
      local m = H.mapId() & 0x1ff
      H.log(string.format("  after: map=%d (%d,%d) z=%d", m,
        H.fieldX(), H.fieldY(), z()))
      if m == 21 and H.fieldY() > 52 then
        crossed = true
        H.log("CROSSED UNDER THE BRIDGE at x=" .. x)
      end
    end),
    -- if we teleported to town, walk back in
    H.cond(function() return mapIs(20) end, flatten({
      H.navTo(36, 2, { maxFrames = 9000, playBattles = "flee",
        arrive = function() return mapIs(21) end }),
      H.driveUntil(function() return mapIs(21) end, 900,
        { H.call(function() H.setPad({ up = true }) end) }, "re-enter 21"),
      H.waitFrames(60),
    }), {}),
  }), {})
end
steps[#steps+1] = H.call(function()
  H.log(string.format("BRIDGE RESULT crossed=%s map=%d (%d,%d)",
    tostring(crossed), H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
  H.screenshot("bridge_result")
end)
steps[#steps+1] = H.cond(function() return crossed end,
  { H.saveState("wob_bridge_south.mss") }, {})
steps[#steps+1] = H.logStep(function() return "done" end)
H.run({ maxFrames = 90000 }, flatten(steps))
