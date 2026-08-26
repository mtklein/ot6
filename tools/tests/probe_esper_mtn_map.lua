-- probe_esper_mtn_map.lua -- one-shot ground-truth dump of map 375's (the
-- Esper Mountain exterior) live tile-passability grid + reachability from
-- the (55,31) world-entrance landing.
--
-- Reads the LIVE decompressed tile-property tables across the whole map (no
-- walking, no BFS cap) and BFS-probes the objectives.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

local function dumpGrid()
  local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
  H.log(string.format("[mmap] masks $86=%02X $87=%02X (map w=%d h=%d)",
    xm, ym, xm + 1, ym + 1))
  for y = 0, ym do
    local chars = {}
    for x = 0, xm do
      local t = H.maptile(x, y)
      local p1 = H.readByte(0x7E7600 + t)
      local p2 = H.readByte(0x7E7700 + t)
      local walkable = (p1 & 0x07) ~= 0x07 and (p2 & 0x0F) ~= 0
      chars[#chars + 1] = walkable and "." or "#"
    end
    H.log(string.format("[mmap] y=%02d %s", y, table.concat(chars)))
  end
end

H.run({ maxFrames = 120000 }, {
  -- boot: cold Continue
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    local function atSite()
      return H.worldMode() and H.worldX() == 249 and H.worldY() == 128
    end
    return H.driveUntil(function() return atSite() and bright() >= 15 end,
      6000, {
      H.call(function()
        ph = (ph + 1) % 48
        if atSite() or bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "Continue -> the M tile world (249,128)")
  end)(),
  H.release(),
  H.waitUntil(function()
    return H.worldMode() and bright() >= 15 and H.worldHasControl()
  end, 1800, "world control at the M tile", 5),
  H.waitFrames(30),

  -- ---- walk into the mountain entrance ----------------------------------
  H.worldNavTo(229, 130, { maxFrames = 40000, playBattles = "flee",
    arrive = function() return not H.worldMode() end }),
  H.release(),
  H.waitUntil(function() return map() == 375 and H.hasControl() end, 4000,
    "Esper Mountain 375 loaded", 5),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
  end, 4000, "375 settled before the dump", 10),
  H.waitFrames(120),

  H.call(function()
    H.log(string.format("[mmap] map=%d landing (%d,%d) f%d",
      map(), H.fieldX(), H.fieldY(), H.frame))
    dumpGrid()
    -- reachability of the objectives from the live landing position
    for _, c in ipairs({
      { 45, 33 }, { 8, 44 }, { 9, 44 }, { 2, 45 }, { 8, 45 }, { 7, 44 },
      { 46, 27 }, { 42, 26 }, { 36, 41 }, { 16, 8 }, { 48, 9 },
      { 47, 53 }, { 39, 54 }, { 36, 53 },
    }) do
      local p = H.bfsPath(c[1], c[2])
      H.log(string.format("[mmap] bfs (%d,%d): %s", c[1], c[2],
        p and ("reachable, " .. #p .. " steps") or "NO PATH"))
    end
    -- the sparkle object positions (map NPCs start at $10)
    for i = 16, 24 do
      local off = 0x29 * i
      local ox, oy = H.readWord(0x086a + off) >> 4, H.readWord(0x086d + off) >> 4
      if ox ~= 0 or oy ~= 0 then
        H.log(string.format("[mmap] obj $%02X at (%d,%d)", i, ox, oy))
      end
    end
    H.log(string.format("[mmap] $0632=%d $0097=%d $0095=%d",
      sw(0x0632), sw(0x0097), sw(0x0095)))
  end),
  H.logStep(function()
    return string.format("map-375 grid dump done at f%d", H.frame)
  end),
})
