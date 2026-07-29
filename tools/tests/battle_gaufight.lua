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
-- move" -- requires that every character be able to DECLINE to spend.  Every
-- other character could; he could not.
--
-- THE FIX, and the thing that makes it interesting: there is no spare slot.
-- Gau now carries FIGHT / RAGE / MAGIC / ITEM, and LEAP SHARES THE FIGHT ROW.
--
-- WHICH ROW LEAP SHARES WAS REVERSED, 2026-07-29 (owner).  The first build put
-- Leap on the MAGIC row, reasoning that the Veldt is where Gau spends the most
-- turns and so is where losing the free action would hurt most.  That reads
-- the Veldt backwards.  On the Veldt you can always just Leap -- Leap is the
-- free thing to do there, and is the whole reason Gau is standing on the Veldt
-- at all -- so FIGHT and LEAP are the redundant pair there and sharing them
-- costs nothing.  MAGIC is the row you might want in BOTH places, so Magic
-- must never be the row sacrificed.  The layout under test:
--
--      on the Veldt:     LEAP  / RAGE / MAGIC / ITEM
--      everywhere else:  FIGHT / RAGE / MAGIC / ITEM
--
-- and Magic is now never lost anywhere, which is strictly better than what the
-- magic-row version shipped.
--
-- AND LEAP IS FREE (owner, same day).  #40 had priced it at a flat 2 MP.  With
-- Leap sitting IN the Fight row, a priced Leap would have re-opened the very
-- hole #47 exists to close, in the one territory Gau lives in.  The price
-- itself is battle_rage.lua §9's measurement (0 MP, and a 0-MP Gau still
-- leaps); this file only asserts the rows.
--
-- THE MECHANISM.  Ot6VeldtRow (battle_main.asm), called from InitCmdList's own
-- row loop -- NOT from an init function, because FIGHT ($00) has no init
-- function at all (InitCmdIDTbl lists only morph/leap/dance/magic/x-magic/
-- lore).  Running in the loop means it runs BEFORE the relic pass, so Dragoon
-- Boots cannot silently replace a Veldt Leap with Jump; and the row it writes
-- is $11, which IS in InitCmdIDTbl, so Leap's own vanilla availability test
-- (InitCmd_01) runs on it for free.  InitCmd_03/04 are back to exact vanilla,
-- so nothing about the has-mp flag $f8 is touched by any of this.
--
-- WHY A NATURAL BOOT.  The commands are per-SAVE data: CharProp is copied into
-- the character record when the join event runs (field/event.asm:1039-1046),
-- and battle reads them from $1616,y, not from the ROM table (InitCmdList).  A
-- poked-in Gau -- the way battle_rage.lua installs him -- would assert the
-- poke, not the data.  So this test boots gau_joined.mss: SABIN + CYAN + GAU
-- standing on Crescent Mountain's doorstep after his own return-visit
-- recruit, and walks into a real world encounter.
--
-- TWO ENCOUNTERS, because the rule has two verdicts and the list is built once
-- per battle.  Battle A is entirely natural and stands ON the Veldt (the
-- fixture's own sector sets $11e4 = $0f, field/battle.asm:141).  Battle B is a
-- FRESH load of the same fixture with ONE bit instrumented: an exec callback on
-- InitCmdList clears $11e4 bit 1 at the routine's first instruction, i.e. at
-- the exact moment the code under test reads its input, so the whole party's
-- lists build as if the encounter were anywhere else in the world.  The bit is
-- restored the moment the measurement lands, and the instrument COUNTS its own
-- firings and asserts the bit really was set beforehand -- an instrument that
-- silently did nothing would make arm 1d vacuous.  The reload is what makes
-- battle B clean: no wounded bench, no post-victory Veldt AI, no residue from
-- battle A's trance.  Nothing else is poked in either battle before its list
-- has been read.
--
-- Asserted:
--   1a. THE SAVE RECORD, unpoked, as the join event copied it out of
--      char_prop: $00 $10 $02 $01 -- FIGHT / RAGE / MAGIC / ITEM.  This is the
--      per-save data every other assertion is a verdict ON, read straight out
--      of the character record at $1616+$3010[slot], not out of the ROM table.
--      FAILS PRE-#47: the record reads $10 $11 $02 $01 and holds no $00.
--   1b. THE BUILT LIST, ON THE VELDT (battle A, natural).  Row 0 is LEAP
--      ($11) -- the SHARED row, asserted as the rule rather than as a
--      constant: LEAP when the Veldt flag $11e4 bit 1 is set, else FIGHT.
--      Measured on the fixture: the flag IS set at Crescent Mountain's
--      doorstep, so the substitution is exercised for real.  Row 1 is RAGE,
--      row 2 is MAGIC's own untouched vanilla verdict -- removed ($ff), since
--      this Gau knows no spells -- and row 3 is ITEM.
--      FAILS PRE-CHANGE (the magic-row version): row 0 read $00 FIGHT and row
--      2 read $11 LEAP, i.e. exactly the two rows swapped.
--   1c. THE NEGATIVE CONTROL, in the same battle: SABIN and CYAN keep FIGHT in
--      row 0 and carry LEAP in no row at all.  The substitution is gated on
--      CHAR::GAU, and standing on the Veldt makes the other half of that gate
--      true for everyone -- so this gate is the only thing stopping it firing
--      for the whole party.
--   1d. THE BUILT LIST, OFF THE VELDT (battle B, the one instrumented bit).
--      Row 0 is FIGHT ($00) -- the free action, in the territory where Leap
--      would be refused by InitCmd_01 anyway -- and rows 1-3 are unchanged
--      from 1b.  The save record is re-read here and asserted byte-identical
--      to 1a: the SAME data, a different verdict, which is what "shared row"
--      has to mean.
--   2. FIGHT EXECUTES AND CARRIES A REAL WEAPON CLASS (battle B, so that row 0
--      really is Fight).  Row 0 is swung through battle_class.lua's berserk
--      driver (rows 1-3 blanked, row 0 left exactly as InitCmdList wrote it,
--      berserk status set, so RandCharAction picks the one command
--      BerserkCmdTbl still admits and Cmd_00 fires at an enemy with no menu
--      and no cursor at all).  Monster HP drops and the live attack-class byte
--      OT6_ATKCLASS ($57b8) reads OT6_BLUDG, and ONLY OT6_BLUDG, for the whole
--      window -- Gau ships with an empty weapon slot (char_prop record 11
--      equips nothing), and Ot6WeapClassTbl[$ff] is OT6_BLUDG, so his bare
--      fists are a bludgeoning probe.  The class is read through the SAME
--      per-swing $3ca8 hand lookup every other character's Fight uses
--      (Ot6WeaponClass, ot6_break.asm), which is the whole point of putting him
--      in the break economy: tools/check_break_reach.py credited him
--      bludgeoning for months while he had no way to throw a punch.
--      FAILS PRE-CHANGE: there is no Fight row to press.
--   3. THE SHIELD LEDGER AGREES WITH THE CLASS.  Which body he hit is
--      MEASURED (whoever lost HP), not guessed, and that body's shield counter
--      moves if and only if its class-weakness byte carries bludgeoning --
--      asserted both ways, so a chip that happens for the wrong reason and a
--      chip that silently never happens both fail.  The window also asserts
--      that ONLY $04 was ever loaded into OT6_ATKCLASS, which is what makes
--      "his class" mean his and not the party's.
--   4. RAGE POSSESSION IS UNAFFECTED (battle A).  Rage is started from row 1
--      of the same new four-row menu; the RAGE status latches, Cmd_10
--      re-enters on its own several times, and Gau's battle menu NEVER opens
--      again -- the command list is irrelevant mid-trance because
--      CheckPlayerAction refuses to open a menu for a RAGE-status actor
--      (battle_main.asm's STATUS34 {DANCE, HIDE, RAGE} gate).  The menu-open
--      count is the assertion: "the shared row must be irrelevant, not broken"
--      is only meaningful if something counted the openings.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/gau_joined.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
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
local function ST3(e)   return 0x3EF8 + e end
local function ST4(e)   return 0x3EF9 + e end
local function SHIELD(e) return 0x3E38 + e end   -- OT6_SHIELD_CUR
local function CLSWEAK(e) return 0x3E9C + e end  -- authored class weakness
local function CURMP(s) return 0x3C08 + s * 2 end

local gauSlot, msPresent = nil, {}
local classWrites, cmd10Hits, gauMenus = {}, 0, 0
local saveRecA = nil                  -- battle A's read of the save record
local veldtCleared = 0                -- battle B: times the instrument fired

-- monster-side staging ONLY: stop everything so nothing acts back or dies.
local function pinStop()
  for _, m in ipairs(msPresent) do
    local e = 8 + m * 2
    H.writeByte(ST3(e), H.readByte(ST3(e)) | 0x10)
  end
end

local function pinMonsters()
  pinStop()
  for _, m in ipairs(msPresent) do
    if H.readWord(MHP(m)) < 0x6000 then H.writeWord(MHP(m), 0xF000) end
  end
end

-- CLEAR THE BENCH, once per battle, AFTER that battle's list arms have read
-- the natural command lists.  The first draft let SABIN and CYAN act (Defend,
-- battle_naturalmp's driver) and the shield ledger promptly caught it: a
-- bludgeoning-weak assertion went red against a SLASH-weak body, because
-- Cyan's katana had been chipping it between Gau's turns.  Nothing about arm
-- 2/3 is attributable unless Gau is the only actor.  A DEAD row raises no menu
-- and takes no turn -- battle_rage.lua:322-331's own measured lesson (a
-- STOPPED row leaves a pending menu open forever and pauses the battle
-- instead).
local function clearBench()
  for s = 0, 3 do
    local id = H.readByte(0x3ED8 + s * 2)
    if id ~= 0xFF and s ~= gauSlot then
      H.writeByte(0x3EE4 + s * 2, H.readByte(0x3EE4 + s * 2) | 0x80)  -- wound
      H.writeWord(0x3BF4 + s * 2, 0)
    end
  end
end

-- wait for GAU's own menu.  With the bench cleared he is the only actor, so
-- this is a wait, not a driver -- and every hit landed in the window that
-- follows is HIS.
local function menuForGau(what)
  return H.driveUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == gauSlot
  end, 20000, {
    H.call(function() pinMonsters(); H.setPad({}) end),
    H.waitFrames(2),
  }, what)
end

local function tap(btn, gap)
  return H.repeatN(1, {
    H.pressButtons({ btn }, 4),
    H.waitFrames(gap or 16),
  })
end

-- Gau's four command bytes AS THE SAVE HOLDS THEM.  InitCmdList's own two
-- lines: `ldy $3010,x` (pointer to character data) then `lda $1616,y` -- the
-- battle command list is copied out of the character record, never read from
-- the ROM's CharProp table, which is exactly why this fixture has to be a
-- natural join and not a poke.
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

-- gen_sabin_gau's own Veldt-grind pacing: alternate left/right at tile
-- boundaries until the world's own encounter roll wins.  No danger poke.
local function walkIntoEncounter()
  local flip = false
  return {
    H.waitUntil(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned()
    end, 4000, "world control at Crescent Mountain's doorstep"),
    H.call(function()
      H.assertEq(H.worldX(), 214, "fixture parked at world x=214")
      H.assertEq(H.worldY(), 149, "fixture parked at world y=149")
    end),
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        if H.battleLoadStarted() then H.setPad({}) return end
        if not H.worldHasControl() then H.setPad({}) return end
        if not H.worldAligned() then return end
        flip = not flip
        H.setPad({ [flip and "left" or "right"] = true })
      end),
    }, "a world encounter fires"),
    H.call(function() H.setPad({}) end),
    H.waitUntil(function() return H.battleActive() end, 1200, "battle armed", 5),
    -- 90 frames is after InitChars/InitCmdList (battle init, before any ATB
    -- fills) and BEFORE the first command window opens.  That ordering is
    -- load-bearing: clearBench has to run before any bench menu exists,
    -- because a menu that is already open belongs to a row that is about to be
    -- wounded and its pending action outlives the wound (measured -- a dead
    -- SABIN's window opened and swung anyway, and Gau's own target cursor was
    -- left sitting in it).
    H.waitFrames(90),
  }
end

-- find Gau, enumerate the bodies, pin them.  Shared by both battles.
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
  pinMonsters()
end

local hpPre, shieldPre = {}, {}

local steps = {}
local function add(list) for _, s in ipairs(list) do steps[#steps + 1] = s end end

add({
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
})

-- ============================================================== BATTLE A ==
-- Entirely natural, and standing ON the Veldt.  Nothing is poked before the
-- list arms below have read it.
add(walkIntoEncounter())

-- -------- 1a/1b/1c. THE SAVE RECORD, THE VELDT LIST, AND THE GAU GATE ------
add({
  H.call(function()
    surveyBattle()

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
      .. "save.  This is the row the magic-row version sacrificed")
    H.assertEq(saveRecA[3], CMD_ITEM, "save record slot 3 is ITEM")

    -- 1b. the built list, on the Veldt.  The rule, not a constant.
    H.assertEq(onVeldt, true,
      "positive control: the fixture really is standing on a Veldt sector, so "
      .. "the substitution below is exercised rather than merely not-fired "
      .. "($11e4 = $0f, field/battle.asm:141)")
    H.assertEq(rows[0], onVeldt and CMD_LEAP or CMD_FIGHT, string.format(
      "row 0 is the SHARED row and follows the rule, not a constant: the Veldt "
      .. "flag $11e4 reads $%02X, so this row belongs to %s.  On the Veldt "
      .. "Leap IS the free action, which is why FIGHT is the row that can "
      .. "afford to share it (owner, 2026-07-29)",
      H.readByte(VELDT), onVeldt and "LEAP" or "FIGHT"))
    H.assertEq(rows[1], CMD_RAGE, "row 1 is RAGE -- the kit verb keeps a row")
    H.assertEq(rows[2], CMD_NONE,
      "row 2 is MAGIC's own untouched vanilla verdict -- removed ($ff), "
      .. "because this Gau knows no spells and InitCmd_03 is back to exact "
      .. "vanilla.  The magic-row version put LEAP here; nothing does now, so "
      .. "a Gau holding magicite keeps his spells ON the Veldt too")
    H.assertEq(rows[3], CMD_ITEM, "row 3 is ITEM -- the free floor is intact")

    -- 1c. the negative control: the substitution is gated on CHAR::GAU, and
    -- this fixture stands ON the Veldt, so the gate is the only thing keeping
    -- Leap off SABIN's and CYAN's rows.
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF and s ~= gauSlot then
        local other = rowsOf(s)
        H.log(string.format("[slot %d] actor $%02X rows = %02X %02X %02X %02X",
          s, id, other[0], other[1], other[2], other[3]))
        H.assertEq(other[0], CMD_FIGHT, string.format(
          "actor $%02X still leads with FIGHT -- his row 0 was NOT substituted "
          .. "even though we are standing on the Veldt, where the other half "
          .. "of the gate is true", id))
        local anyLeap = false
        for i = 0, 3 do if other[i] == CMD_LEAP then anyLeap = true end end
        H.assertEq(anyLeap, false, string.format(
          "actor $%02X got Gau's Veldt Leap on NO row (the substitution is "
          .. "CHAR::GAU-gated)", id))
      end
    end

    clearBench()
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
      "positive control: the fixture's Gau has learned at least one rage "
      .. "(the Veldt grind that recruited him)")
    -- every Cmd_10 entry: the denominator for "the trance took several turns"
    emu.addMemoryCallback(function() cmd10Hits = cmd10Hits + 1 end,
      emu.callbackType.exec, H.sym("Cmd_10"), H.sym("Cmd_10"))
  end),
  tap("down", 24),                  -- row 0 (the shared row) -> row 1 Rage
  H.driveUntil(function() return H.readByte(MSTATE) == ST_RAGE end, 1500, {
    H.call(function() pinMonsters(); H.setPad({ a = true }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the rage window opens from row 1"),
  H.call(function()
    -- park the rage window's cursor on entry 0 -- the scroll/column/row
    -- triple indexed by actor slot, battle_rage.lua:367-372 (_c18438,
    -- btlgfx_main.asm:20096-20111).  Without it the confirm can land on a
    -- blank cell and the trance never starts (measured: 4000 frames, no
    -- RAGE bit).
    cmd10Hits, gauMenus = 0, 0
    H.writeByte(0x892B + gauSlot, 0)
    H.writeByte(0x892F + gauSlot, 0)
    H.writeByte(0x8933 + gauSlot, 0)
  end),
  H.driveUntil(function()
    return (H.readByte(ST4(gauSlot * 2)) & 0x01) ~= 0
  end, 4000, {
    H.call(function()
      pinMonsters()
      -- press A on ANY window Gau still has open: the rage list ($1e) hands
      -- off to a follow-up state ($38) that also waits on a confirm, and a
      -- drive that only answered $1e sat there for 4000 frames (measured).
      H.setPad((H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == gauSlot)
               and { a = true } or {})
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(16),
  }, "the RAGE status latches (Cmd_10 ran)"),
  H.call(function() gauMenus = 0 end),   -- count openings from the trance on
  H.repeatN(300, {
    H.call(function()
      pinMonsters()
      H.setPad({})
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == gauSlot then
        gauMenus = gauMenus + 1
      end
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(6),
  }),
  H.call(function()
    H.log(string.format("[trance] cmd10=%d gau menu openings=%d raging=%s",
      cmd10Hits, gauMenus, tostring((H.readByte(ST4(gauSlot * 2)) & 0x01) ~= 0)))
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
-- A FRESH load of the same fixture, with one bit instrumented at exactly the
-- moment the code under test reads it.
add({
  H.loadState(STATE),
  H.waitFrames(20),
  H.call(function()
    veldtCleared = 0
    emu.addMemoryCallback(function()
      local v = H.readByte(VELDT)
      if (v & 0x02) ~= 0 then
        H.writeByte(VELDT, v & 0xFD)
        veldtCleared = veldtCleared + 1
      end
    end, emu.callbackType.exec, H.sym("InitCmdList"), H.sym("InitCmdList"))
    H.log("battle B armed: $11e4 bit 1 cleared at InitCmdList's entry")
  end),
})
add(walkIntoEncounter())

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
      .. "callback cleared it.  Without this count arm 1d would pass vacuously "
      .. "on a fixture that had wandered off the Veldt by itself")
    H.assertEq(H.readByte(VELDT) & 0x02, 0,
      "and the bit is still clear now, so the list below was built off-Veldt")

    for i = 0, 3 do
      H.assertEq(rec[i], saveRecA[i], string.format(
        "the save record is byte-identical to battle A at slot %d ($%02X): the "
        .. "SAME data, and only the verdict on it changes.  That is what "
        .. "'shared row' has to mean -- nothing rewrites the save", i, rec[i]))
    end

    H.assertEq(rows[0], CMD_FIGHT,
      "row 0 is FIGHT off the Veldt -- the free action, in the territory where "
      .. "Leap would have been refused by InitCmd_01 anyway.  Battle A read "
      .. "$11 LEAP out of this same save byte, one Veldt bit ago")
    H.assertEq(rows[1], CMD_RAGE, "row 1 is still RAGE")
    H.assertEq(rows[2], CMD_NONE,
      "row 2 is still MAGIC's own vanilla verdict (removed -- no spells): the "
      .. "sharing never touches the magic row in EITHER territory, which is "
      .. "the whole point of moving Leap off that row")
    H.assertEq(rows[3], CMD_ITEM, "row 3 is still ITEM")

    -- restore the bit: from here on this is an ordinary Veldt battle again,
    -- and arms 2/3 do not care either way.
    H.writeByte(VELDT, H.readByte(VELDT) | 0x02)

    -- Arm 1d is measured; from here the fixture becomes a LAB so arms 2/3 are
    -- attributable.  battle_class.lua's own driver (:9-11, :283-288): clear
    -- the bench, blank every command row EXCEPT row 0, and berserk the actor
    -- -- RandCharAction then reads the LIVE $202e list, and BerserkCmdTbl
    -- (battle_main.asm:775) admits only Fight out of what is left, so Cmd_00
    -- fires at a random ENEMY with no menu and no cursor at all.
    -- Row 0 is NOT written: the $00 that swings is the byte InitCmdList
    -- produced from the save data, which arm 1d just asserted.  The menu drive
    -- this replaces punched GAU HIMSELF -- the target cursor sits on the party
    -- column and three swings took him 246 -> 176 -> 86 before the party
    -- wiped.  Vivid proof that his Fight is a real weapon swing, useless as an
    -- assertion.
    clearBench()
    for r = 1, 3 do H.writeByte(CMDROW(gauSlot, r), CMD_NONE) end
    local st2 = 0x3EE5 + gauSlot * 2
    H.writeByte(st2, H.readByte(st2) | 0x10)              -- berserk
    H.writeWord(0x3AC8 + gauSlot * 2, 0x2000)             -- hurry the gauge

    -- the class byte, attributed: every store while Gau's swing resolves
    emu.addMemoryCallback(function(_, v)
      classWrites[#classWrites + 1] = v
    end, emu.callbackType.write, 0x7E0000 + ATKCLASS, 0x7E0000 + ATKCLASS)
  end),
})

-- ------------------------- 2/3. FIGHT swings, chips, and carries a class --
add({
  H.call(function()
    -- the whole monster ledger, per body: who the berserk swing picks is the
    -- engine's business, so the body he hits is MEASURED afterwards, never
    -- guessed.  (An earlier draft guessed the first present body and read a
    -- shield another character had chipped.)
    hpPre, shieldPre = {}, {}
    for _, m in ipairs(msPresent) do
      local e = 8 + m * 2
      hpPre[m] = H.readWord(MHP(m))
      shieldPre[m] = H.readByte(SHIELD(e))
    end
    classWrites = {}
    H.log(string.format("[pre-fight] bodies=%d berserk gau in slot %d",
      #msPresent, gauSlot))
  end),
  H.driveUntil(function()
    for _, m in ipairs(msPresent) do
      if H.readWord(MHP(m)) < hpPre[m] then return true end
    end
    return false
  end, 8000, {
    H.call(function()
      -- STOP only: the HP floor must NOT be re-applied inside the measurement
      -- window.  It was, in an earlier draft, and it hid every punch -- the
      -- floor rewrote 0xF000 back before the predicate could see the drop.
      -- Gau hits hard (char_prop record 11 carries battle power 99), so a
      -- 0xF000 body survives the swings this needs.  No pad input at all: a
      -- berserk actor has no menu, so nothing here can be a driver artifact.
      pinStop()
      H.setPad({})
    end),
    H.waitFrames(4),
  }, "Gau's berserk Fight lands damage on a monster"),
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
      .. "and with the bench cleared this damage can only be his")
    H.assertEq(seen[OT6_BLUDG] or false, true,
      "the swing resolved a REAL weapon class: OT6_ATKCLASS took OT6_BLUDG "
      .. "($04) off the empty-hand row of Ot6WeapClassTbl.  Gau equips no "
      .. "weapon at join, so bare fists are his probe -- exactly what "
      .. "check_break_reach.py has been crediting him")
    H.assertEq(#classWrites > 0 and seen[OT6_BLUDG]
               and not seen[0x01] and not seen[0x02] and not seen[0x08], true,
      "and it resolved ONLY bludgeoning: with the bench cleared and every "
      .. "monster stopped, nothing else was loading an attack, so no slashing "
      .. "or piercing probe can have crept into the window")

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
