-- gen_ultros.lua -- the generator that cuts battery checkpoint O,
-- `ultros-won-v1`: back at the Esper Mountain save point 375 (8,44) with
-- $0095=1 and RELM joined.

-- THE FIGHT (Ultros III, battle 125, formation 387): Ultros L25 HP 22000,
-- ABSORBS WATER, WEAK FIRE|BOLT, OT6 row-7 shields slash|pierce.  Two design
-- constraints, both read from ai_script.asm:6267-6355 and both pointing the
-- same way -- to an ALL-PHYSICAL, ELEMENTAL-WEAPON offense with item-only
-- healing:

-- Under 15360 HP Ultros self-casts Haste+Safe (Safe halves physical damage
-- taken), so the back half of the fight is slower; a deep item bag (22
-- Tonics / 9 Potions / 15 Fenix Downs at N) carries it.  The GameOver
-- read-canary (lib) is the ground-truth loss signal; a loss is a wipe the
-- segment runner retries (#311).

-- No chests: none sit on the walked route (the mountain chests are all off
-- the direct save-point<->statue-room line), so chests_opened.txt is
-- untouched and audit_chests stays exact.

-- One generator does the step and cuts the checkpoint, gen_esper_mtn's shape.

-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- ^ run.sh refuses, before boot, any OT6_SRAM_CHECKPOINT whose manifest
--   declares a different persistent_layout.
local H = dofile("tools/tests/lib/ot6.lua")

local SAVE_SELECT = 0x14
local ZMENUSTATE = 0x26
local ULTROS2 = 0x012d
local saveArg = nil

local TERRA, LOCKE, STRAGO, RELM = 0, 1, 7, 8
local FIRE_ROD, THUNDERBLADE = 0x35, 0x0F
local CONFIRM_BATTLE_GONE = 90

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function seq(steps) return H.cond(function() return true end, steps) end
local function partyOf(charId) return H.readByte(0x1850 + charId) & 0x07 end
local function charPos(charId)
  return function() return (H.readByte(0x1850 + charId) >> 3) & 0x03 end
end
-- Ultros's HP sits in the monster HP block; read it for a progress log only.
local function ultrosHp()
  local best = 0
  for i = 0, 5 do
    local h = H.readWord(0x3BFC + i * 2)
    if h > best then best = h end
  end
  return best
end

-- pressWalk: hold a direction, advancing any dialog box with A, until pred
-- (gen_thamasa_fire's shape).  Deliberately does NOT press A merely because
-- hasControl() is false: on a SavePoint trigger tile control never settles,
-- yet the party still walks -- an A there would fire the save prompt instead
-- of stepping off.  During the Ultros choreography the dialog boxes DO set
-- dialogWaiting, so A still advances them; the between-box no-control frames
-- just hold the (harmless) direction.
local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() or H.battleActive() then H.setPad({}); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

-- tapToSave (gen_esper_mtn): a held press walks through a SavePoint trigger
-- without firing it, so tap toward the tile and settle on an aligned rest.
local function tapToSave(tx, ty, maxFrames, what)
  local phase, n, ph, calm = 0, 0, 0, 0
  local W = H.newWalkFighter("tapToSave: " .. what)
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
      if W.frame() then phase = 0; return end
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

-- =============================================================== the FIGHT ==
-- #311: one fight, played once.  This file used to carry its own five-rung
-- seed sweep (H.newSeedSweep): an in-run snapshot at the trigger and up to
-- four reloads at spread battle seeds, the same plan each time, its losses
-- invisible to the retry audit.  A lost Ultros III now raises the wipe it is
-- (the runner's class=wipe), and the segment runner's standard bounded retry
-- -- the boot snapshot, a moved seed, a counted `[retry]` line -- is the only
-- reload.
local function ultrosFight()
  local F = H.newFightDriver("Ultros III", { tactical = true, boost = true,
    bank = 3, items = true, cure = false, healPercent = 45 })
  local notBattle, giveUp = 0, 0
  local function lost(what)
    error(string.format("Ultros III (battle 125): THE PARTY IS WIPED -- %s, f%d",
      what, H.frame), 0)
  end
  return seq({
    H.logStep(function()
      return string.format("Ultros III at f%d", H.frame)
    end),
    -- step down onto (15,22): the Ultros trigger.  pressWalk advances the
    -- choreography + RELM-join dialog with A and exits when the battle module
    -- takes the screen.
    pressWalk("down", function()
      return H.battleLoadStarted() or H.battleActive() or sw(0x0095) == 1
    end, 8000, "walk onto 371 (15,22) until Ultros III (battle 125) starts"),
    -- PHASE 1: drive tactically until the battle module is confirmed gone for
    -- CONFIRM_BATTLE_GONE consecutive frames, or the GameOver read-canary
    -- fires (the ground-truth loss signal).
    H.driveUntil(function()
      if H.gameOverFired > 0 then return true end
      if H.battleLoadStarted() or H.battleActive() then notBattle = 0
      else notBattle = notBattle + 1 end
      return notBattle >= CONFIRM_BATTLE_GONE
    end, 3000000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        F.frame()
      end),
    }, "Ultros III fight"),
    H.call(function()
      H.log(string.format("[Ultros III] phase 1 done, f%d, gameOverFired=%d " ..
        "ultrosHp=%d", H.frame, H.gameOverFired, ultrosHp()))
      if H.gameOverFired > 0 then
        lost("GameOver read-fired (event GameOver, $CC/E568)")
      end
    end),
    -- PHASE 2: mash A through the win tail until $0095 flips (or a GameOver
    -- shows itself).  $0095 is set only by the real post-fight script (:73801)
    -- -- esper-mtn-save-v1 leaves it 0, so ==1 cannot be confused with a
    -- reloaded save.
    H.driveUntil(function()
      if H.gameOverFired > 0 then return true end
      giveUp = giveUp + 1
      return sw(0x0095) == 1 or giveUp >= 11800
    end, 12000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        local ph = (giveUp % 8)
        if not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "the win tail flips $0095 (or a real GameOver shows itself)"),
    -- WIN VERIFICATION: gameOverFired stayed 0, $0095 flipped, and the roster
    -- is sane (TERRA and RELM both present -- a reload to esper-mtn-save-v1
    -- would drop RELM, who joins only in this scene).
    H.call(function()
      H.setPad({})
      if H.gameOverFired > 0 then
        lost("GameOver read-fired in the win tail")
      end
      H.assertEq(sw(0x0095) == 1 and partyOf(TERRA) ~= 0 and partyOf(RELM) ~= 0,
        true, string.format("Ultros III's win verified ($0095=%d partyOf(TERRA)=%d " ..
          "partyOf(RELM)=%d)", sw(0x0095), partyOf(TERRA), partyOf(RELM)))
      H.log(string.format("Ultros III BEATEN, f%d, map=%d pos=(%d,%d) partyRELM=%d",
        H.frame, map(), H.fieldX(), H.fieldY(), partyOf(RELM)))
    end),
  })
end

-- --------------------------------------------------------------------------
H.run({ maxFrames = 5000000, allowGameOver = true }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  (function() local cnt = 0
    return H.waitUntil(function()
      local ok = map() == 375 and H.tileAligned() and bright() >= 15
             and not H.dialogWaiting() and not H.battleLoadStarted()
      cnt = ok and cnt + 1 or 0
      return cnt >= 10
    end, 4000, "cold Continue to the map-375 save tile (boundary N)", 10)
  end)(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[ot6] boot f%d map=%d (%d,%d) $0097=%d $0095=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0097), sw(0x0095)))
    H.assertEntryContract("esper-mtn-save-v1")
  end),

  -- ---- 1. PREP: off the trigger, Fire Rod onto TERRA, full-heal ----------
  -- Walk off the save-point re-entry tile first: its trigger re-fires every
  -- frame, so H.hasControl() never settles there and the equip menu's
  -- back-out drive could not finish (gen_vector_crash's own note).  LEFT
  -- reaches (7,44) in one tile, off the trigger; (6,44) is a wall and the
  -- west route bends down to y=45 (probe_ultros_save375), so this only steps
  -- clear here and hands the bend to navTo below.  The pred does NOT require
  -- hasControl(): it is false ON the trigger and becomes true one tile off.
  pressWalk("left", function()
    return H.fieldX() <= 7 and H.tileAligned() and not H.dialogWaiting()
  end, 3000, "step LEFT off the save-point re-entry tile"),
  H.release(),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
       and not H.dialogWaiting() and not H.battleLoadStarted()
  end, 3000, "settled off the save trigger", 5),
  -- Both swaps are best-effort chip optimization, not win conditions: the
  -- espers end this fight on the script's schedule regardless of break
  -- state (bosses-wob.md par.17).  On the fighting run the bag's one
  -- ThunderBlade rides LOCKE's Genji off-hand, and a person would not
  -- strip a party member's hand to arm another; absent from the bag,
  -- each wearer keeps their current weapon, with a log.
  H.cond(function() return H.invSlotOf(THUNDERBLADE) ~= nil end, {
    H.equipWeapon(charPos(TERRA), THUNDERBLADE,
      { slot = 0, tag = "ThunderBlade -> TERRA" }),
    H.call(function()
      H.assertEq(H.readByte(0x1600 + 37 * TERRA + 0x1F), THUNDERBLADE,
        "TERRA wields the ThunderBlade (bolt weakness)")
    end),
  }, {
    H.logStep("ThunderBlade -> TERRA: not in this run's bag; " ..
      "TERRA keeps her current weapon"),
  }),
  H.cond(function() return H.invSlotOf(FIRE_ROD) ~= nil end, {
    H.equipWeapon(charPos(STRAGO), FIRE_ROD,
      { slot = 0, tag = "Fire Rod -> STRAGO (swaps out his Ice Rod)" }),
    H.call(function()
      H.assertEq(H.readByte(0x1600 + 37 * STRAGO + 0x1F), FIRE_ROD,
        "STRAGO wields the Fire Rod (fire weakness, unshielded bludgeon)")
    end),
  }, {
    H.logStep("Fire Rod -> STRAGO: not in this run's bag; " ..
      "STRAGO keeps his current weapon"),
  }),
  H.fieldCare({ tag = "prep full-heal at the save region", threshold = 1.0 }),

  -- ---- 2. the WEST door 375 (2,45) -> 371 (9,9) --------------------------
  H.navTo(2, 45, { maxFrames = 20000, playBattles = "tactical",
    avoid = { { 15, 17 }, { 12, 46 }, { 11, 51 }, { 17, 49 } },
    arrive = function() return map() ~= 375 end }),
  H.release(),
  H.waitUntil(function()
    return map() == 371 and H.hasControl() and bright() >= 15
       and H.tileAligned() and not H.dialogWaiting()
  end, 6000, "warp into the statue room 371", 10),
  H.waitFrames(45),
  H.call(function()
    H.log(string.format("[ot6] in 371 f%d (%d,%d) $0097=%d $0095=%d",
      H.frame, H.fieldX(), H.fieldY(), sw(0x0097), sw(0x0095)))
    H.assertEq(map(), 371, "in the statue room (map 371)")
  end),

  -- ---- 3. the statue-lore scene (15,20), then Ultros III (15,22) ---------
  -- Stage above the lore trigger (column 15 is a clear walk down, per
  -- probe_ultros_route), then step down onto (15,20) to fire the lore scene.
  H.navTo(15, 17, { maxFrames = 12000, playBattles = "tactical",
    arrive = function() return sw(0x0097) == 1 end }),
  H.release(),
  pressWalk("down", function() return sw(0x0097) == 1 end, 6000,
    "walk onto 371 (15,20): the statue-lore scene ($0096/$0097)"),
  H.waitUntil(function()
    return sw(0x0097) == 1 and H.hasControl() and bright() >= 15
       and H.tileAligned() and not H.dialogWaiting() and not H.battleLoadStarted()
  end, 8000, "lore scene resolved, control back in 371", 10),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(sw(0x0097), 1, "$0097 SET -- the statue lore scene ran")
    H.assertEq(sw(0x0095), 0, "$0095 CLEAR -- Ultros III not fought yet")
    H.log(string.format("[ot6] lore seen f%d (%d,%d)",
      H.frame, H.fieldX(), H.fieldY()))
  end),
  ultrosFight(),
  H.call(function()
    H.assertEq(sw(0x0095), 1, "$0095 SET -- Ultros III beaten")
    H.assertEq(partyOf(RELM) ~= 0, true, "RELM is in the party")
    H.screenshot("ultros_won_scene")
  end),

  -- ---- 4. back out to the save point 375 (8,44) --------------------------
  -- The return door 371 (10,9) -> 375 (3,45).
  H.advanceStory(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
       and not H.dialogWaiting() and not H.battleLoadStarted()
  end, 8000, { playBattles = "tactical" }),
  H.navTo(10, 9, { maxFrames = 20000, playBattles = "tactical",
    avoid = { { 15, 20 }, { 15, 22 } },
    arrive = function() return map() ~= 371 end }),
  H.release(),
  H.waitUntil(function()
    return map() == 375 and H.hasControl() and bright() >= 15
       and H.tileAligned() and not H.dialogWaiting()
  end, 6000, "back on 375 in the save-point region", 10),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(map(), 375, "back on the mountain exterior (map 375)")
    H.log(string.format("[ot6] back on 375 f%d (%d,%d) $0095=%d",
      H.frame, H.fieldX(), H.fieldY(), sw(0x0095)))
  end),
  H.navTo(9, 44, { maxFrames = 20000, playBattles = "tactical",
    avoid = { { 15, 17 }, { 12, 46 }, { 11, 51 }, { 17, 49 } } }),
  H.release(),

  H.fieldCare({ tag = "care before the ultros-won save", threshold = 1.0 }),
  tapToSave(8, 44, 9000, "tap onto the Esper Mountain save point 375 (8,44)"),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(map(), 375, "on the mountain exterior (map 375)")
    H.assertEq(sw(0x01BF), 1, "$01BF SET -- the SavePoint script ran")
    H.assertEq(sw(0x0632), 1, "$0632 SET -- the standing save-sparkle switch")
    H.assertExitContractPreSave("ultros-won-v1")
    H.assertPartyStanding("ultros-won-v1 exit")
    H.screenshot("ultros_won_save_tile")
  end),
  -- THE STEP'S SAVESTATE IS GENERATED HERE, on the save tile, before the menu
  H.saveState("ultros_won.mss"),

  -- ---- 5. the real Save UI, slot 3 (gen_esper_mtn's flow) ----------------
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
    H.assertExitContract("ultros-won-v1")
    H.screenshot("ultros_won_saved")
  end),
  H.logStep(function()
    return string.format("ultros-won-v1 saved via the real Save UI at frame "
      .. "%d -- map 375 (8,44), slot 3; boundary O of the v0.13 range",
      H.frame)
  end),
})
