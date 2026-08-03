-- @suite frontier=worldmap_narshe slow
-- codex_ctx.lua -- a battle entered from the world map AFTER a menu save
-- selects the SAVED game's codex page, not the transient page (issue #29).
--
-- THE GUARANTEE THIS PINS.  Ot6CodexActive (ff6/src/battle/ot6_codex.asm)
-- picks the per-save codex page by reading $7e021f, and its three callers
-- all run in BATTLE context (ot6_break.asm:86/:849/:949).  $021f is a menu
-- module variable, so issue #29 asked whether any other module overlays it
-- between the menu's lifecycle write and the battle's read.  The 2026-07-28
-- audit measured the full module matrix (field/world/battle/menu, fresh and
-- loaded, pre- and post-menu, pre- and post-save) and found the cell held
-- the lifecycle value at every consumer read in every player-shaped flow:
-- $021f has exactly four writers, all menu lifecycle moments
-- (menu_common.asm:250, field_menu.asm:2925/:2963, save.asm:50), the world
-- module's DP swap covers only $0000-$00FF (world/init.asm:1446-1516), and
-- the menu's own clock tick stops at $021e (menu_common.asm:3494-3522, .a8).
-- The overlay measured in issue #29 (value 5, then a 36/37 oscillation) was
-- reproduced ONLY under codex_saveas's then-forced-ZMENUSTATE save drive
-- (since converted to pad input), whose corrupted exit path left menu tasks
-- running -- not in any real flow.
--
-- THE DRIVE.  worldmap_narshe (fresh chain, never saved: lifecycle 0) ->
-- walk to (64,77) by Figaro -> open the menu and save into empty slot 3
-- through the REAL Save command, driven by PAD INPUT ONLY (save-drive rule,
-- tools/tests/README: UP wraps the main-menu cursor to Save, A runs
-- SelectMainMenuOption_06 itself, field_menu.asm:3641-3651; bare
-- ZMENUSTATE=$13 corrupts the exit path) ->
-- stage DISTINGUISHABLE knowledge directly in SRAM: every species knows
-- FIRE in the slot-3 page and ICE in the transient page -> close the menu
-- back to the world -> walk into a desert encounter -> at battle entry,
-- every present monster's revealed-element state must carry FIRE (the
-- saved page surfaced) and not ICE (the transient page did not).  If any
-- module had overlaid $021f between the save and the battle, Ot6CodexActive
-- would fall back to the transient page and the assertions invert.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/worldmap_narshe.mss.lua"

local ZMENUSTATE = 0x26
local MAIN_MENU = 0x05
local SAVE_SELECT = 0x14
local SLOT3_ELEM, TEMP_ELEM = 0x316810, 0x316c10
local N_SPECIES = 384

local function sram(a) return emu.read(a, emu.memType.snesMemory) end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end
local function worldReady()
  return (H.readWord(0x1f64) & 0x03ff) < 3
     and H.readByte(0x0019) == 0
     and (H.readByte(0x00e7) & 0x01) == 0
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(worldReady, 500, "world-map control", 5),

  -- Park by Figaro, off the Narshe entrance tile: closing a world menu ends
  -- in ReloadMap, which re-fires the entrance under the party's feet
  -- (measured: closing on the fixture tile dropped the party into a town).
  H.worldNavTo(64, 77, { maxFrames = 15000 }),

  -- Open the menu and enter save select the way a player does: pad input
  -- only, per the save-drive rule (tools/tests/README;
  -- probe_banquet_timer_save is the template).  The old drive imitated
  -- SelectMainMenuOption_06's writes by hand; pressing A on the Save row
  -- runs the routine itself, which is strictly more honest about the very
  -- thing this test pins (menu lifecycle vs. $021f).
  H.pressButtons({ "x" }, 4),
  H.waitFrames(120),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == MAIN_MENU end,
    300, "main menu", 5),
  -- UP wraps the main-menu cursor from Items straight to Save (row 6).
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == MAIN_MENU and H.readByte(0x4b) == 6
  end, 600, {
    H.pressButtons({ "up" }, 4), H.waitFrames(16),
  }, "main-menu cursor on Save"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    600, "save-slot selection", 5),
  -- Walk the slot cursor to slot 3 by pad, gating on a read-back of the
  -- cursor -- no cursor pokes, no checksum-cache pokes.  Slot 3 is empty in
  -- this fresh run so it saves instantly; the press-A driveUntil would carry
  -- through an overwrite confirm all the same.
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == SAVE_SELECT and H.readByte(0x4b) == 2
  end, 600, {
    H.pressButtons({ "down" }, 4), H.waitFrames(16),
  }, "save cursor on slot 3"),
  H.pressButtons({ "a" }, 4),
  H.driveUntil(function() return sram(0x307ff0) == 3 end, 900, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "first save into slot 3"),
  H.call(function()
    H.assertEq(sram(0x307ff0), 3, "SRAM last-saved-slot marker is 3")
    H.assertEq(sram(0x316800), 0x4f, "slot 3 codex magic 'O'")
    H.assertEq(sram(0x316801), 0x38, "slot 3 codex magic '8'")
    -- Stage the page discriminator: slot 3 knows FIRE for every species,
    -- the transient page knows ICE.  Whichever page the battle's seed
    -- merges from is then visible in the monsters' revealed-element state.
    for i = 0, N_SPECIES - 1 do
      emu.write(SLOT3_ELEM + i, 0x01, emu.memType.snesMemory)
      emu.write(TEMP_ELEM + i, 0x02, emu.memType.snesMemory)
    end
    emu.write(0x316c00, 0x4f, emu.memType.snesMemory)
    emu.write(0x316c01, 0x38, emu.memType.snesMemory)
  end),

  -- Close the menu.  worldReady()/worldHasControl() read menu-module
  -- garbage while the menu owns the zero page (measured), so the positive
  -- witness that the world module is really back is the exact parked tile.
  H.driveUntil(function()
    return H.worldMode() and H.worldAligned() and bright() >= 15
       and H.worldX() == 64 and H.worldY() == 77
  end, 4000, {
    H.pressButtons({ "b" }, 4), H.waitFrames(20),
  }, "world control after menu close"),

  -- Walk into a desert encounter (south/east targets keep clear of the
  -- Figaro gate trigger at (64,76)).
  (function() local plan, idx = nil, 1
    return H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
      H.call(function()
        if not H.worldMode() then H.setPad({}); return end
        if not H.worldHasControl() then plan = nil; H.setPad({}); return end
        if not H.worldAligned() then return end
        if not plan or idx > #plan then
          for _, t in ipairs({ { 70, 80 }, { 58, 80 }, { 64, 85 } }) do
            plan = H.worldBfs(t[1], t[2]); idx = 1
            if plan and #plan > 0 then break end
          end
        end
        if not plan then H.setPad({}); return end
        local dir = plan[idx]; idx = idx + 1
        H.setPad({ [dir] = true })
      end),
    }, "post-save world encounter") end)(),
  H.release(),
  H.waitUntil(function() return H.monstersPresent() > 0 end, 900,
    "monsters seeded", 5),
  H.waitFrames(90),

  -- THE ASSERT: the seed merged the SAVED page, not the transient one.
  H.call(function()
    local checked = 0
    for slot = 0, 5 do
      if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
        local off = 8 + slot * 2
        local revealed = H.readByte(0x3e89 + off)
        H.assertEq(revealed & 0x01, 0x01, string.format(
          "monster slot %d pre-revealed FIRE from the slot-3 codex page", slot))
        H.assertEq(revealed & 0x02, 0x00, string.format(
          "monster slot %d did NOT surface the transient page's ICE", slot))
        checked = checked + 1
      end
    end
    H.assertEq(checked > 0, true, "at least one monster was checked")
    H.log(string.format("codex page selection held post-menu: %d monster(s) "
      .. "carry slot-3 knowledge", checked))
  end),

  -- clear the fight so the run ends in a quiet state
  (function() local ph = 0
    return H.driveUntil(function() return not H.battleLoadStarted() end, 9000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.battleLoadStarted() and H.monstersPresent() > 0 then killBitAll() end
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, "battle cleared") end)(),
})
