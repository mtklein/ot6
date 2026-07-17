-- battle_class.lua -- M3 acceptance: weapon-class chip -> reveal -> break.
--
--   tools/tests/run.sh tools/tests/battle_class.lua
--
-- The doorstep guards are AUTHORED piercing-weak (Ot6ShieldTbl now carries
-- a class byte), so the seed itself is under test before any pokes. The
-- magitek party has no Fight command, so this borrows battle_hits's
-- driver: rewrite the live command lists to Fight-only and berserk the
-- party (RandCharAction -> Cmd_00 -> FightAttack, no menus). The class
-- read is the LIVE $3ca8 hand item, so poking a hand mid-battle swaps the
-- probe class without touching damage stats -- each phase re-arms the
-- party with a different weapon and watches the shield counter:
--
--   0. seed: shields 2/2, class-weak $02 (authored), revealed-class 0,
--      codex magic re-signed 'O7' (fresh init after self-clean)
--   1. slash phase (MithrilBlade $0a): swings land, nothing chips
--   2. pierce phase (Dirk $00): chip + reveal ($3ea9 bit $02) + class
--      codex byte learned
--   3. keep swinging: shields 0 -> broken timer
--   4. recovery: shields restore, revealed class SURVIVES
--   5. null-break phase (Fixed Dice $52 = class $88, guards re-poked
--      ¤-weak): swings land, nothing chips, nothing revealed
--   6. ¤ phase (Dice $51 = class $08): the chip fires
--   7. heal-reversal phase: slash-weak guards ABSORB fire, swings carry
--      fire (hand element poked) -- every hit resolves as a heal, and a
--      resolved heal must chip NOTHING (the $f2 bit-0 gate; per-frame HP
--      watcher proves heals actually landed, so the assert is not vacuous)
--   8. flagged-skill phase (TekMissile $8a, flags3 $20 "can't dodge"):
--      terra is un-berserked, her real commands restored, and her menu
--      driven to TekMissile -- a flags3-nonzero classed skill MUST chip a
--      pierce-weak guard (the whole-byte $f2 gate silently blocked every
--      such chip; this is the regression gate for the bit-0 narrowing)
--
-- Element weaknesses are zeroed on both guards at setup so the magitek
-- holder's stale beams (and poison DoT) can't move shields: every shield
-- transition below is the CLASS path or a bug.
--
-- Guesses pending a real run (marked GUESS below):
--   - GUESS(seed-2): guards still seed 2/2 with the extended 4-byte
--     records (battle_break asserts the same; if this fails the record
--     stride is wrong and everything after is noise)
--   - GUESS(swing-cadence): 1500 frames of berserk is assumed >= a few
--     swings for the no-chip phases; if the cadence is slower the
--     negative asserts pass vacuously (phase 2: eyeball the swing count)
--   - GUESS(dice): poking $3ca8 to dice ids swaps the CLASS lookup but
--     not the init-time special-effect bytes, so dice phases swing like
--     normal weapons here; real equipped-dice behavior (the dice damage
--     effect reaching the join hook) still wants a manual phase-2 look.
--
-- Entity map (same fight as battle_break): guards in monster slots 2/3
-- -> entities $0c/$0e. shields $3E44/$3E46 - timers $3E94/$3E96 -
-- revealed classes $3EA9/$3EAB - class weak $3EA8/$3EAA - weak elems
-- $3BEC/$3BEE - absorbed elems $3BD8/$3BDA - HP $3C00/$3C02. party
-- entities 0/2/4: right-hand item $3CA8/$3CAA/$3CAC, right-hand element
-- $3B90/$3B92/$3B94. species stash $57C4 (slot 2). class codex sram
-- $316190+species. live attack class byte $57B8 (logged, not asserted:
-- monster actions legitimately zero it).

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local function sram(addr) return emu.read(addr, emu.memType.snesMemory) end
local function shields() return H.readByte(0x3E44), H.readByte(0x3E46) end
local function timers() return H.readByte(0x3E94), H.readByte(0x3E96) end
local function classWeak() return H.readByte(0x3EA8), H.readByte(0x3EAA) end
local function classRev() return H.readByte(0x3EA9), H.readByte(0x3EAB) end

local function report(tag)
  return H.call(function()
    local s1, s2 = shields()
    local t1, t2 = timers()
    local w1, w2 = classWeak()
    local r1, r2 = classRev()
    H.log(string.format(
      "%s shields=%d,%d timers=%02X,%02X cweak=%02X,%02X crev=%02X,%02X " ..
      "atkclass=%02X hp=%04X,%04X",
      tag, s1, s2, t1, t2, w1, w2, r1, r2,
      H.readByte(0x57B8), H.readWord(0x3C00), H.readWord(0x3C02)))
  end)
end

-- arm every party right hand with one item id (class probe swap); left
-- hands stay untouched -- a single swing always picks the right hand
local function armRightHands(item)
  return H.call(function()
    for _, a in ipairs({ 0x3CA8, 0x3CAA, 0x3CAC }) do H.writeByte(a, item) end
    H.log(string.format("armed right hands with item %02x", item))
  end)
end

-- 5000 hp: a break window's x2 fights (~100/hit) can't wound a guard
-- between re-pokes; a wounded guard would never chip again (by design)
-- and starve the later phases
local function repokeHp()
  H.writeWord(0x3C00, 5000)
  H.writeWord(0x3C02, 5000)
end

-- one berserk-driven step: keep the guards alive, let time pass
local driveStep = {
  H.call(repokeHp),
  H.waitFrames(30),
}

-- party keepalive for the long late phases: top anyone low BEFORE the
-- wound bit can land (re-poking hp does not revive the dead)
local function pinParty()
  for c = 0, 2 do
    local a = 0x3BF4 + c * 2
    if H.readWord(a) < 100 then H.writeWord(a, 300) end
  end
end

local s1c, s2c -- shield snapshot for the no-chip phases
local terra    -- terra's party slot (char id 0)
local terraCmds, terraSt1 = {}, nil  -- her pre-lab commands + status 1

-- non-vacuity watcher: record every value the attack-class byte ($57b8)
-- is loaded with, so the no-chip phases can PROVE swings of the expected
-- class actually resolved while they ran
local classWrites, classRef = {}, nil
local function watchClasses(on)
  return H.call(function()
    if on then
      classWrites = {}
      classRef = emu.addMemoryCallback(function(addr, value)
        classWrites[value] = (classWrites[value] or 0) + 1
      end, emu.callbackType.write, 0x7E57B8, 0x7E57B8)
    else
      emu.removeMemoryCallback(classRef, emu.callbackType.write,
        0x7E57B8, 0x7E57B8)
      local parts = {}
      for v, n in pairs(classWrites) do
        parts[#parts + 1] = string.format("%02x:%d", v, n)
      end
      table.sort(parts)
      H.log("class byte writes seen: " .. table.concat(parts, " "))
    end
  end)
end

H.run({ maxFrames = 90000 }, {
  H.waitFrames(20),
  H.call(function()
    -- self-cleaning: invalidate the codex so this run proves the v2
    -- (elements + classes) init -> learn cycle from scratch
    emu.write(0x316000, 0, emu.memType.snesMemory)
    emu.write(0x316001, 0, emu.memType.snesMemory)
  end),
  H.loadState(STATE),
  H.waitFrames(10),

  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from doorstep"),
  H.waitUntil(function() return H.battleActive() end, 900,
    "battle active", 30),
  H.waitFrames(240),

  -- 0. seeding: authored shields AND the authored class row
  H.call(function()
    local s1, s2 = shields()
    H.assertEq(s1, 2, "guard 1 shields seeded")           -- GUESS(seed-2)
    H.assertEq(s2, 2, "guard 2 shields seeded")
    local w1, w2 = classWeak()
    H.assertEq(w1, 0x02, "guard 1 authored piercing-weak")
    H.assertEq(w2, 0x02, "guard 2 authored piercing-weak")
    local r1, r2 = classRev()
    H.assertEq(r1, 0, "guard 1 opens with no class revealed")
    H.assertEq(r2, 0, "guard 2 opens with no class revealed")
    H.assertEq(sram(0x316000), 0x4f, "codex magic 'O' after v2 re-init")
    H.assertEq(sram(0x316001), 0x37, "codex magic '7' after v2 re-init")
  end),
  report("seeded"),

  -- lab setup: no element chip possible, tough guards, berserk Fight.
  -- terra's real commands + status are saved first: phase 8 restores
  -- them to drive her menu to TekMissile.
  H.call(function()
    H.writeByte(0x3BEC, 0)                 -- guards lose their element
    H.writeByte(0x3BEE, 0)                 -- weaknesses: class only below
    repokeHp()
    for slot = 0, 3 do
      if H.readByte(0x3ED8 + slot * 2) == 0 then terra = slot end
    end
    H.assertEq(terra ~= nil, true, "terra found in the party")
    for i = 0, 3 do
      terraCmds[i] = H.readByte(0x202E + terra * 12 + i * 3)
    end
    terraSt1 = H.readByte(0x3EE4 + terra * 2)
    local holder = H.readByte(0x62CA)      -- slot with the open menu
    for slot = 0, 3 do                     -- entries are [cmd,d,d] x4
      H.writeByte(0x202E + slot * 12, 0x00)
      H.writeByte(0x2031 + slot * 12, 0xFF)
      H.writeByte(0x2034 + slot * 12, 0xFF)
      H.writeByte(0x2037 + slot * 12, 0xFF)
      local st2 = 0x3EE5 + slot * 2
      H.writeByte(st2, H.readByte(st2) | 0x10)          -- berserk
      if slot ~= holder then
        -- magitek status routes berserk to random beams; clear it so
        -- berserk picks Fight (the holder keeps replaying its stale
        -- staged beam -- battle_hits's C1-staging wart -- which is
        -- harmless here: beams have no class and no element weakness)
        local st1 = 0x3EE4 + slot * 2
        H.writeByte(st1, H.readByte(st1) & 0xF7)
      end
    end
    H.log(string.format("berserk fight party, terra slot %d, menu holder slot %d",
      terra, holder))
  end),

  -- 1. slash phase: wrong class, no chip
  armRightHands(0x0A),                     -- MithrilBlade: slashing
  H.call(function() s1c, s2c = shields() end),
  watchClasses(true),
  H.repeatN(50, driveStep),                -- 1500 berserk-fight frames
  watchClasses(false),
  report("slash-phase"),
  H.call(function()
    H.assertEq((classWrites[0x01] or 0) >= 1, true,
      "slashing swings actually resolved during the phase")
    local s1, s2 = shields()
    H.assertEq(s1, s1c, "slash swings never chip a pierce-weak guard")
    H.assertEq(s2, s2c, "slash swings never chip a pierce-weak guard (2)")
    local r1, r2 = classRev()
    H.assertEq(r1 | r2, 0, "and reveal nothing")
  end),

  -- 2. pierce phase: chip + reveal + codex
  armRightHands(0x00),                     -- Dirk: piercing
  H.driveUntil(function()
    local r1, r2 = classRev()
    return ((r1 | r2) & 0x02) == 0x02
  end, 15000, driveStep, "a piercing chip to reveal the class"),
  report("pierce-chip"),
  H.call(function()
    local s1, s2 = shields()
    H.assertEq(s1 < 2 or s2 < 2, true, "the revealing hit also chipped")
    local species = H.readWord(0x57C4)
    H.log(string.format("guard species=%d", species))
    H.assertEq(sram(0x316190 + species) & 0x02, 0x02,
      "class codex learned piercing")
  end),

  -- 3. keep swinging until a break
  H.driveUntil(function()
    local t1, t2 = timers()
    return t1 > 0 or t2 > 0
  end, 15000, driveStep, "a guard to break on class chip"),
  H.release(),
  report("broken"),
  H.call(function()
    local s1, s2 = shields()
    local t1, t2 = timers()
    local broke = (t1 > 0) and 1 or 2
    H.assertEq(broke == 1 and s1 or s2, 0, "broken guard shields at 0")
    H.screenshot("class_broken")
  end),

  -- 4. recovery: shields restore, the revealed class survives.
  -- (driveUntil, not waitUntil: the re-pokes must keep running or the
  -- x2 break window kills the guards and wound-dead monsters never
  -- chip again -- exactly what the first live run demonstrated)
  H.driveUntil(function()
    local t1, t2 = timers()
    local s1, s2 = shields()
    return t1 == 0 and t2 == 0 and (s1 == 2 or s2 == 2)
  end, 15000, driveStep, "broken guard to recover"),
  H.waitFrames(30),
  report("recovered"),
  H.call(function()
    local s1, s2 = shields()
    local r1, r2 = classRev()
    H.assertEq(s1 == 2 or s2 == 2, true, "shields restored to max")
    H.assertEq((r1 | r2) & 0x02, 0x02, "revealed class survives recovery")
  end),

  -- 5. null-break phase: ¤-weak guards, Fixed Dice teach nothing
  H.call(function()
    H.writeByte(0x3EA8, 0x08)              -- guards now ¤-weak only
    H.writeByte(0x3EAA, 0x08)
  end),
  armRightHands(0x52),                     -- Fixed Dice: ¤ + null-break
  H.call(function() s1c, s2c = shields() end),
  watchClasses(true),
  H.repeatN(50, driveStep),                -- 1500 berserk-fight frames
  watchClasses(false),
  report("nullbreak-phase"),
  H.call(function()                        -- GUESS(dice)
    H.assertEq((classWrites[0x88] or 0) >= 1, true,
      "null-break ¤ swings actually resolved during the phase")
    local s1, s2 = shields()
    H.assertEq(s1, s1c, "fixed dice never chip")
    H.assertEq(s2, s2c, "fixed dice never chip (2)")
    local r1, r2 = classRev()
    H.assertEq((r1 | r2) & 0x08, 0, "and never reveal ¤")
  end),

  -- 6. ¤ phase: ordinary dice chip the special class
  armRightHands(0x51),                     -- Dice: ¤, chips
  H.driveUntil(function()
    local r1, r2 = classRev()
    return ((r1 | r2) & 0x08) == 0x08
  end, 15000, driveStep, "a ¤ chip to reveal the class"),  -- GUESS(dice)
  report("special-chip"),
  H.call(function()
    local s1, s2 = shields()
    H.assertEq(s1 < s1c or s2 < s2c, true, "the ¤ reveal also chipped")
    H.screenshot("class_special")
  end),

  -- 7. heal-reversal phase: a hit that RESOLVES as a heal must not chip.
  -- slash-weak guards absorb fire; the right hands are slash blades whose
  -- pre-baked hand element ($3b90) is poked to fire. every landed swing
  -- heals the guard (CalcTargetDmg's absorb path flips $f2 bit 0) and the
  -- class gate must skip it. the per-frame HP watcher proves heals landed:
  -- a heal clamps the poked 5000 hp down to the guard's natural max.
  H.call(function()
    H.writeByte(0x3E44, 2); H.writeByte(0x3E46, 2)   -- stage shields clean
    H.writeByte(0x3E94, 0); H.writeByte(0x3E96, 0)   -- no timers running
    H.writeByte(0x3EA8, 0x01)              -- guards slash-weak
    H.writeByte(0x3EAA, 0x01)
    H.writeByte(0x3BD8, 0x01)              -- and fire-ABSORBING
    H.writeByte(0x3BDA, 0x01)
    for _, a in ipairs({ 0x3B90, 0x3B92, 0x3B94 }) do
      H.writeByte(a, 0x01)                 -- right-hand element: fire
    end
    repokeHp()
    H.vars.healSeen = false
    H.log("heal-reversal lab: slash-weak fire-absorbing guards, fire slashes")
  end),
  armRightHands(0x0A),                     -- MithrilBlade: slashing
  H.call(function() s1c, s2c = shields() end),
  watchClasses(true),
  H.repeatN(1500, {
    H.call(function()
      pinParty()
      for _, a in ipairs({ 0x3C00, 0x3C02 }) do
        local hp = H.readWord(a)
        if hp ~= 5000 then
          -- a heal clamps 5000 down to natural max (tiny); a stray
          -- damage hit only nibbles. either way, re-pin.
          if hp < 1000 or hp > 5000 then H.vars.healSeen = true end
          H.writeWord(a, 5000)
        end
      end
    end),
    H.waitFrames(1),
  }),
  watchClasses(false),
  report("heal-reversal"),
  H.call(function()
    H.assertEq((classWrites[0x01] or 0) >= 1, true,
      "slashing swings actually resolved during the phase")
    H.assertEq(H.vars.healSeen, true,
      "at least one swing resolved as a heal (absorb reversal ran)")
    local s1, s2 = shields()
    H.assertEq(s1, s1c, "healing hits never chip a slash-weak guard")
    H.assertEq(s2, s2c, "healing hits never chip a slash-weak guard (2)")
    local r1, r2 = classRev()
    H.assertEq((r1 | r2) & 0x01, 0, "and reveal nothing")
  end),

  -- 8. flagged-skill phase: TekMissile (flags3 $20) must chip. restore
  -- the lab to pierce-weak, hand terra her real menu back, and walk it:
  -- MagiTek -> down x3, right (her 2x4 grid's bottom-right cell) -> fire
  -- at the default target. the drive retries the lap until the skill
  -- loader's $02 lands and a shield moves.
  H.call(function()
    H.writeByte(0x3EA8, 0x02); H.writeByte(0x3EAA, 0x02)  -- pierce-weak
    H.writeByte(0x3BD8, 0); H.writeByte(0x3BDA, 0)        -- absorb off
    H.writeByte(0x3E44, 2); H.writeByte(0x3E46, 2)        -- shields staged
    H.writeByte(0x3E94, 0); H.writeByte(0x3E96, 0)
    repokeHp()
    for i = 0, 3 do
      H.writeByte(0x202E + terra * 12 + i * 3, terraCmds[i])
    end
    H.writeByte(0x3EE4 + terra * 2, terraSt1)             -- magitek back
    local st2 = 0x3EE5 + terra * 2
    H.writeByte(st2, H.readByte(st2) & 0xEF)              -- un-berserk
    H.vars.tplan, H.vars.tpf = nil, 1
    H.log("tek lab: terra's menu restored; berserkers keep slashing air")
  end),
  watchClasses(true),
  H.driveUntil(function()
    local s1, s2 = shields()
    return s1 < 2 or s2 < 2
  end, 25000, {
    H.call(function()
      repokeHp()
      pinParty()
      local menu = H.readByte(0x7bca)
      if menu == 0 or H.readByte(0x62CA) ~= terra then
        H.vars.tplan = nil
        H.setPad({})
        return
      end
      local p = H.vars.tplan
      if p == nil or H.vars.tpf > #p then
        p = {}
        local function tap(btn, on, off)
          for _ = 1, on do p[#p + 1] = { btn } end
          for _ = 1, off do p[#p + 1] = {} end
        end
        tap("b", 6, 16); tap("b", 6, 16)   -- converge to the root menu
        tap("a", 6, 40)                    -- MagiTek -> list (long settle:
                                           --   input during window-open
                                           --   wedges the staged rows)
        for _ = 1, 3 do tap("down", 6, 16) end
        tap("right", 6, 16)                -- bottom-right: TekMissile
        tap("a", 6, 20)                    -- pick the cell
        tap("a", 6, 60)                    -- confirm the default target
        for _ = 1, 90 do p[#p + 1] = {} end
        H.vars.tplan, H.vars.tpf = p, 1
      end
      H.setPad(p[H.vars.tpf])
      H.vars.tpf = H.vars.tpf + 1
    end),
  }, "a TekMissile chip moves a guard's shields"),
  H.call(function() H.setPad({}) end),
  H.waitFrames(30),
  watchClasses(false),
  report("tek-chip"),
  H.call(function()
    H.assertEq((classWrites[0x02] or 0) >= 1, true,
      "a piercing skill load resolved -- with slash blades in every hand, " ..
      "only TekMissile ($8a) stores $02")
    local s1, s2 = shields()
    H.assertEq(s1 < 2 or s2 < 2, true,
      "the flags3-$20 skill chipped a pierce-weak guard")
    local species = H.readWord(0x57C4)
    H.assertEq(sram(0x316190 + species) & 0x02, 0x02,
      "class codex holds piercing after the skill chip")
    H.screenshot("class_tek")
  end),
})
