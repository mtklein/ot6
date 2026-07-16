-- probe_collision: reconstruct the field collision grid from RAM and
-- flood-fill it to reveal the reachable map — no playing. Model, from
-- CheckPlayerMove: a tile is a WALL/counter when $7e7600[tile] & 7 == 7;
-- otherwise passable. $7e7700[tile] low nibble further restricts exits
-- (up=$08 right=$01 down=$04 left=$02; DirXTbl/DirYTbl deltas up=(0,-1)
-- right=(1,0) down=(0,1) left=(-1,0)). Map tilemap at $7f0000
-- (row*256+col). We flood from the player and print the reachable
-- region so the route to the gate is readable from data.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local SRM = "/Users/mtklein/ot6/build/states/playthrough_srm.mss.lua"

local function maptile(x, y) return H.readByte(0x7f0000 + (y % 256) * 256 + (x % 256)) end
local function isWall(x, y) return (H.readByte(0x7e7600 + maptile(x, y)) & 0x07) == 0x07 end
local function exits(x, y) return H.readByte(0x7e7700 + maptile(x, y)) & 0x0f end

-- dir index 1..4 = up,right,down,left; bit and delta per the tables
local DIR = {
  { name = "up",    bit = 0x08, dx = 0,  dy = -1 },
  { name = "right", bit = 0x01, dx = 1,  dy = 0 },
  { name = "down",  bit = 0x04, dx = 0,  dy = 1 },
  { name = "left",  bit = 0x02, dx = -1, dy = 0 },
}

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
    local px, py = H.fieldX(), H.fieldY()
    local wmask, hmask = H.readByte(0x86), H.readByte(0x87)
    H.log(string.format("player x=%d y=%d map=%d wmask=%02x hmask=%02x",
      px, py, H.mapId(), wmask, hmask))
    -- BFS flood from the player over passable tiles (edges respect both
    -- the wall test and the source tile's exit bits)
    local seen, q, reach = {}, { { px, py } }, 0
    local minx, maxx, miny, maxy = px, px, py, py
    local key = function(x, y) return y * 512 + x end
    seen[key(px, py)] = true
    while #q > 0 do
      local c = table.remove(q, 1)
      local x, y = c[1], c[2]
      reach = reach + 1
      if x < minx then minx = x end; if x > maxx then maxx = x end
      if y < miny then miny = y end; if y > maxy then maxy = y end
      local ex = exits(x, y)
      for _, d in ipairs(DIR) do
        local nx, ny = x + d.dx, y + d.dy
        if nx >= 0 and ny >= 0 and nx < 256 and ny < 256
           and not seen[key(nx, ny)] and not isWall(nx, ny)
           and (ex & d.bit) ~= 0 then
          seen[key(nx, ny)] = true
          q[#q + 1] = { nx, ny }
        end
      end
    end
    H.log(string.format("reachable tiles=%d bbox x[%d..%d] y[%d..%d]",
      reach, minx, maxx, miny, maxy))
    -- render the reachable region (clamped to a readable size)
    local x0, x1 = math.max(minx, px - 20), math.min(maxx, px + 20)
    local y0, y1 = math.max(miny, py - 20), math.min(maxy, py + 20)
    for y = y0, y1 do
      local row = {}
      for x = x0, x1 do
        if x == px and y == py then row[#row+1] = "@"
        elseif seen[key(x, y)] then row[#row+1] = "."
        elseif isWall(x, y) then row[#row+1] = "#"
        else row[#row+1] = " " end
      end
      H.log(string.format("%3d %s", y, table.concat(row)))
    end
  end),
})
