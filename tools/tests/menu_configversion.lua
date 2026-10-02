-- @suite
-- menu_configversion.lua -- the Config screen shows which OT6 this is:
-- "OT6 v" .. VERSION in the version tab, top-left, on both Config pages.
--
-- The ROM carries the text in Ot6VersionText (c0/ffa0, field/header.asm),
-- stamped after the link from the repo's VERSION by tools/build/rom_version.py;
-- config.asm DrawConfigVersion draws it on BG3 inside ConfigVersionWindow,
-- the "Config" tab's mirror.  The expectation here comes from the tree's
-- VERSION file (compose.py injects it as OT6_VERSION), not from the ROM, so
-- a ROM stamped with another version fails: that is the negative control
-- (a build with a different VERSION, booted with OT6_ROM/OT6_DBG).
--
-- Boot: cold Continue of the narshe-mission-v1 battery (world (84,34), on
-- foot), then the player's path: X opens the main menu, the cursor goes down
-- to Config (row 5: Item Skills Equip Relic Status CONFIG Save), A opens it;
-- Down past the last row of page 1 scrolls to page 2.  Nothing is written
-- and no option is changed (no Left/Right, no A on a row).
--
-- The text is read off the screen two ways, on each page:
--   1. VRAM: the BG3 tilemap the PPU is fetching (its base from the PPU
--      state, not assumed) holds the expected character codes, in white,
--      at the tab's cells, with nothing after them inside the tab; and each
--      code's tile in BG3's character VRAM is the ROM font's glyph
--      (SmallFontGfx), so those codes draw those letters.
--   2. The frame: every 8x8 cell of the picture Mesen produced matches its
--      glyph pixel for pixel (ink in the palette's colours, no ink where the
--      glyph has none).  The frame's row offset is calibrated on the
--      vanilla "Config" title on the same BG3 row first, so the mapping is
--      measured, not assumed.  A screenshot of each page is the evidence.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE, ZCURSOR, ZPAGE = 0x26, 0x4b, 0x4a
local ST_MAIN, ST_CONFIG = 0x05, 0x0e   -- MENU_STATE::CONFIG_SELECT
local MAIN_ROW_CONFIG = 5
local TEXT_X, TEXT_Y = 2, 2             -- DrawConfigVersion: lda_pos BG3A, {2, 2}
local TITLE_X = 24                      -- CONFIG_TITLE: BG3A, {24, 2}, "Config"
local WHITE_ATTR = 0x20                 -- BG3_TEXT_COLOR::DEFAULT (palette 0, priority)

local VR = emu.memType.snesVideoRam

-- the menu font's small-text codes (ff6/tools/char_table/text_en.json)
local function code(ch)
  local b = ch:byte()
  if ch == " " then return 0xff end
  if ch == "." then return 0xc5 end
  if ch == "-" then return 0xc4 end
  if b >= 65 and b <= 90 then return 0x80 + b - 65 end
  if b >= 97 and b <= 122 then return 0x9a + b - 97 end
  if b >= 48 and b <= 57 then return 0xb4 + b - 48 end
  error("no menu-font code for " .. string.format("%q", ch), 0)
end
local function encode(s)
  local t = {}
  for i = 1, #s do t[i] = code(s:sub(i, i)) end
  return t
end

H.assertEq(type(OT6_VERSION), "string",
  "compose.py injects the tree's VERSION as OT6_VERSION")
local EXPECT = "OT6 v" .. OT6_VERSION
local WANT = encode(EXPECT)
local TITLE = encode("Config")
local FONT = H.sym("SmallFontGfx") & 0x3FFFFF
-- the OT6 symbols, looked up where they are used: a ROM from before the
-- version tab has neither, and fails on the screen first
local function romSym(a, name)
  H.assertEq(a ~= nil, true, "this ROM's symbols include " .. name)
  return a & 0x3FFFFF
end

local function st() return H.readByte(ZMENUSTATE) end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

-- BG3 as the PPU sees it right now
local function bg3()
  local s = emu.getState()
  local vs = s["ppu.layers[2].vscroll"]
  return {
    map = s["ppu.layers[2].tilemapAddress"] * 2,      -- word -> byte address
    chr = s["ppu.layers[2].chrAddress"] * 2,
    hscroll = s["ppu.layers[2].hscroll"],
    vscroll = vs >= 512 and vs - 1024 or vs,          -- 10-bit, signed
  }
end
local function mapWord(b, x, y) return emu.readWord(b.map + (y * 32 + x) * 2, VR) end

-- one 2bpp pixel of tile `t` from BG3's character VRAM
local function glyphPixel(b, t, px, py)
  local p0 = emu.read(b.chr + t * 16 + py * 2, VR)
  local p1 = emu.read(b.chr + t * 16 + py * 2 + 1, VR)
  local bit = 7 - px
  return ((p0 >> bit) & 1) | (((p1 >> bit) & 1) << 1)
end

-- CGRAM BGR555 -> the frame's RGB888 (5-bit c -> c<<3 | c>>2)
local function palColor(i)
  local c = emu.readWord(i * 2, emu.memType.snesCgRam)
  local function e(v) return (v << 3) | (v >> 2) end
  return (e(c & 31) << 16) | (e((c >> 5) & 31) << 8) | e((c >> 10) & 31)
end

-- does the frame's 8x8 block for BG3 cell (x,y) show tile t in palette pal,
-- with the frame's row offset `off`?  (nil, why) on the first mismatch.
local function cellShows(b, frame, width, x, y, t, pal, off)
  local ink = { palColor(pal * 4 + 1), palColor(pal * 4 + 2), palColor(pal * 4 + 3) }
  local sx, sy = x * 8 - b.hscroll, y * 8 - b.vscroll + off
  for py = 0, 7 do
    for px = 0, 7 do
      local v = glyphPixel(b, t, px, py)
      local c = frame[(sy + py) * width + sx + px + 1]
      if c == nil then return nil, "outside the frame" end
      c = c & 0xffffff
      if v ~= 0 and c ~= ink[v] then
        return nil, string.format("pixel (%d,%d) is %06X, glyph ink %d is %06X",
          sx + px, sy + py, c, v, ink[v])
      end
      if v == 0 and (c == ink[1] or c == ink[2] or c == ink[3]) then
        return nil, string.format("pixel (%d,%d) is ink %06X where the glyph has none",
          sx + px, sy + py, c)
      end
    end
  end
  return true
end

local function hexs(t)
  local o = {}
  for i, v in ipairs(t) do o[i] = string.format("%02X", v) end
  return table.concat(o, " ")
end

local pageChecked = {}

-- Each page's checks all run and report before the page fails, so one
-- negative control shows every check that catches it (VRAM and frame).
local function checkPage(page)
  local b = bg3()
  local width = emu.getScreenSize().width
  local frame = emu.getScreenBuffer()
  H.assertEq(bright(), 15, page .. ": the screen is fully faded in")
  local fails = {}
  local function check(ok, what)
    if not ok then
      fails[#fails + 1] = what
      H.log(page .. ": MISMATCH " .. what)
    end
  end

  -- 1. VRAM tilemap: the tab's cells hold the expected text in white
  local got = {}
  for i = 1, #WANT do
    local w = mapWord(b, TEXT_X + i - 1, TEXT_Y)
    got[i] = w & 0xff
    check(w >> 8 == WHITE_ATTR, string.format(
      "BG3 VRAM cell {%d,%d} attribute $%02X, want $%02X (white text)",
      TEXT_X + i - 1, TEXT_Y, w >> 8, WHITE_ATTR))
    check(got[i] == WANT[i], string.format(
      "BG3 VRAM cell {%d,%d} is $%02X, want $%02X: %q's character %d (%q)",
      TEXT_X + i - 1, TEXT_Y, got[i], WANT[i], EXPECT, i, EXPECT:sub(i, i)))
  end
  H.log(string.format("%s: BG3 VRAM tilemap at {%d,%d}: %s (want %s = %q)",
    page, TEXT_X, TEXT_Y, hexs(got), hexs(WANT), EXPECT))
  local tabSym = H.sym("ConfigVersionWindow")
  check(tabSym ~= nil, "this ROM's symbols include ConfigVersionWindow")
  -- make_window: .addr pos, .byte w, h
  local tab = tabSym and H.readRomByte((tabSym & 0x3FFFFF) + 2) or 10
  H.assertEq(#WANT <= tab, true, string.format(
    "%q (%d characters) fits the version tab's %d columns", EXPECT, #WANT, tab))
  for x = TEXT_X + #WANT, TEXT_X + tab - 1 do
    check(mapWord(b, x, TEXT_Y) == 0, string.format(
      "BG3 VRAM cell {%d,%d} after the text, inside the tab, is blank", x, TEXT_Y))
  end
  for x = 0, TEXT_X - 1 do
    check(mapWord(b, x, TEXT_Y) == 0, string.format(
      "BG3 VRAM cell {%d,%d} left of the text is blank", x, TEXT_Y))
  end
  for i = 1, #TITLE do
    check(mapWord(b, TITLE_X + i - 1, TEXT_Y) & 0xff == TITLE[i], string.format(
      "the Config title's cell {%d,%d} is still there", TITLE_X + i - 1, TEXT_Y))
  end
  -- ...and each expected code's tile is the ROM font's glyph
  for i = 1, #WANT do
    local same = true
    for j = 0, 15 do
      if emu.read(b.chr + WANT[i] * 16 + j, VR) ~= H.readRomByte(FONT + WANT[i] * 16 + j) then
        same = false
      end
    end
    check(same, string.format("BG3 tile $%02X (%q) is SmallFontGfx's glyph",
      WANT[i], EXPECT:sub(i, i)))
  end

  -- 2. the frame: calibrate the row offset on the vanilla "Config" title
  local offs = {}
  for off = -16, 16 do
    local all = true
    for i = 1, #TITLE do
      local w = mapWord(b, TITLE_X + i - 1, TEXT_Y)
      if not cellShows(b, frame, width, TITLE_X + i - 1, TEXT_Y, w & 0xff, (w >> 10) & 7, off) then
        all = false; break
      end
    end
    if all then offs[#offs + 1] = off end
  end
  H.assertEq(#offs, 1, string.format(
    "%s: exactly one frame row offset shows the vanilla Config title (found %d)", page, #offs))
  local off = offs[1]
  for i = 1, #WANT do
    local ok, why = cellShows(b, frame, width, TEXT_X + i - 1, TEXT_Y, WANT[i], 0, off)
    check(ok, string.format("the frame shows %q's character %d (%q) at cell {%d,%d}%s",
      EXPECT, i, EXPECT:sub(i, i), TEXT_X + i - 1, TEXT_Y, why and (": " .. why) or ""))
  end
  for x = TEXT_X + #WANT, TEXT_X + tab - 1 do
    local ok, why = cellShows(b, frame, width, x, TEXT_Y, 0xff, 0, off)
    check(ok, string.format("the frame shows no ink at cell {%d,%d}, after the text%s",
      x, TEXT_Y, why and (": " .. why) or ""))
  end
  H.assertEq(#fails, 0, string.format("%s: %d check(s) failed (first: %s)",
    page, #fails, fails[1] or "-"))
  H.log(string.format("%s: VRAM and frame show %q at BG3 {%d,%d} (frame row offset %d, "
    .. "calibrated on the Config title)", page, EXPECT, TEXT_X, TEXT_Y, off))
  pageChecked[page] = true
end

local SETTINGS = 0x1d4d                 -- $1d4d-$1d54: the Config options
local before = {}

H.run({ maxFrames = 40000 }, {
  -- cold Continue (the checkpoint's $307ff0=3 preselects slot 3)
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue to the narshe-mission world entry point", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "cold Continue fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("narshe-mission-v1")
    for i = 0, 7 do before[i] = H.readByte(SETTINGS + i) end
  end),

  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),
  H.driveUntil(function() return H.readByte(ZCURSOR) == MAIN_ROW_CONFIG end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "main menu cursor onto Config"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CONFIG end, 600, "the Config menu", 5),
  H.waitUntil(function() return bright() >= 15 end, 300, "Config fade-in", 2),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(ZPAGE), 0, "Config opens on page 1")
    H.screenshot("configversion_page1")    -- the evidence, before the verdict
    checkPage("page 1")
  end),

  -- Down past the last row of page 1 scrolls to page 2 (MenuState_50)
  H.driveUntil(function() return H.readByte(ZPAGE) == 1 and st() == ST_CONFIG end, 1200,
    { H.pressButtons({ "down" }, 2), H.waitFrames(10) }, "Config page 2"),
  H.waitFrames(30),
  H.call(function()
    H.screenshot("configversion_page2")    -- the evidence, before the verdict
    checkPage("page 2")
  end),

  H.driveUntil(function() return st() ~= ST_CONFIG end, 600,
    { H.pressButtons({ "b" }, 4), H.waitFrames(20) }, "leave Config with B"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(pageChecked["page 1"] and pageChecked["page 2"], true, "both pages checked")
    for i = 0, 7 do
      H.assertEq(H.readByte(SETTINGS + i), before[i], string.format(
        "Config option byte $%04X unchanged (the test only moved the cursor)", SETTINGS + i))
    end
    -- the ROM field the screen came from, for the log
    local raw = {}
    local field = romSym(H.sym("Ot6VersionText"), "Ot6VersionText")
    for i = 0, 15 do raw[#raw + 1] = H.readRomByte(field + i) end
    H.log("Ot6VersionText (c0/ffa0) = " .. hexs(raw))
    for i = 1, #WANT do
      H.assertEq(raw[i], WANT[i], string.format("Ot6VersionText byte %d", i - 1))
    end
    H.assertEq(raw[#WANT + 1], 0, "Ot6VersionText is $00-terminated after the text")
    H.log(string.format("VERSION OK: the Config screen shows %q on both pages "
      .. "(VRAM tilemap + glyph tiles, and the frame's pixels)", EXPECT))
  end),
})
