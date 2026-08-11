-- probe_esperdetail_checkpoint.lua -- issue #27's verification instrument.
--
-- The same menu drive and cell-level assertions as menu_esperdetail.lua (the
-- suite test), booted instead from a cold Continue off the tracked post-Opera
-- battery checkpoint, which survives ROM changes (issue #9) where savestate
-- fixtures do not.  Run it in a tree whose fixtures are stale against a fresh
-- menu-bank build:
--
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/post-opera-v1 \
--     tools/tests/run.sh tools/tests/probe_esperdetail_checkpoint.lua
--
-- The Continue sequence is gen_vector_entry.lua's.  The party is LOCKE
-- CELES SABIN EDGAR on the world map at (137,203); the field menu opens from
-- the world map the same way as from a field map.  The esper inventory is
-- pinned to IFRIT and TERRATO (no mod) as in the suite test.
--
-- #62 rebuilt what this asserts: Ot6EsperStatTbl is now two bytes per esper in
-- vanilla's equipment layout (four signed nibbles), so the single
-- "While worn...<Stat> + N" line at row 27 became a caption on the title row
-- plus one term per nonzero delta packed down from row 17.  Ifrit's row is
-- +6 vigor / +4 stamina / -3 mag.pwr, three terms including a minus sign.  The
-- assertions here track menu_esperdetail.lua's cell for cell.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local ZLISTTYPE  = 0x2a
local ZCURSOR    = 0x4b
local Z99        = 0x99
local SKILLCOLOR = 0x79
local ESPERS     = 0x1a69
local GENJULIST  = 0x9d89
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LIST, ST_DETAIL = 0x05, 0x06, 0x0a, 0x1e, 0x4d

local IFRIT, TERRATO = 1, 4

local BG1B = 0x4049
local function cell(x, y) return H.readByte(BG1B + x * 2 + y * 64) end

local CH_W, CH_PLUS, CH_MINUS, CH_DOT, CH_PCT, CH_COLON =
  0x96, 0xca, 0xc4, 0xc5, 0xcd, 0xc1
local BLANK = 0xff
local function digit(n) return 0xb4 + n end      -- '0' = $b4 .. '9' = $bd

-- Stat name tiles, verbatim from menu_text_en.inc.raw:111-114 (7 tiles each).
local STAT = {
  VIGOR   = { 0x95, 0xa2, 0xa0, 0xa8, 0xab, 0xff, 0xff },
  SPEED   = { 0x92, 0xa9, 0x9e, 0x9e, 0x9d, 0xff, 0xff },
  STAMINA = { 0x92, 0xad, 0x9a, 0xa6, 0xa2, 0xa7, 0x9a },
  MAGPWR  = { 0x8c, 0x9a, 0xa0, 0xc5, 0x8f, 0xb0, 0xab },
}

local function st() return H.readByte(ZMENUSTATE) end

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

-- #62 took over cols 17-27 of the spell rows and cols 13-28 of the title row,
-- so the cells the old form of this check used there are replaced by a broader
-- check of the same class: neither the percent glyph nor the learn-rate
-- colon may appear anywhere in the window's rows.
local function assertDeadColumnsGone(tag)
  H.assertEq(cell(12, 17), BLANK, tag .. ": no rate colon after spell 1's name")
  for y = 15, 27, 2 do
    for x = 0, 31 do
      H.assertEq(cell(x, y) ~= CH_PCT, true,
        string.format("%s: no percent glyph in the window {%d,%d}", tag, x, y))
      H.assertEq(cell(x, y) ~= CH_COLON, true,
        string.format("%s: no learn-rate colon in the window {%d,%d}", tag, x, y))
    end
  end
end

local function assertCaption(tag, present)
  if present then
    H.assertEq(cell(13, 15), BLANK, tag .. ": caption pad blank at {13,15}")
    H.assertEq(cell(14, 15), BLANK, tag .. ": caption pad blank at {14,15}")
    H.assertEq(cell(15, 15), CH_W, tag .. ": 'While worn...' starts at {15,15}")
    H.assertEq(cell(27, 15), CH_DOT, tag .. ": caption ends at {27,15}")
  else
    for x = 13, 28 do
      H.assertEq(cell(x, 15), BLANK,
        string.format("%s: no caption at all -- {%d,15} blank", tag, x))
    end
  end
end

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
    string.format("%s: term %d sign at {25,%d}", tag, slot, y))
  H.assertEq(cell(26, y), BLANK,
    string.format("%s: term %d leading zero blanked at {26,%d}", tag, slot, y))
  H.assertEq(cell(27, y), digit(magnitude),
    string.format("%s: term %d magnitude %d at {27,%d}", tag, slot, magnitude, y))
end

local function assertTermRowBlank(tag, slot)
  local y = 17 + slot * 2
  for x = 17, 27 do
    H.assertEq(cell(x, y), BLANK,
      string.format("%s: unused term row %d blank at {%d,%d}", tag, slot, x, y))
  end
end

local function assertOldLineGone(tag)
  for x = 5, 27 do
    H.assertEq(cell(x, 27), BLANK,
      string.format("%s: #27's old row-27 line cleared at {%d,27}", tag, x))
  end
end

H.run({ maxFrames = 80000 }, {
  -- gen_vector_entry.lua's cold Continue off the battery checkpoint.
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function()
    return (H.mapId() & 0x1ff) == 0 and H.worldHasControl()
      and H.worldAligned()
  end, 3000, "cold Continue to post-Opera world entry point", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "cold Continue fade-in", 10),

  -- Pin the esper inventory to exactly IFRIT + TERRATO (bits 1 and 4).
  H.call(function()
    H.log(string.format("[pin] $1a69 was %02x; pinning IFRIT+TERRATO",
      H.readByte(ESPERS)))
    H.writeByte(ESPERS + 0, 0x12)
    H.writeByte(ESPERS + 1, 0x00)
    H.writeByte(ESPERS + 2, 0x00)
    H.writeByte(ESPERS + 3, 0x00)
  end),

  -- X opens the menu (world map and field share the menu program).
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

  -- ---- IFRIT: the stone with a while-worn mod (+5 vigor) ----------------
  listSeek(IFRIT, "cursor to IFRIT's row"),
  H.waitFrames(20),                     -- let any list scroll finish (A is
                                        -- ignored while ScrollListPage runs)
  H.driveUntil(function() return st() == ST_DETAIL end, 600,
    { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, "Ifrit detail"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(Z99), IFRIT, "detail page is IFRIT's")
    assertDeadColumnsGone("ifrit")
    H.assertEq(cell(5, 17) ~= BLANK, true, "ifrit: spell 1 name drawn at {5,17}")
    assertCaption("ifrit", true)
    assertTerm("ifrit", 0, STAT.VIGOR,   "Vigor",   CH_PLUS,  6)
    assertTerm("ifrit", 1, STAT.STAMINA, "Stamina", CH_PLUS,  4)
    assertTerm("ifrit", 2, STAT.MAGPWR,  "Mag.Pwr", CH_MINUS, 3)
    assertTermRowBlank("ifrit", 3)
    assertTermRowBlank("ifrit", 4)
    assertOldLineGone("ifrit")
    H.screenshot("esper_detail_ifrit_checkpoint")
    H.log("IFRIT: dead columns gone; Vigor +6 / Stamina +4 / Mag.Pwr -3 drawn")
  end),

  H.pressButtons({ "b" }, 2),
  H.waitUntil(function() return st() == ST_LIST end, 300, "back to list", 5),
  H.waitFrames(10),

  -- ---- TERRATO: a stone with no mod (Ot6EsperStatTbl $00) ---------------
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
    assertCaption("terrato", false)
    for slot = 0, 4 do assertTermRowBlank("terrato", slot) end
    assertOldLineGone("terrato")
    H.screenshot("esper_detail_terrato_checkpoint")
    H.log("TERRATO: page clean in the no-mod state -- no caption, no terms")
  end),

  H.call(function()
    H.log("PASSED: esper detail shows the while-worn stat mod, hides the "
      .. "dead learn-rate columns, and is correct with and without a mod")
  end),
})
