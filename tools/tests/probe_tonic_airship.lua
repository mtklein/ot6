-- @manual
-- probe_tonic_airship.lua -- DIAGNOSTIC probe for #210's Tonic stop by
-- airship.  Cold-Continue the terra-returned-v1 battery (the party aboard
-- the grounded Blackjack at world (24,121), south of Zozo), lift off, fly
-- to Nikeah, land beside its west edge, walk in, buy Tonics at shop 15
-- (town map 169, the keeper at (24,39) behind the counter), walk back out,
-- fly back and land on (24,121).  Every coordinate the generator stop uses
-- is measured here; the log is the evidence.
--
-- Found on the way (the first versions of this probe booted post-opera-v1):
-- the Blackjack cannot be flown before the factory escape.  A on the parked
-- ship at (137,202) boards into the hatch room (map 7 (8,35)); the deck is
-- (10,29) -> 7 (50,61), (50,50) -> 7 (40,17), (40,10) -> 6 (19,6); and
-- LEFT+A on the wheel (14,6) opens nothing for 1800 frames: _caf532 returns
-- while $01B3 or $01B4 is clear.  So the Vector stretch has no Tonic counter
-- (Albrook's shop 24 sells none).
--
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/terra-returned-v1 \
--     tools/tests/run.sh tools/tests/probe_tonic_airship.lua
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function shipX() return H.readWord(0x34) >> 4 end
local function shipY() return H.readWord(0x38) >> 4 end
local TONIC, POTION, FENIX = 0xE8, 0xE9, 0xF0
local ANTIDOTE, REMEDY = 0xF2, 0xF5

local function bag(tag)
  return string.format("[%s] gil=%d tonic=%d potion=%d fenix=%d f%d", tag,
    H.gil(), H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX), H.frame)
end

local function worldGrind(tx, ty, what)
  local plan, idx = nil, 1
  local W = H.newWalkFighter(what)
  return H.driveUntil(function()
    return (not H.worldMode()) or (H.worldX() == tx and H.worldY() == ty
      and H.worldHasControl() and H.worldAligned())
  end, 30000, {
    H.call(function()
      if W.frame() then plan = nil; return end
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then plan = nil; H.setPad({}); return end
      if not H.worldAligned() then return end
      if not plan or idx > #plan then plan = H.worldBfs(tx, ty); idx = 1 end
      if not plan then H.setPad({}); return end
      local dir = plan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, what)
end

local function flyTo(tx, ty)
  local calm = 0
  return H.driveUntil(function()
    calm = (shipX() == tx and shipY() == ty) and calm + 1 or 0
    return calm >= 90
  end, 20000, {
    H.call(function()
      local dx, dy = tx - shipX(), ty - shipY()
      if dx == 0 and dy == 0 then H.setPad({}); return end
      local pad = { y = true }
      if dx > 0 then pad.right = true elseif dx < 0 then pad.left = true end
      if dy > 0 then pad.down = true elseif dy < 0 then pad.up = true end
      H.setPad(pad)
    end),
  }, string.format("strafe-fly to (%d,%d)", tx, ty))
end

local function board(what)
  local ph = 0
  return H.seqStep({
    H.pressButtons({ "a" }, 8),
    H.waitUntil(function()
      return (H.worldMode() and H.readByte(0xe0) == 0 and H.readByte(0xe2) == 0)
        or not H.worldMode()
    end, 900, what .. ": aboard (lifted off, or on the deck)", 5),
    H.cond(function() return not H.worldMode() end, {
      H.waitUntil(function()
        return map() == 7 and H.hasControl() and H.tileAligned() and bright() >= 15
      end, 1200, what .. ": the Blackjack's hatch (map 7) control", 5),
      H.logStep(function() return string.format("[probe] %s: aboard map %d (%d,%d) f%d",
        what, map(), H.fieldX(), H.fieldY(), H.frame) end),
      H.crossDoor(10, 29, 7, 50, 61, what .. ": hatch room (10,29) -> 7(50,61)"),
      H.crossDoor(50, 50, 7, 40, 17, what .. ": stairs (50,50) -> 7(40,17)"),
      H.crossDoor(40, 10, 6, 19, 6, what .. ": door (40,10) -> the deck 6(19,6)"),
      H.waitUntil(function()
        return map() == 6 and H.hasControl() and H.tileAligned() and bright() >= 15
          and not H.dialogWaiting()
      end, 2400, what .. ": deck control (map 6)", 5),
      H.logStep(function() return string.format("[probe] %s: on the deck map %d (%d,%d) f%d",
        what, map(), H.fieldX(), H.fieldY(), H.frame) end),
      H.navTo(14, 6, { playBattles = "tactical", maxFrames = 6000, calmFrames = 8 }),
      H.driveUntil(function()
        return H.readByte(0x056f) >= 2 or H.worldMode()
      end, 1800, {
        H.call(function()
          ph = (ph + 1) % 8
          H.setPad(ph < 4 and { "a", left = true } or { left = true })
        end),
      }, what .. ": LEFT+A on the wheel"),
      H.release(),
      H.cond(function() return not H.worldMode() end, {
        H.logStep(function() return string.format("[probe] %s: wheel choice up ($056f=%d)",
          what, H.readByte(0x056f)) end),
        H.dialogChoice(0, { ready = "count", on = 3, maxFrames = 3000, what = what .. " (Lift-off)",
          tag = what .. " (Lift-off)", done = function() return H.worldMode() end,
          idle = function(p2) H.setPad(H.readByte(0x00d3) == 1 and p2 < 3 and { "a" } or {}) end }),
      }, {}),
      H.release(),
      H.waitUntil(function()
        return H.worldMode() and H.readByte(0xe0) == 0 and H.readByte(0xe2) == 0
      end, 1800, what .. ": liftoff from the wheel", 5),
    }, {}),
    H.waitFrames(240),
    H.logStep(function() return string.format("[probe] %s: airborne ship=(%d,%d) f%d",
      what, shipX(), shipY(), H.frame) end),
  })
end

local function land(x, y, what)
  return H.seqStep({
    flyTo(x, y),
    H.release(), H.waitFrames(60),
    H.call(function()
      H.log(string.format("[probe] %s: hovering (%d,%d) $c2=%02X (bit1 clear = landable)",
        what, shipX(), shipY(), H.readByte(0xc2)))
      H.assertEq(H.readByte(0xc2) & 0x02, 0, what .. ": landable")
    end),
    H.pressButtons({ "b" }, 8),
    H.waitUntil(function() return H.worldX() ~= 0 or H.worldY() ~= 0 end,
      1200, what .. ": the ship grounds", 10),
    H.waitFrames(120),
    H.logStep(function() return string.format("[probe] %s: grounded world (%d,%d) f%d",
      what, H.worldX(), H.worldY(), H.frame) end),
  })
end

H.run({ maxFrames = 120000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue to the terra-returned world entry point", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("terra-returned-v1")
    H.log(string.format("[probe] boot world (%d,%d) ship (%d,%d) $00A4=%d",
      H.worldX(), H.worldY(), shipX(), shipY(),
      (H.readByte(0x1E80 + (0xA4 >> 3)) >> (0xA4 & 7)) & 1))
    H.log(bag("probe start"))
  end),
  board("the plains"),
  -- South Figaro (shop 8 sells Tonics) was the first try: landable at
  -- (84,112) ($c2=44), world (86,111) -> map 75 (1,28), but the town is
  -- still occupied and its troopers wall the street -- navTo (1,28) ->
  -- (44,31) read no path 20 times (build/probe_sfig8.log).  Nikeah instead.
  H.seqStep({
    -- Nikeah (shop 15: Tonic 0 / Potion 1 / Fenix 5): the world tiles
    -- (117..118,61) -> town 169 (1,35); its x=0 column -> world (116,61).
    land(116, 61, "Nikeah"),
    worldGrind(117, 61, "walk to Nikeah (117,61)"),
    H.waitUntil(function()
      return map() == 169 and H.hasControl() and H.tileAligned() and bright() >= 15
    end, 2400, "Nikeah control", 5),
    H.call(function()
      H.log(string.format("[probe] Nikeah map %d (%d,%d) f%d", map(), H.fieldX(), H.fieldY(), H.frame))
      H.screenshot("probe_nikeah_town")
    end),
    H.waitFrames(150),
    H.waitUntil(function() return H.bfsPath(24, 41) ~= nil end, 1800,
      "a walkable street to the Nikeah counter's talk tile (24,41)", 1),
    H.shopTalk(24, 39, "Nikeah item shop"),
    H.call(function()
      H.assertEq(H.shopId(), 15, "the counter opened shop 15")
      H.log(bag("shop open"))
    end),
    H.buyItem(TONIC, function() return 99 - H.invCountOf(TONIC) end, "TONIC to 99"),
    H.shopClose("Nikeah item shop"),
    H.bagArrange({ POTION, FENIX, TONIC, ANTIDOTE, REMEDY },
      { tag = "bag: combat items on top (Nikeah item shop)" }),
    H.call(function() H.log(bag("shop done")) end),
    H.navTo(1, 35, { maxFrames = 20000, playBattles = "tactical" }),
    H.driveUntil(function() return H.worldMode() end, 900, {
      H.hold({ "left" }), H.waitFrames(8),
    }, "leave Nikeah (x=0 column)"),
    H.release(),
    H.waitFrames(60),
    H.waitUntil(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned() and bright() >= 15
        and H.worldX() >= 100
    end, 2400, "world control outside Nikeah", 5),
    H.waitFrames(30),
    H.call(function()
      H.log(string.format("[probe] outside at (%d,%d) f%d", H.worldX(), H.worldY(), H.frame))
    end),
    worldGrind(116, 61, "back onto the Blackjack (116,61)"),
    board("Nikeah"),
  }),
  land(24, 121, "the plains"),
  H.call(function()
    H.log(bag("probe end"))
    H.log(string.format("[probe] end world (%d,%d) ship (%d,%d)",
      H.worldX(), H.worldY(), shipX(), shipY()))
    H.screenshot("probe_sfig_end")
  end),
})
