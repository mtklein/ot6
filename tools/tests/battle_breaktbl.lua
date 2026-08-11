-- @suite
-- battle_breaktbl.lua -- the v0.6 break-coverage tables, asserted in ROM.
-- (school.lua pattern: pure ROM bytes, no savestate, exit 0 = pass.)
--
-- Proves the authored weaknesses that close the fixed-party break gaps
-- actually land in the assembled ROM. The audit found a class of enemies
-- that no forced party could break -- formula species (no class weakness)
-- whose party could reach none of their vanilla/added ELEMENTS. This test
-- is the regression test for the fix: every gap enemy now carries the
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
local FIRE, ICE, BOLT, POISON, WATER = 0x01, 0x02, 0x04, 0x08, 0x80
local fails = 0

-- MonsterProp is `.incbin monster_prop.dat` at SNES $CF0000 (link map:
-- monster_prop CF0000..CF35FF), so PRG offset = $CF0000 - $C00000 = $0F0000.
-- 32-byte records; +23 absorb, +24 null, +25 weak.
local MPROP, MREC = 0x0F0000, 32
local OFF_ABSORB, OFF_NULL, OFF_WEAK = 23, 24, 25

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
  -- emu.log goes to Mesen's SCRIPT log, which nothing reads headless (run.sh's
  -- --enableStdout mirrors the EMULATOR log only).  print() is the channel that
  -- actually reaches the run log, so a failure here names itself instead of
  -- being a bare exit code.
  local line = string.format("breaktbl: %s %s", cond and "OK  " or "FAIL", msg)
  emu.log(line)
  print(line)
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
  -- issue #23: was PIERCE, authored to a Gau "fanged strike" that bludgeons.
  -- The trench trio is Sabin + Cyan + Gau and NOBODY in it pierces: Gau's
  -- only legal weapon is the Imp Halberd $24 (no shop stocks it) and bare
  -- hands read $ff -> OT6_BLUDG.  A PIERCE row here is a dead row.
  [0x0059] = { 2, BLUDG,          "aspik (trench) -- #23, was a dead PIERCE" },
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

-- ---------------------------------------------------------------- issue #23
-- The four boss element sets bosses-wob.md authored in prose and nobody ever
-- wrote into the data.  check_boss_rows.py carried them as WAIVERS for three
-- releases; these assertions are what keeps them from silently regressing to
-- prose again.  Each is exact-mask: a missing row reads nil and a wrong row
-- reads a different byte, so both directions fail.
local elemWant = {
  -- id       mask                 why this row exists
  { 0x0117, FIRE | ICE | BOLT, "atmaweapon: the WoB capstone had ELEVEN "
    .. "shields behind slash|pierce and no element axis at all" },
  { 0x010b, BOLT | WATER,      "number 128 body: the minecart's part-break "
    .. "lesson was single-axis without it" },
  { 0x013f, BOLT,              "right blade" },
  { 0x0140, BOLT,              "left blade" },
  { 0x0116, WATER,             "flameeater: Strago's debut, and Aqua Breath "
    .. "was AoE-only until this row" },
  { 0x0168, BOLT,              "ultros 4: restores the family row's bolt half "
    .. "on a DIFFERENT species ($168, not $12c/$12d/$12e)" },
}
for _, w in ipairs(elemWant) do
  local r = E[w[1]]
  check(r ~= nil and r[1] == w[2],
    string.format("elem-add $%04X = $%02X (got %s) -- %s", w[1], w[2],
      r and string.format("$%02X", r[1]) or "MISSING", w[3]))
end

-- The trap, asserted in the direction it actually bites: every Ultros record
-- ABSORBS water, so the family row's water half must never reach $168.  A row
-- that "completes" the row by adding $84 would HEAL him, and would still pass
-- a mask-nonzero check.
check(E[0x0168] ~= nil and (E[0x0168][1] & WATER) == 0,
  "ultros 4 $0168 elem-add must NOT carry water -- $168 absorbs it")

-- ...and the same rule as a GENERAL invariant, not a spot-check.  The
-- GhostTrain rule: an element add must never intersect its species' absorb or
-- null byte, or the chip trigger lands where vanilla reverses the damage sign
-- (absorb) or zeroes it (null).  Walking the whole table means every FUTURE
-- row is covered too -- the Crane pair in bosses-wob.md was wrong in exactly
-- this direction once already.
local addRows, badAdds = 0, 0
do
  local o = elemBase
  for _ = 1, 400 do
    local id = rw(o)
    if id == 0xffff then break end
    local add = rb(o + 2)
    local absorb = rb(MPROP + id * MREC + OFF_ABSORB)
    local null   = rb(MPROP + id * MREC + OFF_NULL)
    addRows = addRows + 1
    if (add & absorb) ~= 0 or (add & null) ~= 0 then
      badAdds = badAdds + 1
      emu.log(string.format(
        "breaktbl: FAIL elem-add $%04X adds $%02X but absorb=$%02X null=$%02X"
        .. " -- feeds an absorber/null", id, add, absorb, null))
    end
    o = o + 4
  end
end
check(badAdds == 0, string.format(
  "GhostTrain rule: all %d Ot6ElemAddTbl rows are absorb-safe and null-safe",
  addRows))
-- guard the guard: if the walk found nothing, the loop above proves nothing.
-- 24 rows as of the issue #23 pass (18 before it, + the 6 boss rows above).
check(addRows >= 24, string.format(
  "elem-add walk saw %d rows (expected >= 24; a mislocated base proves nothing)",
  addRows))

-- and prove the MonsterProp base is really MonsterProp, so the invariant above
-- is comparing against real absorb bytes rather than an arbitrary window.
check(rb(MPROP + 0x0168 * MREC + OFF_ABSORB) == WATER,
  "monster_prop base sane: $168 Ultros absorb byte reads water $80")
check(rb(MPROP + 0x0117 * MREC + OFF_WEAK) == 0x00,
  "monster_prop base sane: $117 AtmaWeapon vanilla weak is $00 (the whole "
  .. "point of its added row)")

if fails == 0 then
  emu.log("breaktbl: all v0.6 break-coverage rows present - PASS")
  emu.stop(0)
else
  emu.log(string.format("breaktbl: %d assertion(s) FAILED", fails))
  emu.stop(1)
end
