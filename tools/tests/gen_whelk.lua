-- gen_whelk.lua -- reach the Whelk fight by PATHFINDING on the collision
-- grid read from RAM (not by playing). LIVE tile pos = pixel>>4
-- (H.fieldX/Y); map tilemap $7f0000 (tileY*256+tileX); wall when
-- $7e7600[tile] & 7 == 7. Movement is cardinal: up=-Y down=+Y left=-X
-- right=+X. BFS to the north end of the mine (min Y = the gate to
-- Tritoch that triggers Whelk); execute with press-release steps,
-- movement-verified (blocklist a bad edge + re-plan when a step doesn't
-- advance -- the static grid is optimistic about z-level/ledge blocks);
-- clear random encounters; stop when the Whelk head (species $135)
-- appears. Emits whelk_doorstep.mss (rolling pre-fight state).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local SRM = "/Users/mtklein/ot6/build/states/playthrough_srm.mss.lua"
local WHELK_HEAD = 0x135

local function maptile(x, y) return H.readByte(0x7f0000 + (y%256)*256 + (x%256)) end
local function isWall(x, y) return (H.readByte(0x7e7600 + maptile(x, y)) & 7) == 7 end

local DIR = {                    -- cardinal neighbor deltas + its button
  { dx = 0,  dy = -1, btn = "up" },
  { dx = 1,  dy = 0,  btn = "right" },
  { dx = 0,  dy = 1,  btn = "down" },
  { dx = -1, dy = 0,  btn = "left" },
}
local function key(x, y) return y * 512 + x end
local function ekey(x, y, nx, ny) return key(x, y) * 1000000 + key(nx, ny) end
local blocked = {}
local visited = {}     -- tiles the party has actually stood on

-- EXPLORE: BFS to the nearest reachable tile we haven't stood on yet,
-- biased northward (the gate to Tritoch is north). Sweeping the reachable
-- region guarantees stepping on the Whelk trigger tile without needing
-- its exact coordinate; blocklisted edges (failed real moves) are pruned.
local function plan(sx, sy)
  local seen, q, parent = { [key(sx,sy)] = true }, { {sx, sy} }, {}
  local goal, goalScore, qi = nil, nil, 1
  while qi <= #q do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    if not visited[key(x, y)] and not (x == sx and y == sy) then
      -- prefer the northernmost unvisited tile among the nearest
      local score = y
      if not goal or score < goalScore then goal, goalScore = { x, y }, score end
    end
    for _, d in ipairs(DIR) do
      local nx, ny = x + d.dx, y + d.dy
      if nx>=0 and ny>=0 and nx<256 and ny<256 and not seen[key(nx,ny)]
         and not isWall(nx, ny) and not blocked[ekey(x,y,nx,ny)] then
        seen[key(nx,ny)] = true
        parent[key(nx,ny)] = { x, y }
        q[#q+1] = { nx, ny }
      end
    end
  end
  if not goal then return {}, { sx, sy } end
  local path, cur = {}, goal
  while cur and not (cur[1]==sx and cur[2]==sy) do
    table.insert(path, 1, cur)
    cur = parent[key(cur[1], cur[2])]
  end
  return path, goal
end

local function btnFor(dx, dy)
  for _, d in ipairs(DIR) do if d.dx==dx and d.dy==dy then return d.btn end end
end
local function whelkPresent()
  for s = 0, 5 do if H.readWord(0x57c0 + s*2) == WHELK_HEAD then return true end end
  return false
end

local dumped
local path, idx, sX, sY, tgt, stall, doorstep, saveReq = nil, 1, nil, nil, nil, 0, nil, nil

H.run({ maxFrames = 20000 }, {
  H.waitFrames(5),
  H.call(function()
    local data = H.b64decode(H.resolveStateB64(SRM))
    for i = 1, #data do
      emu.write(0x306000 + i - 1, string.byte(data, i), emu.memType.snesMemory)
    end
  end),
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.hasControl() end, 2000, "field control", 10),
  H.call(function()
    local g; path, g = plan(H.fieldX(), H.fieldY()); idx = 1
    H.log(string.format("planned %d steps (%d,%d)->(%d,%d)", #path,
      H.fieldX(), H.fieldY(), g[1], g[2]))
  end),
  -- executor: one step per press-release cycle, movement-verified
  H.driveUntil(function() return whelkPresent() end, 34000, {
    -- 1. handle battle / no-control at the top of each cycle
    H.call(function()
      if H.battleActive() then
        for s = 0, 5 do
          if H.readByte(0x3aa8 + s*2) % 2 == 1 then
            H.writeByte(0x3eec + s*2, H.readByte(0x3eec + s*2) | 0x80)
          end
        end
        H.setPad({ "a" }); path = nil; tgt = nil; return
      end
      if not H.hasControl() then H.setPad({ "a" }); return end
      local x, y = H.fieldX(), H.fieldY()
      visited[key(x, y)] = true
      if H.frame % 600 < 3 then
        H.log(string.format("hb f%d (%d,%d) path=%d", H.frame, x, y,
          path and #path or -1))
      end
      -- reached the north end but stuck: screenshot + dump the gate area
      -- once so the real trigger location is visible from data
      if y <= 8 and not dumped then
        dumped = true
        H.screenshot("whelk_gate")
        for yy = y - 4, y + 3 do
          local row = {}
          for xx = x - 8, x + 8 do
            row[#row+1] = (xx==x and yy==y) and "@"
              or (isWall(xx, yy) and "#" or ".")
          end
          H.log(string.format("gate Y=%d %s", yy, table.concat(row)))
        end
      end
      -- roll a pre-fight doorstep
      if saveReq and saveReq.done and saveReq.blob then
        doorstep = saveReq.blob; saveReq = nil
      elseif not saveReq and H.frame % 150 < 3 then
        saveReq = H.requestSaveState()
      end
      -- verify the previous step landed; else blocklist + re-plan
      if tgt then
        if x == tgt[1] and y == tgt[2] then tgt = nil; stall = 0
        elseif x == sX and y == sY then
          stall = stall + 1          -- give a step several tries (the
          if stall >= 10 then         -- arrival transition eats presses)
            blocked[ekey(sX, sY, tgt[1], tgt[2])] = true
            H.log(string.format("blocked (%d,%d)->(%d,%d) after %d tries",
              sX, sY, tgt[1], tgt[2], stall))
            path = nil; tgt = nil; stall = 0
          end
        else stall = 0 end          -- moved somewhere (mid-tile) : ok
      end
      if not path then path = plan(x, y); idx = 1 end
      while idx <= #path and path[idx][1] == x and path[idx][2] == y do
        idx = idx + 1; tgt = nil
      end
      if idx > #path then path = nil; H.setPad({}); return end
      local nx, ny = path[idx][1], path[idx][2]
      local btn = btnFor(nx - x, ny - y)
      if btn then
        if not tgt then sX, sY, tgt = x, y, { nx, ny } end
        H.setPad({ [btn] = true })
      else path = nil; H.setPad({}) end
    end),
    H.waitFrames(22),                -- hold: turns AND steps
    H.call(function() H.setPad({}) end),
    H.waitFrames(8),                 -- release, let the tile settle
  }, "whelk fight"),
  H.call(function()
    H.log(string.format("WHELK at frame %d, tile (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
    if doorstep then H.emitBlob("whelk_doorstep.mss", doorstep) end
    H.screenshot("whelk_battle")
  end),
})
