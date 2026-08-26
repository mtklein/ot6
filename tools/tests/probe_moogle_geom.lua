-- probe_moogle_geom.lua -- dumps Moogle-defense passability. Boots
-- moogle_defense.mss (defense live, party 1 at the (14,14) choke) and,
-- with zero writes and zero input, renders:
--   * every field object's tile position (parties, moogles, Marshal,
--     guards, TERRA-down)
--   * the arena's passability x 2..28, y 6..46: prop bytes p1/p2 plus
--     the object-occupancy map, the same view stepAllowed() consults
--   * a flood-fill of party 1's reachable set from the choke, using the
--     live object map
--   * the same flood with the object map ignored (tile geometry only)
--   * BFS probes to candidate aside tiles and to the Marshal
local H = dofile("tools/tests/lib/ot6.lua")
local DEFENSE = "build/states/moogle_defense.mss.lua"

local X0, X1, Y0, Y1 = 2, 28, 6, 46

H.run({ maxFrames = 3000 }, {
  H.loadState(DEFENSE),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("map=%d party at (%d,%d) aligned=%s ctl=%s",
      H.mapId(), H.fieldX(), H.fieldY(),
      tostring(H.tileAligned()), tostring(H.hasControl())))
    -- every object the defense involves: chars 0..15 own objects 0..15
    -- (party 1 = LOCKE 1 / CYAN 2 / SHADOW 3 / EDGAR 4; party 2 = MOG 10 /
    -- SABIN 5 / CELES 6 / STRAGO 7; party 3 = RELM 8 / SETZER 9 / GAU 11 /
    -- GOGO 12), NPCs from 16 (Marshal 18, guards 19..24, TERRA-down 25)
    for i = 0, 27 do
      local base = 0x0867 + 0x29 * i
      local ox = H.readWord(0x086a + 0x29 * i)
      local oy = H.readWord(0x086d + 0x29 * i)
      local live = H.readByte(base) -- object flags byte (bit0 exists-ish)
      H.log(string.format("obj %2d tile (%3d,%3d) px(%d,%d) flags=%02X",
        i, ox >> 4, oy >> 4, ox, oy, live))
    end
    H.log(string.format("party leader obj offset $0803=%04X ($29*n: n=%d)",
      H.readWord(0x0803), H.readWord(0x0803) // 0x29))
    -- Y-switch gate $01CE -> $1EB9 bit $40
    H.log(string.format("$1EB9=%02X (bit40 = Y-switch live)", H.readByte(0x1eb9)))

    -- ---- raw passability map ------------------------------------------
    -- legend: P=party1  2/3=squad leaders  T=TERRA-down  M=Marshal
    --         G=guard   o=other object-occupied tile
    --         #=wall(p1&7==7)  .=all 4 exits  x=no exits  hexdigit=partial
    local objAt = {}
    local function mark(i, ch)
      local x = H.readWord(0x086a + 0x29 * i) >> 4
      local y = H.readWord(0x086d + 0x29 * i) >> 4
      objAt[y * 256 + x] = ch
    end
    for i = 0, 15 do mark(i, "o") end
    mark(5, "2") mark(6, "2") mark(7, "2")  -- party 2 members
    mark(8, "3") mark(9, "3") mark(11, "3") mark(12, "3")
    mark(10, "2")
    for i = 19, 24 do mark(i, "G") end
    mark(18, "M")
    mark(25, "T")
    objAt[H.fieldY() * 256 + H.fieldX()] = "P"
    for y = Y0, Y1 do
      local row = {}
      for x = X0, X1 do
        local t = H.maptile(x, y)
        local p1 = H.readByte(0x7E7600 + t)
        local p2 = H.readByte(0x7E7700 + t)
        local occ = (H.readByte(0x7E2000 + (y & 0xFF) * 256 + (x & 0xFF)) & 0x80) == 0
        local ch = objAt[y * 256 + x]
        if not ch then
          if (p1 & 0x07) == 0x07 then ch = "#"
          elseif occ then ch = "o"
          elseif (p2 & 0x0F) == 0x0F then ch = "."
          elseif (p2 & 0x0F) == 0 then ch = "x"
          else ch = string.format("%X", p2 & 0x0F) end
        end
        row[#row + 1] = ch
      end
      H.log(string.format("y=%02d %s", y, table.concat(row)))
    end

    -- ---- flood-fill party 1's live reachable set ----------------------
    local MOVES = { "up", "right", "down", "left",
                    "upright", "downright", "downleft", "upleft" }
    local DD = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 },
                 left = { -1, 0 }, upright = { 1, -1 },
                 downright = { 1, 1 }, downleft = { -1, 1 },
                 upleft = { -1, -1 } }
    local seen = { [H.fieldY() * 256 + H.fieldX()] = true }
    local q, qi = { { H.fieldX(), H.fieldY() } }, 1
    while qi <= #q and #q < 3000 do
      local x, y = q[qi][1], q[qi][2]
      qi = qi + 1
      for _, m in ipairs(MOVES) do
        if H.canStep(x, y, m) then
          local nx, ny = x + DD[m][1], y + DD[m][2]
          local k = ny * 256 + nx
          if not seen[k] then seen[k] = true; q[#q + 1] = { nx, ny } end
        end
      end
    end
    H.log("LIVE reachable from party 1 (objects as-is): " .. #q .. " tiles")

    -- ---- geometry-only flood (object map ignored) ---------------------
    -- stepAllowed minus its object-occupancy clause. z tracked like bfsPath.
    local DIRBIT = { up = 0x08, right = 0x01, down = 0x04, left = 0x02 }
    local function tileOpen(x, y, m, z)
      if m ~= "up" and m ~= "right" and m ~= "down" and m ~= "left" then
        return false -- skip diagonals in the geometry flood: none expected here
      end
      local c = H.readByte(0x7E7600 + H.maptile(x, y))
      if (c & 0xC0) ~= 0 and (m == "left" or m == "right") then
        -- a diagonal tile turns left/right presses diagonal; treat as closed
        return false
      end
      local d = DD[m]
      local e = H.readByte(0x7E7700 + H.maptile(x, y))
      local t = H.readByte(0x7E7600 + H.maptile(x + d[1], y + d[2]))
      if (e & 0x0F & DIRBIT[m]) == 0 then return false end
      if (t & 0x07) == 0x07 then return false end
      if (c & 0x04) ~= 0 then
        if (z & 0x01) ~= 0 then if (t & 0x02) ~= 0 then return false end
        else if (t & 0x01) ~= 0 then return false end end
      elseif (t & 0x03) == 0x03 then
      elseif (c & 0x03) == 0x03 then
        if (t & 0x04) ~= 0 then return false end
      elseif (((c & 0x03) ~ 0x03) & (t & 0x03)) ~= 0 then
        return false
      end
      return true
    end
    local z0 = H.readByte(0x00b2) & 0x03
    local gseen = { [H.fieldY() * 256 + H.fieldX()] = true }
    local gq, gqi = { { H.fieldX(), H.fieldY() } }, 1
    while gqi <= #gq and #gq < 3000 do
      local x, y = gq[gqi][1], gq[gqi][2]
      gqi = gqi + 1
      for _, m in ipairs({ "up", "right", "down", "left" }) do
        if tileOpen(x, y, m, z0) then
          local nx, ny = x + DD[m][1], y + DD[m][2]
          local k = ny * 256 + nx
          if not gseen[k] then gseen[k] = true; gq[#gq + 1] = { nx, ny } end
        end
      end
    end
    H.log("GEOMETRY reachable from party 1 (objects ignored): " .. #gq .. " tiles")

    -- paint both floods: * = live-reachable, g = geometry-only, '#' wall
    for y = Y0, Y1 do
      local row = {}
      for x = X0, X1 do
        local k = y * 256 + x
        local ch = seen[k] and "*" or gseen[k] and "g"
          or ((H.readByte(0x7E7600 + H.maptile(x, y)) & 7) == 7 and "#" or " ")
        if objAt[k] and objAt[k] ~= "o" then ch = objAt[k] end
        row[#row + 1] = ch
      end
      H.log(string.format("y=%02d %s", y, table.concat(row)))
    end

    -- ---- targeted BFS probes ------------------------------------------
    for _, tgt in ipairs({ { 14, 13 }, { 13, 14 }, { 15, 14 }, { 14, 15 },
                           { 13, 15 }, { 15, 15 }, { 12, 16 }, { 16, 16 },
                           { 10, 18 }, { 18, 18 }, { 8, 20 }, { 20, 20 },
                           { 15, 39 }, { 14, 40 }, { 16, 40 } }) do
      local p = H.bfsPath(tgt[1], tgt[2])
      H.log(string.format("bfs party1->(%d,%d): %s", tgt[1], tgt[2],
        p and (#p .. " steps") or "NO PATH"))
    end
  end),
})
