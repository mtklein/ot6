-- gen_terra_returned_checkpoint.lua -- generate SRAM checkpoint F,
-- `terra-returned-v1` (the A-F save-point boundary range is lettered in
-- tools/tests/savestate_graph.py): the WHOLE E->F step in one run, from
-- n128_won (the nearest generated predecessor, parked on boundary E) to a
-- world-map battery save one takeoff after Terra's return.  This step
-- cannot be split legally -- a save inside the Esper-World flashback would
-- save as the WEDGE-actor Maduin with the roster rewritten -- so the
-- checkpoint gen IS the step.
--
-- The route, every step measured on the probe ladder (2026-07-27):
--  1. 240 (58,7) -> (54,40) -> held LEFT onto the reunion trigger column
--     x=52 (approached from the EAST along row 40; §4.4's (52,36..38)
--     candidates are NOT walkable live).
--  2. The Setzer reunion auto-plays onto the Blackjack deck (map 6),
--     battle 71 (Cranes, 010D+010E) FOUGHT AND WON WITH REAL INPUT
--     (2026-08-10, probe_cranes_water's playbook -- see the prep block
--     below; the original July generator write-cleared this fight, and the
--     interim record called it unwinnable off a Thunder-Blade loadout bug),
--     then the non-interactive flights to Zozo and into the flashback:
--     control as the WEDGE-actor MADUIN at 219 (34,10).
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
-- See gen_mrf_save_room_checkpoint.lua for the codex-witness seeding and the
-- $307ff0 sentinel this file reuses.
local H = dofile("tools/tests/lib/ot6.lua")
-- The ride ladder's spread and its collision check (issue #83): each attempt
-- is held until the game-time frame counter the battle seed is made of
-- reaches its own phase, and L.report() fails if two attempts drew one seed,
-- which would make this ladder one Cranes fight played twice.
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

-- The ride ladder (probe_cranes_water's measured shape).  Each attempt:
-- reload the pre-trigger blob (attempt 1 skips -- it IS that state), walk
-- onto the reunion trigger, and ride the scene with the fight driver;
-- battles go to the driver, non-battle frames edge-A on map 6 and go
-- NEUTRAL on 219 (the flashback's start tile sits by the Esper-world
-- save point -- blind A there re-opens the save query forever, the first
-- budget-burn run's 55k-frame lesson).  A wipe is detected off the LAST
-- in-battle monster HP samples -- never the teardown table, which reads
-- $FFFF everywhere and once turned a measured WIN into a "wipe".
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

-- 160000: the July budget (60000) was sized for 3-frame battle-clear-write
-- fights;  the input-driven ride is ~13k to the flashback
-- (probe_cranes_water: fight open f7452, both Cranes dead ~f15250,
-- flashback f19772 with ~5.5k of menu prep in front), the flashback chain +
-- takeoff + save measured ~55k more in July, and the ladder may burn two
-- wiped attempts (~15k each) before its win.
H.run({ maxFrames = 160000 }, {
  H.loadState("build/states/n128_won.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 240, "booted on boundary E (n128_won)")
    H.assertEq(H.fieldX(), 58, "boot x")
    H.assertEq(H.fieldY(), 7, "boot y")
  end),

  -- 1-2. FIGHT PREP, then the reunion trigger and the ride.
  --
  -- THE WALL, RESOLVED (2026-08-10, probe_cranes_water -- superseding the
  -- "unwinnable in normal play as tuned" record that stood here; the full
  -- wall history lives in that file's header and probe_cranes_wedge's):
  -- the wall was a LOADOUT bug, not balance.  H.equipOptimum had armed
  -- LOCKE and EDGAR with THUNDER BLADES ($0F: slash, LIGHTNING), and the
  -- Left Crane ABSORBS lightning (monster_prop +23 = $04) -- every Fight
  -- healed the boss and walked its Giga Volt counter (_269's if_element
  -- LIGHTNING ladder).  The prior wipe timelines' "chip pace vs survival"
  -- arithmetic was measured on a party feeding the boss.
  --
  -- The vanilla playbook, all through real menus, wins attempt 1 of the
  -- standard ladder (probe_cranes_water PASS f19772; Left dead ~b+4400,
  -- Right broken and dead ~b+7500):
  --   * BISMARK->EDGAR (Sea Song, the designed water key: bosses-wob 16),
  --     SHIVA->SABIN (Diamond Dust), CARBUNKL->LOCKE (party Rflect --
  --     the Cranes' whole normal rotation is reflectable);
  --   * DAGGERS for both swingers (OT6_PIERCE = the Cranes' class weak:
  --     element-clean AND shield-chipping);
  --   * back row for all three (Blitz/summons/items are row-exempt);
  --   * driver: healer=SETZER (the 4th rider the reunion adds; the bag
  --     is 15 Tonics and an all-medic line heal-locks), tools=false
  --     (AutoCrossbow splash feeds both if_hit retal counters), bank 2,
  --     focus on the Left Crane (mask $01 = slot 0, measured by the
  --     probe's delta logger), cadence 12.
  -- SETZER keeps whatever row/kit he joins with -- he cannot be prepped.
  H.equipEsper(0, 7, { tag = "BISMARK -> EDGAR" }),
  H.equipEsper(1, 2, { tag = "SHIVA -> SABIN" }),
  H.equipEsper(2, 19, { tag = "CARBUNKL -> LOCKE" }),
  H.equipWeapon(0, 0x01, { tag = "EDGAR MithrilKnife" }),
  H.equipWeapon(2, 0x02, { tag = "LOCKE Guardian" }),
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

  -- The ride, as a 3-attempt phase-spread ladder (the doctrine).  Some shift
  -- between attempts has always been necessary: the first two July cut
  -- attempts crashed the EMULATOR at the identical battle frame twice,
  -- because same inputs = same deterministic trajectory.  The shift used to
  -- be a 7-frame base plus 37 per attempt; it is now taken from the game-time
  -- frame counter the battle seed is actually made of, and checked (#83).
  L.watch(),
  rideAttempt(1), rideAttempt(2), rideAttempt(3),
  -- Before the verdict, not after: three attempts are evidence only if they
  -- were three DIFFERENT rides -- distinct battle RNG seeds on the first
  -- battle after each attempt's spread -- and if they were not, that is what
  -- this run should report rather than "lost all three" (#83).
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
    H.log("real Save UI wrote the terra-returned checkpoint to slot 3")
  end),
  -- The exit contract is asserted WITH THE MENU OPEN, the post-opera
  -- precedent: the grounded-airship world menu does not unwind on B the
  -- way the field menus do (measured -- 900 frames of B left $59 set),
  -- and every declared field reads from WRAM/SRAM cells the menu leaves
  -- intact ($1f64, $e0/$e2, $1E80.., $1850, bank $31).
  H.waitFrames(45),
  H.call(function()
    H.assertExitContract("terra-returned-v1")
    -- terra-returned-v1 as committed hands over EDGAR at 0/448 and SABIN at
    -- 0/457, and this generator has no care stop and had no exit contract on
    -- the party, so it wrote them out without a word.  Everything below
    -- inherits it: gen_narshe_mission boots this and used to carry both
    -- corpses into narshe-mission-v1, which gen_gate_cave_save boots in
    -- turn.  They arrive already down rather than dying here -- the boot
    -- state is n128_won, and #92 records that fight being retuned to a win
    -- the party "arrives worse" from -- so when this fires the answer is a
    -- care stop before the save, not a lower bar.  Same three conditions as
    -- tools/audit_party_hp.py; change the two together.
    --
    -- NOT EXECUTED.  This generator needs the deep chain down to n128_won,
    -- which is hours, so this line is compiled and loaded but has never run.
    -- The identical line in gen_narshe_mission was run and passes.
    H.assertPartyStanding("terra-returned-v1 exit")
    H.screenshot("checkpoint_f_saved")
  end),
  H.logStep(function()
    return string.format("terra-returned-v1 saved via the real Save UI at "
      .. "frame %d -- world (%d,%d), slot 3; the v0.6 stop line",
      H.frame, H.worldX(), H.worldY())
  end),
})
