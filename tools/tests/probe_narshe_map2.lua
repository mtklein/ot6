-- probe_narshe_map2.lua -- SPIKE instrument, round 2.  Round 1's floods
-- were z-NAIVE (canStep reads the live party z for every hypothetical
-- tile) and ran at f33 with all twelve raider objects parked on the home
-- rows -- the only corridor candidates.  This round: wait 1,800 frames
-- for the marches to disperse (kill-bitting any collision), then flood
-- BOTH regions with bfsPath's own z-tracking rules over a WIDE window,
-- and list every single-step crossing between them.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DEFENSE = "/Users/mtklein/ot6/build/states/spike_defense.mss.lua"

local function killBitAll()
  for slot = 0, 5 do
    if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
      H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
    end
  end
end

-- z-tracked flood: nodes (x,y,z), edges from the same stepAllowed model
-- bfsPath uses (transcribed: canStep is z-parameterized only through the
-- live byte, so this reimplements the z carry with H's own primitives).
local DD = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 },
             left = { -1, 0 }, upright = { 1, -1 }, downright = { 1, 1 },
             downleft = { -1, 1 }, upleft = { -1, -1 } }
local MOVES = { "up", "right", "down", "left",
                "upright", "downright", "downleft", "upleft" }

local function zAfter(x, y, z)
  local c = H.readByte(0x7E7600 + H.maptile(x, y))
  if (c & 0x07) >= 0x03 then return z end
  return c & 0x03
end

-- canStep with a chosen z: temporarily poke $b2 (restored after) so the
-- lib's own model answers for the hypothetical z.  $b2 is only READ by
-- the model; the engine rewrites it on every real step, and this probe
-- never steps.
local function canStepZ(x, y, m, z)
  local save = H.readByte(0x00b2)
  H.writeByte(0x00b2, z)
  local ok = H.canStep(x, y, m)
  H.writeByte(0x00b2, save)
  return ok
end

local function flood(sx, sy, sz)
  local seen = {}
  local function key(x, y, z) return (z << 16) | (y << 8) | x end
  seen[key(sx, sy, sz)] = true
  local q, qi = { { sx, sy, sz } }, 1
  local tiles = {}
  while qi <= #q and #q < 6000 do
    local x, y, z = q[qi][1], q[qi][2], q[qi][3]
    qi = qi + 1
    tiles[y * 256 + x] = true
    local zn = zAfter(x, y, z)
    for _, m in ipairs(MOVES) do
      if canStepZ(x, y, m, z) then
        local nx, ny = x + DD[m][1], y + DD[m][2]
        local k = key(nx, ny, zn)
        if not seen[k] then
          seen[k] = true
          q[#q + 1] = { nx, ny, zn }
        end
      end
    end
  end
  return tiles, #q
end

H.run({ maxFrames = 20000 }, {
  H.loadState(DEFENSE),
  H.waitFrames(30),
  -- let the marches disperse off the home rows; kill-bit any collision
  (function()
    local aPh, waited = 0, 0
    return H.driveUntil(function() return waited >= 1800 end, 4000, {
      H.call(function()
        waited = waited + 1
        aPh = (aPh + 1) % 8
        if H.battleLoadStarted() then
          killBitAll()
          H.setPad(aPh < 4 and { "a" } or {})
          return
        end
        if H.dialogWaiting() then H.setPad(aPh < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, "march dispersal")
  end)(),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end,
    3000, "control for the flood", 5),
  H.call(function()
    local px, py = H.fieldX(), H.fieldY()
    local pz = H.readByte(0x00b2) & 0x03
    H.log(string.format("flood roots: party (%d,%d,z%d), pocket (19,36,z?)",
      px, py, pz))
    local P = flood(px, py, pz)
    -- pocket z unknown: try both
    local K0, n0 = flood(19, 36, 1)
    local K1, n1 = flood(19, 36, 2)
    H.log(string.format("party region nodes vs pocket z1=%d z2=%d", n0, n1))
    local K = n0 >= n1 and K0 or K1
    for y = 4, 48 do
      local row = {}
      for x = 4, 44 do
        local k = y * 256 + x
        local ch = (P[k] and K[k]) and "B" or P[k] and "*" or K[k] and "k"
          or ((H.readByte(0x7E7600 + H.maptile(x, y)) & 7) == 7 and "#" or " ")
        row[#row + 1] = ch
      end
      H.log(string.format("y=%02d %s", y, table.concat(row)))
    end
    -- crossings: party tile with a legal step onto a pocket tile
    local found = 0
    for y = 4, 48 do
      for x = 4, 44 do
        if P[y * 256 + x] then
          for _, m in ipairs(MOVES) do
            local nx, ny = x + DD[m][1], y + DD[m][2]
            if K[ny * 256 + nx] then
              -- z at this tile unknown here; test both
              if canStepZ(x, y, m, 1) or canStepZ(x, y, m, 2) then
                H.log(string.format("crossing: (%d,%d) -%s-> (%d,%d)",
                  x, y, m, nx, ny))
                found = found + 1
              end
            end
          end
        end
      end
    end
    H.log("crossings found: " .. found)
  end),
})
