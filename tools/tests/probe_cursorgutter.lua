-- probe_cursorgutter.lua -- the isolated instrument for issue #43's third
-- round.  Not a suite test (no @suite marker): it asserts one rule, on both
-- OT6 configurator pages, and nothing else.
--
-- The rule.  The field menu's cursor is a 16x16 sprite and `cursor_pos {x, y}`
-- is its top-left corner (menu_ram.inc:582-584; the macro is `.byte x, y`).
-- So an entry at x covers tilemap columns x/8 and x/8+1, and the row it
-- points at must begin at column x/8 + 2:
--
--     cursor_x = 8 * text_col - 16
--
-- Vanilla follows it throughout this window: magic draws at cols 3/16
-- under cursors 8/112 (skills.asm:831, :836 vs :125-126), espers at 3/17 under
-- 8/120 (:1733, :1737 vs :249-250), rage at 5/19 under 24/136 (:1544, :1548 vs
-- :292-293), and the config menu's value column 14 under 96 (config.asm:50).
-- Measured on the shipped ROM too: probe_menucols.lua diffs two frames of the
-- untouched magic list and finds the sprite for `cursor_pos {8, 116}` occupying
-- screen x 8..23, y 116..131 exactly.
--
-- Why this is a separate file.  menu_swdtechpage.lua and menu_ragepage.lua
-- carry this canary too, but they also assert every cell of their pages, so on
-- a ROM with the old column layout they fail on a title glyph before the
-- cursor rule is evaluated.  This probe asserts nothing about which glyph is
-- where, only that the cursor does not sit on one, so it provides the
-- fail-before evidence for the fix: it fails on the pre-fix ROM and names the
-- covered cell, and passes on the fixed ROM, with no other assertion in the
-- way.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/arvis_wake.mss.lua"

local ZMENUSTATE, ZCURSOR = 0x26, 0x4b
-- The lead's four battle-command bytes are $1616..$1619 ($0016..$0019 off the
-- character record; _c34d3d walks all four to colour the skills rows,
-- skills.asm:390-401).  Installing BUSHIDO in one and RAGE in another lights
-- BOTH configurator rows, so one menu trip reaches both pages.
local CMD3, CMD4 = 0x1618, 0x1619
local LEARNED, LOADOUT = 0x1cf7, 0x1e1d
local RAGES, RAGELOAD = 0x1d2c, 0x1e1f
local BATTLE_CMD_BUSHIDO, BATTLE_CMD_RAGE = 0x07, 0x10
local ST_MAIN, ST_CHAR, ST_SKILLS = 0x05, 0x06, 0x0a
local ST_LOADOUT, ST_RAGELOAD = 0x7b, 0x7c
local SKILLS_ROW_BUSHIDO, SKILLS_ROW_RAGE = 2, 5

local BG1A = 0x3849
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end
local function st() return H.readByte(ZMENUSTATE) end

-- The rule, applied to one cursor table entry.  Both sides are read from the
-- running game: the cursor from the ROM the menu indexes, the text from the
-- tilemap it drew.
local function gutter(base, n, page)
  local cx = H.readRomByte(base + n * 2)
  local cy = H.readRomByte(base + n * 2 + 1)
  local col, y = cx // 8, (cy - 116) // 6 + 1
  H.log(string.format("%s: cursor %d at x=%d,y=%d -> row %d, gutter cols %d-%d,"
    .. " row starts at col %d; cells {%d,%d}=%02x {%d,%d}=%02x {%d,%d}=%02x",
    page, n, cx, cy, y, col, col + 1, col + 2,
    col, y, cell(col, y), col + 1, y, cell(col + 1, y),
    col + 2, y, cell(col + 2, y)))
  for _, x in ipairs({ col, col + 1 }) do
    H.assertEq(cell(x, y), 0, string.format(
      "%s: cursor %d sits at x=%d, so the 16px sprite covers tilemap {%d,%d} "
      .. "-- a glyph there is drawn UNDER the cursor", page, n, cx, x, y))
  end
  H.assertEq(cell(col + 2, y) ~= 0, true, string.format(
    "%s: cursor %d at x=%d reserves columns %d-%d, so its row must start at "
    .. "column %d (cursor_x = 8*col - 16)", page, n, cx, col, col + 1, col + 2))
end

-- NB: H.sym must be called with a string literal.  compose.py scans the
-- source for H.sym calls to decide which symbols to bake into OT6_SYMS, so a
-- variable argument resolves to nothing at runtime.  (This note used to spell
-- the call out with a placeholder name in it, which the scanner collected and
-- then warned about as a missing symbol on every compose of this file.
-- Naming a symbol that exists is harmless; naming one that does not produces
-- a warning.)
local BUSH_CURSOR = H.sym("Ot6LoadoutCursorPos") & 0x3FFFFF
local RAGE_CURSOR = H.sym("Ot6RageCursorPos") & 0x3FFFFF

local function checkPage(base, count, page)
  for n = 0, count - 1 do gutter(base, n, page) end
  H.log(page .. ": every cursor entry clears its row's leading glyph")
end

-- from the skills submenu: put the cursor on `row` and press A.
local function openPage(row, want, label)
  return {
    H.driveUntil(function()
      return st() == ST_SKILLS and H.readByte(ZCURSOR) == row
    end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
      "skills cursor to " .. label),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == want end, 300, label .. " page open", 5),
    H.waitFrames(90),
  }
end

local seq = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),
  H.call(function()
    H.writeByte(CMD3, BATTLE_CMD_BUSHIDO)
    H.writeByte(CMD4, BATTLE_CMD_RAGE)
    H.writeByte(LEARNED, 0xff)              -- all eight, so every row has text
    H.writeByte(LOADOUT, 0)
    H.writeByte(LOADOUT + 1, 0)
    for i = 0, 31 do H.writeByte(RAGES + i, 0xff) end   -- every species hunted
    for i = 0, 7 do H.writeByte(RAGELOAD + i, 0) end
  end),

  -- the player's path as far as the skills submenu; both pages hang off it.
  H.pressButtons({ "x" }, 4),
  H.waitUntil(function() return st() == ST_MAIN end, 600, "main menu", 5),
  H.waitFrames(20),
  H.pressButtons({ "down" }, 2),            -- Items -> Skills
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "char select", 5),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(10),
}
for _, s in ipairs(openPage(SKILLS_ROW_BUSHIDO, ST_LOADOUT, "SwdTech")) do
  seq[#seq + 1] = s
end
seq[#seq + 1] = H.call(function()
  checkPage(BUSH_CURSOR, 3, "BUSHIDO LOADOUT")
  H.screenshot("gutter_bushido")
end)

-- B saves-and-exits back to the skills submenu; the Rage row is lit too.
seq[#seq + 1] = H.pressButtons({ "b" }, 3)
seq[#seq + 1] = H.waitUntil(function() return st() == ST_SKILLS end, 300,
  "back to the skills submenu", 5)
seq[#seq + 1] = H.waitFrames(20)
for _, s in ipairs(openPage(SKILLS_ROW_RAGE, ST_RAGELOAD, "Rage")) do
  seq[#seq + 1] = s
end
seq[#seq + 1] = H.call(function()
  checkPage(RAGE_CURSOR, 8, "RAGE LOADOUT")
  H.screenshot("gutter_rage")
  H.log("PASSED: both OT6 configurator pages obey cursor_x = 8*col - 16")
end)

H.run({ maxFrames = 40000 }, seq)
