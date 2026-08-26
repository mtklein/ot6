-- @suite savestate=cyan_defence
-- menu_swdtechpage.lua -- the field Skills->SwdTech page renders.
--
-- The page is driven through the real UI (X -> Skills -> character ->
-- SwdTech row -> A), and rendering is asserted cell by cell in the BG1A
-- tilemap shadow: the title, the 1x..3x labels, each slot's tech name, the
-- " MP" cost suffix, the LEARNED pool, and every row between them is
-- asserted all-zero.
--
-- Every Bushido tech costs at least 1 BP, so the 0x row is retired and the
-- window is three rows, 1x/2x/3x.  The stored format is a packed word at
-- $1e1d, four 3-bit fields, with word slot 0 never read.
--
-- The EN field-menu window does not show BG1 ScreenA one tile row per eight
-- scanlines: a row pair occupies twelve scanlines, the odd row getting
-- eight and the even row four, and nothing past row 15 is inside the window
-- at all.  The page draws on odd rows only, all of it inside row 15, with
-- the pool as two columns of four.
--
-- The cursor is a 16x16 sprite and `cursor_pos {x,y}` is its top-left
-- corner.  Vanilla's arithmetic is cursor_x = 8*col - 16, with no exception
-- anywhere in this window.  The cursor gutter canary reads the page's own
-- Ot6LoadoutCursorPos table out of the ROM and, for each entry, asserts the
-- two columns the sprite covers are blank and the row's content starts in
-- the next one.
--
-- The title is "SWDTECH" (columns 3-9), the control hint sits at 11-19, and
-- LEARNED is at 22-28.
--
-- The price field is read out of Ot6AbilityCostTbl, the same table
-- Ot6CostFor charges the player from, and all five cells of the field are
-- asserted: tens (blank, not '0', under ten), ones, then " MP".  A two-digit
-- price is five cells rather than four.  The tech name starts at column 5;
-- column 17 keeps "Quadra Slice" (the one twelve-cell BushidoName) off
-- "30 MP", and column 23 keeps "30 MP" off "MANUAL".
--
-- Fixture: cyan_defence, a real Cyan, alone at Doma, whose own record
-- carries BUSHIDO.  The command is asserted off his record, the learned set
-- and the loadout word are read, and the slot and pool expectations are
-- derived from $1cf7 as read (Ot6LoadoutAutoTech's window: ceiling c =
-- highest learned, base b = max(0, c-2), row s shows min(c, b+s-1)).  On
-- this fixture $1cf7 = $03 (Dispatch and Retort), so c = 1 and the window is
-- {0, 1, 1}: the 3x tier is clamped to the ceiling and shows Retort twice.
-- Cyan does not sit in menu slot 1 here, so he is found in zCharID and the
-- character cursor is walked to him.
--
-- One labeled isolation arm: the all-eight phase (the full pool, and Quadra
-- Slice's 12-cell name beside its two-digit price) needs a Cyan who has
-- learned tech 8, which is level 68, so the last phase below writes
-- $1cf7 = $ff, one byte once.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/cyan_defence.mss.lua"

local ZMENUSTATE, ZCURSOR = 0x26, 0x4b
local ZCHARID = 0x69                    -- zCharID::Slot1..4 (menu_ram.inc)
local BUSHIDO_ROW_COLOR = 0x7b          -- zSkillsTextColor::Bushido
local LEARNED, LOADOUT = 0x1cf7, 0x1e1d
local CHAR_CYAN = 0x02                  -- CHAR::CYAN (const.inc)
local BATTLE_CMD_BUSHIDO = 0x07
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LOADOUT = 0x05, 0x06, 0x0a, 0x7b

local function st() return H.readByte(ZMENUSTATE) end

-- BG1 screen A tilemap shadow (wBG1Tiles::ScreenA = $7e3849, menu_ram.inc):
-- 2 bytes per cell (char, color), 64 bytes per row; cell(x,y) = char byte.
local BG1A = 0x3849
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end

-- menu text codec: 'A'=$80.. 'a'=$9a.. '0'=$b4.. ' '=$ff.
local T = { B=0x81, U=0x94, S=0x92, H=0x87, I=0x88, D=0x83, O=0x8e, L=0x8b,
            A=0x80, T=0x93, E=0x84, R=0x91, N=0x8d, M=0x8c, P=0x8f, W=0x96,
            C=0x82, Y=0x98, SLASH=0xc0, EQ=0xd2, SP=0xff }
local TITLE = { T.S,T.W,T.D,T.T,T.E,T.C,T.H }
local HINT  = { T.L,T.SLASH,T.R,T.SP,T.S,T.W,T.A,T.P,T.S }
local POOL  = { T.L,T.E,T.A,T.R,T.N,T.E,T.D }
-- An all-zero $1e1d is AUTO: the game picks each tier from the moving
-- window and keeps re-picking as Cyan learns, and the first L/R edit
-- freezes that window into the word until Y clears it.
local MODE_AUTO   = { T.A,T.U,T.T,T.O,T.SP,T.SP }
local MODE_MANUAL = { T.M,T.A,T.N,T.U,T.A,T.L }
local MODE_HINT   = { T.Y,T.EQ,T.A,T.U,T.T,T.O }
local lo = { a=0x9a,c=0x9c,e=0x9e,h=0xa1,i=0xa2,l=0xa5,o=0xa8,p=0xa9,r=0xab,
             s=0xac,t=0xad,x=0xb1 }
local DISPATCH = { T.D,lo.i,lo.s,lo.p,lo.a,lo.t,lo.c,lo.h }
local RETORT   = { T.R,lo.e,lo.t,lo.o,lo.r,lo.t }
local SLASH    = { T.S,lo.l,lo.a,lo.s,lo.h }
local ZERO_CHAR = 0xb4                  -- '0'; '9' is 0xbd
local PAD = 0xff                        -- fixed_length_en.json: 0xFF = {pad}
local MP_SUFFIX = { T.SP, T.M, T.P }    -- OT6_LOADOUT_MP_SUFFIX, " MP"

-- Ot6AbilityCostTbl is (key, cost) pairs, $ff-terminated; SwdTech's keys are
-- attack ids $55..$5c, that is $55 + tech index.
local COSTTBL = H.sym("Ot6AbilityCostTbl") & 0x3FFFFF
local SWDTECH_ATK0 = 0x55
local function costOfTech(techIndex)
  local id, x = SWDTECH_ATK0 + techIndex, 0
  while true do
    local key = H.readRomByte(COSTTBL + x)
    if key == 0xff then return 0 end
    if key == id then return H.readRomByte(COSTTBL + x + 1) end
    x = x + 2
  end
end

-- BushidoName is an 8-entry, 12-byte fixed record table; LoadArrayItem
-- copies all twelve bytes including the $ff pad tail, so a name's full
-- 12-cell field is asserted, pads and all.
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

-- Boost row i (0..2) = tilemap row 3 + i*2; pool cell n (0..7) is
-- column-major, with the left column (col 3) on rows 9/11/13/15 and the
-- right column (col 17) on rows 9/11/13/15.
local TITLE_ROW = 1
local LEFT_COL = 3                      -- the page's left margin (gutter = 1-2)
local HINT_COL = 11                     -- #44: title 3-9, hint 11-19, pool 22-28
local POOL_CAPTION_COL = 22             -- the caption rides the title row
-- "1x" 3-4, name 5..16, blank 17, "nn MP" 18..22, blank 23, mode 24..29.
local NAME_COL, COST_COL = 5, 18
local NAME_COST_SEP_COL = 17            -- the gap "Quadra Slice" would eat
local BOOST_ROWS = { 3, 5, 7 }
-- The mode block, in the page's one free run, columns 23-29 of the three
-- slot rows: mode on row 3, the control that changes it on row 5, row 7
-- left clear.
local MODE_COL, MODE_ROW, MODE_HINT_ROW = 24, 3, 5
local MODE_SEP_COL = 23                 -- the gap that keeps "7 MP" off "MANUAL"
local MODE_FREE_ROW = 7                 -- the third slot row's block stays blank
local function poolRow(n) return 9 + (n % 4) * 2 end
local function poolCol(n) return (n < 4) and LEFT_COL or 17 end

local function assertRun(x0, y, bytes, what)
  for i, b in ipairs(bytes) do
    H.assertEq(cell(x0 + i - 1, y), b,
      string.format("%s: cell {%d,%d}", what, x0 + i - 1, y))
  end
end

-- A row the configurator never draws on must be untouched ($00 from
-- ClearBG1ScreenA).
local function assertRowBlank(y, what)
  for x = 0, 31 do
    H.assertEq(cell(x, y), 0, string.format("%s: cell {%d,%d} blank", what, x, y))
  end
end

-- `cursor_pos {x, y}` assembles to `.byte x, y`, two bytes per entry, and is
-- the top-left of a 16x16 sprite, so entry x owns tilemap columns x/8 and
-- x/8+1, and vanilla starts the row it points at in x/8+2
-- (cursor_x = 8*col - 16).  y is 116 + n*12 and tilemap row = 2n+1, so the
-- row a given entry points at is (y-116)/6 + 1.
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
  H.assertEq(cell(col, y), 0, string.format(
    "%s: cursor entry %d sits at x=%d, so tilemap {%d,%d} is under the sprite "
    .. "and must be blank", what, n, cx, col, y))
  H.assertEq(cell(col + 1, y), 0, string.format(
    "%s: cursor entry %d sits at x=%d, so tilemap {%d,%d} is under the sprite "
    .. "and must be blank", what, n, cx, col + 1, y))
  H.assertEq(cell(col + 2, y) ~= 0, true, string.format(
    "%s: cursor entry %d at x=%d reserves columns %d-%d, so the row must start "
    .. "at column %d (vanilla: cursor_x = 8*col - 16)",
    what, n, cx, col, col + 1, col + 2))
  if leading then
    for x = 0, col + 1 do
      H.assertEq(cell(x, y), 0, string.format(
        "%s: {%d,%d} is left of the cursored row's first glyph (column %d)",
        what, x, y, col + 2))
    end
  end
end

-- The price field, all five cells of it, against Ot6AbilityCostTbl.
-- Right-aligned with a leading blank and never a leading zero.
local function assertCostField(y, techIndex, what)
  local cost = costOfTech(techIndex)
  H.assertEq(cost > 0, true, string.format(
    "%s: tech %d is priced in Ot6AbilityCostTbl -- a 0 here would mean the "
    .. "page has no price to draw", what, techIndex))
  local tens = cost // 10
  H.assertEq(cell(COST_COL, y), tens > 0 and (ZERO_CHAR + tens) or PAD,
    string.format("%s: cost %d tens cell {%d,%d} (blank, not '0', under ten)",
      what, cost, COST_COL, y))
  H.assertEq(cell(COST_COL + 1, y), ZERO_CHAR + (cost % 10),
    string.format("%s: cost %d ones cell {%d,%d}", what, cost, COST_COL + 1, y))
  assertRun(COST_COL + 2, y, MP_SUFFIX, what .. " ' MP'")
  H.assertEq(cell(NAME_COST_SEP_COL, y), 0, string.format(
    "%s: {%d,%d} separates the tech name from its price", what,
    NAME_COST_SEP_COL, y))
end

-- One slot row: the tech's 12-cell name at col 5, then its price at col 18.
local function assertSlotRow(y, name, techIndex, techname)
  assertRun(NAME_COL, y, name, techname)
  assertCostField(y, techIndex, techname)
end

local function assertModeBlock(auto, what)
  assertRun(MODE_COL, MODE_ROW, auto and MODE_AUTO or MODE_MANUAL,
    string.format("%s: the page states %s", what, auto and "AUTO" or "MANUAL"))
  assertRun(MODE_COL, MODE_HINT_ROW, MODE_HINT,
    what .. ": the revert control is named under the mode")
  H.assertEq(#MODE_AUTO, #MODE_MANUAL,
    "the two mode words must be the same width, or a MANUAL -> AUTO revert "
    .. "leaves the tail of MANUAL on screen")
  for _, y in ipairs({ MODE_ROW, MODE_HINT_ROW }) do
    H.assertEq(cell(MODE_SEP_COL, y), 0, string.format(
      "%s: {%d,%d} separates the row's price field from the mode block -- "
      .. "without it the row reads '7 MPMANUAL'", what, MODE_SEP_COL, y))
    H.assertEq(MODE_COL + #MODE_AUTO, 30, string.format(
      "%s: the mode block runs to the last usable column, 29 -- column 30 is "
      .. "the window's own border", what))
  end
  for x = MODE_SEP_COL, 29 do
    H.assertEq(cell(x, MODE_FREE_ROW), 0, string.format(
      "%s: {%d,%d} -- the 3x row's block is deliberately empty", what, x,
      MODE_FREE_ROW))
  end
end

-- An even tilemap row is shown as four scanlines in this window, and rows
-- past 15 are outside it entirely, so nothing the page draws may land on
-- either.  Column 30 is the window's own right border.
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

local t = {}
local nLearned = 0
local cyanSlot = nil

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  H.call(function()
    local L = H.readByte(LEARNED)
    while (L >> nLearned) & 1 == 1 do nLearned = nLearned + 1 end
    H.log(string.format("$1cf7 = $%02x as saved: %d techs learned", L, nLearned))
    H.assertEq(L, (1 << nLearned) - 1,
      "Cyan's real learned set is contiguous from tech 0 (level-derived)")
    H.assertEq(nLearned >= 2, true,
      "at least two techs learned -- one-tech and empty pages would render, "
      .. "but the duplicate-tier clamp below needs a second tech to show")
    local c = nLearned - 1
    local b = math.max(0, c - 2)
    t = { math.min(c, b), math.min(c, b + 1), math.min(c, b + 2) }
    H.log(string.format("auto window {%d,%d,%d}", t[1], t[2], t[3]))
    H.assertEq(H.readByte(LOADOUT) | (H.readByte(LOADOUT + 1) << 8), 0,
      "the loadout word is $0000 as saved (no real save has configured one)")
  end),

  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),
  H.call(function()
    local ids = {}
    for s = 0, 3 do
      local id = H.readByte(ZCHARID + s)
      ids[#ids + 1] = string.format("slot %d = char $%02x", s, id)
      if id == CHAR_CYAN and cyanSlot == nil then cyanSlot = s end
    end
    H.log("party: " .. table.concat(ids, ", "))
    H.assertEq(cyanSlot ~= nil, true, "cyan_defence's party contains CYAN")
  end),
  H.pressButtons({ "down" }, 2),            -- Items -> Skills
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.waitFrames(10),
  H.driveUntil(function() return H.readByte(ZCURSOR) == cyanSlot end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "cursor onto CYAN"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.readByte(BUSHIDO_ROW_COLOR), 0x20,
      "SwdTech row enabled -- CYAN's own record carries BUSHIDO")
  end),

  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == 2
  end, 600, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "skills cursor to SwdTech"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_LOADOUT end, 300,
    "configurator open via the player path", 5),
  H.waitFrames(90),                         -- draws + DMA settle

  H.call(function()
    assertRun(LEFT_COL, TITLE_ROW, TITLE, "title SWDTECH")
    assertRun(HINT_COL, TITLE_ROW, HINT, "L/R SWAPS control hint")
    assertRun(POOL_CAPTION_COL, TITLE_ROW, POOL, "LEARNED caption")
    assertRun(LEFT_COL, BOOST_ROWS[1], { 0xb5, lo.x }, "label 1x")
    assertRun(LEFT_COL, BOOST_ROWS[2], { 0xb6, lo.x }, "label 2x")
    assertRun(LEFT_COL, BOOST_ROWS[3], { 0xb7, lo.x }, "label 3x")
    for y = 0, 15 do
      H.assertEq(cell(LEFT_COL, y) == 0xb4 and cell(LEFT_COL + 1, y) == lo.x, false,
        string.format("no 0x label at row %d (#38 retired the free tier)", y))
    end
    assertSlotRow(BOOST_ROWS[1], bushBytes(t[1]), t[1],
      "slot 1x " .. bushText(t[1]))
    assertSlotRow(BOOST_ROWS[2], bushBytes(t[2]), t[2],
      "slot 2x " .. bushText(t[2]))
    assertSlotRow(BOOST_ROWS[3], bushBytes(t[3]), t[3],
      "slot 3x " .. bushText(t[3]) .. " (ceiling clamp)")
    local LIT = { DISPATCH, RETORT, SLASH }
    for k = 0, nLearned - 1 do
      assertRun(poolCol(k), poolRow(k), bushBytes(k),
        "pool cell " .. k .. " vs BushidoName record")
      if LIT[k + 1] then
        assertRun(poolCol(k), poolRow(k), LIT[k + 1],
          "pool cell " .. k .. " vs the spelled-out literal")
      end
    end
    for k = nLearned, 3 do
      H.assertEq(cell(poolCol(k), poolRow(k)), 0,
        string.format("no pool cell %d (only %d learned)", k, nLearned))
    end
    if nLearned <= 4 then
      H.assertEq(cell(poolCol(4), poolRow(0)), 0,
        "right pool column empty (" .. nLearned .. " learned)")
    end
    if nLearned < 4 then
      assertRowBlank(9 + 3 * 2, "row 15 (no 4th learned tech)")
    end
    for _, x in ipairs({ 10, 20, 21 }) do
      H.assertEq(cell(x, TITLE_ROW), 0,
        string.format("title row gap blank {%d,1}", x))
    end
    for x = 29, 31 do
      H.assertEq(cell(x, TITLE_ROW), 0,
        string.format("title row tail blank {%d,1}", x))
    end
    assertModeBlock(true, "real set, untouched")
    H.assertEq(H.readByte(LOADOUT), 0, "the loadout word is still AUTO ...")
    H.assertEq(H.readByte(LOADOUT + 1), 0, "... in both its bytes")
    assertGeometry("real set")
    for n = 0, 2 do assertCursorGutter(n, true, "real set") end
    H.screenshot("swdtech_page_player_path")
    H.log("PASSED: Skills->SwdTech via the player's path renders for a REAL "
      .. "CYAN -- title, labels, slots (with the ceiling clamp), costs, pool "
      .. "correct; every drawn cell on an ODD row inside row 15 and clear of "
      .. "the border column")
  end),

  H.pressButtons({ "r" }, 3),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(H.readByte(ZMENUSTATE), ST_LOADOUT, "still on the loadout page")
    local w = H.readByte(LOADOUT) + H.readByte(LOADOUT + 1) * 256
    H.assertEq(w ~= 0, true,
      "R froze the auto window into $1e1d, so the loadout is MANUAL now")
    assertModeBlock(false, "after the first edit")
    assertGeometry("after the first edit")
    H.screenshot("swdtech_page_manual")
    H.log("LIVE MODE: the first L/R edit flipped the page from AUTO to MANUAL "
      .. "and the page said so on the same redraw, without being reopened")
  end),

  H.pressButtons({ "y" }, 3),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(H.readByte(LOADOUT), 0, "Y cleared the loadout word ...")
    H.assertEq(H.readByte(LOADOUT + 1), 0, "... in both its bytes: AUTO again")
    assertModeBlock(true, "after Y")
    assertGeometry("after Y")
    for i, y in ipairs(BOOST_ROWS) do
      assertRun(NAME_COL, y, bushBytes(t[i]), "boost row " .. i .. " back on auto")
    end
    H.screenshot("swdtech_page_reverted")
    H.log("REVERT: Y put the page back on AUTO, the indicator followed, and "
      .. "'MANUAL' left nothing of itself behind in the six-cell field")
  end),

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

  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_SKILLS end, 300,
    "back out of the configurator", 5),
  H.call(function()
    H.writeByte(LEARNED, 0xff)            -- THE arm's one write (see header)
    H.assertEq(H.readByte(LOADOUT) | (H.readByte(LOADOUT + 1) << 8), 0,
      "the word is still $0000 from Y's revert -- nothing to zero")
    H.log("[isolation arm] $1cf7 := $ff -- the L68 all-eight Cyan, not generatable "
      .. "under the no-grind-tier ruling")
  end),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_LOADOUT end, 300,
    "configurator reopened with all eight learned", 5),
  H.waitFrames(90),

  H.call(function()
    assertRun(LEFT_COL, TITLE_ROW, TITLE, "title still on row 1")
    assertRun(HINT_COL, TITLE_ROW, HINT, "control hint still on row 1")
    assertRun(POOL_CAPTION_COL, TITLE_ROW, POOL, "LEARNED caption still on row 1")
    for n = 0, 7 do
      assertRun(poolCol(n), poolRow(n), bushBytes(n),
        string.format("pool cell %d '%s' at {%d,%d}",
          n, bushText(n), poolCol(n), poolRow(n)))
    end
    for i, y in ipairs(BOOST_ROWS) do
      assertRun(NAME_COL, y, bushBytes(4 + i), "boost row " .. i .. " tech")
      assertCostField(y, 4 + i, string.format("boost row %d '%s'",
        i, bushText(4 + i)))
    end
    assertModeBlock(true, "8 learned, untouched")
    assertGeometry("8 learned")
    for n = 0, 2 do assertCursorGutter(n, true, "8 learned") end
    H.screenshot("swdtech_page_full_pool")
    H.log("FULL POOL (isolation arm): all eight Bushido techs drawn in two "
      .. "columns of four on rows 9/11/13/15 -- every cell inside the window, "
      .. "none on an even row, none past row 15, none in column 30, none "
      .. "under the cursor")
  end),
})
