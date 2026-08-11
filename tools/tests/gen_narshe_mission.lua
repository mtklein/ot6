-- gen_narshe_mission.lua -- v0.7 LEG F->G (issue #31), and the generator
-- that cuts battery anchor G, `narshe-mission-v1`.
--
-- The leg: cold-Continue the tracked `terra-returned-v1` battery (boundary
-- F, the v0.6 stop line), assert its contract, board the parked Blackjack,
-- fly to Narshe, walk the mission-meeting scene to `$0076=1`, walk back out
-- to the world map, and save through the game's OWN Save UI at the Narshe
-- exit spawn -- world (84,34) -- which is boundary G.
--
-- WHAT THE RECON GOT RIGHT, AND WHAT IT COULD NOT KNOW.  The route recon's
-- leg-1 entry (docs/design/sealed-gate-recon.md, since trimmed) called this
-- leg "fly to Narshe, walk the mission meeting"; the corrections below are
-- this pass's own measurements and supersede it:
--  * The escort trigger row IS (37-39,51) on map 20 and the meeting IS on
--    map 30; `$0076=1` at event_main.asm:94170 is the handoff, measured.
--  * The recon says "fly to Narshe" but not HOW.  Measured this pass
--    (probe_v07_fly, probe_v07_f2g):
--      - a cold Continue of anchor F puts the party ON FOOT standing on the
--        parked ship's tile (the F-anchor Continue behavior, asserted
--        below and by battle_slotsboot.lua);
--      - ONE A tap boards AND lifts off in a single beat -- there is no
--        separate "board" state to wait for.  The flight view zeroes
--        $E0/$E2 (the on-foot world position cells), so "airborne" is
--        `$E0==0 and $E2==0` and the SHIP tile is word($34)>>4, word($38)>>4;
--      - a bare d-pad in flight ROTATES the ship and never translates it;
--        Y+direction STRAFES.  That is gen_terra_returned_anchor's landing
--        idiom, and it is the ONLY way to fly a planned course;
--      - B over a tile whose live prop byte $c2 has bit1 clear grounds the
--        ship; the party is then in the parked state again and one step in
--        any walkable direction puts them on foot.
--  * (83-85,34-36) beside the Narshe gate is landable -- confirmed live at
--    (84,36), one tile south of the (84,33) short entrance's approach row.
--
-- Anchor G is a WORLD battery save, so it needs no authoring (the
-- 2-trigger ROM budget stays untouched).  The save happens at the
-- Narshe exit spawn because that tile is where a cold Continue of the
-- anchor will put the party -- the leg OUT of G starts there.
--
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
-- ^ the persistent-SRAM layout this leg understands (issue #25).  run.sh
--   reads the marker line above and refuses -- BEFORE the emulator boots,
--   naming both strings -- any OT6_SRAM_ANCHOR whose manifest.json declares
--   a different persistent_layout.
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
local function shipX() return H.readWord(0x34) >> 4 end
local function shipY() return H.readWord(0x38) >> 4 end

-- gen_vector_doorstep's grind-and-replan world walker: no edge is ever
-- condemned, so a battle-restored tile is simply retried (the gen_opera1
-- lesson -- worldNavTo reads a battle's snapshot/restore as a dead edge).
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

-- STRAFE-fly the ship to hover tile (tx,ty).  Y is load-bearing: without it
-- the presses only turn the ship (measured, probe_v07_fly -- 240 held frames
-- per direction moved word($34)/word($38) not at all while $29/$2E carried
-- angular velocity).  The terminator wants 90 consecutive frames ON the
-- tile so a decaying strafe cannot carry the ship off the goal unseen.
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

H.run({ maxFrames = 40000 }, {
  -- ---- the cold Continue and the ENTRY CONTRACT (issue #25) -------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue to the terra-returned world doorstep", 10),
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
    -- the F-anchor Continue behavior, measured: the party is restored ON
    -- FOOT on the parked ship's tile even though the save was taken
    -- aboard.  This leg's first move depends on it.
    H.assertEq(H.readByte(0x11FA) & 3, 0, "$11FA -- restored ON FOOT")
    H.assertEq(H.readByte(0x11F3), 0, "$11F3 -- not forced aboard")
    H.assertEq(H.worldX(), 24, "boot world x")
    H.assertEq(H.worldY(), 121, "boot world y")
    H.assertEq(shipX(), 24, "the Blackjack is parked under the party (x)")
    H.assertEq(shipY(), 121, "the Blackjack is parked under the party (y)")
  end),

  -- ---- board + lift off (one A tap does both) ---------------------------
  H.pressButtons({ "a" }, 8),
  H.waitUntil(function()
    return H.readByte(0xe0) == 0 and H.readByte(0xe2) == 0
  end, 900, "liftoff (the flight view zeroes $E0/$E2)", 5),
  H.waitFrames(240),
  H.call(function()
    H.log(string.format("[airborne] ship=(%d,%d)", shipX(), shipY()))
    H.screenshot("leg_fg_airborne")
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
    H.screenshot("leg_fg_grounded")
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
  worldGrind(84, 34, "world walk -> the Narshe doorstep (84,34)"),
  -- (84,33) is the short entrance -> map 20 (38,61); a tile that takes the
  -- party away is entered with a HELD press, never with a walker aimed at
  -- it (the #22 / gen_vector_doorstep lesson).
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

  -- ---- the escort trigger row and the mission meeting --------------------
  -- The trigger row is (37-39,51) (event_trigger.asm:114-116); park two
  -- tiles below it and enter with a held press, then ride the scene.
  H.navTo(38, 53, { honest = "flee", maxFrames = 12000 }),
  pressWalk("up", function() return map() == 30 or not H.hasControl() end,
    2400, "held UP onto the escort trigger row (38,51)"),
  H.advanceStory(function() return map() == 30 and sw(0x0076) == 1 end, 60000, { honest = true }),
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
    H.screenshot("leg_fg_meeting")
  end),

  -- ---- out of Narshe to the world map ------------------------------------
  H.navTo(110, 25, { honest = "flee", maxFrames = 12000,
    arrive = function() return map() == 20 end }),
  pressWalk("down", function() return map() == 20 end, 1200,
    "door 30 (110,26) -> map 20 (18,24)"),
  H.waitUntil(function()
    return map() == 20 and H.hasControl() and H.tileAligned() and bright() >= 15
  end, 1800, "map 20 control", 5),
  H.waitFrames(30),
  H.navTo(18, 61, { honest = "flee", maxFrames = 20000,
    arrive = function() return H.worldMode() end }),
  pressWalk("down", function() return H.worldMode() end, 1200,
    "the map-20 south-edge long entrance -> the world map"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
       and H.worldX() == 84 and H.worldY() == 34
  end, 2400, "back on the world at (84,34), the anchor-G tile", 5),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(H.worldX(), 84, "anchor-G tile x")
    H.assertEq(H.worldY(), 34, "anchor-G tile y")
    H.log(string.format("[G tile] $1f64=%04X $1f66=%02X%02X ship=(%d,%d)",
      H.readWord(0x1f64), H.readByte(0x1f67), H.readByte(0x1f66),
      shipX(), shipY()))
    -- everything the boundary declares except the sram witnesses, which
    -- only the save itself can put into the battery
    H.assertExitContractPreSave("narshe-mission-v1")
    H.screenshot("leg_fg_g_tile")
  end),
  -- THE LEG'S SAVESTATE IS MINTED HERE, BEFORE THE MENU -- not after.  The
  -- WORLD menu does not unwind on B (measured: 900 frames of edge-pressed B
  -- left $0059 nonzero; gen_terra_returned_anchor recorded the same for the
  -- grounded-airship world menu and simply never closed it).  So the only
  -- playable frame this generator can capture is the one before the save
  -- UI opens; the save itself is proven by the FULL exit contract below,
  -- asserted with the menu open, and by the 32 KiB battery run.sh captures
  -- on shutdown.
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
    }, "world menu open on foot at the anchor-G tile")
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
    H.log("real Save UI wrote the narshe-mission anchor to slot 3")
    -- THE FULL exit contract, sram included, at the boundary save moment.
    -- Asserted with the menu still open: like the anchor-F boundary, every
    -- declared field reads from cells the menu leaves intact ($1f60/$1f61
    -- rather than $e0/$e2 -- the #29 module-overlay class).
    H.assertExitContract("narshe-mission-v1")
    H.screenshot("leg_fg_saved")
  end),

  H.logStep(function()
    return string.format("narshe-mission-v1 saved via the real Save UI at "
      .. "frame %d -- world (%d,%d), slot 3; boundary G of the v0.7 band",
      H.frame, H.worldX(), H.worldY())
  end),
})
