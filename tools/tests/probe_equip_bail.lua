-- probe_equip_bail.lua -- exercise M.equipWeapon's list-end bailout and
-- M.equipLoadout's optional rungs on the `thamasa-done-v1` seed: LOCKE is
-- asked for an item the game never lists for him (item_prop mask says no),
-- and the run must LOG the refusal and leave his slot untouched rather than
-- burn the 1800-frame steer and fail (the FC landing's EDGAR/$25 shape).
-- A probe: reads and presses only, cuts nothing.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local LOCKE = 0x01
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
-- candidates LOCKE cannot wear (item_prop_en.dat bytes 1-2, bit 1 clear):
-- $0B (weapon), $76 (helmet slot 2), $8F (armor slot 3); the first in the bag
local CAND = { { 0, 0x0B }, { 2, 0x76 }, { 3, 0x8F } }
local pick, before
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
  -- the Equip walk ends by waiting for FIELD control, which the world map
  -- never reports: step into Thamasa (340) first, as the FC prep does
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
    for _, c in ipairs(CAND) do
      if H.invSlotOf(c[2]) ~= nil then pick = c; break end
    end
    H.assertEq(pick ~= nil, true, "an unwearable-for-LOCKE candidate is in the bag")
    before = H.readByte(0x1600 + 37 * LOCKE + 0x1F + pick[1])
    H.log(string.format("[bail] LOCKE slot %d holds $%02X; asking for $%02X (not wearable)", pick[1], before, pick[2]))
  end),
  -- one optional loadout per candidate, gated at run time on which one the
  -- bag holds (the kitSteps shape in gen_fc_alcove): the step for the
  -- chosen candidate must LOG the refusal and leave the slot alone
  H.cond(function() return pick == CAND[1] end,
    { H.equipLoadout(LOCKE, { { CAND[1][1], CAND[1][2] } }, { tag = "bail probe $0B", optional = true }) }, {}),
  H.cond(function() return pick == CAND[2] end,
    { H.equipLoadout(LOCKE, { { CAND[2][1], CAND[2][2] } }, { tag = "bail probe $76", optional = true }) }, {}),
  H.cond(function() return pick == CAND[3] end,
    { H.equipLoadout(LOCKE, { { CAND[3][1], CAND[3][2] } }, { tag = "bail probe $8F", optional = true }) }, {}),
  H.call(function()
    local after = H.readByte(0x1600 + 37 * LOCKE + 0x1F + pick[1])
    H.assertEq(after, before, string.format("LOCKE slot %d untouched by the refused $%02X", pick[1], pick[2]))
    H.assertEq(H.hasControl(), true, "back in the field with control after the bailout")
  end),
  -- positive control: a weapon LOCKE CAN wear ($0A MithrilBlade, mask bit 1)
  -- must still be found and equipped by the same walk -- the stuck counter
  -- must not call a real list exhausted -- and then his own blade goes back
  H.cond(function() return H.invSlotOf(0x0A) ~= nil end, {
    H.equipLoadout(LOCKE, { { 0, 0x0A } }, { tag = "positive control $0A" }),
    H.call(function()
      H.assertEq(H.readByte(0x1600 + 37 * LOCKE + 0x1F), 0x0A, "LOCKE wears $0A after the positive control")
    end),
  }, { H.logStep(function() return "positive control skipped: $0A not in the bag" end) }),
  H.cond(function() return before ~= nil and H.readByte(0x1600 + 37 * LOCKE + 0x1F) ~= before and pick[1] == 0 end, {
    (function()
      -- restore whatever he held (built lazily: `before` is a run-time read)
      local steps = {}
      for _, id in ipairs({ 0x0F, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x10, 0x11, 0x12 }) do
        steps[#steps + 1] = H.cond(function() return before == id end,
          { H.equipLoadout(LOCKE, { { 0, id } }, { tag = string.format("restore $%02X", id) }) }, {})
      end
      return H.cond(function() return true end, steps)
    end)(),
  }, {}),
})
