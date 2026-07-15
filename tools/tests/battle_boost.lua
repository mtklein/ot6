-- battle_boost: L/R boost-select in the battle menu, end to end.
--   R raises the active character's pending boost (cap 3, never past bp),
--   L lowers it, the party-window pip cell tracks live, and the boosted
--   action consumes the points (and skips that turn's +1 regen).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"
local function pend(slot) return H.readByte(0x3e9d + slot*2) end
local function bp(slot) return H.readByte(0x3e9c + slot*2) end
local actor
H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),
  H.call(function()
    actor = H.readByte(0x62ca)
    H.log("active char slot: " .. actor)
    -- give the actor 3 bp so the cap is reachable
    H.writeByte(0x3e9c + actor*2, 3)
    H.writeWord(0x3C00, 500); H.writeWord(0x3C02, 500)
  end),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function() H.assertEq(pend(actor), 1, "R raises pending to 1") end),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function() H.assertEq(pend(actor), 3, "pending reaches 3") end),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function()
    H.assertEq(pend(actor), 3, "cap: spend at most 3 (and never past bp)")
    -- live pip cell: the pseudo-line paints spendable = 0 (3 bp - 3 pending)
    local reg = H.readByte(0x897f)
    local base = ((reg - (reg % 4)) * 256) * 2
    local row
    for r = 0, 3 do if H.readByte(0x64d6 + r) == actor then row = r end end
    local word = emu.readWord(base + (1 + row*2)*0x40 + 40, emu.memType.snesVideoRam)
    H.log(string.format("pipcur=%04x pipprev=%04x pipcell=%04x row=%d word=%04x",
      H.readWord(0x57cc), H.readWord(0x57ce), H.readWord(0x57d0), row, word))
    H.assertEq(word, 0x2172, "live pip cell shows 0 spendable")
  end),
  H.pressButtons({ "l" }, 6), H.waitFrames(20),
  H.call(function()
    H.assertEq(pend(actor), 2, "L lowers pending")
    H.screenshot("boost_selected")
  end),
  -- fire the boosted action; drive by menu state until it lands
  H.driveUntil(function() return bp(actor) ~= 3 end, 10000, {
    H.call(function() if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "boosted action lands"),
  H.call(function()
    -- 3 bp - 2 spent, no regen on a boosted turn
    H.assertEq(bp(actor), 1, "boost consumed (3-2), regen skipped")
    H.assertEq(pend(actor), 0, "pending cleared after the action")
  end),
})
