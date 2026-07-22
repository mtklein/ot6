-- @suite
-- battle_breaktbl.lua -- the v0.6 break-coverage tables, asserted in ROM.
-- (school.lua pattern: pure ROM bytes, no savestate, exit 0 = pass.)
--
-- Proves the authored weaknesses that close the fixed-party break gaps
-- actually land in the assembled ROM. The audit found a class of enemies
-- that no forced party could break -- formula species (no class weakness)
-- whose party could reach none of their vanilla/added ELEMENTS. This test
-- is the regression gate for the fix: every gap enemy now carries the
-- weapon class its forced party can reach, TEMPLAR gained the conducting
-- bolt half of the armor palette, and the LEADER/GRUNT poison adds -- the
-- retired "one right tool" artifacts on enemies whose forced parties
-- carry no poison -- are gone.
--
-- Ot6ShieldTbl (word id, byte shields, byte class) and Ot6ElemAddTbl
-- (word id, byte element, byte pad) both live in bank $F0 (segment
-- ot6_code); HiROM PRG file offset = SNES addr - 0xC00000, so bank $F0 ->
-- 0x300000+ (school.lua documents the same mapping for the dialog banks).
-- The test SELF-LOCATES both tables by their opening anchor records, so
-- it survives future row insertions/shifts the way school self-locates
-- through the dialog pointer table.

local PRG = emu.memType.snesPrgRom
local SLASH, PIERCE, BLUDG = 0x01, 0x02, 0x04
local FIRE, BOLT, POISON = 0x01, 0x04, 0x08
local fails = 0

local function rb(off) return emu.read(off, PRG) end
local function rw(off) return rb(off) + rb(off + 1) * 256 end

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

-- walk a 4-byte-record table (word id, byte b1, byte b2; $ffff ends it)
-- into id -> {b1, b2}. bounded so a mislocated base can't run away.
local function walk(base)
  local t, o = {}, base
  for _ = 1, 400 do
    local id = rw(o)
    if id == 0xffff then break end
    t[id] = { rb(o + 2), rb(o + 3) }
    o = o + 4
  end
  return t
end

local function check(cond, msg)
  if not cond then fails = fails + 1 end
  emu.log(string.format("breaktbl: %s %s", cond and "OK  " or "FAIL", msg))
end

-- anchors: ShieldTbl opens guard/lobo/whelk(shell); ElemAddTbl opens
-- whelk-head(fire)/vargas(holy). both are distinctive multi-record runs.
local shieldBase = find(
  { 0x00, 0x00, 0x02, 0x02, 0x19, 0x00, 0x03, 0x02, 0x00, 0x01, 0x00, 0x00 },
  0x300000, 0x310000)
local elemBase = find(
  { 0x34, 0x01, 0x01, 0x00, 0x03, 0x01, 0x20, 0x00 },
  0x300000, 0x310000)

if not shieldBase or not elemBase then
  emu.log(string.format("breaktbl: FAIL tables not located (shield=%s elem=%s)",
    tostring(shieldBase), tostring(elemBase)))
  emu.stop(1)
  return
end
emu.log(string.format("breaktbl: Ot6ShieldTbl @%06X  Ot6ElemAddTbl @%06X",
  shieldBase, elemBase))

local S = walk(shieldBase)
local E = walk(elemBase)

-- the v0.6 class rows: id -> {shields, class, name}
local want = {
  [0x0001] = { 2, SLASH | PIERCE, "soldier" },
  [0x0002] = { 3, PIERCE,         "templar" },
  [0x014e] = { 3, SLASH,          "leader (Cyan duel)" },
  [0x014f] = { 2, SLASH | BLUDG,  "grunt" },
  [0x0176] = { 3, SLASH | BLUDG,  "cadet" },
  [0x0175] = { 2, PIERCE,         "officer" },
  [0x0065] = { 2, SLASH | PIERCE, "trooper" },
  [0x003f] = { 3, SLASH | PIERCE, "rider" },
  [0x009f] = { 3, SLASH | PIERCE, "heavyarmor" },
  [0x013a] = { 2, PIERCE,         "merchant" },
  [0x003a] = { 2, SLASH,          "anguiform (trench)" },
  [0x005e] = { 2, BLUDG,          "actaneon (trench)" },
  [0x0059] = { 2, PIERCE,         "aspik (trench)" },
}
for id, w in pairs(want) do
  local r = S[id]
  check(r ~= nil and r[1] == w[1] and r[2] == w[2],
    string.format("%s $%04X: shields=%s class=%s (want %d/%02X)", w[3], id,
      r and tostring(r[1]) or "MISSING",
      r and string.format("%02X", r[2]) or "-", w[1], w[2]))
end

-- element table: templar gained conducting bolt; leader/grunt poison GONE
check(E[0x0002] ~= nil and E[0x0002][1] == BOLT,
  string.format("templar $0002 elem-add = bolt $04 (got %s)",
    E[0x0002] and string.format("%02X", E[0x0002][1]) or "MISSING"))
check(E[0x014e] == nil, "leader $014E has NO element add (poison retired)")
check(E[0x014f] == nil, "grunt $014F has NO element add (poison retired)")
-- the two machines keep their poison (a party that fights them can cast it)
check(E[0x0042] ~= nil and E[0x0042][1] == POISON, "m-tekarmor $0042 keeps poison")
check(E[0x009f] ~= nil and E[0x009f][1] == POISON, "heavyarmor $009F keeps poison")

-- regression: the rows both tables opened with, untouched by this pass
check(S[0x0000] ~= nil and S[0x0000][2] == PIERCE, "regression: guard $0000 pierce")
check(S[0x0134] ~= nil and S[0x0134][2] == PIERCE, "regression: whelk head $0134 pierce")
check(E[0x0134] ~= nil and E[0x0134][1] == FIRE, "regression: whelk head fire add")

if fails == 0 then
  emu.log("breaktbl: all v0.6 break-coverage rows present - PASS")
  emu.stop(0)
else
  emu.log(string.format("breaktbl: %d assertion(s) FAILED", fails))
  emu.stop(1)
end
