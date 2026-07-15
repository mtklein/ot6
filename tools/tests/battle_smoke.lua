-- battle_smoke.lua -- load the captured first-battle savestate and assert
-- battle state is live.  Run with:
--
--   tools/tests/run.sh tools/tests/battle_smoke.lua
--
-- Requires build/states/first_battle.mss.lua, produced by gen_battle_state.lua
-- (Mesen's Lua sandbox has no io library, so the state is loaded back through
-- a generated Lua sidecar rather than the raw .mss).
--
-- Exit codes: 0 = battle active with sane values, 1 = any assert failed.

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/first_battle.mss.lua"

H.run({ maxFrames = 3600 }, {
  -- Let the machine boot a few frames before loading state on top of it.
  H.waitFrames(20),
  H.call(function()
    local bytes = H.loadState(STATE)
    H.log("loaded savestate (" .. bytes .. " bytes)")
  end),
  H.waitFrames(10),

  H.call(function()
    H.assertEq(H.battleLoadStarted(), true, "battle RAM live after state load")
  end),
  H.waitUntil(function() return H.battleActive() end, 300,
    "battle to be active after state load", 10),

  H.call(function()
    local ids = H.monsterIds()
    H.log(string.format("monster ids: %04X %04X %04X %04X %04X %04X",
      ids[1], ids[2], ids[3], ids[4], ids[5], ids[6]))
    local n = H.monstersPresent()
    if n == 0 then error("no monsters present in loaded battle", 0) end
    H.log("monsters present: " .. n)

    local hp = H.partyHp()
    H.log(string.format("party battle hp: %d %d %d %d", hp[1], hp[2], hp[3], hp[4]))
    if hp[1] == 0 or hp[1] == 0xFFFF then
      error("party slot 1 battle HP looks wrong: " .. hp[1], 0)
    end

    -- OT6 break system: in battle, $7E3ECB holds a digit glyph ($B4-$BD).
    local glyph = H.readByte(H.BREAK_GLYPH)
    H.log(string.format("break glyph $7E3ECB = %02X", glyph))

    H.screenshot("battle_smoke")
  end),
})
