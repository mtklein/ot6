-- @manual
-- probe_nikeah_town.lua -- Nikeah's item shop from the town's south entrance
-- (map 169 (14,61), where the dock's north edge lands the party), off the
-- _scratch_nikeah169 state gen_sabin_trench emits there (#176).
--
-- First finding (run 1 of this probe, kept in its log): bfsPath reads no
-- path at all at +20 frames after the map load and a 44-step path to the
-- counter's talk tile (24,41) at +300 -- (24,40) itself is a counter tile
-- (p1 & 7 == 7) -- which is why gen_sabin_trench's first stop attempt
-- cached an unreachable staging pick and failed.  This run is the stop
-- itself, the way the generator now plays it: settle 150 frames, counter
-- talk, buy, back out by the south edge.
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.readWord(0x1f64) & 0x3FF end
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local SHOP_PROP = H.sym("ShopProp") & 0x3FFFFF
local function shopRow(shop, row) return H.readRomByte(SHOP_PROP + shop * 9 + 1 + row) end

H.run({ maxFrames = 20000 }, {
  H.loadState("build/states/_scratch_nikeah169.mss.lua"),
  H.waitFrames(400),
  H.call(function()
    for _, t in ipairs({ { 24, 40 }, { 24, 41 } }) do
      local q = H.bfsPath(t[1], t[2])
      H.log(string.format("[probe] f%d bfs (%d,%d): %s", H.frame, t[1], t[2], q and #q or "none"))
    end
  end),
  H.call(function()
    H.vars.shopStart = H.frame
    H.log(string.format("[shop] Nikeah stop begins f%d: gil=%d tonic=%d potion=%d fenix=%d",
      H.frame, H.gil(), H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN)))
  end),
  H.shopTalk(24, 39, "Nikeah item shop"),
  H.call(function()
    H.assertEq(H.readByte(0x0201), 15, "the counter opened shop 15 ($0201)")
    H.assertEq(shopRow(15, 0), TONIC, "shop 15 row 0 is Tonic")
    H.assertEq(shopRow(15, 1), POTION, "shop 15 row 1 is Potion")
    H.assertEq(shopRow(15, 5), FENIX_DOWN, "shop 15 row 5 is Fenix Down")
  end),
  H.buyItem(POTION, 1, function() return 27 - H.invCountOf(POTION) end, "POTION to 27"),
  H.buyItem(FENIX_DOWN, 5, function() return 15 - H.invCountOf(FENIX_DOWN) end,
    "FENIX DOWN to 15"),
  H.buyItem(TONIC, 0, function() return 99 - H.invCountOf(TONIC) end, "TONIC to 99"),
  H.call(function()
    H.log(string.format("[shop] Nikeah item shop done: tonic=%d potion=%d fenix=%d gil=%d f%d",
      H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN), H.gil(), H.frame))
  end),
  H.shopClose("Nikeah item shop"),
  H.call(function()
    H.assertEq(H.invCountOf(POTION) >= 27, true, "27 Potions bought")
    H.log(string.format("[shop] leaving the shop: gil=%d tonics=%d potions=%d fenix=%d",
      H.gil(), H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN)))
  end),
  H.navTo(13, 62, { maxFrames = 8000, playBattles = "tactical" }),
  (function() local ph = 0
    return H.driveUntil(function() return map() == 187 end, 900, {
      H.call(function() ph = ph + 1
        if H.dialogWaiting() then H.setPad(ph % 8 < 4 and { "a" } or {}); return end
        H.setPad({ down = true })
      end) }, "held DOWN off the town's south edge -> the dock 187") end)(),
  H.release(),
  H.waitUntil(function() return map() == 187 and H.hasControl() and H.tileAligned() end,
    3000, "the dock again", 5),
  H.call(function()
    H.log(string.format("[shop] Nikeah stop cost %d frames (f%d -> f%d); dock (%d,%d)",
      H.frame - H.vars.shopStart, H.vars.shopStart, H.frame, H.fieldX(), H.fieldY()))
    H.screenshot("probe_nikeah_dock")
  end),
})
