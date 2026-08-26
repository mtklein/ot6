-- probe_tzen_seller.lua -- finish the Tzen leg from the banked
-- wob_tzen_town fixture: SRAPHIM, RunningShoes, exit, save.
--
-- The seller at (29,3) hides behind a tile the BFS model calls
-- unwalkable but the engine allows: a held RIGHT from (27,3) lands (28,3).
-- So: navTo(27,3), push right onto the hidden tile,
-- talk RIGHT into (29,3), ride his 3000-GP choice at row 0 (Yes).
-- Then the relic room 312 (bump (25,7)), shop 32 keeper at (80,16):
-- RunningShoes x1.  Exit via room edge and the town's y=31 row; save
-- wob_tzen_done.mss on the world beside the ship.
local H = dofile("tools/tests/lib/ot6.lua")
local function gil() return H.readByte(0x1860) | (H.readByte(0x1861) << 8) | (H.readByte(0x1862) << 16) end
local function espers()
  local n = 0
  for i = 0, 3 do
    local b = H.readByte(0x1a69 + i)
    while b > 0 do n = n + (b & 1); b = b >> 1 end
  end
  return n
end
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
local e0 = nil
local function flatten(t)
  local out = {}
  for _, v in ipairs(t) do
    if type(v) == "table" and v.tick == nil and v[1] ~= nil then
      for _, s in ipairs(v) do out[#out + 1] = s end
    else out[#out + 1] = v end
  end
  return out
end
H.run({ maxFrames = 40000 }, flatten({
  H.loadState("build/states/wob_tzen_town.mss.lua"),
  H.waitFrames(8),
  H.call(function() e0 = espers(); H.log(string.format("boot gil=%d espers=%d", gil(), e0)) end),
  -- the hidden step onto (28,3), then talk right into the seller: the
  -- approach through (28,5)/(29,5) leaves the party on the z-level from
  -- which the (27,3)->right push is allowed.
  H.navTo(28, 5, { maxFrames = 9000, playBattles = "flee" }),
  H.hold({ "up" }), H.waitFrames(60), H.release(), H.waitFrames(8),
  H.navTo(29, 5, { maxFrames = 6000, playBattles = "flee" }),
  H.hold({ "up" }), H.waitFrames(60), H.release(), H.waitFrames(8),
  H.navTo(27, 3, { maxFrames = 9000, playBattles = "flee" }),
  H.driveUntil(function() return H.fieldX() == 28 end, 400,
    { H.call(function() H.setPad({ right = true }) end) },
    "onto the hidden tile (28,3)"),
  H.release(), H.waitFrames(8),
  H.call(function()
    H.log(string.format("at (%d,%d) z=%d", H.fieldX(), H.fieldY(), H.readByte(0xb2) & 3))
    H.screenshot("seller_reach")
  end),
  (function()
    -- dialog choices render as a menu while dialogWaiting reads false, and
    -- a held direction steers that menu, so: press right+a only until
    -- the dialog first opens, then plain A edges only.
    local t, talked = 0, false
    return H.driveUntil(function() return espers() > e0 end, 6000, {
      H.call(function()
        t = t + 1
        if H.dialogWaiting() then talked = true end
        if talked then
          H.setPad(t % 24 < 3 and { "a" } or {})
        else
          H.setPad(t % 30 < 3 and { right = true, a = true } or { right = true })
        end
      end),
    }, "SRAPHIM bought")
  end)(),
  H.call(function()
    H.log(string.format("SRAPHIM: gil=%d espers=%d", gil(), espers()))
  end),
  -- relic room: RunningShoes
  H.navTo(25, 8, { maxFrames = 9000, playBattles = "flee" }),
  H.driveUntil(function() return mapIs(312) end, 600,
    { H.call(function() H.setPad({ up = true }) end) }, "into the relic room"),
  H.waitFrames(50),
  (function()
    local tile, dir = nil, "up"
    local phase = 0
    return {
      H.call(function()
        for _, c in ipairs({ {80,17,"up"},{79,16,"right"},{81,16,"left"},
                             {80,18,"up"},{80,19,"up"} }) do
          if H.bfsPath(c[1], c[2]) then
            tile, dir = { c[1], c[2] }, c[3]
            H.log(string.format("[relics] talk tile (%d,%d) %s", c[1], c[2], dir))
            return
          end
        end
        error("no talk tile near the shop-32 keeper")
      end),
      H.navTo(function() return tile[1] end, function() return tile[2] end,
        { maxFrames = 8000, playBattles = "flee" }),
      H.driveUntil(function() return H.readByte(0x26) == 0x25 end, 3000, {
        H.call(function()
          phase = (phase + 1) % 8
          if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
          H.setPad(phase < 4 and { [dir] = true, a = true } or { [dir] = true })
        end),
      }, "relics: shop open"),
    }
  end)(),
  H.cond(function() return gil() >= 7000 end, {
    H.buyItem(0xba, 1, function() return 1 end, "RunningShoes"),
  }, {}),
  (function()
    local phase = 0
    return H.driveUntil(function() return H.hasControl() end, 3000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(phase < 4 and { "b" } or {})
      end),
    }, "shop closed")
  end)(),
  H.call(function()
    H.log(string.format("TZEN RESULT: gil=%d espers=%d shoes=%d",
      gil(), espers(), H.invCountOf(0xba)))
  end),
  -- exit room -> town -> world; save beside the ship
  H.navTo(81, 22, { maxFrames = 6000, playBattles = "flee",
    arrive = function() return mapIs(306) end }),
  H.driveUntil(function() return mapIs(306) end, 900,
    { H.call(function() H.setPad({ down = true }) end) }, "back in Tzen"),
  H.waitFrames(50),
  H.navTo(23, 30, { maxFrames = 9000, playBattles = "flee",
    arrive = function() return H.worldMode() end }),
  H.driveUntil(function() return H.worldMode() end, 900,
    { H.call(function() H.setPad({ down = true }) end) }, "out to the world"),
  H.waitFrames(60),
  H.saveState("wob_tzen_done.mss"),
  H.logStep(function() return "done" end),
}))
