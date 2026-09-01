-- gen_narshe_mission.lua -- the generator that cuts battery checkpoint G,
-- `narshe-mission-v1`.

-- The step: cold-Continue the tracked `terra-returned-v1` battery (boundary
-- F, the v0.6 stop line), assert its contract, board the parked Blackjack,
-- fly to Narshe, walk the mission-meeting scene to `$0076=1`, walk back out
-- to the world map, and save through the game's own Save UI at the Narshe
-- exit spawn, world (84,34), which is boundary G.

-- Checkpoint G is a world battery save, so it needs no authoring (the
-- 2-trigger ROM budget stays untouched).  The save happens at the
-- Narshe exit spawn because that tile is where a cold Continue of the
-- checkpoint puts the party, and the step out of G starts there.

-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local saveArg = nil
local SAVE_SELECT = 0x14
local ULTROS2 = 0x012d
local TEMP_ELEM = 0x316c10 + ULTROS2
local TEMP_CLASS = 0x316d90 + ULTROS2

local function map() return H.mapId() & 0x1ff end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function maxLvl()
  local m = 0
  for c = 0, 15 do
    if partyOf(c) ~= 0 then
      local l = H.readByte(0x1600 + 37 * c + 8)
      if l > m then m = l end
    end
  end
  return m
end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function shipX() return H.readWord(0x34) >> 4 end
local function shipY() return H.readWord(0x38) >> 4 end

-- gen_vector_entry's grind-and-replan world walker: no edge is ever
-- condemned, so a battle-restored tile is retried (the gen_opera1
-- finding: worldNavTo reads a battle's snapshot/restore as a dead edge).
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

-- unconditional held walk (dialogs/battles absorbed); for trigger tiles and
-- scripted stretches where control flickers
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

local function flyTo(tx, ty)
  local calm, hb = 0, -300
  return H.driveUntil(function()
    calm = (shipX() == tx and shipY() == ty) and calm + 1 or 0
    return calm >= 90
  end, 20000, {
    H.call(function()
      if H.frame - hb >= 300 then
        hb = H.frame
        H.log(string.format("[fly] f%d ship=(%d,%d) $c2=%02X",
          H.frame, shipX(), shipY(), H.readByte(0xc2)))
      end
      local dx, dy = tx - shipX(), ty - shipY()
      if dx == 0 and dy == 0 then H.setPad({}); return end
      local pad = { y = true }
      if dx > 0 then pad.right = true elseif dx < 0 then pad.left = true end
      if dy > 0 then pad.down = true elseif dy < 0 then pad.up = true end
      H.setPad(pad)
    end),
  }, string.format("strafe-fly to (%d,%d)", tx, ty))
end

H.run({ maxFrames = 480000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue to the terra-returned world entry point", 10),
  H.waitUntil(function() return bright() >= 15 end, 900,
    "cold Continue fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    local t = {}
    for c = 0, 13 do t[#t + 1] = string.format("%02X", H.readByte(0x1850 + c)) end
    H.log("[roster] $1850+0..13 = " .. table.concat(t, " ")
      .. string.format("  $1EDE=%02X $1EDF=%02X", H.readByte(0x1EDE),
        H.readByte(0x1EDF)))
    H.assertEntryContract("terra-returned-v1")
    H.assertEq(H.readByte(0x11FA) & 3, 0, "$11FA -- restored ON FOOT")
    H.assertEq(H.readByte(0x11F3), 0, "$11F3 -- not forced aboard")
    H.assertEq(H.worldX(), 24, "boot world x")
    H.assertEq(H.worldY(), 121, "boot world y")
    H.assertEq(shipX(), 24, "the Blackjack is parked under the party (x)")
    H.assertEq(shipY(), 121, "the Blackjack is parked under the party (y)")
  end),

  -- ---- the sanctioned grind, on the Vector plains ------------------------
  -- Six measured Sealed-Gate cave wipes with the complete kit say that
  -- area is a leveling gate at L18, and BOTH its approach pockets are
  -- door-to-door shelves with no pacing ground (censused) -- you arrive
  -- leveled or you don't.  The last open ground before it is right here:
  -- the plains under the parked Blackjack.  The engine censuses its own
  -- pacing pair; level-ups full-restore (the OT6 rule) so the loop
  -- part-sustains; capped legs; goal 21 (level-curve.md's
  -- reasonable-grind rule, which also narrows the documented FC gap).
  (function()
    local ax, ay, bx, by
    local steps = {
      H.call(function()
        local reach = {}
        for y = 112, 130, 2 do
          for x = 14, 40, 2 do
            if not (x == 24 and y == 121) then
              local p = H.worldBfs(x, y)
              if p then reach[#reach + 1] = { x, y, #p } end
            end
          end
        end
        H.assertEq(#reach >= 2, true, "the plains census found pacing ground")
        table.sort(reach, function(u, v) return u[3] > v[3] end)
        ax, ay = reach[1][1], reach[1][2]
        bx, by = reach[#reach][1], reach[#reach][2]
        H.log(string.format("[grind] pacing (%d,%d) <-> (%d,%d) "
          .. "(census: %d reachable; best level %d)", ax, ay, bx, by,
          #reach, maxLvl()))
      end),
    }
    for leg = 1, 80 do
      steps[#steps + 1] = H.cond(function() return maxLvl() < 23 end, {
        H.worldNavTo(function() return leg % 2 == 1 and ax or bx end,
                     function() return leg % 2 == 1 and ay or by end, {
          maxFrames = 45000, playBattles = "tactical",
          careThreshold = 0.7, healPercent = 45,
          -- probe_locke_bolt: this party has NO learned spells (magic
          -- opts would silently degrade to Fight), but three stones are
          -- worn -- Locke Carbunkl, Edgar Bismark, Sabin Shiva -- so the
          -- once-per-fight genju is the party's whole magic game.
          summon = { [1] = {}, [4] = {}, [5] = {} } }),
      }, {})
    end
    return H.cond(function() return true end, steps)
  end)(),
  H.call(function()
    H.log(string.format("[grind] done: best level %d", maxLvl()))
    H.assertEq(maxLvl() >= 22, true, "the plains grind reached at least L22")
  end),
  worldGrind(24, 121, "back onto the parked ship (24,121)"),

  -- ---- board + lift off (one A tap does both) ---------------------------
  H.pressButtons({ "a" }, 8),
  H.waitUntil(function()
    return H.readByte(0xe0) == 0 and H.readByte(0xe2) == 0
  end, 900, "liftoff (the flight view zeroes $E0/$E2)", 5),
  H.waitFrames(240),
  H.call(function()
    H.log(string.format("[airborne] ship=(%d,%d)", shipX(), shipY()))
    H.screenshot("step_fg_airborne")
  end),

  -- ---- fly to Narshe and land beside the gate ---------------------------
  flyTo(84, 36),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(shipX(), 84, "hovering over the Narshe landing tile (x)")
    H.assertEq(shipY(), 36, "hovering over the Narshe landing tile (y)")
    H.assertEq(H.readByte(0xc2) & 0x02, 0,
      "$c2 bit1 CLEAR -- (84,36) is airship-landable (LandAirship, "
      .. "ff6/src/world/init.asm)")
  end),
  H.pressButtons({ "b" }, 8),
  H.waitUntil(function() return H.worldX() ~= 0 or H.worldY() ~= 0 end,
    1200, "the ship grounds (world position cells rewritten)", 10),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(H.worldX(), 84, "grounded x")
    H.assertEq(H.worldY(), 36, "grounded y")
    H.screenshot("step_fg_grounded")
  end),

  -- ---- disembark and walk into Narshe -----------------------------------
  (function() local ph = 0
    return H.driveUntil(function()
      return H.worldX() == 84 and H.worldY() == 35 and H.worldAligned()
    end, 1200, {
      H.call(function() ph = (ph + 1) % 8; H.setPad({ up = true }) end),
    }, "step off the grounded ship UP to (84,35)")
  end)(),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(0x11FA) & 3, 0, "on foot beside the ship")
  end),
  worldGrind(84, 34, "world walk -> the Narshe entry point (84,34)"),
  pressWalk("up", function() return not H.worldMode() and map() == 20 end,
    1200, "held UP onto (84,33) -> NARSHE (map 20)"),
  H.waitUntil(function()
    return map() == 20 and H.hasControl() and H.tileAligned() and bright() >= 15
  end, 1800, "Narshe control", 5),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 20, "Narshe exterior is map 20")
    H.assertEq(H.fieldX(), 38, "Narshe arrival x (short entrance 0 (84,33))")
    H.assertEq(H.fieldY(), 61, "Narshe arrival y")
    H.assertEq(sw(0x0076), 0, "$0076 CLEAR -- the mission meeting is ahead")
  end),

  H.fieldCare({ tag = "care on arrival in Narshe", threshold = 0.55 }),

  -- ---- the escort trigger row and the mission meeting --------------------
  -- The trigger row is (37-39,51) (event_trigger.asm:114-116); park two
  -- tiles below it and enter with a held press, then ride the scene.
  H.navTo(38, 53, { playBattles = "flee", maxFrames = 12000 }),
  pressWalk("up", function() return map() == 30 or not H.hasControl() end,
    2400, "held UP onto the escort trigger row (38,51)"),
  H.advanceStory(function() return map() == 30 and sw(0x0076) == 1 end, 60000, { playBattles = true }),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
       and not H.dialogWaiting()
  end, 6000, "control after the mission meeting", 5),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 30, "the meeting is on map 30 (upper Narshe)")
    H.assertEq(sw(0x0076), 1,
      "$0076 SET -- the mission handoff (event_main.asm:94170)")
    H.assertEq(sw(0x064E), 1, "$064E SET -- the meeting scene latch")
    H.assertEq(sw(0x045E), 0,
      "$045E CLEAR -- the Imperial-Base soldier NPCs were withdrawn "
      .. "(:94171-94180)")
    H.log(string.format("[meeting] done at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("step_fg_meeting")
  end),

  -- ---- out of Narshe to the world map ------------------------------------
  H.navTo(110, 25, { playBattles = "flee", maxFrames = 12000,
    arrive = function() return map() == 20 end }),
  pressWalk("down", function() return map() == 20 end, 1200,
    "door 30 (110,26) -> map 20 (18,24)"),
  H.waitUntil(function()
    return map() == 20 and H.hasControl() and H.tileAligned() and bright() >= 15
  end, 1800, "map 20 control", 5),
  H.waitFrames(30),
  H.navTo(18, 61, { playBattles = "flee", maxFrames = 20000,
    arrive = function() return H.worldMode() end }),
  pressWalk("down", function() return H.worldMode() end, 1200,
    "the map-20 south-edge long entrance -> the world map"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
       and H.worldX() == 84 and H.worldY() == 34
  end, 2400, "back on the world at (84,34), the checkpoint-G tile", 5),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(H.worldX(), 84, "checkpoint-G tile x")
    H.assertEq(H.worldY(), 34, "checkpoint-G tile y")
    H.log(string.format("[G tile] $1f64=%04X $1f66=%02X%02X ship=(%d,%d)",
      H.readWord(0x1f64), H.readByte(0x1f67), H.readByte(0x1f66),
      shipX(), shipY()))
    -- everything the boundary declares except the sram witnesses, which
    -- only the save itself can put into the battery
    H.assertExitContractPreSave("narshe-mission-v1")
    H.assertPartyStanding("narshe_mission exit")
    H.screenshot("step_fg_g_tile")
  end),
  H.saveState("narshe_mission.mss"),

  -- ---- the real Save UI, slot 3 ------------------------------------------
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
    }, "world menu open on foot at the checkpoint-G tile")
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
    H.log("real Save UI wrote the narshe-mission checkpoint to slot 3")
    H.assertExitContract("narshe-mission-v1")
    H.screenshot("step_fg_saved")
  end),

  H.logStep(function()
    return string.format("narshe-mission-v1 saved via the real Save UI at "
      .. "frame %d -- world (%d,%d), slot 3; boundary G of the v0.7 range",
      H.frame, H.worldX(), H.worldY())
  end),
})
