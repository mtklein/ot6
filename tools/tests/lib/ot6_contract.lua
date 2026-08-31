-- ot6_contract.lua -- shared entry/exit contracts for SRAM checkpoint
-- boundaries: the step into a boundary asserts a contract as its exit
-- contract, the step out of the boundary asserts the same table as its
-- entry contract.
--
-- Like lib/ot6_field.lua, this file is not a standalone module: lib/compose.py
-- inlines it as a third chunk after the battle core and the nav half, invoking
-- it with the core's module table (the `local M = ...` below).
--
-- A contract failure names what differed: every field is read, every
-- mismatch is logged as its own "CONTRACT DIFF" line (expected vs read, per
-- field), and the final error carries all of them.
--
-- What a contract can declare (all fields optional):
--   slot     = 3                          -- SRAM $307ff0 last-saved slot, 1..3
--   world    = { x = 137, y = 203 }       -- on the world map at this tile
--   field    = { map = 270, x = 25, y = 10 }  -- on this field map at this tile
--                (a save-point boundary: where a cold Continue of the
--                boundary's checkpoint puts the party, which is the save
--                tile itself)
--   switches = { { id, 0|1, "what" }, ... }   -- story switches $1E80 bits
--   party    = { size = N,                -- count of $1850 party assignments
--                members = { { charId, "NAME" }, ... } }  -- each in party 1
--   ram      = { { addr, mask, byte, "what" }, ... }  -- masked WRAM bytes,
--                for field facts that are not switches (e.g. $1A69 espers)
--   items    = { { itemId, 0|1, "name" }, ... }  -- inventory presence
--                (1) or absence (0): the item id appears in the $1869 list
--                with a nonzero $1969 count. Checks presence rather than
--                slot position, since give_item appends to the first free
--                slot.
--   sram     = { { snesAddr, byte, "what" }, ... }  -- OT6 persistent state,
--                read via emu.memType.snesMemory (bank $31 = the codex bank)
--
-- The pre-boot half, which refuses a checkpoint whose manifest.json
-- persistent_layout the step does not declare support for, lives in
-- lib/sram_checkpoint.py, keyed off the step's "OT6_CHECKPOINT_LAYOUT:"
-- marker comment.  This file is the in-emulator half, covering the case
-- where the checkpoint loaded but its content is not what the step declared.

local M = ...
assert(type(M) == "table",
  "ot6_contract.lua is inlined by lib/compose.py after lib/ot6.lua and "
  .. "lib/ot6_field.lua; it cannot be loaded on its own")

-- ------------------------------------------------------------ the registry --

M.contracts = {}

-- post-opera-v1: world save at (137,203), slot 3, party LOCKE CELES SABIN
-- EDGAR.  Entry contract for gen_vector_entry (step A->B of the save-point
-- boundary sequence lettered in tools/tests/savestate_graph.py); the exit
-- contract of whatever step cuts this checkpoint is this same table.
--
-- Counting the $1850 entries catches a chain that loses (or never gains) a
-- member, which a story-switch or map-id check alone cannot detect.
M.contracts["post-opera-v1"] = {
  slot = 3,                       -- Continue loaded save slot 3 ($307ff0)
  world = { x = 137, y = 203 },   -- one step west of the Albrook gate
  switches = {
    { 0x034b, 0, "Ultros 2 cleared" },
    { 0x005d, 1, "Setzer bargain complete" },
    { 0x005e, 1, "Blackjack arrival complete" },
    { 0x0246, 0, "Blackjack is active airship" },
    { 0x0079, 0, "CLEAR -- the Vector trigger loads map 242, not 253" },
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
  -- OT6 persistent state: the slot-3 codex page in SRAM bank $31
  -- (ff6/src/battle/ot6_codex.asm; page base $316800 = slot 3).  The bank-31
  -- window's only nonzero bytes are the page magics; the chain has earned
  -- zero codex rows by this point.
  sram = {
    { 0x316800, 0x4f, "slot 3 codex magic 'O'" },
    { 0x316801, 0x38, "slot 3 codex magic '8'" },
    { 0x316810 + 0x012d, 0x00, "bank-31 element-codex row (ULTROS2; measured EMPTY, unseeded)" },
    { 0x316990 + 0x012d, 0x03, "bank-31 class-codex row (ULTROS2; the fighting lineage revealed slash|pierce at the Lete -- re-measured 2026-08-31)" },
  },
}

-- The Vector-area SRAM checkpoints B-E (the A-F save-point boundary sequence
-- is lettered in tools/tests/savestate_graph.py).
--  * field = the save tile itself: a cold Continue of the checkpoint puts
--    the party exactly there, and the step into the boundary walks onto the
--    same tile to assert its exit.
--  * The area's canonical four are LOCKE CELES SABIN EDGAR until the tube
--    room takes CELES ($02F6=0, event_main.asm:96157); D and E count three
--    and pin $02F6=0.
--  * ram $1A69 is the give_genju receipt (field/event.asm:3238): magicite
--    ownership is a byte rather than a switch.
--  * sram carries the same four bank-$31 checks as post-opera-v1, seeded by
--    the checkpoint generators before their real Save UI drive; a step that
--    boots from a savestate instead sees whatever codex its fixture embeds
--    (battery SRAM rides Mesen savestates; lib/ot6.lua's loadState note).
--    The pre-save exit check below (assertExitContractPreSave) is what the
--    step into a boundary uses because of that.

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
    { 0x316810 + 0x012d, 0x00, "bank-31 element-codex witness (ULTROS2; fighting lineage: no elem chip on him yet)" },
    { 0x316990 + 0x012d, 0x03, "bank-31 class-codex witness (ULTROS2; slash|pierce, revealed at the Lete and carried by the codex)" },
  },
}

M.contracts["n024-entry-save-v1"] = {
  slot = 3,
  field = { map = 273, x = 26, y = 53 },   -- save point before 024
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
    { 0x316810 + 0x012d, 0x00, "bank-31 element-codex witness (ULTROS2; fighting lineage: no elem chip on him yet)" },
    { 0x316990 + 0x012d, 0x03, "bank-31 class-codex witness (ULTROS2; slash|pierce, revealed at the Lete and carried by the codex)" },
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
    { 0x316810 + 0x012d, 0x00, "bank-31 element-codex witness (ULTROS2; fighting lineage: no elem chip on him yet)" },
    { 0x316990 + 0x012d, 0x03, "bank-31 class-codex witness (ULTROS2; slash|pierce, revealed at the Lete and carried by the codex)" },
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
    { 0x316810 + 0x012d, 0x00, "bank-31 element-codex witness (ULTROS2; fighting lineage: no elem chip on him yet)" },
    { 0x316990 + 0x012d, 0x03, "bank-31 class-codex witness (ULTROS2; slash|pierce, revealed at the Lete and carried by the codex)" },
  },
}

-- terra-returned-v1: boundary F, the v0.6 stop line (§5), a world SRAM save
-- one takeoff after Terra's return, aboard the grounded Blackjack on the
-- plain south of Zozo.  Saving from the grounded ship is legal ($0201 bit7 =
-- $80; airborne it is $00).  TERRA is available again ($02F0=1) and the
-- active party is LOCKE EDGAR SABIN SETZER.  CELES remains gone ($02F6=0)
-- until her later WoB beat.
M.contracts["terra-returned-v1"] = {
  slot = 3,
  -- Position is pinned through the module-stable save-block cells rather
  -- than worldX/worldY: this boundary's exit is asserted with the save menu
  -- still open, and the menu module overlays $e0/$e2.  $1f60/$1f61 are the
  -- world-position cells the save itself records; $1f65 bit5 is the airship
  -- flag of $1f64.
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
    { 0x316810 + 0x012d, 0x00, "bank-31 element-codex witness (ULTROS2; fighting lineage: no elem chip on him yet)" },
    { 0x316990 + 0x012d, 0x03, "bank-31 class-codex witness (ULTROS2; slash|pierce, revealed at the Lete and carried by the codex)" },
  },
}

-- ===================== the v0.7 Sealed Gate area ==========================
-- Position is pinned through $1f60/$1f61 rather than worldX/worldY.  Both
-- v0.7 boundaries are asserted as exit contracts with the save menu still
-- open, and the menu module overlays $e0/$e2.  $1f60/$1f61 are the
-- world-position cells the save block itself records, stable in every
-- module context, and a cold Continue seeds $e0/$e2 from them (world/init.asm
-- ReloadMap tail), so both ends of the boundary compare the same two bytes.

-- narshe-mission-v1: boundary G.  A world SRAM save at the Narshe exit
-- spawn, world (84,34), taken on foot with the Blackjack parked one tile
-- south at (84,36).  $0076=1: the mission meeting on map 30 has run
-- (event_main.asm:94170) and the ten Imperial-Base soldier NPCs have been
-- withdrawn ($045E-$0467=0), which opens the base entrance for step G->H.
--
-- The party is still the v0.6 four.  Terra is available ($02F0=1) but not
-- active: seating her is step G->H's first act (the Blackjack swap room).
M.contracts["narshe-mission-v1"] = {
  slot = 3,
  ram = {
    { 0x1f60, 0xFF, 84, "world x (save-block cell $1f60): the Narshe exit spawn" },
    { 0x1f61, 0xFF, 34, "world y (save-block cell $1f61)" },
    -- the parked Blackjack rides its own save cells, two south of the party
    { 0x1f62, 0xFF, 84, "parked Blackjack x (save-block cell $1f62)" },
    { 0x1f63, 0xFF, 36, "parked Blackjack y (save-block cell $1f63)" },
    { 0x11FA, 0x03, 0x00, "ON FOOT (not aboard a vehicle)" },
    { 0x11F3, 0xFF, 0x00, "not forced aboard the airship" },
    { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA magicite still owned" },
  },
  switches = {
    { 0x0076, 1, "the Narshe mission meeting has run (event_main.asm:94170)" },
    { 0x064E, 1, "the meeting-scene latch" },
    { 0x045E, 0, "the Imperial-Base soldiers were withdrawn (:94171-94180)" },
    { 0x0079, 0, "CLEAR -- the Sealed Gate scene is still ahead" },
    { 0x02F0, 1, "TERRA is available (she is seated in step G->H, not here)" },
    { 0x0070, 1, "the Blackjack party-swap room is armed" },
    { 0x02F9, 1, "SETZER is available" },
    { 0x02F6, 0, "CELES is still out of the roster" },
    { 0x007A, 0, "CLEAR -- the airship still flies" },
    { 0x0242, 0, "CLEAR -- the base entrance has not gone silent" },
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
    { 0x316810 + 0x012d, 0x00, "bank-31 element-codex witness (ULTROS2; fighting lineage: no elem chip on him yet)" },
    { 0x316990 + 0x012d, 0x03, "bank-31 class-codex witness (ULTROS2; slash|pierce, revealed at the Lete and carried by the codex)" },
  },
}

-- gate-cave-save-v1: boundary H, the vanilla save point on map 386 at
-- (74,53), the only interior save in the v0.7 area, reached off map 384
-- (64,10).  The 385 timed-floor crossing is handled by lib/ot6_field.lua's
-- M.phaseWalk (the rewrite-window mechanism).
--
-- The Imperial Base entrance refuses passage to any party without TERRA in
-- the active four (_cb25d6, event_main.asm:44004-44016) and returns it to
-- world (164,194), so the roster is asserted member by member and counted,
-- and SETZER's absence is asserted too since he is the one the swap benched.
M.contracts["gate-cave-save-v1"] = {
  slot = 3,
  field = { map = 386, x = 74, y = 53 },   -- the vanilla save point
  switches = {
    { 0x0076, 1, "the Narshe mission meeting still stands (the G->H entry)" },
    { 0x0172, 1, "the base's 'No Imperial soldiers…' beat has played" },
    { 0x0173, 1, "the (62,11) switch stands -- 384's save-room door is open" },
    { 0x0079, 0, "CLEAR -- the Sealed Gate scene is still ahead" },
    { 0x0242, 0, "CLEAR -- the base entrance has not gone silent" },
    { 0x007A, 0, "CLEAR -- the airship still flies (the crash is step H->I)" },
    { 0x02F0, 1, "TERRA is available" },
    { 0x02F6, 0, "CELES is still out of the roster" },
  },
  party = {
    size = 4,
    members = {
      { 0x00, "TERRA (the base entrance's hard gate)" },
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
    { 0x316810 + 0x012d, 0x00, "bank-31 element-codex witness (ULTROS2; fighting lineage: no elem chip on him yet)" },
    { 0x316990 + 0x012d, 0x03, "bank-31 class-codex witness (ULTROS2; slash|pierce, revealed at the Lete and carried by the codex)" },
  },
}

-- vector-crash-v1: boundary I, the crash-site world SRAM save.  The party
-- stands on the dead Blackjack's world tile (83,238), on foot, because that
-- is where the map-7 hatch (_caf4b1) drops them after the crash.
--
-- $007A=1 and $0246=0: the airship is dead, and every later step plans
-- around it.  The wreck's cells $1F62/63 still read (83,238), so the ship
-- has a position even though it cannot be flown.  The party is still the
-- gate four (TERRA LOCKE EDGAR SABIN, SETZER benched by the G->H swap):
-- battle_event $15 rewrites only the on-screen roster for the deck scene,
-- and the field party comes back intact.
M.contracts["vector-crash-v1"] = {
  slot = 3,
  ram = {
    { 0x1f60, 0xFF, 83, "world x (save-block cell $1f60): the crash site" },
    { 0x1f61, 0xFF, 238, "world y (save-block cell $1f61): on the wreck tile" },
    { 0x1f62, 0xFF, 83, "dead Blackjack x (save-block cell $1f62)" },
    { 0x1f63, 0xFF, 238, "dead Blackjack y (save-block cell $1f63)" },
    { 0x11FA, 0x03, 0x00, "ON FOOT (the wreck is scenery, not a vehicle)" },
    { 0x11F3, 0xFF, 0x00, "not forced aboard the airship" },
    { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA magicite still owned" },
  },
  switches = {
    { 0x0079, 1, "the Sealed Gate scene ran (event_main.asm:46316)" },
    { 0x0471, 1, "the gate-scene tail latch (:46313)" },
    { 0x007A, 1, "THE AIRSHIP IS DEAD (:44451) -- no step after I may fly" },
    { 0x007B, 1, "Vector's soldier machinery stands down (:44453)" },
    { 0x01BA, 1, "the crash latch (:44452)" },
    { 0x0242, 1, "the base entrance went silent forever (:44351)" },
    { 0x0246, 0, "no active airship" },
    { 0x0172, 1, "the base's no-soldiers beat stands" },
    { 0x0173, 1, "384's save-room door switch (persistent) stands" },
    { 0x0174, 1, "384's x=76 column switch (persistent) -- the traverse ran" },
    { 0x0076, 1, "the Narshe mission meeting stands" },
    { 0x02F0, 1, "TERRA is available" },
    { 0x02F6, 0, "CELES is still out of the roster" },
  },
  party = {
    size = 4,
    members = {
      { 0x00, "TERRA (still the gate four -- the deck scene never leaks)" },
      { 0x01, "LOCKE" },
      { 0x04, "EDGAR (pierce+Tools)" },
      { 0x05, "SABIN (bludgeon)" },
    },
  },
  sram = {
    { 0x316800, 0x4f, "slot 3 codex magic 'O'" },
    { 0x316801, 0x38, "slot 3 codex magic '8'" },
    { 0x316810 + 0x012d, 0x00, "bank-31 element-codex witness (ULTROS2; fighting lineage: no elem chip on him yet)" },
    { 0x316990 + 0x012d, 0x03, "bank-31 class-codex witness (ULTROS2; slash|pierce, revealed at the Lete and carried by the codex)" },
  },
}

-- banquet-done-v1: boundary J, the post-banquet world SRAM save, cut at the
-- Vector world exit's landing tile (120,188), the first world tile after the
-- banquet block.
--
-- The banquet tail forces the active party to TERRA+LOCKE and rewrites
-- availability wholesale (event_main.asm:99058-99067, :99079-99101).  The
-- >=67 tier holds across the whole playable chain from this boundary on: all
-- three reward switches pay and neither reward item does (var0 itself is
-- zeroed by the messenger), and the Doma / South Figaro world-state flips
-- carry into every later step.
M.contracts["banquet-done-v1"] = {
  slot = 3,
  ram = {
    { 0x1f60, 0xFF, 120, "world x (save-block cell $1f60): the Vector exit" },
    { 0x1f61, 0xFF, 188, "world y (save-block cell $1f61)" },
    { 0x1f62, 0xFF, 83, "dead Blackjack x -- the wreck never moves" },
    { 0x1f63, 0xFF, 238, "dead Blackjack y" },
    { 0x11FA, 0x03, 0x00, "ON FOOT" },
    { 0x11F3, 0xFF, 0x00, "not forced aboard the airship" },
    { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA magicite still owned" },
    { 0x1fc2, 0xFF, 0x00, "score var 0 lo zeroed by the messenger (:99261)" },
    { 0x1fc3, 0xFF, 0x00, "score var 0 hi zeroed" },
  },
  switches = {
    { 0x0238, 1, "the messenger paid -- the banquet block is CLOSED (:99262)" },
    { 0x007D, 1, "the banquet tail ran -- Albrook's port stands down (:99133)" },
    { 0x0276, 1, "South Figaro withdrawal (always paid)" },
    { 0x0277, 1, "Doma withdrawal (>=50 -- the tier receipt starts here)" },
    { 0x0278, 1, "Imperial-base weapons unlock (>=67)" },
    { 0x0512, 0, "cleared with the Doma withdrawal (:99228)" },
    { 0x0079, 1, "the Sealed Gate scene stands" },
    { 0x007A, 1, "the airship is still dead -- J->K is on foot and by boat" },
    { 0x007B, 1, "Vector's soldier machinery stands down" },
    { 0x0242, 1, "the base entrance is silent" },
    { 0x0246, 0, "no active airship" },
    -- the forced availability rewrite (:99058-99067), pinned wholesale
    { 0x02F0, 1, "TERRA available (forced)" },
    { 0x02F1, 1, "LOCKE available (forced)" },
    { 0x02F2, 1, "CYAN available (forced)" },
    { 0x02F4, 1, "EDGAR available (forced; benched + stripped)" },
    { 0x02F5, 1, "SABIN available (forced; benched + stripped)" },
    { 0x02F9, 1, "SETZER available (forced; benched + stripped)" },
    { 0x02F6, 0, "CELES unavailable until the Albrook pier" },
    { 0x02F3, 0, "SHADOW unavailable until the Crescent landing" },
    { 0x02F7, 0, "STRAGO unavailable" },
    { 0x02F8, 0, "RELM unavailable" },
  },
  party = {
    size = 2,
    members = {
      { 0x00, "TERRA (the envoy)" },
      { 0x01, "LOCKE (the escort)" },
    },
  },
  -- The tier is checked both ways: the >=67 tier ships, so the base-weapons
  -- unlock pays and the two higher rewards do not.
  items = {
    { 0xE5, 0, "Tintinabar -- the >=77 reward, NOT earned at this tier" },
    { 0xDF, 0, "Charm Bangle -- the >=90 reward, NOT earned at this tier" },
  },
  sram = {
    { 0x316800, 0x4f, "slot 3 codex magic 'O'" },
    { 0x316801, 0x38, "slot 3 codex magic '8'" },
    { 0x316810 + 0x012d, 0x00, "bank-31 element-codex witness (ULTROS2; fighting lineage: no elem chip on him yet)" },
    { 0x316990 + 0x012d, 0x03, "bank-31 class-codex witness (ULTROS2; slash|pierce, revealed at the Lete and carried by the codex)" },
  },
}

-- crescent-landing-v1: boundary K, a world SRAM save on the Crescent Island
-- landing tile (232,150), where the voyage's landing sail puts the party
-- (event_main.asm:69188), on foot and controllable.
--
-- SHADOW joins at the landing (`char_party SHADOW, 1` + `$02F3=1` +
-- `norm_lvl`, :69154-69163), so the roster is TERRA LOCKE SHADOW.  The
-- airship stays dead ($007A=1, $0246=0) and the wreck's save cells still
-- read the crash site.
--
-- $02FB: GAU stays available.  The port trigger's guard
-- (`set_case PARTY_CHARS`, :67906) reads the char objects' party fields
-- (EventCmd_de, ff6/src/field/event.asm:4308-4348); the banquet tail forced
-- the party to TERRA+LOCKE with `char_party GAU, 0` (:99089), and no script
-- between the banquet and the pier ever puts GAU back in party 1, so the
-- refusal at :67906 cannot fire on this chain.
M.contracts["crescent-landing-v1"] = {
  slot = 3,
  ram = {
    { 0x1f60, 0xFF, 232, "world x (save-block cell $1f60): the Crescent landing" },
    { 0x1f61, 0xFF, 150, "world y (save-block cell $1f61)" },
    { 0x1f62, 0xFF, 83, "dead Blackjack x -- the wreck never moves" },
    { 0x1f63, 0xFF, 238, "dead Blackjack y" },
    { 0x11FA, 0x03, 0x00, "ON FOOT" },
    { 0x11F3, 0xFF, 0x00, "not forced aboard the airship" },
    { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA magicite still owned" },
  },
  switches = {
    { 0x007D, 1, "the banquet tail stands -- the port opened (:99133)" },
    { 0x0083, 1, "'Right...let's go' -- the voyage began (:68379)" },
    { 0x0086, 1, "the second sail arrived (:69018)" },
    { 0x0089, 1, "Leo's split briefing was given (:69030)" },
    { 0x0087, 1, "the Albrook night was slept (:91497)" },
    { 0x0084, 1, "the night window opened (:68350; no writer ever clears it)" },
    { 0x0085, 1, "the night window opened (:68351; no writer ever clears it)" },
    { 0x0079, 1, "the Sealed Gate scene stands" },
    { 0x007A, 1, "THE AIRSHIP IS STILL DEAD -- v0.8 is on foot" },
    { 0x0246, 0, "no active airship" },
    { 0x02F3, 1, "SHADOW available -- joined at the landing (:69160)" },
    { 0x02E3, 1, "SHADOW initialized (:69158)" },
    { 0x02F6, 0, "CELES still out of the roster (no writer in the voyage)" },
    { 0x02FB, 1, "GAU still available -- the port refusal cannot fire on "
      .. "this chain (see the header note; corrects the survey)" },
    { 0x009D, 0, "the v0.8 area tail is ahead (:77992)" },
  },
  party = {
    size = 3,                     -- TERRA LOCKE SHADOW
    members = {
      { 0x00, "TERRA" },
      { 0x01, "LOCKE" },
      { 0x03, "SHADOW (joined at the landing)" },
    },
  },
  sram = {
    { 0x316800, 0x4f, "slot 3 codex magic 'O'" },
    { 0x316801, 0x38, "slot 3 codex magic '8'" },
    { 0x316810 + 0x012d, 0x00, "bank-31 element-codex witness (ULTROS2; fighting lineage: no elem chip on him yet)" },
    { 0x316990 + 0x012d, 0x03, "bank-31 class-codex witness (ULTROS2; slash|pierce, revealed at the Lete and carried by the codex)" },
  },
}

-- thamasa-night-v1: checkpoint L, a world SRAM save just outside Thamasa on
-- the same south long-entrance strip the town was entered through
-- (long_entrance.dat map-343 block, src (19,48) len 6, landing world
-- (249,128)).  NOT the Memento Ring: map 349's "upstairs" is WoR
-- Gungho/Ebot's Rock content sharing the map id, not reachable from the WoB
-- house's ground floor.
--
-- $008D=1 (Strago engaged) is set at Strago's FIRST line.  It does NOT mean
-- the scene, the fire, or the join have happened: $008E (fire) and $0090
-- (FlameEater down) are asserted clear, and the roster is unchanged from K
-- (Strago's `char_party` join is segment 3, past the burning house).
M.contracts["thamasa-night-v1"] = {
  slot = 3,
  ram = {
    -- the south exit lands the party back on the same staging tile the town
    -- was approached from (249,128), not the long_entrance.dat DestX/DestY
    -- (250,129) -- that record's dest is read at the map edge, one tile
    -- short of where a held press actually releases control on the world map.
    { 0x1f60, 0xFF, 249, "world x (save-block cell $1f60): outside Thamasa" },
    { 0x1f61, 0xFF, 128, "world y (save-block cell $1f61)" },
    { 0x1f62, 0xFF, 83, "dead Blackjack x -- the wreck never moves" },
    { 0x1f63, 0xFF, 238, "dead Blackjack y" },
    { 0x11FA, 0x03, 0x00, "ON FOOT" },
    { 0x11F3, 0xFF, 0x00, "not forced aboard the airship" },
    { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA magicite still owned" },
  },
  switches = {
    { 0x008D, 1, "Strago engaged (:69854) -- NOT scene-complete, see header" },
    { 0x008E, 0, "no fire yet (:70635)" },
    { 0x0090, 0, "FlameEater not fought (:72129)" },
    { 0x02E7, 0, "Strago not yet joined (:71796, segment 3)" },
    { 0x02F7, 0, "Strago not yet available (:71797, segment 3)" },
    { 0x007A, 1, "the airship is still dead -- v0.13 is on foot" },
    { 0x0246, 0, "no active airship" },
    { 0x02F3, 1, "SHADOW available -- unchanged since K (:69160)" },
    { 0x02E3, 1, "SHADOW initialized (:69158)" },
    { 0x02FB, 1, "GAU still available (unchanged since K)" },
    { 0x009D, 0, "the v0.13 area tail is ahead (:77992)" },
  },
  party = {
    size = 3,                     -- TERRA LOCKE SHADOW
    members = {
      { 0x00, "TERRA" },
      { 0x01, "LOCKE" },
      { 0x03, "SHADOW" },
    },
  },
  items = {
    { 0xFB, 1, "Echo Screen -- town chest bit 246" },
    { 0xF8, 1, "Green Cherry -- town chest bit 247" },
    { 0xF4, 1, "Soft -- town chest bit 248" },
    { 0xF3, 1, "Eyedrop -- town chest bit 249" },
    { 0xF0, 1, "Fenix Down -- town chest bit 250" },
  },
  sram = {
    { 0x316800, 0x4f, "slot 3 codex magic 'O'" },
    { 0x316801, 0x38, "slot 3 codex magic '8'" },
    { 0x316810 + 0x012d, 0x00, "bank-31 element-codex witness (ULTROS2; fighting lineage: no elem chip on him yet)" },
    { 0x316990 + 0x012d, 0x03, "bank-31 class-codex witness (ULTROS2; slash|pierce, revealed at the Lete and carried by the codex)" },
  },
}

-- fire-out-v1: checkpoint M, a world SRAM save outside Thamasa on the same
-- south long-entrance strip as L (world (249,128), same staging tile).
--
-- $0090/$0091/$0092: FlameEater beaten, the morning-after resolved, Shadow's
-- goodbye played.  $008D stays 1 (unchanged since L); $008E (the fire) is
-- deliberately NOT asserted either way -- town 343's burning retile is gated
-- `$008E && !$0090` (thamasa-route.md hazard 4), so once $0090=1 the raw
-- value of $008E no longer describes what the player sees.
M.contracts["fire-out-v1"] = {
  slot = 3,
  ram = {
    { 0x1f60, 0xFF, 249, "world x (save-block cell $1f60): outside Thamasa" },
    { 0x1f61, 0xFF, 128, "world y (save-block cell $1f61)" },
    { 0x1f62, 0xFF, 83, "dead Blackjack x -- the wreck never moves" },
    { 0x1f63, 0xFF, 238, "dead Blackjack y" },
    { 0x11FA, 0x03, 0x00, "ON FOOT" },
    { 0x11F3, 0xFF, 0x00, "not forced aboard the airship" },
  },
  switches = {
    { 0x008D, 1, "Strago engaged (unchanged since L)" },
    { 0x0090, 1, "FlameEater beaten (:72129)" },
    { 0x0091, 1, "the morning-after resolved (:73000)" },
    { 0x0092, 1, "Shadow's goodbye played (:73302)" },
    { 0x02E7, 1, "STRAGO joined (:71796)" },
    { 0x02F7, 1, "STRAGO available (:71797)" },
    { 0x02F3, 0, "SHADOW unavailable (left at the inn night, :70653)" },
    { 0x007A, 1, "the airship is still dead -- v0.13 is on foot" },
    { 0x0246, 0, "no active airship" },
    { 0x009D, 0, "the v0.13 area tail is ahead (:77992)" },
  },
  party = {
    size = 3,                     -- TERRA LOCKE STRAGO; SHADOW is gone
    members = {
      { 0x00, "TERRA" },
      { 0x01, "LOCKE" },
      { 0x07, "STRAGO" },
    },
  },
  items = {
    { 0xFB, 1, "Echo Screen -- town chest bit 246 (carried from L)" },
    { 0xF8, 1, "Green Cherry -- town chest bit 247 (carried from L)" },
    { 0xF4, 1, "Soft -- town chest bit 248 (carried from L)" },
    { 0xF3, 1, "Eyedrop -- town chest bit 249 (carried from L)" },
    { 0xF0, 1, "Fenix Down -- town chest bit 250 (carried from L)" },
    { 0x35, 1, "Fire Rod -- map 351 chest bit 104" },
    -- worn by STRAGO ($07), not sitting in the bag. it[4]=0x07 allows either.
    { 0x36, 1, "Ice Rod -- map 351 chest bit 105", 0x07 },
  },
  sram = {
    { 0x316800, 0x4f, "slot 3 codex magic 'O'" },
    { 0x316801, 0x38, "slot 3 codex magic '8'" },
    { 0x316810 + 0x012d, 0x00, "bank-31 element-codex witness (ULTROS2; fighting lineage: no elem chip on him yet)" },
    { 0x316990 + 0x012d, 0x03, "bank-31 class-codex witness (ULTROS2; slash|pierce, revealed at the Lete and carried by the codex)" },
  },
}

-- esper-mtn-save-v1: checkpoint N, the vanilla save point on the mountain
-- exterior at map 375 (8,44), seven tiles east of the 371 west door (2,45).
-- A FIELD save-point boundary: a cold Continue of the captured battery puts
-- the party on the save tile itself.
--
-- The roster is unchanged from M (TERRA LOCKE STRAGO; SHADOW gone), and this
-- boundary sits BEFORE the statues: $0097=0 (statue lore not seen), $0095=0
-- (Ultros III not fought), $0099=0 (the massacre chain not started).  It is
-- the last save reachable before the statue room.  $0090/$0091/$0092 carry
-- from M (FlameEater beaten, morning-after resolved, Shadow's goodbye
-- played); $0632 is the standing save-sparkle switch the 375 (8,44) sparkle
-- rides.
M.contracts["esper-mtn-save-v1"] = {
  slot = 3,
  field = { map = 375, x = 8, y = 44 },     -- the vanilla mountain save point
  switches = {
    { 0x0632, 1, "the standing save-sparkle switch (the 375 (8,44) sparkle rides it)" },
    { 0x008D, 1, "Strago engaged (unchanged since L)" },
    { 0x0090, 1, "FlameEater beaten (carried from M, :72129)" },
    { 0x0091, 1, "the morning-after resolved (carried from M, :73000)" },
    { 0x0092, 1, "Shadow's goodbye played (carried from M, :73302)" },
    { 0x0097, 0, "the statue lore is NOT seen yet (:74019) -- pre-statues" },
    { 0x0095, 0, "Ultros III is NOT fought yet (:73801)" },
    { 0x0099, 0, "the massacre chain has NOT started (:75156)" },
    { 0x02E7, 1, "STRAGO joined (:71796)" },
    { 0x02F7, 1, "STRAGO available (:71797)" },
    { 0x02F3, 0, "SHADOW unavailable (left at the inn night, :70653)" },
    { 0x02E8, 0, "RELM not joined yet (:73700, segment 5 statue room)" },
    { 0x009D, 0, "the v0.13 area tail is ahead (:77992)" },
  },
  party = {
    size = 3,                     -- TERRA LOCKE STRAGO; SHADOW is gone
    members = {
      { 0x00, "TERRA" },
      { 0x01, "LOCKE" },
      { 0x07, "STRAGO" },
    },
  },
  ram = {
    { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA magicite still owned" },
  },
  -- no chest is opened this segment, so the bag is M's, carried through.
  items = {
    { 0xF0, 1, "Fenix Down -- town chest bit 250 (carried from M)" },
    { 0x35, 1, "Fire Rod -- map 351 chest bit 104 (carried from M)" },
    { 0x36, 1, "Ice Rod -- map 351 chest bit 105 (carried from M)", 0x07 },
  },
  sram = {
    { 0x316800, 0x4f, "slot 3 codex magic 'O'" },
    { 0x316801, 0x38, "slot 3 codex magic '8'" },
    { 0x316810 + 0x012d, 0x00, "bank-31 element-codex witness (ULTROS2; fighting lineage: no elem chip on him yet)" },
    { 0x316990 + 0x012d, 0x03, "bank-31 class-codex witness (ULTROS2; slash|pierce, revealed at the Lete and carried by the codex)" },
  },
}

-- ultros-won-v1: checkpoint O, the SAME vanilla save point on the mountain
-- exterior at map 375 (8,44), on its SECOND visit -- after the statue-lore
-- scene and the Ultros III fight.
--
-- The window O lives in is narrow: $0095=1 (Ultros beaten, :73801) AND
-- $0099=0 (the massacre chain has NOT started, :75156).  O must be cut
-- between the Ultros win and the massacre trigger.  RELM is now in the party
-- ($02E8/$02F8, :73700-73701); the statue lore is seen ($0096/$0097,
-- :74018-74019); everything else carries from N.
M.contracts["ultros-won-v1"] = {
  slot = 3,
  field = { map = 375, x = 8, y = 44 },     -- the same vanilla save point
  switches = {
    { 0x0632, 1, "the standing save-sparkle switch (the 375 (8,44) sparkle rides it)" },
    { 0x008D, 1, "Strago engaged (unchanged since L)" },
    { 0x0090, 1, "FlameEater beaten (carried from M, :72129)" },
    { 0x0091, 1, "the morning-after resolved (carried from M, :73000)" },
    { 0x0092, 1, "Shadow's goodbye played (carried from M, :73302)" },
    { 0x0096, 1, "the statue lore IS seen now (:74018)" },
    { 0x0097, 1, "the statue lore IS seen now (:74019)" },
    { 0x0095, 1, "Ultros III IS beaten now (:73801)" },
    { 0x0099, 0, "the massacre chain has NOT started (:75156) -- O's window" },
    { 0x02E7, 1, "STRAGO joined (:71796)" },
    { 0x02F7, 1, "STRAGO available (:71797)" },
    { 0x02F3, 0, "SHADOW unavailable (left at the inn night, :70653)" },
    { 0x02E8, 1, "RELM joined in the Ultros scene (:73700)" },
    { 0x02F8, 1, "RELM available (:73701)" },
    { 0x009D, 0, "the v0.13 area tail is ahead (:77992)" },
  },
  party = {
    size = 4,                     -- STRAGO TERRA LOCKE RELM; SHADOW is gone
    members = {
      { 0x00, "TERRA" },
      { 0x01, "LOCKE" },
      { 0x07, "STRAGO" },
      { 0x08, "RELM" },
    },
  },
  ram = {
    { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA magicite still owned" },
  },
  -- no chest is opened this segment, so the bag is N's carried through.
  -- The Fire Rod is WORN by STRAGO ($07) in place of his Ice Rod, and the
  -- bag's spare ThunderBlade is WORN by TERRA ($00); both it[4] checks find
  -- the weapon on its wearer rather than in the $1869 bag.
  items = {
    { 0xF0, 1, "Fenix Down -- town chest bit 250 (carried from N)" },
    { 0x35, 1, "Fire Rod -- map 351 chest bit 104 (worn by STRAGO in prep)", 0x07 },
    { 0x0F, 1, "ThunderBlade -- bag spare (worn by TERRA in prep)", 0x00 },
  },
  sram = {
    { 0x316800, 0x4f, "slot 3 codex magic 'O'" },
    { 0x316801, 0x38, "slot 3 codex magic '8'" },
    { 0x316810 + 0x012d, 0x00, "bank-31 element-codex witness (ULTROS2; fighting lineage: no elem chip on him yet)" },
    { 0x316990 + 0x012d, 0x03, "bank-31 class-codex witness (ULTROS2; slash|pierce, revealed at the Lete and carried by the codex)" },
  },
}

-- thamasa-done-v1: checkpoint P, the v0.13 route TERMINAL.  Control returns
-- on the WoB world map at (249,128), one tile from the repaired Blackjack
-- (parked (249,127)).
--
-- P's window: $0099=$009B=$009C=$009D=1 (the whole massacre chain and the
-- area tail ran) with the party restored to TERRA LOCKE STRAGO RELM
-- (WEDGE/Leo out, $02F3=0 Shadow still unavailable).
M.contracts["thamasa-done-v1"] = {
  slot = 3,
  world = { x = 249, y = 128 },     -- the stop line, beside the Blackjack
  switches = {
    { 0x008D, 1, "Strago engaged (carried from O)" },
    { 0x0090, 1, "FlameEater beaten (carried, :72129)" },
    { 0x0091, 1, "the morning-after resolved (carried, :73000)" },
    { 0x0092, 1, "Shadow's goodbye played (carried, :73302)" },
    { 0x0096, 1, "the statue lore seen (carried, :74018)" },
    { 0x0097, 1, "the statue lore seen (carried, :74019)" },
    { 0x0095, 1, "Ultros III beaten (carried, :73801)" },
    { 0x0099, 1, "the massacre chain started -- back in town (:75156)" },
    { 0x018A, 1, "Kefka's Magitek entrance ran (:76337)" },
    { 0x009B, 1, "Leo fell (:76598)" },
    { 0x009C, 1, "the burial ran (:77313)" },
    { 0x009D, 1, "the v0.13 area tail ran (:77992)" },
    { 0x02E7, 1, "STRAGO joined (:71796)" },
    { 0x02F7, 1, "STRAGO available (:71797)" },
    { 0x02E8, 1, "RELM joined (:73700)" },
    { 0x02F8, 1, "RELM available (:73701)" },
    { 0x02F3, 0, "SHADOW unavailable (:70653; never restored, :77990)" },
  },
  party = {
    size = 4,                     -- TERRA LOCKE STRAGO RELM; Leo (WEDGE) is gone
    members = {
      { 0x00, "TERRA" },
      { 0x01, "LOCKE" },
      { 0x07, "STRAGO" },
      { 0x08, "RELM" },
    },
  },
  ram = {
    { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA magicite still owned" },
  },
  -- the bag carries from O across the whole massacre chain (no chest on the
  -- route -- audit_chests stays exact at 58).
  items = {
    { 0xF0, 1, "Fenix Down -- town chest bit 250 (carried from O)" },
  },
  sram = {
    { 0x316800, 0x4f, "slot 3 codex magic 'O'" },
    { 0x316801, 0x38, "slot 3 codex magic '8'" },
    { 0x316810 + 0x012d, 0x00, "bank-31 element-codex witness (ULTROS2; fighting lineage: no elem chip on him yet)" },
    { 0x316990 + 0x012d, 0x03, "bank-31 class-codex witness (ULTROS2; slash|pierce, revealed at the Lete and carried by the codex)" },
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
-- formatted "label: expected X, read Y".  Reads every field before judging,
-- so a failure names all differing fields rather than only the first.
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
    -- context.  $021f is not used: that cell is wSaveSlotToLoad only while
    -- the menu module owns the $0200 region, and the world module
    -- block-restores its own variable there after any menu closes, so a
    -- contract read through it holds only until the first menu open after
    -- boot.
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
  if c.items then
    for _, it in ipairs(c.items) do
      local have = 0
      for i = 0, 255 do
        if M.readByte(0x1869 + i) == it[1] and M.readByte(0x1969 + i) > 0 then
          have = 1
          break
        end
      end
      -- it[4], optional: a charId this item is also allowed to be WORN by
      -- rather than sitting in the bag -- a pickup a route deliberately
      -- equips (a rod on a fighter, say) is still "held", just not in the
      -- $1869 array the plain scan above reads.  Checks the character's
      -- six equip slots ($1600+37*charId+$1F..$24: w/sh/he/ar/r1/r2).
      if have == 0 and it[4] then
        local base = 0x1600 + 37 * it[4]
        for slot = 0x1F, 0x24 do
          if M.readByte(base + slot) == it[1] then have = 1; break end
        end
      end
      field(string.format("item $%02X (%s) %s inventory", it[1], it[3],
        it[2] == 1 and "in" or "NOT in"), it[2], have)
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
-- says which end of which boundary disagreed.  All diffs are logged as their
-- own lines first (one per field, greppable), then the error line repeats
-- them, so the [ot6] FAIL verdict names what differed.
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

-- The pre-save exit check, for the step into a boundary.  That step walks
-- onto the save tile and asserts the boundary table before its final
-- saveState.  The `sram` kind declares properties of the boundary save
-- itself: the bank-$31 codex row checks are what the checkpoint generator
-- seeds and the Save UI then writes into SRAM.  A savestate-booted step
-- carries its fixture's codex bytes instead (battery SRAM rides Mesen
-- savestates; lib/ot6.lua's loadState note), which need not match the
-- boundary SRAM, so the step into a boundary asserts everything else here.
-- The full table, sram included, is asserted at both real boundary moments:
-- by the checkpoint generator after its save (assertExitContract), and by
-- the step out after its cold Continue (assertEntryContract).  `slot` stays
-- in the pre-save set: $307ff0 rides Mesen savestates and proves the chain
-- descends from a slot-3 SRAM load.
function M.assertExitContractPreSave(key)
  local c, pre = lookup(key), {}
  for k, v in pairs(c) do
    if k ~= "sram" then pre[k] = v end
  end
  judge(pre, key, "exit pre-save; sram checked at the boundary save")
end
