-- probe_locke_bolt.lua -- what magic does the narshe-mission party hold?
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- Boots the terra-returned checkpoint the way gen_narshe_mission does and
-- prints each mission member's worn esper and key spell-learn bytes, so
-- the grind legs' magic/summon opts can be aimed at a caster who can
-- actually deliver ($FF = learned; 0..99 = progress percent).
local H = dofile("tools/tests/lib/ot6.lua")

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

H.run({ maxFrames = 9000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue to the terra-returned world entry point", 10),
  H.waitUntil(function() return bright() >= 15 end, 900,
    "cold Continue fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    for _, c in ipairs({ { 0, "TERRA" }, { 1, "LOCKE" }, { 4, "EDGAR" },
                         { 5, "SABIN" }, { 9, "MOG" } }) do
      local spells = 0x1A6E + c[1] * 54
      local worn = H.readByte(0x1600 + c[1] * 37 + 0x1E)
      H.log(string.format(
        "%s: esper=$%02X fire=%d ice=%d bolt=%d cure=%d",
        c[2], worn, H.readByte(spells + 0), H.readByte(spells + 1),
        H.readByte(spells + 2), H.readByte(spells + 0x2D)))
    end
  end),
})
