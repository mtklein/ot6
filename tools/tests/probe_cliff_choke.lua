-- probe_cliff_choke.lua -- eyes on the (75,39..41) chokepoint of Narshe
-- checkpoint map 43: bfs says (75,39) is reachable but walking stops at
-- (75,41).  Suspect: an NPC (Lone Wolf mid-chase?) standing in the gap.
local H = dofile("tools/tests/lib/ot6.lua")
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
H.run({ maxFrames = 30000 }, {
  H.loadState("build/states/wob_chase23C.mss.lua"),
  H.waitFrames(8),
  H.navTo(30, 21, { maxFrames = 9000, playBattles = "flee",
    arrive = function() return mapIs(43) end }),
  H.driveUntil(function() return mapIs(43) end, 600,
    { H.call(function() H.setPad({ up = true }) end) }, "into 43"),
  H.waitFrames(50),
  H.navTo(111, 30, { maxFrames = 12000, playBattles = "flee",
    arrive = function()
      return math.abs(H.fieldX() - 73) + math.abs(H.fieldY() - 60) < 6
    end }),
  H.driveUntil(function()
    return math.abs(H.fieldX() - 73) + math.abs(H.fieldY() - 60) < 6
  end, 900, { H.call(function() H.setPad({ up = true }) end) }, "row to (73,60)"),
  H.waitFrames(50),
  H.navTo(75, 41, { maxFrames = 9000, playBattles = "flee" }),
  H.call(function() H.screenshot("choke_before") end),
  H.hold({ "up" }), H.waitFrames(200), H.release(), H.waitFrames(10),
  H.call(function()
    H.log(string.format("after push: (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("choke_after")
  end),
  -- patient climber: the mines' climb tiles move ~1 tile per 100 frames,
  -- so hold each direction long.  Goal-check every 400 frames for the
  -- cliff chain becoming reachable; stop on map 22/23 or a goal.
  (function()
    local t, di = 0, 1
    local dirs = { {up=true}, {up=true,left=true}, {left=true},
                   {up=true,right=true}, {right=true}, {down=true,left=true} }
    local lastPos, still = nil, 0
    return H.driveUntil(function()
      if mapIs(22) or mapIs(23) then return true end
      if t > 0 and t % 400 == 0 then
        local m = H.mapId() & 0x1ff
        local goals = (m == 21) and { {35,2},{34,2},{36,2},{37,2} }
          or (m == 41) and { {107,12},{108,12},{117,12},{116,12} } or {}
        for _, c in ipairs(goals) do
          if H.bfsPath(c[1], c[2]) then
            H.log(string.format("  GOAL on map %d via (%d,%d)", m, c[1], c[2]))
            return true
          end
        end
      end
      return false
    end, 16000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then H.setPad(t % 8 < 4 and { "a" } or {}); return end
        if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
        local pos = H.fieldX() * 256 + H.fieldY()
        if pos ~= lastPos then lastPos = pos; still = 0 else still = still + 1 end
        if still > 240 then di = (di % #dirs) + 1; still = 0 end
        H.setPad(dirs[di])
        if t % 600 == 0 then
          H.log(string.format("  climb t=%d map=%d (%d,%d)", t,
            H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
        end
      end),
    }, "climb to the cliffs")
  end)(),
  H.call(function()
    H.log(string.format("END map=%d at (%d,%d)", H.mapId() & 0x1ff,
      H.fieldX(), H.fieldY()))
    H.screenshot("choke_end")
  end),
  H.cond(function() return mapIs(22) or mapIs(23) or mapIs(21) end,
    { H.saveState("wob_cliffside.mss") }, {}),
  H.logStep(function() return "done" end),
})
