-- probe_banquet_stage.lua -- I->J leg STAGING (issue #31): cold-Continue
-- the vector-crash-v1 battery, walk the world grind to Vector 253, enter
-- the castle, ride the escort, start the banquet at the dais, and mint
-- TWO development savestates:
--
--   banquet_predais.mss  -- standing beside the dais, window NOT started
--   banquet_window.mss   -- control back after the Gestahl/Cid scene,
--                           $007C=1, timer 0 live (the 14400 window)
--
-- These are ITERATION fixtures for the circuit/Q&A probes, not frontier
-- states; the leg generator (gen_banquet_done) replays this whole route
-- itself.  Run:
--
--   OT6_SRAM_ANCHOR=tools/tests/anchors/vector-crash-v1 \
--   tools/tests/run.sh tools/tests/probe_banquet_stage.lua
--
-- HAZARD (the H->I report's first-hazard note): the boot
-- tile world (83,238) is the dead Blackjack itself -- an A tap there
-- re-enters the wreck interior.  The Continue drive below presses A only
-- while NOT on the world map, and the grind presses directions only.
--
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end
local function timerCount() return H.readWord(0x1189) end
local function var0() return H.readWord(0x1fc2) end

-- VERIFIED-STEP world grinder.  The shared grind-and-replan idiom
-- (gen_vector_doorstep's) consumes one plan entry per ALIGNED FRAME, and
-- the party sits aligned for several frames before each press latches --
-- on straight lines the wasted entries agree in direction and nothing
-- shows, but every TURN of a long path desyncs the plan and forces a
-- 60000-node replan.  Measured on this leg's ~117-step grind (run 4,
-- 2026-07-28): ~139 frames/tile, a (73,221)<->(73,222) oscillation with
-- plan lengths jumping 86->93, and the emulator dragged to ~40fps by the
-- per-replan BFS.  This version consumes an entry only when the party
-- LANDS on that entry's destination tile (navTo's rule, worldized): one
-- BFS per leg plus one per battle return, 16 frames/tile.
local function worldGrind(tx, ty, what)
  local plan, idx, ph, hb = nil, 1, 0, -600
  local step = nil
  local DW = { up = { 0, -1 }, down = { 0, 1 },
               left = { -1, 0 }, right = { 1, 0 } }
  return H.driveUntil(function()
    return (not H.worldMode()) or (H.worldX() == tx and H.worldY() == ty
      and H.worldHasControl() and H.worldAligned())
  end, 60000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        killBitAll(); plan = nil; step = nil
        H.setPad(ph < 4 and { "a" } or {}); return
      end
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then
        plan = nil; step = nil; H.setPad({}); return
      end
      if not H.worldAligned() then return end   -- hold through the glide
      local x, y = H.worldX(), H.worldY()
      if step then
        if x == step.tx and y == step.ty then
          step = nil; idx = idx + 1               -- landed: next entry
        elseif x ~= step.fx or y ~= step.fy then
          plan = nil; step = nil                  -- drifted: replan
        else
          step.held = step.held + 1
          if step.held > 90 then                  -- press provably dead
            plan = nil; step = nil; H.setPad({}); return
          end
          H.setPad({ [step.dir] = true }); return
        end
      end
      if not plan or idx > #plan then
        plan = H.worldBfs(tx, ty); idx = 1
        if not plan then
          if H.frame - hb >= 600 then
            hb = H.frame
            H.log(string.format("[grind] NO PATH (%d,%d)->(%d,%d) f%d",
              x, y, tx, ty, H.frame))
          end
          H.setPad({}); return
        end
      end
      local dir = plan[idx]
      local d = DW[dir]
      step = { dir = dir, fx = x, fy = y,
               tx = (x + d[1]) & 0xFF, ty = (y + d[2]) & 0xFF, held = 0 }
      H.setPad({ [dir] = true })
    end),
  }, what or string.format("worldGrind (%d,%d)", tx, ty))
end

local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        killBitAll(); H.setPad(ph < 4 and { "a" } or {}); return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

-- The DAIS is a face-UP+A trigger the party must be STANDING ON: the
-- gate is `$01B4=0 or $01B0=0 or $007C=1 -> EventReturn` (_cc8490,
-- event_main.asm:97243-97247) -- $01B0 = facing up, $01B4 = A HELD.
-- M.tapLever is the wrong drive here: it releases A after 8 frames and
-- then only holds UP, so the gate reads A clear forever (measured, stage
-- run 9: 9000 frames, no latch).  What makes facing-up work without
-- walking off the tile is the GESTAHL NPC standing at (54,15) -- the
-- $062E object (npc_prop map-250 record 5), which blocks the step the
-- same way gen_sabin_train's upA holds into a wall.  So: stand on
-- (54,16), hold UP+A, with a 2-frame A release every 8 so the edge
-- re-arms.
local function holdUpA(swId, maxFrames, what)
  local n = 0
  return H.driveUntil(function() return sw(swId) == 1 end, maxFrames, {
    H.call(function()
      n = n + 1
      if H.dialogWaiting() then H.setPad(n % 8 < 4 and { "a" } or {}); return end
      H.setPad(n % 8 < 6 and { up = true, a = true } or { up = true })
    end),
  }, what)
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
      H.log(string.format("landed(%d) f%d: map=%d ctl=%s dlg=%s (%d,%d)",
        m, H.frame, map(), tostring(H.hasControl()),
        tostring(H.dialogWaiting()), H.fieldX(), H.fieldY()))
    end
    return cnt >= (n or 20)
  end
end

H.run({ maxFrames = 120000 }, {
  -- ---- cold Continue; NO stray A once the crash site is up -----------------
  -- worldMode() alone is useless as a gate here: $1F64 reads < 3 at the
  -- title screen too (measured, this probe's first run).  The A presses are
  -- gated on BRIGHTNESS (menus are lit; load fades are dark) and disarmed
  -- forever once the world is up AT (83,238) -- the boot tile is the wreck
  -- itself and one more A would walk back inside (measured).
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function() local ph = 0
    local function atSite()
      return H.worldMode() and H.worldX() == 83 and H.worldY() == 238
    end
    return H.driveUntil(function()
      return atSite() and bright() >= 15
    end, 4000, {
      H.call(function()
        ph = (ph + 1) % 48
        if atSite() or bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "Continue -> crash-site world load (A gated by brightness+position)")
  end)(),
  H.release(),
  H.waitUntil(function()
    return H.worldMode() and bright() >= 15 and H.worldHasControl()
  end, 1800, "world control at the crash site", 5),
  H.waitFrames(30),
  H.call(function()
    H.assertEntryContract("vector-crash-v1")
    H.log(string.format("[boot] world (%d,%d) f%d", H.worldX(), H.worldY(), H.frame))
  end),

  -- ---- the grind: crash site -> the Vector trigger row ---------------------
  -- ~117 offline steps; the trigger is (120,187)/(121,187) and stepping on
  -- it loads 253 ($0079=1), so aim one south and step up onto it.
  worldGrind(120, 188, "the I->J world grind (83,238) -> (120,188)"),
  H.call(function()
    H.log(string.format("[grind done] world (%d,%d) f%d",
      H.worldX(), H.worldY(), H.frame))
  end),
  pressWalk("up", function() return not H.worldMode() end, 900,
    "step onto the Vector trigger (120,187)"),
  H.waitUntil(landed(253, 10), 2400, "Vector 253 (post-attack)", 1),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[253] landed at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("bq_stage_253")
  end),

  -- ---- 253 -> castle door (28,1)+2 -> 243 (15,29) --------------------------
  H.navTo(28, 2, { maxFrames = 30000 }),
  pressWalk("up", function() return map() == 243 end, 900,
    "castle door 253 (28,1) -> 243 (15,29)"),
  H.waitUntil(landed(243, 10), 2400, "castle antechamber 243", 1),
  H.waitFrames(30),

  -- ---- the escort: walk onto (8,18), ride to $013A=1 -----------------------
  -- (8,18) is a stood-on trigger; the scene's dlg $06A6 blocks until
  -- dismissed and player_ctrl_on returns MID-script, so stepOff does both
  -- jobs: A through the dialog, then an unconditional held walk off the
  -- tile while the NPC finishes and the door opens.
  H.navTo(8, 18, { maxFrames = 12000, calmFrames = 4 }),
  H.stepOff({ "right", "down", "up" }, 6000,
    "escort: A through $06A6, step off (8,18)"),
  H.waitUntil(function() return sw(0x013A) == 1 end, 3000,
    "the escort ran ($013A)", 5),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(sw(0x062F), 1, "$062F -- the castle soldier population is up")
  end),

  -- ---- through the opened door (15,8) -> 250 (23,33) ------------------------
  H.navTo(15, 9, { maxFrames = 12000 }),
  pressWalk("up", function() return map() == 250 end, 900,
    "door 243 (15,8) -> 250 (23,33)"),
  H.waitUntil(landed(250, 10), 2400, "250 first entry", 1),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x013B), 1, "$013B -- 250 map-init ran (the {22,29} door)")
    H.log(string.format("[250] landed at (%d,%d)", H.fieldX(), H.fieldY()))
  end),

  H.call(function() H.screenshot("bq_stage_250_entry") end),
  H.saveState("banquet_250_entry.mss"),

  -- ---- the measured route to the dais --------------------------------------
  -- MEASURED (probe_banquet_interior, iterations 1-8): the 250 entry is a
  -- 131-tile component -- the entrance hall, the corridor, and the four
  -- hall soldiers -- and the dais is NOT in it.  The route is the corridor
  -- stairs, not a walk:
  --   * the {22,29} doorway is a door tile the BFS model reads as a wall;
  --     a HELD UP press crosses it (the {14,8} class);
  --   * (23,12) is the messenger trigger -- gated off ($007D=0) it still
  --     re-enters at every rest frame and WEDGES navTo (iteration 2).  A
  --     held press skips walk-over triggers (measured), so the
  --     messenger tile and the (23,9) stairs are crossed in ONE pressWalk;
  --   * (23,9) -> (54,34) (short entrance), and from (54,34) the dais is
  --     an ordinary 17-step navTo inside the throne tower.
  H.navTo(23, 30, { maxFrames = 6000 }),
  pressWalk("up", function()
    return H.fieldY() <= 28 and H.tileAligned()
  end, 900, "held UP through the {22,29} doorway"),
  H.release(),
  H.waitFrames(30),
  H.navTo(23, 13, { maxFrames = 9000 }),
  pressWalk("up", function()
    return (H.fieldX() ~= 23 or H.fieldY() > 20) and H.tileAligned()
  end, 1200, "held UP past (23,12) onto the (23,9) stairs -> (54,34)"),
  H.release(),
  H.waitUntil(landed(250, 10), 3000, "the throne tower (54,34)", 1),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.fieldX(), 54, "stairs landing x (short entrance 23,9)")
    H.assertEq(H.fieldY(), 34, "stairs landing y")
  end),
  H.navTo(54, 16, { maxFrames = 20000 }),
  H.call(function()
    H.assertEq(sw(0x007C), 0, "$007C still clear at the dais")
    H.screenshot("bq_stage_dais")
  end),
  H.saveState("banquet_predais.mss"),

  -- ---- face-UP+A on (54,16): the banquet starts -----------------------------
  -- tapLever returns the moment $007C latches (:97418); the timer starts
  -- one line later and the scene tail still runs.  The dais tile is a
  -- stood-on trigger afterwards, so the ride-out is stepOff.
  holdUpA(0x007C, 9000, "dais face-UP+A -> _cc8490 -> $007C=1"),
  H.release(),
  H.stepOff({ "down", "left", "right" }, 20000,
    "ride the Gestahl/Cid scene; step off the dais trigger"),
  H.waitUntil(landed(250, 10), 12000, "control with the window live", 1),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(sw(0x007C), 1, "$007C SET -- the window is live")
    H.assertEq(H.readByte(0x1188) ~= 0, true, "timer 0 flags live ($1188)")
    H.assertEq(sw(0x0634), 1, "$0634 -- the window soldier population is up")
    -- THE CASTLE OPENS HERE.  $0630=0 (event_main.asm:97415) deletes the
    -- two "Gestahl waits inside" servants at (16,30) and (30,30) -- and
    -- those are EXACTLY the two tiles the pre-banquet flood found blocked
    -- (probe_banquet_interior iterations 4-8), the object-map blocks that
    -- severed the west and east columns from the corridor.
    H.assertEq(sw(0x0630), 0, "$0630 CLEAR -- the corridor servants are gone")
    H.log(string.format(
      "[window] f%d timer=%d var0=%d at (%d,%d) map=%d",
      H.frame, timerCount(), var0(), H.fieldX(), H.fieldY(), map()))
    H.screenshot("bq_stage_window")
  end),
  H.saveState("banquet_window.mss"),
  H.logStep(function()
    return string.format(
      "banquet staging done: window live, timer=%d, frame %d",
      timerCount(), H.frame)
  end),
})
