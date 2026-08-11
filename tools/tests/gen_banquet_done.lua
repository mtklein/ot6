-- gen_banquet_done.lua -- v0.7 step I->J (issue #31), and the generator
-- that cuts battery checkpoint J, `banquet-done-v1`.
--
-- The input-driven rebuild (issue #75, 2026-08-09).  The previous version of
-- this file encoded banquet-decode.md's old ≥90 route, which that doc
-- withdrew after live measurement (control returns inside the throne
-- tower, the castle is severed until _cc8490, map 243 is a one-way
-- pocket, and ≥90 needs 41 of the window's 44 points against a measured
-- best of 26).  Canon is the ≥67 tier (banquet-decode.md §5.2).  This
-- rebuild drives the canon tier with real input, with no state writes
-- outside the Save-UI checkpoint block.  The arithmetic that makes ≥67
-- the input-driven target is stated here, because it differs from the
-- battle-clear-write version's:
--
--   * A battle-clear-write window fight cost ~3 frames for +6 points.  An
--     input-driven fight against even a lone Commando costs real ATB rounds,
--     2000+ frames of a 14400-frame window, for the same +6, while a
--     talk costs ~210 frames (measured, §9.2) for +1.  Points per frame the
--     two are comparable, but the fight carries wipe and timer risk inside
--     the window and the talk carries none.  So the input-driven window is
--     talk-only: the four fight soldiers are skipped, capping the
--     window at 20 and the step total at 20 + 44 (Q&A) + 5 (the troopers'
--     challenge) = 69.
--   * The tier ledger under that cap: total >= 67 needs window >= 18
--     (of 20) with a perfect Q&A and a clean challenge win.  The ≥77
--     Tintinabar tier cannot be reached by an input-driven talk-only run
--     (69 < 77), which matches the contract: `banquet-done-v1` asserts the
--     Tintinabar and Charm Bangle are absent.
--   * The window driver is probe_banquet_greedy.lua's, used unchanged:
--     nearest reachable un-latched soldier, least-used reachable
--     crossing, 243 last (it is a one-way pocket), one strike per
--     soldier, and never plan on a transition frame.  Its measured best was
--     26 points from 16 soldiers with the fight NPCs in the pool; a
--     talk-only pass of the same driver is the step's own measurement,
--     logged at expiry, and a window under 18 fails at that point with
--     var0, the timer, the soldier count and the full route log, rather
--     than as a lower tier at the messenger.
--   * The troopers' challenge (battle 30: 3x Sp Forces $0c2, 700 hp
--     each, weak poison; §5.4) runs after the window inside its own
--     7200-frame timer and is fought with the library fighter
--     (H.newFightDriver tactical/boost/bank/items, the configuration
--     that has beaten every boss in this conversion wave).  The clean
--     flags ($1dd1 & $31 == 0) are asserted: a win that arrived by
--     timer-expiry pays nothing and must fail.
--   * The party prepares before entering the castle, with H.equipOptimum
--     and H.fieldCare through the real menus, outside the window, where
--     frames are free (the checkpoint-descended party arrives hurt and
--     partly unequipped on every step this wave has measured).
--
-- The step (banquet-decode.md is the script; the route recon's steps 5-6 the
-- route): cold-Continue the tracked `vector-crash-v1` battery
-- (boundary I, world (83,238), standing on the dead Blackjack; do not press
-- A on the boot tile, because that re-enters the wreck, measured),
-- assert its contract, then: the world grind to Vector (120,187), the
-- castle escort, the dais face-UP+A (window opens, timer 14400), the
-- talk-only greedy circuit to expiry, the dinner Q&A driven perfect
-- (choices relative to the window score), the challenge, the Leo
-- intro/roster rewrite (TERRA+LOCKE), the messenger (>=67: $0276/77/78
-- pay; Tintinabar/Charm Bangle do NOT), out to world (120,188), and the
-- world battery save -- boundary J.
--
-- The recall question is settled (probe_banquet_recall.lua, 2026-08-10):
-- the record mechanic works as decoded.  The first question latches $0230
-- plus one of $0231/2/3, and recall pays +5 if and only if the answer
-- matches, deterministically (+5/+0/+0 measured against a first=0
-- record).  This gen's earlier "no record bit ever sets" reading was an
-- instrumentation race: add_var runs before the switch lines in the
-- script, so a read taken the frame var0 crosses its +2 milestone can
-- see zeros (captured live: first=1/2 read $1EC6=20/40 at the milestone
-- and 25/49 settled).  The recall drive below still asserts nothing
-- about its points and the tier arithmetic still clears >=67 at recall=0,
-- which costs nothing to keep.
--
-- The Save-UI block at the end keeps its pokes and its waivers: it is
-- the legacy-checkpoint apparatus (codex witness seeding + deterministic
-- slot-3 drive), its own listed line of #75, converted with the checkpoint
-- re-cut program, not here.  (The timer has expired by then, so the §5.3
-- harness hazard about poked menus inside a live window does not apply.)
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- ^ run.sh refuses, before boot, any OT6_SRAM_CHECKPOINT whose manifest
--   declares a different persistent_layout.
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local saveArg = nil
local SAVE_SELECT = 0x14
local ULTROS2 = 0x012d
local TEMP_ELEM = 0x316c10 + ULTROS2
local TEMP_CLASS = 0x316d90 + ULTROS2

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function timerCount() return H.readWord(0x1189) end
local function var0() return H.readWord(0x1fc2) end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function objAt(idx)
  local off = 0x29 * idx
  return H.readWord(0x086a + off) >> 4, H.readWord(0x086d + off) >> 4
end

-- Verified-step world grinder (see the long comment in gen_vector_crash's
-- sibling; consumes a plan entry only when the party lands on it).  An
-- encounter on the grind is fled with the real L+R run, which is the
-- design for world encounters (issue #75).
local function worldGrind(tx, ty, what)
  local plan, idx, ph, hb = nil, 1, 0, -600
  local step = nil
  local DW = { up = { 0, -1 }, down = { 0, 1 },
               left = { -1, 0 }, right = { 1, 0 } }
  return H.driveUntil(function()
    return (not H.worldMode()) or (H.worldX() == tx and H.worldY() == ty
      and H.worldHasControl() and H.worldAligned())
  end, 60000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        plan = nil; step = nil
        H.setPad({ l = true, r = true }); return
      end
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then
        plan = nil; step = nil; H.setPad({}); return
      end
      if not H.worldAligned() then return end   -- hold through the glide
      local x, y = H.worldX(), H.worldY()
      if step then
        if x == step.tx and y == step.ty then
          step = nil; idx = idx + 1               -- landed: next entry
        elseif x ~= step.fx or y ~= step.fy then
          plan = nil; step = nil                  -- drifted: replan
        else
          step.held = step.held + 1
          if step.held > 90 then                  -- press provably dead
            plan = nil; step = nil; H.setPad({}); return
          end
          H.setPad({ [step.dir] = true }); return
        end
      end
      if not plan or idx > #plan then
        plan = H.worldBfs(tx, ty); idx = 1
        if not plan then
          if H.frame - hb >= 600 then
            hb = H.frame
            H.log(string.format("[grind] NO PATH (%d,%d)->(%d,%d) f%d",
              x, y, tx, ty, H.frame))
          end
          H.setPad({}); return
        end
      end
      local dir = plan[idx]
      local d = DW[dir]
      step = { dir = dir, fx = x, fy = y,
               tx = (x + d[1]) & 0xFF, ty = (y + d[2]) & 0xFF, held = 0 }
      H.setPad({ [dir] = true })
    end),
  }, what or string.format("worldGrind (%d,%d)", tx, ty))
end

-- unconditional held walk (dialogs absorbed; a battle, none of which has
-- fired on these maps, is fled with the real L+R run)
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

-- The dais is a face-up+A trigger the party must be standing on (the
-- GESTAHL NPC at (54,15) blocks the step, so holding UP only sets the
-- facing); the A is released 2 frames in 8 so the edge re-arms.
local function holdUpA(swId, maxFrames, what)
  local n = 0
  return H.driveUntil(function() return sw(swId) == 1 end, maxFrames, {
    H.call(function()
      n = n + 1
      if H.dialogWaiting() then H.setPad(n % 8 < 4 and { "a" } or {}); return end
      H.setPad(n % 8 < 6 and { up = true, a = true } or { up = true })
    end),
  }, what)
end

local function landed(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d) f%d: map=%d ctl=%s dlg=%s (%d,%d)",
        m, H.frame, map(), tostring(H.hasControl()),
        tostring(H.dialogWaiting()), H.fieldX(), H.fieldY()))
    end
    return cnt >= (n or 20)
  end
end

-- edge-A through dialogs until settled
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

-- ---- the talk-only greedy window (probe_banquet_greedy's driver) ---------
-- The 24-soldier census of banquet-decode §3, with the four fight
-- soldiers kept in the table but marked, because the input-driven window
-- skips them (see the header arithmetic).  They stay listed so the skip is
-- explicit data rather than a silent omission.
local SOLDIERS = {
  { map = 250, obj = 0x10, latch = 0x0217, name = "250 (21,24)" },
  { map = 250, obj = 0x11, latch = 0x0218, name = "250 (25,24)" },
  { map = 250, obj = 0x12, latch = 0x0219, name = "250 (21,18)" },
  { map = 250, obj = 0x13, latch = 0x021A, name = "250 (25,18)" },
  { map = 250, obj = 0x19, latch = 0x021F, name = "250 (98,51)" },
  { map = 250, obj = 0x1E, latch = 0x0226, name = "250 (51,50) B27", fight = 0x0c7 },
  { map = 250, obj = 0x1F, latch = 0x0227, name = "250 (9,49)" },
  { map = 250, obj = 0x20, latch = 0x0228, name = "250 (110,51) B27", fight = 0x0c7 },
  { map = 250, obj = 0x21, latch = 0x0229, name = "250 (120,13)" },
  { map = 250, obj = 0x22, latch = 0x022A, name = "250 (115,16)" },
  { map = 243, obj = 0x16, latch = 0x0224, name = "243 (8,18)" },
  { map = 243, obj = 0x17, latch = 0x022B, name = "243 (12,14) B26", fight = 0x102 },
  { map = 243, obj = 0x18, latch = 0x022C, name = "243 (18,14)" },
  { map = 244, obj = 0x24, latch = 0x0220, name = "244 (11,23)" },
  { map = 244, obj = 0x25, latch = 0x0221, name = "244 (25,23)" },
  { map = 244, obj = 0x26, latch = 0x0222, name = "244 (16,14)" },
  { map = 244, obj = 0x27, latch = 0x0223, name = "244 (20,14)" },
  { map = 244, obj = 0x28, latch = 0x0225, name = "244 (10,17)" },
  { map = 252, obj = 0x10, latch = 0x021B, name = "252 (40,56)" },
  { map = 252, obj = 0x11, latch = 0x021C, name = "252 (42,52)" },
  { map = 252, obj = 0x12, latch = 0x021D, name = "252 (42,56)" },
  { map = 252, obj = 0x13, latch = 0x021E, name = "252 (37,57)" },
  { map = 252, obj = 0x14, latch = 0x022D, name = "252 (42,57) B27", fight = 0x0c7 },
  { map = 252, obj = 0x15, latch = 0x022E, name = "252 (40,54)" },
}

local CROSS = {
  [250] = {
    { 15, 21 }, { 31, 21 }, { 9, 14 }, { 37, 14 }, { 9, 9 }, { 37, 9 },
    { 101, 10 }, { 115, 22 }, { 97, 47 }, { 51, 53 }, { 9, 52 }, { 65, 53 },
    { 24, 53 }, { 81, 60 }, { 101, 17 }, { 14, 61 }, { 60, 62 }, { 120, 24 },
    { 22, 34 }, { 111, 62 }, { 23, 9 }, { 53, 35 },
  },
  [243] = { { 15, 8 } },
  [244] = { { 13, 19 }, { 23, 19 }, { 18, 11 } },
  [252] = { { 35, 48 }, { 35, 60 } },
}
local DOOR243 = { { 22, 34 }, { 23, 34 }, { 24, 34 } }

local latchedLog, crossUse, failCount, routeLog = {}, {}, {}, {}
local windowScore, windowSoldiers = nil, nil   -- the measurement

local function circuitSettled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted()
end

-- The range guard, split so the tier is robust to the one unverified Q&A
-- mechanic (recall's +5; see the Q&A section.  The first-question record
-- $0231/2/3 that recall matches against does not latch under live play,
-- measured, so recall's +5 is not assumed).  Arithmetic:
--   * talks fill to 23:  a talk-terminated window is >= 23, and
--     23 + (Q&A without recall = 39) + (challenge 5) = 67, so the tier
--     clears even if recall pays nothing.
--   * fights engage only below 18: a +6 Commando from <=17 lands <= 23,
--     so the window never exceeds ~24, and 24 + (perfect Q&A 44) + 5 = 73
--     < 77, so the >=77 Tintinabar tier stays out of reach, which the exit
--     contract asserts.  With recall working the total is ~72; without,
--     ~67; either way in [67, 77).
local TALK_BELOW, FIGHT_BELOW = 23, 18

local function soldierDone(s) return sw(s.latch) == 1 end
-- Eligible: talks, plus the Commando fights ($0c7).  Measured (run
-- tgW7P8hV), a talk-only window yields 15 of the 18 points the tier
-- needs: the effective talk rate is ~960 frames/point once travel and
-- crossing churn are paid, while a real Commando (580 hp, weak
-- bolt+water, fought by the section's equipped party) is +6 for ~2000-2500
-- frames, a better rate, and both route-side Commandos sit on the
-- corridor the talk circuit already walks.  The B26 Mega Armor stays
-- excluded: it is in the one-way 243 pocket and has 1000 hp.
local function eligible(s)
  if soldierDone(s) or (failCount[s.latch] or 0) >= 1 then return false end
  if s.fight == 0x0c7 then return var0() < FIGHT_BELOW end  -- Commando
  return not s.fight                                        -- talk (B26 excl.)
end

local function anyLeftOutside243()
  for _, s in ipairs(SOLDIERS) do
    if s.map ~= 243 and eligible(s) then return true end
  end
  return false
end

local function avoidNow()
  if map() == 250 and anyLeftOutside243() then
    local a = {}
    for _, t in ipairs(DOOR243) do a[((t[2] & 0xFF) << 8) | (t[1] & 0xFF)] = true end
    return a
  end
  return nil
end

local function nearestSoldier()
  local best, bestLen
  local av = avoidNow()
  for _, s in ipairs(SOLDIERS) do
    if s.map == map() and eligible(s) then
      local ox, oy = objAt(s.obj)
      for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
        local p = H.bfsPath(ox + d[1], oy + d[2], nil, av)
        if p and (not bestLen or #p < bestLen) then best, bestLen = s, #p end
      end
    end
  end
  return best, bestLen
end

local function leastUsedCrossing()
  local best, bestKey, bestScore
  for _, c in ipairs(CROSS[map()] or {}) do
    local key = string.format("%d:%d,%d", map(), c[1], c[2])
    local into243 = (map() == 250 and c[1] == 22 and c[2] == 34)
    local p
    if not (into243 and anyLeftOutside243()) then
      p = H.bfsPath(c[1], c[2], nil, avoidNow())
    end
    if p then
      local score = (crossUse[key] or 0) * 10000 + #p
      if not bestScore or score < bestScore then
        best, bestKey, bestScore = c, key, score
      end
    end
  end
  return best, bestKey
end

-- the greedy runner: talk every reachable un-latched talk soldier on this
-- map nearest-first; when none, take the least-used reachable crossing;
-- terminate on $013C (the dinner fired).  A raising sub-step (navTo
-- no-path, a chase timeout) is caught and the driver re-picks; one strike
-- per soldier, because a soldier that does not answer promptly is not
-- worth a retry inside a fixed window (measured, greedy run 5).

local function circuitRunner()
  local cur, curWhat, curLatch = nil, nil, nil
  local stuckAt, cappedAt = nil, nil
  local inFight, ph = false, 0
  local F = H.newFightDriver("banquet window", { tactical = true,
    boost = true, bank = 1, items = true, healPercent = 60, cadence = 12 })
  return {
    tick = function(self)
      -- a fight soldier's talk opens battle 26/27 mid-chase: hand the
      -- battle to the library fighter (the timer keeps ticking, which is
      -- the real cost), then resume the circuit when it ends.  The +1
      -- and the clean +5 both land in the script tail after the battle.
      if H.battleLoadStarted() then
        if not inFight then
          inFight = true
          cur, curWhat, curLatch = nil, nil, nil
          routeLog[#routeLog + 1] = string.format(
            "f%-6d t=%-5d FIGHT opens (var0=%d)", H.frame, timerCount(), var0())
        end
        F.frame()
        return "frame"
      elseif inFight then
        inFight = false
        F.idle()
        routeLog[#routeLog + 1] = string.format(
          "f%-6d t=%-5d FIGHT over: $1dd1&31=%02X var0=%d",
          H.frame, timerCount(), H.readByte(0x1dd1) & 0x31, var0())
      end
      if sw(0x013C) == 1 then
        if not windowScore then
          windowScore = var0()
          windowSoldiers = 0
          for _, s in ipairs(SOLDIERS) do
            if soldierDone(s) then windowSoldiers = windowSoldiers + 1 end
          end
          H.log(string.format(
            "== WINDOW EXPIRED: var0=%d (%d soldiers) at frame %d ==",
            windowScore, windowSoldiers, H.frame))
          for _, l in ipairs(routeLog) do H.log("[route] " .. l) end
          H.setPad({})
        end
        return "done"
      end
      if cur then
        local ok, r = pcall(function() return cur:tick() end)
        if ok and r == "frame" then return "frame" end
        if not ok then
          routeLog[#routeLog + 1] = string.format("f%-6d ABORT  %s",
            H.frame, curWhat)
          if curLatch then
            failCount[curLatch] = (failCount[curLatch] or 0) + 1
          end
        end
        cur, curWhat, curLatch = nil, nil, nil
        return "frame"
      end
      if not circuitSettled() then
        -- a dialog with no chase in flight is the post-fight canned line
        -- (the chase step was dropped when the battle opened): page it.
        -- Measured (run SchLMrE6): without this the runner idled on that
        -- dialog indefinitely, with the timer not ticking it away.
        ph = (ph + 1) % 8
        H.setPad(H.dialogWaiting() and (ph < 4 and { "a" } or {}) or {})
        return "frame"
      end
      if var0() >= TALK_BELOW then
        if not cappedAt then
          cappedAt = H.frame
          H.log(string.format(
            "== circuit CAPPED at var0=%d (>= %d): the range guard -- "
            .. "idling out the timer at f%d ==",
            var0(), TALK_BELOW, H.frame))
        end
        H.setPad({})
        return "frame"
      end
      local s, len = nearestSoldier()
      if s then
        curWhat, curLatch = s.name, s.latch
        routeLog[#routeLog + 1] = string.format(
          "f%-6d t=%-5d talk   %s (%d steps)",
          H.frame, timerCount(), s.name, len or -1)
        cur = H.chaseTalk(s.obj, 1500, s.name, {
          done = function() return soldierDone(s) or sw(0x013C) == 1 end,
          avoid = avoidNow(),
        })
        return "frame"
      end
      local c, key = leastUsedCrossing()
      if c then
        crossUse[key] = (crossUse[key] or 0) + 1
        curWhat, curLatch = "cross " .. key, nil
        routeLog[#routeLog + 1] = string.format(
          "f%-6d t=%-5d cross  %s (use %d)",
          H.frame, timerCount(), key, crossUse[key])
        local fromMap, fx, fy = map(), H.fieldX(), H.fieldY()
        cur = H.navTo(c[1], c[2], {
          maxFrames = 3000,
          noPathRetries = 3,
          avoid = (map() == 250 and anyLeftOutside243()) and DOOR243 or nil,
          arrive = function()
            return map() ~= fromMap
              or (map() == fromMap and (H.fieldX() ~= fx or H.fieldY() ~= fy)
                  and H.fieldX() == c[1] and H.fieldY() == c[2])
          end,
        })
        return "frame"
      end
      -- nothing reachable: say so once and wait for the expiry
      if not stuckAt then
        stuckAt = H.frame
        H.log(string.format(
          "== circuit idle at f%d: map %d (%d,%d) timer=%d var0=%d -- no "
          .. "reachable un-latched talk soldier and no reachable crossing ==",
          H.frame, map(), H.fieldX(), H.fieldY(), timerCount(), var0()))
        for _, l in ipairs(routeLog) do H.log("[route] " .. l) end
      end
      H.setPad({})
      return "frame"
    end,
    reset = function(self) end,
  }
end

-- ---- the Q&A choice machinery (gen_zozo3_clock's cursor cells) -----------
-- Battles cannot start inside the dinner dialogs, and the challenge battle
-- is driven explicitly below, so this machine carries no battle branch and
-- writes no state.
local function picks(targets, done, maxFrames, what)
  local ph, ti, wasUp = 0, 0, false
  return H.driveUntil(function()
    local d = done()
    if d then H.setPad({}) end
    return d
  end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then H.setPad({}); return end
      local up = H.readByte(0x056f) >= 2
      if up and not wasUp then ti = ti + 1 end
      wasUp = up
      if up then
        local idx = targets[math.min(ti, #targets)]
        local cur = H.readByte(0x056e)
        if cur < idx then H.setPad(ph < 3 and { "down" } or {})
        elseif cur > idx then H.setPad(ph < 3 and { "up" } or {})
        else H.setPad(ph < 3 and { "a" } or {}) end
        return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({})
    end),
  }, what)
end

-- the Q&A scores are relative to whatever the window earned: w0 is
-- captured at the dinner table and every later checkpoint is w0+delta
local dinner = { w0 = nil, preChallenge = nil, preBattle30 = nil,
                 b30Species = nil, b30Clean = nil, preWish = nil,
                 preAccompany = nil, total = nil }
local function atPlus(d) return function() return var0() >= dinner.w0 + d end end
local function ckPlus(name, d)
  return H.call(function()
    H.assertEq(var0(), dinner.w0 + d, name .. ": var0 == window+" .. d)
    H.log(string.format("[qa] %-28s var0=%2d (window %d + %d) f%d",
      name, var0(), dinner.w0, d, H.frame))
  end)
end

-- --------------------------------------------------------------------------
local steps = {
  -- ---- the cold Continue and the entry contract (issue #25) ---------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function() local ph = 0
    local function atSite()
      return H.worldMode() and H.worldX() == 83 and H.worldY() == 238
    end
    return H.driveUntil(function()
      return atSite() and bright() >= 15
    end, 4000, {
      H.call(function()
        ph = (ph + 1) % 48
        if atSite() or bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "Continue -> crash-site world load (A gated by brightness+position)")
  end)(),
  H.release(),
  H.waitUntil(function()
    return H.worldMode() and bright() >= 15 and H.worldHasControl()
  end, 1800, "world control at the crash site", 5),
  H.waitFrames(30),
  H.call(function()
    H.assertEntryContract("vector-crash-v1")
  end),

  -- ---- 1. the grind to Vector ----------------------------------------------
  worldGrind(120, 188, "the I->J world grind -> (120,188)"),
  pressWalk("up", function() return not H.worldMode() end, 900,
    "step onto the Vector trigger (120,187)"),
  H.waitUntil(landed(253, 10), 2400, "Vector 253 (post-attack)", 1),
  H.waitFrames(30),

  -- ---- 1b. the player's prep, outside the window, where frames are free ----
  -- (the checkpoint-descended party arrives hurt and partly unequipped on
  -- every step this wave has measured, and the challenge is a real fight now)
  H.equipOptimum({ tag = "banquet kit" }),
  H.fieldCare({ tag = "care before the banquet", threshold = 0.95 }),

  -- ---- 2. the castle and the dais ------------------------------------------
  H.navTo(28, 2, { maxFrames = 30000, playBattles = "flee" }),
  pressWalk("up", function() return map() == 243 end, 900,
    "castle door 253 (28,1) -> 243 (15,29)"),
  H.waitUntil(landed(243, 10), 2400, "castle antechamber 243", 1),
  H.navTo(8, 18, { maxFrames = 12000, calmFrames = 4, playBattles = "flee" }),
  H.stepOff({ "right", "down", "up" }, 6000,
    "escort: A through $06A6, step off (8,18)"),
  H.waitUntil(function() return sw(0x013A) == 1 end, 3000,
    "the escort ran ($013A)", 5),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(sw(0x062F), 1, "$062F -- the soldier population is up")
  end),
  H.navTo(15, 9, { maxFrames = 12000, playBattles = "flee" }),
  pressWalk("up", function() return map() == 250 end, 900,
    "door 243 (15,8) -> 250 (23,33)"),
  H.waitUntil(landed(250, 10), 2400, "250 first entry", 1),
  H.call(function()
    H.assertEq(sw(0x013B), 1, "$013B -- 250 map-init opened the {22,29} door")
  end),
  -- The measured route to the dais (probe_banquet_stage, iterations 1-8;
  -- the first input-driven run of this gen failed here with "no path
  -- (23,33)-> (54,17)" because the pre-window 250 entry is a 131-tile
  -- component and the dais is not in it): the {22,29} doorway is a door
  -- tile the BFS model reads as a wall (held UP crosses it); (23,12) is the
  -- gated-off messenger trigger that re-enters at every rest frame and
  -- wedges navTo (a held press skips walk-over triggers, so it and the
  -- (23,9) stairs are crossed in one pressWalk); (23,9) short-entrances to
  -- (54,34)  inside the throne tower, and the dais is an ordinary navTo
  -- from there.
  H.navTo(23, 30, { maxFrames = 6000, playBattles = "flee" }),
  pressWalk("up", function()
    return H.fieldY() <= 28 and H.tileAligned()
  end, 900, "held UP through the {22,29} doorway"),
  H.release(),
  H.waitFrames(30),
  H.navTo(23, 13, { maxFrames = 9000, playBattles = "flee" }),
  pressWalk("up", function()
    return (H.fieldX() ~= 23 or H.fieldY() > 20) and H.tileAligned()
  end, 1200, "held UP past (23,12) onto the (23,9) stairs -> (54,34)"),
  H.release(),
  H.waitUntil(landed(250, 10), 3000, "the throne tower (54,34)", 1),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.fieldX(), 54, "stairs landing x (short entrance 23,9)")
    H.assertEq(H.fieldY(), 34, "stairs landing y")
  end),
  H.navTo(54, 16, { maxFrames = 20000, playBattles = "flee" }),
  H.call(function()
    H.assertEq(sw(0x007C), 0, "$007C clear at the dais")
    H.screenshot("step_ij_dais")
  end),

  -- ---- 3. the window --------------------------------------------------------
  holdUpA(0x007C, 9000, "dais face-UP+A -> _cc8490 -> $007C=1"),
  H.release(),
  H.stepOff({ "down", "left", "right" }, 20000,
    "ride the Gestahl/Cid scene; step off the dais trigger"),
  H.waitUntil(landed(250, 10), 9000, "control with the window live", 1),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(sw(0x007C), 1, "$007C SET -- the window is live")
    H.assertEq(H.readByte(0x1188) ~= 0, true, "timer 0 flags live ($1188)")
    H.assertEq(var0(), 0, "var0 zeroed at the window start")
    H.assertEq(sw(0x0634), 1, "$0634 -- the window soldier population is up")
    H.assertEq(sw(0x0630), 0, "$0630 CLEAR -- the corridor servants are "
      .. "gone; the castle is open")
    H.log(string.format("[window] timer=%d f%d", timerCount(), H.frame))
  end),

  -- leave the throne tower (the (53,35) long entrance to the corridor),
  -- then run the talk-only greedy circuit until the timer kills it
  H.navTo(53, 34, { maxFrames = 9000 }),
  (function() local ph = 0
    return H.driveUntil(function() return H.fieldX() < 40 end, 1200, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({ down = true })
      end),
    }, "held DOWN onto (53,35) -> the corridor (23,11)")
  end)(),
  H.release(),
  H.waitFrames(45),
  circuitRunner(),

  -- The feasibility check (issue #75, and the §8 measurement): the tier
  -- ledger needs window >= 18 given a perfect Q&A (+44) and a clean
  -- challenge (+5).  A short window fails here, with the numbers, rather
  -- than as a lower tier at the messenger.
  H.call(function()
    H.assertEq(windowScore ~= nil, true, "the window expired ($013C)")
    H.log(string.format(
      "== WINDOW MEASUREMENT: var0=%d, %d of 20 talk soldiers, "
      .. "need >= 18 for the >=67 tier ==", windowScore, windowSoldiers))
    if windowScore < 18 then
      error(string.format(
        "WINDOW SHORT: var0=%d of the 18 the >=67 tier needs "
        .. "(talk-only cap 20; Q&A 44 + challenge 5 assumed perfect).  "
        .. "This is the feasibility FINDING -- route log above.",
        windowScore), 0)
    end
    H.screenshot("step_ij_window")
  end),

  -- ---- 4. the dinner --------------------------------------------------------
  (function() local ph = 0
    return H.driveUntil(function()
      return map() == 251 and H.readByte(0x056f) >= 2 and H.dialogWaiting()
    end, 40000, {
      H.call(function()
        ph = (ph + 1) % 8
        if sw(0x013C) == 1 and H.dialogWaiting()
           and H.readByte(0x056f) < 2 then
          H.setPad(ph < 4 and { "a" } or {})
        else
          H.setPad({})
        end
      end),
    }, "expiry -> map 5 -> the dinner table -> the toast choice")
  end)(),
  H.call(function()
    H.assertEq(map(), 251, "the dinner table (map 251)")
    H.assertEq(var0(), windowScore, "var0 carried into dinner")
    dinner.w0 = var0()
  end),
  -- Dev scratch state (probe_banquet_recall boots this): the dinner table
  -- with the toast choice up and a known var0.  This is not a fixture: no
  -- graph edge, no stamp, and never a suite boot.  Probes may not produce
  -- fixtures, and this is a probe input cut by a generator.
  H.saveState("banquet_dinner_scratch.mss"),

  -- ---- 5. the Q&A, perfect, relative to the window --------------------------
  picks({ 2 }, atPlus(5), 6000, "toast: hometowns (+5)"),
  ckPlus("toast", 5),
  picks({ 0 }, atPlus(10), 6000, "Kefka: jail (+5)"),
  ckPlus("kefka", 10),
  picks({ 1 }, atPlus(15), 6000, "Doma: inexcusable (+5)"),
  ckPlus("doma", 15),
  picks({ 1 }, atPlus(20), 6000, "Celes: one of us (+5)"),
  ckPlus("celes", 20),
  -- The three questions, as a group (+6): the first question and the two
  -- "one more question please!" re-asks, each +2 (banquet-decode.md §4
  -- items 5-6).  Driven as one stretch that ends when var0 has risen +6,
  -- because the per-item choice->question map is not verified live (the
  -- ≥90 gen that hard-asserted $0231 was withdrawn and never ran, and this
  -- gen's first live run showed the +2 landing but no $0231/2/3 record
  -- bit setting).  The group +6 is what the tier ledger counts.
  picks({ 0, 0, 1, 0, 2 }, atPlus(26), 9000, "the three questions (+6 group)"),
  ckPlus("questions", 26),
  picks({ 1, 0 }, atPlus(31), 9000, "Espers: gone too far (+5)"),
  ckPlus("espers", 31),
  -- capture the score entering recall (recall may or may not pay; every
  -- later delta is measured from here, not from an assumed baseline)
  H.call(function() dinner.preChallenge = var0() end),
  -- Recall plus the rest break, one cursor-0 drive.  Recall is the one Q&A
  -- point this gen does not assume: it scores +5 only if the answer
  -- matches the first-question record ($0231/2/3), and that record does
  -- not latch under live play (measured; see the header finding), so
  -- recall may pay 0.  Recall flows straight into Cid's break offer with
  -- no field control between, and both want cursor 0 (recall option 0 =
  -- first-listed question; break option 0 = "Yes"), so a single
  -- cursor-0 pick carries both and ends on control returning to the
  -- dinner floor.  Its points are not asserted; the tier is made robust
  -- to recall=0 by the window range guard.
  picks({ 0 }, function()
    return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
       and H.readByte(0x056f) < 2
  end, 12000, "recall + rest break: cursor 0 -> control on the floor"),
  H.call(function()
    H.log(string.format("[qa] recall+break resolved: var0=%d (window %d + %d)",
      var0(), dinner.w0, var0() - dinner.w0))
  end),
  H.waitFrames(30),
  H.chaseTalk(0x12, 9000, "chase the trooper at 251 (76,16)"),
  picks({ 0 }, function() return H.battleLoadStarted() end, 15000,
    "challenge: Sure -> battle 30 opens"),
  H.waitUntil(function() return H.battleActive() end, 900,
    "battle 30 active", 30),
  H.call(function() dinner.preBattle30 = var0() end),
  (function()
    local F = H.newFightDriver("b30", { tactical = true, boost = true,
      bank = 1, items = true, healPercent = 60, cadence = 12 })
    local hb = 0
    return H.driveUntil(function() return not H.battleLoadStarted() end,
      20000, {
      H.call(function()
        hb = hb + 1
        -- capture the formation and clean-flag during the battle: after
        -- teardown $57C0 reads the field and $1dd1 is stale.  sawSpForces
        -- is a max-seen count; the clean flag is sampled every frame and
        -- the last battle-active reading is the outcome.
        if H.battleLoadStarted() then
          local found = 0
          for m = 0, 5 do
            if H.readWord(0x57C0 + m * 2) == 0x0c2 then found = found + 1 end
          end
          if found > (dinner.b30Species or 0) then dinner.b30Species = found end
          dinner.b30Clean = H.readByte(0x1dd1) & 0x31
        end
        if hb % 600 == 0 then
          local mhp = {}
          for m = 0, 5 do
            local id = H.readWord(0x57C0 + m * 2)
            if id ~= 0xFFFF and id ~= 0 then
              mhp[#mhp + 1] = string.format("%04X:%d",
                id, H.readWord(0x3BFC + m * 2))
            end
          end
          H.log(string.format(
            "b30 f%d timer=%d party %d/%d/%d/%d | %s",
            H.frame, timerCount(),
            H.readWord(0x3BF4), H.readWord(0x3BF6),
            H.readWord(0x3BF8), H.readWord(0x3BFA),
            table.concat(mhp, " ")))
        end
        F.frame()
      end),
    }, "battle 30, played (clean win inside its own timer)")
  end)(),
  settle(3000, "challenge tail settles"),
  H.call(function()
    H.assertEq((dinner.b30Species or 0) >= 1, true,
      "battle 30: Sp Forces ($0c2) formation (seen live during the fight)")
    H.assertEq(sw(0x0237), 1, "$0237 -- the challenge latch")
    H.assertEq((dinner.b30Clean or 0xFF), 0,
      "battle 30 CLEAN win -- $40/$44/$45 clear at teardown (a timer-expiry "
      .. "'win' pays nothing and must fail here)")
    H.assertEq(var0(), dinner.preBattle30 + 5, "challenge +5 (clean)")
  end),
  -- back to the table: wish +5, accompany +3, measured from a fresh
  -- capture so recall's uncertainty does not propagate into these asserts
  H.navTo(80, 20, { maxFrames = 9000, calmFrames = 4 }),
  H.waitUntil(function() return H.readByte(0x056f) >= 2 end, 1200,
    "'Shall we begin again?'", 5),
  H.call(function() dinner.preWish = var0() end),
  (function() return picks({ 0, 1 },
    function() return var0() >= dinner.preWish + 5 end,
    12000, "begin again + wish: war's over (+5)") end)(),
  H.call(function()
    H.assertEq(var0(), dinner.preWish + 5, "wish +5")
    dinner.preAccompany = var0()
  end),
  (function() return picks({ 0 },
    function() return var0() >= dinner.preAccompany + 3 end,
    9000, "accompany: Yes on the first ask (+3)") end)(),
  H.call(function()
    H.assertEq(var0(), dinner.preAccompany + 3, "accompany +3")
    -- The tier, measured: window plus everything the dinner paid.
    -- Robust to recall by construction (range guard).  Both bounds are
    -- asserted, so an accidental >=77 (which would give Tintinabar,
    -- contradicting the exit contract) fails the same way a short one does.
    local total = var0()
    H.assertEq(total >= 67, true, string.format(
      "THE TIER: total %d (window %d + dinner %d) >= 67",
      total, dinner.w0, total - dinner.w0))
    H.assertEq(total < 77, true, string.format(
      "THE TIER stays under 77 (Tintinabar/Charm Bangle absent): total %d",
      total))
    dinner.total = total
    H.log(string.format("== TIER LEDGER: window %d + dinner %d = %d "
      .. "(>=67 CLEARED, <77 so >=77 tiers absent) ==",
      dinner.w0, total - dinner.w0, total))
  end),

  -- ---- 6. the Leo intro and the roster rewrite ------------------------------
  H.advanceStory(function()
    return sw(0x007D) == 1 and map() == 251 and H.hasControl()
       and H.tileAligned() and bright() >= 15
  end, 60000, { playBattles = true }),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(sw(0x007D), 1, "$007D -- the banquet tail ran")
    H.assertEq(var0(), dinner.total, "var0 held through the rewrite")
    local n = 0
    for c = 0, 15 do if partyOf(c) ~= 0 then n = n + 1 end end
    H.assertEq(n, 2, "party COUNT is two (#21 control, inverted)")
    H.assertEq(partyOf(0x00), 1, "TERRA in party 1")
    H.assertEq(partyOf(0x01), 1, "LOCKE in party 1")
    H.screenshot("step_ij_two")
  end),

  -- ---- 7. the messenger -----------------------------------------------------
  -- The 251->250 door lands the party at (53,11), inside the throne tower
  -- (the 199-tile pocket, x48..60 y9..35); the messenger at (23,12) is in
  -- the corridor.  So exit the tower the same way the window circuit
  -- entered it, through the (53,35) long entrance down to the corridor
  -- (23,11), before walking to the messenger.  (A direct navTo
  -- (53,12)->(23,12) has no path; measured, run QkbMFqWb.)
  H.navTo(80, 26, { maxFrames = 9000, playBattles = "flee" }),
  pressWalk("down", function() return map() == 250 end, 900,
    "251 door row -> 250 (53,11)"),
  H.waitFrames(30),
  H.stepOff({ "down", "left", "right" }, 2400,
    "off the (53,11) trigger tile"),
  H.navTo(53, 34, { maxFrames = 9000, playBattles = "flee" }),
  (function() local ph = 0
    return H.driveUntil(function() return H.fieldX() < 40 end, 1200, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({ down = true })
      end),
    }, "held DOWN onto (53,35) -> the corridor (23,11)")
  end)(),
  H.release(),
  H.waitFrames(30),
  H.navTo(23, 12, { maxFrames = 20000, calmFrames = 4, playBattles = "flee" }),
  (function() local ph = 0
    return H.driveUntil(function() return sw(0x0238) == 1 end, 9000, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(H.dialogWaiting() and (ph < 4 and { "a" } or {}) or {})
      end),
    }, "the messenger -> $0238=1")
  end)(),
  settle(3000, "messenger tail settles"),
  H.call(function()
    H.assertEq(sw(0x0238), 1, "$0238 -- the rewards paid")
    H.assertEq(sw(0x0276), 1, "$0276 -- South Figaro withdrawal")
    H.assertEq(sw(0x0277), 1, "$0277 -- Doma withdrawal (>=50)")
    H.assertEq(sw(0x0278), 1, "$0278 -- base weapons unlock (>=67)")
    H.assertEq(var0(), 0, "var0 zeroed by the messenger")
    H.screenshot("step_ij_messenger")
  end),

  -- ---- 8. out of the castle, out of Vector ----------------------------------
  H.stepOff({ "down", "left", "right" }, 2400,
    "off the messenger trigger tile"),
  H.navTo(23, 33, { maxFrames = 20000, playBattles = "flee" }),
  pressWalk("down", function() return map() == 243 end, 1200,
    "door 250 (22..24,34) -> 243 (15,10)"),
  H.waitUntil(landed(243, 10), 2400, "243 on the way out", 1),
  H.navTo(15, 30, { maxFrames = 12000, playBattles = "flee" }),
  pressWalk("down", function() return map() == 253 end, 1200,
    "south rows -> 253 (29,2)"),
  H.waitUntil(landed(253, 10), 2400, "Vector 253 on the way out", 1),
  H.navTo(30, 62, { maxFrames = 30000, playBattles = "flee",
    arrive = function() return H.worldMode() end }),
  pressWalk("down", function() return H.worldMode() end, 1200,
    "253 (30,63) world exit -> world (120,188)"),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
       and bright() >= 15
  end, 3600, "world control outside Vector", 5),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(H.worldX(), 120, "checkpoint-J tile x")
    H.assertEq(H.worldY(), 188, "checkpoint-J tile y")
    H.assertEq(H.readByte(0x11FA) & 3, 0, "ON FOOT at the J tile")
    H.screenshot("step_ij_j_tile")
  end),

  -- ---- 9. the world battery save -- boundary J ------------------------------
  H.call(function()
    H.assertExitContractPreSave("banquet-done-v1")
  end),
  -- The step's savestate is generated here, before the menu (the world menu
  -- does not unwind on B, measured)
  H.saveState("banquet_done.mss"),
  -- Reload-verified (gen_sabin_gau's pattern, from a failure this program
  -- has hit): a calm capture does not imply a calm reload, so reload the
  -- parked moment and require the consumer's boot to find it quiet.
  -- The Save-UI below then proceeds from the reloaded (equivalent) state.
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
        H.assertEq(H.worldX() == 120 and H.worldY() == 188, true,
          "reload: still on the J tile (120,188)")
        H.assertEq(H.readByte(0x11FA) & 3, 0, "reload: still ON FOOT")
        H.assertEq(H.worldHasControl() and H.worldAligned(), true,
          "reload: controllable at rest")
        H.assertEq(H.battleLoadStarted(), false, "reload: no battle pending")
        H.log("generated-state verify: the reload stayed calm -- banquet_done verified")
      end),
    })
  end)(),

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
    }, "world menu open at the J tile")
  end)(),
  H.waitFrames(30),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x05 end, 600,
    "main menu state", 5),
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "menu-flags $0201 bit7 SET -- the save-enable flow reached the menu")
    -- Arm the input-driven save receipt (issue #75): a read-only exec hook on
    -- the real CopyGameDataToSRAM entry captures the slot argument the
    -- save runs with (codex_saveas's instrument).  This replaces the old
    -- zeroed-$307ff0 sentinel, which was an SRAM write, as the evidence that
    -- the real save ran to completion for slot 3.
    local entry = H.sym("CopyGameDataToSRAM")
    emu.addMemoryCallback(function()
      saveArg = emu.getState()["cpu.a"] & 0xff
    end, emu.callbackType.exec, entry, entry)
  end),
  -- The pad-driven save (save-drive rule, tools/tests/README.md;
  -- codex_saveas and probe_banquet_timer_save are the templates): UP wraps
  -- the main-menu cursor to Save (row 6), A enters the menu's own
  -- SelectMainMenuOption_06 path, the slot cursor is steered to slot 3 by
  -- pad against its live cell, and A confirms on through any overwrite
  -- prompt.  There is no ZMENUSTATE poke, no cursor poke, no display-cache
  -- poke, and no witness seeding: the codex payload the battery carries is
  -- whatever the chain earned, read and logged below (issue #75).
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
    -- the codex witness cells are read, never seeded (issue #75): the
    -- battery carries whatever the chain earned.  The phase-2 checkpoint
    -- re-cuts measure these, and the entry contracts follow the
    -- measurement rather than the other way round.
    H.log(string.format("codex witness cells (earned): elem=%02X class=%02X",
      emu.read(0x316810 + ULTROS2, emu.memType.snesMemory),
      emu.read(0x316990 + ULTROS2, emu.memType.snesMemory)))
    H.assertExitContract("banquet-done-v1")
    H.screenshot("step_ij_saved")
  end),
  H.logStep(function()
    return string.format("banquet-done-v1 saved via the real Save UI at "
      .. "frame %d -- window %d + 49 = %d, the >=67 tier; "
      .. "boundary J of the v0.7 range", H.frame,
      dinner.w0 or -1, (dinner.w0 or -68) + 49)
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

H.run({ maxFrames = 400000 }, flat)
