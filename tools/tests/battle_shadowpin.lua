-- @suite slow
-- battle_shadowpin.lua -- Shadow's throws hobble and pin (#546, docs/design/kit-shadow-pin.md), by play.
--
--   OT6_SRAM_CHECKPOINT=build/checkpoints/wor-kt-factory-v1 tools/tests/run.sh tools/tests/battle_shadowpin.lua
--
-- The rule (Ot6Pin, ot6_pin.asm).  A character's Throw that lands on a monster hobbles it (Slow); a throw at a
-- monster already Slowed, from any source, pins it (Stop for OT6_PIN_TICKS = 8 status ticks, Ot6StopTicks) and
-- uses up the hobble; a throw at a pinned monster changes no status; a Broken monster is hobbled if free and
-- never pinned; vanilla's immunities stand (a Stop-immune body stays hobbled).  Every other Stop keeps
-- vanilla's 18 ticks.  The mark before the shield emblem shows the font's dagger while a monster is Slowed and
-- the knife while it is Stopped; it changes with the hit's numeral (#539's hold and event ring), not when the
-- status is computed, and clears when the status ends.
--
-- Continues wor-kt-factory-v1 (party 3: CYAN, SHADOW, SABIN, GOGO on the factory's save point beside Inferno),
-- puts magicite that teaches Slow on SHADOW, Stop on CYAN and Break on SABIN through the Skills menu (all
-- three have Magic; GOGO's commands hold none), cares, and walks onto Inferno's trigger (event battle 114: Inferno, which takes Slow and not
-- Stop, and his arms Rough and Striker, which take both; any random battle on the way is played by the
-- tactical driver).  In Inferno's battle, through the real menu (H.kitBattle; the others Defend), in four groups,
-- each played from a snapshot at the battle's open until its properties are seen:
--   1. SHADOW throws at Rough: hobbled.            2. GOGO Mimics it: Rough pinned (Shadow hobbles, Gogo pins).
--   3. SHADOW casts Slow on Striker.   4. SABIN's Break (two points: three shields, no damage) breaks it.
--   5. SHADOW throws at the Broken, Slowed Striker: it stays hobbled, never pinned.
--   6. SHADOW casts Slow on a free arm.            7. SHADOW throws at it: pinned by one throw.
--   8. CYAN casts Stop on an arm: 18 ticks, vanilla's.
--   9. 10. SHADOW throws at Inferno twice: hobbled, then still hobbled (Stop-immune), never Stopped.
-- The Stop arm (Ot6BrokenTurn): a Stopped monster whose turn was queued and not yet begun (its command list's
-- head is command $1f, the AI script's turn) loses that turn when ExecAction reaches it: no AI script runs and
-- the list is empty after.  Group 1 confirms GOGO's Mimic while Rough is about to take a turn (see G1 below),
-- each try at another gauge threshold, until a Stop has met a pending turn.  Every case is judged, and one or
-- more must be seen.  A wipe replays the run from its boot (retries 4, counted).
-- Every throw is judged by the rule from the target's state as Ot6Pin found it (stopped, slowed, broken, what
-- it may take) against its status 3 at the script's end, so a draw that breaks an arm is judged as the rule
-- says (a Broken arm is hobbled, never pinned).  The marks are read from VRAM (the cell two before each line's
-- anchor) every frame, beside the frame each numeral's event is shown (Ot6EvApply).  Reads and presses only.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CYAN, SHADOW, SABIN, GOGO = 2, 3, 5, 12
local INFERNO, ROUGH, STRIKER = 0x10C, 0x141, 0x142
local SLOW, STOP = 0x04, 0x10
local SPELL_SLOW, SPELL_STOP = 0x19, 0x20
local DAGGER, KNIFE = 0x21D8, 0x2174
local MARKCELL, HOLD, EVQ, SHADOWL = 0x7EEF16, 0x7EEE4D, 0x7EEE51, 0x7EECF1
local PIN, STOPT, EVAPPLY, FLUSH = H.sym("Ot6Pin"), H.sym("Ot6StopTicks"), H.sym("Ot6EvApply"), H.sym("Ot6ShowFlush")
local EXECACT, EXECAI, RANDAI = H.sym("ExecAction"), H.sym("ExecMonsterAction"), H.sym("RandMonsterAction")
local ENDACT, NOACT = H.sym("EndAction"), H.sym("Ot6NoActionMark")
local acting = false       -- an action is executing (ExecAction entered, EndAction not yet reached)
local actStart = 0         -- the frame it entered
local gaugeHist = {}       -- per monster entity: its gauge ($3218, a word counting up to the fill), last 9 frames
local MAP_FACTORY, INFERNO_TILE = 410, { 31, 18 }

local watching = false
local events = {}          -- every Ot6Pin call on a monster by a character's Throw or Slow/Stop spell
local stops = {}           -- { f, e, v, pin }: every stop-counter set ($3AF1), by Ot6StopTicks
local applies = {}         -- { f, slot, mark }: every event Ot6EvApply showed
local frames = {}          -- per slot: transitions of the VRAM mark cell and of the live status
local seat = {}            -- entity -> character
local shots = {}           -- the screenshots taken, and the esper GOGO wore

local function ent2slot(e) return (e - 8) // 2 end
-- a monster's turn queued and not yet begun: its command list's head ($32CC) is command $1f (the AI's turn)
local function pendingTurn(e)
  local h = H.readByte(0x32CC + e)
  return h < 0x80 and H.readByte(0x3420 + 2 * h) == 0x1F
end
local stoppedTurns = {}    -- { f, e, after }: ExecAction reached a Stopped monster whose head was a $1f turn
local stoppedNow = nil     -- that monster's entity, until the frame ends
local function markOf(st) if st & STOP ~= 0 then return 2 elseif st & SLOW ~= 0 then return 1 end return 0 end
local function wordMark(w) if w == DAGGER then return 1 elseif w == KNIFE then return 2 end return 0 end

emu.addMemoryCallback(function()
  if not watching then return end
  local s = emu.getState()
  local x, y = s["cpu.x"] & 0xFF, s["cpu.y"] & 0xFF
  if x >= 8 or y < 8 then return end
  local cmd, atk = H.readByte(0xB5), H.readByte(0xB6)
  local kind
  if cmd == 0x08 then kind = "throw"
  elseif cmd == 0x02 and (atk == SPELL_SLOW or atk == SPELL_STOP) then kind = (atk == SPELL_SLOW) and "slow" or "stop"
  elseif cmd == 0x02 and atk == 0x0C then kind = "break"   -- logged, not judged: a Break that hit (a miss never gets here)
  else return end
  local ev = { f = H.frame, kind = kind, x = x, y = y, who = seat[x], pre = H.readByte(0x3EF8 + y),
    broken = H.readByte(0x3E88 + y), allowed = H.readByte(0x3330 + y), species = H.monsterIds()[ent2slot(y) + 1] }
  events[#events + 1] = ev
  if kind == "throw" and ev.who == GOGO then shots.gogoThrew = true end
  if kind == "throw" and ev.who == SHADOW and ev.species == STRIKER then shots.striker = true end
  if kind == "throw" and ev.who == GOGO and ev.pre & SLOW ~= 0 then shots.gogoSlot = ent2slot(y) end
  H.log(string.format("[pin] f%d %s by %s (entity %d) at monster %d ($%03X): status3 $%02X broken %d allowed $%02X",
    ev.f, kind, H.SPLIT_NAMES[ev.who] or "?", x, y, ev.species, ev.pre, ev.broken, ev.allowed))
end, emu.callbackType.exec, PIN, PIN)
-- the rule: what a throw should leave, from the state Ot6Pin found
local function expect(ev)
  if ev.pre & STOP ~= 0 then return "pinned already", ev.pre & (SLOW | STOP) end
  if ev.pre & SLOW == 0 then
    return "hobble", (ev.allowed & SLOW ~= 0) and SLOW or 0
  end
  if ev.broken ~= 0 then return "broken, hobbled already", SLOW end
  if ev.allowed & STOP == 0 then return "stop-immune, hobbled already", SLOW end
  return "pin", STOP
end

emu.addMemoryCallback(function()
  if not watching then return end
  for _, ev in ipairs(events) do
    if ev.post == nil and ev.f < H.frame then
      ev.post = H.readByte(0x3EF8 + ev.y)
      ev.dead = (H.readByte(0x3EE4 + ev.y) & 0xC2) ~= 0
      H.log(string.format("[pin] f%d -> monster %d status3 $%02X after the %s of f%d%s", H.frame, ev.y, ev.post,
        ev.kind, ev.f, ev.dead and " (dead)" or ""))
      -- judged here as well as at the end, so a broken rule fails at the throw that shows it (an error in a
      -- callback fails the run at the next frame) rather than after a battle it may not survive
      if ev.kind == "throw" and not ev.dead then
        local why, want = expect(ev)
        if ev.post & (SLOW | STOP) ~= want then
          error(string.format("the throw of f%d at monster %d: %s, so status3 & $14 should be $%02X; it is $%02X",
            ev.f, ev.y, why, want, ev.post & (SLOW | STOP)))
        end
      end
    end
  end
end, emu.callbackType.exec, FLUSH, FLUSH)
local lastStop = {}
emu.addMemoryCallback(function(addr, v)
  if not watching then return end
  local e = addr - 0x7E3AF1
  if e < 8 or e > 0x12 or (e & 1) == 1 then return end
  local s = emu.getState()
  local pc = (s["cpu.k"] << 16) | s["cpu.pc"]
  if pc >= STOPT and pc < STOPT + 0x20 then
    stops[#stops + 1] = { f = H.frame, e = e, v = v }
    H.log(string.format("[stop] f%d monster %d's Stop lands: %d ticks", H.frame, e, v))
    local last
    for _, ev in ipairs(events) do if ev.y == e then last = ev end end
    if last ~= nil and last.kind == "throw" and v ~= 8 then
      error(string.format("the pin of f%d on monster %d counts %d ticks, not OT6_PIN_TICKS = 8", last.f, e, v))
    end
  end
end, emu.callbackType.write, 0x7E3AF1, 0x7E3B04)
emu.addMemoryCallback(function()
  if not watching then return end
  local x = emu.getState()["cpu.x"] & 0xFFFF
  local off = H.readByte(EVQ + x + 1)
  -- the event's class byte: six class bits, the mark after the hit in bits 6-7 (#566, Ot6EvPush/Ot6EvApply;
  -- bits 4-5 under four classes, where a throw's mark now reads 0 or a class bit)
  applies[#applies + 1] = { f = H.frame, slot = off // 2, mark = (H.readByte(EVQ + x + 4) >> 6) & 3 }
end, emu.callbackType.exec, EVAPPLY, EVAPPLY)
-- the Stop arm: ExecAction meets a Stopped monster with a turn pending; the AI script must not run for it
emu.addMemoryCallback(function() acting = false end, emu.callbackType.exec, ENDACT, ENDACT)
emu.addMemoryCallback(function()
  acting, actStart = true, H.frame
  if not watching then return end
  local x = emu.getState()["cpu.x"] & 0xFF
  if x < 8 or x > 0x12 or H.readByte(0x3EF8 + x) & STOP == 0 or not pendingTurn(x) then return end
  stoppedTurns[#stoppedTurns + 1] = { f = H.frame, e = x }
  stoppedNow = x
  H.log(string.format("[turn] f%d monster %d is Stopped with a turn pending as ExecAction reaches it", H.frame, x))
end, emu.callbackType.exec, EXECACT, EXECACT)
for _, at in ipairs({ EXECAI, RANDAI }) do
  emu.addMemoryCallback(function()
    if not watching then return end
    local x = emu.getState()["cpu.x"] & 0xFF
    if x == stoppedNow then
      error(string.format("f%d: monster %d runs its AI script while Stopped; the turn it had pending should have "
        .. "been consumed (Ot6BrokenTurn's Stop arm)", H.frame, x))
    end
  end, emu.callbackType.exec, at, at)
end
-- frames until monster e's gauge fills, at its rate over the last eight frames (nil: not filling)
local function framesToFill(e)
  local h = gaugeHist[e]
  if h == nil or #h < 9 or h[9] < h[1] then return nil end
  local rate = (h[9] - h[1]) / 8
  if rate <= 0 then return nil end
  return (0x10000 - h[9]) / rate
end
emu.addEventCallback(function()
  if not watching then return end
  for e = 8, 0x12, 2 do
    local h = gaugeHist[e] or {}
    h[#h + 1] = H.readWord(0x3218 + e)
    if #h > 9 then table.remove(h, 1) end
    gaugeHist[e] = h
  end
end, emu.eventType.endFrame)
local pendSince = {}
emu.addEventCallback(function()
  if not watching then return end
  for e = 8, 0x12, 2 do
    local p = pendingTurn(e)
    if p and not pendSince[e] then
      pendSince[e] = H.frame
    elseif not p and pendSince[e] then
      H.log(string.format("[turnq] monster %d had a turn pending f%d-f%d (stopped %s)", e, pendSince[e], H.frame,
        tostring(H.readByte(0x3EF8 + e) & STOP ~= 0)))
      pendSince[e] = nil
    end
  end
end, emu.eventType.endFrame)
-- ExecAction's next call after Ot6BrokenTurn: the Stopped monster's list must be empty by now
emu.addMemoryCallback(function()
  if stoppedNow == nil then return end
  local t = stoppedTurns[#stoppedTurns]
  t.after = H.readByte(0x32CC + stoppedNow)
  H.log(string.format("[turn] f%d monster %d's command list after Ot6BrokenTurn: head $%02X", H.frame, stoppedNow,
    t.after))
  if t.after ~= 0xFF then
    error(string.format("f%d: monster %d is Stopped and its pending turn was not consumed (list head $%02X)",
      H.frame, stoppedNow, t.after))
  end
  stoppedNow = nil
end, emu.callbackType.exec, NOACT, NOACT)
local function vramMark(l)
  local cur = H.readWord(SHADOWL + l * 14)
  if cur == 0 or (cur & 0x1F) < 2 then return nil end
  return wordMark(emu.readWord((cur - 2) * 2, emu.memType.snesVideoRam))
end
emu.addEventCallback(function()
  if not watching then return end
  local alive = H.readByte(0x3A75)
  for l = 0, 5 do
    if (alive >> l) & 1 == 1 then
      frames[l] = frames[l] or { vram = {}, live = {} }
      local fr = frames[l]
      local v, live = vramMark(l), markOf(H.readByte(0x3EF8 + 8 + 2 * l))
      if v ~= nil and v ~= fr.lastV then fr.vram[#fr.vram + 1] = { f = H.frame, m = v }; fr.lastV = v end
      if live ~= fr.lastL then fr.live[#fr.live + 1] = { f = H.frame, m = live }; fr.lastL = live end
    end
  end
end, emu.eventType.endFrame)

local slotOf = {}
local snapBattle, reqBattle    -- the snapshot at the battle's open, and a restore of it
local function armState(sp)
  local s = slotOf[sp]
  if s == nil or (H.readByte(0x3A75) >> s) & 1 == 0 then return nil end
  return s, H.readByte(0x3EF8 + 8 + 2 * s)
end
-- the free arm (neither Slowed nor Stopped), else nil
local function freeArm()
  for _, sp in ipairs({ ROUGH, STRIKER }) do
    local s, st = armState(sp)
    if s and st & (SLOW | STOP) == 0 then return s end
  end
end
-- the arm the Slow spell slowed (Slowed, not Stopped)
local function slowedArm()
  for _, sp in ipairs({ ROUGH, STRIKER }) do
    local s, st = armState(sp)
    if s and st & SLOW ~= 0 and st & STOP == 0 then return s end
  end
end
local function unstoppedArm()
  for _, sp in ipairs({ STRIKER, ROUGH }) do
    local s, st = armState(sp)
    if s and st & STOP == 0 then return s end
  end
  return slotOf[STRIKER] or slotOf[ROUGH]
end
-- a Stop spell has landed (its 18 ticks), and a Stop has met a pending turn
local function stopSpellSeen()
  for _, ev in ipairs(events) do
    if ev.kind == "stop" and ev.post ~= nil and ev.pre & STOP == 0 and ev.post & STOP ~= 0 then return true end
  end
  return false
end

-- Striker standing, and not Stopped; and whether a throw has found a Broken, hobbled body yet
local function strikerUp() return armState(STRIKER) end
local function strikerBroken()
  local s, st = armState(STRIKER)
  return s ~= nil and st & STOP == 0 and st & SLOW ~= 0 and H.readByte(0x3E88 + 8 + 2 * s) > 2
    and (events[#events] == nil or events[#events].post ~= nil)
end
local function brokenCaseSeen()
  for _, ev in ipairs(events) do
    if ev.kind == "throw" and ev.post ~= nil and not ev.dead and ev.broken ~= 0 and ev.pre & SLOW ~= 0
       and ev.pre & STOP == 0 then return true end
  end
  return false
end

local KNIFE_ITEM = 0x01           -- Mithril Knife: the bag holds a stack of them
local SPELL_BREAK = 0x0C
-- a hold that gives up after 2400 frames (about two of SHADOW's turns twice over): a gate the rule should open
-- (an arm hobbled, a body free) that never opens plays the entry anyway, so a broken rule fails on the
-- judgement below rather than stalling the battle into a wipe
local function patient(fn, what, budget)
  local t0, told
  budget = budget or 2400
  return function()
    if fn() then return true end
    t0 = t0 or H.frame
    if H.frame - t0 > budget then
      if not told then told = true; H.log(string.format("[shadowpin] f%d %s: waited %d frames, played anyway", H.frame, what or "a gate", budget)) end
      return true
    end
    return false
  end
end
-- The battle is played in groups, each from a snapshot at the battle's open, so the party meets each property
-- whole rather than after a long stretch of Defending against Inferno (the suite's first form, one plan, lost
-- the battle on most seed shifts).  A group is tried until its properties are seen (up to `tries`, each try
-- going back to the open and pausing there 97 frames longer than the try before, so it plays out differently;
-- a try that runs out its frames is logged and dropped, its unresolved events with it).
-- Group 1, the opening: 1. SHADOW hobbles Rough; 2. GOGO's Mimic of that throw pins it (no care window between
-- them: a Potion queued there would be the action Mimic copies).  GOGO holds his window until the hobble has
-- landed and is the action Mimic would copy (SaveForMimic's command, $3F20, a Throw), and then until Rough is
-- about to take a turn (below), so the pin can land while Rough's turn is pending: the Stop arm's case.  The try
-- plays on until the pin wears off.
-- Rough's turn must come up in the last few frames before GOGO's Mimic resolves: then it waits behind the
-- Mimic, which is already in the action queue, and the pin lands on it pending.  GOGO, his command window held
-- open, chooses Mimic when Rough's gauge will fill (at its rate over the last eight
-- frames) lagEst - 8 + offset frames from now, lagEst being the frames from that moment to the Mimic's
-- resolution as the last try measured it (150 before any); the offsets walk the window either side.
local OFFSETS = { 0, -6, 6, -12, 12, -18, 18, -24, 24, -30, 30, 36 }
local DELAYS = #OFFSETS
local lagEst, gateAt = 150, nil
local try = 1
local branchStart = 0
-- the pin of event ev has worn off at least 30 frames ago (its knife's clearing is then on record)
local function pinOver(ev)
  if ev == nil or H.readByte(0x3EF8 + ev.y) & STOP ~= 0 then return false end
  local fr = frames[ent2slot(ev.y)]
  local last = fr and fr.live[#fr.live]
  return last ~= nil and last.m ~= 2 and last.m ~= -1 and H.frame - last.f >= 30
end
local function gogoPinned()
  for _, ev in ipairs(events) do
    if ev.kind == "throw" and ev.who == GOGO and ev.post ~= nil and ev.post & STOP ~= 0 and ev.f >= branchStart then
      return ev
    end
  end
end
local G1 = {
  name = "1. the opening", tries = DELAYS, limit = 9000,
  plan = function(i)
    local off, fired = OFFSETS[i], false
    return {
      { who = SHADOW, cmd = 0x08, row = KNIFE_ITEM, boost = 0, slotFn = function() return slotOf[ROUGH] end },
      { who = GOGO, cmd = 0x12, boost = 0, self = true, hold = true, when = patient(function()
          if fired then return true end   -- latched: the Mimic takes some frames of presses to choose
          local e = events[#events]
          local r = slotOf[ROUGH] and 8 + 2 * slotOf[ROUGH]
          if not (e ~= nil and e.kind == "throw" and e.who == SHADOW and e.post ~= nil and e.pre & SLOW == 0
            and e.post & SLOW ~= 0 and H.readByte(0x3F20) == 0x08) then return false end
          -- GOGO's own command window up, held (the battle runs on meanwhile)
          if H.readByte(0x7BCA) == 0 or H.readByte(0x7BC2) ~= 0x05
             or H.readByte(0x3ED8 + 2 * (H.readByte(0x62CA) & 3)) ~= GOGO then return false end
          -- (an action executing is allowed: on v0.49's line (build/attempts/wt/v049-land/) one was running at
          -- nearly every frame of GOGO's held window (lab/shadowpin_diag.log.gz: "acting true" at every 20-frame sample but two), gate 3's twelve
          -- tries fired the gate once and met no pending turn (gate3/suite_battle_shadowpin.log); the Mimic then
          -- queues behind it, and lagEst, measured per try, takes the queue in)
          if r == nil or pendingTurn(r) then return false end
          local ttf = framesToFill(r)
          if ttf == nil or math.abs(ttf - (lagEst - 8 + off)) > 3 then return false end
          gateAt, fired = H.frame, true
          H.log(string.format("[shadowpin] try %d: GOGO goes with Rough %.0f frames from its turn (the Mimic's lag "
            .. "%d, offset %d)", i, ttf, lagEst, off))
          return true
        end, string.format("2. the throw to Mimic, offset %d", off), 3000) },
    }
  end,
  -- the case seen, and the pin has worn off (its knife's clearing is judged)
  done = function() return #stoppedTurns >= 1 and pinOver(gogoPinned()) end,
  -- this try is over: GOGO's pin has worn off
  over = function() return pinOver(gogoPinned()) end,
  care = function() return shots.gogoThrew == true or H.frame - branchStart > 3000 end,
}
-- Group 2: 3. SHADOW casts Slow on Striker; 4. SABIN's Break, boosted two points, takes its three shields
-- (OT6's Break: no damage, no status); 5. SHADOW throws at the Broken, Slowed Striker: it stays hobbled, never
-- pinned (one knife: a Broken body takes double, and the arms die to a few)
local G2 = {
  name = "2. the broken arm", tries = 6, limit = 8000,
  plan = function()
    return {
      { who = SHADOW, cmd = 0x02, spell = SPELL_SLOW, boost = 0, slotFn = strikerUp },
      { who = SABIN, cmd = 0x02, spell = SPELL_BREAK, boost = 2, slotFn = strikerUp, hold = true,
        when = patient(function() local _, st = armState(STRIKER); return st ~= nil and st & SLOW ~= 0 end,
          "4. Striker slowed") },
      { who = SHADOW, cmd = 0x08, row = KNIFE_ITEM, boost = 0, hold = true, slotFn = strikerUp,
        when = patient(strikerBroken, "5. Striker broken") },
    }
  end,
  done = function() return brokenCaseSeen() end,
  over = function() return brokenCaseSeen() end,
}
-- Group 3: 6. SHADOW casts Slow on a free arm; 7. one throw pins it; 8. CYAN casts Stop on the other arm:
-- vanilla's 18 ticks.  The try plays on until the throw's pin wears off.
local function spellPin()
  local by = {}
  for _, ev in ipairs(events) do
    if ev.post ~= nil and not ev.dead and ev.f >= branchStart then
      if ev.kind == "slow" and ev.post & SLOW ~= 0 then by[ev.y] = "slow"
      elseif ev.kind == "throw" then
        if ev.pre & STOP == 0 and ev.pre & SLOW ~= 0 and ev.post & STOP ~= 0 and by[ev.y] == "slow" then return ev end
        if ev.post & SLOW ~= 0 and ev.pre & SLOW == 0 then by[ev.y] = "throw" end
        if ev.post & STOP ~= 0 then by[ev.y] = nil end
      end
    end
  end
end
local G3 = {
  name = "3. a spell's hobble pinned, and Stop the spell", tries = 4, limit = 9000,
  plan = function()
    return {
      { who = SHADOW, cmd = 0x02, spell = SPELL_SLOW, boost = 0, hold = true, slotFn = freeArm,
        when = patient(function() return freeArm() ~= nil end, "6. a free arm") },
      { who = SHADOW, cmd = 0x08, row = KNIFE_ITEM, boost = 0, slotFn = slowedArm },
      { who = CYAN, cmd = 0x02, spell = SPELL_STOP, boost = 0, slotFn = unstoppedArm },
    }
  end,
  done = function() return stopSpellSeen() and pinOver(spellPin()) end,
  over = function()
    local ev = spellPin()
    if ev ~= nil and not pinOver(ev) then return false end
    for _, e in ipairs(events) do if e.post == nil then return false end end
    local n = 0
    for _, e in ipairs(events) do if e.f >= branchStart then n = n + 1 end end
    return n >= 3
  end,
}
-- Group 4: 9. 10. SHADOW throws at Inferno twice: hobbled, then still hobbled (Stop-immune)
local function infernoThrows()
  local n = 0
  for _, ev in ipairs(events) do
    if ev.kind == "throw" and ev.species == INFERNO and ev.post ~= nil and ev.f >= branchStart then n = n + 1 end
  end
  return n
end
local G4 = {
  name = "4. Inferno", tries = 3, limit = 6000,
  plan = function()
    return {
      { who = SHADOW, cmd = 0x08, row = KNIFE_ITEM, boost = 0, slotFn = function() return slotOf[INFERNO] end },
      { who = SHADOW, cmd = 0x08, row = KNIFE_ITEM, boost = 0, slotFn = function() return slotOf[INFERNO] end },
    }
  end,
  done = function() return infernoThrows() >= 2 end,
  over = function() return infernoThrows() >= 2 end,
}
emu.addEventCallback(function()
  if not watching then return end
  for l = 0, 5 do
    local m = vramMark(l)
    if m == 1 and not shots.dagger then shots.dagger = true; H.screenshot("shadowpin_dagger") end
    if m == 2 and not shots.knife then shots.knife = true; H.screenshot("shadowpin_knife") end
  end
  if shots.gogoSlot and not shots.gogo and vramMark(shots.gogoSlot) == 2 then
    shots.gogo = true; H.screenshot("shadowpin_gogo")
  end
end, emu.eventType.endFrame)

H.NAV_REFIRE_HOLD = true
H.careThreshold = 1.0
local K = H.worLegKit({ fight = {}, links = {}, names = H.SPLIT_NAMES })
H.run({ maxFrames = 1200000, retries = 4 }, {
  H.bootCheckpoint("wor-kt-factory-v1"),
  H.call(function()
    H.assertEq(H.activeParty(), 3, "party 3 walks (gen_wor_kt_factory left it on the factory's save point)")
    for _, c in ipairs({ CYAN, SHADOW, SABIN, GOGO }) do
      H.assertEq(H.readByte(0x1850 + c) & 7, 3, string.format("%s is in party 3", H.SPLIT_NAMES[c]))
    end
    -- the magicite that teaches Slow (for SHADOW) and the one that teaches Stop (for CYAN), owned and worn by
    -- nobody outside party 3, read from the ROM's GenjuProp (spell ids at +1, +3 .. +9)
    local g = H.sym("GenjuProp") & 0x3FFFFF
    local function teaches(e, sp)
      for _, o in ipairs({ 1, 3, 5, 7, 9 }) do if H.readRomByte(g + 11 * e + o) == sp then return true end end
    end
    local function usable(e)
      if (H.readByte(0x1A69 + (e >> 3)) >> (e & 7)) & 1 == 0 then return false end
      for c = 0, 13 do
        if H.readByte(0x1600 + 37 * c + 0x1E) == e and (H.readByte(0x1850 + c) & 7) ~= 3 then return false end
      end
      return true
    end
    for e = 0, 26 do
      if shots.slowEsper == nil and teaches(e, SPELL_SLOW) and usable(e) then shots.slowEsper = e end
      if shots.stopEsper == nil and teaches(e, SPELL_STOP) and usable(e) and e ~= shots.slowEsper then
        shots.stopEsper = e
      end
      if shots.breakEsper == nil and teaches(e, 0x0C) and usable(e) and e ~= shots.slowEsper
         and e ~= shots.stopEsper then shots.breakEsper = e end
    end
    H.log(string.format("[shadowpin] magicite for Slow %s, for Stop %s", tostring(shots.slowEsper),
      tostring(shots.stopEsper)))
    H.assertEq(shots.slowEsper ~= nil and shots.stopEsper ~= nil and shots.breakEsper ~= nil, true,
      "the party owns magicite teaching Slow, Stop and Break that party 3 may wear")
    H.assertEq(H.invCountOf(KNIFE_ITEM) >= 2, true, string.format("the bag holds two Mithril Knives to throw (%d): "
      .. "a group throws two at most, and every group starts from the battle's open", H.invCountOf(KNIFE_ITEM)))
    H.log(string.format("[shadowpin] the bag: %d Softs, %d Fenix Downs, %d Potions for the others' care",
      H.invCountOf(0xF4), H.invCountOf(0xF0), H.invCountOf(0xE9)))
  end),
  H.lazy(function()
    return H.equipEsper(function() return (H.readByte(0x1850 + SHADOW) >> 3) & 3 end, shots.slowEsper,
      { tag = "the Slow magicite -> SHADOW" })
  end),
  H.lazy(function()
    return H.equipEsper(function() return (H.readByte(0x1850 + CYAN) >> 3) & 3 end, shots.stopEsper,
      { tag = "the Stop magicite -> CYAN" })
  end),
  H.lazy(function()
    return H.equipEsper(function() return (H.readByte(0x1850 + SABIN) >> 3) & 3 end, shots.breakEsper,
      { tag = "the Break magicite -> SABIN" })
  end),
  H.call(function()
    H.assertEq(H.knowsSpell(SABIN, 0x0C), true, "SABIN can cast Break")
    H.assertEq(H.knowsSpell(SHADOW, SPELL_SLOW), true, "SHADOW can cast Slow (the magicite he now wears)")
    H.assertEq(H.knowsSpell(CYAN, SPELL_STOP), true, "CYAN can cast Stop")
  end),
  H.splitBegin({ shares = { [1] = 1, [2] = 1, [3] = 2 } }),
  H.absorbSafeArms(nil, { INFERNO, STRIKER, ROUGH }, { tag = "arms for Inferno" }),
  H.fieldCare({ threshold = 1.0, tag = "before Inferno" }),
  H.navTo(INFERNO_TILE[1], INFERNO_TILE[2], { maxFrames = 6000, playBattles = "tactical", fight = {},
    spare = { INFERNO },
    arrive = function()
      return (H.battleLoadStarted() and H.formationHas({ [INFERNO] = true }))
        or (H.fieldX() == INFERNO_TILE[1] and H.fieldY() == INFERNO_TILE[2])
    end }),
  H.waitUntil(function() return H.battleLoadStarted() and H.formationHas({ [INFERNO] = true }) end, 3000,
    "Inferno's battle"),
  H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 2),
  H.call(function()
    local ids = H.monsterIds()
    for s = 1, 6 do if ids[s] ~= 0xFFFF then slotOf[ids[s]] = s - 1 end end
    for s = 0, 3 do seat[2 * s] = H.readByte(0x3ED8 + 2 * s) end
    H.log(string.format("[shadowpin] formation $%03X: Inferno slot %s, Rough %s, Striker %s", H.readWord(0x11E0),
      tostring(slotOf[INFERNO]), tostring(slotOf[ROUGH]), tostring(slotOf[STRIKER])))
    H.assertEq(slotOf[INFERNO] ~= nil and slotOf[ROUGH] ~= nil and slotOf[STRIKER] ~= nil, true,
      "Inferno and both arms are on the field")
    watching = true
    snapBattle = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snapBattle, "the snapshot at the battle's open") end),
  H.lazy(function()
    local steps = {}
    local first = true
    for _, G in ipairs({ G1, G2, G3, G4 }) do
      for i = 1, G.tries do
        local restore = not first
        first = false
        steps[#steps + 1] = H.cond(function() return not G.done() end, {
          H.call(function()
            if not restore then return end
            -- back to the battle's open: an event the try left unresolved goes with it, and the marks' and
            -- statuses' histories get a break so nothing pairs across it
            local kept = {}
            for _, ev in ipairs(events) do if ev.post ~= nil then kept[#kept + 1] = ev end end
            events = kept
            for _, fr in pairs(frames) do
              fr.lastV, fr.lastL = nil, nil
              fr.vram[#fr.vram + 1] = { f = H.frame, m = -1 }
              fr.live[#fr.live + 1] = { f = H.frame, m = -1 }
            end
            stoppedNow, acting, pendSince, gaugeHist, gateAt = nil, false, {}, {}, nil
            shots.gogoThrew = nil
            H.setPad({})
            reqBattle = H.requestLoadState(snapBattle.blob)
          end),
          H.waitFrames(2),
          H.call(function()
            if restore then H.checkReq(reqBattle, "the battle's open"); H.rearmInputInjection() end
            try, branchStart = i, H.frame
            H.log(string.format("[shadowpin] group %s, try %d of %d, from the battle's open", G.name, i, G.tries))
          end),
          -- each try after the first waits a little longer at the open, touching nothing (a player's pause):
          -- the same snapshot and the same presses would play the same battle again
          H.lazy(function()
            H.setPad({})
            return H.waitFrames(1 + (i - 1) * 97)
          end),
          H.lazy(function()
            branchStart = H.frame
            return H.kitBattle(G.plan(i), { maxFrames = G.limit + 2000, untilPlanDone = true, idle = "defend",
              cureAllies = true, planDone = G.over, care = G.care,
              giveUp = function()
                if H.frame - branchStart <= G.limit then return false end
                H.log(string.format("[shadowpin] group %s, try %d: %d frames without its properties; dropped",
                  G.name, i, G.limit))
                return true
              end })
          end),
          H.call(function()
            if G == G1 and gateAt ~= nil then
              for _, ev in ipairs(events) do
                if ev.kind == "throw" and ev.who == GOGO and ev.f >= gateAt then
                  H.log(string.format("[shadowpin] try %d: the Mimic resolved %d frames after GOGO's window went", i,
                    ev.f - gateAt))
                  lagEst = ev.f - gateAt
                  break
                end
              end
              gateAt = nil
            end
            H.log(string.format("[shadowpin] group %s, try %d: %s; Stops met with a turn pending so far %d", G.name, i,
              G.done() and "seen" or "not seen", #stoppedTurns))
          end),
        }, {})
      end
    end
    return H.seqStep(steps)
  end),
  H.call(function()
    watching = false
    -- every throw, by the rule
    local seen = {}
    local hobbledBy = {}       -- target -> the event that last Slowed it
    for i, ev in ipairs(events) do
      if ev.kind == "throw" and not ev.dead and ev.post ~= nil then
        local why, want = expect(ev)
        H.assertEq(ev.post & (SLOW | STOP), want, string.format("throw %d (f%d) by %s at monster %d ($%03X): %s",
          i, ev.f, H.SPLIT_NAMES[ev.who] or "?", ev.y, ev.species, why))
        seen[why] = (seen[why] or 0) + 1
        if why == "pin" then
          local src = hobbledBy[ev.y]
          ev.src = src
          if ev.who == GOGO and src and src.kind == "throw" and src.who == SHADOW then seen.gogo = ev end
          if src and src.kind == "slow" then seen.spellpin = ev end
          -- its Stop counter: the pin's 8
          local st
          for _, s in ipairs(stops) do if s.e == ev.y and s.f >= ev.f and st == nil then st = s end end
          H.assertEq(st ~= nil and st.v, 8, string.format("throw %d's pin counts 8 ticks", i))
          hobbledBy[ev.y] = nil
        elseif why == "hobble" and ev.post & SLOW ~= 0 then
          hobbledBy[ev.y] = ev
          if ev.species == INFERNO then seen.infernoHobble = ev end
        elseif why == "stop-immune, hobbled already" then
          seen.immune = ev
        end
      elseif (ev.kind == "slow" or ev.kind == "stop") and ev.post ~= nil then
        if ev.kind == "slow" and ev.post & SLOW ~= 0 then hobbledBy[ev.y] = ev end
        if ev.kind == "stop" and ev.pre & STOP == 0 and ev.post & STOP ~= 0 then   -- a Stop spell that landed
          local st
          for _, s in ipairs(stops) do if s.e == ev.y and s.f >= ev.f and st == nil then st = s end end
          H.assertEq(st ~= nil and st.v, 18, "Stop the spell counts vanilla's 18 ticks")
          seen.vanillaStop = true
        end
      end
    end
    H.assertEq((seen.hobble or 0) >= 2, true, "1. 9. a first throw hobbles (two or more seen)")
    H.assertEq((seen.pin or 0) >= 2, true, "2. 7. a throw at a hobbled arm pins it, the hobble used up (two or more)")
    H.assertEq(seen.gogo ~= nil, true, "2. SHADOW's throw hobbles, GOGO's Mimic of it pins")
    H.assertEq(seen.spellpin ~= nil, true, "7. a Slow spell, then one throw, pins")
    H.assertEq(seen.vanillaStop, true, "8. a Stop spell keeps vanilla's 18 ticks")
    H.assertEq(seen.infernoHobble ~= nil, true, "9. a throw hobbles Inferno")
    H.assertEq(seen.immune ~= nil and seen.immune.species == INFERNO, true,
      "10. the throw at the hobbled, Stop-immune Inferno leaves him hobbled, not pinned")
    H.assertEq((seen["broken, hobbled already"] or 0) >= 1, true,
      "5. a throw at a Broken, hobbled arm leaves it hobbled, never pinned")
    H.log(string.format("[shadowpin] throws judged: hobble %d, pin %d, broken %d, pinned already %d, immune %d",
      seen.hobble or 0, seen.pin or 0, seen["broken, hobbled already"] or 0, seen["pinned already"] or 0,
      seen["stop-immune, hobbled already"] or 0))

    -- the marks: each hobble's and pin's mark shows with its hit's numeral, not before; each pin's clears with
    -- its Stop
    local judged = 0
    for i, ev in ipairs(events) do
      if ev.kind == "throw" and not ev.dead and ev.post ~= nil and ev.pre & STOP == 0
         and markOf(ev.post) ~= markOf(ev.pre) then
        local l, m = ent2slot(ev.y), markOf(ev.post)
        local fr = frames[l]
        local tLive, tShow, tEv
        for _, t in ipairs(fr.live) do if t.f >= ev.f and t.m == m and tLive == nil then tLive = t.f end end
        for _, t in ipairs(fr.vram) do if t.f >= ev.f and t.m == m and tShow == nil then tShow = t.f end end
        for _, a in ipairs(applies) do if a.f >= ev.f and a.slot == l and a.mark == m and tEv == nil then tEv = a.f end end
        H.log(string.format("[mark] throw %d at slot %d: the status at f%s, its numeral's event at f%s, the mark in "
          .. "vram at f%s", i, l, tostring(tLive), tostring(tEv), tostring(tShow)))
        H.assertEq(tLive ~= nil and tEv ~= nil and tShow ~= nil, true,
          string.format("throw %d: the status, the numeral and the mark are all seen", i))
        H.assertEq(tShow >= tEv and tShow <= tEv + 3, true,
          string.format("throw %d: the mark appears with the numeral (f%d, the numeral f%d), not with the status (f%d)",
            i, tShow, tEv, tLive))
        H.assertEq(tEv > tLive, true, string.format("throw %d: the status was computed before its numeral showed", i))
        judged = judged + 1
      end
    end
    H.assertEq(judged >= 4, true, string.format("the marks of four or more throws judged (%d)", judged))
    local cleared = 0
    for l, fr in pairs(frames) do
      for k, t in ipairs(fr.live) do
        local prev = fr.live[k - 1]
        if prev and prev.m == 2 and t.m == 0 then
          local tShow
          for _, v in ipairs(fr.vram) do if v.f >= t.f and v.m == 0 and tShow == nil then tShow = v.f end end
          H.log(string.format("[mark] slot %d's Stop ended at f%d; the knife went at f%s", l, t.f, tostring(tShow)))
          -- (within 6 frames: the line builder runs on the battle loop's WaitFrame, the flush on the nmi after)
          H.assertEq(tShow ~= nil and tShow <= t.f + 6, true,
            string.format("slot %d: the knife clears when the Stop ends", l))
          cleared = cleared + 1
        end
      end
    end
    H.assertEq(cleared >= 2, true, string.format("two or more pins wore off and their knives cleared (%d)", cleared))
    -- the Stop arm: each case was judged as it happened (no AI script, the list empty); one or more must be seen
    H.log(string.format("[shadowpin] Stopped monsters met with a turn pending: %d", #stoppedTurns))
    H.assertEq(#stoppedTurns >= 1, true,
      "a Stop landed on a monster with a turn pending, and the turn was consumed (Ot6BrokenTurn's Stop arm)")
    H.log("[shadowpin] PASS: throws hobble and pin by the rule; Gogo's Mimic pins; the marks land with the hit")
  end),
})
