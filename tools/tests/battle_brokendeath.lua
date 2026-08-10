-- @suite frontier=ifrit_doorstep slow
-- battle_brokendeath.lua -- THE GUARD on where the Broken turn gate may sit.
--
-- Ot6MayAct (ot6_break.asm) refuses a Broken monster's turn at execution
-- time.  One of its two call sites is inside CheckRetal (battle_main.asm),
-- and CheckRetal is not only the counterattack path: an AI script's
-- `if_self_dead` block rides it too, reached through the `bit $3a56`
-- died-branch ($3a56 is "characters/monsters that have died",
-- battle_main.asm:11849).
--
-- Ifrit & Shiva do not end by dying.  They end by a SCRIPT in that block --
-- dlg $1b / restore_monsters / dlg $1c / dlg $1d / end_battle
-- (ai_script.asm:4551-4562) -- and a break's damage multiplier makes dying
-- WHILE Broken the ordinary way that block is reached.  So a Broken gate
-- placed at the top of CheckRetal, which assembles cleanly and reads
-- tidily, strands the ending and soft-locks the boss.  This test kills a
-- Broken boss in battle 70 and requires the fight to end anyway.
--
-- STATUS ON THIS BRANCH: the Broken turn gate is NOT currently applied --
-- it was written, measured, and then reverted because battle_trueknight's
-- 6a assertion cannot survive any growth of bank $C2's battle path (five
-- bare NOPs reproduce that failure exactly; see the revert commit).  So
-- today this test passes without exercising any gate.  It is kept because
-- it is the guard the gate needs the moment it lands, and because the
-- placement mistake it catches is one that was actually made.
--
-- FAIL-BEFORE OBSERVED, on a build that had the gate: with `jsl Ot6MayAct`
-- at CheckRetal's TOP (replacing `lda $3aa0,x / lsr` -- the size-neutral
-- and therefore tempting placement), the kill landed with ZERO post-kill
-- AI-retal entries recorded, and the fight ended early as an ordinary
-- victory with the recognition scene simply gone.  PASS-AFTER OBSERVED
-- with the gate below the died-branch: one post-kill ExecAIRetal for the
-- dead monster.  Both builds were run; neither result is inferred.
--
-- The FIRST version of this test asserted only "the battle ended", and that
-- passed in both placements -- killing the only on-stage monster is an
-- ordinary victory. That is why the assertion below is about ExecAIRetal
-- and not about the battle ending.
--
-- It also asserts the kill really happened while Broken -- otherwise the
-- whole test degrades into "the boss dies", which passes with no gate at
-- all and proves nothing about placement.
--
-- ============================ THE HONEST REBUILD (#75) ====================
-- The previous version of this file STAGED its scenario: it pinned every
-- party member to 900 HP, set Ifrit's shield count to 0 and his broken
-- timer to $10 by direct write, and clamped his HP to 12 so the next landed
-- hit killed him mid-break.  Issue #75's rule -- inputs in, observations
-- out, NEVER write emulated state -- retired all of that.  This version
-- reaches the same observation through real play: the party re-equips
-- through the real field Equip menu (H.equipOptimum -- the fixture arrives
-- with LOCKE and CELES bare-handed, the Vector remove_equip again), and
-- the fight is the library's shared observed-menu fighter.
--
-- The staging that is GONE is itself asserted against: shields must read
-- 6/6 at battle start (seeded from level, not pre-cleared) and both HP
-- totals must read their authored 3300/3000 -- values a staged run could
-- never show.  Same properties proven as before (the kill lands while the
-- victim's broken timer is running; if_self_dead runs after it; the party
-- is alive at the end), reached through the game's own mechanics.
--
-- CORRECTION 2026-08-09, and it replaced the whole drive.  The Aug-06
-- rebuild drove CELES -> Magic -> Ice and EDGAR -> Tools -> AutoCrossbow
-- while Ifrit was on stage, and its header reported a measured win (kill
-- at tick 4 of the first break, f8283).  On the 2026-08-09 ifrit_doorstep
-- re-mint that drive WIPES, reproducibly: party 0/0/0/0 by ~f6300 with
-- Ifrit still at ~3057 hp and 5 of 6 shields.  Traced on the sibling
-- anchored leg (gen_ifrit_magicite), the mechanism is the TAG: the
-- specials were gated on Ifrit being ON STAGE, and in every measured run
-- he took the stage for ~2400 frames, tagged out, and stayed hidden for
-- the next ~7800 while Shiva soaked everything -- she got BROKEN and then
-- RE-SEEDED her shields 0 -> 6 when the break window lapsed, exactly one
-- Ice ever fired (CELES mp 106 -> 101), and a machine with no heal plan
-- died of attrition, identically with and without its menu-idle A-taps
-- (both variants run).  The drive is now H.newFightDriver -- tactical
-- (EDGAR AutoCrossbow, SABIN Pummel), boost banked to 3 and unloaded,
-- real Item heals and Fenix revival -- the configuration that won VARGAS
-- on attempt 1 and battle 70 itself in gen_ifrit_magicite: there, SHIVA
-- was broken at f7158 (sh 6 -> 0, tk=16) and killed INSIDE her own break
-- window at f8637 (tk=5), and her if_self_dead ran the recognition scene.
--
-- The guarded property is monster-agnostic, so the assertions bind to
-- WHICHEVER of the pair dies first: both siblings end the fight through
-- the same if_self_dead ending, the break multiplier makes dying
-- mid-break the ordinary path for either, and the gate placement mistake
-- strands either one equally.  The old Ifrit-only binding was an artifact
-- of the staged lab, not of the property.
--
-- THE RETRY LADDER (gen_tunnelarmr's; measured necessary here 2026-08-09).
-- This fixture's party is a harder start than the anchored leg's -- CELES
-- arrives at 221/349 and the bag is the Vector chain's leavings -- and the
-- first library-fighter run on it fought well (heals and all three Fenix
-- revives landed) and still wiped at phase 0.  The battle RNG seed is the
-- frame phase at battle init (gen_whelk_poweron's measurement), so the
-- test tops the party up through the real field Item menu (H.fieldCare),
-- captures the doorstep as a blob, and replays up to three phase-spread
-- attempts.  An attempt only counts as THE observation when a boss died
-- with its broken timer running; anything else -- a wipe, or a kill that
-- landed after the window lapsed -- reloads and re-rolls.  That is
-- TAS-style setup for the observation, not assertion-weakening: the
-- claims about what must follow a mid-break kill are unchanged.
--
-- Monster slot note: the LIVE monsters sit in battle slots 0 (Ifrit, on
-- stage from the fly-in) and 1 (Shiva, hidden until the tag); the
-- formation table $57c0 repeats both species at slots 2/3 with dead
-- entities behind them, so the slot scan below prefers the LOWEST slot per
-- species -- the earlier "any matching slot" scan picked ghost slot 2 and
-- watched a corpse that never moved.
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/ifrit_doorstep.mss.lua"
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
local fightBlob = nil
local won = nil    -- the winning attempt's observation, once one produces it

-- a bare step list cannot be spliced into a step list; H.cond with an
-- always-true predicate is the library's public way to wrap one into a step
local function seq(steps) return H.cond(function() return true end, steps) end

-- "the battle ended" is NOT the discriminating observation, and finding that
-- out cost a wrong conclusion: with the gate misplaced the fight still ended,
-- SOONER, because killing the only on-stage monster is an ordinary victory.
-- What must be asserted is that the SCRIPT ran -- CheckRetal sets command
-- $1f and CreateRetalAction queues it (battle_main.asm:12753-12755),
-- ExecRetal dispatches it through ExecAIRetal (:12616), and that is where
-- `if_self_dead` is evaluated.  So: count ExecAIRetal entries for the dead
-- monster after the kill.  Armed once; frame numbers only rise across the
-- ladder's reloads, so entries from a lost attempt can never satisfy the
-- winning attempt's `f >= deathFrame` filter.
local function armRetalDetector()
  if detectorArmed then return end
  detectorArmed = true
  local a = H.sym("ExecAIRetal")
  emu.addMemoryCallback(function()
    retals[#retals + 1] = { f = H.frame, ent = emu.getState()["cpu.x"] & 0xff }
  end, emu.callbackType.exec, a, a)
  H.log(string.format("ExecAIRetal detector armed at $%06X", a))
end

-- One attempt, flat (driveUntil bodies replay latched state, so every
-- attempt builds fresh closures).  Attempt 1 runs in place -- the live
-- timeline IS the blob's timeline; later attempts reload the doorstep blob
-- and shift the RNG phase.  An attempt records into `won` only when a boss
-- died WITH ITS BROKEN TIMER RUNNING and the break was watched happen.
local function attempt(n)
  local loadReq
  local ISLOT, SSLOT = nil, nil
  local sawBreak = {}              -- [slot] = first frame shields 0 + timer up
  local deathSlot, deathFrame, deathTicks = nil, nil, nil
  local hb = 0
  local F = H.newFightDriver("brokendeath", { tactical = true, boost = true,
    bank = 3, items = true, healPercent = 60, cadence = 12 })
  local function mname(m)
    return m == ISLOT and "IFRIT" or m == SSLOT and "SHIVA" or ("slot " .. m)
  end
  return H.cond(function() return won ~= nil end, {}, {
    H.logStep(function()
      return string.format("battle 70 attempt %d (phase offset %d) at f%d",
        n, (n - 1) * 37, H.frame)
    end),
    n > 1 and seq({
      H.call(function() loadReq = H.requestLoadState(fightBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "doorstep blob reload") end),
      H.waitFrames(90),
      H.call(function()
        H.assertEq(H.hasControl(), true, "reloaded controllable at the doorstep")
      end),
    }) or seq({}),
    H.waitFrames((n - 1) * 37),          -- vary the battle RNG seed

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
      -- NO-STAGING CONTROLS: the lab this file used to build is gone, and a
      -- relapse would show here.  Both gauges seed FULL and both HP words
      -- read their authored values (break-band-vector.md:232 / bosses-wob 13).
      H.assertEq(shields(ISLOT), 6, "ifrit opens with his authored 6 shields")
      H.assertEq(shields(SSLOT), 6, "shiva opens with her authored 6 shields")
      H.assertEq(mhp(ISLOT), 3300, "ifrit opens at his authored 3300 HP (no clamp)")
      H.assertEq(mhp(SSLOT), 3000, "shiva opens at her authored 3000 HP (no clamp)")
      H.assertEq(ticks(ISLOT), 0, "ifrit is NOT pre-broken")
      H.assertEq(ticks(SSLOT), 0, "shiva is NOT pre-broken")
      armRetalDetector()
    end),

    -- hands OFF until Ifrit takes the stage (the fly-in; input during the
    -- window-open animation wedges the battle menu -- battle_break's lesson)
    H.waitUntil(function() return onfield(ISLOT) == 1 end, 3600,
      "ifrit takes the stage", 10),
    H.waitFrames(90),

    -- the honest fight: the library fighter, gauges logged around it.  Its
    -- menu==0 branch also pages the recognition scene's dialogs and the
    -- victory teardown, so this one drive carries the battle from fly-in
    -- to field (or through the Annihilated screen, on a loss).
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

    -- evaluate: this attempt is THE observation only if a boss died with
    -- its broken timer running and the break was watched happen first
    H.call(function()
      H.setPad({})
      if deathFrame and deathTicks ~= 0 and sawBreak[deathSlot] then
        won = { slot = deathSlot, name = mname(deathSlot),
                deathFrame = deathFrame, deathTicks = deathTicks,
                breakFrame = sawBreak[deathSlot], endFrame = H.frame,
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

  -- 1. the player's prep, all through real menus: re-equip the
  --    remove_equip'd party (H.equipOptimum -- the library factoring of
  --    the hand-rolled walk this file used to carry), then top up HP with
  --    the bag's own items (H.fieldCare) -- this fixture delivers CELES
  --    at 221/349, and the first ladder-less run wiped from that deficit
  H.equipOptimum({ tag = "brokendeath kit" }),
  H.fieldCare({ tag = "care before battle 70", threshold = 0.95 }),

  -- 2. capture the prepared doorstep as the retry ladder's reload blob
  (function()
    local req
    return seq({
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "doorstep retry blob")
        fightBlob = req.blob
        H.log(string.format("retry blob captured: %d bytes", #fightBlob))
      end),
    })
  end)(),

  -- 3. the fight, on the phase-spread ladder
  attempt(1),
  attempt(2),
  attempt(3),

  -- 4. The whole point: a mid-break kill happened, and the `if_self_dead`
  -- script still ran and ended the fight.
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
})
