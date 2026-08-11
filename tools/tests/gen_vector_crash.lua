-- gen_vector_crash.lua -- v0.7 step H->I (issue #31), and the generator
-- that cuts battery checkpoint I, `vector-crash-v1`.
--
-- The step: cold-Continue the tracked `gate-cave-save-v1` battery (boundary
-- H, map 386 (74,53), the area's only interior save point), assert its
-- contract, then:
--   1. leave the save room (386 (73,59) short entrance -> 384 (64,12));
--   2. the 384 west traverse (measured, probe_v07_384west/2/3/4/5 and
--      probe_v07_384toggle; these probes are the record, and the recon's own
--      seven-lever reading was wrong):
--      the minimal switch chain is two levers rather than seven:
--        * (71,15) face-UP+A (_cb3176, event_main.asm:45276): persistent
--          $0174, extends the x=76 column bridge; 266-tile south loop ->
--          587 tiles, the whole east half;
--        * (104,17) face-UP+A toggle (_cb33c9, :45485): session $01F5,
--          flips the 5x13 tower region; 587 -> 655 tiles, opening the
--          (120..121,17..23) descent.  One 8-frame up+A tap fires it and
--          the switch flips at the event's end (~70 frames); a second A
--          press on the tile toggles it back, so the drive taps once and
--          then waits rather than repeating A;
--      then the (121,23) -> (4,37) teleport (short-entrance record; the
--      pairs are one-way: (4,36)->(121,22) is the return) and the west
--      walk to the gate door row (9..11,27), a 3-tile long entrance,
--      len 2 H, so the entry point must sit off that row.
--      The (58,18) span switch, the (89,29)/(96,18)/(99,18) walk-overs
--      and the (112,16)/(99,13) toggles are not on this route: the span
--      only opens the (46..41,11) west bridge (a dead end for the
--      traverse) and the walk-overs serve the treasure alcove.
--   3. the sealed gate scene (map 391; entry (8,21) is the scene trigger,
--      _cb39ca, :45953): ridden with no input via advanceStory, battles 121
--      and 122 in opts.spare.  The $17b dummy cannot be lost and must
--      never be write-cleared, because its battle_event is the scene
--      (measured).  The tail sets $0079=1 and returns control at 384 (10,28);
--   4. out the post-gate shortcut ((5,43) -> _cb2a9f -> 382 (31,41),
--      exposed by the $0079 map-init retile), the cave mouth (25,38) ->
--      world (169,194), the pocket, (166,194) -> the base east door;
--   5. the base re-cross and the crash: walking into the west trigger row
--      fires _cb280f (:44289), which runs the ensemble scene, $0242=1, the
--      auto-teleport to the Blackjack, battle 123 (spared; battle_event
--      $15 stages the deck crew on-screen, so rosters are asserted
--      field-side only, never inside), $007A/$007B/$01BA=1 $0246=0, the
--      scripted crash flight, and control back on map 6 (16,6) with the
--      wreck's parent map set to world (83,239);
--   6. the airship-dead check at the wheel (facing-LEFT+A on (14,6) opens
--      nothing, because _caf532 EventReturns on $007A=1/$0176=0), then off the
--      wreck: deck door (20,6) -> map 7 (40,11), the interior stairs
--      (40,18)->(50,51) and (50,62)->(10,30), the hatch trigger (8,36)
--      (_caf4b1: with $007A=1/$009D=0 it exits ON FOOT to the parent
--      world map) -- landing ON the wreck's world tile (83,238), on foot
--      (measured, probe_v07_gatescene3; an A tap there re-enters the
--      wreck interior, so the generator never presses A on the world);
--   7. the world battery save on that tile -- boundary I,
--      `vector-crash-v1` (the route recon's own name for the boundary, at
--      the recon's own proposed tile (83,238)).
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- ^ run.sh refuses, before boot, any OT6_SRAM_CHECKPOINT whose manifest
--   declares a different persistent_layout.
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local saveArg = nil
local SAVE_SELECT = 0x14
local ULTROS2 = 0x012d
local TEMP_ELEM = 0x316c10 + ULTROS2
local TEMP_CLASS = 0x316d90 + ULTROS2
local DUMMY = 0x017b            -- the gate set pieces' one formation word

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end

-- gen_vector_entry's grind-and-replan world walker
local function worldGrind(tx, ty, what)
  local plan, idx, ph = nil, 1, 0
  return H.driveUntil(function()
    return (not H.worldMode()) or (H.worldX() == tx and H.worldY() == ty
      and H.worldHasControl() and H.worldAligned())
  end, 30000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        plan = nil; H.setPad({ l = true, r = true }); return
      end
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then plan = nil; H.setPad({}); return end
      if not H.worldAligned() then return end
      if not plan or idx > #plan then plan = H.worldBfs(tx, ty); idx = 1 end
      if not plan then H.setPad({}); return end
      local dir = plan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, what or string.format("worldGrind (%d,%d)", tx, ty))
end

-- unconditional held walk (dialogs/battles absorbed); for trigger tiles
-- and scripted stretches where control flickers
local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true }); return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

-- tapLever / stepOff: the measured lever and re-entry-escape idioms this
-- generator introduced now live in lib/ot6_field.lua (M.tapLever and
-- M.stepOff, promoted 2026-07-28 when the I->J step needed both again).
local tapLever, stepOff = H.tapLever, H.stepOff

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

local function assertGateParty(where)
  H.assertEq(partyOf(0x00), 1, "TERRA in party 1 -- " .. where)
  H.assertEq(partyOf(0x01), 1, "LOCKE in party 1 -- " .. where)
  H.assertEq(partyOf(0x04), 1, "EDGAR in party 1 -- " .. where)
  H.assertEq(partyOf(0x05), 1, "SABIN in party 1 -- " .. where)
end

H.run({ maxFrames = 240000 }, {
  -- ---- the cold Continue and the entry contract (issue #25) -------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  -- The boot tile is the SavePoint trigger: a cold Continue stands the
  -- party on 386 (74,53) and the trigger re-enters every frame, so
  -- hasControl() never settles there.  This is the stood-on-trigger class,
  -- where a trigger tile's script re-fires every frame.
  -- Gate on map, alignment and brightness only; the contract assert is
  -- read-only, and the escape below is an unconditional held press.
  (function() local cnt = 0
    return H.waitUntil(function()
      local ok = map() == 386 and H.tileAligned() and bright() >= 15
             and not H.dialogWaiting() and not H.battleLoadStarted()
      cnt = ok and cnt + 1 or 0
      return cnt >= 10
    end, 3000, "cold Continue to the map-386 save tile (boundary H)", 10)
  end)(),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("gate-cave-save-v1")
    assertGateParty("the H boot")
  end),

  -- ---- 1. out of the save room -------------------------------------------
  pressWalk("down", function()
    return H.fieldY() >= 55 and H.tileAligned()
  end, 1200, "held DOWN off the save-point re-entry tile"),
  H.navTo(73, 58, { playBattles = "flee", maxFrames = 9000 }),
  pressWalk("down", function() return map() == 384 end, 1200,
    "held DOWN off 386 (73,59) -> 384 (64,12)"),
  H.waitUntil(landed(384, 10), 2400, "384 re-entry", 1),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.fieldX(), 64, "384 re-entry x (short entrance 386 (73,59))")
    H.assertEq(H.fieldY(), 12, "384 re-entry y")
  end),

  -- ---- 2. the west traverse: two levers, one teleport ---------------------
  H.navTo(71, 15, { playBattles = "flee", maxFrames = 20000 }),
  tapLever(0x0174, 900, "tap-once UP+A on (71,15) -> $0174 (the x=76 column)"),
  stepOff({ "down", "left", "right", "up" }, 2400,
    "step off the (71,15) re-entry trigger"),
  H.navTo(104, 17, { playBattles = "flee", maxFrames = 30000 }),
  tapLever(0x01F5, 900, "tap-once UP+A on (104,17) -> $01F5 (the tower)"),
  H.release(),
  stepOff({ "down", "left", "right" }, 2400,
    "step off the (104,17) toggle (a further A press would toggle it back)"),
  H.navTo(121, 22, { playBattles = "flee", maxFrames = 20000 }),
  pressWalk("down", function()
    return H.fieldX() <= 8 and H.tileAligned()
  end, 2400, "held DOWN onto the (121,23) teleport -> (4,37)"),
  H.waitUntil(landed(384, 10), 3600, "west side after the teleport", 1),
  H.waitFrames(30),
  H.call(function()
    H.screenshot("step_hi_westside")
    H.log(string.format("[west] (%d,%d)", H.fieldX(), H.fieldY()))
  end),

  -- ---- 3. the gate door and the scene -------------------------------------
  -- the door row (9..11,27) is approached from the south (census G: the
  -- x=9..11 column below it is the only walkway; (12,27) is not walkable),
  -- so the entry point is (10,28), the same tile the scene exits onto
  H.navTo(10, 28, { playBattles = "flee", maxFrames = 20000 }),
  H.call(function()
    assertGateParty("the gate entry point (field side, before the scene)")
    H.assertEq(sw(0x0079), 0, "$0079 CLEAR at the entry point")
    H.screenshot("step_hi_gate_entry")
  end),
  pressWalk("up", function() return map() == 391 end, 1200,
    "held UP onto the door row (10,27) -> SEALED GATE (391)"),
  H.advanceStory(function()
    return map() == 384 and sw(0x0079) == 1 and H.hasControl()
       and H.tileAligned() and bright() >= 15
  end, 90000, { playBattles = "flee", spare = { DUMMY } }),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 384, "back on 384 after the gate scene")
    H.assertEq(H.fieldX(), 10, "scene exit x (load_map 384 {10,28})")
    H.assertEq(H.fieldY(), 28, "scene exit y")
    H.assertEq(sw(0x0079), 1, "$0079 SET -- the gate scene ran")
    H.assertEq(sw(0x0471), 1, "$0471 SET (the scene tail)")
    H.assertEq(sw(0x064D), 1, "$064D SET (the scene tail)")
    assertGateParty("after the gate scene (Terra restored, :46202)")
    H.screenshot("step_hi_post_gate")
  end),

  -- ---- 4. the shortcut out -------------------------------------------------
  H.navTo(5, 42, { playBattles = "flee", maxFrames = 20000,
    arrive = function() return map() == 382 end }),
  pressWalk("down", function() return map() == 382 end, 1200,
    "held DOWN onto the (5,43) shortcut -> 382 (31,41)"),
  H.waitUntil(landed(382, 10), 2400, "382 via the shortcut", 1),
  -- the mouth is the (25,37)/(25,38) pair: (25,37) is the world entry's
  -- landing, (25,38) the exit tile (short-entrance decode); approach the
  -- landing tile and step DOWN out
  H.navTo(25, 37, { playBattles = "flee", maxFrames = 15000,
    arrive = function() return H.worldMode() end }),
  pressWalk("down", function() return H.worldMode() end, 1200,
    "held DOWN onto the mouth exit (25,38) -> world (169,194)"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
       and H.worldX() ~= 0
  end, 2400, "the world pocket", 5),
  H.waitFrames(30),

  -- ---- 5. the base re-cross, battle 123, the crash -------------------------
  worldGrind(167, 194, "pocket walk -> (167,194)"),
  pressWalk("left", function() return not H.worldMode() and map() == 377 end,
    900, "(166,194) -> IMPERIAL BASE east door (30,13)"),
  H.waitUntil(landed(377, 10), 2400, "base east landing", 1),
  H.call(function()
    assertGateParty("the base re-cross (field side, before battle 123)")
  end),
  -- walk west toward the trigger row; _cb280f drives everything from there
  -- to the crash: the scene, $0242=1, the deck, battle 123, the flight,
  -- and control back on map 6 at (16,6) with parent world (83,239)
  H.navTo(9, 17, { playBattles = "flee", maxFrames = 20000 }),
  pressWalk("left", function() return not H.hasControl() or map() ~= 377 end,
    2400, "held LEFT into the west trigger row -> _cb280f"),
  H.advanceStory(function()
    return map() == 6 and sw(0x007A) == 1 and H.hasControl()
       and H.tileAligned() and bright() >= 15
  end, 120000, { playBattles = "flee", spare = { DUMMY } }),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 6, "control back on the wrecked Blackjack (map 6)")
    H.assertEq(sw(0x007A), 1, "$007A SET -- the airship is dead")
    H.assertEq(sw(0x007B), 1, "$007B SET (Vector stands down)")
    H.assertEq(sw(0x01BA), 1, "$01BA SET (crash latch)")
    H.assertEq(sw(0x0242), 1, "$0242 SET -- the base entrance went silent")
    H.assertEq(sw(0x0246), 0, "$0246 CLEAR -- no active airship")
    assertGateParty("after the crash (field side -- battle_event $15's "
      .. "deck roster never leaks out)")
    H.screenshot("step_hi_wreck_deck")
  end),

  -- ---- the airship-dead check: the wheel does not respond -------------------
  -- On a live chain, facing-LEFT+A on the wheel (14,6) opens the $052A
  -- lift-off choice ($0170 is set on this chain).  With the airship dead
  -- ($007A=1, $0176=0), _caf532 EventReturns before any dialog
  -- (event_main.asm:36118-36127).  300 frames of LEFT+A edges must therefore
  -- open nothing.
  H.navTo(14, 6, { playBattles = "flee", maxFrames = 6000, calmFrames = 8 }),
  (function() local n = 0
    return H.driveUntil(function() n = n + 1; return n >= 300 end, 400, {
      H.call(function()
        H.setPad(n % 8 < 4 and { "a", left = true } or { left = true })
      end),
    }, "300 frames of LEFT+A on the dead wheel")
  end)(),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 6, "still on map 6 -- the dead wheel opened nothing")
    H.assertEq(H.dialogWaiting(), false,
      "no lift-off choice -- $007A gates the wheel (_caf532)")
    H.assertEq(H.readByte(0x59), 0, "no menu/vehicle takeover")
  end),

  -- ---- 6. off the wreck: deck -> interior -> the hatch ---------------------
  pressWalk("right", function() return map() == 7 end, 1800,
    "held RIGHT along the deck -> door (20,6) -> map 7"),
  H.waitUntil(landed(7, 10), 2400, "map 7 landing", 1),
  -- the hatch (8,36) is reached through the interior stair-teleports
  -- (short-entrance decode): (40,18) -> (50,51), then (50,62) -> (10,30)
  H.navTo(40, 17, { playBattles = "flee", maxFrames = 9000 }),
  pressWalk("down", function()
    return H.fieldY() >= 45 and H.tileAligned()
  end, 900, "stairs (40,18) -> (50,51)"),
  H.waitFrames(30),
  H.navTo(50, 61, { playBattles = "flee", maxFrames = 9000 }),
  pressWalk("down", function()
    return H.fieldY() <= 35 and H.tileAligned()
  end, 900, "stairs (50,62) -> (10,30)"),
  H.waitFrames(30),
  H.navTo(8, 36, { playBattles = "flee", maxFrames = 20000,
    arrive = function() return H.worldMode() end }),
  pressWalk("up", function() return H.worldMode() end, 1200,
    "held UP onto the hatch (8,36) -> world, on foot (_caf4b1)"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
       and H.worldX() ~= 0
  end, 3600, "world at the crash site", 5),
  H.waitFrames(45),
  -- Measured (probe_v07_gatescene3): the hatch drops the party on the
  -- wreck's own world tile (83,238), the route recon's proposed
  -- checkpoint-I tile, on foot, with $1F60/61 == $1F62/63 == (83,238).
  -- An A tap here re-enters the wreck interior (it does not lift off, and
  -- the gen never presses it); the wheel check above already showed the
  -- airship will not fly.
  H.call(function()
    H.log(string.format("[crash site] world (%d,%d) ship cells $1F62/63 = "
      .. "(%d,%d) $11FA=%02X $11F3=%02X $1F60/61=(%d,%d)",
      H.worldX(), H.worldY(),
      H.readByte(0x1F62), H.readByte(0x1F63),
      H.readByte(0x11FA), H.readByte(0x11F3),
      H.readByte(0x1F60), H.readByte(0x1F61)))
    H.assertEq(H.worldX(), 83, "crash-site x -- standing on the wreck")
    H.assertEq(H.worldY(), 238, "crash-site y")
    H.assertEq(H.readByte(0x11FA) & 3, 0, "ON FOOT at the crash site")
    H.screenshot("step_hi_crash_site")
  end),

  -- ---- 7. the world battery save at the crash site, boundary I ------------
  H.call(function()
    H.assertExitContractPreSave("vector-crash-v1")
    H.screenshot("step_hi_i_tile")
  end),
  -- The step's savestate is generated here, before the menu, because the
  -- world menu does not unwind on B (measured)
  H.saveState("vector_crash.mss"),

  -- ---- the real Save UI, slot 3 --------------------------------------------
  (function() local calm, ph = 0, 0
    return H.driveUntil(function()
      calm = (H.readByte(0x59) ~= 0) and calm + 1 or 0
      return calm >= 30
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 48
        if H.readByte(0x59) ~= 0 then H.setPad({}); return end
        H.setPad(ph < 6 and { "x" } or {})
      end),
    }, "world menu open at the crash site")
  end)(),
  H.waitFrames(30),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x05 end, 600,
    "main menu state", 5),
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "menu-flags $0201 bit7 SET -- the save-enable flow reached the menu")
    -- Arm the input-driven save receipt (issue #75): a read-only exec hook on
    -- the real CopyGameDataToSRAM entry captures the slot argument the
    -- save runs with (codex_saveas's instrument).  This replaces the old
    -- zeroed-$307ff0 sentinel, which was an SRAM write, as the evidence that
    -- the real save ran to completion for slot 3.
    local entry = H.sym("CopyGameDataToSRAM")
    emu.addMemoryCallback(function()
      saveArg = emu.getState()["cpu.a"] & 0xff
    end, emu.callbackType.exec, entry, entry)
  end),
  -- The pad-driven save (save-drive rule, tools/tests/README.md;
  -- codex_saveas and probe_banquet_timer_save are the templates): UP wraps
  -- the main-menu cursor to Save (row 6), A enters the menu's own
  -- SelectMainMenuOption_06 path, the slot cursor is steered to slot 3 by
  -- pad against its live cell, and A confirms on through any overwrite
  -- prompt.  There is no ZMENUSTATE poke, no cursor poke, no display-cache
  -- poke, and no witness seeding: the codex payload the battery carries is
  -- whatever the chain earned, read and logged below (issue #75).
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == 0x05 and H.readByte(0x4b) == 6
  end, 600, {
    H.pressButtons({ "up" }, 4), H.waitFrames(16),
  }, "main-menu cursor on Save"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    600, "save-slot selection", 5),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == SAVE_SELECT and H.readByte(0x4b) == 2
  end, 600, {
    H.pressButtons({ "down" }, 4), H.waitFrames(16),
  }, "save cursor on slot 3"),
  H.driveUntil(function()
    return saveArg == 3
       and emu.read(0x307ff0, emu.memType.snesMemory) == 3
  end, 1800, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "save confirmed -- CopyGameDataToSRAM ran for slot 3 (exec hook)"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), 3,
      "SRAM $307ff0 records slot 3")
    H.assertEq(saveArg, 3, "CopyGameDataToSRAM ran for persistent slot 3")
    -- the codex witness cells are read, never seeded (issue #75): the
    -- battery carries whatever the chain earned.  The phase-2 checkpoint
    -- re-cuts measure these, and the entry contracts follow the
    -- measurement rather than the other way round.
    H.log(string.format("codex witness cells (earned): elem=%02X class=%02X",
      emu.read(0x316810 + ULTROS2, emu.memType.snesMemory),
      emu.read(0x316990 + ULTROS2, emu.memType.snesMemory)))
    H.assertExitContract("vector-crash-v1")
    H.screenshot("step_hi_saved")
  end),
  H.logStep(function()
    return string.format("vector-crash-v1 saved via the real Save UI at "
      .. "frame %d -- the crash-site world save; boundary I of the v0.7 range",
      H.frame)
  end),
})
