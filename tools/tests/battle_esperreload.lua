-- @suite slow
-- battle_esperreload.lua -- the two loads put a save's esper progress back over progress earned since it (#328
-- review: B1, and the copy the title's Continue makes).
--
-- The live esper page ($317C00) is the one play writes; a load copies the slot's page over it.  Two loads:
--   * the title's Continue (field_menu.asm MenuState_23 -> Ot6EsperContinue -> Ot6EsperLoaded);
--   * the reload after a game over (field/menu.asm -> LoadSavedGame -> Ot6CodexLoaded -> Ot6EsperLoaded).  Until
--     the review's fix Ot6CodexLoaded cleared A (shorta0) before handing it the slot, so this reload cleared the
--     live page: every character's progress gone, and the next save wrote the zeros into the slot.
-- Played: Continue post-opera-v1 (its slot 3 page holds the line's progress: LOCKE wears Kirin).  Then
--   1. random battles by the opera house, fought out, until one pays a stone-wearer: the live page now differs
--      from slot 3's.  The console's Reset (a person's button, not the pad's), the title, Continue slot 3:
--      asserted, the Continue's hook ran, the live page is slot 3's word for word, and not the page before the
--      reset;
--   2. again a paying battle won (the live page ahead of the slot), then a random battle with no command given
--      until the party falls (a loss is this run's entry, allowed and answered once), and through the game over
--      to the reloaded save: asserted, Ot6CodexLoaded ran, the live page is slot 3's word for word and not the
--      page before the loss.
-- Nothing is written.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local LIVE, SLOT3 = 0x317C00, 0x317800
local N = 12 * 26
local function sram(a) return emu.read(a, emu.memType.snesMemory) end
local function sramW(a) return sram(a) | (sram(a + 1) << 8) end
local hits = { loaded = 0, continue = 0 }
local function arm()
  local l, c = H.sym("Ot6CodexLoaded"), H.sym("Ot6EsperContinue")
  emu.addMemoryCallback(function() hits.loaded = hits.loaded + 1 end, emu.callbackType.exec, l, l)
  emu.addMemoryCallback(function() hits.continue = hits.continue + 1 end, emu.callbackType.exec, c, c)
end
local function page(base)
  local t, sum = {}, 0
  for i = 0, N - 1 do t[i] = sramW(base + 0x10 + i * 2); sum = sum + t[i] end
  return t, sum
end
local function same(a, b) for i = 0, N - 1 do if a[i] ~= b[i] then return false end end return true end

local A, B, saved, before = nil, nil, nil, nil
local function pace(what)
  return H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
    H.worldNavTo(function() return B[1] end, function() return B[2] end,
      { maxFrames = 3000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() A, B = B, A end),
  }, what)
end
local function lanes()
  return H.call(function()
    local x, y = H.worldX(), H.worldY()
    local function plain(tx, ty) return (H.worldTileProp(tx, ty) & 0x50) == 0x40 end
    A, B = { x, y }, nil
    for _, d in ipairs({ { -1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 0 } }) do
      if B == nil and plain(x + d[1], y + d[2]) then B = { x + d[1], y + d[2] } end
    end
    H.assertEq(plain(x, y) and B ~= nil, true, "two plain tiles that roll random battles")
  end)
end
-- random battles, fought out, until the live page is ahead of slot 3's (at most eight)
local function earn(tag)
  local n = 0
  return H.driveUntil(function() return not same(page(LIVE), saved) end, 300000, {
    H.call(function() n = n + 1; H.assertEq(n <= 8, true, tag .. ": a battle that pays a stone-wearer within eight") end),
    pace(tag .. ": a random battle"),
    H.waitUntil(function() return H.battleActive() end, 1200, tag .. ": the battle is up", 2),
    H.fightBattleByMenu(40000),
    H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000, "back on the map", 2),
    H.fieldCare({ tag = "care between battles" }),
  }, tag)
end

H.run({ maxFrames = 600000, allowGameOver = true }, {
  H.bootCheckpoint("post-opera-v1"),
  H.call(function()
    arm()
    local _, sum = page(SLOT3)
    H.assertEq(sum > 0, true, "slot 3's esper page holds progress (the line's)")
    saved = page(SLOT3)
    H.assertEq(same(page(LIVE), saved), true, "the boot's Continue copied slot 3's page live")
  end),
  lanes(),
  -- 1. the title's Continue
  earn("1"),
  H.call(function()
    before = page(LIVE)
    H.log("[reload] 1: a won battle took the live page past slot 3's; the console's Reset")
    hits.loaded, hits.continue = 0, 0
    H.expectTitle("battle_esperreload: the console's Reset before the Continue under test")
    emu.reset()
  end),
  H.bootCheckpoint("post-opera-v1"),
  H.call(function()
    H.log(string.format("[reload] 1: Ot6EsperContinue ran %d, Ot6CodexLoaded ran %d", hits.continue, hits.loaded))
    H.assertEq(hits.continue > 0, true, "1: the Continue ran its hook")
    H.assertEq(same(page(LIVE), saved), true, "1: after the Continue the live page is slot 3's")
    H.assertEq(same(page(LIVE), before), false, "1: ...not the page the won battle left")
  end),
  lanes(),
  -- 2. the reload after a game over
  earn("2"),
  H.call(function() before = page(LIVE) end),
  pace("2: the battle lost"),
  H.call(function() H.setPad({}) end),
  -- no command: the monsters act until the party falls
  H.waitUntil(function() return (H.gameOverFired or 0) > 0 end, 200000, "the party falls", 60),
  H.call(function()
    H.scriptedLossAnswered("battle_esperreload's loss: the reload under test")
    H.thawPad()
    hits.loaded, hits.continue = 0, 0
  end),
  (function()
    local ph = 0
    return H.driveUntil(function()
      return (H.worldMode() and H.worldHasControl()) or (not H.worldMode() and H.hasControl() and H.tileAligned()
        and hits.loaded > 0)
    end, 20000, {
      H.call(function() ph = (ph + 1) % 48; H.setPad(ph < 8 and { "a" } or {}) end),
    }, "through the game over to the reloaded save")
  end)(),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[reload] 2: Ot6CodexLoaded ran %d, Ot6EsperContinue ran %d", hits.loaded, hits.continue))
    H.assertEq(hits.loaded > 0, true, "2: the reload went through Ot6CodexLoaded")
    H.assertEq(sramW(LIVE), 0x3145, "2: the live esper page is signed after the reload")
    local live = page(LIVE)
    for i = 0, N - 1 do
      H.assertEq(live[i], saved[i], string.format("2: after the reload the live count %d (actor %d, slot %d) is the "
        .. "save's", i, i // 26, i % 26))
    end
    H.assertEq(same(live, before), false, "2: ...not the page the won battle left")
    H.log("[reload] PASS: both loads put the save's esper progress back over what was earned since")
  end),
})
