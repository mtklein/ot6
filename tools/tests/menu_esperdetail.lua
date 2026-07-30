-- @suite frontier=arvis_wake
-- menu_esperdetail.lua -- issue #27, rebuilt for #62: the esper detail page
-- shows the while-worn stat BLOCK and never the dead learn-rate columns.
--
-- M5 made espers while-equipped sub-jobs: every GenjuProp learn rate is 0 and
-- every level-up bonus byte is $ff (ff6/src/menu/genju_prop.asm), but the
-- vanilla esper detail page (skills.asm DrawEsperDetailMenu) still drew the
-- "Learn.Rate"/"Skill" captions, a ":  {times}00" rate after every spell, a
-- "  0%" skill column, and a blank bonus line -- so Ifrit's vigor bonus
-- (Ot6EsperStatTbl, ff6/src/battle/ot6_progression.asm) was invisible in
-- game.  #27 drew the spell names bare and put ONE line, "While worn...<stat>
-- +<n>", where the dead bonus line had been.
--
-- #62 WIDENED THE TABLE AND THIS PAGE WITH IT.  Ot6EsperStatTbl is now two
-- bytes per esper in vanilla's own equipment layout -- four SIGNED nibbles,
-- -7..+7 each -- so a stone carries up to four deltas and any of them can be
-- negative.  Four terms do not fit on one line, so the page draws a right-hand
-- COLUMN: the caption rides the title row (in the very cells vanilla used for
-- its Learn.Rate/Skill captions and #27 blanked), and one term per nonzero
-- delta packs downward from row 17.
--
-- THE ASSERTIONS THAT CHANGED, AND WHY -- deliberately, not loosened:
--   * cell(13,15) was asserted BLANK ("no Learn.Rate caption"); it is now the
--     left pad of the caption field, and the caption's own 'W' is asserted at
--     {15,15} with {13,15}/{14,15} still blank.  The thing that check existed
--     to catch -- vanilla's caption TEXT coming back -- is now covered by
--     asserting the exact tiles that ARE there.
--   * cell(16,17) and cell(26,17)/cell(27,17) were asserted BLANK (no
--     "{times}NN" rate, no percent digits, no percent sign).  Cols 26/27 of row
--     17 now hold a term's magnitude digits.  The percent SIGN at {27,17} is
--     replaced by an exact-value assertion on the digit; the rate colon at
--     {12,17}, which nothing draws to, stays a blank assertion, and a new
--     no-percent-glyph sweep replaces the two cells that moved.
--   * the single line at row 27 is gone, so row 27 is now asserted BLANK for
--     BOTH stones, including the stone WITH a mod -- which is a strictly new
--     check: #27's own line lived there, so nothing could previously prove that
--     region gets cleared on a page that has something to say.
--
-- This test drives the REAL menu UI (X -> Skills -> character -> Espers ->
-- list -> detail) from the arvis_wake fixture, the same boot
-- menu_bushidoloadout uses.  arvis_wake owns no espers yet, so the esper
-- inventory bits are pinned directly (the battle_bushido "install state"
-- house pattern): exactly IFRIT (esper 1 -- #62's marquee, because his row is
-- the two-sided mod magicite-ifrit-shiva.md §12.1 recorded as unbuildable:
-- +6 vigor / +4 stamina / -3 mag.pwr, so this page has to render three terms
-- AND a minus sign) and TERRATO (esper 4, Ot6EsperStatTbl $0000 = no mod),
-- giving one page of each kind.  Rendering is asserted at cell level in the BG1
-- screen-B tilemap shadow the menu draws into (wBG1Tiles::ScreenB = $7e4049,
-- ff6-en.dbg; 2 bytes per cell, char then color, 64 bytes per row) and
-- proven visually with screenshots of both pages.
--
-- LAYOUT, from skills.asm's DrawEsperDetailMenu tail:
--   caption "While worn..." right-aligned in the 16-cell field at {13,15}:
--     cols 13-14 blank, cols 15-27 the 13 caption tiles, col 28 blank
--   one term per nonzero delta, packed downward from tilemap row 17 over the
--   odd rows 17/19/21/23/25 (one window row = two tilemap rows):
--     stat name cols 18-24 (7 tiles, Ot6GenjuStatNameTbl, space-padded)
--     sign col 25: '+' $ca or '-' $c4
--     magnitude cols 26-27, leading zero blanked
--   every term row the walk does not reach: cols 18-27 blank
--   row 27, where #27's single line used to be: cols 5-27 blank
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/arvis_wake.mss.lua"

local ZMENUSTATE = 0x26                 -- menu direct-page vars (menu_ram.inc)
local ZLISTTYPE  = 0x2a
local ZCURSOR    = 0x4b
local Z99        = 0x99                 -- detail page's esper index
local SKILLCOLOR = 0x79                 -- zSkillsTextColor[0] = Espers row
local ESPERS     = 0x1a69               -- owned-esper bitfield, 27 bits
local GENJULIST  = 0x9d89               -- $7e9d89: list row -> esper index
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LIST, ST_DETAIL = 0x05, 0x06, 0x0a, 0x1e, 0x4d

local IFRIT, TERRATO = 1, 4

-- BG1 screen B tilemap shadow: char byte of the cell at tile (x, y).
local BG1B = 0x4049
local function cell(x, y) return H.readByte(BG1B + x * 2 + y * 64) end

-- Menu text codec bytes asserted below (ff6/tools/char_table/text_en.json).
local CH_W, CH_COLON, CH_PCT = 0x96, 0xc1, 0xcd
local CH_PLUS, CH_MINUS, CH_DOT = 0xca, 0xc4, 0xc5
local BLANK = 0xff
local function digit(n) return 0xb4 + n end      -- '0' = $b4 .. '9' = $bd

-- Stat name tiles, verbatim from menu_text_en.inc.raw:111-114 (7 tiles each,
-- space-padded with $ff, the terminator dropped).  Spelled out rather than read
-- from the ROM so a table that silently moved could not make this test agree
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
-- a TWO-COLUMN grid (GenjuCursorProp `cursor_prop {0,0},{2,8}`, skills.asm):
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

-- The shared page shape: vanilla's dead learn-rate machinery is gone.  #62 took
-- over cols 18-27 of the spell rows and cols 13-28 of the title row, so the
-- three cells the old version of this check used there have been replaced with
-- checks of the same class that survive the new layout:
--   * col 12 of a spell row is where vanilla's rate colon sat, and NOTHING in
--     the OT6 page draws there -- so it stays a blank assertion;
--   * the percent glyph $cd (the "0%" column's sign) must not appear ANYWHERE
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
    H.assertEq(cell(18 + k, y), statTiles[k + 1],
      string.format("%s: term %d '%s' tile %d at {%d,%d}",
        tag, slot, statName, k, 18 + k, y))
  end
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
  for x = 18, 27 do
    H.assertEq(cell(x, y), BLANK,
      string.format("%s: unused term row %d blank at {%d,%d}", tag, slot, x, y))
  end
end

-- Row 27 is where #27's single line lived.  Nothing draws there now, and the
-- page must CLEAR it -- asserted for a stone WITH a mod as well as without,
-- which #27 could not do because its own line was there.
local function assertOldLineGone(tag)
  for x = 5, 27 do
    H.assertEq(cell(x, 27), BLANK,
      string.format("%s: #27's old row-27 line cleared at {%d,27}", tag, x))
  end
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  -- Pin the esper inventory to exactly IFRIT + TERRATO (bits 1 and 4).
  H.call(function()
    H.log(string.format("[pin] $1a69 was %02x; pinning IFRIT+TERRATO",
      H.readByte(ESPERS)))
    H.writeByte(ESPERS + 0, 0x12)
    H.writeByte(ESPERS + 1, 0x00)
    H.writeByte(ESPERS + 2, 0x00)
    H.writeByte(ESPERS + 3, 0x00)
  end),

  -- X opens the field menu; ride the fade to the main-menu steady state.
  H.pressButtons({ "x" }, 4),
  H.waitUntil(function() return st() == ST_MAIN end, 600, "main menu", 5),
  H.waitFrames(20),

  -- Items -> Skills, A; pick the lead character; land on the skills submenu.
  H.pressButtons({ "down" }, 2),            -- Items -> Skills
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(10),

  -- POSITIVE CONTROL: the Espers row is enabled (the pin worked) and the
  -- submenu cursor sits on it.
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

  -- ---- IFRIT: the stone WITH a while-worn mod (+5 vigor) ----------------
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
    -- nonzero deltas pack onto rows 17/19/21 -- SPEED IS SKIPPED, which is what
    -- proves the walk packs rather than reserving a line per stat -- and the
    -- third term carries a MINUS, the sign the old encoding could not express.
    assertCaption("ifrit", true)
    assertTerm("ifrit", 0, STAT.VIGOR,   "Vigor",   CH_PLUS,  6)
    assertTerm("ifrit", 1, STAT.STAMINA, "Stamina", CH_PLUS,  4)
    assertTerm("ifrit", 2, STAT.MAGPWR,  "Mag.Pwr", CH_MINUS, 3)
    assertTermRowBlank("ifrit", 3)
    assertTermRowBlank("ifrit", 4)
    assertOldLineGone("ifrit")
    -- Negative control on the packing: Speed's label must appear NOWHERE, since
    -- Ifrit's speed delta is zero.  Without this, a walk that drew all four
    -- stats with a "+ 0" would still satisfy every assertion above.
    for y = 17, 25, 2 do
      H.assertEq(cell(18, y) ~= STAT.SPEED[1] or cell(19, y) ~= STAT.SPEED[2],
        true, string.format("ifrit: no Speed term drawn (row %d) -- zero deltas "
          .. "cost no line", y))
    end
    H.screenshot("esper_detail_ifrit")
    H.log("IFRIT: dead columns gone; Vigor +6 / Stamina +4 / Mag.Pwr -3 drawn")
  end),

  -- Back to the list; the saved cursor row is restored.
  H.pressButtons({ "b" }, 2),
  H.waitUntil(function() return st() == ST_LIST end, 300, "back to list", 5),
  H.waitFrames(10),

  -- ---- TERRATO: a stone with NO mod (Ot6EsperStatTbl $00) ---------------
  listSeek(TERRATO, "cursor to TERRATO's row"),
  H.waitFrames(20),                     -- let any list scroll finish (A is
                                        -- ignored while ScrollListPage runs)
  H.driveUntil(function() return st() == ST_DETAIL end, 600,
    { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, "Terrato detail"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(Z99), TERRATO, "detail page is TERRATO's")
    assertDeadColumnsGone("terrato")
    H.assertEq(cell(5, 17) ~= BLANK, true, "terrato: spell 1 name drawn at {5,17}")
    -- No mod at all ($0000): NO caption and NO term anywhere -- including the
    -- cells Ifrit's page just filled, which is what proves the revisit
    -- overwrote them.  This is the honest-empty-state requirement: a stone with
    -- nothing to say must not show a heading over an empty column.
    assertCaption("terrato", false)
    for slot = 0, 4 do assertTermRowBlank("terrato", slot) end
    assertOldLineGone("terrato")
    H.screenshot("esper_detail_terrato")
    H.log("TERRATO: page clean in the no-mod state -- no caption, no terms")
  end),

  H.call(function()
    H.log("PASSED: esper detail shows the while-worn stat mod, hides the "
      .. "dead learn-rate columns, and is correct with and without a mod")
  end),
})
