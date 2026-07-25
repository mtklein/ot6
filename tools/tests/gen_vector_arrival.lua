-- gen_vector_arrival.lua -- cold Continue from the versioned post-Opera
-- battery anchor, validate its semantic contract, then enter Vector.
--
-- Unlike the tactical frontier chain, this starts from power-on and lets
-- Mesen load an ordinary .srm from its private save directory.  The anchor
-- contains one valid game in slot 3.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local ACTIVE = 0x021f
local ULTROS2 = 0x012d
local function sw(id)
  return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1
end

H.run({ maxFrames = 12000 }, {
  H.waitFrames(350),
  -- Title -> New Game/Continue -> Continue -> the sole valid slot (3) ->
  -- "This data?" -> field.  Repeated edge presses tolerate title animation
  -- timing while the semantic checks below prevent a false landing.
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function()
    return (H.mapId() & 0x1ff) == 0 and H.worldHasControl()
      and H.worldAligned()
  end, 3000, "cold Continue to post-Opera world doorstep", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "cold Continue fade-in", 10),
  H.call(function()
    H.assertEq(H.readByte(ACTIVE), 3, "Continue loaded save slot 3")
    H.assertEq(sw(0x034b), 0, "anchor: Ultros 2 cleared")
    H.assertEq(sw(0x005d), 1, "anchor: Setzer bargain complete")
    H.assertEq(sw(0x005e), 1, "anchor: Blackjack arrival complete")
    H.assertEq(sw(0x0246), 0, "anchor: Blackjack is active airship")
    H.assertEq(H.worldX(), 137, "anchor: west of Vector x")
    H.assertEq(H.worldY(), 203, "anchor: Vector latitude")
    H.assertEq(emu.read(0x316800, emu.memType.snesMemory), 0x4f,
      "anchor: slot 3 codex magic O")
    H.assertEq(emu.read(0x316801, emu.memType.snesMemory), 0x38,
      "anchor: slot 3 codex magic 8")
    H.assertEq(emu.read(0x316810 + ULTROS2, emu.memType.snesMemory), 0x01,
      "anchor: bank-31 element-codex witness survived cold Continue")
    H.assertEq(emu.read(0x316990 + ULTROS2, emu.memType.snesMemory), 0x01,
      "anchor: bank-31 class-codex witness survived cold Continue")
  end),
  H.driveUntil(function() return (H.mapId() & 0x1ff) == 323 end, 1200, {
    H.hold({ "right" }),
  }, "step RIGHT into Vector"),
  H.release(),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned()
  end, 900, "Vector entrance control", 5),
  H.call(function()
    H.assertEq(H.fieldX(), 2, "Vector arrival x")
    H.assertEq(H.fieldY(), 17, "Vector arrival y")
    H.screenshot("vector_arrival")
  end),
  H.saveState("vector_arrival.mss"),
  H.logStep("cold battery Continue entered Vector and minted vector_arrival"),
})
