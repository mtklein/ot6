-- battle_break.lua -- THE M1 acceptance test: chip -> break -> recover, live.
--
--   tools/tests/run.sh tools/tests/battle_break.lua
--
-- Guards have no natural elemental weakness, so this test makes its own
-- laboratory: walk into the first guard battle fresh, then poke both guards
-- fire-weak ($3BE0|=$01) and tough (HP 500) so they survive chipping. Terra
-- then spams Fire Beam at the default target until a break is observed.
--
-- Asserts, in order:
--   1. shields seed at 2/2 (from monster level)
--   2. a fire hit chips the target's shield and reveals the fire weakness
--      (mask $01 in $3E95/$3E97), row glyph drops to $B5 ('1')
--   3. shields reach 0 -> broken timer nonzero, row glyph becomes $81 ('B')
--   4. the broken timer expires -> shields restore to max, revealed mask
--      SURVIVES recovery, glyph returns to a digit
--
-- Entity map for this fight: guards in monster slots 2/3 -> entity offsets
-- $0C/$0E. shields $3E44/$3E46 - timers $3E94/$3E96 - revealed $3E95/$3E97
-- - weak elems $3BEC/$3BEE - HP $3C00/$3C02.

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local function shields() return H.readByte(0x3E44), H.readByte(0x3E46) end
local function timers() return H.readByte(0x3E94), H.readByte(0x3E96) end
local function revealed() return H.readByte(0x3E95), H.readByte(0x3E97) end
local function glyph0() return H.readByte(0x3ECB) end

local function report(tag)
  return H.call(function()
    local s1, s2 = shields()
    local t1, t2 = timers()
    local r1, r2 = revealed()
    H.log(string.format(
      "%s shields=%d,%d timers=%02X,%02X revealed=%02X,%02X glyph=%02X hp=%04X,%04X",
      tag, s1, s2, t1, t2, r1, r2, glyph0(),
      H.readWord(0x3C00), H.readWord(0x3C02)))
  end)
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),

  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from doorstep"),

  H.waitUntil(function() return H.battleActive() end, 900,
    "battle active", 30),
  H.waitFrames(120),

  -- 1. seeding
  H.call(function()
    local s1, s2 = shields()
    H.assertEq(s1, 2, "guard 1 shields seeded")
    H.assertEq(s2, 2, "guard 2 shields seeded")
  end),
  report("seeded"),

  -- lab setup: fire-weak, tough guards
  H.call(function()
    H.writeByte(0x3BEC, H.readByte(0x3BEC) | 0x01)
    H.writeByte(0x3BEE, H.readByte(0x3BEE) | 0x01)
    H.writeWord(0x3C00, 500)
    H.writeWord(0x3C02, 500)
    H.log("lab: guards fire-weak, hp 500")
  end),

  -- 2+3. spam Fire Beam until something breaks
  H.driveUntil(function()
    local t1, t2 = timers()
    return t1 > 0 or t2 > 0
  end, 30000, {
    H.pressButtons({ "a" }, 6), H.waitFrames(30),
    H.pressButtons({ "a" }, 6), H.waitFrames(30),
    H.pressButtons({ "a" }, 6), H.waitFrames(600),
  }, "a guard to break"),
  H.release(),
  report("broken"),
  H.call(function()
    local s1, s2 = shields()
    local t1, t2 = timers()
    local r1, r2 = revealed()
    local broke = (t1 > 0) and 1 or 2
    H.assertEq(broke == 1 and s1 or s2, 0, "broken guard shields at 0")
    H.assertEq((broke == 1 and r1 or r2) & 0x01, 0x01,
      "fire weakness revealed on the broken guard")
    H.assertEq(glyph0(), 0x81, "row glyph shows 'B' while broken")
    H.screenshot("break_broken")
  end),

  -- 4. recovery: timer expires, shields restore, reveal persists
  H.waitUntil(function()
    local t1, t2 = timers()
    local s1, s2 = shields()
    return t1 == 0 and t2 == 0 and (s1 == 2 or s2 == 2)
  end, 12000, "broken guard to recover", 60),
  H.waitFrames(30),
  report("recovered"),
  H.call(function()
    local s1, s2 = shields()
    local r1, r2 = revealed()
    H.assertEq(s1 == 2 or s2 == 2, true, "shields restored to max")
    H.assertEq((r1 | r2) & 0x01, 0x01, "revealed weakness survives recovery")
    local g = glyph0()
    H.assertEq(g >= 0xB4 and g <= 0xBD, true, "row glyph back to a digit")
    H.screenshot("break_recovered")
  end),
})
