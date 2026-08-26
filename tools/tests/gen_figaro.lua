-- gen_figaro.lua -- from worldmap_narshe.mss (LOCKE + TERRA on foot at
-- WoB (84,34)): world-nav south across the plains to Figaro Castle's
-- gate trigger, ride the entry event into the castle complex, and generate
-- figaro_entry.mss at the first controllable interior moment.

local H = dofile("tools/tests/lib/ot6.lua")
local WORLD = "build/states/worldmap_narshe.mss.lua"

local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

H.run({ maxFrames = 90000 }, {
  H.loadState(WORLD),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.worldMode(), true, "boot state is on the world map")
    H.assertEq(H.worldId(), 0, "World of Balance")
    H.assertEq(H.worldX() == 84 and H.worldY() == 34, true,
      "at the Narshe spawn (84,34)")
    H.assertEq((H.readByte(0x1ea1) & 0x08) ~= 0, true,
      "Figaro gate switch $010B set (trigger live)")
  end),

  H.worldNavTo(64, 77, { maxFrames = 45000, playBattles = true }),
  H.logStep(function()
    return string.format("at the Figaro entry point (%d,%d), frame %d, danger=%04X",
      H.worldX(), H.worldY(), H.frame, H.readWord(0x1f6e))
  end),

  H.driveUntil(function() return not H.worldMode() end, 9000, {
    H.call(function()
      if H.battleLoadStarted() then
        H.setPad(H.frame % 8 < 4 and { "a" } or {})
        return
      end
      if not H.worldAligned() then return end
      H.setPad({ up = true })
    end),
  }, "Figaro entry event loads the castle"),
  H.release(),

  -- field-side settle: control + full brightness + margin
  H.waitUntil(calm(30), 1200, "castle control", 5),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "castle fade-in", 10),
  H.waitFrames(30),

  -- ===================================================================== --
  -- Assert + generate.  Masked map compare: SET_PARENT rides bit9 into
  -- $1F64.
  -- ===================================================================== --
  H.call(function()
    H.log(string.format("[record] castle arrival: $1F64 raw=%04X (masked %d)",
      H.readWord(0x1f64), H.readWord(0x1f64) & 0x1FF))
    H.assertEq(H.readWord(0x1f64) & 0x1FF, 55,
      "on the Figaro Castle complex (map 55)")
    H.assertEq(H.fieldX() == 28 and H.fieldY() == 42, true,
      string.format("at the castle gate (28,42) (got %d,%d)",
        H.fieldX(), H.fieldY()))
    H.assertEq(H.readByte(0x1850) & 0x07, 1, "TERRA in party 1")
    H.assertEq(H.readByte(0x1851) & 0x07, 1, "LOCKE in party 1")
    -- story switches consistent: defense won ($0631 clear), collapse
    -- chain done ($012E set), Figaro position-A flag still set
    H.assertEq((H.readByte(0x1f46) & 0x02), 0, "defense-won switch state")
    H.assertEq((H.readByte(0x1ea5) & 0x40) ~= 0, true, "$012E set")
    H.assertEq((H.readByte(0x1ea1) & 0x08) ~= 0, true, "$010B still set")
    H.log(string.format("figaro entry point: map=%d (%d,%d) frame=%d",
      H.readWord(0x1f64) & 0x1FF, H.fieldX(), H.fieldY(), H.frame))
    H.screenshot("figaro_entry")
  end),
  H.saveState("figaro_entry.mss"),
  H.logStep(function()
    return string.format("figaro_entry generated at frame %d", H.frame)
  end),
})
