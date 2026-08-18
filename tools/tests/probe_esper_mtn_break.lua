-- probe_esper_mtn_break.lua -- issue #127 P1: the Esper Mountain
-- sequence-break wedge risk (thamasa-route.md hazard 8, §7 item 8).
--
-- Claim under test: nothing readable gates the world entrance
-- 0 (229,130) -> 375 (55,31) on $008D (Strago talked), and the statue-lore
-- scene on map 371 (_cbf168, event_main.asm:73807) scripts a STRAGO object
-- with no presence check.  A pre-$008D party (TERRA/LOCKE/SHADOW, no Strago
-- in $1850) that reaches the statue trigger at 371 (15,20) may therefore
-- hang the game.  Vanilla might prevent entry by geometry instead
-- (UNVERIFIED).  This is a probe (no `-- @suite` marker, never joins the
-- suite): it drives pad input and reads memory only, per the input-driven
-- rule -- no HP/state/switch pokes.
--
-- Boots build/states/crescent_landing.mss.lua: world (232,150), party
-- TERRA*LOCKE*SHADOW, $008D=0 (checkpoint K, thamasa-route.md's own v0.7
-- stop line).  That is exactly the pre-Strago party the hazard asks about,
-- already on Crescent Island a short walk from the mountain.
--
-- Method:
--   1. (229,130) itself reads world-tile-prop IMPASSABLE ($0010 set) --
--      measured directly (a diagnostic worldPassable() sweep before this
--      probe was written): the whole mountain silhouette around it is
--      walled off except a one-tile gap at (229,131)/(226,*)/(232,*), i.e.
--      the entrance is authored on what looks like solid mountainside, the
--      same way Narshe's and Mt. Kolts's short-entrance tiles are (compare
--      world-map-nav.md's "Mt. Kolts world tile (102,100)").  So the walk
--      is worldNavTo to the one reachable approach tile, (229,131), then a
--      deliberate held UP into (229,130) -- exactly the case HANDOFF trap 6
--      describes ("a tile that takes the party away must be entered with a
--      held press rather than made the goal of navTo"), except here the
--      open question is *whether* it takes the party away at all: does
--      CheckEntrance (move.asm:1246-1303) match the tile before or instead
--      of the passability check blocking the step outright?  Both outcomes
--      are informative: a transition proves the entrance overrides the
--      wall for any party; a refused step (the party never leaves (229,131)
--      no matter how long UP is held) proves vanilla's geometry answer to
--      hazard 8 without ever reaching the statue room.
--   2. If map 375 loads: walk the exterior to the west statue-room door
--      375 (2,45) -> 371 (9,9) (thamasa-route.md §1 segment 5's map graph;
--      the save point (8,44) is the documented waypoint, seven tiles from
--      the door).  Hold directly onto the door tile (never a navTo goal,
--      same overshoot trap) and confirm the map change.
--   3. Inside 371 (no encounters on this map, per the route doc's table):
--      navTo an approach tile west of the statue trigger, avoiding the two
--      live event tiles ((15,20) statue-lore, (15,22) Ultros 3) so the BFS
--      never crosses either by accident.  Hold onto (15,20) on purpose,
--      then ride whatever happens for up to 1800 frames (30s @ 60fps),
--      paging any dialog with A and touching nothing else, sampling
--      hasControl()/eventRunning()/dialogWaiting() and switches $008D,
--      $0096, $0097 on a steady cadence.
--   A drive that never reaches "control back, tile aligned, no dialog"
--   inside that budget raises a driveUntil timeout -- that IS the wedge
--   signature the hazard describes, not a script bug, so it is left
--   unhandled by design: the timeout text plus the last logged sample are
--   the verdict.  No pcall anywhere in this file is deliberate.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/crescent_landing.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

local function logState(tag)
  local w = H.worldMode()
  H.log(string.format(
    "[p127 %s] f%d world=%s map=%d pos=(%d,%d) ctrl=%s evt=%s dlg=%s " ..
    "$008D=%d $0096=%d $0097=%d bright=%d",
    tag, H.frame, tostring(w), map(),
    w and H.worldX() or H.fieldX(), w and H.worldY() or H.fieldY(),
    tostring(w and H.worldHasControl() or H.hasControl()),
    tostring(H.eventRunning()), tostring(H.dialogWaiting()),
    sw(0x008D), sw(0x0096), sw(0x0097), bright()))
end

-- Hold a direction, fleeing any battle, until `pred` or maxFrames.  Used to
-- walk onto a hand-off tile deliberately (door / trigger), never as a navTo
-- goal (HANDOFF trap 6).
local function pressInto(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

-- Same as pressInto, but a timeout is a valid, expected outcome here (the
-- entrance tile may simply refuse the step) rather than a script failure:
-- logs and moves on instead of raising.  Used only for the world-entrance
-- step, where "the party never leaves the approach tile" is itself the
-- hazard-8 "geometry blocks it" answer this probe is checking for.
local function pressIntoSoft(dir, pred, maxFrames, what)
  local waited, ph = 0, 0
  return {
    tick = function()
      if pred() then
        H.setPad({})
        H.log(string.format(
          "pressIntoSoft '%s' satisfied after %d frames", what, waited))
        return "done"
      end
      waited = waited + 1
      if waited > maxFrames then
        H.setPad({})
        H.log(string.format(
          "pressIntoSoft '%s' TIMED OUT (soft) after %d frames -- treating " ..
          "as refused", what, maxFrames))
        return "done"
      end
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true })
      else
        H.setPad({ [dir] = true })
      end
      return "frame"
    end,
    reset = function() waited = 0 end,
  }
end

-- Ride whatever the game does after a step with no directional input: page
-- dialogs with A, flee any battle, otherwise hands off.  Samples state on a
-- steady cadence so a long ride (or a timeout) still leaves a full trace.
local function ride(pred, maxFrames, sampleEvery, what)
  local ph, lastSample = 0, -1
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.frame - lastSample >= sampleEvery then
        lastSample = H.frame
        logState("ride")
      end
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({})
    end),
  }, what)
end

local steps = {
  H.loadState(STATE),
  H.waitFrames(60),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned()
  end, 1800, "control at crescent_landing", 5),
  H.call(function()
    H.assertEq(H.worldX(), 232, "start world x")
    H.assertEq(H.worldY(), 150, "start world y")
    H.assertEq(sw(0x008D), 0, "PRECONDITION: pre-Strago party ($008D clear)")
    local terra, locke, shadow = H.readByte(0x1850 + 0), H.readByte(0x1850 + 1),
      H.readByte(0x1850 + 3)
    H.log(string.format("[p127 roster] TERRA=%02X LOCKE=%02X SHADOW=%02X",
      terra, locke, shadow))
    logState("start")
    H.screenshot("p127_start")
  end),

  -- 1a. World-walk to the one passable tile touching the entrance,
  -- (229,131) (measured; (229,130)/(229,129)/(228,130)/(230,130) are all
  -- impassable terrain).
  H.worldNavTo(229, 131, { maxFrames = 8000, playBattles = "flee" }),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(H.worldX(), 229, "approach tile x")
    H.assertEq(H.worldY(), 131, "approach tile y")
    logState("approach_229_131")
    H.screenshot("p127_approach")
  end),

  -- 1b. The deliberate step: hold UP into (229,130), the entrance tile
  -- itself.  Stops the moment the map changes (entry succeeded) or after
  -- 900 frames of holding UP with the party still on the world map (entry
  -- refused by geometry -- the party cannot even leave the approach tile).
  pressIntoSoft("up", function()
    return not H.worldMode()
  end, 900, "hold UP onto world (229,130) -- the entrance tile"),
  H.waitFrames(30),
  H.call(function()
    logState("entry_result")
    H.screenshot("p127_entry_result")
    if not H.worldMode() then
      H.log(string.format(
        "[p127] ENTRY: world (229,130) loaded map %d at field (%d,%d) -- " ..
        "the entrance is NOT gated on $008D", map(), H.fieldX(), H.fieldY()))
    else
      H.log(string.format(
        "[p127] ENTRY BLOCKED: still on the world at (%d,%d) after holding " ..
        "UP for 900 frames; the map load did not fire -- vanilla's " ..
        "impassable-looking terrain actually blocks the step, geometry " ..
        "prevents this sequence break", H.worldX(), H.worldY()))
    end
  end),

  H.cond(function() return not H.worldMode() end, {
    H.call(function()
      H.assertEq(map(), 375, "entered Esper Mountain exterior (map 375)")
    end),

    -- 2. Exterior 375 -> the save point (8,44) -> the west door approach
    -- (3,45) -> hold LEFT onto (2,45) -> 371 (9,9).  playBattles="flee" for
    -- the map-90 trash (Slurm/Adamanchyt); 371 itself has no encounters.
    H.navTo(8, 44, { maxFrames = 20000, playBattles = "flee" }),
    H.call(function()
      logState("at_save_point_375")
      H.screenshot("p127_save_point_375")
    end),
    H.navTo(3, 45, { maxFrames = 4000, playBattles = "flee" }),
    H.call(function() logState("at_door_approach_375") end),
    pressInto("left", function() return map() == 371 end, 600,
      "hold LEFT onto 375 (2,45) -> 371 (9,9)"),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(map(), 371, "inside the statue room (map 371)")
      logState("in_371")
      H.screenshot("p127_in_371")
    end),

    -- 3. Approach the statue trigger from the west, avoiding both live
    -- event tiles in the BFS plan, then hold onto (15,20) on purpose.
    H.navTo(14, 20, {
      maxFrames = 4000,
      avoid = { { 15, 20 }, { 15, 22 } },
    }),
    H.call(function()
      logState("statue_trigger_approach")
      H.screenshot("p127_statue_trigger_approach")
      H.log(string.format(
        "[p127] BEFORE trigger: $008D=%d $0096=%d $0097=%d",
        sw(0x008D), sw(0x0096), sw(0x0097)))
    end),

    -- The deliberate step: hold RIGHT long enough to cross one 16px tile
    -- (measured elsewhere at 1-1.33 px/frame; 24 frames is a safe margin)
    -- landing on (15,20), the statue-lore trigger.
    H.hold({ "right" }),
    H.waitFrames(24),
    H.release(),
    H.waitFrames(4),
    H.call(function()
      logState("statue_trigger_stepped")
      H.screenshot("p127_statue_trigger_stepped")
    end),

    -- The wedge watch: control back, tile aligned, no dialog waiting,
    -- within 1800 frames (30s).  If this raises a timeout, that is the
    -- wedge verdict; the periodic [p127 ride] lines above it in the log
    -- are the trace ($008D/$0096/$0097, hasControl/eventRunning/dialog).
    ride(function()
      return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
    end, 1800, 60, "wedge watch: control back after the statue-lore trigger"),

    H.call(function()
      logState("after_trigger_control_returned")
      H.screenshot("p127_after_trigger")
      H.log(string.format(
        "[p127 VERDICT] scene-runs-anyway: control returned at f%d, " ..
        "$0096=%d $0097=%d (doc: both set to 1 at event_main.asm:74018-74019 " ..
        "on a normal completion)", H.frame, sw(0x0096), sw(0x0097)))
    end),
  }, {
    H.call(function()
      H.log("[p127 VERDICT] entry-blocked: world (229,130) never handed off " ..
        "to a field map for this pre-Strago party")
    end),
  }),

  H.logStep(function()
    return string.format("probe_esper_mtn_break done at frame %d", H.frame)
  end),
}

local flat = {}
local function push(t)
  if type(t) == "table" and t[1] ~= nil and type(t[1]) == "table" then
    for _, s in ipairs(t) do push(s) end
  else
    flat[#flat + 1] = t
  end
end
for _, s in ipairs(steps) do push(s) end

H.run({ maxFrames = 120000 }, flat)
