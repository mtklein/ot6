-- @suite savestate=magicite_ifrit_shiva
-- menu_esperdetail.lua -- issue #27, rebuilt for #62: the esper detail page
-- shows the while-worn stat block and never the dead learn-rate columns.
--
-- M5 made espers while-equipped sub-jobs: every GenjuProp learn rate is 0 and
-- every level-up bonus byte is $ff (ff6/src/menu/genju_prop.asm), but the
-- vanilla esper detail page (skills.asm DrawEsperDetailMenu) still drew the
-- "Learn.Rate"/"Skill" captions, a ":  {times}00" rate after every spell, a
-- "  0%" skill column, and a blank bonus line, so Ifrit's vigor bonus
-- (Ot6EsperStatTbl, ff6/src/battle/ot6_progression.asm) was invisible in
-- game.  #27 drew the spell names bare and put one line, "While worn...<stat>
-- +<n>", where the dead bonus line had been.
--
-- #62 widened the table and this page with it.  Ot6EsperStatTbl is now two
-- bytes per esper in vanilla's own equipment layout, four signed nibbles of
-- -7..+7 each, so a stone carries up to four deltas and any of them can be
-- negative.  Four terms do not fit on one line, so the page draws a right-hand
-- column: the caption rides the title row (in the cells vanilla used for
-- its Learn.Rate and Skill captions and #27 blanked), and one term per nonzero
-- delta packs downward from row 17.
--
-- Issue #75 conversion: the stones are owned rather than poked.  This file used
-- to boot arvis_wake (which owns no espers) and write the $1a69 inventory
-- bitfield directly to stage IFRIT and TERRATO.  It now boots
-- magicite_ifrit_shiva, the input-driven v0.6 savestate whose bag
-- holds RAMUH, IFRIT and SHIVA (gen_ifrit_magicite: give_genju receipts,
-- $1A69 = $07), and asserts the pages of all three, with no state writes.
-- What each owned stone gives the test:
--   IFRIT  (+6 vigor / +4 stamina / -3 mag.pwr), the row
--          magicite-ifrit-shiva.md's ledger recorded as unbuildable under
--          the old encoding: three terms, speed skipped (which exercises the
--          packing), and a minus sign.  Every assertion of the old Ifrit page
--          is unchanged.
--   SHIVA  (-3 vigor / +4 speed / +6 mag.pwr), Ifrit's authored mirror:
--          three terms again but with stamina skipped (a middle zero costs no
--          line) and the minus leading the block.  Visited right after Ifrit,
--          her slot-1 term must read "Speed" where his read "Stamina", which
--          is the revisit-overwrites check the old TERRATO page made, now made
--          with content rather than with blankness.
--   RAMUH  (+4 stamina / +2 mag.pwr), the two-term shape: the walk must
--          skip two leading zeros (vigor, speed) before its first term, and,
--          visited after two three-term pages, its row-17+2*2 slot must
--          be blanked, which shows the page clears a term row the previous
--          stone filled.  That is the other half of what the Terrato page
--          covered.
-- What no owned stone can show: the no-mod page (Ot6EsperStatTbl $0000, with
-- no caption at all).  Terrato, the authored no-mod control, is not in any
-- reachable bag as far as the game is playable; that arm lives on as
-- menu_esperdetail_tube6.lua's labeled isolation arm.
--
-- The assertions that changed in #62, and why; they were changed rather than
-- loosened:
--   * cell(13,15) was asserted blank (no Learn.Rate caption); it is now the
--     left pad of the caption field, and the caption's own 'W' is asserted at
--     {15,15} with {13,15} and {14,15} still blank.  What that check existed
--     to catch, vanilla's caption text coming back, is now covered by
--     asserting the exact tiles that are there.
--   * cell(16,17) and cell(26,17)/cell(27,17) were asserted blank (no
--     "{times}NN" rate, no percent digits, no percent sign).  Cols 26/27 of row
--     17 now hold a term's magnitude digits.  The percent sign at {27,17} is
--     replaced by an exact-value assertion on the digit; the rate colon at
--     {12,17}, which nothing draws to, stays a blank assertion, and a new
--     no-percent-glyph sweep replaces the two cells that moved.
--   * the single line at row 27 is gone, so row 27 is now asserted blank for
--     every stone, including the stones with a mod, which is a new
--     check: #27's own line lived there, so nothing could previously check that
--     region gets cleared on a page that has something to say.
--
-- This test drives the real menu UI (X -> Skills -> character -> Espers ->
-- list -> detail) from the magicite_ifrit_shiva fixture.  Rendering is
-- asserted at cell level in the BG1 screen-B tilemap shadow the menu draws
-- into (wBG1Tiles::ScreenB = $7e4049, ff6-en.dbg; 2 bytes per cell, char then
-- color, 64 bytes per row) and recorded with screenshots of the pages.
--
-- Layout, from skills.asm's DrawEsperDetailMenu tail:
--   caption "While worn..." right-aligned in the 16-cell field at {13,15}:
--     cols 13-14 blank, cols 15-27 the 13 caption tiles, col 28 blank
--   one term per nonzero delta, packed downward from tilemap row 17 over the
--   odd rows 17/19/21/23/25 (one window row = two tilemap rows):
--     stat name cols 17-23 (7 tiles, Ot6GenjuStatNameTbl, space-padded)
--     a spacer at col 24: "Stamina" and "Mag.Pwr" fill all seven name cells,
--       so without it the sign sits flush against the label
--     sign col 25: '+' $ca or '-' $c4
--     magnitude cols 26-27, leading zero blanked
--   every term row the walk does not reach: cols 17-27 blank
--   row 27, where #27's single line used to be: cols 5-27 blank
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/magicite_ifrit_shiva.mss.lua"

local ZMENUSTATE = 0x26                 -- menu direct-page vars (menu_ram.inc)
local ZLISTTYPE  = 0x2a
local ZCURSOR    = 0x4b
local Z99        = 0x99                 -- detail page's esper index
local SKILLCOLOR = 0x79                 -- zSkillsTextColor[0] = Espers row
local ESPERS     = 0x1a69               -- owned-esper bitfield, 27 bits (READ)
local GENJULIST  = 0x9d89               -- $7e9d89: list row -> esper index
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LIST, ST_DETAIL = 0x05, 0x06, 0x0a, 0x1e, 0x4d

local RAMUH, IFRIT, SHIVA = 0, 1, 2

-- BG1 screen B tilemap shadow: char byte of the cell at tile (x, y).
local BG1B = 0x4049
local function cell(x, y) return H.readByte(BG1B + x * 2 + y * 64) end

-- Menu text codec bytes asserted below (ff6/tools/char_table/text_en.json).
local CH_W, CH_COLON, CH_PCT = 0x96, 0xc1, 0xcd
local CH_PLUS, CH_MINUS, CH_DOT = 0xca, 0xc4, 0xc5
local BLANK = 0xff
local function digit(n) return 0xb4 + n end      -- '0' = $b4 .. '9' = $bd

-- Stat name tiles, copied from menu_text_en.inc.raw:111-114 (7 tiles each,
-- space-padded with $ff, the terminator dropped).  Spelled out rather than read
-- from the ROM, so that a table that moved could not make this test agree
-- with itself.
local STAT = {
  VIGOR   = { 0x95, 0xa2, 0xa0, 0xa8, 0xab, 0xff, 0xff },   -- "Vigor  "
  SPEED   = { 0x92, 0xa9, 0x9e, 0x9e, 0x9d, 0xff, 0xff },   -- "Speed  "
  STAMINA = { 0x92, 0xad, 0x9a, 0xa6, 0xa2, 0xa7, 0x9a },   -- "Stamina"
  MAGPWR  = { 0x8c, 0x9a, 0xa0, 0xc5, 0x8f, 0xb0, 0xab },   -- "Mag.Pwr"
}

local function st() return H.readByte(ZMENUSTATE) end


-- Walk the esper list cursor down to the row holding esper `idx`.
-- Walk the esper list cursor onto the slot holding esper `idx`.  The list is
-- a two-column grid (GenjuCursorProp `cursor_prop {0,0},{2,8}`, skills.asm):
-- $4b is a linear slot index whose parity is the column, so down/up move by
-- 2 and a parity change needs a left/right press first.  Direction-aware
-- because the slot the list restores after a detail-page exit is not
-- reliably the slot it left from.  4-frames-on/4-off gives clean press
-- edges.
local function listSeek(idx, what)
  local ph = 0
  return H.driveUntil(function()
    return st() == ST_LIST and H.readByte(GENJULIST + H.readByte(ZCURSOR)) == idx
  end, 3000, {
    H.call(function()
      ph = (ph + 1) % 8
      if ph >= 4 then H.setPad({}); return end
      local target
      for r = 0, 26 do
        if H.readByte(GENJULIST + r) == idx then target = r; break end
      end
      if not target then H.setPad({}); return end
      local row = H.readByte(ZCURSOR)
      local d = target - row
      if d % 2 ~= 0 then                -- wrong column: fix parity first
        if row % 2 == 0 then
          H.setPad(row >= 26 and { up = true } or { right = true })
        else
          H.setPad({ left = true })
        end
      else
        H.setPad(d > 0 and { down = true } or { up = true })
      end
    end),
    H.waitFrames(1),
  }, what)
end

-- The shared page shape: vanilla's dead learn-rate drawing is gone.  #62 took
-- over cols 17-27 of the spell rows and cols 13-28 of the title row, so the
-- three cells the old version of this check used there have been replaced with
-- checks of the same kind that survive the new layout:
--   * col 12 of a spell row is where vanilla's rate colon sat, and nothing in
--     the OT6 page draws there, so it stays a blank assertion;
--   * the percent glyph $cd (the "0%" column's sign) must not appear anywhere
--     in the window's rows.  That is a stronger statement than the two cells it
--     replaces, and it cannot be satisfied by accident;
--   * the rate colon glyph $c1 likewise must not appear anywhere in the window.
local function assertDeadColumnsGone(tag)
  H.assertEq(cell(12, 17), BLANK, tag .. ": no rate colon after spell 1's name")
  for y = 15, 27, 2 do
    for x = 0, 31 do
      H.assertEq(cell(x, y) ~= CH_PCT, true,
        string.format("%s: no percent glyph anywhere in the window {%d,%d}", tag, x, y))
      H.assertEq(cell(x, y) ~= CH_COLON, true,
        string.format("%s: no learn-rate colon anywhere in the window {%d,%d}", tag, x, y))
    end
  end
end

-- ---- #62: the while-worn stat block ----------------------------------------

-- The caption field at {13,15}: 2 blanks, then "While worn..." on cols 15-27.
-- (The `present = false` arm, the no-mod page, is exercised by
-- menu_esperdetail_tube6.lua's labeled Terrato isolation arm; no stone this
-- save owns carries a $0000 row.)
local function assertCaption(tag, present)
  if present then
    H.assertEq(cell(13, 15), BLANK, tag .. ": caption field pad blank at {13,15}")
    H.assertEq(cell(14, 15), BLANK, tag .. ": caption field pad blank at {14,15}")
    H.assertEq(cell(15, 15), CH_W, tag .. ": 'While worn...' starts at {15,15}")
    H.assertEq(cell(25, 15), CH_DOT, tag .. ": caption ellipsis at {25,15}")
    H.assertEq(cell(26, 15), CH_DOT, tag .. ": caption ellipsis at {26,15}")
    H.assertEq(cell(27, 15), CH_DOT, tag .. ": caption ends at {27,15}")
  else
    for x = 13, 28 do
      H.assertEq(cell(x, 15), BLANK,
        string.format("%s: no caption at all -- {%d,15} blank", tag, x))
    end
  end
end

-- One term.  `slot` is 0-based from row 17; `sign` is CH_PLUS or CH_MINUS.
local function assertTerm(tag, slot, statTiles, statName, sign, magnitude)
  local y = 17 + slot * 2
  for k = 0, 6 do
    H.assertEq(cell(17 + k, y), statTiles[k + 1],
      string.format("%s: term %d '%s' tile %d at {%d,%d}",
        tag, slot, statName, k, 17 + k, y))
  end
  -- The col-24 spacer.  It exists because "Stamina" and "Mag.Pwr" fill all
  -- seven name cells, so without it the sign sits flush against the label.
  H.assertEq(cell(24, y), BLANK,
    string.format("%s: term %d spacer blank at {24,%d}", tag, slot, y))
  H.assertEq(cell(25, y), sign,
    string.format("%s: term %d sign %s at {25,%d}", tag, slot,
      sign == CH_MINUS and "'-'" or "'+'", y))
  H.assertEq(cell(26, y), BLANK,
    string.format("%s: term %d leading zero blanked at {26,%d}", tag, slot, y))
  H.assertEq(cell(27, y), digit(magnitude),
    string.format("%s: term %d magnitude %d at {27,%d}", tag, slot, magnitude, y))
end

-- A term row the walk did not reach: the whole 10-cell field is blank.
local function assertTermRowBlank(tag, slot)
  local y = 17 + slot * 2
  for x = 17, 27 do
    H.assertEq(cell(x, y), BLANK,
      string.format("%s: unused term row %d blank at {%d,%d}", tag, slot, x, y))
  end
end

-- Row 27 is where #27's single line lived.  Nothing draws there now, and the
-- page must clear it.  This is asserted on every stone, all of which have a
-- mod, which #27 could not do because its own line was there.
local function assertOldLineGone(tag)
  for x = 5, 27 do
    H.assertEq(cell(x, 27), BLANK,
      string.format("%s: #27's old row-27 line cleared at {%d,27}", tag, x))
  end
end

-- A stat whose delta is zero must appear nowhere in the term column; without
-- this, a walk that drew all four stats with a "+ 0" would still satisfy every
-- positive assertion above.
local function assertStatAbsent(tag, statTiles, statName)
  for y = 17, 25, 2 do
    H.assertEq(cell(17, y) ~= statTiles[1] or cell(18, y) ~= statTiles[2],
      true, string.format("%s: no %s term drawn (row %d) -- zero deltas "
        .. "cost no line", tag, statName, y))
  end
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  -- positive control on the fixture, read-only: the bag holds the
  -- three stones (gen_ifrit_magicite's own exit assertion, re-made at consume
  -- time).  A fixture that lost them fails here with a clear message rather
  -- than in a list that has no rows.
  H.call(function()
    H.log(string.format("[espers] $1a69 = %02x %02x %02x %02x (read, not pinned)",
      H.readByte(ESPERS), H.readByte(ESPERS + 1), H.readByte(ESPERS + 2),
      H.readByte(ESPERS + 3)))
    H.assertEq(H.readByte(ESPERS) & 0x07, 0x07,
      "the save owns RAMUH + IFRIT + SHIVA ($1a69 bits 0-2, give_genju receipts)")
  end),

  -- X opens the field menu; ride the fade to the main-menu steady state.
  -- This uses driveUntil rather than one press because the X that opens the
  -- field menu is the first step in these tests that needs a specific frame,
  -- so it is where a fixture generated against a different ROM shows up, as
  -- "timeout waiting for main menu", which reads like a menu bug and is not
  -- one.  Retrying the press costs nothing when the pairing is fine and
  -- removes the false report when it is not.  This is the shape
  -- probe_fieldicons.lua and menu_blitzpage_sabin.lua already use.  The
  -- assertion is unchanged: the main menu must still come up.
  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),

  -- Items -> Skills, A; pick the lead character; land on the skills submenu.
  H.pressButtons({ "down" }, 2),            -- Items -> Skills
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(10),

  -- positive control: the Espers row is enabled because the save owns
  -- stones, not because anything was written.
  H.call(function()
    H.assertEq(H.readByte(SKILLCOLOR), 0x20, "Espers row enabled (color $20)")
  end),
  -- The submenu keeps the caller's cursor row; walk it up onto Espers.
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == 0
  end, 600, { H.pressButtons({ "up" }, 2), H.waitFrames(6) },
    "skills submenu cursor to Espers"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_LIST end, 300, "esper list", 5),
  H.call(function()
    H.assertEq(H.readByte(ZLISTTYPE), 4, "list type GENJU (menu_ram.inc)")
  end),

  -- ---- IFRIT: three terms, a skipped speed, and the minus ----------------
  listSeek(IFRIT, "cursor to IFRIT's row"),
  H.waitFrames(20),                     -- let any list scroll finish (A is
                                        -- ignored while ScrollListPage runs)
  H.driveUntil(function() return st() == ST_DETAIL end, 600,
    { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, "Ifrit detail"),
  H.waitFrames(30),                     -- let the page draw + DMA settle
  H.call(function()
    H.assertEq(H.readByte(Z99), IFRIT, "detail page is IFRIT's")
    assertDeadColumnsGone("ifrit")
    -- Spell list: Fire's name cell is drawn (grant list still present).
    H.assertEq(cell(5, 17) ~= BLANK, true, "ifrit: spell 1 name drawn at {5,17}")
    -- Ifrit's row is +6 vigor / 0 speed / +4 stamina / -3 mag.pwr, so the three
    -- nonzero deltas pack onto rows 17/19/21.  Speed is skipped, which shows
    -- the walk packs rather than reserving a line per stat, and the
    -- third term carries a minus, the sign the old encoding could not express.
    assertCaption("ifrit", true)
    assertTerm("ifrit", 0, STAT.VIGOR,   "Vigor",   CH_PLUS,  6)
    assertTerm("ifrit", 1, STAT.STAMINA, "Stamina", CH_PLUS,  4)
    assertTerm("ifrit", 2, STAT.MAGPWR,  "Mag.Pwr", CH_MINUS, 3)
    assertTermRowBlank("ifrit", 3)
    assertTermRowBlank("ifrit", 4)
    assertOldLineGone("ifrit")
    assertStatAbsent("ifrit", STAT.SPEED, "Speed")
    H.screenshot("esper_detail_ifrit")
    H.log("IFRIT: dead columns gone; Vigor +6 / Stamina +4 / Mag.Pwr -3 drawn")
  end),

  -- Back to the list; the saved cursor row is restored.
  H.pressButtons({ "b" }, 2),
  H.waitUntil(function() return st() == ST_LIST end, 300, "back to list", 5),
  H.waitFrames(10),

  -- ---- SHIVA: the mirror, a leading minus with stamina skipped ------------
  -- This is the revisit-overwrite check: her slot-1 term must read "Speed" in
  -- the cells Ifrit's page just drew "Stamina" into, and her slot-0 sign must
  -- be the minus where his was a plus.  A page that failed to redraw would
  -- still show his tiles and fail every one of these exact-value checks.
  listSeek(SHIVA, "cursor to SHIVA's row"),
  H.waitFrames(20),
  H.driveUntil(function() return st() == ST_DETAIL end, 600,
    { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, "Shiva detail"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(Z99), SHIVA, "detail page is SHIVA's")
    assertDeadColumnsGone("shiva")
    H.assertEq(cell(5, 17) ~= BLANK, true, "shiva: spell 1 name drawn at {5,17}")
    -- Shiva's row is -3 vigor / +4 speed / 0 stamina / +6 mag.pwr: three terms
    -- with the middle zero skipped this time, and the minus leading the block.
    assertCaption("shiva", true)
    assertTerm("shiva", 0, STAT.VIGOR,  "Vigor",   CH_MINUS, 3)
    assertTerm("shiva", 1, STAT.SPEED,  "Speed",   CH_PLUS,  4)
    assertTerm("shiva", 2, STAT.MAGPWR, "Mag.Pwr", CH_PLUS,  6)
    assertTermRowBlank("shiva", 3)
    assertTermRowBlank("shiva", 4)
    assertOldLineGone("shiva")
    assertStatAbsent("shiva", STAT.STAMINA, "Stamina")
    H.screenshot("esper_detail_shiva")
    H.log("SHIVA: Vigor -3 / Speed +4 / Mag.Pwr +6 drawn over Ifrit's block")
  end),

  H.pressButtons({ "b" }, 2),
  H.waitUntil(function() return st() == ST_LIST end, 300, "back to list", 5),
  H.waitFrames(10),

  -- ---- RAMUH: the two-term shape, after two three-term pages ---------------
  -- +4 stamina / +2 mag.pwr: the walk must skip two leading zeros before its
  -- first term, and slot 2 must be blank in the cells the last two pages both
  -- filled.  That is the new check here.  It covers the same property the old
  -- no-mod TERRATO page covered with an all-blank block: the page clears what
  -- it does not draw, and blankness after fullness shows the same clear.
  listSeek(RAMUH, "cursor to RAMUH's row"),
  H.waitFrames(20),
  H.driveUntil(function() return st() == ST_DETAIL end, 600,
    { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, "Ramuh detail"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(Z99), RAMUH, "detail page is RAMUH's")
    assertDeadColumnsGone("ramuh")
    H.assertEq(cell(5, 17) ~= BLANK, true, "ramuh: spell 1 name drawn at {5,17}")
    assertCaption("ramuh", true)
    assertTerm("ramuh", 0, STAT.STAMINA, "Stamina", CH_PLUS, 4)
    assertTerm("ramuh", 1, STAT.MAGPWR,  "Mag.Pwr", CH_PLUS, 2)
    -- slot 2 held "Mag.Pwr -3" on Ifrit's page and "Mag.Pwr +6" on Shiva's;
    -- for Ramuh it must be blank, which checks the clear against real content.
    assertTermRowBlank("ramuh", 2)
    assertTermRowBlank("ramuh", 3)
    assertTermRowBlank("ramuh", 4)
    assertOldLineGone("ramuh")
    assertStatAbsent("ramuh", STAT.VIGOR, "Vigor")
    assertStatAbsent("ramuh", STAT.SPEED, "Speed")
    H.screenshot("esper_detail_ramuh")
    H.log("RAMUH: Stamina +4 / Mag.Pwr +2, and the third term row is cleared")
  end),

  H.call(function()
    H.log("PASSED: esper detail shows the while-worn stat block for all three "
      .. "OWNED stones, hides the dead learn-rate columns, packs past zero "
      .. "deltas anywhere in the row, and clears what it does not draw")
  end),
})
