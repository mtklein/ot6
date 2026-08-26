-- gen_thamasa_arrive.lua -- from checkpoint K (crescent-landing-v1, world
-- (232,150), party TERRA-LOCKE-SHADOW) to checkpoint L `thamasa-night`:
-- world outside Thamasa, $008D=1 (Strago engaged), pre-inn, party
-- unchanged, world-saveable.

-- The route, with the mechanism each beat rides (event_main.asm citations
-- from docs/design/thamasa-route.md section 1):

-- Dual boot (the gen_voyage/gen_narshe_mission shape): the normal ninja
-- graph edge is prev="crescent_landing" (H.loadState of the .mss, fast,
-- no title screen); cutting the thamasa-night-v1 checkpoint is a separate
-- by-hand invocation that cold-Continues crescent-landing-v1's SRAM
-- instead, so this script detects OT6_SRAM_CHECKPOINT and drives the
-- title/Continue menu only in that mode.  Both paths converge on the same
-- live state (world (232,150), party TERRA-LOCKE-SHADOW) before segment 1
-- starts.  Re-cutting the checkpoint is:
--     OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/crescent-landing-v1 \
--     OT6_CAPTURE_SRM=tools/tests/checkpoints/thamasa-night-v1/thamasa-night.sram \
--     tools/tests/run.sh tools/tests/gen_thamasa_arrive.lua
--     python3 tools/tests/lib/sram_checkpoint.py seal tools/tests/checkpoints/thamasa-night-v1

-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- ^ run.sh refuses, before boot, any OT6_SRAM_CHECKPOINT whose manifest
--   declares a different persistent_layout.
local H = dofile("tools/tests/lib/ot6.lua")

local SAVE_SELECT = 0x14
local ZMENUSTATE = 0x26
local saveArg = nil

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function menuUp() return H.readByte(0x0059) ~= 0 end
local function seq(steps) return H.cond(function() return true end, steps) end

local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

local VIGNETTES = { { 35, 15 }, { 25, 12 } }

-- edge-A through dialogs until settled (gen_voyage's settle)
local function settle(maxFrames, what)
  local ph = 0
  return H.driveUntil(function()
    return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
       and not H.battleLoadStarted()
  end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      H.setPad(H.dialogWaiting() and (ph < 4 and { "a" } or {}) or {})
    end),
  }, what)
end

-- held walk onto a disappearing tile (HANDOFF trap 6: navTo lands at rest,
-- so the tile that takes the party away is entered with a held press)
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

local function commitName(tag)
  local running = 0
  return seq({
    H.advanceStory(menuUp, 20000, { playBattles = "tactical" }),
    H.waitFrames(180),
    H.call(function()
      H.log(string.format(
        "[ot6] %s: naming menu open at f%d ($59=%d menu_state=$%02X) $008D=%d",
        tag, H.frame, H.readByte(0x0059), H.readByte(0x0026), sw(0x008D)))
      H.screenshot(tag)
    end),
    H.driveUntil(function()
      running = (H.eventRunning() and not menuUp()) and running + 1 or 0
      return running >= 10
    end, 1800, {
      H.pressButtons({ "start" }, 8),
      H.waitFrames(12),
    }, tag .. ": name committed, event resumed"),
  })
end

-- gen_edgar's crossDoor, ported by probe_thamasa_names with an opts.avoid
-- passthrough.  A door is a wall until CheckDoor opens it, so this is
-- navTo-a-neighbour then hold into the door; the neighbour is staged live
-- (bfsPath) rather than guessed, so either side of a door works unseen.
local DIAGSTAGE = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { -1, 1, "upright" }, { -1, -1, "downright" },
  { 1, -1, "downleft" }, { 1, 1, "upleft" },
}
local function crossDoor(sx, sy, dm, dx, dy, what, opts)
  opts = opts or {}
  local pick, startMap
  local function stage()
    if not pick then
      for _, c in ipairs(DIAGSTAGE) do
        local cx, cy, move = sx + c[1], sy + c[2], c[3]
        local press = H.movePress(move)
        if H.bfsPath(cx, cy) and (press == move or H.canStep(cx, cy, move)) then
          pick = { cx, cy, press }; break
        end
      end
      pick = pick or { sx, sy + 1, "up" }
      H.log(string.format("%s: staging (%d,%d), hold %s into (%d,%d)",
        what, pick[1], pick[2], pick[3], sx, sy))
    end
    return pick
  end
  local settled = calm(20)
  local aPhase = 0
  return seq({
    H.call(function() pick, startMap = nil, map() end),
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 9000, playBattles = "flee", avoid = opts.avoid,
        arrive = function() return map() ~= startMap end }),
    H.driveUntil(function()
      return map() ~= startMap or (H.fieldX() == dx and H.fieldY() == dy)
    end, 1800, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
        H.setPad({ [stage()[3]] = true })
      end),
    }, what),
    H.release(),
    H.waitUntil(settled, 1800, what .. ": far-side control"),
    H.waitUntil(function() return bright() >= 15 end, 900, what .. ": fade-in", 10),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(map(), dm, what .. ": landed on the right map")
      H.log(string.format("[ot6] %s: DONE (%d,%d) frame=%d", what,
        H.fieldX(), H.fieldY(), H.frame))
    end),
  })
end

-- H.openChest's shape (navTo -> closed-loop facing -> edge-A -> dismiss ->
-- treasure-bit assert + optional bag delta), with the stand/face picked
-- live via bfsPath instead of hand-guessed, the same live-staging trick
-- crossDoor uses for doors: try below/above/right/left of the
-- chest tile in turn and take the first one bfsPath says is reachable.
local CHEST_CAND = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}
local FACE_VAL = { up = 0, right = 1, down = 2, left = 3 }
local function chestAuto(cx, cy, bit, what, item, opts)
  opts = opts or {}
  local pick
  local function stage()
    if not pick then
      for _, c in ipairs(CHEST_CAND) do
        local sx, sy = cx + c[1], cy + c[2]
        if H.bfsPath(sx, sy) then pick = { sx, sy, c[3] }; break end
      end
      pick = pick or { cx, cy + 1, "up" }
      H.log(string.format("[chest] (%d,%d) %s: staging (%d,%d) face %s",
        cx, cy, what, pick[1], pick[2], pick[3]))
    end
    return pick
  end
  local tag = string.format("chest bit %d (%s)", bit, what)
  local before
  local aPh = 0
  return H.cond(function() return not H.chestOpen(bit) end, {
    H.call(function() pick = nil end),
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 15000, playBattles = "flee", avoid = opts.avoid }),
    H.call(function() before = item and H.invCountOf(item) or nil end),
    H.driveUntil(function()
      return H.readByte(0x087f + H.readWord(0x0803)) == FACE_VAL[stage()[3]]
    end, 300, {
      H.call(function() H.setPad({ [stage()[3]] = true }) end),
    }, tag .. ": faced"),
    H.release(), H.waitFrames(4),
    H.driveUntil(function() return H.dialogWaiting() end, 6000, {
      H.call(function()
        aPh = (aPh + 1) % 12
        H.setPad(aPh < 4 and { a = true } or {})
      end),
    }, tag .. ": the chest answered"),
    H.driveUntil(function() return not H.dialogWaiting() end, 600, {
      H.call(function()
        aPh = (aPh + 1) % 8
        H.setPad(aPh < 4 and { a = true } or {})
      end),
    }, tag .. ": dialog dismissed"),
    H.call(function()
      H.setPad({})
      H.assertEq(H.chestOpen(bit), true, tag .. ": treasure bit set")
      if item then
        local now = H.invCountOf(item)
        H.assertEq(now, before + 1,
          string.format("%s: bag %d -> %d of item $%02X", tag, before, now, item))
      end
      H.log("[chest] " .. tag .. ": OPENED")
    end),
  }, {
    H.call(function()
      H.log(string.format("[chest] %s: already open (rerun), skipping", tag))
    end),
  })
end

-- --------------------------------------------------------------------------
-- Dual boot: the graph edge (prev="crescent_landing") loads the .mss; a
-- by-hand checkpoint-capture run instead cold-Continues whatever SRAM
-- checkpoint run.sh materialized (crescent-landing-v1), which needs the
-- title-screen/Continue drive gen_voyage's own boot uses.  Both converge
-- on world (232,150), party TERRA-LOCKE-SHADOW.
local function envcfg(name)
  local ok, v = pcall(function() return os.getenv(name) end)
  if ok and v and v ~= "" then return v end
  return nil
end
local CHECKPOINT_BOOT = envcfg("OT6_SRAM_CHECKPOINT") ~= nil

local bootSteps
if CHECKPOINT_BOOT then
  bootSteps = {
    H.waitFrames(350),
    H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
    H.waitFrames(120),
    (function()
      local ph = 0
      local function atSite()
        return H.worldMode() and H.worldX() == 232 and H.worldY() == 150
      end
      return H.driveUntil(function() return atSite() and bright() >= 15 end,
        4000, {
        H.call(function()
          ph = (ph + 1) % 48
          if atSite() or bright() < 15 then H.setPad({}); return end
          H.setPad(ph < 8 and { "a" } or {})
        end),
      }, "Continue -> the K tile (A gated by brightness+position)")
    end)(),
    H.release(),
    H.waitUntil(function()
      return H.worldMode() and bright() >= 15 and H.worldHasControl()
    end, 1800, "world control at the K tile", 5),
  }
else
  bootSteps = {
    H.loadState("build/states/crescent_landing.mss.lua"),
  }
end

-- --------------------------------------------------------------------------
local steps = {
  bootSteps,
  H.waitFrames(30),
  H.call(function()
    H.log(string.format(
      "[ot6] boot f%d (%s) world=%s (%d,%d) party0=%02X party1=%02X party3=%02X",
      H.frame, CHECKPOINT_BOOT and "checkpoint" or "loadState",
      tostring(H.worldMode()), H.worldX(), H.worldY(),
      H.readByte(0x1850) & 7, H.readByte(0x1851) & 7, H.readByte(0x1853) & 7))
    H.assertEntryContract("crescent-landing-v1")
  end),

  -- ---- 1. care, then the world walk to the Thamasa trigger ---------------
  H.waitFrames(60),
  H.fieldCare({ tag = "care at the K tile", threshold = 0.9 }),
  H.worldNavTo(249, 128, { maxFrames = 6000, playBattles = "flee" }),
  H.call(function()
    H.log(string.format("[ot6] at (249,128) staging tile, f%d", H.frame))
  end),
  H.driveUntil(function() return not H.worldMode() end, 2000, {
    H.call(function()
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      H.setPad({ right = true })
    end),
  }, "held RIGHT onto (250,128) -> Thamasa 343 (23,46)"),
  H.release(),
  H.waitUntil(function() return map() == 343 and H.hasControl() end, 3000,
    "Thamasa map loaded", 5),
  H.call(function()
    H.log(string.format("[ot6] town entry f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
  end),

  -- ---- 2. ride the first-entry STARTUP_EVENT scene, if any ---------------
  H.advanceStory(calm(30), 20000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 343, "still on Thamasa town map")
    H.log(string.format("[ot6] town entry settled f%d (%d,%d) $007D=%d",
      H.frame, H.fieldX(), H.fieldY(), sw(0x007D)))
    H.screenshot("thamasa_town_entry")
  end),

  chestAuto(31, 37, 249, "Eyedrop", 0xF3, { avoid = VIGNETTES }),
  chestAuto(43, 30, 248, "Soft", 0xF4, { avoid = VIGNETTES }),
  chestAuto(35, 12, 247, "Green Cherry", 0xF8, { avoid = VIGNETTES }),
  chestAuto(13, 8, 246, "Echo Screen", 0xFB, { avoid = VIGNETTES }),
  chestAuto(14, 18, 250, "Fenix Down", 0xF0, { avoid = VIGNETTES }),

  crossDoor(29, 13, 349, 37, 24, "Strago house door 343(29,13)->349(37,24)",
    { avoid = VIGNETTES }),

  -- ---- 5. talk to Strago -> the two naming screens ------------------------
  H.call(function()
    H.log(string.format("[ot6] approaching Strago (obj $10) f%d", H.frame))
  end),
  H.chaseTalk(0x10, 20000, "talk Strago -> scene begins (STRAGO naming menu)",
    { done = menuUp }),
  commitName("thamasa_naming_strago"),
  commitName("thamasa_naming_relm"),
  H.advanceStory(calm(30), 30000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 343, "control returned on Thamasa town map")
    H.assertEq(H.fieldX(), 29, "scene end x (29,15)")
    H.assertEq(H.fieldY(), 15, "scene end y")
    H.assertEq(sw(0x008D), 1, "$008D -- Strago engaged")
    H.assertEq(sw(0x008E), 0, "$008E CLEAR -- no fire yet")
    H.assertEq(sw(0x0090), 0, "$0090 CLEAR -- FlameEater not fought")
    H.log(string.format(
      "[ot6] NAMING SCENE END f%d map=%d (%d,%d) $008D=%d " ..
      "party[TERRA LOCKE SHADOW]=%d %d %d frames from boot: %d",
      H.frame, map(), H.fieldX(), H.fieldY(), sw(0x008D),
      H.readByte(0x1850) & 7, H.readByte(0x1851) & 7, H.readByte(0x1853) & 7,
      H.frame))
    H.screenshot("thamasa_scene_end")
  end),

  H.navTo(21, 47, { maxFrames = 20000, playBattles = "flee", avoid = VIGNETTES }),
  pressWalk("down", function() return H.worldMode() end, 900,
    "held DOWN onto the south strip -> world (249,128)"),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
       and bright() >= 15
  end, 3600, "world control outside Thamasa", 5),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[ot6] outside Thamasa: world (%d,%d) f%d",
      H.worldX(), H.worldY(), H.frame))
    H.screenshot("thamasa_night_world")
  end),
  H.fieldCare({ tag = "care before the L save", threshold = 0.9 }),
  H.call(function()
    H.assertPartyStanding("thamasa_night exit")
    H.assertEq(H.readByte(0x11FA) & 3, 0, "ON FOOT outside Thamasa")
  end),

  -- ---- 7. the world battery save -- checkpoint L --------------------------
  H.call(function()
    H.assertExitContractPreSave("thamasa-night-v1")
  end),
  H.saveState("thamasa_night.mss"),
  (function()
    local saveReq, loadReq
    return H.cond(function() return true end, {
      H.call(function() saveReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(saveReq, "generated-state verify: capture")
        loadReq = H.requestLoadState(saveReq.blob)
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "generated-state verify: reload") end),
      H.waitFrames(180),
      H.call(function()
        H.assertEq(H.worldMode(), true, "reload: on the world map")
        H.assertEq(H.readByte(0x11FA) & 3, 0, "reload: still ON FOOT")
        H.assertEq(H.worldHasControl() and H.worldAligned(), true,
          "reload: controllable at rest")
        H.assertEq(H.battleLoadStarted(), false, "reload: no battle pending")
        H.log("generated-state verify: the reload stayed calm -- thamasa_night verified")
      end),
    })
  end)(),
  (function() local calmN, ph = 0, 0
    return H.driveUntil(function()
      calmN = (H.readByte(0x59) ~= 0) and calmN + 1 or 0
      return calmN >= 30
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 48
        if H.readByte(0x59) ~= 0 then H.setPad({}); return end
        H.setPad(ph < 6 and { "x" } or {})
      end),
    }, "world menu open outside Thamasa")
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
    H.log(string.format("codex witness cells (earned): magic0=%02X magic1=%02X",
      emu.read(0x316800, emu.memType.snesMemory),
      emu.read(0x316801, emu.memType.snesMemory)))
    H.assertExitContract("thamasa-night-v1")
    H.screenshot("thamasa_night_saved")
  end),
  H.logStep(function()
    return string.format("thamasa-night-v1 saved via the real Save UI at "
      .. "frame %d -- Strago engaged, five town chests opened, pre-inn; "
      .. "checkpoint L of v0.13", H.frame)
  end),
}

-- flatten nested step lists
local flat = {}
local function push(t)
  if type(t) == "table" and t[1] ~= nil and type(t[1]) == "table" then
    for _, s in ipairs(t) do push(s) end
  else
    flat[#flat + 1] = t
  end
end
for _, s in ipairs(steps) do push(s) end

H.run({ maxFrames = 300000 }, flat)
