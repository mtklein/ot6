-- probe_cliff43_east.lua -- angle A on the Mog route: map 43's entry
-- column crosses y=45, and the door (113,45)->41 (58,11) sits just east
-- of it.  Climbs 43's entry column to y~45 and bursts east; if that
-- fails, crosses to the (73,60) side and bursts up at the (73-75,39) top.
-- On entering 41, frontier-climbs east to the top doors (107,12)/(117,12)
-- -> 21 top pocket -> 22 -> 23 -> Mog.  Saves wob_mog_done.mss.
local H = dofile("tools/tests/lib/ot6.lua")
local function sw(bit) return (H.readByte(0x1E80 + (bit >> 3)) >> (bit & 7)) & 1 end
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
local function mogIn()
  return (H.readByte(0x1850 + 10) & 0x07) ~= 0 or sw(0x2FA) == 1
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
local function stage(x, y, pred, tag, opts)
  opts = opts or {}
  local aPhase, calm = 0, 0
  return {
    H.navTo(x, y, { maxFrames = opts.maxFrames or 9000,
      playBattles = "flee", arrive = pred }),
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
local function edge(cands, dir, destMap, tag)
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
      error(tag .. ": no reachable approach")
    end),
    H.navTo(function() return tile[1] end, function() return tile[2] end,
      { maxFrames = 12000, playBattles = "flee",
        arrive = function() return mapIs(destMap) end }),
    H.driveUntil(function() return mapIs(destMap) end, 1500,
      { H.call(function() H.setPad({ [dir] = true }) end) }, tag),
    H.waitFrames(60),
    H.call(function()
      H.log(string.format("[%s] now map %d (%d,%d)", tag,
        H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
    end),
  }
end
-- a burst: park on a tile (best-effort navTo), then hold one direction
-- long enough to cross several slow-climb tiles; success = map change or
-- >=3 tiles of movement
local function burst(x, y, dir, tag)
  local m0, x0, y0, t = nil, nil, nil, 0
  return {
    H.navTo(x, y, { maxFrames = 9000, playBattles = "flee" }),
    H.call(function()
      m0, x0, y0, t = H.mapId() & 0x1ff, H.fieldX(), H.fieldY(), 0
      H.log(string.format("[%s] burst %s from (%d,%d)", tag, dir, x0, y0))
    end),
    -- soft timeout: give up quietly after 2500 frames (driveUntil's own
    -- timeout is a hard error)
    H.driveUntil(function()
      return t >= 2500
        or (H.mapId() & 0x1ff) ~= m0
        or math.abs(H.fieldX()-x0) + math.abs(H.fieldY()-y0) >= 3
    end, 4000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then H.setPad(H.frame % 8 < 4 and { "a" } or {}); return end
        if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
        H.setPad({ [dir] = true })
      end),
    }, tag),
    H.release(), H.waitFrames(30),
    H.call(function()
      H.log(string.format("[%s] after: map %d (%d,%d)", tag,
        H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
    end),
  }
end
local TOPS = { {107,12},{108,12},{106,12},{117,12},{116,12},{118,12} }
local function frontierRound(r)
  local mode, tile = nil, nil
  return H.cond(function() return mapIs(41) end, flatten({
    H.call(function()
      mode, tile = nil, nil
      for _, c in ipairs(TOPS) do
        if H.bfsPath(c[1], c[2]) then
          mode, tile = "door", c
          H.log(string.format("[m41 r%d] TOP door (%d,%d) reachable!", r, c[1], c[2]))
          return
        end
      end
      local best, bd, n = nil, 1e9, 0
      for y = 0, 62 do
        for x = 0, 126 do
          if H.bfsPath(x, y) then
            n = n + 1
            local d = math.abs(x - 112) + math.abs(y - 12)
            if d < bd then bd, best = d, {x, y} end
          end
        end
      end
      mode, tile = "frontier", best
      H.log(string.format("[m41 r%d] frontier (%d,%d) dist=%d (%d reachable)",
        r, best[1], best[2], bd, n))
    end),
    H.navTo(function() return tile[1] end, function() return tile[2] end,
      { maxFrames = 12000, playBattles = "flee",
        arrive = function()
          if mode == "door" then return not mapIs(41) end
          return false
        end }),
    H.cond(function() return mode == "door" and mapIs(41) end, {
      H.driveUntil(function() return not mapIs(41) end, 1500,
        { H.call(function() H.setPad({ up = true }) end) }, "top door r" .. r),
    }, {}),
    H.cond(function() return mode == "frontier" and mapIs(41) end, {
      (function()
        local t, di = 0, 1
        local dirs = { {up=true}, {up=true,right=true}, {right=true},
                       {up=true,left=true}, {left=true}, {down=true,right=true},
                       {down=true}, {down=true,left=true} }
        local lastPos, still, x0, y0 = nil, 0, nil, nil
        return H.driveUntil(function()
          if x0 == nil then x0, y0 = H.fieldX(), H.fieldY() end
          return t >= 3400
            or not mapIs(41)
            or math.abs(H.fieldX()-x0) + math.abs(H.fieldY()-y0) >= 4
        end, 5000, {
          H.call(function()
            t = t + 1
            if H.dialogWaiting() then H.setPad(t % 8 < 4 and { "a" } or {}); return end
            if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
            local pos = H.fieldX() * 256 + H.fieldY()
            if pos ~= lastPos then lastPos = pos; still = 0 else still = still + 1 end
            if still > 320 then di = (di % #dirs) + 1; still = 0 end
            H.setPad(dirs[di])
          end),
        }, "m41 burst r" .. r)
      end)(),
      H.waitFrames(30),
    }, {}),
  }), {})
end

H.run({ maxFrames = 180000 }, flatten({
  H.loadState("build/states/wob_chase23C.mss.lua"),
  H.waitFrames(8),
  -- into 43 (the proven cliff_choke opening)
  H.navTo(30, 21, { maxFrames = 9000, playBattles = "flee",
    arrive = function() return mapIs(43) end }),
  H.driveUntil(function() return mapIs(43) end, 600,
    { H.call(function() H.setPad({ up = true }) end) }, "into 43"),
  H.waitFrames(50),
  H.call(function()
    H.log(string.format("43 entry at (%d,%d)", H.fieldX(), H.fieldY()))
  end),
  -- angle A1: east off the entry column around y=45 toward (113,45)->41
  burst(108, 45, "right", "43 east y45"),
  H.cond(function() return mapIs(43) end, flatten({
    burst(108, 44, "right", "43 east y44"),
    burst(108, 46, "right", "43 east y46"),
  }), {}),
  -- press east from wherever the bursts got us: each round either takes
  -- the (113,45) door into 41 or pushes right/up from the current tile
  (function()
    local out = {}
    for r = 1, 8 do
      out[#out+1] = H.cond(function() return mapIs(43) end, flatten({
        (function()
          local tile = nil
          return flatten({
            H.call(function()
              tile = nil
              for _, c in ipairs({ {113,45},{113,46},{112,45},{112,46},
                                   {113,44},{112,44} }) do
                if H.bfsPath(c[1], c[2]) then
                  tile = c
                  H.log(string.format("[43 e r%d] door tile (%d,%d) reachable",
                    r, c[1], c[2]))
                  return
                end
              end
            end),
            H.cond(function() return tile ~= nil end, {
              H.navTo(function() return tile[1] end, function() return tile[2] end,
                { maxFrames = 9000, playBattles = "flee",
                  arrive = function() return not mapIs(43) end }),
              (function()
                local t = 0
                return H.driveUntil(function()
                  t = t + 1
                  return t >= 900 or not mapIs(43)
                end, 1500, { H.call(function() H.setPad({ right = true }) end) },
                  "43 door push r" .. r)
              end)(),
              H.waitFrames(40),
            }, {
              -- no door tile pathable yet: push right then up from here
              (function()
                local m0, x0, y0, t = nil, nil, nil, 0
                return H.driveUntil(function()
                  if m0 == nil then m0, x0, y0 = H.mapId() & 0x1ff, H.fieldX(), H.fieldY() end
                  return t >= 1800 or (H.mapId() & 0x1ff) ~= m0
                    or math.abs(H.fieldX()-x0) + math.abs(H.fieldY()-y0) >= 2
                end, 2500, { H.call(function()
                  t = t + 1
                  if H.dialogWaiting() then H.setPad(t % 8 < 4 and { "a" } or {}); return end
                  if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
                  H.setPad(t % 2400 < 1200 and { right = true } or { up = true })
                end) }, "43 east push r" .. r)
              end)(),
              H.waitFrames(30),
            }),
            H.call(function()
              H.log(string.format("[43 e r%d] now map %d (%d,%d)", r,
                H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
            end),
          })
        end)(),
      }), {})
    end
    return out
  end)(),
  -- angle A2 (only if still on 43): the (73,60) side, up at the top
  H.cond(function() return mapIs(43) end, flatten({
    H.navTo(111, 30, { maxFrames = 12000, playBattles = "flee",
      arrive = function()
        return math.abs(H.fieldX() - 73) + math.abs(H.fieldY() - 60) < 6
      end }),
    H.driveUntil(function()
      return math.abs(H.fieldX() - 73) + math.abs(H.fieldY() - 60) < 6
    end, 900, { H.call(function() H.setPad({ up = true }) end) }, "to (73,60)"),
    burst(74, 39, "up", "43 top x74"),
    H.cond(function() return mapIs(43) end, flatten({
      burst(73, 39, "up", "43 top x73"),
      burst(75, 39, "up", "43 top x75"),
      burst(73, 39, "left", "43 top left"),
    }), {}),
  }), {}),
  H.call(function()
    H.log(string.format("post-43: map %d (%d,%d)", H.mapId() & 0x1ff,
      H.fieldX(), H.fieldY()))
    H.screenshot("post43")
    if mapIs(43) then error("still stuck on 43 after every burst") end
  end),
  -- the decoded chain through the mine:
  --   41 shaft: (57,21) internal door -> (25,58) west interior
  --   (18,51) -> 21 ledge (36,25), which climbs to (24,10)
  --   (24,10) -> 41 east corridor (108,12), cross to (117,12)
  --   (117,12) -> 21 top-right (32,10), which climbs to the (35,1) row
  (function()
    local function doorSeq(x, y, destPred, tag, avoid)
      local t = 0
      local dirs = { "up", "left", "right", "down" }
      return {
        H.navTo(x, y, { maxFrames = 12000, playBattles = "flee",
          arrive = destPred, avoid = avoid }),
        H.driveUntil(destPred, 2400, {
          H.call(function()
            t = t + 1
            if H.dialogWaiting() then H.setPad(t % 8 < 4 and { "a" } or {}); return end
            local d = dirs[(math.floor(t / 300) % #dirs) + 1]
            H.setPad({ [d] = true })
          end),
        }, tag),
        H.waitFrames(50),
        H.call(function()
          H.log(string.format("[%s] now map %d (%d,%d)", tag,
            H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
        end),
      }
    end
    return flatten({
      doorSeq(57, 21, function() return mapIs(41) and H.fieldX() < 50 end,
        "41 shaft -> west interior", { {57,11} }),
      doorSeq(18, 51, function() return mapIs(21) end,
        "41 west -> 21 ledge", { {25,59} }),
      doorSeq(24, 10, function() return mapIs(41) end,
        "21 ledge -> 41 east corridor", { {37,25} }),
      doorSeq(117, 12, function() return mapIs(21) end,
        "41 corridor -> 21 top-right", { {107,12} }),
    })
  end)(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("at the top: map %d (%d,%d)", H.mapId() & 0x1ff,
      H.fieldX(), H.fieldY()))
    H.screenshot("pocket21")
  end),
  H.cond(function() return mapIs(21) end, flatten({
    edge({{35,2},{34,2},{36,2},{37,2},{35,1},{34,1},{36,1},{37,1},{38,1},{39,1}},
      "up", 22, "21 -> 22"),
  }), {}),
  H.cond(function() return mapIs(22) end, flatten({
    edge({{19,2},{18,2},{20,2},{21,2},{19,1},{18,1},{20,1},{21,1}},
      "up", 23, "22 -> 23"),
  }), {}),
  H.call(function()
    H.assertEq(mapIs(23), true, "reached the cliffs (map 23)")
    H.screenshot("cliffs")
  end),
  stage(22, 20, function() return sw(0x23D) == 1 end, "the standoff [$023D]"),
  -- the hostage ledge: any step onto (8-10,18) centers the party at
  -- (9,18), pushes it down, and runs "Halt!  Don't move or this one's
  -- dust...!" ($023E=1 + a 240-unit timer -> the Kupo!! resolution,
  -- _ccd52d, which sets $023F).  Stepping on (8,19)/(10,19)/(9,20)
  -- STOPS the timer -- so after the scene: stand perfectly still.
  H.navTo(11, 18, { maxFrames = 9000, playBattles = "flee",
    arrive = function() return sw(0x23E) == 1 or H.dialogWaiting() end }),
  (function()
    local t = 0
    return H.driveUntil(function()
      return sw(0x23E) == 1 and H.hasControl() and not H.dialogWaiting()
    end, 4000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {})
        elseif sw(0x23E) == 0 then H.setPad({ left = true })
        else H.setPad({}) end
      end),
    }, "Halt! scene [$023E]")
  end)(),
  (function()
    local t = 0
    return H.driveUntil(function() return sw(0x23F) == 1 end, 15000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "stand still for the Kupo!! resolution [$023F]")
  end)(),
  H.waitFrames(120),
  H.call(function()
    H.log(string.format("standoff resolved: $023F=%d at (%d,%d)", sw(0x23F),
      H.fieldX(), H.fieldY()))
    H.screenshot("kupo")
  end),
  -- bank the resolved standoff so later steps can iterate from here
  H.saveState("wob_kupo.mss"),
  H.logStep(function() return "done" end),
}))
