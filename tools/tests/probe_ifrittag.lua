-- PROBE (not a test, no @suite marker): does a Broken monster's timer stop
-- while it is TAGGED OUT, and can a Broken monster tag out at all?
--
-- Second half of the owner's Ifrit & Shiva report, 2026-07-30: "or possibly
-- that his shields didn't return after the broken turn?"
--
-- MECHANISM UNDER TEST.  Ot6Tick (ot6_break.asm:1672) is the only code that
-- counts the broken timer down and restores shields, and it is reached from
-- exactly one place: battle_main.asm:15148, inside DecCounters -- PAST the
-- early return at :15142, `lda $3aa0,x / lsr / bcc _5ae9  ; return if
-- $3aa0.0 is clear (target is not present)`.  Battle 70 is a tag fight:
-- four monster slots ($0109 $0108 $0109 $0108), only one on the field at a
-- time, the swap performed by the on-stage monster's OWN AI turn
-- (ai_script.asm:4523-4529 shiva, :4572-4578 ifrit -- kill_monsters self /
-- show_monsters sibling, gated on `if_battle_var_greater 3, 5`).  So if the
-- tag clears $3aa0.0, a Broken monster that leaves the stage should freeze
-- mid-break and come back still Broken with no shields.
--
-- PAIRED CONTROL, which is the whole design of this probe.  "The off-stage
-- timer did not move" means nothing on its own -- a wedged battle looks
-- identical.  So both siblings are broken on the SAME FRAME, one on stage
-- and one off, and the two timers are logged side by side.  The on-stage
-- one must tick and restore; that is what makes the other one's stillness
-- evidence.
--
-- Phase 1 is a second control: a REAL tag is observed happening on its own
-- before anything is written, so the probe cannot conclude things about a
-- swap mechanic it never saw run.
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/ifrit_doorstep.mss.lua"
local SHIELD_CUR, SHIELD_MAX, TICKS = 0x3e38, 0x3e39, 0x3e88
local IFRIT, SHIVA = 0x0109, 0x0108
local MENU = 0x7bca
local BVAR = 0x3eb0
local BREAK_TICKS = 0x10

local function eoff(slot) return 8 + slot * 2 end
local function ticks(e)   return H.readByte(TICKS + e) end
local function shields(e) return H.readByte(SHIELD_CUR + e) end
local function smax(e)    return H.readByte(SHIELD_MAX + e) end
local function pres(e)    return H.readByte(0x3aa0 + e) & 1 end   -- $3aa0.0
local function fld(slot)  return H.readByte(0x3aa8 + slot * 2) & 1 end
local function species(slot) return H.readWord(0x57c0 + slot * 2) end
local function mhp(slot)  return H.readWord(0x3bfc + slot * 2) end

local onStage, offStage = nil, nil     -- slot indices, latched at the tag
local watching = false
local tagEvents, pairLog, lastPair = {}, {}, nil

-- A swap MATERIALIZES the incoming sibling before it kills the outgoing one
-- (ai_script.asm:4525-4527: kill_monsters_wait / show_monsters /
-- kill_monsters), so for a few frames BOTH read on-field -- measured, mask
-- 1000 -> 1100 -> 0100 at f2692/f2698.  Latching the pair off that overlap
-- frame picks the wrong sibling (it picked slot 2, which the ordinary tag
-- never uses), so the tag is defined on the SOLE occupant changing.
local sole, prevSole = nil, nil
local phase4, p4Armed, p4Slot, p4Bvar, p4Tag = nil, nil, nil, nil, nil

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

local function soleOnField()
  local n, who = 0, nil
  for s = 0, 3 do if fld(s) == 1 then n = n + 1; who = s end end
  return (n == 1) and who or nil
end

local function sample()
  if not watching then return end
  local cur = soleOnField()
  if cur and cur ~= sole then
    if sole ~= nil then
      prevSole = sole
      tagEvents[#tagEvents + 1] = { f = H.frame, from = sole, to = cur,
                                    bv = H.readByte(BVAR + 3) }
      H.log(string.format("TAG f%d: slot %d -> slot %d (bvar3=%d); outgoing "
        .. "$3aa0.0=%d t=%d sh=%d, incoming $3aa0.0=%d t=%d sh=%d",
        H.frame, sole, cur, H.readByte(BVAR + 3),
        pres(eoff(sole)), ticks(eoff(sole)), shields(eoff(sole)),
        pres(eoff(cur)), ticks(eoff(cur)), shields(eoff(cur))))
    end
    if phase4 == "armed" and p4Slot == prevSole and ticks(eoff(p4Slot)) ~= 0
       and not p4Tag then
      p4Tag = { f = H.frame, t = ticks(eoff(p4Slot)) }
    end
    sole = cur
  end
  if phase4 == "armed" and p4Slot and ticks(eoff(p4Slot)) == 0 and not p4Tag then
    phase4 = "arm"            -- it recovered without tagging; try again
  end
  if onStage then
    local key = string.format(
      "ON  slot%d fld=%d pres=%d t=%-2d sh=%d/%d || OFF slot%d fld=%d pres=%d "
      .. "t=%-2d sh=%d/%d", onStage, fld(onStage), pres(eoff(onStage)),
      ticks(eoff(onStage)), shields(eoff(onStage)), smax(eoff(onStage)),
      offStage, fld(offStage), pres(eoff(offStage)), ticks(eoff(offStage)),
      shields(eoff(offStage)), smax(eoff(offStage)))
    if key ~= lastPair then
      lastPair = key
      pairLog[#pairLog + 1] = { f = H.frame, k = key }
    end
  end
end

local aPhase = 0
local fightStep = {
  H.call(function()
    aPhase = (aPhase + 1) % 8
    H.setPad((H.readByte(MENU) ~= 0 and aPhase < 4) and { "a" } or {})
  end),
  H.waitFrames(1),
}

local function survey(tag)
  local t = {}
  for s = 0, 3 do
    t[#t + 1] = string.format("s%d[%04X] fld=%d pres=%d t=%d sh=%d/%d hp=%d",
      s, species(s), fld(s), pres(eoff(s)), ticks(eoff(s)), shields(eoff(s)),
      smax(eoff(s)), mhp(s))
  end
  H.log(string.format("[%s f%d bvar3=%d] %s", tag, H.frame,
    H.readByte(BVAR + 3), table.concat(t, " | ")))
end

local brokeAt, onRecoveredAt, backAt = nil, nil, nil

-- Phase 4's arm and its own positive control.  A tag is the on-stage
-- monster's own AI turn, and probe_ifritbreak showed the ONE ungated window
-- is "queued already, break lands before the drain" -- so the faithful arming
-- point is ExecAction ENTRY (battle_main.asm:209) with x = that monster: the
-- queue entry exists, nothing has re-checked status, and a break landing
-- anywhere in that window looks exactly like this.  aiRuns counts
-- ExecMonsterAction (:463), the call that turns a queued monster turn into a
-- real AI script -- WITHOUT it, "the drained entry dispatched CmdNoEffect" is
-- the only thing a queue-poll arm can ever see (measured: it is what
-- probe_ifritbreak saw twice).
local p4Attempts, aiRuns, aiRunsBroken = 0, 0, 0
local function armPhase4()
  local ea, ma = H.sym("ExecAction"), H.sym("ExecMonsterAction")
  emu.addMemoryCallback(function()
    if phase4 ~= "arm" then return end
    local ent = emu.getState()["cpu.x"] & 0xff
    if ent < 8 or ent > 0x12 then return end
    local slot = (ent - 8) // 2
    if slot ~= sole or ticks(ent) ~= 0 then return end
    if H.readByte(BVAR + 3) <= 5 then return end   -- swap branch not armed
    p4Slot, p4Bvar, p4Armed = slot, H.readByte(BVAR + 3), H.frame
    p4Attempts = p4Attempts + 1
    H.writeByte(SHIELD_CUR + ent, 0)
    H.writeByte(TICKS + ent, BREAK_TICKS)
    phase4 = "armed"
  end, emu.callbackType.exec, ea, ea)
  emu.addMemoryCallback(function()
    local ent = emu.getState()["cpu.x"] & 0xff
    aiRuns = aiRuns + 1
    if ent >= 8 and ent <= 0x12 and ticks(ent) ~= 0 then
      aiRunsBroken = aiRunsBroken + 1
      H.log(string.format("AI SCRIPT ran for entity $%02X at f%d with its "
        .. "broken timer at %d", ent, H.frame, ticks(ent)))
    end
  end, emu.callbackType.exec, ma, ma)
  H.log(string.format("phase-4 detectors armed: ExecAction $%06X "
    .. "ExecMonsterAction $%06X", ea, ma))
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
    H.assertEq(H.formationHas({ [IFRIT] = true, [SHIVA] = true }), true,
      "battle 70: IFRIT and SHIVA in the formation")
    survey("battle start")
    -- lab controls on LONGEVITY only: the fight has to outlive two break
    -- windows and two tags.  Nothing here touches shields, timers, the
    -- present bits, the queues, or the gate.
    for c = 0, 3 do H.writeWord(0x3bf4 + c * 2, 900) end
    for s = 0, 3 do H.writeWord(0x3bfc + s * 2, 9000) end
    emu.addEventCallback(function() sample() end, emu.eventType.startFrame)
    watching = true
  end),

  -- ------------------------------------------------------------ PHASE 1 --
  -- CONTROL: watch a real, unforced tag happen.  The swap is the on-stage
  -- monster's own turn and needs battle var 3 > 5, which its retaliation
  -- script raises one per hit taken -- so just fight.
  H.driveUntil(function() return #tagEvents > 0 end, 25000, fightStep,
    "phase 1: a natural tag-out"),
  H.waitFrames(120),               -- let the materialize overlap settle
  H.call(function()
    survey("just after the first tag")
    onStage, offStage = soleOnField(), prevSole
    H.assertEq(onStage ~= nil, true, "exactly one monster is on the field")
    H.assertEq(offStage ~= nil, true, "a tagged-out sibling exists")
    H.assertEq(onStage ~= offStage, true, "the pair is two different slots")
    H.assertEq(pres(eoff(offStage)), 0,
      "the tagged-out sibling has $3aa0.0 CLEAR (DecCounters' early return "
      .. "at battle_main.asm:15142 will fire for it)")
    H.assertEq(pres(eoff(onStage)), 1, "the on-stage monster has $3aa0.0 set")
    H.log(string.format("on stage = slot %d ($%02X), tagged out = slot %d ($%02X)",
      onStage, eoff(onStage), offStage, eoff(offStage)))
  end),

  -- ------------------------------------------------------------ PHASE 2 --
  -- Break BOTH siblings on the same frame.  The on-stage one is the control.
  H.call(function()
    for _, s in ipairs({ onStage, offStage }) do
      H.writeByte(SHIELD_CUR + eoff(s), 0)
      H.writeByte(TICKS + eoff(s), BREAK_TICKS)
    end
    brokeAt = H.frame
    lastPair = nil
    H.log(string.format("PHASE 2 f%d: BOTH siblings forced Broken (ticks=%d, "
      .. "shields 0) -- slot %d on stage, slot %d tagged out",
      brokeAt, BREAK_TICKS, onStage, offStage))
    survey("both broken")
  end),
  H.driveUntil(function()
    return ticks(eoff(onStage)) == 0
  end, 25000, fightStep, "phase 2: the ON-STAGE break to run out (the control)"),
  H.call(function()
    onRecoveredAt = H.frame
    survey("on-stage sibling recovered")
    H.log(string.format("CONTROL: the ON-STAGE broken timer went %d -> 0 in %d "
      .. "frames and its shields restored to %d/%d", BREAK_TICKS,
      onRecoveredAt - brokeAt, shields(eoff(onStage)), smax(eoff(onStage))))
    H.log(string.format("MEASURED: over those same %d frames the TAGGED-OUT "
      .. "sibling's timer went %d -> %d and its shields are %d/%d",
      onRecoveredAt - brokeAt, BREAK_TICKS, ticks(eoff(offStage)),
      shields(eoff(offStage)), smax(eoff(offStage))))
  end),

  -- ------------------------------------------------------------ PHASE 3 --
  -- Let the fight run to the NEXT tag and watch the frozen sibling come back.
  H.driveUntil(function()
    return soleOnField() == offStage
  end, 25000, fightStep, "phase 3: the frozen sibling to be tagged back in"),
  H.call(function()
    backAt = H.frame
    survey("frozen sibling tagged back in")
    H.log(string.format("BACK IN f%d (%d frames tagged out): slot %d returns "
      .. "with ticks=%d shields=%d/%d", backAt, backAt - brokeAt, offStage,
      ticks(eoff(offStage)), shields(eoff(offStage)), smax(eoff(offStage))))
  end),
  H.driveUntil(function() return ticks(eoff(offStage)) == 0 end, 25000,
    fightStep, "phase 3: the thawed timer to finish"),
  H.call(function()
    survey("thawed sibling recovered")
    H.log(string.format("THAWED: slot %d's timer resumed on re-entry and hit 0 "
      .. "at f%d -- %d frames after the break, %d of them off stage",
      offStage, H.frame, H.frame - brokeAt, backAt - brokeAt))
  end),

  -- ------------------------------------------------------------ PHASE 4 --
  -- REACHABILITY.  Phase 2 wrote the frozen state by hand; this asks whether
  -- play can reach it.  A tag is the on-stage monster's own AI turn and
  -- Ot6Gate refuses to QUEUE a broken monster's turn -- but probe_ifritbreak
  -- showed a queue entry that already exists is executed regardless
  -- (battle_main.asm:150-159).  So: wait until the swap branch is armed
  -- (battle var 3 > 5, ai_script.asm:4523/:4572) AND the on-stage monster's
  -- entity is sitting in $3820, break it at that instant, and see whether the
  -- tag runs anyway.  Soft: it reports either way rather than failing.
  H.call(function()
    armPhase4()
    phase4 = "arm"
    H.log(string.format("PHASE 4 f%d: arming the swap race (bvar3=%d, "
      .. "ExecMonsterAction seen %d times so far)", H.frame,
      H.readByte(BVAR + 3), aiRuns))
  end),
  -- Bounded and SOFT: phase 4 is a reachability hunt, and "did not happen in
  -- N frames" is not a proof of impossibility.  It reports; it does not fail.
  H.repeatN(6000, fightStep),
  H.call(function()
    H.log(string.format("PHASE 4: %d arming attempts; ExecMonsterAction ran %d "
      .. "times total, %d of them with the actor's broken timer up",
      p4Attempts, aiRuns, aiRunsBroken))
    if aiRunsBroken > 0 then
      H.log("PHASE 4: a Broken monster's MAIN AI script did execute (see the "
        .. "'AI SCRIPT ran' lines) -- the leak reaches the script, not just an "
        .. "empty CmdNoEffect turn")
    end
    if not p4Tag then
      H.log("PHASE 4: no tag-out by a Broken monster observed in this window. "
        .. "INCONCLUSIVE about reachability -- phase 2 proved the freeze "
        .. "itself, this only asks whether ordinary play can steer into it.")
    end
    if p4Tag then
      H.log(string.format("PHASE 4 RESULT: slot %d, broken at f%d (bvar3=%d), "
        .. "TAGGED ITSELF OUT at f%d with its broken timer still reading %d. "
        .. "A Broken sibling CAN leave the stage, so the frozen state phase 2 "
        .. "wrote by hand is reachable in ordinary play.",
        p4Slot, p4Armed, p4Bvar, p4Tag.f, p4Tag.t))
    end
    -- Only meaningful while the battle is still live: once it ends the
    -- battle RAM these read is scratch (it reported ticks=255 sh=255/255 the
    -- first time this was printed unguarded).
    if p4Slot and H.battleActive() then
      H.log(string.format("PHASE 4 final: slot %d fld=%d pres=%d ticks=%d sh=%d/%d",
        p4Slot, fld(p4Slot), pres(eoff(p4Slot)), ticks(eoff(p4Slot)),
        shields(eoff(p4Slot)), smax(eoff(p4Slot))))
    else
      H.log("PHASE 4 final: battle no longer live; slot state not reported")
    end
  end),

  H.call(function()
    H.setPad({})
    H.log("======== tag events ========")
    for _, t in ipairs(tagEvents) do
      H.log(string.format("  f%-6d on-field mask %s -> %s (bvar3=%d)",
        t.f, t.from, t.to, t.bv))
    end
    H.log("======== paired timer log (on stage || tagged out) ========")
    for i = 1, math.min(#pairLog, 200) do
      H.log(string.format("  f%-6d %s", pairLog[i].f, pairLog[i].k))
    end
    H.log(string.format("(%d distinct states)", #pairLog))
    H.screenshot("ifrittag_end")
  end),
})
