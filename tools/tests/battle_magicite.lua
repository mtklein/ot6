-- @suite slow
-- battle_magicite.lua -- the v0.6 Ifrit/Shiva magicite redesigns, the halves
-- battle_esperstats.lua does not reach: the ABILITY PRICES their kits are built
-- on, and the SUMMONS.  Design: docs/design/magicite-ifrit-shiva.md (issue #16).
-- battle_esperstats owns "which spells and which stat"; this file owns "what
-- they cost and what the divine does".
--
-- WHAT IS ACTUALLY UNDER TEST, and why each assertion can fail:
--
-- 1. OSMOSE COSTS 8 MP, NOT 1.  The design's biggest balance risk (§6).  Vanilla
--    prices Osmose at 1 MP; Facility boss MP pools are 447-810 against party
--    pools of 40-60, so one 1-MP cast is a full refill -- an off switch for the
--    currency v0.5 turned on.  battle_main.asm splices +$05 of MagicProp record
--    $29 to 8 as an explicit, argued exception to mp-economy.md's "magic keeps
--    vanilla MP costs".  Proved twice over:
--      * the price the engine itself published into the in-battle Magic list
--        (ValidateSpellList writes MagicProp+5 to list record +3), and
--      * a BOUNDARY that only 8 can produce: at 7 MP the Osmose row is GREYED
--        (UpdateEnabledMagic/CheckMagicEnabled compare cost to current MP) while
--        base Ice at 5 MP is still live.  At vanilla's 1 MP, Osmose would be
--        live at 7 MP and this fails loudly.
--
-- 2. DIAMOND DUST IS NO LONGER A MIRROR OF INFERNO.  Vanilla $38 is $37 in
--    another colour (power 52 vs 51, 27 MP vs 26).  v0.6 re-authors $38 to
--    power 34 + a STATUS3::SLOW rider so Inferno stays the damage divine and
--    Diamond Dust becomes the tempo divine.  Asserted as ROM bytes (both
--    records, so "Inferno untouched" is a control) AND behaviourally: a real
--    summon, driven through the real menu, must land Slow on a target whose
--    blocked-status word permits it and must NOT land it on one that does not.
--    That pair is the whole point -- the design flagged "does an unblockable
--    (+$04 bit $20, hit 0) damage spell apply its status bytes at all, and is
--    per-monster immunity still consulted?" as UNVERIFIED and load-bearing.
--    Reading CheckHit @22a1 -> @22e8 (unconditional carry-clear exit) and
--    InitStatusVars ($3dd4 AND $331c / $3de8 AND $3330) says yes to both; this
--    is the measurement that makes it a fact rather than a code reading.
--
-- 3. THE ONCE-PER-BATTLE SUMMON.  Vanilla's own latch, verified not broken by
--    the redesign: the esper row is OFFERED before (enable byte bit 7 clear --
--    CONTRIBUTING's "a quiet test is not a passing test": the row has to have
--    been available for its later refusal to mean anything), the summon fires
--    and the engine sets the caster's bit in $3f2e, and with that bit set
--    UpdateEnabledMagic greys the row -- restored the instant the bit is
--    cleared again, which is the A/B that proves $3f2e is what did it.
--
-- 4. THE KIT PRICES.  Ifrit's Fire 4 / Drain 15 and Shiva's Ice 5 / Shell 15,
--    read off the same published list, plus each stone's summon price (Inferno
--    26, Diamond Dust 27).  These are vanilla numbers and do not change with
--    this release -- they are here because the design's whole economy argument
--    (a 4 MP base Fire folding to a 51 MP Fire 3) rests on them being what it
--    says they are.
--
-- FIXTURE.  battle_doorstep, the same field-doorstep mint battle_esperstats and
-- battle_subjob use: poke char 0's equipped esper ($161e) plus her field MP
-- ($160d/$160f) BEFORE driving in, so the whole spell-list build and the first
-- enabled-magic pass run against the poked values.  MP has to be pinned in the
-- FIELD, not in battle: UpdateEnabledMagic's only battle-init run happens off
-- the $3204 request flags seeded at @2459, long before an in-battle poke lands,
-- and intro Terra cannot afford a 27 MP summon.
--
-- MENU ROUTE TO A SUMMON (measured, probe run 2026-07-27).  $7bc2 is the menu
-- state: $0e = the magic window, $16 = esper select, $38 = target select.  From
-- Terra's command window (Magic pinned as her only command) one A opens $0e;
-- with the list scrolled to the top, UP runs CheckHasGenju and opens $16; A
-- there commits command $19 and A again confirms the target.  The magic grid is
-- offset by one from the list records -- grid cell p is list record p+1, because
-- record 0 is the esper row (get_magic_poi reads $2093,x = record p+1's enable
-- byte) -- which is how a specific spell is put under the cursor here.
--
-- AND THE ONE THING THAT MAKES ANY OF THAT MEASURABLE: see freezeOthers below.
-- On this mint an ally's Magitek beam resolving inside the caster's action
-- window overwrites the shared $11a0 property buffer mid-resolution, and every
-- spell effect measured here reads as "nothing happened".  It is not the spell.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

-- spell ids (const.inc ATTACK enum)
local FIRE, ICE, DRAIN, SHELL, OSMOSE = 0x00, 0x01, 0x04, 0x25, 0x29
local INFERNO, DDUST = 0x37, 0x38        -- summon attack ids (esper + $36)
local IFRIT, SHIVA = 0x01, 0x02          -- esper indices (GenjuProp order)

-- authored prices (magic_prop_en.dat +$05, spliced in battle_main.asm)
local OSMOSE_MP = 8                      -- OT6 v0.6; vanilla was 1
local FIRE_MP, ICE_MP, DRAIN_MP, SHELL_MP = 4, 5, 15, 15
local INFERNO_MP, DDUST_MP = 26, 27
-- authored Diamond Dust record ($38): power cut, Slow added
local DDUST_POWER, DDUST_STATUS3 = 34, 0x04       -- STATUS3::SLOW = BIT_2
local INFERNO_POWER, INFERNO_STATUS3 = 51, 0x00   -- unchanged (the control)
local MAGIC_PROP_REC = 14

local ESPER0, FMPCUR, FMPMAX = 0x161e, 0x160d, 0x160f   -- char 0 field record
local LIST0 = 0x208e                     -- char slot 0's Magic list, 4B records
local MENU, ACTOR, MSTATE = 0x7bca, 0x62ca, 0x7bc2
local ST_MAGIC, ST_ESPER, ST_TARGET = 0x0e, 0x16, 0x38
local CURSOR_SCROLL, CURSOR_X, CURSOR_Y = 0x8913, 0x8917, 0x891b
local SUMMONED = 0x3f2e                  -- per-character "has summoned" mask
local REFRESH = 0x3204                   -- per-entity update-request flags
local STATUS3_SLOW = 0x04

local GUARDS = { 2, 3 }                  -- monster slots present on this mint
local function ent(s) return 8 + s * 2 end
local function MHP(s)  return 0x3bf4 + ent(s) end
local function MMP(s)  return 0x3c08 + ent(s) end
local function MMPMX(s) return 0x3c30 + ent(s) end
local function MST3(s) return 0x3ef8 + ent(s) end
local function MBLOCK34(s) return 0x3330 + ent(s) end     -- allowed status 3/4
local function CURMP(slot) return 0x3c08 + slot * 2 end
local function MASK(slot) return 0x3018 + slot * 2 end

local terra = 0
local spells = {}                        -- attack ids that reached $3410
local mpWrites = {}                      -- low-byte writes to Terra's current MP

local function findTerra()
  for s = 0, 3 do if H.readByte(0x3ed8 + s * 2) == 0 then terra = s end end
  return terra
end
-- list record n: +0 spell id ($ff = empty), +1 enable (bit 7 SET = greyed out),
-- +2 targeting, +3 MP cost.  Record 0 is the ESPER row: +0 is the esper index
-- and +3 is that esper's summon price.
local function recOf(id)
  for n = 1, 78 do
    if H.readByte(LIST0 + n * 4) == id then return n end
  end
  return nil
end
local function costOf(id)
  local n = recOf(id)
  return n and H.readByte(LIST0 + n * 4 + 3) or nil
end
local function enabled(n) return H.readByte(LIST0 + n * 4 + 1) < 0x80 end
local function esperRow() return H.readByte(LIST0) end
local function esperEnabled() return H.readByte(LIST0 + 1) < 0x80 end
local function dumpList(tag)
  local out = {}
  for n = 0, 78 do
    local id = H.readByte(LIST0 + n * 4)
    if id ~= 0xff then
      out[#out + 1] = string.format("%d:%02x%s/%dmp", n, id,
        enabled(n) and "" or "(grey)", H.readByte(LIST0 + n * 4 + 3))
    end
  end
  H.log("[" .. tag .. "] list: " .. table.concat(out, " "))
end
local function sawSpell(id)
  for _, v in ipairs(spells) do if v == id then return true end end
  return false
end

-- Keep Terra on Magic-only and un-magitek'd for the whole menu drive: the mint
-- is the Magitek intro fight, whose status would otherwise force beam actions.
local function pinTerra()
  local st1 = 0x3ee4 + terra * 2
  H.writeByte(st1, H.readByte(st1) & 0xf7)      -- clear magitek
  H.writeByte(0x202e + terra * 12, 0x02)        -- Magic, alone
  H.writeByte(0x2031 + terra * 12, 0xff)
  H.writeByte(0x2034 + terra * 12, 0xff)
  H.writeByte(0x2037 + terra * 12, 0xff)
end

-- Reload, poke the esper + field MP, drive up+A into the guard fight.
local function driveIn(tag, esper, mp)
  return {
    H.loadState(STATE),
    H.waitFrames(10),
    H.call(function()
      H.writeByte(ESPER0, esper)
      H.writeWord(FMPMAX, 99)
      H.writeWord(FMPCUR, mp)
      spells = {}
      mpWrites = {}
      H.log(string.format("[%s] esper := %d, field MP := %d", tag, esper, mp))
    end),
    H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
      H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
      H.pressButtons({ "a" }, 4),
    }, "battle load (" .. tag .. ")"),
    H.waitUntil(function() return H.battleActive() end, 900,
      "battle active (" .. tag .. ")", 30),
    H.waitFrames(120),
    H.call(function()
      findTerra()
      pinTerra()
      emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
        emu.callbackType.write, 0x7e3410, 0x7e3410)
      emu.addMemoryCallback(function(_, v) mpWrites[#mpWrites + 1] = v end,
        emu.callbackType.write, 0x7e0000 + CURMP(terra), 0x7e0000 + CURMP(terra))
      H.log(string.format("[%s] terra slot %d, battle MP %d/%d", tag, terra,
        H.readWord(CURMP(terra)), H.readWord(0x3c30 + terra * 2)))
      local pres = {}
      for s = 0, 5 do
        pres[#pres + 1] = string.format("%d:%02x hp=%d", s,
          H.readByte(0x3aa8 + s * 2), H.readWord(0x3bf4 + ent(s)))
      end
      H.log("[" .. tag .. "] monsters: " .. table.concat(pres, "  "))
      dumpList(tag)
    end),
  }
end

-- Advance until Terra holds an open menu, clearing anyone else's by tapping A.
local function untilTerrasMenu(tag)
  return H.driveUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == terra
  end, 9000, {
    H.call(function()
      pinTerra()
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) ~= terra then H.setPad({ "a" }) end
    end),
    H.waitFrames(4), H.call(function() H.setPad({}) end), H.waitFrames(20),
  }, tag .. ": terra's menu opens")
end
local function openMagicWindow(tag)
  return H.driveUntil(function() return H.readByte(MSTATE) == ST_MAGIC end, 900, {
    H.call(function() pinTerra(); H.setPad({ "a" }) end), H.waitFrames(3),
    H.call(function() H.setPad({}) end), H.waitFrames(14),
  }, tag .. ": magic window opens ($0e)")
end
local function tap(button, frames)
  return { H.call(function() H.setPad({ button }) end), H.waitFrames(3),
           H.call(function() H.setPad({}) end), H.waitFrames(frames or 14) }
end

-- MEASURED AND LOAD-BEARING (2026-07-27, probe run).  Once Terra's menu is open
-- and before her action resolves, STOP every other party member.  This mint is
-- the Magitek intro: Biggs and Wedge fire beams constantly, and a beam
-- resolving inside Terra's action window reloads $11a0..$11ad out from under it
-- -- LoadMagicProp is a single shared property buffer.  Without this freeze the
-- summon reads as "0 MP charged, no status applied, one guard scratched", which
-- is an artifact of the interleave and not the spell.  With it: 27 MP charged,
-- both guards hit, Slow staged on both.  Anything measuring a spell's own
-- effect on this fixture needs it.
local function freezeOthers()
  for s = 0, 3 do
    if s ~= terra then
      H.writeByte(0x3ef8 + s * 2, H.readByte(0x3ef8 + s * 2) | 0x10)   -- STATUS3 STOP
    end
  end
end

-- ---------------------------------------------------------------- results --
local R = {}

local all = { H.waitFrames(20) }
local function add(list) for _, s in ipairs(list) do all[#all + 1] = s end end

-- ------------------------------------------------- 0. the records, in ROM --
-- Cheapest and most direct proof that the splice landed where it was aimed:
-- Diamond Dust re-authored, Inferno untouched beside it as the control.
add({ H.call(function()
  local base = H.sym("MagicProp") & 0x3fffff          -- HiROM cpu -> file offset
  local function fld(rec, off) return H.readRomByte(base + rec * MAGIC_PROP_REC + off) end
  H.log(string.format("MagicProp @ file $%06x", base))
  H.assertEq(fld(DDUST, 6), DDUST_POWER, "Diamond Dust ($38) power re-authored to 34")
  H.assertEq(fld(DDUST, 12), DDUST_STATUS3, "Diamond Dust carries STATUS3::SLOW")
  H.assertEq(fld(DDUST, 5), DDUST_MP, "Diamond Dust still costs 27 MP (unchanged)")
  H.assertEq(fld(DDUST, 1), 0x02, "Diamond Dust still ice (unchanged)")
  H.assertEq(fld(INFERNO, 6), INFERNO_POWER, "control: Inferno ($37) power untouched")
  H.assertEq(fld(INFERNO, 12), INFERNO_STATUS3, "control: Inferno carries no status rider")
  H.assertEq(fld(INFERNO, 5), INFERNO_MP, "control: Inferno still costs 26 MP")
  H.assertEq(fld(OSMOSE, 5), OSMOSE_MP, "Osmose ($29) repriced to 8 MP in the record")
end) })

-- --------------------------------------------- 1. IFRIT: the Furnace's bill --
add(driveIn("ifrit", IFRIT, 99))
add({ H.call(function()
  H.assertEq(esperRow(), IFRIT, "[ifrit] list record 0 is Ifrit's summon row")
  H.assertEq(H.readByte(LIST0 + 3), INFERNO_MP, "[ifrit] Inferno priced at 26 MP")
  H.assertEq(esperEnabled(), true, "[ifrit] the summon is offered at battle start")
  H.assertEq(costOf(FIRE), FIRE_MP, "[ifrit] granted Fire costs 4 MP (base tier)")
  H.assertEq(costOf(DRAIN), DRAIN_MP, "[ifrit] granted Drain costs 15 MP")
end) })

-- ------------------------------ 2. SHIVA at 7 MP: the reprice's boundary --
-- The assertion the reprice exists for.  With Osmose at 8, 7 MP cannot buy it;
-- with vanilla's 1 it could.  Base Ice at 5 stays live in the same window, so
-- this is a boundary, not a blanket "everything is greyed" artifact.
add(driveIn("shiva7", SHIVA, 7))
add({ H.call(function()
  local osm, ice, shl = recOf(OSMOSE), recOf(ICE), recOf(SHELL)
  H.assertEq(osm ~= nil and ice ~= nil and shl ~= nil, true,
    "[shiva7] Shiva granted Ice/Osmose/Shell into the list")
  H.assertEq(H.readWord(CURMP(terra)), 7, "[shiva7] Terra entered the fight on 7 MP")
  H.assertEq(costOf(OSMOSE), OSMOSE_MP, "[shiva7] Osmose published at 8 MP in the list")
  H.assertEq(costOf(ICE), ICE_MP, "[shiva7] Ice published at 5 MP")
  H.assertEq(costOf(SHELL), SHELL_MP, "[shiva7] Shell published at 15 MP")
  H.assertEq(enabled(ice), true, "[shiva7] Ice (5) is castable on 7 MP -- the control")
  H.assertEq(enabled(osm), false, "[shiva7] Osmose (8) is GREYED on 7 MP -- vanilla's 1 would not be")
  H.assertEq(enabled(shl), false, "[shiva7] Shell (15) is greyed on 7 MP")
  H.assertEq(esperEnabled(), false, "[shiva7] and the 27 MP summon is greyed too")
end) })

-- --------------------- 3. SHIVA's divine: Diamond Dust, driven for real --
-- One battle, both sides of the immunity question at once: guard A's
-- allowed-status-3/4 word is given the Slow bit, guard B's has it taken away.
-- Diamond Dust targets the whole enemy half ($6e), so one cast reaches both and
-- the two guards become the experiment and its control in the same measurement.
-- That pair stands in for the Facility spread the design decoded: Number 024
-- blocks Slow (monster_prop +$16 = $14) where Number 128, the Cranes and both
-- blades do not -- magicite-ifrit-shiva.md §5.3.
--
-- $3330 is the engine's own "which status 3/4 may be set" word: InitStatus
-- stores the complement of the monster's immunity there (battle_main @26c5) and
-- InitStatusVars ANDs the staged $3de8 against it before anything is applied.
-- Poking it is pulling exactly the lever monster data pulls, which lets this run
-- on a mint whose guards' own immunities are beside the point.
add(driveIn("ddust", SHIVA, 99))
add({ H.call(function()
  local a, b = GUARDS[1], GUARDS[2]
  H.writeWord(MBLOCK34(a), H.readWord(MBLOCK34(a)) | STATUS3_SLOW)   -- Slow allowed
  H.writeWord(MBLOCK34(b), H.readWord(MBLOCK34(b)) & ~STATUS3_SLOW)  -- Slow immune
  R.hp0, R.st0 = {}, {}
  for _, s in ipairs(GUARDS) do
    H.writeWord(MHP(s), 0x2000)              -- survive a divine, stay readable
    R.hp0[s] = H.readWord(MHP(s))
    R.st0[s] = H.readByte(MST3(s))
    H.assertEq(R.st0[s] & STATUS3_SLOW, 0,
      string.format("[ddust] guard %d starts un-Slowed (control)", s))
  end
  R.mp0 = H.readWord(CURMP(terra))
  H.assertEq(esperRow(), SHIVA, "[ddust] list record 0 is Shiva's summon row")
  H.assertEq(H.readByte(LIST0 + 3), DDUST_MP, "[ddust] Diamond Dust published at 27 MP")
  H.assertEq(esperEnabled(), true,
    "[ddust] the summon is OFFERED before it is spent (the positive control)")
  H.assertEq(H.readWord(SUMMONED) & H.readWord(MASK(terra)), 0,
    "[ddust] $3f2e clear: nobody has summoned yet")
end) })
add({ untilTerrasMenu("ddust") })
add({ H.call(freezeOthers) })               -- see freezeOthers: without it nothing below measures the spell
add({ openMagicWindow("ddust") })
add({ H.driveUntil(function() return H.readByte(MSTATE) == ST_ESPER end, 600, {
  H.call(function() H.writeByte(CURSOR_SCROLL + terra, 0); H.setPad({ "up" }) end),
  H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(14),
}, "ddust: UP from the top of the list opens the esper window ($16)") })
add({ H.driveUntil(function() return sawSpell(DDUST) end, 4000,
  tap("a", 20), "ddust: Diamond Dust ($38) reaches $3410") })
add({ H.waitFrames(180) })
add({ H.call(function()
  local a, b = GUARDS[1], GUARDS[2]
  local report = {}
  for _, s in ipairs(GUARDS) do
    report[#report + 1] = string.format("g%d hp %d->%d st3 %02x->%02x allow34 %04x",
      s, R.hp0[s], H.readWord(MHP(s)), R.st0[s], H.readByte(MST3(s)),
      H.readWord(MBLOCK34(s)))
  end
  H.log(string.format("[ddust] %s | caster MP %d->%d | $3f2e=%04x",
    table.concat(report, "  "), R.mp0, H.readWord(CURMP(terra)), H.readWord(SUMMONED)))
  -- both halves of the experiment have to have been HIT, or the status result
  -- below is vacuous
  H.assertEq(H.readWord(MHP(a)) < R.hp0[a], true,
    "[ddust] the divine hit guard A (positive control for its status result)")
  H.assertEq(H.readWord(MHP(b)) < R.hp0[b], true,
    "[ddust] the divine hit guard B (positive control for its status result)")
  H.assertEq(H.readByte(MST3(a)) & STATUS3_SLOW, STATUS3_SLOW,
    "[ddust] the re-authored Slow rider LANDED where status 3/4 permits it")
  H.assertEq(H.readByte(MST3(b)) & STATUS3_SLOW, 0,
    "[ddust] and was refused where it does not -- immunity is still consulted")
  H.assertEq(R.mp0 - H.readWord(CURMP(terra)), DDUST_MP,
    "[ddust] the summon charged its 27 MP")
  H.assertEq(H.readWord(SUMMONED) & H.readWord(MASK(terra)) ~= 0, true,
    "[ddust] the engine set the caster's once-per-battle bit in $3f2e")
  H.screenshot("magicite_ddust")
end) })
-- The once-per-battle RULE, A/B'd on its own cause, on the battle that just
-- spent one.  UpdateEnabledMagic is what greys the row (`bit $3f2e` -> carry
-- stays set -> bit 7 into the enable byte); it runs from AfterAction2 on the
-- $3204 request flag, so setting that flag is how a refresh is asked for
-- without waiting on an ATB refill this mint does not grant promptly.  Latch
-- set -> greyed; latch cleared -> offered again, which is what makes $3f2e the
-- proven cause rather than a coincidence.
add({ H.driveUntil(function() return not esperEnabled() end, 3000, {
  H.call(function()
    H.writeByte(REFRESH + terra * 2, H.readByte(REFRESH + terra * 2) | 0x80)
  end),
  H.waitFrames(16),
}, "ddust: a spent summon greys the esper row") })
add({ H.driveUntil(function() return esperEnabled() end, 3000, {
  H.call(function()
    H.writeWord(SUMMONED, H.readWord(SUMMONED) & ~H.readWord(MASK(terra)))
    H.writeByte(REFRESH + terra * 2, H.readByte(REFRESH + terra * 2) | 0x80)
  end),
  H.waitFrames(16),
}, "ddust: clearing $3f2e offers it again -- the latch is the cause") })

-- --------------------------- 4. Osmose actually charges 8 and pays back --
-- The boundary above prices it; this proves the price is charged and that the
-- spell is still what Shiva is FOR (net-positive against a pool).  The exact
-- charge is read off the caster's MP word as it is written: the first write is
-- CalcAttackEffect's subtract (mp0 - 8), the later one the drain credit.
add(driveIn("osmose", SHIVA, 30))
add({ H.call(function()
  for _, s in ipairs(GUARDS) do
    H.writeWord(MMPMX(s), 500)
    H.writeWord(MMP(s), 500)                    -- a pool worth stealing
    H.writeWord(MHP(s), 0x2000)
  end
  R.mp0 = H.readWord(CURMP(terra))
  R.gmp0 = H.readWord(MMP(GUARDS[1])) + H.readWord(MMP(GUARDS[2]))
  H.assertEq(R.mp0, 30, "[osmose] Terra entered the fight on 30 MP")
  H.assertEq(enabled(recOf(OSMOSE)), true, "[osmose] Osmose is castable on 30 MP")
end) })
add({ untilTerrasMenu("osmose") })
add({ H.call(freezeOthers) })               -- the shared-prop-buffer interleave again
add({ openMagicWindow("osmose") })
-- Put the cursor on Osmose: grid cell p is list record p+1 (record 0 is the
-- esper row), and get_magic_poi resolves (scroll + cursorY) * 2 + cursorX.
add({ H.driveUntil(function() return H.readByte(MSTATE) == ST_TARGET end, 900, {
  H.call(function()
    local p = recOf(OSMOSE) - 1
    H.writeByte(CURSOR_SCROLL + terra, p >> 1)
    H.writeByte(CURSOR_Y + terra, 0)
    H.writeByte(CURSOR_X + terra, p & 1)
    H.setPad({ "a" })
  end),
  H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(14),
}, "osmose: A on the Osmose cell asks for a target ($38)") })
add({ H.driveUntil(function() return sawSpell(OSMOSE) end, 4000,
  tap("a", 20), "osmose: Osmose ($29) reaches $3410") })
add({ H.waitFrames(180) })
add({ H.call(function()
  local mp1 = H.readWord(CURMP(terra))
  local gmp1 = H.readWord(MMP(GUARDS[1])) + H.readWord(MMP(GUARDS[2]))
  local seen = {}
  for _, v in ipairs(mpWrites) do seen[v] = true end
  H.log(string.format("[osmose] MP %d -> %d (writes seen: %s); guard MP %d -> %d",
    R.mp0, mp1, table.concat((function()
      local t = {}
      for _, v in ipairs(mpWrites) do t[#t + 1] = tostring(v) end
      return t
    end)(), ","), R.gmp0, gmp1))
  H.assertEq(seen[R.mp0 - OSMOSE_MP], true,
    "[osmose] the caster's MP was debited to exactly mp0-8 (the charge)")
  H.assertEq(gmp1 < R.gmp0, true, "[osmose] the target's MP pool actually dropped")
  H.assertEq(mp1 > R.mp0, true,
    "[osmose] and the caster ended NET POSITIVE -- 8 MP is still a refill")
  H.screenshot("magicite_osmose")
end) })

add({ H.call(function() H.log("[magicite] all scenarios passed") end) })

H.run({ maxFrames = 90000 }, all)
