-- gen_whelk.lua -- reach the Whelk fight by PATHFINDING on the collision
-- grid read from RAM, not by playing. Walkable graph from the map tilemap
-- ($7f0000) + tile props ($7e7600 wall test &7==7; $7e7700 low nibble =
-- per-tile exit bits), BFS to the north end of the mine corridor (the
-- gate to Tritoch that triggers Whelk), execute the path, clear random
-- encounters, stop when the Whelk head (species $135) appears.
--
-- Axes (empirically, this mine is isometric so screen buttons are
-- transposed vs the tile grid; fieldX=$1fc0 col, fieldY=$1fc1 row):
--   exit bit / button -> (dFieldX, dFieldY)
--   up/$08 (-1,0)   right/$01 (0,+1)   down/$04 (+1,0)   left/$02 (0,-1)
-- North (up the corridor toward Tritoch) is decreasing fieldY.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local SRM = "/Users/mtklein/ot6/build/states/playthrough_srm.mss.lua"
local WHELK_HEAD = 0x135

local function maptile(x, y) return H.readByte(0x7f0000 + (y%256)*256 + (x%256)) end
local function isWall(x, y) return (H.readByte(0x7e7600 + maptile(x, y)) & 7) == 7 end
local function exits(x, y) return H.readByte(0x7e7700 + maptile(x, y)) & 0x0f end

local DIR = {           -- exit bit -> tile delta (fieldX,fieldY)
  { bit = 0x08, dx = -1, dy = 0  },  -- up
  { bit = 0x01, dx = 0,  dy = 1  },  -- right
  { bit = 0x04, dx = 1,  dy = 0  },  -- down
  { bit = 0x02, dx = 0,  dy = -1 },  -- left
}
local BTN = {           -- button -> tile delta (fieldX,fieldY)
  up = { -1, 0 }, right = { 0, 1 }, down = { 1, 0 }, left = { 0, -1 },
}
local function btnFor(dx, dy)
  for b, d in pairs(BTN) do if d[1] == dx and d[2] == dy then return b end end
end
local function key(x, y) return y * 512 + x end
local function edge(x, y, nx, ny) return key(x, y) * 1000000 + key(nx, ny) end

-- runtime correction: edges the static model thought open but the party
-- couldn't actually traverse (z-level / ledge / event blocks the tables
-- don't fully capture). Movement-verified during execution.
local blocked = {}

-- BFS to the northernmost (min fieldY) reachable tile; returns the path.
-- The static grid is optimistic ($7600 counter walls; the $7700 exit
-- bits read all-open here, so they don't restrict); blocklisted edges
-- from failed real moves are pruned.
local function plan(sx, sy)
  local seen, q, parent = { [key(sx,sy)] = true }, { {sx, sy} }, {}
  local best, bestY, qi = { sx, sy }, sy, 1
  while qi <= #q do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    if y < bestY then bestY = y; best = { x, y } end
    for _, d in ipairs(DIR) do
      local nx, ny = x + d.dx, y + d.dy
      if nx>=0 and ny>=0 and nx<256 and ny<256 and not seen[key(nx,ny)]
         and not isWall(nx, ny) and not blocked[edge(x, y, nx, ny)] then
        seen[key(nx,ny)] = true
        parent[key(nx,ny)] = { x, y }
        q[#q+1] = { nx, ny }
      end
    end
  end
  local path, cur = {}, best
  while cur and not (cur[1]==sx and cur[2]==sy) do
    table.insert(path, 1, cur)
    cur = parent[key(cur[1], cur[2])]
  end
  return path, best
end

local function whelkPresent()
  for s = 0, 5 do if H.readWord(0x57c0 + s*2) == WHELK_HEAD then return true end end
  return false
end

local path, goal, idx = nil, nil, 1
local stepX, stepY, stepTarget, stall = nil, nil, nil, 0

H.run({ maxFrames = 40000 }, {
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
    path, goal = plan(H.fieldX(), H.fieldY()); idx = 1
    H.log(string.format("planned %d steps (%d,%d)->(%d,%d)", #path,
      H.fieldX(), H.fieldY(), goal[1], goal[2]))
  end),
  -- one body tick per frame; HOLD the path direction continuously (FF6
  -- walks tile-by-tile while a direction is held) and only switch on a
  -- turn, a stall (blocklist + re-plan), or a battle.
  H.driveUntil(function() return whelkPresent() end, 30000, {
    H.call(function()
      if H.battleActive() then
        for s = 0, 5 do
          if H.readByte(0x3aa8 + s*2) % 2 == 1 then
            H.writeByte(0x3eec + s*2, H.readByte(0x3eec + s*2) | 0x80)
          end
        end
        H.setPad({ "a" }); path = nil; stepTarget = nil; return
      end
      if not H.hasControl() then H.setPad({ "a" }); return end
      local x, y = H.fieldX(), H.fieldY()
      if H.frame % 300 < 2 then
        H.log(string.format("hb f%d tile(%d,%d) path=%d", H.frame, x, y,
          path and #path or -1))
      end
      -- reached the step target? clear it so we pick the next
      if stepTarget and x == stepTarget[1] and y == stepTarget[2] then
        stepTarget = nil; stall = 0
      end
      -- stall detection while a step is in flight
      if stepTarget then
        if x == stepX and y == stepY then
          stall = stall + 1
          if stall > 30 then                     -- ~half a second, no move
            blocked[edge(stepX, stepY, stepTarget[1], stepTarget[2])] = true
            path = nil; stepTarget = nil; stall = 0
          end
        else
          stall = 0                              -- moving (mid-tile): fine
        end
      end
      if not path then path, goal = plan(x, y); idx = 1 end
      while idx <= #path and path[idx][1] == x and path[idx][2] == y do
        idx = idx + 1; stepTarget = nil
      end
      if idx > #path then path = nil; H.setPad({}); return end
      local tx, ty = path[idx][1], path[idx][2]
      local btn = btnFor(tx - x, ty - y)
      if btn then
        if not stepTarget then stepX, stepY, stepTarget = x, y, { tx, ty } end
        H.setPad({ [btn] = true })             -- held; no release this frame
      else
        path = nil; H.setPad({})
      end
    end),
    H.waitFrames(1),
  }, "whelk fight"),
  H.call(function()
    H.log(string.format("WHELK at frame %d, tile (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
    H.screenshot("whelk_battle")
  end),
})
