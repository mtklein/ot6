-- probe_fc_escape.lua -- #132 segment 4: the 6:00 escape, from
-- fc_escape_start.mss (393 (67,16), clocks already running: master
-- timer 0 at 21600, Shadow timer 2 at 21300 -- both run in menus and
-- battles, so no dawdling and no field menus).  Route: east to Nerapa
-- at (108,15) (talk gesture -> battle 81), then past (112,15) (sets
-- $01FE) to the ledge trigger (115,17) (_ca577e, sets $01FD), answer
-- "Wait!!" (the last choice row), and idle until timer 2 fires
-- _ca57b3: Shadow arrives, $037D=1 -- the owner-canon humane wait.
-- Then absorb the exit flow (airship flees, the RUIN cutscene) as far
-- as it goes and bank the result.
local H = dofile("tools/tests/lib/ot6.lua")
local function mapIs(m) return (H.mapId() & 0x3ff) == m end
local MAG = { [0x07] = { spell = 2, boost = false } }
local FA = H.newFightDriver("escape", { tactical = true, boost = true,
  bank = 3, items = true, healPercent = 60, magic = { [0x07] = { spell = 2 } } })
local function shadowSaved() return (H.readByte(0x1EEF) >> 5) & 1 == 1 end
local function nerapaUp() return (H.readByte(0x1EEC) >> 1) & 1 == 1 end
-- absorb with choice steering to the LAST row (Wait!!) -- $056F is
-- the choice count, the last row is mx-1
local function absorb(pred, cap, tag)
  local t = 0
  return H.driveUntil(function()
    t = t + 1
    return t >= cap or pred()
  end, cap + 500, {
    H.call(function()
      if t % 2400 == 0 then
        H.log(string.format("  [%s] t=%d map=%d (%d,%d) dlg=%s", tag, t,
          H.mapId() & 0x3ff, H.fieldX(), H.fieldY(),
          tostring(H.dialogWaiting())))
      end
      if H.battleLoadStarted() or H.battleActive() then FA.frame(); return end
      local mx = H.readByte(0x056F)
      if mx > 0 then
        local want, sel, ph = mx - 1, H.readByte(0x056E), t % 24
        if sel < want then H.setPad(ph < 3 and { down = true } or {})
        elseif sel > want then H.setPad(ph < 3 and { up = true } or {})
        else H.setPad((ph >= 12 and ph < 15) and { "a" } or {}) end
        return
      end
      if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {})
      else H.setPad({}) end
    end),
  }, tag)
end
H.run({ maxFrames = 150000 }, {
  H.loadState("build/states/fc_escape_start.mss.lua"),
  H.waitFrames(30),
  H.navTo(106, 15, { maxFrames = 20000, playBattles = "tactical",
    magic = MAG }),
  -- CELES (char 7, position 2) carries the Fire Rod, which the route
  -- encounters tolerate (species $0169 absorbs ICE, not fire) but
  -- Nerapa ($0118) ABSORBS -- and Nerapa is ice-weak.  So the rod
  -- swap happens here on his doorstep, and swaps back after the win
  -- for the last legs.  Each equip menu costs ~1500 frames of the
  -- 21300-frame Shadow-timer budget; all three fit.
  H.cond(function() return H.invSlotOf(0x36) ~= nil end,
    { H.equipWeapon(2, 0x36, { tag = "CELES IceRod" }) }, {}),
  H.release(),
  H.waitFrames(30),
  -- Nerapa: face right, tap A from a standstill (the proven gesture)
  (function()
    local t = 0
    return H.driveUntil(function()
      t = t + 1
      return t >= 4000 or H.battleActive() or H.battleLoadStarted()
    end, 4500, {
      H.call(function()
        local c = t % 48
        if c < 4 then H.setPad({ right = true })
        elseif c >= 24 and c < 28 then H.setPad({ a = true })
        else H.setPad({}) end
      end),
    }, "Nerapa engaged")
  end)(),
  absorb(function()
    return not nerapaUp() and not H.battleActive()
      and not H.battleLoadStarted()
  end, 30000, "Nerapa falls ($0361 clears)"),
  H.call(function()
    H.assertEq(nerapaUp(), false, "Nerapa defeated")
    H.log(string.format("post-Nerapa: (%d,%d)", H.fieldX(), H.fieldY()))
  end),
  H.cond(function() return H.invSlotOf(0x35) ~= nil end,
    { H.equipWeapon(2, 0x35, { tag = "CELES FireRod back" }) }, {}),
  H.release(),
  H.waitFrames(30),
  H.navTo(112, 15, { maxFrames = 8000, playBattles = "tactical",
    magic = MAG }),
  -- the ledge: step onto (115,17).  The arrive latch is EXACT-tile
  -- only: adding "or not hasControl()" here once ended the navTo on a
  -- random battle load at (112,16), and the party then idled off the
  -- ledge until the master clock ran out.
  (function()
    local near = false
    return H.navTo(115, 17, { maxFrames = 8000, playBattles = "tactical",
      magic = MAG,
      arrive = function()
        if H.fieldX() == 115 and H.fieldY() == 17 then near = true end
        return near
      end })
  end)(),
  -- answer Wait!! and hold the line until Shadow arrives at 0:05.
  -- If the party is off the ledge tile with control (a battle or a
  -- re-plan drifted it), walk back -- $01FD/$01FE stay latched but
  -- the Shadow scene expects the party at the ledge.
  (function()
    local t = 0
    return H.driveUntil(function()
      t = t + 1
      return t >= 26000 or shadowSaved()
    end, 26500, {
      H.call(function()
        if t % 2400 == 0 then
          H.log(string.format(
            "  [wait] t=%d map=%d (%d,%d) dlg=%s t0=%d t2=%d", t,
            H.mapId() & 0x3ff, H.fieldX(), H.fieldY(),
            tostring(H.dialogWaiting()),
            H.readWord(0x1188), H.readWord(0x118C)))
        end
        if H.battleLoadStarted() or H.battleActive() then FA.frame(); return end
        local mx = H.readByte(0x056F)
        if mx > 0 then
          local want, sel, ph = mx - 1, H.readByte(0x056E), t % 24
          if sel < want then H.setPad(ph < 3 and { down = true } or {})
          elseif sel > want then H.setPad(ph < 3 and { up = true } or {})
          else H.setPad((ph >= 12 and ph < 15) and { "a" } or {}) end
          return
        end
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        local x, y = H.fieldX(), H.fieldY()
        if x == 115 and y == 17 then H.setPad({}); return end
        local ph = t % 24
        if ph >= 3 then H.setPad({}); return end
        if x < 115 then H.setPad({ right = true })
        elseif x > 115 then H.setPad({ left = true })
        elseif y < 17 then H.setPad({ down = true })
        else H.setPad({ up = true }) end
      end),
    }, "the humane wait ($037D)")
  end)(),
  H.call(function()
    H.assertEq(shadowSaved(), true, "$037D set -- Shadow saved")
    H.log("Shadow made the jump; absorbing the exit flow")
    H.screenshot("shadow_saved")
  end),
  -- exit: _ca48d6 -> load_map 10 -> 376 -> 390 (airship flees) -> the
  -- RUIN cutscene -> the WoR landing.  Soft cap; bank wherever it
  -- settles and report.
  absorb(function() return mapIs(397) end, 90000, "exit flow -> WoR"),
  (function()
    local t, calm = 0, 0
    return H.driveUntil(function()
      t = t + 1
      if not H.hasControl() or H.dialogWaiting() then calm = 0
      else calm = calm + 1 end
      return t >= 9000 or calm >= 240
    end, 9500, {
      H.call(function()
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "landing settled")
  end)(),
  H.call(function()
    local hp = {}
    for _, c in ipairs(H.partyMembers()) do hp[#hp+1] = H.charHp(c) end
    H.log(string.format(
      "landing: map=%d (%d,%d) party=%d hp=%s $00A4=%d $037D=%d",
      H.mapId() & 0x3ff, H.fieldX(), H.fieldY(), #H.partyMembers(),
      table.concat(hp, "/"), (H.readByte(0x1E94) >> 4) & 1,
      (H.readByte(0x1EEF) >> 5) & 1))
    H.screenshot("wor_landing")
    H.assertEq(mapIs(393), false, "left the Floating Continent")
  end),
  H.saveState("fc_wor_landing.mss"),
  H.logStep(function() return "done" end),
})
