-- gen_terra_returned_anchor.lua -- mint battery anchor F, `terra-returned-v1`
-- (save-points-vector.md §5): the WHOLE E->F leg in one run, from n128_won
-- (the nearest minted predecessor, parked on boundary E) to a world-map
-- battery save one takeoff after Terra's return.  §5 rules this leg cannot
-- be split legally -- a save inside the Esper-World flashback would save as
-- the WEDGE-actor Maduin with the roster rewritten -- so the anchor gen IS
-- the leg.
--
-- The route, every step measured on the probe ladder (2026-07-27):
--  1. 240 (58,7) -> (54,40) -> held LEFT onto the reunion trigger column
--     x=52 (approached from the EAST along row 40; §4.4's (52,36..38)
--     candidates are NOT walkable live).
--  2. The Setzer reunion auto-plays onto the Blackjack deck (map 6),
--     battle 71 (Cranes, 010D+010E) cleared with the route's kill-bit
--     idiom, then the non-interactive flights to Zozo and into the
--     flashback: control as the WEDGE-actor MADUIN at 219 (34,10).
--  3. The flashback's interactive chain (unmapped until now):
--       a. pocket exit (36,15) -> 217 (23,21);
--       b. talk the (32,11) NPC -> choice -> carry MADONNA in ($006C);
--       c. talk MADONNA resting at 219 (46,42) -> $006E;
--       d. talk the (32,11) NPC again -> PORTED to the gate map 218,
--          landing ON the inert trigger tile (56,49), which flickers
--          control ($0117=0 early-return) -- escaped with an UNCONDITIONAL
--          held press, the {10,9} lesson again;
--       e. talk MADONNA at the gate (55,34) -> the long confession/Terra
--          scene -> $006F=1 -> the Gestahl raid (auto);
--       f. talk NPC_4 (the tempest plan) -> $0116;
--       g. talk the elder -> MADUIN collapses -> $0117;
--       h. pocket exit (41,56) -> 217 -> the gate door (32,6) -> the
--          trigger fires ($0117=1) -> $0118;
--       i. talk MADONNA -> the finale _caa4e0 -> espers stolen, TERRA
--          taken -> party restored, Zozo, $02F0=1 (TERRA AVAILABLE),
--          Setzer's tutorial -> control on map 6.
--  4. Takeoff: LEFT+A on the wheel trigger 6 (14,6) (_caf532, facing+A
--     gated) -> world VEHICLE mode.  Strafe SOUTH (Y+down) until the LIVE
--     tile prop under the ship clears the can't-land bit ($c2 & $02,
--     world/init.asm LandAirship), one B tap -> the ship grounds.  The
--     menu opens from the grounded ship with saving ENABLED ($0201 bit7
--     measured $80 -- resolving §4.5's mid-flight caveat: airborne it is
--     $00).
--  5. The ordinary Save UI into slot 3; run.sh captures the battery.
--
-- See gen_mrf_save_room_anchor.lua for the codex-witness seeding and the
-- $307ff0 sentinel this file reuses.
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local saveArg = nil
local SAVE_SELECT = 0x14
local ULTROS2 = 0x012d
local TEMP_ELEM = 0x316c10 + ULTROS2
local TEMP_CLASS = 0x316d90 + ULTROS2

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end
local function shipX() return H.readWord(0x34) >> 4 end
local function shipY() return H.readWord(0x38) >> 4 end

-- unconditional held walk (dialogs/battles absorbed); for trigger tiles
-- and scripted stretches where control flickers
local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end
-- unconditional talker (A+dir edges)
local function pressTalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad(ph < 4 and { "a", dir } or { dir })
    end),
  }, what)
end
local function objAt(idx)
  local off = 0x29 * idx
  return H.readWord(0x086a + off) >> 4, H.readWord(0x086d + off) >> 4
end
local app = nil
local function planApproach(idx)
  return H.call(function()
    local ox, oy = objAt(idx)
    app = nil
    for _, c in ipairs({ { ox, oy + 1, "up" }, { ox - 1, oy, "right" },
                         { ox + 1, oy, "left" }, { ox, oy - 1, "down" } }) do
      local p = H.bfsPath(c[1], c[2])
      if p and not app then app = c end
    end
    H.log(string.format("[approach obj %02X] at (%d,%d): %s", idx, ox, oy,
      app and string.format("(%d,%d) facing %s", app[1], app[2], app[3]) or "NONE"))
    assert(app, "no reachable neighbor for the talk target")
  end)
end
local function talkApproached(pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad(ph < 4 and { "a", app[3] } or { [app[3]] = true })
    end),
  }, what)
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/n128_won.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 240, "booted on boundary E (n128_won)")
    H.assertEq(H.fieldX(), 58, "boot x")
    H.assertEq(H.fieldY(), 7, "boot y")
  end),

  -- 1. the reunion trigger
  H.navTo(54, 40, { honest = "flee", maxFrames = 25000 }),
  pressWalk("left", function() return map() == 6 end, 9000,
    "held LEFT onto the reunion trigger -> the Blackjack deck"),

  -- 2. reunion, Cranes, flights, into the flashback.  honest="tactical",
  -- not "true": this ride contains the FORCED Left & Right Cranes fight
  -- (bosses-wob.md 16, 6+6 shields), and blind tap-A does not win bosses
  -- -- the library fighter (items, boost, AutoCrossbow/Pummel) does.  The
  -- phase-2 re-cut is this drive's first live run; if the Cranes prove a
  -- wall for the honest chain party, that is a measured finding for the
  -- ladder discussion, not a reason to weaken this back.
  H.advanceStory(function()
    return map() == 219 and sw(0x01C2) == 1 and settled()
  end, 100000, { honest = "tactical" }),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(map(), 219, "the Esper-World flashback (map 219)")
    H.assertEq(sw(0x006B), 1, "$006B SET -- the reunion played")
    H.log("[flashback] control as MADUIN")
  end),

  -- 3a/3b. out to the town, carry Madonna in
  H.navTo(36, 14, { honest = "flee", maxFrames = 6000 }),
  pressWalk("down", function() return map() == 217 end, 6000,
    "pocket exit (36,15) -> 217"),
  H.waitFrames(60),
  H.navTo(32, 12, { honest = "flee", maxFrames = 12000 }),
  pressTalk("up", function() return sw(0x006C) == 1 end, 20000,
    "talk (32,11) -> carry MADONNA in -> $006C"),
  H.waitFrames(90),

  -- 3c. Madonna resting -> $006E
  H.navTo(46, 43, { honest = "flee", maxFrames = 9000 }),
  pressTalk("up", function() return sw(0x006E) == 1 end, 25000,
    "talk MADONNA -> $006E"),
  H.waitFrames(90),

  -- 3d. to the gate (the corridor NPC ports us; the landing tile flickers)
  H.navTo(36, 14, { honest = "flee", maxFrames = 6000 }),
  pressWalk("down", function() return map() == 217 end, 6000,
    "pocket exit -> 217"),
  H.waitFrames(60),
  H.navTo(32, 12, { honest = "flee", maxFrames = 12000 }),
  pressTalk("up", function() return map() == 218 end, 15000,
    "talk (32,11) -> ported to the gate (218)"),
  H.waitFrames(90),
  pressWalk("up", function() return H.fieldY() <= 45 end, 700,
    "held UP off the inert gate trigger tile"),

  -- 3e. the confession -> $006F and the raid
  planApproach(0x1C),
  H.navTo(function() return app[1] end, function() return app[2] end,
    { honest = "flee", maxFrames = 9000 }),
  talkApproached(function() return sw(0x006F) == 1 end, 40000,
    "talk MADONNA at the gate -> $006F"),
  H.advanceStory(function() return map() == 219 and settled() end, 30000, { honest = true }),
  H.waitFrames(90),

  -- 3f. the tempest plan -> $0116
  planApproach(0x13),
  H.navTo(function() return app[1] end, function() return app[2] end,
    { honest = "flee", maxFrames = 9000 }),
  talkApproached(function() return sw(0x0116) == 1 end, 12000,
    "talk NPC_4 -> $0116"),
  H.waitFrames(90),

  -- 3g. the collapse -> $0117
  planApproach(0x12),
  H.navTo(function() return app[1] end, function() return app[2] end,
    { honest = "flee", maxFrames = 9000 }),
  talkApproached(function() return sw(0x0117) == 1 end, 12000,
    "talk the elder -> $0117"),
  H.waitFrames(90),

  -- 3h. the chase to the gate -> $0118
  H.navTo(41, 55, { honest = "flee", maxFrames = 9000 }),
  pressWalk("down", function() return map() == 217 end, 6000,
    "pocket exit (41,56) -> 217"),
  H.waitFrames(60),
  H.navTo(32, 7, { honest = "flee", maxFrames = 15000 }),
  pressWalk("up", function() return map() == 218 or sw(0x0118) == 1 end, 9000,
    "onto (32,6) -> the gate trigger"),
  H.advanceStory(function() return sw(0x0118) == 1 end, 30000, { honest = true }),
  H.waitFrames(60),

  -- 3i. the finale and the ride home
  planApproach(0x1C),
  H.navTo(function() return app[1] end, function() return app[2] end,
    { honest = "flee", maxFrames = 9000 }),
  talkApproached(function() return not H.hasControl() or map() ~= 218 end, 12000,
    "talk MADONNA -> the finale _caa4e0"),
  H.advanceStory(function()
    return map() == 6 and sw(0x02F0) == 1 and settled()
  end, 90000, { honest = true }),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(sw(0x02F0), 1, "$02F0 SET -- TERRA is available (the v0.6 stop line)")
    H.assertEq(sw(0x0070), 1, "$0070 SET -- the party-swap room is armed")
    H.assertEq(sw(0x016F), 1, "$016F SET -- the tutorial tail ran")
    H.log("[blackjack] Terra returned; taking off")
    H.screenshot("anchor_f_blackjack")
  end),

  -- 4. takeoff and grounding
  H.navTo(14, 6, { honest = "flee", maxFrames = 6000, calmFrames = 8 }),
  (function() local ph = 0
    return H.driveUntil(function() return H.worldMode() end, 1200, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({ "a", "left" })
      end),
    }, "LEFT+A on the wheel -> takeoff")
  end)(),
  H.release(),
  H.waitFrames(150),
  (function() local calm = 0
    return H.driveUntil(function()
      calm = ((H.readByte(0xc2) & 0x02) == 0) and calm + 1 or 0
      return calm >= 20
    end, 4000, {
      H.call(function() H.setPad({ y = true, down = true }) end),
    }, "strafe south to landable ground")
  end)(),
  H.release(),
  H.waitFrames(45),
  H.pressButtons({ "b" }, 8),
  H.waitUntil(function() return H.worldX() ~= 0 or H.worldY() ~= 0 end,
    1200, "the ship grounds (world position cells written)", 10),
  H.waitFrames(90),
  H.call(function()
    H.log(string.format("[grounded] $1f64=%04X world=(%d,%d) ship=(%d,%d)",
      H.readWord(0x1f64), H.worldX(), H.worldY(), shipX(), shipY()))
    H.screenshot("anchor_f_grounded")
  end),

  -- 5. the Save UI (menu save is ENABLED from the grounded ship; measured)
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
    }, "world menu open from the grounded ship")
  end)(),
  H.waitFrames(30),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x05 end, 600,
    "main menu state", 5),
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "menu-flags $0201 bit7 SET -- the save-enable flow reached the menu")
    -- ARM THE HONEST SAVE RECEIPT (issue #75): a read-only exec hook on
    -- the real CopyGameDataToSRAM entry captures the slot argument the
    -- save runs with (codex_saveas's instrument).  This replaces the old
    -- zeroed-$307ff0 sentinel -- an SRAM write -- as the proof that the
    -- real save ran to completion for slot 3.
    local entry = H.sym("CopyGameDataToSRAM")
    emu.addMemoryCallback(function()
      saveArg = emu.getState()["cpu.a"] & 0xff
    end, emu.callbackType.exec, entry, entry)
  end),
  -- THE PAD-DRIVEN SAVE (save-drive rule, tools/tests/README.md;
  -- codex_saveas and probe_banquet_timer_save are the templates): UP wraps
  -- the main-menu cursor to Save (row 6), A enters the menu's own
  -- SelectMainMenuOption_06 path, the slot cursor is STEERED to slot 3 by
  -- pad against its live cell, and A confirms on through any overwrite
  -- prompt.  No ZMENUSTATE poke, no cursor poke, no display-cache poke,
  -- and no witness seeding: the codex payload the battery carries is
  -- whatever the chain EARNED, read and logged below (issue #75).
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
    -- the codex witness cells are READ, never seeded (issue #75): the
    -- battery carries whatever the chain actually earned.  The phase-2
    -- anchor re-cuts measure these and the entry contracts follow the
    -- measurement (never the reverse).
    H.log(string.format("codex witness cells (earned): elem=%02X class=%02X",
      emu.read(0x316810 + ULTROS2, emu.memType.snesMemory),
      emu.read(0x316990 + ULTROS2, emu.memType.snesMemory)))
    H.log("real Save UI wrote the terra-returned anchor to slot 3")
  end),
  -- The exit contract is asserted WITH THE MENU OPEN, the post-opera
  -- precedent: the grounded-airship world menu does not unwind on B the
  -- way the field menus do (measured -- 900 frames of B left $59 set),
  -- and every declared field reads from WRAM/SRAM cells the menu leaves
  -- intact ($1f64, $e0/$e2, $1E80.., $1850, bank $31).
  H.waitFrames(45),
  H.call(function()
    H.assertExitContract("terra-returned-v1")
    H.screenshot("anchor_f_saved")
  end),
  H.logStep(function()
    return string.format("terra-returned-v1 saved via the real Save UI at "
      .. "frame %d -- world (%d,%d), slot 3; the v0.6 stop line",
      H.frame, H.worldX(), H.worldY())
  end),
})
