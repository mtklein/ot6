-- @manual
-- probe_wipe163.lua -- #163: measure the converted ladder watch on a real
-- all-zero wipe.  gen_kefka_won, gen_narshe_battle, gen_opera7_blackjack
-- and gen_zozo4_dadaluma now carry the F.watch() below (copied VERBATIM
-- from gen_kefka_won's mkFighter), called on every frame of the drive
-- rather than only while battleLoadStarted() holds.  This probe puts it
-- on a wipe whose HP table really is all zeros -- the case the old gated
-- watches were blind to, and the case the lib's canary counts -- and
-- times it: probe_wipe_canary's recipe (boot fc_alcove, step onto 394,
-- walk into a random, release the pad -- a person who never presses a
-- button), snapshot taken before the encounter, allowGameOver as every
-- converted ladder now runs.
--
-- Attempt 1 is the ladders' shape: the moment F.lost is set the rung
-- ends, the snapshot is reloaded (H.requestLoadState thaws the pad), and
-- H.gameOverFired is cleared; the probe then proves the pad is live again
-- by walking a step.  Attempt 2 replays the same wipe hands-off past the
-- canary's 300 frames to time the watch's other branch (the counter read)
-- against the wipe, then reloads the same way.
--
-- Read-only under docs/TESTING.md: pad presses and memory reads; complete
-- snapshots only.
local H = dofile("tools/tests/lib/ot6.lua")

local FIX = "build/states/fc_alcove.mss.lua"
local function map() return H.mapId() & 0x3ff end
local BCHP, BCMAXHP = 0x3bf4, 0x3c1c
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("%d/%d", H.readWord(BCHP + e * 2),
      H.readWord(BCMAXHP + e * 2))
  end
  return table.concat(p, " ")
end

-- ===================== verbatim from gen_kefka_won.lua =====================
local function mkWatch(tier, tag)
  local F = { lost = nil }
  local bt = nil
  local wipeN = 0
  function F.watch()
    wipeN = H.partyWipedInBattle() and wipeN + 1 or 0
    if (H.gameOverFired or 0) > 0 and not F.lost then
      F.lost = string.format("GAME OVER counted by the canary at f%d " ..
        "(tier %d) -- party [%s]", H.frame, tier, partyLine())
      H.log("[" .. tag .. "] " .. F.lost)
    end
    if wipeN >= 90 and not F.lost then
      F.lost = string.format("PARTY WIPED at f%d (started f%s, tier %d) " ..
        "-- party [%s]", H.frame, bt and tostring(bt.f0) or "?", tier,
        partyLine())
      H.log("[" .. tag .. "] " .. F.lost)
    end
  end
  return F
end
-- ===========================================================================

local preBlob = nil
local function status(tag)
  H.log(string.format("[wipe163] %s f%d hp=[%s] wipedInBattle=%s " ..
    "battleLoadStarted=%s $3ebc=%02X gameOverFired=%d padFrozen=%s ctrl=%s map=%d",
    tag, H.frame, partyLine(), tostring(H.partyWipedInBattle()),
    tostring(H.battleLoadStarted()), H.readByte(0x3ebc), H.gameOverFired or 0,
    tostring(H.padFrozen), tostring(H.hasControl()), map()))
end

local function enterRandom(what)
  return H.cond(function() return true end, {
    H.navTo(82, 30, { maxFrames = 20000, playBattles = "tactical", care = false,
      arrive = function() return H.battleLoadStarted() end }),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 3000, what, 30),
    H.call(function() status(what .. ": battle up, pad released") end),
  })
end

local function attempt(n, observePastCanary)
  local F = mkWatch(n, "wipe163 a" .. n)
  local t, zeroAt, lostAt, firedAt, loadReq = 0, nil, nil, nil, nil
  return H.cond(function() return true end, {
    n > 1 and H.cond(function() return true end, {
      H.call(function() loadReq = H.requestLoadState(preBlob) end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(loadReq, "attempt " .. n .. ": pre-encounter reload")
        H.gameOverFired = 0
        status("attempt " .. n .. ": reloaded the pre-encounter snapshot")
      end),
      H.waitFrames(90),
    }) or H.waitFrames(1),
    enterRandom("attempt " .. n .. " random on 394"),
    H.driveUntil(function()
      t = t + 1
      if zeroAt == nil and H.partyWipedInBattle() then
        zeroAt = H.frame
        status("attempt " .. n .. ": first frame every sane HP word reads 0")
      end
      F.watch()                             -- the converted watch, every frame
      if lostAt == nil and F.lost then
        lostAt = H.frame
        status(string.format("attempt %d: F.lost set %d frames after the " ..
          "all-zero frame", n, zeroAt and (H.frame - zeroAt) or -1))
        if not observePastCanary then return true end
      end
      if firedAt == nil and (H.gameOverFired or 0) > 0 then
        firedAt = H.frame
        status(string.format("attempt %d: canary counted %d frames after " ..
          "the all-zero frame", n, zeroAt and (H.frame - zeroAt) or -1))
        return true
      end
      return t > 60000
    end, 61000, {
      H.call(function()
        H.setPad({})                        -- a person who never presses
        if t % 600 == 0 then status("attempt " .. n .. ": hands off") end
      end),
    }, "attempt " .. n .. ": the passive fight"),
    H.call(function()
      H.log(string.format("[wipe163] attempt %d: zeroAt=%s lostAt=%s (+%s) " ..
        "firedAt=%s (+%s) F.lost=%s", n, tostring(zeroAt), tostring(lostAt),
        zeroAt and lostAt and tostring(lostAt - zeroAt) or "?",
        tostring(firedAt), zeroAt and firedAt and tostring(firedAt - zeroAt) or "?",
        tostring(F.lost)))
    end),
  })
end

H.run({ maxFrames = 200000, allowGameOver = true }, {
  H.loadState(FIX),
  H.waitFrames(60),
  H.waitUntil(function() return H.hasControl() end, 1200, "field control", 5),
  H.navTo(8, 9, { maxFrames = 3000, playBattles = "tactical", care = false }),
  (function()
    local t = 0
    return H.driveUntil(function() t = t + 1; return map() == 394 end, 1800, {
      H.call(function()
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({ up = true })
      end),
    }, "alcove (8,9) -> up through (8,8) -> 394")
  end)(),
  H.release(),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 900,
    "control back on 394", 10),
  H.waitFrames(30),
  -- the sweep's checkpoint: the pre-encounter moment, in memory
  (function()
    local req
    return H.cond(function() return true end, {
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "pre-encounter snapshot")
        preBlob = req.blob
        status("pre-encounter snapshot captured (" .. #preBlob .. " bytes)")
      end),
    })
  end)(),
  attempt(1, false),
  -- the ladders' reaction: reload, clear the counter, and the pad is live
  (function()
    local loadReq
    return H.cond(function() return true end, {
      H.call(function() loadReq = H.requestLoadState(preBlob) end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(loadReq, "attempt 1: loss reload")
        H.gameOverFired = 0
        status("attempt 1: loss reload done, counter cleared")
      end),
      H.waitFrames(90),
      H.call(function()
        H.assertEq(H.padFrozen, false, "the reload thawed the pad")
        H.assertEq(H.hasControl(), true, "control is back on the field")
        H.assertEq(H.partyWipedInBattle(), false, "the wipe is gone with the snapshot")
      end),
    })
  end)(),
  attempt(2, true),
  (function()
    local loadReq
    return H.cond(function() return true end, {
      H.call(function() loadReq = H.requestLoadState(preBlob) end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(loadReq, "attempt 2: loss reload")
        H.gameOverFired = 0
        status("attempt 2: loss reload done, counter cleared")
      end),
      H.waitFrames(90),
      H.call(function()
        H.assertEq(H.padFrozen, false, "the reload thawed the pad (after the canary froze it)")
        H.assertEq(H.hasControl(), true, "control is back on the field")
      end),
    })
  end)(),
  H.logStep("probe_wipe163: done"),
})
