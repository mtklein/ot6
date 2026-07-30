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
-- (ai_script.asm:4551-4562) -- and a break's x2 damage makes dying WHILE
-- Broken the ordinary way that block is reached.  So a Broken gate placed at
-- the top of CheckRetal, which assembles cleanly and reads tidily, strands
-- the ending and soft-locks the boss.  This test kills a Broken Ifrit and
-- requires the fight to end anyway.
--
-- FAIL-BEFORE OBSERVED: built once with the `jsl Ot6MayAct` at CheckRetal's
-- top instead (replacing `lda $3aa0,x / lsr`, which is the size-neutral and
-- therefore tempting placement).  The kill landed, the death script never
-- ran, and this test failed on its battle-ends assertion.  With the gate
-- below the died-branch it passes.  Both states were run; neither is
-- inferred.
--
-- It also asserts the kill really happened while Broken -- otherwise the
-- whole test degrades into "the boss dies", which passes with no gate at
-- all and proves nothing about placement.
local H = dofile("tools/tests/lib/ot6.lua")

local STATE = "build/states/ifrit_doorstep.mss.lua"
local SHIELD_CUR, TICKS = 0x3e38, 0x3e88
local IFRIT, SHIVA = 0x0109, 0x0108
local MENU = 0x7bca
local BREAK_TICKS = 0x10

local function eoff(slot) return 8 + slot * 2 end
local function ticks(e)   return H.readByte(TICKS + e) end
local function mhp(slot)  return H.readWord(0x3bfc + slot * 2) end
local function onfield(slot) return H.readByte(0x3aa8 + slot * 2) & 1 end
local function species(slot) return H.readWord(0x57c0 + slot * 2) end
local function partyAlive()
  for c = 0, 3 do if H.readWord(0x3bf4 + c * 2) > 0 then return true end end
  return false
end

local IE, ISLOT = nil, nil
local deathFrame, deathTicks = nil, nil
local watching = false

-- "the battle ended" is NOT the discriminating observation, and finding that
-- out cost a wrong conclusion: with the gate misplaced the fight still ended,
-- 676 frames SOONER, because killing the only on-stage monster is an ordinary
-- victory.  What must be asserted is that the SCRIPT ran -- CheckRetal sets
-- command $1f and CreateRetalAction queues it (battle_main.asm:12753-12755),
-- ExecRetal dispatches it through ExecAIRetal (:12616), and that is where
-- `if_self_dead` is evaluated.  So: count ExecAIRetal entries for the dead
-- monster after the kill.
local retals = {}
local function armRetalDetector()
  local a = H.sym("ExecAIRetal")
  emu.addMemoryCallback(function()
    retals[#retals + 1] = { f = H.frame, ent = emu.getState()["cpu.x"] & 0xff }
  end, emu.callbackType.exec, a, a)
  H.log(string.format("ExecAIRetal detector armed at $%06X", a))
end

local function sample()
  if not watching or deathFrame then return end
  if mhp(ISLOT) == 0 then
    deathFrame, deathTicks = H.frame, ticks(IE)
    H.log(string.format("IFRIT hp hit 0 at f%d with his broken timer at %d",
      deathFrame, deathTicks))
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
-- past the kill the battle runs its ending: three dialogs then end_battle.
-- Those need A, and the battle menu is gone, so tap unconditionally.
local endStep = {
  H.call(function()
    aPhase = (aPhase + 1) % 8
    H.setPad(aPhase < 4 and { "a" } or {})
  end),
  H.waitFrames(1),
}

H.run({ maxFrames = 40000 }, {
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
    for s = 0, 5 do
      if species(s) == IFRIT and onfield(s) == 1 then ISLOT = s end
    end
    H.assertEq(ISLOT ~= nil, true, "an IFRIT is on the field")
    IE = eoff(ISLOT)
    -- lab: keep the party alive so "the battle ended" can only mean the
    -- script ended it, never a party wipe.
    for c = 0, 3 do H.writeWord(0x3bf4 + c * 2, 900) end
    -- break him, and leave him one good hit from dead
    H.writeByte(SHIELD_CUR + IE, 0)
    H.writeByte(TICKS + IE, BREAK_TICKS)
    H.writeWord(0x3bfc + ISLOT * 2, 12)
    H.log(string.format("staged: ifrit slot %d ($%02X) BROKEN (ticks=%d) with "
      .. "12 hp -- the next landed hit kills him mid-break",
      ISLOT, IE, ticks(IE)))
    armRetalDetector()
    emu.addEventCallback(function() sample() end, emu.eventType.startFrame)
    watching = true
  end),

  H.driveUntil(function() return deathFrame ~= nil end, 12000, fightStep,
    "the party to kill the Broken ifrit"),
  H.call(function()
    H.assertEq(deathTicks ~= 0, true,
      "the kill landed while ifrit was still BROKEN (otherwise this test "
      .. "says nothing about the gate)")
  end),

  -- The whole point: the `if_self_dead` script must still run and end the
  -- fight.  It is three dialogs and an end_battle, so give it room.
  H.driveUntil(function() return not H.battleActive() end, 15000, endStep,
    "the if_self_dead script to end the battle"),
  H.call(function()
    H.setPad({})
    for _, r in ipairs(retals) do
      H.log(string.format("  ExecAIRetal f%-6d ent=$%02X%s", r.f, r.ent,
        (deathFrame and r.f >= deathFrame and r.ent == IE)
          and "   <<== post-kill, the dead ifrit" or ""))
    end
    local postKill = 0
    for _, r in ipairs(retals) do
      if r.f >= deathFrame and r.ent == IE then postKill = postKill + 1 end
    end
    H.assertEq(H.battleActive(), false, "the battle ended")
    H.assertEq(partyAlive(), true,
      "the party survived -- the battle ended by script, not by a wipe")
    H.assertEq(postKill > 0, true,
      "the dead Broken ifrit's AI script RAN (ExecAIRetal after the kill) -- "
      .. "this is `if_self_dead`, the recognition scene and end_battle; a "
      .. "Broken gate placed above CheckRetal's $3a56 died-branch skips it "
      .. "and the fight degrades to an ordinary kill")
    H.log(string.format("battle ended at f%d, %d frames after the Broken kill; "
      .. "%d post-kill AI-retal entries for the dead ifrit",
      H.frame, H.frame - deathFrame, postKill))
    H.screenshot("brokendeath_end")
  end),
})
