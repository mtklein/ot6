-- probe_mrf263_chests.lua -- walkability recon for the #84 pickups on map
-- 263 assigned to gen_ifrit_entry: Gold Helmet (14,55) bit 89, Tent (42,46)
-- bit 92, Gold Armor (32,57) bit 93.  Loads the mrf_kefka fixture (the same
-- boot gen_ifrit_entry uses: map 263, {39,31}, $005F=1) and measures, for
-- each chest, which of its four stand tiles BFS can reach -- both freely and
-- with every known scripted tile on the map excluded -- plus a canStep grid
-- around each chest.  Read-only: no chest is opened, no state is saved.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end

local DELTA = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }

-- Every tile on map 263 known to fire a script when stepped on (from
-- gen_mrf_263/gen_mrf_kefka/gen_ifrit_entry's decodes plus the map's one
-- event trigger, the SavePoint at {60,32}).
local SCRIPTED = {
  { 36, 44 }, { 37, 44 }, { 38, 44 },            -- the chute to 264
  { 24, 17 }, { 24, 18 },                        -- the ride east
  { 40, 32 }, { 41, 32 }, { 42, 32 },            -- the Kefka row (inert now)
  { 42, 41 },                                    -- _cc78e0 lift
  { 49, 48 },                                    -- _cc7905
  { 12, 6 }, { 18, 5 },                          -- entrances back to 262
  { 60, 32 },                                    -- SavePoint
}
local AVOID = {}
for _, t in ipairs(SCRIPTED) do AVOID[((t[2] & 0xFF) << 8) | (t[1] & 0xFF)] = true end

local CHESTS = {
  { 14, 55, "Gold Helmet bit 89" },
  { 42, 46, "Tent bit 92" },
  { 32, 57, "Gold Armor bit 93" },
}

local function census()
  local sx, sy = H.fieldX(), H.fieldY()
  local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
  local seen, q, qi = { [(sy & ym) * 256 + (sx & xm)] = true }, { { sx, sy } }, 1
  while qi <= #q and qi <= 4000 do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    for d, v in pairs(DELTA) do
      if H.canStep(x, y, d) then
        local nx, ny = (x + v[1]) & xm, (y + v[2]) & ym
        local k = ny * 256 + nx
        if not seen[k] then seen[k] = true; q[#q + 1] = { nx, ny } end
      end
    end
  end
  H.log(string.format("[census] from (%d,%d) on map %d: %d tiles reachable",
    sx, sy, map(), #q))
  return seen
end

local function survey(tag, withGrids)
  return H.call(function()
    H.log(string.format("[probe %s] map=%d at (%d,%d)", tag, map(),
      H.fieldX(), H.fieldY()))
    census()
    for _, c in ipairs(CHESTS) do
      local cx, cy = c[1], c[2]
      if withGrids then
        H.log(string.format("[grid] %s at (%d,%d)  ('C'=chest, '.'=enterable, '#'=not)",
          c[3], cx, cy))
        for y = cy - 4, cy + 4 do
          local row = {}
          for x = cx - 6, cx + 6 do
            local r = H.canStep(x, y - 1, "down") or H.canStep(x, y + 1, "up")
              or H.canStep(x - 1, y, "right") or H.canStep(x + 1, y, "left")
            row[#row + 1] = (x == cx and y == cy) and "C" or (r and "." or "#")
          end
          H.log(string.format("[grid] y=%2d %s", y, table.concat(row)))
        end
      end
      local stands = {
        { cx, cy + 1, "up" }, { cx - 1, cy, "right" },
        { cx + 1, cy, "left" }, { cx, cy - 1, "down" },
      }
      for _, s in ipairs(stands) do
        local free = H.bfsPath(s[1], s[2])
        local safe = H.bfsPath(s[1], s[2], nil, AVOID)
        H.log(string.format("[stand %s] %s stand (%d,%d) face %-5s : free=%s safe=%s%s",
          tag, c[3], s[1], s[2], s[3],
          free and (#free .. " steps") or "NO PATH",
          safe and (#safe .. " steps") or "NO PATH",
          safe and ("  [" .. table.concat(safe, " ") .. "]") or ""))
      end
    end
    local p = H.bfsPath(37, 44)
    H.log(string.format("[ref %s] -> chute (37,44): %s", tag,
      p and (#p .. " steps") or "NO PATH"))
  end)
end

H.run({ maxFrames = 9000 }, {
  -- half 1: gen_ifrit_entry's boot -- post-Kefka, map 263 (39,31)
  H.loadState("build/states/mrf_kefka.mss.lua"),
  H.waitFrames(150),
  H.waitUntil(function() return H.hasControl() end, 1000, "ctl A", 5),
  survey("kefka", true),
  -- half 2: gen_mrf_kefka's boot -- pre-ride, map 263 (22,18), where
  -- gen_mrf_263 saved.  If a chest is NO PATH from (39,31) but reachable
  -- here, it belongs to a walk on the other side of the one-way ride.
  H.loadState("build/states/mrf_263.mss.lua"),
  H.waitFrames(150),
  H.waitUntil(function() return H.hasControl() end, 1000, "ctl B", 5),
  survey("263", false),
})
