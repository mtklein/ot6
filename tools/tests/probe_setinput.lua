-- probe_setinput: the MOST minimal input test possible. No srm, no boot, no
-- game logic. Just: inject "up" via emu.setInput inside inputPolled, run a
-- few frames, and read the CPU-visible auto-joypad registers $4218/$4219 to
-- see whether the ROM would observe our buttons. This isolates the input
-- PRIMITIVE from everything else. SNES auto-joypad layout for $4218 (JOY1L)
-- high byte $4219: bit order (byte1=$4219) B Y Sel Sta Up Dn Lt Rt,
-- (byte0=$4218) A X L R ---- . We assert the injected direction shows up.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local function joyRegs()
  -- read the auto-joypad result registers as the CPU sees them
  local lo1 = emu.read(0x4218, emu.memType.snesMemory)
  local hi1 = emu.read(0x4219, emu.memType.snesMemory)
  return lo1, hi1
end

local samples = {}

H.run({ maxFrames = 600 }, {
  H.waitFrames(30),
  H.call(function()
    local lo, hi = joyRegs()
    H.log(string.format("idle:  $4218=%02X $4219=%02X getInput=%s",
      lo, hi, H.dump and H.dump(emu.getInput(0)) or "?"))
  end),
  H.hold({ "up" }),
  H.waitFrames(20),
  H.call(function()
    local lo, hi = joyRegs()
    local gi = emu.getInput(0)
    H.log(string.format("hold up: $4218=%02X $4219=%02X getInput.up=%s",
      lo, hi, tostring(gi and gi.up)))
    samples.up = { lo = lo, hi = hi, gi = gi and gi.up }
  end),
  H.release(),
  H.waitFrames(20),
  H.hold({ "a" }),
  H.waitFrames(20),
  H.call(function()
    local lo, hi = joyRegs()
    local gi = emu.getInput(0)
    H.log(string.format("hold a:  $4218=%02X $4219=%02X getInput.a=%s",
      lo, hi, tostring(gi and gi.a)))
    samples.a = { lo = lo, hi = hi, gi = gi and gi.a }
  end),
  H.release(),
  H.waitFrames(20),
  H.call(function()
    -- $4219 bit3 (0x08) is Up in the standard SNES auto-joypad layout;
    -- $4218 bit7 (0x80) is A. Confirm at least one path shows our injection.
    local upSeen = samples.up and (samples.up.hi & 0x08) ~= 0
    local aSeen = samples.a and (samples.a.lo & 0x80) ~= 0
    local giUp = samples.up and samples.up.gi == true
    local giA = samples.a and samples.a.gi == true
    H.log(string.format("SUMMARY reg:up=%s reg:a=%s getInput:up=%s getInput:a=%s",
      tostring(upSeen), tostring(aSeen), tostring(giUp), tostring(giA)))
    H.assertEq((upSeen or giUp) and (aSeen or giA), true,
      "setInput reaches the emulator (register or getInput reflects injection)")
  end),
})
