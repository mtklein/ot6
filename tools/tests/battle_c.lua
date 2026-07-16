-- battle_c: the Calypsi C toolchain spike, witnessed in a live battle.
-- Ot6InitBP calls the compiled-from-C leaf ot6_c_mix(3, 4) through the
-- documented ABI and publishes the result at $7e57dc. 11 there proves
-- compile -> link -> blob -> jsl -> abi -> return, end to end.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.call(function()
    H.assertEq(H.readWord(0x57dc), 11, "C function computed 3*2+4+1 in-rom")
  end),
})
