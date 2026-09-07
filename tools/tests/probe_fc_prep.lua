-- probe_fc_prep.lua -- measure the Floating Continent PREP a person does at
-- Thamasa before boarding the Blackjack from the `thamasa-done-v1` stop line:
--
--   1. step RIGHT into Thamasa (343), the item shop door 343(26,37)->347,
--      the shopkeeper at (36,39): POTION to 40, FENIX DOWN to 25, TONIC 99
--      (the IAF gauntlet opened with 9 Potions at bag row 43 and lost two of
--      three while the row-43 steer walked -- attempts 10-11);
--   2. arrange the bag so the combat items sit on top: Potion, Fenix Down,
--      Tonic, Antidote, Remedy at slots 0..4 (M.bagArrange, the field Item
--      menu's real pick-up-and-swap);
--   3. walk back out of town and record where the world map puts the party
--      relative to the Blackjack's tile ($1f62/$1f63), so the gen's boarding
--      walk can start from there.
--
-- Reads and pad presses only.  A probe: it cuts no fixture.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local POTION, FENIX_DOWN, TONIC, ANTIDOTE, REMEDY = 0xE9, 0xF0, 0xE8, 0xF2, 0xF5
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function map() return H.mapId() & 0x3ff end
local function bagTop(n)
  local t = {}
  for k = 0, n - 1 do
    t[#t + 1] = string.format("%d:$%02X x%d", k, H.readByte(0x1869 + k), H.readByte(0x1969 + k))
  end
  return table.concat(t, "  ")
end

H.run({ maxFrames = 200000 }, {
  -- cold Continue of P (the gen_fc_alcove prelude, verbatim)
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue to the thamasa-done world stop line", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "cold Continue fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("thamasa-done-v1")
    H.log(string.format("[prep] boot: world (%d,%d) ship (%d,%d) gil=%d | tonic=%d potion=%d fenix=%d | bag top: %s",
      H.worldX(), H.worldY(), H.readByte(0x1f62), H.readByte(0x1f63), H.gil(),
      H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN), bagTop(6)))
    H.log(string.format("[prep] bag slots: potion=%s fenix=%s tonic=%s antidote=%s remedy=%s",
      tostring(H.invSlotOf(POTION)), tostring(H.invSlotOf(FENIX_DOWN)), tostring(H.invSlotOf(TONIC)),
      tostring(H.invSlotOf(ANTIDOTE)), tostring(H.invSlotOf(REMEDY))))
  end),

  -- ---- 1. into Thamasa, the item shop -------------------------------------
  H.driveUntil(function() return not H.worldMode() end, 2000, {
    H.call(function()
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      H.setPad({ right = true })
    end),
  }, "held RIGHT onto (250,128) -> Thamasa 343 (23,46)"),
  H.release(),
  -- post-massacre Thamasa is map 340 (measured: the same tiles, another map
  -- index for the town's later NPC scripts); the door step asserts the shop
  H.waitUntil(function() return (map() == 340 or map() == 343) and H.hasControl() end, 3000, "Thamasa map loaded", 5),
  H.waitUntil(function() return bright() >= 15 end, 900, "Thamasa fade-in", 10),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[prep] in Thamasa at (%d,%d) f%d", H.fieldX(), H.fieldY(), H.frame))
  end),
  H.crossDoor(26, 37, 347, 36, 44, "item shop door 343(26,37)->347(36,44)"),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 2400, "shop interior settled", 10),
  H.waitFrames(150),
  H.shopTalk(36, 39, "Thamasa item shop"),
  H.buyItem(POTION, 1, function() return 40 - H.invCountOf(POTION) end, "POTION to 40"),
  H.buyItem(FENIX_DOWN, 6, function() return 25 - H.invCountOf(FENIX_DOWN) end, "FENIX DOWN to 25"),
  H.buyItem(TONIC, 0, function() return 99 - H.invCountOf(TONIC) end, "TONIC to 99"),
  H.shopClose("Thamasa item shop"),
  H.call(function()
    H.log(string.format("[prep] shop done: tonic=%d potion=%d fenix=%d gil=%d f%d",
      H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN), H.gil(), H.frame))
    H.assertEq(H.invCountOf(POTION) >= 40, true, "Potions stocked to 40")
    H.assertEq(H.invCountOf(FENIX_DOWN) >= 25, true, "Fenix Downs stocked to 25")
  end),

  -- ---- 2. the bag: combat items on top ------------------------------------
  H.bagArrange({ POTION, FENIX_DOWN, TONIC, ANTIDOTE, REMEDY }, { tag = "bag: combat items on top" }),
  H.call(function()
    H.log(string.format("[prep] bag top after arrange: %s", bagTop(6)))
    H.assertEq(H.readByte(0x1869 + 0), POTION, "slot 0 is Potion")
    H.assertEq(H.readByte(0x1869 + 1), FENIX_DOWN, "slot 1 is Fenix Down")
    H.assertEq(H.readByte(0x1869 + 2), TONIC, "slot 2 is Tonic")
    H.screenshot("fc_prep_bag")
  end),

  -- ---- 3. back out to the world ------------------------------------------
  H.crossDoor(36, 45, 340, 26, 39, "item shop door 347(36,45)->340(26,39), return"),
  H.navTo(23, 46, { maxFrames = 9000, playBattles = "tactical", items = true }),
  H.call(function()
    H.log(string.format("[prep] at the town entrance (%d,%d) f%d", H.fieldX(), H.fieldY(), H.frame))
  end),
  H.driveUntil(function() return H.worldMode() end, 2000, {
    H.call(function() H.setPad({ down = true }) end),
  }, "held DOWN off (23,46) -> the world map"),
  H.release(),
  H.waitUntil(function() return H.worldMode() and bright() >= 15 end, 900, "world fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[prep] OUT: world (%d,%d) ship (%d,%d) control=%s f%d",
      H.worldX(), H.worldY(), H.readByte(0x1f62), H.readByte(0x1f63), tostring(H.hasControl()), H.frame))
    H.screenshot("fc_prep_out")
  end),
})
