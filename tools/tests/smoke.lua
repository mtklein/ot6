-- Smoke test: verify the hello-world edit (default name TERRA -> OCTO)
-- is present in PRG ROM, then exit. Exit code 0 = pass, 1 = fail.
-- FF6 text encoding: 'A' = 0x80 ... so OCTO = 8E 82 93 8E, pad = FF.
local expected = { 0x8E, 0x82, 0x93, 0x8E, 0xFF }

local function check()
  for i, v in ipairs(expected) do
    local b = emu.read(0x478C0 + i - 1, emu.memType.snesPrgRom)
    if b ~= v then
      emu.log(string.format("MISMATCH at +%d: got %02X want %02X", i - 1, b or -1, v))
      emu.stop(1)
      return
    end
  end
  emu.log("smoke: OCTO name found in ROM - PASS")
  emu.stop(0)
end

check()
