-- @suite
-- menu_runekntpage_wob.lua -- Celes's Rune Knight page before Break Blade is
-- learned: its locked row (#563).
--
-- menu_runekntpage covers the page in the World of Ruin, where Break Blade
-- is learned; this one covers the save before the Floating Continent, the
-- only place the page's last row draws the locked marker of the other kit
-- pages (the Blitz page's, blue, no price) and the help window says where
-- the row is learned.  The model of the rows is that suite's (the save's
-- learned table, CELES's Break from level 13, her worn esper's spells and
-- her worn pieces' grants; MagicProp's elements and prices through her
-- Economizer or Gold Hairpin; Ot6RuneName; the RUNE help lines in the ROM),
-- never a copy of a number here.
--
-- Boot: cold Continue of mrf-save-room-v1, the Magitek Research Facility's
-- save room (LOCKE, EDGAR, SABIN and CELES seated; switches $0266 and $00A4
-- clear).  Then, through the controller, nothing written:
--   1. CELES's Skills list: the RuneKnt row white; a seated character
--      without the command has it grey;
--   2. A on it opens menu state $32: Runic, the blade rows of the model,
--      then the locked row, blue, with no price; the cursor walks those rows
--      and each shows its help line, the locked row's being line 10, "how it
--      is learned" (screenshot runekntpage_locked, the cursor on that row);
--   3. B returns to the list.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE, ZCURSOR, ZSELINDEX, ZCHARID = 0x26, 0x4b, 0x28, 0x69
local RUNE_COLOR = 0x82                 -- zSkillsTextColor::RuneKnt
local CELES, STRAGO, GOGO = 0x06, 0x07, 0x0c
local CMD_RUNIC = 0x0b
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_RUNE = 0x05, 0x06, 0x0a, 0x32
local ROW_RUNE = 9
local WHITE, GREY = 0x20, 0x24
local BREAK, SCAN = 0x0c, 0x18          -- spell ids
local IDX_RUNIC, IDX_BLADE, IDX_BREAK, IDX_LOCKED = 0, 1, 9, 10   -- a row's id less $D0
local BREAK_MP, BLADES = 99, 6
local NAMES_CH = { [0] = "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO",
  "RELM", "SETZER", "MOG", "GAU", "GOGO", "UMARO" }
local ROWNAME = { [0] = "Runic", "Fire", "Ice", "Bolt", "Poison", "Wind", "Pearl", "Earth", "Water", "Break Blade",
  "Break Blade (locked)" }

local function st() return H.menuRunning() and H.readByte(ZMENUSTATE) or -1 end
local VR = emu.memType.snesVideoRam
local function vcell(base, x, y) return emu.readWord((base + y * 32 + x) * 2, VR) end
local BG3A_V, BG3B_V = 0x4000, 0x4400
local BG1A = 0x3849                     -- wBG1Tiles::ScreenA: tile, attribute
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end
local function attr(x, y) return H.readByte(BG1A + x * 2 + y * 64 + 1) end
local ZERO_CHAR, PAD = 0xb4, 0xff
local MP_SUFFIX = { 0xff, 0x8c, 0x8f }  -- " MP"
local NAME_COL, COST_COL, NAME_SIZE = 3, 16, 10
local TEXT_DEFAULT, TEXT_BLUE = 0x20, 0x2c   -- BG1_TEXT_COLOR

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
local function hasCmd(c, cmd)
  for i = 0, 3 do if H.readByte(rec(c) + 0x16 + i) == cmd then return true end end
  return false
end
local function seated(c)
  local pb = H.readByte(0x1850 + c)
  return (pb & 7) ~= 0 and (pb & 7) == (H.readByte(0x1A6D) & 7)
end
local function record(cmd)
  local t = {}
  for i = 0, 6 do t[#t + 1] = H.readRomByte(CMDNAMES + cmd * 7 + i) end
  return t
end
local function runicItem(item)
  local p = ITEM_PROP + item * 30
  return (H.readRomByte(p) & 7) == 1 and (H.readRomByte(p + 19) & 0x80) ~= 0
end
local function runicHand(c)
  return runicItem(H.readByte(rec(c) + 0x1F)) or runicItem(H.readByte(rec(c) + 0x20))
end
local function wantColour(c) return (hasCmd(c, CMD_RUNIC) and runicHand(c)) and WHITE or GREY end
local function priced(c, mp)
  local r = 0
  for s = 0, 5 do r = r | H.readRomByte(ITEM_PROP + H.readByte(rec(c) + 0x1F + s) * 30 + 11) end
  if (r & 0x40) ~= 0 then return 1 end
  if (r & 0x20) ~= 0 then return (mp + 1) // 2 end
  return mp
end
-- Ot6FieldSpellKnown for one record (menu_runekntpage's model)
local function knows(c, id)
  local actor = H.readByte(rec(c))
  if actor == CELES and id == BREAK and H.readByte(rec(CELES) + 8) >= 13 then return true end
  if actor == STRAGO and id == SCAN then return true end
  if H.readByte(0x1A6E + 54 * actor + id) == 0xFF then return true end
  local e = H.readByte(rec(c) + 0x1E)
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
local function modelRows(c)
  local cheapest = {}
  for id = 0, 0x35 do
    if knows(c, id) then
      local el, mp = H.readRomByte(MAGIC_PROP + id * 14 + 1), H.readRomByte(MAGIC_PROP + id * 14 + 5)
      for b = 0, 7 do
        if (el & (1 << b)) ~= 0 and (cheapest[b] == nil or mp < cheapest[b]) then cheapest[b] = mp end
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
local function lockedBytes()
  local t = {}
  for i = 0, 15 do
    local b = H.readRomByte(LOCKED + i)
    if b == 0 then break end
    t[#t + 1] = b
  end
  return t
end

local function assertList(tag)
  local c = H.readByte(ZCHARID + H.readByte(ZSELINDEX))
  local want = wantColour(c)
  H.assertEq(H.readByte(RUNE_COLOR), want, string.format("%s: %s's RuneKnt row is %s (command $0B %s, a runic "
    .. "weapon in hand %s)", tag, NAMES_CH[c], want == WHITE and "white" or "grey", tostring(hasCmd(c, CMD_RUNIC)),
    tostring(runicHand(c))))
  local name = record(CMD_RUNIC)
  for i = 1, 7 do
    H.assertEq(vcell(BG3A_V, 1 + i, 23) & 0xff, name[i], string.format(
      "%s: the list's tenth row, letter %d at BG3A {%d,23}, is BattleCmdName's record $0B's", tag, i, 1 + i))
  end
  H.assertEq(vcell(BG3A_V, 2, 23) >> 8, want, tag .. ": the row's attribute is the colour the scan chose")
  H.log(string.format("LIST OK (%s): %s, RuneKnt %s", tag, NAMES_CH[c], want == WHITE and "white" or "grey"))
  return want
end

local function openSkills(char, what)
  local function id() return type(char) == "function" and char() or char end
  return H.seqStep({
    H.driveUntil(function() return st() == ST_MAIN end, 1200,
      { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, what .. ": main menu"),
    H.waitFrames(20),
    H.driveUntil(function() return st() == ST_MAIN and H.readByte(ZCURSOR) == 1 end, 900,
      { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, what .. ": Skills"),
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
local function toRune(what)
  return H.driveUntil(function() return st() == ST_SKILLS and H.readByte(ZCURSOR) == ROW_RUNE end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(6) }, what)
end

local rows, other
local steps = {
  H.bootCheckpoint("mrf-save-room-v1"),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "control in the save room", 5),
  H.call(function()
    H.assertEq(seated(CELES), true, "CELES is seated (gen_mrf_save_room_checkpoint's party at the Magitek Research Facility's save point: "
      .. "mrf-save-room-v1)")
    H.assertEq(hasCmd(CELES, CMD_RUNIC), true, "CELES's record carries command $0B")
    H.assertEq(runicHand(CELES), true, "CELES holds a weapon that allows Runic (the party's loadout at the save point)")
    H.assertEq(breakLearned(), false, "Break Blade is not learned: switches $0266 and $00A4 are clear before the "
      .. "Floating Continent")
    for c = 0, 13 do
      if other == nil and c ~= CELES and seated(c) and not hasCmd(c, CMD_RUNIC) then other = c end
    end
    H.assertEq(other ~= nil, true, "a seated character does not carry command $0B")
    rows = modelRows(CELES)
    H.assertEq(rows[#rows][1], IDX_LOCKED, "the model's last row is Break Blade not learned yet")
    H.assertEq(#rows >= 3, true, string.format("CELES holds a spell with an element (Ice, her own): a blade row "
      .. "stands between Runic and the locked row (%s)", said(rows)))
    H.log(string.format("CELES L%d, stone $%02X, holds $%02X/$%02X; the model's rows: %s; %s has no command $0B",
      H.readByte(rec(CELES) + 8), H.readByte(rec(CELES) + 0x1E), H.readByte(rec(CELES) + 0x1F),
      H.readByte(rec(CELES) + 0x20), said(rows), NAMES_CH[other]))
  end),

  -- 1. the list
  openSkills(function() return other end, "a character without the command"),
  H.call(function() H.assertEq(assertList("without the command"), GREY, "no command $0B: the row is grey") end),
  toRune("cursor to the grey RuneKnt row"),
  H.pressButtons({ "a" }, 2),
  H.waitFrames(30),
  H.call(function() H.assertEq(st(), ST_SKILLS, "A on the grey RuneKnt row refuses: still on the list") end),
  H.driveUntil(function() return H.hasControl() end, 1800, { H.pressButtons({ "b" }, 3), H.waitFrames(30) },
    "out to the room"),
  openSkills(CELES, "CELES"),
  H.call(function() H.assertEq(assertList("CELES"), WHITE, "CELES: the row is white") end),

  -- 2. the page: the locked row
  toRune("cursor to RuneKnt"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_RUNE end, 300, "the page opens (menu state $32)", 5),
  H.waitFrames(90),
  H.call(function()
    rows = modelRows(CELES)
    for i = 0, 7 do
      local y, r = 1 + i * 2, rows[i + 1]
      if r == nil then
        for x = 0, 31 do
          H.assertEq(cell(x, y), 0, string.format("row %d is past the %d rows: nothing drawn at {%d,%d}", i, #rows, x, y))
        end
        H.assertEq(H.readByte(0x9d89 + i), 0xFF, string.format("row %d holds no help line", i))
      elseif r[1] == IDX_LOCKED then
        for k, b in ipairs(lockedBytes()) do
          H.assertEq(cell(NAME_COL + k - 1, y), b, string.format(
            "row %d, Break Blade not learned, draws the locked marker (Ot6BlitzLockedTiles): cell {%d,%d}", i,
            NAME_COL + k - 1, y))
        end
        H.assertEq(attr(NAME_COL, y), TEXT_BLUE, string.format("row %d's marker is the other pages' blue", i))
        for x = COST_COL, COST_COL + 4 do
          H.assertEq(cell(x, y), PAD, string.format("row %d (locked) draws no price: {%d,%d}", i, x, y))
        end
        H.assertEq(H.readByte(0x9d89 + i), IDX_LOCKED, string.format("row %d's help line is line 10, how it is "
          .. "learned", i))
      else
        for k = 0, NAME_SIZE - 1 do
          H.assertEq(cell(NAME_COL + k, y), H.readRomByte(RUNE_NAME + (r[1] + 8) * NAME_SIZE + k), string.format(
            "row %d is %s: Ot6RuneName's record %d, cell {%d,%d}", i, ROWNAME[r[1]], r[1] + 8, NAME_COL + k, y))
        end
        H.assertEq(attr(NAME_COL, y), TEXT_DEFAULT, string.format("row %d's name is white", i))
        if r[2] == 0 then
          for x = COST_COL, COST_COL + 4 do
            H.assertEq(cell(x, y), PAD, string.format("row %d (%s) is free: blank at {%d,%d}", i, ROWNAME[r[1]], x, y))
          end
        else
          local tens = r[2] // 10
          H.assertEq(cell(COST_COL, y), tens > 0 and (ZERO_CHAR + tens) or PAD, string.format(
            "row %d (%s) costs %d: tens cell", i, ROWNAME[r[1]], r[2]))
          H.assertEq(cell(COST_COL + 1, y), ZERO_CHAR + r[2] % 10, string.format(
            "row %d (%s) costs %d: ones cell", i, ROWNAME[r[1]], r[2]))
          for k, b in ipairs(MP_SUFFIX) do
            H.assertEq(cell(COST_COL + 1 + k, y), b, string.format("row %d ' MP'", i))
          end
        end
        H.assertEq(H.readByte(0x9d89 + i), r[1], string.format("row %d's help line is line %d", i, r[1]))
      end
    end
    H.assertEq(H.readByte(0x54), #rows, string.format("the cursor walks the %d rows there are", #rows))
    local name = record(CMD_RUNIC)
    for i = 1, 7 do
      H.assertEq(vcell(BG3B_V, 22 + i, 5) & 0xff, name[i], string.format(
        "the title box's letter %d at BG3B {%d,5} is BattleCmdName's record $0B's", i, 22 + i))
    end
    H.log("PAGE OK: CELES's rows are the model's, Break Blade locked: " .. said(rows))
  end),
  H.lazy(function()
    local s = {}
    for i = 0, #rows - 1 do
      local last = i == #rows - 1
      s[#s + 1] = H.waitFrames(last and 150 or 12)
      s[#s + 1] = H.call(function()
        H.assertEq(H.readByte(ZCURSOR), i, string.format("%d steps down is row %d", i, i))
        local want = romLine(rows[i + 1][1])
        H.assertEq(#want > 0, true, string.format("row %d: the table has line %d", i, rows[i + 1][1]))
        for k, b in ipairs(want) do
          H.assertEq(H.readByte(0x9ec9 + k - 1), b, string.format("row %d (%s): the help window shows line %d, byte %d",
            i, ROWNAME[rows[i + 1][1]], rows[i + 1][1], k))
        end
        H.assertEq(H.readByte(0x9ec9 + #want), 0, string.format("row %d: the line ends there", i))
        if last then
          H.assertEq(rows[i + 1][1], IDX_LOCKED, "the last row is the locked one")
          H.screenshot("runekntpage_locked")
        end
      end)
      s[#s + 1] = H.pressButtons({ "down" }, 2)
    end
    s[#s + 1] = H.waitFrames(12)
    s[#s + 1] = H.call(function()
      H.assertEq(H.readByte(ZCURSOR), 0, "down from the locked row, the last, wraps to Runic")
      H.log(string.format("HELP OK: %d rows walked, the locked row showing how it is learned", #rows))
    end)
    return H.seqStep(s)
  end),

  -- 3. B
  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "B returns to the list", 5),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(ZCURSOR), ROW_RUNE, "back on the list, the cursor is on RuneKnt")
    H.log("PASS: the Rune Knight page with Break Blade locked")
  end),
}
H.run({ maxFrames = 60000 }, steps)
