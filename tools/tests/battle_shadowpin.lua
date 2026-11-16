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
-- tactical driver).  In Inferno's battle the plan, through the real menu (H.kitBattle; the others Defend):
--   1. SHADOW casts Slow on Striker.   2. SABIN's Break (two points: three shields, no damage) breaks it.
--   3. SHADOW throws at the Broken, Slowed Striker: it stays hobbled, never pinned.
--   4. SHADOW throws at Rough: hobbled.            5. GOGO Mimics it: Rough pinned (Shadow hobbles, Gogo pins).
--   6. SHADOW casts Slow on a free arm.            7. SHADOW throws at it: pinned by one throw.
--   8. CYAN casts Stop on an arm: 18 ticks, vanilla's.
--   9. 10. SHADOW throws at Inferno twice: hobbled, then still hobbled (Stop-immune), never Stopped.
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
local MAP_FACTORY, INFERNO_TILE = 410, { 31, 18 }

local watching = false
local events = {}          -- every Ot6Pin call on a monster by a character's Throw or Slow/Stop spell
local stops = {}           -- { f, e, v, pin }: every stop-counter set ($3AF1), by Ot6StopTicks
local applies = {}         -- { f, slot, mark }: every event Ot6EvApply showed
local frames = {}          -- per slot: transitions of the VRAM mark cell and of the live status
local seat = {}            -- entity -> character
local shots = {}           -- the screenshots taken, and the esper GOGO wore

local function ent2slot(e) return (e - 8) // 2 end
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
emu.addMemoryCallback(function()
  if not watching then return end
  for _, ev in ipairs(events) do
    if ev.post == nil and ev.f < H.frame then
      ev.post = H.readByte(0x3EF8 + ev.y)
      ev.dead = (H.readByte(0x3EE4 + ev.y) & 0xC2) ~= 0
      H.log(string.format("[pin] f%d -> monster %d status3 $%02X after the %s of f%d%s", H.frame, ev.y, ev.post,
        ev.kind, ev.f, ev.dead and " (dead)" or ""))
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
  end
end, emu.callbackType.write, 0x7E3AF1, 0x7E3B04)
emu.addMemoryCallback(function()
  if not watching then return end
  local x = emu.getState()["cpu.x"] & 0xFFFF
  local off = H.readByte(EVQ + x + 1)
  applies[#applies + 1] = { f = H.frame, slot = off // 2, mark = (H.readByte(EVQ + x + 4) >> 4) & 3 }
end, emu.callbackType.exec, EVAPPLY, EVAPPLY)
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
local function patient(fn)
  local t0
  return function()
    if fn() then return true end
    t0 = t0 or H.frame
    return H.frame - t0 > 2400
  end
end
local plan = {
  -- 1. SHADOW casts Slow on Striker; 2. SABIN's Break, boosted two points, takes its three shields (OT6's
  -- Break: no damage, no status); 3. SHADOW throws at the Broken, Slowed Striker: it stays hobbled, never pinned
  -- (one knife: a Broken body takes double, and the arms die to a few)
  { who = SHADOW, cmd = 0x02, spell = SPELL_SLOW, boost = 0, slotFn = strikerUp },
  { who = SABIN, cmd = 0x02, spell = SPELL_BREAK, boost = 2, slotFn = strikerUp, hold = true,
    when = patient(function() local _, st = armState(STRIKER); return st ~= nil and st & SLOW ~= 0 end) },
  { who = SHADOW, cmd = 0x08, row = KNIFE_ITEM, boost = 0, hold = true, slotFn = strikerUp,
    when = patient(strikerBroken) },
  -- 4. SHADOW hobbles Rough; 6. GOGO's Mimic of that throw pins it.  GOGO holds his window until the hobble has
  -- landed and is the action Mimic would copy (SaveForMimic's command, $3F20, a Throw)
  { who = SHADOW, cmd = 0x08, row = KNIFE_ITEM, boost = 0, slotFn = function() return slotOf[ROUGH] end },
  { who = GOGO, cmd = 0x12, boost = 0, self = true, hold = true, when = patient(function()
      local e = events[#events]
      return e ~= nil and e.kind == "throw" and e.who == SHADOW and e.post ~= nil and e.pre & SLOW == 0
        and e.post & SLOW ~= 0 and H.readByte(0x3F20) == 0x08
    end) },
  -- 6. SHADOW casts Slow on a free arm; 7. one throw pins it
  { who = SHADOW, cmd = 0x02, spell = SPELL_SLOW, boost = 0, hold = true, slotFn = freeArm,
    when = patient(function() return freeArm() ~= nil end) },
  { who = SHADOW, cmd = 0x08, row = KNIFE_ITEM, boost = 0, slotFn = slowedArm },
  -- 8. CYAN casts Stop on an arm: vanilla's 18 ticks
  { who = CYAN, cmd = 0x02, spell = SPELL_STOP, boost = 0, slotFn = unstoppedArm },
  -- 9. 10. SHADOW throws at Inferno twice: hobbled, then still hobbled (Stop-immune)
  { who = SHADOW, cmd = 0x08, row = KNIFE_ITEM, boost = 0, slotFn = function() return slotOf[INFERNO] end },
  { who = SHADOW, cmd = 0x08, row = KNIFE_ITEM, boost = 0, slotFn = function() return slotOf[INFERNO] end },
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

H.NAV_REFIRE_HOLD = true
H.careThreshold = 1.0
local K = H.worLegKit({ fight = {}, links = {}, names = H.SPLIT_NAMES })
H.run({ maxFrames = 1200000 }, {
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
    H.assertEq(H.invCountOf(KNIFE_ITEM) >= 7, true, "the bag holds seven Mithril Knives to throw")
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
  end),
  -- no care window from SHADOW's hobble on Rough (entry 4) until GOGO's Mimic has thrown: a Potion queued
  -- between them would be the action Mimic copies
  -- the step ends once the plan is spent and its last throw, the second at Inferno, has landed; until then
  -- the others (and SHADOW, once his entries are played) Defend, so the battle runs on
  H.kitBattle(plan, { maxFrames = 200000, untilPlanDone = true, idle = "defend",
    planDone = function()
      local inferno = 0
      for _, ev in ipairs(events) do
        if ev.post == nil then return false end
        if ev.kind == "throw" and ev.species == INFERNO then inferno = inferno + 1 end
      end
      return inferno >= 2
    end,
    care = function()
      if shots.gogoThrew or (shots.careT0 and H.frame - shots.careT0 > 2400) then return true end
      shots.careT0 = shots.careT0 or ((function()
        for _, r in ipairs(H.vars.kit or {}) do if r.entry >= 4 then return H.frame end end
      end)())
      for _, r in ipairs(H.vars.kit or {}) do if r.entry >= 4 then return false end end
      return true
    end }),
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
        if ev.kind == "stop" then
          local st
          for _, s in ipairs(stops) do if s.e == ev.y and s.f >= ev.f and st == nil then st = s end end
          H.assertEq(st ~= nil and st.v, 18, "Stop the spell counts vanilla's 18 ticks")
          seen.vanillaStop = true
        end
      end
    end
    H.assertEq((seen.hobble or 0) >= 2, true, "4. 9. a first throw hobbles (two or more seen)")
    H.assertEq((seen.pin or 0) >= 2, true, "5. 7. a throw at a hobbled arm pins it, the hobble used up (two or more)")
    H.assertEq(seen.gogo ~= nil, true, "5. SHADOW's throw hobbles, GOGO's Mimic of it pins")
    H.assertEq(seen.spellpin ~= nil, true, "7. a Slow spell, then one throw, pins")
    H.assertEq(seen.vanillaStop, true, "8. a Stop spell keeps vanilla's 18 ticks")
    H.assertEq(seen.infernoHobble ~= nil, true, "9. a throw hobbles Inferno")
    H.assertEq(seen.immune ~= nil and seen.immune.species == INFERNO, true,
      "10. the throw at the hobbled, Stop-immune Inferno leaves him hobbled, not pinned")
    H.assertEq((seen["broken, hobbled already"] or 0) >= 1, true,
      "3. a throw at a Broken, hobbled arm leaves it hobbled, never pinned")
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
    H.log("[shadowpin] PASS: throws hobble and pin by the rule; Gogo's Mimic pins; the marks land with the hit")
  end),
})
