-- battle_bp.lua v2: BP verification tracking the actual active character
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"
local function bps()
  return { H.readByte(0x3E9C), H.readByte(0x3E9E), H.readByte(0x3EA0), H.readByte(0x3EA2) }
end
local actor, hp0 = 0, 0
H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(150),
  H.call(function()
    local b = bps()
    H.log(string.format("bp at start: %d %d %d %d", b[1], b[2], b[3], b[4]))
    H.assertEq(b[1], 1, "slot 0 opens with 1 bp")
    H.writeWord(0x3C00, 500)
    H.writeWord(0x3C02, 500)
    hp0 = H.readWord(0x3C00) + H.readWord(0x3C02)
    actor = H.readByte(0x62CA)   -- active character (0-3)
    H.log("active char: " .. actor)
    H.screenshot("bp_start")
  end),
  H.pressButtons({ "a" }, 6), H.waitFrames(30),
  H.pressButtons({ "a" }, 6), H.waitFrames(30),
  H.pressButtons({ "a" }, 6), H.waitFrames(600),
  H.call(function()
    local b = bps()
    local hp1 = H.readWord(0x3C00) + H.readWord(0x3C02)
    H.log(string.format("after plain beam by c%d: bp= %d %d %d %d  dmg=%d",
      actor, b[1], b[2], b[3], b[4], hp0 - hp1))
    H.assertEq(b[actor + 1], 2, "actor gained 1 bp")
    hp0 = hp1
    -- boost the NEXT actor (whoever is active now)
    actor = H.readByte(0x62CA)
    H.writeByte(0x3E9C + actor * 2, 4)
    H.writeByte(0x3E9D + actor * 2, 3)
    H.log("boosted next actor: c" .. actor)
  end),
  H.pressButtons({ "a" }, 6), H.waitFrames(30),
  H.pressButtons({ "a" }, 6), H.waitFrames(30),
  H.pressButtons({ "a" }, 6), H.waitFrames(600),
  H.call(function()
    local b = bps()
    local hp1 = H.readWord(0x3C00) + H.readWord(0x3C02)
    local dmg = hp0 - hp1
    H.log(string.format("after boosted beam by c%d: bp= %d %d %d %d  pending=%d dmg=%d",
      actor, b[1], b[2], b[3], b[4], H.readByte(0x3E9D + actor * 2), dmg))
    H.screenshot("bp_after")
    H.assertEq(b[actor + 1], 1, "boost consumed: 4 - 3 = 1, no regen")
    H.assertEq(H.readByte(0x3E9D + actor * 2), 0, "pending cleared")
    H.assertEq(dmg > 250, true, "x8 boost outsized (casters differ: terra base ~46, vicks ~130)")
  end),
})
