-- probe_massacre_map.lua -- one-shot: boot ultros-won-v1 and flood-fill map
-- 375's live passability to find which compartment the massacre trigger
-- 375 (15,17) sits in, and which warp tiles reach it.  No @suite.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

-- warp source tiles on 375 (short_entrance decode) + landmarks
local WARPS = {
  { 48, 9, "->372(16,41)" }, { 55, 32, "->world" }, { 42, 26, "->372(33,45)" },
  { 60, 16, "->373(15,23)" }, { 42, 63, "->373(24,15)" }, { 53, 62, "->371(19,15)" },
  { 2, 45, "->371(9,9)" }, { 32, 50, "->373(17,9)" }, { 36, 41, "->374(11,12)" },
  { 52, 46, "->372(40,33)" }, { 45, 41, "->372(51,17)" }, { 16, 8, "->372(40,20)" },
  { 8, 44, "SAVE" }, { 15, 17, "MASSACRE" },
}

local function walkable(x, y)
  local t = H.maptile(x, y)
  local p1 = H.readByte(0x7E7600 + t)
  local p2 = H.readByte(0x7E7700 + t)
  return (p1 & 0x07) ~= 0x07 and (p2 & 0x0F) ~= 0
end

H.run({ maxFrames = 200000, allowGameOver = true }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  (function() local cnt = 0
    return H.waitUntil(function()
      local ok = map() == 375 and H.tileAligned() and bright() >= 15
      cnt = ok and cnt + 1 or 0
      return cnt >= 10
    end, 4000, "cold Continue to 375", 10)
  end)(),
  H.waitFrames(60),
  H.call(function()
    local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
    H.log(string.format("[mm] map=%d (%d,%d) w=%d h=%d", map(),
      H.fieldX(), H.fieldY(), xm + 1, ym + 1))
    -- flood-fill compartments over 4-connectivity of walkable tiles
    local comp = {}
    local function key(x, y) return y * 256 + x end
    local cid = 0
    for sy = 0, ym do
      for sx = 0, xm do
        if walkable(sx, sy) and not comp[key(sx, sy)] then
          cid = cid + 1
          local stack = { { sx, sy } }
          comp[key(sx, sy)] = cid
          while #stack > 0 do
            local n = table.remove(stack)
            for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
              local nx, ny = n[1] + d[1], n[2] + d[2]
              if nx >= 0 and nx <= xm and ny >= 0 and ny <= ym
                 and walkable(nx, ny) and not comp[key(nx, ny)] then
                comp[key(nx, ny)] = cid
                stack[#stack + 1] = { nx, ny }
              end
            end
          end
        end
      end
    end
    H.log(string.format("[mm] %d compartments", cid))
    for _, w in ipairs(WARPS) do
      local c = comp[key(w[1], w[2])]
      H.log(string.format("[mm] warp (%2d,%2d) %-14s comp=%s walkable=%s",
        w[1], w[2], w[3], tostring(c), tostring(walkable(w[1], w[2]))))
    end
    -- comp-2 (the massacre pocket) local geometry around (15,17) and the
    -- (16,9) entry: pick a save tile (walkable, adjacent to (15,17), not
    -- the trigger itself)
    local mc = comp[key(15, 17)]
    H.log(string.format("[mm] massacre comp=%d; neighbourhood of (15,17):", mc))
    for y = 6, 22 do
      local row = {}
      for x = 10, 20 do
        local ch = "#"
        if walkable(x, y) then ch = (comp[key(x, y)] == mc) and "." or "o" end
        if x == 15 and y == 17 then ch = "M" end
        if x == 16 and y == 9 then ch = "E" end   -- comp-2 entry from 372
        row[#row + 1] = ch
      end
      H.log(string.format("[mm] y=%02d x10..20 %s", y, table.concat(row)))
    end
    for _, t in ipairs({ { 15, 16 }, { 15, 18 }, { 14, 17 }, { 16, 17 } }) do
      H.log(string.format("[mm] adj (%d,%d) walkable=%s comp=%s",
        t[1], t[2], tostring(walkable(t[1], t[2])),
        tostring(comp[key(t[1], t[2])])))
    end
  end),
})
