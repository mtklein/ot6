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
--   slot     = 3                          -- SRAM $307ff0 last-saved slot, 1..3
--   world    = { x = 137, y = 203 }       -- ON THE WORLD MAP at this tile
--   field    = { map = 270, x = 25, y = 10 }  -- ON this field map at this tile
--                (a save-point boundary: where a cold Continue of the
--                boundary's anchor puts the party -- the save tile itself)
--   switches = { { id, 0|1, "what" }, ... }   -- story switches $1E80 bits
--   party    = { size = N,                -- COUNT of $1850 party assignments
--                members = { { charId, "NAME" }, ... } }  -- each in party 1
--   ram      = { { addr, mask, byte, "what" }, ... }  -- masked WRAM bytes,
--                for field facts that are not switches (e.g. $1A69 espers)
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
  slot = 3,                       -- Continue loaded save slot 3 ($307ff0)
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

-- The Vector-band battery anchors B-E (save-points-vector.md §5, issue #25).
-- Every value below is MEASURED, not derived: the boot dumps of the
-- serial-minted boundary states (ifrit_doorstep / n024_doorstep /
-- minecart_doorstep, probed 2026-07-27) and, for E, the n128_won mint log.
-- Shared shape notes:
--  * field = the save tile itself: a cold Continue of the anchor puts the
--    party exactly there, and the leg INTO the boundary walks onto the same
--    tile to assert its exit (so both ends compare the same coordinates).
--  * THE PARTY COUNT stays the #21 control at every boundary.  The band's
--    canonical four are LOCKE CELES SABIN EDGAR until the tube room takes
--    CELES ($02F6=0, event_main.asm:96157); D and E count THREE and pin
--    $02F6=0 so a chain that quietly keeps (or loses) her fails by name.
--  * ram $1A69 is the give_genju receipt (field/event.asm:3238): magicite
--    ownership is a byte, not a switch, and §5 names it load-bearing at C.
--  * sram carries the same four bank-$31 witnesses as post-opera-v1.  The
--    row witnesses exist only in a REAL battery written by the Save UI
--    (H.loadState zeroes every codex page each run -- lib/ot6.lua), which
--    is exactly what makes them anti-synthesis evidence; the pre-save exit
--    check below (assertExitContractPreSave) is what the leg INTO a
--    boundary uses because of that.

M.contracts["mrf-save-room-v1"] = {
  slot = 3,
  field = { map = 270, x = 25, y = 10 },   -- the vanilla save room off the alcove
  switches = {
    { 0x01F0, 0, "the sympathizer's distraction latch is CLEAR (§5 A->B exit)" },
    { 0x005F, 1, "Kefka's esper-drain scene has run" },
    { 0x0060, 0, "battle 70 (Ifrit/Shiva) is still ahead" },
    { 0x0646, 1, "the dying Ifrit/Shiva pair still stands on the doors" },
    { 0x0273, 0, "the alcove is not locked (post-fight latch clear)" },
    { 0x0068, 0, "the tube-room set piece is ahead" },
    { 0x0069, 0, "the factory escape has not happened" },
  },
  party = {
    size = 4,
    members = {
      { 0x01, "LOCKE" },
      { 0x06, "CELES" },
      { 0x05, "SABIN (bludgeon)" },
      { 0x04, "EDGAR (pierce+Tools)" },
    },
  },
  ram = {
    { 0x1A69, 0x07, 0x01, "RAMUH owned, IFRIT+SHIVA not yet ($1A69 & 7)" },
  },
  sram = {
    { 0x316800, 0x4f, "slot 3 codex magic 'O'" },
    { 0x316801, 0x38, "slot 3 codex magic '8'" },
    { 0x316810 + 0x012d, 0x01, "bank-31 element-codex witness (ULTROS2)" },
    { 0x316990 + 0x012d, 0x01, "bank-31 class-codex witness (ULTROS2)" },
  },
}

M.contracts["n024-doorstep-save-v1"] = {
  slot = 3,
  field = { map = 273, x = 26, y = 53 },   -- the NEW #10 save point before 024
  switches = {
    { 0x0649, 1, "NUMBER 024 still stands on {25,51} (§5 B->C exit)" },
    { 0x0060, 1, "battle 70 won" },
    { 0x0646, 0, "the dying espers are gone -- the hand-off completed" },
    { 0x0632, 1, "the standing save-sparkle switch (the 273 sparkle rides it)" },
    { 0x0068, 0, "the tube-room set piece is ahead" },
    { 0x02F6, 1, "CELES is still in the roster" },
  },
  party = {
    size = 4,
    members = {
      { 0x01, "LOCKE" },
      { 0x06, "CELES" },
      { 0x05, "SABIN (bludgeon)" },
      { 0x04, "EDGAR (pierce+Tools)" },
    },
  },
  ram = {
    { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA owned -- both magicite (§5)" },
  },
  sram = {
    { 0x316800, 0x4f, "slot 3 codex magic 'O'" },
    { 0x316801, 0x38, "slot 3 codex magic '8'" },
    { 0x316810 + 0x012d, 0x01, "bank-31 element-codex witness (ULTROS2)" },
    { 0x316990 + 0x012d, 0x01, "bank-31 class-codex witness (ULTROS2)" },
  },
}

M.contracts["minecart-platform-v1"] = {
  slot = 3,
  field = { map = 272, x = 3, y = 55 },    -- the vanilla platform save point
  switches = {
    { 0x0068, 1, "the tube-room set piece has run (§5 C->D exit)" },
    { 0x02F6, 0, "CELES left the roster in the tube room" },
    { 0x0644, 1, "CID is on the platform" },
    { 0x02BC, 0, "`cutscene TRAIN` has not run" },
    { 0x0069, 0, "the escape has not happened" },
  },
  party = {
    size = 3,                              -- the ride is three (#21; gen_n128)
    members = {
      { 0x01, "LOCKE" },
      { 0x05, "SABIN (bludgeon)" },
      { 0x04, "EDGAR (pierce+Tools)" },
    },
  },
  ram = {
    { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA still owned" },
  },
  sram = {
    { 0x316800, 0x4f, "slot 3 codex magic 'O'" },
    { 0x316801, 0x38, "slot 3 codex magic '8'" },
    { 0x316810 + 0x012d, 0x01, "bank-31 element-codex witness (ULTROS2)" },
    { 0x316990 + 0x012d, 0x01, "bank-31 class-codex witness (ULTROS2)" },
  },
}

M.contracts["vector-escape-v1"] = {
  slot = 3,
  field = { map = 240, x = 58, y = 7 },    -- the escape-map save point ($06AE)
  switches = {
    { 0x0069, 1, "the escape happened -- 262 (28,9) now exits to 240 (§5 D->E)" },
    { 0x0666, 1, "escape-scene latch" },
    { 0x06AE, 1, "the 240 (58,7) save-point sparkle is revealed" },
    { 0x006B, 0, "the Setzer reunion is still ahead" },
    { 0x02BC, 0, "`cutscene TRAIN` latch cleared by the escape" },
  },
  party = {
    size = 3,
    members = {
      { 0x01, "LOCKE" },
      { 0x05, "SABIN (bludgeon)" },
      { 0x04, "EDGAR (pierce+Tools)" },
    },
  },
  ram = {
    { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA still owned" },
  },
  sram = {
    { 0x316800, 0x4f, "slot 3 codex magic 'O'" },
    { 0x316801, 0x38, "slot 3 codex magic '8'" },
    { 0x316810 + 0x012d, 0x01, "bank-31 element-codex witness (ULTROS2)" },
    { 0x316990 + 0x012d, 0x01, "bank-31 class-codex witness (ULTROS2)" },
  },
}

-- terra-returned-v1: boundary F, the v0.6 stop line (§5) -- a world battery
-- save one takeoff after Terra's return, aboard the GROUNDED Blackjack on
-- the plain south of Zozo (the ship strafes south from the takeoff hover
-- until the live tile prop allows landing; measured 2026-07-27).  Saving
-- from the grounded ship is legal ($0201 bit7 = $80 measured; airborne it
-- is $00 -- §4.5's caveat resolved).  THE ROSTER IS THE HEADLINE: TERRA is
-- available again ($02F0=1) and the ACTIVE party is LOCKE EDGAR SABIN
-- SETZER -- the finale restores everyone who stood at the Cranes and adds
-- SETZER, so the recon §6d's "Locke and Setzer" (a two-man-chain
-- measurement) undercounts it.  CELES remains gone ($02F6=0) until her
-- later WoB beat.
M.contracts["terra-returned-v1"] = {
  slot = 3,
  -- Position is pinned through the MODULE-STABLE save-block cells, not
  -- worldX/worldY: this boundary's exit is asserted with the save menu
  -- still open (the grounded-airship world menu does not unwind on B), and
  -- the menu module overlays $e0/$e2 -- the same #29 class the slot
  -- witness already dodges.  $1f60/$1f61 are the world-position cells the
  -- save itself records; $1f65 bit5 is the airship flag of $1f64.
  ram = {
    { 0x1f60, 0xFF, 24, "world x (save-block cell $1f60): the grounded Blackjack" },
    { 0x1f61, 0xFF, 121, "world y (save-block cell $1f61): south of Zozo" },
    { 0x1f65, 0x20, 0x20, "aboard the airship ($1f64 bit13)" },
    { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA magicite still owned" },
  },
  switches = {
    { 0x02F0, 1, "TERRA is available again (the v0.6 stop line, §6b)" },
    { 0x0070, 1, "the Blackjack party-swap room is armed" },
    { 0x016F, 1, "the tutorial tail ran (event_main.asm:25671)" },
    { 0x006B, 1, "the Setzer reunion played" },
    { 0x02F9, 1, "SETZER is available" },
    { 0x02F6, 0, "CELES is still out of the roster" },
    { 0x0069, 1, "the factory escape stands" },
  },
  party = {
    size = 4,
    members = {
      { 0x01, "LOCKE" },
      { 0x04, "EDGAR (pierce+Tools)" },
      { 0x05, "SABIN (bludgeon)" },
      { 0x09, "SETZER" },
    },
  },
  sram = {
    { 0x316800, 0x4f, "slot 3 codex magic 'O'" },
    { 0x316801, 0x38, "slot 3 codex magic '8'" },
    { 0x316810 + 0x012d, 0x01, "bank-31 element-codex witness (ULTROS2)" },
    { 0x316990 + 0x012d, 0x01, "bank-31 class-codex witness (ULTROS2)" },
  },
}

-- ===================== the v0.7 Sealed Gate band (issue #31) ==============
-- docs/design/sealed-gate-recon.md §2.2 proposes anchors G-K; these are the
-- two the first slice cuts.  Every value below is MEASURED on the live
-- chain (probe_v07_f2g / probe_v07_g2h / probe_v07_385, 2026-07-28), not
-- derived from the recon's tables.
--
-- POSITION IS PINNED THROUGH $1f60/$1f61, NOT worldX/worldY.  Both v0.7
-- boundaries are asserted as EXIT contracts with the save menu still open
-- (the leg saves, then judges), and the menu module overlays $e0/$e2 -- the
-- same #29 module-overlay class the slot witness already dodges by reading
-- SRAM $307ff0 instead of $021f.  $1f60/$1f61 are the world-position cells
-- the save block itself records, stable in every module context, and a cold
-- Continue seeds $e0/$e2 from them (world/init.asm ReloadMap tail), so both
-- ends of the boundary compare the same two bytes.

-- narshe-mission-v1: boundary G.  A world battery save at the Narshe exit
-- spawn, world (84,34), taken ON FOOT with the Blackjack parked one tile
-- south at (84,36) -- the tile the leg landed on, and the tile the leg OUT
-- of G walks back onto to re-board.  $0076=1 is the whole point of the leg:
-- the mission meeting on map 30 has run (event_main.asm:94170) and the ten
-- Imperial-Base soldier NPCs have been withdrawn ($045E-$0467=0), which is
-- what opens the base entrance for leg G->H.
--
-- THE PARTY IS STILL THE v0.6 FOUR.  Terra is available ($02F0=1) but NOT
-- active: seating her is leg G->H's first act (the Blackjack swap room),
-- and the recon's §2.3 "Terra invariant" starts at anchor H, not here.  The
-- #21 count control therefore reads 4 with TERRA's party nibble ZERO -- a
-- chain that seated her early fails by name at this boundary.
M.contracts["narshe-mission-v1"] = {
  slot = 3,
  ram = {
    { 0x1f60, 0xFF, 84, "world x (save-block cell $1f60): the Narshe exit spawn" },
    { 0x1f61, 0xFF, 34, "world y (save-block cell $1f61)" },
    { 0x11FA, 0x03, 0x00, "ON FOOT (not aboard a vehicle)" },
    { 0x11F3, 0xFF, 0x00, "not forced aboard the airship" },
    { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA magicite still owned" },
  },
  switches = {
    { 0x0076, 1, "the Narshe mission meeting has run (event_main.asm:94170)" },
    { 0x064E, 1, "the meeting-scene latch" },
    { 0x045E, 0, "the Imperial-Base soldiers were withdrawn (:94171-94180)" },
    { 0x0079, 0, "CLEAR -- the Sealed Gate scene is still ahead" },
    { 0x02F0, 1, "TERRA is available (she is seated in leg G->H, not here)" },
    { 0x0070, 1, "the Blackjack party-swap room is armed" },
    { 0x02F9, 1, "SETZER is available" },
    { 0x02F6, 0, "CELES is still out of the roster" },
    { 0x007A, 0, "CLEAR -- the airship still flies" },
    { 0x0242, 0, "CLEAR -- the base entrance has not gone silent" },
  },
  party = {
    size = 4,                     -- the #21 control: still the v0.6 four
    members = {
      { 0x01, "LOCKE" },
      { 0x04, "EDGAR (pierce+Tools)" },
      { 0x05, "SABIN (bludgeon)" },
      { 0x09, "SETZER" },
    },
  },
  sram = {
    { 0x316800, 0x4f, "slot 3 codex magic 'O'" },
    { 0x316801, 0x38, "slot 3 codex magic '8'" },
    { 0x316810 + 0x012d, 0x01, "bank-31 element-codex witness (ULTROS2)" },
    { 0x316990 + 0x012d, 0x01, "bank-31 class-codex witness (ULTROS2)" },
  },
}

-- gate-cave-save-v1: boundary H, the vanilla save point on map 386 at
-- (74,53) -- the ONLY interior save in the whole v0.7 band (recon §2.1 S3),
-- reached off map 384 (64,10).  Exercised by gen_gate_cave_save
-- (2026-07-28): the 385 timed-floor crossing that blocked the first pass
-- is lib/ot6_field.lua's M.phaseWalk (the rewrite-window mechanism,
-- addenda §1.5/§1.8), and every value below was asserted at the live
-- boundary moment through the real anchored mint.
--
-- THE TERRA INVARIANT (recon §2.3) IS THIS TABLE'S REASON TO EXIST.  The
-- Imperial Base entrance refuses passage to any party without TERRA in the
-- ACTIVE four (_cb25d6, event_main.asm:44004-44016) and bounces it back to
-- world (164,194); a stale anchor minted with the wrong four would pass
-- every ordinary check and then bounce off the base on the leg out.  So the
-- roster is asserted member by member AND counted (#21), and SETZER's
-- absence is asserted too -- he is the one the swap benched, and a chain
-- that benched somebody else has a different cave kit.
M.contracts["gate-cave-save-v1"] = {
  slot = 3,
  field = { map = 386, x = 74, y = 53 },   -- the vanilla save point
  switches = {
    { 0x0076, 1, "the Narshe mission meeting still stands (the G->H entry)" },
    { 0x0172, 1, "the base's 'No Imperial soldiers…' beat has played" },
    { 0x0173, 1, "the (62,11) switch stands -- 384's save-room door is open" },
    { 0x0079, 0, "CLEAR -- the Sealed Gate scene is still ahead" },
    { 0x0242, 0, "CLEAR -- the base entrance has not gone silent" },
    { 0x007A, 0, "CLEAR -- the airship still flies (the crash is leg H->I)" },
    { 0x02F0, 1, "TERRA is available" },
    { 0x02F6, 0, "CELES is still out of the roster" },
  },
  party = {
    size = 4,
    members = {
      { 0x00, "TERRA (the base entrance's hard gate, recon §2.3)" },
      { 0x01, "LOCKE" },
      { 0x04, "EDGAR (pierce+Tools)" },
      { 0x05, "SABIN (bludgeon)" },
    },
  },
  ram = {
    { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA magicite still owned" },
  },
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
    -- $307ff0 is the SRAM last-saved-slot marker, stable in every module
    -- context.  NOT $021f: that cell is wSaveSlotToLoad only while the
    -- menu module owns the $0200 region -- the world module block-restores
    -- its own variable there after any menu closes (measured 2026-07-27,
    -- issue #29), so a contract read through it holds only until the first
    -- menu open after boot.
    field("save slot (SRAM $307ff0)", c.slot,
      emu.read(0x307ff0, emu.memType.snesMemory))
  end
  if c.world then
    field("on the world map (mapId & 0x1ff)", 0, M.mapId() & 0x1ff)
    field("world x", c.world.x, M.worldX())
    field("world y", c.world.y, M.worldY())
  end
  if c.field then
    field("field map (mapId & 0x1ff)", c.field.map, M.mapId() & 0x1ff)
    field("field x", c.field.x, M.fieldX())
    field("field y", c.field.y, M.fieldY())
  end
  if c.switches then
    for _, s in ipairs(c.switches) do
      field(string.format("switch $%04X (%s)", s[1], s[3]), s[2], switchVal(s[1]))
    end
  end
  if c.ram then
    for _, r in ipairs(c.ram) do
      field(string.format("ram $%04X & $%02X (%s)", r[1], r[2], r[4]),
        r[3], M.readByte(r[1]) & r[2], true)
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
local function judge(c, key, side)
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

local function lookup(key)
  local c = M.contracts[key]
  if not c then
    error("unknown contract: " .. tostring(key)
      .. " -- declare it in tools/tests/lib/ot6_contract.lua", 0)
  end
  return c
end

function M.assertContract(key, side) judge(lookup(key), key, side) end

function M.assertEntryContract(key) M.assertContract(key, "entry") end
function M.assertExitContract(key)  M.assertContract(key, "exit")  end

-- The PRE-SAVE exit check, for the leg INTO a boundary.  That leg walks
-- onto the save tile and asserts the boundary table BEFORE its final
-- saveState -- but the `sram` kind declares properties of the boundary
-- SAVE itself: the bank-$31 codex row witnesses exist only in a battery
-- the real Save UI has written, and H.loadState zeroes every codex page at
-- each savestate boot precisely so no run inherits one (lib/ot6.lua).  A
-- pre-save assertion of those bytes would fail in every savestate-booted
-- leg BY DESIGN, so the leg INTO a boundary asserts everything else here,
-- and the FULL table -- sram included -- is asserted at both real boundary
-- moments: by the anchor gen after its save (assertExitContract), and by
-- the leg OUT after its cold Continue (assertEntryContract).  `slot` stays
-- in the pre-save set: $307ff0 rides Mesen savestates (measured
-- 2026-07-27) and witnesses the chain descends from a slot-3 battery load.
function M.assertExitContractPreSave(key)
  local c, pre = lookup(key), {}
  for k, v in pairs(c) do
    if k ~= "sram" then pre[k] = v end
  end
  judge(pre, key, "exit pre-save; sram witnessed at the boundary save")
end
