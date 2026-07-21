-- gen_zozo5_ramuh.lua -- v0.4 leg 4, the arc's last: dadaluma_won (map 221,
-- the roof clear) -> the top door (33,9) -> TERRA's tower (map 226, landing
-- {82,37}) -> up to TERRA at {81,17} -> THE RAMUH SCENE -> the four
-- magicite -> the gather room -> the leave-Zozo walk-down -> $0054=1 ->
-- map 221 {57,45} -> mint zozo_done.mss, v0.4's chain tail.
--
-- Everything below was MEASURED end to end (probe_ramuh/tower3/gather/leave),
-- not predicted.  Four surprises the predecessor's source-read missed:
--
--  1. THE TOWER PORCH ROLLS RANDOM ENCOUNTERS.  The (33,10)->(33,9) door
--     leg fired battle 19-class trash on the first run (event PC parked at
--     $CA0029 = RandBattle).  Every player-controlled drive kill-bits a
--     stray before its own work.
--  2. TERRA IS TALKED FROM THE WEST, not below.  Her tile {81,17} is
--     z=UPPER ($0888=1, prop $01); {81,18} below is z=LOWER ($0A), and
--     CheckNPCs' z-match (player.asm @477c) rejects a lower-z party
--     reaching an upper-z NPC.  Stand on the both-z tile {80,17} ($0B)
--     and face RIGHT.
--  3. THE RAMUH SCENE (_ca9749) IS pure dialog -- the prediction held: 30+
--     pages, obj/camera choreography, NO battle/menu/choice.  BUT its
--     TEXT_ONLY pages ($0432/$044A-$044D) park the event PC in a WRAM
--     MIRROR ($80xxxx) that eventRunning() reads as "not an event", so the
--     original stall fallback (gated on eventRunning, 600 frames) never
--     fired and the scene hung at 40000 frames.  rideScene now gates the
--     stall counter on hasControl() instead (the party is event-controlled
--     the whole cutscene, so it can never spuriously tap a field NPC) at a
--     180-frame threshold.  End: $031F/$0320/$0321/$0322=1 (four stones),
--     $0053=1, control returns on map 226.
--  4. THE MAGICITE stones' COLLISION TILES sit ONE ROW BELOW their NPC
--     prop coords: SIREN {82,11}->{82,12}, KIRIN {81,12}->{81,13}, STRAY
--     {83,12}->{83,13}.  They wall the chamber mouth and are all bumped
--     from the single floor tile {82,13} (up/left/right).  RAMUH's stone
--     {84,17} -> _caa7f5 grants RAMUH ($031F=0, $0691=1) and spawns the
--     absent members' gather doubles (CYAN/GAU here).  Each of
--     _caac91/a0/af clears its own vis switch + give_genju.
--  5. THE LEAVE (_caa890, bumped via CYAN's double {83,33} from {83,34})
--     is NOT pure dialog: it pins LOCKE (the tracked leader) in place while
--     the others walk (so rideScene's leader-stall heuristic misfires and
--     wedges it), AND runs a party_menu 1 NO_RESET {LOCKE,CELES} -- a
--     forced-member confirm menu needing START.  It gets its own driver:
--     dialog->A, menu->START, else hands off.  End: the CELES/LOCKE Jidoor
--     dialog -> $0054=1 -> load_map 221 {57,45} RIGHT (:26449-:26452).
--     TERRA does NOT rejoin -- retrieved, catatonic; that is the arc.
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

-- Zozo rolls RANDOM ENCOUNTERS even on the tower porch (measured: the
-- first run of this generator froze at (33,10) with the event PC parked
-- at $CA0029 -- inside RandBattle, right after its rand_battle command --
-- while a battle-blind hold-up drive pressed into the transition for 900
-- frames).  Every drive here that runs under player control clears a
-- stray battle with the kill-bit idiom before doing its own work.
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

-- advanceStory + the TEXT_ONLY stall fallback.  pred as usual; when the
-- scene holds the stage with no dialog flags and no party motion, edge-tap
-- A to advance the flag-less page.
--
-- The stall detector deliberately does NOT gate on eventRunning() -- that
-- was the original bug (measured, probe_ramuh f7208..f13400).  The scene's
-- TEXT_ONLY pages ($0432/$044A-$044D) park the event PC in a WRAM-MIRROR
-- object-script address ($80xxxx) while they wait, and eventRunning() reads
-- $80xxxx as "not an event" -- so an eventRunning-gated counter resets every
-- one of those frames and never taps, hanging the whole scene (the generator
-- timed out at 40000 frames doing exactly this).  The safe guard is
-- hasControl(): the party is event-controlled the entire cutscene (movement
-- type 4, never 2), so hasControl() is false throughout and a stall-tap can
-- only feed the scene -- it can never talk to a field NPC.  The threshold is
-- 180 frames of a stable leader position with no dialog and no field control.
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
      if H.battleLoadStarted() then
        killBitAll()
        stallN = 0
        H.setPad(aPh < 4 and { "a" } or {})
        return
      end
      if H.dialogWaiting() then
        stallN = 0
        H.setPad(aPh < 4 and { "a" } or {})
        return
      end
      -- not moving, no dialog, no field control -> a flag-less scene wait
      if not moving and not H.hasControl() then
        stallN = stallN + 1
      else
        stallN = 0
      end
      if stallN >= 180 then
        if stallN == 180 then
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
    H.driveUntil(function() return H.dialogWaiting() end, 1800, {
      H.call(function()
        aPh = (aPh + 1) % 12
        if H.battleLoadStarted() then
          killBitAll()
          H.setPad(aPh < 4 and { "a" } or {})
          return
        end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, what .. ": answered"),
  })
end

-- Walk INTO a collision-activated object from an approach tile: navTo the
-- approach tile (sx,sy), then alternate HOLDING the bump direction (the
-- event fires on the bump against the solid object) with an A edge (the
-- backup for react NPCs) until a dialog answers.  The three magicite stones
-- and the gather double activate on collision, and their collision tiles
-- sit ONE ROW below the NPC prop coords (measured, probe_gather): SIREN
-- (82,11)->(82,12), KIRIN (81,12)->(81,13), STRAY (83,12)->(83,13), all
-- reached from the single approach tile (82,13) -- up/left/right.
local function bumpTake(sx, sy, dir, what)
  local ph = 0
  return H.cond(function() return true end, {
    H.navTo(sx, sy, { maxFrames = 12000 }),
    H.driveUntil(function() return H.dialogWaiting() end, 1800, {
      H.call(function()
        ph = (ph + 1) % 16
        if H.battleLoadStarted() then killBitAll() end
        if ph < 8 then H.setPad({ [dir] = true })
        elseif ph < 12 then H.setPad({ "a" })
        else H.setPad({}) end
      end),
    }, what .. ": bumped"),
  })
end

H.run({ maxFrames = 120000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/dadaluma_won.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 221, "booted on map 221, the roof clear")
    H.assertEq(sw(0x0053), 0, "$0053 clear -- the scene has not run")
  end),

  -- 1. the top door (33,9) -> 226 {82,37}, then up the tower to TERRA.
  --    Battle-aware: the porch encounter (see killBitAll's note) fired
  --    exactly here on the first run.
  H.navTo(33, 10, { maxFrames = 12000 }),
  (function()
    local ph = 0
    return H.driveUntil(function() return map() == 226 end, 3000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.battleLoadStarted() then
          killBitAll()
          H.setPad(ph < 4 and { "a" } or {})
          return
        end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({ up = true })
      end),
    }, "into TERRA's tower")
  end)(),
  H.waitUntil(landed(226, 10), 1500, "tower up", 1),
  H.waitFrames(150),

  -- 2. TERRA at {81,17}: stand at {80,17} and face EAST, not {81,18}
  --    facing up.  Her tile (81,17) is z=UPPER ($0888=1, prop $01) but
  --    (81,18) below her is a z=LOWER tile ($0A): CheckNPCs' z-match
  --    (player.asm @477c) rejects a lower-z party reaching an upper-z NPC,
  --    so the south approach never activates (measured, probe_tower3:
  --    dlg=false from (81,18), dlg=true from the (80,17) both-z tile $0B).
  -- The ride terminates on the scene's own COMPLETION SWITCH, not on
  -- switch-AND-landed: rideScene releases the pad the instant its pred is
  -- true, so gating on the bare switch stops the stall-tapper exactly at
  -- scene end.  The earlier switch-AND-landed pred kept A hammering through
  -- the wrap-up frames after $0053=1 and walked the party straight into
  -- RAMUH's stone dialog, desyncing the explicit talk() steps below (the
  -- 40000-frame timeout).  Control settles in a separate landed() wait --
  -- measured clean on map 226 within ~300 frames of $0053 (probe_ramuh).
  talk(80, 17, "right", "TERRA answers"),
  rideScene(function() return sw(0x0053) == 1 end, 40000, "the RAMUH scene"),
  H.waitUntil(landed(226, 20), 3000, "control after the scene", 5),
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
  rideScene(function() return sw(0x0691) == 1 end, 20000, "the RAMUH grant"),
  H.waitUntil(landed(226, 20), 3000, "control after RAMUH", 5),
  H.call(function()
    H.assertEq(sw(0x0691), 1, "$0691 SET -- RAMUH taken")
    H.assertEq(sw(0x031F), 0, "his stone gone")
  end),

  -- 4. SIREN/KIRIN/STRAY.  Their collision tiles are (82,12)/(81,13)/
  --    (83,13) -- one row below the NPC prop coords -- and form a barrier
  --    across the chamber mouth, all reached from the single floor tile
  --    (82,13): up into SIREN, left into KIRIN, right into STRAY (measured,
  --    probe_gather2).  Each grant clears the stone's own vis switch.
  bumpTake(82, 13, "up", "SIREN's stone"),
  rideScene(function() return sw(0x0320) == 0 end, 9000, "SIREN taken"),
  H.waitUntil(landed(226, 15), 3000, "control after SIREN", 5),
  bumpTake(82, 13, "left", "KIRIN's stone"),
  rideScene(function() return sw(0x0321) == 0 end, 9000, "KIRIN taken"),
  H.waitUntil(landed(226, 15), 3000, "control after KIRIN", 5),
  bumpTake(82, 13, "right", "STRAY's stone"),
  rideScene(function() return sw(0x0322) == 0 end, 9000, "STRAY taken"),
  H.waitUntil(landed(226, 15), 3000, "control after STRAY", 5),
  H.call(function()
    H.log("[magicite] all four taken; down to the gather room")
    H.screenshot("magicite_taken")
  end),

  -- 5. the gather room: bump CYAN's double (collision tile {83,33}, from
  --    {83,34}) to fire the leave cutscene _caa890.  That cutscene is NOT
  --    pure dialog: it pins LOCKE (the tracked leader) in place while the
  --    others walk, so rideScene's leader-stall heuristic misfires and
  --    hammers A (measured: it wedges the scene).  It also runs a
  --    party_menu 1 NO_RESET {LOCKE,CELES} -- a forced-member confirm menu
  --    that needs START, not A.  So the leave gets its own driver:
  --    dialogWaiting -> edge-A (the BOTTOM Jidoor dialogs), menu up -> edge-
  --    START (commit the fixed party), else hands off (measured clean end
  --    to $0054=1 at {57,45}, probe_leave).
  bumpTake(83, 34, "up", "Everyone here?"),
  (function()
    local aPh, sPh = 0, 0
    return H.driveUntil(function()
      local done = sw(0x0054) == 1
      if done then H.setPad({}) end
      return done
    end, 55000, {
      H.call(function()
        aPh = (aPh + 1) % 8; sPh = (sPh + 1) % 16
        if H.battleLoadStarted() then
          killBitAll(); H.setPad(aPh < 4 and { "a" } or {}); return
        end
        if H.dialogWaiting() then H.setPad(aPh < 4 and { "a" } or {}); return end
        if H.readByte(0x0059) ~= 0 then
          H.setPad(sPh < 6 and { "start" } or {})  -- commit the forced party
          return
        end
        H.setPad({})
      end),
    }, "the leave-Zozo walk-down")
  end)(),
  H.waitUntil(landed(221, 20), 3000, "control after the walk-down", 5),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 221, "back on the street (map 221)")
    H.assertEq(sw(0x0054), 1, "$0054 SET -- the stop line")
    H.assertEq(sw(0x0053), 1, "$0053 still set")
    H.assertEq(sw(0x0691), 1, "RAMUH carried")
    -- the give_genju results: the owned-esper bitfield $1A69, bit index =
    -- esper id - $36 (field/event.asm EventCmd_86).  RAMUH $36, SIREN $39,
    -- STRAY $3e, KIRIN $47 -- all four must be owned.
    local function hasEsper(id)
      local i = id - 0x36
      return (H.readByte(0x1A69 + (i >> 3)) >> (i & 7)) & 1
    end
    H.assertEq(hasEsper(0x36), 1, "RAMUH esper owned")
    H.assertEq(hasEsper(0x39), 1, "SIREN esper owned")
    H.assertEq(hasEsper(0x47), 1, "KIRIN esper owned")
    H.assertEq(hasEsper(0x3e), 1, "STRAY esper owned")
    -- all four stones' field NPCs cleared as taken
    H.assertEq(sw(0x031F), 0, "RAMUH's stone gone")
    H.assertEq(sw(0x0320), 0, "SIREN's stone gone")
    H.assertEq(sw(0x0321), 0, "KIRIN's stone gone")
    H.assertEq(sw(0x0322), 0, "STRAY's stone gone")
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
