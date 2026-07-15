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

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

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
      H.log(string.format("break glyph $7E3ECB = %02X", H.readByte(H.BREAK_GLYPH)))
    end),
  }, {
    H.call(function()
      error("battle entry crashed: load began but battle never became active " ..
        "(see shots/entry_result.png)", 0)
    end),
  }),
})
