-- @suite
-- battle_breakfloor.lua -- the generated per-species break-floor class table,
-- asserted in ROM.  (battle_breaktbl.lua pattern: pure ROM bytes, no
-- savestate, exit 0 = pass.)
--
-- OT6_FLOOR_CLASS is wired into the @formula seed fallback (ot6.asm): a
-- monster with no authored Ot6ShieldTbl row seeds its class-weak mask
-- $3e9c from OT6_FLOOR_CLASS[species] instead of clearing it to zero, so
-- every species is breakable by at least one weapon class. This test
-- checks that the generated table (gen_break_floor.py) lands in the
-- assembled ROM with the classes the classifier chose.
--
-- OT6_FLOOR_CLASS is one class byte per species (0..383), directly indexed by
-- species id (matching OT6_CODEX width); it lives in bank $F0 (segment
-- ot6_code).  HiROM PRG file offset = SNES addr - 0xC00000, so bank $F0 ->
-- 0x300000+. The test locates the table itself by its opening run of
-- species classes, so it survives future data shifts.

local PRG = emu.memType.snesPrgRom
local SWORD, DAGGER, FIST, ARCANE, KATANA, SPEAR = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20   -- ot6_class.asm (#566)
local fails = 0

local function rb(off) return emu.read(off, PRG) end

-- scan [lo, hi] for a byte sequence; return its offset or nil
local function find(seq, lo, hi)
  for o = lo, hi do
    local hit = true
    for i = 1, #seq do
      if rb(o + i - 1) ~= seq[i] then hit = false; break end
    end
    if hit then return o end
  end
  return nil
end

local function check(cond, msg)
  if not cond then fails = fails + 1 end
  emu.log(string.format("breakfloor: %s %s", cond and "OK  " or "FAIL", msg))
end

-- anchor: species 0..15 classes (the guard a spear, the soldier and the
-- templar daggers, the ninja a katana, the samurai a sword, the orog a fist,
-- and so on: the classifier's slash, pierce and bludgeon, each split in two
-- by six_class_split.json), a distinctive 16-byte run (unique in
-- [300000,310000) on the six-class ROM, #566).
local base = find(
  { SPEAR, DAGGER, DAGGER, KATANA, SWORD, FIST, KATANA, SPEAR,
    KATANA, SWORD, SWORD, FIST, KATANA, SWORD, KATANA, SWORD },
  0x300000, 0x310000)

if not base then
  emu.log("breakfloor: FAIL OT6_FLOOR_CLASS not located")
  emu.stop(1)
  return
end
emu.log(string.format("breakfloor: OT6_FLOOR_CLASS @%06X", base))

-- floor[species] the classifier chose: one per class bit, plus a beast
-- default.  These are the bytes the @formula seed reads as the fallback mask.
local want = {
  [0]  = { SPEAR, "guard (armored -> pierce: the spear)" },
  [36] = { SPEAR, "white drgn (pierce: the spear)" },
  [71] = { FIST,   "flan (soft body -> bludgeon: the fist)" },
  [19] = { SWORD,  "were-rat (beast default -> slash: the sword)" },
}
for species, w in pairs(want) do
  local got = rb(base + species)
  check(got == w[1],
    string.format("species %d %s: floor=%02X (want %02X)", species, w[2], got, w[1]))
end

-- every floor byte must name at least one breakable class; that is what the
-- floor is for, so that no un-authored species is left with a zero class
-- mask, which would make it unbreakable.  Sweep all 384 species.
local ANY = SWORD | DAGGER | FIST | ARCANE | KATANA | SPEAR
local zeros = 0
for species = 0, 383 do
  local got = rb(base + species)
  if (got & ANY) == 0 then zeros = zeros + 1 end
end
check(zeros == 0,
  string.format("all 384 species carry a breakable class (%d had none)", zeros))

if fails == 0 then
  emu.log("breakfloor: break-floor table present and complete - PASS")
  emu.stop(0)
else
  emu.log(string.format("breakfloor: %d assertion(s) FAILED", fails))
  emu.stop(1)
end
