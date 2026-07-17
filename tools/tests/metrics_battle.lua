-- metrics_battle: auto-battler balance probe. loads a doorstep state,
-- enters the fight, and PLAYS it with a swappable input policy while
-- recording what the balance work needs (docs/design/balance-metrics.md):
-- actions per side, damage split broken/unbroken, bp regen/spends by
-- level, shield chips, breaks, break uptime. no asserts -- the run
-- "passes" whenever the battle resolves or the budget ends; the product
-- is the report at the bottom of the log, one stat per line, greppable:
--   [ot6] [metrics] key=value
--
-- knobs are the locals right below: POLICY picks the player, STATE the
-- formation, ROUNDS caps recorded player actions (0 = play to the end),
-- SETTLE_EXTRA jitters the rng phase so one state x policy pair can
-- yield a distribution instead of a single deterministic point.
--
-- address notes (confirmed in-repo, not guessed):
--  * battle code runs with db=$7e (battle_main.asm BattleMain), so its
--    absolute stores surface at $7Exxxx for write callbacks; dp writes
--    surface at $0000xx (none watched here).
--  * entity tables are 2 bytes/entity, chars at +0..+6, monsters at
--    +8..+$12: cur hp $3bf4 (battle_main.asm:2934) puts monster slot i
--    at $3bfc+i*2 (the guards: $3c00/$3c02); ot6.asm's shield tables
--    $3e38/timer $3e88 put monster slots at $3e40/$3e90.
--  * executed actions: the battle loop dequeues entity offsets from
--    three queues (battle_main.asm @0092/@00a6/@0049): advance-wait
--    $3720 (start ptr $3a64), action $3820 ($3a66), counter $3920
--    ($3a68). ptrs are 8-bit (the loop runs shortai). sampling each
--    START ptr per frame and reading the bytes it walked past counts
--    what actually ran; $ff bytes are removed/cancelled entries (actor
--    died with actions queued) and don't count. offset < 8 = player.
--
-- TODO (real gaps, deliberately not guessed around):
--  * per-attacker damage attribution: damage is credited to a side by
--    watching the VICTIM's hp, so monster-on-monster damage (muddle)
--    would land in player_dmg. a clean fix needs a hook at damage apply
--    with the attacker index in hand; no stable wram address found that
--    still carries it at write time ($10 is dp scratch, long gone).
--  * "immediate" actions ($340a, battle_main.asm @0033) bypass all
--    three queues (battle-start scripts, final attacks). rare in wob
--    trash; uncounted for now.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

-- ------------------------------------------------------------- knobs --
local POLICY = "boost3"            -- "baseline" | "boost3" | "greedy"
local STATES = {
  doorstep  = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua",
  doorstep2 = "/Users/mtklein/ot6/build/states/battle2_doorstep.mss.lua",
}
local STATE = STATES.doorstep
local ROUNDS = 0                   -- player actions to record; 0 = to the end
local SETTLE_EXTRA = 0             -- extra pre-arm frames (rng phase jitter)
local METRICS_FRAMES = 20000       -- metrics-window frame budget
-- BUFF turns the demo doorstep (40-hp guards, no party-hittable
-- weakness -> break/boost never engage) into a MEASURABLE fixture:
-- inject a fire weakness and enough hp that the fight lasts long
-- enough for banking to pay off. this is a stand-in until real
-- post-magitek states exist; the delta between baseline and boost3
-- here is the first "how much juice" number.
local BUFF_HP   = 0                -- >0 = set every monster's hp to this
local BUFF_FIRE = false            -- true = make monsters fire-weak

-- --------------------------------------------------------- addresses --
local MENU  = 0x7bca               -- battle menu open flag
local ACTOR = 0x62ca               -- whose menu it is (char slot)
local PHP   = 0x3bf4               -- party cur hp, +slot*2
local MHP   = 0x3bfc               -- monster cur hp, +slot*2
local BP    = 0x3e9c               -- char bp, +slot*2
local PEND  = 0x3e9d               -- char pending boost, +slot*2
local SHLD  = 0x3e40               -- monster cur shields, +slot*2 (odd = max)
local TIMER = 0x3e90               -- monster broken timer, +slot*2 (odd = revealed)
local ALIVE = 0x3aa8               -- monster presence bit0, +slot*2
local MSTAT = 0x3eec               -- monster status-1, +slot*2 ($c2 = gone)
local QUEUES = {                   -- dequeue-side action counting (see header)
  { base = 0x3720, ptr = 0x3a64, counter = false },  -- advance-wait (jump)
  { base = 0x3820, ptr = 0x3a66, counter = false },  -- main action queue
  { base = 0x3920, ptr = 0x3a68, counter = true },   -- counterattacks: these
}                                  -- land in the per-side totals TOO; the
                                   -- counter_actions line is a subset, not
                                   -- a third bucket

local function bp(slot) return H.readByte(BP + slot*2) end
local function pend(slot) return H.readByte(PEND + slot*2) end
local function broken(slot) return H.readByte(TIMER + slot*2) > 0 end
local function monsterAlive(slot)
  -- the hud builder's own liveness criterion (visual_f2 idiom)
  return (H.readByte(ALIVE + slot*2) & 0x01) == 1
     and (H.readByte(MSTAT + slot*2) & 0xc2) == 0
end

-- ---------------------------------------------------------- policies --
-- a policy is a function() -> button list for this ~30-frame pulse, or
-- nil to idle. it reads live ram and may keep closure state. swap by
-- editing POLICY above; add new ones here.
local rTries, pendSeen = 0, -1
local function menuSlot()
  if H.readByte(MENU) == 0 then pendSeen = -1 return nil end
  return H.readByte(ACTOR)
end
-- shared commit helper: raise pending toward `want` with R, then
-- confirm with A. the retry guard un-wedges us if some menu context
-- eats R (6 fruitless pulses ~= 180 frames, then fall through to A
-- until pending moves or the menu closes).
local function commitThenConfirm(slot, want)
  local p = pend(slot)
  if p ~= pendSeen then rTries, pendSeen = 0, p end
  if p < want and p < bp(slot) and rTries < 6 then
    rTries = rTries + 1
    return { "r" }
  end
  return { "a" }
end

local POLICIES = {}
-- baseline: confirm through every menu unboosted. vanilla-speed play;
-- the denominator for every boost comparison.
function POLICIES.baseline()
  if menuSlot() == nil then return nil end
  return { "a" }
end
-- boost3: bank bp on plain turns, and the moment 3 are spendable,
-- commit all 3 (fold to tier 3 / x8) and fire. the always-boost-3
-- numerator: maximum per-action throughput.
function POLICIES.boost3()
  local slot = menuSlot()
  if slot == nil then return nil end
  if bp(slot) >= 3 or pend(slot) > 0 then
    return commitThenConfirm(slot, 3)
  end
  return { "a" }                   -- bank toward 3
end
-- greedy: spend whatever is there, every turn (in practice a stream of
-- 1-boosts after the opener). the "player who never banks" datapoint.
function POLICIES.greedy()
  local slot = menuSlot()
  if slot == nil then return nil end
  return commitThenConfirm(slot, 3)
end

-- ------------------------------------------------------ accumulators --
local S = {
  t0 = 0,                          -- H.frame at arm; all frame stats relative
  frames = 0,
  playerActions = 0, enemyActions = 0, counterActions = 0,
  playerDequeues = 0, enemyDequeues = 0,
  playerDmg = 0, playerDmgBroken = 0, monsterHeal = 0,
  enemyDmg = 0, partyHeal = 0,
  regens = 0, boosts = { 0, 0, 0 },
  chips = 0, breaks = 0, breakFrames = {}, firstBreak = -1,
  brokenUptime = 0,                -- frames with any tracked monster broken
  result = "budget",
}
local mons, chars = {}, {}         -- tracked slots, discovered at arm
local qShadow = {}                 -- per-queue start-ptr shadows
local refs = {}                    -- memory-callback handles
local shSeen, tmSeen = {}, {}      -- write-callback shadows by monster slot

-- -------------------------------------------------- event watchers --
-- chips and breaks are WRITE events, not per-frame states: a boosted
-- multi-hit can chip more than once between frames, and a break's
-- 0 -> OT6_BREAK_TICKS store is the only unambiguous "break happened"
-- signal (per-frame timer>0 also sees mid-window decrements).
local function arm()
  S.t0 = H.frame
  for i = 0, 5 do
    shSeen[i] = H.readByte(SHLD + i*2)
    tmSeen[i] = H.readByte(TIMER + i*2)
  end
  -- ot6.asm Ot6Chip: `dec a / sta $3e38,y` -- one absolute store per
  -- chip, value = new count; recovery restores UP (never a chip).
  refs[1] = emu.addMemoryCallback(function(addr, value)
    local off = addr - (0x7e0000 + SHLD)
    if off % 2 ~= 0 then return end          -- odd byte = max shields
    local slot = off // 2
    local prev = shSeen[slot]
    shSeen[slot] = value
    if value < prev then S.chips = S.chips + (prev - value) end
  end, emu.callbackType.write, 0x7e0000 + SHLD, 0x7e0000 + SHLD + 11)
  -- ot6.asm Ot6Chip: `sta $3e88,y` with OT6_BREAK_TICKS on the 0-shield
  -- hit; a 0 -> nonzero write is a break, everything else is the tick.
  refs[2] = emu.addMemoryCallback(function(addr, value)
    local off = addr - (0x7e0000 + TIMER)
    if off % 2 ~= 0 then return end          -- odd byte = revealed mask
    local slot = off // 2
    local prev = tmSeen[slot]
    tmSeen[slot] = value
    if prev == 0 and value > 0 then
      -- pure accumulation only: printing from inside a memory callback
      -- is unproven here (the lib flags callback logging as a crash
      -- suspect); break_frames in the report carries the same info
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
-- runs as the metrics drive's predicate, so it fires EVERY frame while
-- the policy plays. hp and bp move at most once per entity per frame
-- (one store per action-end / damage-apply), so frame deltas lose
-- nothing there; the sampler also walks the dequeue pointers and calls
-- the stop conditions.
local function sample()
  S.frames = H.frame - S.t0
  for qi, q in ipairs(QUEUES) do
    local cur = H.readByte(q.ptr)
    while qShadow[qi] ~= cur do
      local v = H.readByte(q.base + qShadow[qi])
      if (v & 0x80) == 0 then
        -- each real action passes through TWO queues (advance-wait +
        -- action), so raw dequeues run exactly 2x real actions.
        -- player_actions/enemy_actions emit REAL actions: every second
        -- dequeue of a side credits one. counter_actions stays a raw
        -- counter-queue dequeue tally (subset diagnostics).
        if q.counter then S.counterActions = S.counterActions + 1 end
        if v < 8 then
          S.playerDequeues = S.playerDequeues + 1
          if S.playerDequeues % 2 == 0 then
            S.playerActions = S.playerActions + 1
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
      local d = m.hp - hp                    -- effective damage: hp clamps
      S.playerDmg = S.playerDmg + d          -- at 0, which is what ttk feels
      m.dmg = m.dmg + d
      if broken(m.slot) then                 -- the game's own x2 criterion
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
      S.regens = S.regens + (b - c.bp)       -- unboosted action-end: +1
    elseif b < c.bp then
      local lvl = c.bp - b                   -- Ot6ActionEnd consume: -pending
      if lvl >= 1 and lvl <= 3 then S.boosts[lvl] = S.boosts[lvl] + 1 end
    end
    c.bp = b
  end
  -- stop conditions, checked after the frame's bookkeeping
  if not H.battleLoadStarted() then S.result = "torn_down" return true end
  local aliveM = 0
  for _, m in ipairs(mons) do
    if monsterAlive(m.slot) then aliveM = aliveM + 1 end
  end
  if aliveM == 0 then S.result = "won" return true end
  local aliveC = 0
  for _, c in ipairs(chars) do if c.hp > 0 then aliveC = aliveC + 1 end end
  if aliveC == 0 then S.result = "wiped" return true end
  if ROUNDS > 0 and S.playerActions >= ROUNDS then
    S.result = "rounds" return true
  end
  if S.frames >= METRICS_FRAMES then S.result = "budget" return true end
  return false
end

-- ------------------------------------------------------------ report --
local function mline(k, v) H.log("[metrics] " .. k .. "=" .. tostring(v)) end
local function slotCsv(list, field)
  local parts = {}
  for _, e in ipairs(list) do
    parts[#parts + 1] = string.format("s%d:%d", e.slot, e[field])
  end
  return table.concat(parts, ",")
end
local function report()
  mline("policy", POLICY)
  mline("state", STATE:match("[^/]+$"))
  mline("rounds_cfg", ROUNDS)
  mline("jitter_cfg", SETTLE_EXTRA)
  mline("result", S.result)
  mline("frames", S.frames)
  mline("player_actions", S.playerActions)
  mline("enemy_actions", S.enemyActions)
  mline("counter_actions", S.counterActions)
  mline("player_dmg", S.playerDmg)
  mline("player_dmg_broken", S.playerDmgBroken)
  mline("player_dmg_unbroken", S.playerDmg - S.playerDmgBroken)
  mline("enemy_dmg", S.enemyDmg)
  mline("party_heal", S.partyHeal)
  mline("monster_heal", S.monsterHeal)
  mline("boosts_spent", string.format("l1:%d,l2:%d,l3:%d",
    S.boosts[1], S.boosts[2], S.boosts[3]))
  mline("bp_regen", S.regens)
  mline("shield_chips", S.chips)
  mline("breaks", S.breaks)
  mline("first_break_frame", S.firstBreak)
  mline("break_frames", table.concat(S.breakFrames, ","))
  mline("break_uptime_frames", S.brokenUptime)
  mline("monster_hp_start", slotCsv(mons, "hp0"))
  mline("monster_dmg", slotCsv(mons, "dmg"))
  -- re-read at report time: the winning hit may land the same frame the
  -- liveness flip stops the sampler
  for _, m in ipairs(mons) do m.hp = H.readWord(MHP + m.slot*2) end
  mline("monster_hp_remaining", slotCsv(mons, "hp"))
end

-- --------------------------------------------------------------- run --
assert(POLICIES[POLICY], "unknown POLICY: " .. tostring(POLICY))
H.run({ maxFrames = METRICS_FRAMES + 12000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  -- battle-load idiom, verbatim from battle_boost
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  -- input during the first window-open animation wedges the battle menu
  H.waitFrames(240),
  H.waitFrames(SETTLE_EXTRA),      -- 0 = no jitter, completes same frame
  H.call(function()
    -- discover who's actually in this formation, then start the clock
    for slot = 0, 3 do
      local hp = H.readWord(PHP + slot*2)
      if hp > 0 and hp ~= 0xffff then
        chars[#chars + 1] = { slot = slot, hp = hp, bp = bp(slot) }
      end
    end
    for slot = 0, 5 do
      if monsterAlive(slot) then
        -- optional fixture buff, applied BEFORE the hp snapshot so the
        -- dmg accounting starts from the buffed value ($3be0 = weak
        -- elements, low byte fire; $3bec/$3bee mirror for the 2-guard
        -- formation, per battle_break.lua)
        if BUFF_FIRE then
          H.writeByte(0x3be0 + slot*2, H.readByte(0x3be0 + slot*2) | 0x01)
        end
        if BUFF_HP > 0 then H.writeWord(MHP + slot*2, BUFF_HP) end
        local hp = H.readWord(MHP + slot*2)
        mons[#mons + 1] = { slot = slot, hp = hp, hp0 = hp, dmg = 0 }
      end
    end
    for qi, q in ipairs(QUEUES) do qShadow[qi] = H.readByte(q.ptr) end
    arm()
    H.log(string.format("[metrics-ev] armed frame=%d chars=%d mons=%d policy=%s",
      H.frame, #chars, #mons, POLICY))
  end),
  -- the metrics loop: sampler every frame, one policy pulse per ~30.
  -- sample() enforces its own budget (result=budget), so the driveUntil
  -- cap only exists to satisfy the harness and never wins.
  H.driveUntil(function() return sample() end, METRICS_FRAMES + 600, {
    H.call(function()
      local pad = POLICIES[POLICY]()
      if pad then H.setPad(pad) end
    end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(24),
  }, "battle resolved"),
  H.call(function()
    disarm()
    report()
    H.screenshot("metrics_end")
  end),
})
