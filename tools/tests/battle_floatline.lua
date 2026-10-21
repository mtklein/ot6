-- @suite slow
-- battle_floatline.lua -- the fight driver's Float and ward lines against
-- an earth caster (#270; Driver:floatPlan, opts.floatVs; Driver:buffPlan,
-- opts.buffVs).
--
-- Played: the wor_opera leg's own snapshot at the Opera House's catwalk
-- switch (wor_opera_switch; STRAGO seated, Float in his Magic list; nothing
-- here writes it).  The switch drops the party onto the Dirt Dragon (event
-- battle 134), whose spells are all earth, and the real driver fights it
-- with floatVs naming the dragon.  Asserted, reading the engine:
--   1. a Float plan is made (the line fires on the dragon's stage), its
--      caster has Float in its list, and within 2400 frames of the plan
--      (the cast waits its turn in the queue: lab r2, 900 was short) every
--      living member floats (ST4 $3EF9 bit 7): the cast reached the whole
--      party (the all-allies latch), not one member;
-- then the control: the same snapshot, FLOAT_OFF set, the fight driven as
-- long as the first arm's took to float the party and 900 frames more: no
-- Float plan, and no member floats.
--   2. the ward line, from the same snapshot with buffVs naming the dragon
--      (Shell): a ward plan is made, and within 2400 frames its target is
--      under Shell (ST3 $3EF8 bit 5);
-- then its control: BUFF_OFF, the fight driven as long as the ward took and
-- 900 frames more: no ward plan, and that member never under Shell.
-- The fight is left once the read is made (the snapshot is restored); the
-- dragon's result is gen_wor_opera's and route-wor-gogo.md's matter.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local DRAGON = 0x14C
local FIGHT_FLOAT = { nukeLore = { 0x03, 0x04 }, floatVs = { [DRAGON] = true } }
local FIGHT_WARD = { nukeLore = { 0x03, 0x04 }, buffVs = { [DRAGON] = { 0x25 } } }
local FIGHT = FIGHT_FLOAT
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
local ward0, wardAt, warded, wardIn, wardE, shellEver = 0, nil, nil, nil, nil, false
local function shelled(e) return (H.readByte(0x3EF8 + e * 2) & 0x20) ~= 0 end
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
          if H.battleActive() then
            ever = ever | floatMask()
            if wardE ~= nil and shelled(wardE) then shellEver = true end
          end
          return
        end
        if bn == 0 then drv.idle() end
        H.setPad((H.dialogWaiting() and ph < 4) and { "a" } or {})
      end),
    }, what .. ": the Dirt Dragon"),
    H.release(),
  })
end

H.run({ maxFrames = 400000 }, {
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
      return landed ~= nil or H.frame - planAt > 2400
    end
    return false
  end),
  H.call(function()
    H.assertEq(planAt ~= nil, true, "1. a Float plan on the dragon's stage")
    H.assertEq(landed ~= nil, true, "1. every living member floats within 2400 frames of the plan (the whole party)")
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
  -- 3. the ward line
  H.call(function()
    FIGHT = FIGHT_WARD
    ward0 = #(H.buffs or {})
    snap.load = H.requestLoadState(snap.blob)
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap.load, "the switch's snapshot, a third time") end),
  arm("with the ward line", function(f0)
    local bl = H.buffs or {}
    if wardAt == nil and #bl > ward0 then
      local b = bl[ward0 + 1]
      wardAt, wardE = H.frame, b.target
      H.log(string.format("[ward] the plan: actor %d, spell $%02X on entity %d at fight frame %d", b.actor, b.spell,
        b.target, b.frame - (f0 or b.frame)))
    end
    if wardAt then
      if warded == nil and shelled(wardE) then
        warded = H.frame
        H.log(string.format("[ward] entity %d under Shell %d frames after the plan", wardE, H.frame - wardAt))
      end
      return warded ~= nil or H.frame - wardAt > 2400
    end
    return false
  end),
  H.call(function()
    H.assertEq(wardAt ~= nil, true, "2. a ward plan on the dragon's stage")
    H.assertEq(warded ~= nil, true, "2. its target under Shell within 2400 frames of the plan")
    wardIn = warded - fightAt
  end),
  -- 4. its control
  H.call(function()
    BUFF_OFF = true
    ward0, shellEver = #(H.buffs or {}), false
    snap.load = H.requestLoadState(snap.blob)
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap.load, "the switch's snapshot, a fourth time") end),
  arm("with BUFF_OFF", function(f0) return f0 ~= nil and H.frame - f0 > wardIn + 900 end),
  H.call(function()
    local n = #(H.buffs or {}) - ward0
    H.log(string.format("[ward] the control: %d ward plan(s); entity %d under Shell: %s", n, wardE, tostring(shellEver)))
    H.assertEq(n, 0, "control: with BUFF_OFF no ward plan")
    H.assertEq(shellEver, false, "control: with BUFF_OFF the ward's target is never under Shell")
  end),
})
