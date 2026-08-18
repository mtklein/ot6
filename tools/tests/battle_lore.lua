-- @suite savestate=battle_entry
-- battle_lore.lua -- issue #122: Strago's 5-slot lore loadout, asserted at
-- the one choke point InitSpellList's lore walk reads (ot6_lore.asm,
-- battle_main.asm "ot6 #122").
--
-- Writes: the $1d29-2b learned-bitfield and $1e27-2b (OT6_LORELOAD) pokes
-- below are a sanctioned unit-test expedient (owner ruling) -- they set up
-- collection/loadout states (truncation past five, a stale-but-stored id) a
-- human cannot assemble on cue, and every arm reloads the fixture and lets
-- real battle init (InitSpellList) run untouched from there.
--
-- The Ochette model, third instance: LearnLore and the $1d29-$1d2b learned
-- bitfield are untouched (observation stays unlimited), and only the battle
-- Lore menu narrows.  The narrowing is a single choke point: Ot6LoreMask
-- writes an EFFECTIVE 3-byte mask to $ee/$ef/$f0, and InitSpellList's
-- vanilla lore walk (`bit $ee,x`, was `bit $1d29,x`) reads that instead of
-- the raw bitfield.  For each passing bit y (a lore id, 0..23): $3a87
-- (count) increments, $310f,y gets y+$37, and $306a,y gets y+$8b.  A
-- masked-out lore -- whether never learned, or learned but outside the
-- effective mask -- leaves both cells at whatever InitBattle's own $ff fill
-- left them ($2000-$341f, battle_main.asm InitBattle @2402), which this file
-- measures rather than assumes (arm 1 below).
--
-- MANUAL (any of the five OT6_LORELOAD bytes at $7e1e27-$1e2b nonzero): the
-- stored, still-learned ids (byte = lore id+1; validated against $1d29-2b,
-- so a stale/hand-edited slot is dropped, not offered -- arm 4).
-- AUTO (all five loadout bytes zero, the state every existing save is in):
-- the first five known lores in id order, truncating past five (arm 2), the
-- same "the wall must not be reachable through inaction" ruling kit-gau.md
-- made for Gau's rages.
--
-- What is asserted:
--   1. vanilla-equivalence: $1d29-2b pinned to the ROM's own InitLore New
--      Game values (read live via H.sym/H.readRomByte, not hardcoded), AUTO
--      loadout.  The New Game count is well under the 5-slot cap, so AUTO
--      passes every learned bit through untouched -- byte-for-byte what the
--      pre-#122 vanilla walk would have written.  This arm is also the
--      measurement: it reads back a known-clear cell to learn what value
--      InitSpellList's own clearing (the InitBattle $ff fill) leaves, and
--      every other arm's "not written" assertions check against that same
--      measured value rather than a guessed constant.
--   2. AUTO truncation: 8 lores learned (ids 0-7), AUTO loadout -> only the
--      first 5 (ids 0-4) are offered; ids 5-7, though learned, are not.
--   3. MANUAL: a 3-slot loadout {21,22,23}, all three learned -> exactly
--      those three ids offered, in the count, nothing else.
--   4. stale-byte validation: a loadout slot names a lore whose learned bit
--      is CLEAR -> that slot is skipped (dropped from the count and the
--      cells), while a co-resident valid slot still lands.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

local MENU = 0x7BCA
local LOREBITS = 0x1D29                -- learned-lore bitfield, 3 bytes ($1d29-2b)
local LORELOAD = 0x1E27                -- OT6_LORELOAD: 5 bytes, id+1, 0=unset
local LORESLOTS = 5
local COUNT = 0x3A87                   -- $3a87: how many lores passed the mask
local TBL_310F, TBL_306A = 0x310F, 0x306A  -- the two per-id list tables (y = lore id)

local INITLORE = H.sym("InitLore") & 0x3FFFFF

local function teach(ids)
  for i = 0, 2 do H.writeByte(LOREBITS + i, 0) end
  for _, id in ipairs(ids) do
    local a = LOREBITS + (id >> 3)
    H.writeByte(a, H.readByte(a) | (1 << (id & 7)))
  end
end

-- slots: an array of lore ids (nil entries and a short array leave slots unset)
local function loadout(slots)
  for i = 0, LORESLOTS - 1 do
    local v = slots and slots[i + 1]
    H.writeByte(LORELOAD + i, v and (v + 1) or 0)
  end
end

local function cellA(y) return H.readByte(TBL_310F + y) end   -- y+$37
local function cellB(y) return H.readByte(TBL_306A + y) end   -- y+$8b

-- One arm: reload the field fixture, install the save-side state, drop into
-- a battle, and read the tables InitSpellList's lore walk just built.  A
-- savestate reload per arm is the only way to re-run it, because it runs
-- exactly once, from InitBattle.
local function arm(tag, setup, check)
  return {
    H.loadState(STATE),
    H.waitFrames(10),
    H.call(function()
      H.log("---- " .. tag .. " ----")
      setup()
    end),
    H.enterEncounter(),
    H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000,
      { H.waitFrames(4) }, tag .. ": a battle menu opens"),
    H.call(check),
  }
end

local steps = {}
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end

add({ H.waitFrames(20) })

-- fill value: discovered in arm 1, then reused by every later arm's
-- "not written" assertions instead of a guessed constant.
local fillA, fillB

-- ---------------------------------------------------------------- arm 1 --
-- vanilla-equivalence + the fill measurement.  $1d29-2b pinned to the ROM's
-- own New Game InitLore bytes; AUTO loadout (all five bytes zero).
add(arm("vanilla-equivalence", function()
  local b0 = H.readRomByte(INITLORE)
  local b1 = H.readRomByte(INITLORE + 1)
  local b2 = H.readRomByte(INITLORE + 2)
  H.log(string.format("InitLore (ROM, New Game): %02x %02x %02x", b0, b1, b2))
  H.writeByte(LOREBITS, b0)
  H.writeByte(LOREBITS + 1, b1)
  H.writeByte(LOREBITS + 2, b2)
  loadout(nil)                          -- all five bytes zero = AUTO
end, function()
  local b0 = H.readRomByte(INITLORE)
  local b1 = H.readRomByte(INITLORE + 1)
  local b2 = H.readRomByte(INITLORE + 2)
  local learned, popcount = {}, 0
  for id = 0, 23 do
    local byte = (id < 8 and b0) or (id < 16 and b1) or b2
    if (byte & (1 << (id & 7))) ~= 0 then
      learned[id] = true
      popcount = popcount + 1
    end
  end
  H.assertEq(popcount <= LORESLOTS, true,
    "precondition: New Game's own lore count is within the 5-slot cap "
    .. "(" .. popcount .. " learned), so AUTO cannot truncate it -- this "
    .. "arm is a real vanilla-equivalence check, not an accidental AUTO-cap one")
  H.assertEq(H.readByte(COUNT), popcount,
    "vanilla-equivalence: $3a87 == popcount(New Game InitLore bytes)")
  -- measure the fill: the first id NOT in `learned` (New Game never learns
  -- every one of 24) tells us what InitSpellList's own clearing leaves.
  local probeId = nil
  for id = 0, 23 do
    if not learned[id] then probeId = id break end
  end
  H.assertEq(probeId ~= nil, true, "a clear id exists to measure the fill from")
  fillA, fillB = cellA(probeId), cellB(probeId)
  H.log(string.format(
    "measured fill (id %d, learned bit clear): $310f+id=$%02x $306a+id=$%02x",
    probeId, fillA, fillB))
  for id = 0, 23 do
    if learned[id] then
      H.assertEq(cellA(id), id + 0x37,
        string.format("vanilla-equivalence: learned id %d -> $310f+%d = id+$37", id, id))
      H.assertEq(cellB(id), id + 0x8b,
        string.format("vanilla-equivalence: learned id %d -> $306a+%d = id+$8b", id, id))
    else
      H.assertEq(cellA(id), fillA,
        string.format("vanilla-equivalence: unlearned id %d -> $310f+%d untouched", id, id))
      H.assertEq(cellB(id), fillB,
        string.format("vanilla-equivalence: unlearned id %d -> $306a+%d untouched", id, id))
    end
  end
  H.log("VANILLA-EQUIVALENCE: AUTO under New Game's own lore count is "
    .. "byte-for-byte the pre-#122 walk over $1d29-2b")
end))

-- ---------------------------------------------------------------- arm 2 --
-- AUTO truncation: 8 learned (ids 0..7), AUTO loadout -> only the first 5.
add(arm("auto-truncation", function()
  teach({ 0, 1, 2, 3, 4, 5, 6, 7 })
  loadout(nil)
end, function()
  H.assertEq(H.readByte(COUNT), 5, "auto-truncation: $3a87 == 5 (cap, not 8)")
  for id = 0, 4 do
    H.assertEq(cellA(id), id + 0x37,
      string.format("auto-truncation: id %d (offered) $310f cell written", id))
    H.assertEq(cellB(id), id + 0x8b,
      string.format("auto-truncation: id %d (offered) $306a cell written", id))
  end
  for id = 5, 7 do
    H.assertEq(cellA(id), fillA,
      string.format("auto-truncation: id %d (learned but past the cap) "
        .. "$310f cell NOT written", id))
    H.assertEq(cellB(id), fillB,
      string.format("auto-truncation: id %d (learned but past the cap) "
        .. "$306a cell NOT written", id))
  end
  H.log("AUTO TRUNCATION: 8 learned, 5 offered -- ids 5-7 stay learned "
    .. "(the collection) but do not reach the battle menu (the walk)")
end))

-- ---------------------------------------------------------------- arm 3 --
-- MANUAL: a 3-slot loadout {21,22,23}, all three learned.
add(arm("manual", function()
  teach({ 21, 22, 23 })
  loadout({ 21, 22, 23 })               -- stored bytes: 22,23,24
end, function()
  H.assertEq(H.readByte(COUNT), 3, "manual: $3a87 == 3")
  for _, id in ipairs({ 21, 22, 23 }) do
    H.assertEq(cellA(id), id + 0x37,
      string.format("manual: id %d $310f cell written", id))
    H.assertEq(cellB(id), id + 0x8b,
      string.format("manual: id %d $306a cell written", id))
  end
  for id = 0, 23 do
    if id ~= 21 and id ~= 22 and id ~= 23 then
      H.assertEq(cellA(id), fillA,
        string.format("manual: id %d not in the loadout -- $310f untouched", id))
      H.assertEq(cellB(id), fillB,
        string.format("manual: id %d not in the loadout -- $306a untouched", id))
    end
  end
  H.log("MANUAL: exactly the three stored, learned ids reach the walk")
end))

-- ---------------------------------------------------------------- arm 4 --
-- stale-byte validation: slot0 = id 2 (learned), slot1 = id 5 (NOT
-- learned).  MANUAL triggers off the nonzero bytes alone, but the unlearned
-- slot must be skipped: the count excludes it and its cells stay clear.
add(arm("stale-validation", function()
  teach({ 2 })                          -- only id 2 is actually learned
  loadout({ 2, 5 })                     -- slot1 names id 5, never learned
end, function()
  H.assertEq(H.readByte(COUNT), 1,
    "stale-validation: $3a87 == 1 (the stale slot is excluded from the count)")
  H.assertEq(cellA(2), 2 + 0x37, "stale-validation: id 2 (valid slot) $310f written")
  H.assertEq(cellB(2), 2 + 0x8b, "stale-validation: id 2 (valid slot) $306a written")
  H.assertEq(cellA(5), fillA,
    "stale-validation: id 5 (stored but unlearned) $310f cell NOT written")
  H.assertEq(cellB(5), fillB,
    "stale-validation: id 5 (stored but unlearned) $306a cell NOT written")
  H.log("STALE-BYTE VALIDATION: a loadout slot naming an unlearned lore is "
    .. "skipped -- a corrupt or hand-edited save cannot offer an uncastable lore")
end))

H.run({ maxFrames = 60000 }, steps)
