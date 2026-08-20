-- probe_esper_mtn_route.lua -- trace the warp route from the 375 landing to
-- the save-point region and dump caves 373 + statue room 371, issue #127.
--
-- The 375 exterior is a warp-maze (probe_esper_mtn_map): the save-point
-- region (comp 9, containing 375 (8,44)/(2,45)) connects ONLY to the statue
-- room 371.  The reachable route is comp2(landing) -> cave 373 -> comp17 ->
-- 371 -> comp9.  This probe walks it (fleeing), dumping 373 and 371 on
-- arrival so the generator's 371 crossing can be planned to avoid the statue
-- lore trigger (371 (15,20)) and Ultros (371 (15,22)) -- N must stay
-- pre-statue ($0097=0).
--
-- No @suite: one-shot measurement.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function seq(steps) return H.cond(function() return true end, steps) end

local function dumpGrid(tag)
  local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
  H.log(string.format("[%s] masks $86=%02X $87=%02X (w=%d h=%d) pos (%d,%d)",
    tag, xm, ym, xm + 1, ym + 1, H.fieldX(), H.fieldY()))
  for y = 0, ym do
    local chars = {}
    for x = 0, xm do
      local t = H.maptile(x, y)
      local p1 = H.readByte(0x7E7600 + t)
      local p2 = H.readByte(0x7E7700 + t)
      chars[#chars + 1] =
        ((p1 & 0x07) ~= 0x07 and (p2 & 0x0F) ~= 0) and "." or "#"
    end
    H.log(string.format("[%s] y=%02d %s", tag, y, table.concat(chars)))
  end
end

local function warpTo(sx, sy, fromMap, what)
  return seq({
    H.navTo(sx, sy, { maxFrames = 40000, playBattles = "flee",
      arrive = function() return map() ~= fromMap end }),
    H.release(),
    H.waitUntil(function()
      return map() ~= fromMap and H.hasControl() and bright() >= 15
    end, 4000, what, 10),
    H.waitFrames(60),
    H.call(function()
      H.log(string.format("[route] %s -> map=%d (%d,%d) $0097=%d $0095=%d",
        what, map(), H.fieldX(), H.fieldY(), sw(0x0097), sw(0x0095)))
    end),
  })
end

H.run({ maxFrames = 300000 }, {
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
    }, "Continue -> M tile (249,128)")
  end)(),
  H.release(),
  H.waitUntil(function()
    return H.worldMode() and bright() >= 15 and H.worldHasControl()
  end, 1800, "world control at M", 5),
  H.waitFrames(30),
  H.worldNavTo(229, 130, { maxFrames = 40000, playBattles = "flee",
    arrive = function() return not H.worldMode() end }),
  H.release(),
  H.waitUntil(function() return map() == 375 and H.hasControl() end, 4000,
    "375 loaded", 5),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[route] landing map=%d (%d,%d)",
      map(), H.fieldX(), H.fieldY()))
  end),

  -- comp2 landing -> 373 via 375 (60,16)
  warpTo(60, 16, 375, "375(60,16)->373"),
  H.call(function() dumpGrid("d373") end),

  -- 373 -> comp17 via 373 (25,15)  (dest 375 (42,62))
  warpTo(25, 15, 373, "373(25,15)->375 comp17"),

  -- comp17 -> 371 via 375 (53,62)  (dest 371 (19,15))
  warpTo(53, 62, 375, "375(53,62)->371 statue room"),
  H.call(function()
    dumpGrid("d371")
    -- reachability of the 371 west door (10,9) from the (19,15) arrival,
    -- and where the statue triggers sit relative to it
    for _, c in ipairs({ { 10, 9 }, { 9, 9 }, { 15, 20 }, { 15, 22 }, { 15, 17 } }) do
      local p = H.bfsPath(c[1], c[2])
      H.log(string.format("[d371] bfs (%d,%d): %s", c[1], c[2],
        p and (#p .. " steps") or "NO PATH"))
    end
  end),
  H.logStep(function()
    return string.format("esper-mtn route probe done f%d map=%d $0097=%d",
      H.frame, map(), sw(0x0097))
  end),
})
