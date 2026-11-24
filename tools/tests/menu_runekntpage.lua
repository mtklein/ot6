-- @suite
-- menu_runekntpage.lua -- the field Skills list's tenth row, RuneKnt, and
-- Celes's page behind it (#563), with Break Blade learned.
--
-- The page is the counterpart of Locke's Treasure Hunter page and Relm's
-- Painter page (menu_thiefpage, menu_painterpage): one column of rows, the
-- Rune Knight's list behind Runic (ot6_rune.asm) in the battle list's order,
-- each row its name and MP price.  B backs out, A does nothing.  Unlike
-- theirs the rows are not fixed: Runic, a blade row for each element of
-- which the field Magic list has a spell for the character, Break Blade.
--
-- Every number comes from the save and the ROM's tables, never from a copy
-- in this file.  The suite's model of the page (modelRows):
--   the spells     for a character, what Ot6FieldSpellKnown grants: the
--                  learned table ($1A6E + 54 x actor), CELES's Break from
--                  level 13, the worn esper's five spells (GenjuProp), the
--                  worn pieces' grants (Ot6ItemGrantTbl); for GOGO, the
--                  union over the other seated members, as the field Magic
--                  list has it for him (skills.asm _50c5), with his own
--                  stone's and gear's once he is revealed as Leo and has
--                  picked Summon (Ot6FieldLeoMagic)
--   the rows       Runic (free: no price drawn); then, in element bit order,
--                  a blade row for each element some such spell carries
--                  (MagicProp+1), priced at the cheapest of them (MagicProp+5)
--                  through the character's Economizer (1) or Gold Hairpin
--                  (half, rounded up): ItemProp+11 of the six worn pieces,
--                  the byte the field Magic list prices by ($11D7); six
--                  blades at most; then Break Blade at 99 when event switch
--                  $0266 or $00A4 is set, and the locked marker when not
--                  (menu_runekntpage_wob covers that look)
--   the names      Ot6RuneName, ten bytes per id from $C8 (the records the
--                  battle list draws): Runic is record 8, a blade 9 + its bit
--   the help line  tools/kit_pages.py's RUNE table in the ROM
--                  (Ot6RunePageDescPtrs): line n for row id $D0 + n
--   the Skills row BattleCmdName's record $0B, white when the character's
--                  record carries command $0B and a hand holds a weapon whose
--                  ItemProp+19 has bit 7 (battle greys the command without
--                  one: UpdateCmd_01), grey otherwise
--
-- Boot: cold Continue of wor-opera-v1, on the World of Ruin's map beside the
-- Falcon by the Opera House (CELES, STRAGO, RELM and GOGO seated; switch
-- $00A4 set, so Break Blade is learned).  Then, all through the controller,
-- nothing written:
--   1. CELES's Skills list draws the RuneKnt row at BG3A {2,23} inside the
--      list window, which now closes at row 24; the cursor reaches row 9
--      (y = 180) and wraps (screenshot runekntpage_skills);
--   2. A opens menu state $32: the rows equal the model, names and prices,
--      in the Thief page's geometry, the title box reads the command's name,
--      the cursor walks only the rows there are, A does nothing, and the
--      help window shows each row's line (screenshots runekntpage_page, and
--      runekntpage_help_row<n> of a blade row's line and Break Blade's);
--   3. B returns to the list on RuneKnt with the title row blank and BG1
--      clean; Espers then opens with its own title;
--   4. every other seated character: the row's colour by the rule above,
--      and A on a grey row refuses;
--   5. the page follows her esper: Ifrit put on (H.equipEsper) adds what
--      Ifrit lends, Ifrit handed to another member leaves her own spells'
--      rows (screenshot runekntpage_noesper);
--   6. GOGO takes the command in his Status picker: his row turns white and
--      his page lists the seated party's union (screenshot runekntpage_gogo);
--   7. CELES's weapons come off through Equip > Remove: with both hands
--      empty the row is grey and A refuses; a weapon back, it is white.
-- Not reached: the Economizer's and Gold Hairpin's prices (the model has
-- them; no save on the line holds either piece).
-- Reds (the ROM before the page, the page unhooked, ten byte-patch mutants
-- of its arms, mutants.py): build/attempts/wt/v051-spellblade/sb4/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE, ZCURSOR, ZSELINDEX, ZCHARID = 0x26, 0x4b, 0x28, 0x69
local RUNE_COLOR = 0x82                 -- zSkillsTextColor::RuneKnt
local CELES, STRAGO, GOGO = 0x06, 0x07, 0x0c
local CMD_STEAL, CMD_RUNIC, CMD_SKETCH, CMD_MIMIC, CMD_SUMMON = 0x05, 0x0b, 0x0d, 0x12, 0x19
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_RUNE, ST_GOGO_LIST = 0x05, 0x06, 0x0a, 0x32, 0x6a
local ROW_ESPERS, ROW_RUNE = 0, 9
local WHITE, GREY = 0x20, 0x24
local IFRIT = 1                         -- esper index: $1A69 bit 1, +$1E of a record
local BREAK, SCAN = 0x0c, 0x18          -- spell ids
local IDX_RUNIC, IDX_BLADE, IDX_BREAK, IDX_LOCKED = 0, 1, 9, 10   -- a row's id less $D0
local BREAK_MP, BLADES = 99, 6
local NAMES_CH = { [0] = "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO",
  "RELM", "SETZER", "MOG", "GAU", "GOGO", "UMARO" }
local ROWNAME = { [0] = "Runic", "Fire", "Ice", "Bolt", "Poison", "Wind", "Pearl", "Earth", "Water", "Break Blade",
  "Break Blade (locked)" }

local function st() return H.menuRunning() and H.readByte(ZMENUSTATE) or -1 end

-- VRAM (what shows): word addresses, BG1 A $0000; BG2 A $1000; BG3 A $4000, B $4400
local VR = emu.memType.snesVideoRam
local function vcell(base, x, y) return emu.readWord((base + y * 32 + x) * 2, VR) end
local BG1A_V, BG2A_V, BG3A_V, BG3B_V = 0x0000, 0x1000, 0x4000, 0x4400
local function isLetter(t) return t >= 0x80 and t <= 0xb3 end
local function enc(ch)                  -- menu text codec, letters and space
  local b = ch:byte()
  if ch == " " then return 0xff end
  if b >= 65 and b <= 90 then return 0x80 + b - 65 end
  return 0x9a + b - 97
end

-- BG1 screen A tilemap shadow (wBG1Tiles::ScreenA = $7e3849): tile, attribute
local BG1A = 0x3849
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end
local function attr(x, y) return H.readByte(BG1A + x * 2 + y * 64 + 1) end
local ZERO_CHAR, PAD = 0xb4, 0xff
local MP_SUFFIX = { 0xff, 0x8c, 0x8f }  -- " MP"
local NAME_COL, COST_COL, NAME_SIZE = 3, 16, 10
local TEXT_DEFAULT, TEXT_BLUE = 0x20, 0x2c   -- BG1_TEXT_COLOR

-- ---- the ROM's tables ----
local MAGIC_PROP = H.sym("MagicProp") & 0x3FFFFF
local ITEM_PROP = H.sym("ItemProp") & 0x3FFFFF
local GENJU_PROP = H.sym("GenjuProp") & 0x3FFFFF
local ITEM_GRANTS = H.sym("Ot6ItemGrantTbl") & 0x3FFFFF
local RUNE_NAME = H.sym("Ot6RuneName") & 0x3FFFFF
local CMDNAMES = H.sym("BattleCmdName") & 0x3FFFFF
local LOCKED = H.sym("Ot6BlitzLockedTiles") & 0x3FFFFF
local DESC_PTRS, DESC_STR = H.sym("Ot6RunePageDescPtrs") & 0x3FFFFF, H.sym("Ot6RunePageDescStr") & 0x3FFFFF

local function rec(c) return 0x1600 + 37 * c end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function breakLearned() return sw(0x0266) == 1 or sw(0x00A4) == 1 end
local function elements(spell) return H.readRomByte(MAGIC_PROP + spell * 14 + 1) end
local function hasCmd(c, cmd)
  for i = 0, 3 do if H.readByte(rec(c) + 0x16 + i) == cmd then return true end end
  return false
end
local function worn(c) return H.readByte(rec(c) + 0x1E) end
local function posOf(c) return (H.readByte(0x1850 + c) >> 3) & 3 end
local function seated(c)
  local pb = H.readByte(0x1850 + c)
  return (pb & 7) ~= 0 and (pb & 7) == (H.readByte(0x1A6D) & 7)
end
local function record(cmd)              -- BattleCmdName's seven cells
  local t = {}
  for i = 0, 6 do t[#t + 1] = H.readRomByte(CMDNAMES + cmd * 7 + i) end
  return t
end
-- a hand's piece allows Runic: a weapon (ItemProp's type 1) whose special
-- effects (+19) carry bit 7, as UpdateEquip stores it for UpdateCmd_01
local function runicItem(item)
  local p = ITEM_PROP + item * 30
  return (H.readRomByte(p) & 7) == 1 and (H.readRomByte(p + 19) & 0x80) ~= 0
end
local function runicHand(c)
  return runicItem(H.readByte(rec(c) + 0x1F)) or runicItem(H.readByte(rec(c) + 0x20))
end
local function wantColour(c) return (hasCmd(c, CMD_RUNIC) and runicHand(c)) and WHITE or GREY end
-- relic effects 3 of the six worn pieces (UpdateEquip's $11D7): $40 the
-- Economizer, $20 the Gold Hairpin
local function relicBits(c)
  local v = 0
  for s = 0, 5 do v = v | H.readRomByte(ITEM_PROP + H.readByte(rec(c) + 0x1F + s) * 30 + 11) end
  return v
end
local function priced(c, mp)
  local r = relicBits(c)
  if (r & 0x40) ~= 0 then return 1 end
  if (r & 0x20) ~= 0 then return (mp + 1) // 2 end
  return mp
end

-- what a record's worn stone and worn pieces lend: the stone's five spells
-- (GenjuProp) and Ot6ItemGrantTbl's pairs.  `esper` stands in for the worn
-- stone when given (false: none), for the what-if the preconditions ask
local function lent(c, id, esper)
  local e = worn(c)
  if esper ~= nil then e = esper or 0xFF end
  if e < 0x80 then
    for k = 1, 9, 2 do if H.readRomByte(GENJU_PROP + e * 11 + k) == id then return true end end
  end
  for i = 0, 63 do
    local item = H.readRomByte(ITEM_GRANTS + i * 2)
    if item == 0xFF then break end
    if H.readRomByte(ITEM_GRANTS + i * 2 + 1) == id then
      for s = 0, 5 do if H.readByte(rec(c) + 0x1F + s) == item then return true end end
    end
  end
  return false
end
-- Ot6FieldSpellKnown for one record
local function knows(c, id, esper)
  local actor = H.readByte(rec(c))
  if actor == CELES and id == BREAK and H.readByte(rec(CELES) + 8) >= 13 then return true end
  if actor == STRAGO and id == SCAN then return true end
  if H.readByte(0x1A6E + 54 * actor + id) == 0xFF then return true end
  return lent(c, id, esper)
end
local function seatedChars()            -- the active party, in menu order
  local t = {}
  for c = 0, 15 do if seated(c) and (H.readByte(0x1850 + c) & 0x40) ~= 0 then t[#t + 1] = c end end
  table.sort(t, function(a, b) return posOf(a) < posOf(b) end)
  return t
end
-- the spells the field Magic list has for a character (skills.asm _c350a2):
-- Ot6FieldSpellKnown's; for GOGO the other seated members', and his own
-- stone's and gear's once he is revealed as Leo (switch $00E0) with Summon
-- among his commands (Ot6FieldLeoMagic)
local function fieldSpells(c, esper)
  local t = {}
  for id = 0, 0x35 do
    if H.readByte(rec(c)) == GOGO then
      if sw(0x00E0) == 1 and hasCmd(c, CMD_SUMMON) and lent(c, id) then t[id] = true end
      for _, o in ipairs(seatedChars()) do
        if o ~= c and H.readByte(rec(o)) < GOGO and knows(o, id) then t[id] = true end
      end
    elseif knows(c, id, esper) then
      t[id] = true
    end
  end
  return t
end
-- the page's rows: { id less $D0, price }
local function modelRows(c, esper)
  local known, cheapest = fieldSpells(c, esper), {}
  for id = 0, 0x35 do
    if known[id] then
      local mp = H.readRomByte(MAGIC_PROP + id * 14 + 5)
      for b = 0, 7 do
        if (elements(id) & (1 << b)) ~= 0 and (cheapest[b] == nil or mp < cheapest[b]) then cheapest[b] = mp end
      end
    end
  end
  local rows = { { IDX_RUNIC, 0 } }
  for b = 0, 7 do
    if cheapest[b] ~= nil and #rows < 1 + BLADES then rows[#rows + 1] = { IDX_BLADE + b, priced(c, cheapest[b]) } end
  end
  rows[#rows + 1] = breakLearned() and { IDX_BREAK, BREAK_MP } or { IDX_LOCKED, 0 }
  return rows
end
local function said(rows)
  local t = {}
  for _, r in ipairs(rows) do t[#t + 1] = string.format("%s:%d", ROWNAME[r[1]], r[2]) end
  return table.concat(t, " ")
end
local function hasRow(rows, idx)
  for _, r in ipairs(rows) do if r[1] == idx then return r end end
end

local function nameBytes(idx)
  local t = {}
  for k = 0, NAME_SIZE - 1 do t[k + 1] = H.readRomByte(RUNE_NAME + (idx + 8) * NAME_SIZE + k) end
  return t
end
local function lockedBytes()
  local t = {}
  for i = 0, 15 do
    local b = H.readRomByte(LOCKED + i)
    if b == 0 then break end
    t[#t + 1] = b
  end
  return t
end
local function assertRun(x0, y, bytes, what)
  for i, b in ipairs(bytes) do
    H.assertEq(cell(x0 + i - 1, y), b, string.format("%s: cell {%d,%d}", what, x0 + i - 1, y))
  end
end

-- the open page against the model: names, prices, the rows there are not,
-- the list buffer the help window reads, the cursor's rows
local function assertPage(tag)
  local c = H.readByte(ZCHARID + H.readByte(ZSELINDEX))
  local rows = modelRows(c)
  H.assertEq(H.readByte(0x11D7) & 0x60, relicBits(c) & 0x60, string.format(
    "%s: the menu's MP relic bits ($11D7: Economizer $40, Gold Hairpin $20) are %s's worn pieces'", tag, NAMES_CH[c]))
  for i = 0, 7 do
    local y, r = 1 + i * 2, rows[i + 1]
    if r == nil then
      for x = 0, 31 do
        H.assertEq(cell(x, y), 0, string.format("%s: row %d is past the %d rows: nothing drawn at {%d,%d}", tag, i,
          #rows, x, y))
      end
      H.assertEq(H.readByte(0x9d89 + i), 0xFF, string.format("%s: row %d holds no help line", tag, i))
    elseif r[1] == IDX_LOCKED then
      assertRun(NAME_COL, y, lockedBytes(), string.format("%s: row %d, Break Blade not learned, draws the locked marker",
        tag, i))
      H.assertEq(attr(NAME_COL, y), TEXT_BLUE, string.format("%s: row %d's marker is the other pages' blue", tag, i))
      for x = COST_COL, COST_COL + 4 do
        H.assertEq(cell(x, y), PAD, string.format("%s: row %d (locked) draws no price: {%d,%d}", tag, i, x, y))
      end
    else
      assertRun(NAME_COL, y, nameBytes(r[1]), string.format("%s: row %d is %s: Ot6RuneName's record %d", tag, i,
        ROWNAME[r[1]], r[1] + 8))
      H.assertEq(attr(NAME_COL, y), TEXT_DEFAULT, string.format("%s: row %d's name is white", tag, i))
      local cost = r[2]
      if cost == 0 then
        for x = COST_COL, COST_COL + 4 do
          H.assertEq(cell(x, y), PAD, string.format("%s: row %d (%s) is free: blank at {%d,%d}", tag, i, ROWNAME[r[1]],
            x, y))
        end
      else
        local tens = cost // 10
        H.assertEq(cell(COST_COL, y), tens > 0 and (ZERO_CHAR + tens) or PAD, string.format(
          "%s: row %d (%s) costs %d: tens cell {%d,%d}", tag, i, ROWNAME[r[1]], cost, COST_COL, y))
        H.assertEq(cell(COST_COL + 1, y), ZERO_CHAR + cost % 10, string.format(
          "%s: row %d (%s) costs %d: ones cell {%d,%d}", tag, i, ROWNAME[r[1]], cost, COST_COL + 1, y))
        assertRun(COST_COL + 2, y, MP_SUFFIX, string.format("%s: row %d ' MP'", tag, i))
      end
    end
    if r ~= nil then
      H.assertEq(H.readByte(0x9d89 + i), r[1], string.format("%s: row %d's help line is line %d (%s)", tag, i, r[1],
        ROWNAME[r[1]]))
    end
  end
  H.assertEq(H.readByte(0x54), #rows, string.format("%s: the cursor walks the %d rows there are", tag, #rows))
  -- menu_thiefpage's geometry: odd rows 1-15 only, the gutter, the gap and
  -- the border column blank
  for y = 0, 27 do
    if y % 2 == 0 or y > 15 then
      for x = 0, 31 do
        H.assertEq(cell(x, y), 0, string.format("%s: row %d must be empty: cell {%d,%d}", tag, y, x, y))
      end
    end
  end
  for y = 1, 15, 2 do
    for _, x in ipairs({ 0, 1, 2, 13, 14, 15, 30, 31 }) do
      H.assertEq(cell(x, y), 0, string.format("%s: {%d,%d} must stay blank", tag, x, y))
    end
    for x = COST_COL + 5, 29 do
      H.assertEq(cell(x, y), 0, string.format("%s: {%d,%d} is past the price field", tag, x, y))
    end
  end
  -- the title: the command's name in the shared box, nothing left of it
  local name = record(CMD_RUNIC)
  for i = 1, 7 do
    H.assertEq(vcell(BG3B_V, 22 + i, 5) & 0xff, name[i], string.format(
      "%s: the title box's letter %d at BG3B {%d,5} is BattleCmdName's record $0B's", tag, i, 22 + i))
  end
  for x = 15, 22 do
    H.assertEq(isLetter(vcell(BG3B_V, x, 5) & 0xff), false, string.format("%s: the title row holds only the name: {%d,5}",
      tag, x))
  end
  H.log(string.format("PAGE OK (%s): %s's rows are the model's: %s", tag, NAMES_CH[c], said(rows)))
  return rows
end

-- the help window's buffer ($7e9ec9) against the ROM's line
local function romLine(idx)
  local off = H.readRomByte(DESC_PTRS + idx * 2) | (H.readRomByte(DESC_PTRS + idx * 2 + 1) << 8)
  local t, k = {}, 0
  while true do
    local b = H.readRomByte(DESC_STR + off + k)
    if b == 0 then break end
    t[#t + 1] = b
    k = k + 1
  end
  return t
end
local function assertHelp(tag, i, idx)
  local want = romLine(idx)
  H.assertEq(#want > 0, true, string.format("%s row %d: the table has line %d", tag, i, idx))
  for k, b in ipairs(want) do
    H.assertEq(H.readByte(0x9ec9 + k - 1), b, string.format("%s row %d (%s): the help window shows line %d, byte %d",
      tag, i, ROWNAME[idx], idx, k))
  end
  H.assertEq(H.readByte(0x9ec9 + #want), 0, string.format("%s row %d: the line ends there", tag, i))
end
-- every row of the open page under the cursor in turn: the cursor wraps at
-- the rows' end, and each row shows its line.  `shot` names a screenshot of
-- the first blade row's line and of the last row's (the help window types
-- its line out, so those rows wait for it)
local function walkRows(tag, shot)
  return H.lazy(function()
    local c = H.readByte(ZCHARID + H.readByte(ZSELINDEX))
    local rows, steps = modelRows(c), {}
    for i = 0, #rows - 1 do
      local shoot = shot and (i == 1 or i == #rows - 1)
      steps[#steps + 1] = H.waitFrames(shoot and 150 or 12)
      steps[#steps + 1] = H.call(function()
        H.assertEq(st(), ST_RUNE, tag .. ": still on the page")
        H.assertEq(H.readByte(ZCURSOR), i, string.format("%s: one column: %d steps down is row %d", tag, i, i))
        assertHelp(tag, i, rows[i + 1][1])
        if shoot then H.screenshot(string.format("%s_row%d", shot, i)) end
      end)
      steps[#steps + 1] = H.pressButtons({ "down" }, 2)
    end
    steps[#steps + 1] = H.waitFrames(12)
    steps[#steps + 1] = H.call(function()
      H.assertEq(H.readByte(ZCURSOR), 0, string.format("%s: down from row %d, the last, wraps to Runic", tag, #rows - 1))
      H.log(string.format("HELP OK (%s): %d rows walked, each its line, the cursor wrapping after the last", tag,
        #rows))
    end)
    return H.seqStep(steps)
  end)
end

-- the list as it shows for whoever is selected: the row, its colour, the frame
local function assertList(tag)
  local c = H.readByte(ZCHARID + H.readByte(ZSELINDEX))
  local who, want = NAMES_CH[c] or string.format("$%02X", c), wantColour(c)
  H.assertEq(H.readByte(RUNE_COLOR), want, string.format(
    "%s: %s's RuneKnt row is %s (command $0B %s, a runic weapon in hand %s)", tag, who,
    want == WHITE and "white" or "grey", tostring(hasCmd(c, CMD_RUNIC)), tostring(runicHand(c))))
  local name = record(CMD_RUNIC)
  for i = 1, 7 do
    H.assertEq(vcell(BG3A_V, 1 + i, 23) & 0xff, name[i], string.format(
      "%s: the list's tenth row, letter %d at BG3A {%d,23}, is BattleCmdName's record $0B's", tag, i, 1 + i))
  end
  H.assertEq(vcell(BG3A_V, 2, 23) >> 8, want, string.format("%s: the row's attribute is the colour the scan chose", tag))
  for x = 9, 16 do
    H.assertEq(isLetter(vcell(BG3A_V, x, 23) & 0xff), false, string.format(
      "%s: nothing after the name on its row ({%d,23})", tag, x))
  end
  -- the rows above it, where they were
  for row, cmd in pairs({ [19] = CMD_STEAL, [21] = CMD_SKETCH }) do
    local r = record(cmd)
    for i = 1, 7 do
      H.assertEq(vcell(BG3A_V, 1 + i, row) & 0xff, r[i], string.format(
        "%s: row %d still draws command $%02X's name ({%d,%d})", tag, row, cmd, 1 + i, row))
    end
  end
  -- the frame: Window1 ({1,1} 7x4) gives the reference tiles
  H.assertEq(vcell(BG2A_V, 1, 24), vcell(BG2A_V, 1, 6), string.format(
    "%s: the list window closes at row 24: its bottom-left corner at BG2A {1,24}", tag))
  H.assertEq(vcell(BG2A_V, 9, 24), vcell(BG2A_V, 9, 6), string.format(
    "%s: ... and its bottom-right at {9,24}: vanilla's seven columns", tag))
  H.assertEq(vcell(BG2A_V, 1, 23), vcell(BG2A_V, 1, 5), string.format(
    "%s: the RuneKnt row is inside the frame: left border at {1,23}", tag))
  H.assertEq(vcell(BG2A_V, 9, 23), vcell(BG2A_V, 9, 5), string.format(
    "%s: ... and the right border at {9,23}", tag))
  H.assertEq(vcell(BG2A_V, 9, 7), vcell(BG2A_V, 9, 1), string.format(
    "%s: the list window's top-right corner is at {9,7}", tag))
  H.log(string.format("LIST OK (%s): %s, RuneKnt %s", tag, who, want == WHITE and "white" or "grey"))
  return want
end

local function mainRow(row, what)
  return H.driveUntil(function() return st() == ST_MAIN and H.readByte(ZCURSOR) == row end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, what)
end
local function openMain(what)
  return H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, what)
end
local function closeMenu(what)
  return H.driveUntil(function() return H.worldHasControl() end, 1800,
    { H.pressButtons({ "b" }, 3), H.waitFrames(30) }, what)
end
-- the field menu's Skills list for one character (an id, or a function
-- giving one), from the map
local function openSkills(char, what)
  local function id() return type(char) == "function" and char() or char end
  return H.seqStep({
    openMain(what .. ": main menu"),
    H.waitFrames(20),
    mainRow(1, what .. ": Skills"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_CHAR end, 300, what .. ": character select", 5),
    H.waitFrames(10),
    H.driveUntil(function() return st() == ST_CHAR and H.readByte(ZCHARID + H.readByte(ZCURSOR)) == id() end, 900,
      { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, what .. ": the character"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_SKILLS end, 300, what .. ": the Skills list", 5),
    H.waitFrames(20),
  })
end
local function toRow(row, what)
  return H.driveUntil(function() return st() == ST_SKILLS and H.readByte(ZCURSOR) == row end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(6) }, what)
end
-- from the list: the page opened, settled (the help window types its line)
local function openPage(tag, settle)
  return H.seqStep({
    toRow(ROW_RUNE, tag .. ": cursor to RuneKnt"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_RUNE end, 300, tag .. ": the page opens (menu state $32)", 5),
    H.waitFrames(settle or 90),
  })
end
local function backToList(tag)
  return H.seqStep({
    H.pressButtons({ "b" }, 3),
    H.waitUntil(function() return st() == ST_SKILLS end, 300, tag .. ": B back to the list", 5),
    H.waitFrames(30),
  })
end
local function refuses(tag)
  return H.seqStep({
    toRow(ROW_RUNE, tag .. ": cursor to RuneKnt"),
    H.pressButtons({ "a" }, 2),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(st(), ST_SKILLS, tag .. ": A on the grey RuneKnt row refuses: still on the list")
      H.log("REFUSE OK (" .. tag .. ")")
    end),
  })
end

-- a weapon in the bag that allows Runic and that `c` can hold (ItemProp+1:
-- the equippable-characters word, a bit per actor)
local function bagRunicFor(c)
  local actor = H.readByte(rec(c))
  for i = 0, 255 do
    local item = H.readByte(0x1869 + i)
    if item ~= 0xFF and H.readByte(0x1969 + i) > 0 and runicItem(item) then
      local mask = H.readRomByte(ITEM_PROP + item * 30 + 1) | (H.readRomByte(ITEM_PROP + item * 30 + 2) << 8)
      if (mask & (1 << actor)) ~= 0 then return item end
    end
  end
end
-- a soft dependency the suite fixes as a player would: `c` holds a weapon
-- that allows Runic (the fixture's play decides what its members hold)
local function ensureRunic(c, tag)
  return H.cond(function() return not runicHand(c) end, {
    H.lazy(function()
      local item = bagRunicFor(c)
      H.assertEq(item ~= nil, true, string.format("%s: %s holds no weapon that allows Runic and the bag has none for "
        .. "them (gen_wor_opera's party and bag)", tag, NAMES_CH[c]))
      return H.equipWeapon(posOf(c), item, { slot = 0, tag = tag .. ": a runic weapon in hand" })
    end),
    H.waitUntil(function() return H.worldHasControl() end, 1800, tag .. ": control after the Equip menu", 5),
    H.call(function() H.assertEq(runicHand(c), true, tag .. ": a weapon that allows Runic is in hand") end),
  }, {})
end

local others = {}                       -- the seated, CELES apart, in menu order
local taker                             -- who takes Ifrit off her again
local seen = {}                         -- the rows each page showed
local hands = {}                        -- CELES's two hands before they are emptied

local steps = {
  H.bootCheckpoint("wor-opera-v1"),
  H.waitUntil(function() return H.worldSettled() end, 1200, "world settled", 5),
  H.call(function()
    H.assertEq(seated(CELES) and seated(GOGO), true, "CELES and GOGO are seated (gen_wor_opera's party beside the "
      .. "Falcon: wor-opera-v1)")
    H.assertEq(hasCmd(CELES, CMD_RUNIC), true, "CELES's record carries command $0B")
    H.assertEq(breakLearned(), true, "Break Blade is learned: switch $00A4, the World of Ruin's first scene, is set "
      .. "(menu_runekntpage_wob covers the save before it)")
    for _, c in ipairs(seatedChars()) do
      if c ~= CELES then others[#others + 1] = c end
      if taker == nil and c ~= CELES and H.readByte(rec(c)) < GOGO then taker = c end
    end
    H.assertEq(taker ~= nil, true, "another seated member can wear a stone, to take Ifrit off CELES again")
    local grey = false
    for _, c in ipairs(others) do if not hasCmd(c, CMD_RUNIC) then grey = true end end
    H.assertEq(grey, true, "a seated character does not carry command $0B: the grey row has someone to show for")
    H.assertEq(H.readByte(0x1A69) & (1 << IFRIT), 1 << IFRIT, "the party owns Ifrit ($1A69 bit 1): gen_ifrit_magicite, "
      .. "the Magitek factory's leg, takes its magicite")
    local w
    for c = 0, 15 do if worn(c) == IFRIT then w = c end end
    H.assertEq(w == nil or seated(w), true, string.format("Ifrit is in the bag or on a seated member (char %s wears "
      .. "it): the field's Skills menu reaches only the seated", tostring(w)))
    -- what the stone changes, from the tables: the page has something to follow
    local with, without = said(modelRows(CELES, IFRIT)), said(modelRows(CELES, false))
    H.assertEq(with ~= without, true, string.format("CELES's rows with Ifrit (%s) and with no stone (%s) differ: "
      .. "Ifrit lends an element she does not hold by herself", with, without))
    H.assertEq(H.readRomByte(RUNE_NAME + 8 * NAME_SIZE), 0x91, "Ot6RuneName's record 8 is Runic's (R)")
    H.assertEq(H.readRomByte(RUNE_NAME + 9 * NAME_SIZE), 0xd9, "a blade row's name begins with the sword icon ($D9)")
    H.log(string.format("party: CELES and %d others; Ifrit worn by %s; %s takes it in step 5; CELES holds $%02X/$%02X, "
      .. "stone $%02X, rows as booted: %s", #others, tostring(w), NAMES_CH[taker], H.readByte(rec(CELES) + 0x1F),
      H.readByte(rec(CELES) + 0x20), worn(CELES), said(modelRows(CELES))))
  end),
  ensureRunic(CELES, "CELES"),

  -- 1. CELES's list: the tenth row, the cursor, the tables
  openSkills(CELES, "CELES"),
  H.call(function()
    H.assertEq(assertList("CELES"), WHITE, "CELES carries the command and holds a weapon that allows Runic: white")
  end),
  toRow(ROW_RUNE, "skills cursor to RuneKnt (row 9)"),
  H.waitFrames(10),
  H.call(function()
    local tbl, old = H.sym("Ot6SkillsCursorPos") & 0x3FFFFF, H.sym("SkillsCursorPos") & 0x3FFFFF
    H.assertEq(H.readRomByte(tbl + ROW_RUNE * 2 + 1), 8 * 23 - 4,
      "the RuneKnt row's cursor entry points at BG3A row 23 (y = 8n - 4)")
    H.assertEq(H.readRomByte(tbl + 8 * 2 + 1), 8 * 21 - 4, "the Painter row's entry is where it was (row 21)")
    for n = 0, 7 do
      H.assertEq(H.readRomByte(tbl + n * 2 + 1), H.readRomByte(old + n * 2 + 1), string.format(
        "the ten-row cursor table keeps vanilla's row %d", n))
    end
    local jt, ojt = H.sym("Ot6SkillsOptionTbl") & 0x3FFFFF, H.sym("SkillsOptionTbl") & 0x3FFFFF
    for n = 0, 7 do
      H.assertEq(H.readRomByte(jt + n * 2) | H.readRomByte(jt + n * 2 + 1) << 8,
        H.readRomByte(ojt + n * 2) | H.readRomByte(ojt + n * 2 + 1) << 8, string.format(
        "the ten-entry Skills jump table keeps vanilla's entry %d", n))
    end
    H.assertEq(H.readRomByte(jt + 16) | H.readRomByte(jt + 17) << 8, H.sym("SkillsOption_08") & 0xFFFF,
      "entry 8 is still SkillsOption_08, the Painter page")
    H.assertEq(H.readRomByte(jt + 18) | H.readRomByte(jt + 19) << 8, H.sym("SkillsOption_09") & 0xFFFF,
      "entry 9 is SkillsOption_09, the Rune Knight page")
    local states = H.sym("MenuStateTbl") & 0x3FFFFF
    H.assertEq(H.readRomByte(states + 2 * ST_RUNE) | H.readRomByte(states + 2 * ST_RUNE + 1) << 8,
      H.sym("MenuState_32_RuneKnt") & 0xFFFF, "menu state $32 is the Rune Knight page's")
    H.screenshot("runekntpage_skills")
  end),
  H.pressButtons({ "down" }, 2),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.readByte(ZCURSOR), ROW_ESPERS, "down from RuneKnt wraps to Espers (the list's ten rows)")
  end),
  H.pressButtons({ "up" }, 2),
  H.waitFrames(10),
  H.call(function() H.assertEq(H.readByte(ZCURSOR), ROW_RUNE, "up from Espers wraps to RuneKnt") end),

  -- 2. the page
  openPage("CELES", 150),
  H.call(function()
    seen.boot = said(assertPage("CELES, as booted"))
    H.assertEq(H.readByte(ZCURSOR), 0, "the page opens on its first row, Runic")
    assertHelp("CELES, as booted", 0, IDX_RUNIC)
    H.screenshot("runekntpage_page")
  end),
  walkRows("CELES, as booted", "runekntpage_help"),
  H.pressButtons({ "a" }, 2),
  H.waitFrames(30),
  H.call(function() H.assertEq(st(), ST_RUNE, "A on a row does nothing: still on the page") end),

  -- 3. B: back to the list, the cursor on RuneKnt, nothing of the page left
  backToList("CELES"),
  H.call(function()
    H.assertEq(H.readByte(ZCURSOR), ROW_RUNE, "back on the list, the cursor is on RuneKnt")
    for x = 15, 29 do
      H.assertEq(isLetter(vcell(BG3B_V, x, 5) & 0xff), false, string.format(
        "B cleared the title: BG3B {%d,5} holds no letter", x))
    end
    for k = 0, 2 do
      H.assertEq(vcell(BG1A_V, NAME_COL + k, 1) & 0xff, 0, string.format(
        "the page's rows left BG1 screen A in VRAM ({%d,1})", NAME_COL + k))
    end
    assertList("CELES after B")
    H.log("EXIT OK: the cursor on RuneKnt, the title row blank, BG1 clean")
  end),
  H.driveUntil(function() return st() == ST_SKILLS and H.readByte(ZCURSOR) == ROW_ESPERS end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(6) }, "cursor to Espers"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() ~= ST_SKILLS end, 300, "Espers opens", 5),
  H.waitFrames(60),
  H.call(function()
    local text = "Espers"
    for i = 1, #text do
      H.assertEq(vcell(BG3B_V, 22 + i, 5) & 0xff, enc(text:sub(i, i)), string.format(
        "the Espers page's title, letter %d at {%d,5}", i, 22 + i))
    end
    H.assertEq(isLetter(vcell(BG3B_V, 29, 5) & 0xff), false, "no last letter of the Rune Knight's title after Espers ({29,5})")
    H.log("ESPERS OK: the Espers title alone in the shared box")
  end),
  closeMenu("out to the map"),
}

-- 4. every other seated character: the row's colour, and a grey row refuses
for k = 1, 3 do
  steps[#steps + 1] = H.cond(function() return others[k] ~= nil end, {
    openSkills(function() return others[k] end, "seated character " .. k),
    H.call(function() assertList("seated character " .. k) end),
    H.cond(function() return wantColour(others[k]) == GREY end, { refuses("seated character " .. k) }, {}),
    closeMenu("out"),
  }, {})
end

local function celesPage(tag, key, shot)
  return H.seqStep({
    H.waitUntil(function() return H.worldHasControl() end, 1800, tag .. ": control after the menu", 5),
    openSkills(CELES, tag),
    H.call(function() assertList(tag) end),
    openPage(tag, shot and 150 or 90),
    H.call(function()
      seen[key] = said(assertPage(tag))
      if shot then H.screenshot(shot) end
    end),
    walkRows(tag),
    backToList(tag),
    closeMenu(tag .. ": out"),
  })
end
for _, s in ipairs({
  -- 5. the page follows her esper
  H.equipEsper(function() return posOf(CELES) end, IFRIT, { tag = "Ifrit -> CELES" }),
  celesPage("CELES with Ifrit", "ifrit"),
  H.call(function()
    H.assertEq(worn(CELES), IFRIT, "CELES wears Ifrit")
    H.assertEq(seen.ifrit, said(modelRows(CELES, IFRIT)), "her page showed the rows of her spells and Ifrit's")
  end),
  H.equipEsper(function() return posOf(taker) end, IFRIT, { tag = "Ifrit off CELES" }),
  celesPage("CELES with no esper", "none", "runekntpage_noesper"),
  H.call(function()
    H.assertEq(worn(CELES), 0xFF, "CELES wears no esper (Ifrit went to another member)")
    H.assertEq(seen.none, said(modelRows(CELES, false)), "her page showed the rows of the spells she holds by herself")
    H.assertEq(seen.ifrit ~= seen.none, true, "the page with Ifrit and the page without differ")
    H.log(string.format("ESPER OK: the page followed the stone: as booted %s | Ifrit %s | none %s", seen.boot,
      seen.ifrit, seen.none))
  end),

  -- 6. GOGO takes the command in his Status picker
  H.cond(function() return not hasCmd(GOGO, CMD_RUNIC) end, {
    openMain("Status: main menu"),
    H.waitFrames(20),
    mainRow(4, "Status"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_CHAR end, 300, "Status: character select", 5),
    H.waitFrames(10),
    H.driveUntil(function() return st() == ST_CHAR and H.readByte(ZCHARID + H.readByte(ZCURSOR)) == GOGO end, 900,
      { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "Status: GOGO"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() ~= ST_CHAR and st() ~= -1 end, 300, "GOGO's status", 5),
    H.waitFrames(40),
    H.driveUntil(function()
      return H.readByte(rec(GOGO) + 0x16 + H.readByte(ZCURSOR)) ~= CMD_MIMIC
    end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "GOGO's command cursor off Mimic"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_GOGO_LIST end, 300, "GOGO's command list", 5),
    H.waitFrames(20),
    H.call(function()
      local n, has = H.readByte(0x9d89), false
      for i = 0, n - 1 do if H.readByte(0x9d8a + i) == CMD_RUNIC then has = true end end
      H.assertEq(has, true, "GOGO's command list offers command $0B (CELES is recruited)")
    end),
    H.driveUntil(function()
      return st() == ST_GOGO_LIST and H.readByte(0x9d8a + H.readByte(ZCURSOR)) == CMD_RUNIC
    end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "GOGO's list cursor on the command"),
    H.pressButtons({ "a" }, 2),
    H.waitFrames(40),
    H.call(function()
      H.assertEq(hasCmd(GOGO, CMD_RUNIC), true, "GOGO carries command $0B now")
      H.log("GOGO OK: the command taken through his picker")
    end),
    closeMenu("out"),
  }, {}),
  H.waitUntil(function() return H.worldHasControl() end, 1800, "control before GOGO's weapon", 5),
  ensureRunic(GOGO, "GOGO"),
  openSkills(GOGO, "GOGO with the command"),
  H.call(function()
    H.assertEq(assertList("GOGO with the command"), WHITE, "GOGO carries the command and a weapon that allows Runic")
  end),
  openPage("GOGO", 150),
  H.call(function()
    seen.gogo = said(assertPage("GOGO"))
    local union = {}
    for _, o in ipairs(seatedChars()) do
      if o ~= GOGO then union[#union + 1] = string.format("%s (%s)", NAMES_CH[o], said(modelRows(o))) end
    end
    H.screenshot("runekntpage_gogo")
    H.log(string.format("GOGO OK: his page lists the seated party's union: %s; the others' own: %s", seen.gogo,
      table.concat(union, "; ")))
  end),
  walkRows("GOGO"),
  backToList("GOGO"),
  closeMenu("out"),

  -- 7. the weapon: both hands empty, the row is grey, as the command is in battle
  H.call(function() hands[0], hands[1] = H.readByte(rec(CELES) + 0x1F), H.readByte(rec(CELES) + 0x20) end),
  H.removeEquip(CELES, 0, { tag = "CELES's right hand off" }),
  H.waitUntil(function() return H.worldHasControl() end, 1800, "control after the Equip menu", 5),
  H.removeEquip(CELES, 1, { tag = "CELES's left hand off" }),
  H.waitUntil(function() return H.worldHasControl() end, 1800, "control after the Equip menu", 5),
  openSkills(CELES, "CELES bare-handed"),
  H.call(function()
    H.assertEq(H.readByte(rec(CELES) + 0x1F) == 0xFF and H.readByte(rec(CELES) + 0x20) == 0xFF, true,
      "both of CELES's hands are empty")
    H.assertEq(assertList("CELES bare-handed"), GREY, "CELES carries the command and holds no weapon: grey, as the "
      .. "command is in battle")
  end),
  refuses("CELES bare-handed"),
  closeMenu("out"),
  H.lazy(function()
    local item = runicItem(hands[0]) and hands[0] or hands[1]
    H.assertEq(runicItem(item), true, string.format("one of the weapons she held ($%02X, $%02X) allows Runic", hands[0],
      hands[1]))
    return H.equipWeapon(posOf(CELES), item, { slot = 0, tag = "a weapon back in CELES's hand" })
  end),
  H.waitUntil(function() return H.worldHasControl() end, 1800, "control after the Equip menu", 5),
  openSkills(CELES, "CELES armed again"),
  H.call(function()
    H.assertEq(assertList("CELES armed again"), WHITE, "a weapon that allows Runic back in hand: white again")
    H.log("WEAPON OK: grey with both hands empty, white with a runic weapon")
  end),
  openPage("CELES armed again"),
  H.call(function() assertPage("CELES armed again") end),
  backToList("CELES armed again"),
  closeMenu("out"),
  H.call(function() H.log("PASS: the RuneKnt row and the Rune Knight page") end),
}) do steps[#steps + 1] = s end

H.run({ maxFrames = 400000 }, steps)
