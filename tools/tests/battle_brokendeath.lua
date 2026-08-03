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
-- dead Ifrit.  Both builds were run; neither result is inferred.
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
-- reaches the same observation through real play, and the fight is
-- authored to make that possible (bosses-wob.md section 13: Ifrit 6
-- shields, weak ice + piercing; "the first hard absorb lesson"):
--
--   * THE PARTY RE-EQUIPS FIRST, through the real field Equip menu
--     (Equip -> Optimum per character).  The story's own `remove_equip`
--     (event_main.asm:11979-11988, the Vector infiltration) stripped
--     everyone and returned the gear TO INVENTORY (EventCmd_8d), and the
--     mint chain never re-equipped -- so the fixture arrives with LOCKE
--     and CELES bare-handed.  A real player opens the menu before a boss;
--     this drive does exactly that, with pad input only.  Measured on this
--     fixture: Optimum hands Locke and Edgar the ThunderBlades, Celes the
--     MithrilBlade, and armor all around.
--   * THE BREAK IS EARNED: Celes casts Ice (her own natural magic -- the
--     Rune Knight against the elements, exactly the doc's line) and Edgar
--     fires AutoCrossbow (Ot6SkillClassTbl: $aa = OT6_PIERCE), both real
--     menu walks.  Six chips empty Ifrit's authored 6 shields; the broken
--     timer seeds at 16 (observed live, this drive: sh 6->0, tk=16).
--   * THE KILL IS EARNED: the break's own x2 keeps damage ahead of the
--     16-tick recovery -- observed kill at tick 4 of the FIRST break, 8283
--     frames in, with all four party members alive on real HP.  No HP was
--     written on either side of the fight at any point.
--
-- The staging that is GONE is itself now asserted against: shields must
-- read 6/6 at battle start (seeded from level, not pre-cleared) and both
-- HP totals must read their authored 3300/3000 -- the values a staged run
-- could never show.  Same properties proven as before (kill lands while
-- ticks != 0; if_self_dead runs after it; party alive at the end), reached
-- through the game's own mechanics.
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

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F        -- live command rows / cursor cell
local MSCROLL, MCOL, MROW = 0x8913, 0x8917, 0x891B   -- magic-list cursor triple
local TSCROLL, TCOL, TROW = 0x895F, 0x8963, 0x8967   -- tools-shell cursor triple
local ITEMLIST = 0x4005                      -- MakeToolsList's wItemList
local AUTOCROSSBOW = 0xAA
local ICE_REC = 8                            -- master magic list record 8 = Ice ($01)
local ST_CMD, ST_MAGIC, ST_TOOLS = 0x05, 0x0E, 0x30

local ZMENUSTATE, ZCURSOR = 0x26, 0x4B       -- field menu direct-page vars
local ST_MAIN, ST_CHAR, ST_EQUIPOPT = 0x05, 0x06, 0x36
local function st() return H.readByte(ZMENUSTATE) end

local function eoff(m) return 8 + m * 2 end
local function shields(m) return H.readByte(0x3E38 + eoff(m)) end
local function ticks(m)   return H.readByte(0x3E88 + eoff(m)) end
local function mhp(m)     return H.readWord(0x3BFC + m * 2) end
local function onfield(m) return H.readByte(0x3AA8 + m * 2) & 1 end
local function species(m) return H.readWord(0x57C0 + m * 2) end
local function chp(s)     return H.readWord(0x3BF4 + s * 2) end
local function cmp_(s)    return H.readWord(0x3C08 + s * 2) end
local function partyAlive()
  for c = 0, 3 do if chp(c) > 0 then return true end end
  return false
end

-- ---- field menu: Equip -> Optimum for one party slot (real pad walk) ----
local function optimumFor(slotIdx)
  return H.repeatN(1, {
    H.driveUntil(function() return st() == ST_MAIN end, 1200,
      { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu (equip pass)"),
    H.waitFrames(20),
    H.driveUntil(function()
      return st() == ST_MAIN and H.readByte(ZCURSOR) == 2
    end, 600, { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "cursor to Equip"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_CHAR end, 300, "equip char select", 5),
    H.waitFrames(10),
    H.driveUntil(function()
      return st() == ST_CHAR and H.readByte(ZCURSOR) == slotIdx
    end, 600, { H.pressButtons({ "down" }, 2), H.waitFrames(8) },
      "cursor to party slot " .. slotIdx),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_EQUIPOPT end, 300, "equip options", 5),
    H.waitFrames(10),
    -- the option row is HORIZONTAL: Equip / Optimum / Rmove / Empty
    H.driveUntil(function()
      return st() == ST_EQUIPOPT and H.readByte(ZCURSOR) == 1
    end, 600, { H.pressButtons({ "right" }, 2), H.waitFrames(8) }, "cursor to Optimum"),
    H.pressButtons({ "a" }, 2),                -- EquipOptimum runs in place
    H.waitFrames(30),
    (function()
      local calm = 0
      return H.driveUntil(function()
        calm = H.hasControl() and calm + 1 or 0
        return calm >= 10
      end, 2000, { H.pressButtons({ "b" }, 3), H.waitFrames(20) }, "back to field")
    end)(),
  })
end

local slotOf, ISLOT, SSLOT = {}, nil, nil
local deathFrame, deathTicks = nil, nil
local sawBreak = false                        -- shields 0 + timer up, pre-kill
local retals = {}
local xbowIdx = nil

local function rowOf(slot, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + slot * 12 + r * 3) == cmd then return r end
  end
  return nil
end

-- cursor steering for the 2-column battle lists (btlgfx_main UpdateMenuState_0e:
-- scroll+row is the absolute row, col the column; magic maps master record
-- rec to grid cell (rec-1)//2 , (rec-1)%2)
local function magicSeekPad(slot, rec)
  local idx = rec - 1
  local wr, wc = math.floor(idx / 2), idx % 2
  local ar = H.readByte(MSCROLL + slot) + H.readByte(MROW + slot)
  local col = H.readByte(MCOL + slot)
  if ar < wr then return { down = true } end
  if ar > wr then return { up = true } end
  if col < wc then return { right = true } end
  if col > wc then return { left = true } end
  return { a = true }
end
local function toolsSeekPad(slot, idx)
  local wr, wc = math.floor(idx / 2), idx % 2
  local ar = H.readByte(TSCROLL + slot) + H.readByte(TROW + slot)
  local col = H.readByte(TCOL + slot)
  if ar < wr then return { down = true } end
  if ar > wr then return { up = true } end
  if col < wc then return { right = true } end
  if col > wc then return { left = true } end
  return { a = true }
end

-- "the battle ended" is NOT the discriminating observation, and finding that
-- out cost a wrong conclusion: with the gate misplaced the fight still ended,
-- SOONER, because killing the only on-stage monster is an ordinary victory.
-- What must be asserted is that the SCRIPT ran -- CheckRetal sets command
-- $1f and CreateRetalAction queues it (battle_main.asm:12753-12755),
-- ExecRetal dispatches it through ExecAIRetal (:12616), and that is where
-- `if_self_dead` is evaluated.  So: count ExecAIRetal entries for the dead
-- monster after the kill.
local function armRetalDetector()
  local a = H.sym("ExecAIRetal")
  emu.addMemoryCallback(function()
    retals[#retals + 1] = { f = H.frame, ent = emu.getState()["cpu.x"] & 0xff }
  end, emu.callbackType.exec, a, a)
  H.log(string.format("ExecAIRetal detector armed at $%06X", a))
end

H.run({ maxFrames = 90000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 600, "field control", 5),

  -- 1. the player's prep: re-equip the remove_equip'd party, real menus only
  optimumFor(0), optimumFor(1), optimumFor(2), optimumFor(3),

  -- 2. one real A-press into battle 70
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.pressButtons({ "a" }, 4), H.waitFrames(6),
  }, "one A-press -> battle 70"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle 70 active", 30),

  H.call(function()
    H.assertEq(H.formationHas({ [IFRIT] = true, [SHIVA] = true }), true,
      "battle 70: IFRIT and SHIVA in the formation")
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    H.assertEq(slotOf[CELES] ~= nil, true, "CELES present (the Ice chips)")
    H.assertEq(slotOf[EDGAR] ~= nil, true, "EDGAR present (the pierce chips)")
    for m = 5, 0, -1 do                       -- lowest live slot wins (header)
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
    armRetalDetector()
    emu.addEventCallback(function()
      if ISLOT and not deathFrame and mhp(ISLOT) == 0 then
        deathFrame, deathTicks = H.frame, ticks(ISLOT)
        H.log(string.format("IFRIT hp hit 0 at f%d with his broken timer at %d",
          deathFrame, deathTicks))
      end
    end, emu.eventType.startFrame)
  end),

  -- 3. hands OFF until Ifrit takes the stage (the fly-in; input during the
  --    window-open animation wedges the battle menu -- battle_break's lesson)
  H.waitUntil(function() return onfield(ISLOT) == 1 end, 3600,
    "ifrit takes the stage", 10),
  H.waitFrames(90),

  -- 4. the honest fight.  Per open menu: Celes -> Magic -> Ice (ice chip),
  --    Edgar -> Tools -> AutoCrossbow (pierce chip) while Ifrit is up;
  --    everyone else Fights whoever is on stage.  All list cursors are
  --    STEERED against their live RAM, never fire-and-forget.
  (function()
    local ph, n = 0, 0
    return H.driveUntil(function()
      if not sawBreak and shields(ISLOT) == 0 and ticks(ISLOT) ~= 0 then
        sawBreak = true
        H.log(string.format("IFRIT BROKEN at f%d: shields 0, timer %d -- "
          .. "six real chips did this", H.frame, ticks(ISLOT)))
      end
      return deathFrame ~= nil
    end, 60000, {
      H.call(function()
        n = n + 1
        if n % 600 == 0 then
          H.log(string.format(
            "f%d ifr hp=%d sh=%d tk=%d fld=%d | shv hp=%d sh=%d | party %d/%d/%d/%d",
            H.frame, mhp(ISLOT), shields(ISLOT), ticks(ISLOT), onfield(ISLOT),
            mhp(SSLOT), shields(SSLOT), chp(0), chp(1), chp(2), chp(3)))
        end
        ph = (ph + 1) % 8
        local press = ph < 4
        if H.readByte(MENU) == 0 then H.setPad({}); return end
        local slot = H.readByte(ACTOR)
        local charId = H.readByte(0x3ED8 + slot * 2)
        local ms = H.readByte(MSTATE)
        local ifritUp = onfield(ISLOT) == 1
        local pad
        if ms == ST_CMD then
          local want = 0x00                            -- Fight
          if charId == CELES and ifritUp and cmp_(slot) >= 8 then want = 0x02 end
          if charId == EDGAR and ifritUp and cmp_(slot) >= 8 then want = 0x09 end
          local r = rowOf(slot, want)
          local cur = H.readByte(CMDROW + slot)
          if r == nil then pad = { a = true }
          elseif cur < r then pad = { down = true }
          elseif cur > r then pad = { up = true }
          else pad = { a = true } end
        elseif ms == ST_MAGIC then
          pad = magicSeekPad(slot, ICE_REC)
        elseif ms == ST_TOOLS and charId == EDGAR then
          if xbowIdx == nil then
            for i = 0, 7 do
              local id = H.readByte(ITEMLIST + i * 3)
              if id == AUTOCROSSBOW then xbowIdx = i; break end
              if id == 0xFF then break end
            end
          end
          pad = xbowIdx and toolsSeekPad(slot, xbowIdx) or { a = true }
        else
          pad = { a = true }                           -- target select etc.
        end
        H.setPad(press and pad or {})
      end),
      H.waitFrames(1),
    }, "the party to kill the Broken ifrit -- with real chips")
  end)(),
  H.call(function()
    H.assertEq(sawBreak, true,
      "the break was OBSERVED before the kill: shields chipped 6 -> 0 by "
      .. "real Ice casts and AutoCrossbow bolts, timer seeded by the engine")
    H.assertEq(deathTicks ~= 0, true,
      "the kill landed while ifrit was still BROKEN (otherwise this test "
      .. "says nothing about the gate)")
  end),

  -- 5. The whole point: the `if_self_dead` script must still run and end the
  -- fight.  It is three dialogs and an end_battle, so give it room.
  (function()
    local ph = 0
    return H.driveUntil(function() return not H.battleActive() end, 15000, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(ph < 4 and { a = true } or {})
      end),
      H.waitFrames(1),
    }, "the if_self_dead script to end the battle")
  end)(),
  H.call(function()
    H.setPad({})
    for _, r in ipairs(retals) do
      H.log(string.format("  ExecAIRetal f%-6d ent=$%02X%s", r.f, r.ent,
        (deathFrame and r.f >= deathFrame and r.ent == eoff(ISLOT))
          and "   <<== post-kill, the dead ifrit" or ""))
    end
    local postKill = 0
    for _, r in ipairs(retals) do
      if r.f >= deathFrame and r.ent == eoff(ISLOT) then postKill = postKill + 1 end
    end
    H.assertEq(H.battleActive(), false, "the battle ended")
    H.assertEq(partyAlive(), true,
      "the party survived on REAL HP -- the battle ended by script, not by "
      .. "a wipe (and nobody's HP was ever pinned to make that true)")
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
