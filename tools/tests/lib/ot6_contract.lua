-- ot6_contract.lua -- the INVARIANT-CONTRACT half of the OT6 test library:
-- declared entry/exit contracts for battery-anchor boundaries (#25).
--
-- docs/design/leg-fixtures.md, "The invariant contract": parallel legs can
-- all be green while the composition is broken, because a leg run from a
-- stored anchor never sees its predecessor's output.  So every leg asserts
-- its entry invariants before doing anything, and a boundary's contract is
-- written ONCE, here, and shared -- the leg INTO a boundary asserts it as an
-- exit contract, the leg OUT OF the boundary asserts the same table as its
-- entry contract, and a mismatch is a diff between two named things rather
-- than a judgement call.
--
-- Like lib/ot6_field.lua, this file is NOT a standalone module: lib/compose.py
-- inlines it as a third chunk after the battle core and the nav half, invoking
-- it with the core's module table (the `local M = ...` below).  Scripts keep
-- their one-line `local H = dofile("tools/tests/lib/ot6.lua")` contract and
-- see ONE merged H.
--
-- A contract FAILS BY NAMING WHAT DIFFERED: every field is read, every
-- mismatch is logged as its own "CONTRACT DIFF" line (expected vs read, per
-- field), and the final error carries all of them -- one stale field and one
-- wrecked anchor both come out as a precise list, never a timeout.
--
-- What a contract can declare (all fields optional):
--   slot     = 3                          -- $021F wSaveSlotToLoad, 1..3
--   world    = { x = 137, y = 203 }       -- ON THE WORLD MAP at this tile
--   switches = { { id, 0|1, "what" }, ... }   -- story switches $1E80 bits
--   party    = { size = N,                -- COUNT of $1850 party assignments
--                members = { { charId, "NAME" }, ... } }  -- each in party 1
--   sram     = { { snesAddr, byte, "what" }, ... }  -- OT6 persistent state,
--                read via emu.memType.snesMemory (bank $31 = the codex bank)
--
-- The pre-boot half of the same design -- refusing an anchor whose
-- manifest.json persistent_layout the leg does not declare support for --
-- lives in run.sh + lib/sram_anchor.py, keyed off the leg's
-- "OT6_ANCHOR_LAYOUT:" marker comment.  This file is the in-emulator half:
-- the anchor LOADED, but its semantic content is not what the leg declared.

local M = ...
assert(type(M) == "table",
  "ot6_contract.lua is inlined by lib/compose.py after lib/ot6.lua and "
  .. "lib/ot6_field.lua; it cannot be loaded on its own")

-- ------------------------------------------------------------ the registry --

M.contracts = {}

-- post-opera-v1: the tracked battery anchor minted in #9 (world save at
-- (137,203), slot 3, party LOCKE CELES SABIN EDGAR).  Entry contract for
-- gen_vector_doorstep (leg A->B in save-points-vector.md §5); the exit
-- contract of whatever leg someday mints this anchor is THIS SAME TABLE.
--
-- THE PARTY COUNT IS THE CONTROL (#21).  The roster check used to be a log
-- line and nothing else, and that is exactly how #21 survived a release and
-- a half: the leave-Zozo `party_menu 1, NO_RESET, {LOCKE, CELES}` was
-- answered with START, the two free slots were never filled, and the whole
-- v0.5 tail plus every v0.6 leg ran two characters -- while every fixture
-- kept passing, because each was asserting story switches and map ids, and
-- a switch cannot say how many people are walking.  COUNTING the $1850
-- entries is the check that catches a chain which silently loses (or never
-- gains) a member; it lives in the anchor's contract because this boundary
-- is what every v0.6 balance number is measured across.  The canonical
-- fixture party is LOCKE CELES SABIN EDGAR (#21, 2026-07-27): slash, pierce
-- and bludgeon covered with no shop trip, SABIN answering the Vector band's
-- deliberate OT6_BLUDG row.
M.contracts["post-opera-v1"] = {
  slot = 3,                       -- Continue loaded save slot 3
  world = { x = 137, y = 203 },   -- one step WEST of the Albrook gate
  switches = {
    { 0x034b, 0, "Ultros 2 cleared" },
    { 0x005d, 1, "Setzer bargain complete" },
    { 0x005e, 1, "Blackjack arrival complete" },
    { 0x0246, 0, "Blackjack is active airship" },
    { 0x0079, 0, "CLEAR -- the Vector trigger loads map 242, not 253" },
  },
  party = {
    size = 4,                     -- the #21 control: four assignments, counted
    members = {
      { 0x01, "LOCKE" },
      { 0x06, "CELES" },
      { 0x05, "SABIN (bludgeon)" },
      { 0x04, "EDGAR (pierce+Tools)" },
    },
  },
  -- OT6 persistent state: the slot-3 codex page in SRAM bank $31
  -- (ff6/src/battle/ot6_codex.asm; page base $316800 = slot 3).  The two
  -- witnesses are the ULTROS2 rows #9 proved survive a cold Continue.
  sram = {
    { 0x316800, 0x4f, "slot 3 codex magic 'O'" },
    { 0x316801, 0x38, "slot 3 codex magic '8'" },
    { 0x316810 + 0x012d, 0x01, "bank-31 element-codex witness (ULTROS2)" },
    { 0x316990 + 0x012d, 0x01, "bank-31 class-codex witness (ULTROS2)" },
  },
}

-- ------------------------------------------------------------- the checker --

local function switchVal(id)
  return (M.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1
end

local function partyOf(charId)
  -- $1850+charId is verbbppp (ff6/notes/field-ram.txt:928); the low three
  -- bits are the party the character belongs to, 0 for nobody's.
  -- char_party writes it (field/event.asm:563-585) and RemoveChar zeroes it
  -- (battle_main.asm:11927).
  return M.readByte(0x1850 + charId) & 0x07
end

-- Read every declared field and return the list of mismatches, each already
-- formatted "label: expected X, read Y".  Reads EVERYTHING before judging,
-- so a failure names all differing fields, not just the first.
function M.contractDiffs(c)
  local diffs, held = {}, 0
  local function field(label, want, got, hex)
    local fmt = hex and function(v) return string.format("0x%02X", v) end
                     or tostring
    if got == want then
      held = held + 1
      M.log("ok: " .. label .. " = " .. fmt(got))
    else
      diffs[#diffs + 1] =
        string.format("%s: expected %s, read %s", label, fmt(want), fmt(got))
    end
  end

  if c.slot then
    field("save slot ($021F)", c.slot, M.readByte(0x021f))
  end
  if c.world then
    field("on the world map (mapId & 0x1ff)", 0, M.mapId() & 0x1ff)
    field("world x", c.world.x, M.worldX())
    field("world y", c.world.y, M.worldY())
  end
  if c.switches then
    for _, s in ipairs(c.switches) do
      field(string.format("switch $%04X (%s)", s[1], s[3]), s[2], switchVal(s[1]))
    end
  end
  if c.party then
    if c.party.size then
      local n = 0
      for charId = 0, 15 do
        if partyOf(charId) ~= 0 then n = n + 1 end
      end
      field("party size (COUNTED $1850 assignments, #21)", c.party.size, n)
    end
    if c.party.members then
      for _, m in ipairs(c.party.members) do
        field(string.format("%s (char %02X) in party", m[2], m[1]),
          1, partyOf(m[1]))
      end
    end
  end
  if c.sram then
    for _, b in ipairs(c.sram) do
      field(string.format("sram $%06X (%s)", b[1], b[3]),
        b[2], emu.read(b[1], emu.memType.snesMemory), true)
    end
  end
  return diffs, held
end

-- Assert a registered contract; `side` is "entry" or "exit", so the failure
-- says WHICH end of WHICH boundary disagreed.  All diffs are logged as their
-- own lines first (greppable one per field), then the error line repeats
-- them, so the [ot6] FAIL verdict itself names what differed.
function M.assertContract(key, side)
  local c = M.contracts[key]
  if not c then
    error("unknown contract: " .. tostring(key)
      .. " -- declare it in tools/tests/lib/ot6_contract.lua", 0)
  end
  local diffs, held = M.contractDiffs(c)
  if #diffs == 0 then
    M.log(string.format("contract %s (%s): all %d fields hold", key, side, held))
    return
  end
  for _, d in ipairs(diffs) do
    M.log("CONTRACT DIFF [" .. key .. "] " .. d)
  end
  error(string.format("contract %s (%s) VIOLATED -- %d field(s) differ: %s",
    key, side, #diffs, table.concat(diffs, "; ")), 0)
end

function M.assertEntryContract(key) M.assertContract(key, "entry") end
function M.assertExitContract(key)  M.assertContract(key, "exit")  end
