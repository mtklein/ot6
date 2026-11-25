-- @suite slow
-- battle_zinger.lua -- the fight driver's Zinger line against Wrexsoul
-- (#271; Driver:zingerPlan, ZINGER_OFF the control).
--
-- Played: the wor_doma leg's own snapshot below the dream's throne
-- (wor_doma_throne; CELES, RELM and TERRA, the arms the leg chose; nothing
-- here writes it).  The throne (126 (25,11), _cb97d6) opens event battle
-- 92: Wrexsoul and two Soul Savers.  Wrexsoul's first turn is Zinger
-- (AIScript _290): TargetEffect_3a keeps it in $33F8 and the member it
-- hides in in $33F9 (entity x 2), and only that member's fall brings it
-- back (_c207c8); the Soul Savers restore themselves when they fall.  The
-- real driver fights it.  Asserted, reading the engine:
--   1. once Wrexsoul hides, a Zinger plan is made, aimed at the member
--      $33F9 names, by another member (the host's own, which turns its heal
--      on itself into the same Fight, is not the one read);
--   2. that member falls within 19,000 frames of the hide.  The bound is set
--      from the grid on this line's snapshot (wt/v051-six-classes at
--      05150ed5, after 54143478's cure rule; build/attempts/wt/v051-six-
--      classes/labs/zgrid/, shifts 0-60 by 4, 15 distinct battle keys, both
--      arms): with the line the host fell 4,084 to 12,618 frames after the
--      hide (4,084 4,087 4,425 4,838 4,847 4,890 4,938 4,982 5,313 9,829
--      9,863 10,313 11,447 11,889 11,938 12,618; RELM as host 9,829-12,618,
--      CELES or TERRA 4,084-5,313); without it the host had not fallen
--      60,000 frames after the hide on any key.  19,000 is 1.5x the line's
--      longest.  (Earlier grids: wt/v051-tg-wob1's ten keys 4,690 to 30,132,
--      its tail the driver's cure refilling the host, which 54143478
--      stopped; eight keys 3,544 to 13,921; v0.43's 22 keys 3,764 to 6,375);
--   3. Wrexsoul is back ($33F8 cleared, its slot standing) within 600 frames
--      of the fall;
-- then the control: the same snapshot, ZINGER_OFF set, the fight driven to
-- the host's fall or 60,000 frames after the hide: no Zinger plan, and the
-- line's fall at least 40,000 frames sooner than the control's (every key's
-- gap was at least 47,382 (a control
-- with no fall counts as 60,000).  The fight is left once the read
-- is made (the snapshot is restored); its result is gen_wor_doma's and
-- route-wor-dreams.md's matter (lab x16: without the line the party fell
-- after 199,253 frames, 25 deaths and 22 raises in).
local H = dofile("tools/tests/lib/ot6.lua")

local FIGHT = {}
local function map() return H.mapId() & 0x1ff end
local function hidden() return H.readByte(0x33F8) ~= 0xFF end
local function hostOf()
  local t = H.readByte(0x33F9)
  return (t < 8 and t % 2 == 0) and t // 2 or nil
end

local snap, z0, planAt, plan, host, fellAt, backAt, fightAt, backIn, hidAt = nil, 0, nil, nil, nil, nil, nil, nil, nil, nil
local cHid, cHost, cFell = nil, nil, nil
-- one arm: up onto the throne, then the driver until `stop` answers true
local function arm(what, stop)
  local drv, bn, ph, f0 = nil, 0, 0, nil
  return H.seqStep({
    H.waitUntil(function() return H.hasControl() end, 600, what .. ": control below the throne", 1),
    H.driveUntil(function() return H.dialogWaiting() or not H.hasControl() end, 900, { H.hold({ "up" }) },
      what .. ": up onto the throne (25,11)"),
    H.release(),
    H.driveUntil(function() return stop(f0) end, 70000, {
      H.call(function()
        drv = drv or H.fightDriverFor("zinger", { tactical = true, boost = true, items = true, healPercent = 55 },
          FIGHT)
        ph = (ph + 1) % 8
        bn = H.battleLoadStarted() and bn + 1 or 0
        if bn >= 3 then
          f0 = f0 or H.frame
          fightAt = f0
          drv.frame()
          return
        end
        if bn == 0 then drv.idle() end
        H.setPad((H.dialogWaiting() and ph < 4) and { "a" } or {})
      end),
    }, what .. ": Wrexsoul"),
    H.release(),
  })
end

H.run({ maxFrames = 400000 }, {
  H.loadState("build/states/wor_doma_throne.mss.lua"),
  H.call(function()
    H.assertEq(map(), 126, "the snapshot stands in the dream's Doma (map 126)")
    H.assertEq(H.fieldX() == 25 and H.fieldY() == 12, true, "the snapshot stands below the throne (25,12)")
    snap = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap, "the throne's snapshot"); z0 = #H.zingers end),
  -- 1. the line
  arm("with the line", function(f0)
    if not H.battleActive() then return false end
    if hidAt == nil and hidden() then
      hidAt, host = H.frame, hostOf()
      H.log(string.format("[zinger] Wrexsoul hides at fight frame %d in entity %s", H.frame - (f0 or H.frame),
        tostring(host)))
    end
    local first = nil
    for i = z0 + 1, #H.zingers do if first == nil and not H.zingers[i].own then first = H.zingers[i] end end
    if planAt == nil and first ~= nil then
      planAt, plan = H.frame, first
      H.log(string.format("[zinger] the plan: actor %d on entity %d (the host read %d) at fight frame %d, in place "
        .. "of its %s", plan.actor, plan.target, plan.host, plan.frame - (f0 or plan.frame), plan.over))
    end
    if planAt and host and fellAt == nil and H.readWord(0x3BF4 + host * 2) == 0 then
      fellAt = H.frame
      H.log(string.format("[zinger] entity %d fell %d frames after the plan", host, H.frame - planAt))
    end
    if fellAt and backAt == nil and not hidden() then
      backAt = H.frame
      H.log(string.format("[zinger] Wrexsoul back %d frames after the fall", H.frame - fellAt))
    end
    return backAt ~= nil or (hidAt ~= nil and H.frame - hidAt > 19600) or (f0 ~= nil and H.frame - f0 > 50000)
  end),
  H.call(function()
    H.assertEq(planAt ~= nil, true, "1. a Zinger plan once Wrexsoul hides")
    H.assertEq(plan.target, host, "1. the plan's target is the member $33F9 names")
    H.assertEq(plan.actor ~= host, true, "1. the plan is another member's")
    H.assertEq(fellAt ~= nil and fellAt - hidAt <= 19000, true, string.format("2. the host falls within 19000 "
      .. "frames of the hide (%s)", fellAt and tostring(fellAt - hidAt) or "never"))
    H.assertEq(backAt ~= nil and backAt - fellAt <= 600, true, "3. Wrexsoul is back within 600 frames of the fall")
    backIn = backAt - fightAt
  end),
  -- 2. the control
  H.call(function()
    ZINGER_OFF = true
    z0 = #H.zingers
    snap.load = H.requestLoadState(snap.blob)
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap.load, "the throne's snapshot again") end),
  arm("with ZINGER_OFF", function(f0)
    if f0 ~= nil and H.battleActive() then
      if cHid == nil and hidden() then cHid, cHost = H.frame, hostOf() end
      if cHid and cHost and cFell == nil and H.readWord(0x3BF4 + cHost * 2) == 0 then cFell = H.frame end
    end
    return cFell ~= nil or (cHid ~= nil and H.frame - cHid > 60000) or (f0 ~= nil and H.frame - f0 > 62000)
  end),
  H.call(function()
    local n = #H.zingers - z0
    local line, ctl = fellAt - hidAt, cFell and (cFell - cHid) or 60000
    H.log(string.format("[zinger] the control: %d Zinger plan(s); its host fell %s frames after the hide (the line: "
      .. "%d)", n, cFell and tostring(cFell - cHid) or "not within 60000", line))
    H.assertEq(n, 0, "control: with ZINGER_OFF no Zinger plan")
    H.assertEq(cHid ~= nil, true, "control: Wrexsoul hides with ZINGER_OFF too")
    H.assertEq(ctl - line >= 40000, true, string.format("control: the line's fall (%d frames after the hide) is at "
      .. "least 40000 sooner than the control's (%s)", line, cFell and tostring(ctl) or "none within 60000"))
  end),
})
