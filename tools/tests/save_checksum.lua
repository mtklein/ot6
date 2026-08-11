-- @suite savestate=worldmap_narshe
-- (The marker was a bare `-- @suite` until v0.6.  This test loads
-- build/states/worldmap_narshe.mss.lua at :34, which only `make savestates`
-- generates, so a plain marker made it a hard `make test` failure -- "compose
-- failed: save_checksum" -- in every tree without the generated states, i.e. every
-- fresh worktree.  It passed in the main tree only because that tree happens
-- to have the fixture.  codex_saveas.lua loads the same state and declares the
-- same requirement; this now matches it.  Found while landing #11/#23.)
-- Regression for #18.  CheckSaveSlotChecksum returns the checksum ITSELF as its
-- validity token and 0 for invalid -- there is no separate flag -- and every
-- caller tests it with beq.  So a perfectly intact save whose 2558-byte sum
-- happens to land on $0000 is drawn as an EMPTY slot, refuses to load, and is
-- overwritten with no confirmation prompt (field_menu.asm:1981-1988 branches on
-- the zero straight into `; slot is empty, save instantly`).
--
-- CalcSaveSlotChecksum now folds a $0000 result onto $ffff.  The stored word at
-- $1ffe sits OUTSIDE the summed range ($1600..$1ffd, cpx #$09fe), so the fold
-- applies identically on write and on verify.
--
-- This drives the game's REAL save, the codex_saveas way, rather than
-- reimplementing the sum: zero the summed range so it genuinely totals $0000,
-- let vanilla's own CopyGameDataToSRAM run, then read back what it stored.
-- The resulting save is deliberately garbage -- only the checksum is under test.
-- Saving is only legal on the world map, so this runs from worldmap_narshe.
--
-- *** QUARANTINED MECHANISM TEST (issue #75) -- state writes SANCTIONED ***
-- Owner-named on the #75 policy list: the 1/65536 zero-checksum save.  A
-- real game state whose 2558-byte sum lands exactly on $0000 exists but
-- cannot be reached on cue by play; the zeroed range is the only way to
-- put the fold under test.  It keeps its waiver, and it MAY NEVER
-- PRODUCE FIXTURES.
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE       = 0x0026
local MAIN_MENU        = 0x05
local SAVE_SELECT      = 0x14
local ACTIVE           = 0x021f

_zeroed = false
local function sumRange()
  local s = 0
  for a = 0x1600, 0x1ffd do s = (s + H.readByte(a)) & 0xFFFF end
  return s
end

H.run({ maxFrames = 8000 }, {
  H.waitFrames(20),
  H.loadState("build/states/worldmap_narshe.mss.lua"),
  H.waitFrames(60),

  H.pressButtons({ "x" }, 4),
  H.waitFrames(120),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == MAIN_MENU end,
    300, "main menu", 5),
  -- Reach save select by pad (save-drive rule, tools/tests/README): UP wraps
  -- the main-menu cursor from Items to Save, A runs SelectMainMenuOption_06's
  -- real entry, DOWN walks the slot cursor to slot 3.  The drives poll the
  -- state and cursor by READING them, so no frame count is load-bearing.
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == MAIN_MENU and H.readByte(0x4b) == 6
  end, 600, {
    H.pressButtons({ "up" }, 4), H.waitFrames(16),
  }, "main-menu cursor on Save"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    600, "save-slot selection", 5),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == SAVE_SELECT and H.readByte(0x4b) == 2
  end, 600, {
    H.pressButtons({ "down" }, 4), H.waitFrames(16),
  }, "save cursor on slot 3"),
  H.call(function()
    -- The game repacks $1600..$1ffd from live state during the save, so zeroing
    -- it from a step is too early -- it gets overwritten before the sum runs.
    -- Hook the checksum routine itself and zero the range on entry, so the sum
    -- it computes really is $0000.
    local entry = H.sym("CalcSaveSlotChecksum")
    H.assertEq(entry ~= nil, true, "CalcSaveSlotChecksum resolved")
    emu.addMemoryCallback(function()
      for a = 0x1600, 0x1ffd do
        emu.write(a, 0, emu.memType.snesWorkRam)
      end
      _zeroed = true
    end, emu.callbackType.exec, entry, entry)
  end),
  H.pressButtons({ "a" }, 4),
  H.driveUntil(function() return H.readByte(ACTIVE) == 3 end, 900, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "save into slot 3"),

  H.call(function()
    H.assertEq(_zeroed == true, true,
      "control: the checksum hook actually fired (else nothing was tested)")
    local stored = H.readWord(0x1ffe)
    H.log(string.format("[save] summed range = $0000, stored checksum = $%04X", stored))
    H.assertEq(stored, 0xFFFF,
      "a $0000 sum is stored as $ffff, not as the invalid sentinel")
    H.assertEq(stored ~= 0, true,
      "and therefore this save does NOT read as an empty slot")
  end),
  H.logStep("save checksum $0000 collision covered"),
})
