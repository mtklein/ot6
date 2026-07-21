-- gen_zozo5_ramuh.lua -- v0.4 leg 4, the arc's last: dadaluma_won (map 221,
-- the roof clear) -> the top door (33,9) -> TERRA's tower (map 226, landing
-- {82,37}) -> up to TERRA at {81,17} -> THE RAMUH SCENE -> the four
-- magicite -> the gather room -> the leave-Zozo walk-down -> $0054=1 ->
-- map 221 {57,45} -> mint zozo_done.mss, v0.4's chain tail.
--
-- THE SCENE, from source (_ca9749, event_main.asm:22965-23930):
--  * an NPC EVENT on the ESPER_TERRA NPC at {81,17} (npc_prop _226, vis
--    $0314 = set since new game): A-press activation, gated only on
--    $0053=0 (done -> _ca9d10 "TERRA...wait for us").
--  * PURE DIALOG CUTSCENE: 30+ dlg pages, obj choreography, camera work.
--    NO battle command, NO party menu, NO choice -- the issue-#3 trio's
--    dangerous members are absent; the one #3-adjacent risk is TEXT_ONLY
--    pages ($0432/$044B..$044D), IF those wait for a key without raising
--    the field dialog flags.  The driver below rides dialogWaiting like
--    every scene, PLUS a stall fallback: 600 straight frames of
--    event-running, no dialog, no position change -> unconditional
--    edge-A taps (logged loudly) until the scene moves again.
--  * scene end: $031E=0, $031F/$0320/$0321/$0322=1 (the four stones
--    appear), $0053=1, pass_on, control returns beside the bed.
--  * RAMUH's stone {84,17} -> _caa7f5: dialogs, give_genju RAMUH,
--    $031F=0, $0691=1, and the ABSENT party members' doubles spawn in
--    the gather room (vis $0323-$0328, only for chars not in the party
--    -- CYAN and GAU for this roster).
--  * SIREN {82,11} / KIRIN {81,12} / STRAY {83,12} -> _caac91/a0/af:
--    sfx, "Received the Magicite", vis-switch cleared, give_genju.
--  * the LEAVE: any gather double -> _caa890 "Everyone here?" ->
--    load_map 221 {33,6} walk-down cutscene -> the CELES/LOCKE Jidoor
--    dialog -> $0054=1 -> load_map 221 {57,45} RIGHT (:26449-:26452).
--    TERRA does NOT rejoin -- retrieved, catatonic; that is the arc.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id)
  return (H.readByte(0x1E80 + math.floor(id / 8)) >> (id % 8)) & 1
end
local function landed(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d) f%d: map=%d ctl=%s dlg=%s ev=%s (%d,%d)",
        m, H.frame, map(), tostring(H.hasControl()),
        tostring(H.dialogWaiting()), tostring(H.eventRunning()),
        H.fieldX(), H.fieldY()))
    end
    return cnt >= (n or 20)
  end
end

-- advanceStory + the TEXT_ONLY stall fallback (see header).  pred as usual;
-- when the scene holds the stage with no dialog flags and no party motion
-- for 600 straight frames, edge-tap A unconditionally until it moves.
local function rideScene(pred, maxFrames, what)
  local aPh, stallN, lx, ly, fallbacks = 0, 0, -1, -1, 0
  return H.driveUntil(function()
    local done = pred()
    if done then H.setPad({}) end
    return done
  end, maxFrames, {
    H.call(function()
      aPh = (aPh + 1) % 8
      local x, y = H.fieldX(), H.fieldY()
      local moving = (x ~= lx or y ~= ly)
      lx, ly = x, y
      if H.dialogWaiting() then
        stallN = 0
        H.setPad(aPh < 4 and { "a" } or {})
        return
      end
      if H.eventRunning() and not moving and not H.battleLoadStarted() then
        stallN = stallN + 1
      else
        stallN = 0
      end
      if stallN >= 600 then
        if stallN == 600 then
          fallbacks = fallbacks + 1
          H.log(string.format(
            "[%s] STALL at f%d (%d,%d): flag-less wait; unconditional taps (#%d)",
            what, H.frame, x, y, fallbacks))
        end
        H.setPad(aPh < 4 and { "a" } or {})
        return
      end
      H.setPad({})
    end),
  }, what)
end

-- A-press an interactable at (tx,ty) standing on (sx,sy): navTo, face,
-- clean edge-A until a dialog answers (CheckNPCs starves under held
-- directions, so the press is a pure A edge).
local function talk(sx, sy, dir, what)
  local aPh = 0
  return H.cond(function() return true end, {
    H.navTo(sx, sy, { maxFrames = 12000 }),
    H.hold({ dir }), H.waitFrames(8), H.release(), H.waitFrames(4),
    H.driveUntil(function() return H.dialogWaiting() end, 900, {
      H.call(function()
        aPh = (aPh + 1) % 12
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, what .. ": answered"),
  })
end

H.run({ maxFrames = 120000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/dadaluma_won.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 221, "booted on map 221, the roof clear")
    H.assertEq(sw(0x0053), 0, "$0053 clear -- the scene has not run")
  end),

  -- 1. the top door (33,9) -> 226 {82,37}, then up the tower to TERRA
  H.navTo(33, 10, { maxFrames = 12000 }),
  H.driveUntil(function() return map() == 226 end, 900, {
    H.hold({ "up" }), H.waitFrames(4),
  }, "into TERRA's tower"),
  H.waitUntil(landed(226, 10), 1500, "tower up", 1),
  H.waitFrames(150),

  -- 2. TERRA at {81,17}: stand at {81,18}, face up, A -> THE SCENE
  talk(81, 18, "up", "TERRA answers"),
  rideScene(function()
    return sw(0x0053) == 1 and landed(226, 30)()
  end, 40000, "the RAMUH scene"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x0053), 1, "$0053 SET -- the scene ran")
    H.assertEq(sw(0x031F), 1, "RAMUH's stone waits")
    H.log(string.format("[scene done] f%d at (%d,%d)",
      H.frame, H.fieldX(), H.fieldY()))
    H.screenshot("ramuh_scene_done")
  end),

  -- 3. RAMUH's magicite at {84,17}
  talk(84, 18, "up", "RAMUH's stone"),
  rideScene(function()
    return sw(0x0691) == 1 and landed(226, 30)()
  end, 20000, "the RAMUH grant"),
  H.call(function()
    H.assertEq(sw(0x0691), 1, "$0691 SET -- RAMUH taken")
    H.assertEq(sw(0x031F), 0, "his stone gone")
  end),

  -- 4. SIREN {82,11}, KIRIN {81,12}, STRAY {83,12}
  talk(82, 12, "up", "SIREN's stone"),
  rideScene(function() return sw(0x0320) == 0 and landed(226, 30)() end,
    9000, "SIREN taken"),
  talk(81, 13, "up", "KIRIN's stone"),
  rideScene(function() return sw(0x0321) == 0 and landed(226, 30)() end,
    9000, "KIRIN taken"),
  talk(83, 13, "up", "STRAY's stone"),
  rideScene(function() return sw(0x0322) == 0 and landed(226, 30)() end,
    9000, "STRAY taken"),
  H.call(function()
    H.log("[magicite] all four taken; down to the gather room")
    H.screenshot("magicite_taken")
  end),

  -- 5. the gather room: CYAN's double at {83,33} -> the leave walk-down
  talk(83, 34, "up", "Everyone here?"),
  rideScene(function()
    return sw(0x0054) == 1 and landed(221, 30)()
  end, 40000, "the leave-Zozo walk-down"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 221, "back on the street (map 221)")
    H.assertEq(sw(0x0054), 1, "$0054 SET -- the stop line")
    H.assertEq(sw(0x0053), 1, "$0053 still set")
    H.assertEq(sw(0x0691), 1, "RAMUH carried")
    H.log(string.format("[zozo_done] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.screenshot("zozo_done")
  end),
  H.saveState("zozo_done.mss"),
  H.logStep(function()
    return string.format(
      "zozo_done minted at frame %d -- v0.4's Zozo stop line", H.frame)
  end),
})
