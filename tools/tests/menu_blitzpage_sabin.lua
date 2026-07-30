-- @suite frontier=vector_doorstep
-- menu_blitzpage_sabin.lua -- issue #53: the field Skills->Blitz page, opened
-- for A REAL SABIN.
--
-- WHY THIS FILE EXISTS.  menu_blitzpage.lua asserts the page thoroughly and
-- every one of its three phases is SYNTHETIC: arvis_wake's party is Terra
-- alone, so that test installs the Blitz command onto her third battle-command
-- byte and writes the known-blitz mask $1D28 by hand.  Correct as staging --
-- it is the only way to reach the eight-learned and none-learned states at
-- all, and both are real states a Sabin passes through -- but it means the
-- page had never once been rendered for the character it is FOR.  The owner
-- spotted it the way anyone would: Terra's portrait, on the Blitz page, in a
-- screenshot.
--
-- So this test pokes NOTHING.  Its whole job is that every input is the
-- game's own:
--   * the fixture is vector_doorstep, cold-booted from the tracked
--     post-opera-v1 battery (frontier_graph.py:390), whose manifest names its
--     party LOCKE CELES SABIN EDGAR -- one anchored leg, no story replay;
--   * SABIN is FOUND, not assumed: zCharID ($69, four bytes, one per party
--     slot) is read and searched for CHAR::SABIN, and the character cursor is
--     driven to that slot.  A party reshuffle moves the row, not the test;
--   * the Blitz row is enabled because Sabin's own character record carries
--     BATTLE_CMD::BLITZ, which this test asserts rather than arranges;
--   * the learned set is whatever the save holds.  The rows are checked
--     against $1D28 as read, so a level or a story beat can move which rungs
--     are lit without touching this file.
--
-- WHAT IT ADDS OVER menu_blitzpage.lua.  Only the realness -- deliberately.
-- The geometry canaries, the cursor-gutter pairing and the price arithmetic
-- are asserted there, on three learned-counts this fixture cannot produce, and
-- duplicating them here would be two copies to keep in step for no new
-- coverage.  What is genuinely only checkable HERE is that the page a player
-- actually opens agrees with the ROM: the names, the #53 probe icons, and the
-- locked marker on rungs a mid-game Sabin has not reached.
--
-- THE ICONS (#53) are the reason a real Sabin matters more than usual now.
-- Three of his eight Blitzes carry an ELEMENT and no break class -- AuraBolt
-- holy, Fire Dance fire, Air Blade wind -- and until #53 uploaded the element
-- tiles into the FIELD font (Ot6MenuIcons4bpp_ext, ot6_icons.asm) those three
-- rows drew a blank cell.  A mid-game Sabin has learned them, so this fixture
-- puts real element icons on a real page; the test asserts each named cell
-- both in the tilemap AND as art present in the menu font's vram copy.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vector_doorstep.mss.lua"

local ZMENUSTATE, ZCURSOR, ZSELINDEX = 0x26, 0x4b, 0x28
local ZCHARID = 0x69                    -- zCharID::Slot1..4 (menu_ram.inc:168)
local BLITZ_ROW_COLOR = 0x7c            -- zSkillsTextColor::Blitz
local COLOR_ENABLED, COLOR_GREY = 0x20, 0x24
local CHAR_SABIN = 0x05
local BATTLE_CMD_BLITZ = 0x0a
local CHAR_REC, CHAR_CMD = 0x1600, 0x16 -- $1600 + 37n, commands at +$16
local CHAR_STRIDE = 37
local BLITZES = 0x1D28                  -- known-blitz bitmask (FixPlayerAttack's)
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_BLITZ = 0x05, 0x06, 0x0a, 0x33
local SKILLS_ROW_BLITZ = 3
local function st() return H.readByte(ZMENUSTATE) end

-- BG1 screen A tilemap shadow (wBG1Tiles::ScreenA = $7e3849)
local BG1A = 0x3849
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end

local NAME_COL, ICON_COL, COST_COL = 3, 14, 16
local NAME_SIZE, PAD = 10, 0xff
local function blitzRow(i) return 1 + i * 2 end

-- ---- the ROM authorities, all read, none written down ----
local ATKNAME = H.sym("AttackName") & 0x3FFFFF
local ATKNAME_0, BLITZ_ATK0 = 0x51, 0x5d
local SKILLCLASS = H.sym("Ot6SkillClassTbl") & 0x3FFFFF
local CLASSGLYPH = H.sym("Ot6ClassGlyphTbl") & 0x3FFFFF
local ELEMGLYPH = H.sym("Ot6ElemGlyphTbl") & 0x3FFFFF
local MAGICPROP = H.sym("MagicProp") & 0x3FFFFF
local COSTTBL = H.sym("Ot6AbilityCostTbl") & 0x3FFFFF

local function nameBytes(id)
  local t, rec = {}, id - ATKNAME_0
  for i = 0, NAME_SIZE - 1 do t[i + 1] = H.readRomByte(ATKNAME + rec * NAME_SIZE + i) end
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

local function firstBit(m)
  local i = 0
  while m & 1 == 0 do m = m >> 1; i = i + 1 end
  return i
end
-- Ot6ElemGlyphFor's decision, in the same order: element, then break class.
local function iconGlyph(id)
  local e = H.readRomByte(MAGICPROP + id * 14 + 1)
  if e ~= 0 then return H.readRomByte(ELEMGLYPH + firstBit(e)) end
  local x = 0
  while true do
    local key = H.readRomByte(SKILLCLASS + x)
    if key == 0xff then return PAD end
    if key == id then
      local cls = H.readRomByte(SKILLCLASS + x + 1)
      if cls == 0 or cls >= 0x80 then return PAD end
      return H.readRomByte(CLASSGLYPH + firstBit(cls))
    end
    x = x + 2
  end
end
local ELEM_CELLS = {}
for i = 0, 7 do ELEM_CELLS[H.readRomByte(ELEMGLYPH + i)] = true end

-- BG1's char base is word $5000 and the menu's copy of the font is 4bpp there
-- (hBG12NBA = $65, menu_init_2.asm:433), so a tile is 32 bytes.
local function fontCellHasArt(code)
  local base = 0x5000 * 2 + code * 32
  for i = 0, 31 do
    if emu.read(base + i, emu.memType.snesVideoRam) ~= 0 then return true end
  end
  return false
end

local function costOf(id)
  local x = 0
  while true do
    local key = H.readRomByte(COSTTBL + x)
    if key == 0xff then return 0 end
    if key == id then return H.readRomByte(COSTTBL + x + 1) end
    x = x + 2
  end
end

local T = { C = 0x82, D = 0x83, E = 0x84, K = 0x8a, L = 0x8b, M = 0x8c,
            O = 0x8e, P = 0x8f, DASH = 0xc4, SP = 0xff }
local LOCKED = { T.DASH, T.SP, T.L, T.O, T.C, T.K, T.E, T.D, T.SP, T.DASH }
local MP_SUFFIX = { T.SP, T.M, T.P }
local ZERO_CHAR = 0xb4

local function assertRun(x0, y, bytes, what)
  for i, b in ipairs(bytes) do
    H.assertEq(cell(x0 + i - 1, y), b,
      string.format("%s: cell {%d,%d}", what, x0 + i - 1, y))
  end
end

local function assertLearnedRow(i)
  local id, y = BLITZ_ATK0 + i, blitzRow(i)
  assertRun(NAME_COL, y, nameBytes(id),
    string.format("blitz %d name %s", i, nameText(id)))
  local want = iconGlyph(id)
  H.assertEq(cell(ICON_COL, y), want, string.format(
    "blitz %d (%s) draws the probe icon its own data gives it -- element "
    .. "first, break class second -- at {%d,%d}", i, nameText(id), ICON_COL, y))
  if want ~= PAD then
    H.assertEq(fontCellHasArt(want), true, string.format(
      "blitz %d (%s) names font cell $%02x, so the MENU font must carry art "
      .. "there (%s)", i, nameText(id), want,
      ELEM_CELLS[want] and "an element tile -- #53's upload"
        or "a class glyph -- vanilla art"))
  end
  local cost = costOf(id)
  H.assertEq(cost > 0, true, string.format(
    "blitz %d (%s) is priced", i, nameText(id)))
  local tens = cost // 10
  H.assertEq(cell(COST_COL, y), tens > 0 and (ZERO_CHAR + tens) or PAD,
    string.format("blitz %d cost %d: tens cell", i, cost))
  H.assertEq(cell(COST_COL + 1, y), ZERO_CHAR + (cost % 10),
    string.format("blitz %d cost %d: ones cell", i, cost))
  assertRun(COST_COL + 2, y, MP_SUFFIX, string.format("blitz %d ' MP'", i))
end

local function assertLockedRow(i)
  local y = blitzRow(i)
  assertRun(NAME_COL, y, LOCKED, string.format("blitz %d '- LOCKED -'", i))
  H.assertEq(cell(ICON_COL, y), PAD, string.format(
    "blitz %d is not learned, so it advertises no probe", i))
  for x = COST_COL, COST_COL + 4 do
    H.assertEq(cell(x, y), PAD, string.format(
      "blitz %d is not learned, so it carries no price at {%d,%d}", i, x, y))
  end
end

-- filled in once the menu is open
local sabinSlot, learnedMask

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.worldHasControl() or H.hasControl() end,
    600, "control at the vector doorstep", 5),

  -- the player's path in: X opens the menu.  driveUntil, not one press: this
  -- fixture is a cold anchor boot and the frame the state lands on is not
  -- something a single 4-frame press can be pinned to.
  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),
  H.pressButtons({ "down" }, 2),         -- Items -> Skills
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.waitFrames(10),

  -- FIND Sabin rather than assume his row.
  H.call(function()
    local ids = {}
    for s = 0, 3 do
      local id = H.readByte(ZCHARID + s)
      ids[#ids + 1] = string.format("slot %d = char $%02x", s, id)
      if id == CHAR_SABIN and sabinSlot == nil then sabinSlot = s end
    end
    H.log("party: " .. table.concat(ids, ", "))
    H.assertEq(sabinSlot ~= nil, true,
      "vector_doorstep's party must contain SABIN -- post-opera-v1's manifest "
      .. "says LOCKE CELES SABIN EDGAR.  Without him this test is not testing "
      .. "the thing it exists to test, so it fails rather than falls back")
    -- his own record carries Blitz; the test does not install it
    local base = CHAR_REC + CHAR_STRIDE * CHAR_SABIN
    local has = false
    for i = 0, 3 do
      if H.readByte(base + CHAR_CMD + i) == BATTLE_CMD_BLITZ then has = true end
    end
    H.assertEq(has, true,
      "SABIN's own character record carries BATTLE_CMD::BLITZ -- this test "
      .. "pokes no command byte, unlike menu_blitzpage.lua's staged Terra")
    learnedMask = H.readByte(BLITZES)
    H.log(string.format("known-blitz mask $1D28 = $%02x (as saved, not poked)",
      learnedMask))
  end),

  -- walk the character cursor onto his slot.  $4b is the LIVE cursor index on
  -- the character page; zSelIndex ($28) is where the confirm LATCHES it, and is
  -- asserted below once A has been pressed -- the two together are what proves
  -- the page opened for the row the sprite was on.
  H.driveUntil(function() return H.readByte(ZCURSOR) == sabinSlot end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "cursor onto SABIN"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.readByte(ZSELINDEX), sabinSlot,
      "the confirm latched SABIN's party slot (zSelIndex), so every page "
      .. "below is HIS -- this is the assertion the synthetic fixture cannot "
      .. "make, because there the page belonged to Terra")
    H.assertEq(H.readByte(BLITZ_ROW_COLOR), COLOR_ENABLED,
      "the Blitz row is lit for SABIN because his record says so "
      .. "(zSkillsTextColor::Blitz; $24 would be greyed)")
  end),

  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == SKILLS_ROW_BLITZ
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "skills cursor to Blitz"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_BLITZ end, 300,
    "SABIN's Blitz page, opened the way a player opens it", 5),
  H.waitFrames(90),

  H.call(function()
    -- the page must be showing SOMETHING, or the assertions below are empty
    local nLearned = 0
    for i = 0, 7 do if (learnedMask >> i) & 1 == 1 then nLearned = nLearned + 1 end end
    H.assertEq(nLearned > 0, true,
      "a mid-game Sabin has learned Blitzes; a zero mask would mean this "
      .. "fixture renders eight locked rows and proves nothing about the "
      .. "learned path")

    local elemRows = 0
    for i = 0, 7 do
      local id = BLITZ_ATK0 + i
      local learned = ((learnedMask >> i) & 1) == 1
      H.log(string.format("blitz %d %s: %s, icon $%02x, %d MP", i, nameText(id),
        learned and "learned" or "LOCKED", iconGlyph(id), costOf(id)))
      if learned then
        assertLearnedRow(i)
        if ELEM_CELLS[iconGlyph(id)] then elemRows = elemRows + 1 end
      else
        assertLockedRow(i)
      end
    end

    -- #53's point, stated as a property of this render: a real Sabin's real
    -- page carries at least one real ELEMENT icon.  Before #53 the field font
    -- had no element tiles and every one of these rows drew a blank cell.
    H.assertEq(elemRows > 0, true,
      "at least one learned Blitz shows an ELEMENT icon -- AuraBolt is holy, "
      .. "Fire Dance fire, Air Blade wind, and this is the cue #53 exists to "
      .. "put on the page.  Zero here means either the fixture regressed to a "
      .. "level below AuraBolt or the font upload stopped happening")
    H.log(string.format("REAL SABIN: %d of 8 rungs learned, %d of them showing "
      .. "an element icon", nLearned, elemRows))
    H.screenshot("blitz_page_real_sabin")
  end),
})
