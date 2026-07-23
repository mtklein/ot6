-- shot_bushido_kanji.lua -- issue #8 PoC visual.
--
-- Boots to Cyan's battle COMMAND menu (not the tech-selection window) and
-- screenshots the command list, where command $07 (SwdTech / Bushido) is now
-- drawn as the three custom 8x8 kanji [刀][力][火] plus a sample cost digit,
-- via Ot6SwdKanji_ext (ot6.asm) hooked into MenuTextCmd_0d (btlgfx_main.asm).
-- Derived from battle_bushido.lua's Cyan-install rig; it stops at the command
-- menu instead of opening the window, so the SwdTech LABEL is on screen.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local MENU, ACTOR = 0x7BCA, 0x62CA
local KNOWN = 0x2020
local PARTY = { 0, 1, 2 }
local actor
local ceiling = 7

-- Same pin as battle_bushido.pinCyan: make every party slot a Cyan whose only
-- command is Bushido ($07), with the weapon SWDTECH flag so it is not greyed.
local function pinCyan()
  H.writeWord(KNOWN, 0xFF00 | ceiling)
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, 0x02)                 -- CHAR::CYAN
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)          -- clear magitek
    H.writeByte(0x202E + s * 12, 0x07)                -- Bushido, alone
    H.writeByte(0x2031 + s * 12, 0xFF)
    H.writeByte(0x2034 + s * 12, 0xFF)
    H.writeByte(0x2037 + s * 12, 0xFF)
    H.writeByte(0x3BA4 + s * 2, H.readByte(0x3BA4 + s * 2) | 0x02)
    H.writeByte(0x3BA5 + s * 2, H.readByte(0x3BA5 + s * 2) | 0x02)
    H.writeWord(0x3BF4 + s * 2, 999)
    H.writeWord(0x3C08 + s * 2, 99)
    H.writeWord(0x3C30 + s * 2, 99)
  end
end

H.run({ maxFrames = 20000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  -- install Cyan every frame until a menu belongs to somebody
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pinCyan), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.log(string.format("cyan installed in slot %d (char id $%02x)",
      actor, H.readByte(0x3ED8 + actor * 2)))
  end),
  -- keep pinning so the command window stays Cyan's, and let it draw/settle
  -- (MenuTextCmd_0d stamps the kanji into the SwdTech slot every redraw).
  H.repeatN(40, { H.call(pinCyan), H.waitFrames(1) }),
  H.call(function()
    local n = H.screenshot("bushido_kanji_cmd")
    H.log("command-menu screenshot bytes: " .. n)
  end),
})
