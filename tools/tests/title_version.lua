-- @suite
-- title_version.lua -- the boot splash shows which OT6 this is: "OT6 v" ..
-- VERSION under the "FINAL FANTASY III" logo, above the copyright lines,
-- and leaves nothing behind when the splash ends.
--
-- The ROM carries the text in Ot6VersionText (c0/ffa0, field/header.asm),
-- stamped after the link from the repo's VERSION by tools/build/rom_version.py;
-- cutscene/ot6_version.asm draws it on BG1's right screen (the screen the
-- splash shows), row 17: all 15 cells of the field (the text centered and
-- blank-padded), columns 8-22, in BG1 tiles $310-$31e, recoloured from the
-- menu font (SmallFontGfx) into the logo's palette 1.  The expectation comes
-- from the tree's VERSION (compose.py injects OT6_VERSION), so a ROM stamped
-- with another version fails: the negative control boots one with OT6_ROM.
--
-- Power-on, no input.  On the splash, once its fade-in is complete, the text
-- is read off the screen two ways:
--   1. VRAM: the BG1 tilemap the PPU fetches (base and scroll from the PPU
--      state) holds the 15 cells, the rest of the row the splash's fill;
--      and each cell's 4bpp tile, read back through the colour mapping, is
--      the expected cell's SmallFontGfx glyph (a blank cell's is blank).
--   2. The frame: every pixel of those cells is its glyph's colour from the
--      live palette; the frame's row offset is calibrated on the logo's
--      cells (vanilla) first.  A screenshot is the evidence.
-- When the title takes over (BG1 back to its left screen), the row is the
-- fill again and the tiles are zero: what the title always saw.
local H = dofile("tools/tests/lib/ot6.lua")

local VR = emu.memType.snesVideoRam
local ROW, CELLS = 17, 15               -- OT6_SPLASH_ROW, OT6_VERSION_CELLS
local TILE = 0x310                      -- OT6_SPLASH_TILE
local FILL = 0x0777                     -- OT6_SPLASH_FILL (_7e7a4c)
local PAL = 1                           -- the logo's palette
local LOGO_Y0, LOGO_Y1, LOGO_X0, LOGO_X1 = 8, 15, 0, 31  -- the vanilla logo (calibration)
-- font pixel s (2bpp) -> palette-1 colour t (4bpp), cutscene/ot6_version.asm
local S2T = { [0] = 1, [1] = 3, [2] = 2, [3] = 4 }

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

H.assertEq(type(OT6_VERSION), "string",
  "compose.py injects the tree's VERSION as OT6_VERSION")
local EXPECT = "OT6 v" .. OT6_VERSION
H.assertEq(#EXPECT <= CELLS, true, string.format("%q fits %d cells", EXPECT, CELLS))
-- the 15 cells: the text centered, blank-padded (rom_version.py field_bytes)
local PAD = (CELLS - #EXPECT) // 2
local SHOWN = string.rep(" ", PAD) .. EXPECT
SHOWN = SHOWN .. string.rep(" ", CELLS - #SHOWN)
local WANT = {}
for i = 1, CELLS do WANT[i] = code(SHOWN:sub(i, i)) end
local X0 = (32 - CELLS) // 2            -- OT6_SPLASH_X: columns 8-22
local FONT = H.sym("SmallFontGfx") & 0x3FFFFF

local function bg1()
  local s = emu.getState()
  local vs = s["ppu.layers[0].vscroll"]
  return {
    map = s["ppu.layers[0].tilemapAddress"],          -- word address
    chr = s["ppu.layers[0].chrAddress"],
    hscroll = s["ppu.layers[0].hscroll"],
    vscroll = vs >= 512 and vs - 1024 or vs,
  }
end
local function vw(word) return emu.readWord(word * 2, VR) end
-- the 64x64 map's screen for this scroll: BG1SC $03, the splash scrolls to 256
local function cellWord(b, x, y)
  local screen = (b.hscroll >= 256) and 0x400 or 0
  return vw(b.map + screen + y * 32 + x)
end
-- 4bpp pixel of tile t
local function pix4(b, t, px, py)
  local base = b.chr + t * 16
  local w01, w23 = vw(base + py), vw(base + 8 + py)
  local bit = 7 - px
  return ((w01 >> bit) & 1) | (((w01 >> (8 + bit)) & 1) << 1)
       | (((w23 >> bit) & 1) << 2) | (((w23 >> (8 + bit)) & 1) << 3)
end
-- 2bpp font pixel of character c, from the ROM
local function font2(c, px, py)
  local p0 = H.readRomByte(FONT + c * 16 + py * 2)
  local p1 = H.readRomByte(FONT + c * 16 + py * 2 + 1)
  local bit = 7 - px
  return ((p0 >> bit) & 1) | (((p1 >> bit) & 1) << 1)
end
local function palColor(i)
  local c = emu.readWord(i * 2, emu.memType.snesCgRam)
  local function e(v) return (v << 3) | (v >> 2) end
  return (e(c & 31) << 16) | (e((c >> 5) & 31) << 8) | e((c >> 10) & 31)
end
-- the frame's 8x8 block for BG1 cell (x,y) shows tile t's opaque pixels in
-- palette pal (frame row offset `off`); (nil, why) on the first mismatch
local function cellShows(b, frame, width, x, y, t, pal, off)
  local sx, sy = x * 8 - (b.hscroll % 256), y * 8 - b.vscroll + off
  for py = 0, 7 do
    for px = 0, 7 do
      local v = pix4(b, t, px, py)
      if v ~= 0 then
        local c = frame[(sy + py) * width + sx + px + 1]
        if c == nil then return nil, "outside the frame" end
        c = c & 0xffffff
        local want = palColor(pal * 16 + v)
        if c ~= want then
          return nil, string.format("pixel (%d,%d) is %06X, colour %d is %06X",
            sx + px, sy + py, c, v, want)
        end
      end
    end
  end
  return true
end

local function splashUp()
  local b = bg1()
  return b.hscroll == 256 and (emu.getState()["ppu.screenBrightness"] or 0) == 15
    and emu.readWord((16 + 4) * 2, emu.memType.snesCgRam) == 0x7fff   -- SplashPal faded in
end

H.run({ maxFrames = 3000 }, {
  H.waitUntil(splashUp, 1200, "the splash, faded in", 1),
  H.waitFrames(30),
  H.call(function()
    H.screenshot("titleversion_splash")         -- the evidence, before the verdict
    local b = bg1()
    -- every check runs and reports before the verdict, so one negative
    -- control shows each check that catches it
    local fails = {}
    local function check(ok, what)
      if not ok then
        fails[#fails + 1] = what
        H.log("splash: MISMATCH " .. what)
      end
    end
    -- 1. VRAM: the row's cells
    for x = 0, 31 do
      local w = cellWord(b, x, ROW)
      local i = x - X0 + 1
      if i >= 1 and i <= CELLS then
        check(w == (PAL << 10) | (TILE + i - 1), string.format(
          "BG1 cell {%d,%d} is $%04X, want $%04X: cell %d, palette 1, tile $%03X",
          x, ROW, w, (PAL << 10) | (TILE + i - 1), i, TILE + i - 1))
      else
        check(w == FILL, string.format(
          "BG1 cell {%d,%d}, outside the text, is $%04X, want the splash's fill $%04X",
          x, ROW, w, FILL))
      end
    end
    -- ...and each cell's tile is the expected glyph, through the colour mapping
    for i = 1, CELLS do
      local t, bad = TILE + i - 1, nil
      for py = 0, 7 do
        for px = 0, 7 do
          if not bad and pix4(b, t, px, py) ~= S2T[font2(WANT[i], px, py)] then
            bad = string.format("pixel (%d,%d) is colour %d, want %d", px, py,
              pix4(b, t, px, py), S2T[font2(WANT[i], px, py)])
          end
        end
      end
      check(bad == nil, string.format("tile $%03X is cell %d of %q (%q) in SmallFontGfx%s",
        t, i, SHOWN, SHOWN:sub(i, i), bad and (": " .. bad) or ""))
    end
    H.log(string.format("splash: BG1 VRAM row %d, cells %d-%d, tiles $%03X-$%03X checked against %q",
      ROW, X0, X0 + CELLS - 1, TILE, TILE + CELLS - 1, SHOWN))

    -- 2. the frame, calibrated on the logo
    local width = emu.getScreenSize().width
    local frame = emu.getScreenBuffer()
    local offs = {}
    for off = -16, 16 do
      local all = true
      for y = LOGO_Y0, LOGO_Y1 do
        for x = LOGO_X0, LOGO_X1 do
          local w = cellWord(b, x, y)
          if not cellShows(b, frame, width, x, y, w & 0x3ff, (w >> 10) & 7, off) then
            all = false; break
          end
        end
        if not all then break end
      end
      if all then offs[#offs + 1] = off end
    end
    H.assertEq(#offs, 1, string.format(
      "exactly one frame row offset shows the logo (BG1 rows %d-%d) (found %d)",
      LOGO_Y0, LOGO_Y1, #offs))
    -- each character's cell must show its glyph in the live palette (the
    -- tile the cell names is the one the PPU draws; checking the glyph
    -- itself is (1)'s job, so here the expected glyph is rendered directly)
    local function glyphShows(x, c, off)
      local sx, sy = x * 8 - (b.hscroll % 256), ROW * 8 - b.vscroll + off
      for py = 0, 7 do
        for px = 0, 7 do
          local want = palColor(PAL * 16 + S2T[font2(c, px, py)])
          local got = frame[(sy + py) * width + sx + px + 1] & 0xffffff
          if got ~= want then
            return nil, string.format("pixel (%d,%d) is %06X, want %06X", sx + px, sy + py, got, want)
          end
        end
      end
      return true
    end
    for i = 1, CELLS do
      local ok, why = glyphShows(X0 + i - 1, WANT[i], offs[1])
      check(ok, string.format("the frame shows %q's cell %d (%q) at {%d,%d}%s",
        SHOWN, i, SHOWN:sub(i, i), X0 + i - 1, ROW, why and (": " .. why) or ""))
    end
    H.assertEq(#fails, 0, string.format("splash: %d check(s) failed (first: %s)",
      #fails, fails[1] or "-"))
    H.log(string.format("splash: VRAM and the frame show %q under the logo (frame row offset %d, "
      .. "calibrated on the logo)", EXPECT, offs[1]))
  end),

  -- the title takes over: BG1 back on its left screen
  H.waitUntil(function() return bg1().hscroll == 0 and not splashUp() end, 1200,
    "the title after the splash", 1),
  H.call(function()
    local b = bg1()
    for x = 0, 31 do
      H.assertEq(vw(b.map + 0x400 + ROW * 32 + x), FILL, string.format(
        "after the splash, BG1's right-screen cell {%d,%d} is the fill again", x, ROW))
    end
    for i = 0, CELLS * 16 - 1 do
      H.assertEq(vw(b.chr + TILE * 16 + i), 0, string.format(
        "after the splash, BG1 tile word $%04X is zero again", b.chr + TILE * 16 + i))
    end
    H.log(string.format("VERSION OK: the splash showed %q; the title sees the VRAM it always did",
      EXPECT))
  end),
})
