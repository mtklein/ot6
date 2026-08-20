-- gen_esper_mtn.lua -- v0.13 step M->N (issue #127, docs/design/thamasa-
-- route.md Segment 5), and the generator that cuts battery checkpoint N,
-- `esper-mtn-save-v1`: the Esper Mountain save point at map 375 (8,44),
-- pre-statues.
--
-- The step: cold-Continue the tracked `fire-out-v1` battery (boundary M,
-- world (249,128), party TERRA LOCKE STRAGO, Strago wearing the Ice Rod
-- picked up in the burning house), assert its contract, then:
--   1. care (the fire-out checkpoint is already full HP/MP), then the world
--      walk from (249,128) west to the Esper Mountain world entrance 0 at
--      (229,130) -> map 375 (55,31).  playBattles="flee": Crescent Island
--      world trash (Baskervor L22 HP750 / Chimera L22 HP2237, both
--      no-weakness -- thamasa-route.md Segment 1) has no element this
--      L15-17 party can exploit, so the owner doctrine's "AoE weakness
--      offense" does not apply to it and fleeing avoids a pointless attrition
--      fight, the same call gen_thamasa_arrive's own world walk made;
--   2. the mountain warp-maze (measured: probe_esper_mtn_map /
--      probe_esper_mtn_route, and short_entrance.dat maps 371-375).  375's
--      exterior is walled into disconnected components joined only by cave
--      warps; the save-point region (containing 375 (8,44)/(2,45)) is
--      reachable ONLY through the statue room 371.  The route (see the `hop`
--      helper's own header): 375 (55,31) -> cave 373 -> 375 comp17 -> statue
--      room 371 (crossed pre-statue, north corridor) -> 375 (3,45) -> the
--      save point.  Fights are FLEE-ed: this is a transit to a save point,
--      and the L23-24 group-89/90 trash outlevels the L15-17 party with no
--      element it can exploit for a quick kill, so fleeing (the world walk's
--      and gen_gate_cave's transit pattern) is safer and faster than an
--      attrition fight the route does not need to win; care() full-heals
--      before the save, and the fire-weakness offense the owner doctrine
--      names is for the mandatory bosses (the statue room's Ultros III is the
--      NEXT segment, checkpoint O), not this random trash;
--   3. the vanilla save point at 375 (8,44): tapInto, because a HELD press
--      walks straight through a SavePoint trigger without firing it (the
--      gen_gate_cave_save / gen_n024 measurement); tap toward the tile and
--      settle so CheckEventTriggers fires $01BF;
--   4. the ordinary Save UI into slot 3; run.sh captures the battery.
--
-- No chests: the X-Potion (372 (41,34)) and the other mountain chests sit in
-- the cave branches (372/373/374) or off the direct line (Heal Rod 375
-- (46,27), ~6 tiles north of the SW crossing), not on the walked route to
-- the save point, so the #84 chest rule does not reach them and
-- chests_opened.txt is untouched (audit_chests stays exact).
--
-- One generator does the step and cuts the checkpoint, gen_gate_cave_save's
-- shape (an SRAM-boot walk to an interior save point ending in a real
-- battery save).
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- ^ run.sh refuses, before boot, any OT6_SRAM_CHECKPOINT whose manifest
--   declares a different persistent_layout.
local H = dofile("tools/tests/lib/ot6.lua")

local SAVE_SELECT = 0x14
local ZMENUSTATE = 0x26
local ULTROS2 = 0x012d
local saveArg = nil

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function seq(steps) return H.cond(function() return true end, steps) end

-- The 375 exterior is a warp-maze (probe_esper_mtn_map / probe_esper_mtn_route,
-- short_entrance.dat maps 371-375): the save-point region (containing 375
-- (8,44)/(2,45)) is a walled-off component reachable ONLY through the statue
-- room 371, and the landing region (55,31) reaches it only via cave 373 then
-- comp17.  The measured route, each leg a short_entrance warp fired by
-- stepping on its SrcPos tile (entrance.asm CheckShortEntrance, no direction
-- test), traversed pre-statue with $0097 clear throughout:
--
--   375 (55,31) landing --(60,16)-->  373 (15,23)
--   373 (15,23)         --(25,15)-->  375 (42,62)  [rides the (20,17)
--                                     esper-glimpse vignette, a harmless
--                                     one-shot cutscene on the only path]
--   375 (42,62)         --(53,62)-->  371 (19,15)  [statue room, north door]
--   371 (19,15)         --(10,9) -->  375 (3,45)   [AVOID the statue lore
--                                     trigger (15,20) and Ultros (15,22):
--                                     the north-corridor path clears both]
--   375 (3,45)          --walk--->    375 (8,44)   [the save point]
--
-- Fights are FLEE-ed: the mountain trash is L23-24 group-89/90 against an
-- L15-17 party, and this is a transit to a save point, not a fight the route
-- needs to win (the transit-to-save flee pattern of gen_gate_cave / the
-- world walk).  care() full-heals before the save; the fire-weakness offense
-- the owner doctrine names is for the mandatory bosses (the statue room's
-- Ultros III is next segment, checkpoint O), not this random trash.

-- hop: walk onto a short_entrance SrcPos tile and confirm the warp fired
-- (the map id changed), then settle on the far side.
local function hop(sx, sy, fromMap, what, avoid)
  return seq({
    H.navTo(sx, sy, { maxFrames = 40000, playBattles = "flee", avoid = avoid,
      arrive = function() return map() ~= fromMap end }),
    H.release(),
    H.waitUntil(function()
      return map() ~= fromMap and H.hasControl() and bright() >= 15
         and H.tileAligned() and not H.dialogWaiting()
    end, 6000, what, 10),
    H.waitFrames(45),
    H.call(function()
      H.log(string.format("[hop] %s -> map=%d (%d,%d) $0097=%d $0095=%d",
        what, map(), H.fieldX(), H.fieldY(), sw(0x0097), sw(0x0095)))
    end),
  })
end

-- Tap onto a SavePoint tile: a held press walks through it without firing
-- the trigger (gen_gate_cave_save's measured note), so tap toward the tile
-- from wherever the approach left the party and settle on an aligned rest.
local function tapToSave(tx, ty, maxFrames, what)
  local phase, n, ph, calm = 0, 0, 0, 0
  local function calmPred()
    return H.tileAligned() and not H.dialogWaiting() and not H.battleLoadStarted()
  end
  local function pred()
    return H.fieldX() == tx and H.fieldY() == ty and sw(0x01BF) == 1
  end
  local function dirToward()
    local dx, dy = tx - H.fieldX(), ty - H.fieldY()
    if math.abs(dx) >= math.abs(dy) then return dx > 0 and "right" or "left"
    else return dy > 0 and "down" or "up" end
  end
  return H.driveUntil(function()
    calm = (pred() and calmPred()) and calm + 1 or 0
    return calm >= 8
  end, maxFrames or 12000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true }); phase = 0; return
      end
      if H.dialogWaiting() then
        H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
      end
      if phase == 0 then
        H.setPad({})
        if pred() then return end
        if calmPred() then phase, n = 1, 0 end
        return
      end
      if phase == 1 then
        n = n + 1
        H.setPad({ [dirToward()] = true })
        if n >= 8 then phase, n = 2, 0 end
        return
      end
      H.setPad({})
      n = n + 1
      if n >= 24 then phase = 0 end
    end),
  }, what)
end

-- --------------------------------------------------------------------------
H.run({ maxFrames = 500000 }, {
  -- ---- the cold Continue and the ENTRY CONTRACT (issue #25) --------------
  -- fire-out-v1 cold-Continues onto the WORLD map at (249,128) (probe_state,
  -- gen_thamasa_fire's own boot).
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    local function atSite()
      return H.worldMode() and H.worldX() == 249 and H.worldY() == 128
    end
    return H.driveUntil(function() return atSite() and bright() >= 15 end,
      6000, {
      H.call(function()
        ph = (ph + 1) % 48
        if atSite() or bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "cold Continue -> the M tile world (249,128)")
  end)(),
  H.release(),
  H.waitUntil(function()
    return H.worldMode() and bright() >= 15 and H.worldHasControl()
  end, 1800, "world control at the M tile", 5),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[ot6] boot f%d world=%s (%d,%d) party0=%02X 1=%02X 7=%02X",
      H.frame, tostring(H.worldMode()), H.worldX(), H.worldY(),
      H.readByte(0x1850) & 7, H.readByte(0x1851) & 7, H.readByte(0x1857) & 7))
    H.assertEntryContract("fire-out-v1")
  end),

  -- ---- 1. care, then the world walk to the mountain entrance -------------
  H.fieldCare({ tag = "care at the M tile", threshold = 1.0 }),
  H.worldNavTo(229, 130, { maxFrames = 40000, playBattles = "flee",
    arrive = function() return not H.worldMode() end }),
  H.release(),
  H.waitUntil(function() return map() == 375 and H.hasControl() end, 4000,
    "Esper Mountain 375 loaded", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[ot6] mountain entry f%d map=%d (%d,%d) $0098=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0098)))
    H.assertEq(map(), 375, "on the Esper Mountain exterior (map 375)")
    H.screenshot("esper_mtn_entry")
  end),

  -- ---- 2. the warp route across the mountain to the save region ---------
  H.advanceStory(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
       and not H.dialogWaiting() and not H.battleLoadStarted()
  end, 8000, { playBattles = "flee" }),
  hop(60, 16, 375, "375(60,16) -> 373"),
  hop(25, 15, 373, "373(25,15) -> 375 comp17 (rides the (20,17) vignette)"),
  hop(53, 62, 375, "375(53,62) -> 371 statue room"),
  -- the statue room crossing: AVOID the lore trigger (15,20) and Ultros
  -- (15,22) so N stays pre-statue ($0097=0); the north corridor clears both.
  hop(10, 9, 371, "371(19,15..10,9) -> 375 (3,45) save region",
    { { 15, 20 }, { 15, 22 } }),
  H.call(function()
    H.assertEq(map(), 375, "back on 375 in the save-point region")
    H.assertEq(sw(0x0097), 0, "$0097 CLEAR -- the statue room was crossed pre-statue")
    H.assertEq(sw(0x0095), 0, "$0095 CLEAR -- Ultros III was not fought")
  end),
  -- stage one tile east of the save tile (the (2,45)..(8,44) corridor runs
  -- E-W; (9,44) is on it), leaving the tap onto (8,44) to tapToSave
  H.navTo(9, 44, { maxFrames = 20000, playBattles = "flee",
    avoid = { { 15, 17 }, { 12, 46 }, { 11, 51 }, { 17, 49 } } }),
  H.release(),
  H.call(function()
    H.log(string.format("[ot6] near the save point f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
  end),

  -- ---- 3. onto the save point 375 (8,44) --------------------------------
  H.fieldCare({ tag = "care before the esper-mtn save", threshold = 1.0 }),
  tapToSave(8, 44, 9000, "tap onto the Esper Mountain save point 375 (8,44)"),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(map(), 375, "on the Esper Mountain exterior (map 375)")
    H.assertEq(sw(0x01BF), 1, "$01BF SET -- the SavePoint script ran")
    H.assertEq(sw(0x01B5), 1, "$01B5 SET -- the once-per-tile latch took")
    H.assertEq(sw(0x0632), 1, "$0632 SET -- the standing save-sparkle switch")
    H.assertExitContractPreSave("esper-mtn-save-v1")
    H.assertPartyStanding("esper-mtn-save-v1 exit")
    H.screenshot("esper_mtn_save_tile")
  end),
  -- THE STEP'S SAVESTATE IS GENERATED HERE, on the save tile, before the menu
  H.saveState("esper_mtn_save.mss"),

  -- ---- 4. the real Save UI, slot 3 --------------------------------------
  -- $0059 BLIPS nonzero on a save tile (the SavePoint re-entry); a real menu
  -- is 30 CONSECUTIVE frames of it (the gen_n024 / gate_cave pattern).
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
    }, "field menu open on the save tile")
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
  end),
  (function() local calm = 0
    return H.driveUntil(function()
      calm = (H.readByte(0x59) == 0) and calm + 1 or 0
      return calm >= 30
    end, 900, {
      H.pressButtons({ "b" }, 4), H.waitFrames(20),
    }, "field menu closed")
  end)(),
  H.waitFrames(45),
  H.call(function()
    H.assertExitContract("esper-mtn-save-v1")
    H.screenshot("esper_mtn_saved")
  end),
  H.logStep(function()
    return string.format("esper-mtn-save-v1 saved via the real Save UI at "
      .. "frame %d -- map 375 (8,44), slot 3; boundary N of the v0.13 range",
      H.frame)
  end),
})
