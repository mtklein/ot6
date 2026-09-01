-- gen_banquet_done.lua -- generates battery checkpoint J, `banquet-done-v1`,
-- from the tracked `vector-crash-v1` battery: drives the >=67 banquet tier
-- through the Vector castle window, dinner Q&A, and troopers' challenge,
-- then saves via the real Save UI at world (120,188).

-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
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

-- held walk: dialogs are absorbed with A, a battle is fled with L+R.
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

-- ---- the talk-only greedy window --------------------------------------
-- The 24 banquet soldiers; the four marked `fight` are skipped.
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

local TALK_BELOW, FIGHT_BELOW = 23, 18

local function soldierDone(s) return sw(s.latch) == 1 end
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

local function circuitRunner()
  local cur, curWhat, curLatch = nil, nil, nil
  local stuckAt, cappedAt = nil, nil
  local inFight, ph = false, 0
  local chestTries = 0
  local F = H.newFightDriver("banquet window", { tactical = true,
    boost = true, bank = 1, items = true, healPercent = 60, cadence = 12 })
  return {
    tick = function(self)
      -- a fight soldier's talk opens battle 26/27 mid-chase: the library
      -- fighter handles it while the timer keeps ticking; the +1 and the
      -- clean +5 land in the script tail after the battle.
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
        ph = (ph + 1) % 8
        H.setPad(H.dialogWaiting() and (ph < 4 and { "a" } or {}) or {})
        return "frame"
      end
      if map() == 252 and not H.chestOpen(81) and chestTries < 5 then
        local stand =
          (H.bfsPath(41, 55) and { { 41, 55 }, "right" })
          or (H.bfsPath(42, 54) and { { 42, 54 }, "down" })
          or (H.bfsPath(42, 56) and { { 42, 56 }, "up" })
        if stand then
          chestTries = chestTries + 1
          curWhat, curLatch = "252 Tincture chest", nil
          routeLog[#routeLog + 1] = string.format(
            "f%-6d t=%-5d chest  252 Tincture (try %d)",
            H.frame, timerCount(), chestTries)
          cur = H.openChest{ stand = stand[1], face = stand[2], bit = 81,
                             what = "Tincture", item = 0xEB,
                             nav = { playBattles = "tactical", maxFrames = 2500,
                                     noPathRetries = 3 } }
          return "frame"
        end
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
          playBattles = "tactical",
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

-- ---- the Q&A choice machinery -----------------------------------------
-- Battles cannot start inside the dinner dialogs, so this driver carries
-- no battle branch.
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

  -- The kit lists were authored against the fled lineage's exact bag; the
  -- fighting lineage carries different spares, and LOCKE arrives already
  -- dual-wielding under the Genji Glove (owner doctrine: his left hand
  -- holds a SECOND WEAPON, not a shield -- the { 1, $5A } Buckler this kit
  -- used to force is the anti-pattern the wave-4 kits removed).  Each slot
  -- equips best-effort: in the bag -> worn, absent -> the character keeps
  -- what they have, with a log.  Repeated entries for one slot are a
  -- preference ladder, weakest first.  Same pattern as
  -- gen_ifrit_magicite's kit; inlined rather than shared because a lib
  -- edit re-stales every generated state in the chain.
  (function()
    local KITS = {
      -- TERRA has no Genji Glove, so her L-hand takes a shield if the bag
      -- holds one (her row arrives with slot 1 empty on this lineage).
      { 0, "TERRA", { { 0, 0x0E }, { 1, 0x5A }, { 1, 0x5C },
                      { 2, 0x6A }, { 3, 0x84 } } },
      { 1, "LOCKE", { { 0, 0x0F }, { 1, 0x00 }, { 1, 0x01 }, { 1, 0x02 },
                      { 2, 0x69 }, { 3, 0x84 } } },
    }
    local steps = {}
    for _, kit in ipairs(KITS) do
      local char, name, pairs_ = kit[1], kit[2], kit[3]
      for _, p in ipairs(pairs_) do
        local slot, item = p[1], p[2]
        local tag = string.format("%s banquet kit slot %d", name, slot)
        steps[#steps + 1] = H.cond(
          function() return H.invSlotOf(item) ~= nil end,
          { H.equipLoadout(char, { { slot, item } }, { tag = tag }) },
          { H.logStep(string.format(
              "%s: $%02X not in this lineage's bag; keeping current gear",
              tag, item)) })
      end
    end
    return H.cond(function() return true end, steps)
  end)(),
  H.fieldCare({ tag = "care before the banquet", threshold = 0.95 }),

  -- ---- 2. the castle and the dais ------------------------------------------
  H.navTo(28, 2, { maxFrames = 30000, playBattles = "tactical" }),
  pressWalk("up", function() return map() == 243 end, 900,
    "castle door 253 (28,1) -> 243 (15,29)"),
  H.waitUntil(landed(243, 10), 2400, "castle antechamber 243", 1),
  H.navTo(8, 18, { maxFrames = 12000, calmFrames = 4, playBattles = "tactical" }),
  H.stepOff({ "right", "down", "up" }, 6000,
    "escort: A through $06A6, step off (8,18)"),
  H.waitUntil(function() return sw(0x013A) == 1 end, 3000,
    "the escort ran ($013A)", 5),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(sw(0x062F), 1, "$062F -- the soldier population is up")
  end),
  H.navTo(15, 9, { maxFrames = 12000, playBattles = "tactical" }),
  pressWalk("up", function() return map() == 250 end, 900,
    "door 243 (15,8) -> 250 (23,33)"),
  H.waitUntil(landed(250, 10), 2400, "250 first entry", 1),
  H.call(function()
    H.assertEq(sw(0x013B), 1, "$013B -- 250 map-init opened the {22,29} door")
  end),
  H.navTo(23, 30, { maxFrames = 6000, playBattles = "tactical" }),
  pressWalk("up", function()
    return H.fieldY() <= 28 and H.tileAligned()
  end, 900, "held UP through the {22,29} doorway"),
  H.release(),
  H.waitFrames(30),
  H.navTo(23, 13, { maxFrames = 9000, playBattles = "tactical" }),
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
  H.navTo(54, 16, { maxFrames = 20000, playBattles = "tactical" }),
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
  H.navTo(53, 34, { maxFrames = 9000, playBattles = "tactical" }),
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
  -- Dev scratch state: the dinner table with the toast choice up and a
  -- known var0. Not a fixture.
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
  -- The three questions, each +2, driven as one group ending when var0
  -- has risen +6.
  picks({ 0, 0, 1, 0, 2 }, atPlus(26), 9000, "the three questions (+6 group)"),
  ckPlus("questions", 26),
  picks({ 1, 0 }, atPlus(31), 9000, "Espers: gone too far (+5)"),
  ckPlus("espers", 31),
  H.call(function() dinner.preChallenge = var0() end),
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
      bank = 1, items = true, healPercent = 60, cadence = 12,
      tool = H.BIO_BLASTER })
    local hb = 0
    return H.driveUntil(function() return not H.battleLoadStarted() end,
      20000, {
      H.call(function()
        hb = hb + 1
        -- $57C0 and $1dd1 go stale after teardown, so the formation and
        -- clean flag are sampled every frame during the battle; the last
        -- reading while active is the outcome.
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
  H.navTo(80, 20, { maxFrames = 9000, calmFrames = 4, playBattles = "tactical" }),
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

  H.navTo(80, 26, { maxFrames = 9000, playBattles = "tactical" }),
  pressWalk("down", function() return map() == 250 end, 900,
    "251 door row -> 250 (53,11)"),
  H.waitFrames(30),
  H.stepOff({ "down", "left", "right" }, 2400,
    "off the (53,11) trigger tile"),
  H.navTo(53, 34, { maxFrames = 9000, playBattles = "tactical" }),
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
  H.navTo(23, 12, { maxFrames = 20000, calmFrames = 4, playBattles = "tactical" }),
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

  H.navTo(15, 22, { maxFrames = 9000, playBattles = "tactical" }),
  pressWalk("up", function()
    return H.fieldY() >= 45 and H.tileAligned()
  end, 900, "held UP onto (15,21) -> the chest alcove (24,52)"),
  H.release(),
  H.waitUntil(landed(250, 10), 2400, "the chest alcove", 1),
  H.openChest{ stand = { 24, 49 }, face = "up", bit = 77,
               what = "Back Guard",
               nav = { playBattles = "tactical" } },
  H.openChest{ stand = { 25, 49 }, face = "up", bit = 78,
               what = "X-Potion",
               nav = { playBattles = "tactical" } },
  H.navTo(24, 52, { maxFrames = 3000, playBattles = "tactical" }),
  pressWalk("down", function()
    return H.fieldY() <= 30 and H.tileAligned()
  end, 900, "held DOWN onto (24,53) -> back to the corridor (15,23)"),
  H.release(),
  H.waitUntil(landed(250, 10), 2400, "back in the corridor", 1),

  H.navTo(23, 33, { maxFrames = 20000, playBattles = "tactical" }),
  pressWalk("down", function() return map() == 243 end, 1200,
    "door 250 (22..24,34) -> 243 (15,10)"),
  H.waitUntil(landed(243, 10), 2400, "243 on the way out", 1),
  H.navTo(15, 30, { maxFrames = 12000, playBattles = "tactical" }),
  pressWalk("down", function() return map() == 253 end, 1200,
    "south rows -> 253 (29,2)"),
  H.waitUntil(landed(253, 10), 2400, "Vector 253 on the way out", 1),
  H.navTo(30, 62, { maxFrames = 30000, playBattles = "tactical",
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
  H.saveState("banquet_done.mss"),
  -- A calm capture does not imply a calm reload; reload the parked moment
  -- and require it to be quiet before the Save-UI proceeds.
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
