-- @suite
-- battle_blitzlist.lua -- v0.3 Blitz-as-menu: the selector itself.
--
-- Vanilla Blitz had no window: UpdateMenuState_3d (btlgfx_main.asm, now
-- deleted) read button codes off a 64-frame rolling pad-edge buffer.  The
-- command now hands off to Ot6BlitzListOpen (ot6.asm), which fills wItemList
-- with the LEARNED blitzes -- each row keyed by its resolved attack id $5D+i
-- (Pummel $5d .. Bum Rush $64) -- and reuses the Tools window shell (menu
-- state $30).  The row draw flips the Tools template's $0e item-name code to
-- $0f so ListTextCmd_0f renders each row from AttackName; the confirm shim
-- subtracts $5D back to the raw index cmd $0a stores, exactly the byte
-- UpdateMenuState_3d used to write, so FixPlayerAttack (validates i against
-- $1d28, adds +$5d) and everything downstream are untouched.
--
-- Sabin is INSTALLED into the opening guard fight the way battle_bushido pins
-- Cyan -- every party slot gets CHAR::SABIN ($3ED8) and an all-Blitz command
-- list ($202E, stride 12).  Blitz needs no weapon flag (unlike Bushido: it is
-- absent from UpdateCmdIDTbl, so it is never greyed).  The known-blitz set
-- $1D28 is written DIRECTLY, so the test controls exactly which blitzes are
-- learned -- the same byte the menu populates from and FixPlayerAttack reads.
--
-- What is asserted:
--   1. LEARNED-ONLY ROWS.  With Pummel ($5d, bit0) and Suplex ($5f, bit2)
--      learned but AuraBolt ($5e, bit1) NOT, wItemList packs exactly $5d,$5f
--      then $ff, and the drawn menu shows "Pummel" and "Suplex" (findName over
--      VRAM) but never "AuraBolt".
--   2. THE OLD CODE IS DEAD.  Mashing Pummel's vanilla combo directions
--      (LEFT RIGHT LEFT) as pad edges in the open list queues nothing: the
--      menu stays open, no action commits.  Only the cursor + A selects.
--   3. SELECTION RESOLVES.  Writing the cursor onto Pummel's row and pressing
--      A lands attack $5d in $3410 ("last skill used").
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS = 0x05, 0x30
local CMD_BLITZ = 0x0A
local CMDTBL, ITEMLIST, KNOWN = 0x202E, 0x4005, 0x1D28
local PUMMEL, AURABOLT, SUPLEX = 0x5D, 0x5E, 0x5F
local LEARNED = 0x05                   -- bit0 Pummel + bit2 Suplex; bit1 (AuraBolt) OFF

local PARTY = { 0, 1, 2 }
-- FF6 English font glyphs: 'A'..'Z' = $80.., 'a'..'z' = $9a.. (the mapping
-- battle_class.lua's "Chain" = {C=$82,h=$a1,a=$9a,i=$a2,n=$a7} pins down).
local NM = {
  Pummel   = { 0x8f, 0xae, 0xa6, 0xa6, 0x9e, 0xa5 },        -- P u m m e l
  Suplex   = { 0x92, 0xae, 0xa9, 0xa5, 0x9e, 0xb1 },        -- S u p l e x
  AuraBolt = { 0x80, 0xae, 0xab, 0x9a, 0x81, 0xa8, 0xa5, 0xad }, -- A u r a B o l t
}

local actor
-- Install a full-Blitz Sabin in every party slot, every frame it is called.
local function pinSabin()
  H.writeByte(KNOWN, LEARNED)          -- known-blitz set: the byte the menu reads
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, 0x05)               -- CHAR::SABIN
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)        -- clear magitek
    for i = 0, 3 do H.writeByte(CMDTBL + s * 12 + i * 3, CMD_BLITZ) end
    H.writeWord(0x3BF4 + s * 2, 999)                -- nobody dies mid-bench
  end
end

-- findName (battle_class.lua): word address of a rendered glyph run, or nil.
local function findName(seq)
  local vr = emu.memType.snesVideoRam
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then return w end
  end
  return nil
end

local spells = {}

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.call(function()
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
  end),

  -- install Sabin every frame until a menu belongs to somebody
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pinSabin), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.log(string.format("sabin installed in slot %d (char id $%02x), known set $%02x",
      actor, H.readByte(0x3ED8 + actor * 2), H.readByte(KNOWN)))
  end),

  -- open the blitz menu: A from the command list opens the poked Blitz, which
  -- hands off to the tools-shell list (state $30).
  H.driveUntil(function() return H.readByte(MSTATE) == ST_TOOLS end, 900, {
    H.call(function() pinSabin(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the blitz list opens (tools-shell state $30)"),
  H.waitFrames(6),                     -- let every row finish drawing
  H.call(function() H.screenshot("blitzlist_window") end),

  -- 1. LEARNED-ONLY ROWS -----------------------------------------------------
  H.call(function()
    local ids = {}
    for i = 0, 7 do ids[i] = H.readByte(ITEMLIST + i * 3) end
    H.log(string.format("wItemList rows: %02x %02x %02x %02x %02x %02x %02x %02x",
      ids[0], ids[1], ids[2], ids[3], ids[4], ids[5], ids[6], ids[7]))
    H.assertEq(ids[0], PUMMEL, "row 0 is Pummel ($5d, bit0)")
    H.assertEq(ids[1], SUPLEX, "row 1 is Suplex ($5f, bit2) -- AuraBolt (bit1) skipped")
    H.assertEq(ids[2], 0xFF, "row 2 terminates: only the two learned blitzes are packed")

    H.assertEq(findName(NM.Pummel) ~= nil, true, "\"Pummel\" is drawn in the menu")
    H.assertEq(findName(NM.Suplex) ~= nil, true, "\"Suplex\" is drawn in the menu")
    H.assertEq(findName(NM.AuraBolt), nil,
      "\"AuraBolt\" is NOT drawn -- an unlearned blitz never appears")
  end),

  -- 2. THE OLD CODE IS DEAD ---------------------------------------------------
  -- Pummel's vanilla combo was LEFT RIGHT LEFT A.  Its DIRECTIONS, mashed as
  -- pad edges in the open list, must only walk the cursor -- never queue.
  H.call(function() H.assertEq(H.readByte(MSTATE), ST_TOOLS, "in the list before the mash") end),
  H.call(function() pinSabin(); H.setPad({ "left" }) end),  H.waitFrames(4),
  H.call(function() pinSabin(); H.setPad({}) end),          H.waitFrames(4),
  H.call(function() pinSabin(); H.setPad({ "right" }) end), H.waitFrames(4),
  H.call(function() pinSabin(); H.setPad({}) end),          H.waitFrames(4),
  H.call(function() pinSabin(); H.setPad({ "left" }) end),  H.waitFrames(4),
  H.call(function() pinSabin(); H.setPad({}) end),          H.waitFrames(4),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_TOOLS,
      "mashing the old blitz combo directions queued nothing -- still in the menu")
    H.assertEq(H.readByte(MENU) ~= 0, true, "the battle menu is still up")
  end),

  -- 3. SELECTION RESOLVES -----------------------------------------------------
  H.call(function()
    local slot = H.readByte(ACTOR)
    local row = nil
    for i = 0, 7 do if H.readByte(ITEMLIST + i * 3) == PUMMEL then row = i end end
    H.assertEq(row, 0, "Pummel sits at row 0")
    H.writeByte(0x895F + slot, 0)        -- scroll
    H.writeByte(0x8963 + slot, row % 2)  -- column
    H.writeByte(0x8967 + slot, row // 2) -- row
  end),
  H.waitFrames(2),
  H.pressButtons({ "a" }, 4), H.waitFrames(8),
  H.driveUntil(function()
    for _, v in ipairs(spells) do if v == PUMMEL then return true end end
    return false
  end, 4000, {
    H.call(function()
      pinSabin()
      if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) ~= ST_TOOLS then H.setPad({ "a" })
      else H.setPad({}) end
    end),
    H.waitFrames(3),
  }, "the picked Pummel resolves to attack $5d"),
  H.call(function()
    H.assertEq(H.readByte(0x3410), PUMMEL,
      "the selected blitz resolved to Pummel ($5d)")
    H.log("PASSED: blitz menu lists learned-only, ignores the old combo, resolves")
    H.screenshot("blitzlist_resolved")
  end),
})
