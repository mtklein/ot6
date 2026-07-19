-- bal_party.lua -- the multi-character balance measurement. bal_mines.lua's
-- protocol (seeded draws, loadState-independent battles, paired samples
-- across policies) run against a PARTY instead of solo Terra, with every
-- stat attributed per party member.
--
-- THE FIXTURE. worldmap_narshe.mss puts LOCKE (battle slot 0, L6,
-- Fight/Steal/Item) and TERRA (slot 1, L4, Fight/Magic/Item, knowing Fire
-- and Cure) on the World of Balance at (84,34), the state gen_figaro.lua
-- walks south to Figaro. It is the closest existing fixture to the stretch
-- balance-metrics.md wants measured next -- Figaro -> Mt.Kolts is Terra +
-- Locke + Edgar -- and unlike the Figaro interiors it sits on a map with
-- LIVE random encounters, so the fights are the real pool rather than a
-- scripted set piece. What it is missing is EDGAR (and Sabin): the states
-- that carry them are still being minted. So the party numbers below are
-- two thirds of the stretch party, and the Edgar/Sabin kit rungs in
-- metrics_battle.lua's KITS table remain written-but-undriven. Point this
-- driver at a Kolts fixture when one exists; nothing else has to change.
--
-- Protocol (deliberately boring, and the same as bal_mines):
--  * every battle starts from an identical loadState -- battles are fully
--    independent (HP/MP/BP/RNG all reset).
--  * the danger counter $1F6E is zeroed per sample (mines_pace.lua's
--    Measurement #4 finding: the fixture's warm counter otherwise masks
--    the pacing entirely), and $1FA1 is seeded per battle index, so
--    battle k is the SAME battle in every policy arm -- paired samples.
--  * pacing is a dumb left/right two-tile walk at the spawn
--    (84,34)<->(83,34); leaving the world map or running out of budget
--    VOIDS the sample (logged; the next loadState wipes it away).
--  * the battle is then played to the end by POLICY x KIT, and metrics
--    are sampled every frame (the multi-actor core from
--    metrics_battle.lua, which documents every address and every
--    attribution rule -- read that header first).
--  * in-battle rng phase jitter: battle k arms after 240 + 7(k-1) settle
--    frames, so same-formation battles decorrelate.
--
-- Per battle the log carries greppable lines, bal_mines' shape:
--   [ot6] [metrics] b=<k> <key>=<value>
-- with the per-character fan-out riding the same `sN:` CSV convention the
-- monster lines already use. bal_aggregate.py tabulates both.
--
-- Policies (POLICY knob) set the BOOST discipline; the per-character KIT
-- picks the action, so one named policy plays two different characters:
--   baseline  never boosts, never probes -- the denominator
--   boost3    bank BP to 3, then spend all 3, and use the weakness once
--             one is revealed
--   greedy    spend every BP the turn it appears
--   badboost  bank to 3 then dump it into a plain Fight -- Measurement
--             #5's negative control, the "boost feels wasted" misplay
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

-- ------------------------------------------------------------- knobs --
local POLICY = "baseline"
local STATE = "/Users/mtklein/ot6/build/states/worldmap_narshe.mss.lua"
local NBATTLES = 6
-- BUFF_HP: 0 = measure the pool as it ships. >0 = set every monster's HP
-- to this before the clock starts, which is metrics_battle.lua's own
-- fixture-buff knob and the only way to make this pool express the loop
-- at all: the shipped species dies to one weakness hit, so BP can never
-- reach 3 and two chips can never land on a live target. A buffed arm
-- measures the INSTRUMENT and the loop's shape; the unbuffed arm is the
-- honest stretch number. Never mix them in one table.
local BUFF_HP = 0
local PACE_FRAMES = 7000            -- pacing budget per battle
local BATTLE_FRAMES = 9000          -- policy-driven battle budget
local SPAWN_X = 84                  -- pace between SPAWN_X and SPAWN_X-1
-- $1FA1 seeds (encounter-step roll). The world pool at the Narshe spawn
-- drew one formation ($0017) in every probe sample, so these vary the
-- STEP the encounter fires on rather than the formation -- which is what
-- decorrelates the samples. Same seeds in every policy arm.
local SEEDS = { 0x37, 0x6e, 0xa5, 0xdc, 0x13, 0x4a }

-- --------------------------------------------------------- addresses --
-- (all cited in metrics_battle.lua's header; kept in the same order)
local MENU  = 0x7bca               -- battle menu open flag
local ACTOR = 0x62ca               -- whose menu it is (battle slot)
local MSTATE = 0x7bc2              -- battle menu state (btlgfx_main.asm:12536)
local PHP   = 0x3bf4               -- party cur hp, +slot*2
local PMP   = 0x3c08               -- party cur mp, +slot*2
local MHP   = 0x3bfc               -- monster cur hp, +slot*2
local BP    = 0x3e9c               -- char bp, +slot*2
local PEND  = 0x3e9d               -- char pending boost, +slot*2
local SHLD  = 0x3e40               -- monster cur shields, +slot*2
local TIMER = 0x3e90               -- monster broken timer, +slot*2
local RVEAL = 0x3e91               -- monster revealed elements, +slot*2
local WEAK  = 0x3be8               -- monster weak elements, +slot*2
local ALIVE = 0x3aa8               -- monster presence bit0, +slot*2
local MSTAT = 0x3eec               -- monster status-1, +slot*2 ($c2 = gone)
local CHARIX = 0x3ed9              -- battle slot -> character index, +slot*2
local CMDTBL = 0x202e              -- battle commands, +slot*12 +i*3 (BY SLOT)
local DANGER = 0x1f6e              -- random battle counter (word)
local QUEUES = {                   -- `shadow`: dispatches an attack?
  { base = 0x3720, ptr = 0x3a64, counter = false, shadow = false }, -- gauge-full
  { base = 0x3820, ptr = 0x3a66, counter = false, shadow = true  }, -- ExecAction
  { base = 0x3920, ptr = 0x3a68, counter = true,  shadow = true  }, -- ExecRetal
}
local ST = { root = 0x05, spell = 0x0e, tools = 0x30, magitek = 0x2a,
             item = 0x0a, blitz = 0x3d, target = 0x38 }

local function bp(slot) return H.readByte(BP + slot*2) end
local function pend(slot) return H.readByte(PEND + slot*2) end
local function broken(slot) return H.readByte(TIMER + slot*2) > 0 end
local function monsterAlive(slot)
  return (H.readByte(ALIVE + slot*2) & 0x01) == 1
     and (H.readByte(MSTAT + slot*2) & 0xc2) == 0
end
local function battleCmd(slot, i) return H.readByte(CMDTBL + slot*12 + i*3) end
local function hasCmd(rec, want)
  for i = 0, 3 do if rec.cmds[i] == want then return true end end
  return false
end
local function pokeCmd(slot, cmd)
  for i = 0, 3 do H.writeByte(CMDTBL + slot*12 + i*3, cmd) end
end
local function anyRevealed(mask)
  for slot = 0, 5 do
    if monsterAlive(slot) and (H.readByte(RVEAL + slot*2) & mask) ~= 0 then
      return true
    end
  end
  return false
end

local ROSTER = {
  [0x00]="TERRA", [0x01]="LOCKE", [0x02]="CYAN",  [0x03]="SHADOW",
  [0x04]="EDGAR", [0x05]="SABIN", [0x06]="CELES", [0x07]="STRAGO",
  [0x08]="RELM",  [0x09]="SETZER",[0x0a]="MOG",   [0x0b]="GAU",
  [0x0c]="GOGO",  [0x0d]="UMARO", [0x0e]="WEDGE", [0x0f]="VICKS",
}

-- ------------------------------------------------------------- kits --
-- Same shape and same rationale as metrics_battle.lua's KITS: a per
-- character preference ladder, gated on the commands the actor really
-- owns, with sub-list entries reached by writing the cursor triple
-- rather than pressing toward them.
local CMD = { fight = 0x00, item = 0x01, magic = 0x02, steal = 0x05,
              tools = 0x09, blitz = 0x0a, magitek = 0x1d }
local SPELL = { fire = 0x00, cure = 0x2d }
local TOOL  = { autocrossbow = 0xaa, bioblaster = 0xa4 }
local SPELLBASE = { [0] = 0x0000, [1] = 0x013c, [2] = 0x0278, [3] = 0x03b4 }
local function magicCursor(slot, spellId)
  local base = 0x2092 + SPELLBASE[slot]
  for i = 0, 53 do
    if H.readByte(base + i*4) == spellId then
      local r, c = i // 2, i % 2
      local scroll = (r <= 3) and 0 or math.min(r - 3, 0x17)
      H.writeByte(0x8913 + slot, scroll)
      H.writeByte(0x8917 + slot, c)
      H.writeByte(0x891b + slot, r - scroll)
      return true
    end
  end
  return false
end
local function toolsCursor(slot, itemId)
  for i = 0, 7 do
    if H.readByte(0x4005 + i*3) == itemId then
      H.writeByte(0x895f + slot, 0)
      H.writeByte(0x8963 + slot, i % 2)
      H.writeByte(0x8967 + slot, i // 2)
      return true
    end
  end
  return false
end

local KITS = {
  [0x00] = { name = "TERRA",
    { tag = "fire", cmd = CMD.magic, mp = 4, want = "weak_fire",
      pick = function(slot) return magicCursor(slot, SPELL.fire) end },
    { tag = "probe_fire", cmd = CMD.magic, mp = 4, want = "probe_elem",
      pick = function(slot) return magicCursor(slot, SPELL.fire) end },
    { tag = "fight", cmd = CMD.fight },
    { tag = "tek", cmd = CMD.magitek },
  },
  [0x01] = { name = "LOCKE",
    { tag = "steal", cmd = CMD.steal, want = "probe_turn" },
    { tag = "fight", cmd = CMD.fight },
  },
  -- UNEXERCISED (no fixture carries them yet); see metrics_battle.lua
  [0x04] = { name = "EDGAR",
    { tag = "bio", cmd = CMD.tools, want = "weak_poison",
      pick = function(slot) return toolsCursor(slot, TOOL.bioblaster) end },
    { tag = "xbow", cmd = CMD.tools,
      pick = function(slot) return toolsCursor(slot, TOOL.autocrossbow) end },
    { tag = "fight", cmd = CMD.fight },
  },
  [0x05] = { name = "SABIN",
    { tag = "blitz", cmd = CMD.blitz, combo = { "left", "right" } },
    { tag = "fight", cmd = CMD.fight },
  },
}
local FALLBACK_KIT = { name = "?", { tag = "fight", cmd = CMD.fight } }

-- ---------------------------------------------------------- policies --
local POLICIES = {}
POLICIES.baseline = { boost = function() return 0 end, probe = false }
POLICIES.boost3   = { boost = function(slot)
  return bp(slot) >= 3 and 3 or 0 end, probe = true }
POLICIES.greedy   = { boost = function(slot)
  return bp(slot) >= 1 and math.min(bp(slot), 3) or 0 end, probe = true }
POLICIES.badboost = { boost = function(slot)
  return bp(slot) >= 3 and 3 or 0 end, probe = false, force = "fight" }

-- ------------------------------------------------------ accumulators --
local S, C, bySlot, mons, qShadow
local refs, shSeen, tmSeen = {}, {}, {}
local curActor, curSlot
local pendChips, pendBreaks
local voidReason, paceSteps
local actTrace

local function resetBattleState()
  S = {
    t0 = 0, frames = 0,
    playerActions = 0, enemyActions = 0, counterActions = 0,
    playerDequeues = 0, enemyDequeues = 0,
    playerDmg = 0, playerDmgBroken = 0, monsterHeal = 0,
    monsterSelfDmg = 0, unattributedDmg = 0,
    enemyDmg = 0, partyHeal = 0,
    regens = 0, boosts = { 0, 0, 0 },
    chips = 0, breaks = 0, breakFrames = {}, firstBreak = -1,
    unattributedChips = 0, unattributedBreaks = 0,
    brokenUptime = 0, nudges = 0,
    result = "budget",
  }
  C, bySlot, mons, qShadow = {}, {}, {}, {}
  curActor, curSlot = -1, nil
  pendChips, pendBreaks = {}, {}
  voidReason, paceSteps = nil, 0
  actTrace = {}
end

local function newChar(slot)
  local cix = H.readByte(CHARIX + slot*2)
  local cmds = {}
  for i = 0, 3 do cmds[i] = battleCmd(slot, i) end
  return {
    slot = slot, cix = cix, name = ROSTER[cix] or string.format("c%02X", cix),
    kit = KITS[cix] or FALLBACK_KIT, cmds = cmds,
    hp = H.readWord(PHP + slot*2), hp0 = H.readWord(PHP + slot*2),
    mp = H.readWord(PMP + slot*2), mp0 = H.readWord(PMP + slot*2),
    bp = bp(slot), bp0 = bp(slot),
    dequeues = 0, actions = 0, bpWrites = 0,
    dmg = 0, dmgBroken = 0, taken = 0, healed = 0,
    chips = 0, breaks = 0,
    boosts = { 0, 0, 0 }, bpSpent = 0, regens = 0,
    plans = {},
  }
end

-- ------------------------------------------------- turn state machine --
local ep = { slot = nil, entry = nil, want = 0, placed = false,
             comboIx = 1, pulses = 0 }
local function resetEpisode()
  ep.slot, ep.entry, ep.want, ep.placed = nil, nil, 0, false
  ep.comboIx, ep.pulses = 1, 0
end

local function entryOk(rec, entry, pol)
  if pol.force and entry.tag ~= pol.force and entry.tag ~= "fight" then
    return false
  end
  if not hasCmd(rec, entry.cmd) then return false end
  if entry.mp and H.readWord(PMP + rec.slot*2) < entry.mp then return false end
  if entry.want == "weak_fire" then return pol.probe and anyRevealed(0x01) end
  if entry.want == "weak_poison" then return pol.probe and anyRevealed(0x20) end
  if entry.want == "probe_elem" then
    -- the OTHER half of a weakness rung, and the half a first draft
    -- forgot: an elemental weakness is only REVEALED by hitting it, so a
    -- kit that casts Fire "once fire is revealed" never casts Fire at
    -- all. Measured: 6/6 world-pool fights with a fire-weak monster and
    -- Terra never cast. So spend an early turn on the element while the
    -- board is still unread -- bal_mines.lua's probe1 rotation, per
    -- character.
    return pol.probe and not anyRevealed(0xff) and rec.actions == 0
  end
  if entry.want == "probe_turn" then
    return pol.probe and not anyRevealed(0xff) and rec.actions == 0
  end
  return true
end

local function chooseAction(rec, pol)
  local pick
  for _, entry in ipairs(rec.kit) do
    if entryOk(rec, entry, pol) then pick = entry break end
  end
  if pick == nil then pick = { tag = "default", cmd = rec.cmds[0] } end
  pokeCmd(rec.slot, pick.cmd)
  return pick
end

local function pulse()
  if H.readByte(MENU) == 0 then
    if ep.slot ~= nil then resetEpisode() end
    return nil
  end
  local slot = H.readByte(ACTOR)
  local rec = bySlot[slot]
  if rec == nil then return { "a" } end
  if ep.slot ~= slot then resetEpisode() ep.slot = slot end
  ep.pulses = ep.pulses + 1
  if ep.entry == nil then
    ep.want = POLICIES[POLICY].boost(slot)
    ep.entry = chooseAction(rec, POLICIES[POLICY])
    rec.plans[ep.entry.tag] = (rec.plans[ep.entry.tag] or 0) + 1
  end
  if ep.pulses > 40 then
    ep.pulses, ep.placed, ep.entry = 0, false, nil
    S.nudges = S.nudges + 1
    return { "b" }
  end
  local st = H.readByte(MSTATE)
  if st == ST.root then
    if pend(slot) < ep.want and pend(slot) < bp(slot) then return { "r" } end
    return { "a" }
  end
  if st == ST.spell or st == ST.tools then
    if not ep.placed then
      ep.placed = true
      if ep.entry.pick then ep.entry.pick(slot) end
      return nil
    end
    return { "a" }
  end
  if st == ST.magitek or st == ST.item then return { "a" } end
  if st == ST.blitz then
    local combo = ep.entry.combo or {}
    local b = combo[ep.comboIx]
    ep.comboIx = ep.comboIx + 1
    return b and { b } or { "a" }
  end
  if st == ST.target then return { "a" } end
  return nil
end

-- -------------------------------------------------- event watchers --
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
    if value < prev then
      S.chips = S.chips + (prev - value)
      pendChips[#pendChips + 1] = prev - value
    end
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
      pendBreaks[#pendBreaks + 1] = 1
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
        if q.shadow then
          curActor = v
          curSlot = (v < 8) and (v // 2) or nil
        end
        if q.counter then S.counterActions = S.counterActions + 1 end
        if v < 8 then
          S.playerDequeues = S.playerDequeues + 1
          if S.playerDequeues % 2 == 0 then
            S.playerActions = S.playerActions + 1
          end
          local rec = bySlot[v // 2]
          if rec then
            rec.dequeues = rec.dequeues + 1
            if rec.dequeues % 2 == 0 then
              rec.actions = rec.actions + 1
              actTrace[#actTrace + 1] = string.format("%d:s%d:%d",
                S.playerActions, rec.slot, S.playerDmg)
            end
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
  local actorRec = curSlot and bySlot[curSlot]
  for i = 1, #pendChips do
    if actorRec then actorRec.chips = actorRec.chips + pendChips[i]
    else S.unattributedChips = S.unattributedChips + pendChips[i] end
    pendChips[i] = nil
  end
  for i = 1, #pendBreaks do
    if actorRec then actorRec.breaks = actorRec.breaks + 1
    else S.unattributedBreaks = S.unattributedBreaks + 1 end
    pendBreaks[i] = nil
  end
  local anyBroken = false
  for _, m in ipairs(mons) do
    if broken(m.slot) then anyBroken = true end
    local hp = H.readWord(MHP + m.slot*2)
    if hp < m.hp then
      local d = m.hp - hp
      S.playerDmg = S.playerDmg + d
      m.dmg = m.dmg + d
      if broken(m.slot) then S.playerDmgBroken = S.playerDmgBroken + d end
      if actorRec then
        actorRec.dmg = actorRec.dmg + d
        if broken(m.slot) then actorRec.dmgBroken = actorRec.dmgBroken + d end
      elseif curActor >= 8 then
        S.monsterSelfDmg = S.monsterSelfDmg + d
      else
        S.unattributedDmg = S.unattributedDmg + d
      end
    elseif hp > m.hp then
      S.monsterHeal = S.monsterHeal + (hp - m.hp)
    end
    m.hp = hp
  end
  if anyBroken then S.brokenUptime = S.brokenUptime + 1 end
  for _, c in ipairs(C) do
    local hp = H.readWord(PHP + c.slot*2)
    if hp < c.hp then
      S.enemyDmg = S.enemyDmg + (c.hp - hp)
      c.taken = c.taken + (c.hp - hp)
    elseif hp > c.hp then
      S.partyHeal = S.partyHeal + (hp - c.hp)
      c.healed = c.healed + (hp - c.hp)
    end
    c.hp = hp
    c.mp = H.readWord(PMP + c.slot*2)
    local b = bp(c.slot)
    if b > c.bp then
      S.regens = S.regens + (b - c.bp)
      c.regens = c.regens + (b - c.bp)
      c.bpWrites = c.bpWrites + 1
    elseif b < c.bp then
      local lvl = c.bp - b
      if lvl >= 1 and lvl <= 3 then
        S.boosts[lvl] = S.boosts[lvl] + 1
        c.boosts[lvl] = c.boosts[lvl] + 1
      end
      c.bpSpent = c.bpSpent + lvl
      c.bpWrites = c.bpWrites + 1
    end
    c.bp = b
  end
  -- party death first: a wipe's game-over teardown must read "wiped",
  -- not "torn_down" (bal_mines' fire-policy postmortem)
  local aliveC = 0
  for _, c in ipairs(C) do if c.hp > 0 then aliveC = aliveC + 1 end end
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
local function charCsv(fn)
  local parts = {}
  for _, c in ipairs(C) do
    parts[#parts + 1] = string.format("s%d:%s", c.slot, tostring(fn(c)))
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
  mline("buff_hp", BUFF_HP)
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
  mline("menu_nudges", S.nudges)
  mline("monster_hp_start", slotCsv(mons, "hp0"))
  mline("monster_dmg", slotCsv(mons, "dmg"))
  for _, m in ipairs(mons) do m.hp = H.readWord(MHP + m.slot*2) end
  mline("monster_hp_remaining", slotCsv(mons, "hp"))

  -- the fan-out
  mline("party_size", #C)
  mline("party", charCsv(function(c)
    return string.format("%02X:%s", c.cix, c.name) end))
  mline("char_actions", charCsv(function(c) return c.actions end))
  mline("char_dmg", charCsv(function(c) return c.dmg end))
  mline("char_dmg_broken", charCsv(function(c) return c.dmgBroken end))
  mline("char_chips", charCsv(function(c) return c.chips end))
  mline("char_breaks", charCsv(function(c) return c.breaks end))
  mline("char_boosts", charCsv(function(c)
    return string.format("%d/%d/%d", c.boosts[1], c.boosts[2], c.boosts[3]) end))
  mline("char_bp_spent", charCsv(function(c) return c.bpSpent end))
  mline("char_bp_regen", charCsv(function(c) return c.regens end))
  mline("char_bp_start", charCsv(function(c) return c.bp0 end))
  mline("char_bp_end", charCsv(function(c) return c.bp end))
  mline("char_dmg_taken", charCsv(function(c) return c.taken end))
  mline("char_hp_end", charCsv(function(c) return c.hp end))
  mline("char_hp_start", charCsv(function(c) return c.hp0 end))
  mline("char_mp_spent", charCsv(function(c) return c.mp0 - c.mp end))
  mline("char_plan", charCsv(function(c)
    local parts = {}
    for tag, n in pairs(c.plans) do parts[#parts + 1] = tag .. "*" .. n end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, "+") or "-"
  end))

  -- identity checks (see metrics_battle.lua for what each one proves)
  local aSum, dSum, cSum, bSum, tSum, wSum = 0, 0, 0, 0, 0, 0
  for _, c in ipairs(C) do
    aSum = aSum + c.actions
    dSum = dSum + c.dmg
    cSum = cSum + c.chips
    bSum = bSum + c.breaks
    tSum = tSum + c.taken
    wSum = wSum + c.bpWrites
  end
  -- bp_action_skew reads a steady -1 on a won fight and that is
  -- EXPECTED, not slack: the sampler's stop condition fires the frame the
  -- last monster dies, which is before the killing action reaches
  -- Ot6ActionEnd, so its bp write is never observed. Measured constant at
  -- -1 across 6/6 world-pool battles regardless of action count (1 or 2)
  -- and on battle2_doorstep. A skew that GROWS with actions would mean
  -- the dequeue pairing is wrong; a steady -1 means it is right.
  mline("actions_sum", aSum)
  mline("actions_residual", S.playerActions - aSum)
  mline("bp_action_skew", wSum - aSum)
  mline("dmg_sum", dSum)
  mline("monster_self_dmg", S.monsterSelfDmg)
  mline("unattributed_dmg", S.unattributedDmg)
  mline("dmg_residual",
    S.playerDmg - dSum - S.monsterSelfDmg - S.unattributedDmg)
  mline("chips_sum", cSum)
  mline("chips_residual", S.chips - cSum - S.unattributedChips)
  mline("breaks_sum", bSum)
  mline("breaks_residual", S.breaks - bSum - S.unattributedBreaks)
  mline("dmg_taken_residual", S.enemyDmg - tSum)
  mline("action_trace", table.concat(actTrace, ","))
end

-- ----------------------------------------------------- battle blocks --
assert(POLICIES[POLICY], "unknown POLICY: " .. tostring(POLICY))

-- seqStepList: plain sequential composition (H.seqStep is local to the
-- lib, so rebuild the trivial version here -- same as bal_mines.lua)
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

local function calmWorld(n)
  local cnt = 0
  return function()
    cnt = (H.worldHasControl() and H.worldAligned()) and cnt + 1 or 0
    return cnt >= n
  end
end

local function paceStep(k)
  -- Pace two world tiles until a battle starts loading. Never raises from
  -- the predicate: void reasons flow into the report instead.
  local battN, waited, lastX = 0, 0, nil
  return H.driveUntil(function()
    waited = waited + 1
    battN = H.battleLoadStarted() and battN + 1 or 0
    if battN >= 3 then H.setPad({}) return true end
    if not H.worldMode() then voidReason = "left_world" H.setPad({}) return true end
    if waited >= PACE_FRAMES then voidReason = "pace_timeout" H.setPad({}) return true end
    return false
  end, PACE_FRAMES + 600, {
    H.call(function()
      if not (H.worldHasControl() and H.worldAligned()) then H.setPad({}) return end
      local x = H.worldX()
      if lastX ~= nil and x ~= lastX then paceSteps = paceSteps + 1 end
      lastX = x
      H.setPad({ [(x >= SPAWN_X) and "left" or "right"] = true })
    end),
    H.waitFrames(1),
  }, "encounter fires (b=" .. k .. ")")
end

local function battleBlock(k)
  return seqStepList({
    H.call(function() B = k resetBattleState() end),
    H.loadState(STATE),
    H.waitFrames(10),
    H.waitUntil(calmWorld(20), 1800, "world control (b=" .. k .. ")"),
    H.call(function()
      -- cold danger counter + seeded step roll: battle k is the same
      -- battle in every policy arm (mines_pace.lua Measurement #4)
      H.writeWord(DANGER, 0)
      H.writeByte(0x1fa1, SEEDS[k] or 0)
      mline("seed_1fa1", string.format("%02x", H.readByte(0x1fa1)))
    end),
    paceStep(k),
    H.cond(function() return voidReason ~= nil end, {
      H.call(function() report() end),
    }, {
      H.waitUntilSoft(function() return H.battleActive() end, 900,
        "battle_active_b" .. k, 30),
      H.waitFrames(240 + 7 * (k - 1)),   -- settle + rng phase jitter
      H.call(function()
        for slot = 0, 3 do
          local hp = H.readWord(PHP + slot*2)
          if hp > 0 and hp ~= 0xffff then
            local rec = newChar(slot)
            C[#C + 1] = rec
            bySlot[slot] = rec
          end
        end
        for slot = 0, 5 do
          if monsterAlive(slot) then
            if BUFF_HP > 0 then H.writeWord(MHP + slot*2, BUFF_HP) end
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
        -- seed the actor shadow from the action queue's last dequeue: an
        -- action can already be in flight 240 frames into the battle
        local last = (H.readByte(QUEUES[2].ptr) - 1) & 0xff
        local v = H.readByte(QUEUES[2].base + last)
        if (v & 0x80) == 0 then
          curActor = v
          curSlot = (v < 8) and (v // 2) or nil
        end
        resetEpisode()
        arm()
        for _, c in ipairs(C) do
          mline("member", string.format("s%d:%02X:%s:cmds%02X/%02X/%02X/%02X",
            c.slot, c.cix, c.name, c.cmds[0], c.cmds[1], c.cmds[2], c.cmds[3]))
        end
        H.log(string.format("[metrics-ev] b=%d armed frame=%d chars=%d mons=%d policy=%s",
          k, H.frame, #C, #mons, POLICY))
      end),
      H.driveUntil(function() return sample() end, BATTLE_FRAMES + 600, {
        H.call(function()
          local pad = pulse()
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
  })
end

local blocks = {}
for k = 1, NBATTLES do blocks[#blocks + 1] = battleBlock(k) end
blocks[#blocks + 1] = H.call(function()
  H.log(string.format("[metrics] run_done policy=%s battles=%d buff_hp=%d",
    POLICY, NBATTLES, BUFF_HP))
end)

H.run({ maxFrames = 200000 }, blocks)
