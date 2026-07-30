-- @suite frontier=arvis_wake
-- menu_esperdetail_tube6.lua -- the SIX TUBE-ROOM STONES on the esper detail
-- page (docs/design/magicite-tube-six.md §11, issue #31).
--
-- The design doc's closing claim is "menu copy: zero work required" -- the
-- detail page renders the granted spell names and the while-worn stat mod
-- straight out of GenjuProp and Ot6EsperStatTbl, so authoring those two tables
-- IS the whole player-facing job.  That claim is only worth anything if
-- something checks it, which is this file: it drives the real menu UI to three
-- detail pages and asserts the rendered TILES, not the tables.
--
-- #62 CHANGED WHAT "the stat mod" LOOKS LIKE.  Ot6EsperStatTbl is now two bytes
-- per esper in vanilla's own equipment layout (four SIGNED nibbles, -7..+7
-- each), so a stone carries up to four deltas and any of them can be negative.
-- The page's single "While worn...<Stat> + N" line at row 27 is gone; in its
-- place the caption rides the TITLE row and one term per nonzero delta packs
-- downward from row 17, in the columns vanilla used for its dead learn-rate
-- data.  Every stat-line assertion below was rewritten to that layout, and the
-- three pages now assert MORE than before, not less: each checks the exact
-- tiles of every term it should have, that the rows it should NOT have are
-- blank, and (Maduin) that a MINUS sign renders.
--
-- Same drive and same instrument as menu_esperdetail.lua (issue #27): X ->
-- Skills -> character -> Espers -> list -> detail from the arvis_wake fixture,
-- with the esper inventory pinned directly (the battle_bushido "install state"
-- house pattern) because arvis_wake owns no stones yet.  That file stays as it
-- is -- it is #27's shipped gate on the page's SHAPE (dead columns gone, mod
-- and no-mod both correct) and this one is #31's gate on the page's CONTENT.
--
-- THE THREE PAGES:
--   MADUIN  (6)  the marquee, twice over.  Three spell rows that must read Fire
--                / Ice / Bolt where the shipped ROM drew Fire 2 / Ice 2 / Bolt
--                2, and after #62 a THREE-TERM stat block whose first term is
--                NEGATIVE: vigor -3, stamina +3, mag.pwr +7 (the encoding's
--                ceiling and vanilla's own per-stat ceiling).  Speed is zero, so
--                it must cost no line -- which is what proves the walk packs.
--   TERRATO (4)  the surviving no-mod control.  Its Ot6EsperStatTbl row is
--                still $0000 after #62 (deliberately -- ot6_progression.asm
--                says so on the row), so the honest-empty path is still
--                exercised: NO caption and no term anywhere.  Revisited after
--                Maduin, it proves the page overwrites rather than leaving the
--                previous stone's block behind.
--   UNICORN (23) the Pearl grant -- branch A of the cross-doc holy decision
--                (§9's DECIDED box).  Two spell rows where the shipped ROM
--                drew five, so rows 3-5 must be blank: the deletions are
--                asserted on screen, not just in the table.  Its stat block is
--                the two-term shape (stamina +5, mag.pwr +2) with no downside.
--
-- HOW NAMES ARE ASSERTED.  DrawGenjuMagicName (skills.asm:2759) blits a
-- 7-tile MagicName record -- icon byte then up to 6 name tiles, $ff-padded
-- (ff6/src/text/magic_name_en.dat, 7-byte stride) -- to cols 5-11 of the row,
-- then blanks cols 12-19; empty slots blank all 15.  Rows are y=17,19,21,23,25
-- (the $f5 loop, skills.asm:2578-2612 stepping $0011 -> $001b by 2).  The
-- expected byte runs below are those records verbatim, so a wrong spell id in
-- GenjuProp cannot pass: Fire is `e9 85 a2 ab 9e ff ff` and Fire 2 is
-- `e9 85 a2 ab 9e fe b6`, which differ only in the last two tiles -- exactly
-- the tiles this file compares.
--
-- THE STAT BLOCK (#62, skills.asm's DrawEsperDetailMenu tail):
--   caption "While worn..." right-aligned in the 16-cell field at {13,15} --
--     cols 13-14 blank, cols 15-27 the 13 caption tiles;
--   one term per nonzero delta, packed downward over rows 17/19/21/23/25:
--     7-tile stat name at cols 17-23 (Ot6GenjuStatNameTbl, space-padded), a
--     spacer at col 24, sign at col 25 ('+' $ca / '-' $c4), magnitude at cols
--     26-27 with the leading zero blanked;
--   unused term rows: cols 17-27 blank.  Row 27, the old line's home: blank.
--
-- NOTE ON assertRowEmpty BELOW.  It asserts cols 5-19 of an unused SPELL row,
-- and cols 18-19 of that range are now inside the stat block's field.  That is
-- still correct and is not a coincidence: the block writes all eleven cells
-- 17-27 of every row it touches, and blanks all eleven on rows it does not.  The
-- two ranges therefore agree, and a term landing on a row this file expects
-- empty would fail here loudly.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/arvis_wake.mss.lua"

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
local CH_MINUS = 0xc4                   -- #62: a delta can be negative
-- digit tiles: '0' = $b4 .. '9' = $bd (text_en.json)
local function digit(n) return 0xb4 + n end

-- MagicName records, verbatim from ff6/src/text/magic_name_en.dat (7-byte
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
-- 7 tiles each, space-padded -- space is $ff, the same tile as blank.
local STAT = {
  VIGOR   = { 0x95, 0xa2, 0xa0, 0xa8, 0xab, 0xff, 0xff },
  SPEED   = { 0x92, 0xa9, 0x9e, 0x9e, 0x9d, 0xff, 0xff },
  STAMINA = { 0x92, 0xad, 0x9a, 0xa6, 0xa2, 0xa7, 0x9a },
  MAGPWR  = { 0x8c, 0x9a, 0xa0, 0xc5, 0x8f, 0xb0, 0xab },
}

local function st() return H.readByte(ZMENUSTATE) end

-- Walk the esper list cursor onto the slot holding esper `idx`.  Two-column
-- grid (GenjuCursorProp `cursor_prop {0,0},{2,8}`): $4b is a linear slot index
-- whose parity is the column, so down/up move by 2 and a parity change needs a
-- left/right press first.  Lifted verbatim from menu_esperdetail.lua.
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

-- Dump a spell row's 7 name tiles as hex.  Called BEFORE the matching assert so
-- a run against a pre-change ROM leaves the rendered bytes in the log rather
-- than only a verdict.
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

-- #62's stat block.  assertCaption / assertTerm / assertTermRowBlank /
-- assertOldLineGone replace the single assertStatLine this file used to call.
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

-- Row 27 was #27's single-line home; #62 draws nothing there, so the page must
-- clear it -- asserted for a stone WITH a block as well as without.
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

-- The menu drive up to the esper list, shared by every page below.
local toList = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  -- Pin the esper inventory to exactly MADUIN + TERRATO + UNICORN.
  -- bitfield $1a69, bit n of byte n>>3: MADUIN 6 -> $40 and TERRATO 4 -> $10
  -- in byte 0; UNICORN 23 -> bit 7 of byte 2.
  H.call(function()
    H.log(string.format("[pin] $1a69 was %02x; pinning MADUIN+TERRATO+UNICORN",
      H.readByte(ESPERS)))
    H.writeByte(ESPERS + 0, 0x50)
    H.writeByte(ESPERS + 1, 0x00)
    H.writeByte(ESPERS + 2, 0x80)
    H.writeByte(ESPERS + 3, 0x00)
  end),

  -- driveUntil, not one press: the X that opens the field menu is the first
  -- step in these tests that needs a SPECIFIC frame, so it is where a
  -- fixture minted against a different ROM surfaces -- as "timeout waiting
  -- for main menu", which reads like a menu bug and is not one.  Retrying
  -- the press costs nothing when the pairing is fine and removes the false
  -- report when it is not.  Same shape probe_fieldicons.lua and
  -- menu_blitzpage_sabin.lua already use.  The assertion is unchanged: the
  -- main menu must still come up.
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
    H.assertEq(H.readByte(SKILLCOLOR), 0x20, "Espers row enabled (the pin took)")
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

-- ---- MADUIN: the crown.  Fire/Ice/Bolt + a three-term block with a minus ---
add(page(MADUIN, "Maduin"))
add({ H.call(function()
  H.assertEq(H.readByte(Z99), MADUIN, "detail page is MADUIN's")
  logPage("maduin")
  assertRow("maduin", 0, NAME.FIRE, "Fire (base tier, not Fire 2)")
  assertRow("maduin", 1, NAME.ICE,  "Ice (base tier, not Ice 2)")
  assertRow("maduin", 2, NAME.BOLT, "Bolt (base tier, not Bolt 2)")
  assertRowEmpty("maduin", 3)
  assertRowEmpty("maduin", 4)
  -- Maduin's row is vig -3 / spd 0 / stm +3 / mag +7, so three terms pack onto
  -- rows 17/19/21 with SPEED SKIPPED, and the first of them carries a MINUS.
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

-- ---- TERRATO: the surviving no-mod control, revisited after Maduin -------
add(page(TERRATO, "Terrato"))
add({ H.call(function()
  H.assertEq(H.readByte(Z99), TERRATO, "detail page is TERRATO's")
  logPage("terrato")
  assertRow("terrato", 0, NAME.QUAKE,  "Quake (untouched vanilla row)")
  assertRow("terrato", 1, NAME.QUARTR, "Quartr (untouched vanilla row)")
  assertRow("terrato", 2, NAME.W_WIND, "W Wind (untouched vanilla row)")
  assertRowEmpty("terrato", 3)
  assertRowEmpty("terrato", 4)
  -- No mod ($0000): NO caption and no term anywhere -- INCLUDING the cells
  -- Maduin's page just filled, which is what proves the revisit overwrote them.
  assertCaption("terrato", false)
  for slot = 0, 4 do assertTermRowBlank("terrato", slot) end
  assertOldLineGone("terrato")
  H.screenshot("esper_detail_terrato_tube6")
  H.log("TERRATO: still the no-mod control after #62; no caption, no terms")
end) })
add(backToList())

-- ---- UNICORN: the Pearl grant (branch A) + three deleted rows ------------
add(page(UNICORN, "Unicorn"))
add({ H.call(function()
  H.assertEq(H.readByte(Z99), UNICORN, "detail page is UNICORN's")
  logPage("unicorn")
  assertRow("unicorn", 0, NAME.PEARL,  "Pearl (branch A -- not Cure 2)")
  assertRow("unicorn", 1, NAME.REMEDY, "Remedy")
  -- The shipped row had five spells; Dispel/Safe/Shell are gone, and the page
  -- must show that rather than leaving stale tiles from Terrato's three rows.
  assertRowEmpty("unicorn", 2)
  assertRowEmpty("unicorn", 3)
  assertRowEmpty("unicorn", 4)
  -- Unicorn is vig 0 / spd 0 / stm +5 / mag +2: the two-term shape, no downside,
  -- and the two leading zeros must cost no line.
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
