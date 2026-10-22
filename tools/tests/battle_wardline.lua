-- @suite slow
-- battle_wardline.lua -- the fight driver's ward line against a hard caster
-- (#270; Driver:buffPlan, opts.buffVs).
--
-- Played: the wor_opera leg's own snapshot at the Opera House's catwalk
-- switch (wor_opera_switch; nothing here writes it).  The switch drops the
-- party onto the Dirt Dragon (event battle 134), and the real driver fights
-- it with buffVs naming the dragon (Shell), as gen_wor_opera fights it.
-- Asserted, reading the engine:
--   a ward plan is made, and within 2400 frames its target is under Shell
--   (ST3 $3EF8 bit 5);
-- then the control: the same snapshot, BUFF_OFF set, the fight driven as
-- long as the ward took and 900 frames more: no ward plan, and that member
-- never under Shell.
-- The fight is left once the read is made (the snapshot is restored); the
-- dragon's result is gen_wor_opera's and route-wor-gogo.md's matter.
-- (The Float line this suite also checked, Driver:floatPlan, was used by no
-- leg and is gone, #460: the dragon's 50 Gs takes Float off within 400-1300
-- frames of each cast, route-wor-gogo.md section 4.)
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local DRAGON = 0x14C
local FIGHT = { nukeLore = { 0x03, 0x04 }, buffVs = { [DRAGON] = { 0x25 } } }
local function map() return H.mapId() & 0x1ff end

local snap, fightAt = nil, nil
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
        drv = drv or H.fightDriverFor("wardline", { tactical = true, boost = true, items = true, healPercent = 55 },
          FIGHT)
        ph = (ph + 1) % 8
        bn = H.battleLoadStarted() and bn + 1 or 0
        if bn >= 3 then
          f0 = f0 or H.frame
          fightAt = f0
          drv.frame()
          -- (read once the battle is armed: before that the cells hold the field's bytes)
          if H.battleActive() and wardE ~= nil and shelled(wardE) then shellEver = true end
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
  H.call(function() snap = H.requestSaveState() end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap, "the switch's snapshot"); ward0 = #(H.buffs or {}) end),
  -- 1. the ward line
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
    H.assertEq(wardAt ~= nil, true, "1. a ward plan on the dragon's stage")
    H.assertEq(warded ~= nil, true, "1. its target under Shell within 2400 frames of the plan")
    wardIn = warded - fightAt
  end),
  -- 2. the control
  H.call(function()
    BUFF_OFF = true
    ward0, shellEver = #(H.buffs or {}), false
    snap.load = H.requestLoadState(snap.blob)
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap.load, "the switch's snapshot again") end),
  arm("with BUFF_OFF", function(f0) return f0 ~= nil and H.frame - f0 > wardIn + 900 end),
  H.call(function()
    local n = #(H.buffs or {}) - ward0
    H.log(string.format("[ward] the control: %d ward plan(s); entity %d under Shell: %s", n, wardE, tostring(shellEver)))
    H.assertEq(n, 0, "control: with BUFF_OFF no ward plan")
    H.assertEq(shellEver, false, "control: with BUFF_OFF the ward's target is never under Shell")
  end),
})
