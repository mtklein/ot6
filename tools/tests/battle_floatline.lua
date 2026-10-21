-- @suite slow
-- battle_floatline.lua -- the fight driver's Float line against an earth
-- caster (#270; Driver:floatPlan, opts.floatVs).
--
-- Played: the wor_opera leg's own snapshot at the Opera House's catwalk
-- switch (wor_opera_switch; STRAGO seated, Float in his Magic list; nothing
-- here writes it).  The switch drops the party onto the Dirt Dragon (event
-- battle 134), whose spells are all earth, and the real driver fights it
-- with floatVs naming the dragon.  Asserted, reading the engine:
--   1. a Float plan is made (the line fires on the dragon's stage), its
--      caster has Float in its list, and within 900 frames of the plan every
--      living member floats (ST4 $3EF9 bit 7): the cast reached the whole
--      party (the all-allies latch), not one member;
-- then the control: the same snapshot, FLOAT_OFF set, the fight driven as
-- long as the first arm's took to float the party and 900 frames more: no
-- Float plan, and no member floats.
-- The fight is left once the read is made (the snapshot is restored); the
-- dragon's result is gen_wor_opera's and route-wor-gogo.md's matter.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local DRAGON = 0x14C
local FIGHT = { nukeLore = { 0x03, 0x04 }, floatVs = { [DRAGON] = true } }
local function map() return H.mapId() & 0x1ff end
local function floatMask()
  local m, live = 0, 0
  for e = 0, 3 do
    local hp, mx = H.readWord(0x3BF4 + e * 2), H.readWord(0x3C1C + e * 2)
    if mx > 0 and mx ~= 0xFFFF and hp > 0 then
      live = live | (1 << e)
      if (H.readByte(0x3EF9 + e * 2) & 0x80) ~= 0 then m = m | (1 << e) end
    end
  end
  return m, live
end

local snap, plan0, planAt, landed, ever, fightAt, landedIn = nil, 0, nil, nil, 0, nil, nil
-- one arm: the switch, then the driver until `stop` answers true
local function arm(what, stop)
  local drv, bn, ph, f0 = nil, 0, 0, nil
  return H.seqStep({
    H.waitUntil(function() return H.hasControl() end, 600, what .. ": control at the switch", 1),
    H.faceAndHoldA("up", function() return map() ~= 232 or H.battleLoadStarted() end, 900,
      what .. ": the catwalk's switch (232 (118,27)): face up, A"),
    H.release(),
    H.driveUntil(function() return stop(f0) end, 60000, {
      H.call(function()
        drv = drv or H.fightDriverFor("floatline", { tactical = true, boost = true, items = true, healPercent = 55 },
          FIGHT)
        ph = (ph + 1) % 8
        bn = H.battleLoadStarted() and bn + 1 or 0
        if bn >= 3 then
          f0 = f0 or H.frame
          fightAt = f0
          drv.frame()
          -- (read once the battle is armed: before that the cells hold the field's bytes)
          if H.battleActive() then ever = ever | floatMask() end
          return
        end
        if bn == 0 then drv.idle() end
        H.setPad((H.dialogWaiting() and ph < 4) and { "a" } or {})
      end),
    }, what .. ": the Dirt Dragon"),
    H.release(),
  })
end

H.run({ maxFrames = 200000 }, {
  H.loadState("build/states/wor_opera_switch.mss.lua"),
  H.call(function()
    H.assertEq(H.knowsSpell(0x07, 0x22), true, "STRAGO knows Float at the catwalk's switch (the play's own snapshot)")
    snap = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap, "the switch's snapshot"); plan0 = #(H.floats or {}) end),
  -- 1. the line
  arm("with the line", function(f0)
    local fl = H.floats or {}
    if planAt == nil and #fl > plan0 then
      planAt = H.frame
      local p = fl[plan0 + 1]
      H.log(string.format("[float] the plan: actor %d at f%d (fight frame %d), in place of its %s", p.actor, p.frame,
        p.frame - (f0 or p.frame), p.over))
    end
    if planAt then
      local m, live = floatMask()
      if landed == nil and live ~= 0 and m == live then
        landed = H.frame
        H.log(string.format("[float] every living member floats (mask $%X) %d frames after the plan", m, H.frame - planAt))
      end
      return landed ~= nil or H.frame - planAt > 900
    end
    return false
  end),
  H.call(function()
    H.assertEq(planAt ~= nil, true, "1. a Float plan on the dragon's stage")
    H.assertEq(landed ~= nil, true, "1. every living member floats within 900 frames of the plan (the whole party)")
    landedIn = landed - fightAt
  end),
  -- 2. the control
  H.call(function()
    FLOAT_OFF = true
    plan0, ever = #(H.floats or {}), 0
    snap.load = H.requestLoadState(snap.blob)
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap.load, "the switch's snapshot again") end),
  arm("with FLOAT_OFF", function(f0) return f0 ~= nil and H.frame - f0 > landedIn + 900 end),
  H.call(function()
    local n = #(H.floats or {}) - plan0
    H.log(string.format("[float] the control: %d Float plan(s), floating mask ever $%X", n, ever))
    H.assertEq(n, 0, "control: with FLOAT_OFF no Float plan")
    H.assertEq(ever, 0, "control: with FLOAT_OFF no member floats")
  end),
})
