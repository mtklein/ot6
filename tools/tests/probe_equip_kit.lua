-- probe_equip_kit.lua -- exercise M.equipKit (one Equip session, one Relic
-- session, ladder rungs strongest-first) on the `thamasa-done-v1` seed:
-- LOCKE is offered, per slot, a rung he cannot wear ahead of one he can
-- (item_prop_en.dat masks: $0B no / $0A yes; $76 no / $6B yes), plus a
-- relic.  The run must LOG each refusal inside the session, equip the
-- wearable rung, and come back out with control.  A probe: cuts nothing.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local LOCKE = 0x01
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function slotByte(slot) return H.readByte(0x1600 + 37 * LOCKE + 0x1F + slot) end
H.run({ maxFrames = 60000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000, "cold Continue to the stop line", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function() H.assertEntryContract("thamasa-done-v1") end),   -- on the world, before the step in
  H.driveUntil(function() return not H.worldMode() end, 2000, {
    H.call(function()
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      H.setPad({ right = true })
    end),
  }, "held RIGHT into Thamasa"),
  H.release(),
  H.waitUntil(function() return H.hasControl() end, 3000, "Thamasa control", 5),
  H.waitUntil(function() return bright() >= 15 end, 900, "Thamasa fade-in", 10),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[kit probe] bag: $0B=%s $0A=%s $76=%s $6B=%s $B7=%s | LOCKE before %02X %02X %02X %02X %02X %02X",
      tostring(H.invSlotOf(0x0B)), tostring(H.invSlotOf(0x0A)), tostring(H.invSlotOf(0x76)),
      tostring(H.invSlotOf(0x6B)), tostring(H.invSlotOf(0xB7)),
      slotByte(0), slotByte(1), slotByte(2), slotByte(3), slotByte(4), slotByte(5)))
  end),
  -- gear first, asserted before any relic: the ladder's wearable rungs win
  H.equipKit(LOCKE, { { 0, 0x0B }, { 0, 0x0A }, { 2, 0x76 }, { 2, 0x6B } },
    { tag = "LOCKE kit probe", ladder = true }),
  H.call(function()
    H.assertEq(H.hasControl(), true, "back in the field with control after the gear session")
    if H.invSlotOf(0x0A) then H.assertEq(slotByte(0), 0x0A, "slot 0: the wearable rung $0A won the ladder") end
    if H.invSlotOf(0x6B) then H.assertEq(slotByte(2), 0x6B, "slot 2: the wearable rung $6B won the ladder") end
  end),
  -- then the relic session on its own.  $B7 is one of the three relics
  -- (Genji Glove / Gauntlet / Merit Award) whose Relic-screen back-out makes
  -- the game run Optimum by itself (equipWeapon's hazard note; measured
  -- here: the gear session's $0A/$6B were re-dressed to Optimum's picks the
  -- first time this probe put both sessions in one kit), so after it the
  -- assertion is only that the relic is worn
  H.cond(function() return H.invSlotOf(0xB7) ~= nil end, {
    H.equipKit(LOCKE, { { 4, 0xB7 } }, { tag = "LOCKE relic probe" }),
    H.call(function()
      H.assertEq(H.hasControl(), true, "back in the field with control after the relic session")
      H.assertEq(slotByte(4) == 0xB7 or slotByte(5) == 0xB7, true, "relic $B7 worn")
      H.log(string.format("[kit probe] after the relic session (the game's Optimum may have re-dressed): %02X %02X %02X %02X %02X %02X",
        slotByte(0), slotByte(1), slotByte(2), slotByte(3), slotByte(4), slotByte(5)))
    end),
  }, { H.logStep(function() return "[kit probe] $B7 not in the bag; relic session skipped" end) }),
})
