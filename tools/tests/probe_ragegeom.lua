-- probe_ragegeom.lua -- why does the Rage/SwdTech configurator's tilemap render
-- with 12px row pitch and half-height glyphs when reached through the Skills
-- submenu, but 16px pitch and full glyphs when the state is force-jumped?
-- Dumps PPU geometry + screenshots at several settle points.  Throwaway probe.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/arvis_wake.mss.lua"

local ZMENUSTATE, ZCURSOR = 0x26, 0x4b
local CMD3, RAGES, RAGELOAD = 0x1618, 0x1D2C, 0x1E1F
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_RAGELOAD = 0x05, 0x06, 0x0a, 0x7c

local function st() return H.readByte(ZMENUSTATE) end

local FIELDS = {
  "ppu.bgMode", "ppu.mosaicEnabled", "ppu.mosaicSize", "ppu.hiResMode",
  "ppu.screenInterlace", "ppu.objInterlace", "ppu.overscanMode",
  "ppu.mainScreenLayers", "ppu.subScreenLayers", "ppu.screenBrightness",
  "ppu.layers[0].vscroll", "ppu.layers[0].hscroll", "ppu.layers[0].largeTiles",
  "ppu.layers[1].vscroll", "ppu.layers[2].vscroll", "ppu.layers[3].vscroll",
}
local function dumpPpu(tag)
  local ok, s = pcall(emu.getState)
  if not ok then H.log("PPU[" .. tag .. "] getState failed"); return end
  local out = {}
  for _, k in ipairs(FIELDS) do
    out[#out + 1] = string.format("%s=%s", k:sub(5), tostring(s[k]))
  end
  H.log("PPU[" .. tag .. "] " .. table.concat(out, " "))
  H.log(string.format("MENU[%s] zBG1H=%04x zBG1V=%04x zBG2V=%04x z45=%02x z46=%02x",
    tag, H.readWord(0x7b), H.readWord(0x7d), H.readWord(0x81),
    H.readByte(0x45), H.readByte(0x46)))
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),
  H.call(function()
    H.writeByte(CMD3, 0x10)
    for i = 0, 31 do H.writeByte(RAGES + i, 0) end
    for _, id in ipairs({ 3, 20, 41, 90, 130 }) do
      local a = RAGES + (id >> 3)
      H.writeByte(a, H.readByte(a) | (1 << (id & 7)))
    end
    for i = 0, 7 do H.writeByte(RAGELOAD + i, 0) end
  end),
  H.pressButtons({ "x" }, 4),
  H.waitUntil(function() return st() == ST_MAIN end, 600, "main menu", 5),
  H.waitFrames(20),
  H.call(function() dumpPpu("main") end),
  H.call(function() H.screenshot("geom_main") end),
  H.pressButtons({ "down" }, 2),
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(60),
  H.call(function() dumpPpu("skills") end),
  H.call(function() H.screenshot("geom_skills") end),
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == 5
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) }, "cursor to Rage"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_RAGELOAD end, 300, "rage page", 5),
  H.waitFrames(30),
  H.call(function() dumpPpu("page+30") end),
  H.call(function() H.screenshot("geom_page_30") end),
  H.waitFrames(120),
  H.call(function() dumpPpu("page+150") end),
  H.call(function() H.screenshot("geom_page_150") end),
  H.waitFrames(300),
  H.call(function() dumpPpu("page+450") end),
  H.call(function() H.screenshot("geom_page_450") end),

  -- THE RULER.  Paint one distinct letter across every BG1A tilemap row and
  -- photograph it: the shot then says, per row, whether it is on screen at all
  -- and how many of its eight scanlines survive.  MenuState_7c re-DMAs the
  -- whole ScreenA shadow every frame, so a poke into the shadow reaches VRAM.
  H.call(function()
    local BG1A = 0x3849
    for y = 0, 27 do
      for x = 0, 27 do
        H.writeByte(BG1A + x * 2 + y * 64, 0x80 + (y % 26))   -- 'A'.. per row
      end
    end
  end),
  H.waitFrames(20),
  H.call(function() H.screenshot("geom_ruler") end),
})
