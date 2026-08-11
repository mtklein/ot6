-- probe_esperdetail_tube6_checkpoint.lua -- issue #31's verification instrument.
--
-- The SAME menu drive and the SAME cell-level assertions as
-- menu_esperdetail_tube6.lua (the suite test), booted instead from a COLD
-- Continue off the tracked post-Opera battery checkpoint, which survives ROM
-- changes (issue #9) where savestate fixtures do not.  This build changes ROM
-- DATA in two banks (genju_prop, ot6_progression), so it is exactly the class
-- of change that can leave a generated .mss describing the previous ROM;
-- run this to check the page from a boot that cannot be stale:
--
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/post-opera-v1 \
--     tools/tests/run.sh tools/tests/probe_esperdetail_tube6_checkpoint.lua
--
-- The Continue sequence is gen_vector_entry.lua's, copied from
-- probe_esperdetail_checkpoint.lua.  The party is LOCKE CELES SABIN EDGAR on the
-- world map at (137,203); the field menu opens from the world map exactly as
-- from a field map.  The esper inventory is pinned to exactly MADUIN (+5
-- mag.pwr, the crown), TERRATO (Ot6EsperStatTbl $0000 -- still the no-mod
-- control after this pass) and UNICORN (the Pearl grant, branch A).
--
-- Name tiles and stat-line geometry: see menu_esperdetail_tube6.lua's header.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- ^ the persistent-SRAM layout this step understands (issue #25).  run.sh
-- reads
--   the marker line above and refuses -- BEFORE the emulator boots -- any
--   OT6_SRAM_CHECKPOINT whose manifest.json declares a different persistent_layout.
--   NOTE: probe_esperdetail_checkpoint.lua, the #27 probe this file mirrors, has
--   NO such marker and is therefore refused by run.sh today; see this build's
--   report Follow-ups.
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local ZLISTTYPE  = 0x2a
local ZCURSOR    = 0x4b
local Z99        = 0x99
local SKILLCOLOR = 0x79
local ESPERS     = 0x1a69
local GENJULIST  = 0x9d89
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LIST, ST_DETAIL = 0x05, 0x06, 0x0a, 0x1e, 0x4d

local MADUIN, TERRATO, UNICORN = 6, 4, 23

local BG1B = 0x4049
local function cell(x, y) return H.readByte(BG1B + x * 2 + y * 64) end

local BLANK   = 0xff
local CH_W     = 0x96
local CH_DOT   = 0xc5
local CH_PLUS  = 0xca
local CH_MINUS = 0xc4                   -- #62: a delta can be negative
local function digit(n) return 0xb4 + n end

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
-- All four now: #62's block can draw any of them, and Maduin's leads on VIGOR.
local STAT = {
  VIGOR   = { 0x95, 0xa2, 0xa0, 0xa8, 0xab, 0xff, 0xff },
  SPEED   = { 0x92, 0xa9, 0x9e, 0x9e, 0x9d, 0xff, 0xff },
  STAMINA = { 0x92, 0xad, 0x9a, 0xa6, 0xa2, 0xa7, 0x9a },
  MAGPWR  = { 0x8c, 0x9a, 0xa0, 0xc5, 0x8f, 0xb0, 0xab },
}

local function st() return H.readByte(ZMENUSTATE) end

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
      if d % 2 ~= 0 then
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
local function assertRowEmpty(tag, slot)
  local y = 17 + slot * 2
  for x = 5, 19 do
    H.assertEq(cell(x, y), BLANK,
      string.format("%s: row %d empty at {%d,%d}", tag, slot + 1, x, y))
  end
end
-- #62's stat block: caption on the title row, one term per nonzero delta packed
-- down from row 17 (name cols 17-23, spacer 24, sign 25, magnitude 26-27).
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

local function page(idx, name)
  return {
    listSeek(idx, "cursor to " .. name .. "'s row"),
    H.waitFrames(20),
    H.driveUntil(function() return st() == ST_DETAIL end, 600,
      { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, name .. " detail"),
    H.waitFrames(30),
  }
end
local function backToList()
  return {
    H.pressButtons({ "b" }, 2),
    H.waitUntil(function() return st() == ST_LIST end, 300, "back to list", 5),
    H.waitFrames(10),
  }
end

local all = {
  -- gen_vector_entry.lua's cold Continue off the battery checkpoint.
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function()
    return (H.mapId() & 0x1ff) == 0 and H.worldHasControl() and H.worldAligned()
  end, 3000, "cold Continue to post-Opera world entry point", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "cold Continue fade-in", 10),

  -- Pin the esper inventory to exactly MADUIN + TERRATO + UNICORN.
  H.call(function()
    H.log(string.format("[pin] $1a69 was %02x; pinning MADUIN+TERRATO+UNICORN",
      H.readByte(ESPERS)))
    H.writeByte(ESPERS + 0, 0x50)   -- MADUIN (6) | TERRATO (4)
    H.writeByte(ESPERS + 1, 0x00)
    H.writeByte(ESPERS + 2, 0x80)   -- UNICORN (23) = bit 7 of byte 2
    H.writeByte(ESPERS + 3, 0x00)
  end),

  H.pressButtons({ "x" }, 4),
  H.waitUntil(function() return st() == ST_MAIN end, 600, "main menu", 5),
  H.waitFrames(20),

  H.pressButtons({ "down" }, 2),
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
local function add(l) for _, s in ipairs(l) do all[#all + 1] = s end end

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
  H.screenshot("esper_detail_maduin_checkpoint")
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
  H.screenshot("esper_detail_terrato_tube6_checkpoint")
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
  H.screenshot("esper_detail_unicorn_checkpoint")
  H.log("UNICORN: Pearl + Remedy only; Stamina +5 / Mag.Pwr +2")
end) })

add({ H.call(function()
  H.log("PASSED (checkpoint boot): the tube-room six render their new grant lists "
    .. "and stat lines on the real esper detail page")
end) })

H.run({ maxFrames = 80000 }, all)
