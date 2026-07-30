-- @suite
-- battle_entry.lua -- FAST battle-entry regression test (~30s wall clock).
--
--   tools/tests/run.sh tools/tests/battle_entry.lua
--
-- Loads build/states/battle_doorstep.mss (field, just south of the first
-- guard-battle trigger; produced by gen_battle_state.lua), walks north into
-- the battle, and passes iff the battle engine actually comes up (screen
-- rendering + battle RAM).  This is the quick iteration loop for battle/
-- break-system changes -- no 4.5-minute intro replay.
--
-- Exit codes: 0 = battle came up, 1 = battle load began but engine never
-- became active (the current break-ROM crash signature) or no doorstep
-- state exists, 2 = frame budget blown.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

H.run({ maxFrames = 8000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function() H.screenshot("entry_doorstep") end),

  -- Walk north / mash A into the scripted battle trigger.
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from doorstep"),
  H.logStep(function() return "battle load began at frame " .. H.frame end),

  H.waitUntilSoft(function() return H.battleActive() end, 900, "battle_up", 30),
  H.call(function() H.screenshot("entry_result") end),

  H.cond(function() return H.vars.battle_up end, {
    H.call(function()
      local ids = H.monsterIds()
      H.log(string.format("monster ids: %04X %04X %04X %04X %04X %04X",
        ids[1], ids[2], ids[3], ids[4], ids[5], ids[6]))
      local hp = H.partyHp()
      H.log(string.format("party battle hp: %d %d %d %d", hp[1], hp[2], hp[3], hp[4]))
      H.log(string.format("guard shields $7E3E44,$7E3E46 = %d,%d",
        H.readByte(0x3E44), H.readByte(0x3E46)))
      -- ASSERT the break system, do not merely print it.  Until 2026-07-30
      -- these three were H.log lines and nothing else, which made every
      -- reachable check in this file true of a break-system-free ROM:
      -- measured by deleting `jsl Ot6SeedShields` (battle_main.asm:7710) and
      -- rebuilding -- shields read 0,0 and this test reported PASS on a ROM
      -- where nothing in the game is breakable.  That is the exact opposite
      -- of what the header promises ("the quick iteration loop for battle/
      -- break-system changes").
      --
      -- The values are Ot6SeedShields' own output on THIS fixture's opening
      -- guard pair, and are the same ones battle_class.lua:234-240 asserts on
      -- the same battle -- 2 shields each, class row PIERCE ($02).  Kept to
      -- what the seed writes, so this stays a 2-second entry check and not a
      -- second copy of battle_class.
      H.assertEq(H.readByte(0x3E44), 2, "guard 1 shields seeded (Ot6SeedShields ran)")
      H.assertEq(H.readByte(0x3E46), 2, "guard 2 shields seeded (Ot6SeedShields ran)")
      H.assertEq(H.readByte(0x3EA8), 0x02, "guard 1 authored piercing-weak")
      H.assertEq(H.readByte(0x3EAA), 0x02, "guard 2 authored piercing-weak")
    end),
  }, {
    H.call(function()
      error("battle entry crashed: load began but battle never became active " ..
        "(see shots/entry_result.png)", 0)
    end),
  }),
})
