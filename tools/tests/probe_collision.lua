-- probe_collision: reconstruct the field collision grid from RAM using the
-- LIVE tile position (H.fieldX/Y = pixel>>4) and validate the wall model
-- against real cardinal movement. Map tilemap $7f0000 (tileY*256+tileX);
-- wall when $7e7600[tile] & 7 == 7 (CheckPlayerMove's counter test).
-- Cardinal: up=-Y down=+Y left=-X right=+X.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local SRM = "/Users/mtklein/ot6/build/states/playthrough_srm.mss.lua"

local function maptile(x, y) return H.readByte(0x7f0000 + (y%256)*256 + (x%256)) end
local function isWall(x, y) return (H.readByte(0x7e7600 + maptile(x, y)) & 7) == 7 end
local BTN = { up = {0,-1}, down = {0,1}, left = {-1,0}, right = {1,0} }
local sx, sy

local function tryDir(btn)
  return {
    H.call(function() sx, sy = H.fieldX(), H.fieldY() end),
    H.hold({ btn }), H.waitFrames(20), H.release(), H.waitFrames(10),
    H.call(function()
      local d = BTN[btn]
      local moved = (H.fieldX() ~= sx or H.fieldY() ~= sy)
      local pred = not isWall(sx + d[1], sy + d[2])
      H.log(string.format("press %-5s moved=%s  wallModelOpen=%s  %s",
        btn, tostring(moved), tostring(pred),
        moved == pred and "MATCH" or "MISMATCH"))
    end),
  }
end

local steps = {
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
    H.log(string.format("player X=%d Y=%d map=%d", px, py, H.mapId()))
    for y = py - 5, py + 5 do
      local row = {}
      for x = px - 8, px + 8 do
        row[#row+1] = (x==px and y==py) and "@" or (isWall(x, y) and "#" or ".")
      end
      H.log(string.format("Y=%3d %s", y, table.concat(row)))
    end
  end),
}
for _, b in ipairs({ "down", "up", "left", "right" }) do
  for _, s in ipairs(tryDir(b)) do steps[#steps+1] = s end
end
H.run({ maxFrames = 20000 }, steps)
