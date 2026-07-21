-- @suite slow
-- battle_dlgmenu: battles that OPEN with a scripted battle dialogue must
-- come back with intact, working menus.  Regression gate for the whelk
-- garbled-menu bug (first bad: 0666392): Ot6MarkFontDirty_ext was hooked
-- BETWEEN _c143b9's parameter setup and its jmp WaitTfrVRAM and clobbered
-- A -- WaitTfrVRAM's SOURCE BANK -- so every dialogue-close "restore"
-- streamed $1000 bytes of bank-$01 open bus over the small font at vram
-- $5800 and all later menu/list text rendered as noise (the map words
-- stayed correct; deep list picks read as "rejected" only because nobody
-- could see which rows were real).
--   flow: whelk doorstep -> step onto the trigger -> edge-tap the opening
--   dialogues -> first menu entirely hands-off -> whole-font byte scan
--   (every claimed OT6 cell == its bank-F0 data, every other byte ==
--   SmallFontGfx) -> open the magitek list -> staged-row map-word asserts
--   -> a deep row selects, targets, and EXECUTES ($3410 exec watch).
--
-- MENU OWNER DOES NOT MATTER, deliberately.  The battle-start ATB roll
-- decides whose menu opens first, and every assert here is written to hold
-- for any of them: everyone in this fight rides magitek armor, so the top
-- command opens a magitek list whoever holds it; the "Ice" probe and the
-- $83-$8a exec watch are beam-family checks common to all those lists; and
-- assertStagingSane accepts the element icons any of those lists stages.
-- It was not always so -- see the block comment there -- and the fixture
-- generator must NOT be tuned to steer the roll on this test's behalf.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/whelk_doorstep.mss.lua"
local WHELK = { [0x0134] = true }
local function whelk()
  return H.battleLoadStarted() and H.formationHas(WHELK)
end

-- Whole-font correctness: vram $5800-$5fff words (bytes $B000-$BFFF) must
-- be SmallFontGfx (rom C4/7FC0) everywhere EXCEPT the 24 OT6-claimed cells
-- (8 element icons + 16 hud glyphs), which must equal their bank-F0 data.
-- Derivation mirrors H.glyphCanary (signature scan; cell table precedes
-- the glyph data in rom) so art edits never stale this test.
local SMALLFONT_ROM = 0x047FC0          -- C4/7FC0 in the headerless image
local function claimedCells()
  local rom = emu.memType.snesPrgRom
  local function findSig(sig)
    -- v0.2 grew bank F0 ahead of the bg glyph table (~$F0109A now), so the
    -- scan window reaches past the first 4K it used to fit inside.
    for base = 0x300000, 0x303FF0 do
      local hit = true
      for i = 1, 16 do
        if emu.read(base+i-1, rom) ~= sig[i] then hit = false; break end
      end
      if hit then return base end
    end
    return nil
  end
  local icons = findSig({0x10,0x10,0x30,0x38,0x38,0x3c,0x6c,0x7c,
                         0x6e,0x7e,0xee,0xfe,0x7e,0x7c,0x3c,0x00})
  local bg    = findSig({0x7e,0x00,0x91,0x7e,0xb1,0x7e,0x91,0x7e,
                         0x52,0x3c,0x3c,0x38,0x18,0x00,0x00,0x00})
  H.assertEq(icons ~= nil and bg ~= nil, true, "OT6 glyph data found in rom")
  local claimed, elemIcons = {}, {}
  local iconCells = {0xeb,0xec,0xed,0x64,0xef,0xfb,0xfc,0xfd}
  for k, cell in ipairs(iconCells) do
    claimed[cell] = icons + (k-1)*16
    elemIcons[cell] = k                  -- 1-based element index, fire..water
  end
  for k = 1, 16 do
    claimed[emu.read(bg - 17 + k, rom)] = bg + (k-1)*16
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
-- (I=$88 c=$9c e=$9e) proves real text landed in the staging rows
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
-- really carries art: a small-font text tile ($80+), or one of the eight
-- OT6 element icons.  Anything else means garbage got staged.
--
-- The icon half is not a concession, it is the rule.  Ability list rows
-- are drawn by Ot6ListIconCommon / Ot6AbilityPad_ext (ot6.asm), which
-- append the ability's element glyph from Ot6ElemGlyphTbl -- and that
-- table puts POISON at font cell $64, below the text range, with the
-- comment that says why: "$ee is vanilla's border junk fill!"
-- (ot6.asm:1158).  The other seven icons happen to land at $eb $ec $ed
-- $ef $fb $fc $fd, all >= $80, which is the only reason a $80+-only rule
-- ever looked correct.
--
-- Measured on this fixture (probe dump of $7c00-$7d3f with the magitek
-- list open): row $7c70 reads "Bio Blast" followed by word $3964 --
-- tile $164 = font cell $64, palette 6, which is exactly
-- Ot6ElemPalTbl's ".byte 6 << 2 ; poison: green".  That word is correct,
-- intentional, player-visible art.  The old rule called it garbage, so
-- the test could only pass on the battle-start ATB rolls where somebody
-- OTHER than Terra held the first menu -- i.e. it was a coin flip on
-- which ROM bytes happened to be assembled, which is the one thing
-- CONTRIBUTING.md says a gate must never be.
--
-- The allowed set is derived, not listed here: claimedCells() finds the
-- icon data in bank F0 by signature scan, and assertFontIntact() then
-- byte-compares every claimed cell's vram against that rom data -- so a
-- wrong cell list fails the font check loudly rather than quietly
-- widening this one.
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
        if H.monstersPresent() > 0 then
          for slot = 0, 5 do
            if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
        H.setPad(aPhase < 4 and { "a" } or {})
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
  -- edge-tap A only until the first menu appears, then hands off: the
  -- original bug garbled this screen with ZERO further input
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
    -- name the menu owner: nothing asserts on it (see the header), but a
    -- failure that IS roll-dependent should say so in its own log instead
    -- of making the next reader re-measure the ATB phase
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
  -- deep selection: two rows down, select, confirm target -- and prove a
  -- magitek beam actually EXECUTES (the turn engine accepted the pick)
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
