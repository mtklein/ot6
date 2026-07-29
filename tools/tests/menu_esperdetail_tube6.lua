-- @suite frontier=arvis_wake
-- menu_esperdetail_tube6.lua -- the SIX TUBE-ROOM STONES on the esper detail
-- page (docs/design/magicite-tube-six.md §11, issue #31).
--
-- The design doc's closing claim is "menu copy: zero work required" -- the
-- detail page renders the granted spell names and the "While worn...<Stat>+N"
-- line straight out of GenjuProp and Ot6EsperStatTbl, so authoring those two
-- tables IS the whole player-facing job.  That claim is only worth anything if
-- something checks it, which is this file: it drives the real menu UI to three
-- detail pages and asserts the rendered TILES, not the tables.
--
-- Same drive and same instrument as menu_esperdetail.lua (issue #27): X ->
-- Skills -> character -> Espers -> list -> detail from the arvis_wake fixture,
-- with the esper inventory pinned directly (the battle_bushido "install state"
-- house pattern) because arvis_wake owns no stones yet.  That file stays as it
-- is -- it is #27's shipped gate on the page's SHAPE (dead columns gone, mod
-- and no-mod both correct) and this one is #31's gate on the page's CONTENT.
--
-- THE THREE PAGES:
--   MADUIN  (6)  the marquee.  +5 mag.pwr, the crown and the one exception to
--                the story rung, and three spell rows that must now read Fire /
--                Ice / Bolt where the shipped ROM drew Fire 2 / Ice 2 / Bolt 2
--                and a BLANK stat line.
--   TERRATO (4)  the surviving no-mod control.  Its Ot6EsperStatTbl byte is
--                still $00 after this change (only rows 5/6/7/19/20/23 moved),
--                so the blank-line path is still exercised -- and, revisited
--                after Maduin, it proves the page overwrites rather than
--                leaving the previous stone's line behind.
--   UNICORN (23) the Pearl grant -- branch A of the cross-doc holy decision
--                (§9's DECIDED box).  Two spell rows where the shipped ROM
--                drew five, so rows 3-5 must be blank: the deletions are
--                asserted on screen, not just in the table.
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
-- The while-worn line (skills.asm:2624-2673): "While worn..." at cols 5-17,
-- the 7-tile stat name at 18-24 (Ot6GenjuStatNameTbl, space-padded), '+' at
-- 25, and two digit tiles at 26-27 with the leading zero blanked.
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

local BLANK   = 0xff
local CH_W    = 0x96                    -- 'W' of "While worn..."
local CH_PLUS = 0xca
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

local function assertStatLine(tag, statTiles, magnitude)
  H.assertEq(cell(5, 27), CH_W, tag .. ": 'While worn...' starts at {5,27}")
  for k = 0, 6 do
    H.assertEq(cell(18 + k, 27), statTiles[k + 1],
      string.format("%s: stat name tile %d at {%d,27}", tag, k, 18 + k))
  end
  H.assertEq(cell(25, 27), CH_PLUS, tag .. ": '+' at {25,27}")
  H.assertEq(cell(26, 27), BLANK, tag .. ": leading zero blanked at {26,27}")
  H.assertEq(cell(27, 27), digit(magnitude),
    string.format("%s: magnitude %d at {27,27}", tag, magnitude))
end

local function logPage(tag)
  H.log(string.format("[%s] esper=%d rows: 1=%s 2=%s 3=%s 4=%s 5=%s",
    tag, H.readByte(Z99), rowHex(0), rowHex(1), rowHex(2), rowHex(3), rowHex(4)))
  local s = {}
  for x = 5, 27 do s[#s + 1] = string.format("%02x", cell(x, 27)) end
  H.log(string.format("[%s] while-worn line: %s", tag, table.concat(s, " ")))
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

-- ---- MADUIN: the crown.  Fire/Ice/Bolt + "While worn...Mag.Pwr + 5" -------
add(page(MADUIN, "Maduin"))
add({ H.call(function()
  H.assertEq(H.readByte(Z99), MADUIN, "detail page is MADUIN's")
  logPage("maduin")
  assertRow("maduin", 0, NAME.FIRE, "Fire (base tier, not Fire 2)")
  assertRow("maduin", 1, NAME.ICE,  "Ice (base tier, not Ice 2)")
  assertRow("maduin", 2, NAME.BOLT, "Bolt (base tier, not Bolt 2)")
  assertRowEmpty("maduin", 3)
  assertRowEmpty("maduin", 4)
  assertStatLine("maduin", STAT.MAGPWR, 5)
  H.screenshot("esper_detail_maduin")
  H.log("MADUIN: three base tiers drawn, 'While worn...Mag.Pwr + 5'")
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
  -- No mod: the whole while-worn line is blank -- INCLUDING the cells Maduin's
  -- page just filled, which is what proves the revisit overwrote them.
  for x = 5, 27 do
    H.assertEq(cell(x, 27), BLANK,
      string.format("terrato: while-worn line blank at {%d,27}", x))
  end
  H.screenshot("esper_detail_terrato_tube6")
  H.log("TERRATO: still the no-mod control after the v0.7 pass; line blank")
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
  assertStatLine("unicorn", STAT.STAMINA, 3)
  H.screenshot("esper_detail_unicorn")
  H.log("UNICORN: Pearl + Remedy only, 'While worn...Stamina + 3'")
end) })

add({ H.call(function()
  H.log("PASSED: the tube-room six render their new grant lists and stat "
    .. "lines on the real esper detail page")
end) })

H.run({ maxFrames = 40000 }, all)
