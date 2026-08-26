-- @manual quick first-battle smoke, run by hand during battle/break bring-up
-- battle_smoke.lua -- load the captured first-battle savestate and assert
-- battle state is live.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/first_battle.mss.lua"

H.run({ maxFrames = 3600 }, {
  -- Let the machine boot a few frames before loading state on top of it.
  H.waitFrames(20),
  H.loadState(STATE),
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

    -- OT6 break system RAM readings:
    local sw, sb = {}, {}
    for i = 0, 5 do
      sw[i + 1] = string.format("%04X", H.readWord(0x3E40 + i * 2))
      sb[2 * i + 1] = string.format("%02X", H.readByte(0x3E40 + i * 2))
      sb[2 * i + 2] = string.format("%02X", H.readByte(0x3E41 + i * 2))
    end
    H.log("shield current words $7E3E40+2i: " .. table.concat(sw, " "))
    H.log("shield current bytes $7E3E40-$7E3E4B: " .. table.concat(sb, " "))

    -- at least one present monster must carry a seeded shield count
    local seeded = false
    for i = 0, 5 do
      if H.readByte(0x3AA8 + i * 2) % 2 == 1
        and H.readByte(0x3E40 + i * 2) > 0 then seeded = true end
    end
    if not seeded then
      error("no present monster carries a seeded shield count", 0)
    end
    H.log("shield seed present on a live monster")

    H.screenshot("battle_smoke")
  end),
})
