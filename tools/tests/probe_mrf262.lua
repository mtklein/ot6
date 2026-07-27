-- probe_mrf262.lua -- read-only navigation survey of the MAGITEK FACTORY
-- upper floor (map 262) from the mrf_entry fixture, so the next route leg
-- is planned off the LIVE tilemap rather than the offline model the route
-- recon could only build from the static incbin.
--
-- Dumps: the party's landing state, the full BFS step list to each
-- candidate waypoint, an ASCII passability render of the interesting
-- bands, and the object map ($7E2000 bit7 clear = occupied) so a NO-PATH
-- caused by an NPC standing in a corridor is distinguishable from one
-- caused by the tilemap.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

local function path(tx, ty, tag)
  local p = H.bfsPath(tx, ty)
  if not p then
    H.log(string.format("path -> (%d,%d) %-34s : NO PATH", tx, ty, tag))
  else
    H.log(string.format("path -> (%d,%d) %-34s : %d steps: %s",
      tx, ty, tag, #p, table.concat(p, " ")))
  end
end

-- p1/p2 property bytes for a tile, plus object occupancy
local function render(x0, x1, y0, y1, tag)
  H.log(string.format("--- passability %s  x %d..%d  y %d..%d "
    .. "( . walkable   # wall   o object   * party )", tag, x0, x1, y0, y1))
  local px, py = H.fieldX(), H.fieldY()
  for y = y0, y1 do
    local row = {}
    for x = x0, x1 do
      local t = H.readByte(0x7E7600 + H.maptile(x, y))
      local occ = (H.readByte(0x7E2000 + (y & 0xFF) * 256 + (x & 0xFF)) & 0x80) == 0
      local c
      if x == px and y == py then c = "*"
      elseif occ then c = "o"
      elseif (t & 0x07) == 0x07 then c = "#"
      else
        -- walkable-ish: does ANY neighbour step reach it?
        c = "."
      end
      row[#row + 1] = c
    end
    H.log(string.format("y=%2d %s", y, table.concat(row)))
  end
end

H.run({ maxFrames = 4000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/mrf_entry.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.log(string.format("map=%d (%d,%d) z=%02X xmask=$%02X ymask=$%02X "
      .. "$0069=%d $0270=%d $0271=%d",
      map(), H.fieldX(), H.fieldY(), H.readByte(0x00b2),
      H.readByte(0x0086), H.readByte(0x0087),
      sw(0x0069), sw(0x0270), sw(0x0271)))

    path(19, 23, "door anim _cc7753")
    path(19, 24, "door anim _cc7735")
    path(19, 25, "THE CHUTE _cc7771")
    path(21, 23, "door anim _cc77ce")
    path(21, 24, "door anim _cc77b0")
    path(21, 25, "the short chute _cc77ec")
    path(21, 27, "_cc781b")
    path(9, 22, "platform hop east _cc76f1")
    path(11, 16, "_cc7862")
    path(11, 17, "_cc784a")
    path(11, 18, "_cc787a")
    path(11, 21, "_cc78a5")
    path(5, 12, "_cc7716")
    path(10, 54, "_cc7682 lift down")
    path(6, 31, "_cc76a7 lift up")

    render(0, 31, 4, 30, "map 262 north half")
  end),

  -- watch the $0270/$0271 platform window for 600 frames: how long is it
  -- open, and how often (recon probe 3)
  (function() local n, on0, on1, edges0, edges1, p0, p1 = 0, 0, 0, 0, 0, 0, 0
    return H.driveUntil(function() return n >= 600 end, 900, {
      H.call(function()
        n = n + 1
        local a, b = sw(0x0270), sw(0x0271)
        on0 = on0 + a; on1 = on1 + b
        if a == 1 and p0 == 0 then edges0 = edges0 + 1 end
        if b == 1 and p1 == 0 then edges1 = edges1 + 1 end
        p0, p1 = a, b
        if n == 600 then
          H.log(string.format(
            "[platform window] over 600 frames: $0270 up %d frames in %d "
            .. "openings; $0271 up %d frames in %d openings",
            on0, edges0, on1, edges1))
        end
        H.setPad({})
      end),
    }, "watch $0270/$0271")
  end)(),
})
