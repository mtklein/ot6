-- @suite
-- menu_painterpage.lua -- the field Skills list's ninth row, Painter, and
-- Relm's page behind it (#549), early in her learning.
--
-- The page is Locke's Treasure Hunter page's counterpart (menu_thiefpage):
-- one column of eight rows, her list behind Sketch in the battle list's
-- order read a column at a time (ot6_paint.asm Ot6PaintRowTbl), each
-- learned row its name and MP price, each other one the locked marker.
-- B backs out, A does nothing.  The title box reads "Painter".
--
-- Every number here comes from the ROM's own battle tables, never from a
-- copy in this file:
--   the order      Ot6PaintRowTbl's ids, 4-byte records
--   learned        the record's switch (byte off $1E80, bit) or, when the
--                  bit is 0, Relm's level against the record's level (0 = at
--                  join): Ot6PaintRowKnown's rule, read off the save
--   the names      Ot6PaintName, ten bytes per id from $E8 (the records the
--                  battle list draws)
--   the prices     Ot6PaintCostTbl, the base each list cell is stamped with
--                  and the price the battle list draws at no boost; Sketch's
--                  0 draws blank, as the battle list's two blanks do
--
-- Boot: cold Continue of ultros-won-v1, beside Esper Mountain's save point
-- (TERRA, LOCKE, STRAGO, RELM seated; RELM L22 with her recruitment switch
-- $02E8 set: Sketch, Portrait and Tint learned, the other five locked).
-- Everything below is the player's path: X, Skills, a character, the rows,
-- A and B and the shoulder buttons.  Nothing is written.
--
-- Asserted:
--   1. every seated character's Skills list draws the Painter row at BG3A
--      {2,21} inside the list window, which now closes at row 22; the row is
--      white (zSkillsTextColor::Painter $20) exactly for the character whose
--      record carries Sketch and grey ($24) for the rest; the Treasure
--      Hunter row's colour is LOCKE's alone, as before;
--   2. the cursor reaches row 8 (y = 164, the row's text row) and wraps;
--   3. A on RELM's row opens menu state $31, which draws the eight rows as
--      above, the geometry of menu_thiefpage (odd rows 1-15, nothing in the
--      gutter or past the price), the title "Painter" at BG3B {23,5}, and
--      the help window's line for the row under the cursor (below);
--   4. the page's cursor walks one column of eight;
--   5. B returns to the list with the cursor on Painter, the title row
--      blank and BG1 screen A clean in VRAM; then Espers opens with its own
--      title and no letter of "Painter" left over;
--   6. A on a grey Painter row (LOCKE, TERRA, STRAGO) refuses;
--   7. the main menu's Skills entry and the shoulder buttons still reach
--      every seated character.
-- Screenshots: painterpage_list (RELM's list), painterpage_rows (the page
-- with locked rows).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE, ZCURSOR, ZSELINDEX = 0x26, 0x4b, 0x28
local ZCHARID = 0x69                    -- zCharID::Slot1..4 (menu_ram.inc)
local THIEF_COLOR, PAINTER_COLOR = 0x80, 0x81   -- zSkillsTextColor::Thief, ::Painter
local CHAR_LOCKE, CHAR_RELM = 0x01, 0x08
local CMD_STEAL, CMD_SKETCH = 0x05, 0x0d
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_PAINTER, ST_THIEF = 0x05, 0x06, 0x0a, 0x31, 0x30
local ROW_ESPERS, ROW_THIEF, ROW_PAINTER = 0, 7, 8
local WHITE, GREY = 0x20, 0x24
local NAMES_CH = { [0] = "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO",
  "RELM", "SETZER", "MOG", "GAU", "GOGO", "UMARO" }

local function st() return H.menuRunning() and H.readByte(ZMENUSTATE) or -1 end

-- VRAM (what shows): word addresses, BG2 A $1000, B $1400; BG3 A $4000, B $4400
local VR = emu.memType.snesVideoRam
local function vcell(base, x, y) return emu.readWord((base + y * 32 + x) * 2, VR) end
local BG1A_V, BG2A_V, BG3A_V, BG3B_V = 0x0000, 0x1000, 0x4000, 0x4400
local function enc(ch)                  -- menu text codec, letters and space
  local b = ch:byte()
  if ch == " " then return 0xff end
  if b >= 65 and b <= 90 then return 0x80 + b - 65 end
  return 0x9a + b - 97
end
local function assertVText(base, x0, y, text, what)
  for i = 1, #text do
    H.assertEq(vcell(base, x0 + i - 1, y) & 0xff, enc(text:sub(i, i)),
      string.format("%s: '%s' letter %d ('%s') at {%d,%d}", what, text, i,
        text:sub(i, i), x0 + i - 1, y))
  end
end
local function isLetter(t) return t >= 0x80 and t <= 0xb3 end

-- BG1 screen A tilemap shadow (wBG1Tiles::ScreenA = $7e3849): 2 bytes a cell
local BG1A = 0x3849
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end

local ZERO_CHAR, DIGIT9, PAD = 0xb4, 0xbd, 0xff
local MP_SUFFIX = { 0xff, 0x8c, 0x8f }  -- " MP"

-- ---- the battle's tables ----
local ROWTBL = H.sym("Ot6PaintRowTbl") & 0x3FFFFF
local NAMES = H.sym("Ot6PaintName") & 0x3FFFFF
local COSTS = H.sym("Ot6PaintCostTbl") & 0x3FFFFF
local LOCKED = H.sym("Ot6BlitzLockedTiles") & 0x3FFFFF
local ID0 = 0xe8                        -- Ot6PaintName / Ot6PaintCostTbl's first id
local REC, ROWS, NAME_SIZE = 4, 8, 10
local RELM_LEVEL = 0x1600 + 37 * CHAR_RELM + 8
local function rowId(i) return H.readRomByte(ROWTBL + i * REC) end
local function learned(i)
  local a, b = H.readRomByte(ROWTBL + i * REC + 2), H.readRomByte(ROWTBL + i * REC + 3)
  if b ~= 0 then return (H.readByte(0x1E80 + a) & b) ~= 0 end
  return a == 0 or a - 1 < H.readByte(RELM_LEVEL)
end
local function nameBytes(id)
  local t = {}
  for k = 0, NAME_SIZE - 1 do t[k + 1] = H.readRomByte(NAMES + (id - ID0) * NAME_SIZE + k) end
  return t
end
local function nameText(id)
  local s = ""
  for _, b in ipairs(nameBytes(id)) do
    if b == PAD then s = s .. "."
    elseif b >= 0x80 and b <= 0x99 then s = s .. string.char(65 + b - 0x80)
    elseif b >= 0x9a and b <= 0xb3 then s = s .. string.char(97 + b - 0x9a)
    else s = s .. "?" end
  end
  return s
end
local function costOf(id) return H.readRomByte(COSTS + id - ID0) end
local function lockedBytes()
  local t = {}
  for i = 0, 15 do
    local b = H.readRomByte(LOCKED + i)
    if b == 0 then break end
    t[#t + 1] = b
  end
  return t
end

local NAME_COL, COST_COL = 3, 16
local function pageRow(i) return 1 + i * 2 end

local function assertRun(x0, y, bytes, what)
  for i, b in ipairs(bytes) do
    H.assertEq(cell(x0 + i - 1, y), b, string.format("%s: cell {%d,%d}", what, x0 + i - 1, y))
  end
end

local function assertPainterRow(i)
  local id, y = rowId(i), pageRow(i)
  if not learned(i) then
    assertRun(NAME_COL, y, lockedBytes(), string.format(
      "painter row %d ($%02X %s, not learned) draws the locked marker", i, id, nameText(id)))
    for x = COST_COL, COST_COL + 4 do
      H.assertEq(cell(x, y), PAD, string.format("painter row %d (locked) draws no price: {%d,%d}", i, x, y))
    end
    return
  end
  assertRun(NAME_COL, y, nameBytes(id), string.format("painter row %d name %s", i, nameText(id)))
  local cost = costOf(id)
  if cost == 0 then
    for x = COST_COL, COST_COL + 4 do
      H.assertEq(cell(x, y), PAD, string.format(
        "painter row %d (%s) costs 0: blank, as the battle list's two blanks ({%d,%d})", i, nameText(id), x, y))
    end
    return
  end
  local tens = cost // 10
  H.assertEq(cell(COST_COL, y), tens > 0 and (ZERO_CHAR + tens) or PAD, string.format(
    "painter row %d (%s) cost %d: tens cell {%d,%d}", i, nameText(id), cost, COST_COL, y))
  H.assertEq(cell(COST_COL + 1, y), ZERO_CHAR + (cost % 10), string.format(
    "painter row %d (%s) cost %d: ones cell {%d,%d}", i, nameText(id), cost, COST_COL + 1, y))
  assertRun(COST_COL + 2, y, MP_SUFFIX, string.format("painter row %d ' MP'", i))
end

-- menu_thiefpage's geometry: odd rows 1-15 only, the gutter, the gap and
-- the border column blank
local function assertGeometry(what)
  for y = 0, 27 do
    if y % 2 == 0 or y > 15 then
      for x = 0, 31 do
        H.assertEq(cell(x, y), 0, string.format("%s: row %d must be empty: cell {%d,%d}", what, y, x, y))
      end
    end
  end
  for y = 1, 15, 2 do
    for _, x in ipairs({ 0, 1, 2, 13, 14, 15, 30, 31 }) do
      H.assertEq(cell(x, y), 0, string.format("%s: {%d,%d} must stay blank", what, x, y))
    end
    for x = COST_COL + 5, 29 do
      H.assertEq(cell(x, y), 0, string.format("%s: {%d,%d} is past the price field", what, x, y))
    end
  end
end


-- ---- the help window: the line of the row under the cursor (#549) ----
-- tools/kit_pages.py's table in the ROM, sixteen lines a page: row n's own
-- when it is learned, line 8 + n (how it is learned) when not.  The help
-- window draws the menu's help buffer ($7e9ec9), so the buffer is compared
-- with the line the save's learned state calls for, byte for byte.
local function romLine(ptrs, strs, idx)
  local tp, ts = ptrs & 0x3FFFFF, strs & 0x3FFFFF
  local off = H.readRomByte(tp + idx * 2) | (H.readRomByte(tp + idx * 2 + 1) << 8)
  local t, k = {}, 0
  while true do
    local b = H.readRomByte(ts + off + k)
    if b == 0 then break end
    t[#t + 1] = b
    k = k + 1
  end
  return t
end
local function helpWalk(ptrs, strs, isLearned, pageState, tag, shotRows)
  local steps = {}
  for i = 0, 7 do
    steps[#steps + 1] = H.driveUntil(function() return st() == pageState and H.readByte(ZCURSOR) == i end, 900,
      { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, tag .. ": cursor to row " .. i)
    -- the help window types its line out; a row that is shot waits it out
    steps[#steps + 1] = H.waitFrames((shotRows and shotRows[i]) and 150 or 12)
    steps[#steps + 1] = H.call(function()
      local lrn = isLearned(i)
      local want = romLine(ptrs, strs, lrn and i or 8 + i)
      H.assertEq(#want > 0, true, string.format("%s row %d: the table has a line", tag, i))
      for k, b in ipairs(want) do
        H.assertEq(H.readByte(0x9ec9 + k - 1), b, string.format(
          "%s row %d (%s): the help window shows its %s line, byte %d", tag, i,
          lrn and "learned" or "locked", lrn and "own" or "how-it-is-learned", k))
      end
      H.assertEq(H.readByte(0x9ec9 + #want), 0, string.format("%s row %d: the line ends there", tag, i))
      if shotRows and shotRows[i] then H.screenshot(string.format("%s_help_row%d", tag, i)) end
    end)
  end
  steps[#steps + 1] = H.call(function() H.log("HELP OK (" .. tag .. "): every row's help line, learned and locked") end)
  return H.seqStep(steps)
end

local function hasCmd(char, cmd)
  local rec = 0x1600 + 37 * char
  for i = 0, 3 do
    if H.readByte(rec + 0x16 + i) == cmd then return true end
  end
  return false
end

local slots = {}                        -- slot -> char id
local relmSlot

-- the list as it shows for whoever is selected: the row, its colour, the frame
local function assertList(tag)
  local char = H.readByte(ZCHARID + H.readByte(ZSELINDEX))
  local who = NAMES_CH[char] or string.format("$%02X", char)
  local want = hasCmd(char, CMD_SKETCH) and WHITE or GREY
  H.assertEq(H.readByte(PAINTER_COLOR), want, string.format(
    "%s: %s's Painter row is %s (%s Sketch in the record)", tag, who,
    want == WHITE and "white" or "grey", want == WHITE and "carries" or "no"))
  H.assertEq(H.readByte(THIEF_COLOR), hasCmd(char, CMD_STEAL) and WHITE or GREY, string.format(
    "%s: %s's Treasure Hunter row as before (Steal decides it)", tag, who))
  assertVText(BG3A_V, 2, 21, "Painter", tag .. ": the list's ninth row")
  H.assertEq(vcell(BG3A_V, 2, 21) >> 8, want, string.format(
    "%s: the row's attribute is the colour the scan chose", tag))
  for x = 9, 16 do
    H.assertEq(isLetter(vcell(BG3A_V, x, 21) & 0xff), false, string.format(
      "%s: nothing after 'Painter' on its row ({%d,21})", tag, x))
  end
  -- the frame: Window1 ({1,1} 7x4) gives the reference tiles
  H.assertEq(vcell(BG2A_V, 1, 22), vcell(BG2A_V, 1, 6), string.format(
    "%s: the list window closes at row 22: its bottom-left corner at BG2A {1,22}", tag))
  H.assertEq(vcell(BG2A_V, 9, 22), vcell(BG2A_V, 9, 6), string.format(
    "%s: ... and its bottom-right at {9,22}: vanilla's seven columns", tag))
  H.assertEq(vcell(BG2A_V, 1, 21), vcell(BG2A_V, 1, 5), string.format(
    "%s: the Painter row is inside the frame: left border at {1,21}", tag))
  H.assertEq(vcell(BG2A_V, 9, 7), vcell(BG2A_V, 9, 1), string.format(
    "%s: the list window's top-right corner is at {9,7}", tag))
  H.log(string.format("LIST OK (%s): %s, Painter %s, Treasure Hunter %s", tag, who,
    want == WHITE and "white" or "grey", H.readByte(THIEF_COLOR) == WHITE and "white" or "grey"))
end

local function toRow(row, what)
  return H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == row
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) }, what)
end

local function toChar(slot, what)
  return H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZSELINDEX) == slot()
  end, 900, { H.pressButtons({ "r" }, 2), H.waitFrames(30) }, what)
end

local function refusesGreyRow(tag)
  return {
    toRow(ROW_PAINTER, tag .. ": cursor to the Painter row"),
    H.pressButtons({ "a" }, 2),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(st(), ST_SKILLS, tag .. ": A on the grey Painter row refuses: still on the list")
      H.log("REFUSE OK (" .. tag .. ")")
    end),
  }
end

local steps = {
  H.bootCheckpoint("ultros-won-v1"),
  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),
  H.call(function()
    for s = 0, 3 do
      slots[s] = H.readByte(ZCHARID + s)
      if slots[s] == CHAR_RELM then relmSlot = s end
    end
    H.log(string.format("party: %s %s %s %s", NAMES_CH[slots[0]] or "-", NAMES_CH[slots[1]] or "-",
      NAMES_CH[slots[2]] or "-", NAMES_CH[slots[3]] or "-"))
    H.assertEq(relmSlot ~= nil, true, "ultros-won-v1 seats RELM (her recruitment at Esper Mountain)")
    H.assertEq(hasCmd(CHAR_RELM, CMD_SKETCH), true, "RELM's record carries Sketch")
    local n = 0
    for i = 0, ROWS - 1 do
      local id = rowId(i)
      H.assertEq(id, ID0 + i, string.format("Ot6PaintRowTbl row %d is id $%02X (the name index)", i, ID0 + i))
      H.log(string.format("painter row %d $%02X %s costs %d MP, %s", i, id, nameText(id), costOf(id),
        learned(i) and "learned" or "not learned yet"))
      if learned(i) then n = n + 1 end
    end
    H.assertEq(n > 1 and n < ROWS, true, string.format(
      "RELM L%d here has some rows and not all (%d of 8): both kinds of row draw", H.readByte(RELM_LEVEL), n))
  end),
  H.driveUntil(function() return st() == ST_MAIN and H.readByte(ZCURSOR) == 1 end, 600,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "main menu cursor to Skills"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.waitFrames(10),
  H.driveUntil(function() return H.readByte(ZCURSOR) == relmSlot end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "cursor onto RELM"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "RELM's skills list", 5),
  H.waitFrames(20),
  H.call(function() assertList("RELM") end),

  -- the cursor: row 8 is the Painter row, at its text row; down wraps to 0
  toRow(ROW_PAINTER, "skills cursor to Painter (row 8)"),
  H.waitFrames(10),
  H.call(function()
    local tbl = H.sym("Ot6SkillsCursorPos") & 0x3FFFFF
    H.assertEq(H.readRomByte(tbl + ROW_PAINTER * 2 + 1), 8 * 21 - 4,
      "the Painter row's cursor entry points at BG3A row 21 (y = 8n - 4)")
    for n = 0, 7 do
      local old = H.sym("SkillsCursorPos") & 0x3FFFFF
      H.assertEq(H.readRomByte(tbl + n * 2 + 1), H.readRomByte(old + n * 2 + 1), string.format(
        "the nine-row copy keeps vanilla's row %d", n))
    end
    -- and the jump table: the copy keeps vanilla's eight entries, Painter's is new
    local jt, ojt = H.sym("Ot6SkillsOptionTbl") & 0x3FFFFF, H.sym("SkillsOptionTbl") & 0x3FFFFF
    for n = 0, 7 do
      H.assertEq(H.readRomByte(jt + n * 2) | H.readRomByte(jt + n * 2 + 1) << 8,
        H.readRomByte(ojt + n * 2) | H.readRomByte(ojt + n * 2 + 1) << 8, string.format(
        "the nine-entry Skills jump table keeps vanilla's entry %d", n))
    end
    H.assertEq(H.readRomByte(jt + 16) | H.readRomByte(jt + 17) << 8, H.sym("SkillsOption_08") & 0xFFFF,
      "entry 8 is SkillsOption_08, the Painter page")
    H.screenshot("painterpage_list")
  end),
  H.pressButtons({ "down" }, 2),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.readByte(ZCURSOR), 0, "down from Painter wraps to Espers (the list's nine rows)")
  end),
  H.pressButtons({ "up" }, 2),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.readByte(ZCURSOR), ROW_PAINTER, "up from Espers wraps to Painter")
  end),

  -- the page
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_PAINTER end, 300,
    "the Painter page opens through the player path (menu state $31)", 5),
  H.waitFrames(90),
  H.call(function()
    for i = 0, ROWS - 1 do assertPainterRow(i) end
    assertGeometry("painter page")
    assertVText(BG3B_V, 23, 5, "Painter", "the page's title box")
    for x = 15, 22 do
      H.assertEq(isLetter(vcell(BG3B_V, x, 5) & 0xff), false, string.format(
        "the title row holds only 'Painter': {%d,5}", x))
    end
    H.screenshot("painterpage_rows")
    H.log("RENDER OK: eight rows, the learned ones Ot6PaintName's names at Ot6PaintCostTbl's prices, "
      .. "the rest the locked marker, title 'Painter'")
  end),
  H.pressButtons({ "down" }, 2),
  H.waitFrames(20),
  H.pressButtons({ "down" }, 2),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(st(), ST_PAINTER, "still on the page")
    H.assertEq(H.readByte(ZCURSOR), 2, "one column: two steps down is row 2")
  end),
  H.pressButtons({ "a" }, 2),
  H.waitFrames(30),
  H.call(function() H.assertEq(st(), ST_PAINTER, "A on a row does nothing: still on the page") end),
  helpWalk(H.sym("Ot6PaintPageDescPtrs"), H.sym("Ot6PaintPageDescStr"), learned, ST_PAINTER, "painterpage",
    { [0] = true, [2] = true, [3] = true, [7] = true }),

  -- B: back to the list, the cursor on Painter, nothing of the page left
  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "B returns to the skills list", 5),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(ZCURSOR), ROW_PAINTER, "back on the list, the cursor is on Painter")
    for x = 15, 29 do
      H.assertEq(isLetter(vcell(BG3B_V, x, 5) & 0xff), false, string.format(
        "B cleared the title: BG3B {%d,5} holds no letter", x))
    end
    for k = 0, 2 do
      H.assertEq(vcell(BG1A_V, NAME_COL + k, pageRow(0)) & 0xff, 0, string.format(
        "the page's rows left BG1 screen A in VRAM ({%d,%d})", NAME_COL + k, pageRow(0)))
    end
    assertList("RELM after B")
    H.log("EXIT OK: the cursor on Painter, the title row blank, BG1 clean")
  end),
  -- Espers next: its title and nothing of "Painter"'s
  H.driveUntil(function() return st() == ST_SKILLS and H.readByte(ZCURSOR) == ROW_ESPERS end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(6) }, "cursor to Espers"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() ~= ST_SKILLS end, 300, "Espers opens", 5),
  H.waitFrames(60),
  H.call(function()
    assertVText(BG3B_V, 23, 5, "Espers", "the Espers page's title")
    H.assertEq(isLetter(vcell(BG3B_V, 29, 5) & 0xff), false,
      "no 'r' of Painter after Espers ({29,5})")
    H.log("ESPERS OK: the Espers title alone in the shared box")
  end),
  H.driveUntil(function() return st() == ST_SKILLS end, 600,
    { H.pressButtons({ "b" }, 3), H.waitFrames(20) }, "back to the list"),
  H.waitFrames(20),
}

-- every other seated character, by the shoulder button
for k = 1, 3 do
  local target
  steps[#steps + 1] = H.call(function() target = (relmSlot + k) % 4 end)
  steps[#steps + 1] = toChar(function() return target end, "R to the next character")
  steps[#steps + 1] = H.waitFrames(20)
  steps[#steps + 1] = H.call(function() assertList("slot " .. target) end)
  steps[#steps + 1] = H.cond(function() return slots[target] ~= nil and not hasCmd(slots[target], CMD_SKETCH) end,
    refusesGreyRow("character " .. k .. " after RELM"), {})
  -- LOCKE's Treasure Hunter page in and out under the nine-row list
  steps[#steps + 1] = H.cond(function() return slots[target] ~= nil and hasCmd(slots[target], CMD_STEAL) end, {
    toRow(ROW_THIEF, "cursor to Treasure Hunter"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_THIEF end, 300, "the Treasure Hunter page", 5),
    H.waitFrames(60),
    H.call(function() assertVText(BG3B_V, 15, 5, "Treasure Hunter", "the Treasure Hunter page's title") end),
    H.pressButtons({ "b" }, 3),
    H.waitUntil(function() return st() == ST_SKILLS end, 300, "B back from Treasure Hunter", 5),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(H.readByte(ZCURSOR), ROW_THIEF, "back on the list on Treasure Hunter")
      for x = 15, 29 do
        H.assertEq(isLetter(vcell(BG3B_V, x, 5) & 0xff), false, string.format(
          "B from Treasure Hunter cleared its title: {%d,5}", x))
      end
      assertList("LOCKE after Treasure Hunter")
      H.log("THIEF OK: Treasure Hunter's page in and out, the nine-row list intact")
    end),
  }, {})
end
-- and round to RELM again: her row white, the page opens
steps[#steps + 1] = toChar(function() return relmSlot end, "R round to RELM")
steps[#steps + 1] = H.waitFrames(20)
steps[#steps + 1] = H.call(function() assertList("RELM again") end)
steps[#steps + 1] = toRow(ROW_PAINTER, "cursor to Painter")
steps[#steps + 1] = H.pressButtons({ "a" }, 2)
steps[#steps + 1] = H.waitUntil(function() return st() == ST_PAINTER end, 300, "the page again", 5)
steps[#steps + 1] = H.waitFrames(60)
steps[#steps + 1] = H.call(function()
  for i = 0, ROWS - 1 do assertPainterRow(i) end
  H.log("AGAIN OK: the page after the round")
end)
steps[#steps + 1] = H.pressButtons({ "b" }, 3)
steps[#steps + 1] = H.waitUntil(function() return st() == ST_SKILLS end, 300, "back", 5)
-- out to the main menu and in again through Skills
steps[#steps + 1] = H.pressButtons({ "b" }, 3)
steps[#steps + 1] = H.waitUntil(function() return st() == ST_MAIN end, 600, "main menu", 5)
steps[#steps + 1] = H.waitFrames(20)
steps[#steps + 1] = H.driveUntil(function() return st() == ST_MAIN and H.readByte(ZCURSOR) == 1 end, 600,
  { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "main menu cursor to Skills")
steps[#steps + 1] = H.pressButtons({ "a" }, 2)
steps[#steps + 1] = H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5)
for s = 0, 3 do
  steps[#steps + 1] = H.driveUntil(function() return st() == ST_CHAR and H.readByte(ZCURSOR) == s end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "character cursor")
  steps[#steps + 1] = H.pressButtons({ "a" }, 2)
  steps[#steps + 1] = H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills list from the main menu", 5)
  steps[#steps + 1] = H.waitFrames(20)
  steps[#steps + 1] = H.call(function() assertList("main menu slot " .. s) end)
  steps[#steps + 1] = H.pressButtons({ "b" }, 3)
  steps[#steps + 1] = H.waitUntil(function() return st() == ST_MAIN end, 600, "main menu", 5)
  steps[#steps + 1] = H.waitFrames(20)
  steps[#steps + 1] = H.driveUntil(function() return st() == ST_MAIN and H.readByte(ZCURSOR) == 1 end, 600,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "main menu cursor to Skills")
  steps[#steps + 1] = H.pressButtons({ "a" }, 2)
  steps[#steps + 1] = H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5)
end
steps[#steps + 1] = H.call(function() H.log("ROUND OK: every seated character's list from the main menu") end)

H.run({ maxFrames = 40000 }, steps)
