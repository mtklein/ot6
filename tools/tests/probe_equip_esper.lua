-- @manual
-- probe_equip_esper.lua -- #151: H.equipEsper reports success without
-- reading the worn byte.  Boots fc_landing (the FC gauntlet's between-wave
-- window, where gen_fc_landing asks for "SHIVA -> EDGAR" while SHIVA is on
-- TERRA), logs every party member's worn esper (+$1E of the $1600 record)
-- before and after the equip, and lets the helper say what it thinks
-- happened.  Reads and pad presses only.
local H = dofile("tools/tests/lib/ot6.lua")

local FIX = "build/states/fc_landing.mss.lua"
local TERRA, LOCKE, SHADOW, EDGAR = 0x00, 0x01, 0x03, 0x04
local SHIVA = 0x02
local function charPos(c) return function() return (H.readByte(0x1850 + c) >> 3) & 0x03 end end
local function worn(c) return H.readByte(0x1600 + 37 * c + 0x1E) end
local function wornLine(tag)
  local out = {}
  for _, c in ipairs(H.partyMembers()) do
    out[#out + 1] = string.format("char %d (pos %d) esper=$%02X", c, charPos(c)(), worn(c))
  end
  H.log(string.format("[equip probe] %s: %s", tag, table.concat(out, " | ")))
end

H.run({ maxFrames = 30000 }, {
  H.loadState(FIX),
  H.waitFrames(60),
  H.waitUntil(function() return H.hasControl() end, 1200, "field control", 5),
  H.call(function() wornLine("before") end),
  H.equipEsper(charPos(EDGAR), SHIVA, { tag = "SHIVA -> EDGAR" }),
  H.call(function()
    wornLine("after")
    H.log(string.format("[equip probe] EDGAR wears $%02X (want $%02X); TERRA wears $%02X",
      worn(EDGAR), SHIVA, worn(TERRA)))
  end),
})
