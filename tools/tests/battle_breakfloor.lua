-- @suite
-- battle_breakfloor.lua -- the generated per-species break-floor class table,
-- asserted in ROM.  (battle_breaktbl.lua pattern: pure ROM bytes, no
-- savestate, exit 0 = pass.)
--
-- Phase 2 of "break floor" (#6) wired OT6_FLOOR_CLASS into the @formula seed
-- fallback (ot6.asm): a monster with NO authored Ot6ShieldTbl row now seeds
-- its class-weak mask $3e9c from OT6_FLOOR_CLASS[species] instead of clearing
-- it to zero -- so every species is breakable by SOME weapon class.  This
-- test is the regression gate that the generated table (gen_break_floor.py)
-- actually lands in the assembled ROM with the classes the classifier chose.
--
-- OT6_FLOOR_CLASS is one class byte per species (0..383), directly indexed by
-- species id (matching OT6_CODEX width); it lives in bank $F0 (segment
-- ot6_code).  HiROM PRG file offset = SNES addr - 0xC00000, so bank $F0 ->
-- 0x300000+ (school.lua / battle_breaktbl.lua document the same mapping).
-- The test SELF-LOCATES the table by its opening run of species classes, so
-- it survives future data shifts the way breaktbl self-locates its tables.

local PRG = emu.memType.snesPrgRom
local SLASH, PIERCE, BLUDG = 0x01, 0x02, 0x04
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

-- anchor: species 0..15 classes -- guard/soldier/templar pierce, ninja/
-- samurai slash, orog bludgeon, ... a distinctive 16-byte run (verified
-- unique in [300000,310000) at authoring time).
local base = find(
  { PIERCE, PIERCE, PIERCE, SLASH, SLASH, BLUDG, SLASH, PIERCE,
    SLASH, SLASH, SLASH, BLUDG, SLASH, SLASH, SLASH, SLASH },
  0x300000, 0x310000)

if not base then
  emu.log("breakfloor: FAIL OT6_FLOOR_CLASS not located")
  emu.stop(1)
  return
end
emu.log(string.format("breakfloor: OT6_FLOOR_CLASS @%06X", base))

-- floor[species] the classifier chose -- one per class bit, plus a beast
-- default.  These are the bytes the @formula seed reads as the fallback mask.
local want = {
  [0]  = { PIERCE, "guard (armored -> pierce)" },
  [36] = { PIERCE, "white drgn (pierce)" },
  [71] = { BLUDG,  "flan (soft body -> bludgeon)" },
  [19] = { SLASH,  "were-rat (beast default -> slash)" },
}
for species, w in pairs(want) do
  local got = rb(base + species)
  check(got == w[1],
    string.format("species %d %s: floor=%02X (want %02X)", species, w[2], got, w[1]))
end

-- every floor byte must name at least one breakable class (that is the whole
-- point of a FLOOR: no un-authored species left with a zero -- i.e.
-- unbreakable -- class mask).  Sweep all 384 species.
local ANY = SLASH | PIERCE | BLUDG
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
