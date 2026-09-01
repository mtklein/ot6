-- gen_massacre.lua -- the generator that cuts battery checkpoint P,
-- `thamasa-done-v1`: world (249,128), party TERRA LOCKE STRAGO RELM,
-- $009D=1, beside the repaired Blackjack.

-- No chests on the massacre route (audit_chests stays exact at 58).

-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- ^ run.sh refuses, before boot, any OT6_SRAM_CHECKPOINT whose manifest
--   declares a different persistent_layout.
local H = dofile("tools/tests/lib/ot6.lua")

local SAVE_SELECT = 0x14
local ZMENUSTATE = 0x26
local ULTROS2 = 0x012d
local saveArg = nil

local TERRA, LOCKE, STRAGO, RELM, WEDGE = 0, 1, 7, 8, 14

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function seq(steps) return H.cond(function() return true end, steps) end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end

-- care: a full-heal stop that skips (logged) rather than hangs when the
-- field isn't settled.
local function care(what)
  return seq({
    H.waitUntilSoft(function()
      return H.hasControl() and H.tileAligned() and bright() >= 15
         and not H.dialogWaiting() and not H.battleLoadStarted()
    end, 1200, "care " .. what),
    H.cond(function()
      return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
         and not H.battleLoadStarted()
    end, {
      H.waitFrames(45),
      H.fieldCare({ tag = "care " .. what, threshold = 1.0 }),
    }, {
      H.logStep(function()
        return string.format("[care %s] SKIPPED -- not settled at (%d,%d) map %d",
          what, H.fieldX(), H.fieldY(), map())
      end),
    }),
  })
end

-- hop: navTo a warp/shortcut SrcPos (arrive when `arriveFn` fires -- a map
-- change, or a same-map teleport detected by position), settle, log.
local function hop(sx, sy, arriveFn, what)
  return seq({
    H.navTo(sx, sy, { maxFrames = 40000, playBattles = "tactical",
      arrive = arriveFn }),
    H.release(),
    H.waitUntil(function()
      return arriveFn() and H.hasControl() and bright() >= 15
         and H.tileAligned() and not H.dialogWaiting()
    end, 6000, what, 10),
    H.waitFrames(45),
    H.call(function()
      H.log(string.format("[climb] %s -> map=%d (%d,%d) $0097=%d $0099=%d",
        what, map(), H.fieldX(), H.fieldY(), sw(0x0097), sw(0x0099)))
    end),
  })
end

-- rideScene: advance a scripted cutscene/theater stretch -- edge-A whenever the
-- field is not in settled player control (dialog boxes, message pages, theater
-- battle victory pages), nothing while in control -- until `pred`.
local function rideScene(pred, maxF, tag)
  local ph = 0
  return H.driveUntil(pred, maxF, {
    H.call(function()
      ph = (ph + 1) % 8
      -- in a real fight we must NOT mash A blindly; but the massacre's other
      -- battles (105/97) are scripted theater that A pages through.  This
      -- helper is only used OUTSIDE battle 124 (driven separately).
      if H.hasControl() and H.tileAligned() and not H.dialogWaiting()
         and not H.battleLoadStarted() and not H.battleActive() then
        H.setPad({})
      else
        H.setPad(ph < 4 and { "a" } or {})
      end
    end),
  }, tag)
end

-- lossReload: restore the pre-battle-124 blob and clear the GameOver counter.
local function lossReload(blobFn, tag)
  local req
  return seq({
    H.call(function() req = H.requestLoadState(blobFn()) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, tag .. ": loss-reload")
      H.gameOverFired = 0
      H.log(string.format("[%s] loss-reload done, GameOver cleared, f%d",
        tag, H.frame))
    end),
    H.waitFrames(90),
  })
end

-- ============================================================ battle 124 ==
local L124 = H.newSeedLadder("Kefka vs Leo (battle 124)", { attempts = 5 })
local leoBlob, leoWon = nil, false
local CONFIRM_GONE = 90

local function leoAttempt(n)
  local F = H.newFightDriver("Kefka vs Leo", { tactical = true, boost = true,
    bank = 3, items = true, cure = false, healPercent = 50 })
  local notBattle, giveUp = 0, 0
  return H.cond(function() return leoWon end, {}, {
    H.logStep(function()
      return string.format("battle 124 attempt %d at f%d", n, H.frame)
    end),
    n > 1 and seq({
      lossReload(function() return leoBlob end, "battle 124"),
    }) or seq({}),
    L124.spread(n),
    H.hold({ "up" }), H.waitFrames(6), H.release(), H.waitFrames(8),
    (function() local ph = 0
      return H.driveUntil(function()
        return H.battleLoadStarted() or H.battleActive()
      end, 4000, {
        H.call(function()
          ph = (ph + 1) % 16
          if H.battleLoadStarted() or H.battleActive() then H.setPad({}); return end
          H.setPad(ph < 4 and { "a" } or {})
        end),
      }, "edge-A into the Kefka NPC -> battle 124")
    end)(),
    H.waitUntil(function() return H.battleActive() end, 3000, "battle 124 up", 10),
    -- PHASE 1: drive the fight until the battle module is gone for
    -- CONFIRM_GONE frames, or the GameOver read-canary fires (loss).
    H.driveUntil(function()
      if H.gameOverFired > 0 then return true end
      if H.battleLoadStarted() or H.battleActive() then notBattle = 0
      else notBattle = notBattle + 1 end
      return notBattle >= CONFIRM_GONE
    end, 3000000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        F.frame()
      end),
    }, "battle 124, Leo solo (attempt " .. n .. ")"),
    H.call(function()
      H.log(string.format("[battle 124] phase1 done, attempt %d, f%d, "
        .. "gameOverFired=%d map=%d", n, H.frame, H.gameOverFired, map()))
    end),
    H.call(function()
      H.setPad({})
      if H.gameOverFired == 0 and partyOf(WEDGE) ~= 0 then
        leoWon = true
        H.log(string.format("battle 124 WON on attempt %d, f%d map=%d "
          .. "(Leo lives, no GameOver)", n, H.frame, map()))
        H.screenshot("battle124_won")
      else
        H.log(string.format("battle 124 attempt %d LOST -- gameOverFired=%d "
          .. "partyWEDGE=%d, f%d", n, H.gameOverFired, partyOf(WEDGE), H.frame))
      end
    end),
    H.cond(function() return not leoWon end, {
      lossReload(function() return leoBlob end, "battle 124"),
    }, {}),
  })
end

-- --------------------------------------------------------------------------
H.run({ maxFrames = 6000000, allowGameOver = true }, {
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
    end, 4000, "cold Continue to the map-375 save tile (boundary O)", 10)
  end)(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[ot6] boot f%d map=%d (%d,%d) $0095=%d $0099=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0095), sw(0x0099)))
    H.assertEntryContract("ultros-won-v1")
  end),

  -- ---- 1. PREP: full-heal at the save region ----------------------------
  -- step LEFT off the save re-entry tile first (its trigger re-fires
  -- every frame, so hasControl never settles on it).
  (function() local ph = 0
    return H.driveUntil(function()
      return H.fieldX() <= 7 and H.tileAligned() and not H.dialogWaiting()
    end, 3000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({ left = true })
      end),
    }, "step LEFT off the save tile")
  end)(),
  H.release(),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
       and not H.dialogWaiting()
  end, 3000, "settled off the save trigger", 5),
  H.fieldCare({ tag = "prep full-heal at the save region", threshold = 1.0 }),

  -- ---- 2. THE CLIMB: save comp -> shortcut -> 372 -> the massacre pocket -
  -- leg 1: the (11,51) $0097 shortcut retiles and teleports to 375 (39,51),
  -- the SE compartment that owns the 372 (45,41) door.
  hop(11, 51, function() return H.fieldX() >= 30 and map() == 375 end,
    "375(11,51) $0097 shortcut -> the SE compartment (39,51)"),
  H.call(function()
    H.assertEq(map(), 375, "still on the mountain (map 375) after the shortcut")
    H.assertEq(H.fieldX() >= 30, true, "teleported east of the save compartment")
  end),
  -- leg 2: the SE compartment -> cave 372 via 375 (45,41).
  hop(45, 41, function() return map() == 372 end,
    "375(45,41) -> cave 372 (51,17)"),
  H.call(function()
    H.assertEq(map(), 372, "crossed into cave 372")
  end),
  -- leg 3: 372 (40,19) -> the massacre pocket 375 (16,9).
  hop(40, 19, function() return map() == 375 end,
    "372(40,19) -> the massacre pocket 375 (16,9)"),
  H.call(function()
    H.assertEq(map(), 375, "back on 375 in the massacre pocket (comp 2)")
    H.log(string.format("[ot6] in the pocket f%d (%d,%d)",
      H.frame, H.fieldX(), H.fieldY()))
  end),
  H.navTo(15, 17, { maxFrames = 20000, playBattles = "tactical",
    arrive = function()
      return sw(0x0099) == 1 or map() == 341 or H.battleLoadStarted()
    end }),
  H.release(),
  H.waitFrames(90),
  H.call(function()
    H.log(string.format("[ot6] massacre trigger fired f%d map=%d $0099=%d $018A=%d",
      H.frame, map(), sw(0x0099), sw(0x018A)))
    H.assertEq(sw(0x0099) == 1 or map() == 341, true,
      "the massacre chain fired ($0099=1 or town 341 loaded)")
  end),

  -- ---- 3. ride the chain to solo Leo at 341 (22,22) ---------------------
  rideScene(function()
    return map() == 341 and H.hasControl() and H.tileAligned()
       and bright() >= 15 and not H.dialogWaiting() and not H.battleLoadStarted()
       and partyOf(WEDGE) ~= 0 and partyOf(TERRA) == 0
  end, 120000, "ride the massacre cutscene to solo Leo at 341"),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(map(), 341, "in the locked town (map 341)")
    H.assertEq(sw(0x018A), 1, "$018A SET -- Kefka's Magitek entrance ran")
    H.assertEq(partyOf(WEDGE) ~= 0, true, "Leo (WEDGE actor) is the solo party")
    H.assertEq(partyOf(TERRA), 0, "TERRA is benched")
    H.log(string.format("[ot6] solo Leo control f%d (%d,%d)",
      H.frame, H.fieldX(), H.fieldY()))
    H.screenshot("massacre_solo_leo")
  end),

  -- ---- 4. approach the Kefka NPC (24,18); battle 124 seed ladder --------
  -- Stage at (24,19), one tile below Kefka, avoiding the exit-row triggers
  -- (x=9 col; y=45-46; x=24-28 y=15-16) that fire battle 75 in the Leo
  -- window.  navTo the approach tile, then capture the pre-battle-124 blob.
  H.navTo(24, 19, { maxFrames = 15000, playBattles = "tactical",
    avoid = { { 9, 28 }, { 9, 29 }, { 9, 30 }, { 9, 31 }, { 9, 32 }, { 9, 33 },
              { 9, 34 }, { 24, 16 }, { 25, 16 }, { 27, 16 }, { 28, 15 },
              { 24, 15 }, { 25, 15 } } }),
  H.release(),
  H.waitUntil(function()
    return map() == 341 and H.hasControl() and H.tileAligned()
       and bright() >= 15 and not H.dialogWaiting() and not H.battleLoadStarted()
  end, 6000, "staged below the Kefka NPC", 10),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[ot6] staged for battle 124 at (%d,%d)",
      H.fieldX(), H.fieldY()))
  end),
  (function()
    local ckReq
    return seq({
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "pre-battle-124 checkpoint")
        leoBlob = ckReq.blob
        H.log("[ot6] pre-battle-124 savestate captured")
      end),
    })
  end)(),
  L124.watch(),
  leoAttempt(1),
  leoAttempt(2),
  leoAttempt(3),
  leoAttempt(4),
  leoAttempt(5),
  H.call(function()
    if not leoWon then
      error(L124.report() .. " -- all 5 battle-124 seed-ladder attempts lost "
        .. "(GameOver each); the per-attempt numbers above are the balance "
        .. "finding (#74-style; a solo-guest wall for the owner) -- do not "
        .. "touch enemy stats", 0)
    end
    H.log(L124.report())
  end),

  -- ---- 5. ride the scripted tail to world (249,128) ---------------------
  -- $009B=1, theater battle 105, the esper flyover, reload 341, Kefka's drain,
  -- theater battle 97 (scripted -- A pages it), Leo's death, party restore,
  -- grave 340 ($009C=1), burial, the Blackjack, the roster re-normalize,
  -- $009D=1, control at world (249,128).  All scripted: rideScene drives A.
  rideScene(function()
    return sw(0x009D) == 1 and H.worldMode() and H.worldHasControl()
       and H.worldX() == 249 and H.worldY() == 128
  end, 300000, "ride the theater tail to world (249,128)"),
  H.release(),
  H.waitUntil(function()
    return H.worldMode() and bright() >= 15 and H.worldHasControl()
  end, 3000, "world control at (249,128)", 5),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[ot6] world control f%d (%d,%d) $009B=%d $009C=%d "
      .. "$009D=%d", H.frame, H.worldX(), H.worldY(), sw(0x009B), sw(0x009C),
      sw(0x009D)))
    H.assertEq(sw(0x009B), 1, "$009B SET -- Leo fell")
    H.assertEq(sw(0x009C), 1, "$009C SET -- the burial ran")
    H.assertEq(sw(0x009D), 1, "$009D SET -- the v0.13 area tail ran")
    H.assertEq(sw(0x02F3), 0, "$02F3 CLEAR -- Shadow unavailable")
    H.assertEq(partyOf(TERRA) ~= 0 and partyOf(LOCKE) ~= 0
      and partyOf(STRAGO) ~= 0 and partyOf(RELM) ~= 0, true,
      "party restored to TERRA LOCKE STRAGO RELM")
    H.assertEq(partyOf(WEDGE), 0, "Leo (WEDGE) is gone")
    H.screenshot("thamasa_done_world")
  end),

  -- ---- 6. full-heal, then the real world Save UI, slot 3 ----------------
  H.fieldCare({ tag = "full-heal before the thamasa-done save", threshold = 1.0 }),
  H.call(function()
    H.assertExitContractPreSave("thamasa-done-v1")
    H.assertPartyStanding("thamasa-done-v1 exit")
  end),
  H.saveState("thamasa_done.mss"),

  -- world save: open the field menu with X, Save, slot 3.  On the world
  -- map $0059 is 0 with the menu closed and nonzero once it is open.
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
    }, "field menu open on the world map")
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
    H.assertExitContract("thamasa-done-v1")
    H.screenshot("thamasa_done_saved")
  end),
  H.logStep(function()
    return string.format("thamasa-done-v1 saved via the real Save UI at frame "
      .. "%d -- world (249,128), slot 3; boundary P, the v0.13 TERMINAL",
      H.frame)
  end),
})
