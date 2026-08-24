-- probe_fc_descent.lua -- #132 segment 2: cross the Floating Continent
-- (map 394) from the IAF landing to the encounter-free save alcove
-- (358).  Boots fc_land.mss.  The descent is a chain of mod_bg_tiles
-- stair-reveal triggers, driven empirically: step the nearest reachable
-- un-visited trigger, let it reveal, re-scan.  AVOIDED: (70,29) (the
-- "return to the airship?" choice -- the Shadow-posing detour, a later
-- probe) and (60,11) (the AtmaWeapon approach).  Fights: tactical (the
-- 177-188 pool permits pincers; Behemoth/Dragon are real fights).
-- Saves fc_alcove.mss on 358.
local H = dofile("tools/tests/lib/ot6.lua")
local function mapIs(m) return (H.mapId() & 0x3ff) == m end
local function flatten(t)
  local out = {}
  for _, v in ipairs(t) do
    if type(v) == "table" and v.tick == nil and v[1] ~= nil then
      for _, s in ipairs(v) do out[#out + 1] = s end
    else out[#out + 1] = v end
  end
  return out
end
local TRIGGERS = {
  {19,12},{25,19},{40,12},{40,6},{32,16},{44,11},{36,28},{67,39},
  {42,17},{40,24},{63,31},{48,22},{77,31},{52,24},{59,39},{82,30},
  {63,28},{89,25},{70,23},{90,43},
}
local AVOID = { {70,29},{60,11} }
local visited = {}
local burst = nil
local stuckN = 0
local preBurst = nil
local function key(c) return c[1] .. "," .. c[2] end
local function round(r)
  local tile = nil
  return H.cond(function() return mapIs(394) end, flatten({
    -- care between legs: the pool's Behemoths/Dragons are long fights
    -- and a wounded party entering the next one dies (measured r7)
    H.cond(function()
      if not mapIs(394) then return false end
      for _, c in ipairs(H.partyMembers()) do
        if H.charHp(c) < H.charMaxHp(c) * 0.7 then return true end
      end
      return false
    end, { H.fieldCare({ tag = "fc-care r" .. r, threshold = 0.8 }) }, {}),
    H.call(function()
      tile = nil
      local best, bd = nil, 1e9
      for _, c in ipairs(TRIGGERS) do
        if not visited[key(c)] then
          local p = H.bfsPath(c[1], c[2], nil, nil)
          if p then
            if #p < bd then bd, best = #p, c end
          end
        end
      end
      if best then
        tile = best
        H.log(string.format("[fc r%d] trigger (%d,%d) dist=%d", r,
          best[1], best[2], bd))
      else
        -- bfs-blind reveal (z-stairs, the session's recurring blind
        -- spot): burst-walk toward the nearest un-visited trigger
        local cands = {}
        for _, c in ipairs(TRIGGERS) do
          if not visited[key(c)] then
            local dx = c[1] - H.fieldX()
            local dy = c[2] - H.fieldY()
            cands[#cands+1] = { c, dx * dx + dy * dy }
          end
        end
        if #cands == 0 then error("fc r" .. r .. ": all triggers visited, not on 358") end
        table.sort(cands, function(a, b) return a[2] < b[2] end)
        if preBurst ~= nil and preBurst ~= H.fieldX() * 256 + H.fieldY() then
          stuckN = 0        -- the last burst moved us: progress
        end
        preBurst = H.fieldX() * 256 + H.fieldY()
        stuckN = stuckN + 1
        -- rotate the target by stuck count so a walled-off nearest
        -- trigger doesn't monopolize the bursts
        burst = cands[((stuckN - 1) % #cands) + 1][1]
        H.log(string.format("[fc r%d] no bfs frontier from (%d,%d); burst toward (%d,%d) (stuck %d)",
          r, H.fieldX(), H.fieldY(), burst[1], burst[2], stuckN))
        if stuckN >= 5 then
          -- ground truth for the offline solver: live tile props
          local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
          H.log(string.format("m394 masks xm=%02X ym=%02X party=(%d,%d) z=%02X",
            xm, ym, H.fieldX(), H.fieldY(), H.readByte(0xb2)))
          local function tp(base, x, y)
            local tl = H.readByte(0x7F0000 + (y & ym) * 256 + (x & xm))
            return H.readByte(base + tl)
          end
          for y = 0, ym do
            local r1, r2, r3 = {}, {}, {}
            for x = 0, xm do
              r1[#r1+1] = string.format("%02x", tp(0x7E7600, x, y))
              r2[#r2+1] = string.format("%02x", tp(0x7E7700, x, y))
              r3[#r3+1] = (H.readByte(0x7E2000 + (y & 0xFF) * 256 + (x & 0xFF)) & 0x80) == 0
                and "X" or "."
            end
            H.log(string.format("p1 y%02d %s", y, table.concat(r1)))
            H.log(string.format("p2 y%02d %s", y, table.concat(r2)))
            H.log(string.format("nb y%02d %s", y, table.concat(r3)))
          end
          error(string.format("fc r%d: descent stalled", r))
        end
      end
    end),
    -- the burst: long axis-major holds toward the target, rotating on
    -- stall, until displaced >=3 tiles or a battle interrupts
    H.cond(function() return tile == nil and burst ~= nil end, {
      (function()
        local t2, x0, y0, di, still, lastPos = 0, nil, nil, 1, 0, nil
        local dirs = { "right", "down", "left", "up" }
        return H.driveUntil(function()
          if x0 == nil then x0, y0 = H.fieldX(), H.fieldY() end
          if t2 >= 2200 then return true end
          if math.abs(H.fieldX() - x0) + math.abs(H.fieldY() - y0) >= 3 then return true end
          -- early stop the moment any un-visited trigger becomes pathable
          if t2 % 64 == 0 and t2 > 0 then
            for _, c in ipairs(TRIGGERS) do
              if not visited[key(c)] and H.bfsPath(c[1], c[2], nil, nil) then
                return true
              end
            end
          end
          return false
        end, 2500, {
          H.call(function()
            t2 = t2 + 1
            if H.dialogWaiting() then H.setPad(t2 % 16 < 4 and { "a" } or {}); return end
            if H.battleLoadStarted() or H.battleActive() then H.setPad({}); return end
            local pos = H.fieldX() * 256 + H.fieldY()
            if pos ~= lastPos then lastPos = pos; still = 0 else still = still + 1 end
            local dx = burst[1] - H.fieldX()
            local dy = burst[2] - H.fieldY()
            local d = math.abs(dx) >= math.abs(dy)
              and (dx > 0 and "right" or "left")
              or (dy > 0 and "down" or "up")
            if still > 300 then di = di % #dirs + 1; still = 0; lastPos = nil end
            if di > 1 then d = dirs[di] end
            H.setPad({ [d] = true })
          end),
        }, "burst r" .. r)
      end)(),
      H.release(),
      H.waitFrames(30),
      H.call(function() burst = nil end),
    }, {}),
    -- the party can be moved between scan and walk (trigger events,
    -- battles); re-verify at execution time and defer instead of dying
    H.cond(function()
      return tile ~= nil and H.bfsPath(tile[1], tile[2], nil, nil) ~= nil
    end, {
      -- arrive-latch: several triggers are scripted chutes that seize
      -- control and slide the party away the moment the tile is
      -- touched; finish the walk on first touch and let the settle
      -- rider absorb the ride
      (function()
        local near = false
        return H.navTo(function() return tile[1] end, function() return tile[2] end,
          { maxFrames = 20000, playBattles = "flee", magic = { [0x07] = { spell = 2 } }, avoid = AVOID,
            arrive = function()
              if H.fieldX() == tile[1] and H.fieldY() == tile[2] then
                near = true
              end
              return near
            end })
      end)(),
      H.call(function() visited[key(tile)] = true; stuckN = 0 end),
    }, {
      H.call(function()
        H.log(string.format("  deferred (%s): unreachable at walk time", tile and key(tile) or "-"))
        tile = nil
      end),
    }),
    -- ride whatever the trigger does; choices steered to the LAST row
    -- (cancel) via the closed-loop $056E/$056F readout, defensively
    (function()
      local t, calm = 0, 0
      return H.driveUntil(function()
        if not mapIs(394) then return true end
        if not H.hasControl() or H.dialogWaiting() then calm = 0; return false end
        calm = calm + 1
        return calm >= 40
      end, 4000, {
        H.call(function()
          t = t + 1
          local mx = H.readByte(0x056F)
          if mx > 0 then
            local sel = H.readByte(0x056E)
            local ph = t % 24
            if sel < mx then H.setPad(ph < 3 and { down = true } or {})
            else H.setPad((ph >= 12 and ph < 15) and { "a" } or {}) end
            return
          end
          if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {})
          else H.setPad({}) end
        end),
      }, "trigger settles r" .. r)
    end)(),
    H.waitFrames(20),
    H.call(function()
      H.log(string.format("[fc r%d] after (%s): map %d (%d,%d)", r,
        tile and key(tile) or "-", H.mapId() & 0x3ff, H.fieldX(), H.fieldY()))
      if tile ~= nil then
        local d = math.abs(H.fieldX() - tile[1]) + math.abs(H.fieldY() - tile[2])
        if d >= 4 then
          for _, c in ipairs(TRIGGERS) do
            if not visited[key(c)]
               and math.abs(c[1] - H.fieldX()) + math.abs(c[2] - H.fieldY()) <= 2 then
              visited[key(c)] = true
              H.log(string.format("  chute twin (%s) marked visited", key(c)))
            end
          end
        end
      end
    end),
  }), {})
end

H.run({ maxFrames = 200000 }, flatten({
  H.loadState("build/states/fc_land.mss.lua"),
  H.waitFrames(60),
  (function()
    local t = 0
    return H.driveUntil(function()
      return H.hasControl() and not H.dialogWaiting()
    end, 3000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "arrival settles")
  end)(),
  H.call(function()
    H.log(string.format("FC landing: map %d (%d,%d)", H.mapId() & 0x3ff,
      H.fieldX(), H.fieldY()))
    H.screenshot("fc_landing")
  end),
  (function()
    local out = {}
    for r = 1, 30 do out[#out+1] = round(r) end
    return out
  end)(),
  H.call(function()
    H.assertEq(mapIs(358), true, "reached the save alcove (map 358)")
    H.screenshot("fc_alcove")
  end),
  H.navTo(8, 10, { maxFrames = 4000 }),
  H.saveState("fc_alcove.mss"),
  H.logStep(function() return "done" end),
}))
