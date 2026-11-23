-- @suite
-- Smoke test: verify the build pipeline produced an OT6 ROM, then exit.
-- Exit code 0 = pass, 1 = fail.
--
-- The marker is an item-name byte 0. OT6 gives every weapon's item name its
-- break-class icon.  Under six classes (#566) Dirk, item 0, wears the dagger
-- icon {dagger} = $D8, the byte vanilla FF3us has there too, so Dirk no
-- longer tells an OT6 ROM from a vanilla one (under four classes it wore the
-- piercing icon $DA and was the marker).  The marker is the Mithril Claw,
-- item $54: an edged claw is a Katana and wears the katana icon $DB, where
-- vanilla has the claw icon $E1.  Dirk's own bytes are still checked: a
-- dagger wears the dagger icon.
-- The item_name segment loads at $D2B300, HiROM $D2B300 -> PRG file offset
-- 0x12B300; ITEM_SIZE = 13 per entry. "Dirk" encodes as 83 A2 AB A4 and
-- "Mithril Claw" as 8C A2 AD A1 AB A2 A5 FE 82 A5 9A B0.
local ITEM_NAME, ITEM_SIZE = 0x12B300, 13
local expected = {
  { item = 0x00, what = "{dagger}Dirk", bytes = { 0xD8, 0x83, 0xA2, 0xAB, 0xA4 } },
  { item = 0x54, what = "{katana}Mithril Claw",
    bytes = { 0xDB, 0x8C, 0xA2, 0xAD, 0xA1, 0xAB, 0xA2, 0xA5, 0xFE, 0x82, 0xA5, 0x9A, 0xB0 } },
}

local function check()
  for _, e in ipairs(expected) do
    for i, v in ipairs(e.bytes) do
      local b = emu.read(ITEM_NAME + e.item * ITEM_SIZE + i - 1, emu.memType.snesPrgRom)
      if b ~= v then
        emu.log(string.format("MISMATCH in %s (item $%02X) at +%d: got %02X want %02X",
          e.what, e.item, i - 1, b or -1, v))
        emu.stop(1)
        return
      end
    end
  end
  emu.log("smoke: {dagger}Dirk and the {katana}Mithril Claw class-icon marker found in ROM - PASS")
  emu.stop(0)
end

check()
