-- bal_mines.lua -- the first real balance measurement (M6 groundwork).
-- Multi-battle auto-battler over the LIVE random-encounter pool of the
-- mines chase map (map 50), from the mines_chase.mss fixture: OCTO
-- (Terra) L5, alone, normal Fight/Magic/Item commands, Mithril Knife
-- (pierce), spells Fire + Cure, MP 34.
--
-- Protocol (docs in the report; deliberately boring):
--  * every battle starts from an identical loadState(mines_chase) --
--    battles are fully independent (HP/MP/XP/RNG all reset).
--  * the encounter draw is seeded, not paced-for: FF6 draws the battle
--    step from RNG stream $1fa1 and the formation from stream $1fa2
--    (tools note: NOTHING else consumes these streams on this map, so
--    pacing patterns alone cannot vary the draw from a fixed state).
--    Battle k writes documented seed values before pacing; the seed
--    list below covers every formation slot of the map's encounter
--    group, including the 1/16 slot. Reproducible by construction.
--  * pacing is a dumb left/right two-tile walk at the map entry
--    (78,58)<->(77,58); a guard-catch event or an off-pool formation
--    VOIDS the sample (logged; the next loadState wipes it away).
--  * the battle is then played to the end by POLICY (below), metrics
--    sampled every frame (adapted from metrics_battle.lua).
--  * in-battle rng phase jitter: battle k arms after 240 + 7(k-1)
--    settle frames, so same-formation battles decorrelate.
--
-- Per battle the log carries greppable lines:
--   [ot6] [metrics] b=<k> <key>=<value>
--
-- Policies (POLICY knob):
--   baseline  unboosted Fight only (confirm everything with A)
--   boost3    bank BP to 3, then one 3-BP boosted Fight, repeat
--   greedy    commit every BP available on a boosted Fight, every turn
--   fire      unboosted Fire every turn (Fight if MP < 4)
--   probe1    hit a revealed weakness (Fire) if any alive monster shows
--             one; else rotate Fire/Fight probes (Fight if MP < 4)
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

-- ------------------------------------------------------------- knobs --
local POLICY = "baseline"
local STATE = "/Users/mtklein/ot6/build/states/mines_chase.mss.lua"
local NBATTLES = 8
-- co-tune poke (Measurement #5): if set, write these into the ROM before each
-- battle so the HP-multiplier x resistance grid sweeps without a rebuild.
-- POKE_HP -> Ot6HpMulTbl band0 ($10=1x, $18=1.5x, $20=2x); POKE_SHIELD ->
-- Ot6ShieldedMulW ($08=0.5x, $0c=0.75x, $10=1x/off). nil = shipped bytes.
-- Proven equivalent to a rebuild by mines_pace.lua (Measurement #4).
local POKE_HP = nil
local POKE_SHIELD = nil
local ROM_HPMUL  = 0x300173         -- Ot6HpMulTbl band0
local ROM_SHIELD = 0x30033C         -- Ot6ShieldedMulW (word, low byte)
-- $1fa2 seeds (formation draw): group slots for map 50 at $1fa3=0x61 --
-- slot0 = Vaporite x2, slot1 = Were-Rat x2, slot2/3 = RepoMan+Vaporite.
-- false = leave the state's natural values (draw = Were-Rat x2 after 9
-- paced steps, measured). Chosen mix ~ the pool's own 5/16,5/16,6/16.
local SEEDS = {
  { },                              -- b=1 natural: Were-Rat x2
  { fa2 = 0x00, fa1 = 0x90 },       -- b=2 slot0: Vaporite x2
  { fa2 = 0x06, fa1 = 0x95 },       -- b=3 slot0: Vaporite x2
  { fa2 = 0x01, fa1 = 0x9a },       -- b=4 slot1: Were-Rat x2
  { fa2 = 0x02, fa1 = 0x9f },       -- b=5 slot1: Were-Rat x2
  { fa2 = 0x03, fa1 = 0xa4 },       -- b=6 slot2: RepoMan+Vaporite
  { fa2 = 0x04, fa1 = 0xa9 },       -- b=7 slot2: RepoMan+Vaporite
  { fa2 = 0x0b, fa1 = 0xae },       -- b=8 slot3: RepoMan+Vaporite
}
local POOL = { [0x0013] = true, [0x0046] = true, [0x004d] = true }
local PACE_FRAMES = 4500            -- pacing budget per battle
local BATTLE_FRAMES = 9000          -- policy-driven battle budget

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
local RVEAL = 0x3e91               -- monster revealed elements, +slot*2
local WEAK  = 0x3be8               -- monster weak elements, +slot*2
local ALIVE = 0x3aa8               -- monster presence bit0, +slot*2
local MSTAT = 0x3eec               -- monster status-1, +slot*2 ($c2 = gone)
local QUEUES = {                   -- dequeue-side action counting
  { base = 0x3720, ptr = 0x3a64, counter = false },
  { base = 0x3820, ptr = 0x3a66, counter = false },
  { base = 0x3920, ptr = 0x3a68, counter = true },
}

local function bp(slot) return H.readByte(BP + slot*2) end
local function pend(slot) return H.readByte(PEND + slot*2) end
local function broken(slot) return H.readByte(TIMER + slot*2) > 0 end
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

-- ---------------------------------------------------------- policies --
local rTries, pendSeen = 0, -1
local function menuSlot()
  if H.readByte(MENU) == 0 then pendSeen = -1 return nil end
  return H.readByte(ACTOR)
end
local function commitThenConfirm(slot, want)
  local p = pend(slot)
  if p ~= pendSeen then rTries, pendSeen = 0, p end
  if p < want and p < bp(slot) and rTries < 6 then
    rTries = rTries + 1
    return { "r" }
  end
  return { "a" }
end

-- Fire cast: from the command menu, the magic list opens with the
-- cursor on Cure at grid (0,0); Fire sits at (1,1) (measured; the list
-- is a sparse fixed-slot grid and the cursor walks blank cells). The
-- sequence below commits base Fire on the default enemy target.
-- Two hard-won rules:
--  * input into a JUST-opened battle window is eaten (and can wedge the
--    menu) -- the same window-open animation metrics_battle's 240-frame
--    settle dodges at battle start recurs on EVERY turn's menu. So the
--    machine waits for the menu flag to hold 4 consecutive pulses
--    (~120 frames) before its first press of an episode.
--  * if the sequence runs dry with the menu still open (a press still
--    got eaten), nudge with A twice (a lost target-confirm), then back
--    out with B and restart the sequence from the top.
local fireSeq = { "down", "a", "down", "right", "a", "a" }
local fireIdx, fireStall, menuStreak = 1, 0, 0
local function fireCastPulse()
  if H.readByte(MENU) == 0 then
    fireIdx, fireStall, menuStreak = 1, 0, 0
    return nil
  end
  menuStreak = menuStreak + 1
  if menuStreak < 4 then return nil end
  if fireIdx <= #fireSeq then
    local b = fireSeq[fireIdx]
    fireIdx = fireIdx + 1
    return { b }
  end
  fireStall = fireStall + 1
  if fireStall > 2 then
    fireIdx, fireStall = 1, 0
    return { "b" }
  end
  return { "a" }
end
local function fireResetEpisode() fireIdx, fireStall, menuStreak = 1, 0, 0 end

local function anyRevealedFire()
  for slot = 0, 5 do
    if monsterAlive(slot) and (H.readByte(RVEAL + slot*2) & 0x01) ~= 0 then
      return true
    end
  end
  return false
end

local POLICIES = {}
function POLICIES.baseline()
  if menuSlot() == nil then return nil end
  return { "a" }
end
function POLICIES.boost3()
  local slot = menuSlot()
  if slot == nil then return nil end
  if bp(slot) >= 3 or pend(slot) > 0 then
    return commitThenConfirm(slot, 3)
  end
  return { "a" }
end
function POLICIES.greedy()
  local slot = menuSlot()
  if slot == nil then return nil end
  return commitThenConfirm(slot, 3)
end
function POLICIES.fire()
  local slot = menuSlot()
  if slot == nil then fireResetEpisode() return nil end
  if H.readWord(PMP + slot*2) < 4 then return { "a" } end
  return fireCastPulse()
end
-- the deliberate BAD-PLAYER (Measurement #5): bank to 3, then dump a 3-BP
-- boosted FIGHT at the default target. Fight is pierce, and every mines-pool
-- species is formula (no class weakness), so this boost ALWAYS lands in a
-- shielded-unweak target -- the canonical "boost feels wasted" misplay. For
-- this pool it coincides with boost3 (Fight matches nothing either way);
-- the point is the framing and the outcome-vs-baseline comparison.
function POLICIES.badboost()
  local slot = menuSlot()
  if slot == nil then return nil end
  if bp(slot) >= 3 or pend(slot) > 0 then
    return commitThenConfirm(slot, 3)
  end
  return { "a" }
end
local probeActions = 0             -- reset per battle
function POLICIES.probe1()
  local slot = menuSlot()
  if slot == nil then fireResetEpisode() return nil end
  if H.readWord(PMP + slot*2) < 4 then return { "a" } end
  if anyRevealedFire() then return fireCastPulse() end
  -- rotate probes: even action = Fire (informative axis), odd = Fight
  if probeActions % 2 == 0 then return fireCastPulse() end
  return { "a" }
end

-- ------------------------------------------------------ accumulators --
local S, mons, chars, qShadow
local refs, shSeen, tmSeen = {}, {}, {}
local bpTrace, actTrace, lastBp
local voidReason, paceSteps

local function resetBattleState()
  S = {
    t0 = 0, frames = 0,
    playerActions = 0, enemyActions = 0, counterActions = 0,
    playerDequeues = 0, enemyDequeues = 0,
    playerDmg = 0, playerDmgBroken = 0, monsterHeal = 0,
    enemyDmg = 0, partyHeal = 0,
    regens = 0, boosts = { 0, 0, 0 },
    chips = 0, breaks = 0, breakFrames = {}, firstBreak = -1,
    brokenUptime = 0,
    boostLog = {},                  -- per boosted action: state at cast
    result = "budget",
  }
  mons, chars, qShadow = {}, {}, {}
  bpTrace, actTrace = {}, {}
  lastBp = nil
  voidReason, paceSteps = nil, 0
  probeActions = 0
  rTries, pendSeen = 0, -1
  fireResetEpisode()
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
      S.breakFrames[#S.breakFrames + 1] = at
      if S.firstBreak < 0 then S.firstBreak = at end
    end
  end, emu.callbackType.write, 0x7e0000 + TIMER, 0x7e0000 + TIMER + 11)
end
local function disarm()
  emu.removeMemoryCallback(refs[1], emu.callbackType.write,
    0x7e0000 + SHLD, 0x7e0000 + SHLD + 11)
  emu.removeMemoryCallback(refs[2], emu.callbackType.write,
    0x7e0000 + TIMER, 0x7e0000 + TIMER + 11)
end

-- ------------------------------------------------- per-frame sampler --
local function sample()
  S.frames = H.frame - S.t0
  for qi, q in ipairs(QUEUES) do
    local cur = H.readByte(q.ptr)
    while qShadow[qi] ~= cur do
      local v = H.readByte(q.base + qShadow[qi])
      if (v & 0x80) == 0 then
        -- each real action passes through TWO queues (advance-wait +
        -- action), so raw dequeues run exactly 2x real actions (verified
        -- against BP-regen stamps and the whelk driver's exec-verified
        -- cast counters). player_actions/enemy_actions emit REAL actions:
        -- every second dequeue of a side credits one. counter_actions
        -- stays a raw counter-queue dequeue tally (subset diagnostics).
        if q.counter then S.counterActions = S.counterActions + 1 end
        if v < 8 then
          S.playerDequeues = S.playerDequeues + 1
          if S.playerDequeues % 2 == 0 then
            S.playerActions = S.playerActions + 1
            probeActions = probeActions + 1
            actTrace[#actTrace + 1] = string.format("%d:%d:%d",
              S.playerActions, S.playerDmg, bp(0))
          end
        else
          S.enemyDequeues = S.enemyDequeues + 1
          if S.enemyDequeues % 2 == 0 then
            S.enemyActions = S.enemyActions + 1
          end
        end
      end
      qShadow[qi] = (qShadow[qi] + 1) & 0xff
    end
  end
  local anyBroken = false
  for _, m in ipairs(mons) do
    if broken(m.slot) then anyBroken = true end
    local hp = H.readWord(MHP + m.slot*2)
    if hp < m.hp then
      local d = m.hp - hp
      S.playerDmg = S.playerDmg + d
      m.dmg = m.dmg + d
      if broken(m.slot) then
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
    if hp < c.hp then S.enemyDmg = S.enemyDmg + (c.hp - hp)
    elseif hp > c.hp then S.partyHeal = S.partyHeal + (hp - c.hp) end
    c.hp = hp
    local b = bp(c.slot)
    if b > c.bp then
      S.regens = S.regens + (b - c.bp)
    elseif b < c.bp then
      local lvl = c.bp - b
      if lvl >= 1 and lvl <= 3 then S.boosts[lvl] = S.boosts[lvl] + 1 end
      -- classify the default target's state at the moment BP was spent, so
      -- every boosted action is logged (Measurement #5). Fight matches no
      -- pool weakness, so a boosted Fight here is "shielded-unweak".
      local tgt
      for _, m in ipairs(mons) do
        if monsterAlive(m.slot) then tgt = m.slot break end
      end
      if tgt then
        local st = broken(tgt) and "broken"
          or (H.readByte(SHLD + tgt*2) > 0 and "shielded" or "shieldless")
        local wk = H.readByte(WEAK + tgt*2)
        S.boostLog[#S.boostLog + 1] = string.format("l%d:%s:wk%02x:sh%d",
          lvl, st, wk, H.readByte(SHLD + tgt*2))
      end
    end
    c.bp = b
  end
  local b0 = bp(0)
  if b0 ~= lastBp then
    lastBp = b0
    if #bpTrace < 60 then
      bpTrace[#bpTrace + 1] = string.format("f%d:%d", S.frames, b0)
    end
  end
  -- party death first: a wipe's game-over teardown must read "wiped",
  -- not "torn_down" (fire-policy postmortem: a death raced the label)
  local aliveC = 0
  for _, c in ipairs(chars) do if c.hp > 0 then aliveC = aliveC + 1 end end
  if aliveC == 0 then S.result = "wiped" return true end
  if not H.battleLoadStarted() then S.result = "torn_down" return true end
  local aliveM = 0
  for _, m in ipairs(mons) do
    if monsterAlive(m.slot) then aliveM = aliveM + 1 end
  end
  if aliveM == 0 then S.result = "won" return true end
  if S.frames >= BATTLE_FRAMES then S.result = "budget" return true end
  return false
end

-- ------------------------------------------------------------ report --
local B = 0                        -- current battle index (1-based)
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
  mline("steps_paced", paceSteps)
  if voidReason then
    mline("void", voidReason)
    return
  end
  local sp = {}
  for _, m in ipairs(mons) do
    sp[#sp + 1] = string.format("%04X", H.readWord(0x57c0 + m.slot*2))
  end
  mline("formation", table.concat(sp, ","))
  mline("result", S.result)
  mline("frames", S.frames)
  mline("player_actions", S.playerActions)
  mline("enemy_actions", S.enemyActions)
  mline("counter_actions", S.counterActions)
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
  mline("monster_hp_start", slotCsv(mons, "hp0"))
  mline("monster_dmg", slotCsv(mons, "dmg"))
  for _, m in ipairs(mons) do m.hp = H.readWord(MHP + m.slot*2) end
  mline("monster_hp_remaining", slotCsv(mons, "hp"))
  local shields = {}
  for _, m in ipairs(mons) do
    shields[#shields + 1] = string.format("s%d:%d/%d", m.slot,
      H.readByte(SHLD + m.slot*2), H.readByte(SHLD + m.slot*2 + 1))
  end
  mline("monster_shields_end", table.concat(shields, ","))
  mline("terra_hp_end", H.readWord(PHP))
  mline("terra_mp_end", H.readWord(PMP))
  mline("bp_curve", table.concat(bpTrace, ","))
  mline("action_trace", table.concat(actTrace, ","))
  mline("boost_states", table.concat(S.boostLog, ","))
end

-- ----------------------------------------------------- battle blocks --
assert(POLICIES[POLICY], "unknown POLICY: " .. tostring(POLICY))

local function paceStep(k)
  -- pace (78,58)<->(77,58) until a battle starts loading. A random
  -- encounter fires THROUGH an event script (EventScript_RandBattle,
  -- field/battle.asm), so eventRunning alone is normal here: pacing goes
  -- hands-off during any event and only voids if no battle follows
  -- within 600 frames (a guard-catch's chatter would stall that long;
  -- its battle, if one comes, is caught by the formation pool gate).
  -- Never raises from the predicate: void reasons flow into the report.
  local battN, evHold, waited, lastX = 0, 0, 0, nil
  return H.driveUntil(function()
    waited = waited + 1
    battN = H.battleLoadStarted() and battN + 1 or 0
    if battN >= 3 then H.setPad({}) return true end
    if H.eventRunning() or H.dialogWaiting() then
      evHold = evHold + 1
    elseif H.hasControl() then
      evHold = 0
    end
    if evHold >= 600 then voidReason = "event_no_battle" H.setPad({}) return true end
    if H.mapId() ~= 50 then voidReason = "left_map" H.setPad({}) return true end
    if waited >= PACE_FRAMES then voidReason = "pace_timeout" H.setPad({}) return true end
    return false
  end, PACE_FRAMES + 600, {
    H.call(function()
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
      local x = H.fieldX()
      if lastX ~= nil and x ~= lastX then paceSteps = paceSteps + 1 end
      lastX = x
      H.setPad({ [(x >= 78) and "left" or "right"] = true })
    end),
    H.waitFrames(1),
  }, "encounter fires (b=" .. k .. ")")
end

local function battleBlock(k)
  local seed = SEEDS[k] or {}
  return seqStepList({
    H.call(function()
      B = k
      resetBattleState()
    end),
    H.loadState(STATE),
    H.waitFrames(10),
    H.waitUntil(calm(20), 1200, "field control (b=" .. k .. ")"),
    H.call(function()
      -- co-tune poke (survives loadState: ROM is not savestate-backed)
      if POKE_HP ~= nil then
        emu.write(ROM_HPMUL, POKE_HP, emu.memType.snesPrgRom)
        H.assertEq(H.readRomByte(ROM_HPMUL), POKE_HP, "hp band0 poked")
      end
      if POKE_SHIELD ~= nil then
        emu.write(ROM_SHIELD, POKE_SHIELD, emu.memType.snesPrgRom)
        H.assertEq(H.readRomByte(ROM_SHIELD), POKE_SHIELD, "resistance poked")
      end
      mline("knob_hp", string.format("%02x", H.readRomByte(ROM_HPMUL)))
      mline("knob_shield", string.format("%02x", H.readRomByte(ROM_SHIELD)))
      if seed.fa1 then H.writeByte(0x1fa1, seed.fa1) end
      if seed.fa2 then H.writeByte(0x1fa2, seed.fa2) end
      mline("seed_1fa1", string.format("%02x", H.readByte(0x1fa1)))
      mline("seed_1fa2", string.format("%02x", H.readByte(0x1fa2)))
    end),
    paceStep(k),
    H.cond(function() return voidReason ~= nil end, {
      H.call(function() report() end),
    }, {
      H.waitUntilSoft(function() return H.battleActive() end, 900,
        "battle_active_b" .. k, 30),
      H.waitFrames(240 + 7 * (k - 1)),   -- settle + rng phase jitter
      H.call(function()
        -- formation gate: every present species must be from the pool
        for slot = 0, 5 do
          if monsterAlive(slot) then
            local sp = H.readWord(0x57c0 + slot*2)
            if not POOL[sp] then
              voidReason = string.format("off_pool_species_%04X", sp)
            end
          end
        end
        if voidReason then report() return end
        for slot = 0, 3 do
          local hp = H.readWord(PHP + slot*2)
          if hp > 0 and hp ~= 0xffff then
            chars[#chars + 1] = { slot = slot, hp = hp, bp = bp(slot) }
          end
        end
        for slot = 0, 5 do
          if monsterAlive(slot) then
            local hp = H.readWord(MHP + slot*2)
            mons[#mons + 1] = { slot = slot, hp = hp, hp0 = hp, dmg = 0 }
            mline("mon_detail", string.format(
              "s%d:sp%04X:hp%d:weak%02x:sh%d/%d", slot,
              H.readWord(0x57c0 + slot*2), hp,
              H.readByte(WEAK + slot*2),
              H.readByte(SHLD + slot*2), H.readByte(SHLD + slot*2 + 1)))
          end
        end
        for qi, q in ipairs(QUEUES) do qShadow[qi] = H.readByte(q.ptr) end
        arm()
        H.log(string.format("[metrics-ev] b=%d armed frame=%d chars=%d mons=%d policy=%s",
          k, H.frame, #chars, #mons, POLICY))
      end),
      H.cond(function() return voidReason ~= nil end, {}, {
        H.driveUntil(function() return sample() end, BATTLE_FRAMES + 600, {
          H.call(function()
            local pad = POLICIES[POLICY]()
            if pad then H.setPad(pad) end
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

-- seqStepList: plain sequential composition (H.seqStep is local to the
-- lib, so rebuild the trivial version here)
function seqStepList(steps)
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

local blocks = {}
for k = 1, NBATTLES do blocks[#blocks + 1] = battleBlock(k) end
blocks[#blocks + 1] = H.call(function()
  H.log(string.format("[metrics] run_done policy=%s battles=%d", POLICY, NBATTLES))
end)

H.run({ maxFrames = 140000 }, blocks)
