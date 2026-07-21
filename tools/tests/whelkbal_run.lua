-- whelkbal_run.lua -- boss break-loop measurement on the Whelk fight
-- (M6 groundwork; the boss-row companion to bal_mines.lua).
--
--   sed -i '' 's/^local POLICY .*/local POLICY = "<p>"/' tools/tests/whelkbal_run.lua
--   tools/tests/run.sh tools/tests/whelkbal_run.lua build/states/whelkbal_<p>.log
--
-- Protocol (bal_mines discipline, adapted to a scripted boss):
--  * every battle starts from an identical loadState(whelk_doorstep);
--    battles are fully independent (HP/RNG reset; loadState re-virgins
--    the codex). The formation is scripted ($0100 shell + $0134 head),
--    so there are no encounter seeds: battle k decorrelates by SETTLE
--    JITTER alone (k*11 field frames before the trigger step, and
--    240 + 7(k-1) in-battle settle frames before the driver arms).
--  * the fight is played to the end by POLICY (below), all-legit: no
--    HP pins, no kill-bits. A wipe is a sample, not a failure.
--  * battle menus eat input during their open animation EVERY turn:
--    presses are gated on the menu flag holding 4 consecutive 30-frame
--    pulses (bal_mines' hard-won settle rule). When no menu is up, A is
--    edge-tapped every other pulse (the opener battle dialog and the
--    shell's mid-fight "Gruuu……" dialogs need it; on a running battle
--    a stray A is inert).
--  * the whelk's shell hides/shows the head on a monster-timer cycle
--    (vanilla AI). While the head is hidden the default target is the
--    shell, and any shell hit draws a MegaVolt counter. Deliberate
--    policies (beams/pierce) spend hidden-phase turns on Heal Force;
--    naive keeps mashing A into the shell, exactly like the player it
--    models.
--
-- Per battle the log carries greppable lines:
--   [ot6] [metrics] b=<k> <key>=<value>
--
-- Policies (POLICY knob):
--   beams   fire beam at the default target every turn (never tek);
--           Heal Force while the head hides. "ignores the pierce
--           weakness" control. (With the head's fire-weak ADD, beams
--           now chip too -- this is no longer a zero-chip control.)
--   pierce  terra: TekMissile at the head until it breaks, beams into
--           the break window, TekMissile again as shields re-arm;
--           vicks/wedge: fire beams. Heal Force while the head hides.
--   tutorial the designed line the fire-weak ADD exists for: everyone
--           beams the head (3 fire chips), and terra spends her action
--           on TekMissile exactly when one shield remains -- the 4th
--           chip. beams into the break window; Heal Force while the
--           head hides.
--   naive   everyone confirms their first beam at the default target
--           (A-A-A), always. The mash-through player.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

-- ------------------------------------------------------------- knobs --
local POLICY = "beams"
local STATE = "/Users/mtklein/ot6/build/states/whelk_doorstep.mss.lua"
local NBATTLES = 5
local BATTLE_FRAMES = 20000        -- policy-driven battle budget
local WHELK = { [0x0134] = true }

-- --------------------------------------------------------- addresses --
local MENU  = 0x7bca               -- battle menu open flag
local ACTOR = 0x62ca               -- whose menu it is (char slot)
local PHP   = 0x3bf4               -- party cur hp, +slot*2
local PMP   = 0x3c08               -- party cur mp, +slot*2
local MHP   = 0x3bfc               -- monster cur hp, +slot*2
local BP    = 0x3e9c               -- char bp, +slot*2
local PEND  = 0x3e9d               -- char pending boost, +slot*2
local SHLD  = 0x3e40               -- monster cur shields, +slot*2 (odd = max)
local TIMER = 0x3e90               -- monster broken timer, +slot*2
local CWEAK = 0x3ea4               -- monster class weaknesses, +slot*2
local WEAK  = 0x3be8               -- monster weak elements, +slot*2
local ALIVE = 0x3aa8               -- monster presence bit0, +slot*2
local MSTAT = 0x3eec               -- monster status-1, +slot*2 ($c2 = gone)
local SPEC  = 0x57c0               -- formation species words
local CHID  = 0x3ed8               -- char id, +slot*2 (0 = terra)
local QUEUES = {                   -- dequeue-side action counting
  { base = 0x3720, ptr = 0x3a64, counter = false },
  { base = 0x3820, ptr = 0x3a66, counter = false },
  { base = 0x3920, ptr = 0x3a68, counter = true },
}

local hs, ss, terra                -- head slot, shell slot, terra char slot
local function bp(slot) return H.readByte(BP + slot*2) end
local function broken() return H.readByte(TIMER + hs*2) > 0 end
local function shields() return H.readByte(SHLD + hs*2) end
local function headAlive()
  return (H.readByte(ALIVE + hs*2) & 1) == 1
     and (H.readByte(MSTAT + hs*2) & 0xc2) == 0
end
local function monsterAlive(slot)
  return (H.readByte(ALIVE + slot*2) & 0x01) == 1
     and (H.readByte(MSTAT + slot*2) & 0xc2) == 0
end
local function calm(n)
  local cnt = 0
  return function()
    cnt = (H.hasControl() and H.tileAligned()) and cnt + 1 or 0
    return cnt >= n
  end
end
local function whelkUp()
  return H.battleLoadStarted() and H.formationHas(WHELK)
end

-- ---------------------------------------------------------- policies --
-- Sequences run from the settled top command menu (cursor on MagiTek):
--   beam at default target        A A A
--   heal force (2,0), BOTH lists  A dn dn A A   (self-target by default;
--     the soldiers' 4-cell list stages sparse -- Fire|Bolt / Ice / Heal --
--     so Heal Force is (2,0) for everyone; (1,1) is a BLANK cell the
--     cursor can walk onto and wedge, measured the hard way)
--   tekmissile  terra (3,1)       A dn dn dn rt A A
local function seqFor(actor)
  local hidden = not headAlive()
  if POLICY == "naive" then
    return { "a", "a", "a" }
  end
  if hidden then
    return { "a", "down", "down", "a", "a" }
  end
  if POLICY == "pierce" and actor == terra
     and not broken() and shields() > 0 then
    return { "a", "down", "down", "down", "right", "a", "a" }
  end
  if POLICY == "tutorial" and actor == terra
     and not broken() and shields() == 1 then
    return { "a", "down", "down", "down", "right", "a", "a" }
  end
  return { "a", "a", "a" }
end

-- the menu-episode machine (bal_mines settle discipline)
local mStreak, mSeq, mIdx, mStall, mNoMenu = 0, nil, 1, 0, 0
local function policyPulse()
  if H.readByte(MENU) == 0 then
    mStreak, mSeq, mIdx, mStall = 0, nil, 1, 0
    mNoMenu = mNoMenu + 1
    return mNoMenu % 2 == 0 and { "a" } or {}
  end
  mNoMenu = 0
  mStreak = mStreak + 1
  if mStreak < 4 then return {} end
  if mSeq == nil then
    mSeq, mIdx = seqFor(H.readByte(ACTOR)), 1
  end
  if mIdx <= #mSeq then
    local b = mSeq[mIdx]
    mIdx = mIdx + 1
    return { b }
  end
  mStall = mStall + 1
  if mStall > 2 then
    mSeq, mStall = nil, 0              -- back out; rebuild from scratch
    return { "b" }
  end
  return { "a" }
end

-- ------------------------------------------------------ accumulators --
local S, mons, chars, qShadow
local refs, shSeen, tmSeen = {}, {}, {}
local execN = {}
local bpTrace, actTrace, lastBp
local voidReason

local function resetBattleState()
  S = {
    t0 = 0, frames = 0,
    playerActions = 0, enemyActions = 0, counterActions = 0,
    playerDequeues = 0, enemyDequeues = 0,
    headDequeues = 0, shellDequeues = 0,
    headActions = 0, shellActions = 0,
    playerDmg = 0, playerDmgBroken = 0, monsterHeal = 0,
    enemyDmg = 0, partyHeal = 0,
    regens = 0, boosts = { 0, 0, 0 },
    chips = 0, breaks = 0, firstBreak = -1,
    windows = {},                   -- { {start, stop or -1}, ... }
    brokenUptime = 0,
    menuFrames = 0, hiddenFrames = 0, retracts = 0,
    deaths = 0,
    result = "budget",
  }
  mons, chars, qShadow = {}, {}, {}
  execN = {}
  bpTrace, actTrace = {}, {}
  lastBp = nil
  voidReason = nil
  hs, ss, terra = nil, nil, nil
  mStreak, mSeq, mIdx, mStall, mNoMenu = 0, nil, 1, 0, 0
end

local function arm()
  S.t0 = H.frame
  for i = 0, 5 do
    shSeen[i] = H.readByte(SHLD + i*2)
    tmSeen[i] = H.readByte(TIMER + i*2)
  end
  refs[1] = emu.addMemoryCallback(function(addr, value)
    local off = addr - (0x7e0000 + SHLD)
    if off % 2 ~= 0 then return end
    local slot = off // 2
    local prev = shSeen[slot]
    shSeen[slot] = value
    if value < prev then S.chips = S.chips + (prev - value) end
  end, emu.callbackType.write, 0x7e0000 + SHLD, 0x7e0000 + SHLD + 11)
  refs[2] = emu.addMemoryCallback(function(addr, value)
    local off = addr - (0x7e0000 + TIMER)
    if off % 2 ~= 0 then return end
    local slot = off // 2
    local prev = tmSeen[slot]
    tmSeen[slot] = value
    if prev == 0 and value > 0 then
      S.breaks = S.breaks + 1
      local at = H.frame - S.t0
      S.windows[#S.windows + 1] = { at, -1 }
      if S.firstBreak < 0 then S.firstBreak = at end
    elseif prev > 0 and value == 0 then
      local w = S.windows[#S.windows]
      if w and w[2] < 0 then w[2] = H.frame - S.t0 end
    end
  end, emu.callbackType.write, 0x7e0000 + TIMER, 0x7e0000 + TIMER + 11)
  refs[3] = emu.addMemoryCallback(function(addr, value)
    if value ~= 0 and value ~= 0xff then
      execN[value] = (execN[value] or 0) + 1
    end
  end, emu.callbackType.write, 0x7e3410, 0x7e3410)
end
local function disarm()
  emu.removeMemoryCallback(refs[1], emu.callbackType.write,
    0x7e0000 + SHLD, 0x7e0000 + SHLD + 11)
  emu.removeMemoryCallback(refs[2], emu.callbackType.write,
    0x7e0000 + TIMER, 0x7e0000 + TIMER + 11)
  emu.removeMemoryCallback(refs[3], emu.callbackType.write,
    0x7e3410, 0x7e3410)
end

-- ------------------------------------------------- per-frame sampler --
local headWasAlive, wonStreak
local function sample()
  S.frames = H.frame - S.t0
  for qi, q in ipairs(QUEUES) do
    local cur = H.readByte(q.ptr)
    while qShadow[qi] ~= cur do
      local v = H.readByte(q.base + qShadow[qi])
      if (v & 0x80) == 0 then
        -- each real action passes through TWO queues (advance-wait +
        -- action; measured in this fight: raw player dequeues == 2x the
        -- exec-verified cast counters). player/enemy/head/shell action
        -- lines emit REAL actions: every second dequeue of a bucket
        -- credits one. counter_actions stays a raw counter-queue
        -- dequeue tally (subset diagnostics).
        if q.counter then S.counterActions = S.counterActions + 1 end
        if v < 8 then
          S.playerDequeues = S.playerDequeues + 1
          if S.playerDequeues % 2 == 0 then
            S.playerActions = S.playerActions + 1
            actTrace[#actTrace + 1] = string.format("%d:%d",
              S.playerActions, S.playerDmg)
          end
        else
          S.enemyDequeues = S.enemyDequeues + 1
          if S.enemyDequeues % 2 == 0 then
            S.enemyActions = S.enemyActions + 1
          end
          if hs and v == 8 + hs*2 then
            S.headDequeues = S.headDequeues + 1
            if S.headDequeues % 2 == 0 then S.headActions = S.headActions + 1 end
          end
          if ss and v == 8 + ss*2 then
            S.shellDequeues = S.shellDequeues + 1
            if S.shellDequeues % 2 == 0 then S.shellActions = S.shellActions + 1 end
          end
        end
      end
      qShadow[qi] = (qShadow[qi] + 1) & 0xff
    end
  end
  local anyBroken = false
  for _, m in ipairs(mons) do
    if H.readByte(TIMER + m.slot*2) > 0 then anyBroken = true end
    local hp = H.readWord(MHP + m.slot*2)
    if hp < m.hp then
      local d = m.hp - hp
      S.playerDmg = S.playerDmg + d
      m.dmg = m.dmg + d
      if H.readByte(TIMER + m.slot*2) > 0 then
        S.playerDmgBroken = S.playerDmgBroken + d
      end
    elseif hp > m.hp then
      S.monsterHeal = S.monsterHeal + (hp - m.hp)
    end
    m.hp = hp
  end
  if anyBroken then S.brokenUptime = S.brokenUptime + 1 end
  for _, c in ipairs(chars) do
    local hp = H.readWord(PHP + c.slot*2)
    if hp < c.hp then
      S.enemyDmg = S.enemyDmg + (c.hp - hp)
      if hp == 0 then S.deaths = S.deaths + 1 end
    elseif hp > c.hp then S.partyHeal = S.partyHeal + (hp - c.hp) end
    c.hp = hp
    local b = bp(c.slot)
    if b > c.bp then
      S.regens = S.regens + (b - c.bp)
    elseif b < c.bp then
      local lvl = c.bp - b
      if lvl >= 1 and lvl <= 3 then S.boosts[lvl] = S.boosts[lvl] + 1 end
    end
    c.bp = b
  end
  if H.readByte(MENU) ~= 0 then S.menuFrames = S.menuFrames + 1 end
  local ha = headAlive()
  if not ha then S.hiddenFrames = S.hiddenFrames + 1 end
  if headWasAlive and not ha then S.retracts = S.retracts + 1 end
  headWasAlive = ha
  local b0 = bp(0)
  if b0 ~= lastBp then
    lastBp = b0
    if #bpTrace < 60 then
      bpTrace[#bpTrace + 1] = string.format("f%d:%d", S.frames, b0)
    end
  end
  local aliveC = 0
  for _, c in ipairs(chars) do if c.hp > 0 then aliveC = aliveC + 1 end end
  if aliveC == 0 then S.result = "wiped" return true end
  if not H.battleLoadStarted() then
    -- terra KO'd ends this scripted fight in a game over even with the
    -- soldiers standing (measured: the teardown follows c0 -> 0 directly)
    local tdead = false
    for _, c in ipairs(chars) do
      if c.slot == terra and c.hp == 0 then tdead = true end
    end
    S.result = tdead and "gameover_terra" or "torn_down"
    return true
  end
  -- "won" needs a 3-frame debounce: the head flickers through dead-ish
  -- states when the shell's script hides it
  local aliveM = 0
  for _, m in ipairs(mons) do
    if monsterAlive(m.slot) then aliveM = aliveM + 1 end
  end
  if aliveM == 0 then
    wonStreak = wonStreak + 1
    if wonStreak >= 3 then S.result = "won" return true end
  else
    wonStreak = 0
  end
  if S.frames >= BATTLE_FRAMES then S.result = "budget" return true end
  return false
end

-- ------------------------------------------------------------ report --
local B = 0
local function mline(k, v)
  H.log(string.format("[metrics] b=%d %s=%s", B, k, tostring(v)))
end
local function slotCsv(list, field)
  local parts = {}
  for _, e in ipairs(list) do
    parts[#parts + 1] = string.format("s%d:%d", e.slot, e[field])
  end
  return table.concat(parts, ",")
end
local function report()
  mline("policy", POLICY)
  if voidReason then
    mline("void", voidReason)
    return
  end
  local sp = {}
  for _, m in ipairs(mons) do
    sp[#sp + 1] = string.format("%04X", H.readWord(SPEC + m.slot*2))
  end
  mline("formation", table.concat(sp, ","))
  mline("result", S.result)
  mline("frames", S.frames)
  mline("player_actions", S.playerActions)
  mline("enemy_actions", S.enemyActions)
  mline("counter_actions", S.counterActions)
  mline("head_actions", S.headActions)
  mline("shell_actions", S.shellActions)
  mline("player_dmg", S.playerDmg)
  mline("player_dmg_broken", S.playerDmgBroken)
  mline("enemy_dmg", S.enemyDmg)
  mline("party_heal", S.partyHeal)
  mline("monster_heal", S.monsterHeal)
  mline("boosts_spent", string.format("l1:%d,l2:%d,l3:%d",
    S.boosts[1], S.boosts[2], S.boosts[3]))
  mline("bp_regen", S.regens)
  mline("shield_chips", S.chips)
  mline("breaks", S.breaks)
  mline("first_break_frame", S.firstBreak)
  mline("break_uptime_frames", S.brokenUptime)
  local ws = {}
  for _, w in ipairs(S.windows) do
    ws[#ws + 1] = string.format("%d:%s", w[1], w[2] >= 0 and (w[2] - w[1]) or "open")
  end
  mline("break_windows", table.concat(ws, ","))
  mline("menu_frames", S.menuFrames)
  mline("head_hidden_frames", S.hiddenFrames)
  mline("retracts", S.retracts)
  mline("deaths", S.deaths)
  local ex = {}
  for id, n in pairs(execN) do ex[#ex + 1] = string.format("%02x:%d", id, n) end
  table.sort(ex)
  mline("exec_writes", table.concat(ex, ","))  -- NB: 2 writes per cast
  mline("casts_beam", ((execN[0x83] or 0) + (execN[0x84] or 0) + (execN[0x85] or 0)) // 2)
  mline("casts_tek", (execN[0x8a] or 0) // 2)
  mline("casts_heal", (execN[0x87] or 0) // 2)
  mline("casts_megavolt", (execN[0xb8] or 0) // 2)
  mline("monster_hp_start", slotCsv(mons, "hp0"))
  mline("monster_dmg", slotCsv(mons, "dmg"))
  for _, m in ipairs(mons) do m.hp = H.readWord(MHP + m.slot*2) end
  mline("monster_hp_remaining", slotCsv(mons, "hp"))
  local sh = {}
  for _, m in ipairs(mons) do
    sh[#sh + 1] = string.format("s%d:%d/%d", m.slot,
      H.readByte(SHLD + m.slot*2), H.readByte(SHLD + m.slot*2 + 1))
  end
  mline("monster_shields_end", table.concat(sh, ","))
  local ph = {}
  for _, c in ipairs(chars) do
    ph[#ph + 1] = string.format("c%d:%d", c.slot, H.readWord(PHP + c.slot*2))
  end
  mline("party_hp_end", table.concat(ph, ","))
  mline("terra_mp_end", H.readWord(PMP + (terra or 0)*2))
  mline("bp_curve", table.concat(bpTrace, ","))
  mline("action_trace", table.concat(actTrace, ","))
end

-- ----------------------------------------------------- battle blocks --
-- seqStepList: plain sequential composition (H.seqStep is public, but the lib reserves it for ot6_field's route())
local function seqStepList(steps)
  return {
    i = 1,
    tick = function(self)
      while self.i <= #steps do
        local r = steps[self.i]:tick()
        if r == "frame" then return "frame" end
        self.i = self.i + 1
      end
      return "done"
    end,
  }
end

local function stepToWhelk(k)
  local aPhase, waited, strayN = 0, 0, 0
  return H.driveUntil(function()
    waited = waited + 1
    if whelkUp() then return true end
    if waited >= 2600 then
      voidReason = "no_whelk_battle"
      H.setPad({})
      return true
    end
    return false
  end, 3300, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.battleLoadStarted() then
        if whelkUp() then H.setPad({}); return end
        -- battleLoadStarted flips true BEFORE the formation words land, so
        -- the whelk's own load window looks like a stray fight for a few
        -- dozen frames: hands off until the non-whelk state HOLDS. A real
        -- random encounter (shouldn't happen on this one-step route) gets
        -- kill-bitted to unstick, and the sample is voided.
        strayN = strayN + 1
        if strayN >= 120 and H.monstersPresent() > 0 then
          voidReason = "stray_encounter"
          for slot = 0, 5 do
            if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
          H.setPad(aPhase < 4 and { "a" } or {})
          return
        end
        H.setPad({})
        return
      end
      strayN = 0
      if H.dialogWaiting() then
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
    end),
  }, "whelk event (b=" .. k .. ")")
end

local function battleBlock(k)
  return seqStepList({
    H.call(function()
      B = k
      resetBattleState()
    end),
    H.loadState(STATE),
    H.waitFrames(10),
    H.waitUntil(calm(20), 1200, "field control (b=" .. k .. ")"),
    H.waitFrames(11 * (k - 1)),        -- field-side rng phase jitter
    stepToWhelk(k),
    H.cond(function() return voidReason ~= nil end, {
      H.call(function() report() end),
    }, {
      H.waitUntilSoft(function() return H.battleActive() end, 900,
        "battle_active_b" .. k, 30),
      H.waitFrames(240 + 7 * (k - 1)), -- in-battle settle + rng jitter
      H.call(function()
        for slot = 0, 5 do
          local sp = H.readWord(SPEC + slot*2)
          if sp == 0x0134 then hs = slot end
          if sp == 0x0100 then ss = slot end
        end
        if hs == nil or ss == nil then voidReason = "slots_missing" end
        if hs and H.readByte(SHLD + hs*2) ~= 4 then voidReason = "bad_seed" end
        if hs and H.readByte(CWEAK + hs*2) ~= 2 then voidReason = "bad_class" end
        if hs and (H.readByte(WEAK + hs*2) & 0x01) == 0 then
          voidReason = "no_fire_add"   -- the Ot6ElemAddTbl row must land
        end
        if voidReason then report() return end
        for slot = 0, 3 do
          if H.readByte(CHID + slot*2) == 0 then terra = slot end
          local hp = H.readWord(PHP + slot*2)
          if hp > 0 and hp ~= 0xffff then
            chars[#chars + 1] = { slot = slot, hp = hp, bp = bp(slot) }
          end
        end
        if terra == nil then voidReason = "no_terra" report() return end
        for slot = 0, 5 do
          if monsterAlive(slot) then
            local hp = H.readWord(MHP + slot*2)
            mons[#mons + 1] = { slot = slot, hp = hp, hp0 = hp, dmg = 0 }
            mline("mon_detail", string.format(
              "s%d:sp%04X:hp%d:cweak%02x:weak%02x:sh%d/%d", slot,
              H.readWord(SPEC + slot*2), hp,
              H.readByte(CWEAK + slot*2), H.readByte(WEAK + slot*2),
              H.readByte(SHLD + slot*2), H.readByte(SHLD + slot*2 + 1)))
          end
        end
        for qi, q in ipairs(QUEUES) do qShadow[qi] = H.readByte(q.ptr) end
        headWasAlive, wonStreak = true, 0
        arm()
        H.log(string.format(
          "[metrics-ev] b=%d armed frame=%d chars=%d mons=%d terra=%d policy=%s",
          k, H.frame, #chars, #mons, terra, POLICY))
      end),
      H.cond(function() return voidReason ~= nil end, {}, {
        H.driveUntil(function() return sample() end, BATTLE_FRAMES + 600, {
          H.call(function()
            H.setPad(policyPulse())
          end),
          H.waitFrames(6),
          H.call(function() H.setPad({}) end),
          H.waitFrames(24),
        }, "battle resolved (b=" .. k .. ")"),
        H.call(function()
          disarm()
          report()
        end),
      }),
    }),
  })
end

local blocks = {}
for k = 1, NBATTLES do blocks[#blocks + 1] = battleBlock(k) end
blocks[#blocks + 1] = H.call(function()
  H.log(string.format("[metrics] run_done policy=%s battles=%d", POLICY, NBATTLES))
end)

H.run({ maxFrames = 140000 }, blocks)
