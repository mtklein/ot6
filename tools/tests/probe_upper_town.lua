-- probe_upper_town.lua -- reach Narshe's upper north through the
-- buildings (#133): map 30's rooms exit at town (53,8)/(49,14)/(18,24)/
-- (32,18); from the treasure room they may interconnect.  Enter at
-- (52,38), chart 30, hop every reachable exit door, and from each town
-- landing chart the neighborhood + try the north-mine door (26,9)->50.
local H = dofile("tools/tests/lib/ot6.lua")
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
local function sw(bit) return (H.readByte(0x1E80 + (bit >> 3)) >> (bit & 7)) & 1 end
local function flatten(t)
  local out = {}
  for _, v in ipairs(t) do
    if type(v) == "table" and v.tick == nil and v[1] ~= nil then
      for _, s in ipairs(v) do out[#out + 1] = s end
    else out[#out + 1] = v end
  end
  return out
end
H.run({ maxFrames = 60000 }, flatten({
  H.loadState("build/states/wob_narshe_town.mss.lua"),
  H.waitFrames(8),
  H.navTo(52, 38, { maxFrames = 12000, playBattles = "flee" }),
  H.driveUntil(function() return mapIs(30) end, 900,
    { H.call(function() H.setPad({ up = true }) end) }, "into the building"),
  -- ride the Lone Wolf intro if it fires (part of the chase anyway)
  (function()
    local t = 0
    return H.driveUntil(function()
      return t > 400 and H.hasControl() and not H.dialogWaiting()
    end, 4000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then H.setPad(t % 8 < 4 and { "a" } or {}) else H.setPad({}) end
      end),
    }, "intro settled")
  end)(),
  H.call(function()
    H.log(string.format("in 30 at (%d,%d) $0239=%d", H.fieldX(), H.fieldY(), sw(0x239)))
    for y = 8, 44, 2 do
      local row = {}
      for x = 40, 116, 2 do row[#row+1] = H.bfsPath(x, y) and "O" or "." end
      H.log(string.format("  m30 y%02d %s", y, table.concat(row)))
    end
  end),
  -- hop to each exit door that is reachable, preferring the north ones
  (function()
    local out = {}
    for _, d in ipairs({ {67,26,"(53,8) north"}, {55,35,"(49,14) mid"},
                          {110,26,"(18,24) west"}, {80,36,"(32,18) center"} }) do
      out[#out+1] = H.cond(function()
        return mapIs(30) and H.bfsPath(d[1], d[2]) ~= nil
      end, flatten({
        H.call(function() H.log("taking door to town " .. d[3]) end),
        H.navTo(d[1], d[2], { maxFrames = 9000, playBattles = "flee",
          arrive = function() return mapIs(20) end }),
        H.driveUntil(function() return mapIs(20) end, 900,
          { H.call(function() H.setPad({ down = true }) end) }, "out " .. d[3]),
        H.waitFrames(50),
      }), {})
    end
    return out
  end)(),
  H.call(function()
    H.log(string.format("landed town (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("upper_town")
    for _, t in ipairs({ {26,9},{26,8},{25,9},{27,9},{34,2},{36,2},{20,9},{15,57} }) do
      local p = H.bfsPath(t[1], t[2])
      H.log(string.format("  from here (%d,%d): %s", t[1], t[2],
        p and (#p .. " steps") or "no"))
    end
  end),
  H.cond(function() return mapIs(20) and H.bfsPath(26, 9) ~= nil end, flatten({
    H.navTo(26, 9, { maxFrames = 9000, playBattles = "flee",
      arrive = function() return mapIs(50) end }),
    H.driveUntil(function() return mapIs(50) end, 900,
      { H.call(function() H.setPad({ up = true }) end) }, "NORTH MINE"),
    H.waitFrames(60),
    H.call(function()
      H.log(string.format("IN THE NORTH MINE (50) at (%d,%d)", H.fieldX(), H.fieldY()))
      H.screenshot("north_mine")
      H.saveState("wob_north_mine.mss")
    end),
  }), {}),
  H.logStep(function() return "done" end),
}))
