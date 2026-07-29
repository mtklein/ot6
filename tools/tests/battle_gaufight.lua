-- @suite frontier=gau_joined slow
-- battle_gaufight.lua -- issue #47: GAU HAS A FREE ACTION.
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
-- Gau now carries FIGHT / RAGE / MAGIC / ITEM, and LEAP shares the magic row
-- (InitCmd_03/04): Leap is refused anywhere but the Veldt by its own vanilla
-- availability test, so on the Veldt that row is Leap and everywhere else it
-- is Magic.  Nothing is lost except casting WHILE STANDING ON the Veldt.
--
-- WHY A NATURAL BOOT.  The commands are per-SAVE data: CharProp is copied into
-- the character record when the join event runs (field/event.asm:1039-1046),
-- and battle reads them from $1616,y, not from the ROM table (InitCmdList).  A
-- poked-in Gau -- the way battle_rage.lua installs him -- would assert the
-- poke, not the data.  So this test boots gau_joined.mss: SABIN + CYAN + GAU
-- standing on Crescent Mountain's doorstep after his own return-visit
-- recruit, and walks into a real world encounter.  Arm 1 -- the whole
-- natural-boot claim -- reads the command lists with NO character row poked at
-- all.  Only after it lands does the fixture clear the bench (SABIN and CYAN
-- wounded) so that arms 2/3 are ATTRIBUTABLE: the first draft let them Defend
-- and the shield ledger caught Cyan's katana chipping the body Gau was
-- punching.  Monsters are stopped and HP-pinned throughout so nothing dies
-- before the measurements land.
--
-- Asserted:
--   1. THE COMMAND LIST, as InitCmdList built it from his save record.  Row 0
--      is FIGHT ($00), row 1 RAGE ($10), row 3 ITEM ($01), and row 2 is the
--      SHARED row, asserted as the rule rather than as a constant: LEAP ($11)
--      when the Veldt flag $11e4 bit 1 is set, otherwise magic's own vanilla
--      verdict -- removed ($ff), since this Gau knows no spells.  Measured on
--      the fixture: the flag IS set at Crescent Mountain's doorstep, so the
--      shared row resolves to LEAP here and the substitution is exercised for
--      real.  SABIN and CYAN in the same battle are the negative control:
--      their own row 2 must stay magic's ($ff), never Leap -- the
--      substitution is gated on CHAR::GAU, and on the Veldt that gate is the
--      only thing stopping it firing for everyone.
--      FAILS PRE-CHANGE: the rows read $10 / $11 / $11 / $01 -- Rage, Leap,
--      the shared row, Item -- and no row anywhere in the list is $00.
--      (Measured on the pre-change fixture, 2026-07-29.)
--   2. FIGHT EXECUTES AND CARRIES A REAL WEAPON CLASS.  Row 0 is swung
--      through battle_class.lua's berserk driver (rows 1-3 blanked, row 0
--      left exactly as the save data wrote it, berserk status set, so
--      RandCharAction picks the one command BerserkCmdTbl still admits and
--      Cmd_00 fires at an enemy with no menu and no cursor at all).  Monster
--      HP drops and the live attack-class byte OT6_ATKCLASS ($57b8) reads
--      OT6_BLUDG, and ONLY OT6_BLUDG, for the whole window --
--      Gau ships with an empty weapon slot (char_prop record 11 equips
--      nothing), and Ot6WeapClassTbl[$ff] is OT6_BLUDG, so his bare fists are
--      a bludgeoning probe.  The class is read through the SAME per-swing
--      $3ca8 hand lookup every other character's Fight uses (Ot6WeaponClass,
--      ot6_break.asm), which is the whole point of putting him in the break
--      economy: tools/check_break_reach.py credited him bludgeoning for
--      months while he had no way to throw a punch.
--      FAILS PRE-CHANGE: there is no Fight row to press.
--   3. THE SHIELD LEDGER AGREES WITH THE CLASS.  Which body he hit is
--      MEASURED (whoever lost HP), not guessed, and that body's shield counter
--      moves if and only if its class-weakness byte carries bludgeoning --
--      asserted both ways, so a chip that happens for the wrong reason and a
--      chip that silently never happens both fail.  The window also asserts
--      that ONLY $04 was ever loaded into OT6_ATKCLASS, which is what makes
--      "his class" mean his and not the party's.
--   4. RAGE POSSESSION IS UNAFFECTED.  Rage is started from row 1 of the same
--      new four-row menu; the RAGE status latches, Cmd_10 re-enters on its own
--      several times, and Gau's battle menu NEVER opens again -- the command
--      list, Fight included, is irrelevant mid-trance because CheckPlayerAction
--      refuses to open a menu for a RAGE-status actor (battle_main.asm's
--      STATUS34 {DANCE, HIDE, RAGE} gate).  The menu-open count is the
--      assertion: "Fight must be irrelevant, not broken" is only meaningful if
--      something counted the openings.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/gau_joined.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local GAU = 0x0B
local CMD_FIGHT, CMD_RAGE, CMD_ITEM, CMD_NONE = 0x00, 0x10, 0x01, 0xFF
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

local gauSlot, msPresent, gauRows = nil, {}, {}
local classWrites, cmd10Hits, gauMenus = {}, 0, 0

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

-- CLEAR THE BENCH, once, AFTER arm 1 has read the natural command lists.
-- The first draft let SABIN and CYAN act (Defend, battle_naturalmp's driver)
-- and the shield ledger promptly caught it: a bludgeoning-weak assertion went
-- red against a SLASH-weak body, because Cyan's katana had been chipping it
-- between Gau's turns.  Nothing about arm 2/3 is attributable unless Gau is
-- the only actor.  A DEAD row raises no menu and takes no turn -- battle_rage
-- .lua:322-331's own measured lesson (a STOPPED row leaves a pending menu open
-- forever and pauses the battle instead).  Arm 1 is already measured by the
-- time this runs, so the natural-boot claim is untouched.
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

local hpPre, shieldPre = {}, {}

H.run({ maxFrames = 120000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 4000, "world control at Crescent Mountain's doorstep"),
  H.call(function()
    H.assertEq(H.worldX(), 214, "fixture parked at world x=214")
    H.assertEq(H.worldY(), 149, "fixture parked at world y=149")
  end),

  -- ------------------------------------------------ a natural encounter --
  -- gen_sabin_gau's own Veldt-grind pacing: alternate left/right at tile
  -- boundaries until the world's own encounter roll wins.  No danger poke.
  (function()
    local flip = false
    return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        if H.battleLoadStarted() then H.setPad({}) return end
        if not H.worldHasControl() then H.setPad({}) return end
        if not H.worldAligned() then return end
        flip = not flip
        H.setPad({ [flip and "left" or "right"] = true })
      end),
    }, "a world encounter fires")
  end)(),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 1200, "battle armed", 5),
  -- 90 frames is after InitChars/InitCmdList (battle init, before any ATB
  -- fills) and BEFORE the first command window opens.  That ordering is
  -- load-bearing: clearBench below has to run before any bench menu exists,
  -- because a menu that is already open belongs to a row that is about to be
  -- wounded and its pending action outlives the wound (measured -- a dead
  -- SABIN's window opened and swung anyway, and Gau's own target cursor was
  -- left sitting in it).
  H.waitFrames(90),

  -- --------------------------------- 1. THE COMMAND LIST, as data built it --
  H.call(function()
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) == GAU then gauSlot = s end
    end
    assert(gauSlot, "GAU is in the battle party (the s2/sabin chain seats him)")
    for m = 0, 5 do
      if H.readByte(0x3AA8 + m * 2) % 2 == 1 then msPresent[#msPresent + 1] = m end
    end
    assert(#msPresent > 0, "the encounter has monsters")
    pinMonsters()

    local onVeldt = (H.readByte(VELDT) & 0x02) ~= 0
    local rows = {}
    for r = 0, 3 do rows[r] = H.readByte(CMDROW(gauSlot, r)) end
    H.log(string.format("[gau slot %d] rows = %02X %02X %02X %02X  MP=%d  "
      .. "$11e4=%02X (veldt=%s)", gauSlot, rows[0], rows[1], rows[2], rows[3],
      H.readWord(CURMP(gauSlot)), H.readByte(VELDT), tostring(onVeldt)))

    H.assertEq(rows[0], CMD_FIGHT,
      "row 0 is FIGHT -- the free action Gau never had (issue #47); "
      .. "pre-change this row reads $10 RAGE and no row is $00")
    H.assertEq(rows[1], CMD_RAGE, "row 1 is RAGE -- the kit verb keeps a row")
    H.assertEq(rows[2], onVeldt and CMD_LEAP or CMD_NONE, string.format(
      "row 2 is the SHARED row and follows the rule, not a constant: the "
      .. "Veldt flag $11e4 reads $%02X, so this row belongs to %s.  Gau knows "
      .. "no spells, so magic's own verdict on this row is 'removed'",
      H.readByte(VELDT), onVeldt and "LEAP" or "magic (removed)"))
    H.assertEq(rows[3], CMD_ITEM, "row 3 is ITEM -- the free floor is intact")

    -- the negative control: the substitution is gated on CHAR::GAU, and this
    -- fixture stands ON the Veldt, so the gate is the only thing keeping Leap
    -- off SABIN's and CYAN's magic rows.
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF and s ~= gauSlot then
        local r0, r2 = H.readByte(CMDROW(s, 0)), H.readByte(CMDROW(s, 2))
        H.log(string.format("[slot %d] actor $%02X row0=%02X row2=%02X",
          s, id, r0, r2))
        H.assertEq(r0, CMD_FIGHT, string.format(
          "actor $%02X still leads with FIGHT", id))
        H.assertEq(r2 ~= CMD_LEAP, true, string.format(
          "actor $%02X did NOT get Gau's Veldt Leap on his magic row (the "
          .. "substitution is CHAR::GAU-gated, and we are standing on the "
          .. "Veldt where the other half of that gate is true)", id))
      end
    end

    -- Arm 1 is measured; from here the fixture becomes a LAB so arms 2/3 are
    -- attributable.  battle_class.lua's own driver (:9-11, :283-288): clear
    -- the bench, blank every command row EXCEPT row 0, and berserk the actor
    -- -- RandCharAction then reads the LIVE $202e list, and BerserkCmdTbl
    -- (battle_main.asm:775) admits only Fight out of what is left, so Cmd_00
    -- fires at a random ENEMY with no menu and no cursor at all.
    -- Row 0 is NOT written: the $00 that swings is the byte the save data
    -- produced, which arm 1 just asserted.  The menu drive this replaces
    -- punched GAU HIMSELF -- the target cursor sits on the party column and
    -- three swings took him 246 -> 176 -> 86 before the party wiped.  Vivid
    -- proof that his Fight is a real weapon swing, useless as an assertion.
    gauRows = { [0] = rows[0], rows[1], rows[2], rows[3] }
    clearBench()
    for r = 1, 3 do H.writeByte(CMDROW(gauSlot, r), CMD_NONE) end
    local st2 = 0x3EE5 + gauSlot * 2
    H.writeByte(st2, H.readByte(st2) | 0x10)              -- berserk
    H.writeWord(0x3AC8 + gauSlot * 2, 0x2000)             -- hurry the gauge

    -- the class byte, attributed: every store while Gau's swing resolves
    emu.addMemoryCallback(function(_, v)
      classWrites[#classWrites + 1] = v
    end, emu.callbackType.write, 0x7E0000 + ATKCLASS, 0x7E0000 + ATKCLASS)
    -- every Cmd_10 entry: the denominator for "the trance took several turns"
    emu.addMemoryCallback(function() cmd10Hits = cmd10Hits + 1 end,
      emu.callbackType.exec, H.sym("Cmd_10"), H.sym("Cmd_10"))
  end),

  -- ------------------------- 2/3. FIGHT swings, chips, and carries a class --
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
  end),

  -- --------------------------------- 4. RAGE POSSESSION IS UNAFFECTED --
  -- put the lab back: the rows arm 1 measured, and no berserk, so the trance
  -- is started from the real four-row menu with real pad edges.
  H.call(function()
    for r = 1, 3 do H.writeByte(CMDROW(gauSlot, r), gauRows[r]) end
    local st2 = 0x3EE5 + gauSlot * 2
    H.writeByte(st2, H.readByte(st2) & 0xEF)
    pinMonsters()
    H.log("lab restored: rows back to the measured list, berserk cleared")
  end),
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
  end),
  tap("down", 24),                  -- row 0 Fight -> row 1 Rage
  H.driveUntil(function() return H.readByte(MSTATE) == ST_RAGE end, 1500, {
    H.call(function() pinMonsters(); H.setPad({ a = true }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the rage window opens from the new row 1"),
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
      "adding FIGHT did not give a possessed Gau a menu: CheckPlayerAction's "
      .. "STATUS34 {DANCE,HIDE,RAGE} gate still refuses to open one, so his "
      .. "command list -- Fight included -- is IRRELEVANT mid-trance, which is "
      .. "what 'unaffected' has to mean")
    H.screenshot("gau_fight")
  end),
})
