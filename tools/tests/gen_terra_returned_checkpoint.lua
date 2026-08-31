-- gen_terra_returned_checkpoint.lua -- generate SRAM checkpoint F,
-- `terra-returned-v1` (the A-F save-point boundary range is lettered in
-- tools/tests/savestate_graph.py): the WHOLE E->F step in one run, from
-- n128_won (the nearest generated predecessor, parked on boundary E) to a
-- world-map battery save one takeoff after Terra's return.  This step
-- cannot be split legally -- a save inside the Esper-World flashback would
-- save as the WEDGE-actor Maduin with the roster rewritten -- so the
-- checkpoint gen IS the step.

-- See gen_mrf_save_room_checkpoint.lua for the codex-witness seeding and the
-- $307ff0 sentinel this file reuses.
local H = dofile("tools/tests/lib/ot6.lua")
local L = H.newSeedLadder("cranes ride")

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

local summonChars, rideBlob, rideWon = {}, nil, false
local function rideAttempt(n)
  local loadReq
  return H.cond(function() return rideWon end, {}, {
    H.logStep(function()
      return string.format("cranes ride attempt %d at f%d", n, H.frame)
    end),
    (n > 1) and H.seqStep({
      H.call(function() loadReq = H.requestLoadState(rideBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "pre-attempt reload") end),
      H.waitFrames(90),
    }) or H.waitFrames(1),
    H.navTo(54, 40, { playBattles = "flee", maxFrames = 25000 }),
    pressWalk("left", function() return map() == 6 end, 9000,
      "held LEFT onto the reunion trigger -> the Blackjack deck"),
    H.release(),
    L.spread(n),                         -- spread the battle RNG phase (#83)
    (function()
      local F = H.newFightDriver("terra ride", { tactical = true,
        boost = true, bank = 2, items = true, healer = 9, healPercent = 45,
        tools = false, cadence = 12, summon = summonChars,
        focus = { { slot = 0, mask = 0x01 } } })
      local ph, battN, wasBatt = 0, 0, false
      local lastHp, wiped = {}, false
      return H.driveUntil(function()
        if map() == 219 and sw(0x01C2) == 1 and settled() then
          rideWon = true
          H.setPad({})
          H.log(string.format("[ride] attempt %d reached the flashback "
            .. "at f%d", n, H.frame))
          return true
        end
        if wiped then
          H.log(string.format("[ride] attempt %d WIPED at f%d", n, H.frame))
          return true
        end
        return false
      end, 100000, {
        H.call(function()
          ph = (ph + 1) % 8
          battN = H.battleLoadStarted() and battN + 1 or 0
          if battN == 3 and not wasBatt then wasBatt, lastHp = true, {} end
          if wasBatt and battN == 0 then
            wasBatt = false
            for m = 0, 1 do
              if lastHp[m] and lastHp[m] > 0 then wiped = true end
            end
          end
          if battN >= 3 then
            for m = 0, 1 do
              local id = H.readWord(0x57C0 + m * 2)
              if id ~= 0 and id ~= 0xFFFF then
                lastHp[m] = H.readWord(0x3BFC + m * 2)
              end
            end
            F.frame()
            return
          end
          if battN > 0 then F.idle(); H.setPad({}); return end
          F.idle()
          if map() == 219 then
            if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {})
            else H.setPad({}) end
            return
          end
          H.setPad(ph < 4 and { "a" } or {})
        end),
      }, "the reunion/Cranes ride, vanilla playbook (attempt " .. n .. ")")
    end)(),
  })
end

H.run({ maxFrames = 160000 }, {
  H.loadState("build/states/n128_won.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 240, "booted on boundary E (n128_won)")
    H.assertEq(H.fieldX(), 58, "boot x")
    H.assertEq(H.fieldY(), 7, "boot y")
  end),

  -- 1-2. FIGHT PREP, then the reunion trigger and the ride.

  H.equipEsper(0, 7, { tag = "BISMARK -> EDGAR" }),
  H.equipEsper(1, 2, { tag = "SHIVA -> SABIN" }),
  H.equipEsper(2, 19, { tag = "CARBUNKL -> LOCKE" }),
  -- Both swaps are best-effort: the fighting lineage's LOCKE already
  -- WIELDS Guardian in his Genji offhand (it is on his hand, not in the
  -- bag), and the bag's dagger spread differs from the fled lineage's.
  H.cond(function() return H.invSlotOf(0x01) ~= nil end,
    { H.equipWeapon(0, 0x01, { tag = "EDGAR MithrilKnife" }) },
    { H.logStep("no bagged MithrilKnife; EDGAR keeps his weapon") }),
  -- The Cranes ABSORB bolt ($10D) and fire ($10E): LOCKE's ThunderBlade
  -- R-hand would heal the Left Crane every swing (issue #81's absorb
  -- guard measured exactly that).  Both Cranes are pierce-weak, so the
  -- R-hand takes a plain dagger (ladder, weakest first) and Guardian
  -- stays in the offhand under his Genji Glove.
  H.cond(function() return H.invSlotOf(0x00) ~= nil end,
    { H.equipWeapon(2, 0x00, { tag = "LOCKE R-hand Dirk (no element)" }) }, {}),
  H.cond(function() return H.invSlotOf(0x01) ~= nil end,
    { H.equipWeapon(2, 0x01, { tag = "LOCKE R-hand MithrilKnife" }) }, {}),
  H.cond(function() return H.invSlotOf(0x04) ~= nil end,
    { H.equipWeapon(2, 0x04, { tag = "LOCKE R-hand ThiefKnife" }) }, {}),
  H.call(function()
    local base = 0x1600 + 37 * 1
    H.assertEq(H.readByte(base + 0x1F) ~= 0x0F, true,
      "LOCKE's R-hand is no longer the ThunderBlade (the Cranes absorb bolt)")
  end),
  H.setRows({ [1] = true, [4] = true, [5] = true }, { tag = "back row" }),
  H.call(function()
    -- key the summon table off what is actually WORN, never assumed
    local pid = H.readByte(0x1A6D)
    for c = 0, 13 do
      local b = H.readByte(0x1850 + c)
      if b ~= 0 and (b & 0x07) == pid then
        local base = 0x1600 + 37 * c
        local actor, esper = H.readByte(base) & 0x3f, H.readByte(base + 30)
        if esper == 7 then summonChars[actor] = { mp = 50 } end   -- Sea Song
        if esper == 2 then summonChars[actor] = { mp = 27 } end   -- DDust
        if esper == 19 then summonChars[actor] = { mp = 36 } end  -- Carbunkl
        H.log(string.format("[prep] c%d actor=%d esper=%02X weapon=%02X",
          c, actor, esper, H.readByte(base + 31)))
      end
    end
    local n = 0
    for _ in pairs(summonChars) do n = n + 1 end
    H.assertEq(n, 3, "three stones worn (the prep drives worked)")
  end),
  (function()
    local req
    return H.seqStep({
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "the pre-trigger retry blob")
        rideBlob = req.blob
      end),
    })
  end)(),

  L.watch(),
  rideAttempt(1), rideAttempt(2), rideAttempt(3),
  L.report(),
  H.call(function()
    H.assertEq(rideWon, true,
      "the Cranes fell and the ride reached the flashback within 3 attempts")
  end),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(map(), 219, "the Esper-World flashback (map 219)")
    H.assertEq(sw(0x006B), 1, "$006B SET -- the reunion played")
    H.log("[flashback] control as MADUIN")
  end),

  -- 3a/3b. out to the town, carry Madonna in
  H.navTo(36, 14, { playBattles = "flee", maxFrames = 6000 }),
  pressWalk("down", function() return map() == 217 end, 6000,
    "pocket exit (36,15) -> 217"),
  H.waitFrames(60),
  H.navTo(32, 12, { playBattles = "flee", maxFrames = 12000 }),
  pressTalk("up", function() return sw(0x006C) == 1 end, 20000,
    "talk (32,11) -> carry MADONNA in -> $006C"),
  H.waitFrames(90),

  -- 3c. Madonna resting -> $006E
  H.navTo(46, 43, { playBattles = "flee", maxFrames = 9000 }),
  pressTalk("up", function() return sw(0x006E) == 1 end, 25000,
    "talk MADONNA -> $006E"),
  H.waitFrames(90),

  -- 3d. to the gate (the corridor NPC ports us; the landing tile flickers)
  H.navTo(36, 14, { playBattles = "flee", maxFrames = 6000 }),
  pressWalk("down", function() return map() == 217 end, 6000,
    "pocket exit -> 217"),
  H.waitFrames(60),
  H.navTo(32, 12, { playBattles = "flee", maxFrames = 12000 }),
  pressTalk("up", function() return map() == 218 end, 15000,
    "talk (32,11) -> ported to the gate (218)"),
  H.waitFrames(90),
  pressWalk("up", function() return H.fieldY() <= 45 end, 700,
    "held UP off the inert gate trigger tile"),

  -- 3e. the confession -> $006F and the raid
  planApproach(0x1C),
  H.navTo(function() return app[1] end, function() return app[2] end,
    { playBattles = "flee", maxFrames = 9000 }),
  talkApproached(function() return sw(0x006F) == 1 end, 40000,
    "talk MADONNA at the gate -> $006F"),
  H.advanceStory(function() return map() == 219 and settled() end, 30000, { playBattles = true }),
  H.waitFrames(90),

  -- 3f. the tempest plan -> $0116
  planApproach(0x13),
  H.navTo(function() return app[1] end, function() return app[2] end,
    { playBattles = "flee", maxFrames = 9000 }),
  talkApproached(function() return sw(0x0116) == 1 end, 12000,
    "talk NPC_4 -> $0116"),
  H.waitFrames(90),

  -- 3g. the collapse -> $0117
  planApproach(0x12),
  H.navTo(function() return app[1] end, function() return app[2] end,
    { playBattles = "flee", maxFrames = 9000 }),
  talkApproached(function() return sw(0x0117) == 1 end, 12000,
    "talk the elder -> $0117"),
  H.waitFrames(90),

  -- 3h. the chase to the gate -> $0118
  H.navTo(41, 55, { playBattles = "flee", maxFrames = 9000 }),
  pressWalk("down", function() return map() == 217 end, 6000,
    "pocket exit (41,56) -> 217"),
  H.waitFrames(60),
  H.navTo(32, 7, { playBattles = "flee", maxFrames = 15000 }),
  pressWalk("up", function() return map() == 218 or sw(0x0118) == 1 end, 9000,
    "onto (32,6) -> the gate trigger"),
  H.advanceStory(function() return sw(0x0118) == 1 end, 30000, { playBattles = true }),
  H.waitFrames(60),

  -- 3i. the finale and the ride home
  planApproach(0x1C),
  H.navTo(function() return app[1] end, function() return app[2] end,
    { playBattles = "flee", maxFrames = 9000 }),
  talkApproached(function() return not H.hasControl() or map() ~= 218 end, 12000,
    "talk MADONNA -> the finale _caa4e0"),
  H.advanceStory(function()
    return map() == 6 and sw(0x02F0) == 1 and settled()
  end, 90000, { playBattles = true }),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(sw(0x02F0), 1, "$02F0 SET -- TERRA is available (the v0.6 stop line)")
    H.assertEq(sw(0x0070), 1, "$0070 SET -- the party-swap room is armed")
    H.assertEq(sw(0x016F), 1, "$016F SET -- the tutorial tail ran")
    H.log("[blackjack] Terra returned; taking off")
    H.screenshot("checkpoint_f_blackjack")
  end),

  -- 3j. pick the party up off the floor, before the save.

  H.fieldCare({ tag = "care on the deck after the Cranes" }),

  -- 4. takeoff and grounding
  H.navTo(14, 6, { playBattles = "flee", maxFrames = 6000, calmFrames = 8 }),
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
    H.screenshot("checkpoint_f_grounded")
  end),

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
    local entry = H.sym("CopyGameDataToSRAM")
    emu.addMemoryCallback(function()
      saveArg = emu.getState()["cpu.a"] & 0xff
    end, emu.callbackType.exec, entry, entry)
  end),
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
    H.log(string.format("codex witness cells (earned): elem=%02X class=%02X",
      emu.read(0x316810 + ULTROS2, emu.memType.snesMemory),
      emu.read(0x316990 + ULTROS2, emu.memType.snesMemory)))
    H.log("real Save UI wrote the terra-returned checkpoint to slot 3")
  end),
  H.waitFrames(45),
  H.call(function()
    H.assertExitContract("terra-returned-v1")
    -- RUN, and it fired.  Without the care stop above it named EDGAR at
    -- 0/448 at this exact point, which is how terra-returned-v1 came to be
    -- committed with EDGAR and SABIN dead; everything below inherited it,
    -- since gen_narshe_mission cold-Continues this battery and
    -- gen_gate_cave_save cold-Continues that one.  The corpses are made in
    -- battle 71 rather than carried in -- the fight opens at full HP -- so
    -- the answer was a care stop between the fight and the save, not a lower
    -- bar.  Same three conditions as tools/audit_party_hp.py; change the two
    -- together.
    H.assertPartyStanding("terra-returned-v1 exit")
    H.screenshot("checkpoint_f_saved")
  end),
  H.logStep(function()
    return string.format("terra-returned-v1 saved via the real Save UI at "
      .. "frame %d -- world (%d,%d), slot 3; the v0.6 stop line",
      H.frame, H.worldX(), H.worldY())
  end),
})
