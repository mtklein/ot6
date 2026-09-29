-- @suite slow
-- battle_dlgmenu: battles that open with a scripted battle dialogue must
-- come back with intact, working menus: the small font at vram $5800 must
-- render correctly and every menu and list pick must resolve.
--   flow: whelk entry point -> step onto the trigger -> edge-tap the opening
--   dialogues -> first menu entirely hands-off -> whole-font byte scan
--   (every claimed OT6 cell == its bank-F0 data, every other byte ==
--   SmallFontGfx) -> open the magitek list -> staged-row map-word asserts
--   -> a deep row selects, targets, and executes ($3410 exec watch).

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/whelk_entry.mss.lua"
local WHELK = { [0x0134] = true }
local function whelk()
  return H.battleLoadStarted() and H.formationHas(WHELK)
end

-- Whole-font correctness: vram $5800-$5fff words (bytes $B000-$BFFF) must
-- be SmallFontGfx (rom C4/7FC0) everywhere except the OT6-claimed cells,
-- which must hold what H.ot6FontCells says (the element icons, the fixed hud
-- glyphs, and each monster slot's shield-count tile, #292).  The model reads
-- the ROM's own cell tables by symbol, so art edits never stale this test.
local SMALLFONT_ROM = H.sym("SmallFontGfx") & 0x3FFFFF  -- headerless-image offset
local function claimedCells()
  local rom = emu.memType.snesPrgRom
  local claimed, elemIcons = {}, {}
  for cell, c in pairs(H.ot6FontCells()) do claimed[cell] = c.rom end
  local iconCells = H.sym("Ot6ElemGlyphTbl") & 0x3FFFFF
  for k = 1, 8 do
    elemIcons[emu.read(iconCells + k - 1, rom)] = k  -- 1-based element index, fire..water
  end
  return claimed, elemIcons
end
local function assertFontIntact(what)
  local vr, rom = emu.memType.snesVideoRam, emu.memType.snesPrgRom
  local claimed = claimedCells()
  local bad, badAt = 0, -1
  for cell = 0, 0xFF do
    local src = claimed[cell] or (SMALLFONT_ROM + cell*16)
    for i = 0, 15 do
      if emu.read(0xB000 + cell*16 + i, vr) ~= emu.read(src + i, rom) then
        bad = bad + 1
        if badAt < 0 then badAt = cell*16 + i end
      end
    end
  end
  if bad ~= 0 then
    error(string.format("%s: font region corrupt: %d bytes differ " ..
      "(first at vram byte $B000+%03x)", what, bad, badAt), 0)
  end
  H.log("ok: " .. what .. " = font byte-exact (SmallFontGfx + OT6 cells)")
end

-- staged magitek-list map words (rows 32+ off vram word $7800): "Ice"
-- (I=$88 c=$9c e=$9e) shows real text landed in the staging rows
local function iceStaged()
  local vr = emu.memType.snesVideoRam
  for w = 0x400, 0x5fc do
    local base = (0x7800 + w) * 2
    if emu.read(base, vr) == 0x88 and emu.read(base+2, vr) == 0x9c and
       emu.read(base+4, vr) == 0x9e then
      return true
    end
  end
  return false
end
-- Whole-map scan of the staging rows.  Every word must be a cell that
-- carries art: a small-font text tile ($80+), or one of the eight
-- OT6 element icons.  Anything else means garbage got staged.

-- The icon half is part of the rule, not an exception to it.  Ability list
-- rows are drawn by Ot6ListIconCommon and Ot6AbilityPad_ext (ot6.asm), which
-- append the ability's element glyph from Ot6ElemGlyphTbl, and that
-- table puts poison at font cell $64, below the text range, with a
-- comment giving the reason: "$ee is vanilla's border junk fill!"
-- (ot6.asm:1158).  The other seven icons land at $eb $ec $ed
-- $ef $fb $fc $fd, all >= $80, which is why a $80+-only rule
-- looked correct.

-- The allowed set is derived rather than listed here: claimedCells() finds
-- the icon data in bank F0 by signature scan, and assertFontIntact() then
-- byte-compares every claimed cell's vram against that rom data, so a
-- wrong cell list fails the font check rather than quietly widening this
-- one.
local function assertStagingSane()
  local vr = emu.memType.snesVideoRam
  local _, elemIcons = claimedCells()
  local seen = {}
  for w = 0x400, 0x53f do
    local base = (0x7800 + w) * 2
    local tile = emu.read(base, vr)
    if tile < 0x80 and not elemIcons[tile] then
      error(string.format("staging row word $%04x holds tile $%02x " ..
        "(neither a text tile nor an OT6 element icon)", 0x7800 + w, tile), 0)
    end
    if elemIcons[tile] then seen[tile] = (seen[tile] or 0) + 1 end
  end
  -- observation, not an assertion: which lists stage icons depends on
  -- whose menu the ATB roll opened, and that is legitimately either way
  local s = {}
  for tile, n in pairs(seen) do
    s[#s+1] = string.format("$%02x x%d", tile, n)
  end
  table.sort(s)
  H.log("ok: staged list rows hold only text tiles + OT6 element icons"
    .. (#s > 0 and ("; icons staged: " .. table.concat(s, " ")) or ""))
end

local execs = {}
local aPhase = 0
H.run({ maxFrames = 12000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return whelk() end, 2200, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.battleLoadStarted() then
        if whelk() then H.setPad({}); return end
        H.setPad({ l = true, r = true })
        return
      end
      if H.dialogWaiting() then
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
    end),
  }, "whelk event fires"),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 900, "whelk up", 30),
  H.waitFrames(240),
  -- edge-tap A only until the first menu appears, then hands off
  H.driveUntil(function() return H.readByte(0x7bca) ~= 0 end, 4000, {
    H.call(function()
      local n = (H.vars.mn or 0) + 1
      H.vars.mn = n
      H.setPad(n % 60 < 4 and { "a" } or {})
    end),
  }, "first menu opens"),
  H.call(function() H.setPad({}) end),
  H.waitFrames(300),
  H.call(function()
    local actor = H.readByte(0x62ca)
    H.log(string.format("first menu: actor slot %d, char id $%02x", actor,
      H.readByte(0x3ed8 + actor * 2)))
    assertFontIntact("untouched first menu after opening dialogues")
    H.screenshot("dlgmenu_untouched")
    emu.addMemoryCallback(function(addr, value)
      execs[#execs+1] = value
    end, emu.callbackType.write, 0x7e3410, 0x7e3410)
  end),
  -- open the magitek list (everyone in this fight rides magitek armor,
  -- so A on the top command opens it no matter who holds the menu)
  H.driveUntil(function() return iceStaged() end, 600, {
    H.pressButtons({ "a" }, 4), H.waitFrames(40),
  }, "magitek list staged"),
  H.waitFrames(30),             -- let the window scroll open + rows finish
  H.call(function()
    assertStagingSane()
    H.screenshot("dlgmenu_list")
  end),
  -- deep selection: two rows down, select, confirm target, and check that a
  -- magitek beam executes, which means the turn engine accepted the pick
  H.pressButtons({ "down" }, 4), H.waitFrames(20),
  H.pressButtons({ "down" }, 4), H.waitFrames(20),
  H.pressButtons({ "a" }, 4), H.waitFrames(30),
  H.pressButtons({ "a" }, 4), H.waitFrames(30),
  H.waitUntil(function()
    for _, v in ipairs(execs) do
      if v >= 0x83 and v <= 0x8a then return true end
    end
    return false
  end, 900, "deep-row magitek attack executes", 10),
  H.waitFrames(90),
  H.call(function()
    local s = {}
    for _, v in ipairs(execs) do s[#s+1] = string.format("%02X", v) end
    H.log("execs at $3410: " .. table.concat(s, " "))
    -- the action banner + attack anims must not have re-clobbered the font
    assertFontIntact("font after the deep-row attack ran")
    H.screenshot("dlgmenu_done")
  end),
})
