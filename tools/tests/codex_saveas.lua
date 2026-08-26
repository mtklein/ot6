-- @suite savestate=worldmap_narshe
-- codex_saveas.lua -- an unsaved New Game's transient codex follows its first
-- real in-game save into the chosen slot.
--
-- The chain that generates worldmap_narshe never saves, so the lifecycle
-- cell already reads 0 and the transient page already carries the chain's
-- earned reveals; slot 3 is empty and is asserted so by reading it.  On
-- top of that inherited payload the test earns one byte during the run: it
-- patrols the grass area south of Narshe, Terra casts a real Fire, and the
-- chip path's own persistent store writes the transient page, observed as
-- a before/after page diff rather than assumed.  Then the ordinary field
-- menu's Save command is driven with pad input only, saving into empty
-- slot 3.  The test then asserts that the full transient payload, both
-- the inherited bytes and the earned one, arrived in the slot 3 page,
-- along with the lifecycle marker.  This exercises CopyGameDataToSRAM's
-- real Ot6CodexSaveAs hook rather than calling an OT6 helper directly.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/worldmap_narshe.mss.lua"

local ZMENUSTATE = 0x26
local MAIN_MENU = 0x05
local SAVE_SELECT = 0x14
local ACTIVE = 0x021f
local SLOT3, TEMP = 0x316800, 0x316C00  -- codex pages (root $316000 + $400*n)
local PAGE_USED = 0x310                 -- magic + elem@$10 + class@$190

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_MAGIC, ST_TGT = 0x05, 0x0E, 0x38
local CMDTBL = 0x202E
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }
local FIRE = 0x00

local function sram(a) return emu.read(a, emu.memType.snesMemory) end
local saveArg
local function worldReady()
  return (H.readWord(0x1f64) & 0x03ff) < 3
     and H.readByte(0x0019) == 0
     and (H.readByte(0x00e7) & 0x01) == 0
end
local function snapPage(base)
  local t = {}
  for off = 0, PAGE_USED - 1 do t[off] = sram(base + off) end
  return t
end
local function offName(off)
  if off >= 0x190 then return string.format("class species $%03X", off - 0x190) end
  if off >= 0x10 then return string.format("elem species $%03X", off - 0x10) end
  return string.format("header+%X", off)
end

local tempBefore, earned = nil, {}

local function spellIndexOf(slot, id)
  for i = 0, 15 do
    local a = 0x2092 + SPELL_PTR[slot] + i * 4
    if H.readByte(a) == id and (H.readByte(a + 1) & 0x80) == 0 then return i end
  end
  return nil
end

-- one grass-area fight: patrol until an encounter, then TERRA casts Fire
-- and everyone else Fights, all through the live menus, with 4-frame-held
-- presses because 1-frame presses are lost at the poll, until the
-- battle ends.  Trash here dies to the same drive, so no flee is needed.
local function grassFight(n)
  local plan, idx, goal = nil, 1, { 82, 56 }
  local mf, lastActor, act = 0, nil, nil
  return H.cond(function() return #earned == 0 end, {
    H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
      H.call(function()
        if not H.worldMode() then H.setPad({}); return end
        if not H.worldHasControl() then plan = nil; H.setPad({}); return end
        if not H.worldAligned() then return end
        if not plan or idx > #plan then
          if H.worldX() == goal[1] and H.worldY() == goal[2] then
            goal = (goal[2] == 56) and { 82, 50 } or { 82, 56 }
          end
          plan = H.worldBfs(goal[1], goal[2]); idx = 1
          if not plan or #plan == 0 then plan = nil; H.setPad({}); return end
        end
        local dir = plan[idx]; idx = idx + 1
        if not dir then H.setPad({}); return end
        H.setPad({ [dir] = true })
      end),
    }, "grass-area encounter " .. n),
    H.release(),
    H.waitUntil(function() return H.monstersPresent() > 0 end, 900,
      "monsters seeded", 5),
    H.waitFrames(90),
    H.driveUntil(function() return not H.battleLoadStarted() end, 30000, {
      H.call(function()
        if H.readByte(MENU) == 0 then
          lastActor = nil
          H.setPad(H.frame % 8 < 4 and { "a" } or {})
          return
        end
        local a = H.readByte(ACTOR)
        if lastActor ~= a then
          lastActor, mf = a, 0
          act = (H.readByte(0x3ED8 + a * 2) == 0x00) and "fire" or "fight"
        end
        mf = mf + 1
        local hold = (mf % 10) < 5
        local st, btn = H.readByte(MSTATE), nil
        if st == ST_CMD then
          btn = "a"
          if act == "fire" then
            local cell = nil
            for i = 0, 3 do
              if H.readByte(CMDTBL + a * 12 + i * 3) == 0x02 then cell = i end
            end
            if cell == nil then act = "fight"
            else
              local cur = H.readByte(0x890F + a)
              if cur ~= cell then btn = (cur < cell) and "down" or "up" end
            end
          end
        elseif st == ST_MAGIC then
          if act ~= "fire" then btn = "b"
          else
            local i = spellIndexOf(a, FIRE)
            if i == nil then act = "fight"; btn = "b"
            else
              local wantRow, wantCol = i // 2, i % 2
              local absRow = H.readByte(0x8913 + a) + H.readByte(0x891B + a)
              local col = H.readByte(0x8917 + a)
              btn = "a"
              if absRow ~= wantRow then btn = (absRow < wantRow) and "down" or "up"
              elseif col ~= wantCol then btn = (col < wantCol) and "right" or "left" end
            end
          end
        elseif st == ST_TGT then
          btn = "a"
        end
        H.setPad((hold and btn) and { [btn] = true } or {})
      end),
    }, "fight " .. n .. " played to its end"),
    H.call(function()
      H.setPad({})
      -- the earn detector: the game's own codex write, seen as a page diff
      for off = 0, PAGE_USED - 1 do
        local now = sram(TEMP + off)
        if now ~= tempBefore[off] then
          earned[#earned + 1] = { off = off, was = tempBefore[off], now = now }
          H.log(string.format("[saveas] EARNED %s: %02X -> %02X",
            offName(off), tempBefore[off], now))
        end
      end
      -- and it must never land in a save slot pre-save
      for _, base in ipairs({ 0x316000, 0x316400, SLOT3 }) do
        for off = 0, PAGE_USED - 1 do
          H.assertEq(sram(base + off), 0, string.format(
            "no pre-save battle write reaches save-slot page $%06X+%03X",
            base, off))
        end
      end
    end),
  }, {})
end

H.run({ maxFrames = 90000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(worldReady, 500, "world-map control", 5),
  H.call(function()
    local entry = H.sym("CopyGameDataToSRAM")
    emu.addMemoryCallback(function()
      local st = emu.getState()
      saveArg = st["cpu.a"] & 0xff
    end, emu.callbackType.exec, entry, entry)
    H.assertEq(H.readByte(ACTIVE), 0,
      "lifecycle 0: this chain has never saved, the transient page is active")
    H.assertEq(sram(TEMP), 0x4f, "transient codex magic 'O' (Ot6CodexEnsure)")
    H.assertEq(sram(TEMP + 1), 0x38, "transient codex magic '8'")
    H.assertEq(sram(0x307ff0) ~= 3, true,
      "no save has ever claimed slot 3 (SRAM last-saved-slot marker)")
    H.assertEq(sram(SLOT3) ~= 0x4f or sram(SLOT3 + 1) ~= 0x38, true,
      "slot 3's codex page is really unformatted -- read, not zeroed")
    local known = 0
    for off = 0x10, PAGE_USED - 1 do
      if sram(TEMP + off) ~= 0 then known = known + 1 end
    end
    H.log(string.format("[saveas] transient page carries %d earned byte(s) "
      .. "from the generation chain", known))
    H.assertEq(known > 0, true,
      "positive control: the chain's own fights populated the transient page")
    tempBefore = snapPage(TEMP)
  end),

  -- earn one more byte on camera (up to four encounters)
  grassFight(1), grassFight(2), grassFight(3), grassFight(4),
  H.call(function()
    H.assertEq(#earned > 0, true,
      "a real battle taught the transient codex at least one new byte")
    tempBefore = snapPage(TEMP)   -- the payload the save must carry over
  end),
  -- the post-battle world fade eats early presses, so wait for settled
  -- world control and then retry the open until the menu state answers
  (function()
    local calm = 0
    return H.waitUntil(function()
      local ok = H.worldMode() and H.worldHasControl() and H.worldAligned()
        and (emu.getState()["ppu.screenBrightness"] or 0) >= 15
      calm = ok and calm + 1 or 0
      return calm >= 30
    end, 3600, "world settled after the fight", 1)
  end)(),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == MAIN_MENU
  end, 1200, {
    H.pressButtons({ "x" }, 4), H.waitFrames(40),
  }, "main menu"),
  -- up wraps the main-menu cursor from Items straight down to Save (row 6);
  -- A then runs the real save-enabled code path rather than an imitation.
  -- World-map saving is legal, so the menu allows it.
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == MAIN_MENU and H.readByte(0x4b) == 6
  end, 600, {
    H.pressButtons({ "up" }, 4), H.waitFrames(16),
  }, "main-menu cursor on Save"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    600, "save-slot selection", 5),
  -- Walk the slot cursor to slot 3 (zero-based 2) by pad, confirming by
  -- reading the cursor back each frame.  This run's SRAM is fresh so slot 3
  -- saves instantly; were it occupied, the driveUntil below presses A on
  -- through the overwrite confirm.
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == SAVE_SELECT and H.readByte(0x4b) == 2
  end, 600, {
    H.pressButtons({ "down" }, 4), H.waitFrames(16),
  }, "save cursor on slot 3"),
  H.pressButtons({ "a" }, 4),
  H.waitFrames(40),
  H.call(function()
    H.log(string.format("save drive: state=$%02x cursor=%d selected=%d arg=%s active=%d last=%d magic=%02x%02x",
      H.readByte(ZMENUSTATE), H.readByte(0x4b), H.readByte(0x66),
      tostring(saveArg), H.readByte(ACTIVE), sram(0x307ff0),
      sram(SLOT3 + 1), sram(SLOT3)))
  end),
  -- $021f is wSaveSlotToLoad only while the menu module owns that RAM; the
  -- moment the world module resumes, a block restore puts the world's own
  -- variable back in that cell.  Observe the save through channels that
  -- are context-stable instead: the SRAM last-saved-slot marker ($307ff0),
  -- the captured CopyGameDataToSRAM argument, and the codex payload itself.
  H.driveUntil(function()
    return sram(0x307ff0) == 3 and sram(SLOT3) == 0x4f
  end, 600, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "first save into slot 3"),
  H.call(function()
    H.assertEq(saveArg, 3, "CopyGameDataToSRAM ran for persistent slot 3")
    H.assertEq(sram(0x307ff0), 3, "SRAM last-saved-slot marker is 3")
    H.assertEq(sram(SLOT3), 0x4f, "slot 3 codex magic 'O'")
    H.assertEq(sram(SLOT3 + 1), 0x38, "slot 3 codex magic '8'")
    -- the transfer: every byte the transient page holds, both the chain's
    -- inherited reveals and the byte this run earned, must
    -- appear in slot 3, and the source page must survive intact.
    local moved = 0
    for off = 0x10, PAGE_USED - 1 do
      local want = tempBefore[off]
      if want ~= 0 then
        moved = moved + 1
        H.assertEq(sram(SLOT3 + off), want,
          "first save transferred " .. offName(off) .. " into slot 3")
        H.assertEq(sram(TEMP + off), want,
          "Save As did not destroy the transient source page (" ..
          offName(off) .. ")")
      end
    end
    for _, e in ipairs(earned) do
      H.assertEq(sram(SLOT3 + e.off), e.now,
        "the byte EARNED this run rode the save: " .. offName(e.off))
    end
    H.log(string.format("[saveas] full payload transferred: %d byte(s), "
      .. "%d earned this run", moved, #earned))
  end),
})
