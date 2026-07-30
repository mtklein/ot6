-- @suite frontier=arvis_wake
-- menu_ragepage.lua -- issue #40: the field Skills->Rage LOADOUT page RENDERS.
--
-- The page (MenuState_7c / Ot6Rage* in ot6_kits.asm, the C3 shim at
-- field_menu.asm:2907-3075) was wired, assembled and shipped without one
-- rendered cell ever being asserted.  That is exactly the hole issue #39 fell
-- through on the SwdTech configurator: menu_bushidoloadout force-jumped
-- zMenuState and asserted only stored bytes, so a page whose every label
-- streamed the ending-credits charmap into the tilemap stayed green.  This
-- test gives the Rage page the menu_swdtechpage treatment:
--
--   * PATH: it drives the real UI -- X -> Skills -> character -> the Rage row
--     -> A -- so SkillsOption_05 (field_menu.asm:1327-1348) opens the
--     configurator, not a forced state;
--   * RENDER: it asserts the BG1A tilemap shadow cell-by-cell -- the title,
--     each slot's MONSTER name, the flat "8 MP" cost suffix, the LEARNED
--     caption and its three-digit count -- and, the class-closer, that every
--     row the page never draws on is still all-zero (a runaway unterminated
--     draw cannot leave them blank).
--
-- THE 12-PIXEL CADENCE (found by this test's first run, and the reason the
-- page's layout changed).  The tilemap was always CORRECT; what was wrong was
-- WHERE on it the page drew.  The EN field-menu window does not show BG1
-- ScreenA one tile row per eight scanlines: a row PAIR occupies twelve
-- scanlines, the ODD row getting eight and the even row four, and nothing past
-- row 15 is inside the window at all (measured with a per-row glyph ruler,
-- probe_ragegeom.lua; vanilla's own cursor tables say it from the other side --
-- every EN list for this window is `cursor_pos {x, 116 + n*12}`,
-- skills.asm:125-126, and DrawRageName biases its row `.if LANG_EN`,
-- skills.asm:1571-1574).  The page shipped with eight slots on EVEN rows
-- 4..18 and LEARNED on row 20, so through the player's path every beast name
-- rendered as a three-scanline sliver and the collection counter was off the
-- bottom of the window.  It now draws two columns of four on odd rows 5/7/9/11
-- with LEARNED on 15 -- vanilla's own shape for this very window.  Hence the
-- EVEN-ROW CANARY below: it is not decoration, it is the regression.
--
-- THE CURSOR GUTTER (#43 round 3) -- the same cadence story, in x.  The cursor
-- is a 16x16 SPRITE and `cursor_pos {x,y}` is its top-left corner, so an entry
-- at x owns tilemap columns x/8 and x/8+1 and the row it points at must start
-- at x/8+2.  Vanilla's arithmetic is cursor_x = 8*col - 16 everywhere in this
-- window: magic draws at cols 3/16 under cursors 8/112 (skills.asm:831, :836 vs
-- :125-126), espers at 3/17 under 8/120 (:1733, :1737 vs :249-250), rage at
-- 5/19 under 24/136 (:1544, :1548 vs :292-293), config's value column 14 under
-- 96 (config.asm:50); measured the same way on the shipped ROM, where the magic
-- list's `cursor_pos {8, 116}` lights screen x 8..23, y 116..131
-- (tools/tests/probe_menucols.lua).  This page's RIGHT column was already
-- right -- col 16 under x=112 is vanilla's magic pair verbatim -- but its LEFT
-- column drew at col 2 under x=8, so the sprite covered the first letter of
-- every left-hand beast name.  The left column is 3 now; the cursor table did
-- not move.  THE CURSOR GUTTER CANARY below reads Ot6RageCursorPos out of the
-- ROM and checks both halves against the tilemap, so neither can move alone.
-- It is duplicated from menu_swdtechpage.lua rather than shared: the only lua
-- the runner inlines is lib/ot6{,_field,_contract}.lua, and those three files
-- ARE the frontier mint signature (lib/frontier_stamp.sh:49-55), so a helper
-- added there would mark every minted fixture drifted.
--
-- THE NAME SOURCE, and why it is not the SwdTech one.  Ot6DrawRageName
-- (field_menu.asm:2992-3016) calls GetMonsterNamePtr (skills.asm:1557-1565),
-- which points LoadArrayItem at MonsterName -- a 384-entry, 10-byte fixed
-- record table (include/text/monster_name_en.inc:13-14), NOT BushidoName and
-- not any spell table.  So the expected bytes are read out of the ROM's own
-- MonsterName records at runtime (H.sym + readRomByte): the assertion is
-- against the very bytes the drawing code streams, and a text re-encode
-- cannot silently invalidate a hardcoded literal here.  LoadArrayItem copies
-- all ten bytes including the $ff pad tail (item.asm:1255-1276), so a name's
-- full 10-cell field is asserted, pads and all.
--
-- issue #44 -- THE CONTROL HINT and THE EMPTY MARKER.  Two owner-playtest
-- findings on a page that already rendered correctly.  L/R cycling the
-- cursored slot is the page's only real interaction and nothing named it; and
-- an unset slot was a run of $ff pads, which reads as a rendering bug rather
-- than as "you have not hunted eight species yet".  Row 3 was spare (the page
-- draws on 1/5/7/9/11/15), so the hint cost nothing but that row; the marker
-- replaces the pad fill over exactly the same ten cells.  The EXPECTED cells
-- below were rewritten to that layout deliberately -- assertRowBlank(3) became
-- a positive assertion on the hint plus head/tail guards, and assertEmptyRow
-- checks the marker's bytes instead of ten pads.  Neither was loosened.
--
-- Fixture: arvis_wake (the menu_swdtechpage / menu_bushidoloadout boot).  Its
-- lead has no Rage command, so it is installed the house "install state" way:
-- the lead's third battle-command byte becomes BATTLE_CMD::RAGE ($10) and five
-- bits are set in the $1d2c-$1d4b learned-rage bitfield.  Five is chosen on
-- purpose -- inside the eight slots, so the SAME render exercises filled rows
-- (name + cost) and empty rows (the $ff-blanked name field and blanked cost),
-- and AUTO's window is short.  The loadout bytes stay $00 (AUTO): opening the
-- page must write NOTHING, the implicit-seed property the Bushido page has.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/arvis_wake.mss.lua"

local ZMENUSTATE, ZCURSOR = 0x26, 0x4b
local RAGE_ROW_COLOR = 0x7e             -- zSkillsTextColor::Rage (menu_ram.inc)
local CMD3 = 0x1618                     -- lead char's 3rd battle command
local BATTLE_CMD_RAGE = 0x10
local RAGES = 0x1D2C                    -- learned-rage bitfield, 32 bytes
local RAGELOAD = 0x1E1F                 -- OT6_RAGELOAD: 8 bytes, id+1, 0 = unset
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_RAGELOAD = 0x05, 0x06, 0x0a, 0x7c
local SKILLS_ROW_RAGE = 5               -- Espers Magic SwdTech Blitz Lore RAGE Dance

local function st() return H.readByte(ZMENUSTATE) end

-- BG1 screen A tilemap shadow (wBG1Tiles::ScreenA = $7e3849, menu_ram.inc):
-- 2 bytes per cell (char, color), 64 bytes per row; cell(x,y) = char byte.
local BG1A = 0x3849
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end

-- menu text codec (ff6/tools/char_table/text_en.json): 'A'=$80.. 'a'=$9a..
-- '0'=$b4.. ' '=$ff.  ZERO_CHAR and " MP" are menu_text_en.inc.raw:7,:128.
local T = { A=0x80, C=0x82, D=0x83, E=0x84, G=0x86, H=0x87, L=0x8b, M=0x8c,
            N=0x8d, O=0x8e, P=0x8f, R=0x91, S=0x92, T=0x93, U=0x94, W=0x96,
            Y=0x98, DASH=0xc4, SLASH=0xc0, EQ=0xd2, SP=0xff }
local TITLE   = { T.R,T.A,T.G,T.E,T.SP,T.L,T.O,T.A,T.D,T.O,T.U,T.T }  -- RAGE LOADOUT
local LEARNED = { T.L,T.E,T.A,T.R,T.N,T.E,T.D }
local EACH_TX = { T.E,T.A,T.C,T.H }
-- #44: the control hint, character for character the same string the Bushido
-- loadout page draws.  Both pages cycle the cursored entry with L/R and both
-- shipped without saying so; a player who learns the idiom on one must not
-- have to re-learn it on the other, so the strings are asserted to be equal by
-- being written out identically in both tests.
local HINT    = { T.L,T.SLASH,T.R,T.SP,T.S,T.W,T.A,T.P,T.S }  -- L/R SWAPS
-- #49: the STATE that L/R changes, which the page never showed.  All eight
-- bytes zero is AUTO -- the game picks the first eight species in id order and
-- keeps re-picking as Gau hunts -- and the first cycle calls Ot6RageSeed and
-- freezes that window into the save, permanently, until Y clears it.  A player
-- could not see which of the two they were in, nor that Y existed.
--
-- Both words are six cells, "AUTO" space-padded, so a MANUAL -> AUTO revert
-- overwrites the whole field; asserted as an equality below rather than trusted.
-- Written out character for character in BOTH page tests on purpose, the #44
-- rule: two pages that teach the same idiom must teach it in the same words.
local MODE_AUTO   = { T.A,T.U,T.T,T.O,T.SP,T.SP }
local MODE_MANUAL = { T.M,T.A,T.N,T.U,T.A,T.L }
local MODE_HINT   = { T.Y,T.EQ,T.A,T.U,T.T,T.O }              -- Y=AUTO
-- #44: what an UNSET slot draws now, in place of a run of $ff pads.  Exactly
-- MonsterName::ITEM_SIZE (10) cells, so it still overwrites a name completely
-- and a revert wipes what was there -- the property the pad fill had.
local EMPTY_TX = { T.DASH,T.SP,T.E,T.M,T.P,T.T,T.Y,T.SP,T.DASH,T.SP }
local ZERO_CHAR = 0xb4
local MP_SUFFIX = { T.SP, T.M, T.P }
local PAD = 0xff                        -- fixed_length_en.json: 0xFF = {pad}

-- MonsterName, verbatim, out of the ROM the drawing code reads.
-- H.sym gives the 24-bit CPU address; & 0x3FFFFF is the snesPrgRom file offset.
local MONNAME = H.sym("MonsterName") & 0x3FFFFF
local NAME_SIZE = 10                    -- MonsterName::ITEM_SIZE
local function nameBytes(id)
  local t = {}
  for i = 0, NAME_SIZE - 1 do t[i + 1] = H.readRomByte(MONNAME + id * NAME_SIZE + i) end
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

-- Five species, spread over several bitfield bytes so the AUTO window has to
-- cross byte boundaries the way a real Gau's does, and short of eight so the
-- same page shows filled AND empty rows.
local KNOWN = { 3, 20, 41, 90, 130 }    -- Ninja Ursus Beakor Ghost Zombone
-- #44: ten species -- more than the eight slots -- so the last phase of this
-- test can show the page with NO empty row on it.  The empty marker is only
-- honest if it disappears the moment a slot has something in it, and the only
-- way to see that is a state where the AUTO window fills every slot.  AUTO is
-- "the first eight known in id order" (Ot6RageNth), so the eight drawn are the
-- eight lowest ids here and 150/200 stay out of the loadout.
local KNOWN_FULL = { 3, 5, 20, 41, 60, 77, 90, 130, 150, 200 }

local function teach(ids)
  for i = 0, 31 do H.writeByte(RAGES + i, 0) end
  for _, id in ipairs(ids) do
    local a = RAGES + (id >> 3)
    H.writeByte(a, H.readByte(a) | (1 << (id & 7)))
  end
end

local function assertRun(x0, y, bytes, what)
  for i, b in ipairs(bytes) do
    H.assertEq(cell(x0 + i - 1, y), b,
      string.format("%s: cell {%d,%d}", what, x0 + i - 1, y))
  end
end

-- The class-closer: a row the configurator never draws on must be untouched
-- ($00 from ClearBG1ScreenA).  #39's runaway draws carpeted BG1A with ROM code
-- bytes, so every one of these would fail on a garbled page.
local function assertRowBlank(y, what)
  for x = 0, 31 do
    H.assertEq(cell(x, y), 0, string.format("%s: cell {%d,%d} blank", what, x, y))
  end
end

-- Page geometry, mirroring field_menu.asm's Ot6RageDrawSlots: two columns of
-- four on ODD rows.  slot even = left column (name col 3), slot odd = right
-- (col 16); row = 5 + (slot & ~1).  {3, 16} under cursors {8, 112} is vanilla's
-- magic list verbatim -- see the cursor-gutter note in the header.  The price
-- is stated ONCE on the title row ("8 MP EACH") rather than per row: two
-- 10-cell names plus two cursor gutters plus two cost fields does not fit
-- inside the window's right border, which is column 30 (measured at screen
-- x = 245).  The price is flat by design, so one copy teaches the same rule.
local TITLE_ROW, LEARNED_ROW = 1, 15
local HINT_ROW = 3                      -- #44: row 3 was spare; the hint has it
local LEFT_COL = 3                      -- the page's left margin (gutter = 1-2)
-- #56: the price field is FIVE cells, "nn MP", not four -- Ot6LoadoutDrawCost
-- is the one price drawer in the field menu now and it carries a tens place.
-- It moved LEFT (17 -> 16) rather than growing rightwards, because "EACH" is a
-- fixed pos_text at 22 and a five-cell field starting at 17 would have rendered
-- "8 MPEACH".  This page's number is 8 today and can reach two digits without
-- anyone editing it: Ot6RageCost tail-calls Ot6DanceCost (ot6_boost.asm:600-619)
-- deliberately, and mp-economy.md's band for a flat possess-verb price is 4-10.
local COST_COL, EACH_COL = 16, 22
local COUNT_COL = 11                    -- just past "LEARNED " at 3..9
-- #49: row 13 was this page's one spare row (it draws on 1/3/5/7/9/11/15) and
-- issue #49's survey costed it at 27 free columns.  The mode goes at column 3
-- and the control that changes it at 16 -- the page's OWN two slot columns, so
-- the pair lines up under the grid instead of floating.  Row 13 is therefore no
-- longer in the "undrawn odd row" list below; that assertion became the
-- positive one in assertModeBlock, deliberately, not by being dropped.
local MODE_ROW, MODE_COL, MODE_HINT_COL = 13, 3, 16
local function slotRow(slot) return 5 + (slot & ~1) end
local function slotCol(slot) return (slot % 2 == 0) and LEFT_COL or 16 end

-- THE CURSOR GUTTER CANARY (#43 round 3).  Both sides are read, not written:
-- the cursor table comes out of the ROM the menu itself indexes, and the text
-- comes out of the tilemap the menu itself drew.
--
-- `cursor_pos {x, y}` assembles to `.byte x, y` (menu_ram.inc:582-584), two
-- bytes per entry, in the framework's index order ($4b = 2*row + col).  It is
-- the TOP-LEFT of a 16x16 sprite, so entry x owns tilemap columns x/8 and
-- x/8+1 and the slot it points at must start at x/8+2.  y is 116 + n*12 and
-- tilemap row = 2n+1, so the row an entry points at is (y-116)/6 + 1.
local CURSOR_POS = H.sym("Ot6RageCursorPos") & 0x3FFFFF
local function cursorEntry(n)
  return H.readRomByte(CURSOR_POS + n * 2), H.readRomByte(CURSOR_POS + n * 2 + 1)
end

local function assertCursorGutter(n, what)
  local cx, cy = cursorEntry(n)
  local col, y = cx // 8, (cy - 116) // 6 + 1
  H.assertEq(y % 2 == 1 and y >= 1 and y <= 15, true, string.format(
    "%s: cursor entry %d (y=%d) points at tilemap row %d, which this window "
    .. "does not show whole", what, n, cy, y))
  H.assertEq(y, slotRow(n), string.format(
    "%s: cursor entry %d must point at slot %d's row", what, n, n))
  -- the two columns UNDER the sprite carry no glyph ...
  for _, x in ipairs({ col, col + 1 }) do
    H.assertEq(cell(x, y), 0, string.format(
      "%s: cursor entry %d sits at x=%d, so tilemap {%d,%d} is under the "
      .. "sprite and must be blank", what, n, cx, x, y))
  end
  -- ... and the slot it points at begins in the very next one.  An UNFILLED
  -- slot is $ff-blanked across its width, which is still a drawn cell, so this
  -- holds at any known-rage count.
  H.assertEq(cell(col + 2, y) ~= 0, true, string.format(
    "%s: cursor entry %d at x=%d reserves columns %d-%d, so slot %d must start "
    .. "at column %d (vanilla: cursor_x = 8*col - 16)",
    what, n, cx, col, col + 1, n, col + 2))
  H.assertEq(col + 2, slotCol(n), string.format(
    "%s: cursor entry %d and slot %d's draw column must agree", what, n, n))
  -- for a left-column entry, nothing at all may precede it on the row
  if slotCol(n) == LEFT_COL then
    for x = 0, col + 1 do
      H.assertEq(cell(x, y), 0, string.format(
        "%s: {%d,%d} is left of the cursored row's first glyph (column %d)",
        what, x, y, col + 2))
    end
  end
end

-- #49: row 13, asserted as a whole row -- the mode word, the control, and every
-- other cell on the row still blank, so neither half can grow into the other or
-- into the window's border column 30.
local function assertModeBlock(auto, what)
  H.assertEq(#MODE_AUTO, #MODE_MANUAL,
    "the two mode words must be the same width, or a MANUAL -> AUTO revert "
    .. "leaves the tail of MANUAL on screen")
  assertRun(MODE_COL, MODE_ROW, auto and MODE_AUTO or MODE_MANUAL,
    string.format("%s: the page states %s", what, auto and "AUTO" or "MANUAL"))
  assertRun(MODE_HINT_COL, MODE_ROW, MODE_HINT,
    what .. ": the revert control is named beside the mode")
  for x = 0, 31 do
    local inMode = x >= MODE_COL and x < MODE_COL + #MODE_AUTO
    local inHint = x >= MODE_HINT_COL and x < MODE_HINT_COL + #MODE_HINT
    if not inMode and not inHint then
      H.assertEq(cell(x, MODE_ROW), 0, string.format(
        "%s: {%d,%d} is neither the mode nor the control and must stay blank",
        what, x, MODE_ROW))
    end
  end
end

local function assertFilledRow(slot, id)
  local y, c = slotRow(slot), slotCol(slot)
  assertRun(c, y, nameBytes(id), string.format("slot %d name %s", slot, nameText(id)))
end
-- An UNSET slot (#44).  It used to be $ff pads across the full name width --
-- correct (a revert wiped what was there) and unreadable: the owner's playtest
-- read the blank rows as a bug.  It now spells "- EMPTY - " over exactly the
-- same ten cells, so the overwrite property is unchanged and the row says what
-- it means.
--
-- WHY "EMPTY" AND NOT "DEFAULT".  A blank row has two causes and both mean the
-- slot contributes NOTHING to the battle list, so neither is a default:
--   * AUTO (all eight bytes $00) with fewer than eight species hunted --
--     Ot6RageNth returns carry clear past the end of the window
--     (ot6_kits.asm:1856-1858), and Ot6RageList's AUTO arm writes no id for it;
--   * MANUAL with a $00 byte -- Ot6RageSlot returns carry clear (:1820) and
--     Ot6RageList's @manual arm SKIPS the slot (:1993-2002).
-- This test exercises the first (five species known, slots 5-7 unset) and the
-- second (after the first edit, Ot6RageSeed leaves the tail at $00).
local function assertEmptyRow(slot)
  local y, c = slotRow(slot), slotCol(slot)
  H.assertEq(#EMPTY_TX, NAME_SIZE,
    "the empty marker must be exactly a name field wide, or a revert leaves "
    .. "the tail of the old name on screen")
  for i, b in ipairs(EMPTY_TX) do
    H.assertEq(cell(c + i - 1, y), b,
      string.format("empty slot %d: '- EMPTY -' cell {%d,%d}",
        slot, c + i - 1, y))
  end
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  -- install state: the Rage command on the lead + five hunted species, AUTO
  -- loadout (all eight bytes zero -- the state every real save is in).
  H.call(function()
    H.writeByte(CMD3, BATTLE_CMD_RAGE)
    teach(KNOWN)
    for i = 0, 7 do H.writeByte(RAGELOAD + i, 0) end
    H.log("installed: Rage on the lead, " .. #KNOWN .. " species hunted, AUTO loadout")
  end),

  -- the player's path: X -> main menu -> Skills -> lead character -> submenu
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
  H.pressButtons({ "down" }, 2),            -- Items -> Skills
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.readByte(RAGE_ROW_COLOR), 0x20,
      "Rage row enabled (install-state command took)")
  end),

  -- cursor down to the Rage row, A opens the configurator through
  -- SkillsOption_05 -- the exact edge no test has ever driven.
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == SKILLS_ROW_RAGE
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "skills cursor to Rage"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_RAGELOAD end, 300,
    "rage configurator open via the player path", 5),
  H.waitFrames(90),                         -- draws + DMA settle

  H.call(function()
    -- chrome
    assertRun(LEFT_COL, TITLE_ROW, TITLE, "title RAGE LOADOUT")
    -- the flat price, stated once: "8 MP EACH" on the title row.  #56: five
    -- cells, right-aligned -- the tens cell is BLANK for a one-digit price and
    -- must not be '0' (vanilla's own rule: HexToDec3 overwrites leading zeroes
    -- with $ff, menu_common.asm:906-918).
    H.assertEq(cell(COST_COL, TITLE_ROW), PAD,
      "the trance price is one digit, so its tens cell is blank, not '0'")
    H.assertEq(cell(COST_COL + 1, TITLE_ROW), ZERO_CHAR + 8,
      "the trance price on the title row is 8 (Dance's number, one authority)")
    assertRun(COST_COL + 2, TITLE_ROW, MP_SUFFIX, "' MP' after the price")
    H.assertEq(cell(EACH_COL - 1, TITLE_ROW), 0,
      "a gap separates the price field from 'EACH' -- without it the title row "
      .. "reads '8 MPEACH' (the #49 failure, on this page's row)")
    assertRun(EACH_COL, TITLE_ROW, EACH_TX, "'EACH' -- the price is per trance")
    -- #44: the control hint, on the one spare row above the slots
    assertRun(LEFT_COL, HINT_ROW, HINT, "L/R SWAPS control hint")
    assertRun(LEFT_COL, LEARNED_ROW, LEARNED, "LEARNED caption")
    -- the collection score: three digits at col 11 of the caption row
    assertRun(COUNT_COL, LEARNED_ROW, { ZERO_CHAR, ZERO_CHAR, ZERO_CHAR + #KNOWN },
      "LEARNED count = 00" .. #KNOWN)

    -- AUTO's window: the first eight known rages in id order.  Five are known,
    -- so slots 0-4 draw those five and slots 5-7 draw blank.
    for i, id in ipairs(KNOWN) do
      assertFilledRow(i - 1, id)
      H.log(string.format("slot %d at {%d,%d} = rage %d '%s'",
        i - 1, slotCol(i - 1), slotRow(i - 1), id, nameText(id)))
    end
    for slot = #KNOWN, 7 do assertEmptyRow(slot) end

    -- opening the page WRITES NOTHING: AUTO is computed per slot on the fly
    -- (Ot6RageShow), so an un-edited page leaves every save byte at zero.
    for i = 0, 7 do
      H.assertEq(H.readByte(RAGELOAD + i), 0,
        string.format("opening the page did not seed OT6_RAGELOAD+%d", i))
    end

    -- THE EVEN-ROW CANARY -- the regression this test exists for.  An even
    -- tilemap row is shown as three scanlines in this window, so nothing the
    -- page draws may land on one.  Rows past 15 are outside the window
    -- entirely, so nothing may land there either.  Both were violated before
    -- (slots on 4..18, LEARNED on 20), and a plain tilemap assertion could
    -- not see it -- only the geometry rule can.
    for y = 0, 27 do
      if y % 2 == 0 or y > 15 then
        assertRowBlank(y, string.format(
          "row %d is unusable (%s) and must stay blank", y,
          y > 15 and "outside the window" or "even: 3 scanlines"))
      end
    end
    -- Every odd row this page has is spoken for now.  Row 3 was the last one
    -- until #44 spent it on the control hint; #49 has spent row 13 on the mode
    -- block.  Both were asserted blank here once and both became POSITIVE
    -- assertions instead (assertRun on the hint above, assertModeBlock below) --
    -- neither was dropped, and assertModeBlock still pins every cell of row 13
    -- that is not one of the two words.
    assertModeBlock(true, "opened untouched")
    -- ... and the hint row's own head and tail, so the hint cannot grow into
    -- the cursor gutter on its left or the window border on its right.  The
    -- hint runs 3..11; everything else on row 3 is blank.
    for x = 0, 2 do
      H.assertEq(cell(x, HINT_ROW), 0, string.format(
        "{%d,%d} is the cursor gutter -- the hint starts at column %d",
        x, HINT_ROW, LEFT_COL))
    end
    for x = LEFT_COL + #HINT, 31 do
      H.assertEq(cell(x, HINT_ROW), 0,
        string.format("hint row tail blank {%d,%d}", x, HINT_ROW))
    end
    -- the gaps on the title row, its head and its tail: nothing may sit left
    -- of the page's margin (columns 0-2, the cursor's own gutter) and nothing
    -- may run into the window's right border, which lives in column 30.
    -- "RAGE LOADOUT" occupies 3..14, the price 16..20 (#56: five cells, its
    -- leading one blank at this price), EACH 22..25.  Column 16 is therefore
    -- no longer in this list -- it holds the price field's blank tile ($ff),
    -- which is asserted above as a value rather than dropped from here.
    for _, x in ipairs({ 0, 1, 2, 15, 21, 26, 27, 28, 29, 30, 31 }) do
      H.assertEq(cell(x, TITLE_ROW), 0,
        string.format("title row gap/tail blank {%d,%d}", x, TITLE_ROW))
    end
    -- and the same for the LEARNED row: caption 3..9, count 11..13.
    for _, x in ipairs({ 0, 1, 2, 10, 14, 15, 29, 30, 31 }) do
      H.assertEq(cell(x, LEARNED_ROW), 0,
        string.format("LEARNED row gap/tail blank {%d,%d}", x, LEARNED_ROW))
    end
    -- THE CURSOR GUTTER CANARY, every slot: nothing under the sprite, the slot
    -- starting in the column right after it -- on BOTH columns.  Five species
    -- are known, so this covers filled rows and $ff-blanked ones in one pass.
    for n = 0, 7 do assertCursorGutter(n, "5 known") end
    H.screenshot("rage_page_player_path")
    H.log("RENDER OK: Skills->Rage via the player's path -- title, eight slots "
      .. "in two columns on the window's odd rows, names against MonsterName "
      .. "verbatim, the flat 8 MP stated once, LEARNED count; nothing on an "
      .. "even row, nothing past row 15, nothing in the border column, nothing "
      .. "in either cursor's gutter")
  end),

  -- ---- the page is LIVE, not a one-shot draw: R cycles the cursored slot ----
  -- The first edit out of AUTO freezes the window into the eight bytes
  -- (Ot6RageSeed) and then walks the bitfield, so slot 0 must move from the
  -- first known species to the second and the row must REDRAW to match.
  H.pressButtons({ "r" }, 3),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(H.readByte(RAGELOAD + 0), KNOWN[2] + 1,
      "R cycled slot 0 to the next learned rage (stored byte = id + 1)")
    for i = 2, #KNOWN do
      H.assertEq(H.readByte(RAGELOAD + i - 1), KNOWN[i] + 1,
        string.format("the first edit froze AUTO's window into slot %d", i - 1))
    end
    for i = #KNOWN, 7 do
      H.assertEq(H.readByte(RAGELOAD + i), 0,
        string.format("slot %d had no window entry to freeze, stays unset", i))
    end
    assertFilledRow(0, KNOWN[2])
    -- #44: the page is MANUAL now and the tail slots are stored $00 -- a
    -- genuinely empty slot that Ot6RageList skips, not an "unfilled default".
    -- The marker must read the same here as it did under AUTO, because it
    -- means the same thing: nothing in this slot, nothing in the battle list.
    for slot = #KNOWN, 7 do assertEmptyRow(slot) end
    -- #49: and the page must SAY it went manual, on this same redraw and
    -- without being reopened.  A mode drawn once at page-init would still read
    -- AUTO here, which is the exact failure this assertion exists for.
    assertModeBlock(false, "after the first edit")
    H.assertEq(H.readByte(ZMENUSTATE), ST_RAGELOAD, "still on the rage page")
    H.screenshot("rage_page_after_cycle")
    H.log("LIVE: R redrew slot 0 as '" .. nameText(KNOWN[2])
      .. "' , the first edit froze the AUTO window into the save bytes, and the "
      .. "mode indicator followed it from AUTO to MANUAL in the same frame")
  end),

  -- ---- #49: Y reverts, and the indicator comes back with it ----
  -- The revert is the half a player cannot guess -- which is why the control is
  -- named on screen -- and it is the half that proves the two mode words are the
  -- same width: a five-cell "AUTO " would leave MANUAL's trailing L behind.
  -- Ot6RageInput's Y arm zeroes all eight bytes (ot6_kits.asm), so the window
  -- goes back to being computed on the fly and the five known species must
  -- re-appear in id order exactly as they did on entry.
  H.pressButtons({ "y" }, 3),
  H.waitFrames(40),
  H.call(function()
    for i = 0, 7 do
      H.assertEq(H.readByte(RAGELOAD + i), 0,
        string.format("Y cleared OT6_RAGELOAD+%d: the loadout is AUTO again", i))
    end
    assertModeBlock(true, "after Y")
    for i, id in ipairs(KNOWN) do assertFilledRow(i - 1, id) end
    for slot = #KNOWN, 7 do assertEmptyRow(slot) end
    H.screenshot("rage_page_reverted")
    H.log("REVERT: Y put the page back on AUTO -- the eight bytes are zero, the "
      .. "window is recomputed, and 'MANUAL' left nothing of itself behind in "
      .. "the six-cell field")
  end),

  -- put the page back into MANUAL for the phases below, which assert on the
  -- frozen bytes R wrote.  (Re-cycling slot 0 lands on the same species the
  -- first edit did: the walk is deterministic from the same starting point.)
  H.pressButtons({ "r" }, 3),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(H.readByte(RAGELOAD + 0), KNOWN[2] + 1,
      "back to MANUAL with slot 0 on the second known species, as before Y")
    assertModeBlock(false, "re-edited after the revert")
  end),

  -- ---- the SECOND column is reachable and maps to the right slot ----
  -- Two columns only exist because the window has eight text rows; the
  -- cursor index is $4b = 2*row + col, so dpad-Right from slot 0 must land on
  -- slot 1 -- the row-5 RIGHT cell -- and R must edit THAT byte and no other.
  H.pressButtons({ "right" }, 3),
  H.waitFrames(20),
  H.call(function() _G.__before = H.readByte(RAGELOAD + 1) end),
  H.pressButtons({ "r" }, 3),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(H.readByte(RAGELOAD + 0), KNOWN[2] + 1,
      "dpad-Right moved off slot 0: its byte is untouched by the second cycle")
    H.assertEq(H.readByte(RAGELOAD + 1), KNOWN[3] + 1,
      "and slot 1 -- the row-5 RIGHT cell -- cycled instead (was rage "
      .. tostring(_G.__before - 1) .. ")")
    assertFilledRow(1, KNOWN[3])
    for n = 0, 7 do assertCursorGutter(n, "cursor on the right column") end
    H.screenshot("rage_page_second_column")
    H.log("TWO COLUMNS: the cursor reaches slot 1 with dpad-Right and the "
      .. "cycle edits exactly that slot -- $4b = 2*row + col, on both sides; "
      .. "the right cursor's gutter (columns 14-15) is clear too")
  end),

  -- ---- and a LOWER row, so the shipped screenshots cover more than row 5 ----
  -- The canary above reads the whole cursor table, but only the row the sprite
  -- is parked on shows up in a picture.  Walk back to the LEFT column -- the
  -- half that moved -- and down to slot 4, the last FILLED left-hand row, so
  -- the shot shows the cursor abutting a name and not empty space.
  H.pressButtons({ "left" }, 3),
  H.waitFrames(20),
  H.pressButtons({ "down" }, 3),
  H.waitFrames(20),
  H.pressButtons({ "down" }, 3),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(H.readByte(ZMENUSTATE), ST_RAGELOAD, "still on the rage page")
    H.assertEq(H.readByte(ZCURSOR), 4, "cursor walked to slot 4 (row 9, left)")
    for n = 0, 7 do assertCursorGutter(n, "cursor on slot 4") end
    H.screenshot("rage_page_cursor_bottom")
    H.log("CURSOR WALK: the sprite is on slot 4 -- a lower LEFT row with a "
      .. "name in it -- and columns 1-2 are still empty on every slot row; the "
      .. "gutter is a property of the page, not of which slot is selected")
  end),

  -- ---- #44: a FULL page -- the empty marker must not survive a filled slot --
  -- Every state above has empty rows in it, so on its own it cannot tell
  -- "- EMPTY -" drawn for an unset slot from "- EMPTY -" leaking over a real
  -- one.  Back out, hunt ten species, revert to AUTO, and re-enter: the window
  -- now fills all eight slots, and the marker must appear NOWHERE on the page.
  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_SKILLS end, 300,
    "back out of the rage configurator", 5),
  H.call(function()
    teach(KNOWN_FULL)
    for i = 0, 7 do H.writeByte(RAGELOAD + i, 0) end   -- AUTO again
  end),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_RAGELOAD end, 300,
    "rage configurator reopened with ten species hunted", 5),
  H.waitFrames(90),

  H.call(function()
    assertRun(LEFT_COL, TITLE_ROW, TITLE, "title still on row 1")
    assertRun(LEFT_COL, HINT_ROW, HINT, "control hint still on row 3")
    -- eight filled slots: AUTO's window is the eight LOWEST known ids
    for slot = 0, 7 do
      assertFilledRow(slot, KNOWN_FULL[slot + 1])
    end
    -- ... and the marker is gone from the page entirely.  Scan every slot
    -- row's first cell: a filled slot starts with a name's first letter, never
    -- with the marker's leading dash.
    for slot = 0, 7 do
      H.assertEq(cell(slotCol(slot), slotRow(slot)) ~= T.DASH, true,
        string.format("slot %d is filled, so it must not draw the empty "
          .. "marker at {%d,%d}", slot, slotCol(slot), slotRow(slot)))
    end
    -- the collection score counts the WHOLE bitfield, not the eight slots:
    -- ten hunted, eight loaded, and the page must say ten.
    assertRun(COUNT_COL, LEARNED_ROW,
      { ZERO_CHAR, ZERO_CHAR + 1, ZERO_CHAR }, "LEARNED count = 010")
    -- the eight bytes were re-zeroed before this re-entry, so the page is AUTO
    -- again -- and the indicator must have been redrawn to match on OPEN, not
    -- only on an in-page edit.
    assertModeBlock(true, "reopened on AUTO with ten hunted")
    for n = 0, 7 do assertCursorGutter(n, "ten known, page full") end
    H.screenshot("rage_page_full")
    H.log("FULL PAGE: ten species hunted -- all eight slots carry a beast, the "
      .. "'- EMPTY -' marker appears nowhere, and LEARNED still reports the "
      .. "whole collection (010), not the eight that fit")
  end),
})
