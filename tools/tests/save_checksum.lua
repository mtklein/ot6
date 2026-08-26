-- @suite savestate=worldmap_narshe
-- CheckSaveSlotChecksum returns the checksum itself as its validity token
-- and 0 for invalid, with no separate flag, and every caller tests it with
-- beq.  So an intact save whose 2558-byte sum happens to land on $0000 is
-- drawn as an empty slot, refuses to load, and is overwritten with no
-- confirmation prompt.
--
-- CalcSaveSlotChecksum folds a $0000 result onto $ffff.  The stored word at
-- $1ffe sits outside the summed range ($1600..$1ffd), so the fold applies
-- identically on write and on verify.
--
-- This drives the game's own save path rather than reimplementing the sum:
-- zero the summed range so it totals $0000, let vanilla's own
-- CopyGameDataToSRAM run, then read back what it stored.  The resulting
-- save is garbage; only the checksum is under test.  Saving is only legal
-- on the world map, so this runs from worldmap_narshe.
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
  -- up wraps the main-menu cursor from Items to Save, A runs
  -- SelectMainMenuOption_06's real entry, down walks the slot cursor to
  -- slot 3.  The drives poll the state and cursor by reading them, so no
  -- frame count is load-bearing.
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
    -- it from a step is too early: it gets overwritten before the sum runs.
    -- Hook the checksum routine itself and zero the range on entry, so the sum
    -- it computes is $0000.
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
