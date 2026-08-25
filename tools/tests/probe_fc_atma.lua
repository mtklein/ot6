-- probe_fc_atma.lua -- #132 segment 3: AtmaWeapon.  Boots fc_alcove2
-- (Shadow in party, at the 358 save point).  Exit to 394 (90,42), walk
-- to the (60,11) approach (the fixture carries every stair reveal, so
-- plain navTo should path), ride CATASTROPHE, fight battle 80 (form
-- 450, AtmaWeapon: 11 pips, slash|pierce, bolt-weak).  A loss is a
-- real Game Over -- honest.  Saves fc_atma_down.mss on the win.
local H = dofile("tools/tests/lib/ot6.lua")
local function mapIs(m) return (H.mapId() & 0x3ff) == m end
local F = H.newFightDriver("atma", { tactical = true, boost = true, bank = 3,
  items = true, healPercent = 60, magic = { [0x07] = { spell = 2 } } })
local seen, lastActive = false, false
H.run({ maxFrames = 120000 }, {
  H.loadState("build/states/fc_shadow.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("on 394 at (%d,%d)", H.fieldX(), H.fieldY()))
  end),
  -- to the approach: the CATASTROPHE trigger at (60,11).  The alcove
  -- door area is a bfs pocket, so this is the descent's frontier/burst
  -- machinery pointed at (60,12): waypoints when reachable, bursts
  -- toward the goal when bfs is blind.
  (function()
    -- the normal descent prefix; each round first checks whether the
    -- (60,12) plateau has become pathable
    -- the decoded approach: the descent prefix to the (40,24) tunnel
    -- (lands (63,31)), then (63,28) -- its reveal is the plateau ladder
    -- at (63,25-27), the ONLY entry to Atma's hermetic component
    local WPS = { {19,12},{25,19},{40,12},{44,11},{40,6},{36,28},{67,39},{40,24},{63,28} }
    local visited, out = {}, {}
    local wedgePos = nil
    local wedgeN = 0
    local function key(c) return c[1] .. "," .. c[2] end
    for r = 1, 45 do
      local tile = nil
      -- hard-wedge retry: an off-grid party (movement AND menu refused)
      -- only realigns on a state load.  Two wedged rounds -> reload the
      -- checkpoint and re-walk on a shifted RNG timeline.
      out[#out+1] = H.cond(function() return wedgeN >= 2 end, {
        H.call(function()
          H.log(string.format("[atma r%d] WEDGED at (%d,%d): reloading the checkpoint",
            r, H.fieldX(), H.fieldY()))
          visited = {}
          wedgeN = 0
          wedgePos = nil
        end),
        H.loadState("build/states/fc_shadow.mss.lua"),
        H.waitFrames(90 + (r % 7) * 17),
      }, {})
      out[#out+1] = H.cond(function()
        return mapIs(394) and not (H.fieldX() == 60 and H.fieldY() == 12)
          and H.bfsPath(60, 12, nil, nil) == nil
      end, {
        H.call(function()
          tile = nil
          local best, bd = nil, 1e9
          for _, c in ipairs(WPS) do
            if not visited[key(c)] then
              local p = H.bfsPath(c[1], c[2], nil, nil)
              if p and #p < bd then bd, best = #p, c end
            end
          end
          tile = best
          if best then
            H.log(string.format("[atma r%d] at (%d,%d): waypoint (%s) dist=%d",
              r, H.fieldX(), H.fieldY(), key(best), bd))
          else
            H.log(string.format("[atma r%d] no waypoint; burst toward (60,12) from (%d,%d)",
              r, H.fieldX(), H.fieldY()))
          end
        end),
        H.cond(function() return tile ~= nil end, {
          (function()
            local near, px, py, nchk = false, nil, nil, 0
            return H.navTo(function() return tile[1] end, function() return tile[2] end,
              { maxFrames = 20000, playBattles = "tactical",
                magic = { [0x07] = { spell = 2, boost = false } },
                avoid = { {70,29}, {90,43}, {60,11} },
                arrive = function()
                  local x, y = H.fieldX(), H.fieldY()
                  if x == tile[1] and y == tile[2] then near = true end
                  -- a chute ride mid-walk (>=4-tile jump) also ends the
                  -- leg: the next round rescans from the landing
                  if px and math.abs(x - px) + math.abs(y - py) >= 4 then near = true end
                  px, py = x, y
                  -- and if the target stopped being pathable (a slide
                  -- navTo's jump-poll missed), bail rather than letting
                  -- the no-path retries hard-fail the run
                  nchk = (nchk or 0) + 1
                  if nchk % 48 == 0
                     and H.bfsPath(tile[1], tile[2], nil, nil) == nil then
                    near = true
                  end
                  return near
                end })
          end)(),
          H.call(function() visited[key(tile)] = true end),
          H.waitFrames(30),
        }, {
          -- wedge recovery first: a tile where no direction moves for a
          -- whole round is usually fine-position desync; a menu
          -- open/close realigns the walker
          (function()
            local t3, opened = 0, false
            return H.cond(function()
              return wedgePos == H.fieldX() * 256 + H.fieldY()
            end, {
              H.driveUntil(function()
                t3 = t3 + 1
                if H.readByte(0x26) == 0x05 then opened = true end
                return t3 >= 700 or (opened and H.readByte(0x26) ~= 0x05)
              end, 1000, {
                H.call(function()
                  if not opened then H.setPad(t3 % 12 < 4 and { "x" } or {})
                  else H.setPad(t3 % 12 < 4 and { "b" } or {}) end
                end),
              }, "wedge jiggle r" .. r),
              H.release(),
              H.waitFrames(30),
            }, {})
          end)(),
          H.call(function()
            local pos = H.fieldX() * 256 + H.fieldY()
            if pos == wedgePos then wedgeN = wedgeN + 1 else wedgeN = 0 end
            wedgePos = pos
          end),
          (function()
            local t2, x0, y0, di, still, lastPos = 0, nil, nil, 1, 0, nil
            local dirs = { "left", "up", "down", "right" }
            return H.driveUntil(function()
              if x0 == nil then x0, y0 = H.fieldX(), H.fieldY() end
              if t2 >= 2200 then return true end
              if math.abs(H.fieldX() - x0) + math.abs(H.fieldY() - y0) >= 3 then return true end
              if t2 % 64 == 0 and t2 > 0 and H.bfsPath(60, 12, nil, nil) then return true end
              return false
            end, 2500, {
              H.call(function()
                t2 = t2 + 1
                if H.dialogWaiting() then H.setPad(t2 % 16 < 4 and { "a" } or {}); return end
                if H.battleLoadStarted() or H.battleActive() then H.setPad({}); return end
                local pos = H.fieldX() * 256 + H.fieldY()
                if pos ~= lastPos then lastPos = pos; still = 0 else still = still + 1 end
                local dx, dy = 60 - H.fieldX(), 12 - H.fieldY()
                local d = math.abs(dx) >= math.abs(dy)
                  and (dx > 0 and "right" or "left")
                  or (dy > 0 and "down" or "up")
                if still > 300 then di = di % #dirs + 1; still = 0; lastPos = nil end
                if di > 1 then d = dirs[di] end
                H.setPad({ [d] = true })
              end),
            }, "atma burst r" .. r)
          end)(),
          H.release(),
          H.waitFrames(30),
        }),
      }, {})
    end
    return H.cond(function() return true end, out, {})
  end)(),
  H.cond(function() return H.bfsPath(60, 12, nil, nil) ~= nil end, {
    H.navTo(60, 12, { maxFrames = 20000, playBattles = "tactical",
      magic = { [0x07] = { spell = 2, boost = false } },
      avoid = { {70,29}, {90,43}, {60,11} } }),
  }, {}),
  H.call(function()
    H.log(string.format("approach parked at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("atma_approach")
  end),
  (function()
    local t = 0
    return H.driveUntil(function()
      return H.battleActive() or H.battleLoadStarted()
    end, 8000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({ up = true })
      end),
    }, "CATASTROPHE -> battle 80")
  end)(),
  (function()
    local t = 0
    return H.driveUntil(function()
      if H.battleActive() then seen = true end
      return seen and not H.battleActive() and not H.battleLoadStarted()
    end, 60000, {
      H.call(function()
        t = t + 1
        if t == 90 then
          local f = H.formationWords()
          H.log(string.format("ATMA fight: species=%s",
            table.concat({ f[1] or "?", f[2] or "?", f[3] or "?" }, ",")))
        end
        F.frame()
      end),
    }, "AtmaWeapon falls")
  end)(),
  H.waitFrames(120),
  H.call(function()
    local hp = {}
    for _, c in ipairs(H.partyMembers()) do hp[#hp+1] = H.charHp(c) end
    H.log(string.format("post-Atma: map=%d (%d,%d) hp=%s",
      H.mapId() & 0x3ff, H.fieldX(), H.fieldY(), table.concat(hp, "/")))
    H.screenshot("atma_down")
    H.assertEq(mapIs(394), true, "still on 394 (not a Game Over)")
  end),
  H.saveState("fc_atma_down.mss"),
  H.logStep(function() return "done" end),
})
