-- @suite slow
-- battle_esperreload.lua -- a reload after a game over keeps the save's esper progress (#328 review, B1).
--
-- The reload after a game over goes through LoadSavedGame (field/menu.asm -> save.asm -> Ot6CodexLoaded ->
-- Ot6EsperLoaded), not the title's Continue.  Until the review's fix Ot6CodexLoaded cleared A (shorta0) before
-- handing it the slot, so the reload read slot 0's page, found no signature and cleared the live page: every
-- character's esper progress was gone, and the next save wrote the zeros into the slot.
--
-- Played: Continue post-opera-v1, whose slot 3 page holds the line's progress (LOCKE's count on Kirin), walk into
-- a random battle by the opera house and give no command until the party falls (a loss is the property's entry,
-- allowed for this run and answered once), then press through the game over until the party stands on the map
-- again.  Asserted: the reload ran Ot6CodexLoaded; the live page is signed and equal to slot 3's page word for
-- word; and slot 3's page holds some progress (else the property is vacuous).  Nothing is written.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local LIVE, SLOT3 = 0x317C00, 0x317800
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
  for i = 0, 12 * 26 - 1 do t[i] = sramW(base + 0x10 + i * 2); sum = sum + t[i] end
  return t, sum
end

local A, B, saved = nil, nil, nil
H.run({ maxFrames = 400000, allowGameOver = true }, {
  H.bootCheckpoint("post-opera-v1"),
  H.call(function()
    arm()
    local _, sum = page(SLOT3)
    H.assertEq(sum > 0, true, "slot 3's esper page holds progress (the line's)")
    saved = page(SLOT3)
    local x, y = H.worldX(), H.worldY()
    local function plain(tx, ty) return (H.worldTileProp(tx, ty) & 0x50) == 0x40 end
    A = { x, y }
    for _, d in ipairs({ { -1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 0 } }) do
      if B == nil and plain(x + d[1], y + d[2]) then B = { x + d[1], y + d[2] } end
    end
    H.assertEq(plain(x, y) and B ~= nil, true, "two plain tiles that roll random battles")
  end),
  H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
    H.worldNavTo(function() return B[1] end, function() return B[2] end,
      { maxFrames = 3000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() A, B = B, A end),
  }, "a random battle"),
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
    H.log(string.format("[reload] Ot6CodexLoaded ran %d, Ot6EsperContinue ran %d", hits.loaded, hits.continue))
    H.assertEq(hits.loaded + hits.continue > 0, true, "the reload went through a load hook")
    H.assertEq(sramW(LIVE), 0x3145, "the live esper page is signed after the reload")
    local live = page(LIVE)
    for i = 0, 12 * 26 - 1 do
      H.assertEq(live[i], saved[i], string.format("after the reload the live count %d (actor %d, slot %d) is the "
        .. "save's", i, i // 26, i % 26))
    end
    H.log("[reload] PASS: the game over's reload put the save's esper progress back, word for word")
  end),
})
