-- @suite savestate=esper_tubes
-- menu_esperdetail_tube6.lua -- the six tube-room stones on the esper detail
-- page.  The detail page renders the granted spell names and the while-worn
-- stat mod straight out of GenjuProp and Ot6EsperStatTbl; this file drives
-- the real menu UI to three detail pages and asserts the rendered tiles.
--
-- Ot6EsperStatTbl is two bytes per esper in vanilla's own equipment layout
-- (four signed nibbles, -7..+7 each), so a stone carries up to four deltas
-- and any of them can be negative.  The caption rides the title row and one
-- term per nonzero delta packs downward from row 17, in the columns vanilla
-- used for its dead learn-rate data.
--
-- Drive: X -> Skills -> character -> Espers -> list -> detail, from the
-- esper_tubes fixture, whose bag holds the boot roster (RAMUH IFRIT SHIVA
-- SIREN) plus the six give_genju grants SHOAT MADUIN BISMARK CARBUNKL
-- PHANTOM UNICORN.  MADUIN and UNICORN are rendered for stones the save
-- owns, with no inventory write.
--
-- One labeled isolation arm: the TERRATO page is the page's empty control
-- (Ot6EsperStatTbl $0000, no caption and no terms), and no stone this save
-- owns carries a $0000 row, so the single write below ORs Terrato's bit into
-- $1a69, adding one list row.
--
-- The three pages:
--   MADUIN  (6)  three spell rows Fire / Ice / Bolt, and a three-term stat
--                block: vigor -3, stamina +3, mag.pwr +7.  Speed is zero and
--                costs no line.
--   TERRATO (4)  the no-mod control: no caption and no term anywhere.
--   UNICORN (23) the Pearl grant.  Two spell rows (Pearl, Remedy); rows 3-5
--                are blank.  Its stat block is the two-term shape (stamina
--                +5, mag.pwr +2) with no downside.
--
-- How names are asserted.  DrawGenjuMagicName blits a 7-tile MagicName record
-- (icon byte then up to 6 name tiles, $ff-padded; 7-byte stride) to cols 5-11
-- of the row, then blanks cols 12-19; empty slots blank all 15.  Rows are
-- y=17,19,21,23,25.  The expected byte runs below are those records copied
-- exactly: Fire is `e9 85 a2 ab 9e ff ff` and Fire 2 is
-- `e9 85 a2 ab 9e fe b6`, which differ only in the last two tiles.
--
-- The stat block (skills.asm's DrawEsperDetailMenu tail):
--   caption "While worn..." right-aligned in the 16-cell field at {13,15}:
--     cols 13-14 blank, cols 15-27 the 13 caption tiles;
--   one term per nonzero delta, packed downward over rows 17/19/21/23/25:
--     7-tile stat name at cols 17-23 (Ot6GenjuStatNameTbl, space-padded), a
--     spacer at col 24, sign at col 25 ('+' $ca / '-' $c4), magnitude at cols
--     26-27 with the leading zero blanked;
--   unused term rows: cols 17-27 blank.  Row 27: blank.
--
-- assertRowEmpty asserts cols 5-19 of an unused spell row; cols 18-19 of that
-- range are inside the stat block's field, because the block writes all
-- eleven cells 17-27 of every row it touches and blanks all eleven on rows it
-- does not.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/esper_tubes.mss.lua"

local ZMENUSTATE = 0x26                 -- menu direct-page vars (menu_ram.inc)
local ZLISTTYPE  = 0x2a
local ZCURSOR    = 0x4b
local Z99        = 0x99                 -- detail page's esper index
local SKILLCOLOR = 0x79                 -- zSkillsTextColor[0] = Espers row
local ESPERS     = 0x1a69               -- owned-esper bitfield, 27 bits
local GENJULIST  = 0x9d89               -- $7e9d89: list row -> esper index
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LIST, ST_DETAIL = 0x05, 0x06, 0x0a, 0x1e, 0x4d

local MADUIN, TERRATO, UNICORN = 6, 4, 23

local BG1B = 0x4049
local function cell(x, y) return H.readByte(BG1B + x * 2 + y * 64) end

local BLANK    = 0xff
local CH_W     = 0x96                   -- 'W' of "While worn..."
local CH_DOT   = 0xc5                   -- '.' -- the caption's ellipsis
local CH_PLUS  = 0xca
local CH_MINUS = 0xc4                   -- a delta can be negative
-- digit tiles: '0' = $b4 .. '9' = $bd (text_en.json)
local function digit(n) return 0xb4 + n end

-- MagicName records, copied from ff6/src/text/magic_name_en.dat (7-byte
-- stride; byte 0 is the school icon: $e9 attack, $ea effect, $e8 heal).
local NAME = {
  FIRE   = { 0xe9, 0x85, 0xa2, 0xab, 0x9e, 0xff, 0xff },
  ICE    = { 0xe9, 0x88, 0x9c, 0x9e, 0xff, 0xff, 0xff },
  BOLT   = { 0xe9, 0x81, 0xa8, 0xa5, 0xad, 0xff, 0xff },
  PEARL  = { 0xe9, 0x8f, 0x9e, 0x9a, 0xab, 0xa5, 0xff },
  REMEDY = { 0xe8, 0x91, 0x9e, 0xa6, 0x9e, 0x9d, 0xb2 },
  QUAKE  = { 0xe9, 0x90, 0xae, 0x9a, 0xa4, 0x9e, 0xff },
  QUARTR = { 0xe9, 0x90, 0xae, 0x9a, 0xab, 0xad, 0xab },
  -- "W Wind": tile 2 is $fe, the narrow-space glyph, not the $ff blank.
  W_WIND = { 0xe9, 0x96, 0xfe, 0x96, 0xa2, 0xa7, 0x9d },
}

-- Ot6GenjuStatNameTbl entries (skills.asm:3058, menu_text_en.inc:110-113),
-- 7 tiles each, space-padded; space is $ff, the same tile as blank.
local STAT = {
  VIGOR   = { 0x95, 0xa2, 0xa0, 0xa8, 0xab, 0xff, 0xff },
  SPEED   = { 0x92, 0xa9, 0x9e, 0x9e, 0x9d, 0xff, 0xff },
  STAMINA = { 0x92, 0xad, 0x9a, 0xa6, 0xa2, 0xa7, 0x9a },
  MAGPWR  = { 0x8c, 0x9a, 0xa0, 0xc5, 0x8f, 0xb0, 0xab },
}

local function st() return H.readByte(ZMENUSTATE) end

-- Walk the esper list cursor onto the slot holding esper `idx`.  Two-column
-- grid: $4b is a linear slot index whose parity is the column, so down/up
-- move by 2 and a parity change needs a left/right press first.
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

-- Dump a spell row's 7 name tiles as hex.
local function rowHex(slot)
  local y = 17 + slot * 2
  local t = {}
  for k = 0, 6 do t[#t + 1] = string.format("%02x", cell(5 + k, y)) end
  return table.concat(t, " ")
end

local function assertRow(tag, slot, want, label)
  local y = 17 + slot * 2
  for k = 0, 6 do
    H.assertEq(cell(5 + k, y), want[k + 1],
      string.format("%s: row %d tile %d = %s", tag, slot + 1, k, label))
  end
end

-- An unused spell slot: DrawGenjuMagicName blanks all 15 tiles of the field.
local function assertRowEmpty(tag, slot)
  local y = 17 + slot * 2
  for x = 5, 19 do
    H.assertEq(cell(x, y), BLANK,
      string.format("%s: row %d empty at {%d,%d}", tag, slot + 1, x, y))
  end
end

local function assertCaption(tag, present)
  if present then
    H.assertEq(cell(13, 15), BLANK, tag .. ": caption pad blank at {13,15}")
    H.assertEq(cell(14, 15), BLANK, tag .. ": caption pad blank at {14,15}")
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
    string.format("%s: term %d sign %s at {25,%d}", tag, slot,
      sign == CH_MINUS and "'-'" or "'+'", y))
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

-- Nothing draws to row 27; the page must clear it.
local function assertOldLineGone(tag)
  for x = 5, 27 do
    H.assertEq(cell(x, 27), BLANK,
      string.format("%s: #27's old row-27 line cleared at {%d,27}", tag, x))
  end
end

local function logPage(tag)
  H.log(string.format("[%s] esper=%d rows: 1=%s 2=%s 3=%s 4=%s 5=%s",
    tag, H.readByte(Z99), rowHex(0), rowHex(1), rowHex(2), rowHex(3), rowHex(4)))
  local cap = {}
  for x = 13, 28 do cap[#cap + 1] = string.format("%02x", cell(x, 15)) end
  H.log(string.format("[%s] caption field: %s", tag, table.concat(cap, " ")))
  for slot = 0, 4 do
    local t = {}
    for x = 17, 27 do t[#t + 1] = string.format("%02x", cell(x, 17 + slot * 2)) end
    H.log(string.format("[%s] term row %d: %s", tag, slot, table.concat(t, " ")))
  end
end

local toList = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  H.call(function()
    H.log(string.format("[espers] $1a69 = %02x %02x %02x %02x (read)",
      H.readByte(ESPERS), H.readByte(ESPERS + 1), H.readByte(ESPERS + 2),
      H.readByte(ESPERS + 3)))
    H.assertEq(H.readByte(ESPERS) & 0xEF, 0xEF,
      "the save owns RAMUH IFRIT SHIVA SIREN + SHOAT MADUIN BISMARK")
    H.assertEq(H.readByte(ESPERS + 2) & 0x98, 0x98,
      "... and CARBUNKL PHANTOM UNICORN (the give_genju receipts)")
  end),

  H.call(function()
    H.writeByte(ESPERS + 0, H.readByte(ESPERS) | 0x10)
    H.log("[isolation arm] TERRATO's bit OR'd into $1a69 -- the $0000 no-mod "
      .. "control, unreachable on this savestate chain (see header)")
  end),

  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),

  H.pressButtons({ "down" }, 2),            -- Items -> Skills
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(10),

  H.call(function()
    H.assertEq(H.readByte(SKILLCOLOR), 0x20,
      "Espers row enabled (the save owns stones)")
  end),
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == 0
  end, 600, { H.pressButtons({ "up" }, 2), H.waitFrames(6) },
    "skills submenu cursor to Espers"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_LIST end, 300, "esper list", 5),
  H.call(function()
    H.assertEq(H.readByte(ZLISTTYPE), 4, "list type GENJU (menu_ram.inc)")
  end),
}

local all = {}
local function add(list) for _, s in ipairs(list) do all[#all + 1] = s end end
add(toList)

-- Open one stone's detail page, then run `body`.
local function page(idx, name)
  return {
    listSeek(idx, "cursor to " .. name .. "'s row"),
    H.waitFrames(20),                   -- A is ignored while ScrollListPage runs
    H.driveUntil(function() return st() == ST_DETAIL end, 600,
      { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, name .. " detail"),
    H.waitFrames(30),                   -- let the page draw + DMA settle
  }
end
local function backToList()
  return {
    H.pressButtons({ "b" }, 2),
    H.waitUntil(function() return st() == ST_LIST end, 300, "back to list", 5),
    H.waitFrames(10),
  }
end

add(page(MADUIN, "Maduin"))
add({ H.call(function()
  H.assertEq(H.readByte(Z99), MADUIN, "detail page is MADUIN's")
  logPage("maduin")
  assertRow("maduin", 0, NAME.FIRE, "Fire (base tier, not Fire 2)")
  assertRow("maduin", 1, NAME.ICE,  "Ice (base tier, not Ice 2)")
  assertRow("maduin", 2, NAME.BOLT, "Bolt (base tier, not Bolt 2)")
  assertRowEmpty("maduin", 3)
  assertRowEmpty("maduin", 4)
  assertCaption("maduin", true)
  assertTerm("maduin", 0, STAT.VIGOR,   "Vigor",   CH_MINUS, 3)
  assertTerm("maduin", 1, STAT.STAMINA, "Stamina", CH_PLUS,  3)
  assertTerm("maduin", 2, STAT.MAGPWR,  "Mag.Pwr", CH_PLUS,  7)
  assertTermRowBlank("maduin", 3)
  assertTermRowBlank("maduin", 4)
  assertOldLineGone("maduin")
  H.screenshot("esper_detail_maduin")
  H.log("MADUIN: three base tiers drawn; Vigor -3 / Stamina +3 / Mag.Pwr +7")
end) })
add(backToList())

add(page(TERRATO, "Terrato"))
add({ H.call(function()
  H.assertEq(H.readByte(Z99), TERRATO, "detail page is TERRATO's")
  logPage("terrato")
  assertRow("terrato", 0, NAME.QUAKE,  "Quake (untouched vanilla row)")
  assertRow("terrato", 1, NAME.QUARTR, "Quartr (untouched vanilla row)")
  assertRow("terrato", 2, NAME.W_WIND, "W Wind (untouched vanilla row)")
  assertRowEmpty("terrato", 3)
  assertRowEmpty("terrato", 4)
  assertCaption("terrato", false)
  for slot = 0, 4 do assertTermRowBlank("terrato", slot) end
  assertOldLineGone("terrato")
  H.screenshot("esper_detail_terrato_tube6")
  H.log("TERRATO: still the no-mod control after #62; no caption, no terms")
end) })
add(backToList())

add(page(UNICORN, "Unicorn"))
add({ H.call(function()
  H.assertEq(H.readByte(Z99), UNICORN, "detail page is UNICORN's")
  logPage("unicorn")
  assertRow("unicorn", 0, NAME.PEARL,  "Pearl (branch A -- not Cure 2)")
  assertRow("unicorn", 1, NAME.REMEDY, "Remedy")
  assertRowEmpty("unicorn", 2)
  assertRowEmpty("unicorn", 3)
  assertRowEmpty("unicorn", 4)
  assertCaption("unicorn", true)
  assertTerm("unicorn", 0, STAT.STAMINA, "Stamina", CH_PLUS, 5)
  assertTerm("unicorn", 1, STAT.MAGPWR,  "Mag.Pwr", CH_PLUS, 2)
  assertTermRowBlank("unicorn", 2)
  assertTermRowBlank("unicorn", 3)
  assertTermRowBlank("unicorn", 4)
  assertOldLineGone("unicorn")
  H.screenshot("esper_detail_unicorn")
  H.log("UNICORN: Pearl + Remedy only; Stamina +5 / Mag.Pwr +2")
end) })

add({ H.call(function()
  H.log("PASSED: the tube-room six render their new grant lists and stat "
    .. "lines on the real esper detail page")
end) })

H.run({ maxFrames = 40000 }, all)
