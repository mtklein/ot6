-- probe_wor_start_continue.lua -- cold-Continue the sealed `wor-start-v1`
-- battery on this tree's ROM and check it is the boot the World of Ruin
-- generators expect: the title's Continue into slot 3 lands on the World
-- of Ruin map at the raft's landing (146,212) with CELES alone and Cid
-- recovered (the entry contract in lib/ot6_contract.lua), and log her
-- level, HP, kit and supplies for the next leg.
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-start-v1 \
--     tools/tests/run.sh tools/tests/probe_wor_start_continue.lua
-- A probe: reads and presses only.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local CELES = 6

H.run({ maxFrames = 12000 }, {
  H.call(function()
    H.assertEq(OT6_SRAM_CHECKPOINT ~= nil and OT6_SRAM_CHECKPOINT ~= "", true,
      "run with OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-start-v1")
    H.log("[continue] booting the battery " .. tostring(OT6_SRAM_CHECKPOINT))
  end),
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end, 3000,
    "cold Continue onto the world map", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "cold Continue fade-in", 10),
  H.waitFrames(60),
  H.call(function() H.assertEntryContract("wor-start-v1") end),
  H.call(function()
    local c = 0x1600 + 37 * CELES
    local eq = {}
    for k = 0x1F, 0x24 do eq[#eq + 1] = string.format("%02X", H.readByte(c + k)) end
    H.log(string.format("[continue] world %d at (%d,%d): CELES L%d HP %d/%d MP %d kit %s; Cid recovered $00B3=%d; tonic=%d potion=%d fenix=%d gil=%d",
      H.worldId(), H.worldX(), H.worldY(), H.readByte(c + 8), H.charHp(CELES), H.charMaxHp(CELES),
      H.charMp(CELES), table.concat(eq, " "), (H.readByte(0x1E80 + (0xB3 >> 3)) >> (0xB3 & 7)) & 1,
      H.invCountOf(0xE8), H.invCountOf(0xE9), H.invCountOf(0xF0), H.gil()))
    H.screenshot("wor_start_continue")
  end),
})
