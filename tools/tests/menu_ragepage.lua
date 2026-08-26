-- @suite savestate=gau_joined
-- menu_ragepage.lua -- the field Skills->Rage loadout page renders.
--
-- The page (MenuState_7c and Ot6Rage* in ot6_kits.asm) is driven through the
-- real UI (X -> Skills -> character -> the Rage row -> A), and rendering is
-- asserted cell by cell in the BG1A tilemap shadow: the title, each slot's
-- monster name, the flat "8 MP" cost suffix, the LEARNED caption and its
-- three-digit count, and every row the page never draws on is asserted
-- all-zero.
--
-- This test boots gau_joined, the post-join savestate on the world map with
-- CYAN, SABIN and GAU, finds Gau in zCharID, and reads everything off his
-- save: the Rage command is his record's own, the learned set is InitRage's
-- nine starting rages (ids 11, 14, 19, 21, 25, 46, 54, 57, 66; hunting only
-- adds, so >= 9 is a floor for every real save), and the loadout bytes are
-- $00 as saved, so AUTO needs no zeroing.  The nine-rage floor makes the
-- page full from its first open: AUTO's window always fills all eight
-- slots, and the LEARNED count (009) exceeds the eight drawn.
--
-- One labeled isolation arm: the "- EMPTY -" marker is unreachable by play
-- in both of its causes (AUTO shows an empty slot only below eight known
-- rages, and InitRage's floor is nine; MANUAL shows one only for a stored
-- $00 byte, and Ot6RageCycleCore can only store a learned id + 1), so the
-- marker's assertions live in a labeled tail arm that writes the $1d2c
-- bitfield down to five species.
--
-- The EN field-menu window does not show BG1 ScreenA one tile row per eight
-- scanlines: a row pair occupies twelve scanlines, the odd row getting
-- eight and the even row four, and nothing past row 15 is inside the window
-- at all.  The page draws two columns of four on odd rows 5/7/9/11 with
-- LEARNED on 15.
--
-- The cursor is a 16x16 sprite and `cursor_pos {x,y}` is its top-left
-- corner, so an entry at x owns tilemap columns x/8 and x/8+1 and the row
-- it points at must start at x/8+2; vanilla's arithmetic is
-- cursor_x = 8*col - 16 everywhere in this window.
--
-- Ot6DrawRageName calls GetMonsterNamePtr, which points LoadArrayItem at
-- MonsterName, a 384-entry, 10-byte fixed record table, rather than
-- BushidoName or any spell table.  LoadArrayItem copies all ten bytes
-- including the $ff pad tail, so a name's full 10-cell field is asserted,
-- pads and all.
--
-- L/R cycles the cursored slot; the first cycle calls Ot6RageSeed and
-- freezes the AUTO window into the save until Y clears it.  Row 13 carries
-- the mode word and the Y=AUTO control.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/gau_joined.mss.lua"

local ZMENUSTATE, ZCURSOR = 0x26, 0x4b
local ZCHARID = 0x69                    -- zCharID::Slot1..4 (menu_ram.inc)
local RAGE_ROW_COLOR = 0x7e             -- zSkillsTextColor::Rage (menu_ram.inc)
local CHAR_GAU = 0x0b                   -- CHAR::GAU (const.inc)
local RAGES = 0x1D2C                    -- learned-rage bitfield, 32 bytes
local RAGELOAD = 0x1E1F                 -- OT6_RAGELOAD: 8 bytes, id+1, 0 = unset
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_RAGELOAD = 0x05, 0x06, 0x0a, 0x7c
local SKILLS_ROW_RAGE = 5               -- Espers Magic SwdTech Blitz Lore RAGE Dance

local function st() return H.readByte(ZMENUSTATE) end

-- BG1 screen A tilemap shadow (wBG1Tiles::ScreenA = $7e3849, menu_ram.inc):
-- 2 bytes per cell (char, color), 64 bytes per row; cell(x,y) = char byte.
local BG1A = 0x3849
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end

-- menu text codec: 'A'=$80.. 'a'=$9a.. '0'=$b4.. ' '=$ff.
local T = { A=0x80, C=0x82, D=0x83, E=0x84, G=0x86, H=0x87, L=0x8b, M=0x8c,
            N=0x8d, O=0x8e, P=0x8f, R=0x91, S=0x92, T=0x93, U=0x94, W=0x96,
            Y=0x98, DASH=0xc4, SLASH=0xc0, EQ=0xd2, SP=0xff }
local TITLE   = { T.R,T.A,T.G,T.E,T.SP,T.L,T.O,T.A,T.D,T.O,T.U,T.T }  -- RAGE LOADOUT
local LEARNED = { T.L,T.E,T.A,T.R,T.N,T.E,T.D }
local EACH_TX = { T.E,T.A,T.C,T.H }
local HINT    = { T.L,T.SLASH,T.R,T.SP,T.S,T.W,T.A,T.P,T.S }  -- L/R SWAPS
local MODE_AUTO   = { T.A,T.U,T.T,T.O,T.SP,T.SP }
local MODE_MANUAL = { T.M,T.A,T.N,T.U,T.A,T.L }
local MODE_HINT   = { T.Y,T.EQ,T.A,T.U,T.T,T.O }              -- Y=AUTO
local EMPTY_TX = { T.DASH,T.SP,T.E,T.M,T.P,T.T,T.Y,T.SP,T.DASH,T.SP }
local ZERO_CHAR = 0xb4
local MP_SUFFIX = { T.SP, T.M, T.P }
local PAD = 0xff                        -- fixed_length_en.json: 0xFF = {pad}

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

local KNOWN = {}
local gauSlot = nil

local ARM_KNOWN = { 3, 20, 41, 90, 130 }  -- Ninja Ursus Beakor Ghost Zombone

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

-- A row the configurator never draws on must be untouched ($00 from
-- ClearBG1ScreenA).
local function assertRowBlank(y, what)
  for x = 0, 31 do
    H.assertEq(cell(x, y), 0, string.format("%s: cell {%d,%d} blank", what, x, y))
  end
end

-- Two columns of four on odd rows.  An even slot is the left column (name
-- col 3) and an odd slot the right (col 16); row = 5 + (slot & ~1).  The
-- price is stated once on the title row ("8 MP EACH") rather than per row,
-- because two 10-cell names plus two cursor gutters plus two cost fields
-- does not fit inside the window's right border, column 30.
local TITLE_ROW, LEARNED_ROW = 1, 15
local HINT_ROW = 3
local LEFT_COL = 3                      -- the page's left margin (gutter = 1-2)
-- The price field is five cells, "nn MP", rather than four, because it
-- carries a tens place and can reach two digits.
local COST_COL, EACH_COL = 16, 22
local COUNT_COL = 11                    -- just past "LEARNED " at 3..9
local MODE_ROW, MODE_COL, MODE_HINT_COL = 13, 3, 16
local function slotRow(slot) return 5 + (slot & ~1) end
local function slotCol(slot) return (slot % 2 == 0) and LEFT_COL or 16 end

-- `cursor_pos {x, y}` assembles to `.byte x, y`, two bytes per entry, in the
-- framework's index order ($4b = 2*row + col).  It is the top-left of a
-- 16x16 sprite, so entry x owns tilemap columns x/8 and x/8+1 and the slot
-- it points at must start at x/8+2.  y is 116 + n*12 and tilemap row = 2n+1,
-- so the row an entry points at is (y-116)/6 + 1.
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
  for _, x in ipairs({ col, col + 1 }) do
    H.assertEq(cell(x, y), 0, string.format(
      "%s: cursor entry %d sits at x=%d, so tilemap {%d,%d} is under the "
      .. "sprite and must be blank", what, n, cx, x, y))
  end
  H.assertEq(cell(col + 2, y) ~= 0, true, string.format(
    "%s: cursor entry %d at x=%d reserves columns %d-%d, so slot %d must start "
    .. "at column %d (vanilla: cursor_x = 8*col - 16)",
    what, n, cx, col, col + 1, n, col + 2))
  H.assertEq(col + 2, slotCol(n), string.format(
    "%s: cursor entry %d and slot %d's draw column must agree", what, n, n))
  if slotCol(n) == LEFT_COL then
    for x = 0, col + 1 do
      H.assertEq(cell(x, y), 0, string.format(
        "%s: {%d,%d} is left of the cursored row's first glyph (column %d)",
        what, x, y, col + 2))
    end
  end
end

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
-- An unset slot: "- EMPTY - " over exactly the ten name cells.
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

-- The LEARNED counter: three zero-padded digits at COUNT_COL.
local function assertCount(n, what)
  assertRun(COUNT_COL, LEARNED_ROW,
    { ZERO_CHAR + (n // 100), ZERO_CHAR + ((n // 10) % 10), ZERO_CHAR + (n % 10) },
    string.format("%s: LEARNED count = %03d", what, n))
end

-- win[1..8] = the id each slot shows, or nil for empty.
local function assertPage(win, nKnown, what)
  assertRun(LEFT_COL, TITLE_ROW, TITLE, what .. ": title RAGE LOADOUT")
  H.assertEq(cell(COST_COL, TITLE_ROW), PAD,
    what .. ": the trance price is one digit, so its tens cell is blank, not '0'")
  H.assertEq(cell(COST_COL + 1, TITLE_ROW), ZERO_CHAR + 8,
    what .. ": the trance price on the title row is 8 (Dance's number, one authority)")
  assertRun(COST_COL + 2, TITLE_ROW, MP_SUFFIX, what .. ": ' MP' after the price")
  H.assertEq(cell(EACH_COL - 1, TITLE_ROW), 0,
    what .. ": a gap separates the price field from 'EACH' -- without it the "
    .. "title row reads '8 MPEACH' (the #49 failure, on this page's row)")
  assertRun(EACH_COL, TITLE_ROW, EACH_TX, what .. ": 'EACH' -- the price is per trance")
  assertRun(LEFT_COL, HINT_ROW, HINT, what .. ": L/R SWAPS control hint")
  assertRun(LEFT_COL, LEARNED_ROW, LEARNED, what .. ": LEARNED caption")
  assertCount(nKnown, what)

  for slot = 0, 7 do
    if win[slot + 1] then
      assertFilledRow(slot, win[slot + 1])
    else
      assertEmptyRow(slot)
    end
  end

  -- An even tilemap row is shown as three scanlines in this window, so
  -- nothing the page draws may land on one.  Rows past 15 are outside the
  -- window entirely.
  for y = 0, 27 do
    if y % 2 == 0 or y > 15 then
      assertRowBlank(y, string.format(
        "%s: row %d is unusable (%s) and must stay blank", what, y,
        y > 15 and "outside the window" or "even: 3 scanlines"))
    end
  end
  for x = 0, 2 do
    H.assertEq(cell(x, HINT_ROW), 0, string.format(
      "%s: {%d,%d} is the cursor gutter -- the hint starts at column %d",
      what, x, HINT_ROW, LEFT_COL))
  end
  for x = LEFT_COL + #HINT, 31 do
    H.assertEq(cell(x, HINT_ROW), 0,
      string.format("%s: hint row tail blank {%d,%d}", what, x, HINT_ROW))
  end
  for _, x in ipairs({ 0, 1, 2, 15, 21, 26, 27, 28, 29, 30, 31 }) do
    H.assertEq(cell(x, TITLE_ROW), 0,
      string.format("%s: title row gap/tail blank {%d,%d}", what, x, TITLE_ROW))
  end
  for _, x in ipairs({ 0, 1, 2, 10, 14, 15, 29, 30, 31 }) do
    H.assertEq(cell(x, LEARNED_ROW), 0,
      string.format("%s: LEARNED row gap/tail blank {%d,%d}", what, x, LEARNED_ROW))
  end
  for n = 0, 7 do assertCursorGutter(n, what) end
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.worldHasControl() or H.hasControl() end,
    600, "control on the world map", 5),

  H.call(function()
    for id = 0, 254 do
      if (H.readByte(RAGES + (id >> 3)) >> (id & 7)) & 1 == 1 then
        KNOWN[#KNOWN + 1] = id
      end
    end
    local names = {}
    for _, id in ipairs(KNOWN) do names[#names + 1] = id .. ":" .. nameText(id) end
    H.log(string.format("$1d2c as saved: %d rages -- %s", #KNOWN,
      table.concat(names, " ")))
    H.assertEq(#KNOWN >= 9, true,
      "InitRage grants NINE rages at New Game (field/init.asm) and hunting "
      .. "only adds -- fewer than nine means the fixture is not a real save")
    for i = 0, 7 do
      H.assertEq(H.readByte(RAGELOAD + i), 0,
        string.format("OT6_RAGELOAD+%d is $00 AS SAVED -- no real save has "
          .. "configured a loadout, AUTO needs no zeroing", i))
    end
  end),

  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),
  H.call(function()
    local ids = {}
    for s = 0, 3 do
      local id = H.readByte(ZCHARID + s)
      ids[#ids + 1] = string.format("slot %d = char $%02x", s, id)
      if id == CHAR_GAU and gauSlot == nil then gauSlot = s end
    end
    H.log("party: " .. table.concat(ids, ", "))
    H.assertEq(gauSlot ~= nil, true, "gau_joined's party contains GAU")
  end),
  H.pressButtons({ "down" }, 2),            -- Items -> Skills
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.waitFrames(10),
  H.driveUntil(function() return H.readByte(ZCURSOR) == gauSlot end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "cursor onto GAU"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.readByte(RAGE_ROW_COLOR), 0x20,
      "Rage row enabled -- GAU's own record carries the command")
  end),

  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == SKILLS_ROW_RAGE
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "skills cursor to Rage"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_RAGELOAD end, 300,
    "rage configurator open via the player path", 5),
  H.waitFrames(90),                         -- draws + DMA settle

  H.call(function()
    local win = {}
    for s = 1, 8 do win[s] = KNOWN[s] end
    assertPage(win, #KNOWN, "real save")
    for slot = 0, 7 do
      H.assertEq(cell(slotCol(slot), slotRow(slot)) ~= T.DASH, true,
        string.format("slot %d is filled, so it must not draw the empty "
          .. "marker at {%d,%d}", slot, slotCol(slot), slotRow(slot)))
    end
    H.assertEq(#KNOWN > 8, true,
      "the collection exceeds the eight slots, so the count above is counting "
      .. "the bitfield, not the page")
    for i = 0, 7 do
      H.assertEq(H.readByte(RAGELOAD + i), 0,
        string.format("opening the page did not seed OT6_RAGELOAD+%d", i))
    end
    assertModeBlock(true, "opened untouched")
    H.screenshot("rage_page_player_path")
    H.log("RENDER OK: Skills->Rage via the player's path for a REAL GAU -- "
      .. "title, eight slots FULL from InitRage's nine, names against "
      .. "MonsterName verbatim, the flat 8 MP stated once, LEARNED counting "
      .. "the whole collection; nothing on an even row, nothing past row 15, "
      .. "nothing in the border column, nothing in either cursor's gutter")
  end),

  H.pressButtons({ "r" }, 3),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(H.readByte(RAGELOAD + 0), KNOWN[2] + 1,
      "R cycled slot 0 to the next learned rage (stored byte = id + 1)")
    for i = 2, 8 do
      H.assertEq(H.readByte(RAGELOAD + i - 1), KNOWN[i] + 1,
        string.format("the first edit froze AUTO's window into slot %d", i - 1))
    end
    assertFilledRow(0, KNOWN[2])
    assertModeBlock(false, "after the first edit")
    H.assertEq(H.readByte(ZMENUSTATE), ST_RAGELOAD, "still on the rage page")
    H.screenshot("rage_page_after_cycle")
    H.log("LIVE: R redrew slot 0 as '" .. nameText(KNOWN[2])
      .. "' , the first edit froze the AUTO window into the save bytes, and the "
      .. "mode indicator followed it from AUTO to MANUAL in the same frame")
  end),

  H.pressButtons({ "y" }, 3),
  H.waitFrames(40),
  H.call(function()
    for i = 0, 7 do
      H.assertEq(H.readByte(RAGELOAD + i), 0,
        string.format("Y cleared OT6_RAGELOAD+%d: the loadout is AUTO again", i))
    end
    assertModeBlock(true, "after Y")
    for i = 1, 8 do assertFilledRow(i - 1, KNOWN[i]) end
    H.screenshot("rage_page_reverted")
    H.log("REVERT: Y put the page back on AUTO -- the eight bytes are zero, the "
      .. "window is recomputed, and 'MANUAL' left nothing of itself behind in "
      .. "the six-cell field")
  end),

  H.pressButtons({ "r" }, 3),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(H.readByte(RAGELOAD + 0), KNOWN[2] + 1,
      "back to MANUAL with slot 0 on the second known species, as before Y")
    assertModeBlock(false, "re-edited after the revert")
  end),

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

  H.pressButtons({ "y" }, 3),               -- the page's own revert, not a write
  H.waitFrames(20),
  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_SKILLS end, 300,
    "back out of the rage configurator", 5),
  H.call(function()
    for i = 0, 7 do
      H.assertEq(H.readByte(RAGELOAD + i), 0,
        "Y left OT6_RAGELOAD+" .. i .. " at $00 -- nothing to zero by hand")
    end
    teach(ARM_KNOWN)                        -- THE arm's write (see header)
    H.log("[isolation arm] $1d2c := five species -- below the InitRage floor, "
      .. "a collection no real save can hold")
  end),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_RAGELOAD end, 300,
    "rage configurator reopened with five species", 5),
  H.waitFrames(90),

  H.call(function()
    local win = {}
    for i = 1, #ARM_KNOWN do win[i] = ARM_KNOWN[i] end
    assertPage(win, #ARM_KNOWN, "isolation arm, AUTO")
    for i = 0, 7 do
      H.assertEq(H.readByte(RAGELOAD + i), 0,
        string.format("opening the page did not seed OT6_RAGELOAD+%d", i))
    end
    assertModeBlock(true, "isolation arm, AUTO")
    H.screenshot("rage_page_empty_marker")
    H.log("ISOLATION ARM (AUTO cause): five species -- slots 5-7 read "
      .. "'- EMPTY -', the count reads 005, and the page still wrote nothing")
  end),

  H.pressButtons({ "r" }, 3),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(H.readByte(RAGELOAD + 0), ARM_KNOWN[2] + 1,
      "R cycled slot 0 to the next learned rage (stored byte = id + 1)")
    for i = 2, #ARM_KNOWN do
      H.assertEq(H.readByte(RAGELOAD + i - 1), ARM_KNOWN[i] + 1,
        string.format("the first edit froze AUTO's window into slot %d", i - 1))
    end
    for i = #ARM_KNOWN, 7 do
      H.assertEq(H.readByte(RAGELOAD + i), 0,
        string.format("slot %d had no window entry to freeze, stays unset", i))
    end
    assertFilledRow(0, ARM_KNOWN[2])
    for slot = #ARM_KNOWN, 7 do assertEmptyRow(slot) end
    assertModeBlock(false, "isolation arm, after the first edit")
    H.screenshot("rage_page_manual_empty")
    H.log("ISOLATION ARM (MANUAL cause): the freeze stopped at the window's "
      .. "end, the $00 tails still read '- EMPTY -', and the mode says MANUAL")
  end),
})
