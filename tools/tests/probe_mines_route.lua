-- probe_mines_route.lua -- thread the Narshe mines from the banked
-- $023C chase state to the cliff map 23, then take MOG (#133 item 3).
--
-- The (30,22) chase pocket on map 21 is enclosed; its only forward exits
-- (bfs-scanned) are the (30,20) row -> map 43 (108,59) and the way back
-- to town.  Decoded chain to the cliff:
--   21 (30,20)row -> 43 (108,59); 43 door (113,45) -> 41 (58,11);
--   41 doors (107,12)/(117,12) -> 21's TOP pocket (23,10)/(32,10);
--   21 top row (34..37,1) -> 22 (19,39); 22 top row (18..21,1) -> 23.
-- Every hop scans candidates first and logs what is reachable, so a
-- wrong link fails loudly with the data to fix it.
local H = dofile("tools/tests/lib/ot6.lua")
local function sw(bit) return (H.readByte(0x1E80 + (bit >> 3)) >> (bit & 7)) & 1 end
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
local function mogIn()
  return (H.readByte(0x1850 + 10) & 0x07) ~= 0 or sw(0x2FA) == 1
end
local function hop(cands, dir, destMap, tag)
  local tile = nil
  return {
    H.call(function()
      for _, c in ipairs(cands) do
        if H.bfsPath(c[1], c[2]) or (H.fieldX()==c[1] and H.fieldY()==c[2]) then
          tile = c
          H.log(string.format("[%s] approach (%d,%d)", tag, c[1], c[2]))
          return
        end
      end
      local probes = {}
      for _, c in ipairs(cands) do probes[#probes+1] = string.format("(%d,%d)", c[1], c[2]) end
      error(tag .. ": none reachable of " .. table.concat(probes, " "))
    end),
    H.navTo(function() return tile[1] end, function() return tile[2] end,
      { maxFrames = 12000, playBattles = "flee",
        arrive = function() return mapIs(destMap) end }),
    H.driveUntil(function() return mapIs(destMap) end, 1200,
      { H.call(function() H.setPad({ [dir] = true }) end) }, tag),
    H.waitFrames(60),
    H.call(function()
      H.log(string.format("[%s] now map %d at (%d,%d)", tag,
        H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
    end),
  }
end
local function stage(x, y, pred, tag)
  local aPhase, calm = 0, 0
  return {
    H.navTo(x, y, { maxFrames = 9000, playBattles = "flee", arrive = pred }),
    H.driveUntil(function()
      if not pred() then calm = 0; return false end
      return calm >= 60
    end, 6000, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if H.dialogWaiting() then
          calm = 0
          H.setPad(aPhase < 4 and { "a" } or {})
        else
          if pred() and H.hasControl() then calm = calm + 1 end
          H.setPad({})
        end
      end),
    }, tag),
  }
end
local function flatten(t)
  local out = {}
  for _, v in ipairs(t) do
    if type(v) == "table" and v.tick == nil and v[1] ~= nil then
      for _, s in ipairs(v) do out[#out + 1] = s end
    else out[#out + 1] = v end
  end
  return out
end
H.run({ maxFrames = 80000 }, flatten({
  H.loadState("build/states/wob_chase23C.mss.lua"),
  H.waitFrames(8),
  -- back to town, then in through the (22,44) mines door: its 41 pocket
  -- (20,9) is the best candidate link to the (107/117,12) top doors
  hop({{24,52},{25,52},{26,52},{23,52},{27,52},{28,52},{24,51},{25,51}},
      "down", 20, "21 -> town"),
  hop({{22,45},{21,44},{23,44},{22,43},{22,44}}, "up", 41, "town -> 41 north"),
  -- The mines are a designed maze of one-way pockets threading 41<->43
  -- (and possibly 42).  Generic explorer: on each round, if the goal
  -- doors are reachable take them; else take the first unused door for
  -- the CURRENT map from the decoded entrance records.  Teleports are
  -- detected by the position jumping far from both start and target.
  (function()
    local used = {}
    local out = {}
    local function oneRound(r)
      local tile = nil
      return {
        H.call(function()
          local m = H.mapId() & 0x1ff
          if m == 21 then tile = nil; return end   -- reached 21: stop exploring
          local TOP = { {107,12},{106,12},{107,13},{108,12},
                        {117,12},{116,12},{117,13},{118,12} }
          if m == 41 then
            for _, c in ipairs(TOP) do
              if H.bfsPath(c[1], c[2]) then
                tile = c
                H.log(string.format("[maze r%d] 41 TOP door (%d,%d)", r, c[1], c[2]))
                return
              end
            end
          end
          local DOORS = {
            [41] = { {57,11},{58,12},{56,11},{57,12},
                     {41,5},{42,5},{40,5},{43,5},
                     {57,21},{25,59},{18,51},{86,29} },
            [43] = { {75,39},{74,39},{76,39},{75,40},{74,40},{76,40},
                     {111,30},{110,30},{112,30},{111,31},
                     {73,61},{74,61},{72,61},{73,62},
                     {113,45},{113,44},{112,45},
                     {108,60},{109,60},{107,60},
                     {68,48},{69,48},{81,48},{82,48},{70,45},{80,45} },
            [42] = { {86,29},{86,30},{85,29},{87,29} },
          }
          for _, c in ipairs(DOORS[m] or {}) do
            local key = m .. ":" .. c[1] .. "," .. c[2]
            if not used[key] and H.bfsPath(c[1], c[2]) then
              used[key] = true
              tile = c
              H.log(string.format("[maze r%d] map %d door (%d,%d)", r, m, c[1], c[2]))
              return
            end
          end
          for yy = 0, 63, 3 do
            local row = {}
            for xx = 0, 126, 3 do
              row[#row+1] = H.bfsPath(xx, yy) and "O" or "."
            end
            H.log("  chart y" .. yy .. " " .. table.concat(row))
          end
          error(string.format("maze r%d: map %d, nothing new from (%d,%d)",
            r, m, H.fieldX(), H.fieldY()))
        end),
        H.cond(function() return tile ~= nil end, {
          (function()
            local sx, sy, sm = nil, nil, nil
            return H.navTo(function() return tile[1] end,
                           function() return tile[2] end,
              { maxFrames = 12000, playBattles = "flee",
                arrive = function()
                  if sx == nil then sx, sy, sm = H.fieldX(), H.fieldY(), H.mapId() & 0x1ff end
                  local x, y = H.fieldX(), H.fieldY()
                  if (H.mapId() & 0x1ff) ~= sm then return true end
                  local dT = math.abs(x - tile[1]) + math.abs(y - tile[2])
                  local dS = math.abs(x - sx) + math.abs(y - sy)
                  return dT > 15 and dS > 15
                end })
          end)(),
          H.waitFrames(30),
          -- an L-row trigger tile sits one step past the approach: if the
          -- arrival did not teleport us, push into it (up first -- every
          -- decoded row here faces north -- then the other directions)
          (function()
            local m0, x0, y0 = nil, nil, nil
            local pushes = { "up", "left", "right", "down" }
            local pi, pt = 1, 0
            return H.driveUntil(function()
              if m0 == nil then m0, x0, y0 = H.mapId() & 0x1ff, H.fieldX(), H.fieldY() end
              local moved = (H.mapId() & 0x1ff) ~= m0
                or math.abs(H.fieldX() - x0) + math.abs(H.fieldY() - y0) > 10
              return moved or pi > #pushes
            end, 900, {
              H.call(function()
                pt = pt + 1
                if pt % 50 == 0 then pi = pi + 1 end
                H.setPad(pushes[pi] and { [pushes[pi]] = true } or {})
              end),
            }, "maze push r" .. r)
          end)(),
          H.waitFrames(50),
          H.call(function()
            H.log(string.format("[maze r%d] now map %d (%d,%d)", r,
              H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
          end),
        }, {}),
      }
    end
    for r = 1, 12 do
      out[#out+1] = H.cond(function() return not mapIs(21) or true end,
        flatten(oneRound(r)), {})
    end
    return out
  end)(),
  hop({{35,2},{34,2},{36,2},{37,2},{35,3},{34,3},{36,3},{37,3}},
      "up", 22, "21 -> 22"),
  hop({{19,2},{18,2},{20,2},{21,2},{19,3},{18,3},{20,3},{21,3}},
      "up", 23, "22 -> 23"),
  stage(22, 20, function() return sw(0x23D) == 1 end, "the standoff [$023D]"),
  stage(8, 18, function() return sw(0x23F) == 1 end, "the ledge [$023F]"),
  H.navTo(9, 17, { maxFrames = 6000, playBattles = "flee" }),
  (function()
    local t, talked = 0, false
    return H.driveUntil(function() return mogIn() end, 9000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then talked = true end
        if talked then
          H.setPad(t % 24 < 3 and { "a" } or {})
        else
          H.setPad(t % 30 < 3 and { up = true, a = true } or { up = true })
        end
      end),
    }, "MOG joins")
  end)(),
  H.call(function()
    H.log("MOG RECRUITED")
    H.screenshot("mog_joined")
  end),
  H.saveState("wob_mog_done.mss"),
  H.logStep(function() return "done" end),
}))
