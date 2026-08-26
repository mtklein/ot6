-- probe_massacre_climb.lua -- boot ultros-won-v1 and ASCEND from the save
-- point 375 (8,44) to the massacre trigger 375 (15,17) via the
-- $0097-shortcut + warp route:
--   save comp10 --(11,51) $0097 shortcut: retile+teleport--> 375 (39,51) comp8
--   comp8       --(45,41)--> 372 (51,17) comp22
--   372 (40,19) --> 375 (16,9) comp2 (massacre pocket)
--   walk (15,17) --> the massacre chain ($0099=1 / town 341)
-- No @suite.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function seq(steps) return H.cond(function() return true end, steps) end

local function hop(sx, sy, arriveFn, what, avoid)
  return seq({
    H.navTo(sx, sy, { maxFrames = 40000, playBattles = "flee", avoid = avoid,
      arrive = arriveFn }),
    H.release(),
    H.waitUntil(function()
      return arriveFn() and H.hasControl() and bright() >= 15
         and H.tileAligned() and not H.dialogWaiting()
    end, 6000, what, 10),
    H.waitFrames(45),
    H.call(function()
      H.log(string.format("[climb] %s -> map=%d (%d,%d) $0097=%d $0099=%d",
        what, map(), H.fieldX(), H.fieldY(), sw(0x0097), sw(0x0099)))
    end),
  })
end

H.run({ maxFrames = 400000, allowGameOver = true }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  (function() local cnt = 0
    return H.waitUntil(function()
      local ok = map() == 375 and H.tileAligned() and bright() >= 15
             and not H.dialogWaiting() and not H.battleLoadStarted()
      cnt = ok and cnt + 1 or 0
      return cnt >= 10
    end, 4000, "cold Continue to 375 save tile", 10)
  end)(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[climb] boot map=%d (%d,%d) $0097=%d $0095=%d $0099=%d",
      map(), H.fieldX(), H.fieldY(), sw(0x0097), sw(0x0095), sw(0x0099)))
  end),
  -- step off the save re-entry tile
  (function() local ph = 0
    return H.driveUntil(function()
      return H.fieldX() <= 7 and H.tileAligned() and not H.dialogWaiting()
    end, 3000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({ left = true })
      end),
    }, "step LEFT off save")
  end)(),
  H.release(),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "settled", 5),

  -- leg 1: comp10 -> comp8 via the (11,51) $0097 shortcut (teleports to (39,51))
  hop(11, 51, function() return H.fieldX() >= 30 and map() == 375 end,
    "375(11,51) shortcut -> comp8"),
  H.call(function()
    for _, c in ipairs({ { 45, 41 }, { 52, 46 } }) do
      local p = H.bfsPath(c[1], c[2])
      H.log(string.format("[climb] comp8 bfs (%d,%d): %s", c[1], c[2],
        p and (#p .. " steps") or "NO PATH"))
    end
  end),
  -- leg 2: comp8 -> 372 comp22 via 375 (45,41)
  hop(45, 41, function() return map() == 372 end, "375(45,41)->372 comp22"),
  H.call(function()
    for _, c in ipairs({ { 40, 19 }, { 39, 19 }, { 51, 17 }, { 50, 16 } }) do
      local p = H.bfsPath(c[1], c[2])
      H.log(string.format("[climb] 372 bfs (%d,%d): %s", c[1], c[2],
        p and (#p .. " steps") or "NO PATH"))
    end
  end),
  -- leg 3: 372 comp22 -> 375 comp2 via 372 (40,19)
  hop(40, 19, function() return map() == 375 end, "372(40,19)->375 comp2 POCKET"),
  H.call(function()
    H.assertEq(map(), 375, "back on 375 in the massacre pocket")
    for _, c in ipairs({ { 15, 17 }, { 15, 16 } }) do
      local p = H.bfsPath(c[1], c[2])
      H.log(string.format("[climb] comp2 bfs (%d,%d): %s", c[1], c[2],
        p and (#p .. " steps") or "NO PATH"))
    end
  end),
  H.logStep(function()
    return string.format("climb probe reached map=%d (%d,%d) $0099=%d f%d",
      map(), H.fieldX(), H.fieldY(), sw(0x0099), H.frame)
  end),
})
