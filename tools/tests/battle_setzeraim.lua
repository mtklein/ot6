-- @suite slow
-- battle_setzeraim.lua -- H.setzerBattle confirms only the target it was
-- asked for (lib/ot6.lua, aimStep).  Its slot aim used to press down, up,
-- right and left twelve times and then A wherever the cursor stood: once a
-- party member, and a 2 BP Jackpot rolled on the party and wiped it
-- (wt/pass-retarget, build/attempts/wt/pass-retarget/iterations/).
--
-- Played, no writes: Continue the wor-tomb-v1 battery and walk Darill's
-- Tomb's east room until a battle deals two or more monsters (fighting out
-- any other with the route's fight driver, care after), within
-- M.setzerCrowdBudget's decoded worst case.  On SETZER's first turn there,
-- through the real menu, one plan (opts.aimRefusedOk):
--   a. Hired Help aimed at a slot no monster holds: refused at target
--      select, not confirmed (the entry records why), backed out;
--   b. Hired Help aimed at a live monster the cursor is not on, with
--      walking off for this entry (aimWalk = false): refused the same way;
--   c. Hired Help, unboosted, aimed at the live monster with the highest
--      slot: the cursor is walked there and the hire lands on that slot and
--      no other ($b9 at its exec).
-- Asserted: a and b refused, exactly one hire executed (c's), on c's slot,
-- and the purse fell by that one fee.  On the lib before aimStep a and b
-- were confirmed where the cursor stood: build/attempts/wt/pass-retarget/aim/.
-- The fight driver then ends the battle.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local HIRE = 0x5A
local TAG = "setzeraim"

local function alive() return H.readByte(0x3A75) end
local function count(m) local n = 0 while m ~= 0 do n = n + (m & 1); m = m >> 1 end return n end
local function gil() return H.readWord(0x1860) + H.readByte(0x1862) * 65536 end

local W, since, wp = nil, 0, 1
local WPS = { { 124, 26 }, { 120, 11 } }
local done = false
local far, absent = nil, nil

local function play()
  local S = {}
  return { tick = function()
    if S.phase == nil then
      local m = alive()
      H.log(string.format("[%s] encounter %d: alive $%02X (%d monster(s))", TAG, since, m, count(m)))
      S.phase = (count(m) >= 2 and not done) and "plan" or "fight"
      if S.phase == "plan" then
        for s = 0, 5 do if (m >> s) & 1 == 1 then far = s end end
        for s = 5, 0, -1 do
          if (m >> s) & 1 == 0 and (H.readByte(0x3AA8 + s * 2) & 1) == 0 then absent = s end
        end
        H.assertEq(absent ~= nil, true, "a slot no monster holds (a formation of six fills them all)")
        S.gil0 = gil()
        S.negA = { row = HIRE, boost = 0, slot = absent }
        -- read when target select opens: a live monster the cursor is not on
        S.negB = setmetatable({ row = HIRE, boost = 0, aimWalk = false }, { __index = function(_, k)
          if k ~= "slot" then return nil end
          local cur, lm = H.readByte(0x7B7E), alive()
          for s = 0, 5 do if (lm >> s) & 1 == 1 and (1 << s) ~= cur then return s end end
          return absent
        end })
        S.pos = { row = HIRE, boost = 0, slot = far }
        S.step = H.setzerBattle({ S.negA, S.negB, S.pos }, { untilPlanDone = true, aimRefusedOk = true })
      end
    end
    if S.phase == "plan" then
      local r = S.step:tick()
      if r ~= "done" then return r end
      local recs = H.vars.setzer
      H.log(string.format("[%s] a (slot %d, no monster): %s", TAG, absent, tostring(rawget(S.negA, "aimRefused"))))
      H.log(string.format("[%s] b (off the cursor, walking off): %s", TAG, tostring(rawget(S.negB, "aimRefused"))))
      H.assertEq(rawget(S.negA, "aimRefused") ~= nil, true, string.format("a hire aimed at slot %d, which no monster "
        .. "holds, is refused at target select", absent))
      H.assertEq(rawget(S.negB, "aimRefused") ~= nil, true, "a hire aimed off the cursor with walking off is "
        .. "refused, not confirmed where the cursor stands")
      H.assertEq(rawget(S.pos, "aimRefused"), nil, string.format("the hire aimed at live slot %d is not refused", far))
      H.assertEq(#recs, 1, "exactly one hire executed: the aimed one")
      H.log(string.format("[%s] c: aimed at slot %d, the hire's targets $%02X, purse %d -> %d (fee %d)", TAG, far,
        recs[1].targets, S.gil0, gil(), recs[1].level * 50))
      H.assertEq(recs[1].targets, 1 << far, string.format("the aimed hire lands on slot %d and no other", far))
      H.assertEq(S.gil0 - gil(), recs[1].level * 50, "the purse paid one fee: no refused hire was paid for")
      done = true
      S.phase = "fight"
    end
    if S.F == nil then
      S.F = H.newFightDriver(TAG .. " fight", { tactical = true, boost = true, items = true, bank = 0,
        healPercent = 55, setzer = false })
    end
    if not H.battleLoadStarted() then return "done" end
    S.F.frame()
    return "frame"
  end, reset = function() S = {} end }
end

H.run({ maxFrames = 600000 }, {
  H.bootCheckpoint("wor-tomb-v1"),
  H.call(function() W = H.setzerCrowdBudget(H.fieldEncounterGroup(H.mapId() & 0x1ff), TAG) end),
  H.driveUntil(function() return done end, 560000, {
    H.call(function()
      since = since + 1
      H.assertEq(since <= W, true, string.format("two or more monsters within %d encounters (the decoded worst "
        .. "case to a crowd, which deals three)", W))
    end),
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.navTo(function() return WPS[wp][1] end, function() return WPS[wp][2] end,
        { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() wp = wp % #WPS + 1 end),
    }, "a random battle"),
    H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 2),
    play(),
    H.waitFrames(60),
    H.careStop(TAG .. " care after the battle"),
  }, "a battle with two or more monsters"),
  H.call(function()
    H.log(string.format("[%s] PASSED: the aim landed on slot %d; an aim at absent slot %d and an aim off the cursor "
      .. "with walking off were refused, not confirmed", TAG, far, absent))
  end),
})
