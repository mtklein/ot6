-- PROBE (not a test, no @suite marker): can a BROKEN monster still act?
--
-- Owner report from live play of Ifrit & Shiva (battle 70, map 264),
-- 2026-07-30: "is it possible that I saw Ifrit attack while broken? or
-- possibly that his shields didn't return after the broken turn?"
--
-- Ot6Gate (ot6_break.asm:1655) is consulted in exactly ONE place --
-- battle_main.asm:1416, inside "add pending action to queue"
-- (_countercheck).  Everything downstream of a queue entry is ungated:
--
--   A1  the ACTION queue.  battle_main.asm:150-159 pulls the entity out of
--       $3820 and jumps to ExecAction with no status re-check; the only
--       code that ever purges a queued action is QuetzEffect
--       (battle_main.asm:1809-1817).  A break landing AFTER the queue entry
--       exists should therefore not stop the action.
--   A2  the COUNTERATTACK queue.  CreateRetalAction (battle_main.asm:13114)
--       writes $3920 through _c24e84 with no gate at all, and ExecRetal
--       (battle_main.asm:12602) re-checks nothing.  Ifrit's retaliation
--       script is `if_hit: add_battle_var 3,1 / attack NOTHING,NOTHING,FIRE`
--       (ai_script.asm:4657-4660), so hits on him answer with Fire -- which
--       is exactly what "Ifrit attacked while broken" looks like from the
--       couch.  A2 needs no race at all: it is the ordinary case.
--
-- THE DETECTOR AND ITS POSITIVE CONTROL.  A previous cut of this probe
-- used $3406 as the "currently acting entity" witness and measured zero.
-- $3406 is the WRONG witness: ExecAction's first instruction is
-- `sec / ror $3406` (battle_main.asm:210-211), which sets bit 7 -- the
-- "no valid resume" marker -- and $3406 only receives the real entity at
-- :305, on the multi-action path.  A single-action monster turn never
-- writes it.  That measurement was a check that passed without running.
--
-- This one hooks the code instead: exec callbacks on ExecAction, ExecRetal
-- and ExecCmd, reading the entity out of cpu.x (all three are entered with
-- x = character/monster data pointer).  Phase 1 runs the fight untouched
-- and REQUIRES the detector to see the monsters act while unbroken -- the
-- positive control, asserted, so "we saw nothing" can never mean "nothing
-- was watching".
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/ifrit_doorstep.mss.lua"
local SHIELD_CUR, SHIELD_MAX, TICKS = 0x3e38, 0x3e39, 0x3e88
local IFRIT, SHIVA = 0x0109, 0x0108
local MENU = 0x7bca
local BVAR = 0x3eb0                      -- battle vars (battle_main.asm:5151)
local BREAK_TICKS = 0x10                 -- OT6_BREAK_TICKS (ot6_break.asm:1)

local function eoff(slot) return 8 + slot * 2 end
local function ticks(e)   return H.readByte(TICKS + e) end
local function shields(e) return H.readByte(SHIELD_CUR + e) end
local function smax(e)    return H.readByte(SHIELD_MAX + e) end
local function present(e) return H.readByte(0x3aa0 + e) & 1 end
local function species(slot) return H.readWord(0x57c0 + slot * 2) end
local function onfield(slot) return H.readByte(0x3aa8 + slot * 2) & 1 end
-- HP is one word per ENTITY offset: $3bf4 + entity.  Characters are
-- $3bf4..$3bfa, monsters $3bfc.. (Ot6BreakStart reads `$3bfc,y`,
-- ot6_break.asm:1228, with y = the monster's SLOT offset 0,2,..).
local function mhp(slot) return H.readWord(0x3bfc + slot * 2) end
local function partyHp()
  local t = {}
  for c = 0, 3 do t[#t + 1] = H.readWord(0x3bf4 + c * 2) end
  return table.concat(t, "/")
end

local function queueList()
  local s, e = H.readByte(0x3a66), H.readByte(0x3a67)
  local out = {}
  for i = s, e - 1 do
    local v = H.readByte(0x3820 + (i & 0xff))
    if v ~= 0xff then out[#out + 1] = v end
  end
  return out
end
local function queued(ent)
  for _, v in ipairs(queueList()) do if v == ent then return true end end
  return false
end

-- ------------------------------------------------------------- detectors --
local phase = "boot"
local acts = {}
local nAction, nRetal, nCmd = 0, 0, 0
local gateCalls, gateRefusals = 0, 0

local function note(kind, ent, extra)
  acts[#acts + 1] = { f = H.frame, kind = kind, ent = ent, ph = phase,
                      t = ticks(ent), sh = shields(ent), p = present(ent),
                      cmd = H.readByte(0x3a7a), atk = H.readByte(0x3a7b),
                      src = extra or "" }
end

local function armDetectors()
  -- `ExecCmd` is AMBIGUOUS in ff6-en.dbg: there are two (a field one at
  -- $C09B1B and the battle dispatcher at $C213E6), and H.sym returns the
  -- first, which never runs in battle.  `_dispatcher` (battle_main.asm:3115)
  -- is the unique alias for the battle one.
  local a, r, c = H.sym("ExecAction"), H.sym("ExecRetal"), H.sym("_dispatcher")
  local g = H.sym("Ot6Gate")
  emu.addMemoryCallback(function()
    nAction = nAction + 1
    local ent = emu.getState()["cpu.x"] & 0xff
    -- PROVENANCE.  BattleLoop reaches ExecAction two ways
    -- (battle_main.asm:148-159): a RESUME, when $3406 already holds a valid
    -- (bit-7-clear) entity because the last action left more pending
    -- (:305), or a DRAIN out of the $3820 action queue.  The callback fires
    -- on ExecAction's first instruction (`sec`, :210) so $3406 is still the
    -- pre-`ror` value the loop branched on.
    local resume = H.readByte(0x3406)
    note("ACTION", ent, (resume < 0x80) and string.format("resume$3406=%02X", resume)
      or string.format("drain q={%s}", table.concat(queueList(), ",")))
  end, emu.callbackType.exec, a, a)
  emu.addMemoryCallback(function()
    nRetal = nRetal + 1
    note("RETAL", emu.getState()["cpu.x"] & 0xff,
      string.format("$3407=%02X", H.readByte(0x3407)))
  end, emu.callbackType.exec, r, r)
  emu.addMemoryCallback(function()
    nCmd = nCmd + 1
    note("EXECCMD", emu.getState()["cpu.x"] & 0xff,
      string.format("cmd=%02X", H.readByte(0x00b5)))
  end, emu.callbackType.exec, c, c)
  -- Is the monster's AI SCRIPT itself running?  ExecAction's $1f arm
  -- (battle_main.asm:226-239) calls ExecMonsterAction, which is what turns a
  -- queued monster turn into a real attack / a tag.  Without this, a drained
  -- queue entry that dispatched CmdNoEffect ($b5 stays #$12 from :213 when
  -- the command list is empty) is indistinguishable from a real turn.
  local m = H.sym("ExecMonsterAction")
  emu.addMemoryCallback(function()
    note("AISCRIPT", emu.getState()["cpu.x"] & 0xff, "ExecMonsterAction")
  end, emu.callbackType.exec, m, m)
  local mr = H.sym("ExecAIRetal")
  emu.addMemoryCallback(function()
    note("AIRETAL", emu.getState()["cpu.x"] & 0xff, "ExecAIRetal")
  end, emu.callbackType.exec, mr, mr)
  -- The GATE's own control: prove Ot6Gate is consulted and does refuse
  -- broken entities at its one site, so anything that still acts is
  -- leakage DOWNSTREAM of the gate, not a gate that failed to fire.
  emu.addMemoryCallback(function()
    gateCalls = gateCalls + 1
    local ent = emu.getState()["cpu.x"] & 0xff
    if ent <= 0x12 and ticks(ent) ~= 0 then gateRefusals = gateRefusals + 1 end
  end, emu.callbackType.exec, g, g)
  H.log(string.format("detectors armed: ExecAction $%06X ExecRetal $%06X "
    .. "ExecCmd/_dispatcher $%06X Ot6Gate $%06X", a, r, c, g))
end

-- ------------------------------------------------------------- the ifrit --
-- The formation is FOUR monsters (measured: slots 0-3 = $0109 $0108 $0109
-- $0108) that hide and show each other; the tag IS a monster turn
-- (ai_script.asm:4523-4529 shiva / :4572-4578 ifrit).  "The ifrit" is
-- whichever $0109 slot is on the field.
local function ifritSlot()
  for s = 0, 5 do if species(s) == IFRIT and onfield(s) == 1 then return s end end
  for s = 0, 5 do if species(s) == IFRIT then return s end end
  return nil
end

local IE = nil
local brokeAt, armedAt, armedQ = nil, nil, nil
local qFrames = 0                -- frames ifrit's entity spent in the queue
local slotLog, lastKey = {}, nil

local function sample()
  if phase == "boot" then return end
  local key = {}
  for s = 0, 5 do
    if species(s) ~= 0xffff then
      key[#key + 1] = string.format("s%d[%04X] fld=%d pr=%d t=%-2d sh=%d/%d hp=%d",
        s, species(s), onfield(s), present(eoff(s)), ticks(eoff(s)),
        shields(eoff(s)), smax(eoff(s)), mhp(s))
    end
  end
  key = table.concat(key, " | ") .. string.format("  bvar3=%d", H.readByte(BVAR + 3))
  if key ~= lastKey then
    lastKey = key
    slotLog[#slotLog + 1] = { f = H.frame, k = key }
  end
  if IE and queued(IE) then qFrames = qFrames + 1 end

  -- PHASE 3 arming: break him the instant his entity sits in the action queue
  if phase == "arm" and not armedAt and IE and queued(IE) and ticks(IE) == 0 then
    armedQ = table.concat(queueList(), ",")
    H.writeByte(SHIELD_CUR + IE, 0)
    H.writeByte(TICKS + IE, BREAK_TICKS)
    armedAt = H.frame
    phase = "raced"
    H.log(string.format("ARMED f%d: ifrit (entity $%02X) forced BROKEN while his "
      .. "entity sat in the action queue [$3a66=%d $3a67=%d queue={%s}]",
      armedAt, IE, H.readByte(0x3a66), H.readByte(0x3a67), armedQ))
  end
end

local aPhase = 0
local function drive()
  aPhase = (aPhase + 1) % 8
  H.setPad((H.readByte(MENU) ~= 0 and aPhase < 4) and { "a" } or {})
end
local fightStep = { H.call(drive), H.waitFrames(1) }

local function dump(tag, from, to)
  H.log("---- " .. tag .. " ----")
  local n = 0
  for _, r in ipairs(acts) do
    if r.f >= from and (not to or r.f <= to) then
      n = n + 1
      H.log(string.format("  f%-6d %-7s ent=$%02X ticks=%-3d sh=%d pres=%d "
        .. "%-22s [%s]%s", r.f, r.kind, r.ent, r.t, r.sh, r.p,
        r.src, r.ph,
        (r.ent >= 8 and r.t ~= 0) and "   <<== BROKEN MONSTER ACTING" or ""))
    end
  end
  H.log(string.format("---- %d entries ----", n))
end

local function heartbeat(tag)
  return H.call(function()
    H.log(string.format("[%s] f%d phase=%s ifrit t=%d sh=%d/%d hp=%d pres=%d | "
      .. "party %s | queue={%s} | acts=%d/%d/%d",
      tag, H.frame, phase, ticks(IE or 8), shields(IE or 8), smax(IE or 8),
      mhp((IE or 8) // 2 - 4), present(IE or 8), partyHp(),
      table.concat(queueList(), ","), nAction, nRetal, nCmd))
  end)
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.pressButtons({ "a" }, 4), H.waitFrames(6),
  }, "one A-press -> battle 70"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle 70 active", 30),
  H.waitFrames(240),

  H.call(function()
    H.log("---- formation survey ----")
    for s = 0, 5 do
      H.log(string.format("  slot %d species=%04X entity=$%02X field=%d pres=%d "
        .. "shields=%d/%d ticks=%d hp=%d", s, species(s), eoff(s), onfield(s),
        present(eoff(s)), shields(eoff(s)), smax(eoff(s)), ticks(eoff(s)), mhp(s)))
    end
    H.assertEq(H.formationHas({ [IFRIT] = true, [SHIVA] = true }), true,
      "battle 70: IFRIT $0109 and SHIVA $0108 in the formation")
    IE = eoff(assert(ifritSlot(), "no IFRIT slot"))
    H.log(string.format("ifrit entity offset $%02X, shields %d/%d", IE,
      shields(IE), smax(IE)))
    -- Bosses are authored 6-shield (bosses-wob.md:626-629); make the fight
    -- survivable long enough to measure: pin party HP high, and give the
    -- espers enough HP that the party cannot end the fight early.  These are
    -- LAB CONTROLS on longevity only -- nothing here touches shields, the
    -- broken timer, the queues, or the gate.
    for c = 0, 3 do H.writeWord(0x3bf4 + c * 2, 800) end
    for s = 0, 3 do H.writeWord(0x3bfc + s * 2, 6000) end
    armDetectors()
    emu.addEventCallback(function() sample() end, emu.eventType.startFrame)
    phase = "control"
  end),

  -- ---------------------------------------------------------- PHASE 1 --
  -- POSITIVE CONTROL: the fight, untouched, must show monsters acting.
  H.driveUntil(function() return #acts >= 14 end, 12000, fightStep,
    "phase 1: unmolested fight, detector sees actions"),
  heartbeat("end of phase 1"),
  H.call(function()
    local monsterActs, ifritActs = 0, 0
    for _, r in ipairs(acts) do
      if r.ent >= 8 then
        monsterActs = monsterActs + 1
        if r.ent == IE then ifritActs = ifritActs + 1 end
      end
    end
    dump("phase 1 timeline (positive control)", 0)
    H.assertEq(monsterActs > 0, true,
      "POSITIVE CONTROL: the detector observed a MONSTER acting")
    H.assertEq(ifritActs > 0, true,
      "POSITIVE CONTROL: the detector observed IFRIT acting while unbroken")
  end),

  -- ---------------------------------------------------------- PHASE 2 --
  -- A2, the ordinary case: break ifrit outright (NOT racing the queue --
  -- his entity is deliberately not in it) and keep hitting him.  Anything
  -- he does from here is something a Broken monster did.
  H.call(function()
    phase = "broken"
    H.writeByte(SHIELD_CUR + IE, 0)
    H.writeByte(TICKS + IE, BREAK_TICKS)
    brokeAt = H.frame
    H.log(string.format("PHASE 2 f%d: ifrit forced BROKEN (ticks=%d, shields 0). "
      .. "queue at this instant = {%s} -- ifrit queued? %s",
      brokeAt, BREAK_TICKS, table.concat(queueList(), ","), tostring(queued(IE))))
  end),
  H.driveUntil(function() return ticks(IE) == 0 end, 20000, fightStep,
    "phase 2: fight on while ifrit is broken, until he recovers"),
  heartbeat("end of phase 2"),
  H.call(function()
    dump("phase 2 timeline (ifrit BROKEN the whole time)", brokeAt)
    local brk = {}
    for _, r in ipairs(acts) do
      if r.f >= brokeAt and r.ent >= 8 and r.t ~= 0 then brk[#brk + 1] = r end
    end
    H.log(string.format("A2) actions by a monster with a nonzero broken timer: %d",
      #brk))
    H.log(string.format("A2) ifrit recovered at f%d (%d frames after the break); "
      .. "shields %d/%d", H.frame, H.frame - brokeAt, shields(IE), smax(IE)))
  end),

  -- ---------------------------------------------------------- PHASE 3 --
  -- A1, the race: break him at the exact frame his entity sits in $3820.
  H.call(function()
    phase = "arm"
    H.log(string.format("PHASE 3 f%d: waiting for ifrit's entity to enter the "
      .. "action queue (it has been queued on %d frames so far)", H.frame, qFrames))
  end),
  H.driveUntil(function() return armedAt ~= nil end, 20000, fightStep,
    "phase 3: catch ifrit in the action queue and break him there"),
  H.driveUntil(function()
    return armedAt and ticks(IE) == 0 and H.frame > armedAt + 120
  end, 20000, fightStep, "phase 3: run that break out to recovery"),
  H.waitFrames(60),

  H.call(function()
    H.setPad({})
    dump("phase 3 timeline (break landed on a QUEUED action)", armedAt - 1)
    local raced = {}
    for _, r in ipairs(acts) do
      if r.f >= armedAt and r.ent >= 8 and r.t ~= 0 then raced[#raced + 1] = r end
    end
    H.log("======== VERDICT ========")
    H.log(string.format("detector totals: ExecAction=%d ExecRetal=%d ExecCmd=%d, "
      .. "%d entries recorded", nAction, nRetal, nCmd, #acts))
    local all = {}
    for _, r in ipairs(acts) do
      if r.ent >= 8 and r.t ~= 0 then all[#all + 1] = r end
    end
    H.log(string.format("A) TOTAL actions executed by a monster whose broken "
      .. "timer was nonzero: %d  (phase 3 alone: %d)", #all, #raced))
    local byKind = {}
    for _, r in ipairs(all) do byKind[r.kind] = (byKind[r.kind] or 0) + 1 end
    for k, v in pairs(byKind) do H.log(string.format("     %s x%d", k, v)) end
    H.log(string.format("ifrit's entity was in the action queue on %d of %d "
      .. "sampled frames", qFrames, H.frame))
    -- The gate's own control: it IS consulted, and it DOES see broken
    -- entities.  Everything above therefore leaked past it downstream.
    H.log(string.format("Ot6Gate: %d calls, %d of them with the entity's broken "
      .. "timer nonzero (i.e. turns the gate correctly refused to QUEUE)",
      gateCalls, gateRefusals))
    H.assertEq(gateRefusals > 0, true,
      "GATE CONTROL: Ot6Gate was consulted while a monster was broken")

    H.log("======== slot choreography (deduped) ========")
    for i = 1, math.min(#slotLog, 160) do
      H.log(string.format("  f%-6d %s", slotLog[i].f, slotLog[i].k))
    end
    H.log(string.format("(%d distinct states)", #slotLog))
    H.screenshot("ifritbreak_end")
  end),
})
