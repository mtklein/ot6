-- probe_fieldicons.lua -- reference probe, not a suite test (no `-- @suite`).
--
-- Measures where the field menu's small font lives in vram, whether the
-- eight element icon cells are free there, and what a field page draws in
-- its icon column.  Run it on the shipped ROM and on a pre-change ROM
-- (OT6_ROM=...) to get both halves of the before/after.
--
-- What it measures
--   1. Font space.  The menu keeps two copies of the small font, neither
--      of them the battle font at word $5800: LoadFontGfx2bpp lays 256
--      2bpp tiles at word $6000 and LoadFontGfx4bpp expands the same art
--      into 4bpp tiles at word $5000 (char bases hBG12NBA = $65 /
--      hBG34NBA = $66).  For each of the eight cells Ot6ElemGlyphTbl
--      claims, the probe prints the tile as it stands in vram in both
--      copies, and prints cell $d9 (the sword, which ships in the
--      vanilla art) as the positive control that the addresses are right.
--   2. Stray references.  Every cell of the BG1 A/B and BG3 A tilemap
--      shadows is scanned for the eight icon codes.  A vanilla surface
--      that spelled one of them would start drawing an element icon the
--      moment the tiles arrive ($ee is vanilla's battle-tilemap junk
--      fill, hence poison at $64).
--   3. The Blitz page's icon column, cell by cell, against the ROM tables.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/arvis_wake.mss.lua"

local VR, ROM = emu.memType.snesVideoRam, emu.memType.snesPrgRom

-- byte addresses of the two menu font copies (vram word address * 2)
local F4BPP, F4STRIDE = 0x5000 * 2, 32     -- BG1: 16 words per tile
local F2BPP, F2STRIDE = 0x6000 * 2, 16     -- BG2/BG3: 8 words per tile

local ELEMGLYPH = H.sym("Ot6ElemGlyphTbl") & 0x3FFFFF
local FONTICONS = H.sym("Ot6FontIcons") & 0x3FFFFF
local SKILLCLASS = H.sym("Ot6SkillClassTbl") & 0x3FFFFF
local CLASSGLYPH = H.sym("Ot6ClassGlyphTbl") & 0x3FFFFF
local ELEM = { "fire", "ice", "bolt", "poison", "wind", "holy", "earth", "water" }

local BG1A, BG1B, BG3A = 0x3849, 0x4049, 0x7849   -- wBG1Tiles $7e3849, wBG3Tiles $7e7849
local function cell(base, x, y) return H.readByte(base + x * 2 + y * 64) end

local ZMENUSTATE, ZCURSOR = 0x26, 0x4b
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_BLITZ = 0x05, 0x06, 0x0a, 0x33
local SKILLS_ROW_BLITZ = 3
local CMD3, BATTLE_CMD_BLITZ, BLITZES = 0x1618, 0x0a, 0x1D28
local BLITZ_ATK0, ICON_COL = 0x5d, 14
local function st() return H.readByte(ZMENUSTATE) end

local function hex16(base, off)
  local t = {}
  for i = 0, 15 do t[#t + 1] = string.format("%02x", emu.read(base + off + i, VR)) end
  return table.concat(t)
end

local function iconCells()
  local t = {}
  for i = 0, 7 do t[i + 1] = H.readRomByte(ELEMGLYPH + i) end
  return t
end

local function reportFont(tag)
  local cells = iconCells()
  H.log("---- " .. tag .. ": the two menu font copies ----")
  -- positive control first: the sword cell ships in the vanilla art, so it
  -- must be nonzero in both copies, or the addresses below are wrong.
  H.log(string.format("control  cell $d9 (sword) 4bpp[%s] 2bpp[%s]",
    hex16(F4BPP, 0xd9 * F4STRIDE), hex16(F2BPP, 0xd9 * F2STRIDE)))
  for i = 1, 8 do
    local c = cells[i]
    local want = {}
    for k = 0, 15 do want[#want + 1] = string.format("%02x", H.readRomByte(FONTICONS + (i - 1) * 16 + k)) end
    want = table.concat(want)
    local got4 = hex16(F4BPP, c * F4STRIDE)          -- first 16 bytes = planes 0/1
    local got2 = hex16(F2BPP, c * F2STRIDE)
    H.log(string.format("%-7s cell $%02x rom[%s] 4bpp[%s]%s 2bpp[%s]%s",
      ELEM[i], c, want, got4, got4 == want and " OK" or " --",
      got2, got2 == want and " OK" or " --"))
  end
  -- and the 4bpp copy's upper bitplanes must be zero (2bpp art in a 4bpp cell)
  for i = 1, 8 do
    local c = cells[i]
    local hi = hex16(F4BPP, c * F4STRIDE + 16)
    if hi ~= string.rep("0", 32) then
      H.log(string.format("%-7s cell $%02x 4bpp planes 2/3 NOT blank: [%s]", ELEM[i], c, hi))
    end
  end
end

local function scanStray(tag)
  local cells, set = iconCells(), {}
  for _, c in ipairs(cells) do set[c] = true end
  local hits = 0
  for _, m in ipairs({ { "BG1A", BG1A }, { "BG1B", BG1B }, { "BG3A", BG3A } }) do
    for y = 0, 27 do
      for x = 0, 31 do
        local b = cell(m[2], x, y)
        if set[b] then
          hits = hits + 1
          if hits <= 40 then
            H.log(string.format("%s: %s {%d,%d} = $%02x (an icon cell)", tag, m[1], x, y, b))
          end
        end
      end
    end
  end
  H.log(string.format("%s: %d tilemap cells across BG1A/BG1B/BG3A carry an icon code",
    tag, hits))
  return hits
end

-- the icon an ability should show, derived the way the ROM derives it
local MAGICPROP = H.sym("MagicProp") & 0x3FFFFF
local function wantIcon(id)
  local e = H.readRomByte(MAGICPROP + id * 14 + 1)
  if e ~= 0 then
    local i = 0
    while e & 1 == 0 do e = e >> 1; i = i + 1 end
    return H.readRomByte(ELEMGLYPH + i), ELEM[i + 1]
  end
  local x = 0
  while true do
    local key = H.readRomByte(SKILLCLASS + x)
    if key == 0xff then return 0xff, "none" end
    if key == id then
      local cls = H.readRomByte(SKILLCLASS + x + 1)
      if cls == 0 or cls >= 0x80 then return 0xff, "none" end
      local i = 0
      while cls & 1 == 0 do cls = cls >> 1; i = i + 1 end
      return H.readRomByte(CLASSGLYPH + i), ("class" .. i)
    end
    x = x + 2
  end
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),
  H.call(function()
    H.writeByte(CMD3, BATTLE_CMD_BLITZ)
    H.writeByte(BLITZES, 0xff)          -- all eight learned: every row is data
  end),
  -- driveUntil rather than a single press: this probe is also run against a
  -- different ROM (OT6_ROM=<pre-change>.sfc), where the fixture's timing
  -- is not the timing it was generated for and one X can land on a dead
  -- frame.
  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(30),
  H.call(function()
    reportFont("main menu open")
    scanStray("main menu")
    H.screenshot("fieldicons_main_menu")
  end),
  H.pressButtons({ "down" }, 2),
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == SKILLS_ROW_BLITZ
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) }, "skills cursor to Blitz"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_BLITZ end, 300, "blitz page", 5),
  H.waitFrames(90),
  H.call(function()
    reportFont("blitz page open")
    H.log("---- the Blitz page's icon column (col " .. ICON_COL .. ") ----")
    for i = 0, 7 do
      local id, y = BLITZ_ATK0 + i, 1 + i * 2
      local want, why = wantIcon(id)
      local got = cell(BG1A, ICON_COL, y)
      H.log(string.format("blitz %d (id $%02x) row %2d: drew $%02x, authority says $%02x (%s)%s",
        i, id, y, got, want, why, got == want and "" or "   <-- MISMATCH"))
    end
    scanStray("blitz page")
    H.screenshot("fieldicons_blitz_page")
  end),
})
