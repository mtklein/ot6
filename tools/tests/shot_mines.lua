-- shot_mines.lua -- one screenshot of a live mines random-encounter fight at
-- the shipped constants, for eyeball verification (Measurement #5).
--   tools/tests/run.sh tools/tests/shot_mines.lua build/states/shot_mines.log
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/mines_chase.mss.lua"

-- knob offsets for the caption, read live from ROM. BUILD-SPECIFIC (bank
-- F0 layout) and they HAD drifted: both were $12 low ($300173/$30033C)
-- against the build of 2026-07-18 and read $6A/$88 -- live code bytes,
-- not knobs -- so a shot taken "at the shipped constants" was captioned
-- with two instruction bytes. Re-derive from ff6/rom/ff6-en.dbg after any
-- bank-F0 edit (val=0xF00185 etc, minus $C00000); KNOB_OK fails loudly.
local ROM_HPMUL  = 0x300185         -- Ot6HpMulTbl band0
local ROM_SHIELD = 0x30034E         -- Ot6ShieldedMulW (word, low byte)
local KNOB_OK = { [0x08]=true, [0x0c]=true, [0x10]=true, [0x18]=true, [0x20]=true }

local function calm(n)
  local cnt = 0
  return function()
    cnt = (H.hasControl() and H.tileAligned()) and cnt + 1 or 0
    return cnt >= n
  end
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(calm(20), 1200, "field control"),
  -- pace the two-tile walk at map entry until a battle starts loading
  H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
    H.call(function()
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
      local x = H.fieldX()
      H.setPad({ [(x >= 78) and "left" or "right"] = true })
    end),
    H.waitFrames(1),
  }, "encounter fires"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 1200, "battle active", 30),
  H.waitFrames(300),                 -- settle past the window-open animation
  H.call(function()
    local sp = {}
    for slot = 0, 5 do
      if (H.readByte(0x3aa8 + slot*2) & 1) == 1 then
        sp[#sp+1] = string.format("s%d:sp%04X:hp%d:sh%d/%d", slot,
          H.readWord(0x57c0 + slot*2), H.readWord(0x3bfc + slot*2),
          H.readByte(0x3e40 + slot*2), H.readByte(0x3e40 + slot*2 + 1))
      end
    end
    for _, g in ipairs({ { ROM_HPMUL,  "Ot6HpMulTbl"     },
                         { ROM_SHIELD, "Ot6ShieldedMulW" } }) do
      local seen = H.readRomByte(g[1])
      if not KNOB_OK[seen] then
        error(string.format(
          "knob layout drift: %s at $%06X reads $%02X -- re-derive from "
          .. "ff6/rom/ff6-en.dbg", g[2], g[1], seen), 0)
      end
    end
    H.log("mines fight: knob_hp=" .. string.format("%02x", H.readRomByte(ROM_HPMUL))
      .. " knob_shield=" .. string.format("%02x", H.readRomByte(ROM_SHIELD)))
    H.log("formation: " .. table.concat(sp, "  "))
    H.screenshot("shot_mines")
  end),
})
