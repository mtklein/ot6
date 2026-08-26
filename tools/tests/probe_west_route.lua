-- probe_west_route.lua -- the walkthrough route, literally:
-- cracked wall (15,57) -> mine 41-NW -> door (21,9) -> town (23,44)
-- ["outside again"] -> WEST -> door (10,36) -> caves 48 -> 49 -> 50 ->
-- onward, scanning and charting at every landing, goal-checking for the
-- snow-field chain and the (26,9)->50 door region.
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
local function landing(tag)
  return H.call(function()
    H.log(string.format("[%s] map=%d (%d,%d)", tag, H.mapId() & 0x1ff,
      H.fieldX(), H.fieldY()))
    H.screenshot(tag)
  end)
end
H.run({ maxFrames = 90000 }, flatten({
  H.loadState("build/states/wob_chase23C.mss.lua"),
  H.waitFrames(8),
  -- down to town
  H.navTo(27, 51, { maxFrames = 9000, playBattles = "flee",
    arrive = function() return mapIs(20) end }),
  H.driveUntil(function() return mapIs(20) end, 900,
    { H.call(function() H.setPad({ down = true }) end) }, "to town"),
  H.waitFrames(60),
  -- the cracked wall (opens fresh in this boot)
  H.navTo(15, 57, { maxFrames = 12000, playBattles = "flee" }),
  H.driveUntil(function() return sw(0x1F0) == 1 end, 900, {
    H.call(function() H.setPad({ up = true, a = true }) end),
  }, "wall opens"),
  H.release(), H.waitFrames(60),
  H.driveUntil(function() return mapIs(41) end, 1500, {
    H.call(function() H.setPad({ up = true }) end),
  }, "into 41-NW"),
  H.waitFrames(60),
  landing("nw41"),
  -- up the NW corridor to the (21,9) door -> town (23,44)
  (function()
    local tile = nil
    return {
      H.call(function()
        for _, c in ipairs({ {21,9},{20,9},{22,9},{21,10},{21,8} }) do
          if H.bfsPath(c[1], c[2]) then tile = c
            H.log(string.format("exit door via (%d,%d)", c[1], c[2])); return end
        end
        error("41-NW: no exit-door tile reachable")
      end),
      H.navTo(function() return tile[1] end, function() return tile[2] end,
        { maxFrames = 12000, playBattles = "flee",
          arrive = function() return mapIs(20) end }),
      H.driveUntil(function() return mapIs(20) end, 1500, {
        H.call(function() H.setPad({ up = true }) end),
      }, "out at town (23,44)"),
    }
  end)(),
  H.waitFrames(60),
  landing("town_west"),
  H.call(function()
    for _, t in ipairs({ {10,36},{10,37},{11,36},{9,36},{26,9},{26,8},
                          {18,22},{15,56},{34,2},{22,45} }) do
      local p = H.bfsPath(t[1], t[2])
      H.log(string.format("  west-scan (%d,%d): %s", t[1], t[2],
        p and (#p .. " steps") or "no"))
    end
  end),
  -- west to the (10,36) door -> 48
  H.cond(function() return H.bfsPath(10, 37) ~= nil or H.bfsPath(11, 36) ~= nil end,
  flatten({
    (function()
      local tile = nil
      return {
        H.call(function()
          for _, c in ipairs({ {10,37},{11,36},{9,36},{10,36} }) do
            if H.bfsPath(c[1], c[2]) then tile = c; return end
          end
        end),
        H.navTo(function() return tile[1] end, function() return tile[2] end,
          { maxFrames = 9000, playBattles = "flee",
            arrive = function() return mapIs(48) end }),
        H.driveUntil(function() return mapIs(48) end, 1200,
          { H.call(function() H.setPad({ up = true }) end) }, "into 48"),
        H.waitFrames(60),
        landing("cave48"),
      }
    end)(),
    -- 48 -> 49 via (79,9); 49 -> 50 via (111,10)
    H.navTo(79, 10, { maxFrames = 12000, playBattles = "flee",
      arrive = function() return mapIs(49) end }),
    H.driveUntil(function() return mapIs(49) end, 1200,
      { H.call(function() H.setPad({ up = true }) end) }, "into 49"),
    H.waitFrames(60),
    landing("cave49"),
    -- 49 is a slow-climb map (bfs can't model it: control drops on the
    -- climb tiles and the walkable set looks like a 9-tile island).
    -- Patient climber, straight from the mines/cliff lesson: long holds,
    -- rotate on stall, ride dialogs A-only, until the map changes.
    (function()
      local t, di = 0, 1
      local dirs = { {up=true}, {up=true,left=true}, {up=true,right=true},
                     {left=true}, {right=true} }
      local lastPos, still = nil, 0
      return H.driveUntil(function() return not mapIs(49) end, 20000, {
        H.call(function()
          t = t + 1
          if H.dialogWaiting() then H.setPad(t % 8 < 4 and { "a" } or {}); return end
          if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
          local pos = H.fieldX() * 256 + H.fieldY()
          if pos ~= lastPos then lastPos = pos; still = 0 else still = still + 1 end
          if still > 300 then di = (di % #dirs) + 1; still = 0 end
          H.setPad(dirs[di])
          if t % 600 == 0 then
            H.log(string.format("  climb49 t=%d (%d,%d) ctrl=%s", t,
              H.fieldX(), H.fieldY(), tostring(H.hasControl())))
          end
        end),
      }, "climb out of 49")
    end)(),
    H.waitFrames(60),
    landing("after49"),
    H.call(function()
      for y = 0, 62, 2 do
        local row = {}
        for x = 0, 126, 2 do row[#row+1] = H.bfsPath(x, y) and "O" or "." end
        H.log(string.format("  m%d y%02d %s", H.mapId() & 0x1ff, y,
          table.concat(row)))
      end
    end),
    H.saveState("wob_north_mine.mss"),
  }), {}),
  H.logStep(function() return "done" end),
}))
