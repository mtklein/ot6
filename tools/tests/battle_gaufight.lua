-- @suite frontier=gau_joined slow
-- battle_gaufight.lua -- issue #47: GAU HAS A FREE ACTION, IN BOTH TERRITORIES.
--
-- THE HOLE.  Vanilla gives Gau four command slots and no Fight among them:
-- RAGE / LEAP / MAGIC / ITEM (char_prop.asm, record 11).  The third row LOOKS
-- empty in vanilla only because InitCmd_03 removes MAGIC from a character who
-- knows no spells (battle_main.asm), and off the Veldt InitCmd_01 removes LEAP
-- as well -- so the real menu a v0.7 player saw was RAGE / - / - / ITEM.  That
-- was survivable while Rage was free.  It is not survivable now that Rage
-- costs a flat 8 MP (#40): an out-of-MP Gau had literally no action to take,
-- and mp-economy.md's stated target -- "Fight must sometimes be the right
-- move" -- requires that every character be able to DECLINE to spend.
--
-- THE FIX: Gau now carries FIGHT / RAGE / MAGIC / ITEM, and LEAP SHARES THE
-- FIGHT ROW (owner reversal 2026-07-29 -- on the Veldt Leap IS the free
-- action, so Fight is the row that can afford to share; Magic must never be
-- the sacrificed row):
--
--      on the Veldt:     LEAP  / RAGE / MAGIC / ITEM
--      everywhere else:  FIGHT / RAGE / MAGIC / ITEM
--
-- THE MECHANISM.  Ot6VeldtRow (battle_main.asm), called from InitCmdList's own
-- row loop; the row it writes is $11, which is in InitCmdIDTbl, so Leap's own
-- vanilla availability test (InitCmd_01) runs on it for free.
--
-- ISSUE #75 CONVERSION.  All the staging is gone: no monster stop bits, no
-- HP floors, no bench-wounding, no berserk/row-blank/ATB-hurry lab, no rage
-- cursor pokes.  Battle A is entirely natural (the trance's survivability
-- comes from CHOOSING the draw: unsuitable formations are resolved -- fled,
-- or won through the real menus when the Veldt roster deals an unrunnable
-- set-piece formation, a measured hazard -- and the walk resumes).  The
-- bench is parked with X, vanilla's own turn-cycling key, which also makes
-- arm 4's claim SHARP: focus is actively cycled all trance long and must
-- never land on Gau.  Arm 2's Fight is picked from the REAL menu.
--
-- *** ONE LABELED ISOLATION ARM (issue #75) -- one write site STAYS ***
-- THE OFF-VELDT VERDICT (arms 1d/2/3) CANNOT BE REACHED BY GEOGRAPHY from
-- any generated fixture: gau_joined's entire walkable component was enumerated
-- live (2026-08-10, BFS over worldPassable from (214,149)) -- 1239 tiles
-- spanning exactly three 32x32 sectors, and WorldBattleGroup reads $ff
-- (Veldt) for all three; the component is walled by Crescent Mountain and
-- the sea, and no other fixture fields Gau at all (sabin_done is the bare
-- scenario hub).  "Walk off the Veldt" is therefore IMPOSSIBLE from the
-- input-driven tree today, and battle B keeps the burn-down plan's instrumented
-- bit as a loudly-labeled isolation arm: an exec callback on InitCmdList
-- clears $11e4 bit 1 at the exact moment the code under test reads it (the
-- callback COUNTS its firings and asserts the bit really was set, so it
-- cannot be vacuous), and the bit is restored the moment the lists are
-- read.  It MAY NEVER PRODUCE FIXTURES; it converts organically when the
-- chain crosses the Serpent Trench and generates a world-side Gau fixture off
-- the Veldt.  This is the file's only write site (.writeByte( waiver).
--
-- Asserted:
--   1a. THE SAVE RECORD, unpoked: $00 $10 $02 $01 -- FIGHT / RAGE / MAGIC /
--      ITEM, read straight out of the character record at $1616+$3010[slot].
--      FAILS PRE-#47: the record reads $10 $11 $02 $01 and holds no $00.
--   1b. THE BUILT LIST, ON THE VELDT (battle A, natural).  Row 0 is LEAP --
--      the SHARED row, asserted as the rule: LEAP when $11e4 bit 1 is set,
--      else FIGHT.  Row 1 RAGE, row 2 MAGIC's own vanilla verdict (removed,
--      no spells), row 3 ITEM.
--   1c. THE NEGATIVE CONTROL: SABIN and CYAN keep FIGHT in row 0 and carry
--      LEAP nowhere -- the substitution is CHAR::GAU-gated.
--   1d. THE BUILT LIST, OFF THE VELDT (battle B, the labeled arm's one
--      instrumented bit).  Row 0 is FIGHT; rows 1-3 unchanged; the save
--      record re-read and byte-identical to 1a -- the SAME data, a
--      different verdict, which is what "shared row" has to mean.
--   2. FIGHT EXECUTES AND CARRIES A REAL WEAPON CLASS (battle B, where row
--      0 really is Fight): picked through the live $7BC2 menu, target
--      steered onto the monster side, the bench deferred with X so every
--      monster HP drop is Gau's.  OT6_ATKCLASS ($57b8) reads OT6_BLUDG and
--      ONLY OT6_BLUDG for the window -- Gau equips nothing at join and
--      Ot6WeapClassTbl[$ff] is OT6_BLUDG: bare fists are a bludgeoning
--      probe, through the same per-swing $3ca8 hand lookup as everyone.
--   3. THE SHIELD LEDGER AGREES WITH THE CLASS: the body he hit is MEASURED
--      (whoever lost HP), and its shield counter moves iff its class-
--      weakness byte carries bludgeoning -- both ways.
--   4. RAGE POSSESSION IS UNAFFECTED (battle A): rage started from row 1 of
--      the real menu, the window's cursor STEERED to entry 0 by d-pad
--      against the live cursor cells (no pokes), the RAGE status latches,
--      Cmd_10 re-enters on its own >= 3 times, and the actively-X-cycled
--      focus never once lands on Gau -- CheckPlayerAction's STATUS34
--      {DANCE, HIDE, RAGE} gate holds.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/gau_joined.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TGT = 0x05, 0x38
local GAU = 0x0B
local CMD_FIGHT, CMD_RAGE, CMD_ITEM, CMD_NONE = 0x00, 0x10, 0x01, 0xFF
local CMD_MAGIC = 0x02
local CMD_LEAP = 0x11
local VELDT = 0x11E4                  -- bit 1 = the flag InitCmd_01 reads
local ATKCLASS = 0x57B8               -- OT6_ATKCLASS (ot6_memory.inc:85)
local OT6_BLUDG = 0x04                -- ot6_class.asm:12
local ST_RAGE = 0x1E                  -- the rage window's battle menu state

local function CMDROW(slot, row) return 0x202E + slot * 12 + row * 3 end
local function MHP(m)   return 0x3BFC + m * 2 end
local function ST4(e)   return 0x3EF9 + e end
local function SHIELD(e) return 0x3E38 + e end   -- OT6_SHIELD_CUR
local function CLSWEAK(e) return 0x3E9C + e end  -- authored class weakness
local function CURMP(s) return 0x3C08 + s * 2 end

local gauSlot, msPresent = nil, {}
local classWrites, cmd10Hits, gauMenus = {}, 0, 0
local saveRecA = nil                  -- battle A's read of the save record
local veldtCleared = 0                -- battle B: times the instrument fired

-- Gau's four command bytes AS THE SAVE HOLDS THEM (InitCmdList's own two
-- lines: `ldy $3010,x` then `lda $1616,y`).
local function saveRecord(slot)
  local ptr = H.readWord(0x3010 + slot * 2)
  local r = {}
  for i = 0, 3 do r[i] = H.readByte(0x1616 + ptr + i) end
  return r
end

local function rowsOf(slot)
  local r = {}
  for i = 0, 3 do r[i] = H.readByte(CMDROW(slot, i)) end
  return r
end

local function tap(btn, gap)
  return H.repeatN(1, {
    H.pressButtons({ btn }, 4),
    H.waitFrames(gap or 16),
  })
end

-- gen_sabin_gau's own Veldt-grind pacing: alternate left/right at tile
-- boundaries until the world's own encounter roll wins.  No danger poke.
local function walkIntoEncounter(what)
  local flip = false
  return {
    H.waitUntil(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned()
    end, 6000, what .. ": world control on the Veldt"),
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        if H.battleLoadStarted() then H.setPad({}) return end
        if not H.worldHasControl() then H.setPad({}) return end
        if not H.worldAligned() then return end
        flip = not flip
        H.setPad({ [flip and "left" or "right"] = true })
      end),
    }, what .. ": a Veldt encounter fires"),
    H.call(function() H.setPad({}) end),
    H.waitUntil(function() return H.battleActive() end, 1200,
      what .. ": battle armed", 5),
    -- 90 frames is after InitChars/InitCmdList and BEFORE the first
    -- command window opens.
    H.waitFrames(90),
  }
end

-- resolve an unwanted battle: flee (L+R), and when the Veldt roster deals
-- an unrunnable set-piece formation (measured 2026-08-10: the fled Guard
-- formation from Sabin's own scripted fights timed a 9000-frame L+R hold
-- out), fall back to winning it through the real menus.
local function resolveBattle(tag)
  local n, F = 0, nil
  return H.repeatN(1, {
    H.driveUntil(function() return not H.battleLoadStarted() end, 30000, {
      H.call(function()
        n = n + 1
        if n < 1200 then
          H.setPad({ l = true, r = true })
        else
          if not F then
            F = H.newFightDriver(tag .. "-win")
            H.log(tag .. ": flee stalled (unrunnable roster draw) -- "
              .. "winning it through the menus instead")
          end
          F.frame()
        end
      end),
    }, tag .. ": unwanted battle resolved"),
    H.call(function() H.setPad({}) end),
    H.waitFrames(30),
  })
end

-- find Gau, enumerate the bodies.  Shared by both battles.  READS ONLY.
local function surveyBattle()
  gauSlot, msPresent = nil, {}
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) == GAU then gauSlot = s end
  end
  assert(gauSlot, "GAU is in the battle party (the s2/sabin chain seats him)")
  for m = 0, 5 do
    if H.readByte(0x3AA8 + m * 2) % 2 == 1 then msPresent[#msPresent + 1] = m end
  end
  assert(#msPresent > 0, "the encounter has monsters")
end

local function monsterHpTotal()
  local t = 0
  for _, m in ipairs(msPresent) do t = t + H.readWord(MHP(m)) end
  return t
end

-- X-defer any non-Gau menu (vanilla's turn-cycling key); nothing else.
local function deferBench()
  if H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) ~= gauSlot then
    if H.readByte(MSTATE) == ST_CMD then H.setPad({ x = true })
    else H.setPad({ b = true }) end
    return true
  end
  return false
end

-- wait for GAU's own menu, X-cycling the bench out of the way.
local function menuForGau(what)
  local ph = 0
  return H.driveUntil(function()
    return H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) == gauSlot
  end, 20000, {
    H.call(function()
      ph = ph + 1
      if ph % 8 < 4 then
        if not deferBench() then H.setPad({}) end
      else
        H.setPad({})
      end
    end),
    H.waitFrames(2),
  }, what)
end

local hpPre, shieldPre = {}, {}

local steps = {}
local function add(list) for _, s in ipairs(list) do steps[#steps + 1] = s end end

add({
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(H.worldX(), 214, "fixture parked at world x=214")
    H.assertEq(H.worldY(), 149, "fixture parked at world y=149")
  end),
})

-- ============================================================== BATTLE A ==
-- Entirely natural, ON the Veldt.  The draw is CHOSEN for the trance: the
-- ride needs the fight alive for >= 3 possessed turns, so a draw under 500
-- total monster HP is resolved and re-walked (measured pool: 3x $02f = 729
-- and $038+$039 = 432 recur; trash draws run 107).  Nothing is poked in any
-- draw -- selection is play.
add({ H.call(function() H.vars.suitable = false end) })
for n = 1, 6 do
  local w = {}
  for _, s in ipairs(walkIntoEncounter("battle A draw " .. n)) do w[#w + 1] = s end
  w[#w + 1] = H.call(function()
    surveyBattle()
    local total = monsterHpTotal()
    H.vars.suitable = (#msPresent >= 2 and total >= 500)
    H.log(string.format("battle A draw %d: %d bodies, %d total HP -> %s",
      n, #msPresent, total, H.vars.suitable and "FIGHT" or "resolve"))
  end)
  w[#w + 1] = H.cond(function() return not H.vars.suitable end,
    { resolveBattle("battle A draw " .. n) }, {})
  if n == 1 then add(w)
  else add({ H.cond(function() return not H.vars.suitable end, w, {}) }) end
end
add({
  H.call(function()
    H.assertEq(H.vars.suitable, true,
      "the Veldt dealt a trance-sized formation within six draws")
  end),
})

-- -------- 1a/1b/1c. THE SAVE RECORD, THE VELDT LIST, AND THE GAU GATE ------
add({
  H.call(function()
    local onVeldt = (H.readByte(VELDT) & 0x02) ~= 0
    local rows = rowsOf(gauSlot)
    saveRecA = saveRecord(gauSlot)
    H.log(string.format("[battle A / gau slot %d] save record = %02X %02X %02X "
      .. "%02X", gauSlot, saveRecA[0], saveRecA[1], saveRecA[2], saveRecA[3]))
    H.log(string.format("[battle A / gau slot %d] rows = %02X %02X %02X %02X  "
      .. "MP=%d  $11e4=%02X (veldt=%s)", gauSlot, rows[0], rows[1], rows[2],
      rows[3], H.readWord(CURMP(gauSlot)), H.readByte(VELDT), tostring(onVeldt)))

    -- 1a. the per-save data itself, unpoked
    H.assertEq(saveRecA[0], CMD_FIGHT,
      "save record slot 0 is FIGHT -- the free action Gau never had (#47), "
      .. "copied into the character record by his own join event; pre-#47 this "
      .. "byte was $10 RAGE and the record held no $00 anywhere")
    H.assertEq(saveRecA[1], CMD_RAGE, "save record slot 1 is RAGE")
    H.assertEq(saveRecA[2], CMD_MAGIC,
      "save record slot 2 is MAGIC -- and it STAYS magic in the record; the "
      .. "sharing is a runtime verdict on the FIGHT row, not a rewrite of the "
      .. "save")
    H.assertEq(saveRecA[3], CMD_ITEM, "save record slot 3 is ITEM")

    -- 1b. the built list, on the Veldt.  The rule, not a constant.
    H.assertEq(onVeldt, true,
      "positive control: the fixture really is standing on a Veldt sector, so "
      .. "the substitution below is exercised rather than merely not-fired "
      .. "($11e4 |= $02, field/battle.asm:141)")
    H.assertEq(rows[0], onVeldt and CMD_LEAP or CMD_FIGHT, string.format(
      "row 0 is the SHARED row and follows the rule, not a constant: the Veldt "
      .. "flag $11e4 reads $%02X, so this row belongs to %s",
      H.readByte(VELDT), onVeldt and "LEAP" or "FIGHT"))
    H.assertEq(rows[1], CMD_RAGE, "row 1 is RAGE -- the kit verb keeps a row")
    H.assertEq(rows[2], CMD_NONE,
      "row 2 is MAGIC's own untouched vanilla verdict -- removed ($ff), "
      .. "because this Gau knows no spells and InitCmd_03 is back to exact "
      .. "vanilla")
    H.assertEq(rows[3], CMD_ITEM, "row 3 is ITEM -- the free floor is intact")

    -- 1c. the negative control: the substitution is CHAR::GAU-gated.
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF and s ~= gauSlot then
        local other = rowsOf(s)
        H.log(string.format("[slot %d] actor $%02X rows = %02X %02X %02X %02X",
          s, id, other[0], other[1], other[2], other[3]))
        H.assertEq(other[0], CMD_FIGHT, string.format(
          "actor $%02X still leads with FIGHT -- his row 0 was NOT substituted "
          .. "even though we are standing on the Veldt", id))
        local anyLeap = false
        for i = 0, 3 do if other[i] == CMD_LEAP then anyLeap = true end end
        H.assertEq(anyLeap, false, string.format(
          "actor $%02X got Gau's Veldt Leap on NO row", id))
      end
    end
  end),
})

-- ----------------------------------- 4. RAGE POSSESSION IS UNAFFECTED --
add({
  H.waitFrames(60),
  menuForGau("gau_menu_for_rage"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readWord(CURMP(gauSlot)) >= 8, true, string.format(
      "positive control: Gau's own save MP can afford the flat-8 trance "
      .. "(got %d)", H.readWord(CURMP(gauSlot))))
    H.assertEq(H.readByte(0x3A9A) > 0, true,
      "positive control: the fixture's Gau has learned at least one rage")
    emu.addMemoryCallback(function() cmd10Hits = cmd10Hits + 1 end,
      emu.callbackType.exec, H.sym("Cmd_10"), H.sym("Cmd_10"))
  end),
  tap("down", 24),                  -- row 0 (the shared row) -> row 1 Rage
  H.driveUntil(function() return H.readByte(MSTATE) == ST_RAGE end, 1500, {
    H.call(function() H.setPad({ a = true }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the rage window opens from row 1"),
  -- STEER the rage window's cursor to entry 0 with the d-pad against the
  -- live cursor cells (scroll $892b / col $892f / row $8933 indexed by the
  -- actor slot -- _c18438, btlgfx_main.asm:20096-20111).  This replaces the
  -- old three cursor pokes: same triple, read instead of written.
  H.driveUntil(function()
    return H.readByte(MSTATE) == ST_RAGE
       and H.readByte(0x892B + gauSlot) + H.readByte(0x8933 + gauSlot) == 0
       and H.readByte(0x892F + gauSlot) == 0
  end, 1500, {
    H.call(function()
      if H.readByte(MSTATE) ~= ST_RAGE then H.setPad({}); return end
      if H.readByte(0x892F + gauSlot) > 0 then H.setPad({ left = true })
      elseif H.readByte(0x892B + gauSlot) + H.readByte(0x8933 + gauSlot) > 0
        then H.setPad({ up = true })
      else H.setPad({}) end
    end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(8),
  }, "rage cursor steered to entry 0 (d-pad, no pokes)"),
  H.call(function() cmd10Hits, gauMenus = 0, 0 end),
  H.driveUntil(function()
    return (H.readByte(ST4(gauSlot * 2)) & 0x01) ~= 0
  end, 4000, {
    H.call(function()
      -- press A on ANY window Gau still has open: the rage list ($1e) hands
      -- off to a follow-up state ($38) that also waits on a confirm.
      H.setPad((H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) == gauSlot)
               and { a = true } or {})
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(16),
  }, "the RAGE status latches (Cmd_10 ran)"),
  H.call(function() gauMenus = 0 end),   -- count openings from the trance on
  -- ride the trance: the bench is actively X-CYCLED, so if the four-row
  -- menu ever offered a possessed Gau a window, the cycling would land
  -- focus on him and the counter below would catch it.
  H.repeatN(150, {
    H.call(function()
      if H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) == gauSlot then
        gauMenus = gauMenus + 1
      end
      if not deferBench() then H.setPad({}) end
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(6),
  }),
  H.call(function()
    H.log(string.format("[trance] cmd10=%d gau menu openings=%d raging=%s "
      .. "monstersLeft=%d", cmd10Hits, gauMenus,
      tostring((H.readByte(ST4(gauSlot * 2)) & 0x01) ~= 0),
      H.monstersPresent()))
    H.assertEq((H.readByte(ST4(gauSlot * 2)) & 0x01) ~= 0, true,
      "still possessed after riding the trance")
    H.assertEq(cmd10Hits >= 3, true, string.format(
      "the trance really took several turns on its own (Cmd_10 re-entered %d "
      .. "times) -- without this count the claim below is vacuous", cmd10Hits))
    H.assertEq(gauMenus, 0,
      "the four-row menu did not give a possessed Gau a menu: "
      .. "CheckPlayerAction's STATUS34 {DANCE,HIDE,RAGE} gate still refuses to "
      .. "open one, so his command list -- the shared row included -- is "
      .. "IRRELEVANT mid-trance, which is what 'unaffected' has to mean")
    H.screenshot("gau_veldt_row")
  end),
})

-- ============================================================== BATTLE B ==
-- *** LABELED ISOLATION ARM (issue #75) -- see the header. ***  A FRESH
-- load, with one bit instrumented at the exact moment the code under test
-- reads it, because the off-Veldt verdict is unreachable by geography from
-- the generated tree (the component enumeration in the header).
add({
  H.loadState(STATE),
  H.waitFrames(20),
  H.call(function()
    veldtCleared = 0
    emu.addMemoryCallback(function()
      local v = H.readByte(VELDT)
      if (v & 0x02) ~= 0 then
        H.writeByte(VELDT, v & 0xFD)          -- THE arm's write (header)
        veldtCleared = veldtCleared + 1
      end
    end, emu.callbackType.exec, H.sym("InitCmdList"), H.sym("InitCmdList"))
    H.log("[isolation arm] battle B armed: $11e4 bit 1 cleared at "
      .. "InitCmdList's entry")
  end),
})
add(walkIntoEncounter("battle B"))

-- --------------------- 1d. THE BUILT LIST, OFF THE VELDT -------------------
add({
  H.call(function()
    surveyBattle()

    local rows = rowsOf(gauSlot)
    local rec = saveRecord(gauSlot)
    H.log(string.format("[battle B / gau slot %d] rows = %02X %02X %02X %02X  "
      .. "$11e4=%02X  instrument fired %d time(s)", gauSlot, rows[0], rows[1],
      rows[2], rows[3], H.readByte(VELDT), veldtCleared))

    H.assertEq(veldtCleared > 0, true,
      "the instrument actually did something: $11e4 bit 1 was SET when "
      .. "InitCmdList ran (a Veldt sector, exactly as in battle A) and this "
      .. "callback cleared it.  Without this count arm 1d would pass vacuously")
    H.assertEq(H.readByte(VELDT) & 0x02, 0,
      "and the bit is still clear now, so the list below was built off-Veldt")

    for i = 0, 3 do
      H.assertEq(rec[i], saveRecA[i], string.format(
        "the save record is byte-identical to battle A at slot %d ($%02X): the "
        .. "SAME data, and only the verdict on it changes", i, rec[i]))
    end

    H.assertEq(rows[0], CMD_FIGHT,
      "row 0 is FIGHT off the Veldt -- the free action, in the territory "
      .. "where Leap would have been refused by InitCmd_01 anyway.  Battle A "
      .. "read $11 LEAP out of this same save byte, one Veldt bit ago")
    H.assertEq(rows[1], CMD_RAGE, "row 1 is still RAGE")
    H.assertEq(rows[2], CMD_NONE, "row 2 is still MAGIC's own vanilla verdict")
    H.assertEq(rows[3], CMD_ITEM, "row 3 is still ITEM")

    -- restore the bit: from here on this is an ordinary Veldt battle again,
    -- and arms 2/3 do not care either way.
    H.writeByte(VELDT, H.readByte(VELDT) | 0x02)

    -- arms 2/3 observe through the real menu now -- no berserk, no row
    -- blanking, no ATB hurry, no bench wounds.  The class byte watch:
    emu.addMemoryCallback(function(_, v)
      classWrites[#classWrites + 1] = v
    end, emu.callbackType.write, 0x7E0000 + ATKCLASS, 0x7E0000 + ATKCLASS)
  end),
})

-- ------------------------- 2/3. FIGHT swings, chips, and carries a class --
add({
  H.call(function()
    hpPre, shieldPre = {}, {}
    for _, m in ipairs(msPresent) do
      local e = 8 + m * 2
      hpPre[m] = H.readWord(MHP(m))
      shieldPre[m] = H.readByte(SHIELD(e))
    end
    classWrites = {}
    H.log(string.format("[pre-fight] bodies=%d gau slot %d fights from the "
      .. "real menu", #msPresent, gauSlot))
  end),
  -- Gau's Fight, picked from the real four-row menu: cursor to row 0, A,
  -- then the target cursor steered onto the MONSTER side before confirming
  -- (the old menu drive confirmed blind and punched Gau himself -- measured;
  -- $7b7e is the monster-side target mask the cursor state exposes).
  H.driveUntil(function()
    for _, m in ipairs(msPresent) do
      if H.readWord(MHP(m)) < hpPre[m] then return true end
    end
    return false
  end, 12000, {
    H.call(function()
      if H.readByte(MENU) == 0 then H.setPad({}); return end
      if deferBench() then return end
      local st = H.readByte(MSTATE)
      if st == ST_CMD then
        local cur = H.readByte(0x890F + gauSlot) & 3
        H.setPad(cur == 0 and { a = true } or { up = true })
      elseif st == ST_TGT then
        H.setPad(H.readByte(0x7B7E) ~= 0 and { a = true } or { left = true })
      else
        H.setPad({})
      end
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(6),
  }, "Gau's real-menu Fight lands damage on a monster"),
  H.waitFrames(60),                 -- let the chip/reveal frame settle
  H.call(function()
    local seen = {}
    for _, v in ipairs(classWrites) do seen[v] = true end
    local hit = {}
    for _, m in ipairs(msPresent) do
      local e = 8 + m * 2
      local dmg = hpPre[m] - H.readWord(MHP(m))
      local sh = H.readByte(SHIELD(e))
      H.log(string.format("[post-fight] body %d: dmg=%d shield %d->%d "
        .. "clsweak=%02X", m, dmg, shieldPre[m], sh, H.readByte(CLSWEAK(e))))
      if dmg > 0 then hit[#hit + 1] = m end
    end
    H.log(string.format("[post-fight] atkclass writes=%d", #classWrites))

    H.assertEq(#hit > 0, true,
      "Gau's Fight actually dealt damage -- an out-of-MP Gau now has a turn, "
      .. "and with the bench X-deferred this damage can only be his")
    H.assertEq(seen[OT6_BLUDG] or false, true,
      "the swing resolved a REAL weapon class: OT6_ATKCLASS took OT6_BLUDG "
      .. "($04) off the empty-hand row of Ot6WeapClassTbl -- bare fists are "
      .. "his probe")
    H.assertEq(#classWrites > 0 and seen[OT6_BLUDG]
               and not seen[0x01] and not seen[0x02] and not seen[0x08], true,
      "and it resolved ONLY bludgeoning: with the bench deferred, nothing "
      .. "else was loading an attack class into the window")

    -- the ledger and the class must agree, both ways, on the body he hit
    for _, m in ipairs(hit) do
      local e = 8 + m * 2
      local weak = H.readByte(CLSWEAK(e))
      local chipped = H.readByte(SHIELD(e)) < shieldPre[m]
      H.assertEq(chipped, (weak & OT6_BLUDG) ~= 0, string.format(
        "body %d's shield ledger agrees with the class: class-weakness $%02X, "
        .. "shield %d -> %d.  A bludgeoning probe chips a bludgeon-weak body "
        .. "and nothing else (Ot6ClassChip, ot6_break.asm)",
        m, weak, shieldPre[m], H.readByte(SHIELD(e))))
    end
    H.screenshot("gau_fight")
  end),
})

H.run({ maxFrames = 300000 }, steps)
