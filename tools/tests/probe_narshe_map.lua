-- probe_narshe_map.lua -- SPIKE instrument: renders map 22's passability
-- around the defense (the model's own view: prop bytes + object map) and
-- asks bfsPath for routes from the start line.  Pure reads off
-- spike_defense.mss; no walking.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DEFENSE = "/Users/mtklein/ot6/build/states/spike_defense.mss.lua"

H.run({ maxFrames = 2000 }, {
  H.loadState(DEFENSE),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("party at (%d,%d) map=%d", H.fieldX(), H.fieldY(),
      H.mapId() & 0x1ff))
    -- legend: # = wall (p1&7==7), . = open, o = object-occupied,
    --         digits = exit-bits nibble when partial (hex), P = party tile
    for y = 6, 42 do
      local row = {}
      for x = 12, 30 do
        local t = H.maptile(x, y)
        local p1 = H.readByte(0x7E7600 + t)
        local p2 = H.readByte(0x7E7700 + t)
        local occ = (H.readByte(0x7E2000 + (y & 0xFF) * 256 + (x & 0xFF)) & 0x80) == 0
        local ch
        if x == H.fieldX() and y == H.fieldY() then ch = "P"
        elseif occ then ch = "o"
        elseif (p1 & 0x07) == 0x07 then ch = "#"
        elseif (p2 & 0x0F) == 0x0F then ch = "."
        elseif (p2 & 0x0F) == 0 then ch = "x"
        else ch = string.format("%X", p2 & 0x0F) end
        row[#row + 1] = ch
      end
      H.log(string.format("y=%02d %s", y, table.concat(row)))
    end
    for _, tgt in ipairs({ { 19, 36 }, { 20, 12 }, { 18, 12 }, { 22, 12 },
                           { 19, 11 }, { 21, 11 }, { 23, 11 }, { 20, 8 } }) do
      local p = H.bfsPath(tgt[1], tgt[2])
      H.log(string.format("bfs (20,10)->(%d,%d): %s", tgt[1], tgt[2],
        p and (#p .. " steps") or "NO PATH"))
    end
    -- flood-fill the party-walkable region from the start tile (the same
    -- moves bfsPath uses, via canStep) and paint it over the map: '*' =
    -- reachable.  Shows exactly where the walking region ENDS.
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
          if not seen[k] then
            seen[k] = true
            q[#q + 1] = { nx, ny }
          end
        end
      end
    end
    H.log("reachable set from (20,10): " .. #q .. " tiles")
    -- and the same flood from KEFKA's pocket (canStep is pure tile math,
    -- no party needed there).  '*' = party's region, 'k' = pocket's
    -- region, 'B' = both (the connecting tiles), '#' wall, ' ' open.
    local kseen = { [36 * 256 + 19] = true }
    local kq, kqi = { { 19, 36 } }, 1
    while kqi <= #kq and #kq < 3000 do
      local x, y = kq[kqi][1], kq[kqi][2]
      kqi = kqi + 1
      for _, m in ipairs(MOVES) do
        if H.canStep(x, y, m) then
          local nx, ny = x + DD[m][1], y + DD[m][2]
          local k = ny * 256 + nx
          if not kseen[k] then
            kseen[k] = true
            kq[#kq + 1] = { nx, ny }
          end
        end
      end
    end
    H.log("reachable set from (19,36): " .. #kq .. " tiles")
    for y = 6, 46 do
      local row = {}
      for x = 10, 34 do
        local k = y * 256 + x
        local ch = (seen[k] and kseen[k]) and "B" or seen[k] and "*"
          or kseen[k] and "k"
          or ((H.readByte(0x7E7600 + H.maptile(x, y)) & 7) == 7 and "#" or " ")
        row[#row + 1] = ch
      end
      H.log(string.format("y=%02d %s", y, table.concat(row)))
    end
    -- where the two regions touch across one step: candidate crossings
    for _, e in ipairs(kq) do
      local x, y = e[1], e[2]
      for _, m in ipairs(MOVES) do
        local nx, ny = x + DD[m][1], y + DD[m][2]
        if seen[ny * 256 + nx] and H.canStep(nx, ny,
            ({ up = "down", down = "up", left = "right", right = "left",
               upright = "downleft", downleft = "upright",
               upleft = "downright", downright = "upleft" })[m]) then
          H.log(string.format("crossing: party (%d,%d) -> pocket (%d,%d)",
            nx, ny, x, y))
        end
      end
    end
  end),
})
