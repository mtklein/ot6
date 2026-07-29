-- @suite frontier=arvis_wake
-- menu_swdtechpage.lua -- issue #39: the field Skills->SwdTech page RENDERS.
--
-- The v0.5 loadout configurator (#8 Layer B) shipped with its pos_text labels
-- written as bare string literals in field_menu.asm.  menu_main.asm includes
-- ending_anim.asm BEFORE field_menu.asm, and ending_anim.asm installs the
-- ending-credits .charmap and never removes it -- so those literals assembled
-- to credits-font tiles, and (unlike menu_text_en.inc's encode pipeline) got
-- no $00 terminator, so every DrawPosText call streamed the ROM bytes that
-- follow the label into the BG1A tilemap until it happened upon a zero: the
-- whole page body became overlapping glyph soup.  menu_bushidoloadout stayed
-- green through all of it because it (a) force-jumps zMenuState to $7b from
-- the top menu instead of walking the player's path and (b) asserts only the
-- $1e1d word and menu state -- not one rendered cell.  This test closes BOTH
-- gaps:
--
--   * PATH: it drives the real UI -- X -> Skills -> character -> SwdTech row
--     -> A -- so SkillsOption_02 (field_menu.asm), not a forced state, opens
--     the configurator;
--   * RENDER: it asserts the BG1A tilemap shadow cell-by-cell: the title,
--     the 1x..3x labels, each slot's tech name, the " MP" cost suffix, the
--     LEARNED pool -- and, the class-closer, that the rows BETWEEN them are
--     still all-zero (a runaway unterminated draw can not leave them blank).
--
-- issue #38 refloored the page: every Bushido tech costs at least 1 BP, so the
-- 0x row is RETIRED and the window is three rows -- 1x/2x/3x.  The stored
-- format did NOT move (the same packed word at $1e1d, four 3-bit fields; word
-- slot 0 is simply never read), so this test's install and its AUTO word are
-- unchanged.
--
-- issue #43 -- THE GEOMETRY, and why this test shipped a broken page green.
-- Everything above asserts WHAT is drawn; nothing asserted WHERE, and the
-- where was wrong from v0.5.  The EN field-menu window does not show BG1
-- ScreenA one tile row per eight scanlines: a row PAIR occupies twelve
-- scanlines, the ODD row getting eight and the even row four, and nothing past
-- row 15 is inside the window at all (measured with a per-row glyph ruler,
-- tools/tests/probe_ragegeom.lua; vanilla says it from the other side -- every
-- EN cursor list for this window is `cursor_pos {x, 116 + n*12}`,
-- skills.asm:125-126, and DrawRageName biases its row `.if LANG_EN`,
-- skills.asm:1571-1574).  The page drew its slots on EVEN rows 4/6/8 and its
-- LEARNED grid on 15/17/19/21, so every tech name rendered as a four-scanline
-- sliver and THREE of the pool's four rows were off the bottom of the window.
-- It now draws on odd rows only, all of it inside row 15, with the pool as two
-- columns of four (field_menu.asm Ot6LoadoutDrawSlots' cadence note).
--
-- Hence the EVEN-ROW / ROW>15 / BORDER-COLUMN CANARY at the bottom of this
-- file -- the same assertion class menu_ragepage.lua carries.  It is not
-- decoration; it is the regression, and it is the thing this test was missing.
--
-- issue #43, ROUND THREE -- THE CURSOR GUTTER, the other half of "where".
-- The rows landed on the right SCANLINES and still looked wrong, because the
-- cursor is a 16x16 SPRITE and `cursor_pos {x,y}` is its top-left corner: at
-- x = 8 it covers tilemap columns 1 AND 2, and this page drew its "1x" label
-- at column 2 -- so the sprite sat on the leading glyph.  Vanilla's own
-- arithmetic is cursor_x = 8*col - 16, with no exception anywhere in this
-- window: magic draws at cols 3/16 under cursors 8/112 (skills.asm:831, :836
-- vs :125-126), espers at 3/17 under 8/120 (:1733, :1737 vs :249-250), rage at
-- 5/19 under 24/136 (:1544, :1548 vs :292-293), and the config menu's value
-- column 14 under 96 (config.asm:50).  Measured the same on the shipped ROM:
-- the magic list's `cursor_pos {8, 116}` lights screen x 8..23, y 116..131
-- (tools/tests/probe_menucols.lua).  The fix moved the page's left margin from
-- column 2 to column 3 and everything right of it by one; the cursor table did
-- not move, because it was already vanilla's.
--
-- THE CURSOR GUTTER CANARY below is what keeps that true.  It reads the page's
-- OWN Ot6LoadoutCursorPos table out of the ROM and, for each entry, asserts the
-- two columns the sprite covers are blank and the row's content starts in the
-- very next one.  Neither side is hardcoded -- the cursor comes from the ROM,
-- the text is read out of the tilemap -- so moving either half alone fails
-- here.  It is duplicated in menu_ragepage.lua rather than shared: the only
-- lua the runner inlines is lib/ot6{,_field,_contract}.lua, and those three
-- files ARE the frontier mint signature (lib/frontier_stamp.sh:49-55), so a
-- helper added there would mark every minted fixture drifted.
--
-- Fixture: arvis_wake (same boot as menu_bushidoloadout / menu_esperdetail).
-- Its lead has no Bushido command, so the SwdTech row is installed the house
-- "install state" way (menu_esperdetail pins esper bits the same way): the
-- lead's third battle-command byte becomes BUSHIDO, and $1cf7 = $07 -- the
-- natural learned set of the owner's scenario-band Cyan (Dispatch, Retort,
-- Slash; the LV14-era set from the #39 report), loadout word $0000 = AUTO.
-- With exactly 3 of 8 techs learned the ceiling is 2, so the three-rung auto
-- window (base = max(0, ceiling-2) = 0) draws Dispatch/Retort/Slash at
-- 1x/2x/3x -- every learned tech reachable, none duplicated -- and the pool
-- holds the same three names.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/arvis_wake.mss.lua"

local ZMENUSTATE, ZCURSOR = 0x26, 0x4b
local BUSHIDO_ROW_COLOR = 0x7b          -- zSkillsTextColor::Bushido
local CMD3 = 0x1618                     -- lead char's 3rd battle command
local LEARNED, LOADOUT = 0x1cf7, 0x1e1d
local BATTLE_CMD_BUSHIDO = 0x07
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LOADOUT = 0x05, 0x06, 0x0a, 0x7b

local function st() return H.readByte(ZMENUSTATE) end

-- BG1 screen A tilemap shadow (wBG1Tiles::ScreenA = $7e3849, menu_ram.inc):
-- 2 bytes per cell (char, color), 64 bytes per row; cell(x,y) = char byte.
local BG1A = 0x3849
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end

-- menu text codec (ff6/tools/char_table/text_en.json): 'A'=$80.. 'a'=$9a..
-- '0'=$b4.. ' '=$ff.
local T = { B=0x81, U=0x94, S=0x92, H=0x87, I=0x88, D=0x83, O=0x8e, L=0x8b,
            A=0x80, T=0x93, E=0x84, R=0x91, N=0x8d, M=0x8c, P=0x8f, SP=0xff }
local TITLE = { T.B,T.U,T.S,T.H,T.I,T.D,T.O,T.SP,T.L,T.O,T.A,T.D,T.O,T.U,T.T }
local POOL  = { T.L,T.E,T.A,T.R,T.N,T.E,T.D }
local lo = { a=0x9a,c=0x9c,e=0x9e,h=0xa1,i=0xa2,l=0xa5,o=0xa8,p=0xa9,r=0xab,
             s=0xac,t=0xad,x=0xb1 }
local DISPATCH = { T.D,lo.i,lo.s,lo.p,lo.a,lo.t,lo.c,lo.h }
local RETORT   = { T.R,lo.e,lo.t,lo.o,lo.r,lo.t }
local SLASH    = { T.S,lo.l,lo.a,lo.s,lo.h }
local DIGIT0, DIGIT9 = 0xb4, 0xbd
local PAD = 0xff                        -- fixed_length_en.json: 0xFF = {pad}

-- BushidoName, verbatim, out of the ROM Ot6DrawBushName itself reads (via
-- _c35328 -> LoadArrayItem, skills.asm:1408-1416).  An 8-entry, 12-byte fixed
-- record table (include/text/bushido_name_en.inc); LoadArrayItem copies all
-- twelve bytes including the $ff pad tail, so a name's FULL 12-cell field is
-- asserted, pads and all.  Reading the ROM rather than hardcoding means a text
-- re-encode cannot silently invalidate the all-eight pool arm below -- the
-- literals above stay as the positive control on the encode pipeline itself.
local BUSHNAME = H.sym("BushidoName") & 0x3FFFFF
local BUSH_SIZE = 12                    -- BushidoName::ITEM_SIZE
local function bushBytes(id)
  local t = {}
  for i = 0, BUSH_SIZE - 1 do t[i + 1] = H.readRomByte(BUSHNAME + id * BUSH_SIZE + i) end
  return t
end
local function bushText(id)             -- for the log only
  local s = ""
  for _, b in ipairs(bushBytes(id)) do
    if b == PAD then s = s .. "."
    elseif b >= 0x80 and b <= 0x99 then s = s .. string.char(65 + b - 0x80)
    elseif b >= 0x9a and b <= 0xb3 then s = s .. string.char(97 + b - 0x9a)
    else s = s .. "?" end
  end
  return s
end

-- #43 geometry, mirroring field_menu.asm's Ot6LoadoutDraw{Slots,Pool}: ODD
-- tilemap rows only, nothing past row 15, nothing in the window's own border
-- column 30, and nothing in the cursor's gutter (columns 1-2).  Boost row i
-- (0..2) = tilemap row 3 + i*2; pool cell n (0..7) is column-major -- left
-- column (col 3) rows 9/11/13/15, right column (col 17) rows 9/11/13/15.  A
-- 12-cell name at col 17 ends at 28, inside the border.
local TITLE_ROW = 1
local LEFT_COL = 3                      -- the page's left margin (gutter = 1-2)
local POOL_CAPTION_COL = 22             -- the caption rides the title row
local NAME_COL, COST_COL = 6, 19        -- "1x" 3-4, blank 5, name 6..17, cost 19
local BOOST_ROWS = { 3, 5, 7 }
local function poolRow(n) return 9 + (n % 4) * 2 end
local function poolCol(n) return (n < 4) and LEFT_COL or 17 end

local function assertRun(x0, y, bytes, what)
  for i, b in ipairs(bytes) do
    H.assertEq(cell(x0 + i - 1, y), b,
      string.format("%s: cell {%d,%d}", what, x0 + i - 1, y))
  end
end

-- The class-closer: a row the configurator never draws on must be untouched
-- ($00 from ClearBG1ScreenA).  Before the fix the runaway draws carpeted rows
-- 1..19 of BG1A with ROM code bytes, so every one of these failed.
local function assertRowBlank(y, what)
  for x = 0, 31 do
    H.assertEq(cell(x, y), 0, string.format("%s: cell {%d,%d} blank", what, x, y))
  end
end

-- THE CURSOR GUTTER CANARY (#43 round 3).  Both sides are read, not written:
-- the cursor table comes out of the ROM the menu itself indexes, and the text
-- comes out of the tilemap the menu itself drew.
--
-- `cursor_pos {x, y}` assembles to `.byte x, y` (menu_ram.inc:582-584), two
-- bytes per entry, and is the TOP-LEFT of a 16x16 sprite -- so entry x owns
-- tilemap columns x/8 and x/8+1, and vanilla starts the row it points at in
-- x/8+2 (cursor_x = 8*col - 16; see the header).  y is 116 + n*12 and tilemap
-- row = 2n+1, so the row a given entry points at is (y-116)/6 + 1.
local CURSOR_POS = H.sym("Ot6LoadoutCursorPos") & 0x3FFFFF
local function cursorEntry(n)
  return H.readRomByte(CURSOR_POS + n * 2), H.readRomByte(CURSOR_POS + n * 2 + 1)
end

local function assertCursorGutter(n, leading, what)
  local cx, cy = cursorEntry(n)
  local col, y = cx // 8, (cy - 116) // 6 + 1
  H.assertEq(y % 2 == 1 and y >= 1 and y <= 15, true, string.format(
    "%s: cursor entry %d (y=%d) points at tilemap row %d, which this window "
    .. "does not show whole", what, n, cy, y))
  -- the two columns UNDER the sprite must carry no glyph at all
  H.assertEq(cell(col, y), 0, string.format(
    "%s: cursor entry %d sits at x=%d, so tilemap {%d,%d} is under the sprite "
    .. "and must be blank", what, n, cx, col, y))
  H.assertEq(cell(col + 1, y), 0, string.format(
    "%s: cursor entry %d sits at x=%d, so tilemap {%d,%d} is under the sprite "
    .. "and must be blank", what, n, cx, col + 1, y))
  -- ... and the row's content must begin in the very next column, so the
  -- cursor abuts its row exactly the way every vanilla list in this window does
  H.assertEq(cell(col + 2, y) ~= 0, true, string.format(
    "%s: cursor entry %d at x=%d reserves columns %d-%d, so the row must start "
    .. "at column %d (vanilla: cursor_x = 8*col - 16)",
    what, n, cx, col, col + 1, col + 2))
  -- for a leading (left-most) cursor, nothing at all may precede it on the row
  if leading then
    for x = 0, col + 1 do
      H.assertEq(cell(x, y), 0, string.format(
        "%s: {%d,%d} is left of the cursored row's first glyph (column %d)",
        what, x, y, col + 2))
    end
  end
end

-- One slot row: name at col 6, then a 1-digit MP cost at col 19 + " MP".
local function assertSlotRow(y, name, techname)
  assertRun(NAME_COL, y, name, techname)
  local d = cell(COST_COL, y)
  H.assertEq(d >= DIGIT0 and d <= DIGIT9, true,
    string.format("%s: cost digit at {%d,%d} (got %02x)", techname, COST_COL, y, d))
  assertRun(COST_COL + 1, y, { T.SP, T.M, T.P }, techname .. " ' MP'")
end

-- THE GEOMETRY CANARY (#43) -- the assertion class this test was missing, and
-- the reason a page whose every slot was a four-scanline sliver shipped green.
-- An EVEN tilemap row is shown as four scanlines in this window, and rows past
-- 15 are outside it entirely, so NOTHING the page draws may land on either.
-- Column 30 is the window's own right border, so nothing may run into it.
-- Both row rules were violated before the fix (slots on 4/6/8, pool on
-- 15/17/19/21), and no cell-content assertion can see that -- only this can.
local function assertGeometry(what)
  for y = 0, 27 do
    if y % 2 == 0 or y > 15 then
      for x = 0, 31 do
        H.assertEq(cell(x, y), 0, string.format(
          "%s: {%d,%d} must stay blank -- row %d is %s", what, x, y, y,
          y > 15 and "outside the window" or "even: four scanlines"))
      end
    end
  end
  for y = 1, 15, 2 do
    for _, x in ipairs({ 30, 31 }) do
      H.assertEq(cell(x, y), 0, string.format(
        "%s: {%d,%d} is the border column or past it", what, x, y))
    end
  end
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  -- install state: SwdTech command on the lead + the scenario-band learned
  -- set (Dispatch/Retort/Slash), AUTO loadout word.
  H.call(function()
    H.writeByte(CMD3, BATTLE_CMD_BUSHIDO)
    H.writeByte(LEARNED, 0x07)
    H.writeByte(LOADOUT, 0)
    H.writeByte(LOADOUT + 1, 0)
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
    H.assertEq(H.readByte(BUSHIDO_ROW_COLOR), 0x20,
      "SwdTech row enabled (install-state command took)")
  end),

  -- cursor to the SwdTech row (row 2: Espers, Magic, SwdTech), A opens the
  -- configurator through SkillsOption_02 -- the exact edge no test drove.
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == 2
  end, 600, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "skills cursor to SwdTech"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_LOADOUT end, 300,
    "configurator open via the player path", 5),
  H.waitFrames(90),                         -- draws + DMA settle

  H.call(function()
    -- chrome.  The LEARNED caption rides the TITLE row (#43): the window has
    -- eight text rows and the page needs nine, and the pool's four rows are
    -- not negotiable if all eight techs are to be inside the frame.
    assertRun(LEFT_COL, TITLE_ROW, TITLE, "title BUSHIDO LOADOUT")
    assertRun(POOL_CAPTION_COL, TITLE_ROW, POOL, "LEARNED caption")
    assertRun(LEFT_COL, BOOST_ROWS[1], { 0xb5, lo.x }, "label 1x")
    assertRun(LEFT_COL, BOOST_ROWS[2], { 0xb6, lo.x }, "label 2x")
    assertRun(LEFT_COL, BOOST_ROWS[3], { 0xb7, lo.x }, "label 3x")
    -- #38: no 0x label anywhere on the page -- the retired rung must not be
    -- drawn at its old home nor anywhere else in the label column.
    for y = 0, 15 do
      H.assertEq(cell(LEFT_COL, y) == 0xb4 and cell(LEFT_COL + 1, y) == lo.x, false,
        string.format("no 0x label at row %d (#38 retired the free rung)", y))
    end
    -- the three boost slots: ceiling 2 -> base 0 -> Dispatch/Retort/Slash
    assertSlotRow(BOOST_ROWS[1], DISPATCH, "slot 1x Dispatch")
    assertSlotRow(BOOST_ROWS[2], RETORT,   "slot 2x Retort")
    assertSlotRow(BOOST_ROWS[3], SLASH,    "slot 3x Slash")
    -- the LEARNED pool: exactly the three learned names, left column, on the
    -- window's odd rows.  Cross-check the hardcoded literals against the ROM
    -- records the drawing code actually reads.
    for n, name in ipairs({ DISPATCH, RETORT, SLASH }) do
      assertRun(poolCol(n - 1), poolRow(n - 1), name, "pool cell " .. (n - 1))
      assertRun(poolCol(n - 1), poolRow(n - 1), bushBytes(n - 1),
        "pool cell " .. (n - 1) .. " vs BushidoName record")
    end
    H.assertEq(cell(poolCol(3), poolRow(3)), 0, "no 4th pool cell (only 3 learned)")
    H.assertEq(cell(poolCol(4), poolRow(0)), 0, "right pool column empty (3 learned)")
    -- spray canaries: undrawn odd rows are still cleared
    assertRowBlank(9 + 3 * 2, "row 15 (no 4th learned tech)")
    -- the title row's gaps and tail: the title ends at 17 and the caption runs
    -- 22..28, and nothing may run into the window's own right border in
    -- column 30.
    for x = 18, 21 do
      H.assertEq(cell(x, TITLE_ROW), 0,
        string.format("title row gap blank {%d,1}", x))
    end
    for x = 29, 31 do
      H.assertEq(cell(x, TITLE_ROW), 0,
        string.format("title row tail blank {%d,1}", x))
    end
    assertGeometry("3 learned")
    -- the cursor gutter, on every one of the three boost rows: nothing under
    -- the sprite, content starting in the column right after it.
    for n = 0, 2 do assertCursorGutter(n, true, "3 learned") end
    H.screenshot("swdtech_page_player_path")
    H.log("PASSED: Skills->SwdTech via the player's path renders -- title, "
      .. "labels, slots, costs, pool correct; every drawn cell on an ODD row "
      .. "inside row 15 and clear of the border column")
  end),

  -- ---- #43: the WHOLE learned pool is inside the window ----
  -- Three learned techs only ever exercised the left column's top three cells,
  -- which is why a grid whose rows ran to 21 looked fine.  Back out to the
  -- skills submenu, teach all eight, and re-enter: the pool now fills both
  -- columns of all four rows, and every one of those cells must still be on an
  -- odd row <= 15.  This is the acceptance criterion the old layout could not
  -- meet at any learned count above three.
  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_SKILLS end, 300,
    "back out of the configurator", 5),
  H.call(function()
    H.writeByte(LEARNED, 0xff)            -- all eight Bushido techs
    H.writeByte(LOADOUT, 0)
    H.writeByte(LOADOUT + 1, 0)           -- AUTO again
  end),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_LOADOUT end, 300,
    "configurator reopened with all eight learned", 5),
  H.waitFrames(90),

  H.call(function()
    assertRun(LEFT_COL, TITLE_ROW, TITLE, "title still on row 1")
    assertRun(POOL_CAPTION_COL, TITLE_ROW, POOL, "LEARNED caption still on row 1")
    -- all eight, column-major: cells 0-3 down col 3, cells 4-7 down col 17.
    for n = 0, 7 do
      assertRun(poolCol(n), poolRow(n), bushBytes(n),
        string.format("pool cell %d '%s' at {%d,%d}",
          n, bushText(n), poolCol(n), poolRow(n)))
    end
    -- the three boost rows are still full-height rows with a priced tech on
    -- them (ceiling 7 -> base 5 -> Stunner / Quadra Slice / Cleave).
    for i, y in ipairs(BOOST_ROWS) do
      assertRun(NAME_COL, y, bushBytes(4 + i), "boost row " .. i .. " tech")
      local d = cell(COST_COL, y)
      H.assertEq(d >= DIGIT0 and d <= DIGIT9, true,
        string.format("boost row %d cost digit at {%d,%d} (got %02x)",
          i, COST_COL, y, d))
    end
    assertGeometry("8 learned")
    -- the full pool is the case that puts a glyph in EVERY cursored row and in
    -- both pool columns, so it is the strongest state to check the gutter in.
    for n = 0, 2 do assertCursorGutter(n, true, "8 learned") end
    H.screenshot("swdtech_page_full_pool")
    H.log("FULL POOL: all eight Bushido techs drawn in two columns of four on "
      .. "rows 9/11/13/15 -- every cell inside the window, none on an even "
      .. "row, none past row 15, none in column 30, none under the cursor")
  end),

  -- ---- the cursor MOVES, and the gutter holds on every row it reaches ----
  -- The canary above reads the whole cursor table, but only the row the sprite
  -- is actually parked on is visible in a screenshot.  Walk it down to the
  -- bottom slot and shoot that too, so the owner's own check -- "open it and
  -- look" -- is covered on more than the first row.
  H.pressButtons({ "down" }, 2),
  H.waitFrames(20),
  H.pressButtons({ "down" }, 2),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(H.readByte(ZMENUSTATE), ST_LOADOUT, "still on the loadout page")
    for n = 0, 2 do assertCursorGutter(n, true, "cursor on the 3x row") end
    assertGeometry("cursor on the 3x row")
    H.screenshot("swdtech_page_cursor_bottom")
    H.log("CURSOR WALK: the sprite is on the 3x row and columns 1-2 are still "
      .. "empty on all three -- the gutter is a property of the page, not of "
      .. "which row happens to be selected")
  end),
})
