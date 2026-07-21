-- @suite
-- Smoke test: verify the build pipeline produced an OT6 ROM, then exit.
-- Exit code 0 = pass, 1 = fail.
--
-- The marker is Dirk's item-name byte 0. OT6 replaces every weapon's
-- item-name icon with its break-class icon (commit "the icon IS the
-- class"); Dirk is item 0 and wears the piercing icon {spear} = $DA
-- (vanilla FF3us has the dirk icon $D8 there). The address: the
-- item_name segment loads at $D2B300 (ff6/rom/ff6-en.map), HiROM
-- $D2B300 -> PRG file offset 0x12B300; ITEM_SIZE = 13 per entry
-- (include/text/item_name_en.inc) and Dirk is entry 0, so its bytes
-- start at the segment base. "Dirk" itself encodes as 83 A2 AB A4.
local expected = { 0xDA, 0x83, 0xA2, 0xAB, 0xA4 }

local function check()
  for i, v in ipairs(expected) do
    local b = emu.read(0x12B300 + i - 1, emu.memType.snesPrgRom)
    if b ~= v then
      emu.log(string.format("MISMATCH at +%d: got %02X want %02X", i - 1, b or -1, v))
      emu.stop(1)
      return
    end
  end
  emu.log("smoke: {spear}Dirk class-icon marker found in ROM - PASS")
  emu.stop(0)
end

check()
