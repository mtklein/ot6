-- @suite savestate=celes_freed
-- menu_thiefpage.lua -- issue #68: the field Skills->Thief page, the acceptance
-- criterion #55 (Locke's battle thief submenu) shipped without.
--
-- The skills list grew an 8th row, Thief, gated like every other row by the
-- character's own battle commands (_c34d78 gained BATTLE_CMD::STEAL, so the
-- row is white exactly for Steal owners), and A on it opens a field info page
-- in the Blitz page's shape: one column, name + MP price per row, B backs out,
-- A is a no-op.  Three rows, always -- there is no learned set: Steal, Filch
-- and Bestow exist from the moment Locke does (granted at join, kits.md).
--
-- Everything is asserted against the tables the game itself reads, so the
-- page cannot drift from the battle submenu it mirrors:
--
--   * names from the ROM's own AttackName records.  The thief row ids $56-$58
--     are AttackName pad slots (record = id - $51, so 5/6/7), the same records
--     ListTextCmd_0f renders the battle thief list from (btlgfx_main.asm).
--   * prices from the same two authorities the battle CHARGE reads
--     (Ot6ThiefCost's split, ot6_loadout.asm): Steal from Ot6StealCost's
--     immediate (read at the source, battle_costtable.lua's pattern, with an
--     opcode guard so a reshaped leaf fails loudly), Filch/Bestow from
--     Ot6ThiefCostTbl's (key, cost) records.  NOT Ot6AbilityCostTbl: that
--     table keys $55-$5c as SwdTech boost rows, which is why the page pricing
--     through generic Ot6LoadoutCost would have drawn SwdTech prices here.
--   * NO probe-icon column, asserted blank.  Ot6SkillClassTbl keys $56-$58 to
--     SwdTech's slash class (the id collision again), so an icon here would
--     teach the wrong thing; the battle thief list draws none either.
--
-- Geometry is the Blitz page's (#43): rows 1/3/5 (odd rows only, nothing past
-- row 15), name at column 3 flush against the cursor at x=8 (cursor_x =
-- 8*col - 16), price right-aligned at column 16 through Ot6LoadoutDrawCost.
-- The cursor canary reads Ot6ThiefCursorPos out of the ROM and the text out
-- of the tilemap shadow, both sides live, as menu_blitzpage.lua does.
--
-- Fixture: celes_freed, the real just-freed-Celes save.  LOCKE carries Steal
-- (his own record; nothing is installed) so his row is white and the page
-- opens; CELES does not, so her row is gray and A on it refuses
-- (SelectSkillsOption's $20 gate).  Both paths run on one save with zero
-- memory writes.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/celes_freed.mss.lua"

local ZMENUSTATE, ZCURSOR, ZSELINDEX = 0x26, 0x4b, 0x28
local ZCHARID = 0x69                    -- zCharID::Slot1..4 (menu_ram.inc)
local THIEF_ROW_COLOR = 0x80            -- zSkillsTextColor::Thief (menu_ram.inc)
local CHAR_LOCKE, CHAR_CELES = 0x01, 0x06
local BATTLE_CMD_STEAL = 0x05
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_THIEF = 0x05, 0x06, 0x0a, 0x30
local SKILLS_ROW_THIEF = 7              -- Espers Magic SwdTech Blitz Lore Rage Dance THIEF

local function st() return H.readByte(ZMENUSTATE) end

-- BG1 screen A tilemap shadow (wBG1Tiles::ScreenA = $7e3849, menu_ram.inc):
-- 2 bytes per cell (char, color), 64 bytes per row; cell(x,y) = char byte.
local BG1A = 0x3849
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end

-- menu text codec (ff6/tools/char_table/text_en.json): 'A'=$80.. 'a'=$9a..
-- '0'=$b4.. ' '=$ff.  " MP" is menu_text_en.inc.raw's OT6_LOADOUT_MP_SUFFIX.
local T = { M = 0x8c, P = 0x8f, SP = 0xff }
local MP_SUFFIX = { T.SP, T.M, T.P }
local ZERO_CHAR, DIGIT9 = 0xb4, 0xbd
local PAD = 0xff                        -- fixed_length_en.json: 0xFF = {pad}

-- ---- the ROM tables this page must agree with ----
local ATKNAME = H.sym("AttackName") & 0x3FFFFF
local NAME_SIZE = 10                    -- AttackName::ITEM_SIZE
local ATKNAME_0 = 0x51                  -- AttackName record 0 is attack id $51
local THIEF_ATK0 = 0x56                 -- Steal; Filch $57, Bestow $58
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

-- Prices, from the charge's own two authorities (Ot6ThiefCost's split).
-- Steal: Ot6StealCost is `lda #imm / rtl`; read the immediate at the source
-- with battle_costtable.lua's opcode guard.  Filch/Bestow: Ot6ThiefCostTbl,
-- (key, cost) pairs, $ff-terminated (ot6_boost.asm).
local STEALCOST = H.sym("Ot6StealCost") & 0x3FFFFF
local THIEFTBL = H.sym("Ot6ThiefCostTbl") & 0x3FFFFF
local function costOf(id)
  if id == THIEF_ATK0 then
    H.assertEq(H.readRomByte(STEALCOST), 0xA9,
      "Ot6StealCost still opens with LDA #imm -- the +1 read below is the price")
    return H.readRomByte(STEALCOST + 1)
  end
  local x = 0
  while true do
    local key = H.readRomByte(THIEFTBL + x)
    if key == 0xff then return 0 end
    if key == id then return H.readRomByte(THIEFTBL + x + 1) end
    x = x + 2
  end
end

-- ---- page geometry, mirroring skills.asm's Ot6ThiefPageDraw ----
local NAME_COL, COST_COL = 3, 16
local function thiefRow(i) return 1 + i * 2 end   -- odd rows 1/3/5 (#43)

local function assertRun(x0, y, bytes, what)
  for i, b in ipairs(bytes) do
    H.assertEq(cell(x0 + i - 1, y), b,
      string.format("%s: cell {%d,%d}", what, x0 + i - 1, y))
  end
end

local function assertRowBlank(y, what)
  for x = 0, 31 do
    H.assertEq(cell(x, y), 0, string.format("%s: cell {%d,%d} blank", what, x, y))
  end
end

-- The geometry canary (#43): even rows are four scanlines in this window and
-- rows past 15 are outside it, so nothing may land on either.  Column 30 is
-- the window's right border; columns 0-2 the cursor gutter on every row.
-- Rows 7..15 are odd and usable but this page has only three rows, so they
-- must stay blank too -- a fourth row appearing is a bug this catches.
local function assertGeometry(what)
  for y = 0, 27 do
    if y % 2 == 0 or y > 5 then
      assertRowBlank(y, string.format(
        "%s: row %d must be empty (%s)", what, y,
        (y % 2 == 0) and "even: four scanlines"
          or (y > 15) and "outside the window"
          or "past the page's three rows"))
    end
  end
  for y = 1, 5, 2 do
    for _, x in ipairs({ 0, 1, 2, 13, 14, 15, 30, 31 }) do
      H.assertEq(cell(x, y), 0, string.format(
        "%s: {%d,%d} must stay blank -- %s", what, x, y,
        (x <= 2) and "the cursor sprite's gutter"
          or (x >= 30) and "the window's border column"
          or "the gap between name and price (NO icon column on this page: "
             .. "Ot6SkillClassTbl keys $56-$58 as SwdTech slash rows)"))
    end
    for x = COST_COL + 5, 29 do
      H.assertEq(cell(x, y), 0, string.format(
        "%s: {%d,%d} is past the price field", what, x, y))
    end
  end
end

-- The cursor gutter canary (#43 round 3), menu_blitzpage.lua's, over
-- Ot6ThiefCursorPos's three entries.  Both sides are read live: the cursor
-- table out of the ROM the menu indexes, the text out of the tilemap shadow
-- the menu drew.  y = 116 + n*12 -> tilemap row (y-116)/6 + 1.
local CURSOR_POS = H.sym("Ot6ThiefCursorPos") & 0x3FFFFF
local function assertCursorGutter(n, what)
  local cx = H.readRomByte(CURSOR_POS + n * 2)
  local cy = H.readRomByte(CURSOR_POS + n * 2 + 1)
  local col, y = cx // 8, (cy - 116) // 6 + 1
  H.assertEq(y % 2 == 1 and y >= 1 and y <= 15, true, string.format(
    "%s: cursor entry %d (y=%d) points at tilemap row %d, which this window "
    .. "does not show whole", what, n, cy, y))
  H.assertEq(y, thiefRow(n), string.format(
    "%s: cursor entry %d must point at thief row %d's tilemap row", what, n, n))
  for _, x in ipairs({ col, col + 1 }) do
    H.assertEq(cell(x, y), 0, string.format(
      "%s: cursor entry %d sits at x=%d, so tilemap {%d,%d} is under the "
      .. "sprite and must be blank", what, n, cx, x, y))
  end
  H.assertEq(cell(col + 2, y) ~= 0, true, string.format(
    "%s: cursor entry %d at x=%d reserves columns %d-%d, so row %d must start "
    .. "at column %d (vanilla: cursor_x = 8*col - 16)",
    what, n, cx, col, col + 1, n, col + 2))
  H.assertEq(col + 2, NAME_COL, string.format(
    "%s: cursor entry %d and the page's name column must agree", what, n))
end

-- ---- one row: name + price, and deliberately no icon ----
local function assertThiefRow(i)
  local id, y = THIEF_ATK0 + i, thiefRow(i)
  assertRun(NAME_COL, y, nameBytes(id),
    string.format("thief row %d name %s", i, nameText(id)))
  local cost = costOf(id)
  H.assertEq(cost > 0, true, string.format(
    "thief row %d (%s) is priced -- every ability costs MP (v0.5); a zero "
    .. "here means the page read the wrong table", i, nameText(id)))
  local tens = cost // 10
  H.assertEq(cell(COST_COL, y), tens > 0 and (ZERO_CHAR + tens) or PAD,
    string.format("thief row %d cost %d: tens cell {%d,%d} (blank, not '0', "
      .. "under 10)", i, cost, COST_COL, y))
  H.assertEq(cell(COST_COL + 1, y), ZERO_CHAR + (cost % 10),
    string.format("thief row %d cost %d: ones cell {%d,%d}", i, cost, COST_COL + 1, y))
  assertRun(COST_COL + 2, y, MP_SUFFIX, string.format("thief row %d ' MP'", i))
end

local lockeSlot, celesSlot = nil, nil

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  -- the player's path: X -> main menu -> Skills -> LOCKE -> the 8th row
  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),
  -- Find both characters rather than assume their slots, and assert LOCKE's
  -- own record carries Steal and CELES's does not: the gating below is the
  -- character data's, nothing installed by this test.
  H.call(function()
    local ids = {}
    for s = 0, 3 do
      local id = H.readByte(ZCHARID + s)
      ids[#ids + 1] = string.format("slot %d = char $%02x", s, id)
      if id == CHAR_LOCKE and lockeSlot == nil then lockeSlot = s end
      if id == CHAR_CELES and celesSlot == nil then celesSlot = s end
    end
    H.log("party: " .. table.concat(ids, ", "))
    H.assertEq(lockeSlot ~= nil, true, "celes_freed's party contains LOCKE")
    H.assertEq(celesSlot ~= nil, true, "celes_freed's party contains CELES")
    local function hasSteal(char)
      local rec = 0x1600 + 37 * char
      for i = 0, 3 do
        if H.readByte(rec + 0x16 + i) == BATTLE_CMD_STEAL then return true end
      end
      return false
    end
    H.assertEq(hasSteal(CHAR_LOCKE), true,
      "LOCKE's own record carries BATTLE_CMD::STEAL -- nothing is installed")
    H.assertEq(hasSteal(CHAR_CELES), false,
      "CELES's record does not carry Steal -- she is the gray-row control")
    for i = 0, 2 do
      H.log(string.format("thief row %d %s costs %d MP",
        i, nameText(THIEF_ATK0 + i), costOf(THIEF_ATK0 + i)))
    end
  end),
  H.pressButtons({ "down" }, 2),            -- Items -> Skills
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.waitFrames(10),
  H.driveUntil(function() return H.readByte(ZCURSOR) == lockeSlot end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "cursor onto LOCKE"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.readByte(THIEF_ROW_COLOR), 0x20,
      "Thief row white for LOCKE -- his own record carries Steal")
  end),

  -- cursor to the 8th row (the row itself is the fail-before: a 7-row build's
  -- cursor prop {1,7} cannot reach index 7 and this times out), A opens the
  -- page through SkillsOption_07
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == SKILLS_ROW_THIEF
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "skills cursor to Thief (index 7)"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_THIEF end, 300,
    "thief page open via the player path (menu state $30)", 5),
  H.waitFrames(90),                         -- draws + DMA settle

  H.call(function()
    for i = 0, 2 do assertThiefRow(i) end
    assertGeometry("thief page")
    for n = 0, 2 do assertCursorGutter(n, "thief page") end
    -- the description box holds the empty string, not another page's
    -- leftovers: LoadThiefDesc stages $ff (LoadBigText's blank arm) every
    -- frame, and $7e9ec9 is the buffer the big-text task renders from.
    H.assertEq(H.readByte(0x9ec9), 0xff,
      "description buffer holds the blank marker -- the thief rows have no "
      .. "desc asset and must not show another page's text")
    H.screenshot("thiefpage_rows")
    H.log("RENDER OK: Skills->Thief for a REAL LOCKE -- three rows, each the "
      .. "AttackName record's own name and the charge's own price, no icon "
      .. "column, no fourth row, every cell inside rows 1/3/5 and clear of "
      .. "the gutter and border")
  end),

  -- ---- the cursor moves over exactly three rows ----
  H.pressButtons({ "down" }, 2),
  H.waitFrames(20),
  H.pressButtons({ "down" }, 2),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(st(), ST_THIEF, "still on the thief page")
    H.assertEq(H.readByte(ZCURSOR), 2,
      "one column: two steps down is row 2 (Bestow)")
    for n = 0, 2 do assertCursorGutter(n, "cursor on row 2") end
  end),

  -- ---- B backs out and the skills list is whole again ----
  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_SKILLS end, 300,
    "B returns to the skills list", 5),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(THIEF_ROW_COLOR), 0x20,
      "back on the list, the Thief row is still LOCKE-white -- the list "
      .. "redraw (_c34d27/ReloadSkillsMenu) recomputed the colors")
  end),

  -- ---- the control: CELES's gray row refuses ----
  -- shoulder R steps to the next character's skills list (CheckShoulderBtns)
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZSELINDEX) == celesSlot
  end, 900, { H.pressButtons({ "r" }, 2), H.waitFrames(30) },
    "shoulder R to CELES"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(THIEF_ROW_COLOR), 0x24,
      "Thief row gray for CELES -- no Steal in her record")
  end),
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == SKILLS_ROW_THIEF
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "CELES's cursor to the Thief row"),
  H.pressButtons({ "a" }, 2),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(st(), ST_SKILLS,
      "A on the gray Thief row refuses (SelectSkillsOption's $20 gate) -- "
      .. "still on the skills list, not on the thief page")
    H.log("GATING OK: white for the Steal owner and the page opens; gray for "
      .. "everyone else and A goes nowhere")
  end),
})
