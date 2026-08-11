-- @suite savestate=gau_joined
-- menu_ragepage.lua -- issue #40: the field Skills->Rage loadout page renders.
--
-- The page (MenuState_7c and Ot6Rage* in ot6_kits.asm, the C3 shim at
-- field_menu.asm:2907-3075) was wired, assembled and shipped without one
-- rendered cell ever being asserted.  That is the gap issue #39 fell
-- through on the SwdTech configurator: menu_bushidoloadout force-jumped
-- zMenuState and asserted only stored bytes, so a page whose every label
-- streamed the ending-credits charmap into the tilemap stayed green.  This
-- test treats the Rage page the way menu_swdtechpage treats its page:
--
--   * path: it drives the real UI (X -> Skills -> character -> the Rage row
--     -> A) so SkillsOption_05 (field_menu.asm:1327-1348) opens the
--     configurator rather than a forced state;
--   * render: it asserts the BG1A tilemap shadow cell by cell (the title,
--     each slot's monster name, the flat "8 MP" cost suffix, the LEARNED
--     caption and its three-digit count) and also that every
--     row the page never draws on is still all-zero, which a runaway
--     unterminated draw cannot leave blank.
--
-- Issue #75 conversion: a real Gau, and the InitRage floor.  This file used
-- to stage everything onto arvis_wake's lead: the Rage command, a hand-picked
-- learned bitfield, and zeroed loadout bytes.  It now boots gau_joined, the
-- input-driven post-join savestate on the world map with CYAN, SABIN and GAU,
-- finds Gau in zCharID, and reads everything off his save:
--   * the Rage command is his record's own;
--   * the learned set is `InitRage` (field/init.asm InitRage table): nine
--     rages at New Game, ids 11, 14, 19, 21, 25, 46, 54, 57, 66, and
--     hunting only adds, so >= 9 is a floor for every real save and is
--     asserted as one.  The expected names are still read out of the ROM's
--     MonsterName records, now for ids taken from the save's own bitfield;
--   * the loadout bytes are $00 as saved (no real save has configured a
--     loadout), so AUTO needs no zeroing and the revert is driven with the
--     page's own Y command rather than a write.
-- The nine-rage floor makes the page full from its first open: AUTO's window
-- always fills all eight slots, and the LEARNED count (009) exceeding the
-- eight drawn is now asserted on the first render.  That is the claim that the
-- count counts the whole bitfield rather than the slots, which the old test
-- needed a second, staged visit to make.
--
-- One labeled isolation arm (issue #75): one write site stays.
-- The "- EMPTY -" marker (#44) is unreachable by play, in both of its
-- documented causes: AUTO shows an empty slot only below eight known rages,
-- and InitRage's floor is nine; MANUAL shows one only for a stored $00 byte,
-- and Ot6RageCycleCore can only store a learned id + 1.  A renderer
-- state no controller can produce is a mechanism claim (burn-down plan
-- systemic call 2), so the marker's assertions live in a labeled tail
-- arm that writes the $1d2c bitfield down to five species, which is the one
-- write this file keeps its .writeByte( waiver line for.  It may never produce
-- fixtures.  (Follow-up filed in the conversion report: given the floor, the
-- marker may be permanently unreachable UI.)
--
-- The 12-pixel cadence (found by this test's first run, and the reason the
-- page's layout changed).  The tilemap was correct; what was wrong was
-- where on it the page drew.  The EN field-menu window does not show BG1
-- ScreenA one tile row per eight scanlines: a row pair occupies twelve
-- scanlines, the odd row getting eight and the even row four, and nothing past
-- row 15 is inside the window at all (measured with a glyph drawn in every
-- row, probe_ragegeom.lua; vanilla's own cursor tables say the same from the
-- other side, since every EN list for this window is
-- `cursor_pos {x, 116 + n*12}`, skills.asm:125-126, and DrawRageName biases
-- its row `.if LANG_EN`, skills.asm:1571-1574).  The page shipped with eight
-- slots on even rows 4..18 and LEARNED on row 20, so through the player's path
-- every beast name rendered as a three-scanline sliver and the collection
-- counter was off the bottom of the window.  It now draws two columns of four
-- on odd rows 5/7/9/11 with LEARNED on 15, which is vanilla's shape for this
-- window.  Hence the even-row canary below: it is the regression check.
--
-- The cursor gutter (#43 round 3) is the same cadence story in x.  The cursor
-- is a 16x16 sprite and `cursor_pos {x,y}` is its top-left corner, so an entry
-- at x owns tilemap columns x/8 and x/8+1 and the row it points at must start
-- at x/8+2.  Vanilla's arithmetic is cursor_x = 8*col - 16 everywhere in this
-- window: magic draws at cols 3/16 under cursors 8/112 (skills.asm:831, :836 vs
-- :125-126), espers at 3/17 under 8/120 (:1733, :1737 vs :249-250), rage at
-- 5/19 under 24/136 (:1544, :1548 vs :292-293), and config's value column 14
-- under 96 (config.asm:50); measured the same way on the shipped ROM, where the
-- magic list's `cursor_pos {8, 116}` lights screen x 8..23, y 116..131
-- (tools/tests/probe_menucols.lua).  This page's right column was already
-- correct, since col 16 under x=112 is vanilla's magic pair, but its left
-- column drew at col 2 under x=8, so the sprite covered the first letter of
-- every left-hand beast name.  The left column is 3 now; the cursor table did
-- not move.  The cursor gutter canary below reads Ot6RageCursorPos out of the
-- ROM and checks both halves against the tilemap, so neither can move alone.
-- It is duplicated from menu_swdtechpage.lua rather than shared: the only lua
-- the runner inlines is lib/ot6{,_field,_contract}.lua, and those three files
-- are the savestate generation signature (lib/savestate_stamp.sh:82-85), so a
-- helper added there would mark every generated fixture drifted.
--
-- The name source, and why it is not the SwdTech one.  Ot6DrawRageName
-- (field_menu.asm:2992-3016) calls GetMonsterNamePtr (skills.asm:1557-1565),
-- which points LoadArrayItem at MonsterName, a 384-entry, 10-byte fixed
-- record table (include/text/monster_name_en.inc:13-14), rather than
-- BushidoName or any spell table.  So the expected bytes are read out of the
-- ROM's own MonsterName records at runtime (H.sym and readRomByte): the
-- assertion is against the bytes the drawing code streams, and a text
-- re-encode cannot invalidate a hardcoded literal here without being noticed.
-- LoadArrayItem copies all ten bytes including the $ff pad tail
-- (item.asm:1255-1276), so a name's full 10-cell field is asserted, pads and
-- all.
--
-- issue #44: the control hint and the empty marker.  Two owner-playtest
-- findings on a page that already rendered correctly.  L/R cycling the
-- cursored slot is the page's only real interaction and nothing named it, and
-- an unset slot was a run of $ff pads, which reads as a rendering bug rather
-- than as "you have not hunted eight species yet".  Row 3 was spare (the page
-- draws on 1/5/7/9/11/15), so the hint cost only that row, and the marker
-- replaces the pad fill over the same ten cells.
-- issue #49: the mode block.  All eight bytes zero is AUTO: the game
-- picks the first eight species in id order and keeps re-picking as Gau
-- hunts, and the first cycle calls Ot6RageSeed and freezes that window into
-- the save until Y clears it.  Row 13 carries the mode word and
-- the Y=AUTO control, worded identically to the Bushido page's, per the #44
-- rule that one idiom gets one wording so a player does not have to learn it
-- twice.
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
-- shipped without saying so; a player who learns the idiom on one should not
-- have to re-learn it on the other, so the strings are asserted to be equal by
-- being written out identically in both tests.
local HINT    = { T.L,T.SLASH,T.R,T.SP,T.S,T.W,T.A,T.P,T.S }  -- L/R SWAPS
-- #49: both mode words are six cells, "AUTO" space-padded, so a MANUAL to
-- AUTO revert overwrites the whole field; asserted as an equality below
-- rather than assumed.  Written out character for character in both page
-- tests on purpose, per the #44 rule.
local MODE_AUTO   = { T.A,T.U,T.T,T.O,T.SP,T.SP }
local MODE_MANUAL = { T.M,T.A,T.N,T.U,T.A,T.L }
local MODE_HINT   = { T.Y,T.EQ,T.A,T.U,T.T,T.O }              -- Y=AUTO
-- #44: what an unset slot draws, in place of a run of $ff pads.  Exactly
-- MonsterName::ITEM_SIZE (10) cells, so it still overwrites a name completely
-- and a revert clears what was there, which is the property the pad fill had.
local EMPTY_TX = { T.DASH,T.SP,T.E,T.M,T.P,T.T,T.Y,T.SP,T.DASH,T.SP }
local ZERO_CHAR = 0xb4
local MP_SUFFIX = { T.SP, T.M, T.P }
local PAD = 0xff                        -- fixed_length_en.json: 0xFF = {pad}

-- MonsterName, read out of the ROM the drawing code reads.
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

-- The save's own collection, derived at boot: KNOWN is every learned id in
-- ascending order, and AUTO's window is its first eight.
local KNOWN = {}
local gauSlot = nil

-- The isolation arm's five species (the old staged set), spread over several
-- bitfield bytes and short of eight so the marker has slots to appear in.
local ARM_KNOWN = { 3, 20, 41, 90, 130 }  -- Ninja Ursus Beakor Ghost Zombone

-- teach() survives only for the labeled isolation arm at the tail.
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

-- A row the configurator never draws on must be untouched
-- ($00 from ClearBG1ScreenA).  #39's runaway draws filled BG1A with ROM code
-- bytes, so every one of these would fail on a garbled page.
local function assertRowBlank(y, what)
  for x = 0, 31 do
    H.assertEq(cell(x, y), 0, string.format("%s: cell {%d,%d} blank", what, x, y))
  end
end

-- Page geometry, mirroring field_menu.asm's Ot6RageDrawSlots: two columns of
-- four on odd rows.  An even slot is the left column (name col 3) and an odd
-- slot the right (col 16); row = 5 + (slot & ~1).  {3, 16} under cursors
-- {8, 112} is vanilla's magic list unchanged; see the cursor-gutter note in
-- the header.  The price is stated once on the title row ("8 MP EACH") rather
-- than per row, because two 10-cell names plus two cursor gutters plus two
-- cost fields does not fit inside the window's right border, which is column
-- 30 (measured at screen x = 245).  The price is flat by design, so one copy
-- states the same rule.
local TITLE_ROW, LEARNED_ROW = 1, 15
local HINT_ROW = 3                      -- #44: row 3 was spare; the hint has it
local LEFT_COL = 3                      -- the page's left margin (gutter = 1-2)
-- #56: the price field is five cells, "nn MP", rather than four, because
-- Ot6LoadoutDrawCost is the one price drawer in the field menu now and it
-- carries a tens place.  It moved left (17 -> 16) rather than growing
-- rightwards, because "EACH" is a fixed pos_text at 22 and a five-cell field
-- starting at 17 would have rendered "8 MPEACH".  This page's number is 8
-- today and can reach two digits without anyone editing it: Ot6RageCost
-- tail-calls Ot6DanceCost (ot6_boost.asm:600-619) on purpose, and
-- mp-economy.md's range for a flat possess-verb price is 4-10.
local COST_COL, EACH_COL = 16, 22
local COUNT_COL = 11                    -- just past "LEARNED " at 3..9
local MODE_ROW, MODE_COL, MODE_HINT_COL = 13, 3, 16
local function slotRow(slot) return 5 + (slot & ~1) end
local function slotCol(slot) return (slot % 2 == 0) and LEFT_COL or 16 end

-- The cursor gutter canary (#43 round 3).  Both sides are read, not written:
-- the cursor table comes out of the ROM the menu itself indexes, and the text
-- comes out of the tilemap the menu itself drew.
--
-- `cursor_pos {x, y}` assembles to `.byte x, y` (menu_ram.inc:582-584), two
-- bytes per entry, in the framework's index order ($4b = 2*row + col).  It is
-- the top-left of a 16x16 sprite, so entry x owns tilemap columns x/8 and
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
  -- the two columns under the sprite carry no glyph ...
  for _, x in ipairs({ col, col + 1 }) do
    H.assertEq(cell(x, y), 0, string.format(
      "%s: cursor entry %d sits at x=%d, so tilemap {%d,%d} is under the "
      .. "sprite and must be blank", what, n, cx, x, y))
  end
  -- ... and the slot it points at begins in the next one.  An unfilled
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

-- #49: row 13, asserted as a whole row: the mode word, the control, and every
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
-- An unset slot (#44): "- EMPTY - " over exactly the ten name cells, so the
-- overwrite property is unchanged and the row says what it means.  It is
-- reachable only through the isolation arm now; see the header.
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

-- The shared chrome and geometry sweep, parameterized by how many of the eight
-- slots are filled and with which ids (win[1..8], nil = empty).
local function assertPage(win, nKnown, what)
  assertRun(LEFT_COL, TITLE_ROW, TITLE, what .. ": title RAGE LOADOUT")
  -- the flat price, stated once: "8 MP EACH" on the title row.  #56: five
  -- cells, right-aligned, with the tens cell blank for a one-digit price and
  -- never '0' (vanilla's own rule: HexToDec3 overwrites leading zeroes
  -- with $ff, menu_common.asm:906-918).
  H.assertEq(cell(COST_COL, TITLE_ROW), PAD,
    what .. ": the trance price is one digit, so its tens cell is blank, not '0'")
  H.assertEq(cell(COST_COL + 1, TITLE_ROW), ZERO_CHAR + 8,
    what .. ": the trance price on the title row is 8 (Dance's number, one authority)")
  assertRun(COST_COL + 2, TITLE_ROW, MP_SUFFIX, what .. ": ' MP' after the price")
  H.assertEq(cell(EACH_COL - 1, TITLE_ROW), 0,
    what .. ": a gap separates the price field from 'EACH' -- without it the "
    .. "title row reads '8 MPEACH' (the #49 failure, on this page's row)")
  assertRun(EACH_COL, TITLE_ROW, EACH_TX, what .. ": 'EACH' -- the price is per trance")
  -- #44: the control hint, on the one spare row above the slots
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

  -- The even-row canary, the regression this test exists for.  An even
  -- tilemap row is shown as three scanlines in this window, so nothing the
  -- page draws may land on one.  Rows past 15 are outside the window
  -- entirely, so nothing may land there either.  Both were violated before
  -- (slots on 4..18, LEARNED on 20), and a plain tilemap assertion could
  -- not see it; only the geometry rule can.
  for y = 0, 27 do
    if y % 2 == 0 or y > 15 then
      assertRowBlank(y, string.format(
        "%s: row %d is unusable (%s) and must stay blank", what, y,
        y > 15 and "outside the window" or "even: 3 scanlines"))
    end
  end
  -- the hint row's own head and tail, so the hint cannot grow into the cursor
  -- gutter on its left or the window border on its right.  The hint runs
  -- 3..11; everything else on row 3 is blank.
  for x = 0, 2 do
    H.assertEq(cell(x, HINT_ROW), 0, string.format(
      "%s: {%d,%d} is the cursor gutter -- the hint starts at column %d",
      what, x, HINT_ROW, LEFT_COL))
  end
  for x = LEFT_COL + #HINT, 31 do
    H.assertEq(cell(x, HINT_ROW), 0,
      string.format("%s: hint row tail blank {%d,%d}", what, x, HINT_ROW))
  end
  -- the gaps on the title row, its head and its tail: nothing may sit left
  -- of the page's margin (columns 0-2, the cursor's own gutter) and nothing
  -- may run into the window's right border, which lives in column 30.
  -- "RAGE LOADOUT" occupies 3..14, the price 16..20 (#56: five cells, its
  -- leading one blank at this price), EACH 22..25.
  for _, x in ipairs({ 0, 1, 2, 15, 21, 26, 27, 28, 29, 30, 31 }) do
    H.assertEq(cell(x, TITLE_ROW), 0,
      string.format("%s: title row gap/tail blank {%d,%d}", what, x, TITLE_ROW))
  end
  -- and the same for the LEARNED row: caption 3..9, count 11..13.
  for _, x in ipairs({ 0, 1, 2, 10, 14, 15, 29, 30, 31 }) do
    H.assertEq(cell(x, LEARNED_ROW), 0,
      string.format("%s: LEARNED row gap/tail blank {%d,%d}", what, x, LEARNED_ROW))
  end
  -- The cursor gutter canary, on every slot: filled rows and $ff-blanked ones.
  for n = 0, 7 do assertCursorGutter(n, what) end
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.worldHasControl() or H.hasControl() end,
    600, "control on the world map", 5),

  -- The save's own state, read: derive the collection, assert the InitRage
  -- floor, and prove the loadout has never been configured.
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

  -- the player's path: X -> main menu -> Skills -> GAU -> the Rage row -> A.
  -- This uses driveUntil rather than one press because the X that opens the
  -- field menu is the first step in these tests that needs a specific frame,
  -- so it is where a fixture generated against a different ROM shows up, as
  -- "timeout waiting for main menu", which reads like a menu bug and is not
  -- one.  Retrying the press costs nothing when the pairing is fine and
  -- removes the false report when it is not.  This is the shape
  -- probe_fieldicons.lua and menu_blitzpage_sabin.lua already use.
  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),
  -- Find Gau rather than assume his row.
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

  -- cursor down to the Rage row, A opens the configurator through
  -- SkillsOption_05, the edge no test had driven before.
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == SKILLS_ROW_RAGE
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "skills cursor to Rage"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_RAGELOAD end, 300,
    "rage configurator open via the player path", 5),
  H.waitFrames(90),                         -- draws + DMA settle

  -- ---- the full page every real Gau opens: AUTO's window = KNOWN[1..8] ----
  H.call(function()
    local win = {}
    for s = 1, 8 do win[s] = KNOWN[s] end
    assertPage(win, #KNOWN, "real save")
    -- the marker appears nowhere: a filled slot starts with a name's first
    -- letter, never the marker's leading dash.  That was the old staged
    -- full-page phase's final check, and it is now true of the first render.
    for slot = 0, 7 do
      H.assertEq(cell(slotCol(slot), slotRow(slot)) ~= T.DASH, true,
        string.format("slot %d is filled, so it must not draw the empty "
          .. "marker at {%d,%d}", slot, slotCol(slot), slotRow(slot)))
    end
    -- and the count exceeds the slots: #KNOWN >= 9 > 8, so this render
    -- alone shows LEARNED counts the whole bitfield rather than the loadout.
    H.assertEq(#KNOWN > 8, true,
      "the collection exceeds the eight slots, so the count above is counting "
      .. "the bitfield, not the page")
    -- opening the page writes nothing: AUTO is computed per slot on the fly
    -- (Ot6RageShow), so an un-edited page leaves every save byte at zero.
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

  -- ---- the page redraws rather than drawing once: R cycles the slot ------
  -- The first edit out of AUTO freezes the window into the eight bytes
  -- (Ot6RageSeed) and then walks the bitfield, so slot 0 must move from the
  -- first known species to the second and the row must redraw to match.
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
    -- #49: and the page must say it went manual, on this same redraw and
    -- without being reopened.  A mode drawn once at page-init would still read
    -- AUTO here, which is the failure this assertion exists for.
    assertModeBlock(false, "after the first edit")
    H.assertEq(H.readByte(ZMENUSTATE), ST_RAGELOAD, "still on the rage page")
    H.screenshot("rage_page_after_cycle")
    H.log("LIVE: R redrew slot 0 as '" .. nameText(KNOWN[2])
      .. "' , the first edit froze the AUTO window into the save bytes, and the "
      .. "mode indicator followed it from AUTO to MANUAL in the same frame")
  end),

  -- ---- #49: Y reverts, and the indicator comes back with it ----
  -- The revert is the half a player cannot guess, which is why the control is
  -- named on screen, and it is the half that shows the two mode words are the
  -- same width: a five-cell "AUTO " would leave MANUAL's trailing L behind.
  -- Ot6RageInput's Y arm zeroes all eight bytes (ot6_kits.asm), so the window
  -- goes back to being computed on the fly and the first eight known species
  -- must re-appear in id order exactly as they did on entry.
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

  -- put the page back into MANUAL for the phases below, which assert on the
  -- frozen bytes R wrote.  (Re-cycling slot 0 lands on the same species the
  -- first edit did, because the walk is deterministic from the same starting
  -- point.)
  H.pressButtons({ "r" }, 3),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(H.readByte(RAGELOAD + 0), KNOWN[2] + 1,
      "back to MANUAL with slot 0 on the second known species, as before Y")
    assertModeBlock(false, "re-edited after the revert")
  end),

  -- ---- the second column is reachable and maps to the right slot ----
  -- Two columns only exist because the window has eight text rows; the
  -- cursor index is $4b = 2*row + col, so dpad-right from slot 0 must land on
  -- slot 1, the row-5 right cell, and R must edit that byte and no other.
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

  -- ---- and a lower row, so the shipped screenshots cover more than row 5 --
  -- The canary above reads the whole cursor table, but only the row the sprite
  -- is parked on shows up in a picture.  Walk back to the left column, the
  -- half that moved, and down to slot 4, so the shot shows the cursor
  -- next to a name.
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

  -- ======================================================================= --
  -- Labeled isolation arm (issue #75, the renderer-mechanism rule).
  -- The "- EMPTY -" marker, in both its documented causes, neither of which
  -- a controller can produce (see header: InitRage's nine-rage floor rules out
  -- the AUTO cause, and Ot6RageCycleCore only stores learned ids, which rules
  -- out the MANUAL cause).  The one write sets the $1d2c bitfield to
  -- five species.  The loadout bytes are not written: Y is pressed first so
  -- the page's own revert leaves them $00, which is asserted.
  -- ======================================================================= --
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
    -- AUTO with five known: slots 0-4 carry the five, slots 5-7 the marker.
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

  -- and the MANUAL cause: the first R freezes only the five-slot window
  -- (Ot6RageSeed stops when the window runs out), leaving stored $00 tails
  -- that Ot6RageList skips, and the marker must read the same over them.
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
