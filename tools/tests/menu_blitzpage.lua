-- @suite frontier=arvis_wake
-- menu_blitzpage.lua -- issue #46: the field Skills->Blitz page describes the
-- ABILITY, not a retired input system.
--
-- v0.4 turned Blitz into a menu (Ot6BlitzListOpen, ot6_kits.asm, in place of
-- _c1776b's 64-frame pad-edge buffer and UpdateMenuState_3d's button matcher).
-- The FIELD page went on drawing vanilla's button combos -- eight ten-tile runs
-- of arrow and shoulder glyphs out of BlitzInputTileTbl.  Measured on the
-- pre-change ROM with tools/tests/probe_blitzpage.lua: rows 1/5/9/13, columns
-- 4-13 and 18-27, cells $d4/$d5/$d6 (the up / right / down-left arrows) and
-- $91/$8b/$97/$98 (R/L/X/Y) -- e.g. row 9 read `RLRLXY`, row 13 `RLXY->->`.
-- Nothing on the page could be acted on: the combos do nothing now.
--
-- The page shows name, break class and MP price instead, and this test asserts
-- all three against the SAME authorities the rest of the game reads, so none of
-- them can drift into a second opinion:
--
--   * the NAME comes out of the ROM's own AttackName records (the table
--     ListTextCmd_0f renders the battle Blitz list from), read here with
--     H.sym + readRomByte rather than hardcoded, so a text re-encode cannot
--     silently invalidate the expectation;
--   * the PROBE ICON is checked against the same three ROM tables
--     Ot6ElemGlyphFor walks -- MagicProp's element byte, then Ot6SkillClassTbl
--     (the very table the chip consults, ot6_break.asm:1266) into
--     Ot6ClassGlyphTbl.  Element first, class second, blank when neither.
--
--     #53 IS WHY THIS IS THREE TABLES AND NOT ONE.  Until it landed the column
--     was CLASS-ONLY, and this test asserted five of the eight rows BLANK --
--     correct for what the page could then draw, and wrong about the game:
--     AuraBolt is holy, Fire Dance fire, Air Blade wind, and those three
--     carried a real elemental probe the page could not show, because the
--     element tiles were uploaded into the BATTLE font only.  The expectation
--     changed here because the correct BEHAVIOUR changed, not to get green:
--     the three rows are now asserted to carry their element, and only Mantra
--     and Spiraler stay blank (neither element nor class -- honest).  Measured
--     before and after on purpose-built ROMs, tools/tests/probe_fieldicons.lua.
--
--     Each named cell is ALSO checked to have art in the menu font's own vram
--     copy, which is the half a tilemap assertion cannot see: a page can name
--     $eb all day and $eb can be sixteen zero bytes, which is exactly the
--     state the field font was in before #53;
--   * the PRICE is checked against Ot6AbilityCostTbl, the table Ot6CostFor
--     scans for the charge and for the battle row.  The numbers are read, not
--     written down: a balance retune must not turn this test red, but a page
--     that stops agreeing with the cost authority must.
--
-- GEOMETRY, in the loadout pages' style (#43, and the reason this window has
-- now bitten us four times).  The EN field-menu window shows a tilemap row PAIR
-- in twelve scanlines -- odd row eight, even row four -- and nothing past row 15
-- is inside it (probe_ragegeom.lua; vanilla says it from the other side, every
-- EN cursor list here being `cursor_pos {x, 116 + n*12}`, skills.asm:125-126).
-- The page is one column of eight now, on rows 1/3/5/7/9/11/13/15, so the
-- EVEN-ROW / ROW>15 / BORDER-COLUMN canary below is a genuine constraint on all
-- eight rows at once -- there is no spare odd row left to hide a mistake in.
--
-- THE CURSOR GUTTER (#43 round 3).  `cursor_pos {x,y}` is the TOP-LEFT of a
-- 16x16 sprite, so an entry at x owns tilemap columns x/8 and x/8+1 and the row
-- it points at must start at x/8+2 -- cursor_x = 8*col - 16, vanilla's rule in
-- every list it draws in this window.  Vanilla's own blitz page drew at column
-- 4 under a cursor at x=8, one column of dead air; the names start at 3 now.
-- The canary reads BOTH halves out of the ROM/tilemap the menu itself uses, so
-- neither can move alone.  It is duplicated from menu_ragepage.lua rather than
-- shared: the only lua the runner inlines is lib/ot6{,_field,_contract}.lua,
-- and those three files ARE the frontier mint signature
-- (lib/frontier_stamp.sh:49-55), so a helper added there would mark every
-- minted fixture drifted.
--
-- Fixture: arvis_wake (the menu_swdtechpage / menu_ragepage boot).  Its lead has
-- no Blitz command, so it is installed the house "install state" way: the lead's
-- third battle-command byte becomes BATTLE_CMD::BLITZ ($0a) and the known-blitz
-- bitmask $1d28 is written directly.  Three phases: THREE known (so the same
-- render carries learned rows AND locked ones), ALL EIGHT (every row a Blitz,
-- the state that proves the locked marker cannot leak onto a learned row, and
-- the only state that puts a two-digit price on screen), and NONE (the page a
-- fresh Sabin opens -- eight locked rows and not one number).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/arvis_wake.mss.lua"

local ZMENUSTATE, ZCURSOR = 0x26, 0x4b
local BLITZ_ROW_COLOR = 0x7c            -- zSkillsTextColor::Blitz (menu_ram.inc)
local CMD3 = 0x1618                     -- lead char's 3rd battle command
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

-- ---- the three ROM authorities this page must agree with ----
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

-- THE PROBE ICON (#53), derived here exactly as Ot6ElemGlyphFor derives it in
-- the ROM: the ability's ELEMENT if it has one, else its BREAK CLASS, else
-- blank.  Three tables, all read out of the ROM so a data edit cannot leave a
-- stale expectation behind:
--   * MagicProp record +1 is the element byte (battle_main.asm:7037, 14-byte
--     records).  First set bit indexes Ot6ElemGlyphTbl.
--   * Ot6SkillClassTbl: (id, class) pairs, $ff-terminated (ot6_class.asm:184).
--     The class byte is a BIT mask and the first set bit indexes
--     Ot6ClassGlyphTbl -- the same walk Ot6ToolListIcon_ext and the hud's
--     weakness strip do.  Bit 7 is null-break: teaches nothing, shows nothing.
-- Element BEFORE class is the design ("consult the class when the ability has
-- no element"), and asserting it in that order here is what stops the page
-- quietly reverting to #46's class-only answer: three Blitzes have an element
-- AND no class, so a class-only page draws PAD on all three.
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
-- ... and the icon must be a cell the menu font actually HAS art in.  Before
-- #53 the element tiles were uploaded for BATTLE only, so a field page asking
-- for one drew a blank cell; this is the guard that the page and the font
-- agree, checked against vram rather than against the source art.
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
local function blitzRow(i) return 1 + i * 2 end   -- ODD rows 1/3/5/../15 (#43)

local function assertRun(x0, y, bytes, what)
  for i, b in ipairs(bytes) do
    H.assertEq(cell(x0 + i - 1, y), b,
      string.format("%s: cell {%d,%d}", what, x0 + i - 1, y))
  end
end

-- The class-closer: a row the page never draws on must be untouched ($00 from
-- ClearBG1ScreenA).  #39's runaway draws carpeted BG1A with ROM code bytes, so
-- every one of these would fail on a garbled page.
local function assertRowBlank(y, what)
  for x = 0, 31 do
    H.assertEq(cell(x, y), 0, string.format("%s: cell {%d,%d} blank", what, x, y))
  end
end

-- THE GEOMETRY CANARY (#43).  An EVEN tilemap row is four scanlines in this
-- window and rows past 15 are outside it entirely, so NOTHING may land on
-- either.  Column 30 is the window's own right border.  Columns 0-2 are the
-- cursor's gutter on EVERY row here, because every row is cursored.
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

-- THE CURSOR GUTTER CANARY (#43 round 3).  Both sides are read, not written:
-- the cursor table comes out of the ROM the menu itself indexes, the text out of
-- the tilemap the menu itself drew.  `cursor_pos {x,y}` assembles to
-- `.byte x, y` (menu_ram.inc:582-584), two bytes per entry, in the framework's
-- index order ($4b = cols*row + col, and cols is 1 here so $4b IS the row).
-- y is 116 + n*12 and tilemap row = 2n+1, so the row an entry points at is
-- (y-116)/6 + 1.
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
  -- ... and the row it points at begins in the very next column.  A LOCKED row
  -- draws its marker over the same ten cells, so this holds at any learned count.
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
  -- and the cell it named is one the FIELD font has art in (#53).  An element
  -- icon is only a cue if the tile arrived: before #53 the page could name
  -- $eb and the menu font's $eb was sixteen zero bytes.
  if want ~= PAD then
    H.assertEq(fontCellHasArt(want), true, string.format(
      "blitz %d (%s) names font cell $%02x, so the MENU font must carry art "
      .. "there -- %s", i, nameText(id), want,
      ELEM_CELLS[want] and "an ELEMENT tile, uploaded by Ot6MenuIcons4bpp_ext"
        or "a class glyph, which ships in the vanilla art"))
  end
  -- the price, right-aligned two digits + " MP", against Ot6AbilityCostTbl
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

-- A rung the character has not reached.  It is NOT blank (vanilla drew ten pads,
-- which the owner's playtest of the Rage page read as a rendering fault) and it
-- is NOT "- EMPTY -" (that word belongs to a Rage slot holding nothing; this
-- rung exists and is merely unreached).  Ten cells, exactly a name field wide,
-- so a learn wipes it completely; the class and price fields blank with it, or
-- the page would price something the player cannot pick.
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

-- ---- the retired input system, named so it cannot come back ----
-- Vanilla's combo glyphs, from BlitzInputTileTbl by way of GetBlitzInputTiles.
-- Measured on the pre-change ROM (probe_blitzpage.lua): these are the codes that
-- carpeted columns 4-13 and 18-27 of rows 1/5/9/13.  If any of them reappears
-- anywhere on this page, the page is teaching the retired system again.
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

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  -- install state: the Blitz command on the lead + three learned rungs.
  H.call(function()
    H.writeByte(CMD3, BATTLE_CMD_BLITZ)
    teach(0x07)                         -- Pummel / AuraBolt / Suplex
    H.log("installed: Blitz on the lead, 3 of 8 rungs learned")
    -- the shape of the price data this page has to render, asserted as a shape
    -- rather than as numbers so a balance retune cannot turn the page red:
    -- there is at least one one-digit price and at least one two-digit price,
    -- so the right-alignment path below is genuinely exercised.
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
    -- #53's shape check, so the icon assertions above cannot all be vacuous.
    -- The ladder must contain at least one ELEMENT row, one CLASS row and one
    -- BLANK row, or the column is only ever exercised on one of its three
    -- answers.  Counted from the ROM, so a data retune moves the numbers and
    -- not the property.
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
      .. "element, break class, and honestly nothing -- or the assertions "
      .. "below only ever test one of them")
  end),

  -- the player's path: X -> main menu -> Skills -> lead character -> submenu
  H.pressButtons({ "x" }, 4),
  H.waitUntil(function() return st() == ST_MAIN end, 600, "main menu", 5),
  H.waitFrames(20),
  H.pressButtons({ "down" }, 2),            -- Items -> Skills
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.readByte(BLITZ_ROW_COLOR), 0x20,
      "Blitz row enabled (install-state command took)")
  end),

  -- cursor to the Blitz row, A opens the page through SkillsOption_03
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == SKILLS_ROW_BLITZ
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "skills cursor to Blitz"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_BLITZ end, 300,
    "blitz page open via the player path", 5),
  H.waitFrames(90),                         -- draws + DMA settle

  H.call(function()
    for i = 0, 2 do assertLearnedRow(i) end
    for i = 3, 7 do assertLockedRow(i) end
    assertNoCombos("3 learned")
    assertGeometry("3 learned")
    for n = 0, 7 do assertCursorGutter(n, "3 learned") end
    H.screenshot("blitz_page_player_path")
    H.log("RENDER OK: Skills->Blitz via the player's path -- three learned rungs "
      .. "carry name + break class + price, five unreached rungs say '- LOCKED -', "
      .. "no combo glyph anywhere, every drawn cell on an ODD row inside row 15, "
      .. "clear of the border column and of every cursor's gutter")
  end),

  -- ---- the cursor MOVES, and picks the row's description ----
  -- One column means $4b IS the blitz index (CalcShortListIndex: $4b = cols*row
  -- + col, cols = 1), which is what LoadBigText indexes $7e9d89 with to choose a
  -- description.  Walk down two and check the index tracks, so the description
  -- box below the list keeps pointing at the row the sprite is on.
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

  -- ---- ALL EIGHT: no locked row anywhere, and a two-digit price on screen ----
  -- Every state above has locked rows in it, so on its own it cannot tell
  -- "- LOCKED -" drawn for an unreached rung from "- LOCKED -" leaking over a
  -- learned one.  It is also the only state that renders Bum Rush, the 30 MP top
  -- of the ladder and the only row that fills the tens cell.
  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_SKILLS end, 300,
    "back out of the blitz page", 5),
  H.call(function() teach(0xff) end),
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
    H.log("FULL PAGE: all eight rungs learned -- eight names, their classes and "
      .. "their prices, the '- LOCKED -' marker nowhere on the page")
  end),

  -- ---- NONE: the page a fresh Sabin opens ----
  -- Sabin joins knowing Pummel, but a level-1 read of this page is the honest
  -- worst case for the marker, and it is the one state where NOTHING on the page
  -- is data.  Nothing may be priced and nothing may carry a class.
  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_SKILLS end, 300,
    "back out of the blitz page", 5),
  H.call(function() teach(0x00) end),
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
