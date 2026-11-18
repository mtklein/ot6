-- @suite
-- menu_thiefpage.lua -- the field Skills->Treasure Hunter page.
--
-- The skills list's 8th row (the page's internal name stays "thief") reads
-- Locke's battle command's name, BattleCmdName's Steal record ("TresHnt"),
-- inside the list window's vanilla seven columns (#549, the owner: "the same
-- abbrev we do in the combat menus, much like SwdTech above for cyan").  It is
-- gated like every other row by the character's own battle commands, and by
-- the relic rewrite battle makes: a worn Thief Glove turns Steal into
-- Capture, which opens no list in battle, so the row greys and A on it
-- refuses.  A on a white row opens a field info page in the Blitz page's
-- shape: one column, name + MP price per row, B backs out, A is a no-op.
-- Eight rows, the battle list's order read a column at a time (ot6_thief.asm
-- Ot6ThiefRowTbl): Steal, Filch and Bestow from the moment Locke joins; Mug,
-- Trickshot, Dismantle, Appraise and Master's Mark once their story beat's
-- event switch is set (#382), the Blitz page's locked marker before that.
-- The page's own title box reads "Treasure Hunter" in full (its own wide
-- box, put back by B).
--
-- Names come from the ROM's own Ot6ThiefName records (one per row, in
-- order).  Prices come from the same two authorities the battle charge
-- reads: Steal from Ot6StealCost's immediate, the rest from
-- Ot6ThiefCostTbl's (key, cost) records -- not Ot6AbilityCostTbl, which keys
-- $55-$5c as SwdTech boost rows.  There is no probe-icon column.
--
-- Geometry is the Blitz page's: rows 1/3/.../15 (odd rows only, nothing past
-- row 15), name at column 3 flush against the cursor at x=8
-- (cursor_x = 8*col - 16), price right-aligned at column 16.
--
-- Boot: cold Continue of ultros-won-v1, beside Esper Mountain's save point
-- (#549 moved it off the celes_freed savestate, which every ROM change
-- stales, onto a tracked battery): TERRA, LOCKE, STRAGO, RELM seated, LOCKE
-- with some of his later rows learned and Master's Mark not.  LOCKE carries
-- Steal (his own record) so his row is white and the page opens; TERRA does
-- not, so hers is grey and A on it refuses.  Then the Thief Glove: no save
-- the line makes holds one, so one is put in the bag (a declared two-byte
-- write, tools/state_write_waivers.txt), LOCKE puts it on through the Relic
-- menu, his row is grey and refuses, and in the next random battle his
-- command rows hold Capture ($06) and no Steal ($05): the field agrees with
-- the battle.  The battle is fought through the Fight menu.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE, ZCURSOR, ZSELINDEX = 0x26, 0x4b, 0x28
local ZCHARID = 0x69                    -- zCharID::Slot1..4 (menu_ram.inc)
local THIEF_ROW_COLOR = 0x80            -- zSkillsTextColor::Thief (menu_ram.inc)
local CHAR_LOCKE, CHAR_TERRA = 0x01, 0x00   -- TERRA: the grey control
local THIEF_GLOVE, CMD_CAPTURE = 0xcf, 0x06
local RELIC_CAPTURE = 0x40              -- ItemProp+10 / $11d6: Steal -> Capture
local BATTLE_CMD_STEAL = 0x05
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_THIEF = 0x05, 0x06, 0x0a, 0x30
local SKILLS_ROW_THIEF = 7              -- Espers Magic SwdTech Blitz Lore Rage Dance THIEF

local function st() return H.menuRunning() and H.readByte(ZMENUSTATE) or -1 end

-- ---- the name on the list and on the page's title box (VRAM, what shows) ----
-- Locke's row is "Treasure Hunter", the word he insists on in the story, on
-- the Skills list (BG3 screen A, row 19 from column 2) and in the page's
-- title box (BG3 screen B, row 5 from column 15).  Both boxes are widened for
-- it: the list window to 15 tiles (its top-right corner at BG2A {17,7}) and
-- the page draws a 15-tile title box over the shared 7-tile one (corners at
-- BG2B {14,4} and {30,4}), which the B exit puts back.
-- VRAM word addresses: BG2 screen A $1000, B $1400; BG3 A $4000, B $4400.
local VR = emu.memType.snesVideoRam
local function vcell(base, x, y) return emu.readWord((base + y * 32 + x) * 2, VR) end
local BG2A_V, BG2B_V, BG3A_V, BG3B_V = 0x1000, 0x1400, 0x4000, 0x4400
local TITLE = "Treasure Hunter"          -- the page's own title box
-- the list row: the battle command window's name for Steal
local CMDNAMES = H.sym("BattleCmdName") & 0x3FFFFF
local function rowName()
  local t = {}
  for k = 0, 6 do t[#t + 1] = H.readRomByte(CMDNAMES + BATTLE_CMD_STEAL * 7 + k) end
  return t
end
local function rowText()
  local s = ""
  for _, b in ipairs(rowName()) do
    if b >= 0x80 and b <= 0x99 then s = s .. string.char(65 + b - 0x80)
    elseif b >= 0x9a and b <= 0xb3 then s = s .. string.char(97 + b - 0x9a) else s = s .. "." end
  end
  return s
end
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
local box0 = {}                          -- BG2B rows 4-6 before the page opens

-- BG1 screen A tilemap shadow (wBG1Tiles::ScreenA = $7e3849, menu_ram.inc):
-- 2 bytes per cell (char, color), 64 bytes per row; cell(x,y) = char byte.
local BG1A = 0x3849
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end

-- menu text codec: 'A'=$80.. 'a'=$9a.. '0'=$b4.. ' '=$ff.
local T = { M = 0x8c, P = 0x8f, SP = 0xff }
local MP_SUFFIX = { T.SP, T.M, T.P }
local ZERO_CHAR, DIGIT9 = 0xb4, 0xbd
local PAD = 0xff                        -- fixed_length_en.json: 0xFF = {pad}

-- ---- the ROM tables this page must agree with ----
local NAMES = H.sym("Ot6ThiefName") & 0x3FFFFF
local ROWTBL = H.sym("Ot6ThiefRowTbl") & 0x3FFFFF
local NAME_SIZE = 10                    -- Ot6ThiefName's record
local THIEF_ATK0 = 0x56                 -- Steal
local ROWS = 8
local function rowId(i) return H.readRomByte(ROWTBL + i * 5) end
-- learned: the row's switch (record +3 the byte off $1E80, +4 the bit; 0 =
-- at join), read off the save
local function learned(i)
  local bit = H.readRomByte(ROWTBL + i * 5 + 4)
  return bit == 0 or (H.readByte(0x1E80 + H.readRomByte(ROWTBL + i * 5 + 3)) & bit) ~= 0
end
local LOCKED = H.sym("Ot6BlitzLockedTiles") & 0x3FFFFF
local function lockedBytes()
  local t = {}
  for i = 0, 15 do
    local b = H.readRomByte(LOCKED + i)
    if b == 0 then break end
    t[#t + 1] = b
  end
  return t
end
local function nameBytes(i)
  local t = {}
  for k = 0, NAME_SIZE - 1 do t[k + 1] = H.readRomByte(NAMES + i * NAME_SIZE + k) end
  return t
end
local function nameText(i)              -- for the log only
  local s = ""
  for _, b in ipairs(nameBytes(i)) do
    if b == PAD then s = s .. "."
    elseif b >= 0x80 and b <= 0x99 then s = s .. string.char(65 + b - 0x80)
    elseif b >= 0x9a and b <= 0xb3 then s = s .. string.char(97 + b - 0x9a)
    else s = s .. "?" end
  end
  return s
end

-- Steal: Ot6StealCost is `lda #imm / rtl`; read the immediate at the
-- source.  Filch/Bestow: Ot6ThiefCostTbl, (key, cost) pairs, $ff-terminated.
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
local function thiefRow(i) return 1 + i * 2 end   -- odd rows 1..15 (#43)

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

-- Even rows are four scanlines in this window and rows past 15 are outside
-- it, so nothing may land on either.  Column 30 is the window's right
-- border; columns 0-2 the cursor gutter on every row.
local function assertGeometry(what)
  for y = 0, 27 do
    if y % 2 == 0 or y > 15 then
      assertRowBlank(y, string.format(
        "%s: row %d must be empty (%s)", what, y,
        (y % 2 == 0) and "even: four scanlines" or "outside the window"))
    end
  end
  for y = 1, 15, 2 do
    for _, x in ipairs({ 0, 1, 2, 13, 14, 15, 30, 31 }) do
      H.assertEq(cell(x, y), 0, string.format(
        "%s: {%d,%d} must stay blank -- %s", what, x, y,
        (x <= 2) and "the cursor sprite's gutter"
          or (x >= 30) and "the window's border column"
          or "the gap between name and price (NO icon column on this page)"))
    end
    for x = COST_COL + 5, 29 do
      H.assertEq(cell(x, y), 0, string.format(
        "%s: {%d,%d} is past the price field", what, x, y))
    end
  end
end

-- y = 116 + n*12 -> tilemap row (y-116)/6 + 1.
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
  local id, y = rowId(i), thiefRow(i)
  if not learned(i) then
    assertRun(NAME_COL, y, lockedBytes(), string.format("thief row %d ($%02X, not learned) draws the locked "
      .. "marker", i, id))
    for x = COST_COL, COST_COL + 1 do
      local c = cell(x, y)
      H.assertEq(c >= ZERO_CHAR and c <= DIGIT9, false, string.format("thief row %d (locked) draws no price", i))
    end
    return
  end
  assertRun(NAME_COL, y, nameBytes(i),
    string.format("thief row %d name %s", i, nameText(i)))
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

local lockeSlot, terraSlot = nil, nil

H.run({ maxFrames = 120000 }, {
  H.bootCheckpoint("ultros-won-v1"),

  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),
  H.call(function()
    local ids = {}
    for s = 0, 3 do
      local id = H.readByte(ZCHARID + s)
      ids[#ids + 1] = string.format("slot %d = char $%02x", s, id)
      if id == CHAR_LOCKE and lockeSlot == nil then lockeSlot = s end
      if id == CHAR_TERRA and terraSlot == nil then terraSlot = s end
    end
    H.log("party: " .. table.concat(ids, ", "))
    H.assertEq(lockeSlot ~= nil, true, "ultros-won-v1's party contains LOCKE")
    H.assertEq(terraSlot ~= nil, true, "ultros-won-v1's party contains TERRA, the grey control")
    local function hasSteal(char)
      local rec = 0x1600 + 37 * char
      for i = 0, 3 do
        if H.readByte(rec + 0x16 + i) == BATTLE_CMD_STEAL then return true end
      end
      return false
    end
    H.assertEq(hasSteal(CHAR_LOCKE), true,
      "LOCKE's own record carries BATTLE_CMD::STEAL -- nothing is installed")
    H.assertEq(hasSteal(CHAR_TERRA), false,
      "TERRA's record does not carry Steal -- she is the gray-row control")
    for i = 0, ROWS - 1 do
      H.log(string.format("thief row %d $%02X %s costs %d MP, %s", i, rowId(i), nameText(i), costOf(rowId(i)),
        learned(i) and "learned" or "not learned yet"))
    end
    local later, locked = 0, 0
    for i = 3, ROWS - 1 do
      if learned(i) then later = later + 1 else locked = locked + 1 end
    end
    H.assertEq(later > 0 and locked > 0, true, string.format(
      "the save has later rows learned (%d) and rows still locked (%d): both kinds draw", later, locked))
    H.assertEq(H.readByte(0x1600 + 37 * CHAR_LOCKE + 0x23) ~= THIEF_GLOVE
      and H.readByte(0x1600 + 37 * CHAR_LOCKE + 0x24) ~= THIEF_GLOVE, true, "LOCKE wears no Thief Glove yet")
  end),
  H.driveUntil(function() return st() == ST_MAIN and H.readByte(ZCURSOR) == 1 end, 600,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "main menu cursor to Skills"),
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
    for k, b in ipairs(rowName()) do
      H.assertEq(vcell(BG3A_V, 1 + k, 19) & 0xff, b, string.format(
        "Skills list row 8 reads the battle command's name '%s': letter %d at {%d,19}", rowText(), k, 1 + k))
    end
    H.assertEq(vcell(BG2A_V, 9, 7), vcell(BG2A_V, 9, 1),
      "the list window is vanilla's 7 tiles wide: its top-right corner at BG2A {9,7} "
      .. "is the Espers/Magic window's corner tile ({9,1})")
    for y = 4, 6 do
      for x = 0, 31 do box0[#box0 + 1] = vcell(BG2B_V, x, y) end
    end
    H.screenshot("thiefpage_list")
    H.log("LIST OK: Locke's row reads '" .. rowText() .. "' (BattleCmdName) inside the 7-tile list window")
  end),

  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == SKILLS_ROW_THIEF
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "skills cursor to Thief (index 7)"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_THIEF end, 300,
    "thief page open via the player path (menu state $30)", 5),
  H.waitFrames(90),                         -- draws + DMA settle

  H.call(function()
    for i = 0, ROWS - 1 do assertThiefRow(i) end
    assertGeometry("thief page")
    for n = 0, ROWS - 1 do assertCursorGutter(n, "thief page") end
    assertVText(BG3B_V, 15, 5, TITLE, "page title box")
    H.assertEq(vcell(BG2B_V, 14, 4), vcell(BG2B_V, 1, 1),
      "the page's title box opens at BG2B {14,4}: the description window's "
      .. "top-left corner tile ({1,1})")
    H.assertEq(vcell(BG2B_V, 30, 4), vcell(BG2B_V, 30, 1),
      "the page's title box closes at BG2B {30,4}: the top-right corner tile")
    H.log("TITLE OK: the page's title box reads '" .. TITLE .. "' (BG2B {14,4}-{30,6})")
    H.screenshot("thiefpage_rows")
    H.log("RENDER OK: Skills->Thief for a REAL LOCKE -- eight rows, each learned "
      .. "one Ot6ThiefName's own name and the charge's own price, each other one "
      .. "the locked marker, no icon column, every cell inside rows 1..15 and "
      .. "clear of the gutter and border")
  end),

  H.pressButtons({ "down" }, 2),
  H.waitFrames(20),
  H.pressButtons({ "down" }, 2),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(st(), ST_THIEF, "still on the thief page")
    H.assertEq(H.readByte(ZCURSOR), 2,
      "one column: two steps down is row 2 (Bestow)")
    for n = 0, ROWS - 1 do assertCursorGutter(n, "cursor on row 2") end
  end),
  helpWalk(H.sym("Ot6ThiefPageDescPtrs"), H.sym("Ot6ThiefPageDescStr"), learned, ST_THIEF, "thiefpage",
    { [0] = true, [3] = true, [6] = true, [7] = true }),

  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_SKILLS end, 300,
    "B returns to the skills list", 5),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(THIEF_ROW_COLOR), 0x20,
      "back on the list, the Thief row is still LOCKE-white -- the list "
      .. "redraw (_c34d27/ReloadSkillsMenu) recomputed the colors")
    local i = 0
    for y = 4, 6 do
      for x = 0, 31 do
        i = i + 1
        H.assertEq(vcell(BG2B_V, x, y), box0[i], string.format(
          "B put the shared 7-tile title box back: BG2B {%d,%d} as before the "
          .. "page opened (every other page titles at column 23 inside it)", x, y))
      end
    end
    for x = 15, 29 do
      local t = vcell(BG3B_V, x, 5) & 0xff
      H.assertEq(t >= 0x80 and t <= 0xb3, false, string.format(
        "B cleared the long title: BG3B {%d,5} holds no letter (the next "
        .. "page writes only its own short title at column 23)", x))
    end
    for _, cyc in ipairs({ 0, 1, 2 }) do
      H.assertEq(vcell(0x0000, NAME_COL + cyc, thiefRow(0)) & 0xff, 0, string.format(
        "the page's rows left BG1 screen A in VRAM ({%d,%d}): the list "
        .. "must not show them through", NAME_COL + cyc, thiefRow(0)))
    end
    H.log("EXIT OK: the shared title box, an empty title row and a clean BG1 behind the list")
  end),

  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZSELINDEX) == terraSlot
  end, 900, { H.pressButtons({ "r" }, 2), H.waitFrames(30) },
    "shoulder R to TERRA"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(THIEF_ROW_COLOR), 0x24,
      "Thief row gray for TERRA -- no Steal in her record")
  end),
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == SKILLS_ROW_THIEF
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "TERRA's cursor to the Thief row"),
  H.pressButtons({ "a" }, 2),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(st(), ST_SKILLS,
      "A on the gray Thief row refuses (SelectSkillsOption's $20 gate) -- "
      .. "still on the skills list, not on the thief page")
    H.log("GATING OK: white for the Steal owner and the page opens; gray for "
      .. "everyone else and A goes nowhere")
  end),

  -- the Thief Glove: Capture in battle, so no page in the field
  H.driveUntil(function() return H.hasControl() and not H.menuRunning() end, 1800,
    { H.pressButtons({ "b" }, 3), H.waitFrames(30) }, "out of the menu"),
  H.waitFrames(20),
  H.call(function()
    -- the static half: the glove's relic-effects byte carries the rewrite
    -- (that no esper rung does is the build's esper_ladder check)
    local ip = H.sym("ItemProp") & 0x3FFFFF
    H.assertEq(H.readRomByte(ip + THIEF_GLOVE * 30 + 10) & RELIC_CAPTURE, RELIC_CAPTURE,
      "the Thief Glove's relic-effects byte (ItemProp+10) carries Steal -> Capture ($40)")
    -- the declared write (the header): one Thief Glove into an empty bag slot
    local slot
    for i = 0, 255 do
      if slot == nil and H.readByte(0x1869 + i) == 0xff then slot = i end
    end
    H.assertEq(slot ~= nil, true, "the bag has an empty slot")
    H.writeByte(0x1869 + slot, THIEF_GLOVE)
    H.writeByte(0x1969 + slot, 1)
    H.log(string.format("[thiefpage] declared: a Thief Glove in bag slot %d", slot))
  end),
  H.equipLoadout(CHAR_LOCKE, { { 4, THIEF_GLOVE } }, { tag = "LOCKE: Thief Glove" }),
  H.waitUntil(function() return H.hasControl() and not H.menuRunning() end, 1800, "back in the field", 5),
  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu again"),
  H.waitFrames(20),
  H.driveUntil(function() return st() == ST_MAIN and H.readByte(ZCURSOR) == 1 end, 600,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "main menu cursor to Skills"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.waitFrames(10),
  H.driveUntil(function() return st() == ST_CHAR and H.readByte(ZCURSOR) == lockeSlot end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "cursor onto LOCKE"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "LOCKE's skills list with the glove", 5),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(H.readByte(THIEF_ROW_COLOR), 0x24,
      "with the Thief Glove LOCKE's row is grey: Capture in battle, no list")
    H.screenshot("thiefpage_glove")
  end),
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == SKILLS_ROW_THIEF
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) }, "cursor to the grey row"),
  H.pressButtons({ "a" }, 2),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(st(), ST_SKILLS, "A on the gloved LOCKE's grey row refuses")
    H.log("GLOVE OK: grey and refused with the Thief Glove on")
  end),
  H.driveUntil(function() return H.hasControl() and not H.menuRunning() end, 1800,
    { H.pressButtons({ "b" }, 3), H.waitFrames(30) }, "out of the menu"),
  H.paceToEncounter("thiefpage", 0, { { 6, 45 }, { 4, 45 } }),
  H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
  H.waitFrames(30),
  H.call(function()
    local cmds
    for a = 0, 3 do
      if H.readByte(0x3ED8 + a * 2) == CHAR_LOCKE then
        cmds = {}
        for r = 0, 3 do cmds[#cmds + 1] = H.readByte(0x202E + a * 12 + r * 3) end
      end
    end
    H.assertEq(cmds ~= nil, true, "LOCKE is in the battle")
    H.log(string.format("battle commands: LOCKE %02X %02X %02X %02X", cmds[1], cmds[2], cmds[3], cmds[4]))
    local cap, steal = false, false
    for _, c in ipairs(cmds) do
      if c == CMD_CAPTURE then cap = true end
      if c == BATTLE_CMD_STEAL then steal = true end
    end
    H.assertEq(cap and not steal, true,
      "in battle the gloved LOCKE has Capture and no Steal: no list, as the field said")
    H.log("BATTLE OK: the field menu and the battle agree")
  end),
  H.fightBattleByMenu(40000),
})
