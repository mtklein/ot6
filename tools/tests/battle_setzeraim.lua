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
--      slot the cursor is not resting on when its target select opens: the
--      cursor is walked there and the hire lands on that slot and no other
--      ($b9 at its exec).
-- Asserted: a and b refused, exactly one hire executed (c's), on c's slot,
-- and the purse fell by that one fee.  On the lib before aimStep a and b
-- were confirmed where the cursor stood: build/attempts/wt/pass-retarget/aim/.
-- The fight driver then ends the battle.
--
-- A crowd can stop being one the plan can be played through before it is
-- done, and the battle is then lost to the test: the plan is dropped,
-- the route's fight driver fights it out, and the next crowd (at most W
-- encounters on, the decoded worst case) plays the plan from its start --
-- at most MAX_LOST such battles in the run.  The points:
--   * care.lostPoint's (the rule battle_slots and battle_slotsboot play
--     by) without "SETZER fell" (lo.fell = false: a Zombie reads 0 HP,
--     and H.setzerBattle's care cures or raises him): two or more members
--     out of control (H.controlTaken: Death, Zombie, Sleep, Muddle ...),
--     nobody but SETZER in control, or a conditional control attack live.
--     The tomb's crowds all hold Exorays, whose Special Zombies on any
--     turn (PowerDemon's skill too), and the plan holds the formation with
--     Defends: on #475's chain SETZER was Zombied between his hire's
--     confirm and its exec, the engine aimed it at CELES (#433), EDGAR and
--     SABIN were Zombied, and the party wiped with the plan still owed
--     (build/attempts/wt/v037-menu-race-3/suite_battle_setzeraim.log).
--   * c's target select opening with fewer than two live monsters (c
--     needs one off the cursor).  Read only there: the tomb's formations
--     hide and show bodies (Cmd_24), so $3A75 passes through 0 between
--     waves and the plan goes on once they are back.
--   * c's slot fallen between its confirm and its exec (the engine
--     retargets it), or the battle over with c not run.
-- c's slot is latched when its target select opens, once per aim: when
-- the engine aims c (SETZER Zombied after his confirm) H.setzerBattle
-- plays the entry again with a new aim, and the slot is latched again
-- (the first may have fallen meanwhile).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local HIRE = 0x5A
local TAG = "setzeraim"

local function alive() return H.readByte(0x3A75) end
local function count(m) local n = 0 while m ~= 0 do n = n + (m & 1); m = m >> 1 end return n end
local function gil() return H.readWord(0x1860) + H.readByte(0x1862) * 65536 end

local W, since, wp = nil, 0, 1
local lost, MAX_LOST = 0, 3
local function seat() for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == 9 then return s end end end
-- read only: the lost point and the party line
local care = H.newSpinnerCare({ spinner = seat })
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
        -- latched when its target select opens (H.setzerBattle builds the
        -- entry's aim there, then reads its slot): the live monster with the
        -- highest slot the cursor is not resting on, so the aim must walk.
        -- Once per aim: a replay (the engine aimed the row he confirmed)
        -- comes with a new aim and latches again.  With fewer than two live
        -- monsters there is no such slot, and the battle is lost to the
        -- test (an absent slot meanwhile, so nothing is confirmed)
        S.pos = setmetatable({ row = HIRE, boost = 0 }, { __index = function(t, k)
          if k ~= "slot" then return nil end
          local aim = rawget(t, "aim")
          if aim ~= nil and rawget(t, "latchedFor") ~= aim then
            local cur, lm = H.readByte(0x7B7E), alive()
            local was = rawget(t, "latched")
            rawset(t, "latched", nil)
            for s = 0, 5 do if (lm >> s) & 1 == 1 and (1 << s) ~= cur then rawset(t, "latched", s) end end
            rawset(t, "latchedFor", aim)
            S.latches = (S.latches or 0) + 1
            far = rawget(t, "latched")
            H.log(string.format("[%s] f%d c latched (aim %d): slot %s (cursor mons=%02X, $3A75 = $%02X)%s", TAG,
              H.frame, S.latches, tostring(far), cur, lm, was ~= nil and string.format(", was slot %d", was) or ""))
            if far == nil then
              S.lostWhy = string.format("c's target select opened with %d live monster(s) ($3A75 = $%02X), and c "
                .. "needs one off the cursor", count(lm), lm)
            end
          end
          return rawget(t, "latched") or absent
        end })
        S.step = H.setzerBattle({ S.negA, S.negB, S.pos }, { untilPlanDone = true, aimRefusedOk = true })
      end
    end
    local function forfeit(why)
      if S.phase ~= "plan" then return end
      lost = lost + 1
      H.log(string.format("[%s] f%d encounter %d: %s -- this battle is lost to the test (#%d of at most %d); the "
        .. "plan is dropped, the fight driver fights it out, and the next crowd plays it | party %s", TAG, H.frame,
        since, why, lost, MAX_LOST, care.partyLine()))
      H.assertEq(lost <= MAX_LOST, true, string.format("%d battles lost to the test (the bound is %d)", lost, MAX_LOST))
      -- the budget counts from this crowd, as from the last
      since = 0
      S.phase = "fight"
    end
    if S.phase == "plan" and H.battleActive() then
      local why = S.lostWhy or care.lostPoint({ fell = false })
      if why then forfeit(why) end
    end
    if S.phase == "plan" then
      local r = S.step:tick()
      if r ~= "done" then return r end
      local recs = H.vars.setzer
      if #recs == 1 and far ~= nil and recs[1].mon0[far] and not recs[1].mon0[far].alive then
        -- its slot fell between the confirm and the exec, and the engine
        -- aimed it elsewhere (vanilla's retarget): not the aim's doing
        forfeit(string.format("the aimed hire's slot %d fell before it ran (exec f%d, targets $%02X)", far,
          recs[1].f, recs[1].targets))
      elseif #recs == 0 and not H.battleLoadStarted() and rawget(S.pos, "aimRefused") == nil then
        forfeit("the battle ended before c ran")
      end
    end
    if S.phase == "plan" then
      local recs = H.vars.setzer
      H.log(string.format("[%s] a (slot %d, no monster): %s", TAG, absent, tostring(rawget(S.negA, "aimRefused"))))
      H.log(string.format("[%s] b (off the cursor, walking off): %s", TAG, tostring(rawget(S.negB, "aimRefused"))))
      H.assertEq(rawget(S.negA, "aimRefused") ~= nil, true, string.format("a hire aimed at slot %d, which no monster "
        .. "holds, is refused at target select", absent))
      H.assertEq(rawget(S.negB, "aimRefused") ~= nil, true, "a hire aimed off the cursor with walking off is "
        .. "refused, not confirmed where the cursor stands")
      H.assertEq(rawget(S.pos, "aimRefused"), nil, string.format("the hire aimed at live slot %s is not refused", tostring(far)))
      H.assertEq(#recs, 1, "exactly one hire executed: the aimed one")
      H.assertEq((rawget(S.pos, "aim") or { presses = 0 }).presses > 0, true, "the aimed hire walked the cursor")
      H.log(string.format("[%s] c: aimed at slot %d, the hire's targets $%02X, purse %d -> %d (fee %d)", TAG, far,
        recs[1].targets, S.gil0, gil(), recs[1].level * 50))
      H.assertEq(recs[1].targets, 1 << far, string.format("the aimed hire lands on slot %d and no other", far))
      -- a hire the engine aimed (SETZER Zombied or Muddled by the time it
      -- ran, set aside by H.setzerBattle and its plan entry played again,
      -- #433) paid its own fee, read at its TakeGil
      local aside, asideN = 0, 0
      for _, t in ipairs(H.vars.setzerTaken or {}) do
        asideN = asideN + 1
        for _, c in ipairs(t.costs or {}) do aside = aside + c end
      end
      H.log(string.format("[%s] set aside (the engine's aim): %d row(s), %d gil", TAG, asideN, aside))
      H.assertEq(S.gil0 - gil() - aside, recs[1].level * 50, "the purse paid one fee: no refused hire was paid for")
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
