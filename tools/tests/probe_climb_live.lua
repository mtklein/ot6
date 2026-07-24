-- probe_climb_live.lua -- boot bridge_checkpoint and drive the climb to
-- (30,34) using a SINGLE-LIVE-Z door-walled BFS recomputed each aligned
-- tile (the proper crack technique), logging EVERY aligned tile with
-- map/x/y/z/facing and flagging any map change / battle / event.  Read-only.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function key(x, y) return y * 256 + x end
local function prop1(x, y) return H.readByte(0x7E7600 + H.maptile(x, y)) end
local function prop2(x, y) return H.readByte(0x7E7700 + H.maptile(x, y)) end
local function facing() return H.readByte(0x00b0) end   -- party facing (0u1r2d3l)
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end
local DIRBIT = { up = 0x08, right = 0x01, down = 0x04, left = 0x02 }
local DELTA  = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 },
                 upright = { 1, -1 }, downright = { 1, 1 },
                 downleft = { -1, 1 }, upleft = { -1, -1 } }
local MOVES  = { "up", "right", "down", "left",
                 "upright", "downright", "downleft", "upleft" }
local PRESS  = { up = "up", right = "right", down = "down", left = "left",
                 upright = "right", downright = "right",
                 downleft = "left", upleft = "left" }
local function diagStep(x, y, c, press, z)
  if press ~= "left" and press ~= "right" then return nil end
  if (c & 0xC0) == 0 then return nil end
  if (c & 0x04) ~= 0 and z == 0x02 then return nil end
  local bit = (c & 0x80) ~= 0 and 0x80 or 0x40
  local mv
  if bit == 0x80 then mv = press == "right" and "downright" or "upleft"
  else                mv = press == "right" and "upright"   or "downleft" end
  local d = DELTA[mv]
  local t = prop1(x + d[1], y + d[2])
  if t == 0xF7 or (t & bit) == 0 then return nil end
  return mv
end
local function stepAllowed(x, y, move, z)
  local c = prop1(x, y)
  local press = PRESS[move]
  local diag = diagStep(x, y, c, press, z)
  if move ~= press then return move == diag end
  if diag then return false end
  local d = DELTA[move]
  local nx, ny = x + d[1], y + d[2]
  local e = prop2(x, y)
  local t = prop1(nx, ny)
  if (e & 0x0F & DIRBIT[move]) == 0 then return false end
  if (t & 0x07) == 0x07 then return false end
  if (c & 0x04) ~= 0 then
    if (z & 0x01) ~= 0 then
      if (t & 0x02) ~= 0 then return false end
    else
      if (t & 0x01) ~= 0 then return false end
    end
  elseif (t & 0x03) == 0x03 then
  elseif (c & 0x03) == 0x03 then
    if (t & 0x04) ~= 0 then return false end
  elseif (((c & 0x03) ~ 0x03) & (t & 0x03)) ~= 0 then
    return false
  end
  return true
end
local function zAfter(x, y, z)
  local c = prop1(x, y)
  if (c & 0x07) >= 0x03 then return z end
  return c & 0x03
end
local DOORS225 = { {12,44},{11,17},{21,15},{52,57},{47,47},{59,35},{46,9},
  {118,27},{104,27},{83,62},{124,56},{98,62},{110,55},{66,57},{11,62},
  {30,62},{30,34},{35,14} }
-- SINGLE-Z BFS from (sx,sy,z) to (tx,ty); returns first move + full path.
local function bfs1(sx, sy, z0, tx, ty, walls)
  local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
  local function nk(x, y, z) return (z << 16) | (y << 8) | x end
  local seen = { [nk(sx, sy, z0)] = true }
  local q, qi, parent = { { sx, sy, z0 } }, 1, {}
  while qi <= #q do
    local x, y, z = q[qi][1], q[qi][2], q[qi][3]; qi = qi + 1
    if x == tx and y == ty then
      local dirs, k = {}, nk(x, y, z)
      while parent[k] do table.insert(dirs, 1, parent[k][2]); k = parent[k][1] end
      return dirs[1], dirs
    end
    local zn = zAfter(x, y, z)
    for _, mv in ipairs(MOVES) do
      local d = DELTA[mv]; local nx, ny = x + d[1], y + d[2]
      if nx >= 0 and ny >= 0 and nx <= xm and ny <= ym
         and (not walls[key(nx, ny)] or (nx == tx and ny == ty)) then
        local kk = nk(nx, ny, zn)
        if not seen[kk] and stepAllowed(x, y, mv, z) then
          seen[kk] = true
          parent[kk] = { nk(x, y, z), mv }
          q[#q+1] = { nx, ny, zn }
        end
      end
    end
  end
  return nil, nil
end
local WALLS = {}
for _, d in ipairs(DOORS225) do WALLS[key(d[1], d[2])] = true end

H.run({ maxFrames = 12000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/bridge_checkpoint.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.log(string.format("[boot] map=%d (%d,%d) z%d face=%d", map(),
      H.fieldX(), H.fieldY(), H.readByte(0x00b2) & 3, facing()))
  end),
  (function()
    local hb, lastkey, planShown = 0, nil, false
    return H.driveUntil(function()
      -- stop when we reach the door target OR the map changes off 225
      if map() ~= 225 then H.setPad({}); return true end
      if H.fieldX() == 30 and H.fieldY() == 34 and H.tileAligned() then
        H.setPad({}); return true end
      return false
    end, 11000, {
      H.call(function()
        hb = hb + 1
        if hb % 300 == 0 then
          H.log(string.format("[hb f%d] map=%d (%d,%d) z%d ev=%s ctl=%s batt=%s dlg=%s bri=%d",
            hb, map(), H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
            tostring(H.eventRunning()), tostring(H.hasControl()),
            tostring(H.battleLoadStarted()), tostring(H.dialogWaiting()), bright()))
        end
        local m = map()
        if m ~= 225 then
          local kk = string.format("m%d(%d,%d)", m, H.fieldX(), H.fieldY())
          if kk ~= lastkey then lastkey = kk
            H.log(string.format("[LEFT 225] f%d map=%d (%d,%d) z%d ev=%s ctl=%s bri=%d",
              hb, m, H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
              tostring(H.eventRunning()), tostring(H.hasControl()), bright())) end
          H.setPad({}); return
        end
        if H.battleLoadStarted() then
          if lastkey ~= "BATTLE" then lastkey = "BATTLE"
            local w = H.formationWords()
            H.log(string.format("[BATTLE] f%d at (%d,%d) form=%04X %04X %04X %04X %04X %04X",
              hb, H.fieldX(), H.fieldY(), w[1],w[2],w[3],w[4],w[5],w[6])) end
          killBitAll()
          H.setPad(hb % 8 < 4 and { "a" } or {}); return
        end
        if H.dialogWaiting() then
          H.setPad(hb % 8 < 4 and { "a" } or {}); return
        end
        if not H.hasControl() or H.eventRunning() then
          if lastkey ~= "EVENT" or hb % 60 == 0 then lastkey = "EVENT"
            H.log(string.format("[EVENT] f%d map=%d (%d,%d) z%d PC=%02X%02X%02X bri=%d",
              hb, map(), H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
              H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5), bright())) end
          H.setPad(hb % 8 < 4 and { "a" } or {}); return
        end
        if not H.tileAligned() then H.setPad({}); return end
        local x, y = H.fieldX(), H.fieldY()
        local z = H.readByte(0x00b2) & 3
        local kk = key(x, y)
        if kk ~= lastkey then
          lastkey = kk
          local mv = bfs1(x, y, z, 30, 34, WALLS)
          H.log(string.format("[tile] f%d (%2d,%2d) z%d face=%d p1=%02X -> %s",
            hb, x, y, z, facing(), prop1(x, y), tostring(mv)))
        end
        local mv = bfs1(x, y, z, 30, 34, WALLS)
        if mv and H.canStep(x, y, mv) then
          H.setPad({ [PRESS[mv]] = true })
        else
          -- log the stall reason once per tile
          H.setPad({})
        end
      end),
    }, "live climb -> (30,34)")
  end)(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[END] map=%d (%d,%d) z%d face=%d ctl=%s",
      map(), H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3, facing(),
      tostring(H.hasControl())))
    H.screenshot("climb_live_end")
  end),
})
