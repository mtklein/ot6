-- @suite
-- battle_sixhud.lua -- the HUD's weakness line draws six classes with six
-- different icons (#566).
--
-- A synthetic mechanism test of the under-monster line (ot6_hud.asm
-- Ot6BgHudLine), which is a function of three bytes a body: its weak elements
-- ($3BE8 + 2*slot), its class row ($3EA4 + 2*slot) and its revealed classes
-- ($3EA5 + 2*slot).  It boots battle_entry (the first battle of the game: two
-- Guards, three Magitek riders), lets the battle open, and writes those bytes
-- on the two Guards (declared: tools/state_write_waivers.txt); nobody acts.
-- No fixture early in the line fields bodies weak to all six classes, and the
-- line's cells are what is under test, not how the bytes got there
-- (battle_sixchip reveals each class by a real hit and reads its cell).
--
--   1. hidden.  Guard A's row := sword|dagger|fist|arcane, Guard B's :=
--      katana|spear, no elements, nothing revealed: A's line draws four grey
--      '?', B's two and two blanks.
--   2. revealed.  Both rows revealed: A's four cells are the sword, dagger,
--      fist and arcane glyphs and B's first two the katana and spear glyphs,
--      each the design's cell (GLYPH below), each white; the six cells are
--      six different tiles; each tile's pixels in VRAM (the battle font,
--      byte $B000 + cell*16) are the ROM font's, differ from the other
--      five's, and the dagger, katana and spear are the redrawn art (ART:
--      the dagger level, the katana vanilla's mirrored, the spear upright).
--      Screenshot sixhud_six: the six icons, on two bodies.
--   3. every class in every cell it can take.  For each class c, a row of c
--      and the classes below it (c alone; c and one below; ...): the class
--      sits in the cell its rank says, up to the fourth.
--   4. the cap, measured.  A's row := all six, all revealed.  The line has
--      four weakness cells after the count (elements first, then classes in
--      bit order), so a body weak to more than four things shows the first
--      four: this step logs exactly what a six-class body draws and which
--      classes it does not, asserts the cells it does draw are the right
--      glyphs in order, and takes screenshot sixhud_allsix.  It does not
--      assert the cap either way: see the [sixhud] MEASURED line.
--
-- Mutants (build/attempts/wt/v051-six-classes/newsuites/): two classes
-- sharing a glyph cell; the katana's cell holding the sword's picture; the
-- line walking four class bits.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

-- the design: class bit -> name, the font cell its icon is
local CLASSES = {
  { bit = 0x01, name = "sword",  glyph = 0xD9 },
  { bit = 0x02, name = "dagger", glyph = 0xD8 },
  { bit = 0x04, name = "fist",   glyph = 0xE1 },
  { bit = 0x08, name = "arcane", glyph = 0xDF },
  { bit = 0x10, name = "katana", glyph = 0xDB },
  { bit = 0x20, name = "spear",  glyph = 0xDA },
}
-- ' ' 0 clear, '.' 1 shadow, 'o' 2 grey, '#' 3 white
local ART = {
  dagger = { "        ",
             "     #. ",
             "     #. ",
             "######oo",
             " oooo#oo",
             " ....#..",
             "     #. ",
             "      . " },
  katana = { "       #",
             "      o#",
             "     o#.",
             "    o#. ",
             " # o#.  ",
             "  #..   ",
             " o.#    ",
             "#. .    " },
  spear  = { "   #    ",
             "  ###.  ",
             "  ###.  ",
             "   #..  ",
             "   o.   ",
             "   o.   ",
             "   o.   ",
             "   o.   " },
}
local QMARK = (H.HUD_QMARK_ATTR << 8) | 0xBF
local BLANK = 0x21FF
local WHITE = H.HUD_GAUGE_ATTR

local ELEM, ROW, REV = 0x3BE8, 0x3EA4, 0x3EA5
local SHADOW = H.sym("OT6_SHADOW")
local vr, rom = emu.memType.snesVideoRam, emu.memType.snesPrgRom

local function standing(s) return (H.readByte(0x3AA8 + s * 2) & 1) == 1 and H.readWord(0x3BFC + s * 2) > 0 end
local function cells(s)
  local addr = H.readWord(SHADOW + s * 14)
  if addr == 0 then return nil end
  local t = {}
  for i = 1, 4 do t[i] = emu.readWord((addr + i) * 2, vr) end
  return t
end
local function said(t)
  if t == nil then return "off" end
  local p = {}
  for i = 1, 4 do p[i] = string.format("%04X", t[i]) end
  return table.concat(p, " ")
end
local function art(cell)
  local rows = {}
  for r = 0, 7 do
    local p0, p1, line = emu.read(0xB000 + cell * 16 + 2 * r, vr), emu.read(0xB000 + cell * 16 + 2 * r + 1, vr), {}
    for c = 7, 0, -1 do
      local v = ((p0 >> c) & 1) | (((p1 >> c) & 1) << 1)
      line[#line + 1] = (" .o#"):sub(v + 1, v + 1)
    end
    rows[r + 1] = table.concat(line)
  end
  return rows
end
local function tileBytes(cell)
  local t = {}
  for i = 0, 15 do t[#t + 1] = string.format("%02X", emu.read(0xB000 + cell * 16 + i, vr)) end
  return table.concat(t)
end

local A, Bd = nil, nil       -- the two Guards' slots
-- stage one body's line: no elements, this class row, this much of it revealed
local function stage(s, rowv, revv)
  H.writeByte(ELEM + s * 2, 0)
  H.writeByte(ROW + s * 2, rowv)
  H.writeByte(REV + s * 2, revv)
end
-- what a row should draw: its classes in bit order, the first four
local function expect(rowv, revv)
  local t = {}
  for _, c in ipairs(CLASSES) do
    if (rowv & c.bit) ~= 0 then t[#t + 1] = (revv & c.bit) ~= 0 and ((WHITE << 8) | c.glyph) or QMARK end
  end
  return t
end
local function settle() return H.waitFrames(40) end

local steps = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "the first battle loads"),
  H.waitUntil(function() return H.battleActive() end, 900, "the battle is up", 30),
  H.waitFrames(240),
  H.call(function()
    for s = 0, 5 do
      if standing(s) then
        if A == nil then A = s elseif Bd == nil then Bd = s end
      end
    end
    H.assertEq(A ~= nil and Bd ~= nil, true, "two monsters stand in the first battle (the two Guards)")
    H.log(string.format("[sixhud] bodies: slot %d ($%03X row $%02X) and slot %d ($%03X row $%02X), as the ROM "
      .. "seeded them; lines %s | %s", A, H.readWord(0x57C0 + A * 2), H.readByte(ROW + A * 2), Bd,
      H.readWord(0x57C0 + Bd * 2), H.readByte(ROW + Bd * 2), said(cells(A)), said(cells(Bd))))
    -- the design's cells are the ROM's
    local tbl = H.sym("Ot6ClassGlyphTbl") & 0x3FFFFF
    local seen = {}
    for i, c in ipairs(CLASSES) do
      local cell = emu.read(tbl + i - 1, rom)
      H.assertEq(seen[cell], nil, string.format("Ot6ClassGlyphTbl: %s's cell $%02X is not another class's (%s) -- "
        .. "the six classes draw six different tiles", c.name, cell, tostring(seen[cell])))
      seen[cell] = c.name
    end
    for i, c in ipairs(CLASSES) do
      H.assertEq(emu.read(tbl + i - 1, rom), c.glyph, string.format("Ot6ClassGlyphTbl: %s draws the design's cell "
        .. "$%02X", c.name, c.glyph))
    end
    -- 1. hidden
    stage(A, 0x0F, 0x00); stage(Bd, 0x30, 0x00)
  end),
  settle(),
  H.call(function()
    local a, b = cells(A), cells(Bd)
    H.log(string.format("[sixhud] hidden: A (row $0F) draws %s; B (row $30) draws %s", said(a), said(b)))
    H.assertEq(a ~= nil and b ~= nil, true, "both HUD lines are on")
    for i = 1, 4 do H.assertEq(a[i], QMARK, string.format("hidden: A's weakness cell %d is the grey '?'", i)) end
    for i = 1, 2 do H.assertEq(b[i], QMARK, string.format("hidden: B's weakness cell %d is the grey '?'", i)) end
    for i = 3, 4 do H.assertEq(b[i], BLANK, string.format("hidden: B's weakness cell %d is blank", i)) end
    H.screenshot("sixhud_hidden")
  end),
  H.waitFrames(4),                     -- (a screenshot is of the next frame drawn)
  -- 2. revealed
  H.call(function() stage(A, 0x0F, 0x0F); stage(Bd, 0x30, 0x30) end),
  settle(),
  H.call(function()
    local a, b = cells(A), cells(Bd)
    H.log(string.format("[sixhud] revealed: A (row $0F) draws %s; B (row $30) draws %s", said(a), said(b)))
    local drawn = { a[1], a[2], a[3], a[4], b[1], b[2] }
    local tiles = {}
    for i, c in ipairs(CLASSES) do
      H.assertEq(drawn[i], (WHITE << 8) | c.glyph, string.format("revealed: the %s cell is its glyph $%02X, white "
        .. "(attr $%02X)", c.name, c.glyph, WHITE))
      local t = drawn[i] & 0xFF
      H.assertEq(tiles[t], nil, string.format("revealed: the %s cell's tile $%02X is not the %s cell's -- six "
        .. "different tiles on screen", c.name, t, tostring(tiles[t])))
      tiles[t] = c.name
    end
    for i = 3, 4 do H.assertEq(b[i], BLANK, string.format("revealed: B's weakness cell %d is blank", i)) end
    -- the tiles' pixels, as VRAM holds them
    local font = H.sym("SmallFontGfx") & 0x3FFFFF
    local px = {}
    for _, c in ipairs(CLASSES) do
      px[c.name] = tileBytes(c.glyph)
      H.log(string.format("[sixhud] %-6s cell $%02X VRAM %s", c.name, c.glyph, px[c.name]))
      for r, line in ipairs(art(c.glyph)) do H.log(string.format("[sixhud]   %-6s |%s|", r == 1 and c.name or "", line)) end
      local romBytes = {}
      for i = 0, 15 do romBytes[#romBytes + 1] = string.format("%02X", emu.read(font + c.glyph * 16 + i, rom)) end
      H.assertEq(px[c.name], table.concat(romBytes), string.format("the %s tile in VRAM is the ROM font's cell "
        .. "$%02X", c.name, c.glyph))
      H.assertEq(px[c.name] ~= string.rep("00", 16), true, "the " .. c.name .. " tile is not blank")
    end
    for i, c in ipairs(CLASSES) do
      for j = i + 1, #CLASSES do
        H.assertEq(px[c.name] ~= px[CLASSES[j].name], true, string.format("the %s and %s tiles' pixels differ",
          c.name, CLASSES[j].name))
      end
    end
    for _, c in ipairs(CLASSES) do
      if ART[c.name] then
        H.assertEq(table.concat(art(c.glyph), "/"), table.concat(ART[c.name], "/"), string.format("the %s tile is "
          .. "the redrawn art", c.name))
      end
    end
    H.screenshot("sixhud_six")
  end),
  H.waitFrames(4),
}

-- 3. each class in each cell its rank can give it
for i, c in ipairs(CLASSES) do
  for below = 0, math.min(i - 1, 3) do
    -- the class and the `below` classes just under it
    local rowv = c.bit
    for k = 1, below do rowv = rowv | CLASSES[i - k].bit end
    steps[#steps + 1] = H.call(function() stage(A, rowv, rowv); stage(Bd, 0x00, 0x00) end)
    steps[#steps + 1] = H.waitFrames(12)
    steps[#steps + 1] = H.call(function()
      local a, want = cells(A), expect(rowv, rowv)
      H.assertEq(a ~= nil, true, "A's HUD line is on")
      H.assertEq(a[below + 1], (WHITE << 8) | c.glyph, string.format("row $%02X: %s, with %d class(es) below it, is "
        .. "weakness cell %d (line: %s)", rowv, c.name, below, below + 1, said(a)))
      for k = 1, 4 do
        H.assertEq(a[k], want[k] or BLANK, string.format("row $%02X: weakness cell %d (line: %s)", rowv, k, said(a)))
      end
    end)
  end
end

-- 4. the cap, measured
steps[#steps + 1] = H.call(function() stage(A, 0x3F, 0x3F); stage(Bd, 0x3F, 0x00) end)
steps[#steps + 1] = settle()
steps[#steps + 1] = H.call(function()
  local a, b = cells(A), cells(Bd)
  local drawn, missing = {}, {}
  for _, c in ipairs(CLASSES) do
    local at = nil
    for k = 1, 4 do if a[k] == ((WHITE << 8) | c.glyph) then at = k end end
    if at then drawn[#drawn + 1] = string.format("%s (cell %d)", c.name, at) else missing[#missing + 1] = c.name end
  end
  H.log(string.format("[sixhud] MEASURED: a body weak to all six classes, all revealed (row $3F, revealed $3F, no "
    .. "elements) draws weakness cells %s: %d of its 6 classes -- %s; NOT drawn: %s.  The same body with nothing "
    .. "revealed draws %s", said(a), #drawn, table.concat(drawn, ", "), #missing > 0 and table.concat(missing, ", ")
    or "none", said(b)))
  local want = expect(0x3F, 0x3F)
  for k = 1, 4 do
    H.assertEq(a[k], want[k], string.format("all six: weakness cell %d is the class of rank %d, in bit order", k, k))
  end
  H.screenshot("sixhud_allsix")
end)
steps[#steps + 1] = H.waitFrames(4)
steps[#steps + 1] = H.call(function() H.log("[sixhud] PASS") end)

H.run({ maxFrames = 20000 }, steps)
