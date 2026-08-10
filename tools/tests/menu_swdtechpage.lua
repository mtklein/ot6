-- @suite frontier=cyan_defence
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
-- files ARE the frontier mint signature (lib/frontier_stamp.sh:82-85), so a
-- helper added there would mark every minted fixture drifted.
--
-- issue #44 -- THE CONTROL HINT, and why the title row's expectations moved.
-- The page rendered correctly and the owner still could not use it: L/R
-- cycling the cursored rung is its only real interaction and nothing on screen
-- said so.  All eight of the window's text rows were already spoken for, so
-- the hint had to come out of found space, and the title was the cheapest
-- source -- "BUSHIDO LOADOUT" spent columns 3-17 saying what the 1x/2x/3x
-- rungs and the LEARNED pool already show.  It is "SWDTECH" now (3-9), the
-- hint sits at 11-19, LEARNED is unmoved at 22-28.  The EXPECTED cells below
-- were rewritten to that layout deliberately; nothing was loosened, and the
-- title-row gap assertion gained a job it did not have before (it now pins the
-- separation between three chrome words instead of one empty run).
--
-- issue #56 -- THE PRICE FIELD, and why this file's cost check moved from a
-- shape to a value.  What shipped here asserted only that column 19 held SOME
-- digit and that " MP" followed it.  That shape was true of a page drawing the
-- WRONG NUMBER for seven of eight techniques: Ot6LoadoutDrawCost added the cost
-- straight onto ZERO_CHAR ("kit costs 1..8", its own comment), and #45's
-- rescale to 4/10/13/16/18/22/30/46 pushed six of those sums past '9' into
-- punctuation -- Retort's 10 drew $be, Quadra Slice's 30 drew '='.  The shape
-- check caught it only because $be is not in the digit range; a cost of, say,
-- 20 would have drawn a legal-looking glyph and passed.
--
-- So the check reads the PRICE out of Ot6AbilityCostTbl -- the same table
-- Ot6CostFor charges the player from -- and asserts all five cells of the
-- field: tens (BLANK, not '0', under ten), ones, then " MP".  It is strictly
-- stronger than what it replaces, not looser: it now fails if the page and the
-- cost authority ever disagree, while a balance retune moves both together and
-- reddens nothing.  This is menu_blitzpage.lua's own idiom (#46), which is the
-- point -- the two pages draw their prices with ONE proc now.
--
-- ... and the row's COLUMNS moved with it.  A two-digit price is five cells,
-- not four, and columns 3..29 held exactly 27 with 28 wanted.  The tech name
-- starts at 5 instead of 6 -- the blank that used to sit between "1x" and the
-- name is the donor, and it is the only one of the row's three gaps whose two
-- sides cannot be misread as one token.  The other two are asserted here and
-- stay: column 17 keeps "Quadra Slice" (the one twelve-cell BushidoName) off
-- "30 MP", and column 23 keeps "30 MP" off "MANUAL" -- the failure #49 shipped
-- a screenshot of.  Full derivation over Ot6LoadoutDrawSlots, field_menu.asm.
--
-- Fixture (issue #75 conversion): cyan_defence -- a REAL CYAN, alone at Doma
-- (map 120, gen_sabin_camp), whose own record carries BUSHIDO.  The "install
-- state" stagings this file used on arvis_wake (command byte, learned set,
-- loadout zeroing) are gone: the command is asserted off his record, the
-- learned set and the loadout word are READ, and the slot/pool expectations
-- are DERIVED from $1cf7 as read (Ot6LoadoutAutoTech's window: ceiling c =
-- highest learned, base b = max(0, c-2), row s shows min(c, b+s-1)).
--
-- MEASURED on this fixture: $1cf7 = $03 -- TWO techs, Dispatch and Retort
-- (the burn-down plan's "$07 scenario-band" note describes a later Cyan) --
-- so c = 1 and the window is {0, 1, 1}: the 3x rung is CLAMPED to the
-- ceiling and shows Retort TWICE.  That is a page state the old $07 staging
-- never rendered, and it is the honest one: a real early Cyan's page
-- duplicates his top tech on the deeper rungs.  Also measured: CYAN does not
-- sit in menu slot 1 here (slot 1 reads $FF after the scenario shuffle), so
-- he is FOUND in zCharID and the character cursor is walked to him.
--
-- *** ONE LABELED ISOLATION ARM (issue #75) -- a single state write STAYS ***
-- The ALL-EIGHT phase (the full pool, and Quadra Slice's 12-cell name beside
-- its two-digit price -- the #56 arm this page exists to hold) needs a Cyan
-- who has learned tech 8, which is LEVEL 68.  Per the owner's learn-ceiling
-- ruling (2026-08-10, docs/waiver-burndown-plan.md systemic call 1: no
-- leveled-fixture grind tier; true ceiling arms stay as loudly-labeled
-- memory-hack isolation arms, converted organically as higher-level content
-- arrives), the LAST phase below writes $1cf7 = $ff -- one byte, once -- and
-- this file keeps its .writeByte( waiver line for exactly that site.  It MAY
-- NEVER PRODUCE FIXTURES.
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

-- menu text codec (ff6/tools/char_table/text_en.json): 'A'=$80.. 'a'=$9a..
-- '0'=$b4.. ' '=$ff.
local T = { B=0x81, U=0x94, S=0x92, H=0x87, I=0x88, D=0x83, O=0x8e, L=0x8b,
            A=0x80, T=0x93, E=0x84, R=0x91, N=0x8d, M=0x8c, P=0x8f, W=0x96,
            C=0x82, Y=0x98, SLASH=0xc0, EQ=0xd2, SP=0xff }
-- #44: the title is "SWDTECH", not "BUSHIDO LOADOUT".  Two reasons, and this
-- test asserts the result of both: the fifteen-column title was the only place
-- on the page with room to spend on a control hint, and "SwdTech" is what
-- every other player-facing EN string calls this skill (SKILLS_LIST_BUSHIDO,
-- SKILLS_BUSHIDO_TITLE, ITEM_BUSHIDO in menu_text_en.inc) -- including the row
-- the player picks to reach this page.
local TITLE = { T.S,T.W,T.D,T.T,T.E,T.C,T.H }
-- #44: the control hint the page shipped without.  L/R cycling the cursored
-- rung is this page's only real interaction and nothing named it ("that part
-- was not obvious", owner playtest v0.7).  Character for character the same
-- string the Rage page draws -- the two loadout pages share the idiom and must
-- teach it with the same words.
local HINT  = { T.L,T.SLASH,T.R,T.SP,T.S,T.W,T.A,T.P,T.S }
local POOL  = { T.L,T.E,T.A,T.R,T.N,T.E,T.D }
-- issue #44 gave this page a control hint; issue #49 gives it the STATE that
-- control changes.  An all-zero $1e1d is AUTO -- the game picks each rung from
-- the moving window, and keeps re-picking as Cyan learns -- and the first L/R
-- edit freezes that window into the word, permanently, until Y clears it.  The
-- page said nothing about which of the two it was in, and nothing named Y.
--
-- Same six cells carry both words, "AUTO" space-padded to "MANUAL"'s width, so
-- a revert overwrites the whole field: a five-cell "AUTO " would leave MANUAL's
-- trailing L on screen.  #EXPECTED is asserted below for exactly that reason.
local MODE_AUTO   = { T.A,T.U,T.T,T.O,T.SP,T.SP }
local MODE_MANUAL = { T.M,T.A,T.N,T.U,T.A,T.L }
-- ... and the control, worded identically to the Rage page's (the #44 rule:
-- one idiom, one wording, or a player has to learn it twice).
local MODE_HINT   = { T.Y,T.EQ,T.A,T.U,T.T,T.O }
local lo = { a=0x9a,c=0x9c,e=0x9e,h=0xa1,i=0xa2,l=0xa5,o=0xa8,p=0xa9,r=0xab,
             s=0xac,t=0xad,x=0xb1 }
local DISPATCH = { T.D,lo.i,lo.s,lo.p,lo.a,lo.t,lo.c,lo.h }
local RETORT   = { T.R,lo.e,lo.t,lo.o,lo.r,lo.t }
local SLASH    = { T.S,lo.l,lo.a,lo.s,lo.h }
local ZERO_CHAR = 0xb4                  -- '0'; '9' is 0xbd
local PAD = 0xff                        -- fixed_length_en.json: 0xFF = {pad}
local MP_SUFFIX = { T.SP, T.M, T.P }    -- OT6_LOADOUT_MP_SUFFIX, " MP"

-- #56: the price the page must print, read from the table the game CHARGES
-- from.  Ot6AbilityCostTbl is (key, cost) pairs, $ff-terminated
-- (ot6_boost.asm:744-794); SwdTech's keys are attack ids $55..$5c, i.e.
-- $55 + tech index -- the same `adc #$55` Ot6LoadoutDrawSlots does before it
-- calls Ot6LoadoutCost.  An id absent from the table is free (Ot6CostFor's
-- @free arm), which for a SwdTech row would mean the page had no price to show
-- at all, so the assertion below demands a nonzero one.
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
local HINT_COL = 11                     -- #44: title 3-9, hint 11-19, pool 22-28
local POOL_CAPTION_COL = 22             -- the caption rides the title row
-- #56: "1x" 3-4, name 5..16, blank 17, "nn MP" 18..22, blank 23, mode 24..29.
local NAME_COL, COST_COL = 5, 18
local NAME_COST_SEP_COL = 17            -- the gap "Quadra Slice" would eat
local BOOST_ROWS = { 3, 5, 7 }
-- #49: the mode block, in the page's one free run -- columns 23-29 of the three
-- slot rows (the survey in issue #49).  Mode on row 3, the control that changes
-- it on row 5, row 7 left clear so the two read as a pair and not as a third
-- column of per-rung data.
--
-- The block starts at 24, not 23, and MODE_SEP_COL below is why: the slot's
-- price field is "n MP" at columns 19-22, and the first cut of this change put
-- the block at 23, where the row rendered as "7 MPMANUAL" (screenshot).  Column
-- 23 is the separator and is asserted BLANK, so a later widening of either the
-- price field or the mode word fails here rather than shipping as one word.
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

-- #56: the price field, all five cells of it, against Ot6AbilityCostTbl.
-- Right-aligned with a LEADING BLANK and never a leading zero -- vanilla's own
-- rule for a menu number (HexToDec3 overwrites each leading '0' with $ff,
-- menu_common.asm:906-918, and DrawNum2 prints the low two,
-- menu_common.asm:856-860) -- so the three rungs read as a column.  Asserting
-- PAD rather than "anything" for a one-digit price is the half that catches a
-- drawer which right-pads instead ("4  MP") or zero-fills ("04 MP").
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
  -- the gap the widened field ate into: without it the widest name and the
  -- widest price render as "Quadra Slice30 MP".
  H.assertEq(cell(NAME_COST_SEP_COL, y), 0, string.format(
    "%s: {%d,%d} separates the tech name from its price", what,
    NAME_COST_SEP_COL, y))
end

-- One slot row: the tech's 12-cell name at col 5, then its price at col 18.
local function assertSlotRow(y, name, techIndex, techname)
  assertRun(NAME_COL, y, name, techname)
  assertCostField(y, techIndex, techname)
end

-- #49: the mode block, asserted as a block -- the word, the control under it,
-- and the three cells (29 on both rows, and the whole of row 7's run) that must
-- stay clear so it cannot creep into the window's border.
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

-- Derived from the learned set as READ: the auto window techs for rows
-- 1x/2x/3x, and n = the learned count (filled at runtime).
local t = {}
local nLearned = 0
local cyanSlot = nil

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  -- The save's own state, read -- nothing installed.  Derive the auto window
  -- Ot6LoadoutAutoTech will draw and assert the word has never been touched.
  H.call(function()
    local L = H.readByte(LEARNED)
    while (L >> nLearned) & 1 == 1 do nLearned = nLearned + 1 end
    H.log(string.format("$1cf7 = $%02x as saved: %d techs learned", L, nLearned))
    H.assertEq(L, (1 << nLearned) - 1,
      "Cyan's real learned set is contiguous from tech 0 (level-derived)")
    H.assertEq(nLearned >= 2, true,
      "at least two techs learned -- one-tech and empty pages would render, "
      .. "but the duplicate-rung clamp below needs a second tech to show")
    local c = nLearned - 1
    local b = math.max(0, c - 2)
    t = { math.min(c, b), math.min(c, b + 1), math.min(c, b + 2) }
    H.log(string.format("auto window {%d,%d,%d}", t[1], t[2], t[3]))
    H.assertEq(H.readByte(LOADOUT) | (H.readByte(LOADOUT + 1) << 8), 0,
      "the loadout word is $0000 as saved (no real save has configured one)")
  end),

  -- the player's path: X -> main menu -> Skills -> CYAN -> submenu
  -- driveUntil, not one press: the X that opens the field menu is the first
  -- step in these tests that needs a SPECIFIC frame, so it is where a
  -- fixture minted against a different ROM surfaces -- as "timeout waiting
  -- for main menu", which reads like a menu bug and is not one.  Retrying
  -- the press costs nothing when the pairing is fine and removes the false
  -- report when it is not.  Same shape probe_fieldicons.lua and
  -- menu_blitzpage_sabin.lua already use.  The assertion is unchanged: the
  -- main menu must still come up.
  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),
  -- FIND Cyan rather than assume his row (measured: menu slot 1 is $FF here).
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
    assertRun(LEFT_COL, TITLE_ROW, TITLE, "title SWDTECH")
    assertRun(HINT_COL, TITLE_ROW, HINT, "L/R SWAPS control hint")
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
    -- the three boost slots, derived from the save's own set: window {0,1,1}
    -- on the measured fixture, i.e. the 3x rung CLAMPED to the ceiling shows
    -- the top tech AGAIN -- the honest early-Cyan page the old staging never
    -- rendered.  #56: costs 4 / 10 -- the one- to two-digit boundary is still
    -- on screen (Retort is two-digit).
    assertSlotRow(BOOST_ROWS[1], bushBytes(t[1]), t[1],
      "slot 1x " .. bushText(t[1]))
    assertSlotRow(BOOST_ROWS[2], bushBytes(t[2]), t[2],
      "slot 2x " .. bushText(t[2]))
    assertSlotRow(BOOST_ROWS[3], bushBytes(t[3]), t[3],
      "slot 3x " .. bushText(t[3]) .. " (ceiling clamp)")
    -- the LEARNED pool: exactly the learned names, in id order, column-major.
    -- Cross-check the hardcoded literals against the ROM records the drawing
    -- code actually reads (the encode-pipeline positive control).
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
    -- spray canaries: undrawn odd pool rows are still cleared
    if nLearned < 4 then
      assertRowBlank(9 + 3 * 2, "row 15 (no 4th learned tech)")
    end
    -- the title row's gaps and tail (#44).  Three chrome words now share it:
    -- SWDTECH 3..9, the hint 11..19, LEARNED 22..28.  The gaps are what keeps
    -- them from reading as one string, so they are asserted, not tolerated --
    -- a wording change that eats column 10 or 20 fails here rather than
    -- shipping as "SWDTECHL/R SWAPS".  Nothing may run into the window's own
    -- right border in column 30.
    for _, x in ipairs({ 10, 20, 21 }) do
      H.assertEq(cell(x, TITLE_ROW), 0,
        string.format("title row gap blank {%d,1}", x))
    end
    for x = 29, 31 do
      H.assertEq(cell(x, TITLE_ROW), 0,
        string.format("title row tail blank {%d,1}", x))
    end
    -- #49: the loadout word is $0000 here, so the page must say AUTO
    assertModeBlock(true, "real set, untouched")
    H.assertEq(H.readByte(LOADOUT), 0, "the loadout word is still AUTO ...")
    H.assertEq(H.readByte(LOADOUT + 1), 0, "... in both its bytes")
    assertGeometry("real set")
    -- the cursor gutter, on every one of the three boost rows: nothing under
    -- the sprite, content starting in the column right after it.
    for n = 0, 2 do assertCursorGutter(n, true, "real set") end
    H.screenshot("swdtech_page_player_path")
    H.log("PASSED: Skills->SwdTech via the player's path renders for a REAL "
      .. "CYAN -- title, labels, slots (with the ceiling clamp), costs, pool "
      .. "correct; every drawn cell on an ODD row inside row 15 and clear of "
      .. "the border column")
  end),

  -- ---- #49: the mode is LIVE, in both directions ----
  -- Everything above is AUTO.  A mode indicator that only ever renders one of
  -- its two words proves nothing, and one drawn at page-init would keep saying
  -- AUTO for as long as the player stayed on the page -- which is exactly the
  -- failure this block exists to catch.  R cycles the cursored rung, which calls
  -- Ot6LoadoutSeedWord and makes $1e1d nonzero = MANUAL; the page must say so on
  -- the very next redraw, without leaving the page.
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

  -- ... and Y reverts.  The revert is the half a player cannot guess, which is
  -- why the control is named on screen; it is also the half that proves the two
  -- words are the same width -- a short "AUTO" would leave MANUAL's L behind.
  H.pressButtons({ "y" }, 3),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(H.readByte(LOADOUT), 0, "Y cleared the loadout word ...")
    H.assertEq(H.readByte(LOADOUT + 1), 0, "... in both its bytes: AUTO again")
    assertModeBlock(true, "after Y")
    assertGeometry("after Y")
    -- the boost rows still name techs (AUTO recomputes them on the fly)
    for i, y in ipairs(BOOST_ROWS) do
      assertRun(NAME_COL, y, bushBytes(t[i]), "boost row " .. i .. " back on auto")
    end
    H.screenshot("swdtech_page_reverted")
    H.log("REVERT: Y put the page back on AUTO, the indicator followed, and "
      .. "'MANUAL' left nothing of itself behind in the six-cell field")
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

  -- ======================================================================= --
  -- *** LABELED ISOLATION ARM (issue #75, owner's learn-ceiling ruling) *** --
  -- The WHOLE learned pool inside the window (#43), and Quadra Slice's
  -- twelve-cell name beside its two-digit price (#56) -- both need all eight
  -- techs, and tech 8 is LEVEL 68.  One byte is written, once: $1cf7 = $ff.
  -- The loadout word is NOT written -- Y above already proved it $0000, and
  -- that is asserted rather than re-zeroed.  See the header; this arm may
  -- never produce fixtures, and converts organically when high-level content
  -- reaches the frontier.
  -- ======================================================================= --
  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_SKILLS end, 300,
    "back out of the configurator", 5),
  H.call(function()
    H.writeByte(LEARNED, 0xff)            -- THE arm's one write (see header)
    H.assertEq(H.readByte(LOADOUT) | (H.readByte(LOADOUT + 1) << 8), 0,
      "the word is still $0000 from Y's revert -- nothing to zero")
    H.log("[isolation arm] $1cf7 := $ff -- the L68 all-eight Cyan, unmintable "
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
    -- all eight, column-major: cells 0-3 down col 3, cells 4-7 down col 17.
    for n = 0, 7 do
      assertRun(poolCol(n), poolRow(n), bushBytes(n),
        string.format("pool cell %d '%s' at {%d,%d}",
          n, bushText(n), poolCol(n), poolRow(n)))
    end
    -- the three boost rows are still full-height rows with a priced tech on
    -- them (ceiling 7 -> base 5 -> Stunner / Quadra Slice / Cleave).
    -- #56: this is the STRONGEST arm for the price field -- tech 6 is
    -- "Quadra Slice", the only BushidoName that fills all twelve of its cells,
    -- and its price is 30, so the widest name and a two-digit number sit either
    -- side of the single blank at column 17.  That pairing is exactly what the
    -- old four-cell field could not hold.
    for i, y in ipairs(BOOST_ROWS) do
      assertRun(NAME_COL, y, bushBytes(4 + i), "boost row " .. i .. " tech")
      assertCostField(y, 4 + i, string.format("boost row %d '%s'",
        i, bushText(4 + i)))
    end
    assertModeBlock(true, "8 learned, untouched")
    assertGeometry("8 learned")
    -- the full pool is the case that puts a glyph in EVERY cursored row and in
    -- both pool columns, so it is the strongest state to check the gutter in.
    for n = 0, 2 do assertCursorGutter(n, true, "8 learned") end
    H.screenshot("swdtech_page_full_pool")
    H.log("FULL POOL (isolation arm): all eight Bushido techs drawn in two "
      .. "columns of four on rows 9/11/13/15 -- every cell inside the window, "
      .. "none on an even row, none past row 15, none in column 30, none "
      .. "under the cursor")
  end),
})
