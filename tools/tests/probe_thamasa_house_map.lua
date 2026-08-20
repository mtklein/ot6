-- probe_thamasa_house_map.lua -- one-shot ground-truth dump of map 351's
-- (the Thamasa burning house) live tile-passability grid, issue #127.
--
-- gen_thamasa_fire.lua's own STATUS header flags that its post-(4,10)-
-- trigger walk was discovered live, tile-by-tile, and that a navTo toward
-- (1,0) lost control at (4,3) and resurfaced at (4,38) with NO intervening
-- tiles recorded in the [tiles] walk trace -- a real jump, not a walk (a
-- genuine walk would have logged dozens of tileAligned() samples in
-- between; the trace jumps straight from (4,3)-ish to (4,38)). A source
-- read of event_trigger.asm's map-351 block (only 3 triggers: (4,10),
-- (21,22), (46,53)) and npc_prop.asm's map-351 block (all 20 make_npc
-- records, coordinates and events all cross-checked) turned up NO scripted
-- mechanism anywhere near (4,3) that could explain a teleport -- no
-- load_map, no mod_bg_tiles, no NPC event. So either it's an engine-level
-- tile-property effect baked into the compressed BURNING_BUILDING tileset
-- (map_tile_prop/burning_building.dat.lz, opaque without a live read) or
-- source review missed something. Rather than guess further from static
-- source, this probe reads the LIVE decompressed tile-property tables
-- ($7E7600 prop1 / $7E7700 prop2, indexed through the BG1 tilemap byte at
-- each (x,y) -- exactly what H.canStep/H.bfsPath already read) across the
-- WHOLE map in one pass, with the party never moving from the (4,10)/
-- (4,11) landing pocket. This sidesteps bfsPath's 4096-node cap entirely
-- (no search, just a grid read) and gives real ground truth: is the north
-- pocket actually wall-sealed from the main floor in the STATIC data (which
-- would mean a real engine warp exists somewhere), or does a corridor
-- exist that a single long bfsPath query simply couldn't reach (the same
-- cap trap gen_tunnelarmr's header documents for map 75)?
--
-- No -- @suite marker: one-shot measurement, not a suite test (probe
-- convention, see probe_thamasa_names.lua's header). Boot/inn/fire/join
-- steps are gen_thamasa_fire.lua's, copied rather than shared (same
-- convention: no second real caller yet to justify a lib promotion).
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, STRAGO = 0, 1, 7
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function seq(steps) return H.cond(function() return true end, steps) end

local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

local DIAGSTAGE = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { -1, 1, "upright" }, { -1, -1, "downright" },
  { 1, -1, "downleft" }, { 1, 1, "upleft" },
}
local function crossDoor(sx, sy, dm, dx, dy, what)
  local pick, startMap
  local function stage()
    if not pick then
      for _, c in ipairs(DIAGSTAGE) do
        local cx, cy, move = sx + c[1], sy + c[2], c[3]
        local press = H.movePress(move)
        if H.bfsPath(cx, cy) and (press == move or H.canStep(cx, cy, move)) then
          pick = { cx, cy, press }; break
        end
      end
      pick = pick or { sx, sy + 1, "up" }
    end
    return pick
  end
  local settled = calm(20)
  local aPhase = 0
  return seq({
    H.call(function() pick, startMap = nil, map() end),
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 9000, playBattles = "tactical", healer = TERRA, bank = 3,
        items = true, arrive = function() return map() ~= startMap end }),
    H.driveUntil(function()
      return map() ~= startMap or (H.fieldX() == dx and H.fieldY() == dy)
    end, 1800, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
        H.setPad({ [stage()[3]] = true })
      end),
    }, what),
    H.release(),
    H.waitUntil(settled, 1800, what .. ": far-side control"),
    H.waitUntil(function() return bright() >= 15 end, 900, what .. ": fade-in", 10),
    H.waitFrames(30),
  })
end

local function objAt(idx)
  local off = 0x29 * idx
  return H.readWord(0x086a + off) >> 4, H.readWord(0x086d + off) >> 4
end
local function findNpc(x, y, fallback)
  local best, bestD = nil, nil
  for i = 16, 31 do
    local ox, oy = objAt(i)
    local d = math.abs(ox - x) + math.abs(oy - y)
    if (ox ~= 0 or oy ~= 0) and (not bestD or d < bestD) then
      best, bestD = i, d
    end
  end
  return best or fallback
end
local function chaseTalkLazy(idxFn, maxFrames, what, opts)
  opts = opts or {}
  local ph = 0
  local done = opts.done or function()
    return H.readByte(0x056f) >= 2 and H.dialogWaiting()
  end
  return H.driveUntil(done, maxFrames or 9000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        for s = 0, 5 do
          if H.readByte(0x3aa8 + s * 2) % 2 == 1 then H.killbit(s) end
        end
        H.setPad(ph < 4 and { "a" } or {})
        return
      end
      if H.readByte(0x056f) >= 2 then H.setPad({}); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
      local objIdx = idxFn()
      local ox, oy = objAt(objIdx)
      local px, py = H.fieldX(), H.fieldY()
      local dx, dy = ox - px, oy - py
      if math.abs(dx) + math.abs(dy) == 1 then
        local dir
        if dx == 1 then dir = "right" elseif dx == -1 then dir = "left"
        elseif dy == 1 then dir = "down" else dir = "up" end
        H.setPad(ph < 4 and { "a", [dir] = true } or { [dir] = true })
        return
      end
      local best, bestC
      for _, c in ipairs({ { ox, oy + 1 }, { ox - 1, oy },
                           { ox + 1, oy }, { ox, oy - 1 } }) do
        local p = H.bfsPath(c[1], c[2])
        if p and (not best or #p < #best) then best, bestC = p, c end
      end
      if best and #best > 0 then
        H.setPad({ [H.movePress(best[1])] = true })
      else
        H.setPad({})
      end
    end),
  }, what or "chaseTalkLazy")
end

-- ---- the grid dump itself ------------------------------------------------
-- prop1 bits: 0x01/0x02 z-level walkable, 0x04 bridge, 0x07==both -> counter
-- (wall). prop2 low nibble: exit bits per direction (down/up/right/left,
-- DIRBIT order in ot6_field.lua). A tile is "open" here if prop1 isn't the
-- $F7-style wall/counter pattern AND prop2's exit nibble is nonzero (some
-- exit exists). This mirrors stepAllowed's own tests without needing the
-- party actually standing adjacent (no z-transition edge cases at this
-- coarse a grain -- good enough to map connectivity, not to execute steps).
local function dumpGrid()
  local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
  H.log(string.format("[hmap] masks $86=%02X $87=%02X (map w=%d h=%d)",
    xm, ym, xm + 1, ym + 1))
  local rows = {}
  for y = 0, ym do
    local chars = {}
    for x = 0, xm do
      local t = H.maptile(x, y)
      local p1 = H.readByte(0x7E7600 + t)
      local p2 = H.readByte(0x7E7700 + t)
      local walkable = (p1 & 0x07) ~= 0x07 and (p2 & 0x0F) ~= 0
      chars[#chars + 1] = walkable and "." or "#"
    end
    rows[#rows + 1] = table.concat(chars)
  end
  for y, row in ipairs(rows) do
    H.log(string.format("[hmap] y=%02d %s", y - 1, row))
  end
  -- also dump raw prop1/prop2 for the columns/rows the earlier run actually
  -- touched, as decimal, for exact stepAllowed cross-checking
  local function dumpPoint(x, y)
    local t = H.maptile(x, y)
    local p1 = H.readByte(0x7E7600 + t)
    local p2 = H.readByte(0x7E7700 + t)
    H.log(string.format("[hmap] (%d,%d) tile=$%02X prop1=$%02X prop2=$%02X",
      x, y, t, p1, p2))
  end
  for _, c in ipairs({
    { 4, 3 }, { 4, 4 }, { 4, 5 }, { 4, 6 }, { 4, 7 }, { 4, 8 }, { 4, 9 },
    { 4, 10 }, { 4, 11 }, { 4, 12 },
    { 4, 20 }, { 4, 30 }, { 4, 38 }, { 4, 40 }, { 4, 52 }, { 4, 53 },
    { 3, 3 }, { 5, 3 }, { 0, 3 }, { 9, 3 }, { 0, 0 }, { 9, 12 },
  }) do dumpPoint(c[1], c[2]) end
end

H.run({ maxFrames = 60000 }, {
  -- ---- boot: cold Continue thamasa-night-v1 (gen_thamasa_fire's boot) ----
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    local function atSite()
      return H.worldMode() and H.worldX() == 249 and H.worldY() == 128
    end
    return H.driveUntil(function() return atSite() and bright() >= 15 end,
      4000, {
      H.call(function()
        ph = (ph + 1) % 48
        if atSite() or bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "Continue -> the L tile")
  end)(),
  H.release(),
  H.waitUntil(function()
    return H.worldMode() and bright() >= 15 and H.worldHasControl()
  end, 1800, "world control at the L tile", 5),
  H.waitFrames(30),
  H.call(function() H.assertEntryContract("thamasa-night-v1") end),
  H.fieldCare({ tag = "care at the L tile", threshold = 0.9 }),
  H.driveUntil(function() return not H.worldMode() end, 2000, {
    H.call(function()
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      H.setPad({ right = true })
    end),
  }, "held RIGHT onto (250,128) -> Thamasa 343 (23,46)"),
  H.release(),
  H.waitUntil(function() return map() == 343 and H.hasControl() end, 3000,
    "Thamasa map re-loaded", 5),

  -- ---- the inn, the fire (talk-across-the-counter, the proven fix) -------
  crossDoor(12, 19, 346, 23, 23, "inn door"),
  H.navTo(24, 17, { maxFrames = 9000, playBattles = "tactical", healer = TERRA,
    bank = 3, items = true }),
  H.driveUntil(function()
    return H.readByte(0x087f + H.readWord(0x0803)) == 0
  end, 300, { H.call(function() H.setPad({ up = true }) end) },
    "face up at the inn counter"),
  H.release(), H.waitFrames(4),
  (function()
    local ph = 0
    return H.driveUntil(function() return H.dialogWaiting() end, 3000, {
      H.call(function()
        ph = (ph + 1) % 12
        H.setPad(ph < 4 and { a = true, up = true } or {})
      end),
    }, "talk-across-the-counter -> innkeeper's 1 GP choice")
  end)(),
  H.advanceStory(calm(30), 30000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 343, "control back on town map after the fire")
  end),

  -- ---- talk to Strago at the house door -> join -> map 351 ---------------
  (function()
    local idxCell = { v = 0x14 }
    return seq({
      H.call(function() idxCell.v = findNpc(39, 24, 0x14) end),
      chaseTalkLazy(function() return idxCell.v end, 9000,
        "chase+talk Strago's door NPC",
        { done = function() return H.eventRunning() or H.dialogWaiting() end }),
    })
  end)(),
  H.advanceStory(function() return map() == 351 and H.hasControl() end,
    40000, { playBattles = "tactical" }),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 351, "loaded into the burning house (map 351)")
    H.log(string.format("[hmap] map 351 entry f%d (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
  end),

  -- ---- ride the (4,10) trigger scene (no walking past it) ----------------
  H.navTo(4, 10, { maxFrames = 20000, playBattles = "tactical", healer = TERRA,
    bank = 3, items = true }),
  H.advanceStory(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
       and sw(0x0190) == 0
  end, 12000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
  end, 2400, "map 351 settled before the dump", 10),
  H.waitFrames(150),

  -- ---- the dump itself: no more walking, just reads ----------------------
  H.call(function()
    H.log(string.format("[hmap] pre-dump position (%d,%d) f%d",
      H.fieldX(), H.fieldY(), H.frame))
    dumpGrid()
  end),
  H.logStep(function()
    return string.format("map-351 grid dump done at f%d", H.frame)
  end),
})
