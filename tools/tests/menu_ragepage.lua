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
-- skills.asm:124-125, and DrawRageName biases its row `.if LANG_EN`,
-- skills.asm:1518-1521).  The page shipped with eight slots on EVEN rows
-- 4..18 and LEARNED on row 20, so through the player's path every beast name
-- rendered as a three-scanline sliver and the collection counter was off the
-- bottom of the window.  It now draws two columns of four on odd rows 5/7/9/11
-- with LEARNED on 15 -- vanilla's own shape for this very window.  Hence the
-- EVEN-ROW CANARY below: it is not decoration, it is the regression.
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
            N=0x8d, O=0x8e, P=0x8f, R=0x91, T=0x93, U=0x94, SP=0xff }
local TITLE   = { T.R,T.A,T.G,T.E,T.SP,T.L,T.O,T.A,T.D,T.O,T.U,T.T }  -- RAGE LOADOUT
local LEARNED = { T.L,T.E,T.A,T.R,T.N,T.E,T.D }
local EACH_TX = { T.E,T.A,T.C,T.H }
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
-- four on ODD rows.  slot even = left column (name col 2), slot odd = right
-- (col 16); row = 5 + (slot & ~1).  The price is stated ONCE on the title row
-- ("8 MP EACH") rather than per row: two 10-cell names plus two cursor columns
-- plus two 4-cell cost fields is 30 columns and the window's right border is
-- column 30 (measured at screen x = 245).  The price is flat by design, so one
-- copy teaches the same rule.
local TITLE_ROW, LEARNED_ROW = 1, 15
local COST_COL, EACH_COL = 17, 22
local function slotRow(slot) return 5 + (slot & ~1) end
local function slotCol(slot) return (slot % 2 == 0) and 2 or 16 end

local function assertFilledRow(slot, id)
  local y, c = slotRow(slot), slotCol(slot)
  assertRun(c, y, nameBytes(id), string.format("slot %d name %s", slot, nameText(id)))
end
-- An empty slot: the name field is $ff-blanked across its full width, so a
-- revert wipes what was there.  NOT $00 -- these cells ARE drawn, blank.
local function assertEmptyRow(slot)
  local y, c = slotRow(slot), slotCol(slot)
  for i = 0, NAME_SIZE - 1 do
    H.assertEq(cell(c + i, y), PAD,
      string.format("empty slot %d: name cell {%d,%d} blanked", slot, c + i, y))
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
    assertRun(2, TITLE_ROW,   TITLE,   "title RAGE LOADOUT")
    -- the flat price, stated once: "8 MP EACH" on the title row
    H.assertEq(cell(COST_COL, TITLE_ROW), ZERO_CHAR + 8,
      "the trance price on the title row is 8 (Dance's number, one authority)")
    assertRun(COST_COL + 1, TITLE_ROW, MP_SUFFIX, "' MP' after the price")
    assertRun(EACH_COL, TITLE_ROW, EACH_TX, "'EACH' -- the price is per trance")
    assertRun(2, LEARNED_ROW, LEARNED, "LEARNED caption")
    -- the collection score: three digits at col 10 of the caption row
    assertRun(10, LEARNED_ROW, { ZERO_CHAR, ZERO_CHAR, ZERO_CHAR + #KNOWN },
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
    -- the odd rows the page deliberately leaves empty
    for _, y in ipairs({ 3, 13 }) do
      assertRowBlank(y, "undrawn odd row " .. y)
    end
    -- the gaps on the title row, and its tail: nothing may run into the
    -- window's own right border, which lives in column 30.
    for _, x in ipairs({ 14, 15, 16, 21, 26, 27, 28, 29, 30, 31 }) do
      H.assertEq(cell(x, TITLE_ROW), 0,
        string.format("title row gap/tail blank {%d,%d}", x, TITLE_ROW))
    end
    H.screenshot("rage_page_player_path")
    H.log("RENDER OK: Skills->Rage via the player's path -- title, eight slots "
      .. "in two columns on the window's odd rows, names against MonsterName "
      .. "verbatim, the flat 8 MP stated once, LEARNED count; nothing on an "
      .. "even row, nothing past row 15, nothing in the border column")
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
    H.assertEq(H.readByte(ZMENUSTATE), ST_RAGELOAD, "still on the rage page")
    H.screenshot("rage_page_after_cycle")
    H.log("LIVE: R redrew slot 0 as '" .. nameText(KNOWN[2])
      .. "' and the first edit froze the AUTO window into the save bytes")
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
    H.screenshot("rage_page_second_column")
    H.log("TWO COLUMNS: the cursor reaches slot 1 with dpad-Right and the "
      .. "cycle edits exactly that slot -- $4b = 2*row + col, on both sides")
  end),
})
