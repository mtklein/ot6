-- @manual
-- probe_m269lab_bake.lua -- bake the map-269 random lab fixture (issue #171).
--
-- gen_n024_entry.lua's first two steps, verbatim: boot magicite_ifrit_shiva
-- (map 264 {9,7}, the Ifrit & Shiva save room, the party exactly as the
-- route leaves it: SABIN dead from battle 70, CELES at 6 MP), walk to the
-- {9,5} exit onto map 269, land on {44,53}, settle.  The fixture is that
-- landing, so a lab run's first step off the tile is the same first step
-- the generator takes.  Nothing is healed, equipped or moved here: the
-- policies do that per run and log it.
--
--   OT6_LIVE=0 tools/tests/run.sh tools/tests/probe_m269lab_bake.lua build/m269lab/bake.log
--
-- Artifact: build/states/m269lab_pre.mss (+ .mss.lua sidecar).
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

local CHARS = { "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN",
                "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU",
                "GOGO", "UMARO" }
local function partyLine(tag)
  local cur = H.readByte(0x1A6D)
  local out = {}
  for c = 0, 13 do
    local b = H.readByte(0x1850 + c)
    if (b & 0x07) == cur and b ~= 0 then
      local base = 0x1600 + 37 * c
      out[#out + 1] = string.format("%s L%d %d/%d hp %d/%d mp %s status1=%02X xp=%d",
        CHARS[c + 1], H.readByte(base + 0x08),
        H.readWord(base + 0x09), H.readWord(base + 0x0B) & 0x3FFF,
        H.readWord(base + 0x0D), H.readWord(base + 0x0F) & 0x3FFF,
        (b & 0x20) ~= 0 and "back" or "front",
        H.readByte(base + 0x14),
        H.readByte(base + 0x11) | (H.readByte(base + 0x12) << 8) | (H.readByte(base + 0x13) << 16))
    end
  end
  return string.format("[m269lab bake %s] %s | tonic=%d fenix=%d tincture=%d", tag,
    table.concat(out, "; "), H.invCountOf(0xE8), H.invCountOf(0xF0), H.invCountOf(0xEB))
end

H.run({ maxFrames = 30000 }, {
  H.loadState("build/states/magicite_ifrit_shiva.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 264, "booted on map 264")
    H.assertEq(H.readByte(0x1A69) & 0x07, 0x07, "RAMUH + IFRIT + SHIVA owned")
    H.log(partyLine("at the save"))
  end),
  H.navTo(9, 5, { maxFrames = 9000, playBattles = "tactical", arrive = function() return map() == 269 end }),
  H.waitUntil(function() return map() == 269 and settled() end, 6000, "map 269 control", 5),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 269, "map 269")
    H.assertEq(H.fieldX(), 44, "269 landing x")
    H.assertEq(H.fieldY(), 53, "269 landing y")
    H.assertEq(settled(), true, "settled on the landing")
    H.log(partyLine("269 landing"))
    H.log(string.format("[m269lab bake] f%d phase=%d $1fa1=%02X $1fa2=%02X",
      H.frame, H.readByte(0x021E), H.readByte(0x1FA1), H.readByte(0x1FA2)))
  end),
  H.saveState("m269lab_pre.mss"),
  H.logStep(function()
    return string.format("m269lab_pre baked at frame %d -- map 269 (44,53), the landing", H.frame)
  end),
})
