-- probe_m75_disguise.lua -- #244.  Boot locke_scenario (LOCKE at map 75
-- (47,43), no disguise) and flood map 75 to measure the starting pocket:
-- what is reachable WITHOUT fighting the gate soldier, and where the
-- gate/Imperial soldiers and the route doors sit.  Read-only, no walking.
-- @manual
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function seq(steps) return H.cond(function() return true end, steps) end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end

local MOVES = { "up", "down", "left", "right",
                "upleft", "upright", "downleft", "downright" }
local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 },
                right = { 1, 0 }, upleft = { -1, -1 }, upright = { 1, -1 },
                downleft = { -1, 1 }, downright = { 1, 1 } }

local function flood(tag, marks, paths)
  local seen, parent, q, qi, done
  return seq({
    H.call(function()
      local sx, sy = H.fieldX(), H.fieldY()
      seen = { [sy * 256 + sx] = true }
      parent = {}
      q, qi, done = { { sx, sy } }, 1, false
      H.log(string.format("=== flood %s: map %d from (%d,%d) ===", tag, map(), sx, sy))
    end),
    H.driveUntil(function() return done end, 12000, {
      H.call(function()
        H.setPad({})
        local budget = 300
        while qi <= #q and budget > 0 do
          local x, y = q[qi][1], q[qi][2]
          qi = qi + 1; budget = budget - 1
          for _, d in ipairs(MOVES) do
            if H.canStep(x, y, d) then
              local nx, ny = x + DELTA[d][1], y + DELTA[d][2]
              local k = ny * 256 + nx
              if not seen[k] and nx >= 0 and ny >= 0 and nx < 256 and ny < 256 then
                seen[k] = true; parent[k] = y * 256 + x; q[#q + 1] = { nx, ny }
              end
            end
          end
        end
        if qi > #q or #q > 20000 then done = true end
      end),
    }, "flood " .. tag),
    H.call(function()
      local n = 0
      for _ in pairs(seen) do n = n + 1 end
      H.log(string.format("%s: %d tiles reachable (no fight)", tag, n))
      for _, m in ipairs(marks or {}) do
        local k = m[2] * 256 + m[1]
        H.log(string.format("   (%2d,%2d) %-40s %s", m[1], m[2], m[3],
          seen[k] and "REACHABLE" or "not reachable"))
      end
      -- reconstruct + print the walkable path to each target (waypoints
      -- every `step` tiles, for hop() chains that stay inside the BFS cap)
      for _, p in ipairs(paths or {}) do
        local tk = p[2] * 256 + p[1]
        if not seen[tk] then
          H.log(string.format("PATH to (%d,%d) %s: not reachable", p[1], p[2], p[3]))
        else
          local chain, k = {}, tk
          while k do chain[#chain + 1] = k; k = parent[k] end
          local out = {}
          local step = p[4] or 6
          for i = #chain, 1, -1 do
            local idx = #chain - i
            if idx % step == 0 or i == 1 then
              out[#out + 1] = string.format("(%d,%d)", chain[i] % 256, chain[i] // 256)
            end
          end
          H.log(string.format("PATH to (%d,%d) %s [%d steps]: %s", p[1], p[2],
            p[3], #chain - 1, table.concat(out, " ")))
        end
      end
    end),
  })
end

local MARKS = {
  { 30, 42, "gate soldier A (battle 11, _ca854f)" },
  { 14, 24, "gate soldier B (battle 11, _ca856f)" },
  { 19, 51, "gate soldier C (battle 11, _ca858f)" },
  { 11, 21, "IMPERIAL soldier (battle 9, $0318, _ca7e7b)" },
  { 22, 47, "IMPERIAL soldier (battle 9, $0319, _ca7e9a)" },
  { 44, 30, "item shop door -> map 85" },
  { 22, 44, "cider cafe door -> map 78 (26,52)" },
  { 37, 40, "old man door -> map 86 (36,22)" },
  { 34, 35, "grandson door -> map 86 (4,6)" },
  { 48, 37, "pocket? door -> map 86 (52,29)" },
  { 46, 39, "pocket? door -> map 86 (49,54)" },
  { 22, 43, "B1 probe (cafe entry point)" },
  { 30, 43, "R1 probe (into SE quarter)" },
}

H.run({ maxFrames = 40000 }, {
  H.loadState("build/states/locke_scenario.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[probe] boot map=%d (%d,%d) | 0103(Imp)=%d 0104(Mer)=%d 030C=n/a 0318=%d 0319=%d 01D0(cider)=%d",
      map(), H.fieldX(), H.fieldY(), sw(0x0103), sw(0x0104), sw(0x0318), sw(0x0319), sw(0x01D0)))
    H.assertEq(map(), 75, "booted on map 75")
  end),
  flood("map 75 from the boot pocket (no disguise)", MARKS, {
    { 22, 43, "cider cafe entry", 5 },
    { 34, 35, "grandson door approach", 5 },
    { 37, 41, "old man door approach", 5 },
  }),
  -- The z-AWARE check: the flood above dedups by (x,y) only, so it can cross
  -- z-levels invalidly.  H.bfsPath is the real, z-aware nav (nodes are
  -- (x,y,z)); this is what #145 and navTo actually use.  Raise the cap so
  -- the map-size limit is not the reason for a nil.
  H.call(function()
    H.BFS_CAP = 20000
    H.log(string.format("[probe] z=%d at (%d,%d); BFS_CAP=%d",
      H.readByte(0x00b2) & 3, H.fieldX(), H.fieldY(), H.BFS_CAP))
    for _, t in ipairs({
      { 22, 43, "cider cafe entry" }, { 30, 43, "SE lane" },
      { 34, 35, "grandson door approach" }, { 37, 41, "old man door approach" },
      { 22, 47, "Imperial soldier" }, { 44, 32, "item shop doorstep" },
      { 40, 34, "main street (mid)" }, { 24, 34, "main street (west)" },
    }) do
      local p = H.bfsPath(t[1], t[2])
      H.log(string.format("   H.bfsPath (z-aware) -> (%2d,%2d) %-26s %s",
        t[1], t[2], t[3], p and (#p .. " steps") or "NO PATH (nil)"))
    end
  end),
})
