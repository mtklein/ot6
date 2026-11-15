-- @suite newgame
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_newgameloadouts.lua -- a New Game on a console whose RAM powers on
-- non-zero gives Gau and Strago their full AUTO lists (#389).
--
-- Vanilla clears WRAM only to $11FF and its New Game names none of the save
-- block's spare bytes, so before Ot6NewGameClear a New Game kept the
-- power-on fill in the three OT6 loadouts ($1E1D-$1E2B), the signature and
-- reserve ($1E2C-$1E3F) and the block's tail ($1FF7-$1FFD), and every save
-- of that game carried it.  Under an all-ones fill that is $FF: a manual
-- Rage and Lore loadout whose every slot names an unknown entry, so the
-- battle lists came up empty.
--
-- Boots under OT6_RAM_POWERON=AllOnes with a v0.44 world-map battery whose
-- party seats GAU (golden-saves/v0.44/wor-gau-v1, 11 rages learned) or
-- STRAGO (golden-saves/v0.44/wor-opera-v1, 9 lores): a battle builds only a
-- seated character's list.  configure.py runs it on both.  By hand:
--   OT6_RAM_POWERON=AllOnes \
--   OT6_SRAM_CHECKPOINT=tools/tests/golden-saves/v0.44/wor-gau-v1 \
--     tools/tests/run.sh tools/tests/battle_newgameloadouts.lua <log>
--
-- Played:
--   1. the title, the load menu's New Game row, A: Ot6CodexNewGame runs;
--      600 frames into the opening the scrap and the tail are read (N; they
--      are asserted zero at the end, after the lists they build are read);
--   2. the console's Reset, the title, Continue slot 3 (the battery's save:
--      its loadout bytes are zero, as every harness save's are);
--   3. the expedient: the fifteen loadout bytes N holds are written over
--      the loaded ones, standing for a save made from that New Game, which
--      would carry them (the only way to carry a New Game's bytes to a game
--      that has Gau's and Strago's learning without playing the whole
--      game);
--   4. walking two plain world tiles until a random battle opens, and
--      reading the lists InitBattle built: the Rage list ($257E, count
--      $3A9A) is the first eight learned rages in id order (AUTO), and the
--      Lore count ($3A87) is AUTO's first five slottable lores plus the free
--      row (Aqua Rake) when learned.
-- Red on v0.44's ROM, whose New Game leaves $FF there (N reads $FF and the
-- lists are empty), and on a ROM whose Ot6NewGameClear returns at once
-- (tools/build/mutant_rom.py; configure.py's negative edge).
--
-- Writes: the console's Reset, and the fifteen loadout bytes (step 3);
-- tools/state_write_waivers.txt.
local H = dofile("tools/tests/lib/ot6.lua")

local SLOT_PTR = { [1] = 0x0000, [2] = 0x0A00, [3] = 0x1400 }
local SCRAP, SCRAP_N = 0x1E1D, 0x23
local TAIL, TAIL_N = 0x1FF7, 7
local LOADOUT_N = 15                     -- $1E1D-$1E2B: Bushido word, 8 rage, 5 lore
local RAGES, LORES = 0x1D2C, 0x1D29
local RAGELIST, RAGECOUNT, LORECOUNT = 0x257E, 0x3A9A, 0x3A87
local ZMENUSTATE, ZCURSOR = 0x26, 0x4b
local FREE_LORE = 3                      -- Aqua Rake

local function sram(a) return emu.read(a, emu.memType.snesMemory) end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

local newgames, loadmenu = 0, 0
local seated = {}
local nonzero
local ragelistRuns = 0
local CHAR_STRAGO, CHAR_GAU = 7, 11
local N = {}
local target

local function hex(t, n)
  local s = {}
  for i = 0, n - 1 do s[#s + 1] = string.format("%02X", t[i]) end
  return table.concat(s, " ")
end

local function atTarget()
  if target.world then
    return H.worldMode() and H.worldX() == target.x and H.worldY() == target.y
  end
  return not H.worldMode() and not H.menuRunning() and (H.mapId() & 0x1ff) == target.map
    and H.fieldX() == target.x and H.fieldY() == target.y
end

local function title()
  return H.seqStep({
    H.waitFrames(350),
    H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
    H.waitFrames(120),
  })
end

local function continue(tag)
  local ph = 0
  return H.seqStep({
    title(),
    H.withReset(H.driveUntil(function() return atTarget() and bright() >= 15 end, 2400, {
      H.call(function()
        ph = (ph + 1) % 48
        if atTarget() or bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, tag .. ": Continue slot 3 -> the saved tile"), function() ph = 0 end),
    H.release(),
    H.waitUntil(function() return H.worldMode() and H.worldHasControl() and bright() >= 15 end, 1800,
      tag .. ": control on the world map after the load", 1),
    H.waitFrames(30),
  })
end

-- random battles come on the world map's plain tiles: walk between two
local A, B
local function lanes()
  return H.call(function()
    local x, y = H.worldX(), H.worldY()
    local function plain(tx, ty) return (H.worldTileProp(tx, ty) & 0x50) == 0x40 end
    A, B = { x, y }, nil
    for _, d in ipairs({ { -1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 0 } }) do
      if B == nil and plain(x + d[1], y + d[2]) then B = { x + d[1], y + d[2] } end
    end
    H.assertEq(plain(x, y) and B ~= nil, true, "two plain world tiles that roll random battles")
  end)
end

local function learned(base, n)
  local ids = {}
  for id = 0, n - 1 do
    if (H.readByte(base + (id >> 3)) & (1 << (id & 7))) ~= 0 then ids[#ids + 1] = id end
  end
  return ids
end

H.run({ maxFrames = 60000 }, {
  H.call(function()
    local at = H.sym("Ot6CodexNewGame")
    emu.addMemoryCallback(function() newgames = newgames + 1 end, emu.callbackType.exec, at, at)
    local rl = H.sym("Ot6RageList")
    emu.addMemoryCallback(function() ragelistRuns = ragelistRuns + 1 end, emu.callbackType.exec, rl, rl)
    local lm = H.sym("GameLoadMenu")
    emu.addMemoryCallback(function() loadmenu = loadmenu + 1 end, emu.callbackType.exec, lm, lm)
    local slot = sram(0x307FF0)
    H.assertEq(slot, 3, "the battery last saved slot 3")
    local base = 0x306000 + SLOT_PTR[3]
    local word = sram(base + 0x1F64 - 0x1600) | (sram(base + 0x1F65 - 0x1600) << 8)
    target = { world = (word & 0x1ff) <= 1, x = sram(base + 0x1F60 - 0x1600), y = sram(base + 0x1F61 - 0x1600) }
    H.assertEq(target.world, true, "the battery's slot 3 is a world-map save (random battles nearby)")
  end),
  -- 1. New Game from the load menu, under the all-ones fill (the title
  -- takes its button later than on a zero fill: Start and A, pressed until
  -- the load menu starts)
  H.driveUntil(function() return loadmenu > 0 end, 9000, {
    H.pressButtons({ "start" }, 6), H.waitFrames(14), H.pressButtons({ "a" }, 6), H.waitFrames(14),
  }, "the load menu (GameLoadMenu)"),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x21 end, 1200, "the load menu's slot list", 1),
  H.driveUntil(function() return H.readByte(ZMENUSTATE) == 0x21 and H.readByte(ZCURSOR) == 0 end, 600, {
    H.pressButtons({ "up" }, 4), H.waitFrames(16),
  }, "the cursor on New Game"),
  H.driveUntil(function() return newgames > 0 end, 600, {
    H.pressButtons({ "a" }, 4), H.waitFrames(30),
  }, "New Game chosen (Ot6CodexNewGame)"),
  H.waitFrames(600),
  H.call(function()
    for i = 0, SCRAP_N - 1 do N[i] = H.readByte(SCRAP + i) end
    local tail = {}
    for i = 0, TAIL_N - 1 do tail[i] = H.readByte(TAIL + i) end
    print("[newgame] $1E1D-$1E3F " .. hex(N, SCRAP_N))
    print("[newgame] $1FF7-$1FFD " .. hex(tail, TAIL_N))
    nonzero = 0
    for i = 0, SCRAP_N - 1 do if N[i] ~= 0 then nonzero = nonzero + 1 end end
    for i = 0, TAIL_N - 1 do if tail[i] ~= 0 then nonzero = nonzero + 1 end end
    -- asserted at the end, after the lists these bytes build are read
    H.expectTitle("battle_newgameloadouts: the console's Reset after the New Game")
    emu.reset()
  end),
  -- 2. Continue the battery's save
  continue("load"),
  H.call(function()
    -- who is in the battle party: the current party's members
    local cur = H.readByte(0x1A6D)
    seated.gau = (H.readByte(0x1850 + CHAR_GAU) & 7) == cur
    seated.strago = (H.readByte(0x1850 + CHAR_STRAGO) & 7) == cur
    H.assertEq(seated.gau or seated.strago, true,
      "the save seats GAU or STRAGO in the current party (the battle builds only a seated one's list)")
    for i = 0, LOADOUT_N - 1 do
      H.assertEq(H.readByte(SCRAP + i), 0, string.format("the save's loadout byte $%04X is zero", SCRAP + i))
    end
    -- 3. the New Game's loadout bytes, as a save from that game would carry them
    for i = 0, LOADOUT_N - 1 do H.writeByte(SCRAP + i, N[i]) end
    print("[newgame] the loadout bytes now hold the New Game's: " .. hex(N, LOADOUT_N))
  end),
  lanes(),
  -- 4. a random battle, and the lists it built
  H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
    H.worldNavTo(function() return B[1] end, function() return B[2] end,
      { maxFrames = 3000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() A, B = B, A end),
  }, "a random battle"),
  -- (the battle's own RAM still holds the all-ones fill until InitBattle
  -- writes it, so the menu byte is no witness: the list builder is)
  H.waitUntil(function() return ragelistRuns > 0 and H.battleActive() end, 3000,
    "the battle initialized (Ot6RageList ran from InitSkills)", 1),
  H.waitFrames(60),
  H.call(function()
    if seated.gau then
      local rages = learned(RAGES, 255)
      local want = {}
      for i = 1, math.min(8, #rages) do want[i] = rages[i] end
      local got = {}
      for i = 0, H.readByte(RAGECOUNT) - 1 do got[#got + 1] = H.readByte(RAGELIST + i) end
      print(string.format("[newgame] GAU seated; rages learned %d; the battle's Rage list has %d: %s", #rages,
        #got, table.concat(got, " ")))
      H.assertEq(#got, #want, "Gau's Rage list is AUTO's eight (the first eight learned)")
      for i, id in ipairs(want) do
        H.assertEq(got[i], id, string.format("Rage list[%d] is learned rage %d", i - 1, id))
      end
    end
    if seated.strago then
      local lores = learned(LORES, 24)
      local slottable, free = 0, false
      for _, id in ipairs(lores) do
        if id == FREE_LORE then free = true else slottable = slottable + 1 end
      end
      local wantLore = math.min(5, slottable) + (free and 1 or 0)
      print(string.format("[newgame] STRAGO seated; lores learned %d (free row %s); the battle offers %d",
        #lores, tostring(free), H.readByte(LORECOUNT)))
      H.assertEq(H.readByte(LORECOUNT), wantLore, "Strago's Lore list is AUTO's five plus the free row")
    end
    H.assertEq(nonzero, 0, "a New Game on an all-ones power-on fill leaves $1E1D-$1E3F and $1FF7-$1FFD zero")
    H.log("[newgame] PASS: the New Game's loadout bytes give Gau and Strago their AUTO lists")
  end),
})
