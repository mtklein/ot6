-- @suite savestate=ifrit_entry slow
-- battle_brokendeath.lua -- the Broken turn gate: that it holds, and where it
-- may sit.

-- Ot6MayAct (ot6_break.asm) refuses a Broken monster's turn at execution
-- time.  Its one call site is inside CheckRetal (battle_main.asm), and
-- CheckRetal is not only the counterattack path: an AI script's
-- `if_self_dead` block reaches it too, through the `bit $3a56`
-- died-branch ($3a56 is "characters/monsters that have died",
-- set at battle_main.asm:11859-11863).

-- Ifrit and Shiva do not end by dying.  They end by a script in that block:
-- three dlg lines around a restore_monsters, then end_battle (Shiva's at
-- ai_script.asm:4546-4557, Ifrit's at :4595-4606), and a break's x2 makes dying
-- while Broken the ordinary way that block is reached.  So a Broken gate
-- placed at the top of CheckRetal, which assembles cleanly and reads
-- tidily, strands the ending and soft-locks the boss.  This test kills a
-- Broken boss in battle 70 and requires the fight to end anyway.

-- The assertion is on ExecAIRetal running (not merely on the battle
-- ending, since killing the only on-stage monster is an ordinary victory
-- either way), and on the kill landing while Broken (otherwise the test
-- degrades to checking that the boss dies, which passes with no gate at
-- all).  Shields read 6/6 at battle start (seeded from level, not
-- pre-cleared) and both HP totals read their authored 3300 and 3000.

-- The guarded property is monster-agnostic, so the assertions bind to
-- whichever of the pair dies first: both siblings end the fight through
-- the same if_self_dead ending, the break multiplier makes dying
-- mid-break the ordinary path for either, and the gate placement mistake
-- strands either one equally.

-- Monster slot note: the live monsters sit in battle slots 0 (Ifrit, on
-- stage from the fly-in) and 1 (Shiva, hidden until the tag); the
-- formation table $57c0 repeats both species at slots 2/3 with dead
-- entities behind them, so the slot scan below prefers the lowest slot per
-- species.
local H = dofile("tools/tests/lib/ot6.lua")
local L = H.newSeedLadder("battle 70")

local STATE = "build/states/ifrit_entry.mss.lua"
local IFRIT, SHIVA = 0x0109, 0x0108
local EDGAR, CELES = 0x04, 0x06

local function eoff(m) return 8 + m * 2 end
local function shields(m) return H.readByte(0x3E38 + eoff(m)) end
local function ticks(m)   return H.readByte(0x3E88 + eoff(m)) end
local function mhp(m)     return H.readWord(0x3BFC + m * 2) end
local function onfield(m) return H.readByte(0x3AA8 + m * 2) & 1 end
local function species(m) return H.readWord(0x57C0 + m * 2) end
local function chp(s)     return H.readWord(0x3BF4 + s * 2) end
local function partyAlive()
  for c = 0, 3 do if chp(c) > 0 then return true end end
  return false
end

local retals, detectorArmed = {}, false
local cmds, execs = {}, {}   -- the leak detector's raw entries, see below
local fightBlob = nil
local won = nil    -- the winning attempt's observation, once one produces it

-- a bare step list cannot be spliced into a step list; H.cond with an
-- always-true predicate is the library's public way to wrap one into a step
local function seq(steps) return H.cond(function() return true end, steps) end

-- "the battle ended" is not the discriminating observation, and taking it as
-- one produced a wrong conclusion: with the gate misplaced the fight still
-- ended, sooner, because killing the only on-stage monster is an ordinary
-- victory.  What must be asserted is that the script ran: CheckRetal sets
-- command $1f and CreateRetalAction queues it (battle_main.asm:12753-12755),
-- ExecRetal dispatches it through ExecAIRetal (:12616), and that is where
-- `if_self_dead` is evaluated.  So: count ExecAIRetal entries for the dead
-- monster after the kill.  Armed once; frame numbers only rise across the
-- ladder's reloads, so entries from a lost attempt can never satisfy the
-- winning attempt's `f >= deathFrame` filter.

-- What that is worth asserting on is the command dispatch, not the queue
-- entry: Ot6MayAct lets the turn be consumed and thrown away, so bare
-- ExecAction/ExecRetal entries with the timer up still happen and are not the
-- defect.  So hook `_dispatcher` (battle_main.asm:3120, the battle ExecCmd's
-- unique alias; the bare name `ExecCmd` is defined twice in ff6-en.dbg and
-- H.sym refuses it) and require zero dispatches by an entity whose broken
-- timer is running.

-- Classifying them by reading $3a56 at the dispatch does not work, which cost
-- a run to find out: ExecAIRetal clears the entity's died bit on entry
-- (`trb $3a56`, battle_main.asm:12682) before it runs a line of script, and
-- carrying a flag from ExecAIRetal does not work either, because the block's
-- four commands drain one per ExecRetal call (:12662-12668 re-arms $3407 and
-- the next BattleLoop iteration re-enters), so there is no single turn to
-- scope the flag to.  A frame bound needs neither.

-- Its positive control is the same hook's other tally: monsters must be seen
-- dispatching commands while unbroken, inside the same window.  Without that,
-- "no broken dispatches" and "the hook never fired" report the same green.
local function armRetalDetector()
  if detectorArmed then return end
  detectorArmed = true
  local a = H.sym("ExecAIRetal")
  emu.addMemoryCallback(function()
    retals[#retals + 1] = { f = H.frame, ent = emu.getState()["cpu.x"] & 0xff }
  end, emu.callbackType.exec, a, a)
  local d = H.sym("_dispatcher")
  emu.addMemoryCallback(function()
    local e = emu.getState()["cpu.x"] & 0xff
    cmds[#cmds + 1] = { f = H.frame, ent = e, tk = H.readByte(0x3E88 + e),
                        cmd = H.readByte(0x00B5) }
  end, emu.callbackType.exec, d, d)
  for _, name in ipairs({ "ExecAction", "ExecRetal" }) do
    local s = H.sym(name)
    emu.addMemoryCallback(function()
      local e = emu.getState()["cpu.x"] & 0xff
      execs[#execs + 1] = { f = H.frame, ent = e, tk = H.readByte(0x3E88 + e),
                            kind = name }
    end, emu.callbackType.exec, s, s)
  end
  local ms = H.sym("ExecMonsterAction")
  emu.addMemoryCallback(function()
    local e = emu.getState()["cpu.x"] & 0xff
    execs[#execs + 1] = { f = H.frame, ent = e, tk = H.readByte(0x3E88 + e),
                          kind = "ExecMonsterAction" }
  end, emu.callbackType.exec, ms, ms)
  H.log(string.format("detectors armed: ExecAIRetal $%06X, ExecCmd $%06X, "
    .. "ExecAction $%06X, ExecRetal $%06X", a, d,
    H.sym("ExecAction"), H.sym("ExecRetal")))
end

-- One attempt, flat (driveUntil bodies replay latched state, so every
-- attempt builds fresh closures).  Attempt 1 runs in place, since the live
-- timeline is the blob's timeline; later attempts reload the entry-point blob
-- and shift the RNG phase.  An attempt records into `won` only when a boss
-- died with its broken timer running and the break was observed happening.
local function attempt(n)
  local loadReq
  local ISLOT, SSLOT = nil, nil
  local sawBreak = {}              -- [slot] = first frame shields 0 + timer up
  local deathSlot, deathFrame, deathTicks = nil, nil, nil
  local startFrame = nil           -- first frame of THIS attempt's battle
  local hb = 0
  -- CELES chips IFRIT with Ice (the b70 design: ice + piercing is his row),
  -- so the break lands before the kill.  Under the one-care-per-round
  -- driver the party attacks harder, and without a chip key IFRIT died
  -- through his shields unbroken -- the ladder then had no observation.
  local F = H.newFightDriver("brokendeath", { tactical = true, boost = true,
    bank = 3, items = true, healPercent = 60, cadence = 12,
    magic = { [6] = { spell = 1, boost = false } } })
  local function mname(m)
    return m == ISLOT and "IFRIT" or m == SSLOT and "SHIVA" or ("slot " .. m)
  end
  return H.cond(function() return won ~= nil end, {}, {
    H.logStep(function()
      return string.format("battle 70 attempt %d at f%d", n, H.frame)
    end),
    n > 1 and seq({
      H.call(function() loadReq = H.requestLoadState(fightBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "entry-point blob reload") end),
      H.waitFrames(90),
      H.call(function()
        H.assertEq(H.hasControl(), true, "reloaded controllable at the entry point")
      end),
    }) or seq({}),
    L.spread(n),                        -- spread the battle RNG phase (#83)

    -- one real A-press into battle 70
    H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
      H.pressButtons({ "a" }, 4), H.waitFrames(6),
    }, "one A-press -> battle 70"),
    H.waitUntil(function() return H.battleActive() end, 900,
      "battle 70 active", 30),

    H.call(function()
      H.assertEq(H.formationHas({ [IFRIT] = true, [SHIVA] = true }), true,
        "battle 70: IFRIT and SHIVA in the formation")
      local slotOf = {}
      for s = 0, 3 do
        local id = H.readByte(0x3ED8 + s * 2)
        if id ~= 0xFF then slotOf[id] = s end
      end
      H.assertEq(slotOf[CELES] ~= nil, true, "CELES present (#21 roster)")
      H.assertEq(slotOf[EDGAR] ~= nil, true,
        "EDGAR present (#21 roster; his AutoCrossbow is the tactical pierce)")
      for m = 5, 0, -1 do                -- lowest live slot wins (header)
        if species(m) == IFRIT then ISLOT = m end
        if species(m) == SHIVA then SSLOT = m end
      end
      H.assertEq(ISLOT ~= nil, true, "an IFRIT slot resolved")
      H.assertEq(SSLOT ~= nil, true, "a SHIVA slot resolved")
      -- both gauges seed full and both HP words read their authored values
      H.assertEq(shields(ISLOT), 6, "ifrit opens with his authored 6 shields")
      H.assertEq(shields(SSLOT), 6, "shiva opens with her authored 6 shields")
      H.assertEq(mhp(ISLOT), 3300, "ifrit opens at his authored 3300 HP (no clamp)")
      H.assertEq(mhp(SSLOT), 3000, "shiva opens at her authored 3000 HP (no clamp)")
      H.assertEq(ticks(ISLOT), 0, "ifrit is NOT pre-broken")
      H.assertEq(ticks(SSLOT), 0, "shiva is NOT pre-broken")
      startFrame = H.frame
      armRetalDetector()
    end),

    H.waitUntil(function() return onfield(ISLOT) == 1 end, 3600,
      "ifrit takes the stage", 10),
    H.waitFrames(90),

    -- the input-driven fight: the library fighter, with gauges logged around
    -- it.  Its menu==0 branch also pages the recognition scene's dialogs and
    -- the victory teardown, so this one drive carries the battle from fly-in
    -- to field, or through the Annihilated screen on a loss.
    H.driveUntil(function() return not H.battleLoadStarted() end, 60000, {
      H.call(function()
        hb = hb + 1
        if hb % 600 == 0 then
          H.log(string.format(
            "f%d ifr hp=%d sh=%d tk=%d fld=%d | shv hp=%d sh=%d tk=%d | party %d/%d/%d/%d",
            H.frame, mhp(ISLOT), shields(ISLOT), ticks(ISLOT), onfield(ISLOT),
            mhp(SSLOT), shields(SSLOT), ticks(SSLOT),
            chp(0), chp(1), chp(2), chp(3)))
        end
        for _, m in ipairs({ ISLOT, SSLOT }) do
          if not sawBreak[m] and shields(m) == 0 and ticks(m) ~= 0 then
            sawBreak[m] = H.frame
            H.log(string.format("%s BROKEN at f%d: shields 0, timer %d -- "
              .. "six real chips did this", mname(m), H.frame, ticks(m)))
          end
          if not deathFrame and mhp(m) == 0 then
            deathSlot, deathFrame, deathTicks = m, H.frame, ticks(m)
            H.log(string.format("%s hp hit 0 at f%d with a broken timer of %d",
              mname(m), deathFrame, deathTicks))
          end
        end
        F.frame()
      end),
    }, "battle 70 fought to the script's own ending"),

    -- evaluate: this attempt counts as the observation only if a boss died
    -- with its broken timer running and the break was observed first
    H.call(function()
      H.setPad({})
      if deathFrame and deathTicks ~= 0 and sawBreak[deathSlot] then
        won = { slot = deathSlot, name = mname(deathSlot),
                deathFrame = deathFrame, deathTicks = deathTicks,
                breakFrame = sawBreak[deathSlot], endFrame = H.frame,
                startFrame = startFrame,
                partyAlive = partyAlive(),
                battleOver = not H.battleActive() }
        H.log(string.format("attempt %d: %s killed mid-break (tk=%d) -- "
          .. "the observation this test exists for", n, won.name, deathTicks))
      elseif deathFrame then
        H.log(string.format("attempt %d: %s died but NOT broken (tk=0) -- "
          .. "no observation; retrying", n, mname(deathSlot)))
      else
        H.log(string.format("attempt %d: no boss died (party %d/%d/%d/%d) -- "
          .. "a wipe; retrying", n, chp(0), chp(1), chp(2), chp(3)))
      end
    end),
  })
end

H.run({ maxFrames = 250000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 600, "field control", 5),

  -- 1. the player's prep, all through real menus: preserve this fixture's
  --    actual named kit, then top up HP with the bag's own items
  --    (H.fieldCare).  The old arm asked this independent lineage for the
  --    checkpoint lineage's two ThunderBlades; neither exists in this save,
  --    so that was a fixture fabrication disguised as menu input.  EDGAR's
  --    MithrilBlade supplies slash, while the daggers and Tools cover pierce.
  -- Best-effort, like the wave-4 kits: each slot conds on the bag
  -- (present -> worn, absent -> keep current gear, logged).  LOCKE wears
  -- the Genji Glove, so his left hand is a DAGGER ladder, never a shield
  -- -- the { 1, $5A } this kit used to force stuffed a Buckler over his
  -- dual-wield whenever the bag held one.  EDGAR and CELES have no
  -- glove; their shields stay, skipping when the bag runs out.
  (function()
    local KITS = {
      { 1, "LOCKE", { { 0, 0x0F }, { 1, 0x00 }, { 1, 0x01 }, { 1, 0x02 },
                      { 2, 0x69 }, { 3, 0x84 } } },
      { 4, "EDGAR", { { 0, 0x0A }, { 1, 0x5A }, { 2, 0x69 }, { 3, 0x84 } } },
      { 5, "SABIN", { { 0, 0x53 }, { 2, 0x69 }, { 3, 0x86 } } },
      { 6, "CELES", { { 0, 0x01 }, { 1, 0x5A }, { 2, 0x6A }, { 3, 0x84 } } },
    }
    local steps = {}
    for _, kit in ipairs(KITS) do
      local char, name, pairs_ = kit[1], kit[2], kit[3]
      for _, p in ipairs(pairs_) do
        local slot, item = p[1], p[2]
        local tag = string.format("%s battle-70 kit slot %d", name, slot)
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
  H.fieldCare({ tag = "care before battle 70", threshold = 0.95 }),

  -- 2. capture the prepared entry point as the retry ladder's reload blob
  (function()
    local req
    return seq({
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "entry-point retry blob")
        fightBlob = req.blob
        H.log(string.format("retry blob captured: %d bytes", #fightBlob))
      end),
    })
  end)(),

  -- 3. the fight, on the phase-spread ladder
  L.watch(),
  attempt(1),
  attempt(2),
  attempt(3),
  L.report(),

  -- 4. The property under test: a mid-break kill happened, and the
  -- `if_self_dead` script still ran and ended the fight.
  H.call(function()
    H.assertEq(won ~= nil, true,
      "a Broken boss was killed mid-break within 3 attempts -- without "
      .. "that kill this test cannot say anything about the gate")
    H.assertEq(won.breakFrame <= won.deathFrame, true,
      "the break was OBSERVED before the kill: " .. won.name
      .. "'s shields chipped 6 -> 0 by real hits, timer seeded by the engine")
    H.assertEq(won.deathTicks ~= 0, true,
      "the kill landed while " .. won.name .. " was still BROKEN "
      .. "(otherwise this test says nothing about the gate)")
    for _, r in ipairs(retals) do
      H.log(string.format("  ExecAIRetal f%-6d ent=$%02X%s", r.f, r.ent,
        (r.f >= won.deathFrame and r.ent == eoff(won.slot))
          and ("   <<== post-kill, the dead " .. won.name) or ""))
    end
    local postKill = 0
    for _, r in ipairs(retals) do
      if r.f >= won.deathFrame and r.ent == eoff(won.slot) then
        postKill = postKill + 1
      end
    end
    H.assertEq(won.battleOver, true, "the battle ended")
    H.assertEq(won.partyAlive, true,
      "the party survived on REAL HP -- the battle ended by script, not by "
      .. "a wipe (and nobody's HP was ever pinned to make that true)")
    H.assertEq(postKill > 0, true,
      "the dead Broken " .. won.name .. "'s AI script RAN "
      .. "(ExecAIRetal after the kill) -- this is `if_self_dead`, the "
      .. "recognition scene and end_battle; a Broken gate placed above "
      .. "CheckRetal's $3a56 died-branch skips it and the fight degrades "
      .. "to an ordinary kill")
    H.log(string.format("battle ended at f%d, %d frames after the Broken kill; "
      .. "%d post-kill AI-retal entries for the dead %s",
      won.endFrame, won.endFrame - won.deathFrame, postKill, won.name))
    H.screenshot("brokendeath_end")
  end),

  H.call(function()
    -- Entities are $00..$12 in steps of 2.  ExecCmd's third caller, "execute
    -- immediate action" (battle_main.asm:5778-5797), is entered with A = a
    -- command-list pointer and X left as it was, so those arrivals carry no
    -- entity and are counted separately rather than attributed to whatever X
    -- happened to hold.  A baseline run produced four of them at x=$ff, whose
    -- $3e88+$ff read lands outside the broken-timer table entirely.
    local function isEntity(e) return e <= 0x12 and e % 2 == 0 end
    local leaks, ending, monsterCmds, charCmds, noEntity = {}, {}, 0, 0, {}
    for _, r in ipairs(cmds) do
      if r.f >= won.startFrame then
        if not isEntity(r.ent) then noEntity[#noEntity + 1] = r
        elseif r.f > won.deathFrame then
          if r.ent >= 0x08 and r.tk ~= 0 then ending[#ending + 1] = r end
        elseif r.ent < 0x08 then charCmds = charCmds + 1
        elseif r.tk == 0 then monsterCmds = monsterCmds + 1
        else leaks[#leaks + 1] = r end
      end
    end
    local byKind = {}
    for _, r in ipairs(execs) do
      if r.f >= won.startFrame and r.f <= won.deathFrame
         and isEntity(r.ent) and r.ent >= 0x08 and r.tk ~= 0 then
        byKind[r.kind] = (byKind[r.kind] or 0) + 1
        H.log(string.format("  consumed and dropped: %-18s f%-6d ent=$%02X "
          .. "timer=%d", r.kind, r.f, r.ent, r.tk))
      end
    end
    for _, r in ipairs(ending) do
      H.log(string.format("  after the kill: ExecCmd f%-6d ent=$%02X cmd=$%02X "
        .. "timer=%d (the `if_self_dead` ending, outside the window)",
        r.f, r.ent, r.cmd, r.tk))
    end
    for _, r in ipairs(leaks) do
      H.log(string.format("  LEAK: ExecCmd f%-6d ent=$%02X cmd=$%02X "
        .. "timer=%d", r.f, r.ent, r.cmd, r.tk))
    end
    for _, r in ipairs(noEntity) do
      H.log(string.format("  no entity: ExecCmd f%-6d x=$%02X cmd=$%02X "
        .. "(the immediate-action caller; not attributable)", r.f, r.ent, r.cmd))
    end
    H.log(string.format("f%d..f%d: %d command dispatches by monsters (%d by "
      .. "characters); %d of the monster ones had a broken timer running.  "
      .. "%d turns began with the timer up "
      .. "(%d ExecAction, %d ExecRetal), %d of them after running the "
      .. "monster's AI script -- #85's queue purge owes a zero here.  "
      .. "%d dispatches by a broken actor after the kill (the ending), "
      .. "%d not attributable to an entity.",
      won.startFrame, won.deathFrame, monsterCmds + #leaks, charCmds, #leaks,
      (byKind.ExecAction or 0) + (byKind.ExecRetal or 0),
      byKind.ExecAction or 0, byKind.ExecRetal or 0,
      byKind.ExecMonsterAction or 0, #ending, #noEntity))
    -- The positive control.  Without it, a detector that never fired and a
    -- gate that works report the same green.
    H.assertEq(monsterCmds > 0, true,
      "control: inside this same window the ExecCmd detector saw monsters "
      .. "dispatch commands while unbroken, so a count of zero below means "
      .. "the gate held rather than that nothing was watching")
    H.assertEq(#leaks, 0,
      "no monster dispatched a command while its broken timer was running "
      .. "(issue #66: Ot6Gate answers at queue time, and before Ot6MayAct "
      .. "nothing re-checked between the queue entry and the turn)")
    H.assertEq((byKind.ExecMonsterAction or 0) <= 3, true,
      "broken-timer script turns stay near the measured ~1/run rate "
      .. "(the channel is load-bearing for scripted fights -- battle 57; "
      .. "only runaway would mean a new defect)")
  end),
})
