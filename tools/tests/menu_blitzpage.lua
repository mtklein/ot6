-- @suite savestate=vargas_won
-- menu_blitzpage.lua -- the field Skills->Blitz page shows name, probe icon
-- and MP price for each Blitz, asserted against the ROM's AttackName,
-- Ot6SkillClassTbl/Ot6ClassGlyphTbl/Ot6ElemGlyphTbl and Ot6AbilityCostTbl.
--
-- The probe icon is the ability's element if it has one, else its break
-- class, else blank; the named cell must also carry art in the menu font's
-- own vram copy.
--
-- The EN field-menu window shows a tilemap row pair in twelve scanlines, odd
-- row eight and even row four, and nothing past row 15 is inside it.  The
-- page is one column of eight rows: 1/3/5/7/9/11/13/15.
--
-- `cursor_pos {x,y}` is the top-left of a 16x16 sprite; an entry at x owns
-- tilemap columns x/8 and x/8+1, so the row it points at starts at x/8+2,
-- that is cursor_x = 8*col - 16.
--
-- Fixture: vargas_won, a real Sabin on Mt. Kolts right after his own boss
-- fight, found in zCharID and entered by walking the character cursor onto
-- his slot.  The learned mask $1d28 is whatever the save holds.
--
-- Two labeled isolation arms write $1d28 directly, to reach two states no
-- real save can produce: all eight Blitzes learned (Sabin's eighth Blitz is
-- level 70) and none learned (Pummel is learned at level 1, so every real
-- Sabin's mask has bit 0 set from the moment he exists).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vargas_won.mss.lua"

local ZMENUSTATE, ZCURSOR = 0x26, 0x4b
local ZCHARID = 0x69                    -- zCharID::Slot1..4 (menu_ram.inc)
local BLITZ_ROW_COLOR = 0x7c            -- zSkillsTextColor::Blitz (menu_ram.inc)
local CHAR_SABIN = 0x05                 -- CHAR::SABIN (const.inc)
local BATTLE_CMD_BLITZ = 0x0a
local BLITZES = 0x1D28                  -- known-blitz bitmask (FixPlayerAttack's)
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_BLITZ = 0x05, 0x06, 0x0a, 0x33
local SKILLS_ROW_BLITZ = 3              -- Espers Magic SwdTech BLITZ Lore Rage Dance

local function st() return H.readByte(ZMENUSTATE) end

-- BG1 screen A tilemap shadow (wBG1Tiles::ScreenA = $7e3849, menu_ram.inc):
-- 2 bytes per cell (char, color), 64 bytes per row; cell(x,y) = char byte.
local BG1A = 0x3849
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end

-- menu text codec (ff6/tools/char_table/text_en.json): 'A'=$80.. 'a'=$9a..
-- '0'=$b4.. ' '=$ff.  " MP" is menu_text_en.inc.raw's OT6_LOADOUT_MP_SUFFIX.
local T = { C=0x82, D=0x83, E=0x84, K=0x8a, L=0x8b, M=0x8c, O=0x8e, P=0x8f,
            DASH=0xc4, SP=0xff }
local LOCKED = { T.DASH,T.SP,T.L,T.O,T.C,T.K,T.E,T.D,T.SP,T.DASH } -- "- LOCKED -"
local MP_SUFFIX = { T.SP, T.M, T.P }
local ZERO_CHAR, DIGIT9 = 0xb4, 0xbd
local PAD = 0xff                        -- fixed_length_en.json: 0xFF = {pad}

-- ---- the three ROM tables this page must agree with ----
local ATKNAME = H.sym("AttackName") & 0x3FFFFF
local NAME_SIZE = 10                    -- AttackName::ITEM_SIZE
local ATKNAME_0 = 0x51                  -- AttackName record 0 is attack id $51
local BLITZ_ATK0 = 0x5d                 -- Pummel; Bum Rush is $64
local function nameBytes(id)
  local t, rec = {}, id - ATKNAME_0
  for i = 0, NAME_SIZE - 1 do t[i + 1] = H.readRomByte(ATKNAME + rec * NAME_SIZE + i) end
  return t
end
local function nameText(id)             -- for the log only
  local s = ""
  for _, b in ipairs(nameBytes(id)) do
    if b == PAD then s = s .. "."
    elseif b >= 0x80 and b <= 0x99 then s = s .. string.char(65 + b - 0x80)
    elseif b >= 0x9a and b <= 0xb3 then s = s .. string.char(97 + b - 0x9a)
    else s = s .. "?" end
  end
  return s
end

-- The probe icon, derived here as Ot6ElemGlyphFor derives it in the ROM:
-- MagicProp record +1 is the element byte (14-byte records); its first set
-- bit indexes Ot6ElemGlyphTbl.  Otherwise Ot6SkillClassTbl gives (id, class)
-- pairs, $ff-terminated; the class byte is a bit mask whose first set bit
-- indexes Ot6ClassGlyphTbl.  Bit 7 is null-break and shows nothing.
local SKILLCLASS = H.sym("Ot6SkillClassTbl") & 0x3FFFFF
local CLASSGLYPH = H.sym("Ot6ClassGlyphTbl") & 0x3FFFFF
local ELEMGLYPH = H.sym("Ot6ElemGlyphTbl") & 0x3FFFFF
local MAGICPROP = H.sym("MagicProp") & 0x3FFFFF
local MAGICPROP_REC = 14
local function firstBit(m)              -- bit mask -> index of its lowest set bit
  local i = 0
  while m & 1 == 0 do m = m >> 1; i = i + 1 end
  return i
end
local function iconGlyph(id)            -- -> glyph tile, or PAD for neither
  local e = H.readRomByte(MAGICPROP + id * MAGICPROP_REC + 1)
  if e ~= 0 then return H.readRomByte(ELEMGLYPH + firstBit(e)) end
  local x = 0
  while true do
    local key = H.readRomByte(SKILLCLASS + x)
    if key == 0xff then return PAD end
    if key == id then
      local cls = H.readRomByte(SKILLCLASS + x + 1)
      if cls == 0 or cls >= 0x80 then return PAD end
      return H.readRomByte(CLASSGLYPH + firstBit(cls))
    end
    x = x + 2
  end
end
-- The icon's cell must also have art in the menu font's own vram copy.
local ELEM_CELLS = {}
for i = 0, 7 do ELEM_CELLS[H.readRomByte(ELEMGLYPH + i)] = i end
local function fontCellHasArt(cellCode)
  -- BG1's char base is word $5000 (hBG12NBA = $65, menu_init_2.asm:433) and the
  -- menu's copy of the font is 4bpp there: 32 bytes per tile.
  local base = 0x5000 * 2 + cellCode * 32
  for i = 0, 31 do
    if emu.read(base + i, emu.memType.snesVideoRam) ~= 0 then return true end
  end
  return false
end

-- Ot6AbilityCostTbl: (key, cost) pairs, $ff-terminated (ot6_boost.asm:671).
local COSTTBL = H.sym("Ot6AbilityCostTbl") & 0x3FFFFF
local function costOf(id)
  local x = 0
  while true do
    local key = H.readRomByte(COSTTBL + x)
    if key == 0xff then return 0 end    -- unpriced id is free (Ot6CostFor @free)
    if key == id then return H.readRomByte(COSTTBL + x + 1) end
    x = x + 2
  end
end

-- ---- page geometry, mirroring skills.asm's Ot6BlitzPageDraw ----
local NAME_COL, ICON_COL, COST_COL = 3, 14, 16
local function blitzRow(i) return 1 + i * 2 end   -- odd rows 1/3/5/../15

local function assertRun(x0, y, bytes, what)
  for i, b in ipairs(bytes) do
    H.assertEq(cell(x0 + i - 1, y), b,
      string.format("%s: cell {%d,%d}", what, x0 + i - 1, y))
  end
end

-- A row the page never draws on must be untouched ($00 from ClearBG1ScreenA).
local function assertRowBlank(y, what)
  for x = 0, 31 do
    H.assertEq(cell(x, y), 0, string.format("%s: cell {%d,%d} blank", what, x, y))
  end
end

-- An even tilemap row is four scanlines in this window and rows past 15 are
-- outside it entirely, so nothing may land on either.  Column 30 is the
-- window's own right border.  Columns 0-2 are the cursor's gutter on every
-- row here, because every row is cursored.
local function assertGeometry(what)
  for y = 0, 27 do
    if y % 2 == 0 or y > 15 then
      assertRowBlank(y, string.format(
        "%s: row %d is unusable (%s)", what, y,
        y > 15 and "outside the window" or "even: four scanlines"))
    end
  end
  for y = 1, 15, 2 do
    for _, x in ipairs({ 0, 1, 2, 13, 15, 30, 31 }) do
      H.assertEq(cell(x, y), 0, string.format(
        "%s: {%d,%d} must stay blank -- %s", what, x, y,
        (x <= 2) and "the cursor sprite's gutter"
          or (x >= 30) and "the window's border column"
          or "the gap between the page's three fields"))
    end
    -- ... and everything right of the price, out to the border
    for x = COST_COL + 5, 29 do
      H.assertEq(cell(x, y), 0, string.format(
        "%s: {%d,%d} is past the price field", what, x, y))
    end
  end
end

-- `cursor_pos {x,y}` assembles to `.byte x, y`, two bytes per entry ($4b =
-- cols*row + col, cols is 1 here, so $4b is the row).  y is 116 + n*12 and
-- tilemap row = 2n+1, so the row an entry points at is (y-116)/6 + 1.
local CURSOR_POS = H.sym("Ot6BlitzCursorPos") & 0x3FFFFF
local function assertCursorGutter(n, what)
  local cx = H.readRomByte(CURSOR_POS + n * 2)
  local cy = H.readRomByte(CURSOR_POS + n * 2 + 1)
  local col, y = cx // 8, (cy - 116) // 6 + 1
  H.assertEq(y % 2 == 1 and y >= 1 and y <= 15, true, string.format(
    "%s: cursor entry %d (y=%d) points at tilemap row %d, which this window "
    .. "does not show whole", what, n, cy, y))
  H.assertEq(y, blitzRow(n), string.format(
    "%s: cursor entry %d must point at Blitz %d's row", what, n, n))
  for _, x in ipairs({ col, col + 1 }) do
    H.assertEq(cell(x, y), 0, string.format(
      "%s: cursor entry %d sits at x=%d, so tilemap {%d,%d} is under the "
      .. "sprite and must be blank", what, n, cx, x, y))
  end
  -- the row it points at begins in the next column.
  H.assertEq(cell(col + 2, y) ~= 0, true, string.format(
    "%s: cursor entry %d at x=%d reserves columns %d-%d, so row %d must start "
    .. "at column %d (vanilla: cursor_x = 8*col - 16)",
    what, n, cx, col, col + 1, n, col + 2))
  H.assertEq(col + 2, NAME_COL, string.format(
    "%s: cursor entry %d and the page's name column must agree", what, n))
end

-- ---- one row ----
local function assertLearnedRow(i)
  local id, y = BLITZ_ATK0 + i, blitzRow(i)
  assertRun(NAME_COL, y, nameBytes(id), string.format("blitz %d name %s", i, nameText(id)))
  local want = iconGlyph(id)
  H.assertEq(cell(ICON_COL, y), want, string.format(
    "blitz %d (%s) draws the probe icon its own data gives it -- MagicProp's "
    .. "element byte first, Ot6SkillClassTbl's break class second -- at {%d,%d}",
    i, nameText(id), ICON_COL, y))
  -- and the cell it named is one the field font has art in.
  if want ~= PAD then
    H.assertEq(fontCellHasArt(want), true, string.format(
      "blitz %d (%s) names font cell $%02x, so the MENU font must carry art "
      .. "there -- %s", i, nameText(id), want,
      ELEM_CELLS[want] and "an ELEMENT tile, uploaded by Ot6MenuIcons4bpp_ext"
        or "a class glyph, which ships in the vanilla art"))
  end
  -- the price, right-aligned two digits plus " MP", against Ot6AbilityCostTbl
  local cost = costOf(id)
  H.assertEq(cost > 0, true, string.format(
    "blitz %d (%s) is priced -- 'free-to-learn is not free-to-use', so a zero "
    .. "here would mean the page had nothing to show", i, nameText(id)))
  local tens = cost // 10
  H.assertEq(cell(COST_COL, y), tens > 0 and (ZERO_CHAR + tens) or PAD,
    string.format("blitz %d cost %d: tens cell {%d,%d} (blank, not '0', under 10)",
      i, cost, COST_COL, y))
  H.assertEq(cell(COST_COL + 1, y), ZERO_CHAR + (cost % 10),
    string.format("blitz %d cost %d: ones cell {%d,%d}", i, cost, COST_COL + 1, y))
  assertRun(COST_COL + 2, y, MP_SUFFIX, string.format("blitz %d ' MP'", i))
end

-- A tier the character has not reached shows "- LOCKED -" across the ten
-- name cells; the class and price fields are blank.
local function assertLockedRow(i)
  local y = blitzRow(i)
  H.assertEq(#LOCKED, NAME_SIZE,
    "the locked marker must be exactly a name field wide, or learning a Blitz "
    .. "leaves the tail of the marker on screen")
  assertRun(NAME_COL, y, LOCKED, string.format("blitz %d '- LOCKED -'", i))
  H.assertEq(cell(ICON_COL, y), PAD, string.format(
    "blitz %d is not learned, so it advertises no probe at {%d,%d}", i, ICON_COL, y))
  for x = COST_COL, COST_COL + 4 do
    H.assertEq(cell(x, y), PAD, string.format(
      "blitz %d is not learned, so it carries no price at {%d,%d}", i, x, y))
  end
end

-- The vanilla combo glyphs, from BlitzInputTileTbl by way of
-- GetBlitzInputTiles.  None of these may appear anywhere on this page.
local COMBO_TILES = { [0xd4] = "up", [0xd5] = "right", [0xd6] = "down-left" }
local function assertNoCombos(what)
  for y = 0, 27 do
    for x = 0, 31 do
      local b = cell(x, y)
      H.assertEq(COMBO_TILES[b] == nil, true, string.format(
        "%s: {%d,%d} draws the %s arrow ($%02x) -- Blitz has been a menu since "
        .. "v0.4 and this page must not teach button combos", what, x, y,
        COMBO_TILES[b] or "?", b))
    end
  end
end

local function teach(mask) H.writeByte(BLITZES, mask) end

local learnedMask = nil                 -- $1d28 as read off the save
local sabinSlot = nil                   -- SABIN's menu slot, found not assumed

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  H.call(function()
    learnedMask = H.readByte(BLITZES)
    local n = 0
    for i = 0, 7 do if (learnedMask >> i) & 1 == 1 then n = n + 1 end end
    H.log(string.format("$1d28 = $%02x as saved: %d of 8 tiers learned",
      learnedMask, n))
    H.assertEq(n > 0 and n < 8, true,
      "the real mask mixes learned and locked rows -- both render paths run")
    local lo, hi = 0, 0
    for i = 0, 7 do
      local c = costOf(BLITZ_ATK0 + i)
      if c > 0 and c < 10 then lo = lo + 1 end
      if c >= 10 then hi = hi + 1 end
      H.log(string.format("blitz %d %s costs %d MP, probe icon $%02x",
        i, nameText(BLITZ_ATK0 + i), c, iconGlyph(BLITZ_ATK0 + i)))
    end
    H.assertEq(lo > 0 and hi > 0, true,
      "the Blitz ladder spans one- and two-digit prices, so this page's "
      .. "right-aligned two-digit field is doing real work")
    local nElem, nClass, nBlank = 0, 0, 0
    for i = 0, 7 do
      local g = iconGlyph(BLITZ_ATK0 + i)
      if g == PAD then nBlank = nBlank + 1
      elseif ELEM_CELLS[g] then nElem = nElem + 1
      else nClass = nClass + 1 end
    end
    H.log(string.format("ladder icons: %d element, %d class, %d blank",
      nElem, nClass, nBlank))
    H.assertEq(nElem > 0 and nClass > 0 and nBlank > 0, true,
      "the Blitz ladder must exercise all three answers of the icon column -- "
      .. "element, break class, and nothing at all -- or the assertions "
      .. "below only ever test one of them")
  end),

  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),
  H.call(function()
    local ids = {}
    for s = 0, 3 do
      local id = H.readByte(ZCHARID + s)
      ids[#ids + 1] = string.format("slot %d = char $%02x", s, id)
      if id == CHAR_SABIN and sabinSlot == nil then sabinSlot = s end
    end
    H.log("party: " .. table.concat(ids, ", "))
    H.assertEq(sabinSlot ~= nil, true, "vargas_won's party contains SABIN")
    local rec = 0x1600 + 37 * CHAR_SABIN
    local has = false
    for i = 0, 3 do
      if H.readByte(rec + 0x16 + i) == BATTLE_CMD_BLITZ then has = true end
    end
    H.assertEq(has, true,
      "SABIN's own record carries BATTLE_CMD::BLITZ -- nothing is installed")
  end),
  H.pressButtons({ "down" }, 2),            -- Items -> Skills
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.waitFrames(10),
  H.driveUntil(function() return H.readByte(ZCURSOR) == sabinSlot end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "cursor onto SABIN"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.readByte(BLITZ_ROW_COLOR), 0x20,
      "Blitz row enabled -- SABIN's own record carries the command")
  end),

  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == SKILLS_ROW_BLITZ
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "skills cursor to Blitz"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_BLITZ end, 300,
    "blitz page open via the player path", 5),
  H.waitFrames(90),                         -- draws + DMA settle

  H.call(function()
    local nL = 0
    for i = 0, 7 do
      if (learnedMask >> i) & 1 == 1 then
        assertLearnedRow(i)
        nL = nL + 1
      else
        assertLockedRow(i)
      end
    end
    assertNoCombos("real mask")
    assertGeometry("real mask")
    for n = 0, 7 do assertCursorGutter(n, "real mask") end
    H.screenshot("blitz_page_player_path")
    H.log(string.format("RENDER OK: Skills->Blitz via the player's path for a "
      .. "REAL SABIN -- %d learned tiers carry name + probe icon + price, %d "
      .. "unreached tiers say '- LOCKED -', no combo glyph anywhere, every "
      .. "drawn cell on an ODD row inside row 15, clear of the border column "
      .. "and of every cursor's gutter", nL, 8 - nL))
  end),

  H.pressButtons({ "down" }, 2),
  H.waitFrames(20),
  H.pressButtons({ "down" }, 2),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(H.readByte(ZMENUSTATE), ST_BLITZ, "still on the blitz page")
    H.assertEq(H.readByte(ZCURSOR), 2,
      "one column: $4b IS the blitz index, so two steps down is Blitz 2 "
      .. "(LoadBigText reads $7e9d89 at $4b to pick the description)")
    for n = 0, 7 do assertCursorGutter(n, "cursor on blitz 2") end
    assertGeometry("cursor on blitz 2")
    H.screenshot("blitz_page_cursor_walk")
    H.log("CURSOR WALK: the sprite is on Blitz 2 and columns 1-2 are still empty "
      .. "on every row -- the gutter is a property of the page, not of which row "
      .. "happens to be selected")
  end),

  -- Isolation arm 1: all eight Blitzes learned, no locked row anywhere.
  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_SKILLS end, 300,
    "back out of the blitz page", 5),
  H.call(function()
    teach(0xff)
    H.log("[isolation arm] $1d28 := $ff -- the L70 all-eight Sabin")
  end),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_BLITZ end, 300,
    "blitz page reopened with all eight learned", 5),
  H.waitFrames(90),

  H.call(function()
    for i = 0, 7 do assertLearnedRow(i) end
    -- the marker is gone from the page entirely: a learned row starts with a
    -- name's first letter, never with the marker's leading dash.
    for i = 0, 7 do
      H.assertEq(cell(NAME_COL, blitzRow(i)) ~= T.DASH, true, string.format(
        "blitz %d is learned, so it must not draw the locked marker at {%d,%d}",
        i, NAME_COL, blitzRow(i)))
    end
    assertNoCombos("8 learned")
    assertGeometry("8 learned")
    for n = 0, 7 do assertCursorGutter(n, "8 learned") end
    H.screenshot("blitz_page_full")
    H.log("FULL PAGE: all eight tiers learned -- eight names, their classes and "
      .. "their prices, the '- LOCKED -' marker nowhere on the page")
  end),

  -- Isolation arm 2: none learned, eight locked rows and not one digit.
  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_SKILLS end, 300,
    "back out of the blitz page", 5),
  H.call(function()
    teach(0x00)
    H.log("[isolation arm] $1d28 := $00 -- the empty ladder no real save holds")
  end),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_BLITZ end, 300,
    "blitz page reopened with none learned", 5),
  H.waitFrames(90),

  H.call(function()
    for i = 0, 7 do assertLockedRow(i) end
    -- no digit anywhere: an unlearned page must not price a thing
    for y = 1, 15, 2 do
      for x = 0, 31 do
        local b = cell(x, y)
        H.assertEq(b >= ZERO_CHAR and b <= DIGIT9, false, string.format(
          "nothing is learned, so {%d,%d} must not carry a digit (got $%02x)",
          x, y, b))
      end
    end
    assertNoCombos("none learned")
    assertGeometry("none learned")
    for n = 0, 7 do assertCursorGutter(n, "none learned") end
    H.screenshot("blitz_page_none_learned")
    H.log("EMPTY LADDER: nothing learned -- eight '- LOCKED -' rows, not one "
      .. "class glyph, not one digit on the page")
  end),
})
