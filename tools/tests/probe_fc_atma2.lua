-- probe_fc_atma2.lua -- #132 segment 2: cross the Floating Continent
-- (map 394) from the IAF landing to the encounter-free save alcove
-- (358).  Boots fc_land.mss.  The descent is a chain of mod_bg_tiles
-- stair-reveal triggers, driven empirically: step the nearest reachable
-- un-visited trigger, let it reveal, re-scan.  AVOIDED: (70,29) (the
-- "return to the airship?" choice -- the Shadow-posing detour, a later
-- probe) and (60,11) (the AtmaWeapon approach).  Fights: tactical (the
-- 177-188 pool permits pincers; Behemoth/Dragon are real fights).
-- Saves fc_alcove.mss on 358.
local H = dofile("tools/tests/lib/ot6.lua")
local FA = H.newFightDriver("atma", { tactical = true, boost = true, bank = 3,
  items = true, healPercent = 60, magic = { [0x07] = { spell = 2 } } })
local atmaDone = false
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
-- the proven direct path only: the (89,25) chute and the whole (70,x)
-- pocket are the pre-Shadow detour -- riding them post-Shadow dead-ends
-- against the avoided (70,29)
local TRIGGERS = {
  {19,12},{25,19},{40,12},{44,11},{40,6},{36,28},{67,39},
  {40,24},{59,39},{52,24},{82,30},{89,25},
}
-- (70,29): the return prompt's Yes-with-Shadow branch is the
-- scripted Shadow REMOVAL (_cad9fc) -- never step it on this crossing
local AVOID = { {60,11}, {70,29} }
local visited = {}
local burst = nil
local stuckN = 0
local preBurst = nil
local function key(c) return c[1] .. "," .. c[2] end
local function rd(a) return emu.read(a, emu.memType.snesMemory) end
local function midx() return H.readByte(0x4b) + H.readByte(0x4a) + H.readByte(0x5a) end
local function charAt(i) return rd(0x7e9d89 + i) end
local function grpCount() local n=0; for i=0,3 do if rd(0x7e9d99+i)~=0xFF then n=n+1 end end; return n end
local function firstEmptyGroupSlot() for _,i in ipairs({0x10,0x11,0x12,0x13}) do if charAt(i)==0xFF then return i end end end
local function inGroup(c) for i=0,3 do if rd(0x7e9d99+i)==c then return true end end; return false end
local function nextTarget() for _,c in ipairs({0x00,0x01,0x07}) do if not inGroup(c) then return c end end end
local shadowIn = true      -- boots from fc_shadow.mss
local banked = true        -- no re-bank; the goal is the alcove
local function deckPhase(r)
  -- the (70,29) "return?" Yes lands us on the Blackjack deck with
  -- $035E set (Shadow posed).  Wheel right+A, steer dlg $0527 to row 0
  -- ("Find the Floating Continent" -- with $00A0=1 this is the quick
  -- re-arrival, no IAF), then talk Shadow into the party at (10,16).
  local t2 = 0
  local pcPhase, pcDir, pcLastIdx, pcLastBtn, pcProbe, pcProbeN = 0, {}, nil, nil, 0, 0
  return H.cond(function() return mapIs(6) and not atmaDone end, {
    H.navTo(14, 6, { maxFrames = 4000,
      arrive = function() return not H.hasControl() or H.dialogWaiting() end }),
    H.driveUntil(function() return mapIs(394) end, 8000, {
      H.call(function()
        t2 = t2 + 1
        -- "Find the FC" reruns the 3-char party select before the
        -- $00A0 re-entry branch: drive it (probe_iaf_fight3's learned-
        -- button builder, condensed)
        local ms = H.readByte(0x26)
        if not H.hasControl() and ms >= 0x2c and ms <= 0x2f then
          pcPhase = (pcPhase + 1) % 9
          local function tap(btn) H.setPad(pcPhase < 3 and { btn } or {}) end
          if ms == 0x2d then
            if grpCount() >= 3 then tap("start")
            elseif H.readByte(0x4a) ~= 0 then tap("up")
            else
              local tgt = nil
              for i = 0, 15 do
                local c = charAt(i)
                if (c==0x00 or c==0x01 or c==0x07) and not inGroup(c)
                   and rd(0x7eac8d + i) < 0x80 then tgt = i; break end
              end
              local cur = midx()
              if not tgt then tap("b")
              elseif cur == tgt then tap("a")
              else
                local want = (cur < tgt) and "inc" or "dec"
                if pcLastIdx ~= nil and cur ~= pcLastIdx and pcLastBtn then
                  pcDir[(cur > pcLastIdx) and "inc" or "dec"] = pcLastBtn
                end
                local btn = pcDir[want]
                if not btn then
                  btn = ({"down","up","right","left"})[(pcProbe % 4) + 1]
                  pcProbeN = pcProbeN + 1
                  if pcProbeN % 14 == 0 then pcProbe = pcProbe + 1 end
                end
                pcLastIdx, pcLastBtn = cur, btn
                tap(btn)
              end
            end
          elseif ms == 0x2e then
            if H.readByte(0x4a) ~= 0x10 then tap("down")
            else
              local tgt = firstEmptyGroupSlot()
              if not tgt then tap("a")
              else
                local cc, cr = (midx() >> 1) & 1, midx() & 1
                local tc, tr = (tgt >> 1) & 1, tgt & 1
                if cc < tc then tap("right") elseif cc > tc then tap("left")
                elseif cr < tr then tap("down") elseif cr > tr then tap("up")
                else tap("a") end
              end
            end
          else tap("b") end
          return
        end
        if t2 % 900 == 0 then
          H.log(string.format("  deck t=%d map=%d (%d,%d) ctrl=%s dlg=%s 56F=%02X d0=%04X world=%s",
            t2, H.mapId() & 0x3ff, H.fieldX(), H.fieldY(),
            tostring(H.hasControl()), tostring(H.dialogWaiting()),
            H.readByte(0x056F), H.readWord(0x00d0), tostring(H.worldMode())))
        end
        if t2 == 4000 then H.screenshot("deck4000") end
        local mx = H.readByte(0x056F)
        if mx > 0 then
          local sel = H.readByte(0x056E)
          local ph = t2 % 24
          if sel > 0 then H.setPad(ph < 3 and { up = true } or {})
          else H.setPad((ph >= 12 and ph < 15) and { "a" } or {}) end
          return
        end
        if H.dialogWaiting() then H.setPad(t2 % 16 < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        -- the wheel gate needs RIGHT+A held ON (14,6); anywhere else,
        -- walk there (blind holds are what wandered us into the ship)
        if H.fieldX() == 14 and H.fieldY() == 6 then
          H.setPad({ right = true, a = true })
        else
          local dx, dy = 14 - H.fieldX(), 6 - H.fieldY()
          local d = math.abs(dx) >= math.abs(dy)
            and (dx > 0 and "right" or "left")
            or (dy > 0 and "down" or "up")
          H.setPad({ [d] = true })
        end
      end),
    }, "re-enter the FC r" .. r),
    H.waitFrames(90),
    -- Shadow stands at (10,16); (10,17) is not walkable -- approach
    -- from whichever adjacent tile paths, face him, tap A (the Mog-take
    -- pattern: face-taps can step, so re-aim each cycle)
    (function()
      local t3 = 0
      local cands = { {10,17,"up"}, {9,16,"right"}, {11,16,"left"}, {10,15,"down"} }
      local ci = 1
      return H.driveUntil(function()
        if (H.readByte(0x1850 + 3) & 0x07) ~= 0 then shadowIn = true end
        return shadowIn
      end, 12000, {
        H.call(function()
          t3 = t3 + 1
          if H.dialogWaiting() then H.setPad(t3 % 24 < 3 and { "a" } or {}); return end
          if H.battleLoadStarted() or H.battleActive() then H.setPad({}); return end
          if not H.hasControl() then H.setPad({}); return end
          local c = cands[ci]
          local dx, dy = c[1] - H.fieldX(), c[2] - H.fieldY()
          if dx == 0 and dy == 0 then
            local ph = t3 % 40
            if ph < 2 then H.setPad({ [c[3]] = true })
            elseif ph >= 10 and ph < 14 then H.setPad({ "a" })
            elseif ph == 39 then ci = ci % #cands + 1; H.setPad({})
            else H.setPad({}) end
          else
            local d = math.abs(dx) >= math.abs(dy)
              and (dx > 0 and "right" or "left")
              or (dy > 0 and "down" or "up")
            H.setPad({ [d] = true })
            if t3 % 300 == 299 then ci = ci % #cands + 1 end
          end
        end),
      }, "SHADOW joins r" .. r)
    end)(),
    H.call(function()
      H.log(string.format("[fc r%d] SHADOW aboard: party byte=%02X", r,
        H.readByte(0x1850 + 3)))
      -- the descent re-walks from the landing: un-mark the path so the
      -- chutes can be re-ridden (reveal triggers re-step as no-ops;
      -- (70,29) is latched inert)
      visited = {}
      stuckN = 0
    end),
  }, {})
end
local function round(r)
  local tile = nil
  return H.cond(function() return mapIs(394) and not atmaDone end, flatten({
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
        -- the 358 door is gated on Shadow: stepping (90,43) latches
        -- $01B5, which also kills the (70,29) return prompt that poses
        -- him -- AtmaWeapon forces Shadow, so he comes first
        local gated = (key(c) == "90,43") and not shadowIn
        if not visited[key(c)] and not gated then
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
          local gated = (key(c) == "90,43") and not shadowIn
          if not visited[key(c)] and not gated then
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
              local gated = (key(c) == "90,43") and not shadowIn
              if not visited[key(c)] and not gated
                 and H.bfsPath(c[1], c[2], nil, nil) then
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
          { maxFrames = 20000, playBattles = "flee", magic = { [0x07] = { spell = 2, boost = false } }, avoid = AVOID,
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
      end, 15000, {
        H.call(function()
          t = t + 1
          if t % 1200 == 0 then
            H.log(string.format("  settle t=%d map=%d (%d,%d) ctrl=%s dlg=%s 56F=%02X 56E=%02X",
              t, H.mapId() & 0x3ff, H.fieldX(), H.fieldY(),
              tostring(H.hasControl()), tostring(H.dialogWaiting()),
              H.readByte(0x056F), H.readByte(0x056E)))
          end
          if t == 6000 then H.screenshot("settle6000") end
          local mx = H.readByte(0x056F)
          if mx > 0 then
            -- $056F is the choice COUNT; the last row is mx-1
            local want = mx - 1
            local sel = H.readByte(0x056E)
            local ph = t % 24
            if sel < want then H.setPad(ph < 3 and { down = true } or {})
            elseif sel > want then H.setPad(ph < 3 and { up = true } or {})
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
              if key(c) ~= "63,28" then
                visited[key(c)] = true
                H.log(string.format("  chute twin (%s) marked visited", key(c)))
              end
            end
          end
        end
      end
    end),
  }), {})
end

H.run({ maxFrames = 200000 }, flatten({
  H.loadState("build/states/fc_shadow.mss.lua"),
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
    for r = 1, 40 do
      out[#out+1] = deckPhase(r)
      out[#out+1] = H.cond(function()
        return shadowIn and not banked and mapIs(394)
      end, {
        H.waitFrames(60),
        H.waitFrames(1),
        H.call(function() banked = true end),
      }, {})
      out[#out+1] = round(r)
      -- the Atma diversion: when the (40,24) tunnel has landed us in
      -- the (63,3x) pocket, (63,28) is pathable -- step it (the ladder
      -- reveal), climb to the plateau, ride CATASTROPHE, fight
      out[#out+1] = H.cond(function()
        return not atmaDone and mapIs(394)
          and H.fieldX() >= 43 and H.fieldX() <= 46
          and H.fieldY() >= 9 and H.fieldY() <= 12
      end, {
        -- the north route: up from the (44,11) region to the y4 z0
        -- corridor, east across the (57,4) bridge into the plateau's
        -- north room, then south to the approach
        (function()
          local wps = { {44,9},{43,5},{45,4},{50,4},{54,4},{56,4},{58,4},
                        {60,5},{60,8},{60,11} }
          local wi, t6, wt = 1, 0, 0
          return H.driveUntil(function()
            t6 = t6 + 1
            return t6 >= 9000
              or (math.abs(H.fieldX() - 60) <= 1 and H.fieldY() <= 12)
          end, 10000, {
            H.call(function()
              if t6 % 1200 == 0 then
                H.log(string.format("  north t=%d at (%d,%d) wp=%d", t6,
                  H.fieldX(), H.fieldY(), wi))
              end
              if t6 == 6000 then H.screenshot("north6000") end
              if H.dialogWaiting() then H.setPad(t6 % 16 < 4 and { "a" } or {}); return end
              if H.battleLoadStarted() or H.battleActive() then H.setPad({}); return end
              if not H.hasControl() then H.setPad({}); return end
              local wp = wps[wi]
              if not wp then H.setPad({ up = true }); return end
              local dx, dy = wp[1] - H.fieldX(), wp[2] - H.fieldY()
              wt = wt + 1
              if (dx == 0 and dy == 0) or wt > 900 then
                wi, wt = wi + 1, 0
                H.setPad({})
                return
              end
              local d = math.abs(dx) >= math.abs(dy)
                and (dx > 0 and "right" or "left")
                or (dy > 0 and "down" or "up")
              H.setPad({ [d] = true })
            end),
          }, "north bridge to the approach")
        end)(),
        H.release(),
        H.waitFrames(90),
        -- the revealed ladder ((63,25-27), tile $1F) is bfs-blind like
        -- every climb tile: blind hold up to the plateau tip
        (function()
          local t7 = 0
          return H.driveUntil(function()
            t7 = t7 + 1
            return t7 >= 1500 or H.fieldY() <= 24
          end, 2000, {
            H.call(function()
              if H.dialogWaiting() then H.setPad(t7 % 16 < 4 and { "a" } or {}); return end
              H.setPad({ up = true })
            end),
          }, "climb the ladder")
        end)(),
        H.release(),
        H.waitFrames(60),
        H.call(function()
          local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
          local function tp(x, y)
            local tl = H.readByte(0x7F0000 + (y & ym) * 256 + (x & xm))
            return string.format("%02x/%02x", H.readByte(0x7E7600 + tl), tl)
          end
          H.log(string.format("ladder probe at (%d,%d): (63,25)=%s (63,26)=%s (63,27)=%s (63,28)=%s $1FB-era=%d",
            H.fieldX(), H.fieldY(), tp(63,25), tp(63,26), tp(63,27), tp(63,28),
            (H.readByte(0x1E80 + (0x1FB >> 3)) >> (0x1FB & 7)) & 1))
          H.screenshot("ladder_probe")
        end),
        -- plateau interior: live bfs is z-blind off the ladder; blind
        -- waypoint walk up the west arm to the approach at (60,12)
        (function()
          local wps = { {62,24},{60,22},{58,20},{57,17},{58,14},{60,12} }
          local wi, t8, wt = 1, 0, 0
          return H.driveUntil(function()
            t8 = t8 + 1
            return t8 >= 6000
              or (H.fieldX() == 60 and H.fieldY() == 12)
          end, 7000, {
            H.call(function()
              if H.dialogWaiting() then H.setPad(t8 % 16 < 4 and { "a" } or {}); return end
              if H.battleLoadStarted() or H.battleActive() then H.setPad({}); return end
              local wp = wps[wi]
              if not wp then H.setPad({ up = true }); return end
              local dx, dy = wp[1] - H.fieldX(), wp[2] - H.fieldY()
              wt = wt + 1
              if (dx == 0 and dy == 0) or wt > 900 then
                wi, wt = wi + 1, 0
                H.setPad({})
                return
              end
              local d = math.abs(dx) >= math.abs(dy)
                and (dx > 0 and "right" or "left")
                or (dy > 0 and "down" or "up")
              H.setPad({ [d] = true })
            end),
          }, "plateau walk to (60,12)")
        end)(),
        H.release(),
        H.waitFrames(30),
        H.cond(function()
          return H.fieldY() <= 16 and math.abs(H.fieldX() - 60) <= 3
        end, {
          H.call(function() H.screenshot("atma_approach") end),
          (function()
            local t4 = 0
            return H.driveUntil(function()
              return H.battleActive() or H.battleLoadStarted()
            end, 8000, {
              H.call(function()
                t4 = t4 + 1
                if H.dialogWaiting() then H.setPad(t4 % 16 < 4 and { "a" } or {}); return end
                if not H.hasControl() then H.setPad({}); return end
                H.setPad({ up = true })
              end),
            }, "CATASTROPHE -> battle 80")
          end)(),
          (function()
            local t5, seenB = 0, false
            return H.driveUntil(function()
              if H.battleActive() then seenB = true end
              return seenB and not H.battleActive() and not H.battleLoadStarted()
            end, 90000, {
              H.call(function()
                t5 = t5 + 1
                if t5 == 90 then
                  local f = H.formationWords()
                  H.log(string.format("ATMA fight: species=%s",
                    table.concat({ f[1] or "?", f[2] or "?", f[3] or "?" }, ",")))
                end
                FA.frame()
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
            atmaDone = true
          end),
        }, {}),
      }, {})
    end
    return out
  end)(),
  H.call(function()
    H.assertEq(atmaDone, true, "AtmaWeapon fought (no Game Over)")
    H.assertEq((H.mapId() & 0x3ff) == 394, true, "still on 394")
  end),
  H.saveState("fc_atma_down.mss"),
  H.logStep(function() return "done" end),
}))
